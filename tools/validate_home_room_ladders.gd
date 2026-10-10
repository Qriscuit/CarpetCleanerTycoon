extends SceneTree
## Real Home-sheet gestures and narrow-screen layout, with an isolated save.
const RoomRules = preload("res://scripts/room_upgrades.gd")
const Progression = preload("res://scripts/progression.gd")
var checks := 0
var failures := 0
var home: Control

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to protect the player's save")
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func touch(point: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)

func capture(label: String) -> void:
	if "--home-room-capture" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://../art/renders/home_room_ladders_" + label + ".png") == OK, "Home ladder capture saves " + label)

func run() -> void:
	var ledger := root.get_node("ShopState")
	ledger._save_path = "res://../art/home_room_ladders_%d.json" % OS.get_process_id()
	ledger.set_process(false)
	check(ledger.reset_progress(), "Home ladders use a disposable ledger")
	ledger.cash = 50000
	root.size = Vector2i(390, 844)
	home = load("res://scenes/production/floating_home.tscn").instantiate()
	home.animate_shop = false
	root.add_child(home)
	current_scene = home
	await settle()
	home.open_management("shop")
	await settle()
	var sheet: Control = home.management
	for index in RoomRules.IDS.size():
		var id: String = RoomRules.IDS[index]
		var row_id: String = sheet.ROW_IDS[index]
		var offer: Dictionary = ledger.room_upgrade_view(id)
		check(sheet.actions[row_id] == "room:" + id, "Home explicitly targets " + id)
		check(sheet.rows[row_id].get_node("Row/Words/Title").text.contains("Lv 0"), "Home shows " + id + " local level")
		var detail: String = sheet.rows[row_id].get_node("Row/Words/Status").text
		check(detail.contains("Clean 40") and detail.contains("Lv %d" % RoomRules.visual_milestones(id, 1)[0]) and not detail.contains("75%"), "Home uses full Clean earnings and the authored look milestone for " + id)
		check(sheet.action_for(row_id).text == sheet._amount(float(offer.cost)), "Home displays " + id + " exact independent price")
	check(not sheet.actions.values().has("payout"), "Home has no hidden generic earnings purchase")
	await capture("portrait")
	var floor_button: Button = sheet.action_for(sheet.ROW_IDS[0])
	var button_point := floor_button.get_global_rect().get_center()
	var before: Dictionary = ledger._capture_state()
	touch(button_point, true)
	check(ledger._capture_state() == before, "Home purchase waits for touch release")
	touch(button_point, false, true)
	check(ledger._capture_state() == before, "Canceled Home upgrade cannot spend")
	touch(button_point, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = button_point + Vector2(25, 0)
	drag.relative = Vector2(25, 0)
	root.push_input(drag, true)
	touch(drag.position, false)
	check(ledger._capture_state() == before, "Dragging over a Home upgrade cannot buy")
	touch(button_point, true)
	touch(button_point, false)
	await settle()
	check(ledger.cash == 49960 and ledger.room_upgrade_levels().floor == 1, "Home touch spends40 on the floor only")
	check(ledger.room_upgrade_levels().plants == 0 and ledger.room_upgrade_view("plants").cost == 25 and ledger.room_upgrade_view("window").cost == 60 and ledger.room_upgrade_view("railings").cost == 35, "Buying floor leaves all other ladders at their starting prices")
	check(sheet.rows[sheet.ROW_IDS[0]].get_node("Row/Words/Status").text.contains("Clean " + sheet._amount(float(ledger.room_upgrade_view("floor").full_reward))), "Home refreshes the actual shared Clean total")
	var milestones := RoomRules.visual_milestones("floor", 1)
	var first_milestone: int = milestones[0]
	ledger.cash = 1e8
	ledger.changed.emit()
	for level in range(1, first_milestone - 1): check(ledger.buy_room_upgrade("floor"), "Home milestone fixture buys floor level%d" % (level + 1))
	await settle()
	button_point = floor_button.get_global_rect().get_center()
	touch(button_point, true)
	touch(button_point, false)
	await settle()
	check(ledger.room_upgrade_levels().floor == first_milestone and sheet.rows[sheet.ROW_IDS[0]].get_node("Row/Words/Status").text.contains("Lv %d" % milestones[1]), "The Home milestone purchase advances to the next authored makeover")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(390, 844), Vector2i(568, 320)]:
		root.size = dimensions
		await settle()
		var sheet_rect: Rect2 = sheet.get_node("%Sheet").get_global_rect()
		check(sheet.get_global_rect().grow(1.0).encloses(sheet_rect), "Five-object Home sheet fits " + str(dimensions))
		check(sheet.get_node("%MenuScroll").size.y > 50.0, "Room offers retain usable scrolling in " + str(dimensions))
		for index in RoomRules.IDS.size():
			var row: Control = sheet.rows[sheet.ROW_IDS[index]]
			for path: String in ["Row/Words/Title", "Row/Words/Status", "Row/Action"]:
				check(row.get_global_rect().grow(1.0).encloses(row.get_node(path).get_global_rect()), path + " fits its Home row in " + str(dimensions))
		await capture("%dx%d" % [dimensions.x, dimensions.y])
	for level in range(first_milestone, Progression.room_level_cap(1)): check(ledger.buy_room_upgrade("floor"), "Home cap fixture buys floor level%d" % (level + 1))
	await settle()
	check(floor_button.disabled and floor_button.text == "Max", "Final Home floor ladder is clearly complete")
	check(not sheet.action_for(sheet.ROW_IDS[1]).disabled and ledger.room_upgrade_view("plants").cost == 25, "Completing the floor leaves plants independently available")
	home.close_management()
	home.open_management("items")
	await settle()
	check(sheet.actions[sheet.ROW_IDS[1]] == "tool" and sheet.rows[sheet.ROW_IDS[1]].get_node("Row/Words/Title").text == "Wide brush", "Tools remain available in the Tools tab")
	home.close_management()
	home.open_management("plans")
	await settle()
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(390, 844), Vector2i(568, 320)]:
		root.size = dimensions
		await settle()
		var scroll: ScrollContainer = sheet.get_node("%MenuScroll")
		check(sheet.get_global_rect().grow(1.0).encloses(sheet.get_node("%Sheet").get_global_rect()), "Six-store section sheet fits " + str(dimensions))
		check(sheet.get_node("%SheetNote").text.contains("Section 1") and sheet.get_node("%SheetNote").text.contains("0/6 stores mastered"), "Section progress stays visible at " + str(dimensions))
		for index in Progression.STORES_PER_SECTION:
			var row: Control = sheet.rows[sheet.PLAN_ROW_IDS[index]]
			check(row.visible and row.get_node("Row/Words/Status").text.contains("Brush cleaning"), "Store %d belongs to the brush-cleaning section" % (index + 1))
			for path: String in ["Row/Words/Title", "Row/Words/Status", "Row/Action"]:
				check(row.get_global_rect().grow(1.0).encloses(row.get_node(path).get_global_rect()), "Section store %d %s fits at %s" % [index + 1, path, str(dimensions)])
		scroll.ensure_control_visible(sheet.action_for("store_6"))
		await settle()
		check(scroll.get_global_rect().grow(1.0).encloses(sheet.action_for("store_6").get_global_rect()), "Store six remains reachable by scrolling at " + str(dimensions))
		check(sheet.rows.next_section.visible and sheet.action_for("next_section").disabled, "Section two is a locked future preview at " + str(dimensions))
		await capture("section_%dx%d" % [dimensions.x, dimensions.y])
	home.free()
	current_scene = null
	root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ledger._save_path))
	print("HOME_ROOM_LADDERS %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
