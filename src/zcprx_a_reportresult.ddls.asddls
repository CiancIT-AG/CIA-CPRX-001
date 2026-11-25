@EndUserText.label: 'Praxedo: Ergebnis Bericht'
define abstract entity ZCPRX_A_ReportResult
{
  ReportStatus  : abap.char(12);
  ReportMessage : abap.char(220);
  PraxedoUUID   : abap.char(40);
}
