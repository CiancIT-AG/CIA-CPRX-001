CLASS ltcl_error DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS client_errors_are_permanent FOR TESTING.
    METHODS transient_codes_are_retried FOR TESTING.
ENDCLASS.

CLASS ltcl_error IMPLEMENTATION.
  METHOD client_errors_are_permanent.
    cl_abap_unit_assert=>assert_true( zcprx_cx_error=>is_permanent_http( 400 ) ).
    cl_abap_unit_assert=>assert_true( zcprx_cx_error=>is_permanent_http( 404 ) ).
    cl_abap_unit_assert=>assert_true( zcprx_cx_error=>is_permanent_http( 422 ) ).
  ENDMETHOD.

  METHOD transient_codes_are_retried.
    cl_abap_unit_assert=>assert_false( zcprx_cx_error=>is_permanent_http( 408 ) ).
    cl_abap_unit_assert=>assert_false( zcprx_cx_error=>is_permanent_http( 429 ) ).
    cl_abap_unit_assert=>assert_false( zcprx_cx_error=>is_permanent_http( 500 ) ).
    cl_abap_unit_assert=>assert_false( zcprx_cx_error=>is_permanent_http( 503 ) ).
  ENDMETHOD.
ENDCLASS.
