# INC-TECH-001 — Bloqueo de ejecución del checklist crítico de walls/colliders

## Prioridad
- **P2 (deuda técnica / entorno)**

## Tipo
- Bloqueo de QA por entorno

## Contexto
Al intentar ejecutar la validación controlada de `walls/colliders` en CI/local container, el runtime no está disponible:
- Comando: `godot --path . --headless --script res://scripts/tests/walls_colliders_checklist_runner.gd`
- Error: `bash: command not found: godot`

## Impacto
- No se puede certificar en este entorno el checklist crítico previo a Fase 4.
- Riesgo de avanzar sin evidencia de regresión en gameplay.

## Acciones propuestas
1. Instalar/proveer binario Godot 4.x en el entorno de validación.
2. Ejecutar runner `scripts/tests/walls_colliders_checklist_runner.gd`.
3. Adjuntar artefacto `user://walls_colliders_checklist_results.json` al registro de QA.
4. Re-evaluar gate: solo habilitar Fase 4 con checklist crítico en verde.
