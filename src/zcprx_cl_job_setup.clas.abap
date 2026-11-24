CLASS zcprx_cl_job_setup DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcprx_cl_job_base.
  PROTECTED SECTION.
    METHODS get_subobject     REDEFINITION.
    METHODS run               REDEFINITION.
    METHODS define_parameters REDEFINITION.
    METHODS default_values    REDEFINITION.
ENDCLASS.

CLASS zcprx_cl_job_setup IMPLEMENTATION.
  METHOD get_subobject.
    rv_subobject = zcprx_if_constants=>log-sub_setup.
  ENDMETHOD.

  METHOD define_parameters.
    rt_definition = VALUE #(
      ( selname = 'P_MODE'  kind = if_apj_dt_exec_object=>parameter datatype = 'C' length = 1
        param_text = 'I = Installieren, U = Deinstallieren' changeable_ind = abap_true mandatory_ind = abap_true )
      ( selname = 'P_MD'    kind = if_apj_dt_exec_object=>parameter datatype = 'C' length = 1
        param_text = 'Artikelgruppen/Equipmenttypen senden (X)' changeable_ind = abap_true )
      ( selname = 'P_JOBS'  kind = if_apj_dt_exec_object=>parameter datatype = 'C' length = 1
        param_text = 'Periodische Jobs einplanen (X)' changeable_ind = abap_true )
      ( selname = 'P_FORCE' kind = if_apj_dt_exec_object=>parameter datatype = 'C' length = 1
        param_text = 'Jobs neu einplanen / trotz Fehler (X)' changeable_ind = abap_true ) ).
  ENDMETHOD.

  METHOD default_values.
    rt_values = VALUE #(
      ( selname = 'P_MODE' kind = if_apj_dt_exec_object=>parameter sign = 'I' option = 'EQ' low = 'I' )
      ( selname = 'P_MD'   kind = if_apj_dt_exec_object=>parameter sign = 'I' option = 'EQ' low = 'X' )
      ( selname = 'P_JOBS' kind = if_apj_dt_exec_object=>parameter sign = 'I' option = 'EQ' low = 'X' ) ).
  ENDMETHOD.

  METHOD run.
    DATA(lo_installer) = NEW zcprx_cl_installer( mo_log ).

    IF to_upper( param( it_parameters = it_parameters iv_name = 'P_MODE' ) ) = 'U'.
      lo_installer->uninstall( ).
      RETURN.
    ENDIF.

    lo_installer->install(
      iv_masterdata = xsdbool( param( it_parameters = it_parameters iv_name = 'P_MD' )    = 'X' )
      iv_schedule   = xsdbool( param( it_parameters = it_parameters iv_name = 'P_JOBS' )  = 'X' )
      iv_force      = xsdbool( param( it_parameters = it_parameters iv_name = 'P_FORCE' ) = 'X' ) ).
  ENDMETHOD.
ENDCLASS.
