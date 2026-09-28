extends SceneTree
## Repeatable CPU/desktop-frame measurements, never a phone FPS guarantee.
var results: Dictionary = {}
var game: Node

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Run with the graphics renderer and -- --shop-test")
		quit(2)
		return
	call_deferred("run")

func frames(count: int = 2) -> void:
	for _frame in count:
		await process_frame
		await RenderingServer.frame_post_draw

func timed_summary(samples: Array[float]) -> Dictionary:
	var ordered := samples.duplicate()
	ordered.sort()
	return {"median_ms": ordered[ordered.size() / 2], "p95_ms": ordered[mini(ordered.size() - 1, floori(ordered.size() * 0.95))], "max_ms": ordered.back()}

func stop_effect_processing() -> void:
	game.soil.set_process(false)
	game.water.set_process(false)
	game.squeegee_water.set_process(false)

func run() -> void:
	var state := root.get_node("ShopState")
	state.set_process(false)
	state._test_ticks_msec = 0
	state._test_unix_time = 1000000.0
	root.size = Vector2i(390, 844)
	var started := Time.get_ticks_usec()
	var scene: PackedScene = load("res://scenes/test/rug_cleaning_gym.tscn")
	results.scene_resource_load_ms = (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	game = scene.instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	results.scene_setup_ms = (Time.get_ticks_usec() - started) / 1000.0
	await frames(5)
	started = Time.get_ticks_usec()
	game.select_rug(1)
	results.select_wet_rug_ms = (Time.get_ticks_usec() - started) / 1000.0
	await frames(3)
	started = Time.get_ticks_usec()
	game._on_practice_tool_pressed(1)
	results.equip_squeegee_ms = (Time.get_ticks_usec() - started) / 1000.0
	await frames(3)
	stop_effect_processing()
	var strokes: Array[float] = []
	var effects: Array[float] = []
	var uploads: Array[float] = []
	var frame_times: Array[float] = []
	var last := Vector3(-0.55, 0.067, -1.45)
	for index in 120:
		var progress := float(index + 1) / 120.0
		var next := Vector3(-0.55 + sin(progress * TAU * 1.25) * 0.38, 0.067, -1.45 + progress * 3.1)
		var frame_start := Time.get_ticks_usec()
		started = frame_start
		game.apply_selected_tool_stroke(last, next, 1.0 / 60.0)
		strokes.append((Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		game.squeegee_water._process(1.0 / 60.0)
		effects.append((Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		game.soil._process(0.0)
		uploads.append((Time.get_ticks_usec() - started) / 1000.0)
		stop_effect_processing()
		await frames(1)
		frame_times.append((Time.get_ticks_usec() - frame_start) / 1000.0)
		last = next
	results.first_stroke_ms = strokes[0]
	results.first_effect_update_ms = effects[0]
	results.first_draw_frame_ms = frame_times[0]
	results.stroke_cpu = timed_summary(strokes)
	results.effect_cpu = timed_summary(effects)
	results.mask_upload_cpu = timed_summary(uploads)
	results.desktop_frame_wall_time = timed_summary(frame_times)
	results.effect_stats = game.squeegee_water.debug_stats()
	started = Time.get_ticks_usec()
	var snapshot: Dictionary = game.soil.make_snapshot()
	results.wet_snapshot_cpu_ms = (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	game._on_practice_tool_pressed(1)
	results.repeat_equip_squeegee_ms = (Time.get_ticks_usec() - started) / 1000.0
	results.snapshot_bytes = JSON.stringify(snapshot).length()
	game.free()
	current_scene = null
	var label := "latest"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profile-label="):
			label = argument.get_slice("=", 1).validate_filename()
	var output := FileAccess.open("res://../build/mobile_profile_" + label + ".json", FileAccess.WRITE)
	output.store_string(JSON.stringify(results, "\t"))
	output.close()
	print("MOBILE_PROFILE ", label, " ", JSON.stringify(results))
	quit()
