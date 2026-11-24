@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Praxedo Sync-Status'
@ObjectModel.resultSet.sizeCategory: #XS
@ObjectModel.dataCategory: #VALUE_HELP
define view entity ZCPRX_I_SyncStatusVH
  as select from DDCDS_CUSTOMER_DOMAIN_VALUE_T( p_domain_name: 'ZCPRX_SYNC_STATUS' )
{
      @ObjectModel.text.element: [ 'StatusText' ]
  key cast( value_low as abap.char(12) ) as Status,
      @Semantics.text: true
      text                              as StatusText
}
where
  language = $session.system_language
