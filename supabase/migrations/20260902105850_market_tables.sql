-- SAQ-MCDS-V1 §16 · 0006_market_tables
-- Bookmakers, selections, odds, consensus y cierre.

create table market.bookmakers (
  bookmaker_id         uuid primary key default gen_random_uuid(),
  project_id           uuid not null references cfg.projects (project_id) on delete restrict,
  bookmaker_key        text not null,
  display_name         text not null,
  region               text not null,
  role                 text not null,
  independence_group   text,
  status               app.catalog_status not null,
  created_at           timestamptz not null default clock_timestamp(),
  retired_at           timestamptz,
  constraint bookmakers_project_key_region_uq unique (project_id, bookmaker_key, region),
  constraint bookmakers_role_chk check (role in ('EXECUTION_BOOK','SENSOR','BOTH'))
);
comment on table market.bookmakers is 'Identidad canonica del operador de cuotas y su contexto regional.';

create table market.selections (
  selection_id                 uuid primary key default gen_random_uuid(),
  project_id                   uuid not null references cfg.projects (project_id) on delete restrict,
  event_id                     uuid not null references core.events (event_id) on delete restrict,
  market_contract_version_id   uuid not null references cfg.market_contract_versions (market_contract_version_id) on delete restrict,
  outcome_side                 text not null,
  participant_id               uuid references core.participants (participant_id) on delete restrict,
  line                         app.line_t,
  selection_key                text not null,
  created_at                   timestamptz not null default clock_timestamp(),
  constraint selections_project_key_uq unique (project_id, selection_key)
);
comment on table market.selections is 'Resultado apostable exacto dentro de un Market Contract y evento.';

create table market.odds_snapshots (
  odds_snapshot_id         uuid primary key default gen_random_uuid(),
  project_id               uuid not null references cfg.projects (project_id) on delete restrict,
  selection_id             uuid not null references market.selections (selection_id) on delete restrict,
  bookmaker_id             uuid not null references market.bookmakers (bookmaker_id) on delete restrict,
  price_decimal            app.price_t not null,
  line                     app.line_t,
  source_observed_at       timestamptz,
  ingested_at              timestamptz not null default clock_timestamp(),
  available_for_model_at   timestamptz not null,
  quote_status             app.quote_status not null,
  raw_payload_id           uuid not null references raw.payloads (raw_payload_id) on delete restrict,
  idempotency_key          app.hash_t not null,
  bookmaker_last_update    timestamptz,
  constraint odds_snapshots_project_idempotency_uq unique (project_id, idempotency_key)
);
comment on table market.odds_snapshots is 'Observacion inmutable de cuota y linea ofrecidas por un bookmaker.';

create table market.consensus_snapshots (
  consensus_snapshot_id   uuid primary key default gen_random_uuid(),
  project_id              uuid not null references cfg.projects (project_id) on delete restrict,
  selection_id            uuid not null references market.selections (selection_id) on delete restrict,
  method_version          text not null,
  consensus_price         app.price_t not null,
  consensus_probability   app.probability_t,
  freshness_cutoff_at     timestamptz not null,
  source_count            smallint not null,
  independence_count      smallint not null,
  quality_status          app.data_quality_status not null,
  calculated_at           timestamptz not null default clock_timestamp(),
  input_hash              app.hash_t not null,
  constraint consensus_snapshots_uq unique (selection_id, method_version, calculated_at)
);
comment on table market.consensus_snapshots is 'Referencia de mercado versionada y reproducible, separada de la probabilidad del modelo.';

create table market.consensus_components (
  consensus_snapshot_id  uuid not null references market.consensus_snapshots (consensus_snapshot_id) on delete restrict,
  odds_snapshot_id       uuid not null references market.odds_snapshots (odds_snapshot_id) on delete restrict,
  included               boolean not null,
  weight                 numeric(12,10),
  devig_probability      app.probability_t,
  reason_code            text,
  primary key (consensus_snapshot_id, odds_snapshot_id),
  constraint consensus_components_weight_chk check (
    (included and weight is not null and weight >= 0)
    or (not included and weight is null)
  )
);
comment on table market.consensus_components is 'Explica que quotes participaron o fueron excluidos de cada consenso.';

create table market.closing_lines (
  closing_line_id         uuid primary key default gen_random_uuid(),
  project_id              uuid not null references cfg.projects (project_id) on delete restrict,
  selection_id            uuid not null references market.selections (selection_id) on delete restrict,
  close_type              text not null,
  bookmaker_id            uuid references market.bookmakers (bookmaker_id) on delete restrict,
  consensus_snapshot_id   uuid references market.consensus_snapshots (consensus_snapshot_id) on delete restrict,
  closing_price           app.price_t not null,
  closing_line            app.line_t,
  source_observed_at      timestamptz,
  recorded_at             timestamptz not null default clock_timestamp(),
  quality_status          app.data_quality_status not null,
  method_version          text not null,
  constraint closing_lines_uq unique (selection_id, close_type, method_version, recorded_at),
  constraint closing_lines_close_type_chk check (close_type in ('EXECUTION_BOOK','MARKET_CONSENSUS')),
  constraint closing_lines_single_source_chk check (
    (close_type = 'EXECUTION_BOOK' and bookmaker_id is not null and consensus_snapshot_id is null)
    or
    (close_type = 'MARKET_CONSENSUS' and consensus_snapshot_id is not null and bookmaker_id is null)
  )
);
comment on table market.closing_lines is 'Cierre comparable del execution book y/o consenso para calculo de CLV.';
