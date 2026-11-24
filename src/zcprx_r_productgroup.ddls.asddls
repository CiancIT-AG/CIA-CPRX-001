@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Praxedo Artikelgruppen'
define root view entity ZCPRX_R_ProductGroup
  as select from zcprxagr
  association [0..*] to I_ProductGroupText_2     as _Text       on $projection.ProductGroup = _Text.ProductGroup
  association [0..1] to ZCPRX_I_SyncStatusVH as _StatusText on $projection.Status = _StatusText.Status
{
  key product_group                                                    as ProductGroup,
      cast( _Text[1: Language = $session.system_language].ProductGroupName as abap.char(60) ) as ProductGroupName, // Built-in-Typ für die Draft-Tabelle
      is_active                                                        as IsActive,
      praxedo_id                                                       as PraxedoId,
      status                                                           as Status,
      last_sent_at                                                     as LastSentAt,
      message_text                                                     as MessageText,
      @Semantics.user.createdBy: true
      created_by                                                       as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at                                                       as CreatedAt,
      @Semantics.user.localInstanceLastChangedBy: true
      last_changed_by                                                  as LastChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at                                                  as LastChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at                                            as LocalLastChangedAt,

      _StatusText
}
