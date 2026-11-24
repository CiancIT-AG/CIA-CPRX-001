@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Praxedo Artikel (Admin)'
@Metadata.allowExtensions: true
@Search.searchable: true
define root view entity ZCPRX_C_Product
  provider contract transactional_query
  as projection on ZCPRX_R_Product
{
      @Search.defaultSearchElement: true
  @ObjectModel.text.element: [ 'ProductDescription' ]
  key Product,
      @Search.defaultSearchElement: true
      ProductDescription,
      ProductGroup,
      ProductType,
      PraxedoId,
      @ObjectModel.text.element: [ 'StatusText' ]
      Status,
      _StatusText.StatusText as StatusText,
      LastSentAt,
      MessageText,
      LastChangedAt,
      LocalLastChangedAt
}
