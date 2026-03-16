extends Node
class_name FootstepAudioComponent

const SURFACE_ID_GRASS: StringName = &"grass"
const SURFACE_ID_DIRT: StringName = &"dirt"
const SURFACE_ID_WOOD: StringName = &"wood"
const LOOP_PLAYER_NODE_NAME: StringName = &"FootstepLoopPlayer"
const LOOP_PLAYER_NODE_PATH: NodePath = ^"FootstepLoopPlayer"

const DEFAULT_WALKING_GRASS_SFX: AudioStream = preload("res://art/Sounds/walking/walkingongrass.ogg")
const DEFAULT_WALKING_DIRT_SFX: AudioStream = preload("res://art/Sounds/walking/walkingondirt.ogg")
const DEFAULT_WALKING_WOOD_SFX: AudioStream = preload("res://art/Sounds/walking/walkingonfloorwood.ogg")

const DEFAULT_STREAM_BY_SURFACE := {
	SURFACE_ID_GRASS: DEFAULT_WALKING_GRASS_SFX,
	SURFACE_ID_DIRT: DEFAULT_WALKING_DIRT_SFX,
	SURFACE_ID_WOOD: DEFAULT_WALKING_WOOD_SFX,
}

const DEFAULT_VOLUME_DB_BY_SURFACE := {
	SURFACE_ID_GRASS: 0.0,
	SURFACE_ID_DIRT: 0.0,
	SURFACE_ID_WOOD: 0.0,
}

@export var enabled: bool = true
@export var movement_speed_threshold: float = 12.0
@export var default_surface_id: StringName = SURFACE_ID_GRASS
@export var bus: StringName = &"SFX"
@export var randomize_loop_start: bool = true
@export_range(0.0, 0.98, 0.01) var random_start_max_ratio_grass: float = 0.9
@export_range(0.0, 0.98, 0.01) var random_start_max_ratio_dirt: float = 0.45
@export_range(0.0, 0.98, 0.01) var random_start_max_ratio_wood: float = 0.9

var player: Player = null
var surface_resolver: Callable = Callable()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _loop_player: AudioStreamPlayer2D = null
var _active_surface_id: StringName = &""
var _loop_stream_cache: Dictionary = {}
var _sound_panel_ref: WeakRef = null


func setup(p_player: Player, p_surface_resolver: Callable = Callable()) -> void:
	player = p_player
	surface_resolver = p_surface_resolver
	_rng.randomize()
	_loop_stream_cache.clear()
	_ensure_loop_player()


func physics_tick(_delta: float) -> void:
	if not enabled or player == null or not is_instance_valid(player):
		stop_loop()
		return
	if player.dying:
		stop_loop()
		return
	if player.velocity.length_squared() < movement_speed_threshold * movement_speed_threshold:
		stop_loop()
		return

	var surface_id: StringName = _resolve_surface_id(player.global_position)
	_play_surface(surface_id)


func stop_loop() -> void:
	if _loop_player != null and is_instance_valid(_loop_player) and _loop_player.playing:
		_loop_player.stop()
	_active_surface_id = &""


func _exit_tree() -> void:
	stop_loop()


func _play_surface(surface_id: StringName) -> void:
	_ensure_loop_player()
	if _loop_player == null:
		return

	var stream: AudioStream = _resolve_surface_stream(surface_id)
	if stream == null:
		stop_loop()
		return

	var volume_db: float = _resolve_surface_volume_db(surface_id)
	var loop_stream: AudioStream = _get_or_create_loop_stream(surface_id, stream)
	if loop_stream == null:
		stop_loop()
		return

	_loop_player.bus = bus
	_loop_player.volume_db = volume_db

	if _active_surface_id != surface_id or _loop_player.stream != loop_stream:
		_loop_player.stream = loop_stream
		_play_loop_from_random_offset(loop_stream, surface_id)
		_active_surface_id = surface_id
		return

	if not _loop_player.playing:
		_play_loop_from_random_offset(loop_stream, surface_id)


func _resolve_surface_id(world_pos: Vector2) -> StringName:
	var resolved: Variant = null
	if surface_resolver.is_valid():
		resolved = surface_resolver.call(world_pos)
	else:
		var world := _resolve_world_node()
		if world != null and world.has_method("get_walk_surface_at_world_pos"):
			resolved = world.call("get_walk_surface_at_world_pos", world_pos)

	if typeof(resolved) == TYPE_STRING_NAME:
		var id: StringName = resolved
		if id != StringName():
			return id
	if typeof(resolved) == TYPE_STRING:
		var id_str: String = String(resolved).strip_edges()
		if not id_str.is_empty():
			return StringName(id_str)
	return default_surface_id


func _resolve_surface_stream(surface_id: StringName) -> AudioStream:
	var panel := _resolve_sound_panel()
	if panel is SoundPanel:
		var panel_stream: AudioStream = (panel as SoundPanel).get_walk_surface_sfx(surface_id)
		if panel_stream != null:
			return panel_stream
	var raw_stream: Variant = DEFAULT_STREAM_BY_SURFACE.get(surface_id, null)
	if raw_stream is AudioStream and raw_stream != null:
		return raw_stream as AudioStream
	var fallback_stream: Variant = DEFAULT_STREAM_BY_SURFACE.get(default_surface_id, DEFAULT_WALKING_GRASS_SFX)
	if fallback_stream is AudioStream and fallback_stream != null:
		return fallback_stream as AudioStream
	return DEFAULT_WALKING_GRASS_SFX


func _resolve_surface_volume_db(surface_id: StringName) -> float:
	var panel := _resolve_sound_panel()
	if panel is SoundPanel:
		return (panel as SoundPanel).get_walk_surface_volume_db(surface_id)
	if DEFAULT_VOLUME_DB_BY_SURFACE.has(surface_id):
		return float(DEFAULT_VOLUME_DB_BY_SURFACE[surface_id])
	return float(DEFAULT_VOLUME_DB_BY_SURFACE.get(default_surface_id, 0.0))


func _resolve_sound_panel() -> Node:
	if _sound_panel_ref != null:
		var cached: Node = _sound_panel_ref.get_ref() as Node
		if cached != null and is_instance_valid(cached):
			return cached
		_sound_panel_ref = null

	if AudioSystem == null or not AudioSystem.has_method("get_sound_panel"):
		return null
	var panel: Node = AudioSystem.get_sound_panel()
	if panel != null:
		_sound_panel_ref = weakref(panel)
	return panel


func _resolve_world_node() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var worlds: Array = tree.get_nodes_in_group("world")
	if worlds.is_empty():
		return null
	return worlds[0] as Node


func _ensure_loop_player() -> void:
	if _loop_player != null and is_instance_valid(_loop_player):
		return
	if player == null or not is_instance_valid(player):
		return

	var existing: AudioStreamPlayer2D = player.get_node_or_null(LOOP_PLAYER_NODE_PATH) as AudioStreamPlayer2D
	if existing != null:
		_loop_player = existing
	else:
		_loop_player = AudioStreamPlayer2D.new()
		_loop_player.name = String(LOOP_PLAYER_NODE_NAME)
		player.add_child(_loop_player)
	_loop_player.bus = bus


func _get_or_create_loop_stream(surface_id: StringName, source: AudioStream) -> AudioStream:
	if source == null:
		return null

	var cache_raw: Variant = _loop_stream_cache.get(surface_id, null)
	if cache_raw is Dictionary:
		var cache: Dictionary = cache_raw as Dictionary
		if cache.get("source", null) == source and cache.get("looped", null) is AudioStream:
			return cache.get("looped", null) as AudioStream

	var looped: AudioStream = _make_loop_stream(source)
	_loop_stream_cache[surface_id] = {
		"source": source,
		"looped": looped,
	}
	return looped


func _make_loop_stream(source: AudioStream) -> AudioStream:
	if source is AudioStreamOggVorbis:
		var ogg: AudioStreamOggVorbis = (source as AudioStreamOggVorbis).duplicate(true) as AudioStreamOggVorbis
		if ogg != null:
			ogg.loop = true
			return ogg
	if source is AudioStreamWAV:
		var wav: AudioStreamWAV = (source as AudioStreamWAV).duplicate(true) as AudioStreamWAV
		if wav != null:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			return wav
	return source


func _play_loop_from_random_offset(stream: AudioStream, surface_id: StringName) -> void:
	if _loop_player == null or not is_instance_valid(_loop_player):
		return
	var start_pos: float = 0.0
	if randomize_loop_start:
		var clip_length: float = _resolve_stream_length_seconds(stream)
		if clip_length > 0.05:
			var max_ratio: float = clampf(_resolve_surface_random_start_max_ratio(surface_id), 0.0, 0.98)
			var max_start: float = minf(clip_length - 0.02, clip_length * max_ratio)
			if max_start > 0.0:
				start_pos = _rng.randf_range(0.0, max_start)
	_loop_player.play(start_pos)


func _resolve_stream_length_seconds(stream: AudioStream) -> float:
	if stream == null:
		return 0.0
	return maxf(0.0, stream.get_length())


func _resolve_surface_random_start_max_ratio(surface_id: StringName) -> float:
	match surface_id:
		SURFACE_ID_DIRT:
			return random_start_max_ratio_dirt
		SURFACE_ID_WOOD:
			return random_start_max_ratio_wood
		_:
			return random_start_max_ratio_grass
