extends SceneTree
## Actual Gym extraction + four-edge splash geometry, lifecycle and save isolation.
const Routes := preload("res://scripts/scene_routes.gd")
var checks := 0
var failures := 0
var game: Node
var water: Node
var soil: Node

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Use a renderer and -- --shop-test")
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

func capture(label: String) -> void:
	water.set_process(false)
	soil._process(0.0)
	await settle()
	var path := "res://../art/renders/squeegee_" + label + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "Capture " + label)
	print("SQUEEGEE_CAPTURE ", ProjectSettings.globalize_path(path))

func prepare() -> void:
	game.select_rug(1)
	game._on_practice_tool_pressed(1)
	water.set_process(false)

func step(from: Vector3, to: Vector3, delta := 1.0 / 60.0) -> void:
	game.apply_selected_tool_stroke(from, to, delta)
	game.contact_point = to
	game.place_selected_tool()
	water._process(delta)
	water.set_process(false)

func advance(seconds: float) -> void:
	for _frame in ceili(seconds * 120.0):
		water._process(1.0 / 120.0)
	water.set_process(false)

func straight(start: Vector3, direction: Vector3, frames: int, speed := 0.75) -> Vector3:
	var point := start
	for _frame in frames:
		var next := point + direction * speed / 60.0
		step(point, next)
		point = next
	return point

func check_four_edge_geometry() -> void:
	var impact: Node = water.impact
	var directions: Array[Vector3] = [water.heading, -water.heading, Vector3.UP.cross(water.heading), -Vector3.UP.cross(water.heading)]
	var found := [false, false, false, false]
	var extends_outward := true
	var peak := 0.0
	var nearest := INF
	var wave_changes := false
	for index in 128:
		var u := float(index) / 128.0
		var edge: Dictionary = impact.sample_perimeter(u)
		var normal: Vector3 = edge.normal
		var offset: Vector3 = edge.point - water.contact_position
		nearest = minf(nearest, Vector2(offset.x, offset.z).length())
		for side in 4:
			if normal.dot(directions[side]) > 0.999:
				found[side] = true
		var tip: Vector3 = impact.sample_splash(u, 1.0)
		extends_outward = extends_outward and (tip - (edge.point as Vector3)).dot(normal) > 0.015
		for row in 9:
			var sample: Vector3 = impact.sample_splash(u, float(row) / 8.0)
			peak = maxf(peak, sample.y - water.contact_position.y)
		var before: Vector3 = impact.sample_splash(u, 0.65)
		var old_clock: float = impact.clock_seconds
		impact.clock_seconds += 0.19
		var after: Vector3 = impact.sample_splash(u, 0.65)
		impact.clock_seconds = old_clock
		wave_changes = wave_changes or before.distance_to(after) > 0.002
	check(found.all(func(value): return value), "All four local blade edges have their own outward normals")
	check(extends_outward, "Every sampled edge throws its curl outward, not only forwards")
	check(nearest > 0.05, "Perimeter has an open center instead of a filled cyan slab")
	check(peak > 0.025 and peak <= 0.13, "Curl stays visibly raised but low beside the head; no tall column")
	check(wave_changes, "Perimeter curls visibly undulate over time")
	check(water.contact_position.distance_to(game.contact_point) < 0.001, "Splash remains centered on the physical blade")

func run() -> void:
	var state: Node = root.get_node("ShopState")
	state.set_process(false)
	state._test_unix_time = 1234567890.0
	state._test_ticks_msec = 0
	state._last_ticks = 0
	check(state.reset_progress(), "Isolate test save")
	state.cash = 123
	check(not state.start_job().is_empty(), "Preserve an existing paid job")
	var saved_state: Dictionary = state._capture_state().duplicate(true)
	var saved_bytes := FileAccess.get_file_as_bytes(state._save_path)
	root.size = Vector2i(600, 950)
	game = load(Routes.GYM).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await settle()
	water = game.squeegee_water
	soil = game.soil
	check(is_instance_valid(water), "Authored Gym scene owns the perimeter effect")
	check(not water.enabled and not water.is_processing(), "Brush exercise has no water work")
	var mesh_id: int = water.impact.patch.mesh.get_instance_id()
	var droplet_id: int = water.impact.droplet_batch.get_instance_id()
	var wet_id: int = soil.wet_texture.get_instance_id()
	check(water.find_children("WaterSheet*", "MeshInstance3D", true, false).is_empty(), "Old airborne water-sheet nodes are completely absent")
	check(water.find_children("*", "MeshInstance3D", true, false).size() == 1, "Squeegee owns just one perimeter mesh")
	check(water.impact.get_script() == game.water.impact.get_script(), "Hose and squeegee share the same splash implementation")
	check(water.impact.patch_material.shader == game.water.impact.patch_material.shader, "Circular and rectangular curls share the same visual shader")
	prepare()
	check(game.selected_tool == 1 and water.enabled, "Gym shortcut prepares the real squeegee")
	check(water.impact.droplet_batch.instance_count == 24, "Droplets retain the fixed 24-slot budget")
	var point := Vector3(0, 0.067, 0.75)
	step(point, point)
	check(water.emitted_strokes == 0 and not water.impact.is_alive(), "Stationary blade emits nothing")
	point = straight(point, Vector3.FORWARD, 1)
	check(water.debug_stats().active_splashes == 1 and water.debug_stats().active_edges == 4, "Positive extraction immediately lights all four edges without a flight delay")
	point = straight(point, Vector3.FORWARD, 41)
	check(water.emitted_strokes > 0 and water.removed_water > 0, "Only newly removed real water funds the visual effect")
	check(water.impact.active_droplet_count > 0, "Short outward curls emit small secondary droplets")
	check(water.debug_stats().active_sheets == 0, "No water column returns during an active swipe")
	check_four_edge_geometry()
	print("SQUEEGEE_PERIMETER ", water.debug_stats())
	await capture("gym_portrait")
	var camera_pose: Transform3D = game.camera.transform
	var camera_size: float = game.camera.size
	game.hud.hide()
	root.size = Vector2i(1100, 820)
	await settle()
	game.camera.position = Vector3(1.45, 1.55, 1.55)
	game.camera.look_at(Vector3(0, 0.10, -0.18))
	game.camera.size = 1.90
	await capture("perimeter_oblique_detail")
	game.end_stroke()
	check(not water.feeding and water.impact.is_alive(), "Release stops supply while small curls and droplets settle")
	var births: int = water.impact.emitted_count
	var extraction: float = soil.extraction_coverage_total
	var wet_total: float = soil.water_coverage_total
	advance(0.08)
	check(water.impact.is_alive(), "Splash eases out briefly rather than popping away")
	check(water.impact.emitted_count == births, "Release never creates more droplets")
	await capture("perimeter_settling")
	advance(1.0)
	check(not water.impact.is_alive() and water.trail.is_alive(), "Head splash retires promptly while cleared-path ridges linger")
	advance(11.0)
	check(not water.trail.is_alive() and not water.is_processing(), "Lingering ridge and runoff eventually settle to idle")
	check(soil.water_coverage_total == wet_total and soil.extraction_coverage_total == extraction, "Outward splash never rewets or alters extraction")

	prepare()
	point = straight(Vector3(0, 0.067, 0.5), Vector3.FORWARD, 30)
	point = straight(point, Vector3.BACK, 30)
	check(water.heading.dot(game.squeegee_motion.heading) > 0.999, "Rectangular perimeter follows reversed blade orientation")
	check(water.debug_stats().active_edges == 4, "Reversal retains all four splash sides")
	check_four_edge_geometry()
	await capture("perimeter_reversal")
	prepare()
	point = straight(Vector3(0.89, 0.067, 0.55), Vector3.FORWARD, 42)
	var stats: Dictionary = water.impact.debug_stats()
	check(int(stats.rug_contacts) > 0 and int(stats.floor_contacts) > 0, "Perimeter sampling resolves both carpet and floor at an edge")
	var no_buried_surface := true
	for index in 128:
		var sample: Vector3 = water.impact.sample_splash(float(index) / 128.0, 0.65)
		var on_rug: bool = soil.footprint.contains_point(Vector2(sample.x, sample.z))
		no_buried_surface = no_buried_surface and sample.y >= (0.067 if on_rug else 0.002)
	check(no_buried_surface, "Low splash does not sink into carpet when the head straddles its edge")
	game.camera.position = Vector3(2.0, 1.6, 1.5)
	game.camera.look_at(Vector3(0.9, 0.1, -0.15))
	game.camera.size = 1.90
	await capture("perimeter_rug_edge")

	advance(1.0)
	var emitted: int = water.emitted_strokes
	step(Vector3(2, 0.006, 0), Vector3(2, 0.006, -0.1))
	check(water.emitted_strokes == emitted, "Off-carpet motion cannot invent water")
	prepare()
	soil.extraction_values = soil.water_values.duplicate()
	soil.extraction_coverage_total = soil.water_coverage_total
	step(Vector3(0, 0.067, 0.1), Vector3(0, 0.067, 0))
	check(water.emitted_strokes == 0, "Dry carpet cannot emit new splash")
	prepare()
	point = straight(Vector3(0, 0.067, 0.5), Vector3.FORWARD, 12)
	advance(0.10)
	check(not water.feeding, "A stationary input gap promptly stops supply")
	for i in 50:
		var direction := Vector3.FORWARD if i % 2 == 0 else Vector3.BACK
		water.feed_stroke(point, point + direction * 0.01, 1.0 / 60.0, 40.0)
		water._process(1.0 / 60.0)
	water.set_process(false)
	check(water.debug_stats().active_splashes == 1 and water.debug_stats().active_sheets == 0, "Frantic motion never allocates another rim or column")
	check(water.impact.active_droplet_count <= 24, "Repeated splashes stay inside the droplet budget")
	game.reset_rug()
	check(not water.impact.is_alive() and not water.is_processing(), "Reset clears all curls and droplets without background work")
	game.hud.show()
	root.size = Vector2i(390, 844)
	game.camera.transform = camera_pose
	await settle()
	prepare()
	point = Vector3(-0.2, 0.067, 0.6)
	game.begin_stroke(game.camera.unproject_position(point), false)
	check(game.brush_dragging and water.emitted_strokes == 0, "Press only places the blade")
	for _frame in 32:
		point.z -= 0.014
		game.stroke_time = Time.get_ticks_msec() - 16
		game.move_brush_to_screen(game.camera.unproject_position(point), false)
		water._process(1.0 / 60.0)
		water.set_process(false)
	check(water.emitted_strokes > 0 and water.debug_stats().active_edges == 4, "Real screen-space drag drives four-edge splashing")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not game.brush_dragging and not water.feeding, "Focus loss stops splash supply")
	water.set_process(true)
	await create_timer(1.0).timeout
	check(not water.impact.is_alive() and water.trail.is_alive(), "Focus loss stops head splashing while the existing ridge lingers")
	advance(11.0)
	check(not water.is_processing() and not water.trail.is_alive(), "Existing ridge also retires after focus loss")
	for rate in [30.0, 60.0, 120.0]:
		water.reset()
		water.feed_stroke(Vector3.ZERO, Vector3.FORWARD * 0.6 / rate, 1.0 / rate, 0.3 / water.pixel_area / rate)
		check(absf(water.power - 0.3 / 0.65) < 0.001, "Extraction-rate normalization at %d Hz" % int(rate))
	water.reset()
	water.feed_stroke(Vector3(0, 0.067, 0), Vector3(0, 0.067, -0.01), 1.0 / 60.0, 0.03 / water.pixel_area / 60.0)
	water._process(1.0 / 60.0)
	check(water.power < 0.05, "Nearly dry supply produces a much gentler splash")
	water.reset()
	water.feed_stroke(Vector3(0, 0.067, 0), Vector3(0, 0.067, -0.04), 0.1, 100.0)
	water._process(0.1)
	check(water.debug_stats().active_edges == 4 and water.impact.patch.visible, "A newly funded swipe is visible even when its first render frame takes 100 ms")
	var hitch_births: int = water.impact.emitted_count
	water._process(0.1)
	check(not water.feeding and water.impact.emitted_count == hitch_births, "A presented slow-frame sample still stops new births on inactivity")
	prepare()
	straight(Vector3.ZERO, Vector3.FORWARD, 10)
	game.select_rug(0)
	check(not water.enabled and not water.impact.is_alive(), "Changing exercise cancels every splash immediately")
	check(water.impact.patch.mesh.get_instance_id() == mesh_id and water.impact.droplet_batch.get_instance_id() == droplet_id, "All strokes and resets reuse the mesh and droplet allocation")
	check(soil.wet_texture.get_instance_id() == wet_id, "Existing wetness texture is reused")
	check(state._capture_state() == saved_state, "Gym preserves paid state")
	check(FileAccess.get_file_as_bytes(state._save_path) == saved_bytes, "Gym preserves paid save bytes")
	game.camera.transform = camera_pose
	game.camera.size = camera_size
	print("SQUEEGEE_WATER_VALIDATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
