# AGENTE-QUANT-BOT
"Bot de alertas de apuestas de valor".

## Fase 1 — Infraestructura Supabase (SAQ-MCDS-V1.1-APPROVED)

Estructura de datos canónica (36 tablas, RLS, views/RPC api) definida en
`supabase/migrations/`. Ningún dato productivo, apuesta real ni modelo
predictivo se activa en esta fase; los catálogos quedan en `DRAFT`.

### Instalación local

1. Requiere Docker en ejecución.
2. `npx --yes supabase@2.116.0 start` — levanta Postgres local y aplica
   `supabase/config.toml`.
3. `npx --yes supabase@2.116.0 db reset` — aplica las 13 migraciones de
   `supabase/migrations/` en orden, desde cero, sobre la base local.

### Pruebas

`npx --yes supabase@2.116.0 test db` ejecuta las 10 suites pgTAP de
`supabase/tests/database/` contra la base local (fuera del historial de
migraciones aplicadas).

### Variables de entorno

Ver `.env.example` para los nombres de variable requeridos. Ningún
secreto se documenta ni se sube al repositorio.

