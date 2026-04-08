extends RefCounted
class_name SandboxDomainEventDispatcher

## Lightweight domain event bus for world-module boundaries.
## - Explicit registration (`subscribe`)
## - Explicit dispatch (`publish`)
## - Small in-memory trace for audit/debug (`get_recent_events`)

const DEFAULT_TRACE_LIMIT: int = 128

var _trace_limit: int = DEFAULT_TRACE_LIMIT
var _seq: int = 0
var _listeners_by_event: Dictionary = {} # event_type(String) -> Array[Dictionary]
var _recent_events: Array[Dictionary] = []

func setup(config: Dictionary = {}) -> void:
	_trace_limit = maxi(16, int(config.get("trace_limit", DEFAULT_TRACE_LIMIT)))

func subscribe(event_type: String, consumer_id: String, callback: Callable) -> void:
	var key: String = event_type.strip_edges()
	if key.is_empty() or consumer_id.strip_edges().is_empty() or not callback.is_valid():
		return
	var listeners: Array = _listeners_by_event.get(key, []) as Array
	for listener_raw in listeners:
		if not (listener_raw is Dictionary):
			continue
		var listener: Dictionary = listener_raw as Dictionary
		if String(listener.get("consumer_id", "")) == consumer_id:
			return
	listeners.append({
		"consumer_id": consumer_id,
		"callback": callback,
	})
	_listeners_by_event[key] = listeners

func publish(event_type: String, payload: Dictionary = {}) -> void:
	var key: String = event_type.strip_edges()
	if key.is_empty():
		return
	_seq += 1
	var event_record: Dictionary = {
		"seq": _seq,
		"type": key,
		"at": RunClock.now(),
		"payload": payload.duplicate(true),
	}
	_recent_events.append(event_record)
	while _recent_events.size() > _trace_limit:
		_recent_events.remove_at(0)
	var listeners: Array = _listeners_by_event.get(key, []) as Array
	for listener_raw in listeners:
		if not (listener_raw is Dictionary):
			continue
		var listener: Dictionary = listener_raw as Dictionary
		var cb: Callable = listener.get("callback", Callable()) as Callable
		if cb.is_valid():
			cb.call(event_record.duplicate(true))

func get_recent_events(limit: int = 64) -> Array[Dictionary]:
	var safe_limit: int = maxi(0, limit)
	if safe_limit <= 0 or _recent_events.is_empty():
		return []
	if safe_limit >= _recent_events.size():
		return _recent_events.duplicate(true)
	return _recent_events.slice(_recent_events.size() - safe_limit, _recent_events.size()).duplicate(true)

