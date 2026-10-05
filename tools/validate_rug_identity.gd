extends SceneTree
## Isolated ledger coverage; run with the pinned wrapper and -- --shop-test.
const State := preload("res://scripts/shop_state.gd")
const Catalog := preload("res://scripts/rug_catalog.gd")
const Rules := preload("res://scripts/progression.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []


func _initialize() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		printerr("Refusing to run without --shop-test.")
		quit(2)
		return
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)


func new_state(label: String) -> Node:
	var state := State.new()
	state._save_path = "res://.godot/rug_identity_%d_%s.json" % [OS.get_process_id(), label]
	paths.append(state._save_path)
	state._test_ticks_msec = 0
	state._test_unix_time = 1800000000.0
	root.add_child(state)
	state.set_process(false)
	return state


func reload_state(state: Node) -> Node:
	var next := State.new()
	next._save_path = state._save_path
	next._test_ticks_msec = 0
	next._test_unix_time = state._test_unix_time
	state.free()
	root.add_child(next)
	next.set_process(false)
	return next


func snapshot(state: Node, fraction: float = 1.0) -> Dictionary:
	var result := {"rug_id": state.active_rug_id, "unique_clearance": fraction, "surface_clearance": fraction, "pixels": [1, 7, 9]}
	if state.active_store >= 2:
		result.merge({"wet_recipe": true, "water_clearance": fraction, "extraction_clearance": fraction if fraction >= 0.99 else 0.0, "wash_cycle_count": 3, "wash_cycle": 2 if fraction >= 0.99 else 0})
		if state.active_store == 2: result.skip_dry_stage = true
	return result


func write_fixture(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _run() -> void:
	check(Catalog.IDS.size() == 24 and Catalog.id_for_completed_jobs(0) == "mint_meadow" and Catalog.id_for_completed_jobs(1) == "sunburst_geometry" and Catalog.id_for_completed_jobs(2) == "playful_fox" and Catalog.id_for_completed_jobs(3) == "moonlit_owl" and Catalog.id_for_completed_jobs(5) == "stillwater_pond" and Catalog.id_for_completed_jobs(11) == "wildflower_meadow" and Catalog.id_for_completed_jobs(12) == "sleepy_cat" and Catalog.id_for_completed_jobs(20) == "misty_tea_garden" and Catalog.id_for_completed_jobs(21) == "quiet_cove" and Catalog.id_for_completed_jobs(22) == "moonlit_greenhouse" and Catalog.id_for_completed_jobs(23) == "ramen_neko" and Catalog.id_for_completed_jobs(Catalog.IDS.size()) == "mint_meadow", "Soothing designs and Ramen Neko join the rotation while Stillwater replaces Whale without moving the other earlier designs")
	check(not Catalog.is_known("celestial_whale") and not Catalog.NAMES.has("celestial_whale") and not Catalog.TEXTURES.has("celestial_whale"), "Retired Whale cannot appear in paid jobs or Gym decks")
	var unique_ids := {}
	for index in Catalog.IDS.size():
		var id: String = Catalog.IDS[index]
		check(not unique_ids.has(id) and Catalog.id_for_completed_jobs(index) == id and Catalog.NAMES.has(id) and Catalog.TEXTURES.has(id), "Catalog entry is unique, named and reachable: " + id)
		unique_ids[id] = true
	check(not Catalog.is_known("../untrusted") and not Catalog.is_known(12) and Catalog.definition_path("../untrusted") == Catalog.definition_path(Catalog.DEFAULT_ID), "Catalog resolves only known resource paths")
	var state := new_state("rotation")
	var job: String = state.start_job()
	check(not job.is_empty() and state.active_rug_id == "mint_meadow" and state.start_job() == job, "First reservation is stable Mint")
	var next: String = state.complete_and_start_next_job(job, snapshot(state, 0.75))
	check(not next.is_empty() and state.active_rug_id == "sunburst_geometry" and state.cash == 20 and state.progression_view().local_jobs == 1, "Early paid finish reserves Sunburst in the same payout transaction")
	var progress := snapshot(state, 0.43)
	check(state.save_job_snapshot(progress), "Sunburst partial work saves")
	state = reload_state(state)
	check(state._save_enabled and state.active_job_id == next and state.active_rug_id == "sunburst_geometry" and state.job_snapshot.rug_id == "sunburst_geometry" and state.job_snapshot.surface_clearance == 0.43 and int(state.job_snapshot.pixels[1]) == 7, "Disk reload retains the exact rug and partial work")
	check(state.start_job() == next and state.active_rug_id == "sunburst_geometry", "Repeated start does not reroll resumed art")
	var before: Dictionary = state._capture_state()
	for invalid: Variant in ["mint_meadow", "playful_fox", "unknown", "", 42, {"bad": true}]:
		var wrong := snapshot(state)
		wrong.rug_id = invalid
		check(not state.save_job_snapshot(wrong) and state.reward_for_current_job(wrong) == 0 and state.complete_and_start_next_job(next, wrong).is_empty() and state._capture_state() == before, "Explicit mismatched/invalid snapshot cannot change or reward current rug: " + str(invalid))
	var good_path: String = state._save_path
	state._save_path += "/cannot-write.json"
	check(state.complete_and_start_next_job(next, snapshot(state)).is_empty() and state._capture_state() == before, "Failed payout rolls back identity, snapshot, reservation, wallet and counters")
	state._save_path = good_path
	job = state.complete_and_start_next_job(next, snapshot(state))
	check(not job.is_empty() and state.active_rug_id == "playful_fox" and state.cash == 60, "Retry pays once and advances to Fox")
	check(state.complete_and_start_next_job(next, progress).is_empty() and state.cash == 60 and state.active_rug_id == "playful_fox", "Retired job cannot pay or advance discovery twice")
	check(state.save_job_snapshot(snapshot(state)) and state.complete_job(job), "Separate completion path supports Fox")
	state = reload_state(state)
	check(state.active_job_id.is_empty() and state.cash == 100, "Completed job stays paid and retired on reload")
	before = state._capture_state()
	state._save_path += "/cannot-write.json"
	check(state.start_job().is_empty() and state._capture_state() == before, "Failed start cannot reserve or advance a rug")
	state._save_path = good_path
	check(not state.start_job().is_empty() and state.active_rug_id == "moonlit_owl", "Completing the original three discovers the first new design")
	state.free()
	_check_stores()
	_check_every_design_in_every_store()
	_check_migration()
	_check_identity_recovery()
	_check_retired_design_migration()
	for path: String in paths:
		for suffix: String in ["", ".tmp"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("Rug identity: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check_stores() -> void:
	var state := new_state("stores")
	state.start_job()
	state.complete_and_start_next_job(state.active_job_id, snapshot(state))
	state.save_job_snapshot(snapshot(state, 0.35))
	var first_job: String = state.active_job_id
	state.stores["2"] = Rules.new_branch(2)
	check(state.save_state() and state.select_store(2) and not state.start_job().is_empty() and state.active_rug_id == "mint_meadow", "New store starts its own discovery sequence")
	state.complete_and_start_next_job(state.active_job_id, snapshot(state))
	state.complete_and_start_next_job(state.active_job_id, snapshot(state))
	state.save_job_snapshot(snapshot(state, 0.6))
	var second_job: String = state.active_job_id
	state = reload_state(state)
	check(state.active_store == 2 and state.active_rug_id == "playful_fox" and state.active_job_id == second_job, "Active wet-store identity survives disk reload")
	check(state.select_store(1) and state.active_rug_id == "sunburst_geometry" and state.active_job_id == first_job and state.job_snapshot.surface_clearance == 0.35, "Travel restores Neighborhood's unfinished Sunburst")
	check(state.select_store(2) and state.active_rug_id == "playful_fox" and state.active_job_id == second_job and state.job_snapshot.surface_clearance == 0.6, "Travel restores High Street's unfinished Fox independently")
	state.free()


func _check_every_design_in_every_store() -> void:
	var state := new_state("full_collection")
	for store_id in range(2, Rules.STORE_COUNT + 1):
		state.stores[str(store_id)] = Rules.new_branch(store_id)
	check(state.save_state(), "All four stores are available in the isolated collection fixture")
	for store_id in range(1, Rules.STORE_COUNT + 1):
		check(state.select_store(store_id), "Enter collection test store %d" % store_id)
		var job: String = state.start_job()
		var earned := 0
		var opening_cash: int = state.cash
		for index in Catalog.IDS.size():
			var expected: String = Catalog.IDS[index]
			check(not job.is_empty() and state.active_rug_id == expected, "Store %d reserves %s in the full discovery cycle" % [store_id, expected])
			check(state.save_job_snapshot(snapshot(state, 0.41)), "Store %d saves partial %s" % [store_id, expected])
			state = reload_state(state)
			check(state.active_store == store_id and state.active_job_id == job and state.active_rug_id == expected and state.job_snapshot.rug_id == expected and is_equal_approx(state.job_snapshot.surface_clearance, 0.41), "Store %d resumes the exact job, design and partial work for %s" % [store_id, expected])
			check(state.start_job() == job and state.active_rug_id == expected, "Re-entering %s cannot reroll a paid reservation" % expected)
			var finished := snapshot(state)
			earned += state.reward_for_current_job(finished)
			job = state.complete_and_start_next_job(job, finished)
			check(not job.is_empty() and state.active_rug_id == Catalog.IDS[(index + 1) % Catalog.IDS.size()], "Store %d advances after completing %s" % [store_id, expected])
		check(state.active_rug_id == Catalog.DEFAULT_ID and int(state.progression_view().local_jobs) == Catalog.IDS.size() and state.cash == opening_cash + earned, "Store %d completes and pays the whole collection exactly once before repeating" % store_id)
	state.free()


func _check_migration() -> void:
	for version: int in [1, 2]:
		var state := new_state("legacy_%d" % version)
		state.start_job()
		state.cash = 777
		state.manual_jobs = 8
		state.stores["1"].manual_jobs = 8
		state.save_job_snapshot(snapshot(state, 0.58))
		var old: Dictionary = state._capture_state()
		old.erase("active_rug_id")
		old.job_snapshot.erase("rug_id")
		for branch: Dictionary in old.stores.values():
			branch.erase("active_rug_id")
			branch.job_snapshot.erase("rug_id")
		old.version = version
		if version == 1:
			for key: String in ["stores", "active_store", "completed_rewards", "ad_receipts", "latest_reward_job"]: old.erase(key)
		write_fixture(state._save_path, old)
		state = reload_state(state)
		check(state._save_enabled and state.active_rug_id == "mint_meadow" and state.cash == 777 and state.manual_jobs == 8 and state.job_snapshot.surface_clearance == 0.58 and int(state.job_snapshot.pixels[1]) == 7, "Version %d missing identity preserves old Mint and progress regardless of count" % version)
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state._save_path))
		check(saved.version == 2 and saved.stores["1"].active_rug_id == "mint_meadow" and saved.job_snapshot.rug_id == "mint_meadow", "Version %d identity migration commits without replacing the ledger" % version)
		state.free()


func _check_identity_recovery() -> void:
	var state := new_state("recovery")
	state.start_job()
	state.complete_and_start_next_job(state.active_job_id, snapshot(state))
	state.save_job_snapshot(snapshot(state, 0.67))
	var valid: Dictionary = state._capture_state()
	for invalid: Variant in ["unknown", 42, {"bad": true}]:
		var damaged := valid.duplicate(true)
		damaged.active_rug_id = invalid
		damaged.stores["1"].active_rug_id = invalid
		write_fixture(state._save_path, damaged)
		state = reload_state(state)
		check(state._save_enabled and state.active_rug_id == "sunburst_geometry" and state.cash == 40 and state.job_snapshot.surface_clearance == 0.67, "Known snapshot recovers invalid reservation without wiping wallet/progress")
	var mismatch := valid.duplicate(true)
	mismatch.stores["1"].job_snapshot.rug_id = "playful_fox"
	write_fixture(state._save_path, mismatch)
	state = reload_state(state)
	check(state.active_rug_id == "sunburst_geometry" and state.job_snapshot.rug_id == "sunburst_geometry" and state.job_snapshot.surface_clearance == 0.67, "Known reservation wins a saved snapshot identity conflict without losing work")
	var unknown := valid.duplicate(true)
	unknown.active_rug_id = "unknown"
	unknown.stores["1"].active_rug_id = "unknown"
	unknown.stores["1"].job_snapshot.rug_id = "unknown"
	write_fixture(state._save_path, unknown)
	state = reload_state(state)
	check(state._save_enabled and state.active_rug_id == "mint_meadow" and state.cash == 40 and state.job_snapshot.surface_clearance == 0.67, "Entirely unknown art IDs fall back to Mint while preserving earned state")
	state.free()


func _check_retired_design_migration() -> void:
	var state := new_state("retired_whale")
	state.start_job()
	state.save_job_snapshot(snapshot(state, 0.43))
	var dry_job: String = state.active_job_id
	state.stores["2"] = Rules.new_branch(2)
	state.save_state()
	state.select_store(2)
	state.start_job()
	state.save_job_snapshot(snapshot(state, 0.67))
	var wet_job: String = state.active_job_id
	var old: Dictionary = state._capture_state()
	old.active_rug_id = "celestial_whale"
	old.job_snapshot.rug_id = "celestial_whale"
	for branch: Dictionary in old.stores.values():
		branch.active_rug_id = "celestial_whale"
		branch.job_snapshot.rug_id = "celestial_whale"
	# Compare the serialized numeric types used by both the old and restored save.
	var expected_wet: Dictionary = JSON.parse_string(JSON.stringify(old.stores["2"].job_snapshot))
	expected_wet.rug_id = "stillwater_pond"
	var expected_dry: Dictionary = JSON.parse_string(JSON.stringify(old.stores["1"].job_snapshot))
	expected_dry.rug_id = "stillwater_pond"
	write_fixture(state._save_path, old)
	state = reload_state(state)
	check(state._save_enabled and state.active_rug_id == "stillwater_pond" and state.active_job_id == wet_job and state.job_snapshot == expected_wet, "Active Whale migrates to Stillwater with exact saved water and cleaning progress")
	check(state.cash == int(old.cash) and state.manual_jobs == int(old.manual_jobs) and state.completed_rewards == old.completed_rewards, "Retiring Whale preserves wallet, completed jobs and reward receipts")
	check(state.select_store(1) and state.active_rug_id == "stillwater_pond" and state.active_job_id == dry_job and state.job_snapshot == expected_dry, "Inactive-store Whale also migrates with exact saved dirt and reservation")
	state = reload_state(state)
	check(state.active_rug_id == "stillwater_pond" and state.job_snapshot == expected_dry and state.start_job() == dry_job, "Migrated identity persists and repeated entry does not reset cleaning")
	check(State._saved_rug_id({}, {"rug_id": "celestial_whale"}) == "stillwater_pond", "Snapshot-only retired identity recovers its replacement")
	check(State._saved_rug_id({"active_rug_id": "celestial_whale"}, {}) == "stillwater_pond", "Unstarted reserved Whale switches to Stillwater with an empty snapshot")
	check(State._saved_rug_id({"active_rug_id": "sunburst_geometry"}, {"rug_id": "celestial_whale"}) == "sunburst_geometry", "Valid current reservation remains authoritative over a stale Whale snapshot")
	check(not state.save_job_snapshot({"rug_id": "celestial_whale"}) and state.reward_for_current_job({"rug_id": "celestial_whale"}) == 0, "Retired live snapshots cannot overwrite or reward the replacement")
	var before_reward: int = state.cash
	check(not state.complete_and_start_next_job(dry_job, snapshot(state)).is_empty() and state.cash == before_reward + 40, "Migrated job completes with its existing payout exactly once")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state._save_path))
	check(saved.stores["2"].active_rug_id == "stillwater_pond" and saved.stores["2"].job_snapshot == expected_wet, "Committing the replacement also persists the inactive store migration")
	state.free()
