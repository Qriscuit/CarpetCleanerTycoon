extends SceneTree
## Renderer-backed contract tests use a separate ledger and never touch player progress.
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CONTRACT CHECK: " + message)

func _initialize() -> void:
	call_deferred("run")

func capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../art/renders/" + filename))

func sweep_lanes(soil: Node) -> void:
	for lane in [-0.85, -0.42, 0.0, 0.42, 0.85]:
		soil.begin_pass()
		soil.stroke(Vector3(lane, 0.067, -2.5), Vector3(lane, 0.067, 1.85), 0.04)
		soil.end_pass()
		for tick in 200:
			if not soil.is_physics_processing():
				break
			soil._physics_process(1.0 / 60.0)

func run() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test for an isolated contract run.")
		quit(2)
		return
	var state := root.get_node("ShopState")
	state._save_path = "res://../art/contract_test_%d.json" % OS.get_process_id()
	var job_id: String = state.start_job()
	check(not job_id.is_empty(), "Job creation commits")
	state.contract_mode = true
	var scene := load("res://scenes/rug_cleaning_gym.tscn") as PackedScene
	var game := scene.instantiate()
	root.add_child(game)
	await process_frame
	var soil: Node = game.soil
	check(game.paid_contract and not soil.automatic_completion_enabled, "Paid mode disables the free gym auto reveal")
	check(game.finish_button.disabled, "Untouched rug cannot finish")
	check(game.tool_buttons[1].disabled and game.tool_buttons[2].disabled, "Paid work equips the owned functional brush")
	game.select_tool(2)
	check(game.selected_tool == 0, "Unowned test tools cannot be selected by code")
	game.select_rug(2)
	check(game.selected_rug == 0, "A customer's rug cannot be switched")
	game.finish_contract()
	check(state.cash == 0 and state.manual_jobs == 0, "Empty job never pays")
	await capture("contract_start.png")
	sweep_lanes(soil)
	check(soil.unique_clearance() >= 0.9, "Real sweeps remove at least 90 percent of unique debris")
	check(soil.surface_clearance() < 0.9, "A first dust pass remains insufficient")
	check(not soil.completion_started, "Clearing every clump does not auto erase paid-job dust")
	game.update_contract_status()
	check(game.finish_button.disabled, "High debris clearance alone cannot finish")
	game.finish_contract()
	check(state.cash == 0, "Dust threshold is enforced by the action")
	# Back must keep the live rug when a disk write cannot commit its latest work.
	var unsaved_surface: float = soil.surface_clearance()
	state._save_enabled = false
	game.return_to_shop()
	await process_frame
	check(is_instance_valid(game) and game.is_inside_tree() and state.contract_mode, "A failed Back save keeps the paid scene alive")
	check(is_equal_approx(soil.surface_clearance(), unsaved_surface), "A failed Back save preserves the current rug work")
	game.update_contract_status()
	check(game.contract_status.text.contains("Couldn't save"), "A failed Back save explains how to retry")
	state._save_enabled = true
	check(game.save_contract_progress(), "Saving can be retried after the write failure clears")
	game.save_contract_progress()
	var unique_before: float = soil.unique_clearance()
	var dust_before: float = soil.surface_clearance()
	game.free()
	# Reload the serialized data, not just an in-memory copy of the snapshot.
	var ledger: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state._save_path))
	state.job_snapshot = ledger.job_snapshot
	game = scene.instantiate()
	root.add_child(game)
	await process_frame
	soil = game.soil
	check(is_equal_approx(soil.unique_clearance(), unique_before), "Unique clump progress survives JSON save and re-entry")
	check(absf(soil.surface_clearance() - dust_before) < 0.003, "Dust mask survives JSON save and re-entry")
	game.reset_rug()
	check(is_equal_approx(soil.unique_clearance(), unique_before), "Paid reset cannot replace the current contract state")
	sweep_lanes(soil)
	sweep_lanes(soil)
	game.update_contract_status()
	check(soil.unique_clearance() >= 0.9 and soil.surface_clearance() >= 0.9, "Repeated real brush strokes satisfy both targets")
	check(not game.finish_button.disabled, "Complete cleaning enables Finish")
	await capture("contract_ready.png")
	game.finish_contract()
	check(state.cash == 20 and state.manual_jobs == 1 and state.active_job_id.is_empty(), "One completed contract pays exactly 20 cash")
	check(game.contract_finished and soil.completion_started, "Only accepted completion triggers the clean reveal")
	game.finish_contract()
	check(not state.complete_job(job_id) and state.cash == 20 and state.manual_jobs == 1, "Repeated button/API completion cannot pay twice")
	for tick in 120:
		soil._physics_process(1.0 / 60.0)
	await capture("contract_complete.png")
	game.free()
	state.contract_mode = false
	game = scene.instantiate()
	root.add_child(game)
	await process_frame
	check(not game.paid_contract and game.soil.automatic_completion_enabled, "Free gym retains its original completion behavior")
	game.finish_contract()
	check(state.cash == 20, "Free gym never awards cash")
	game.free()
	state._owned["wide_brush"] = true
	state.start_job()
	state.contract_mode = true
	game = scene.instantiate()
	root.add_child(game)
	await process_frame
	check(game.soil.head_half.x > game.soil.HEAD_HALF.x * 1.4, "Owned wide brush has a wider physical footprint")
	check(game.brush.scale.x > game.brush.scale.z * 1.4, "Owned wide brush is visibly wider")
	game.soil.begin_pass()
	game.soil.stroke(Vector3(0, 0.067, -1.6), Vector3(0, 0.067, 1.6), 0.4)
	check(game.soil.coverage_values[208 * 256 + 177] < 0.6, "Wider brush actually removes dust beyond the starter width")
	await capture("contract_wide_brush.png")
	game.free()
	state.set_process(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("CONTRACT CHECKS COMPLETE: ", failures, " failures; separate gym mode, two cleanliness targets, JSON resume, exact-once cash and wide brush.")
	quit(0 if failures == 0 else 1)
