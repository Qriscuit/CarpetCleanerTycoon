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
@onready var hud: CanvasLayer = $GymUI
var hud_touch := -1
var hud_button: Button
var hud_touch_origin := Vector2.ZERO
var hud_touch_last := Vector2.ZERO
var hud_touch_canceled := false
var hud_touch_scroll := false
var held_touches: Dictionary = {}
var touch_chord := false
var next_job_pending := false
const TOUCH_DRAG_THRESHOLD := 14.0
const CONTRACT_TARGET := 0.90

func _ready() -> void:
	shop_state = get_node_or_null("/root/ShopState")
	paid_contract = shop_state != null and shop_state.contract_mode and not str(shop_state.active_job_id).is_empty()
	if paid_contract:
		contract_job_id = shop_state.active_job_id
		wide_brush = shop_state.owns("wide_brush") and shop_state.equipped_brush == "wide_brush"
	frame_carpet()
	add_soft_accent_lights()
	brush_home = brush.transform
	tool_nodes = [brush, $StarterTools/Squeegee, $StarterTools/JetSpray]
	contact_point = brush.position + brush.basis * TOOL_PIVOTS[0]
	last_brush_position = contact_point
	bind_ui()
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
	if event.device == -1:
		return
	# Real touch is routed on release because mouse emulation is disabled. A
	# gesture belongs to one surface until every finger is up: a canceled swipe
	# cannot become a button tap or a new brush stroke behind the HUD.
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			held_touches[event.index] = true
			if held_touches.size() > 1:
				touch_chord = true
				hud_touch_canceled = true
				end_stroke()
			if touch_chord:
				get_viewport().set_input_as_handled()
				return
			if hud.blocks_point(event.position):
				end_stroke()
				hud_touch = event.index
				hud_touch_origin = event.position
				hud_touch_last = event.position
				hud_touch_canceled = false
				hud_button = hud.visible_button_at(event.position, touch_buttons)
				hud_touch_scroll = hud.control("LeftRail").get_global_rect().has_point(event.position)
				get_viewport().set_input_as_handled()
				return
		else:
			held_touches.erase(event.index)
			if event.index == hud_touch:
				var activate: bool = not event.canceled and not hud_touch_canceled and not touch_chord and is_instance_valid(hud_button) and hud.visible_button_at(event.position, touch_buttons) == hud_button
				var button := hud_button
				hud_touch = -1
				hud_button = null
				if held_touches.is_empty():
					touch_chord = false
				get_viewport().set_input_as_handled()
				if activate:
					button.grab_focus()
					button.pressed.emit()
				return
			if held_touches.is_empty():
				touch_chord = false
	if event is InputEventScreenDrag:
		if event.index == hud_touch:
			if event.position.distance_to(hud_touch_origin) > TOUCH_DRAG_THRESHOLD:
				hud_touch_canceled = true
			if hud_touch_scroll and hud_touch_canceled:
				var rail := hud.control("LeftRail") as ScrollContainer
				rail.scroll_vertical += roundi(hud_touch_last.y - event.position.y)
			hud_touch_last = event.position
			get_viewport().set_input_as_handled()
			return
		if touch_chord:
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and active_touch == -1:
		end_stroke()
	elif event is InputEventScreenTouch and event.index == active_touch and (not event.pressed or event.canceled):
		end_stroke()
	elif brush_dragging:
		if event is InputEventMouseMotion and active_touch == -1:
			if hud.blocks_point(event.position):
				end_stroke()
			else:
				move_brush_to_screen(event.position, false)
			get_viewport().set_input_as_handled()
		elif event is InputEventScreenDrag and event.index == active_touch:
			if hud.blocks_point(event.position) or hud.blocks_point(event.position + TOUCH_CONTACT_OFFSET):
				end_stroke()
			else:
				move_brush_to_screen(event.position, true)
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if soil.completion_started or brush_dragging or event.device == -1 or touch_chord or hud_touch != -1:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not hud.blocks_point(event.position):
			begin_stroke(event.position, false)
	elif event is InputEventScreenTouch and event.pressed and not event.canceled:
		if not hud.blocks_point(event.position) and not hud.blocks_point(event.position + TOUCH_CONTACT_OFFSET):
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
		hud_touch = -1
		hud_button = null
		held_touches.clear()
		touch_chord = false

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
	if not is_instance_valid(hud):
		return
	var state := "InstructionActive" if active else "InstructionIdle"
	if selected_tool != 0:
		state = "InstructionOther"
	if soil != null and soil.completion_started:
		state = "InstructionComplete" if soil.vacuum_complete else "InstructionVacuum"
	show_instruction(state)

func reset_rug() -> void:
	if paid_contract:
		return
	end_stroke()
	hud.control("CompletionCard").hide()
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
	hud.control("CompletionCard").hide()
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
	state_label.self_modulate = color
	completion_icon.visible = not dirty
	update_contract_status()
	if paid_contract and snapshot_timer != null:
		snapshot_timer.start()

func progress_color(fraction: float) -> Color:
	var stage := clampf(fraction, 0.0, 1.0) * 3.0
	var index := mini(floori(stage), 2)
	var colors: PackedColorArray = hud.progress_colors
	if colors.size() < 4:
		colors = PackedColorArray(PROGRESS_COLORS)
	return colors[index].lerp(colors[index + 1], stage - index)

func toggle_view() -> void:
	end_stroke()
	frame_carpet()

func frame_carpet() -> void:
	overhead = true
	var viewport_size := get_viewport().get_visible_rect().size
	# Reserve the left rug rail and right tool rail so neither covers the carpet.
	var usable_width := maxf(viewport_size.x - 348.0, 120.0)
	var aspect := usable_width / maxf(viewport_size.y, 1.0)
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = maxf(4.35, 2.2 / aspect)
	camera.position = Vector3(-54.0 * camera.size / maxf(viewport_size.y, 1.0), 9, -0.20)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	if soil != null:
		soil.request_render()

func on_vacuum_started() -> void:
	end_stroke()
	for tool in tool_nodes:
		tool.hide()
	for button in tool_buttons:
		button.disabled = true
	show_instruction("InstructionVacuum")

func on_vacuum_finished() -> void:
	show_instruction("InstructionComplete")
	hud.control("CompletionCard").show()
	hud.control("RewardReceived").visible = paid_contract
	hud.control("LeftRail").set_deferred("scroll_vertical", 10000)
	if contract_finished:
		update_progress(0, soil.initial.size())

func update_contract_status() -> void:
	if not paid_contract or soil == null or contract_status == null:
		return
	var clumps: float = soil.unique_clearance()
	var surface: float = soil.surface_clearance()
	contract_status.text = hud.contract_progress_text % [floori(clumps * 100.0), floori(surface * 100.0)]
	(hud.control("DustBar") as ProgressBar).value = surface * 100.0
	finish_button.disabled = contract_finished or clumps < CONTRACT_TARGET or surface < CONTRACT_TARGET
	hud.control("ContractCard").visible = not contract_finished
	hud.control("SaveError").visible = contract_save_failed

func save_contract_progress() -> bool:
	if not paid_contract or contract_finished:
		return true
	if is_instance_valid(soil) and is_instance_valid(shop_state) and shop_state.active_job_id == contract_job_id:
		if shop_state.save_job_snapshot(soil.make_snapshot()):
			contract_save_failed = false
			update_contract_status()
			return true
	contract_save_failed = true
	if is_instance_valid(hud):
		hud.control("SaveError").show()
	return false

func finish_contract() -> void:
	if not paid_contract or contract_finished or soil.unique_clearance() < CONTRACT_TARGET or soil.surface_clearance() < CONTRACT_TARGET:
		return
	end_stroke()
	hud.control("FinishSaveError").hide()
	hud.control("FinishError").hide()
	if not shop_state.save_job_snapshot(soil.make_snapshot()):
		hud.control("FinishSaveError").show()
		return
	if not shop_state.complete_job(contract_job_id):
		hud.control("FinishError").show()
		return
	contract_finished = true
	update_contract_status()
	soil.start_vacuum(true)

func next_rug() -> void:
	if next_job_pending or not soil.vacuum_complete:
		return
	if not paid_contract:
		select_rug((selected_rug + 1) % rugs.size())
		(hud.control("LeftRail") as ScrollContainer).scroll_vertical = 0
		return
	if not contract_finished:
		return
	hud.control("NextJobError").hide()
	if shop_state.start_job().is_empty():
		hud.control("NextJobError").show()
		return
	next_job_pending = true
	shop_state.contract_mode = true
	get_tree().change_scene_to_file("res://scenes/rug_cleaning_gym.tscn")

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

func show_instruction(node_name: String) -> void:
	for name in ["InstructionIdle", "InstructionActive", "InstructionOther", "InstructionVacuum", "InstructionComplete"]:
		hud.control(name).visible = name == node_name
	instruction_label = hud.control(node_name) as Label

func bind_ui() -> void:
	# %unique names survive moving/reparenting controls in cleaning_hud.tscn.
	# UI nodes, text, icons, dimensions and theme resources are serialized there.
	rug_buttons.assign([hud.control("RugButton0"), hud.control("RugButton1"), hud.control("RugButton2")])
	tool_buttons.assign([hud.control("BrushButton"), hud.control("SqueegeeButton"), hud.control("JetSprayButton")])
	rug_hint = hud.control("RugHint") as Label
	progress_card = hud.control("CleaningProgress") as PanelContainer
	progress_track = hud.control("ProgressTrack")
	progress_value_marker = hud.control("ProgressValueMarker") as HBoxContainer
	state_label = hud.control("ProgressValue") as Label
	progress_bar = hud.control("ProgressBar") as ProgressBar
	progress_fill = progress_bar.get_theme_stylebox("fill") as StyleBoxFlat
	completion_icon = hud.control("CompletionIcon") as TextureRect
	contract_label = hud.control("ContractReward") as Label
	contract_status = hud.control("ContractStatus") as Label
	finish_button = hud.control("FinishJobButton") as Button
	reset_button = hud.control("ResetRugButton") as Button
	hud.control("PracticeTitle").visible = not paid_contract
	hud.control("ContractTitle").visible = paid_contract
	hud.control("PracticeRugs").visible = not paid_contract
	hud.control("ContractCard").visible = paid_contract
	hud.control("PaidTarget").visible = paid_contract
	hud.control("PracticeToolsHint").visible = not paid_contract
	hud.control("StarterBrushHint").visible = paid_contract and not wide_brush
	hud.control("WideBrushHint").visible = paid_contract and wide_brush
	var reward: int = shop_state.MANUAL_REWARD if shop_state != null else 20
	contract_label.text = hud.reward_text % reward
	(hud.control("RewardReceived") as Label).text = hud.reward_received_text % reward
	for i in tool_buttons.size():
		tool_buttons[i].pressed.connect(select_tool.bind(i))
		tool_buttons[i].visible = not paid_contract or i == 0
	for i in rug_buttons.size():
		rug_buttons[i].pressed.connect(select_rug.bind(i))
		rug_buttons[i].disabled = paid_contract
	reset_button.pressed.connect(reset_rug)
	finish_button.pressed.connect(finish_contract)
	(hud.control("HomeButton") as Button).pressed.connect(return_to_shop)
	(hud.control("CompletionHomeButton") as Button).pressed.connect(return_to_shop)
	(hud.control("NextRugButton") as Button).pressed.connect(next_rug)
	touch_buttons.assign(tool_buttons)
	touch_buttons.append_array(rug_buttons)
	for name in ["ResetRugButton", "FinishJobButton", "HomeButton", "CompletionHomeButton", "NextRugButton"]:
		touch_buttons.append(hud.control(name) as Button)
	show_instruction("InstructionIdle")
