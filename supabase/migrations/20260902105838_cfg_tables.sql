-- SAQ-MCDS-V1 §13 · 0003_cfg_tables
-- Proyectos, membresias, fuentes, deportes, contratos, modelos y politicas.

create table cfg.projects (
  project_id        uuid primary key default gen_random_uuid(),
  project_key       text not null,
  name              text not null,
  base_currency     char(3) not null,
  display_timezone  text not null,
  status            app.project_status not null,
  created_at        timestamptz not null default clock_timestamp(),
  retired_at        timestamptz,
  constraint projects_base_currency_chk check (base_currency ~ '^[A-Z]{3}$'),
  constraint projects_retired_coherence_chk check ((status = 'RETIRED') = (retired_at is not null))
);
create unique index projects_key_uq on cfg.projects (lower(project_key));
comment on table cfg.projects is 'Raiz de aislamiento, propiedad y configuracion general del SuperAgente.';

create table cfg.project_members (
  project_id   uuid not null references cfg.projects (project_id) on delete restrict,
  user_id      uuid not null references auth.users (id),
  member_role  app.member_role not null,
  status       app.membership_status not null,
  joined_at    timestamptz not null default clock_timestamp(),
  revoked_at   timestamptz,
  primary key (project_id, user_id)
);
comment on table cfg.project_members is 'Relaciona usuarios de Supabase Auth con proyectos y roles autorizados.';

create table cfg.data_sources (
  data_source_id   uuid primary key default gen_random_uuid(),
  project_id       uuid not null references cfg.projects (project_id) on delete restrict,
  source_key       text not null,
  source_type      text not null,
  display_name     text not null,
  authority_scope  text[] not null,
  adapter_version  text not null,
  enabled          boolean not null default false,
  created_at       timestamptz not null default clock_timestamp(),
  retired_at       timestamptz,
  constraint data_sources_project_key_uq unique (project_id, source_key)
);
comment on table cfg.data_sources is 'Registro versionado de proveedores y ambitos de autoridad de cada fuente.';

create table cfg.sports (
  sport_id        uuid primary key default gen_random_uuid(),
  project_id      uuid not null references cfg.projects (project_id) on delete restrict,
  sport_key       text not null,
  display_name    text not null,
  adapter_version text not null,
  research_mode   boolean not null default true,
  status          app.catalog_status not null,
  created_at      timestamptz not null default clock_timestamp(),
  retired_at      timestamptz,
  constraint sports_project_key_uq unique (project_id, sport_key)
);
comment on table cfg.sports is 'Catalogo minimo de deportes y adaptadores especificos.';

create table cfg.market_contracts (
  market_contract_id uuid primary key default gen_random_uuid(),
  project_id         uuid not null references cfg.projects (project_id) on delete restrict,
  sport_id           uuid not null references cfg.sports (sport_id) on delete restrict,
  contract_key       text not null,
  market_family      text not null,
  status             app.catalog_status not null,
  created_at         timestamptz not null default clock_timestamp(),
  retired_at         timestamptz,
  constraint market_contracts_project_key_uq unique (project_id, contract_key)
);
comment on table cfg.market_contracts is 'Identidad estable de una familia de mercado independiente de etiquetas comerciales.';

create table cfg.market_contract_versions (
  market_contract_version_id uuid primary key default gen_random_uuid(),
  project_id                 uuid not null references cfg.projects (project_id) on delete restrict,
  market_contract_id         uuid not null references cfg.market_contracts (market_contract_id) on delete restrict,
  semantic_version           text not null,
  period                     text not null,
  unit                       text not null,
  line_schema                jsonb,
  selection_schema           jsonb not null,
  payoff_rule                jsonb not null,
  void_policy                jsonb not null,
  active_from                timestamptz not null,
  active_to                  timestamptz,
  config_hash                app.hash_t not null,
  approved_at                timestamptz,
  supersedes_version_id      uuid references cfg.market_contract_versions (market_contract_version_id),
  constraint market_contract_versions_semver_uq unique (market_contract_id, semantic_version),
  constraint market_contract_versions_validity_chk check (active_to is null or active_from < active_to),
  exclude using gist (
    market_contract_id with =,
    tstzrange(active_from, coalesce(active_to, 'infinity'::timestamptz), '[)') with &&
  )
);
create unique index market_contract_versions_config_hash_uq
  on cfg.market_contract_versions (market_contract_id, config_hash);
comment on table cfg.market_contract_versions is 'Version normativa que fija periodo, unidad, seleccion, linea, payoff, void y settlement.';

create table cfg.model_registry (
  model_id       uuid primary key default gen_random_uuid(),
  project_id     uuid not null references cfg.projects (project_id) on delete restrict,
  sport_id       uuid not null references cfg.sports (sport_id) on delete restrict,
  model_key      text not null,
  display_name   text not null,
  current_stage  app.model_stage not null,
  health_status  app.model_health not null,
  owner          text not null,
  created_at     timestamptz not null default clock_timestamp(),
  retired_at     timestamptz,
  constraint model_registry_project_key_uq unique (project_id, model_key)
);
comment on table cfg.model_registry is 'Identidad y autorizacion de cada familia de modelo cuantitativo.';

create table cfg.policy_versions (
  policy_version_id             uuid primary key default gen_random_uuid(),
  project_id                    uuid not null references cfg.projects (project_id) on delete restrict,
  policy_key                    text not null,
  semantic_version              text not null,
  stage                         app.model_stage not null,
  config                        jsonb not null,
  config_hash                   app.hash_t not null,
  active_from                   timestamptz not null,
  active_to                     timestamptz,
  approved_at                   timestamptz,
  supersedes_policy_version_id  uuid references cfg.policy_versions (policy_version_id),
  constraint policy_versions_semver_uq unique (project_id, policy_key, semantic_version),
  constraint policy_versions_validity_chk check (active_to is null or active_from < active_to),
  constraint policy_versions_config_hash_uq unique (config_hash),
  exclude using gist (
    project_id with =,
    policy_key with =,
    tstzrange(active_from, coalesce(active_to, 'infinity'::timestamptz), '[)') with &&
  )
);
comment on table cfg.policy_versions is 'Congela hard gates, reglas de senal, riesgo, exposicion y presentacion.';
