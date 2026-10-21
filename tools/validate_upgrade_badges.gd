extends SceneTree
## Production affordability, marker taps, animation and phone composition.
## Run through tools/run_godot.ps1 with -- --shop-test; optionally --badge-capture.

const RoomRules := preload("res://scripts/room_upgrades.gd")
const HUD_CONTROLS := ["HomeButton", "CleaningProgress", "EarningsPerCarpet", "Wallet", "UpgradeButton", "FinishJobButton", "AdRewardButton"]
const SHOP_BADGES := ["UpgradeButton", "ToolUpgradeButton", "HoseUpgradeButton", "SqueegeeUpgradeButton"]
var game: Node
var ledger: Node
var checks := 0
var failures := 0
var save_path := ""

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		printerr("Upgrade badge validation requires -- --shop-test.")
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("UPGRADE BADGES: " + message)

func settle(keep_focused: bool = true) -> void:
	await process_frame
	if keep_focused and is_instance_valid(game) and not game.application_focused:
		game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func settle_badges(keep_focused: bool = true) -> void:
	await create_timer(0.36).timeout
	await settle(keep_focused)

func set_cash(amount: float) -> void:
	ledger.cash = amount
	ledger.changed.emit()

func room_badge(id: String) -> Control:
	return game.hud._room_upgrade_badges[id] as Control

func available(badge: Control) -> bool:
	return bool(badge.get("available"))

func check_room_set(expected: Array, label: String) -> void:
	for id: String in RoomRules.IDS:
		var badge := room_badge(id)
		check(available(badge) == (id in expected), label + ": " + id + " affordability")
		check(badge.is_visible_in_tree() == (id in expected), label + ": " + id + " rendered marker")
		if id in expected:
			check(badge.scale.is_equal_approx(Vector2.ONE), label + ": " + id + " pop settles at its authored size")

func touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = pressed
	root.push_input(event, true)

func tap(point: Vector2) -> void:
	touch(point, true)
	touch(point, false)

func projected_rug() -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for corner: Vector2 in [Vector2(-1.06, -1.72), Vector2(1.06, -1.72), Vector2(1.06, 1.72), Vector2(-1.06, 1.72)]:
		polygon.append(game.camera.unproject_position(Vector3(corner.x, game.CARPET_PLANE_Y, corner.y)))
	return polygon

func rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])

func capture(label: String) -> void:
	if "--badge-capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var folder := "res://../art/renders"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	check(root.get_texture().get_image().save_png(folder.path_join("upgrade_badges_" + label + ".png")) == OK, "Screenshot saves: " + label)

func run() -> void:
	ledger = root.get_node("ShopState")
	save_path = "res://../art/upgrade_badges_test_%d.json" % OS.get_process_id()
	ledger._save_path = save_path
	ledger.set_process(false)


	check(ledger.reset_progress(), "A fresh isolated ledger is available")
	ledger.cash = 0.0
	root.size = Vector2i(390, 844)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await settle_badges()
	check(game.hud._room_upgrade_badges.size() == RoomRules.IDS.size(), "Every room ladder has one marker")
	check(game.hud._shop_upgrade_badges.size() == SHOP_BADGES.size(), "Cart and drawer purchases each have one marker")
	check_room_set([], "No starting money")
	set_cash(24.0)
	await settle_badges()
	check_room_set([], "24 coins")
	set_cash(25.0)
	var plant := room_badge("plants")
	# Affordability refresh coalesces at the frame boundary. The shared badge
	# animation can be inspected synchronously, before its first tween frame.
	plant.set_available(true)
	check(available(plant) and plant.visible and plant.scale.length() < 0.01, "Revealing a plant marker starts a pop from zero")
	await settle_badges()
	check_room_set(["plants"], "25 coins")
	for sample: Dictionary in [
		{"cash":35.0, "ids":["plants", "railings"]},
		{"cash":40.0, "ids":["plants", "railings", "floor"]},
		{"cash":50.0, "ids":["plants", "railings", "floor", "walls"]},
		{"cash":60.0, "ids":RoomRules.IDS},
	]:
		set_cash(float(sample.cash))
		await settle_badges()
		check_room_set(sample.ids, "%d coins" % int(sample.cash))
	await check_purchase_and_reversal()
	await check_gates()
	await check_phone_layouts()
	await check_tool_badges()
	await check_practice()
	finish()

func check_purchase_and_reversal() -> void:
	set_cash(25.0)
	await settle_badges()
	var plant := room_badge("plants")
	tap(plant.get_global_rect().get_center())
	await settle()
	check(game.hud.room_panel.visible and game.hud.room_panel.selected_id == "plants", "The plant marker opens its real room offer")
	tap(game.hud.room_panel.get_node("%Buy").get_global_rect().get_center())
	await settle()
	check(ledger.cash == 0.0 and int(ledger.room_upgrade_levels().plants) == 1, "The marker offer buys one plant upgrade for exactly 25 coins")
	game.hud.close_upgrades()
	await settle_badges()
	check_room_set([], "Spending the available wallet")
	set_cash(float(ledger.room_upgrade_view("plants").cost))
	await settle_badges()
	check(available(plant) and plant.is_visible_in_tree(), "Earning the next plant price restores its marker")
	# Fast earn/spend changes must cancel old tweens instead of resurrecting a dot.
	for index in range(4):
		set_cash(0.0)
		await process_frame
		set_cash(1000.0)
		await process_frame
	set_cash(0.0)
	await settle_badges()
	check_room_set([], "Rapid earn/spend ends unaffordable")
	for id: String in RoomRules.IDS:
		check(room_badge(id).scale.length() < 0.01, id + " finishes a canceled pop at zero")
	set_cash(1000.0)
	await settle_badges()
	check_room_set(RoomRules.IDS, "Rapid changes recover to affordable")
	var steady_badge := room_badge("plants")
	var steady_tween: Tween = steady_badge.get("_visibility_tween")
	game.hud.reserve_reward(1.0)
	ledger.cash += 1.0
	ledger.changed.emit()
	game.hud.show_cleaning_reward(1.0, ledger.cash)
	await settle()
	check(available(steady_badge) and steady_badge.scale.is_equal_approx(Vector2.ONE) and steady_badge.get("_visibility_tween") == steady_tween, "An ordinary cleaning credit does not retrigger an already-affordable marker")
	var branch: Dictionary = ledger.stores[str(ledger.active_store)]
	branch.room_upgrades.walls = RoomRules.Progression.room_level_cap(int(ledger.active_store))
	ledger.changed.emit()
	await settle_badges()
	check(not available(room_badge("walls")) and not room_badge("walls").visible, "A maxed room ladder has no marker even with ample money")
	branch.room_upgrades.walls = 0
	ledger.changed.emit()
	await settle_badges()

func check_gates() -> void:
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await settle_badges(false)
	check_room_set([], "Application focus lost")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await settle_badges()
	check_room_set(RoomRules.IDS, "Application focus restored")
	game.hud.reserve_reward(12.0)
	await settle_badges()
	check_room_set([], "Reward coins are pending")
	game.hud.cancel_reserved_reward(12.0)
	await settle_badges()
	check_room_set(RoomRules.IDS, "Reward reservation ends")
	game.open_room_upgrade("floor")
	await settle_badges()
	check_room_set([], "A room offer is open")
	game.hud.close_upgrades()
	await settle_badges()
	check_room_set(RoomRules.IDS, "Room offer closes")

func check_phone_layouts() -> void:
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(390, 844), Vector2i(844, 390)]:
		root.size = dimensions
		await settle()
		game.frame_carpet()
		await settle_badges()
		var label := "%dx%d" % [dimensions.x, dimensions.y]
		var safe: Rect2 = game.hud._safe_rect()
		var world: Rect2 = game.hud.workshop_view_rect()
		var rug := projected_rug()
		var physical_ratio: Vector2 = Vector2(root.size) / root.get_visible_rect().size
		var seen: Array[Rect2] = []
		for id: String in RoomRules.IDS:
			var badge := room_badge(id)
			var rect := badge.get_global_rect()
			var pixels := rect.size * physical_ratio
			check(badge.is_visible_in_tree(), label + ": " + id + " marker is rendered")
			check(safe.grow(0.75).encloses(rect) and world.grow(0.75).encloses(rect), label + ": " + id + " fits the safe room area")
			check(minf(pixels.x, pixels.y) >= 18.0 and maxf(pixels.x, pixels.y) <= 34.0, label + ": " + id + " stays a small legible dot")
			check(Geometry2D.intersect_polygons(rug, rect_polygon(rect.grow(1.0))).is_empty(), label + ": " + id + " clears the playable rug")
			for other: Rect2 in seen: check(not rect.grow(1.0).intersects(other), label + ": room markers do not overlap")
			seen.append(rect)
			for control_name: String in HUD_CONTROLS:
				var control: Control = game.hud.control(control_name)
				if control.is_visible_in_tree(): check(not rect.grow(1.0).intersects(control.get_global_rect()), label + ": " + id + " clears " + control_name)
			check(game.hud.room_badge_at_point(rect.get_center()) == id, label + ": " + id + " marker owns its center")
		await capture(label)
		for id: String in RoomRules.IDS:
			tap(room_badge(id).get_global_rect().get_center())
			await settle()
			check(game.hud.room_panel.visible and game.hud.room_panel.selected_id == id, label + ": tapping " + id + " opens the correct offer")
			check(not game.brush_dragging, label + ": marker tap does not clean the rug")
			game.hud.close_upgrades()
			await settle_badges()

func check_tool_badges() -> void:
	var cart: Control = game.hud._shop_upgrade_badges.UpgradeButton
	set_cash(float(ledger.progression_view().tool_cost) - 1.0)
	await settle_badges()

	check(not available(cart) and not cart.visible, "The cart ignores affordable room ladders when the tool is unaffordable")
	set_cash(float(ledger.progression_view().tool_cost))
	await settle_badges()
	check(available(cart) and cart.is_visible_in_tree(), "An affordable brush shows the cart marker")
	game.hud.open_upgrades()
	await settle_badges()
	check(not cart.is_visible_in_tree(), "The cart marker leaves the screen while the drawer is open")
	var tool: Control = game.hud._shop_upgrade_badges.ToolUpgradeButton
	check(available(tool) and tool.is_visible_in_tree(), "The affordable brush purchase shows its drawer marker")

	await capture("brush_drawer")
	game.hud.close_upgrades()
	await settle_badges()
	check(not tool.is_visible_in_tree(), "Drawer purchase markers leave with the drawer")
	# A standalone HUD fixture exercises both wet offers without changing stores.
	var wet_hud: Node = load("res://scenes/ui/cleaning_hud.tscn").instantiate()
	root.add_child(wet_hud)
	await settle()
	wet_hud.initialize_wallet(1000.0)
	var wet_view: Dictionary = ledger.progression_view().duplicate(true)
	wet_view.merge({"store_id":7, "wet_unlocked":true, "tool_cost":640.0, "can_upgrade_tool":true, "hose_cost":640.0, "can_upgrade_hose":true, "squeegee_cost":800.0, "can_upgrade_squeegee":true}, true)
	wet_hud.set_progression(wet_view, true)
	wet_hud.open_upgrades()
	await settle_badges()
	check(available(wet_hud._shop_upgrade_badges.ToolUpgradeButton) and wet_hud._shop_upgrade_badges.ToolUpgradeButton.is_visible_in_tree(), "The main water-hose offer has an affordable marker")
	check(available(wet_hud._shop_upgrade_badges.SqueegeeUpgradeButton) and wet_hud._shop_upgrade_badges.SqueegeeUpgradeButton.is_visible_in_tree(), "The separate squeegee offer has an affordable marker")
	check(not wet_hud._shop_upgrade_badges.HoseUpgradeButton.is_visible_in_tree(), "The hidden duplicate hose row adds no visible marker")
	wet_hud.sync_wallet(639.0)
	await settle_badges()
	check(not wet_hud._shop_upgrade_badges.ToolUpgradeButton.visible and not wet_hud._shop_upgrade_badges.SqueegeeUpgradeButton.visible, "Spending below wet prices removes both drawer markers")
	wet_hud.sync_wallet(1000.0)
	wet_hud.set_progression(wet_view, true)
	await settle_badges()

	wet_hud.reserve_reward(1.0)
	await settle_badges()
	check(not wet_hud._shop_upgrade_badges.ToolUpgradeButton.visible and not wet_hud._shop_upgrade_badges.SqueegeeUpgradeButton.visible, "Pending rewards gate drawer purchases")

	wet_hud.free()

func check_practice() -> void:
	game.free()
	current_scene = null
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.practice_only = true
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await settle_badges()
	check_room_set([], "Practice room")
	for name: String in SHOP_BADGES:
		var badge: Control = game.hud._shop_upgrade_badges[name]
		check(not available(badge) and not badge.is_visible_in_tree(), "Practice hides " + name + " marker")

func finish() -> void:
	if is_instance_valid(game): game.free()
	current_scene = null
	var audio := root.get_node_or_null("GameAudio")
	if audio != null: audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if FileAccess.file_exists(save_path + ".tmp"): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + ".tmp"))
	print("UPGRADE_BADGE_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
