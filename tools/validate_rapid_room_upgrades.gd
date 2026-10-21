extends SceneTree
## Real floating touch purchases during continuous, retriggered room feedback.
## Requires -- --shop-test; optional --rapid-upgrade-capture renders pop phases.

const ROOM := preload("res://scripts/room_upgrades.gd")
const MONEY := preload("res://scripts/money.gd")
const WORKSHOP := preload("res://scenes/production/rug_cleaning.tscn")

var checks := 0
var failures := 0
var ledger: Node
var game: Node
var room: Node3D
var save_path := ""
var completed: Dictionary = {}
var effects: Dictionary = {}
var original_rug: Dictionary = {}
var original_job := ""


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Rapid room upgrade validation requires -- --shop-test to protect player progress.")
		quit(2)
		return
	call_deferred("run")


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("RAPID_ROOM: " + description)


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


func button() -> Button:
	return game.hud.room_panel.get_node("%Buy") as Button


func visible_model(id: String) -> Node3D:
	return room.get_node("%s/Tier%d" % [room.GROUP_NAMES[id], int(room.visual_tiers[id])]) as Node3D


func advance_feedback(seconds: float) -> void:
	# The production animation update advances every active category. Keeping
	# the automatic callback off makes the elapsed tap spacing reproducible.
	room.set_process(false)
	var remaining := seconds
	while remaining > 0.00001:
		var delta := minf(remaining, 1.0 / 120.0)
		room._process_upgrades(delta)
		remaining -= delta


func assert_saved(id: String, level: int, cash: float) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	check(parsed is Dictionary, "Each " + id + " tap commits a readable isolated save")
	if parsed is Dictionary:
		check(int(parsed.stores["1"].room_upgrades[id]) == level and float(parsed.cash) == cash,
			"Each %s level%d persists the exact new level and charged wallet" % [id, level])


func assert_next_quote(id: String) -> void:
	var quote: Dictionary = ledger.room_upgrade_view(id)
	var panel: Control = game.hud.room_panel
	check(int(panel.offer.level) == int(quote.level) and float(panel.offer.cost) == float(quote.cost),
		id + " refreshes the current level and next price before another frame")
	check(button().text.contains(MONEY.format(float(quote.cost))), id + " labels its latest independent price")
	check(not button().disabled, id + " leaves its affordable native Upgrade button enabled during VFX")
	var counter := "%d / %d" % [int(quote.level), int(quote.max_level)] if int(quote.next_visual_level) < 0 else "%d / %d" % [int(quote.level) - ROOM.milestone_start(id, int(quote.level), ledger.active_store), int(quote.visual_step)]
	check(panel.get_node("%ProgressState").text == counter,
		id + " refreshes its transformation step immediately")
	check(panel.get_node("%CleanValue").text == "%s → %s" % [MONEY.format(float(quote.full_reward)), MONEY.format(float(quote.next_full))],
		id + " refreshes current and next carpet pay with the purchase")


func assert_effect_reused(id: String) -> void:
	var effect: Node3D = room.upgrade_effects[id]
	check(effect.get_instance_id() == int(effects[id].node) and effect.ring.get_instance_id() == int(effects[id].ring)
		and effect.pillar.get_instance_id() == int(effects[id].pillar), id + " reuses its one ring and pillar for every tap")
	check(room.upgrade_effects.size() == ROOM.IDS.size() and effect.get_child_count() == 2,
		id + " keeps the effect pool bounded under repeated purchases")
	check(effect.visible and float(effect.opacity) > 0.0, id + " keeps the glow visible between rapid taps")
	var model := visible_model(id)
	var dimensions: Vector3 = room.upgrade_scale(id)
	check(model.transform.is_finite() and dimensions.x > 0.75 and dimensions.x < 1.25 and dimensions.y > 0.75
		and dimensions.y < 1.25 and dimensions.z > 0.75 and dimensions.z < 1.25,
		id + " has finite, bounded pop deformation without compounded growth")


func buy_rapid(id: String, expected_level: int) -> void:
	var before: Dictionary = ledger.room_upgrade_levels().duplicate(true)
	var offer: Dictionary = ledger.room_upgrade_view(id)
	var cash_before: float = ledger.cash
	var model := visible_model(id)
	var before_transform := model.transform
	var before_scale: Vector3 = room.upgrade_scale(id)
	var effect: Node3D = room.upgrade_effects[id]
	var was_active: bool = room.is_upgrade_active(id)
	var opacity_before: float = effect.opacity
	var pillar_scale: Vector3 = effect.pillar.scale
	var ring_scale: Vector3 = effect.ring.scale
	var point := button().get_global_rect().get_center()
	touch(point, true)
	check(ledger.cash == cash_before and ledger.room_upgrade_levels() == before, id + " press waits for touch release")
	touch(point, false)
	room.set_process(false)
	check(int(ledger.room_upgrade_levels()[id]) == expected_level and ledger.cash == cash_before - float(offer.cost),
		"Rapid %s tap%d buys exactly one new level at the displayed price" % [id, expected_level])
	for other: String in ROOM.IDS:
		if other != id:
			check(int(ledger.room_upgrade_levels()[other]) == int(before[other]), "Rapid " + id + " purchase preserves the " + other + " ladder")
	check(ledger.reward_for_current_job({"unique_clearance": 1.0, "surface_clearance": 1.0}) == float(offer.next_full),
		id + " applies its quoted income immediately to the live carpet")
	check(room.is_upgrade_active(id) and int(completed.get(id, 0)) == 0,
		id + " restarts its quiet timeout without finishing between continued taps")
	if was_active:
		check(model.visible and model.transform.is_equal_approx(before_transform) and room.upgrade_scale(id).is_equal_approx(before_scale), id + " retrigger preserves the displayed model pose synchronously")
		check(effect.opacity == opacity_before and effect.pillar.scale == pillar_scale and effect.ring.scale == ring_scale,
			id + " retrigger preserves visible glow brightness and geometry synchronously")
	assert_next_quote(id)
	assert_saved(id, expected_level, ledger.cash)
	advance_feedback(0.06)
	check(not room.upgrade_scale(id).is_equal_approx(before_scale), id + " gives the new tap a visible fresh pop")
	assert_effect_reused(id)
	if expected_level - ROOM.milestone_start(id, expected_level, ledger.active_store) >= 3:
		check(int(room.visual_tiers[id]) == ROOM.visual_tier(id, expected_level, ledger.active_store), id + " swaps its latest milestone without waiting for taps to stop")


func capture(label: String) -> void:
	if "--rapid-upgrade-capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../art/renders")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join("rapid_upgrade_" + label + ".png")) == OK, "Capture saves " + label)


func validate_bursts() -> void:
	for id: String in ROOM.IDS:
		var point: Vector2 = game.camera.unproject_position(room.anchor_world(id))
		check(room.pick_upgrade(game.camera, point) == id, id + " remains tappable in the workshop")
		tap(point)
		await settle()
		check(game.hud.room_panel.visible and game.hud.room_panel.selected_id == id, "A real " + id + " touch opens its own floating offer")
		for level: int in range(1, 22):
			buy_rapid(id, level)
		# Twenty-one clicks span 1.26 seconds: longer than the old 0.90-second
		# effect, but never with enough quiet time for the pulse to finish.
		check(room.is_upgrade_active(id) and int(completed.get(id, 0)) == 0, id + " sustains feedback through 21 rapid touches")
		advance_feedback(0.13)
		check(int(room.visual_tiers[id]) == ROOM.visual_tier(id, 21, ledger.active_store),
			id + " displays its earned authored makeover during a continued upgrade run")
		if id == "plants" or id == "walls":
			await capture(id + "_burst")
		tap(game.hud.room_panel.get_node("%Close").get_global_rect().get_center())
		check(not game.hud.upgrades_open() and room.is_upgrade_active(id), "Closing " + id + " resumes rug input while its VFX continues")
		check(not game.soil.simulation_suspended and not game.brush_dragging, "Closing " + id + " cannot turn the close gesture into a stroke")
		room.set_process(false)
	# The last active category does not finish before the last tap's timeout.
	advance_feedback(0.60)
	check(room.is_upgrade_active("walls"), "The final wall feedback remains active before its final quiet timeout")
	advance_feedback(0.20)
	check(not room.is_upgrade_active(), "All rapid upgrade animations eventually settle after the final tap")
	for id: String in ROOM.IDS:
		check(int(completed.get(id, 0)) == 1, id + " emits one completion for its whole continuous burst")
		check(not room.upgrade_effects[id].visible and float(room.upgrade_effects[id].opacity) == 0.0, id + " releases its reusable effect at rest")
		for tier: int in range(4):
			var key := "%s/Tier%d" % [room.GROUP_NAMES[id], tier]
			check((room.get_node(key) as Node3D).transform.is_equal_approx(room._tier_transforms[key]), id + " tier%d restores its exact authored transform" % tier)
	check(game.soil.make_snapshot() == original_rug and ledger.active_job_id == original_job,
		"All 105 rapid purchases, milestone swaps and modal switches preserve the live carpet and its genuine dirt")


func deformation_scale(id: String) -> Vector3:
	return room.upgrade_scale(id)


func validate_visual_phases() -> void:
	if "--rapid-upgrade-capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	for id: String in ["plants", "window"]:
		game.open_room_upgrade(id)
		await settle()
		tap(button().get_global_rect().get_center())
		room.set_process(false)
		advance_feedback(0.60)
		# Sustain the pillar beyond the first pulse, then capture a new impulse
		# in isolation rather than conflating it with that pulse's wider phase.
		tap(button().get_global_rect().get_center())
		room.set_process(false)
		advance_feedback(0.40)
		var current_pose := deformation_scale(id)
		tap(button().get_global_rect().get_center())
		room.set_process(false)
		check(deformation_scale(id).is_equal_approx(current_pose) and not button().disabled,
			id + " visual retrigger starts from its current pose with the next purchase enabled")
		await capture(id + "_current_pose")
		advance_feedback(0.10)
		var tall_pose := deformation_scale(id)
		check(tall_pose.y > current_pose.y and tall_pose.x < current_pose.x and not button().disabled,
			id + " fresh retrigger grows tall and narrows while Upgrade stays enabled")
		await capture(id + "_tall")
		advance_feedback(0.30)
		var wide_pose := deformation_scale(id)
		check(wide_pose.x > tall_pose.x and wide_pose.y < tall_pose.y and not button().disabled,
			"%s fresh retrigger returns through a wider pop while Upgrade stays enabled (start%s tall%s wide%s disabled%s)" % [id, current_pose, tall_pose, wide_pose, button().disabled])
		await capture(id + "_wide")
		advance_feedback(0.55)
		tap(game.hud.room_panel.get_node("%Close").get_global_rect().get_center())


func validate_gates() -> void:
	game.open_room_upgrade("floor")
	await settle()
	var before: Dictionary = ledger._capture_state()
	var point := button().get_global_rect().get_center()
	touch(point, true)
	touch(point, false, true)
	check(ledger._capture_state() == before and not room.is_upgrade_active("floor"), "Canceled native Upgrade touch spends nothing and starts no pop")
	var quote: Dictionary = ledger.room_upgrade_view("floor")
	ledger.cash = float(quote.cost) - 1.0
	ledger.changed.emit()
	before = ledger._capture_state()
	check(button().disabled, "Insufficient funds still disable Upgrade without an animation lock")
	tap(button().get_global_rect().get_center())
	check(ledger._capture_state() == before, "Repeated unaffordable Upgrade touches preserve money and levels")
	ledger.cash = 1000000000.0
	ledger.changed.emit()
	game.hud.reserve_reward(40.0)
	# The actual payout transaction emits the ledger change immediately after
	# reserving its flights, which refreshes the selected offer's availability.
	ledger.changed.emit()
	before = ledger._capture_state()
	check(button().disabled and not game._can_purchase(), "Incoming reserved coin flights still gate real purchases")
	tap(button().get_global_rect().get_center())
	check(ledger._capture_state() == before, "Upgrade cannot spend coins while a reward is visually reserved")
	game.hud.cancel_reserved_reward(40.0)
	ledger.changed.emit()
	check(not button().disabled and game._can_purchase(), "Clearing the last reserved coin immediately restores an affordable Upgrade")
	# A real write failure rolls back and must not start or retrigger feedback.
	var good_path: String = ledger._save_path
	ledger._save_path = good_path + "/cannot-write.json"
	before = ledger._capture_state()
	tap(button().get_global_rect().get_center())
	room.set_process(false)
	check(ledger._capture_state() == before and not room.is_upgrade_active("floor"), "Failed durable save leaves the wallet, quote, levels and VFX unchanged")
	check(game.hud.room_panel.get_node("%Status").text.contains("Couldn't save"), "Failed save reports unchanged coins in the floating offer")
	ledger._save_path = good_path
	ledger.changed.emit()
	quote = ledger.room_upgrade_view("floor")
	var wallet: float = ledger.cash
	tap(button().get_global_rect().get_center())
	room.set_process(false)
	check(int(ledger.room_upgrade_levels().floor) == 22 and ledger.cash == wallet - float(quote.cost), "Restoring writes allows exactly one immediate retry")
	advance_feedback(0.08)
	# A failing rapid tap must leave the earlier paid pulse running unchanged.
	before = ledger._capture_state()
	var running_animation: Dictionary = room._upgrade_animations.floor.duplicate(true)
	var running_pose: Transform3D = visible_model("floor").transform
	var running_opacity: float = room.upgrade_effects.floor.opacity
	ledger._save_path = good_path + "/cannot-write.json"
	tap(button().get_global_rect().get_center())
	room.set_process(false)
	check(ledger._capture_state() == before and room.is_upgrade_active("floor"), "Failed rapid save preserves the earlier paid purchase and its running pulse")
	check(room._upgrade_animations.floor == running_animation and visible_model("floor").transform == running_pose
		and room.upgrade_effects.floor.opacity == running_opacity, "Failed rapid save neither cancels nor retriggers the existing pose and glow")
	check(game.hud.room_panel.get_node("%Status").text.contains("Couldn't save"), "Failed rapid save reports unchanged coins during existing VFX")
	ledger._save_path = good_path
	ledger.changed.emit()
	tap(game.hud.room_panel.get_node("%Close").get_global_rect().get_center())
	game.open_room_upgrade("plants")
	await settle()
	check(room.is_upgrade_active("floor") and not button().disabled, "Another object's running VFX cannot lock the new selected offer")
	quote = ledger.room_upgrade_view("plants")
	wallet = ledger.cash
	tap(button().get_global_rect().get_center())
	room.set_process(false)
	check(room.is_upgrade_active("floor") and room.is_upgrade_active("plants") and ledger.cash == wallet - float(quote.cost),
		"Two independently selected objects can animate and commit purchases concurrently")
	advance_feedback(0.95)
	tap(game.hud.room_panel.get_node("%Close").get_global_rect().get_center())
	# The actual cap remains the limit even with large routine-cleaning funds.
	var branch: Dictionary = ledger._branch()
	var cap := ROOM.Progression.room_level_cap(ledger.active_store)
	branch.room_upgrades.walls = cap - 1
	branch.payout_level = ROOM.total_levels(branch.room_upgrades)
	ledger.cash = 1000000000.0
	check(ledger.save_state(), "Final-level fixture saves the first store's actual bounded progress")
	ledger.changed.emit()
	game.open_room_upgrade("walls")
	await settle()
	quote = ledger.room_upgrade_view("walls")
	wallet = ledger.cash
	tap(button().get_global_rect().get_center())
	room.set_process(false)
	check(int(ledger.room_upgrade_levels().walls) == cap and ledger.cash == wallet - float(quote.cost), "The true final wall upgrade is bought exactly once")
	check(room.is_upgrade_active("walls") and button().disabled and button().text == "Fully upgraded", "The store's actual cap disables another purchase immediately while its VFX runs")
	before = ledger._capture_state()
	for _repeat in 5:
		tap(button().get_global_rect().get_center())
	check(ledger._capture_state() == before, "Rapid final-level touches cannot exceed the store cap or spend extra money")
	advance_feedback(0.95)
	check(int(room.levels.walls) == cap and int(room.visual_tiers.walls) == ROOM.visual_count("walls") and game.hud.room_panel.get_node("%ProgressState").text == "Fully upgraded",
		"The final income upgrade retains the last authored mesh and completes at its actual cap")
	tap(game.hud.room_panel.get_node("%Close").get_global_rect().get_center())
	check(game.soil.make_snapshot() == original_rug and ledger.active_job_id == original_job, "All blocked/retried purchases preserve the live carpet")


func set_completion_fixture(id: String, level: int) -> void:
	var branch: Dictionary = ledger._branch()
	branch.room_upgrades[id] = level
	branch.payout_level = ROOM.total_levels(branch.room_upgrades)
	ledger.cash = 1000000000.0
	check(ledger.save_state(), "%s completion fixture saves its real level%d" % [id, level])
	ledger.changed.emit()
	room.set_process(false)


func validate_completion_progress() -> void:
	var cap := ROOM.Progression.room_level_cap(ledger.active_store)
	var panel: Control = game.hud.room_panel
	for id: String in ROOM.IDS:
		var milestones := ROOM.visual_milestones(id, ledger.active_store)
		var last := milestones[-1]
		check(last < cap, id + " first-store fixture leaves income upgrades after its last visual makeover")
		set_completion_fixture(id, last - 1)
		game.open_room_upgrade(id)
		await settle()
		var quote: Dictionary = ledger.room_upgrade_view(id)
		var wallet: float = ledger.cash
		tap(button().get_global_rect().get_center())
		room.set_process(false)
		check(int(ledger.room_upgrade_levels()[id]) == last and ledger.cash == wallet - float(quote.cost),
			id + " buys its last authored makeover once at the quoted price")
		check(panel.get_node("%ProgressState").text == "%d / %d" % [last, cap]
			and not button().disabled and button().text != "Fully upgraded",
			id + " last visual makeover immediately shows its remaining upgrade levels")
		await create_timer(0.3).timeout
		check(absf(panel.get_node("%TransformationProgress").value - float(last) / float(cap)) < 0.005,
			id + " last visual makeover keeps its displayed progress bar incomplete")
		advance_feedback(0.95)
		check(int(room.visual_tiers[id]) == ROOM.visual_count(id), id + " reaches its final authored look before full upgrade completion")
		quote = ledger.room_upgrade_view(id)
		wallet = ledger.cash
		tap(button().get_global_rect().get_center())
		room.set_process(false)
		check(int(ledger.room_upgrade_levels()[id]) == last + 1 and ledger.cash == wallet - float(quote.cost)
			and panel.get_node("%ProgressState").text == "%d / %d" % [last + 1, cap] and not button().disabled,
			id + " continues its real income upgrades after the last makeover")
		advance_feedback(0.95)
		set_completion_fixture(id, cap - 1)
		check(panel.get_node("%ProgressState").text == "%d / %d" % [cap - 1, cap] and not button().disabled,
			id + " penultimate level keeps the final upgrade available")
		quote = ledger.room_upgrade_view(id)
		wallet = ledger.cash
		tap(button().get_global_rect().get_center())
		room.set_process(false)
		check(int(ledger.room_upgrade_levels()[id]) == cap and ledger.cash == wallet - float(quote.cost)
			and panel.get_node("%ProgressState").text == "Fully upgraded" and button().disabled and button().text == "Fully upgraded",
			id + " completes only when its final real upgrade is purchased")
		var before: Dictionary = ledger._capture_state()
		tap(button().get_global_rect().get_center())
		check(ledger._capture_state() == before, id + " completed offer prevents any extra spend")
		advance_feedback(0.95)
		await create_timer(0.3).timeout
		check(panel.get_node("%TransformationProgress").value == 1.0, id + " real cap fills its displayed progress bar")
		tap(panel.get_node("%Close").get_global_rect().get_center())
	check(game.soil.make_snapshot() == original_rug and ledger.active_job_id == original_job,
		"All five completion transitions preserve the live carpet and its current job")


func run() -> void:
	ledger = root.get_node("ShopState")
	ledger.set_process(false)


	save_path = ProjectSettings.globalize_path("res://.godot/rapid_room_test_%d.json" % OS.get_process_id())
	ledger._save_path = save_path
	check(ledger.reset_progress(), "Rapid upgrade validation uses its own isolated save")
	ledger.cash = 1000000000.0
	check(ledger.save_state(), "Rapid touch fixtures save independent funds")
	root.size = Vector2i(390, 844)
	game = WORKSHOP.instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await settle()
	check(game.paid_contract and game.rug_phase == game.RugPhase.CLEANING, "The real paid production scene is ready for rapid room purchases")
	room = game.room
	room.set_process(false)
	room.upgrade_finished.connect(func(id: String): completed[id] = int(completed.get(id, 0)) + 1)
	for id: String in ROOM.IDS:
		var effect: Node3D = room.upgrade_effects[id]
		effects[id] = {"node": effect.get_instance_id(), "ring": effect.ring.get_instance_id(), "pillar": effect.pillar.get_instance_id()}
	original_rug = game.soil.make_snapshot()
	original_job = ledger.active_job_id
	await validate_bursts()
	await validate_visual_phases()
	await validate_gates()
	await validate_completion_progress()
	game.free()
	current_scene = null
	var audio := root.get_node_or_null("GameAudio")
	if audio != null:
		audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	DirAccess.remove_absolute(save_path)
	print("RAPID_ROOM_UPGRADE_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
