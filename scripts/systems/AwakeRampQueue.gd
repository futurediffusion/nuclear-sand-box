extends Node

@export var full_tick_budget_per_frame: int = 4
@export var max_delay_frames: int = 12

var _queue: Array[int] = []
var _scheduled_frames: Dictionary = {}
var _requested_frames: Dictionary = {}

func _process(_delta: float) -> void:
	var current_frame := Engine.get_process_frames()
	if not _queue.is_empty() and max_delay_frames > 0:
		var overdue_ids: Array[int] = []
		for enemy_id in _queue:
			if not _requested_frames.has(enemy_id):
				continue
			var waited_frames := current_frame - int(_requested_frames[enemy_id])
			if waited_frames >= max_delay_frames:
				overdue_ids.append(enemy_id)
		for enemy_id in overdue_ids:
			_queue.erase(enemy_id)
			_scheduled_frames[enemy_id] = current_frame

	if _queue.is_empty():
		return
	var budget := maxi(full_tick_budget_per_frame, 1)
	while budget > 0 and not _queue.is_empty():
		var enemy_id: int = _queue.pop_front()
		_scheduled_frames[enemy_id] = current_frame
		budget -= 1

func request_ticket(enemy_id: int) -> void:
	if enemy_id <= 0:
		return
	if _scheduled_frames.has(enemy_id) or _queue.has(enemy_id):
		return
	_requested_frames[enemy_id] = Engine.get_process_frames()
	_queue.append(enemy_id)

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
	_requested_frames.erase(enemy_id)

func cancel_ticket(enemy_id: int) -> void:
	if enemy_id <= 0:
		return
	_scheduled_frames.erase(enemy_id)
	_requested_frames.erase(enemy_id)
	_queue.erase(enemy_id)


func get_queue_size() -> int:
	return _queue.size()

func get_scheduled_size() -> int:
	return _scheduled_frames.size()

func get_pending_count() -> int:
	return _queue.size() + _scheduled_frames.size()
