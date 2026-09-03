-- SAQ-MCDS-V1 §19, §20, §23 + SAQ-MCDS-V1.1-APPROVED §4 · 0009_constraints_and_triggers
-- 9 funciones v1.0 reutilizadas + 6 funciones NEW_IN_V1_1_TRIGGER_SUPPORT (REV3) + 31 instancias de trigger.
-- No se agregan tablas, columnas, schemas, RPC ni funciones nuevas respecto al inventario cerrado.

-- =====================================================================
-- 1. Funciones v1.0 (SAQ-MCDS-V1 §23)
-- =====================================================================

-- app.current_project_ids(): memberships activas del usuario autenticado.
-- SECURITY DEFINER privada; no se expone en el schema api (no llega a Data API).
-- EXECUTE se concede a authenticated porque las policies RLS la invocan como ese rol;
-- revocarla de authenticated (lectura literal de Apendice B.6) rompe toda policy que la use.
create function app.current_project_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select pm.project_id
  from cfg.project_members pm
  where pm.user_id = auth.uid()
    and pm.status = 'ACTIVE'::app.membership_status;
$$;
revoke execute on function app.current_project_ids() from public, anon;
grant execute on function app.current_project_ids() to authenticated;

-- app.has_project_role(project_id, roles): helper RLS. Ver nota de current_project_ids().
create function app.has_project_role(p_project_id uuid, p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from cfg.project_members pm
    where pm.project_id = p_project_id
      and pm.user_id = auth.uid()
      and pm.status = 'ACTIVE'::app.membership_status
      and pm.member_role::text = any (p_roles)
  );
$$;
revoke execute on function app.has_project_role(uuid, text[]) from public, anon;
grant execute on function app.has_project_role(uuid, text[]) to authenticated;

-- app.forbid_mutation(): bloquea UPDATE/DELETE en objetos append-only. Reutilizada en 15 tablas.
create function app.forbid_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'append_only_violation: % en %.% no esta permitido (SAQ-MCDS-V1 §11/§20)',
    TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME
    using errcode = '23000';
end;
$$;

-- app.validate_temporal_gate(): impide leakage temporal en model.predictions (instancia 16).
-- Trigger BEFORE INSERT ordinario (REV1/REV2: un CONSTRAINT TRIGGER de PostgreSQL exige AFTER,
-- no BEFORE; model.predictions es solo-insercion, un BEFORE INSERT ordinario basta).
-- Nota (REV3 §4.5 instancia 16): el registro de DataQualityEvent(LEAKAGE_RISK) exigido por
-- SAQ-CC-V1 §10 corresponde a la capa que captura la excepcion (RPC/servicio), no a este
-- trigger, porque la fila no puede persistir dentro de una transaccion que se esta rechazando.
create function app.validate_temporal_gate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_run_cutoff timestamptz;
  v_snapshot_as_of timestamptz;
  v_snapshot_available timestamptz;
begin
  select data_cutoff_at into v_run_cutoff
  from model.model_runs
  where model_run_id = NEW.model_run_id;

  select as_of_at, available_for_model_at into v_snapshot_as_of, v_snapshot_available
  from model.feature_snapshots
  where feature_snapshot_id = NEW.feature_snapshot_id;

  if v_run_cutoff is null or v_snapshot_as_of is null then
    raise exception 'temporal_gate_missing_reference: model_run % o feature_snapshot % no existen',
      NEW.model_run_id, NEW.feature_snapshot_id;
  end if;

  if v_run_cutoff > NEW.decision_at
     or v_snapshot_as_of > NEW.decision_at
     or v_snapshot_available > NEW.decision_at then
    raise exception 'temporal_gate_violation: leakage risk para prediction % (SAQ-CC-V1 §10, SAQ-MCDS-V1 §10)',
      NEW.prediction_id;
  end if;

  return NEW;
end;
$$;

-- app.validate_state_transition(): valida transiciones de execution_status en ops.execution_events.
-- Alcance implementado (instancia 19): (a) el from_status declarado debe coincidir con el
-- execution_status vigente de la ejecucion referenciada -- rechaza transiciones "no publicadas"
-- en el sentido de no reflejar el estado real; (b) UNKNOWN nunca se abandona sin evidencia
-- (SAQ-CC-V1 §7 invariante). No existe en ningun documento normativo adjunto una matriz cerrada
-- y literal de pares (from_status, to_status) permitidos para execution_status; por disciplina
-- de "no inferir", este trigger no reconstruye esa matriz -- queda documentado como decision
-- abierta en el informe final, no como supuesto.
create function app.validate_state_transition()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_current app.execution_status;
begin
  select execution_status into v_current
  from ops.executions
  where execution_id = NEW.execution_id;

  if v_current is null then
    raise exception 'state_transition_unknown_execution: execution % no existe', NEW.execution_id;
  end if;

  if NEW.from_status is not null and NEW.from_status is distinct from v_current then
    raise exception 'state_transition_stale: from_status % declarado no coincide con execution_status % vigente de execution % (SAQ-MCDS-V1 §20)',
      NEW.from_status, v_current, NEW.execution_id;
  end if;

  if coalesce(NEW.from_status, 'UNKNOWN'::app.execution_status) = 'UNKNOWN'::app.execution_status
     and NEW.to_status <> 'UNKNOWN'::app.execution_status
     and (NEW.evidence is null or NEW.evidence = '{}'::jsonb) then
    raise exception 'state_transition_unknown_requires_evidence: salir de UNKNOWN sin evidencia no esta permitido para execution % (SAQ-CC-V1 §7)',
      NEW.execution_id;
  end if;

  return NEW;
end;
$$;

-- app.compute_settlement(): recalcula/valida net_return y payout segun el payoff unitario
-- cerrado de SAQ-CC-V1 §14. La clasificacion WIN/HALF_WIN/PUSH/... (incluida la descomposicion
-- de lineas asiaticas de cuarto, §15) es responsabilidad del Settlement Engine antes del INSERT;
-- este trigger solo verifica que la aritmetica declarada sea exacta para el estado ya asignado.
create function app.compute_settlement()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_expected numeric(18,6);
begin
  case NEW.settlement_status
    when 'WIN' then
      v_expected := NEW.stake * (NEW.price - 1);
    when 'HALF_WIN' then
      v_expected := 0.5 * NEW.stake * (NEW.price - 1);
    when 'PUSH' then
      v_expected := 0;
    when 'HALF_LOSS' then
      v_expected := -0.5 * NEW.stake;
    when 'LOSS' then
      v_expected := -NEW.stake;
    when 'VOID' then
      v_expected := 0;
    when 'PENDING', 'UNKNOWN', 'DISPUTED' then
      v_expected := 0;
    when 'PARTIAL_VOID' then
      raise exception 'settlement_partial_void_not_configured: % requiere una fraccion de void definida explicitamente en el contrato; SAQ-CC-V1 §14 no fija una formula generica y ningun addendum V1 la publica todavia',
        NEW.settlement_id;
    when 'CORRECTED' then
      v_expected := NEW.net_return; -- estado administrativo de correccion; se exige solo consistencia interna
    else
      raise exception 'settlement_status_unhandled: % no tiene formula de payoff definida (SAQ-CC-V1 §14)', NEW.settlement_status;
  end case;

  if NEW.net_return is distinct from v_expected then
    raise exception 'settlement_payoff_mismatch: se esperaba % y se recibio % para estado % (SAQ-CC-V1 §14)',
      v_expected, NEW.net_return, NEW.settlement_status;
  end if;

  if NEW.payout is distinct from (NEW.stake + NEW.net_return) then
    raise exception 'settlement_payout_mismatch: payout debe ser igual a stake + net_return (settlement %)', NEW.settlement_id;
  end if;

  return NEW;
end;
$$;

-- app.create_monthly_partitions(): job opcional. SAQ-MCDS-V1 §22 deja el diseno preparado para
-- particion mensual mientras la activacion se prueba en una migracion separada; ninguna tabla
-- V1 esta particionada todavia, por lo que este job es un no-op documentado, no programado
-- por pg_cron sin verificar antes su disponibilidad.
create function app.create_monthly_partitions()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise notice 'create_monthly_partitions: no-op -- ninguna tabla V1 esta particionada todavia (SAQ-MCDS-V1 §22)';
end;
$$;
revoke execute on function app.create_monthly_partitions() from public, anon, authenticated;
grant execute on function app.create_monthly_partitions() to service_role;

-- app.expire_signals(): job idempotente. Marca EXPIRED por TTL; nunca crea NOT_PLACED
-- (SAQ-MCDS-V1 §23; ops.signals no es append-only, ver SAQ-MCDS-V1.1-APPROVED §4.5).
create function app.expire_signals()
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_count integer;
begin
  update ops.signals
  set signal_status = 'EXPIRED'::app.signal_status
  where signal_status in ('GENERATED','APPROVED','SENT_TELEGRAM')
    and expiration_at <= clock_timestamp();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function app.expire_signals() from public, anon, authenticated;
grant execute on function app.expire_signals() to service_role;

-- app.refresh_operational_views(): job opcional. Solo materialized views aprobadas; V1 expone
-- unicamente views planas con security_invoker (SAQ-MCDS-V1 §23/§25), por lo que es un no-op.
create function app.refresh_operational_views()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise notice 'refresh_operational_views: no-op -- V1 no tiene materialized views aprobadas (SAQ-MCDS-V1 §23)';
end;
$$;
revoke execute on function app.refresh_operational_views() from public, anon, authenticated;
grant execute on function app.refresh_operational_views() to service_role;

-- =====================================================================
-- 2. Funciones NEW_IN_V1_1_TRIGGER_SUPPORT (SAQ-MCDS-V1.1-APPROVED §4.3)
-- =====================================================================

-- A. app.validate_selection_line_schema(): cierra la primera clausula de la fila "Linea" de §20.
-- El contenido literal de line_schema (escala/precision/lineas permitidas) no se publica como
-- un esquema JSON cerrado en ningun documento adjunto; se implementa contra las claves
-- auto-descriptivas min/max/step/nullable, documentado como decision de interpretacion.
create function app.validate_selection_line_schema()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_schema jsonb;
begin
  select line_schema into v_schema
  from cfg.market_contract_versions
  where market_contract_version_id = NEW.market_contract_version_id;

  if NEW.line is null then
    if v_schema is not null and coalesce((v_schema ->> 'nullable')::boolean, false) is distinct from true then
      raise exception 'selection_line_null_not_allowed: market_contract_version % no admite linea nula (SAQ-MCDS-V1 §20)',
        NEW.market_contract_version_id;
    end if;
    return NEW;
  end if;

  if v_schema is null then
    raise exception 'selection_line_schema_missing: market_contract_version % no tiene line_schema pero selection % declara una linea',
      NEW.market_contract_version_id, NEW.selection_id;
  end if;

  if v_schema ? 'min' and NEW.line < (v_schema ->> 'min')::numeric then
    raise exception 'selection_line_below_min: % < % (market_contract_version %)', NEW.line, v_schema ->> 'min', NEW.market_contract_version_id;
  end if;

  if v_schema ? 'max' and NEW.line > (v_schema ->> 'max')::numeric then
    raise exception 'selection_line_above_max: % > % (market_contract_version %)', NEW.line, v_schema ->> 'max', NEW.market_contract_version_id;
  end if;

  if v_schema ? 'step' and (v_schema ->> 'step')::numeric > 0
     and mod(NEW.line - coalesce((v_schema ->> 'min')::numeric, 0::numeric), (v_schema ->> 'step')::numeric) <> 0 then
    raise exception 'selection_line_off_step: % no esta alineada al step % (market_contract_version %)',
      NEW.line, v_schema ->> 'step', NEW.market_contract_version_id;
  end if;

  return NEW;
end;
$$;

-- B. app.validate_odds_snapshot_line_consistency(): cierra la segunda clausula de "Linea" de §20.
create function app.validate_odds_snapshot_line_consistency()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_selection_line app.line_t;
begin
  select line into v_selection_line
  from market.selections
  where selection_id = NEW.selection_id;

  if NEW.line is distinct from v_selection_line then
    raise exception 'odds_snapshot_line_mismatch: % difiere de la linea % de la selection % (SAQ-MCDS-V1 §20)',
      NEW.line, v_selection_line, NEW.selection_id;
  end if;

  return NEW;
end;
$$;

-- C. app.validate_bet_placed_fields(): cierra "BET_PLACED -- CHECK diferido" de §20.
-- CONSTRAINT TRIGGER AFTER, DEFERRABLE INITIALLY DEFERRED (Postgres no admite CHECK DEFERRABLE).
create function app.validate_bet_placed_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if NEW.execution_status = 'BET_PLACED'::app.execution_status then
    if NEW.actual_odds is null or NEW.accepted_stake is null or NEW.placed_at is null then
      raise exception 'bet_placed_fields_incomplete: execution % marcada BET_PLACED sin actual_odds/accepted_stake/placed_at completos (SAQ-MCDS-V1 §20)',
        NEW.execution_id;
    end if;
  end if;
  return NEW;
end;
$$;

-- D. app.validate_mapping_target_entity(): cierra §19 para source_entity_mappings.
create function app.validate_mapping_target_entity()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  case NEW.entity_type
    when 'SPORT' then
      select exists (select 1 from cfg.sports where sport_id = NEW.canonical_entity_id) into v_found;
    when 'COMPETITION' then
      select exists (select 1 from core.competitions where competition_id = NEW.canonical_entity_id) into v_found;
    when 'SEASON' then
      select exists (select 1 from core.seasons where season_id = NEW.canonical_entity_id) into v_found;
    when 'PARTICIPANT' then
      select exists (select 1 from core.participants where participant_id = NEW.canonical_entity_id) into v_found;
    when 'EVENT' then
      select exists (select 1 from core.events where event_id = NEW.canonical_entity_id) into v_found;
    when 'BOOKMAKER' then
      select exists (select 1 from market.bookmakers where bookmaker_id = NEW.canonical_entity_id) into v_found;
    else
      raise exception 'mapping_entity_type_not_whitelisted: % no pertenece a la whitelist cerrada (SAQ-MCDS-V1 §19)', NEW.entity_type;
  end case;

  if not v_found then
    raise exception 'mapping_target_entity_missing: % % no existe (mapping %)', NEW.entity_type, NEW.canonical_entity_id, NEW.mapping_id;
  end if;

  return NEW;
end;
$$;

-- E. app.validate_data_quality_event_entity(): mapa cerrado de 36 correspondencias
-- schema.tabla -> columna PK (SAQ-MCDS-V1.1-APPROVED §4.3.E). SECURITY DEFINER; resuelve
-- exclusivamente contra el CASE literal siguiente, nunca contra information_schema/pg_catalog.
-- Identificadores via format()+%I; entity_id exclusivamente via USING; search_path vacio;
-- propietario = rol de migracion; EXECUTE revocado a PUBLIC/anon/authenticated, concedido
-- unicamente a service_role (unico rol que escribe en ops.data_quality_events, SAQ-MCDS-V1 §24).
create function app.validate_data_quality_event_entity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pk_column text;
  v_exists boolean;
  v_key text := NEW.entity_schema || '.' || NEW.entity_table;
begin
  v_pk_column := case v_key
    when 'cfg.projects' then 'project_id'
    when 'cfg.project_members' then null -- PK compuesta, ver excepcion abajo
    when 'cfg.data_sources' then 'data_source_id'
    when 'cfg.sports' then 'sport_id'
    when 'cfg.market_contracts' then 'market_contract_id'
    when 'cfg.market_contract_versions' then 'market_contract_version_id'
    when 'cfg.model_registry' then 'model_id'
    when 'cfg.policy_versions' then 'policy_version_id'
    when 'raw.api_requests' then 'request_id'
    when 'raw.payloads' then 'raw_payload_id'
    when 'core.competitions' then 'competition_id'
    when 'core.seasons' then 'season_id'
    when 'core.participants' then 'participant_id'
    when 'core.source_entity_mappings' then 'mapping_id'
    when 'core.events' then 'event_id'
    when 'core.event_versions' then 'event_version_id'
    when 'market.bookmakers' then 'bookmaker_id'
    when 'market.selections' then 'selection_id'
    when 'market.odds_snapshots' then 'odds_snapshot_id'
    when 'market.consensus_snapshots' then 'consensus_snapshot_id'
    when 'market.consensus_components' then null -- PK compuesta, ver excepcion abajo
    when 'market.closing_lines' then 'closing_line_id'
    when 'model.feature_snapshots' then 'feature_snapshot_id'
    when 'model.model_runs' then 'model_run_id'
    when 'model.predictions' then 'prediction_id'
    when 'model.evaluation_runs' then 'evaluation_run_id'
    when 'model.metric_results' then 'metric_result_id'
    when 'ops.signals' then 'signal_id'
    when 'ops.signal_deliveries' then 'signal_delivery_id'
    when 'ops.executions' then 'execution_id'
    when 'ops.execution_events' then 'execution_event_id'
    when 'ops.settlements' then 'settlement_id'
    when 'ops.bankroll_ledger' then 'bankroll_entry_id'
    when 'ops.portfolio_exposures' then 'portfolio_exposure_id'
    when 'ops.data_quality_events' then 'data_quality_event_id'
    when 'ops.audit_events' then 'audit_event_id'
    else '__NOT_MAPPED__'
  end;

  if v_key in ('cfg.project_members', 'market.consensus_components') then
    raise exception 'data_quality_event_entity_composite_pk: % no admite referencia mediante entity_id de columna unica (SAQ-MCDS-V1.1-APPROVED §4.3.E)', v_key;
  end if;

  if v_pk_column is null or v_pk_column = '__NOT_MAPPED__' then
    raise exception 'data_quality_event_entity_not_mapped: % no coincide exactamente con ninguna de las 36 filas del mapa cerrado (SAQ-MCDS-V1.1-APPROVED §4.3.E)', v_key;
  end if;

  execute format('select exists (select 1 from %I.%I where %I = $1)', NEW.entity_schema, NEW.entity_table, v_pk_column)
    using NEW.entity_id
    into v_exists;

  if not v_exists then
    raise exception no_data_found using message = format('data_quality_event_entity_missing: %s.%s = %s no existe', v_key, v_pk_column, NEW.entity_id);
  end if;

  return NEW;
end;
$$;
revoke execute on function app.validate_data_quality_event_entity() from public, anon, authenticated;
grant execute on function app.validate_data_quality_event_entity() to service_role;

-- F. app.forbid_supersedes_cycle(): cierra §19 (ciclos supersedes_* imposibles).
-- Reutilizada en 8 tablas via TG_ARGV[0]=columna supersedes_*, TG_ARGV[1]=columna PK.
create function app.forbid_supersedes_cycle()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_supersedes_col text := TG_ARGV[0];
  v_pk_col text := TG_ARGV[1];
  v_supersedes_id uuid;
  v_pk_id uuid;
  v_current uuid;
  v_depth integer := 0;
  v_row jsonb := to_jsonb(NEW);
begin
  v_supersedes_id := nullif(v_row ->> v_supersedes_col, '')::uuid;
  v_pk_id := nullif(v_row ->> v_pk_col, '')::uuid;

  if v_supersedes_id is null then
    return NEW;
  end if;

  if v_supersedes_id = v_pk_id then
    raise exception 'supersedes_self_reference: %.%.% no puede supersederse a si misma (%) (SAQ-MCDS-V1 §19)',
      TG_TABLE_SCHEMA, TG_TABLE_NAME, v_pk_col, v_pk_id;
  end if;

  v_current := v_supersedes_id;
  loop
    v_depth := v_depth + 1;
    if v_depth > 100000 then
      raise exception 'supersedes_chain_too_long: cadena sospechosa en %.% desde % (SAQ-MCDS-V1 §19)',
        TG_TABLE_SCHEMA, TG_TABLE_NAME, v_pk_id;
    end if;

    if v_current = v_pk_id then
      raise exception 'supersedes_cycle_detected: %.% forma un ciclo desde % (SAQ-MCDS-V1 §19)',
        TG_TABLE_SCHEMA, TG_TABLE_NAME, v_pk_id;
    end if;

    execute format('select %I from %I.%I where %I = $1', v_supersedes_col, TG_TABLE_SCHEMA, TG_TABLE_NAME, v_pk_col)
      using v_current
      into v_current;

    exit when v_current is null;
  end loop;

  return NEW;
end;
$$;

-- =====================================================================
-- 3. Inventario cerrado de 31 instancias de trigger (SAQ-MCDS-V1.1-APPROVED §4.4, Tabla 1)
-- =====================================================================

-- Bloqueo append-only (15 instancias, #1-#15)
create trigger api_requests_no_mutation before update or delete on raw.api_requests
  for each row execute function app.forbid_mutation();

create trigger payloads_no_mutation before update or delete on raw.payloads
  for each row execute function app.forbid_mutation();

create trigger event_versions_no_mutation before update or delete on core.event_versions
  for each row execute function app.forbid_mutation();

create trigger odds_snapshots_no_mutation before update or delete on market.odds_snapshots
  for each row execute function app.forbid_mutation();

create trigger consensus_snapshots_no_mutation before update or delete on market.consensus_snapshots
  for each row execute function app.forbid_mutation();

create trigger feature_snapshots_no_mutation before update or delete on model.feature_snapshots
  for each row execute function app.forbid_mutation();

create trigger model_runs_no_mutation before update or delete on model.model_runs
  for each row execute function app.forbid_mutation();

create trigger predictions_no_mutation before update or delete on model.predictions
  for each row execute function app.forbid_mutation();

create trigger execution_events_no_mutation before update or delete on ops.execution_events
  for each row execute function app.forbid_mutation();

create trigger settlements_no_mutation before update or delete on ops.settlements
  for each row execute function app.forbid_mutation();

create trigger bankroll_ledger_no_mutation before update or delete on ops.bankroll_ledger
  for each row execute function app.forbid_mutation();

create trigger audit_events_no_mutation before update or delete on ops.audit_events
  for each row execute function app.forbid_mutation();

create trigger market_contract_versions_no_mutation before update or delete on cfg.market_contract_versions
  for each row execute function app.forbid_mutation();

create trigger policy_versions_no_mutation before update or delete on cfg.policy_versions
  for each row execute function app.forbid_mutation();

create trigger selections_no_mutation before update or delete on market.selections
  for each row execute function app.forbid_mutation();

-- Compuerta temporal / anti-leakage (#16)
create trigger predictions_temporal_gate before insert on model.predictions
  for each row execute function app.validate_temporal_gate();

-- Consistencia de linea (#17-#18)
create trigger selections_line_schema_check before insert on market.selections
  for each row execute function app.validate_selection_line_schema();

create trigger odds_snapshots_line_consistency before insert on market.odds_snapshots
  for each row execute function app.validate_odds_snapshot_line_consistency();

-- Transicion de estado (#19)
create trigger execution_events_state_transition before insert on ops.execution_events
  for each row execute function app.validate_state_transition();

-- Computo determinista de settlement (#20)
create trigger settlements_compute_payoff before insert on ops.settlements
  for each row execute function app.compute_settlement();

-- BET_PLACED -- chequeo diferido (#21)
create constraint trigger executions_bet_placed_fields_check
  after insert or update on ops.executions
  deferrable initially deferred
  for each row execute function app.validate_bet_placed_fields();

-- Validacion polimorfica de FK (#22-#23)
create trigger source_entity_mappings_target_entity_check before insert or update on core.source_entity_mappings
  for each row execute function app.validate_mapping_target_entity();

create trigger data_quality_events_entity_check before insert on ops.data_quality_events
  for each row execute function app.validate_data_quality_event_entity();

-- Prevencion de ciclos supersedes_* (8 instancias, #24-#31)
create trigger market_contract_versions_supersedes_cycle_check before insert or update on cfg.market_contract_versions
  for each row execute function app.forbid_supersedes_cycle('supersedes_version_id', 'market_contract_version_id');

create trigger policy_versions_supersedes_cycle_check before insert or update on cfg.policy_versions
  for each row execute function app.forbid_supersedes_cycle('supersedes_policy_version_id', 'policy_version_id');

create trigger source_entity_mappings_supersedes_cycle_check before insert or update on core.source_entity_mappings
  for each row execute function app.forbid_supersedes_cycle('supersedes_mapping_id', 'mapping_id');

create trigger event_versions_supersedes_cycle_check before insert or update on core.event_versions
  for each row execute function app.forbid_supersedes_cycle('supersedes_event_version_id', 'event_version_id');

create trigger predictions_supersedes_cycle_check before insert or update on model.predictions
  for each row execute function app.forbid_supersedes_cycle('supersedes_prediction_id', 'prediction_id');

create trigger signals_supersedes_cycle_check before insert or update on ops.signals
  for each row execute function app.forbid_supersedes_cycle('supersedes_signal_id', 'signal_id');

create trigger executions_supersedes_cycle_check before insert or update on ops.executions
  for each row execute function app.forbid_supersedes_cycle('supersedes_execution_id', 'execution_id');

create trigger settlements_supersedes_cycle_check before insert or update on ops.settlements
  for each row execute function app.forbid_supersedes_cycle('supersedes_settlement_id', 'settlement_id');
