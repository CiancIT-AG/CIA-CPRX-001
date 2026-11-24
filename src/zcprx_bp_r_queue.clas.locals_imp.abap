" ---- Local Types ----------------------------------------------------
CLASS lcl_buffer DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-DATA mt_ids TYPE zcprx_cl_queue=>tt_uuid.
ENDCLASS.

CLASS lhc_queue DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Queue RESULT result.
    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Queue RESULT result.
    METHODS retry FOR MODIFY
      IMPORTING keys FOR ACTION Queue~retry RESULT result.
ENDCLASS.

CLASS lhc_queue IMPLEMENTATION.

  METHOD get_global_authorizations.
    DATA(act) = zcprx_if_constants=>activity.
    DATA(lv_create)  = COND #( WHEN zcprx_cl_auth=>is_allowed( act-create )  = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    DATA(lv_change)  = COND #( WHEN zcprx_cl_auth=>is_allowed( act-change )  = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    DATA(lv_delete)  = COND #( WHEN zcprx_cl_auth=>is_allowed( act-delete )  = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    DATA(lv_execute) = COND #( WHEN zcprx_cl_auth=>is_allowed( act-execute ) = abap_true THEN if_abap_behv=>auth-allowed ELSE if_abap_behv=>auth-unauthorized ).
    result = VALUE #( %delete                = lv_delete
                      %action-retry          = lv_execute ).
  ENDMETHOD.

  METHOD get_instance_features.
    READ ENTITIES OF zcprx_r_queue IN LOCAL MODE
      ENTITY Queue FIELDS ( Status ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_queue) FAILED failed.

    result = VALUE #( FOR q IN lt_queue
      ( %tky          = q-%tky
        %action-retry = COND #( WHEN q-Status = zcprx_if_constants=>queue_status-error
                                THEN if_abap_behv=>fc-o-enabled
                                ELSE if_abap_behv=>fc-o-disabled ) ) ).
  ENDMETHOD.

  METHOD retry.
    MODIFY ENTITIES OF zcprx_r_queue IN LOCAL MODE
      ENTITY Queue UPDATE FIELDS ( Status RetryCount MessageText NextRetryAt )
      WITH VALUE #( FOR k IN keys ( %tky        = k-%tky
                                    Status      = zcprx_if_constants=>queue_status-new
                                    RetryCount  = 0
                                    MessageText = ''
                                    NextRetryAt = 0 ) ).

    LOOP AT keys INTO DATA(ls_key).
      APPEND ls_key-QueueUUID TO lcl_buffer=>mt_ids.
    ENDLOOP.

    READ ENTITIES OF zcprx_r_queue IN LOCAL MODE
      ENTITY Queue ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_result).
    result = VALUE #( FOR r IN lt_result ( %tky = r-%tky %param = r ) ).
  ENDMETHOD.

ENDCLASS.

CLASS lsc_queue DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS save_modified    REDEFINITION.
    METHODS cleanup_finalize REDEFINITION.
ENDCLASS.

CLASS lsc_queue IMPLEMENTATION.
  METHOD save_modified.
    IF lcl_buffer=>mt_ids IS NOT INITIAL.
      zcprx_cl_queue=>start_background( lcl_buffer=>mt_ids ).
      CLEAR lcl_buffer=>mt_ids.
    ENDIF.
  ENDMETHOD.
  METHOD cleanup_finalize.
    CLEAR lcl_buffer=>mt_ids.
  ENDMETHOD.
ENDCLASS.
