extends SceneTree
## Exercise the real video button, pause gates and doubled carpet payouts.
const Routes := preload("res://scripts/scene_routes.gd")
const HUD := preload("res://scripts/cleaning_hud.gd")
var checks := 0
var failures := 0
var state: Node
var game: Node
var save_path := ""

class VideoProvider extends RefCounted:
	var job := ""
	var nonce := ""
	var callback: Callable
	var requests := 0
	func is_rewarded_ad_available() -> bool: return true
	func request_verified_reward(requested_job: String, requested_nonce: String, result: Callable) -> bool:
		job = requested_job
		nonce = requested_nonce
		callback = result
		requests += 1
		return true
	func verify_reward_receipt(requested_job: String, requested_nonce: String, receipt: Dictionary) -> bool:
		return requested_job == job and requested_nonce == nonce and receipt.get("status") == "completed" and receipt.get("verified") == true
	func finish(status: String, receipt_id: String) -> void:
		callback.call(job, nonce, {"status": status, "verified": true, "receipt_id": receipt_id})

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Carpet video flow needs a renderer and -- --shop-test")
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CARPET VIDEO: " + message)

func frames(count: int = 2) -> void:
	for _step in count:
		await process_frame
		await RenderingServer.frame_post_draw

func enter() -> void:
	game = load(Routes.CLEANING).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frames()
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(game.paid_contract and game.rug_phase == game.RugPhase.CLEANING, "Enter a real paid carpet")

func leave() -> void:
	game.free()
	game = null
	current_scene = null
	await frames()

func cleanliness(fraction: float) -> void:
	var soil: Node = game.soil
	soil.set_physics_process(false)
	soil.active.clear()
	soil.timed_debris.clear()
	soil.floor_debris.clear()
	soil.moving.fill(false)
	soil.velocities.fill(Vector3.ZERO)
	soil.growth.fill(0.0)
	soil.awakened.fill(false)
	soil.credited.fill(true)
	soil.retired_credits.fill(true)
	soil.retired_credit_count = soil.initial.size()
	soil.cleared.fill(true)
	soil.recycled.fill(true)
	soil.debris_age.fill(-1.0)
	soil.cooldown.fill(0.0)
	soil.remaining = 0
	soil.surface_coverage_total = 0.0
	for index in soil.coverage_values.size():
		var value: float = 1.0 - fraction if soil.surface_pixels[index] == 1 else 0.0
		soil.coverage_values[index] = value
		soil.mask.set_pixel(index % soil.MASK_SIZE.x, index / soil.MASK_SIZE.x, Color(value, value, value))
		soil.surface_coverage_total += value
	soil.mask_changed = true
	soil.request_render()
	soil._process(0.0)
	game.update_contract_status()

func capture(label: String) -> void:
	if "--carpet-video-capture" not in OS.get_cmdline_user_args(): return
	await frames()
	var path := "res://../art/renders/carpet_video_" + label + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "Capture actual paid UI " + label)

func run() -> void:
	state = root.get_node("ShopState")
	save_path = "res://.godot/carpet_video_flow_%d.json" % OS.get_process_id()
	state._save_path = save_path
	state.set_process(false)
	state._test_ticks_msec = 0
	state._last_ticks = 0
	state._test_unix_time = 1800000000.0
	check(state.reset_progress(), "Reset a disposable save")
	root.size = Vector2i(390, 844)
	await enter()
	var ad: Button = game.hud.control("AdRewardButton")
	check(ad.visible and ad.disabled and game.hud._carpet_ad_state == HUD.CarpetAdState.LOCKED, "No provider shows a locked video button without inventing an ad")
	cleanliness(0.75)
	check(game.finish_button.visible and game.finish_button.text == "Finish" and game.finish_button.tooltip_text == "Finish this carpet", "Finish never carries a price, even when eligible")
	check(game._flush_cleaning_earnings(true) and state.cash == 15.0, "Real cleaning still earns its proportional part before Finish")
	await capture("locked_early")
	var provider := VideoProvider.new()
	check(state.register_reward_ad_provider(provider), "Connect only the test's verified provider")
	check(not ad.disabled and game.hud._carpet_ad_state == HUD.CarpetAdState.READY, "A ready video enables the actual carpet button")
	var job_id: String = game.contract_job_id
	ad.pressed.emit()
	check(provider.requests == 1 and provider.job == job_id, "The real button requests the carpet being cleaned")
	check(game.carpet_video_pending and game.soil.simulation_suspended and game.hud._wallet_paused, "The video pauses dirt, input and wallet presentation together")
	check(not game.finish_button.visible and ad.disabled and not game._can_purchase(), "Finish and purchases wait for the pending video")
	game.begin_stroke(game.camera.unproject_position(Vector3.ZERO), false)
	game.finish_rug()
	check(not game.brush_dragging and state.manual_jobs == 0 and state.cash == 15.0, "Pending video cannot clean or finish the carpet")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(0.30).timeout
	check(game.soil.simulation_suspended and game.hud._wallet_paused and state.cash == 15.0, "Focus return cannot resume a video still awaiting verification")
	provider.finish("completed", "carpet-video-flow-early")
	check(not game.carpet_video_pending and not game.soil.simulation_suspended and not game.hud._wallet_paused, "Verified completion restores the cleaning clocks")
	check(state.cash == 30.0 and state.current_job_full_reward() == 80.0 and state._branch().job_cleaning_paid == 30.0, "Video doubles previously earned cleaning once and the current carpet quote")
	check(game.hud._carpet_ad_state == HUD.CarpetAdState.ACTIVE and ad.disabled and game.hud.control("CarpetEarningsValue").text == "80", "The same carpet visibly shows its active doubled quote")
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	check(disk is Dictionary and float(disk.cash) == 30.0 and disk.stores["1"].job_ad_boost == true and float(disk.stores["1"].job_cleaning_paid) == 30.0, "The verified video and retroactive money are durably saved together")
	provider.finish("completed", "carpet-video-flow-early")
	check(state.cash == 30.0 and provider.requests == 1, "A replayed video callback cannot pay again")
	await create_timer(0.30).timeout
	check(game.hud.displayed_gold == 30.0 and game.hud.pending_reward == 0.0, "The video top-up uses the live wallet count-up and settles cleanly")
	await capture("active_early")
	game.finish_rug()
	check(state.cash == 40.0 and state.completed_rewards[job_id].amount == 40.0 and state.completed_rewards[job_id].ad_claimed, "Boosted early Finish totals forty and cannot sell another completed-carpet boost")
	check(game.hud.control("CarpetEarningsValue").text == "80", "The completed carpet keeps its doubled quote during suction")
	await leave()
	await enter()
	ad = game.hud.control("AdRewardButton")
	check(state.current_job_full_reward() == 40.0 and not state._branch().job_ad_boost and game.hud._carpet_ad_state == HUD.CarpetAdState.READY, "A new carpet starts with its own unboosted quote")
	cleanliness(0.50)
	check(game._flush_cleaning_earnings(true) and state.cash == 50.0, "A second carpet earns its own normal cleaning share")
	ad.pressed.emit()
	provider.finish("skipped", "carpet-video-flow-skipped")
	check(state.cash == 50.0 and state.current_job_full_reward() == 40.0 and not game.carpet_video_pending and not game.soil.simulation_suspended, "Skipping a video resumes work with no boost or extra money")
	ad.pressed.emit()
	cleanliness(0.99)
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	provider.finish("completed", "carpet-video-flow-full")
	check(state.cash == 60.0 and state.current_job_full_reward() == 80.0, "A later verified attempt doubles the second carpet once")
	await frames()
	check(state.manual_jobs == 1 and not game.finish_requested and not game.auto_finish_queued and game.soil.simulation_suspended and game.hud._wallet_paused, "A video result received in the background preserves the ready carpet and paused clocks")
	game.finish_rug()
	check(state.manual_jobs == 1 and state.cash == 60.0 and not game.finish_requested, "A background finish call cannot settle or animate the carpet")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(game.auto_finish_queued and not game.soil.simulation_suspended and not game.hud._wallet_paused, "Focus return resumes completion eligibility and presentation")
	check(game._flush_cleaning_earnings(true) and state.cash == 80.0, "The boosted cleaning half reaches exactly forty on the second carpet")
	game.finish_rug()
	check(state.cash == 120.0 and state.manual_jobs == 2, "A full boosted carpet totals eighty, separate from the prior forty early finish")
	await leave()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("CARPET_VIDEO_FLOW_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
