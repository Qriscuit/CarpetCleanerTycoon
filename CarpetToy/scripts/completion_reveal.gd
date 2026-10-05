extends CanvasLayer
## Short appreciation beat. Holding Compare pauses it; Next rug skips it.
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
var _canceled := false
var _touches: Dictionary = {}
@export var preview_safe_insets := Vector4.ZERO

func _ready() -> void:
	hide()
	set_process(false)
	get_viewport().size_changed.connect(_layout)
	%ContinueButton.pressed.connect(continue_now)
	%CompareButton.button_down.connect(set_comparing.bind(true))
	%CompareButton.button_up.connect(set_comparing.bind(false))
	%CompareButton.focus_exited.connect(set_comparing.bind(false))
	_layout()

func show_reveal(full: bool, fraction: float, can_compare: bool, reward: int, initial_label: String = "Before") -> void:
	active = true
	comparing = false
	remaining = 2.4 if full else 1.1
	before_label = initial_label
	%Title.text = "Rug restored" if full else "Job finished"
	%Detail.text = "%d%% cleaned" % floori(clampf(fraction, 0.0, 1.0) * 100.0 + 0.0001)
	if reward > 0: %Detail.text += "  ·  +%s coins" % _money_text(reward)
	if full: %Detail.text = "+%s coins earned" % _money_text(reward) if reward > 0 else "Fresh and ready"
	%ViewLabel.text = "After"
	%CompareButton.visible = can_compare
	_clear_pointer()
	show()
	_layout()
	set_process(true)
	%ContinueButton.grab_focus()

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
	%ViewLabel.text = before_label if before else "After"
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
	return Rect2(Vector2(inset.x, inset.y), extent - Vector2(inset.x + inset.z, inset.y + inset.w))

func _layout() -> void:
	if not is_node_ready() or not is_inside_tree() or get_viewport() == null: return
	var extent := get_viewport().get_visible_rect().size
	var window_size := Vector2(DisplayServer.window_get_size())
	var pixels_per_unit := minf(window_size.x / maxf(extent.x, 1), window_size.y / maxf(extent.y, 1))
	var ui_scale := clampf(44.0 / (52.0 * maxf(pixels_per_unit, 0.01)), 1.0, 2.5)
	$Content.scale = Vector2.ONE * ui_scale
	var raw_safe := _safe_rect()
	var safe := Rect2(raw_safe.position / ui_scale, raw_safe.size / ui_scale)
	if safe.size.x > safe.size.y * 1.35:
		# Keep a tall rug prominent in landscape: place controls beside it.
		var width := minf(350.0, safe.size.x * 0.43)
		%Heading.size = Vector2(width, 108.0)
		%Heading.position = Vector2(safe.end.x - width - 18.0, safe.get_center().y - 98.0)
		%Actions.size = Vector2(width, 52.0)
		%Actions.position = %Heading.position + Vector2(0.0, 132.0)
	else:
		var width := minf(370.0, safe.size.x - 28.0)
		%Heading.position = Vector2(safe.get_center().x - width * 0.5, safe.position.y + 14.0)
		%Heading.size = Vector2(width, 108.0)
		%Actions.size = Vector2(minf(350.0, safe.size.x - 28.0), 52.0)
		%Actions.position = Vector2(safe.get_center().x - %Actions.size.x * 0.5, safe.end.y - 66.0)
	layout_changed.emit()

func rug_view_rect() -> Rect2:
	var safe := _safe_rect()
	if safe.size.x > safe.size.y * 1.35:
		var right: float = %Heading.get_global_rect().position.x - 18.0 * $Content.scale.x
		return Rect2(safe.position + Vector2(18.0, 14.0), Vector2(maxf(right - safe.position.x - 18.0, 1.0), maxf(safe.size.y - 28.0, 1.0)))
	var top: float = %Heading.get_global_rect().end.y + 10.0 * $Content.scale.y
	var bottom: float = %Actions.get_global_rect().position.y - 14.0 * $Content.scale.y
	return Rect2(Vector2(safe.position.x + 18.0, top), Vector2(maxf(safe.size.x - 36.0, 1.0), maxf(bottom - top, 1.0)))

func _button_at(point: Vector2) -> Button:
	for button: Button in [%CompareButton, %ContinueButton]:
		if button.is_visible_in_tree() and button.get_global_rect().has_point(point): return button
	return null

func _press(point: Vector2, pointer: int) -> void:
	_pointer = pointer
	_origin = point
	_button = _button_at(point)
	_canceled = false
	if is_instance_valid(_button): _button.grab_focus()
	if _button == %CompareButton: set_comparing(true)

func _move(point: Vector2) -> void:
	if point.distance_to(_origin) > 14.0:
		_canceled = true
		set_comparing(false)

func _release(point: Vector2, canceled: bool) -> void:
	var next := not canceled and not _canceled and is_instance_valid(_button) and _button == %ContinueButton and _button_at(point) == _button
	set_comparing(false)
	_pointer = -1
	_button = null
	if next: continue_now()

func _clear_pointer() -> void:
	_pointer = -1
	_button = null
	_canceled = false
	_touches.clear()

func _input(event: InputEvent) -> void:
	if not active or not focused: return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			_touches[event.index] = true
			if _touches.size() == 1: _press(event.position, event.index)
			else:
				_canceled = true
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
		elif event.is_action_pressed("ui_accept"):
			continue_now()
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		focused = false
		if is_node_ready(): set_comparing(false)
		_clear_pointer()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		focused = true

func _money_text(amount: int) -> String:
	for unit: Array in [[1e15, "Q"], [1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "K"]]:
		if amount >= unit[0]: return ("%.1f" % (float(amount) / unit[0])).trim_suffix(".0") + unit[1]
	return str(amount)
