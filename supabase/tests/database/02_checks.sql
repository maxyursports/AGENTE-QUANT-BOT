-- SAQ-MCDS-V1 §29 (02_checks): rangos numeric, hashes, ubicacion de raw, tiempos.
-- Writes invalidos fallan.
begin;
select plan(11);

-- Fixtures del seed canonico (0013).
select ok((select count(*) from cfg.projects where project_key = 'agente-quant-bot') = 1, 'fixture: proyecto seed presente');

-- Fixture local: una request para poder ejercitar raw.payloads en esta suite.
insert into raw.api_requests (project_id, data_source_id, endpoint, method, request_fingerprint, requested_at, request_status)
select p.project_id, ds.data_source_id, '/test', 'GET', repeat('f', 64), clock_timestamp(), 'SUCCEEDED'::app.request_status
from cfg.projects p join cfg.data_sources ds on ds.project_id = p.project_id
where p.project_key = 'agente-quant-bot' limit 1;

-- Precio/cuota: CHECK price > 1 (dominio app.price_t, SAQ-MCDS-V1 §9/§20).
select throws_ok(
  $$ insert into market.odds_snapshots (project_id, selection_id, bookmaker_id, price_decimal, ingested_at, available_for_model_at, quote_status, raw_payload_id, idempotency_key)
     select (select project_id from cfg.projects limit 1), gen_random_uuid(), gen_random_uuid(), 0.95, clock_timestamp(), clock_timestamp(), 'AVAILABLE'::app.quote_status, gen_random_uuid(), repeat('a', 64) $$,
  null, 'price_decimal <= 1 es rechazado por app.price_t'
);

-- Probabilidad: CHECK entre 0 y 1 (dominio app.probability_t).
select throws_ok(
  $$ select '1.5'::app.probability_t $$,
  null, 'probabilidad > 1 es rechazada por app.probability_t'
);
select throws_ok(
  $$ select '-0.1'::app.probability_t $$,
  null, 'probabilidad negativa es rechazada por app.probability_t'
);
select lives_ok($$ select '0.5'::app.probability_t $$, 'probabilidad valida (0.5) es aceptada');

-- Hash SHA-256: CHECK regex ^[0-9a-f]{64}$ (dominio app.hash_t).
select throws_ok(
  $$ select 'not-a-hash'::app.hash_t $$,
  null, 'hash con formato invalido es rechazado por app.hash_t'
);
select throws_ok(
  $$ select upper(repeat('a', 64))::app.hash_t $$,
  null, 'hash en mayusculas es rechazado por app.hash_t (exige hex minuscula)'
);
select lives_ok($$ select repeat('a', 64)::app.hash_t $$, 'hash valido (64 hex minuscula) es aceptado');

-- Ubicacion raw: exactamente payload_json o storage_path, nunca ambos ni ninguno (SAQ-MCDS-V1 §20).
select throws_ok(
  $$ insert into raw.payloads (project_id, request_id, payload_seq, ingested_at, available_for_model_at, content_type, content_sha256, byte_count, schema_version, quality_status)
     select (select project_id from cfg.projects limit 1),
            (select request_id from raw.api_requests limit 1),
            999, clock_timestamp(), clock_timestamp(), 'application/json', repeat('a', 64), 10, 'v1', 'AVAILABLE'::app.data_quality_status $$,
  null, 'raw.payloads sin payload_json ni storage_path es rechazado'
);
select throws_ok(
  $$ insert into raw.payloads (project_id, request_id, payload_seq, ingested_at, available_for_model_at, content_type, payload_json, storage_bucket, storage_path, content_sha256, byte_count, schema_version, quality_status)
     select (select project_id from cfg.projects limit 1),
            (select request_id from raw.api_requests limit 1),
            998, clock_timestamp(), clock_timestamp(), 'application/json', '{}'::jsonb, 'bucket', 'path', repeat('a', 64), 10, 'v1', 'AVAILABLE'::app.data_quality_status $$,
  null, 'raw.payloads con payload_json Y storage_path a la vez es rechazado'
);

-- Tiempos: valid_from < valid_to (SAQ-MCDS-V1 §10/§20, cfg.market_contract_versions).
select throws_ok(
  $$ insert into cfg.market_contract_versions (project_id, market_contract_id, semantic_version, period, unit, selection_schema, payoff_rule, void_policy, active_from, active_to, config_hash)
     select (select project_id from cfg.projects limit 1), (select market_contract_id from cfg.market_contracts limit 1),
            '99.0.0-test', 'MATCH', 'GOALS', '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
            '2026-01-01'::timestamptz, '2025-01-01'::timestamptz, repeat('b', 64) $$,
  null, 'active_to anterior a active_from es rechazado en cfg.market_contract_versions'
);

select * from finish();
rollback;
