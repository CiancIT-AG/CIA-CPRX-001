CLASS ltcl_mapper DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS to_iso_appends_utc_marker FOR TESTING.
    METHODS from_iso_roundtrip        FOR TESTING.
    METHODS from_iso_empty_is_initial FOR TESTING.
    METHODS from_iso_applies_offset   FOR TESTING.
    METHODS from_iso_ignores_fraction FOR TESTING.
ENDCLASS.

CLASS ltcl_mapper IMPLEMENTATION.
  METHOD to_iso_appends_utc_marker.
    cl_abap_unit_assert=>assert_equals(
      exp = `2026-11-24T10:15:30Z`
      act = zcprx_cl_mapper=>to_iso( CONV utclong( '2026-11-24T10:15:30' ) ) ).
  ENDMETHOD.

  METHOD from_iso_roundtrip.
    DATA(lv_value) = CONV utclong( '2026-11-24T10:15:30' ).
    cl_abap_unit_assert=>assert_equals(
      exp = lv_value
      act = zcprx_cl_mapper=>from_iso( zcprx_cl_mapper=>to_iso( lv_value ) ) ).
  ENDMETHOD.

  METHOD from_iso_empty_is_initial.
    cl_abap_unit_assert=>assert_initial( zcprx_cl_mapper=>from_iso( `` ) ).
  ENDMETHOD.

  METHOD from_iso_applies_offset.
    " Praxedo liefert Ortszeit mit Offset -> UTC
    cl_abap_unit_assert=>assert_equals(
      exp = CONV utclong( '2026-11-24T09:15:30' )
      act = zcprx_cl_mapper=>from_iso( `2026-11-24T10:15:30.000+01:00` ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = CONV utclong( '2026-11-24T15:15:30' )
      act = zcprx_cl_mapper=>from_iso( `2026-11-24T10:15:30-0500` ) ).
  ENDMETHOD.

  METHOD from_iso_ignores_fraction.
    cl_abap_unit_assert=>assert_equals(
      exp = CONV utclong( '2026-11-24T10:15:30' )
      act = zcprx_cl_mapper=>from_iso( `2026-11-24T10:15:30.123Z` ) ).
  ENDMETHOD.
ENDCLASS.

