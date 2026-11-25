CLASS zcprx_cl_job_report DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcprx_cl_job_base.
  PROTECTED SECTION.
    METHODS get_subobject     REDEFINITION.
    METHODS run               REDEFINITION.
    METHODS define_parameters REDEFINITION.
    METHODS default_values    REDEFINITION.
ENDCLASS.

CLASS zcprx_cl_job_report IMPLEMENTATION.
  METHOD get_subobject.
    rv_subobject = zcprx_if_constants=>log-sub_report.
  ENDMETHOD.

  METHOD define_parameters.
    rt_definition = VALUE #(
      ( selname = 'P_CHECK' kind = if_apj_dt_exec_object=>parameter datatype = 'C' length = 1
        param_text = 'Nicht validierte Einsätze nachprüfen (X)' changeable_ind = abap_true )
      ( selname = 'P_DAYS'  kind = if_apj_dt_exec_object=>parameter datatype = 'N' length = 3
        param_text = 'Nachprüfung: Einsätze der letzten n Tage' changeable_ind = abap_true )
      ( selname = 'P_RETRY' kind = if_apj_dt_exec_object=>parameter datatype = 'C' length = 1
        param_text = 'Fehlerhafte Berichte erneut anhängen (X)' changeable_ind = abap_true )
      ( selname = 'P_MAX'   kind = if_apj_dt_exec_object=>parameter datatype = 'N' length = 6
        param_text = 'Max. Einsätze je Schritt' changeable_ind = abap_true ) ).
  ENDMETHOD.

  METHOD default_values.
    rt_values = VALUE #(
      ( selname = 'P_CHECK' kind = if_apj_dt_exec_object=>parameter sign = 'I' option = 'EQ' low = 'X' )
      ( selname = 'P_DAYS'  kind = if_apj_dt_exec_object=>parameter sign = 'I' option = 'EQ' low = '030' )
      ( selname = 'P_RETRY' kind = if_apj_dt_exec_object=>parameter sign = 'I' option = 'EQ' low = 'X' )
      ( selname = 'P_MAX'   kind = if_apj_dt_exec_object=>parameter sign = 'I' option = 'EQ' low = '000200' ) ).
  ENDMETHOD.

  METHOD run.
    DATA(lv_days) = CONV i( param( it_parameters = it_parameters iv_name = 'P_DAYS' ) ).
    DATA(lv_max)  = CONV i( param( it_parameters = it_parameters iv_name = 'P_MAX' ) ).
    lv_days = COND #( WHEN lv_days > 0 THEN lv_days ELSE 30 ).
    lv_max  = COND #( WHEN lv_max  > 0 THEN lv_max  ELSE 200 ).

    DATA(lo_report) = NEW zcprx_cl_report( ).

    IF param( it_parameters = it_parameters iv_name = 'P_CHECK' ) = 'X'.
      DATA(lv_checked) = lo_report->check_pending( io_log = mo_log iv_days = lv_days iv_max = lv_max ).
      mo_log->info( |{ lv_checked } Einsatz/Einsätze bei Praxedo nachgeprüft| ).
    ENDIF.

    DATA(lv_count) = lo_report->attach_open(
                       io_log         = mo_log
                       iv_max         = lv_max
                       iv_with_errors = xsdbool( param( it_parameters = it_parameters iv_name = 'P_RETRY' ) = 'X' ) ).
    mo_log->success( |{ lv_count } Bericht(e) an Serviceaufträge angehängt| ).
  ENDMETHOD.
ENDCLASS.

