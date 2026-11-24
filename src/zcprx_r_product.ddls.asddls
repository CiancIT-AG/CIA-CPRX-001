@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Praxedo Artikel-Synchronisation'
define root view entity ZCPRX_R_Product
  as select from zcprxart
  association [0..1] to I_Product                as _Product     on  $projection.Product = _Product.Product
  association [0..*] to I_ProductDescription     as _Description on  $projection.Product = _Description.Product
  association [0..1] to ZCPRX_I_SyncStatusVH as _StatusText  on  $projection.Status = _StatusText.Status
{
  key product                                                              as Product,
      _Description[1: Language = $session.system_language].ProductDescription as ProductDescription,
      _Product.ProductGroup                                                as ProductGroup,
      _Product.ProductType                                                 as ProductType,
      praxedo_id                                                           as PraxedoId,
      status                                                               as Status,
      last_sent_at                                                         as LastSentAt,
      message_text                                                         as MessageText,
      @Semantics.user.createdBy: true
      created_by                                                           as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at                                                           as CreatedAt,
      @Semantics.user.localInstanceLastChangedBy: true
      last_changed_by                                                      as LastChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at                                                      as LastChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at                                                as LocalLastChangedAt,

      _Product,
      _StatusText
}
