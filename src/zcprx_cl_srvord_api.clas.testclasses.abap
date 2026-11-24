CLASS ltcl_srvord_dates DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS parses_v2_epoch           FOR TESTING.
    METHODS parses_v2_with_offset     FOR TESTING.
    METHODS parses_iso                FOR TESTING.
    METHODS writes_v2                 FOR TESTING.
ENDCLASS.

CLASS ltcl_srvord_dates IMPLEMENTATION.
  METHOD parses_v2_epoch.
    cl_abap_unit_assert=>assert_equals(
      exp = CONV utclong( '1970-01-01T00:00:00' )
      act = zcprx_cl_srvord_api=>parse_v2_date( `/Date(0)/` ) ).
  ENDMETHOD.

  METHOD parses_v2_with_offset.
    cl_abap_unit_assert=>assert_equals(
      exp = CONV utclong( '2023-11-14T22:13:20' )
      act = zcprx_cl_srvord_api=>parse_v2_date( `/Date(1700000000000+0000)/` ) ).
  ENDMETHOD.

  METHOD parses_iso.
    cl_abap_unit_assert=>assert_equals(
      exp = CONV utclong( '2026-11-24T08:00:00' )
      act = zcprx_cl_srvord_api=>parse_v2_date( `2026-11-24T08:00:00Z` ) ).
  ENDMETHOD.

  METHOD writes_v2.
    cl_abap_unit_assert=>assert_equals(
      exp = `/Date(1700000000000)/`
      act = zcprx_cl_srvord_api=>to_v2_date( CONV utclong( '2023-11-14T22:13:20' ) ) ).
  ENDMETHOD.
ENDCLASS.
