@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Praxedo Verarbeitungs-Queue'
define root view entity ZCPRX_R_Queue
  as select from zcprxque
{
  key queue_uuid            as QueueUUID,
      object_type           as ObjectType,
      object_key            as ObjectKey,
      operation             as Operation,
      status                as Status,
      retry_count           as RetryCount,
      message_text          as MessageText,
      created_at            as CreatedAt,
      started_at            as StartedAt,
      next_retry_at         as NextRetryAt,
      processed_at          as ProcessedAt,
      cast( case status
              when 'ERROR'   then 1
              when 'RUNNING' then 2
              when 'DONE'    then 3
              else 0
            end as abap.int1 ) as StatusCriticality,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at       as LastChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt
}
