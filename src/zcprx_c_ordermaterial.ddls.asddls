@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Praxedo Einsatz – Materialien (Admin)'
@Metadata.allowExtensions: true
define view entity ZCPRX_C_OrderMaterial
  as projection on ZCPRX_R_OrderMaterial
{
  key MaterialUUID,
      OrderUUID,
      PraxedoLineId,
      Product,
      Quantity,
      QuantityUnit,
      Plant,
      StorageLocation,
      IsPosted,
      LocalLastChangedAt,

      _Order : redirected to parent ZCPRX_C_Order
}
