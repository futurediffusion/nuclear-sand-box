class_name UID
extends RefCounted

static func make_uid(kind: String, site_id: String = "", tile: Vector2i = Vector2i(-1, -1)) -> String:
	if site_id != "":
		return "%s:%s" % [kind, site_id]
	if tile != Vector2i(-1, -1):
		return "%s:tile:%d,%d" % [kind, tile.x, tile.y]
	return kind
