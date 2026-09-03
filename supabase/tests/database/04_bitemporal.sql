-- SAQ-MCDS-V1 §29 (04_bitemporal): available_for_model_at y decision_at.
-- Leakage rechazado (SAQ-CC-V1 §10); el registro del DataQualityEvent es responsabilidad de la
-- capa de servicio, no del trigger (SAQ-MCDS-V1.1-APPROVED §4.5 instancia 16) -- se verifica que
-- la transaccion completa (incluido cualquier intento de auditoria dentro de ella) se revierte.
begin;
select plan(5);

insert into core.events (project_id, sport_id, competition_id, identity_status, candidate_fingerprint)
select p.project_id, s.sport_id, c.competition_id, 'VALIDATED', repeat('3', 64)
from cfg.projects p join cfg.sports s on s.project_id = p.project_id
join core.competitions c on c.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;

insert into market.selections (project_id, event_id, market_contract_version_id, outcome_side, selection_key)
select p.project_id, ev.event_id, mcv.market_contract_version_id, 'HOME', 'test-selection-bitemporal'
from cfg.projects p
join core.events ev on ev.project_id = p.project_id
join cfg.market_contracts mc on mc.project_id = p.project_id and mc.contract_key = 'FT_1X2'
join cfg.market_contract_versions mcv on mcv.market_contract_id = mc.market_contract_id
where p.project_key = 'agente-quant-bot' limit 1;

insert into cfg.model_registry (project_id, sport_id, model_key, display_name, current_stage, health_status, owner)
select p.project_id, s.sport_id, 'test_model_bitemporal', 'Test Model', 'RESEARCH'::app.model_stage, 'HEALTHY'::app.model_health, 'qa'
from cfg.projects p join cfg.sports s on s.project_id = p.project_id where p.project_key = 'agente-quant-bot';

-- model_run con data_cutoff_at = 2026-01-01 12:00.
insert into model.model_runs (project_id, model_id, model_version, code_commit_sha, config_hash, data_cutoff_at, stage, health_status, started_at, run_status)
select p.project_id, mr.model_id, '0.1.0', repeat('4', 40), repeat('5', 64), '2026-01-01 12:00:00+00', 'RESEARCH'::app.model_stage, 'HEALTHY'::app.model_health, clock_timestamp(), 'SUCCEEDED'
from cfg.projects p join cfg.model_registry mr on mr.project_id = p.project_id and mr.model_key = 'test_model_bitemporal'
where p.project_key = 'agente-quant-bot';

-- feature_snapshot con as_of_at = available_for_model_at = 2026-01-01 12:00.
insert into model.feature_snapshots (project_id, event_id, feature_set_version, as_of_at, available_for_model_at, values, lineage, completeness, quality_status, snapshot_hash)
select p.project_id, ev.event_id, 'v1', '2026-01-01 12:00:00+00', '2026-01-01 12:00:00+00', '{}'::jsonb, '{}'::jsonb, 1.0, 'AVAILABLE'::app.data_quality_status, repeat('6', 64)
from cfg.projects p join core.events ev on ev.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;

-- decision_at POSTERIOR al cutoff/as_of: pasa el temporal gate.
select lives_ok(
  $$ insert into model.predictions (project_id, model_run_id, feature_snapshot_id, selection_id, predictive_distribution, fair_price, uncertainty, robust_ev, decision_at, expires_at, prediction_status, prediction_fingerprint)
     select p.project_id,
            (select model_run_id from model.model_runs where config_hash = repeat('5', 64)),
            (select feature_snapshot_id from model.feature_snapshots where snapshot_hash = repeat('6', 64)),
            (select selection_id from market.selections where selection_key = 'test-selection-bitemporal'),
            '{}'::jsonb, 2.10, '{}'::jsonb, 0.05, '2026-01-01 12:05:00+00', '2026-01-01 13:00:00+00', 'CREATED'::app.prediction_status, repeat('7', 64)
     from cfg.projects p where p.project_key = 'agente-quant-bot' $$,
  'decision_at posterior a data_cutoff_at/as_of_at pasa el temporal gate'
);

select is((select count(*)::int from model.predictions where prediction_fingerprint = repeat('7', 64)), 1,
  'la prediccion valida quedo persistida');

-- decision_at ANTERIOR al cutoff/as_of: viola el temporal gate (leakage).
select throws_ok(
  $$ insert into model.predictions (project_id, model_run_id, feature_snapshot_id, selection_id, predictive_distribution, fair_price, uncertainty, robust_ev, decision_at, expires_at, prediction_status, prediction_fingerprint)
     select p.project_id,
            (select model_run_id from model.model_runs where config_hash = repeat('5', 64)),
            (select feature_snapshot_id from model.feature_snapshots where snapshot_hash = repeat('6', 64)),
            (select selection_id from market.selections where selection_key = 'test-selection-bitemporal'),
            '{}'::jsonb, 2.10, '{}'::jsonb, 0.05, '2026-01-01 11:00:00+00', '2026-01-01 13:00:00+00', 'CREATED'::app.prediction_status, repeat('8', 64)
     from cfg.projects p where p.project_key = 'agente-quant-bot' $$,
  null, 'decision_at anterior al cutoff/as_of es rechazado (leakage risk)'
);

select is((select count(*)::int from model.predictions where prediction_fingerprint = repeat('8', 64)), 0,
  'la prediccion con leakage NO quedo persistida (rollback completo de la transaccion fallida)');

select is((select count(*)::int from ops.data_quality_events where issue_type = 'LEAKAGE_RISK'), 0,
  'ningun DataQualityEvent(LEAKAGE_RISK) quedo persistido por el trigger (responsabilidad de la capa de servicio, SAQ-MCDS-V1.1-APPROVED §4.5)');

select * from finish();
rollback;
