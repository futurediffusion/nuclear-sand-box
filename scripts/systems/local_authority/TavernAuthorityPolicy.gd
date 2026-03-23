extends RefCounted
class_name TavernAuthorityPolicy

## Capa de política institucional de la taberna.
##
## Fase 2: sin estado propio — delega completamente en LocalAuthorityEventFeed.
##   El resultado es idéntico a llamar LocalAuthorityEventFeed.evaluate() directamente.
##
## Fase 3: recibirá TavernLocalMemory para enriquecer decisiones con historial:
##   - Reincidentes → escalar respuesta
##   - Múltiples incidentes en ventana de tiempo → activar lockdown automático
##   - Ofensores conocidos → distinción primera vez vs. reiteración
##
## USO:
##   var directive := _tavern_policy.evaluate(incident)

## Evalúa el incidente y devuelve un LocalAuthorityDirective.
## Nunca devuelve null (contrato heredado de LocalAuthorityEventFeed).
func evaluate(incident: LocalCivilIncident) -> LocalAuthorityDirective:
	return LocalAuthorityEventFeed.evaluate(incident)
