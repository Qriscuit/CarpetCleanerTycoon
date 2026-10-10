extends SceneTree
## Independent accessory prices, real quotes, rollback, migration and store caps.
const State := preload("res://scripts/shop_state.gd")
const Room := preload("res://scripts/room_upgrades.gd")
const Rules := preload("res://scripts/progression.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		printerr("Room economy validation requires -- --shop-test.")
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
	state._save_path = "res://.godot/room_economy_%d_%s.json" % [OS.get_process_id(), label]
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

func write_fixture(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "", true, true))
	file.close()

func run() -> void:
	check_independent_purchases()
	check_visual_quotes()
	check_legacy_migration()
	check_validation()
	check_final_cap()
	for path: String in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(path + ".tmp"): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	print("ROOM_ECONOMY_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check_independent_purchases() -> void:
	var state := fresh("independence")
	check(state.room_upgrade_levels() == {"floor":0,"plants":0,"window":0,"railings":0,"walls":0}, "A fresh shop has five independent accessory tracks")
	var before: Dictionary = state._capture_state()
	check(not state.buy_room_upgrade("floor") and state._capture_state() == before, "An unfunded purchase leaves the whole ledger unchanged")
	check(state.room_upgrade_view("missing").is_empty() and not state.buy_room_upgrade("missing") and state._capture_state() == before, "An unknown accessory cannot spend money")
	check(not state.select_store(2), "Room purchases cannot select or unlock unowned stores")
	state.cash = 1000000000.0
	check(state.save_state(), "Isolated room test funds save")
	var job: String = state.start_job()
	check(state.save_job_snapshot({"unique_clearance":0.2,"surface_clearance":0.3,"pixels":[2,4,6]}), "The unfinished rug has saved dirt before a room purchase")
	var prices := {"floor":40,"plants":25,"window":60,"railings":35,"walls":50}
	var gains := {"floor":6,"plants":4,"window":8,"railings":4,"walls":6}
	for id: String in Room.IDS:
		var view: Dictionary = state.room_upgrade_view(id)
		var wallet: float = state.cash
		var total: int = state.progression_view().payout_level
		var others := {}
		for other: String in Room.IDS:
			if other != id: others[other] = state.room_upgrade_view(other)
		check(view.level == 0 and view.visual_level == 0 and view.max_visual_level == Room.visual_count(id), id + " exposes its local untouched ladder")
		check(view.cost == prices[id] and view.wallet_after == wallet - prices[id] and view.next_full - view.full_reward == gains[id], id + " preserves its affordable starter price and actual gain")
		check(view.next_visual_level == Room.next_visual_level(id, 0, 1) and view.max_level == Rules.room_level_cap(1), id + " previews its store-specific model milestone and ladder cap")
		check(state.buy_room_upgrade(id) and state.cash == float(view.wallet_after) and state.room_upgrade_levels()[id] == 1 and state.progression_view().payout_level == total + 1, id + " spends its quote and increments only one local step")
		check(state.active_job_id == job and state.job_snapshot.pixels == [2,4,6] and state.reward_for_current_job({"unique_clearance":1.0,"surface_clearance":1.0}) == float(view.next_full), id + " updates the current rug reward without changing identity or dirt")
		for other: String in others:
			var after: Dictionary = state.room_upgrade_view(other)
			check(after.cost == others[other].cost and after.level == others[other].level and after.contribution == others[other].contribution, id + " leaves every other feature's price, level and contribution independent")
	var saved: Dictionary = state._capture_state()
	state = reload_state(state)
	check(state.cash == saved.cash and state.room_upgrade_levels() == saved.stores["1"].room_upgrades and state.active_job_id == job, "The five accessory tracks, wallet and unfinished rug survive reload")
	var path: String = state._save_path
	before = state._capture_state()
	state._save_path = path + "/blocked.json"
	check(not state.buy_room_upgrade("plants") and state._capture_state() == before, "A failed durable room write rolls back the price, local level and current quote")
	state._save_path = path
	check(state.buy_room_upgrade("plants") and state.room_upgrade_levels().plants == 2, "The failed purchase can be retried exactly once")
	state.stores["2"] = Rules.new_branch(2)
	check(state.select_store(2), "An explicitly test-owned second place can be selected")
	var second: Dictionary = state.room_upgrade_view("window")
	check(second.level == 0 and second.cost == 60.0 * Rules.scale_for(2) and second.early_reward == 20.0 * Rules.scale_for(2), "A later place starts with its own reward, price scale and empty accessories")
	check(state.buy_room_upgrade("window") and state.select_store(1) and state.room_upgrade_levels().plants == 2 and state.room_upgrade_levels().window == 1, "Visiting the next place cannot overwrite the first place's accessory progress")
	state = reload_state(state)
	check(state.stores["2"].room_upgrades.window == 1 and state.stores["2"].room_upgrades.walls == 0 and state.room_upgrade_levels().plants == 2, "Inactive places persist their independent accessories")
	state.free()

func check_visual_quotes() -> void:
	var state := fresh("milestones")
	for store_id in range(1, Rules.STORE_COUNT + 1):
		if store_id > 1: state.stores[str(store_id)] = Rules.new_branch(store_id)
		check(state.select_store(store_id), "Select an isolated milestone fixture")
		state.room_upgrade_view("floor")
		for id: String in Room.IDS:
			var branch: Dictionary = state.stores[str(store_id)]
			for level in range(Rules.room_level_cap(store_id) + 1):
				branch.room_upgrades[id] = level
				branch.payout_level = Room.total_levels(branch.room_upgrades)
				var offer: Dictionary = state.room_upgrade_view(id)
				check(offer.visual_level == Room.visual_tier(id, level, store_id) and offer.next_visual_level == Room.next_visual_level(id, level, store_id), "Store%d/%s level%d uses its authored model intervals" % [store_id,id,level])
				check(offer.milestone_progress >= 0.0 and offer.milestone_progress <= 1.0 and offer.maxed == (level == Rules.room_level_cap(store_id)), "Milestone progress stays bounded and only the store cap completes its economic ladder")
			branch.room_upgrades[id] = 0
			branch.payout_level = 0
	state.free()

func check_legacy_migration() -> void:
	var state := fresh("legacy")
	state.cash = 777
	var job: String = state.start_job()
	state.save_job_snapshot({"unique_clearance":0.4,"surface_clearance":0.5,"pixels":[9,8]})
	var old: Dictionary = state._capture_state()
	old.version = 2
	var branch: Dictionary = old.stores["1"]
	branch.room_rules_version = 2
	branch.room_upgrades = {"floor":5,"plants":10,"window":15,"railings":4}
	branch.room_income_origins = {"floor":0,"plants":0,"window":0,"railings":0}
	branch.room_base_early = 20
	branch.payout_level = 34
	branch.job_early_reward = 1000
	write_fixture(state._save_path, old)
	state = reload_state(state)
	check(state._save_enabled and state.cash == 777 and state.active_job_id == job and state.job_snapshot.pixels.size() == 2 and int(state.job_snapshot.pixels[0]) == 9 and int(state.job_snapshot.pixels[1]) == 8, "Legacy purchased investments migrate without changing coins, rug identity or dirt")
	check(state.room_upgrade_levels().floor == 15 and state.room_upgrade_levels().plants == 30 and state.room_upgrade_levels().window == 45 and state.room_upgrade_levels().walls == 0, "Historical makeovers map to the same models at their new evenly spaced levels")
	check(state.stores["1"].room_rules_version == Room.RULES_VERSION and state.reward_for_current_job({"unique_clearance":1.0,"surface_clearance":1.0}) == state.progression_view().full_reward and state.progression_view().full_reward <= 400000.0, "The one-time new rules checkpoint rebases the unpaid quote within the store ceiling")
	var migrated: Dictionary = state._capture_state()
	state = reload_state(state)
	check(JSON.parse_string(JSON.stringify(state._capture_state())) == JSON.parse_string(JSON.stringify(migrated)), "Reload cannot map a historical makeover or income checkpoint twice")
	state.free()

func check_validation() -> void:
	var state := fresh("validation")
	state.room_upgrade_view("floor")
	var valid: Dictionary = state._capture_state()
	check(state._valid_save(valid), "Fresh modern accessory data passes save validation")
	for invalid_level: Variant in [-1,0.5,Rules.room_level_cap(1)+1]:
		var data := valid.duplicate(true)
		data.stores["1"].room_upgrades.floor = invalid_level
		data.stores["1"].payout_level = invalid_level
		check(not state._valid_save(data), "Negative, fractional or beyond-cap accessory levels are rejected")
	var data := valid.duplicate(true)
	data.stores["1"].room_upgrades.floor = 1
	check(not state._valid_save(data), "Accessory levels cannot exceed the paid compatibility count")
	data = valid.duplicate(true)
	data.stores["1"].room_upgrades = {"floor":0,"plants":0,"window":0,"railings":0,"unknown":0}
	check(not state._valid_save(data), "An unknown accessory identifier is rejected")
	data = valid.duplicate(true)
	data.stores["1"].room_income_origins.floor = 1
	check(not state._valid_save(data), "An income origin cannot exceed its purchased level")
	data = valid.duplicate(true)
	data.stores["1"].room_rules_version = 999
	check(not state._valid_save(data), "Unsupported future room rules are preserved through rejection")
	data = valid.duplicate(true)
	data.stores["1"].room_base_early = -1
	check(not state._valid_save(data), "Negative room base income cannot enter the save")
	data = valid.duplicate(true)
	data.cash = 1e32
	data.manual_jobs = Rules.MAX_COUNTER
	check(state._valid_save(data), "Large currency remains valid while job counters retain their separate bound")
	data.manual_jobs = Rules.MAX_COUNTER + 1
	check(not state._valid_save(data), "Large currency cannot extend job counter bounds")
	check(Room.cost(1,"window",1000000) == -1 and Room.early_contribution(6,"window",1000000) == -1, "Extreme curve inputs fail before overflowing arithmetic")
	state.free()

func check_final_cap() -> void:
	var state := fresh("final_cap")
	state.room_upgrade_view("plants")
	var cap := Rules.room_level_cap(1)
	state.stores["1"].room_upgrades.plants = cap
	state.stores["1"].payout_level = cap
	check(state.save_state(), "A completed single accessory is valid saved data")
	var offer: Dictionary = state.room_upgrade_view("plants")
	var before: Dictionary = state._capture_state()
	check(offer.maxed and offer.level == cap and offer.next_level == cap and offer.next_visual_level == -1 and offer.milestone_progress == 1.0, "The final local step explicitly fills and completes its model progress")
	check(offer.cost == -1 and not offer.can_upgrade and offer.next_full == offer.full_reward and not state.buy_room_upgrade("plants") and state._capture_state() == before, "A maxed accessory cannot spend coins or create an extra reward")
	state.free()
