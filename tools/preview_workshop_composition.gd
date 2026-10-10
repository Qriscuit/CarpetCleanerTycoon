extends SceneTree
## Twelve real workshop previews; keep the production 720x1000 canvas intact.
## tools/run_godot.ps1 --path CarpetToy --rendering-method gl_compatibility --script ../tools/preview_workshop_composition.gd -- --shop-test
const Rules := preload("res://scripts/progression.gd")
const RoomRules := preload("res://scripts/room_upgrades.gd")
const Money := preload("res://scripts/money.gd")
const FOLDER := "res://../art/renders/composition_angles"
const YAW_ANGLES := [0.0, -8.0, -12.0]
const WINDOW_SIZES := [Vector2i(390, 844), Vector2i(844, 390)]
var ledger: Node
var game: Node
var save_path := ""
var captures := 0
var failures := 0

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Composition previews need a real renderer and -- --shop-test")
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for _frame: int in 4:
		await process_frame
		await RenderingServer.frame_post_draw

func seed_room(maxed: bool) -> void:
	check(ledger.reset_progress(), "The preview ledger resets in its disposable file")
	ledger.room_upgrade_view("floor")
	var branch: Dictionary = ledger._branch()
	if maxed:
		for id: String in RoomRules.IDS: branch.room_upgrades[id] = Rules.room_level_cap(1)
		branch.payout_level = RoomRules.total_levels(branch.room_upgrades)
		branch.tool_level = 4
		branch.bonzi_tier = 2
		ledger._owned.merge({"wide_brush": true, "bonzi": true, "bonzi_mk2": true, "intake": true}, true)
	branch.job_early_reward = RoomRules.early_reward(1, branch)
	ledger.cash = 400000.0 if maxed else 1000.0
	check(ledger.save_state(), "The preview's real levels and quote save and emit the normal state update")
	check(float(ledger.progression_view().full_reward) == (Rules.reward_cap(1) if maxed else 40.0), "The durable per-carpet quote matches the selected room")

func enter_room() -> void:
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	game.room_view_pitch_from_top = 30.0
	root.add_child(game)
	current_scene = game
	# Freeze only preview labor so every angle shows the same dirty carpet.
	game.soil.suspend_simulation(true)
	game._physics_process(0.0)
	game.set_physics_process(false)
	await settle()
	check(root.content_scale_size == Vector2i(720, 1000), "The production reference canvas stays 720x1000")

func capture_room(label: String, window_size: Vector2i, yaw: float) -> void:
	root.size = window_size
	game.room_view_yaw_degrees = yaw
	await settle()
	game.frame_carpet()
	await settle()
	var value: String = (game.hud.control("CarpetEarningsValue") as Label).text
	var expected := Money.format(Rules.reward_cap(1)) if label == "all_max" else "40"
	check(value == expected, "The captured room's earnings plaque follows its real ledger")
	var yaw_label := "0" if is_zero_approx(yaw) else "minus%d" % roundi(absf(yaw))
	var name := "%s_yaw_%s_%dx%d.png" % [label, yaw_label, window_size.x, window_size.y]
	var path := ProjectSettings.globalize_path(FOLDER.path_join(name))
	check(root.get_texture().get_image().save_png(path) == OK, "The requested room-angle image saves")
	captures += 1
	print("COMPOSITION_CAPTURE ", path, "; reference=", root.content_scale_size, "; viewport=", root.get_visible_rect().size, "; reward=", value, "; camera_size=", game.camera.size)

func run() -> void:
	ledger = root.get_node("ShopState")
	ledger.set_process(false)
	ledger._test_ticks_msec = 0
	ledger._test_unix_time = 1800000000.0
	save_path = "res://.godot/preview_workshop_composition_%d.json" % OS.get_process_id()
	ledger._save_path = save_path
	root.size = WINDOW_SIZES[0]
	root.title = "Carpet Cleaner · Room angles (test save)"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	for maxed: bool in [false, true]:
		seed_room(maxed)
		await enter_room()
		for window_size: Vector2i in WINDOW_SIZES:
			for yaw: float in YAW_ANGLES:
				await capture_room("all_max" if maxed else "starter", window_size, yaw)
		game.free()
		game = null
		current_scene = null
		await process_frame
	root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	print("WORKSHOP_COMPOSITION_PREVIEW %d captures, %d failures" % [captures, failures])
	quit(0 if failures == 0 else 1)
