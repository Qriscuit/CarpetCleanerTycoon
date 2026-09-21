extends Node3D
## Mouse/touch brush control over the rug and surrounding tiled work area.
const Routes = preload("res://scripts/scene_routes.gd")
const Pop = preload("res://scripts/ui/button_pop.gd")
const ShopLedger = preload("res://scripts/shop_state.gd")
@export var practice_only := false
@export var animate_rug_changes := true
enum RugPhase { ARRIVING, GROWING, TOOL_ENTERING, CLEANING, VACUUMING, DEPARTING }
var rug_phase := RugPhase.ARRIVING
var rug_roll := preload("res://scripts/rug_roll.gd").new()
var transition_tween: Tween
var leaving_scene := false

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
var progress_fraction := 0.0
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
var finish_button: Button
var wide_brush := false
var tool_width := 1.0
var wet_recipe := false
var tool_visuals: RefCounted
var updating_progression := false
var switching_tool := false
var cached_progression: Dictionary = {}
var applied_visual_tier := -1
var applied_strength := -1.0
var cached_purchase_state := false
var snapshot_timer: Timer
var rug_initialized := false
@onready var hud: CanvasLayer = $GymUI
var hud_touch := -1
var hud_button: Button
var hud_touch_origin := Vector2.ZERO
var hud_touch_canceled := false
var held_touches: Dictionary = {}
var touch_chord := false
var next_job_pending := false
var finish_requested := false
var auto_finish_queued := false
var replacement_job_id := ""
var completed_reward := 0
var original_scale_size := Vector2i.ZERO
var original_scale_aspect := 0
var original_scale_mode := 0
var original_orientation := -1
const TOUCH_DRAG_THRESHOLD := 14.0
const CONTRACT_TARGET := ShopLedger.MANUAL_COMPLETION_THRESHOLD
const AUTO_FINISH_TARGET := ShopLedger.PERFECT_COMPLETION_THRESHOLD

func _ready() -> void:
	var window := get_window()
	original_scale_size = window.content_scale_size
	original_scale_aspect = window.content_scale_aspect
	original_scale_mode = window.content_scale_mode
	window.content_scale_size = Vector2i(720, 1000)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if OS.has_feature("mobile"):
		original_orientation = DisplayServer.screen_get_orientation()
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
	shop_state = get_node_or_null("/root/ShopState")
	if practice_only:
		if shop_state != null:
			shop_state.contract_mode = false
	else:
		# This production scene is always the paid cleaning window. Direct F6
		# entry and a process restart both create/resume a real rug automatically.
		paid_contract = shop_state != null
		if paid_contract:
			shop_state.contract_mode = true
			if str(shop_state.active_job_id).is_empty():
				shop_state.start_job()
	if paid_contract:
		contract_job_id = str(shop_state.active_job_id)
		wide_brush = shop_state.owns("wide_brush") and shop_state.equipped_brush == "wide_brush"
	frame_carpet()
	add_soft_accent_lights()
	brush_home = brush.transform
	tool_nodes = [brush, $StarterTools/Squeegee, $StarterTools/JetSpray]
	tool_visuals = preload("res://scripts/tool_progression_visual.gd").new()
	tool_visuals.setup(brush)
	contact_point = brush.position + brush.basis * TOOL_PIVOTS[0]
	last_brush_position = contact_point
	bind_ui()
	if shop_state != null:
		hud.initialize_wallet(shop_state.cash)
		shop_state.changed.connect(_sync_wallet)
		shop_state.ad_reward_granted.connect(_show_ad_reward)
	soil = preload("res://scripts/dirt_controller.gd").new()
	# Workshop owns the 85% manual and 99% automatic rules for both modes.
	soil.automatic_completion_enabled = false
	soil.head_half = Vector2(0.44, 0.11) if wide_brush else soil.HEAD_HALF
	add_child(soil)
	soil.progress_changed.connect(update_progress)
	soil.surface_changed.connect(update_surface_progress)
	soil.vacuum_started.connect(on_vacuum_started)
	soil.vacuum_finished.connect(on_vacuum_finished)
	soil.setup($RugDisplay)
	wet_recipe = paid_contract and shop_state.active_store >= 3
	soil.set_recipe(wet_recipe)
	if animate_rug_changes:
		rug_roll.setup($RugDisplay/Dirty/CarpetMesh)
	select_rug(0)
	_sync_progression()
	if paid_contract and not shop_state.job_snapshot.is_empty():
		soil.restore_snapshot(shop_state.job_snapshot)
		applied_strength = -1.0
		_sync_progression()
	snapshot_timer = Timer.new()
	snapshot_timer.one_shot = true
	snapshot_timer.wait_time = 0.5
	add_child(snapshot_timer)
	snapshot_timer.timeout.connect(save_contract_progress)
	start_rug_arrival()
	get_viewport().size_changed.connect(frame_carpet)
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
				if is_instance_valid(hud_button):
					Pop.reset(hud_button)
				end_stroke()
			if touch_chord:
				get_viewport().set_input_as_handled()
				return
			if hud.blocks_point(event.position):
				end_stroke()
				hud_touch = event.index
				hud_touch_origin = event.position
				hud_touch_canceled = false
				hud_button = hud.visible_button_at(event.position, touch_buttons)
				if is_instance_valid(hud_button):
					Pop.press(hud_button)
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
					Pop.release(button)
					button.grab_focus()
					button.pressed.emit()
				elif is_instance_valid(button):
					Pop.reset(button)
				return
			if held_touches.is_empty():
				touch_chord = false
	if event is InputEventScreenDrag:
		if event.index == hud_touch:
			if not hud_touch_canceled and event.position.distance_to(hud_touch_origin) > TOUCH_DRAG_THRESHOLD:
				hud_touch_canceled = true
				if is_instance_valid(hud_button):
					Pop.reset(hud_button)
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
	if rug_phase != RugPhase.CLEANING or leaving_scene or soil.completion_started or brush_dragging or event.device == -1 or touch_chord or hud_touch != -1:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not hud.blocks_point(event.position):
			begin_stroke(event.position, false)
	elif event is InputEventScreenTouch and event.pressed and not event.canceled:
		if not hud.blocks_point(event.position) and not hud.blocks_point(event.position + TOUCH_CONTACT_OFFSET):
			active_touch = event.index
			begin_stroke(event.position, true)

func begin_stroke(screen_position: Vector2, touch_input: bool) -> void:
	if rug_phase != RugPhase.CLEANING or leaving_scene or hud.upgrades_open() or soil.completion_started:
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
	if was_dragging and not finish_requested:
		save_contract_progress()
	if wet_recipe and not switching_tool and rug_phase == RugPhase.CLEANING and not finish_requested:
		_advance_wet_tool.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_node_ready():
		back()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		end_stroke()
		if is_instance_valid(hud_button):
			Pop.reset(hud_button)
		hud_touch = -1
		hud_button = null
		held_touches.clear()
		touch_chord = false

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		back()
		get_viewport().set_input_as_handled()

func back() -> void:
	if hud.upgrades_open():
		hud.close_upgrades()
	else:
		return_to_shop()

func _sync_wallet() -> void:
	hud.sync_wallet(shop_state.cash)
	_sync_progression()

func _sync_progression() -> void:
	if updating_progression or shop_state == null or not paid_contract: return
	updating_progression = true
	var view: Dictionary = shop_state.progression_view()
	var wider: bool = float(view.tool_width) > tool_width
	tool_width = float(view.tool_width)
	wide_brush = tool_width > 1.0
	if soil != null:
		soil.head_half = Vector2(0.305 * tool_width, 0.11)
		if wider and not brush_dragging:
			contact_point.x = clampf(contact_point.x, -1.0 + soil.head_half.x, 1.0 - soil.head_half.x)
		var strength: float = float(view.get("wet_power", view.tool_power)) if wet_recipe and selected_tool != 0 else float(view.tool_power)
		if strength != applied_strength:
			soil.set_tool_strength(strength)
			applied_strength = strength
		if int(view.global_tool_tier) != applied_visual_tier:
			tool_visuals.apply_tier(int(view.global_tool_tier), tool_width)
			applied_visual_tier = int(view.global_tool_tier)
		if rug_phase == RugPhase.CLEANING: place_selected_tool()
	var allowed := rug_phase == RugPhase.CLEANING and not finish_requested and not leaving_scene
	if cached_progression != view or cached_purchase_state != allowed:
		hud.set_progression(view, allowed)
		cached_progression = view
		cached_purchase_state = allowed
	var offer: Dictionary = shop_state.reward_offer()
	hud.set_ad_offer(int(offer.get("amount", 0)), shop_state.reward_ad_available())
	updating_progression = false

func _purchase_payout() -> void:
	if not _can_purchase(): return
	end_stroke()
	if shop_state.buy_payout_upgrade(): update_contract_status()
	_sync_progression()

func _purchase_tool() -> void:
	if not _can_purchase(): return
	end_stroke()
	if shop_state.buy_tool_upgrade():
		_sync_progression()
		if not hud.upgrades_open(): select_tool(selected_tool)

func _can_purchase() -> bool:
	return paid_contract and rug_phase == RugPhase.CLEANING and not finish_requested and not leaving_scene and hud.pending_reward == 0

func _request_rewarded_ad() -> void:
	if not _can_purchase() or not shop_state.reward_ad_available(): return
	end_stroke()
	shop_state.request_reward_ad(str(shop_state.reward_offer().get("job_id", "")))

func _show_ad_reward(amount: int) -> void:
	if leaving_scene: return
	hud.reserve_reward(amount)
	hud.show_reward(amount, shop_state.cash)

func _advance_wet_tool() -> void:
	if not wet_recipe or brush_dragging or rug_phase != RugPhase.CLEANING or finish_requested: return
	var next_tool: int = soil.recommended_tool()
	if next_tool != selected_tool: select_tool(next_tool)

func _on_upgrades_changed(open: bool) -> void:
	end_stroke()
	if open:
		soil.suspend_simulation(true)
		if transition_tween != null and transition_tween.is_valid():
			transition_tween.pause()
	else:
		soil.suspend_simulation(rug_phase not in [RugPhase.CLEANING, RugPhase.VACUUMING])
		if transition_tween != null and transition_tween.is_valid():
			transition_tween.play()
	update_contract_status()

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
	if brush_dragging:
		var now := Time.get_ticks_msec()
		var dt := float(now - stroke_time) / 1000.0
		if last_brush_position.distance_squared_to(target) > 0.00001:
			if paid_contract: shop_state.note_current_tool_used()
			if selected_tool == 0: soil.stroke(last_brush_position, target, dt)
			elif wet_recipe and selected_tool == 2: soil.apply_water_stroke(last_brush_position, target, dt)
			elif wet_recipe and selected_tool == 1: soil.apply_squeegee_stroke(last_brush_position, target, dt)
		stroke_time = now
	contact_point = target
	place_selected_tool()
	last_brush_position = target

func select_tool(index: int) -> void:
	if soil.completion_started or index < 0 or index >= tool_nodes.size():
		return
	if paid_contract and not wet_recipe and index != 0:
		return
	switching_tool = true
	end_stroke()
	selected_tool = index
	for i in tool_nodes.size():
		tool_nodes[i].visible = i == selected_tool
		if i < tool_buttons.size():
			tool_buttons[i].set_pressed_no_signal(i == selected_tool)
	contact_point.y = soil.brush_surface_height(contact_point, current_head_half())
	place_selected_tool()
	last_brush_position = contact_point
	set_brush_instruction(false)
	switching_tool = false
	_sync_progression()

func place_selected_tool() -> void:
	var tool := tool_nodes[selected_tool]
	var pose := Basis.IDENTITY.scaled(Vector3.ONE * 0.77)
	if selected_tool == 0:
		pose = Basis.IDENTITY.scaled(Vector3(0.77 * tool_width, 0.77, 0.77))
	var hover := 0.0
	if selected_tool == 2:
		pose = Basis(Vector3.RIGHT, deg_to_rad(55.0)).scaled(Vector3.ONE * 1.12)
		hover = 0.14
	tool.transform = Transform3D(pose, contact_point + Vector3.UP * hover - pose * TOOL_PIVOTS[selected_tool])

func current_head_half() -> Vector2:
	return soil.head_half if selected_tool == 0 else TOOL_HEAD_HALVES[selected_tool]

func set_brush_instruction(_active: bool) -> void:
	# The cleaning window intentionally carries no instructional copy.
	pass

func reset_rug() -> void:
	if paid_contract:
		return
	end_stroke()
	_cancel_transition()
	finish_requested = false
	auto_finish_queued = false
	contract_finished = false
	$RugDisplay.position = Vector3.ZERO
	rug_roll.set_roll(0.0)
	soil.reset()
	soil.set_reveal_progress(1.0)
	soil.suspend_simulation(false)
	rug_phase = RugPhase.CLEANING
	for button in tool_buttons:
		button.disabled = false
	contact_point = brush_home.origin + brush_home.basis * TOOL_PIVOTS[0]
	select_tool(selected_tool)
	update_contract_status()

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
	for button in tool_buttons:
		button.disabled = false
	if paid_contract:
		for i in tool_buttons.size():
			tool_buttons[i].disabled = i != 0
	contact_point = brush_home.origin + brush_home.basis * TOOL_PIVOTS[0]
	select_tool(0)
	rug_initialized = true

func update_progress(_remaining: int, _total: int) -> void:
	update_contract_status()
	queue_snapshot_save()


func update_surface_progress() -> void:
	update_contract_status()
	queue_snapshot_save()


func queue_snapshot_save() -> void:
	if paid_contract and snapshot_timer != null and snapshot_timer.is_inside_tree() and not contract_finished:
		snapshot_timer.start()


func update_contract_status() -> void:
	if soil == null or state_label == null:
		return
	# A rug is only as clean as its dirtier layer. One honest number now drives
	# the bar, the Finish button, and automatic completion.
	var fraction: float = 1.0 if contract_finished else soil.overall_clearance()
	progress_fraction = clampf(fraction, 0.0, 1.0)
	var percent := floori(progress_fraction * 100.0 + 0.0001)
	dirty = not contract_finished and progress_fraction < AUTO_FINISH_TARGET
	state_label.text = "%d%%" % percent
	var color := progress_color(progress_fraction)
	progress_bar.value = progress_fraction * 100.0
	progress_fill.bg_color = color
	progress_fill.shadow_color = Color(color, 0.42)
	finish_button.visible = rug_phase == RugPhase.CLEANING and not hud.upgrades_open() and not contract_finished and not finish_requested and progress_fraction >= CONTRACT_TARGET and (progress_fraction < AUTO_FINISH_TARGET or contract_save_failed)
	finish_button.disabled = not finish_button.visible
	if paid_contract:
		var payout: int = shop_state.reward_for_current_job(soil.make_progress_snapshot())
		finish_button.text = "Finish · %s" % hud._money_text(payout) if payout > 0 else "Finish job"
		finish_button.tooltip_text = "%d coins" % payout if payout > 0 else "Finish this rug"
	_sync_progression()
	if rug_phase == RugPhase.CLEANING and not hud.upgrades_open() and progress_fraction >= AUTO_FINISH_TARGET and not contract_finished and not finish_requested and not auto_finish_queued and not contract_save_failed:
		auto_finish_queued = true
		finish_rug.call_deferred()

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
	var aspect := maxf(viewport_size.x, 1.0) / maxf(viewport_size.y, 1.0)
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = maxf(4.35, 2.2 / aspect)
	camera.position = Vector3(0.0, 9.0, -0.20)
	# Reserve the earnings/Finish band even before Finish appears. A short
	# phone must expose every fringe without zooming when the rug reaches85%.
	if is_instance_valid(hud) and hud.is_node_ready():
		hud._layout()
		var safe: Rect2 = hud._safe_rect()
		if safe.size.x <= safe.size.y * 1.35:
			var ui_scale: float = hud.get_node("HUD").scale.y
			var top: float = hud.control("UpgradeButton").get_global_rect().end.y + 8.0 * ui_scale
			var bottom: float = hud.control("PayoutCard").get_global_rect().position.y - 80.0 * ui_scale
			var available_height := maxf(bottom - top, viewport_size.y * 0.25)
			var available_width := maxf(safe.size.x - 32.0 * ui_scale, viewport_size.x * 0.25)
			camera.size = maxf(camera.size, maxf(3.48 * viewport_size.y / available_height, 2.20 * viewport_size.y / available_width))
			camera.position.z = (0.5 - (top + bottom) * 0.5 / viewport_size.y) * camera.size
			camera.position.x = (0.5 - safe.get_center().x / viewport_size.x) * camera.size * aspect
	camera.rotation_degrees = Vector3(-90, 0, 0)
	if soil != null:
		soil.request_render()

func on_vacuum_started() -> void:
	rug_phase = RugPhase.VACUUMING
	end_stroke()
	for tool in tool_nodes:
		tool.hide()
	for button in tool_buttons:
		button.disabled = true
	finish_button.hide()
	_cancel_transition()

func on_vacuum_finished() -> void:
	if not contract_finished or leaving_scene:
		return
	rug_phase = RugPhase.DEPARTING
	if not animate_rug_changes:
		next_rug.call_deferred()
		return
	transition_tween = create_tween()
	transition_tween.tween_method(_roll_departure,0.0,1.0,0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition_tween.tween_property($RugDisplay,"position:z",_offscreen_z(-1.0),0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	transition_tween.tween_callback(next_rug)

func _roll_departure(amount: float) -> void:
	rug_roll.set_roll(amount,1.0)

func _roll_arrival(amount: float) -> void:
	rug_roll.set_roll(amount,-1.0)

func _offscreen_z(direction: float) -> float:
	return direction * (camera.size * 0.5 + 2.3)

func _cancel_transition() -> void:
	if transition_tween != null and transition_tween.is_valid():
		transition_tween.kill()

func start_rug_arrival() -> void:
	_cancel_transition()
	rug_phase = RugPhase.ARRIVING
	soil.suspend_simulation(true)
	soil.set_reveal_progress(0.0)
	for tool in tool_nodes: tool.hide()
	finish_button.hide()
	update_contract_status()
	# Persist the new scatter before its presentation, including a Back tap
	# during arrival. Render-only growth never changes this saved dirt state.
	save_contract_progress()
	if not animate_rug_changes:
		$RugDisplay.position = Vector3.ZERO
		soil.set_reveal_progress(1.0)
		_tool_arrival_finished()
		return
	$RugDisplay.position = Vector3(0,0,_offscreen_z(1.0))
	_roll_arrival(1.0)
	transition_tween = create_tween()
	transition_tween.tween_property($RugDisplay,"position:z",0.0,0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	transition_tween.tween_method(_roll_arrival,1.0,0.0,0.68).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition_tween.tween_callback(_grow_arriving_dirt)
	transition_tween.tween_method(soil.set_reveal_progress,0.0,1.0,0.42)
	transition_tween.tween_callback(_bring_in_tool)

func _grow_arriving_dirt() -> void:
	rug_phase = RugPhase.GROWING

func _bring_in_tool() -> void:
	rug_phase = RugPhase.TOOL_ENTERING
	contact_point = brush_home.origin + brush_home.basis * TOOL_PIVOTS[0]
	contact_point.x = clampf(contact_point.x, -1.0 + soil.head_half.x, 1.0 - soil.head_half.x)
	place_selected_tool()
	last_brush_position = contact_point
	var tool := tool_nodes[selected_tool]
	var resting_position := tool.position
	tool.position.z = _offscreen_z(1.0)
	tool.show()
	transition_tween = create_tween()
	transition_tween.tween_property(tool,"position",resting_position,0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	transition_tween.tween_callback(_tool_arrival_finished)

func _tool_arrival_finished() -> void:
	if leaving_scene: return
	rug_phase = RugPhase.CLEANING
	soil.suspend_simulation(false)
	select_tool(soil.recommended_tool() if wet_recipe else 0)
	update_contract_status()

func save_contract_progress() -> bool:
	if not paid_contract or contract_finished:
		return true
	if is_instance_valid(soil) and is_instance_valid(shop_state) and shop_state.active_job_id == contract_job_id:
		var snapshot: Dictionary = soil.make_snapshot()
		if shop_state.save_job_snapshot(snapshot):
			contract_save_failed = false
			update_contract_status()
			return true
		# Keep the latest rug in memory so Back remains available even when the
		# device cannot write. A later save/re-entry in this process can retry it.
		shop_state.job_snapshot = snapshot.duplicate(true)
	contract_save_failed = true
	return false

func finish_contract() -> void:
	finish_rug()


func finish_rug() -> void:
	auto_finish_queued = false
	if rug_phase != RugPhase.CLEANING or leaving_scene or hud.upgrades_open() or soil == null or soil.completion_started or contract_finished or finish_requested:
		return
	if soil.overall_clearance() < CONTRACT_TARGET:
		return
	finish_requested = true
	end_stroke()
	if paid_contract:
		var completed_snapshot: Dictionary = soil.make_snapshot()
		# Reserve only the visual count-up before the transaction emits changed.
		# The ledger owns the payout; coin arrivals never grant actual currency.
		completed_reward = shop_state.reward_for_current_job(completed_snapshot)
		hud.reserve_reward(completed_reward)
		replacement_job_id = shop_state.complete_and_start_next_job(contract_job_id, completed_snapshot)
		if replacement_job_id.is_empty():
			hud.cancel_reserved_reward(completed_reward)
			completed_reward = 0
			_sync_wallet()
			shop_state.job_snapshot = completed_snapshot.duplicate(true)
			finish_requested = false
			contract_save_failed = true
			update_contract_status()
			return
	contract_finished = true
	contract_save_failed = false
	snapshot_timer.stop()
	update_contract_status()
	soil.start_vacuum(true)

func next_rug() -> void:
	if leaving_scene or next_job_pending or not soil.vacuum_complete or not contract_finished:
		return
	next_job_pending = true
	rug_phase = RugPhase.ARRIVING
	if paid_contract:
		hud.show_reward(completed_reward,shop_state.cash)
		completed_reward = 0
		contract_job_id = replacement_job_id
		replacement_job_id = ""
		shop_state.contract_mode = true
	else:
		selected_rug = (selected_rug+1)%rugs.size()
	# Refill the existing batch offscreen. No PackedScene instantiation, mesh
	# loading, or scene replacement occurs between rugs.
	soil.set_reveal_progress(0.0)
	soil.configure_rug(rugs[selected_rug])
	contract_finished = false
	finish_requested = false
	auto_finish_queued = false
	contract_save_failed = false
	next_job_pending = false
	start_rug_arrival()

func return_to_shop() -> void:
	if leaving_scene: return
	leaving_scene = true
	_cancel_transition()
	end_stroke()
	save_contract_progress()
	if shop_state != null:
		shop_state.contract_mode = false
	get_tree().change_scene_to_file(Routes.MAIN_MENU)

func _exit_tree() -> void:
	if is_instance_valid(shop_state) and shop_state.changed.is_connected(_sync_wallet):
		shop_state.changed.disconnect(_sync_wallet)
	if is_instance_valid(shop_state) and shop_state.ad_reward_granted.is_connected(_show_ad_reward):
		shop_state.ad_reward_granted.disconnect(_show_ad_reward)
	save_contract_progress()
	if original_scale_size != Vector2i.ZERO:
		var window := get_window()
		window.content_scale_size = original_scale_size
		window.content_scale_aspect = original_scale_aspect
		window.content_scale_mode = original_scale_mode
	if original_orientation >= 0:
		DisplayServer.screen_set_orientation(original_orientation)

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

func bind_ui() -> void:
	progress_card = hud.control("CleaningProgress") as PanelContainer
	state_label = hud.control("ProgressValue") as Label
	progress_bar = hud.control("ProgressBar") as ProgressBar
	progress_fill = progress_bar.get_theme_stylebox("fill") as StyleBoxFlat
	finish_button = hud.control("FinishJobButton") as Button
	finish_button.pressed.connect(finish_contract)
	var home_button := hud.control("HomeButton") as Button
	home_button.pressed.connect(back)
	var upgrade_button := hud.control("UpgradeButton") as Button
	var close_upgrades := hud.control("CloseUpgradesButton") as Button
	upgrade_button.pressed.connect(hud.open_upgrades)
	close_upgrades.pressed.connect(hud.close_upgrades)
	hud.upgrades_changed.connect(_on_upgrades_changed)
	hud.request_payout_upgrade.connect(_purchase_payout)
	hud.request_tool_upgrade.connect(_purchase_tool)
	hud.request_rewarded_ad.connect(_request_rewarded_ad)
	for button in [home_button, finish_button] + hud.action_buttons():
		if button in touch_buttons: continue
		Pop.bind(button)
		touch_buttons.append(button)
