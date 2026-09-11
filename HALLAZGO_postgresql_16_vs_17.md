# Hallazgo: las validaciones de pgTAP se hicieron contra PostgreSQL 16, no contra 17

**Fecha:** 2026-09-09
**Encontrado al:** diseñar el borrador de CI (`test-fase1-supabase.yml`) y revisar `supabase/config.toml` en `saq/phase1-supabase` para escribirlo correctamente.
**Severidad:** media — no invalida el trabajo ya hecho, pero sí exige una corrida adicional antes de confiar en los resultados para producción.

## El hecho

`supabase/config.toml` (real, en el repositorio) declara:

```toml
[db]
major_version = 17
```

Todas las corridas de pgTAP hechas durante esta auditoría (5 veces, siempre 141/141 aserciones en verde, incluyendo la validación del parche de fixtures) se ejecutaron contra un PostgreSQL **16** efímero, instalado localmente con `initdb`/`pg_ctl`, porque es la versión disponible en este entorno de auditoría — no hay acceso de red a los paquetes de PostgreSQL 17 ni a Docker Hub desde aquí para levantar el stack real de Supabase.

## Por qué importa

PostgreSQL 17 introdujo cambios internos (planificador, algunas funciones de fecha/hora, comportamiento de `MERGE`, mejoras en particionamiento) que en principios generales podrían, en teoría, hacer que una prueba que pasa en 16 falle en 17 o viceversa. No hay ninguna evidencia concreta de que esto esté pasando aquí — las migraciones y los tests de este repositorio no usan sintaxis exclusiva de una versión en las partes revisadas — pero **no se puede afirmar "141/141 en producción" sin haberlo corrido contra la versión real que Supabase va a usar.**

## Qué NO se está diciendo

No se está diciendo que el trabajo de Fase 1 esté roto, ni que haya que rehacerlo. Es una verificación pendiente, no un defecto encontrado.

## Recomendación

Antes de fusionar el parche de fixtures o el borrador de siembra de Etapa B al repositorio real:

1. Correr `supabase db start && supabase db reset && supabase test db` en una máquina con Docker (tu equipo, o un runner de GitHub Actions usando el workflow adjunto) sobre la rama `saq/phase1-supabase` con el parche y el borrador de siembra aplicados.
2. Si el resultado es 141/141 (o el número correspondiente tras sumar las pruebas de Etapa B) en PostgreSQL 17 real, la validación queda completa y sin reservas.
3. Si algo falla, es información nueva y real que hay que atender antes de fusionar — no antes visto porque nunca se había probado contra la versión 17.

Este hallazgo no bloquea nada que ya estuviera aprobado; sólo se agrega como condición explícita antes de dar por buena, en PostgreSQL 17, cualquier fusión futura al repositorio real.
