CLASS zcprx_cl_auth DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CONSTANTS c_object TYPE c LENGTH 10 VALUE 'ZCPRXA'.

    CLASS-METHODS is_allowed
      IMPORTING iv_activity      TYPE c
      RETURNING VALUE(rv_result) TYPE abap_bool.

ENDCLASS.

CLASS zcprx_cl_auth IMPLEMENTATION.
  METHOD is_allowed.
    AUTHORITY-CHECK OBJECT c_object ID 'ACTVT' FIELD iv_activity.
    rv_result = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.
ENDCLASS.
