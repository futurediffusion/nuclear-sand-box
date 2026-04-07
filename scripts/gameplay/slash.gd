extends Node2D

const CombatQueryScript := preload("res://scripts/systems/CombatQuery.gd")
const CollisionLayersScript := preload("res://scripts/systems/CollisionLayers.gd")

@export var knockback_strength: float = 120.0
@export var damage: int = 1
@export var CharacterHitbox_active_time: float = 0.10

@onready var anim: AnimatedSprite2D = $Anim
var hitbox: Area2D = null
@onready var sfx: AudioStreamPlayer2D = $Sfx
@onready var impact_sound: AudioStreamPlayer2D = $ImpactSound

@export var pitch_min: float = 0.8
@export var pitch_max: float = 1.2
@export var can_mine: bool = true

@export_group("Target Priority")
@export var destructible_focus_tolerance_px: float = 24.0
@export var wall_focus_tolerance_px: float = 28.0
@export_range(1, 8, 1) var max_destructible_hits_per_swing: int = 3
@export_range(1, 8, 1) var max_wall_hits_per_swing: int = 2
@export var wall_multi_probe_offset_px: float = 16.0


var already_hit := {}
var owner_team: StringName = &"player"
var owner_node: Node = null
var owner_damage_entity: Node = null
var owner_hurtbox: Area2D = null
var did_hitstop: bool = false
var _destructible_hits_this_swing: int = 0
var _closest_destructible_hit_dist_sq: float = -1.0
var _non_wall_hits_this_swing: int = 0
var _closest_non_wall_hit_dist_sq: float = -1.0
var _wall_hits_this_swing: int = 0
var _wall_hit_keys_this_swing: Dictionary = {}
var _aim_world_pos: Vector2 = Vector2.ZERO
var _aim_world_pos_valid: bool = false



func setup(team: StringName, owner: Node) -> void:
	owner_team = team
	owner_node = owner
	owner_damage_entity = null
	owner_hurtbox = null

	if owner_node != null:
		owner_damage_entity = owner_node
		if owner_node.has_node("Hurtbox"):
			owner_hurtbox = owner_node.get_node("Hurtbox") as Area2D

func _ready() -> void:
	hitbox = get_node_or_null("Hitbox")
	_apply_sound_panel_overrides()
	_cache_aim_world_pos()

	if sfx and sfx.stream:
		sfx.pitch_scale = randf_range(pitch_min, pitch_max)
		sfx.play()

	_configure_mask()
	_set_hitbox_enabled(false)
	hitbox.body_entered.connect(_on_body_entered)
	hitbox.area_entered.connect(_on_area_entered)
	call_deferred("_activate_hitbox")

	get_tree().create_timer(CharacterHitbox_active_time).timeout.connect(func():
		if is_instance_valid(self):
			_set_hitbox_enabled(false)
	)

	anim.play("slash")
	anim.animation_finished.connect(_on_anim_finished)

func _activate_hitbox() -> void:
	if hitbox == null:
		return
	_set_hitbox_enabled(true)

func _set_hitbox_enabled(enabled: bool) -> void:
	hitbox.monitoring = enabled
	hitbox.monitorable = enabled
	var shape := hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape:
		shape.disabled = not enabled

func _configure_mask() -> void:
	if hitbox == null:
		return

	# Player + EnemyNPC + Resources + World walls
	hitbox.collision_mask = (1 << 0) | (1 << 2) | (1 << 3) | CollisionLayersScript.WORLD_WALL_LAYER_MASK

func _on_anim_finished() -> void:
	queue_free()

func _try_damage(raw_target: Node) -> void:
	if raw_target == null:
		return

	var normalized := CombatQueryScript.resolve_damage_target(raw_target)
	if normalized.is_empty():
		return

	var target := normalized.get("entity") as Node
	var target_hurtbox := normalized.get("hurtbox") as Area2D
	if target == null:
		return

	if owner_damage_entity != null and target == owner_damage_entity:
		return
	if owner_hurtbox != null and target_hurtbox != null and target_hurtbox == owner_hurtbox:
		return
	if raw_target == owner_node or raw_target == owner_hurtbox:
		return

	if CombatQueryScript.is_owner_related(owner_node, raw_target):
		return
	if CombatQueryScript.is_owner_related(owner_node, target_hurtbox):
		return
	if CombatQueryScript.is_owner_related(owner_node, target):
		return

	var target_world_pos: Vector2 = _resolve_target_world_pos(target, target_hurtbox)

	# Destructibles (hit) son objetos físicos — si el hitbox los toca, están al alcance.
	# El check de pared solo aplica a entidades con take_damage (enemigos con hurtbox).
	if not target.has_method("hit"):
		if _is_target_blocked_by_wall(target, target_hurtbox):
			return

	var id := target.get_instance_id()
	if already_hit.has(id):
		return

	if can_mine and target.has_method("hit"):
		if not _can_hit_destructible_target(target_world_pos):
			return
		already_hit[id] = true
		target.call("hit", owner_node)
		_register_destructible_hit(target_world_pos)
		_register_non_wall_hit(target_world_pos)

		var suppress_default_impact_sound := false
		if target.has_method("suppress_default_impact_sound"):
			suppress_default_impact_sound = bool(target.call("suppress_default_impact_sound"))
		if suppress_default_impact_sound:
			return

		var s: AudioStream = null
		if target.has_method("get_hit_sound"):
			s = target.call("get_hit_sound")

		if s != null:
			impact_sound.stream = s
			impact_sound.play()
		elif not suppress_default_impact_sound and impact_sound and impact_sound.stream:
			impact_sound.play()

		return

	if target.has_method("take_damage"):
		var from_pos := global_position
		if owner_node is Node2D:
			from_pos = (owner_node as Node2D).global_position

		already_hit[id] = true
		target.call("take_damage", damage, from_pos)
		if owner_node != null and owner_node.is_in_group("player") \
				and target.has_method("notify_player_hit"):
			target.call("notify_player_hit")

		# Enemy-vs-enemy hit: initiate a 1v1 duel between them.
		# Neither will re-engage the player or group-up until one dies.
		if owner_node != null and owner_node != target:
			var a_ai: AIComponent = owner_node.get_node_or_null("AIComponent") as AIComponent
			# target puede ser el Hurtbox (Area2D) en lugar del enemy directamente —
			# buscar AIComponent en target, si no, en su padre.
			var v_ai: AIComponent = target.get_node_or_null("AIComponent") as AIComponent
			var duel_victim: Node = target
			if v_ai == null and target.get_parent() != null:
				v_ai = target.get_parent().get_node_or_null("AIComponent") as AIComponent
				if v_ai != null:
					duel_victim = target.get_parent()
			if a_ai != null and v_ai != null:
				# No iniciar duel si alguno está en misión de demolición de estructuras.
				# Evita que el fuego amigo entre bodyguards los saque de la demolition session.
				var in_structure_mission: bool = a_ai.is_structure_focus_active() \
						or v_ai.is_structure_focus_active()
				if not in_structure_mission:
					a_ai.force_target(duel_victim, 25.0)
					v_ai.force_target(owner_node,  25.0)
		_register_non_wall_hit(target_world_pos)

		if impact_sound and impact_sound.stream:
			impact_sound.play()

		if target.has_method("apply_knockback"):
			var knockback_dir: Vector2
			if owner_node is Node2D and target is Node2D:
				knockback_dir = ((target as Node2D).global_position - (owner_node as Node2D).global_position).normalized()
			else:
				knockback_dir = Vector2.RIGHT.rotated(global_rotation)

			target.call("apply_knockback", knockback_dir * knockback_strength)

		if not did_hitstop and target.has_method("apply_hitstop"):
			did_hitstop = true
			target.call("apply_hitstop")


func _is_target_blocked_by_wall(target: Node, target_hurtbox: Area2D = null) -> bool:
	if target == null:
		return false
	if not (target is Node2D):
		return false

	# Usar la posición del dueño (atacante), no la del slash.
	# El slash es Area2D y barre a través de las paredes — su global_position puede estar
	# del lado del objetivo cuando se detecta la colisión, haciendo que el check falle.
	var from_pos := global_position
	if owner_node is Node2D:
		from_pos = (owner_node as Node2D).global_position

	var excluded: Array = [self, target]
	if owner_node != null:
		excluded.append(owner_node)
	if target_hurtbox != null:
		excluded.append(target_hurtbox)

	return CombatQueryScript.is_melee_target_blocked_by_wall(self, from_pos, target, target_hurtbox, excluded)


func _is_slash_overlapping_wall() -> bool:
	if hitbox == null:
		return false

	var shape := hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null or shape.shape == null:
		return false

	var excluded: Array = [self]
	if owner_node != null:
		excluded.append(owner_node)

	return CombatQueryScript.shape_overlaps_wall(self, shape, excluded)

func _try_damage_player_walls_prioritized(force_when_overlapping: bool = false) -> void:
	var max_wall_hits := maxi(1, max_wall_hits_per_swing)
	if _wall_hits_this_swing >= max_wall_hits:
		return
	var world := _get_world_node()
	if world == null:
		return

	var amount: int = maxi(1, damage)
	var radius := _estimate_wall_hit_radius_world()
	var owner_pos := global_position
	if owner_node is Node2D:
		owner_pos = (owner_node as Node2D).global_position

	var candidates := _collect_wall_hit_candidates(owner_pos)
	if candidates.is_empty():
		if force_when_overlapping and _is_slash_overlapping_wall():
			candidates.append({
				"position": global_position,
				"dist_sq": _distance_sq_to_aim(global_position),
			})
		else:
			return

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("dist_sq", 1.0e30)) < float(b.get("dist_sq", 1.0e30))
	)

	var nearest_wall_dist_sq: float = float(candidates[0].get("dist_sq", 1.0e30))
	if not _should_mix_wall_damage(nearest_wall_dist_sq):
		return

	for candidate in candidates:
		if _wall_hits_this_swing >= max_wall_hits:
			break
		var hit_pos: Vector2 = candidate.get("position", global_position)
		var wall_key := _wall_candidate_key(world, hit_pos)
		if wall_key != "" and _wall_hit_keys_this_swing.has(wall_key):
			continue
		var damaged := _damage_wall_at_world_pos(world, hit_pos, amount, radius)
		if not damaged:
			continue
		_wall_hits_this_swing += 1
		if wall_key != "":
			_wall_hit_keys_this_swing[wall_key] = true


func _collect_wall_hit_candidates(owner_pos: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var excluded: Array = [self]
	if owner_node != null:
		excluded.append(owner_node)

	var main_endpoint := global_position
	var base_dir := main_endpoint - owner_pos
	if base_dir.length_squared() < 0.0001:
		base_dir = Vector2.RIGHT.rotated(global_rotation)
	var dir := base_dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var probe_offset := maxf(0.0, wall_multi_probe_offset_px)

	var endpoints: Array[Vector2] = [main_endpoint]
	if probe_offset > 0.0:
		endpoints.append(main_endpoint + perp * probe_offset)
		endpoints.append(main_endpoint - perp * probe_offset)

	for endpoint in endpoints:
		var wall_hit := CombatQueryScript.find_first_wall_hit(self, owner_pos, endpoint, excluded, true)
		if wall_hit.is_empty():
			continue
		var hit_pos: Vector2 = wall_hit.get("position", endpoint)
		_append_wall_candidate(out, hit_pos)

	if _is_slash_overlapping_wall():
		_append_wall_candidate(out, global_position)

	return out


func _append_wall_candidate(candidates: Array[Dictionary], hit_pos: Vector2) -> void:
	for existing in candidates:
		var existing_pos: Vector2 = existing.get("position", Vector2.INF)
		if existing_pos == Vector2.INF:
			continue
		if existing_pos.distance_squared_to(hit_pos) <= 4.0:
			return
	candidates.append({
		"position": hit_pos,
		"dist_sq": _distance_sq_to_aim(hit_pos),
	})


func _should_mix_wall_damage(nearest_wall_dist_sq: float) -> bool:
	if _non_wall_hits_this_swing <= 0:
		return true
	var tol: float = maxf(0.0, wall_focus_tolerance_px)
	var tol_sq: float = tol * tol
	return nearest_wall_dist_sq <= (_closest_non_wall_hit_dist_sq + tol_sq)


func _damage_wall_at_world_pos(world: Node, hit_pos: Vector2, amount: int, radius: float) -> bool:
	var damaged: bool = false
	if world.has_method("hit_wall_at_world_pos"):
		damaged = bool(world.call("hit_wall_at_world_pos", hit_pos, amount, radius, true))
	elif world.has_method("damage_player_wall_at_world_pos"):
		damaged = bool(world.call("damage_player_wall_at_world_pos", hit_pos, amount))
	if damaged and owner_node != null and owner_node.is_in_group("enemy") and "faction_id" in owner_node:
		var fid: String = String(owner_node.get("faction_id"))
		if fid != "":
			FactionHostilityManager.add_hostility(fid, 0.0, "wall_damaged",
				{"position": hit_pos})
	return damaged


func _wall_candidate_key(world: Node, hit_pos: Vector2) -> String:
	if world != null and world.has_method("_world_to_tile"):
		var tile_raw: Variant = world.call("_world_to_tile", hit_pos)
		if tile_raw is Vector2i:
			var tile: Vector2i = tile_raw as Vector2i
			return "%d,%d" % [tile.x, tile.y]
	return "%d,%d" % [floori(hit_pos.x / 16.0), floori(hit_pos.y / 16.0)]

func _estimate_wall_hit_radius_world() -> float:
	var default_radius: float = 20.0
	if hitbox == null:
		return default_radius
	var shape_node := hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return default_radius

	var scale_x: float = absf(hitbox.global_scale.x * shape_node.global_scale.x)
	var scale_y: float = absf(hitbox.global_scale.y * shape_node.global_scale.y)
	var world_scale: float = maxf(scale_x, scale_y)
	var shape := shape_node.shape

	if shape is CircleShape2D:
		return maxf((shape as CircleShape2D).radius * world_scale, default_radius)
	if shape is RectangleShape2D:
		var half_size: Vector2 = (shape as RectangleShape2D).size * 0.5
		return maxf(maxf(half_size.x, half_size.y) * world_scale, default_radius)
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		return maxf(maxf(capsule.radius, capsule.height * 0.5) * world_scale, default_radius)

	return default_radius

func _get_world_node() -> Node:
	var worlds := get_tree().get_nodes_in_group("world")
	if worlds.is_empty():
		return null
	return worlds[0]

func _on_body_entered(body: Node) -> void:
	var body_pos: Vector2 = (body as Node2D).global_position if body is Node2D else Vector2.INF
	if CombatQueryScript.is_wall_obstacle_hit(self, body, body_pos) and CombatQueryScript.resolve_damage_target(body).is_empty():
		# Solo activar daño a paredes si es un cuerpo de pared real del mundo,
		# no un prop estático sin método hit() que esté en la misma layer.
		if body.is_in_group("world_wall_body"):
			_try_damage_player_walls_prioritized()
		return
	_try_damage(body)

func _on_area_entered(area: Area2D) -> void:
	_try_damage(area)


func _resolve_target_world_pos(target: Node, target_hurtbox: Area2D = null) -> Vector2:
	if target_hurtbox != null:
		return target_hurtbox.global_position
	if target is Node2D:
		return (target as Node2D).global_position
	return global_position


func _can_hit_destructible_target(target_world_pos: Vector2) -> bool:
	if _destructible_hits_this_swing <= 0:
		return true
	if _destructible_hits_this_swing >= maxi(1, max_destructible_hits_per_swing):
		return false
	var tol: float = maxf(0.0, destructible_focus_tolerance_px)
	var tol_sq: float = tol * tol
	var target_dist_sq: float = _distance_sq_to_aim(target_world_pos)
	return target_dist_sq <= (_closest_destructible_hit_dist_sq + tol_sq)


func _register_destructible_hit(target_world_pos: Vector2) -> void:
	var target_dist_sq: float = _distance_sq_to_aim(target_world_pos)
	if _destructible_hits_this_swing <= 0:
		_closest_destructible_hit_dist_sq = target_dist_sq
	else:
		_closest_destructible_hit_dist_sq = minf(_closest_destructible_hit_dist_sq, target_dist_sq)
	_destructible_hits_this_swing += 1


func _register_non_wall_hit(target_world_pos: Vector2) -> void:
	var target_dist_sq: float = _distance_sq_to_aim(target_world_pos)
	if _non_wall_hits_this_swing <= 0:
		_closest_non_wall_hit_dist_sq = target_dist_sq
	else:
		_closest_non_wall_hit_dist_sq = minf(_closest_non_wall_hit_dist_sq, target_dist_sq)
	_non_wall_hits_this_swing += 1


func _cache_aim_world_pos() -> void:
	_aim_world_pos_valid = false

	if owner_node != null and owner_node.has_method("get_world_mouse_pos"):
		var raw_mouse: Variant = owner_node.call("get_world_mouse_pos")
		if raw_mouse is Vector2:
			_aim_world_pos = raw_mouse as Vector2
			_aim_world_pos_valid = true

	if not _aim_world_pos_valid and owner_node is Node2D:
		var owner_pos := (owner_node as Node2D).global_position
		var forward := Vector2.RIGHT.rotated(global_rotation)
		_aim_world_pos = owner_pos + forward * _estimate_wall_hit_radius_world()
		_aim_world_pos_valid = true

	if not _aim_world_pos_valid:
		var forward_fallback := Vector2.RIGHT.rotated(global_rotation)
		_aim_world_pos = global_position + forward_fallback * _estimate_wall_hit_radius_world()
		_aim_world_pos_valid = true


func _distance_sq_to_aim(world_pos: Vector2) -> float:
	if not _aim_world_pos_valid:
		_cache_aim_world_pos()
	return world_pos.distance_squared_to(_aim_world_pos)


func _apply_sound_panel_overrides() -> void:
	var panel := _resolve_sound_panel()
	if panel == null:
		return
	if sfx != null:
		if panel.slash_swing_sfx != null:
			sfx.stream = panel.slash_swing_sfx
		sfx.volume_db = panel.slash_swing_volume_db
	if impact_sound != null:
		var npc_hit := panel.npc_enemy_hit_sfx
		if npc_hit != null:
			impact_sound.stream = npc_hit
			impact_sound.volume_db = panel.npc_enemy_hit_volume_db
		elif panel.slash_impact_sfx != null:
			impact_sound.stream = panel.slash_impact_sfx
			impact_sound.volume_db = panel.slash_impact_volume_db
		else:
			impact_sound.volume_db = panel.npc_enemy_hit_volume_db


func _resolve_sound_panel() -> SoundPanel:
	if AudioSystem == null or not AudioSystem.has_method("get_sound_panel"):
		return null
	var node: Node = AudioSystem.get_sound_panel()
	if node is SoundPanel:
		return node as SoundPanel
	return null
