CLASS zcprx_cl_http_event DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_http_service_extension.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_data,
        serviceorder TYPE string,
      END OF ty_data,
      BEGIN OF ty_event,
        id   TYPE string,
        type TYPE string,
        data TYPE ty_data,
      END OF ty_event.
ENDCLASS.

CLASS zcprx_cl_http_event IMPLEMENTATION.

  METHOD if_http_service_extension~handle_request.
    DATA ls_event TYPE ty_event.

    " Webhook-Validierung / Health-Check (Event Mesh sendet ggf. OPTIONS)
    DATA(lv_method) = request->get_method( ).
    IF lv_method = 'OPTIONS' OR lv_method = 'GET'.
      response->set_header_field( i_name = 'WebHook-Allowed-Origin' i_value = '*' ).
      response->set_status( i_code = 200 i_reason = 'OK' ).
      RETURN.
    ENDIF.

    /ui2/cl_json=>deserialize( EXPORTING json = request->get_text( ) CHANGING data = ls_event ).

    " nur Serviceauftrags-Events annehmen (Subscription kann breiter sein)
    IF ls_event-type IS NOT INITIAL AND to_lower( ls_event-type ) NS 'serviceorder'.
      response->set_status( i_code = 202 i_reason = 'Ignored' ).
      RETURN.
    ENDIF.

    IF ls_event-data-serviceorder IS INITIAL.
      response->set_status( i_code = 400 i_reason = 'ServiceOrder missing' ).
      RETURN.
    ENDIF.

    " Entkoppeln: Queue-Eintrag + bgPF, sofort 202 zurück
    zcprx_cl_queue=>enqueue( VALUE #( ( object_type = zcprx_if_constants=>object_type-service_order
                                            operation   = zcprx_if_constants=>operation-upsert
                                            object_key  = ls_event-data-serviceorder ) ) ).
    COMMIT WORK.

    response->set_status( i_code = 202 i_reason = 'Accepted' ).
  ENDMETHOD.

ENDCLASS.
