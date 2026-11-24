CLASS zcprx_cl_job_products DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcprx_cl_job_base.
  PROTECTED SECTION.
    METHODS get_subobject REDEFINITION.
    METHODS run           REDEFINITION.
ENDCLASS.

CLASS zcprx_cl_job_products IMPLEMENTATION.
  METHOD get_subobject.
    rv_subobject = zcprx_if_constants=>log-sub_product.
  ENDMETHOD.

  METHOD run.
    DATA(lv_count) = NEW zcprx_cl_masterdata( )->send_products( io_log = mo_log ).
    mo_log->success( |{ lv_count } Artikel an Praxedo übertragen| ).
  ENDMETHOD.
ENDCLASS.
