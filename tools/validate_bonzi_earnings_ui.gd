extends SceneTree
## Real Home sheet and ledger purchases, with a disposable, frozen test clock.
## Required: -- --shop-test. Optional: --bonzi-earnings-capture.

const HOME_SCENE := preload("res://scenes/production/floating_home.tscn")
const Rules := preload("res://scripts/progression.gd")
const Money := preload("res://scripts/money.gd")
const CYCLES := [120, 90, 60]
const PRICES := [100, 300, 900]

var checks := 0
var failures := 0
var ledger: Node
var home: Control
var sheet: Control
var save_path := ""


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Bonzi earnings UI validation requires -- --shop-test to protect player progress.")
		quit(2)
		return
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BONZI_EARNINGS_UI: " + message)


func settle() -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = pressed
	root.push_input(event, true)


func detail(index: int) -> String:
	return sheet.rows[sheet.ROW_IDS[index]].get_node("Row/Words/Status").text


func assert_owned_offer(tier: int, reward: float) -> void:
	var view: Dictionary = ledger.progression_view()
	check(int(view.bonzi_tier) == tier, "The real purchased tier is %d" % tier)
	check(float(view.full_reward) == reward and float(view.bonzi_reward) == reward, "Tier %d pays the current full rug reward %s" % [tier, Money.format(reward)])
	check(sheet.get_node("%Routine").visible, "An owned Bonzi displays its actual cycle bar")
	check(sheet.get_node("%RoutineRate").text == "%s coins / %ds" % [Money.format(reward), CYCLES[tier]], "Tier %d bar quotes the real coins and cycle" % tier)
	if tier < 2:
		check(sheet.rows[sheet.ROW_IDS[1]].visible, "A faster tier remains offered")
		check(sheet.rows[sheet.ROW_IDS[1]].get_node("Row/Words/Title").text == "Faster cycle", "The next tier explains the speed improvement")
		check(detail(1) == "%s coins / %ds" % [Money.format(reward), CYCLES[tier + 1]], "The next tier preserves the full rug coins and shortens the cycle")
		check(sheet.action_for(sheet.ROW_IDS[0]).text == Money.format(Rules.bot_cost(ledger.active_store, tier)), "The next tier preserves its local incremental price")
	else:
		check(not sheet.rows[sheet.ROW_IDS[1]].visible, "The final tier has no fictional faster offer")
		check(sheet.action_for(sheet.ROW_IDS[0]).disabled and sheet.action_for(sheet.ROW_IDS[0]).text == "Max", "The final tier is visibly complete")


func buy_from_sheet(expected_tier: int, price: float) -> void:
	var button: Button = sheet.action_for(sheet.ROW_IDS[0])
	sheet.get_node("%MenuScroll").ensure_control_visible(button)
	await settle()
	check(not button.disabled, "The real Bonzi purchase action is available")
	var point := button.get_global_rect().get_center()
	var before: Dictionary = ledger._capture_state()
	var cash_before: float = ledger.cash
	touch(point, true)
	check(ledger._capture_state() == before, "Touch press does not spend before release")
	touch(point, false)
	await settle()
	check(int(ledger.progression_view().bonzi_tier) == expected_tier and ledger.cash == cash_before - price, "Touch release purchases exactly one tier for its stated price")


func assert_layout(dimensions: Vector2i) -> void:
	var panel: Control = sheet.get_node("%Sheet")
	var scroll: ScrollContainer = sheet.get_node("%MenuScroll")
	check(sheet.get_global_rect().grow(1.0).encloses(panel.get_global_rect()), "The Bonzi sheet fits " + str(dimensions))
	check(scroll.size.y > 80.0, "Bonzi earnings retain usable scrolling in " + str(dimensions))
	for index in 2:
		var row: Control = sheet.rows[sheet.ROW_IDS[index]]
		if not row.visible:
			continue
		for path: String in ["Row/Words/Title", "Row/Words/Status", "Row/Action"]:
			check(row.get_global_rect().grow(1.0).encloses(row.get_node(path).get_global_rect()), path + " fits the Bonzi row in " + str(dimensions))
	var action: Button = sheet.action_for(sheet.ROW_IDS[0])
	check(action.size.x >= 44.0 and action.size.y >= 44.0, "The priced action keeps a reasonable touch target")
	scroll.ensure_control_visible(action)
	await settle()
	check(scroll.get_global_rect().has_point(action.get_global_rect().get_center()), "The priced action can be reached inside the scroll area")


func capture(label: String) -> void:
	if "--bonzi-earnings-capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	var folder := ProjectSettings.globalize_path("res://../art/renders")
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join("bonzi_earnings_" + label + ".png")) == OK, "Save Bonzi earnings " + label + " capture")


func run() -> void:
	ledger = root.get_node("ShopState")
	ledger.set_process(false)
	ledger._test_ticks_msec = 1000
	ledger._test_unix_time = 1791471600.0
	save_path = ProjectSettings.globalize_path("res://.godot/bonzi_earnings_ui_%d.json" % OS.get_process_id())
	ledger._save_path = save_path
	check(ledger.reset_progress(), "Create an isolated Bonzi earnings ledger")
	ledger.cash = 50000
	root.size = Vector2i(320, 720)
	home = HOME_SCENE.instantiate()
	ledger.set_meta("home_animate", false)
	root.add_child(home)
	current_scene = home
	await settle()
	home.open_management("bonzi")
	await settle()
	sheet = home.management
	check(int(ledger.progression_view().full_reward) == 40, "A fresh full carpet quote is40 coins")
	check(not sheet.get_node("%Routine").visible, "Unowned Bonzi has no earning progress bar")
	check(detail(0).contains("3 rugs to meet Bonzi") and detail(0).contains("40 coins / 120s"), "The locked purchase previews the real full reward and three-job gate")
	check(sheet.action_for(sheet.ROW_IDS[0]).disabled and sheet.action_for(sheet.ROW_IDS[0]).text == "100", "The three-job purchase gate preserves its100-coin price")
	await assert_layout(Vector2i(320, 720))
	for job_index in 3:
		var job: String = ledger.start_job()
		check(not ledger.complete_and_start_next_job(job, {"unique_clearance": 1.0, "surface_clearance": 1.0}).is_empty(), "Complete the real unlock fixture commission%d" % (job_index + 1))
	await settle()
	check(not sheet.action_for(sheet.ROW_IDS[0]).disabled and detail(0) == "40 coins / 120s", "Completing three rugs unlocks the same full-reward purchase preview")
	await buy_from_sheet(0, PRICES[0])
	assert_owned_offer(0, 40)
	# A real room purchase emits changed while the Bonzi sheet remains open.
	var floor_quote: Dictionary = ledger.room_upgrade_view("floor")
	check(ledger.buy_room_upgrade("floor"), "Purchase the first independent floor upgrade")
	await settle()
	var upgraded_reward := float(floor_quote.next_full)
	check(int(ledger.room_upgrade_levels().floor) == 1 and float(ledger.progression_view().full_reward) == upgraded_reward and upgraded_reward > 40.0 and upgraded_reward <= Rules.reward_cap(1), "The actual floor purchase supplies its quoted first-store reward within the400000 ceiling")
	assert_owned_offer(0, upgraded_reward)
	var before_delivery: float = ledger.cash
	ledger._test_ticks_msec += 120000
	check(ledger.save_state(), "Commit a real live cycle using the frozen test clock")
	await settle()
	check(ledger.cash == before_delivery + upgraded_reward and float(ledger.progression_view().bonzi_earned) == upgraded_reward, "The displayed upgraded quote is paid by the live ledger")
	check(detail(0) == "%s / 100 earned" % Money.format(upgraded_reward), "The earned counter refreshes from the completed real order")
	for dimensions: Vector2i in [Vector2i(320, 720), Vector2i(800, 360)]:
		root.size = dimensions
		await settle()
		await assert_layout(dimensions)
		assert_owned_offer(0, upgraded_reward)
		await capture("portrait" if dimensions.x < dimensions.y else "landscape")
	root.size = Vector2i(390, 844)
	await settle()
	for tier in [1, 2]:
		await buy_from_sheet(tier, PRICES[tier])
		assert_owned_offer(tier, upgraded_reward)
		var cash_before: float = ledger.cash
		ledger._test_ticks_msec += CYCLES[tier] * 1000
		check(ledger.save_state(), "Commit the tier%d live cycle" % tier)
		await settle()
		check(ledger.cash == cash_before + upgraded_reward, "Faster tier%d still pays the same upgraded quote for its real order" % tier)
	await validate_later_store()
	await finish_tests()


func validate_later_store() -> void:
	ledger.stores["2"] = Rules.new_branch(2)
	ledger.cash = 1e8
	check(ledger.save_state() and ledger.select_store(2), "Fund and visit an isolated second store through the real ledger")
	await settle()
	assert_owned_offer(0, 40.0 * Rules.scale_for(2))
	var room_quote: Dictionary = ledger.room_upgrade_view("window")
	check(ledger.buy_room_upgrade("window"), "A later store independently improves its room earnings")
	await settle()
	var reward := float(room_quote.next_full)
	check(reward > 40.0 * Rules.scale_for(2) and reward <= Rules.reward_cap(2), "The later room quote follows its own scale and ceiling")
	assert_owned_offer(0, reward)
	for dimensions: Vector2i in [Vector2i(320, 720), Vector2i(800, 360)]:
		root.size = dimensions
		await settle()
		await assert_layout(dimensions)
		assert_owned_offer(0, reward)
		await capture("section_store2_%dx%d" % [dimensions.x, dimensions.y])
	root.size = Vector2i(390, 844)
	await settle()
	for tier in [1, 2]:
		var price := Rules.bot_cost(2, tier - 1)
		await buy_from_sheet(tier, price)
		assert_owned_offer(tier, reward)
		var second_earned := float(ledger.progression_view().bonzi_earned)
		ledger._test_ticks_msec += CYCLES[tier] * 1000
		check(ledger.save_state(), "Commit the later store's real tier%d cycle" % tier)
		await settle()
		check(float(ledger.progression_view().bonzi_earned) == second_earned + reward, "The later store earns its own full reward at tier%d" % tier)


func finish_tests() -> void:
	if is_instance_valid(home):
		home.free()
	current_scene = null
	root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	DirAccess.remove_absolute(save_path)
	DirAccess.remove_absolute(save_path + ".bak")
	print("BONZI_EARNINGS_UI_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
