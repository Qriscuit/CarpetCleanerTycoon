extends SceneTree
const State := preload("res://scripts/shop_state.gd")
const Rules := preload("res://scripts/progression.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []

class TestProvider extends RefCounted:
	var requests := 0
	var pending_job := ""
	var pending_nonce := ""
	var callback: Callable
	func is_rewarded_ad_available() -> bool: return true
	func request_verified_reward(job_id: String, nonce: String, result: Callable) -> bool:
		requests += 1
		pending_job = job_id
		pending_nonce = nonce
		callback = result
		return true
	func verify_reward_receipt(job_id: String, nonce: String, receipt: Dictionary) -> bool:
		return receipt.get("signed_test_receipt") == true and job_id == pending_job and nonce == pending_nonce
	func resolve(valid: bool = true) -> void:
		callback.call(pending_job, pending_nonce, {"receipt_id": "receipt-%d" % requests, "signed_test_receipt": valid})

func _initialize() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		quit(2)
		return
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func new_state(label: String) -> Node:
	var state := State.new()
	state._save_path = "res://.godot/progression_%d_%s.json" % [OS.get_process_id(), label]
	paths.append(state._save_path)
	state._test_ticks_msec = 0
	state._test_unix_time = 1800000000.0
	root.add_child(state)
	state.set_process(false)
	return state

func reload_state(state: Node, away: float = 0.0) -> Node:
	var replacement := State.new()
	replacement._save_path = state._save_path
	replacement._test_unix_time = state._test_unix_time + away
	replacement._test_ticks_msec = 0
	state.free()
	root.add_child(replacement)
	replacement.set_process(false)
	return replacement

func advance(state: Node, seconds: float) -> void:
	state._test_ticks_msec += roundi(seconds * 1000.0)
	state._test_unix_time += seconds
	state.save_state()

func complete(state: Node, use_final: bool = true) -> bool:
	var id: String = state.start_job()
	if use_final: state.note_current_tool_used()
	var snapshot := {"unique_clearance": 1.0, "surface_clearance": 1.0}
	if state.active_store >= 3:
		snapshot.merge({"wet_recipe": true, "water_clearance": 1.0, "extraction_clearance": 1.0})
	return not state.complete_and_start_next_job(id, snapshot).is_empty()

func fund(state: Node, amount: int) -> void:
	state.cash = amount
	check(state.save_state(), "Isolated test funds save")

func run() -> void:
	var state := new_state("main")
	var view: Dictionary = state.progression_view()
	check(view.store_id == 1 and view.early_reward == 20 and view.full_reward == 40 and view.payout_cost == 25, "Starter payout and first price match design")
	check(view.bonzi_tier == -1 and view.tool_width == 1.0 and not view.can_travel, "Starter tools and travel gates are intact")
	check(not state.reward_ad_available() and not state.request_reward_ad(), "No configured provider means no production ad or reward")
	check(not state.buy_bonzi_upgrade() and not state.select_store(2) and not state.open_next_store(), "Locked automation and unowned stores cannot be bypassed")
	var job: String = state.start_job()
	state.save_job_snapshot({"unique_clearance": 0.2, "surface_clearance": 0.3, "pixels": [7, 8]})
	for pair: Array in [[0.8499, 0], [0.85, 20], [0.9899, 20], [0.99, 40], [1.0, 40]]:
		check(state.reward_for_current_job({"unique_clearance": pair[0], "surface_clearance": pair[0]}) == pair[1], "Current quote respects completion tier " + str(pair[0]))
	check(state.reward_for_current_job({"unique_clearance": 1.0, "surface_clearance": 0.84}) == 0, "Dry payout requires both layers")
	fund(state, 100)
	check(state.buy_payout_upgrade() and state.cash == 75 and state.active_job_id == job and state.job_snapshot.pixels == [7, 8], "Earnings upgrade atomically keeps rug and rebases unpaid quote")
	check(state.reward_for_current_job({"unique_clearance": 1.0, "surface_clearance": 1.0}) == 44, "Already-present rug receives the purchased quote")
	state = reload_state(state)
	check(state.progression_view().payout_level == 1 and state.active_job_id == job and state.reward_for_current_job({"unique_clearance": 0.85, "surface_clearance": 0.85}) == 22, "Payout level and current quote survive reload")
	var good_path: String = state._save_path
	var before: Dictionary = state._capture_state()
	state._save_path += "/cannot-write.json"
	check(not state.buy_payout_upgrade() and state._capture_state() == before, "Failed upgrade save rolls back price, level and quote together")
	state._save_path = good_path
	check(state.buy_payout_upgrade() and state.progression_view().payout_level == 2, "Failed purchase can be retried once storage recovers")
	fund(state, 500000)
	for index in 3: check(complete(state), "Paid local job " + str(index + 1))
	check(state.progression_view().local_jobs == 3 and state.buy_bonzi_upgrade(), "Three paid local jobs unlock basic Bonzi")
	var income_before: int = state.cash
	advance(state, 120.0)
	check(state.cash == income_before + 10 and state.progression_view().bonzi_earned == 10, "Basic Bonzi credits one 10-coin completed cycle")
	check(state.buy_bonzi_upgrade(), "Improved Bonzi can be bought")
	income_before = state.cash
	advance(state, 90.0)
	check(state.cash == income_before + 20 and state.progression_view().bonzi_seconds == 90.0, "Improved cycle pays 20 every 90 seconds")
	check(state.buy_bonzi_upgrade(), "Final Bonzi can be bought")
	advance(state, 120.0)
	check(state.progression_view().bonzi_earned == 110 and not state.buy_bonzi_upgrade(), "Final cycles pay 40 and cumulative earned count never gets spent")
	for index in 4: check(state.buy_tool_upgrade(), "Tool milestone " + str(index + 1))
	check(state.progression_view().global_tool_tier == 4 and state.progression_view().tool_cost == -1 and not state.buy_tool_upgrade(), "Store's capstone is a one-time fourth tool purchase")
	check(complete(state) and state.progression_view().final_tool_jobs == 0, "Rug begun before final-tool purchase cannot count retroactively")
	check(complete(state, false) and state.progression_view().final_tool_jobs == 0, "Owning the final tool without using it cannot count")
	for index in 3: check(complete(state), "Final tool used on new paid rug " + str(index + 1))
	check(state.progression_view().can_travel and state.progression_view().final_tool_jobs == 3, "All three travel goals are independently satisfied")
	job = state.active_job_id
	state.save_job_snapshot({"pixels": [3, 1, 4], "unique_clearance": 0.5, "surface_clearance": 0.5})
	before = state._capture_state()
	state._save_path += "/cannot-write.json"
	check(not state.open_next_store() and state._capture_state() == before, "Failed store opening preserves wallet, ownership and old job")
	state._save_path = good_path
	income_before = state.cash
	check(state.open_next_store() and state.active_store == 2 and state.cash == income_before - 2000, "Opening Store 2 charges once and selects its included starter kit")
	check(state.progression_view().bonzi_tier == 0 and state.progression_view().early_reward == 160 and state.progression_view().global_tool_tier == 4, "Store 2 inherits tool power and starts higher payout with Bonzi included")
	check(state.select_store(1) and state.active_job_id == job and state.job_snapshot.pixels == [3, 1, 4], "Returning to a store restores its exact unfinished rug")
	check(not state.open_next_store(), "Owned store cannot be bought twice")
	check(state.select_store(2), "Owned store travel is free")
	income_before = state.cash
	advance(state, 120.0)
	check(state.cash == income_before + 160 and state.stores["1"].bonzi_earned == 190 and state.stores["2"].bonzi_earned == 80, "Old and active stores produce concurrently at their own cycles")
	state.start_job()
	for index in 4: check(state.buy_tool_upgrade(), "Store 2 higher global tool milestone")
	check(state.progression_view().global_tool_tier == 8, "Dry brush progression reaches global tier 8")
	check(state.select_store(1) and state.progression_view().global_tool_tier == 8 and state.progression_view().tool_width == 1.75, "Returning to old stores never downgrades the global brush")
	state.select_store(2)
	complete(state)
	for index in 3: complete(state)
	advance(state, 1080.0)
	check(state.progression_view().bonzi_earned == 800 and state.progression_view().can_travel, "Store 2's local Bonzi target cannot be replaced by old-store earnings")
	check(state.open_next_store() and state.active_store == 3, "Wet store opens only after its preceding store's goals")
	state.start_job()
	check(state.reward_for_current_job({"unique_clearance": 1.0, "surface_clearance": 1.0}) == 0, "Wet jobs cannot pay from dry-only snapshots")
	check(state.reward_for_current_job({"wet_recipe": true, "unique_clearance": 1.0, "surface_clearance": 1.0, "water_clearance": 1.0, "extraction_clearance": 0.55}) == 1280, "Wet early reward follows the validated three-stage meter")
	check(state.reward_for_current_job({"wet_recipe": true, "unique_clearance": 0.5, "surface_clearance": 1.0, "water_clearance": 1.0, "extraction_clearance": 1.0, "overall_clearance": 1.0}) == 0, "Out-of-sequence wet progress and forged overall meters cannot pay")
	check(state.reward_for_current_job({"wet_recipe": true, "unique_clearance": 1.0, "surface_clearance": 1.0, "water_clearance": 1.0, "extraction_clearance": 1.0}) == 2560, "Wet full reward remains exactly double")
	state = reload_state(state)
	check(state.active_store == 3 and state.stores.size() == 3 and state.progression_view().global_tool_tier == 8, "All stores, selection and permanent tools survive reload")
	fund(state, 5000000)
	for index in 4: check(state.buy_tool_upgrade(), "Wet kit milestone " + str(index + 1))
	complete(state)
	for index in 3: complete(state)
	advance(state, 1200.0)
	check(state.progression_view().can_travel and state.open_next_store() and state.active_store == 4, "Store 4 is reachable through wet capstone jobs and its own Bonzi earnings")
	check(state.progression_view().wet_power >= 2.1 and state.progression_view().global_tool_tier == 8 and not state.progression_view().has_next_store, "Final authored store inherits every tool and has no imaginary next-store purchase")
	check(state.buy_tool_upgrade() and state.progression_view().next_wet_power > state.progression_view().wet_power, "Later wet upgrades improve real wet power and preview the next gain")
	var power: float = state.progression_view().wet_power
	check(state.select_store(3) and state.progression_view().wet_power == power, "Earlier wet stores retain the strongest owned wet kit")
	state.start_job()
	fund(state, Rules.MAX_MONEY)
	var cap_job: String = state.active_job_id
	check(not complete(state) and state.cash == Rules.MAX_MONEY and state.active_job_id == cap_job, "Wallet overflow rejects a job transaction without losing its rug or wrapping coins")
	check(Rules.early_reward(1, 19) == 122 and Rules.early_reward(1, 20) == 135 and Rules.payout_cost(1, 19) == 356, "Payout levels continue beyond the twenty-milestone target")
	check(Rules.early_reward(4, 1000000) == -1 and Rules.payout_cost(4, 1000000) == -1, "Extreme levels are guarded before non-finite or integer overflow")
	state.free()
	check_offline()
	check_migration()
	check_ads()
	for path in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(path + ".tmp"): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	print("PROGRESSION_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check_offline() -> void:
	var state := new_state("offline")
	state.stores["1"].bonzi_tier = 2
	state.stores["2"] = Rules.new_branch(2)
	state.routine_remainder = 0.5
	state.stores["2"].routine_remainder = 0.25
	state.save_state()
	state = reload_state(state, 12.0 * 3600.0)
	check(state.cash == 38400 and state.return_reward == 38400 and state.return_seconds == 28800.0, "Twelve offline hours credit exactly eight hours from every owned branch")
	check(is_equal_approx(state.routine_remainder, 0.5) and is_equal_approx(float(state.stores["2"].routine_remainder), 0.25), "Offline accounting preserves each branch's partial cycle")
	state = reload_state(state)
	check(state.cash == 38400, "Repeated return cannot pay offline production twice")
	state.free()

func check_migration() -> void:
	var state := new_state("migration")
	var path: String = state._save_path
	var old: Dictionary = state._capture_state()
	for key in ["stores", "active_store", "completed_rewards", "ad_receipts", "latest_reward_job"]: old.erase(key)
	old.version = 1
	old.cash = 777
	old.manual_jobs = 12
	old.automated_jobs = 7
	old.owned = {"hand_brush": true, "wide_brush": true, "bonzi": true, "bonzi_mk2": true, "intake": true}
	old.equipped_brush = "wide_brush"
	old.active_job_id = "neighborhood-13"
	old.job_serial = 13
	old.job_snapshot = {"pixels": [1, 9], "unique_clearance": 0.4, "surface_clearance": 0.5}
	old.routine_remainder = 0.5
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	state = reload_state(state)
	var view: Dictionary = state.progression_view()
	check(state.cash == 777 and state.active_job_id == "neighborhood-13" and state.job_snapshot.pixels.size() == 2 and int(state.job_snapshot.pixels[0]) == 1 and int(state.job_snapshot.pixels[1]) == 9, "Version 1 migration preserves wallet and active rug")
	check(view.tool_width >= 1.44 and float(view.bonzi_reward) * 3600.0 / float(view.bonzi_seconds) >= 450.0 and state.routine_remainder == 0.5, "Migration never downgrades owned brush power or prior maximum bot income")
	check(view.bonzi_earned == 70 and state.manual_jobs == 12 and state.automated_jobs == 7, "Migration preserves existing earned milestones and counters")
	check(JSON.parse_string(FileAccess.get_file_as_string(path)).version == 2, "Migrated state is durably upgraded once")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	state = reload_state(state, 3600.0)
	check(state.cash == 1227 and state.return_reward == 450 and state.routine_remainder == 0.5, "Migration settles prior absence at the original 450-per-hour rate before upgrading future output")
	state.free()

func check_ads() -> void:
	var state := new_state("ads")
	complete(state)
	var offer: Dictionary = state.reward_offer()
	check(not offer.available and offer.amount == 40 and not state.request_reward_ad(offer.job_id), "Finished rug has no ad button or bonus without a provider")
	var provider := TestProvider.new()
	check(state.register_reward_ad_provider(provider) and state.reward_offer().available, "Verified provider can make an optional completed-job offer available")
	check(state.request_reward_ad(offer.job_id) and not state.request_reward_ad(offer.job_id), "Only one provider request may be pending per completed rug")
	provider.resolve(false)
	check(state.cash == 40, "Unverified provider results grant no coins")
	check(state.request_reward_ad(offer.job_id), "A rejected receipt leaves the optional offer retryable")
	var signals: Array[String] = []
	var durable_at_signal: Array[bool] = []
	state.ad_reward_granted.connect(func(_amount: int) -> void:
		signals.append("ad")
		durable_at_signal.append(int(JSON.parse_string(FileAccess.get_file_as_string(state._save_path)).cash) == state.cash)
	)
	state.changed.connect(func() -> void: signals.append("changed"))
	provider.resolve()
	check(state.cash == 80 and not state.reward_offer().available, "Verified receipt adds one optional bonus matching the completed reward")
	check(signals == ["ad", "changed"] and durable_at_signal == [true], "Ad cosmetic notification follows durable commit and precedes wallet changed signal")
	provider.resolve()
	check(state.cash == 80 and not state.request_reward_ad(offer.job_id), "Duplicate callbacks and repeated requests cannot pay the ad reward twice")
	complete(state)
	offer = state.reward_offer()
	check(state.request_reward_ad(offer.job_id), "A different completed job can request its own optional ad")
	var save_path: String = state._save_path
	state._save_path += "/cannot-write.json"
	provider.resolve()
	check(state.cash == 120 and not state.completed_rewards[offer.job_id].ad_claimed, "Failed ad save preserves the completed job's unclaimed bonus")
	var requests_before: int = provider.requests
	state._save_path = save_path
	check(state.request_reward_ad(offer.job_id) and state.cash == 160 and provider.requests == requests_before, "Verified bonus retries after storage recovery without replaying an ad")
	state = reload_state(state)
	check(state.cash == 160 and state.completed_rewards[offer.job_id].ad_claimed, "Ad claims and receipts survive reload")
	state.free()
