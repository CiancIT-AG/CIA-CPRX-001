CLASS ltcl_report DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS file_name_uses_code      FOR TESTING.
    METHODS file_name_replaces_chars FOR TESTING.
ENDCLASS.

CLASS ltcl_report IMPLEMENTATION.
  METHOD file_name_uses_code.
    cl_abap_unit_assert=>assert_equals( exp = `Praxedo_8000000123-10.pdf`
                                        act = zcprx_cl_report=>file_name( `8000000123-10` ) ).
  ENDMETHOD.

  METHOD file_name_replaces_chars.
    cl_abap_unit_assert=>assert_equals( exp = `Praxedo_A_B_C.pdf`
                                        act = zcprx_cl_report=>file_name( `A/B C` ) ).
  ENDMETHOD.
ENDCLASS.

