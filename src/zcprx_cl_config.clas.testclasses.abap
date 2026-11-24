CLASS ltcl_config DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS defaults_are_unique         FOR TESTING.
    METHODS defaults_cover_all_params   FOR TESTING.
ENDCLASS.

CLASS ltcl_config IMPLEMENTATION.
  METHOD defaults_are_unique.
    DATA(lt_defaults) = zcprx_cl_config=>get_defaults( ).
    DATA(lv_lines)    = lines( lt_defaults ).
    SORT lt_defaults BY param.
    DELETE ADJACENT DUPLICATES FROM lt_defaults COMPARING param.
    cl_abap_unit_assert=>assert_equals( exp = lv_lines act = lines( lt_defaults )
                                        msg = 'Parameter doppelt in GET_DEFAULTS' ).
  ENDMETHOD.

  METHOD defaults_cover_all_params.
    " Jeder Parameter außer Laufzeitwerten/Präfixen braucht einen Standard,
    " sonst liefert GET nach der Installation einen leeren Wert.
    DATA(lt_defaults) = zcprx_cl_config=>get_defaults( ).
    DATA(lo_struct)   = CAST cl_abap_structdescr(
                          cl_abap_typedescr=>describe_by_data( zcprx_cl_config=>c_param ) ).
    DATA(lt_runtime)  = VALUE zcprx_cl_config=>tt_values(
                          ( CONV #( zcprx_cl_config=>c_param-last_fetch_ts ) )
                          ( CONV #( zcprx_cl_config=>c_param-last_delta_ts ) )
                          ( CONV #( zcprx_cl_config=>c_param-job_prefix ) )
                          ( CONV #( zcprx_cl_config=>c_param-alert_ts_prefix ) ) ).

    LOOP AT lo_struct->components INTO DATA(ls_component).
      ASSIGN COMPONENT ls_component-name OF STRUCTURE zcprx_cl_config=>c_param TO FIELD-SYMBOL(<lv_param>).
      CHECK sy-subrc = 0.
      CHECK NOT line_exists( lt_runtime[ table_line = CONV string( <lv_param> ) ] ).
      cl_abap_unit_assert=>assert_true(
        act = xsdbool( line_exists( lt_defaults[ param = <lv_param> ] ) )
        msg = |Kein Standardwert für { <lv_param> }| ).
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
