# Cooldown Sovereignty Register

Fecha de corte: **2026-04-01**.
Responsable técnico de este registro: **GPT-5.3-Codex (agent)**.

## 1) Cooldowns que afectan la misma acción en sistemas diferentes

| Acción | Sistemas detectados | Riesgo de duplicación |
|---|---|---|
| Encolar extorsión de grupo | `BanditGroupIntel` (guard), `ExtortionQueue` (timestamp por grupo), `BanditGroupMemory` (social cooldown interno) | Alto |
| Encolar raid (light/full) | `BanditGroupIntel` (guard), `RaidQueue` (timestamp por grupo), `BanditGroupMemory` (social cooldown interno) | Alto |
| Encolar wall probe | `BanditGroupIntel` (guard), `RaidQueue` (timestamp específico de probe), `BanditGroupMemory` (social cooldown interno) | Alto |
| Reacción social de runtime | `BanditBehaviorLayer` (micro-cooldowns de chat/log), `BanditTerritoryResponse` (cooldown territorial) | Medio |

## 2) Owner único por tipo de cooldown

| Tipo de cooldown | Owner designado | Justificación |
|---|---|---|
| **Raid** (light/full) | `RaidQueue` | Es la cola que persiste el último raid y decide disponibilidad temporal de nuevas encoladas. |
| **Interacción social (extorsión)** | `ExtortionQueue` | Es la cola de intents de extorsión y guarda el último request por grupo. |
| **Combate/estado social interno de grupo** | `BanditGroupMemory` | Mantiene `internal_social_cooldown_until` por grupo para readiness social. |
| **Runtime diegético/UI** | `BanditBehaviorLayer` y `BanditTerritoryResponse` (scope local) | Son cooldowns locales de presentación/reacción, no de scheduling de colas. |

## 3) Migración aplicada (cálculo + validación en owner)

- `ExtortionQueue` ahora expone:
  - `get_cooldown_remaining(group_id, cooldown)`
  - `is_request_available(group_id, cooldown)`
- `RaidQueue` ahora expone:
  - `get_raid_cooldown_remaining(group_id, cooldown)`
  - `is_raid_available(group_id, cooldown)`
  - `get_wall_probe_cooldown_remaining(group_id, cooldown)`
  - `is_wall_probe_available(group_id, cooldown)`
- `BanditGroupIntel` dejó de calcular `now-last<cooldown` para extorsión/raid/probe y usa solo checks de lectura al owner.

## 4) Cooldowns defensivos duplicados sustituidos

Se sustituyeron guards locales en `BanditGroupIntel`:

- **Extorsión**: cálculo local `elapsed` reemplazado por `ExtortionQueue.get_cooldown_remaining(...)`.
- **Wall probe**: `RunClock.now() - last_probe < probe_cd` reemplazado por `RaidQueue.is_wall_probe_available(...)`.
- **Light raid / full raid**: checks `RunClock.now() - last_time < cooldown` reemplazados por `RaidQueue.is_raid_available(...)`.

## 5) Excepciones justificadas

| Fecha | Excepción | Motivo | Responsable técnico |
|---|---|---|---|
| 2026-04-01 | Se mantiene `BanditGroupMemory.push_social_cooldown(...)` además de cooldowns de cola (`ExtortionQueue`/`RaidQueue`). | No es duplicación del mismo dato temporal: modela fatiga social interna del grupo, no cadencia de encolado de jobs. | GPT-5.3-Codex |
| 2026-04-01 | Se mantienen cooldowns de `BanditBehaviorLayer` y `BanditTerritoryResponse`. | Son cooldowns de runtime diegético/UI (chat/reacción territorial), fuera del scope de scheduling de extorsión/raid/probe. | GPT-5.3-Codex |
