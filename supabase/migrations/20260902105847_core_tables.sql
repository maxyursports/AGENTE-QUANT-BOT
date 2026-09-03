-- SAQ-MCDS-V1 §15 · 0005_core_tables
-- Identidades, mappings, eventos y versiones.

create table core.competitions (
  competition_id    uuid primary key default gen_random_uuid(),
  project_id        uuid not null references cfg.projects (project_id) on delete restrict,
  sport_id          uuid not null references cfg.sports (sport_id) on delete restrict,
  canonical_name    text not null,
  country_code      char(2),
  competition_type  text not null,
  status            app.catalog_status not null,
  created_at        timestamptz not null default clock_timestamp(),
  retired_at        timestamptz
);
comment on table core.competitions is 'Identidad canonica de ligas, torneos y competiciones.';

create table core.seasons (
  season_id       uuid primary key default gen_random_uuid(),
  project_id      uuid not null references cfg.projects (project_id) on delete restrict,
  competition_id  uuid not null references core.competitions (competition_id) on delete restrict,
  season_key      text not null,
  starts_on       date,
  ends_on         date,
  status          app.catalog_status not null,
  created_at      timestamptz not null default clock_timestamp(),
  retired_at      timestamptz,
  constraint seasons_competition_key_uq unique (competition_id, season_key),
  constraint seasons_range_chk check (starts_on is null or ends_on is null or starts_on <= ends_on)
);
comment on table core.seasons is 'Edicion temporal de una competicion.';

create table core.participants (
  participant_id    uuid primary key default gen_random_uuid(),
  project_id        uuid not null references cfg.projects (project_id) on delete restrict,
  sport_id          uuid not null references cfg.sports (sport_id) on delete restrict,
  participant_type  text not null,
  canonical_name    text not null,
  country_code      char(2),
  status            app.catalog_status not null,
  created_at        timestamptz not null default clock_timestamp(),
  retired_at        timestamptz
);
comment on table core.participants is 'Identidad canonica de equipos, jugadores, pares u organizaciones.';

create table core.source_entity_mappings (
  mapping_id             uuid primary key default gen_random_uuid(),
  project_id             uuid not null references cfg.projects (project_id) on delete restrict,
  data_source_id         uuid not null references cfg.data_sources (data_source_id) on delete restrict,
  entity_type            text not null,
  source_entity_id       text not null,
  canonical_entity_id    uuid not null,
  mapping_status         text not null,
  confidence             numeric(6,5),
  valid_from             timestamptz not null,
  valid_to               timestamptz,
  recorded_at            timestamptz not null default clock_timestamp(),
  supersedes_mapping_id  uuid references core.source_entity_mappings (mapping_id),
  constraint sem_source_entity_valid_from_uq unique (data_source_id, entity_type, source_entity_id, valid_from),
  constraint sem_entity_type_chk check (entity_type in ('SPORT','COMPETITION','SEASON','PARTICIPANT','EVENT','BOOKMAKER')),
  constraint sem_mapping_status_chk check (mapping_status in ('PROPOSED','CONFIRMED','REJECTED','SUPERSEDED')),
  constraint sem_validity_chk check (valid_to is null or valid_from < valid_to)
);
comment on table core.source_entity_mappings is 'Mapea identificadores externos a identidades internas con vigencia y evidencia.';

create table core.events (
  event_id              uuid primary key default gen_random_uuid(),
  project_id            uuid not null references cfg.projects (project_id) on delete restrict,
  sport_id              uuid not null references cfg.sports (sport_id) on delete restrict,
  competition_id        uuid not null references core.competitions (competition_id) on delete restrict,
  season_id             uuid references core.seasons (season_id) on delete restrict,
  home_participant_id   uuid references core.participants (participant_id) on delete restrict,
  away_participant_id   uuid references core.participants (participant_id) on delete restrict,
  neutral_venue         boolean not null default false,
  identity_status       text not null,
  candidate_fingerprint app.hash_t not null,
  merged_into_event_id  uuid references core.events (event_id),
  created_at            timestamptz not null default clock_timestamp(),
  constraint events_identity_status_chk check (identity_status in ('PROPOSED','VALIDATED','MERGED','REJECTED')),
  constraint events_distinct_participants_chk check (
    home_participant_id is null or away_participant_id is null or home_participant_id <> away_participant_id
  )
);
comment on table core.events is 'Identidad estable de un encuentro deportivo; separada de su representacion cambiante.';

create table core.event_versions (
  event_version_id             uuid primary key default gen_random_uuid(),
  project_id                   uuid not null references cfg.projects (project_id) on delete restrict,
  event_id                     uuid not null references core.events (event_id) on delete restrict,
  scheduled_start_at           timestamptz not null,
  lifecycle_status             app.event_lifecycle_status not null,
  analysis_status              app.event_analysis_status not null,
  venue                        jsonb,
  source_observed_at           timestamptz,
  ingested_at                  timestamptz not null default clock_timestamp(),
  available_for_model_at       timestamptz not null,
  valid_from                   timestamptz not null,
  valid_to                     timestamptz,
  recorded_at                  timestamptz not null default clock_timestamp(),
  raw_payload_id               uuid references raw.payloads (raw_payload_id) on delete restrict,
  version_hash                 app.hash_t not null,
  supersedes_event_version_id  uuid references core.event_versions (event_version_id),
  constraint event_versions_validity_chk check (valid_to is null or valid_from < valid_to)
);
comment on table core.event_versions is 'Representacion bitemporal de horario, estado y sede de un evento.';
