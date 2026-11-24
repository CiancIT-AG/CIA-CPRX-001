CLASS zcprx_cl_bgpf_queue DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_bgmc_op_single_tx_uncontr.
    METHODS constructor IMPORTING it_ids TYPE zcprx_cl_queue=>tt_uuid.
  PRIVATE SECTION.
    DATA mt_ids TYPE zcprx_cl_queue=>tt_uuid.
ENDCLASS.

CLASS zcprx_cl_bgpf_queue IMPLEMENTATION.
  METHOD constructor.
    mt_ids = it_ids.
  ENDMETHOD.

  METHOD if_bgmc_op_single_tx_uncontr~execute.
    NEW zcprx_cl_queue( )->process( it_ids = mt_ids ).
  ENDMETHOD.
ENDCLASS.
