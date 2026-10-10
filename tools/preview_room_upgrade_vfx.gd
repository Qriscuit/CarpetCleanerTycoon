extends SceneTree
## Actual production touch purchases captured at exact feedback phases. The
## isolated funded ledger never reads or writes the player's save.
const RoomRules := preload("res://scripts/room_upgrades.gd")
const IDS := RoomRules.IDS
const TIMES := [0.0, 0.10, 0.18, 0.38, 0.80, 0.95]
var game: Node
var ledger: Node
var capture_mode := false
var video_mode := false
var failures := 0
var folder := "res://../art/renders/room_upgrade_pulse"

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test for this disposable upgrade preview")
		quit(2)
		return
	capture_mode = "--upgrade-capture" in OS.get_cmdline_user_args()
	video_mode = "--upgrade-video" in OS.get_cmdline_user_args()
	capture_mode = capture_mode or video_mode
	call_deferred("run")

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func touch_buy() -> void:
	var buy: Button = game.hud.room_panel.get_node("%Buy")
	var point := buy.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)

func run() -> void:
	if capture_mode and DisplayServer.get_name() == "headless":
		push_error("Use the graphical renderer for visual captures")
		quit(2)
		return
	ledger = root.get_node("ShopState")
	ledger._save_path = "res://../art/room_upgrade_pulse_test_%d.json" % OS.get_process_id()
	ledger.reset_progress()
	ledger.cash = 500000
	root.size = Vector2i(540, 750)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	root.title = "Carpet Cleaner · Independent upgrades (test save)"
	await settle()
	if capture_mode:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		for orientation: String in ["portrait", "landscape"]:
			root.size = Vector2i(540, 750) if orientation == "portrait" else Vector2i(844, 390)
			await settle()
			var ids: Array = IDS if not video_mode else ["plants" if orientation == "portrait" else "window"]
			for id: String in ids:
				var milestones: Array = [false, true] if not video_mode else [true]
				for milestone: bool in milestones:
					# Reset to a real, paid local ladder so each screenshot is a
					# successful first or real makeover purchase, not a mock offer.
					game.hud.close_upgrades()
					ledger.reset_progress()
					ledger.cash = 500000
					if milestone:
						for step in range(RoomRules.visual_milestones(id, ledger.active_store)[0] - 1):
							if not ledger.buy_room_upgrade(id): failures += 1
					await settle()
					await capture_purchase(id, orientation, milestone)
		print("ROOM UPGRADE PULSE CAPTURES: %d frames; %d failures" % [72 if video_mode else IDS.size() * 2 * TIMES.size() * 2, failures])
		var test_path: String = ProjectSettings.globalize_path(ledger._save_path)
		game.hud.close_upgrades()
		game.free()
		DirAccess.remove_absolute(test_path)
		DirAccess.remove_absolute(test_path + ".bak")
		quit(0 if failures == 0 else 1)
	else:
		for id: String in IDS:
			for step in range(RoomRules.visual_milestones(id, ledger.active_store)[0] - 1): ledger.buy_room_upgrade(id)
		for id: String in IDS:
			open_item(id)
			await settle()
			touch_buy()
			await create_timer(1.6).timeout
		game.hud.close_upgrades()

func open_item(id: String) -> void:
	var anchor: Vector3 = game.room.anchor_world(id)
	if id == "plants": anchor = game.room.to_global(Vector3(-1.94, 0.7, 2.42))
	if id == "floor": anchor = game.room.to_global(Vector3(-1.70, 0.025, 0.90))
	if id == "railings": anchor = game.room.to_global(Vector3(2.16, 0.44, 0.65))
	game.open_room_upgrade(id, game.camera.unproject_position(anchor))

func capture_purchase(id: String, orientation: String, milestone: bool) -> void:
	open_item(id)
	await settle()
	touch_buy()
	game.room.set_process(false)
	if not game.room.is_upgrade_active(id):
		push_error("Gesture did not buy " + id)
		failures += 1
		return
	var previous_time := 0.0
	var phases: Array = TIMES if not video_mode else range(36)
	for item: Variant in phases:
		var time: float = float(item) if not video_mode else float(item) / 30.0
		game.room._process(time - previous_time)
		game.room.set_process(false)
		previous_time = time
		await settle()
		await RenderingServer.frame_post_draw
		var label := "%s_%s_%s_%03d.png" % [orientation, id, "milestone" if milestone else "first", roundi(time * 100)]
		if video_mode: label = "pulse_%s_%03d.png" % [orientation, int(item)]
		if root.get_texture().get_image().save_png(folder.path_join(label)) != OK:
			failures += 1
	game.room.set_process(false)
