extends SceneTree
## Current paid stores do not sell wet tools; free Gym water mechanics remain separate.
const State := preload("res://scripts/shop_state.gd")
const Rules := preload("res://scripts/progression.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PAID WET GATES: " + message)

func run() -> void:
	var state := State.new()
	var path := "res://.godot/paid_wet_gates_%d.json" % OS.get_process_id()
	state._save_path = path
	root.add_child(state)
	for store_id in range(1,Rules.STORE_COUNT+1):
		if store_id > 1: state.stores[str(store_id)] = Rules.new_branch(store_id)
		check(state.select_store(store_id), "The owned brush-store fixture selects normally")
		state.cash = Rules.reward_cap(store_id)*10.0
		var job: String = state.start_job()
		check(state.save_job_snapshot({"unique_clearance":0.2,"surface_clearance":0.3,"marker":"paid-brush"}), "A paid brush rug checkpoints")
		var before: Dictionary = state._capture_state()
		var view: Dictionary = state.progression_view()
		check(not view.wet_unlocked and not view.can_upgrade_hose and not view.can_upgrade_squeegee and view.hose_cost < 0 and view.squeegee_cost < 0, "Each current store exposes no paid wet offers")
		check(not state.buy_hose_upgrade() and not state.buy_squeegee_upgrade() and state._capture_state() == before, "Blocked wet purchases cannot spend money or mutate progress")
		check(state.buy_tool_upgrade() and state._branch().tool_level == 1 and state._branch().hose_level == 0 and state._branch().squeegee_level == 0, "A brush upgrade changes only the brush track")
		check(state.active_job_id == job and state.job_snapshot.marker == "paid-brush", "The independent brush purchase retains the current paid rug")
	state.free()
	for suffix: String in ["", ".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("WET_UPGRADES_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
