extends SceneTree
## Manual upgrades preserve the live rug; mastery retains only player-work gates.
const State := preload("res://scripts/shop_state.gd")
const Rules := preload("res://scripts/progression.gd")
const Room := preload("res://scripts/room_upgrades.gd")
var checks := 0
var failures := 0
var path := ""

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PROGRESSION: " + message)

func complete(state: Node, use_tool: bool = true) -> bool:
	var job: String = state.start_job()
	if use_tool: state.note_current_tool_used(0)
	return not state.complete_and_start_next_job(job,{"unique_clearance":1.0,"surface_clearance":1.0}).is_empty()

func run() -> void:
	var state := State.new()
	path = "res://.godot/manual_progression_%d.json" % OS.get_process_id()
	state._save_path = path
	root.add_child(state)
	check(state.progression_view().full_reward == 40.0 and state.room_upgrade_view("plants").cost == 25.0 and not state.progression_view().can_travel, "Starter manual prices, rewards and locked travel are intact")
	check(not state.select_store(2) and not state.open_next_store(), "An unowned store cannot be visited or opened without requirements")
	var job: String = state.start_job()
	check(state.save_job_snapshot({"unique_clearance":0.2,"surface_clearance":0.3,"pixels":[7,8]}), "A disposable active rug has unfinished saved work")
	state.cash = 100.0
	check(state.buy_room_upgrade("floor") and state.cash == 60.0 and state.current_job_full_reward() == 46.0 and state.active_job_id == job and state.job_snapshot.pixels == [7,8], "The real floor purchase rebases the current quote and preserves its masks")
	var before: Dictionary = state._capture_state()
	state._save_path += "/blocked.json"
	check(not state.buy_room_upgrade("plants") and state._capture_state() == before, "A failed room purchase rolls back money, level and current quote")
	state._save_path = path
	check(state.buy_room_upgrade("plants") and state.cash == 35.0 and state.current_job_full_reward() == 50.0, "The room purchase retries at its exact price")
	state.cash = Rules.reward_cap(1) * 10.0
	check(state.save_state(), "Mastery fixture funds save")
	check(complete(state,false) and state.progression_view().final_tool_jobs == 0, "A paid rug without max-brush work cannot qualify")
	for level in range(4):
		var price: float = state.progression_view().tool_cost
		var wallet: float = state.cash
		check(state.buy_tool_upgrade() and state.cash == wallet-price and state.progression_view().tool_level == level+1, "Each local brush purchase charges the displayed price once")
	check(not state.buy_tool_upgrade(), "The four-upgrade brush ladder rejects a fifth purchase")
	check(complete(state,false) and state.progression_view().final_tool_jobs == 0, "Max-brush ownership without actual use cannot qualify")
	for count in range(1,4):
		check(complete(state) and state.progression_view().final_tool_jobs == count, "Each real max-brush rug advances the three-job requirement")
	check(not state.store_mastered(1) and not state.open_next_store(), "Max brush, its three jobs and funds cannot bypass incomplete room ladders")
	var branch: Dictionary = state._branch()
	for id: String in Room.IDS:
		branch.room_upgrades[id] = Rules.room_level_cap(1)
	branch.payout_level = Room.total_levels(branch.room_upgrades)
	state.cash = 1999.0
	check(state.save_state() and state.store_mastered(1) and not state.progression_view().can_travel, "Manual mastery is complete before the separate opening-money gate")
	check(state.progression_view().travel_blockers.size() == 1 and state.progression_view().travel_blockers[0].begins_with("Opening coins"), "The opening checklist has only the unmet coin requirement")
	state.cash = 2000.0
	check(state.save_state() and state.open_next_store() and state.active_store == 2 and state.cash == 0.0 and state.stores.size() == 2, "Exact opening funds unlock and select one next store")
	check(state.select_store(1) and not state.open_next_store() and state.select_store(2), "Owned-store visits are free and cannot purchase the store twice")
	check(state.progression_view().full_reward == 400000.0 and not state.progression_view().wet_unlocked and state.progression_view().tool_power > 1.0, "The next brush store starts at its scale and retains the strongest owned tool")
	state.free()
	state = State.new()
	state._save_path = path
	root.add_child(state)
	check(state.active_store == 2 and state.stores.size() == 2 and state.cash == 0.0 and state.store_mastered(1), "Current-store selection, ownership and manual mastery persist together")
	check(not state.section_progress(1).complete and not state.section_progress(1).next_available, "One mastered store cannot complete the six-store section")
	state.free()
	for suffix: String in ["", ".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("PROGRESSION_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
