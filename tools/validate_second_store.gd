extends SceneTree
## Current production Store 2: dry manual cleaning, durable identity and upgrades.
## Wet simulation is covered separately by the Gym, hose and wash validators.
## Run through tools/run_godot.ps1 with: --headless --path CarpetToy --script ../tools/validate_second_store.gd -- --shop-test

const Progression = preload("res://scripts/progression.gd")
const Catalog = preload("res://scripts/rug_catalog.gd")
const Routes = preload("res://scripts/scene_routes.gd")
const CLEANING_SCENE := preload("res://scenes/production/rug_cleaning.tscn")

var checks := 0
var failures := 0
var state: Node
var game: Node


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test so this validation cannot touch player progress.")
		quit(2)
		return
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SECOND STORE: " + message)


func settle() -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func enter_cleaning() -> Node:
	var instance := CLEANING_SCENE.instantiate()
	instance.animate_rug_changes = false
	root.add_child(instance)
	current_scene = instance
	await settle()
	return instance


func leave_cleaning() -> void:
	if is_instance_valid(game):
		game.free()
	game = null
	current_scene = null


func settle_debris(soil: Node) -> void:
	for _step in 720:
		if not soil.is_physics_processing(): break
		soil._physics_process(1.0 / 120.0)


func check_dry_store(store_id: int) -> void:
	check(game.paid_contract and not game.wet_recipe and not game.water_only_recipe and not game.soil.wet_recipe and not game.soil.skip_dry_stage, "Store %d uses the paid dry recipe" % store_id)
	check(game.selected_tool == 0 and game.soil.remaining > 0, "Store %d starts with the brush and physical dirt" % store_id)
	check(not is_instance_valid(game.water) and not is_instance_valid(game.squeegee_water), "Store %d allocates neither hose nor extraction VFX" % store_id)
	game.hud.open_upgrades()
	check(not game.hud.control("HoseUpgradeButton").is_visible_in_tree() and not game.hud.control("SqueegeeUpgradeButton").is_visible_in_tree(), "Store %d hides wet purchases" % store_id)
	game.hud.close_upgrades()


func run() -> void:
	state = root.get_node("ShopState")
	state._save_path = "res://.godot/second_store_%d.json" % OS.get_process_id()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	check(state.reset_progress(), "isolated current-schema ledger resets")
	# Fixture ownership bypasses only the already-covered travel grind. Every
	# following purchase, physical stroke and scene checkpoint uses live APIs.
	state.stores["2"] = Progression.new_branch(2)
	check(state.select_store(2), "select the owned second store")
	state.cash = 1.0e14
	check(not state.start_job().is_empty(), "Store 2 reserves a paid job")
	var job_id: String = state.active_job_id
	var rug_id: String = state.active_rug_id
	game = await enter_cleaning()
	var soil: Node = game.soil
	check_dry_store(2)
	check(game.scene_file_path == Routes.CLEANING and game.contract_job_id == job_id, "production route opens the reserved job")
	check(Catalog.IDS[game.selected_rug] == rug_id and str(soil.rug_definition.rug_id) == rug_id, "selected art and physical rug match the ledger identity")
	check(soil.unique_clearance() == 0.0 and soil.surface_clearance() == 0.0 and game.progress_fraction == 0.0, "fresh Store 2 rug begins completely dirty")
	var pristine: Dictionary = soil.make_snapshot()
	var idle_cash: float = state.cash
	await create_timer(0.08).timeout
	check(state.cash == idle_cash and soil.make_snapshot() == pristine, "idle time cannot earn money or clean the rug")
	game.select_tool(1)
	game.select_tool(2)
	game.select_rug((game.selected_rug + 1) % Catalog.IDS.size())
	check(game.selected_tool == 0 and Catalog.IDS[game.selected_rug] == rug_id and soil.make_snapshot() == pristine, "paid job rejects wet tools and art rerolls")

	game.hud.open_upgrades()
	for level in 4:
		var before: Dictionary = state.progression_view()
		var wallet: float = state.cash
		(game.hud.control("ToolUpgradeButton") as Button).pressed.emit()
		var after: Dictionary = state.progression_view()
		check(int(after.tool_level) == level + 1 and is_equal_approx(state.cash, wallet - float(before.tool_cost)), "brush purchase %d charges its current price once" % (level + 1))
		check(int(after.hose_level) == 0 and int(after.squeegee_level) == 0 and int(state.stores["1"].tool_level) == 0, "brush purchase %d changes only the local dry upgrade" % (level + 1))
		check(state.active_job_id == job_id and state.active_rug_id == rug_id and soil.make_snapshot() == pristine, "brush purchase %d preserves job identity and every dirt pixel" % (level + 1))
	check(is_equal_approx(game.dry_tool_power, float(state.progression_view().tool_power)) and is_equal_approx(game.tool_width, float(state.progression_view().tool_width)), "live brush uses the strongest owned power and width")
	check(not bool(state._branch().job_final_tool_used), "max-brush ownership alone earns no use credit")
	game.hud.close_upgrades()
	game.apply_selected_tool_stroke(Vector3(5.0, 0.067, 5.0), Vector3(5.2, 0.067, 5.2), 0.08)
	check(not bool(state._branch().job_final_tool_used) and soil.make_snapshot() == pristine, "pointer motion away from the rug earns no work or mastery")
	game.apply_selected_tool_stroke(soil.rug_node.to_global(Vector3(-0.3, 0.0, -0.4)), soil.rug_node.to_global(Vector3(0.3, 0.0, -0.4)), 0.08)
	settle_debris(soil)
	check(soil.surface_clearance() > 0.0 and soil.surface_clearance() < 0.75, "actual manual brush contact makes partial dry progress")
	check(bool(state._branch().job_final_tool_used), "actual max-brush contact earns the travel-use credit")
	check(game.save_contract_progress(), "partial manual work checkpoints successfully")
	var partial: Dictionary = soil.make_snapshot()
	var saved_cash: float = state.cash
	leave_cleaning()
	state._load_state()
	check(state._save_enabled and state.active_store == 2 and state.active_job_id == job_id and state.active_rug_id == rug_id and state.cash == saved_cash, "current-schema disk reload preserves Store 2, job identity and wallet")
	game = await enter_cleaning()
	soil = game.soil
	var restored: Dictionary = soil.make_snapshot()
	check(str(restored.rug_id) == rug_id and restored.coverage == partial.coverage and restored.credited == partial.credited, "scene reentry preserves the exact saved surface mask and debris credits")
	check(absf(soil.surface_clearance() - float(partial.surface_clearance)) < 0.005 and absf(soil.unique_clearance() - float(partial.unique_clearance)) < 0.001, "scene reentry retains partial manual progress within mask quantization")
	check(int(state.progression_view().tool_level) == 4 and bool(state._branch().job_final_tool_used) and state.cash == saved_cash, "upgrades and real-use credit persist without a reload payout")
	game.return_to_shop()
	await settle()
	game = null
	check(current_scene != null and current_scene.scene_file_path == Routes.MAIN_MENU and current_scene.preview_store == 2 and state.active_store == 2, "Back returns to the selected second store in the production home")
	check(state.active_job_id == job_id and state.active_rug_id == rug_id and not state.contract_mode, "Back preserves the unfinished manual job")
	if current_scene != null:
		current_scene.free()
	current_scene = null

	# Preserve the delayed-clump regression: a brush can move debris on a fully
	# swept mask before physics actually pushes it off the carpet. Only that
	# later contact result may grant max-brush use credit.
	check(state.select_store(1), "return to the owned first store")
	check(not state.start_job().is_empty(), "Store 1 reserves its own manual job")
	for _level in 4:
		check(state.buy_tool_upgrade(), "Store 1 owns its own max-brush upgrades")
	game = await enter_cleaning()
	check_dry_store(1)
	soil = game.soil
	soil.surface_coverage_total = 0.0
	soil.coverage_values.fill(0.0)
	soil.mask.fill(Color.BLACK)
	soil.mask_changed = true
	var edge_clump := 0
	for index in soil.positions.size():
		if soil.positions[index].z > soil.positions[edge_clump].z:
			edge_clump = index
	var edge_position: Vector3 = soil.positions[edge_clump]
	var before_remaining: int = soil.remaining
	game.apply_selected_tool_stroke(soil.rug_node.to_global(edge_position + Vector3(0.0, 0.0, -0.22)), soil.rug_node.to_global(edge_position + Vector3(0.0, 0.0, 0.22)), 0.08)
	check(not bool(state._branch().job_final_tool_used), "clump motion without a cleanliness delta is not credited early")
	for _step in 360:
		soil._physics_process(1.0 / 120.0)
		if soil.remaining < before_remaining: break
	check(soil.remaining < before_remaining and bool(state._branch().job_final_tool_used), "a clump actually leaving the carpet earns max-brush use credit")
	leave_cleaning()

	# All currently available stores share the same manual-only allocation
	# boundary. Future wet recipes must not leak into this six-store section.
	for store_id in range(3, Progression.STORE_COUNT + 1):
		state.stores[str(store_id)] = Progression.new_branch(store_id)
		check(state.select_store(store_id) and not state.start_job().is_empty(), "Store %d reserves a current-schema manual job" % store_id)
		game = await enter_cleaning()
		check_dry_store(store_id)
		leave_cleaning()
	# Let the audio server release the final stopped brush stream after the
	# scene teardown before asking the engine to report shutdown leaks.
	await create_timer(0.1).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("SECOND_STORE_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
