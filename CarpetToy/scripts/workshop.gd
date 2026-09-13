extends Node3D
## Mouse/touch brush control over the rug and surrounding tiled work area.

const CARPET_PLANE_Y := 0.067
const BRUSH_X_LIMIT := 2.4
const BRUSH_Z_MIN := -2.58
const BRUSH_Z_MAX := 2.82
const TOUCH_CONTACT_OFFSET := Vector2(0.0, -72.0)
const TOOL_NAMES := ["Brush", "Squeegee", "Jet spray"]
const TOOL_PIVOTS := [Vector3(0, 0.007, 0), Vector3(0, 0, 0.025), Vector3(0, 0.24, 0.689)]
const TOOL_HEAD_HALVES := [Vector2(0.305, 0.11), Vector2(0.34, 0.075), Vector2(0.035, 0.035)]
const RUG_VIEW_CENTER := Vector3(0, 0.0335, 0)
const PROGRESS_COLORS := [Color("e76c62"), Color("dfb13d"), Color("63b66e"), Color("559bdd")]
@export var rugs: Array[Resource] = [
	preload("res://resources/rugs/mint_meadow.tres"),
	preload("res://resources/rugs/terracotta_flatweave.tres"),
	preload("res://resources/rugs/indigo_weave.tres"),
]
var selected_rug := 0
var rug_buttons: Array[Button] = []
var rug_hint: Label
var progress_card: PanelContainer

@onready var camera: Camera3D = $Camera3D
@onready var brush: Node3D = $StarterTools/LargeBrush

var dirty := true
var overhead := true
var brush_dragging := false
var brush_home := Transform3D.IDENTITY
var last_brush_position := Vector3.ZERO
var state_label: Label
var progress_bar: ProgressBar
var progress_fill: StyleBoxFlat
var progress_track: Control
var progress_value_marker: HBoxContainer
var progress_fraction := 0.0
var completion_icon: TextureRect
var dirt_button: Button
var instruction_label: Label
var active_touch := -1
var stroke_time := 0
var soil: Node
var selected_tool := 0
var tool_nodes: Array[Node3D] = []
var tool_buttons: Array[Button] = []
var touch_buttons: Array[Button] = []
var contact_point := Vector3.ZERO
var shop_state: Node
var paid_contract := false
var contract_finished := false
var contract_save_failed := false
var contract_job_id := ""
var contract_label: Label
var contract_status: Label
var finish_button: Button
var reset_button: Button
var wide_brush := false
var snapshot_timer: Timer
var rug_initialized := false
const CONTRACT_TARGET := 0.90

func _ready() -> void:
	shop_state = get_node_or_null("/root/ShopState")
	paid_contract = shop_state != null and shop_state.contract_mode and not str(shop_state.active_job_id).is_empty()
	if paid_contract:
		contract_job_id = shop_state.active_job_id
		wide_brush = shop_state.owns("wide_brush")
	frame_carpet()
	add_soft_accent_lights()
	brush_home = brush.transform
	tool_nodes = [brush, $StarterTools/Squeegee, $StarterTools/JetSpray]
	contact_point = brush.position + brush.basis * TOOL_PIVOTS[0]
	last_brush_position = contact_point
	build_ui()
	soil = preload("res://scripts/dirt_controller.gd").new()
	soil.automatic_completion_enabled = not paid_contract
	soil.head_half = Vector2(0.44, 0.11) if wide_brush else soil.HEAD_HALF
	add_child(soil)
	soil.progress_changed.connect(update_progress)
	soil.surface_changed.connect(update_contract_status)
	soil.setup($RugDisplay)
	select_rug(0)
	if paid_contract and not shop_state.job_snapshot.is_empty():
		soil.restore_snapshot(shop_state.job_snapshot)
	snapshot_timer = Timer.new()
	snapshot_timer.one_shot = true
	snapshot_timer.wait_time = 0.5
	add_child(snapshot_timer)
	snapshot_timer.timeout.connect(save_contract_progress)
	update_contract_status()
	get_viewport().size_changed.connect(frame_carpet)
	soil.vacuum_started.connect(on_vacuum_started)
	soil.vacuum_finished.connect(on_vacuum_finished)
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var filename := "starter_workshop_dirty.png" if dirty else "starter_workshop_clean.png"
		if overhead: filename = "starter_workshop_top.png"
		var path := ProjectSettings.globalize_path("res://../art/renders/"+filename)
		get_viewport().get_texture().get_image().save_png(path)
		print("WORKSHOP_CAPTURE: ",path)
		print("RENDER_INFO: draw_calls=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)," primitives=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		get_tree().quit()

func _input(event: InputEvent) -> void:
	# Releases must reach us even over a UI button; one finger owns each stroke.
	if event.device == -1:
		return
	# Mouse emulation is disabled, so dispatch real touch taps to the UI explicitly.
	if event is InputEventScreenTouch and event.pressed and not event.canceled:
		for button in touch_buttons:
			if button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(event.position):
				button.pressed.emit()
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and active_touch == -1:
		end_stroke()
	elif event is InputEventScreenTouch and event.index == active_touch and (not event.pressed or event.canceled):
		end_stroke()
	elif brush_dragging:
		if event is InputEventMouseMotion and active_touch == -1:
			move_brush_to_screen(event.position, false)
			get_viewport().set_input_as_handled()
		elif event is InputEventScreenDrag and event.index == active_touch:
			move_brush_to_screen(event.position, true)
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if soil.completion_started or brush_dragging or event.device == -1:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		begin_stroke(event.position, false)
	elif event is InputEventScreenTouch and event.pressed and not event.canceled:
		active_touch = event.index
		begin_stroke(event.position, true)

func begin_stroke(screen_position: Vector2, touch_input: bool) -> void:
	if soil.completion_started:
		return
	# Placement is not a sweep from the parked tool: only held motion rakes dirt.
	if selected_tool == 0:
		soil.begin_pass()
	move_brush_to_screen(screen_position, touch_input)
	brush_dragging = true
	stroke_time = Time.get_ticks_msec()
	set_brush_instruction(true)
	get_viewport().set_input_as_handled()

func end_stroke() -> void:
	var was_dragging := brush_dragging
	if soil != null:
		soil.end_pass()
	brush_dragging = false
	active_touch = -1
	set_brush_instruction(false)
	if was_dragging:
		save_contract_progress()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		end_stroke()

func move_brush_to_screen(screen_position: Vector2, touch_input: bool) -> void:
	var contact_position := screen_position + (TOUCH_CONTACT_OFFSET if touch_input else Vector2.ZERO)
	var ray_origin := camera.project_ray_origin(contact_position)
	var ray_direction := camera.project_ray_normal(contact_position)
	if absf(ray_direction.y) < 0.0001:
		return
	var distance := (CARPET_PLANE_Y - ray_origin.y) / ray_direction.y
	if distance <= 0.0:
		return
	var target := ray_origin + ray_direction * distance
	target.x = clampf(target.x, -BRUSH_X_LIMIT, BRUSH_X_LIMIT)
	target.z = clampf(target.z, BRUSH_Z_MIN, BRUSH_Z_MAX)
	target.y = soil.brush_surface_height(target, current_head_half())
	if brush_dragging and selected_tool == 0:
		var now := Time.get_ticks_msec()
		soil.stroke(last_brush_position, target, float(now - stroke_time) / 1000.0)
		stroke_time = now
	contact_point = target
	place_selected_tool()
	last_brush_position = target

func select_tool(index: int) -> void:
	if soil.completion_started or index < 0 or index >= tool_nodes.size():
		return
	if paid_contract and index != 0:
		return
	end_stroke()
	selected_tool = index
	for i in tool_nodes.size():
		tool_nodes[i].visible = i == selected_tool
		tool_buttons[i].set_pressed_no_signal(i == selected_tool)
	contact_point.y = soil.brush_surface_height(contact_point, current_head_half())
	place_selected_tool()
	last_brush_position = contact_point
	set_brush_instruction(false)

func place_selected_tool() -> void:
	var tool := tool_nodes[selected_tool]
	var pose := Basis.IDENTITY.scaled(Vector3.ONE * 0.77)
	if selected_tool == 0 and wide_brush:
		pose = Basis.IDENTITY.scaled(Vector3(0.77 * 0.44 / 0.305, 0.77, 0.77))
	var hover := 0.0
	if selected_tool == 2:
		pose = Basis(Vector3.RIGHT, deg_to_rad(55.0)).scaled(Vector3.ONE * 1.12)
		hover = 0.14
	tool.transform = Transform3D(pose, contact_point + Vector3.UP * hover - pose * TOOL_PIVOTS[selected_tool])

func current_head_half() -> Vector2:
	return soil.head_half if selected_tool == 0 else TOOL_HEAD_HALVES[selected_tool]

func set_brush_instruction(active: bool) -> void:
	if instruction_label == null:
		return
	if contract_finished:
		instruction_label.text = "JOB COMPLETE / +20 CASH"
		return
	if selected_tool == 0:
		instruction_label.text = "SWEEP BACK FOR PASS TWO" if active else "SWEEP. REVEAL. RELAX."
	else:
		instruction_label.text = TOOL_NAMES[selected_tool].to_upper() + " / HOLD + DRAG"
	instruction_label.add_theme_color_override("font_color", Color("f58c74") if active else Color("547f72"))

func reset_rug() -> void:
	if paid_contract:
		return
	end_stroke()
	soil.reset()
	for button in tool_buttons:
		button.disabled = false
	contact_point = brush_home.origin + brush_home.basis * TOOL_PIVOTS[0]
	select_tool(selected_tool)

func select_rug(index: int) -> void:
	if index < 0 or index >= rugs.size():
		return
	if paid_contract and (index != 0 or rug_initialized):
		return
	end_stroke()
	selected_rug = index
	soil.configure_rug(rugs[index])
	for i in rug_buttons.size():
		rug_buttons[i].set_pressed_no_signal(i == index)
	rug_hint.text = rugs[index].cleaning_hint
	for button in tool_buttons:
		button.disabled = false
	if paid_contract:
		for i in tool_buttons.size():
			tool_buttons[i].disabled = i != 0
	contact_point = brush_home.origin + brush_home.basis * TOOL_PIVOTS[0]
	select_tool(0)
	rug_initialized = true

func update_progress(remaining: int, total: int) -> void:
	var fraction := float(total - remaining) / maxf(total, 1)
	progress_fraction = clampf(fraction, 0.0, 1.0)
	var percent := floori(fraction * 100.0)
	dirty = fraction < soil.COMPLETION_FRACTION
	state_label.text = "%d%%" % percent
	var color := progress_color(fraction)
	progress_bar.value = fraction * 100.0
	progress_fill.bg_color = color
	progress_fill.shadow_color = Color(color, 0.42)
	state_label.add_theme_color_override("font_color", color)
	state_label.add_theme_color_override("font_shadow_color", Color(color, 0.34))
	completion_icon.visible = not dirty
	call_deferred("position_progress_value")
	update_contract_status()
	if paid_contract and snapshot_timer != null:
		snapshot_timer.start()

func progress_color(fraction: float) -> Color:
	var stage := clampf(fraction, 0.0, 1.0) * 3.0
	var index := mini(floori(stage), 2)
	return PROGRESS_COLORS[index].lerp(PROGRESS_COLORS[index + 1], stage - index)

func toggle_view() -> void:
	end_stroke()
	frame_carpet()

func frame_carpet() -> void:
	overhead = true
	var viewport_size := get_viewport().get_visible_rect().size
	# Reserve the left rug rail and right tool rail so neither covers the carpet.
	var usable_width := maxf(viewport_size.x - 304.0, 120.0)
	var aspect := usable_width / maxf(viewport_size.y, 1.0)
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = maxf(4.35, 2.2 / aspect)
	camera.position = Vector3(-56.0 * camera.size / maxf(viewport_size.y, 1.0), 9, -0.20)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	if soil != null:
		soil.request_render()

func on_vacuum_started() -> void:
	end_stroke()
	for tool in tool_nodes:
		tool.hide()
	for button in tool_buttons:
		button.disabled = true
	instruction_label.text = "CLEARING UP..."

func on_vacuum_finished() -> void:
	instruction_label.text = "JOB COMPLETE / +20 CASH" if contract_finished else "BEAUTIFULLY CLEAN"
	if contract_finished:
		update_progress(0, soil.initial.size())

func update_contract_status() -> void:
	if not paid_contract or soil == null or contract_status == null:
		return
	var clumps: float = soil.unique_clearance()
	var surface: float = soil.surface_clearance()
	contract_status.text = "Debris %d%%  /  Dust %d%%\nReach 90%% on both to finish." % [floori(clumps * 100.0), floori(surface * 100.0)]
	finish_button.disabled = contract_finished or clumps < CONTRACT_TARGET or surface < CONTRACT_TARGET
	if contract_finished:
		contract_status.text = "Beautiful work!\n20 cash added to your shop."
		finish_button.text = "JOB COMPLETE"
	elif contract_save_failed:
		contract_status.text = "Couldn't save this rug.\nTry Back to shop again."

func save_contract_progress() -> bool:
	if not paid_contract or contract_finished:
		return true
	if is_instance_valid(soil) and is_instance_valid(shop_state) and shop_state.active_job_id == contract_job_id:
		if shop_state.save_job_snapshot(soil.make_snapshot()):
			contract_save_failed = false
			update_contract_status()
			return true
	contract_save_failed = true
	if is_instance_valid(contract_status):
		contract_status.text = "Couldn't save this rug.\nTry Back to shop again."
	return false

func finish_contract() -> void:
	if not paid_contract or contract_finished or soil.unique_clearance() < CONTRACT_TARGET or soil.surface_clearance() < CONTRACT_TARGET:
		return
	end_stroke()
	if not shop_state.save_job_snapshot(soil.make_snapshot()):
		contract_status.text = "Couldn't save this job.\nTry Finish again."
		return
	if not shop_state.complete_job(contract_job_id):
		contract_status.text = "Couldn't finish this job.\nYour cleaning is saved."
		return
	contract_finished = true
	update_contract_status()
	soil.start_vacuum(true)

func return_to_shop() -> void:
	end_stroke()
	if not save_contract_progress():
		return
	if shop_state != null:
		shop_state.contract_mode = false
	get_tree().change_scene_to_file("res://scenes/shop_hub.tscn")

func _exit_tree() -> void:
	save_contract_progress()

func add_soft_accent_lights() -> void:
	# Small, shadowless color pools give the vinyl objects a gentle mobile-safe glow.
	for data in [
		[Vector3(-1.8, 2.1, -1.6), Color("ffc7a8")],
		[Vector3(1.7, 1.7, 1.4), Color("9fe2d1")],
	]:
		var light := OmniLight3D.new()
		light.light_color = data[1]
		light.light_energy = 0.18
		light.omni_range = 3.6
		light.omni_attenuation = 1.35
		light.shadow_enabled = false
		light.position = data[0]
		add_child(light)

func position_progress_value() -> void:
	if progress_track == null or progress_value_marker == null:
		return
	progress_value_marker.reset_size()
	var marker_width := progress_value_marker.size.x
	var available := maxf(progress_track.size.x - marker_width, 0.0)
	progress_value_marker.position = Vector2(available * progress_fraction, 35.0)

func label(text: String,size: int,color: String) -> Label:
	var node := Label.new()
	node.text=text
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",Color(color))
	return node

func style(color: String) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color=Color(color)
	box.set_corner_radius_all(16)
	return box

func build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GymUI"
	add_child(layer)
	var root := Control.new()
	root.name = "HUD"
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var heading := VBoxContainer.new()
	heading.position = Vector2(16, 16)
	heading.add_theme_constant_override("separation", 4)
	root.add_child(heading)
	heading.add_child(label("MINT MEADOW JOB" if paid_contract else "RUG CLEANING GYM", 15, "285c50"))
	instruction_label = label("SWEEP. REVEAL. RELAX.", 10, "547f72")
	heading.add_child(instruction_label)
	var picker := VBoxContainer.new()
	root.add_child(picker)
	picker.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	picker.offset_left = -88
	picker.offset_right = -24
	picker.offset_top = 24
	picker.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	var icons := [preload("res://assets/ui/brush.svg"), preload("res://assets/ui/squeegee.svg"), preload("res://assets/ui/spray.svg")]
	for i in TOOL_NAMES.size():
		var button := Button.new()
		button.name = ["BrushButton", "SqueegeeButton", "JetSprayButton"][i]
		button.icon = icons[i]
		button.tooltip_text = TOOL_NAMES[i]
		if paid_contract:
			button.tooltip_text = ("Wide brush / 44% wider reach" if wide_brush else "Starter brush") if i == 0 else "Practice tool / try it in the Rug Cleaning Gym"
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(64, 60)
		button.add_theme_font_size_override("font_size", 17)
		button.add_theme_color_override("font_color", Color("285c50"))
		button.add_theme_color_override("font_hover_color", Color("285c50"))
		button.add_theme_color_override("font_pressed_color", Color("fff8e8"))
		button.add_theme_stylebox_override("normal", style("f6eedb"))
		button.add_theme_stylebox_override("disabled", style("f6eedb"))
		button.add_theme_stylebox_override("hover", style("e4ead8"))
		button.add_theme_stylebox_override("pressed", style("328671"))
		button.add_theme_stylebox_override("hover_pressed", style("328671"))
		button.pressed.connect(select_tool.bind(i))
		picker.add_child(button)
		tool_buttons.append(button)
		touch_buttons.append(button)
	var card := PanelContainer.new()
	progress_card = card
	card.name = "CleaningProgress"
	root.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	card.offset_left = 16
	card.offset_right = 200
	card.offset_top = 64
	var card_style := style("fff8e9")
	card_style.set_corner_radius_all(22)
	card_style.shadow_color = Color(0.22,0.35,0.30,0.12)
	card_style.shadow_size = 2
	card_style.shadow_offset = Vector2(0,4)
	card_style.content_margin_left = 16
	card_style.content_margin_right = 16
	card_style.content_margin_top = 18
	card_style.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", card_style)
	progress_track = Control.new()
	progress_track.custom_minimum_size = Vector2(152, 70)
	card.add_child(progress_track)
	progress_track.resized.connect(position_progress_value)
	progress_bar = ProgressBar.new()
	progress_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	progress_bar.offset_bottom = 26
	progress_bar.show_percentage = false
	progress_bar.step = 0.0
	progress_bar.add_theme_stylebox_override("background", style("e3e5d8"))
	progress_fill = style("e76c62")
	progress_fill.shadow_color = Color("6ee76c62")
	progress_fill.shadow_size = 8
	progress_fill.shadow_offset = Vector2.ZERO
	progress_bar.add_theme_stylebox_override("fill", progress_fill)
	progress_track.add_child(progress_bar)
	progress_value_marker = HBoxContainer.new()
	progress_value_marker.add_theme_constant_override("separation", 6)
	progress_track.add_child(progress_value_marker)
	state_label = label("0%", 26, "e76c62")
	state_label.add_theme_color_override("font_shadow_color", Color("57e76c62"))
	state_label.add_theme_constant_override("shadow_outline_size", 6)
	progress_value_marker.add_child(state_label)
	completion_icon = TextureRect.new()
	completion_icon.texture = preload("res://assets/ui/complete.svg")
	completion_icon.custom_minimum_size = Vector2(24, 24)
	completion_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	completion_icon.visible = false
	progress_value_marker.add_child(completion_icon)
	var rug_picker := VBoxContainer.new()
	rug_picker.name = "RugPicker"
	root.add_child(rug_picker)
	rug_picker.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	rug_picker.offset_left = 16
	rug_picker.offset_right = 200
	rug_picker.offset_top = 180
	rug_picker.add_theme_constant_override("separation", 10)
	rug_picker.add_child(label("CUSTOMER RUG" if paid_contract else "TEST RUGS", 12, "547f72"))
	var rug_group := ButtonGroup.new()
	for i in rugs.size():
		var button := Button.new()
		button.name = "RugButton%d" % i
		button.text = rugs[i].display_name
		button.tooltip_text = rugs[i].cleaning_hint
		button.toggle_mode = true
		button.button_group = rug_group
		button.custom_minimum_size = Vector2(184, 52)
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_color_override("font_color", Color("285c50"))
		button.add_theme_color_override("font_hover_color", Color("285c50"))
		button.add_theme_color_override("font_pressed_color", Color("fff8e8"))
		button.add_theme_stylebox_override("normal", style("f6eedb"))
		button.add_theme_stylebox_override("hover", style("e4ead8"))
		button.add_theme_stylebox_override("pressed", style("328671"))
		button.add_theme_stylebox_override("hover_pressed", style("328671"))
		button.add_theme_stylebox_override("disabled", style("dce9d8"))
		button.add_theme_color_override("font_disabled_color", Color("285c50"))
		button.pressed.connect(select_rug.bind(i))
		if paid_contract:
			button.disabled = true
			button.visible = i == 0
		rug_picker.add_child(button)
		rug_buttons.append(button)
		touch_buttons.append(button)
	rug_hint = label("", 12, "285c50")
	rug_hint.custom_minimum_size.x = 184
	rug_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rug_picker.add_child(rug_hint)
	var restart := Button.new()
	reset_button = restart
	restart.name = "ResetRugButton"
	restart.text = "Reset rug"
	restart.custom_minimum_size.y = 40
	restart.add_theme_font_size_override("font_size", 13)
	restart.add_theme_color_override("font_color", Color("285c50"))
	restart.add_theme_stylebox_override("normal", style("e4ead8"))
	restart.pressed.connect(reset_rug)
	restart.visible = not paid_contract
	rug_picker.add_child(restart)
	touch_buttons.append(restart)
	if paid_contract:
		var contract_card := PanelContainer.new()
		contract_card.name = "ContractCard"
		var contract_style := style("fff8e9")
		contract_style.content_margin_left = 12
		contract_style.content_margin_right = 12
		contract_style.content_margin_top = 14
		contract_style.content_margin_bottom = 14
		contract_card.add_theme_stylebox_override("panel", contract_style)
		rug_picker.add_child(contract_card)
		var contract_column := VBoxContainer.new()
		contract_column.add_theme_constant_override("separation", 9)
		contract_card.add_child(contract_column)
		contract_column.add_child(label("JOB REWARD", 11, "547f72"))
		contract_label = label("+20 CASH", 22, "cf9634")
		contract_column.add_child(contract_label)
		contract_status = label("", 11, "285c50")
		contract_status.custom_minimum_size.x = 156
		contract_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		contract_column.add_child(contract_status)
		finish_button = Button.new()
		finish_button.name = "FinishJobButton"
		finish_button.text = "FINISH JOB"
		finish_button.custom_minimum_size.y = 46
		finish_button.add_theme_font_size_override("font_size", 13)
		finish_button.add_theme_color_override("font_color", Color.WHITE)
		finish_button.add_theme_color_override("font_disabled_color", Color("86a296"))
		finish_button.add_theme_stylebox_override("normal", style("43a963"))
		finish_button.add_theme_stylebox_override("hover", style("5cba78"))
		finish_button.add_theme_stylebox_override("pressed", style("328671"))
		finish_button.add_theme_stylebox_override("disabled", style("e4ead8"))
		finish_button.pressed.connect(finish_contract)
		contract_column.add_child(finish_button)
		touch_buttons.append(finish_button)
		var equipment := label("WIDE BRUSH\n44% wider cleaning reach" if wide_brush else "STARTER BRUSH\nSweep beyond the rug edges.", 11, "547f72")
		equipment.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		equipment.custom_minimum_size.x = 184
		rug_picker.add_child(equipment)
		rug_picker.add_child(label("Progress saves as you clean.", 10, "547f72"))
	var back := Button.new()
	back.name = "BackToShopButton"
	back.text = "<  BACK TO SHOP"
	back.custom_minimum_size = Vector2(184, 48)
	back.add_theme_font_size_override("font_size", 12)
	back.add_theme_color_override("font_color", Color("285c50"))
	back.add_theme_stylebox_override("normal", style("fff8e9"))
	back.add_theme_stylebox_override("hover", style("e4ead8"))
	back.add_theme_stylebox_override("pressed", style("c6dbc8"))
	back.pressed.connect(return_to_shop)
	root.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	back.offset_left = 16
	back.offset_right = 200
	back.offset_top = -68
	back.offset_bottom = -20
	touch_buttons.append(back)


