extends Node
class_name CarryableComponent

@export var carry_offset: Vector2 = Vector2(0, -20)
@export var disable_collision_on_carry: bool = true
@export var drop_ground_offset: Vector2 = Vector2(0, 0)
## Si true, solo se puede cargar cuando el padre tiene is_downed == true
@export var require_downed: bool = false
## Si false, siempre se suelta sin scatter (útil para personajes)
@export var allow_scatter: bool = true
## Si true, deshabilita _physics_process y _process del padre mientras es cargado
@export var disable_process_on_carry: bool = false

var _parent: Node2D
var _carrier: Node2D = null
var _original_parent: Node = null
var _original_collision_layer: int = 1
var _original_collision_mask: int = 1
var _is_carried: bool = false
var _carry_tween: Tween = null   # tween de reposicionamiento en el stack
var _was_enemy_child: bool = false

func _ready() -> void:
	_parent = get_parent() as Node2D
	if _parent == null:
		push_warning("CarryableComponent must be a child of a Node2D.")
		return

	_parent.add_to_group("carryable")

func can_pickup() -> bool:
	if _is_carried:
		return false
	if require_downed:
		return _parent.get("is_downed") == true
	return true

func pickup(carrier: Node2D) -> void:
	if _is_carried or carrier == null or _parent == null:
		return

	_is_carried = true
	_carrier = carrier

	# Store original state
	_original_parent = _parent.get_parent()
	_was_enemy_child = _original_parent != null and _original_parent is CharacterBody2D
	if _parent is CollisionObject2D and disable_collision_on_carry:
		_original_collision_layer = _parent.collision_layer
		_original_collision_mask = _parent.collision_mask
		_parent.collision_layer = 0
		_parent.collision_mask = 0

	# Freeze AI/physics while carried
	if disable_process_on_carry:
		_parent.set_physics_process(false)
		_parent.set_process(false)

	# Reparent to carrier
	if _original_parent != null:
		var global_pos = _parent.global_position
		_original_parent.remove_child(_parent)
		_carrier.add_child(_parent)
		_parent.global_position = global_pos

func update_carry_position(target_offset: Vector2) -> void:
	if not _is_carried or _parent == null:
		return

	carry_offset = target_offset
	if _carry_tween != null and _carry_tween.is_valid():
		_carry_tween.kill()
	_carry_tween = create_tween()
	_carry_tween.tween_property(_parent, "position", target_offset, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func drop(scatter: bool = false) -> void:
	if not _is_carried or _parent == null:
		return

	_is_carried = false
	# Matar el tween de posición del stack antes de iniciar la caída,
	# para que no compita con el tween de global_position del drop.
	if _carry_tween != null and _carry_tween.is_valid():
		_carry_tween.kill()
	_carry_tween = null

	# Scatter solo si está permitido para este tipo de objeto
	var do_scatter := scatter and allow_scatter

	# Save elevated carry position BEFORE reparenting (coordinate space changes after)
	var carry_global_pos := _parent.global_position

	# Compute landing target from player ground plane
	var global_drop_pos: Vector2
	if _carrier != null and is_instance_valid(_carrier) and _carrier.get_parent() != null:
		global_drop_pos = _carrier.get_parent().global_position + drop_ground_offset
	else:
		global_drop_pos = carry_global_pos

	# Restore parent.
	# Si el padre original es un CharacterBody2D (enemy, NPC) no devolver el item
	# a él — soltarlo al mundo para que quede en el suelo y se pueda recoger.
	if _carrier != null:
		_carrier.remove_child(_parent)
	var restore_parent: Node = _original_parent
	if restore_parent != null and restore_parent is CharacterBody2D:
		restore_parent = null
	if restore_parent != null and is_instance_valid(restore_parent):
		restore_parent.add_child(_parent)
	elif get_tree() != null and get_tree().current_scene != null:
		get_tree().current_scene.add_child(_parent)
	elif _parent.get_parent() == null:
		push_warning("CarryableComponent: no valid parent to restore to for %s" % _parent.name)

	# Keep item at its elevated carry position so the fall tween is visible
	_parent.global_position = carry_global_pos

	# Restore collision
	if _parent is CollisionObject2D and disable_collision_on_carry:
		_parent.collision_layer = _original_collision_layer
		_parent.collision_mask = _original_collision_mask

	# Restore AI/physics
	if disable_process_on_carry:
		_parent.set_physics_process(true)
		_parent.set_process(true)

	# Si el item fue robado de un enemy (original parent era CharacterBody2D),
	# restaurarlo a estado funcional: proceso, monitoring, grupo y colisión.
	if _was_enemy_child:
		_parent.set_process(true)
		_parent.set_physics_process(true)
		if _parent is Area2D:
			(_parent as Area2D).set_deferred("monitoring", true)
		if not _parent.is_in_group("item_drop"):
			_parent.add_to_group("item_drop")
		if _parent is CollisionObject2D and _original_collision_layer == 0:
			_parent.collision_layer = 1
			_parent.collision_mask = 1

	# Reset magnet so it doesn't fight the fall tween (items only)
	if _parent.has_method("reset_magnet_delay"):
		_parent.reset_magnet_delay()

	if do_scatter:
		var random_offset = Vector2(randf_range(-15, 15), randf_range(-15, 15))
		var tw = create_tween()
		tw.tween_property(_parent, "global_position", global_drop_pos + random_offset, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		var tw = create_tween()
		tw.tween_property(_parent, "global_position", global_drop_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	_carrier = null
	_original_parent = null
	_was_enemy_child = false
