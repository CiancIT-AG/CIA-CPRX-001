CLASS ltcl_praxedo_mapping DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS sample_event RETURNING VALUE(rv_xml) TYPE string.
    METHODS maps_code_status_order    FOR TESTING RAISING cx_static_check.
    METHODS maps_used_items           FOR TESTING RAISING cx_static_check.
    METHODS takes_completion_date     FOR TESTING RAISING cx_static_check.
    METHODS finds_uuid_by_key         FOR TESTING RAISING cx_static_check.
    METHODS finds_uuid_by_pattern     FOR TESTING RAISING cx_static_check.
    METHODS foreign_code_has_no_order FOR TESTING RAISING cx_static_check.
    METHODS path_has_no_double_slash  FOR TESTING.
ENDCLASS.

CLASS ltcl_praxedo_mapping IMPLEMENTATION.
  METHOD sample_event.
    rv_xml = `<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope"><soap:Body>` &&
             `<ns2:getEventsResponse xmlns:ns2="http://ws.praxedo.com/v6/businessEvent"><return><resultCode>0</resultCode>` &&
             `<entities><completionData>` &&
             `<lifecycleTransitionDates><date>2026-11-20T09:00:00.000+01:00</date><name>STARTED</name></lifecycleTransitionDates>` &&
             `<lifecycleTransitionDates><date>2026-11-20T11:30:00.000+01:00</date><name>COMPLETED</name></lifecycleTransitionDates>` &&
             `<usedItems><booked>false</booked><id>MAT-1</id><ordered>false</ordered><quantity>2.0</quantity><storeId>1010/0001</storeId></usedItems>` &&
             `<usedItems><booked>false</booked><id>MAT-2</id><ordered>false</ordered><quantity>0.5</quantity></usedItems>` &&
             `</completionData><coreData><anomaly>false</anomaly><priority>0</priority></coreData>` &&
             `<extensions><key>other</key><value>x</value></extensions>` &&
             `<extensions><key>businessEvent.uuid</key><value>19aebf92-5d8b-4f2d-9a07-c30f07aff26e</value></extensions>` &&
             `<id>8000000123-10</id><status>VALIDATED</status></entities>` &&
             `</return></ns2:getEventsResponse></soap:Body></soap:Envelope>`.
  ENDMETHOD.

  METHOD maps_code_status_order.
    DATA(lo_xml)   = zcprx_cl_xml=>parse_string( sample_event( ) ).
    DATA(ls_order) = zcprx_cl_praxedo_api=>map_event( io_xml = lo_xml iv_node = lo_xml->find( `entities` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `8000000123-10` act = ls_order-id ).
    cl_abap_unit_assert=>assert_equals( exp = `VALIDATED`     act = ls_order-status ).
    cl_abap_unit_assert=>assert_equals( exp = `8000000123`    act = ls_order-service_order ).
    cl_abap_unit_assert=>assert_equals( exp = `10`            act = ls_order-service_order_item ).
  ENDMETHOD.

  METHOD maps_used_items.
    DATA(lo_xml)   = zcprx_cl_xml=>parse_string( sample_event( ) ).
    DATA(ls_order) = zcprx_cl_praxedo_api=>map_event( io_xml = lo_xml iv_node = lo_xml->find( `entities` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( ls_order-materials ) ).
    DATA(ls_first) = ls_order-materials[ 1 ].
    cl_abap_unit_assert=>assert_equals( exp = `MAT-1` act = ls_first-product ).
    cl_abap_unit_assert=>assert_equals( exp = CONV decfloat34( 2 ) act = ls_first-quantity ).
    cl_abap_unit_assert=>assert_equals( exp = `1010` act = ls_first-plant ).
    cl_abap_unit_assert=>assert_equals( exp = `0001` act = ls_first-storage_location ).
    cl_abap_unit_assert=>assert_initial( ls_order-materials[ 2 ]-plant ).
  ENDMETHOD.

  METHOD takes_completion_date.
    DATA(lo_xml)   = zcprx_cl_xml=>parse_string( sample_event( ) ).
    DATA(ls_order) = zcprx_cl_praxedo_api=>map_event( io_xml = lo_xml iv_node = lo_xml->find( `entities` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `2026-11-20T10:30:00Z` act = ls_order-completed_at ).
  ENDMETHOD.

  METHOD finds_uuid_by_key.
    DATA(lo_xml) = zcprx_cl_xml=>parse_string( sample_event( ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = `19aebf92-5d8b-4f2d-9a07-c30f07aff26e`
      act = zcprx_cl_praxedo_api=>extract_uuid( io_xml = lo_xml iv_node = lo_xml->find( `entities` ) iv_key = `uuid` ) ).
  ENDMETHOD.

  METHOD finds_uuid_by_pattern.
    " Schlüssel passt nicht -> UUID-Muster in irgendeiner Extension
    DATA(lo_xml) = zcprx_cl_xml=>parse_string( sample_event( ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = `19aebf92-5d8b-4f2d-9a07-c30f07aff26e`
      act = zcprx_cl_praxedo_api=>extract_uuid( io_xml = lo_xml iv_node = lo_xml->find( `entities` ) iv_key = `reportId` ) ).
  ENDMETHOD.

  METHOD path_has_no_double_slash.
    " Arrangement-Pfad "/" + relativer Pfad = "/eTech/…", nie "//eTech/…"
    cl_abap_unit_assert=>assert_equals( exp = `eTech/services/cxf/v6/BusinessEventManager`
                                        act = zcprx_cl_praxedo_api=>relative_path( `/eTech/services/cxf/v6/BusinessEventManager` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `eTech/rest/api/v1/workOrder/uuid:1/render`
                                        act = zcprx_cl_praxedo_api=>relative_path( `//eTech/rest/api/v1//workOrder/uuid:1/render` ) ).
  ENDMETHOD.

  METHOD foreign_code_has_no_order.
    DATA(lo_xml)   = zcprx_cl_xml=>parse_string( replace( val = sample_event( ) sub = `8000000123-10` with = `PX-4711` ) ).
    DATA(ls_order) = zcprx_cl_praxedo_api=>map_event( io_xml = lo_xml iv_node = lo_xml->find( `entities` ) ).
    cl_abap_unit_assert=>assert_initial( ls_order-service_order ).
  ENDMETHOD.
ENDCLASS.

