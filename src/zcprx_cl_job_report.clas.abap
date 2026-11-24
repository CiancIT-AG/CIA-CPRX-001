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
      ( selname = 'P_REPID' kind = if_apj_dt_exec_object=>parameter datatype = 'C' length = 40
        param_text = 'Praxedo-Bericht (ID)' changeable_ind = abap_true mandatory_ind = abap_true lowercase_ind = abap_true )
      ( selname = 'P_DATE'  kind = if_apj_dt_exec_object=>parameter datatype = 'D' length = 8
        param_text = 'Stichtag (leer = gestern)' changeable_ind = abap_true ) ).
  ENDMETHOD.

  METHOD default_values.
    rt_values = VALUE #( ( selname = 'P_REPID' kind = if_apj_dt_exec_object=>parameter sign = 'I' option = 'EQ' low = 'DAILY' ) ).
  ENDMETHOD.

  METHOD run.
    DATA(lv_report) = param( it_parameters = it_parameters iv_name = 'P_REPID' ).
    DATA(lv_date)   = CONV d( param( it_parameters = it_parameters iv_name = 'P_DATE' ) ).
    IF lv_date IS INITIAL OR lv_date = '00000000'.
      lv_date = cl_abap_context_info=>get_system_date( ) - 1.
    ENDIF.

    DATA(lt_lines) = NEW zcprx_cl_praxedo_api( )->zcprx_if_praxedo_api~get_report(
                       iv_report_id = lv_report
                       iv_date      = lv_date ).

    mo_log->info( |Praxedo-Bericht { lv_report } vom { lv_date DATE = ISO }: { lines( lt_lines ) } Zeile(n)| ).

    LOOP AT lt_lines INTO DATA(ls_line).
      DATA(lv_text) = |{ ls_line-timestamp } { ls_line-text }|.
      CASE to_upper( ls_line-level ).
        WHEN 'ERROR'.
          " Berichtsinhalt -> als Warnung protokollieren, Job selbst bleibt erfolgreich
          mo_log->warning( lv_text ).
        WHEN 'WARNING'.
          mo_log->warning( lv_text ).
        WHEN OTHERS.
          mo_log->info( lv_text ).
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
