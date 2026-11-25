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
    " Als Freitext protokollieren: Der Exception-Setter zeigt bei Ausnahmen
    " ohne T100-Nachricht nur "An exception was raised."
    DATA(lv_text) = ix_error->get_text( ).
    IF lv_text IS INITIAL.
      lv_text = cl_abap_typedescr=>describe_by_object_ref( ix_error )->get_relative_name( ).
    ENDIF.
    " Vorgänger anhängen, sofern nicht schon im Text enthalten (bei ZCPRX_CX_ERROR schon drin)
    DATA(lx_previous) = ix_error->previous.
    WHILE lx_previous IS BOUND.
      DATA(lv_previous) = lx_previous->get_text( ).
      IF lv_previous IS NOT INITIAL AND lv_text NS lv_previous.
        lv_text = |{ lv_text } / { lv_previous }|.
      ENDIF.
      lx_previous = lx_previous->previous.
    ENDWHILE.
    error( lv_text ).
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
    " Zeilenumbrüche entfernen; Freitext max. 200 Zeichen -> lange Texte auf Folgezeilen
    DATA(lv_text) = condense( replace( val = CONV string( iv_text ) pcre = `[\r\n\t]+` with = ` ` occ = 0 ) ).
    DATA(lv_first) = abap_true.
    WHILE lv_text IS NOT INITIAL.
      DATA(lv_len)  = nmin( val1 = strlen( lv_text ) val2 = COND i( WHEN lv_first = abap_true THEN 200 ELSE 198 ) ).
      DATA(lv_part) = COND string( WHEN lv_first = abap_true THEN substring( val = lv_text len = lv_len )
                                   ELSE |… { substring( val = lv_text len = lv_len ) }| ).
      lv_text  = substring( val = lv_text off = lv_len ).
      lv_first = abap_false.
      TRY.
          mo_log->add_item( item = cl_bali_free_text_setter=>create( severity = CONV #( iv_severity )
                                                                     text     = CONV #( lv_part ) ) ).
        CATCH cx_bali_runtime ##NO_HANDLER.
      ENDTRY.
    ENDWHILE.
  ENDMETHOD.

ENDCLASS.

