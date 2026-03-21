extends Node
class_name BanditBehaviorLayer

# ── BanditBehaviorLayer ──────────────────────────────────────────────────────
# Node child of World. Owns and ticks all BanditWorldBehavior instances for
# active bandit enemies.
#
# Every TICK_INTERVAL seconds:
#   1. Lazily creates behaviors for new sleeping bandits (group_id required).
#   2. Builds a ctx dict with nearby drops / resources for each enemy.
#   3. Ticks each behavior.
#   4. Handles pending_collect_id (does the actual node interaction so behaviors
#      stay pure RefCounted — no node access inside them).
#   5. Prunes behaviors for enemies that have despawned.
#
# Every physics frame:
#   Applies desired_velocity (+ friction compensation) to sleeping non-lite enemies.
#
# Carry preference: NPCs carry drops to base (cargo_count) rather than
# putting them in inventory. Inventory is not touched here.

const TICK_INTERVAL: float = 0.5

# enemy.gd default friction = 1500; at 60 fps delta≈0.0167 → ≈25 px/s per frame.
# We add this so net movement ≈ behavior's intended speed after friction.
const BanditTuningScript := preload("res://scripts/world/BanditTuning.gd")
const ITEM_DROP_SCENE: PackedScene = preload("res://scenes/items/ItemDrop.tscn")
const CAMP_BARREL_SCENE: PackedScene = preload("res://scenes/placeables/barrel_world.tscn")


# World-layer ally separation (sleeping NPCs don't run CharacterBody2D separation)
const ALLY_SEP_RADIUS: float = 44.0
const ALLY_SEP_FORCE:  float = 55.0

# Scan radii for finding world objects per tick
const LOOT_SCAN_RADIUS_SQ: float    = 144.0 * 144.0   # 144 px
const RESOURCE_SCAN_RADIUS_SQ: float = 288.0 * 288.0  # 288 px

const BanditGroupIntelScript := preload("res://scripts/world/BanditGroupIntel.gd")
const BanditExtortionDirectorScript := preload("res://scripts/world/BanditExtortionDirector.gd")

var _npc_simulator: NpcSimulator    = null
var _group_intel: BanditGroupIntel  = null
var _player: Node2D = null
var _bubble_manager: WorldSpeechBubbleManager = null
var _behaviors: Dictionary = {}   # enemy_id (String) -> BanditWorldBehavior
var _tick_timer: float = 0.0

const DEBUG_ALERTED_CHASE: bool = true  # Debug: scout del grupo alerted persigue al player

var _extortion_director: BanditExtortionDirector = null
# NOTE: extortion encounter progress is owned by BanditExtortionDirector as
# ephemeral runtime state. This layer recreates the director on setup and does
# not attempt to serialize in-flight extortions across world/chunk rebuilds.

# Cached world-level item/resource lists (rebuilt once per tick, shared across all enemies)
var _all_drops_cache: Array    = []   # Array of ItemDrop nodes
var _all_resources_cache: Array = []  # Array of world_resource nodes

# One physical barrel per camp group — spawned by this layer, tracked by instance_id
var _camp_barrels: Dictionary = {}   # group_id (String) -> instance_id (int)


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(ctx: Dictionary) -> void:
	_npc_simulator  = ctx.get("npc_simulator")
	_player         = ctx.get("player")
	_bubble_manager = ctx.get("speech_bubble_manager")
	if _extortion_director != null:
		if is_instance_valid(_extortion_director):
			_extortion_director.queue_free()
		_extortion_director = null
	_extortion_director = BanditExtortionDirectorScript.new()
	add_child(_extortion_director)
	_extortion_director.setup({
		"npc_simulator": _npc_simulator,
		"player": _player,
		"speech_bubble_manager": _bubble_manager,
		"get_behavior_for_enemy": Callable(self, "_get_behavior")
	})

## Called from world.gd after SettlementIntel is ready.
func setup_group_intel(ctx: Dictionary) -> void:
	_group_intel = BanditGroupIntelScript.new()
	_group_intel.setup({
		"npc_simulator":             _npc_simulator,
		"get_interest_markers_near": ctx.get("get_interest_markers_near", Callable()),
		"get_detected_bases_near":   ctx.get("get_detected_bases_near",   Callable()),
	})


# ---------------------------------------------------------------------------
# Physics frame — apply velocity to sleeping, non-lite enemies
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _npc_simulator == null:
		return

	# Pass 1: apply desired velocities + collect per-group node positions
	var group_nodes: Dictionary = {}  # group_id -> Array of {node, pos}
	for enemy_id in _behaviors:
		var behavior: BanditWorldBehavior = _behaviors[enemy_id]
		var node = _npc_simulator._get_active_enemy_node(enemy_id)
		if node == null or not node.has_method("is_world_behavior_eligible") \
				or not node.is_world_behavior_eligible():
			continue
		var vel: Vector2 = behavior.get_desired_velocity()
		if vel.length_squared() > 0.01:
			node.velocity = vel.normalized() * (vel.length() + BanditTuningScript.friction_compensation())
		# Idle (vel == 0): don't override, let enemy friction decelerate naturally
		if behavior.group_id != "":
			if not group_nodes.has(behavior.group_id):
				group_nodes[behavior.group_id] = []
			group_nodes[behavior.group_id].append({"node": node, "pos": node.global_position})

	# Pass 2: ally separation — push nearby group members apart
	for gid in group_nodes:
		var members: Array = group_nodes[gid]
		if members.size() < 2:
			continue
		for i in members.size():
			var a: Dictionary = members[i]
			var sep: Vector2 = Vector2.ZERO
			for j in members.size():
				if i == j:
					continue
				var diff: Vector2 = (a["pos"] as Vector2) - (members[j]["pos"] as Vector2)
				var d: float = diff.length()
				if d < ALLY_SEP_RADIUS and d > 0.5:
					sep += diff.normalized() * (ALLY_SEP_RADIUS - d) / ALLY_SEP_RADIUS * ALLY_SEP_FORCE
			if sep.length_squared() > 0.01:
				a["node"].velocity += sep

	if _extortion_director != null:
		_extortion_director.apply_extortion_movement(BanditTuningScript.friction_compensation())

	# Debug alerted scout chase — un solo NPC persigue al player cuando el grupo está "alerted"
	# Para desactivar: pon DEBUG_ALERTED_CHASE = false arriba
	if DEBUG_ALERTED_CHASE and _player != null and is_instance_valid(_player):
		var ap: Vector2 = _player.global_position
		for gid in BanditGroupMemory.get_all_group_ids():
			var g: Dictionary = BanditGroupMemory.get_group(gid)
			if String(g.get("current_group_intent", "")) != "alerted":
				continue
			var scout_id: String = BanditGroupMemory.get_scout(gid)
			if scout_id == "":
				continue
			var snode = _npc_simulator._get_active_enemy_node(scout_id)
			if snode == null or not snode.has_method("is_world_behavior_eligible") \
					or not snode.is_world_behavior_eligible():
				continue
			var to_p: Vector2 = ap - snode.global_position
			if to_p.length() > 1.0:
				snode.velocity = to_p.normalized() * (BanditTuningScript.alerted_scout_chase_speed(gid) + BanditTuningScript.friction_compensation())


# ---------------------------------------------------------------------------
# Process tick — behavior maintenance
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _npc_simulator == null:
		return
	if _group_intel != null:
		_group_intel.tick(delta)
	if _extortion_director != null:
		_extortion_director.process_extortion()
	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL:
		return
	_tick_timer = 0.0

	_refresh_world_caches()
	_ensure_behaviors_for_active_enemies()   # crea behaviors primero
	_ensure_camp_barrels()                   # luego empuja deposit_pos a todos los behaviors existentes
	_tick_behaviors()
	_prune_behaviors()


# ---------------------------------------------------------------------------
# World caches (rebuilt once per tick — shared across all enemy tick calls)
# ---------------------------------------------------------------------------

func _refresh_world_caches() -> void:
	_all_drops_cache     = get_tree().get_nodes_in_group("item_drop")
	_all_resources_cache = get_tree().get_nodes_in_group("world_resource")


# ---------------------------------------------------------------------------
# Behavior tick
# ---------------------------------------------------------------------------

func _tick_behaviors() -> void:
	# Collect leader positions by group_id for FOLLOW_LEADER support
	var leader_pos_by_group: Dictionary = {}
	for enemy_id in _behaviors:
		var beh: BanditWorldBehavior = _behaviors[enemy_id]
		if beh.role != "leader" or beh.group_id == "":
			continue
		var node = _npc_simulator._get_active_enemy_node(enemy_id)
		if node != null:
			leader_pos_by_group[beh.group_id] = node.global_position

	for enemy_id in _behaviors:
		var beh: BanditWorldBehavior = _behaviors[enemy_id]
		var node = _npc_simulator._get_active_enemy_node(enemy_id)
		if node == null or not node.has_method("is_world_behavior_eligible") \
				or not node.is_world_behavior_eligible():
			# Si tenía carry y entró en combate, suelta todo al suelo
			if not beh._cargo_manifest.is_empty():
				_drop_carry_on_aggro(beh, node)
			continue

		var node_pos: Vector2 = node.global_position
		var ctx: Dictionary = {
			"node_pos":          node_pos,
			"nearby_drops_info": _build_drops_info(node_pos),
			"nearby_res_info":   _build_res_info(node_pos),
		}
		if beh.group_id != "":
			ctx["leader_pos"] = leader_pos_by_group.get(beh.group_id, beh.home_pos)

		beh.tick(TICK_INTERVAL, ctx)

		# Detección de aggro mientras aún es eligible (AIComponent tiene target)
		if not beh._cargo_manifest.is_empty():
			var ai_comp := node.get_node_or_null("AIComponent")
			if ai_comp != null and ai_comp.get("target") != null:
				_drop_carry_on_aggro(beh, node)

		# Sync state back to WorldSave — cargo and full behavior for data-only continuity
		var save_state_ref: Dictionary = _get_save_state_for(enemy_id)
		if not save_state_ref.is_empty():
			save_state_ref["cargo_count"]    = beh.cargo_count
			save_state_ref["world_behavior"] = beh.export_state()

		# Handle node interactions (actual world interaction lives here, not in behavior)
		_handle_mining(beh, node)
		# Sweep de recogida — un solo jalon recoge todos los drops cercanos con tururur
		if beh.state == NpcWorldBehavior.State.RESOURCE_WATCH:
			# Durante órbita: medir desde el centro del recurso
			var res_center := node_pos
			if beh._resource_node_id != 0 and is_instance_id_valid(beh._resource_node_id):
				var res := instance_from_id(beh._resource_node_id) as Node2D
				if res != null and is_instance_valid(res):
					res_center = res.global_position
			_sweep_collect(beh, node, res_center, ORBIT_COLLECT_DIST_SQ)
		elif beh.pending_collect_id != 0:
			# Al llegar al drop: recoger todos los cercanos de una vez
			_sweep_collect(beh, node, node_pos, LOOT_ARRIVE_COLLECT_SQ)
		_handle_cargo_deposit(beh, node)


# ---------------------------------------------------------------------------
# Camp barrel management — one real barrel_world.tscn per camp group
# ---------------------------------------------------------------------------

func _ensure_camp_barrels() -> void:
	for group_id in BanditGroupMemory.get_all_group_ids():
		var barrel_id: int = int(_camp_barrels.get(group_id, 0))
		if barrel_id != 0 and is_instance_id_valid(barrel_id):
			var existing := instance_from_id(barrel_id) as Node
			if existing != null and is_instance_valid(existing) \
					and not existing.is_queued_for_deletion():
				_update_deposit_pos(group_id, (existing as Node2D).global_position)
				continue  # barrel is alive
		# Barrel missing or destroyed — spawn a new one
		var g: Dictionary = BanditGroupMemory.get_group(group_id)
		if (g.get("member_ids", []) as Array).is_empty():
			continue   # no active members — don't spawn barrel yet
		var home: Vector2 = g.get("home_world_pos", Vector2.ZERO)
		var barrel := _spawn_camp_barrel(home, 0)
		if barrel != null:
			_camp_barrels[group_id] = barrel.get_instance_id()
			_update_deposit_pos(group_id, (barrel as Node2D).global_position)


## Propaga la posición del barril a todos los comportamientos del grupo.
## Cada NPC recibe un punto personal alrededor del barril (ángulo determinista por member_id)
## para que se distribuyan en todos los lados en vez de apilarse en uno.
func _update_deposit_pos(group_id: String, barrel_pos: Vector2) -> void:
	for eid in _behaviors:
		var beh: BanditWorldBehavior = _behaviors[eid]
		if beh.group_id != group_id:
			continue
		# Si ya tiene un punto asignado cerca de este barril, no reasignar
		if beh.deposit_pos != Vector2.ZERO \
				and beh.deposit_pos.distance_squared_to(barrel_pos) < 72.0 * 72.0:
			continue
		# Ángulo y radio deterministas según member_id → siempre el mismo slot por NPC
		var h := absi(hash(beh.member_id))
		var angle := (h % 36) * (TAU / 36.0)   # 36 posiciones uniformes alrededor
		var radius := 32.0 + float(h % 20)      # 32–52 px desde el centro del barril
		beh.deposit_pos = barrel_pos + Vector2(cos(angle), sin(angle)) * radius


func _spawn_camp_barrel(home_pos: Vector2, column: int = 0) -> Node:
	if CAMP_BARREL_SCENE == null:
		push_warning("[BanditBL] CAMP_BARREL_SCENE not loaded")
		return null
	var barrel := CAMP_BARREL_SCENE.instantiate()
	var world := get_tree().current_scene
	world.add_child(barrel)
	barrel.global_position = home_pos + Vector2(64.0 + column * 32.0, 0.0)
	Debug.log("camp_stash", "[BanditBL] spawned camp barrel at=%s col=%d" % [str(home_pos), column])
	return barrel


# ---------------------------------------------------------------------------
# Mining — called when behavior emits a pending_mine_id
# ---------------------------------------------------------------------------

func _handle_mining(beh: BanditWorldBehavior, enemy_node: Node) -> void:
	var mine_id: int = beh.pending_mine_id
	if mine_id == 0:
		return
	beh.pending_mine_id = 0
	if not is_instance_id_valid(mine_id):
		beh._resource_node_id = 0
		return
	var res_node: Node = instance_from_id(mine_id) as Node
	if res_node == null or not is_instance_valid(res_node):
		beh._resource_node_id = 0
		return
	# Solo pegar si el NPC está en rango melee (radio máximo de órbita + margen)
	const MINE_RANGE_SQ: float = 52.0 * 52.0
	var enemy_pos: Vector2 = (enemy_node as Node2D).global_position
	var res_pos:   Vector2 = (res_node   as Node2D).global_position
	if enemy_pos.distance_squared_to(res_pos) > MINE_RANGE_SQ:
		return   # todavía acercándose — no hay golpe desde lejos

	res_node.hit(enemy_node)   # resource handles sfx, particles, drop spawn
	# Animación de slash melee — spawn_slash directo para no activar el arco
	if enemy_node != null and is_instance_valid(enemy_node) \
			and enemy_node.has_method("spawn_slash"):
		var dir: Vector2 = res_pos - enemy_pos
		enemy_node.call("spawn_slash", dir.angle())


# ---------------------------------------------------------------------------
# Aggro drop — enemy con carry entra en combate y suelta todo al suelo
# ---------------------------------------------------------------------------

func _drop_carry_on_aggro(beh: BanditWorldBehavior, enemy_node: Node) -> void:
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
				# Si ya fue soltado por _drop_carried_items en enemy.gd, no relanzar
				if drop_node.is_in_group("item_drop"):
					continue
				drop_node.reparent(get_tree().current_scene, false)
				drop_node.add_to_group("item_drop")
				drop_node.set_deferred("collision_layer", orig_layer)
				drop_node.set_deferred("monitoring",      true)
				drop_node.set_process(true)
				drop_node.throw_from(drop_pos, throw_dir, randf_range(55.0, 110.0))
				continue

		# Fallback: el nodo no sobrevivió — spawnear uno nuevo y lanzarlo
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
	beh.cargo_count                  = 0
	beh._just_arrived_home_with_cargo = false
	Debug.log("bandit_ai", "[BanditBL] carry soltado al entrar en combate id=%s" % beh.member_id)


# ---------------------------------------------------------------------------
# Orbit drop collection — picks up drops spawned directly under the NPC while mining
# ---------------------------------------------------------------------------

# Radio de recogida durante órbita (desde el centro del recurso)
const ORBIT_COLLECT_DIST_SQ: float = 56.0 * 56.0
# Radio de recogida al llegar a un drop via LOOT_APPROACH (recoge todo lo cercano)
const LOOT_ARRIVE_COLLECT_SQ: float = 40.0 * 40.0

## Recoge en un solo barrido todos los drops dentro de radius_sq desde check_pos.
## Los sonidos salen escalonados (tururur). Llamar solo si !beh.is_cargo_full().
func _sweep_collect(beh: BanditWorldBehavior, enemy_node: Node, check_pos: Vector2, radius_sq: float) -> void:
	if beh.is_cargo_full():
		return
	var sound_idx := 0
	for drop in _all_drops_cache:
		if beh.is_cargo_full():
			break
		var drop_node := drop as Node2D
		if not is_instance_valid(drop_node) or drop_node.is_queued_for_deletion():
			continue
		if not drop_node.is_in_group("item_drop"):
			continue   # ya recogido por otro NPC este tick
		if check_pos.distance_squared_to(drop_node.global_position) > radius_sq:
			continue
		beh.pending_collect_id = drop_node.get_instance_id()
		_handle_collection(beh, enemy_node, sound_idx * 0.07)
		sound_idx += 1


# ---------------------------------------------------------------------------
# Collection — called when behavior arrives at a drop
# ---------------------------------------------------------------------------

func _handle_collection(beh: BanditWorldBehavior, enemy_node: Node = null, sound_delay: float = 0.0) -> void:
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

	# Sonido escalonado (tururur cuando se recogen varios de un jalon)
	if sound_delay <= 0.0:
		AudioSystem.play_2d(sfx_stream, drop_pos, null, &"SFX")
	else:
		get_tree().create_timer(sound_delay).timeout.connect(func() -> void:
			AudioSystem.play_2d(sfx_stream, drop_pos, null, &"SFX")
		)

	# ── Visual carry: reparentar el ItemDrop al enemy para verlo encima ──────
	var carried: bool = false
	if enemy_node != null and is_instance_valid(enemy_node):
		var orig_layer: int = drop_node.collision_layer
		# Sacar del grupo para que _all_drops_cache no lo vuelva a recoger
		drop_node.remove_from_group("item_drop")
		drop_node.set_deferred("monitoring",      false)
		drop_node.set_deferred("collision_layer", 0)
		drop_node.set_process(false)
		# Stack: primer item a (0,-22), siguiente a (0,-30), etc.
		var stack_offset := Vector2(0.0, -22.0 - beh._cargo_manifest.size() * 8.0)
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

	Debug.log("bandit_ai", "[BanditBL] collected %s×%d id=%s cargo=%d→%d/%d" % [
		item_id, collected_amount, beh.member_id, prev, beh.cargo_count, beh.cargo_capacity])


# ---------------------------------------------------------------------------
# Cargo deposit — called once when NPC arrives home carrying cargo
# ---------------------------------------------------------------------------

func _handle_cargo_deposit(beh: BanditWorldBehavior, enemy_node: Node) -> void:
	if not beh._just_arrived_home_with_cargo:
		return
	beh._just_arrived_home_with_cargo = false
	beh.cargo_count = 0

	var spawn_pos: Vector2 = beh.home_pos
	if enemy_node != null and is_instance_valid(enemy_node):
		spawn_pos = (enemy_node as Node2D).global_position

	# 1) Prefer the camp's own barrel (direct lookup by group_id, no proximity check needed)
	var chest: Node = null
	if beh.group_id != "":
		var barrel_id: int = int(_camp_barrels.get(beh.group_id, 0))
		if barrel_id != 0 and is_instance_id_valid(barrel_id):
			var bn := instance_from_id(barrel_id) as Node
			if bn != null and is_instance_valid(bn) and not bn.is_queued_for_deletion():
				chest = bn

	# 2) Fallback: any nearby interactable with insert support
	if chest == null:
		for node in get_tree().get_nodes_in_group("interactable"):
			if not node.has_method("try_insert_item") or not node.has_method("is_position_nearby"):
				continue
			if node.call("is_position_nearby", spawn_pos):
				chest = node
				break

	const FALL_TIME:   float = 0.25   # duración de la caída (igual que CarryableComponent)
	const SFX_STAGGER: float = 0.07   # delay entre sonidos (tururur)

	# Items caen hacia el barril/cofre, no hacia los pies del NPC
	var land_target: Vector2 = spawn_pos
	if chest != null and chest is Node2D:
		land_target = (chest as Node2D).global_position

	for i in beh._cargo_manifest.size():
		var entry: Dictionary = beh._cargo_manifest[i]
		var node_id: int    = int(entry.get("node_id",    0))
		var item_id: String = String(entry.get("item_id", ""))
		var amount: int     = int(entry.get("amount",     1))
		var orig_layer: int = int(entry.get("orig_layer", 4))
		var offset    := Vector2(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0))
		var ground_pos := land_target + offset

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
			drop_node.global_position = spawn_pos + Vector2(0.0, -22.0 - i * 8.0)

		# Reparentar a la escena manteniendo la posición elevada del carry
		var carry_pos := drop_node.global_position
		if drop_node.get_parent() != get_tree().current_scene:
			drop_node.reparent(get_tree().current_scene, false)
		drop_node.global_position = carry_pos   # elevar antes de la caída

		# Caída animada desde la altura de carry hasta el suelo
		var tw := create_tween()
		tw.tween_property(drop_node, "global_position", ground_pos, FALL_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

		var cap_drop    := drop_node
		var cap_item_id := item_id
		var cap_amount  := amount
		var cap_sfx: AudioStream = drop_node.get("pickup_sfx") as AudioStream
		var cap_group_id := beh.group_id

		if chest != null:
			# Con cofre/barril: sfx al aterrizar + absorber con stagger (tururur)
			var deposit_delay := FALL_TIME + i * SFX_STAGGER
			get_tree().create_timer(deposit_delay).timeout.connect(func() -> void:
				if not is_instance_valid(cap_drop) or cap_drop.is_queued_for_deletion():
					return
				var inserted := int(chest.call("try_insert_item", cap_item_id, cap_amount))
				if inserted > 0:
					if cap_sfx != null:
						AudioSystem.play_2d(cap_sfx, spawn_pos, null, &"SFX")
					cap_drop.queue_free()
					return
				# Barril lleno — spawnear uno nuevo para este camp y reintentar
				if cap_group_id != "":
					var col: int = 0
					for gid in _camp_barrels:
						if String(gid).begins_with(cap_group_id):
							col += 1
					var new_barrel := _spawn_camp_barrel(spawn_pos, col)
					if new_barrel != null:
						_camp_barrels[cap_group_id + "_extra_%d" % col] = new_barrel.get_instance_id()
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
			# Sin barril — spawnear uno nuevo en la posición de depósito e insertar ahí
			var cap_group_id2 := beh.group_id
			var cap_deposit   := land_target
			get_tree().create_timer(FALL_TIME).timeout.connect(func() -> void:
				if not is_instance_valid(cap_drop) or cap_drop.is_queued_for_deletion():
					return
				var new_barrel := _spawn_camp_barrel(cap_deposit - Vector2(36.0, 0.0), 0)
				if new_barrel != null and cap_group_id2 != "":
					_camp_barrels[cap_group_id2] = new_barrel.get_instance_id()
					_update_deposit_pos(cap_group_id2, new_barrel.global_position)
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
	# Notify behavior to leave the barrel area immediately
	beh.on_deposit_complete()
	Debug.log("bandit_ai", "[BanditBL] cargo depositado id=%s pos=%s chest=%s" % [
		beh.member_id, str(spawn_pos), str(chest != null)])


# ---------------------------------------------------------------------------
# ctx builders — filter world-cache lists by proximity
# ---------------------------------------------------------------------------

func _build_drops_info(node_pos: Vector2) -> Array:
	var result: Array = []
	for drop in _all_drops_cache:
		var drop_node := drop as Node2D
		if drop_node == null or not is_instance_valid(drop_node) \
				or drop_node.is_queued_for_deletion():
			continue
		if node_pos.distance_squared_to(drop_node.global_position) > LOOT_SCAN_RADIUS_SQ:
			continue
		result.append({
			"id":     drop_node.get_instance_id(),
			"pos":    drop_node.global_position,
			"amount": int(drop_node.get("amount") if drop_node.get("amount") != null else 1),
		})
	return result


func _build_res_info(node_pos: Vector2) -> Array:
	var result: Array = []
	for res in _all_resources_cache:
		var res_node := res as Node2D
		if res_node == null or not is_instance_valid(res_node) \
				or res_node.is_queued_for_deletion():
			continue
		if node_pos.distance_squared_to(res_node.global_position) > RESOURCE_SCAN_RADIUS_SQ:
			continue
		result.append({"pos": res_node.global_position, "id": res_node.get_instance_id()})
	return result


# ---------------------------------------------------------------------------
# Lazy behavior creation
# ---------------------------------------------------------------------------

func _ensure_behaviors_for_active_enemies() -> void:
	for enemy_id in _npc_simulator.active_enemies:
		var enemy_id_str: String = String(enemy_id)
		if _behaviors.has(enemy_id_str):
			continue
		var node = _npc_simulator._get_active_enemy_node(enemy_id_str)
		if node == null or not node.has_method("is_world_behavior_eligible") \
				or not node.is_world_behavior_eligible():
			continue
		var save_state: Dictionary = _get_save_state_for(enemy_id_str)
		if save_state.is_empty() or String(save_state.get("group_id", "")) == "":
			continue
		var beh := BanditWorldBehavior.new()
		beh.setup({
			"home_pos":      _get_home_pos(save_state),
			"role":          String(save_state.get("role", "scavenger")),
			"group_id":      String(save_state.get("group_id", "")),
			"member_id":     enemy_id_str,
			"cargo_count":   int(save_state.get("cargo_count", 0)),
		})
		# Import behavior state for continuity (from data-only or previous session)
		var wb = save_state.get("world_behavior", {})
		if wb is Dictionary and not (wb as Dictionary).is_empty():
			beh.import_state(wb as Dictionary)
		else:
			beh._rng.seed = absi(int(save_state.get("seed", 0)) ^ hash(enemy_id_str))
			beh._idle_timer = beh._rng.randf_range(NpcWorldBehavior.IDLE_WAIT_MIN, NpcWorldBehavior.IDLE_WAIT_MAX)
		_behaviors[enemy_id_str] = beh
		Debug.log("bandit_ai", "[BanditBL] behavior created id=%s role=%s group=%s cargo_cap=%d home=%s" % [
			enemy_id_str, beh.role, beh.group_id, beh.cargo_capacity, str(beh.home_pos)])


# ---------------------------------------------------------------------------
# Pruning
# ---------------------------------------------------------------------------

func _prune_behaviors() -> void:
	var to_remove: Array = []
	for enemy_id in _behaviors:
		if _npc_simulator._get_active_enemy_node(enemy_id) == null:
			to_remove.append(enemy_id)
	for enemy_id in to_remove:
		_behaviors.erase(enemy_id)
		if NpcPathService.is_ready():
			NpcPathService.clear_agent(enemy_id)
		Debug.log("bandit_ai", "[BanditBL] behavior pruned id=%s" % enemy_id)


func _get_behavior(enemy_id: String) -> BanditWorldBehavior:
	return _behaviors.get(enemy_id, null) as BanditWorldBehavior


# ---------------------------------------------------------------------------
# Save-state helpers
# ---------------------------------------------------------------------------

func _get_save_state_for(enemy_id: String) -> Dictionary:
	var chunk_key: String = _npc_simulator._get_active_enemy_chunk_key(enemy_id)
	if chunk_key == "":
		return {}
	var chunk_states: Dictionary = WorldSave.enemy_state_by_chunk.get(chunk_key, {})
	var state_v = chunk_states.get(enemy_id, {})
	if state_v is Dictionary:
		return state_v as Dictionary
	return {}


func _get_home_pos(save_state: Dictionary) -> Vector2:
	var hp = save_state.get("home_world_pos", null)
	if hp is Vector2:
		return hp
	if hp is Dictionary:
		return Vector2(float((hp as Dictionary).get("x", 0.0)), float((hp as Dictionary).get("y", 0.0)))
	return Vector2.ZERO
