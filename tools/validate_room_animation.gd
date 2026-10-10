extends SceneTree
## Isolated geometry and foliage checks for the completion animation assets.
var failures: Array[String] = []
const RoomRules := preload("res://scripts/room_upgrades.gd")

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test for isolated validation")
		quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	var room: Node3D = load("res://scenes/room/upgrade_room.tscn").instantiate()
	room.scale = Vector3(0.9, 1, 0.9)
	root.add_child(room)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.8
	camera.position = Vector3(0, 10, 1.76)
	root.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	await process_frame
	var aperture: Dictionary = room.window_clear_aperture_world()
	_expect(aperture.width >= 2.25, "Opening includes clearance around the two-metre rug")
	_expect(aperture.bottom <= 0.13 and aperture.top >= 1.03, "Opening clears the lifted rolled rug vertically")
	var open_bounds := AABB()
	var have_bounds := false
	var closest_leaf_x := INF
	for tier: int in range(4):
		var purchase_level: int = 0 if tier == 0 else RoomRules.visual_milestones("floor")[tier - 1]
		var levels := {}
		for category: String in RoomRules.IDS: levels[category] = purchase_level
		room.set_levels(levels)
		var surfaces := _visible_surface_count(room)
		# The original four categories budget48 batches; authored walls add at
		# most ten. Exercise the real five-category room at every earned tier.
		_expect(surfaces <= 58, "Animated five-category room remains within58 visible material batches")
		print("Animated room tier %d: %d visible material batches" % [tier, surfaces])
		var fixed_pots: MeshInstance3D = room.get_node("Plants/Tier%d/BakedModel" % tier)
		var pots_transform := fixed_pots.global_transform
		for amount: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			room.set_window_open_amount(amount)
			for side: String in ["LeftHinge", "RightHinge"]:
				var model: MeshInstance3D = room.get_node("Window/Tier%d/%s/BakedModel" % [tier, side])
				for surface: int in model.mesh.get_surface_count():
					var vertices: PackedVector3Array = model.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					for vertex: Vector3 in vertices:
						var point := model.to_global(vertex)
						_expect(point.y >= 0.085, "Opening leaf never sinks through the ground")
						if amount == 1.0:
							closest_leaf_x = minf(closest_leaf_x, absf(point.x))
							_expect(absf(point.x) >= aperture.width * 0.5, "Open leaf stays outside conservative rug corridor")
							if not have_bounds:
								open_bounds = AABB(point, Vector3.ZERO)
								have_bounds = true
							else:
								open_bounds = open_bounds.expand(point)
		room.start_completion_breeze()
		room._process(0.6)
		_expect(room.breeze_strength > 0.4, "Completion gives a gentle, visible initial gust")
		var paused_time: float = room.breeze_time
		room.set_completion_paused(true)
		room._process(2.0)
		_expect(is_equal_approx(room.breeze_time, paused_time), "Focus loss freezes breeze phase")
		room.set_completion_paused(false)
		if DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
		_expect(fixed_pots.global_transform == pots_transform, "Plant pots remain fixed during foliage bending")
		if tier > 0:
			var foliage: MeshInstance3D = room.get_node("Plants/Tier%d/Foliage/BakedModel" % tier)
			for surface: int in foliage.mesh.get_surface_count():
				var material := foliage.mesh.surface_get_material(surface) as ShaderMaterial
				_expect(material != null, "Living foliage has a flexible shader")
				if material != null:
					_expect(is_equal_approx(material.get_shader_parameter("breeze_strength"), room.breeze_strength), "Every living surface receives the breeze")
		room.clear_selection()
		_expect(room.is_processing(), "Clearing selection does not cancel the breeze")
		room._process(4.0)
		_expect(is_zero_approx(room.breeze_strength) and not room.is_processing(), "Breeze settles and disables idle processing")
		room.set_selected("window")
		room.start_completion_breeze()
		room.reset_completion_motion()
		_expect(is_zero_approx(room.window_open_amount) and is_zero_approx(room.breeze_strength), "Reset restores closed windows and still foliage")
		_expect(room.is_processing(), "Completion reset preserves active selection pulsing")
		room.clear_selection()
	print("Fully open leaf world bounds: ", open_bounds)
	print("Open leaf minimum absolute world x: ", closest_leaf_x)
	print("Conservative exit corridor: ", aperture)
	room.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: all four casement tiers clear the rug, stay above ground, reset cleanly; foliage bends and settles with stationary pots")
	else:
		for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)

func _visible_surface_count(node: Node3D) -> int:
	if not node.visible:
		return 0
	var surfaces := 0
	if node is MeshInstance3D and node.mesh != null:
		surfaces = node.mesh.get_surface_count()
	for child: Node3D in node.get_children():
		surfaces += _visible_surface_count(child)
	return surfaces
