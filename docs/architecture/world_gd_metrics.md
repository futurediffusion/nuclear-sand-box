# Métricas simples para `world.gd`

## Métricas base

Estas métricas se registran por iteración para evaluar la reducción de lógica de dominio en `world.gd`.

1. **Número de métodos de dominio en `world.gd`**
   - Conteo de métodos con responsabilidad de reglas de gameplay/dominio.
   - Excluye wiring técnico (render, señales, setup visual, logging).

2. **Número de dependencias directas de dominio**
   - Conteo de colaboraciones de dominio invocadas directamente desde `world.gd`.
   - Incluye acceso directo a servicios, repositorios o modelos de dominio.

3. **Número de decisiones condicionales de gameplay en `_process`/helpers**
   - Conteo de ramas condicionales (`if`/`match`/guards equivalentes) que deciden comportamiento de gameplay.
   - Se mide en `_process` y métodos auxiliares llamados desde `_process`.

## Objetivo de salida — Fase 1

Para considerar Fase 1 cerrada, se debe cumplir:

- **0 nuevas responsabilidades de dominio añadidas** en `world.gd`.
- **Tendencia de reducción visible** en las métricas, aunque la extracción total aún no esté completa.
- **Todas las entradas nuevas de gameplay pasan por dispatcher** (sin atajos directos a lógica de dominio).
