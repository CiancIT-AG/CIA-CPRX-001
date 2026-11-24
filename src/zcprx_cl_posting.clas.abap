CLASS zcprx_cl_posting DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES:
      tt_time     TYPE TABLE FOR READ RESULT zcprx_r_order\\OrderTime,
      tt_material TYPE TABLE FOR READ RESULT zcprx_r_order\\OrderMaterial.
    TYPES ty_order TYPE STRUCTURE FOR READ RESULT zcprx_r_order\\Order.

    METHODS constructor
      IMPORTING io_srvord TYPE REF TO zcprx_if_srvord_api OPTIONAL.

    METHODS post_order
      IMPORTING iv_order_uuid TYPE sysuuid_x16
      RAISING   zcprx_cx_error.

    "! Job: alle rückgemeldeten Einsätze (Status RECEIVED) verbuchen
    METHODS post_all_received
      IMPORTING io_log          TYPE REF TO zcprx_cl_log
                iv_max          TYPE i DEFAULT 500
      RETURNING VALUE(rv_count) TYPE i.

    "! Reine Abbildung Einsatz -> Servicebestätigung (ohne DB/HTTP, testbar)
    "! Nur nicht verbuchte Zeilen; Zeiten -> Leistung, Material -> Material.
    METHODS build_confirmation
      IMPORTING is_order               TYPE ty_order
                it_time                TYPE tt_time
                it_material            TYPE tt_material
                iv_itemcat_time        TYPE csequence OPTIONAL
                iv_itemcat_material    TYPE csequence OPTIONAL
                iv_default_product     TYPE csequence OPTIONAL
      RETURNING VALUE(rs_confirmation) TYPE zcprx_if_srvord_api=>ty_confirmation.

  PRIVATE SECTION.
    DATA mo_srvord TYPE REF TO zcprx_if_srvord_api.

    METHODS set_result
      IMPORTING iv_order_uuid   TYPE sysuuid_x16
                iv_status       TYPE c
                iv_confirmation TYPE char10 OPTIONAL
                iv_message      TYPE string OPTIONAL
      RETURNING VALUE(rv_ok)    TYPE abap_bool.

    METHODS persist_fallback
      IMPORTING iv_order_uuid   TYPE sysuuid_x16
                iv_confirmation TYPE char10.
ENDCLASS.

CLASS zcprx_cl_posting IMPLEMENTATION.

  METHOD constructor.
    mo_srvord = COND #( WHEN io_srvord IS BOUND THEN io_srvord ELSE NEW zcprx_cl_srvord_api( ) ).
  ENDMETHOD.

  METHOD post_order.
    DATA(st) = zcprx_if_constants=>order_status.

    " 1) Sperre vor jeder Buchung (verhindert Buchung während offenem Draft)
    SET LOCKS OF zcprx_r_order
      ENTITY Order FROM VALUE #( ( OrderUUID = iv_order_uuid ) )
      FAILED DATA(ls_lock_failed).
    IF ls_lock_failed IS NOT INITIAL.
      ROLLBACK ENTITIES.
      zcprx_cx_error=>raise( |Einsatz { iv_order_uuid } gesperrt (Draft/anderer Benutzer) – Retry folgt| ).
    ENDIF.

    READ ENTITIES OF zcprx_r_order
      ENTITY Order ALL FIELDS WITH VALUE #( ( OrderUUID = iv_order_uuid ) ) RESULT DATA(lt_order)
      ENTITY Order BY \_Time     ALL FIELDS WITH VALUE #( ( OrderUUID = iv_order_uuid ) ) RESULT DATA(lt_time)
      ENTITY Order BY \_Material ALL FIELDS WITH VALUE #( ( OrderUUID = iv_order_uuid ) ) RESULT DATA(lt_material).

    IF lt_order IS INITIAL.
      ROLLBACK ENTITIES.
      zcprx_cx_error=>raise( iv_text = |Einsatz { iv_order_uuid } nicht gefunden| iv_permanent = abap_true ).
    ENDIF.
    DATA(ls_order) = lt_order[ 1 ].

    IF ls_order-Status <> st-received AND ls_order-Status <> st-error AND ls_order-Status <> st-in_process.
      ROLLBACK ENTITIES.
      zcprx_cx_error=>raise( iv_text      = |Einsatz { ls_order-ServiceOrder }/{ ls_order-ServiceOrderItem } ist nicht verbuchbar (Status { ls_order-Status })|
                                 iv_permanent = abap_true ).
    ENDIF.

    " 2) Bestätigung existiert bereits -> nur Status nachziehen
    IF ls_order-ServiceConfirmation IS NOT INITIAL.
      set_result( iv_order_uuid = iv_order_uuid iv_status = st-processed iv_confirmation = ls_order-ServiceConfirmation ).
      RETURN.
    ENDIF.

    DATA(ls_conf) = build_confirmation(
      is_order            = ls_order
      it_time             = lt_time
      it_material         = lt_material
      iv_itemcat_time     = zcprx_cl_config=>get( zcprx_cl_config=>c_param-conf_itemcat_time )
      iv_itemcat_material = zcprx_cl_config=>get( zcprx_cl_config=>c_param-conf_itemcat_mat )
      iv_default_product  = zcprx_cl_config=>get( zcprx_cl_config=>c_param-default_srv_product ) ).

    IF ls_conf-items IS INITIAL.
      set_result( iv_order_uuid = iv_order_uuid iv_status = st-error iv_message = `Keine Zeiten/Materialien zum Verbuchen` ).
      zcprx_cx_error=>raise( iv_text = 'Keine Zeiten/Materialien zum Verbuchen' iv_permanent = abap_true ).
    ENDIF.
    IF line_exists( ls_conf-items[ product = '' ] ).
      set_result( iv_order_uuid = iv_order_uuid iv_status = st-error
                  iv_message    = `Zeit ohne Leistungsartikel – DEFAULT_SRV_PRODUCT pflegen oder Zeile ergänzen` ).
      zcprx_cx_error=>raise( iv_text = 'Zeit ohne Leistungsartikel' iv_permanent = abap_true ).
    ENDIF.

    " 3) Buchen (Sperre wird bis zum Speichern des Ergebnisses gehalten)
    TRY.
        DATA(lv_confirmation) = mo_srvord->create_confirmation( ls_conf ).
      CATCH zcprx_cx_error INTO DATA(lx_error).
        set_result( iv_order_uuid = iv_order_uuid iv_status = st-error iv_message = lx_error->get_text( ) ).
        RAISE EXCEPTION lx_error.
    ENDTRY.

    IF set_result( iv_order_uuid   = iv_order_uuid
                   iv_status       = st-processed
                   iv_confirmation = lv_confirmation ) = abap_false.
      persist_fallback( iv_order_uuid = iv_order_uuid iv_confirmation = lv_confirmation ).
    ENDIF.
  ENDMETHOD.

  METHOD build_confirmation.
    rs_confirmation = VALUE #( service_order = is_order-ServiceOrder
                               description   = |Praxedo { is_order-PraxedoId } { is_order-Description }|
                               sold_to_party = is_order-SoldToParty ).

    " Zeiten -> Leistungspositionen
    LOOP AT it_time INTO DATA(ls_time) WHERE IsPosted = abap_false.
      APPEND VALUE #( service_order_item = is_order-ServiceOrderItem
                      product            = COND #( WHEN ls_time-ServiceProduct IS NOT INITIAL
                                                   THEN ls_time-ServiceProduct ELSE iv_default_product )
                      item_category      = iv_itemcat_time
                      quantity           = ls_time-Duration
                      unit               = ls_time-DurationUnit
                      start_at           = ls_time-StartAt
                      end_at             = ls_time-EndAt ) TO rs_confirmation-items.
    ENDLOOP.

    " Materialien -> Material-/Ersatzteilpositionen
    LOOP AT it_material INTO DATA(ls_material) WHERE IsPosted = abap_false.
      APPEND VALUE #( service_order_item = is_order-ServiceOrderItem
                      product            = ls_material-Product
                      item_category      = iv_itemcat_material
                      quantity           = ls_material-Quantity
                      unit               = ls_material-QuantityUnit
                      plant              = ls_material-Plant
                      storage_location   = ls_material-StorageLocation ) TO rs_confirmation-items.
    ENDLOOP.
  ENDMETHOD.

  METHOD post_all_received.
    SELECT OrderUUID, ServiceOrder, ServiceOrderItem
      FROM zcprx_r_order
      WHERE Status = @zcprx_if_constants=>order_status-received
      ORDER BY LastFetchAt
      INTO TABLE @DATA(lt_orders)
      UP TO @iv_max ROWS.

    io_log->info( |{ lines( lt_orders ) } rückgemeldete Einsätze zum Verbuchen| ).

    LOOP AT lt_orders INTO DATA(ls_order).
      TRY.
          post_order( ls_order-OrderUUID ).
          rv_count += 1.
          io_log->success( |{ ls_order-ServiceOrder }/{ ls_order-ServiceOrderItem } verbucht| ).
        CATCH zcprx_cx_error INTO DATA(lx_error).
          " gesperrte Einsätze sind kein Fehler, nur Warnung (nächster Lauf)
          IF lx_error->mv_permanent = abap_true.
            io_log->error( |{ ls_order-ServiceOrder }/{ ls_order-ServiceOrderItem }: { lx_error->get_text( ) }| ).
          ELSE.
            io_log->warning( |{ ls_order-ServiceOrder }/{ ls_order-ServiceOrderItem }: { lx_error->get_text( ) }| ).
          ENDIF.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

  METHOD set_result.
    MODIFY ENTITIES OF zcprx_r_order
      ENTITY Order EXECUTE setPostingResult
      FROM VALUE #( ( OrderUUID = iv_order_uuid
                      %param    = VALUE #( ServiceConfirmation = iv_confirmation
                                           Status              = iv_status
                                           MessageText         = iv_message ) ) )
      FAILED DATA(ls_failed).
    IF ls_failed IS NOT INITIAL.
      ROLLBACK ENTITIES.
      RETURN.
    ENDIF.
    COMMIT ENTITIES RESPONSE OF zcprx_r_order FAILED DATA(ls_commit_failed) ##NEEDED.
    rv_ok = xsdbool( ls_commit_failed IS INITIAL ).
  ENDMETHOD.

  METHOD persist_fallback.
    " Letzte Rückfallebene: Bestätigung ist gebucht, BO-Speichern scheiterte.
    " Direktes Schreiben in die eigene Tabelle verhindert eine Doppelbuchung.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.
    UPDATE zcprxord
      SET service_confirmation = @iv_confirmation,
          status               = @zcprx_if_constants=>order_status-processed,
          posted_at            = @lv_now,
          message_text         = 'Ergebnis per Rückfallebene gespeichert',
          last_changed_at      = @lv_now,
          local_last_changed_at = @lv_now
      WHERE order_uuid = @iv_order_uuid.
    UPDATE zcprxtim SET is_posted = @abap_true WHERE order_uuid = @iv_order_uuid.
    UPDATE zcprxmat SET is_posted = @abap_true WHERE order_uuid = @iv_order_uuid.
    COMMIT WORK.

    DATA(lo_log) = zcprx_cl_log=>create( zcprx_if_constants=>log-sub_post ).
    lo_log->warning( |Bestätigung { iv_confirmation } per Rückfallebene am Einsatz gespeichert| ).
    lo_log->save( ).
  ENDMETHOD.

ENDCLASS.
