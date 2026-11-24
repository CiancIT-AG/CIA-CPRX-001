CLASS zcprx_cl_praxedo_api DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES zcprx_if_praxedo_api.

    CONSTANTS c_comm_scenario TYPE c LENGTH 30 VALUE 'ZCPRX_CS_PRAXEDO'.
    CONSTANTS c_service_id    TYPE c LENGTH 40 VALUE 'ZCPRX_OS_PRAXEDO_REST'.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_id_response,
             id TYPE string,
           END OF ty_id_response.

    METHODS call
      IMPORTING iv_method          TYPE if_web_http_client=>method
                iv_path            TYPE string
                iv_body            TYPE string OPTIONAL
                iv_accept_404      TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(rv_response) TYPE string
      RAISING   zcprx_cx_error.

    "! HTTP-Status -> dauerhafter Fehler? (4xx außer 408/429 = Daten/Konfiguration)


    METHODS to_json
      IMPORTING ia_data        TYPE any
      RETURNING VALUE(rv_json) TYPE string.

    METHODS from_json
      IMPORTING iv_json TYPE string
      CHANGING  ca_data TYPE any.

    METHODS path
      IMPORTING iv_param       TYPE csequence
      RETURNING VALUE(rv_path) TYPE string
      RAISING   zcprx_cx_error.

    METHODS upsert_single
      IMPORTING iv_path      TYPE string
                ia_data      TYPE any
      RETURNING VALUE(rv_id) TYPE string
      RAISING   zcprx_cx_error.
ENDCLASS.

CLASS zcprx_cl_praxedo_api IMPLEMENTATION.

  METHOD zcprx_if_praxedo_api~upsert_customer.
    rv_id = upsert_single( iv_path = path( zcprx_cl_config=>c_param-path_customer )
                           ia_data = is_customer ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~upsert_location.
    rv_id = upsert_single( iv_path = path( zcprx_cl_config=>c_param-path_location )
                           ia_data = is_location ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~upsert_equipment.
    rv_id = upsert_single( iv_path = path( zcprx_cl_config=>c_param-path_equipment )
                           ia_data = is_equipment ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~upsert_order.
    DATA(lv_path) = path( zcprx_cl_config=>c_param-path_order ).
    IF is_order-id IS INITIAL.
      rv_id = upsert_single( iv_path = lv_path ia_data = is_order ).
    ELSE.
      call( iv_method = if_web_http_client=>put
            iv_path   = |{ lv_path }/{ escape( val = is_order-id format = cl_abap_format=>e_url_full ) }|
            iv_body   = to_json( is_order ) ).
      rv_id = is_order-id.
    ENDIF.
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~delete_order.
    DATA(lv_path) = path( zcprx_cl_config=>c_param-path_order ).
    " 404 = in Praxedo bereits gelöscht -> kein Fehler (idempotent)
    call( iv_method     = if_web_http_client=>delete
          iv_path       = |{ lv_path }/{ escape( val = iv_id format = cl_abap_format=>e_url_full ) }|
          iv_accept_404 = abap_true ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~get_order.
    DATA(lv_path) = path( zcprx_cl_config=>c_param-path_order ).
    DATA(lv_json) = call( iv_method = if_web_http_client=>get
                          iv_path   = |{ lv_path }/{ escape( val = iv_id format = cl_abap_format=>e_url_full ) }| ).
    from_json( EXPORTING iv_json = lv_json CHANGING ca_data = rs_order ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~get_completed_orders.
    DATA(lv_path) = path( zcprx_cl_config=>c_param-path_order_search ).
    DATA(lv_json) = call( iv_method = if_web_http_client=>get
                          iv_path   = |{ lv_path }?since={ escape( val = iv_since format = cl_abap_format=>e_url_full ) }| ).
    from_json( EXPORTING iv_json = lv_json CHANGING ca_data = rt_orders ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~upsert_products.
    DATA(lv_json) = call( iv_method = if_web_http_client=>post
                          iv_path   = path( zcprx_cl_config=>c_param-path_product )
                          iv_body   = to_json( it_products ) ).
    from_json( EXPORTING iv_json = lv_json CHANGING ca_data = rt_result ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~upsert_product_groups.
    DATA(lv_json) = call( iv_method = if_web_http_client=>post
                          iv_path   = path( zcprx_cl_config=>c_param-path_product_group )
                          iv_body   = to_json( it_groups ) ).
    from_json( EXPORTING iv_json = lv_json CHANGING ca_data = rt_result ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~upsert_equipment_types.
    DATA(lv_json) = call( iv_method = if_web_http_client=>post
                          iv_path   = path( zcprx_cl_config=>c_param-path_equipment_type )
                          iv_body   = to_json( it_types ) ).
    from_json( EXPORTING iv_json = lv_json CHANGING ca_data = rt_result ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~get_report.
    DATA(lv_date) = |{ iv_date(4) }-{ iv_date+4(2) }-{ iv_date+6(2) }|.
    DATA(lv_path) = path( zcprx_cl_config=>c_param-path_report ).
    DATA(lv_json) = call( iv_method = if_web_http_client=>get
                          iv_path   = |{ lv_path }/{ escape( val = iv_report_id format = cl_abap_format=>e_url_full ) }?date={ lv_date }| ).
    from_json( EXPORTING iv_json = lv_json CHANGING ca_data = rt_lines ).
  ENDMETHOD.

  METHOD zcprx_if_praxedo_api~ping.
    DATA(lv_path) = zcprx_cl_config=>get( zcprx_cl_config=>c_param-path_ping ).
    IF lv_path IS NOT INITIAL.
      call( iv_method = if_web_http_client=>get iv_path = lv_path ).
      RETURN.
    ENDIF.
    TRY.
        cl_http_destination_provider=>create_by_comm_arrangement( comm_scenario = CONV #( c_comm_scenario )
                                                                  service_id    = CONV #( c_service_id ) ).
      CATCH cx_http_dest_provider_error INTO DATA(lx_dest).
        zcprx_cx_error=>raise( iv_text     = |Kein Kommunikationsarrangement für { c_comm_scenario }|
                                   ix_previous = lx_dest ).
    ENDTRY.
  ENDMETHOD.

  METHOD upsert_single.
    DATA ls_response TYPE ty_id_response.
    DATA(lv_json) = call( iv_method = if_web_http_client=>post
                          iv_path   = iv_path
                          iv_body   = to_json( ia_data ) ).
    from_json( EXPORTING iv_json = lv_json CHANGING ca_data = ls_response ).
    rv_id = ls_response-id.
  ENDMETHOD.

  METHOD call.
    DATA lo_client TYPE REF TO if_web_http_client.
    TRY.
        DATA(lo_destination) = cl_http_destination_provider=>create_by_comm_arrangement(
                                 comm_scenario = CONV #( c_comm_scenario )
                                 service_id    = CONV #( c_service_id ) ).
        lo_client = cl_web_http_client_manager=>create_by_http_destination( lo_destination ).

        DATA(lo_request) = lo_client->get_http_request( ).
        lo_request->set_uri_path( i_uri_path = iv_path ).
        lo_request->set_header_field( i_name = 'Accept'       i_value = 'application/json' ).
        IF iv_body IS NOT INITIAL.
          lo_request->set_header_field( i_name = 'Content-Type' i_value = 'application/json; charset=utf-8' ).
          lo_request->set_text( iv_body ).
        ENDIF.

        DATA(lo_response) = lo_client->execute( iv_method ).
        DATA(ls_status)   = lo_response->get_status( ).
        rv_response       = lo_response->get_text( ).
        lo_client->close( ).

        IF ls_status-code = 404 AND iv_accept_404 = abap_true.
          CLEAR rv_response.
          RETURN.
        ENDIF.
        IF ls_status-code >= 300.
          zcprx_cx_error=>raise(
            iv_text      = |Praxedo HTTP { ls_status-code } { iv_path }: { substring( val = rv_response len = nmin( val1 = strlen( rv_response ) val2 = 150 ) ) }|
            iv_permanent = zcprx_cx_error=>is_permanent_http( ls_status-code ) ).
        ENDIF.

      CATCH cx_http_dest_provider_error cx_web_http_client_error cx_web_message_error INTO DATA(lx_http).
        IF lo_client IS BOUND.
          TRY.
              lo_client->close( ).
            CATCH cx_web_http_client_error ##NO_HANDLER.
          ENDTRY.
        ENDIF.
        zcprx_cx_error=>raise( iv_text = |Praxedo-Aufruf { iv_path } fehlgeschlagen| ix_previous = lx_http ).
    ENDTRY.
  ENDMETHOD.

  METHOD to_json.
    rv_json = /ui2/cl_json=>serialize( data        = ia_data
                                       pretty_name = /ui2/cl_json=>pretty_mode-camel_case
                                       compress    = abap_true ).
  ENDMETHOD.

  METHOD from_json.
    CHECK iv_json IS NOT INITIAL.
    /ui2/cl_json=>deserialize( EXPORTING json        = iv_json
                                         pretty_name = /ui2/cl_json=>pretty_mode-camel_case
                               CHANGING  data        = ca_data ).
  ENDMETHOD.

  METHOD path.
    " Standardwerte zentral in ZCPRX_CL_CONFIG=>GET_DEFAULTS
    rv_path = zcprx_cl_config=>get( iv_param ).
    IF rv_path IS INITIAL.
      zcprx_cx_error=>raise( iv_text = |Praxedo-Pfad { iv_param } nicht konfiguriert| iv_permanent = abap_true ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
