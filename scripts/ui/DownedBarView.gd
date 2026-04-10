extends TextureProgressBar
class_name DownedBarView

@export var downed_component_path: NodePath = ^"../DownedComponent"

var _downed_component: DownedComponent

func _ready() -> void:
	# Configuración visual equivalente a la actual
	texture_under = load("res://art/sprites/stamina-under.png")
	texture_progress = load("res://art/sprites/stamina-progress.png")
	tint_progress = Color(1.0, 0.8, 0.2)
	min_value = 0
	max_value = 100
	step = 0.1
	z_index = 100

	var w := float(texture_under.get_width()) if texture_under else 0.0
	var h := float(texture_under.get_height()) if texture_under else 0.0
	var bar_scale := 0.3
	scale = Vector2(bar_scale, bar_scale)
	custom_minimum_size = Vector2(w, h)
	position = Vector2(-w * bar_scale * 0.5, 10.0)

	visible = false

	# Intentar resolver el componente
	if not downed_component_path.is_empty():
		_downed_component = get_node_or_null(downed_component_path) as DownedComponent

	if _downed_component == null:
		# Fallback por si la ruta no sirve pero es hermano
		var parent := get_parent()
		if parent != null:
			for child in parent.get_children():
				if child is DownedComponent:
					_downed_component = child
					break

	if _downed_component == null:
		push_warning("DownedBarView no encontró un DownedComponent válido en la ruta '%s' ni como hermano. Se desactivará." % downed_component_path)
		set_process(false)
		return

	# Conectar señales para ocultar/mostrar si no se quiere hacer todo en _process
	if not _downed_component.entered_downed.is_connected(_on_entered_downed):
		_downed_component.entered_downed.connect(_on_entered_downed)
	if not _downed_component.revived.is_connected(_on_hide_bar):
		_downed_component.revived.connect(_on_hide_bar)
	if not _downed_component.died_final.is_connected(_on_hide_bar):
		_downed_component.died_final.connect(_on_hide_bar)

	# Sincronizar estado inicial (por si cargamos partida y ya estaba downed)
	_sync_state()

func _process(_delta: float) -> void:
	if _downed_component == null or not _downed_component.is_downed:
		if visible:
			visible = false
		return

	if not visible:
		visible = true

	# Actualizar valor del progreso
	if _downed_component.has_method("get_progress_ratio"):
		var progress_ratio: float = _downed_component.get_progress_ratio()
		value = clampf(progress_ratio * 100.0, 0.0, 100.0)

func _sync_state() -> void:
	if _downed_component != null and _downed_component.is_downed:
		_on_entered_downed()
	else:
		_on_hide_bar()

func _on_entered_downed() -> void:
	visible = true

func _on_hide_bar() -> void:
	visible = false
