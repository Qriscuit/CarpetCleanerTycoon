extends SceneTree
## Graphics-backed production integration; never touches player progress.
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
	state._test_ticks_msec = 0
	state._test_unix_time = 1000000.0
	state._save_path = "res://../art/store_loop_%d.json" % OS.get_process_id()
	check(state.reset_progress(), "Isolated ledger resets")
	state.cash = 50000
	root.size = Vector2i(390, 844)
	await enter_rug()
	var pool_id: int = game.soil.batch.get_instance_id()
	var scene_id: int = game.get_instance_id()
	check(game.hud.control("PayoutCard").visible and game.hud.control("PayoutUpgradeButton").visible, "Payout and distinct purchase button are visible")
	check(not game.hud.control("AdRewardButton").visible, "Ad button stays hidden without a configured provider")
	game.soil.remaining = 300
	game.soil.surface_coverage_total *= 0.7
	var before: Dictionary = game.soil.make_snapshot()
	var job: String = state.active_job_id
	tap(game.hud.control("PayoutUpgradeButton"))
	await frames()
	check(state.cash == 49975 and state.progression_view().early_reward == 22, "Touch purchases the first payout level for25")
	check(state.active_job_id == job and game.soil.make_snapshot() == before, "Payout purchase preserves current rug identity and dirt")
	check(state.reward_for_current_job({"unique_clearance":1.0,"surface_clearance":1.0}) == 44, "An unfinished rug immediately receives the new44 full quote")
	await capture("rug_portrait")
	tap(game.hud.control("UpgradeButton"))
	await create_timer(0.2).timeout
	check(game.hud.upgrades_open() and game.soil.simulation_suspended, "Left tool drawer pauses cleaning")
	for tier in 4:
		tap(game.hud.control("ToolUpgradeButton"))
		await frames()
		check(state.progression_view().tool_level == tier + 1, "Drawer purchases next tool tier")
	check(game.soil.head_half.x > 0.5 and game.soil.tool_strength > 1.0, "Capstone changes physical width and cleaning power")
	check(game.tool_visuals.active_tier == 4, "Capstone shows the engraved Blender brush")
	await capture("brush_drawer")
	game.hud.close_upgrades()
	await complete_rug()
	check(state.progression_view().final_tool_jobs == 0, "Rug begun before final-tool purchase does not count toward travel use")
	for index in 3: await complete_rug(0.85)
	check(state.progression_view().final_tool_jobs == 3, "Three subsequent paid rugs count toward final-tool use")
	var provider := TestAdProvider.new()
	check(state.register_reward_ad_provider(provider), "Test-only provider attaches through the real ad adapter")
	await frames()
	check(game.hud.control("AdRewardButton").visible and not game.hud.control("AdRewardButton").disabled, "Late provider setup refreshes the ready offer")
	var before_ad: int = state.cash
	tap(game.hud.control("AdRewardButton"))
	check(provider.callback.is_valid(), "Ad button requests the provider only after player action")
	provider.resolve()
	check(state.cash == before_ad + 22 and game.hud.pending_reward == 22 and game.hud.displayed_gold == before_ad, "Verified bonus saves once and reserves the visual coins before wallet synchronization")
	for tick in 110:
		if game.hud.pending_reward == 0: break
		await create_timer(0.02).timeout
	check(game.hud.displayed_gold == state.cash and game.hud.pending_reward == 0, "Ad coins arrive into the same wallet counter")
	provider.resolve()
	check(state.cash == before_ad + 22 and not game.hud.control("AdRewardButton").visible, "Duplicate callback grants no coins and the claimed offer disappears")
	check(game.get_instance_id() == scene_id and game.soil.batch.get_instance_id() == pool_id, "Upgrades and rewards retain the same scene and dirt pool")
	check(state.buy_bonzi_upgrade(), "Bonzi can be built after three paid rugs")
	state._produce(1200.0)
	check(state.progression_view().bonzi_earned >= 100 and state.progression_view().can_travel, "Bonzi earnings and final-tool use unlock affordable travel")
	root.size = Vector2i(844, 390)
	await capture("rug_landscape")
	for dimensions: Vector2i in [Vector2i(320,568),Vector2i(390,844),Vector2i(844,390)]:
		root.size = dimensions
		await frames()
		for name: String in ["PayoutCard","PayoutUpgradeButton","UpgradeButton","Wallet"]:
			check(game.hud._safe_rect().encloses(game.hud.control(name).get_global_rect()), name + " fits " + str(dimensions))
		check(not game.hud.control("PayoutCard").get_global_rect().intersects(game.hud.control("PayoutUpgradeButton").get_global_rect()), "Payout preview and purchase price do not overlap")
		var rug_top: Vector2 = game.camera.unproject_position(Vector3(-1.0, 0.06, -1.66))
		var rug_bottom: Vector2 = game.camera.unproject_position(Vector3(1.0, 0.06, 1.66))
		var rug_bounds := Rect2(rug_top, rug_bottom - rug_top)
		for name: String in ["PayoutCard", "PayoutUpgradeButton", "CleaningProgress", "UpgradeButton", "FinishJobButton"]:
			check(not rug_bounds.intersects(game.hud.control(name).get_global_rect()), "Whole rug stays clear of " + name + " at " + str(dimensions))
	game.return_to_shop()
	await frames()
	var home: Node = current_scene
	check(home.preview_store == 1, "Home opens the current store")
	home.open_management("plans")
	await capture("travel")
	home.management.action_for("intake").grab_focus()
	home.management._item_action("intake")
	await frames()
	check(home.management.pending_item == "travel", "Travel opens a concrete purchase review")
	check(home.management.action_for("hand_brush").focus_mode == Control.FOCUS_NONE, "Travel review excludes background purchase actions from keyboard focus")
	home.management.cancel_build()
	check(home.management.action_for("intake").has_focus(), "Cancel restores focus to the travel action")
	home.management._item_action("intake")
	home.management.confirm_build()
	await frames()
	check(state.active_store == 2 and home.preview_store == 2, "Travel selects the new store in both ledger and diorama")
	check(home.management.get_node("%CloseSheet").has_focus(), "Successful travel retains visible keyboard focus when its old button becomes disabled")
	check(state.progression_view().early_reward == 160, "Store2 starts at160 per early rug")
	home.close_management()
	var origin: Vector2 = home.get_node("%ShopTap").get_global_rect().get_center()
	for pressed: bool in [true,false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = origin if pressed else origin + Vector2(80,0)
		touch.pressed = pressed
		root.push_input(touch,true)
	await frames()
	check(state.active_store == 1 and current_scene == home, "Store swipe selects an owned store without entering cleaning")
	home.preview_location(3)
	state.changed.emit()
	check(home.get_node("%ShopTap").tooltip_text == "View store milestones", "Passive balance refresh preserves locked-store action copy")
	home.enter_cleaning()
	check(current_scene == home and home.get_node("%Management").visible, "Tapping a locked preview opens its store sheet")
	home.close_management()
	home.preview_location(2)
	await capture("store_two")
	# Seed a completed Store2 service history to exercise the real travel into wet recipes.
	for tier in 4: check(state.buy_tool_upgrade(), "Buy each Store2 tool tier")
	state.stores["2"].final_tool_jobs = 3
	state._produce(1200.0)
	check(state.open_next_store(), "Store3 opens with its wet starter kit")
	home.free()
	current_scene = null
	await enter_rug()
	check(game.wet_recipe and game.selected_tool == 0 and game.soil.overall_clearance() == 0.0, "Wet store starts at brush stage")
	game.soil.remaining = 0
	game.soil.surface_coverage_total = 0
	game.soil.coverage_values.fill(0.0)
	game.soil.credited.fill(true)
	game.soil.cleared.fill(true)
	game.soil.mask.fill(Color.BLACK)
	game.soil.mask_changed = true
	game.update_contract_status()
	game.end_stroke()
	await frames()
	check(game.selected_tool == 2 and game.progress_fraction > 0.32 and game.progress_fraction < 0.34, "Finished dry stage advances meter and automatically equips water")
	for z_step in 19:
		var z := -1.62 + z_step * 0.18
		for pass_index in 3: game.soil.apply_water_stroke(Vector3(-1.15,0.067,z),Vector3(1.15,0.067,z),0.08)
	game.end_stroke()
	await frames()
	check(game.selected_tool == 1 and game.progress_fraction > 0.65, "Water stage automatically equips the squeegee")
	await capture("wet_squeegee")
	var wet_job: String = state.active_job_id
	for pass_index in 3:
		for z_step in 34:
			var z := -1.65 + z_step * 0.10
			game.soil.apply_squeegee_stroke(Vector3(-1.15,0.067,z),Vector3(1.15,0.067,z),0.08)
	await frames()
	check(game.contract_finished and state.active_job_id != wet_job, "Wet recipe completes and reserves the next rug automatically")
	game.free()
	current_scene = null
	state.cash = 2000000
	for tier in 4: state.buy_tool_upgrade()
	state.stores["3"].final_tool_jobs = 3
	state._produce(1200.0)
	check(state.open_next_store(), "Store4 opens after wet capstone service")
	state.stores["4"].payout_level = 19
	root.size = Vector2i(320,568)
	await enter_rug()
	check(state.progression_view().full_reward == 124928, "Store4 level19 exposes the expected six-digit payout")
	for name: String in ["PayoutCard","PayoutUpgradeButton","Wallet"]:
		check(game.hud._safe_rect().encloses(game.hud.control(name).get_global_rect()), "Large-value " + name + " fits a narrow phone")
	await capture("store_four_values")
	game.free()
	current_scene = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("STORE_LOOP_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
