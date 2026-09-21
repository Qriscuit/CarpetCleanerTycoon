extends SceneTree
## Actual ledger payouts, per-coin display increments and modal input isolation.
var failures := 0
var checks := 0
var game: Node
var state: Node
var arrivals: Array[int] = []
var last_display := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func frame() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func capture(label: String) -> void:
	await frame()
	root.get_texture().get_image().save_png("res://../art/renders/coins_"+label+".png")

func tap(button: Button) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = button.get_global_rect().get_center()
		event.pressed = pressed
		root.push_input(event,true)

func on_coin(value: int) -> void:
	arrivals.append(value)
	check(game.hud.displayed_gold == last_display+value,"Each coin adds exactly its own value to the displayed gold")
	last_display = game.hud.displayed_gold

func finish(amount: float) -> void:
	# A discrete pool cannot represent every percentage; clear at least the target.
	game.soil.remaining = floori(float(game.soil.initial.size())*(1.0-amount)+0.0001)
	game.soil.surface_coverage_total = float(game.soil.surface_pixel_count)*(1.0-amount)
	game.update_contract_status()
	if amount < 0.99: tap(game.finish_button)
	await process_frame

func finish_suction() -> void:
	for tick in 120:
		if game.soil.vacuum_complete: break
		game.soil._physics_process(1.0/60.0)
	await frame()

func settle_coins() -> void:
	for tick in 250:
		if game.hud.pending_reward == 0: return
		await create_timer(0.02).timeout
	check(false,"All coin particles arrive within five seconds")

func run() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		quit(2)
		return
	state = root.get_node("ShopState")
	state._save_path = "res://../art/coin_reward_test_%d.json"%OS.get_process_id()
	check(state.reset_progress(),"Isolated reward ledger")
	state.cash = 120
	root.size = Vector2i(390,844)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frame()
	check(game.hud.displayed_gold == 120,"Wallet starts with current gold")
	last_display = 120
	game.hud.coin_arrived.connect(on_coin)
	# Mouse and touch may open the placeholder, but cannot paint beneath it.
	tap(game.hud.control("UpgradeButton"))
	await frame()
	await create_timer(0.20).timeout
	check(game.hud.upgrades_open() and game.soil.simulation_suspended,"Upgrade button opens a modal and pauses cleaning")
	var before: Dictionary = game.soil.make_snapshot()
	var center: Vector2 = game.camera.unproject_position(Vector3.ZERO)
	game.begin_stroke(center,false)
	game.soil.stroke(Vector3(0,.067,-1),Vector3(0,.067,1),0.2)
	check(not game.brush_dragging and game.soil.make_snapshot() == before,"Upgrade modal blocks brushing and keeps rug progress")
	await capture("upgrades_portrait")
	game.back()
	check(not game.hud.upgrades_open() and current_scene == game and not game.soil.simulation_suspended,"Back closes upgrades before leaving and resumes the rug")
	await finish(0.85)
	check(state.cash == 140 and game.hud.displayed_gold == 120 and game.hud.pending_reward == 20,"85% pays20 durably while the display waits for coins")
	await finish_suction()
	await create_timer(0.24).timeout
	check(game.hud.active_coin_count() > 0 and arrivals.is_empty(),"Coins burst and linger before any gold arrives")
	await capture("burst20")
	# Automation during a reward must be reflected without absorbing or duplicating it.
	state.cash += 10
	state.changed.emit()
	last_display += 10
	check(game.hud.displayed_gold == last_display,"Unrelated income updates while reward coins are pending")
	root.size = Vector2i(844,390)
	await frame()
	await capture("flight_landscape")
	await settle_coins()
	var total := 0
	for value in arrivals: total += value
	check(total == 20 and game.hud.displayed_gold == 150 and state.cash == 150,"Coin values sum to20 without changing the already-credited balance")
	var early_count := arrivals.size()
	arrivals.clear()
	await finish(0.99)
	check(state.cash == 190 and game.hud.pending_reward == 40 and game.hud.displayed_gold == 150,"99% reserves a40-coin celebration")
	await finish_suction()
	await create_timer(0.24).timeout
	await capture("burst40_landscape")
	await settle_coins()
	total = 0
	for value in arrivals: total += value
	check(total == 40 and arrivals.size() > early_count and state.cash == 190 and game.hud.displayed_gold == 190,"Full clean gives a larger burst worth exactly40")
	# Failed durable payout must cancel its cosmetic reservation too.
	state._save_enabled = false
	await finish(0.85)
	check(state.cash == 190 and game.hud.pending_reward == 0 and game.hud.displayed_gold == 190,"Failed payout creates neither coins nor a hidden balance deduction")
	state._save_enabled = true
	# Check compact layouts and long balances with simulated notches.
	for dimensions: Vector2i in [Vector2i(320,568),Vector2i(390,844),Vector2i(844,390)]:
		root.size = dimensions
		await frame()
		game.hud.preview_safe_insets = Vector4(12,24,12,20)
		game.hud.sync_wallet(1234567890)
		await frame()
		for name: String in ["HomeButton","Wallet","CleaningProgress","UpgradeButton"]:
			check(game.hud._safe_rect().encloses(game.hud.control(name).get_global_rect()),name+" fits "+str(dimensions))
		check(not game.hud.control("Wallet").get_global_rect().intersects(game.hud.control("CleaningProgress").get_global_rect()),"Gold and cleanliness never overlap")
		tap(game.hud.control("UpgradeButton"))
		await frame()
		check(game.hud._safe_rect().encloses(game.hud.control("UpgradesPanel").get_global_rect()),"Upgrade modal fits "+str(dimensions))
		tap(game.hud.control("CloseUpgradesButton"))
		check(not game.hud.upgrades_open(),"Done closes the upgrade menu")
	game.hud.preview_safe_insets = Vector4.ZERO
	game.hud.sync_wallet(state.cash)
	last_display = state.cash
	# Leaving during the final celebration keeps the reward exactly once.
	await finish(0.85)
	await finish_suction()
	await create_timer(0.2).timeout
	check(game.hud.pending_reward > 0,"Interrupt an unfinished celebration")
	game.return_to_shop()
	await frame()
	check(state.cash == 210,"Leaving mid-flight retains the committed20")
	change_scene_to_file("res://scenes/production/rug_cleaning.tscn")
	await frame()
	game = current_scene
	check(game.hud.displayed_gold == 210 and game.hud.pending_reward == 0,"Reentry displays actual saved gold without replaying a payout")
	# The popup pauses even an unroll and resumes it on close.
	game.hud.open_upgrades()
	var entrance: Tween = game.transition_tween
	var elapsed := entrance.get_total_elapsed_time()
	await create_timer(0.15).timeout
	check(entrance.get_total_elapsed_time() == elapsed and not entrance.is_running(),"Upgrades pauses an in-progress rug transition")
	game.hud.close_upgrades()
	await create_timer(0.15).timeout
	check(entrance.get_total_elapsed_time() > elapsed,"Closing upgrades resumes the transition")
	game.free()
	current_scene = null
	state.set_process(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("COIN_REWARDS_VALIDATION %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
