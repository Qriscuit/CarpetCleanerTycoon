extends SceneTree
## Run through tools/run_godot.ps1 with -- --shop-test.
const Routes = preload("res://scripts/scene_routes.gd")
const CameraFit = preload("res://scripts/gym_camera.gd")
var checks := 0
var failures := 0
var game: Node
var room_points := PackedVector3Array()

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to protect the player's save")
		quit(2)
		return
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func visual_lift() -> float:
	var tip: Vector3 = game.brush.position + game.brush.basis * game.TOOL_PIVOTS[0]
	return tip.y - game.contact_point.y

func settle_lift() -> void:
	await create_timer(0.23).timeout

func mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	event.global_position = point
	root.push_input(event, true)

func touch(point: Vector2, pressed: bool, canceled := false, index := 3) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	event.position = point
	root.push_input(event, true)

func collect_room_geometry(node: Node3D) -> void:
	# Inspect the rendered models of every earned tier, including the fixed
	# architecture. Hidden editable construction meshes do not render twice.
	if node.name == "EditableSource" or node.name == "UpgradeSelectionRing" or node.get_script() == preload("res://scripts/room_upgrade_effect.gd"):
		return
	if node is MeshInstance3D and node.mesh != null:
		for surface: int in node.mesh.get_surface_count():
			var vertices: PackedVector3Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				room_points.append(node.to_global(vertex))
	for child: Node in node.get_children():
		if child is Node3D: collect_room_geometry(child)

func room_geometry_fits(viewport: Rect2) -> bool:
	if room_points.is_empty(): return false
	for point: Vector3 in room_points:
		if not viewport.has_point(game.camera.unproject_position(point)): return false
	return true

func run() -> void:
	var state := root.get_node("ShopState")
	state._save_path = "res://.godot/brush_lift_test_%d.json" % OS.get_process_id()
	check(state.reset_progress(), "Isolated ledger resets")
	root.size = Vector2i(720, 1000)
	game = load(Routes.CLEANING).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	# Drain initial native pointer events and the HUD's deferred camera fit
	# before injecting a stationary press into the visible test window.
	for _frame: int in 3:
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
	collect_room_geometry(game.room)
	check(game.rug_phase == game.RugPhase.CLEANING, "Workshop reaches cleaning")
	check(is_equal_approx(visual_lift(), game.BRUSH_IDLE_LIFT), "Idle brush visibly hovers above its contact point")
	var start: Vector2 = game.camera.unproject_position(Vector3(0.0, game.CARPET_PLANE_Y, -0.25))
	var before: float = game.soil.surface_coverage_total
	mouse_button(start, true)
	check(game.brush_dragging, "Mouse press starts a stroke")
	await settle_lift()
	check(is_zero_approx(visual_lift()), "Holding the pointer lowers the brush to the carpet")
	check(is_equal_approx(before, game.soil.surface_coverage_total), "Lowering without motion does not clean a sweep")
	check(is_equal_approx(game.contact_point.y, game.CARPET_PLANE_Y), "Visual lowering never moves the actual contact plane")
	var motion := InputEventMouseMotion.new()
	motion.position = game.camera.unproject_position(Vector3(0.1, game.CARPET_PLANE_Y, 0.65))
	root.push_input(motion, true)
	check(game.soil.surface_coverage_total < before, "Held brush movement cleans the carpet")
	mouse_button(motion.position, false)
	await settle_lift()
	check(not game.brush_dragging and is_equal_approx(visual_lift(), game.BRUSH_IDLE_LIFT), "Mouse release lifts the brush")
	before = game.soil.surface_coverage_total
	motion.position = start
	root.push_input(motion, true)
	check(is_equal_approx(before, game.soil.surface_coverage_total), "Pointer motion after release does not clean")

	var finger: Vector2 = start - game.TOUCH_CONTACT_OFFSET
	touch(finger, true)
	await settle_lift()
	check(game.active_touch == 3 and is_zero_approx(visual_lift()), "Real touch lowers the brush")
	touch(finger, false, true)
	await settle_lift()
	check(not game.brush_dragging and is_equal_approx(visual_lift(), game.BRUSH_IDLE_LIFT), "Canceled touch lifts the brush")

	touch(finger, true)
	await settle_lift()
	touch(finger + Vector2(30, 0), true, false, 4)
	await settle_lift()
	check(not game.brush_dragging and is_equal_approx(visual_lift(), game.BRUSH_IDLE_LIFT), "A second finger cancels contact and lifts")
	touch(finger, false)
	touch(finger, false, false, 4)

	mouse_button(start, true)
	await settle_lift()
	game.hud.open_upgrades()
	await settle_lift()
	check(not game.brush_dragging and is_equal_approx(visual_lift(), game.BRUSH_IDLE_LIFT), "Opening a modal lifts the brush")
	game.hud.close_upgrades()
	mouse_button(start, true)
	await settle_lift()
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await settle_lift()
	check(not game.brush_dragging and is_equal_approx(visual_lift(), game.BRUSH_IDLE_LIFT), "Focus loss leaves no held brush")

	# Projection checks run with the app active after the focus-loss assertion.
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)

	for window_size: Vector2i in [Vector2i(390, 844), Vector2i(720, 1000), Vector2i(844, 390)]:
		root.size = window_size
		await process_frame
		await process_frame
		game.frame_carpet()
		var expected_basis := CameraFit.workshop_basis(game.room_view_pitch_from_top, game.room_view_yaw_degrees)
		check(game.camera.global_basis.is_equal_approx(expected_basis), "Production camera retains its authored room angle at %s" % window_size)
		var viewport: Rect2 = root.get_visible_rect().grow(1.0)
		check(room_geometry_fits(viewport), "Every authored room upgrade tier fits at %s" % window_size)
		var projected: Vector2 = game.camera.unproject_position(Vector3(0.6, game.CARPET_PLANE_Y, -0.7))
		game.move_brush_to_screen(projected, false)
		check(Vector2(game.contact_point.x - 0.6, game.contact_point.z + 0.7).length() < 0.001, "Tilted projection preserves brush coordinates at %s" % window_size)

	game.on_vacuum_started()
	check(not game.brush.visible and not game.brush_dragging and is_equal_approx(game.brush_visual_lift, game.BRUSH_IDLE_LIFT), "Completion retires a lifted, released brush")
	game.free()
	root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("BRUSH LIFT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
