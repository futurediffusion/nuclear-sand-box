extends IronPipeWeapon
class_name MeleeWeapon

## Arma melee configurable. Hereda todo el comportamiento de IronPipeWeapon.
## Permite sobrescribir cooldown y bonus de daño al equipar.

@export var damage_bonus: int = 0

var _base_hitbox_damage: int = 0


func on_equipped(p_owner: Node, p_controller: WeaponController = null) -> void:
	super.on_equipped(p_owner, p_controller)
	if _character_hitbox == null or damage_bonus == 0:
		return
	var cur = _character_hitbox.get("damage")
	if cur != null:
		_base_hitbox_damage = int(cur)
		_character_hitbox.set("damage", _base_hitbox_damage + damage_bonus)


func on_unequipped() -> void:
	if _character_hitbox != null and damage_bonus != 0:
		var cur = _character_hitbox.get("damage")
		if cur != null:
			_character_hitbox.set("damage", int(cur) - damage_bonus)
	super.on_unequipped()
