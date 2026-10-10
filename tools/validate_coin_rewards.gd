extends SceneTree
## Live cleaning count-ups, verified-ad coin flights and modal input isolation.
var failures := 0
var checks := 0
var game: Node
var state: Node
var arrivals: Array[float] = []
var last_display := 0.0

class TestProvider extends RefCounted:
	var requests := 0
	var pending_job := ""
	var pending_nonce := ""
	var callback: Callable
	func is_rewarded_ad_available() -> bool: return true
	func request_verified_reward(job_id: String, nonce: String, result: Callable) -> bool:
		requests += 1
		pending_job = job_id
		pending_nonce = nonce
		callback = result
		return true
	func verify_reward_receipt(job_id: String, nonce: String, receipt: Dictionary) -> bool:
		return receipt.get("signed_test_receipt") == true and job_id == pending_job and nonce == pending_nonce
	func resolve(valid: bool = true) -> void:
		callback.call(pending_job, pending_nonce, {"receipt_id": "coin-receipt-%d" % requests, "signed_test_receipt": valid})

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
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frame()
	root.get_texture().get_image().save_png("res://../art/renders/coins_" + label + ".png")

func tap(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = button.get_global_rect().get_center()
		event.pressed = pressed
		root.push_input(event, true)

func on_coin(value: float) -> void:
	arrivals.append(value)
	check(game.hud.displayed_gold == last_display + value, "Each ad coin adds exactly its own value to the displayed wallet")
	last_display = game.hud.displayed_gold

func finish(amount: float) -> void:
	# Contact/removal integration has its own real-brush suite. Deterministic
	# completion counters isolate the terminal wallet presentation here.
	game.soil.remaining = floori(float(game.soil.initial.size()) * (1.0 - amount) + 0.0001)
	game.soil.surface_coverage_total = float(game.soil.surface_pixel_count) * (1.0 - amount)
	game.update_contract_status()
	if amount < 0.99: tap(game.finish_button)
	await process_frame

func finish_suction() -> void:
	for _tick in 180:
		if game.soil.vacuum_complete: break
		game.soil._physics_process(1.0 / 60.0)
	var completed: bool = game.soil.vacuum_complete
	await frame()
	check(completed, "Vacuum completes before the next carpet is requested")

func advance_finished() -> void:
	await finish_suction()
	game.next_rug()
	await frame()
	check(game.rug_phase == game.RugPhase.CLEANING and not game.contract_finished, "The replacement carpet becomes playable without another payout")

func settle_coins() -> void:
	for _tick in 100:
		if game.hud.pending_reward == 0.0 and game.hud.active_coin_count() == 0: return
		game.hud._process(0.05)
	check(false, "All ad coins arrive within five simulated seconds")

func run() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		quit(2)
		return
	state = root.get_node("ShopState")
	state.set_process(false)
	state._test_ticks_msec = 0
	state._test_unix_time = 1800000000.0
	state._save_path = "res://.godot/coin_reward_test_%d.json" % OS.get_process_id()
	check(state.reset_progress(), "The reward ledger is isolated from the player's save")
	state.cash = 120.0
	check(state.save_state(), "The starting wallet is saved")
	root.size = Vector2i(390, 844)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await frame()
	check(game.hud.displayed_gold == 120.0, "The wallet starts with current gold")
	game.hud.coin_arrived.connect(on_coin)
	tap(game.hud.control("UpgradeButton"))
	await frame()
	await create_timer(0.20).timeout
	check(game.hud.upgrades_open() and game.soil.simulation_suspended, "Shop opens a modal and pauses cleaning")
	var before: Dictionary = game.soil.make_snapshot()
	var center: Vector2 = game.camera.unproject_position(Vector3.ZERO)
	game.begin_stroke(center, false)
	game.soil.stroke(Vector3(0, .067, -1), Vector3(0, .067, 1), 0.2)
	check(not game.brush_dragging and game.soil.make_snapshot() == before, "The shop blocks brushing and keeps rug progress")
	await capture("upgrades_portrait")
	game.back()
	check(not game.hud.upgrades_open() and current_scene == game and not game.soil.simulation_suspended, "Back closes the shop before leaving and resumes the rug")
	var early_job: String = game.contract_job_id
	await finish(0.75)
	check(state.cash == 140.0 and float(state.completed_rewards[early_job].amount) == 20.0 and game.completed_reward == 0.0, "75% settles 20 cleaning coins without the restoration half or a delayed second award")
	check(game.soil.completion_started and not game.soil.vacuum_complete and game.hud.pending_reward == 0.0 and game.hud.active_coin_count() == 0, "The cleaning count begins during vacuum instead of waiting for reward flights")
	check(game.hud.displayed_gold >= 120.0 and game.hud.displayed_gold <= 140.0, "The count-up stays between the previous and committed wallet")
	var displayed_before: float = game.hud.displayed_gold
	state.cash += 10.0
	state.changed.emit()
	check(game.hud.displayed_gold == displayed_before + 10.0, "Unrelated income is reflected without absorbing the cleaning count-up")
	game.hud._process(0.25)
	check(game.hud.displayed_gold == 150.0 and game.hud._cleaning_pending == 0.0 and arrivals.is_empty(), "The cleaning wallet settles promptly without generating ad coin arrivals")
	await capture("cleaning20")
	await advance_finished()
	check(state.cash == 150.0, "Next carpet does not replay the early settlement")

	# Ads remain genuine provider-verified ledger rewards with cosmetic flights.
	var provider := TestProvider.new()
	check(state.register_reward_ad_provider(provider) and state.reward_ad_available(), "A verified test provider enables the completed-carpet ad")
	check(state.request_reward_ad(early_job), "The early ad request starts once")
	provider.callback.call(early_job, "wrong-nonce", {"receipt_id": "forged", "signed_test_receipt": true})
	check(state.cash == 150.0 and game.hud.pending_reward == 0.0, "A mismatched callback cannot create money or cosmetic coins")
	provider.resolve(false)
	check(state.cash == 150.0 and state.request_reward_ad(early_job), "An unverified receipt pays nothing and allows a valid retry")
	state._save_enabled = false
	provider.resolve()
	check(state.cash == 150.0 and game.hud.pending_reward == 0.0 and not state.completed_rewards[early_job].ad_claimed, "A failed ad write creates neither money nor a hidden wallet reservation")
	state._save_enabled = true
	last_display = 150.0
	check(state.request_reward_ad(early_job) and state.cash == 170.0 and game.hud.pending_reward == 20.0, "Retry pays the entire early job's 20 coins exactly once")
	provider.resolve()
	check(state.cash == 170.0 and not state.request_reward_ad(early_job), "Duplicate callbacks and requests cannot replay an ad")
	check(game.hud.active_coin_count() == 10 and arrivals.is_empty(), "The 20-coin ad uses a bounded cosmetic burst before any arrivals")
	await capture("ad_burst20")
	state.cash += 10.0
	state.changed.emit()
	last_display += 10.0
	check(game.hud.displayed_gold == last_display, "Unrelated income updates while ad coins are pending")
	root.size = Vector2i(844, 390)
	await frame()
	await capture("ad_flight_landscape")
	settle_coins()
	var total := 0.0
	for value in arrivals: total += value
	check(total == 20.0 and game.hud.displayed_gold == 180.0 and state.cash == 180.0, "Ad coin values sum to 20 without changing already-credited money")
	var early_count := arrivals.size()
	arrivals.clear()

	var full_job: String = game.contract_job_id
	await finish(0.99)
	check(state.cash == 220.0 and float(state.completed_rewards[full_job].amount) == 40.0 and game.hud.pending_reward == 0.0, "99% settles the exact unchanged 40-coin full quote")
	game.hud._process(0.25)
	check(game.hud.displayed_gold == 220.0 and game.hud.active_coin_count() == 0, "Full restoration counts promptly before the next carpet")
	await advance_finished()
	last_display = 220.0
	check(state.request_reward_ad(full_job), "The full-job ad uses its own verified request")
	provider.resolve()
	check(state.cash == 260.0 and game.hud.pending_reward == 40.0 and game.hud.displayed_gold == 220.0, "A full-job ad reserves 40 cosmetic coins after its durable credit")
	await capture("ad_burst40_landscape")
	settle_coins()
	total = 0.0
	for value in arrivals: total += value
	check(total == 40.0 and arrivals.size() > early_count and state.cash == 260.0 and game.hud.displayed_gold == 260.0, "The larger full-job ad burst is worth exactly 40")
	check(game.hud._coin_nodes.size() == 24 and game.hud.active_coin_count() == 0, "Cleaning and ads preserve the fixed cosmetic pool")
	state._save_enabled = false
	await finish(0.75)
	check(state.cash == 260.0 and game.hud.pending_reward == 0.0 and game.hud._reserved_reward == 0.0 and game.hud.displayed_gold == 260.0, "Failed cleaning settlement creates neither count-up nor hidden deduction")
	state._save_enabled = true

	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(390, 844), Vector2i(844, 390)]:
		root.size = dimensions
		await frame()
		game.hud.preview_safe_insets = Vector4(12, 24, 12, 20)
		game.hud.sync_wallet(1234567890.0)
		await frame()
		for name: String in ["HomeButton", "Wallet", "CleaningProgress", "UpgradeButton"]:
			check(game.hud._safe_rect().grow(0.5).encloses(game.hud.control(name).get_global_rect()), name + " fits " + str(dimensions))
		check(not game.hud.control("Wallet").get_global_rect().intersects(game.hud.control("CleaningProgress").get_global_rect()), "Gold and cleanliness never overlap")
		tap(game.hud.control("UpgradeButton"))
		await frame()
		check(game.hud._safe_rect().grow(0.5).encloses(game.hud.control("UpgradesPanel").get_global_rect()), "The shop fits " + str(dimensions))
		tap(game.hud.control("CloseUpgradesButton"))
		check(not game.hud.upgrades_open(), "Done closes the shop")
	game.hud.preview_safe_insets = Vector4.ZERO
	game.hud.sync_wallet(state.cash)
	await finish(0.75)
	check(state.cash == 280.0 and game.contract_finished, "The failed early settlement can retry successfully once")
	game.return_to_shop()
	await frame()
	check(state.cash == 280.0, "Leaving during the count-up retains its committed 20 coins")
	current_scene.free()
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = true
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await frame()
	check(game.hud.displayed_gold == 280.0 and game.hud.pending_reward == 0.0 and game.hud._cleaning_pending == 0.0, "Reentry displays saved money without replaying a count-up or payout")
	game.hud.open_upgrades()
	var entrance: Tween = game.transition_tween
	check(entrance != null and entrance.is_valid(), "Reentry fixture uses a real arrival tween")
	if entrance != null and entrance.is_valid():
		var elapsed := entrance.get_total_elapsed_time()
		await create_timer(0.15).timeout
		check(entrance.get_total_elapsed_time() == elapsed and not entrance.is_running(), "The shop pauses an in-progress rug arrival")
		game.hud.close_upgrades()
		await create_timer(0.15).timeout
		check(entrance.get_total_elapsed_time() > elapsed, "Closing the shop resumes the transition")
	game.free()
	current_scene = null
	state.set_process(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	var audio := root.get_node_or_null("GameAudio")
	if audio != null: audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	print("COIN_REWARDS_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
