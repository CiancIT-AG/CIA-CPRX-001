@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Praxedo Equipmenttypen'
define root view entity ZCPRX_R_EquipmentType
  as select from zcprxeqt
  association [0..*] to I_TechnicalObjectTypeText as _Text       on $projection.EquipmentType = _Text.TechnicalObjectType
  association [0..1] to ZCPRX_I_SyncStatusVH  as _StatusText on $projection.Status = _StatusText.Status
{
  key equipment_type                                                           as EquipmentType,
      cast( _Text[1: Language = $session.system_language].TechnicalObjectTypeDesc as abap.char(40) ) as EquipmentTypeName, // Built-in-Typ: Draft-Tabelle darf kein nicht freigegebenes Datenelement nutzen
      is_active                                                                as IsActive,
      praxedo_id                                                               as PraxedoId,
      status                                                                   as Status,
      last_sent_at                                                             as LastSentAt,
      message_text                                                             as MessageText,
      @Semantics.user.createdBy: true
      created_by                                                               as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at                                                               as CreatedAt,
      @Semantics.user.localInstanceLastChangedBy: true
      last_changed_by                                                          as LastChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at                                                          as LastChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at                                                    as LocalLastChangedAt,

      _StatusText
}
