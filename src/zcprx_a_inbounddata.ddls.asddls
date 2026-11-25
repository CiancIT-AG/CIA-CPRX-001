@EndUserText.label: 'Praxedo: Ergebnis Rückmeldung'
define abstract entity ZCPRX_A_InboundData
{
  PraxedoId     : abap.char(40);
  PraxedoUUID   : abap.char(40);
  PraxedoStatus : abap.char(20);
  ReportStatus  : abap.char(12);
  Status        : abap.char(12);
  MessageText   : abap.char(220);
}
