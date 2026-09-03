-- SAQ-MCDS-V1 §29 (06_settlement): WIN/HALF_WIN/PUSH/HALF_LOSS/LOSS/VOID.
-- Payoff exacto para enteros, medias y cuartos (SAQ-CC-V1 §14/§15).
begin;
select plan(7);

insert into core.events (project_id, sport_id, competition_id, identity_status, candidate_fingerprint)
select p.project_id, s.sport_id, c.competition_id, 'VALIDATED', repeat('b1', 32)
from cfg.projects p join cfg.sports s on s.project_id = p.project_id
join core.competitions c on c.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;

insert into market.selections (project_id, event_id, market_contract_version_id, outcome_side, selection_key)
select p.project_id, ev.event_id, mcv.market_contract_version_id, 'HOME', 'test-selection-settlement'
from cfg.projects p
join core.events ev on ev.project_id = p.project_id
join cfg.market_contracts mc on mc.project_id = p.project_id and mc.contract_key = 'FT_1X2'
join cfg.market_contract_versions mcv on mcv.market_contract_id = mc.market_contract_id
where p.project_key = 'agente-quant-bot' limit 1;

insert into market.bookmakers (project_id, bookmaker_key, display_name, region, role, status)
select project_id, 'test_book_settlement', 'Test Book', 'GLOBAL', 'SENSOR', 'DRAFT'::app.catalog_status
from cfg.projects where project_key = 'agente-quant-bot';

insert into raw.api_requests (project_id, data_source_id, endpoint, method, request_fingerprint, requested_at, request_status)
select p.project_id, ds.data_source_id, '/test-settlement-odds', 'GET', repeat('b5', 32), clock_timestamp(), 'SUCCEEDED'::app.request_status
from cfg.projects p join cfg.data_sources ds on ds.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;
insert into raw.payloads (project_id, request_id, payload_seq, ingested_at, available_for_model_at, content_type, payload_json, content_sha256, byte_count, schema_version, quality_status)
select p.project_id, r.request_id, 1, clock_timestamp(), clock_timestamp(), 'application/json', '{}'::jsonb, repeat('b6', 32), 2, 'v1', 'AVAILABLE'::app.data_quality_status
from cfg.projects p join raw.api_requests r on r.project_id = p.project_id and r.endpoint = '/test-settlement-odds'
where p.project_key = 'agente-quant-bot';
insert into market.odds_snapshots (project_id, selection_id, bookmaker_id, price_decimal, ingested_at, available_for_model_at, quote_status, raw_payload_id, idempotency_key)
select p.project_id, (select selection_id from market.selections where selection_key='test-selection-settlement'),
       (select bookmaker_id from market.bookmakers where bookmaker_key='test_book_settlement'),
       1.90, clock_timestamp(), clock_timestamp(), 'AVAILABLE'::app.quote_status,
       (select raw_payload_id from raw.payloads where content_sha256 = repeat('b6', 32)), repeat('b7', 32)
from cfg.projects p where p.project_key = 'agente-quant-bot';

insert into cfg.model_registry (project_id, sport_id, model_key, display_name, current_stage, health_status, owner)
select p.project_id, s.sport_id, 'test_model_settlement', 'Test Model', 'RESEARCH'::app.model_stage, 'HEALTHY'::app.model_health, 'qa'
from cfg.projects p join cfg.sports s on s.project_id = p.project_id where p.project_key = 'agente-quant-bot';
insert into model.model_runs (project_id, model_id, model_version, code_commit_sha, config_hash, data_cutoff_at, stage, health_status, started_at, run_status)
select p.project_id, mr.model_id, '0.1.0', repeat('b8', 20), repeat('b9', 32), clock_timestamp(), 'RESEARCH'::app.model_stage, 'HEALTHY'::app.model_health, clock_timestamp(), 'SUCCEEDED'
from cfg.projects p join cfg.model_registry mr on mr.project_id = p.project_id and mr.model_key = 'test_model_settlement'
where p.project_key = 'agente-quant-bot';
insert into model.feature_snapshots (project_id, event_id, feature_set_version, as_of_at, available_for_model_at, values, lineage, completeness, quality_status, snapshot_hash)
select p.project_id, ev.event_id, 'v1', clock_timestamp(), clock_timestamp(), '{}'::jsonb, '{}'::jsonb, 1.0, 'AVAILABLE'::app.data_quality_status, repeat('ba', 32)
from cfg.projects p join core.events ev on ev.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;
insert into model.predictions (project_id, model_run_id, feature_snapshot_id, selection_id, predictive_distribution, fair_price, uncertainty, robust_ev, decision_at, expires_at, prediction_status, prediction_fingerprint)
select p.project_id, (select model_run_id from model.model_runs where config_hash = repeat('b9', 32)),
       (select feature_snapshot_id from model.feature_snapshots where snapshot_hash = repeat('ba', 32)),
       (select selection_id from market.selections where selection_key = 'test-selection-settlement'),
       '{}'::jsonb, 2.10, '{}'::jsonb, 0.05, clock_timestamp(), clock_timestamp() + interval '1 hour', 'CREATED'::app.prediction_status, repeat('bb', 32)
from cfg.projects p where p.project_key = 'agente-quant-bot';

insert into ops.signals (project_id, prediction_id, selection_id, odds_snapshot_id, policy_version_id, minimum_acceptable_odds, suggested_stake_fraction, quality_band, generated_at, expiration_at, signal_status, payload_hash)
select p.project_id, (select prediction_id from model.predictions where prediction_fingerprint = repeat('bb', 32)),
       (select selection_id from market.selections where selection_key='test-selection-settlement'),
       (select odds_snapshot_id from market.odds_snapshots where idempotency_key = repeat('b7', 32)),
       (select policy_version_id from cfg.policy_versions where project_id = p.project_id limit 1),
       1.50, 0, 'NOT_APPROVED', clock_timestamp(), clock_timestamp() + interval '1 hour', 'GENERATED'::app.signal_status, repeat('b2', 32)
from cfg.projects p where p.project_key = 'agente-quant-bot';

insert into ops.executions (project_id, signal_id, execution_status, confirmation_method)
select p.project_id, (select signal_id from ops.signals where payload_hash = repeat('b2', 32)), 'BET_PLACED'::app.execution_status, 'TELEGRAM_USER'
from cfg.projects p where p.project_key = 'agente-quant-bot';

insert into raw.api_requests (project_id, data_source_id, endpoint, method, request_fingerprint, requested_at, request_status)
select p.project_id, ds.data_source_id, '/test-settlement', 'GET', repeat('b3', 32), clock_timestamp(), 'SUCCEEDED'::app.request_status
from cfg.projects p join cfg.data_sources ds on ds.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;
insert into raw.payloads (project_id, request_id, payload_seq, ingested_at, available_for_model_at, content_type, payload_json, content_sha256, byte_count, schema_version, quality_status)
select p.project_id, r.request_id, 1, clock_timestamp(), clock_timestamp(), 'application/json', '{}'::jsonb, repeat('b4', 32), 2, 'v1', 'AVAILABLE'::app.data_quality_status
from cfg.projects p join raw.api_requests r on r.project_id = p.project_id and r.endpoint = '/test-settlement'
where p.project_key = 'agente-quant-bot';

-- WIN: stake 100, price 2.5 -> net_return = 100*(2.5-1) = 150; payout = 250 (SAQ-CC-V1 §14, entero).
select lives_ok(
  $$ insert into ops.settlements (project_id, execution_id, selection_id, market_contract_version_id, settlement_status, result_values, stake, price, payout, net_return, source_id, raw_payload_id, settled_at, settlement_hash)
     select p.project_id, (select execution_id from ops.executions limit 1), (select selection_id from market.selections where selection_key='test-selection-settlement'),
            (select market_contract_version_id from market.selections where selection_key='test-selection-settlement'),
            'WIN'::app.settlement_status, '{}'::jsonb, 100.00, 2.50, 250.00, 150.00, gen_random_uuid(),
            (select raw_payload_id from raw.payloads where content_sha256 = repeat('b4', 32)), clock_timestamp(), repeat('c1', 32)
     from cfg.projects p where p.project_key = 'agente-quant-bot' $$,
  'WIN: payoff entero exacto (150) es aceptado'
);

-- HALF_WIN (linea de cuarto, SAQ-CC-V1 §15): stake 100, price 2.0 -> net_return = 0.5*100*(2-1) = 50.
select lives_ok(
  $$ insert into ops.settlements (project_id, execution_id, selection_id, market_contract_version_id, settlement_status, result_values, stake, price, payout, net_return, source_id, raw_payload_id, settled_at, settlement_hash)
     select p.project_id, (select execution_id from ops.executions limit 1), (select selection_id from market.selections where selection_key='test-selection-settlement'),
            (select market_contract_version_id from market.selections where selection_key='test-selection-settlement'),
            'HALF_WIN'::app.settlement_status, '{}'::jsonb, 100.00, 2.00, 150.00, 50.00, gen_random_uuid(),
            (select raw_payload_id from raw.payloads where content_sha256 = repeat('b4', 32)), clock_timestamp(), repeat('c2', 32)
     from cfg.projects p where p.project_key = 'agente-quant-bot' $$,
  'HALF_WIN: payoff de linea de cuarto (50) es aceptado'
);

-- PUSH: net_return = 0; payout = stake.
select lives_ok(
  $$ insert into ops.settlements (project_id, execution_id, selection_id, market_contract_version_id, settlement_status, result_values, stake, price, payout, net_return, source_id, raw_payload_id, settled_at, settlement_hash)
     select p.project_id, (select execution_id from ops.executions limit 1), (select selection_id from market.selections where selection_key='test-selection-settlement'),
            (select market_contract_version_id from market.selections where selection_key='test-selection-settlement'),
            'PUSH'::app.settlement_status, '{}'::jsonb, 100.00, 2.00, 100.00, 0.00, gen_random_uuid(),
            (select raw_payload_id from raw.payloads where content_sha256 = repeat('b4', 32)), clock_timestamp(), repeat('c3', 32)
     from cfg.projects p where p.project_key = 'agente-quant-bot' $$,
  'PUSH: net_return 0 es aceptado'
);

-- HALF_LOSS: net_return = -0.5*stake = -50.
select lives_ok(
  $$ insert into ops.settlements (project_id, execution_id, selection_id, market_contract_version_id, settlement_status, result_values, stake, price, payout, net_return, source_id, raw_payload_id, settled_at, settlement_hash)
     select p.project_id, (select execution_id from ops.executions limit 1), (select selection_id from market.selections where selection_key='test-selection-settlement'),
            (select market_contract_version_id from market.selections where selection_key='test-selection-settlement'),
            'HALF_LOSS'::app.settlement_status, '{}'::jsonb, 100.00, 2.00, 50.00, -50.00, gen_random_uuid(),
            (select raw_payload_id from raw.payloads where content_sha256 = repeat('b4', 32)), clock_timestamp(), repeat('c4', 32)
     from cfg.projects p where p.project_key = 'agente-quant-bot' $$,
  'HALF_LOSS: payoff de media linea (-50) es aceptado'
);

-- LOSS: net_return = -stake.
select lives_ok(
  $$ insert into ops.settlements (project_id, execution_id, selection_id, market_contract_version_id, settlement_status, result_values, stake, price, payout, net_return, source_id, raw_payload_id, settled_at, settlement_hash)
     select p.project_id, (select execution_id from ops.executions limit 1), (select selection_id from market.selections where selection_key='test-selection-settlement'),
            (select market_contract_version_id from market.selections where selection_key='test-selection-settlement'),
            'LOSS'::app.settlement_status, '{}'::jsonb, 100.00, 2.00, 0.00, -100.00, gen_random_uuid(),
            (select raw_payload_id from raw.payloads where content_sha256 = repeat('b4', 32)), clock_timestamp(), repeat('c5', 32)
     from cfg.projects p where p.project_key = 'agente-quant-bot' $$,
  'LOSS: net_return = -stake es aceptado'
);

-- VOID: net_return = 0.
select lives_ok(
  $$ insert into ops.settlements (project_id, execution_id, selection_id, market_contract_version_id, settlement_status, result_values, stake, price, payout, net_return, source_id, raw_payload_id, settled_at, settlement_hash)
     select p.project_id, (select execution_id from ops.executions limit 1), (select selection_id from market.selections where selection_key='test-selection-settlement'),
            (select market_contract_version_id from market.selections where selection_key='test-selection-settlement'),
            'VOID'::app.settlement_status, '{}'::jsonb, 100.00, 2.00, 100.00, 0.00, gen_random_uuid(),
            (select raw_payload_id from raw.payloads where content_sha256 = repeat('b4', 32)), clock_timestamp(), repeat('c6', 32)
     from cfg.projects p where p.project_key = 'agente-quant-bot' $$,
  'VOID: net_return 0 es aceptado'
);

-- Payoff declarado incorrecto: rechazado (WIN con net_return erroneo).
select throws_ok(
  $$ insert into ops.settlements (project_id, execution_id, selection_id, market_contract_version_id, settlement_status, result_values, stake, price, payout, net_return, source_id, raw_payload_id, settled_at, settlement_hash)
     select p.project_id, (select execution_id from ops.executions limit 1), (select selection_id from market.selections where selection_key='test-selection-settlement'),
            (select market_contract_version_id from market.selections where selection_key='test-selection-settlement'),
            'WIN'::app.settlement_status, '{}'::jsonb, 100.00, 2.50, 999.00, 999.00, gen_random_uuid(),
            (select raw_payload_id from raw.payloads where content_sha256 = repeat('b4', 32)), clock_timestamp(), repeat('c7', 32)
     from cfg.projects p where p.project_key = 'agente-quant-bot' $$,
  null, 'WIN con net_return incorrecto (999 en vez de 150) es rechazado'
);

select * from finish();
rollback;
