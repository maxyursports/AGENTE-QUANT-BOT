-- SAQ-MCDS-V1 §21 + indices "Índices:" de cada tabla (Partes IV-VI) · 0010_indexes
-- B-tree, partial y BRIN definidos en V1. Los indices que respaldan PK/UNIQUE/EXCLUDE
-- se crean junto a su tabla (0003-0008); este archivo contiene exclusivamente los indices
-- de consulta/lookup adicionales. No se indexa JSONB completo por defecto (§21).

-- cfg
create index projects_status_idx on cfg.projects (status);
create index project_members_user_status_idx on cfg.project_members (user_id, status);
create index project_members_project_role_idx on cfg.project_members (project_id, member_role);
create index data_sources_project_enabled_idx on cfg.data_sources (project_id, enabled);
create index sports_project_status_research_idx on cfg.sports (project_id, status, research_mode);
create index market_contracts_project_sport_family_status_idx
  on cfg.market_contracts (project_id, sport_id, market_family, status);
create index market_contract_versions_contract_active_idx
  on cfg.market_contract_versions (market_contract_id, active_from desc);
create index model_registry_project_sport_stage_health_idx
  on cfg.model_registry (project_id, sport_id, current_stage, health_status);
create index policy_versions_project_key_active_idx
  on cfg.policy_versions (project_id, policy_key, active_from desc);

-- raw
create index api_requests_project_source_requested_idx
  on raw.api_requests (project_id, data_source_id, requested_at desc);
create index api_requests_requested_at_brin on raw.api_requests using brin (requested_at);
create index payloads_project_request_idx on raw.payloads (project_id, request_id);
create index payloads_available_for_model_idx on raw.payloads (available_for_model_at);
-- "Ingestion historica" (§21): BRIN para rangos temporales grandes en raw.payloads y odds_snapshots.
create index payloads_ingested_at_brin on raw.payloads using brin (ingested_at);
create index payloads_content_sha256_idx on raw.payloads using hash (content_sha256);

-- core
-- "Eventos proximos" / "Ultima version" (§21).
create index event_versions_project_scheduled_idx on core.event_versions (project_id, scheduled_start_at);
create index event_versions_event_valid_from_idx on core.event_versions (event_id, valid_from desc);
create index event_versions_recorded_at_brin on core.event_versions using brin (recorded_at);
create index competitions_project_sport_status_idx on core.competitions (project_id, sport_id, status);
create index seasons_project_competition_status_idx on core.seasons (project_id, competition_id, status);
create index participants_project_sport_type_status_idx
  on core.participants (project_id, sport_id, participant_type, status);
create index sem_source_entity_idx on core.source_entity_mappings (data_source_id, entity_type, source_entity_id);
create index sem_canonical_entity_idx on core.source_entity_mappings (canonical_entity_id);
create index events_project_competition_season_idx on core.events (project_id, competition_id, season_id);
create index events_candidate_fingerprint_idx on core.events (candidate_fingerprint);
create index events_validated_idx on core.events (project_id) where identity_status = 'VALIDATED';

-- market
create index bookmakers_project_role_status_idx on market.bookmakers (project_id, role, status);
create index bookmakers_independence_group_idx on market.bookmakers (independence_group);
create index selections_event_contract_version_idx
  on market.selections (event_id, market_contract_version_id);
create index selections_project_participant_idx on market.selections (project_id, participant_id);
-- "Ultima cuota" (§21).
create index odds_snapshots_selection_bookmaker_observed_idx
  on market.odds_snapshots (selection_id, bookmaker_id, source_observed_at desc);
create index odds_snapshots_ingested_at_brin on market.odds_snapshots using brin (ingested_at);
create index consensus_snapshots_selection_calculated_idx
  on market.consensus_snapshots (selection_id, calculated_at desc);
create index consensus_snapshots_project_quality_idx
  on market.consensus_snapshots (project_id, quality_status);
create index consensus_components_odds_snapshot_idx on market.consensus_components (odds_snapshot_id);
create index consensus_components_included_idx
  on market.consensus_components (consensus_snapshot_id) where included = true;
create index closing_lines_selection_type_recorded_idx
  on market.closing_lines (selection_id, close_type, recorded_at desc);

-- model
create index feature_snapshots_event_as_of_idx on model.feature_snapshots (event_id, as_of_at desc);
create index model_runs_model_started_idx on model.model_runs (model_id, started_at desc);
create index model_runs_project_status_idx on model.model_runs (project_id, run_status);
-- "Prediccion activa" (§21).
create index predictions_selection_decision_idx on model.predictions (selection_id, decision_at desc);
create index predictions_model_run_idx on model.predictions (model_run_id);
create index predictions_validated_idx on model.predictions (project_id) where prediction_status = 'VALIDATED';
create index evaluation_runs_model_type_started_idx
  on model.evaluation_runs (model_id, evaluation_type, started_at desc);
create index evaluation_runs_project_status_idx on model.evaluation_runs (project_id, status);
create index metric_results_run_name_idx on model.metric_results (evaluation_run_id, metric_name);

-- ops
-- "Senal activa" (§21).
create index signals_project_status_generated_idx on ops.signals (project_id, signal_status, generated_at desc);
create index signals_active_idx on ops.signals (project_id, expiration_at)
  where signal_status in ('GENERATED','APPROVED','SENT_TELEGRAM');
create index signal_deliveries_signal_attempt_idx on ops.signal_deliveries (signal_id, attempt_no);
create index signal_deliveries_project_status_sent_idx
  on ops.signal_deliveries (project_id, delivery_status, sent_at desc);
create index executions_signal_idx on ops.executions (signal_id);
create index executions_project_status_attempted_idx
  on ops.executions (project_id, execution_status, attempted_at desc);
-- "Ejecucion desconocida" (§21).
create index executions_unknown_idx on ops.executions (project_id, attempted_at desc)
  where execution_status = 'UNKNOWN';
create index execution_events_execution_event_at_idx on ops.execution_events (execution_id, event_at);
create index execution_events_event_at_brin on ops.execution_events using brin (event_at);
create index settlements_execution_settled_idx on ops.settlements (execution_id, settled_at desc);
create index settlements_project_status_idx on ops.settlements (project_id, settlement_status);
create index settlements_settled_at_brin on ops.settlements using brin (settled_at);
-- "Settlement pendiente" (§21).
create index settlements_pending_idx on ops.settlements (project_id, settled_at)
  where settlement_status in ('PENDING','UNKNOWN','DISPUTED');
create index bankroll_ledger_project_effective_idx on ops.bankroll_ledger (project_id, effective_at);
create index bankroll_ledger_execution_idx on ops.bankroll_ledger (execution_id);
create index bankroll_ledger_settlement_idx on ops.bankroll_ledger (settlement_id);
create index portfolio_exposures_signal_idx on ops.portfolio_exposures (signal_id);
create index portfolio_exposures_project_as_of_gate_idx
  on ops.portfolio_exposures (project_id, as_of_at desc, gate_status);
create index data_quality_events_project_status_detected_idx
  on ops.data_quality_events (project_id, quality_status, detected_at desc);
create index data_quality_events_entity_idx on ops.data_quality_events (entity_table, entity_id);
create index audit_events_project_created_idx on ops.audit_events (project_id, created_at desc);
create index audit_events_entity_idx on ops.audit_events (entity_table, entity_id);
