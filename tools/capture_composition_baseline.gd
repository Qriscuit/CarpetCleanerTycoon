extends SceneTree
## Before-layout screenshots from disposable production gameplay, including departure.
## --composition-phone preserves the real 720x1000 canvas and captures phone UI
## in composition_phone; --composition-phone-first saves only the 591x1280 view.
## --composition-shop captures the integrated in-carpet manual-tool shop on the
## actual production canvas, preserving the earlier composition previews.
const Room := preload("res://scripts/room_upgrades.gd")
const Rules := preload("res://scripts/progression.gd")
var game: Node
var ledger: Node
var save_path := ""
var folder := ""
var failures := 0
var phone_mode := false

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		printerr("Composition capture requires a renderer and -- --shop-test.")
		quit(2)
		return
	phone_mode = "--composition-phone" in OS.get_cmdline_user_args() or "--composition-shop" in OS.get_cmdline_user_args()
	run.call_deferred()

func frame() -> void:
	await process_frame
	if is_instance_valid(game) and not game.application_focused: game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await RenderingServer.frame_post_draw

func capture(label: String) -> void:
	await frame()
	var path := folder.path_join(label + ".png")
	if not phone_mode and "--composition-after" not in OS.get_cmdline_user_args() and FileAccess.file_exists(path):
		failures += 1
		push_error("The before-composition preview is preserved: " + path)
		return
	var image := root.get_texture().get_image()
	if image.save_png(path) != OK:
		failures += 1
		push_error("Could not save composition baseline: " + path)
	else:
		print("COMPOSITION_BASELINE " + path)
		if phone_mode:
			print("PHONE_COMPOSITION observed_window=", DisplayServer.window_get_size(), "; root_window=", root.size, "; image=", image.get_size(), "; reference=", root.content_scale_size, "; viewport=", root.get_visible_rect().size, "; hud_scale=", game.hud.get_node("HUD").scale)

func wait_cleaning() -> void:
	for _tick in 240:
		if game.rug_phase == game.RugPhase.CLEANING: return
		await frame()
	failures += 1
	push_error("Baseline rug did not become playable")

func set_room_mastery() -> void:
	ledger.room_upgrade_view("floor")
	var branch: Dictionary = ledger._branch()
	for id: String in Room.IDS: branch.room_upgrades[id] = Rules.room_level_cap(1)
	branch.payout_level = Room.total_levels(branch.room_upgrades)
	if not ledger.active_job_id.is_empty(): branch.job_early_reward = Room.early_reward(1,branch)
	ledger.cash = 1000000.0
	ledger.save_state()

func run() -> void:
	if "--composition-shop" in OS.get_cmdline_user_args():
		await run_phone_shop()
		return
	if phone_mode:
		await run_phone()
		return
	ledger = root.get_node("ShopState")
	ledger.set_process(false)


	save_path = "res://.godot/composition_baseline_%d.json" % OS.get_process_id()
	ledger._save_path = save_path
	ledger.reset_progress()
	ledger.cash = 1000.0
	ledger.save_state()
	folder = ProjectSettings.globalize_path("res://../art/renders/composition_after" if "--composition-after" in OS.get_cmdline_user_args() else "res://../art/renders/composition_before")
	DirAccess.make_dir_recursive_absolute(folder)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await wait_cleaning()
	for size: Vector2i in [Vector2i(320,568),Vector2i(390,844),Vector2i(568,320),Vector2i(844,390),Vector2i(768,1024),Vector2i(1024,768)]:
		root.content_scale_size = size
		root.size = size
		await frame()
		game.frame_carpet()
		await capture("starter_%dx%d" % [size.x,size.y])
	set_room_mastery()
	for size: Vector2i in [Vector2i(320,568),Vector2i(390,844),Vector2i(568,320),Vector2i(844,390),Vector2i(768,1024),Vector2i(1024,768)]:
		root.content_scale_size = size
		root.size = size
		await frame()
		game.frame_carpet()
		await capture("mastered_%dx%d" % [size.x,size.y])
	root.content_scale_size = Vector2i(390,844)
	root.size = Vector2i(390,844)
	await frame()
	game.frame_carpet()
	game.soil.remaining = 0
	game.soil.surface_coverage_total = 0.0
	game.update_contract_status()
	await frame()
	for _tick in 180:
		if game.soil.vacuum_complete: break
		game.soil._physics_process(1.0 / 60.0)
	await frame()
	if game.rug_phase == game.RugPhase.REVEAL:
		game.completion_reveal.remaining = 30.0
		for _tick in 18: await frame()
		await capture("mastered_reveal_390x844")
		game.skip_completion_reveal()
		var open_saved := false
		var rolled_saved := false
		for _tick in 300:
			await frame()
			if not open_saved and game.room.window_open_amount >= 0.99:
				await capture("mastered_open_window_390x844")
				open_saved = true
			if not rolled_saved and game.rug_phase == game.RugPhase.DEPARTING and game.get_node("RugDisplay").position.z < -0.6:
				await capture("mastered_departure_390x844")
				rolled_saved = true
			if rolled_saved and game.rug_phase == game.RugPhase.CLEANING: break
	else:
		failures += 1
		push_error("Baseline completion did not reach its reveal")
	game.free()
	current_scene = null
	var audio := root.get_node_or_null("GameAudio")
	if audio != null: audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if FileAccess.file_exists(save_path + ".tmp"): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + ".tmp"))
	print("COMPOSITION_BASELINE_CAPTURE %d failures" % failures)
	quit(0 if failures == 0 else 1)

func phone_settle() -> void:
	for _tick: int in 8: await frame()
	game.frame_carpet()
	await frame()
	if root.content_scale_size != Vector2i(720, 1000):
		failures += 1
		push_error("Phone previews must retain the production 720x1000 reference canvas")

func phone_progress() -> void:
	# Skip only the fixture's labor: the production eligibility path decides
	# the real 84% progress text, quoted Finish button and modal availability.
	game.soil.remaining = floori(game.soil.initial.size() * 0.16)
	game.soil.surface_coverage_total = game.soil.surface_pixel_count * 0.16
	game.update_contract_status()
	if game.state_label.text != "84%" or not game.finish_button.visible:
		failures += 1
		push_error("The phone preview must show 84% and its earned Finish action")

func phone_expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("PHONE_COMPOSITION: " + message)

func phone_button_bounds(button: Button, panel: Control) -> void:
	var bounds := button.get_global_rect()
	phone_expect(game.hud._safe_rect().grow(0.5).encloses(bounds), button.name + " stays fully inside the safe screen")
	phone_expect(panel.get_global_rect().grow(0.5).encloses(bounds), button.name + " stays fully inside its purchase panel")
	phone_expect(game.hud.visible_button_at(bounds.get_center(), game.hud.action_buttons()) == button, button.name + " remains available to the real touch route")

func phone_touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 5
	event.position = point
	event.pressed = pressed
	root.push_input(event, true)

func phone_drawer_accessibility() -> void:
	var panel: Control = game.hud.control("UpgradesPanel")
	var done: Button = game.hud.control("CloseUpgradesButton")
	var buy: Button = game.hud.control("ToolUpgradeButton")
	phone_button_bounds(done, panel)
	phone_button_bounds(buy, panel)
	var scroll: ScrollContainer = game.hud.control("ToolCardsScroll")
	var bar := scroll.get_v_scroll_bar()
	if bar.max_value <= bar.page + 0.5: return
	var done_bounds := done.get_global_rect()
	var buy_bounds := buy.get_global_rect()
	var before_cash: float = ledger.cash
	var before_job: String = ledger.active_job_id
	var origin := scroll.get_global_rect().get_center()
	phone_touch(origin, true)
	var point := origin
	for _step: int in 3:
		var drag := InputEventScreenDrag.new()
		drag.index = 5
		drag.relative = Vector2(0, -scroll.get_global_rect().size.y * 0.3)
		point += drag.relative
		drag.position = point
		root.push_input(drag, true)
	phone_touch(point, false)
	await frame()
	await frame()
	phone_expect(scroll.scroll_vertical > 0, "A real finger drag reaches the clipped tool comparison")
	phone_expect(scroll.get_global_rect().grow(0.5).encloses(game.hud.control("NextToolStats").get_global_rect()), "Scrolling exposes both next-tool stat lines")
	phone_expect(done.get_global_rect().is_equal_approx(done_bounds) and buy.get_global_rect().is_equal_approx(buy_bounds), "Done and Buy stay fixed while tool cards scroll")
	phone_expect(ledger.cash == before_cash and ledger.active_job_id == before_job, "A card swipe cannot buy equipment or replace the rug")
	scroll.scroll_vertical = 0
	await frame()
	print("PHONE_DRAWER_BOUNDS Done=", done_bounds, "; Buy=", buy_bounds, "; safe=", game.hud._safe_rect())

func phone_room_accessibility() -> void:
	var panel: Control = game.hud.room_panel.get_node("%Card")
	for button: Button in game.hud.room_panel.action_buttons(): phone_button_bounds(button, panel)

func phone_scroll(scroll: ScrollContainer, direction: float = -1.0) -> void:
	var rect := scroll.get_global_rect()
	var point := rect.position + Vector2(rect.size.x * 0.5,rect.size.y * 0.24)
	phone_touch(point,true)
	for _step: int in 3:
		var drag := InputEventScreenDrag.new()
		drag.index = 5
		drag.relative = Vector2(0,direction * rect.size.y * 0.30)
		point += drag.relative
		drag.position = point
		root.push_input(drag,true)
	phone_touch(point,false)
	await frame()
	await frame()

func phone_shop_accessibility(label: String) -> void:
	var panel: Control = game.hud.control("UpgradesPanel")
	var done: Button = game.hud.control("CloseUpgradesButton")
	var buy: Button = game.hud.control("ToolUpgradeButton")
	phone_button_bounds(done,panel)
	var done_bounds := done.get_global_rect()
	var scroll: ScrollContainer = game.hud.control("ShopContentsScroll")
	var before_cash: float = ledger.cash
	var before_job: String = ledger.active_job_id
	var before_tool: int = int(ledger._branch().tool_level)
	for _step: int in 8:
		if game.hud.visible_button_at(buy.get_global_rect().get_center(),game.hud.action_buttons()) == buy: break
		await phone_scroll(scroll)
	phone_button_bounds(buy,panel)
	phone_expect(done.get_global_rect().is_equal_approx(done_bounds), "Done stays fixed while the integrated shop scrolls")
	phone_expect(ledger.cash == before_cash and ledger.active_job_id == before_job and int(ledger._branch().tool_level) == before_tool, "A shop swipe does not buy a tool or replace the carpet")
	await capture(label + "_tool_action")
	print("PHONE_SHOP_BOUNDS Done=",done_bounds,"; ToolBuy=",buy.get_global_rect(),"; Scroll=",scroll.get_global_rect(),"; safe=",game.hud._safe_rect())
	var cards: ScrollContainer = game.hud.control("ToolCardsScroll")
	if cards.get_v_scroll_bar().max_value > cards.get_v_scroll_bar().page + 0.5:
		var buy_bounds := buy.get_global_rect()
		await phone_scroll(cards)
		phone_expect(cards.scroll_vertical > 0,"Actual touch scrolling reaches the next tool comparison")
		phone_expect(cards.get_global_rect().grow(0.5).encloses(game.hud.control("NextToolStats").get_global_rect()),"Both next-tool stats remain readable after the card swipe")
		phone_expect(done.get_global_rect().is_equal_approx(done_bounds) and buy.get_global_rect().is_equal_approx(buy_bounds),"Done and Buy remain fixed during comparison scrolling")
		phone_expect(ledger.cash == before_cash and ledger.active_job_id == before_job and int(ledger._branch().tool_level) == before_tool,"A comparison swipe does not spend coins or replace the carpet")
		await capture(label + "_tool_comparison")

func run_phone_shop() -> void:
	ledger = root.get_node("ShopState")
	ledger.set_process(false)


	save_path = "res://.godot/composition_shop_%d.json" % OS.get_process_id()
	ledger._save_path = save_path
	phone_expect(ledger.reset_progress(), "Integrated shop uses a fresh disposable save")
	ledger.cash = 1000.0
	phone_expect(ledger.save_state(), "Manual-tool capture fixture is saved")
	folder = ProjectSettings.globalize_path("res://../art/renders/composition_integrated")
	DirAccess.make_dir_recursive_absolute(folder)
	root.size = Vector2i(591,1280)
	root.title = "Carpet Cleaner · Integrated shop (test save)"
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	game.soil.suspend_simulation(true)
	game.set_physics_process(false)
	await phone_settle()
	phone_progress()
	for size: Vector2i in [Vector2i(591,1280),Vector2i(390,844),Vector2i(844,390)]:
		root.size = size
		await phone_settle()
		game.hud.open_upgrades()
		await phone_settle()
		var label := "shop_manual_%dx%d" % [size.x,size.y]
		await capture(label + "_top")
		await phone_shop_accessibility(label)
		game.hud.close_upgrades()
		await phone_settle()
	game.free()
	game = null
	current_scene = null
	root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	print("COMPOSITION_INTEGRATED_SHOP_CAPTURE %d failures" % failures)
	quit(0 if failures == 0 else 1)

func run_phone() -> void:
	ledger = root.get_node("ShopState")
	ledger.set_process(false)


	save_path = "res://.godot/composition_phone_%d.json" % OS.get_process_id()
	ledger._save_path = save_path
	if not ledger.reset_progress(): failures += 1
	ledger.cash = 1000.0
	if not ledger.save_state(): failures += 1
	folder = ProjectSettings.globalize_path("res://../art/renders/composition_phone")
	DirAccess.make_dir_recursive_absolute(folder)
	root.size = Vector2i(591, 1280)
	root.title = "Carpet Cleaner · Phone composition (test save)"
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	game.soil.suspend_simulation(true)
	game.set_physics_process(false)
	await phone_settle()
	phone_progress()
	await phone_settle()
	await capture("starter_84_finish_591x1280")
	if "--composition-phone-first" not in OS.get_cmdline_user_args():
		for size: Vector2i in [Vector2i(591,1280), Vector2i(390,844), Vector2i(1080,2340), Vector2i(844,390)]:
			root.size = size
			await phone_settle()
			phone_progress()
			await phone_settle()
			if size != Vector2i(591,1280): await capture("starter_84_finish_%dx%d" % [size.x,size.y])
			game.hud.open_upgrades()
			await phone_settle()
			await capture("tool_drawer_%dx%d" % [size.x,size.y])
			await phone_drawer_accessibility()
			game.hud.close_upgrades()
			await phone_settle()
			game.open_room_upgrade("floor")
			await phone_settle()
			phone_room_accessibility()
			await capture("room_offer_%dx%d" % [size.x,size.y])
			game.hud.close_upgrades()
			await phone_settle()
		set_room_mastery()
		if (game.hud.control("CarpetEarningsValue") as Label).text != "400K":
			failures += 1
			push_error("The mastered phone preview must show the durable 400K carpet quote")
		for size: Vector2i in [Vector2i(591,1280), Vector2i(390,844), Vector2i(1080,2340), Vector2i(844,390)]:
			root.size = size
			await phone_settle()
			phone_progress()
			await phone_settle()
			await capture("mastered_84_finish_%dx%d" % [size.x,size.y])
	game.free()
	game = null
	current_scene = null
	var audio := root.get_node_or_null("GameAudio")
	if audio != null: audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	print("COMPOSITION_PHONE_CAPTURE %d failures" % failures)
	quit(0 if failures == 0 else 1)
