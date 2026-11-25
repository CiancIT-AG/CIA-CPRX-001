CLASS zcprx_cl_prx_console DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
ENDCLASS.

CLASS zcprx_cl_prx_console IMPLEMENTATION.
  METHOD if_oo_adt_classrun~main.
    CONSTANTS lc_code TYPE string VALUE ``.   " Praxedo-Code des Einsatzes, z. B. `8000000123-10`

    IF lc_code IS INITIAL.
      out->write( 'Bitte LC_CODE (Praxedo-Code eines Einsatzes) eintragen und erneut ausführen.' ).
      RETURN.
    ENDIF.

    DATA(lo_api) = NEW zcprx_cl_praxedo_api( ).
    TRY.
        out->write( |--- getEvents { lc_code } (roh) ---| ).
        out->write( lo_api->get_event_raw( lc_code ) ).

        DATA(ls_order) = lo_api->zcprx_if_praxedo_api~get_order( lc_code ).
        out->write( |--- Mapping ---| ).
        out->write( |Code { ls_order-id }, Status { ls_order-status }, UUID { ls_order-uuid }| ).
        out->write( |Serviceauftrag { ls_order-service_order } / { ls_order-service_order_item }, abgeschlossen { ls_order-completed_at }| ).
        out->write( |{ lines( ls_order-times ) } Zeit(en), { lines( ls_order-materials ) } Material(ien)| ).
        out->write( ls_order-times ).
        out->write( ls_order-materials ).
      CATCH zcprx_cx_error INTO DATA(lx_error).
        out->write( |FEHLER: { lx_error->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

