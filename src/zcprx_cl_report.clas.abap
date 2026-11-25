CLASS zcprx_cl_report DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING io_praxedo TYPE REF TO zcprx_if_praxedo_api OPTIONAL
                io_srvord  TYPE REF TO zcprx_if_srvord_api  OPTIONAL.

    "! Bericht holen und an den Serviceauftrag anhängen (idempotent über den Dateinamen)
    METHODS attach
      IMPORTING iv_order_uuid TYPE sysuuid_x16
      RAISING   zcprx_cx_error.

    "! Job: offene (und optional fehlerhafte) Berichte anhängen
    METHODS attach_open
      IMPORTING io_log          TYPE REF TO zcprx_cl_log
                iv_max          TYPE i
                iv_with_errors  TYPE abap_bool
      RETURNING VALUE(rv_count) TYPE i.

    "! Job: Einsätze ohne fälligen Bericht bei Praxedo nachprüfen (Status VALIDATED?)
    METHODS check_pending
      IMPORTING io_log          TYPE REF TO zcprx_cl_log
                iv_days         TYPE i
                iv_max          TYPE i
      RETURNING VALUE(rv_count) TYPE i.

    "! Praxedo_<Code>.pdf, unzulässige Zeichen -> _
    CLASS-METHODS file_name
      IMPORTING iv_code        TYPE csequence
      RETURNING VALUE(rv_name) TYPE string.

    CLASS-METHODS is_report_status
      IMPORTING iv_status        TYPE csequence
      RETURNING VALUE(rv_result) TYPE abap_bool.

  PRIVATE SECTION.
    DATA mo_praxedo TYPE REF TO zcprx_if_praxedo_api.
    DATA mo_srvord  TYPE REF TO zcprx_if_srvord_api.

    METHODS set_result
      IMPORTING iv_order_uuid TYPE sysuuid_x16
                iv_status     TYPE csequence
                iv_message    TYPE csequence
                iv_uuid       TYPE csequence OPTIONAL.
ENDCLASS.

CLASS zcprx_cl_report IMPLEMENTATION.

  METHOD constructor.
    mo_praxedo = COND #( WHEN io_praxedo IS BOUND THEN io_praxedo ELSE NEW zcprx_cl_praxedo_api( ) ).
    mo_srvord  = COND #( WHEN io_srvord  IS BOUND THEN io_srvord  ELSE NEW zcprx_cl_srvord_api( ) ).
  ENDMETHOD.

  METHOD attach.
    DATA(rs) = zcprx_if_constants=>report_status.
    DATA lv_uuid TYPE string.

    SELECT SINGLE ServiceOrder, PraxedoId, PraxedoUUID, PraxedoStatus
      FROM zcprx_r_order
      WHERE OrderUUID = @iv_order_uuid
      INTO @DATA(ls_order).
    IF sy-subrc <> 0.
      zcprx_cx_error=>raise( iv_text = |Einsatz { iv_order_uuid } nicht gefunden| iv_permanent = abap_true ).
    ENDIF.

    TRY.
        IF ls_order-PraxedoId IS INITIAL OR ls_order-ServiceOrder IS INITIAL.
          zcprx_cx_error=>raise( iv_text = 'Einsatz ohne Praxedo-Code oder Serviceauftrag' iv_permanent = abap_true ).
        ENDIF.
        IF is_report_status( ls_order-PraxedoStatus ) = abap_false.
          zcprx_cx_error=>raise(
            iv_text      = |Bericht erst bei Praxedo-Status { zcprx_cl_config=>get( zcprx_cl_config=>c_param-report_statuses ) } (aktuell { ls_order-PraxedoStatus })|
            iv_permanent = abap_true ).
        ENDIF.

        " UUID fehlt (z. B. alter Einsatz) -> Einsatz neu lesen
        lv_uuid = ls_order-PraxedoUUID.
        IF lv_uuid IS INITIAL.
          lv_uuid = mo_praxedo->get_order( CONV #( ls_order-PraxedoId ) )-uuid.
        ENDIF.

        DATA(lv_file) = file_name( ls_order-PraxedoId ).
        IF mo_srvord->has_attachment( iv_service_order = ls_order-ServiceOrder iv_file_name = lv_file ) = abap_true.
          set_result( iv_order_uuid = iv_order_uuid iv_status = rs-attached
                      iv_message    = |{ lv_file } bereits vorhanden| iv_uuid = lv_uuid ).
          RETURN.
        ENDIF.

        DATA(lv_pdf) = mo_praxedo->get_report_pdf( iv_uuid = lv_uuid iv_code = CONV #( ls_order-PraxedoId ) ).
        mo_srvord->add_attachment( iv_service_order = ls_order-ServiceOrder
                                   iv_file_name     = lv_file
                                   iv_mime_type     = `application/pdf`
                                   iv_content       = lv_pdf ).
        set_result( iv_order_uuid = iv_order_uuid iv_status = rs-attached iv_message = lv_file iv_uuid = lv_uuid ).

      CATCH zcprx_cx_error INTO DATA(lx_error).
        set_result( iv_order_uuid = iv_order_uuid iv_status = rs-error iv_message = lx_error->get_text( ) iv_uuid = lv_uuid ).
        RAISE EXCEPTION lx_error.
    ENDTRY.
  ENDMETHOD.

  METHOD attach_open.
    DATA(rs) = zcprx_if_constants=>report_status.
    DATA lr_status TYPE RANGE OF zcprxord-report_status.
    lr_status = VALUE #( ( sign = 'I' option = 'EQ' low = rs-open ) ).
    IF iv_with_errors = abap_true.
      APPEND VALUE #( sign = 'I' option = 'EQ' low = rs-error ) TO lr_status.
    ENDIF.

    SELECT OrderUUID, PraxedoId FROM zcprx_r_order
      WHERE ReportStatus IN @lr_status
      ORDER BY LastChangedAt
      INTO TABLE @DATA(lt_order)
      UP TO @iv_max ROWS.

    LOOP AT lt_order INTO DATA(ls_order).
      TRY.
          attach( ls_order-OrderUUID ).
          rv_count += 1.
        CATCH zcprx_cx_error INTO DATA(lx_error).
          io_log->error( |Bericht { ls_order-PraxedoId }: { lx_error->get_text( ) }| ).
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_pending.
    DATA(st) = zcprx_if_constants=>order_status.
    DATA lv_now   TYPE timestampl.
    DATA lv_limit TYPE timestampl.
    GET TIME STAMP FIELD lv_now.
    TRY.
        lv_limit = cl_abap_tstmp=>subtractsecs( tstmp = lv_now secs = iv_days * 86400 ).
      CATCH cx_parameter_invalid_range cx_parameter_invalid_type.
        CLEAR lv_limit.
    ENDTRY.

    " gesendet/rückgemeldet/verbucht, Bericht noch nicht fällig
    SELECT OrderUUID, PraxedoId FROM zcprx_r_order
      WHERE PraxedoId    <> ''
        AND ReportStatus  = ''
        AND ( Status = @st-sent OR Status = @st-received OR Status = @st-processed )
        AND LastChangedAt >= @lv_limit
      ORDER BY LastChangedAt
      INTO TABLE @DATA(lt_order)
      UP TO @iv_max ROWS.

    DATA(lo_inbound) = NEW zcprx_cl_inbound( mo_praxedo ).
    LOOP AT lt_order INTO DATA(ls_order).
      TRY.
          lo_inbound->fetch_order( ls_order-OrderUUID ).
          rv_count += 1.
        CATCH zcprx_cx_error INTO DATA(lx_error).
          io_log->warning( |Nachprüfung { ls_order-PraxedoId }: { lx_error->get_text( ) }| ).
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

  METHOD file_name.
    rv_name = |Praxedo_{ condense( CONV string( iv_code ) ) }.pdf|.
    rv_name = replace( val = rv_name pcre = `[\\/:*?"<>|\s]` with = `_` occ = 0 ).
  ENDMETHOD.

  METHOD is_report_status.
    DATA(lt_status) = zcprx_cl_config=>get_list( zcprx_cl_config=>c_param-report_statuses ).
    IF lt_status IS INITIAL.
      lt_status = VALUE #( ( `VALIDATED` ) ).
    ENDIF.
    rv_result = xsdbool( iv_status IS NOT INITIAL
                     AND line_exists( lt_status[ table_line = to_upper( condense( CONV string( iv_status ) ) ) ] ) ).
  ENDMETHOD.

  METHOD set_result.
    MODIFY ENTITIES OF zcprx_r_order
      ENTITY Order EXECUTE setReportResult
      FROM VALUE #( ( OrderUUID = iv_order_uuid
                      %param    = VALUE #( ReportStatus  = iv_status
                                           ReportMessage = iv_message
                                           PraxedoUUID   = iv_uuid ) ) )
      FAILED DATA(ls_failed) ##NEEDED.
    COMMIT ENTITIES.
  ENDMETHOD.

ENDCLASS.

