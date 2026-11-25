CLASS zcprx_cl_mapper DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    METHODS customer
      IMPORTING iv_customer        TYPE char10
      RETURNING VALUE(rs_customer) TYPE zcprx_if_praxedo_api=>ty_customer
      RAISING   zcprx_cx_error.

    METHODS location
      IMPORTING iv_ship_to         TYPE char10
                iv_sold_to         TYPE char10
                iv_customer_id     TYPE string
      RETURNING VALUE(rs_location) TYPE zcprx_if_praxedo_api=>ty_location
      RAISING   zcprx_cx_error.

    METHODS equipment
      IMPORTING iv_equipment        TYPE char18
                iv_customer_id      TYPE string
                iv_location_id      TYPE string
      RETURNING VALUE(rs_equipment) TYPE zcprx_if_praxedo_api=>ty_equipment
      RAISING   zcprx_cx_error.

    CLASS-METHODS to_iso
      IMPORTING iv_value        TYPE utclong
      RETURNING VALUE(rv_value) TYPE string.

    CLASS-METHODS from_iso
      IMPORTING iv_value        TYPE string
      RETURNING VALUE(rv_value) TYPE utclong.

    CLASS-METHODS language
      RETURNING VALUE(rv_language) TYPE spras.
ENDCLASS.

CLASS zcprx_cl_mapper IMPLEMENTATION.

  METHOD customer.
    SELECT SINGLE Customer, CustomerName, StreetName, PostalCode, CityName, Country, TelephoneNumber1
      FROM I_Customer
      WHERE Customer = @iv_customer
      INTO @DATA(ls_customer).
    IF sy-subrc <> 0.
      zcprx_cx_error=>raise( iv_text = |Kunde { iv_customer } nicht gefunden| iv_permanent = abap_true ).
    ENDIF.

    rs_customer = VALUE #( external_id = ls_customer-Customer
                           name        = ls_customer-CustomerName
                           phone       = ls_customer-TelephoneNumber1
                           address     = VALUE #( street   = ls_customer-StreetName
                                                  zip_code = ls_customer-PostalCode
                                                  city     = ls_customer-CityName
                                                  country  = ls_customer-Country ) ).
  ENDMETHOD.

  METHOD location.
    " Location = Einsatzort = Adresse des Warenempfängers (Fallback Auftraggeber)
    DATA(lv_partner) = COND char10( WHEN iv_ship_to IS NOT INITIAL THEN iv_ship_to ELSE iv_sold_to ).
    DATA(ls_customer) = customer( lv_partner ).

    rs_location = VALUE #( external_id = |{ iv_sold_to }-{ lv_partner }|
                           name        = ls_customer-name
                           customer_id = iv_customer_id
                           address     = ls_customer-address ).
  ENDMETHOD.

  METHOD equipment.
    SELECT SINGLE Equipment, TechnicalObjectType, SerialNumber
      FROM I_Equipment
      WHERE Equipment = @iv_equipment
      INTO @DATA(ls_equipment).
    IF sy-subrc <> 0.
      zcprx_cx_error=>raise( iv_text = |Equipment { iv_equipment } nicht gefunden| iv_permanent = abap_true ).
    ENDIF.

    DATA(lv_language) = language( ).
    SELECT SINGLE EquipmentName
      FROM I_EquipmentText
      WHERE Equipment = @iv_equipment
        AND Language  = @lv_language
      INTO @DATA(lv_name).

    rs_equipment = VALUE #( external_id   = ls_equipment-Equipment
                            name          = COND #( WHEN lv_name IS NOT INITIAL THEN lv_name ELSE ls_equipment-Equipment )
                            serial_number = ls_equipment-SerialNumber
                            type_id       = ls_equipment-TechnicalObjectType
                            customer_id   = iv_customer_id
                            location_id   = iv_location_id ).
  ENDMETHOD.

  METHOD to_iso.
    CHECK iv_value IS NOT INITIAL.
    rv_value = |{ substring( val = |{ iv_value TIMESTAMP = ISO }| len = 19 ) }Z|.
  ENDMETHOD.

  METHOD from_iso.
    " 2026-11-24T10:15:30Z | 2026-11-24T10:15:30.123+01:00 | 2026-11-24T10:15:30
    " Offset wird nach UTC umgerechnet (Praxedo liefert Ortszeit mit Offset)
    CHECK strlen( iv_value ) >= 19.
    TRY.
        rv_value = CONV utclong( substring( val = iv_value len = 19 ) ).
        IF strlen( iv_value ) > 19.
          FIND PCRE `([+-])(\d{2}):?(\d{2})$` IN iv_value SUBMATCHES DATA(lv_sign) DATA(lv_hours) DATA(lv_minutes).
          IF sy-subrc = 0.
            DATA(lv_offset) = CONV i( lv_hours ) * 3600 + CONV i( lv_minutes ) * 60.
            rv_value = utclong_add( val     = rv_value
                                    seconds = COND i( WHEN lv_sign = '+' THEN 0 - lv_offset ELSE lv_offset ) ).
          ENDIF.
        ENDIF.
      CATCH cx_root.
        CLEAR rv_value.
    ENDTRY.
  ENDMETHOD.

  METHOD language.
    TRY.
        rv_language = cl_abap_context_info=>get_user_language_abap_format( ).
      CATCH cx_abap_context_info_error.
        rv_language = 'E'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

