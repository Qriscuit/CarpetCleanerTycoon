extends SceneTree
const State := preload("res://scripts/shop_state.gd")
const Rules := preload("res://scripts/progression.gd")
const Room := preload("res://scripts/room_upgrades.gd")
const Money := preload("res://scripts/money.gd")
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
	return not state.complete_and_start_next_job(id, snapshot).is_empty()

func fund(state: Node, amount: float) -> void:
	state.cash = amount
	var saved: bool = state.save_state()
	if not saved:
		print("FUNDS_SAVE_FAILURE ", JSON.stringify({
			"error": state.last_error, "amount": "%.0f" % amount, "cash": "%.0f" % state.cash,
			"money_limit": "%.0f" % Rules.MAX_MONEY, "shared_money_limit": "%.0f" % Money.MAX_VALUE,
			"cash_valid": state._bounded_money(state.cash),
			"manual_jobs": state.manual_jobs, "manual_valid": state._bounded_integer(state.manual_jobs),
			"automated_jobs": state.automated_jobs, "automated_valid": state._bounded_integer(state.automated_jobs),
			"job_serial": state._job_serial, "serial_valid": state._bounded_integer(state._job_serial),
			"return_reward": state.return_reward, "return_valid": state._bounded_money(state.return_reward),
			"save_enabled": state._save_enabled, "active_store": state.active_store,
		}))
	check(saved, "Isolated test funds save")

func run() -> void:
	var state := new_state("main")
	var view: Dictionary = state.progression_view()
	check(view.store_id == 1 and view.early_reward == 20 and view.full_reward == 40 and state.room_upgrade_view("plants").cost == 25 and view.payout_cost == 40, "Starter payout and independent floor/plant prices match design")
	check(view.bonzi_tier == -1 and view.bonzi_reward == 0 and state.bonzi_reward_for_store() == 0 and view.tool_width == 1.0 and not view.can_travel, "Starter tools and travel gates are intact without unowned Bonzi income")
	check(not state.reward_ad_available() and not state.request_reward_ad(), "No configured provider means no production ad or reward")
	check(not state.buy_bonzi_upgrade() and not state.select_store(2) and not state.open_next_store(), "Locked automation and unowned stores cannot be bypassed")
	var job: String = state.start_job()
	state.save_job_snapshot({"unique_clearance": 0.2, "surface_clearance": 0.3, "pixels": [7, 8]})
	for pair: Array in [[0.7499, 0], [0.75, 20], [0.85, 20], [0.9899, 20], [0.99, 40], [1.0, 40]]:
		check(state.reward_for_current_job({"unique_clearance": pair[0], "surface_clearance": pair[0]}) == pair[1], "Current quote respects completion tier " + str(pair[0]))
	check(state.reward_for_current_job({"unique_clearance": 1.0, "surface_clearance": 0.7499}) == 0, "Dry payout requires both layers")
	fund(state, 100)
	check(state.buy_room_upgrade("floor") and state.cash == 60 and state.active_job_id == job and state.job_snapshot.pixels == [7, 8], "Room upgrade atomically keeps rug and rebases unpaid quote")
	check(state.reward_for_current_job({"unique_clearance": 1.0, "surface_clearance": 1.0}) == 46, "Already-present rug receives the floor's purchased quote")
	state = reload_state(state)
	check(state.progression_view().payout_level == 1 and state.room_upgrade_levels().floor == 1 and state.active_job_id == job and state.reward_for_current_job({"unique_clearance": 0.75, "surface_clearance": 0.75}) == 23, "Selected room improvement and the fixed early half survive reload")
	var good_path: String = state._save_path
	var before: Dictionary = state._capture_state()
	state._save_path += "/cannot-write.json"
	check(not state.buy_room_upgrade("plants") and state._capture_state() == before, "Failed room upgrade save rolls back price, level and quote together")
	state._save_path = good_path
	check(state.buy_room_upgrade("plants") and state.progression_view().payout_level == 2 and state.room_upgrade_levels().plants == 1, "Failed room purchase can be retried once storage recovers")
	fund(state, Rules.reward_cap(1) * 20.0)
	for index in 3: check(complete(state), "Paid local job " + str(index + 1))
	check(state.progression_view().local_jobs == 3 and state.buy_bonzi_upgrade(), "Three paid local jobs unlock basic Bonzi")
	var income_before: float = state.cash
	advance(state, 120.0)
	check(state.cash == income_before + 50 and state.progression_view().bonzi_earned == 50 and state.progression_view().bonzi_reward == 50 and state.progression_view().full_reward == 50, "Basic Bonzi credits the same room-upgraded full-rug reward as the player")
	check(state.buy_bonzi_upgrade(), "Improved Bonzi can be bought")
	income_before = state.cash
	advance(state, 90.0)
	check(state.cash == income_before + 50 and state.progression_view().bonzi_reward == 50 and state.progression_view().bonzi_seconds == 90.0, "Improved Bonzi completes the same 50-coin rug every 90 seconds")
	check(state.buy_bonzi_upgrade(), "Final Bonzi can be bought")
	income_before = state.cash
	advance(state, 120.0)
	check(state.cash == income_before + 100 and state.progression_view().bonzi_earned == 200 and state.progression_view().bonzi_reward == 50 and state.progression_view().bonzi_seconds == 60.0 and not state.buy_bonzi_upgrade(), "Final Bonzi completes two equally valued rugs and retains cumulative earnings")
	for index in 4: check(state.buy_tool_upgrade(), "Tool milestone " + str(index + 1))
	check(state.progression_view().global_tool_tier == 4 and state.progression_view().tool_cost == -1 and not state.buy_tool_upgrade(), "Store's capstone is a one-time fourth tool purchase")
	check(complete(state) and state.progression_view().final_tool_jobs == 1, "Using the purchased final tool on the current rug counts without a throwaway job")
	check(complete(state, false) and state.progression_view().final_tool_jobs == 1, "Owning the final tool without using it cannot count")
	for index in 3: check(complete(state), "Final tool used on new paid rug " + str(index + 1))
	check(not state.progression_view().can_travel and state.progression_view().final_tool_jobs == 3 and state.progression_view().payout_level == 2, "Tools and service cannot bypass unfinished room mastery")
	for id: String in Room.IDS:
		for _upgrade in range(int(state.room_upgrade_levels()[id]), Rules.room_level_cap(1)):
			var offer: Dictionary = state.room_upgrade_view(id)
			fund(state, maxf(float(offer.cost) * 2.0, 1000000.0))
			check(state.buy_room_upgrade(id), "Buy remaining " + id + " mastery")
	check(state.progression_view().can_travel and state.progression_view().full_reward == 400000.0, "A fully mastered first place has its400K reward and opens the travel gate")
	job = state.active_job_id
	state.save_job_snapshot({"pixels": [3, 1, 4], "unique_clearance": 0.5, "surface_clearance": 0.5})
	before = state._capture_state()
	state._save_path += "/cannot-write.json"
	check(not state.open_next_store() and state._capture_state() == before, "Failed store opening preserves wallet, ownership and old job")
	state._save_path = good_path
	income_before = state.cash
	check(state.open_next_store() and state.active_store == 2 and state.cash == income_before - 2000, "Opening Store2 charges once and selects its starter kit")
	check(state.progression_view().bonzi_tier == 0 and state.progression_view().early_reward == 20.0 * Rules.scale_for(2) and state.progression_view().global_tool_tier == 4 and not state.progression_view().wet_unlocked, "Store2 inherits brush power and starts at the preceding mastered payout with Bonzi included")
	check(state.select_store(1) and state.active_job_id == job and state.job_snapshot.pixels == [3, 1, 4], "Returning restores the exact old unfinished rug")
	check(not state.open_next_store() and state.select_store(2), "Owned-store visits are free and cannot duplicate opening purchases")
	income_before = state.cash
	advance(state, 120.0)
	check(state.cash == income_before + Rules.reward_cap(1) * 2.0 + 40.0 * Rules.scale_for(2), "Old and current stores produce concurrently at their independent saved full-rug rewards")
	check(complete(state), "The second first-section place pays for ordinary brush cleaning")
	state = reload_state(state)
	check(state._save_enabled and state.active_store == 2 and state.stores.size() == 2 and state.stores["1"].room_upgrades.walls == Rules.room_level_cap(1), "Independent mastery and the newly owned store survive reload")
	state.start_job()
	fund(state, Rules.MAX_MONEY)
	var cap_job: String = state.active_job_id
	check(not complete(state) and state.cash == Rules.MAX_MONEY and state.active_job_id == cap_job, "A full wallet rejects a reward without losing the rug or wrapping coins")
	check(Rules.early_reward(4, 1000000) == -1 and Rules.payout_cost(4, 1000000) == -1, "Extreme legacy curve levels are guarded before non-finite arithmetic")
	state.free()
	check_room_automation_rewards()
	check_offline()
	check_migration()
	check_ads()
	for path in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(path + ".tmp"): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	print("PROGRESSION_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check_room_automation_rewards() -> void:
	var state := new_state("room_automation")
	state.cash = 10000
	state.stores["1"].bonzi_tier = 0
	state.stores["2"] = Rules.new_branch(2)
	check(state.save_state(), "Two independent automation branches save")
	var ids := ["floor", "plants", "window", "railings", "walls"]
	var prices := [40, 25, 60, 35, 50]
	var full_rewards := [40, 46, 50, 58, 62, 68]
	var other_reward := 40.0 * Rules.scale_for(2)
	for index in ids.size():
		var cash_before: float = state.cash
		state._test_ticks_msec += 120000
		state._test_unix_time += 120.0
		check(state.buy_room_upgrade(ids[index]), "Upgrade " + ids[index] + " during a pending Bonzi delivery")
		check(state.cash == cash_before + float(full_rewards[index]) + other_reward - float(prices[index]), "Buying " + ids[index] + " first settles both stores at their previous full-rug rewards")
		check(state.bonzi_reward_for_store(1) == float(full_rewards[index + 1]) and state.progression_view().bonzi_reward == float(full_rewards[index + 1]) and state.progression_view().full_reward == float(full_rewards[index + 1]), ids[index] + " increases player and Bonzi full-rug rewards together")
		check(state.bonzi_reward_for_store(2) == other_reward, ids[index] + " leaves the other store's Bonzi reward unchanged")
	check(state.stores["1"].bonzi_earned == 256 and state.stores["2"].bonzi_earned == other_reward * 5.0, "All five room improvements retain both branches' independent pre-upgrade delivery totals")
	# A failed room write must roll back its pending deliveries as well as its
	# price and levels, so retry can settle the old reward exactly once.
	state._test_ticks_msec += 120000
	state._test_unix_time += 120.0
	var before: Dictionary = state._capture_state()
	var before_ticks: int = state._last_ticks
	var good_path: String = state._save_path
	state._save_path += "/cannot-write.json"
	check(not state.buy_room_upgrade("floor") and state._capture_state() == before and state._last_ticks == before_ticks, "Failed room write restores pending automation, cash, levels and settlement clock")
	state._save_path = good_path
	var cash_before: float = state.cash
	var quote: Dictionary = state.room_upgrade_view("floor")
	check(state.buy_room_upgrade("floor") and state.cash == cash_before + 68.0 + other_reward - float(quote.cost) and state.bonzi_reward_for_store(1) == float(quote.next_full), "Storage recovery settles the previous reward once, spends the local quote and changes future rug income")
	advance(state, 60.0)
	check(is_equal_approx(state.routine_remainder, 0.5) and is_equal_approx(float(state.stores["2"].routine_remainder), 0.5), "Shared reward changes preserve each branch's fractional cycle")
	state = reload_state(state)
	check(state.bonzi_reward_for_store(1) == float(quote.next_full) and state.bonzi_reward_for_store(2) == other_reward and is_equal_approx(state.routine_remainder, 0.5), "Room-based automation rewards and partial cycles survive reload")
	state.free()
	state = new_state("automation_wallet_cap")
	state.stores["1"].bonzi_tier = 0
	state.room_upgrade_view("floor") # Initialize the branch's modern income checkpoint.
	state.cash = Rules.MAX_MONEY
	check(state.save_state(), "A full-wallet fixture saves")
	advance(state, 120.0)
	check(state.cash == Rules.MAX_MONEY and state.automated_jobs == 0 and state.stores["1"].banked_orders == 1, "A full-rug delivery waits without partial payment or overflow in a full wallet")
	state.cash = 0.0
	check(state.save_state() and state.cash == 40.0 and state.automated_jobs == 1 and state.stores["1"].banked_orders == 0, "Making wallet space releases the banked full-rug reward once")
	state = reload_state(state)
	check(state.cash == 40.0 and state.automated_jobs == 1 and state.stores["1"].banked_orders == 0, "Reopening cannot duplicate the released banked delivery")
	state.free()

func check_offline() -> void:
	var state := new_state("offline")
	state.stores["1"].bonzi_tier = 2
	state.stores["2"] = Rules.new_branch(2)
	state.routine_remainder = 0.5
	state.stores["2"].routine_remainder = 0.25
	state.save_state()
	var expected := 480.0 * 40.0 + 240.0 * 40.0 * Rules.scale_for(2)
	state = reload_state(state, 12.0 * 3600.0)
	check(state.cash == expected and state.return_reward == expected and state.return_seconds == 28800.0, "Twelve offline hours credit eight hours of full-rug rewards from every owned branch")
	check(is_equal_approx(state.routine_remainder, 0.5) and is_equal_approx(float(state.stores["2"].routine_remainder), 0.25), "Offline accounting preserves each branch's partial cycle")
	state = reload_state(state)
	check(state.cash == expected, "Repeated return cannot pay offline production twice")
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
	var migrated: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(migrated.version == 3 and migrated.stores["1"].room_rules_version == Room.RULES_VERSION and migrated.stores["1"].room_upgrades.walls == 0, "Original version1 state upgrades durably to current room rules with an unpurchased wall track")
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
	state.ad_reward_granted.connect(func(_amount: float) -> void:
		signals.append("ad")
		durable_at_signal.append(float(JSON.parse_string(FileAccess.get_file_as_string(state._save_path)).cash) == state.cash)
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
