extends Node
class_name BanditExtortionDirector

# Responsibility boundary:
# BanditExtortionDirector owns the full extortion event lifecycle:
# job acquisition, phase transitions, taunt/choice/warn/aggro/resolution flow,
# and orchestration of low-level enemy control primitives.
#
# Persistence decision:
# Active extortion jobs are intentionally ephemeral runtime state. `_active_extortions`
# is rebuilt only from queued intent + live world conditions and is not serialized.
# If the chunk unloads or the world is reconstructed, the in-flight encounter is
# discarded and the group may later regenerate a new attempt from ExtortionQueue.

class ExtortionJob:
	enum Phase {
		APPROACHING,
		TAUNTED,
		WAITING_CHOICE,
		WARNING_STRIKE,
		FULL_AGGRO,
		RESOLVED,
		ABORTED,
	}

	var group_id: String = ""
	var leader_id: String = ""
	var assigned_ids: Array[String] = []
	var taunt_speaker_id: String = ""
	var phase: Phase = Phase.APPROACHING

	func _init(p_group_id: String, p_leader_id: String, p_assigned_ids: Array[String]) -> void:
		group_id = p_group_id
		leader_id = p_leader_id
		assigned_ids = p_assigned_ids.duplicate()

	func is_finished() -> bool:
		return phase == Phase.RESOLVED or phase == Phase.ABORTED

	func is_aggressive() -> bool:
		return phase == Phase.FULL_AGGRO

	func needs_warning_strike() -> bool:
		return phase == Phase.WARNING_STRIKE

	func is_collecting() -> bool:
		return phase == Phase.WAITING_CHOICE

	func has_taunted() -> bool:
		return phase >= Phase.TAUNTED

	func can_open_choice() -> bool:
		return phase == Phase.TAUNTED

	func mark_taunted(speaker_id: String) -> void:
		taunt_speaker_id = speaker_id
		phase = Phase.TAUNTED

	func mark_waiting_choice() -> void:
		phase = Phase.WAITING_CHOICE

	func mark_warning_strike() -> void:
		phase = Phase.WARNING_STRIKE

	func mark_full_aggro() -> void:
		phase = Phase.FULL_AGGRO

	func mark_resolved() -> void:
		phase = Phase.RESOLVED

	func mark_aborted() -> void:
		phase = Phase.ABORTED


const TAUNT_PHRASES: Array[String] = [
	"Mira quién cree que puede pasar por aquí.",
	"Paga y quizá sigas respirando.",
	"No pongas esa cara. Esto es solo negocios.",
]
const BanditTuningScript := preload("res://scripts/world/BanditTuning.gd")
const CHOICE_SCENE: PackedScene = preload("res://scenes/ui/extortion_choice_bubble.tscn")

var _npc_simulator: NpcSimulator = null
var _player: Node2D = null
var _bubble_manager: WorldSpeechBubbleManager = null
var _active_extortions: Dictionary = {} # gid -> ExtortionJob (runtime-only, not persisted)
var _extortion_choice_node: ExtortionChoiceBubble = null
var _extortion_choice_gid: String = ""
var _closing_extortion_choice_from_selection: bool = false

var _get_behavior_for_enemy: Callable = Callable()
var _post_pay_groups: Dictionary = {}  # gid -> Array[String] of suppressed aids


func setup(ctx: Dictionary) -> void:
	_npc_simulator = ctx.get("npc_simulator")
	_player = ctx.get("player")
	_bubble_manager = ctx.get("speech_bubble_manager")
	_get_behavior_for_enemy = ctx.get("get_behavior_for_enemy", Callable())
	if not ModalWorldUIController.modal_closed.is_connected(_on_modal_closed):
		ModalWorldUIController.modal_closed.connect(_on_modal_closed)


func process_extortion() -> void:
	_abort_invalid_jobs()
	_check_retaliation()
	_consume_extortion_queue()




func _abort_invalid_jobs() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var player_pos: Vector2 = _player.global_position
	for gid in _active_extortions.keys():
		var job: ExtortionJob = _active_extortions[gid] as ExtortionJob
		if job == null or job.is_finished():
			continue
		var reason: String = _get_abort_reason(job.group_id, job, player_pos)
		if reason == "":
			continue
		_abort_job(job.group_id, job, reason)


func _get_abort_reason(gid: String, job: ExtortionJob, player_pos: Vector2) -> String:
	var group_data: Dictionary = BanditGroupMemory.get_group(gid)
	if group_data.is_empty():
		return "group_missing"

	var leader_id: String = String(group_data.get("leader_id", ""))
	if leader_id == "":
		return "leader_dead"
	var leader_node = _npc_simulator._get_active_enemy_node(leader_id)
	if leader_node == null or not is_instance_valid(leader_node):
		return "leader_dead"

	var current_intent: String = String(group_data.get("current_group_intent", "idle"))
	if _intent_strength(current_intent) > _intent_strength("extorting"):
		return "stronger_group_intent:%s" % current_intent

	var member_ids: Array = group_data.get("member_ids", [])
	for aid: String in job.assigned_ids:
		if not member_ids.has(aid):
			return "group_composition_broken"
		var anode = _npc_simulator._get_active_enemy_node(aid)
		if anode == null or not is_instance_valid(anode):
			return "group_composition_broken"

	if job.assigned_ids.size() <= 0:
		return "group_composition_broken"

	if (leader_node as Node2D).global_position.distance_squared_to(player_pos) > BanditTuningScript.extort_abort_distance_sq(gid):
		return "player_too_far"

	if job.taunt_speaker_id != "":
		var speaker = _npc_simulator._get_active_enemy_node(job.taunt_speaker_id)
		if speaker == null or not is_instance_valid(speaker):
			return "speaker_missing"

	return ""


func _intent_strength(intent: String) -> int:
	match intent:
		"idle":
			return 0
		"alerted":
			return 1
		"extorting":
			return 2
		"hunting":
			return 3
		_:
			return 0


func _abort_job(gid: String, job: ExtortionJob, reason: String) -> void:
	if job == null or job.is_finished():
		return
	job.mark_aborted()
	_release_job_ai_control(job)
	_close_extortion_choice_if_matches(gid)
	var group_data: Dictionary = BanditGroupMemory.get_group(gid)
	if String(group_data.get("current_group_intent", "idle")) == "extorting":
		BanditGroupMemory.update_intent(gid, "idle")
	Debug.log("extortion", "[EXTORT ABORT] group=%s reason=%s" % [gid, reason])


func _close_extortion_choice_if_matches(gid: String) -> void:
	if _extortion_choice_gid != gid or _extortion_choice_node == null:
		return
	var node := _extortion_choice_node
	_extortion_choice_node = null
	_extortion_choice_gid = ""
	_closing_extortion_choice_from_selection = false
	ModalWorldUIController.close_modal(node)

func apply_extortion_movement(friction_compensation: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var player_pos: Vector2 = _player.global_position
	for gid in _active_extortions:
		var job: ExtortionJob = _active_extortions[gid] as ExtortionJob
		if job == null or job.is_finished():
			continue

		if job.is_aggressive():
			var dc := _player.get_node_or_null("DownedComponent")
			if dc != null and (dc as DownedComponent).is_downed:
				job.mark_resolved()
				for aid: String in job.assigned_ids:
					# Control was already released by _resolve_extortion_aggro; just send home.
					var behavior: BanditWorldBehavior = _behavior_for_enemy(aid)
					if behavior != null:
						behavior.force_return_home()
				Debug.log("extortion", "[EXTORT] aggro resolved (player downed) group=%s" % gid)
			continue

		if job.needs_warning_strike():
			var speaker_id: String = job.taunt_speaker_id
			var speaker = _npc_simulator._get_active_enemy_node(speaker_id) if speaker_id != "" else null
			if speaker == null:
				_abort_job(job.group_id, job, "speaker_missing")
				Debug.log("extortion", "[EXTORT] warn strike aborted (speaker missing) group=%s" % gid)
			else:
				var to_player: Vector2 = player_pos - (speaker as Node2D).global_position
				var dist: float = to_player.length()
				var atk_range: float = BanditTuningScript.extort_warn_strike_range(job.group_id)
				if "attack_range" in speaker:
					atk_range = float(speaker.get("attack_range")) + BanditTuningScript.extort_warn_strike_range_bonus(job.group_id)
				if dist <= atk_range:
					var reenable_delay: float = BanditTuningScript.extort_ai_reenable_delay(job.group_id)
					if speaker.has_method("begin_scripted_melee_action"):
						# Lock the speaker for the full reenable delay so they also go home
						# without chasing (not just 7 s). Guards stay suppressed via _post_pay_groups.
						speaker.begin_scripted_melee_action(player_pos, reenable_delay)
					job.mark_resolved()
					BanditGroupMemory.update_intent(job.group_id, "idle")
					var ids_warn: Array[String] = job.assigned_ids.duplicate()
					var gid_warn: String = job.group_id
					_post_pay_groups[gid_warn] = ids_warn
					get_tree().create_timer(reenable_delay).timeout.connect(func() -> void:
						_post_pay_groups.erase(gid_warn)
						for aid: String in ids_warn:
							if aid != speaker_id:  # speaker auto-releases via its scripted timer
								_set_enemy_scripted_control(_npc_simulator._get_active_enemy_node(aid), false)
					)
					for aid: String in job.assigned_ids:
						var behavior: BanditWorldBehavior = _behavior_for_enemy(aid)
						if behavior != null:
							behavior.force_return_home()
					Debug.log("extortion", "[EXTORT] warn strike delivered group=%s" % gid)
				else:
					_set_enemy_scripted_control(speaker, true)
					_drive_enemy_toward_point(speaker, player_pos, BanditTuningScript.extort_warn_approach_speed(job.group_id) + friction_compensation)
			continue

		if job.is_collecting():
			continue

		for eid in job.assigned_ids:
			var enode = _npc_simulator._get_active_enemy_node(eid)
			if enode == null:
				continue
			_set_enemy_scripted_control(enode, true)
			_drive_enemy_toward_point(enode, player_pos, BanditTuningScript.extort_group_approach_speed(job.group_id) + friction_compensation)


func _consume_extortion_queue() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var done: Array = []
	for gid in _active_extortions:
		var finished_job: ExtortionJob = _active_extortions[gid] as ExtortionJob
		if finished_job != null and finished_job.is_finished():
			done.append(gid)
	for gid in done:
		_active_extortions.erase(gid)
		Debug.log("extortion", "[EXTORT FLOW] job cleaned group=%s" % gid)

	if _bubble_manager != null:
		var player_pos: Vector2 = _player.global_position
		for gid in _active_extortions:
			var job: ExtortionJob = _active_extortions[gid] as ExtortionJob
			if job == null or job.has_taunted():
				continue
			for eid in job.assigned_ids:
				var enode = _npc_simulator._get_active_enemy_node(eid)
				if enode == null or not is_instance_valid(enode):
					continue
				if (enode as Node2D).global_position.distance_squared_to(player_pos) > BanditTuningScript.extort_taunt_range_sq(job.group_id):
					continue
				job.mark_taunted(eid)
				var phrase: String = TAUNT_PHRASES[randi() % TAUNT_PHRASES.size()]
				_bubble_manager.show_actor_bubble(enode as Node2D, phrase, BanditTuningScript.extort_taunt_bubble_duration(job.group_id))
				Debug.log("extortion", "[EXTORT] taunt group=%s speaker=%s" % [gid, eid])
				break

	if _bubble_manager != null:
		var player_pos_collect: Vector2 = _player.global_position
		for gid in _active_extortions:
			var job_collect: ExtortionJob = _active_extortions[gid] as ExtortionJob
			if job_collect == null or job_collect.is_finished():
				continue
			if job_collect.is_collecting():
				continue
			if not job_collect.can_open_choice():
				continue
			for eid in job_collect.assigned_ids:
				var enode_collect = _npc_simulator._get_active_enemy_node(eid)
				if enode_collect == null or not is_instance_valid(enode_collect):
					continue
				if (enode_collect as Node2D).global_position.distance_squared_to(player_pos_collect) > BanditTuningScript.extort_collect_range_sq(job_collect.group_id):
					continue
				job_collect.mark_waiting_choice()
				_show_extortion_choice(gid)
				Debug.log("extortion", "[EXTORT] collection triggered group=%s speaker=%s" % [gid, eid])
				break

	if not _active_extortions.is_empty():
		return

	for gid in BanditGroupMemory.get_all_group_ids():
		if _active_extortions.has(gid):
			continue
		var group_data: Dictionary = BanditGroupMemory.get_group(gid)
		if String(group_data.get("current_group_intent", "")) != "extorting":
			continue
		var intents: Array = ExtortionQueue.consume_for_group(gid)
		if intents.is_empty():
			continue
		var leader_id: String = String(group_data.get("leader_id", ""))
		if leader_id == "":
			continue
		var leader_node = _npc_simulator._get_active_enemy_node(leader_id)
		var leader_pos: Vector2 = leader_node.global_position if leader_node != null else Vector2.ZERO
		var guards: Array = []
		for mid_v in group_data.get("member_ids", []):
			var mid: String = String(mid_v)
			if mid == leader_id:
				continue
			var mnode = _npc_simulator._get_active_enemy_node(mid)
			if mnode == null:
				continue
			guards.append({"id": mid, "dist_sq": mnode.global_position.distance_squared_to(leader_pos)})
		guards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist_sq"] < b["dist_sq"])
		var assigned: Array[String] = [leader_id]
		for i in mini(2, guards.size()):
			assigned.append(guards[i]["id"])
		_active_extortions[gid] = ExtortionJob.new(gid, leader_id, assigned)
		for aid in assigned:
			var anode = _npc_simulator._get_active_enemy_node(aid)
			_set_enemy_scripted_control(anode, true)
		Debug.log("extortion", "[EXTORT FLOW] job started group=%s leader=%s assigned=%d" % [
			gid, leader_id, assigned.size()])
		break  # one new job per tick; the is_empty() guard prevents stacking


func _show_extortion_choice(gid: String) -> void:
	if _bubble_manager == null:
		return

	var bubble: ExtortionChoiceBubble = CHOICE_SCENE.instantiate() as ExtortionChoiceBubble
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var visual: Vector2 = bubble.custom_minimum_size * bubble.scale
	bubble.position = (vp_size - visual) * 0.5
	bubble.set_main_text("¿Entonces qué?\n¿Pagas o prefieres problemas?")
	bubble.choice_made.connect(func(option: int): _on_extortion_choice(option, gid), CONNECT_ONE_SHOT)

	_extortion_choice_gid = gid
	_extortion_choice_node = ModalWorldUIController.show_modal(
		bubble,
		_bubble_manager,
		"extortion_choice"
	) as ExtortionChoiceBubble
	Debug.log("extortion", "[EXTORT] choice bubble shown group=%s" % gid)


func _on_extortion_choice(option: int, gid: String) -> void:
	_closing_extortion_choice_from_selection = true
	ModalWorldUIController.close_modal(_extortion_choice_node)
	_closing_extortion_choice_from_selection = false
	_extortion_choice_node = null
	_extortion_choice_gid = ""

	if not _active_extortions.has(gid):
		return
	var job: ExtortionJob = _active_extortions[gid] as ExtortionJob
	if job == null:
		return

	match option:
		1:
			var inv := _player.get_node_or_null("InventoryComponent") as InventoryComponent
			var pay_amount: int = BanditTuningScript.extort_pay_amount(gid)
			if inv != null and inv.gold >= pay_amount:
				inv.spend_gold(pay_amount)
				Debug.log("extortion", "[EXTORT] paid %d gold group=%s" % [pay_amount, gid])
				_resolve_extortion_idle(job)
			else:
				Debug.log("extortion", "[EXTORT] can't pay, forced refuse group=%s" % gid)
				_resolve_extortion_warn(job)
		2:
			_resolve_extortion_warn(job)
		3:
			_resolve_extortion_aggro(job)


func _on_modal_closed(reason: String) -> void:
	if reason != "extortion_choice":
		return

	var gid := _extortion_choice_gid
	var closed_from_selection := _closing_extortion_choice_from_selection
	_extortion_choice_node = null
	_extortion_choice_gid = ""
	_closing_extortion_choice_from_selection = false

	if closed_from_selection:
		Debug.log("extortion", "[EXTORT] choice modal closed from confirmed selection group=%s" % gid)
		return

	if gid == "" or not _active_extortions.has(gid):
		return

	var job: ExtortionJob = _active_extortions[gid] as ExtortionJob
	if job == null or not job.is_collecting():
		return

	Debug.log("extortion", "[EXTORT] choice modal closed externally — escalating to warning strike group=%s" % gid)
	_resolve_extortion_warn(job)


func _check_retaliation() -> void:
	# During active jobs: if any assigned bandit was hit and job is not already aggro, go full aggro.
	for gid: String in _active_extortions.keys():
		var job: ExtortionJob = _active_extortions.get(gid) as ExtortionJob
		if job == null or job.is_finished() or job.is_aggressive():
			continue
		for aid: String in job.assigned_ids:
			var anode = _npc_simulator._get_active_enemy_node(aid)
			if anode == null or not is_instance_valid(anode):
				continue
			if "hurt_t" in anode and float(anode.get("hurt_t")) > 0.0:
				Debug.log("extortion", "[EXTORT] retaliation — bandit hit during job group=%s" % gid)
				_resolve_extortion_aggro(job)
				break

	# Post-pay cooldown: if any member is hit, release AI immediately so they can fight back.
	for gid: String in _post_pay_groups.keys():
		var ids: Array = _post_pay_groups[gid] as Array
		var was_hit: bool = false
		for aid in ids:
			var anode = _npc_simulator._get_active_enemy_node(aid)
			if anode != null and is_instance_valid(anode) \
					and "hurt_t" in anode and float(anode.get("hurt_t")) > 0.0:
				was_hit = true
				break
		if was_hit:
			_post_pay_groups.erase(gid)
			for aid in ids:
				var anode = _npc_simulator._get_active_enemy_node(aid)
				_set_enemy_scripted_control(anode, false)
			Debug.log("extortion", "[EXTORT] post-pay retaliation — group=%s ai released early" % gid)


func _resolve_extortion_idle(job: ExtortionJob) -> void:
	job.mark_resolved()
	BanditGroupMemory.update_intent(job.group_id, "idle")
	for aid: String in job.assigned_ids:
		var behavior: BanditWorldBehavior = _behavior_for_enemy(aid)
		if behavior != null:
			behavior.force_return_home()
	var ids: Array[String] = job.assigned_ids.duplicate()
	var gid: String = job.group_id
	_post_pay_groups[gid] = ids
	var reenable_delay: float = BanditTuningScript.extort_ai_reenable_delay(gid)
	get_tree().create_timer(reenable_delay).timeout.connect(func() -> void:
		_post_pay_groups.erase(gid)
		for aid: String in ids:
			var anode = _npc_simulator._get_active_enemy_node(aid)
			_set_enemy_scripted_control(anode, false)
	)
	Debug.log("extortion", "[EXTORT] resolved idle — ai re-enable in %.1f s" % reenable_delay)


func _resolve_extortion_warn(job: ExtortionJob) -> void:
	job.mark_warning_strike()
	Debug.log("extortion", "[EXTORT] warn pending (refuse) — approaching player")


func _resolve_extortion_aggro(job: ExtortionJob) -> void:
	_close_extortion_choice_if_matches(job.group_id)
	job.mark_full_aggro()
	_release_job_ai_control(job)
	Debug.log("extortion", "[EXTORT] resolved aggro")


func _behavior_for_enemy(enemy_id: String) -> BanditWorldBehavior:
	if not _get_behavior_for_enemy.is_valid():
		return null
	var behavior = _get_behavior_for_enemy.call(enemy_id)
	return behavior as BanditWorldBehavior


func _release_job_ai_control(job: ExtortionJob) -> void:
	for aid: String in job.assigned_ids:
		var anode = _npc_simulator._get_active_enemy_node(aid)
		_set_enemy_scripted_control(anode, false)


func _set_enemy_scripted_control(enemy: Node, enabled: bool) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.has_method("set_scripted_control_enabled"):
		enemy.set_scripted_control_enabled(enabled)
	elif "external_ai_override" in enemy:
		enemy.external_ai_override = enabled


func _drive_enemy_toward_point(enemy: Node, target_pos: Vector2, speed: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not enemy is Node2D:
		return
	var to_target: Vector2 = target_pos - (enemy as Node2D).global_position
	if to_target.length() <= 1.0:
		if enemy.has_method("set_scripted_velocity"):
			enemy.set_scripted_velocity(Vector2.ZERO)
		elif "velocity" in enemy:
			enemy.velocity = Vector2.ZERO
		return
	var desired_velocity: Vector2 = to_target.normalized() * speed
	if enemy.has_method("set_scripted_velocity"):
		enemy.set_scripted_velocity(desired_velocity)
	elif "velocity" in enemy:
		enemy.velocity = desired_velocity
