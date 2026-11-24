CLASS zcprx_cl_job_outbound DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcprx_cl_job_base.
  PROTECTED SECTION.
    METHODS get_subobject     REDEFINITION.
    METHODS run               REDEFINITION.
    METHODS define_parameters REDEFINITION.
    METHODS default_values    REDEFINITION.
ENDCLASS.

CLASS zcprx_cl_job_outbound IMPLEMENTATION.

  METHOD get_subobject.
    rv_subobject = zcprx_if_constants=>log-sub_out.
  ENDMETHOD.

  METHOD define_parameters.
    rt_definition = VALUE #(
      ( selname = 'P_DELTA' kind = if_apj_dt_exec_object=>parameter datatype = 'C' length = 1
        param_text = 'Geänderte Serviceaufträge lesen (X)' changeable_ind = abap_true )
      ( selname = 'P_MAXQ'  kind = if_apj_dt_exec_object=>parameter datatype = 'N' length = 6
        param_text = 'Max. Queue-Einträge je Lauf' changeable_ind = abap_true ) ).
  ENDMETHOD.

  METHOD default_values.
    rt_values = VALUE #(
      ( selname = 'P_DELTA' kind = if_apj_dt_exec_object=>parameter sign = 'I' option = 'EQ' low = 'X' )
      ( selname = 'P_MAXQ'  kind = if_apj_dt_exec_object=>parameter sign = 'I' option = 'EQ' low = '001000' ) ).
  ENDMETHOD.

  METHOD run.
    DATA lt_entries TYPE zcprx_cl_queue=>tt_entry.

    IF param( it_parameters = it_parameters iv_name = 'P_DELTA' ) = 'X'.
      DATA(lv_now)   = utclong_current( ).
      DATA(lv_since) = zcprx_cl_mapper=>from_iso(
                         zcprx_cl_config=>get( zcprx_cl_config=>c_param-last_delta_ts ) ).
      IF lv_since IS INITIAL.
        lv_since = utclong_add( val = lv_now days = -1 ).
      ENDIF.

      DATA(lt_ids) = NEW zcprx_cl_srvord_api( )->zcprx_if_srvord_api~get_changed_service_orders( lv_since ).
      lt_entries = VALUE #( FOR id IN lt_ids ( object_type = zcprx_if_constants=>object_type-service_order
                                               operation   = zcprx_if_constants=>operation-upsert
                                               object_key  = id ) ).
      IF lt_entries IS NOT INITIAL.
        zcprx_cl_queue=>enqueue( it_entries = lt_entries iv_start_bgpf = abap_false ).
      ENDIF.
      zcprx_cl_config=>set( iv_param = zcprx_cl_config=>c_param-last_delta_ts
                                iv_value = zcprx_cl_mapper=>to_iso( lv_now ) ).
      COMMIT WORK.
      mo_log->info( |{ lines( lt_ids ) } geänderte Serviceaufträge seit { zcprx_cl_mapper=>to_iso( lv_since ) }| ).
    ENDIF.

    DATA(lv_max)   = CONV i( param( it_parameters = it_parameters iv_name = 'P_MAXQ' ) ).
    DATA(lo_queue) = NEW zcprx_cl_queue( ).
    " abgebrochene Verarbeitungen (z. B. Systemneustart) wieder freigeben
    lo_queue->reset_stale( mo_log ).
    lo_queue->process( io_log         = mo_log
                       iv_max_entries = COND #( WHEN lv_max > 0 THEN lv_max ELSE 1000 ) ).
  ENDMETHOD.

ENDCLASS.
