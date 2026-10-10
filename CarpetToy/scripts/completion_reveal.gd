extends CanvasLayer
## Short appreciation beat. Holding Compare pauses the automatic next rug.
signal continued
signal comparison_changed(before: bool)
signal layout_changed
var active := false
var comparing := false
var remaining := 0.0
var focused := true
var before_label := "Before"
var _pointer := -1
var _origin := Vector2.ZERO
var _button: Button
var _touches: Dictionary = {}
@export var preview_safe_insets := Vector4.ZERO
@export_group("Responsive layout")
@export_range(360.0, 440.0, 10.0) var phone_portrait_width := 390.0
@export_range(340.0, 400.0, 10.0) var phone_landscape_height := 360.0
@export_range(560.0, 800.0, 20.0) var tablet_short_side := 640.0
@export_range(8.0, 32.0, 1.0) var layout_edge := 16.0
@export_range(8.0, 32.0, 1.0) var rug_gutter := 16.0
var _rug_rect := Rect2()
var _layout_extent := Vector2.ZERO
var _landscape := false

func _ready() -> void:
	hide()
	set_process(false)
	get_viewport().size_changed.connect(_layout)
	%CompareButton.button_down.connect(set_comparing.bind(true))
	%CompareButton.button_up.connect(set_comparing.bind(false))
	%CompareButton.focus_exited.connect(set_comparing.bind(false))
	_layout()

func show_reveal(full: bool, _fraction: float, can_compare: bool, _reward: float, initial_label: String = "Before") -> void:
	set_comparing(false)
	active = true
	comparing = false
	remaining = 2.4 if full else 1.1
	before_label = initial_label
	%CompareButton.visible = can_compare
	_clear_pointer()
	show()
	_layout()
	set_process(true)
	if can_compare: %CompareButton.grab_focus()

func dismiss() -> void:
	set_comparing(false)
	active = false
	_clear_pointer()
	hide()
	set_process(false)

func set_comparing(before: bool) -> void:
	before = before and active and focused and %CompareButton.visible
	if before == comparing: return
	comparing = before
	if not before: remaining = maxf(remaining, 0.9)
	comparison_changed.emit(before)

func continue_now() -> void:
	if not active or not focused: return
	dismiss()
	continued.emit()

func _process(delta: float) -> void:
	if not active or not focused or comparing or _pointer != -1: return
	remaining -= delta
	if remaining <= 0.0: continue_now()

func _safe_rect() -> Rect2:
	if get_viewport() == null: return Rect2()
	var extent := get_viewport().get_visible_rect().size
	var inset := preview_safe_insets
	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var window_size := Vector2(DisplayServer.window_get_size())
		if safe.size.x > 0 and safe.size.y > 0 and window_size.x > 0 and window_size.y > 0:
			var ratio := extent / window_size
			var origin := Vector2(safe.position - DisplayServer.window_get_position()) * ratio
			var end := origin + Vector2(safe.size) * ratio
			inset = Vector4(maxf(origin.x, 0), maxf(origin.y, 0), maxf(extent.x-end.x, 0), maxf(extent.y-end.y, 0))
	return Rect2(Vector2(inset.x, inset.y), Vector2(maxf(extent.x - inset.x - inset.z, 1.0), maxf(extent.y - inset.y - inset.w, 1.0)))

func _layout() -> void:
	if not is_node_ready() or not is_inside_tree() or get_viewport() == null: return
	var extent := get_viewport().get_visible_rect().size
	if not extent.is_equal_approx(_layout_extent):
		set_comparing(false)
		_clear_pointer()
		_layout_extent = extent
	var window_size := Vector2(DisplayServer.window_get_size())
	if DisplayServer.get_name() == "headless": window_size = Vector2(get_window().size)
	var pixels_per_unit := minf(window_size.x / maxf(extent.x, 1), window_size.y / maxf(extent.y, 1))
	var raw_safe := _safe_rect()
	# Match the cleaning HUD's phone proportions; native pixels only enforce
	# a minimum target in a small window, independent of the world canvas.
	_landscape = raw_safe.size.x > raw_safe.size.y * 1.35
	var short_side := minf(raw_safe.size.x, raw_safe.size.y)
	var elongation := maxf(raw_safe.size.x, raw_safe.size.y) / maxf(short_side, 1.0)
	var phone_weight := clampf((elongation - 1.45) / 0.30, 0.0, 1.0)
	var phone_reference := phone_landscape_height if _landscape else phone_portrait_width
	var reference_short_side := lerpf(tablet_short_side, phone_reference, phone_weight)
	var ui_scale := maxf(short_side / reference_short_side, 44.0 / (56.0 * maxf(pixels_per_unit, 0.01)))
	$Content.scale = Vector2.ONE * ui_scale
	var safe := Rect2(raw_safe.position / ui_scale, raw_safe.size / ui_scale)
	%Actions.size = Vector2(148.0, 56.0)
	var action_x: float = safe.end.x - layout_edge - %Actions.size.x if _landscape else safe.get_center().x - %Actions.size.x * 0.5
	%Actions.position = Vector2(action_x, safe.end.y - layout_edge - %Actions.size.y)
	var top: float = raw_safe.position.y + layout_edge * ui_scale
	var bottom: float = %Actions.get_global_rect().position.y - rug_gutter * ui_scale
	var next_rect := Rect2(Vector2(raw_safe.position.x + layout_edge * ui_scale, top), Vector2(maxf(raw_safe.size.x - layout_edge * ui_scale * 2.0, 1.0), maxf(bottom - top, 1.0)))
	if _landscape:
		# Use the full room height beside Compare rather than stacking the
		# diorama over a bottom row on a short screen.
		var right: float = %Actions.get_global_rect().position.x - rug_gutter * ui_scale
		next_rect.size = Vector2(maxf(right - next_rect.position.x, 1.0), maxf(raw_safe.end.y - layout_edge * ui_scale - top, 1.0))
	if not _rug_rect.is_equal_approx(next_rect):
		_rug_rect = next_rect
		layout_changed.emit()

func rug_view_rect() -> Rect2:
	return _rug_rect if _rug_rect.has_area() else _safe_rect()

func is_landscape_layout() -> bool:
	return _landscape

func _button_at(point: Vector2) -> Button:
	var button: Button = %CompareButton
	if button.is_visible_in_tree() and button.get_global_rect().has_point(point): return button
	return null

func _press(point: Vector2, pointer: int) -> void:
	_pointer = pointer
	_origin = point
	_button = _button_at(point)
	if is_instance_valid(_button): _button.grab_focus()
	if _button == %CompareButton: set_comparing(true)

func _move(point: Vector2) -> void:
	if point.distance_to(_origin) > 14.0 * $Content.scale.x:
		set_comparing(false)

func _release(_point: Vector2, _canceled_release: bool) -> void:
	set_comparing(false)
	_pointer = -1
	_button = null

func _clear_pointer() -> void:
	_pointer = -1
	_button = null
	_touches.clear()

func _input(event: InputEvent) -> void:
	if not active or not focused: return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			_touches[event.index] = true
			if _touches.size() == 1: _press(event.position, event.index)
			else:
				set_comparing(false)
		else:
			_touches.erase(event.index)
			if _pointer == event.index: _release(event.position, event.canceled)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _pointer: _move(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != -1:
		if not _touches.is_empty():
			get_viewport().set_input_as_handled()
			return
		if event.pressed: _press(event.position, -2)
		elif _pointer == -2: _release(event.position, false)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _pointer == -2:
		_move(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and not event.echo:
		if event.is_action("ui_accept") and (%CompareButton.has_focus() or (comparing and not event.pressed)):
			set_comparing(event.pressed)
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		focused = false
		if is_node_ready(): set_comparing(false)
		_clear_pointer()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		focused = true
