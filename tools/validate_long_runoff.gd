extends "res://../tools/validate_squeegee_runoff.gd"
## Actual extraction → grouped, matte, fast ribbons; bounded resource regression.

func check_camera_escape(streams: Node, slot: int, label: String) -> void:
	var original_size: Vector2i = root.size
	var far_front: Vector3 = streams.sample_packet(slot, 1.0, 0.5)
	for size in [Vector2i(320, 568), Vector2i(568, 320), Vector2i(844, 390), Vector2i(900, 1100)]:
		root.size = size
		await settle()
		for angle in [false, true]:
			game.hud.show()
			game.set_camera_angle(angle)
			water.set_process(false)
			var screen: Vector2 = game.camera.unproject_position(far_front)
			check(not game.camera.get_viewport().get_visible_rect().has_point(screen), "%s flow leaves full viewport %s angled=%s" % [label, size, angle])
	root.size = original_size
	await settle()

func check_packet_bounds(streams: Node, slot: int, label: String) -> void:
	var contained := true
	for u in [0.0, 0.25, 0.5, 0.75, 1.0]:
		for v in [0.0, 0.5, 1.0]:
			var point: Vector3 = streams.sample_packet(slot, u, v)
			contained = contained and point.is_finite() and streams.node.custom_aabb.has_point(point)
	check(contained, label + " curved flow stays within its expanded rendering bounds")

func run() -> void:
	var state: Node = root.get_node("ShopState")
	state.set_process(false)
	state._test_unix_time = 1234567890.0
	state._test_ticks_msec = 0
	state._last_ticks = 0
	check(state.reset_progress(), "Isolate long-flow validation")
	state.cash = 123
	check(not state.start_job().is_empty(), "Preserve an existing paid job")
	var saved: Dictionary = state._capture_state().duplicate(true)
	var saved_bytes := FileAccess.get_file_as_bytes(state._save_path)
	root.size = Vector2i(900, 1100)
	game = load(Routes.GYM).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await settle()
	soil = game.soil
	water = game.squeegee_water
	trail = water.trail
	var streams: Node = trail.streams
	check(is_instance_valid(streams), "Gym owns the dedicated pooled floor-flow renderer")
	var mesh_id: int = streams.batch.mesh.get_instance_id()
	var batch_id: int = streams.batch.get_instance_id()
	check(streams.batch.instance_count == 16, "Long runoff has a fixed sixteen-packet pool")
	check(not streams.is_alive(), "Dry Gym creates no flowing water")
	prepare()
	game.hud.hide()
	game.camera.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 7, 0.7))
	game.camera.size = 5.2
	swipe(Vector3(0, 0.067, 0.85), Vector3(0, 0.067, 1.64), 1.0)
	check(streams.is_alive(), "Real positive extraction at the edge starts long runoff")
	var active := 0
	var chosen := -1
	for slot in streams.batch.instance_count:
		var p: Dictionary = streams.packet_debug(slot)
		if p.active:
			active += 1
			if chosen < 0: chosen = slot
	check(active >= 1 and active <= 4, "One broad exit becomes a few coherent streams, not a fan per tiny contour segment")
	check(chosen >= 0, "Fixture contains a live world-anchored ribbon")
	if chosen < 0:
		quit(1)
		return
	var initial: Dictionary = streams.packet_debug(chosen)
	check(float(initial.width) >= 0.3, "An ordinary blade-wide exit produces substantial broad water")
	var early_front: Vector3 = streams.sample_packet(chosen, 1.0, 0.5)
	var wet_bytes: PackedByteArray = soil.wet_mask.get_data()
	var extraction: PackedFloat32Array = soil.extraction_values.duplicate()
	var rebuilds: int = trail.debug_stats().build_count
	await capture("long_flow_fresh_top")
	advance(0.30)
	var later: Dictionary = streams.packet_debug(chosen)
	var later_front: Vector3 = streams.sample_packet(chosen, 1.0, 0.5)
	check(later.active and (later_front - early_front).dot(initial.direction) > 0.70, "Runoff advances more than seventy centimeters in 0.3 seconds")
	check(float(later.front_distance) > 1.1, "The leading water rapidly travels more than a meter beyond the binding")
	check((later.origin as Vector3).distance_to(initial.origin) < 0.0001, "The source stays anchored while the water travels")
	check(int(trail.debug_stats().build_count) == rebuilds, "Long-flow motion does not rebuild extraction contours")
	check(soil.wet_mask.get_data() == wet_bytes and soil.extraction_values == extraction, "Long flowing water is visual only")
	var tip_width: float = streams.sample_packet(chosen, 1.0, 0.0).distance_to(streams.sample_packet(chosen, 1.0, 1.0))
	var middle_width: float = streams.sample_packet(chosen, 0.5, 0.0).distance_to(streams.sample_packet(chosen, 0.5, 1.0))
	check(middle_width > 0.2 and tip_width < middle_width * 0.3, "Broad ribbon ends round off instead of ending in a square slab")
	var finite_and_bounded := true
	for u in [0.0, 0.25, 0.5, 0.75, 1.0]:
		for v in [0.0, 0.5, 1.0]:
			var point: Vector3 = streams.sample_packet(chosen, u, v)
			finite_and_bounded = finite_and_bounded and point.is_finite() and streams.node.custom_aabb.has_point(point)
	check(finite_and_bounded, "Curved vertices are finite and inside expanded rendering bounds")
	await capture("long_flow_moving_top")
	game.camera.position = Vector3(2.3, 4.4, 5.8)
	game.camera.look_at(Vector3(0, 0.02, 0.65))
	game.camera.size = 5.4
	await capture("long_flow_oblique")
	# A long stream can reach the tile field's edge in wide phone layouts.
	# Inspect its support transition onto the lower backing floor as well.
	advance(maxf(0.0, 1.42 - float(streams.packet_debug(chosen).age)))
	game.camera.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 6, 7.67))
	game.camera.size = 2.9
	await capture("long_flow_tile_transition")
	var outer_floor: Image = root.get_texture().get_image()
	var continuous := true
	for z in [7.52, 7.57, 7.62, 7.67, 7.72, 7.77]:
		var water_pixels := 0
		for x in [-0.18, -0.12, -0.06, 0.0, 0.06, 0.12, 0.18]:
			var screen: Vector2 = game.camera.unproject_position(Vector3(x, 0.006, z))
			var pixel := Vector2i(screen.round()).clamp(Vector2i.ZERO, outer_floor.get_size() - Vector2i.ONE)
			var color := outer_floor.get_pixelv(pixel)
			if minf(color.g, color.b) > 0.50 and minf(color.g, color.b) - color.r > 0.16:
				water_pixels += 1
		continuous = continuous and water_pixels >= 5
	check(continuous, "Long water stays visibly continuous across the tile-to-backing floor boundary")

	# Normal game cameras must allow the outgoing flow to cross their edges;
	# the stream must not be cut short merely because its source is offscreen.
	advance(maxf(0.0, float(streams.packet_debug(chosen).lifetime) - 0.2 - float(streams.packet_debug(chosen).age)))
	check(streams.packet_debug(chosen).active, "Long stream remains alive as it travels out of view")
	await check_camera_escape(streams, chosen, "+Z")
	check_packet_bounds(streams, chosen, "Late-life +Z")
	print("LONG_RUNOFF_STREAMS ", streams.debug_stats())
	game.hud.hide()
	game.camera.position = Vector3(2.3, 4.4, 5.8)
	game.camera.look_at(Vector3(0, 0.02, 0.65))
	game.camera.size = 5.4
	await capture("long_flow_departing")
	advance(3.0)
	check(not streams.is_alive(), "Long water fully vanishes without a permanent floor pattern")
	check(trail.is_alive(), "Carpet ridges retain their independent longer lifetime")
	await capture("long_flow_gone")
	# A dry notification and an unrelated fresh central stroke cannot refill it.
	trail.notify_extraction(Vector3(0, 0.067, 1.5), 100.0)
	advance(0.2)
	check(not streams.is_alive(), "Unchanged extraction cannot emit new flow packets")
	swipe(Vector3(0.55, 0.067, -1.0), Vector3(0.55, 0.067, -0.5))
	check(not streams.is_alive(), "Remote fresh cleaning does not revive the old exit")
	# All four edge directions, including phone landscape/portrait framing.
	for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD]:
		prepare()
		var boundary := 1.0 if absf(direction.x) > 0.5 else 1.5
		swipe(direction * (boundary - 0.5) + Vector3.UP * 0.067, direction * (boundary + 0.15) + Vector3.UP * 0.067, 1.0)
		var edge_slot := -1
		for slot in streams.batch.instance_count:
			if streams.packet_debug(slot).active:
				edge_slot = slot
				break
		check(edge_slot >= 0, "Real %s edge stroke creates a stream" % direction)
		if edge_slot >= 0:
			advance(maxf(0.0, float(streams.packet_debug(edge_slot).lifetime) - 0.2 - float(streams.packet_debug(edge_slot).age)))
			await check_camera_escape(streams, edge_slot, str(direction))
			check_packet_bounds(streams, edge_slot, "Late-life " + str(direction))
	prepare()
	swipe(Vector3(0.85, 0.067, 1.15), Vector3(1.10, 0.067, 1.52), 0.65)
	check(streams.is_alive(), "Rounded-corner exits also launch a coherent stream")
	game._on_practice_tool_pressed(2)
	check(not streams.is_alive() and not trail.is_alive(), "Hose/reset cancels every long-flow packet")
	check(streams.batch.mesh.get_instance_id() == mesh_id and streams.batch.get_instance_id() == batch_id, "All strokes and resets reuse the fixed flow mesh and batch")
	check(state._capture_state() == saved and FileAccess.get_file_as_bytes(state._save_path) == saved_bytes, "Long-runoff practice preserves paid progress and save bytes")
	print("LONG_RUNOFF_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
