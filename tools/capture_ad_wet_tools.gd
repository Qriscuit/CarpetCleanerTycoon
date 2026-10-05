extends SceneTree
## Isolated native-speed production capture. Initial unlocked-save fixture only;
## all visible wetting/extraction is real tool input, no mask writes or physics loops.
## Launch only with the pinned Mono wrapper and -- --shop-test --audition-audio.
## Movie writing uses --write-movie <path.avi> --fixed-fps 30 before the --.

const PHASE_NAMES := ["ARRIVING", "GROWING", "TOOL_ENTERING", "CLEANING", "VACUUMING", "REVEAL", "DEPARTING"]
const LANES := [-0.28, 0.25, -0.81, 0.78]
const STROKE_SECONDS := 2.0
const GAP_SECONDS := 0.16
const TOUCH_INDEX := 0

var game: Node
var ledger: Node
var audio: Node
var mode := "full"
var output_dir := ""
var resume_from := ""
var fps := 30
var rug_target := 3
var max_frames := 30 * 420
var smoke_seconds := 10.0
var frame := 0
var engine_frame_at_start := 0
var event_file: FileAccess
var events: Array[Dictionary] = []
var completed_jobs: Array[Dictionary] = []
var current_job := ""
var current_rug := ""
var last_phase := -1
var previous_phase := -1
var phase_started := 0
var warmup_until := 0
var lane_index := 0
var lane_pass := 0
var sweep_round := 0
var stroke_start := -1
var stroke_from := Vector3.ZERO
var stroke_to := Vector3.ZERO
var touch_position := Vector2.ZERO
var pointer_down := false
var next_stroke_frame := 0
var last_progress_bucket := -1
var ending := false
var failed := false
var error_text := ""
var started_at := ""
var wall_start_usec := 0
var tool_seen := -1
var shot_row := 0
var stroke_duration := 3.0
var wet_rows := [-0.05, -1.35, 0.75, -0.65, 1.15]
var extract_rows := [0.0, -0.60, 0.60, -1.18, 1.18, -1.52, 1.52]
var segment_tool := -1
var brush_only := false
var panel_sweep := false


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Ad capture requires -- --shop-test; refusing access to player progress.")
		quit(2)
		return
	call_deferred("run")


func arg_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix + "="):
			return argument.substr(prefix.length() + 1)
	return fallback


func run() -> void:
	mode = arg_value("--ad-capture-mode", "full")
	brush_only = arg_value("--ad-tool", "wet") == "brush"
	panel_sweep = arg_value("--ad-panel-sweep", "0") == "1"
	fps = int(arg_value("--ad-fps", "30"))
	rug_target = int(arg_value("--ad-rug-count", "3"))
	smoke_seconds = float(arg_value("--ad-smoke-seconds", "10"))
	max_frames = int(arg_value("--ad-max-frames", str(fps * 420)))
	if mode not in ["smoke", "full"] or fps < 24 or fps > 60 or rug_target < 1 or rug_target > 3:
		push_error("Invalid ad capture arguments.")
		quit(2)
		return
	# Resolve from this harness, not res://: the renderer may use an isolated
	# project snapshot whose res:// root lives inside the capture session.
	var harness_path: String = ProjectSettings.globalize_path(get_script().resource_path)
	var workspace_root := harness_path.get_base_dir().get_base_dir()
	var permitted_root := (workspace_root + "/build/ad-capture-v3").simplify_path().replace("\\", "/")
	output_dir = ProjectSettings.globalize_path(arg_value("--ad-output", permitted_root + "/session-001")).simplify_path().replace("\\", "/")
	if not output_dir.to_lower().begins_with(permitted_root.to_lower() + "/"):
		push_error("Capture output must be a session directory inside build/ad-capture-v3. Harness=%s; allowed=%s; output=%s; arguments=%s" % [harness_path, permitted_root, output_dir, str(OS.get_cmdline_user_args())])
		quit(2)
		return
	for folder: String in ["", "/saves", "/checkpoints", "/logs", "/stills"]:
		if DirAccess.make_dir_recursive_absolute(output_dir + folder) != OK:
			push_error("Unable to create isolated capture directory.")
			quit(2)
			return
	var save_path := output_dir + "/saves/ledger.json"
	if FileAccess.file_exists(save_path) or FileAccess.file_exists(output_dir + "/logs/events.jsonl"):
		push_error("Session already contains evidence; select a new --ad-output directory.")
		quit(2)
		return
	resume_from = arg_value("--ad-resume-from", "")
	if not resume_from.is_empty():
		resume_from = ProjectSettings.globalize_path(resume_from).simplify_path().replace("\\", "/")
		if not resume_from.to_lower().begins_with(permitted_root.to_lower() + "/") or not FileAccess.file_exists(resume_from):
			push_error("Resume requires an existing earned checkpoint inside build/ad-capture-v3.")
			quit(2)
			return
		if DirAccess.copy_absolute(resume_from, save_path) != OK:
			push_error("Unable to copy the earned checkpoint into this isolated session.")
			quit(2)
			return
	event_file = FileAccess.open(output_dir + "/logs/events.jsonl", FileAccess.WRITE)
	if event_file == null:
		push_error("Cannot create capture event log.")
		quit(2)
		return
	ledger = root.get_node("ShopState")
	ledger._save_path = save_path
	if resume_from.is_empty():
		if not ledger.reset_progress():
			abort_capture("Isolated ledger initialization failed.")
			return
	else:
		ledger._load_state()
		if not str(ledger.last_error).is_empty():
			abort_capture("Earned checkpoint could not be loaded: " + str(ledger.last_error))
			return
	# Unlock fixture affects only this isolated save. Production progression methods
	# purchase the authored maximum upgrades; the mask itself is never seeded.
	if not brush_only:
		var rules := load("res://scripts/progression.gd")
		for store_id in range(2, 5):
			ledger.stores[str(store_id)] = rules.new_branch(store_id)
		ledger.cash = 5000000
		if not ledger.save_state() or not ledger.select_store(4):
			abort_capture("Unable to save isolated unlocked branches.")
			return
		for _level in range(4):
			if not ledger.buy_hose_upgrade() or not ledger.buy_squeegee_upgrade():
				abort_capture("Production maximum wet-tool purchase failed.")
				return
		if not ledger.select_store(2):
			abort_capture("Cannot select production water-only workshop.")
			return
		for _level in range(4):
			if not ledger.buy_hose_upgrade() or not ledger.buy_squeegee_upgrade():
				abort_capture("Local wet upgrade selection failed.")
				return
		# Choose the actual third catalog motif through saved completed-job index.
		# This is an explicit setup fixture, not evidence of earned progression.
		ledger.manual_jobs = 2
		ledger.stores["2"].manual_jobs = 2
		ledger.save_state()
		mark("isolated_unlock_setup", {"fixture": true, "mask_fixture": false, "progression": ledger.progression_view(), "setup_note": "Unlocked stores and filming cash seeded only in isolated save; actual maximum upgrades purchased through production methods. Two past jobs seeded solely to select Fox's Den. All water/extraction captured from ordinary input."})
	if brush_only:
		ledger.manual_jobs = 2
		ledger.stores["1"].manual_jobs = 2
		ledger.save_state()
		mark("isolated_catalog_setup", {"mask_fixture": false, "setup_note": "Two past jobs seeded only to choose Fox motif; starter brush unchanged."})
	audio = root.get_node("GameAudio")
	audio.settings_path = output_dir + "/saves/audio.cfg"
	audio.set_music_enabled(false)
	audio.set_effects_enabled(true)
	root.size = Vector2i(540, 960)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	# Production Workshop installs its normal canvas scaling during _ready.
	# Override only the capture window's render resolution, keeping the window
	# on screen; gameplay HUD and camera still perform their actual layout.
	root.content_scale_size = Vector2i(1080, 1920)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(540, 960)
	started_at = Time.get_datetime_string_from_system(true, true)
	wall_start_usec = Time.get_ticks_usec()
	engine_frame_at_start = Engine.get_process_frames()
	mark("capture_start", {
		"mode": mode, "panel_sweep": panel_sweep, "requested_rugs": rug_target, "native_speed": true,
		"engine": Engine.get_version_info(), "fps": fps,
		"render_size": [1080, 1920], "window_size": [540, 960],
		"resumed": not resume_from.is_empty(), "resume_from": resume_from,
		"clock_note": "One ordinary touch movement per rendered frame. Only the previous stroke timestamp is normalized to the movie frame duration because production input otherwise reads wall-clock time. All production delta/physics, brush power, masks, rewards and animations are unchanged.",
		"music": false, "effects": true, "audio_audition_enabled": not audio.silent_test,
		"fixture_only": false, "unlocked_setup_fixture": not brush_only, "mask_fixture": false, "hud_hidden": false
	})
	while not ending:
		await process_frame
		frame += 1
		step_capture()
	finish_capture()


func step_capture() -> void:
	if frame >= max_frames:
		abort_capture("Bounded limit reached before wet restoration completed.")
		return
	if mode == "smoke" and frame >= ceili(smoke_seconds * fps):
		mark("smoke_complete", stats())
		ending = true
		return
	if not audio.focused:
		abort_capture("Capture window lost focus.")
		return
	var phase: int = game.rug_phase
	if current_job.is_empty():
		current_job = game.contract_job_id
		current_rug = str(game.soil.rug_definition.rug_id)
		mark("job_start", {"progression": ledger.progression_view(), "hose_level": game.hose_upgrade_level, "hose_direct_power": game.hose_direct_power, "squeegee_level": game.squeegee_upgrade_level, "squeegee_power": game.squeegee_power, "width": game.tool_width, "dry_power": game.dry_tool_power})
	if phase != last_phase:
		last_phase = phase
		phase_started = frame
		mark("phase", {"phase": PHASE_NAMES[phase], "progress": stats()})
		if phase == game.RugPhase.CLEANING:
			next_stroke_frame = frame + roundi(0.6 * fps)
		if phase == game.RugPhase.VACUUMING:
			pointer_down = false
			stroke_start = -1
			completed_jobs.append({"job_id": current_job, "rug_id": current_rug, "frame": frame, "engine_frame": Engine.get_process_frames(), "full_restoration": game.completed_full_restore, "clearance": game.completed_fraction, "reward": game.completed_reward})
		if phase == game.RugPhase.REVEAL:
			_save_still.call_deferred("wet_full_clean_reveal")
			mark("hero_reveal_start", {"full_restoration": game.completed_full_restore})
	if phase == game.RugPhase.DEPARTING and frame - phase_started >= roundi(0.8 * fps):
		mark("wet_job_complete", stats())
		ending = true
		return
	if phase != game.RugPhase.CLEANING: return
	if frame % fps == 0: mark("progress", stats())
	# Wet emission locks at the actual 99% coverage gate. Release before the
	# normal workshop auto-advance chooses the squeegee on the next frame.
	if not brush_only and game.selected_tool == 2 and game.soil.water_stage_complete():
		if pointer_down:
			release_touch()
			mark("hose_stage_complete", stats())
			_save_still.call_deferred("fully_wet_from_real_hose")
		return
	if game.selected_tool != tool_seen:
		tool_seen = game.selected_tool
		shot_row = 0
		mark("tool_selected", {"tool": tool_seen, "progress": stats()})
		next_stroke_frame = frame + roundi(0.6 * fps)
	if pointer_down:
		var amount := minf(float(frame - stroke_start) / (stroke_duration * fps), 1.0)
		var eased := amount * amount * (3.0 - 2.0 * amount)
		move_touch(stroke_from.lerp(stroke_to, eased))
		if frame - stroke_start == roundi(1.5 * fps):
			_save_still.call_deferred("tool_%d_row_%d_mid" % [segment_tool, shot_row])
		if not game.brush_dragging and not game.soil.completion_started:
			abort_capture("Production pointer rejected the stroke.")
			return
		if amount >= 1.0:
			release_touch()
			mark("stroke_end", {"tool": segment_tool, "row": shot_row, "progress": stats()})
			if panel_sweep and segment_tool == 1 and shot_row == 0:
				mark("panel_sample_complete", stats())
				ending = true
			shot_row += 1
			next_stroke_frame = frame + roundi(0.22 * fps)
			if brush_only and shot_row >= 10:
				ending = true
	elif frame >= next_stroke_frame:
		segment_tool = game.selected_tool
		var z := 0.0
		if not brush_only:
			var rows: Array = wet_rows if segment_tool == 2 else extract_rows
			z = float(rows[shot_row % rows.size()])
		var reverse := shot_row % 2 == 1
		# Central horizontal movement keeps contact and runoff together in a
		# landscape editorial crop. It remains an ordinary production gesture.
		var span := 0.65 if panel_sweep and (brush_only or shot_row == 0) else 1.27
		stroke_from = Vector3(span if reverse else -span, 0.067, z)
		stroke_to = Vector3(-span if reverse else span, 0.067, z)
		stroke_start = frame
		stroke_duration = float(arg_value("--ad-center-seconds", "3.0")) if shot_row == 0 and not brush_only else 3.0
		begin_touch(stroke_from)
		mark("stroke_start", {"tool": segment_tool, "row": shot_row, "local_from": [stroke_from.x, z], "local_to": [stroke_to.x, z], "screen_from": [touch_position.x, touch_position.y], "screen_to": [pointer_for(stroke_to).x, pointer_for(stroke_to).y], "duration": stroke_duration, "progress": stats()})
		if not game.brush_dragging:
			abort_capture("Production stroke did not begin; inspect HUD limits.")


func stats() -> Dictionary:
	return {"surface": game.soil.surface_clearance(), "water": game.soil.water_clearance(), "extraction": game.soil.extraction_clearance(), "overall": game.soil.overall_clearance(), "tool": game.selected_tool, "wet_events": game.water.wet_events if is_instance_valid(game.water) else 0, "squeegee_fx": game.squeegee_water.debug_stats() if is_instance_valid(game.squeegee_water) else {}}


func pointer_for(local_point: Vector3) -> Vector2:
	var world: Vector3 = game.soil.rug_node.to_global(local_point)
	return game.camera.unproject_position(world) - game.TOUCH_CONTACT_OFFSET


func begin_touch(local_point: Vector3) -> void:
	touch_position = pointer_for(local_point)
	var touch := InputEventScreenTouch.new()
	touch.index = TOUCH_INDEX
	touch.position = touch_position
	touch.pressed = true
	root.push_input(touch, true)
	pointer_down = true


func move_touch(local_point: Vector3) -> void:
	var next_position := pointer_for(local_point)
	var motion := InputEventScreenDrag.new()
	motion.index = TOUCH_INDEX
	motion.position = next_position
	motion.relative = next_position - touch_position
	# Godot's movie writer uses fixed simulation delta, while the production
	# input callback reads a wall clock. Normalize that input timestamp only.
	var milliseconds := roundi(float(frame + 1) * 1000.0 / fps) - roundi(float(frame) * 1000.0 / fps)
	game.stroke_time = Time.get_ticks_msec() - milliseconds
	root.push_input(motion, true)
	touch_position = next_position


func release_touch() -> void:
	if not pointer_down: return
	var touch := InputEventScreenTouch.new()
	touch.index = TOUCH_INDEX
	touch.position = touch_position
	touch.pressed = false
	root.push_input(touch, true)
	pointer_down = false


func checkpoint(label: String) -> void:
	var name := "%s_%s_%06d.json" % [current_rug, label, frame]
	var destination := output_dir + "/checkpoints/" + name
	if DirAccess.copy_absolute(ledger._save_path, destination) != OK:
		abort_capture("Unable to archive earned checkpoint: " + name)
		return
	mark("checkpoint", {"path": destination, "label": label, "earned_through_production_input": true})


func _save_still(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := output_dir + "/stills/" + label + ".png"
	var image := root.get_texture().get_image()
	var result := image.save_png(path)
	mark("still", {"path": path, "width": image.get_width(), "height": image.get_height(), "success": result == OK})


func mark(kind: String, detail: Dictionary = {}) -> void:
	var record := {"kind": kind, "frame": frame, "engine_frame": Engine.get_process_frames(), "seconds": float(frame) / float(fps), "job_id": current_job, "rug_id": current_rug}
	record.merge(detail, true)
	events.append(record)
	if event_file != null:
		event_file.store_line(JSON.stringify(record))
		event_file.flush()
	print("AD_CAPTURE ", JSON.stringify(record))


func abort_capture(message: String) -> void:
	error_text = message
	failed = true
	ending = true
	push_error(message)
	mark("capture_failed", {"error": message})
	if not is_instance_valid(game):
		finish_capture()


func finish_capture() -> void:
	if is_instance_valid(game):
		release_touch()
		game.save_contract_progress()
	mark("capture_end", {"success": not failed, "error": error_text, "completed_jobs": completed_jobs, "wall_seconds": float(Time.get_ticks_usec() - wall_start_usec) / 1000000.0})
	var report := {"success": not failed, "error": error_text, "mode": mode, "panel_sweep": panel_sweep, "started_at_utc": started_at, "native_speed": true, "fixture_only": false, "unlocked_setup_fixture": not brush_only, "mask_fixture": false, "fps": fps, "driver_frames": frame, "engine_frame_at_start": engine_frame_at_start, "recording_frame_note": "engine_frame is the engine process-frame index; verify first-frame offset against the exported movie when selecting edit in/out.", "render_size": [1080, 1920], "resume_from": resume_from, "production_input": "InputEventScreenTouch and InputEventScreenDrag through root.push_input; one motion per rendered frame", "clock_normalization": "Only the previous brush input timestamp is aligned with fixed movie delta. No calls to manual physics, soil strokes or mask writes. Isolated initial progression/cash unlock fixture documented separately.", "completed_jobs": completed_jobs, "events": events}
	var file := FileAccess.open(output_dir + "/take_manifest.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	if event_file != null:
		event_file.close()
	quit(1 if failed else 0)
