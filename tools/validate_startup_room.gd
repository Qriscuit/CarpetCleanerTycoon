extends SceneTree
## A fresh launch and reloaded ledgers enter the real paid room, using test saves.
const State := preload("res://scripts/shop_state.gd")
const Routes := preload("res://scripts/scene_routes.gd")
const Rules := preload("res://scripts/progression.gd")
var ledger: Node
var game: Node
var checks := 0
var failures := 0
var save_path := ""

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		printerr("Startup room validation requires a renderer and -- --shop-test.")
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("STARTUP ROOM: " + message)

func frames() -> void:
	await process_frame
	if is_instance_valid(game) and not game.application_focused:
		game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await process_frame
	await RenderingServer.frame_post_draw

func launch() -> void:
	game = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	# Exercise actual startup selection/restoration, without spending test time
	# on the cosmetic entrance animation already checked by choreography tests.
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	game.soil.set_physics_process(false)
	game.set_physics_process(false)
	await frames()
	check(game.scene_file_path == Routes.CLEANING and game.paid_contract, "The configured launch opens the paid carpet room")
	check(game.rug_phase == game.RugPhase.CLEANING and game.soil.reveal_progress >= 1.0, "The launch reaches a playable carpet")
	check(game.contract_job_id == ledger.active_job_id and not game.contract_job_id.is_empty(), "The room uses the durable current job")
	check(game.room.visible and int(game.room.store_id) == ledger.active_store, "The room displays the selected store")

func leave() -> void:
	game.free()
	game = null
	current_scene = null
	await frames()

func reload_ledger() -> void:
	ledger.free()
	ledger = State.new()
	ledger.name = "ShopState"
	ledger._save_path = save_path
	ledger._test_ticks_msec = 0
	ledger._test_unix_time = 1800000000.0
	root.add_child(ledger)
	ledger.set_process(false)
	check(ledger.last_error.is_empty(), "A new ledger instance loads the saved progress")

func check_restore(job: String, rug: String, snapshot: Dictionary, balance: float, store: int) -> void:
	check(ledger.active_store == store and ledger.active_job_id == job and ledger.active_rug_id == rug, "Cold launch preserves selected store, rug and reservation")
	check(is_equal_approx(ledger.cash, balance), "Cold launch preserves the wallet without duplicate income")
	await launch()
	check(game._resumed_rug and game.contract_job_id == job, "The carpet restores its existing unfinished progress")
	var restored: Dictionary = game.soil.make_snapshot()
	for key: String in ["rug_id", "coverage", "water", "extracted", "wash_cycle", "hose_patch_water"]:
		if snapshot.has(key):
			check(restored.get(key) == snapshot[key], "Restored carpet retains saved " + key)
	check(game.room.levels == ledger.room_upgrade_levels(), "Saved accessory levels remain visible on launch")

func run() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == Routes.CLEANING, "Project startup is the carpet scene")
	save_path = "res://.godot/startup_room_%d.json" % OS.get_process_id()
	ledger = root.get_node("ShopState")
	ledger._save_path = save_path
	ledger._test_ticks_msec = 0
	ledger._test_unix_time = 1800000000.0
	ledger.set_process(false)
	check(ledger.reset_progress(), "A new-player fixture persists in an isolated save")
	await launch()
	check(ledger.active_store == 1 and ledger.manual_jobs == 0 and ledger._job_serial == 1, "A first launch reserves one first-store carpet without paying it")
	ledger.cash = 1000.0
	check(ledger.buy_room_upgrade("floor"), "The resumable fixture purchases an accessory normally")
	game.apply_selected_tool_stroke(Vector3(-0.6, game.CARPET_PLANE_Y, 0), Vector3(0.6, game.CARPET_PLANE_Y, 0), 0.15)
	check(game.soil.surface_clearance() > 0.0 and game.soil.surface_clearance() < 0.75, "The fixture has actual unfinished dry cleaning")
	check(game.save_contract_progress(), "Unfinished dry progress checkpoints")
	var job: String = ledger.active_job_id
	var rug: String = ledger.active_rug_id
	var snapshot: Dictionary = ledger.job_snapshot.duplicate(true)
	var balance: float = ledger.cash
	await leave()
	reload_ledger()
	await check_restore(job, rug, snapshot, balance, 1)
	# The visible Back action still opens the store browser.
	game.hud.control("HomeButton").pressed.emit()
	await frames()
	game = null
	check(current_scene.scene_file_path == Routes.MAIN_MENU, "Back retains access to store browsing")
	current_scene.free()
	current_scene = null
	# A later selected place must remain selected after a fresh ledger load.
	ledger.stores["2"] = Rules.new_branch(2)
	check(ledger.select_store(2), "The isolated unlocked-store fixture selects its latest place")
	await launch()
	game.apply_selected_tool_stroke(Vector3(-0.4, game.CARPET_PLANE_Y, 0), Vector3(0.4, game.CARPET_PLANE_Y, 0), 0.15)
	check(game.soil.surface_clearance() > 0.0 and game.soil.surface_clearance() < 0.75, "The later-store fixture has unfinished cleaning progress")
	check(game.save_contract_progress(), "The later store's unfinished progress checkpoints")
	job = ledger.active_job_id
	rug = ledger.active_rug_id
	snapshot = ledger.job_snapshot.duplicate(true)
	balance = ledger.cash
	await leave()
	reload_ledger()
	await check_restore(job, rug, snapshot, balance, 2)
	await leave()
	var audio := root.get_node_or_null("GameAudio")
	if audio != null: audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	print("STARTUP_ROOM_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
