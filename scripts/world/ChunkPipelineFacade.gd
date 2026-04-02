extends RefCounted
class_name ChunkPipelineFacade

var _pipeline: ChunkPipeline

func setup(ctx: Dictionary) -> ChunkPipeline:
	_pipeline = ChunkPipeline.new()
	_pipeline.name = "ChunkPipeline"
	var owner: Node = ctx.get("owner")
	if owner != null:
		owner.add_child(_pipeline)
	_pipeline.setup(ctx.get("pipeline_setup", {}))
	return _pipeline

func update_chunks(ctx: Dictionary, center: Vector2i) -> void:
	var callable_update: Callable = ctx.get("update_callable", Callable())
	if callable_update.is_valid():
		await callable_update.call(center)
