CLASS zcprx_cl_alert DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CONSTANTS c_max_lines TYPE i VALUE 50.

    "! Fehler-Alert (gebündelt, gedrosselt)
    "! @parameter rv_sent | X = Mail versendet
    METHODS send
      IMPORTING iv_key         TYPE csequence
                iv_subject     TYPE csequence
                it_errors      TYPE zcprx_cl_log=>tt_text
                iv_force       TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(rv_sent) TYPE abap_bool.

    "! Informationsmail ohne Drosselung (z. B. Installationsergebnis)
    METHODS send_info
      IMPORTING iv_subject     TYPE csequence
                it_lines       TYPE zcprx_cl_log=>tt_text
      RETURNING VALUE(rv_sent) TYPE abap_bool.

    "! Empfänger gepflegt und Alerting aktiv?
    METHODS is_configured
      RETURNING VALUE(rv_result) TYPE abap_bool.

  PRIVATE SECTION.
    METHODS is_throttled
      IMPORTING iv_key           TYPE csequence
      RETURNING VALUE(rv_result) TYPE abap_bool.

    METHODS remember_sent
      IMPORTING iv_key TYPE csequence.

    METHODS deliver
      IMPORTING iv_subject     TYPE csequence
                iv_html        TYPE string
      RETURNING VALUE(rv_sent) TYPE abap_bool.

    METHODS build_html
      IMPORTING iv_title       TYPE csequence
                it_lines       TYPE zcprx_cl_log=>tt_text
                iv_is_error    TYPE abap_bool
      RETURNING VALUE(rv_html) TYPE string.

    METHODS system_name
      RETURNING VALUE(rv_name) TYPE string.

    METHODS html_escape
      IMPORTING iv_value        TYPE csequence
      RETURNING VALUE(rv_value) TYPE string.
ENDCLASS.

CLASS zcprx_cl_alert IMPLEMENTATION.

  METHOD send.
    CHECK is_configured( ) = abap_true.
    CHECK it_errors IS NOT INITIAL.

    IF iv_force = abap_false AND is_throttled( iv_key ) = abap_true.
      RETURN.                                   " innerhalb Drosselfenster
    ENDIF.

    rv_sent = deliver(
      iv_subject = |[Praxedo-Adapter] { iv_subject } – { lines( it_errors ) } Fehler ({ system_name( ) })|
      iv_html    = build_html( iv_title    = iv_subject
                               it_lines    = it_errors
                               iv_is_error = abap_true ) ).

    IF rv_sent = abap_true.
      remember_sent( iv_key ).
    ENDIF.
  ENDMETHOD.

  METHOD send_info.
    CHECK is_configured( ) = abap_true.
    rv_sent = deliver(
      iv_subject = |[Praxedo-Adapter] { iv_subject } ({ system_name( ) })|
      iv_html    = build_html( iv_title    = iv_subject
                               it_lines    = it_lines
                               iv_is_error = abap_false ) ).
  ENDMETHOD.

  METHOD is_configured.
    rv_result = xsdbool( zcprx_cl_config=>get( zcprx_cl_config=>c_param-alert_active ) = 'X'
                     AND zcprx_cl_config=>get_list( zcprx_cl_config=>c_param-alert_recipients ) IS NOT INITIAL
                     AND zcprx_cl_config=>get( zcprx_cl_config=>c_param-alert_sender ) IS NOT INITIAL ).
  ENDMETHOD.

  METHOD is_throttled.
    DATA lv_last TYPE timestampl.
    DATA lv_now  TYPE timestampl.

    DATA(lv_minutes) = zcprx_cl_config=>get_int( zcprx_cl_config=>c_param-alert_throttle_min ).
    CHECK lv_minutes > 0.

    DATA(lv_value) = zcprx_cl_config=>get(
                       iv_param   = |{ zcprx_cl_config=>c_param-alert_ts_prefix }{ iv_key }|
                       iv_default = `` ).
    CHECK lv_value IS NOT INITIAL.

    TRY.
        lv_last = CONV timestampl( lv_value ).
      CATCH cx_sy_conversion_error.
        RETURN.
    ENDTRY.

    GET TIME STAMP FIELD lv_now.
    TRY.
        rv_result = xsdbool( cl_abap_tstmp=>subtract( tstmp1 = lv_now tstmp2 = lv_last ) < lv_minutes * 60 ).
      CATCH cx_parameter_invalid_range cx_parameter_invalid_type.
        rv_result = abap_false.
    ENDTRY.
  ENDMETHOD.

  METHOD remember_sent.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.
    zcprx_cl_config=>set( iv_param = |{ zcprx_cl_config=>c_param-alert_ts_prefix }{ iv_key }|
                              iv_value = |{ lv_now }| ).
    COMMIT WORK.
  ENDMETHOD.

  METHOD deliver.
    DATA(lo_log) = zcprx_cl_log=>create( zcprx_if_constants=>log-sub_alert ).
    TRY.
        DATA(lo_mail) = cl_bcs_mail_message=>create_instance( ).
        lo_mail->set_sender( CONV #( zcprx_cl_config=>get( zcprx_cl_config=>c_param-alert_sender ) ) ).

        LOOP AT zcprx_cl_config=>get_list( zcprx_cl_config=>c_param-alert_recipients ) INTO DATA(lv_recipient).
          lo_mail->add_recipient( CONV #( lv_recipient ) ).
        ENDLOOP.

        DATA(lv_subject) = CONV string( iv_subject ).
        IF strlen( lv_subject ) > 120.
          lv_subject = lv_subject(120).
        ENDIF.
        lo_mail->set_subject( CONV #( lv_subject ) ).
        lo_mail->set_main( cl_bcs_mail_textpart=>create_instance( iv_content      = iv_html
                                                                  iv_content_type = 'text/html' ) ).
        lo_mail->send( ).
        rv_sent = abap_true.

      CATCH cx_bcs_mail INTO DATA(lx_mail).
        " Mailfehler nie an die fachliche Verarbeitung weitergeben
        lo_log->error( |Alert-Mail nicht versendet: { lx_mail->get_text( ) }| ).
        lo_log->save( ).
    ENDTRY.
  ENDMETHOD.

  METHOD build_html.
    DATA(lv_rows) = ``.
    LOOP AT it_lines INTO DATA(lv_line) TO c_max_lines.
      lv_rows = |{ lv_rows }<tr><td style="padding:4px 8px;border-bottom:1px solid #ddd">{ html_escape( lv_line ) }</td></tr>|.
    ENDLOOP.
    IF lines( it_lines ) > c_max_lines.
      lv_rows = |{ lv_rows }<tr><td style="padding:4px 8px">… { lines( it_lines ) - c_max_lines } weitere Einträge im Application Log</td></tr>|.
    ENDIF.

    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    rv_html =
      |<html><body style="font-family:Arial,sans-serif;font-size:13px">| &&
      |<h3 style="color:{ COND string( WHEN iv_is_error = abap_true THEN '#b00' ELSE '#333' ) }">{ html_escape( iv_title ) }</h3>| &&
      |<p>System: { html_escape( system_name( ) ) }<br>Zeitpunkt (UTC): { lv_now TIMESTAMP = ISO }</p>| &&
      |<table style="border-collapse:collapse">{ lv_rows }</table>| &&
      COND string( WHEN iv_is_error = abap_true THEN
        |<p>Details: App „Application Jobs“ (Protokoll am Joblauf) bzw. Admin-App „Praxedo Adapter Administration“, Tab Queue.<br>| &&
        |Weitere Mails zu diesem Fehlerbild frühestens nach { zcprx_cl_config=>get( zcprx_cl_config=>c_param-alert_throttle_min ) } Minuten.</p>| ) &&
      |</body></html>|.
  ENDMETHOD.

  METHOD system_name.
    TRY.
        rv_name = cl_abap_context_info=>get_system_url( ).
      CATCH cx_abap_context_info_error.
        rv_name = `S/4HANA Cloud`.
    ENDTRY.
  ENDMETHOD.

  METHOD html_escape.
    rv_value = escape( val = iv_value format = cl_abap_format=>e_xss_ml ).
  ENDMETHOD.

ENDCLASS.
