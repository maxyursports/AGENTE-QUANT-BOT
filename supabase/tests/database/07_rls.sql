-- SAQ-MCDS-V1 §29 (07_rls): allow/deny por anon y cada rol.
-- Sin acceso cruzado entre proyectos (SAQ-MCDS-V1 §24, Apendice B.3).
begin;
select plan(8);

-- Segundo proyecto ("B") para probar aislamiento cruzado frente al proyecto seed ("A").
insert into cfg.projects (project_key, name, base_currency, display_timezone, status)
values ('rls-test-project-b', 'RLS Test Project B', 'USD', 'UTC', 'ACTIVE'::app.project_status);

-- Dos usuarios de auth.users: uno con membership ACTIVE en A, otro sin membership en ningun lado.
insert into auth.users (id) values ('11111111-1111-1111-1111-111111111111'), ('22222222-2222-2222-2222-222222222222');

insert into cfg.project_members (project_id, user_id, member_role, status)
select project_id, '11111111-1111-1111-1111-111111111111'::uuid, 'VIEWER'::app.member_role, 'ACTIVE'::app.membership_status
from cfg.projects where project_key = 'agente-quant-bot';

insert into core.competitions (project_id, sport_id, canonical_name, competition_type, status)
select (select project_id from cfg.projects where project_key='rls-test-project-b'),
       (select sport_id from cfg.sports where project_id = (select project_id from cfg.projects where project_key='agente-quant-bot') limit 1),
       'Competicion solo de B', 'LEAGUE', 'DRAFT'::app.catalog_status;

-- anon: sin USAGE en el schema cfg -- la consulta falla por permisos, ni siquiera llega a RLS.
select throws_ok(
  $$ set local role anon; select count(*) from cfg.projects; $$,
  '42501', null, 'anon no tiene ni USAGE sobre cfg (permission denied)'
);
reset role;

-- authenticated + membership ACTIVE en el proyecto A: ve exactamente ese proyecto, no el B.
set local role authenticated;
set local "request.jwt.claim.sub" to '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$ select project_key from cfg.projects order by project_key $$,
  $$ values ('agente-quant-bot'::text) $$,
  'usuario con membership ACTIVE en A ve solo el proyecto A, nunca B'
);
select is((select count(*)::int from core.competitions where canonical_name = 'Competicion solo de B'), 0,
  'usuario con membership solo en A no ve competitions del proyecto B');
reset role;
reset "request.jwt.claim.sub";

-- authenticated sin ninguna membership: no ve ningun proyecto (RLS deniega todas las filas).
set local role authenticated;
set local "request.jwt.claim.sub" to '22222222-2222-2222-2222-222222222222';
select is((select count(*)::int from cfg.projects), 0, 'usuario sin membership no ve ningun proyecto');
reset role;
reset "request.jwt.claim.sub";

-- has_project_role() es consistente con una verificacion directa de membership.
set local role authenticated;
set local "request.jwt.claim.sub" to '11111111-1111-1111-1111-111111111111';
select ok(
  app.has_project_role((select project_id from cfg.projects where project_key = 'agente-quant-bot'), array['VIEWER','ANALYST','OPERATOR','OWNER']) = true,
  'has_project_role() confirma VIEWER activo del usuario 1 en el proyecto A'
);
select ok(
  app.has_project_role((select project_id from cfg.projects where project_key = 'rls-test-project-b'), array['VIEWER','ANALYST','OPERATOR','OWNER']) = false,
  'has_project_role() niega acceso del usuario 1 al proyecto B (sin membership)'
);
reset role;
reset "request.jwt.claim.sub";

-- service_role: BYPASSRLS, ve ambos proyectos sin restriccion.
set local role service_role;
select is((select count(*)::int from cfg.projects), 2, 'service_role (BYPASSRLS) ve ambos proyectos sin restriccion de RLS');
reset role;

-- authenticated no tiene privilegio de UPDATE directo en ninguna tabla de negocio.
select throws_ok(
  $$ set local role authenticated;
     set local "request.jwt.claim.sub" to '11111111-1111-1111-1111-111111111111';
     update cfg.projects set name = 'hack' where project_key = 'agente-quant-bot'; $$,
  '42501', null, 'authenticated no puede hacer UPDATE directo sobre cfg.projects'
);
reset role;
reset "request.jwt.claim.sub";

select * from finish();
rollback;
