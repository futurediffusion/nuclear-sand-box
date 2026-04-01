## Resumen
- Describe brevemente el cambio y su impacto.

## Checklist obligatoria — olores prohibidos (bloqueante)
Marca cada ítem con `Sí` o `No` y agrega evidencia.

Fuente de verdad: [`docs/pr-smell-blacklist.md`](../docs/pr-smell-blacklist.md).

> **Regla de merge:** cualquier respuesta **“Sí”** sin justificación aprobada y sin excepción registrada bloquea el merge.

- [ ] **¿introduce timer local pudiendo usar cadence?**
  - Respuesta: 
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura): 
- [ ] **¿agrega comportamiento en autoload que debería vivir en un owner de dominio?**
  - Respuesta: 
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura): 
- [ ] **¿duplica heurística ya existente?**
  - Respuesta: 
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura): 
- [ ] **¿mezcla debug con mutación?**
  - Respuesta: 
  - Evidencia de cumplimiento (ruta de código o nota de arquitectura): 

## Evidencia global obligatoria
- [ ] Incluí evidencia para todos los puntos (ruta de código o nota de arquitectura).
- [ ] Si hubo excepciones, quedaron registradas en `docs/incidencias/registro-unico-deuda-tecnica.md` con fecha de retiro.
- [ ] Acepto criterio de bloqueo: cualquier “Sí” sin excepción temporal aprobada deja este PR en **No Ready**.

## Excepciones (solo si aplica)
Si marcaste algún **“Sí”**, completa:
- Justificación aprobada:
- ID / enlace de aprobación:
- Registro en deuda técnica (fila o sección):
- Fecha de retiro comprometida (YYYY-MM-DD):
