class_name BanditCampStashSystem
extends Node

## Responsabilidad única: ciclo de vida del cargo de los bandidos y los barriles de campamento.
##
## Cubre:
##   • Spawn y tracking de barriles físicos por grupo (_camp_barrels)
##   • Distribución de deposit_pos a cada behavior (vía callable externo)
##   • Recogida de drops: sweep de órbita y sweep de llegada
##   • Depósito animado de cargo en el barril (con overflow → nuevo barril)
##   • Drop del cargo al suelo cuando el NPC entra en combate
##
## No accede a _behaviors directamente — comunica cambios de barril al caller
## a través del callable update_deposit_pos_cb(group_id, barrel_pos).

const BanditTuningScript := preload("res://scripts/world/BanditTuning.gd")
const CAMP_BARREL_SCENE:  PackedScene = preload("res://scenes/placeables/barrel_world.tscn")
const ITEM_DROP_SCENE:    PackedScene = preload("res://scenes/items/ItemDrop.tscn")

# ---------------------------------------------------------------------------
# Camp layout constants — geometría visual interna, no balance de gameplay.
# Los radios de pickup y timings de animación viven en BanditTuning.
# ---------------------------------------------------------------------------
const BARREL_SPAWN_OFFSET_BASE:  float = 64.0   # px desde home_pos al primer barril
const BARREL_SPAWN_COLUMN_STEP:  float = 32.0   # px entre barriles adicionales

const CARRY_STACK_BASE_Y:  float = -22.0  # Y del primer item cargado sobre el NPC
const CARRY_STACK_STEP_Y:  float =   8.0  # desplazamiento Y por item adicional en el stack

# group_id (String) -> instance_id (int) del barrel físico (runtime-only, no persisted)
var _camp_barrels: Dictionary = {}

# Callable(group_id: String, barrel_pos: Vector2) -> void
# Implementado por BanditBehaviorLayer para propagar deposit_pos a los behaviors.
var _update_deposit_pos_cb: Callable = Callable()


func setup(ctx: Dictionary) -> void:
	_update_deposit_pos_cb = ctx.get("update_deposit_pos_cb", Callable())


# ---------------------------------------------------------------------------
# API pública — llamada por BanditBehaviorLayer en cada tick
# ---------------------------------------------------------------------------

## Garantiza que cada grupo activo tiene un barril vivo; spawna si es necesario.
func ensure_barrels() -> void:
	for group_id in BanditGroupMemory.get_all_group_ids():
		var barrel_id: int = int(_camp_barrels.get(group_id, 0))
		if barrel_id != 0 and is_instance_id_valid(barrel_id):
			var existing := instance_from_id(barrel_id) as Node
			if existing != null and is_instance_valid(existing) \
					and not existing.is_queued_for_deletion():
				_notify_deposit_pos(group_id, (existing as Node2D).global_position)
				continue
		var g: Dictionary = BanditGroupMemory.get_group(group_id)
		if (g.get("member_ids", []) as Array).is_empty():
			continue
		var home: Vector2 = g.get("home_world_pos", Vector2.ZERO)
		var barrel := _spawn_camp_barrel(home, 0)
		if barrel != null:
			_camp_barrels[group_id] = barrel.get_instance_id()
			_notify_deposit_pos(group_id, (barrel as Node2D).global_position)


## Recoge drops en radio de órbita (desde el centro del recurso).
func sweep_collect_orbit(beh: BanditWorldBehavior, enemy_node: Node,
		orbit_center: Vector2, drops_cache: Array) -> void:
	_sweep(beh, enemy_node, orbit_center, BanditTuningScript.orbit_collect_radius_sq(), drops_cache)


## Recoge todos los drops cercanos al llegar a un drop objetivo.
func sweep_collect_arrive(beh: BanditWorldBehavior, enemy_node: Node,
		arrive_pos: Vector2, drops_cache: Array) -> void:
	_sweep(beh, enemy_node, arrive_pos, BanditTuningScript.loot_arrive_collect_radius_sq(), drops_cache)


## Deposita el cargo en el barril del campamento (animación de caída + inserción).
func handle_cargo_deposit(beh: BanditWorldBehavior, enemy_node: Node) -> void:
	if not beh._just_arrived_home_with_cargo:
		return
	beh._just_arrived_home_with_cargo = false
	beh.cargo_count = 0

	var spawn_pos: Vector2 = beh.home_pos
	if enemy_node != null and is_instance_valid(enemy_node):
		spawn_pos = (enemy_node as Node2D).global_position

	# 1) Barril del campamento por group_id (lookup directo, sin proximity)
	var chest: Node = null
	if beh.group_id != "":
		var barrel_id: int = int(_camp_barrels.get(beh.group_id, 0))
		if barrel_id != 0 and is_instance_id_valid(barrel_id):
			var bn := instance_from_id(barrel_id) as Node
			if bn != null and is_instance_valid(bn) and not bn.is_queued_for_deletion():
				chest = bn

	# 2) Fallback: cualquier interactable cercano con soporte de inserción
	if chest == null:
		for node in get_tree().get_nodes_in_group("interactable"):
			if not node.has_method("try_insert_item") or not node.has_method("is_position_nearby"):
				continue
			if node.call("is_position_nearby", spawn_pos):
				chest = node
				break

	var land_target: Vector2 = spawn_pos
	if chest != null and chest is Node2D:
		land_target = (chest as Node2D).global_position

	var fall_time:   float = BanditTuningScript.cargo_fall_time()
	var sfx_stagger: float = BanditTuningScript.cargo_sfx_stagger()

	for i in beh._cargo_manifest.size():
		var entry:      Dictionary  = beh._cargo_manifest[i]
		var node_id:    int         = int(entry.get("node_id",    0))
		var item_id:    String      = String(entry.get("item_id", ""))
		var amount:     int         = int(entry.get("amount",     1))
		var orig_layer: int         = int(entry.get("orig_layer", 4))
		var offset      := Vector2(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0))
		var ground_pos  := land_target + offset

		# Obtener o re-spawnar el nodo del drop
		var drop_node: ItemDrop = null
		if node_id != 0 and is_instance_id_valid(node_id):
			var obj := instance_from_id(node_id)
			if obj != null and is_instance_valid(obj) \
					and not (obj as Node).is_queued_for_deletion():
				drop_node = obj as ItemDrop

		if drop_node == null:
			if item_id == "" or amount <= 0 or ITEM_DROP_SCENE == null:
				continue
			drop_node = ITEM_DROP_SCENE.instantiate() as ItemDrop
			if drop_node == null:
				continue
			drop_node.item_id = item_id
			drop_node.amount  = amount
			get_tree().current_scene.add_child(drop_node)
			drop_node.global_position = spawn_pos + Vector2(0.0, CARRY_STACK_BASE_Y - i * CARRY_STACK_STEP_Y)

		# Reparentar a la escena manteniendo la posición elevada del carry
		var carry_pos := drop_node.global_position
		if drop_node.get_parent() != get_tree().current_scene:
			drop_node.reparent(get_tree().current_scene, false)
		drop_node.global_position = carry_pos

		# Caída animada hacia el barril/suelo
		var tw := create_tween()
		tw.tween_property(drop_node, "global_position", ground_pos, fall_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

		var cap_drop     := drop_node
		var cap_item_id  := item_id
		var cap_amount   := amount
		var cap_sfx: AudioStream = drop_node.get("pickup_sfx") as AudioStream
		var cap_group_id := beh.group_id

		if chest != null:
			var deposit_delay := fall_time + i * sfx_stagger
			get_tree().create_timer(deposit_delay).timeout.connect(func() -> void:
				if not is_instance_valid(cap_drop) or cap_drop.is_queued_for_deletion():
					return
				var inserted := int(chest.call("try_insert_item", cap_item_id, cap_amount))
				if inserted > 0:
					if cap_sfx != null:
						AudioSystem.play_2d(cap_sfx, spawn_pos, null, &"SFX")
					cap_drop.queue_free()
					return
				# Barril lleno — buscar extras del grupo primero
				if cap_group_id != "":
					var found_space := false
					for gid in _camp_barrels.keys():
						if not String(gid).begins_with(cap_group_id) or String(gid) == cap_group_id:
							continue
						var bid: int = int(_camp_barrels[gid])
						if bid == 0 or not is_instance_id_valid(bid):
							continue
						var bn2 := instance_from_id(bid) as Node
						if bn2 == null or not is_instance_valid(bn2) \
								or not bn2.has_method("try_insert_item"):
							continue
						var ins2 := int(bn2.call("try_insert_item", cap_item_id, cap_amount))
						if ins2 > 0:
							_camp_barrels[cap_group_id] = bid
							_notify_deposit_pos(cap_group_id, (bn2 as Node2D).global_position)
							if cap_sfx != null:
								AudioSystem.play_2d(cap_sfx, spawn_pos, null, &"SFX")
							cap_drop.queue_free()
							found_space = true
							break
					if not found_space:
						var col: int = 0
						for gid in _camp_barrels:
							if String(gid).begins_with(cap_group_id):
								col += 1
						var new_barrel := _spawn_camp_barrel(spawn_pos, col)
						if new_barrel != null:
							var nrid: int = new_barrel.get_instance_id()
							_camp_barrels[cap_group_id + "_extra_%d" % col] = nrid
							_camp_barrels[cap_group_id] = nrid
							_notify_deposit_pos(cap_group_id, (new_barrel as Node2D).global_position)
							new_barrel.call("try_insert_item", cap_item_id, cap_amount)
							if cap_sfx != null:
								AudioSystem.play_2d(cap_sfx, spawn_pos, null, &"SFX")
							cap_drop.queue_free()
							return
				# Sin espacio en ningún barril — dejar en el suelo
				cap_drop.add_to_group("item_drop")
				cap_drop.set_deferred("collision_layer", orig_layer)
				cap_drop.set_deferred("monitoring",      true)
				cap_drop.set_process(true)
			)
		else:
			# Sin barril — spawnear uno nuevo en la posición de depósito
			var cap_group_id2 := beh.group_id
			var cap_deposit   := land_target
			get_tree().create_timer(fall_time).timeout.connect(func() -> void:
				if not is_instance_valid(cap_drop) or cap_drop.is_queued_for_deletion():
					return
				var new_barrel := _spawn_camp_barrel(cap_deposit - Vector2(36.0, 0.0), 0)
				if new_barrel != null and cap_group_id2 != "":
					_camp_barrels[cap_group_id2] = new_barrel.get_instance_id()
					_notify_deposit_pos(cap_group_id2, new_barrel.global_position)
				if new_barrel != null:
					new_barrel.call("try_insert_item", cap_item_id, cap_amount)
					if cap_sfx != null:
						AudioSystem.play_2d(cap_sfx, cap_deposit, null, &"SFX")
					cap_drop.queue_free()
				else:
					cap_drop.add_to_group("item_drop")
					cap_drop.set_deferred("collision_layer", orig_layer)
					cap_drop.set_deferred("monitoring",      true)
					cap_drop.set_process(true)
			)

	beh._cargo_manifest.clear()
	beh.on_deposit_complete()
	Debug.log("bandit_ai", "[CampStash] cargo depositado id=%s pos=%s chest=%s" % [
		beh.member_id, str(spawn_pos), str(chest != null)])


## Suelta todo el cargo al suelo cuando el NPC entra en combate.
func drop_carry_on_aggro(beh: BanditWorldBehavior, enemy_node: Node) -> void:
	var drop_pos: Vector2 = beh.home_pos
	if enemy_node != null and is_instance_valid(enemy_node):
		drop_pos = (enemy_node as Node2D).global_position

	for entry in beh._cargo_manifest:
		var node_id: int    = int(entry.get("node_id",    0))
		var orig_layer: int = int(entry.get("orig_layer", 4))
		var throw_dir := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 0.2)).normalized()

		if node_id != 0 and is_instance_id_valid(node_id):
			var drop_node := instance_from_id(node_id) as ItemDrop
			if drop_node != null and is_instance_valid(drop_node) \
					and not drop_node.is_queued_for_deletion():
				if drop_node.is_in_group("item_drop"):
					continue
				drop_node.reparent(get_tree().current_scene, false)
				drop_node.add_to_group("item_drop")
				drop_node.set_deferred("collision_layer", orig_layer)
				drop_node.set_deferred("monitoring",      true)
				drop_node.set_process(true)
				drop_node.throw_from(drop_pos, throw_dir, randf_range(55.0, 110.0))
				continue

		# Fallback: el nodo no sobrevivió — spawnear uno nuevo
		var item_id := String(entry.get("item_id", ""))
		var amount  := int(entry.get("amount", 1))
		if item_id == "" or amount <= 0 or ITEM_DROP_SCENE == null:
			continue
		var drop := ITEM_DROP_SCENE.instantiate() as ItemDrop
		if drop == null:
			continue
		drop.item_id = item_id
		drop.amount  = amount
		get_tree().current_scene.add_child(drop)
		drop.throw_from(drop_pos, throw_dir, randf_range(55.0, 110.0))

	beh._cargo_manifest.clear()
	beh.cargo_count                   = 0
	beh._just_arrived_home_with_cargo = false
	Debug.log("bandit_ai", "[CampStash] carry soltado al entrar en combate id=%s" % beh.member_id)


# ---------------------------------------------------------------------------
# Privado — sweep y collection
# ---------------------------------------------------------------------------

func _sweep(beh: BanditWorldBehavior, enemy_node: Node,
		check_pos: Vector2, radius_sq: float, drops_cache: Array) -> void:
	if beh.is_cargo_full():
		return
	var sound_idx := 0
	for drop in drops_cache:
		if beh.is_cargo_full():
			break
		var drop_node := drop as Node2D
		if not is_instance_valid(drop_node) or drop_node.is_queued_for_deletion():
			continue
		if not drop_node.is_in_group("item_drop"):
			continue
		if check_pos.distance_squared_to(drop_node.global_position) > radius_sq:
			continue
		beh.pending_collect_id = drop_node.get_instance_id()
		_handle_collection(beh, enemy_node, sound_idx * BanditTuningScript.cargo_sfx_stagger())
		sound_idx += 1


func _handle_collection(beh: BanditWorldBehavior, enemy_node: Node,
		sound_delay: float = 0.0) -> void:
	var drop_id: int = beh.pending_collect_id
	beh.pending_collect_id = 0

	if drop_id == 0 or not is_instance_id_valid(drop_id):
		return
	var drop_obj: Object = instance_from_id(drop_id)
	if drop_obj == null or not is_instance_valid(drop_obj):
		return
	var drop_node: Node2D = drop_obj as Node2D
	if drop_node == null or drop_node.is_queued_for_deletion():
		return

	var collected_amount: int = int(drop_node.get("amount") if drop_node.get("amount") != null else 1)
	var item_id: String       = String(drop_node.get("item_id") if drop_node.get("item_id") != null else "")
	var drop_pos: Vector2     = drop_node.global_position
	var pickup_sfx            = drop_node.get("pickup_sfx")
	var sfx_stream: AudioStream = pickup_sfx if pickup_sfx is AudioStream else AudioSystem.default_pickup_sfx

	if sound_delay <= 0.0:
		AudioSystem.play_2d(sfx_stream, drop_pos, null, &"SFX")
	else:
		get_tree().create_timer(sound_delay).timeout.connect(func() -> void:
			AudioSystem.play_2d(sfx_stream, drop_pos, null, &"SFX")
		)

	var carried: bool = false
	if enemy_node != null and is_instance_valid(enemy_node):
		var orig_layer: int = drop_node.collision_layer
		drop_node.remove_from_group("item_drop")
		drop_node.set_deferred("monitoring",      false)
		drop_node.set_deferred("collision_layer", 0)
		drop_node.set_process(false)
		var stack_offset := Vector2(0.0, CARRY_STACK_BASE_Y - beh._cargo_manifest.size() * CARRY_STACK_STEP_Y)
		drop_node.reparent(enemy_node, false)
		drop_node.position = stack_offset
		beh._cargo_manifest.append({
			"item_id":    item_id,
			"amount":     collected_amount,
			"node_id":    drop_node.get_instance_id(),
			"orig_layer": orig_layer,
		})
		carried = true

	if not carried:
		drop_node.queue_free()
		if item_id != "":
			beh._cargo_manifest.append({"item_id": item_id, "amount": collected_amount, "node_id": 0})

	var prev: int = beh.cargo_count
	beh.cargo_count = mini(beh.cargo_count + collected_amount, beh.cargo_capacity)
	Debug.log("bandit_ai", "[CampStash] collected %s×%d id=%s cargo=%d→%d/%d" % [
		item_id, collected_amount, beh.member_id, prev, beh.cargo_count, beh.cargo_capacity])


# ---------------------------------------------------------------------------
# Privado — barrel spawn
# ---------------------------------------------------------------------------

func _spawn_camp_barrel(home_pos: Vector2, column: int = 0) -> Node:
	if CAMP_BARREL_SCENE == null:
		push_warning("[CampStash] CAMP_BARREL_SCENE not loaded")
		return null
	var barrel := CAMP_BARREL_SCENE.instantiate()
	get_tree().current_scene.add_child(barrel)
	barrel.global_position = home_pos + Vector2(BARREL_SPAWN_OFFSET_BASE + column * BARREL_SPAWN_COLUMN_STEP, 0.0)
	Debug.log("camp_stash", "[CampStash] spawned camp barrel at=%s col=%d" % [str(home_pos), column])
	return barrel


func _notify_deposit_pos(group_id: String, barrel_pos: Vector2) -> void:
	if _update_deposit_pos_cb.is_valid():
		_update_deposit_pos_cb.call(group_id, barrel_pos)
