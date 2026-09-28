extends SceneTree
## Repeatable renderer-backed hose workload. Desktop timing is not phone FPS.
var game: Node
var paint_usec := 0
var contact_count := 0
var results: Dictionary = {}

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Run with the graphics renderer and -- --shop-test")
		quit(2)
		return
	call_deferred("run")

func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func summary(samples: Array[float]) -> Dictionary:
	var ordered := samples.duplicate()
	ordered.sort()
	return {"median_ms": ordered[ordered.size() / 2], "p95_ms": ordered[mini(ordered.size() - 1, floori(ordered.size() * 0.95))], "max_ms": ordered.back()}

func direct_contact(position: Vector3, radius: float, strength: float) -> void:
	var begin := Time.get_ticks_usec()
	game._on_water_contact(position, radius, strength)
	paint_usec += Time.get_ticks_usec() - begin
	contact_count += 1

func soak_contact(position: Vector3, radius: float, strength: float) -> void:
	var begin := Time.get_ticks_usec()
	game._on_soak_contact(position, radius, strength)
	paint_usec += Time.get_ticks_usec() - begin
	contact_count += 1

func pause_effects() -> void:
	game.water.set_process(false)
	game.soil.set_process(false)
	game.squeegee_water.set_process(false)

func run() -> void:
	var state := root.get_node("ShopState")
	state.set_process(false)
	state._test_ticks_msec = 0
	state._test_unix_time = 1000000.0
	root.size = Vector2i(390, 844)
	game = load("res://scenes/test/rug_cleaning_gym.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	for _i in 4: await frame()
	game.select_rug(1)
	game.water.water_contact.disconnect(game._on_water_contact)
	game.water.soak_contact.disconnect(game._on_soak_contact)
	game.water.water_contact.connect(direct_contact)
	game.water.soak_contact.connect(soak_contact)
	for level in [0, 4]:
		for motion in ["hold", "fast"]:
			game._on_practice_tool_pressed(2)
			game.set_hose_upgrade_level(level)
			for _i in 3: await frame()
			pause_effects()
			var ticks: Array[float] = []
			var paint: Array[float] = []
			var visual: Array[float] = []
			var uploads: Array[float] = []
			var wall: Array[float] = []
			var max_contacts := 0
			var all_contacts := 0
			for index in 180:
				var t := float(index) / 60.0
				var point := Vector3.ZERO if motion == "hold" else Vector3(sin(t * TAU * 2.4) * 0.83, 0.067, sin(t * TAU * 0.73) * 1.25)
				point.y = 0.067
				var start := Time.get_ticks_usec()
				if index == 0:
					game.begin_stroke(game.camera.unproject_position(point), false)
				else:
					game.move_brush_to_screen(game.camera.unproject_position(point), false)
				paint_usec = 0
				contact_count = 0
				var tick := Time.get_ticks_usec()
				game.water._process(1.0 / 60.0)
				var elapsed := Time.get_ticks_usec() - tick
				ticks.append(elapsed / 1000.0)
				paint.append(paint_usec / 1000.0)
				visual.append((elapsed - paint_usec) / 1000.0)
				max_contacts = maxi(max_contacts, contact_count)
				all_contacts += contact_count
				tick = Time.get_ticks_usec()
				game.soil._process(0.0)
				uploads.append((Time.get_ticks_usec() - tick) / 1000.0)
				pause_effects()
				await frame()
				wall.append((Time.get_ticks_usec() - start) / 1000.0)
			var key := "%s_level_%d" % [motion, level]
			results[key] = {"water_cpu": summary(ticks), "contact_paint_and_ui_cpu": summary(paint), "jet_visual_and_bookkeeping_cpu": summary(visual), "upload_cpu": summary(uploads), "frame_wall_time": summary(wall), "max_contacts_per_tick": max_contacts, "total_contacts": all_contacts, "water_total": game.soil.water_coverage_total, "mask_hash": hash(game.soil.wet_mask.get_data()), "wet_events": game.water.wet_events, "pending_soak": game.water.soak.debug_stats().get("pending_events", 0)}
			game.end_stroke()
			# Pending capillary work and in-flight water are allowed to drain.
			# These totals are outside the timed drag workload above.
			for _step in 90:
				game.water._process(1.0 / 60.0)
			game.soil._process(0.0)
			pause_effects()
			results[key]["settled_water_total"] = game.soil.water_coverage_total
			results[key]["settled_mask_hash"] = hash(game.soil.wet_mask.get_data())
			results[key]["settled_soak_alive"] = game.water.soak.is_alive()
			print("HOSE_PROFILE_CASE ", key, " ", JSON.stringify(results[key]))
	game.free()
	current_scene = null
	var label := "local"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profile-label="):
			label = argument.get_slice("=", 1).validate_filename()
	var output := FileAccess.open("res://../build/mobile_hose_profile_" + label + ".json", FileAccess.WRITE)
	output.store_string(JSON.stringify(results, "\t"))
	output.close()
	quit()
