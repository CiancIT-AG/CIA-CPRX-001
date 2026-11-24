@EndUserText.label: 'Praxedo: Konfiguration'
@AccessControl.authorizationCheck: #MANDATORY
@Metadata.allowExtensions: true
define view entity ZI_PraxedoKonfiguratio
  as select from ZCPRXCFG
  association to parent ZCPRX_BCM_I as _PraxedoKonfiguraAll on $projection.SingletonID = _PraxedoKonfiguraAll.SingletonID
{
  key PARAM as Param,
  VALUE as Value,
  @Semantics.systemDateTime.lastChangedAt: true
  LAST_CHANGED_AT as LastChangedAt,
  @Consumption.hidden: true
  1 as SingletonID,
  _PraxedoKonfiguraAll
}
