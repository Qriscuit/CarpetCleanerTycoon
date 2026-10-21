extends SceneTree
## Authored casement edges stay attached through opening and closing at every tier.
## Add --window-hinge-capture with the real renderer for closed/half/open previews.
const RoomRules := preload("res://scripts/room_upgrades.gd")
const CameraFit := preload("res://scripts/gym_camera.gd")
const AMOUNTS := [0.0, 0.12, 0.25, 0.50, 0.75, 0.85, 1.0, 0.75, 0.50, 0.25, 0.0]
var game: Node
var ledger: Node
var checks := 0
var failures: Array[String] = []
var capture_mode := false
var save_path := ""

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Window hinge validation requires -- --shop-test")
		quit(2)
		return
	capture_mode = "--window-hinge-capture" in OS.get_cmdline_user_args()
	if capture_mode and DisplayServer.get_name() == "headless":
		push_error("Window hinge captures require the real renderer")
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message): failures.append(message)

func frames() -> void:
	for _frame: int in 3:
		await process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func source_edge(hinge: Node3D) -> Dictionary:
	var stile: MeshInstance3D = hinge.get_node("EditableSource/MovingStile")
	var bounds := stile.mesh.get_aabb()
	var local: Transform3D = hinge.global_transform.affine_inverse() * stile.global_transform
	var bottom := local * Vector3(0, bounds.position.y, 0)
	var top := local * Vector3(0, bounds.end.y, 0)
	# The named side stile straddles the hinge barrel. Its centreline is offset
	# by the authored trim thickness; the pivot runs through x=z=0 inside it.
	bottom.x = 0.0
	bottom.z = 0.0
	top.x = 0.0
	top.z = 0.0
	return {"stile": stile, "bounds": bounds, "bottom": bottom, "top": top, "axis": (hinge.to_global(top) - hinge.to_global(bottom)).normalized(), "bottom_world": hinge.to_global(bottom), "top_world": hinge.to_global(top)}

func validate_leaf(hinge: Node3D, edge: Dictionary, amount: float, tier: int) -> void:
	var label := "Tier%d %s opening%.2f" % [tier, hinge.name, amount]
	for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var point: Vector3 = (edge.bottom as Vector3).lerp(edge.top, fraction)
		var expected: Vector3 = (edge.bottom_world as Vector3).lerp(edge.top_world, fraction)
		check(hinge.to_global(point).distance_to(expected) < 0.00001, label + " fixes the entire hinge line at%.2f" % fraction)
	var stile: MeshInstance3D = edge.stile
	var bounds: AABB = edge.bounds
	for x: float in [bounds.position.x, bounds.end.x]:
		for z: float in [bounds.position.z, bounds.end.z]:
			var bottom := stile.to_global(Vector3(x, bounds.position.y, z))
			var top := stile.to_global(Vector3(x, bounds.end.y, z))
			check((top - bottom).normalized().distance_to(edge.axis) < 0.00001, label + " preserves the real side-edge vertex direction")
	var model: MeshInstance3D = hinge.get_node("BakedModel")
	var closed_basis: Basis = hinge.get_meta("closed_basis")
	var closed_centroid: Vector3 = hinge.global_position + game.room.global_basis * closed_basis * model.mesh.get_aabb().get_center()
	if amount > 0.0:
		check(model.to_global(model.mesh.get_aabb().get_center()).z < closed_centroid.z - 0.0001, label + " swings outward behind the fixed frame")
	var aperture: Dictionary = game.room.window_clear_aperture_world()
	var fit: AABB = game.room.global_transform * game.room.geometry_fit_bounds_local(true)
	var above_ground := true
	var clear_exit := true
	var inside_fit := true
	for surface: int in model.mesh.get_surface_count():
		var vertices: PackedVector3Array = model.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			var point := model.to_global(vertex)
			above_ground = above_ground and point.y >= 0.085
			inside_fit = inside_fit and fit.grow(0.0001).has_point(point)
			if amount == 1.0: clear_exit = clear_exit and absf(point.x) >= float(aperture.width) * 0.5
	check(above_ground, label + " stays above the floor")
	check(inside_fit, label + " fits the complete departure bounds")
	if amount == 1.0: check(clear_exit, label + " clears the full unchanged rug corridor")

func capture(tier: int, label: String) -> void:
	if not capture_mode: return
	var viewport: Vector2 = game.get_viewport().get_visible_rect().size
	var basis := CameraFit.workshop_basis(game.room_view_pitch_from_top, game.room_view_yaw_degrees)
	CameraFit.frame_departure(game.camera, viewport, game.hud._safe_rect().grow(-16.0), 0.0, game._workshop_geometry_bounds(true), game.room_view_pitch_from_top, game.room_view_yaw_degrees)
	check(game.camera.global_basis.is_equal_approx(basis), "The preview retains the production room angle")
	await frames()
	var folder := ProjectSettings.globalize_path("res://../art/renders/window_edge_hinges")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join("tier%d_%s.png" % [tier, label])) == OK, "The requested hinge preview saves")

func run() -> void:
	ledger = root.get_node("ShopState")
	ledger.set_process(false)


	save_path = "res://.godot/window_edge_hinges_%d.json" % OS.get_process_id()
	ledger._save_path = save_path
	check(ledger.reset_progress(), "The hinge test starts in an isolated ledger")
	root.size = Vector2i(591, 1280)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.soil.suspend_simulation(true)
	game.hud.hide()
	await frames()
	for tier: int in 4:
		var levels := {}
		for id: String in RoomRules.IDS: levels[id] = 0 if tier == 0 else RoomRules.visual_milestones(id)[tier - 1]
		game.room.set_levels(levels)
		game.room.set_window_open_amount(0.0)
		var edges := {}
		var originals := {}
		for side: String in ["LeftHinge", "RightHinge"]:
			var hinge: Node3D = game.room.get_node("Window/Tier%d/%s" % [tier, side])
			edges[side] = source_edge(hinge)
			originals[side] = hinge.transform
			check((edges[side].axis as Vector3).distance_to(Vector3.UP) < 0.00001, "Tier%d %s has a world-vertical authored hinge edge" % [tier, side])
		var frame_source: Node3D = game.room.get_node("Window/Tier%d/EditableSource/WindowFrame" % tier)
		check(frame_source.global_basis.y.normalized().distance_to(Vector3.UP) < 0.00001, "Tier%d's fixed frame matches the upright casements" % tier)
		var fixed_frame: MeshInstance3D = game.room.get_node("Window/Tier%d/BakedModel" % tier)
		var frame_pose := fixed_frame.global_transform
		for amount: float in AMOUNTS:
			game.room.set_window_open_amount(amount)
			for side: String in edges: validate_leaf(game.room.get_node("Window/Tier%d/%s" % [tier, side]), edges[side], amount, tier)
			check(fixed_frame.global_transform.is_equal_approx(frame_pose), "The decorative frame never moves while a leaf opens")
		game.room.set_window_open_amount(1.0)
		game.room.reset_completion_motion()
		for side: String in originals:
			check(game.room.get_node("Window/Tier%d/%s" % [tier, side]).transform.is_equal_approx(originals[side]), "Tier%d %s resets to its exact closed authored transform" % [tier, side])
		for amount: float in [0.0, 0.5, 1.0]:
			game.room.set_window_open_amount(amount)
			await capture(tier, "closed" if amount == 0.0 else ("half_open" if amount == 0.5 else "fully_open"))
	game.room.reset_completion_motion()
	game.free()
	current_scene = null
	root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	for index: int in mini(failures.size(), 12): push_error(failures[index])
	print("WINDOW_EDGE_HINGE_VALIDATION %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
