extends SceneTree
## Focused production integration for Store 2's hose -> squeegee job.
## Run through tools/run_godot.ps1 with: --path CarpetToy --script ../tools/validate_second_store_wet.gd -- --shop-test

const Progression = preload("res://scripts/progression.gd")
const ShopLedger = preload("res://scripts/shop_state.gd")
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
		push_error("SECOND STORE WET: " + message)


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


func set_dry_clearance(soil: Node, fraction: float) -> void:
	var target := clampf(fraction, 0.0, 1.0)
	var cleared_count := clampi(roundi(float(soil.initial.size()) * target), 0, soil.initial.size())
	soil.active.clear()
	soil.remaining = soil.initial.size() - cleared_count
	for index in soil.initial.size():
		var cleared: bool = index < cleared_count
		soil.credited[index] = cleared
		soil.cleared[index] = cleared
		soil.moving[index] = false
		soil.velocities[index] = Vector3.ZERO
		soil.growth[index] = 0.0 if cleared else soil.initial_growth[index]
	var coverage := 1.0 - target
	soil.surface_coverage_total = 0.0
	for index in soil.coverage_values.size():
		var value := coverage if soil.surface_pixels[index] != 0 else 0.0
		soil.coverage_values[index] = value
		soil.mask.set_pixel(index % soil.MASK_SIZE.x, index / soil.MASK_SIZE.x, Color(value, value, value))
		if soil.surface_pixels[index] != 0:
			soil.surface_coverage_total += value
	soil.mask_changed = true
	soil.request_render()


func set_wet_clearances(soil: Node, water_fraction: float, extraction_fraction: float) -> void:
	var wet := clampf(water_fraction, 0.0, 1.0)
	var extracted := clampf(extraction_fraction, 0.0, wet)
	soil.water_coverage_total = 0.0
	soil.extraction_coverage_total = 0.0
	for index in soil.water_values.size():
		if soil.surface_pixels[index] == 0:
			soil.water_values[index] = 0.0
			soil.extraction_values[index] = 0.0
			continue
		soil.water_values[index] = wet
		soil.extraction_values[index] = extracted
		soil.water_coverage_total += wet
		soil.extraction_coverage_total += extracted
		var visible := wet - extracted
		soil.wet_mask.set_pixel(index % soil.MASK_SIZE.x, index / soil.MASK_SIZE.x, Color(visible, visible, visible))
	soil.wet_mask_changed = true
	soil.request_render()


func advance_water(water: Node, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001 and water.is_processing():
		var step := minf(remaining, 1.0 / 120.0)
		water._process(step)
		remaining -= step


func run() -> void:
	state = root.get_node("ShopState")
	state.set_process(false)
	state._test_ticks_msec = 0
	state._test_unix_time = 2000000.0
	state._save_path = "res://.godot/second_store_wet_%d.json" % OS.get_process_id()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	check(state.reset_progress(), "isolated ledger resets")
	state._sync_active_branch()
	state.stores["2"] = Progression.new_branch(2)
	state.active_store = 2
	state._load_active_branch()
	state.cash = 1000000
	check(not state.start_job().is_empty(), "Store 2 has a paid job")

	# A fresh High Street rug starts clean-dry on the hose: no brush stage or
	# visible dirt reveal is allowed before the two wet actions.
	game = await enter_cleaning()
	var soil: Node = game.soil
	check(game.paid_contract and game.wet_recipe and game.water_only_recipe and soil.wet_recipe and soil.skip_dry_stage, "High Street is a paid water-only recipe")
	check(soil.unique_clearance() == 1.0 and soil.surface_clearance() == 1.0 and soil.remaining == 0, "fresh Store 2 dirt is already cleared")
	check(game.selected_tool == 2 and game.progress_fraction == 0.0 and soil.recommended_tool() == 2, "fresh Store 2 starts at zero progress with the hose")
	soil._process(0.0)
	check(soil.batch.visible_instance_count == 0, "fresh Store 2 never reveals dry clumps")
	game.select_tool(0)
	check(game.selected_tool == 2, "the obsolete brush cannot be selected in Store 2")
	var before_early_extract: float = float(soil.extraction_coverage_total)
	soil.apply_squeegee_stroke(Vector3(-0.4, 0.067, 0.0), Vector3(0.4, 0.067, 0.0), 0.08)
	check(soil.extraction_coverage_total == before_early_extract, "squeegee cannot bypass the water stage")

	# Manufacture a legacy three-stage Store 2 save with partial dirt, water and
	# extraction. Migration clears only dry work and preserves both wet masks.
	set_dry_clearance(game.soil, 0.42)
	set_wet_clearances(game.soil, 1.0, 0.12)
	var legacy_dry: Dictionary = game.soil.make_snapshot()
	legacy_dry["skip_dry_stage"] = false
	var expected_water := float(legacy_dry.water_clearance)
	var expected_extraction := float(legacy_dry.extraction_clearance)
	leave_cleaning()
	state.job_snapshot = legacy_dry.duplicate(true)
	state._branch().job_snapshot = legacy_dry.duplicate(true)

	game = await enter_cleaning()
	soil = game.soil
	check(game.paid_contract and game.wet_recipe and game.water_only_recipe and soil.wet_recipe and soil.skip_dry_stage, "legacy High Street save adopts the water-only recipe")
	check(is_instance_valid(game.water) and is_instance_valid(game.squeegee_water), "paid Store 2 allocates the real hose and squeegee effects")
	check(game.water.enabled and game.squeegee_water.enabled and game.water.stream != null and game.squeegee_water.trail != null, "both bounded VFX systems are configured and enabled")
	check(soil.unique_clearance() == 1.0 and soil.surface_clearance() == 1.0 and soil.remaining == 0, "migration clears only the obsolete dry layer")
	check(absf(soil.water_clearance() - expected_water) < 0.01 and absf(soil.extraction_clearance() - expected_extraction) < 0.01, "migration preserves saved water and extraction")
	check(game.selected_tool == 1 and absf(game.progress_fraction - (soil.water_clearance() + soil.extraction_clearance()) * 0.5) < 0.0001, "migrated job resumes the saved squeegee stage with two-stage progress")
	# Continue the remaining checks from a partial hose stage in the same migrated
	# job; this fixture change is not a recipe migration or runtime reset.
	set_wet_clearances(soil, 0.36, 0.0)
	game.update_contract_status()
	game.end_stroke()
	await settle()
	check(game.selected_tool == 2, "a partial-water Store 2 job consistently selects the hose")

	# Purchase each wet tool through its independent paid HUD signal. Neither
	# purchase may change the other level, the current job, or any rug pixels.
	var job_before: String = state.active_job_id
	var rug_before: Dictionary = soil.make_snapshot()
	game.hud.open_upgrades()
	# Store 2's main tool card is the hose; extraction remains an independent row.
	(game.hud.control("ToolUpgradeButton") as Button).pressed.emit()
	var hose_view: Dictionary = state.progression_view()
	check(int(hose_view.hose_level) == 1 and int(hose_view.squeegee_level) == 0, "hose purchase advances only the hose")
	check(game.hose_upgrade_level == int(hose_view.effective_hose_level) and game.water.upgrade_level == int(hose_view.effective_hose_level), "paid hose profile follows the strongest owned level")
	check(is_equal_approx(game.hose_direct_power, float(hose_view.hose_power)), "paid direct contact uses the ledger hose power")
	(game.hud.control("SqueegeeUpgradeButton") as Button).pressed.emit()
	var both_view: Dictionary = state.progression_view()
	check(int(both_view.hose_level) == 1 and int(both_view.squeegee_level) == 1, "squeegee purchase is independent of the hose")
	check(is_equal_approx(game.squeegee_power, float(both_view.squeegee_power)), "paid extraction uses the strongest ledger squeegee power")
	check(state.active_job_id == job_before and soil.make_snapshot() == rug_before, "wet upgrades preserve the current job and every rug mask")
	for _level in range(int(both_view.hose_level), 4):
		(game.hud.control("ToolUpgradeButton") as Button).pressed.emit()
	var max_hose_view: Dictionary = state.progression_view()
	check(int(max_hose_view.hose_level) == 4 and not bool(state._branch().job_final_tool_used), "mid-job max hose ownership alone does not earn use credit")
	game.hud.close_upgrades()
	game.apply_selected_tool_stroke(Vector3(-0.2, 0.067, 0.0), Vector3(0.2, 0.067, 0.0), 0.08)
	check(not bool(state._branch().job_final_tool_used), "hose pointer motion without a water-mask delta earns no use credit")

	# Use the actual equipped ballistic hose. Pointer travel itself must not
	# paint; only the connected carpet-contact signal may.
	game.update_contract_status()
	game.end_stroke()
	await settle()
	check(game.selected_tool == 2 and game.progress_fraction > 0.17 and game.progress_fraction < 0.19, "partial legacy wet work resumes at its two-stage average")
	var hose_screen: Vector2 = game.camera.unproject_position(Vector3(0.0, 0.067, -0.25))
	game.begin_stroke(hose_screen, false)
	check(game.brush_dragging and game.water.emitting and game.water.nozzle.distance_to(game.nozzle_socket.global_position) < 0.001, "the paid tool starts emission from its 3D nozzle socket")
	var before_hose: float = float(soil.water_coverage_total)
	advance_water(game.water, 1.2)
	check(game.water.wet_events > 0 and soil.water_coverage_total > before_hose, "ballistic contact, not a bare pointer stroke, wets the paid rug")
	check(bool(state._branch().job_started_with_final_tool) and bool(state._branch().job_final_tool_used), "actual max-hose contact earns the travel-use credit")
	check(game.water.visible_rings > 0 and game.water.impact != null and game.water.soak != null, "paid hose renders its stream, impact and bounded soak presentation")
	game.end_stroke()
	advance_water(game.water, 1.0)
	soil._process(0.0)
	var saved_water: float = float(soil.water_clearance())
	var saved_extraction: float = float(soil.extraction_clearance())
	check(saved_water > 0.0 and game.save_contract_progress(), "partial paid hose progress saves")
	leave_cleaning()

	game = await enter_cleaning()
	soil = game.soil
	check(game.wet_recipe and game.water_only_recipe and soil.skip_dry_stage and game.selected_tool == 2, "water-only save reload resumes the correct hose stage")
	check(absf(soil.water_clearance() - saved_water) < 0.01 and absf(soil.extraction_clearance() - saved_extraction) < 0.01, "wet mask reload retains both wet stages")
	check(game.water.upgrade_level == int(state.progression_view().effective_hose_level) and is_equal_approx(game.squeegee_power, float(state.progression_view().squeegee_power)), "paid wet upgrades survive scene re-entry")

	# Saturate through the shared contact painter, then exercise the production
	# rotated blade path and its visual-only splash/trail companion.
	check(soil.apply_water_blob(soil.rug_node.to_global(Vector3.ZERO), soil.RUG_HALF.length() * 2.0, 1.0, 0.01), "shared hose contact painter can finish the water stage")
	game.update_contract_status()
	game.end_stroke()
	await settle()
	check(game.selected_tool == 1 and game.water.emission_locked, "99% water gate locks in-flight wetting and equips the squeegee")
	var locked_mask := hash(soil.wet_mask.get_data())
	advance_water(game.water, 1.0)
	check(hash(soil.wet_mask.get_data()) == locked_mask, "locked hose cannot leak delayed wetness into extraction")
	var before_extract: float = float(soil.extraction_coverage_total)
	game.apply_selected_tool_stroke(Vector3(-0.55, 0.067, -0.2), Vector3(0.55, 0.067, 0.15), 0.08)
	var squeegee_stats: Dictionary = game.squeegee_water.debug_stats()
	check(soil.extraction_coverage_total > before_extract and game.squeegee_motion.tracking, "paid rotated squeegee removes water with tracked heading")
	check(int(squeegee_stats.emitted_strokes) > 0 and float(squeegee_stats.removed_water) > 0.0, "paid squeegee funds its real head splash and cleared-path trail")
	check(is_equal_approx(soil.tool_strength, float(state.progression_view().squeegee_power)), "squeegee applies its independent global extraction strength")

	# Water complete plus 50% extraction is exactly 75% overall. At 98%
	# extraction the two-stage average is exact 99%, including float epsilon.
	set_wet_clearances(soil, 1.0, 0.50)
	game.update_contract_status()
	check(ShopLedger.completion_reached(game.progress_fraction, ShopLedger.MANUAL_COMPLETION_THRESHOLD) and game.finish_button.visible, "two-stage 75% exposes manual Finish")
	var full_job: String = state.active_job_id
	set_wet_clearances(soil, 1.0, 0.98)
	game.update_contract_status()
	check(game.auto_finish_queued, "two-stage exact 99% queues automatic completion")
	await process_frame
	check(game.contract_finished and state.active_job_id != full_job, "full Store 2 wet job pays once and reserves its replacement")
	leave_cleaning()

	# Later wet stores retain the original brush -> hose -> squeegee recipe and
	# three-way progress arithmetic.
	for store_id in [3, 4]:
		state._sync_active_branch()
		state.stores[str(store_id)] = Progression.new_branch(store_id)
		state.active_store = store_id
		state._load_active_branch()
		state.cash = 1000000000
		check(not state.start_job().is_empty(), "Store %d has a paid job" % store_id)
		game = await enter_cleaning()
		soil = game.soil
		check(game.wet_recipe and not game.water_only_recipe and not soil.skip_dry_stage and game.selected_tool == 0, "Store %d retains the three-stage brush start" % store_id)
		set_dry_clearance(soil, 0.50)
		set_wet_clearances(soil, 0.40, 0.20)
		check(absf(soil.overall_clearance() - (0.50 + 0.40 + 0.20) / 3.0) < 0.002, "Store %d retains three-stage progress averaging" % store_id)
		check(not soil.apply_water_blob(Vector3.ZERO, 0.5, 1.0), "Store %d hose cannot bypass dry work" % store_id)
		leave_cleaning()

	# Neighborhood remains the original dry-only contract and does not allocate
	# either wet presentation system.
	check(state.select_store(1), "return to the owned first store")
	if state.active_job_id.is_empty():
		check(not state.start_job().is_empty(), "Store 1 has a paid job")
	for _level in range(int(state.progression_view().tool_level), 4):
		check(state.buy_tool_upgrade(), "Store 1 brush upgrade succeeds")
	check(not bool(state._branch().job_final_tool_used), "mid-job max brush ownership alone does not earn use credit")
	game = await enter_cleaning()
	check(not game.wet_recipe and not game.soil.wet_recipe and game.selected_tool == 0, "Store 1 remains dry brush gameplay")
	check(not is_instance_valid(game.water) and not is_instance_valid(game.squeegee_water), "Store 1 does not allocate wet VFX")
	# With the surface mask already clean, only a clump crossing the edge changes
	# dry progress. Its delayed physics signal must still credit real brush use.
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
	game.apply_selected_tool_stroke(
		soil.rug_node.to_global(edge_position + Vector3(0.0, 0.0, -0.22)),
		soil.rug_node.to_global(edge_position + Vector3(0.0, 0.0, 0.22)),
		0.08
	)
	check(not bool(state._branch().job_final_tool_used), "clump motion without a cleanliness delta is not credited early")
	for _step in 360:
		soil._physics_process(1.0 / 120.0)
		if soil.remaining < before_remaining:
			break
	check(soil.remaining < before_remaining and bool(state._branch().job_final_tool_used), "a clump actually leaving the clean surface earns max-brush use credit")
	game.hud.open_upgrades()
	check(not game.hud.control("HoseUpgradeButton").is_visible_in_tree() and not game.hud.control("SqueegeeUpgradeButton").is_visible_in_tree(), "Store 1 hides wet purchases")
	game.hud.close_upgrades()
	leave_cleaning()

	state.set_process(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("SECOND_STORE_WET_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
