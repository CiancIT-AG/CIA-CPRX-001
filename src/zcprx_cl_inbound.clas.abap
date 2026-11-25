CLASS zcprx_cl_inbound DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING io_praxedo TYPE REF TO zcprx_if_praxedo_api OPTIONAL.

    "! Alle seit dem letzten Lauf abgeschlossenen Praxedo-Aufträge holen
    METHODS fetch_completed
      IMPORTING io_log          TYPE REF TO zcprx_cl_log
      RETURNING VALUE(rv_count) TYPE i
      RAISING   zcprx_cx_error.

    "! Einzelnen Einsatz aktualisieren (Admin-Action)
    METHODS fetch_order
      IMPORTING iv_order_uuid TYPE sysuuid_x16
      RAISING   zcprx_cx_error.

  PRIVATE SECTION.
    DATA mo_praxedo TYPE REF TO zcprx_if_praxedo_api.

    "! @parameter rv_stored | X = gespeichert, '' = übersprungen (verbucht/unbekannt)
    METHODS store
      IMPORTING is_praxedo       TYPE zcprx_if_praxedo_api=>ty_completed_order
      RETURNING VALUE(rv_stored) TYPE abap_bool
      RAISING   zcprx_cx_error.

    METHODS is_completed
      IMPORTING iv_status        TYPE string
      RETURNING VALUE(rv_result) TYPE abap_bool.

    METHODS report_due
      IMPORTING iv_praxedo_status TYPE csequence
                iv_report_status  TYPE csequence
      RETURNING VALUE(rv_result)  TYPE abap_bool.

    METHODS fill_units
      CHANGING ct_materials TYPE zcprx_if_praxedo_api=>tt_material.
ENDCLASS.

CLASS zcprx_cl_inbound IMPLEMENTATION.

  METHOD constructor.
    mo_praxedo = COND #( WHEN io_praxedo IS BOUND THEN io_praxedo ELSE NEW zcprx_cl_praxedo_api( ) ).
  ENDMETHOD.

  METHOD fetch_completed.
    DATA lv_failed TYPE i.

    " Laufbeginn (nicht Laufende) merken; Abfrage mit Überlappung gegen
    " Uhrzeitabweichungen. store() ist idempotent, Doppellieferungen sind unkritisch.
    DATA(lv_run_start) = utclong_current( ).
    DATA(lv_last)      = zcprx_cl_mapper=>from_iso(
                           zcprx_cl_config=>get( iv_param   = zcprx_cl_config=>c_param-last_fetch_ts
                                                     iv_default = '1970-01-01T00:00:00Z' ) ).
    DATA(lv_overlap)   = zcprx_cl_config=>get_int( zcprx_cl_config=>c_param-fetch_overlap_min ).
    DATA(lv_since)     = zcprx_cl_mapper=>to_iso(
                           COND #( WHEN lv_last IS INITIAL THEN lv_last
                                   ELSE utclong_add( val = lv_last minutes = - lv_overlap ) ) ).
    IF lv_since IS INITIAL.
      lv_since = `1970-01-01T00:00:00Z`.
    ENDIF.

    DATA(lt_orders) = mo_praxedo->get_completed_orders( lv_since ).
    io_log->info( |{ lines( lt_orders ) } abgeschlossene Praxedo-Aufträge seit { lv_since }| ).

    LOOP AT lt_orders INTO DATA(ls_order).
      TRY.
          IF store( ls_order ) = abap_true.
            rv_count += 1.
          ENDIF.
        CATCH zcprx_cx_error INTO DATA(lx_error).
          lv_failed += 1.
          io_log->error( |Praxedo { ls_order-id }: { lx_error->get_text( ) }| ).
      ENDTRY.
    ENDLOOP.

    " Zeitstempel nur fortschreiben, wenn alles gespeichert wurde. Sonst
    " holt der nächste Lauf dieselben Aufträge erneut (z. B. nach Draft-Sperre).
    IF lv_failed = 0.
      zcprx_cl_config=>set( iv_param = zcprx_cl_config=>c_param-last_fetch_ts
                                iv_value = zcprx_cl_mapper=>to_iso( lv_run_start ) ).
      COMMIT WORK.
    ELSE.
      io_log->warning( |{ lv_failed } Rückmeldung(en) fehlerhaft – Zeitstempel bleibt, nächster Lauf wiederholt| ).
    ENDIF.
  ENDMETHOD.

  METHOD fetch_order.
    SELECT SINGLE PraxedoId FROM zcprx_r_order WHERE OrderUUID = @iv_order_uuid INTO @DATA(lv_praxedo_id).
    IF lv_praxedo_id IS INITIAL.
      zcprx_cx_error=>raise( 'Einsatz hat keine Praxedo-ID' ).
    ENDIF.
    store( mo_praxedo->get_order( CONV #( lv_praxedo_id ) ) ).
  ENDMETHOD.

  METHOD report_due.
    " Bericht fällig: Praxedo-Status in REPORT_STATUSES und noch nicht angehängt
    rv_result = xsdbool( zcprx_cl_report=>is_report_status( iv_praxedo_status ) = abap_true
                     AND iv_report_status <> zcprx_if_constants=>report_status-attached ).
  ENDMETHOD.

  METHOD fill_units.
    " Praxedo kennt keine Mengeneinheit -> Basismengeneinheit des Produkts
    LOOP AT ct_materials ASSIGNING FIELD-SYMBOL(<ls_material>) WHERE unit IS INITIAL AND product IS NOT INITIAL.
      DATA lv_product TYPE I_Product-Product.
      lv_product = <ls_material>-product.
      SELECT SINGLE BaseUnit FROM I_Product WHERE Product = @lv_product INTO @DATA(lv_unit).
      IF sy-subrc = 0.
        <ls_material>-unit = lv_unit.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD store.
    DATA(st) = zcprx_if_constants=>order_status.
    DATA lv_uuid          TYPE sysuuid_x16.
    DATA lv_status        TYPE c LENGTH 12.
    DATA lv_report_status TYPE c LENGTH 12.

    " 1) Einsatz ermitteln: Praxedo-ID, sonst Serviceauftrag/Position
    SELECT SINGLE OrderUUID, Status, ReportStatus FROM zcprx_r_order
      WHERE PraxedoId = @is_praxedo-id
      INTO (@lv_uuid, @lv_status, @lv_report_status).

    IF sy-subrc <> 0 AND is_praxedo-service_order IS NOT INITIAL.
      SELECT SINGLE OrderUUID, Status, ReportStatus FROM zcprx_r_order
        WHERE ServiceOrder     = @is_praxedo-service_order
          AND ServiceOrderItem = @is_praxedo-service_order_item
          AND Status          <> @st-cancelled
        INTO (@lv_uuid, @lv_status, @lv_report_status).
    ENDIF.

    DATA(lv_completed)  = is_completed( is_praxedo-status ).
    DATA(lv_report_due) = report_due( iv_praxedo_status = is_praxedo-status iv_report_status = lv_report_status ).

    " 2) Unbekannt -> nur abgeschlossene Aufträge mit Serviceauftragsbezug anlegen
    IF lv_uuid IS INITIAL.
      IF lv_completed = abap_false.
        RETURN.                                   " offener Fremdauftrag – ignorieren
      ENDIF.
      IF is_praxedo-service_order IS INITIAL.
        zcprx_cx_error=>raise( iv_text = |Praxedo-Auftrag { is_praxedo-id } ohne Serviceauftragsbezug| iv_permanent = abap_true ).
      ENDIF.
      MODIFY ENTITIES OF zcprx_r_order
        ENTITY Order CREATE FIELDS ( ServiceOrder ServiceOrderItem Description )
        WITH VALUE #( ( %cid             = 'NEW'
                        ServiceOrder     = is_praxedo-service_order
                        ServiceOrderItem = is_praxedo-service_order_item
                        Description      = |Praxedo { is_praxedo-id }| ) )
        MAPPED DATA(ls_mapped)
        FAILED DATA(ls_create_failed) ##NEEDED.
      IF ls_mapped-order IS INITIAL.
        ROLLBACK ENTITIES.
        zcprx_cx_error=>raise( |Einsatz zu Praxedo { is_praxedo-id } konnte nicht angelegt werden| ).
      ENDIF.
      lv_uuid   = ls_mapped-order[ 1 ]-OrderUUID.
      lv_status = st-new.
    ENDIF.

    " 3) Statusprüfung
    IF lv_status = st-cancelled.
      ROLLBACK ENTITIES.
      RETURN.                                     " storniert
    ENDIF.
    IF lv_status = st-in_process.
      ROLLBACK ENTITIES.
      zcprx_cx_error=>raise( |Einsatz zu Praxedo { is_praxedo-id } in Verarbeitung| ).
    ENDIF.

    " 4) Zeiten/Materialien ersetzen (nur nicht verbuchte) – nur wenn abgeschlossen
    "    und noch nicht verbucht. Verbuchte Einsätze bekommen nur noch
    "    Praxedo-Status/UUID (z. B. VALIDATED -> Bericht anhängen).
    IF lv_completed = abap_true AND lv_status <> st-processed.
      READ ENTITIES OF zcprx_r_order
        ENTITY Order BY \_Time     FIELDS ( IsPosted ) WITH VALUE #( ( OrderUUID = lv_uuid ) ) RESULT DATA(lt_time)
        ENTITY Order BY \_Material FIELDS ( IsPosted ) WITH VALUE #( ( OrderUUID = lv_uuid ) ) RESULT DATA(lt_material).
      DELETE lt_time     WHERE IsPosted = abap_true.
      DELETE lt_material WHERE IsPosted = abap_true.

      DATA(lv_default_product) = zcprx_cl_config=>get( zcprx_cl_config=>c_param-default_srv_product ).
      DATA(lt_new_material)    = is_praxedo-materials.
      fill_units( CHANGING ct_materials = lt_new_material ).

      MODIFY ENTITIES OF zcprx_r_order
        ENTITY OrderTime     DELETE FROM VALUE #( FOR old_t IN lt_time     ( %tky = old_t-%tky ) )
        ENTITY OrderMaterial DELETE FROM VALUE #( FOR old_m IN lt_material ( %tky = old_m-%tky ) )
        ENTITY Order
          CREATE BY \_Time
            FIELDS ( PraxedoLineId Technician ServiceProduct StartAt EndAt Duration DurationUnit )
            WITH VALUE #( ( OrderUUID = lv_uuid
                            %target   = VALUE #( FOR t IN is_praxedo-times INDEX INTO i
                                          ( %cid           = |T{ i }|
                                            PraxedoLineId  = t-line_id
                                            Technician     = t-technician
                                            ServiceProduct = COND #( WHEN t-product IS NOT INITIAL THEN t-product ELSE lv_default_product )
                                            StartAt        = zcprx_cl_mapper=>from_iso( t-start_at )
                                            EndAt          = zcprx_cl_mapper=>from_iso( t-end_at )
                                            Duration       = t-duration
                                            DurationUnit   = COND #( WHEN t-unit IS NOT INITIAL THEN t-unit ELSE 'H' ) ) ) ) )
          CREATE BY \_Material
            FIELDS ( PraxedoLineId Product Quantity QuantityUnit Plant StorageLocation )
            WITH VALUE #( ( OrderUUID = lv_uuid
                            %target   = VALUE #( FOR m IN lt_new_material INDEX INTO j
                                          ( %cid            = |M{ j }|
                                            PraxedoLineId   = m-line_id
                                            Product         = m-product
                                            Quantity        = m-quantity
                                            QuantityUnit    = m-unit
                                            Plant           = m-plant
                                            StorageLocation = m-storage_location ) ) ) )
        FAILED DATA(ls_child_failed) ##NEEDED.

      IF ls_child_failed IS NOT INITIAL.
        ROLLBACK ENTITIES.
        zcprx_cx_error=>raise( |Zeiten/Materialien zu Praxedo { is_praxedo-id } fehlerhaft| ).
      ENDIF.
    ENDIF.

    " 5) Status: abgeschlossen -> RECEIVED (verbuchbar), verbucht bleibt PROCESSED,
    "    sonst Status beibehalten. Bericht fällig -> ReportStatus OPEN.
    MODIFY ENTITIES OF zcprx_r_order
      ENTITY Order EXECUTE setInboundData
      FROM VALUE #( ( OrderUUID = lv_uuid
                      %param    = VALUE #( PraxedoId     = is_praxedo-id
                                           PraxedoUUID   = is_praxedo-uuid
                                           PraxedoStatus = is_praxedo-status
                                           ReportStatus  = COND #( WHEN lv_report_due = abap_true
                                                                   THEN zcprx_if_constants=>report_status-open )
                                           Status        = COND #( WHEN lv_status = st-processed THEN lv_status
                                                                   WHEN lv_completed = abap_true THEN st-received
                                                                   WHEN lv_status IS INITIAL     THEN st-sent
                                                                   ELSE lv_status )
                                           MessageText   = `` ) ) )
      FAILED DATA(ls_action_failed).
    IF ls_action_failed IS NOT INITIAL.
      ROLLBACK ENTITIES.
      zcprx_cx_error=>raise( |Rückmeldung Praxedo { is_praxedo-id }: Einsatz gesperrt (offener Draft?)| ).
    ENDIF.

    COMMIT ENTITIES RESPONSE OF zcprx_r_order
      FAILED DATA(ls_commit_failed)
      REPORTED DATA(ls_commit_reported) ##NEEDED.
    IF ls_commit_failed IS NOT INITIAL.
      zcprx_cx_error=>raise( |Rückmeldung Praxedo { is_praxedo-id } konnte nicht gespeichert werden| ).
    ENDIF.

    " 6) Bericht anhängen entkoppelt über die Queue (Job OUTBOUND bzw. REPORT
    "    verarbeitet den Eintrag; kein bgPF, da store() selbst im bgPF laufen kann)
    IF lv_report_due = abap_true.
      zcprx_cl_queue=>enqueue( it_entries    = VALUE #( ( object_type = zcprx_if_constants=>object_type-order
                                                              operation   = zcprx_if_constants=>operation-report
                                                              object_key  = |{ lv_uuid }| ) )
                                   iv_start_bgpf = abap_false ).
      COMMIT WORK.
    ENDIF.
    rv_stored = abap_true.
  ENDMETHOD.

  METHOD is_completed.
    DATA(lt_status) = zcprx_cl_config=>get_list( zcprx_cl_config=>c_param-completed_statuses ).
    IF lt_status IS INITIAL.
      lt_status = VALUE #( ( `COMPLETED` ) ( `VALIDATED` ) ).
    ENDIF.
    rv_result = xsdbool( line_exists( lt_status[ table_line = to_upper( iv_status ) ] ) ).
  ENDMETHOD.

ENDCLASS.

