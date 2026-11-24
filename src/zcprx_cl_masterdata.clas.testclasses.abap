CLASS ltd_praxedo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zcprx_if_praxedo_api PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_praxedo IMPLEMENTATION.
ENDCLASS.

CLASS ltcl_masterdata DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO zcprx_cl_masterdata.
    METHODS setup.
    METHODS empty_bulk_answer_means_sent FOR TESTING.
    METHODS error_entry_is_error         FOR TESTING.
    METHODS missing_entry_is_error       FOR TESTING.
    METHODS praxedo_id_is_taken          FOR TESTING.
ENDCLASS.

CLASS ltcl_masterdata IMPLEMENTATION.
  METHOD setup.
    mo_cut = NEW #( io_praxedo = NEW ltd_praxedo( ) ).
  ENDMETHOD.

  METHOD empty_bulk_answer_means_sent.
    DATA(ls_result) = mo_cut->result_for( it_result = VALUE #( ) iv_key = 'PG01' ).
    cl_abap_unit_assert=>assert_equals( exp = zcprx_if_constants=>sync_status-sent act = ls_result-Status ).
    cl_abap_unit_assert=>assert_equals( exp = 'PG01' act = ls_result-PraxedoId ).
  ENDMETHOD.

  METHOD error_entry_is_error.
    DATA(ls_result) = mo_cut->result_for( it_result = VALUE #( ( external_id = `PG01` error = `ungültig` ) ) iv_key = 'PG01' ).
    cl_abap_unit_assert=>assert_equals( exp = zcprx_if_constants=>sync_status-error act = ls_result-Status ).
  ENDMETHOD.

  METHOD missing_entry_is_error.
    DATA(ls_result) = mo_cut->result_for( it_result = VALUE #( ( external_id = `PG02` id = `77` ) ) iv_key = 'PG01' ).
    cl_abap_unit_assert=>assert_equals( exp = zcprx_if_constants=>sync_status-error act = ls_result-Status ).
  ENDMETHOD.

  METHOD praxedo_id_is_taken.
    DATA(ls_result) = mo_cut->result_for( it_result = VALUE #( ( external_id = `PG01` id = `77` ) ) iv_key = 'PG01' ).
    cl_abap_unit_assert=>assert_equals( exp = '77' act = ls_result-PraxedoId ).
  ENDMETHOD.
ENDCLASS.
