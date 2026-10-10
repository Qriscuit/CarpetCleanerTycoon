extends SceneTree
## Restoration payoff, touch isolation and durable payout checks; renderer captures when available.
## Run through tools/run_godot.ps1 with -- --shop-test; never use the player save.
var checks := 0
var failures := 0
var game: Node
var state: Node
var finished_completion_cues := 0

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Completion reveal validation requires -- --shop-test")
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 2) -> void:
	for _tick in count:
		foreground_fixture()
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		foreground_fixture()

func foreground_fixture() -> void:
	# Desktop window focus can change while these isolated rendered fixtures
	# run. Explicit background checks below stay synchronous until FocusIn.
	if is_instance_valid(game) and is_instance_valid(game.game_audio) and (not game.application_focused or not game.game_audio.focused):
		game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	check(root.get_texture().get_image().save_png("res://../art/renders/completion_" + label + ".png") == OK, "Actual completion preview saves: " + label)

func touch(point: Vector2, down: bool, canceled: bool = false, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = down
	event.canceled = canceled
	root.push_input(event, true)

func tap(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	touch(point, true)
	touch(point, false)

func wait_cleaning() -> void:
	for _tick in 350:
		if game.rug_phase == game.RugPhase.CLEANING:
			return
		await create_timer(0.02).timeout
	check(false, "Replacement rug becomes ready within seven seconds")

func finish_vacuum() -> void:
	for _tick in 140:
		if game.soil.vacuum_complete:
			break
		game.soil._physics_process(1.0 / 60.0)
	await frames()

func all_surface_dust(expected: float) -> bool:
	for material: ShaderMaterial in game.soil.surface_materials:
		if not is_equal_approx(float(material.get_shader_parameter("dust_strength")), expected):
			return false
	return true

func set_actual_cleanliness(amount: float) -> void:
	foreground_fixture()
	# Keep a real compact residual patch. Full acceptance may polish its
	# appearance, but must preserve these earned masks and payout inputs.
	var soil: Node = game.soil
	soil.active.clear()
	soil.timed_debris.clear()
	soil.floor_debris.clear()
	soil.moving.fill(false)
	soil.credited.fill(true)
	soil.remaining = 0
	soil.surface_coverage_total = 0.0
	var remaining_dirt: float = float(soil.surface_pixel_count) * (1.0 - amount)
	for y in soil.MASK_SIZE.y:
		for x in soil.MASK_SIZE.x:
			var index: int = y * soil.MASK_SIZE.x + x
			var value := 0.0
			if soil.surface_pixels[index] == 1 and remaining_dirt > 0.0:
				value = minf(1.0, remaining_dirt)
				remaining_dirt -= value
				soil.surface_coverage_total += value
			soil.coverage_values[index] = value
			soil.mask.set_pixel(x, y, Color(value, value, value))
	soil.mask_changed = true
	soil._process(0.0)
	game.update_contract_status()

func enter_rug(animated: bool = true) -> void:
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = animated
	root.add_child(game)
	current_scene = game
	await frames()
	await wait_cleaning()

func run() -> void:
	state = root.get_node("ShopState")
	state._save_path = "res://../art/completion_reveal_test_%d.json" % OS.get_process_id()
	state.set_process(false)
	check(state.reset_progress(), "Isolated completion ledger resets")
	root.size = Vector2i(390, 844)
	await enter_rug()
	game.game_audio.completion.finished.connect(func(): finished_completion_cues += 1)
	var scene_id: int = game.get_instance_id()
	var pool_id: int = game.soil.batch.get_instance_id()
	var first_job: String = game.contract_job_id
	var original_mask: PackedByteArray = game.soil.mask.get_data().duplicate()
	var original_buffer: PackedFloat32Array = game.soil.batch.buffer.duplicate()
	var original_count: int = game.soil.batch.visible_instance_count
	var starting_dust_strength: float = game.soil.rug_definition.dust_strength
	set_actual_cleanliness(0.99)
	var earned_mask: PackedByteArray = game.soil.mask.get_data().duplicate()
	await frames()
	check(game.rug_phase == game.RugPhase.VACUUMING, "Full restoration vacuums before the clean reveal")
	check(is_equal_approx(game.completed_fraction, 0.99) and game.completed_full_restore, "Full classification preserves the actual 99 percent result")
	check(game.state_label.text == "99%" and game.progress_bar.value < 100.0, "Accepting a job does not invent a 100 percent result")
	check(state.cash == 40 and state.manual_jobs == 1 and state.active_job_id != first_job, "Full payout and replacement job are durable before presentation")
	game.finish_rug()
	game.finish_rug()
	check(state.cash == 40 and state.manual_jobs == 1, "Repeated finish requests cannot grant another reward")
	game.soil._physics_process(game.soil.VACUUM_SECONDS * 0.5)
	var fading_dust: float = game.soil.surface_materials[0].get_shader_parameter("dust_strength")
	check(fading_dust > 0.0 and fading_dust < starting_dust_strength, "Accepted full restoration gradually fades the residual soil during suction")
	await finish_vacuum()
	var reveal: Node = game.completion_reveal
	check(game.rug_phase == game.RugPhase.REVEAL and reveal.active, "Suction enters the dedicated reveal before departure")
	check(reveal.remaining > 1.5 and reveal.remaining <= 2.4, "Full restoration gets a short automatic reveal")
	# A cold renderer can take longer than this deliberately short cue. Its
	# natural finished event still proves playback occurred exactly once.
	var completion_played: bool = (game.game_audio.completion.playing and finished_completion_cues == 0) or (not game.game_audio.completion.playing and finished_completion_cues == 1)
	if not completion_played:
		print("COMPLETION_CUE_DIAGNOSTIC focused=%s effects=%s context=%s finished=%d" % [game.game_audio.focused, game.game_audio.effects_enabled, game.game_audio.context, finished_completion_cues])
	check(completion_played, "Full restoration plays the restrained completion cue")
	check(game.soil.batch.visible_instance_count == 0 and not game.brush.visible, "Actual clean result has no tools or leftover airborne dirt obscuring it")
	check(game.get_node("RugDisplay").position.is_equal_approx(Vector3.ZERO), "Revealed carpet remains centered and unrolled")
	check(game.soil.mask.get_data() == earned_mask and game.soil.surface_coverage_total > 0.0, "Full reveal preserves the actual 99 percent coverage data and earned progress")
	check(all_surface_dust(0.0), "Successful full restoration reveals pristine pile, binding and fringe with no residual soil texture")
	for removed: String in ["Heading", "Title", "Detail", "ViewLabel", "ContinueButton"]:
		check(reveal.get_node_or_null("%" + removed) == null, "Completion has no " + removed + " prompt")
	check(reveal.find_children("*", "Button", true, false).size() == 1, "Compare is the only completion button")
	var after_snapshot: Dictionary = game.soil.make_snapshot()
	var after_buffer: PackedFloat32Array = game.soil.batch.buffer.duplicate()
	var ledger_after: Dictionary = state.job_snapshot.duplicate(true)
	reveal.remaining = 30.0
	game.begin_stroke(game.camera.unproject_position(Vector3.ZERO), false)
	check(not game.brush_dragging and game.soil.make_snapshot() == after_snapshot, "Reveal blocks brushing without changing progress")
	await capture("full_after_portrait")
	var compare: Button = reveal.get_node("%CompareButton")
	check(compare.visible and not compare.disabled and compare.text == "Compare", "The small Compare action is the only visible completion caption")
	var point := compare.get_global_rect().get_center()
	touch(point, true)
	await frames()
	check(reveal.comparing, "Holding Compare with a real touch shows before")
	var material: ShaderMaterial = game.soil.surface_materials[0]
	var displayed: Texture2D = material.get_shader_parameter("coverage")
	check(displayed.get_image().get_data() == original_mask and displayed.get_image().get_data() != earned_mask, "Before uses the captured starting coverage rather than a fabricated clean or dirty image")
	check(all_surface_dust(starting_dust_strength), "Full reveal comparison restores the captured starting soil strength on every material")
	check(game.soil.batch.buffer == original_buffer and game.soil.batch.visible_instance_count == original_count, "Before restores the actual starting dirt scatter in the existing render batch")
	check(game.soil.make_snapshot() == after_snapshot and state.job_snapshot == ledger_after, "Before comparison changes neither current progress nor the durable replacement job")
	var held_remaining: float = reveal.remaining
	await create_timer(0.18).timeout
	check(is_equal_approx(reveal.remaining, held_remaining), "Holding before pauses automatic departure")
	await capture("full_before_portrait")
	touch(point, false, true)
	await frames()
	check(not reveal.comparing and material.get_shader_parameter("coverage") == game.soil.mask_texture, "A canceled comparison touch restores the actual after texture")
	check(all_surface_dust(0.0), "Releasing comparison restores the polished full-restoration appearance")
	check(game.soil.batch.buffer == after_buffer and game.soil.make_snapshot() == after_snapshot, "Leaving comparison restores the exact after render buffer without changing gameplay")
	touch(point, true, false, 11)
	touch(point + Vector2(20, 0), true, false, 12)
	check(not reveal.comparing and reveal.active, "A second finger cancels comparison without skipping the reveal")
	touch(point, false, false, 11)
	touch(point + Vector2(20, 0), false, false, 12)
	var background_point: Vector2 = reveal._safe_rect().position + Vector2(2.0, 2.0)
	touch(background_point, true)
	touch(background_point, false, true)
	check(reveal.active and game.rug_phase == game.RugPhase.REVEAL, "A canceled background tap cannot skip the reveal")
	touch(point, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = point + Vector2(40.0, 0.0) * reveal.get_node("Content").scale
	root.push_input(drag, true)
	check(not reveal.comparing and reveal.active, "Dragging off a comparison hold restores after without advancing")
	touch(drag.position, false)
	reveal.remaining = 30.0
	touch(compare.get_global_rect().get_center(), true)
	await frames()
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not reveal.comparing and material.get_shader_parameter("coverage") == game.soil.mask_texture, "Focus loss releases a held comparison and restores after")
	check(all_surface_dust(0.0), "Focus loss restores the polished appearance as well as the after mask")
	var paused_remaining: float = reveal.remaining
	reveal._process(5.0)
	check(reveal.active and is_equal_approx(reveal.remaining, paused_remaining), "Background time cannot advance the completion timer")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	touch(compare.get_global_rect().get_center(), false, true)
	reveal.remaining = 30.0
	compare.grab_focus()
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	root.push_input(key, true)
	await frames()
	check(reveal.active and reveal.comparing, "Enter on the focused Compare button holds before instead of skipping")
	key = InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = false
	root.push_input(key, true)
	await frames()
	check(reveal.active and not reveal.comparing, "Releasing Enter restores after and keeps the reveal open")
	var layouts := [
		{"size": Vector2i(320, 568)}, {"size": Vector2i(568, 320)},
		{"size": Vector2i(390, 844)}, {"size": Vector2i(844, 390)},
		{"size": Vector2i(591, 1280), "reference": true},
		{"size": Vector2i(390, 844), "reference": true},
		{"size": Vector2i(844, 390), "reference": true},
		{"size": Vector2i(1080, 2340), "reference": true},
		{"size": Vector2i(2340, 1080), "reference": true},
		{"size": Vector2i(768, 1024)}, {"size": Vector2i(1024, 768)}]
	for example: Dictionary in layouts:
		var size: Vector2i = example.size
		reveal.remaining = 30.0
		if size == Vector2i(320, 568): touch(compare.get_global_rect().get_center(), true)
		root.content_scale_size = Vector2i(720, 1000) if example.get("reference", false) else size
		root.size = size
		await frames()
		if size == Vector2i(320, 568):
			check(not reveal.comparing and reveal._pointer == -1 and material.get_shader_parameter("coverage") == game.soil.mask_texture, "Resizing cancels a held comparison and releases its pointer safely")
			touch(point, false, true)
		var units_per_pixel := root.get_visible_rect().size / Vector2(root.size)
		reveal.preview_safe_insets = Vector4(10.0 * units_per_pixel.x, 20.0 * units_per_pixel.y, 10.0 * units_per_pixel.x, 16.0 * units_per_pixel.y)
		game.hud.preview_safe_insets = reveal.preview_safe_insets
		reveal._layout()
		await frames()
		var visible_rect: Rect2 = reveal._safe_rect()
		var button_rect: Rect2 = compare.get_global_rect()
		var design_scale: float = reveal.get_node("Content").scale.x
		check(visible_rect.grow(0.1).encloses(button_rect), "Compare fits the inset safe area at " + str(size))
		if reveal.is_landscape_layout():
			check(absf(visible_rect.end.x - button_rect.end.x - 16.0 * design_scale) < 0.1, "Landscape Compare keeps right-edge breathing room at " + str(size))
		else:
			check(absf(button_rect.get_center().x - visible_rect.get_center().x) < 0.1, "Portrait Compare remains centered at " + str(size))
		check(absf(visible_rect.end.y - button_rect.end.y - 16.0 * design_scale) < 0.1, "Compare has consistent bottom breathing room at " + str(size))
		check(button_rect.size.y / units_per_pixel.y >= 43.9, "Compare retains a physical44-pixel touch target at " + str(size))
		check(compare.get_theme_font_size("font_size") == 20, "Compare typography stays authored and readable at " + str(size))
		var rug_space: Rect2 = reveal.rug_view_rect()
		check(visible_rect.encloses(rug_space) and not rug_space.intersects(button_rect), "Room view remains safe and separate from Compare at " + str(size))
		if reveal.is_landscape_layout():
			check(absf(button_rect.position.x - rug_space.end.x - 16.0 * design_scale) < 0.1, "A horizontal gutter separates landscape Compare from the room at " + str(size))
			check(absf(visible_rect.end.y - rug_space.end.y - 16.0 * design_scale) < 0.1, "Landscape room retains the full safe height at " + str(size))
		else:
			check(absf(button_rect.position.y - rug_space.end.y - 16.0 * design_scale) < 0.1, "A vertical gutter separates portrait Compare from the rug at " + str(size))
		reveal.show_reveal(true, 0.995, true, 1e60, "Before this session")
		await frames()
		check(compare.text == "Compare" and compare.get_global_rect().is_equal_approx(button_rect), "Even maximum rewards do not expand the completion UI")
		reveal.show_reveal(true, 0.995, true, 40)
		reveal.remaining = 30.0
		await create_timer(0.46).timeout
		game._frame_workshop_camera()
		var cleaning_camera_size: float = game.camera.size
		game._set_completion_zoom(1.0)
		await frames()
		if reveal.is_landscape_layout():
			var room_bounds: AABB = game._workshop_geometry_bounds()
			for corner in 8:
				check(rug_space.grow(0.1).has_point(game.camera.unproject_position(room_bounds.get_endpoint(corner))), "Landscape reveal shows the entire room beside Compare at " + str(size))
			check(game.camera.size <= cleaning_camera_size * 1.01, "Landscape reveal preserves the cleaning carpet size at " + str(size))
		for x: float in [-1.06, 1.06]:
			for z: float in [-1.72, 1.72]:
				check(rug_space.has_point(game.camera.unproject_position(Vector3(x, 0.08, z))), "Full design and fringe stay in the reveal frame at " + str(size))
		point = compare.get_global_rect().get_center()
		touch(point, true)
		var timer_before: float = reveal.remaining
		await frames()
		check(reveal.comparing and is_equal_approx(timer_before, reveal.remaining), "Phone touch holds comparison and pauses the timer at " + str(size))
		if example.get("reference", false): await capture("compare_before_%dx%d_720canvas" % [size.x, size.y])
		touch(point, false)
		check(not reveal.comparing and reveal.active, "Phone release restores after without skipping at " + str(size))
		await capture("compare_after_%dx%d%s" % [size.x, size.y, "_720canvas" if example.get("reference", false) else ""])
	reveal.preview_safe_insets = Vector4.ZERO
	game.hud.preview_safe_insets = Vector4.ZERO
	reveal._layout()
	var old_job: String = game.contract_job_id
	reveal.continue_now()
	game.skip_completion_reveal()
	game.skip_completion_reveal()
	check(not reveal.active and game.rug_phase == game.RugPhase.DEPARTING, "Programmatic continuation runs once and repeated calls cannot start another transition")
	check(state.cash == 40 and state.manual_jobs == 1, "Skip is cosmetic and never pays again")
	await wait_cleaning()
	check(game.get_instance_id() == scene_id and game.soil.batch.get_instance_id() == pool_id and game.contract_job_id != old_job, "Reveal retains the scene and dirt pool while moving to one replacement rug")
	check(not game.brush_dragging, "The comparison release cannot become a brush gesture on the replacement rug")
	check(all_surface_dust(game.soil.rug_definition.dust_strength), "A replacement rug restores its authored soil strength after full-restoration polish")
	# Failed writes must not start a payoff or conceal the current result.
	state._save_enabled = false
	set_actual_cleanliness(0.75)
	game.finish_rug()
	check(game.rug_phase == game.RugPhase.CLEANING and not reveal.active and not game.soil.completion_started, "Failed completion commit leaves the rug playable without a reveal")
	check(state.cash == 40 and state.manual_jobs == 1 and game.finish_button.visible, "Failed completion can be retried without awarding a payout")
	check(all_surface_dust(game.soil.rug_definition.dust_strength), "A failed early finish leaves the visible dirt unchanged")
	state._save_enabled = true
	var cues_before_early: int = finished_completion_cues
	game.finish_rug()
	check(not game.completed_full_restore and is_equal_approx(game.completed_fraction, 0.75) and game.state_label.text == "75%", "Early finish retains its actual 75 percent result")
	await finish_vacuum()
	check(reveal.active and compare.text == "Compare" and compare.visible, "Early finish uses the same restrained comparison action")
	check(not game.game_audio.completion.playing and finished_completion_cues == cues_before_early, "Early finish does not play the full-restoration cue")
	check(reveal.remaining <= 1.1 and state.cash == 60 and state.manual_jobs == 2, "Early finish has a shorter hold and its twenty-coin cleaning payout")
	check(all_surface_dust(game.soil.rug_definition.dust_strength) and game.soil.surface_coverage_total > 0.0, "Early finish retains residual soil instead of receiving the full-restoration polish")
	reveal.remaining = 30.0
	var early_mask: PackedByteArray = game.soil.mask.get_data().duplicate()
	reveal.set_comparing(true)
	await frames()
	check(all_surface_dust(game.soil.rug_definition.dust_strength), "Early comparison retains the original starting soil strength")
	reveal.set_comparing(false)
	await frames()
	check(all_surface_dust(game.soil.rug_definition.dust_strength) and game.soil.mask.get_data() == early_mask, "Early comparison returns to the actual remaining dirt without changing its mask")
	await capture("early_finish")
	reveal.remaining = 0.02
	await wait_cleaning()
	check(not reveal.active and state.cash == 60, "Untouched reveal advances automatically without extra taps or payout")
	# A clean reveal is already paid: Back must leave the reserved job intact.
	state._save_enabled = false
	set_actual_cleanliness(0.99)
	await frames()
	check(game.rug_phase == game.RugPhase.CLEANING and not game.soil.completion_started and not reveal.active, "A failed full-restoration commit stays playable and never starts the visual payoff")
	check(all_surface_dust(game.soil.rug_definition.dust_strength) and game.soil.surface_coverage_total > 0.0, "Failed full-restoration save does not fade or remove the residual soil")
	check(state.cash == 60 and state.manual_jobs == 2, "Failed full-restoration save awards no reward")
	state._save_enabled = true
	game.finish_rug()
	await frames()
	await finish_vacuum()
	check(all_surface_dust(0.0), "A successful retry completes the full-restoration polish")
	reveal.remaining = 30.0
	var reserved_job: String = state.active_job_id
	check(state.cash == 100 and state.manual_jobs == 3, "Another full result commits only its own reward")
	reveal.set_comparing(true)
	game.back()
	await frames()
	check(current_scene.scene_file_path == "res://scenes/production/floating_home.tscn" and state.active_job_id == reserved_job, "Back during comparison reaches the shop with its reserved next job")
	check(state.cash == 100 and state.manual_jobs == 3 and state.job_snapshot.is_empty(), "Leaving the reveal does not overwrite the reserved job with the old rug or repay it")
	change_scene_to_file("res://scenes/production/rug_cleaning.tscn")
	await frames()
	game = current_scene
	await wait_cleaning()
	check(game.contract_job_id == reserved_job and game.progress_fraction == 0.0 and not game.completion_reveal.active, "Re-entry starts the fresh reserved rug without replaying its predecessor's reveal")
	check(state.cash == 100 and state.manual_jobs == 3, "Re-entry never duplicates a committed completion")
	check(all_surface_dust(game.soil.rug_definition.dust_strength), "Re-entry restores dirt on the reserved rug instead of leaking the old polished appearance")
	game.free()
	current_scene = null
	state.set_process(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("COMPLETION_REVEAL_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
