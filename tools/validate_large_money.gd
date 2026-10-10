extends SceneTree
## Money formatting and real UI paths across ordinary coins through AF and beyond.
## Run with the pinned toolchain and -- --shop-test. No real save is touched.
const Money := preload("res://scripts/money.gd")
const Progression := preload("res://scripts/progression.gd")

var checks := 0
var failures := 0
var ledger: Node
var home: Control
var hud: CanvasLayer
var save_path := ""


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Large money validation requires -- --shop-test.")
		quit(2)
		return
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("LARGE MONEY: " + message)


func settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func check_formatter() -> void:
	for pair: Array in [[0.0, "0"], [1.0, "1"], [40.0, "40"], [999.0, "999"], [1000.0, "1K"], [1250.0, "1.3K"], [999949.0, "999.9K"], [999950.0, "1M"], [1234567.0, "1.2M"], [1e30, "1AF"], [1.25e30, "1.3AF"], [9.9995e29, "1AF"], [1e60, "1AP"], [-1.0, "-1"]]:
		check(Money.format(float(pair[0])) == str(pair[1]), "Compact formatter matches " + str(pair[1]))
	var suffixes := ["K", "M", "B", "T", "AA", "AB", "AC", "AD", "AE", "AF", "AG", "AH", "AI", "AJ", "AK", "AL", "AM", "AN", "AO", "AP"]
	for index in suffixes.size():
		var value := pow(1000.0, float(index + 1))
		check(Money.format(value) == "1" + str(suffixes[index]), "Every thousand-group boundary has the expected suffix " + str(suffixes[index]))
	check(Money.format(1250.0, 0) == "1K" and Money.format(1250.0, 2) == "1.25K", "Requested decimal precision applies to compact groups")
	check(Money.format(40.0, 2) == "40", "Ordinary whole coins do not acquire decimal padding")
	check(Money.rounded(25.6) == 26.0 and Money.rounded(25.4) == 25.0 and Money.rounded(-1.0) == -1.0, "Currency rounding retains whole ordinary coins and negative progression sentinels")
	check(Money.rounded(1e30) == 1e30 and Money.rounded(1e60) == 1e60, "Large bounded currency rounds without integer conversion")
	check(is_nan(Money.rounded(INF)) and is_nan(Money.rounded(NAN)) and is_nan(Money.rounded(1e61)), "Invalid or out-of-range rounding cannot manufacture money")
	check(Money.is_valid(40) and Money.is_valid(40.0) and Money.is_valid(1e30) and Money.is_valid(1e60), "Integer saves and bounded float currency both validate")
	check(not Money.is_valid(-1.0) and not Money.is_valid(INF) and not Money.is_valid(NAN) and not Money.is_valid(1e61) and not Money.is_valid("40") and not Money.is_valid(true), "Money validation rejects negative, non-finite, excessive and nonnumeric values")
	check(Money.is_valid(-1.0, -1.0) and not Money.is_valid(0.0, 1.0), "Explicit currency minima support progression sentinels")
	var decoded: Variant = JSON.parse_string(JSON.stringify({"cash": 1.23456789012345e30}))
	check(decoded is Dictionary and absf(float(decoded.cash) / 1.23456789012345e30 - 1.0) < 1e-14, "A large float survives JSON round trip at the available precision")


func check_home_ui() -> void:
	ledger = root.get_node("ShopState")
	ledger.set_process(false)
	ledger._test_ticks_msec = 0
	ledger._test_unix_time = 1800000000.0
	save_path = ProjectSettings.globalize_path("res://.godot/large_money_test_%d.json" % OS.get_process_id())
	ledger._save_path = save_path
	check(ledger.reset_progress(), "Large-wallet fixtures use an isolated save")
	for index in 3:
		var job: String = ledger.start_job()
		check(not ledger.complete_and_start_next_job(job, {"unique_clearance": 1.0, "surface_clearance": 1.0}).is_empty(), "Complete onboarding fixture rug %d through the ledger" % (index + 1))
	ledger.cash = 1e30
	check(ledger.save_state(), "AF wallet saves without int64 truncation")
	root.size = Vector2i(390, 844)
	home = load("res://scenes/production/floating_home.tscn").instantiate()
	root.add_child(home)
	current_scene = home
	await settle()
	check(home.get_node("%Cash").text == "1AF", "The real home wallet renders an AF balance")
	var nav := home.get_node("%NavBonzi") as Button
	var caption := nav.get_node("CaptionContent/Caption") as Label
	check(caption.text == "Hire Bonzi" and nav.tooltip_text.contains(Money.format(Progression.bot_cost(1, -1))) and nav.tooltip_text.contains("while away"), "Three local rugs reveal the nonblocking Bonzi hint with its actual revised hire price")
	check(not ledger.owns("bonzi") and ledger.cash == 1e30 and not home.get_node("%Management").visible, "The hiring hint neither buys Bonzi nor opens a modal")
	home.open_management("shop")
	var menu: Control = home.management
	await settle()
	var visible_rows := 0
	for row: Control in menu.rows.values():
		if row.visible:
			visible_rows += 1
	check(visible_rows == 5 and menu.actions.values().has("room:walls"), "Home shop presents all five independent accessory rows")
	var walls_button: Button = menu.action_for("intake")
	check(menu.rows["intake"].get_node("Row/Words/Title").text.begins_with("Walls"), "The fifth authored row presents the wall upgrade")
	for size: Vector2i in [Vector2i(390, 844), Vector2i(844, 390)]:
		root.size = size
		await settle()
		(menu.get_node("%MenuScroll") as ScrollContainer).ensure_control_visible(walls_button)
		await settle()
		check(menu.get_node("%MenuScroll").get_global_rect().grow(0.5).encloses(walls_button.get_global_rect()), "The fifth upgrade remains reachable by scrolling at " + str(size))
	check(menu.get_node("%SheetCash").text == "1AF", "The real compact sheet uses the shared AF formatter")
	home.close_management()
	check(ledger.buy_bonzi_upgrade(), "The normal Bonzi hire transaction still works with an AF wallet")
	check(caption.text == "Bonzi", "Hiring Bonzi restores its ordinary navigation caption")
	ledger._sync_active_branch()
	ledger.stores["2"] = Progression.new_branch(2)
	check(ledger.select_store(2), "Owned later-store fixture selects normally")
	check(caption.text == "Bonzi", "Later stores retain the ordinary Bonzi navigation caption")
	home.free()
	home = null
	current_scene = null


func settle_coins() -> void:
	for _step in 100:
		if hud.pending_reward == 0.0 and hud.active_coin_count() == 0:
			return
		hud._process(0.05)
	check(false, "Cosmetic reward flights settle within five simulated seconds")


func check_cleaning_ui() -> void:
	root.size = Vector2i(648, 900)
	hud = load("res://scenes/ui/cleaning_hud.tscn").instantiate()
	root.add_child(hud)
	await settle()
	hud.set_progression({"store_id": 6, "full_reward": Progression.reward_cap(6), "tool_cost": 1e29, "can_upgrade_tool": true}, true)
	hud.initialize_wallet(1e30)
	check(hud.control("WalletValue").text == "1AF", "Cleaning wallet supports AF currency")
	check(hud.control("CarpetEarningsValue").text == "400AF" and hud.control("EarningsPerCarpet").visible, "The carpet earnings label formats the sixth store's true400AF cap")
	check(hud.control("WalletValue").get_theme_font_size("font_size") >= 32, "The enlarged wallet keeps its readable font for AF balances")
	check((hud.control("UpgradeButton") as Button).icon.resource_path == "res://assets/ui/room_upgrades/cart.svg", "Large-value tool offers retain the authored shopping-cart action icon")
	var arrivals: Array[float] = []
	hud.coin_arrived.connect(func(value: float) -> void: arrivals.append(value))
	hud.reserve_reward(1e30)
	hud.show_reward(1e30, 2e30)
	check(hud.pending_reward == 1e30 and hud.displayed_gold == 1e30 and hud.active_coin_count() == 16, "AF reward uses the existing bounded sixteen-coin burst")
	check((hud.control("ToolUpgradeButton") as Button).disabled, "Pending AF coin arrivals temporarily disable purchases")
	settle_coins()
	var arrived := 0.0
	for value in arrivals:
		arrived += value
	check(absf(arrived / 1e30 - 1.0) < 1e-12, "Large cosmetic coin values preserve their reward at float precision")
	check(hud.pending_reward == 0.0 and hud._reserved_reward == 0.0 and hud.displayed_gold == 2e30 and hud.control("WalletValue").text == "2AF", "Completed AF flights clear pending residue and reveal the durable wallet")
	check(hud.control("CarpetEarningsValue").text == "400AF", "Cosmetic wallet count-up cannot change the store's per-carpet earnings")
	check(not (hud.control("ToolUpgradeButton") as Button).disabled, "Completed AF flights unlock an affordable high-value purchase")
	check(hud._coin_nodes.size() == 24 and hud.active_coin_count() == 0, "Large rewards retain the fixed cosmetic coin pool")
	hud.reserve_reward(1e30)
	hud.cancel_reserved_reward(1e30)
	check(hud.pending_reward == 0.0 and hud.displayed_gold == 2e30, "Failed large-reward reservations cancel cleanly")
	arrivals.clear()
	hud.initialize_wallet(100.0)
	hud.reserve_reward(43.0)
	hud.show_reward(43.0, 143.0)
	settle_coins()
	arrived = 0.0
	for value in arrivals:
		arrived += value
	check(arrived == 43.0 and hud.displayed_gold == 143.0 and hud.pending_reward == 0.0, "Ordinary cosmetic coin values remain exact whole coins")
	var offer := {"id": "walls", "title": "Workshop walls", "level": 10, "next_level": 11, "cost": 1e30, "full_reward": 1e30, "next_full": 1.2e30, "wallet_before": 5e30, "can_upgrade": true, "visual_step": 5, "milestone_progress": 0.0}
	hud.room_panel.show_offer(offer, true)
	await settle()
	check(hud.room_panel.get_node("%Title").text == "Walls" and hud.room_panel.get_node("%Icon").texture != null, "Floating wall offer has its own title and vector icon")
	check(hud.room_panel.get_node("%CleanValue").text == "1AF → 1.2AF" and hud.room_panel.get_node("%Buy").text.contains("1AF") and not hud.room_panel.get_node("%Buy").disabled, "Floating offers retain high-value earnings and prices without int64 coercion")
	hud.free()
	hud = null
	var reveal: CanvasLayer = load("res://scenes/ui/completion_reveal.tscn").instantiate()
	root.add_child(reveal)
	reveal.show_reveal(true, 1.0, false, 1e30)
	check(reveal.active and reveal.remaining > 0.0 and reveal.get_node_or_null("%Detail") == null, "AF rewards retain automatic completion without a redundant payout label")
	var advances := []
	reveal.continued.connect(func(): advances.append(true))
	reveal._process(3.0)
	reveal._process(3.0)
	check(not reveal.active and advances.size() == 1, "An AF completion without comparison advances automatically exactly once")
	reveal.free()


func run() -> void:
	check_formatter()
	await check_home_ui()
	await check_cleaning_ui()
	var audio := root.get_node_or_null("GameAudio")
	if audio != null:
		audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	if not save_path.is_empty():
		DirAccess.remove_absolute(save_path)
	print("LARGE_MONEY_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
