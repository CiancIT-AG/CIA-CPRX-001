CLASS zcprx_cl_job_fetch DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcprx_cl_job_base.
  PROTECTED SECTION.
    METHODS get_subobject REDEFINITION.
    METHODS run           REDEFINITION.
ENDCLASS.

CLASS zcprx_cl_job_fetch IMPLEMENTATION.
  METHOD get_subobject.
    rv_subobject = zcprx_if_constants=>log-sub_fetch.
  ENDMETHOD.

  METHOD run.
    DATA(lv_count) = NEW zcprx_cl_inbound( )->fetch_completed( mo_log ).
    mo_log->success( |{ lv_count } Rückmeldung(en) gespeichert| ).
  ENDMETHOD.
ENDCLASS.
