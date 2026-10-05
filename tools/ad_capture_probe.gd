extends SceneTree
func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		quit(2)
		return
	root.content_scale_size = Vector2i(1080, 1920)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size = Vector2i(540, 960)
	call_deferred("run")
func run() -> void:
	var stage = load("res://scenes/production/floating_home.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	root.content_scale_size = Vector2i(1080, 1920)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	await process_frame
	await RenderingServer.frame_post_draw
	print("CAPTURE_VIEWPORT ", root.get_texture().get_size())
	for i in 45:
		await process_frame
	quit()
