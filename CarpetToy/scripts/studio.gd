extends Node3D
## A small art-review scene. The reusable carpet scene has no UI or camera.

@onready var camera: Camera3D = $Camera3D
@onready var carpet: Node3D = $Carpet
var top_view := false
var turn := false
var ui: CanvasLayer

func _ready() -> void:
	camera.look_at(Vector3(0, 0, 0))
	_build_ui()
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
			KEY_SPACE: turn = not turn
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
	top_view = false
	carpet.rotation.y = -0.14
	camera.position = Vector3(3.1, 6.8, 4.7)
	camera.look_at(Vector3.ZERO)

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _style(bg: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	var header := VBoxContainer.new()
	header.position = Vector2(42, 38)
	header.add_theme_constant_override("separation", 4)
	root.add_child(header)
	header.add_child(_label("CARPET CLEANER  /  ART STUDY 01", 15, Color("408674")))
	header.add_child(_label("Mint Meadow", 42, Color("244b42")))
	header.add_child(_label("A little sunshine. A fresh start.", 18, Color("548474")))
	var badge := PanelContainer.new()
	badge.position = Vector2(42, 158)
	badge.add_theme_stylebox_override("panel", _style(Color("ecf4e9"), 18))
	badge.add_child(_label("CLEAN RUG  •  01", 14, Color("408674")))
	root.add_child(badge)
	var footer := VBoxContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 42
	footer.offset_right = -42
	footer.offset_top = -197
	footer.offset_bottom = -30
	footer.add_theme_constant_override("separation", 16)
	root.add_child(footer)
	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 8)
	footer.add_child(swatches)
	for c in ["72c8ab", "f8eed4", "f58c74", "308e7d", "f4c45f"]:
		var swatch := Panel.new()
		swatch.custom_minimum_size = Vector2(28, 10)
		swatch.add_theme_stylebox_override("panel", _style(Color(c), 5))
		swatches.add_child(swatch)
	footer.add_child(_label("Woven pile  ·  Soft binding  ·  Rounded fringe", 18, Color("416d60")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	footer.add_child(row)
	for title in ["Turntable", "Top / Angle", "Reset"]:
		var button := Button.new()
		button.text = title
		button.custom_minimum_size = Vector2(0, 54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_color_override("font_color", Color("f7f4e7") if title == "Turntable" else Color("30594c"))
		button.add_theme_stylebox_override("normal", _style(Color("328671") if title == "Turntable" else Color("eaf1e7"), 16))
		button.add_theme_stylebox_override("hover", _style(Color("63ae95"), 16))
		button.add_theme_stylebox_override("pressed", _style(Color("8dcbb5"), 16))
		row.add_child(button)
		match title:
			"Turntable": button.pressed.connect(func(): turn = not turn)
			"Top / Angle": button.pressed.connect(_toggle_view)
			"Reset": button.pressed.connect(_reset)
	footer.add_child(_label("MATERIAL PREVIEW   /   MATTE + WOVEN", 12, Color("628676")))
