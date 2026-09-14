extends SceneTree
## Run with --headless --path CarpetToy --script ../tools/validate_shop_state.gd -- --shop-test

const State := preload("res://scripts/shop_state.gd")
var _paths: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		printerr("Refusing to run without --shop-test: real player saves must remain untouched.")
		quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	var state := _new_state("main")
	_check(state.cash == 0 and state.owns("hand_brush") and state.output_per_hour() == 0.0, "Free shop starts without routine income")
	_check(state.equipped_brush == "hand_brush", "Free starter brush is equipped by default")
	_check(not state.equip_brush("wide_brush") and not state.equip_brush("bonzi") and not state.equip_brush("unknown") and state.equipped_brush == "hand_brush", "Only owned personal brushes can be equipped")
	_check(not state.build("bonzi") and not state.build("unknown"), "Locked and unknown builds are rejected")
	var first: String = state.start_job()
	_check(not first.is_empty() and state.start_job() == first, "One resumable active job")
	_check(not state.complete_job(first), "Uncleaned carpet does not pay")
	state.save_job_snapshot({"unique_clearance": 0.95, "surface_clearance": 0.89, "pixels": [1, 2, 3]})
	_check(not state.complete_job(first), "Both clearance thresholds are required")
	state.save_job_snapshot({"unique_clearance": 0.9, "surface_clearance": 0.9, "pixels": [1, 2, 3]})
	state = _reload(state)
	_check(state.active_job_id == first and state.job_snapshot["pixels"].size() == 3, "Active carpet persists across reload")
	_check(state.complete_job(first) and state.cash == 20 and state.manual_jobs == 1, "Saved eligible carpet pays 20")
	_check(not state.complete_job(first) and state.cash == 20, "Repeated reward is rejected")
	for _job in range(2):
		_finish_one(state)
	_check(state.blueprint_known("bonzi") and not state.owns("bonzi") and state.cash == 60, "Bonzi blueprint is permanent permission at three jobs")
	_check(not state.build("bonzi") and state.cash == 60, "Unaffordable blueprint cannot be built")
	for _job in range(2):
		_finish_one(state)
	_advance(state, 10000.0)
	_check(state.build("bonzi") and state.cash == 0 and state.output_per_hour() == 30.0, "Bonzi starts at purchase, with no earlier catch-up")
	_check(not state.build("bonzi") and state.cash == 0, "Duplicate purchases do not charge")
	_advance(state, 60.0)
	_check(state.save_state() and state.cash == 0 and is_equal_approx(state.routine_remainder, 0.5), "Only whole automated deliveries pay")
	_check(is_equal_approx(state.seconds_to_delivery(), 60.0), "Delivery countdown uses remaining order fraction")
	state = _reload(state)
	_check(is_equal_approx(state.routine_remainder, 0.5), "Fractional routine order survives a reload")
	_advance(state, 60.0)
	state.save_state()
	_check(state.cash == 10 and state.automated_jobs == 1, "One full order gives ten cash")
	for _job in range(5):
		_finish_one(state)
	_check(state.blueprint_known("wide_brush") and state.blueprint_known("bonzi_mk2") and state.blueprint_known("intake"), "Job milestones reveal starter tools and modules")
	# At 110 cash, the final old-rate delivery makes Mk II affordable before the debit.
	_advance(state, 120.0)
	_check(state.build("bonzi_mk2") and state.cash == 0 and state.automated_jobs == 2, "Rate change settles old output before charging")
	_check(state.capacity_per_hour() == 45.0 and state.output_per_hour() == 40.0 and state.bottleneck() == "Customer demand", "Mk II is demand-limited at forty orders/hour")
	_advance(state, 45.0)
	state.save_state()
	_check(is_equal_approx(state.routine_remainder, 0.5), "New output applies only after installation")
	for _job in range(5):
		_finish_one(state)
	_check(state.build("intake") and state.output_per_hour() == 45.0, "Intake unlocks remaining Mk II capacity")
	var pre_offline_cash: int = state.cash
	var pre_offline_jobs: int = state.automated_jobs
	state = _reload(state, 12.0 * 3600.0)
	_check(state.cash == pre_offline_cash + 3600 and state.automated_jobs == pre_offline_jobs + 360, "Twelve hours away credits the eight-hour cap")
	_check(is_equal_approx(state.routine_remainder, 0.5) and is_equal_approx(state.return_seconds, 28800.0), "Offline cap preserves the half-finished order")
	_check(state.return_reward == 3600, "Return summary describes cash already credited")
	state = _reload(state)
	_check(state.cash == pre_offline_cash + 3600 and state.return_reward == 3600, "Reopening the return panel cannot pay twice")
	_check(state.acknowledge_return() and state.return_reward == 0 and state.cash == pre_offline_cash + 3600, "Acknowledgement clears only the summary")
	state = _reload(state)
	_check(state.return_reward == 0, "Acknowledgement survives reload")
	var before_backward: int = state.cash
	state = _reload(state, -3600.0)
	_check(state.cash == before_backward, "Backward wall clock awards no offline time")
	_advance(state, 3600.0)
	state.save_state()
	_check(state.cash == before_backward + 450, "Online production follows elapsed monotonic time")
	_check(state.build("wide_brush") and state.owns("wide_brush"), "The optional personal tool can be built")
	_check(state.equipped_brush == "wide_brush", "Building the wider brush equips its benefit immediately")
	state = _reload(state)
	_check(state.equipped_brush == "wide_brush", "New brush selection persists after building")
	var before_equip_cash: int = state.cash
	_check(state.equip_brush("hand_brush") and state.cash == before_equip_cash, "Owned brushes can be swapped without spending cash")
	state = _reload(state)
	_check(state.equipped_brush == "hand_brush" and state.owns("wide_brush"), "Selected starter brush survives reload while the wider brush remains owned")
	var equipped_path: String = state._save_path
	state._save_path += "/cannot-write.json"
	_check(not state.equip_brush("wide_brush") and state.equipped_brush == "hand_brush", "Failed equipment save preserves the previous selection")
	state._save_path = equipped_path
	_check(state.equip_brush("wide_brush") and state.equip_brush("wide_brush") and state.cash == before_equip_cash, "Repeated equip taps are harmless and keep the wider brush selected")
	_check(not state.build("wide_brush"), "The personal tool cannot be duplicated")
	var pre_pause_cash: int = state.cash
	state._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_advance(state, 12.0 * 3600.0)
	state._process(12.0 * 3600.0)
	_check(state.cash == pre_pause_cash, "Suspended app does not count absence as live production")
	state._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check(state.cash == pre_pause_cash + 3600 and state.return_reward == 3600, "Suspending and returning uses the same eight-hour absence cap")
	state.acknowledge_return()
	var main_path: String = state._save_path
	state._save_path = main_path + "/missing-folder/save.json"
	var before_failed_cash: int = state.cash
	var before_failed_jobs: int = state.manual_jobs
	_check(state.start_job().is_empty() and state.active_job_id.is_empty(), "Failed save rolls back new jobs")
	state._save_path = main_path
	var pending: String = state.start_job()
	state.save_job_snapshot({"unique_clearance": 1.0, "surface_clearance": 1.0})
	state._save_path = main_path + "/missing-folder/save.json"
	_check(not state.complete_job(pending) and state.cash == before_failed_cash and state.manual_jobs == before_failed_jobs and state.active_job_id == pending, "Failed commit rolls back cash, count and the active job")
	state._save_path = main_path
	state.free()
	# Intake before Mk II is allowed, and honestly yields no immediate rate increase.
	var intake_first := _new_state("intake_first")
	for _job in range(15):
		_finish_one(intake_first)
	_check(intake_first.build("bonzi") and intake_first.build("intake") and intake_first.output_per_hour() == 30.0, "Intake does not bypass the cleaner bottleneck")
	var before_build: int = intake_first.cash
	intake_first._save_path += "/cannot-write.json"
	_check(not intake_first.build("wide_brush") and not intake_first.owns("wide_brush") and intake_first.cash == before_build and intake_first.equipped_brush == "hand_brush", "Failed purchase preserves cash, ownership and equipment")
	intake_first.free()
	# Additive version-1 migration preserves the pre-selector equipment behavior.
	var legacy := _new_state("legacy_equipment")
	_check(legacy.save_state(), "Legacy fixture begins with a valid ledger")
	_remove_equipment_field(legacy._save_path)
	legacy = _reload(legacy)
	_check(legacy.equipped_brush == "hand_brush", "Legacy starter save migrates to its free hand brush")
	for _job in range(8):
		_finish_one(legacy)
	_check(legacy.build("wide_brush"), "Legacy wider-brush fixture is earned and built")
	_remove_equipment_field(legacy._save_path)
	legacy = _reload(legacy)
	_check(legacy.equipped_brush == "wide_brush", "Legacy save with an owned wide brush retains that equipped benefit")
	_check(JSON.parse_string(FileAccess.get_file_as_string(legacy._save_path)).get("equipped_brush") == "wide_brush", "Migrated equipment is written back to disk")
	for invalid_selection: Variant in ["jet_spray", 42, {"not": "an item"}]:
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(legacy._save_path))
		fixture["equipped_brush"] = invalid_selection
		_write_fixture(legacy._save_path, fixture)
		legacy = _reload(legacy)
		_check(legacy.equipped_brush == "hand_brush" and legacy.owns("wide_brush"), "Invalid saved equipment falls back safely without losing owned tools")
	legacy.free()
	var unowned := _new_state("unowned_equipment")
	unowned.save_state()
	var unowned_fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(unowned._save_path))
	unowned_fixture["equipped_brush"] = "wide_brush"
	_write_fixture(unowned._save_path, unowned_fixture)
	unowned = _reload(unowned)
	_check(unowned.equipped_brush == "hand_brush" and not unowned.owns("wide_brush"), "Saved equipment cannot grant an unowned tool")
	unowned.free()
	# Preserve unknown future data instead of silently starting over and overwriting it.
	var invalid_path := _path("invalid")
	var invalid := FileAccess.open(invalid_path, FileAccess.WRITE)
	invalid.store_string('{"version":999}')
	invalid.close()
	var broken := _new_state("invalid")
	_check(not broken.save_state() and FileAccess.get_file_as_string(invalid_path) == '{"version":999}', "Unsupported save versions remain untouched")
	broken.free()
	for path in _paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(path + ".tmp"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	print("VERIFIED: ", _checks, " shop ledger checks; save/resume, brush selection/migration, thresholds, one-time rewards/builds, production, offline cap, bottlenecks and failure rollback.")
	quit(0)


func _new_state(suffix: String) -> Node:
	var state := State.new()
	state._save_path = _path(suffix)
	state._test_ticks_msec = 0
	state._test_unix_time = 1800000000.0
	root.add_child(state)
	state.set_process(false)
	return state


func _path(suffix: String) -> String:
	var path := "res://.godot/shop_validation_%d_%s.json" % [OS.get_process_id(), suffix]
	if not path in _paths:
		_paths.append(path)
	return path


func _reload(old: Node, away_seconds: float = 0.0) -> Node:
	var state := State.new()
	state._save_path = old._save_path
	state._test_ticks_msec = 0
	state._test_unix_time = old._test_unix_time + away_seconds
	old.free()
	root.add_child(state)
	state.set_process(false)
	return state


func _advance(state: Node, seconds: float) -> void:
	state._test_ticks_msec += int(seconds * 1000.0)
	state._test_unix_time += seconds


func _finish_one(state: Node) -> void:
	var id: String = state.start_job()
	_check(state.save_job_snapshot({"unique_clearance": 1.0, "surface_clearance": 1.0}) and state.complete_job(id), "Complete an eligible manual commission")


func _remove_equipment_field(path: String) -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	fixture.erase("equipped_brush")
	_write_fixture(path, fixture)


func _write_fixture(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		printerr("FAILED: ", message)
		quit(1)
		assert(false, message)
