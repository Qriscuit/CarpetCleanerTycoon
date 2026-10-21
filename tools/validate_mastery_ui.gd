extends SceneTree
## Late-game real scene purchases, wall picking, completion and phone layouts.
## Requires -- --shop-test. Add --mastery-capture with a graphical renderer.

const Money := preload("res://scripts/money.gd")
const RoomRules := preload("res://scripts/room_upgrades.gd")
const Progression := preload("res://scripts/progression.gd")
const PHONE_SIZES := [Vector2i(320, 568), Vector2i(568, 320)]

var checks := 0
var failures := 0
var ledger: Node
var home: Control
var game: Node
var save_path := ""


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Mastery UI validation requires -- --shop-test to protect player progress.")
		quit(2)
		return
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MASTERY UI: " + message)


func settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func touch(point: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)


func tap(point: Vector2) -> void:
	touch(point, true)
	touch(point, false)


func capture(label: String) -> void:
	if "--mastery-capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../art/renders")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join("mastery_" + label + ".png")) == OK, "Save render: " + label)


func seed_late_game() -> void:
	ledger = root.get_node("ShopState")
	ledger.set_process(false)


	save_path = ProjectSettings.globalize_path("res://.godot/mastery_ui_test_%d.json" % OS.get_process_id())
	ledger._save_path = save_path
	check(ledger.reset_progress(), "Mastery fixtures use an isolated save")
	# The first workshop stays modest; AF belongs at the end of this section.
	ledger.room_upgrade_view("walls")
	var first_branch: Dictionary = ledger._branch().duplicate(true)
	for id: String in RoomRules.IDS: first_branch.room_upgrades[id] = Progression.room_level_cap(1)
	first_branch.payout_level = RoomRules.total_levels(first_branch.room_upgrades)
	check(RoomRules.early_reward(1, first_branch) * 2.0 == 400000.0, "All first-store accessories produce the exact 400,000 full-rug ceiling")
	check(not Money.format(RoomRules.early_reward(1, first_branch) * 2.0).contains("AF"), "The first workshop cannot reach AF through upgrades")
	for id in range(2, Progression.STORE_COUNT + 1):
		ledger.stores[str(id)] = Progression.new_branch(id)
		RoomRules.migrate_branch(id, ledger.stores[str(id)])
	ledger.active_store = Progression.STORE_COUNT
	ledger._load_active_branch()
	ledger.room_upgrade_view("walls")
	var branch: Dictionary = ledger._branch()
	var cap := Progression.room_level_cap(ledger.active_store)
	var levels := {"floor": cap - 1, "plants": cap, "window": cap, "railings": cap, "walls": cap - 2}
	branch.room_upgrades = levels
	branch.room_income_origins = {"floor": 0, "plants": 0, "window": 0, "railings": 0, "walls": 0}
	branch.room_base_early = 20.0 * Progression.scale_for(ledger.active_store)
	branch.room_rules_version = RoomRules.RULES_VERSION
	branch.payout_level = RoomRules.total_levels(levels)
	ledger.cash = float(ledger.room_upgrade_view("walls").cost) * 10.0
	check(ledger.save_state(), "A high-level five-object ladder saves without monetary integer casts")
	var offer: Dictionary = ledger.room_upgrade_view("walls")
	check(float(offer.cost) > 9.223372036854776e18 and float(offer.full_reward) >= 1e30, "The fixture uses real prices beyond int64 and AF-valued rugs")


func validate_home_walls() -> void:
	root.size = Vector2i(390, 844)
	home = load("res://scenes/production/floating_home.tscn").instantiate()
	home.animate_shop = false
	root.add_child(home)
	current_scene = home
	await settle()
	home.open_management("shop")
	await settle()
	var sheet: Control = home.management
	var button: Button = sheet.action_for("slot_5")
	check(sheet.actions.get("slot_5") == "room:walls" and sheet.rows["slot_5"].visible, "The actual fifth Home row targets its independent walls ladder")
	check(sheet.get_node("%SheetCash").text == Money.format(ledger.cash) and home.get_node("%Cash").text == Money.format(ledger.cash), "Both real Home wallet labels show the sixth-store balance")
	for size: Vector2i in PHONE_SIZES:
		root.size = size
		await settle()
		(sheet.get_node("%MenuScroll") as ScrollContainer).ensure_control_visible(button)
		await settle()
		var viewport := root.get_visible_rect()
		check(viewport.grow(0.5).encloses(sheet.get_node("%Sheet").get_global_rect()), "Home sheet fits the small phone at " + str(size))
		check(sheet.get_node("%MenuScroll").get_global_rect().grow(0.5).encloses(button.get_global_rect()), "The fifth Home purchase is reachable by scrolling at " + str(size))
		check(not button.disabled and button.text == Money.format(float(ledger.room_upgrade_view("walls").cost)), "The native wall row displays its affordable real late-game price at " + str(size))
		await capture("home_%dx%d" % [size.x, size.y])
	var before: Dictionary = ledger.room_upgrade_levels().duplicate(true)
	var offer: Dictionary = ledger.room_upgrade_view("walls")
	var cash_before: float = ledger.cash
	var point := button.get_global_rect().get_center()
	touch(point, true)
	check(ledger.cash == cash_before and ledger.room_upgrade_levels() == before, "Home wall purchase waits for touch release")
	touch(point, false, true)
	check(ledger.cash == cash_before and ledger.room_upgrade_levels() == before, "Canceled fifth-row touch cannot spend AF money")
	tap(point)
	await settle()
	var expected_level := Progression.room_level_cap(ledger.active_store) - 1
	check(ledger.cash == cash_before - float(offer.cost) and int(ledger.room_upgrade_levels().walls) == expected_level, "A real fifth-row touch buys exactly one late-game wall level")
	for id: String in ["floor", "plants", "window", "railings"]:
		check(int(ledger.room_upgrade_levels()[id]) == int(before[id]), "Home walls purchase leaves the " + id + " ladder unchanged")
	check(sheet.rows["slot_5"].get_node("Row/Words/Title").text == "Walls · Lv %d" % expected_level, "The fifth row refreshes to its newly saved level")
	home.free()
	home = null
	current_scene = null


func wall_screen_point() -> Vector2:
	# Prefer an authored wall anchor. A scan also catches camera-fit regressions
	# without manufacturing an offer through open_room_upgrade().
	var viewport := root.get_visible_rect()
	for local: Vector3 in [Vector3(2.37, 0.85, -0.16), Vector3(2.37, 0.85, -2.05), Vector3(-2.225, 0.85, -2.86), Vector3(2.225, 0.85, -2.86), Vector3(0, 1.58, -2.86)]:
		var point: Vector2 = game.camera.unproject_position(game.room.to_global(local))
		if viewport.has_point(point) and game.room.pick_upgrade(game.camera, point) == "walls":
			return point
	for y in range(8, int(viewport.size.y) - 8, 8):
		for x in range(8, int(viewport.size.x) - 8, 8):
			var point := viewport.position + Vector2(x, y)
			if game.room.pick_upgrade(game.camera, point) == "walls":
				return point
	return Vector2.INF


func assert_offer_layout(description: String) -> void:
	var panel: Control = game.hud.room_panel
	var safe: Rect2 = game.hud._safe_rect().grow(0.5)
	check(safe.encloses(panel.get_node("%Card").get_global_rect()), description + ": floating wall card fits the safe display")
	for button: Button in panel.action_buttons():
		check(safe.encloses(button.get_global_rect()), description + ": the floating action is reachable")
		var physical_size: Vector2 = button.get_global_rect().size * Vector2(root.size) / root.get_visible_rect().size
		check(minf(physical_size.x, physical_size.y) >= 43.5, description + ": action retains a 44-pixel finger target")


func validate_cleaning_walls() -> void:
	root.size = Vector2i(390, 844)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	for _tick in 100:
		if game.rug_phase == game.RugPhase.CLEANING:
			break
		await create_timer(0.025).timeout
	check(game.paid_contract and game.rug_phase == game.RugPhase.CLEANING, "The production scene enters its real paid cleaning phase")
	var rug_before: Dictionary = game.soil.make_snapshot()
	for size: Vector2i in PHONE_SIZES:
		root.size = size
		await settle()
		game.frame_carpet()
		var point := wall_screen_point()
		check(point.is_finite(), "A visible wall is tappable in the small phone at " + str(size))
		if not point.is_finite():
			continue
		tap(point)
		await settle()
		check(game.hud.room_panel.visible and game.hud.room_panel.selected_id == "walls", "A real wall touch opens its own offer at " + str(size))
		check(not game.brush_dragging and game.soil.simulation_suspended, "The wall offer safely pauses rug input at " + str(size))
		assert_offer_layout("Walls " + str(size))
		var offer: Dictionary = ledger.room_upgrade_view("walls")
		check(game.hud.room_panel.get_node("%CleanValue").text == "%s → %s" % [Money.format(float(offer.full_reward)), Money.format(float(offer.next_full))], "The actual wall offer previews the real AF full-rug increase")
		check(game.hud.room_panel.get_node("%Buy").text.contains(Money.format(float(offer.cost))), "The wall offer shows its independent AF price")
		await capture("walls_%dx%d" % [size.x, size.y])
		tap(game.hud.room_panel.get_node("%Close").get_global_rect().get_center())
		await settle()
	check(game.soil.make_snapshot() == rug_before, "Opening and closing real wall offers leaves the paid carpet untouched")
	var point := wall_screen_point()
	if not point.is_finite():
		return
	tap(point)
	await settle()
	var offer: Dictionary = ledger.room_upgrade_view("walls")
	var cash_before: float = ledger.cash
	tap(game.hud.room_panel.get_node("%Buy").get_global_rect().get_center())
	await settle()
	var cap := Progression.room_level_cap(ledger.active_store)
	check(ledger.cash == cash_before - float(offer.cost) and int(ledger.room_upgrade_levels().walls) == cap, "A real floating purchase saves the final wall level and spends one AF price")
	check(game.room.is_upgrade_active("walls") and game.hud.room_panel.get_node("%Buy").disabled, "The final wall purchase animates its object while its store cap prevents further purchases")
	await create_timer(1.0).timeout
	check(int(game.room.levels.walls) == cap and game.hud.room_panel.get_node("%Buy").text == "Fully upgraded", "The final upgrade finishes and exposes the true ladder cap")
	check(game.soil.make_snapshot() == rug_before, "The wall purchase leaves the rug identity and genuine dirt unchanged")
	tap(game.hud.room_panel.get_node("%Close").get_global_rect().get_center())
	await settle()


func validate_af_completion() -> void:
	var job: String = game.contract_job_id
	var cash_before: float = ledger.cash
	var jobs_before: int = ledger.manual_jobs
	var quote: float = ledger.current_job_full_reward()
	check(quote >= 1e30 and Money.format(quote).contains("AF"), "The real active paid rug has an AF full-clean reward")
	# Accelerate contact time across real strips. This cleans both source clumps
	# and the saved mask, then uses the ordinary finish transaction and vacuum.
	for _repeat in 12:
		for lane in 24:
			var z := lerpf(-1.8, 1.8, float(lane) / 23.0)
			var start: Vector3 = game.soil.rug_node.to_global(Vector3(-1.3, game.soil.RUG_Y, z))
			var finish: Vector3 = game.soil.rug_node.to_global(Vector3(1.3, game.soil.RUG_Y, z))
			game.soil.end_pass()
			game.apply_selected_tool_stroke(start, finish, 0.1)
			for tick in 45: game.soil._physics_process(0.05)
	game.soil._process(0.0)
	game.update_contract_status()
	game.finish_rug()
	await settle()
	check(game.contract_finished and ledger.cash == cash_before + quote and ledger.manual_jobs == jobs_before + 1, "The genuine completed rug pays its AF reward exactly once")
	if not ledger.completed_rewards.has(job): return
	check(float(ledger.completed_rewards[job].amount) == quote and game.hud.pending_reward == 0.0 and game.hud._reserved_reward == 0.0, "AF history records the entire carpet quote and consumes the count-up reservation")
	check(game.hud.displayed_gold >= cash_before - absf(cash_before) * 1e-12 and game.hud.displayed_gold <= ledger.cash + absf(ledger.cash) * 1e-12 and game.hud.active_coin_count() == 0, "The prompt AF count-up stays within the committed wallet and does not launch delayed reward flights")
	game.finish_rug()
	check(ledger.cash == cash_before + quote and ledger.manual_jobs == jobs_before + 1, "Repeated AF completion cannot pay the same rug twice")
	for _tick in 40:
		if game.soil.vacuum_complete:
			break
		game.soil._physics_process(0.05)
		game.soil._process(0.05)
	await settle()
	check(game.rug_phase == game.RugPhase.REVEAL and game.completion_reveal.active, "The actual completed rug opens its appreciation reveal")
	game.completion_reveal.set_process(false)
	check(game.completed_reward == 0.0 and float(ledger.completed_rewards[job].amount) == quote and game.completion_reveal.get_node("%CompareButton").text == "Compare" and game.completion_reveal.get_node_or_null("%Detail") == null, "The AF total remains in durable history while Compare carries no second payout")
	for size: Vector2i in PHONE_SIZES:
		root.size = size
		await settle()
		var safe: Rect2 = game.completion_reveal._safe_rect().grow(0.5)
		check(safe.encloses(game.completion_reveal.get_node("%Actions").get_global_rect()), "Completion actions remain reachable at " + str(size))
		await capture("completion_%dx%d" % [size.x, size.y])
	# Skip presentation time only after testing the genuine reveal. The next rug
	# reuses the production scene without awarding the finished carpet again.
	game.hud._process(0.25)
	check(game.hud.pending_reward == 0.0 and game.hud._reserved_reward == 0.0 and game.hud._cleaning_pending == 0.0 and game.hud.displayed_gold == ledger.cash, "The prompt AF count-up settles exactly before the next carpet")
	game.animate_rug_changes = false
	game.next_rug()
	await settle()
	check(game.rug_phase == game.RugPhase.CLEANING and game.contract_job_id != job and ledger.cash == cash_before + quote and ledger.manual_jobs == jobs_before + 1, "AF completion advances to a new dirty rug without duplicating earned money")
	game.open_room_upgrade("floor")
	await settle()
	check(game._can_purchase() and not game.hud.room_panel.get_node("%Buy").disabled, "The already-earned AF wallet supports its affordable floor offer immediately")
	check(game.hud._coin_nodes.size() == 24 and game.hud.active_coin_count() == 0, "Progressive and final AF count-ups preserve the fixed cosmetic coin pool")
	await capture("coins_collected")


func run() -> void:
	seed_late_game()
	await validate_home_walls()
	await validate_cleaning_walls()
	if is_instance_valid(game) and game.rug_phase == game.RugPhase.CLEANING and not game.hud.upgrades_open():
		await validate_af_completion()
	else:
		check(false, "Cleaning fixture must be ready before AF completion validation")
	if is_instance_valid(game):
		game.free()
	current_scene = null
	var audio := root.get_node_or_null("GameAudio")
	if audio != null:
		audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	DirAccess.remove_absolute(save_path)
	print("MASTERY_UI_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
