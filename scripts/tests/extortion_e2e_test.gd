extends Node2D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const DIRECTOR_SCRIPT = preload("res://scripts/world/BanditExtortionDirector.gd")

const GROUP_ID := "test:extortion_e2e"
const FACTION_ID := "bandits"
const LEADER_ID := "test_leader"
const GUARD_A_ID := "test_guard_a"
const GUARD_B_ID := "test_guard_b"
const PAY_OPTION := 1
const REFUSE_OPTION := 2
const INSULT_OPTION := 3
const PLAYER_FAR_POS := Vector2(1540, 580)
const LEADER_GOLD := 50

class TestBehavior:
	extends RefCounted

	# Lightweight test double used only for `force_return_home()` so the scene can
	# observe retreat resolution without depending on the full runtime behavior stack.

	var enemy: Node2D
	var home_pos: Vector2

	func _init(p_enemy: Node2D) -> void:
		enemy = p_enemy
		home_pos = p_enemy.global_position

	func force_return_home() -> void:
		if enemy == null or not is_instance_valid(enemy):
			return
		enemy.global_position = home_pos
		if enemy.has_method("set_scripted_velocity"):
			enemy.set_scripted_velocity(Vector2.ZERO)


@onready var _status_label: Label = $UI/DebugPanel/Margin/VBox/StatusLabel
@onready var _hint_label: Label = $UI/DebugPanel/Margin/VBox/HintLabel
@onready var _player_anchor: Marker2D = $Anchors/PlayerAnchor
@onready var _leader_anchor: Marker2D = $Anchors/LeaderAnchor
@onready var _guard_a_anchor: Marker2D = $Anchors/GuardAAnchor
@onready var _guard_b_anchor: Marker2D = $Anchors/GuardBAnchor
@onready var _world_layer: Node2D = $WorldLayer
@onready var _bubble_manager: WorldSpeechBubbleManager = $WorldSpeechBubbleManager
@onready var _npc_simulator: NpcSimulator = $NpcSimulator

var _player: Player
var _leader: EnemyAI
var _guard_a: EnemyAI
var _guard_b: EnemyAI
var _director: BanditExtortionDirector
var _behaviors: Dictionary = {}
var _status_history: PackedStringArray = []


func _ready() -> void:
	$UI/DebugPanel/Margin/VBox/Buttons/TriggerButton.pressed.connect(_trigger_extortion)
	$UI/DebugPanel/Margin/VBox/Buttons/ResetButton.pressed.connect(reset_environment)
	$UI/DebugPanel/Margin/VBox/Buttons/PayButton.pressed.connect(func() -> void: _choose_option(PAY_OPTION))
	$UI/DebugPanel/Margin/VBox/Buttons/RefuseButton.pressed.connect(func() -> void: _choose_option(REFUSE_OPTION))
	$UI/DebugPanel/Margin/VBox/Buttons/InsultButton.pressed.connect(func() -> void: _choose_option(INSULT_OPTION))
	$UI/DebugPanel/Margin/VBox/Buttons/KillLeaderButton.pressed.connect(_kill_leader)
	$UI/DebugPanel/Margin/VBox/Buttons/MoveFarButton.pressed.connect(_move_player_far)
	$UI/DebugPanel/Margin/VBox/Buttons/DeleteSpeakerButton.pressed.connect(_delete_speaker)
	reset_environment()
	_hint_label.text = "Atajos: T encola extorsión · 1 pagar · 2 negarse · 3 insultar · K matar líder · F alejar player · X borrar speaker"
	_append_status("Escena lista. Usa 'Trigger extorsión' para iniciar el flujo.")


func _exit_tree() -> void:
	if _director != null and is_instance_valid(_director):
		_director.queue_free()
	ExtortionQueue.reset()
	BanditGroupMemory.reset()
	ModalWorldUIController.close_modal()
	get_tree().paused = false


func _process(_delta: float) -> void:
	if _director == null:
		return
	_director.process_extortion()
	# This manual scene advances movement from `_process()` with zero friction
	# compensation for determinism and easy inspection. It is intentionally close
	# to the runtime flow, but not a byte-for-byte simulation of `_physics_process()`.
	_director.apply_extortion_movement(0.0)
	_update_status_label()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_T:
				_trigger_extortion()
			KEY_1:
				_choose_option(PAY_OPTION)
			KEY_2:
				_choose_option(REFUSE_OPTION)
			KEY_3:
				_choose_option(INSULT_OPTION)
			KEY_K:
				_kill_leader()
			KEY_F:
				_move_player_far()
			KEY_X:
				_delete_speaker()


func reset_environment() -> void:
	ExtortionQueue.reset()
	BanditGroupMemory.reset()
	ModalWorldUIController.close_modal()
	get_tree().paused = false

	for child in _world_layer.get_children():
		child.queue_free()
	await get_tree().process_frame

	_behaviors.clear()
	_status_history.clear()

	_player = _spawn_player()
	_leader = _spawn_enemy(LEADER_ID, _leader_anchor.global_position, "leader")
	_guard_a = _spawn_enemy(GUARD_A_ID, _guard_a_anchor.global_position, "guard")
	_guard_b = _spawn_enemy(GUARD_B_ID, _guard_b_anchor.global_position, "guard")

	_npc_simulator.active_enemies.clear()
	_npc_simulator.active_enemy_chunk.clear()
	_register_enemy(_leader)
	_register_enemy(_guard_a)
	_register_enemy(_guard_b)

	BanditGroupMemory.register_member(GROUP_ID, LEADER_ID, "leader", _leader.global_position, FACTION_ID)
	BanditGroupMemory.register_member(GROUP_ID, GUARD_A_ID, "guard", _guard_a.global_position, FACTION_ID)
	BanditGroupMemory.register_member(GROUP_ID, GUARD_B_ID, "guard", _guard_b.global_position, FACTION_ID)
	BanditGroupMemory.update_intent(GROUP_ID, "idle")

	if _director != null and is_instance_valid(_director):
		_director.queue_free()
	_director = DIRECTOR_SCRIPT.new()
	add_child(_director)
	_director.setup({
		"npc_simulator": _npc_simulator,
		"player": _player,
		"speech_bubble_manager": _bubble_manager,
		"get_behavior_for_enemy": Callable(self, "_get_behavior_for_enemy"),
	})

	_append_status("Entorno reiniciado: player + leader + 2 guards preparados.")


func _spawn_player() -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	_world_layer.add_child(player)
	player.global_position = _player_anchor.global_position
	player.name = "Player"
	var inventory := player.get_node_or_null("InventoryComponent") as InventoryComponent
	if inventory != null:
		inventory.gold = LEADER_GOLD
	return player


func _spawn_enemy(enemy_id: String, pos: Vector2, role: String) -> EnemyAI:
	var enemy := ENEMY_SCENE.instantiate() as EnemyAI
	_world_layer.add_child(enemy)
	enemy.global_position = pos
	enemy.entity_uid = enemy_id
	enemy.group_id = GROUP_ID
	enemy.faction_id = FACTION_ID
	enemy.name = enemy_id
	enemy.external_ai_override = true
	enemy.detection_range = 0.0
	_behaviors[enemy_id] = TestBehavior.new(enemy)
	if role == "leader":
		var inv := enemy.get_node_or_null("InventoryComponent") as InventoryComponent
		if inv != null:
			inv.gold = 0
	return enemy


func _register_enemy(enemy: EnemyAI) -> void:
	_npc_simulator.active_enemies[enemy.entity_uid] = enemy
	_npc_simulator.active_enemy_chunk[enemy.entity_uid] = "test_chunk"


func _trigger_extortion() -> void:
	if _player == null or _leader == null:
		return
	if not is_instance_valid(_leader):
		_append_status("No se puede encolar: el líder ya no existe.")
		return
	_move_player_near()
	ExtortionQueue.enqueue_intent(
		"player",
		FACTION_ID,
		GROUP_ID,
		LEADER_ID,
		"debug_button",
		_player.global_position,
		1.0
	)
	BanditGroupMemory.update_intent(GROUP_ID, "extorting")
	_append_status("Extorsión encolada. El director debería acercar al grupo, tauntear y abrir la elección.")


func _choose_option(option: int) -> void:
	var modal := ModalWorldUIController.get_active_modal()
	if modal == null or not modal is ExtortionChoiceBubble:
		_append_status("No hay modal de extorsión activo para elegir opción %d." % option)
		return
	(modal as ExtortionChoiceBubble).choice_made.emit(option)
	match option:
		PAY_OPTION:
			_append_status("Opción debug: pagar.")
		REFUSE_OPTION:
			_append_status("Opción debug: negarse.")
		INSULT_OPTION:
			_append_status("Opción debug: insultar.")


func _kill_leader() -> void:
	if _leader == null or not is_instance_valid(_leader):
		_append_status("El líder ya estaba eliminado.")
		return
	BanditGroupMemory.remove_member(GROUP_ID, LEADER_ID)
	_npc_simulator._clear_enemy_tracking(LEADER_ID)
	_leader.queue_free()
	_append_status("Líder eliminado. La extorsión activa debería abortarse por leader_dead.")


func _move_player_far() -> void:
	if _player == null:
		return
	_player.global_position = PLAYER_FAR_POS
	_append_status("Player alejado fuera del rango de aborto para probar cancelación por distancia.")


func _move_player_near() -> void:
	if _player == null:
		return
	_player.global_position = _player_anchor.global_position
	_append_status("Player reposicionado cerca del grupo para reintentar el flujo.")


func _delete_speaker() -> void:
	if _director == null:
		return
	var gid := _director._extortion_choice_gid
	var active := _director._active_extortions as Dictionary
	var speaker_id := ""
	if gid != "" and active.has(gid):
		var job = active[gid]
		if job != null:
			speaker_id = String(job.taunt_speaker_id)
	if speaker_id == "":
		speaker_id = LEADER_ID
	var speaker := _npc_simulator._get_active_enemy_node(speaker_id)
	if speaker == null or not is_instance_valid(speaker):
		_append_status("No hay speaker vivo para borrar.")
		return
	BanditGroupMemory.remove_member(GROUP_ID, speaker_id)
	_npc_simulator._clear_enemy_tracking(speaker_id)
	speaker.queue_free()
	_append_status("Speaker borrado (%s). La extorsión debería abortarse por speaker_missing/group_composition_broken." % speaker_id)


func _get_behavior_for_enemy(enemy_id: String) -> Variant:
	return _behaviors.get(enemy_id, null)


func _append_status(text: String) -> void:
	_status_history.append(text)
	while _status_history.size() > 8:
		_status_history.remove_at(0)
	_update_status_label()


func _update_status_label() -> void:
	if _status_label == null:
		return
	var lines := PackedStringArray()
	lines.append("Grupo=%s | Queue=%d | Modal=%s | Paused=%s" % [
		GROUP_ID,
		ExtortionQueue.get_pending_for_group(GROUP_ID).size(),
		str(ModalWorldUIController.has_active_modal()),
		str(get_tree().paused),
	])
	var active := _director._active_extortions as Dictionary if _director != null else {}
	if active.has(GROUP_ID):
		var job = active[GROUP_ID]
		lines.append("Job activo: %s" % [str(job.phase if job != null else "?")])
	else:
		lines.append("Job activo: none")
	lines.append_array(_status_history)
	_status_label.text = "\n".join(lines)
