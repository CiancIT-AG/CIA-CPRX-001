INTERFACE zcprx_if_praxedo_api PUBLIC.

  TYPES:
    BEGIN OF ty_address,
      street   TYPE string,
      zip_code TYPE string,
      city     TYPE string,
      country  TYPE string,
    END OF ty_address,

    BEGIN OF ty_customer,
      external_id TYPE string,
      name        TYPE string,
      phone       TYPE string,
      address     TYPE ty_address,
    END OF ty_customer,

    BEGIN OF ty_location,
      external_id TYPE string,
      name        TYPE string,
      customer_id TYPE string,
      address     TYPE ty_address,
    END OF ty_location,

    BEGIN OF ty_equipment,
      external_id   TYPE string,
      name          TYPE string,
      serial_number TYPE string,
      type_id       TYPE string,
      customer_id   TYPE string,
      location_id   TYPE string,
    END OF ty_equipment,

    BEGIN OF ty_order,
      id                 TYPE string,   " Praxedo-Code (leer = external_id)
      external_id        TYPE string,
      service_order      TYPE string,
      service_order_item TYPE string,
      description        TYPE string,
      customer_id        TYPE string,
      location_id        TYPE string,
      equipment_id       TYPE string,
      technician         TYPE string,
      planned_start      TYPE string,   " ISO 8601 UTC
      planned_end        TYPE string,
    END OF ty_order,

    BEGIN OF ty_time,
      line_id    TYPE string,
      technician TYPE string,
      product    TYPE string,
      start_at   TYPE string,
      end_at     TYPE string,
      duration   TYPE decfloat34,
      unit       TYPE string,
    END OF ty_time,
    tt_time TYPE STANDARD TABLE OF ty_time WITH EMPTY KEY,

    BEGIN OF ty_material,
      line_id          TYPE string,
      product          TYPE string,
      quantity         TYPE decfloat34,
      unit             TYPE string,
      plant            TYPE string,
      storage_location TYPE string,
    END OF ty_material,
    tt_material TYPE STANDARD TABLE OF ty_material WITH EMPTY KEY,

    BEGIN OF ty_completed_order,
      id                 TYPE string,   " Praxedo-Code des Einsatzes
      uuid               TYPE string,   " Praxedo-UUID (für den Bericht)
      external_id        TYPE string,
      service_order      TYPE string,
      service_order_item TYPE string,
      status             TYPE string,
      completed_at       TYPE string,
      times              TYPE tt_time,
      materials          TYPE tt_material,
    END OF ty_completed_order,
    tt_completed_order TYPE STANDARD TABLE OF ty_completed_order WITH EMPTY KEY,

    BEGIN OF ty_product,
      external_id TYPE string,
      name        TYPE string,
      group_id    TYPE string,
      unit        TYPE string,
    END OF ty_product,
    tt_product TYPE STANDARD TABLE OF ty_product WITH EMPTY KEY,

    "! Artikelgruppen / Equipmenttypen
    BEGIN OF ty_code,
      external_id TYPE string,
      name        TYPE string,
    END OF ty_code,
    tt_code TYPE STANDARD TABLE OF ty_code WITH EMPTY KEY,

    BEGIN OF ty_id_result,
      external_id TYPE string,
      id          TYPE string,
      error       TYPE string,
    END OF ty_id_result,
    tt_id_result TYPE STANDARD TABLE OF ty_id_result WITH EMPTY KEY.

  METHODS upsert_customer
    IMPORTING is_customer  TYPE ty_customer
    RETURNING VALUE(rv_id) TYPE string
    RAISING   zcprx_cx_error.

  METHODS upsert_location
    IMPORTING is_location  TYPE ty_location
    RETURNING VALUE(rv_id) TYPE string
    RAISING   zcprx_cx_error.

  METHODS upsert_equipment
    IMPORTING is_equipment TYPE ty_equipment
    RETURNING VALUE(rv_id) TYPE string
    RAISING   zcprx_cx_error.

  "! Einsatz anlegen bzw. ändern (BusinessEventManager), mit Techniker einplanen
  METHODS upsert_order
    IMPORTING is_order     TYPE ty_order
    RETURNING VALUE(rv_id) TYPE string
    RAISING   zcprx_cx_error.

  "! Einsatz stornieren (cancelEvent) bzw. löschen (Konfig PRX_CANCEL_MODE)
  METHODS delete_order
    IMPORTING iv_id TYPE string
    RAISING   zcprx_cx_error.

  "! Einsatz inkl. Zeiten (ActivityManager) und Material lesen
  METHODS get_order
    IMPORTING iv_id           TYPE string
    RETURNING VALUE(rs_order) TYPE ty_completed_order
    RAISING   zcprx_cx_error.

  "! Abgeschlossene/validierte Einsätze inkl. Zeiten & Materialien seit Zeitpunkt
  METHODS get_completed_orders
    IMPORTING iv_since         TYPE string
    RETURNING VALUE(rt_orders) TYPE tt_completed_order
    RAISING   zcprx_cx_error.

  METHODS upsert_products
    IMPORTING it_products      TYPE tt_product
    RETURNING VALUE(rt_result) TYPE tt_id_result
    RAISING   zcprx_cx_error.

  METHODS upsert_product_groups
    IMPORTING it_groups        TYPE tt_code
    RETURNING VALUE(rt_result) TYPE tt_id_result
    RAISING   zcprx_cx_error.

  METHODS upsert_equipment_types
    IMPORTING it_types         TYPE tt_code
    RETURNING VALUE(rt_result) TYPE tt_id_result
    RAISING   zcprx_cx_error.

  "! Installationsprüfung: SOAP-Aufruf + REST-v1-Arrangement
  METHODS ping
    RAISING zcprx_cx_error.

  "! Einsatzbericht als PDF (REST v1 render, ohne Anmeldung)
  METHODS get_report_pdf
    IMPORTING iv_uuid       TYPE string
              iv_code       TYPE string
    RETURNING VALUE(rv_pdf) TYPE xstring
    RAISING   zcprx_cx_error.

ENDINTERFACE.
