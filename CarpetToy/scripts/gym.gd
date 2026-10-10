extends "res://scripts/workshop.gd"
## Free, repeatable brush and three-wash carpet exercises.
const GYM_HUD := preload("res://scenes/ui/gym_hud.tscn")
const GymCamera = preload("res://scripts/gym_camera.gd")
const PracticeCatalog = preload("res://scripts/rug_catalog.gd")
var camera_oblique := false
var practice_design_id := ""
var _design_deck: Array[String] = []
var _design_rng := RandomNumberGenerator.new()

func _ready() -> void:
	practice_only = true
	_design_rng.randomize()
	_draw_practice_design()
	# Swap the authored overlay explicitly: overriding an inherited instance
	# in the scene file leaves its original CanvasLayer orphaned in Godot.
	var old_hud := hud
	remove_child(old_hud)
	old_hud.free()
	hud = GYM_HUD.instantiate()
	hud.name = "GymUI"
	add_child(hud)
	super._ready()
	_ensure_wet_runtime()
	_sync_wet_runtime_state()
	set_hose_upgrade_level(hose_upgrade_level)
	set_squeegee_upgrade(squeegee_upgrade_level, Progression.WET_POWERS[squeegee_upgrade_level])

func _draw_practice_design() -> void:
	# Browse the same complete catalog as paid jobs, independently of the
	# player's unlocks. Finish one shuffled deck before repeating any design.
	if _design_deck.is_empty():
		_design_deck.assign(PracticeCatalog.IDS)
		for index in range(_design_deck.size() - 1, 0, -1):
			var other := _design_rng.randi_range(0, index)
			var id := _design_deck[index]
			_design_deck[index] = _design_deck[other]
			_design_deck[other] = id
		if _design_deck.size() > 1 and _design_deck.back() == practice_design_id:
			var id := _design_deck[0]
			_design_deck[0] = _design_deck[-1]
			_design_deck[-1] = id
	practice_design_id = _design_deck.pop_back()
	var definition: Resource = load(PracticeCatalog.definition_path(practice_design_id))
	# Modes share a design while keeping their resource instances local to this
	# practice session; the catalog resources and paid job are never modified.
	rugs.assign([definition.duplicate(), definition.duplicate()])

func bind_ui() -> void:
	super.bind_ui()
	rug_buttons.assign([hud.control("GymRug1"), hud.control("GymRug2")])
	tool_buttons.assign([hud.control("GymBrush"), hud.control("GymSqueegee"), hud.control("GymHose")])
	for index in rug_buttons.size():
		rug_buttons[index].pressed.connect(select_rug.bind(index))
	for index in tool_buttons.size():
		tool_buttons[index].pressed.connect(_on_practice_tool_pressed.bind(index))
	(hud.control("GymReset") as Button).pressed.connect(reset_rug)
	hud.hose_level_requested.connect(set_hose_upgrade_level)
	hud.squeegee_level_requested.connect(set_squeegee_upgrade_level)
	hud.camera_angle_requested.connect(set_camera_angle)
	hud.set_camera_angle(camera_oblique)

func set_camera_angle(oblique: bool) -> void:
	if leaving_scene: return
	end_stroke()
	camera_oblique = oblique
	hud.set_camera_angle(oblique)
	frame_carpet()

func set_hose_upgrade_level(level: int) -> void:
	if leaving_scene: return
	var next_level := clampi(level, 0, HoseProfile.MAX_LEVEL)
	# A preview change never resets the rug or charges/persists an upgrade.
	# Cancel outstanding parcels/soak so the previous profile cannot repaint it.
	end_stroke()
	_cancel_wet_runtime_effects()
	# Free practice preserves the authored hose profile's direct-flow ladder.
	# Paid contracts normalize direct strength to the global ledger hose_power.
	_configure_hose_upgrade(next_level, float(HoseProfile.SOAK_MULTIPLIERS[next_level]))
	_sync_wet_runtime_state()
	hud.set_hose_upgrade(hose_upgrade_level, HoseProfile.for_level(hose_upgrade_level))


func set_squeegee_upgrade_level(level: int) -> void:
	var next_level := clampi(level, 0, Progression.WET_POWERS.size() - 1)
	set_squeegee_upgrade(next_level, Progression.WET_POWERS[next_level])


func set_squeegee_upgrade(level: int, power: float) -> void:
	if leaving_scene: return
	end_stroke()
	_cancel_wet_runtime_effects()
	_configure_squeegee_upgrade(level, power)
	hud.set_squeegee_upgrade(squeegee_upgrade_level, squeegee_power)

func select_rug(index: int) -> void:
	if index < 0 or index >= rugs.size() or leaving_scene: return
	_dismiss_completion_reveal()
	_resumed_rug = false
	end_stroke()
	_cancel_wet_runtime_effects()
	squeegee_motion.reset()
	_cancel_transition()
	finish_requested = false
	auto_finish_queued = false
	contract_finished = false
	contract_save_failed = false
	next_job_pending = false
	selected_rug = index
	# Rug 2 reuses the production mask and extraction rules, but it starts after
	# dry cleaning and never touches the paid job snapshot.
	wet_recipe = index == 1
	soil.set_recipe(wet_recipe)
	$RugDisplay.position = Vector3.ZERO
	rug_roll.set_roll(0.0)
	soil.configure_rug(rugs[index])
	if wet_recipe:
		_ensure_wet_runtime()
		soil.prepare_water_stage()
	soil.batch_node.visible = index == 0
	soil.set_reveal_progress(1.0)
	soil.suspend_simulation(false)
	rug_phase = RugPhase.CLEANING
	hud.set_practice_design(PracticeCatalog.display_name(practice_design_id))
	hud.set_practice_rug(index)
	for i in rug_buttons.size():
		rug_buttons[i].set_pressed_no_signal(i == index)
	for button in tool_buttons: button.disabled = false
	contact_point = brush_home.origin + brush_home.basis * TOOL_PIVOTS[0]
	rug_initialized = true
	_sync_wet_runtime_state()
	select_tool(0 if index == 0 else 2)
	update_contract_status()
	frame_carpet()
	_capture_rug_before()

func select_tool(index: int) -> void:
	if selected_rug == 0 and index != 0: return
	if selected_rug == 1 and index not in [1, 2]: return
	if selected_rug == 1 and index == 1 and not soil.water_stage_complete(): return
	if selected_rug == 1 and index == 2 and soil.water_stage_complete(): return
	super.select_tool(index)
	hud.set_practice_tool(selected_tool)

func _on_practice_tool_pressed(index: int) -> void:
	if leaving_scene: return
	if selected_rug != 1:
		select_tool(index)
		return
	if index not in [1, 2]: return
	# These explicit Gym shortcuts always restart the exercise, including a
	# second tap on the equipped tool. Internal selection/auto-advance must not
	# refill or drain the carpet. Reset also discards water still in flight,
	# passive soak and extraction VFX while retaining the camera and hose tier.
	# Setup shortcuts refill/drain the current design. Only Reset draws a new
	# catalog carpet, so switching between wet tools keeps the same artwork.
	select_rug(selected_rug)
	if index == 1:
		# This shortcut fills every carpet pixel uniformly. Use the cached exact
		# silhouette instead of a 106k-pixel geometric paint on the input frame.
		soil.prepare_extraction_stage()
		_capture_rug_before()
		select_tool(1)
	update_contract_status()

func reset_rug() -> void:
	if leaving_scene: return
	_draw_practice_design()
	select_rug(selected_rug)

func update_contract_status() -> void:
	if selected_rug == 1 and is_instance_valid(water) and state_label != null:
		var wet_fraction: float = soil.water_clearance()
		var ready: bool = soil.water_stage_complete()
		var extraction_fraction: float = soil.extraction_clearance()
		var stage_fraction: float = soil.extraction_stage_progress() if ready else soil.water_stage_progress()
		progress_fraction = stage_fraction
		state_label.text = "%d%%" % floori(stage_fraction * 100.0 + 0.0001)
		var color := progress_color(stage_fraction)
		progress_bar.value = stage_fraction * 100.0
		progress_fill.bg_color = color
		progress_fill.shadow_color = Color(color, 0.42)
		dirty = not soil.all_washes_complete()
		water.set_emission_locked(ready)
		hud.set_wet_progress(wet_fraction, extraction_fraction, ready, soil.wash_cycle + 1, soil.WASH_CYCLES, soil.all_washes_complete())
		finish_button.hide()
		finish_button.disabled = true
		return
	super.update_contract_status()

func _tool_arrival_finished() -> void:
	if leaving_scene: return
	rug_phase = RugPhase.CLEANING
	soil.suspend_simulation(false)
	_capture_rug_before()
	select_tool(0 if selected_rug == 0 else soil.recommended_tool())
	update_contract_status()

func next_rug() -> void:
	if leaving_scene or next_job_pending or not soil.vacuum_complete or not contract_finished: return
	_dismiss_completion_reveal()
	_resumed_rug = false
	_cancel_wet_runtime_effects()
	# Completion repeats this exercise; changing exercises is always explicit.
	next_job_pending = true
	rug_phase = RugPhase.ARRIVING
	soil.set_reveal_progress(0.0)
	soil.configure_rug(rugs[selected_rug])
	if selected_rug == 1:
		soil.prepare_water_stage()
	contract_finished = false
	finish_requested = false
	auto_finish_queued = false
	contract_save_failed = false
	next_job_pending = false
	select_tool(0 if selected_rug == 0 else 2)
	_sync_wet_runtime_state()
	start_rug_arrival()

func frame_carpet() -> void:
	super.frame_carpet()
	if rug_phase == RugPhase.REVEAL: return
	if not is_instance_valid(hud) or not hud.has_method("rug_view_rect"): return
	var viewport_size := get_viewport().get_visible_rect().size
	var space: Rect2 = hud.rug_view_rect()
	if space.size.x <= 0.0 or space.size.y <= 0.0: return
	overhead = not camera_oblique
	GymCamera.frame(camera, viewport_size, space, camera_oblique)

func _show_ad_reward(_amount: float) -> void:
	pass
