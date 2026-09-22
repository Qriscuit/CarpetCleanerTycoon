extends SceneTree
## Renderer-backed integration test. Player saves are isolated by --shop-test.
## Godot --path CarpetToy --script ../tools/validate_water_jet.gd -- --shop-test

const Routes = preload("res://scripts/scene_routes.gd")

var checks := 0
var failures := 0
var game: Node
var water: Node
var soil: Node


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to keep player saves isolated")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Water jet validation requires a real renderer for visual captures")
		quit(2)
		return
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func settle() -> void:
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout
	await settle()


func wait_for_contact(timeout_seconds := 3.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(water.debug_stats().contact_active):
			return true
		await process_frame
	return false


func wait_for_idle() -> void:
	var deadline := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < deadline:
		if not water.is_processing() and not soil.is_processing():
			await settle()
			return
		await process_frame
	check(false, "Released jet, droplets and shared mask settle within 2.5 seconds")


func tap(button: Button) -> void:
	for down: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 1
		event.position = button.get_global_rect().get_center()
		event.pressed = down
		root.push_input(event, true)


func begin_hose(point: Vector3) -> void:
	game.begin_stroke(game.camera.unproject_position(point), false)


func move_hose(point: Vector3) -> void:
	game.move_brush_to_screen(game.camera.unproject_position(point), false)


func mask_stats() -> Dictionary:
	var mask: Image = soil.wet_mask
	var bytes := mask.get_data()
	var total := 0
	var occupied := 0
	var outside := 0
	for index in bytes.size():
		var value := int(bytes[index])
		total += value
		if value > 5:
			occupied += 1
		if soil.surface_pixels[index] == 0 and value > 0:
			outside += 1
	return {"hash": hash(bytes), "total": total, "occupied": occupied, "outside": outside}


func capture(label: String) -> void:
	await settle()
	var output := "res://../art/renders/water_jet_" + label + ".png"
	check(root.get_texture().get_image().save_png(output) == OK, "Capture " + label)
	print("WATER_JET_CAPTURE ", ProjectSettings.globalize_path(output))


func node_count(node: Node) -> int:
	var result := 1
	for child in node.get_children():
		result += node_count(child)
	return result


func advance_water(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var step := minf(remaining, 1.0 / 240.0)
		water._process(step)
		remaining -= step


func check_lifecycle_edges() -> void:
	# A press and release arriving in the same frame creates no emitted volume.
	game.reset_rug()
	water.set_emitter(true, Vector3(0.0, 0.60, 0.0), Vector3.DOWN)
	water.set_emitter(false, water.nozzle, Vector3.DOWN)
	await wait_for_idle()
	check(not water.is_processing() and not water.stream.visible and int(mask_stats().total) == 0, "A same-frame tap returns to idle without water or outstanding work")

	# This burst is shorter than the normal deposition interval. Its final
	# contact fraction must still reach the shared wet mask after the tail lands.
	game.reset_rug()
	water.set_emitter(true, Vector3(0.0, 0.60, 0.0), Vector3.DOWN)
	advance_water(0.02)
	water.set_emitter(false, water.nozzle, Vector3.DOWN)
	check(int(mask_stats().total) == 0, "A short released burst stays dry while still airborne")
	var short_burst_contact := false
	for _frame in 360:
		if not water.is_processing():
			break
		water._process(1.0 / 240.0)
		short_burst_contact = short_burst_contact or bool(water.debug_stats().contact_active)
	check(short_burst_contact and int(mask_stats().total) > 0 and int(water.debug_stats().wet_events) > 0, "A burst shorter than the deposition interval still wets the carpet on landing")
	check(not water.is_processing() and int(water.debug_stats().active_droplets) == 0, "A short burst drains and retires all splash work")

	# Re-press while old water is in flight: preserve its downstream trajectory.
	game.reset_rug()
	water.set_emitter(true, Vector3(-0.45, 0.60, 0.0), Vector3.DOWN)
	advance_water(0.35)
	water.set_emitter(false, water.nozzle, Vector3.DOWN)
	advance_water(0.02)
	var old_tail: Vector3 = water.debug_stats().ring_centers[-1]
	water.set_emitter(true, Vector3(0.45, 0.60, 0.0), Vector3.DOWN)
	advance_water(1.0 / 240.0)
	var reconnected: Dictionary = water.debug_stats()
	var reconnected_centers: PackedVector3Array = reconnected.ring_centers
	check(reconnected.contact_active and absf(reconnected_centers[-1].x - old_tail.x) < 0.05, "Rapid re-press preserves the already emitted tail and its impact")
	check(reconnected_centers[0].distance_to(water.nozzle) < 0.015 and int(reconnected.history_count) > 2, "Rapid re-press attaches new water to the spout without discarding pose history")

	# Aim near either side of the raised carpet boundary, including trajectories
	# whose plane crossing and next sampled point fall on different surfaces.
	var hit_rug := false
	var hit_floor := false
	for target_x in [0.98, 0.99, 0.995, 1.0, 1.005, 1.01, 1.025, 1.05]:
		game.reset_rug()
		water.set_emitter(true, Vector3(target_x - 0.12, 0.55, 0.0), Vector3(0.30, -1.0, 0.0).normalized())
		advance_water(0.35)
		var edge: Dictionary = water.debug_stats()
		var point: Vector3 = edge.contact_position
		var inside: bool = soil.footprint.contains_point(Vector2(point.x, point.z))
		var expected_y: float = water.SURFACE_HEIGHT if inside else water.FLOOR_HEIGHT
		check(edge.contact_active and bool(edge.contact_on_rug) == inside and absf(point.y - expected_y) < 0.0001, "Boundary jet lands on the correct rug or tile plane at x %.3f" % target_x)
		hit_rug = hit_rug or (bool(edge.contact_active) and inside)
		hit_floor = hit_floor or (bool(edge.contact_active) and not inside)
	check(hit_rug and hit_floor and int(mask_stats().outside) == 0, "Boundary cases exercise both surface heights without wetting outside the rug")
	game.reset_rug()
	await settle()
	check(int(mask_stats().total) == 0 and not water.is_processing(), "Lifecycle regression cases leave the normal fixture dry and idle")


func run() -> void:
	var state: Node = root.get_node("ShopState")
	state.set_process(false)
	state._test_unix_time = 1234567890.0
	state._test_ticks_msec = 0
	state._last_ticks = 0
	check(state.reset_progress(), "Create isolated test progress")
	state.cash = 123
	check(not state.start_job().is_empty(), "A paid job exists beside the free practice scene")
	var saved_state: Dictionary = state._capture_state().duplicate(true)
	var saved_bytes := FileAccess.get_file_as_bytes(state._save_path)

	root.size = Vector2i(390, 844)
	game = load(Routes.GYM).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await settle()
	water = game.water
	soil = game.soil
	check(is_instance_valid(water) and water.has_method("debug_stats"), "Gym owns the continuous jet controller")
	check(not water.is_physics_processing(), "Visual water has no per-body physics callback")
	var controller_id := water.get_instance_id()
	var wet_texture_id: int = soil.wet_texture.get_instance_id()
	var stream_node_id: int = water.stream.get_instance_id()
	var stream_mesh_id: int = water.stream.mesh.get_instance_id()
	var stream_material_id: int = water.stream_material.get_instance_id()
	var impact_id: int = water.impact.get_instance_id()
	var initial_nodes := node_count(water)

	tap(game.hud.control("GymRug2"))
	await settle()
	check(game.selected_rug == 1 and game.selected_tool == 2 and water.enabled, "Rug 2 equips the continuous hose")
	check(game.wet_recipe and soil.wet_recipe, "Hose feeds the shared wet-cleaning recipe")
	check(soil.water_clearance() == 0.0 and soil.extraction_clearance() == 0.0, "Wet practice begins dry")
	check(soil.wet_mask.get_format() == Image.FORMAT_L8 and soil.wet_mask.get_size() == Vector2i(256, 416), "Existing 256 x 416 L8 texture owns carpet wetness")
	check((game.hud.control("GymSqueegee") as Button).disabled, "Squeegee begins locked")
	var socket := game.tool_nodes[2].find_child("NozzleSocket", true, false) as Marker3D
	check(socket != null, "Hose provides an explicit 3D nozzle socket")
	check(not game.hud.control("WaterDropCharge").visible, "Former discrete-drop charge UI is hidden")
	await check_lifecycle_edges()

	# Exercise the actual equipped hose, rather than a disconnected test emitter.
	begin_hose(Vector3(-0.45, 0.067, -0.65))
	check(game.brush_dragging and water.emitting, "Holding the real hose begins emission immediately")
	if socket != null:
		check(water.nozzle.distance_to(socket.global_position) < 0.001, "Water source is attached to the equipped nozzle socket")
	check(int(mask_stats().total) == 0, "Pressing cannot paint water before it travels to the carpet")
	water.set_process(false)
	water._process(0.04)
	var starting: Dictionary = water.debug_stats()
	check(not starting.contact_active and int(mask_stats().total) == 0, "A newly emitted short column stays airborne during startup")
	check(int(starting.visible_rings) >= 2 and water.stream.visible, "Startup renders connected water before first impact")
	water.set_process(true)
	check(await wait_for_contact(), "Water reaches the carpet after its physical flight time")
	await wait_seconds(0.25)
	var steady: Dictionary = water.debug_stats()
	var first_mark := mask_stats()
	check(int(first_mark.occupied) > 0 and soil.water_clearance() > 0.0, "A stationary held hose wets the carpet")
	check(int(steady.visible_rings) == int(steady.ring_count), "Sustained water spans the complete tube")
	check(water.stream.visible and water.stream.material_override == water.stream_material, "One mesh renders the continuous water material")
	check(int(steady.active_droplets) > 0, "Continuous carpet contact emits secondary splash droplets")
	check(int(steady.history_count) <= int(steady.history_capacity), "Nozzle history uses a bounded buffer")
	var centers: PackedVector3Array = steady.ring_centers
	check(centers.size() == int(steady.ring_count), "Every tube ring has a centerline sample")
	if centers.size() > 1:
		check(centers[0].distance_to(water.nozzle) < 0.015, "The rendered tube starts at the nozzle")
		check(centers[centers.size() - 1].distance_to(steady.contact_position) < 0.04, "The rendered tube ends at its visible impact")
	var stream_arrays: Array = water.stream.mesh.surface_get_arrays(0)
	var stream_vertices: PackedVector3Array = stream_arrays[Mesh.ARRAY_VERTEX]
	check(stream_vertices.size() >= 100 and stream_vertices.size() <= 512, "The solid 3D stream uses a small fixed mesh")
	await capture("steady_portrait")
	var contacts_before := int(water.debug_stats().wet_events)
	await wait_seconds(0.22)
	check(int(water.debug_stats().wet_events) > contacts_before, "Watering continues without pointer movement")

	# Abrupt movement changes the newest parcel only. Old water must remain in
	# world space rather than translating with its parent hose model.
	var before_move: Dictionary = water.debug_stats()
	var old_centers: PackedVector3Array = before_move.ring_centers.duplicate()
	water.set_process(false)
	move_hose(Vector3(0.45, 0.067, -0.65))
	water.set_process(false)
	water._process(1.0 / 240.0)
	water.set_process(false)
	var moved: Dictionary = water.debug_stats()
	var moved_centers: PackedVector3Array = moved.ring_centers
	if moved_centers.size() > 1 and old_centers.size() == moved_centers.size():
		check(moved_centers[0].distance_to(water.nozzle) < 0.015, "New water follows a moved spout immediately")
		check(absf(moved_centers[0].x - old_centers[0].x) > 0.70, "Test movement meaningfully displaces the nozzle")
		check(absf(moved_centers[-1].x - old_centers[-1].x) < 0.20, "Already emitted water trails the spout instead of snapping with it")
	else:
		check(false, "Moving stream retains its centerline samples")
	await capture("movement_lag_portrait")
	water.set_process(true)
	await wait_seconds(0.45)
	check(int(mask_stats().occupied) > int(first_mark.occupied), "Dragging the actual nozzle waters another area")
	check(int(mask_stats().outside) == 0, "Water painting respects the rounded carpet and fringe footprint")

	# A close oblique view exposes the entire volumetric column and impact rim.
	move_hose(Vector3(0.0, 0.067, -0.20))
	await wait_seconds(0.30)
	var original_camera: Transform3D = game.camera.transform
	var original_camera_size: float = game.camera.size
	game.camera.position = Vector3(1.65, 1.9, 2.15)
	game.camera.look_at(Vector3(0.0, 0.30, -0.08))
	game.camera.size = 2.5
	game.hud.hide()
	await capture("column_closeup")
	game.hud.show()
	game.camera.transform = original_camera
	game.camera.size = original_camera_size

	game.end_stroke()
	check(not water.emitting and int(water.debug_stats().visible_rings) > 0, "Releasing stops new water while the airborne tail drains")
	await wait_for_idle()
	var idle: Dictionary = water.debug_stats()
	check(not idle.contact_active and int(idle.visible_rings) == 0 and int(idle.active_droplets) == 0, "Release clears the column, impact and secondary droplets")
	check(not water.stream.visible and not water.is_processing(), "Settled water disables its renderable and CPU callback")
	var idle_processes := int(idle.process_count)
	var idle_mask := mask_stats()
	await wait_seconds(0.12)
	check(int(water.debug_stats().process_count) == idle_processes and mask_stats().hash == idle_mask.hash, "Idle hose performs no more work or carpet painting")

	# Fully off-carpet water must neither teleport to an edge nor paint a rug.
	water.set_emitter(true, Vector3(4.0, 0.60, 0.0), Vector3.DOWN)
	await wait_seconds(0.45)
	check(water.debug_stats().contact_active and not water.debug_stats().contact_on_rug and mask_stats().hash == idle_mask.hash, "A stream missing the carpet hits the floor without painting the rug")
	water.set_emitter(false, water.nozzle, Vector3.DOWN)
	await wait_for_idle()

	var extraction_before: PackedFloat32Array = soil.extraction_values.duplicate()
	game.select_tool(1)
	soil.apply_squeegee_stroke(Vector3(-0.8, 0.067, 0.0), Vector3(0.8, 0.067, 0.0), 0.08)
	check(game.selected_tool == 2 and soil.extraction_values == extraction_before, "Squeegee remains unavailable before the full-wet threshold")
	check(soil.apply_water_blob(Vector3(0.0, 0.067, 0.0), 5.0), "Shared production paint path can saturate the practice footprint")
	await settle()
	game.update_contract_status()
	check(soil.water_stage_complete() and soil.water_stage_progress() == 1.0, "The shared 99% wetness gate remains reachable")
	check(water.emission_locked and (game.hud.control("GymHose") as Button).disabled, "Full wetness disables more hose emission")
	check(not (game.hud.control("GymSqueegee") as Button).disabled, "Full wetness unlocks extraction")
	var fully_wet := mask_stats()
	game.select_tool(1)
	game.begin_stroke(game.camera.unproject_position(Vector3(-0.8, 0.067, 0.0)), false)
	game.move_brush_to_screen(game.camera.unproject_position(Vector3(0.8, 0.067, 0.0)), false)
	game.end_stroke()
	await settle()
	check(soil.extraction_clearance() > 0.0 and int(mask_stats().total) < int(fully_wet.total), "Equipped squeegee removes water from the same L8 mask")
	check(soil.water_stage_complete(), "Extraction preserves cumulative wet-stage completion")
	await capture("extraction_portrait")

	game.reset_rug()
	await settle()
	check(game.selected_tool == 2 and int(mask_stats().total) == 0 and not water.is_processing(), "Reset restores a dry rug and idle hose")
	# A severe frame hitch must not replay seconds of deposits in one frame,
	# allocate unbounded history, or revive old work after a reset.
	begin_hose(Vector3(0.0, 0.067, -0.3))
	water.set_process(false)
	water._process(10.0)
	check(int(mask_stats().total) == 0, "A stalled startup frame cannot instantly wet the carpet")
	for _frame in 5:
		var events_before := int(water.debug_stats().wet_events)
		water._process(10.0)
		check(int(water.debug_stats().wet_events) - events_before <= 8, "A severe hitch performs bounded water deposition")
	var hitch: Dictionary = water.debug_stats()
	check(int(hitch.history_count) <= int(hitch.history_capacity) and int(hitch.active_droplets) < 100, "Repeated hitches preserve bounded history and splash pools")
	check(soil.water_clearance() > 0.0 and soil.water_clearance() < 0.10, "Hitches advance only the local wetted footprint")
	game.reset_rug()
	await wait_seconds(0.35)
	check(int(mask_stats().total) == 0 and not water.is_processing(), "Reset cancels any remaining work after long frames")
	begin_hose(Vector3(0.0, 0.067, -0.3))
	await wait_for_contact()
	game.reset_rug()
	await wait_seconds(0.50)
	check(int(mask_stats().total) == 0 and int(water.debug_stats().visible_rings) == 0 and int(water.debug_stats().active_droplets) == 0, "Reset cancels airborne water and every delayed splash")
	begin_hose(Vector3(0.0, 0.067, -0.3))
	tap(game.hud.control("GymRug1"))
	await wait_seconds(0.35)
	check(not water.enabled and not water.is_processing() and game.selected_tool == 0, "Switching exercises cancels the jet and restores brush practice")
	tap(game.hud.control("GymRug2"))
	await settle()
	check(game.selected_tool == 2 and soil.water_clearance() == 0.0, "Returning to Rug 2 starts fresh hose practice")

	root.size = Vector2i(844, 390)
	await settle()
	begin_hose(Vector3(-0.30, 0.067, -0.50))
	check(await wait_for_contact(), "Hose remains functional in landscape")
	await wait_seconds(0.20)
	await capture("steady_landscape")
	game.end_stroke()
	await wait_for_idle()
	check(water.get_instance_id() == controller_id and soil.wet_texture.get_instance_id() == wet_texture_id, "Resets and exercise changes reuse the water controller and shared wet texture")
	check(water.stream.get_instance_id() == stream_node_id and water.stream.mesh.get_instance_id() == stream_mesh_id and water.stream_material.get_instance_id() == stream_material_id, "Motion and resets reuse the fixed stream mesh and material")
	check(water.impact.get_instance_id() == impact_id and node_count(water) == initial_nodes, "Splash emission and repeated use create no growing node population")
	check(int(water.debug_stats().history_count) <= int(water.debug_stats().history_capacity), "Repeated use keeps nozzle history bounded")
	check(state._capture_state() == saved_state and FileAccess.get_file_as_bytes(state._save_path) == saved_bytes, "Hose practice preserves paid progress, cash and on-disk save")
	game.return_to_shop()
	await settle()
	check(current_scene.scene_file_path == Routes.MAIN_MENU and FileAccess.get_file_as_bytes(state._save_path) == saved_bytes, "Leaving practice returns home without changing the paid save")
	print("WATER_JET_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
