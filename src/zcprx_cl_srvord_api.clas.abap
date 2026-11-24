CLASS zcprx_cl_srvord_api DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES zcprx_if_srvord_api.

    CONSTANTS c_comm_scenario TYPE c LENGTH 30 VALUE 'ZCPRX_CS_S4_LOOPBACK'.
    CONSTANTS c_service_id    TYPE c LENGTH 40 VALUE 'ZCPRX_OS_S4_LOOPBACK_REST'.

    CLASS-METHODS parse_v2_date
      IMPORTING iv_value        TYPE string
      RETURNING VALUE(rv_value) TYPE utclong.

    CLASS-METHODS to_v2_date
      IMPORTING iv_value        TYPE utclong
      RETURNING VALUE(rv_value) TYPE string.

  PRIVATE SECTION.
    " ---- OData-V2-Strukturen (Feldnamen = JSON-Namen, case-insensitive)
    " HINWEIS: Feld-/Navigationsnamen gegen das EDMX im Business
    "          Accelerator Hub verifizieren (siehe Verifikationsliste).
    TYPES:
      BEGIN OF ty_v2_item,
        serviceorderitem              TYPE string,
        product                       TYPE string,
        serviceorderitemdescription   TYPE string,
        serviceorderitemcategory      TYPE string,
        quantity                      TYPE string,
        quantityunit                  TYPE string,
        requestedservicestartdatetime TYPE string,
        requestedserviceenddatetime   TYPE string,
      END OF ty_v2_item,
      BEGIN OF ty_v2_items,
        results TYPE STANDARD TABLE OF ty_v2_item WITH EMPTY KEY,
      END OF ty_v2_items,
      BEGIN OF ty_v2_refobj,
        servicereferenceequipment    TYPE string,
        servicerefobjectismainobject TYPE abap_bool,
      END OF ty_v2_refobj,
      BEGIN OF ty_v2_refobjs,
        results TYPE STANDARD TABLE OF ty_v2_refobj WITH EMPTY KEY,
      END OF ty_v2_refobjs,
      BEGIN OF ty_v2_so,
        serviceorder                  TYPE string,
        serviceordertype              TYPE string,
        serviceorderdescription       TYPE string,
        soldtoparty                   TYPE string,
        shiptoparty                   TYPE string,
        requestedservicestartdatetime TYPE string,
        requestedserviceenddatetime   TYPE string,
        to_item                       TYPE ty_v2_items,
        to_referenceobject            TYPE ty_v2_refobjs,
      END OF ty_v2_so,
      BEGIN OF ty_v2_so_resp,
        d TYPE ty_v2_so,
      END OF ty_v2_so_resp,
      BEGIN OF ty_v2_so_id,
        serviceorder TYPE string,
      END OF ty_v2_so_id,
      BEGIN OF ty_v2_so_list,
        results TYPE STANDARD TABLE OF ty_v2_so_id WITH EMPTY KEY,
      END OF ty_v2_so_list,
      BEGIN OF ty_v2_so_list_resp,
        d TYPE ty_v2_so_list,
      END OF ty_v2_so_list_resp,
      BEGIN OF ty_v2_conf,
        serviceconfirmation TYPE string,
      END OF ty_v2_conf,
      BEGIN OF ty_v2_conf_resp,
        d TYPE ty_v2_conf,
      END OF ty_v2_conf_resp.

    METHODS get_client
      RETURNING VALUE(ro_client) TYPE REF TO if_web_http_client
      RAISING   zcprx_cx_error.

    METHODS get
      IMPORTING iv_path        TYPE string
      RETURNING VALUE(rv_json) TYPE string
      RAISING   zcprx_cx_error.

    METHODS build_confirmation_json
      IMPORTING is_confirmation TYPE zcprx_if_srvord_api=>ty_confirmation
      RETURNING VALUE(rv_json)  TYPE string.

    METHODS json_escape
      IMPORTING iv_value        TYPE csequence
      RETURNING VALUE(rv_value) TYPE string.
ENDCLASS.

CLASS zcprx_cl_srvord_api IMPLEMENTATION.

  METHOD zcprx_if_srvord_api~get_service_order.
    DATA ls_resp TYPE ty_v2_so_resp.

    DATA(lv_base) = zcprx_cl_config=>get( zcprx_cl_config=>c_param-so_api_path ).
    DATA(lv_json) = get( |{ lv_base }/A_ServiceOrder('{ iv_service_order }')?$expand=to_Item,to_ReferenceObject&$format=json| ).

    /ui2/cl_json=>deserialize( EXPORTING json = lv_json CHANGING data = ls_resp ).
    IF ls_resp-d-serviceorder IS INITIAL.
      zcprx_cx_error=>raise( iv_text = |Serviceauftrag { iv_service_order } nicht gefunden| iv_permanent = abap_true ).
    ENDIF.

    rs_service_order = VALUE #( service_order = ls_resp-d-serviceorder
                                order_type    = ls_resp-d-serviceordertype
                                description   = ls_resp-d-serviceorderdescription
                                sold_to_party = ls_resp-d-soldtoparty
                                ship_to_party = ls_resp-d-shiptoparty
                                planned_start = parse_v2_date( ls_resp-d-requestedservicestartdatetime )
                                planned_end   = parse_v2_date( ls_resp-d-requestedserviceenddatetime ) ).

    " Hauptreferenzobjekt = Equipment
    LOOP AT ls_resp-d-to_referenceobject-results INTO DATA(ls_ref) WHERE servicereferenceequipment IS NOT INITIAL.
      rs_service_order-equipment = ls_ref-servicereferenceequipment.
      IF ls_ref-servicerefobjectismainobject = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    LOOP AT ls_resp-d-to_item-results INTO DATA(ls_item).
      DATA(lv_qty) = CONV decfloat34( 0 ).
      TRY.
          lv_qty = CONV decfloat34( ls_item-quantity ).
        CATCH cx_sy_conversion_error ##NO_HANDLER.
      ENDTRY.
      APPEND VALUE #( service_order_item = ls_item-serviceorderitem
                      product            = ls_item-product
                      description        = ls_item-serviceorderitemdescription
                      item_category      = ls_item-serviceorderitemcategory
                      quantity           = lv_qty
                      unit               = ls_item-quantityunit
                      planned_start      = parse_v2_date( ls_item-requestedservicestartdatetime )
                      planned_end        = parse_v2_date( ls_item-requestedserviceenddatetime ) )
             TO rs_service_order-items.
    ENDLOOP.
  ENDMETHOD.

  METHOD zcprx_if_srvord_api~get_changed_service_orders.
    DATA ls_resp TYPE ty_v2_so_list_resp.

    DATA(lv_base)  = zcprx_cl_config=>get( zcprx_cl_config=>c_param-so_api_path ).
    " Feldname des Änderungszeitstempels konfigurierbar (EDMX prüfen)
    DATA(lv_field) = zcprx_cl_config=>get( zcprx_cl_config=>c_param-so_changed_field ).
    DATA(lv_iso)   = substring( val = |{ iv_since TIMESTAMP = ISO }| len = 19 ).

    DATA(lv_json) = get( |{ lv_base }/A_ServiceOrder?$select=ServiceOrder| &&
                         |&$filter={ lv_field }%20gt%20datetimeoffset'{ lv_iso }Z'| &&
                         |&$top=5000&$format=json| ).

    /ui2/cl_json=>deserialize( EXPORTING json = lv_json CHANGING data = ls_resp ).
    rt_ids = VALUE #( FOR r IN ls_resp-d-results ( CONV #( r-serviceorder ) ) ).
  ENDMETHOD.

  METHOD zcprx_if_srvord_api~create_confirmation.
    DATA ls_resp TYPE ty_v2_conf_resp.
    DATA(lv_base) = zcprx_cl_config=>get( zcprx_cl_config=>c_param-conf_api_path ).
    DATA(lo_client) = get_client( ).

    TRY.
        " 1) CSRF-Token holen
        DATA(lo_request) = lo_client->get_http_request( ).
        lo_request->set_uri_path( i_uri_path = |{ lv_base }/| ).
        lo_request->set_header_field( i_name = 'x-csrf-token' i_value = 'fetch' ).
        DATA(lo_response) = lo_client->execute( if_web_http_client=>get ).
        DATA(lv_token)    = lo_response->get_header_field( 'x-csrf-token' ).
        DATA(lt_cookies)  = lo_response->get_cookies( ).

        " 2) Deep Insert Servicebestätigung inkl. Positionen
        lo_request->set_uri_path( i_uri_path = |{ lv_base }/A_ServiceConfirmation| ).
        lo_request->set_header_field( i_name = 'x-csrf-token' i_value = lv_token ).
        lo_request->set_header_field( i_name = 'Content-Type' i_value = 'application/json' ).
        lo_request->set_header_field( i_name = 'Accept'       i_value = 'application/json' ).
        LOOP AT lt_cookies INTO DATA(ls_cookie).
          lo_request->set_cookie( i_name = ls_cookie-name i_value = ls_cookie-value ).
        ENDLOOP.
        lo_request->set_text( build_confirmation_json( is_confirmation ) ).

        lo_response = lo_client->execute( if_web_http_client=>post ).
        DATA(ls_status) = lo_response->get_status( ).
        DATA(lv_json)   = lo_response->get_text( ).
        lo_client->close( ).

        IF ls_status-code <> 201 AND ls_status-code <> 200.
          zcprx_cx_error=>raise(
            iv_text      = |Servicebestätigung: HTTP { ls_status-code } { substring( val = lv_json len = nmin( val1 = strlen( lv_json ) val2 = 160 ) ) }|
            iv_permanent = zcprx_cx_error=>is_permanent_http( ls_status-code ) ).
        ENDIF.

      CATCH cx_web_http_client_error cx_web_message_error INTO DATA(lx_http).
        zcprx_cx_error=>raise( iv_text = 'Servicebestätigung: HTTP-Fehler' ix_previous = lx_http ).
    ENDTRY.

    /ui2/cl_json=>deserialize( EXPORTING json = lv_json CHANGING data = ls_resp ).
    rv_confirmation = ls_resp-d-serviceconfirmation.
  ENDMETHOD.

  METHOD zcprx_if_srvord_api~ping.
    get( |{ zcprx_cl_config=>get( zcprx_cl_config=>c_param-so_api_path ) }/A_ServiceOrder?$top=1&$select=ServiceOrder&$format=json| ).
    get( |{ zcprx_cl_config=>get( zcprx_cl_config=>c_param-conf_api_path ) }/A_ServiceConfirmation?$top=1&$select=ServiceConfirmation&$format=json| ).
  ENDMETHOD.

  METHOD build_confirmation_json.
    DATA(lv_type)      = zcprx_cl_config=>get( zcprx_cl_config=>c_param-conf_type ).
    " Optional: Bestätigung direkt abschließen (Feldname im EDMX prüfen,
    " z. B. 'ServiceConfirmationIsCompleted'); leer = nicht senden
    DATA(lv_completed) = zcprx_cl_config=>get( zcprx_cl_config=>c_param-conf_completed_field ).

    DATA(lv_items) = REDUCE string(
      INIT s = `` sep = ``
      FOR i IN is_confirmation-items
      NEXT s = s && sep &&
               |\{"ReferenceServiceOrder":"{ is_confirmation-service_order }"| &&
               |,"ReferenceServiceOrderItem":"{ i-service_order_item }"| &&
               |,"Product":"{ json_escape( i-product ) }"| &&
               |,"Quantity":"{ i-quantity NUMBER = RAW }"| &&
               |,"QuantityUnit":"{ json_escape( i-unit ) }"| &&
               COND string( WHEN i-item_category IS NOT INITIAL
                            THEN |,"ServiceConfirmationItemCategory":"{ i-item_category }"| ) &&
               COND string( WHEN i-start_at IS NOT INITIAL
                            THEN |,"ActualServiceStartDateTime":"{ to_v2_date( i-start_at ) }"| ) &&
               COND string( WHEN i-end_at IS NOT INITIAL
                            THEN |,"ActualServiceEndDateTime":"{ to_v2_date( i-end_at ) }"| ) &&
               |\}|
           sep = `,` ).

    rv_json = |\{"ServiceConfirmationType":"{ lv_type }"| &&
              |,"ServiceConfirmationDescription":"{ json_escape( is_confirmation-description ) }"| &&
              |,"ReferenceServiceOrder":"{ is_confirmation-service_order }"| &&
              |,"SoldToParty":"{ is_confirmation-sold_to_party }"| &&
              COND string( WHEN lv_completed IS NOT INITIAL THEN |,"{ lv_completed }":true| ) &&
              |,"to_Item":[{ lv_items }]\}|.
  ENDMETHOD.

  METHOD get.
    DATA(lo_client) = get_client( ).
    TRY.
        DATA(lo_request) = lo_client->get_http_request( ).
        lo_request->set_uri_path( i_uri_path = iv_path ).
        lo_request->set_header_field( i_name = 'Accept' i_value = 'application/json' ).
        DATA(lo_response) = lo_client->execute( if_web_http_client=>get ).
        DATA(ls_status)   = lo_response->get_status( ).
        rv_json           = lo_response->get_text( ).
        lo_client->close( ).
      CATCH cx_web_http_client_error cx_web_message_error INTO DATA(lx_http).
        zcprx_cx_error=>raise( iv_text = |GET { iv_path } fehlgeschlagen| ix_previous = lx_http ).
    ENDTRY.
    IF ls_status-code >= 300.
      zcprx_cx_error=>raise(
        iv_text      = |SAP-API HTTP { ls_status-code }: { substring( val = rv_json len = nmin( val1 = strlen( rv_json ) val2 = 160 ) ) }|
        iv_permanent = zcprx_cx_error=>is_permanent_http( ls_status-code ) ).
    ENDIF.
  ENDMETHOD.

  METHOD get_client.
    TRY.
        DATA(lo_destination) = cl_http_destination_provider=>create_by_comm_arrangement(
                                 comm_scenario = CONV #( c_comm_scenario )
                                 service_id    = CONV #( c_service_id ) ).
        ro_client = cl_web_http_client_manager=>create_by_http_destination( lo_destination ).
      CATCH cx_http_dest_provider_error cx_web_http_client_error INTO DATA(lx_dest).
        zcprx_cx_error=>raise( iv_text = 'Loopback-Destination nicht verfügbar' ix_previous = lx_dest ).
    ENDTRY.
  ENDMETHOD.

  METHOD parse_v2_date.
    " V2: /Date(1700000000000)/ bzw. /Date(1700000000000+0000)/ ; V4/ISO: 2026-11-23T10:15:00Z
    CHECK iv_value IS NOT INITIAL.
    TRY.
        FIND PCRE '/Date\((-?\d+)' IN iv_value SUBMATCHES DATA(lv_ms).
        IF sy-subrc = 0.
          rv_value = utclong_add( val     = CONV utclong( '1970-01-01T00:00:00' )
                                  seconds = CONV decfloat34( lv_ms ) / 1000 ).
        ELSEIF strlen( iv_value ) >= 19.
          rv_value = CONV utclong( substring( val = iv_value len = 19 ) ).
        ENDIF.
      CATCH cx_root.
        CLEAR rv_value.
    ENDTRY.
  ENDMETHOD.

  METHOD to_v2_date.
    CHECK iv_value IS NOT INITIAL.
    DATA(lv_ms) = CONV int8( utclong_diff( high = iv_value
                                           low  = CONV utclong( '1970-01-01T00:00:00' ) ) * 1000 ).
    rv_value = |/Date({ lv_ms })/|.
  ENDMETHOD.

  METHOD json_escape.
    rv_value = escape( val = iv_value format = cl_abap_format=>e_json_string ).
  ENDMETHOD.

ENDCLASS.
