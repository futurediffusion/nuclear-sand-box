extends Node2D

## DuelTest — arena de duelo con piso de hierba y cliffs.
##
## La arena se genera en _ready():
##   • GroundMap:  hierba interior (12×12 tiles)
##   • CliffsMap:  borde de cliffs (2 tiles de ancho)
##   • ArenaWalls: 4 StaticBody2D que bloquean físicamente las salidas
##
## [SPACE] o botón SPAWN: spawna dos enemies en el centro de la arena.
## EnemyA apunta a EnemyB (set_current_target, no force_target).
## Cuando el slash conecta → trigger natural del duelo → ambos pelean.

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")

# Tamaño de la arena en tiles — arena interior 12×12, cliffs 2 tiles de borde
const ARENA_HALF: int   = 6   # interior va de -ARENA_HALF a ARENA_HALF-1 (12 tiles)
const CLIFF_RING: int   = 2   # ancho del borde de cliffs
const TILE_PX:   int    = 32  # tamaño de cada tile en pixels

# Tile IDs del GroundMap (TileMap_Ground.tres)
# terrain_set=0, terrain_id=1 → hierba (auto-connect)
const GROUND_TERRAIN_SET: int = 0
const GROUND_TERRAIN_GRASS: int = 1

# Tile IDs del CliffsMap (TileMap_Cliffs .tres)
# terrain_set=0, terrain_id=2 → cliffs
const CLIFF_TERRAIN_SET: int = 0
const CLIFF_TERRAIN_ID:  int = 2
# Fill sólido detrás de los cliffs (fuera del borde)
const CLIFF_FILL_SRC:    int      = 3
const CLIFF_FILL_ATLAS:  Vector2i = Vector2i(1, 5)

# Separación de spawn entre los dos enemies (pixels)
const SPAWN_SEP: float = 22.0

@onready var _ground_map:   TileMap        = $GroundMap
@onready var _cliffs_map:   TileMap        = $CliffsMap
@onready var _arena_walls:  StaticBody2D   = $ArenaWalls
@onready var _world_layer:  Node2D         = $WorldLayer
@onready var _status_label: Label          = $UI/DebugPanel/Margin/VBox/StatusLabel
@onready var _ea_label:     Label          = $UI/DebugPanel/Margin/VBox/EnemyALabel
@onready var _eb_label:     Label          = $UI/DebugPanel/Margin/VBox/EnemyBLabel
@onready var _log_label:    Label          = $UI/DebugPanel/Margin/VBox/LogLabel

var _enemy_a: EnemyAI = null
var _enemy_b: EnemyAI = null
var _log_lines: PackedStringArray = []
var _duel_triggered: bool = false
var _duel_start_time: float = 0.0
var _spawned: bool = false


func _ready() -> void:
	$UI/DebugPanel/Margin/VBox/Buttons/SpawnButton.pressed.connect(_on_spawn_pressed)
	$UI/DebugPanel/Margin/VBox/Buttons/ResetButton.pressed.connect(_on_reset_pressed)
	_build_arena()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey \
			and (event as InputEventKey).keycode == KEY_SPACE \
			and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		if _spawned:
			_on_reset_pressed()
		else:
			_on_spawn_pressed()


func _process(_delta: float) -> void:
	if not is_instance_valid(_enemy_a) or not is_instance_valid(_enemy_b):
		return
	_update_labels()


# ---------------------------------------------------------------------------
# Arena
# ---------------------------------------------------------------------------

func _build_arena() -> void:
	var inner_cells: Array[Vector2i] = []
	var cliff_cells: Array[Vector2i] = []
	var outer_border := ARENA_HALF + CLIFF_RING

	# Piso de hierba interior
	for y in range(-ARENA_HALF, ARENA_HALF):
		for x in range(-ARENA_HALF, ARENA_HALF):
			inner_cells.append(Vector2i(x, y))

	# Borde de cliffs
	for y in range(-outer_border, outer_border):
		for x in range(-outer_border, outer_border):
			if x < -ARENA_HALF or x >= ARENA_HALF or y < -ARENA_HALF or y >= ARENA_HALF:
				cliff_cells.append(Vector2i(x, y))

	# Pintar hierba con terrain auto-connect
	_ground_map.set_cells_terrain_connect(0, inner_cells, GROUND_TERRAIN_SET, GROUND_TERRAIN_GRASS, false)

	# Pintar cliffs con terrain auto-connect
	_cliffs_map.set_cells_terrain_connect(0, cliff_cells, CLIFF_TERRAIN_SET, CLIFF_TERRAIN_ID, false)

	# Fill sólido extra (1 tile más allá del borde) para tapar huecos visuales
	var fill_min := outer_border
	for x in range(-fill_min - 1, fill_min + 1):
		_cliffs_map.set_cell(0, Vector2i(x, -fill_min - 1), CLIFF_FILL_SRC, CLIFF_FILL_ATLAS)
		_cliffs_map.set_cell(0, Vector2i(x,  fill_min),     CLIFF_FILL_SRC, CLIFF_FILL_ATLAS)
	for y in range(-fill_min, fill_min):
		_cliffs_map.set_cell(0, Vector2i(-fill_min - 1, y), CLIFF_FILL_SRC, CLIFF_FILL_ATLAS)
		_cliffs_map.set_cell(0, Vector2i( fill_min,     y), CLIFF_FILL_SRC, CLIFF_FILL_ATLAS)

	# Muros de colisión invisibles en los 4 lados del interior
	_build_wall_shapes()


func _build_wall_shapes() -> void:
	var half_px: float = ARENA_HALF * TILE_PX   # píxeles desde el origen al borde
	var thickness: float = 16.0
	var length: float    = half_px * 2.0 + thickness * 2.0

	var shapes: Array[Dictionary] = [
		{ "node": "WallTop",    "pos": Vector2(0.0, -half_px - thickness * 0.5), "size": Vector2(length, thickness) },
		{ "node": "WallBottom", "pos": Vector2(0.0,  half_px + thickness * 0.5), "size": Vector2(length, thickness) },
		{ "node": "WallLeft",   "pos": Vector2(-half_px - thickness * 0.5, 0.0), "size": Vector2(thickness, length) },
		{ "node": "WallRight",  "pos": Vector2( half_px + thickness * 0.5, 0.0), "size": Vector2(thickness, length) },
	]
	for s in shapes:
		var col: CollisionShape2D = $ArenaWalls.get_node(s["node"]) as CollisionShape2D
		var rect := RectangleShape2D.new()
		rect.size = s["size"]
		col.shape = col.shape if col.shape != null else RectangleShape2D.new()
		col.shape = rect
		col.position = s["pos"]


# ---------------------------------------------------------------------------
# Spawn / Reset
# ---------------------------------------------------------------------------

func _on_spawn_pressed() -> void:
	if _spawned:
		_on_reset_pressed()
		return
	_spawned = true

	_enemy_a = ENEMY_SCENE.instantiate() as EnemyAI
	_world_layer.add_child(_enemy_a)
	_enemy_a.global_position = Vector2(-SPAWN_SEP * 0.5, 0.0)

	_enemy_b = ENEMY_SCENE.instantiate() as EnemyAI
	_world_layer.add_child(_enemy_b)
	_enemy_b.global_position = Vector2( SPAWN_SEP * 0.5, 0.0)

	await get_tree().process_frame
	await get_tree().process_frame

	_kick_off_attack()
	_log("Spawneados. EnemyA apuntando a EnemyB.")
	_status_label.text = "EnemyA atacando → esperando slash…"


func _kick_off_attack() -> void:
	var ai_a: AIComponent = _get_ai(_enemy_a)
	if ai_a == null:
		_log("ERROR: EnemyA sin AIComponent")
		return
	# Solo apuntar — NO force_target para que el duel arranque por el slash real.
	ai_a.set_current_target(_enemy_b)
	ai_a.wake_now()
	ai_a.current_state = AIComponent.AIState.CHASE


func _on_reset_pressed() -> void:
	_spawned = false
	if is_instance_valid(_enemy_a): _enemy_a.queue_free()
	if is_instance_valid(_enemy_b): _enemy_b.queue_free()
	_enemy_a = null
	_enemy_b = null
	_duel_triggered = false
	_duel_start_time = 0.0
	_log_lines.clear()
	_status_label.text = "Presiona SPACE o SPAWN para iniciar."
	_ea_label.text = "EnemyA: —"
	_eb_label.text = "EnemyB: —"
	_log_label.text = ""


# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

func _update_labels() -> void:
	var ai_a: AIComponent = _get_ai(_enemy_a)
	var ai_b: AIComponent = _get_ai(_enemy_b)
	if ai_a == null or ai_b == null:
		return

	var a_duel := _is_duel_active(ai_a)
	var b_duel := _is_duel_active(ai_b)

	if (a_duel or b_duel) and not _duel_triggered:
		_duel_triggered = true
		_duel_start_time = Time.get_ticks_msec() / 1000.0
		_log("✓ DUELO ACTIVADO")
		_status_label.text = "DUELO ACTIVO — pelean a muerte (max 25s)"

	_ea_label.text = "EnemyA | %s | → %s | %s" % [
		_state_name(ai_a), _target_name(ai_a.get_current_target()),
		"DUEL✓" if a_duel else "libre"
	]
	_eb_label.text = "EnemyB | %s | → %s | %s" % [
		_state_name(ai_b), _target_name(ai_b.get_current_target()),
		"DUEL✓" if b_duel else "libre"
	]

	if _duel_triggered and not _log_lines.has("fin"):
		var a_dead := ai_a.current_state == AIComponent.AIState.DEAD
		var b_dead := ai_b.current_state == AIComponent.AIState.DEAD
		if a_dead or b_dead:
			var winner := "EnemyB" if a_dead else "EnemyA"
			var elapsed := snappedf(Time.get_ticks_msec() / 1000.0 - _duel_start_time, 0.1)
			_status_label.text = "FIN — %s ganó (%.1fs)  SPACE=repetir" % [winner, elapsed]
			_log("Ganador: %s en %.1fs" % [winner, elapsed])
			_log_lines.append("fin")
			_spawned = false


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _is_duel_active(ai: AIComponent) -> bool:
	if ai == null or RunClock == null:
		return false
	var duel_id: int   = int(ai.get("_duel_target_id")    if ai.get("_duel_target_id")    != null else -1)
	var until: float   = float(ai.get("_duel_locked_until") if ai.get("_duel_locked_until") != null else 0.0)
	return duel_id != -1 and RunClock.now() < until


func _state_name(ai: AIComponent) -> String:
	return AIComponent.AIState.keys()[ai.current_state]


func _target_name(t: Node) -> String:
	if t == null:      return "ninguno"
	if t == _enemy_a:  return "EnemyA"
	if t == _enemy_b:  return "EnemyB"
	return t.name


func _get_ai(e: EnemyAI) -> AIComponent:
	if e == null or not is_instance_valid(e):
		return null
	return e.get_node_or_null("AIComponent") as AIComponent


func _log(msg: String) -> void:
	_log_lines.append(msg)
	if _log_lines.size() > 8:
		_log_lines.remove_at(0)
	_log_label.text = "\n".join(_log_lines)
