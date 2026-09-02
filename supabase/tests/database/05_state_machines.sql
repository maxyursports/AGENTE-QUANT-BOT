-- SAQ-MCDS-V1 §29 (05_state_machines): transiciones validas e invalidas.
-- UNKNOWN permanece UNKNOWN sin evidencia (SAQ-CC-V1 §7 invariante).
begin;
select plan(5);

insert into core.events (project_id, sport_id, competition_id, identity_status, candidate_fingerprint)
select p.project_id, s.sport_id, c.competition_id, 'VALIDATED', repeat('9', 64)
from cfg.projects p join cfg.sports s on s.project_id = p.project_id
join core.competitions c on c.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;

insert into market.selections (project_id, event_id, market_contract_version_id, outcome_side, selection_key)
select p.project_id, ev.event_id, mcv.market_contract_version_id, 'HOME', 'test-selection-sm'
from cfg.projects p
join core.events ev on ev.project_id = p.project_id
join cfg.market_contracts mc on mc.project_id = p.project_id and mc.contract_key = 'FT_1X2'
join cfg.market_contract_versions mcv on mcv.market_contract_id = mc.market_contract_id
where p.project_key = 'agente-quant-bot' limit 1;

insert into market.bookmakers (project_id, bookmaker_key, display_name, region, role, status)
select project_id, 'test_book_sm', 'Test Book', 'GLOBAL', 'SENSOR', 'DRAFT'::app.catalog_status
from cfg.projects where project_key = 'agente-quant-bot';

insert into raw.api_requests (project_id, data_source_id, endpoint, method, request_fingerprint, requested_at, request_status)
select p.project_id, ds.data_source_id, '/test-sm', 'GET', repeat('a1', 32), clock_timestamp(), 'SUCCEEDED'::app.request_status
from cfg.projects p join cfg.data_sources ds on ds.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;

insert into raw.payloads (project_id, request_id, payload_seq, ingested_at, available_for_model_at, content_type, payload_json, content_sha256, byte_count, schema_version, quality_status)
select p.project_id, r.request_id, 1, clock_timestamp(), clock_timestamp(), 'application/json', '{}'::jsonb, repeat('a2', 32), 2, 'v1', 'AVAILABLE'::app.data_quality_status
from cfg.projects p join raw.api_requests r on r.project_id = p.project_id and r.endpoint = '/test-sm'
where p.project_key = 'agente-quant-bot';

insert into market.odds_snapshots (project_id, selection_id, bookmaker_id, price_decimal, ingested_at, available_for_model_at, quote_status, raw_payload_id, idempotency_key)
select p.project_id, (select selection_id from market.selections where selection_key='test-selection-sm'),
       (select bookmaker_id from market.bookmakers where bookmaker_key='test_book_sm'),
       1.90, clock_timestamp(), clock_timestamp(), 'AVAILABLE'::app.quote_status,
       (select raw_payload_id from raw.payloads where content_sha256 = repeat('a2', 32)), repeat('a3', 32)
from cfg.projects p where p.project_key = 'agente-quant-bot';

insert into cfg.model_registry (project_id, sport_id, model_key, display_name, current_stage, health_status, owner)
select p.project_id, s.sport_id, 'test_model_sm', 'Test Model', 'RESEARCH'::app.model_stage, 'HEALTHY'::app.model_health, 'qa'
from cfg.projects p join cfg.sports s on s.project_id = p.project_id where p.project_key = 'agente-quant-bot';

insert into model.model_runs (project_id, model_id, model_version, code_commit_sha, config_hash, data_cutoff_at, stage, health_status, started_at, run_status)
select p.project_id, mr.model_id, '0.1.0', repeat('a4', 20), repeat('a5', 32), clock_timestamp(), 'RESEARCH'::app.model_stage, 'HEALTHY'::app.model_health, clock_timestamp(), 'SUCCEEDED'
from cfg.projects p join cfg.model_registry mr on mr.project_id = p.project_id and mr.model_key = 'test_model_sm'
where p.project_key = 'agente-quant-bot';

insert into model.feature_snapshots (project_id, event_id, feature_set_version, as_of_at, available_for_model_at, values, lineage, completeness, quality_status, snapshot_hash)
select p.project_id, ev.event_id, 'v1', clock_timestamp(), clock_timestamp(), '{}'::jsonb, '{}'::jsonb, 1.0, 'AVAILABLE'::app.data_quality_status, repeat('a6', 32)
from cfg.projects p join core.events ev on ev.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;

insert into model.predictions (project_id, model_run_id, feature_snapshot_id, selection_id, predictive_distribution, fair_price, uncertainty, robust_ev, decision_at, expires_at, prediction_status, prediction_fingerprint)
select p.project_id, (select model_run_id from model.model_runs where config_hash = repeat('a5', 32)),
       (select feature_snapshot_id from model.feature_snapshots where snapshot_hash = repeat('a6', 32)),
       (select selection_id from market.selections where selection_key = 'test-selection-sm'),
       '{}'::jsonb, 2.10, '{}'::jsonb, 0.05, clock_timestamp(), clock_timestamp() + interval '1 hour', 'CREATED'::app.prediction_status, repeat('a7', 32)
from cfg.projects p where p.project_key = 'agente-quant-bot';

insert into ops.signals (project_id, prediction_id, selection_id, odds_snapshot_id, policy_version_id, minimum_acceptable_odds, suggested_stake_fraction, quality_band, generated_at, expiration_at, signal_status, payload_hash)
select p.project_id, (select prediction_id from model.predictions where prediction_fingerprint = repeat('a7', 32)),
       (select selection_id from market.selections where selection_key = 'test-selection-sm'),
       (select odds_snapshot_id from market.odds_snapshots where idempotency_key = repeat('a3', 32)),
       (select policy_version_id from cfg.policy_versions where project_id = p.project_id limit 1),
       1.50, 0, 'NOT_APPROVED', clock_timestamp(), clock_timestamp() + interval '1 hour', 'GENERATED'::app.signal_status, repeat('0', 64)
from cfg.projects p where p.project_key = 'agente-quant-bot';

insert into ops.executions (project_id, signal_id, execution_status, confirmation_method)
select p.project_id, (select signal_id from ops.signals where payload_hash = repeat('0', 64)),
       'UNKNOWN'::app.execution_status, 'TELEGRAM_USER'
from cfg.projects p where p.project_key = 'agente-quant-bot';

-- Permanecer en UNKNOWN no exige evidencia.
select lives_ok(
  $$ insert into ops.execution_events (project_id, execution_id, from_status, to_status, actor_type, evidence, event_hash)
     select project_id, (select execution_id from ops.executions where confirmation_method='TELEGRAM_USER' limit 1),
            'UNKNOWN'::app.execution_status, 'UNKNOWN'::app.execution_status, 'SYSTEM', '{}'::jsonb, repeat('1', 64)
     from cfg.projects where project_key='agente-quant-bot' $$,
  'permanecer en UNKNOWN sin evidencia es aceptado'
);

-- Abandonar UNKNOWN sin evidencia: rechazado.
select throws_ok(
  $$ insert into ops.execution_events (project_id, execution_id, from_status, to_status, actor_type, evidence, event_hash)
     select project_id, (select execution_id from ops.executions where confirmation_method='TELEGRAM_USER' limit 1),
            'UNKNOWN'::app.execution_status, 'BET_PLACED'::app.execution_status, 'USER', '{}'::jsonb, repeat('2', 64)
     from cfg.projects where project_key='agente-quant-bot' $$,
  null, 'abandonar UNKNOWN sin evidencia es rechazado'
);

-- Abandonar UNKNOWN CON evidencia: aceptado.
select lives_ok(
  $$ insert into ops.execution_events (project_id, execution_id, from_status, to_status, actor_type, evidence, event_hash)
     select project_id, (select execution_id from ops.executions where confirmation_method='TELEGRAM_USER' limit 1),
            'UNKNOWN'::app.execution_status, 'BET_PLACED'::app.execution_status, 'USER', '{"receipt":"r1"}'::jsonb, repeat('3', 64)
     from cfg.projects where project_key='agente-quant-bot' $$,
  'abandonar UNKNOWN con evidencia no vacia es aceptado'
);

-- from_status declarado que no coincide con el execution_status vigente (sigue siendo UNKNOWN
-- en ops.executions porque este trigger no actualiza esa tabla): rechazado por "stale".
select throws_ok(
  $$ insert into ops.execution_events (project_id, execution_id, from_status, to_status, actor_type, evidence, event_hash)
     select project_id, (select execution_id from ops.executions where confirmation_method='TELEGRAM_USER' limit 1),
            'BET_PLACED'::app.execution_status, 'MARKET_CLOSED'::app.execution_status, 'SYSTEM', '{"x":1}'::jsonb, repeat('4', 64)
     from cfg.projects where project_key='agente-quant-bot' $$,
  null, 'from_status declarado que no coincide con el estado vigente es rechazado'
);

select is((select count(*)::int from ops.execution_events
             where execution_id = (select execution_id from ops.executions where confirmation_method='TELEGRAM_USER' limit 1)),
  2, 'solo las 2 transiciones validas quedaron persistidas');

select * from finish();
rollback;
