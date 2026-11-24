CLASS zcprx_cl_job_post DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcprx_cl_job_base.
  PROTECTED SECTION.
    METHODS get_subobject     REDEFINITION.
    METHODS run               REDEFINITION.
    METHODS define_parameters REDEFINITION.
    METHODS default_values    REDEFINITION.
ENDCLASS.

CLASS zcprx_cl_job_post IMPLEMENTATION.
  METHOD get_subobject.
    rv_subobject = zcprx_if_constants=>log-sub_post.
  ENDMETHOD.

  METHOD define_parameters.
    rt_definition = VALUE #(
      ( selname = 'P_MAX' kind = if_apj_dt_exec_object=>parameter datatype = 'N' length = 6
        param_text = 'Max. Einsätze je Lauf' changeable_ind = abap_true ) ).
  ENDMETHOD.

  METHOD default_values.
    rt_values = VALUE #( ( selname = 'P_MAX' kind = if_apj_dt_exec_object=>parameter sign = 'I' option = 'EQ' low = '000500' ) ).
  ENDMETHOD.

  METHOD run.
    DATA(lv_max)   = CONV i( param( it_parameters = it_parameters iv_name = 'P_MAX' ) ).
    DATA(lv_count) = NEW zcprx_cl_posting( )->post_all_received(
                       io_log = mo_log
                       iv_max = COND #( WHEN lv_max > 0 THEN lv_max ELSE 500 ) ).
    mo_log->success( |{ lv_count } Einsatz/Einsätze verbucht (Status PROCESSED)| ).
  ENDMETHOD.
ENDCLASS.
