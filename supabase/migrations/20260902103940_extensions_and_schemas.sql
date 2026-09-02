-- SAQ-MCDS-V1 §3, §6, Apéndice A · 0001_extensions_and_schemas
-- Extensiones minimas de la Fase 1 y los 8 esquemas logicos aprobados.
-- pgTAP se instala en el entorno de pruebas (supabase/tests/database/), no aqui.

create extension if not exists pgcrypto;

-- Requerida por los EXCLUDE (gist) de vigencias no solapadas en
-- cfg.market_contract_versions y cfg.policy_versions (SAQ-MCDS-V1 §20/§13.6/§13.8).
create extension if not exists btree_gist;

create schema if not exists app;
create schema if not exists cfg;
create schema if not exists raw;
create schema if not exists core;
create schema if not exists market;
create schema if not exists model;
create schema if not exists ops;
create schema if not exists api;

comment on schema app is 'Tipos, dominios, funciones y triggers compartidos. Ninguna tabla de negocio.';
comment on schema cfg is 'Proyectos, fuentes, contratos, modelos y politicas.';
comment on schema raw is 'Requests y payloads originales. Append-only.';
comment on schema core is 'Identidades deportivas y versiones de evento.';
comment on schema market is 'Selecciones, cuotas, consenso y cierres.';
comment on schema model is 'Features, runs, predicciones y evaluacion.';
comment on schema ops is 'Senales, ejecucion, settlement, banca y auditoria.';
comment on schema api is 'Unica superficie expuesta por Data API: views y RPC aprobadas.';
