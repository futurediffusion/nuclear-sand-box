extends Node

const DEFAULT_CHUNK_SAVE := {
	"entities": {},
	"flags": {}
}

var chunks: Dictionary = {}  # chunk_key(String) -> ChunkSave(Dictionary)

func chunk_key(cx: int, cy: int) -> String:
	return "%d,%d" % [cx, cy]

func get_chunk_save(cx: int, cy: int) -> Dictionary:
	var k := chunk_key(cx, cy)
	if not chunks.has(k):
		chunks[k] = {
			"entities": {},
			"flags": {}
		}
	return chunks[k]

func get_entity_state(cx: int, cy: int, uid: String):
	var cs: Dictionary = get_chunk_save(cx, cy)
	return cs["entities"].get(uid, null)

func set_entity_state(cx: int, cy: int, uid: String, state: Dictionary) -> void:
	get_chunk_save(cx, cy)["entities"][uid] = state.duplicate(true)

func erase_entity_state(cx: int, cy: int, uid: String) -> void:
	get_chunk_save(cx, cy)["entities"].erase(uid)

# --- Generic scaffolding for future chunk facts (props moved/broken, chests looted, NPC KO/dead, etc.) ---
func get_chunk_flag(cx: int, cy: int, flag_key: String):
	return get_chunk_save(cx, cy)["flags"].get(flag_key, null)

func set_chunk_flag(cx: int, cy: int, flag_key: String, value) -> void:
	get_chunk_save(cx, cy)["flags"][flag_key] = value

