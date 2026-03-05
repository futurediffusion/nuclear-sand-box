extends Node

@export var full_tick_budget_per_frame: int = 4
@export var max_delay_frames: int = 12

var _queue: Array[int] = []
var _scheduled_frames: Dictionary = {}

func _process(_delta: float) -> void:
	if _queue.is_empty():
		return
	var budget := maxi(full_tick_budget_per_frame, 1)
	while budget > 0 and not _queue.is_empty():
		var enemy_id: int = _queue.pop_front()
		_scheduled_frames[enemy_id] = Engine.get_process_frames()
		budget -= 1

func request_ticket(enemy_id: int) -> void:
	if enemy_id <= 0:
		return
	if _scheduled_frames.has(enemy_id) or _queue.has(enemy_id):
		return
	_queue.append(enemy_id)
	var queue_count := _queue.size()
	if max_delay_frames > 0 and queue_count > max_delay_frames:
		var promote_count := queue_count - max_delay_frames
		for i in range(promote_count):
			var promoted_id: int = _queue[i]
			_scheduled_frames[promoted_id] = Engine.get_process_frames()
		_queue = _queue.slice(promote_count)

func is_ticket_ready(enemy_id: int) -> bool:
	if enemy_id <= 0:
		return true
	if not _scheduled_frames.has(enemy_id):
		return false
	return int(_scheduled_frames[enemy_id]) <= Engine.get_process_frames()

func consume_ticket(enemy_id: int) -> void:
	if enemy_id <= 0:
		return
	_scheduled_frames.erase(enemy_id)

func cancel_ticket(enemy_id: int) -> void:
	if enemy_id <= 0:
		return
	_scheduled_frames.erase(enemy_id)
	_queue.erase(enemy_id)
