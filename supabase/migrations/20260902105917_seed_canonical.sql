-- SAQ-MCDS-V1 §28 + SAQ-CLAUDE-PHASE1-PROMPT-V1 Paquete Inline A2-A5 · 0013_seed_canonical
-- Proyecto, futbol, fuentes y catalogos DRAFT; sin umbrales de promocion.
-- Ningun catalogo queda ACTIVE por defecto salvo lo explicitamente autorizado (FOOTBALL, v1.0 §3).
-- Nota de fidelidad: los "tiers" cualitativos del paquete inline (CORE_RESEARCH,
-- CHALLENGER_MARKET_RESEARCH, PASSIVE_WATCHLIST, etc.) no tienen columna fisica dedicada en el
-- inventario cerrado de 36 tablas; se seedan status=DRAFT (unico campo fisico de gobierno de
-- catalogo disponible) y el tier queda documentado solo en comentarios, no como dato persistido.

-- Proyecto base.
insert into cfg.projects (project_key, name, base_currency, display_timezone, status)
values ('agente-quant-bot', 'AGENTE-QUANT-BOT', 'USD', 'UTC', 'ACTIVE'::app.project_status);

-- Fuentes (SAQ-IB-V1 §6): The Odds API, API-Football y user/official. enabled=false por defecto.
insert into cfg.data_sources (project_id, source_key, source_type, display_name, authority_scope, adapter_version, enabled)
select p.project_id, v.source_key, v.source_type, v.display_name, v.authority_scope, v.adapter_version, false
from cfg.projects p
cross join (values
  ('the_odds_api', 'ODDS', 'The Odds API', array['ODDS']::text[], 'v1'),
  ('api_football', 'SPORTS_DATA', 'API-Football', array['SCHEDULE','RESULT']::text[], 'v1'),
  ('user', 'OFFICIAL_RESULT', 'Usuario / fuente oficial', array['RESULT']::text[], 'v1')
) as v(source_key, source_type, display_name, authority_scope, adapter_version)
where p.project_key = 'agente-quant-bot';

-- Deporte: FOOTBALL conforme A3; unico deporte autorizado ACTIVE en V1 (SAQ-IB-V1 §3/§6).
insert into cfg.sports (project_id, sport_key, display_name, adapter_version, research_mode, status)
select p.project_id, 'FOOTBALL', 'Football', 'v1', true, 'ACTIVE'::app.catalog_status
from cfg.projects p where p.project_key = 'agente-quant-bot';

-- A3 LEAGUES -- todas status=DRAFT (paquete inline A2-A5).
insert into core.competitions (project_id, sport_id, canonical_name, country_code, competition_type, status)
select p.project_id, s.sport_id, v.canonical_name, v.country_code, 'LEAGUE', 'DRAFT'::app.catalog_status
from cfg.projects p
join cfg.sports s on s.project_id = p.project_id and s.sport_key = 'FOOTBALL'
cross join (values
  ('Premier League', 'EN'),  -- CORE_RESEARCH
  ('La Liga', 'ES'),         -- CORE_RESEARCH
  ('Serie A', 'IT'),         -- CORE_RESEARCH
  ('Bundesliga', 'DE'),      -- CHALLENGER_RESEARCH
  ('Ligue 1', 'FR'),         -- CHALLENGER_RESEARCH
  ('Eredivisie', 'NL'),      -- PASSIVE_WATCHLIST
  ('Primeira Liga', 'PT')    -- PASSIVE_WATCHLIST
) as v(canonical_name, country_code)
where p.project_key = 'agente-quant-bot';

-- A4 MARKETS -- todos status=DRAFT (paquete inline A2-A5); linea 2.5 para totals fijo, resto sin linea unica.
insert into cfg.market_contracts (project_id, sport_id, contract_key, market_family, status)
select p.project_id, s.sport_id, v.contract_key, v.market_family, 'DRAFT'::app.catalog_status
from cfg.projects p
join cfg.sports s on s.project_id = p.project_id and s.sport_key = 'FOOTBALL'
cross join (values
  ('FT_TOTAL_GOALS_2_5', 'TOTAL_GOALS'),   -- CORE_MARKET_RESEARCH
  ('FT_1X2', '1X2'),                       -- CHALLENGER_MARKET_RESEARCH
  ('FT_BTTS', 'BTTS'),                     -- CHALLENGER_MARKET_RESEARCH
  ('FT_ASIAN_TOTALS_WL', 'ASIAN_TOTALS'),  -- PASSIVE_MARKET_WATCHLIST
  ('FT_AH_WL', 'AH')                       -- PASSIVE_MARKET_WATCHLIST
) as v(contract_key, market_family)
where p.project_key = 'agente-quant-bot';

-- Versiones normativas DRAFT de cada contrato; approved_at queda NULL (ningun mercado se activa).
insert into cfg.market_contract_versions (
  project_id, market_contract_id, semantic_version, period, unit,
  line_schema, selection_schema, payoff_rule, void_policy, active_from, config_hash
)
select
  p.project_id, mc.market_contract_id, '0.1.0-draft', 'MATCH', v.unit,
  v.line_schema, v.selection_schema, v.payoff_rule, '{}'::jsonb, clock_timestamp(),
  encode(public.digest(mc.contract_key || ':0.1.0-draft', 'sha256'), 'hex')
from cfg.projects p
join cfg.market_contracts mc on mc.project_id = p.project_id
join (values
  ('FT_TOTAL_GOALS_2_5', 'GOALS',
    '{"min":2.5,"max":2.5,"step":0.5,"nullable":false}'::jsonb,
    '{"sides":["OVER","UNDER"]}'::jsonb,
    '{"type":"TOTALS","description":"payoff unitario segun SAQ-CC-V1 §14"}'::jsonb),
  ('FT_1X2', 'POINTS',
    '{"nullable":true}'::jsonb,
    '{"sides":["HOME","DRAW","AWAY"]}'::jsonb,
    '{"type":"MONEYLINE","description":"payoff unitario segun SAQ-CC-V1 §14"}'::jsonb),
  ('FT_BTTS', 'GOALS',
    '{"nullable":true}'::jsonb,
    '{"sides":["YES","NO"]}'::jsonb,
    '{"type":"BINARY","description":"payoff unitario segun SAQ-CC-V1 §14"}'::jsonb),
  ('FT_ASIAN_TOTALS_WL', 'GOALS',
    '{"min":2.0,"max":3.0,"step":0.25,"nullable":false}'::jsonb,
    '{"sides":["OVER","UNDER"]}'::jsonb,
    '{"type":"ASIAN_TOTALS","description":"descomposicion de cuartos segun SAQ-CC-V1 §15"}'::jsonb),
  ('FT_AH_WL', 'GOALS',
    '{"min":-1.0,"max":1.0,"step":0.25,"nullable":false}'::jsonb,
    '{"sides":["HOME","AWAY"]}'::jsonb,
    '{"type":"ASIAN_HANDICAP","description":"descomposicion de cuartos segun SAQ-CC-V1 §15; FUTURO tras Settlement Engine (SAQ-CC-V1 §16)"}'::jsonb)
) as v(contract_key, unit, line_schema, selection_schema, payoff_rule) on v.contract_key = mc.contract_key
where p.project_key = 'agente-quant-bot';

-- A5 ROSTER -- status=DRAFT, effective_weight=0 (peso efectivo se aplica en devig/consenso, no en
-- esta tabla; bookmakers.role solo admite EXECUTION_BOOK/SENSOR/BOTH, mas fino que el A5 original).
insert into market.bookmakers (project_id, bookmaker_key, display_name, region, role, independence_group, status)
select p.project_id, v.bookmaker_key, v.display_name, v.region, v.role, v.independence_group, 'DRAFT'::app.catalog_status
from cfg.projects p
cross join (values
  ('onexbet',      '1xBet',              'GLOBAL', 'EXECUTION_BOOK', null),
  ('pinnacle',     'Pinnacle',           'GLOBAL', 'SENSOR', 'ORIGIN_PINNACLE'),
  ('betfair_ex_eu','Betfair Exchange EU','EU',     'SENSOR', 'ORIGIN_BETFAIR_EXCHANGE'),
  ('betfair_ex_uk','Betfair Exchange UK','UK',     'SENSOR', 'ORIGIN_BETFAIR_EXCHANGE'),
  ('matchbook',    'Matchbook',          'GLOBAL', 'SENSOR', 'ORIGIN_MATCHBOOK_EXCHANGE'),
  ('betonlineag',  'BetOnline',          'GLOBAL', 'SENSOR', 'ORIGIN_BETONLINE'),
  ('betvictor',    'BetVictor',          'GLOBAL', 'SENSOR', 'ORIGIN_BETVICTOR'),
  ('betclic_fr',   'Betclic',            'FR',     'SENSOR', 'ORIGIN_BETCLIC'),
  ('betsson',      'Betsson',            'GLOBAL', 'SENSOR', 'ORIGIN_BETSSON_GROUP'),
  ('nordicbet',    'NordicBet',          'GLOBAL', 'SENSOR', 'ORIGIN_BETSSON_GROUP'),
  ('unibet',       'Unibet',             'GLOBAL', 'SENSOR', 'ORIGIN_FDJ_UNIBET'),
  ('sport888',     '888sport',           'GLOBAL', 'SENSOR', 'ORIGIN_EVOKE'),
  ('williamhill',  'William Hill',       'GLOBAL', 'SENSOR', 'ORIGIN_EVOKE'),
  ('winamax_fr',   'Winamax FR',         'FR',     'SENSOR', 'ORIGIN_WINAMAX'),
  ('winamax_de',   'Winamax DE',         'DE',     'SENSOR', 'ORIGIN_WINAMAX')
) as v(bookmaker_key, display_name, region, role, independence_group)
where p.project_key = 'agente-quant-bot';

-- Policy version DRAFT con los gates A2 (frescura/TTL) y las constantes A5 (consenso/devig)
-- del paquete inline; approved_at NULL -- ningun umbral queda activo (SAQ-IB-V1 §4).
insert into cfg.policy_versions (project_id, policy_key, semantic_version, stage, config, config_hash, active_from)
select
  p.project_id, 'a2_freshness_and_a5_consensus_gates', '0.1.0-draft', 'RESEARCH'::app.model_stage,
  '{
    "a2_odds_prematch_featured": {
      "gt_24h":  {"soft_min":"10m","hard_min":"20m","state_min":"60m","ttl_min":"5m"},
      "6h_24h":  {"soft_min":"5m","hard_min":"10m","state_min":"30m","ttl_min":"5m"},
      "1h_6h":   {"soft_min":"3m","hard_min":"5m","state_min":"15m","ttl_min":"3m"},
      "15m_60m": {"soft_min":"2m","hard_min":"3m","state_min":"8m","ttl_min":"90s"},
      "lt_15m":  "NO_NEW_SIGNAL"
    },
    "a2_fixture": {
      "gt_24h":  {"soft_min":"6h","hard_min":"12h"},
      "6h_24h":  {"soft_min":"2h","hard_min":"4h"},
      "1h_6h":   {"soft_min":"30m","hard_min":"60m"},
      "15m_60m": {"soft_min":"10m","hard_min":"20m"},
      "lt_15m":  {"soft_min":"5m","hard_min":"10m","state":"NO_NEW_SIGNAL"}
    },
    "a2_player_availability": {
      "gt_24h":"6h/12h","6h_24h":"2h/4h","1h_6h":"30m/60m","15m_60m":"10m/20m","lt_15m":"5m/10m NO_NEW_SIGNAL"
    },
    "a2_lineup": {
      "unpublished":"UNAVAILABLE","le_5m":"PASS","5m_10m":"WATCH","gt_10m":"BLOCKED","on_change":"CORRECTED+replay"
    },
    "a2_hist_form_standings": {"soft_min":"24h","hard_min":"48h","mapping_revalidate_days":30},
    "a2_result": {"le_5m":"PROVISIONAL","le_60m":"finalizable","gt_24h":"UNKNOWN+DQE"},
    "a2_execution": {"missing_placed_at_or_actual_odds":"UNKNOWN"},
    "a2_default": "UNAVAILABLE/EXPERIMENTAL",
    "a5_constants": {
      "method":"MC-POWER-LOGPOOL-V1.0",
      "closing":"CLOSE-PREMATCH-5M-G30S-V1.0",
      "devig":"POWER",
      "devig_shadow":"multiplicative",
      "pool":"weighted_log",
      "min_groups":5,
      "max_group_weight":0.30,
      "min_n_eff":4.0,
      "primary":"Pinnacle+>=1 native_exchange",
      "fallback":"exactly_one_anchor",
      "binary_range80_max":0.080,
      "weighted_mad_max":0.025,
      "method_gap_max":0.030,
      "close_primary_window":"[cutoff-5m,cutoff]",
      "proxy_window":"[cutoff-10m,cutoff-5m)",
      "guard_seconds":30,
      "market_clv_formula":"actual_odds*p_consensus_close-1",
      "execution_clv_formula":"actual_odds/same_book_close_odds-1"
    }
  }'::jsonb,
  encode(public.digest('a2_freshness_and_a5_consensus_gates:0.1.0-draft', 'sha256'), 'hex'),
  clock_timestamp()
from cfg.projects p where p.project_key = 'agente-quant-bot';
