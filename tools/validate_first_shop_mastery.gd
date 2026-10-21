extends SceneTree
## Real purchases, bounded first-shop mastery and persistence in a disposable ledger.
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
	root.add_child(state)
	state.set_process(false)
	return state

func reload_state(state: Node, _away: float = 0.0) -> Node:
	var replacement := State.new()
	replacement._save_path = state._save_path
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
	var job: String = state.start_job()
	check(state.save_job_snapshot({"unique_clearance":0.25,"surface_clearance":0.4,"pixels":[2,7]}), "Store a real unfinished rug")
	for id: String in Room.IDS:
		var offer: Dictionary = state.room_upgrade_view(id)
		check(offer.cost == prices[id] and offer.next_full - offer.full_reward == gains[id], id + " retains its independent affordable first price and gain")
		var wallet: float = state.cash
		check(state.buy_room_upgrade(id) and state.cash == wallet - float(offer.cost), id + " actually spends its own stated price")
		check(state.active_job_id == job, id + " improves the player quote without replacing the rug")
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
			check(state.room_upgrade_levels()[id] == target, "Local levels remain valid at%s level%d" % [id,target])
			for other: String in Room.IDS:
				if other != id:
					check(state.room_upgrade_levels()[other] == other_levels[other], "A large upgrade cannot advance another object")
			var purchased: Dictionary = state.room_upgrade_view(id)
			check(purchased.full_reward <= Rules.reward_cap(1), "Every first-store purchase respects its400K full-clean ceiling")
		var final_offer: Dictionary = state.room_upgrade_view(id)
		check(final_offer.maxed and final_offer.cost == -1 and final_offer.next_visual_level == -1 and final_offer.milestone_progress == 1.0 and not state.buy_room_upgrade(id), id + " ends at its store cap with no extra spend")
	var full: float = state.progression_view().full_reward
	check(full == 400000.0 and Rules.reward_cap(1) == full and Money.format(full) == "400K", "A mastered first shop pays exactly400K per full carpet")
	check(state.reward_for_current_job({"unique_clearance":1.0,"surface_clearance":1.0}) == full, "The player receives the exact400K carpet quote")
	state.cash = full * 10.0
	check(state.save_state(), "The large wallet and completed ladders commit")
	var wallet: float = state.cash
	var next_job: String = state.complete_and_start_next_job(job,{"unique_clearance":1.0,"surface_clearance":1.0})
	check(not next_job.is_empty() and is_equal_approx(state.cash,wallet + full), "A mastered visible rug pays400K once in a real transaction")
	check(state.complete_and_start_next_job(job,{"unique_clearance":1.0,"surface_clearance":1.0}).is_empty(), "Repeated completion cannot duplicate the400K payment")
	wallet = state.cash
	check(state.save_state() and state.cash == wallet, "Saving without manual work grants no additional income")
	state = reload_state(state)
	check(state._save_enabled and state.room_upgrade_levels().walls == Rules.room_level_cap(1) and state.progression_view().full_reward == full, "The completed store-specific ladders and reward survive save/reload")
	wallet = state.cash
	state = reload_state(state, 12.0*3600.0)
	check(state.cash == wallet, "Reloading never grants absence income")
	wallet = state.cash
	state = reload_state(state)
	check(state.cash == wallet, "Reload cannot collect the absence twice")
	var valid: Dictionary = state._capture_state()
	for invalid: float in [NAN,INF,-1.0,Rules.MAX_MONEY*2.0,1.5]:
		var broken := valid.duplicate(true)
		broken.cash = invalid
		check(not state._valid_save(broken), "Invalid or fractional currency cannot enter a save")
	state.free()
	check_pending_and_failure()
	for path: String in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".tmp"))
	print("FIRST_SHOP_MASTERY: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func check_pending_and_failure() -> void:
	var state := fresh("transaction")
	state.cash = 10000.0
	check(state.save_state(), "Prepare isolated wall transaction")
	var before: Dictionary = state._capture_state()
	var path: String = state._save_path
	state._save_path = path + "/blocked.json"
	check(not state.buy_room_upgrade("walls") and state._capture_state() == before, "A failed wall save rolls back wallet, quote and levels")
	state._save_path = path
	check(state.buy_room_upgrade("walls") and state.cash == 9950.0 and state.progression_view().full_reward == 46.0, "Retry spends exactly the wall price and updates the manual quote")
	check(state.save_state() and state.cash == 9950.0, "Subsequent saves cannot grant passive income")
	state.free()
