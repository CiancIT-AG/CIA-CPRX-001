@EndUserText.label: 'Praxedo: Konfiguration Singleton'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Semantics.valueRange.maximum: '1'
@ObjectModel.semanticKey: [ 'SingletonID' ]
@UI: {
  headerInfo: {
    typeName: 'PraxedoKonfiguraAll'
  }
}
define root view entity ZCPRX_BCM_I
  as select from I_Language
    left outer join ZCPRXCFG on 0 = 0
  association [0..*] to I_ABAPTransportRequestText as _ABAPTransportRequestText on $projection.TransportRequestID = _ABAPTransportRequestText.TransportRequestID
  composition [0..*] of ZI_PraxedoKonfiguratio as _PraxedoKonfiguratio
{
  @UI.facet: [ {
    id: 'PraxedoKonfiguratio', 
    purpose: #STANDARD, 
    type: #LINEITEM_REFERENCE, 
    label: 'Praxedo: Konfiguration', 
    position: 1 , 
    targetElement: '_PraxedoKonfiguratio'
  } ]
  @UI.lineItem: [ {
    position: 1 
  } ]
  key 1 as SingletonID,
  _PraxedoKonfiguratio,
  @UI.hidden: true
  max( ZCPRXCFG.LAST_CHANGED_AT ) as LastChangedAtMax,
  @ObjectModel.text.association: '_ABAPTransportRequestText'
  @UI.identification: [ {
    position: 1 , 
    type: #WITH_INTENT_BASED_NAVIGATION, 
    semanticObjectAction: 'manage'
  } ]
  @Consumption.semanticObject: 'CustomizingTransport'
  cast( '' as SXCO_TRANSPORT) as TransportRequestID,
  _ABAPTransportRequestText
}
where I_Language.Language = $session.system_language
