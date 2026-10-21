extends SceneTree
## Desktop comparison of the companion's incremental cost; not a battery claim.
var game: Node
var companion: Node3D
var results := {}

func _initialize() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Use the graphics renderer and -- --shop-test")
		quit(2)
		return
	run.call_deferred()

func summary(samples: Array[float]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	return {"median_ms": sorted[sorted.size() / 2], "p95_ms": sorted[floori((sorted.size() - 1) * 0.95)]}

func sample(label: String, count := 180, warmup := 90) -> void:
	var process_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var wall_ms: Array[float] = []
	var peak_bodies := 0
	var peak_draws := 0
	var peak_primitives := 0
	for tick in count + warmup:
		var started := Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		if tick < warmup: continue
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		wall_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
		peak_bodies = maxi(peak_bodies, int(companion.debug_stats().simulating_body_count))
		peak_draws = maxi(peak_draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		peak_primitives = maxi(peak_primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	results[label] = {"engine_process": summary(process_ms), "engine_physics": summary(physics_ms), "desktop_frame": summary(wall_ms), "peak_simulating_bodies": peak_bodies, "peak_draw_calls": peak_draws, "peak_triangles": peak_primitives}

func run() -> void:
	var ledger := root.get_node("ShopState")
	ledger._save_path = "res://.godot/companion_profile_%d.json" % OS.get_process_id()
	ledger.reset_progress()
	root.size = Vector2i(390, 844)
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await process_frame
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game.set_physics_process(false)
	game.soil.set_process(false)
	game.soil.set_physics_process(false)
	companion = game.companion
	companion.set_active(false)
	companion.hide()
	await sample("room_without_companion")
	companion.show()
	companion.reset_to_tool()
	companion.set_active(true)
	await sample("seated_companion")
	var seat := Transform3D(game.brush.global_basis.orthonormalized(), game.brush.global_transform * game.COMPANION_SEAT)
	companion.update_tool_transform(seat, 1.0 / 60.0, true)
	for tick in 12:
		seat.origin.x += 0.16
		companion.update_tool_transform(seat, 1.0 / 60.0)
		await physics_frame
	await sample("fall_and_recovery", 360, 15)
	companion.park_at(game.COMPANION_REST_SPOT)
	await sample("parked_companion")
	results["configuration"] = {"engine": Engine.get_version_info().string, "viewport": "390x844", "fps_cap": 60, "note": "Desktop GL Compatibility; same room, frozen soil, real physics. Frame timing includes scheduling. Battery and phone thermals require device testing."}
	var file := FileAccess.open("res://../build/level_companion_profile.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	print("LEVEL_COMPANION_PROFILE ", JSON.stringify(results))
	game.free()
	quit()
