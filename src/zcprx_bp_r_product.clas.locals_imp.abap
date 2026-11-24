" ---- Local Types ----------------------------------------------------
CLASS lcl_buffer DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-DATA mt_entries TYPE zcprx_cl_queue=>tt_entry.
ENDCLASS.

CLASS lhc_product DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Product RESULT result.
    METHODS sendtopraxedo FOR MODIFY
      IMPORTING keys FOR ACTION Product~sendToPraxedo RESULT result.
    METHODS setsyncresult FOR MODIFY
      IMPORTING keys FOR ACTION Product~setSyncResult RESULT result.
ENDCLASS.

CLASS lhc_product IMPLEMENTATION.

  METHOD get_global_authorizations.
    DATA(act) = zcprx_if_constants=>activity.
    DATA(lv_create)  = COND #( WHEN zcprx_cl_auth=>is_allowed( act-create )  = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    DATA(lv_change)  = COND #( WHEN zcprx_cl_auth=>is_allowed( act-change )  = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    DATA(lv_delete)  = COND #( WHEN zcprx_cl_auth=>is_allowed( act-delete )  = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    DATA(lv_execute) = COND #( WHEN zcprx_cl_auth=>is_allowed( act-execute ) = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    result = VALUE #( %create                = lv_create
                      %update                = lv_change
                      %delete                = lv_delete
                      %action-sendToPraxedo  = lv_execute
                      %action-setSyncResult  = lv_execute ).
  ENDMETHOD.

  METHOD sendtopraxedo.
    MODIFY ENTITIES OF zcprx_r_product IN LOCAL MODE
      ENTITY Product UPDATE FIELDS ( Status MessageText )
      WITH VALUE #( FOR k IN keys ( %tky        = k-%tky
                                    Status      = zcprx_if_constants=>sync_status-in_process
                                    MessageText = '' ) ).

    LOOP AT keys INTO DATA(ls_key).
      APPEND VALUE #( object_type = zcprx_if_constants=>object_type-product
                      operation   = zcprx_if_constants=>operation-upsert
                      object_key  = ls_key-Product ) TO lcl_buffer=>mt_entries.
    ENDLOOP.

    READ ENTITIES OF zcprx_r_product IN LOCAL MODE
      ENTITY Product ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_result).
    result = VALUE #( FOR r IN lt_result ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

  METHOD setsyncresult.
    DATA lt_update TYPE TABLE FOR UPDATE zcprx_r_product\\Product.
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

    MODIFY ENTITIES OF zcprx_r_product IN LOCAL MODE
      ENTITY Product UPDATE FROM lt_update.

    READ ENTITIES OF zcprx_r_product IN LOCAL MODE
      ENTITY Product ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_result).
    result = VALUE #( FOR r IN lt_result ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

ENDCLASS.

CLASS lsc_product DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS save_modified    REDEFINITION.
    METHODS cleanup_finalize REDEFINITION.
ENDCLASS.

CLASS lsc_product IMPLEMENTATION.
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
