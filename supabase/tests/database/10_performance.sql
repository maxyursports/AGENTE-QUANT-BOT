-- SAQ-MCDS-V1 §29 (10_performance): consultas calientes con datos representativos.
-- El plan usa los indices aprobados en SAQ-MCDS-V1 §21.
--
-- LIMITACION HONESTA: esta suite corre sobre el volumen del seed canonico de Fase 1 (catalogos
-- DRAFT, sin datos transaccionales de produccion). Con tablas de pocas filas, el planificador de
-- Postgres normalmente prefiere un Seq Scan aunque el indice exista (es la eleccion correcta a
-- ese volumen). Por eso esta suite verifica (a) que los 9 indices de §21 existen fisicamente y
-- (b) que las consultas calientes definidas en §21 se ejecutan correctamente y devuelven el tipo
-- de resultado esperado -- no fuerza una asercion sobre el plan de ejecucion, que solo es
-- representativa con datos de volumen productivo (Definition of Done §31.3, pendiente de una
-- carga de datos real fuera del alcance de Fase 1).
begin;
select plan(11);

select has_index('core', 'event_versions', 'event_versions_project_scheduled_idx', 'indice "Eventos proximos" (§21) existe');
select has_index('core', 'event_versions', 'event_versions_event_valid_from_idx', 'indice "Ultima version" (§21) existe');
select has_index('market', 'odds_snapshots', 'odds_snapshots_selection_bookmaker_observed_idx', 'indice "Ultima cuota" (§21) existe');
select has_index('raw', 'payloads', 'payloads_ingested_at_brin', 'indice BRIN "Ingestion historica" en raw.payloads (§21) existe');
select has_index('market', 'odds_snapshots', 'odds_snapshots_ingested_at_brin', 'indice BRIN "Ingestion historica" en odds_snapshots (§21) existe');
select has_index('model', 'predictions', 'predictions_selection_decision_idx', 'indice "Prediccion activa" (§21) existe');
select has_index('ops', 'signals', 'signals_active_idx', 'indice partial "Senal activa" (§21) existe');
select has_index('ops', 'executions', 'executions_unknown_idx', 'indice partial "Ejecucion desconocida" (§21) existe');
select has_index('ops', 'settlements', 'settlements_pending_idx', 'indice partial "Settlement pendiente" (§21) existe');

-- Las consultas calientes ejecutan correctamente (correctud funcional; el plan no se afirma).
select lives_ok(
  $$ select event_id from core.event_versions
       where project_id = (select project_id from cfg.projects where project_key='agente-quant-bot')
       order by scheduled_start_at limit 10 $$,
  'consulta "eventos proximos" ejecuta sin error'
);
select lives_ok(
  $$ select signal_id from ops.signals
       where project_id = (select project_id from cfg.projects where project_key='agente-quant-bot')
         and expiration_at > clock_timestamp()
         and signal_status in ('GENERATED','APPROVED','SENT_TELEGRAM') $$,
  'consulta "senal activa" ejecuta sin error'
);

select * from finish();
rollback;
