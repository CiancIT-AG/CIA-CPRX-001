@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Praxedo Einsatz (Admin)'
@Metadata.allowExtensions: true
@Search.searchable: true
@ObjectModel.semanticKey: [ 'ServiceOrder', 'ServiceOrderItem' ]
define root view entity ZCPRX_C_Order
  provider contract transactional_query
  as projection on ZCPRX_R_Order
{
  key OrderUUID,
      @Search.defaultSearchElement: true
      PraxedoId,
      @Search.defaultSearchElement: true
      ServiceOrder,
      ServiceOrderItem,
      @Search.defaultSearchElement: true
      Description,
      @ObjectModel.text.element: [ 'SoldToPartyName' ]
      SoldToParty,
      _SoldToParty.CustomerName as SoldToPartyName,
      ShipToParty,
      Equipment,
      Technician,
      PlannedStart,
      PlannedEnd,
      @ObjectModel.text.element: [ 'StatusText' ]
      Status,
      _StatusText.StatusText    as StatusText,
      PraxedoStatus,
      PraxedoUUID,
      ReportStatus,
      ReportAttachedAt,
      ReportMessage,
      ReportCriticality,
      ServiceConfirmation,
      SyncRequired,
      LastSyncAt,
      LastFetchAt,
      PostedAt,
      MessageText,
      StatusCriticality,
      CreatedBy,
      CreatedAt,
      LastChangedBy,
      LastChangedAt,
      LocalLastChangedAt,

      _Time     : redirected to composition child ZCPRX_C_OrderTime,
      _Material : redirected to composition child ZCPRX_C_OrderMaterial
}
