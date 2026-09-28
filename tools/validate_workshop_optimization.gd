extends SceneTree
## Renderer-backed regression for cached progression and synchronous save safety.
## Run with the pinned wrapper and -- --shop-test; never against a player save.

const Rules = preload("res://scripts/progression.gd")
const CLEANING_SCENE := preload("res://scenes/production/rug_cleaning.tscn")

class InstrumentedWorkshop extends "res://scripts/workshop.gd":
	var progression_sync_calls := 0
	var snapshot_save_calls := 0

	func _sync_progression() -> void:
		progression_sync_calls += 1
		super._sync_progression()

	func save_contract_progress() -> bool:
		snapshot_save_calls += 1
		return super.save_contract_progress()

var checks := 0
var failures := 0
var state: Node
var game: Node
var save_path := ""


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test so this validation cannot touch player progress.")
		quit(2)
		return
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("WORKSHOP OPTIMIZATION: " + message)


func settle() -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func enter_cleaning() -> Node:
	var instance := CLEANING_SCENE.instantiate()
	# Keep the authored scene, children and production methods; only count the
	# two calls whose frequency this suite is intended to constrain.
	instance.set_script(InstrumentedWorkshop)
	instance.animate_rug_changes = false
	root.add_child(instance)
	current_scene = instance
	await settle()
	return instance


func leave_cleaning() -> void:
	if is_instance_valid(game):
		game.free()
	game = null
	current_scene = null


func read_save() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	return parsed if parsed is Dictionary else {}


func paint_water(position: Vector3) -> void:
	check(game.soil.apply_water_blob(position, 0.20, 0.35), "fixture changes real wet pixels")
	game.soil._process(0.0)


func check_progression_cache() -> void:
	var start_syncs: int = game.progression_sync_calls
	for step in 120:
		# Progress totals are independent of upgrade/economy state. Keep these
		# synthetic values below completion, then restore before save checks.
		game.soil.water_coverage_total = float(game.soil.surface_pixel_count) * float(step + 1) / 300.0
		game.update_contract_status()
	check(game.progression_sync_calls == start_syncs, "120 mask-only progress updates do not rebuild full progression")
	check(game.state_label.text == "20%" and is_equal_approx(game.progress_fraction, 0.20), "progress text and bar still update without rebuilding upgrade data")
	game.soil.water_coverage_total = 0.0
	game.update_contract_status()

	state.cash = 0
	state.changed.emit()
	check(game.progression_sync_calls > start_syncs, "ledger changed still refreshes progression immediately")
	check(not bool(game.cached_progression.can_upgrade_hose) and game.hud.control("ToolUpgradeButton").disabled, "wallet signal disables unaffordable upgrades")
	check(game.hud.displayed_gold == 0, "wallet signal updates the displayed cash")
	state.cash = 1000000
	state.changed.emit()
	check(bool(game.cached_progression.can_upgrade_hose) and not game.hud.control("ToolUpgradeButton").disabled, "later wallet signal enables affordable upgrades")

	var job_before: String = state.active_job_id
	var before_pixels: int = hash(game.soil.wet_mask.get_data())
	var price: int = state.progression_view().hose_cost
	var wallet: int = state.cash
	game._purchase_hose()
	check(state.cash == wallet - price and int(state._branch().hose_level) == 1, "hose purchase still charges the exact current price")
	check(game.hose_upgrade_level == 1 and is_equal_approx(game.hose_direct_power, float(state.progression_view().hose_power)), "purchase refreshes the live hose configuration")
	check(int(game.cached_progression.hose_level) == 1 and int(game.hud._progression.hose_level) == 1, "purchase refreshes both cached and displayed upgrade state")
	price = state.progression_view().squeegee_cost
	wallet = state.cash
	game._purchase_squeegee()
	check(state.cash == wallet - price and int(state._branch().squeegee_level) == 1, "squeegee purchase still charges independently")
	check(is_equal_approx(game.squeegee_power, float(state.progression_view().squeegee_power)), "purchase refreshes the live extraction strength")
	check(state.active_job_id == job_before and hash(game.soil.wet_mask.get_data()) == before_pixels, "upgrade refresh does not reset the job or wet mask")

	start_syncs = game.progression_sync_calls
	game.rug_phase = game.RugPhase.ARRIVING
	game.update_contract_status()
	check(game.progression_sync_calls == start_syncs + 1 and not game.cached_purchase_state, "leaving the cleaning phase refreshes purchase availability once")
	for _step in 12:
		game.update_contract_status()
	check(game.progression_sync_calls == start_syncs + 1, "unchanged non-cleaning phase does not repeat progression work")
	game.rug_phase = game.RugPhase.CLEANING
	game.update_contract_status()
	check(game.progression_sync_calls == start_syncs + 2 and game.cached_purchase_state, "returning to cleaning restores purchase availability")


func check_snapshot_safety() -> void:
	paint_water(Vector3(-0.45, 0.067, -0.55))
	await settle()
	game.queue_snapshot_save()
	check(not game.snapshot_timer.is_stopped(), "mask changes can schedule an autosave")
	check(game.save_contract_progress(), "explicit wet snapshot commits")
	check(game.snapshot_timer.is_stopped(), "explicit save cancels its pending timer")
	var saved_calls: int = game.snapshot_save_calls
	await create_timer(0.62).timeout
	check(game.snapshot_save_calls == saved_calls, "no duplicate timer save follows an explicit save")
	var disk: Dictionary = read_save()
	check(disk.get("active_job_id") == state.active_job_id and disk.get("job_snapshot", {}).get("water") == state.job_snapshot.water, "explicit save contains the current paid job and wet pixels")

	var disk_before := FileAccess.get_file_as_string(save_path)
	paint_water(Vector3(0.45, 0.067, -0.55))
	var expected: Dictionary = game.soil.make_snapshot()
	state._save_enabled = false
	game.queue_snapshot_save()
	check(not game.save_contract_progress(), "failed snapshot reports failure")
	check(not game.snapshot_timer.is_stopped() and game.contract_save_failed, "failed explicit save preserves the pending timer retry and exposes failure state")
	check(FileAccess.get_file_as_string(save_path) == disk_before, "failed write preserves the previous durable save")
	check(state.job_snapshot.water == expected.water and state.job_snapshot.extracted == expected.extracted, "failed write retains the latest rug pixels in memory")
	state._save_enabled = true
	game.queue_snapshot_save()
	check(game.save_contract_progress() and not game.contract_save_failed and game.snapshot_timer.is_stopped(), "explicit retry commits and clears failure state")
	check(read_save().get("job_snapshot", {}).get("water") == expected.water, "retry persists the retained latest pixels")

	paint_water(Vector3(-0.45, 0.067, 0.55))
	expected = game.soil.make_snapshot()
	game.brush_dragging = true
	game.end_stroke()
	check(not game.brush_dragging and game.snapshot_timer.is_stopped(), "release still saves immediately and cancels autosave")
	check(read_save().get("job_snapshot", {}).get("water") == expected.water, "release is durable before another frame")

	paint_water(Vector3(0.45, 0.067, 0.55))
	expected = game.soil.make_snapshot()
	game.brush_dragging = true
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not game.brush_dragging and read_save().get("job_snapshot", {}).get("water") == expected.water, "focus loss still ends the stroke and immediately persists its pixels")


func check_finish_and_exit() -> void:
	# Completion accounting is tested separately from mask geometry. The other
	# wet suites cover geometric extraction and save restoration in detail.
	game.soil.water_coverage_total = float(game.soil.surface_pixel_count)
	game.soil.extraction_coverage_total = float(game.soil.surface_pixel_count) * 0.50
	game.update_contract_status()
	check(game.finish_button.visible and is_equal_approx(game.progress_fraction, 0.75), "cached upgrade UI does not prevent the 75 percent Finish offer")
	var old_job: String = state.active_job_id
	var wallet: int = state.cash
	var jobs: int = state.manual_jobs
	var reward: int = state.reward_for_current_job(game.soil.make_progress_snapshot())
	state._save_enabled = false
	game.finish_rug()
	check(not game.contract_finished and game.contract_save_failed and not game.soil.completion_started, "failed reward commit leaves the rug available for retry")
	check(state.cash == wallet and state.manual_jobs == jobs and state.active_job_id == old_job, "failed reward commit changes neither wallet nor job identity")
	state._save_enabled = true
	game.finish_rug()
	check(game.contract_finished and state.cash == wallet + reward and state.manual_jobs == jobs + 1, "retry pays exactly one reward")
	check(state.active_job_id != old_job and game.snapshot_timer.is_stopped(), "accepted Finish durably reserves its replacement and cancels autosave")
	check(not game.cached_purchase_state and not game._can_purchase(), "accepted Finish disables purchases")
	game.finish_rug()
	game._purchase_hose()
	check(state.cash == wallet + reward and state.manual_jobs == jobs + 1, "repeat Finish and purchase calls during takeaway do nothing")
	var reserved_job: String = state.active_job_id
	leave_cleaning()

	game = await enter_cleaning()
	check(game.contract_job_id == reserved_job and not game.contract_finished and game.progress_fraction == 0.0, "re-entry opens the already reserved fresh rug")
	paint_water(Vector3(0.0, 0.067, 0.15))
	var expected: Dictionary = game.soil.make_snapshot()
	leave_cleaning()
	var saved: Dictionary = read_save()
	check(saved.get("active_job_id") == reserved_job and saved.get("job_snapshot", {}).get("water") == expected.water, "scene exit still saves the current rug without detached UI work")


func run() -> void:
	state = root.get_node("ShopState")
	state.set_process(false)
	state._test_ticks_msec = 0
	state._test_unix_time = 2000000.0
	save_path = "res://.godot/workshop_optimization_%d.json" % OS.get_process_id()
	state._save_path = save_path
	check(state.reset_progress(), "isolated ledger resets")
	state._sync_active_branch()
	state.stores["2"] = Rules.new_branch(2)
	state.active_store = 2
	state._load_active_branch()
	state.cash = 1000000
	check(not state.start_job().is_empty(), "isolated Store 2 job starts")
	game = await enter_cleaning()
	check(game.paid_contract and game.wet_recipe and game.selected_tool == 2, "instrumented scene uses the real paid hose-first workshop")
	check_progression_cache()
	await check_snapshot_safety()
	await check_finish_and_exit()
	state.set_process(false)
	for path: String in [save_path, save_path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("WORKSHOP_OPTIMIZATION_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
