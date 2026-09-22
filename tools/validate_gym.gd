extends SceneTree
## Godot --path CarpetToy --script ../tools/validate_gym.gd -- --shop-test
## Use the renderer for accurate camera, window scaling and MultiMesh checks.
const Routes = preload("res://scripts/scene_routes.gd")
var checks := 0
var failures := 0
var game: Node

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to keep player saves isolated")
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	await process_frame
	await process_frame

func wait_ready() -> void:
	for tick in 300:
		if game.rug_phase == game.RugPhase.CLEANING: return
		await create_timer(0.02).timeout
	check(false, "Gym rug becomes ready within six seconds")

func mouse_at(point: Vector2) -> void:
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		root.push_input(event, true)

func mouse_click(button: Button) -> void:
	mouse_at(button.get_global_rect().get_center())

func touch_at(point: Vector2, canceled := false) -> void:
	for down: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 1
		event.position = point
		event.pressed = down
		event.canceled = canceled and not down
		root.push_input(event, true)

func tap(button: Button, canceled := false) -> void:
	touch_at(button.get_global_rect().get_center(), canceled)

func settle_dirt() -> void:
	for tick in 300:
		if not game.soil.is_physics_processing(): break
		game.soil._physics_process(1.0 / 60.0)

func stroke(from: Vector3, to: Vector3) -> void:
	game.begin_stroke(game.camera.unproject_position(from), false)
	game.move_brush_to_screen(game.camera.unproject_position(to), false)
	game.end_stroke()

func saturate_wet_rug() -> void:
	# One oversized test blob exercises the public production paint path while
	# deterministically covering every valid footprint pixel.
	check(game.soil.apply_water_blob(Vector3(0.0, 0.067, 0.0), 5.0), "A deterministic water blob saturates the practice rug")
	game.soil._process(0.0)
	game.update_contract_status()

func check_tool(index: int) -> void:
	check(game.selected_tool == index, "Selected gym tool is %d" % index)
	for other in game.tool_nodes.size():
		check(game.tool_nodes[other].visible == (other == index), "Exactly the selected tool model is visible (%d, %d)" % [index, other])
		check(game.tool_buttons[other].button_pressed == (other == index), "Tool picker highlights the equipped tool (%d, %d)" % [index, other])

func check_no_stroke(message: String) -> void:
	check(not game.brush_dragging and game.active_touch == -1 and not game.soil.pass_active, message)

func capture_and_check_layout(label: String) -> void:
	await settle()
	var safe: Rect2 = game.hud._safe_rect()
	var visible_controls: Array[Control] = []
	for name: String in ["HomeButton", "CleaningProgress", "FinishJobButton", "GymRug1", "GymRug2", "GymBrush", "GymHose", "GymSqueegee", "GymReset"]:
		var control: Control = game.hud.control(name)
		if control.is_visible_in_tree():
			check(safe.grow(1.0).encloses(control.get_global_rect()), "%s fits the safe area in %s" % [name, label])
			visible_controls.append(control)
	for index in visible_controls.size():
		for other in range(index + 1, visible_controls.size()):
			check(not visible_controls[index].get_global_rect().intersects(visible_controls[other].get_global_rect()), "%s and %s do not overlap in %s" % [visible_controls[index].name, visible_controls[other].name, label])
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://../art/renders/gym_" + label + ".png") == OK, "Capture " + label)

func run() -> void:
	var state: Node = root.get_node("ShopState")
	# Keep asynchronous automation/checkpoints out of exact save comparisons.
	state.set_process(false)
	state._test_unix_time = 1234567890.0
	state._test_ticks_msec = 0
	state._last_ticks = 0
	check(state.reset_progress(), "Create isolated test progress")
	state.cash = 123
	check(not state.start_job().is_empty(), "Create an existing paid job")
	root.size = Vector2i(390, 844)
	game = load(Routes.CLEANING).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await settle()
	stroke(Vector3(0, 0.067, -1.8), Vector3(0.1, 0.067, 1.85))
	settle_dirt()
	check(game.save_contract_progress(), "Persist a partially brushed paid rug")
	game.return_to_shop()
	await settle()
	check(current_scene.scene_file_path == Routes.MAIN_MENU, "Start navigation from the production home")
	var saved_state: Dictionary = state._capture_state().duplicate(true)
	var saved_bytes := FileAccess.get_file_as_bytes(state._save_path)
	var home: Control = current_scene
	home.animate_shop = false
	check(home.get_node_or_null("%CloseSettings") == null, "Settings no longer contains a Done button")
	tap(home.get_node("%Settings"))
	await settle()
	check(home.get_node("%SettingsSheet").visible, "Touch opens Settings")
	mouse_at(home.get_node("%SettingsTitle").get_global_rect().get_center())
	check(home.get_node("%SettingsSheet").visible, "Clicking inside Settings keeps it open")
	var outside: Vector2 = home._safe_rect().position + Vector2(4, 4)
	mouse_at(outside)
	check(not home.get_node("%SettingsSheet").visible, "Clicking outside dismisses Settings")
	mouse_click(home.get_node("%Settings"))
	await settle()
	touch_at(outside)
	check(not home.get_node("%SettingsSheet").visible, "Touching outside also dismisses Settings")
	mouse_click(home.get_node("%Settings"))
	await settle()
	tap(home.get_node("%OpenGym"), true)
	await settle()
	check(current_scene == home, "A canceled Gym touch never navigates")
	tap(home.get_node("%OpenGym"))
	await settle()
	check(current_scene.scene_file_path == Routes.GYM, "The Settings Gym button opens the practice scene")
	if current_scene.scene_file_path != Routes.GYM:
		print("GYM_VALIDATION %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	game = current_scene
	await wait_ready()
	check(game.practice_only and not game.paid_contract and not state.contract_mode, "Gym remains free practice beside an existing paid job")
	check(game.rugs.size() == 2 and game.rug_buttons.size() == 2, "Gym offers exactly two exercises")
	check(game.selected_rug == 0, "Gym starts on Rug 1")
	check_tool(0)
	for name: String in ["Wallet", "UpgradeButton", "PayoutCard", "PayoutUpgradeButton", "AdRewardButton"]:
		check(not game.hud.control(name).is_visible_in_tree(), "Gym hides production control " + name)
	check(game.soil.remaining == 560 and game.soil.batch_node.visible, "Rug 1 starts with its reusable 560-clump pool")
	check(game.soil.surface_clearance() == 0.0 and not game.wet_recipe, "Rug 1 starts with dust and the brush recipe")
	var pool_id: int = game.soil.batch.get_instance_id()
	var controller_id: int = game.soil.get_instance_id()
	game.select_tool(1)
	game.select_tool(2)
	check_tool(0)
	await capture_and_check_layout("rug1_portrait")
	stroke(Vector3(0, 0.067, -1.8), Vector3(0.1, 0.067, 1.85))
	settle_dirt()
	check(game.soil.remaining < 560 and game.soil.surface_clearance() > 0.0, "Real brush strokes remove clumps and dust on Rug 1")
	game.begin_stroke(game.camera.unproject_position(Vector3.ZERO), false)
	tap(game.hud.control("GymReset"))
	check_no_stroke("Reset closes an active brush pass")
	check(game.soil.remaining == 560 and game.soil.surface_clearance() == 0.0 and game.selected_tool == 0, "Rug 1 Reset restores its brush and full dirt")
	# Reset must also cancel a completion already in flight.
	game.soil.remaining = 50
	game.soil.surface_coverage_total = 0.1 * float(game.soil.surface_pixel_count)
	game.update_contract_status()
	game.finish_rug()
	check(game.rug_phase == game.RugPhase.VACUUMING, "A completed brush exercise begins its cleanup transition")
	tap(game.hud.control("GymReset"))
	await settle()
	check(game.rug_phase == game.RugPhase.CLEANING and not game.soil.completion_started and game.soil.remaining == 560, "Reset cancels completion and restores an immediately usable rug")
	check_tool(0)
	game.begin_stroke(game.camera.unproject_position(Vector3.ZERO), false)
	tap(game.hud.control("GymRug2"))
	await settle()
	check_no_stroke("Changing exercises closes a brush pass")
	check(game.selected_rug == 1 and game.rug_phase == game.RugPhase.CLEANING, "Rug 2 selector opens the wet-tools workspace")
	check_tool(2)
	check(not game.soil.batch_node.visible and game.wet_recipe and game.soil.wet_recipe, "Rug 2 hides clumps and enables the shared wet-cleaning recipe")
	check(game.soil.water_clearance() == 0.0 and not game.soil.water_stage_complete() and game.soil.recommended_tool() == 2, "Rug 2 begins dry and requires the hose first")
	check(game.hud.control("GymSqueegee").disabled and not game.hud.control("GymHose").disabled, "The squeegee is unavailable until the entire rug is wet")
	check(not game.finish_button.is_visible_in_tree(), "Rug 2 has no cleaning completion action")
	game.select_tool(0)
	check_tool(2)
	await capture_and_check_layout("rug2_portrait")
	var extraction_before: PackedFloat32Array = game.soil.extraction_values.duplicate()
	var dry_wet_mask_hash := hash(game.soil.wet_mask.get_data())
	tap(game.hud.control("GymSqueegee"))
	check_tool(2)
	game.soil.apply_squeegee_stroke(Vector3(-0.6, 0.067, -0.6), Vector3(0.6, 0.067, 0.6), 0.08)
	check(game.soil.extraction_values == extraction_before and hash(game.soil.wet_mask.get_data()) == dry_wet_mask_hash, "A pre-gate squeegee request cannot extract or alter the wet mask")
	game.begin_stroke(game.camera.unproject_position(Vector3(-0.6, 0.067, -0.6)), false)
	var parked_hose: Vector3 = game.tool_nodes[2].position
	game.move_brush_to_screen(game.camera.unproject_position(Vector3(0.6, 0.067, 0.6)), false)
	game.end_stroke()
	check(not game.tool_nodes[2].position.is_equal_approx(parked_hose), "The Rug 2 hose moves over the rug")
	saturate_wet_rug()
	check(game.soil.water_clearance() >= 0.99 and game.soil.water_stage_complete() and game.soil.recommended_tool() == 1, "Full water coverage opens the extraction stage")
	check(game.hud.control("GymHose").disabled and not game.hud.control("GymSqueegee").disabled, "The completed water stage locks the hose and enables the squeegee")
	tap(game.hud.control("GymSqueegee"))
	check_tool(1)
	var extraction_at_gate: float = game.soil.extraction_clearance()
	var wet_mask_before_extraction := hash(game.soil.wet_mask.get_data())
	stroke(Vector3(-0.6, 0.067, -0.6), Vector3(0.6, 0.067, 0.6))
	game.soil._process(0.0)
	check(game.soil.extraction_clearance() > extraction_at_gate and hash(game.soil.wet_mask.get_data()) != wet_mask_before_extraction, "The enabled squeegee extracts water and lightens the shared wet mask")
	game.begin_stroke(game.camera.unproject_position(Vector3.ZERO), false)
	tap(game.hud.control("GymReset"))
	check_no_stroke("Wet-tool Reset closes the current stroke")
	check_tool(2)
	check(game.selected_rug == 1 and not game.soil.batch_node.visible and game.soil.water_clearance() == 0.0 and game.soil.extraction_clearance() == 0.0, "Reset restores Rug 2 to its dry hose stage")
	check(game.hud.control("GymSqueegee").disabled and not game.hud.control("GymHose").disabled, "Reset gates the squeegee again")
	root.size = Vector2i(844, 390)
	await capture_and_check_layout("rug2_landscape")
	mouse_click(game.hud.control("GymRug1"))
	await settle()
	check(game.selected_rug == 0 and game.soil.batch_node.visible and game.soil.remaining == 560, "Mouse selection returns to a fresh dry exercise")
	await capture_and_check_layout("rug1_landscape")
	game.start_rug_arrival()
	tap(game.hud.control("GymRug2"))
	await settle()
	check(game.selected_rug == 1 and game.rug_phase == game.RugPhase.CLEANING, "Switching during arrival cancels the old transition")
	check_tool(2)
	check(game.soil.batch.get_instance_id() == pool_id and game.soil.get_instance_id() == controller_id, "Resets and exercise switches reuse the controller and GPU dirt pool")
	root.size = Vector2i(320, 568)
	await capture_and_check_layout("rug2_small_portrait")
	tap(game.hud.control("GymSqueegee"))
	check_tool(2)
	saturate_wet_rug()
	tap(game.hud.control("GymSqueegee"))
	check_tool(1)
	root.size = Vector2i(568, 320)
	await capture_and_check_layout("rug2_small_landscape")
	tap(game.hud.control("GymReset"))
	check_tool(2)
	check(state._capture_state() == saved_state, "Gym practice leaves the paid job, cash, and progression unchanged")
	tap(game.hud.control("HomeButton"))
	await settle()
	check(current_scene.scene_file_path == Routes.MAIN_MENU, "Gym Home returns to the production home")
	check(state._capture_state() == saved_state and not state.contract_mode, "Returning from Gym preserves the existing paid job and ledger")
	check(FileAccess.get_file_as_bytes(state._save_path) == saved_bytes, "Gym does not modify the existing on-disk save")
	print("GYM_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
