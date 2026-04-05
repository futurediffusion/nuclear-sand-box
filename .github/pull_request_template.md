## Resumen
- Describe brevemente qué cambia este PR.

## Checklist obligatorio
Marca cada punto antes de solicitar revisión:

- [ ] No agregué lógica de gameplay nueva en `world.gd`.
- [ ] Si toqué `world.gd`, fue solo para wiring/bootstrap/tick/bridge.
- [ ] La lógica de dominio nueva vive en módulo dedicado.

## Regla de revisión (bloqueante)
- Un PR **no se aprueba** si añade branches de decisión de dominio en `world.gd`.
