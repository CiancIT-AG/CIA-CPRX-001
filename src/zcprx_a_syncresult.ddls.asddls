@EndUserText.label: 'Praxedo: Ergebnis Übertragung'
define abstract entity ZCPRX_A_SyncResult
{
  PraxedoId   : abap.char(40);
  Status      : abap.char(12);
  MessageText : abap.char(220);
}
