extends SceneTree
var failures := 0
var checks := 0
var hub: Control
var authored_controls: Dictionary = {}

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func frame() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func screenshot(file: String) -> void:
	await frame()
	root.get_texture().get_image().save_png("res://../art/renders/" + file + ".png")

func mouse_click(button: Button) -> void:
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = down
		root.push_input(event, true)

func touch_at(point: Vector2, pressed: bool, index: int = 1) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	root.push_input(event, true)

func drag_touch(start: Vector2, displacement: Vector2, index: int = 1) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = start + displacement
	event.relative = displacement
	root.push_input(event, true)

func check_persistent_controls() -> void:
	for path: NodePath in authored_controls:
		var node := hub.get_node_or_null(path)
		check(node != null and node.get_instance_id() == authored_controls[path], "Authored UI node remains the rendered instance: " + str(path))

func item_card(item_id: String, page_name: String) -> Control:
	for node: Node in hub.get_node("%" + page_name).find_children("*", "PanelContainer", true, false):
		if node.get_script() == load("res://scripts/ui/item_card.gd") and node.item_id == item_id:
			return node
	check(false, "Authored item card exists: " + item_id)
	return null

func item_action(card: Control, action: String) -> Button:
	for node: Node in card.find_children("*", "Button", true, false):
		if str(node.get_meta("action", "")) == action and node.is_visible_in_tree():
			return node
	check(false, "Visible item action exists: " + action)
	return null

func run() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to keep player saves isolated")
		quit(1)
		return
	var ledger: Node = root.get_node("ShopState")
	hub = load("res://scenes/test/shop_hub.tscn").instantiate()
	# These must already exist before _ready: the local editor hierarchy is the UI.
	check(hub.get_node_or_null("%CleanRugButton") is Button, "Paid cleaning button is authored in the packed scene")
	check(hub.get_node_or_null("%PurchaseSheet") is Control, "Purchase sheet exists before runtime initialization")
	var pages: TabContainer = hub.get_node("%Pages")
	check(pages.get_child_count() == 5, "All five management pages are serialized in the editor")
	# Native scrollbars/tab internals are engine implementation details, not authored nodes.
	for node: Node in hub.find_children("*", "Control", true, true):
		authored_controls[hub.get_path_to(node)] = node.get_instance_id()
		check(node.owner != null, "Visible UI control has a scene owner: " + str(hub.get_path_to(node)))
	var brand: Label = hub.get_node("%Brand")
	var original_brand := brand.text
	brand.text = "My editable shop"
	var shell: MarginContainer = hub.get_node("%Shell")
	var original_margin := shell.get_theme_constant("margin_left")
	shell.add_theme_constant_override("margin_left", original_margin + 7)
	root.add_child(hub)
	current_scene = hub
	await frame()
	check(brand.text == "My editable shop", "Authored static label text survives runtime initialization")
	check(shell.get_theme_constant("margin_left") == original_margin + 7, "Authored shell margins survive runtime layout")
	check(ledger.cash == 0 and ledger.manual_jobs == 0, "First visit starts free with no cash or completed jobs")
	check(hub.get_node("%CleanRugButton").is_visible_in_tree(), "Shop has a visible entry into paid cleaning")
	for tab: String in ["shop", "items", "plans", "bonzi"]:
		var target: Button = hub.tabs[tab]
		mouse_click(target)
		await frame()
		check(hub.current_tab == tab, "Mouse navigation opens " + tab)
		check(hub.scroll.get_global_rect().end.y < target.get_global_rect().position.y, "Scrolling content stays above navigation")
		for button: Button in hub.buttons:
			if not is_instance_valid(button) or not button.is_visible_in_tree(): continue
			var rect := button.get_global_rect()
			check(rect.position.x >= -1 and rect.end.x <= hub.size.x + 1, "Buttons fit horizontally: " + button.text)
	# Touch follows the same navigation path with emulated mouse disabled.
	var touch_point: Vector2 = hub.tabs["items"].get_global_rect().get_center()
	touch_at(touch_point, true)
	check(hub.current_tab == "bonzi", "Touch-down alone never activates navigation")
	touch_at(touch_point, false)
	await frame()
	check(hub.current_tab == "items", "Real touch selects Items")
	touch_point = hub.tabs["plans"].get_global_rect().get_center()
	touch_at(touch_point, true)
	drag_touch(touch_point, Vector2(0, -60))
	touch_at(touch_point, false)
	check(hub.current_tab == "items", "Dragging away and back cancels a tap")
	# Swipes actually move the persistent page; earnings must not jump it to the top.
	hub.scroll.scroll_vertical = 0
	await frame()
	touch_point = hub.scroll.get_global_rect().get_center()
	touch_at(touch_point, true)
	drag_touch(touch_point, Vector2(0, -130))
	touch_at(touch_point + Vector2(0, -130), false)
	await frame()
	check(hub.scroll.scroll_vertical > 0, "Touch swiping scrolls long menu content")
	var retained_scroll: int = hub.scroll.scroll_vertical
	ledger.changed.emit()
	await frame()
	check(hub.scroll.scroll_vertical == retained_scroll, "Refreshing cash retains reading position")
	hub.show_tab("plans")
	await frame()
	hub.show_tab("items")
	await frame()
	check(hub.scroll.scroll_vertical == retained_scroll, "Returning to a tab restores its reading position")
	hub.show_tab("expansion")
	ledger.changed.emit()
	await frame()
	check(hub.current_tab == "expansion", "State changes preserve the open future-location preview")
	check(brand.text == "My editable shop" and shell.get_theme_constant("margin_left") == original_margin + 7, "Earnings refresh preserves authored copy and spacing")
	check_persistent_controls()
	brand.text = original_brand
	shell.add_theme_constant_override("margin_left", original_margin)
	for tab: String in ["shop", "items", "plans", "bonzi"]:
		hub.show_tab(tab)
		hub.scroll.scroll_vertical = 0
		await screenshot("shop_" + tab)
	# Seed earned progress through the same guarded ledger transactions.
	for i in 20:
		var job: String = ledger.start_job()
		check(ledger.save_job_snapshot({"unique_clearance":1.0, "surface_clearance":1.0}), "Test job saves")
		check(ledger.complete_job(job), "Test job pays")
		if i == 2:
			await frame()
			var saving_goal: Control = hub.get_node("%SaveGoal")
			var saving_copy: Label = saving_goal.find_child("Description", true, false)
			check(saving_goal.visible and saving_copy.text.contains("40") and saving_copy.text.contains("2 customer rugs"), "First blueprint explains the exact cash gap and two-job route to Bonzi")
		if i == 4:
			await frame()
			check(hub.get_node("%BuildGoal").visible, "Five base jobs change the main goal to building Bonzi")
			hub.follow_goal()
			await frame()
			check(hub.get_node("%PurchaseSheet").visible and not ledger.owns("bonzi"), "Affordable main goal opens Bonzi's purchase review")
			hub.cancel_build()
	await frame()
	var purchase_sheet: Control = hub.get_node("%PurchaseSheet")
	var confirm: Button = hub.get_node("%ConfirmBuildButton")
	hub.show_tab("items")
	await frame()
	var wide_card := item_card("wide_brush", "ItemsPage")
	var wide_build := item_action(wide_card, "build")
	hub.scroll.ensure_control_visible(wide_build)
	await frame()
	touch_point = wide_build.get_global_rect().get_center()
	touch_at(touch_point, true)
	drag_touch(touch_point, Vector2(0, -80))
	touch_at(touch_point + Vector2(0, -80), false)
	await frame()
	check(not purchase_sheet.visible and not ledger.owns("wide_brush"), "Swiping over an affordable Build action never opens a purchase")
	var before_purchase: int = ledger.cash
	hub.request_build("bonzi")
	await frame()
	check(purchase_sheet.is_visible_in_tree() and not confirm.disabled, "Affordable build opens a reviewable confirmation sheet")
	check(ledger.cash == before_purchase and not ledger.owns("bonzi"), "Opening purchase details never spends cash")
	mouse_click(hub.get_node("%CancelBuildButton"))
	await frame()
	check(not purchase_sheet.visible and ledger.cash == before_purchase and not ledger.owns("bonzi"), "Cancel keeps cash and ownership untouched")
	hub.request_build("bonzi")
	await frame()
	mouse_click(confirm)
	await frame()
	check(ledger.owns("bonzi") and ledger.cash == before_purchase - 100 and not purchase_sheet.visible, "Confirm builds Bonzi once and closes the sheet")
	hub.confirm_build()
	check(ledger.cash == before_purchase - 100, "Duplicate confirmation cannot purchase twice")
	for item: String in ["bonzi_mk2", "intake", "wide_brush"]:
		hub.request_build(item)
		await frame()
		check(purchase_sheet.visible and not confirm.disabled, "Earned upgrade is reviewable: " + item)
		hub.confirm_build()
		await frame()
		check(ledger.owns(item), "Confirmed upgrade is owned: " + item)
	check(ledger.equipped_brush == "wide_brush", "New Wide Brush is equipped immediately")
	check(hub.get_node("%SettledGoal").visible, "Fully equipped starter shop presents an honest completed goal")
	hub.show_tab("items")
	await frame()
	var equip_hand := item_action(item_card("hand_brush", "ItemsPage"), "equip")
	hub.scroll.ensure_control_visible(equip_hand)
	await frame()
	var before_equipping: int = ledger.cash
	mouse_click(equip_hand)
	await frame()
	check(ledger.equipped_brush == "hand_brush" and ledger.cash == before_equipping, "Items lets the player equip the owned starter brush for free")
	var equip_wide := item_action(wide_card, "equip")
	hub.scroll.ensure_control_visible(equip_wide)
	await frame()
	mouse_click(equip_wide)
	await frame()
	check(ledger.equipped_brush == "wide_brush" and ledger.cash == before_equipping, "Items lets the player return to the owned wider brush for free")
	var notice: Control = hub.get_node("%Notice")
	check(not notice.visible or not notice.get_global_rect().intersects(hub.get_node("%CleanRugButton").get_global_rect()), "Status feedback keeps the primary cleaning action readable")
	hub.show_tab("bonzi")
	await screenshot("shop_bonzi_working")
	check(ledger.output_per_hour() == 45.0, "Fully upgraded first shop produces 45 orders/hour")
	# Return summaries describe existing cash and remain until acknowledged.
	ledger.return_reward = 30
	ledger.return_seconds = 240.0
	ledger.changed.emit()
	hub.show_tab("shop")
	await frame()
	var return_card: Control = hub.get_node("%ReturnCard")
	check(return_card.visible, "Away earnings summary appears on the shop page")
	hub.show_tab("items")
	hub.show_tab("shop")
	ledger.changed.emit()
	await frame()
	check(return_card.visible and ledger.return_reward == 30, "Navigation and earnings refresh do not dismiss the return summary")
	var before_acknowledge: int = ledger.cash
	hub.acknowledge_return()
	await frame()
	check(not return_card.visible and ledger.return_reward == 0 and ledger.cash == before_acknowledge, "Acknowledgement clears the summary without paying again")
	check_persistent_controls()
	# Keep later tabs useful on a wider window too.
	root.content_scale_size = Vector2i(1100, 760)
	root.size = Vector2i(1100, 760)
	hub.show_tab("shop")
	await screenshot("shop_landscape")
	check(root.get_texture().get_size() == Vector2(1100, 760), "Wide-layout validation renders the requested landscape viewport")
	check(hub.shell.get_global_rect().position.x >= 0 and hub.shell.get_global_rect().end.x <= hub.size.x, "Authored hub shell fits a wider window")
	check(not notice.visible or not notice.get_global_rect().intersects(hub.get_node("%CleanRugButton").get_global_rect()), "Wide status feedback stays clear of the primary action")
	for tab: String in ["shop", "items", "plans", "bonzi"]:
		hub.show_tab(tab)
		await frame()
		for button: Button in hub.buttons:
			if not button.is_visible_in_tree(): continue
			check(button.get_global_rect().position.x >= 0 and button.get_global_rect().end.x <= hub.size.x, "Menu action fits wide viewport: " + button.name)
	root.content_scale_size = Vector2i(720, 1000)
	root.size = Vector2i(720, 1000)
	hub.enter_cleaning()
	await frame()
	check(current_scene.name == "RugCleaningGym", "Paid button opens the cleaning scene")
	check(current_scene.paid_contract, "Paid job keeps contract mode")
	check(current_scene.wide_brush, "The customer rug uses the brush selected in Items")
	check(current_scene.soil.automatic_completion_enabled == false, "Paid work requires explicit completion")
	await screenshot("shop_paid_rug")
	current_scene.return_to_shop()
	await frame()
	check(current_scene.scene_file_path == "res://scenes/production/floating_home.tscn", "Legacy menu's paid rug returns to the production main menu")
	check(not ledger.active_job_id.is_empty(), "Returning preserves the active customer rug")
	print("SHOP UI: ", checks, " checks; ", failures, " failures")
	quit(0 if failures == 0 else 1)
