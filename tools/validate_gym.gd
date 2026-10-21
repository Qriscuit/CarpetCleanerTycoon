extends SceneTree
## Godot --path CarpetToy --script ../tools/validate_gym.gd -- --shop-test
## Use the renderer for accurate camera, window scaling and MultiMesh checks.
const Routes = preload("res://scripts/scene_routes.gd")
const Catalog = preload("res://scripts/rug_catalog.gd")
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
	# Contacts now advance a whole-carpet level at a fixed rate. Repeating
	# contacts at one position must complete every footprint pixel.
	var changed := false
	for _contact in 20:
		changed = game.soil.apply_water_blob(Vector3(0.0, 0.067, 0.0), 0.19) or changed
		if game.soil.water_stage_complete(): break
	check(changed and game.soil.water_stage_complete(), "Repeated contacts at one spot saturate the whole practice carpet")
	game.soil._process(0.0)
	game.update_contract_status()

func finish_current_wash_fixture() -> void:
	# Only completion-transition setup is synthetic. Real hose contacts and
	# rotated blade strokes are exercised separately in this integration run.
	game.soil.extraction_values = game.soil._full_water_values.duplicate()
	game.soil.extraction_coverage_total = float(game.soil.surface_pixel_count)
	game.soil.extraction_mask.set_data(game.soil.MASK_SIZE.x, game.soil.MASK_SIZE.y, false, Image.FORMAT_L8, game.soil._full_wet_pixels)
	game.soil.extraction_mask_changed = true
	game.soil.wet_mask.fill(Color.BLACK)
	game.soil.wet_mask_changed = true
	game.soil._process(0.0)
	game.update_contract_status()
	game._advance_wet_tool()

func check_tool(index: int) -> void:
	check(game.selected_tool == index, "Selected gym tool is %d" % index)
	for other in game.tool_nodes.size():
		check(game.tool_nodes[other].visible == (other == index), "Exactly the selected tool model is visible (%d, %d)" % [index, other])
		check(game.tool_buttons[other].button_pressed == (other == index), "Tool picker highlights the equipped tool (%d, %d)" % [index, other])

func check_no_stroke(message: String) -> void:
	check(not game.brush_dragging and game.active_touch == -1 and not game.soil.pass_active, message)

func check_full_wet_rug(message: String) -> void:
	var fully_wet := is_equal_approx(game.soil.water_clearance(), 1.0)
	for pixel in game.soil.surface_pixels.size():
		if game.soil.surface_pixels[pixel] != 0:
			fully_wet = fully_wet and is_equal_approx(game.soil.water_values[pixel], 1.0)
	check(fully_wet and game.soil.extraction_clearance() == 0.0, message)

func check_empty_water_effects(message: String) -> void:
	var jet: Dictionary = game.water.debug_stats()
	var splash: Dictionary = game.squeegee_water.debug_stats()
	check(jet.history_count == 0 and jet.soak.active_spots == 0 and not jet.emitting and splash.active_splashes == 0 and not game.squeegee_water.impact.is_alive() and not game.squeegee_water.trail.is_alive(), message)

func check_practice_design() -> void:
	var id: String = game.practice_design_id
	check(Catalog.is_known(id), "Practice uses a production catalog identity: " + id)
	check(game.soil.rug_definition.rug_id == id, "The loaded carpet matches the selected identity: " + id)
	check(game.hud.control("GymTitle").text == Catalog.display_name(id), "The gym names its current design: " + id)
	for index in game.soil.surface_names.size():
		if game.soil.surface_names[index] == &"Carpet_Pile":
			var texture: Texture2D = game.soil.surface_materials[index].get_shader_parameter("clean_map")
			check(texture != null and texture.resource_path == Catalog.texture_path(id), "The visible pile uses this catalog design's art: " + id)

func check_catalog_cycles() -> void:
	# Exercise every production design in both practice recipes. A full deck
	# prevents a lucky random run from overlooking an unloadable carpet.
	for mode in [0, 1]:
		game.select_rug(mode)
		game._design_deck.clear()
		var seen: Dictionary = {}
		var previous_id: String = game.practice_design_id
		for _draw in Catalog.IDS.size():
			game.reset_rug()
			var id: String = game.practice_design_id
			check(id != previous_id, "Reset changes the carpet immediately in mode %d" % mode)
			check(not seen.has(id), "A shuffled deck visits each design once in mode %d: %s" % [mode, id])
			seen[id] = true
			previous_id = id
			check_practice_design()
			check(game.rug_phase == game.RugPhase.CLEANING and not game.soil.completion_started and not game.soil.simulation_suspended, "A swapped carpet is immediately playable: " + id)
			check_empty_water_effects("A swapped carpet has no effects from the preceding design: " + id)
			if mode == 0:
				check(game.soil.remaining == 560 and game.soil.surface_clearance() == 0.0, "Each brush carpet starts dirty: " + id)
				stroke(Vector3(0, 0.067, -1.8), Vector3(0.1, 0.067, 1.85))
				check(game.soil.surface_clearance() > 0.0, "Each catalog carpet accepts brush cleaning: " + id)
			else:
				check(game.soil.water_clearance() == 0.0 and game.soil.extraction_clearance() == 0.0, "Each wet carpet starts dry: " + id)
				check(game.soil.apply_water_blob(Vector3.ZERO, 0.45, 0.8), "Each catalog carpet accepts water: " + id)
				game.water.soak.feed(Vector3.ZERO, 0.2)
		check(seen.size() == Catalog.IDS.size(), "The gym offers the entire catalog in mode %d" % mode)
		game.reset_rug()
		check(game.practice_design_id != previous_id, "The next shuffled deck avoids an immediate repeat in mode %d" % mode)
		check_empty_water_effects("Crossing a deck boundary clears all old water effects")
		for tick in 6:
			game.water._process(0.1)
		check(game.soil.water_coverage_total == 0.0, "No old water can arrive on the next deck's carpet")
	check(game.hose_upgrade_level == 3 and game.squeegee_upgrade_level == 2 and game.camera_oblique, "Catalog resets retain both upgrade previews and the camera angle")

func capture_and_check_layout(label: String) -> void:
	await settle()
	# The headless DisplayServer reports a zero physical window size, so its
	# touch scale cannot model a phone. Native renderer runs retain every
	# viewport/layout/capture assertion below.
	if DisplayServer.get_name() == "headless": return
	var safe: Rect2 = game.hud._safe_rect()
	var visible_controls: Array[Control] = []
	for name: String in ["HomeButton", "CleaningProgress", "FinishJobButton", "GymRug1", "GymRug2", "GymBrush", "GymHose", "GymSqueegee", "GymReset", "GymCameraAngle", "GymTitle", "GymDescription", "GymStatus"]:
		var control: Control = game.hud.control(name)
		if control.is_visible_in_tree():
			check(safe.grow(1.0).encloses(control.get_global_rect()), "%s fits the safe area in %s" % [name, label])
			visible_controls.append(control)
	for index in visible_controls.size():
		for other in range(index + 1, visible_controls.size()):
			check(not visible_controls[index].get_global_rect().intersects(visible_controls[other].get_global_rect()), "%s and %s do not overlap in %s" % [visible_controls[index].name, visible_controls[other].name, label])
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://../art/renders/gym_" + label + ".png") == OK, "Capture " + label)

func run() -> void:
	var state: Node = root.get_node("ShopState")
	# Keep checkpoints out of exact save comparisons.
	state.set_process(false)



	state._save_path = "res://.godot/gym_validation_%d.json" % OS.get_process_id()
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
	check_practice_design()
	check_tool(0)
	check(game.hud.get_node_or_null("%PayoutCard") == null, "Practice inherits a HUD without the removed earnings footer")
	for name: String in ["Wallet", "UpgradeButton", "AdRewardButton"]:
		check(not game.hud.control(name).is_visible_in_tree(), "Gym hides production control " + name)
	check(not game.hud.room_panel.is_visible_in_tree(), "Gym hides the room purchase modal")
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
	var brush_design: String = game.practice_design_id
	tap(game.hud.control("GymReset"))
	check(game.practice_design_id != brush_design, "The Reset touch replaces the brush carpet with another design")
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
	var current_design: String = game.practice_design_id
	tap(game.hud.control("GymRug2"))
	await settle()
	check_no_stroke("Changing exercises closes a brush pass")
	check(game.selected_rug == 1 and game.rug_phase == game.RugPhase.CLEANING, "Rug 2 selector opens the wet-tools workspace")
	check(game.practice_design_id == current_design, "Changing exercises retains the current carpet design")
	check_tool(2)
	check(not game.soil.batch_node.visible and game.wet_recipe and game.soil.wet_recipe, "Rug 2 hides clumps and enables the shared wet-cleaning recipe")
	check(game.soil.water_clearance() == 0.0 and not game.soil.water_stage_complete() and game.soil.recommended_tool() == 2, "Rug 2 begins dry with the hose equipped")
	check(not game.hud.control("GymSqueegee").disabled and not game.hud.control("GymHose").disabled, "Both wet-tool setup shortcuts are available on a dry rug")
	check(not game.finish_button.is_visible_in_tree(), "Rug 2 has no cleaning completion action")
	game.select_tool(0)
	check_tool(2)
	await capture_and_check_layout("rug2_portrait")
	var extraction_before: PackedFloat32Array = game.soil.extraction_values.duplicate()
	var dry_wet_mask_hash := hash(game.soil.wet_mask.get_data())
	game.select_tool(1)
	check_tool(2)
	game.soil.apply_squeegee_stroke(Vector3(-0.6, 0.067, -0.6), Vector3(0.6, 0.067, 0.6), 0.08)
	check(game.soil.extraction_values == extraction_before and hash(game.soil.wet_mask.get_data()) == dry_wet_mask_hash, "Internal selection and production paint gates never refill or extract a dry rug")
	game.set_hose_upgrade_level(3)
	game.set_squeegee_upgrade_level(2)
	game.set_camera_angle(true)
	game.begin_stroke(game.camera.unproject_position(Vector3(-0.6, 0.067, -0.6)), false)
	var parked_hose: Vector3 = game.tool_nodes[2].position
	game.move_brush_to_screen(game.camera.unproject_position(Vector3(0.6, 0.067, 0.6)), false)
	game.end_stroke()
	check(not game.tool_nodes[2].position.is_equal_approx(parked_hose), "The Rug 2 hose moves over the rug")
	game.water.soak.feed(Vector3(0.0, 0.067, 0.0), 0.2)
	game.begin_stroke(game.camera.unproject_position(Vector3.ZERO), false)
	tap(game.hud.control("GymSqueegee"))
	check_no_stroke("Squeegee shortcut closes the active hose stroke")
	check_tool(1)
	check_full_wet_rug("Squeegee shortcut instantly wets every valid carpet pixel, including its edges")
	check_empty_water_effects("Squeegee shortcut removes old jet parcels, soak and extraction effects")
	check(game.hose_upgrade_level == 3 and game.water.upgrade_level == 3 and game.camera_oblique, "Practice shortcuts retain the hose upgrade and camera angle")
	mouse_click(game.hud.control("GymHose"))
	check_tool(2)
	check(game.soil.water_clearance() == 0.0 and game.soil.extraction_clearance() == 0.0, "Hose shortcut instantly clears both wetness and extraction")
	check_empty_water_effects("Hose shortcut clears old water before a new exercise")
	game.soil.apply_water_blob(Vector3.ZERO, 0.45, 0.8)
	check(game.soil.water_clearance() > 0.0, "The newly dry exercise accepts fresh water")
	tap(game.hud.control("GymHose"))
	check_tool(2)
	for tick in 6:
		game.water._process(0.1)
	check(game.soil.water_clearance() == 0.0 and game.soil.extraction_clearance() == 0.0, "Tapping the already equipped hose resets the rug without delayed rewetting")
	saturate_wet_rug()
	check(game.soil.water_clearance() >= 0.99 and game.soil.water_stage_complete() and game.soil.recommended_tool() == 1, "Full water coverage opens the extraction stage")
	check(not game.hud.control("GymHose").disabled and not game.hud.control("GymSqueegee").disabled, "Both practice shortcuts remain available after full wetness")
	tap(game.hud.control("GymSqueegee"))
	check_tool(1)
	var extraction_at_gate: float = game.soil.extraction_clearance()
	var wet_mask_before_extraction := hash(game.soil.wet_mask.get_data())
	stroke(Vector3(-0.6, 0.067, -0.6), Vector3(0.6, 0.067, 0.6))
	game.soil._process(0.0)
	check(game.soil.extraction_clearance() > extraction_at_gate and hash(game.soil.wet_mask.get_data()) != wet_mask_before_extraction, "The enabled squeegee extracts water and lightens the shared wet mask")
	var scraped_values: PackedFloat32Array = game.soil.extraction_values.duplicate()
	game.select_tool(1)
	check(game.soil.extraction_values == scraped_values, "Internal squeegee reselection never refills a partially scraped carpet")
	for round_index in 2:
		finish_current_wash_fixture()
		await settle()
		check(game.soil.wash_cycle == round_index + 1 and game.selected_tool == 2 and game.dirty, "Completing wash %d equips the next hose and retains dirty state" % (round_index + 1))
		check(game.soil.water_clearance() == 0.0 and game.soil.extraction_clearance() == 0.0 and not game.soil.all_washes_complete(), "Next wash starts with empty current-round water and extraction")
		check(game.hud.control("ProgressStage").text == "Wet · %d/3" % (round_index + 2), "Gym progress caption follows the new wash")
		saturate_wet_rug()
		game._advance_wet_tool()
		check_tool(1)
	finish_current_wash_fixture()
	await settle()
	check(game.soil.wash_cycle == 2 and game.soil.all_washes_complete() and not game.dirty, "The third squeegee round restores the carpet")
	check(game.hud.control("ProgressStage").text == "Clean" and game.hud.control("GymStatus").text == "Clean", "Final wash reports clean in both Gym progress labels")
	mouse_click(game.hud.control("GymSqueegee"))
	check_tool(1)
	check_full_wet_rug("Tapping the already equipped squeegee refills the rug and clears extraction")
	check_empty_water_effects("Refilling clears the previous swipe's water and impact effects")
	check(game.practice_design_id == current_design, "Repeated wet-tool shortcuts retain the current carpet design")
	game.begin_stroke(game.camera.unproject_position(Vector3.ZERO), false)
	tap(game.hud.control("GymReset"))
	check(game.practice_design_id != current_design, "The Reset touch replaces the wet carpet with another design")
	check_no_stroke("Wet-tool Reset closes the current stroke")
	check_tool(2)
	check(game.selected_rug == 1 and not game.soil.batch_node.visible and game.soil.water_clearance() == 0.0 and game.soil.extraction_clearance() == 0.0, "Reset restores Rug 2 to its dry hose stage")
	check(not game.hud.control("GymSqueegee").disabled and not game.hud.control("GymHose").disabled, "Reset retains both repeatable setup shortcuts")
	root.size = Vector2i(844, 390)
	await capture_and_check_layout("rug2_landscape")
	mouse_click(game.hud.control("GymRug1"))
	await settle()
	check(game.selected_rug == 0 and game.soil.batch_node.visible and game.soil.remaining == 560, "Mouse selection returns to a fresh dry exercise")
	await capture_and_check_layout("rug1_landscape")
	game.start_rug_arrival()
	current_design = game.practice_design_id
	tap(game.hud.control("GymReset"))
	await settle()
	check(game.practice_design_id != current_design and game.rug_phase == game.RugPhase.CLEANING and game.get_node("RugDisplay").position == Vector3.ZERO, "Reset during arrival replaces the carpet and cancels its movement")
	check(game.transition_tween == null or not game.transition_tween.is_running(), "Reset leaves no arrival animation capable of moving the new carpet")
	game.start_rug_arrival()
	tap(game.hud.control("GymRug2"))
	await settle()
	check(game.selected_rug == 1 and game.rug_phase == game.RugPhase.CLEANING, "Switching during arrival cancels the old transition")
	check_tool(2)
	check(game.soil.batch.get_instance_id() == pool_id and game.soil.get_instance_id() == controller_id, "Resets and exercise switches reuse the controller and GPU dirt pool")
	root.size = Vector2i(320, 568)
	await capture_and_check_layout("rug2_small_portrait")
	tap(game.hud.control("GymSqueegee"))
	check_tool(1)
	check_full_wet_rug("Small-portrait touch can prepare a fully wet squeegee exercise")
	tap(game.hud.control("GymSqueegee"))
	check_tool(1)
	root.size = Vector2i(568, 320)
	await capture_and_check_layout("rug2_small_landscape")
	tap(game.hud.control("GymReset"))
	check_tool(2)
	check_catalog_cycles()
	check(state._capture_state() == saved_state, "Gym practice leaves the paid job, cash, and progression unchanged")
	tap(game.hud.control("HomeButton"))
	await settle()
	check(current_scene.scene_file_path == Routes.MAIN_MENU, "Gym Home returns to the production home")
	check(state._capture_state() == saved_state and not state.contract_mode, "Returning from Gym preserves the existing paid job and ledger")
	check(FileAccess.get_file_as_bytes(state._save_path) == saved_bytes, "Gym does not modify the existing on-disk save")
	print("GYM_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
