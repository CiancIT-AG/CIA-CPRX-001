CLASS zcprx_cl_installer DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    " Periodizität laut CL_APJ_RT_API=>TY_SCHEDULING_INFO (Werte verifizieren)
    CONSTANTS:
      BEGIN OF c_granularity,
        minutes TYPE c LENGTH 2 VALUE 'MI',
        hours   TYPE c LENGTH 2 VALUE 'H',
        days    TYPE c LENGTH 2 VALUE 'D',
      END OF c_granularity.

    TYPES:
      BEGIN OF ty_job,
        name        TYPE c LENGTH 10,
        template    TYPE c LENGTH 30,
        text        TYPE c LENGTH 120,
        granularity TYPE c LENGTH 2,
        value       TYPE i,
        start_time  TYPE t,            " initial = sofort starten
        parameters  TYPE cl_apj_rt_api=>tt_job_parameter_value,
      END OF ty_job,
      tt_job TYPE STANDARD TABLE OF ty_job WITH EMPTY KEY.

    METHODS constructor
      IMPORTING io_log TYPE REF TO zcprx_cl_log.

    METHODS install
      IMPORTING iv_masterdata TYPE abap_bool DEFAULT abap_true
                iv_schedule   TYPE abap_bool DEFAULT abap_true
                iv_force      TYPE abap_bool DEFAULT abap_false.

    METHODS uninstall.

    METHODS get_job_catalog
      RETURNING VALUE(rt_jobs) TYPE tt_job.

  PRIVATE SECTION.
    DATA mo_log TYPE REF TO zcprx_cl_log.

    METHODS step_config.
    METHODS step_connectivity
      RETURNING VALUE(rv_ok) TYPE abap_bool.
    METHODS step_customer_settings.
    METHODS step_masterdata.
    METHODS step_schedule
      IMPORTING iv_force TYPE abap_bool.
    METHODS step_alerting.
    METHODS step_authorization.
    METHODS cancel_job
      IMPORTING iv_param TYPE csequence.
    METHODS next_start
      IMPORTING iv_time      TYPE t
      RETURNING VALUE(rv_ts) TYPE timestamp.
    METHODS job_param
      IMPORTING iv_name         TYPE csequence
      RETURNING VALUE(rv_param) TYPE string.
    METHODS timezone
      RETURNING VALUE(rv_timezone) TYPE timezone.
ENDCLASS.

CLASS zcprx_cl_installer IMPLEMENTATION.

  METHOD constructor.
    mo_log = io_log.
  ENDMETHOD.

  METHOD install.
    mo_log->info( 'Installation Praxedo-Adapter ZCPRX gestartet' ).

    step_config( ).
    step_authorization( ).
    DATA(lv_connected) = step_connectivity( ).
    step_customer_settings( ).

    IF iv_masterdata = abap_true.
      IF lv_connected = abap_true.
        step_masterdata( ).
      ELSE.
        mo_log->warning( 'Stammdaten übersprungen: Verbindung fehlt. Job SETUP nach Einrichtung erneut starten.' ).
      ENDIF.
    ENDIF.

    IF iv_schedule = abap_true.
      IF lv_connected = abap_true OR iv_force = abap_true.
        step_schedule( iv_force ).
      ELSE.
        mo_log->warning( 'Jobs nicht eingeplant: Verbindung fehlt (P_FORCE = X plant trotzdem ein).' ).
      ENDIF.
    ENDIF.

    step_alerting( ).

    mo_log->info( 'Manuell bleibt: Business Role aus ZCPRX_BC_ADMIN + ZCPRX_BC_JOBS anlegen und Benutzern zuweisen' ).
    mo_log->info( 'Optional (Echtzeit SAP->Praxedo): Event Mesh + Arrangement ZCPRX_CS_EVENT_IN, sonst Delta-Job' ).
  ENDMETHOD.

  METHOD uninstall.
    LOOP AT get_job_catalog( ) INTO DATA(ls_job).
      cancel_job( job_param( ls_job-name ) ).
      mo_log->info( |Job { ls_job-name } storniert| ).
    ENDLOOP.
    COMMIT WORK.
    mo_log->info( 'Daten in ZCPRX*-Tabellen bleiben erhalten. Add-on-Deinstallation über Landscape Portal.' ).
  ENDMETHOD.

  METHOD get_job_catalog.
    rt_jobs = VALUE #(
      ( name        = 'OUTBOUND'
        template    = 'ZCPRX_JT_OUTBOUND'
        text        = 'Praxedo: Delta Serviceaufträge + Queue-Retry'
        granularity = c_granularity-minutes
        value       = 5
        parameters  = VALUE #( ( name = 'P_DELTA' t_value = VALUE #( ( sign = 'I' option = 'EQ' low = 'X' ) ) ) ) )
      ( name        = 'FETCH'
        template    = 'ZCPRX_JT_FETCH'
        text        = 'Praxedo: Rückmeldungen holen'
        granularity = c_granularity-minutes
        value       = 15 )
      ( name        = 'POST'
        template    = 'ZCPRX_JT_POST'
        text        = 'Praxedo: Einsätze verbuchen'
        granularity = c_granularity-minutes
        value       = 15 )
      ( name        = 'PRODUCTS'
        template    = 'ZCPRX_JT_PRODUCTS'
        text        = 'Praxedo: Artikel übertragen'
        granularity = c_granularity-days
        value       = 1
        start_time  = '020000' )
      ( name        = 'REPORT'
        template    = 'ZCPRX_JT_REPORT'
        text        = 'Praxedo: Berichte an Serviceaufträge anhängen'
        granularity = c_granularity-days
        value       = 1
        start_time  = '060000'
        parameters  = VALUE #( ( name = 'P_CHECK' t_value = VALUE #( ( sign = 'I' option = 'EQ' low = 'X' ) ) )
                               ( name = 'P_RETRY' t_value = VALUE #( ( sign = 'I' option = 'EQ' low = 'X' ) ) ) ) ) ).
  ENDMETHOD.

  METHOD step_config.
    DATA(lv_count)    = zcprx_cl_config=>init_defaults( ).
    DATA(lv_obsolete) = zcprx_cl_config=>delete_obsolete( ).
    COMMIT WORK.
    mo_log->success( |Konfiguration: { lv_count } Standardwert(e) angelegt, vorhandene Werte unverändert| ).
    IF lv_obsolete > 0.
      mo_log->info( |Konfiguration: { lv_obsolete } veraltete Parameter (PATH_*, REPORT_ID) gelöscht| ).
    ENDIF.
  ENDMETHOD.

  METHOD step_connectivity.
    rv_ok = abap_true.

    TRY.
        NEW zcprx_cl_praxedo_api( )->zcprx_if_praxedo_api~ping( ).
        mo_log->success( 'Verbindung Praxedo: OK' ).
      CATCH zcprx_cx_error INTO DATA(lx_praxedo).
        rv_ok = abap_false.
        mo_log->error( |Verbindung Praxedo: { lx_praxedo->get_text( ) }| ).
        mo_log->error( 'MANUELL: Comm. System PRAXEDO + Arrangement ZCPRX_CS_PRAXEDO (SOAP: Basic, REST v1: keine Auth.)' ).
    ENDTRY.

    TRY.
        NEW zcprx_cl_srvord_api( )->zcprx_if_srvord_api~ping( ).
        mo_log->success( 'Verbindung SAP-Loopback (Service Order/Confirmation): OK' ).
      CATCH zcprx_cx_error INTO DATA(lx_loopback).
        rv_ok = abap_false.
        mo_log->error( |SAP-Loopback: { lx_loopback->get_text( ) }| ).
        mo_log->error( 'MANUELL: Inbound-Arrangements der SAP-Service-APIs + Arrangement ZCPRX_CS_S4_LOOPBACK anlegen' ).
    ENDTRY.
  ENDMETHOD.

  METHOD step_customer_settings.
    " Parameter, deren leerer Standard fachlich bewusst sein sollte
    DATA(lt_check) = VALUE zcprx_cl_config=>tt_default(
      ( param = zcprx_cl_config=>c_param-prx_event_type      value = `Praxedo-Einsatztyp (Pflicht für Einsätze)` )
      ( param = zcprx_cl_config=>c_param-default_item_cat    value = `Praxedo-Artikelkategorie für Artikel ohne Gruppe` )
      ( param = zcprx_cl_config=>c_param-activity_products   value = `Aktivitätstyp -> Leistungsartikel (leer = DEFAULT_SRV_PRODUCT)` )
      ( param = zcprx_cl_config=>c_param-conf_itemcat_time   value = `Positionstyp Zeiten (leer = SAP-Ermittlung)` )
      ( param = zcprx_cl_config=>c_param-conf_itemcat_mat    value = `Positionstyp Material (leer = SAP-Ermittlung)` )
      ( param = zcprx_cl_config=>c_param-default_srv_product value = `Leistungsartikel ohne Praxedo-Angabe` )
      ( param = zcprx_cl_config=>c_param-product_types       value = `Artikelarten für Tagesjob (leer = alle)` )
      ( param = zcprx_cl_config=>c_param-relevant_so_types   value = `Serviceauftragsarten (leer = alle)` )
      ( param = zcprx_cl_config=>c_param-alert_recipients    value = `Empfänger Fehler-Mails (leer = kein Alerting)` )
      ( param = zcprx_cl_config=>c_param-alert_sender        value = `Absender aus freigegebener Mail-Domäne` ) ).

    LOOP AT lt_check INTO DATA(ls_check).
      IF zcprx_cl_config=>get( ls_check-param ) IS INITIAL.
        mo_log->warning( |PRÜFEN: { ls_check-param } – { ls_check-value } (App Custom Business Configurations)| ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD step_masterdata.
    MODIFY ENTITIES OF zcprx_r_productgroup
      ENTITY ProductGroup EXECUTE loadFromSap FROM VALUE #( ( %cid = 'LOAD_PG' ) )
      FAILED DATA(ls_pg_failed) ##NEEDED.
    MODIFY ENTITIES OF zcprx_r_equipmenttype
      ENTITY EquipmentType EXECUTE loadFromSap FROM VALUE #( ( %cid = 'LOAD_EQT' ) )
      FAILED DATA(ls_eqt_failed) ##NEEDED.
    COMMIT ENTITIES.

    DATA(lo_masterdata) = NEW zcprx_cl_masterdata( ).
    TRY.
        mo_log->success( |{ lo_masterdata->send_product_groups( ) } Artikelgruppe(n) an Praxedo übertragen| ).
      CATCH zcprx_cx_error INTO DATA(lx_pg).
        mo_log->error( |Artikelgruppen: { lx_pg->get_text( ) }| ).
    ENDTRY.
    TRY.
        mo_log->success( |{ lo_masterdata->send_equipment_types( ) } Equipmenttyp(en) an Praxedo übertragen| ).
      CATCH zcprx_cx_error INTO DATA(lx_eqt).
        mo_log->error( |Equipmenttypen: { lx_eqt->get_text( ) }| ).
    ENDTRY.
    mo_log->info( 'Artikel: erste Vollübertragung im ersten Lauf des Jobs PRODUCTS' ).
  ENDMETHOD.

  METHOD step_schedule.
    DATA(lv_timezone) = timezone( ).

    LOOP AT get_job_catalog( ) INTO DATA(ls_job).
      DATA(lv_param) = job_param( ls_job-name ).

      IF zcprx_cl_config=>get( iv_param = lv_param iv_default = `` ) IS NOT INITIAL.
        IF iv_force = abap_false.
          mo_log->info( |Job { ls_job-name } bereits eingeplant (P_FORCE = X plant neu ein)| ).
          CONTINUE.
        ENDIF.
        cancel_job( lv_param ).
      ENDIF.

      TRY.
          cl_apj_rt_api=>schedule_job(
            EXPORTING
              iv_job_template_name   = CONV #( ls_job-template )
              iv_job_text            = CONV #( ls_job-text )
              is_start_info          = VALUE #( start_immediately = xsdbool( ls_job-start_time IS INITIAL )
                                                timestamp         = COND #( WHEN ls_job-start_time IS NOT INITIAL
                                                                            THEN next_start( ls_job-start_time ) ) )
              is_scheduling_info     = VALUE #( periodic_granularity = ls_job-granularity
                                                periodic_value       = ls_job-value
                                                timezone             = lv_timezone )
              it_job_parameter_value = ls_job-parameters
            IMPORTING
              ev_jobname             = DATA(lv_jobname)
              ev_jobcount            = DATA(lv_jobcount) ).

          zcprx_cl_config=>set( iv_param = lv_param iv_value = |{ lv_jobname };{ lv_jobcount }| ).
          COMMIT WORK.
          mo_log->success( |Job { ls_job-name } eingeplant (alle { ls_job-value } { ls_job-granularity })| ).

        CATCH cx_apj_rt INTO DATA(lx_apj).
          mo_log->error( |Job { ls_job-name } konnte nicht eingeplant werden: { lx_apj->get_text( ) }| ).
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

  METHOD step_authorization.
    " Die eingeplanten Jobs laufen unter diesem Benutzer -> er braucht
    " ZCPRXA mit 01, 02, 16 (IAM-App ZCPRX_JOBS)
    DATA(act) = zcprx_if_constants=>activity.
    DATA(lt_missing) = VALUE zcprx_cl_log=>tt_text(
      ( COND #( WHEN zcprx_cl_auth=>is_allowed( act-create )  = abap_false THEN `01` ) )
      ( COND #( WHEN zcprx_cl_auth=>is_allowed( act-change )  = abap_false THEN `02` ) )
      ( COND #( WHEN zcprx_cl_auth=>is_allowed( act-execute ) = abap_false THEN `16` ) ) ).
    DELETE lt_missing WHERE table_line IS INITIAL.
    IF lt_missing IS INITIAL.
      mo_log->success( 'Berechtigung ZCPRXA für den Jobbenutzer: OK' ).
    ELSE.
      mo_log->error( |MANUELL: Jobbenutzer fehlt ZCPRXA ACTVT { concat_lines_of( table = lt_missing sep = `, ` ) } | &&
                     |(Business Role mit Katalog ZCPRX_BC_JOBS zuweisen)| ).
    ENDIF.
  ENDMETHOD.

  METHOD step_alerting.
    " Testmail = Nachweis, dass Mailversand und Empfänger funktionieren
    DATA(lo_alert) = NEW zcprx_cl_alert( ).
    IF lo_alert->is_configured( ) = abap_false.
      mo_log->warning( 'PRÜFEN: Mail-Alerting nicht konfiguriert (ALERT_RECIPIENTS, ALERT_SENDER)' ).
      RETURN.
    ENDIF.

    DATA(lv_errors) = lines( mo_log->get_errors( ) ).
    DATA(lt_lines) = VALUE zcprx_cl_log=>tt_text(
      ( `Setup-Job ZCPRX_JT_SETUP wurde ausgeführt.` )
      ( COND #( WHEN lv_errors = 0 THEN `Ergebnis: ohne Fehler. Das Mail-Alerting ist aktiv.`
                ELSE |Ergebnis: { lv_errors } Fehler – Details folgen in einer separaten Fehler-Mail und im Joblog.| ) ) ).

    IF lo_alert->send_info( iv_subject = 'Installation / Test Mail-Alerting' it_lines = lt_lines ) = abap_true.
      mo_log->success( 'Testmail an ALERT_RECIPIENTS versendet' ).
    ELSE.
      mo_log->error( 'Testmail nicht versendet: E-Mail-Einrichtung des Tenants prüfen (DKIM, erlaubte Domänen)' ).
    ENDIF.
  ENDMETHOD.

  METHOD cancel_job.
    DATA(lv_value) = zcprx_cl_config=>get( iv_param = iv_param iv_default = `` ).
    CHECK lv_value IS NOT INITIAL.
    SPLIT lv_value AT ';' INTO DATA(lv_jobname) DATA(lv_jobcount).
    TRY.
        cl_apj_rt_api=>cancel_job( iv_jobname  = CONV #( lv_jobname )
                                   iv_jobcount = CONV #( lv_jobcount ) ).
      CATCH cx_apj_rt ##NO_HANDLER.
        " Job existiert nicht mehr / bereits beendet
    ENDTRY.
    zcprx_cl_config=>set( iv_param = iv_param iv_value = `` ).
  ENDMETHOD.

  METHOD next_start.
    " morgen zur angegebenen Uhrzeit (Zeitzone des Benutzers)
    DATA(lv_date)     = CONV d( cl_abap_context_info=>get_system_date( ) + 1 ).
    DATA(lv_timezone) = timezone( ).
    CONVERT DATE lv_date TIME iv_time INTO TIME STAMP rv_ts TIME ZONE lv_timezone.
  ENDMETHOD.

  METHOD timezone.
    TRY.
        rv_timezone = cl_abap_context_info=>get_user_time_zone( ).
      CATCH cx_abap_context_info_error.
        rv_timezone = 'UTC'.
    ENDTRY.
  ENDMETHOD.

  METHOD job_param.
    rv_param = |{ zcprx_cl_config=>c_param-job_prefix }{ iv_name }|.
  ENDMETHOD.

ENDCLASS.

