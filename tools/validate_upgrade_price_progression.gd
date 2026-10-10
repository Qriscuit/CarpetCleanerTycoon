extends SceneTree
## Fixed upgrade milestones, real debits, save compatibility and price guards.
const Rules := preload("res://scripts/progression.gd")
const State := preload("res://scripts/shop_state.gd")
const Money := preload("res://scripts/money.gd")
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
		push_error("UPGRADE PRICES: " + message)

func fresh(label: String) -> Node:
	var state := State.new()
	state._save_path = "res://.godot/upgrade_prices_%d_%s.json" % [OS.get_process_id(), label]
	state._test_ticks_msec = 0
	state._test_unix_time = 1800000000.0
	paths.append(state._save_path)
	root.add_child(state)
	state.set_process(false)
	check(state.reset_progress(), "Price fixtures use a disposable ledger")
	return state

func reload_state(state: Node) -> Node:
	var next := State.new()
	next._save_path = state._save_path
	next._test_ticks_msec = 0
	next._test_unix_time = 1800000000.0
	state.free()
	root.add_child(next)
	next.set_process(false)
	check(next._save_enabled, "Changed offers preserve valid saves")
	return next

func check_curve() -> void:
	for level: int in range(4):
		check(Rules.tool_cost(1, level) == float([120, 2585, 55699, 1200000][level]), "Neighborhood brush prices have the approved early, middle and capstone milestones")
	for tier: int in [-1, 0, 1]:
		check(Rules.bot_cost(1, tier) == float([160, 16000, 1600000][tier + 1]), "Neighborhood Bonzi prices remain above comparable brush milestones")
	for store: int in range(1, Rules.STORE_COUNT + 1):
		var start := 40.0 * Rules.scale_for(store)
		var cap := Rules.reward_cap(store)
		check(Rules.tool_cost(store, 0) == 3.0 * start and Rules.bot_cost(store, -1) == 4.0 * start, "Initial prices stay anchored to the store's starting rug value")
		check(Rules.tool_cost(store, 3) == 3.0 * cap and Rules.bot_cost(store, 1) == 4.0 * cap, "Late prices track the full carpet cap instead of lagging behind its store scale")
		var previous := 0.0
		for level: int in range(4):
			var cost := Rules.tool_cost(store, level)
			check(Money.is_valid(cost) and cost == floorf(cost) and cost > previous, "All four brush milestones are finite, increasing whole currency")
			if level in [1, 2]:
				var expected_stage := float(level) / 3.0
				var actual_stage := log(cost / (3.0 * start)) / log(cap / start)
				check(absf(actual_stage - expected_stage) < 2e-5, "Middle brush offers sit at one-third and two-thirds of the store's logarithmic earning range")
			previous = cost
		previous = 0.0
		for tier: int in [-1, 0, 1]:
			var cost := Rules.bot_cost(store, tier)
			check(Money.is_valid(cost) and cost == floorf(cost) and cost > previous, "All three Bonzi milestones are finite, increasing whole currency")
			previous = cost
		var mid := Rules.bot_cost(store, 0)
		check(absf(mid / (4.0 * sqrt(start * cap)) - 1.0) < 1e-5, "The middle Bonzi price follows the geometric earning midpoint")
	for store: int in [0, -1, Rules.STORE_COUNT + 1, 999]:
		check(Rules.tool_cost(store, 0) == -1.0 and Rules.bot_cost(store, -1) == -1.0, "Missing stores cannot sell an upgrade")
	for level: int in [-1, 4, 999]: check(Rules.tool_cost(1, level) == -1.0, "Invalid and completed brush levels have no payable offer")
	for tier: int in [-2, 2, 999]: check(Rules.bot_cost(1, tier) == -1.0, "Invalid and completed Bonzi tiers have no payable offer")
	check(Rules.tool_cost(6, 3) > 9.223372036854776e18 and Rules.bot_cost(6, 1) == 1.6e33, "Royal prices remain valid beyond int64 and reach the authored AG scale")

func check_transactions() -> void:
	for store: int in range(1, Rules.STORE_COUNT + 1):
		var state := fresh("store_%d" % store)
		for id: int in range(2, store + 1): state.stores[str(id)] = Rules.new_branch(id)
		check(state.select_store(store), "Visit each authored store through its owned branch")
		state._branch().manual_jobs = 3
		state.cash = Rules.reward_cap(store) * 10.0
		var job: String = state.start_job()
		check(state.save_job_snapshot({"unique_clearance": 0.2, "surface_clearance": 0.3, "marker": "price-fixture"}), "Upgrade prices retain a real unfinished job")
		var snapshot: Dictionary = state.job_snapshot.duplicate(true)
		var price_before := Rules.tool_cost(store, 0)
		check(state.buy_room_upgrade("floor") and Rules.tool_cost(store, 0) == price_before, "Room improvements do not reprice a fixed tool milestone")
		for level: int in range(4):
			var offer: Dictionary = state.progression_view()
			var expected := Rules.tool_cost(store, level)
			check(float(offer.tool_cost) == expected and state.build_cost("wide_brush") == expected, "Tool offers and the compatibility build price share the real staged cost")
			var before: Dictionary = state._capture_state()
			state._save_enabled = false
			check(not state.buy_tool_upgrade() and state._capture_state() == before, "A failed tool write keeps money and owned levels intact")
			state._save_enabled = true
			var cash_before: float = state.cash
			check(state.buy_tool_upgrade() and state.cash == cash_before - expected and int(state.progression_view().tool_level) == level + 1, "A real tool purchase charges exactly its fixed price once")
			check(state.active_job_id == job and state.job_snapshot == snapshot, "Tool purchases preserve the current carpet and progress")
		for tier: int in range(int(state.progression_view().bonzi_tier), 2):
			var expected := Rules.bot_cost(store, tier)
			var alias: String = ["bonzi", "bonzi_mk2", "intake"][tier + 1]
			check(float(state.progression_view().bonzi_cost) == expected and state.build_cost(alias) == expected, "Bonzi shop and compatibility alias show the same staged price")
			var cash_before: float = state.cash
			check(state.buy_bonzi_upgrade() and state.cash == cash_before - expected and int(state.progression_view().bonzi_tier) == tier + 1, "A real Bonzi purchase charges its quote once")
			check(float(state.progression_view().bonzi_seconds) == float([120, 90, 60][tier + 1]), "Price changes preserve Bonzi's authored cycle times")
		var cash_before: float = state.cash
		state = reload_state(state)
		check(state.cash == cash_before and int(state.progression_view().tool_level) == 4 and int(state.progression_view().bonzi_tier) == 2 and state.active_job_id == job and state.job_snapshot == snapshot, "Reload preserves paid upgrades without charging the new offers again")
		check(not state.buy_tool_upgrade() and not state.buy_bonzi_upgrade() and state.cash == cash_before, "Completed ladders reject duplicate purchases")
		state.free()

func check_affordability_and_existing_levels() -> void:
	var state := fresh("affordability")
	state.cash = 119.0
	state.save_state()
	check(not state.buy_tool_upgrade() and state.cash == 119.0, "A brush cannot spend one coin below its displayed price")
	state.cash = 120.0
	state.save_state()
	check(state.buy_tool_upgrade() and state.cash == 0.0, "Exact starter funds buy the brush without residue")
	state._branch().manual_jobs = 3
	state.cash = 159.0
	state.save_state()
	check(not state.buy_bonzi_upgrade() and state.cash == 159.0, "The three-job unlock still requires enough money for Bonzi")
	state.cash = 160.0
	state.save_state()
	check(state.buy_bonzi_upgrade() and state.cash == 0.0, "Exact hiring funds acquire Bonzi once")
	state._branch().tool_level = 2
	state._branch().bonzi_tier = 1
	state.cash = 777.0
	state.save_state()
	state = reload_state(state)
	check(int(state.progression_view().tool_level) == 2 and int(state.progression_view().bonzi_tier) == 1 and state.cash == 777.0, "Existing owned tiers keep their cash and power levels when prices change")
	check(float(state.progression_view().tool_cost) == 55699.0 and float(state.progression_view().bonzi_cost) == 1600000.0, "Only the next unowned offers use the updated price curve")
	state.free()

func run() -> void:
	check_curve()
	check_transactions()
	check_affordability_and_existing_levels()
	for path: String in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(path + ".tmp"): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	print("UPGRADE_PRICE_PROGRESSION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
