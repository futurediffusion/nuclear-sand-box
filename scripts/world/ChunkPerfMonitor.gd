extends RefCounted
class_name ChunkPerfMonitor

const STAGE_GENERATE: String = "generate"
const STAGE_GROUND_CONNECT: String = "ground terrain connect"
const STAGE_WALL_CONNECT: String = "wall terrain connect"
const STAGE_COLLIDER_BUILD: String = "collider build"
const STAGE_ENTITIES: String = "enqueue/spawn entities"

var enabled: bool = true
var window_size: int = 64
var auto_print: bool = false
var print_interval: float = 5.0
var auto_calibrate: bool = false

# Umbrales de alerta para ring 0
var alert_generate_ms: float = 4.0
var alert_ground_connect_ms: float = 4.0
var alert_wall_connect_ms: float = 4.0
var alert_collider_ms: float = 4.0
var alert_entities_ms: float = 4.0

# Acumuladores de fallback de terrain
var fallback_cells_accum: int = 0
var fallback_events_accum: int = 0
var fallback_missing_accum: int = 0
var fallback_invalid_source_accum: int = 0
var fallback_last_log_msec: int = 0

var _data: Dictionary = { 0: {}, 1: {}, 2: {} }
var _timer: float = 0.0

func record(stage: String, chunk_pos: Vector2i, center_chunk: Vector2i, elapsed_ms: float) -> void:
	if not enabled:
		return
	var ring: int = clampi(max(abs(chunk_pos.x - center_chunk.x), abs(chunk_pos.y - center_chunk.y)), 0, 2)
	var ring_data: Dictionary = _data.get(ring, {})
	if not ring_data.has(stage):
		ring_data[stage] = []
	var samples: Array = ring_data[stage]
	samples.append(elapsed_ms)
	var max_s: int = max(8, window_size)
	while samples.size() > max_s:
		samples.remove_at(0)
	ring_data[stage] = samples
	_data[ring] = ring_data
	_check_alert(stage, ring, elapsed_ms, chunk_pos)

func record_fallback(chunk_pos: Vector2i, total_cells: int, missing_cells: int, invalid_source_cells: int, mode: String) -> void:
	if total_cells <= 0:
		return
	fallback_events_accum += 1
	fallback_cells_accum += total_cells
	fallback_missing_accum += missing_cells
	fallback_invalid_source_accum += invalid_source_cells
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - fallback_last_log_msec < 2000:
		return
	fallback_last_log_msec = now_msec
	Debug.log("ground", "fallback mode=%s events=%d total_cells=%d missing=%d invalid_src=%d" % [
		mode, fallback_events_accum, fallback_cells_accum,
		fallback_missing_accum, fallback_invalid_source_accum,
	])

# Llama cada frame desde World._process. Retorna true si acaba de imprimir (para trigger calibración).
func tick(delta: float) -> bool:
	if not auto_print:
		return false
	_timer += delta
	if _timer < maxf(0.5, print_interval):
		return false
	_timer = 0.0
	print_percentiles()
	return true

func print_percentiles() -> void:
	if not enabled:
		Debug.log("chunk_perf", "disabled")
		return
	for ring in [0, 1, 2]:
		var ring_data: Dictionary = _data.get(ring, {})
		if ring_data.is_empty():
			Debug.log("chunk_perf", "ring=%d no-data" % ring)
			continue
		for stage in [STAGE_GENERATE, STAGE_GROUND_CONNECT, STAGE_WALL_CONNECT, STAGE_COLLIDER_BUILD, STAGE_ENTITIES]:
			var samples: Array = ring_data.get(stage, [])
			if samples.is_empty():
				continue
			var p50: float = _calc_percentile(samples, 0.50)
			var p95: float = _calc_percentile(samples, 0.95)
			Debug.log("chunk_perf", "ring=%d stage=%s n=%d p50=%.3fms p95=%.3fms" % [ring, stage, samples.size(), p50, p95])

# Retorna dict con budgets calibrados. Vacío si auto_calibrate está off.
func get_calibrated_budgets() -> Dictionary:
	if not auto_calibrate:
		return {}
	var result: Dictionary = {}
	var ring0: Dictionary = _data.get(0, {})
	var ground_samples: Array = ring0.get(STAGE_GROUND_CONNECT, [])
	var collider_samples: Array = ring0.get(STAGE_COLLIDER_BUILD, [])
	if not ground_samples.is_empty():
		var p95: float = _calc_percentile(ground_samples, 0.95)
		result["terrain_paint_ms_budget"] = clampf(maxf(0.75, p95 * 1.15), 0.75, 8.0)
	if not collider_samples.is_empty():
		var p95: float = _calc_percentile(collider_samples, 0.95)
		result["wall_collider_chunks_per_tick"] = int(clampf(floor(4.0 / maxf(0.1, p95)), 1.0, 4.0))
	if not result.is_empty():
		Debug.log("chunk_perf", "calibrated terrain_paint_ms_budget=%s wall_collider_chunks_per_tick=%s" % [
			str(result.get("terrain_paint_ms_budget", "unchanged")),
			str(result.get("wall_collider_chunks_per_tick", "unchanged")),
		])
	return result

func _check_alert(stage: String, ring: int, elapsed_ms: float, chunk_pos: Vector2i) -> void:
	if ring != 0:
		return
	var threshold: float = _alert_threshold(stage)
	if threshold <= 0.0 or elapsed_ms <= threshold:
		return
	Debug.log("chunk_perf", "ALERT stage=%s ring=%d chunk=%s ms=%.3f threshold=%.3f" % [
		stage, ring, str(chunk_pos), elapsed_ms, threshold
	])

func _alert_threshold(stage: String) -> float:
	match stage:
		STAGE_GENERATE:      return alert_generate_ms
		STAGE_GROUND_CONNECT: return alert_ground_connect_ms
		STAGE_WALL_CONNECT:  return alert_wall_connect_ms
		STAGE_COLLIDER_BUILD: return alert_collider_ms
		STAGE_ENTITIES:      return alert_entities_ms
		_: return 0.0

func _calc_percentile(values: Array, ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	var idx: int = int(round((sorted.size() - 1) * clampf(ratio, 0.0, 1.0)))
	return float(sorted[idx])
