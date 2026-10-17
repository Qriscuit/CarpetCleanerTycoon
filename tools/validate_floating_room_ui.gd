extends SceneTree
## Exercise the real floating room offers, pointer routing and responsive layouts.
## Requires -- --shop-test; add --floating-capture with the graphical renderer.

const IDS := ["floor", "plants", "window", "railings"]
const ROOM_RULES := preload("res://scripts/room_upgrades.gd")
const PROGRESSION := preload("res://scripts/progression.gd")
var game: Node
var ledger: Node
var checks := 0
var failures := 0


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Floating UI validation requires -- --shop-test")
		quit(2)
		return
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


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


func drag(point: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = point
	event.relative = relative
	root.push_input(event, true)


func capture(label: String) -> void:
	if "--floating-capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../art/renders")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join("floating_" + label + ".png")) == OK, "Capture saved: " + label)


func assert_offer_layout(id: String, expected_anchor: Vector2, description: String) -> void:
	var panel: Control = game.hud.room_panel
	var card: Control = panel.get_node("%Card")
	var safe: Rect2 = game.hud._safe_rect()
	check(panel.visible and panel.selected_id == id, description + ": the selected feature is identified")
	check(safe.grow(0.5).encloses(card.get_global_rect()), description + ": offer stays inside the safe display")
	var rendered_anchor: Vector2 = panel.get_global_transform() * panel.anchor_point
	check(rendered_anchor.distance_to(expected_anchor) < 2.0, description + ": offer stays attached to the selected item")
	var edge_point := Vector2(clampf(expected_anchor.x, card.get_global_rect().position.x, card.get_global_rect().end.x), clampf(expected_anchor.y, card.get_global_rect().position.y, card.get_global_rect().end.y))
	check(edge_point.distance_to(expected_anchor) <= 96.0, description + ": offer sits near its item")
	for button: Button in panel.action_buttons():
		check(safe.grow(0.5).encloses(button.get_global_rect()), description + ": action stays reachable")
		check(minf(button.get_global_rect().size.x, button.get_global_rect().size.y) >= 43.5, description + ": action keeps a finger-sized target")
		var physical_size: Vector2 = button.get_global_rect().size * Vector2(root.size) / root.get_visible_rect().size
		check(minf(physical_size.x, physical_size.y) >= 43.5, description + ": action remains at least 44 physical pixels")
	var scroll_rect: Rect2 = panel.get_node("%Scroll").get_global_rect()
	for label_name: String in ["%CleanValue", "%Status"]:
		var detail := panel.get_node(label_name) as Label
		if detail.is_visible_in_tree():
			check(scroll_rect.grow(0.5).encloses(detail.get_global_rect()), "%s: %s fits without scrolling (%s inside %s)" % [description, label_name, detail.get_global_rect(), scroll_rect])
	var bar := panel.get_node("%TransformationProgress") as ProgressBar
	check(bar.min_value == 0.0 and bar.max_value == 1.0 and bar.value >= 0.0 and bar.value <= 1.0, description + ": transformation bar stays normalized")
	check(bar.custom_minimum_size.y == 28.0 and bar.size.y >= 28.0, description + ": transformation bar has a taller 28-pixel track")
	check(scroll_rect.grow(0.5).encloses(bar.get_global_rect()), description + ": transformation bar fits without scrolling")
	var counter := panel.get_node("%ProgressState") as Label
	check(bar.get_global_rect().grow(0.5).encloses(counter.get_global_rect()) and counter.get_global_rect().get_center().distance_to(bar.get_global_rect().get_center()) < 0.5, description + ": upgrade count is centered inside the bar")
	check(card.get_global_rect().size.y <= 360.0, description + ": offer remains a compact floating card")


func assert_transformation_progress(completed_steps: int, description: String) -> void:
	var offer: Dictionary = game.hud.room_panel.offer
	var id: String = game.hud.room_panel.selected_id
	var store_id := int(ledger.active_store)
	var level := int(offer.level)
	var next := ROOM_RULES.next_visual_level(id, level, store_id)
	var previous := ROOM_RULES.milestone_start(id, level, store_id)
	var segment := maxi(1, next - previous)
	var cap := PROGRESSION.room_level_cap(store_id)
	var maxed := level >= cap
	var expected := float(level) / float(cap) if next < 0 else float(completed_steps) / float(segment)
	var bar := game.hud.room_panel.get_node("%TransformationProgress") as Range
	check(absf(bar.value - expected) < 0.015, description + ": bar shows completed upgrades toward the current target")
	var counter := "Fully upgraded" if maxed else ("%d / %d" % [level, cap] if next < 0 else "%d / %d" % [completed_steps, segment])
	check(game.hud.room_panel.get_node("%ProgressState").text == counter, description + ": counter follows its makeover segment or actual cap")


func run() -> void:
	ledger = root.get_node("ShopState")
	ledger._save_path = "res://../art/floating_room_ui_test_%d.json" % OS.get_process_id()
	check(ledger.reset_progress(), "Isolated save starts clean")
	ledger.cash = 1000
	root.content_scale_size = Vector2i(540, 750)
	root.size = Vector2i(540, 750)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await settle()
	var original: Dictionary = game.soil.make_snapshot()
	check(game.hud.room_panel.get_node_or_null("%Early") == null and game.hud.room_panel.get_node_or_null("%Full") == null and game.hud.room_panel.get_node_or_null("%Balance") == null, "Floating offer replaces the earnings table and wallet with one Clean value")
	check(game.hud.room_panel.get_node_or_null("%Milestone") == null and game.hud.room_panel.get_node_or_null("%Affordability") == null and game.hud.room_panel.get_node_or_null("Card/Frame/Scroll/Content/ProgressLabels") == null, "Floating offer removes coin-saved, ready and next-look labels")
	var card_centers: Array[Vector2] = []
	for id: String in IDS:
		var point: Vector2 = game.camera.unproject_position(game.room.anchor_world(id))
		check(game.room.pick_upgrade(game.camera, point) == id, id + " can be selected in the closer camera")
		touch(point, true)
		check(not game.hud.upgrades_open(), id + " waits for release before opening")
		touch(point, false)
		await settle()
		assert_offer_layout(id, point, "Portrait " + id)
		card_centers.append(game.hud.room_panel.get_node("%Card").get_global_rect().get_center())
		check(not game.brush_dragging and game.soil.simulation_suspended, "Opening " + id + " suspends carpet input")
		await create_timer(0.3).timeout
		assert_transformation_progress(0, "Starting " + id)
		await capture("portrait_" + id)
		if id == "floor":
			ledger.cash = 12
			ledger.changed.emit()
			await create_timer(0.3).timeout
			assert_offer_layout(id, point, "Partially funded floor")
			assert_transformation_progress(0, "Unaffordable starting floor")
			await capture("portrait_partial_funding")
			ledger.cash = 1000
			ledger.changed.emit()
			await create_timer(0.3).timeout
		var offer: Dictionary = ledger.room_upgrade_view(id)
		check(game.hud.room_panel.get_node("%CleanValue").text == "%d → %d" % [offer.full_reward, offer.next_full], "Clean previews the exact full-rug earnings increase for " + id)
		var before_cash: int = ledger.cash
		var before_level := int(offer.level)
		var buy_point: Vector2 = game.hud.room_panel.get_node("%Buy").get_global_rect().get_center()
		touch(buy_point, true)
		check(ledger.cash == before_cash, "Pressing " + id + " upgrade does not buy before release")
		touch(buy_point, false)
		await settle()
		check(ledger.cash == before_cash - int(offer.cost), "Releasing " + id + " upgrade spends one price")
		check(int(ledger.room_upgrade_levels()[id]) == before_level + 1, id + " upgrades exactly once")
		check(int(game.hud.room_panel.offer.level) == before_level + 1, id + " immediately shows the next upgrade number")
		check(int(game.hud.room_panel.offer.cost) == int(ledger.room_upgrade_view(id).cost), id + " immediately shows the next price")
		check(game.room.is_upgrade_active(id), "Successful " + id + " release starts object upgrade feedback")
		check(not game.hud.room_panel.get_node("%Buy").disabled, "Buy remains available while " + id + " is upgrading")
		check(game.soil.make_snapshot() == original, id + " purchase leaves carpet untouched")
		await create_timer(1.0).timeout
		check(not game.hud.room_panel.get_node("%Buy").disabled, "Settling " + id + " does not change purchase availability")
		assert_transformation_progress(1, "First " + id + " purchase")
		if id == "floor":
			await create_timer(0.3).timeout
			await capture("portrait_after_upgrade")
		tap(game.hud.room_panel.get_node("%Close").get_global_rect().get_center())
		await settle()
		check(not game.hud.upgrades_open() and not game.soil.simulation_suspended, "Closing " + id + " resumes cleaning")
	check(card_centers[0].distance_to(card_centers[2]) > 50.0, "Window and floor cards appear near different items instead of one fixed screen center")
	# Income advances on every purchase; authored models span the whole ladder.
	var floor_milestones := ROOM_RULES.visual_milestones("floor", ledger.active_store)
	var first_milestone: int = floor_milestones[0]
	ledger.cash = 1e8
	ledger.changed.emit()
	game.open_room_upgrade("floor")
	await settle()
	for next_level: int in range(2, first_milestone + 1):
		var milestone_offer: Dictionary = ledger.room_upgrade_view("floor")
		var milestone_buy: Vector2 = game.hud.room_panel.get_node("%Buy").get_global_rect().get_center()
		tap(milestone_buy)
		await settle()
		check(ledger.room_upgrade_levels().floor == next_level, "Repeated floor purchase reaches exactly step %d" % next_level)
		check(ledger.progression_view().early_reward == milestone_offer.next_early, "Floor step %d gives its quoted earnings immediately" % next_level)
		if next_level < first_milestone:
			check(game.room.visual_tiers.floor == 0, "Floor step %d keeps the concrete appearance" % next_level)
			check(game.hud.room_panel.offer.next_visual_level == first_milestone, "Offer keeps the next floor makeover at its authored milestone")
			await create_timer(1.0).timeout
			assert_transformation_progress(next_level, "Floor level %d" % next_level)
	check(game.room.is_upgrade_active("floor"), "The floor milestone purchase performs the makeover animation")
	await create_timer(1.0).timeout
	check(game.room.visual_tiers.floor == 1 and game.room.get_node("Floor/Tier1").visible, "The floor milestone purchase settles on the first authored makeover")
	check(not game.room.is_upgrade_active("floor"), "Milestone effect settles without leaving an active animation")
	check(game.hud.room_panel.offer.next_visual_level == floor_milestones[1], "After the first makeover the offer names the second authored milestone")
	assert_transformation_progress(0, "First floor transformation resets its next segment")
	check(game.soil.make_snapshot() == original, "Milestone purchases preserve the rug being cleaned")
	await capture("portrait_first_makeover")
	game.hud.close_upgrades()
	# Repeated props must point to the selected instance, not the group's first pot.
	for local_position: Vector3 in [Vector3(1.94, 0.70, 2.42), Vector3(1.94, 0.70, -2.42)]:
		var actual_corner: Vector2 = game.camera.unproject_position(game.room.to_global(local_position))
		game.open_room_upgrade("plants", actual_corner)
		await settle()
		assert_offer_layout("plants", actual_corner, "Selected plant corner")
		var selected_position: Vector3 = game.room._selection.global_position
		var expected_position: Vector3 = game.room.to_global(local_position)
		check(Vector2(selected_position.x, selected_position.z).distance_to(Vector2(expected_position.x, expected_position.z)) < 0.005, "Selection highlight follows the same plant corner as the offer")
		game.hud.close_upgrades()

	# Wallet changes gate purchases while leaving transformation progress unchanged.
	game.open_room_upgrade("floor")
	var cost := int(ledger.room_upgrade_view("floor").cost)
	for wallet: int in [0, int(cost / 2), cost, cost * 2]:
		ledger.cash = wallet
		ledger.changed.emit()
		await create_timer(0.3).timeout
		assert_transformation_progress(0, "Floor milestone with wallet %d" % wallet)
		check(game.hud.room_panel.get_node("%Buy").disabled == (wallet < cost), "Purchase availability still follows wallet %d against price %d" % [wallet, cost])
		if wallet == int(cost / 2):
			await capture("funding_half")
	var untouched_cash: int = ledger.cash
	var buy: Vector2 = game.hud.room_panel.get_node("%Buy").get_global_rect().get_center()
	touch(buy, true)
	touch(buy, false, true)
	check(ledger.cash == untouched_cash, "Canceled touch cannot spend coins")
	touch(buy, true)
	drag(buy + Vector2(0, -90), Vector2(0, -90))
	touch(buy + Vector2(0, -90), false)
	check(ledger.cash == untouched_cash, "Dragging away from upgrade cannot spend coins")
	var rug_point: Vector2 = game.camera.unproject_position(Vector3(0, 0.067, 0))
	touch(rug_point, true)
	drag(rug_point + Vector2(45, 35), Vector2(45, 35))
	touch(rug_point + Vector2(45, 35), false)
	check(not game.brush_dragging and game.soil.make_snapshot() == original, "Dragging on the carpet behind the offer cannot clean")
	check(game.hud.upgrades_open(), "Dragging outside the offer does not accidentally dismiss it")
	var card_rect: Rect2 = game.hud.room_panel.get_node("%Card").get_global_rect()
	var outside := Vector2(24, 220)
	if card_rect.has_point(outside): outside = Vector2(516, 220)
	tap(outside)
	check(not game.hud.upgrades_open(), "A clean tap outside dismisses the floating offer")
	check(ledger.cash == untouched_cash and game.soil.make_snapshot() == original, "Dismissing the offer neither purchases nor brushes")
	game.open_room_upgrade("floor")
	await settle()
	await create_timer(1.0).timeout
	check(not game.room.is_upgrade_active(), "Previous effects are settled before testing a failed purchase")
	var saved_path: String = ledger._save_path
	var before_failed_purchase: Dictionary = ledger._capture_state()
	var before_failed_models: Dictionary = game.room.levels.duplicate()
	# The save path is an existing regular file, so a child beneath it cannot be written.
	ledger._save_path = saved_path + "/cannot-write.json"
	tap(game.hud.room_panel.get_node("%Buy").get_global_rect().get_center())
	await settle()
	check(ledger._capture_state() == before_failed_purchase and game.room.levels == before_failed_models, "Failed save rolls back coins, levels, earnings and visible room")
	check(not game.room.is_upgrade_active(), "Failed save cannot play a successful-upgrade effect")
	var status := game.hud.room_panel.get_node("%Status") as Label
	check(status.is_visible_in_tree() and status.text.contains("Couldn't save"), "Failed purchase makes its explanation visible in the card")
	assert_offer_layout("floor", game.camera.unproject_position(game.room.anchor_world("floor")), "Failed-save offer")
	check(game.soil.make_snapshot() == original, "Failed purchase preserves the current carpet")
	ledger._save_path = saved_path
	game.hud.close_upgrades()

	# Normal and inset phone layouts, including a resize while an offer is open.
	ledger.cash = 10000
	ledger.changed.emit()
	for viewport_size: Vector2i in [Vector2i(320, 720), Vector2i(360, 800), Vector2i(800, 360), Vector2i(720, 1000)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		game.hud.preview_safe_insets = Vector4(10, 24, 12, 14)
		ledger.cash = 12 if viewport_size.x == 320 else 10000
		ledger.changed.emit()
		await settle()
		game.frame_carpet()
		for id: String in IDS:
			game.open_room_upgrade(id)
			await settle()
			var anchor: Vector2 = game.camera.unproject_position(game.room.anchor_world(id))
			assert_offer_layout(id, anchor, "%dx%d %s" % [viewport_size.x, viewport_size.y, id])
			if id == "window" or (id == "plants" and viewport_size.x > viewport_size.y):
				await create_timer(0.3).timeout
				await capture("%dx%d_%s" % [viewport_size.x, viewport_size.y, id])
			game.hud.close_upgrades()
	game.open_room_upgrade("plants")
	root.content_scale_size = Vector2i(800, 360)
	root.size = Vector2i(800, 360)
	await settle()
	assert_offer_layout("plants", game.camera.unproject_position(game.room.anchor_world("plants")), "Rotation while open")
	check(game.soil.make_snapshot() == original, "All offers and rotations leave carpet dirt untouched")
	game.hud.close_upgrades()
	# The final authored model is followed by earnings upgrades to the store cap.
	game.open_room_upgrade("floor")
	await settle()
	var level_cap := PROGRESSION.room_level_cap(ledger.active_store)
	while int(ledger.room_upgrade_levels().floor) < level_cap:
		# Fund this quote and the next (up to 2.4x at a price-band boundary),
		# at their own scale so every deduction remains representable.
		ledger.cash = float(ledger.room_upgrade_view("floor").cost) * 4.0
		ledger.changed.emit()
		if not ledger.buy_room_upgrade("floor"):
			check(false, "Fixture reaches floor mastery using actual purchases")
			break
		var purchased_level := int(ledger.room_upgrade_levels().floor)
		if purchased_level in floor_milestones or purchased_level == level_cap:
			await create_timer(0.3).timeout
			assert_transformation_progress(0, "Actual floor purchase reaches level %d" % purchased_level)
			check(game.hud.room_panel.get_node("%Buy").disabled == (purchased_level == level_cap), "Floor only stops purchases at mastery, including premium model and finish milestones")
	await settle()
	assert_offer_layout("floor", game.camera.unproject_position(game.room.anchor_world("floor")), "Completed floor ladder")
	check(game.hud.room_panel.offer.level == level_cap and game.hud.room_panel.offer.next_level == level_cap, "Finished floor offer remains at its final level")
	check(game.hud.room_panel.get_node("%Buy").disabled, "Completed floor mastery disables further purchases")
	assert_transformation_progress(0, "Completed floor ladder stays full")
	var completed_cash: float = ledger.cash
	tap(game.hud.room_panel.get_node("%Buy").get_global_rect().get_center())
	check(ledger.cash == completed_cash and game.room.visual_tiers.floor == 3, "Tapping a finished ladder cannot spend coins or change its model")
	game.hud.close_upgrades()
	print("FLOATING ROOM UI: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ledger._save_path))
	quit(1 if failures > 0 else 0)
