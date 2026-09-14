extends Node3D
## A small art-review scene. The reusable carpet scene has no UI or camera.

@onready var camera: Camera3D = $Camera3D
@onready var carpet: Node3D = $Carpet
var top_view := false
var turn := false
var ui: CanvasLayer
var touch_button: Button
var touch_index := -1
var touch_start := Vector2.ZERO
var touch_canceled := false

func _ready() -> void:
	camera.look_at(Vector3(0, 0, 0))
	_bind_ui()
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var target := ProjectSettings.globalize_path("res://../art/renders/mint_meadow_godot.png")
		get_viewport().get_texture().get_image().save_png(target)
		print("GODOT_CAPTURE: ", target)
		get_tree().quit()

func _process(delta: float) -> void:
	if turn:
		carpet.rotation.y += delta * 0.35

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE: _toggle_turntable()
			KEY_T: _toggle_view()
			KEY_R: _reset()

func _toggle_view() -> void:
	top_view = not top_view
	if top_view:
		camera.position = Vector3(0, 8, 0.001)
	else:
		camera.position = Vector3(3.1, 6.8, 4.7)
	camera.look_at(Vector3.ZERO)

func _reset() -> void:
	turn = false
	(ui.get_node("%TurntableButton") as Button).set_pressed_no_signal(false)
	top_view = false
	carpet.rotation.y = -0.14
	camera.position = Vector3(3.1, 6.8, 4.7)
	camera.look_at(Vector3.ZERO)

func _toggle_turntable() -> void:
	turn = not turn
	(ui.get_node("%TurntableButton") as Button).set_pressed_no_signal(turn)

func _input(event: InputEvent) -> void:
	if event.device == -1:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if touch_index != -1:
				touch_canceled = true
				return
			touch_index = event.index
			touch_start = event.position
			touch_canceled = false
			for node_name in ["TurntableButton", "ViewButton", "ResetButton"]:
				var button := ui.get_node("%" + node_name) as Button
				if button.get_global_rect().has_point(event.position):
					touch_button = button
					get_viewport().set_input_as_handled()
					break
		elif event.index == touch_index:
			var button := touch_button
			touch_index = -1
			touch_button = null
			if is_instance_valid(button) and not event.canceled and not touch_canceled and button.get_global_rect().has_point(event.position):
				get_viewport().set_input_as_handled()
				button.pressed.emit()
	elif event is InputEventScreenDrag and event.index == touch_index:
		if event.position.distance_to(touch_start) > 14.0:
			touch_canceled = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		touch_index = -1
		touch_button = null

func _bind_ui() -> void:
	ui = $StudioUI
	(ui.get_node("%TurntableButton") as Button).pressed.connect(_toggle_turntable)
	(ui.get_node("%ViewButton") as Button).pressed.connect(_toggle_view)
	(ui.get_node("%ResetButton") as Button).pressed.connect(_reset)
