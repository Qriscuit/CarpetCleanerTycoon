extends Node
## F6 this optional art-review scene: it exercises the real Gym extraction hook.
## Nothing here is loaded by the normal Gym or touches paid progress.

@export var autoplay := true
@export var oblique_camera := true
var game: Node3D
var clock_seconds := 0.0
var prepared := false
var previous := Vector3.ZERO
var label: Label

func _ready() -> void:
	_start.call_deferred()

func _start() -> void:
	game = get_parent()
	game.animate_rug_changes = false
	game.get_viewport().size_changed.connect(_frame)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(22, 18)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("315d61"))
	label.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	overlay.add_child(label)
	_frame()

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not autoplay: return
	if not prepared:
		game.select_rug(1)
		game.soil.apply_water_blob(Vector3.ZERO, 5.0)
		game.update_contract_status()
		game.select_tool(1)
		previous = Vector3(0, 0.067, 0.95)
		game.contact_point = previous
		game.place_selected_tool()
		prepared = true
		_frame()
	var before := clock_seconds
	clock_seconds += minf(delta, 0.08)
	if clock_seconds >= 0.30 and clock_seconds <= 2.30:
		var point := Vector3(0, 0.067, 0.95 - (clock_seconds - 0.30) * 0.72)
		game.apply_selected_tool_stroke(previous, point, minf(delta, 0.08))
		game.contact_point = point
		game.place_selected_tool()
		previous = point
	elif before <= 2.30 and clock_seconds > 2.30:
		game.squeegee_water.end_stroke()
	if clock_seconds > 3.50:
		clock_seconds = 0.0
		prepared = false

func _input(event: InputEvent) -> void:
	if not is_instance_valid(game): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			autoplay = not autoplay
			if not autoplay: game.squeegee_water.end_stroke()
			_frame()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB:
			oblique_camera = not oblique_camera
			_frame()
			get_viewport().set_input_as_handled()
	elif (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		autoplay = false
		game.squeegee_water.end_stroke()
		oblique_camera = false
		_frame()

func _frame() -> void:
	if not is_instance_valid(label): return
	label.text = "Squeegee water  /  Space: play-pause\nTab: camera  /  Click: try it"
	label.visible = oblique_camera
	game.hud.visible = not oblique_camera
	if oblique_camera:
		game.camera.position = Vector3(1.65, 2.15, 2.5)
		game.camera.look_at(Vector3(0, 0.08, 0.0))
		var viewport_size: Vector2 = game.get_viewport().get_visible_rect().size
		game.camera.size = maxf(3.25, 3.45 * viewport_size.y / maxf(1.0, viewport_size.x))
	else:
		game.camera.rotation_degrees = Vector3(-90, 0, 0)
		game.camera.position = Vector3(0, 7, 0)
		game.frame_carpet()
