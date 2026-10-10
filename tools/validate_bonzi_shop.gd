extends SceneTree
## Real Bonzi transactions, responsive shop controls and owned dismissal gestures.
const Money := preload("res://scripts/money.gd")
var game: Node
var ledger: Node
var checks := 0
var failures := 0
var save_path := ""
var folder := ""

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		printerr("Bonzi shop validation requires a renderer and -- --shop-test.")
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BONZI SHOP: " + message)

func frame() -> void:
	await process_frame
	if is_instance_valid(game) and not game.application_focused: game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await RenderingServer.frame_post_draw

func touch(point: Vector2, pressed: bool, canceled: bool = false, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event,true)

func drag(origin: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.position = origin + relative
	event.relative = relative
	event.index = 0
	root.push_input(event,true)

func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event,true)

func enter() -> void:
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frame()
	await frame()

func leave() -> void:
	game.free()
	current_scene = null
	game = null
	await process_frame

func open_shop() -> void:
	game.hud.open_upgrades()
	await create_timer(0.22).timeout
	await frame()
	check(game.hud.upgrades_open() and game.soil.simulation_suspended, "Opening the shop pauses cleaning")

func reveal(button: Control) -> void:
	var parent := button.get_parent()
	while parent is Control:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
		parent = parent.get_parent()
	await frame()
	await frame()

func tap(button: Button) -> void:
	await reveal(button)
	var point := button.get_global_rect().get_center()
	touch(point,true)
	check(not game.brush_dragging, "A shop action owns its touch without cleaning underneath")
	touch(point,false)
	await frame()

func capture(name: String) -> void:
	if "--bonzi-capture" not in OS.get_cmdline_user_args(): return
	await frame()
	check(root.get_texture().get_image().save_png(folder.path_join(name + ".png")) == OK, "The Bonzi shop preview saves")

func scroll_to_bonzi() -> void:
	var scroll: ScrollContainer = game.hud.control("ShopContentsScroll")
	var button: Button = game.hud.control("BonziUpgradeButton")
	var done_rect: Rect2 = game.hud.control("CloseUpgradesButton").get_global_rect()
	var before_cash: float = ledger.cash
	var before_job: String = ledger.active_job_id
	var overflow := scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page
	if game.hud._shop_stacked and overflow > 0.5:
		var origin := scroll.get_global_rect().get_center()
		var relative := Vector2(0,-minf(scroll.get_global_rect().size.y * 0.3,60.0 * root.get_visible_rect().size.y / root.size.y))
		touch(origin,true)
		for step: int in 3:
			drag(origin + relative * step,relative)
			await frame()
		touch(origin + relative * 3,false,true)
		await frame()
		check(scroll.scroll_vertical > 0, "A real finger swipe scrolls the stacked Bonzi shop")
		check(game.hud.control("CloseUpgradesButton").get_global_rect().is_equal_approx(done_rect), "Scrolling Bonzi keeps Done fixed in the header")
		check(game.hud.upgrades_open() and not game.brush_dragging and ledger.cash == before_cash and ledger.active_job_id == before_job, "Scrolling stays in the shop without painting or buying")
		for attempt: int in 10:
			if scroll.get_global_rect().encloses(button.get_global_rect()): break
			touch(origin,true)
			drag(origin,relative)
			touch(origin + relative,false,true)
			await frame()
		# ScrollContainer uses integer local offsets; allow its last fractional
		# pixel at the end of a density-scaled viewport.
		var pixel := root.get_visible_rect().size.y / root.size.y
		check(scroll.get_global_rect().grow(pixel).encloses(button.get_global_rect()), "Real swipes expose the whole Bonzi action inside the clipped shop %s (scroll=%s, button=%s, value=%d/%f)" % [root.size,scroll.get_global_rect(),button.get_global_rect(),scroll.scroll_vertical,overflow])

func layout_cases(label: String) -> void:
	var examples := [
		{"size":Vector2i(320,568),"insets":Vector4.ZERO},
		{"size":Vector2i(568,320),"insets":Vector4.ZERO},
		{"size":Vector2i(390,844),"insets":Vector4.ZERO},
		{"size":Vector2i(1080,2340),"insets":Vector4.ZERO},
		{"size":Vector2i(844,390),"insets":Vector4(44,0,34,20)},
	]
	for example: Dictionary in examples:
		root.content_scale_size = Vector2i(720,1000)
		root.size = example.size
		await frame()
		var ratio: Vector2 = root.get_visible_rect().size / Vector2(root.size)
		game.hud.preview_safe_insets = Vector4(example.insets.x * ratio.x,example.insets.y * ratio.y,example.insets.z * ratio.x,example.insets.w * ratio.y)
		game.hud._layout()
		game.frame_carpet()
		await open_shop()
		var safe: Rect2 = game.hud._safe_rect()
		var panel: Control = game.hud.control("UpgradesPanel")
		check(safe.grow(0.75).encloses(panel.get_global_rect()), label + ": the shop fits the safe display at " + str(example.size))
		var tools: Control = game.hud.control("Contents")
		var bonzi: Control = game.hud.control("BonziContents")
		check(bonzi.visible and game.hud.control("CurrentBonziPreview").texture != null and game.hud.control("NextBonziPreview").texture != null, label + ": authored Bonzi art is present beside the real tool offer")
		if game.hud._shop_stacked:
			check(bonzi.position.y >= tools.position.y + tools.size.y + 15.5, label + ": a narrow shop stacks Bonzi after the brush")
		else:
			check(bonzi.position.x >= tools.position.x + tools.size.x + 15.5 and is_equal_approx(bonzi.position.y,tools.position.y), label + ": a wide shop places Bonzi next to the brush")
		await scroll_to_bonzi()
		for name: String in ["ToolUpgradeButton","BonziUpgradeButton","CloseUpgradesButton"]:
			var button: Button = game.hud.control(name)
			await reveal(button)
			var rect := button.get_global_rect()
			check(safe.grow(0.75).encloses(rect) and panel.get_global_rect().grow(0.75).encloses(rect), label + ": " + name + " becomes fully reachable inside its shop")
			var physical: Vector2 = rect.size * Vector2(root.size) / root.get_visible_rect().size
			check(minf(physical.x,physical.y) >= 43.5, label + ": " + name + " keeps a 44px physical touch target")
			if not button.disabled: check(game.hud.visible_button_at(rect.get_center(),game.touch_buttons) == button, label + ": " + name + " owns its visible touch target")
		await reveal(game.hud.control("BonziUpgradeButton"))
		await capture("bonzi_%s_%dx%d" % [label,example.size.x,example.size.y])
		await tap(game.hud.control("CloseUpgradesButton"))
		check(not game.hud.upgrades_open() and not game.soil.simulation_suspended, label + ": Done closes the shop")
	game.hud.preview_safe_insets = Vector4.ZERO

func check_dismissal() -> void:
	root.size = Vector2i(390,844)
	await frame()
	game.hud._layout()
	var original_cash: float = ledger.cash
	var original_job: String = ledger.active_job_id
	var dirt: Dictionary = game.soil.make_snapshot()
	await open_shop()
	var outside: Vector2 = game.hud._safe_rect().end - Vector2(2,2)
	check(not game.hud.modal_contains_point(outside), "The dismissal fixture uses a point outside the panel")
	touch(outside,true)
	check(game.hud.upgrades_open() and not game.brush_dragging, "Outside touch down keeps the modal and locks the rug")
	touch(outside,false)
	check(not game.hud.upgrades_open() and not game.brush_dragging, "Outside touch release closes without starting a stroke")
	await open_shop()
	touch(outside,true)
	drag(outside,Vector2(-50,0))
	touch(outside + Vector2(-50,0),false)
	check(game.hud.upgrades_open(), "Dragging outside cancels dismissal")
	touch(outside,true)
	touch(outside + Vector2(-3,-3),true,false,1)
	touch(outside + Vector2(-3,-3),false,false,1)
	touch(outside,false)
	check(game.hud.upgrades_open(), "A second finger cancels dismissal")
	touch(outside,true)
	touch(outside,false,true)
	check(game.hud.upgrades_open(), "A canceled touch cannot close the modal")
	mouse(outside,true)
	var motion := InputEventMouseMotion.new()
	motion.position = outside + Vector2(-50,0)
	motion.relative = Vector2(-50,0)
	root.push_input(motion,true)
	mouse(outside + Vector2(-50,0),false)
	check(game.hud.upgrades_open(), "A mouse drag cancels dismissal")
	mouse(outside,true)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	mouse(outside,false)
	check(game.hud.upgrades_open(), "A stale mouse release after focus loss cannot dismiss the shop")
	mouse(outside,true)
	mouse(outside,false)
	check(not game.hud.upgrades_open() and not game.brush_dragging, "An outside mouse click closes without painting")
	check(ledger.cash == original_cash and ledger.active_job_id == original_job and game.soil.make_snapshot() == dirt, "Dismissal and canceled gestures preserve the wallet, job and dirt")
	game.open_room_upgrade("floor")
	await frame()
	touch(outside,true)
	touch(outside,false)
	check(not game.hud.upgrades_open() and not game.brush_dragging, "Existing room-offer outside dismissal still consumes the gesture")

func run() -> void:
	ledger = root.get_node("ShopState")
	ledger.set_process(false)
	ledger._test_ticks_msec = 0
	ledger._test_unix_time = 1800000000.0
	save_path = "res://.godot/bonzi_shop_%d.json" % OS.get_process_id()
	ledger._save_path = save_path
	check(ledger.reset_progress(), "The shop test uses a disposable ledger")
	ledger.cash = 10000.0
	ledger.save_state()
	folder = ProjectSettings.globalize_path("res://../art/renders/bonzi_shop")
	DirAccess.make_dir_recursive_absolute(folder)
	await enter()
	check((game.hud.control("BonziUpgradeButton") as Button).disabled and game.hud.control("BonziStatus").text.contains("0 / 3"), "The shop shows the existing three-carpet hiring gate")
	await layout_cases("locked")
	await check_dismissal()
	await leave()
	for _job: int in 3:
		check(not ledger.complete_and_start_next_job(ledger.start_job(),{"unique_clearance":1.0,"surface_clearance":1.0}).is_empty(), "Real paid rugs unlock Bonzi normally")
	ledger.cash = 99.0
	ledger.save_state()
	await enter()
	check((game.hud.control("BonziUpgradeButton") as Button).disabled and game.hud.control("BonziUpgradeButton").text == "Hire 160", "An unlocked unaffordable hire shows its actual revised price")
	ledger.cash = 10000.0
	ledger.save_state()
	ledger.changed.emit()
	await open_shop()
	var original_job: String = ledger.active_job_id
	var original_dirt: Dictionary = game.soil.make_snapshot()
	var before_tool_cash: float = ledger.cash
	var tool_price := float(ledger.progression_view().tool_cost)
	await tap(game.hud.control("ToolUpgradeButton"))
	check(ledger.cash == before_tool_cash - tool_price and int(ledger.progression_view().tool_level) == 1 and int(ledger.progression_view().bonzi_tier) == -1, "The existing brush action still purchases only its intended tool tier")
	game.hud.pending_reward = 1.0
	game.hud._refresh_availability()
	check((game.hud.control("BonziUpgradeButton") as Button).disabled, "Pending coins retain the existing purchase gate for Bonzi")
	game.hud.pending_reward = 0.0
	game.hud._refresh_availability()
	var before_failed: float = ledger.cash
	ledger._save_enabled = false
	await tap(game.hud.control("BonziUpgradeButton"))
	check(int(ledger.progression_view().bonzi_tier) == -1 and ledger.cash == before_failed and game.hud.control("BonziUpgradeButton").text == "Hire 160", "A failed durable save rolls back the hire and keeps the displayed offer")
	ledger._save_enabled = true
	for pair: Array in [[-1,160.0,120],[0,16000.0,90],[1,1600000.0,60]]:
		var tier := int(pair[0])
		ledger.cash = float(pair[1]) * 2.0
		check(ledger.save_state(), "Fund the isolated Bonzi purchase at its actual new milestone")
		ledger.changed.emit()
		var before: float = ledger.cash
		var button: Button = game.hud.control("BonziUpgradeButton")
		check(not button.disabled and button.text.ends_with(Money.format(float(pair[1]))), "The Bonzi offer shows its real incremental price")
		await tap(button)
		check(int(ledger.progression_view().bonzi_tier) == tier + 1 and ledger.cash == before - float(pair[1]), "A real hire/upgrade commits exactly one Bonzi tier and price")
		check(game.hud.control("CurrentBonziStats").text.contains("Every %ds" % int(pair[2])) and game.hud.control("CurrentBonziStats").text.contains(Money.format(ledger.progression_view().bonzi_reward)), "The current card refreshes its actual earnings and improved cycle")
	check((game.hud.control("BonziUpgradeButton") as Button).disabled and game.hud.control("BonziUpgradeButton").text == "Max" and not game.hud.control("NextBonziCard").visible, "Maximum Bonzi speed disables its purchase and hides the next offer")
	check(ledger.active_job_id == original_job and game.soil.make_snapshot() == original_dirt, "Bonzi purchases preserve the active carpet and cleaning masks")
	await tap(game.hud.control("CloseUpgradesButton"))
	await layout_cases("max")
	var saved_cash: float = ledger.cash
	await leave()
	ledger._load_state()
	check(ledger.cash == saved_cash and int(ledger.progression_view().bonzi_tier) == 2 and ledger.active_job_id == original_job, "Bonzi upgrades and current job persist through a durable reload")
	await enter()
	check(game.hud.control("CurrentBonziName").text == "Bonzi III" and game.hud.control("BonziUpgradeButton").text == "Max", "Re-entering the workshop presents the saved maximum Bonzi")
	await leave()
	var audio := root.get_node_or_null("GameAudio")
	if audio != null: audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if FileAccess.file_exists(save_path + ".tmp"): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + ".tmp"))
	print("BONZI_SHOP_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
