extends SceneTree
## Real renderer + mouse/touch camera and rotating-tool integration checks.
const Routes := preload("res://scripts/scene_routes.gd")
var checks := 0
var failures := 0
var game: Node
var water: Node

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Use the renderer with -- --shop-test")
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

func prepare() -> void:
	game.select_rug(1)
	game.soil.apply_water_blob(Vector3.ZERO, 5.0)
	game.update_contract_status()
	game.select_tool(1)
	water.set_process(false)

func capture(label: String) -> void:
	water.set_process(false)
	game.soil._process(0.0)
	await settle()
	var path := "res://../art/renders/squeegee_controls_" + label + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "Capture " + label)
	print("SQUEEGEE_CONTROLS_CAPTURE ", ProjectSettings.globalize_path(path))

func tap_camera(touch: bool) -> void:
	var button: Button = game.hud.control("GymCameraAngle")
	var point := button.get_global_rect().get_center()
	for down in [true, false]:
		if touch:
			var event := InputEventScreenTouch.new()
			event.index = 2
			event.position = point
			event.pressed = down
			root.push_input(event, true)
		else:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = point
			event.global_position = point
			event.pressed = down
			root.push_input(event, true)

func screen_at(point: Vector3, touch: bool) -> Vector2:
	return game.camera.unproject_position(point) - (game.TOUCH_CONTACT_OFFSET if touch else Vector2.ZERO)

func drag(start: Vector3, direction: Vector3, touch: bool, frames := 36, speed := 0.70) -> Vector3:
	var point := start
	if touch:
		var event := InputEventScreenTouch.new()
		event.index = 1
		event.pressed = true
		event.position = screen_at(point, true)
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		event.position = screen_at(point, false)
		root.push_input(event, true)
	check(game.brush_dragging, "Press begins %s drag" % ("touch" if touch else "mouse"))
	for _frame in frames:
		point += direction * speed / 60.0
		game.stroke_time = Time.get_ticks_msec() - 16
		if touch:
			var event := InputEventScreenDrag.new()
			event.index = 1
			event.position = screen_at(point, true)
			root.push_input(event, true)
		else:
			var event := InputEventMouseMotion.new()
			event.button_mask = MOUSE_BUTTON_MASK_LEFT
			event.position = screen_at(point, false)
			root.push_input(event, true)
		water._process(1.0 / 60.0)
		water.set_process(false)
	check(Vector2(game.contact_point.x - point.x, game.contact_point.z - point.z).length() < 0.002, "Ground projection preserves drag location")
	check((-game.tool_nodes[1].global_basis.z.normalized()).dot(direction) > 0.995, "Blade front faces drag intent")
	var model: MeshInstance3D = game.tool_nodes[1].get_node("squeegee")
	check(model.global_basis.z.normalized().dot(direction) > 0.995, "Authored blade front faces drag intent after the art-only half-turn")
	check(model.global_basis.y.normalized().dot(Vector3.UP) > 0.999, "Model flip keeps the handle upright")
	check((model.global_transform * game.TOOL_PIVOTS[1]).distance_to(game.contact_point) < 0.0001, "Art flip preserves the exact blade contact pivot")
	check(game.squeegee_motion.heading.dot(water.heading) > 0.999, "Four-edge splash follows the blade's local orientation")
	check(water.debug_stats().active_splashes == 1 and water.debug_stats().active_edges == 4 and water.debug_stats().active_sheets == 0, "Drag renders four perimeter edges and no airborne sheet")
	check(game.soil.extraction_clearance() > 0.0, "Drag extracts real water")
	return point

func check_layout(label: String) -> void:
	var safe: Rect2 = game.hud._safe_rect()
	var button: Control = game.hud.control("GymCameraAngle")
	check(safe.grow(1).encloses(button.get_global_rect()), "Camera button fits " + label)
	check(not button.get_global_rect().intersects(game.hud.control("CleaningProgress").get_global_rect()), "Camera button clears progress " + label)
	check(not button.get_global_rect().intersects(game.hud.control("GymPracticePanel").get_global_rect()), "Camera button clears practice panel " + label)
	check(game.hud.blocks_point(button.get_global_rect().get_center()), "Camera button blocks painting " + label)
	var view: Rect2 = game.hud.rug_view_rect()
	for x in [-1.0, 1.0]:
		for z in [-1.66, 1.66]:
			check(view.grow(1).has_point(game.camera.unproject_position(Vector3(x, 0.067, z))), "Rug corner stays in play area " + label)
	check(game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Both camera angles remain orthographic " + label)

func run() -> void:
	var state: Node = root.get_node("ShopState")
	state.set_process(false)
	state._test_unix_time = 1234567890.0
	state._test_ticks_msec = 0
	state._last_ticks = 0
	check(state.reset_progress(), "Isolated test progress")
	state.cash = 123
	check(not state.start_job().is_empty(), "Existing paid job")
	var saved_state: Dictionary = state._capture_state().duplicate(true)
	var saved_bytes := FileAccess.get_file_as_bytes(state._save_path)
	root.size = Vector2i(390, 844)
	game = load(Routes.GYM).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await settle()
	water = game.squeegee_water
	var authored_blade: MeshInstance3D = game.tool_nodes[1].get_node("squeegee")
	check(authored_blade.basis.is_equal_approx(Basis(Vector3.UP, PI)), "Squeegee model has an authored 180-degree front/back correction")
	check(not game.camera_oblique, "Gym starts in familiar top view")
	prepare()
	check_layout("top portrait")
	tap_camera(false)
	await settle()
	check(game.camera_oblique and not game.overhead, "Mouse button switches to oblique view")
	check_layout("angle portrait")
	await capture("angled_portrait")
	drag(Vector3(-0.45, 0.067, 0.25), Vector3.RIGHT, false)
	var source: Vector3 = water.contact_position
	check(source.distance_to(game.contact_point) < 0.001, "Perimeter is centered on the head, not offset into the old front jet")
	check(absf(source.y - game.contact_point.y) < 0.001, "Rim uses actual blade contact height")
	await capture("rightward_oblique")
	var total: float = game.soil.extraction_coverage_total
	tap_camera(true)
	await settle()
	check(not game.camera_oblique and not game.brush_dragging, "Touch camera button safely ends current drag")
	check(game.soil.extraction_coverage_total == total, "Camera change cannot paint a connecting stroke")
	prepare()
	drag(Vector3(0.10, 0.067, 0.40), Vector3(-0.6, 0, -0.8), true)
	await capture("diagonal_top")
	game.end_stroke()
	game.set_camera_angle(true)
	prepare()
	drag(Vector3(0.2, 0.067, 0.5), Vector3.FORWARD, true)
	await capture("forward_oblique")
	# Direction noise must not create multiple streams or rotate the blade wildly.
	var point: Vector3 = game.contact_point
	var peak_jitter := 0.0
	for frame in 90:
		var next := point + Vector3(0.002 if frame % 2 == 0 else -0.002, 0, -0.004)
		game.apply_selected_tool_stroke(point, next, 1.0 / 60.0)
		game.contact_point = next
		game.place_selected_tool()
		water._process(1.0 / 60.0)
		water.set_process(false)
		peak_jitter = maxf(peak_jitter, absf(game.squeegee_motion.heading.signed_angle_to(Vector3.FORWARD, Vector3.UP)))
		point = next
	check(peak_jitter < deg_to_rad(12.0), "Small alternating finger jitter keeps a stable heading")
	check(water.debug_stats().active_splashes == 1 and water.debug_stats().active_sheets == 0, "Jitter never creates a water column or extra splash mesh")
	# A sharp reversal turns predictably, with no sideways inherited velocity.
	var largest_turn := 0.0
	for _frame in 30:
		var previous_heading: Vector3 = game.squeegee_motion.heading
		var next := point + Vector3.BACK * 0.008
		game.apply_selected_tool_stroke(point, next, 1.0 / 60.0)
		game.contact_point = next
		game.place_selected_tool()
		water._process(1.0 / 60.0)
		water.set_process(false)
		largest_turn = maxf(largest_turn, previous_heading.angle_to(game.squeegee_motion.heading))
		point = next
	check(largest_turn <= 14.0 / 60.0 + 0.001, "Reversal respects the bounded turning rate")
	check(game.squeegee_motion.heading.dot(Vector3.BACK) > 0.995, "Squeegee completes the intended reversal")
	check(water.heading.dot(game.squeegee_motion.heading) > 0.999, "Perimeter keeps the correct local axes on reversal")
	check(water.debug_stats().active_splashes == 1 and water.debug_stats().active_edges == 4, "All four edges remain active through turns")
	await capture("turned_oblique")
	game.end_stroke()
	# Many subthreshold movements must accumulate into relaxed, slow strokes.
	prepare()
	point = Vector3(0.2, 0.067, 0.30)
	game.begin_stroke(screen_at(point, false), false)
	for _frame in 80:
		point.z -= 0.1 / 60.0
		game.stroke_time = mini(game.stroke_time, Time.get_ticks_msec() - 16)
		game.move_brush_to_screen(screen_at(point, false), false)
		water._process(1.0 / 60.0)
		water.set_process(false)
	check(water.emitted_strokes >= 20 and game.soil.extraction_clearance() > 0, "Slow 0.1m/s finger movement still turns, extracts and emits")
	game.end_stroke()
	# Broad blade supported by the rug while its source center crosses the edge.
	prepare()
	drag(Vector3(1.06, 0.067, 0.45), Vector3.FORWARD, false, 30, 0.5)
	check(absf(game.contact_point.y - 0.067) < 0.001, "Wide blade remains supported near the side edge")
	check(absf(water.contact_position.y - 0.067) < 0.001, "Outside midpoint does not put source below the blade")
	game.end_stroke()
	for size in [Vector2i(320, 568), Vector2i(568, 320), Vector2i(844, 390), Vector2i(1100, 820)]:
		root.size = size
		await settle()
		for angle in [false, true]:
			game.set_camera_angle(angle)
			check_layout("%s angle=%s" % [size, angle])
		await capture("angle_%dx%d" % [size.x, size.y])
	check(state._capture_state() == saved_state, "Camera and steering preserve paid state")
	check(FileAccess.get_file_as_bytes(state._save_path) == saved_bytes, "Camera and steering preserve paid save")
	print("SQUEEGEE_CONTROLS_VALIDATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
