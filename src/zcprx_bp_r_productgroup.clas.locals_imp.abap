" ---- Local Types ----------------------------------------------------
CLASS lcl_buffer DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-DATA mt_entries TYPE zcprx_cl_queue=>tt_entry.
ENDCLASS.

CLASS lhc_productgroup DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR ProductGroup RESULT result.
    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR ProductGroup RESULT result.
    METHODS loadfromsap FOR MODIFY
      IMPORTING keys FOR ACTION ProductGroup~loadFromSap.
    METHODS sendtopraxedo FOR MODIFY
      IMPORTING keys FOR ACTION ProductGroup~sendToPraxedo RESULT result.
    METHODS setActive FOR MODIFY
      IMPORTING keys FOR ACTION ProductGroup~setActive RESULT result.
    METHODS setInactive FOR MODIFY
      IMPORTING keys FOR ACTION ProductGroup~setInactive RESULT result.
    METHODS setsyncresult FOR MODIFY
      IMPORTING keys FOR ACTION ProductGroup~setSyncResult RESULT result.
ENDCLASS.

CLASS lhc_productgroup IMPLEMENTATION.

  METHOD get_global_authorizations.
    DATA(act) = zcprx_if_constants=>activity.
    DATA(lv_create)  = COND #( WHEN zcprx_cl_auth=>is_allowed( act-create )  = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    DATA(lv_change)  = COND #( WHEN zcprx_cl_auth=>is_allowed( act-change )  = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    DATA(lv_delete)  = COND #( WHEN zcprx_cl_auth=>is_allowed( act-delete )  = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    DATA(lv_execute) = COND #( WHEN zcprx_cl_auth=>is_allowed( act-execute ) = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    result = VALUE #( %create                = lv_create
                      %update                = lv_change
                      %delete                = lv_delete
                      %action-loadFromSap    = lv_execute
                      %action-sendToPraxedo  = lv_execute
                      %action-setActive       = lv_execute
                      %action-setInactive     = lv_execute
                      %action-setSyncResult  = lv_execute ).
  ENDMETHOD.

  METHOD get_instance_features.
    " Actions nur auf aktiven Instanzen (nicht im Draft)
    READ ENTITIES OF zcprx_r_productgroup IN LOCAL MODE
      ENTITY ProductGroup FIELDS ( IsActive ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data) FAILED failed.

    result = VALUE #( FOR d IN lt_data
      LET active_instance = xsdbool( d-%is_draft = if_abap_behv=>mk-off ) IN
      ( %tky                  = d-%tky
        %action-sendToPraxedo = COND #( WHEN active_instance = abap_true AND d-IsActive = abap_true
                                        THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
        %action-setActive      = COND #( WHEN active_instance = abap_true AND d-IsActive = abap_false
                                        THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
        %action-setInactive    = COND #( WHEN active_instance = abap_true AND d-IsActive = abap_true
                                        THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled ) ) ).
  ENDMETHOD.

  METHOD loadfromsap.
    " Übernimmt alle Produktgruppen aus I_ProductGroup_2, die noch fehlen
    DATA lt_create TYPE TABLE FOR CREATE zcprx_r_productgroup\\ProductGroup.
    DATA lv_index  TYPE i.

    DATA(lt_sap) = NEW zcprx_cl_masterdata( )->get_sap_product_groups( ).
    SELECT product_group FROM zcprxagr INTO TABLE @DATA(lt_existing).

    LOOP AT lt_sap INTO DATA(ls_sap).
      CHECK NOT line_exists( lt_existing[ product_group = ls_sap-external_id ] ).
      lv_index += 1.
      APPEND VALUE #( %cid         = |PG{ lv_index }|
                      ProductGroup = ls_sap-external_id
                      IsActive     = abap_true
                      Status       = zcprx_if_constants=>sync_status-new ) TO lt_create.
    ENDLOOP.

    IF lt_create IS NOT INITIAL.
      MODIFY ENTITIES OF zcprx_r_productgroup IN LOCAL MODE
        ENTITY ProductGroup CREATE FIELDS ( ProductGroup IsActive Status ) WITH lt_create
        FAILED DATA(ls_failed) ##NEEDED.
    ENDIF.

    APPEND new_message_with_text( severity = if_abap_behv_message=>severity-success
                                  text     = |{ lines( lt_create ) } Artikelgruppe(n) aus SAP übernommen| ) TO reported-%other.
  ENDMETHOD.

  METHOD sendtopraxedo.
    MODIFY ENTITIES OF zcprx_r_productgroup IN LOCAL MODE
      ENTITY ProductGroup UPDATE FIELDS ( Status MessageText )
      WITH VALUE #( FOR k IN keys ( %tky        = k-%tky
                                    Status      = zcprx_if_constants=>sync_status-in_process
                                    MessageText = '' ) ).

    LOOP AT keys INTO DATA(ls_key).
      APPEND VALUE #( object_type = zcprx_if_constants=>object_type-product_group
                      operation   = zcprx_if_constants=>operation-upsert
                      object_key  = ls_key-ProductGroup ) TO lcl_buffer=>mt_entries.
    ENDLOOP.

    READ ENTITIES OF zcprx_r_productgroup IN LOCAL MODE
      ENTITY ProductGroup ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_result).
    result = VALUE #( FOR r IN lt_result ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

  METHOD setActive.
    MODIFY ENTITIES OF zcprx_r_productgroup IN LOCAL MODE
      ENTITY ProductGroup UPDATE FIELDS ( IsActive )
      WITH VALUE #( FOR k IN keys ( %tky = k-%tky IsActive = abap_true ) ).
    READ ENTITIES OF zcprx_r_productgroup IN LOCAL MODE
      ENTITY ProductGroup ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_result).
    result = VALUE #( FOR r IN lt_result ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

  METHOD setInactive.
    MODIFY ENTITIES OF zcprx_r_productgroup IN LOCAL MODE
      ENTITY ProductGroup UPDATE FIELDS ( IsActive )
      WITH VALUE #( FOR k IN keys ( %tky = k-%tky IsActive = abap_false ) ).
    READ ENTITIES OF zcprx_r_productgroup IN LOCAL MODE
      ENTITY ProductGroup ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_result).
    result = VALUE #( FOR r IN lt_result ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

  METHOD setsyncresult.
    DATA lt_update TYPE TABLE FOR UPDATE zcprx_r_productgroup\\ProductGroup.
    DATA lv_now    TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    LOOP AT keys INTO DATA(ls_key).
      APPEND VALUE #( %tky                 = ls_key-%tky
                      Status               = ls_key-%param-Status
                      MessageText          = ls_key-%param-MessageText
                      LastSentAt           = lv_now
                      %control-Status      = if_abap_behv=>mk-on
                      %control-MessageText = if_abap_behv=>mk-on
                      %control-LastSentAt  = if_abap_behv=>mk-on ) TO lt_update ASSIGNING FIELD-SYMBOL(<ls_update>).
      IF ls_key-%param-PraxedoId IS NOT INITIAL.
        <ls_update>-PraxedoId          = ls_key-%param-PraxedoId.
        <ls_update>-%control-PraxedoId = if_abap_behv=>mk-on.
      ENDIF.
    ENDLOOP.

    MODIFY ENTITIES OF zcprx_r_productgroup IN LOCAL MODE
      ENTITY ProductGroup UPDATE FROM lt_update.

    READ ENTITIES OF zcprx_r_productgroup IN LOCAL MODE
      ENTITY ProductGroup ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_result).
    result = VALUE #( FOR r IN lt_result ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

ENDCLASS.

CLASS lsc_productgroup DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS save_modified    REDEFINITION.
    METHODS cleanup_finalize REDEFINITION.
ENDCLASS.

CLASS lsc_productgroup IMPLEMENTATION.
  METHOD save_modified.
    IF lcl_buffer=>mt_entries IS NOT INITIAL.
      zcprx_cl_queue=>enqueue( lcl_buffer=>mt_entries ).
      CLEAR lcl_buffer=>mt_entries.
    ENDIF.
  ENDMETHOD.
  METHOD cleanup_finalize.
    CLEAR lcl_buffer=>mt_entries.
  ENDMETHOD.
ENDCLASS.
