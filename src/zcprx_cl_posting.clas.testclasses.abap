CLASS ltd_srvord DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zcprx_if_srvord_api PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_srvord IMPLEMENTATION.
ENDCLASS.

CLASS ltcl_posting DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    DATA mo_cut      TYPE REF TO zcprx_cl_posting.
    DATA ms_order    TYPE zcprx_cl_posting=>ty_order.
    DATA mt_time     TYPE zcprx_cl_posting=>tt_time.
    DATA mt_material TYPE zcprx_cl_posting=>tt_material.

    METHODS setup.
    METHODS skips_posted_lines          FOR TESTING.
    METHODS applies_default_product     FOR TESTING.
    METHODS maps_material_fields        FOR TESTING.
    METHODS header_references_order     FOR TESTING.
ENDCLASS.

CLASS ltcl_posting IMPLEMENTATION.
  METHOD setup.
    mo_cut   = NEW #( io_srvord = NEW ltd_srvord( ) ).
    ms_order = VALUE #( ServiceOrder     = '8000001'
                        ServiceOrderItem = '10'
                        PraxedoId        = 'PX-4711'
                        SoldToParty      = '1000001'
                        Description      = 'Wartung' ).
    mt_time = VALUE #(
      ( ServiceProduct = ''      Duration = '1.5' DurationUnit = 'H' IsPosted = abap_false )
      ( ServiceProduct = 'SRV_A' Duration = '2.0' DurationUnit = 'H' IsPosted = abap_true ) ).
    mt_material = VALUE #(
      ( Product = 'MAT-1' Quantity = 3 QuantityUnit = 'ST' Plant = '1010' StorageLocation = '0001' IsPosted = abap_false ) ).
  ENDMETHOD.

  METHOD skips_posted_lines.
    DATA(ls_conf) = mo_cut->build_confirmation( is_order = ms_order it_time = mt_time it_material = mt_material ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( ls_conf-items )
                                        msg = 'Bereits verbuchte Zeile darf nicht erneut gebucht werden' ).
  ENDMETHOD.

  METHOD applies_default_product.
    DATA(ls_conf) = mo_cut->build_confirmation( is_order           = ms_order
                                                it_time            = mt_time
                                                it_material        = mt_material
                                                iv_itemcat_time    = 'SRVP'
                                                iv_default_product = 'SRV_DEFAULT' ).
    cl_abap_unit_assert=>assert_equals( exp = 'SRV_DEFAULT' act = ls_conf-items[ 1 ]-product ).
    cl_abap_unit_assert=>assert_equals( exp = 'SRVP'        act = ls_conf-items[ 1 ]-item_category ).
    cl_abap_unit_assert=>assert_equals( exp = CONV decfloat34( '1.5' ) act = ls_conf-items[ 1 ]-quantity ).
  ENDMETHOD.

  METHOD maps_material_fields.
    DATA(ls_conf) = mo_cut->build_confirmation( is_order = ms_order it_time = mt_time it_material = mt_material
                                                iv_itemcat_material = 'SRVM' ).
    DATA(ls_item) = ls_conf-items[ 2 ].
    cl_abap_unit_assert=>assert_equals( exp = 'MAT-1' act = ls_item-product ).
    cl_abap_unit_assert=>assert_equals( exp = '1010'  act = ls_item-plant ).
    cl_abap_unit_assert=>assert_equals( exp = '0001'  act = ls_item-storage_location ).
    cl_abap_unit_assert=>assert_equals( exp = 'SRVM'  act = ls_item-item_category ).
    cl_abap_unit_assert=>assert_equals( exp = '10'    act = ls_item-service_order_item ).
  ENDMETHOD.

  METHOD header_references_order.
    DATA(ls_conf) = mo_cut->build_confirmation( is_order = ms_order it_time = mt_time it_material = mt_material ).
    cl_abap_unit_assert=>assert_equals( exp = '8000001' act = ls_conf-service_order ).
    cl_abap_unit_assert=>assert_equals( exp = '1000001' act = ls_conf-sold_to_party ).
    cl_abap_unit_assert=>assert_char_cp( exp = '*PX-4711*' act = ls_conf-description ).
  ENDMETHOD.
ENDCLASS.
