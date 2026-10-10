extends SceneTree
## Production-ledger checks for Bonzi's full-rug reward and room improvements.
## Clock overrides and process-specific saves require -- --shop-test.

const State := preload("res://scripts/shop_state.gd")
const Rules := preload("res://scripts/progression.gd")
const Room := preload("res://scripts/room_upgrades.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		printerr("Bonzi earnings validation requires -- --shop-test to protect player saves.")
		quit(2)
		return
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func new_state(label: String) -> Node:
	var state := State.new()
	state._save_path = "res://.godot/bonzi_earnings_%d_%s.json" % [OS.get_process_id(), label]
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


func tick_without_save(state: Node, seconds: float) -> void:
	state._test_ticks_msec += roundi(seconds * 1000.0)
	state._test_unix_time += seconds


func advance(state: Node, seconds: float) -> void:
	tick_without_save(state, seconds)
	check(state.save_state(), "Production saves after %.3f test seconds" % seconds)


func complete_player_rug(state: Node) -> bool:
	var job: String = state.start_job()
	return not state.complete_and_start_next_job(job, {"unique_clearance": 1.0, "surface_clearance": 1.0}).is_empty()


func owned_state(label: String) -> Node:
	var state := new_state(label)
	state.cash = Rules.reward_cap(1) * 10.0
	check(state.save_state(), "Fund only the isolated " + label + " ledger")
	for index in 3:
		check(complete_player_rug(state), "Pay the local player rug needed to unlock Bonzi: %d" % (index + 1))
	check(state.buy_bonzi_upgrade(), "Actually purchase basic Bonzi in " + label)
	return state


func run() -> void:
	var state := new_state("unowned")
	check(state.has_method("bonzi_reward_for_store"), "Ledger exposes each owned store's Bonzi reward")
	if not state.has_method("bonzi_reward_for_store"):
		state.free()
		cleanup()
		quit(1)
		return
	check(state.progression_view().full_reward == 40 and state.progression_view().bonzi_reward == 0, "Unowned Bonzi cannot advertise or collect the player's starting full reward")
	check(state.bonzi_reward_for_store() == 0 and state.bonzi_reward_for_store(2) == 0, "An absent bot and unowned branch both quote zero")
	advance(state, 3600.0)
	check(state.cash == 0 and state.automated_jobs == 0, "Unowned Bonzi produces no online earnings")
	state.free()
	check_room_purchases_and_bot_tiers()
	check_pending_upgrade()
	check_failed_upgrade()
	check_branches_and_offline()
	check_legacy_absence()
	check_wallet_limit()
	cleanup()
	print("BONZI EARNINGS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func check_room_purchases_and_bot_tiers() -> void:
	var state := owned_state("room_ladders")
	check(state.progression_view().bonzi_reward == 40 and state.bonzi_reward_for_store() == 40, "Basic Bonzi earns the same 40 coins as a fully cleaned starter rug")
	var job: String = state.start_job()
	check(state.save_job_snapshot({"unique_clearance": 0.2, "surface_clearance": 0.3, "pixels": [3, 8]}), "Keep a real unfinished rug while improving its room")
	var snapshot: Dictionary = state.job_snapshot.duplicate(true)
	for id: String in Room.IDS:
		var quote: Dictionary = state.room_upgrade_view(id)
		var before: Dictionary = state.progression_view()
		var wallet: int = state.cash
		check(state.buy_room_upgrade(id), "Purchase the actual " + id + " improvement")
		var after: Dictionary = state.progression_view()
		check(state.cash == wallet - int(quote.cost), id + " spends exactly its own quoted price")
		check(after.full_reward == quote.next_full and int(after.full_reward) > int(before.full_reward), id + " raises the player's full-rug reward immediately")
		check(after.bonzi_reward == after.full_reward and state.bonzi_reward_for_store(1) == after.full_reward, id + " raises Bonzi by the same full-rug amount")
		check(state.active_job_id == job and state.job_snapshot == snapshot and state.reward_for_current_job({"unique_clearance": 1.0, "surface_clearance": 1.0}) == after.bonzi_reward, id + " keeps the current rug and gives player and Bonzi identical full quotes")
		var earned: int = int(after.bonzi_earned)
		var automatic: int = state.automated_jobs
		wallet = state.cash
		advance(state, 120.0)
		check(state.cash == wallet + int(after.full_reward) and state.progression_view().bonzi_earned == earned + int(after.full_reward), id + " pays its upgraded full reward for a completed basic cycle")
		check(state.automated_jobs == automatic + 1 and state.progression_view().local_jobs == 3, "Bonzi's " + id + " cycle records an automated rug without a manual rug")
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state._save_path))
		check(int(saved.cash) == state.cash and int(saved.stores["1"].bonzi_earned) == int(state.progression_view().bonzi_earned), id + " earnings are durable when reported")
	var full_reward: int = int(state.progression_view().full_reward)
	for tier in [1, 2]:
		state.cash = Rules.bot_cost(1, tier - 1) * 2.0
		check(state.save_state(), "Fund the isolated speed milestone at its actual revised price")
		check(state.buy_bonzi_upgrade(), "Actually purchase Bonzi speed tier %d" % tier)
		var view: Dictionary = state.progression_view()
		var seconds: float = 90.0 if tier == 1 else 60.0
		check(view.bonzi_tier == tier and view.bonzi_seconds == seconds and view.bonzi_reward == full_reward, "Bonzi tier %d changes cycle speed while preserving the room's full-rug reward" % tier)
		var wallet: int = state.cash
		var earned: int = int(view.bonzi_earned)
		advance(state, seconds - 0.001)
		check(state.cash == wallet and state.progression_view().bonzi_earned == earned, "Tier %d does not pay one millisecond before completing its rug" % tier)
		advance(state, 0.001)
		check(state.cash == wallet + full_reward and state.progression_view().bonzi_earned == earned + full_reward, "Tier %d pays exactly one full reward at its cycle boundary" % tier)
	check(not state.buy_bonzi_upgrade() and state.progression_view().bonzi_reward == full_reward, "Maximum bot speed cannot buy a phantom reward tier")
	state = reload_state(state)
	check(state.progression_view().bonzi_reward == full_reward and state.progression_view().bonzi_tier == 2, "Bot speed and the room's full-rug reward survive reload together")
	# JSON restores all numbers as floats and its normal serialization does not
	# guarantee bit-identical decoding. Assert saved gameplay values explicitly.
	var restored: Dictionary = state.job_snapshot
	check(state.active_job_id == job and restored.size() == snapshot.size() and restored.get("rug_id") == snapshot.rug_id, "Reload preserves the current rug's identity and snapshot fields")
	check(is_equal_approx(float(restored.get("unique_clearance", -1.0)), float(snapshot.unique_clearance)) and is_equal_approx(float(restored.get("surface_clearance", -1.0)), float(snapshot.surface_clearance)), "Reload preserves both unfinished cleaning layers within save precision")
	var restored_pixels: Array = restored.get("pixels", [])
	check(restored_pixels.size() == 2 and int(restored_pixels[0]) == 3 and int(restored_pixels[1]) == 8, "Reload preserves every stored dirt pixel numerically")
	if restored != snapshot and restored_pixels.size() == 2:
		print("BONZI RELOAD NUMERIC TYPES: pixel before=%d after=%d; layer difference=%.16f; restored bot tier=%d reward=%d" % [typeof(snapshot.pixels[0]), typeof(restored_pixels[0]), float(restored.surface_clearance) - float(snapshot.surface_clearance), int(state.progression_view().bonzi_tier), int(state.progression_view().bonzi_reward)])
	state.free()


func check_pending_upgrade() -> void:
	var state := owned_state("pending_upgrade")
	var before: Dictionary = state.progression_view()
	var quote: Dictionary = state.room_upgrade_view("floor")
	var wallet: int = state.cash
	tick_without_save(state, 120.0)
	check(state.buy_room_upgrade("floor"), "An upgrade settles an already completed Bonzi cycle")
	check(state.cash == wallet + int(before.full_reward) - int(quote.cost) and state.progression_view().bonzi_earned == before.full_reward, "Elapsed work before renovation earns the old 40-coin reward exactly once")
	check(state.progression_view().bonzi_reward == quote.next_full and state.progression_view().bonzi_reward > before.bonzi_reward, "The next Bonzi rug immediately uses the upgraded room reward")
	wallet = state.cash
	advance(state, 120.0)
	check(state.cash == wallet + float(quote.next_full) and state.progression_view().bonzi_earned == float(before.full_reward) + float(quote.next_full), "The subsequent cycle pays the quoted upgraded full-rug reward")
	state.free()


func check_failed_upgrade() -> void:
	var state := owned_state("failed_upgrade")
	var good_path: String = state._save_path
	var saved_text := FileAccess.get_file_as_string(good_path)
	var before: Dictionary = state._capture_state()
	var old_quote: Dictionary = state.progression_view()
	var quote: Dictionary = state.room_upgrade_view("plants")
	var ticks: int = state._last_ticks
	tick_without_save(state, 150.0)
	state._save_path = good_path + "/cannot-write.json"
	check(not state.buy_room_upgrade("plants"), "A room purchase fails when its durable save cannot be written")
	check(state._capture_state() == before and state._last_ticks == ticks, "Failed purchase rolls back coins, bot earnings, level, partial cycle and elapsed settlement")
	check(state.progression_view().bonzi_reward == old_quote.bonzi_reward and state.progression_view().full_reward == old_quote.full_reward and FileAccess.get_file_as_string(good_path) == saved_text, "Failed save preserves both visible reward quotes and the prior durable ledger")
	state._save_path = good_path
	check(state.buy_room_upgrade("plants"), "Retry commits the same purchase after storage recovers")
	check(state.cash == int(before.cash) + int(old_quote.full_reward) - int(quote.cost) and state.progression_view().bonzi_earned == old_quote.full_reward and is_equal_approx(state.routine_remainder, 0.25), "Retry credits old elapsed work once and retains its remaining quarter-cycle")
	var wallet: int = state.cash
	advance(state, 90.0)
	check(state.cash == wallet + int(quote.next_full) and state.progression_view().bonzi_earned == int(old_quote.full_reward) + int(quote.next_full), "Remaining work finishes once at the new reward after the successful purchase")
	state.free()


func check_branches_and_offline() -> void:
	var state := owned_state("branches_offline")
	check(state.buy_room_upgrade("floor") and state.buy_room_upgrade("plants"), "Renovate the first branch through actual purchases")
	check(state.buy_bonzi_upgrade() and state.buy_bonzi_upgrade(), "First branch owns the actual 60-second Bonzi")
	var first_reward: int = int(state.progression_view().full_reward)
	state.cash = 10.0 * float(Room.ECONOMY.window.cost) * Rules.scale_for(2)
	state.stores["2"] = Rules.new_branch(2)
	check(state.save_state() and state.select_store(2), "Create an isolated already-owned second branch and visit it normally")
	check(state.buy_room_upgrade("window") and state.buy_room_upgrade("window"), "Second branch purchases its own independent window ladder")
	var second_reward: int = int(state.progression_view().full_reward)
	check(second_reward > 40.0 * Rules.scale_for(2) and state.bonzi_reward_for_store(2) == second_reward and state.bonzi_reward_for_store(1) == first_reward, "Active and inactive bots quote their own branch's upgrades")
	check(state.bonzi_reward_for_store(3) == 0 and state.bonzi_reward_for_store(0) == 0 and state.bonzi_reward_for_store(Rules.STORE_COUNT + 1) == 0, "Unowned and unsupported branch IDs never manufacture a reward")
	check(state.select_store(1) and state.progression_view().bonzi_reward == first_reward, "Returning restores the first branch's own Bonzi reward")
	state.routine_remainder = 0.5
	state.stores["2"].routine_remainder = 0.25
	check(state.save_state(), "Save both branches' different partial rugs")
	var wallet: int = state.cash
	var jobs: int = state.automated_jobs
	advance(state, 120.0)
	check(state.cash == wallet + first_reward * 2 + second_reward and state.automated_jobs == jobs + 3, "Different branch speeds produce concurrently at their own upgraded full rewards")
	check(int(state.stores["1"].bonzi_earned) == first_reward * 2 and int(state.stores["2"].bonzi_earned) == second_reward, "Each store's earned milestone counts only its own paid rugs")
	wallet = state.cash
	jobs = state.automated_jobs
	var offline_income := first_reward * 480 + second_reward * 240
	state = reload_state(state, 12.0 * 3600.0)
	check(state._save_enabled and state.cash == wallet + offline_income and state.return_reward == offline_income and state.return_seconds == 28800.0, "Twelve hours away pay exactly eight hours of both stores' upgraded rewards")
	check(state.automated_jobs == jobs + 720 and is_equal_approx(state.routine_remainder, 0.5) and is_equal_approx(float(state.stores["2"].routine_remainder), 0.25), "Offline cap preserves fractional work and credits only completed branch cycles")
	check(int(state.stores["1"].bonzi_earned) == first_reward * 482 and int(state.stores["2"].bonzi_earned) == second_reward * 241, "Offline milestones use each store's exact independent reward")
	wallet = state.cash
	state = reload_state(state)
	check(state.cash == wallet and state.automated_jobs == jobs + 720, "Immediate repeated reload never awards the same offline rugs twice")
	check(state.select_store(2) and state.progression_view().bonzi_reward == second_reward and state.progression_view().full_reward == second_reward and state.bonzi_reward_for_store(1) == first_reward, "Saved room ladders remain authoritative when an inactive branch becomes active")
	state.free()


func check_legacy_absence() -> void:
	var state := new_state("legacy_absence")
	var old: Dictionary = state._capture_state()
	for field: String in ["stores", "active_store", "completed_rewards", "ad_receipts", "latest_reward_job"]:
		old.erase(field)
	old.version = 1
	old.cash = 777
	old.manual_jobs = 12
	old.automated_jobs = 7
	old.owned = {"hand_brush": true, "bonzi": true, "bonzi_mk2": true, "intake": true}
	old.routine_remainder = 0.5
	var file := FileAccess.open(state._save_path, FileAccess.WRITE)
	check(file != null, "Create an isolated original version-1 ledger")
	if file == null:
		state.free()
		return
	file.store_string(JSON.stringify(old))
	file.close()
	state = reload_state(state, 3600.0)
	check(state._save_enabled and state.cash == 1227 and state.return_reward == 450 and state.return_seconds == 3600.0, "Legacy absence settles at its original fixed 450 coins per hour before future rewards change")
	check(is_equal_approx(state.routine_remainder, 0.5) and state.progression_view().bonzi_earned == 520, "Migration preserves the old partial rug and historical earned milestone")
	var view: Dictionary = state.progression_view()
	check(view.bonzi_tier == 1 and view.bonzi_reward == view.full_reward and view.bonzi_seconds == 90.0, "After legacy settlement, future Bonzi rugs use the preserved room's full reward")
	var wallet: int = state.cash
	advance(state, 90.0)
	check(state.cash == wallet + int(view.full_reward), "One future migrated cycle earns the new full-rug quote")
	state = reload_state(state)
	check(state.cash == wallet + int(view.full_reward) and state.return_reward == 450, "Reload cannot repay either the legacy absence or the future cycle")
	state.free()


func check_wallet_limit() -> void:
	var state := owned_state("wallet_limit")
	var reward: float = float(state.progression_view().full_reward)
	state.cash = Rules.MAX_MONEY
	check(state.save_state(), "Save a wallet at its full idle-game money limit")
	var wallet: float = state.cash
	advance(state, 240.0)
	check(state.cash == wallet and state.stores["1"].banked_orders == 2 and state.progression_view().bonzi_earned == 0, "Full-wallet Bonzi rugs remain banked without partial payment or monetary overflow")
	state = reload_state(state)
	check(state.cash == wallet and state.stores["1"].banked_orders == 2 and state.automated_jobs == 0, "Blocked deliveries survive reload without falsely counting paid rugs")
	# An80-coin debit is below float64 precision at1e60. Supply representable
	# wallet space, then exercise the real bank settlement and durable reload.
	state.cash = 100.0
	check(state.stores["1"].banked_orders == 2 and state.progression_view().bonzi_reward == reward, "Creating fixture headroom preserves both banked rugs and their full reward")
	check(state.save_state(), "Settle banked rugs after representable wallet space becomes available")
	check(state.cash == 100.0 + reward * 2.0 and state.stores["1"].banked_orders == 0 and state.progression_view().bonzi_earned == reward * 2.0 and state.automated_jobs == 2, "Both banked rugs pay in full exactly once when wallet space becomes available")
	state = reload_state(state)
	check(state.cash == 100.0 + reward * 2.0 and state.stores["1"].banked_orders == 0 and state.automated_jobs == 2, "Reload retains the settled bank without paying its orders twice")
	wallet = state.cash
	check(state.buy_tool_upgrade(), "A real tool purchase remains available after the bank settles")
	check(state.cash == wallet - Rules.tool_cost(1, 0) and state.progression_view().bonzi_reward == reward and state.automated_jobs == 2, "A real small-wallet transaction spends its price without altering settled earnings")
	state.cash = 100
	state.stores["1"].bonzi_earned = Rules.MAX_MONEY
	state.stores["1"].automated_jobs = Rules.MAX_COUNTER - 1
	state.automated_jobs = Rules.MAX_COUNTER - 1
	advance(state, 240.0)
	check(state.cash == 100 + reward * 2 and state.progression_view().bonzi_earned == Rules.MAX_MONEY and state.automated_jobs == Rules.MAX_COUNTER and int(state.stores["1"].automated_jobs) == Rules.MAX_COUNTER, "Lifetime counters and monetary earnings respect their separate caps while ordinary wallet payments remain exact")
	check(state._valid_save(state._capture_state()), "Capped production persists as a valid ledger")
	state = reload_state(state)
	check(state.automated_jobs == Rules.MAX_COUNTER and state.progression_view().bonzi_earned == Rules.MAX_MONEY and state.cash == 100 + reward * 2, "Capped production reload preserves counters, earnings and exact ordinary payments")
	state.free()


func cleanup() -> void:
	for path: String in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(path + ".tmp"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
