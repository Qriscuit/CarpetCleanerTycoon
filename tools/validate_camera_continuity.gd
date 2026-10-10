extends SceneTree
## Actual rendered camera continuity through a complete rug exchange.
## Run at fixed 30 FPS with the pinned Mono wrapper and -- --shop-test.

const MARKERS := [Vector3(-1.3, 0.1, -1.9), Vector3(1.3, 0.1, -1.9), Vector3(0, 0, 1.9)]
const MAX_FRAME_TRAVEL_SHARE := 0.16
const MAX_BOUNDARY_DRIFT := 0.002
const MAX_FRAME_SIZE_CHANGE := 0.04
const RoomUpgrades := preload("res://scripts/room_upgrades.gd")
var game: Node
var state: Node
var checks := 0
var failures := 0
var samples: Array[Dictionary] = []

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Camera continuity validation requires -- --shop-test")
		quit(2)
		return
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func frame() -> void:
	await process_frame
	# This samples camera motion rather than application focus. Keep the
	# disposable run moving when another validation window takes focus.
	if is_instance_valid(game) and not game.application_focused:
		game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func wait_cleaning() -> void:
	for _tick: int in 450:
		if game.rug_phase == game.RugPhase.CLEANING:
			return
		await frame()
	check(false, "The replacement rug becomes playable")

func sample() -> void:
	var points: Array[Vector2] = []
	for marker: Vector3 in MARKERS:
		points.append(game.camera.unproject_position(marker))
	var material: ShaderMaterial = game.soil.surface_materials[0]
	if game.rug_phase != game.RugPhase.CLEANING:
		game.begin_stroke(game.camera.unproject_position(Vector3.ZERO), false)
	samples.append({
		"phase": game.rug_phase,
		"job": game.contract_job_id,
		"points": points,
		"size": game.camera.size,
		"position": game.get_node("RugDisplay").position,
		"roll": float(material.get_shader_parameter("roll_amount")),
		"direction": float(material.get_shader_parameter("roll_direction")),
		"input_allowed": game.brush_dragging,
	})

func finish_rug() -> void:
	game.soil.remaining = 0
	game.soil.surface_coverage_total = 0.0
	game.update_contract_status()
	await frame()
	for _tick: int in 150:
		if game.soil.vacuum_complete:
			break
		game.soil._physics_process(1.0 / 60.0)
	await frame()
	check(game.rug_phase == game.RugPhase.REVEAL, "The completed rug reaches its design reveal")
	game.completion_reveal.remaining = 30.0

func validate_exchange(label: String, window_size: Vector2i, early_skip: bool) -> void:
	root.size = window_size
	await frame()
	game.frame_carpet()
	await frame()
	var initial_camera: Transform3D = game.camera.global_transform
	var initial_size: float = game.camera.size
	var original_job: String = game.contract_job_id
	var scene_id: int = game.get_instance_id()
	var pool_id: int = game.soil.batch.get_instance_id()
	await finish_rug()
	for _tick: int in (2 if early_skip else 20):
		await frame()
	check(game.room.get_node("Window/Tier3").visible, "%s: the most upgraded window is active" % label)
	samples.clear()
	sample()
	game.skip_completion_reveal()
	sample()
	for _tick: int in 400:
		await frame()
		sample()
		if game.contract_job_id != original_job and game.rug_phase == game.RugPhase.CLEANING:
			break
	var normalization: float = minf(game.get_viewport().get_visible_rect().size.x, game.get_viewport().get_visible_rect().size.y)
	var max_drift := 0.0
	var total_camera_travel := 0.0
	var max_size_change := 0.0
	var max_boundary_drift := 0.0
	var max_drift_detail := ""
	var saw_outgoing_curl := false
	var saw_outgoing_travel := false
	var saw_incoming_roll := false
	var saw_incoming_unroll := false
	var input_unlocked_early := false
	var outgoing_finished_before_new_job := true
	for index: int in samples.size():
		var now: Dictionary = samples[index]
		if now.job == original_job:
			if now.roll > 0.05 and now.roll < 0.95 and now.direction > 0:
				saw_outgoing_curl = true
			if now.position.z < -2.0:
				saw_outgoing_travel = true
		else:
			if now.phase == game.RugPhase.ARRIVING and now.roll > 0.95 and now.direction < 0:
				saw_incoming_roll = true
			if now.phase == game.RugPhase.ARRIVING and now.roll > 0.05 and now.roll < 0.95 and now.direction < 0:
				saw_incoming_unroll = true
		if now.phase != game.RugPhase.CLEANING and now.input_allowed:
			input_unlocked_early = true
		if index == 0: continue
		var before: Dictionary = samples[index - 1]
		var drift := 0.0
		for marker_index: int in MARKERS.size():
			drift = maxf(drift, now.points[marker_index].distance_to(before.points[marker_index]) / normalization)
		total_camera_travel += drift
		if drift > max_drift:
			max_drift = drift
			max_drift_detail = "phase %s -> %s, job changed %s, sample %d" % [before.phase, now.phase, before.job != now.job, index]
		max_size_change = maxf(max_size_change, absf(now.size - before.size) / before.size)
		if now.phase != before.phase or now.job != before.job:
			max_boundary_drift = maxf(max_boundary_drift, drift)
		if now.job != before.job and before.position.z >= -2.0:
			outgoing_finished_before_new_job = false
	var maximum_travel_share := max_drift / maxf(total_camera_travel, 0.001)
	print("CAMERA_CONTINUITY %s: maximum marker drift %.5f (%s), phase-boundary drift %.5f, size change %.5f, maximum frame share %.5f" % [label, max_drift, max_drift_detail, max_boundary_drift, max_size_change, maximum_travel_share])
	# Portrait and landscape have different intentional pan distances. At 30
	# FPS a smooth 0.42-second sine ease cannot spend 16% of the whole exchange's
	# camera travel in a single frame; a camera reset does.
	check(maximum_travel_share < MAX_FRAME_TRAVEL_SHARE, "%s: no rendered frame consumes an abrupt share of the camera travel" % label)
	check(max_size_change < MAX_FRAME_SIZE_CHANGE, "%s: camera size changes smoothly on every rendered frame" % label)
	check(max_boundary_drift < MAX_BOUNDARY_DRIFT, "%s: phase changes and the next-job handoff never snap the camera" % label)
	check(saw_outgoing_curl and saw_outgoing_travel and outgoing_finished_before_new_job, "%s: the completed rug visibly curls and exits before replacement" % label)
	check(saw_incoming_roll and saw_incoming_unroll, "%s: the replacement visibly enters rolled and unrolls" % label)
	check(not input_unlocked_early, "%s: cleaning controls stay locked throughout the exchange" % label)
	check(game.rug_phase == game.RugPhase.CLEANING and game.contract_job_id != original_job, "%s: a new rug becomes playable" % label)
	check(game.camera.global_transform.is_equal_approx(initial_camera) and is_equal_approx(game.camera.size, initial_size), "%s: the camera finishes exactly at its original cleaning frame" % label)
	check(game.get_instance_id() == scene_id and game.soil.batch.get_instance_id() == pool_id, "%s: the same level and dirt pool survive the exchange" % label)
	check(game.get_node("RugDisplay").position.is_zero_approx() and is_zero_approx(float(game.soil.surface_materials[0].get_shader_parameter("roll_amount"))), "%s: the new rug finishes flat and centered" % label)

func run() -> void:
	state = root.get_node("ShopState")
	state._save_path = "res://.godot/camera_continuity_test_%d.json" % OS.get_process_id()
	state.set_process(false)
	check(state.reset_progress(), "The camera test uses an isolated ledger")
	state.cash = 1000000000
	for id: String in ["floor", "plants", "window", "railings", "walls"]:
		for _tier: int in RoomUpgrades.visual_milestones(id, state.active_store)[-1]:
			check(state.buy_room_upgrade(id), "Test fixture upgrades the room with isolated coins")
	root.size = Vector2i(390, 844)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await wait_cleaning()
	await validate_exchange("portrait tier 3", Vector2i(390, 844), false)
	await validate_exchange("portrait early skip", Vector2i(390, 844), true)
	await validate_exchange("landscape tier 3", Vector2i(844, 390), false)
	await validate_exchange("landscape early skip", Vector2i(844, 390), true)
	game.free()
	current_scene = null
	state.set_process(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("CAMERA_CONTINUITY_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
