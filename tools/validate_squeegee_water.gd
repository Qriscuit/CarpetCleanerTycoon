extends SceneTree
## Renderer-backed Gym integration and bounded-lifecycle tests; isolated saves only.
## Godot --path CarpetToy --script ../tools/validate_squeegee_water.gd -- --shop-test

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
	soil.apply_water_blob(Vector3.ZERO, 5.0)
	game.update_contract_status()
	game.select_tool(1)
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
	check(is_instance_valid(water), "Authored Gym scene owns the squeegee effect")
	check(not water.enabled and not water.is_processing(), "Brush exercise has no water work")
	var mesh_id: int = water.sheets[0].mesh.mesh.get_instance_id()
	var wet_id: int = soil.wet_texture.get_instance_id()
	var arrays: Array = water.sheets[0].mesh.mesh.surface_get_arrays(0)
	check(arrays[Mesh.ARRAY_VERTEX].size() == 316, "Closed sheet has 316 fixed vertices")
	check(arrays[Mesh.ARRAY_INDEX].size() == 444 * 3, "Closed sheet has 444 triangles")
	prepare()
	check(game.selected_tool == 1 and water.enabled, "Wet stage unlocks the real squeegee")
	check(water.impact.drop_batch.instance_count == 24, "Shared droplets have a fixed 24-slot budget")
	check(water.sheets.size() == 3, "Turns use at most three sheet segments")
	var point := Vector3(0, 0.067, 0.75)
	step(point, point)
	check(water.debug_stats().emitted_strokes == 0, "Stationary blade emits nothing")
	point = straight(point, Vector3.FORWARD, 8)
	check(water.debug_stats().emitted_strokes > 0 and water.debug_stats().removed_water > 0, "Actual newly removed coverage drives emission")
	check(water.debug_stats().active_sheets == 1 and water.sheets[0].mesh.visible, "Short stroke renders an airborne thick sheet")
	check(water.debug_stats().impact.active_contacts == 0, "Splash waits for physical flight")
	point = straight(point, Vector3.FORWARD, 34)
	var stats: Dictionary = water.debug_stats()
	print("SQUEEGEE_STEADY ", stats)
	check(stats.impact.active_contacts == 7, "A broad push lands all seven transverse samples")
	check(stats.impact.active_droplets > 0, "Landing emits secondary droplets")
	var grid: PackedVector4Array = water.sheets[water.current].grid
	var peak := 0.0
	for vertex in grid: peak = maxf(peak, vertex.y)
	check(peak > 0.27 and peak < 0.33, "Arc crest is about 20 cm above its lip")
	check(absf(grid[6].x - grid[0].x) > 0.60, "Forward stroke spans most of the blade")
	check(grid[0].w > 0.012, "Opaque water has real visible thickness")
	await capture("gym_portrait")
	var camera_pose: Transform3D = game.camera.transform
	var camera_size: float = game.camera.size
	game.hud.hide()
	root.size = Vector2i(1100, 820)
	await settle()
	game.camera.position = Vector3(1.45, 1.55, 1.55)
	game.camera.look_at(Vector3(0, 0.10, -0.18))
	game.camera.size = 1.90
	await capture("oblique_detail")
	game.end_stroke()
	check(water.debug_stats().feeding_sheets == 0 and water.debug_stats().active_sheets > 0, "Release stops the source but retains airborne water")
	var extraction: float = soil.extraction_coverage_total
	var wet_total: float = soil.water_coverage_total
	advance(0.12)
	check(water.debug_stats().active_sheets > 0, "Released water travels instead of disappearing immediately")
	await capture("released_tail")
	advance(1.2)
	check(water.debug_stats().active_sheets == 0 and not water.impact.is_alive(), "Tail, patches and droplets drain completely")
	check(soil.water_coverage_total == wet_total and soil.extraction_coverage_total == extraction, "Landing VFX never rewet or change extraction progress")
	water._process(0.0)
	check(not water.is_processing(), "Controller disables itself when idle")
	prepare()
	point = straight(Vector3(0, 0.067, 0.5), Vector3.FORWARD, 30)
	var old_slot: int = water.current
	var old_origin: Vector3 = water.sheets[old_slot].origin
	point = straight(point, Vector3.BACK, 4)
	check(water.debug_stats().active_sheets == 2, "Reversal creates a fresh segment and drains the old one")
	check(water.sheets[old_slot].origin == old_origin and not water.sheets[old_slot].feeding, "Old trajectory does not teleport with the tool")
	game.camera.position = Vector3(1.45, 1.55, 1.55)
	game.camera.look_at(Vector3(0, 0.10, -0.18))
	game.camera.size = 1.90
	await capture("reversal")
	# Straddle the raised rug and floor with one broad sheet.
	prepare()
	point = straight(Vector3(0.89, 0.067, 0.55), Vector3.FORWARD, 42)
	stats = water.debug_stats()
	check(stats.impact.rug_contacts > 0 and stats.impact.floor_contacts > 0, "Wide landing respects both rug and tile heights")
	game.camera.position = Vector3(2.0, 1.6, 1.5)
	game.camera.look_at(Vector3(0.9, 0.1, -0.15))
	game.camera.size = 1.90
	await capture("rug_edge")
	# Off-rug / dry / disabled strokes have no renewed supply.
	advance(1.0)
	var emitted: int = water.emitted_strokes
	step(Vector3(2, 0.006, 0), Vector3(2, 0.006, -0.1))
	check(water.emitted_strokes == emitted, "Off-carpet stroke cannot create water")
	prepare()
	soil.extraction_values = soil.water_values.duplicate()
	soil.extraction_coverage_total = soil.water_coverage_total
	step(Vector3(0, 0.067, 0.1), Vector3(0, 0.067, 0))
	check(water.emitted_strokes == 0, "Already extracted carpet cannot emit a full sheet again")
	prepare()
	point = straight(Vector3(0, 0.067, 0.5), Vector3.FORWARD, 12)
	advance(0.10)
	check(water.debug_stats().feeding_sheets == 0, "Stationary input gap stops new emission promptly")
	for i in 50:
		var direction := Vector3.FORWARD if i % 2 == 0 else Vector3.BACK
		water.feed_stroke(point, point + direction * 0.01, 1.0 / 60.0, 40.0)
		water._process(1.0 / 60.0)
	water.set_process(false)
	check(water.debug_stats().active_sheets <= 3, "Frantic zig-zags remain bounded")
	check(water.debug_stats().impact.active_droplets <= 24, "Repeated impacts remain inside droplet budget")
	game.reset_rug()
	check(water.debug_stats().active_sheets == 0 and not water.impact.is_alive(), "Reset clears all pending sheet and splash work")
	check(not water.is_processing(), "Reset leaves no background update")
	# Drive the real screen-space input route as well as deterministic geometry.
	game.hud.show()
	root.size = Vector2i(390, 844)
	game.camera.transform = camera_pose
	await settle()
	prepare()
	point = Vector3(-0.2, 0.067, 0.6)
	game.begin_stroke(game.camera.unproject_position(point), false)
	check(game.brush_dragging and water.emitted_strokes == 0, "Press only places the blade; it does not emit")
	for _frame in 32:
		point.z -= 0.014
		game.stroke_time = Time.get_ticks_msec() - 16
		game.move_brush_to_screen(game.camera.unproject_position(point), false)
		water._process(1.0 / 60.0)
		water.set_process(false)
	check(water.emitted_strokes > 0 and water.debug_stats().impact.active_contacts > 0, "Screen-space drag drives extraction, sheet, and splash")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not game.brush_dragging and water.debug_stats().feeding_sheets == 0, "Focus loss stops emission without losing the airborne tail")
	water.set_process(true)
	await create_timer(1.2).timeout
	check(not water.is_processing() and not water.impact.is_alive(), "Automatic runtime processing drains to idle after release")
	# Source strength responds to supply, and is independent of event frequency.
	for rate in [30.0, 60.0, 120.0]:
		water.reset()
		water.feed_stroke(Vector3.ZERO, Vector3.FORWARD * 0.6 / rate, 1.0 / rate, 0.3 / water.pixel_area / rate)
		check(absf(water.sheets[water.current].power - 0.3 / 0.65) < 0.001, "Area-rate normalization at %d Hz" % int(rate))
	water.reset()
	water.feed_stroke(Vector3.ZERO, Vector3.FORWARD * 0.01, 1.0 / 60.0, 0.03 / water.pixel_area / 60.0)
	water._process(1.0 / 60.0)
	check(water.sheets[water.current].grid[0].w < 0.009, "Nearly dry supply produces a thinner sheet")
	prepare()
	straight(Vector3.ZERO, Vector3.FORWARD, 10)
	game.select_rug(0)
	check(not water.enabled and water.debug_stats().active_sheets == 0, "Changing exercise cancels water immediately")
	check(water.sheets[0].mesh.mesh.get_instance_id() == mesh_id, "All strokes and resets reuse the mesh allocation")
	check(soil.wet_texture.get_instance_id() == wet_id, "Existing wetness texture is reused")
	check(state._capture_state() == saved_state, "Gym leaves paid state unchanged")
	check(FileAccess.get_file_as_bytes(state._save_path) == saved_bytes, "Gym leaves paid save bytes unchanged")
	game.camera.transform = camera_pose
	game.camera.size = camera_size
	print("SQUEEGEE_WATER_VALIDATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
