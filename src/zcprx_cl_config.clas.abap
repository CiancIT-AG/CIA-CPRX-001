CLASS zcprx_cl_config DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES tt_values TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    CONSTANTS:
      BEGIN OF c_param,
        " Praxedo SOAP v6 / REST v1 (Pfade relativ zum Host im Kommunikationssystem)
        prx_soap_path        TYPE c LENGTH 30 VALUE 'PRX_SOAP_PATH',
        prx_rest_path        TYPE c LENGTH 30 VALUE 'PRX_REST_PATH',
        prx_event_type       TYPE c LENGTH 30 VALUE 'PRX_EVENT_TYPE',
        prx_event_duration   TYPE c LENGTH 30 VALUE 'PRX_EVENT_DURATION',
        prx_agent_id_type    TYPE c LENGTH 30 VALUE 'PRX_AGENT_ID_TYPE',
        prx_populate         TYPE c LENGTH 30 VALUE 'PRX_POPULATE',
        prx_search_dates     TYPE c LENGTH 30 VALUE 'PRX_SEARCH_DATES',
        prx_batch_size       TYPE c LENGTH 30 VALUE 'PRX_BATCH_SIZE',
        prx_uuid_key         TYPE c LENGTH 30 VALUE 'PRX_UUID_KEY',
        prx_cancel_mode      TYPE c LENGTH 30 VALUE 'PRX_CANCEL_MODE',
        activity_types       TYPE c LENGTH 30 VALUE 'ACTIVITY_TYPES',
        activity_products    TYPE c LENGTH 30 VALUE 'ACTIVITY_PRODUCTS',
        activity_validated   TYPE c LENGTH 30 VALUE 'ACTIVITY_VALIDATED',
        default_item_cat     TYPE c LENGTH 30 VALUE 'DEFAULT_ITEM_CAT',
        " Bericht (PDF) -> Anlage am Serviceauftrag
        report_statuses      TYPE c LENGTH 30 VALUE 'REPORT_STATUSES',
        report_path          TYPE c LENGTH 30 VALUE 'REPORT_PATH',
        attach_api_path      TYPE c LENGTH 30 VALUE 'ATTACH_API_PATH',
        attach_object_type   TYPE c LENGTH 30 VALUE 'ATTACH_OBJECT_TYPE',
        " SAP-Loopback-APIs (Service Order / Service Confirmation)
        so_api_path          TYPE c LENGTH 30 VALUE 'SO_API_PATH',
        so_changed_field     TYPE c LENGTH 30 VALUE 'SO_CHANGED_FIELD',
        conf_api_path        TYPE c LENGTH 30 VALUE 'CONF_API_PATH',
        conf_type            TYPE c LENGTH 30 VALUE 'CONF_TYPE',
        conf_itemcat_time    TYPE c LENGTH 30 VALUE 'CONF_ITEMCAT_TIME',
        conf_itemcat_mat     TYPE c LENGTH 30 VALUE 'CONF_ITEMCAT_MAT',
        conf_completed_field TYPE c LENGTH 30 VALUE 'CONF_COMPLETED_FIELD',
        default_srv_product  TYPE c LENGTH 30 VALUE 'DEFAULT_SRV_PRODUCT',
        " Filter
        relevant_so_types    TYPE c LENGTH 30 VALUE 'RELEVANT_SO_TYPES',
        relevant_item_cats   TYPE c LENGTH 30 VALUE 'RELEVANT_ITEM_CATS',
        product_types        TYPE c LENGTH 30 VALUE 'PRODUCT_TYPES',
        completed_statuses   TYPE c LENGTH 30 VALUE 'COMPLETED_STATUSES',
        " Laufzeit
        last_fetch_ts        TYPE c LENGTH 30 VALUE 'LAST_FETCH_TS',
        last_delta_ts        TYPE c LENGTH 30 VALUE 'LAST_DELTA_TS',
        max_retries          TYPE c LENGTH 30 VALUE 'MAX_RETRIES',
        package_size         TYPE c LENGTH 30 VALUE 'PACKAGE_SIZE',
        " Mail-Alerting
        alert_active         TYPE c LENGTH 30 VALUE 'ALERT_ACTIVE',
        alert_recipients     TYPE c LENGTH 30 VALUE 'ALERT_RECIPIENTS',
        alert_sender         TYPE c LENGTH 30 VALUE 'ALERT_SENDER',
        alert_throttle_min   TYPE c LENGTH 30 VALUE 'ALERT_THROTTLE_MIN',
        alert_ts_prefix      TYPE c LENGTH 30 VALUE 'ALERT_TS_',
        " Installation: eingeplante Jobs ('JOB_<NAME>' = Jobname;Jobcount)
        job_prefix           TYPE c LENGTH 30 VALUE 'JOB_',
        " Queue: Backoff/Timeout
        retry_base_min       TYPE c LENGTH 30 VALUE 'RETRY_BASE_MIN',
        retry_max_min        TYPE c LENGTH 30 VALUE 'RETRY_MAX_MIN',
        running_timeout_min  TYPE c LENGTH 30 VALUE 'RUNNING_TIMEOUT_MIN',
        fetch_overlap_min    TYPE c LENGTH 30 VALUE 'FETCH_OVERLAP_MIN',
      END OF c_param.

    TYPES:
      BEGIN OF ty_default,
        param TYPE c LENGTH 30,
        value TYPE string,
      END OF ty_default,
      tt_default TYPE STANDARD TABLE OF ty_default WITH EMPTY KEY.

    "! Ausgelieferte Standardwerte (gleich für alle Kunden). Kundenspezifisch
    "! sind nur die Werte, die das Installationsprotokoll als "prüfen" meldet.
    CLASS-METHODS get_defaults
      RETURNING VALUE(rt_defaults) TYPE tt_default.

    "! Schreibt fehlende Standardwerte in ZCPRXCFG (vorhandene bleiben)
    CLASS-METHODS init_defaults
      RETURNING VALUE(rv_inserted) TYPE i.

    CLASS-METHODS get
      IMPORTING iv_param        TYPE csequence
                iv_default      TYPE csequence OPTIONAL
      RETURNING VALUE(rv_value) TYPE string.

    "! Kommagetrennte Werteliste, z. B. 'SVO1,SVO2'
    CLASS-METHODS get_list
      IMPORTING iv_param         TYPE csequence
      RETURNING VALUE(rt_values) TYPE tt_values.

    "! Schreibt Wert; Commit durch Aufrufer
    CLASS-METHODS set
      IMPORTING iv_param TYPE csequence
                iv_value TYPE csequence.

    "! Puffer verwerfen (z. B. nach Pflege in der App während eines langen Laufs)
    CLASS-METHODS refresh.

    "! Nicht mehr verwendete Parameter (REST-Pfade vor SOAP-Umstellung) löschen
    CLASS-METHODS delete_obsolete
      RETURNING VALUE(rv_deleted) TYPE i.

    "! Ganzzahliger Parameter; ungültig/leer -> Standardwert, mind. iv_min
    CLASS-METHODS get_int
      IMPORTING iv_param        TYPE csequence
                iv_min          TYPE i DEFAULT 0
      RETURNING VALUE(rv_value) TYPE i.

  PRIVATE SECTION.
    TYPES tt_cache TYPE HASHED TABLE OF zcprxcfg WITH UNIQUE KEY param.
    CLASS-DATA gt_cache  TYPE tt_cache.
    CLASS-DATA gv_loaded TYPE abap_bool.

    "! Laufzeitwerte (Zeitstempel, Jobnummern) nie puffern
    CLASS-METHODS is_volatile
      IMPORTING iv_param         TYPE csequence
      RETURNING VALUE(rv_result) TYPE abap_bool.
ENDCLASS.

CLASS zcprx_cl_config IMPLEMENTATION.

  METHOD get.
    DATA lv_value TYPE zcprxcfg-value.
    DATA(lv_param) = CONV zcprxcfg-param( iv_param ).

    IF is_volatile( lv_param ) = abap_true.
      SELECT SINGLE value FROM zcprxcfg WHERE param = @lv_param INTO @lv_value.
    ELSE.
      IF gv_loaded = abap_false.
        SELECT * FROM zcprxcfg INTO TABLE @gt_cache.
        gv_loaded = abap_true.
      ENDIF.
      lv_value = VALUE #( gt_cache[ param = lv_param ]-value OPTIONAL ).
    ENDIF.

    IF lv_value IS NOT INITIAL.
      rv_value = condense( lv_value ).
    ELSEIF iv_default IS SUPPLIED.
      rv_value = iv_default.
    ELSE.
      " Fallback: ausgelieferter Standardwert
      READ TABLE get_defaults( ) INTO DATA(ls_default) WITH KEY param = lv_param.
      rv_value = ls_default-value.
    ENDIF.
  ENDMETHOD.

  METHOD get_defaults.
    rt_defaults = VALUE #(
      " Praxedo SOAP v6 (Manager-Name wird angehängt) und REST v1
      ( param = c_param-prx_soap_path       value = `/eTech/services/cxf/v6` )
      ( param = c_param-prx_rest_path       value = `/eTech/rest/api/v1` )
      ( param = c_param-prx_event_type      value = `` )                  " Pflicht: Praxedo-Einsatztyp
      ( param = c_param-prx_event_duration  value = `60` )                " Minuten ohne Planzeitraum
      ( param = c_param-prx_agent_id_type   value = `praxedoEntityId` )   " oder externalEntityId
      ( param = c_param-prx_populate        value = `coreData,qualificationData,completionData.items,completionData.lifecycleTransitionDate` )
      ( param = c_param-prx_search_dates    value = `completionDate,validationDate` )
      ( param = c_param-prx_batch_size      value = `50` )
      ( param = c_param-prx_uuid_key        value = `uuid` )
      ( param = c_param-prx_cancel_mode     value = `CANCEL` )            " CANCEL | DELETE
      ( param = c_param-activity_types      value = `` )                  " leer = alle Aktivitätstypen
      ( param = c_param-activity_products   value = `` )                  " TYP=PRODUKT,…
      ( param = c_param-activity_validated  value = `` )                  " leer | true | false
      ( param = c_param-default_item_cat    value = `` )
      ( param = c_param-report_statuses     value = `VALIDATED` )
      ( param = c_param-report_path         value = `/workOrder/uuid:{UUID}/render` )
      ( param = c_param-attach_api_path     value = `/sap/opu/odata/sap/API_CV_ATTACHMENT_SRV` )
      ( param = c_param-attach_object_type  value = `BUS2000116` )
      ( param = c_param-so_api_path         value = `/sap/opu/odata/sap/API_SERVICE_ORDER_SRV` )
      ( param = c_param-so_changed_field    value = `ServiceDocChangedDateTime` )
      ( param = c_param-conf_api_path       value = `/sap/opu/odata/sap/API_SERVICE_CONFIRMATION_SRV` )
      ( param = c_param-conf_type           value = `SVC1` )
      ( param = c_param-conf_itemcat_time   value = `` )
      ( param = c_param-conf_itemcat_mat    value = `` )
      ( param = c_param-conf_completed_field value = `` )
      ( param = c_param-default_srv_product value = `` )
      ( param = c_param-relevant_so_types   value = `` )
      ( param = c_param-relevant_item_cats  value = `` )
      ( param = c_param-product_types       value = `` )
      ( param = c_param-completed_statuses  value = `COMPLETED,VALIDATED` )
      ( param = c_param-max_retries         value = `5` )
      ( param = c_param-package_size        value = `500` )
      ( param = c_param-alert_active        value = `X` )
      ( param = c_param-alert_recipients    value = `` )
      ( param = c_param-alert_sender        value = `` )
      ( param = c_param-alert_throttle_min  value = `60` )
      ( param = c_param-retry_base_min      value = `5` )
      ( param = c_param-retry_max_min       value = `60` )
      ( param = c_param-running_timeout_min value = `30` )
      ( param = c_param-fetch_overlap_min   value = `5` ) ).
  ENDMETHOD.

  METHOD get_int.
    TRY.
        rv_value = CONV i( condense( get( iv_param ) ) ).
      CATCH cx_sy_conversion_error.
        DATA(lv_param) = CONV zcprxcfg-param( iv_param ).
        READ TABLE get_defaults( ) INTO DATA(ls_default) WITH KEY param = lv_param.
        TRY.
            rv_value = CONV i( ls_default-value ).
          CATCH cx_sy_conversion_error.
            rv_value = iv_min.
        ENDTRY.
    ENDTRY.
    rv_value = nmax( val1 = rv_value val2 = iv_min ).
  ENDMETHOD.

  METHOD refresh.
    CLEAR: gt_cache, gv_loaded.
  ENDMETHOD.

  METHOD is_volatile.
    DATA(lv_param) = to_upper( CONV string( iv_param ) ).
    rv_result = xsdbool( lv_param CP 'LAST_*'
                      OR lv_param CP |{ c_param-job_prefix }*|
                      OR lv_param CP |{ c_param-alert_ts_prefix }*| ).
  ENDMETHOD.

  METHOD init_defaults.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.
    SELECT param FROM zcprxcfg INTO TABLE @DATA(lt_existing).

    LOOP AT get_defaults( ) INTO DATA(ls_default).
      CHECK NOT line_exists( lt_existing[ param = ls_default-param ] ).
      INSERT zcprxcfg FROM @( VALUE #( param           = ls_default-param
                                          value           = ls_default-value
                                          last_changed_at = lv_now ) ).
      IF sy-subrc = 0.
        rv_inserted += 1.
      ENDIF.
    ENDLOOP.
    refresh( ).
  ENDMETHOD.

  METHOD delete_obsolete.
    DELETE FROM zcprxcfg WHERE param LIKE 'PATH\_%' ESCAPE '\' OR param = 'REPORT_ID'.
    rv_deleted = sy-dbcnt.
    " Alter Standardwert existiert in A_ServiceOrder nicht
    UPDATE zcprxcfg SET value = 'ServiceDocChangedDateTime'
      WHERE param = 'SO_CHANGED_FIELD' AND value = 'LastChangeDateTime'.
    rv_deleted = rv_deleted + sy-dbcnt.
    refresh( ).
  ENDMETHOD.

  METHOD get_list.
    DATA(lv_value) = get( iv_param ).
    CHECK lv_value IS NOT INITIAL.
    SPLIT lv_value AT ',' INTO TABLE rt_values.
    LOOP AT rt_values ASSIGNING FIELD-SYMBOL(<lv_value>).
      <lv_value> = condense( <lv_value> ).
    ENDLOOP.
    DELETE rt_values WHERE table_line IS INITIAL.
  ENDMETHOD.

  METHOD set.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.
    DATA(ls_row) = VALUE zcprxcfg( param           = iv_param
                                       value           = iv_value
                                       last_changed_at = lv_now ).
    MODIFY zcprxcfg FROM @ls_row.
    IF gv_loaded = abap_true AND is_volatile( iv_param ) = abap_false.
      DELETE gt_cache WHERE param = ls_row-param.
      INSERT ls_row INTO TABLE gt_cache.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

