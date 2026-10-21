extends SceneTree
## Production audio lifecycle and touch settings, isolated from real saves.
## Run with the pinned wrapper, a renderer, and -- --shop-test.
## Physical audio is muted unless --audition-audio is also explicitly passed.
var checks := 0
var failures := 0
var audio: Node
var game: Node
var home: Control
var voice_ids: Array[int] = []
const CAPTURE_DIR := "res://../art/renders/"

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Audio lifecycle validation requires a renderer and -- --shop-test")
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 2) -> void:
	for _frame in count:
		await process_frame
		await RenderingServer.frame_post_draw

func advance(seconds: float) -> void:
	# Exercise the real gain/envelope code without waiting for wall-clock fades.
	for _step in ceili(seconds / 0.01):
		audio._process(0.01)

func brush_stopped() -> bool:
	return audio.fabric_target == 0.0 and audio.grit_target == 0.0 and not audio.fabric.playing and not audio.grit.playing

func voice_identity() -> Array[int]:
	var result: Array[int] = []
	for child in audio.get_children():
		if child is AudioStreamPlayer:
			result.append(child.get_instance_id())
	return result

func touch(point: Vector2, down: bool, index: int = 0, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.index = index
	event.pressed = down
	event.canceled = canceled
	root.push_input(event, true)

func tap(button: Button, canceled: bool = false) -> void:
	var point := button.get_global_rect().get_center()
	touch(point, true)
	touch(point, false, 0, canceled)

func drag(point: Vector2, index: int = 0) -> void:
	var event := InputEventScreenDrag.new()
	event.position = point
	event.index = index
	root.push_input(event, true)

func mouse_release() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	root.push_input(event, true)

func check_assets_and_envelopes() -> void:
	voice_ids = voice_identity()
	check(voice_ids.size() == 4, "Audio owns exactly four reusable playback voices")
	var expected_frames := [1058400, 176400, 176400]
	var voices: Array[AudioStreamPlayer] = [audio.music, audio.fabric, audio.grit]
	for index in voices.size():
		var stream := voices[index].stream as AudioStreamWAV
		check(stream != null and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 44100, "Runtime voice uses the intended PCM source: " + str(voices[index].name))
		if stream == null: continue
		check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0 and stream.loop_end == expected_frames[index] - 1, "Runtime loop ends at the last valid sample-frame index: " + str(voices[index].name))
		check(stream.data.size() == expected_frames[index] * (4 if index == 0 else 2), "Loop covers all source frames: " + str(voices[index].name))
	audio.set_context("cleaning")
	audio.feed_brush(1.5, 1.0, true)
	advance(0.02)
	check(audio.fabric.playing and audio.grit.playing and audio.fabric_gain > 0.0 and audio.grit_gain > 0.0, "Dirty moving contact activates both fabric and soil voices")
	if audio.silent_test:
		check(audio.fabric.volume_linear == 0.0 and audio.grit.volume_linear == 0.0, "Shop tests exercise playing streams while muting physical output")
	var initial_gain: float = audio.fabric_gain
	check(initial_gain < audio.fabric_target, "Contact enters through a smooth gain attack")
	advance(0.5)
	check(brush_stopped(), "Stationary input times out and releases both loops without a new event")
	audio.feed_brush(1.5, 0.0, false)
	advance(0.02)
	check(audio.fabric.playing and audio.fabric_target > 0.0 and audio.grit_target == 0.0 and not audio.grit.playing, "Clean grooming keeps cloth contact without a soil sound")
	audio.feed_brush(0.0, 1.0, true)
	advance(0.5)
	check(brush_stopped(), "Zero-speed contact cannot hold a brush sound open")
	audio.set_context("home")
	audio.feed_brush(1.5, 1.0, true)
	advance(0.5)
	check(brush_stopped() and audio.music.playing, "Home music does not accept stray brush contact")
	check(voice_identity() == voice_ids, "Repeated contacts reuse the original four playback nodes")

func check_completion_lifecycle() -> void:
	var stream := audio.completion.stream as AudioStreamWAV
	check(stream != null and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 44100 and not stream.stereo, "Completion uses the intended mono PCM16 source")
	if stream != null:
		check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and stream.data.size() == 37044 * 2, "Completion is a complete 0.84-second one-shot, never a loop")
	audio.set_context("cleaning")
	check(audio.play_completion() and audio.completion.playing, "A restoration event starts the completion cue")
	check(not audio.play_completion(), "Duplicate event during the active cue cannot restart it")
	if audio.silent_test:
		check(audio.completion.volume_linear == 0.0, "Shop validation mutes the completion cue's physical output")
	# A one-shot must actually finish through AudioStreamPlayer, rather than
	# relying on a manual stop or the gain-envelope simulation used above.
	await create_timer(1.1).timeout
	check(not audio.completion.playing, "Completion reaches its own ending without looping")
	audio.play_completion()
	audio.set_effects_enabled(false)
	check(not audio.completion.playing and not audio.play_completion(), "Effects mute immediately stops and blocks completion playback")
	audio.set_effects_enabled(true)
	check(not audio.completion.playing, "Unmuting does not replay a stale completion event")
	audio.play_completion()
	audio.set_context("off")
	check(not audio.completion.playing and not audio.play_completion(), "Inactive context immediately stops and blocks the cue")
	audio.set_context("cleaning")
	audio.play_completion()
	audio._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not audio.completion.playing and not audio.play_completion(), "Focus loss stops the cue and background events cannot restart it")
	audio._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not audio.completion.playing, "Focus return does not replay a stale completion event")
	audio.play_completion()
	audio._notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	check(not audio.completion.playing and not audio.play_completion(), "Application pause also stops and blocks the cue")
	audio._notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	check(not audio.completion.playing and voice_identity() == voice_ids, "Resume retains all four voices without restarting the cue")
	audio.set_context("off")

func clean_surface_fixture() -> void:
	var soil: Node = game.soil
	# Suppress automatic transitions before publishing the clean mask fixture.
	game.auto_finish_queued = true
	soil.completion_started = false
	soil.automatic_completion_enabled = false
	soil.active.clear()
	soil.floor_debris.clear()
	soil.timed_debris.clear()
	soil.recycled.fill(true)
	soil.growth.fill(0.0)
	soil.coverage_values.fill(0.0)
	soil.surface_coverage_total = 0.0
	soil.mask.fill(Color.BLACK)
	soil.mask_changed = true
	soil._process(0.0)
	soil.set_physics_process(false)

func screen_at(world: Vector3, for_touch: bool = false) -> Vector2:
	var result: Vector2 = game.camera.unproject_position(world)
	return result - game.TOUCH_CONTACT_OFFSET if for_touch else result

func brush_move() -> void:
	game.begin_stroke(screen_at(Vector3(0.0, 0.067, -0.3)), false)
	game.move_brush_to_screen(screen_at(Vector3(0.0, 0.067, 0.3)), false)
	advance(0.02)

func check_workshop_lifecycle() -> void:
	game = (load("res://scenes/test/rug_cleaning_gym.tscn") as PackedScene).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frames(4)
	game.soil.configure_rug(load("res://resources/rugs/mint_meadow.tres"))
	game.soil.automatic_completion_enabled = false
	game.set_process(false)
	game.soil.set_physics_process(false)
	check(audio.context == "cleaning", "Entering the actual workshop selects its audio context")
	game.begin_stroke(screen_at(Vector3(0.0, 0.067, -0.3)), false)
	check(audio.fabric_target == 0.0, "Brush placement alone does not scrape")
	game.move_brush_to_screen(screen_at(Vector3(0.0, 0.067, 0.3)), false)
	advance(0.02)
	check(audio.fabric.playing and audio.grit.playing, "Production brush input feeds dirt removal into both audio layers")
	mouse_release()
	advance(0.5)
	check(not game.brush_dragging and brush_stopped(), "Mouse release stops the real workshop gesture and its sound")
	game.begin_stroke(screen_at(Vector3(1.7, 0.0, -0.2)), false)
	game.move_brush_to_screen(screen_at(Vector3(1.7, 0.0, 0.2)), false)
	advance(0.02)
	check(audio.fabric_target == 0.0 and audio.grit_target == 0.0, "A real sweep on bare floor produces no carpet-brushing sound")
	game.end_stroke()
	clean_surface_fixture()
	brush_move()
	check(audio.fabric.playing and audio.fabric_target > 0.0 and audio.grit_target == 0.0, "Actual already-clean carpet remains audible without invented soil removal")
	# Dry gym deliberately rejects non-brush tools. Exercise the actual route
	# from brushing to another tool instead of bypassing that selection policy.
	game.select_tool(1)
	check(game.selected_tool == 0 and game.brush_dragging, "Unavailable dry-gym tool selection correctly leaves the active brush unchanged")
	game.select_rug(1)
	advance(0.5)
	check(game.selected_tool == 2 and not game.brush_dragging and brush_stopped(), "Switching to the wet exercise equips the hose and releases previous brush audio")
	game.select_rug(0)
	clean_surface_fixture()
	var start := screen_at(Vector3(0.0, 0.067, -0.3), true)
	var finish := screen_at(Vector3(0.0, 0.067, 0.3), true)
	touch(start, true, 3)
	drag(finish, 3)
	advance(0.02)
	check(game.brush_dragging and audio.fabric_target > 0.0, "Real touch motion starts cloth contact")
	touch(finish + Vector2(25, 0), true, 4)
	advance(0.5)
	check(not game.brush_dragging and brush_stopped(), "A second finger cancels the stroke and releases its audio")
	touch(finish, false, 3)
	touch(finish + Vector2(25, 0), false, 4)
	touch(start, true, 3)
	drag(finish, 3)
	advance(0.02)
	touch(finish, false, 3, true)
	advance(0.5)
	check(not game.brush_dragging and brush_stopped(), "Canceled owning touch also releases the audio")
	brush_move()
	audio._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not game.brush_dragging and brush_stopped() and not audio.music.playing and not audio.completion.playing, "Application focus loss immediately silences all four voices")
	audio.feed_brush(1.5, 1.0, true)
	advance(0.1)
	check(brush_stopped() and not audio.music.playing, "Background input cannot restart playback")
	audio._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	advance(0.1)
	check(audio.music.playing and brush_stopped(), "Focus return resumes allowed music without replaying stale contact")
	brush_move()
	game.free()
	current_scene = null
	advance(3.0)
	check(audio.context == "off" and brush_stopped() and not audio.music.playing, "Leaving the workshop clears contact and settles every voice to silence")
	check(voice_identity() == voice_ids, "Workshop gestures, cancellation and exit do not allocate more audio voices")

func check_home_settings() -> void:
	home = (load("res://scenes/production/floating_home.tscn") as PackedScene).instantiate()
	root.add_child(home)
	current_scene = home
	home.animate_shop = false
	await frames(3)
	advance(0.3)
	tap(home.get_node("%Settings"))
	await frames()
	var music_toggle: Button = home.get_node("%MusicToggle")
	var effects_toggle: Button = home.get_node("%EffectsToggle")
	check(home.get_node("%SettingsSheet").visible and music_toggle.button_pressed and effects_toggle.button_pressed, "Home exposes the current independent music and effects preferences")
	tap(music_toggle, true)
	check(audio.music_enabled and music_toggle.button_pressed, "Canceled touch cannot change music preference")
	tap(effects_toggle, true)
	check(audio.effects_enabled and effects_toggle.button_pressed, "Canceled touch cannot change effects preference")
	tap(music_toggle)
	check(not audio.music_enabled and not music_toggle.button_pressed and not audio.music.playing and audio.effects_enabled, "Music touch toggle stops music without disabling effects")
	tap(effects_toggle)
	check(not audio.effects_enabled and not effects_toggle.button_pressed and not audio.music_enabled, "Effects touch toggle independently disables game sound effects")
	var saved := ConfigFile.new()
	check(saved.load(audio.settings_path) == OK and saved.get_value("audio", "music", true) == false and saved.get_value("audio", "effects", true) == false, "Touch preferences are persisted in the isolated test configuration")
	audio.music_enabled = true
	audio.effects_enabled = true
	audio.load_settings()
	check(not audio.music_enabled and not audio.effects_enabled, "Reloading persisted preferences restores both muted settings")
	audio.set_context("cleaning")
	audio.feed_brush(1.5, 1.0, true)
	advance(0.2)
	check(brush_stopped() and not audio.music.playing, "Saved mute choices prevent playback even with valid contact")
	audio.set_context("home")
	tap(music_toggle)
	tap(effects_toggle)
	advance(0.3)
	check(audio.music_enabled and audio.effects_enabled and audio.music.playing, "Both controls can re-enable their audio without recreating voices")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(844, 390)]:
		root.size = dimensions
		# Touch release deliberately enlarges a control for 0.22 seconds. Static
		# row containment is evaluated after that feedback returns to rest.
		await create_timer(0.3).timeout
		await frames(3)
		var panel: Control = home.get_node("%SettingsPanel")
		var row: Control = home.get_node("%AudioToggles")
		check(home._safe_rect().encloses(panel.get_global_rect()), "Audio settings panel fits " + str(dimensions))
		check(panel.get_global_rect().encloses(row.get_global_rect()) and row.get_global_rect().encloses(music_toggle.get_global_rect()) and row.get_global_rect().encloses(effects_toggle.get_global_rect()), "Music and effects controls fit inside their settings row at " + str(dimensions))
		check(not music_toggle.get_global_rect().intersects(effects_toggle.get_global_rect()), "Audio touch targets do not overlap at " + str(dimensions))
		var filename := "audio_settings_%dx%d.png" % [dimensions.x, dimensions.y]
		check(root.get_texture().get_image().save_png(CAPTURE_DIR + filename) == OK, "Capture " + filename)
		print("AUDIO_CAPTURE ", ProjectSettings.globalize_path(CAPTURE_DIR + filename))
	tap(home.get_node("%ResetProgress"))
	await frames()
	check(not home.get_node("%AudioToggles").visible, "Reset confirmation hides unrelated audio controls")
	home._back()
	await frames()
	check(home.get_node("%AudioToggles").visible and music_toggle.button_pressed and effects_toggle.button_pressed, "Canceling reset restores the existing audio choices")
	home.free()
	current_scene = null
	advance(3.0)
	check(audio.context == "off" and not audio.music.playing and brush_stopped(), "Leaving home does not leave music playing in an inactive context")
	check(voice_identity() == voice_ids, "Settings, screen changes and scene changes retain exactly the original four voices")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	root.size = Vector2i(390, 844)
	audio = root.get_node("GameAudio")
	audio.set_process(false)
	check(str(audio.settings_path).begins_with("res://.godot/audio_test_") and not str(audio.settings_path).begins_with("user://"), "Validation cannot write the player's real audio preferences")
	audio.set_music_enabled(true)
	audio.set_effects_enabled(true)
	audio.focused = true
	var state := root.get_node("ShopState")
	state.set_process(false)


	var saved_state: Dictionary = state._capture_state().duplicate(true)
	check_assets_and_envelopes()
	await check_completion_lifecycle()
	await check_workshop_lifecycle()
	await check_home_settings()
	check(state._capture_state() == saved_state, "Audio and settings validation leave paid progress and cash unchanged")
	var cleanup := DirAccess.remove_absolute(ProjectSettings.globalize_path(audio.settings_path))
	check(cleanup == OK or cleanup == ERR_FILE_NOT_FOUND, "Remove only this process's isolated audio preference fixture")
	print("GAME AUDIO: %d checks, %d failures; four fixed voices, completion and input lifecycle, isolated settings and phone-sized captures" % [checks, failures])
	quit(0 if failures == 0 else 1)
