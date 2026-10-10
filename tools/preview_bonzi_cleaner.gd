extends SceneTree
## Disposable interactive Bonzi workshop. Required: -- --shop-test.
## Add --bonzi-capture to save the full workshop and model detail, then exit.

const CLEANING_SCENE := preload("res://scenes/production/rug_cleaning.tscn")
const STEP := 0.05
const CAPTURE_SECONDS := 70.0

var game: Node
var ledger: Node
var save_path := ""
var capture_mode := false
var closing := false


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Bonzi preview requires -- --shop-test to protect player progress.")
		quit(2)
		return
	capture_mode = "--bonzi-capture" in OS.get_cmdline_user_args()
	auto_accept_quit = false
	root.close_requested.connect(close_preview)
	call_deferred("run")


func settle() -> void:
	await process_frame
	await process_frame


func run() -> void:
	if capture_mode and DisplayServer.get_name() == "headless":
		push_error("Use a graphical renderer for Bonzi captures.")
		await close_preview(2)
		return
	ledger = root.get_node("ShopState")
	ledger.set_process(false)
	ledger._test_ticks_msec = 1000
	ledger._test_unix_time = 1791471600.0
	save_path = ProjectSettings.globalize_path("res://.godot/bonzi_preview_%d.json" % OS.get_process_id())
	ledger._save_path = save_path
	if not ledger.reset_progress():
		push_error("Could not create the disposable Bonzi preview save.")
		await close_preview(1)
		return
	# Open the real three-job gate and buy Bonzi through the normal ledger.
	for job_index in 3:
		var job: String = ledger.start_job()
		if job.is_empty() or ledger.complete_and_start_next_job(job, {"unique_clearance": 1.0, "surface_clearance": 1.0}).is_empty():
			push_error("Could not complete Bonzi preview fixture commission %d." % (job_index + 1))
			await close_preview(1)
			return
	ledger.cash = 5000
	if not ledger.buy_bonzi_upgrade():
		push_error("Could not purchase Bonzi through its normal unlocked offer.")
		await close_preview(1)
		return
	ledger.cash = 5000
	if not ledger.save_state():
		push_error("Could not fund the disposable Bonzi preview.")
		await close_preview(1)
		return
	root.size = Vector2i(648, 900)
	root.title = "Carpet Cleaner · Bonzi preview (test save)"
	game = CLEANING_SCENE.instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await settle()
	if not capture_mode:
		print("BONZI_PREVIEW: interactive paid workshop, purchased Bonzi, 5000 disposable coins.")
		return
	await capture_showcase()


func capture_showcase() -> void:
	var physics_was_active: bool = game.is_physics_processing()
	var visual: Node3D = game.bonzi.visual
	var visual_was_active: bool = visual.is_processing()
	game.set_physics_process(false)
	visual.set_process(false)
	# Move the lifted player tool without beginning any manual cleaning stroke.
	game.move_brush_to_screen(game.camera.unproject_position(Vector3(0.65, 0.067, 1.2)), false)
	for _step in roundi(CAPTURE_SECONDS / STEP):
		game._physics_process(STEP)
		if game.rug_phase == game.RugPhase.CLEANING:
			game.soil._physics_process(STEP)
		game.soil._process(STEP)
		visual.set_process(false)
		if visual.cleaning:
			visual._process(STEP)
	await settle()
	var folder := ProjectSettings.globalize_path("res://../art/renders")
	DirAccess.make_dir_recursive_absolute(folder)
	var saved_showcase: bool = await save_frame(folder.path_join("bonzi_showcase.png"))
	var camera: Camera3D = game.camera
	var camera_transform := camera.global_transform
	var camera_projection := camera.projection
	var camera_size := camera.size
	var hud_was_visible: bool = game.hud.visible
	game.hud.hide()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.0
	# Retain the production camera's exact 20-degree pitch and heading.
	var focus := visual.global_position + Vector3(0, 0.06, -0.04)
	camera.global_transform = Transform3D(camera_transform.basis, focus + camera_transform.basis.z.normalized() * 6.0)
	await settle()
	var saved_detail: bool = await save_frame(folder.path_join("bonzi_model_detail.png"))
	camera.global_transform = camera_transform
	camera.projection = camera_projection
	camera.size = camera_size
	game.hud.visible = hud_was_visible
	game.set_physics_process(physics_was_active)
	visual.set_process(visual_was_active)
	print("BONZI_PREVIEW_CAPTURE: ", folder, " after ", CAPTURE_SECONDS, " simulated seconds")
	await close_preview(0 if saved_showcase and saved_detail else 1)


func save_frame(path: String) -> bool:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(path)
	if result != OK:
		push_error("Could not save Bonzi preview frame: " + path)
	return result == OK


func close_preview(exit_code: int = 0) -> void:
	if closing:
		return
	closing = true
	if is_instance_valid(game):
		game.free()
	game = null
	current_scene = null
	var audio := root.get_node_or_null("GameAudio")
	if audio != null:
		audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	if not save_path.is_empty():
		DirAccess.remove_absolute(save_path)
		DirAccess.remove_absolute(save_path + ".bak")
	quit(exit_code)
