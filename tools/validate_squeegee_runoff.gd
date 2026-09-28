extends "res://../tools/validate_squeegee_trail.gd"
## Independent local drainage, remote-stroke non-renewal and real floor pixels.

func live_exit(left: bool) -> int:
	var count := 0
	# Long world-anchored streams continue draining after the small joining
	# apron disappears; both belong to this exit's local visual lifetime.
	if is_instance_valid(trail.streams):
		for slot in trail.streams.batch.instance_count:
			var packet: Dictionary = trail.streams.packet_debug(slot)
			if packet.active and packet.origin.z > 1.4 and (packet.origin.x < 0 if left else packet.origin.x > 0):
				count += 1
	for index in int(trail.debug_stats().stored_segments):
		var edge: Dictionary = trail.segment_debug(index)
		var mid: Vector3 = (edge.start as Vector3).lerp(edge.end, 0.5)
		if not edge.spill or mid.z < 1.4 or (mid.x >= 0 if left else mid.x <= 0):
			continue
		if trail.sample_segment_visible(index, 0.5, 0.8):
			count += 1
	return count

func floor_pixels(left: bool) -> int:
	water.set_process(false)
	soil._process(0.0)
	await settle()
	var shot: Image = root.get_texture().get_image()
	# Exact top view: wholly beyond the longest tassel, and inside each exit's
	# own half. Do not mistake the other fresh mouth's sideways flare for revival.
	var a: Vector2 = game.camera.unproject_position(Vector3(-0.95 if left else 0.20, 0.006, 1.68))
	var b: Vector2 = game.camera.unproject_position(Vector3(-0.20 if left else 0.95, 0.006, 2.10))
	var lo := Vector2i(a.min(b).floor()).clamp(Vector2i.ZERO, shot.get_size())
	var hi := Vector2i(a.max(b).ceil()).clamp(Vector2i.ZERO, shot.get_size())
	var count := 0
	for y in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			var c := shot.get_pixel(x, y)
			if minf(c.g, c.b) > 0.50 and minf(c.g, c.b) - c.r > 0.16:
				count += 1
	return count

func newest_left_segment() -> int:
	for index in int(trail.debug_stats().stored_segments):
		var edge: Dictionary = trail.segment_debug(index)
		var mid: Vector3 = (edge.start as Vector3).lerp(edge.end, 0.5)
		if edge.spill_start > 0.99 and edge.spill_end > 0.99 and mid.x < -0.1 and mid.z > 1.4:
			return index
	return -1

func run() -> void:
	var state: Node = root.get_node("ShopState")
	state.set_process(false)
	state._test_unix_time = 1234567890.0
	state._test_ticks_msec = 0
	state._last_ticks = 0
	check(state.reset_progress(), "Isolate runoff test save")
	state.cash = 123
	check(not state.start_job().is_empty(), "Preserve an existing paid job")
	var saved: Dictionary = state._capture_state().duplicate(true)
	var saved_bytes := FileAccess.get_file_as_bytes(state._save_path)
	root.size = Vector2i(900, 1000)
	game = load(Routes.GYM).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await settle()
	soil = game.soil
	water = game.squeegee_water
	trail = water.trail
	prepare()
	game.hud.hide()
	game.tool_nodes[1].hide()
	game.camera.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 6, 0.30))
	game.camera.size = 4.35
	var batch_id: int = trail.batch.get_instance_id()
	var mesh_id: int = trail.batch.mesh.get_instance_id()
	var a := Vector3(-0.45, 0.067, 0.9)
	var b := Vector3(-0.45, 0.067, 1.65)
	swipe(a, b)
	check(live_exit(true) > 0, "Fresh water at the left edge creates runoff")
	var initial_pixels: int = await floor_pixels(true)
	check(initial_pixels > 50, "Fresh runoff is actually visible beyond the fringe")
	await capture("drain_fresh")
	var chosen := newest_left_segment()
	check(chosen >= 0, "Fixture includes an entirely spilling edge segment")
	var early := Vector3.ZERO
	if chosen >= 0:
		early = trail.sample_segment(chosen, 0.5, 0.5)
	var wet_bytes: PackedByteArray = soil.wet_mask.get_data()
	var extraction: PackedFloat32Array = soil.extraction_values.duplicate()
	var total_water: PackedFloat32Array = soil.water_values.duplicate()
	var old_builds: int = trail.debug_stats().build_count
	advance(1.0)
	if chosen >= 0:
		var late: Vector3 = trail.sample_segment(chosen, 0.5, 0.5)
		check(late.z > early.z + 0.025, "Draining water flows outward rather than retracting back onto the carpet")
	check(live_exit(true) > 0, "Runoff disappears gradually, not immediately on release")
	check(int(trail.debug_stats().build_count) == old_builds, "Drain animation does not rebuild the contour")
	check(soil.wet_mask.get_data() == wet_bytes and soil.extraction_values == extraction and soil.water_values == total_water, "Draining is visual only and leaves the real masks untouched")
	await capture("drain_moving")

	# Keep the global carpet ridge fully alive by extracting elsewhere. The
	# old left exit must still die on its own local clock.
	swipe(Vector3(0.45, 0.067, -0.9), Vector3(0.45, 0.067, 0.6), 0.4)
	check(float(trail.debug_stats().strength) > 0.99 and trail.is_alive(), "Remote wet cleaning keeps the carpet ridge alive")
	check(live_exit(true) == 0, "Remote extraction cannot preserve or resurrect the old left spill")
	var expired_pixels: int = await floor_pixels(true)
	check(expired_pixels <= 2, "Expired runoff leaves no cyan floor pattern while the carpet ridge remains visible")
	await capture("drain_gone_while_cleaning")

	# A fresh second exit gets its own supply without waking the first one.
	swipe(Vector3(0.45, 0.067, 0.6), Vector3(0.45, 0.067, 1.65))
	check(live_exit(false) > 0 and live_exit(true) == 0, "A new right spill cannot revive the drained left spill")
	var fresh_right: int = await floor_pixels(false)
	var still_gone_left: int = await floor_pixels(true)
	check(fresh_right > 50 and still_gone_left <= 2, "The renderer shows only the freshly funded runoff mouth")
	await capture("drain_independent_exits")
	advance(4.0)
	check(live_exit(false) == 0 and live_exit(true) == 0, "Both floor spills fully retire within the short runoff lifetime")
	trail.notify_extraction(Vector3(-0.45, 0.067, 1.5), 100.0)
	advance(0.2)
	check(live_exit(true) == 0 and live_exit(false) == 0, "A fake notification with unchanged extraction arrays cannot refill runoff")
	# Old water must never reappear when the wave animation clock wraps.
	trail.clock_seconds += 100.0
	trail.advance(0.01)
	check(live_exit(true) == 0 and live_exit(false) == 0, "Animation-clock wrap cannot resurrect expired runoff")
	game.reset_rug()
	check(not trail.is_alive() and int(trail.debug_stats().stored_segments) == 0, "Reset clears local supply clocks and every runoff segment")
	prepare()
	swipe(a, b)
	check(live_exit(true) > 0, "A fresh wet rug starts new runoff after clock reset")
	game._on_practice_tool_pressed(2)
	check(not trail.is_alive(), "Switching to hose cancels active drainage immediately")
	check(trail.batch.get_instance_id() == batch_id and trail.batch.mesh.get_instance_id() == mesh_id, "Drainage reuses the fixed batch and mesh")
	check(state._capture_state() == saved and FileAccess.get_file_as_bytes(state._save_path) == saved_bytes, "Runoff practice preserves paid progress and save bytes")
	print("SQUEEGEE_RUNOFF_PIXELS fresh=%d expired=%d" % [initial_pixels, expired_pixels])
	print("SQUEEGEE_RUNOFF_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
