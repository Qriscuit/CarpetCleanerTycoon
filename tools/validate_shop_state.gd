extends SceneTree
## Current manual ledger: durable jobs, progressive rewards and failure rollback.
const State := preload("res://scripts/shop_state.gd")
const Rules := preload("res://scripts/progression.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SHOP STATE: " + message)

func fresh(label: String) -> Node:
	var state := State.new()
	state._save_path = "res://.godot/manual_state_%d_%s.json" % [OS.get_process_id(),label]
	paths.append(state._save_path)
	root.add_child(state)
	return state

func reload_state(state: Node) -> Node:
	var path: String = state._save_path
	state.free()
	var next := State.new()
	next._save_path = path
	root.add_child(next)
	return next

func snapshot(fraction: float) -> Dictionary:
	return {"unique_clearance":fraction,"surface_clearance":fraction,"earned_clearance":fraction,"marker":"manual-work"}

func run() -> void:
	var state := fresh("jobs")
	check(state.cash == 0.0 and state.manual_jobs == 0 and state.stores.size() == 1 and state.active_store == 1, "A fresh save starts at Neighborhood with an empty wallet")
	check(state._valid_save(state._capture_state()), "A fresh current-schema ledger validates")
	check(not state.is_processing(), "The ledger has no idle production process")
	check(not state.complete_job("missing") and state.active_job_id.is_empty(), "Unknown job completion cannot pay")
	var job: String = state.start_job()
	check(not job.is_empty() and state.start_job() == job and state._job_serial == 1, "Repeated start reuses one durable reservation")
	for pair: Array in [[0.0,0.0],[0.7499,0.0],[0.75,20.0],[0.9899,20.0],[0.99,40.0],[1.0,40.0]]:
		check(state.reward_for_current_job(snapshot(float(pair[0]))) == float(pair[1]), "The starter quote respects early/full thresholds")
	check(state.record_cleaning_progress(job,snapshot(0.25)) == 5.0 and state.cash == 5.0, "Manual surface removal saves its first installment")
	check(state.record_cleaning_progress(job,snapshot(0.25)) == 0.0 and state.cash == 5.0, "Replaying an installment cannot pay twice")
	state = reload_state(state)
	check(state.active_job_id == job and state.cash == 5.0 and state.job_snapshot.marker == "manual-work", "Wallet, reservation, masks and watermark survive reload")
	check(state.record_cleaning_progress(job,snapshot(0.25)) == 0.0, "Reloading cannot reopen a paid installment")
	var before: Dictionary = state._capture_state()
	var disk := FileAccess.get_file_as_string(state._save_path)
	var path: String = state._save_path
	state._save_path += "/cannot-write.json"
	check(state.record_cleaning_progress(job,snapshot(0.5)) == -1.0 and state._capture_state() == before, "A real file-open failure restores wallet and cleaning snapshot")
	check(state.complete_and_start_next_job(job,snapshot(1.0)).is_empty() and state._capture_state() == before, "A failed completion preserves its current rug and unpaid reward")
	state._save_path = path
	check(FileAccess.get_file_as_string(path) == disk, "Failed transactions leave the durable ledger unchanged")
	var next_job: String = state.complete_and_start_next_job(job,snapshot(1.0))
	check(not next_job.is_empty() and next_job != job and state.cash == 40.0 and state.manual_jobs == 1, "Retry settles exactly one full carpet and reserves its replacement atomically")
	check(state.completed_rewards[job].amount == 40.0 and state.job_snapshot.is_empty(), "Completion records the full job value and starts fresh masks")
	check(state.complete_and_start_next_job(job,snapshot(1.0)).is_empty() and state.cash == 40.0, "The prior job ID cannot pay again")
	check(state.save_job_snapshot(snapshot(0.75)) and state.complete_job(next_job) and state.cash == 60.0 and state.active_job_id.is_empty(), "Early completion settles exactly its half quote")
	state = reload_state(state)
	check(state.cash == 60.0 and state.manual_jobs == 2 and state.active_job_id.is_empty(), "Cold reload retains completed earnings without reserving or paying another rug")
	job = state.start_job()
	for malformed: Dictionary in [{"unique_clearance":NAN,"surface_clearance":0.5},{"unique_clearance":0.5,"surface_clearance":INF},{"unique_clearance":1.1,"surface_clearance":0.5},{"unique_clearance":0.5,"surface_clearance":0.5,"earned_clearance":0.8},{"unique_clearance":0.5,"surface_clearance":0.5,"rug_id":"missing"}]:
		before = state._capture_state()
		check(state.record_cleaning_progress(job,malformed) == -1.0 and state._capture_state() == before, "Malformed work cannot alter a reservation or wallet")
	var valid: Dictionary = state._capture_state()
	for amount: Variant in [NAN,INF,-1.0,0.5,Rules.MAX_MONEY*2.0]:
		var invalid := valid.duplicate(true)
		invalid.cash = amount
		check(not state._valid_save(invalid), "Invalid money cannot be loaded")
	state.cash = Rules.MAX_MONEY
	check(state.save_state(), "The supported wallet maximum saves")
	check(state.complete_and_start_next_job(job,snapshot(1.0)).is_empty() and state.cash == Rules.MAX_MONEY, "A full wallet cannot destroy an unpaid completion")
	state.cash = 0.0
	check(not state.complete_and_start_next_job(job,snapshot(1.0)).is_empty() and state.cash == 40.0, "Completion retries once wallet space exists")
	check(state.set_appearance("mint","beanie"), "The free appearance can be selected before reset")
	before = state._capture_state()
	state._save_path += "/cannot-write.json"
	check(not state.reset_progress() and state._capture_state() == before, "A failed reset keeps all current progress and appearance")
	state._save_path = path
	check(state.reset_progress() and state.cash == 0.0 and state.manual_jobs == 0 and state.stores.size() == 1 and state.appearance == {"color_id":"orange","hat_id":"none"}, "A durable reset restores the new free starter state")
	state.free()
	for saved: String in paths:
		for suffix: String in ["", ".tmp"]:
			if FileAccess.file_exists(saved+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(saved+suffix))
	print("SHOP_STATE_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
