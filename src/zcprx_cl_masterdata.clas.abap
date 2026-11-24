CLASS zcprx_cl_masterdata DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES tt_key TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    METHODS constructor
      IMPORTING io_praxedo TYPE REF TO zcprx_if_praxedo_api OPTIONAL.

    METHODS get_sap_product_groups
      RETURNING VALUE(rt_groups) TYPE zcprx_if_praxedo_api=>tt_code.

    METHODS get_sap_equipment_types
      RETURNING VALUE(rt_types) TYPE zcprx_if_praxedo_api=>tt_code.

    "! Aktive Artikelgruppen senden (it_keys leer = alle aktiven)
    METHODS send_product_groups
      IMPORTING it_keys         TYPE tt_key OPTIONAL
      RETURNING VALUE(rv_count) TYPE i
      RAISING   zcprx_cx_error.

    METHODS send_equipment_types
      IMPORTING it_keys         TYPE tt_key OPTIONAL
      RETURNING VALUE(rv_count) TYPE i
      RAISING   zcprx_cx_error.

    "! Ergebnis je Eintrag aus der Bulk-Antwort (öffentlich für Unit-Tests)
    METHODS result_for
      IMPORTING it_result        TYPE zcprx_if_praxedo_api=>tt_id_result
                iv_key           TYPE csequence
      RETURNING VALUE(rs_result) TYPE zcprx_a_syncresult.

    "! Artikel senden (it_keys leer = alle Artikel der konfigurierten Artikelarten)
    METHODS send_products
      IMPORTING it_keys         TYPE tt_key OPTIONAL
                io_log          TYPE REF TO zcprx_cl_log OPTIONAL
      RETURNING VALUE(rv_count) TYPE i
      RAISING   zcprx_cx_error.

  PRIVATE SECTION.
    TYPES tt_range TYPE RANGE OF char40.
    DATA mo_praxedo TYPE REF TO zcprx_if_praxedo_api.

    METHODS to_range
      IMPORTING it_keys         TYPE tt_key
      RETURNING VALUE(rt_range) TYPE tt_range.

ENDCLASS.

CLASS zcprx_cl_masterdata IMPLEMENTATION.

  METHOD constructor.
    mo_praxedo = COND #( WHEN io_praxedo IS BOUND THEN io_praxedo ELSE NEW zcprx_cl_praxedo_api( ) ).
  ENDMETHOD.

  METHOD get_sap_product_groups.
    DATA(lv_language) = zcprx_cl_mapper=>language( ).
    SELECT g~ProductGroup, t~ProductGroupName
      FROM I_ProductGroup_2 AS g
      LEFT OUTER JOIN I_ProductGroupText_2 AS t
        ON  t~ProductGroup = g~ProductGroup
        AND t~Language     = @lv_language
      INTO TABLE @DATA(lt_groups).
    rt_groups = VALUE #( FOR g IN lt_groups ( external_id = g-ProductGroup name = g-ProductGroupName ) ).
  ENDMETHOD.

  METHOD get_sap_equipment_types.
    " HINWEIS: freigegebene Views für Techn. Objekttypen im Business
    " Accelerator Hub prüfen (Namen hier: I_TechnicalObjectType/-Text)
    DATA(lv_language) = zcprx_cl_mapper=>language( ).
    SELECT o~TechnicalObjectType, t~TechnicalObjectTypeDesc
      FROM I_TechnicalObjectType AS o
      LEFT OUTER JOIN I_TechnicalObjectTypeText AS t
        ON  t~TechnicalObjectType = o~TechnicalObjectType
        AND t~Language            = @lv_language
      INTO TABLE @DATA(lt_types).
    rt_types = VALUE #( FOR o IN lt_types ( external_id = o-TechnicalObjectType name = o-TechnicalObjectTypeDesc ) ).
  ENDMETHOD.

  METHOD send_product_groups.
    DATA lt_exec TYPE TABLE FOR ACTION IMPORT zcprx_r_productgroup\\ProductGroup~setSyncResult.
    DATA lt_result TYPE zcprx_if_praxedo_api=>tt_id_result.
    DATA(lr_keys) = to_range( it_keys ).

    SELECT ProductGroup, ProductGroupName FROM zcprx_r_productgroup
      WHERE IsActive = @abap_true AND ProductGroup IN @lr_keys
      INTO TABLE @DATA(lt_groups).
    CHECK lt_groups IS NOT INITIAL.

    TRY.
        lt_result = mo_praxedo->upsert_product_groups(
                      VALUE #( FOR g IN lt_groups ( external_id = g-ProductGroup name = g-ProductGroupName ) ) ).
      CATCH zcprx_cx_error INTO DATA(lx_error).
        lt_result = VALUE #( FOR g IN lt_groups ( external_id = g-ProductGroup error = lx_error->get_text( ) ) ).
    ENDTRY.

    lt_exec = VALUE #( FOR g IN lt_groups ( ProductGroup = g-ProductGroup
                                            %param       = result_for( it_result = lt_result iv_key = g-ProductGroup ) ) ).
    MODIFY ENTITIES OF zcprx_r_productgroup
      ENTITY ProductGroup EXECUTE setSyncResult FROM lt_exec
      FAILED DATA(ls_failed) ##NEEDED.
    COMMIT ENTITIES.

    IF lx_error IS BOUND.
      RAISE EXCEPTION lx_error.
    ENDIF.
    rv_count = lines( lt_groups ).
  ENDMETHOD.

  METHOD send_equipment_types.
    DATA lt_exec TYPE TABLE FOR ACTION IMPORT zcprx_r_equipmenttype\\EquipmentType~setSyncResult.
    DATA lt_result TYPE zcprx_if_praxedo_api=>tt_id_result.
    DATA(lr_keys) = to_range( it_keys ).

    SELECT EquipmentType, EquipmentTypeName FROM zcprx_r_equipmenttype
      WHERE IsActive = @abap_true AND EquipmentType IN @lr_keys
      INTO TABLE @DATA(lt_types).
    CHECK lt_types IS NOT INITIAL.

    TRY.
        lt_result = mo_praxedo->upsert_equipment_types(
                      VALUE #( FOR t IN lt_types ( external_id = t-EquipmentType name = t-EquipmentTypeName ) ) ).
      CATCH zcprx_cx_error INTO DATA(lx_error).
        lt_result = VALUE #( FOR t IN lt_types ( external_id = t-EquipmentType error = lx_error->get_text( ) ) ).
    ENDTRY.

    lt_exec = VALUE #( FOR t IN lt_types ( EquipmentType = t-EquipmentType
                                           %param        = result_for( it_result = lt_result iv_key = t-EquipmentType ) ) ).
    MODIFY ENTITIES OF zcprx_r_equipmenttype
      ENTITY EquipmentType EXECUTE setSyncResult FROM lt_exec
      FAILED DATA(ls_failed) ##NEEDED.
    COMMIT ENTITIES.

    IF lx_error IS BOUND.
      RAISE EXCEPTION lx_error.
    ENDIF.
    rv_count = lines( lt_types ).
  ENDMETHOD.

  METHOD send_products.
    TYPES tt_type_range TYPE RANGE OF char4.
    DATA lt_create TYPE TABLE FOR CREATE zcprx_r_product\\Product.
    DATA lt_exec   TYPE TABLE FOR ACTION IMPORT zcprx_r_product\\Product~setSyncResult.
    DATA lt_result TYPE zcprx_if_praxedo_api=>tt_id_result.
    DATA lv_errors TYPE i.

    DATA(lr_products) = to_range( it_keys ).
    DATA(lr_types)    = VALUE tt_type_range( FOR ty IN zcprx_cl_config=>get_list( zcprx_cl_config=>c_param-product_types )
                                             ( sign = 'I' option = 'EQ' low = ty ) ).
    DATA(lv_language) = zcprx_cl_mapper=>language( ).
    " mind. 1 -> keine Endlosschleife bei Fehlkonfiguration
    DATA(lv_size)     = zcprx_cl_config=>get_int( iv_param = zcprx_cl_config=>c_param-package_size iv_min = 1 ).

    SELECT p~Product, p~ProductGroup, p~BaseUnit, d~ProductDescription
      FROM I_Product AS p
      LEFT OUTER JOIN I_ProductDescription AS d
        ON  d~Product  = p~Product
        AND d~Language = @lv_language
      WHERE p~Product             IN @lr_products
        AND p~ProductType         IN @lr_types
        AND p~IsMarkedForDeletion  = @abap_false
      ORDER BY p~Product
      INTO TABLE @DATA(lt_products).

    SELECT Product FROM zcprx_r_product INTO TABLE @DATA(lt_existing).
    SORT lt_existing BY Product.

    DATA(lv_from) = 1.
    WHILE lv_from <= lines( lt_products ).
      DATA(lv_to) = nmin( val1 = lv_from + lv_size - 1 val2 = lines( lt_products ) ).
      CLEAR: lt_create, lt_exec, lt_result.

      " 1) Paket an Praxedo
      TRY.
          lt_result = mo_praxedo->upsert_products( VALUE #(
                        FOR i = lv_from WHILE i <= lv_to
                        LET p = lt_products[ i ] IN
                        ( external_id = p-Product
                          name        = p-ProductDescription
                          group_id    = p-ProductGroup
                          unit        = p-BaseUnit ) ) ).
        CATCH zcprx_cx_error INTO DATA(lx_error).
          lv_errors += 1.
          IF io_log IS BOUND.
            io_log->error( |Artikelpaket { lv_from }-{ lv_to }: { lx_error->get_text( ) }| ).
          ENDIF.
          lt_result = VALUE #( FOR i = lv_from WHILE i <= lv_to
                               ( external_id = lt_products[ i ]-Product error = lx_error->get_text( ) ) ).
      ENDTRY.

      " 2) Sync-Status im RAP-BO fortschreiben (neue Artikel anlegen)
      DO lv_to - lv_from + 1 TIMES.
        DATA(ls_product) = lt_products[ lv_from + sy-index - 1 ].
        READ TABLE lt_existing WITH KEY Product = ls_product-Product BINARY SEARCH TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND VALUE #( %cid = |P{ sy-index }| Product = ls_product-Product
                          Status = zcprx_if_constants=>sync_status-new ) TO lt_create.
        ENDIF.
        APPEND VALUE #( Product = ls_product-Product
                        %param  = result_for( it_result = lt_result iv_key = ls_product-Product ) ) TO lt_exec.
      ENDDO.

      IF lt_create IS NOT INITIAL.
        MODIFY ENTITIES OF zcprx_r_product
          ENTITY Product CREATE FIELDS ( Product Status ) WITH lt_create
          FAILED DATA(ls_create_failed) ##NEEDED.
        COMMIT ENTITIES.
      ENDIF.

      MODIFY ENTITIES OF zcprx_r_product
        ENTITY Product EXECUTE setSyncResult FROM lt_exec
        FAILED DATA(ls_exec_failed) ##NEEDED.
      COMMIT ENTITIES.

      rv_count += lv_to - lv_from + 1.
      lv_from = lv_to + 1.
    ENDWHILE.

    IF lv_errors > 0 AND it_keys IS NOT INITIAL.
      zcprx_cx_error=>raise( 'Artikel konnte nicht an Praxedo übertragen werden' ).
    ENDIF.
  ENDMETHOD.

  METHOD to_range.
    rt_range = VALUE #( FOR k IN it_keys ( sign = 'I' option = 'EQ' low = k ) ).
  ENDMETHOD.

  METHOD result_for.
    " Liefert Praxedo keine Einzelergebnisse (leere Antwort = Bulk ok),
    " gilt jeder Eintrag als übertragen; fehlt nur dieser Eintrag -> Fehler.
    READ TABLE it_result INTO DATA(ls_result) WITH KEY external_id = CONV string( iv_key ).
    IF sy-subrc <> 0 AND it_result IS NOT INITIAL.
      rs_result = VALUE #( Status = zcprx_if_constants=>sync_status-error MessageText = 'Keine Rückmeldung von Praxedo zu diesem Eintrag' ).
    ELSEIF ls_result-error IS NOT INITIAL.
      rs_result = VALUE #( Status = zcprx_if_constants=>sync_status-error MessageText = ls_result-error ).
    ELSE.
      rs_result = VALUE #( PraxedoId   = COND #( WHEN ls_result-id IS NOT INITIAL THEN ls_result-id ELSE iv_key )
                           Status      = zcprx_if_constants=>sync_status-sent
                           MessageText = '' ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
