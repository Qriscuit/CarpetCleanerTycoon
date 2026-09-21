extends SceneTree
var checks := 0
var failures := 0
var home: Control

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func tap(button: Button, canceled := false) -> void:
	for down: bool in [true,false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = button.get_global_rect().get_center()
		touch.pressed = down
		touch.canceled = canceled and not down
		root.push_input(touch,true)

func run() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		quit(2)
		return
	var state := root.get_node("ShopState")
	state.cash = 800
	state.manual_jobs = 10
	state._refresh_blueprints()
	state.build("bonzi")
	state.build("bonzi_mk2")
	state.build("intake")
	state.start_job()
	home = load("res://scenes/production/floating_home.tscn").instantiate()
	root.add_child(home)
	current_scene = home
	home.animate_shop = false
	root.size = Vector2i(390,844)
	await settle()
	check(home.get_node_or_null("%Hint") == null and not home.get_node("%StatusMessage").visible, "No persistent text under the house")
	for state_name: String in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
		check(home.get_node("%ShopTap").get_theme_stylebox(state_name) is StyleBoxEmpty, "House has no color overlay in " + state_name)
	tap(home.get_node("%NavBonzi"))
	await settle()
	check(home.management.get_node("%RoutineRate").text == "10 coins every 80s", "Bonzi shows reward per actual bar length")
	check(home.management.get_node("%RoutineTime").text.begins_with("Next +10 in"), "Countdown states the next payout")
	root.get_texture().get_image().save_png("res://../art/renders/bonzi_cycle_payout.png")
	tap(home.management.get_node("%CloseSheet"))
	tap(home.get_node("%Settings"))
	await settle()
	var readable_blue := Color(0.20784314,0.34509805,0.4627451,1)
	for node_name: String in ["MotionToggle","ResetProgress","CloseSettings","CancelReset","ConfirmReset"]:
		var control: Button = home.get_node("%"+node_name)
		for color_name: String in ["font_color","font_focus_color","font_pressed_color","font_hover_color","font_hover_pressed_color","font_disabled_color"]:
			check(control.get_theme_color(color_name).is_equal_approx(readable_blue), "%s keeps readable %s text" % [node_name,color_name])
	root.get_texture().get_image().save_png("res://../art/renders/home_settings.png")
	var before: int = state.cash
	for dimensions: Vector2i in [Vector2i(320,568),Vector2i(390,844),Vector2i(844,390)]:
		root.size = dimensions
		await settle()
		check(home._safe_rect().encloses(home.get_node("%SettingsPanel").get_global_rect()), "Settings fits " + str(dimensions))
		tap(home.get_node("%ResetProgress"))
		await settle()
		check(state.cash == before and home.reset_pending, "Opening reset review does not erase progress")
		check(home._safe_rect().encloses(home.get_node("%SettingsPanel").get_global_rect()), "Reset review fits %s: panel %s, safe %s" % [dimensions,home.get_node("%SettingsPanel").get_global_rect(),home._safe_rect()])
		for node_name: String in ["CancelReset","ConfirmReset"]:
			check(home.get_node("%SettingsPanel").get_global_rect().encloses(home.get_node("%"+node_name).get_global_rect()), node_name + " fits review")
		home._back()
		check(not home.reset_pending and home.get_node("%SettingsSheet").visible and state.cash == before, "Back dismisses reset without deleting progress")
	root.size = Vector2i(390,844)
	await settle()
	tap(home.get_node("%ResetProgress"))
	await settle()
	tap(home.get_node("%ConfirmReset"),true)
	check(state.cash == before and home.reset_pending, "Canceled touch cannot reset progress")
	root.get_texture().get_image().save_png("res://../art/renders/home_reset_confirmation.png")
	var path: String = state._save_path
	state._save_path += "/cannot-write.json"
	tap(home.get_node("%ConfirmReset"))
	await settle()
	check(state.cash == before and home.reset_pending and home.get_node("%ResetError").visible, "Failed reset displays an error and preserves progress")
	state._save_path = path
	tap(home.get_node("%CancelReset"))
	await settle()
	check(state.cash == before and not home.reset_pending, "Keep playing cancels reset")
	tap(home.get_node("%ResetProgress"))
	await settle()
	tap(home.get_node("%ConfirmReset"))
	await settle()
	check(state.cash == 0 and not state.owns("bonzi") and state.active_job_id.is_empty(), "Confirmed reset clears earned progress")
	check(not home.get_node("%SettingsSheet").visible and home.get_node("%Cash").text == "0", "Reset refreshes the home wallet")
	state.cash = 3
	home._confirm_reset()
	check(state.cash == 3, "Stale repeated confirmation cannot reset again")
	state.cash = 0
	home._clear_status()
	await settle()
	root.get_texture().get_image().save_png("res://../art/renders/home_no_hint.png")
	print("HOME_SETTINGS_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
