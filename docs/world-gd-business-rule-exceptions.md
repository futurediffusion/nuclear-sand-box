# Excepciones temporales — business rules en `world.gd`

Registro único de excepciones **temporales y explícitas** para patrones prohibidos de lógica de negocio dentro de `scripts/world/world.gd`.

## Política

- Toda excepción debe ser temporal.
- Toda excepción requiere justificación explícita.
- Toda excepción requiere fecha de retiro en formato `YYYY-MM-DD`.
- El guard de CI falla si:
  - detecta un patrón prohibido sin excepción, o
  - detecta una excepción vencida.

## Formato obligatorio

```text
PATTERN:|<pattern_id>|<justification>|<YYYY-MM-DD>
```

## Excepciones activas

Ninguna.
