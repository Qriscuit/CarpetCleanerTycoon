extends SceneTree
## Real room purchases, carpet payments and phone geometry use a disposable save.
const Rules := preload("res://scripts/progression.gd")
const Room := preload("res://scripts/room_upgrades.gd")
const Money := preload("res://scripts/money.gd")
const CART_PATH := "res://assets/ui/room_upgrades/cart.svg"
var checks := 0
var failures := 0
var ledger: Node
var game: Node
var save_path := ""
var cart_id := 0

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		printerr("Carpet earnings HUD validation requires -- --shop-test.")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		printerr("Carpet earnings HUD validation needs a real renderer.")
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CARPET EARNINGS HUD: " + message)

func frames() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func tap(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = button.get_global_rect().get_center()
		event.pressed = pressed
		root.push_input(event, true)

func enter(scene_path: String = "res://scenes/production/rug_cleaning.tscn") -> void:
	game = load(scene_path).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frames()

func leave() -> void:
	game.free()
	game = null
	current_scene = null
	await process_frame

func readout() -> String:
	return (game.hud.control("CarpetEarningsValue") as Label).text

func check_earnings(amount: float, message: String) -> void:
	check(game.hud.control("EarningsPerCarpet").visible and readout() == Money.format(amount), message)

func check_cart(message: String) -> void:
	var icon: Texture2D = (game.hud.control("UpgradeButton") as Button).icon
	check(icon != null and icon.resource_path == CART_PATH and icon.get_instance_id() == cart_id, message)

func rug_bounds() -> Rect2:
	var bounds := Rect2(game.camera.unproject_position(Vector3(-1.06, game.CARPET_PLANE_Y, -1.72)), Vector2.ZERO)
	for x: float in [-1.06, 1.06]:
		for z: float in [-1.72, 1.72]:
			bounds = bounds.expand(game.camera.unproject_position(Vector3(x, game.CARPET_PLANE_Y, z)))
	return bounds

func check_phone_geometry(label: String) -> void:
	var cases := [
		{"size":Vector2i(320,568), "insets":Vector4.ZERO},
		{"size":Vector2i(568,320), "insets":Vector4.ZERO},
		{"size":Vector2i(390,844), "insets":Vector4.ZERO},
		{"size":Vector2i(844,390), "insets":Vector4.ZERO},
		{"size":Vector2i(390,844), "insets":Vector4(0,44,0,34)},
		{"size":Vector2i(844,390), "insets":Vector4(44,0,34,20)},
	]
	for example: Dictionary in cases:
		root.content_scale_size = example.size
		root.size = example.size
		game.hud.preview_safe_insets = example.insets
		await frames()
		game.hud._layout()
		game.frame_carpet()
		game.finish_button.hide()
		var camera_transform: Transform3D = game.camera.global_transform
		var camera_size: float = game.camera.size
		game.finish_button.show()
		game.frame_carpet()
		check(game.camera.global_transform.is_equal_approx(camera_transform) and is_equal_approx(game.camera.size,camera_size), "Finish visibility cannot move the carpet camera at " + label + str(example.size))
		var safe: Rect2 = game.hud._safe_rect()
		var rug := rug_bounds()
		for name: String in ["HomeButton","CleaningProgress","EarningsPerCarpet","Wallet","UpgradeButton","FinishJobButton"]:
			var control: Control = game.hud.control(name)
			check(safe.grow(0.5).encloses(control.get_global_rect()), name + " stays inside safe edges at " + label + str(example.size))
			var clear := not control.get_global_rect().grow(4.0).intersects(rug)
			check(clear, name + " leaves a clear margin around the rug and fringe at " + label + str(example.size))
			if not clear: print("HUD_GEOMETRY %s %s %s control=%s rug=%s" % [label,str(example.size),name,str(control.get_global_rect()),str(rug)])
		var progress: Rect2 = game.hud.control("CleaningProgress").get_global_rect()
		var earnings: Rect2 = game.hud.control("EarningsPerCarpet").get_global_rect()
		var gap: float = game.hud.earnings_gap * game.hud.get_node("HUD").scale.y
		check(earnings.position.y >= progress.end.y + gap - 0.5 and earnings.position.y <= progress.end.y + gap + 0.5, "The carpet earnings plaque follows its authored gap below the progress bar")
		check(not earnings.grow(3.0).intersects(game.hud.control("Wallet").get_global_rect()) and not progress.grow(3.0).intersects(game.hud.control("Wallet").get_global_rect()), "The larger wallet stays clear of both progress and carpet earnings")
		check(not game.hud.control("HomeButton").get_global_rect().grow(4.0).intersects(game.hud.control("Wallet").get_global_rect()), "The enlarged wallet leaves space around the Home button")
		var block: Rect2 = game.hud.progress_block_rect()
		check(block.grow(0.5).encloses(progress) and block.grow(0.5).encloses(earnings), "The camera's progress reservation includes the new earnings plaque")
		var wallet_value := game.hud.control("WalletValue") as Label
		check(wallet_value.get_theme_font_size("font_size") >= 32 and wallet_value.size.x + 0.5 >= wallet_value.get_minimum_size().x and wallet_value.size.y + 0.5 >= wallet_value.get_minimum_size().y, "The enlarged wallet text fits its authored label without clipping")
		var earnings_value := game.hud.control("CarpetEarningsValue") as Label
		check(earnings_value.size.x + 0.5 >= earnings_value.get_minimum_size().x, "The per-carpet amount fits without clipping at " + label + str(example.size))
		game.finish_button.hide()
		if "--earnings-capture" in OS.get_cmdline_user_args():
			await frames()
			var folder := ProjectSettings.globalize_path("res://../art/renders")
			DirAccess.make_dir_recursive_absolute(folder)
			check(root.get_texture().get_image().save_png(folder.path_join("carpet_earnings_%s_%dx%d.png" % [label,example.size.x,example.size.y])) == OK, "The requested HUD preview saves")
	game.hud.preview_safe_insets = Vector4.ZERO

func complete_paid_rug(amount: float) -> void:
	var full: float = ledger.progression_view().full_reward
	var reward := full if amount >= 0.99 else full / 2.0
	var job: String = ledger.active_job_id
	var before_cash: float = ledger.cash
	var scene_id: int = game.get_instance_id()
	var pool_id: int = game.soil.batch.get_instance_id()
	game.soil.remaining = floori(game.soil.initial.size() * (1.0 - amount) + 0.00001)
	game.soil.surface_coverage_total = game.soil.surface_pixel_count * (1.0 - amount)
	game.update_contract_status()
	check_earnings(full, "Partial or full cleanliness retains the full per-carpet rate")
	if amount < 0.99: tap(game.finish_button)
	await frames()
	check(ledger.active_job_id != job and is_equal_approx(ledger.cash,before_cash + reward), "A real cleaning completion credits its early/full tier once")
	check(float(ledger.completed_rewards[job].amount) == reward, "The durable job reward matches the quoted completion tier")
	check_earnings(full, "The per-carpet label retains the full rate during a completed rug's payment")
	for _tick in 150:
		if game.soil.vacuum_complete: break
		game.soil._physics_process(1.0 / 60.0)
	await frames()
	for _tick in 110:
		if game.hud.pending_reward == 0.0 and game.hud.active_coin_count() == 0: break
		game.hud._process(0.05)
	await frames()
	check(game.hud.pending_reward == 0.0 and game.hud.displayed_gold == ledger.cash and game.hud.control("WalletValue").text == Money.format(ledger.cash), "Cosmetic coin collection settles to the durable wallet without float residue")
	check(game.get_instance_id() == scene_id and game.soil.batch.get_instance_id() == pool_id, "The earnings readout and rug replacement retain the same game and dirt pool")
	check_earnings(full, "The next rug keeps the store's per-carpet earnings")

func seed_last_wall_purchase(store_id: int) -> void:
	for id in range(2,store_id + 1):
		if not ledger.stores.has(str(id)): ledger.stores[str(id)] = Rules.new_branch(id)
	check(ledger.select_store(store_id), "The isolated authored-store fixture selects normally")
	ledger.room_upgrade_view("walls")
	var branch: Dictionary = ledger._branch()
	var cap := Rules.room_level_cap(store_id)
	for id: String in Room.IDS: branch.room_upgrades[id] = cap
	branch.room_upgrades.walls = cap - 1
	branch.payout_level = Room.total_levels(branch.room_upgrades)
	branch.job_early_reward = Room.early_reward(store_id,branch)
	ledger.cash = float(ledger.room_upgrade_view("walls").cost) * 3.0
	check(ledger.save_state(), "The last-accessory fixture persists bounded real levels, prices and earnings")

func buy_last_wall(store_id: int) -> void:
	await enter()
	var quote: Dictionary = ledger.room_upgrade_view("walls")
	check_earnings(float(quote.full_reward), "Entering shows the saved current room value before its last purchase")
	game.open_room_upgrade("walls")
	await frames()
	var before_cash: float = ledger.cash
	var job: String = ledger.active_job_id
	var dirt: Dictionary = game.soil.make_snapshot()
	tap(game.hud.room_panel.get_node("%Buy"))
	check(ledger.room_upgrade_levels().walls == Rules.room_level_cap(store_id) and is_equal_approx(ledger.cash,before_cash-float(quote.cost)), "A real wall-panel touch buys exactly the last accessory level at its stated price")
	check_earnings(Rules.reward_cap(store_id), "The existing HUD updates to the exact store cap immediately on purchase release")
	check(ledger.active_job_id == job and game.soil.make_snapshot() == dirt, "Updating the carpet earnings leaves the active rug and dirt untouched")
	check_cart("Accessory upgrades retain the authored shopping-cart icon")
	game.hud.close_upgrades()
	await frames()
	await check_phone_geometry("cap%d" % store_id)
	await leave()
	ledger._load_state()
	await enter()
	check_earnings(Rules.reward_cap(store_id), "The mastered per-carpet amount survives disk reload and workshop reentry")
	await leave()

func run() -> void:
	ledger = root.get_node("ShopState")
	ledger.set_process(false)


	save_path = "res://.godot/carpet_earnings_hud_%d.json" % OS.get_process_id()
	ledger._save_path = save_path
	check(ledger.reset_progress(), "The HUD test begins in a disposable save")
	ledger.cash = 1000.0
	check(ledger.save_state(), "Modest starter funds save")
	root.content_scale_size = Vector2i(390,844)
	root.size = Vector2i(390,844)
	await enter()
	check_earnings(40.0, "A starter carpet clearly shows its full40-coin reward beneath progress")
	var icon: Texture2D = (game.hud.control("UpgradeButton") as Button).icon
	check(icon != null and icon.resource_path == CART_PATH, "The shopping action uses the new authored accessory-style SVG")
	if icon != null: cart_id = icon.get_instance_id()
	check(game.hud.control("CarpetEarningsIcon").texture != null and game.hud.control("CarpetEarningsIcon").texture.resource_path.ends_with(".svg"), "The per-carpet readout uses an authored vector carpet icon")
	game.open_room_upgrade("floor")
	await frames()
	var job: String = ledger.active_job_id
	var dirt: Dictionary = game.soil.make_snapshot()
	tap(game.hud.room_panel.get_node("%Buy"))
	check_earnings(46.0, "The actual first floor purchase refreshes earnings immediately on touch release")
	check(ledger.cash == 960.0 and ledger.active_job_id == job and game.soil.make_snapshot() == dirt, "The visible upgrade spends40 once and preserves the current carpet")
	game.hud.close_upgrades()
	ledger.cash = 5000.0
	check(ledger.save_state(), "A tool-only test budget saves")
	tap(game.hud.control("UpgradeButton"))
	await frames()
	for _tier in 4:
		tap(game.hud.control("ToolUpgradeButton"))
		check_cart("Each real brush purchase preserves the shopping-cart action icon")
		check_earnings(46.0, "Brush improvements retain the room's per-carpet earnings")
	game.hud.close_upgrades()
	await check_phone_geometry("starter")
	await complete_paid_rug(0.75)
	await complete_paid_rug(1.0)
	check(game.save_contract_progress(), "The next playable rug saves before reentry")
	await leave()
	ledger._load_state()
	await enter()
	check_earnings(46.0, "Ordinary earned room income survives reload and reenter without reset")
	await leave()
	seed_last_wall_purchase(1)
	await buy_last_wall(1)
	seed_last_wall_purchase(6)
	await buy_last_wall(6)
	ledger.cash = 9.999e32
	check(ledger.save_state(), "A long999.9AF wallet fixture saves at available float precision")
	await enter()
	check(game.hud.control("WalletValue").text == "999.9AF", "The longest ordinary compact AF label keeps the larger readable type")
	check_earnings(Rules.reward_cap(6), "A larger accumulated wallet cannot change per-carpet income")
	await check_phone_geometry("long_wallet")
	await leave()
	var saved_cash: float = ledger.cash
	var saved_jobs: int = ledger.manual_jobs
	await enter("res://scenes/test/rug_cleaning_gym.tscn")
	check(not game.paid_contract and not game.hud.control("EarningsPerCarpet").visible, "Free Gym practice never advertises paid per-carpet income")
	check(ledger.cash == saved_cash and ledger.manual_jobs == saved_jobs, "Opening free practice cannot alter the real isolated store ledger")
	await leave()
	var audio := root.get_node_or_null("GameAudio")
	if audio != null: audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if FileAccess.file_exists(save_path + ".tmp"): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + ".tmp"))
	print("CARPET_EARNINGS_HUD_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
