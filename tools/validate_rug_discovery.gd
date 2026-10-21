extends SceneTree
## Renderer-backed paid-rug discovery and continuity checks.
## Run through the pinned wrapper with -- --shop-test. Never uses player progress.
const Routes := preload("res://scripts/scene_routes.gd")
const Catalog := preload("res://scripts/rug_catalog.gd")
const EXPECTED_IDS := Catalog.IDS
var checks := 0
var failures := 0
var state: Node
var game: Node
var captures: Array[Dictionary] = []
var clean_images: Array[Image] = []
var texture_hashes: Array[String] = []
var camera_reference := Transform3D.IDENTITY
var camera_size := 0.0

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Rug discovery validation requires a renderer and -- --shop-test")
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 2) -> void:
	for _tick in count:
		await process_frame
		await RenderingServer.frame_post_draw

func wait_cleaning() -> void:
	for _tick in 350:
		if game.rug_phase == game.RugPhase.CLEANING: return
		await create_timer(0.02).timeout
	check(false, "The reserved rug becomes playable within seven seconds")

func enter_rug() -> void:
	game = load(Routes.CLEANING).instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	await wait_cleaning()

func pile_material() -> ShaderMaterial:
	for index in game.soil.surface_names.size():
		if str(game.soil.surface_names[index]).to_lower().contains("pile"):
			return game.soil.surface_materials[index]
	check(false, "The existing pile mesh has its own material")
	return game.soil.surface_materials[0]

func pixel_hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func mesh_ids() -> Array[int]:
	var result: Array[int] = []
	for child: Node in game.get_node("RugDisplay/Dirty/CarpetMesh").get_children():
		if child is MeshInstance3D: result.append(child.mesh.get_instance_id())
	return result

func capture(rug_id: String, stage: String) -> Image:
	await frames()
	var image := root.get_texture().get_image()
	var file := "res://../art/renders/discovery_%s_%s.png" % [rug_id, stage]
	check(image.save_png(file) == OK, "Save actual game view " + rug_id + " " + stage)
	var clean_map: Texture2D = pile_material().get_shader_parameter("clean_map")
	captures.append({
		"rug_id": rug_id, "stage": stage, "file": file,
		"width": image.get_width(), "height": image.get_height(),
		"render_pixel_sha256": pixel_hash(image.get_data()),
		"texture_path": clean_map.resource_path,
		"texture_pixel_sha256": pixel_hash(clean_map.get_image().get_data()),
		"surface_clearance": game.soil.surface_clearance(),
		"camera_transform": str(game.camera.transform), "camera_size": game.camera.size,
	})
	return image

func settle_dirt() -> void:
	for _tick in 300:
		if not game.soil.is_physics_processing(): break
		game.soil._physics_process(1.0 / 60.0)
	game.soil._process(0.0)

func stroke(lane: float) -> void:
	game.begin_stroke(game.camera.unproject_position(Vector3(lane, 0.067, -1.85)), false)
	game.move_brush_to_screen(game.camera.unproject_position(Vector3(lane, 0.067, 1.85)), false)
	game.end_stroke()
	settle_dirt()

func set_result_coverage(amount: float) -> void:
	# Rendering/completion fixture: change both the real mask and bookkeeping.
	# Preserve the requested residual mask for accurate progress/payout data;
	# accepted full restoration separately polishes its visible soil away.
	# Install the guard before _process emits surface_changed; a deferred finish
	# already queued by that signal cannot be canceled by setting this afterward.
	game.auto_finish_queued = true
	game.snapshot_timer.stop()
	var soil: Node = game.soil
	soil.active.clear()
	soil.timed_debris.clear()
	soil.floor_debris.clear()
	soil.moving.fill(false)
	soil.credited.fill(true)
	soil.growth.fill(0.0)
	soil.remaining = 0
	soil.surface_coverage_total = 0.0
	var dirt: float = float(soil.surface_pixel_count) * (1.0 - amount)
	for y in soil.MASK_SIZE.y:
		for x in soil.MASK_SIZE.x:
			var index: int = y * soil.MASK_SIZE.x + x
			var value := 0.0
			if soil.surface_pixels[index] == 1 and dirt > 0.0:
				value = minf(1.0, dirt)
				dirt -= value
				soil.surface_coverage_total += value
			soil.coverage_values[index] = value
			soil.mask.set_pixel(x, y, Color(value, value, value))
	soil.mask_changed = true
	soil.request_render()
	soil._process(0.0)
	# Hold the fixture for a capture without triggering the completion callback.
	game.update_contract_status()

func finish_vacuum() -> void:
	for _tick in 140:
		if game.soil.vacuum_complete: break
		game.soil._physics_process(1.0 / 60.0)
	await frames()

func image_difference(a: Image, b: Image) -> float:
	var difference := 0.0
	var count := 0
	# Sample only the central carpet; HUD/brush changes cannot pass this check.
	for y in range(240, 570, 3):
		for x in range(110, 280, 3):
			var ac := a.get_pixel(x, y)
			var bc := b.get_pixel(x, y)
			difference += (absf(ac.r - bc.r) + absf(ac.g - bc.g) + absf(ac.b - bc.b)) / 3.0
			count += 1
	return difference / float(count)

func pattern_correlation(a: Image, b: Image) -> float:
	# A brightness/tint swap keeps the spatial luminance structure correlated.
	# Sampling only the pile verifies a different visible motif as well as color.
	var values_a := PackedFloat32Array()
	var values_b := PackedFloat32Array()
	var mean_a := 0.0
	var mean_b := 0.0
	for y in range(260, 550, 3):
		for x in range(130, 260, 3):
			var ac := a.get_pixel(x, y)
			var bc := b.get_pixel(x, y)
			var al := ac.r * 0.2126 + ac.g * 0.7152 + ac.b * 0.0722
			var bl := bc.r * 0.2126 + bc.g * 0.7152 + bc.b * 0.0722
			values_a.append(al)
			values_b.append(bl)
			mean_a += al
			mean_b += bl
	mean_a /= float(values_a.size())
	mean_b /= float(values_b.size())
	var covariance := 0.0
	var variance_a := 0.0
	var variance_b := 0.0
	for index in values_a.size():
		var da := values_a[index] - mean_a
		var db := values_b[index] - mean_b
		covariance += da * db
		variance_a += da * da
		variance_b += db * db
	return covariance / sqrt(maxf(variance_a * variance_b, 0.000000001))

func reload_partial_rug(expected: String) -> void:
	var job: String = game.contract_job_id
	var mask: PackedByteArray = game.soil.mask.get_data().duplicate()
	var positions: Array = game.soil.positions.duplicate()
	var texture: String = pile_material().get_shader_parameter("clean_map").resource_path
	check(game.save_contract_progress(), "Partly brushed " + expected + " saves")
	check(state.job_snapshot.get("rug_id") == expected, "The durable dirt snapshot carries the actual rug identity")
	var saved_coverage: String = state.job_snapshot.coverage
	game.return_to_shop()
	await frames()
	check(current_scene.scene_file_path == Routes.MAIN_MENU and state.active_rug_id == expected, "Back leaves the same paid rug reserved")
	state._load_state()
	check(state.active_job_id == job and state.active_rug_id == expected and state._save_enabled, "Reloading the saved ledger retains this rug and job")
	change_scene_to_file(Routes.CLEANING)
	await frames()
	game = current_scene
	await wait_cleaning()
	check(game.soil.rug_definition.rug_id == expected and pile_material().get_shader_parameter("clean_map").resource_path == texture, "Re-entry restores the same pattern")
	check(game.soil.make_snapshot().coverage == saved_coverage, "Re-entry restores the exact serialized partial coverage")
	check(game.soil.positions == positions, "Re-entry restores the exact dirt positions")
	var resumed_mask: PackedByteArray = game.soil.mask.get_data()
	var maximum_mask_delta := 0
	for index in mask.size():
		maximum_mask_delta = maxi(maximum_mask_delta, absi(int(mask[index]) - int(resumed_mask[index])))
	# Save coverage already uses nearest 8-bit quantization; the live L8 image's
	# float conversion can differ by one unit. Identity must not reset the mask.
	check(maximum_mask_delta <= 1, "Reloaded appearance stays within existing one-byte save quantization")
	check(game.rug_comparison.label == "Before this session" and game.rug_comparison.coverage.get_image().get_data() == resumed_mask, "A resumed rug compares against its real resumed appearance")
	await capture(expected, "resumed")

func run() -> void:
	state = root.get_node("ShopState")
	state.set_process(false)


	state._save_path = "res://../art/rug_discovery_test_%d.json" % OS.get_process_id()
	check(state.reset_progress(), "Isolated discovery ledger resets")
	root.size = Vector2i(390, 844)
	await enter_rug()
	camera_reference = game.camera.transform
	camera_size = game.camera.size
	for index in EXPECTED_IDS.size():
		var expected: String = EXPECTED_IDS[index]
		check(state.active_rug_id == expected and game.soil.rug_definition.rug_id == expected, "Paid job selects " + expected)
		check(not game.practice_only and game.paid_contract and game.RugCatalog.IDS.size() == EXPECTED_IDS.size(), "Paid jobs draw from the complete shared collection")
		check(game.camera.transform.is_equal_approx(camera_reference) and is_equal_approx(game.camera.size, camera_size), "Every pattern uses the same gameplay camera")
		check(game.soil.initial.size() == 560 and game.soil.batch.instance_count == 560, "Each pattern reuses the 560-clump recipe")
		check(is_equal_approx(game.soil.rug_definition.removal_per_pass, 0.1) and is_equal_approx(game.soil.rug_definition.dust_strength, 0.94) and game.soil.rug_definition.grain_axis.is_zero_approx(), "Pattern variety leaves the starter ten-pass cleaning recipe unchanged")
		var material := pile_material()
		var texture: Texture2D = material.get_shader_parameter("clean_map")
		check(texture != null, "A real pattern texture is bound for " + expected)
		texture_hashes.append(pixel_hash(texture.get_image().get_data()))
		await capture(expected, "dirty")
		stroke(0.0)
		check(absf(game.soil.mask.get_pixel(128, 208).r - 0.9) < 0.01, "One real brush pass removes ten percent on " + expected)
		for _pass in 10:
			stroke(-0.68)
			stroke(-0.32)
		check(game.soil.surface_clearance() > 0.15 and game.soil.surface_clearance() < 0.9, "Real strokes reveal part of the design while retaining dirt")
		await capture(expected, "partly_dirty")
		if index == 1 or index == EXPECTED_IDS.size() - 1:
			await reload_partial_rug(expected)
			material = pile_material()
			texture = material.get_shader_parameter("clean_map")
		var before: PackedByteArray = game.rug_comparison.coverage.get_image().get_data().duplicate()
		var scene_id: int = game.get_instance_id()
		var pool_id: int = game.soil.batch.get_instance_id()
		var mask_id: int = game.soil.mask_texture.get_instance_id()
		var material_id: int = material.get_instance_id()
		var geometry := mesh_ids()
		set_result_coverage(1.0)
		clean_images.append(await capture(expected, "clean"))
		var result := 0.75 if index == 1 else 1.0
		set_result_coverage(result)
		game.auto_finish_queued = false
		if index == 1:
			state._save_enabled = false
			game.finish_rug()
			check(state.active_rug_id == expected and game.soil.rug_definition.rug_id == expected and game.rug_phase == game.RugPhase.CLEANING, "A failed completion keeps the same visible rug playable")
			check(pile_material().get_shader_parameter("clean_map") == texture and state.manual_jobs == 1, "Failure neither swaps the pattern nor counts the job")
			state._save_enabled = true
		game.finish_rug()
		var next_id: String = EXPECTED_IDS[(index + 1) % EXPECTED_IDS.size()]
		check(state.active_rug_id == next_id and state.manual_jobs == index + 1, "Full and early finishes both reserve the next discovery exactly once")
		await finish_vacuum()
		check(game.rug_phase == game.RugPhase.REVEAL and game.completion_reveal.active, "The completed pattern receives the existing clean reveal")
		game.completion_reveal.remaining = 30.0
		check(game.soil.rug_definition.rug_id == expected and pile_material().get_shader_parameter("clean_map") == texture, "The reveal keeps the completed pattern while the ledger reserves the next one")
		check(game.completed_full_restore == (index != 1) and is_equal_approx(game.completed_fraction, result), "The reveal accurately distinguishes full and early results")
		var after: PackedByteArray = game.soil.mask.get_data().duplicate()
		await capture(expected, "reveal_after")
		game.completion_reveal.set_comparing(true)
		await frames()
		var displayed: Texture2D = pile_material().get_shader_parameter("coverage")
		check(displayed.get_image().get_data() == before and displayed.get_image().get_data() != after, "Before comparison shows the actual captured surface of " + expected)
		check(pile_material().get_shader_parameter("clean_map") == texture, "Before comparison cannot swap in another pattern")
		await capture(expected, "reveal_before")
		game.completion_reveal.set_comparing(false)
		check(pile_material().get_shader_parameter("coverage") == game.soil.mask_texture and game.soil.mask.get_data() == after, "Releasing comparison restores the exact earned surface")
		game.skip_completion_reveal()
		await wait_cleaning()
		check(game.get_instance_id() == scene_id and game.soil.batch.get_instance_id() == pool_id and mesh_ids() == geometry and game.soil.mask_texture.get_instance_id() == mask_id and pile_material().get_instance_id() == material_id, "Pattern changes reuse the existing scene, carpet meshes, GPU dirt pool, mask and material")
		check(game.soil.rug_definition.rug_id == next_id and state.active_rug_id == next_id, "Arrival applies the reserved next pattern")
	check(pixel_hash(pile_material().get_shader_parameter("clean_map").get_image().get_data()) == texture_hashes[0], "Cycling through the full collection back to Mint restores the original authored pattern")
	for child: Node in game.get_node("RugDisplay/Dirty/CarpetMesh").get_children():
		if child is MeshInstance3D:
			var authored: StandardMaterial3D = child.mesh.surface_get_material(0)
			check(child.material_override.get_shader_parameter("clean_color") == authored.albedo_color, "Returning to Mint restores the authored color of " + str(child.name))
	var differences: Array[Dictionary] = []
	for a in EXPECTED_IDS.size():
		for b in range(a + 1, EXPECTED_IDS.size()):
			var difference := image_difference(clean_images[a], clean_images[b])
			var correlation := pattern_correlation(clean_images[a], clean_images[b])
			check(texture_hashes[a] != texture_hashes[b], "Each design binds distinct texture pixels")
			check(difference > 0.025, "Distinct pattern pixels visibly change the rendered carpet")
			check(absf(correlation) < 0.97, "Rendered patterns have distinct spatial structure beyond a color tint")
			differences.append({"a": EXPECTED_IDS[a], "b": EXPECTED_IDS[b], "mean_rgb_absolute_difference": difference, "luminance_pattern_correlation": correlation})
	check(state.manual_jobs == EXPECTED_IDS.size() and state.cash == 40 * EXPECTED_IDS.size() - 20, "The full collection preserves existing full and early payouts")
	var ledger: Dictionary = state._capture_state().duplicate(true)
	game.free()
	current_scene = null
	game = load(Routes.GYM).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frames()
	check(game.practice_only and not game.paid_contract and game.rugs.size() == 2 and Catalog.is_known(game.practice_design_id), "Gym retains two exercises over the same shared design collection")
	check(not game.wet_recipe and game.soil.remaining == 560, "Gym brush exercise keeps its dry recipe")
	game.select_rug(1)
	check(game.wet_recipe and game.selected_tool == 2 and not game.soil.batch_node.visible, "Gym water exercise keeps its hose recipe")
	game.select_rug(0)
	check(not game.wet_recipe and game.selected_tool == 0 and game.soil.batch_node.visible, "Returning to the brush exercise restores its authored appearance and recipe")
	check(state._capture_state() == ledger, "Gym exercise changes preserve the paid discovery ledger")
	game.free()
	current_scene = null
	var report := FileAccess.open("res://../art/rug_discovery_validation.json", FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"checks": checks, "failures": failures, "captures": captures, "rendered_pair_differences": differences}, "\t"))
		report.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("RUG_DISCOVERY_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
