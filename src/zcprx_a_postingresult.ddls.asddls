@EndUserText.label: 'Praxedo: Ergebnis Verbuchung'
define abstract entity ZCPRX_A_PostingResult
{
  ServiceConfirmation : abap.char(10);
  Status              : abap.char(12);
  MessageText         : abap.char(220);
}
