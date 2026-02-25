extends Node
class_name NodePool

var scene: PackedScene = null
var _available: Array[Node] = []
var _holder: Node = null

func configure(p_scene: PackedScene, holder: Node, prewarm_count: int = 0) -> void:
	scene = p_scene
	_holder = holder
	if scene == null or _holder == null:
		return
	for _i: int in range(maxi(prewarm_count, 0)):
		var node := _create_instance()
		if node != null:
			release(node)

func acquire() -> Node:
	if _available.is_empty():
		return _create_instance()
	var node: Node = _available.pop_back() as Node
	if node == null:
		return _create_instance()
	_activate(node)
	return node

func release(node: Node) -> void:
	if node == null:
		return
	if node.get_parent() != _holder and _holder != null:
		node.reparent(_holder)
	_deactivate(node)
	_available.push_back(node)

func _create_instance() -> Node:
	if scene == null or _holder == null:
		return null
	var node: Node = scene.instantiate()
	_holder.add_child(node)
	_activate(node)
	return node

func _activate(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = true
	if node is Node2D:
		(node as Node2D).scale = Vector2.ONE
	if node.has_method("on_pool_acquired"):
		node.call("on_pool_acquired")

func _deactivate(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	if node is RigidBody2D:
		var body := node as RigidBody2D
		body.freeze = false
		body.sleeping = false
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0.0
	if node.has_method("on_pool_released"):
		node.call("on_pool_released")
