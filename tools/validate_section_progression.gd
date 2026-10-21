extends SceneTree
## Six-store mastery, capped scaling and save persistence in disposable ledgers.
const State := preload("res://scripts/shop_state.gd")
const Rules := preload("res://scripts/progression.gd")
const Room := preload("res://scripts/room_upgrades.gd")
const Money := preload("res://scripts/money.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		printerr("Section progression validation requires -- --shop-test.")
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
	state._save_path = "res://.godot/section_progression_%d_%s.json" % [OS.get_process_id(), label]
	paths.append(state._save_path)
	root.add_child(state)
	state.set_process(false)
	return state

func reload_state(state: Node) -> Node:
	var replacement := State.new()
	replacement._save_path = state._save_path
	state.free()
	root.add_child(replacement)
	replacement.set_process(false)
	return replacement

func write_fixture(path: String, fixture: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(fixture, "", true, true))
	file.close()

func finish(state: Node, use_tool: bool = true) -> bool:
	var job: String = state.start_job()
	if use_tool: state.note_current_tool_used()
	return not state.complete_and_start_next_job(job, {"unique_clearance":1.0, "surface_clearance":1.0}).is_empty()

func buy_all_room(state: Node) -> void:
	for id: String in Room.IDS:
		while not bool(state.room_upgrade_view(id).maxed):
			var offer: Dictionary = state.room_upgrade_view(id)
			state.cash = maxf(float(offer.cost) * 2.0, state.progression_view().full_reward * 10.0)
			if not state.buy_room_upgrade(id):
				check(false, "Real room purchase failed for store%d/%s: %s" % [state.active_store, id, state.last_error])
				return
			check(state.progression_view().full_reward <= Rules.reward_cap(state.active_store), "Every paid room step stays within its store reward cap")

func run() -> void:
	check_rules()
	check_unlock_sequence()
	for path: String in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(path + ".tmp"): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	print("SECTION_PROGRESSION_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check_rules() -> void:
	var expected_caps := [4e5, 4e8, 4e12, 4e17, 4e24, 4e32]
	var expected_levels := [50, 75, 100, 125, 150, 175]
	check(Rules.STORE_COUNT == 6, "The authored first section contains six playable stores")
	check(Rules.section_available(1) and not Rules.section_available(2), "Only the first authored section is available")
	for store_id in range(1, Rules.STORE_COUNT + 1):
		check(Rules.section_for(store_id) == 1 and Rules.store_in_section(store_id) == store_id, "Each first-section store has a stable section and local position")
		check(Rules.room_level_cap(store_id) == expected_levels[store_id - 1] and Rules.reward_cap(store_id) == expected_caps[store_id - 1], "Store%d has its specified ladder and reward ceiling" % store_id)
		var branch := Rules.new_branch(store_id)
		Room.migrate_branch(store_id, branch)
		check(Room.early_reward(store_id, branch) * 2.0 == 40.0 * Rules.scale_for(store_id), "A fresh store starts from its specified base earnings")
		if store_id > 1:
			check(40.0 * Rules.scale_for(store_id) == Rules.reward_cap(store_id - 1), "The next place starts at the preceding place's mastered earnings")
	check(Money.format(Rules.reward_cap(1)) == "400K" and Money.format(Rules.reward_cap(6)).ends_with("AF"), "400K is first-store mastery and AF arrives at the section finale")
	check(Rules.scale_for(0) == 0 and Rules.scale_for(7) == 0 and Rules.reward_cap(7) <= 0, "Unknown stores have no usable economy scale")

func check_unlock_sequence() -> void:
	var state := fresh("sequence")
	check(state.active_store == 1 and state.stores.size() == 1 and not state.select_store(2) and not state.select_store(7), "A new save owns only its first place")
	for store_id in range(1, Rules.STORE_COUNT + 1):
		check(state.active_store == store_id and not state.progression_view().wet_unlocked, "All six first-section places use the brush mechanic")
		var unchanged: Dictionary = state._capture_state()
		check(not state.buy_hose_upgrade() and not state.buy_squeegee_upgrade() and state._capture_state() == unchanged, "First-section wet-tool purchases are unavailable and cannot spend coins")
		state.cash = maxf(10000.0 * Rules.scale_for(store_id), Rules.reward_cap(store_id) * 10.0)
		check(state.save_state(), "Store%d test funds save" % store_id)
		check(not state.open_next_store(), "Coins alone cannot unlock the next place")
		for _job in 3: check(finish(state), "Three real brush jobs preserve paid job history")
		for _upgrade in 4:
			var previous_power: float = state.progression_view().tool_power
			check(state.buy_tool_upgrade(), "Buy every local brush tier")
			if store_id >= 3: check(state.progression_view().tool_power > previous_power, "Every later numerical brush purchase increases physical cleaning power")
		for _job in 3: check(finish(state), "A paid rug using the local max brush advances mastery")
		check(not state.open_next_store(), "Tools, capstone rugs and funds cannot bypass unfinished room accessories")
		buy_all_room(state)
		check(state.progression_view().full_reward == Rules.reward_cap(store_id), "All accessories reach the exact full-clean cap for the player")
		check(state.reward_for_current_job({"unique_clearance":1.0,"surface_clearance":1.0}) == Rules.reward_cap(store_id), "The already-active unpaid rug has the exact fully mastered quote")
		var cap_job: String = state.active_job_id
		var old_cash: float = state.cash
		check(finish(state) and is_equal_approx(state.cash, old_cash + Rules.reward_cap(store_id)), "The exact mastered quote commits as one real full-clean payment")
		check(state.complete_and_start_next_job(cap_job, {"unique_clearance":1.0,"surface_clearance":1.0}).is_empty(), "A mastered carpet reward cannot be paid twice")
		state.cash = maxf(state.progression_view().travel_cost * 2.0, Rules.reward_cap(store_id) * 10.0)
		check(state.save_state(), "Mastered store state commits")
		var section: Dictionary = state.section_progress(1)
		check(int(section.completed) == store_id and int(section.total) == 6 and bool(section.complete) == (store_id == 6), "Section completion counts mastered places rather than ownership alone")
		check(not bool(section.next_available), "An unauthored next section stays unavailable")
		state = reload_state(state)
		check(state._save_enabled and state.active_store == store_id and state.stores.size() == store_id and state.progression_view().full_reward == Rules.reward_cap(store_id) and state.progression_view().tool_level == 4, "The current place, owned stores, brush cap and room cap survive reload")
		if store_id < Rules.STORE_COUNT:
			var before_cash: float = state.cash
			var opening: float = state.progression_view().travel_cost
			check(state.open_next_store() and state.active_store == store_id + 1 and is_equal_approx(state.cash, before_cash - opening), "Mastery opens exactly the next place and charges its stated opening fee once")
			check(state.select_store(store_id) and not state.open_next_store() and state.select_store(store_id + 1), "Returning restores the old place and cannot duplicate an already-owned purchase")
		else:
			var before: Dictionary = state._capture_state()
			check(not state.progression_view().has_next_store and not state.open_next_store() and not state.select_store(7) and state._capture_state() == before, "Completing all six cannot travel to or create an unauthored seventh place")
	state.free()
