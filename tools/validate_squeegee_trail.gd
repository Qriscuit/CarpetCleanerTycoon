extends SceneTree
## Renderer-backed cleared-swath union, lingering ridge and edge runoff checks.
const Routes := preload("res://scripts/scene_routes.gd")
var checks := 0
var failures := 0
var game: Node
var soil: Node
var water: Node
var trail: Node

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
	await RenderingServer.frame_post_draw

func prepare() -> void:
	game.select_rug(1)
	game._on_practice_tool_pressed(1)
	water.set_process(false)

func advance(seconds: float) -> void:
	for _frame in ceili(seconds * 60.0):
		water._process(1.0 / 60.0)
	water.set_process(false)

func step(a: Vector3, b: Vector3, seconds := 1.0 / 60.0) -> void:
	game.apply_selected_tool_stroke(a, b, seconds)
	game.contact_point = b
	game.place_selected_tool()
	water._process(seconds)
	water.set_process(false)

func swipe(a: Vector3, b: Vector3, speed := 0.7) -> void:
	var frames := maxi(1, ceili(a.distance_to(b) / speed * 60.0))
	for frame in frames:
		step(a.lerp(b, float(frame) / frames), a.lerp(b, float(frame + 1) / frames))
	game.end_stroke()
	water.set_process(false)
	advance(0.12)

func capture(label: String) -> void:
	soil._process(0.0)
	water.set_process(false)
	await settle()
	var path := "res://../art/renders/squeegee_trail_" + label + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "Capture " + label)
	print("SQUEEGEE_TRAIL_CAPTURE ", ProjectSettings.globalize_path(path))

func segment_mid(index: int) -> Vector3:
	var edge: Dictionary = trail.segment_debug(index)
	return (edge.start as Vector3).lerp(edge.end, 0.5)

func run() -> void:
	var state: Node = root.get_node("ShopState")
	state.set_process(false)
	state._test_unix_time = 1234567890.0
	state._test_ticks_msec = 0
	state._last_ticks = 0
	check(state.reset_progress(), "Isolate trail test saves")
	state.cash = 123
	check(not state.start_job().is_empty(), "Keep a paid job beside the free Gym")
	var saved: Dictionary = state._capture_state().duplicate(true)
	var saved_bytes := FileAccess.get_file_as_bytes(state._save_path)
	root.size = Vector2i(1100, 900)
	game = load(Routes.GYM).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await settle()
	soil = game.soil
	water = game.squeegee_water
	trail = water.trail
	check(trail != null and not trail.is_alive(), "Fresh dry Gym has no fabricated cleaned-path ridge")
	var mesh_id: int = trail.batch.mesh.get_instance_id()
	var batch_id: int = trail.batch.get_instance_id()
	var texture_id: int = soil.wet_texture.get_instance_id()
	check(trail.material.shader == water.impact.patch_material.shader, "Trail, head splash and hose share the existing splash shader")
	prepare()
	check(not trail.is_alive() and int(trail.debug_stats().active_segments) == 0, "Instantly wetting the rug creates no extracted boundary")
	game.hud.hide()
	game.camera.position = Vector3(1.65, 2.40, 2.5)
	game.camera.look_at(Vector3(0, 0.08, 0.15))
	game.camera.size = 3.95
	var a := Vector3(0, 0.067, -0.9)
	var b := Vector3(0, 0.067, 0.9)
	swipe(a, b)
	swipe(b, a)
	var centered: Dictionary = trail.debug_stats()
	check(int(centered.active_segments) > 20, "Real back-and-forth extraction leaves a substantial path boundary")
	check(int(centered.spill_segments) == 0, "A centered channel cannot spill through intact carpet")
	var pressure_encoding_ok := true
	for index in int(centered.active_segments):
		var packed: float = trail.batch.get_instance_custom_data(index).a
		var segment: Dictionary = trail.segment_debug(index)
		pressure_encoding_ok = pressure_encoding_ok and packed >= 0.0 and packed <= 1023.0 and is_equal_approx(packed, roundf(packed))
		pressure_encoding_ok = pressure_encoding_ok and is_equal_approx(fmod(packed, 32.0) / 31.0, float(segment.pressure_start)) and is_equal_approx(floorf(packed / 32.0) / 31.0, float(segment.pressure_end))
	check(pressure_encoding_ok, "Shared endpoint pressure packing stays exactly representable in Compatibility float16 instance data")
	var left := false
	var right := false
	var behind_blade := false
	for index in int(centered.active_segments):
		var p := segment_mid(index)
		left = left or (p.x < -0.20 and absf(p.z) < 0.65)
		right = right or (p.x > 0.20 and absf(p.z) < 0.65)
		behind_blade = behind_blade or p.distance_to(game.contact_point) > 1.0
	check(left and right, "Water ridges line both long sides of the cleaned channel")
	check(behind_blade, "Path water stays anchored far behind the current blade")
	await capture("centered_oblique")
	var wet_bytes: PackedByteArray = soil.wet_mask.get_data()
	var extracted: PackedFloat32Array = soil.extraction_values.duplicate()
	var water_values: PackedFloat32Array = soil.water_values.duplicate()
	var contour_origin: Dictionary = trail.segment_debug(0).duplicate(true)
	var old_crest: Vector3 = trail.sample_segment(0, 0.5, 0.5)
	var old_builds: int = trail.debug_stats().build_count
	var old_renewals: int = trail.debug_stats().renewal_count
	advance(2.0)
	check(not water.impact.is_alive() and trail.is_alive(), "Ridge remains after the head splash settles")
	var held_contour: Dictionary = trail.segment_debug(0)
	check(held_contour.start == contour_origin.start and held_contour.end == contour_origin.end and held_contour.normal_start == contour_origin.normal_start and held_contour.normal_end == contour_origin.normal_end, "Released contour remains world anchored")
	check(old_crest.distance_to(trail.sample_segment(0, 0.5, 0.5)) > 0.0001, "The anchored path ridge continues gently undulating")
	check(int(trail.debug_stats().build_count) == old_builds, "Stationary ridge animates without rebuilding its contour")
	check(soil.wet_mask.get_data() == wet_bytes and soil.extraction_values == extracted and soil.water_values == water_values, "Visual ridge and runoff never alter wetness or extraction")
	game.set_camera_angle(true)
	check(trail.is_alive(), "Changing the camera preserves deposited path water")
	step(a, a)
	check(int(trail.debug_stats().renewal_count) == old_renewals, "Stationary input cannot renew the water ridge")
	advance(11.0)
	check(not trail.is_alive(), "Ridges eventually drain instead of updating forever")
	water._process(1.0 / 60.0)
	check(not water.is_processing(), "The controller disables processing after all water settles")

	# Two parallel overlapping strokes must become ONE union, without a seam.
	prepare()
	for x in [-0.18, 0.18]:
		a = Vector3(x, 0.067, -0.8)
		b = Vector3(x, 0.067, 0.8)
		swipe(a, b)
		swipe(b, a)
	var internal_edges := 0
	for index in int(trail.debug_stats().active_segments):
		var p := segment_mid(index)
		if absf(p.x) < 0.36 and absf(p.z) < 0.60:
			internal_edges += 1
	check(internal_edges == 0, "Overlapping cleaned swaths remove internal water seams")
	await capture("merged_swaths")

	# A perpendicular pass opens the middle of the existing channel as well.
	prepare()
	swipe(Vector3(0, 0.067, -0.8), Vector3(0, 0.067, 0.8))
	swipe(Vector3(-0.8, 0.067, 0), Vector3(0.8, 0.067, 0))
	internal_edges = 0
	for index in int(trail.debug_stats().active_segments):
		var p := segment_mid(index)
		if absf(p.x) < 0.23 and absf(p.z) < 0.23:
			internal_edges += 1
	check(internal_edges == 0, "Crossing passes remove the old ridge through their cleared intersection")
	await capture("crossed_swaths")

	# Reproduce the drawing: one long channel, then push off the tasselled end.
	prepare()
	a = Vector3(0, 0.067, -0.90)
	b = Vector3(0, 0.067, 1.68)
	swipe(a, b)
	# Inspect a fresh spill: repeated already-dry passes must not keep old
	# runoff alive now that each exit has its own short drainage clock.
	var spills: Dictionary = trail.debug_stats()
	check(int(spills.spill_segments) > 0 or trail.streams.is_alive(), "Pushing the cleaned channel to the rug edge creates runoff")
	var reaches_floor := false
	var ridge_is_raised := false
	for index in int(spills.active_segments):
		var edge: Dictionary = trail.segment_debug(index)
		if edge.spill:
			for along in [0.0, 0.5, 1.0]:
				var tip: Vector3 = trail.sample_segment(index, along, 1.0)
				reaches_floor = reaches_floor or (tip.y < 0.025 and not soil.footprint.contains_point(Vector2(tip.x, tip.z)))
		else:
			var crest: Vector3 = trail.sample_segment(index, 0.5, 0.5)
			ridge_is_raised = ridge_is_raised or crest.y > 0.10
	check(reaches_floor, "Edge runoff extends beyond the silhouette and drops onto the floor")
	check(ridge_is_raised, "The side ridge is genuinely raised 3D water, not a flat decal")
	var no_buried_spill := true
	for index in int(spills.active_segments):
		if not trail.segment_debug(index).spill:
			continue
		for row in range(trail.ROWS):
			for along in [0.0, 1.0]:
				var p: Vector3 = trail.sample_segment(index, along, float(row) / float(trail.ROWS - 1))
				var on_carpet: bool = trail._surface_at(Vector2(p.x, p.z))
				no_buried_spill = no_buried_spill and p.y >= (0.070 if on_carpet else 0.006)
	check(no_buried_spill, "Wide spill vertices remain above adjacent fringe and floor")
	game.hud.hide()
	game.camera.position = Vector3(1.65, 2.40, 2.5)
	game.camera.look_at(Vector3(0, 0.08, 0.2))
	game.camera.size = 4.05
	await capture("runoff_oblique")
	game.camera.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 6, 0.15))
	game.camera.size = 3.9
	await capture("runoff_top")
	var frozen_builds: int = trail.debug_stats().build_count
	var frozen_renewals: int = trail.debug_stats().renewal_count
	for _tick in 20:
		step(Vector3(2, 0.006, 0.5), Vector3(2, 0.006, 0.6))
	check(int(trail.debug_stats().build_count) == frozen_builds and int(trail.debug_stats().renewal_count) == frozen_renewals, "Off-rug strokes cannot generate or refresh runoff")
	check(int(spills.active_segments) <= int(spills.capacity), "Long repeated swipes respect the fixed segment budget")
	check(int(spills.clipped_segments) == 0 and int(spills.build_count) < int(spills.notification_count) / 2, "Real strokes coalesce contour rebuilds without exhausting the pool")
	print("SQUEEGEE_TRAIL_STATS ", spills)
	# Move back up the same cleared channel so the lingering floor spill is
	# unobscured by the head, matching the reference drawing's composition.
	swipe(b, Vector3(0, 0.067, 0.25))
	game.camera.position = Vector3(1.65, 2.40, 2.5)
	game.camera.look_at(Vector3(0, 0.08, 0.2))
	game.camera.size = 4.05
	await capture("return_pass")
	game._on_practice_tool_pressed(2)
	check(not trail.is_alive() and int(trail.debug_stats().active_segments) == 0, "Hose shortcut removes every ridge and spill")
	advance(0.5)
	check(not trail.is_alive(), "Canceled contour work cannot resurrect water after reset")
	game._on_practice_tool_pressed(1)
	check(not trail.is_alive(), "Squeegee shortcut starts a fresh rug with no old path water")
	swipe(Vector3(0.82, 0.067, 1.20), Vector3(1.10, 0.067, 1.52), 0.35)
	check(int(trail.debug_stats().spill_segments) > 0 or trail.streams.is_alive(), "Diagonal cleaning uses the rounded carpet corner for runoff")
	game.select_rug(0)
	check(not trail.is_alive() and not water.is_processing(), "Switching exercises removes all persistent visual water")
	check(trail.batch.get_instance_id() == batch_id and trail.batch.mesh.get_instance_id() == mesh_id, "Contour changes and resets reuse the same mesh and fixed batch")
	check(soil.wet_texture.get_instance_id() == texture_id, "Trail never replaces the real wetness texture")
	check(state._capture_state() == saved and FileAccess.get_file_as_bytes(state._save_path) == saved_bytes, "Trail practice preserves paid progress and save bytes")
	print("SQUEEGEE_TRAIL_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
