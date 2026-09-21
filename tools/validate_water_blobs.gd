extends SceneTree
## Run with the renderer: Godot --path CarpetToy --script ../tools/validate_water_blobs.gd -- --shop-test
## GPU image readback is deliberately confined to this validation script.
const Routes = preload("res://scripts/scene_routes.gd")
var checks := 0
var failures := 0
var game: Node
var water: Node
var benchmark_start: Dictionary

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to keep player saves isolated")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Water validation requires the real renderer for persistent field checks")
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

func wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout
	await settle()

func begin_at(point: Vector3) -> void:
	game.begin_stroke(game.camera.unproject_position(point), false)

func move_to(point: Vector3) -> void:
	game.move_brush_to_screen(game.camera.unproject_position(point), false)

func release_mouse() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = game.camera.unproject_position(game.contact_point)
	event.global_position = event.position
	event.pressed = false
	root.push_input(event, true)

func tap(button: Button) -> void:
	for down: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 1
		event.position = button.get_global_rect().get_center()
		event.pressed = down
		root.push_input(event, true)

func image_stats() -> Dictionary:
	var field: Image = water.field_viewport.get_texture().get_image()
	var total := 0.0
	var occupied := 0
	var peak := 0.0
	for y in field.get_height():
		for x in field.get_width():
			var value := field.get_pixel(x, y).r
			total += value
			peak = maxf(peak, value)
			if value > 0.02: occupied += 1
	return {"hash": hash(field.get_data()), "total": total, "occupied": occupied, "peak": peak, "size": field.get_size()}

func blob_components() -> int:
	# The surface shader's .20 isocontour defines connected puddles. Four-way
	# connectivity distinguishes a shared neck from merely adjacent soft halos.
	var field: Image = water.field_viewport.get_texture().get_image()
	var width := field.get_width()
	var height := field.get_height()
	var occupied := PackedByteArray()
	occupied.resize(width * height)
	for y in height:
		for x in width:
			occupied[y * width + x] = 1 if field.get_pixel(x, y).r >= 0.20 else 0
	var components := 0
	for pixel in occupied.size():
		if occupied[pixel] == 0: continue
		var queue: Array[int] = [pixel]
		occupied[pixel] = 0
		var next := 0
		while next < queue.size():
			var point := queue[next]
			next += 1
			for neighbor: int in [point - width, point + width, point - 1, point + 1]:
				if neighbor < 0 or neighbor >= occupied.size() or occupied[neighbor] == 0: continue
				if absi(neighbor % width - point % width) > 1: continue
				occupied[neighbor] = 0
				queue.append(neighbor)
		if queue.size() > 4: components += 1
	return components

func wait_for_idle() -> void:
	for step in 120:
		if not water.is_processing() and int(water.debug_stats().get("pending_stamps", 0)) == 0:
			await settle()
			return
		await create_timer(0.02).timeout
	check(false, "Water settles and stops CPU processing within 2.4 seconds")

func expect_blank(label: String) -> void:
	await settle()
	var pixels := image_stats()
	var stats: Dictionary = water.debug_stats()
	check(float(pixels.total) == 0.0, label + ": persistent density clears completely")
	check(int(stats.active_drops) == 0 and int(stats.pending_stamps) == 0, label + ": no live drops or queued stamps remain")
	check(not water.emitting and not water.is_processing(), label + ": CPU work stops")

func capture(label: String) -> void:
	await settle()
	var output := "res://../art/renders/water_blobs_" + label + ".png"
	check(root.get_texture().get_image().save_png(output) == OK, "Capture " + label)
	print("WATER_CAPTURE ", ProjectSettings.globalize_path(output))

func run() -> void:
	var state: Node = root.get_node("ShopState")
	state.set_process(false)
	state._test_unix_time = 1234567890.0
	state._test_ticks_msec = 0
	state._last_ticks = 0
	check(state.reset_progress(), "Create isolated player progress")
	state.cash = 123
	check(not state.start_job().is_empty(), "Existing paid job is available beside free practice")
	var saved_state: Dictionary = state._capture_state().duplicate(true)
	var saved_bytes := FileAccess.get_file_as_bytes(state._save_path)
	root.size = Vector2i(390, 844)
	game = load(Routes.GYM).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await settle()
	water = game.water
	check(is_instance_valid(water), "Gym owns a water controller")
	check(not water.enabled and not water.emitting, "Dry rug has water disabled")
	check(not water.is_physics_processing(), "Water has no physics callback")
	var controller_id := water.get_instance_id()
	var viewport_id: int = water.field_viewport.get_instance_id()
	var texture_id: int = water.field_viewport.get_texture().get_instance_id()
	var pool_id: int = water.drop_batch.get_instance_id()
	var initial_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	tap(game.hud.control("GymRug2"))
	await settle()
	check(game.selected_rug == 1 and game.selected_tool == 2 and water.enabled, "Rug 2 activates the hose and water field")
	check(not game.wet_recipe and not game.soil.wet_recipe, "Prototype does not enable the production wet-cleaning recipe")
	check(water.field_viewport.size == Vector2i(192, 320), "Density field remains a small fixed 192 x 320 texture")
	check(water.drop_batch.instance_count == 32, "Falling water uses a fixed 32-instance pool")
	await expect_blank("Initial wet rug")
	var original_soil: Dictionary = game.soil.make_snapshot()
	begin_at(Vector3(-0.4, 0.067, -0.6))
	check(game.brush_dragging and water.emitting, "Holding the hose starts water without pointer movement")
	await wait_seconds(0.65)
	var held: Dictionary = water.debug_stats()
	check(int(held.emitted) >= 8 and int(held.emitted) <= 15, "Stationary hose emits at a bounded rate near 16 drops per second")
	check(int(held.landed) > 0 and int(held.active_drops) > 0, "Stationary water both falls and lands")
	var held_field := image_stats()
	check(int(held_field.occupied) > 0 and float(held_field.peak) > 0.05, "Landing drops create visible accumulated density")
	release_mouse()
	check(not water.emitting and not game.brush_dragging, "Mouse release immediately stops births")
	var after_release: int = water.debug_stats().emitted
	await wait_for_idle()
	var settled: Dictionary = water.debug_stats()
	check(int(settled.emitted) == after_release and int(settled.landed) == after_release, "Already-emitted drops finish landing after release")
	check(int(settled.active_drops) == 0 and not bool(settled.processing), "Settled pool consumes no controller process calls")
	var idle_field := image_stats()
	check(blob_components() == 1, "Repeated nearby drops merge into one connected visible blob")
	await wait_seconds(0.30)
	check(image_stats().hash == idle_field.hash, "Idle water does not redraw or grow its density field")
	check(water.debug_stats().field_updates == settled.field_updates, "Idle water submits no field updates")
	check(water.debug_stats().process_count == settled.process_count, "Settled water receives no further CPU callbacks")
	# Returning to the same location deepens/joins the existing field instead
	# of introducing one independently-rendered surface per landed drop.
	begin_at(Vector3(-0.32, 0.067, -0.6))
	await wait_seconds(0.40)
	game.end_stroke()
	await wait_for_idle()
	var overlap_field := image_stats()
	check(float(overlap_field.total) >= float(idle_field.total), "Nearby deposits accumulate in the same density field")
	check(int(overlap_field.occupied) > int(idle_field.occupied), "Overlapping deposits extend a shared water footprint")
	check(blob_components() == 1, "Neighboring deposits keep a continuous above-threshold neck")
	begin_at(Vector3(0.65, 0.067, 1.0))
	await wait_seconds(0.35)
	game.end_stroke()
	await wait_for_idle()
	check(int(image_stats().occupied) > int(overlap_field.occupied), "A distant hold leaves an additional water blob")
	check(blob_components() == 2, "Distant deposits remain two separate blobs until their fields meet")
	check(game.soil.make_snapshot() == original_soil, "Visual water leaves dirt and extraction progress unchanged")
	# Exercise a real moving hose path while recording only prototype counters.
	benchmark_start = water.debug_stats().duplicate(true)
	var benchmark_wall_start := Time.get_ticks_usec()
	var frame_samples: Array[float] = []
	var max_active_drops := 0
	begin_at(Vector3(-0.82, 0.067, 1.35))
	for step in 100:
		var before_frame := Time.get_ticks_usec()
		var t := float(step) / 99.0
		move_to(Vector3(lerpf(-0.82, 0.82, t), 0.067, 0.5 + sin(t * TAU) * 0.95))
		await process_frame
		frame_samples.append(float(Time.get_ticks_usec() - before_frame) / 1000.0)
		max_active_drops = maxi(max_active_drops, int(water.debug_stats().active_drops))
	check(max_active_drops > 0 and max_active_drops <= 32, "Moving hose remains within the fixed pool throughout the benchmark")
	await capture("falling_portrait")
	game.end_stroke()
	await wait_for_idle()
	var benchmark_end: Dictionary = water.debug_stats()
	frame_samples.sort()
	var measured_processes := int(benchmark_end.process_count) - int(benchmark_start.process_count)
	var measured_cpu_usec := int(benchmark_end.cpu_usec_total) - int(benchmark_start.cpu_usec_total)
	print("WATER_DESKTOP_BENCHMARK ", JSON.stringify({"wall_ms": float(Time.get_ticks_usec() - benchmark_wall_start) / 1000.0, "sample_frames": frame_samples.size(), "frame_ms_p50": frame_samples[50], "frame_ms_p95": frame_samples[95], "water_cpu_usec_average": float(measured_cpu_usec) / maxi(1, measured_processes), "water_cpu_usec_total": measured_cpu_usec, "water_process_calls": measured_processes, "start": benchmark_start, "end": benchmark_end, "note": "Desktop full-frame wall timing; includes rendering and frame pacing, not a phone CPU/GPU measurement."}))
	check(int(benchmark_end.emitted) > int(benchmark_start.emitted) and int(benchmark_end.field_updates) > int(benchmark_start.field_updates), "Moving hose emits and paints throughout the benchmark")
	await capture("portrait")
	root.size = Vector2i(844, 390)
	await settle()
	await capture("landscape")
	root.size = Vector2i(390, 844)
	await settle()
	var before_squeegee := image_stats()
	tap(game.hud.control("GymSqueegee"))
	begin_at(Vector3(-0.7, 0.067, 0.0))
	move_to(Vector3(0.7, 0.067, 0.0))
	await wait_seconds(0.20)
	check(not water.emitting, "Squeegee movement never emits hose water")
	game.end_stroke()
	check(image_stats().hash == before_squeegee.hash, "Squeegee leaves prototype water in place for future interaction work")
	tap(game.hud.control("GymHose"))
	begin_at(Vector3.ZERO)
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not water.emitting and not game.brush_dragging, "Losing application focus cancels emission")
	await wait_for_idle()
	begin_at(Vector3.ZERO)
	var hud_motion := InputEventMouseMotion.new()
	hud_motion.position = game.hud.control("GymReset").get_global_rect().get_center()
	hud_motion.global_position = hud_motion.position
	root.push_input(hud_motion, true)
	check(not water.emitting and not game.brush_dragging, "Dragging onto the HUD cancels emission")
	await wait_for_idle()
	var emitted_before_hud: int = water.debug_stats().emitted
	tap(game.hud.control("GymHose"))
	await wait_seconds(0.20)
	check(int(water.debug_stats().emitted) == emitted_before_hud and not water.emitting, "HUD taps do not create hidden water strokes")
	begin_at(Vector3.ZERO)
	await process_frame
	tap(game.hud.control("GymReset"))
	await expect_blank("Reset during emission")
	await wait_seconds(0.60)
	check(float(image_stats().total) == 0.0, "Pre-reset drops never repaint the cleared field")
	begin_at(Vector3.ZERO)
	await wait_seconds(0.08)
	tap(game.hud.control("GymRug1"))
	check(not water.enabled and not water.emitting, "Switching to brush practice disables water mid-fall")
	await expect_blank("Switch to dry rug")
	tap(game.hud.control("GymRug2"))
	await expect_blank("Return to wet rug")
	await wait_seconds(0.60)
	check(float(image_stats().total) == 0.0, "Switching exercises cannot resurrect an old drop")
	# Compatibility packs birth time into per-instance data. Exercise the
	# eight-second wrap without waiting through an artificial long session.
	water.clock_seconds = 7.88
	begin_at(Vector3.ZERO)
	await wait_seconds(0.40)
	check(float(water.clock_seconds) > 8.0 and int(water.debug_stats().emitted) >= 5, "Drops can be emitted across the shader clock wrap")
	check(int(water.debug_stats().landed) > 0 and int(water.debug_stats().active_drops) > 0, "Pre-wrap drops land while post-wrap drops are still falling")
	game.end_stroke()
	await wait_for_idle()
	var wrapped: Dictionary = water.debug_stats()
	check(wrapped.emitted == wrapped.landed and int(wrapped.active_drops) == 0 and water.drop_batch.visible_instance_count == 0, "All drops retire across the clock wrap with no ghost instances")
	var wrapped_field := image_stats()
	await wait_seconds(0.30)
	check(image_stats().hash == wrapped_field.hash and water.debug_stats().process_count == wrapped.process_count, "Wrapped drops leave stable water and stop all CPU callbacks")
	tap(game.hud.control("GymReset"))
	await expect_blank("After clock wrap")
	# A stalled app must not replay several seconds of births in one frame.
	begin_at(Vector3.ZERO)
	water._process(5.0)
	var stalled: Dictionary = water.debug_stats()
	check(int(stalled.emitted) > 0 and int(stalled.emitted) <= 2 and int(stalled.active_drops) <= 32, "A five-second frame cannot create an emission backlog")
	check(float(water.clock_seconds) <= 0.101, "A long frame advances only the capped visual timestep")
	game.end_stroke()
	await wait_for_idle()
	var recovered: Dictionary = water.debug_stats()
	check(recovered.emitted == recovered.landed and int(recovered.pending_stamps) == 0 and not bool(recovered.field_pending), "Bounded drops land and flush cleanly after a long frame")
	check(int(recovered.field_updates) <= int(recovered.landed), "Field updates stay bounded by newly landed drops")
	tap(game.hud.control("GymReset"))
	await expect_blank("Final reset")
	check(water.get_instance_id() == controller_id and water.field_viewport.get_instance_id() == viewport_id and water.field_viewport.get_texture().get_instance_id() == texture_id and water.drop_batch.get_instance_id() == pool_id, "Emission, reset and rug changes reuse all water resources")
	check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) <= initial_nodes + 2, "Depositing many drops creates no growing scene-node population")
	check(state._capture_state() == saved_state, "Water practice preserves paid progress and cash")
	check(FileAccess.get_file_as_bytes(state._save_path) == saved_bytes, "Water practice leaves the saved paid job untouched")
	game.return_to_shop()
	await settle()
	check(current_scene.scene_file_path == Routes.MAIN_MENU, "Water practice exits through the normal home route")
	check(FileAccess.get_file_as_bytes(state._save_path) == saved_bytes, "Leaving water practice preserves the existing save")
	print("WATER_BLOBS_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
