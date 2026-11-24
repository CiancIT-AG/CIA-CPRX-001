INTERFACE zcprx_if_constants PUBLIC.

  CONSTANTS:
    BEGIN OF order_status,
      new        TYPE c LENGTH 12 VALUE 'NEW',
      in_process TYPE c LENGTH 12 VALUE 'IN_PROCESS',
      sent       TYPE c LENGTH 12 VALUE 'SENT',
      received   TYPE c LENGTH 12 VALUE 'RECEIVED',
      processed  TYPE c LENGTH 12 VALUE 'PROCESSED',
      error      TYPE c LENGTH 12 VALUE 'ERROR',
      cancelled  TYPE c LENGTH 12 VALUE 'CANCELLED',
    END OF order_status.

  CONSTANTS:
    BEGIN OF sync_status,
      new        TYPE c LENGTH 12 VALUE 'NEW',
      in_process TYPE c LENGTH 12 VALUE 'IN_PROCESS',
      sent       TYPE c LENGTH 12 VALUE 'SENT',
      error      TYPE c LENGTH 12 VALUE 'ERROR',
    END OF sync_status.

  CONSTANTS:
    BEGIN OF queue_status,
      new        TYPE c LENGTH 12 VALUE 'NEW',
      running    TYPE c LENGTH 12 VALUE 'RUNNING',
      done       TYPE c LENGTH 12 VALUE 'DONE',
      error      TYPE c LENGTH 12 VALUE 'ERROR',
    END OF queue_status.

  " Berechtigungsobjekt ZCPRXA, Feld ACTVT
  CONSTANTS:
    BEGIN OF activity,
      create  TYPE c LENGTH 2 VALUE '01',
      change  TYPE c LENGTH 2 VALUE '02',
      display TYPE c LENGTH 2 VALUE '03',
      delete  TYPE c LENGTH 2 VALUE '06',
      execute TYPE c LENGTH 2 VALUE '16',
    END OF activity.

  CONSTANTS:
    BEGIN OF object_type,
      order          TYPE c LENGTH 10 VALUE 'ORDER',
      service_order  TYPE c LENGTH 10 VALUE 'SRVORD',
      product        TYPE c LENGTH 10 VALUE 'PRODUCT',
      product_group  TYPE c LENGTH 10 VALUE 'PRODGRP',
      equipment_type TYPE c LENGTH 10 VALUE 'EQTYPE',
    END OF object_type.

  CONSTANTS:
    BEGIN OF operation,
      upsert TYPE c LENGTH 10 VALUE 'UPSERT',
      delete TYPE c LENGTH 10 VALUE 'DELETE',
      fetch  TYPE c LENGTH 10 VALUE 'FETCH',
      post   TYPE c LENGTH 10 VALUE 'POST',
    END OF operation.

  " Application-Log-Objekt (ADT: New > Application Log Object)
  CONSTANTS:
    BEGIN OF log,
      object      TYPE c LENGTH 20 VALUE 'ZCPRX_LOG',
      sub_queue   TYPE c LENGTH 20 VALUE 'QUEUE',
      sub_out     TYPE c LENGTH 20 VALUE 'OUTBOUND',
      sub_fetch   TYPE c LENGTH 20 VALUE 'FETCH',
      sub_post    TYPE c LENGTH 20 VALUE 'POST',
      sub_product TYPE c LENGTH 20 VALUE 'PRODUCTS',
      sub_report  TYPE c LENGTH 20 VALUE 'REPORT',
      sub_setup   TYPE c LENGTH 20 VALUE 'SETUP',
      sub_alert   TYPE c LENGTH 20 VALUE 'ALERT',
      sub_event   TYPE c LENGTH 20 VALUE 'EVENT',
    END OF log.

ENDINTERFACE.
