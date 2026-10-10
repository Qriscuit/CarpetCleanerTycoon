extends SceneTree
## Integrated camera, aperture and foliage checks using an isolated reward ledger.
## Use tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_completion_choreography.gd -- --shop-test
## Add --choreography-render with the graphical renderer to save milestone images.

var game: Node
var state: Node
var checks := 0
var failures := 0
var render_previews := false
var captured: Dictionary = {}
var _roll_samples: Array[Dictionary] = []
const RoomRules := preload("res://scripts/room_upgrades.gd")
const CameraFit := preload("res://scripts/gym_camera.gd")


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Completion choreography validation requires -- --shop-test")
		quit(2)
		return
	render_previews = "--choreography-render" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func frames(count: int = 2) -> void:
	for _tick: int in count:
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw


func capture_once(label: String) -> void:
	if not render_previews or captured.has(label):
		return
	captured[label] = true
	await RenderingServer.frame_post_draw
	var path := "res://../art/renders/choreography_%s.png" % label
	check(root.get_texture().get_image().save_png(path) == OK, "Rendered milestone saved: " + label)


func wait_cleaning() -> void:
	for _tick: int in 450:
		if game.rug_phase == game.RugPhase.CLEANING:
			return
		await create_timer(0.02).timeout
	check(false, "The replacement carpet becomes ready within nine seconds")


func finish_full_restoration() -> void:
	# The ledger and completion path remain real; only the labor is skipped.
	game.soil.remaining = 0
	game.soil.surface_coverage_total = 0.0
	game.update_contract_status()
	await frames()
	check(game.rug_phase == game.RugPhase.VACUUMING, "A completed rug enters suction before its reveal")
	for _tick: int in 150:
		if game.soil.vacuum_complete:
			break
		game.soil._physics_process(1.0 / 60.0)
	await frames()
	check(game.rug_phase == game.RugPhase.REVEAL, "Suction reaches the clean design reveal")
	game.completion_reveal.remaining = 30.0


func prepare_roll_samples() -> void:
	# Sample the actual rug mesh bounds at close longitudinal intervals. The
	# generous box samples also cover fringe vertices between the mesh strips.
	for model: MeshInstance3D in game.get_node("RugDisplay/Dirty/CarpetMesh").get_children():
		var bounds: AABB = model.mesh.get_aabb()
		var material := model.material_override as ShaderMaterial
		var offset: Vector3 = material.get_shader_parameter("roll_mesh_offset")
		for x: float in [bounds.position.x, bounds.end.x]:
			for y: float in [bounds.position.y, bounds.end.y]:
				for step: int in 73:
					var point := Vector3(x, y, lerpf(bounds.position.z, bounds.end.z, float(step) / 72.0))
					_roll_samples.append({"model": model, "point": point + offset, "offset": offset})


func deformed_bounds() -> AABB:
	var material: ShaderMaterial = game.soil.surface_materials[0]
	var amount: float = material.get_shader_parameter("roll_amount")
	var direction: float = material.get_shader_parameter("roll_direction")
	var front := lerpf(1.72, -1.72, amount)
	var radius := 0.17 + 0.22 * sqrt(amount)
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for sample: Dictionary in _roll_samples:
		var point: Vector3 = sample.point
		var distance := maxf(point.z * direction - front, 0.0)
		if distance > 0.0 and amount > 0.0:
			var angle := (radius - sqrt(maxf(radius * radius - 0.028 * distance, 0.001))) / 0.014
			var inner_radius := radius - 0.014 * angle
			var thickness := point.y
			point.y = radius - (inner_radius - thickness) * cos(angle)
			point.z = (front + (inner_radius - thickness) * sin(angle)) * direction
		var world: Vector3 = sample.model.to_global(point - sample.offset)
		low = low.min(world)
		high = high.max(world)
	return AABB(low, high - low)


func whole_design_is_visible() -> bool:
	var space: Rect2 = game.completion_reveal.rug_view_rect()
	for x: float in [-1.06, 1.06]:
		for z: float in [-1.72, 1.72]:
			if not space.has_point(game.camera.unproject_position(Vector3(x, 0.08, z))):
				return false
	return true


func whole_room_is_visible() -> bool:
	var space: Rect2 = game.completion_reveal.rug_view_rect().grow(0.5)
	var bounds: AABB = game._workshop_geometry_bounds()
	for corner in 8:
		if not space.has_point(game.camera.unproject_position(bounds.get_endpoint(corner))):
			return false
	return true


func open_leaves_are_visible(tier: int) -> bool:
	var viewport: Rect2 = game.get_viewport().get_visible_rect()
	for side: String in ["LeftHinge", "RightHinge"]:
		var model: MeshInstance3D = game.room.get_node("Window/Tier%d/%s/BakedModel" % [tier, side])
		var bounds: AABB = model.mesh.get_aabb()
		for corner: int in 8:
			var world: Vector3 = model.to_global(bounds.get_endpoint(corner))
			if not viewport.has_point(game.camera.unproject_position(world)):
				return false
	return true


func validate_tier(tier: int) -> void:
	var start_cash: int = state.cash
	var start_job: String = game.contract_job_id
	var base_camera_size: float = game.camera.size
	await finish_full_restoration()
	var levels := {}
	for id: String in RoomRules.IDS:
		levels[id] = 0 if tier == 0 else RoomRules.visual_milestones(id, state.active_store)[tier - 1]
	game.room.set_levels(levels, state.active_store)
	await create_timer(0.5).timeout
	var expected_basis := CameraFit.workshop_basis(game.room_view_pitch_from_top, game.room_view_yaw_degrees)
	check(game.camera.global_basis.is_equal_approx(expected_basis), "Tier %d reveal preserves the authored room angle" % tier)
	if game.completion_reveal.is_landscape_layout():
		check(whole_room_is_visible(), "Tier %d landscape reveal frames the whole room beside Compare" % tier)
	else:
		check(game.camera.size >= base_camera_size * 0.90 - 0.001 and game.camera.size < base_camera_size, "Tier %d portrait design reveal uses a slight zoom" % tier)
	check(whole_design_is_visible(), "Tier %d reveal keeps the whole carpet and fringe in view" % tier)
	check(is_zero_approx(game.completion_focus.blur_amount), "Tier %d design hold is sharp" % tier)
	check(state.cash > start_cash and state.manual_jobs == tier + 1, "Tier %d reward commits exactly once before presentation" % tier)
	await capture_once("tier%d_design" % tier)
	var aperture: Dictionary = game.room.window_clear_aperture_world()
	check(float(aperture.width) > 2.0, "Tier %d clear window opening is wider than the carpet" % tier)
	check(is_zero_approx(game.room.window_open_amount), "Tier %d window starts closed" % tier)
	var paid_cash: int = state.cash
	game.skip_completion_reveal()
	game.skip_completion_reveal()
	check(game.rug_phase == game.RugPhase.DEPARTING, "Tier %d repeated skip enters just one departure" % tier)
	var saw_blur := false
	var saw_opening := false
	var saw_full_open := false
	var saw_curl := false
	var saw_passage := false
	var saw_breeze := false
	var leaves_cropped := false
	var curl_before_open := false
	var unsafe_passage := false
	var window_closed_early := false
	var prior_open := 0.0
	var smallest_camera := base_camera_size
	var furthest_z := 0.0
	for tick: int in 450:
		if game.contract_job_id != start_job:
			break
		var amount: float = game.soil.surface_materials[0].get_shader_parameter("roll_amount")
		var opening: float = game.room.window_open_amount
		var bounds := deformed_bounds()
		var straddles_window := bounds.position.z <= float(aperture.plane_z) and bounds.end.z >= float(aperture.plane_z)
		if game.completion_focus.blur_amount > 0.05:
			saw_blur = true
			if game.completion_focus.blur_amount > 0.7:
				await capture_once("tier%d_soft_return" % tier)
		if opening > 0.05 and opening < 0.95:
			saw_opening = true
		if opening >= 0.999:
			saw_full_open = true
			if not open_leaves_are_visible(tier):
				leaves_cropped = true
			if amount < 0.01:
				await capture_once("tier%d_open_window" % tier)
		if amount > 0.001:
			saw_curl = true
			if not saw_full_open:
				curl_before_open = true
			if amount > 0.3 and amount < 0.7:
				await capture_once("tier%d_curl" % tier)
		if straddles_window:
			saw_passage = true
			if opening < 0.999 or bounds.position.x < -float(aperture.width) * 0.5 or bounds.end.x > float(aperture.width) * 0.5 or bounds.position.y < float(aperture.bottom) - 0.002 or bounds.end.y > float(aperture.top) + 0.002:
				unsafe_passage = true
			await capture_once("tier%d_window_passage" % tier)
		if prior_open > opening + 0.001 and bounds.end.z >= float(aperture.plane_z):
			window_closed_early = true
		if game.room.breeze_strength > 0.01:
			saw_breeze = true
		prior_open = opening
		smallest_camera = minf(smallest_camera, game.camera.size)
		furthest_z = minf(furthest_z, game.get_node("RugDisplay").position.z)
		await create_timer(0.012).timeout
	check(saw_blur, "Tier %d zoom return includes transient soft focus" % tier)
	check(saw_opening and saw_full_open and saw_curl and not curl_before_open, "Tier %d window opens before the carpet curls" % tier)
	check(saw_passage and not unsafe_passage, "Tier %d rolled rug clears the sill, header and open leaves without shrinking" % tier)
	check(not leaves_cropped, "Tier %d fully open window leaves remain inside the viewport" % tier)
	check(not window_closed_early, "Tier %d window waits until the entire roll has passed before closing" % tier)
	check(furthest_z < -2.0, "Tier %d rug departs through the rear window" % tier)
	check(saw_breeze, "Tier %d completion starts the gentle plant breeze" % tier)
	check(smallest_camera >= base_camera_size * 0.90 - 0.001, "Tier %d camera never crops in beyond the restrained zoom" % tier)
	await wait_cleaning()
	check(game.contract_job_id != start_job and state.cash == paid_cash and state.manual_jobs == tier + 1, "Tier %d replacement starts without another payout" % tier)
	check(is_zero_approx(game.completion_focus.blur_amount) and not game.completion_focus.visible, "Tier %d new carpet has no lingering blur" % tier)
	check(is_zero_approx(game.room.window_open_amount), "Tier %d window closes for the next cleaning job" % tier)
	check(game.get_node("RugDisplay").position.is_zero_approx(), "Tier %d replacement rug returns to floor height and center" % tier)
	check(game.camera.global_basis.is_equal_approx(expected_basis), "Tier %d replacement keeps the room angle" % tier)
	await capture_once("tier%d_next_rug" % tier)


func validate_interruption() -> void:
	root.size = Vector2i(844, 390)
	await frames()
	var starting_cash: int = state.cash
	state._save_enabled = false
	game.soil.remaining = 0
	game.soil.surface_coverage_total = 0.0
	game.update_contract_status()
	await frames()
	check(game.rug_phase == game.RugPhase.CLEANING and state.cash == starting_cash, "A failed completion save cannot start the room celebration")
	check(is_zero_approx(game.completion_focus.blur_amount) and is_zero_approx(game.room.window_open_amount) and is_zero_approx(game.room.breeze_strength), "A failed save leaves the room still and sharp")
	state._save_enabled = true
	game.finish_rug()
	for _tick: int in 150:
		if game.soil.vacuum_complete:
			break
		game.soil._physics_process(1.0 / 60.0)
	await frames()
	game.completion_reveal.remaining = 30.0
	await create_timer(0.12).timeout
	game.completion_reveal.set_comparing(true)
	check(is_zero_approx(game.completion_focus.blur_amount) and is_equal_approx(game.completion_zoom, 1.0), "Holding Compare settles the camera and immediately removes moving blur")
	check(whole_design_is_visible(), "Landscape comparison keeps the whole carpet in view")
	game.completion_reveal.set_comparing(false)
	await capture_once("landscape_design")
	var reserved_job: String = state.active_job_id
	var paid_cash: int = state.cash
	game.skip_completion_reveal()
	await create_timer(0.15).timeout
	check(game.completion_focus.blur_amount > 0.0, "Back interruption begins during the real soft-focus return")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var paused_camera: Transform3D = game.camera.global_transform
	var paused_size: float = game.camera.size
	var paused_breeze: float = game.room.breeze_time
	await create_timer(0.18).timeout
	check(game.camera.global_transform.is_equal_approx(paused_camera) and is_equal_approx(game.camera.size, paused_size) and is_equal_approx(game.room.breeze_time, paused_breeze), "Focus loss pauses the camera transition and plant motion together")
	check(is_zero_approx(game.completion_focus.blur_amount), "Focus loss clears the temporary blur overlay")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(0.04).timeout
	check(not is_equal_approx(game.camera.size, paused_size) or not game.camera.global_transform.is_equal_approx(paused_camera), "Focus return resumes the paused transition")
	game.back()
	await frames()
	check(current_scene.scene_file_path == "res://scenes/production/floating_home.tscn" and state.cash == paid_cash, "Back during a blurred transition keeps the committed payout")
	change_scene_to_file("res://scenes/production/rug_cleaning.tscn")
	await frames()
	game = current_scene
	await wait_cleaning()
	check(game.contract_job_id == reserved_job and state.cash == paid_cash, "Re-entry resumes the reserved rug without another payment")
	check(is_zero_approx(game.completion_focus.blur_amount) and not game.completion_focus.visible and is_zero_approx(game.room.window_open_amount) and is_zero_approx(game.room.breeze_strength), "Re-entry cannot inherit blur, an open window or a stale breeze")


func run() -> void:
	state = root.get_node("ShopState")
	state._save_path = "res://.godot/completion_choreography_test_%d.json" % OS.get_process_id()
	state.set_process(false)
	check(state.reset_progress(), "Isolated completion choreography ledger resets")
	root.size = Vector2i(390, 844)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	await wait_cleaning()
	prepare_roll_samples()
	var scene_id: int = game.get_instance_id()
	var pool_id: int = game.soil.batch.get_instance_id()
	for tier: int in range(4):
		if tier == 3:
			root.size = Vector2i(844, 390)
			await frames()
		await validate_tier(tier)
	check(game.get_instance_id() == scene_id and game.soil.batch.get_instance_id() == pool_id, "All four completion tiers reuse the live scene and dirt pool")
	await validate_interruption()
	game.free()
	current_scene = null
	state.set_process(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("COMPLETION_CHOREOGRAPHY_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
