-- SAQ-MCDS-V1 §11, §19, §24-27 · 0011_rls_and_grants
-- Revocacion por defecto, RLS, policies y roles (Apendice B.1/B.3).

-- Revocacion por defecto (Apendice B.1). public no contiene tablas de negocio.
revoke all on schema public from anon, authenticated;
alter default privileges for role postgres revoke all on tables from anon, authenticated;

-- Uso de esquemas. app/cfg/raw/core/market/model/ops son "Privado" en el sentido de §6
-- (nunca se agregan a Exposed schemas de la Data API); el grant de USAGE + SELECT que sigue
-- es el que permite que las views api (security_invoker=true) y las RPC (security invoker por
-- defecto, §26) operen correctamente como el rol authenticated -- sin el, security_invoker no
-- tendria nada que heredar y toda consulta a la superficie api fallaria por permisos.
grant usage on schema app, cfg, raw, core, market, model, ops to authenticated;
grant usage on schema app, cfg, raw, core, market, model, ops, api to service_role;
grant usage on schema api to authenticated;

-- RLS: enable + force + policy de lectura por membership ACTIVE (SAQ-MCDS-V1 §24, Apendice B.3).
-- Las 36 tablas de negocio comparten el mismo predicado: cualquier rol de proyecto (VIEWER,
-- ANALYST, OPERATOR, OWNER) con membership ACTIVE puede leer filas de su project_id; ningun
-- documento adjunto especifica una matriz de lectura mas fina por schema/tabla y rol, por lo
-- que no se inventa una (decision documentada en el informe final).

alter table cfg.projects enable row level security;
alter table cfg.projects force row level security;
create policy projects_select_member on cfg.projects
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table cfg.project_members enable row level security;
alter table cfg.project_members force row level security;
create policy project_members_select_member on cfg.project_members
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table cfg.data_sources enable row level security;
alter table cfg.data_sources force row level security;
create policy data_sources_select_member on cfg.data_sources
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table cfg.sports enable row level security;
alter table cfg.sports force row level security;
create policy sports_select_member on cfg.sports
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table cfg.market_contracts enable row level security;
alter table cfg.market_contracts force row level security;
create policy market_contracts_select_member on cfg.market_contracts
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table cfg.market_contract_versions enable row level security;
alter table cfg.market_contract_versions force row level security;
create policy market_contract_versions_select_member on cfg.market_contract_versions
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table cfg.model_registry enable row level security;
alter table cfg.model_registry force row level security;
create policy model_registry_select_member on cfg.model_registry
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table cfg.policy_versions enable row level security;
alter table cfg.policy_versions force row level security;
create policy policy_versions_select_member on cfg.policy_versions
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table raw.api_requests enable row level security;
alter table raw.api_requests force row level security;
create policy api_requests_select_member on raw.api_requests
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table raw.payloads enable row level security;
alter table raw.payloads force row level security;
create policy payloads_select_member on raw.payloads
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table core.competitions enable row level security;
alter table core.competitions force row level security;
create policy competitions_select_member on core.competitions
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table core.seasons enable row level security;
alter table core.seasons force row level security;
create policy seasons_select_member on core.seasons
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table core.participants enable row level security;
alter table core.participants force row level security;
create policy participants_select_member on core.participants
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table core.source_entity_mappings enable row level security;
alter table core.source_entity_mappings force row level security;
create policy source_entity_mappings_select_member on core.source_entity_mappings
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table core.events enable row level security;
alter table core.events force row level security;
create policy events_select_member on core.events
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table core.event_versions enable row level security;
alter table core.event_versions force row level security;
create policy event_versions_select_member on core.event_versions
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table market.bookmakers enable row level security;
alter table market.bookmakers force row level security;
create policy bookmakers_select_member on market.bookmakers
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table market.selections enable row level security;
alter table market.selections force row level security;
create policy selections_select_member on market.selections
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table market.odds_snapshots enable row level security;
alter table market.odds_snapshots force row level security;
create policy odds_snapshots_select_member on market.odds_snapshots
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table market.consensus_snapshots enable row level security;
alter table market.consensus_snapshots force row level security;
create policy consensus_snapshots_select_member on market.consensus_snapshots
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

-- market.consensus_components es tabla puente sin project_id propio (SAQ-MCDS-V1 §8: "salvo
-- ... tablas puente cuya PK ya lo contiene" no aplica aqui porque su PK tampoco lo contiene;
-- se resuelve el project_id via consensus_snapshot_id, unica FK no nula de la fila).
alter table market.consensus_components enable row level security;
alter table market.consensus_components force row level security;
create policy consensus_components_select_member on market.consensus_components
  for select to authenticated
  using (
    app.has_project_role(
      (select cs.project_id from market.consensus_snapshots cs where cs.consensus_snapshot_id = consensus_components.consensus_snapshot_id),
      array['VIEWER','ANALYST','OPERATOR','OWNER']
    )
  );

alter table market.closing_lines enable row level security;
alter table market.closing_lines force row level security;
create policy closing_lines_select_member on market.closing_lines
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table model.feature_snapshots enable row level security;
alter table model.feature_snapshots force row level security;
create policy feature_snapshots_select_member on model.feature_snapshots
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table model.model_runs enable row level security;
alter table model.model_runs force row level security;
create policy model_runs_select_member on model.model_runs
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table model.predictions enable row level security;
alter table model.predictions force row level security;
create policy predictions_select_member on model.predictions
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table model.evaluation_runs enable row level security;
alter table model.evaluation_runs force row level security;
create policy evaluation_runs_select_member on model.evaluation_runs
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table model.metric_results enable row level security;
alter table model.metric_results force row level security;
create policy metric_results_select_member on model.metric_results
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table ops.signals enable row level security;
alter table ops.signals force row level security;
create policy signals_select_member on ops.signals
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table ops.signal_deliveries enable row level security;
alter table ops.signal_deliveries force row level security;
create policy signal_deliveries_select_member on ops.signal_deliveries
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table ops.executions enable row level security;
alter table ops.executions force row level security;
create policy executions_select_member on ops.executions
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table ops.execution_events enable row level security;
alter table ops.execution_events force row level security;
create policy execution_events_select_member on ops.execution_events
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table ops.settlements enable row level security;
alter table ops.settlements force row level security;
create policy settlements_select_member on ops.settlements
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table ops.bankroll_ledger enable row level security;
alter table ops.bankroll_ledger force row level security;
create policy bankroll_ledger_select_member on ops.bankroll_ledger
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table ops.portfolio_exposures enable row level security;
alter table ops.portfolio_exposures force row level security;
create policy portfolio_exposures_select_member on ops.portfolio_exposures
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table ops.data_quality_events enable row level security;
alter table ops.data_quality_events force row level security;
create policy data_quality_events_select_member on ops.data_quality_events
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

alter table ops.audit_events enable row level security;
alter table ops.audit_events force row level security;
create policy audit_events_select_member on ops.audit_events
  for select to authenticated
  using (app.has_project_role(project_id, array['VIEWER','ANALYST','OPERATOR','OWNER']));

-- Grants de tabla. authenticated: solo SELECT (gated por RLS arriba); ninguna mutacion directa
-- en ninguna de las 36 tablas de negocio salvo la superficie RPC explicita de la seccion final
-- (SAQ-MCDS-V1 §24: "Ninguna mutacion directa" para VIEWER/ANALYST/OPERATOR; OWNER solo via
-- "RPC administrativas aprobadas"). service_role: acceso completo de backend (BYPASSRLS ya
-- fijado en el rol); los triggers append-only siguen bloqueando UPDATE/DELETE incluso para
-- service_role, que es el comportamiento deseado (fail closed, SAQ-MCDS-V1 §20).
grant select on all tables in schema cfg, raw, core, market, model, ops to authenticated;
grant select, insert, update, delete on all tables in schema cfg, raw, core, market, model, ops to service_role;

-- Superficie de mutacion autorizada para authenticated: exclusivamente INSERT en ops.executions
-- y ops.execution_events, que es lo que las RPC SECURITY INVOKER api.confirm_execution y
-- api.mark_not_placed necesitan ejecutar corriendo como el usuario que las invoca (SAQ-MCDS-V1
-- §26: "Las RPC usan security invoker por defecto"). El resto de columnas/tablas de ops
-- permanecen sin mutacion directa para authenticated.
grant insert on ops.executions, ops.execution_events to authenticated;

-- api.confirm_execution ejecuta "SELECT ... FOR UPDATE" sobre ops.signals para bloquear la fila
-- durante la confirmacion (Apendice B, paso 2). PostgreSQL exige privilegio UPDATE en la tabla
-- para adquirir ese bloqueo de fila, aunque la RPC no modifique columnas de ops.signals; sin este
-- GRANT + policy, confirm_execution falla con permission denied para cualquier OPERATOR/OWNER.
grant update on ops.signals to authenticated;
create policy signals_lock_for_confirm on ops.signals
  for update to authenticated
  using (app.has_project_role(project_id, array['OPERATOR','OWNER']))
  with check (app.has_project_role(project_id, array['OPERATOR','OWNER']));

create policy executions_insert_operator on ops.executions
  for insert to authenticated
  with check (app.has_project_role(project_id, array['OPERATOR','OWNER']));

create policy execution_events_insert_operator on ops.execution_events
  for insert to authenticated
  with check (app.has_project_role(project_id, array['OPERATOR','OWNER']));

-- api.request_settlement_replay (RPC OWNER, SAQ-MCDS-V1 §25/§26) encola el pedido como un
-- ops.audit_events; ops.audit_events es append-only (no UPDATE/DELETE), pero admite INSERT.
grant insert on ops.audit_events to authenticated;

create policy audit_events_insert_owner on ops.audit_events
  for insert to authenticated
  with check (app.has_project_role(project_id, array['OWNER']));
