extends SceneTree
## Real renderer + isolated Store 2 and Gym. Run through the pinned wrapper:
## --path CarpetToy --script ../tools/validate_wet_freshness.gd -- --shop-test
const Progression := preload("res://scripts/progression.gd")
const Catalog := preload("res://scripts/rug_catalog.gd")
const Routes := preload("res://scripts/scene_routes.gd")
const DESIGNS := ["ramen_neko", "stillwater_pond"]
const CENTER := Rect2(-0.22, -0.85, 0.44, 1.70)
const UNTOUCHED := Rect2(0.55, -0.85, 0.18, 1.70)
var checks := 0
var failures := 0
var state: Node
var game: Node
var captures: Array[Dictionary] = []

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Wet freshness validation requires a renderer and -- --shop-test")
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("WET FRESHNESS: " + message)

func frames(count: int = 2) -> void:
	for _tick in count:
		await process_frame
		if is_instance_valid(game) and is_instance_valid(game.snapshot_timer):
			game.snapshot_timer.stop()
		await RenderingServer.frame_post_draw

func pile_material() -> ShaderMaterial:
	for index in game.soil.surface_names.size():
		if str(game.soil.surface_names[index]).to_lower().contains("pile"):
			return game.soil.surface_materials[index]
	check(false, "The existing pile mesh has its material")
	return game.soil.surface_materials[0]

func capture(id: String, stage: String) -> Image:
	await frames()
	var image := root.get_texture().get_image()
	var path := "res://../art/renders/wet_freshness_%s_%s.png" % [id, stage]
	check(image.save_png(path) == OK, "Capture " + id + " " + stage)
	captures.append({"rug_id": id, "stage": stage, "path": path,
		"width": image.get_width(), "height": image.get_height(),
		"surface_clearance": game.soil.surface_clearance(),
		"water_clearance": game.soil.water_clearance(),
		"extraction_clearance": game.soil.extraction_clearance()})
	return image

func sample_position(x: int, z: int, region: Rect2, image_size: Vector2) -> Vector2i:
	var local := Vector3(region.position.x + region.size.x * float(x) / 8.0,
		0.067, region.position.y + region.size.y * float(z) / 12.0)
	var screen: Vector2 = game.camera.unproject_position(game.soil.rug_node.to_global(local))
	# Canvas stretch exposes logical camera coordinates; viewport screenshots
	# contain the physical 390 x 844 render pixels.
	screen *= image_size / root.get_visible_rect().size
	return Vector2i(screen.round())

func mean_luminance(image: Image, region: Rect2 = CENTER) -> float:
	var total := 0.0
	var count := 0
	for z in 13:
		for x in 9:
			var p := sample_position(x, z, region, Vector2(image.get_size()))
			if p.x < 0 or p.y < 0 or p.x >= image.get_width() or p.y >= image.get_height():
				continue
			var color := image.get_pixelv(p)
			total += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			count += 1
	return total / float(maxi(count, 1))

func relative_grime_variation(dirty: Image, clean_reference: Image) -> Dictionary:
	# Compare dirt attenuation among points with similar clean brightness. Raw
	# variance would confuse the artwork's contrast with a mottled soil layer.
	var totals := PackedFloat32Array()
	var counts := PackedInt32Array()
	totals.resize(20)
	counts.resize(20)
	var samples: Array[Vector2] = []
	for z in 13:
		for x in 9:
			var p := sample_position(x, z, CENTER, Vector2(dirty.get_size()))
			if p.x < 0 or p.y < 0 or p.x >= dirty.get_width() or p.y >= dirty.get_height():
				continue
			var clean_color := clean_reference.get_pixelv(p)
			var clean_luminance := clean_color.r * 0.2126 + clean_color.g * 0.7152 + clean_color.b * 0.0722
			# Very dark artwork cannot provide a stable denominator for shading.
			if clean_luminance < 0.12:
				continue
			var dirty_color := dirty.get_pixelv(p)
			var dirty_luminance := dirty_color.r * 0.2126 + dirty_color.g * 0.7152 + dirty_color.b * 0.0722
			var bucket := mini(int(clean_luminance / 0.05), 19)
			var ratio := dirty_luminance / clean_luminance
			totals[bucket] += ratio
			counts[bucket] += 1
			samples.append(Vector2(float(bucket), ratio))
	var variance := 0.0
	var comparable_samples := 0
	for sample in samples:
		var bucket := int(sample.x)
		if counts[bucket] < 3:
			continue
		var residual := sample.y - totals[bucket] / float(counts[bucket])
		variance += residual * residual
		comparable_samples += 1
	return {"samples": comparable_samples,
		"spread": sqrt(variance / float(maxi(comparable_samples, 1)))}

func image_difference(a: Image, b: Image, region: Rect2 = CENTER) -> float:
	var total := 0.0
	var count := 0
	for z in 13:
		for x in 9:
			var p := sample_position(x, z, region, Vector2(a.get_size()))
			if p.x < 0 or p.y < 0 or p.x >= a.get_width() or p.y >= a.get_height():
				continue
			var ac := a.get_pixelv(p)
			var bc := b.get_pixelv(p)
			total += (absf(ac.r - bc.r) + absf(ac.g - bc.g) + absf(ac.b - bc.b)) / 3.0
			count += 1
	return total / float(maxi(count, 1))

func mask_index(local: Vector2) -> int:
	var soil: Node = game.soil
	var pixel := Vector2i(((local + soil.RUG_HALF) / (soil.RUG_HALF * 2.0) * Vector2(soil.MASK_SIZE)).floor())
	pixel = pixel.clamp(Vector2i.ZERO, soil.MASK_SIZE - Vector2i.ONE)
	return pixel.y * soil.MASK_SIZE.x + pixel.x

func maximum_byte_difference(a: PackedByteArray, b: PackedByteArray) -> int:
	if a.size() != b.size(): return 256
	var difference := 0
	for index in a.size():
		difference = maxi(difference, absi(int(a[index]) - int(b[index])))
	return difference

func all_zero(bytes: PackedByteArray) -> bool:
	for value in bytes:
		if value != 0: return false
	return true

func enter_paid(id: String) -> void:
	state._sync_active_branch()
	var branch: Dictionary = Progression.new_branch(2)
	branch.manual_jobs = Catalog.IDS.find(id)
	state.stores["2"] = branch
	state.active_store = 2
	state._load_active_branch()
	check(not state.start_job().is_empty(), "Reserve isolated Store 2 job for " + id)
	game = load(Routes.CLEANING).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frames()
	game.auto_finish_queued = true
	check(game.paid_contract and game.wet_recipe and game.water_only_recipe,
		id + " uses the real paid water-only scene")
	check(game.soil.rug_definition.rug_id == id and state.active_rug_id == id,
		"The paid reservation selects " + id)
	check(game.selected_tool == 2 and game.soil.surface_clearance() == 1.0,
		"Store 2 starts on the hose without dry-stage progress")
	# Measure the actual pile shader without transient spray/ridge pixels.
	# The production stroke still feeds those systems and they remain allocated.
	game.water.hide()
	game.squeegee_water.hide()

func leave_game() -> void:
	if is_instance_valid(game): game.free()
	game = null
	current_scene = null

func check_design(id: String) -> void:
	await enter_paid(id)
	var soil: Node = game.soil
	var extraction_texture_id: int = soil.extraction_texture.get_instance_id()
	var wet_texture_id: int = soil.wet_texture.get_instance_id()
	check(soil.wash_cycle == 0 and soil.WASH_CYCLES == 3, "New paid rugs require three full wash rounds")
	var dirty := await capture(id, "dirty_dry")
	var pile := pile_material()
	var authored_map: Texture2D = pile.get_shader_parameter("clean_map")
	var alternate := Image.create(2, 2, false, Image.FORMAT_RGB8)
	alternate.fill(Color.MAGENTA)
	pile.set_shader_parameter("clean_map", ImageTexture.create_from_image(alternate))
	await frames()
	check(image_difference(root.get_texture().get_image(), dirty) < 0.004,
		id + " uniform opaque grime fully hides the artwork")
	pile.set_shader_parameter("clean_map", authored_map)
	for material: ShaderMaterial in soil.surface_materials:
		material.set_shader_parameter("wet_recipe", false)
	await frames()
	var clean_reference := root.get_texture().get_image()
	for material: ShaderMaterial in soil.surface_materials:
		material.set_shader_parameter("wet_recipe", true)
	check(mean_luminance(dirty) < mean_luminance(clean_reference) * 0.50,
		id + " starts as an unmistakably dark dirty carpet")
	var previous_extracted := dirty
	for cycle in 3:
		check(soil.wash_cycle == cycle and game.selected_tool == 2, "Each wash starts with the hose")
		check(game.hud.control("ProgressStage").text.contains("%d/3" % (cycle + 1)),
			"Paid HUD identifies the current wash round")
		# Hold the hose over just one corner: all pixels gain the same wetness.
		for _contact in 40:
			game._on_water_contact(soil.rug_node.to_global(Vector3(0.72, 0.067, 1.20)), 0.19, 0.5)
			if _contact == 5:
				game.update_contract_status()
				check(absf(game.progress_bar.value - soil.water_stage_progress() * 100.0) < 0.00001,
					"The visible watering meter measures this action from zero to 100 percent")
				await capture(id, "wash_%d_watering" % (cycle + 1))
		soil._process(0.0)
		check(soil.water_stage_complete() and soil.water_clearance() == 1.0,
			"A stationary corner contact wets the whole carpet with no missing speck")
		check(absf(soil.water_values[mask_index(Vector2.ZERO)] - soil.water_values[mask_index(Vector2(-0.7, -1.2))]) < 0.00001,
			"Remote pixels receive exactly the same soak")
		await frames()
		game.select_tool(1)
		var soaked := await capture(id, "wash_%d_soaked" % (cycle + 1))
		check(mean_luminance(soaked) < mean_luminance(previous_extracted) * 0.95,
			"Water deepens the whole carpet on wash %d" % (cycle + 1))
		var fully_soaked: Dictionary = soil.make_snapshot()
		game.apply_selected_tool_stroke(soil.rug_node.to_global(Vector3(0, 0.067, -1.30)),
			soil.rug_node.to_global(Vector3(0, 0.067, 1.30)), 1.0 / 60.0)
		soil._process(0.0)
		await frames()
		check(mean_luminance(root.get_texture().get_image()) > mean_luminance(soaked) + 0.006,
			"Even the first 60-Hz blade contact lifts grime")
		check(soil.restore_snapshot(fully_soaked), "Restore the soak before a complete blade pass")
		soil._process(0.0)
		game.squeegee_motion.reset()
		game.apply_selected_tool_stroke(soil.rug_node.to_global(Vector3(0, 0.067, -1.30)),
			soil.rug_node.to_global(Vector3(0, 0.067, 1.30)), 0.08)
		soil._process(0.0)
		var first_pass := await capture(id, "wash_%d_first_pass" % (cycle + 1))
		check(mean_luminance(first_pass) > mean_luminance(soaked) + 0.025,
			"Each blade pass reveals a clearer band of art immediately")
		check(image_difference(first_pass, soaked, UNTOUCHED) < 0.008,
			"Untouched fabric keeps the current round's wet grime")
		if cycle < 2:
			check(image_difference(first_pass, clean_reference) > 0.03,
				"Early wash rounds leave further dirt to remove")
		else:
			check(image_difference(first_pass, clean_reference) < image_difference(soaked, clean_reference) * 0.55,
				"The final blade pass brings back the authored clean palette")
		var saved: Dictionary = soil.make_snapshot()
		var ledger_before: Dictionary = state._capture_state().duplicate(true)
		var disk_before := FileAccess.get_file_as_bytes(state._save_path)
		soil.reset()
		check(soil.restore_snapshot(saved) and soil.wash_cycle == cycle, "Save reload resumes the same wash round")
		soil._process(0.0)
		await frames()
		check(image_difference(root.get_texture().get_image(), first_pass) < 0.008,
			"Reload preserves the visible fresh lanes")
		check(soil.extraction_texture.get_instance_id() == extraction_texture_id
			and soil.wet_texture.get_instance_id() == wet_texture_id, "All rounds reuse the existing GPU masks")
		game.rug_comparison.set_before(soil, true)
		await frames()
		check(image_difference(root.get_texture().get_image(), dirty) < 0.008,
			"Before returns to the original opaque dirty arrival even in a later round")
		game.rug_comparison.set_before(soil, false)
		check(soil.make_snapshot().extracted == saved.extracted
			and state._capture_state() == ledger_before
			and FileAccess.get_file_as_bytes(state._save_path) == disk_before, "Comparison leaves earned progress and ledger intact")
		for lane in [-0.85, -0.43, 0.0, 0.43, 0.85]:
			for _pass in 2:
				game.squeegee_motion.reset()
				game.apply_selected_tool_stroke(soil.rug_node.to_global(Vector3(lane, 0.067, -1.85)),
					soil.rug_node.to_global(Vector3(lane, 0.067, 1.85)), 0.08)
		soil._process(0.0)
		check(soil.extraction_stage_complete(), "A full blade sweep completes the current extraction")
		previous_extracted = await capture(id, "wash_%d_extracted" % (cycle + 1))
		game.squeegee_water.show()
		await capture(id, "wash_%d_runoff" % (cycle + 1))
		game.squeegee_water.hide()
		if cycle == 2:
			check(soil.all_washes_complete() and soil.overall_clearance() >= 0.99, "Only the third complete extraction restores the rug")
			check(image_difference(previous_extracted, clean_reference) < 0.012, "Final restoration returns authored clean colors")
		else:
			check(not soil.all_washes_complete() and state.reward_for_current_job(soil.make_progress_snapshot()) == 0,
				"Earlier rounds cannot finish or pay out")
			game._advance_wet_tool()
			check(soil.wash_cycle == cycle + 1 and game.selected_tool == 2
				and soil.water_clearance() == 0.0, "Completed extraction automatically returns to the next hose round")
		print("THREE_WASH_RENDER rug=%s round=%d soaked=%.4f first=%.4f extracted=%.4f" %
			[id, cycle + 1, mean_luminance(soaked), mean_luminance(first_pass), mean_luminance(previous_extracted)])
	soil.prepare_extraction_stage(2)
	soil._process(0.0)
	soil.start_vacuum(true, true)
	soil.animate_vacuum(soil.VACUUM_SECONDS)
	await frames()
	check(image_difference(root.get_texture().get_image(), clean_reference) < 0.018,
		"Completion polish leaves a fully clean carpet")
	leave_game()
func check_gym() -> void:
	var ledger_before: Dictionary = state._capture_state().duplicate(true)
	var disk_before := FileAccess.get_file_as_bytes(state._save_path)
	game = load(Routes.GYM).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frames()
	game.select_rug(1)
	game.soil.prepare_extraction_stage()
	game.select_tool(1)
	game.apply_selected_tool_stroke(Vector3(0, 0.067, -0.8), Vector3(0, 0.067, 0.8), 0.08)
	game.soil._process(0.0)
	check(not all_zero(game.soil.extraction_mask.get_data()), "Gym uses the same local fresh-color extraction")
	game.reset_rug()
	game.soil._process(0.0)
	check(all_zero(game.soil.extraction_mask.get_data()) and game.soil.extraction_clearance() == 0.0,
		"Gym reset restores the dirty water exercise without old clean lanes")
	check(state._capture_state() == ledger_before and FileAccess.get_file_as_bytes(state._save_path) == disk_before,
		"Free freshness practice preserves the paid ledger")
	leave_game()

func run() -> void:
	state = root.get_node("ShopState")
	state.set_process(false)
	state._test_ticks_msec = 0
	state._test_unix_time = 2000000.0
	state._save_path = "res://.godot/wet_freshness_%d.json" % OS.get_process_id()
	check(state.reset_progress(), "Create an isolated freshness ledger")
	root.size = Vector2i(390, 844)
	for id: String in DESIGNS:
		await check_design(id)
	await check_gym()
	var manifest := FileAccess.open("res://../art/renders/wet_freshness_manifest.json", FileAccess.WRITE)
	if manifest != null:
		manifest.store_string(JSON.stringify({"checks": checks, "failures": failures, "captures": captures}, "\t"))
		manifest.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("WET_FRESHNESS_VALIDATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
