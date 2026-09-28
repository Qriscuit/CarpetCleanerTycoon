extends "res://../tools/validate_wet_upgrades.gd"
## Regression coverage for the Shop 3 unlock contract; no real saves or GUI.

func run() -> void:
	check_unlock_flow()
	check_current_rug_use()
	check_legacy_progress()
	check_store_recipes()
	for path in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(path + ".tmp"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	print("STORE_UNLOCK_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func second_store(label: String) -> Node:
	var state := new_state(label)
	add_stores(state, 2)
	check(state.select_store(2), "Isolated Store 2 fixture opens")
	return state

func finish_wet(state: Node, use_hose: bool = true) -> bool:
	var job: String = state.start_job()
	if use_hose: state.note_current_tool_used(2)
	return not state.complete_and_start_next_job(job, wet_snapshot(1.0)).is_empty()

func check_unlock_flow() -> void:
	var state := second_store("unlock_flow")
	state.cash = 0
	state.save_state()
	var view: Dictionary = state.progression_view()
	check(view.travel_tool_name == "Water hose" and view.travel_tool_level == 0 and view.travel_tool_target == 4, "Store 2 names the hose as its actual unlock tool")
	check(view.travel_blockers.size() == 4 and view.travel_requirements.split("\n").size() == 4, "All four incomplete requirements have explicit checklist entries")
	for text: String in ["Water hose", "0/4", "0/3", "0/800", "0/16000"]:
		check(str(view.travel_requirements).contains(text), "Checklist exposes exact requirement " + text)
	check(not state.open_next_store() and state.last_error.contains("Water hose") and state.last_error.contains("0/3") and state.last_error.contains("800") and state.last_error.contains("16000"), "A denied opening explains each unmet requirement")
	state.cash = 100000
	state.save_state()
	for level in range(4):
		check(state.buy_tool_upgrade() and state.progression_view().hose_level == level + 1, "The main Store 2 tool button advances hose milestone " + str(level + 1))
	view = state.progression_view()
	check(view.tool_level == 4 and view.travel_tool_level == 4 and view.tool_name.contains("Water hose") and view.tool_cost == -1, "Main slot, capstone gate and hose purchase share the same level")
	check(state.stores["2"].tool_level == 0 and view.global_tool_tier == 4 and view.squeegee_level == 0, "Opening Shop 3 does not secretly require brush or squeegee upgrades")
	for job_index in range(3):
		check(finish_wet(state) and state.progression_view().final_tool_jobs == job_index + 1, "A paid max-hose rug advances the visible counter once")
	check(finish_wet(state) and state.progression_view().final_tool_jobs == 3, "Extra qualifying rugs do not overflow the three-rug checklist")
	state.stores["1"].bonzi_earned = 100000
	state.stores["2"].bonzi_earned = 799
	state.save_state()
	view = state.progression_view()
	check(not view.can_travel and view.travel_blockers.size() == 1 and str(view.travel_blockers[0]).contains("799/800"), "Old-store earnings cannot replace Store 2's local Bonzi target")
	state.stores["2"].bonzi_earned = 800
	state.cash = 15999
	state.save_state()
	view = state.progression_view()
	check(view.travel_ready and not view.can_travel and view.travel_blockers.size() == 1 and str(view.travel_blockers[0]).contains("15999/16000"), "The last missing opening coin is reported separately from completed milestones")
	state.cash = 16000
	state.save_state()
	view = state.progression_view()
	check(view.can_travel and view.travel_blockers.is_empty() and view.payout_level == 0, "Exact requirements unlock Shop 3 without an unadvertised payout-level gate")
	var before: Dictionary = state._capture_state()
	var path: String = state._save_path
	state._save_path += "/cannot-write.json"
	check(not state.open_next_store() and state._capture_state() == before, "A failed opening save preserves wallet, stores, active rug and checklist counters")
	state._save_path = path
	check(state.open_next_store() and state.active_store == 3 and state.cash == 0 and state.stores.has("3"), "Shop 3 opens and charges exactly 16000 once")
	state = reload_state(state)
	check(state.active_store == 3 and state.stores.has("3") and state.stores["2"].final_tool_jobs == 3, "Owned Shop 3 and the completed checklist survive restart")
	state.select_store(2)
	before = state._capture_state()
	check(not state.open_next_store() and state.last_error.contains("already open") and state._capture_state() == before, "An already-owned shop cannot be charged again and explains Visit")
	add_stores(state, 4)
	state.select_store(4)
	check(not state.open_next_store() and state.last_error.contains("final store"), "The final store does not invent another destination or requirements")
	state.free()

func check_current_rug_use() -> void:
	var state := second_store("current_rug")
	for _level in range(3): state.buy_hose_upgrade()
	var job: String = state.start_job()
	state.note_current_tool_used(2)
	check(not state.stores["2"].job_final_tool_used, "Hose activity before the final purchase cannot count retroactively")
	check(state.buy_hose_upgrade(), "The final hose can be bought while a rug is active")
	state.note_current_tool_used(0)
	state.note_current_tool_used(1)
	check(not state.stores["2"].job_final_tool_used, "Brush or squeegee activity cannot masquerade as max-hose use")
	state.note_current_tool_used(2)
	check(state.stores["2"].job_started_with_final_tool and state.stores["2"].job_final_tool_used, "A real hose contact after buying the capstone qualifies the existing rug")
	state.save_job_snapshot(wet_snapshot(0.5))
	state = reload_state(state)
	check(state.active_job_id == job and state.stores["2"].job_final_tool_used, "An in-progress qualifying rug retains its use flag across restart")
	var before: Dictionary = state._capture_state()
	var path: String = state._save_path
	state._save_path += "/cannot-write.json"
	check(state.complete_and_start_next_job(job, wet_snapshot(0.5)).is_empty() and state._capture_state() == before, "Failed completion cannot consume a qualifying rug or advance its counter")
	state._save_path = path
	check(not state.complete_and_start_next_job(job, wet_snapshot(0.5)).is_empty() and state.progression_view().final_tool_jobs == 1, "The current rug counts on successful paid completion, including a 75% finish")
	check(state.complete_and_start_next_job(job, wet_snapshot(1.0)).is_empty() and state.progression_view().final_tool_jobs == 1, "Repeated completion of the old rug cannot count twice")
	check(finish_wet(state, false) and state.progression_view().final_tool_jobs == 1, "Ownership alone does not qualify the next rug")
	state.start_job()
	state.note_current_tool_used()
	check(state.stores["2"].job_final_tool_used, "Compatibility callers default to the store's relevant tool")
	state.free()
	state = new_state("brush_use")
	state.cash = 5000
	state.save_state()
	state.start_job()
	for _level in range(4): state.buy_tool_upgrade()
	state.note_current_tool_used(2)
	check(not state.stores["1"].job_final_tool_used and state.progression_view().travel_tool_name == "Brush", "Store 1 still requires its brush, not a hose")
	state.note_current_tool_used(0)
	check(state.stores["1"].job_final_tool_used, "Store 1's mid-job capstone brush use qualifies correctly")
	state.free()

func check_legacy_progress() -> void:
	for old_level in [0, 2, 4]:
		var state := second_store("legacy_%d" % old_level)
		state.start_job()
		state.save_job_snapshot(wet_snapshot(0.6))
		var fixture: Dictionary = state._capture_state()
		fixture.stores["2"].tool_level = old_level
		fixture.stores["2"].hose_level = 1
		fixture.stores["2"].squeegee_level = 2
		fixture.stores["2"].final_tool_jobs = 2
		fixture.stores["2"].job_started_with_final_tool = true
		fixture.stores["2"].job_final_tool_used = true
		write_fixture(state._save_path, fixture)
		state = reload_state(state)
		var branch: Dictionary = state.stores["2"]
		var view: Dictionary = state.progression_view()
		check(branch.tool_level == old_level and branch.hose_level == maxi(old_level, 1) and branch.squeegee_level == 2, "Migration preserves and credits old Store 2 brush investment at level " + str(old_level))
		check(view.global_tool_tier == 4 + old_level and branch.final_tool_jobs == 2 and branch.job_started_with_final_tool and branch.job_final_tool_used, "Migration retains historical brush power, earned rugs and active qualification")
		var before_cash: int = state.cash
		check(not state.complete_and_start_next_job(state.active_job_id, wet_snapshot(0.6)).is_empty() and state.progression_view().final_tool_jobs == 3 and state.cash == before_cash + 160, "A previously qualifying saved rug keeps its earned completion credit")
		if int(view.hose_level) < 4:
			check(state.buy_hose_upgrade() and state.stores["2"].tool_level == old_level, "Future hose purchases do not overwrite old brush power")
		state.free()

func check_store_recipes() -> void:
	var state := second_store("recipes")
	state.start_job()
	for pair: Array in [[0.4999, 0], [0.5, 160], [0.9799, 160], [0.98, 320], [1.0, 320]]:
		check(state.reward_for_current_job(wet_snapshot(pair[0], 1.0, 0.0)) == pair[1], "Store 2 uses only water and extraction for reward tier " + str(pair[0]))
	var wrong_recipe := wet_snapshot(1.0)
	wrong_recipe.erase("skip_dry_stage")
	check(state.reward_for_current_job(wrong_recipe) == 0, "Store 2 rejects old three-stage completion snapshots")
	check(state.reward_for_current_job(wet_snapshot(1.0, 0.9899)) == 0, "Store 2 cannot extract before full water coverage")
	add_stores(state, 3)
	state.select_store(3)
	state.start_job()
	check(state.reward_for_current_job(wet_snapshot(1.0, 1.0, 0.0)) == 0, "Store 3 cannot use the two-stage flag to bypass its dry stage")
	wrong_recipe = wet_snapshot(1.0, 1.0, 0.0)
	wrong_recipe.erase("skip_dry_stage")
	check(state.reward_for_current_job(wrong_recipe) == 0, "Store 3 still validates actual dry clearance")
	wrong_recipe.unique_clearance = 1.0
	wrong_recipe.surface_clearance = 1.0
	check(state.reward_for_current_job(wrong_recipe) == 2560, "Store 3 still awards a valid full three-stage rug")
	state.free()
