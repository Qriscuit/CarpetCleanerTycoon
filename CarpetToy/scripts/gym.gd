extends "res://scripts/workshop.gd"
## Free, repeatable brush and water-blob exercises.
const GYM_HUD := preload("res://scenes/ui/gym_hud.tscn")
const WaterBlobs = preload("res://scripts/water_blobs.gd")
const HOSE_LANDING_OFFSET := Vector3(0.0, 0.0, 0.20)
var water: Node3D

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
	water = WaterBlobs.new()
	water.name = "WaterBlobs"
	add_child(water)
	water.setup(soil.surface_materials, soil.footprint)
	water.set_enabled(selected_rug == 1)

func begin_stroke(screen_position: Vector2, touch_input: bool) -> void:
	super.begin_stroke(screen_position, touch_input)
	_sync_water_emitter()

func move_brush_to_screen(screen_position: Vector2, touch_input: bool) -> void:
	super.move_brush_to_screen(screen_position, touch_input)
	_sync_water_emitter()

func end_stroke() -> void:
	super.end_stroke()
	_sync_water_emitter()

func _sync_water_emitter() -> void:
	if not is_instance_valid(water): return
	var spraying := selected_rug == 1 and selected_tool == 2 and brush_dragging and rug_phase == RugPhase.CLEANING and not leaving_scene
	var nozzle: Vector3 = tool_nodes[2].to_global(TOOL_PIVOTS[2])
	# A short forward arc makes the falling drops visible from the overhead
	# camera instead of hiding the entire stream under the hose model.
	water.set_emitter(spraying, nozzle, contact_point + HOSE_LANDING_OFFSET)

func place_selected_tool() -> void:
	super.place_selected_tool()
	if selected_rug == 1 and selected_tool == 2:
		# Leave a readable gap for the short stream of falling droplets.
		tool_nodes[2].position.y += WaterBlobs.LAUNCH_HEIGHT - 0.14

func bind_ui() -> void:
	super.bind_ui()
	rug_buttons.assign([hud.control("GymRug1"), hud.control("GymRug2")])
	tool_buttons.assign([hud.control("GymBrush"), hud.control("GymSqueegee"), hud.control("GymHose")])
	for index in rug_buttons.size():
		rug_buttons[index].pressed.connect(select_rug.bind(index))
	for index in tool_buttons.size():
		tool_buttons[index].pressed.connect(select_tool.bind(index))
	(hud.control("GymReset") as Button).pressed.connect(reset_rug)

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
	# Visual blobs remain separate from the paid brush -> water -> extraction
	# recipe. Squeegee displacement and dirt removal come in a later pass.
	wet_recipe = false
	soil.set_recipe(false)
	$RugDisplay.position = Vector3.ZERO
	rug_roll.set_roll(0.0)
	soil.configure_rug(rugs[index])
	soil.batch_node.visible = index == 0
	soil.set_reveal_progress(1.0)
	soil.suspend_simulation(false)
	rug_phase = RugPhase.CLEANING
	hud.set_practice_rug(index)
	for i in rug_buttons.size():
		rug_buttons[i].set_pressed_no_signal(i == index)
	for button in tool_buttons: button.disabled = false
	contact_point = brush_home.origin + brush_home.basis * TOOL_PIVOTS[0]
	select_tool(0 if index == 0 else 2)
	rug_initialized = true
	if is_instance_valid(water): water.set_enabled(index == 1)
	update_contract_status()
	frame_carpet()

func select_tool(index: int) -> void:
	if selected_rug == 0 and index != 0: return
	if selected_rug == 1 and index not in [1, 2]: return
	super.select_tool(index)
	hud.set_practice_tool(selected_tool)

func reset_rug() -> void:
	if leaving_scene: return
	super.reset_rug()
	soil.batch_node.visible = selected_rug == 0
	hud.set_practice_rug(selected_rug)
	hud.set_practice_tool(selected_tool)
	if is_instance_valid(water): water.reset()

func update_contract_status() -> void:
	super.update_contract_status()
	if selected_rug == 1 and is_instance_valid(finish_button):
		finish_button.hide()
		finish_button.disabled = true

func _tool_arrival_finished() -> void:
	if leaving_scene: return
	rug_phase = RugPhase.CLEANING
	soil.suspend_simulation(false)
	select_tool(0 if selected_rug == 0 else 2)
	update_contract_status()

func next_rug() -> void:
	if leaving_scene or next_job_pending or not soil.vacuum_complete or not contract_finished: return
	# Completion repeats this exercise; changing exercises is always explicit.
	next_job_pending = true
	rug_phase = RugPhase.ARRIVING
	soil.set_reveal_progress(0.0)
	soil.configure_rug(rugs[selected_rug])
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
