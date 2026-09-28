extends SceneTree
## Isolated headless coverage for 75% rewards and the Store 2 wet-tool tracks.
const State := preload("res://scripts/shop_state.gd")
const Rules := preload("res://scripts/progression.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []

func _initialize() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		printerr("Refusing to change the real player save; pass -- --shop-test.")
		quit(2)
		return
	call_deferred("run")

func check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error(message)

func new_state(label: String) -> Node:
	var state := State.new()
	state._save_path = "res://.godot/wet_upgrade_%d_%s.json" % [OS.get_process_id(), label]
	paths.append(state._save_path)
	state._test_ticks_msec = 0
	state._test_unix_time = 1800000000.0
	root.add_child(state)
	state.set_process(false)
	return state

func reload_state(state: Node) -> Node:
	var replacement := State.new()
	replacement._save_path = state._save_path
	replacement._test_ticks_msec = 0
	replacement._test_unix_time = state._test_unix_time
	state.free()
	root.add_child(replacement)
	replacement.set_process(false)
	return replacement

func add_stores(state: Node, through: int) -> void:
	for store_id in range(2, through + 1):
		if not state.stores.has(str(store_id)):
			state.stores[str(store_id)] = Rules.new_branch(store_id)
	state.cash = 5000000
	check(state.save_state(), "Isolated branch fixture saves")

func wet_snapshot(extraction: float, water: float = 1.0, dry: float = 1.0) -> Dictionary:
	return {"wet_recipe": true, "skip_dry_stage": true, "unique_clearance": dry, "surface_clearance": dry,
		"water_clearance": water, "extraction_clearance": extraction}

func run() -> void:
	check_thresholds()
	check_independent_tracks()
	check_migration()
	check_invalid_fields()
	for path in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(path + ".tmp"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	print("WET_UPGRADE_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check_thresholds() -> void:
	var state := new_state("thresholds")
	var job: String = state.start_job()
	for pair: Array in [[0.7499, 0], [0.75, 20], [0.85, 20], [0.9899, 20], [0.99, 40], [1.0, 40]]:
		var snapshot := {"unique_clearance": pair[0], "surface_clearance": pair[0]}
		check(State.manual_reward_for(snapshot) == pair[1], "Static reward tier " + str(pair[0]))
		check(state.reward_for_current_job(snapshot) == pair[1], "Live dry reward tier " + str(pair[0]))
	check(state.reward_for_current_job({"unique_clearance": 1.0, "surface_clearance": 0.7499}) == 0, "Dirty surface prevents an early dry payout")
	check(state.reward_for_current_job({"unique_clearance": 0.7499, "surface_clearance": 1.0}) == 0, "Remaining debris prevents an early dry payout")
	check(not state.complete_and_start_next_job(job, {"unique_clearance": 0.75, "surface_clearance": 0.75}).is_empty() and state.cash == 20, "Exactly 75% awards one base payout and reserves the next rug")
	check(state.complete_and_start_next_job(job, {"unique_clearance": 1.0, "surface_clearance": 1.0}).is_empty() and state.cash == 20, "A retired job cannot earn a second payout")
	add_stores(state, 2)
	check(state.select_store(2), "Store 2 fixture is selectable")
	job = state.start_job()
	check(state.reward_for_current_job({"unique_clearance": 1.0, "surface_clearance": 1.0}) == 0, "Store 2 dry-only snapshots cannot skip watering and extraction")
	for pair: Array in [[0.4999, 0], [0.5, 160], [0.9799, 160], [0.98, 320], [1.0, 320]]:
		check(state.reward_for_current_job(wet_snapshot(pair[0])) == pair[1], "Wet 75%/99% overall tier at extraction " + str(pair[0]))
	check(state.reward_for_current_job(wet_snapshot(1.0, 0.9899)) == 0, "Extraction cannot skip 99% water coverage")
	check(state.reward_for_current_job(wet_snapshot(1.0, 1.0, 0.0)) == 320, "Store 2's dry metrics do not gate or dilute its two-stage reward")
	var forged := wet_snapshot(0.0)
	forged.overall_clearance = 1.0
	check(state.reward_for_current_job(forged) == 0, "Forged overall meter cannot finish an unextracted wet rug")
	var starting_cash: int = state.cash
	check(not state.complete_and_start_next_job(job, wet_snapshot(0.5)).is_empty() and state.cash == starting_cash + 160, "Store 2's exact 75% wet job commits the base reward")
	state.free()

func check_independent_tracks() -> void:
	var state := new_state("tracks")
	state.cash = 5000000
	state.save_state()
	var before: Dictionary = state._capture_state()
	check(not state.buy_hose_upgrade() and not state.buy_squeegee_upgrade() and state._capture_state() == before, "Store 1 cannot buy wet upgrades or lose coins")
	add_stores(state, 2)
	state.select_store(2)
	var job: String = state.start_job()
	state.save_job_snapshot(wet_snapshot(0.0))
	var view: Dictionary = state.progression_view()
	check(view.hose_level == 0 and view.squeegee_level == 0 and view.tool_level == 0, "Store 2 starts a hose main track and an independent squeegee")
	check(view.hose_cost == 640 and view.squeegee_cost == 640, "Store 2 wet prices use its 8x economy scale")
	var starting_cash: int = state.cash
	var snapshot: Dictionary = state.job_snapshot.duplicate(true)
	check(state.buy_hose_upgrade(), "The Store 2 hose can be upgraded")
	view = state.progression_view()
	check(state.cash == starting_cash - 640 and view.hose_level == 1 and view.squeegee_level == 0 and view.tool_level == 1 and state.stores["2"].tool_level == 0, "Buying a hose changes the main track without changing historical brush power")
	check(view.hose_power > 1.0 and is_equal_approx(float(view.squeegee_power), 1.0), "Hose strength does not upgrade extraction strength")
	check(state.active_job_id == job and state.job_snapshot == snapshot, "Wet upgrade preserves the exact in-progress rug")
	starting_cash = state.cash
	check(state.buy_squeegee_upgrade(), "The Store 2 squeegee can be upgraded")
	view = state.progression_view()
	check(state.cash == starting_cash - 640 and view.squeegee_level == 1 and view.hose_level == 1 and view.tool_level == 1 and state.stores["2"].tool_level == 0, "Squeegee purchase leaves hose and brush progression untouched")
	check(view.squeegee_power > 1.0, "Squeegee upgrade increases real extraction strength")
	check(state.buy_tool_upgrade() and state.progression_view().tool_level == 2 and state.progression_view().hose_level == 2 and state.progression_view().squeegee_level == 1 and state.stores["2"].tool_level == 0, "Store 2's main tool purchase now aliases the hose and preserves historical brush power")
	for kind: String in ["hose", "squeegee"]:
		before = state._capture_state()
		var path: String = state._save_path
		state._save_path += "/cannot-write.json"
		check(not state.call("buy_" + kind + "_upgrade") and state._capture_state() == before, "Failed " + kind + " save rolls back wallet, levels and active rug atomically")
		state._save_path = path
		check(state.call("buy_" + kind + "_upgrade"), "The " + kind + " upgrade retries after storage recovers")
	state = reload_state(state)
	view = state.progression_view()
	check(view.hose_level == 3 and view.squeegee_level == 2 and view.tool_level == 3 and state.stores["2"].tool_level == 0 and state.active_job_id == job and state.job_snapshot == snapshot, "Separate levels and the untouched rug survive reload")
	state.cash = 0
	state.save_state()
	before = state._capture_state()
	check(not state.buy_hose_upgrade() and not state.buy_squeegee_upgrade() and state._capture_state() == before, "Unaffordable wet upgrades preserve the ledger")
	state.cash = 5000000
	state.save_state()
	for kind: String in ["hose", "squeegee"]:
		for level in range(int(state.progression_view()[kind + "_level"]), 4):
			starting_cash = state.cash
			check(state.call("buy_" + kind + "_upgrade") and state.cash == starting_cash - Rules.TOOL_COSTS[level] * 8, "Store 2 " + kind + " milestone " + str(level + 1) + " charges its incremental price")
		before = state._capture_state()
		view = state.progression_view()
		check(view[kind + "_level"] == 4 and view[kind + "_cost"] == -1 and not view["can_upgrade_" + kind] and not state.call("buy_" + kind + "_upgrade") and state._capture_state() == before, "Maxed " + kind + " cannot be bought twice")
	var hose_power: float = state.progression_view().hose_power
	var extraction_power: float = state.progression_view().squeegee_power
	check(state.select_store(1) and state.progression_view().hose_power >= hose_power and state.progression_view().squeegee_power >= extraction_power and state.progression_view().effective_hose_level == 4, "Returning to Store 1 never loses globally owned wet power")
	add_stores(state, 3)
	state.select_store(3)
	view = state.progression_view()
	check(is_equal_approx(float(view.hose_power), hose_power) and is_equal_approx(float(view.squeegee_power), extraction_power), "Store 3 starts at Store 2's strongest kit without losing earned power")
	check(state.buy_tool_upgrade() and state.progression_view().tool_level == 1 and state.progression_view().hose_level == 1 and state.progression_view().squeegee_level == 0, "Legacy Store 3 tool purchase aliases the hose and preserves independent extraction")
	check(state.progression_view().hose_power > hose_power and is_equal_approx(float(state.progression_view().squeegee_power), extraction_power), "The first Store 3 hose upgrade produces real power above Store 2's capstone")
	hose_power = state.progression_view().hose_power
	check(state.buy_hose_upgrade() and state.progression_view().tool_level == 2 and state.progression_view().hose_level == 2, "Direct Store 3 hose purchase mirrors the legacy travel level")
	check(state.progression_view().hose_power > hose_power, "The second Store 3 hose upgrade produces another real increase")
	check(state.buy_squeegee_upgrade() and state.progression_view().tool_level == 2 and state.progression_view().hose_level == 2 and state.progression_view().squeegee_level == 1, "Store 3 squeegee purchase cannot advance the hose travel gate")
	check(state.progression_view().squeegee_power > extraction_power, "The first Store 3 squeegee upgrade produces real power above Store 2's capstone")
	for kind: String in ["hose", "squeegee"]:
		for _level in range(int(state.progression_view()[kind + "_level"]), 4):
			check_effective_purchase(state, kind)
	hose_power = state.progression_view().hose_power
	extraction_power = state.progression_view().squeegee_power
	add_stores(state, 4)
	state.select_store(4)
	view = state.progression_view()
	check(is_equal_approx(float(view.hose_power), hose_power) and is_equal_approx(float(view.squeegee_power), extraction_power), "Store 4 begins at Store 3's fully upgraded power")
	for kind: String in ["hose", "squeegee"]:
		for _level in range(4):
			check_effective_purchase(state, kind)
	hose_power = state.progression_view().hose_power
	extraction_power = state.progression_view().squeegee_power
	check(state.select_store(2) and is_equal_approx(float(state.progression_view().hose_power), hose_power) and is_equal_approx(float(state.progression_view().squeegee_power), extraction_power), "All later-store gains remain effective when returning to Store 2")
	state.free()

func check_effective_purchase(state: Node, kind: String) -> void:
	var before: Dictionary = state.progression_view()
	var power: float = before[kind + "_power"]
	var other := "squeegee" if kind == "hose" else "hose"
	var label := "Store %d %s level %d" % [before.store_id, kind, int(before[kind + "_level"]) + 1]
	check(float(before["next_" + kind + "_power"]) > power, label + " previews a real power increase")
	var cash_before: int = state.cash
	var purchased: bool = state.call("buy_" + kind + "_upgrade")
	var after: Dictionary = state.progression_view()
	check(purchased and state.cash == cash_before - int(before[kind + "_cost"]), label + " charges exactly the quoted incremental price")
	check(float(after[kind + "_power"]) > power and is_equal_approx(float(after[kind + "_power"]), float(before["next_" + kind + "_power"])), label + " applies the power it previewed")
	check(is_equal_approx(float(after[other + "_power"]), float(before[other + "_power"])), label + " does not change the other wet tool")

func write_fixture(path: String, fixture: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(fixture))
	file.close()

func check_migration() -> void:
	var state := new_state("migration")
	add_stores(state, 4)
	state.select_store(4)
	state.start_job()
	var old_snapshot := wet_snapshot(0.5)
	old_snapshot.erase("skip_dry_stage")
	state.save_job_snapshot(old_snapshot)
	var job: String = state.active_job_id
	var snapshot: Dictionary = state.job_snapshot.duplicate(true)
	var legacy: Dictionary = state._capture_state()
	for key: String in legacy.stores:
		legacy.stores[key].erase("hose_level")
		legacy.stores[key].erase("squeegee_level")
		legacy.stores[key].tool_level = 2 if key == "4" else 3
	check(state._valid_save(legacy), "Old version 2 saves without the two new fields remain loadable")
	write_fixture(state._save_path, legacy)
	state = reload_state(state)
	check(state._save_enabled and state.active_job_id == job and state.job_snapshot == snapshot, "Migration preserves the active rug and its wet progress")
	for store_id in range(1, 5):
		var branch: Dictionary = state.stores[str(store_id)]
		var expected_hose := (2 if store_id == 4 else 3) if store_id >= 2 else 0
		var expected_squeegee := (2 if store_id == 4 else 3) if store_id >= 3 else 0
		check(branch.hose_level == expected_hose and branch.squeegee_level == expected_squeegee, "Migration preserves past purchases correctly for Store " + str(store_id))
	var view: Dictionary = state.progression_view()
	check(view.hose_power >= Rules.WET_POWERS[2] * Rules.wet_base_power(4) and view.squeegee_power >= Rules.WET_POWERS[2] * Rules.wet_base_power(4), "Prior Store 4 wet strength is preserved and uses the current branch scale for both tools")
	var hose_power: float = view.hose_power
	var extraction_power: float = view.squeegee_power
	check(state.select_store(2) and state.progression_view().hose_power >= hose_power and state.progression_view().squeegee_power >= extraction_power, "Migrated higher-store power carries back to Store 2")
	state = reload_state(state)
	check(state.stores["4"].hose_level == 2 and state.stores["4"].squeegee_level == 2 and state.stores["2"].hose_level == 3, "Migration is durable and retains Store 2's historical brush investment")
	state.free()

func check_invalid_fields() -> void:
	var state := new_state("invalid")
	add_stores(state, 2)
	var valid: Dictionary = state._capture_state()
	for key: String in ["hose_level", "squeegee_level"]:
		for bad: Variant in [-1, 5, 1.5, true, null, "2", NAN, INF, [], {}]:
			var fixture := valid.duplicate(true)
			fixture.stores["2"][key] = bad
			check(not state._valid_save(fixture), "Malformed " + key + " is rejected: " + str(bad))
	var invalid := valid.duplicate(true)
	invalid.stores["2"].squeegee_level = 5
	write_fixture(state._save_path, invalid)
	var original := FileAccess.get_file_as_string(state._save_path)
	state = reload_state(state)
	check(not state._save_enabled and not state.save_state() and FileAccess.get_file_as_string(state._save_path) == original, "An invalid saved wet level stays untouched instead of being overwritten")
	state.free()
