@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Praxedo Auftrag / Einsatz'
define root view entity ZCPRX_R_Order
  as select from zcprxord
  composition [0..*] of ZCPRX_R_OrderTime     as _Time
  composition [0..*] of ZCPRX_R_OrderMaterial as _Material
  association [0..1] to I_Customer                as _SoldToParty on $projection.SoldToParty = _SoldToParty.Customer
  association [0..1] to I_Customer                as _ShipToParty on $projection.ShipToParty = _ShipToParty.Customer
  association [0..1] to I_Equipment               as _Equipment   on $projection.Equipment = _Equipment.Equipment
  association [0..1] to ZCPRX_I_OrderStatusVH as _StatusText  on $projection.Status = _StatusText.Status
{
  key order_uuid            as OrderUUID,
      praxedo_id            as PraxedoId,
      service_order         as ServiceOrder,
      service_order_item    as ServiceOrderItem,
      description           as Description,
      sold_to_party         as SoldToParty,
      ship_to_party         as ShipToParty,
      equipment             as Equipment,
      technician            as Technician,
      planned_start         as PlannedStart,
      planned_end           as PlannedEnd,
      status                as Status,
      praxedo_status        as PraxedoStatus,
      service_confirmation  as ServiceConfirmation,
      sync_required         as SyncRequired,
      last_sync_at          as LastSyncAt,
      last_fetch_at         as LastFetchAt,
      posted_at             as PostedAt,
      message_text          as MessageText,
      // UI-Kritikalität: 1 rot, 2 gelb, 3 grün, 0 neutral (nicht persistiert)
      cast( case status
              when 'ERROR'      then 1
              when 'IN_PROCESS' then 2
              when 'RECEIVED'   then 2
              when 'PROCESSED'  then 3
              when 'SENT'       then 3
              else 0
            end as abap.int1 )  as StatusCriticality,
      @Semantics.user.createdBy: true
      created_by            as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at            as CreatedAt,
      @Semantics.user.localInstanceLastChangedBy: true
      last_changed_by       as LastChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at       as LastChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,

      _Time,
      _Material,
      _SoldToParty,
      _ShipToParty,
      _Equipment,
      _StatusText
}
