extends SceneTree
## Disposable playback of the actual completion sequence; no player save.
var game: Node
var record_video := false
var recording := false
var frame_index := 0
var recording_done := false
const FRAME_FOLDER := "res://../art/renders/completion_sequence_frames"

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test for this preview")
		quit(2)
		return
	record_video = "--completion-video" in OS.get_cmdline_user_args()
	call_deferred("run")

func run() -> void:
	var state := root.get_node("ShopState")
	state._save_path = "res://../art/completion_preview_test_%d.json" % OS.get_process_id()
	state.reset_progress()
	state.cash = 50000
	for id: String in ["floor", "plants", "window", "railings"]:
		for tier in range(15): state.buy_room_upgrade(id)
	root.size = Vector2i(540, 750)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	root.title = "Carpet Cleaner · Completion sequence (test save)"
	while game.rug_phase != game.RugPhase.CLEANING:
		await process_frame
	if record_video:
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAME_FOLDER)) != OK:
			push_error("Could not prepare completion preview frames")
			quit(1)
			return
		recording = true
		capture_frames.call_deferred()
	await create_timer(0.5).timeout
	game.soil.remaining = 0
	game.soil.surface_coverage_total = 0.0
	game.update_contract_status()
	await process_frame
	while game.rug_phase != game.RugPhase.CLEANING:
		await process_frame
	await create_timer(0.5).timeout
	if record_video:
		recording = false
		while not recording_done: await process_frame
		print("COMPLETION_VIDEO_FRAMES ", frame_index)
		game.free()
		root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		await create_timer(0.06).timeout
		DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
		quit()

func capture_frames() -> void:
	while recording:
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(FRAME_FOLDER + "/frame_%04d.png" % frame_index) != OK:
			recording = false
			quit(1)
			break
		frame_index += 1
	recording_done = true
