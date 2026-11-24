CLASS zcprx_cl_outbound DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING io_praxedo TYPE REF TO zcprx_if_praxedo_api OPTIONAL
                io_srvord  TYPE REF TO zcprx_if_srvord_api  OPTIONAL.

    "! Einsatz inkl. Kunde, Location, Equipment nach Praxedo übertragen
    METHODS sync_order
      IMPORTING iv_order_uuid TYPE sysuuid_x16
      RAISING   zcprx_cx_error.

    METHODS delete_order
      IMPORTING iv_praxedo_id TYPE string
      RAISING   zcprx_cx_error.

    "! Serviceauftrag geändert (Event/Delta): Einsätze anlegen/aktualisieren.
    "! Die Übertragung nach Praxedo erfolgt danach automatisch über
    "! markForSync -> Queue -> bgPF -> sync_order.
    METHODS sync_service_order
      IMPORTING iv_service_order TYPE char10
      RAISING   zcprx_cx_error.

  PRIVATE SECTION.
    DATA mo_praxedo TYPE REF TO zcprx_if_praxedo_api.
    DATA mo_srvord  TYPE REF TO zcprx_if_srvord_api.
    DATA mo_mapper  TYPE REF TO zcprx_cl_mapper.

    METHODS set_result
      IMPORTING iv_order_uuid TYPE sysuuid_x16
                iv_praxedo_id TYPE string
                iv_status     TYPE c
                iv_message    TYPE string.
ENDCLASS.

CLASS zcprx_cl_outbound IMPLEMENTATION.

  METHOD constructor.
    mo_praxedo = COND #( WHEN io_praxedo IS BOUND THEN io_praxedo ELSE NEW zcprx_cl_praxedo_api( ) ).
    mo_srvord  = COND #( WHEN io_srvord  IS BOUND THEN io_srvord  ELSE NEW zcprx_cl_srvord_api( ) ).
    mo_mapper  = NEW #( ).
  ENDMETHOD.

  METHOD sync_order.
    DATA lv_equipment_id TYPE string.

    READ ENTITIES OF zcprx_r_order
      ENTITY Order ALL FIELDS WITH VALUE #( ( OrderUUID = iv_order_uuid ) )
      RESULT DATA(lt_order).
    IF lt_order IS INITIAL.
      zcprx_cx_error=>raise( iv_text = |Einsatz { iv_order_uuid } nicht gefunden| iv_permanent = abap_true ).
    ENDIF.
    DATA(ls_order) = lt_order[ 1 ].

    " Zwischenzeitlich storniert/verbucht -> nichts mehr senden
    IF ls_order-Status = zcprx_if_constants=>order_status-cancelled
    OR ls_order-Status = zcprx_if_constants=>order_status-processed.
      RETURN.
    ENDIF.
    IF ls_order-SoldToParty IS INITIAL.
      set_result( iv_order_uuid = iv_order_uuid iv_praxedo_id = `` iv_status = zcprx_if_constants=>order_status-error
                  iv_message    = `Auftraggeber fehlt` ).
      zcprx_cx_error=>raise( iv_text = 'Auftraggeber fehlt' iv_permanent = abap_true ).
    ENDIF.

    TRY.
        " 1) Kunde
        DATA(lv_customer_id) = mo_praxedo->upsert_customer( mo_mapper->customer( ls_order-SoldToParty ) ).
        lv_customer_id = COND #( WHEN lv_customer_id IS NOT INITIAL THEN lv_customer_id ELSE ls_order-SoldToParty ).

        " 2) Location (Einsatzort)
        DATA(ls_location)    = mo_mapper->location( iv_ship_to     = ls_order-ShipToParty
                                                    iv_sold_to     = ls_order-SoldToParty
                                                    iv_customer_id = lv_customer_id ).
        DATA(lv_location_id) = mo_praxedo->upsert_location( ls_location ).
        lv_location_id = COND #( WHEN lv_location_id IS NOT INITIAL THEN lv_location_id ELSE ls_location-external_id ).

        " 3) Equipment (optional)
        IF ls_order-Equipment IS NOT INITIAL.
          lv_equipment_id = mo_praxedo->upsert_equipment( mo_mapper->equipment( iv_equipment   = ls_order-Equipment
                                                                                iv_customer_id = lv_customer_id
                                                                                iv_location_id = lv_location_id ) ).
          lv_equipment_id = COND #( WHEN lv_equipment_id IS NOT INITIAL THEN lv_equipment_id ELSE ls_order-Equipment ).
        ENDIF.

        " 4) Auftrag / Einsatz
        DATA(lv_praxedo_id) = mo_praxedo->upsert_order( VALUE #(
                                id                 = ls_order-PraxedoId
                                external_id        = |{ ls_order-ServiceOrder }-{ ls_order-ServiceOrderItem }|
                                service_order      = ls_order-ServiceOrder
                                service_order_item = ls_order-ServiceOrderItem
                                description        = ls_order-Description
                                customer_id        = lv_customer_id
                                location_id        = lv_location_id
                                equipment_id       = lv_equipment_id
                                technician         = ls_order-Technician
                                planned_start      = zcprx_cl_mapper=>to_iso( ls_order-PlannedStart )
                                planned_end        = zcprx_cl_mapper=>to_iso( ls_order-PlannedEnd ) ) ).

        set_result( iv_order_uuid = iv_order_uuid
                    iv_praxedo_id = lv_praxedo_id
                    iv_status     = zcprx_if_constants=>order_status-sent
                    iv_message    = `` ).

      CATCH zcprx_cx_error INTO DATA(lx_error).
        set_result( iv_order_uuid = iv_order_uuid
                    iv_praxedo_id = ``
                    iv_status     = zcprx_if_constants=>order_status-error
                    iv_message    = lx_error->get_text( ) ).
        RAISE EXCEPTION lx_error.
    ENDTRY.
  ENDMETHOD.

  METHOD delete_order.
    CHECK iv_praxedo_id IS NOT INITIAL.
    mo_praxedo->delete_order( iv_praxedo_id ).
  ENDMETHOD.

  METHOD sync_service_order.
    DATA(st) = zcprx_if_constants=>order_status.
    DATA lt_create TYPE TABLE FOR CREATE zcprx_r_order\\Order.
    DATA lt_update TYPE TABLE FOR UPDATE zcprx_r_order\\Order.
    DATA lv_index  TYPE i.

    DATA(ls_so) = mo_srvord->get_service_order( iv_service_order ).

    " Relevanz: Auftragsarten / Positionstypen (leer = alle)
    DATA(lt_types) = zcprx_cl_config=>get_list( zcprx_cl_config=>c_param-relevant_so_types ).
    IF lt_types IS NOT INITIAL AND NOT line_exists( lt_types[ table_line = CONV string( ls_so-order_type ) ] ).
      RETURN.
    ENDIF.
    DATA(lt_cats) = zcprx_cl_config=>get_list( zcprx_cl_config=>c_param-relevant_item_cats ).

    SELECT OrderUUID, ServiceOrderItem, Status, Description, SoldToParty, ShipToParty,
           Equipment, PlannedStart, PlannedEnd
      FROM zcprx_r_order
      WHERE ServiceOrder = @iv_service_order
        AND Status      <> @st-cancelled
      INTO TABLE @DATA(lt_existing).

    LOOP AT ls_so-items INTO DATA(ls_item).
      IF lt_cats IS NOT INITIAL AND NOT line_exists( lt_cats[ table_line = CONV string( ls_item-item_category ) ] ).
        CONTINUE.
      ENDIF.

      DATA(lv_descr) = CONV char80( COND string( WHEN ls_item-description IS NOT INITIAL
                                                 THEN ls_item-description ELSE ls_so-description ) ).
      DATA(lv_start) = COND utclong( WHEN ls_item-planned_start IS NOT INITIAL THEN ls_item-planned_start ELSE ls_so-planned_start ).
      DATA(lv_end)   = COND utclong( WHEN ls_item-planned_end   IS NOT INITIAL THEN ls_item-planned_end   ELSE ls_so-planned_end ).

      READ TABLE lt_existing INTO DATA(ls_existing) WITH KEY ServiceOrderItem = ls_item-service_order_item.
      IF sy-subrc <> 0.
        lv_index += 1.
        APPEND VALUE #( %cid             = |SO{ lv_index }|
                        ServiceOrder     = ls_so-service_order
                        ServiceOrderItem = ls_item-service_order_item
                        Description      = lv_descr
                        SoldToParty      = ls_so-sold_to_party
                        ShipToParty      = ls_so-ship_to_party
                        Equipment        = ls_so-equipment
                        PlannedStart     = lv_start
                        PlannedEnd       = lv_end ) TO lt_create.
        CONTINUE.
      ENDIF.

      " Rückgemeldet/verbucht: keine Änderung mehr aus SAP übernehmen
      IF ls_existing-Status = st-received OR ls_existing-Status = st-processed.
        CONTINUE.
      ENDIF.
      IF ls_existing-Status = st-in_process.
        zcprx_cx_error=>raise( |Einsatz zu { iv_service_order }/{ ls_item-service_order_item } in Verarbeitung – Wiederholung folgt| ).
      ENDIF.

      " nur geänderte Felder übernehmen (Trigger für markForSync)
      APPEND VALUE #( OrderUUID = ls_existing-OrderUUID ) TO lt_update ASSIGNING FIELD-SYMBOL(<ls_update>).
      IF ls_existing-Description <> lv_descr.
        <ls_update>-Description = lv_descr.            <ls_update>-%control-Description = if_abap_behv=>mk-on.
      ENDIF.
      IF ls_existing-SoldToParty <> ls_so-sold_to_party.
        <ls_update>-SoldToParty = ls_so-sold_to_party. <ls_update>-%control-SoldToParty = if_abap_behv=>mk-on.
      ENDIF.
      IF ls_existing-ShipToParty <> ls_so-ship_to_party.
        <ls_update>-ShipToParty = ls_so-ship_to_party. <ls_update>-%control-ShipToParty = if_abap_behv=>mk-on.
      ENDIF.
      IF ls_existing-Equipment <> ls_so-equipment.
        <ls_update>-Equipment = ls_so-equipment.       <ls_update>-%control-Equipment = if_abap_behv=>mk-on.
      ENDIF.
      IF ls_existing-PlannedStart <> lv_start.
        <ls_update>-PlannedStart = lv_start.           <ls_update>-%control-PlannedStart = if_abap_behv=>mk-on.
      ENDIF.
      IF ls_existing-PlannedEnd <> lv_end.
        <ls_update>-PlannedEnd = lv_end.               <ls_update>-%control-PlannedEnd = if_abap_behv=>mk-on.
      ENDIF.
      IF <ls_update>-%control IS INITIAL.
        DELETE lt_update INDEX lines( lt_update ).     " nichts geändert
      ENDIF.
    ENDLOOP.

    " Positionen, die im Serviceauftrag entfallen sind -> Einsatz stornieren
    " (nur solange in Praxedo noch nichts zurückgemeldet wurde)
    DATA lt_cancel TYPE TABLE FOR ACTION IMPORT zcprx_r_order\\Order~cancel.
    LOOP AT lt_existing INTO ls_existing
         WHERE Status = st-new OR Status = st-sent OR Status = st-error.
      IF NOT line_exists( ls_so-items[ service_order_item = ls_existing-ServiceOrderItem ] ).
        APPEND VALUE #( OrderUUID = ls_existing-OrderUUID ) TO lt_cancel.
      ENDIF.
    ENDLOOP.

    CHECK lt_create IS NOT INITIAL OR lt_update IS NOT INITIAL OR lt_cancel IS NOT INITIAL.

    MODIFY ENTITIES OF zcprx_r_order
      ENTITY Order
        CREATE FIELDS ( ServiceOrder ServiceOrderItem Description SoldToParty ShipToParty
                        Equipment PlannedStart PlannedEnd ) WITH lt_create
        UPDATE FROM lt_update
        EXECUTE cancel FROM lt_cancel
      FAILED DATA(ls_failed)
      REPORTED DATA(ls_reported) ##NEEDED.

    IF ls_failed IS NOT INITIAL.
      ROLLBACK ENTITIES.
      zcprx_cx_error=>raise( |Einsätze zu Serviceauftrag { iv_service_order } konnten nicht gespeichert werden| ).
    ENDIF.

    COMMIT ENTITIES RESPONSE OF zcprx_r_order
      FAILED DATA(ls_commit_failed)
      REPORTED DATA(ls_commit_reported) ##NEEDED.
    IF ls_commit_failed IS NOT INITIAL.
      zcprx_cx_error=>raise( |Commit für Serviceauftrag { iv_service_order } fehlgeschlagen| ).
    ENDIF.
  ENDMETHOD.

  METHOD set_result.
    MODIFY ENTITIES OF zcprx_r_order
      ENTITY Order EXECUTE setSyncResult
      FROM VALUE #( ( OrderUUID = iv_order_uuid
                      %param    = VALUE #( PraxedoId   = iv_praxedo_id
                                           Status      = iv_status
                                           MessageText = iv_message ) ) )
      FAILED DATA(ls_failed) ##NEEDED.
    COMMIT ENTITIES.
  ENDMETHOD.

ENDCLASS.
