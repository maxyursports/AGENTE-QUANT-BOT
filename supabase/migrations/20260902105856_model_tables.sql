-- SAQ-MCDS-V1 §17 · 0007_model_tables
-- Features, runs, predictions, evaluation y metricas.

create table model.feature_snapshots (
  feature_snapshot_id      uuid primary key default gen_random_uuid(),
  project_id               uuid not null references cfg.projects (project_id) on delete restrict,
  event_id                 uuid not null references core.events (event_id) on delete restrict,
  feature_set_version      text not null,
  as_of_at                 timestamptz not null,
  available_for_model_at   timestamptz not null,
  values                   jsonb not null,
  lineage                  jsonb not null,
  completeness             numeric(7,6) not null,
  missing_fields           text[] not null default '{}',
  quality_status           app.data_quality_status not null,
  snapshot_hash            app.hash_t not null,
  constraint feature_snapshots_uq unique (event_id, feature_set_version, as_of_at, snapshot_hash),
  constraint feature_snapshots_completeness_chk check (completeness >= 0 and completeness <= 1)
);
create unique index feature_snapshots_hash_uq on model.feature_snapshots (snapshot_hash);
comment on table model.feature_snapshots is 'Conjunto congelado y reproducible de variables disponibles en un instante as-of.';

create table model.model_runs (
  model_run_id      uuid primary key default gen_random_uuid(),
  project_id        uuid not null references cfg.projects (project_id) on delete restrict,
  model_id          uuid not null references cfg.model_registry (model_id) on delete restrict,
  model_version     text not null,
  code_commit_sha   char(40) not null,
  config_hash       app.hash_t not null,
  data_cutoff_at    timestamptz not null,
  random_seed       bigint,
  stage             app.model_stage not null,
  health_status     app.model_health not null,
  started_at        timestamptz not null,
  completed_at      timestamptz,
  run_status        text not null,
  constraint model_runs_uq unique (model_id, model_version, config_hash, data_cutoff_at, random_seed, started_at),
  constraint model_runs_code_commit_sha_chk check (code_commit_sha ~ '^[0-9a-f]{40}$'),
  constraint model_runs_status_chk check (run_status in ('STARTED','SUCCEEDED','FAILED','CANCELLED'))
);
comment on table model.model_runs is 'Ejecucion reproducible de un artefacto, codigo, configuracion y corte de datos.';

create table model.predictions (
  prediction_id              uuid primary key default gen_random_uuid(),
  project_id                 uuid not null references cfg.projects (project_id) on delete restrict,
  model_run_id               uuid not null references model.model_runs (model_run_id) on delete restrict,
  feature_snapshot_id        uuid not null references model.feature_snapshots (feature_snapshot_id) on delete restrict,
  selection_id               uuid not null references market.selections (selection_id) on delete restrict,
  predictive_distribution    jsonb not null,
  model_probability          app.probability_t,
  fair_price                 app.price_t not null,
  uncertainty                jsonb not null,
  robust_ev                  app.ev_t not null,
  decision_at                timestamptz not null,
  expires_at                 timestamptz not null,
  prediction_status          app.prediction_status not null,
  prediction_fingerprint     app.hash_t not null,
  supersedes_prediction_id   uuid references model.predictions (prediction_id),
  constraint predictions_project_fingerprint_uq unique (project_id, prediction_fingerprint)
);
comment on table model.predictions is 'Salida matematica congelada del modelo antes de aplicar la politica de apuesta.';

create table model.evaluation_runs (
  evaluation_run_id      uuid primary key default gen_random_uuid(),
  project_id             uuid not null references cfg.projects (project_id) on delete restrict,
  model_id               uuid not null references cfg.model_registry (model_id) on delete restrict,
  policy_version_id      uuid not null references cfg.policy_versions (policy_version_id) on delete restrict,
  evaluation_type        text not null,
  universe_definition    jsonb not null,
  train_range            tstzrange,
  test_range             tstzrange not null,
  selection_rules_hash   app.hash_t not null,
  started_at             timestamptz not null,
  completed_at           timestamptz,
  status                 text not null,
  holdout_opened_at      timestamptz,
  constraint evaluation_runs_type_chk check (evaluation_type in ('WALK_FORWARD','HOLDOUT','SHADOW_REPLAY')),
  constraint evaluation_runs_status_chk check (status in ('PLANNED','RUNNING','SUCCEEDED','FAILED','LOCKED'))
);
comment on table model.evaluation_runs is 'Define una evaluacion walk-forward, holdout o replay completa y preregistrada.';

create table model.metric_results (
  metric_result_id        uuid primary key default gen_random_uuid(),
  project_id              uuid not null references cfg.projects (project_id) on delete restrict,
  evaluation_run_id       uuid not null references model.evaluation_runs (evaluation_run_id) on delete restrict,
  metric_name             text not null,
  metric_version          text not null,
  segment                 jsonb not null,
  value                   numeric not null,
  lower_ci                numeric,
  upper_ci                numeric,
  effective_sample_size   numeric,
  calculated_at           timestamptz not null default clock_timestamp(),
  input_hash              app.hash_t not null,
  constraint metric_results_uq unique (evaluation_run_id, metric_name, metric_version, segment, input_hash)
);
comment on table model.metric_results is 'Resultados reproducibles de calibracion, precio, economia, riesgo, operacion y datos.';
