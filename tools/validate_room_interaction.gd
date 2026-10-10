extends SceneTree
## Exercise real pointer routing, room offers, save effects and responsive layout.
var failures := 0
var checks := 0
var game: Node
var ledger: Node
const RoomRules := preload("res://scripts/room_upgrades.gd")

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func touch(point: Vector2, pressed: bool, index: int = 0, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.pressed = pressed
	event.index = index
	event.canceled = canceled
	root.push_input(event, true)

func tap(point: Vector2) -> void:
	touch(point, true)
	touch(point, false)

func drag(point: Vector2, index: int = 0) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	root.push_input(event, true)

func settle() -> void:
	await process_frame
	await process_frame

func capture(label: String) -> void:
	if not "--room-capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../art/renders/room_" + label + ".png")

func run() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		quit(2)
		return
	ledger = root.get_node("ShopState")
	ledger._save_path = "res://../art/room_interaction_test_%d.json" % OS.get_process_id()
	check(ledger.reset_progress(), "Isolated save starts clean")
	ledger.cash = 10000
	root.size = Vector2i(648, 900)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await settle()
	check(game.hud.get_node_or_null("%PayoutUpgradeButton") == null, "Generic earnings purchase button is removed")
	check(game.room != null, "Authored room is installed in production")
	await capture("starter")
	var original: Dictionary = game.soil.make_snapshot()
	for id: String in RoomRules.IDS:
		var point: Vector2 = game.camera.unproject_position(game.room.anchor_world(id))
		check(game.room.pick_upgrade(game.camera, point) == id, "Visible " + id + " is pickable")
		tap(point)
		await settle()
		check(game.hud.room_panel.visible and game.hud.room_panel.selected_id == id, "Touch opens the selected " + id)
		check(not game.brush_dragging and game.soil.simulation_suspended, "Room offer pauses cleaning")
		var offer: Dictionary = ledger.room_upgrade_view(id)
		check(game.hud.room_panel.offer == offer, "Offer previews durable wallet and earnings")
		var other_prices := {}
		for other: String in RoomRules.IDS:
			if other != id: other_prices[other] = ledger.room_upgrade_view(other).cost
		var cash_before: int = ledger.cash
		var clean_before: Dictionary = game.soil.make_snapshot()
		await capture(id + "_offer")
		tap(game.hud.room_panel.get_node("%Buy").get_global_rect().get_center())
		await settle()
		check(ledger.cash == cash_before - int(offer.cost), "One touch spends exactly one upgrade price")
		check(int(ledger.room_upgrade_levels()[id]) == 1 and int(game.room.levels[id]) == 1 and int(game.room.visual_tiers[id]) == 0, "First " + id + " purchase saves its level while retaining the starter model")
		check(game.room.is_upgrade_active(id), "Successful " + id + " purchase animates the room object")
		for other: String in other_prices:
			check(ledger.room_upgrade_view(other).cost == other_prices[other], "Buying " + id + " leaves " + other + " price unchanged")
		check(int(ledger.progression_view().early_reward) == int(offer.next_early), "Previewed earnings apply immediately")
		check(game.soil.make_snapshot() == clean_before, "Buying does not clean or replace carpet")
		await create_timer(1.0).timeout
		tap(game.hud.room_panel.get_node("%Close").get_global_rect().get_center())
		await settle()
		check(not game.hud.upgrades_open() and not game.soil.simulation_suspended, "Close resumes cleaning")
	check(game.soil.make_snapshot() == original, "All room interactions leave rug untouched")
	var floor_point: Vector2 = game.camera.unproject_position(game.room.anchor_world("floor"))
	touch(floor_point, true)
	drag(floor_point + Vector2(40, 0))
	touch(floor_point, false)
	check(not game.hud.upgrades_open() and not game.brush_dragging, "Swipe on floor is not a purchase tap or brush stroke")
	touch(floor_point, true)
	touch(floor_point, false, 0, true)
	check(not game.hud.upgrades_open(), "Canceled floor touch does not open a modal")
	touch(floor_point, true)
	touch(floor_point + Vector2(20, 0), true, 1)
	touch(floor_point + Vector2(20, 0), false, 1)
	touch(floor_point, false)
	check(not game.hud.upgrades_open(), "Two-finger room gesture cannot buy or open upgrades")
	var rug_point: Vector2 = game.camera.unproject_position(Vector3(0, 0.067, 0))
	check(game.room.pick_upgrade(game.camera, rug_point).is_empty(), "Carpet keeps its input priority")
	touch(rug_point, true)
	check(game.brush_dragging, "Finger on carpet lowers brush and starts cleaning")
	touch(rug_point, false)
	await create_timer(0.20).timeout
	check(not game.brush_dragging and game.brush_visual_lift > 0.20, "Releasing returns brush to hovering")
	ledger.cash = 0
	ledger.changed.emit()
	tap(floor_point)
	check(game.hud.room_panel.visible and game.hud.room_panel.get_node("%Buy").disabled, "Unaffordable room feature still shows its offer")
	game.hud.close_upgrades()
	ledger.cash = 10000
	ledger.changed.emit()
	# Opening a feature while reward coins are flying must become buyable when
	# the displayed wallet catches up, without requiring a close/reopen.
	game.hud.reserve_reward(12)
	ledger.cash += 12
	ledger.changed.emit()
	game.open_room_upgrade("floor")
	game.hud.show_reward(12, ledger.cash)
	check(game.hud.room_panel.get_node("%Buy").disabled, "Incoming reward coins temporarily block purchase")
	for tick in range(100):
		if game.hud.pending_reward == 0: break
		game.hud._process(0.05)
	check(not game.hud.room_panel.get_node("%Buy").disabled, "Buy becomes available after the last reward coin")
	game.hud.close_upgrades()
	for viewport_size: Vector2i in [Vector2i(360, 800), Vector2i(800, 360), Vector2i(720, 1000)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		await settle()
		game.frame_carpet()
		game.open_room_upgrade("floor")
		await settle()
		var safe: Rect2 = game.hud._safe_rect()
		check(safe.encloses(game.hud.room_panel.get_node("%Card").get_global_rect()), "Room card fits " + str(viewport_size))
		for button: Button in game.hud.room_panel.action_buttons():
			check(safe.encloses(button.get_global_rect()), "Room action is reachable " + str(viewport_size))
		if viewport_size.x > viewport_size.y:
			var scroll: ScrollContainer = game.hud.room_panel.get_node("%Scroll")
			var scroll_bar := scroll.get_v_scroll_bar()
			check(scroll.scroll_vertical == 0 and scroll_bar.max_value <= scroll_bar.page + 1.0, "Compact offer shows details without scrolling in a short phone layout")
		await capture("layout_%dx%d" % [viewport_size.x, viewport_size.y])
		game.hud.close_upgrades()
	game.room.cancel_upgrade_effects()
	var final_levels := {}
	for id: String in RoomRules.IDS: final_levels[id] = RoomRules.Progression.room_level_cap(1)
	game.room.set_levels(final_levels, 1)
	await capture("fully_upgraded")
	print("ROOM INTERACTION: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ledger._save_path))
	quit(1 if failures > 0 else 0)
