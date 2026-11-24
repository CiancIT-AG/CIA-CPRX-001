CLASS zcprx_cx_error DEFINITION PUBLIC INHERITING FROM cx_static_check FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    "! X = dauerhafter Fehler (z. B. HTTP 4xx, Daten fehlen) -> kein Retry
    DATA mv_permanent TYPE abap_bool READ-ONLY.

    METHODS constructor
      IMPORTING iv_text      TYPE string OPTIONAL
                iv_permanent TYPE abap_bool DEFAULT abap_false
                previous     TYPE REF TO cx_root OPTIONAL.
    METHODS get_text REDEFINITION.
    CLASS-METHODS raise
      IMPORTING iv_text      TYPE csequence
                iv_permanent TYPE abap_bool DEFAULT abap_false
                ix_previous  TYPE REF TO cx_root OPTIONAL
      RAISING   zcprx_cx_error.

    "! HTTP-Status -> dauerhafter Fehler? 4xx außer 408/429 (Daten/Konfiguration)
    "! wird nicht wiederholt; 5xx, 408, 429, Verbindungsfehler = vorübergehend.
    CLASS-METHODS is_permanent_http
      IMPORTING iv_code          TYPE i
      RETURNING VALUE(rv_result) TYPE abap_bool.
  PRIVATE SECTION.
    DATA mv_text TYPE string.
ENDCLASS.

CLASS zcprx_cx_error IMPLEMENTATION.
  METHOD constructor.
    super->constructor( previous = previous ).
    mv_text      = iv_text.
    mv_permanent = iv_permanent.
  ENDMETHOD.

  METHOD get_text.
    result = COND #( WHEN mv_text IS NOT INITIAL AND previous IS BOUND
                       THEN |{ mv_text }: { previous->get_text( ) }|
                     WHEN mv_text IS NOT INITIAL THEN mv_text
                     WHEN previous IS BOUND      THEN previous->get_text( )
                     ELSE super->get_text( ) ).
  ENDMETHOD.

  METHOD is_permanent_http.
    rv_result = xsdbool( iv_code >= 400 AND iv_code < 500 AND iv_code <> 408 AND iv_code <> 429 ).
  ENDMETHOD.

  METHOD raise.
    RAISE EXCEPTION NEW zcprx_cx_error( iv_text      = CONV #( iv_text )
                                            iv_permanent = iv_permanent
                                            previous     = ix_previous ).
  ENDMETHOD.
ENDCLASS.
