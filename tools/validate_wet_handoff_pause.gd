extends SceneTree
## Real workshop/mask handoff without rendering assertions or paid wet stores.
const CLEANING := preload("res://scenes/production/rug_cleaning.tscn")
const HUD := preload("res://scripts/cleaning_hud.gd")
var checks := 0
var failures := 0
var game: Node
var state: Node
var save_path := ""
var ledger_before: Dictionary

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("WET HANDOFF: " + message)

func frames(count: int = 3) -> void:
	for _step in count: await process_frame

func video_pause(pending: bool) -> void:
	# The unpaid wet fixture bypasses ledger progression, so supply the same
	# paired HUD state that production _sync_progression supplies for a video.
	game.hud.set_carpet_ad_offer(HUD.CarpetAdState.REQUESTING if pending else HUD.CarpetAdState.HIDDEN)
	game._sync_carpet_video_pause(pending)

func prepare_finished_rinse(cycle: int = 0, extraction: float = 1.0) -> void:
	check(not game.carpet_video_pending and game.application_focused and not game.hud.upgrades_open(), "Fixture preparation starts with all pause sources clear")
	game.soil.suspend_simulation(false)
	game.soil.prepare_extraction_stage(cycle)
	game.select_tool(1)
	# Exact real arrays and masks model the completed blade pass whose deferred
	# handoff competes with a video/modal/focus notification in the same frame.
	game.soil.extraction_values.fill(extraction)
	game.soil.extraction_coverage_total = extraction * float(game.soil.surface_pixel_count)
	game.soil.extraction_mask.fill(Color(extraction, extraction, extraction))
	game.soil.extraction_mask_changed = true
	game.soil.request_render()
	game.soil._process(0.0)
	check(game.soil.wash_cycle == cycle and game.selected_tool == 1 and game.soil.water_stage_complete(), "The authored workshop has a soaked rinse and its real squeegee equipped")
	check(game.soil.extraction_stage_complete() == (extraction >= game.soil.WET_STAGE_TARGET), "Real mask totals determine whether the deferred handoff is eligible")

func wet_state() -> Dictionary:
	return {
		"cycle":game.soil.wash_cycle,"water":game.soil.water_values.duplicate(),
		"extraction":game.soil.extraction_values.duplicate(),
		"water_total":game.soil.water_coverage_total,"extraction_total":game.soil.extraction_coverage_total,
		"global_water":game.soil.global_water_level,"tool":game.selected_tool,
	}

func check_frozen(before: Dictionary, label: String) -> void:
	game._advance_wet_tool()
	await frames()
	check(game.soil.simulation_suspended, label + ": soil remains suspended")
	check(wet_state() == before, label + ": direct and already-deferred calls preserve rinse, masks and equipped tool")
	check(not game.brush_dragging, label + ": no stroke survives the pause")

func check_handoff(next_cycle: int, label: String) -> void:
	await frames()
	check(not game.soil.simulation_suspended and game.soil.wash_cycle == next_cycle, label + ": resume advances exactly one rinse")
	check(game.soil.water_clearance() == 0.0 and game.soil.extraction_clearance() == 0.0 and game.soil.global_water_level == 0.0, label + ": the next rinse starts with the real water/extraction masks empty")
	check(game.selected_tool == 2 and game.soil.recommended_tool() == 2, label + ": the existing tool switches to the next hose round")
	game._advance_wet_tool()
	game._advance_wet_tool.call_deferred()
	await frames()
	check(game.soil.wash_cycle == next_cycle and game.soil.water_clearance() == 0.0, label + ": repeated handoff callbacks cannot skip another rinse")
	check(state._capture_state() == ledger_before, label + ": the future wet fixture cannot alter the player's carpet, boost or wallet")

func check_video_resume() -> void:
	prepare_finished_rinse()
	var before := wet_state()
	video_pause(true)
	check(game.carpet_video_pending and game.hud._wallet_paused and game.cleaning_reward_timer.paused, "Video begins with dirt, wallet and reward clocks paused")
	await check_frozen(before,"Video")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await check_frozen(before,"Video plus focus loss")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await check_frozen(before,"Focus return while video is pending")
	check(game.hud._wallet_paused and game.cleaning_reward_timer.paused, "Focus return cannot release the video's wallet and reward clocks")
	video_pause(false)
	await check_handoff(1,"Video verification")
	check(not game.hud._wallet_paused and not game.cleaning_reward_timer.paused, "Verified video releases both presentation clocks")

func check_background_video_resume() -> void:
	prepare_finished_rinse(1)
	var before := wet_state()
	video_pause(true)
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	video_pause(false)
	await check_frozen(before,"Video reply while backgrounded")
	check(not game.carpet_video_pending and game.hud._wallet_paused and game.cleaning_reward_timer.paused, "The reply ends video waiting without releasing the focus pause")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await check_handoff(2,"Foreground after verified reply")

func check_modal_resume() -> void:
	prepare_finished_rinse()
	var before := wet_state()
	game.hud.open_upgrades()
	check(game.hud.upgrades_open(), "The actual production shop modal opens")
	await check_frozen(before,"Shop modal")
	game.hud.close_upgrades()
	await check_handoff(1,"Shop close")
	prepare_finished_rinse()
	before = wet_state()
	game.hud.open_upgrades()
	video_pause(true)
	video_pause(false)
	await check_frozen(before,"Video reply beneath an open modal")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game.hud.close_upgrades()
	await check_frozen(before,"Modal close while backgrounded")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await check_handoff(1,"Foreground after modal close")

func check_focus_and_incomplete_resume() -> void:
	prepare_finished_rinse()
	var before := wet_state()
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await check_frozen(before,"Focus pause alone")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await check_handoff(1,"Focus return alone")
	prepare_finished_rinse(0,0.5)
	before = wet_state()
	video_pause(true)
	await check_frozen(before,"Video during incomplete extraction")
	video_pause(false)
	await frames()
	check(not game.soil.simulation_suspended and wet_state() == before and game.selected_tool == 1, "Resuming incomplete extraction restores the same squeegee pass without skipping its remaining work")
	prepare_finished_rinse()
	before = wet_state()
	game.soil.suspend_simulation(true)
	await check_frozen(before,"Explicit soil suspension")
	game.soil.suspend_simulation(false)
	game._advance_wet_tool()
	await check_handoff(1,"Explicit simulation resume")

func run() -> void:
	# This mask/state test has no audio assertions. Keep the dummy headless
	# mixer from holding an active music playback during immediate shutdown.
	root.get_node("GameAudio").set_process(false)
	state = root.get_node("ShopState")
	save_path = "res://.godot/wet_handoff_%d.json" % OS.get_process_id()
	state._save_path = save_path



	state.set_process(false)
	check(state.reset_progress(), "Reset a disposable ledger")
	state.start_job()
	check(state.record_cleaning_progress(state.active_job_id,{"unique_clearance":0.5,"surface_clearance":0.5}) == 10.0, "The fixture preserves a separately reserved paid brush carpet")
	ledger_before = state._capture_state()
	game = CLEANING.instantiate()
	game.practice_only = true
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frames()
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not game.paid_contract and game.rug_phase == game.RugPhase.CLEANING and game.soil != null, "Instantiate the actual workshop in an unpaid isolated wet fixture")
	game.wet_recipe = true
	game.water_only_recipe = true
	game.soil.set_recipe(true,true)
	game._ensure_wet_runtime()
	game._sync_wet_runtime_state()
	await frames()
	await check_video_resume()
	await check_background_video_resume()
	await check_modal_resume()
	await check_focus_and_incomplete_resume()
	check(state._capture_state() == ledger_before and state.cash == 10.0, "All handoff pauses and resumes leave saved paid money and reservations untouched")
	game.free()
	game = null
	current_scene = null
	await frames()
	for suffix: String in ["", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	print("WET_HANDOFF_PAUSE_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
