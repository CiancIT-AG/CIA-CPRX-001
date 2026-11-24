@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Praxedo Einsatz – Materialien'
define view entity ZCPRX_R_OrderMaterial
  as select from zcprxmat
  association to parent ZCPRX_R_Order as _Order   on $projection.OrderUUID = _Order.OrderUUID
  association [0..1] to I_Product         as _Product on $projection.Product = _Product.Product
{
  key material_uuid         as MaterialUUID,
      order_uuid            as OrderUUID,
      praxedo_line_id       as PraxedoLineId,
      product               as Product,
      @Semantics.quantity.unitOfMeasure: 'QuantityUnit'
      quantity              as Quantity,
      quantity_unit         as QuantityUnit,
      plant                 as Plant,
      storage_location      as StorageLocation,
      is_posted             as IsPosted,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,

      _Order,
      _Product
}
