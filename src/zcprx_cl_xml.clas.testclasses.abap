CLASS ltcl_xml DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS sample_soap RETURNING VALUE(rv_xml) TYPE string.
    METHODS parses_and_navigates     FOR TESTING RAISING cx_static_check.
    METHODS finds_paths              FOR TESTING RAISING cx_static_check.
    METHODS extracts_mtom_root_part  FOR TESTING RAISING cx_static_check.
    METHODS plain_body_is_unchanged  FOR TESTING RAISING cx_static_check.
    METHODS escapes_and_skips_empty  FOR TESTING.
    METHODS rejects_invalid_xml      FOR TESTING.
ENDCLASS.

CLASS ltcl_xml IMPLEMENTATION.
  METHOD sample_soap.
    rv_xml = `<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">` &&
             `<soap:Body><ns2:createItemsResponse xmlns:ns2="http://ws.praxedo.com/v6/customermodel">` &&
             `<return><resultCode>0</resultCode><results><resultCode>0</resultCode><id>A1</id></results>` &&
             `<results><message>Kategorie fehlt</message><resultCode>12</resultCode><id>A2</id></results>` &&
             `</return></ns2:createItemsResponse></soap:Body></soap:Envelope>`.
  ENDMETHOD.

  METHOD parses_and_navigates.
    DATA(lo_xml)     = zcprx_cl_xml=>parse_string( sample_soap( ) ).
    DATA(lv_return)  = lo_xml->find( `return` ).
    DATA(lt_results) = lo_xml->children( iv_parent = lv_return iv_name = `results` ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( lt_results ) ).
    cl_abap_unit_assert=>assert_equals( exp = `0`  act = lo_xml->child_value( iv_parent = lv_return iv_path = `resultCode` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `A2` act = lo_xml->child_value( iv_parent = lt_results[ 2 ] iv_path = `id` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `12` act = lo_xml->child_value( iv_parent = lt_results[ 2 ] iv_path = `resultCode` ) ).
  ENDMETHOD.

  METHOD finds_paths.
    DATA(lo_xml) = zcprx_cl_xml=>parse_string( sample_soap( ) ).
    " Pfad nimmt jeweils das erste Kind gleichen Namens: results[1] hat keine message
    cl_abap_unit_assert=>assert_initial( lo_xml->child_value( iv_parent = lo_xml->find( `return` ) iv_path = `results/message` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `A1`
                                        act = lo_xml->child_value( iv_parent = lo_xml->find( `return` ) iv_path = `results/id` ) ).
    " find sucht nur im Teilbaum
    DATA(lt_results) = lo_xml->children( iv_parent = lo_xml->find( `return` ) iv_name = `results` ).
    cl_abap_unit_assert=>assert_initial( lo_xml->find( iv_name = `message` iv_parent = lt_results[ 1 ] ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Kategorie fehlt`
                                        act = lo_xml->child_value( iv_parent = lt_results[ 2 ] iv_path = `message` ) ).
    cl_abap_unit_assert=>assert_initial( lo_xml->find( `gibtsnicht` ) ).
  ENDMETHOD.

  METHOD extracts_mtom_root_part.
    DATA(lv_mtom) = |--uuid:abc\r\nContent-Type: application/xop+xml; type="application/soap+xml"\r\n| &&
                    |Content-ID: <root.message@cxf.apache.org>\r\n\r\n{ sample_soap( ) }\r\n--uuid:abc--|.
    DATA(lv_root) = zcprx_cl_xml=>extract_root_part(
                      iv_body         = zcprx_cl_xml=>to_utf8( lv_mtom )
                      iv_content_type = `multipart/related; type="application/xop+xml"; boundary="uuid:abc"; start="<root.message@cxf.apache.org>"` ).
    cl_abap_unit_assert=>assert_equals( exp = zcprx_cl_xml=>to_utf8( sample_soap( ) ) act = lv_root ).
    DATA(lo_xml) = zcprx_cl_xml=>parse( lv_root ).
    cl_abap_unit_assert=>assert_differs( exp = 0 act = lo_xml->find( `createItemsResponse` ) ).
  ENDMETHOD.

  METHOD plain_body_is_unchanged.
    DATA(lv_body) = zcprx_cl_xml=>to_utf8( sample_soap( ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = lv_body
      act = zcprx_cl_xml=>extract_root_part( iv_body = lv_body iv_content_type = `application/soap+xml; charset=UTF-8` ) ).
  ENDMETHOD.

  METHOD escapes_and_skips_empty.
    cl_abap_unit_assert=>assert_equals( exp = `<name>A &amp; B &lt;1</name>`
                                        act = zcprx_cl_xml=>el( iv_name = `name` iv_value = `A & B <1` ) ).
    cl_abap_unit_assert=>assert_initial( zcprx_cl_xml=>el( iv_name = `name` iv_value = `` ) ).
  ENDMETHOD.

  METHOD rejects_invalid_xml.
    TRY.
        zcprx_cl_xml=>parse_string( `<a><b></a>` ).
        cl_abap_unit_assert=>fail( msg = 'Ausnahme erwartet' ).
      CATCH zcprx_cx_error ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

