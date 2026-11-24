@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Praxedo Einsatz – Zeiten (Admin)'
@Metadata.allowExtensions: true
define view entity ZCPRX_C_OrderTime
  as projection on ZCPRX_R_OrderTime
{
  key TimeUUID,
      OrderUUID,
      PraxedoLineId,
      Technician,
      ServiceProduct,
      StartAt,
      EndAt,
      Duration,
      DurationUnit,
      IsPosted,
      LocalLastChangedAt,

      _Order : redirected to parent ZCPRX_C_Order
}
