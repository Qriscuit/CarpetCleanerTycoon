extends SceneTree
var failures := 0
var checks := 0
var hub: Control

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

func run() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to keep player saves isolated")
		quit(1)
		return
	var ledger: Node = root.get_node("ShopState")
	hub = load("res://scenes/shop_hub.tscn").instantiate()
	root.add_child(hub)
	current_scene = hub
	await frame()
	check(ledger.cash == 0 and ledger.manual_jobs == 0, "First visit starts free with no cash or completed jobs")
	check(hub.page.find_child("CleanRugButton", true, false) != null, "Shop has an entry into paid cleaning")
	for tab: String in ["shop", "items", "plans", "bonzi"]:
		var target: Button = hub.tabs[tab]
		for down: bool in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.position = target.get_global_rect().get_center()
			e.pressed = down
			root.push_input(e, true)
		await frame()
		check(hub.current_tab == tab, "Mouse navigation opens " + tab)
		check(hub.scroll.get_global_rect().end.y < target.get_global_rect().position.y, "Scrolling content stays above navigation")
		for button: Button in hub.buttons:
			if not is_instance_valid(button) or not button.is_visible_in_tree(): continue
			var rect := button.get_global_rect()
			check(rect.position.x >= -1 and rect.end.x <= hub.size.x + 1, "Buttons fit horizontally: " + button.text)
		await screenshot("shop_" + tab)
	# Touch follows the same navigation path with emulated mouse disabled.
	var touch := InputEventScreenTouch.new()
	touch.index = 1
	touch.pressed = true
	touch.position = hub.tabs["items"].get_global_rect().get_center()
	root.push_input(touch, true)
	check(hub.current_tab == "bonzi", "Touch-down alone never activates navigation")
	touch.pressed = false
	root.push_input(touch, true)
	await frame()
	check(hub.current_tab == "items", "Real touch selects Items")
	touch.position = hub.tabs["plans"].get_global_rect().get_center()
	touch.pressed = true
	root.push_input(touch, true)
	var drag := InputEventScreenDrag.new()
	drag.index = touch.index
	drag.position = touch.position + Vector2(0, -60)
	root.push_input(drag, true)
	touch.pressed = false
	root.push_input(touch, true)
	check(hub.current_tab == "items", "Dragging away and back cancels a tap")
	# Seed earned progress through the same guarded ledger transactions.
	for i in 16:
		var job: String = ledger.start_job()
		check(ledger.save_job_snapshot({"unique_clearance":1.0, "surface_clearance":1.0}), "Test job saves")
		check(ledger.complete_job(job), "Test job pays")
	check(ledger.build("bonzi"), "Bonzi can be built after earned cash and blueprint")
	check(ledger.build("bonzi_mk2"), "Mk II uses the unlocked blueprint")
	check(ledger.build("intake"), "Intake purchase combines with Mk II")
	hub.show_tab("bonzi")
	await screenshot("shop_bonzi_working")
	check(ledger.output_per_hour() == 45.0, "Fully upgraded first shop produces 45 orders/hour")
	# Keep later tabs useful on a wider window too.
	root.size = Vector2i(1100, 760)
	hub.show_tab("shop")
	await screenshot("shop_landscape")
	check(hub.shell.size.x <= 800, "Hub width stays readable on a wide screen")
	root.size = Vector2i(720, 1000)
	hub.enter_cleaning()
	await frame()
	check(current_scene.name == "RugCleaningGym", "Paid button opens the cleaning scene")
	check(current_scene.paid_contract, "Paid job keeps contract mode")
	check(current_scene.soil.automatic_completion_enabled == false, "Paid work requires explicit completion")
	await screenshot("shop_paid_rug")
	current_scene.return_to_shop()
	await frame()
	check(current_scene.name == "ShopHub", "Return navigation reaches the hub")
	check(not ledger.active_job_id.is_empty(), "Returning preserves the active customer rug")
	print("SHOP UI: ", checks, " checks; ", failures, " failures")
	quit(0 if failures == 0 else 1)
