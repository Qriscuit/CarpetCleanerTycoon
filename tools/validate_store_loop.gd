extends SceneTree
## Graphics-backed production integration; never touches player progress.
const ShopLedger = preload("res://scripts/shop_state.gd")
const Rules := preload("res://scripts/progression.gd")
const Room := preload("res://scripts/room_upgrades.gd")
const Money := preload("res://scripts/money.gd")
var checks := 0
var failures := 0
var state: Node
var game: Node

class TestAdProvider extends RefCounted:
	var job := ""
	var nonce := ""
	var callback: Callable
	func is_rewarded_ad_available() -> bool: return true
	func request_verified_reward(job_id: String, request_nonce: String, result: Callable) -> bool:
		job = job_id
		nonce = request_nonce
		callback = result
		return true
	func verify_reward_receipt(job_id: String, request_nonce: String, receipt: Dictionary) -> bool:
		return job_id == job and request_nonce == nonce and receipt.get("test_verified", false)
	func resolve() -> void:
		if callback.is_valid(): callback.call(job, nonce, {"receipt_id":"store-loop-test", "test_verified":true})

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	await process_frame
	if is_instance_valid(game) and not game.application_focused:
		game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await process_frame
	await RenderingServer.frame_post_draw

func capture(label: String) -> void:
	await frames()
	root.get_texture().get_image().save_png("res://../art/renders/progression_" + label + ".png")

func tap(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = button.get_global_rect().get_center()
		event.pressed = pressed
		root.push_input(event, true)

func enter_rug() -> void:
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frames()

func settle_home(home: Node) -> void:
	for tick in 150:
		if not home.store_transition_active: break
		await create_timer(0.02).timeout
	check(not home.store_transition_active, "Store carousel settles before the next gesture")
	await frames()

func complete_rug(amount: float = 1.0) -> void:
	game.soil.remaining = floori(game.soil.initial.size() * (1.0 - amount) + 0.00001)
	game.soil.surface_coverage_total = game.soil.surface_pixel_count * (1.0 - amount)
	state.note_current_tool_used()
	game.update_contract_status()
	if amount < 0.99: game.finish_rug()
	await process_frame
	for tick in 130:
		if game.soil.vacuum_complete: break
		game.soil._physics_process(1.0 / 60.0)
	await frames()
	for tick in 110:
		if game.hud.pending_reward == 0: break
		await create_timer(0.02).timeout

func run() -> void:
	state = root.get_node("ShopState")
	state.set_process(false)
	state._save_path = "res://.godot/store_loop_%d.json" % OS.get_process_id()
	check(state.reset_progress(), "Isolated ledger resets")
	state.cash = 50000
	root.size = Vector2i(390, 844)
	await enter_rug()
	var pool_id: int = game.soil.batch.get_instance_id()
	var scene_id: int = game.get_instance_id()
	check(game.hud.get_node_or_null("%PayoutCard") == null and game.hud.get_node_or_null("%PayoutUpgradeButton") == null, "Paid cleaning has no persistent earnings footer or generic purchase button")
	check(game.hud.control("EarningsPerCarpet").visible and game.hud.control("CarpetEarningsValue").text == "40", "Paid cleaning shows its starter full-clean earnings beneath the progress bar")
	check(game.hud.control("AdRewardButton").visible and game.hud.control("AdRewardButton").disabled and game.hud._carpet_ad_state == game.hud.CarpetAdState.LOCKED, "The current-carpet ad action shows its locked state without a configured provider")
	game.soil.remaining = 300
	game.soil.surface_coverage_total *= 0.7
	var before: Dictionary = game.soil.make_snapshot()
	var job: String = state.active_job_id
	game.hud.open_room_upgrade(state.room_upgrade_view("floor"), true)
	await frames()
	check(game.hud.room_panel.get_node("%CleanValue").text == "40 → 46" and game.hud.room_panel.offer.early_reward == 20 and game.hud.room_panel.offer.next_early == 23, "Selected floor offer shows its independent Clean increase")
	tap(game.hud.room_panel.get_node("%Buy"))
	await frames()
	check(state.cash == 49960 and state.progression_view().early_reward == 23 and state.room_upgrade_levels().floor == 1, "Touch purchases the selected floor improvement for its own40 coin price")
	check(state.active_job_id == job and game.soil.make_snapshot() == before, "Payout purchase preserves current rug identity and dirt")
	check(state.reward_for_current_job({"unique_clearance":1.0,"surface_clearance":1.0}) == 46, "An unfinished rug immediately receives the new46 full quote")
	check(game.hud.control("CarpetEarningsValue").text == "46", "The visible earnings amount refreshes after the real floor purchase")
	game.hud.close_upgrades()
	await capture("rug_portrait")
	tap(game.hud.control("UpgradeButton"))
	await create_timer(0.2).timeout
	check(game.hud.upgrades_open() and game.soil.simulation_suspended, "Left tool drawer pauses cleaning")
	for tier in 4:
		state.cash = maxf(state.cash, Rules.tool_cost(state.active_store, tier) * 2.0)
		check(state.save_state(), "Fund each isolated brush purchase at its actual earning milestone")
		tap(game.hud.control("ToolUpgradeButton"))
		await frames()
		check(state.progression_view().tool_level == tier + 1, "Drawer purchases next tool tier")
	check(game.soil.head_half.x > 0.5 and game.soil.tool_strength > 1.0, "Capstone changes physical width and cleaning power")
	check(game.tool_visuals.active_tier == 4, "Capstone shows the engraved Blender brush")
	await capture("brush_drawer")
	game.hud.close_upgrades()
	await complete_rug()
	check(state.progression_view().final_tool_jobs == 1, "Current rug counts after the newly purchased final tool is used")
	for index in 3: await complete_rug(0.75)
	check(state.progression_view().final_tool_jobs == 3, "Three subsequent paid rugs count toward final-tool use")
	game.hud._process(0.25)
	var ad_button := game.hud.control("AdRewardButton") as Button
	check(ad_button.visible and ad_button.disabled and game.hud._carpet_ad_state == game.hud.CarpetAdState.LOCKED, "The current-carpet video action stays visibly locked without a provider")
	var provider := TestAdProvider.new()
	check(state.register_reward_ad_provider(provider), "Test-only provider attaches through the real ad adapter")
	await frames()
	check(game.hud.control("AdRewardButton").visible and not game.hud.control("AdRewardButton").disabled, "Late provider setup refreshes the ready offer")
	var before_ad: float = state.cash
	var base_quote: float = state.current_job_full_reward()
	var boosted_job: String = state.active_job_id
	check(float(state._branch().job_cleaning_paid) == 0.0, "The newly reserved carpet has no progressive money to top up")
	tap(game.hud.control("AdRewardButton"))
	check(provider.callback.is_valid() and ad_button.disabled and game.hud._carpet_ad_state == game.hud.CarpetAdState.REQUESTING, "A real tap requests the video once and disables duplicate requests")
	provider.resolve()
	check(state.cash == before_ad and state.current_job_full_reward() == base_quote * 2.0 and game.hud.pending_reward == 0.0 and game.hud.displayed_gold == before_ad, "Verified video doubles the current quote without granting unearned money or reward flights")
	check(ad_button.visible and ad_button.disabled and game.hud._carpet_ad_state == game.hud.CarpetAdState.ACTIVE and game.hud.control("CarpetEarningsValue").text == Money.format(base_quote * 2.0), "The doubled quote has a persistent active indicator and its actual per-carpet value")
	state._load_state()
	state.changed.emit()
	await frames()
	check(state.active_job_id == boosted_job and state.current_job_full_reward() == base_quote * 2.0 and bool(state._branch().job_ad_boost) and ad_button.visible and ad_button.disabled, "Reload retains the same boosted job and active disabled video state")
	provider.resolve()
	check(state.cash == before_ad and state.current_job_full_reward() == base_quote * 2.0 and ad_button.visible and ad_button.disabled, "A replayed verified receipt cannot add money or multiply the quote again")
	check(game.get_instance_id() == scene_id and game.soil.batch.get_instance_id() == pool_id, "Upgrades and rewards retain the same scene and dirt pool")
	if not master_current_store():
		quit(1)
		return
	check(state.progression_view().can_travel, "Completing every accessory and the max-brush jobs enables affordable travel")
	root.size = Vector2i(844, 390)
	await capture("rug_landscape")
	for dimensions: Vector2i in [Vector2i(320,568),Vector2i(390,844),Vector2i(844,390)]:
		root.size = dimensions
		await frames()
		for name: String in ["UpgradeButton","AdRewardButton","Wallet","EarningsPerCarpet"]:
			check(game.hud._safe_rect().encloses(game.hud.control(name).get_global_rect()), name + " fits " + str(dimensions))
		var rug_top: Vector2 = game.camera.unproject_position(Vector3(-1.0, 0.06, -1.66))
		var rug_bottom: Vector2 = game.camera.unproject_position(Vector3(1.0, 0.06, 1.66))
		var rug_bounds := Rect2(rug_top, rug_bottom - rug_top)
		for name: String in ["CleaningProgress", "EarningsPerCarpet", "UpgradeButton", "FinishJobButton"]:
			check(not rug_bounds.intersects(game.hud.control(name).get_global_rect()), "Whole rug stays clear of " + name + " at " + str(dimensions))
		game.hud.open_room_upgrade(state.room_upgrade_view("plants"), true)
		await frames()
		check(game.hud._safe_rect().grow(1.0).encloses(game.hud.room_panel.get_node("%Card").get_global_rect()), "Room offer fits " + str(dimensions))
		game.hud.close_upgrades()
	game.return_to_shop()
	await frames()
	var home: Node = current_scene
	check(home.preview_store == 1, "Home opens the current store")
	home.open_management("plans")
	await capture("travel")
	home.management.action_for("slot_5").grab_focus()
	home.management._item_action("slot_5")
	await frames()
	check(home.management.pending_item == "travel", "Travel opens a concrete purchase review")
	check(home.management.action_for("slot_1").focus_mode == Control.FOCUS_NONE, "Travel review excludes background purchase actions from keyboard focus")
	home.management.cancel_build()
	check(home.management.action_for("slot_5").has_focus(), "Cancel restores focus to the travel action")
	home.management._item_action("slot_5")
	home.management.confirm_build()
	await settle_home(home)
	check(state.active_store == 2 and home.preview_store == 2, "Travel selects the new store in both ledger and diorama")
	check(home.management.get_node("%CloseSheet").has_focus(), "Successful travel retains visible keyboard focus when its old button becomes disabled")
	check(state.progression_view().early_reward == 20.0 * Rules.scale_for(2), "Store2 starts at the first place\'s mastered payout")
	home.close_management()
	var origin: Vector2 = home.get_node("%ShopTap").get_global_rect().get_center()
	for pressed: bool in [true,false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = origin if pressed else origin + Vector2(80,0)
		touch.pressed = pressed
		root.push_input(touch,true)
	await settle_home(home)
	check(state.active_store == 1 and current_scene == home, "Store swipe selects an owned store without entering cleaning")
	home.preview_location(3)
	await settle_home(home)
	state.changed.emit()
	check(home.get_node("%ShopTap").tooltip_text == "View store milestones", "Passive balance refresh preserves locked-store action copy")
	home.enter_cleaning()
	check(current_scene == home and home.get_node("%Management").visible, "Tapping a locked preview opens its store sheet")
	home.close_management()
	home.preview_location(2)
	await settle_home(home)
	await capture("store_two")
	if not master_current_store():
		quit(1)
		return
	check(state.open_next_store(), "Completing the second place opens the third brush workshop")
	home.free()
	current_scene = null
	for store_id in range(3, Rules.STORE_COUNT + 1):
		await enter_rug()
		check(state.active_store == store_id and not game.wet_recipe and game.selected_tool == 0, "First-section place%d enters ordinary brush cleaning" % store_id)
		check(state.progression_view().full_reward == 40.0 * Rules.scale_for(store_id), "Each new place inherits the preceding mastered earnings")
		check(game.hud.control("CarpetEarningsValue").text == Money.format(state.progression_view().full_reward), "Every real workshop renders its current per-carpet amount at the new store scale")
		var visible_job: String = state.active_job_id
		var before_cash: float = state.cash
		var reward: float = state.progression_view().full_reward
		await complete_rug()
		check(state.active_job_id != visible_job and is_equal_approx(state.cash, before_cash + reward), "The actual brush workshop pays its new scale once and reserves the next rug")
		root.size = Vector2i(320,568)
		await frames()
		check(game.hud._safe_rect().encloses(game.hud.control("Wallet").get_global_rect()), "The growing wallet fits a narrow phone at place%d" % store_id)
		if store_id == 4: await capture("store_four_values")
		if store_id == 6: await capture("store_six_values")
		if not master_current_store():
			quit(1)
			return
		game.free()
		current_scene = null
		if store_id < Rules.STORE_COUNT:
			check(state.open_next_store(), "Mastering place%d opens exactly its successor" % store_id)
		else:
			check(state.section_progress(1).complete and not state.section_progress(1).next_available and not state.open_next_store(), "Six completed places finish the first section while the future chapter stays locked")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("STORE_LOOP_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func master_current_store() -> bool:
	for id: String in Room.IDS:
		for _upgrade in range(int(state.room_upgrade_levels()[id]), Rules.room_level_cap(state.active_store)):
			var offer: Dictionary = state.room_upgrade_view(id)
			state.cash = maxf(float(offer.cost) * 2.0, Rules.reward_cap(state.active_store) * 10.0)
			var bought: bool = state.buy_room_upgrade(id)
			check(bought, "Complete store%d/%s level%d for travel: %s" % [state.active_store,id,int(offer.next_level),state.last_error])
			if not bought: return false
	state.cash = maxf(Rules.reward_cap(state.active_store) * 10.0, 10000.0 * Rules.scale_for(state.active_store))
	for _tier in range(int(state.progression_view().tool_level), 4):
		check(state.buy_tool_upgrade(), "Complete the current brush track")
	state.stores[str(state.active_store)].final_tool_jobs = 3
	check(state.save_state(), "The authored travel fixture commits every room and tool goal")
	return failures == 0
