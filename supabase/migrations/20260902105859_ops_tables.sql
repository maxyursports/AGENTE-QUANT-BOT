-- SAQ-MCDS-V1 §18 · 0008_ops_tables
-- Signals, execution, settlement, bankroll, exposure y auditoria.

create table ops.signals (
  signal_id                  uuid primary key default gen_random_uuid(),
  project_id                 uuid not null references cfg.projects (project_id) on delete restrict,
  prediction_id              uuid not null references model.predictions (prediction_id) on delete restrict,
  selection_id               uuid not null references market.selections (selection_id) on delete restrict,
  odds_snapshot_id           uuid not null references market.odds_snapshots (odds_snapshot_id) on delete restrict,
  policy_version_id          uuid not null references cfg.policy_versions (policy_version_id) on delete restrict,
  minimum_acceptable_odds    app.price_t not null,
  suggested_stake_fraction   numeric(12,10) not null,
  quality_band               text not null,
  reason_codes               text[] not null default '{}',
  invalidation_conditions    text[] not null default '{}',
  generated_at               timestamptz not null default clock_timestamp(),
  expiration_at              timestamptz not null,
  signal_status              app.signal_status not null,
  payload_hash               app.hash_t not null,
  supersedes_signal_id       uuid references ops.signals (signal_id),
  constraint signals_uq unique (prediction_id, odds_snapshot_id, policy_version_id),
  constraint signals_stake_fraction_chk check (suggested_stake_fraction >= 0),
  constraint signals_quality_band_chk check (quality_band in ('ELITE','HIGH','MEDIUM','NOT_APPROVED'))
);
comment on table ops.signals is 'Decision del Policy Engine preparada para entrega; no equivale a ejecucion.';

create table ops.signal_deliveries (
  signal_delivery_id    uuid primary key default gen_random_uuid(),
  project_id            uuid not null references cfg.projects (project_id) on delete restrict,
  signal_id             uuid not null references ops.signals (signal_id) on delete restrict,
  channel               text not null,
  destination_ref       text not null,
  external_message_id   text,
  delivery_status       text not null,
  attempt_no            smallint not null,
  sent_at               timestamptz,
  delivered_at          timestamptz,
  opened_at             timestamptz,
  error_code            text,
  response_hash         app.hash_t,
  constraint signal_deliveries_uq unique (signal_id, channel, attempt_no),
  constraint signal_deliveries_status_chk check (delivery_status in ('QUEUED','SENT','DELIVERED','OPENED','FAILED'))
);
comment on table ops.signal_deliveries is 'Registra cada intento de entrega y apertura en Telegram u otro canal.';

create table ops.executions (
  execution_id              uuid primary key default gen_random_uuid(),
  project_id                uuid not null references cfg.projects (project_id) on delete restrict,
  signal_id                 uuid not null references ops.signals (signal_id) on delete restrict,
  execution_status          app.execution_status not null,
  actual_odds               app.price_t,
  actual_line               app.line_t,
  requested_stake           app.money_t,
  accepted_stake            app.money_t,
  attempted_at              timestamptz,
  placed_at                 timestamptz,
  account_region            text,
  confirmation_method       text not null,
  receipt_ref               text,
  rejection_reason          text,
  execution_delay_ms        integer,
  price_slippage            app.ev_t,
  supersedes_execution_id   uuid references ops.executions (execution_id),
  constraint executions_confirmation_method_chk
    check (confirmation_method in ('USER','RECEIPT','AUTOMATED','TELEGRAM_USER','AUTOMATED_RECEIPT'))
);
comment on table ops.executions is 'Registro de lo que realmente se intento o coloco en el execution book.';

create table ops.execution_events (
  execution_event_id   uuid primary key default gen_random_uuid(),
  project_id           uuid not null references cfg.projects (project_id) on delete restrict,
  execution_id         uuid not null references ops.executions (execution_id) on delete restrict,
  from_status          app.execution_status,
  to_status            app.execution_status not null,
  event_at             timestamptz not null default clock_timestamp(),
  actor_type           text not null,
  actor_ref            text,
  evidence             jsonb not null default '{}'::jsonb,
  event_hash           app.hash_t not null,
  constraint execution_events_project_hash_uq unique (project_id, event_hash),
  constraint execution_events_actor_type_chk check (actor_type in ('USER','SYSTEM','BOOKMAKER','TELEGRAM'))
);
comment on table ops.execution_events is 'Historial inmutable de transiciones y evidencia del ciclo de ejecucion.';

create table ops.settlements (
  settlement_id                uuid primary key default gen_random_uuid(),
  project_id                   uuid not null references cfg.projects (project_id) on delete restrict,
  execution_id                 uuid not null references ops.executions (execution_id) on delete restrict,
  selection_id                 uuid not null references market.selections (selection_id) on delete restrict,
  market_contract_version_id   uuid not null references cfg.market_contract_versions (market_contract_version_id) on delete restrict,
  settlement_status            app.settlement_status not null,
  result_values                jsonb not null,
  stake                        app.money_t not null,
  price                        app.price_t not null,
  payout                       app.money_t not null,
  net_return                   app.money_t not null,
  source_id                    uuid not null,
  raw_payload_id               uuid not null references raw.payloads (raw_payload_id) on delete restrict,
  source_observed_at           timestamptz,
  settled_at                   timestamptz not null default clock_timestamp(),
  settlement_hash              app.hash_t not null,
  supersedes_settlement_id     uuid references ops.settlements (settlement_id),
  constraint settlements_project_hash_uq unique (project_id, settlement_hash)
);
comment on table ops.settlements is 'Resultado economico calculado por el Settlement Engine conforme al contrato exacto.';

create table ops.bankroll_ledger (
  bankroll_entry_id   uuid primary key default gen_random_uuid(),
  project_id          uuid not null references cfg.projects (project_id) on delete restrict,
  currency            char(3) not null,
  entry_type          text not null,
  amount              app.money_t not null,
  execution_id        uuid references ops.executions (execution_id) on delete restrict,
  settlement_id       uuid references ops.settlements (settlement_id) on delete restrict,
  effective_at        timestamptz not null,
  recorded_at         timestamptz not null default clock_timestamp(),
  entry_hash          app.hash_t not null,
  notes               text,
  constraint bankroll_ledger_project_hash_uq unique (project_id, entry_hash),
  constraint bankroll_ledger_entry_type_chk check (entry_type in ('DEPOSIT','WITHDRAWAL','STAKE','PAYOUT','ADJUSTMENT')),
  constraint bankroll_ledger_adjustment_notes_chk check (entry_type <> 'ADJUSTMENT' or notes is not null)
);
comment on table ops.bankroll_ledger is 'Libro mayor append-only para reconstruir banca, depositos, retiros y P&L realizado.';

create table ops.portfolio_exposures (
  portfolio_exposure_id   uuid primary key default gen_random_uuid(),
  project_id              uuid not null references cfg.projects (project_id) on delete restrict,
  signal_id               uuid not null references ops.signals (signal_id) on delete restrict,
  policy_version_id       uuid not null references cfg.policy_versions (policy_version_id) on delete restrict,
  as_of_at                timestamptz not null,
  bankroll_amount         app.money_t not null,
  proposed_stake          app.money_t not null,
  exposures               jsonb not null,
  correlation_groups      jsonb not null,
  gate_status             text not null,
  reason_codes            text[] not null default '{}',
  snapshot_hash           app.hash_t not null,
  constraint portfolio_exposures_uq unique (signal_id, policy_version_id, snapshot_hash),
  constraint portfolio_exposures_gate_status_chk check (gate_status in ('PASS','FAIL'))
);
comment on table ops.portfolio_exposures is 'Snapshot de exposicion y correlacion usado por el hard gate EXPOSURE.';

create table ops.data_quality_events (
  data_quality_event_id   uuid primary key default gen_random_uuid(),
  project_id              uuid not null references cfg.projects (project_id) on delete restrict,
  data_source_id          uuid references cfg.data_sources (data_source_id) on delete restrict,
  entity_schema           text not null,
  entity_table            text not null,
  entity_id               uuid not null,
  issue_type              text not null,
  severity                text not null,
  quality_status          app.data_quality_status not null,
  detected_at             timestamptz not null default clock_timestamp(),
  resolved_at             timestamptz,
  evidence                jsonb not null,
  resolution              jsonb
);
comment on table ops.data_quality_events is 'Incidencias de frescura, completitud, identidad, esquema y correccion.';

create table ops.audit_events (
  audit_event_id       uuid primary key default gen_random_uuid(),
  project_id           uuid not null references cfg.projects (project_id) on delete restrict,
  actor_type           text not null,
  actor_id             uuid,
  action               text not null,
  entity_schema        text not null,
  entity_table         text not null,
  entity_id            uuid not null,
  before_state         jsonb,
  after_state          jsonb,
  reason               text not null,
  change_request_ref   text,
  created_at           timestamptz not null default clock_timestamp(),
  event_hash           app.hash_t not null,
  constraint audit_events_project_hash_uq unique (project_id, event_hash),
  constraint audit_events_actor_type_chk check (actor_type in ('USER','SERVICE','MIGRATION','CLAUDE'))
);
comment on table ops.audit_events is 'Bitacora de cambios administrativos, promociones y decisiones de gobierno.';
