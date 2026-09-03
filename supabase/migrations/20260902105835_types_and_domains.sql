-- SAQ-MCDS-V1 §9, §12 · 0002_types_and_domains
-- 15 enums cerrados (app.*) y dominios numeric/hash reutilizables (Parte III, Tipos fisicos).
-- No se agregan enums, valores ni dominios fuera de los listados en SAQ-MCDS-V1 / REV3.

create type app.project_status as enum ('ACTIVE','SUSPENDED','RETIRED');

create type app.member_role as enum ('OWNER','OPERATOR','ANALYST','VIEWER');

create type app.membership_status as enum ('ACTIVE','REVOKED');

create type app.catalog_status as enum ('DRAFT','ACTIVE','SUSPENDED','RETIRED');

create type app.model_stage as enum ('RESEARCH','CHALLENGER','SHADOW','MICROSTAKE','CONTROLLED','MATURE','RETIRED');

create type app.model_health as enum ('HEALTHY','WATCH','DEGRADED','SUSPENDED');

create type app.event_lifecycle_status as enum ('DISCOVERED','SCHEDULED','LIVE','FINISHED','POSTPONED','CANCELLED','ABANDONED','UNKNOWN');

create type app.event_analysis_status as enum ('UNASSESSED','VALIDATED','ANALYZING','NO_DATA','REJECTED','ELIGIBLE','CLOSED');

create type app.prediction_status as enum ('CREATED','VALIDATED','REJECTED','PUBLISHED','SUPERSEDED','EXPIRED');

create type app.signal_status as enum ('GENERATED','APPROVED','SENT_TELEGRAM','OPENED','EXPIRED','CANCELLED','DELIVERY_FAILED');

create type app.execution_status as enum ('UNKNOWN','NOT_PLACED','BET_PLACED','PARTIALLY_PLACED','ODDS_CHANGED','LINE_CHANGED','MARKET_SUSPENDED','MARKET_CLOSED','REJECTED_BY_BOOK','LIMIT_REDUCED','ERROR');

create type app.settlement_status as enum ('PENDING','WIN','HALF_WIN','PUSH','HALF_LOSS','LOSS','VOID','PARTIAL_VOID','UNKNOWN','DISPUTED','CORRECTED');

create type app.data_quality_status as enum ('AVAILABLE','UNAVAILABLE','STALE','PARTIAL','CONFIRMED','INVALID','CORRECTED');

create type app.request_status as enum ('PLANNED','SENT','SUCCEEDED','EMPTY','RATE_LIMITED','FAILED','RETRY_EXHAUSTED');

create type app.quote_status as enum ('AVAILABLE','STALE','SUSPENDED','CLOSED','INVALID');

-- Dominios numericos (SAQ-MCDS-V1 §9 "Tipos fisicos"). NUMERIC exacto; float queda prohibido.

create domain app.price_t as numeric(12,6)
  check (value > 1);
comment on domain app.price_t is 'Cuota decimal exacta. CHECK price > 1 (SAQ-MCDS-V1 §9/§20).';

create domain app.line_t as numeric(10,4);
comment on domain app.line_t is 'Linea de mercado; conserva signo, medias y cuartos (SAQ-MCDS-V1 §9).';

create domain app.probability_t as numeric(12,10)
  check (value >= 0 and value <= 1);
comment on domain app.probability_t is 'Probabilidad/proxy de mercado. CHECK entre 0 y 1 (SAQ-MCDS-V1 §9/§20).';

create domain app.ev_t as numeric(14,10);
comment on domain app.ev_t is 'EV o CLV: retorno proporcional exacto (SAQ-MCDS-V1 §9).';

create domain app.money_t as numeric(18,6);
comment on domain app.money_t is 'Dinero o stake en la moneda del proyecto (SAQ-MCDS-V1 §9).';

create domain app.hash_t as char(64)
  check (value ~ '^[0-9a-f]{64}$');
comment on domain app.hash_t is 'Hash SHA-256 hex minuscula (SAQ-MCDS-V1 §9).';
