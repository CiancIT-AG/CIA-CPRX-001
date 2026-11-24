CLASS ltcl_queue DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS backoff_first_retry_is_base  FOR TESTING.
    METHODS backoff_doubles              FOR TESTING.
    METHODS backoff_is_capped            FOR TESTING.
    METHODS to_uuid_roundtrip            FOR TESTING RAISING cx_static_check.
    METHODS to_uuid_rejects_invalid      FOR TESTING.
ENDCLASS.

CLASS ltcl_queue IMPLEMENTATION.
  METHOD backoff_first_retry_is_base.
    cl_abap_unit_assert=>assert_equals(
      exp = 300
      act = zcprx_cl_queue=>calc_backoff_seconds( iv_retry = 1 iv_base_min = 5 iv_max_min = 60 ) ).
  ENDMETHOD.

  METHOD backoff_doubles.
    cl_abap_unit_assert=>assert_equals(
      exp = 600
      act = zcprx_cl_queue=>calc_backoff_seconds( iv_retry = 2 iv_base_min = 5 iv_max_min = 60 ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = 1200
      act = zcprx_cl_queue=>calc_backoff_seconds( iv_retry = 3 iv_base_min = 5 iv_max_min = 60 ) ).
  ENDMETHOD.

  METHOD backoff_is_capped.
    " 5 * 2^4 = 80 Min -> gedeckelt auf 60 Min
    cl_abap_unit_assert=>assert_equals(
      exp = 3600
      act = zcprx_cl_queue=>calc_backoff_seconds( iv_retry = 5 iv_base_min = 5 iv_max_min = 60 ) ).
  ENDMETHOD.

  METHOD to_uuid_roundtrip.
    DATA(lv_uuid) = cl_system_uuid=>create_uuid_x16_static( ).
    cl_abap_unit_assert=>assert_equals( exp = lv_uuid
                                        act = zcprx_cl_queue=>to_uuid( |{ lv_uuid }| ) ).
  ENDMETHOD.

  METHOD to_uuid_rejects_invalid.
    TRY.
        zcprx_cl_queue=>to_uuid( 'KEINE-UUID' ).
        cl_abap_unit_assert=>fail( msg = 'Ausnahme erwartet' ).
      CATCH zcprx_cx_error INTO DATA(lx_error).
        cl_abap_unit_assert=>assert_true( act = lx_error->mv_permanent
                                          msg = 'Ungültiger Schlüssel muss dauerhaft sein (kein Retry)' ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
