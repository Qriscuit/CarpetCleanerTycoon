extends Node3D
## Mouse/touch brush control over the rug and surrounding tiled work area.
const Routes = preload("res://scripts/scene_routes.gd")
const Pop = preload("res://scripts/ui/button_pop.gd")
const ShopLedger = preload("res://scripts/shop_state.gd")
const Progression = preload("res://scripts/progression.gd")
const Money = preload("res://scripts/money.gd")
const RugCatalog = preload("res://scripts/rug_catalog.gd")
const WaterJet = preload("res://scripts/water_jet.gd")
const HoseProfile = preload("res://scripts/water_hose_profile.gd")
const SqueegeeMotion = preload("res://scripts/squeegee_motion.gd")
const WorkshopCamera = preload("res://scripts/gym_camera.gd")
const CleaningHUD = preload("res://scripts/cleaning_hud.gd")
const LevelCompanion = preload("res://scripts/level_companion.gd")
const SQUEEGEE_WATER_SCENE = preload("res://scenes/effects/squeegee_water.tscn")
@export var practice_only := false
@export var animate_rug_changes := true
@export_range(15.0, 45.0, 1.0) var room_view_pitch_from_top := 20.0
@export_range(-30.0, 30.0, 1.0) var room_view_yaw_degrees := 0.0
enum RugPhase { ARRIVING, GROWING, TOOL_ENTERING, CLEANING, VACUUMING, REVEAL, DEPARTING }
var rug_phase := RugPhase.ARRIVING
var rug_roll := preload("res://scripts/rug_roll.gd").new()
var transition_tween: Tween
var leaving_scene := false
var companion: Node3D
var companion_motion_reset := true
var companion_parked := false
# All nine authored brush tiers share the same handle endpoints. The rider's
# pelvis sits halfway up that shaft; cosmetic width upgrades never stretch him.
const COMPANION_SEAT := Vector3(0, 0.835, -0.345)
const COMPANION_BOUNDS := Rect2(-1.85, -2.30, 3.70, 4.60)
const COMPANION_REST_SPOT := Vector3(1.6, CARPET_PLANE_Y, 1.8)

const CARPET_PLANE_Y := 0.067
const BRUSH_IDLE_LIFT := 0.24
const BRUSH_LOWER_SECONDS := 0.09
const BRUSH_RAISE_SECONDS := 0.16
const BRUSH_X_LIMIT := 2.4
const BRUSH_Z_MIN := -2.58
const BRUSH_Z_MAX := 2.82
const TOUCH_CONTACT_OFFSET := Vector2(0.0, -72.0)
const TOOL_NAMES := ["Brush", "Squeegee", "Jet spray"]
const TOOL_PIVOTS := [Vector3(0, 0.007, 0), Vector3(0, 0, 0.025), Vector3(0, 0.24, 0.689)]
const TOOL_HEAD_HALVES := [Vector2(0.305, 0.11), Vector2(0.34, 0.075), Vector2(0.035, 0.035)]
const RUG_VIEW_CENTER := Vector3(0, 0.0335, 0)
const PROGRESS_COLORS := [Color("e76c62"), Color("dfb13d"), Color("63b66e"), Color("559bdd")]
# Practice keeps its authored recipes, independently of paid-job discovery.
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
var brush_visual_lift := BRUSH_IDLE_LIFT
var brush_lift_tween: Tween
var brush_home := Transform3D.IDENTITY
var last_brush_position := Vector3.ZERO
var state_label: Label
var progress_bar: ProgressBar
var progress_fill: StyleBoxFlat
var progress_fraction := 0.0
var active_touch := -1
var stroke_time := 0
var soil: Node
var application_focused := true
var carpet_video_pending := false
var completed_full_quote := 0.0
var selected_tool := 0
var tool_nodes: Array[Node3D] = []
var tool_buttons: Array[Button] = []
var touch_buttons: Array[Button] = []
var contact_point := Vector3.ZERO
var shop_state: Node
var game_audio: Node
var paid_contract := false
var contract_finished := false
var contract_save_failed := false
var contract_job_id := ""
var finish_button: Button
var wide_brush := false
var tool_width := 1.0
var wet_recipe := false
var water_only_recipe := false
var tool_visuals: RefCounted
var updating_progression := false
var switching_tool := false
var cached_progression: Dictionary = {}
var applied_visual_tier := -1
var applied_strength := -1.0
var dry_tool_power := 1.0
var hose_upgrade_level := 0
var hose_direct_power := 1.0
var hose_direct_scale := 1.0
var squeegee_upgrade_level := 0
var squeegee_power := 1.0
var water: Node3D
var nozzle_socket: Marker3D
var squeegee_water: Node3D
var squeegee_motion := SqueegeeMotion.new()
var cached_purchase_state := false
var snapshot_timer: Timer
var cleaning_reward_timer: Timer
var cleaning_reward_committing := false
var dry_earned_base := 0.0
var dry_surface_base := 0.0
var wet_earned_clearance := 0.0
var wet_pending_clearance := 0.0
var wet_reward_age := 0.0
const CLEANING_REWARD_INTERVAL := 0.20
const RUNOFF_REWARD_TAIL := 2.70
var rug_initialized := false
@onready var hud: CanvasLayer = $GymUI
var hud_touch := -1
var hud_button: Button
var hud_touch_origin := Vector2.ZERO
var hud_touch_canceled := false
var modal_mouse_down := false
var modal_mouse_origin := Vector2.ZERO
var modal_mouse_canceled := false
@onready var room: Node3D = get_node_or_null("UpgradeRoom")
var room_press_id := ""
var room_pointer := -2
var room_press_origin := Vector2.ZERO
var room_touch_canceled := false
var room_offer_anchor := Vector3.ZERO
var room_purchase_committing := false
var held_touches: Dictionary = {}
var touch_chord := false
var next_job_pending := false
var finish_requested := false
var auto_finish_queued := false
var replacement_job_id := ""
var completed_reward := 0.0
var completed_fraction := 0.0
var completed_full_restore := false
var completion_reveal: CanvasLayer
var completion_focus: CanvasLayer
var completion_zoom := 0.0
var completion_focus_tween: Tween
var completion_motion_paused := false
var completion_camera_from := Transform3D.IDENTITY
var completion_camera_from_size := 1.0
var completion_camera_from_zoom := 0.0
var completion_camera_viewport := Vector2.ZERO
var completion_camera_progress := 0.0
var completion_camera_returning := false
const COMPLETION_ZOOM_SECONDS := 0.42
const WINDOW_OPEN_SECONDS := 0.42
const DEPARTURE_LIFT := 0.13
var rug_comparison := preload("res://scripts/rug_comparison.gd").new()
var _resumed_rug := false
var original_scale_size := Vector2i.ZERO
var original_scale_aspect := 0
var original_scale_mode := 0
var original_orientation := -1
const TOUCH_DRAG_THRESHOLD := 14.0
const CONTRACT_TARGET := ShopLedger.MANUAL_COMPLETION_THRESHOLD
const AUTO_FINISH_TARGET := ShopLedger.PERFECT_COMPLETION_THRESHOLD

func _ready() -> void:
	game_audio = get_node_or_null("/root/GameAudio")
	if game_audio != null: game_audio.set_context("cleaning")
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
	frame_carpet()
	add_soft_accent_lights()
	brush_home = brush.transform
	tool_nodes = [brush, $StarterTools/Squeegee, $StarterTools/JetSpray]
	tool_visuals = preload("res://scripts/tool_progression_visual.gd").new()
	tool_visuals.setup(brush)
	contact_point = brush.position + brush.basis * TOOL_PIVOTS[0]
	last_brush_position = contact_point
	bind_ui()
	if is_instance_valid(room) and shop_state != null:
		room.set_levels(shop_state.room_upgrade_levels(), int(shop_state.active_store))
	completion_reveal = preload("res://scenes/ui/completion_reveal.tscn").instantiate()
	add_child(completion_reveal)
	completion_reveal.continued.connect(skip_completion_reveal)
	completion_reveal.comparison_changed.connect(_set_completion_comparison)
	completion_reveal.layout_changed.connect(_frame_completion_reveal)
	completion_focus = preload("res://scripts/completion_focus.gd").new()
	add_child(completion_focus)
	if shop_state != null:
		hud.initialize_wallet(shop_state.cash)
		shop_state.changed.connect(_sync_wallet)
		shop_state.ad_reward_granted.connect(_show_ad_reward)
		shop_state.carpet_ad_reward_granted.connect(_show_carpet_ad_reward)
	soil = preload("res://scripts/dirt_controller.gd").new()
	# Workshop owns the 75% manual and 99% automatic rules for both modes.
	soil.automatic_completion_enabled = false
	soil.head_half = Vector2(0.44, 0.11) if wide_brush else soil.HEAD_HALF
	add_child(soil)
	soil.progress_changed.connect(update_progress)
	soil.manual_debris_cleared.connect(_on_manual_debris_cleared)
	soil.surface_changed.connect(update_surface_progress)
	soil.cleaning_material_removed.connect(_queue_cleaning_earnings)
	soil.vacuum_started.connect(on_vacuum_started)
	soil.vacuum_finished.connect(on_vacuum_finished)
	soil.setup($RugDisplay)
	wet_recipe = paid_contract and bool(shop_state.progression_view().get("wet_unlocked", false))
	water_only_recipe = wet_recipe and int(shop_state.active_store) == Progression.WET_FIRST_STORE
	soil.set_recipe(wet_recipe, water_only_recipe)
	if wet_recipe:
		_ensure_wet_runtime()
	if animate_rug_changes:
		rug_roll.setup($RugDisplay/Dirty/CarpetMesh)
	select_rug(_active_paid_rug_index() if paid_contract else 0)
	_sync_progression()
	if paid_contract and not shop_state.job_snapshot.is_empty():
		# Normalize legacy Store 2 saves to its water-only recipe. Restoring clears
		# only the obsolete dry layer while retaining any saved wet/extracted masks.
		var restored_snapshot: Dictionary = shop_state.job_snapshot.duplicate(true)
		restored_snapshot["wet_recipe"] = wet_recipe
		restored_snapshot["skip_dry_stage"] = water_only_recipe
		_resumed_rug = soil.restore_snapshot(restored_snapshot)
		if _resumed_rug:
			# L8 reconstruction can slightly increase apparent cleanliness.
			# Preserve earned work and count only subsequent surface removal.
			dry_earned_base = float(restored_snapshot.get("dry_cleaning_clearance", restored_snapshot.get("surface_clearance", soil.surface_clearance())))
			dry_surface_base = soil.surface_clearance()
			wet_earned_clearance = clampf(float(restored_snapshot.get("earned_clearance", 0.0)), 0.0, 0.99)
			wet_pending_clearance = clampf(float(restored_snapshot.get("cleaning_pending_clearance", wet_earned_clearance)), 0.0, 0.99)
		applied_strength = -1.0
		_sync_progression()
	_sync_wet_runtime_state()
	snapshot_timer = Timer.new()
	snapshot_timer.one_shot = true
	snapshot_timer.wait_time = 0.5
	add_child(snapshot_timer)
	snapshot_timer.timeout.connect(save_contract_progress)
	cleaning_reward_timer = Timer.new()
	cleaning_reward_timer.one_shot = true
	cleaning_reward_timer.wait_time = CLEANING_REWARD_INTERVAL
	add_child(cleaning_reward_timer)
	cleaning_reward_timer.timeout.connect(_flush_cleaning_earnings)
	_setup_companion()
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

func _physics_process(delta: float) -> void:
	_sync_companion(delta)
	if not is_instance_valid(soil):
		return
	# A restored/canceled visual still owes the removed water, never a second
	# reward. Release its durable watermark after the bounded runoff tail.
	if paid_contract and wet_recipe and application_focused and not carpet_video_pending and rug_phase == RugPhase.CLEANING and not hud.upgrades_open() and not finish_requested and wet_pending_clearance > wet_earned_clearance:
		wet_reward_age += delta
		if wet_reward_age >= RUNOFF_REWARD_TAIL:
			_release_pending_runoff()

func _setup_companion() -> void:
	if not paid_contract or is_instance_valid(companion): return
	companion = LevelCompanion.new()
	companion.name = "LevelCompanion"
	add_child(companion)
	companion.setup(COMPANION_BOUNDS, CARPET_PLANE_Y, shop_state.appearance)
	shop_state.appearance_changed.connect(_on_companion_appearance)
	_sync_companion(0.0, true)

func _on_companion_appearance(appearance: Dictionary) -> void:
	if is_instance_valid(companion): companion.set_appearance(appearance)

func _sync_companion(delta := 0.0, reset_motion := false) -> void:
	if not is_instance_valid(companion) or not companion.is_inside_tree(): return
	if leaving_scene:
		companion.set_active(false)
		companion.hide()
		return
	var riding_phase := rug_phase == RugPhase.CLEANING and selected_tool == 0 and brush.visible and not finish_requested
	if not riding_phase:
		if not companion_parked:
			companion.park_at(COMPANION_REST_SPOT)
			companion_parked = true
		companion.set_active(false)
		companion.show()
		return
	var seat := Transform3D(brush.global_basis.orthonormalized(), brush.global_transform * COMPANION_SEAT)
	companion.update_tool_transform(seat, delta, reset_motion or companion_motion_reset or companion_parked)
	companion_motion_reset = false
	if companion_parked:
		companion.reset_to_tool()
		companion_parked = false
	companion.show()
	var enabled: bool = application_focused and not carpet_video_pending and not hud.upgrades_open() and not soil.simulation_suspended
	companion.set_active(enabled)

func _input(event: InputEvent) -> void:
	if not application_focused or carpet_video_pending: return
	if rug_phase == RugPhase.REVEAL:
		return # The reveal owns its gestures; the hidden cleaning HUD cannot act.
	if event.device == -1:
		return
	# A shop dismissal owns its entire gesture, including the release after
	# closing, so the same click cannot begin a stroke on the rug underneath.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and hud.upgrades_open():
		if event.pressed:
			modal_mouse_down = true
			modal_mouse_origin = event.position
			modal_mouse_canceled = false
			if not hud.modal_contains_point(event.position):
				end_stroke()
				get_viewport().set_input_as_handled()
				return
		elif modal_mouse_down:
			var started_outside: bool = not hud.modal_contains_point(modal_mouse_origin)
			var ended_outside: bool = not hud.modal_contains_point(event.position)
			modal_mouse_down = false
			if started_outside:
				if ended_outside and not modal_mouse_canceled: hud.close_upgrades()
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseMotion and modal_mouse_down:
		if event.position.distance_to(modal_mouse_origin) > TOUCH_DRAG_THRESHOLD: modal_mouse_canceled = true
		if hud.upgrades_open() and not hud.modal_contains_point(modal_mouse_origin):
			get_viewport().set_input_as_handled()
			return
	# Real touch is routed on release because mouse emulation is disabled. A
	# gesture belongs to one surface until every finger is up: a canceled swipe
	# cannot become a button tap or a new brush stroke behind the HUD.
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			held_touches[event.index] = true
			if held_touches.size() > 1:
				touch_chord = true
				room_touch_canceled = true
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
				var dismiss_modal: bool = hud.upgrades_open() and not event.canceled and not hud_touch_canceled and not touch_chord and not hud.modal_contains_point(hud_touch_origin) and not hud.modal_contains_point(event.position)
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
				elif dismiss_modal:
					hud.close_upgrades()
				return
			if held_touches.is_empty():
				touch_chord = false
	if event is InputEventScreenDrag:
		if event.index == hud_touch:
			if not hud_touch_canceled and event.position.distance_to(hud_touch_origin) > TOUCH_DRAG_THRESHOLD:
				hud_touch_canceled = true
				if is_instance_valid(hud_button):
					Pop.reset(hud_button)
					hud_button = null
			if not touch_chord and not is_instance_valid(hud_button):
				if hud.room_panel.visible and hud.room_panel.get_node("%Card").get_global_rect().has_point(hud_touch_origin):
					hud.room_panel.drag_contents(event.relative)
				else:
					hud.drag_tool_contents(hud_touch_origin, event.relative)
			get_viewport().set_input_as_handled()
			return
		if touch_chord:
			get_viewport().set_input_as_handled()
			return
	if _route_room_pointer(event):
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
	if not application_focused or carpet_video_pending or rug_phase != RugPhase.CLEANING or leaving_scene or soil.completion_started or brush_dragging or event.device == -1 or touch_chord or hud_touch != -1:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not hud.blocks_point(event.position):
			if _begin_room_press(event.position, -1): return
			begin_stroke(event.position, false)
	elif event is InputEventScreenTouch and event.pressed and not event.canceled:
		if not hud.blocks_point(event.position) and _begin_room_press(event.position, event.index): return
		if not hud.blocks_point(event.position) and not hud.blocks_point(event.position + TOUCH_CONTACT_OFFSET):
			active_touch = event.index
			begin_stroke(event.position, true)


func _begin_room_press(point: Vector2, pointer: int) -> bool:
	if not is_instance_valid(room) or not paid_contract or hud.upgrades_open(): return false
	var badge_id: String = hud.room_badge_at_point(point)
	# A finger sits below its brush head. Reserve the intended carpet contact
	# before picking the room underneath the finger, especially on wide aisles.
	if badge_id.is_empty() and pointer >= 0 and _touch_contact_is_on_carpet(point): return false
	var id: String = badge_id if not badge_id.is_empty() else room.pick_upgrade(camera, point)
	if id.is_empty(): return false
	end_stroke()
	room_press_id = id
	room_pointer = pointer
	room_press_origin = point
	room_touch_canceled = false
	get_viewport().set_input_as_handled()
	return true


func _touch_contact_is_on_carpet(point: Vector2) -> bool:
	var contact_screen := point + TOUCH_CONTACT_OFFSET
	var origin := camera.project_ray_origin(contact_screen)
	var direction := camera.project_ray_normal(contact_screen)
	if absf(direction.y) < 0.00001: return false
	var distance := (CARPET_PLANE_Y - origin.y) / direction.y
	if distance <= 0.0: return false
	var hit := origin + direction * distance
	var rug_half: Vector2 = soil.RUG_HALF + Vector2(0.06, 0.06)
	return absf(hit.x) <= rug_half.x and absf(hit.z) <= rug_half.y


func _route_room_pointer(event: InputEvent) -> bool:
	if room_press_id.is_empty(): return false
	var release := false
	var canceled := false
	var point := room_press_origin
	if event is InputEventMouseMotion and room_pointer == -1:
		point = event.position
	elif event is InputEventScreenDrag and event.index == room_pointer:
		point = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and room_pointer == -1:
		point = event.position
		release = not event.pressed
	elif event is InputEventScreenTouch and event.index == room_pointer:
		point = event.position
		release = not event.pressed or event.canceled
		canceled = event.canceled
	else:
		return false
	if point.distance_to(room_press_origin) > TOUCH_DRAG_THRESHOLD:
		room_touch_canceled = true
	if release:
		var id := room_press_id
		room_press_id = ""
		room_pointer = -2
		var badge_id: String = hud.room_badge_at_point(point)
		if not canceled and not room_touch_canceled and not touch_chord and (badge_id == id or room.pick_upgrade(camera, point) == id):
			open_room_upgrade(id, point)
	return true


func open_room_upgrade(id: String, screen_point: Vector2 = Vector2.INF) -> void:
	if carpet_video_pending or not paid_contract or not is_instance_valid(room) or rug_phase != RugPhase.CLEANING or leaving_scene or finish_requested or hud.upgrades_open(): return
	var view: Dictionary = shop_state.room_upgrade_view(id)
	if view.is_empty(): return
	end_stroke()
	room_offer_anchor = room.anchor_world_near(id, camera, screen_point)
	room.set_selected(id, room_offer_anchor)
	hud.open_room_upgrade(view, _can_purchase(), camera.unproject_position(room_offer_anchor))


func _refresh_room_offer_anchor() -> void:
	if is_instance_valid(hud) and hud.is_node_ready() and hud.room_panel.visible:
		hud.set_room_upgrade_anchor(camera.unproject_position(room_offer_anchor))


func _purchase_room(id: String) -> void:
	if room_purchase_committing or not _can_purchase() or not hud.room_panel.visible or hud.room_panel.selected_id != id: return
	var previous_levels: Dictionary = shop_state.room_upgrade_levels()
	room_purchase_committing = true
	var purchased: bool = shop_state.buy_room_upgrade(id)
	room_purchase_committing = false
	if purchased:
		room.play_upgrade(id, shop_state.room_upgrade_levels(), room_offer_anchor, previous_levels)
		room.set_selected(id, room_offer_anchor)
		update_contract_status()
	else:
		hud.room_panel.get_node("%Status").text = "Couldn't save. Coins unchanged."
		hud.room_panel.get_node("%Status").show()
		hud.room_panel.layout_in(hud._safe_rect())

func _on_room_upgrade_finished(_id: String) -> void:
	if is_instance_valid(hud) and is_instance_valid(hud.room_panel):
		if hud.room_panel.visible:
			hud.refresh_room_upgrade(shop_state.room_upgrade_view(hud.room_panel.selected_id), _can_purchase())

func begin_stroke(screen_position: Vector2, touch_input: bool) -> void:
	if not application_focused or carpet_video_pending or rug_phase != RugPhase.CLEANING or leaving_scene or hud.upgrades_open() or soil.completion_started or soil.simulation_suspended:
		return
	companion_motion_reset = true
	# Placement is not a sweep from the parked tool: only held motion rakes dirt.
	if selected_tool == 0:
		soil.begin_pass()
	move_brush_to_screen(screen_position, touch_input)
	brush_dragging = true
	_set_brush_engaged(true)
	stroke_time = Time.get_ticks_msec()
	set_brush_instruction(true)
	_sync_water_emitter()
	get_viewport().set_input_as_handled()

func end_stroke() -> void:
	if is_instance_valid(game_audio): game_audio.end_brush()
	var was_dragging := brush_dragging
	if soil != null:
		soil.end_pass()
	brush_dragging = false
	active_touch = -1
	_set_brush_engaged(false)
	_sync_water_emitter()
	if is_instance_valid(squeegee_water):
		squeegee_water.end_stroke()
	squeegee_motion.end_stroke()
	set_brush_instruction(false)
	if was_dragging and not finish_requested:
		save_contract_progress()
	if wet_recipe and not switching_tool and rug_phase == RugPhase.CLEANING and not finish_requested:
		_advance_wet_tool.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_node_ready():
		back()
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		application_focused = false
		_sync_companion(0.0, true)
		if is_instance_valid(hud): hud.set_wallet_paused(true)
		if is_instance_valid(cleaning_reward_timer): cleaning_reward_timer.paused = true
		modal_mouse_down = false
		modal_mouse_canceled = false

		if is_instance_valid(room): room.set_completion_paused(true)
		if rug_phase in [RugPhase.REVEAL, RugPhase.DEPARTING]:
			completion_motion_paused = true
			if completion_focus_tween != null and completion_focus_tween.is_valid(): completion_focus_tween.pause()
			if transition_tween != null and transition_tween.is_valid(): transition_tween.pause()
			if is_instance_valid(completion_focus): completion_focus.reset()
			if is_instance_valid(room): room.set_completion_paused(true)
		room_press_id = ""
		room_pointer = -2
		end_stroke()
		# Keep disappearance, payout presentation and the finishing vacuum on
		# the same paused clock while the player cannot see the wallet.
		if is_instance_valid(soil): soil.suspend_simulation(true)
		_cancel_wet_runtime_effects()
		if is_instance_valid(hud_button):
			Pop.reset(hud_button)
		hud_touch = -1
		hud_button = null
		held_touches.clear()
		touch_chord = false
		if is_node_ready() and is_instance_valid(soil) and is_instance_valid(hud):
			update_contract_status()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		application_focused = true
		companion_motion_reset = true
		if is_instance_valid(hud): hud.set_wallet_paused(carpet_video_pending)
		if is_instance_valid(cleaning_reward_timer): cleaning_reward_timer.paused = carpet_video_pending
		if is_instance_valid(soil): soil.suspend_simulation(carpet_video_pending or leaving_scene or hud.upgrades_open() or rug_phase not in [RugPhase.CLEANING, RugPhase.VACUUMING])
		if is_instance_valid(room): room.set_completion_paused(false)
		if completion_motion_paused:
			completion_motion_paused = false
			if completion_focus_tween != null and completion_focus_tween.is_valid(): completion_focus_tween.play()
			if transition_tween != null and transition_tween.is_valid(): transition_tween.play()
		if is_node_ready() and is_instance_valid(soil) and is_instance_valid(hud):
			update_contract_status()
			if wet_recipe: _advance_wet_tool.call_deferred()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		back()
		get_viewport().set_input_as_handled()

func back() -> void:
	if carpet_video_pending: return
	if hud.upgrades_open():
		hud.close_upgrades()
	else:
		return_to_shop()

func _sync_wallet() -> void:
	hud.sync_wallet(shop_state.cash)
	if is_instance_valid(room):
		if not room_purchase_committing:
			room.set_levels(shop_state.room_upgrade_levels(), int(shop_state.active_store))
		if hud.room_panel.visible:
			hud.refresh_room_upgrade(shop_state.room_upgrade_view(hud.room_panel.selected_id), _can_purchase())
	_sync_progression()

func _sync_progression() -> void:
	# Snapshot persistence runs once more during _exit_tree. At that point the
	# ledger still needs the mask, but UI/tool transforms are already detached.
	if updating_progression or shop_state == null or not paid_contract or leaving_scene or not is_inside_tree(): return
	updating_progression = true
	var view: Dictionary = shop_state.progression_view()
	view["carpet_full_reward"] = completed_full_quote if (contract_finished or finish_requested) and completed_full_quote > 0.0 else shop_state.current_job_full_reward()
	dry_tool_power = float(view.get("tool_power", 1.0))
	if wet_recipe:
		_ensure_wet_runtime()
		_configure_hose_upgrade(int(view.get("effective_hose_level", view.get("hose_level", 0))), float(view.get("hose_power", 1.0)))
		_configure_squeegee_upgrade(int(view.get("squeegee_level", 0)), float(view.get("squeegee_power", 1.0)))
	if not is_equal_approx(float(view.tool_width), tool_width): companion_motion_reset = true
	var wider: bool = float(view.tool_width) > tool_width
	tool_width = float(view.tool_width)
	wide_brush = tool_width > 1.0
	if soil != null:
		soil.head_half = Vector2(0.305 * tool_width, 0.11)
		if wider and not brush_dragging:
			contact_point.x = clampf(contact_point.x, -1.0 + soil.head_half.x, 1.0 - soil.head_half.x)
		_apply_selected_tool_strength()
		if int(view.global_tool_tier) != applied_visual_tier:
			tool_visuals.apply_tier(int(view.global_tool_tier), tool_width)
			applied_visual_tier = int(view.global_tool_tier)
		if rug_phase == RugPhase.CLEANING: place_selected_tool()
	var offer: Dictionary = shop_state.carpet_ad_offer()
	_sync_carpet_video_pause(bool(offer.get("requesting", false)) and str(offer.get("job_id", "")) == contract_job_id)
	var allowed := application_focused and not carpet_video_pending and rug_phase == RugPhase.CLEANING and not finish_requested and not leaving_scene
	if cached_progression != view or cached_purchase_state != allowed:
		hud.set_progression(view, allowed)
		cached_progression = view
		cached_purchase_state = allowed
	var room_available := {}
	if is_instance_valid(room):
		for id: String in room.CATEGORIES:
			room_available[id] = bool(shop_state.room_upgrade_view(id).get("can_upgrade", false))
	hud.set_room_upgrade_availability(room_available)
	var ad_state := CleaningHUD.CarpetAdState.HIDDEN
	if not contract_finished and not finish_requested and not leaving_scene:
		ad_state = CleaningHUD.CarpetAdState.ACTIVE if bool(offer.get("boosted", false)) else (CleaningHUD.CarpetAdState.REQUESTING if carpet_video_pending else (CleaningHUD.CarpetAdState.READY if bool(offer.get("available", false)) else CleaningHUD.CarpetAdState.LOCKED))
	hud.set_carpet_ad_offer(ad_state)
	updating_progression = false


func _sync_carpet_video_pause(requesting: bool) -> void:
	if carpet_video_pending == requesting: return
	carpet_video_pending = requesting
	_sync_companion(0.0, true)
	if requesting:
		end_stroke()

		_cancel_wet_runtime_effects()
	if is_instance_valid(soil): soil.suspend_simulation(requesting or not application_focused or leaving_scene or hud.upgrades_open() or rug_phase not in [RugPhase.CLEANING, RugPhase.VACUUMING])
	if is_instance_valid(hud): hud.set_wallet_paused(requesting or not application_focused)
	if is_instance_valid(cleaning_reward_timer): cleaning_reward_timer.paused = requesting or not application_focused
	update_contract_status()
	if not requesting and wet_recipe: _advance_wet_tool.call_deferred()

func _purchase_tool() -> void:
	if not _can_purchase(): return
	end_stroke()
	if shop_state.buy_tool_upgrade():
		_sync_progression()
		if not hud.upgrades_open(): select_tool(selected_tool)


func _purchase_hose() -> void:
	if not _can_purchase(): return
	end_stroke()
	_cancel_wet_runtime_effects()
	if shop_state.buy_hose_upgrade():
		_sync_progression()


func _purchase_squeegee() -> void:
	if not _can_purchase(): return
	end_stroke()
	_cancel_wet_runtime_effects()
	if shop_state.buy_squeegee_upgrade():
		_sync_progression()


func _can_purchase() -> bool:
	return application_focused and not carpet_video_pending and paid_contract and rug_phase == RugPhase.CLEANING and not finish_requested and not leaving_scene and hud.pending_reward == 0

func _request_rewarded_ad() -> void:
	if not _can_purchase() or not bool(shop_state.carpet_ad_offer().get("available", false)): return
	end_stroke()
	if not save_contract_progress(): return
	shop_state.request_carpet_reward_ad(contract_job_id)
	_sync_progression()

func _show_ad_reward(amount: float) -> void:
	if leaving_scene: return
	hud.reserve_reward(amount)
	hud.show_reward(amount, shop_state.cash)


func _show_carpet_ad_reward(amount: float) -> void:
	if leaving_scene or not is_inside_tree() or not paid_contract: return
	if amount > 0.0:
		hud.reserve_reward(amount)
		hud.show_cleaning_reward(amount, shop_state.cash)

func _advance_wet_tool() -> void:
	if not application_focused or carpet_video_pending or leaving_scene or not is_inside_tree() or not wet_recipe or brush_dragging or rug_phase != RugPhase.CLEANING or finish_requested or hud.upgrades_open() or soil.simulation_suspended: return
	if soil.advance_wash_cycle():
		# Retire old spray/ridges before the next round; no airborne parcel
		# from a prior hose session may pre-wet the following wash.
		_cancel_wet_runtime_effects()
		_sync_wet_runtime_state()
		update_contract_status()
		queue_snapshot_save()
	var next_tool: int = soil.recommended_tool()
	if next_tool != selected_tool: select_tool(next_tool)


func _ensure_wet_runtime() -> void:
	# Snapshot saving can refresh progression during _exit_tree. Preserve that
	# save, but never recreate effects after the scene has begun teardown.
	if leaving_scene or not is_inside_tree(): return
	if not is_instance_valid(nozzle_socket):
		nozzle_socket = Marker3D.new()
		nozzle_socket.name = "NozzleSocket"
		nozzle_socket.position = TOOL_PIVOTS[2]
		tool_nodes[2].add_child(nozzle_socket)
	if not is_instance_valid(water):
		water = WaterJet.new()
		water.name = "WaterJet"
		add_child(water)
		water.setup(soil.footprint)
		water.water_contact.connect(_on_water_contact)
		water.soak_contact.connect(_on_soak_contact)
	if not is_instance_valid(squeegee_water):
		squeegee_water = get_node_or_null("SqueegeeWater") as Node3D
		if not is_instance_valid(squeegee_water):
			squeegee_water = SQUEEGEE_WATER_SCENE.instantiate()
			squeegee_water.name = "SqueegeeWater"
			add_child(squeegee_water)
		if squeegee_water.impact == null:
			squeegee_water.setup(soil.footprint, soil.surface_pixels, soil.MASK_SIZE, soil)
		if not squeegee_water.runoff_retired.is_connected(_on_runoff_retired):
			squeegee_water.runoff_retired.connect(_on_runoff_retired)
	_configure_hose_upgrade(hose_upgrade_level, hose_direct_power)
	_configure_squeegee_upgrade(squeegee_upgrade_level, squeegee_power)
	_sync_wet_runtime_state()


func _configure_hose_upgrade(level: int, direct_power: float) -> void:
	var next_level := clampi(level, 0, HoseProfile.MAX_LEVEL)
	var next_power := direct_power if is_finite(direct_power) and direct_power > 0.0 else 1.0
	var level_changed := next_level != hose_upgrade_level
	hose_upgrade_level = next_level
	hose_direct_power = next_power
	# WaterJet's authored profile already includes a direct-flow multiplier.
	# Normalize it out so the ledger's strongest global hose_power is the one
	# authoritative direct-contact strength, without losing profile spread/soak.
	var profile_power := float(HoseProfile.for_level(hose_upgrade_level).soak_multiplier)
	hose_direct_scale = hose_direct_power / maxf(profile_power, 0.0001)
	if is_instance_valid(water) and (level_changed or int(water.upgrade_level) != hose_upgrade_level):
		water.set_upgrade_level(hose_upgrade_level)


func _configure_squeegee_upgrade(level: int, power: float) -> void:
	squeegee_upgrade_level = clampi(level, 0, Progression.WET_POWERS.size() - 1)
	squeegee_power = power if is_finite(power) and power > 0.0 else 1.0
	_apply_selected_tool_strength()


func _apply_selected_tool_strength() -> void:
	if not is_instance_valid(soil): return
	var strength := squeegee_power if wet_recipe and selected_tool == 1 else dry_tool_power
	if not is_equal_approx(strength, applied_strength):
		soil.set_tool_strength(strength)
		applied_strength = strength


func _sync_wet_runtime_state() -> void:
	if leaving_scene or not is_inside_tree(): return
	if not is_instance_valid(water) or not is_instance_valid(squeegee_water): return
	if bool(water.enabled) != wet_recipe:
		water.set_enabled(wet_recipe)
	if bool(squeegee_water.enabled) != wet_recipe:
		squeegee_water.set_enabled(wet_recipe)
	if wet_recipe and is_instance_valid(soil):
		water.set_emission_locked(soil.water_stage_complete())
		squeegee_water.set_wash_cycle(soil.wash_cycle)
	_sync_water_emitter()


func _sync_water_emitter() -> void:
	if leaving_scene or not is_inside_tree() or not is_instance_valid(water) or not is_instance_valid(nozzle_socket) or not nozzle_socket.is_inside_tree(): return
	var spraying: bool = wet_recipe and selected_tool == 2 and not bool(soil.water_stage_complete()) and brush_dragging and rug_phase == RugPhase.CLEANING and not leaving_scene and not bool(soil.simulation_suspended)
	water.set_emitter(spraying, nozzle_socket.global_position, nozzle_socket.global_basis.z.normalized())


func _on_water_contact(world_position: Vector3, radius: float, strength: float) -> void:
	_apply_hose_water(world_position, radius, strength * hose_direct_scale, soil.WATER_BLOB_EDGE_FRACTION)


func _on_soak_contact(_world_position: Vector3, _radius: float, _strength: float) -> void:
	# Capillary circles remain visual. Direct landed flow alone grows the
	# whole-carpet meter at the same rate at the center or an edge.
	pass


func _apply_hose_water(world_position: Vector3, radius: float, strength: float, edge_fraction: float) -> void:
	if not wet_recipe or leaving_scene or not is_instance_valid(soil): return
	if not soil.apply_water_blob(world_position, radius, strength, edge_fraction): return
	# Credit the equipped hose only when contact actually changes the wet mask.
	# This also catches stationary direct flow and passive soak contacts.
	if paid_contract:
		shop_state.note_current_tool_used(2)
	var ready: bool = soil.water_stage_complete()
	water.set_emission_locked(ready)
	update_contract_status()
	# The final in-flight parcel may complete the stage after pointer release.
	if ready and not brush_dragging and selected_tool == 2:
		_advance_wet_tool.call_deferred()


func _cancel_wet_runtime_effects() -> void:
	squeegee_motion.end_stroke()
	if is_instance_valid(squeegee_water):
		squeegee_water.reset()
	if is_instance_valid(water):
		water.reset()
		if wet_recipe and is_instance_valid(soil):
			water.set_emission_locked(soil.water_stage_complete())

func _on_upgrades_changed(open: bool) -> void:
	_sync_companion(0.0, true)
	if not open:
		modal_mouse_down = false
		modal_mouse_canceled = false
	end_stroke()
	if open:

		_cancel_wet_runtime_effects()
		soil.suspend_simulation(true)
		if transition_tween != null and transition_tween.is_valid():
			transition_tween.pause()
	else:
		if is_instance_valid(room): room.clear_selection()
		soil.suspend_simulation(carpet_video_pending or not application_focused or leaving_scene or rug_phase not in [RugPhase.CLEANING, RugPhase.VACUUMING])
		if application_focused and transition_tween != null and transition_tween.is_valid():
			transition_tween.play()
	update_contract_status()
	if not open and wet_recipe: _advance_wet_tool.call_deferred()

func move_brush_to_screen(screen_position: Vector2, touch_input: bool) -> void:
	if not application_focused or carpet_video_pending: return
	var stroke_origin := last_brush_position
	var stroke_started := stroke_time
	var accumulate_squeegee := brush_dragging and wet_recipe and selected_tool == 1
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
		# Motion has real carpet contact, even if it arrives during the short
		# lowering animation. Only the visual is lifted; the dirt plane never is.
		if selected_tool == 0 and brush_visual_lift > 0.0:
			_set_brush_engaged(true, true)
		var now := Time.get_ticks_msec()
		var dt := float(now - stroke_time) / 1000.0
		if last_brush_position.distance_squared_to(target) > 0.00001:
			apply_selected_tool_stroke(last_brush_position, target, dt)
		stroke_time = now
	contact_point = target
	place_selected_tool()
	last_brush_position = target
	if accumulate_squeegee:
		var movement := Vector3(last_brush_position.x - stroke_origin.x, 0.0, last_brush_position.z - stroke_origin.z)
		if movement.length_squared() <= 0.00001:
			# Preserve sub-pixel travel and elapsed time until the squeegee has a
			# meaningful direction; slow input must not repeatedly lose its motion.
			last_brush_position = stroke_origin
			stroke_time = stroke_started
	_sync_water_emitter()

func apply_selected_tool_stroke(world_from: Vector3, world_to: Vector3, elapsed: float) -> void:
	if not application_focused or carpet_video_pending or rug_phase != RugPhase.CLEANING or leaving_scene or finish_requested or hud.upgrades_open() or soil.simulation_suspended: return
	if selected_tool == 0:
		_apply_selected_tool_strength()
		var dry_before: float = soil.surface_coverage_total
		soil.stroke(world_from, world_to, elapsed)
		_update_brush_audio(world_from, world_to, elapsed, soil.surface_coverage_total < dry_before)
		if paid_contract and soil.surface_coverage_total < dry_before:
			shop_state.note_current_tool_used(0)
	elif wet_recipe and selected_tool == 2:
		# The ballistic hose owns contact timing. Wetness is written only by its
		# carpet-contact signals, never by the pointer's projected screen segment.
		return
	elif wet_recipe and selected_tool == 1:
		_apply_selected_tool_strength()
		var previous_heading: Vector3 = squeegee_motion.heading
		var was_tracking: bool = squeegee_motion.tracking
		squeegee_motion.update(world_to - world_from, elapsed)
		if not was_tracking:
			previous_heading = squeegee_motion.heading
		var before: float = soil.extraction_coverage_total
		soil.apply_squeegee_stroke(world_from, world_to, elapsed, squeegee_motion.heading, previous_heading)
		if paid_contract and soil.extraction_coverage_total > before:
			wet_pending_clearance = maxf(wet_pending_clearance, shop_state.cleaning_clearance_for_snapshot(soil.make_progress_snapshot()))
			wet_reward_age = 0.0
		if is_instance_valid(squeegee_water):
			var splash_contact := world_to
			splash_contact.y = soil.squeegee_surface_height(world_to, squeegee_motion.heading)
			squeegee_water.feed_stroke(world_from, splash_contact, elapsed, maxf(0.0, soil.extraction_coverage_total - before), squeegee_motion.heading, squeegee_motion.speed, wet_pending_clearance)

func _update_brush_audio(world_from: Vector3, world_to: Vector3, elapsed: float, removed: bool) -> void:
	if not is_instance_valid(game_audio): return
	if soil.completion_started or soil.simulation_suspended or soil.reveal_progress < 1.0 or soil.brush_surface_height(world_to, soil.head_half) <= 0.0:
		game_audio.end_brush()
		return
	var local: Vector3 = soil.rug_node.to_local(world_to)
	var pixel := Vector2i(((Vector2(local.x, local.z) + soil.RUG_HALF) / (soil.RUG_HALF * 2.0) * Vector2(soil.MASK_SIZE)).floor())
	pixel = pixel.clamp(Vector2i.ZERO, soil.MASK_SIZE - Vector2i.ONE)
	var amount: float = soil.coverage_values[pixel.y * soil.MASK_SIZE.x + pixel.x]
	game_audio.feed_brush(world_from.distance_to(world_to) / maxf(elapsed, 0.016), amount, removed)

func select_tool(index: int) -> void:
	if soil.completion_started or index < 0 or index >= tool_nodes.size():
		return
	if paid_contract and not wet_recipe and index != 0:
		return
	if paid_contract and wet_recipe and index != soil.recommended_tool():
		return
	switching_tool = true
	companion_motion_reset = true
	end_stroke()
	selected_tool = index
	_set_brush_engaged(false, true)
	for i in tool_nodes.size():
		tool_nodes[i].visible = i == selected_tool
		if i < tool_buttons.size():
			tool_buttons[i].set_pressed_no_signal(i == selected_tool)
	contact_point.y = soil.brush_surface_height(contact_point, current_head_half())
	place_selected_tool()
	last_brush_position = contact_point
	set_brush_instruction(false)
	if is_instance_valid(squeegee_water) and selected_tool != 1:
		squeegee_water.reset()
	_apply_selected_tool_strength()
	_sync_water_emitter()
	switching_tool = false
	_sync_progression()

func place_selected_tool() -> void:
	var tool := tool_nodes[selected_tool]
	var pose := Basis.IDENTITY.scaled(Vector3.ONE * 0.77)
	if selected_tool == 0:
		pose = Basis.IDENTITY.scaled(Vector3(0.77 * tool_width, 0.77, 0.77))
	elif wet_recipe and selected_tool == 1:
		var heading: Vector3 = squeegee_motion.heading
		pose = Basis(Vector3.UP, atan2(-heading.x, -heading.z)).scaled(Vector3.ONE * 0.77)
		contact_point.y = soil.squeegee_surface_height(contact_point, heading)
	var hover := brush_visual_lift if selected_tool == 0 else 0.0
	if selected_tool == 2:
		pose = Basis(Vector3.RIGHT, deg_to_rad(55.0)).scaled(Vector3.ONE * 1.12)
		hover = 0.14
	tool.transform = Transform3D(pose, contact_point + Vector3.UP * hover - pose * TOOL_PIVOTS[selected_tool])
	if wet_recipe and selected_tool == 2:
		tool.position.y += WaterJet.LAUNCH_HEIGHT - 0.14

func _set_brush_engaged(engaged: bool, immediate := false) -> void:
	if brush_lift_tween != null and brush_lift_tween.is_valid():
		brush_lift_tween.kill()
	var target := 0.0 if engaged else BRUSH_IDLE_LIFT
	if immediate or leaving_scene or not is_inside_tree() or rug_phase != RugPhase.CLEANING or selected_tool != 0:
		_set_brush_visual_lift(target)
		return
	if is_equal_approx(brush_visual_lift, target): return
	brush_lift_tween = create_tween()
	brush_lift_tween.tween_method(_set_brush_visual_lift, brush_visual_lift, target, BRUSH_LOWER_SECONDS if engaged else BRUSH_RAISE_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_brush_visual_lift(amount: float) -> void:
	brush_visual_lift = amount
	# Arrival owns the complete tool transform until cleaning begins. Updating
	# only height here also preserves tool tier scaling and the pointer anchor.
	if selected_tool == 0 and rug_phase == RugPhase.CLEANING and is_instance_valid(brush):
		brush.position.y = contact_point.y + amount - (brush.basis * TOOL_PIVOTS[0]).y

func current_head_half() -> Vector2:
	if wet_recipe and selected_tool == 1:
		return squeegee_motion.projected_half_extents(TOOL_HEAD_HALVES[1])
	return soil.head_half if selected_tool == 0 else TOOL_HEAD_HALVES[selected_tool]

func set_brush_instruction(_active: bool) -> void:
	# The cleaning window intentionally carries no instructional copy.
	pass

func reset_rug() -> void:
	if paid_contract:
		return
	_dismiss_completion_reveal()
	_resumed_rug = false
	end_stroke()
	_cancel_wet_runtime_effects()
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
	_capture_rug_before()

func select_rug(index: int) -> void:
	var choice_count: int = RugCatalog.IDS.size() if paid_contract else rugs.size()
	if index < 0 or index >= choice_count:
		return
	if paid_contract and (index != _active_paid_rug_index() or rug_initialized):
		return
	_dismiss_completion_reveal()
	end_stroke()
	_cancel_wet_runtime_effects()
	selected_rug = index
	soil.configure_rug(_selected_rug_definition())
	dry_earned_base = 0.0
	dry_surface_base = 0.0
	for i in rug_buttons.size():
		rug_buttons[i].set_pressed_no_signal(i == index)
	for button in tool_buttons:
		button.disabled = false
	var start_tool: int = soil.recommended_tool() if wet_recipe else 0
	if paid_contract:
		for i in tool_buttons.size():
			tool_buttons[i].disabled = i != start_tool
	contact_point = brush_home.origin + brush_home.basis * TOOL_PIVOTS[0]
	select_tool(start_tool)
	_sync_wet_runtime_state()
	rug_initialized = true

func _active_paid_rug_index() -> int:
	if shop_state != null:
		return maxi(0, RugCatalog.IDS.find(str(shop_state.active_rug_id)))
	return 0

func _selected_rug_definition() -> Resource:
	if paid_contract:
		return RugCatalog.load_definition(RugCatalog.IDS[selected_rug])
	return rugs[selected_rug]

func update_progress(_remaining: int, _total: int) -> void:
	update_contract_status()
	queue_snapshot_save()
	_queue_cleaning_earnings()

func _on_manual_debris_cleared() -> void:
	# Physical debris removal qualifies the current manual brush for mastery.
	if paid_contract and rug_phase == RugPhase.CLEANING and selected_tool == 0:
		shop_state.note_current_tool_used(0)


func update_surface_progress() -> void:
	update_contract_status()
	queue_snapshot_save()
	_queue_cleaning_earnings()

func _queue_cleaning_earnings() -> void:
	if not paid_contract or not is_instance_valid(cleaning_reward_timer) or rug_phase != RugPhase.CLEANING or contract_finished or finish_requested or leaving_scene: return
	if cleaning_reward_timer.is_stopped(): cleaning_reward_timer.start()

func _on_runoff_retired(_packet_id: int, progress_target: float) -> void:
	if not paid_contract or not wet_recipe or contract_finished or finish_requested or leaving_scene: return
	wet_earned_clearance = maxf(wet_earned_clearance, minf(progress_target, wet_pending_clearance))
	_queue_cleaning_earnings()

func _release_pending_runoff() -> void:
	wet_earned_clearance = maxf(wet_earned_clearance, wet_pending_clearance)
	_queue_cleaning_earnings()

func _payment_snapshot() -> Dictionary:
	var snapshot: Dictionary = soil.make_snapshot()
	var actual_removal: float = shop_state.cleaning_clearance_for_snapshot(snapshot)
	var eligible: float = actual_removal
	if wet_recipe:
		eligible = soil.removed_dry_clearance()
		var dry_share: float = 0.0 if water_only_recipe else eligible / float(1 + soil.WASH_CYCLES)
		eligible = maxf(dry_share, wet_earned_clearance)
		eligible = minf(eligible, actual_removal)
	else:
		eligible = minf(actual_removal, dry_earned_base + maxf(0.0, soil.surface_clearance() - dry_surface_base))
		snapshot["dry_cleaning_clearance"] = clampf(eligible, 0.0, 0.99)
	snapshot["earned_clearance"] = clampf(eligible, 0.0, 0.99)
	# Reloading an L8 mask can slightly lower its reconstructed fraction. Keep
	# the visual tail within this snapshot; the ledger retains paid high-water.
	snapshot["cleaning_pending_clearance"] = minf(wet_pending_clearance, maxf(actual_removal, 0.0))
	return snapshot

func _flush_cleaning_earnings(force: bool = false) -> bool:
	if not paid_contract or contract_finished or cleaning_reward_committing or not is_instance_valid(soil) or not is_instance_valid(shop_state) or shop_state.active_job_id != contract_job_id: return true
	if not force and (leaving_scene or finish_requested or carpet_video_pending or rug_phase != RugPhase.CLEANING or not application_focused): return true
	var snapshot := _payment_snapshot()
	var reward: float = shop_state.preview_cleaning_reward(contract_job_id, snapshot)
	if reward < 0.0: return false
	# Commit the masks and payment together; the HUD only animates saved coins.
	if reward > 0.0: hud.reserve_reward(reward)
	cleaning_reward_committing = true
	var credited: float = shop_state.record_cleaning_progress(contract_job_id, snapshot)
	cleaning_reward_committing = false
	if credited < 0.0:
		if reward > 0.0: hud.cancel_reserved_reward(reward)
		contract_save_failed = true
		if is_instance_valid(cleaning_reward_timer) and not leaving_scene: cleaning_reward_timer.start(0.75)
		return false
	if credited > 0.0: hud.show_cleaning_reward(credited, shop_state.cash)
	contract_save_failed = false
	return true


func queue_snapshot_save() -> void:
	if paid_contract and snapshot_timer != null and snapshot_timer.is_inside_tree() and not contract_finished:
		snapshot_timer.start(0.5)


func update_contract_status() -> void:
	if soil == null or state_label == null:
		return
	# Overall work drives payout eligibility; each wet action has its own 0–100% meter.
	var fraction: float = completed_fraction if contract_finished else soil.overall_clearance()
	progress_fraction = clampf(fraction, 0.0, 1.0)
	var final_stage_ready: bool = not wet_recipe or (soil.wash_cycle == soil.WASH_CYCLES - 1 and soil.water_stage_complete() and soil.extraction_clearance() >= CONTRACT_TARGET)
	var contract_ready := ShopLedger.completion_reached(progress_fraction, CONTRACT_TARGET) and final_stage_ready
	var auto_finish_ready: bool = soil.all_washes_complete() if wet_recipe else ShopLedger.completion_reached(progress_fraction, AUTO_FINISH_TARGET)
	var display_fraction := progress_fraction
	if wet_recipe and soil.recommended_tool() != 0 and not contract_finished:
		display_fraction = soil.extraction_stage_progress() if soil.water_stage_complete() else soil.water_stage_progress()
	var percent := floori(display_fraction * 100.0 + 0.0001)
	dirty = not contract_finished and not auto_finish_ready
	state_label.text = "%d%%" % percent
	if wet_recipe and soil.recommended_tool() != 0:
		hud.set_wet_stage(soil.wash_cycle + 1, soil.WASH_CYCLES, soil.water_stage_complete(), soil.all_washes_complete())
	else:
		hud.clear_wet_stage()
	var color := progress_color(display_fraction)
	progress_bar.value = display_fraction * 100.0
	progress_fill.bg_color = color
	progress_fill.shadow_color = Color(color, 0.42)
	finish_button.visible = application_focused and rug_phase == RugPhase.CLEANING and not carpet_video_pending and not hud.upgrades_open() and not contract_finished and not finish_requested and contract_ready and (not auto_finish_ready or contract_save_failed)
	finish_button.disabled = not finish_button.visible
	if wet_recipe and is_instance_valid(water):
		water.set_emission_locked(soil.water_stage_complete())
	finish_button.text = "Finish"
	finish_button.tooltip_text = "Finish this carpet"
	# Mask updates change cleanliness, not prices or owned equipment. Wallet /
	# purchase signals refresh those separately; only phase availability needs
	# checking here. Avoid rebuilding the ledger view and tool poses per stroke.
	var purchases_allowed := application_focused and not carpet_video_pending and rug_phase == RugPhase.CLEANING and not finish_requested and not leaving_scene
	if paid_contract and (cached_progression.is_empty() or cached_purchase_state != purchases_allowed):
		_sync_progression()
	if application_focused and rug_phase == RugPhase.CLEANING and not carpet_video_pending and not hud.upgrades_open() and auto_finish_ready and not contract_finished and not finish_requested and not auto_finish_queued and not contract_save_failed:
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
	if rug_phase in [RugPhase.REVEAL, RugPhase.DEPARTING]:
		_frame_completion_reveal()
		return
	_frame_workshop_camera()

func _frame_workshop_camera() -> void:
	if not is_instance_valid(camera) or not camera.is_inside_tree(): return
	overhead = false
	var viewport_size := get_viewport().get_visible_rect().size
	var space := Rect2(Vector2(16.0, 100.0), viewport_size - Vector2(32.0, 200.0))
	# The HUD owns the composition rectangle. Camera fitting and touch-space
	# reservations therefore share one layout at every size and orientation.
	if is_instance_valid(hud) and hud.is_node_ready():
		hud._layout()
		space = hud.workshop_view_rect()
	WorkshopCamera.frame_workshop(camera, viewport_size, space, _workshop_geometry_bounds(), room_view_pitch_from_top, room_view_yaw_degrees)
	_refresh_room_offer_anchor()
	if is_instance_valid(room) and is_instance_valid(hud) and hud.is_node_ready():
		var points := {}
		for id: String in room.CATEGORIES:
			points[id] = camera.unproject_position(room.badge_anchor_world(id))
		hud.set_room_upgrade_positions(points)
	if soil != null and rug_phase not in [RugPhase.REVEAL, RugPhase.DEPARTING]:
		soil.request_render()

func _workshop_geometry_bounds(open_window: bool = false) -> AABB:
	if is_instance_valid(room) and room.is_inside_tree() and room.has_method("geometry_fit_bounds_local"):
		var local_bounds: AABB = room.geometry_fit_bounds_local(open_window)
		return (room.global_transform * local_bounds).grow(0.03)
	return WorkshopCamera.DEPARTURE_CLEARANCE if open_window else WorkshopCamera.WORKSHOP_CLEARANCE

func on_vacuum_started() -> void:
	rug_phase = RugPhase.VACUUMING
	end_stroke()
	_cancel_wet_runtime_effects()
	for tool in tool_nodes:
		tool.hide()
	for button in tool_buttons:
		button.disabled = true
	finish_button.hide()
	_cancel_transition()

func on_vacuum_finished() -> void:
	if not contract_finished or leaving_scene:
		return
	if not animate_rug_changes:
		rug_phase = RugPhase.DEPARTING
		next_rug.call_deferred()
		return
	# Flush the final render request before freezing this actual completed rug.
	soil._process(0.0)
	soil.suspend_simulation(true)
	rug_phase = RugPhase.REVEAL
	hud.hide()
	held_touches.clear()
	touch_chord = false
	hud_touch = -1
	hud_button = null
	completion_zoom = 0.0
	completion_reveal.show_reveal(completed_full_restore, completed_fraction, rug_comparison.available, completed_reward, rug_comparison.label)
	_frame_completion_reveal()
	if is_instance_valid(room): room.start_completion_breeze()
	if completion_focus_tween != null and completion_focus_tween.is_valid(): completion_focus_tween.kill()
	completion_focus_tween = create_tween()
	completion_focus_tween.tween_method(_set_reveal_focus, 0.0, 1.0, COMPLETION_ZOOM_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	completion_focus_tween.tween_callback(completion_focus.reset)
	if completed_full_restore and is_instance_valid(game_audio):
		game_audio.play_completion()

func _capture_rug_before() -> void:
	if is_instance_valid(soil) and not soil.completion_started:
		rug_comparison.capture(soil, _resumed_rug)

func _set_completion_comparison(before: bool) -> void:
	if not is_instance_valid(soil): return
	if before and rug_phase != RugPhase.REVEAL: return
	if before:
		# A held comparison should always be sharp and still, even if it starts
		# during the short camera easing at the beginning of the reveal.
		if completion_focus_tween != null and completion_focus_tween.is_valid(): completion_focus_tween.kill()
		_set_completion_zoom(1.0)
		if is_instance_valid(completion_focus): completion_focus.reset()
	# Only GPU render state changes. Saved masks, dirt and rewards remain intact.
	rug_comparison.set_before(soil, before)

func _dismiss_completion_reveal() -> void:
	if completion_focus_tween != null and completion_focus_tween.is_valid(): completion_focus_tween.kill()
	completion_zoom = 0.0
	completion_motion_paused = false
	completion_camera_progress = 0.0
	completion_camera_returning = false
	if is_instance_valid(completion_focus): completion_focus.reset()
	if is_instance_valid(room): room.reset_completion_motion()
	_set_completion_comparison(false)
	if is_instance_valid(completion_reveal): completion_reveal.dismiss()
	if is_instance_valid(hud): hud.show()

func _frame_completion_reveal() -> void:
	if leaving_scene or not is_inside_tree() or rug_phase not in [RugPhase.REVEAL, RugPhase.DEPARTING] or not is_instance_valid(completion_reveal) or not completion_reveal.is_inside_tree(): return
	var viewport_size := get_viewport().get_visible_rect().size
	var space: Rect2 = completion_reveal.rug_view_rect()
	_frame_workshop_camera()
	var wide_transform := camera.global_transform
	var wide_size := camera.size
	if completion_reveal.is_landscape_layout():
		# A short screen has room for the full diorama beside Compare. Keep
		# its cleaning scale instead of cropping the architecture for a push-in.
		WorkshopCamera.frame_workshop(camera, viewport_size, space, _workshop_geometry_bounds(), room_view_pitch_from_top, room_view_yaw_degrees)
	else:
		WorkshopCamera.frame_reveal(camera, viewport_size, space, wide_size, room_view_pitch_from_top, room_view_yaw_degrees)
	var close_transform := camera.global_transform
	var close_size := camera.size
	if rug_phase == RugPhase.DEPARTING:
		WorkshopCamera.frame_departure(camera, viewport_size, hud._safe_rect().grow(-16.0), wide_size, _workshop_geometry_bounds(true), room_view_pitch_from_top, room_view_yaw_degrees)
		var departure_transform := camera.global_transform
		var departure_size := camera.size
		# Preserve the exact camera at a phase boundary, including internal
		# continuation halfway through the reveal. Refit if the screen rotates.
		if not viewport_size.is_equal_approx(completion_camera_viewport):
			completion_camera_from = departure_transform if completion_camera_returning else wide_transform.interpolate_with(close_transform, completion_camera_from_zoom)
			completion_camera_from_size = departure_size if completion_camera_returning else lerpf(wide_size, close_size, completion_camera_from_zoom)
			completion_camera_viewport = viewport_size
		var target_transform := wide_transform if completion_camera_returning else departure_transform
		var target_size := wide_size if completion_camera_returning else departure_size
		camera.global_transform = completion_camera_from.interpolate_with(target_transform, completion_camera_progress)
		camera.size = lerpf(completion_camera_from_size, target_size, completion_camera_progress)
		return
	camera.global_transform = wide_transform.interpolate_with(close_transform, completion_zoom)
	camera.size = lerpf(wide_size, close_size, completion_zoom)

func _set_completion_zoom(amount: float) -> void:
	completion_zoom = clampf(amount, 0.0, 1.0)
	_frame_completion_reveal()

func _set_reveal_focus(amount: float) -> void:
	_set_completion_zoom(amount)
	# Blur only the moving frames. The complete rug remains sharp for the
	# appreciation/compare beat, and the HUD is on a higher canvas layer.
	completion_focus.set_blur_amount(sin(clampf(amount, 0.0, 1.0) * PI) * 0.55)

func _set_departure_focus(amount: float) -> void:
	completion_camera_progress = clampf(amount, 0.0, 1.0)
	completion_zoom = lerpf(completion_camera_from_zoom, 0.0, completion_camera_progress)
	_frame_completion_reveal()
	completion_focus.set_blur_amount(sin(clampf(amount, 0.0, 1.0) * PI))

func _capture_completion_camera(returning: bool) -> void:
	completion_camera_from = camera.global_transform
	completion_camera_from_size = camera.size
	completion_camera_from_zoom = completion_zoom
	completion_camera_viewport = get_viewport().get_visible_rect().size
	completion_camera_progress = 0.0
	completion_camera_returning = returning

func _return_completion_camera() -> void:
	_capture_completion_camera(true)

func skip_completion_reveal() -> void:
	if leaving_scene or rug_phase != RugPhase.REVEAL: return
	_set_completion_comparison(false)
	completion_reveal.dismiss()
	_capture_completion_camera(false)
	rug_phase = RugPhase.DEPARTING
	if completion_focus_tween != null and completion_focus_tween.is_valid(): completion_focus_tween.kill()
	_cancel_transition()
	transition_tween = create_tween()
	# Return to the whole room before opening its exit; never hide the opening
	# or the roll behind a lingering fullscreen blur.
	transition_tween.tween_method(_set_departure_focus, 0.0, 1.0, COMPLETION_ZOOM_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition_tween.tween_callback(completion_focus.reset)
	if is_instance_valid(room):
		transition_tween.tween_method(room.set_window_open_amount, room.window_open_amount, 1.0, WINDOW_OPEN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition_tween.tween_method(_roll_departure,0.0,1.0,0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition_tween.tween_property($RugDisplay,"position:z",_offscreen_z(-1.0),0.46).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Settle back into the working view while the completed rug is offscreen.
	# The next rug then rolls into a stationary room instead of snapping cameras
	# when start_rug_arrival reapplies the normal cleaning frame.
	transition_tween.tween_callback(_return_completion_camera)
	transition_tween.tween_method(_set_departure_focus, 0.0, 1.0, COMPLETION_ZOOM_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if is_instance_valid(room):
		transition_tween.parallel().tween_method(room.set_window_open_amount, 1.0, 0.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition_tween.tween_callback(completion_focus.reset)
	transition_tween.tween_callback(next_rug)

func _roll_departure(amount: float) -> void:
	rug_roll.set_roll(amount,1.0)
	$RugDisplay.position.y = amount * DEPARTURE_LIFT

func _roll_arrival(amount: float) -> void:
	rug_roll.set_roll(amount,-1.0)

func _offscreen_z(direction: float) -> float:
	return direction * (camera.size * 0.5 + 2.3)

func _cancel_transition() -> void:
	if transition_tween != null and transition_tween.is_valid():
		transition_tween.kill()

func start_rug_arrival() -> void:
	_dismiss_completion_reveal()
	_cancel_transition()
	_cancel_wet_runtime_effects()
	rug_phase = RugPhase.ARRIVING
	companion_motion_reset = true
	_sync_companion(0.0, true)
	_set_brush_engaged(false, true)
	frame_carpet()
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
	soil.suspend_simulation(carpet_video_pending or not application_focused or hud.upgrades_open())
	_capture_rug_before()
	select_tool(soil.recommended_tool() if wet_recipe else 0)
	_sync_companion(0.0, true)
	if is_instance_valid(companion): companion.reset_to_tool()
	update_contract_status()
	# A saved last blade pass may precede its deferred round transition.
	# Resume that finished round without requiring a redundant press/release.
	if wet_recipe:
		_advance_wet_tool.call_deferred()

func save_contract_progress() -> bool:
	if not paid_contract or contract_finished:
		if is_instance_valid(snapshot_timer): snapshot_timer.stop()
		return true
	if is_instance_valid(soil) and is_instance_valid(shop_state) and shop_state.active_job_id == contract_job_id:
		var snapshot: Dictionary = _payment_snapshot()
		if _flush_cleaning_earnings(true):
			# A successful release/Back checkpoint supersedes the pending timer.
			# Keep that existing retry opportunity if the immediate write fails.
			if is_instance_valid(snapshot_timer): snapshot_timer.stop()
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
	if not application_focused or rug_phase != RugPhase.CLEANING or carpet_video_pending or leaving_scene or hud.upgrades_open() or soil == null or soil.completion_started or contract_finished or finish_requested:
		return
	if not ShopLedger.completion_reached(soil.overall_clearance(), CONTRACT_TARGET):
		return
	if wet_recipe and (soil.wash_cycle != soil.WASH_CYCLES - 1 or not soil.water_stage_complete() or soil.extraction_clearance() < CONTRACT_TARGET):
		return
	finish_requested = true
	_sync_companion(0.0, true)
	completed_full_quote = shop_state.current_job_full_reward() if paid_contract else 0.0
	completed_fraction = soil.overall_clearance()
	completed_full_restore = soil.all_washes_complete() if wet_recipe else ShopLedger.completion_reached(completed_fraction, AUTO_FINISH_TARGET)
	end_stroke()
	if paid_contract:
		var completed_snapshot: Dictionary = _payment_snapshot()
		# Finishing takes the remaining material offscreen. Early finish settles
		# only removal work; the restoration half is added solely at 99%.
		completed_snapshot["earned_clearance"] = shop_state.cleaning_clearance_for_snapshot(completed_snapshot)
		# Reserve only the visual count-up before the transaction emits changed.
		# The ledger owns the payout; coin arrivals never grant actual currency.
		completed_reward = shop_state.reward_for_current_job(completed_snapshot)
		hud.reserve_reward(completed_reward)
		replacement_job_id = shop_state.complete_and_start_next_job(contract_job_id, completed_snapshot)
		if replacement_job_id.is_empty():
			hud.cancel_reserved_reward(completed_reward)
			completed_reward = 0.0
			completed_full_quote = 0.0
			_sync_wallet()
			shop_state.job_snapshot = completed_snapshot.duplicate(true)
			finish_requested = false
			contract_save_failed = true
			update_contract_status()
			return
		hud.show_cleaning_reward(completed_reward, shop_state.cash)
		completed_reward = 0.0
	contract_finished = true
	contract_save_failed = false
	snapshot_timer.stop()
	if is_instance_valid(cleaning_reward_timer): cleaning_reward_timer.stop()
	update_contract_status()
	soil.start_vacuum(true, completed_full_restore)

func next_rug() -> void:
	if leaving_scene or next_job_pending or not soil.vacuum_complete or not contract_finished:
		return
	next_job_pending = true
	completed_full_quote = 0.0
	_dismiss_completion_reveal()
	_resumed_rug = false
	rug_phase = RugPhase.ARRIVING
	if paid_contract:
		hud.show_reward(completed_reward,shop_state.cash)
		completed_reward = 0.0
		contract_job_id = replacement_job_id
		replacement_job_id = ""
		shop_state.contract_mode = true
		selected_rug = _active_paid_rug_index()
	else:
		selected_rug = (selected_rug+1)%rugs.size()
	# Refill the existing batch offscreen. No PackedScene instantiation, mesh
	# loading, or scene replacement occurs between rugs.
	soil.set_reveal_progress(0.0)
	soil.configure_rug(_selected_rug_definition())
	dry_earned_base = 0.0
	dry_surface_base = 0.0
	wet_earned_clearance = 0.0
	wet_pending_clearance = 0.0
	wet_reward_age = 0.0
	contract_finished = false
	finish_requested = false
	auto_finish_queued = false
	contract_save_failed = false
	next_job_pending = false
	_cancel_wet_runtime_effects()
	select_tool(soil.recommended_tool() if wet_recipe else 0)
	_sync_wet_runtime_state()
	start_rug_arrival()

func return_to_shop() -> void:
	if leaving_scene: return
	# Leaving removes every remaining runoff visual from the screen. Preserve
	# its funded work in the same checkpoint as the carpet and wallet.
	if paid_contract and wet_recipe: _release_pending_runoff()
	_dismiss_completion_reveal()
	leaving_scene = true
	_sync_companion(0.0, true)
	_cancel_transition()
	end_stroke()
	_cancel_wet_runtime_effects()
	save_contract_progress()
	if shop_state != null:
		shop_state.contract_mode = false
	get_tree().change_scene_to_file(Routes.MAIN_MENU)

func _exit_tree() -> void:
	if brush_lift_tween != null and brush_lift_tween.is_valid():
		brush_lift_tween.kill()
	_dismiss_completion_reveal()
	if is_instance_valid(game_audio): game_audio.set_context("off")
	leaving_scene = true
	_cancel_wet_runtime_effects()
	if is_instance_valid(shop_state) and shop_state.appearance_changed.is_connected(_on_companion_appearance):
		shop_state.appearance_changed.disconnect(_on_companion_appearance)
	if is_instance_valid(shop_state) and shop_state.changed.is_connected(_sync_wallet):
		shop_state.changed.disconnect(_sync_wallet)
	if is_instance_valid(shop_state) and shop_state.ad_reward_granted.is_connected(_show_ad_reward):
		shop_state.ad_reward_granted.disconnect(_show_ad_reward)
	if is_instance_valid(shop_state) and shop_state.carpet_ad_reward_granted.is_connected(_show_carpet_ad_reward):
		shop_state.carpet_ad_reward_granted.disconnect(_show_carpet_ad_reward)
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
	hud.composition_changed.connect(frame_carpet, CONNECT_DEFERRED)
	hud.request_room_upgrade.connect(_purchase_room)
	if is_instance_valid(room): room.upgrade_finished.connect(_on_room_upgrade_finished)
	hud.reward_finished.connect(_sync_wallet)
	hud.request_tool_upgrade.connect(_purchase_tool)
	if hud.has_signal("request_hose_upgrade"):
		hud.request_hose_upgrade.connect(_purchase_hose)
	if hud.has_signal("request_squeegee_upgrade"):
		hud.request_squeegee_upgrade.connect(_purchase_squeegee)
	hud.request_rewarded_ad.connect(_request_rewarded_ad)
	for button in [home_button, finish_button] + hud.action_buttons():
		if button in touch_buttons: continue
		Pop.bind(button)
		touch_buttons.append(button)
