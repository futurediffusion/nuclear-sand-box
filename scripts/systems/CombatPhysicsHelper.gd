extends RefCounted
class_name CombatPhysicsHelper

# ── CombatPhysicsHelper ───────────────────────────────────────────────────────
# Helpers de física de combate reutilizables por cualquier actor del juego.
#
# POR QUÉ EXISTE AQUÍ Y NO ENTERRADO EN SENTINEL:
#   Un empujón sin daño es una capacidad genérica — sentinels la usan para
#   advertencias físicas, pero enemigos, trampas o mecánicas de arena podrían
#   necesitarla también. Si viviera solo en Sentinel, cada sistema que la
#   necesite la reimplementaría por su cuenta.
#
# USO:
#   CombatPhysicsHelper.shove_no_damage(my_pos, target_character, 380.0)
#
# CONTRATO:
#   - No inflige daño ni cambia HP
#   - No cambia estado de salud ni downed
#   - Solo aplica knockback físico a un CharacterBase
#   - Es responsabilidad del llamador garantizar que target es válido


## Aplica un empujón físico sin daño a un CharacterBase.
##
## source_pos: posición mundo desde donde viene el empujón (para calcular dirección)
## target:     el CharacterBase que recibe el empujón
## force:      magnitud del knockback (en px/s²). ~300-500 es un empujón moderado.
##
## Seguro llamar aunque target esté en estado hurt — no agrava el estado de salud.
## No hace nada si target está muerto, en proceso de muerte o siendo cargado.
static func shove_no_damage(source_pos: Vector2, target: CharacterBase, force: float) -> void:
	if not is_instance_valid(target):
		return
	if target.dying:
		return
	if target.is_downed:
		return  # empujar a alguien caído no tiene sentido; ignorar silenciosamente

	var dir: Vector2 = (target.global_position - source_pos).normalized()
	if dir == Vector2.ZERO:
		# source y target en la misma posición exacta — empujar en dirección arbitraria
		dir = Vector2.RIGHT

	target.apply_knockback(dir * force)


## Versión con dirección explícita — útil para trampas o áreas con dirección fija.
static func shove_directional(target: CharacterBase, direction: Vector2, force: float) -> void:
	if not is_instance_valid(target):
		return
	if target.dying or target.is_downed:
		return

	var dir: Vector2 = direction.normalized()
	if dir == Vector2.ZERO:
		return

	target.apply_knockback(dir * force)
