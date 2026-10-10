extends SceneTree
## Progressive cleaning coins and restoration settlement use disposable ledgers.
const State := preload("res://scripts/shop_state.gd")
const Rules := preload("res://scripts/progression.gd")
const Room := preload("res://scripts/room_upgrades.gd")
const Soil := preload("res://scripts/dirt_controller.gd")
const Workshop := preload("res://scripts/workshop.gd")
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
		push_error("SPLIT LEDGER: " + message)

func fresh(label: String) -> Node:
	var state := State.new()
	state._save_path = "res://.godot/split_ledger_%d_%s.json" % [OS.get_process_id(),label]
	paths.append(state._save_path)
	state._test_ticks_msec = 0
	state._test_unix_time = 1800000000.0
	root.add_child(state)
	state.set_process(false)
	check(state.reset_progress(), "A disposable ledger resets")
	return state

func reload_state(state: Node) -> Node:
	var replacement := State.new()
	replacement._save_path = state._save_path
	replacement._test_ticks_msec = state._test_ticks_msec
	replacement._test_unix_time = state._test_unix_time
	state.free()
	root.add_child(replacement)
	replacement.set_process(false)
	check(replacement._save_enabled, "The saved split ledger reloads")
	return replacement

func snapshot(progress: float, eligible: float = -1.0) -> Dictionary:
	var result := {"unique_clearance":progress,"surface_clearance":progress,"mask_marker":"real-work"}
	if eligible >= 0.0: result.earned_clearance = eligible
	return result

func check_dry_and_full() -> void:
	var state := fresh("full")
	var job: String = state.start_job()
	var before: Dictionary = state._capture_state()
	check(state.current_job_full_reward() == 40.0 and state.preview_cleaning_reward(job,snapshot(0.25)) == 5.0, "A quarter of the carpet previews whole coins from its cleaning half")
	check(state._capture_state() == before, "Reward preview never changes wallet, dirt or paid marks")
	check(state.record_cleaning_progress(job,snapshot(0.25)) == 5.0 and state.cash == 5.0, "Progress commits coins and its snapshot together")
	check(state.job_snapshot.mask_marker == "real-work" and state._branch().job_cleaning_paid == 5.0 and state._branch().job_cleaning_progress == 0.25, "The paid amount and watermark share the saved rug")
	check(state.record_cleaning_progress(job,snapshot(0.25)) == 0.0 and state.cash == 5.0, "A repeated snapshot never pays again")
	check(state.record_cleaning_progress(job,snapshot(0.60,0.25)) == 0.0, "Material still visible on screen can save cleaning without earning early")
	check(state.record_cleaning_progress(job,snapshot(0.60,0.50)) == 5.0 and state.cash == 10.0, "The disappearance watermark unlocks only newly eligible coins")
	state = reload_state(state)
	check(state.active_job_id == job and state.record_cleaning_progress(job,snapshot(0.60,0.50)) == 0.0 and state.cash == 10.0, "Reload and replay retain already-paid cleaning")
	check(state.record_cleaning_progress(job,snapshot(0.99)) == 10.0 and state.cash == 20.0, "99% exhausts exactly the first half")
	check(state.reward_for_current_job(snapshot(0.99)) == 20.0 and state.current_job_full_reward() == 40.0, "The remaining restoration payment is separate from the total quote")
	var next: String = state.complete_and_start_next_job(job,snapshot(0.99))
	check(not next.is_empty() and next != job and state.cash == 40.0, "Cleaning and restoration together pay exactly the unchanged full quote")
	check(state.completed_rewards[job].amount == 40.0 and state.reward_offer().amount == 40.0, "The ad offer records the entire job's earnings, not its remaining payment")
	check(state._branch().job_cleaning_paid == 0.0 and state._branch().job_cleaning_progress == 0.0, "The replacement carpet starts with fresh payment marks")
	check(state.record_cleaning_progress(job,snapshot(1.0)) == -1.0 and state.complete_and_start_next_job(job,snapshot(1.0)).is_empty() and state.cash == 40.0, "A completed job ID cannot pay cleaning or settlement again")
	state.free()

func check_early() -> void:
	var state := fresh("early")
	var job: String = state.start_job()
	check(state.record_cleaning_progress(job,snapshot(0.75)) == 15.0 and state.reward_for_current_job(snapshot(0.75)) == 5.0, "Early75% earns proportional cleaning and settles the remaining cleaning half")
	check(not state.complete_and_start_next_job(job,snapshot(0.75)).is_empty() and state.cash == 20.0 and state.manual_jobs == 1, "Early settlement totals exactly the20 half quote once")
	check(state.completed_rewards[job].amount == 20.0, "Early history includes both earlier coins and the remaining half settlement")
	state = reload_state(state)
	check(state.cash == 20.0 and state.manual_jobs == 1, "Early completion survives reload without another payment")
	job = state.start_job()
	check(state.save_job_snapshot(snapshot(0.75)) and state.complete_job(job) and state.cash == 40.0 and state.active_job_id.is_empty(), "The no-replacement completion API settles the complete first half")
	job = state.start_job()
	check(not state.complete_and_start_next_job(job,snapshot(0.75,0.0)).is_empty(), "A valid early exit can finish before any material is eligible")
	check(state.completed_rewards[job].amount == 20.0 and state.cash == 60.0, "Early Finish pays the half quote even before deferred material disappearance pays installments")
	state = reload_state(state)
	check(state.cash == 60.0 and state._save_enabled, "The early half settlement remains a valid durable save")
	state.free()

func check_failures_and_validation() -> void:
	var state := fresh("failures")
	var job: String = state.start_job()
	check(state.record_cleaning_progress(job,snapshot(0.20)) == 4.0, "The failure fixture earns a first installment")
	var before: Dictionary = state._capture_state()
	var disk := FileAccess.get_file_as_string(state._save_path)
	state._save_enabled = false
	check(state.record_cleaning_progress(job,snapshot(0.5)) == -1.0 and state._capture_state() == before and FileAccess.get_file_as_string(state._save_path) == disk, "Disabled writes roll back wallet, masks and payment marks")
	state._save_enabled = true
	var real_path: String = state._save_path
	state._save_path = "res://.godot/split_missing_%d/ledger.json" % OS.get_process_id()
	check(state.record_cleaning_progress(job,snapshot(0.5)) == -1.0 and state._capture_state() == before, "A real file-open failure rolls back the entire installment")
	state._save_path = real_path
	for invalid: Dictionary in [{"unique_clearance":NAN,"surface_clearance":0.5},snapshot(0.5,0.6),{"unique_clearance":0.5,"surface_clearance":INF},{"unique_clearance":0.5,"surface_clearance":0.5,"earned_clearance":-0.1},{"unique_clearance":0.5,"surface_clearance":0.5,"rug_id":"wrong-rug"}]:
		check(state.preview_cleaning_reward(job,invalid) == -1.0 and state.record_cleaning_progress(job,invalid) == -1.0 and state._capture_state() == before, "Invalid progress cannot alter a saved installment")
	for field: String in ["earned_clearance", "cleaning_pending_clearance"]:
		for invalid: Variant in [NAN, INF, -0.1, 0.6, "0.5"]:
			var malformed := snapshot(0.5)
			malformed[field] = invalid
			check(state.preview_cleaning_reward(job,malformed) == -1.0 and state.record_cleaning_progress(job,malformed) == -1.0 and not state.save_job_snapshot(malformed) and state._capture_state() == before and FileAccess.get_file_as_string(state._save_path) == disk, "Malformed optional payment progress preserves wallet, masks and durable bytes")
	state._branch().bonzi_tier = 0
	state.save_state()
	state._test_ticks_msec += 120000
	state._test_unix_time += 120.0
	state._save_enabled = false
	var old_ticks: int = state._last_ticks
	check(state.record_cleaning_progress(job,snapshot(0.5)) == -1.0 and state.cash == 4.0 and state.automated_jobs == 0 and state._last_ticks == old_ticks, "Failed progress also rolls back independently elapsed Bonzi delivery")
	state._save_enabled = true
	check(state.record_cleaning_progress(job,snapshot(0.5)) == 6.0 and state.cash == 50.0 and state.automated_jobs == 1, "Retry pays the cleaning delta and the unchanged timed Bonzi order once")
	state._save_enabled = false
	before = state._capture_state()
	check(state.complete_and_start_next_job(job,snapshot(1.0)).is_empty() and state._capture_state() == before, "Failed restoration settlement preserves the job, wallet and already-paid half")
	state._save_enabled = true
	state._branch().bonzi_tier = -1
	state.cash = Rules.MAX_MONEY
	state.save_state()
	before = state._capture_state()
	check(state.record_cleaning_progress(job,snapshot(0.75)) == -1.0 and state._capture_state() == before, "The wallet limit cannot discard an unpaid installment")
	state.cash = 0.0
	state.save_state()
	check(state.record_cleaning_progress(job,snapshot(0.75)) == 5.0, "An installment retries after wallet space becomes available")
	state.free()

func check_travel_upgrade_migration() -> void:
	var state := fresh("travel")
	var job: String = state.start_job()
	state.record_cleaning_progress(job,snapshot(0.5))
	state.stores["2"] = Rules.new_branch(2)
	check(state.select_store(2), "An owned next store can be visited")
	var second: String = state.start_job()
	check(state.record_cleaning_progress(second,snapshot(0.25)) == 50505.0, "A second store has its own scaled cleaning installment")
	check(state.select_store(1) and state.active_job_id == job and state.record_cleaning_progress(job,snapshot(0.5)) == 0.0 and state._branch().job_cleaning_paid == 10.0, "Travel restores the first rug's independent paid watermark")
	state.cash = 1000.0
	state.save_state()
	check(state.buy_room_upgrade("floor") and state.current_job_full_reward() == 46.0, "A room renovation keeps the active quote live")
	var after_buy: float = state.cash
	check(state.record_cleaning_progress(job,snapshot(0.5)) == 0.0 and state.cash == after_buy, "Upgrading and replaying the same work cannot cause retroactive payout")
	check(state.record_cleaning_progress(job,snapshot(0.501)) == 1.0, "New work after an upgrade catches up to the new first-half rate")
	check(state.reward_for_current_job(snapshot(0.99)) == 35.0 and not state.complete_and_start_next_job(job,snapshot(0.99)).is_empty() and state.cash == 996.0, "Full restoration after renovation pays the new quote minus every earlier installment")
	state.free()
	state = fresh("migration")
	job = state.start_job()
	state.cash = 1234.0
	state.save_job_snapshot(snapshot(0.5))
	var legacy: Dictionary = state._capture_state()
	for key: String in legacy.stores:
		legacy.stores[key].erase("job_cleaning_paid")
		legacy.stores[key].erase("job_cleaning_progress")
	var file := FileAccess.open(state._save_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy,"",true,true))
	file.close()
	state = reload_state(state)
	check(state.active_job_id == job and state.cash == 1234.0 and state.job_snapshot.mask_marker == "real-work" and state._branch().job_cleaning_paid == 0.0, "An old unfinished save adds accounting without replacing wallet, job or masks")
	check(state.record_cleaning_progress(job,state.job_snapshot) == 10.0, "Previously unpaid saved work remains eligible under the additive migration")
	var fixture: Dictionary = state._capture_state()
	for invalid: Variant in [-1.0,10.5,NAN,INF,21.0,"10"]:
		var bad := fixture.duplicate(true)
		bad.stores["1"].job_cleaning_paid = invalid
		check(not state._valid_save(bad), "Saved payment marks reject invalid currency")
	for invalid: Variant in [-0.1,1.01,NAN,INF,"0.5"]:
		var bad := fixture.duplicate(true)
		bad.stores["1"].job_cleaning_progress = invalid
		check(not state._valid_save(bad), "Saved progress watermarks reject invalid fractions")
	for field: String in ["earned_clearance", "cleaning_pending_clearance"]:
		for invalid: Variant in [NAN, INF, -0.1, 0.6, "0.5"]:
			var bad := fixture.duplicate(true)
			bad.job_snapshot[field] = invalid
			check(not state._valid_save(bad), "The active snapshot mirror rejects malformed payment progress")
			bad = fixture.duplicate(true)
			bad.stores["1"].job_snapshot[field] = invalid
			check(not state._valid_save(bad), "Saved branch snapshots reject malformed payment progress")
	var valid := fixture.duplicate(true)
	valid.job_snapshot.earned_clearance = 0.5
	valid.job_snapshot.cleaning_pending_clearance = 0.5
	valid.stores["1"].job_snapshot = valid.job_snapshot.duplicate(true)
	check(state._valid_save(valid), "Valid optional payment marks retain additive save compatibility")
	state.free()
	for pair: Array in [["cleaning_pending_clearance", NAN], ["earned_clearance", -0.1], ["cleaning_pending_clearance", 0.6]]:
		state = fresh("malformed_%d" % checks)
		state.start_job()
		state.record_cleaning_progress(state.active_job_id,snapshot(0.5))
		var bad: Dictionary = state._capture_state()
		bad.stores["1"].job_snapshot[pair[0]] = pair[1]
		var corrupt_bytes := JSON.stringify(bad, "", true, true)
		file = FileAccess.open(state._save_path, FileAccess.WRITE)
		file.store_string(corrupt_bytes)
		file.close()
		var rejected := State.new()
		rejected._save_path = state._save_path
		rejected._test_ticks_msec = 0
		rejected._test_unix_time = 1800000000.0
		state.free()
		root.add_child(rejected)
		rejected.set_process(false)
		check(not rejected._save_enabled and rejected.cash == 0.0 and FileAccess.get_file_as_string(rejected._save_path) == corrupt_bytes, "Reload refuses malformed payment progress without credit or replacing the original file")
		rejected.free()

func wet_snapshot(skip: bool, cycle: int, water: float, extraction: float) -> Dictionary:
	return {"unique_clearance":0.0 if skip else 1.0,"surface_clearance":0.0 if skip else 1.0,"wet_recipe":true,"skip_dry_stage":skip,"wash_cycle_count":3,"wash_cycle":cycle,"water_clearance":water,"extraction_clearance":extraction}

func check_wet_and_large() -> void:
	var state := fresh("wet_math")
	state.active_store = Rules.WET_FIRST_STORE
	for water: float in [0.0,0.25,0.75,1.0]:
		check(state.cleaning_clearance_for_snapshot(wet_snapshot(true,0,water,0.0)) == 0.0, "Pouring water alone grants no cleaning coins")
	check(is_equal_approx(state.cleaning_clearance_for_snapshot(wet_snapshot(true,0,1.0,0.60)),0.20), "Only extraction contributes to the water-only recipe's cleaning half")
	check(state.cleaning_clearance_for_snapshot(wet_snapshot(true,1,0.0,0.0)) == 0.33, "A retired cycle carries its cumulative removal into the next rinse")
	check(state.cleaning_clearance_for_snapshot(wet_snapshot(true,2,1.0,1.0)) == 0.99, "All three removal cycles reach the cleaning-half cap")
	for cycle: int in [0, 1]:
		var before_transition: float = state.cleaning_clearance_for_snapshot(wet_snapshot(true,cycle,1.0,1.0))
		var after_transition: float = state.cleaning_clearance_for_snapshot(wet_snapshot(true,cycle+1,0.0,0.0))
		check(before_transition == after_transition, "Water-only extraction overshoot preserves eligible work when the next rinse starts")
	check(state.cleaning_clearance_for_snapshot(wet_snapshot(true,0,0.5,0.1)) == -1.0, "Extraction before sufficient soaking is invalid")
	state.active_store += 1
	check(state.cleaning_clearance_for_snapshot(wet_snapshot(false,0,1.0,0.0)) == 0.25, "A mixed recipe pays its removed dry dirt but no money for the hose")
	for cycle: int in [0, 1]:
		var before_transition: float = state.cleaning_clearance_for_snapshot(wet_snapshot(false,cycle,1.0,1.0))
		var after_transition: float = state.cleaning_clearance_for_snapshot(wet_snapshot(false,cycle+1,0.0,0.0))
		check(before_transition == after_transition, "Mixed-recipe extraction overshoot preserves eligible work when the next rinse starts")
	var bad := wet_snapshot(false,0,1.0,0.0)
	bad.surface_clearance = 0.5
	check(state.cleaning_clearance_for_snapshot(bad) == -1.0, "Mixed wet progress cannot precede the dry stage")
	state.free()
	state = fresh("large")
	for id: int in range(2,7): state.stores[str(id)] = Rules.new_branch(id)
	var branch: Dictionary = state.stores["6"]
	Room.migrate_branch(6,branch)
	for id: String in Room.IDS: branch.room_upgrades[id] = Rules.room_level_cap(6)
	branch.payout_level = Room.total_levels(branch.room_upgrades)
	check(state.select_store(6), "A maxed sixth-store ledger uses its real AF quote")
	var job: String = state.start_job()
	check(state.current_job_full_reward() == 4e32, "The full quote remains exactly400AF")
	for step: int in range(1,101):
		var progress := float(step) * 0.99 / 100.0
		var delta: float = state.record_cleaning_progress(job,snapshot(progress))
		check(delta >= 0.0 and is_finite(delta) and delta == floorf(delta) and state.cash <= 2e32 * (1.0 + 1e-14), "AF installments remain finite whole-valued floats within the half budget")
	check(state._branch().job_cleaning_paid == 2e32 and state.reward_for_current_job(snapshot(0.99)) == 2e32, "Large first-half accounting ends at the exact budget with no floating residue")
	state = reload_state(state)
	check(state.record_cleaning_progress(job,snapshot(0.99)) == 0.0, "Large-money reload cannot replay the first half")
	check(not state.complete_and_start_next_job(job,snapshot(0.99)).is_empty() and absf(state.cash / 4e32 - 1.0) < 1e-14 and state.completed_rewards[job].amount == 4e32, "Large restoration totals preserve the quote at float64 precision")
	state.free()

func check_wet_mask_roundtrip() -> void:
	var state := fresh("wet_mask_roundtrip")
	state.record_cleaning_progress(state.start_job(), snapshot(0.25))
	var paid_branch: Dictionary = state.stores["1"].duplicate(true)
	var rug := Node3D.new()
	var dirty: Node3D = load("res://scenes/dirty_carpet.tscn").instantiate()
	dirty.name = "Dirty"
	rug.add_child(dirty)
	root.add_child(rug)
	var soil := Soil.new()
	root.add_child(soil)
	soil.automatic_completion_enabled = false
	soil.setup(rug)
	soil.set_process(false)
	soil.set_physics_process(false)
	# Invoke the real production payment builder without entering a locked wet
	# store, starting world effects, or writing a fabricated future-store save.
	var workshop := Workshop.new()
	workshop.soil = soil
	workshop.shop_state = state
	workshop.wet_recipe = true
	for skip_dry: bool in [true, false]:
		state.active_store = Rules.WET_FIRST_STORE if skip_dry else Rules.WET_FIRST_STORE + 1
		workshop.water_only_recipe = skip_dry
		soil.set_recipe(true, skip_dry)
		for cycle: int in [0, 1]:
			soil.prepare_extraction_stage(cycle)
			# This deliberate sub-byte value rounds down in the actual L8 mask.
			var extracted := 100.49 / 255.0
			soil.extraction_values.fill(extracted)
			soil.extraction_coverage_total = extracted * float(soil.surface_pixel_count)
			var saved: Dictionary = soil.make_snapshot()
			var original: float = state.cleaning_clearance_for_snapshot(saved)
			check(soil.restore_snapshot(saved), "A real partial wet mask restores through its authored snapshot format")
			var restored: Dictionary = soil.make_snapshot()
			var actual: float = state.cleaning_clearance_for_snapshot(restored)
			check(actual < original and original - actual > 1e-5, "L8 roundtrip can lower actual removal below a previously funded runoff watermark")
			var stale := restored.duplicate(true)
			stale.earned_clearance = actual
			stale.cleaning_pending_clearance = original
			check(state._eligible_cleaning_clearance(stale) == -1.0, "The real rounded mask demonstrates why an unclamped pending snapshot is invalid")
			workshop.wet_earned_clearance = original
			workshop.wet_pending_clearance = original
			var checkpoint: Dictionary = workshop._payment_snapshot()
			check(float(checkpoint.cleaning_pending_clearance) == actual and float(checkpoint.earned_clearance) <= actual and state._eligible_cleaning_clearance(checkpoint) >= 0.0, "Production checkpoint bounds restored earned and pending fractions to current removal")
			check(state.stores["1"] == paid_branch, "Rounding the presentation watermark never changes durable paid money or its high-water mark")
	workshop.free()
	soil.free()
	rug.free()
	state.free()

func run() -> void:
	check_dry_and_full()
	check_early()
	check_failures_and_validation()
	check_travel_upgrade_migration()
	check_wet_and_large()
	check_wet_mask_roundtrip()
	for path: String in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(path + ".tmp"): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	print("SPLIT_CLEANING_LEDGER_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
