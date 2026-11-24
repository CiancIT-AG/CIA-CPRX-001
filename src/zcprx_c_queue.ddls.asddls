@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Praxedo Queue (Admin)'
@Metadata.allowExtensions: true
define root view entity ZCPRX_C_Queue
  provider contract transactional_query
  as projection on ZCPRX_R_Queue
{
  key QueueUUID,
      ObjectType,
      ObjectKey,
      Operation,
      Status,
      RetryCount,
      MessageText,
      CreatedAt,
      StartedAt,
      NextRetryAt,
      ProcessedAt,
      StatusCriticality,
      LastChangedAt,
      LocalLastChangedAt
}
