extends CanvasLayer
class_name WorldSpeechBubbleManager

# ── WorldSpeechBubbleManager ──────────────────────────────────────────────────
# CanvasLayer that owns world-space speech bubbles.
# Bubbles follow their actor's screen position every frame and die after duration.
#
# API:  show_actor_bubble(actor: Node2D, text: String, duration := 2.5)
#
# One bubble per actor at a time — calling show_actor_bubble() again on the
# same actor replaces the previous bubble.

const BUBBLE_SCENE: PackedScene = preload("res://scenes/ui/speechbubble.tscn")

# Píxeles sobre el pivot del actor (negativo = baja, positivo = sube).
const HEAD_OFFSET: float = -9.0
# Píxeles horizontales desde el centro del actor (negativo = izquierda, positivo = derecha).
const SIDE_OFFSET: float = 61.5

# active entries:  actor_instance_id (int) -> { bubble, actor (WeakRef), timer }
var _active: Dictionary = {}


func _ready() -> void:
	layer = 5   # above world, below main HUD
	process_mode = Node.PROCESS_MODE_ALWAYS


## Show a speech bubble above actor for duration seconds.
## Replaces any existing bubble on the same actor.
func show_actor_bubble(actor: Node2D, text: String, duration: float = 2.5) -> void:
	var id: int = actor.get_instance_id()
	_kill_entry(id)

	var bubble: SpeechBubble = BUBBLE_SCENE.instantiate() as SpeechBubble
	add_child(bubble)
	bubble.set_text(text)

	_active[id] = {
		"bubble": bubble,
		"actor":  weakref(actor),
		"timer":  duration,
	}


func _process(delta: float) -> void:
	if _active.is_empty():
		return

	var to_remove: Array = []

	for id in _active:
		var entry: Dictionary = _active[id]
		entry["timer"] -= delta

		var actor = (entry["actor"] as WeakRef).get_ref()
		var bubble: SpeechBubble = entry.get("bubble") as SpeechBubble

		if entry["timer"] <= 0.0 \
				or actor == null or not is_instance_valid(actor) \
				or bubble == null or not is_instance_valid(bubble):
			to_remove.append(id)
			continue

		# get_global_transform_with_canvas() da la posición del actor en coordenadas
		# de viewport (píxeles lógicos), equivalente al espacio del CanvasLayer.
		# Es la forma correcta en Godot 4 — funciona con cámara, escala y stretch.
		var screen_pos: Vector2 = (actor as Node2D).get_global_transform_with_canvas().origin
		# Centrado horizontal, borde inferior a HEAD_OFFSET px sobre el pivot del actor.
		bubble.position = screen_pos - Vector2(bubble.size.x * 0.5 - SIDE_OFFSET, bubble.size.y + HEAD_OFFSET)

	for id in to_remove:
		_kill_entry(id)


func _kill_entry(id: int) -> void:
	if not _active.has(id):
		return
	var entry: Dictionary = _active[id]
	var bubble = entry.get("bubble")
	if bubble != null and is_instance_valid(bubble):
		(bubble as Node).queue_free()
	_active.erase(id)
