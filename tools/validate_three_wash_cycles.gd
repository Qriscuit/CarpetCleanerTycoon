extends SceneTree
## Real production soil and ledger; run with the pinned toolchain and -- --shop-test.
const Soil := preload("res://scripts/dirt_controller.gd")
const State := preload("res://scripts/shop_state.gd")
const Rules := preload("res://scripts/progression.gd")
const CLEANING := preload("res://scenes/production/rug_cleaning.tscn")
var checks := 0
var failures := 0
var soil: Node
var rug: Node3D
var save_path := ""

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Refusing to run without -- --shop-test")
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("THREE WASH CYCLES: " + message)

func new_soil() -> void:
	rug = Node3D.new()
	var dirty := (load("res://scenes/dirty_carpet.tscn") as PackedScene).instantiate()
	dirty.name = "Dirty"
	rug.add_child(dirty)
	root.add_child(rug)
	soil = Soil.new()
	soil.automatic_completion_enabled = false
	root.add_child(soil)
	soil.setup(rug)
	soil.set_recipe(true, true)
	soil.prepare_water_stage()

func local_point(x: float, z: float) -> Vector3:
	return rug.to_global(Vector3(x, 0.067, z))

func uniform_water() -> bool:
	var expected: float = soil.water_clearance()
	for index in soil.water_values.size():
		if soil.surface_pixels[index] == 1 and absf(soil.water_values[index] - expected) > 0.00002:
			return false
	return true

func no_extraction() -> bool:
	for value in soil.extraction_values:
		if value != 0.0: return false
	return true

func saturate_corner() -> void:
	for _contact in 80:
		if soil.water_stage_complete(): break
		soil.apply_water_blob(local_point(0.82, 1.25), 0.19, 1.0)
	soil._process(0.0)

func extract_all() -> void:
	soil.set_tool_strength(9.261)
	for _pass in 3:
		if soil.extraction_stage_complete(): break
		for row in 36:
			var z := -1.75 + float(row) * 0.1
			soil.apply_squeegee_stroke(local_point(-1.3, z), local_point(1.3, z), 0.08)
	soil._process(0.0)

func validate_global_water() -> void:
	check(soil.wash_cycle == 0 and soil.overall_clearance() == 0.0 and soil.recommended_tool() == 2,
		"A fresh wet carpet starts on the first of three wash cycles")
	var untouched: Dictionary = soil.make_snapshot()
	check(not soil.apply_water_blob(local_point(4.0, 4.0), 0.19, 1.0)
		and soil.make_snapshot() == untouched, "Off-carpet watering cannot advance the meter")
	check(soil.apply_water_blob(local_point(0.0, 0.0), 0.19, 0.4), "Center contact adds water")
	var center_amount: float = soil.water_clearance()
	check(center_amount > 0.0 and uniform_water(), "The first contact wets every carpet pixel uniformly")
	check(soil.restore_snapshot(untouched), "Reset the fixture from its real snapshot")
	check(soil.apply_water_blob(local_point(0.82, 1.25), 0.19, 0.4), "Corner contact adds water")
	check(absf(soil.water_clearance() - center_amount) < 0.000001 and uniform_water(),
		"Equal corner and center contact produces equal whole-carpet progress")
	for point in [Vector2(0.82, 1.25), Vector2.ZERO, Vector2(-0.75, -1.2)]:
		var before: float = soil.water_clearance()
		soil.apply_water_blob(local_point(point.x, point.y), 0.19, 0.4)
		check(soil.water_clearance() > before and uniform_water(), "Repeated valid contact grows steadily at " + str(point))
	check(no_extraction() and not soil.advance_wash_cycle(), "Watering cannot extract fabric or skip a wash cycle")
	soil.prepare_water_stage()
	soil.apply_water_blob(local_point(0.0, 0.0), 0.19, 1.20393)
	var single_parcel: float = soil.water_clearance()
	soil.prepare_water_stage()
	for parcel in 8:
		soil.apply_water_blob(local_point(0.82, 1.25), 0.19, 1.20393 / 8.0)
	check(absf(soil.water_clearance() - single_parcel) < 0.000001,
		"Strong hose flow conserves water when pointer motion splits one parcel into eight contacts")
	soil.prepare_water_stage()
	soil.apply_water_blob(local_point(0.0, 0.0), 0.19, Soil.HOSE_PATCH_SATURATION)
	var prior_start: float = soil.water_clearance()
	soil.apply_water_blob(local_point(0.0, 0.0), 0.19, 0.05 * 2.6 * 7.7175)
	var prior_upgrade: float = soil.water_clearance() - prior_start
	soil.prepare_water_stage()
	soil.apply_water_blob(local_point(0.0, 0.0), 0.19, Soil.HOSE_PATCH_SATURATION)
	var final_start: float = soil.water_clearance()
	soil.apply_water_blob(local_point(0.0, 0.0), 0.19, 0.05 * 2.6 * 9.261)
	check(soil.water_clearance() - final_start > prior_upgrade * 1.19,
		"The final paid hose upgrade retains its real flow increase instead of flattening at the per-contact cap")
	soil.prepare_water_stage()
	rug.transform = Transform3D(Basis(Vector3.UP, 0.63), Vector3(2.0, 0.5, -3.0))
	check(soil.apply_water_blob(local_point(0.82, 1.25), 0.19, 0.4) and uniform_water(),
		"Global hose contact respects the rug's transformed footprint")
	rug.transform = Transform3D.IDENTITY
	soil.prepare_water_stage()

func validate_fresh_patch_rate() -> void:
	soil.prepare_water_stage()
	var supplied := 16.0 * 0.13
	for parcel in 16:
		soil.apply_water_blob(local_point(0.0, 0.0), 0.19, 0.13)
	var held: float = soil.water_clearance()
	check(held > supplied * Soil.GLOBAL_WATER_GAIN and held < supplied * 0.08,
		"Holding one spot remains productive and is slower than the previous watering rate")
	soil.prepare_water_stage()
	for row in 4:
		for column in 4:
			soil.apply_water_blob(local_point(-0.75 + column * 0.5, -1.1 + row * 0.7), 0.19, 0.13)
	var moved: float = soil.water_clearance()
	check(moved > held * 1.10 and moved <= supplied * Soil.GLOBAL_WATER_GAIN * (1.0 + Soil.FRESH_WATER_BONUS),
		"Equal flow across new patches earns a modest bounded movement bonus")
	check(moved < supplied * 0.08 and uniform_water(),
		"Even fresh-patch watering is slightly slower than before and wets every carpet pixel")
	soil.prepare_water_stage()
	soil.apply_water_blob(local_point(0.0, 0.0), 0.19, Soil.HOSE_PATCH_SATURATION)
	var saturated_patch: PackedFloat32Array = soil.hose_patch_water.duplicate()
	for parcel in 5:
		var before: float = soil.water_clearance()
		soil.apply_water_blob(local_point(0.0, 0.0), 0.19, 0.13)
		check(absf(soil.water_clearance() - before - 0.13 * Soil.GLOBAL_WATER_GAIN) < 0.000001,
			"An already sprayed patch settles to the same constant base increment")
		check(soil.hose_patch_water == saturated_patch, "Repeated watering cannot replenish a patch's freshness bonus")
	var before_new: float = soil.water_clearance()
	soil.apply_water_blob(local_point(-0.75, -1.1), 0.19, 0.13)
	check(soil.water_clearance() - before_new > 0.13 * Soil.GLOBAL_WATER_GAIN * 1.18,
		"Moving from a saturated spot to untouched fabric immediately restores the small bonus")

	soil.prepare_water_stage()
	soil.apply_water_blob(local_point(0.0, 0.0), 0.19, 0.31)
	var saved: Dictionary = soil.make_snapshot()
	var saved_patches: PackedFloat32Array = soil.hose_patch_water.duplicate()
	soil.apply_water_blob(local_point(0.0, 0.0), 0.19, 0.21)
	var uninterrupted: float = soil.water_clearance()
	check(soil.restore_snapshot(saved) and soil.hose_patch_water == saved_patches,
		"Save reload restores exact local hose exposure without refreshing a used patch")
	soil.apply_water_blob(local_point(0.0, 0.0), 0.19, 0.21)
	check(absf(soil.water_clearance() - uninterrupted) < 0.000001,
		"Watering after reload matches uninterrupted watering at the same location")

	var old_save := saved.duplicate(true)
	old_save.erase("hose_patch_water")
	check(soil.restore_snapshot(old_save), "Older whole-carpet saves remain compatible")
	var conservative := true
	for value in soil.hose_patch_water:
		conservative = conservative and is_equal_approx(value, soil.global_water_level)
	check(conservative, "Missing local history uses saved whole-carpet wetness without removing earned work")

	var invalid_values: Array = [null, [], 1.0, "", Marshalls.raw_to_base64(PackedByteArray([0, 1, 2]))]
	for bad in [NAN, INF, -0.01, 1.01]:
		var invalid_patches := saved_patches.duplicate()
		invalid_patches[0] = bad
		invalid_values.append(Marshalls.raw_to_base64(invalid_patches.to_byte_array()))
	for value in invalid_values:
		var invalid := saved.duplicate(true)
		invalid["hose_patch_water"] = value
		var before: Dictionary = soil.make_snapshot()
		check(not soil.restore_snapshot(invalid) and soil.make_snapshot() == before,
			"Invalid local hose history is rejected before mutating progress")

	soil.prepare_extraction_stage(0)
	extract_all()
	check(soil.advance_wash_cycle(), "Advance from the first wash for contact-history reset")
	var fresh_round := true
	for value in soil.hose_patch_water:
		fresh_round = fresh_round and value == 0.0
	check(fresh_round, "The next wash gives every patch a fresh bonus again")
	soil.prepare_extraction_stage(1)
	var soaked_round := true
	for value in soil.hose_patch_water:
		soaked_round = soaked_round and value == 1.0
	check(soaked_round, "Instant extraction practice marks the local patches as already watered")
	soil.prepare_water_stage()
func validate_cycles() -> Dictionary:
	var texture_id: int = soil.wet_texture.get_instance_id()
	var extraction_texture_id: int = soil.extraction_texture.get_instance_id()
	var last_progress := 0.0
	var final_snapshot := {}
	for cycle in Soil.WASH_CYCLES:
		check(soil.wash_cycle == cycle and soil.recommended_tool() == 2 and no_extraction(),
			"Cycle %d starts with an empty water/extraction stage" % (cycle + 1))
		var before_premature: Dictionary = soil.make_snapshot()
		soil.apply_squeegee_stroke(local_point(-0.5, 0.0), local_point(0.5, 0.0), 0.08)
		check(soil.make_snapshot() == before_premature, "Cycle %d cannot extract before watering" % (cycle + 1))
		saturate_corner()
		check(soil.water_stage_complete() and uniform_water() and soil.recommended_tool() == 1,
			"Holding the hose at one corner wets the entire cycle %d without hidden leftovers" % (cycle + 1))
		var fully_wet: Dictionary = soil.make_snapshot()
		check(not soil.apply_water_blob(local_point(-0.75, -1.2), 0.19, 1.0),
			"A completed water stage stops accepting extra contact")
		check(fully_wet.get("wash_cycle_count") == 3 and fully_wet.get("wash_cycle") == cycle,
			"Save metadata identifies the cycle and required wash count")
		check(soil.restore_snapshot(fully_wet) and soil.wash_cycle == cycle and soil.water_stage_complete(),
			"A fully wet cycle %d restores the correct squeegee stage" % (cycle + 1))
		soil.set_tool_strength(1.0)
		soil.apply_squeegee_stroke(local_point(-0.6, 0.0), local_point(0.6, 0.0), 0.08)
		check(soil.extraction_clearance() > 0.0 and soil.extraction_clearance() < 0.4,
			"The squeegee reveals a local strip rather than cleaning the whole carpet")
		var partial: Dictionary = soil.make_snapshot()
		var partial_fraction: float = soil.extraction_clearance()
		check(not soil.advance_wash_cycle(), "Partial extraction cannot advance cycle %d" % (cycle + 1))
		soil.reset()
		check(soil.restore_snapshot(partial) and soil.wash_cycle == cycle
			and absf(soil.extraction_clearance() - partial_fraction) < 0.002,
			"Partial extraction and wash identity survive reset/reload")
		extract_all()
		check(soil.extraction_stage_complete(), "Full passes complete extraction cycle %d" % (cycle + 1))
		var progress: float = soil.overall_clearance()
		check(progress > last_progress, "Completing each cycle advances the overall cleaning meter")
		last_progress = progress
		if cycle < Soil.WASH_CYCLES - 1:
			check(not soil.all_washes_complete() and progress < 0.75,
				"Cycle %d cannot complete or enter the finish range" % (cycle + 1))
			check(soil.advance_wash_cycle() and soil.wash_cycle == cycle + 1 and soil.water_clearance() == 0.0
				and no_extraction(), "A completed extraction advances to a fresh watering stage")
			check(soil.overall_clearance() + 0.004 >= progress,
				"Advancing the wash retains all previously earned overall progress")
		else:
			check(soil.all_washes_complete() and progress >= 0.99,
				"Only the third extraction completes the carpet")
			final_snapshot = soil.make_snapshot()
			check(not soil.advance_wash_cycle() and soil.wash_cycle == 2,
				"The third extraction cannot create a fourth wash")
	check(soil.wet_texture.get_instance_id() == texture_id
		and soil.extraction_texture.get_instance_id() == extraction_texture_id,
		"All cycles and reloads reuse the existing render textures")
	return final_snapshot

func validate_restore(final_snapshot: Dictionary) -> void:
	var legacy := final_snapshot.duplicate(true)
	legacy.erase("wash_cycle")
	legacy.erase("wash_cycle_count")
	soil.prepare_water_stage()
	check(soil.restore_snapshot(legacy) and soil.wash_cycle == 2 and soil.all_washes_complete(),
		"Legacy one-wash progress migrates to the final cycle without losing earned cleaning")
	for field in ["wash_cycle", "wash_cycle_count"]:
		var invalid_values: Array = [-1, 3, 1.5, true, "2", NAN, INF, null, [], {}] if field == "wash_cycle" else [0, 1, 2, 4, 3.5, true, "3", NAN, INF, null]
		for value in invalid_values:
			var invalid := final_snapshot.duplicate(true)
			invalid[field] = value
			var before: Dictionary = soil.make_snapshot()
			check(not soil.restore_snapshot(invalid) and soil.make_snapshot() == before,
				"Malformed " + field + " is rejected before mutating any rug progress: " + str(value))
	var wrong_extracted := final_snapshot.duplicate(true)
	var water := Marshalls.base64_to_raw(wrong_extracted.water)
	var extracted := Marshalls.base64_to_raw(wrong_extracted.extracted)
	for index in soil.surface_pixels.size():
		if soil.surface_pixels[index] == 1:
			water[index] = 0
			extracted[index] = 255
			break
	wrong_extracted.water = Marshalls.raw_to_base64(water)
	wrong_extracted.extracted = Marshalls.raw_to_base64(extracted)
	var before: Dictionary = soil.make_snapshot()
	check(not soil.restore_snapshot(wrong_extracted) and soil.make_snapshot() == before,
		"Impossible extraction greater than water remains an atomic restore failure")

func reward_snapshot(cycle: int, extraction: float, water: float = 1.0) -> Dictionary:
	return {"unique_clearance": 1.0, "surface_clearance": 1.0, "wet_recipe": true,
		"skip_dry_stage": true, "wash_cycle_count": 3, "wash_cycle": cycle,
		"water_clearance": water, "extraction_clearance": extraction, "overall_clearance": 1.0}

func validate_rewards() -> void:
	var state := State.new()
	save_path = "res://.godot/three_wash_cycles_%d.json" % OS.get_process_id()
	state._save_path = save_path
	state._test_ticks_msec = 0
	state._test_unix_time = 1800000000.0
	root.add_child(state)
	state.set_process(false)
	state.stores["2"] = Rules.new_branch(2)
	check(state.save_state() and state.select_store(2), "The isolated wet contract is ready")
	var job: String = state.start_job()
	for cycle in [0, 1]:
		var before: Dictionary = state._capture_state()
		check(state.reward_for_current_job(reward_snapshot(cycle, 1.0)) == 0
			and state.complete_and_start_next_job(job, reward_snapshot(cycle, 1.0)).is_empty()
			and state._capture_state() == before,
			"A forged overall meter cannot pay cycle %d or retire its reservation" % (cycle + 1))
	check(state.reward_for_current_job(reward_snapshot(2, 0.7499)) == 0,
		"The final extraction must reach its own finish threshold")
	check(state.reward_for_current_job(reward_snapshot(2, 0.75)) == 160,
		"Final extraction at 75 percent offers the normal early reward")
	check(state.reward_for_current_job(reward_snapshot(2, 1.0, 0.5)) == 0,
		"A final cycle cannot extract before its watering gate")
	check(state.reward_for_current_job(reward_snapshot(2, 1.0)) == 320,
		"The third fully clean extraction earns the full quoted payout")
	check(not state.complete_and_start_next_job(job, reward_snapshot(2, 1.0)).is_empty()
		and state.cash == 320, "Completing all three washes pays once and reserves the next carpet")
	check(state.complete_and_start_next_job(job, reward_snapshot(2, 1.0)).is_empty()
		and state.cash == 320, "A retired three-wash contract cannot pay twice")
	state.free()
	for suffix in ["", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))

func validate_completed_cycle_resume() -> void:
	# A release saves before its deferred stage advance. Recreate that exact
	# durable boundary and use the authored animated paid scene to resume it.
	var state: Node = root.get_node("ShopState")
	state.set_process(false)
	state._save_path = "res://.godot/three_wash_resume_%d.json" % OS.get_process_id()
	state._test_ticks_msec = 0
	state._test_unix_time = 1800000000.0
	check(state.reset_progress(), "The animated-resume ledger is isolated")
	state._sync_active_branch()
	state.stores["2"] = Rules.new_branch(2)
	state.active_store = 2
	state._load_active_branch()
	check(not state.start_job().is_empty(), "Reserve a real paid carpet for the resume check")
	var game := CLEANING.instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	await process_frame
	game.soil.prepare_extraction_stage(0)
	game.soil.set_tool_strength(9.261)
	for row in 36:
		var z := -1.75 + float(row) * 0.1
		game.soil.apply_squeegee_stroke(Vector3(-1.3, 0.067, z), Vector3(1.3, 0.067, z), 0.08)
	game.soil._process(0.0)
	check(game.soil.extraction_stage_complete() and game.soil.wash_cycle == 0
		and game.save_contract_progress(), "Save a completed first extraction before advancing its wash")
	var job: String = state.active_job_id
	var cash: int = state.cash
	game.free()
	game = CLEANING.instantiate()
	game.animate_rug_changes = true
	root.add_child(game)
	await create_timer(4.0).timeout
	check(game.rug_phase == game.RugPhase.CLEANING and game.soil.wash_cycle == 1
		and game.selected_tool == 2 and game.soil.water_clearance() == 0.0
		and game.soil.extraction_clearance() == 0.0,
		"Animated arrival automatically resumes the next hose round after a fully extracted nonfinal save")
	check(state.active_job_id == job and state.cash == cash,
		"Resuming a completed intermediate cycle preserves its reservation and awards no premature payout")
	game.free()
	for suffix in ["", ".tmp"]:
		if FileAccess.file_exists(state._save_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path + suffix))

func run() -> void:
	new_soil()
	validate_global_water()
	validate_fresh_patch_rate()
	var final_snapshot := validate_cycles()
	validate_restore(final_snapshot)
	validate_rewards()
	await validate_completed_cycle_resume()
	soil.free()
	rug.free()
	print("THREE_WASH_CYCLE_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
