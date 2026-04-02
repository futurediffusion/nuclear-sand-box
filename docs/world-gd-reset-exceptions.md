# Excepciones aprobadas — `world.gd` reset boundary

Este registro habilita **excepciones temporales** para llamadas directas a `*.reset()` en `scripts/world/world.gd`.

## Política

- Solo se permiten excepciones cuando exista una justificación explícita.
- Toda excepción debe incluir fecha de retiro en formato `YYYY-MM-DD`.
- El guard de CI falla si detecta llamadas `*.reset()` sin excepción aprobada.

## Formato obligatorio

```text
scripts/world/world.gd:<line>|<justification>|<YYYY-MM-DD>
```

## Excepciones activas

Ninguna.
