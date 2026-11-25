CLASS zcprx_cl_queue DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_entry,
        object_type TYPE c LENGTH 10,
        object_key  TYPE c LENGTH 40,
        operation   TYPE c LENGTH 10,
      END OF ty_entry,
      tt_entry TYPE STANDARD TABLE OF ty_entry WITH EMPTY KEY,
      tt_uuid  TYPE STANDARD TABLE OF sysuuid_x16 WITH EMPTY KEY.

    CLASS-METHODS enqueue
      IMPORTING it_entries    TYPE tt_entry
                iv_start_bgpf TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(rt_ids) TYPE tt_uuid.

    CLASS-METHODS start_background
      IMPORTING it_ids TYPE tt_uuid.

    CLASS-METHODS to_uuid
      IMPORTING iv_key         TYPE csequence
      RETURNING VALUE(rv_uuid) TYPE sysuuid_x16
      RAISING   zcprx_cx_error.

    "! Wartezeit vor dem n-ten Retry in Sekunden (exponentiell, gedeckelt)
    CLASS-METHODS calc_backoff_seconds
      IMPORTING iv_retry          TYPE i
                iv_base_min       TYPE i
                iv_max_min        TYPE i
      RETURNING VALUE(rv_seconds) TYPE i.

    METHODS process
      IMPORTING it_ids         TYPE tt_uuid OPTIONAL
                io_log         TYPE REF TO zcprx_cl_log OPTIONAL
                iv_max_entries TYPE i DEFAULT 1000.

    "! Hängende RUNNING-Einträge zurücksetzen (nur Job)
    METHODS reset_stale
      IMPORTING io_log          TYPE REF TO zcprx_cl_log
      RETURNING VALUE(rv_count) TYPE i.

  PRIVATE SECTION.
    METHODS claim
      CHANGING  cs_queue         TYPE zcprxque
      RETURNING VALUE(rv_result) TYPE abap_bool.

    METHODS dispatch
      IMPORTING is_queue TYPE zcprxque
      RAISING   zcprx_cx_error.

    CLASS-METHODS now
      RETURNING VALUE(rv_now) TYPE timestampl.
ENDCLASS.

CLASS zcprx_cl_queue IMPLEMENTATION.

  METHOD enqueue.
    DATA lt_db TYPE STANDARD TABLE OF zcprxque WITH EMPTY KEY.
    DATA(lv_now) = now( ).

    DATA(lt_entries) = it_entries.
    SORT lt_entries BY object_type object_key operation.
    DELETE ADJACENT DUPLICATES FROM lt_entries COMPARING object_type object_key operation.
    CHECK lt_entries IS NOT INITIAL.

    " bereits offene, noch nicht begonnene Einträge wiederverwenden
    SELECT queue_uuid, object_type, object_key, operation FROM zcprxque
      FOR ALL ENTRIES IN @lt_entries
      WHERE object_type = @lt_entries-object_type
        AND object_key  = @lt_entries-object_key
        AND operation   = @lt_entries-operation
        AND status      = @zcprx_if_constants=>queue_status-new
      INTO TABLE @DATA(lt_open).

    LOOP AT lt_entries INTO DATA(ls_entry).
      READ TABLE lt_open INTO DATA(ls_open) WITH KEY object_type = ls_entry-object_type
                                                     object_key  = ls_entry-object_key
                                                     operation   = ls_entry-operation.
      IF sy-subrc = 0.
        APPEND ls_open-queue_uuid TO rt_ids.
        CONTINUE.
      ENDIF.
      TRY.
          DATA(lv_uuid) = cl_system_uuid=>create_uuid_x16_static( ).
        CATCH cx_uuid_error.
          CONTINUE.
      ENDTRY.
      APPEND VALUE #( queue_uuid            = lv_uuid
                      object_type           = ls_entry-object_type
                      object_key            = ls_entry-object_key
                      operation             = ls_entry-operation
                      status                = zcprx_if_constants=>queue_status-new
                      created_at            = lv_now
                      last_changed_at       = lv_now
                      local_last_changed_at = lv_now ) TO lt_db.
      APPEND lv_uuid TO rt_ids.
    ENDLOOP.

    IF lt_db IS NOT INITIAL.
      INSERT zcprxque FROM TABLE @lt_db.
    ENDIF.

    IF iv_start_bgpf = abap_true.
      start_background( rt_ids ).
    ENDIF.
  ENDMETHOD.

  METHOD start_background.
    CHECK it_ids IS NOT INITIAL.
    TRY.
        DATA(lo_process) = cl_bgmc_process_factory=>get_default( )->create( ).
        lo_process->set_name( 'CPRX Praxedo Queue' ).
        lo_process->set_operation_tx_uncontrolled( NEW zcprx_cl_bgpf_queue( it_ids ) ).
        lo_process->save_for_execution( ).
      CATCH cx_bgmc ##NO_HANDLER.
        " Kein Abbruch: Einträge bleiben NEW und werden vom Job
        " ZCPRX_JT_OUTBOUND verarbeitet.
    ENDTRY.
  ENDMETHOD.

  METHOD to_uuid.
    DATA(lv_key) = condense( CONV string( iv_key ) ).
    IF strlen( lv_key ) <> 32.
      zcprx_cx_error=>raise( iv_text = |Ungültiger Schlüssel { lv_key }| iv_permanent = abap_true ).
    ENDIF.
    TRY.
        rv_uuid = CONV sysuuid_x16( lv_key ).
      CATCH cx_sy_conversion_error INTO DATA(lx_conv).
        zcprx_cx_error=>raise( iv_text = |Ungültiger Schlüssel { lv_key }| iv_permanent = abap_true ix_previous = lx_conv ).
    ENDTRY.
  ENDMETHOD.

  METHOD calc_backoff_seconds.
    " Retry 1 -> base, 2 -> 2*base, 3 -> 4*base ... gedeckelt auf max
    DATA(lv_factor)  = ipow( base = 2 exp = nmax( val1 = iv_retry - 1 val2 = 0 ) ).
    DATA(lv_minutes) = nmin( val1 = iv_base_min * lv_factor val2 = iv_max_min ).
    rv_seconds = nmax( val1 = lv_minutes val2 = 1 ) * 60.
  ENDMETHOD.

  METHOD now.
    GET TIME STAMP FIELD rv_now.
  ENDMETHOD.

  METHOD reset_stale.
    DATA(lv_timeout) = zcprx_cl_config=>get_int( iv_param = zcprx_cl_config=>c_param-running_timeout_min
                                                     iv_min   = 5 ).
    DATA lv_limit TYPE timestampl.
    TRY.
        lv_limit = cl_abap_tstmp=>subtractsecs( tstmp = now( ) secs = lv_timeout * 60 ).
      CATCH cx_parameter_invalid_range cx_parameter_invalid_type.
        RETURN.
    ENDTRY.

    UPDATE zcprxque
      SET status       = @zcprx_if_constants=>queue_status-error,
          retry_count  = retry_count + 1,
          message_text = 'Abgebrochen (Timeout) – wird erneut versucht'
      WHERE status     = @zcprx_if_constants=>queue_status-running
        AND started_at < @lv_limit.
    rv_count = sy-dbcnt.
    COMMIT WORK.
    IF rv_count > 0.
      io_log->warning( |{ rv_count } hängende Queue-Einträge auf ERROR zurückgesetzt| ).
    ENDIF.
  ENDMETHOD.

  METHOD claim.
    " Bedingtes UPDATE: nur wenn der Status seit dem Lesen unverändert ist
    DATA(lv_old_status) = cs_queue-status.
    cs_queue-status     = zcprx_if_constants=>queue_status-running.
    cs_queue-started_at = now( ).

    UPDATE zcprxque
      SET status     = @cs_queue-status,
          started_at = @cs_queue-started_at
      WHERE queue_uuid = @cs_queue-queue_uuid
        AND status     = @lv_old_status.
    rv_result = xsdbool( sy-dbcnt = 1 ).
    COMMIT WORK.
  ENDMETHOD.

  METHOD process.
    DATA lt_queue TYPE STANDARD TABLE OF zcprxque WITH EMPTY KEY.
    DATA(qs)          = zcprx_if_constants=>queue_status.
    DATA(lv_max_retr) = zcprx_cl_config=>get_int( iv_param = zcprx_cl_config=>c_param-max_retries iv_min = 1 ).
    DATA(lv_base_min) = zcprx_cl_config=>get_int( iv_param = zcprx_cl_config=>c_param-retry_base_min iv_min = 1 ).
    DATA(lv_max_min)  = zcprx_cl_config=>get_int( iv_param = zcprx_cl_config=>c_param-retry_max_min iv_min = 1 ).
    DATA(lv_now)      = now( ).

    DATA(lo_log) = io_log.
    IF lo_log IS NOT BOUND.
      lo_log = zcprx_cl_log=>create( zcprx_if_constants=>log-sub_queue ).
    ENDIF.

    IF it_ids IS NOT INITIAL.
      " gezielt (bgPF / manueller Retry): nur nicht begonnene Einträge
      SELECT * FROM zcprxque
        FOR ALL ENTRIES IN @it_ids
        WHERE queue_uuid = @it_ids-table_line
          AND status     = @qs-new
        INTO TABLE @lt_queue.
    ELSE.
      " Job: alle neuen + fälligen Retries
      SELECT * FROM zcprxque
        WHERE status = @qs-new
           OR ( status        = @qs-error
            AND retry_count   < @lv_max_retr
            AND next_retry_at <= @lv_now )
        ORDER BY created_at
        INTO TABLE @lt_queue
        UP TO @iv_max_entries ROWS.
    ENDIF.
    SORT lt_queue BY created_at.

    LOOP AT lt_queue ASSIGNING FIELD-SYMBOL(<ls_queue>).
      IF claim( CHANGING cs_queue = <ls_queue> ) = abap_false.
        CONTINUE.                                 " von anderem Prozess übernommen
      ENDIF.

      DATA(lv_label) = |{ <ls_queue>-object_type } { <ls_queue>-operation } { <ls_queue>-object_key }|.
      TRY.
          dispatch( <ls_queue> ).
          <ls_queue>-status = qs-done.
          CLEAR: <ls_queue>-message_text, <ls_queue>-next_retry_at.
          lo_log->success( |{ lv_label }: OK| ).

        CATCH zcprx_cx_error INTO DATA(lx_error).
          <ls_queue>-status       = qs-error.
          <ls_queue>-message_text = lx_error->get_text( ).
          <ls_queue>-retry_count  = COND #( WHEN lx_error->mv_permanent = abap_true THEN lv_max_retr
                                            ELSE <ls_queue>-retry_count + 1 ).
        CATCH cx_root INTO DATA(lx_root).
          <ls_queue>-status       = qs-error.
          <ls_queue>-message_text = lx_root->get_text( ).
          <ls_queue>-retry_count += 1.
      ENDTRY.

      IF <ls_queue>-status = qs-error.
        IF <ls_queue>-retry_count >= lv_max_retr.
          " endgültig -> Error im Log (löst Alert-Mail aus)
          lo_log->error( |ENDGÜLTIG { lv_label }: { <ls_queue>-message_text }| ).
          CLEAR <ls_queue>-next_retry_at.
        ELSE.
          DATA(lv_wait) = calc_backoff_seconds( iv_retry    = <ls_queue>-retry_count
                                                iv_base_min = lv_base_min
                                                iv_max_min  = lv_max_min ).
          TRY.
              <ls_queue>-next_retry_at = cl_abap_tstmp=>add( tstmp = now( ) secs = lv_wait ).
            CATCH cx_parameter_invalid_range cx_parameter_invalid_type.
              <ls_queue>-next_retry_at = now( ).
          ENDTRY.
          lo_log->warning( |Retry { <ls_queue>-retry_count }/{ lv_max_retr } in { lv_wait / 60 } Min – { lv_label }: { <ls_queue>-message_text }| ).
        ENDIF.
      ENDIF.

      <ls_queue>-processed_at          = now( ).
      <ls_queue>-last_changed_at       = <ls_queue>-processed_at.
      <ls_queue>-local_last_changed_at = <ls_queue>-processed_at.
      UPDATE zcprxque FROM @<ls_queue>.
      COMMIT WORK.
    ENDLOOP.

    IF io_log IS NOT BOUND.
      " Kontext bgPF (kein Job): Log speichern und endgültige Fehler direkt melden
      lo_log->save( ).
      IF lo_log->has_errors( ).
        NEW zcprx_cl_alert( )->send(
          iv_key     = 'QUEUE'
          iv_subject = 'Verarbeitung endgültig fehlgeschlagen'
          it_errors  = lo_log->get_errors( ) ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD dispatch.
    DATA(ot) = zcprx_if_constants=>object_type.
    DATA(op) = zcprx_if_constants=>operation.

    CASE is_queue-object_type.
      WHEN ot-order.
        CASE is_queue-operation.
          WHEN op-upsert.
            NEW zcprx_cl_outbound( )->sync_order( to_uuid( is_queue-object_key ) ).
          WHEN op-delete.
            NEW zcprx_cl_outbound( )->delete_order( CONV #( is_queue-object_key ) ).
          WHEN op-fetch.
            NEW zcprx_cl_inbound( )->fetch_order( to_uuid( is_queue-object_key ) ).
          WHEN op-post.
            NEW zcprx_cl_posting( )->post_order( to_uuid( is_queue-object_key ) ).
          WHEN op-report.
            NEW zcprx_cl_report( )->attach( to_uuid( is_queue-object_key ) ).
          WHEN OTHERS.
            zcprx_cx_error=>raise( iv_text = |Unbekannte Operation { is_queue-operation }| iv_permanent = abap_true ).
        ENDCASE.

      WHEN ot-service_order.
        NEW zcprx_cl_outbound( )->sync_service_order( CONV #( is_queue-object_key ) ).

      WHEN ot-product.
        NEW zcprx_cl_masterdata( )->send_products( it_keys = VALUE #( ( CONV #( is_queue-object_key ) ) ) ).

      WHEN ot-product_group.
        NEW zcprx_cl_masterdata( )->send_product_groups( it_keys = VALUE #( ( CONV #( is_queue-object_key ) ) ) ).

      WHEN ot-equipment_type.
        NEW zcprx_cl_masterdata( )->send_equipment_types( it_keys = VALUE #( ( CONV #( is_queue-object_key ) ) ) ).

      WHEN OTHERS.
        zcprx_cx_error=>raise( iv_text = |Unbekannter Objekttyp { is_queue-object_type }| iv_permanent = abap_true ).
    ENDCASE.
  ENDMETHOD.

ENDCLASS.

