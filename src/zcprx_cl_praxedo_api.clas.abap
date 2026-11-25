CLASS zcprx_cl_praxedo_api DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES zcprx_if_praxedo_api.

    CONSTANTS c_comm_scenario TYPE c LENGTH 30 VALUE 'ZCPRX_CS_PRAXEDO'.
    CONSTANTS c_service_soap  TYPE c LENGTH 40 VALUE 'ZCPRX_OS_PRX_SOAP_REST'.
    CONSTANTS c_service_rest  TYPE c LENGTH 40 VALUE 'ZCPRX_OS_PRX_RESTV1_REST'.

    CONSTANTS:
      BEGIN OF c_manager,
        event      TYPE string VALUE `BusinessEventManager`,
        activity   TYPE string VALUE `ActivityManager`,
        customer   TYPE string VALUE `CustomerManager`,
        location   TYPE string VALUE `LocationManager`,
        equipment  TYPE string VALUE `EquipmentManager`,
        eq_type    TYPE string VALUE `EquipmentTypeManager`,
        item_cat   TYPE string VALUE `ItemCategoryManager`,
        item       TYPE string VALUE `ItemManager`,
      END OF c_manager.

    CONSTANTS c_ns_event TYPE string VALUE `http://ws.praxedo.com/v6/businessEvent`.
    CONSTANTS c_ns_model TYPE string VALUE `http://ws.praxedo.com/v6/customermodel`.
    CONSTANTS c_ns_soap  TYPE string VALUE `http://www.w3.org/2003/05/soap-envelope`.
    CONSTANTS c_ns_xsi   TYPE string VALUE `http://www.w3.org/2001/XMLSchema-instance`.

    "! businessEvent-Knoten -> DTO (ohne Zeiten). Öffentlich für Unit-Tests.
    CLASS-METHODS map_event
      IMPORTING io_xml          TYPE REF TO zcprx_cl_xml
                iv_node         TYPE i
                iv_uuid_key     TYPE csequence DEFAULT 'uuid'
      RETURNING VALUE(rs_order) TYPE zcprx_if_praxedo_api=>ty_completed_order.

    "! Praxedo-UUID im Einsatz suchen: Element "uuid" oder Extension, deren
    "! Schlüssel iv_key enthält, sonst UUID-Muster in einem Extension-Wert
    CLASS-METHODS extract_uuid
      IMPORTING io_xml         TYPE REF TO zcprx_cl_xml
                iv_node        TYPE i
                iv_key         TYPE csequence DEFAULT 'uuid'
      RETURNING VALUE(rv_uuid) TYPE string.

    "! Praxedo-Datum (xs:dateTime mit Z oder Offset) -> ISO UTC mit Z
    CLASS-METHODS normalize_date
      IMPORTING iv_value        TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    "! Pfad relativ zum Arrangement: Das Arrangement liefert "/" als Pfad, und
    "! SET_URI_PATH hängt an. Ein führender "/" ergäbe "//eTech/…", das Praxedo
    "! mit einer HTML-Fehlerseite (HTTP 500) ablehnt. Doppelte "/" werden entfernt.
    CLASS-METHODS relative_path
      IMPORTING iv_path        TYPE string
      RETURNING VALUE(rv_path) TYPE string.

    "! Diagnose: rohe SOAP-Antwort von getEvents (Konsole)
    METHODS get_event_raw
      IMPORTING iv_id         TYPE string
      RETURNING VALUE(rv_xml) TYPE string
      RAISING   zcprx_cx_error.

  PRIVATE SECTION.
    TYPES tt_string TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_event_times,
        event_id TYPE string,
        times    TYPE zcprx_if_praxedo_api=>tt_time,
      END OF ty_event_times,
      tt_event_times TYPE HASHED TABLE OF ty_event_times WITH UNIQUE KEY event_id.

    DATA mv_last_raw TYPE string.

    METHODS soap
      IMPORTING iv_manager    TYPE string
                iv_operation  TYPE string
                iv_namespace  TYPE string
                iv_body       TYPE string
      RETURNING VALUE(ro_xml) TYPE REF TO zcprx_cl_xml
      RAISING   zcprx_cx_error.

    METHODS client
      IMPORTING iv_service       TYPE csequence
      RETURNING VALUE(ro_client) TYPE REF TO if_web_http_client
      RAISING   zcprx_cx_error.

    "! resultCode des <return> prüfen (0 = OK), sonst Ausnahme
    METHODS check_return
      IMPORTING io_xml           TYPE REF TO zcprx_cl_xml
                iv_context       TYPE csequence
      RETURNING VALUE(rv_return) TYPE i
      RAISING   zcprx_cx_error.

    "! Anlage-Ergebnis mit genau einem Eintrag -> ID
    METHODS single_result
      IMPORTING io_xml       TYPE REF TO zcprx_cl_xml
                iv_context   TYPE csequence
                iv_default   TYPE string
      RETURNING VALUE(rv_id) TYPE string
      RAISING   zcprx_cx_error.

    "! Anlage-Ergebnis mit n Einträgen (Reihenfolge = Anfrage)
    METHODS batch_results
      IMPORTING io_xml           TYPE REF TO zcprx_cl_xml
                it_ids           TYPE tt_string
      RETURNING VALUE(rt_result) TYPE zcprx_if_praxedo_api=>tt_id_result.

    "! createItems/-ItemCategories/-EquipmentTypes paketweise
    METHODS send_batches
      IMPORTING iv_manager       TYPE string
                iv_operation     TYPE string
                iv_element       TYPE string
                it_ids           TYPE tt_string
                it_xml           TYPE tt_string
      RETURNING VALUE(rt_result) TYPE zcprx_if_praxedo_api=>tt_id_result.

    METHODS event_options
      RETURNING VALUE(rv_xml) TYPE string.

    METHODS event_exists
      IMPORTING iv_id            TYPE string
      RETURNING VALUE(rv_exists) TYPE abap_bool
      RAISING   zcprx_cx_error.

    METHODS build_event
      IMPORTING is_order      TYPE zcprx_if_praxedo_api=>ty_order
                iv_code       TYPE string
      RETURNING VALUE(rv_xml) TYPE string
      RAISING   zcprx_cx_error.

    METHODS schedule
      IMPORTING is_order TYPE zcprx_if_praxedo_api=>ty_order
                iv_code  TYPE string
      RAISING   zcprx_cx_error.

    "! Zeiten je Einsatz über ActivityManager.searchActivitiesByBusinessEvent
    METHODS get_times
      IMPORTING it_event_ids    TYPE tt_string
      RETURNING VALUE(rt_times) TYPE tt_event_times
      RAISING   zcprx_cx_error.

    METHODS batch_size
      RETURNING VALUE(rv_size) TYPE i.

    METHODS el
      IMPORTING iv_name       TYPE csequence
                iv_value      TYPE csequence
      RETURNING VALUE(rv_xml) TYPE string.
ENDCLASS.

CLASS zcprx_cl_praxedo_api IMPLEMENTATION.

  METHOD zcprx_if_praxedo_api~upsert_customer.
    " CustomerManager.createCustomers legt an oder aktualisiert (gleiche id)
    DATA(lv_xml) = |<customers>| &&
                   el( iv_name = `address` iv_value = is_customer-address-street ) &&
                   el( iv_name = `city`    iv_value = is_customer-address-city ) &&
                   COND string( WHEN is_customer-phone IS NOT INITIAL
                                THEN |<contacts>{ el( iv_name = `coordinates` iv_value = is_customer-phone ) }| &&
                                     |<flags>0</flags><type>PHONE</type></contacts>| ) &&
                   el( iv_name = `country` iv_value = is_customer-address-country ) &&
                   el( iv_name = `id`      iv_value = is_customer-external_id ) &&
                   el( iv_name = `name`    iv_value = is_customer-name ) &&
                   el( iv_name = `zipCode` iv_value = is_customer-address-zip_code ) &&
                   |</customers>|.
    rv_id = single_result( io_xml     = soap( iv_manager   = c_manager-customer
                                              iv_operation = `createCustomers`
                                              iv_namespace = c_ns_model
                                              iv_body      = lv_xml )
                           iv_context = |Kunde { is_customer-external_id }|
                           iv_default = is_customer-external_id ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~upsert_location.
    DATA(lv_xml) = |<locations>| &&
                   el( iv_name = `address`  iv_value = is_location-address-street ) &&
                   el( iv_name = `city`     iv_value = is_location-address-city ) &&
                   el( iv_name = `country`  iv_value = is_location-address-country ) &&
                   el( iv_name = `customer` iv_value = is_location-customer_id ) &&
                   el( iv_name = `id`       iv_value = is_location-external_id ) &&
                   el( iv_name = `name`     iv_value = is_location-name ) &&
                   el( iv_name = `zipCode`  iv_value = is_location-address-zip_code ) &&
                   |</locations>|.
    rv_id = single_result( io_xml     = soap( iv_manager   = c_manager-location
                                              iv_operation = `createLocations`
                                              iv_namespace = c_ns_model
                                              iv_body      = lv_xml )
                           iv_context = |Einsatzort { is_location-external_id }|
                           iv_default = is_location-external_id ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~upsert_equipment.
    DATA(lv_xml) = |<equipments>| &&
                   el( iv_name  = `description`
                       iv_value = COND string( WHEN is_equipment-serial_number IS NOT INITIAL
                                               THEN |SN { is_equipment-serial_number }| ) ) &&
                   el( iv_name = `id`       iv_value = is_equipment-external_id ) &&
                   el( iv_name = `location` iv_value = is_equipment-location_id ) &&
                   el( iv_name = `name`     iv_value = is_equipment-name ) &&
                   el( iv_name = `type`     iv_value = is_equipment-type_id ) &&
                   |</equipments>|.
    rv_id = single_result( io_xml     = soap( iv_manager   = c_manager-equipment
                                              iv_operation = `createEquipments`
                                              iv_namespace = c_ns_model
                                              iv_body      = lv_xml )
                           iv_context = |Equipment { is_equipment-external_id }|
                           iv_default = is_equipment-external_id ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~upsert_order.
    DATA(lv_code)  = COND string( WHEN is_order-id IS NOT INITIAL THEN is_order-id ELSE is_order-external_id ).
    DATA(lv_event) = build_event( is_order = is_order iv_code = lv_code ).

    " Vorhanden? (auch nach einem Timeout, bei dem die Anlage schon geklappt hat)
    IF event_exists( lv_code ) = abap_true.
      check_return( io_xml     = soap( iv_manager   = c_manager-event
                                       iv_operation = `updateEvent`
                                       iv_namespace = c_ns_event
                                       iv_body      = |<event>{ lv_event }</event>| )
                    iv_context = |Einsatz { lv_code } ändern| ).
    ELSE.
      lv_code = single_result( io_xml     = soap( iv_manager   = c_manager-event
                                                  iv_operation = `createEvents`
                                                  iv_namespace = c_ns_event
                                                  iv_body      = |<events>{ lv_event }</events>| )
                               iv_context = |Einsatz { lv_code } anlegen|
                               iv_default = lv_code ).
    ENDIF.

    IF is_order-technician IS NOT INITIAL.
      schedule( is_order = is_order iv_code = lv_code ).
    ENDIF.
    rv_id = lv_code.
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~delete_order.
    CHECK iv_id IS NOT INITIAL.
    " bereits gelöscht -> nichts zu tun (idempotent)
    IF event_exists( iv_id ) = abap_false.
      RETURN.
    ENDIF.

    IF to_upper( zcprx_cl_config=>get( zcprx_cl_config=>c_param-prx_cancel_mode ) ) = 'DELETE'.
      check_return( io_xml     = soap( iv_manager   = c_manager-event
                                       iv_operation = `deleteEvents`
                                       iv_namespace = c_ns_event
                                       iv_body      = el( iv_name = `eventsToDelete` iv_value = iv_id ) )
                    iv_context = |Einsatz { iv_id } löschen| ).
    ELSE.
      check_return( io_xml     = soap( iv_manager   = c_manager-event
                                       iv_operation = `cancelEvent`
                                       iv_namespace = c_ns_event
                                       iv_body      = el( iv_name = `businessEventId` iv_value = iv_id ) &&
                                                      |<cancellationRequest>| &&
                                                      el( iv_name = `message` iv_value = `Storniert in SAP` ) &&
                                                      |</cancellationRequest>| )
                    iv_context = |Einsatz { iv_id } stornieren| ).
    ENDIF.
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~get_order.
    DATA(lo_xml) = soap( iv_manager   = c_manager-event
                         iv_operation = `getEvents`
                         iv_namespace = c_ns_event
                         iv_body      = el( iv_name = `requestedEvents` iv_value = iv_id ) && event_options( ) ).
    DATA(lv_return) = lo_xml->find( `return` ).
    DATA(lt_events) = lo_xml->children( iv_parent = lv_return iv_name = `entities` ).
    IF lt_events IS INITIAL.
      zcprx_cx_error=>raise( iv_text      = |Einsatz { iv_id } in Praxedo nicht gefunden { lo_xml->child_value( iv_parent = lv_return iv_path = `message` ) }|
                                 iv_permanent = abap_true ).
    ENDIF.

    rs_order = map_event( io_xml      = lo_xml
                          iv_node     = lt_events[ 1 ]
                          iv_uuid_key = zcprx_cl_config=>get( zcprx_cl_config=>c_param-prx_uuid_key ) ).
    DATA(lt_times) = get_times( VALUE #( ( rs_order-id ) ) ).
    rs_order-times = VALUE #( lt_times[ event_id = rs_order-id ]-times OPTIONAL ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~get_completed_orders.
    DATA lt_ids TYPE tt_string.
    DATA(lv_size)     = batch_size( ).
    DATA(lv_until)    = zcprx_cl_mapper=>to_iso( utclong_current( ) ).
    DATA(lv_uuid_key) = zcprx_cl_config=>get( zcprx_cl_config=>c_param-prx_uuid_key ).

    " Status: abgeschlossen (Zeiten/Material) + Berichtsstatus (VALIDATED)
    DATA(lt_status)        = zcprx_cl_config=>get_list( zcprx_cl_config=>c_param-completed_statuses ).
    DATA(lt_report_status) = zcprx_cl_config=>get_list( zcprx_cl_config=>c_param-report_statuses ).
    APPEND LINES OF lt_report_status TO lt_status.
    SORT lt_status.
    DELETE ADJACENT DUPLICATES FROM lt_status.
    DATA(lv_status_xml) = REDUCE string( INIT s = `` FOR st IN lt_status
                                         NEXT s = s && el( iv_name = `statusConstraint` iv_value = to_upper( st ) ) ).

    DATA(lt_dates) = zcprx_cl_config=>get_list( zcprx_cl_config=>c_param-prx_search_dates ).
    IF lt_dates IS INITIAL.
      zcprx_cx_error=>raise( iv_text = 'PRX_SEARCH_DATES nicht gepflegt' iv_permanent = abap_true ).
    ENDIF.

    " Je Datumsart (z. B. Abschluss, Validierung) seitenweise suchen
    LOOP AT lt_dates INTO DATA(lv_date_name).
      DATA(lv_first) = 0.
      DO.
        DATA(lo_xml) = soap(
          iv_manager   = c_manager-event
          iv_operation = `searchEvents`
          iv_namespace = c_ns_event
          iv_body      = |<request><dateConstraints>| &&
                         el( iv_name = `dateRange` iv_value = iv_since ) &&
                         el( iv_name = `dateRange` iv_value = lv_until ) &&
                         el( iv_name = `name`      iv_value = lv_date_name ) &&
                         |</dateConstraints>{ lv_status_xml }</request>| &&
                         |<batchSize>{ lv_size }</batchSize><firstResultIndex>{ lv_first }</firstResultIndex>| &&
                         event_options( ) ).
        DATA(lv_return) = check_return( io_xml = lo_xml iv_context = |Suche Einsätze ({ lv_date_name })| ).
        DATA(lt_events) = lo_xml->children( iv_parent = lv_return iv_name = `entities` ).

        LOOP AT lt_events INTO DATA(lv_event).
          DATA(ls_order) = map_event( io_xml = lo_xml iv_node = lv_event iv_uuid_key = lv_uuid_key ).
          IF ls_order-id IS NOT INITIAL AND NOT line_exists( lt_ids[ table_line = ls_order-id ] ).
            APPEND ls_order-id TO lt_ids.
            APPEND ls_order TO rt_orders.
          ENDIF.
        ENDLOOP.

        IF lines( lt_events ) < lv_size.
          EXIT.
        ENDIF.
        lv_first += lv_size.
      ENDDO.
    ENDLOOP.

    CHECK lt_ids IS NOT INITIAL.
    DATA(lt_times) = get_times( lt_ids ).
    LOOP AT rt_orders ASSIGNING FIELD-SYMBOL(<ls_order>).
      <ls_order>-times = VALUE #( lt_times[ event_id = <ls_order>-id ]-times OPTIONAL ).
    ENDLOOP.
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~upsert_products.
    DATA lt_ids TYPE tt_string.
    DATA lt_xml TYPE tt_string.
    DATA(lv_default_cat) = zcprx_cl_config=>get( zcprx_cl_config=>c_param-default_item_cat ).

    LOOP AT it_products INTO DATA(ls_product).
      DATA(lv_category) = COND string( WHEN ls_product-group_id IS NOT INITIAL THEN ls_product-group_id ELSE lv_default_cat ).
      IF lv_category IS INITIAL.
        " itemCategoryId ist in Praxedo Pflicht
        APPEND VALUE #( external_id = ls_product-external_id
                        error       = `Keine Artikelgruppe (Konfig DEFAULT_ITEM_CAT)` ) TO rt_result.
        CONTINUE.
      ENDIF.
      DATA(lv_item_xml) = el( iv_name = `id`             iv_value = ls_product-external_id ) &&
                          el( iv_name = `itemCategoryId` iv_value = lv_category ) &&
                          el( iv_name = `name`           iv_value = COND string( WHEN ls_product-name IS NOT INITIAL
                                                                                 THEN ls_product-name ELSE ls_product-external_id ) ) &&
                          el( iv_name = `reference`      iv_value = ls_product-external_id ).
      APPEND ls_product-external_id TO lt_ids.
      APPEND lv_item_xml TO lt_xml.
    ENDLOOP.

    DATA(lt_sent) = send_batches( iv_manager   = c_manager-item
                                  iv_operation = `createItems`
                                  iv_element   = `items`
                                  it_ids       = lt_ids
                                  it_xml       = lt_xml ).
    APPEND LINES OF lt_sent TO rt_result.
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~upsert_product_groups.
    rt_result = send_batches(
      iv_manager   = c_manager-item_cat
      iv_operation = `createItemCategories`
      iv_element   = `itemCategories`
      it_ids       = VALUE #( FOR g IN it_groups ( g-external_id ) )
      it_xml       = VALUE #( FOR g IN it_groups
                              ( el( iv_name = `description` iv_value = g-name ) &&
                                el( iv_name = `id`          iv_value = g-external_id ) &&
                                el( iv_name = `name`        iv_value = COND string( WHEN g-name IS NOT INITIAL
                                                                                    THEN g-name ELSE g-external_id ) ) ) ) ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~upsert_equipment_types.
    rt_result = send_batches(
      iv_manager   = c_manager-eq_type
      iv_operation = `createEquipmentTypes`
      iv_element   = `equipmentTypes`
      it_ids       = VALUE #( FOR t IN it_types ( t-external_id ) )
      it_xml       = VALUE #( FOR t IN it_types
                              ( el( iv_name = `id`   iv_value = t-external_id ) &&
                                el( iv_name = `name` iv_value = COND string( WHEN t-name IS NOT INITIAL
                                                                             THEN t-name ELSE t-external_id ) ) ) ) ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~get_report_pdf.
    DATA lo_client TYPE REF TO if_web_http_client.
    DATA(lv_template) = zcprx_cl_config=>get( zcprx_cl_config=>c_param-report_path ).
    IF lv_template CS '{UUID}' AND iv_uuid IS INITIAL.
      zcprx_cx_error=>raise( iv_text      = |Praxedo-UUID zu Einsatz { iv_code } unbekannt (Konfig PRX_UUID_KEY / PRX_POPULATE prüfen)|
                                 iv_permanent = abap_true ).
    ENDIF.
    DATA(lv_path) = replace( val = lv_template sub = '{UUID}' with = iv_uuid occ = 0 ).
    lv_path = replace( val  = lv_path sub = '{CODE}'
                       with = escape( val = iv_code format = cl_abap_format=>e_url_full ) occ = 0 ).
    lv_path = relative_path( |{ zcprx_cl_config=>get( zcprx_cl_config=>c_param-prx_rest_path ) }{ lv_path }| ).

    TRY.
        lo_client = client( c_service_rest ).
        DATA(lo_request) = lo_client->get_http_request( ).
        lo_request->set_uri_path( i_uri_path = lv_path ).
        lo_request->set_header_field( i_name = 'Accept' i_value = 'application/pdf' ).
        DATA(lo_response) = lo_client->execute( if_web_http_client=>get ).
        DATA(ls_status)   = lo_response->get_status( ).
        rv_pdf            = lo_response->get_binary( ).
        lo_client->close( ).
      CATCH cx_web_http_client_error cx_web_message_error INTO DATA(lx_http).
        IF lo_client IS BOUND.
          TRY.
              lo_client->close( ).
            CATCH cx_web_http_client_error ##NO_HANDLER.
          ENDTRY.
        ENDIF.
        zcprx_cx_error=>raise( iv_text = |Bericht { iv_code }: Abruf fehlgeschlagen| ix_previous = lx_http ).
    ENDTRY.

    IF ls_status-code <> 200.
      zcprx_cx_error=>raise( iv_text      = |Bericht { iv_code }: HTTP { ls_status-code } { lv_path }|
                                 iv_permanent = zcprx_cx_error=>is_permanent_http( ls_status-code ) ).
    ENDIF.
    " PDF beginnt mit "%PDF"
    IF xstrlen( rv_pdf ) < 4 OR rv_pdf(4) <> CONV xstring( '25504446' ).
      zcprx_cx_error=>raise( iv_text = |Bericht { iv_code }: Antwort ist kein PDF| ).
    ENDIF.
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~ping.
    " SOAP: Antwort auf getEvents (auch "nicht gefunden") beweist Erreichbarkeit + Anmeldung
    soap( iv_manager   = c_manager-event
          iv_operation = `getEvents`
          iv_namespace = c_ns_event
          iv_body      = el( iv_name = `requestedEvents` iv_value = `CPRX-PING` ) ).
    " REST v1: nur Arrangement prüfen (Bericht braucht eine echte UUID)
    DATA(lo_rest) = client( c_service_rest ).
    TRY.
        lo_rest->close( ).
      CATCH cx_web_http_client_error ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.

  METHOD get_event_raw.
    soap( iv_manager   = c_manager-event
          iv_operation = `getEvents`
          iv_namespace = c_ns_event
          iv_body      = el( iv_name = `requestedEvents` iv_value = iv_id ) && event_options( ) ).
    rv_xml = mv_last_raw.
  ENDMETHOD.

  METHOD map_event.
    rs_order-id     = io_xml->child_value( iv_parent = iv_node iv_path = `id` ).
    rs_order-status = to_upper( io_xml->child_value( iv_parent = iv_node iv_path = `status` ) ).
    rs_order-uuid   = extract_uuid( io_xml = io_xml iv_node = iv_node iv_key = iv_uuid_key ).
    rs_order-external_id = rs_order-id.

    " Code "<Serviceauftrag>-<Position>" (so vom Adapter vergeben)
    FIND PCRE `^(\d{1,10})-(\d{1,6})$` IN rs_order-id
         SUBMATCHES rs_order-service_order rs_order-service_order_item.

    DATA(lv_completion) = io_xml->child( iv_parent = iv_node iv_name = `completionData` ).
    CHECK lv_completion > 0.

    " Abschlusszeitpunkt aus den Lebenszyklus-Übergängen (spätester COMPLETED-Eintrag)
    LOOP AT io_xml->children( iv_parent = lv_completion iv_name = `lifecycleTransitionDates` ) INTO DATA(lv_transition).
      DATA(lv_name) = to_upper( io_xml->child_value( iv_parent = lv_transition iv_path = `name` ) ).
      DATA(lv_date) = normalize_date( io_xml->child_value( iv_parent = lv_transition iv_path = `date` ) ).
      IF lv_name CS 'COMPLET' AND lv_date > rs_order-completed_at.
        rs_order-completed_at = lv_date.
      ENDIF.
    ENDLOOP.

    " Material = verwendete Artikel (Artikel-ID = SAP-Produkt, so übertragen)
    LOOP AT io_xml->children( iv_parent = lv_completion iv_name = `usedItems` ) INTO DATA(lv_item).
      DATA(lv_line) = sy-tabix.
      DATA(lv_qty)  = CONV decfloat34( 0 ).
      TRY.
          lv_qty = CONV decfloat34( io_xml->child_value( iv_parent = lv_item iv_path = `quantity` ) ).
        CATCH cx_sy_conversion_error ##NO_HANDLER.
      ENDTRY.
      DATA(lv_store) = io_xml->child_value( iv_parent = lv_item iv_path = `storeId` ).
      DATA lv_plant TYPE string.
      DATA lv_sloc  TYPE string.
      CLEAR: lv_plant, lv_sloc.
      " Lager optional als "<Werk>/<Lagerort>" bzw. "<Werk>-<Lagerort>"
      FIND PCRE `^(\w{4})[/-](\w{1,4})$` IN lv_store SUBMATCHES lv_plant lv_sloc.
      APPEND VALUE #( line_id          = |{ lv_line }|
                      product          = io_xml->child_value( iv_parent = lv_item iv_path = `id` )
                      quantity         = lv_qty
                      plant            = lv_plant
                      storage_location = lv_sloc ) TO rs_order-materials.
    ENDLOOP.
    DELETE rs_order-materials WHERE product IS INITIAL OR quantity = 0.
  ENDMETHOD.

  METHOD extract_uuid.
    CONSTANTS lc_uuid TYPE string VALUE `[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}`.
    DATA(lv_key) = to_lower( condense( CONV string( iv_key ) ) ).

    " 1) direktes Element <uuid>
    DATA(lv_direct) = io_xml->value( io_xml->find( iv_name = `uuid` iv_parent = iv_node ) ).
    rv_uuid = match( val = lv_direct pcre = lc_uuid ).
    IF rv_uuid IS NOT INITIAL.
      RETURN.
    ENDIF.

    " 2) Extension mit passendem Schlüssel, 3) beliebige Extension mit UUID-Wert
    DATA(lt_ext) = io_xml->find_all( iv_name = `extensions` iv_parent = iv_node ).
    DO 2 TIMES.
      DATA(lv_pass) = sy-index.
      LOOP AT lt_ext INTO DATA(lv_ext).
        DATA(lv_ext_key) = to_lower( io_xml->child_value( iv_parent = lv_ext iv_path = `key` ) ).
        IF lv_pass = 1 AND ( lv_key IS INITIAL OR lv_ext_key NS lv_key ).
          CONTINUE.
        ENDIF.
        rv_uuid = match( val = io_xml->child_value( iv_parent = lv_ext iv_path = `value` ) pcre = lc_uuid ).
        IF rv_uuid IS NOT INITIAL.
          RETURN.
        ENDIF.
      ENDLOOP.
    ENDDO.
  ENDMETHOD.

  METHOD relative_path.
    rv_path = replace( val = iv_path pcre = `/{2,}` with = `/` occ = 0 ).
    rv_path = shift_left( val = rv_path sub = `/` ).
  ENDMETHOD.

  METHOD normalize_date.
    CHECK iv_value IS NOT INITIAL.
    rv_value = zcprx_cl_mapper=>to_iso( zcprx_cl_mapper=>from_iso( iv_value ) ).
  ENDMETHOD.

  METHOD build_event.
    DATA(lv_type) = zcprx_cl_config=>get( zcprx_cl_config=>c_param-prx_event_type ).
    IF lv_type IS INITIAL.
      zcprx_cx_error=>raise( iv_text = 'Praxedo-Einsatztyp nicht gepflegt (Konfig PRX_EVENT_TYPE)' iv_permanent = abap_true ).
    ENDIF.

    " Dauer in Minuten aus dem Planzeitraum, sonst Standard
    DATA(lv_start)    = zcprx_cl_mapper=>from_iso( is_order-planned_start ).
    DATA(lv_end)      = zcprx_cl_mapper=>from_iso( is_order-planned_end ).
    DATA(lv_duration) = 0.
    IF lv_start IS NOT INITIAL AND lv_end IS NOT INITIAL AND lv_end > lv_start.
      lv_duration = CONV i( utclong_diff( high = lv_end low = lv_start ) / 60 ).
    ENDIF.
    IF lv_duration <= 0.
      lv_duration = zcprx_cl_config=>get_int( iv_param = zcprx_cl_config=>c_param-prx_event_duration iv_min = 1 ).
    ENDIF.

    " Elementreihenfolge laut WSDL (xs:sequence)
    rv_xml = |<coreData><anomaly>false</anomaly>| &&
             el( iv_name = `description`    iv_value = is_order-description ) &&
             el( iv_name = `earliestDate`   iv_value = is_order-planned_start ) &&
             el( iv_name = `expirationDate` iv_value = is_order-planned_end ) &&
             |<priority>0</priority>| &&
             |<referentialData xsi:type="ns:praxedoReferentialData">| &&
             el( iv_name = `customerId`  iv_value = is_order-customer_id ) &&
             el( iv_name = `equipmentId` iv_value = is_order-equipment_id ) &&
             el( iv_name = `locationId`  iv_value = is_order-location_id ) &&
             |</referentialData></coreData>| &&
             el( iv_name = `id` iv_value = iv_code ) &&
             |<qualificationData><type><duration>{ lv_duration }</duration>| &&
             el( iv_name = `id` iv_value = lv_type ) &&
             |</type></qualificationData>|.
  ENDMETHOD.

  METHOD schedule.
    DATA(lv_id_type) = zcprx_cl_config=>get( zcprx_cl_config=>c_param-prx_agent_id_type ).
    check_return(
      io_xml     = soap( iv_manager   = c_manager-event
                         iv_operation = `scheduleEvent`
                         iv_namespace = c_ns_event
                         iv_body      = |<event>{ el( iv_name = `id` iv_value = iv_code ) }<schedulingData>| &&
                                        |<agentId xsi:type="ns:{ lv_id_type }">{ el( iv_name = `id` iv_value = is_order-technician ) }</agentId>| &&
                                        el( iv_name = `schedulingDate`    iv_value = is_order-planned_start ) &&
                                        el( iv_name = `schedulingEndDate` iv_value = is_order-planned_end ) &&
                                        |<useSchedulingHour>{ COND string( WHEN is_order-planned_start IS NOT INITIAL
                                                                           THEN `true` ELSE `false` ) }</useSchedulingHour>| &&
                                        |</schedulingData></event>| )
      iv_context = |Einsatz { iv_code } einplanen ({ is_order-technician })| ).
  ENDMETHOD.

  METHOD event_exists.
    DATA(lo_xml) = soap( iv_manager   = c_manager-event
                         iv_operation = `getEvents`
                         iv_namespace = c_ns_event
                         iv_body      = el( iv_name = `requestedEvents` iv_value = iv_id ) ).
    DATA(lv_return) = lo_xml->find( `return` ).
    LOOP AT lo_xml->children( iv_parent = lv_return iv_name = `entities` ) INTO DATA(lv_event).
      IF lo_xml->child_value( iv_parent = lv_event iv_path = `id` ) = iv_id.
        rv_exists = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD event_options.
    " Kurzformen aus PRX_POPULATE -> businessEvent.populate.<…>
    LOOP AT zcprx_cl_config=>get_list( zcprx_cl_config=>c_param-prx_populate ) INTO DATA(lv_option).
      rv_xml = rv_xml && |<options>{ el( iv_name  = `key`
                                         iv_value = COND string( WHEN lv_option CS '.populate.' OR lv_option CS '.feature.'
                                                                 THEN lv_option
                                                                 ELSE |businessEvent.populate.{ lv_option }| ) ) }</options>|.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_times.
    DATA(lv_size)       = batch_size( ).
    DATA(lv_validated)  = zcprx_cl_config=>get( zcprx_cl_config=>c_param-activity_validated ).
    DATA(lv_default)    = zcprx_cl_config=>get( zcprx_cl_config=>c_param-default_srv_product ).
    DATA(lv_types_xml)  = REDUCE string( INIT s = `` FOR ty IN zcprx_cl_config=>get_list( zcprx_cl_config=>c_param-activity_types )
                                         NEXT s = s && el( iv_name = `activityTypeIds` iv_value = ty ) ).
    " Zuordnung Aktivitätstyp -> SAP-Leistungsartikel ("TYP=PRODUKT,…")
    DATA lt_map TYPE HASHED TABLE OF zcprx_cl_config=>ty_default WITH UNIQUE KEY param.
    LOOP AT zcprx_cl_config=>get_list( zcprx_cl_config=>c_param-activity_products ) INTO DATA(lv_pair).
      SPLIT lv_pair AT '=' INTO DATA(lv_map_type) DATA(lv_map_product).
      INSERT VALUE #( param = condense( lv_map_type ) value = condense( lv_map_product ) ) INTO TABLE lt_map.
    ENDLOOP.

    " Einsätze paketweise abfragen
    DATA(lv_count) = lines( it_event_ids ).
    DATA(lv_from)  = 1.
    WHILE lv_from <= lv_count.
      DATA(lv_to)   = nmin( val1 = lv_from + lv_size - 1 val2 = lv_count ).
      DATA(lv_ids)  = ``.
      LOOP AT it_event_ids INTO DATA(lv_event_id) FROM lv_from TO lv_to.
        lv_ids = lv_ids && el( iv_name = `businessEventIds` iv_value = lv_event_id ).
      ENDLOOP.

      DATA(lv_first) = 0.
      DO.
        DATA(lo_xml) = soap( iv_manager   = c_manager-activity
                             iv_operation = `searchActivitiesByBusinessEvent`
                             iv_namespace = c_ns_model
                             iv_body      = |<request>{ lv_types_xml }{ lv_ids }| &&
                                            el( iv_name = `validated` iv_value = lv_validated ) &&
                                            |</request><batchSize>{ lv_size }</batchSize>| &&
                                            |<firstResultIndex>{ lv_first }</firstResultIndex>| ).
        DATA(lv_return) = check_return( io_xml = lo_xml iv_context = 'Zeiten (ActivityManager)' ).
        DATA(lt_activities) = lo_xml->children( iv_parent = lv_return iv_name = `entities` ).

        LOOP AT lt_activities INTO DATA(lv_activity).
          IF to_lower( lo_xml->child_value( iv_parent = lv_activity iv_path = `deleted` ) ) = `true`.
            CONTINUE.
          ENDIF.
          DATA(lv_start) = zcprx_cl_mapper=>from_iso( lo_xml->child_value( iv_parent = lv_activity iv_path = `activityStart` ) ).
          DATA(lv_end)   = zcprx_cl_mapper=>from_iso( lo_xml->child_value( iv_parent = lv_activity iv_path = `activityEnd` ) ).
          IF lv_start IS INITIAL OR lv_end IS INITIAL OR lv_end <= lv_start.
            CONTINUE.
          ENDIF.
          DATA(lv_type)   = lo_xml->child_value( iv_parent = lv_activity iv_path = `activityTypeId` ).
          DATA(lv_owner)  = lo_xml->child_value( iv_parent = lv_activity iv_path = `businessEventId` ).
          DATA(lv_hours)  = round( val = CONV decfloat34( utclong_diff( high = lv_end low = lv_start ) / 3600 ) dec = 3 ).

          READ TABLE rt_times ASSIGNING FIELD-SYMBOL(<ls_times>) WITH TABLE KEY event_id = lv_owner.
          IF sy-subrc <> 0.
            INSERT VALUE #( event_id = lv_owner ) INTO TABLE rt_times ASSIGNING <ls_times>.
          ENDIF.
          APPEND VALUE #( line_id    = lo_xml->child_value( iv_parent = lv_activity iv_path = `id` )
                          technician = lo_xml->child_value( iv_parent = lv_activity iv_path = `agentId` )
                          product    = VALUE #( lt_map[ param = lv_type ]-value DEFAULT lv_default )
                          start_at   = zcprx_cl_mapper=>to_iso( lv_start )
                          end_at     = zcprx_cl_mapper=>to_iso( lv_end )
                          duration   = lv_hours
                          unit       = `H` ) TO <ls_times>-times.
        ENDLOOP.

        IF lines( lt_activities ) < lv_size.
          EXIT.
        ENDIF.
        lv_first += lv_size.
      ENDDO.
      lv_from = lv_to + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD send_batches.
    DATA lt_ids TYPE tt_string.
    DATA(lv_size)  = batch_size( ).
    DATA(lv_count) = lines( it_ids ).
    DATA(lv_from)  = 1.

    WHILE lv_from <= lv_count.
      DATA(lv_to)   = nmin( val1 = lv_from + lv_size - 1 val2 = lv_count ).
      DATA(lv_body) = ``.
      CLEAR lt_ids.
      LOOP AT it_xml INTO DATA(lv_xml) FROM lv_from TO lv_to.
        lv_body = |{ lv_body }<{ iv_element }>{ lv_xml }</{ iv_element }>|.
        APPEND it_ids[ sy-tabix ] TO lt_ids.
      ENDLOOP.

      TRY.
          DATA(lt_package) = batch_results( io_xml = soap( iv_manager   = iv_manager
                                                           iv_operation = iv_operation
                                                           iv_namespace = c_ns_model
                                                           iv_body      = lv_body )
                                            it_ids = lt_ids ).
        CATCH zcprx_cx_error INTO DATA(lx_error).
          " Paket fehlgeschlagen -> alle Einträge des Pakets als Fehler
          lt_package = VALUE #( FOR id IN lt_ids ( external_id = id error = lx_error->get_text( ) ) ).
      ENDTRY.
      APPEND LINES OF lt_package TO rt_result.
      lv_from = lv_to + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD batch_results.
    DATA(lv_return)  = io_xml->find( `return` ).
    DATA(lv_code)    = io_xml->child_value( iv_parent = lv_return iv_path = `resultCode` ).
    DATA(lv_message) = io_xml->child_value( iv_parent = lv_return iv_path = `message` ).
    DATA(lt_results) = io_xml->children( iv_parent = lv_return iv_name = `results` ).

    LOOP AT it_ids INTO DATA(lv_id).
      DATA(lv_index) = sy-tabix.
      IF lv_index <= lines( lt_results ).
        DATA(lv_node)      = lt_results[ lv_index ].
        DATA(lv_item_code) = io_xml->child_value( iv_parent = lv_node iv_path = `resultCode` ).
        IF lv_item_code IS INITIAL OR lv_item_code = `0`.
          DATA(lv_new_id) = io_xml->child_value( iv_parent = lv_node iv_path = `id` ).
          APPEND VALUE #( external_id = lv_id id = COND #( WHEN lv_new_id IS NOT INITIAL THEN lv_new_id ELSE lv_id ) ) TO rt_result.
        ELSE.
          APPEND VALUE #( external_id = lv_id
                          error       = |Praxedo { lv_item_code }: { io_xml->child_value( iv_parent = lv_node iv_path = `message` ) }| ) TO rt_result.
        ENDIF.
      ELSEIF lv_code IS NOT INITIAL AND lv_code <> `0`.
        APPEND VALUE #( external_id = lv_id error = |Praxedo { lv_code }: { lv_message }| ) TO rt_result.
      ELSE.
        APPEND VALUE #( external_id = lv_id id = lv_id ) TO rt_result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD single_result.
    DATA(lt_result) = batch_results( io_xml = io_xml it_ids = VALUE #( ( iv_default ) ) ).
    DATA(ls_result) = VALUE #( lt_result[ 1 ] OPTIONAL ).
    IF ls_result-error IS NOT INITIAL.
      zcprx_cx_error=>raise( iv_text = |{ iv_context }: { ls_result-error }| iv_permanent = abap_true ).
    ENDIF.
    rv_id = COND #( WHEN ls_result-id IS NOT INITIAL THEN ls_result-id ELSE iv_default ).
  ENDMETHOD.

  METHOD check_return.
    rv_return = io_xml->find( `return` ).
    DATA(lv_code) = io_xml->child_value( iv_parent = rv_return iv_path = `resultCode` ).
    IF lv_code IS NOT INITIAL AND lv_code <> `0`.
      zcprx_cx_error=>raise(
        iv_text      = |{ iv_context }: Praxedo { lv_code } { io_xml->child_value( iv_parent = rv_return iv_path = `message` ) }|
        iv_permanent = abap_true ).
    ENDIF.
  ENDMETHOD.

  METHOD soap.
    DATA lo_client TYPE REF TO if_web_http_client.
    DATA lv_body   TYPE xstring.
    DATA lv_ctype  TYPE string.

    DATA(lv_envelope) = |<?xml version="1.0" encoding="UTF-8"?>| &&
                        |<soap:Envelope xmlns:soap="{ c_ns_soap }" xmlns:xsi="{ c_ns_xsi }" xmlns:ns="{ iv_namespace }">| &&
                        |<soap:Body><ns:{ iv_operation }>{ iv_body }</ns:{ iv_operation }></soap:Body></soap:Envelope>|.
    DATA(lv_path) = relative_path( |{ zcprx_cl_config=>get( zcprx_cl_config=>c_param-prx_soap_path ) }/{ iv_manager }| ).

    TRY.
        lo_client = client( c_service_soap ).
        DATA(lo_request) = lo_client->get_http_request( ).
        lo_request->set_uri_path( i_uri_path = lv_path ).
        lo_request->set_header_field( i_name  = 'Content-Type'
                                      i_value = |application/soap+xml; charset=UTF-8; action="{ iv_operation }"| ).
        lo_request->set_header_field( i_name = 'Accept' i_value = 'application/soap+xml, multipart/related, text/xml' ).
        lo_request->set_binary( zcprx_cl_xml=>to_utf8( lv_envelope ) ).

        DATA(lo_response) = lo_client->execute( if_web_http_client=>post ).
        DATA(ls_status)   = lo_response->get_status( ).
        lv_body           = lo_response->get_binary( ).
        lv_ctype          = lo_response->get_header_field( 'Content-Type' ).
        lo_client->close( ).
      CATCH cx_web_http_client_error cx_web_message_error INTO DATA(lx_http).
        IF lo_client IS BOUND.
          TRY.
              lo_client->close( ).
            CATCH cx_web_http_client_error ##NO_HANDLER.
          ENDTRY.
        ENDIF.
        zcprx_cx_error=>raise( iv_text = |Praxedo { iv_manager }.{ iv_operation } nicht erreichbar| ix_previous = lx_http ).
    ENDTRY.

    IF ls_status-code = 401 OR ls_status-code = 403.
      zcprx_cx_error=>raise( iv_text      = |Praxedo { iv_manager }: Anmeldung abgelehnt (HTTP { ls_status-code }, Benutzer im Kommunikationssystem prüfen)|
                                 iv_permanent = abap_true ).
    ENDIF.

    DATA(lv_xml) = zcprx_cl_xml=>extract_root_part( iv_body = lv_body iv_content_type = lv_ctype ).
    TRY.
        mv_last_raw = cl_abap_conv_codepage=>create_in( codepage = COND #( WHEN to_upper( lv_ctype ) CS 'ISO-8859-1'
                                                                           THEN `ISO-8859-1` ELSE `UTF-8` ) )->convert( lv_xml ).
      CATCH cx_root.
        CLEAR mv_last_raw.
    ENDTRY.

    " HTML-Fehlerseite (z. B. von der eTech-Webanwendung statt vom SOAP-Dienst):
    " nur Titel und sichtbaren Text in die Meldung übernehmen
    IF to_lower( lv_ctype ) CS 'html'.
      DATA(lv_page) = replace( val = mv_last_raw pcre = `(?is)<(script|style|head)\b.*?</\1>` with = ` ` occ = 0 ).
      DATA(lv_title) = match( val = mv_last_raw pcre = `(?is)(?<=<title>).*?(?=</title>)` ).
      lv_page = replace( val = lv_page pcre = `<[^>]*>` with = ` ` occ = 0 ).
      lv_page = replace( val = lv_page pcre = `&nbsp;|&#160;` with = ` ` occ = 0 ).
      mv_last_raw = condense( |HTML-Seite "{ condense( lv_title ) }": { lv_page }| ).
    ENDIF.

    TRY.
        ro_xml = zcprx_cl_xml=>parse( lv_xml ).
      CATCH zcprx_cx_error INTO DATA(lx_parse).
        IF ls_status-code >= 300.
          zcprx_cx_error=>raise(
            iv_text      = |Praxedo { iv_manager }.{ iv_operation }: HTTP { ls_status-code } ({ lv_ctype }) | &&
                           substring( val = mv_last_raw len = nmin( val1 = strlen( mv_last_raw ) val2 = 300 ) )
            iv_permanent = zcprx_cx_error=>is_permanent_http( ls_status-code ) ).
        ENDIF.
        RAISE EXCEPTION lx_parse.
    ENDTRY.

    " SOAP-1.2-Fault: Reason/Text, fachlich mit Detail/WSFault (message, resultCode)
    DATA(lv_fault) = ro_xml->find( `Fault` ).
    IF lv_fault > 0.
      DATA(lv_ws_fault) = ro_xml->find( iv_name = `WSFault` iv_parent = lv_fault ).
      DATA(lv_text)     = COND string( WHEN lv_ws_fault > 0
                                       THEN |{ ro_xml->child_value( iv_parent = lv_ws_fault iv_path = `resultCode` ) } | &&
                                            ro_xml->child_value( iv_parent = lv_ws_fault iv_path = `message` ) ).
      IF lv_text IS INITIAL OR lv_text = ` `.
        lv_text = ro_xml->value( ro_xml->find( iv_name = `Text` iv_parent = lv_fault ) ).
      ENDIF.
      " fachlicher Fehler (WSFault) wird nicht wiederholt, technischer schon
      zcprx_cx_error=>raise( iv_text      = |Praxedo { iv_manager }.{ iv_operation }: { lv_text }|
                                 iv_permanent = xsdbool( lv_ws_fault > 0 ) ).
    ENDIF.

    IF ls_status-code >= 300.
      zcprx_cx_error=>raise( iv_text      = |Praxedo { iv_manager }.{ iv_operation }: HTTP { ls_status-code } | &&
                                                substring( val = mv_last_raw len = nmin( val1 = strlen( mv_last_raw ) val2 = 300 ) )
                                 iv_permanent = zcprx_cx_error=>is_permanent_http( ls_status-code ) ).
    ENDIF.
  ENDMETHOD.

  METHOD client.
    TRY.
        DATA(lo_destination) = cl_http_destination_provider=>create_by_comm_arrangement(
                                 comm_scenario = CONV #( c_comm_scenario )
                                 service_id    = CONV #( iv_service ) ).
        ro_client = cl_web_http_client_manager=>create_by_http_destination( lo_destination ).
      CATCH cx_http_dest_provider_error cx_web_http_client_error INTO DATA(lx_dest).
        zcprx_cx_error=>raise( iv_text      = |Kein Kommunikationsarrangement { c_comm_scenario } / { iv_service }|
                                   ix_previous  = lx_dest
                                   iv_permanent = abap_true ).
    ENDTRY.
  ENDMETHOD.

  METHOD batch_size.
    rv_size = nmax( val1 = zcprx_cl_config=>get_int( iv_param = zcprx_cl_config=>c_param-prx_batch_size iv_min = 1 )
                    val2 = 1 ).
  ENDMETHOD.

  METHOD el.
    rv_xml = zcprx_cl_xml=>el( iv_name = iv_name iv_value = iv_value ).
  ENDMETHOD.

ENDCLASS.

