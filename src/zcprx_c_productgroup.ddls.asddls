@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Praxedo Artikelgruppen (Admin)'
@Metadata.allowExtensions: true
@ObjectModel.semanticKey: [ 'ProductGroup' ]
define root view entity ZCPRX_C_ProductGroup
  provider contract transactional_query
  as projection on ZCPRX_R_ProductGroup
{
  @ObjectModel.text.element: [ 'ProductGroupName' ]
  key ProductGroup,
      ProductGroupName,
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
