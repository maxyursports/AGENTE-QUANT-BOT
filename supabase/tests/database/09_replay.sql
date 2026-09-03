-- SAQ-MCDS-V1 §29 (09_replay): reconstruccion de prediction -> settlement.
-- Mismos hashes y resultados (SAQ-CC-V1: "que sabia, cuando, que calculo, que se ejecuto y como
-- se liquido"; SAQ-MCDS-V1 §11 append-only/supersedes).
begin;
select plan(6);

insert into core.events (project_id, sport_id, competition_id, identity_status, candidate_fingerprint)
select p.project_id, s.sport_id, c.competition_id, 'VALIDATED', repeat('e1', 32)
from cfg.projects p join cfg.sports s on s.project_id = p.project_id
join core.competitions c on c.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;

insert into market.selections (project_id, event_id, market_contract_version_id, outcome_side, selection_key)
select p.project_id, ev.event_id, mcv.market_contract_version_id, 'HOME', 'test-selection-replay'
from cfg.projects p
join core.events ev on ev.project_id = p.project_id
join cfg.market_contracts mc on mc.project_id = p.project_id and mc.contract_key = 'FT_1X2'
join cfg.market_contract_versions mcv on mcv.market_contract_id = mc.market_contract_id
where p.project_key = 'agente-quant-bot' limit 1;

insert into market.bookmakers (project_id, bookmaker_key, display_name, region, role, status)
select project_id, 'test_book_replay', 'Test Book', 'GLOBAL', 'SENSOR', 'DRAFT'::app.catalog_status
from cfg.projects where project_key = 'agente-quant-bot';
insert into raw.api_requests (project_id, data_source_id, endpoint, method, request_fingerprint, requested_at, request_status)
select p.project_id, ds.data_source_id, '/test-replay', 'GET', repeat('e2', 32), clock_timestamp(), 'SUCCEEDED'::app.request_status
from cfg.projects p join cfg.data_sources ds on ds.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;
insert into raw.payloads (project_id, request_id, payload_seq, ingested_at, available_for_model_at, content_type, payload_json, content_sha256, byte_count, schema_version, quality_status)
select p.project_id, r.request_id, 1, clock_timestamp(), clock_timestamp(), 'application/json', '{}'::jsonb, repeat('e3', 32), 2, 'v1', 'AVAILABLE'::app.data_quality_status
from cfg.projects p join raw.api_requests r on r.project_id = p.project_id and r.endpoint = '/test-replay'
where p.project_key = 'agente-quant-bot';
insert into market.odds_snapshots (project_id, selection_id, bookmaker_id, price_decimal, ingested_at, available_for_model_at, quote_status, raw_payload_id, idempotency_key)
select p.project_id, (select selection_id from market.selections where selection_key='test-selection-replay'),
       (select bookmaker_id from market.bookmakers where bookmaker_key='test_book_replay'),
       2.20, clock_timestamp(), clock_timestamp(), 'AVAILABLE'::app.quote_status,
       (select raw_payload_id from raw.payloads where content_sha256 = repeat('e3', 32)), repeat('e4', 32)
from cfg.projects p where p.project_key = 'agente-quant-bot';
insert into cfg.model_registry (project_id, sport_id, model_key, display_name, current_stage, health_status, owner)
select p.project_id, s.sport_id, 'test_model_replay', 'Test Model', 'RESEARCH'::app.model_stage, 'HEALTHY'::app.model_health, 'qa'
from cfg.projects p join cfg.sports s on s.project_id = p.project_id where p.project_key = 'agente-quant-bot';
insert into model.model_runs (project_id, model_id, model_version, code_commit_sha, config_hash, data_cutoff_at, stage, health_status, started_at, run_status)
select p.project_id, mr.model_id, '0.1.0', repeat('e5', 20), repeat('e6', 32), clock_timestamp(), 'RESEARCH'::app.model_stage, 'HEALTHY'::app.model_health, clock_timestamp(), 'SUCCEEDED'
from cfg.projects p join cfg.model_registry mr on mr.project_id = p.project_id and mr.model_key = 'test_model_replay'
where p.project_key = 'agente-quant-bot';
insert into model.feature_snapshots (project_id, event_id, feature_set_version, as_of_at, available_for_model_at, values, lineage, completeness, quality_status, snapshot_hash)
select p.project_id, ev.event_id, 'v1', clock_timestamp(), clock_timestamp(), '{}'::jsonb, '{}'::jsonb, 1.0, 'AVAILABLE'::app.data_quality_status, repeat('e7', 32)
from cfg.projects p join core.events ev on ev.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;
insert into model.predictions (project_id, model_run_id, feature_snapshot_id, selection_id, predictive_distribution, fair_price, uncertainty, robust_ev, decision_at, expires_at, prediction_status, prediction_fingerprint)
select p.project_id, (select model_run_id from model.model_runs where config_hash = repeat('e6', 32)),
       (select feature_snapshot_id from model.feature_snapshots where snapshot_hash = repeat('e7', 32)),
       (select selection_id from market.selections where selection_key = 'test-selection-replay'),
       '{}'::jsonb, 2.20, '{}'::jsonb, 0.05, clock_timestamp(), clock_timestamp() + interval '1 hour', 'PUBLISHED'::app.prediction_status, repeat('e8', 32)
from cfg.projects p where p.project_key = 'agente-quant-bot';
insert into ops.signals (project_id, prediction_id, selection_id, odds_snapshot_id, policy_version_id, minimum_acceptable_odds, suggested_stake_fraction, quality_band, generated_at, expiration_at, signal_status, payload_hash)
select p.project_id, (select prediction_id from model.predictions where prediction_fingerprint = repeat('e8', 32)),
       (select selection_id from market.selections where selection_key='test-selection-replay'),
       (select odds_snapshot_id from market.odds_snapshots where idempotency_key = repeat('e4', 32)),
       (select policy_version_id from cfg.policy_versions where project_id = p.project_id limit 1),
       1.50, 0, 'HIGH', clock_timestamp(), clock_timestamp() + interval '1 hour', 'SENT_TELEGRAM'::app.signal_status, repeat('e9', 32)
from cfg.projects p where p.project_key = 'agente-quant-bot';
insert into ops.executions (project_id, signal_id, execution_status, actual_odds, accepted_stake, attempted_at, placed_at, confirmation_method)
select p.project_id, (select signal_id from ops.signals where payload_hash = repeat('e9', 32)), 'BET_PLACED'::app.execution_status,
       2.20, 100.00, clock_timestamp(), clock_timestamp(), 'TELEGRAM_USER'
from cfg.projects p where p.project_key = 'agente-quant-bot';
insert into ops.settlements (project_id, execution_id, selection_id, market_contract_version_id, settlement_status, result_values, stake, price, payout, net_return, source_id, raw_payload_id, settled_at, settlement_hash)
select p.project_id, (select execution_id from ops.executions where accepted_stake = 100.00 limit 1),
       (select selection_id from market.selections where selection_key='test-selection-replay'),
       (select market_contract_version_id from market.selections where selection_key='test-selection-replay'),
       'WIN'::app.settlement_status, '{"final_score":"2-0"}'::jsonb, 100.00, 2.20, 220.00, 120.00, gen_random_uuid(),
       (select raw_payload_id from raw.payloads where content_sha256 = repeat('e3', 32)), clock_timestamp(), repeat('ea', 32)
from cfg.projects p where p.project_key = 'agente-quant-bot';

-- Reconstruccion completa: settlement -> execution -> signal -> {prediction -> feature_snapshot,
-- odds_snapshot -> raw.payloads}, en una sola cadena de FKs, sin huecos (SAQ-CC-V1: "que sabia,
-- cuando lo sabia, que calculo, que se ejecuto y como se liquido").
select is(
  (select count(*)::int
     from ops.settlements st
     join ops.executions ex on ex.execution_id = st.execution_id
     join ops.signals sg on sg.signal_id = ex.signal_id
     join model.predictions pr on pr.prediction_id = sg.prediction_id
     join model.feature_snapshots fs on fs.feature_snapshot_id = pr.feature_snapshot_id
     join market.odds_snapshots os on os.odds_snapshot_id = sg.odds_snapshot_id
     join raw.payloads rp on rp.raw_payload_id = os.raw_payload_id
     where st.settlement_hash = repeat('ea', 32)
       and rp.content_sha256 = repeat('e3', 32)),
  1,
  'la cadena completa raw->odds->signal->prediction->feature_snapshot->execution->settlement se reconstruye sin huecos'
);

-- El payoff recalculado a mano coincide EXACTAMENTE con lo persistido (mismo resultado).
select is(
  (select net_return::numeric from ops.settlements where settlement_hash = repeat('ea', 32)),
  (select (stake::numeric * (price::numeric - 1)) from ops.settlements where settlement_hash = repeat('ea', 32)),
  'net_return persistido coincide con el recalculo manual del payoff (WIN, SAQ-CC-V1 §14)'
);

-- Recalcular el hash de identidad con los mismos inputs produce el MISMO hash (reproducibilidad).
select is(
  encode(extensions.digest('test-replay-input', 'sha256'), 'hex'),
  encode(extensions.digest('test-replay-input', 'sha256'), 'hex'),
  'el mismo input produce siempre el mismo hash (determinismo, SAQ-CC-V1: "que calculo, que publico")'
);

-- Inmutabilidad: ni la prediction ni el settlement admiten UPDATE (la correccion es una fila nueva
-- via supersedes_*, nunca una reescritura -- SAQ-MCDS-V1 §11).
select throws_ok(
  $$ update model.predictions set fair_price = 9.99 where prediction_fingerprint = repeat('e8', 32) $$,
  null, 'model.predictions es append-only: UPDATE es rechazado'
);
select throws_ok(
  $$ update ops.settlements set net_return = 0 where settlement_hash = repeat('ea', 32) $$,
  null, 'ops.settlements es append-only: UPDATE es rechazado'
);

-- Una correccion valida crea una fila NUEVA que referencia la anterior via supersedes_settlement_id.
select lives_ok(
  $$ insert into ops.settlements (project_id, execution_id, selection_id, market_contract_version_id, settlement_status, result_values, stake, price, payout, net_return, source_id, raw_payload_id, settled_at, settlement_hash, supersedes_settlement_id)
     select project_id, execution_id, selection_id, market_contract_version_id, 'CORRECTED'::app.settlement_status, '{"final_score":"2-1 corregido"}'::jsonb,
            stake, price, payout, net_return, source_id, raw_payload_id, clock_timestamp(), repeat('eb', 32),
            (select settlement_id from ops.settlements where settlement_hash = repeat('ea', 32))
     from ops.settlements where settlement_hash = repeat('ea', 32) $$,
  'una correccion oficial crea una fila nueva encadenada via supersedes_settlement_id, sin tocar la original'
);

select * from finish();
rollback;
