extends "res://scripts/workshop.gd"
## Free, repeatable brush and wet-then-extract exercises.
const GYM_HUD := preload("res://scenes/ui/gym_hud.tscn")
const WaterJet = preload("res://scripts/water_jet.gd")
var water: Node3D
var nozzle_socket: Marker3D
var hose_upgrade_level := 0

func _ready() -> void:
	practice_only = true
	# Swap the authored overlay explicitly: overriding an inherited instance
	# in the scene file leaves its original CanvasLayer orphaned in Godot.
	var old_hud := hud
	remove_child(old_hud)
	old_hud.free()
	hud = GYM_HUD.instantiate()
	hud.name = "GymUI"
	add_child(hud)
	super._ready()
	nozzle_socket = Marker3D.new()
	nozzle_socket.name = "NozzleSocket"
	nozzle_socket.position = TOOL_PIVOTS[2]
	tool_nodes[2].add_child(nozzle_socket)
	water = WaterJet.new()
	water.name = "WaterJet"
	add_child(water)
	water.setup(soil.footprint)
	water.water_contact.connect(_on_water_contact)
	water.soak_contact.connect(_on_soak_contact)
	water.set_enabled(selected_rug == 1)
	set_hose_upgrade_level(hose_upgrade_level)

func begin_stroke(screen_position: Vector2, touch_input: bool) -> void:
	super.begin_stroke(screen_position, touch_input)
	_sync_water_emitter()

func move_brush_to_screen(screen_position: Vector2, touch_input: bool) -> void:
	super.move_brush_to_screen(screen_position, touch_input)
	_sync_water_emitter()

func end_stroke() -> void:
	super.end_stroke()
	_sync_water_emitter()

func apply_selected_tool_stroke(world_from: Vector3, world_to: Vector3, elapsed: float) -> void:
	if selected_rug == 1:
		# Coverage arrives at the stream's actual impact point after flight.
		if selected_tool == 1:
			soil.apply_squeegee_stroke(world_from, world_to, elapsed)
		return
	super.apply_selected_tool_stroke(world_from, world_to, elapsed)

func _sync_water_emitter() -> void:
	if not is_instance_valid(water): return
	var spraying: bool = selected_rug == 1 and selected_tool == 2 and not soil.water_stage_complete() and brush_dragging and rug_phase == RugPhase.CLEANING and not leaving_scene
	water.set_emitter(spraying, nozzle_socket.global_position, nozzle_socket.global_basis.z.normalized())

func _on_water_contact(world_position: Vector3, radius: float, strength: float) -> void:
	_apply_hose_water(world_position, radius, strength, soil.WATER_BLOB_EDGE_FRACTION)

func _on_soak_contact(world_position: Vector3, radius: float, strength: float) -> void:
	_apply_hose_water(world_position, radius, strength, 0.78)

func _apply_hose_water(world_position: Vector3, radius: float, strength: float, edge_fraction: float) -> void:
	if selected_rug != 1 or leaving_scene:
		return
	if not soil.apply_water_blob(world_position, radius, strength, edge_fraction):
		return
	var ready: bool = soil.water_stage_complete()
	water.set_emission_locked(ready)
	update_contract_status()
	# Water already in flight still lands after the player releases the hose.
	if ready and not brush_dragging and selected_tool == 2:
		_advance_wet_tool.call_deferred()

func place_selected_tool() -> void:
	super.place_selected_tool()
	if selected_rug == 1 and selected_tool == 2:
		tool_nodes[2].position.y += WaterJet.LAUNCH_HEIGHT - 0.14

func bind_ui() -> void:
	super.bind_ui()
	rug_buttons.assign([hud.control("GymRug1"), hud.control("GymRug2")])
	tool_buttons.assign([hud.control("GymBrush"), hud.control("GymSqueegee"), hud.control("GymHose")])
	for index in rug_buttons.size():
		rug_buttons[index].pressed.connect(select_rug.bind(index))
	for index in tool_buttons.size():
		tool_buttons[index].pressed.connect(select_tool.bind(index))
	(hud.control("GymReset") as Button).pressed.connect(reset_rug)
	hud.hose_level_requested.connect(set_hose_upgrade_level)

func set_hose_upgrade_level(level: int) -> void:
	if leaving_scene: return
	hose_upgrade_level = clampi(level, 0, WaterJet.HoseProfile.MAX_LEVEL)
	# A preview change never resets the rug or charges/persists an upgrade.
	# Cancel outstanding parcels/soak so the previous profile cannot repaint it.
	end_stroke()
	if is_instance_valid(water):
		water.reset()
		water.set_upgrade_level(hose_upgrade_level)
		water.set_emission_locked(soil.water_stage_complete())
	hud.set_hose_upgrade(hose_upgrade_level, WaterJet.HoseProfile.for_level(hose_upgrade_level))

func select_rug(index: int) -> void:
	if index < 0 or index >= rugs.size() or leaving_scene: return
	end_stroke()
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
		soil.prepare_water_stage()
	soil.batch_node.visible = index == 0
	soil.set_reveal_progress(1.0)
	soil.suspend_simulation(false)
	rug_phase = RugPhase.CLEANING
	hud.set_practice_rug(index)
	for i in rug_buttons.size():
		rug_buttons[i].set_pressed_no_signal(i == index)
	for button in tool_buttons: button.disabled = false
	contact_point = brush_home.origin + brush_home.basis * TOOL_PIVOTS[0]
	rug_initialized = true
	if is_instance_valid(water):
		water.set_enabled(index == 1)
	select_tool(0 if index == 0 else 2)
	update_contract_status()
	frame_carpet()

func select_tool(index: int) -> void:
	if selected_rug == 0 and index != 0: return
	if selected_rug == 1 and index not in [1, 2]: return
	if selected_rug == 1 and index == 1 and not soil.water_stage_complete(): return
	if selected_rug == 1 and index == 2 and soil.water_stage_complete(): return
	super.select_tool(index)
	hud.set_practice_tool(selected_tool)
	_sync_water_emitter()

func reset_rug() -> void:
	if leaving_scene: return
	super.reset_rug()
	if selected_rug == 1:
		soil.prepare_water_stage()
	soil.batch_node.visible = selected_rug == 0
	if is_instance_valid(water):
		water.reset()
		water.set_enabled(selected_rug == 1)
	select_tool(0 if selected_rug == 0 else 2)
	hud.set_practice_rug(selected_rug)
	hud.set_practice_tool(selected_tool)
	update_contract_status()

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
		dirty = not soil.extraction_stage_complete()
		water.set_emission_locked(ready)
		hud.set_wet_progress(wet_fraction, extraction_fraction, ready)
		finish_button.hide()
		finish_button.disabled = true
		return
	super.update_contract_status()

func _tool_arrival_finished() -> void:
	if leaving_scene: return
	rug_phase = RugPhase.CLEANING
	soil.suspend_simulation(false)
	select_tool(0 if selected_rug == 0 else soil.recommended_tool())
	update_contract_status()

func next_rug() -> void:
	if leaving_scene or next_job_pending or not soil.vacuum_complete or not contract_finished: return
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
	start_rug_arrival()

func frame_carpet() -> void:
	super.frame_carpet()
	if not is_instance_valid(hud) or not hud.has_method("rug_view_rect"): return
	var viewport_size := get_viewport().get_visible_rect().size
	var space: Rect2 = hud.rug_view_rect()
	if space.size.x <= 0.0 or space.size.y <= 0.0: return
	# Preserve room around all four edges for throwing brush debris onto tile.
	camera.size = maxf(4.2 * viewport_size.y / space.size.y, 3.0 * viewport_size.y / space.size.x)
	camera.position.z = (0.5 - space.get_center().y / viewport_size.y) * camera.size
	camera.position.x = (0.5 - space.get_center().x / viewport_size.x) * camera.size * viewport_size.x / viewport_size.y

func _show_ad_reward(_amount: int) -> void:
	pass
