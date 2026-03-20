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

# Extra pixels above the actor's pivot before placing the bottom of the bubble.
const HEAD_OFFSET: float = 10.0

# active entries:  actor_instance_id (int) -> { bubble, actor (WeakRef), timer }
var _active: Dictionary = {}


func _ready() -> void:
	layer = 5   # above world, below main HUD


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
	var canvas_xform: Transform2D = get_viewport().get_canvas_transform()

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

		# World → viewport (CanvasLayer-space) position.
		var screen_pos: Vector2 = canvas_xform * (actor as Node2D).global_position
		# Place bubble centered horizontally, bottom edge above actor's pivot.
		bubble.position = screen_pos - Vector2(bubble.size.x * 0.5, bubble.size.y + HEAD_OFFSET)

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
