extends SceneTree
## Geometry-based camera fit checks; always uses an isolated workshop save.
const CameraFit = preload("res://scripts/gym_camera.gd")
var points := PackedVector3Array()
var checks := 0
var failures := 0

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to protect the player's save")
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func collect(node: Node3D) -> void:
	if node.name == "EditableSource" or node.name == "UpgradeSelectionRing" or node.get_script() == preload("res://scripts/room_upgrade_effect.gd"):
		return
	if node is MeshInstance3D and node.mesh != null:
		for surface: int in node.mesh.get_surface_count():
			var vertices: PackedVector3Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				points.append(node.to_global(vertex))
	for child: Node in node.get_children():
		if child is Node3D:
			collect(child)

func capture(label: String) -> void:
	if "--diorama-capture" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../art/renders")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join("diorama_no_footer_" + label + ".png")) == OK, "Camera preview saves for " + label)

func run() -> void:
	var state := root.get_node("ShopState")
	state._save_path = "res://.godot/diorama_camera_test_%d.json" % OS.get_process_id()
	check(state.reset_progress(), "Isolated camera ledger resets")
	root.size = Vector2i(720, 1000)
	var game: Node = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await process_frame
	check(game.hud.get_node_or_null("%PayoutCard") == null, "The cleaning HUD has no earnings footer")
	collect(game.room)
	var basis: Basis = CameraFit.workshop_basis(game.room_view_pitch_from_top, game.room_view_yaw_degrees)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var world := AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		var local := point - CameraFit.RUG_CENTER
		var projected := Vector2(basis.x.dot(local), basis.y.dot(local))
		low = low.min(projected)
		high = high.max(projected)
		world = world.expand(point)
	print("CLOSED ROOM: world=", world, "; projected=", Rect2(low, high - low))
	var cases := [
		{"size": Vector2i(320, 568), "insets": Vector4.ZERO, "label": "small_phone"},
		{"size": Vector2i(320, 568), "insets": Vector4(0, 24, 0, 20), "label": "small_phone_safe"},
		{"size": Vector2i(390, 844), "insets": Vector4(0, 44, 0, 34), "label": "tall_phone_safe"},
		{"size": Vector2i(540, 750), "insets": Vector4.ZERO, "label": "portrait"},
		{"size": Vector2i(720, 1000), "insets": Vector4.ZERO, "label": "large_portrait"},
		{"size": Vector2i(844, 390), "insets": Vector4.ZERO, "label": "landscape"},
		{"size": Vector2i(844, 390), "insets": Vector4(44, 0, 34, 20), "label": "landscape_safe"},
	]
	for example: Dictionary in cases:
		var viewport_size: Vector2i = example.size
		var label: String = example.label
		root.size = viewport_size
		game.hud.preview_safe_insets = example.insets
		await process_frame
		await process_frame
		game.finish_button.hide()
		game.frame_carpet()
		var cleaning_transform: Transform3D = game.camera.global_transform
		var cleaning_size: float = game.camera.size
		game.finish_button.show()
		game.frame_carpet()
		check(game.camera.global_transform.is_equal_approx(cleaning_transform) and is_equal_approx(game.camera.size, cleaning_size), "Finish appearing does not move the camera in " + label)
		var viewport: Rect2 = game.hud._safe_rect().grow(0.5)
		var all_visible := true
		for point: Vector3 in points:
			all_visible = all_visible and viewport.has_point(game.camera.unproject_position(point))
		check(all_visible, "Every authored upgrade tier fits inside safe screen edges in " + label)
		check(game.camera.global_basis.is_equal_approx(basis), "The configured room pitch and yaw preserve room depth in " + label)
		var rug_screen := Rect2(game.camera.unproject_position(Vector3(-1.06, game.CARPET_PLANE_Y, -1.72)), Vector2.ZERO)
		for x: float in [-1.06, 1.06]:
			for z: float in [-1.72, 1.72]:
				rug_screen = rug_screen.expand(game.camera.unproject_position(Vector3(x, game.CARPET_PLANE_Y, z)))
		check(not game.finish_button.get_global_rect().grow(4.0).intersects(rug_screen), "Finish button never overlaps the playable rug in " + label)
		check(viewport.encloses(game.finish_button.get_global_rect()), "Finish remains inside the safe screen in " + label)
		for z: float in [-1.66, 1.66]:
			var fringe: Vector2 = game.camera.unproject_position(Vector3(0.0, game.CARPET_PLANE_Y, z))
			check(viewport.has_point(fringe), "Full rug fringe fits " + label)
			check(not game.finish_button.get_global_rect().grow(4.0).has_point(fringe), "Finish button clears the rug fringe " + label)
		print("CAMERA %s: size=%.4f; rug=%s; Finish=%s" % [label, game.camera.size, rug_screen, game.finish_button.get_global_rect()])
		game.finish_button.hide()
		game.hud._layout()
		await capture(label)
	game.free()
	current_scene = null
	root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("DIORAMA CAMERA: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
