@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Praxedo Equipmenttypen (Admin)'
@Metadata.allowExtensions: true
@ObjectModel.semanticKey: [ 'EquipmentType' ]
define root view entity ZCPRX_C_EquipmentType
  provider contract transactional_query
  as projection on ZCPRX_R_EquipmentType
{
  @ObjectModel.text.element: [ 'EquipmentTypeName' ]
  key EquipmentType,
      EquipmentTypeName,
      IsActive,
      PraxedoId,
      @ObjectModel.text.element: [ 'StatusText' ]
      Status,
      _StatusText.StatusText as StatusText,
      LastSentAt,
      MessageText,
      LastChangedAt,
      LocalLastChangedAt
}
