extends SceneTree
## Real purchases, bounded first-shop mastery and migration in a disposable ledger.
const State := preload("res://scripts/shop_state.gd")
const Room := preload("res://scripts/room_upgrades.gd")
const Rules := preload("res://scripts/progression.gd")
const Money := preload("res://scripts/money.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		printerr("First shop mastery validation requires -- --shop-test.")
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func fresh(label: String) -> Node:
	var state := State.new()
	state._save_path = "res://.godot/mastery_%d_%s.json" % [OS.get_process_id(), label]
	paths.append(state._save_path)
	state._test_ticks_msec = 0
	state._test_unix_time = 1800000000.0
	root.add_child(state)
	state.set_process(false)
	return state

func reload_state(state: Node, away: float = 0.0) -> Node:
	var replacement := State.new()
	replacement._save_path = state._save_path
	replacement._test_ticks_msec = 0
	replacement._test_unix_time = state._test_unix_time + away
	state.free()
	root.add_child(replacement)
	replacement.set_process(false)
	return replacement

func run() -> void:
	var state := fresh("mastery")
	var prices := {"floor":40, "plants":25, "window":60, "railings":35, "walls":50}
	var gains := {"floor":6, "plants":4, "window":8, "railings":4, "walls":6}
	check(state.room_upgrade_levels().size() == 5 and state.room_upgrade_levels().walls == 0, "Five independent ladders include fresh walls")
	check(state.progression_view().full_reward == 40, "The first carpet retains its40-coin full reward")
	state.cash = 100000
	state.stores["1"].bonzi_tier = 2
	var job: String = state.start_job()
	check(state.save_job_snapshot({"unique_clearance":0.25,"surface_clearance":0.4,"pixels":[2,7]}), "Store a real unfinished rug")
	for id: String in Room.IDS:
		var offer: Dictionary = state.room_upgrade_view(id)
		check(offer.cost == prices[id] and offer.next_full - offer.full_reward == gains[id], id + " retains its independent affordable first price and gain")
		var wallet: float = state.cash
		check(state.buy_room_upgrade(id) and state.cash == wallet - float(offer.cost), id + " actually spends its own stated price")
		check(state.bonzi_reward_for_store() == state.progression_view().full_reward and state.active_job_id == job, id + " gives player and Bonzi the same upgraded rug without replacing it")
	check(state.progression_view().full_reward == 68, "One purchase of every object raises40 to68 full coins")
	for id: String in Room.IDS:
		for target in range(2, Rules.room_level_cap(1) + 1):
			var offer: Dictionary = state.room_upgrade_view(id)
			var other_levels: Dictionary = state.room_upgrade_levels().duplicate()
			# Fund each real transaction at its own scale, rather than subtracting
			# tiny prices from an artificially enormous wallet.
			state.cash = float(offer.cost) * 2.0
			check(state.buy_room_upgrade(id), "Purchase %s level%d" % [id,target])
			check(is_equal_approx(state.cash, float(offer.cost)), "The %s level%d debit uses a finite large number" % [id,target])
			check(state.room_upgrade_levels()[id] == target and state.progression_view().bonzi_reward == state.progression_view().full_reward, "Local levels and shared reward remain valid at%s level%d" % [id,target])
			for other: String in Room.IDS:
				if other != id:
					check(state.room_upgrade_levels()[other] == other_levels[other], "A large upgrade cannot advance another object")
			var purchased: Dictionary = state.room_upgrade_view(id)
			check(purchased.full_reward <= Rules.reward_cap(1), "Every first-store purchase respects its400K full-clean ceiling")
		var final_offer: Dictionary = state.room_upgrade_view(id)
		check(final_offer.maxed and final_offer.cost == -1 and final_offer.next_visual_level == -1 and final_offer.milestone_progress == 1.0 and not state.buy_room_upgrade(id), id + " ends at its store cap with no extra spend")
	var full: float = state.progression_view().full_reward
	check(full == 400000.0 and Rules.reward_cap(1) == full and Money.format(full) == "400K", "A mastered first shop pays exactly400K per full carpet")
	check(state.reward_for_current_job({"unique_clearance":1.0,"surface_clearance":1.0}) == full and state.bonzi_reward_for_store() == full, "Player and Bonzi share the exact400K carpet quote")
	state.cash = full * 10.0
	check(state.save_state(), "The large wallet and completed ladders commit")
	var wallet: float = state.cash
	var next_job: String = state.complete_and_start_next_job(job,{"unique_clearance":1.0,"surface_clearance":1.0})
	check(not next_job.is_empty() and is_equal_approx(state.cash,wallet + full), "A mastered visible rug pays400K once in a real transaction")
	check(state.complete_and_start_next_job(job,{"unique_clearance":1.0,"surface_clearance":1.0}).is_empty(), "Repeated completion cannot duplicate the400K payment")
	wallet = state.cash
	state._test_ticks_msec += 60000
	state._test_unix_time += 60.0
	check(state.save_state() and is_equal_approx(state.cash,wallet + full), "The60-second routine order actually pays the same400K amount")
	state = reload_state(state)
	check(state._save_enabled and state.room_upgrade_levels().walls == Rules.room_level_cap(1) and state.progression_view().full_reward == full, "The completed store-specific ladders and reward survive save/reload")
	wallet = state.cash
	state = reload_state(state, 12.0*3600.0)
	check(is_equal_approx(state.cash,wallet+480.0*full) and is_equal_approx(state.return_reward,480.0*full) and state.return_seconds==28800.0, "Twelve hours away credit exactly eight hours of capped orders")
	wallet = state.cash
	state = reload_state(state)
	check(state.cash == wallet, "Reload cannot collect the absence twice")
	var valid: Dictionary = state._capture_state()
	for invalid: float in [NAN,INF,-1.0,Rules.MAX_MONEY*2.0,1.5]:
		var broken := valid.duplicate(true)
		broken.cash = invalid
		check(not state._valid_save(broken), "Invalid or fractional currency cannot enter a save")
	state.free()
	check_legacy()
	check_pending_and_failure()
	for path: String in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".tmp"))
	print("FIRST_SHOP_MASTERY: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func check_legacy() -> void:
	var state := fresh("legacy")
	state.cash = 1234
	var job: String = state.start_job()
	check(state.save_job_snapshot({"unique_clearance":0.4,"surface_clearance":0.5,"pixels":[3,8]}), "Legacy fixture keeps an unfinished rug")
	var old: Dictionary = state._capture_state()
	old.version = 2
	var branch: Dictionary = old.stores["1"]
	branch.room_rules_version = 2
	branch.room_upgrades = {"floor":5,"plants":10,"window":15,"railings":4}
	branch.room_income_origins = {"floor":0,"plants":0,"window":0,"railings":0}
	branch.payout_level = 34
	branch.room_base_early = 20
	branch.bonzi_tier = 0
	branch.job_early_reward = Room.early_reward(1,branch)
	var preserved: float = branch.job_early_reward
	var file := FileAccess.open(state._save_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(old,"",true,true))
	file.close()
	state = reload_state(state)
	check(state._save_enabled and state.cash == 1234 and state.progression_view().full_reward >= minf(preserved*2.0, Rules.reward_cap(1)) and state.progression_view().full_reward <= Rules.reward_cap(1), "Version2 migration keeps the wallet and preserves earned income within the new store ceiling")
	check(state.room_upgrade_levels().walls == 0 and state.stores["1"].room_rules_version == Room.RULES_VERSION, "Legacy room investments migrate to current rules with walls unpurchased")
	check(state.active_job_id == job and state.job_snapshot.pixels.size()==2 and state.reward_for_current_job({"unique_clearance":1.0,"surface_clearance":1.0})==state.progression_view().full_reward, "Migration preserves the rug and dirt while granting its unpaid quote the same improved value")
	state.cash = 100000000
	var offer: Dictionary = state.room_upgrade_view("floor")
	var prior_level: int = state.room_upgrade_levels().floor
	check(state.buy_room_upgrade("floor") and state.progression_view().full_reward==offer.next_full and state.room_upgrade_levels().floor==prior_level+1, "A migrated track buys the next level under the new curve without duplicate income")
	var after: float = state.progression_view().full_reward
	state = reload_state(state)
	check(state.progression_view().full_reward==after and state.room_upgrade_levels().floor==prior_level+1, "The income checkpoint migrates only once")
	state.free()

func check_pending_and_failure() -> void:
	var state := fresh("transaction")
	state.cash = 10000
	state.stores["1"].bonzi_tier = 0
	check(state.save_state(), "Prepare isolated wall transaction")
	state._test_ticks_msec += 150000
	state._test_unix_time += 150.0
	var before: Dictionary = state._capture_state()
	var ticks: int = state._last_ticks
	var path: String = state._save_path
	state._save_path = path+"/blocked.json"
	check(not state.buy_room_upgrade("walls") and state._capture_state()==before and state._last_ticks==ticks, "A failed wall save rolls back pending orders, price and levels")
	state._save_path = path
	check(state.buy_room_upgrade("walls") and state.cash==9990 and state.bonzi_reward_for_store()==46 and is_equal_approx(state.routine_remainder,0.25), "Retry settles the prior40 coins once, spends50, and quotes46 with quarter-cycle retained")
	state._test_ticks_msec += 90000
	state._test_unix_time += 90.0
	check(state.save_state() and state.cash==10036, "The remaining cycle pays the wall-upgraded46 coins")
	state.free()
