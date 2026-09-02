-- SAQ-MCDS-V1 §29 (08_rpc): confirmacion concurrente/repetida.
-- Una sola ejecucion canonica (SAQ-MCDS-V1 §26, Apendice B "confirm_execution").
begin;
select plan(6);

insert into auth.users (id) values ('33333333-3333-3333-3333-333333333333');
insert into cfg.project_members (project_id, user_id, member_role, status)
select project_id, '33333333-3333-3333-3333-333333333333'::uuid, 'OPERATOR'::app.member_role, 'ACTIVE'::app.membership_status
from cfg.projects where project_key = 'agente-quant-bot';

insert into core.events (project_id, sport_id, competition_id, identity_status, candidate_fingerprint)
select p.project_id, s.sport_id, c.competition_id, 'VALIDATED', repeat('d1', 32)
from cfg.projects p join cfg.sports s on s.project_id = p.project_id
join core.competitions c on c.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;

insert into market.selections (project_id, event_id, market_contract_version_id, outcome_side, selection_key)
select p.project_id, ev.event_id, mcv.market_contract_version_id, 'HOME', 'test-selection-rpc'
from cfg.projects p
join core.events ev on ev.project_id = p.project_id
join cfg.market_contracts mc on mc.project_id = p.project_id and mc.contract_key = 'FT_1X2'
join cfg.market_contract_versions mcv on mcv.market_contract_id = mc.market_contract_id
where p.project_key = 'agente-quant-bot' limit 1;

insert into market.bookmakers (project_id, bookmaker_key, display_name, region, role, status)
select project_id, 'test_book_rpc', 'Test Book', 'GLOBAL', 'SENSOR', 'DRAFT'::app.catalog_status
from cfg.projects where project_key = 'agente-quant-bot';
insert into raw.api_requests (project_id, data_source_id, endpoint, method, request_fingerprint, requested_at, request_status)
select p.project_id, ds.data_source_id, '/test-rpc', 'GET', repeat('d4', 32), clock_timestamp(), 'SUCCEEDED'::app.request_status
from cfg.projects p join cfg.data_sources ds on ds.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;
insert into raw.payloads (project_id, request_id, payload_seq, ingested_at, available_for_model_at, content_type, payload_json, content_sha256, byte_count, schema_version, quality_status)
select p.project_id, r.request_id, 1, clock_timestamp(), clock_timestamp(), 'application/json', '{}'::jsonb, repeat('d5', 32), 2, 'v1', 'AVAILABLE'::app.data_quality_status
from cfg.projects p join raw.api_requests r on r.project_id = p.project_id and r.endpoint = '/test-rpc'
where p.project_key = 'agente-quant-bot';
insert into market.odds_snapshots (project_id, selection_id, bookmaker_id, price_decimal, ingested_at, available_for_model_at, quote_status, raw_payload_id, idempotency_key)
select p.project_id, (select selection_id from market.selections where selection_key='test-selection-rpc'),
       (select bookmaker_id from market.bookmakers where bookmaker_key='test_book_rpc'),
       1.90, clock_timestamp(), clock_timestamp(), 'AVAILABLE'::app.quote_status,
       (select raw_payload_id from raw.payloads where content_sha256 = repeat('d5', 32)), repeat('d6', 32)
from cfg.projects p where p.project_key = 'agente-quant-bot';
insert into cfg.model_registry (project_id, sport_id, model_key, display_name, current_stage, health_status, owner)
select p.project_id, s.sport_id, 'test_model_rpc', 'Test Model', 'RESEARCH'::app.model_stage, 'HEALTHY'::app.model_health, 'qa'
from cfg.projects p join cfg.sports s on s.project_id = p.project_id where p.project_key = 'agente-quant-bot';
insert into model.model_runs (project_id, model_id, model_version, code_commit_sha, config_hash, data_cutoff_at, stage, health_status, started_at, run_status)
select p.project_id, mr.model_id, '0.1.0', repeat('d7', 20), repeat('d8', 32), clock_timestamp(), 'RESEARCH'::app.model_stage, 'HEALTHY'::app.model_health, clock_timestamp(), 'SUCCEEDED'
from cfg.projects p join cfg.model_registry mr on mr.project_id = p.project_id and mr.model_key = 'test_model_rpc'
where p.project_key = 'agente-quant-bot';
insert into model.feature_snapshots (project_id, event_id, feature_set_version, as_of_at, available_for_model_at, values, lineage, completeness, quality_status, snapshot_hash)
select p.project_id, ev.event_id, 'v1', clock_timestamp(), clock_timestamp(), '{}'::jsonb, '{}'::jsonb, 1.0, 'AVAILABLE'::app.data_quality_status, repeat('d9', 32)
from cfg.projects p join core.events ev on ev.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;
insert into model.predictions (project_id, model_run_id, feature_snapshot_id, selection_id, predictive_distribution, fair_price, uncertainty, robust_ev, decision_at, expires_at, prediction_status, prediction_fingerprint)
select p.project_id, (select model_run_id from model.model_runs where config_hash = repeat('d8', 32)),
       (select feature_snapshot_id from model.feature_snapshots where snapshot_hash = repeat('d9', 32)),
       (select selection_id from market.selections where selection_key = 'test-selection-rpc'),
       '{}'::jsonb, 2.10, '{}'::jsonb, 0.05, clock_timestamp(), clock_timestamp() + interval '1 hour', 'CREATED'::app.prediction_status, repeat('da', 32)
from cfg.projects p where p.project_key = 'agente-quant-bot';

insert into ops.signals (project_id, prediction_id, selection_id, odds_snapshot_id, policy_version_id, minimum_acceptable_odds, suggested_stake_fraction, quality_band, generated_at, expiration_at, signal_status, payload_hash)
select p.project_id, (select prediction_id from model.predictions where prediction_fingerprint = repeat('da', 32)),
       (select selection_id from market.selections where selection_key='test-selection-rpc'),
       (select odds_snapshot_id from market.odds_snapshots where idempotency_key = repeat('d6', 32)),
       (select policy_version_id from cfg.policy_versions where project_id = p.project_id limit 1),
       1.50, 0, 'HIGH', clock_timestamp(), clock_timestamp() + interval '1 hour', 'SENT_TELEGRAM'::app.signal_status, repeat('d2', 32)
from cfg.projects p where p.project_key = 'agente-quant-bot';

insert into market.odds_snapshots (project_id, selection_id, bookmaker_id, price_decimal, ingested_at, available_for_model_at, quote_status, raw_payload_id, idempotency_key)
select p.project_id, (select selection_id from market.selections where selection_key='test-selection-rpc'),
       (select bookmaker_id from market.bookmakers where bookmaker_key='test_book_rpc'),
       1.85, clock_timestamp(), clock_timestamp(), 'AVAILABLE'::app.quote_status,
       (select raw_payload_id from raw.payloads where content_sha256 = repeat('d5', 32)), repeat('db', 32)
from cfg.projects p where p.project_key = 'agente-quant-bot';

insert into ops.signals (project_id, prediction_id, selection_id, odds_snapshot_id, policy_version_id, minimum_acceptable_odds, suggested_stake_fraction, quality_band, generated_at, expiration_at, signal_status, payload_hash)
select p.project_id, (select prediction_id from model.predictions where prediction_fingerprint = repeat('da', 32)),
       (select selection_id from market.selections where selection_key='test-selection-rpc'),
       (select odds_snapshot_id from market.odds_snapshots where idempotency_key = repeat('db', 32)),
       (select policy_version_id from cfg.policy_versions where project_id = p.project_id limit 1),
       1.50, 0, 'HIGH', clock_timestamp(), clock_timestamp() - interval '1 hour', 'EXPIRED'::app.signal_status, repeat('d3', 32)
from cfg.projects p where p.project_key = 'agente-quant-bot';

set local role authenticated;
set local "request.jwt.claim.sub" to '33333333-3333-3333-3333-333333333333';

-- Cuota por debajo del minimo: rechazado.
select throws_ok(
  format($$ select api.confirm_execution(%L, 'k-below-min', 1.10, null, 50.00, clock_timestamp()) $$,
    (select signal_id from ops.signals where payload_hash = repeat('d2', 32))),
  null, 'actual_odds por debajo de minimum_acceptable_odds es rechazado'
);

-- Signal expirado: rechazado.
select throws_ok(
  format($$ select api.confirm_execution(%L, 'k-expired', 1.80, null, 50.00, clock_timestamp()) $$,
    (select signal_id from ops.signals where payload_hash = repeat('d3', 32))),
  null, 'confirmar una signal expirada es rechazado'
);

-- Primera confirmacion: exitosa.
select lives_ok(
  format($$ select api.confirm_execution(%L, 'k-ok', 1.80, null, 50.00, clock_timestamp()) $$,
    (select signal_id from ops.signals where payload_hash = repeat('d2', 32))),
  'primera confirmacion con cuota valida es aceptada'
);

select is((select count(*)::int from ops.executions where signal_id = (select signal_id from ops.signals where payload_hash = repeat('d2', 32))),
  1, 'exactamente 1 execution tras la primera confirmacion');

-- Reintento (misma idempotency_key): devuelve el MISMO execution_id, no crea una segunda fila.
select is(
  (select api.confirm_execution((select signal_id from ops.signals where payload_hash = repeat('d2', 32)), 'k-ok', 1.80, null, 50.00, clock_timestamp())),
  (select execution_id from ops.executions where signal_id = (select signal_id from ops.signals where payload_hash = repeat('d2', 32))),
  'reintento con la misma idempotency_key devuelve el execution_id existente'
);

select is((select count(*)::int from ops.executions where signal_id = (select signal_id from ops.signals where payload_hash = repeat('d2', 32))),
  1, 'sigue existiendo una unica ejecucion canonica tras el reintento');

reset role;
reset "request.jwt.claim.sub";

select * from finish();
rollback;
