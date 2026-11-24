CLASS zcprx_cl_job_base DEFINITION PUBLIC ABSTRACT CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_apj_dt_exec_object.
    INTERFACES if_apj_rt_exec_object.

  PROTECTED SECTION.
    DATA mo_log TYPE REF TO zcprx_cl_log.

    METHODS get_subobject ABSTRACT
      RETURNING VALUE(rv_subobject) TYPE string.

    METHODS run ABSTRACT
      IMPORTING it_parameters TYPE if_apj_rt_exec_object=>tt_templ_val
      RAISING   zcprx_cx_error.

    METHODS define_parameters
      RETURNING VALUE(rt_definition) TYPE if_apj_dt_exec_object=>tt_templ_def.

    METHODS default_values
      RETURNING VALUE(rt_values) TYPE if_apj_dt_exec_object=>tt_templ_val.

    METHODS param
      IMPORTING it_parameters   TYPE if_apj_rt_exec_object=>tt_templ_val
                iv_name         TYPE csequence
      RETURNING VALUE(rv_value) TYPE string.
ENDCLASS.

CLASS zcprx_cl_job_base IMPLEMENTATION.

  METHOD if_apj_dt_exec_object~get_parameters.
    et_parameter_def = define_parameters( ).
    et_parameter_val = default_values( ).
  ENDMETHOD.

  METHOD if_apj_rt_exec_object~execute.
    mo_log = zcprx_cl_log=>create( iv_subobject = get_subobject( ) ).
    TRY.
        run( it_parameters ).
      CATCH zcprx_cx_error INTO DATA(lx_error).
        mo_log->exception( lx_error ).
      CATCH cx_root INTO DATA(lx_root).
        mo_log->exception( lx_root ).
    ENDTRY.

    " Log am Joblauf in F1240 sichtbar
    mo_log->save( iv_assign_to_job = abap_true ).

    " Fehler -> Alert-Mail (gebündelt, gedrosselt) + Jobstatus "Fehlerhaft"
    " (Warnungen, z. B. Retries oder gesperrte Einsätze, lösen keinen Alarm aus)
    IF mo_log->has_errors( ).
      NEW zcprx_cl_alert( )->send(
        iv_key     = |JOB_{ get_subobject( ) }|
        iv_subject = |Fehler im Job { get_subobject( ) }|
        it_errors  = mo_log->get_errors( ) ).
      RAISE EXCEPTION NEW cx_apj_rt_content( ).
    ENDIF.
  ENDMETHOD.

  METHOD define_parameters.
    " Standard: keine Parameter
  ENDMETHOD.

  METHOD default_values.
  ENDMETHOD.

  METHOD param.
    READ TABLE it_parameters INTO DATA(ls_parameter) WITH KEY selname = iv_name.
    IF sy-subrc = 0.
      rv_value = condense( CONV string( ls_parameter-low ) ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
