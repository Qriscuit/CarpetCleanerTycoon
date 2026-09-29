extends SceneTree
## Staged reference stills from the unmodified production scenes.
## NOT a live player walkthrough: isolated ledger fixtures select upgrades/store.
## Run via tools/run_godot.ps1 --path CarpetToy --script
## ../design/marketing/capture_storyboard.gd -- --shop-test

const Progression = preload("res://scripts/progression.gd")
const OUT := "res://../design/marketing/references/"
var state: Node
var game: Node
var manifest: Array[Dictionary] = []

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Storyboarding requires -- --shop-test; refusing player-save access.")
		quit(2)
		return
	call_deferred("run")

func settle() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func capture(filename: String, description: String) -> bool:
	await settle()
	var picture := root.get_texture().get_image()
	var error := picture.save_png(OUT + filename)
	if error != OK:
		push_error("Could not save capture: " + filename)
		quit(3)
		return false
	manifest.append({"file": filename, "description": description, "staged": true, "width": picture.get_width(), "height": picture.get_height()})
	print("STORYBOARD_CAPTURE: ", filename, " ", picture.get_width(), "x", picture.get_height())
	return true

func leave() -> void:
	if is_instance_valid(game): game.free()
	game = null
	current_scene = null

func enter_cleaning() -> void:
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await settle()

func brush_pass(x: float, start_z: float, finish_z: float) -> void:
	game.soil.begin_pass()
	for step in 48:
		var a := Vector3(x, 0.067, lerpf(start_z, finish_z, float(step) / 48.0))
		var b := Vector3(x, 0.067, lerpf(start_z, finish_z, float(step + 1) / 48.0))
		game.apply_selected_tool_stroke(a, b, 1.0 / 60.0)
		game.soil._physics_process(1.0 / 60.0)
	game.soil.end_pass()
	game.contact_point = Vector3(x, 0.067, finish_z)
	game.place_selected_tool()
	game.update_contract_status()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Capture needs the real renderer.")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT)) != OK:
		push_error("Cannot create storyboard reference directory.")
		quit(3)
		return
	root.size = Vector2i(720, 1280)
	state = root.get_node("ShopState")
	state.set_process(false)
	state._test_ticks_msec = 0
	state._test_unix_time = 2000000.0
	state._save_path = "res://../build/storyboard_capture_%d.json" % OS.get_process_id()
	if not state.reset_progress():
		push_error("Cannot initialize isolated storyboard ledger.")
		quit(3)
		return
	game = load("res://scenes/production/floating_home.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	if not await capture("01_home.png", "Current production home, fresh isolated save."): return
	leave()
	await enter_cleaning()
	game.contact_point = Vector3(-0.34, 0.067, 0.7)
	game.place_selected_tool()
	if not await capture("02_dirty_starter.png", "Current production Neighborhood rug and starter brush; arrival animation skipped for a still."): return
	for pass_index in 4:
		brush_pass(-0.34, 1.95 if pass_index % 2 == 0 else -1.95, -1.95 if pass_index % 2 == 0 else 1.95)
	game.contact_point = Vector3(-0.34, 0.067, 1.0)
	game.place_selected_tool()
	if not await capture("03_brushed_stripe.png", "Actual starter-brush stroke API, four passes on the same stripe with debris pushed beyond the edge; current dust contrast."): return
	state.cash = 80
	if not state.buy_tool_upgrade():
		push_error("Staged first brush upgrade failed.")
		quit(3)
		return
	game.contact_point = Vector3(0.2, 0.067, 0.4)
	game.place_selected_tool()
	if not await capture("04_first_upgrade.png", "Actual FIRST Store 1 upgrade: Wide brush, 1.44x starter width. Bought through the real ledger for 80 seeded test coins; wallet now zero. Same partially cleaned rug."): return
	state.cash = 1700
	for level in 3:
		if not state.buy_tool_upgrade():
			push_error("Staged brush upgrade failed.")
			quit(3)
			return
	game.contact_point = Vector3(0.2, 0.067, 0.4)
	game.place_selected_tool()
	if not await capture("04_upgraded_brush.png", "Actual maximum Store 1 brush, 1.75x starter width; three additional upgrades purchased with 1700 seeded isolated-test coins after the first 80-coin upgrade. Same partially cleaned rug."): return
	leave()
	state._sync_active_branch()
	state.stores["2"] = Progression.new_branch(2)
	state.active_store = 2
	state._load_active_branch()
	state.cash = 800
	if state.start_job().is_empty():
		push_error("Cannot start staged Store 2 job.")
		quit(3)
		return
	await enter_cleaning()
	game.begin_stroke(game.camera.unproject_position(Vector3(-0.25, 0.067, 0.15)), false)
	for tick in 90:
		game.water._process(1.0 / 120.0)
	if not await capture("05_hose.png", "Actual paid Store 2 hose and contact/soak VFX, selected using a staged unlocked-store ledger."): return
	game.end_stroke()
	game.soil.apply_water_blob(game.soil.rug_node.to_global(Vector3.ZERO), game.soil.RUG_HALF.length() * 2.0, 1.0, 0.01)
	game.update_contract_status()
	game.end_stroke()
	await settle()
	for pass_index in 3:
		game.squeegee_motion.end_stroke()
		for step in 48:
			var a := Vector3(-0.22, 0.067, lerpf(-1.2, 1.7, float(step) / 48.0))
			var b := Vector3(-0.22, 0.067, lerpf(-1.2, 1.7, float(step + 1) / 48.0))
			game.apply_selected_tool_stroke(a, b, 1.0 / 60.0)
	game.contact_point = Vector3(-0.22, 0.067, 1.1)
	game.place_selected_tool()
	game.update_contract_status()
	if not await capture("06_squeegee.png", "Actual production squeegee stroke/VFX; entire rug first wetted through the shared water painter as a staged capture setup."): return
	# Deliberate clean-mask fixture: show the original material without triggering
	# a job completion or payout. Never describe this as an earned full clean.
	game.contract_finished = true
	game.leaving_scene = true
	game._cancel_wet_runtime_effects()
	game.soil._clear_dry_stage()
	game.soil.extraction_values = game.soil.water_values.duplicate()
	game.soil.extraction_coverage_total = game.soil.water_coverage_total
	game.soil.wet_mask.fill(Color.BLACK)
	game.soil.wet_mask_changed = true
	game.soil.request_render()
	for tool in game.tool_nodes: tool.hide()
	game.update_contract_status()
	if not await capture("07_clean_rug_fixture.png", "Clean-rug material reference, staged by clearing dry/wet masks and hiding tools. The 100% HUD is a fixture; no natural full job or payout occurred."): return
	var file := FileAccess.open(OUT + "capture_manifest.json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write storyboard capture manifest.")
		quit(3)
		return
	file.store_string(JSON.stringify({"engine": Engine.get_version_info(), "isolated_shop_test": true, "production_files_modified": false, "captures": manifest}, "\t"))
	file.flush()
	if file.get_error() != OK:
		push_error("Storyboard capture manifest write failed.")
		file.close()
		quit(3)
		return
	file.close()
	leave()
	print("STORYBOARD CAPTURE COMPLETE: ", manifest.size(), " staged production reference stills.")
	quit(0)
