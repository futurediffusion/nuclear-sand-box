extends Node
class_name BanditExtortionDirector

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

	var leader_id: String = ""
	var assigned_ids: Array[String] = []
	var taunt_speaker_id: String = ""
	var phase: Phase = Phase.APPROACHING

	func _init(p_leader_id: String, p_assigned_ids: Array[String]) -> void:
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
const TAUNT_RANGE_SQ: float = 300.0 * 300.0
const COLLECT_RANGE_SQ: float = 160.0 * 160.0
const EXTORT_PAY_AMOUNT: int = 10
const CHOICE_SCENE: PackedScene = preload("res://scenes/ui/extortion_choice_bubble.tscn")

var _npc_simulator: NpcSimulator = null
var _player: Node2D = null
var _bubble_manager: WorldSpeechBubbleManager = null
var _active_extortions: Dictionary = {} # gid -> ExtortionJob
var _extortion_choice_node: Node = null

var _get_behavior_for_enemy: Callable = Callable()


func setup(ctx: Dictionary) -> void:
	_npc_simulator = ctx.get("npc_simulator")
	_player = ctx.get("player")
	_bubble_manager = ctx.get("speech_bubble_manager")
	_get_behavior_for_enemy = ctx.get("get_behavior_for_enemy", Callable())


func process_extortion() -> void:
	_consume_extortion_queue()


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
					var anode = _npc_simulator._get_active_enemy_node(aid)
					if anode != null and "suppress_ai" in anode:
						anode.suppress_ai = true
					var behavior: BanditWorldBehavior = _behavior_for_enemy(aid)
					if behavior != null:
						behavior.force_return_home()
				Debug.log("extortion", "[EXTORT] aggro resolved (player downed) group=%s" % gid)
			continue

		if job.needs_warning_strike():
			var speaker_id: String = job.taunt_speaker_id
			var speaker = _npc_simulator._get_active_enemy_node(speaker_id) if speaker_id != "" else null
			if speaker == null:
				job.mark_aborted()
			else:
				var to_player: Vector2 = player_pos - (speaker as Node2D).global_position
				var dist: float = to_player.length()
				var atk_range: float = 76.0
				if "attack_range" in speaker:
					atk_range = float(speaker.get("attack_range")) + 8.0
				if dist <= atk_range:
					if speaker.has_method("begin_scripted_warning_strike"):
						speaker.begin_scripted_warning_strike(player_pos, 7.0)
					job.mark_resolved()
					for aid: String in job.assigned_ids:
						var behavior: BanditWorldBehavior = _behavior_for_enemy(aid)
						if behavior != null:
							behavior.force_return_home()
					Debug.log("extortion", "[EXTORT] warn strike delivered group=%s" % gid)
				else:
					if "suppress_ai" in speaker:
						speaker.suppress_ai = true
					(speaker as Node2D).velocity = to_player.normalized() * (75.0 + friction_compensation)
			continue

		if job.is_collecting():
			continue

		for eid in job.assigned_ids:
			var enode = _npc_simulator._get_active_enemy_node(eid)
			if enode == null:
				continue
			if "suppress_ai" in enode:
				enode.suppress_ai = true
			var to_player: Vector2 = player_pos - enode.global_position
			if to_player.length() > 1.0:
				enode.velocity = to_player.normalized() * (55.0 + friction_compensation)


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
		Debug.log("extortion", "[EXTORT TEST] job cleaned group=%s" % gid)

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
				if (enode as Node2D).global_position.distance_squared_to(player_pos) > TAUNT_RANGE_SQ:
					continue
				job.mark_taunted(eid)
				var phrase: String = TAUNT_PHRASES[randi() % TAUNT_PHRASES.size()]
				_bubble_manager.show_actor_bubble(enode as Node2D, phrase, 3.5)
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
			if not job_collect.has_taunted():
				continue
			for eid in job_collect.assigned_ids:
				var enode_collect = _npc_simulator._get_active_enemy_node(eid)
				if enode_collect == null or not is_instance_valid(enode_collect):
					continue
				if (enode_collect as Node2D).global_position.distance_squared_to(player_pos_collect) > COLLECT_RANGE_SQ:
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
		var assigned: Array = [leader_id]
		for i in mini(2, guards.size()):
			assigned.append(guards[i]["id"])
		_active_extortions[gid] = ExtortionJob.new(leader_id, assigned)
		for aid in assigned:
			var anode = _npc_simulator._get_active_enemy_node(aid)
			if anode != null and "suppress_ai" in anode:
				anode.suppress_ai = true
		Debug.log("extortion", "[EXTORT TEST] job started group=%s leader=%s assigned=%d" % [
			gid, leader_id, assigned.size()])


func _show_extortion_choice(gid: String) -> void:
	if _extortion_choice_node != null and is_instance_valid(_extortion_choice_node):
		_extortion_choice_node.queue_free()

	var bubble: ExtortionChoiceBubble = CHOICE_SCENE.instantiate() as ExtortionChoiceBubble
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var visual: Vector2 = bubble.custom_minimum_size * 0.5
	bubble.position = (vp_size - visual) * 0.5
	bubble.choice_made.connect(func(option: int): _on_extortion_choice(option, gid), CONNECT_ONE_SHOT)

	_bubble_manager.add_child(bubble)
	bubble.set_main_text("¿Entonces qué?\n¿Pagas o prefieres problemas?")
	_extortion_choice_node = bubble

	var cursor := get_tree().root.find_child("MouseCursor", true, false)
	if cursor != null:
		cursor.process_mode = Node.PROCESS_MODE_ALWAYS

	get_tree().paused = true
	Debug.log("extortion", "[EXTORT] choice bubble shown group=%s" % gid)


func _on_extortion_choice(option: int, gid: String) -> void:
	var cursor := get_tree().root.find_child("MouseCursor", true, false)
	if cursor != null:
		cursor.process_mode = Node.PROCESS_MODE_INHERIT

	get_tree().paused = false
	_extortion_choice_node = null

	if not _active_extortions.has(gid):
		return
	var job: ExtortionJob = _active_extortions[gid] as ExtortionJob
	if job == null:
		return

	match option:
		1:
			var inv := _player.get_node_or_null("InventoryComponent") as InventoryComponent
			if inv != null and inv.gold >= EXTORT_PAY_AMOUNT:
				inv.spend_gold(EXTORT_PAY_AMOUNT)
				Debug.log("extortion", "[EXTORT] paid %d gold group=%s" % [EXTORT_PAY_AMOUNT, gid])
				_resolve_extortion_idle(job)
			else:
				Debug.log("extortion", "[EXTORT] can't pay, forced refuse group=%s" % gid)
				_resolve_extortion_warn(job)
		2:
			_resolve_extortion_warn(job)
		3:
			_resolve_extortion_aggro(job)


func _resolve_extortion_idle(job: ExtortionJob) -> void:
	job.mark_resolved()
	for aid: String in job.assigned_ids:
		var behavior: BanditWorldBehavior = _behavior_for_enemy(aid)
		if behavior != null:
			behavior.force_return_home()
	var ids: Array[String] = job.assigned_ids.duplicate()
	get_tree().create_timer(12.0).timeout.connect(func() -> void:
		for aid: String in ids:
			var anode = _npc_simulator._get_active_enemy_node(aid)
			if anode != null and is_instance_valid(anode) and "suppress_ai" in anode:
				anode.suppress_ai = false
	)
	Debug.log("extortion", "[EXTORT] resolved idle — ai re-enable in 12 s")


func _resolve_extortion_warn(job: ExtortionJob) -> void:
	job.mark_warning_strike()
	Debug.log("extortion", "[EXTORT] warn pending (refuse) — approaching player")


func _resolve_extortion_aggro(job: ExtortionJob) -> void:
	job.mark_full_aggro()
	for aid: String in job.assigned_ids:
		var anode = _npc_simulator._get_active_enemy_node(aid)
		if anode != null and "suppress_ai" in anode:
			anode.suppress_ai = false
	Debug.log("extortion", "[EXTORT] resolved aggro (insult)")


func _behavior_for_enemy(enemy_id: String) -> BanditWorldBehavior:
	if not _get_behavior_for_enemy.is_valid():
		return null
	var behavior = _get_behavior_for_enemy.call(enemy_id)
	return behavior as BanditWorldBehavior
