extends SceneTree
## Real brush extraction, retained debris, atomic payment and completion.
## Run with a renderer, the pinned Mono wrapper and -- --shop-test.
const Routes := preload("res://scripts/scene_routes.gd")
const Rules := preload("res://scripts/progression.gd")
const Room := preload("res://scripts/room_upgrades.gd")
var checks := 0
var failures := 0
var state: Node
var game: Node
var save_path := ""
var observed_cash := 0.0
var observed_jobs := 0
var payment_commits := 0
var freeze_dirt_physics := false

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Incremental cleaning validation requires a renderer and -- --shop-test")
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("INCREMENTAL CLEANING: " + message)

func frames(count: int = 2) -> void:
	for _step in count:
		await process_frame
		await RenderingServer.frame_post_draw

func capture(label: String) -> void:
	if "--incremental-capture" not in OS.get_cmdline_user_args(): return
	await frames()
	var path := "res://../art/renders/incremental_cleaning_" + label + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "Save actual renderer capture " + label)

func observe_save() -> void:
	if state.cash > observed_cash:
		payment_commits += 1
		var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		check(disk is Dictionary and is_equal_approx(float(disk.get("cash", -1)), state.cash), "Every wallet increase already exists in the same durable save")
		if state.manual_jobs == observed_jobs:
			check(not state.job_snapshot.is_empty() and disk.job_snapshot.get("coverage") == state.job_snapshot.get("coverage"), "A cleaning payment durably saves its actual coverage mask together with cash")
			check(is_equal_approx(float(disk.job_snapshot.get("earned_clearance", -1)), float(state.job_snapshot.get("earned_clearance", -2))), "A cleaning payment and its eligible progress watermark commit atomically")
	observed_cash = state.cash
	observed_jobs = state.manual_jobs

func enter_paid() -> void:
	game = load(Routes.CLEANING).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frames()
	game.animate_rug_changes = true
	check(game.rug_phase == game.RugPhase.CLEANING and game.paid_contract, "Production starts with the saved paid carpet ready")

func leave_game() -> void:
	game.free()
	current_scene = null
	game = null
	await frames()

func stroke(a: Vector3, b: Vector3) -> void:
	game.soil.end_pass()
	game.apply_selected_tool_stroke(a, b, 0.08)
	if freeze_dirt_physics: game.soil.set_physics_process(false)
	game.soil._process(0.0)

func set_cleanliness(clearance: float) -> void:
	# Threshold fixtures follow the real extraction/retained-debris checks below.
	# Keep the full snapshot valid: every original debris ID is retired once.
	var soil: Node = game.soil
	soil.active.clear()
	soil.timed_debris.clear()
	soil.floor_debris.clear()
	soil.free_slots.assign(range(soil.initial.size()))
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
	soil.end_pass()
	soil.surface_coverage_total = 0.0
	var residue := 1.0 - clearance
	for index in soil.coverage_values.size():
		var value: float = residue if soil.surface_pixels[index] == 1 else 0.0
		soil.coverage_values[index] = value
		soil.mask.set_pixel(index % soil.MASK_SIZE.x, index / soil.MASK_SIZE.x, Color(value, value, value))
		soil.surface_coverage_total += value
	soil.mask_changed = true
	soil.request_render()
	soil._process(0.0)
	game.update_contract_status()

func validate_real_removal() -> void:
	var source_mask: PackedByteArray = game.soil.mask.get_data()
	var original_ids: int = game.soil.initial.size()
	check(state.current_job_full_reward() == 40.0 and state.cash == 0.0, "Starter carpet has its unchanged forty-coin full value")
	# Freeze only visual motion: production strokes, reward timer and ledger run.
	# Each contact re-enables soil physics, so the helper disables it again.
	freeze_dirt_physics = true
	game.soil.set_physics_process(false)
	for _pass_number in 3:
		for x: float in [-0.65, -0.25, 0.25, 0.65]:
			stroke(Vector3(x, 0.067, -0.80), Vector3(x, 0.067, 0.80))
	check(game.soil.mask.get_data() != source_mask and not game.soil.active.is_empty(), "Actual repeated brush passes clear the mask and launch real dirt")
	var airborne: Array = game.soil.positions.duplicate()
	check(game.soil.unique_clearance() == 0.0 and game.soil.retired_credit_count == 0 and game.soil.timed_debris.is_empty(), "Fresh extraction has not landed, crossed the carpet edge or retired a visual slot")
	check(game._flush_cleaning_earnings() and state.cash > 0.0 and state.cash <= 20.0, "Fresh surface extraction pays before any dirt landing or disappearance")
	game.hud._process(game.hud.CLEANING_COUNT_SECONDS)
	check(game.hud.displayed_gold == state.cash and game.soil.positions == airborne and game.soil.batch.visible_instance_count > 25, "The wallet count-up completes while extracted dirt remains visibly frozen at contact")
	var explicit_cash: float = state.cash
	for _pass_number in 2:
		for x: float in [-0.65, -0.25, 0.25, 0.65]:
			stroke(Vector3(x, 0.067, -0.80), Vector3(x, 0.067, 0.80))
	airborne = game.soil.positions.duplicate()
	await create_timer(game.CLEANING_REWARD_INTERVAL + game.hud.CLEANING_COUNT_SECONDS + 0.15).timeout
	check(state.cash > explicit_cash and game.hud.displayed_gold == state.cash, "The real production timer also credits and counts fresh cleaning while dirt is visible")
	check(game.soil.positions == airborne and game.soil.unique_clearance() == 0.0 and game.soil.retired_credit_count == 0, "Timer-based payment needs no physical dirt collection")
	for _pass_number in 5:
		for x: float in [-0.65, -0.25, 0.25, 0.65]:
			stroke(Vector3(x, 0.067, -0.80), Vector3(x, 0.067, 0.80))
	check(game.soil.free_slots.is_empty() and game.soil.batch.visible_instance_count == original_ids, "Repeated real extraction fills the entire fixed visual pool")
	check(game._flush_cleaning_earnings(), "Payment catches up to extracted surface work with the entire pool visible")
	var full_pool_cash: float = state.cash
	var full_pool_surface: float = game.soil.surface_clearance()
	for _pass_number in 10:
		stroke(Vector3(0, 0.067, 0.95), Vector3(0, 0.067, 1.55))
	check(game.soil.surface_clearance() > full_pool_surface and game.soil.free_slots.is_empty(), "A fresh dirty stripe still cleans when no cosmetic clump slots are available")
	check(game._flush_cleaning_earnings() and state.cash > full_pool_cash and state.cash <= 20.0, "Removing fresh dirt earns money even when the visible pool is full")
	await capture("full_pool_before_collection")
	freeze_dirt_physics = false
	game.soil.set_physics_process(true)
	await create_timer(2.3).timeout
	await frames()
	check(not game.soil.floor_debris.is_empty() and game.soil.timed_debris.is_empty() and game.soil.retired_credit_count == 0, "Gravity leaves settled dirt visible until later extraction needs its slots")
	var retained: Array = game.soil.floor_debris.duplicate()
	var retained_cash: float = state.cash
	await create_timer(0.8).timeout
	check(game.soil.floor_debris == retained and game.soil.timed_debris.is_empty() and state.cash == retained_cash, "Idle settled clumps remain on screen and elapsed time grants no extra payment")
	check(state.cash > 0.0 and state.cash <= 20.0 and state.manual_jobs == 0, "Extraction pays the cleaning half before physical job completion")
	check(game.soil.initial.size() == original_ids and game.soil.batch.instance_count == original_ids, "Incremental payment preserves the existing fixed dirt pool")
	await capture("earned_with_retained_dirt")
	# Repeat only inside the patch that the broader ten-pass sweep fully cleared.
	var before_mask: PackedByteArray = game.soil.mask.get_data()
	var cash_before: float = state.cash
	for _repeat in 5:
		stroke(Vector3(0, 0.067, -0.20), Vector3(0, 0.067, 0.20))
	await create_timer(0.8).timeout
	check(game.soil.mask.get_data() == before_mask and state.cash == cash_before, "Rebrushing an already clean patch creates neither dirt progress nor money")
	check(game._flush_cleaning_earnings() and state.cash == cash_before, "Repeated flush of the same extraction is idempotent")
	var job_id: String = game.contract_job_id
	check(game.save_contract_progress(), "Current paid mask and cleanup earnings save together")
	var paid_mask: String = state.job_snapshot.coverage
	await leave_game()
	state._load_state()
	await enter_paid()
	check(game.contract_job_id == job_id and state.cash == cash_before and state.job_snapshot.coverage == paid_mask, "Real disk reload restores the same carpet, paid watermark and wallet")
	check(not game.soil.floor_debris.is_empty() and game.soil.timed_debris.is_empty(), "JSON reload keeps settled floor dirt visible without starting an idle fade")
	check(game._flush_cleaning_earnings() and state.cash == cash_before, "Reloading the paid mask cannot pay the same extraction again")

func validate_failure_focus_and_full() -> void:
	await create_timer(0.65).timeout
	var before_cash: float = state.cash
	var before_disk := FileAccess.get_file_as_bytes(save_path)
	state._save_enabled = false
	set_cleanliness(0.65)
	check(not game._flush_cleaning_earnings() and state.cash == before_cash, "Failed payment save leaves the wallet unchanged")
	check(FileAccess.get_file_as_bytes(save_path) == before_disk and game.contract_save_failed, "Failed payment retains the previous durable wallet and mask for retry")
	state._save_enabled = true
	check(game._flush_cleaning_earnings() and state.cash == 13.0, "Retry commits only the owed progress toward the twenty-coin cleaning half")
	set_cleanliness(0.70)
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var background_cash: float = state.cash
	var background_mask: PackedByteArray = game.soil.mask.get_data()
	var background_positions: Array = game.soil.positions.duplicate()
	game.begin_stroke(game.camera.unproject_position(Vector3.ZERO), false)
	game._flush_cleaning_earnings()
	await create_timer(0.35).timeout
	check(state.cash == background_cash and game.soil.mask.get_data() == background_mask and not game.brush_dragging, "Background time and canceled input cannot earn or animate new cleaning progress (cash %s→%s, mask unchanged %s, dragging %s)" % [background_cash, state.cash, game.soil.mask.get_data() == background_mask, game.brush_dragging])
	check(game.soil.simulation_suspended and game.soil.positions == background_positions, "Focus loss suspends the soil simulation and preserves its real dirt positions")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(0.85).timeout
	check(state.cash == 14.0, "Focus return resumes the pending honest progress once")
	var completed_id: String = game.contract_job_id
	set_cleanliness(0.99)
	check(game._flush_cleaning_earnings(true) and state.cash == 20.0 and state.manual_jobs == 0, "The first half stops at twenty coins before full-restoration completion")
	var count_before: float = game.hud.displayed_gold
	game.finish_rug()
	check(state.cash == 40.0 and state.manual_jobs == 1 and state.active_job_id != completed_id, "Ninety-nine percent adds only the remaining half for exactly forty total coins")
	check(float(state.completed_rewards.get(completed_id, {}).get("amount", -1)) == 40.0, "Completion receipt records the full job value including earlier cleaning earnings")
	check(game.rug_phase == game.RugPhase.VACUUMING and game.soil.VACUUM_SECONDS == 1.8 and game.completed_reward == 0.0, "The restoration count-up starts during the existing vacuum and leaves no next-rug reward")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var paused_vacuum: float = game.soil.vacuum_elapsed
	var paused_wallet: float = game.hud.displayed_gold
	var paused_counter: float = game.hud._cleaning_count_time
	await create_timer(0.25).timeout
	check(game.soil.simulation_suspended and game.soil.vacuum_elapsed == paused_vacuum and game.hud.displayed_gold == paused_wallet and game.hud._cleaning_count_time == paused_counter and state.cash == 40.0, "Background time pauses both vacuum and restoration count-up without changing the committed reward")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(0.25).timeout
	check(game.rug_phase == game.RugPhase.VACUUMING and game.hud.displayed_gold > count_before and game.soil.vacuum_elapsed > paused_vacuum, "Focus return resumes the wallet count-up while the completed carpet is still in suction")
	await capture("restoration_during_vacuum")
	game.finish_rug()
	game.finish_rug()
	check(state.cash == 40.0 and state.manual_jobs == 1, "Repeated finish calls cannot repay cleanup or restoration")
	await create_timer(0.65).timeout
	check(game.hud.displayed_gold == 40.0 and game.hud._reserved_reward == 0.0 and game.hud.pending_reward == 0.0, "Both halves finish their count-up without stranded coin reservations")
	await leave_game()

func validate_early_and_gym() -> void:
	await enter_paid()
	var early_id: String = game.contract_job_id
	set_cleanliness(0.75)
	check(game._flush_cleaning_earnings(true) and state.cash == 55.0, "Seventy-five percent earns floor(20×.75/.99), fifteen cleanup coins")
	game.finish_rug()
	check(not game.completed_full_restore and state.cash == 60.0 and state.manual_jobs == 2, "Early finish settles the twenty-coin cleaning half without a restoration bonus")
	check(float(state.completed_rewards.get(early_id, {}).get("amount", -1)) == 20.0, "The early receipt includes earlier cleanup payments within its twenty-coin total")
	await leave_game()
	var paid_before: Dictionary = state._capture_state().duplicate(true)
	var paid_bytes := FileAccess.get_file_as_bytes(save_path)
	game = load(Routes.GYM).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frames()
	stroke(Vector3(0, 0.067, -0.8), Vector3(0, 0.067, 1.5))
	for _step in 180: game.soil._physics_process(1.0 / 60.0)
	game._flush_cleaning_earnings(true)
	check(not game.paid_contract and state._capture_state() == paid_before and FileAccess.get_file_as_bytes(save_path) == paid_bytes, "Real free Gym extraction and dirt motion leave the paid wallet and save untouched")
	await leave_game()

func validate_dry_mask_roundtrip() -> void:
	check(state.reset_progress(), "The dry mask rounding regression uses a fresh isolated ledger")
	var branch: Dictionary = state._branch()
	for id: String in Room.IDS: branch.room_upgrades[id] = Rules.room_level_cap(1)
	branch.payout_level = Room.total_levels(branch.room_upgrades)
	check(state.save_state(), "The maximum starter-shop quote uses valid saved room levels")
	await enter_paid()
	check(state.current_job_full_reward() == 400000.0, "The real maximum starter-shop quote exposes a one-coin rounding boundary")
	freeze_dirt_physics = true
	game.soil.set_physics_process(false)
	var soil: Node = game.soil
	# Use genuine L8-representable coverage plus a tiny sub-byte remainder.
	# Saving drops only that remainder and raises surface clearance across the
	# 55,952-coin boundary, although the player has performed no further work.
	var original_clearance := 0.27696009226312
	var desired_restored_clearance := 0.27696268773943
	var count: int = soil.surface_pixel_count
	var higher_pixels := roundi(((1.0 - desired_restored_clearance) * 255.0 - 184.0) * count)
	var restored_clearance := 1.0 - float(184 * count + higher_pixels) / (255.0 * count)
	var sub_byte_remainder := restored_clearance - original_clearance
	check(sub_byte_remainder > 0.0 and sub_byte_remainder < 0.5 / 255.0, "The mask fixture rounds upward without changing its saved coverage bytes")
	soil.surface_coverage_total = 0.0
	var written := 0
	for index in soil.coverage_values.size():
		var value := 0.0
		if soil.surface_pixels[index] == 1:
			value = float(185 if written < higher_pixels else 184) / 255.0 + sub_byte_remainder
			written += 1
			soil.surface_coverage_total += value
		soil.coverage_values[index] = value
		soil.mask.set_pixel(index % soil.MASK_SIZE.x, index / soil.MASK_SIZE.x, Color(value, value, value))
	soil.mask_changed = true
	soil._process(0.0)
	var before_roundtrip: float = soil.surface_clearance()
	check(game._flush_cleaning_earnings() and state.cash == 55951.0, "The original precise surface earns exactly 55,951 coins before any reload")
	check(is_equal_approx(float(state.job_snapshot.dry_cleaning_clearance), before_roundtrip), "The durable dry payment field records extraction before lossy mask serialization")
	var paid_cash: float = state.cash
	var paid_job: String = game.contract_job_id
	var paid_progress: float = state._branch().job_cleaning_progress
	await leave_game()
	state._load_state()
	await enter_paid()
	game.soil.set_physics_process(false)
	check(game.soil.surface_clearance() > before_roundtrip and state._cleaning_target(game.soil.surface_clearance()) == 55952.0, "The real JSON/L8 roundtrip raises the live mask above the next coin boundary")
	check(game.contract_job_id == paid_job and state.cash == paid_cash and state._branch().job_cleaning_progress == paid_progress, "Restoring the quantized mask preserves the paid wallet and its exact watermark")
	check(game._flush_cleaning_earnings() and game._flush_cleaning_earnings() and state.cash == paid_cash, "Repeated reload payment flushes cannot grant the one coin created by mask rounding")
	await create_timer(game.CLEANING_REWARD_INTERVAL + 0.15).timeout
	check(state.cash == paid_cash and float(state.job_snapshot.dry_cleaning_clearance) <= before_roundtrip + 1e-12, "The real timer also leaves idle restored mask rounding unpaid")
	stroke(Vector3(0, 0.067, -0.8), Vector3(0, 0.067, 0.8))
	check(game._flush_cleaning_earnings() and state.cash > paid_cash, "Fresh real extraction after the quantized restore still earns new cleaning coins")
	var fresh_cash: float = state.cash
	var fresh_earned: float = state.job_snapshot.dry_cleaning_clearance
	await leave_game()
	state._load_state()
	await enter_paid()
	game.soil.set_physics_process(false)
	check(game._flush_cleaning_earnings() and state.cash == fresh_cash and float(state.job_snapshot.dry_cleaning_clearance) <= fresh_earned + 1e-12, "A second save/reload preserves the new extraction without paying either rounding remainder again")
	freeze_dirt_physics = false
	await leave_game()

func run() -> void:
	state = root.get_node("ShopState")
	save_path = "res://../art/incremental_cleaning_test_%d.json" % OS.get_process_id()
	state._save_path = save_path
	state.set_process(false)
	state._test_unix_time = 1500000000.0
	state._test_ticks_msec = 0
	state._last_ticks = 0
	check(state.reset_progress(), "Use an isolated incremental-cleaning save")
	state.changed.connect(observe_save)
	root.size = Vector2i(390, 844)
	await enter_paid()
	await validate_real_removal()
	await validate_failure_focus_and_full()
	await validate_early_and_gym()
	await validate_dry_mask_roundtrip()
	check(payment_commits >= 4, "Several real payment transactions exercised atomic wallet and mask observations")
	state.changed.disconnect(observe_save)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("INCREMENTAL_CLEANING_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
