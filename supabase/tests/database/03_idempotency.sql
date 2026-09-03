-- SAQ-MCDS-V1 §29 (03_idempotency): repeticion y hash conflictivo.
-- Mismo contenido no duplica; conflicto falla (SAQ-MCDS-V1 §11).
begin;
select plan(6);

-- Fixture: una selection valida para colgar odds_snapshots.
insert into core.events (project_id, sport_id, competition_id, identity_status, candidate_fingerprint)
select p.project_id, s.sport_id, c.competition_id, 'VALIDATED', repeat('e', 64)
from cfg.projects p join cfg.sports s on s.project_id = p.project_id
join core.competitions c on c.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;

-- FT_1X2 tiene line_schema nullable=true en el seed (0013); evita disparar
-- selections_line_schema_check con una linea NULL sobre un contrato que la exige.
insert into market.selections (project_id, event_id, market_contract_version_id, outcome_side, selection_key)
select p.project_id, ev.event_id, mcv.market_contract_version_id, 'HOME', 'test-selection-idem'
from cfg.projects p
join core.events ev on ev.project_id = p.project_id
join cfg.market_contracts mc on mc.project_id = p.project_id and mc.contract_key = 'FT_1X2'
join cfg.market_contract_versions mcv on mcv.market_contract_id = mc.market_contract_id
where p.project_key = 'agente-quant-bot' limit 1;

insert into market.bookmakers (project_id, bookmaker_key, display_name, region, role, status)
select project_id, 'test_book_idem', 'Test Book', 'GLOBAL', 'SENSOR', 'DRAFT'::app.catalog_status
from cfg.projects where project_key = 'agente-quant-bot';

insert into raw.api_requests (project_id, data_source_id, endpoint, method, request_fingerprint, requested_at, request_status)
select p.project_id, ds.data_source_id, '/test-idem', 'GET', repeat('1', 64), clock_timestamp(), 'SUCCEEDED'::app.request_status
from cfg.projects p join cfg.data_sources ds on ds.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;

insert into raw.payloads (project_id, request_id, payload_seq, ingested_at, available_for_model_at, content_type, payload_json, content_sha256, byte_count, schema_version, quality_status)
select p.project_id, r.request_id, 1, clock_timestamp(), clock_timestamp(), 'application/json', '{}'::jsonb, repeat('2', 64), 2, 'v1', 'AVAILABLE'::app.data_quality_status
from cfg.projects p join raw.api_requests r on r.project_id = p.project_id and r.endpoint = '/test-idem'
where p.project_key = 'agente-quant-bot';

-- Primer INSERT: exitoso.
select lives_ok(
  $$ insert into market.odds_snapshots (project_id, selection_id, bookmaker_id, price_decimal, ingested_at, available_for_model_at, quote_status, raw_payload_id, idempotency_key)
     select (select project_id from cfg.projects where project_key='agente-quant-bot'),
            (select selection_id from market.selections where selection_key='test-selection-idem'),
            (select bookmaker_id from market.bookmakers where bookmaker_key='test_book_idem'),
            1.90, clock_timestamp(), clock_timestamp(), 'AVAILABLE'::app.quote_status, (select raw_payload_id from raw.payloads limit 1), repeat('c', 64) $$,
  'primer insert con idempotency_key nuevo es aceptado'
);

select is((select count(*)::int from market.odds_snapshots where idempotency_key = repeat('c', 64)), 1,
  'exactamente 1 fila tras el primer insert');

-- Reintento con el MISMO idempotency_key (incluso con contenido distinto): la UNIQUE constraint
-- lo rechaza; la resolucion "mismo contenido no duplica / contenido distinto crea incidencia" es
-- responsabilidad de la capa de aplicacion que atrapa este error (SAQ-MCDS-V1 §11).
select throws_ok(
  $$ insert into market.odds_snapshots (project_id, selection_id, bookmaker_id, price_decimal, ingested_at, available_for_model_at, quote_status, raw_payload_id, idempotency_key)
     select (select project_id from cfg.projects where project_key='agente-quant-bot'),
            (select selection_id from market.selections where selection_key='test-selection-idem'),
            (select bookmaker_id from market.bookmakers where bookmaker_key='test_book_idem'),
            2.10, clock_timestamp(), clock_timestamp(), 'AVAILABLE'::app.quote_status, (select raw_payload_id from raw.payloads limit 1), repeat('c', 64) $$,
  '23505', null, 'reintento con idempotency_key repetido falla (unique_violation)'
);

select is((select count(*)::int from market.odds_snapshots where idempotency_key = repeat('c', 64)), 1,
  'sigue existiendo exactamente 1 fila -- el conflicto no duplico ni sobrescribio');

-- Idempotencia UNIQUE(project_id, entry_hash) en ops.bankroll_ledger.
select lives_ok(
  $$ insert into ops.bankroll_ledger (project_id, currency, entry_type, amount, effective_at, entry_hash)
     select project_id, base_currency, 'DEPOSIT', 100.00, clock_timestamp(), repeat('d', 64)
     from cfg.projects where project_key = 'agente-quant-bot' $$,
  'primer bankroll_ledger con entry_hash nuevo es aceptado'
);
select throws_ok(
  $$ insert into ops.bankroll_ledger (project_id, currency, entry_type, amount, effective_at, entry_hash)
     select project_id, base_currency, 'DEPOSIT', 999.00, clock_timestamp(), repeat('d', 64)
     from cfg.projects where project_key = 'agente-quant-bot' $$,
  '23505', null, 'entry_hash repetido en bankroll_ledger falla (unique_violation)'
);

select * from finish();
rollback;
