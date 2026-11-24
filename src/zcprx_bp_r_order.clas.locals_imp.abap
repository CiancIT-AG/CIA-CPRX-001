" Tab "Local Types" (CCIMP)

" Transaktionspuffer: Queue-Einträge, die in save_modified geschrieben
" werden (Delete/Post/Fetch). Upserts werden über SyncRequired erkannt.
CLASS lcl_buffer DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-DATA mt_entries TYPE zcprx_cl_queue=>tt_entry.
ENDCLASS.

" Handler Order
CLASS lhc_order DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Order RESULT result.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Order RESULT result.

    METHODS precheck_delete FOR PRECHECK
      IMPORTING keys FOR DELETE Order.

    METHODS setinitialvalues FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Order~setInitialValues.

    METHODS markforsync FOR DETERMINE ON SAVE
      IMPORTING keys FOR Order~markForSync.

    METHODS validateserviceorder FOR VALIDATE ON SAVE
      IMPORTING keys FOR Order~validateServiceOrder.

    METHODS validateperiod FOR VALIDATE ON SAVE
      IMPORTING keys FOR Order~validatePeriod.

    METHODS sendtopraxedo FOR MODIFY
      IMPORTING keys FOR ACTION Order~sendToPraxedo RESULT result.

    METHODS fetchfrompraxedo FOR MODIFY
      IMPORTING keys FOR ACTION Order~fetchFromPraxedo RESULT result.

    METHODS post FOR MODIFY
      IMPORTING keys FOR ACTION Order~post RESULT result.

    METHODS reseterror FOR MODIFY
      IMPORTING keys FOR ACTION Order~resetError RESULT result.

    METHODS cancel FOR MODIFY
      IMPORTING keys FOR ACTION Order~cancel RESULT result.

    METHODS setsyncresult FOR MODIFY
      IMPORTING keys FOR ACTION Order~setSyncResult RESULT result.

    METHODS setinbounddata FOR MODIFY
      IMPORTING keys FOR ACTION Order~setInboundData RESULT result.

    METHODS setpostingresult FOR MODIFY
      IMPORTING keys FOR ACTION Order~setPostingResult RESULT result.
ENDCLASS.

CLASS lhc_order IMPLEMENTATION.

  METHOD get_global_authorizations.
    " Berechtigungsobjekt ZCPRXA (ACTVT), siehe ZCPRX_CL_AUTH.
    " Technische Actions (set*) sind nicht im Service veröffentlicht und
    " werden nur von Adapter-Klassen aufgerufen -> Ausführen (16).
    DATA(act) = zcprx_if_constants=>activity.
    DATA(lv_create)  = COND #( WHEN zcprx_cl_auth=>is_allowed( act-create )  = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    DATA(lv_change)  = COND #( WHEN zcprx_cl_auth=>is_allowed( act-change )  = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    DATA(lv_delete)  = COND #( WHEN zcprx_cl_auth=>is_allowed( act-delete )  = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    DATA(lv_execute) = COND #( WHEN zcprx_cl_auth=>is_allowed( act-execute ) = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).

    result = VALUE #( %create                   = lv_create
                      %update                   = lv_change
                      %delete                   = lv_delete
                      %action-sendToPraxedo     = lv_execute
                      %action-fetchFromPraxedo  = lv_execute
                      %action-post              = lv_execute
                      %action-resetError        = lv_execute
                      %action-cancel            = lv_execute
                      %action-setSyncResult     = lv_execute
                      %action-setInboundData    = lv_execute
                      %action-setPostingResult  = lv_execute ).
  ENDMETHOD.

  METHOD get_instance_features.
    DATA(st) = zcprx_if_constants=>order_status.

    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order FIELDS ( Status PraxedoId ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_order)
      FAILED failed.

    LOOP AT lt_order INTO DATA(ls_order).
      DATA(lv_draft)  = xsdbool( ls_order-%is_draft = if_abap_behv=>mk-on ).
      DATA(lv_locked) = xsdbool( ls_order-Status = st-processed
                              OR ls_order-Status = st-in_process
                              OR ls_order-Status = st-cancelled ).
      DATA(lv_post)   = xsdbool( lv_draft = abap_false
                             AND ( ls_order-Status = st-received OR ls_order-Status = st-error ) ).
      DATA(lv_send)   = xsdbool( lv_draft = abap_false AND lv_locked = abap_false
                             AND ls_order-Status <> st-received ).
      DATA(lv_fetch)  = xsdbool( lv_draft = abap_false AND lv_locked = abap_false
                             AND ls_order-PraxedoId IS NOT INITIAL ).
      DATA(lv_reset)  = xsdbool( lv_draft = abap_false AND ls_order-Status = st-error ).
      " Löschen nur, solange nichts zurückgemeldet ist; danach Stornieren
      DATA(lv_delete) = xsdbool( ls_order-Status = st-new OR ls_order-Status = st-sent
                              OR ls_order-Status = st-error OR ls_order-Status = st-cancelled
                              OR ls_order-Status IS INITIAL ).
      DATA(lv_cancel) = xsdbool( lv_draft = abap_false
                             AND ( ls_order-Status = st-new OR ls_order-Status = st-sent OR ls_order-Status = st-error ) ).

      APPEND VALUE #(
        %tky                     = ls_order-%tky
        %update                  = COND #( WHEN lv_locked = abap_true THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
        %delete                  = COND #( WHEN lv_delete = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
        %action-Edit             = COND #( WHEN lv_locked = abap_true THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
        %assoc-_Time             = COND #( WHEN lv_locked = abap_true THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
        %assoc-_Material         = COND #( WHEN lv_locked = abap_true THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
        %action-sendToPraxedo    = COND #( WHEN lv_send  = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
        %action-fetchFromPraxedo = COND #( WHEN lv_fetch = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
        %action-post             = COND #( WHEN lv_post  = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
        %action-resetError       = COND #( WHEN lv_reset  = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
        %action-cancel           = COND #( WHEN lv_cancel = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
      ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD precheck_delete.
    " Beim Löschen eines aktiven Einsatzes wird der Auftrag auch in
    " Praxedo gelöscht (asynchron über Queue + bgPF).
    " Nur in den Status NEW/SENT/ERROR/CANCELLED erlaubt (Feature Control).
    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order FIELDS ( PraxedoId Status ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_order).

    " Stornierte sind in Praxedo bereits gelöscht
    LOOP AT lt_order INTO DATA(ls_order) WHERE %is_draft = if_abap_behv=>mk-off
                                           AND PraxedoId IS NOT INITIAL
                                           AND Status <> zcprx_if_constants=>order_status-cancelled.
      APPEND VALUE #( object_type = zcprx_if_constants=>object_type-order
                      operation   = zcprx_if_constants=>operation-delete
                      object_key  = ls_order-PraxedoId ) TO lcl_buffer=>mt_entries.
    ENDLOOP.
  ENDMETHOD.

  METHOD setinitialvalues.
    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order FIELDS ( Status ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_order).

    DELETE lt_order WHERE Status IS NOT INITIAL.
    CHECK lt_order IS NOT INITIAL.

    MODIFY ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order UPDATE FIELDS ( Status )
      WITH VALUE #( FOR o IN lt_order ( %tky   = o-%tky
                                        Status = zcprx_if_constants=>order_status-new ) ).
  ENDMETHOD.

  METHOD markforsync.
    " Geschäftlich relevante Änderung -> Übertragung nach Praxedo nötig.
    " Rückgemeldete/verbuchte Einsätze werden nicht erneut gesendet.
    DATA(st) = zcprx_if_constants=>order_status.

    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order FIELDS ( Status ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_order).

    DELETE lt_order WHERE Status = st-received
                       OR Status = st-processed
                       OR Status = st-in_process
                       OR Status = st-cancelled.
    CHECK lt_order IS NOT INITIAL.

    MODIFY ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order UPDATE FIELDS ( SyncRequired Status )
      WITH VALUE #( FOR o IN lt_order ( %tky         = o-%tky
                                        SyncRequired = abap_true
                                        Status       = st-in_process ) ).
  ENDMETHOD.

  METHOD validateserviceorder.
    DATA lv_exists TYPE abap_bool.

    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order FIELDS ( ServiceOrder ServiceOrderItem ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_order).

    LOOP AT lt_order INTO DATA(ls_order).
      APPEND VALUE #( %tky = ls_order-%tky %state_area = 'VAL_SO' ) TO reported-order.

      IF ls_order-ServiceOrder IS INITIAL OR ls_order-ServiceOrderItem IS INITIAL.
        APPEND VALUE #( %tky = ls_order-%tky ) TO failed-order.
        APPEND VALUE #( %tky        = ls_order-%tky
                        %state_area = 'VAL_SO'
                        %msg        = new_message_with_text(
                                        severity = if_abap_behv_message=>severity-error
                                        text     = 'Serviceauftrag und Position sind Pflichtfelder' )
                        %element-ServiceOrder     = if_abap_behv=>mk-on
                        %element-ServiceOrderItem = if_abap_behv=>mk-on ) TO reported-order.
        CONTINUE.
      ENDIF.

      CLEAR lv_exists.
      SELECT SINGLE @abap_true FROM zcprxord
        WHERE service_order      = @ls_order-ServiceOrder
          AND service_order_item = @ls_order-ServiceOrderItem
          AND order_uuid        <> @ls_order-OrderUUID
          AND status            <> @zcprx_if_constants=>order_status-cancelled
        INTO @lv_exists.

      IF lv_exists = abap_true.
        APPEND VALUE #( %tky = ls_order-%tky ) TO failed-order.
        APPEND VALUE #( %tky        = ls_order-%tky
                        %state_area = 'VAL_SO'
                        %msg        = new_message_with_text(
                                        severity = if_abap_behv_message=>severity-error
                                        text     = |Für { ls_order-ServiceOrder }/{ ls_order-ServiceOrderItem } existiert bereits ein Einsatz| )
                        %element-ServiceOrder = if_abap_behv=>mk-on ) TO reported-order.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD validateperiod.
    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order FIELDS ( PlannedStart PlannedEnd ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_order).

    LOOP AT lt_order INTO DATA(ls_order).
      APPEND VALUE #( %tky = ls_order-%tky %state_area = 'VAL_PERIOD' ) TO reported-order.
      IF ls_order-PlannedStart IS NOT INITIAL AND ls_order-PlannedEnd IS NOT INITIAL
         AND ls_order-PlannedEnd < ls_order-PlannedStart.
        APPEND VALUE #( %tky = ls_order-%tky ) TO failed-order.
        APPEND VALUE #( %tky        = ls_order-%tky
                        %state_area = 'VAL_PERIOD'
                        %msg        = new_message_with_text(
                                        severity = if_abap_behv_message=>severity-error
                                        text     = 'Geplantes Ende liegt vor dem geplanten Beginn' )
                        %element-PlannedEnd = if_abap_behv=>mk-on ) TO reported-order.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD sendtopraxedo.
    " SyncRequired = X -> save_modified legt Queue-Eintrag ORDER/UPSERT an
    MODIFY ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order UPDATE FIELDS ( Status SyncRequired MessageText )
      WITH VALUE #( FOR k IN keys ( %tky         = k-%tky
                                    Status       = zcprx_if_constants=>order_status-in_process
                                    SyncRequired = abap_true
                                    MessageText  = '' ) ).

    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_result).
    result = VALUE #( FOR r IN lt_result ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

  METHOD fetchfrompraxedo.
    LOOP AT keys INTO DATA(ls_key).
      APPEND VALUE #( object_type = zcprx_if_constants=>object_type-order
                      operation   = zcprx_if_constants=>operation-fetch
                      object_key  = |{ ls_key-OrderUUID }| ) TO lcl_buffer=>mt_entries.
    ENDLOOP.

    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_result).
    result = VALUE #( FOR r IN lt_result ( %tky = r-%tky %param = r ) ).

    APPEND new_message_with_text( severity = if_abap_behv_message=>severity-information
                                  text     = 'Rückmeldung von Praxedo wurde angestoßen' ) TO reported-%other.
  ENDMETHOD.

  METHOD post.
    DATA(st) = zcprx_if_constants=>order_status.
    DATA lt_update TYPE TABLE FOR UPDATE zcprx_r_order\\Order.

    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order FIELDS ( Status ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_order).

    LOOP AT lt_order INTO DATA(ls_order).
      IF ls_order-Status <> st-received AND ls_order-Status <> st-error.
        APPEND VALUE #( %tky = ls_order-%tky ) TO failed-order.
        APPEND VALUE #( %tky = ls_order-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = 'Nur rückgemeldete oder fehlerhafte Einsätze können verbucht werden' ) ) TO reported-order.
        CONTINUE.
      ENDIF.

      APPEND VALUE #( object_type = zcprx_if_constants=>object_type-order
                      operation   = zcprx_if_constants=>operation-post
                      object_key  = |{ ls_order-OrderUUID }| ) TO lcl_buffer=>mt_entries.
      APPEND VALUE #( %tky                = ls_order-%tky
                      Status              = st-in_process
                      MessageText         = ''
                      %control-Status      = if_abap_behv=>mk-on
                      %control-MessageText = if_abap_behv=>mk-on ) TO lt_update.
    ENDLOOP.

    IF lt_update IS NOT INITIAL.
      MODIFY ENTITIES OF zcprx_r_order IN LOCAL MODE
        ENTITY Order UPDATE FROM lt_update.
    ENDIF.

    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_result).
    result = VALUE #( FOR r IN lt_result ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

  METHOD reseterror.
    DATA(st) = zcprx_if_constants=>order_status.

    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order FIELDS ( LastFetchAt ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_order).

    " Bereits rückgemeldet -> wieder RECEIVED (verbuchbar), sonst NEW
    MODIFY ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order UPDATE FIELDS ( Status MessageText )
      WITH VALUE #( FOR o IN lt_order ( %tky        = o-%tky
                                        Status      = COND #( WHEN o-LastFetchAt IS NOT INITIAL
                                                              THEN st-received ELSE st-new )
                                        MessageText = '' ) ).

    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_result).
    result = VALUE #( FOR r IN lt_result ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

  METHOD cancel.
    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order FIELDS ( PraxedoId ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_order).

    LOOP AT lt_order INTO DATA(ls_order) WHERE PraxedoId IS NOT INITIAL.
      APPEND VALUE #( object_type = zcprx_if_constants=>object_type-order
                      operation   = zcprx_if_constants=>operation-delete
                      object_key  = ls_order-PraxedoId ) TO lcl_buffer=>mt_entries.
    ENDLOOP.

    MODIFY ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order UPDATE FIELDS ( Status SyncRequired MessageText )
      WITH VALUE #( FOR o IN lt_order ( %tky         = o-%tky
                                        Status       = zcprx_if_constants=>order_status-cancelled
                                        SyncRequired = abap_false
                                        MessageText  = '' ) ).

    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_result).
    result = VALUE #( FOR r IN lt_result ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

  METHOD setsyncresult.
    DATA lt_update TYPE TABLE FOR UPDATE zcprx_r_order\\Order.
    DATA lv_now    TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    LOOP AT keys INTO DATA(ls_key).
      APPEND VALUE #( %tky                  = ls_key-%tky
                      Status                = ls_key-%param-Status
                      MessageText           = ls_key-%param-MessageText
                      SyncRequired          = abap_false
                      LastSyncAt            = lv_now
                      %control-Status       = if_abap_behv=>mk-on
                      %control-MessageText  = if_abap_behv=>mk-on
                      %control-SyncRequired = if_abap_behv=>mk-on
                      %control-LastSyncAt   = if_abap_behv=>mk-on ) TO lt_update ASSIGNING FIELD-SYMBOL(<ls_update>).
      IF ls_key-%param-PraxedoId IS NOT INITIAL.
        <ls_update>-PraxedoId          = ls_key-%param-PraxedoId.
        <ls_update>-%control-PraxedoId = if_abap_behv=>mk-on.
      ENDIF.
    ENDLOOP.

    MODIFY ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order UPDATE FROM lt_update.

    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_result).
    result = VALUE #( FOR r IN lt_result ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

  METHOD setinbounddata.
    DATA lt_update TYPE TABLE FOR UPDATE zcprx_r_order\\Order.
    DATA lv_now    TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    LOOP AT keys INTO DATA(ls_key).
      APPEND VALUE #( %tky                   = ls_key-%tky
                      Status                 = ls_key-%param-Status
                      PraxedoStatus          = ls_key-%param-PraxedoStatus
                      MessageText            = ls_key-%param-MessageText
                      LastFetchAt            = lv_now
                      %control-Status        = if_abap_behv=>mk-on
                      %control-PraxedoStatus = if_abap_behv=>mk-on
                      %control-MessageText   = if_abap_behv=>mk-on
                      %control-LastFetchAt   = if_abap_behv=>mk-on ) TO lt_update ASSIGNING FIELD-SYMBOL(<ls_update>).
      IF ls_key-%param-PraxedoId IS NOT INITIAL.
        <ls_update>-PraxedoId          = ls_key-%param-PraxedoId.
        <ls_update>-%control-PraxedoId = if_abap_behv=>mk-on.
      ENDIF.
    ENDLOOP.

    MODIFY ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order UPDATE FROM lt_update.

    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_result).
    result = VALUE #( FOR r IN lt_result ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

  METHOD setpostingresult.
    DATA lt_update     TYPE TABLE FOR UPDATE zcprx_r_order\\Order.
    DATA lt_time_upd   TYPE TABLE FOR UPDATE zcprx_r_order\\OrderTime.
    DATA lt_mat_upd    TYPE TABLE FOR UPDATE zcprx_r_order\\OrderMaterial.
    DATA lv_now        TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    LOOP AT keys INTO DATA(ls_key).
      APPEND VALUE #( %tky                 = ls_key-%tky
                      Status               = ls_key-%param-Status
                      MessageText          = ls_key-%param-MessageText
                      %control-Status      = if_abap_behv=>mk-on
                      %control-MessageText = if_abap_behv=>mk-on ) TO lt_update ASSIGNING FIELD-SYMBOL(<ls_update>).

      IF ls_key-%param-ServiceConfirmation IS NOT INITIAL.
        <ls_update>-ServiceConfirmation          = ls_key-%param-ServiceConfirmation.
        <ls_update>-%control-ServiceConfirmation = if_abap_behv=>mk-on.
      ENDIF.

      IF ls_key-%param-Status = zcprx_if_constants=>order_status-processed.
        <ls_update>-PostedAt          = lv_now.
        <ls_update>-%control-PostedAt = if_abap_behv=>mk-on.

        " Zeiten und Materialien als verbucht kennzeichnen
        READ ENTITIES OF zcprx_r_order IN LOCAL MODE
          ENTITY Order BY \_Time FIELDS ( IsPosted ) WITH VALUE #( ( %tky = ls_key-%tky ) )
          RESULT DATA(lt_time)
          ENTITY Order BY \_Material FIELDS ( IsPosted ) WITH VALUE #( ( %tky = ls_key-%tky ) )
          RESULT DATA(lt_material).

        LOOP AT lt_time INTO DATA(ls_time) WHERE IsPosted = abap_false.
          APPEND VALUE #( %tky = ls_time-%tky IsPosted = abap_true %control-IsPosted = if_abap_behv=>mk-on ) TO lt_time_upd.
        ENDLOOP.
        LOOP AT lt_material INTO DATA(ls_material) WHERE IsPosted = abap_false.
          APPEND VALUE #( %tky = ls_material-%tky IsPosted = abap_true %control-IsPosted = if_abap_behv=>mk-on ) TO lt_mat_upd.
        ENDLOOP.
      ENDIF.
    ENDLOOP.

    MODIFY ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order         UPDATE FROM lt_update
      ENTITY OrderTime     UPDATE FROM lt_time_upd
      ENTITY OrderMaterial UPDATE FROM lt_mat_upd.

    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY Order ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_result).
    result = VALUE #( FOR r IN lt_result ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

ENDCLASS.

" Handler Zeiten / Materialien (Feature Control)
CLASS lhc_ordertime DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR OrderTime RESULT result.
ENDCLASS.

CLASS lhc_ordertime IMPLEMENTATION.
  METHOD get_instance_features.
    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY OrderTime FIELDS ( IsPosted ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_time) FAILED failed.

    result = VALUE #( FOR t IN lt_time
      ( %tky    = t-%tky
        %update = COND #( WHEN t-IsPosted = abap_true THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
        %delete = COND #( WHEN t-IsPosted = abap_true THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled ) ) ).
  ENDMETHOD.
ENDCLASS.

CLASS lhc_ordermaterial DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR OrderMaterial RESULT result.
ENDCLASS.

CLASS lhc_ordermaterial IMPLEMENTATION.
  METHOD get_instance_features.
    READ ENTITIES OF zcprx_r_order IN LOCAL MODE
      ENTITY OrderMaterial FIELDS ( IsPosted ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_material) FAILED failed.

    result = VALUE #( FOR m IN lt_material
      ( %tky    = m-%tky
        %update = COND #( WHEN m-IsPosted = abap_true THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
        %delete = COND #( WHEN m-IsPosted = abap_true THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled ) ) ).
  ENDMETHOD.
ENDCLASS.

" Saver: schreibt Queue-Einträge und startet bgPF (nach Commit)
CLASS lsc_order DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS save_modified    REDEFINITION.
    METHODS cleanup_finalize REDEFINITION.
ENDCLASS.

CLASS lsc_order IMPLEMENTATION.

  METHOD save_modified.
    DATA lt_entries TYPE zcprx_cl_queue=>tt_entry.

    LOOP AT create-order INTO DATA(ls_create) WHERE SyncRequired = abap_true.
      APPEND VALUE #( object_type = zcprx_if_constants=>object_type-order
                      operation   = zcprx_if_constants=>operation-upsert
                      object_key  = |{ ls_create-OrderUUID }| ) TO lt_entries.
    ENDLOOP.

    LOOP AT update-order INTO DATA(ls_update) WHERE %control-SyncRequired = if_abap_behv=>mk-on
                                                AND SyncRequired = abap_true.
      APPEND VALUE #( object_type = zcprx_if_constants=>object_type-order
                      operation   = zcprx_if_constants=>operation-upsert
                      object_key  = |{ ls_update-OrderUUID }| ) TO lt_entries.
    ENDLOOP.

    APPEND LINES OF lcl_buffer=>mt_entries TO lt_entries.
    CLEAR lcl_buffer=>mt_entries.

    IF lt_entries IS NOT INITIAL.
      " schreibt ZCPRXQUE und registriert bgPF-Prozess (läuft nach COMMIT)
      zcprx_cl_queue=>enqueue( lt_entries ).
    ENDIF.
  ENDMETHOD.

  METHOD cleanup_finalize.
    CLEAR lcl_buffer=>mt_entries.
  ENDMETHOD.

ENDCLASS.
