extends SceneTree
## Renderer-backed checks for the production 85%/99% rug loop.
var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CONTRACT CHECK: " + message)


func _initialize() -> void:
	call_deferred("run")


func set_cleanliness(game: Node, unique: float, surface: float) -> void:
	var soil: Node = game.soil
	soil.remaining = roundi(float(soil.initial.size()) * (1.0 - unique))
	soil.surface_coverage_total = float(soil.surface_pixel_count) * (1.0 - surface)
	game.update_contract_status()


func run() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test for an isolated contract run.")
		quit(2)
		return
	var state := root.get_node("ShopState")
	state._save_path = "res://../art/contract_test_%d.json" % OS.get_process_id()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	check(state.reset_progress(), "Isolated ledger starts clean")
	var scene := load("res://scenes/production/rug_cleaning.tscn") as PackedScene
	var game := scene.instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	await process_frame
	var soil: Node = game.soil
	var first_job: String = game.contract_job_id
	check(game.name == "RugCleaningWindow" and game.paid_contract and not first_job.is_empty(), "Production cleaning is a distinct paid scene with a rug ready")
	check(not soil.automatic_completion_enabled, "Workshop owns the combined completion rule")
	check(game.hud.get_node_or_null("%LeftRail") == null and game.hud.get_node_or_null("%ToolRail") == null and game.hud.get_node_or_null("%CompletionCard") == null, "Legacy rails and completion prompt are absent")
	check(not game.finish_button.visible, "Untouched rug has no Finish button")

	set_cleanliness(game, 1.0, 0.84)
	check(game.state_label.text == "84%" and not game.finish_button.visible, "The bar uses the dirtier layer and stays locked below 85%")
	set_cleanliness(game, 0.85, 0.85)
	check(game.state_label.text == "85%" and game.finish_button.visible and not game.finish_button.disabled, "Finish job appears at 85%")

	state._save_enabled = false
	game.finish_contract()
	check(state.cash == 0 and state.manual_jobs == 0 and state.active_job_id == first_job, "A failed commit leaves the current rug and reward unchanged")
	check(not soil.completion_started and game.finish_button.visible, "A failed Finish can be retried")
	state._save_enabled = true
	game.finish_contract()
	var second_job: String = state.active_job_id
	check(state.cash == 20 and state.manual_jobs == 1 and not second_job.is_empty() and second_job != first_job, "Finish pays once and atomically reserves the next rug")
	check(game.contract_finished and soil.completion_started and not game.finish_button.visible, "Accepted Finish starts automatic takeaway")
	check(game.state_label.text == "100%" and game.progress_bar.value == 100.0, "Accepted cleanup fills the one progress bar during takeaway")
	game.finish_contract()
	game.finish_contract()
	check(not state.complete_job(first_job) and state.cash == 20 and state.manual_jobs == 1, "Repeated taps and the old job id cannot pay twice")

	# Re-enter before the old takeaway ends: the replacement is already durable.
	game.free()
	game = scene.instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	await process_frame
	soil = game.soil
	check(game.contract_job_id == second_job and game.progress_fraction == 0.0 and not soil.completion_started, "Restarting during takeaway opens the fresh reserved rug")
	set_cleanliness(game, 1.0, 0.989)
	check(game.state_label.text == "98%" and game.finish_button.visible and not soil.completion_started, "98% still leaves manual Finish available")
	set_cleanliness(game, 1.0, 0.99)
	await process_frame
	var third_job: String = state.active_job_id
	check(game.contract_finished and soil.completion_started, "99% automatically finishes without a tap")
	check(state.cash == 60 and state.manual_jobs == 2 and third_job != second_job, "99% completion pays double exactly once and reserves another rug")

	# The cleaning scene and its dirt batch are retained across jobs. This suite
	# skips presentation timing; the production transition suite exercises rolls.
	current_scene = game
	var scene_id: int = game.get_instance_id()
	var soil_id: int = soil.get_instance_id()
	var batch_id: int = soil.batch.get_instance_id()
	for _tick in 140:
		if soil.vacuum_complete:
			break
		soil._physics_process(1.0 / 60.0)
	await process_frame
	await process_frame
	game = current_scene
	check(game != null and game.get_instance_id() == scene_id, "Takeaway keeps the same cleaning scene instance")
	check(game.soil.get_instance_id() == soil_id and game.soil.batch.get_instance_id() == batch_id, "The next job reuses the same soil controller and GPU dirt pool")
	check(game.contract_job_id == third_job and not game.contract_finished and game.progress_fraction == 0.0, "The replacement rug is immediately ready to clean")
	check(game.hud.get_node_or_null("%NextRugButton") == null, "No new-rug prompt is present")
	state._save_enabled = false
	set_cleanliness(game, 1.0, 0.99)
	await process_frame
	await process_frame
	check(state.cash == 60 and state.active_job_id == third_job and not game.soil.completion_started, "A failed 99% auto-save keeps the current rug and never pays")
	check(game.finish_button.visible, "A failed automatic save exposes Finish for a manual retry instead of retrying every frame")
	state._save_enabled = true
	game.finish_contract()
	check(state.cash == 100 and state.manual_jobs == 3 and state.active_job_id != third_job, "Manual retry preserves the 99% double reward and completes exactly once")

	game.free()
	current_scene = null
	state.contract_mode = false
	var practice := (load("res://scenes/test/rug_cleaning_gym.tscn") as PackedScene).instantiate()
	practice.animate_rug_changes = false
	root.add_child(practice)
	await process_frame
	var cash_before: int = state.cash
	set_cleanliness(practice, 0.85, 0.85)
	practice.finish_contract()
	check(not practice.paid_contract and state.cash == cash_before, "The inherited test gym remains free practice")
	practice.free()
	state.set_process(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("CONTRACT CHECKS COMPLETE: ", failures, " failures; minimal HUD, 85% Finish, 99% auto, exact-once reward and immediate replacement rug.")
	quit(0 if failures == 0 else 1)
