CLASS zcprx_cl_log DEFINITION PUBLIC FINAL CREATE PRIVATE.
  PUBLIC SECTION.
    TYPES tt_text TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    CLASS-METHODS create
      IMPORTING iv_subobject   TYPE csequence
                iv_external_id TYPE csequence OPTIONAL
      RETURNING VALUE(ro_log)  TYPE REF TO zcprx_cl_log.

    METHODS info      IMPORTING iv_text TYPE csequence.
    METHODS success   IMPORTING iv_text TYPE csequence.
    METHODS warning   IMPORTING iv_text TYPE csequence.
    METHODS error     IMPORTING iv_text TYPE csequence.
    METHODS exception IMPORTING ix_error TYPE REF TO cx_root.
    METHODS has_errors RETURNING VALUE(rv_result) TYPE abap_bool.
    "! Gesammelte Fehlertexte (für das Mail-Alerting)
    METHODS get_errors RETURNING VALUE(rt_errors) TYPE tt_text.
    METHODS save IMPORTING iv_assign_to_job TYPE abap_bool DEFAULT abap_false.

  PRIVATE SECTION.
    DATA mo_log    TYPE REF TO if_bali_log.
    DATA mv_errors TYPE i.
    DATA mt_errors TYPE tt_text.
    METHODS add_text IMPORTING iv_severity TYPE c
                               iv_text     TYPE csequence.
ENDCLASS.

CLASS zcprx_cl_log IMPLEMENTATION.

  METHOD create.
    ro_log = NEW #( ).
    TRY.
        ro_log->mo_log = cl_bali_log=>create_with_header(
          header = cl_bali_header_setter=>create(
                     object      = CONV #( zcprx_if_constants=>log-object )
                     subobject   = CONV #( iv_subobject )
                     external_id = CONV #( iv_external_id ) ) ).
      CATCH cx_bali_runtime.
        CLEAR ro_log->mo_log.   " Logging darf die Verarbeitung nie abbrechen
    ENDTRY.
  ENDMETHOD.

  METHOD info.
    add_text( iv_severity = if_bali_constants=>c_severity_information iv_text = iv_text ).
  ENDMETHOD.

  METHOD success.
    add_text( iv_severity = if_bali_constants=>c_severity_status iv_text = iv_text ).
  ENDMETHOD.

  METHOD warning.
    add_text( iv_severity = if_bali_constants=>c_severity_warning iv_text = iv_text ).
  ENDMETHOD.

  METHOD error.
    mv_errors += 1.
    APPEND CONV string( iv_text ) TO mt_errors.
    add_text( iv_severity = if_bali_constants=>c_severity_error iv_text = iv_text ).
  ENDMETHOD.

  METHOD exception.
    mv_errors += 1.
    APPEND ix_error->get_text( ) TO mt_errors.
    CHECK mo_log IS BOUND.
    TRY.
        mo_log->add_item( item = cl_bali_exception_setter=>create(
                                   severity  = if_bali_constants=>c_severity_error
                                   exception = ix_error ) ).
      CATCH cx_bali_runtime ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.

  METHOD get_errors.
    rt_errors = mt_errors.
  ENDMETHOD.

  METHOD has_errors.
    rv_result = xsdbool( mv_errors > 0 ).
  ENDMETHOD.

  METHOD save.
    CHECK mo_log IS BOUND.
    TRY.
        cl_bali_log_db=>get_instance( )->save_log( log                        = mo_log
                                                   assign_to_current_appl_job = iv_assign_to_job ).
      CATCH cx_bali_runtime ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.

  METHOD add_text.
    CHECK mo_log IS BOUND.
    DATA(lv_text) = CONV string( iv_text ).
    IF strlen( lv_text ) > 200.          " Freitext max. 200 Zeichen
      lv_text = lv_text(200).
    ENDIF.
    TRY.
        mo_log->add_item( item = cl_bali_free_text_setter=>create( severity = CONV #( iv_severity )
                                                                   text     = CONV #( lv_text ) ) ).
      CATCH cx_bali_runtime ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
