INTERFACE zcprx_if_srvord_api PUBLIC.

  TYPES:
    BEGIN OF ty_item,
      service_order_item TYPE c LENGTH 6,
      product            TYPE c LENGTH 40,
      description        TYPE string,
      item_category      TYPE c LENGTH 4,
      quantity           TYPE decfloat34,
      unit               TYPE string,
      planned_start      TYPE utclong,
      planned_end        TYPE utclong,
    END OF ty_item,
    tt_item TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY,

    BEGIN OF ty_service_order,
      service_order TYPE c LENGTH 10,
      order_type    TYPE c LENGTH 4,
      description   TYPE string,
      sold_to_party TYPE c LENGTH 10,
      ship_to_party TYPE c LENGTH 10,
      equipment     TYPE c LENGTH 18,
      planned_start TYPE utclong,
      planned_end   TYPE utclong,
      items         TYPE tt_item,
    END OF ty_service_order,

    tt_service_order_id TYPE STANDARD TABLE OF char10 WITH EMPTY KEY,

    BEGIN OF ty_conf_item,
      service_order_item TYPE c LENGTH 6,
      product            TYPE c LENGTH 40,
      item_category      TYPE c LENGTH 4,
      quantity           TYPE decfloat34,
      unit               TYPE string,
      start_at           TYPE utclong,
      end_at             TYPE utclong,
      plant              TYPE c LENGTH 4,
      storage_location   TYPE c LENGTH 4,
    END OF ty_conf_item,
    tt_conf_item TYPE STANDARD TABLE OF ty_conf_item WITH EMPTY KEY,

    BEGIN OF ty_confirmation,
      service_order TYPE c LENGTH 10,
      description   TYPE string,
      sold_to_party TYPE c LENGTH 10,
      items         TYPE tt_conf_item,
    END OF ty_confirmation.

  METHODS get_service_order
    IMPORTING iv_service_order        TYPE char10
    RETURNING VALUE(rs_service_order) TYPE ty_service_order
    RAISING   zcprx_cx_error.

  METHODS get_changed_service_orders
    IMPORTING iv_since      TYPE utclong
    RETURNING VALUE(rt_ids) TYPE tt_service_order_id
    RAISING   zcprx_cx_error.

  "! Installationsprüfung: Loopback-Arrangement + Berechtigung auf beide APIs
  METHODS ping
    RAISING zcprx_cx_error.

  METHODS create_confirmation
    IMPORTING is_confirmation        TYPE ty_confirmation
    RETURNING VALUE(rv_confirmation) TYPE char10
    RAISING   zcprx_cx_error.

ENDINTERFACE.
