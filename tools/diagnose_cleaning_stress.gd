extends SceneTree
## Desktop production-path diagnostic, isolated from the player's progress.
## Pinned engine, graphics renderer, and -- --shop-test are mandatory.
## Touches and saves are real; final completion masks are accelerated after
## each rug's real-input workload so several normal replacement animations run.

const Rules := preload("res://scripts/progression.gd")
const Scene := preload("res://scenes/production/rug_cleaning.tscn")
const OUTPUT := "res://../build/cleaning_stress_diagnostic.json"
const STROKES_PER_RUG := 80
const RUGS_PER_STORE := 3
const DRAGS_PER_STROKE := 8

var game: Node
var ledger: Node
var save_path := ""
var checks := 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []
var stroke_times: Array[float] = []
var release_times: Array[float] = []
var touch_starts := 0
var accepted_strokes := 0
var accepted_by_tool: Dictionary = {"brush": 0, "hose": 0, "squeegee": 0}
var changing_by_tool: Dictionary = {"brush": 0, "hose": 0, "squeegee": 0}
var drag_events := 0
var touch_releases := 0
var simulated_replacements := 0
var focus_cycles := 0
var room_purchases := 0
var started_usec := 0

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Cleaning stress requires a graphics renderer and -- --shop-test")
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("CLEANING STRESS: " + message)

func frames(count: int = 1) -> void:
	for frame in count:
		await process_frame
		await RenderingServer.frame_post_draw

func sample(label: String) -> void:
	var entry: Dictionary = {
		"label": label,
		"elapsed_seconds": (Time.get_ticks_usec() - started_usec) / 1000000.0,
		"static_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"static_memory_peak_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resource_count": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"texture_memory_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"video_memory_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"buffer_memory_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
	}
	if is_instance_valid(game):
		entry["store"] = int(ledger.active_store)
		entry["job_id"] = str(game.contract_job_id)
		entry["tool"] = int(game.selected_tool)
		entry["phase"] = int(game.rug_phase)
		entry["pool_size"] = game.soil.batch.instance_count
		entry["debris_active"] = game.soil.active.size()
		entry["debris_fading"] = game.soil.timed_debris.size()
		entry["mask_bytes"] = game.soil.mask.get_data().size()
		entry["window_physical_size"] = str(root.size)
		entry["viewport_visible_size"] = str(root.get_visible_rect().size)
	samples.append(entry)
	print("CLEANING_STRESS_SAMPLE ", JSON.stringify(entry))

func touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.device = 0
	event.index = 0
	event.position = point
	event.pressed = pressed
	root.push_input(event, true)

func point_on_rug(world: Vector3) -> Vector2:
	return game.camera.unproject_position(world) - game.TOUCH_CONTACT_OFFSET

func swipe(index: int) -> void:
	var lane := -0.82 + float(index % 5) * 0.41
	# Finger contact is 72 logical pixels below the brush head. Leave enough
	# room inside the carpet for that pointer, rather than tap the floor below.
	var start_z := -1.08 if index % 2 == 0 else 1.08
	var finish_z := -start_z
	var origin := point_on_rug(Vector3(lane, 0.067, start_z))
	var previous := origin
	var begin := Time.get_ticks_usec()
	var tool: int = game.selected_tool
	var tool_name: String = ["brush", "squeegee", "hose"][tool]
	var coverage_before: float = game.soil.surface_coverage_total if tool == 0 else (game.soil.water_coverage_total if tool == 2 else game.soil.extraction_coverage_total)
	touch(origin, true)
	check(game.brush_dragging and game.active_touch == 0, "Touch begins real cleaning gesture %d" % index)
	if game.brush_dragging and game.active_touch == 0:
		accepted_strokes += 1
		accepted_by_tool[tool_name] += 1
	touch_starts += 1
	for step in DRAGS_PER_STROKE:
		var amount := float(step + 1) / DRAGS_PER_STROKE
		var x := lane + sin(amount * PI) * (0.14 if index % 3 == 0 else 0.0)
		var position := point_on_rug(Vector3(x, 0.067, lerpf(start_z, finish_z, amount)))
		var event := InputEventScreenDrag.new()
		event.device = 0
		event.index = 0
		event.position = position
		event.relative = position - previous
		event.velocity = event.relative * 120.0
		root.push_input(event, true)
		previous = position
		drag_events += 1
	stroke_times.append((Time.get_ticks_usec() - begin) / 1000.0)
	# Draw while held so wet emission and texture/buffer uploads actually run.
	await frames(2 if tool == 2 else 1)
	begin = Time.get_ticks_usec()
	touch(previous, false)
	touch_releases += 1
	release_times.append((Time.get_ticks_usec() - begin) / 1000.0)
	check(not game.brush_dragging and not game.contract_save_failed, "Release saves and ends gesture %d" % index)
	await frames()
	var coverage_after: float = game.soil.surface_coverage_total if tool == 0 else (game.soil.water_coverage_total if tool == 2 else game.soil.extraction_coverage_total)
	if not is_equal_approx(coverage_before, coverage_after): changing_by_tool[tool_name] += 1

func wait_for_cleaning() -> void:
	var deadline := Time.get_ticks_msec() + 12000
	while game.rug_phase != game.RugPhase.CLEANING and Time.get_ticks_msec() < deadline:
		await frames()
	check(game.rug_phase == game.RugPhase.CLEANING, "Normal production arrival reaches cleaning")
	game.auto_finish_queued = true # Retain this rug for the prescribed workload.

func upgrade_pulse(category: String) -> void:
	game.open_room_upgrade(category)
	var old_level: int = int(ledger.room_upgrade_levels()[category])
	game._purchase_room(category)
	check(int(ledger.room_upgrade_levels()[category]) == old_level + 1, "Real room purchase " + category)
	check(game.room.is_upgrade_active(category), "Room pulse started " + category)
	room_purchases += 1
	await create_timer(0.98).timeout
	await frames()
	check(not game.room.is_upgrade_active(), "Room pulse settles " + category)
	game.hud.close_upgrades()

func exercise_focus() -> void:
	var point := point_on_rug(Vector3(0, 0.067, 0))
	touch(point, true)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not game.brush_dragging, "Focus out cancels active touch")
	await frames(2)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	touch(point, false)
	focus_cycles += 1
	await frames()

func complete_and_replace() -> void:
	var old_job: String = game.contract_job_id
	# Completed fixture only after the real touch workload. It accelerates
	# geometric cleaning, while reward/save/blur/window/roll/arrival stay real.
	var soil: Node = game.soil
	soil.end_pass()
	if game.wet_recipe:
		soil.prepare_extraction_stage(soil.WASH_CYCLES - 1)
		soil.extraction_values.fill(1.0)
		soil.extraction_coverage_total = float(soil.surface_pixel_count)
		soil.extraction_mask.fill(Color.WHITE)
		soil.extraction_mask_changed = true
	else:
		soil.remaining = 0
		soil.credited.fill(true)
		soil.cleared.fill(true)
		soil.coverage_values.fill(0.0)
		soil.surface_coverage_total = 0.0
		soil.mask.fill(Color.BLACK)
		soil.mask_changed = true
	soil.request_render()
	game.finish_rug()
	check(game.contract_finished and ledger.active_job_id != old_job, "Completion commits next paid rug")
	var deadline := Time.get_ticks_msec() + 12000
	while game.rug_phase != game.RugPhase.REVEAL and Time.get_ticks_msec() < deadline:
		await frames()
	check(game.rug_phase == game.RugPhase.REVEAL, "Normal completion reaches reveal")
	await create_timer(0.50).timeout
	await frames()
	sample("store_%d_reveal_%d" % [int(ledger.active_store), simulated_replacements])
	game.skip_completion_reveal()
	await wait_for_cleaning()
	check(game.contract_job_id != old_job, "Normal roll sequence opens replacement rug")
	simulated_replacements += 1

func summary(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	return {"count": sorted.size(), "median_ms": sorted[sorted.size() / 2], "p95_ms": sorted[mini(sorted.size() - 1, floori(sorted.size() * 0.95))], "max_ms": sorted.back()}

func run() -> void:
	started_usec = Time.get_ticks_usec()
	ledger = root.get_node("ShopState")
	ledger.set_process(false)


	save_path = "res://.godot/cleaning_stress_%d.json" % OS.get_process_id()
	ledger._save_path = save_path
	root.size = Vector2i(1080, 2400)
	await frames(3)
	sample("before_workshops")
	for store in [1, 2]:
		check(ledger.reset_progress(), "Isolated ledger resets")
		ledger._sync_active_branch()
		if store == 2: ledger.stores["2"] = Rules.new_branch(2)
		ledger.active_store = store
		ledger._load_active_branch()
		ledger.cash = 1000000
		check(not ledger.start_job().is_empty(), "Isolated paid job starts")
		game = Scene.instantiate()
		root.add_child(game)
		current_scene = game
		await wait_for_cleaning()
		await frames(5)
		sample("store_%d_ready" % store)
		for rug in RUGS_PER_STORE:
			for stroke in STROKES_PER_RUG:
				await swipe(stroke)
				if stroke % 20 == 19:
					sample("store_%d_rug_%d_strokes_%d" % [store, rug, stroke + 1])
				if stroke == 39:
					await exercise_focus()
					if store == 2:
						# After real hose gestures, accelerate the soak fixture so
						# subsequent gestures exercise real extraction and its VFX.
						game.soil.prepare_extraction_stage(0)
						game.select_tool(1)
						await frames(2)
			await upgrade_pulse(["floor", "plants", "window"][rug])
			if rug == 2: await upgrade_pulse("railings")
			await complete_and_replace()
			await frames(8)
			sample("store_%d_replacement_%d_settled" % [store, rug + 1])
		game.free()
		game = null
		current_scene = null
		await frames(8)
		sample("store_%d_freed" % store)
	var result: Dictionary = {
		"scope": "Windows desktop compatibility renderer; not an Android crash reproduction",
		"engine": Engine.get_version_info(), "platform": OS.get_name(),
		"requested_physical_viewport": "1080x2400",
		"isolated_test_save": true, "completion_fixture_accelerated_after_real_strokes": true,
		"touch_starts": touch_starts, "drag_events": drag_events, "touch_releases": touch_releases,
		"accepted_strokes": accepted_strokes, "accepted_by_tool": accepted_by_tool,
		"changing_real_masks_by_tool": changing_by_tool,
		"replacement_sequences": simulated_replacements, "focus_cycles": focus_cycles, "room_purchases": room_purchases,
		"stroke_handler_cpu": summary(stroke_times), "release_handler_cpu": summary(release_times),
		"checks": checks, "failure_count": failures.size(), "failures": failures,
		"elapsed_seconds": (Time.get_ticks_usec() - started_usec) / 1000000.0, "samples": samples,
	}
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		push_error("Could not write stress diagnostic")
		quit(2)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	for path: String in [save_path, save_path + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("CLEANING_STRESS_COMPLETE ", checks, " checks, ", failures.size(), " failures; ", touch_starts, " strokes; ", simulated_replacements, " replacement sequences")
	quit(0 if failures.is_empty() else 1)
