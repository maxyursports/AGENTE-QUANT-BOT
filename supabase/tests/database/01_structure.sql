SET search_path = extensions, public;
-- SAQ-MCDS-V1 §29 (01_structure): schemas, tablas, columnas, tipos, PK/FK/UQ.
-- 100% de objetos V1 presentes. Fuera del historial de migraciones aplicadas.
begin;
SET LOCAL ROLE postgres;
select extensions.plan(76);

-- 8 schemas logicos + api.
select extensions.has_schema('app', 'schema app existe');
select extensions.has_schema('cfg', 'schema cfg existe');
select extensions.has_schema('raw', 'schema raw existe');
select extensions.has_schema('core', 'schema core existe');
select extensions.has_schema('market', 'schema market existe');
select extensions.has_schema('model', 'schema model existe');
select extensions.has_schema('ops', 'schema ops existe');
select extensions.has_schema('api', 'schema api existe');

-- 36 tablas exactas (SAQ-MCDS-V1 Apendice A).
select extensions.has_table('cfg', 'projects', 'cfg.projects existe');
select extensions.has_table('cfg', 'project_members', 'cfg.project_members existe');
select extensions.has_table('cfg', 'data_sources', 'cfg.data_sources existe');
select extensions.has_table('cfg', 'sports', 'cfg.sports existe');
select extensions.has_table('cfg', 'market_contracts', 'cfg.market_contracts existe');
select extensions.has_table('cfg', 'market_contract_versions', 'cfg.market_contract_versions existe');
select extensions.has_table('cfg', 'model_registry', 'cfg.model_registry existe');
select extensions.has_table('cfg', 'policy_versions', 'cfg.policy_versions existe');
select extensions.has_table('raw', 'api_requests', 'raw.api_requests existe');
select extensions.has_table('raw', 'payloads', 'raw.payloads existe');
select extensions.has_table('core', 'competitions', 'core.competitions existe');
select extensions.has_table('core', 'seasons', 'core.seasons existe');
select extensions.has_table('core', 'participants', 'core.participants existe');
select extensions.has_table('core', 'source_entity_mappings', 'core.source_entity_mappings existe');
select extensions.has_table('core', 'events', 'core.events existe');
select extensions.has_table('core', 'event_versions', 'core.event_versions existe');
select extensions.has_table('market', 'bookmakers', 'market.bookmakers existe');
select extensions.has_table('market', 'selections', 'market.selections existe');
select extensions.has_table('market', 'odds_snapshots', 'market.odds_snapshots existe');
select extensions.has_table('market', 'consensus_snapshots', 'market.consensus_snapshots existe');
select extensions.has_table('market', 'consensus_components', 'market.consensus_components existe');
select extensions.has_table('market', 'closing_lines', 'market.closing_lines existe');
select extensions.has_table('model', 'feature_snapshots', 'model.feature_snapshots existe');
select extensions.has_table('model', 'model_runs', 'model.model_runs existe');
select extensions.has_table('model', 'predictions', 'model.predictions existe');
select extensions.has_table('model', 'evaluation_runs', 'model.evaluation_runs existe');
select extensions.has_table('model', 'metric_results', 'model.metric_results existe');
select extensions.has_table('ops', 'signals', 'ops.signals existe');
select extensions.has_table('ops', 'signal_deliveries', 'ops.signal_deliveries existe');
select extensions.has_table('ops', 'executions', 'ops.executions existe');
select extensions.has_table('ops', 'execution_events', 'ops.execution_events existe');
select extensions.has_table('ops', 'settlements', 'ops.settlements existe');
select extensions.has_table('ops', 'bankroll_ledger', 'ops.bankroll_ledger existe');
select extensions.has_table('ops', 'portfolio_exposures', 'ops.portfolio_exposures existe');
select extensions.has_table('ops', 'data_quality_events', 'ops.data_quality_events existe');
select extensions.has_table('ops', 'audit_events', 'ops.audit_events existe');

-- Conteo exacto de objetos V1 (SAQ-MCDS-V1.1-APPROVED §5/§6).
select extensions.is(
  (select count(*)::int from information_schema.tables
    where table_schema in ('cfg','raw','core','market','model','ops') and table_type = 'BASE TABLE'),
  36, 'exactamente 36 tablas de negocio'
);
select extensions.is((select count(*)::int from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'app' and t.typtype = 'e'), 15, 'exactamente 15 enums app.*');
select extensions.is((select count(*)::int from information_schema.views where table_schema = 'api'), 5, 'exactamente 5 views api.*');
select extensions.is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'api'), 4, 'exactamente 4 RPC api.*');
select extensions.is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app'), 15, 'exactamente 15 funciones app.*');
select extensions.is((select count(*)::int from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal and n.nspname in ('cfg','core','market','model','ops','raw')), 31, 'exactamente 31 instancias de trigger');

-- PK / UQ / FK representativos (uno por cada schema, no exhaustivo por brevedad de la suite).
select extensions.has_pk('cfg', 'projects', 'cfg.projects tiene PK');
select col_is_pk('cfg', 'projects', 'project_id', 'cfg.projects PK es project_id');
select extensions.has_pk('cfg', 'project_members', 'cfg.project_members tiene PK compuesta');
select col_is_pk('cfg', 'project_members', array['project_id','user_id'], 'PK compuesta correcta en cfg.project_members');
select extensions.has_fk('raw', 'payloads', 'raw.payloads tiene FK');
select col_is_fk('raw', 'payloads', 'request_id', 'raw.payloads.request_id es FK');
select extensions.has_fk('market', 'selections', 'market.selections tiene FK');
select extensions.has_fk('ops', 'executions', 'ops.executions tiene FK');

-- Tipos fisicos representativos (SAQ-MCDS-V1 §9), vehiculados via los dominios de app.* creados
-- en 0002_types_and_domains para reutilizacion (SAQ-IMPLEMENTATION-BOUNDARY-V1.1-APPROVED §28).
select extensions.col_type_is('market', 'odds_snapshots', 'price_decimal', 'app.price_t', 'price_decimal usa el dominio app.price_t');
select extensions.col_type_is('market', 'odds_snapshots', 'line', 'app.line_t', 'line usa el dominio app.line_t');
select extensions.col_type_is('model', 'predictions', 'model_probability', 'app.probability_t', 'model_probability usa el dominio app.probability_t');
select extensions.col_type_is('model', 'predictions', 'robust_ev', 'app.ev_t', 'robust_ev usa el dominio app.ev_t');
select extensions.col_type_is('ops', 'bankroll_ledger', 'amount', 'app.money_t', 'amount usa el dominio app.money_t');
select extensions.col_type_is('raw', 'payloads', 'content_sha256', 'app.hash_t', 'content_sha256 usa el dominio app.hash_t');
select extensions.is((select (domain_name, data_type, numeric_precision, numeric_scale) from information_schema.domains
             where domain_schema='app' and domain_name='price_t')::text,
          '(price_t,numeric,12,6)', 'app.price_t es numeric(12,6)');
select extensions.is((select (domain_name, data_type, character_maximum_length) from information_schema.domains
             where domain_schema='app' and domain_name='hash_t')::text,
          '(hash_t,character,64)', 'app.hash_t es char(64)');
select col_not_null('cfg', 'projects', 'project_key', 'project_key es NOT NULL');
select col_is_null('cfg', 'projects', 'retired_at', 'retired_at admite NULL');

-- Enums cerrados: valores exactos de execution_status y settlement_status.
select extensions.enum_has_labels('app', 'execution_status',
  array['UNKNOWN','NOT_PLACED','BET_PLACED','PARTIALLY_PLACED','ODDS_CHANGED','LINE_CHANGED',
        'MARKET_SUSPENDED','MARKET_CLOSED','REJECTED_BY_BOOK','LIMIT_REDUCED','ERROR'],
  'app.execution_status tiene exactamente los 11 valores V1');
select extensions.enum_has_labels('app', 'settlement_status',
  array['PENDING','WIN','HALF_WIN','PUSH','HALF_LOSS','LOSS','VOID','PARTIAL_VOID','UNKNOWN','DISPUTED','CORRECTED'],
  'app.settlement_status tiene exactamente los 11 valores V1');

-- Views api con security_invoker=true (SAQ-MCDS-V1 §25).
select extensions.ok(
  (select (reloptions::text[] @> array['security_invoker=true'])
     from pg_class where relname = 'v_active_signals' and relnamespace = 'api'::regnamespace),
  'api.v_active_signals tiene security_invoker=true'
);
select extensions.ok(
  (select (reloptions::text[] @> array['security_invoker=true'])
     from pg_class where relname = 'v_event_schedule' and relnamespace = 'api'::regnamespace),
  'api.v_event_schedule tiene security_invoker=true'
);

-- RLS habilitada y forzada en tablas representativas de cada schema.
select extensions.ok((select relrowsecurity from pg_class where oid = 'cfg.projects'::regclass), 'RLS habilitada en cfg.projects');
select extensions.ok((select relforcerowsecurity from pg_class where oid = 'cfg.projects'::regclass), 'RLS forzada en cfg.projects');
select extensions.ok((select relrowsecurity from pg_class where oid = 'ops.settlements'::regclass), 'RLS habilitada en ops.settlements');
select extensions.ok((select relrowsecurity from pg_class where oid = 'market.consensus_components'::regclass), 'RLS habilitada en market.consensus_components (tabla puente)');

select * from extensions.finish();
rollback;
