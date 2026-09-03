-- SAQ-MCDS-V1 §25, §26, Apendice B.2 · 0012_api_views_and_rpcs
-- Superficie api con security_invoker y RPC transaccionales.
-- Ninguna view expuesta se crea sin security_invoker=true (SAQ-MCDS-V1 §25).

revoke execute on all functions in schema api from public, anon, authenticated;

-- api.v_event_schedule: eventos y su ultima version bitemporal; sin raw_payload_id (sin raw payload).
create view api.v_event_schedule
with (security_invoker = true) as
select distinct on (e.event_id)
  e.event_id,
  e.project_id,
  e.competition_id,
  e.season_id,
  e.home_participant_id,
  e.away_participant_id,
  e.identity_status,
  ev.event_version_id,
  ev.scheduled_start_at,
  ev.lifecycle_status,
  ev.analysis_status,
  ev.venue,
  ev.valid_from
from core.events e
join core.event_versions ev on ev.event_id = e.event_id
order by e.event_id, ev.valid_from desc;

-- api.v_active_signals: senales vigentes con precio y condiciones de invalidacion.
-- Filtro literal de Apendice B.2 (signal_status APPROVED/SENT_TELEGRAM; expiration_at > now()).
create view api.v_active_signals
with (security_invoker = true) as
select
  s.signal_id,
  s.project_id,
  s.prediction_id,
  s.selection_id,
  s.odds_snapshot_id,
  s.policy_version_id,
  s.minimum_acceptable_odds,
  s.suggested_stake_fraction,
  s.quality_band,
  s.reason_codes,
  s.invalidation_conditions,
  s.generated_at,
  s.expiration_at,
  s.signal_status
from ops.signals s
where s.signal_status in ('APPROVED','SENT_TELEGRAM')
  and s.expiration_at > clock_timestamp();

-- api.v_execution_queue: senales enviadas que todavia no tienen ejecucion registrada.
create view api.v_execution_queue
with (security_invoker = true) as
select
  s.signal_id,
  s.project_id,
  s.selection_id,
  s.minimum_acceptable_odds,
  s.suggested_stake_fraction,
  s.generated_at,
  s.expiration_at
from ops.signals s
where s.signal_status = 'SENT_TELEGRAM'
  and s.expiration_at > clock_timestamp()
  and not exists (
    select 1 from ops.executions e where e.signal_id = s.signal_id
  );

-- api.v_performance_summary: metricas de evaluation_runs ya cerradas (SUCCEEDED/LOCKED),
-- unica nocion de "aprobadas" disponible en el estado cerrado de model.evaluation_runs.status.
create view api.v_performance_summary
with (security_invoker = true) as
select
  mr.project_id,
  mr.evaluation_run_id,
  er.model_id,
  er.policy_version_id,
  er.evaluation_type,
  er.status as evaluation_status,
  mr.metric_name,
  mr.metric_version,
  mr.segment,
  mr.value,
  mr.lower_ci,
  mr.upper_ci,
  mr.effective_sample_size,
  mr.calculated_at
from model.metric_results mr
join model.evaluation_runs er on er.evaluation_run_id = mr.evaluation_run_id
where er.status in ('SUCCEEDED','LOCKED');

-- api.v_model_health: salud registrada y ultima evaluacion por modelo.
create view api.v_model_health
with (security_invoker = true) as
select
  mreg.project_id,
  mreg.model_id,
  mreg.model_key,
  mreg.current_stage,
  mreg.health_status,
  last_run.evaluation_run_id as last_evaluation_run_id,
  last_run.evaluation_type as last_evaluation_type,
  last_run.status as last_evaluation_status,
  last_run.completed_at as last_evaluation_completed_at
from cfg.model_registry mreg
left join lateral (
  select er.evaluation_run_id, er.evaluation_type, er.status, er.completed_at
  from model.evaluation_runs er
  where er.model_id = mreg.model_id
  order by er.started_at desc
  limit 1
) last_run on true;

-- api.confirm_execution: crea/corrige ejecucion y su evento en una transaccion (Apendice B, §26).
-- SECURITY INVOKER (por defecto, §26): corre con los privilegios y RLS de authenticated;
-- requiere el GRANT INSERT + policy OPERATOR/OWNER ya otorgados en 0011.
create function api.confirm_execution(
  p_signal_id uuid,
  p_idempotency_key text,
  p_actual_odds app.price_t,
  p_actual_line app.line_t,
  p_accepted_stake app.money_t,
  p_placed_at timestamptz,
  p_receipt_ref text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_signal ops.signals%rowtype;
  v_existing_execution_id uuid;
  v_execution_id uuid;
  v_event_hash app.hash_t;
begin
  -- 1. auth.uid() + project membership + role OPERATOR/OWNER: aplicado por la RLS policy
  --    executions_insert_operator / execution_events_insert_operator (SECURITY INVOKER).
  -- 2. SELECT signal FOR UPDATE; verificar vigencia y linea exacta.
  select * into v_signal
  from ops.signals
  where signal_id = p_signal_id
  for update;

  if not found then
    raise exception 'confirm_execution_signal_not_found: signal % no existe o no es visible', p_signal_id;
  end if;

  if v_signal.expiration_at <= clock_timestamp() then
    raise exception 'confirm_execution_signal_expired: signal % expiro en %', p_signal_id, v_signal.expiration_at;
  end if;

  -- 3. actual_odds >= minimum_acceptable_odds.
  if p_actual_odds < v_signal.minimum_acceptable_odds then
    raise exception 'confirm_execution_odds_below_minimum: % < % (signal %)',
      p_actual_odds, v_signal.minimum_acceptable_odds, p_signal_id;
  end if;

  -- 5. return existing execution when idempotency hash matches.
  v_event_hash := encode(extensions.digest(p_signal_id::text || ':' || p_idempotency_key, 'sha256'), 'hex');

  select ee.execution_id into v_existing_execution_id
  from ops.execution_events ee
  where ee.event_hash = v_event_hash;

  if found then
    return v_existing_execution_id;
  end if;

  -- 4. insert execution + execution_event atomicamente.
  insert into ops.executions (
    project_id, signal_id, execution_status, actual_odds, actual_line,
    requested_stake, accepted_stake, attempted_at, placed_at,
    confirmation_method, receipt_ref
  ) values (
    v_signal.project_id, p_signal_id, 'BET_PLACED'::app.execution_status, p_actual_odds, p_actual_line,
    p_accepted_stake, p_accepted_stake, clock_timestamp(), p_placed_at,
    'TELEGRAM_USER', p_receipt_ref
  )
  returning execution_id into v_execution_id;

  insert into ops.execution_events (
    project_id, execution_id, from_status, to_status, actor_type, evidence, event_hash
  ) values (
    v_signal.project_id, v_execution_id, null, 'BET_PLACED'::app.execution_status,
    'USER',
    jsonb_build_object('idempotency_key', p_idempotency_key, 'receipt_ref', p_receipt_ref),
    v_event_hash
  );

  return v_execution_id;
end;
$$;
revoke execute on function api.confirm_execution(uuid, text, app.price_t, app.line_t, app.money_t, timestamptz, text) from public, anon;
grant execute on function api.confirm_execution(uuid, text, app.price_t, app.line_t, app.money_t, timestamptz, text) to authenticated;

-- api.mark_not_placed: registra NOT_PLACED con motivo y hora (§25).
create function api.mark_not_placed(
  p_signal_id uuid,
  p_rejection_reason text,
  p_occurred_at timestamptz default clock_timestamp()
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_signal ops.signals%rowtype;
  v_execution_id uuid;
begin
  select * into v_signal from ops.signals where signal_id = p_signal_id for update;

  if not found then
    raise exception 'mark_not_placed_signal_not_found: signal % no existe o no es visible', p_signal_id;
  end if;

  insert into ops.executions (
    project_id, signal_id, execution_status, attempted_at,
    confirmation_method, rejection_reason
  ) values (
    v_signal.project_id, p_signal_id, 'NOT_PLACED'::app.execution_status, p_occurred_at,
    'TELEGRAM_USER', p_rejection_reason
  )
  returning execution_id into v_execution_id;

  insert into ops.execution_events (
    project_id, execution_id, from_status, to_status, actor_type, evidence, event_hash
  ) values (
    v_signal.project_id, v_execution_id, null, 'NOT_PLACED'::app.execution_status,
    'USER',
    jsonb_build_object('rejection_reason', p_rejection_reason),
    encode(extensions.digest(v_execution_id::text || ':not_placed', 'sha256'), 'hex')
  );

  return v_execution_id;
end;
$$;
revoke execute on function api.mark_not_placed(uuid, text, timestamptz) from public, anon;
grant execute on function api.mark_not_placed(uuid, text, timestamptz) to authenticated;

-- api.expire_signal: RPC backend, expira senales por TTL de forma idempotente (§25).
-- Unicamente service_role (job/backend), nunca clientes autenticados directos.
create function api.expire_signal()
returns integer
language sql
security invoker
set search_path = ''
as $$
  select app.expire_signals();
$$;
revoke execute on function api.expire_signal() from public, anon, authenticated;
grant execute on function api.expire_signal() to service_role;

-- api.request_settlement_replay: RPC OWNER, encola el pedido; nunca edita settlements
-- historicos (§25/§26). No existe una tabla de cola dedicada en el inventario cerrado de 36
-- tablas; se registra como ops.audit_events (accion REQUEST_SETTLEMENT_REPLAY), el unico
-- mecanismo generico de gobierno/auditoria disponible para este proposito.
create function api.request_settlement_replay(
  p_settlement_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_project_id uuid;
  v_audit_event_id uuid;
begin
  select project_id into v_project_id from ops.settlements where settlement_id = p_settlement_id;

  if not found then
    raise exception 'request_settlement_replay_not_found: settlement % no existe o no es visible', p_settlement_id;
  end if;

  insert into ops.audit_events (
    project_id, actor_type, actor_id, action, entity_schema, entity_table, entity_id,
    reason, created_at, event_hash
  ) values (
    v_project_id, 'USER', auth.uid(), 'REQUEST_SETTLEMENT_REPLAY', 'ops', 'settlements', p_settlement_id,
    p_reason, clock_timestamp(),
    encode(extensions.digest(p_settlement_id::text || ':' || clock_timestamp()::text, 'sha256'), 'hex')
  )
  returning audit_event_id into v_audit_event_id;

  return v_audit_event_id;
end;
$$;
revoke execute on function api.request_settlement_replay(uuid, text) from public, anon;
grant execute on function api.request_settlement_replay(uuid, text) to authenticated;
