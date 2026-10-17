extends SceneTree
## Actual paid Stillwater Pond input, in an isolated source/save snapshot.
## No mask writes, manual simulation, gameplay power edits, or forced completion.

const PHASE_NAMES := ["ARRIVING", "GROWING", "TOOL_ENTERING", "CLEANING", "VACUUMING", "REVEAL", "DEPARTING"]
const LANES := [-0.28, 0.25, 0.78, -0.81]
const TOUCH_INDEX := 0
const FPS := 30

var game: Node
var ledger: Node
var audio: Node
var output_dir := ""
var mode := "full"
var frame := 0
var engine_frame_at_start := 0
var current_job := ""
var current_rug := ""
var last_phase := -1
var phase_started := 0
var next_stroke_frame := 0
var stroke_start := -1
var stroke_duration := 2.0
var stroke_from := Vector3.ZERO
var stroke_to := Vector3.ZERO
var touch_position := Vector2.ZERO
var pointer_down := false
var stroke_number := 0
var hero_pass := 0
var lane_index := 0
var lane_pass := 0
var sweep_round := 0
var hero_done := false
var completed_jobs: Array[Dictionary] = []
var events: Array[Dictionary] = []
var event_file: FileAccess
var ending := false
var failed := false
var error_text := ""
var started_at := ""
var wall_start_usec := 0
var empty_saved := false
var window_saved := false
var curl_saved := false
var room_saved := false
var next_arrival_frame := -1
var setup_purchases: Array[Dictionary] = []
var resumed_session := ""

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Ad recording requires -- --shop-test and isolated saves.")
		quit(2)
		return
	run.call_deferred()

func arg_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix + "="):
			return argument.substr(prefix.length() + 1)
	return fallback

func run() -> void:
	mode = arg_value("--ad-capture-mode", "full")
	var harness_path := ProjectSettings.globalize_path(get_script().resource_path)
	var allowed := (harness_path.get_base_dir().get_base_dir() + "/build/ad-capture-v5").simplify_path().replace("\\", "/")
	output_dir = (allowed + "/" + arg_value("--ad-session-name", "")).simplify_path().replace("\\", "/")
	if mode not in ["smoke", "full"] or not output_dir.to_lower().begins_with(allowed.to_lower() + "/"):
		push_error("A new build/ad-capture-v5 session is required. mode=%s allowed=%s output=%s harness=%s args=%s" % [mode, allowed, output_dir, harness_path, str(OS.get_cmdline_user_args())])
		quit(2)
		return
	for folder: String in ["saves", "logs", "stills", "checkpoints"]:
		DirAccess.make_dir_recursive_absolute(output_dir + "/" + folder)
	if FileAccess.file_exists(output_dir + "/saves/ledger.json"):
		push_error("Refusing to overwrite an existing session.")
		quit(2)
		return
	event_file = FileAccess.open(output_dir + "/logs/events.jsonl", FileAccess.WRITE)
	ledger = root.get_node("ShopState")
	ledger._save_path = output_dir + "/saves/ledger.json"
	resumed_session = arg_value("--ad-resume-session", "")
	if not resumed_session.is_empty():
		var earned_save := (allowed + "/" + resumed_session + "/saves/ledger.json").simplify_path()
		if not earned_save.to_lower().begins_with(allowed.to_lower() + "/") or not FileAccess.file_exists(earned_save):
			abort_capture("Resume requires a genuinely earned save in build/ad-capture-v5.")
			return
		if DirAccess.copy_absolute(earned_save, ledger._save_path) != OK:
			abort_capture("Unable to copy the prior real-input save.")
			return
		ledger._load_state()
		if not str(ledger.last_error).is_empty():
			abort_capture("Earned isolated save did not load: " + str(ledger.last_error))
			return
		hero_done = true
		lane_index = int(arg_value("--ad-resume-lane", "2"))
		lane_pass = int(arg_value("--ad-resume-pass", "2"))
		mark("earned_save_resumed", {"session": resumed_session, "save": earned_save, "starting_cash": ledger.cash, "starting_lane": lane_index, "starting_lane_pass": lane_pass, "note": "Prior masks were earned by ordinary production input. Their production save is loaded unchanged; no clearance is seeded."})
	else:
		if not ledger.reset_progress():
			abort_capture("Isolated setup save failed.")
			return
	# Catalog/job count and filming budget are setup fixtures only. Every visible
	# improvement below is bought using ordinary production ledger methods.
	if resumed_session.is_empty():
		ledger.manual_jobs = 5
		ledger.stores["1"].manual_jobs = 5
		ledger.cash = 1000000000.0
		if not ledger.save_state():
			abort_capture("Unable to seed isolated catalog setup.")
			return
		var room_rules := load("res://scripts/room_upgrades.gd")
		for id: String in room_rules.IDS:
			var milestones: Array = room_rules.visual_milestones(id, 1)
			var target_level: int = milestones[1]
			for _level in range(target_level):
				var offer: Dictionary = ledger.room_upgrade_view(id)
				if not ledger.buy_room_upgrade(id):
					abort_capture("Authored " + id + " purchase failed: " + str(ledger.last_error))
					return
				setup_purchases.append({"kind": "room", "id": id, "level": _level + 1, "cost": offer.cost})
		var tool_offer: Dictionary = ledger.progression_view()
		if not ledger.buy_tool_upgrade():
			abort_capture("Authored wide-brush purchase failed.")
			return
		setup_purchases.append({"kind": "brush", "level": 1, "cost": tool_offer.tool_cost})
	# A compact filming wallet is still a documented setup fixture. No earned
	# balances, job clearance, completion thresholds or rewards are seeded.
	if resumed_session.is_empty(): ledger.cash = 1240.0
	if not ledger.save_state():
		abort_capture("Unable to save completed filming setup.")
		return
	mark("isolated_setup", {"fixture": true, "mask_fixture": false, "active_store": ledger.active_store, "selected_catalog_index": 5, "progression": ledger.progression_view(), "purchases": setup_purchases, "note": "Only starting catalog count/budget are fixtures. Current paid rules use dry brush in Store 1; wet paid jobs are not available in the current authored six-store section. Wide brush and mint checker / leafy / arched / ivory room are genuinely purchased through production methods."})
	audio = root.get_node("GameAudio")
	audio.settings_path = output_dir + "/saves/audio.cfg"
	audio.set_music_enabled(false)
	audio.set_effects_enabled(true)
	root.size = Vector2i(540, 960)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	root.content_scale_size = Vector2i(1080, 1920)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(540, 960)
	started_at = Time.get_datetime_string_from_system(true, true)
	wall_start_usec = Time.get_ticks_usec()
	engine_frame_at_start = Engine.get_process_frames()
	mark("capture_start", {"engine": Engine.get_version_info(), "fps": FPS, "mode": mode, "resumed_session": resumed_session, "native_speed": true, "render_size": [1080, 1920], "window_size": [540, 960], "music": false, "effects": true, "audio_audition": not audio.silent_test, "hud_hidden": false, "input_clock_note": "Only previous input timestamp aligns with 30fps movie delta. Production physics, tool power, mask, reward and animations are unchanged."})
	while not ending:
		await process_frame
		frame += 1
		step_capture()
	finish_capture()

func step_capture() -> void:
	if frame >= 30 * 320:
		abort_capture("Bounded capture reached 320 seconds without a full paid job and next arrival.")
		return
	if not audio.focused or not game.application_focused:
		abort_capture("Game window lost focus; this session is rejected.")
		return
	if mode == "smoke" and frame >= 30 * 12:
		mark("smoke_complete", stats())
		ending = true
		return
	var job: String = game.contract_job_id
	if current_job.is_empty():
		current_job = job
		current_rug = str(game.soil.rug_definition.rug_id)
		mark("job_start", {"rug_definition": game.soil.rug_definition.resource_path, "removal_per_pass": game.soil.rug_definition.removal_per_pass, "tool_width": game.tool_width, "tool_power": game.soil.tool_strength, "wet_recipe": game.wet_recipe, "full_quote": ledger.current_job_full_reward(), "cash": ledger.cash})
		if current_rug != "stillwater_pond" or game.wet_recipe:
			abort_capture("Current paid Stillwater dry job was not selected.")
			return
	elif job != current_job and next_arrival_frame < 0:
		next_arrival_frame = frame
		mark("next_job_arrival", {"new_job_id": job, "new_rug_id": str(game.soil.rug_definition.rug_id)})
		_save_still.call_deferred("next_arrival")
	if next_arrival_frame >= 0 and frame - next_arrival_frame > 30 * 2:
		mark("full_native_exchange_complete", stats())
		ending = true
		return
	var phase: int = game.rug_phase
	if phase != last_phase:
		last_phase = phase
		phase_started = frame
		mark("phase", {"phase": PHASE_NAMES[phase], "progress": stats(), "rug_position": str(game.get_node("RugDisplay").position)})
		if phase == game.RugPhase.CLEANING and completed_jobs.is_empty():
			next_stroke_frame = frame + 18
			_save_still.call_deferred("dirty_pond_arrived")
		if phase == game.RugPhase.VACUUMING:
			pointer_down = false
			stroke_start = -1
			var reward_record: Dictionary = ledger.completed_rewards.get(current_job, {}).duplicate(true)
			var result := {"job_id": current_job, "rug_id": current_rug, "frame": frame, "engine_frame": Engine.get_process_frames(), "full_restoration": game.completed_full_restore, "clearance": game.completed_fraction, "remaining_reward": game.completed_reward, "quoted_full_reward": game.completed_full_quote, "ledger_reward_record": reward_record, "cash": ledger.cash}
			completed_jobs.append(result)
			mark("full_restoration_committed", result)
			if not game.completed_full_restore:
				abort_capture("Native job completed early; full restoration required.")
				return
			DirAccess.copy_absolute(ledger._save_path, output_dir + "/checkpoints/full_restoration_paid.json")
		if phase == game.RugPhase.REVEAL:
			mark("native_clean_reveal", {"full_restoration": game.completed_full_restore})
			_save_still.call_deferred("clean_pond_reveal_start")
	if phase == game.RugPhase.REVEAL and frame - phase_started == 25:
		_save_still.call_deferred("clean_pond_hero")
	if phase == game.RugPhase.DEPARTING:
		var elapsed: int = frame - phase_started
		if not room_saved and elapsed >= 18:
			room_saved = true
			mark("room_pullback", stats())
			_save_still.call_deferred("clean_pond_room_pullback")
		if not window_saved and game.room.window_open_amount >= 0.99:
			window_saved = true
			mark("window_fully_open", {"window_open_amount": game.room.window_open_amount})
			_save_still.call_deferred("room_window_fully_open")
		if not curl_saved and elapsed >= 45:
			curl_saved = true
			mark("native_rug_curl", {"rug_position": str(game.get_node("RugDisplay").position)})
			_save_still.call_deferred("room_rug_curl")
		if not empty_saved and game.get_node("RugDisplay").position.z < -3.8:
			empty_saved = true
			mark("rug_offscreen_room_empty", {"rug_position": str(game.get_node("RugDisplay").position), "window_open_amount": game.room.window_open_amount})
			_save_still.call_deferred("room_empty_after_exit")
	if phase != game.RugPhase.CLEANING or not completed_jobs.is_empty(): return
	if frame % 30 == 0: mark("progress", stats())
	if pointer_down:
		var amount := minf(float(frame - stroke_start) / (stroke_duration * FPS), 1.0)
		var eased := amount * amount * (3.0 - 2.0 * amount)
		move_touch(stroke_from.lerp(stroke_to, eased))
		if not game.brush_dragging and not game.soil.completion_started:
			abort_capture("Actual pointer was rejected during a stroke.")
			return
		if amount >= 1.0:
			release_touch()
			mark("stroke_end", {"stroke": stroke_number, "hero": not hero_done, "hero_pass": hero_pass + 1, "lane": lane_index, "lane_pass": lane_pass + 1, "progress": stats()})
			if not hero_done:
				hero_pass += 1
				if hero_pass >= 10: hero_done = true
			else:
				lane_pass += 1
				if lane_pass >= 11:
					lane_pass = 0
					lane_index += 1
					if lane_index >= LANES.size():
						lane_index = 0
						sweep_round += 1
						if sweep_round >= 2:
							abort_capture("Normal input sweeps did not reach full restoration.")
							return
			next_stroke_frame = frame + 5
	elif frame >= next_stroke_frame:
		stroke_number += 1
		if not hero_done:
			# Every hero pass moves left to right for a matchable five-second clip.
			stroke_from = Vector3(-0.82, 0.067, 0.0)
			stroke_to = Vector3(0.82, 0.067, 0.0)
			stroke_duration = 5.2
		else:
			var reverse := lane_pass % 2 == 1
			stroke_from = Vector3(LANES[lane_index], 0.067, 1.70 if reverse else -1.70)
			stroke_to = Vector3(LANES[lane_index], 0.067, -1.70 if reverse else 1.70)
			stroke_duration = 2.0
		stroke_start = frame
		begin_touch(stroke_from)
		mark("stroke_start", {"stroke": stroke_number, "hero": not hero_done, "hero_pass": hero_pass + 1, "lane": lane_index, "lane_pass": lane_pass + 1, "sweep_round": sweep_round, "local_from": str(stroke_from), "local_to": str(stroke_to), "screen_from": str(touch_position), "screen_to": str(pointer_for(stroke_to)), "duration": stroke_duration, "progress": stats()})
		if not game.brush_dragging:
			abort_capture("Actual screen-touch did not begin. Inspect native HUD bounds.")

func stats() -> Dictionary:
	if not is_instance_valid(game): return {}
	return {"surface": game.soil.surface_clearance(), "unique": game.soil.unique_clearance(), "overall": game.soil.overall_clearance(), "tool": game.selected_tool, "cash": ledger.cash, "water": game.soil.water_clearance(), "extraction": game.soil.extraction_clearance(), "wash_cycle": game.soil.wash_cycle}

func pointer_for(local_point: Vector3) -> Vector2:
	return game.camera.unproject_position(game.soil.rug_node.to_global(local_point)) - game.TOUCH_CONTACT_OFFSET

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
	var milliseconds := roundi(float(frame + 1) * 1000.0 / FPS) - roundi(float(frame) * 1000.0 / FPS)
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

func _save_still(label: String) -> void:
	await RenderingServer.frame_post_draw
	var pixels := root.get_texture().get_image()
	var path := output_dir + "/stills/" + label + ".png"
	var saved := pixels.save_png(path)
	mark("still", {"path": path, "size": str(pixels.get_size()), "success": saved == OK})

func mark(kind: String, detail: Dictionary = {}) -> void:
	var record := {"kind": kind, "frame": frame, "engine_frame": Engine.get_process_frames(), "seconds": float(frame) / FPS, "job_id": current_job, "rug_id": current_rug}
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
	if not is_instance_valid(game): finish_capture()

func finish_capture() -> void:
	if is_instance_valid(game):
		release_touch()
		game.save_contract_progress()
	mark("capture_end", {"success": not failed, "error": error_text, "completed_jobs": completed_jobs, "wall_seconds": float(Time.get_ticks_usec() - wall_start_usec) / 1000000.0})
	var report := {"success": not failed, "error": error_text, "mode": mode, "resumed_session": resumed_session, "started_at_utc": started_at, "native_speed": true, "fps": FPS, "driver_frames": frame, "engine_frame_at_start": engine_frame_at_start, "recording_frame_note": "engine_frame is process index; verify the first rendered frame against AVI when cutting.", "render_size": [1080, 1920], "source_rules": "current six-store paid dry-brush rules", "setup_fixture_only": "catalog index, filming budget; purchased room tier2 and wide brush through production methods", "mask_fixture": false, "production_input": "InputEventScreenTouch/InputEventScreenDrag through root.push_input, one ordinary movement per rendered frame", "clock_normalization": "Only previous input timestamp aligned with 30fps frame duration; no manual physics, soil strokes, mask or reward writes", "completed_jobs": completed_jobs, "events": events}
	var file := FileAccess.open(output_dir + "/take_manifest.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	if event_file != null: event_file.close()
	quit(1 if failed else 0)
