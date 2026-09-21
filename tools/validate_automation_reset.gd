extends SceneTree
const State = preload("res://scripts/shop_state.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func fresh(suffix: String) -> Node:
	var state := State.new()
	state._save_path = "res://.godot/automation_reset_%d_%s.json" % [OS.get_process_id(),suffix]
	paths.append(state._save_path)
	state._test_unix_time = 1800000000.0
	state._test_ticks_msec = 0
	root.add_child(state)
	state.set_process(false)
	state.cash = 500
	state.manual_jobs = 10
	state._refresh_blueprints()
	check(state.build("bonzi"), "Build Bonzi fixture")
	return state

func advance(state: Node, seconds: float, sleep := false) -> void:
	state._test_unix_time += seconds
	if not sleep: state._test_ticks_msec += roundi(seconds * 1000.0)

func run() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		quit(2)
		return
	var state := fresh("sleep")
	for interval: int in [120,90,80]:
		var before: int = state.cash
		advance(state,interval-1)
		state._process(0.0)
		check(state.cash == before, "No early payment before %ds bar finishes" % interval)
		advance(state,1)
		state._process(0.0)
		check(state.cash == before+10 and state.seconds_to_delivery() == interval, "Exactly ten coins per completed %ds bar" % interval)
		if interval == 120: check(state.build("bonzi_mk2"), "Install Mk II")
		elif interval == 90: check(state.build("intake"), "Install intake")
	var before_sleep: int = state.cash
	state._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	advance(state,160,true)
	state._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	state._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(state.cash == before_sleep+20 and state.return_reward == 20, "Device sleep earns two bars even with a stopped live clock")
	state._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	state._process(0.0)
	check(state.cash == before_sleep+20, "Repeated resume and next frame do not pay twice")
	check(state.acknowledge_return() and state.cash == before_sleep+20 and state.return_reward == 0, "Away acknowledgement grants no extra coins")
	var before_cap: int = state.cash
	state._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	advance(state,12*3600,true)
	var path: String = state._save_path
	state._save_path += "/cannot-write.json"
	state._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(state.cash == before_cap and state.return_reward == 0, "Failed resume save rolls back coins and summary")
	state._process(0.0)
	check(state.cash == before_cap and state.return_reward == 0, "Failed retry also keeps summary unchanged")
	state._save_path = path
	state._process(0.0)
	check(state.cash == before_cap+3600 and state.return_reward == 3600 and state.return_seconds == 28800, "Successful retry pays only the eight-hour cap once")
	state._process(0.0)
	check(state.cash == before_cap+3600, "Discarded hours cannot leak into the next live frame")
	advance(state,80)
	state._process(0.0)
	check(state.cash == before_cap+3610, "Live production restarts at the normal bar length")
	check(state.build("wide_brush"), "Own an equipped tool before resetting")
	check(not state.start_job().is_empty(), "Have an active job before resetting")
	state.save_job_snapshot({"unique_clearance":0.5,"surface_clearance":0.5})
	var before_reset: Dictionary = state._capture_state()
	var disk_before := FileAccess.get_file_as_string(path)
	state._save_path += "/cannot-write.json"
	check(not state.reset_progress() and state._capture_state() == before_reset, "Failed reset restores all progress")
	check(FileAccess.get_file_as_string(path) == disk_before, "Failed reset leaves the previous save intact")
	state._save_path = path
	check(state.reset_progress(), "Confirmed reset commits")
	check(state.cash == 0 and state.manual_jobs == 0 and state.automated_jobs == 0 and state.routine_remainder == 0.0, "Reset clears coins, milestones and fractional automation")
	check(state._owned == {"hand_brush":true} and state._blueprints == {"hand_brush":true} and state.equipped_brush == "hand_brush", "Reset restores only the free starter brush")
	check(state.active_job_id.is_empty() and state.job_snapshot.is_empty() and state.return_reward == 0 and state.return_seconds == 0.0, "Reset clears the rug and away summary")
	advance(state,86400)
	state._process(0.0)
	check(state.cash == 0 and state.automated_jobs == 0, "Old Bonzi cannot earn after reset")
	var reloaded := State.new()
	reloaded._save_path = path
	reloaded._test_unix_time = state._test_unix_time+86400
	reloaded._test_ticks_msec = 0
	state.free()
	root.add_child(reloaded)
	reloaded.set_process(false)
	check(reloaded.cash == 0 and not reloaded.owns("bonzi") and reloaded.active_job_id.is_empty(), "Reset survives reopening without old earnings")
	reloaded.free()
	var late := fresh("late_save")
	var late_cash: int = late.cash
	var late_path: String = late._save_path
	late._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	advance(late,120,true)
	late._save_path += "/cannot-write.json"
	late._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	late._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	late._save_path = late_path
	check(late.save_state() and late.cash == late_cash+10, "Late paused save can retry the previous absence without losing it")
	advance(late,120,true)
	late._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(late.cash == late_cash+20 and late.return_reward == 20, "Second absence pays separately without duplicating the earlier retry")
	late._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	advance(late,-120,true)
	late._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(late.cash == late_cash+20, "Backward wall-clock change grants no suspended income")
	advance(late,120)
	late._process(0.0)
	check(late.cash == late_cash+30, "Live bar still pays normally after a backward wall-clock change")
	late.free()
	for file_path: String in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	print("AUTOMATION_RESET_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
