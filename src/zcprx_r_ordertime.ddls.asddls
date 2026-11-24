@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Praxedo Einsatz – Zeiten'
define view entity ZCPRX_R_OrderTime
  as select from zcprxtim
  association to parent ZCPRX_R_Order as _Order on $projection.OrderUUID = _Order.OrderUUID
{
  key time_uuid             as TimeUUID,
      order_uuid            as OrderUUID,
      praxedo_line_id       as PraxedoLineId,
      technician            as Technician,
      service_product       as ServiceProduct,
      start_at              as StartAt,
      end_at                as EndAt,
      @Semantics.quantity.unitOfMeasure: 'DurationUnit'
      duration              as Duration,
      duration_unit         as DurationUnit,
      is_posted             as IsPosted,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,

      _Order
}
