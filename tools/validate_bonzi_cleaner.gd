extends SceneTree
## Bonzi exercises the real paid rug, durable ledger and manual brush together.
## Use the pinned runner with -- --shop-test; optional --bonzi-capture saves renders.

const CLEANING_SCENE := preload("res://scenes/production/rug_cleaning.tscn")
const Progression := preload("res://scripts/progression.gd")
const STEP := 0.05
const COMPLETION_BUDGET := 400.0

var checks := 0
var failures := 0
var game: Node
var ledger: Node
var save_path := ""


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Bonzi validation requires -- --shop-test to protect player progress.")
		quit(2)
		return
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BONZI: " + message)


func settle() -> void:
	await process_frame
	await process_frame


func capture(label: String) -> void:
	if "--bonzi-capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../art/renders")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join("bonzi_" + label + ".png")) == OK, "Save render: " + label)


func enter_cleaning(practice: bool = false) -> void:
	game = CLEANING_SCENE.instantiate()
	game.animate_rug_changes = false
	game.practice_only = practice
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await settle()
	game.set_physics_process(false)
	check(game.rug_phase == game.RugPhase.CLEANING, "Production rug reaches its real cleaning phase")


func leave_cleaning() -> void:
	if is_instance_valid(game):
		game.free()
	game = null
	current_scene = null


func advance_steps(count: int) -> void:
	for _step in count:
		game._physics_process(STEP)
		# Deterministic simulation also lets any real manually launched clumps move.
		if game.rug_phase == game.RugPhase.CLEANING:
			game.soil._physics_process(STEP)
		game.soil._process(STEP)


func assert_paused(label: String) -> void:
	var position: Vector3 = game.bonzi.position
	var distance: float = game.bonzi.travelled_distance
	var coverage: float = game.soil.surface_coverage_total
	var remaining: int = game.soil.remaining
	advance_steps(20)
	check(game.bonzi.position.is_equal_approx(position) and is_equal_approx(float(game.bonzi.travelled_distance), distance), label + ": Bonzi does not advance")
	check(is_equal_approx(float(game.soil.surface_coverage_total), coverage) and game.soil.remaining == remaining, label + ": Bonzi does not clean")
	check(not game.bonzi.running and not game._bonzi_can_clean(), label + ": the autonomous work gate is closed")


func validate_pause_gates() -> void:
	game.open_room_upgrade("floor")
	check(game.hud.upgrades_open(), "Real accessory offer opens")
	assert_paused("Accessory offer")
	await capture("upgrade_paused")
	game.hud.close_upgrades()
	advance_steps(2)
	check(game.bonzi.running and game._bonzi_can_clean(), "Closing the accessory offer resumes Bonzi")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_paused("Application focus loss")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	advance_steps(2)
	check(game.bonzi.running and game.application_focused, "Application focus return resumes Bonzi")
	game.soil.suspend_simulation(true)
	assert_paused("Suspended dirt simulation")
	game.soil.suspend_simulation(false)
	game.soil.set_reveal_progress(0.5)
	assert_paused("Partly revealed carpet")
	game.soil.set_reveal_progress(1.0)
	for phase: int in [game.RugPhase.ARRIVING, game.RugPhase.GROWING, game.RugPhase.TOOL_ENTERING, game.RugPhase.VACUUMING, game.RugPhase.REVEAL, game.RugPhase.DEPARTING]:
		game.rug_phase = phase
		assert_paused("Non-cleaning phase %d" % phase)
		check(not game.bonzi.visible, "Non-cleaning phase %d hides Bonzi" % phase)
	game.rug_phase = game.RugPhase.CLEANING
	game.finish_requested = true
	assert_paused("Finish requested")
	game.finish_requested = false
	game.leaving_scene = true
	assert_paused("Leaving the scene")
	game.leaving_scene = false
	advance_steps(2)
	check(game.bonzi.running and game.bonzi.visible, "Restoring cleaning conditions reveals and resumes Bonzi")


func validate_checkpoint_and_resume() -> void:
	game.snapshot_timer.stop()
	var before: float = float(ledger.job_snapshot.get("surface_clearance", 0.0))
	var cash_before: float = ledger.cash
	var paid_before: float = ledger._branch().job_cleaning_paid
	var jobs_before: int = ledger.manual_jobs
	var orders_before: int = ledger.automated_jobs
	# Keep producing progress throughout the real two-second checkpoint window.
	# Restarting a debounce timer on every bot stroke would fail this check.
	for _tick in 32:
		advance_steps(12)
		await create_timer(0.075).timeout
	check(float(ledger.job_snapshot.get("surface_clearance", 0.0)) > before + 0.001, "Continuous Bonzi movement checkpoints progress without a finger release")
	check(ledger.cash > cash_before and float(ledger._branch().job_cleaning_paid) > paid_before and ledger.manual_jobs == jobs_before and ledger.automated_jobs == orders_before, "Real Bonzi removal earns the same cleaning half before completion without adding a routine order")
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	check(disk is Dictionary and float(disk.get("job_snapshot", {}).get("surface_clearance", 0.0)) > before + 0.001, "The autonomous checkpoint exists on disk")
	var saved_job: String = game.contract_job_id
	var saved_rug: String = ledger.active_rug_id
	var saved_surface: float = game.soil.surface_clearance()
	var saved_unique: float = game.soil.unique_clearance()
	check(saved_surface > 0.0 and saved_surface < 0.99, "Resume fixture contains real partial autonomous cleaning")
	leave_cleaning()
	var saved_paid: float = ledger._branch().job_cleaning_paid
	var saved_progress: float = ledger._branch().job_cleaning_progress
	var saved_cash: float = ledger.cash
	ledger._load_state()
	await enter_cleaning()
	check(game.contract_job_id == saved_job and ledger.active_rug_id == saved_rug, "Reopening restores the same unfinished paid rug")
	check(absf(game.soil.surface_clearance() - saved_surface) <= 1.0 / 255.0 and is_equal_approx(game.soil.unique_clearance(), saved_unique), "Reopening retains the real dust mask and clump credit")
	check(game.bonzi.travelled_distance == 0.0 and game.bonzi.completed_sweeps == 0, "Reopening starts a fresh route without adding path data to the save")
	check(ledger.cash == saved_cash and float(ledger._branch().job_cleaning_paid) == saved_paid and float(ledger._branch().job_cleaning_progress) == saved_progress and saved_paid > 0.0 and saved_progress > 0.0, "Reopening retains Bonzi's paid cleaning amount and high-water mark without replaying coins")
	check(not bool(ledger._branch().job_final_tool_used), "Autonomous saved progress does not become manual capstone use")
	await capture("resumed")


func validate_autonomous_completion() -> void:
	var job_id: String = game.contract_job_id
	var quote: float = ledger.current_job_full_reward()
	var already_paid: float = ledger._branch().job_cleaning_paid
	var remaining: float = quote - already_paid
	var cash_before: float = ledger.cash
	var jobs_before: int = ledger.manual_jobs
	var automated_before: int = ledger.automated_jobs
	var scene_id: int = game.get_instance_id()
	var pool_id: int = game.soil.batch.get_instance_id()
	var robot_id: int = game.bonzi.get_instance_id()
	var simulated := 0.0
	var previous_position: Vector3 = game.bonzi.position
	var largest_step := 0.0
	var captured_half := false
	while simulated < COMPLETION_BUDGET and not game.contract_finished:
		advance_steps(1)
		simulated += STEP
		largest_step = maxf(largest_step, previous_position.distance_to(game.bonzi.position))
		previous_position = game.bonzi.position
		if int(roundf(simulated / STEP)) % 20 == 0:
			await process_frame
			if not captured_half and game.soil.overall_clearance() >= 0.5 and not game.contract_finished:
				captured_half = true
				await capture("cleaning_half")
	print("BONZI_COMPLETION: simulated_seconds=", snappedf(simulated, 0.05), " surface_clearance=", game.soil.surface_clearance(), " unique_clearance=", game.soil.unique_clearance(), " completed=", game.contract_finished)
	check(game.contract_finished, "Bonzi completes an untouched carpet within 400 simulated seconds")
	check(not game.brush_dragging and game.active_touch == -1, "No finger input is required for the complete rug")
	check(game.completed_full_restore and game.completed_fraction >= 0.99, "Bot completion clears both dry layers enough for the full rug reward")
	check(largest_step <= 0.02, "Bonzi sweeps continuously without teleporting between lanes")
	check(ledger.cash == cash_before + remaining and ledger.manual_jobs == jobs_before + 1 and float(ledger.completed_rewards[job_id].amount) == quote, "Completion settles only the unpaid quote and records the entire Bonzi-cleaned carpet exactly once")
	check(ledger.automated_jobs == automated_before, "The visible cleaner does not invent a second routine-order payout")
	check(int(ledger._branch().final_tool_jobs) == 0, "Bot-only completion does not satisfy the manually used capstone tool requirement")
	check(not game.bonzi.running and not game.bonzi.visible, "The completed rug pauses and hides Bonzi before departure")
	game.finish_rug()
	check(ledger.cash == cash_before + remaining and ledger.manual_jobs == jobs_before + 1, "Repeated completion requests cannot duplicate the bot-cleaned reward")
	check(ledger.complete_and_start_next_job(job_id, {"unique_clearance": 1.0, "surface_clearance": 1.0}).is_empty(), "The old rug reservation cannot be paid again")
	await capture("completed")
	if not game.contract_finished:
		return
	for _tick in 50:
		if game.soil.vacuum_complete:
			break
		game.soil._physics_process(STEP)
		game.soil._process(STEP)
	await settle()
	check(game.contract_job_id != job_id and game.rug_phase == game.RugPhase.CLEANING, "The real vacuum completion opens the next paid carpet")
	check(game.get_instance_id() == scene_id and game.soil.batch.get_instance_id() == pool_id and game.bonzi.get_instance_id() == robot_id, "Next carpet reuses the scene, debris pool and Bonzi model")
	check(game.bonzi.travelled_distance == 0.0 and game.bonzi.completed_sweeps == 0, "A replacement carpet resets the autonomous route")
	check(game.soil.surface_clearance() == 0.0 and game.soil.unique_clearance() == 0.0, "The next carpet begins dirty without old cleaning credit")


func validate_simultaneous_brushing() -> void:
	var soil: Node = game.soil
	# Put the manual stroke in Bonzi's actual current lane, so the later manual
	# extension overlaps dust the bot has removed since this pass began.
	var lane: Vector3 = game.bonzi.position
	var start: Vector3 = soil.rug_node.to_global(Vector3(lane.x, soil.RUG_Y, lane.z - 0.8))
	var middle: Vector3 = soil.rug_node.to_global(Vector3(lane.x, soil.RUG_Y, lane.z - 0.2))
	var finish: Vector3 = soil.rug_node.to_global(Vector3(lane.x, soil.RUG_Y, lane.z + 0.8))
	game.begin_stroke(game.camera.unproject_position(start), false)
	game.apply_selected_tool_stroke(start, middle, 0.3)
	var base: PackedFloat32Array = soil.pass_base.duplicate()
	var strength: PackedFloat32Array = soil.pass_strength.duplicate()
	var pass_serial: int = soil.pass_serial
	var manual_before: float = soil.surface_coverage_total
	var distance: float = game.bonzi.travelled_distance
	advance_steps(160)
	check(game.brush_dragging and soil.pass_active, "Bonzi keeps working while the player's brush is held")
	check(game.bonzi.travelled_distance > distance, "Holding the manual brush does not pause Bonzi")
	check(soil.pass_serial == pass_serial and soil.pass_base == base and soil.pass_strength == strength, "Bonzi does not reset or modify the manual stroke history")
	check(soil.surface_coverage_total <= manual_before, "Concurrent bot cleaning never puts dirt back on the carpet")
	var combined_before: PackedFloat32Array = soil.coverage_values.duplicate()
	game.apply_selected_tool_stroke(middle, finish, 0.3)
	var dirt_increased := false
	for index in combined_before.size():
		if soil.coverage_values[index] > combined_before[index] + 0.000001:
			dirt_increased = true
			break
	check(not dirt_increased, "A manual stroke cannot restore dust removed concurrently by Bonzi")
	check(bool(ledger._branch().job_final_tool_used), "Real use of the owned capstone brush still receives manual tool qualification")
	game.end_stroke()
	check(not game.brush_dragging and not soil.pass_active, "Manual release closes only the manual pass")
	advance_steps(4)
	check(game.bonzi.running, "Bonzi continues after the manual brush is released")
	await capture("brush_together")


func finish_tests() -> void:
	leave_cleaning()
	var audio := root.get_node_or_null("GameAudio")
	if audio != null:
		audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	if not save_path.is_empty():
		DirAccess.remove_absolute(save_path)
	print("BONZI_RESULT: ", checks, " checks, ", failures, " failures")
	quit(1 if failures > 0 else 0)


func run() -> void:
	ledger = root.get_node("ShopState")
	ledger.set_process(false)
	ledger._test_ticks_msec = 1000
	ledger._test_unix_time = 1791471600.0
	save_path = ProjectSettings.globalize_path("res://.godot/bonzi_cleaner_test_%d.json" % OS.get_process_id())
	ledger._save_path = save_path
	check(ledger.reset_progress(), "Create an isolated durable ledger")
	root.size = Vector2i(648, 900)
	await enter_cleaning()
	check(game.bonzi != null, "The production scene installs the Bonzi controller")
	if game.bonzi == null:
		await finish_tests()
		return
	assert_paused("Bonzi not purchased")
	check(not game.bonzi.visible and int(ledger.progression_view().bonzi_tier) == -1, "Unowned Bonzi is hidden without granting ownership")
	leave_cleaning()
	# Ledger fixtures unlock the existing purchase through its existing job gate.
	for job_index in 3:
		var job: String = ledger.start_job()
		check(not ledger.complete_and_start_next_job(job, {"unique_clearance": 1.0, "surface_clearance": 1.0}).is_empty(), "Record fixture commission %d through the atomic ledger" % (job_index + 1))
	ledger.cash = Progression.bot_cost(1, -1)
	check(ledger.save_state(), "Fund the isolated hire fixture at its actual revised price")
	check(ledger.buy_bonzi_upgrade(), "Bonzi is acquired through its real gated purchase")
	for _level in 4:
		ledger.cash = Progression.tool_cost(1, _level)
		check(ledger.save_state(), "Fund each isolated brush tier at its actual price")
		check(ledger.buy_tool_upgrade(), "Purchase the capstone brush for the qualification checks")
	await enter_cleaning()
	advance_steps(1)
	check(game._bonzi_can_clean() and game.bonzi.running and game.bonzi.visible, "Purchased Bonzi activates on the paid dry carpet")
	check(game.bonzi.visual != null and game.bonzi.visual.scene_file_path == "res://scenes/tools/bonzi_cleaner.tscn", "The real authored 3D robot is attached to the controller")
	check(not bool(ledger._branch().job_final_tool_used), "Owning the capstone brush alone does not count as using it")
	await capture("purchased")
	advance_steps(160)
	check(game.bonzi.travelled_distance > 0.0 and game.soil.surface_clearance() > 0.0 and game.soil.unique_clearance() > 0.0, "Autonomous motor motion cleans real dust and original clumps")
	check(not soil_pass_active(), "Autonomous cleaning does not begin a manual pass")
	await validate_pause_gates()
	await validate_checkpoint_and_resume()
	await validate_autonomous_completion()
	if game.rug_phase == game.RugPhase.CLEANING and not game.contract_finished:
		await validate_simultaneous_brushing()
	root.size = Vector2i(900, 648)
	await settle()
	await capture("landscape")
	leave_cleaning()
	await enter_cleaning(true)
	assert_paused("Free practice carpet")
	check(not game.bonzi.visible, "Practice does not use the purchased production helper")
	leave_cleaning()
	# Every currently playable shop uses dry work; water remains a future section.
	ledger._sync_active_branch()
	ledger.stores["2"] = Progression.new_branch(2)
	check(ledger.select_store(2), "Visit a second owned dry shop")
	await enter_cleaning()
	check(not game.wet_recipe and int(ledger.progression_view().bonzi_tier) >= 0, "The second shop retains dry cleaning and owned Bonzi")
	advance_steps(160)
	check(game.bonzi.visible and game.bonzi.running and game.soil.surface_clearance() > 0.0, "Bonzi works on the second real shop's carpet")
	leave_cleaning()
	ledger._sync_active_branch()
	ledger.stores["3"] = Progression.new_branch(3)
	check(ledger.select_store(3), "Visit a third owned dry shop")
	await enter_cleaning()
	advance_steps(160)
	check(not game.wet_recipe and game.bonzi.visible and game.bonzi.running and game.soil.unique_clearance() > 0.0, "Bonzi also removes real clumps in the third dry shop")
	check(not ledger.select_store(Progression.WET_FIRST_STORE) and not Progression.section_available(2), "The future wet section cannot be entered through the helper fixture")
	await finish_tests()


func soil_pass_active() -> bool:
	return bool(game.soil.pass_active)
