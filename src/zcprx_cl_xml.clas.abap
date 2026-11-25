CLASS zcprx_cl_xml DEFINITION PUBLIC FINAL CREATE PRIVATE.
  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_node,
        index  TYPE i,
        parent TYPE i,
        last   TYPE i,
        name   TYPE string,
        value  TYPE string,
      END OF ty_node,
      tt_node  TYPE STANDARD TABLE OF ty_node WITH EMPTY KEY,
      tt_index TYPE STANDARD TABLE OF i WITH EMPTY KEY.

    DATA mt_nodes TYPE tt_node READ-ONLY.

    CLASS-METHODS parse
      IMPORTING iv_xml        TYPE xstring
      RETURNING VALUE(ro_xml) TYPE REF TO zcprx_cl_xml
      RAISING   zcprx_cx_error.

    CLASS-METHODS parse_string
      IMPORTING iv_xml        TYPE string
      RETURNING VALUE(ro_xml) TYPE REF TO zcprx_cl_xml
      RAISING   zcprx_cx_error.

    "! Wurzelteil (SOAP-Umschlag) einer MTOM-/multipart-Antwort; sonst unverändert
    CLASS-METHODS extract_root_part
      IMPORTING iv_body        TYPE xstring
                iv_content_type TYPE string
      RETURNING VALUE(rv_xml)  TYPE xstring.

    CLASS-METHODS esc
      IMPORTING iv_value        TYPE csequence
      RETURNING VALUE(rv_value) TYPE string.

    "! <name>wert</name>; leerer Wert -> leer (Element entfällt)
    CLASS-METHODS el
      IMPORTING iv_name         TYPE csequence
                iv_value        TYPE csequence
      RETURNING VALUE(rv_xml)   TYPE string.

    CLASS-METHODS to_utf8
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_data) TYPE xstring
      RAISING   zcprx_cx_error.

    "! erster Nachfahre mit Namen (0 = ganzes Dokument); 0 = nicht gefunden
    METHODS find
      IMPORTING iv_name         TYPE csequence
                iv_parent       TYPE i DEFAULT 0
      RETURNING VALUE(rv_index) TYPE i.

    "! alle Nachfahren mit Namen
    METHODS find_all
      IMPORTING iv_name         TYPE csequence
                iv_parent       TYPE i DEFAULT 0
      RETURNING VALUE(rt_index) TYPE tt_index.

    "! direkte Kinder (optional nur mit Namen)
    METHODS children
      IMPORTING iv_parent       TYPE i
                iv_name         TYPE csequence OPTIONAL
      RETURNING VALUE(rt_index) TYPE tt_index.

    METHODS child
      IMPORTING iv_parent       TYPE i
                iv_name         TYPE csequence
      RETURNING VALUE(rv_index) TYPE i.

    METHODS value
      IMPORTING iv_index        TYPE i
      RETURNING VALUE(rv_value) TYPE string.

    "! Wert eines Kindes; Pfad mit "/" möglich, z. B. 'coreData/description'
    METHODS child_value
      IMPORTING iv_parent       TYPE i
                iv_path         TYPE csequence
      RETURNING VALUE(rv_value) TYPE string.
ENDCLASS.

CLASS zcprx_cl_xml IMPLEMENTATION.

  METHOD parse.
    DATA lt_stack TYPE tt_index.
    DATA lv_top   TYPE i.
    ro_xml = NEW #( ).

    TRY.
        DATA(lo_reader) = cl_sxml_string_reader=>create( iv_xml ).
        DO.
          DATA(lo_node) = lo_reader->read_next_node( ).
          IF lo_node IS INITIAL.
            EXIT.
          ENDIF.
          CASE lo_node->type.
            WHEN if_sxml_node=>co_nt_element_open.
              DATA(lo_open) = CAST if_sxml_open_element( lo_node ).
              lv_top = COND #( WHEN lt_stack IS INITIAL THEN 0 ELSE lt_stack[ lines( lt_stack ) ] ).
              APPEND VALUE #( index  = lines( ro_xml->mt_nodes ) + 1
                              parent = lv_top
                              name   = lo_open->qname-name ) TO ro_xml->mt_nodes.
              APPEND lines( ro_xml->mt_nodes ) TO lt_stack.
            WHEN if_sxml_node=>co_nt_element_close.
              IF lt_stack IS NOT INITIAL.
                lv_top = lt_stack[ lines( lt_stack ) ].
                ro_xml->mt_nodes[ lv_top ]-last = lines( ro_xml->mt_nodes ).
                DELETE lt_stack INDEX lines( lt_stack ).
              ENDIF.
            WHEN if_sxml_node=>co_nt_value.
              IF lt_stack IS NOT INITIAL.
                lv_top = lt_stack[ lines( lt_stack ) ].
                DATA(lo_value) = CAST if_sxml_value_node( lo_node ).
                ro_xml->mt_nodes[ lv_top ]-value = ro_xml->mt_nodes[ lv_top ]-value && lo_value->get_value( ).
              ENDIF.
            WHEN OTHERS.
          ENDCASE.
        ENDDO.
      " CX_SXML_ERROR ist in ABAP Cloud nicht freigegeben; sXML-Fehler erben von CX_DYNAMIC_CHECK
      CATCH cx_dynamic_check INTO DATA(lx_xml).
        zcprx_cx_error=>raise( iv_text = 'Praxedo-Antwort ist kein gültiges XML' ix_previous = lx_xml ).
    ENDTRY.

    IF ro_xml->mt_nodes IS INITIAL.
      zcprx_cx_error=>raise( 'Praxedo-Antwort ist leer' ).
    ENDIF.
  ENDMETHOD.

  METHOD parse_string.
    ro_xml = parse( to_utf8( iv_xml ) ).
  ENDMETHOD.

  METHOD to_utf8.
    TRY.
        rv_data = cl_abap_conv_codepage=>create_out( )->convert( iv_text ).
      CATCH cx_sy_conversion_codepage INTO DATA(lx_conv).
        zcprx_cx_error=>raise( iv_text = 'Zeichensatzumsetzung fehlgeschlagen' ix_previous = lx_conv ).
    ENDTRY.
  ENDMETHOD.

  METHOD extract_root_part.
    CONSTANTS lc_crlf2 TYPE x LENGTH 4 VALUE '0D0A0D0A'.
    rv_xml = iv_body.

    IF to_lower( iv_content_type ) NS 'multipart/'.
      RETURN.
    ENDIF.
    FIND PCRE `boundary="?([^";]+)"?` IN iv_content_type IGNORING CASE SUBMATCHES DATA(lv_boundary).
    IF sy-subrc <> 0 OR lv_boundary IS INITIAL.
      RETURN.
    ENDIF.

    DATA lv_delim TYPE xstring.
    TRY.
        lv_delim = to_utf8( |--{ lv_boundary }| ).
      CATCH zcprx_cx_error.
        RETURN.
    ENDTRY.

    " 1. Teil = Wurzelteil (CXF schreibt den SOAP-Umschlag immer zuerst)
    FIND FIRST OCCURRENCE OF lv_delim IN iv_body IN BYTE MODE MATCH OFFSET DATA(lv_first).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    DATA(lv_header_from) = lv_first + xstrlen( lv_delim ).
    FIND FIRST OCCURRENCE OF lc_crlf2 IN SECTION OFFSET lv_header_from OF iv_body
         IN BYTE MODE MATCH OFFSET DATA(lv_header_end).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    DATA(lv_from) = lv_header_end + 4.
    FIND FIRST OCCURRENCE OF lv_delim IN SECTION OFFSET lv_from OF iv_body
         IN BYTE MODE MATCH OFFSET DATA(lv_next).
    IF sy-subrc <> 0.
      lv_next = xstrlen( iv_body ).
    ENDIF.
    " CRLF vor dem nächsten Trenner gehört nicht zum Inhalt
    DATA(lv_len) = lv_next - lv_from.
    IF lv_len >= 2.
      DATA(lv_tail) = lv_next - 2.
      IF iv_body+lv_tail(2) = CONV xstring( '0D0A' ).
        lv_len -= 2.
      ENDIF.
    ENDIF.
    IF lv_len > 0.
      rv_xml = iv_body+lv_from(lv_len).
    ENDIF.
  ENDMETHOD.

  METHOD esc.
    rv_value = escape( val = iv_value format = cl_abap_format=>e_xml_text ).
  ENDMETHOD.

  METHOD el.
    CHECK iv_value IS NOT INITIAL.
    rv_xml = |<{ iv_name }>{ esc( iv_value ) }</{ iv_name }>|.
  ENDMETHOD.

  METHOD find.
    DATA(lv_from) = iv_parent + 1.
    DATA(lv_to)   = COND i( WHEN iv_parent = 0 THEN lines( mt_nodes )
                            ELSE VALUE #( mt_nodes[ iv_parent ]-last OPTIONAL ) ).
    CHECK lv_from <= lv_to.
    LOOP AT mt_nodes INTO DATA(ls_node) FROM lv_from TO lv_to WHERE name = iv_name.
      rv_index = ls_node-index.
      RETURN.
    ENDLOOP.
  ENDMETHOD.

  METHOD find_all.
    DATA(lv_from) = iv_parent + 1.
    DATA(lv_to)   = COND i( WHEN iv_parent = 0 THEN lines( mt_nodes )
                            ELSE VALUE #( mt_nodes[ iv_parent ]-last OPTIONAL ) ).
    CHECK lv_from <= lv_to.
    LOOP AT mt_nodes INTO DATA(ls_node) FROM lv_from TO lv_to WHERE name = iv_name.
      APPEND ls_node-index TO rt_index.
    ENDLOOP.
  ENDMETHOD.

  METHOD children.
    " Teilbaum in Dokumentreihenfolge durchlaufen (Reihenfolge der Kinder bleibt erhalten)
    DATA(lv_from) = iv_parent + 1.
    DATA(lv_to)   = COND i( WHEN iv_parent = 0 THEN lines( mt_nodes )
                            ELSE VALUE #( mt_nodes[ iv_parent ]-last OPTIONAL ) ).
    CHECK lv_from <= lv_to.
    LOOP AT mt_nodes INTO DATA(ls_node) FROM lv_from TO lv_to WHERE parent = iv_parent.
      IF iv_name IS INITIAL OR ls_node-name = iv_name.
        APPEND ls_node-index TO rt_index.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD child.
    DATA(lv_from) = iv_parent + 1.
    DATA(lv_to)   = COND i( WHEN iv_parent = 0 THEN lines( mt_nodes )
                            ELSE VALUE #( mt_nodes[ iv_parent ]-last OPTIONAL ) ).
    CHECK lv_from <= lv_to.
    LOOP AT mt_nodes INTO DATA(ls_node) FROM lv_from TO lv_to WHERE parent = iv_parent AND name = iv_name.
      rv_index = ls_node-index.
      RETURN.
    ENDLOOP.
  ENDMETHOD.

  METHOD value.
    CHECK iv_index > 0.
    rv_value = VALUE #( mt_nodes[ iv_index ]-value OPTIONAL ).
  ENDMETHOD.

  METHOD child_value.
    DATA lt_path TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    SPLIT iv_path AT '/' INTO TABLE lt_path.
    DATA(lv_node) = iv_parent.
    LOOP AT lt_path INTO DATA(lv_name).
      lv_node = child( iv_parent = lv_node iv_name = lv_name ).
      IF lv_node = 0.
        RETURN.
      ENDIF.
    ENDLOOP.
    rv_value = value( lv_node ).
  ENDMETHOD.

ENDCLASS.

