-- SAQ-MCDS-V1 §14 · 0004_raw_tables
-- Requests, payloads y restriccion de ubicacion (exactamente payload_json o Storage).

create table raw.api_requests (
  request_id            uuid primary key default gen_random_uuid(),
  project_id            uuid not null references cfg.projects (project_id) on delete restrict,
  data_source_id        uuid not null references cfg.data_sources (data_source_id) on delete restrict,
  endpoint              text not null,
  method                text not null,
  request_fingerprint   app.hash_t not null,
  requested_at          timestamptz not null,
  responded_at          timestamptz,
  request_status        app.request_status not null,
  http_status           integer,
  error_code            text,
  credits_used          numeric,
  latency_ms            integer,
  retry_of_request_id   uuid references raw.api_requests (request_id),
  created_at            timestamptz not null default clock_timestamp()
);
comment on table raw.api_requests is 'Bitacora inmutable de toda llamada, costo, latencia, reintento y respuesta de proveedor.';

create table raw.payloads (
  raw_payload_id           uuid primary key default gen_random_uuid(),
  project_id               uuid not null references cfg.projects (project_id) on delete restrict,
  request_id               uuid not null references raw.api_requests (request_id) on delete restrict,
  payload_seq              smallint not null,
  source_observed_at       timestamptz,
  ingested_at              timestamptz not null default clock_timestamp(),
  available_for_model_at   timestamptz not null,
  content_type             text not null,
  payload_json             jsonb,
  storage_bucket           text,
  storage_path             text,
  content_sha256           app.hash_t not null,
  byte_count               bigint not null,
  schema_version           text not null,
  quality_status           app.data_quality_status not null,
  constraint payloads_request_seq_uq unique (request_id, payload_seq),
  constraint payloads_location_chk check (
    (payload_json is not null and storage_bucket is null and storage_path is null)
    or
    (payload_json is null and storage_bucket is not null and storage_path is not null)
  )
);
comment on table raw.payloads is 'Conserva el contenido recibido, su hash, tiempos de conocimiento y ubicacion fisica.';
