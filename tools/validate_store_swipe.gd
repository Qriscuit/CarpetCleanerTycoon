extends SceneTree
## Production carousel input and geometry, using an isolated ledger only.
const Ledger = preload("res://scripts/shop_state.gd")
const Rules = preload("res://scripts/progression.gd")
const Pattern = preload("res://scripts/ui/home_pattern.gd")
var checks := 0
var failures := 0
var home: Control
var state: Node

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to isolate the carousel ledger")
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

func settle_transition() -> void:
	for tick in 100:
		if not home.store_transition_active:
			break
		await create_timer(0.04).timeout
	check(not home.store_transition_active, "Carousel completes its automatic slide")
	await frames()

func touch_at(point: Vector2, down: bool, canceled := false, finger := 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = finger
	event.position = point
	event.pressed = down
	event.canceled = canceled
	root.push_input(event, true)

func touch_swipe(delta: Vector2, canceled := false) -> void:
	var origin: Vector2 = home.get_node("%ShopTap").get_global_rect().get_center()
	touch_at(origin, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = origin + delta
	drag.relative = delta
	root.push_input(drag, true)
	touch_at(origin + delta, false, canceled)

func mouse_at(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = down
	root.push_input(event, true)

func mouse_swipe(delta: Vector2) -> void:
	var origin: Vector2 = home.get_node("%ShopTap").get_global_rect().get_center()
	mouse_at(origin, true)
	var drag := InputEventMouseMotion.new()
	drag.position = origin + delta
	drag.global_position = drag.position
	drag.relative = delta
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(drag, true)
	mouse_at(origin + delta, false)

func tap_shop() -> void:
	var point: Vector2 = home.get_node("%ShopTap").get_global_rect().get_center()
	touch_at(point, true)
	touch_at(point, false)

func projected_bounds(pivot: Node3D) -> Rect2:
	var incoming := pivot == home.get_node("%IncomingShopPivot")
	var camera: Camera3D = home.get_node("%IncomingShopCamera" if incoming else "%ShopCamera")
	var view: SubViewport = home.get_node("%IncomingShopViewport" if incoming else "%ShopViewport")
	var canvas: SubViewportContainer = home.get_node("%IncomingBuildingView" if incoming else "%BuildingView")
	var rect := canvas.get_global_rect()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for mesh: MeshInstance3D in pivot.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var bounds := mesh.get_aabb()
		for corner in 8:
			var pixel := camera.unproject_position(mesh.global_transform * bounds.get_endpoint(corner))
			var point := rect.position + pixel / Vector2(view.size) * rect.size
			minimum = minimum.min(point)
			maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)

func resource_ids() -> Array:
	var ids: Array = []
	for key: String in ["BuildingView", "ShopViewport", "ShopCamera", "IncomingBuildingView", "IncomingShopViewport", "IncomingShopCamera"]:
		ids.append(home.get_node("%" + key).get_instance_id())
	for pivot: Node3D in [home.get_node("%ShopPivot"), home.get_node("%IncomingShopPivot")]:
		ids.append(pivot.get_instance_id())
		for mesh: MeshInstance3D in pivot.find_children("*", "MeshInstance3D", true, false):
			ids.append(mesh.get_instance_id())
			ids.append(mesh.mesh.get_instance_id())
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface)
				ids.append(material.get_instance_id() if material != null else 0)
	return ids

func check_gradient(store_id: int) -> void:
	var sky = home.get_node("SkyPattern")
	check(sky._gradient_top.is_equal_approx(Pattern.STORE_TOP_COLORS[store_id - 1]), "Settled sky uses store %d's top color" % store_id)
	check(sky._gradient_bottom.is_equal_approx(Pattern.STORE_BOTTOM_COLORS[store_id - 1]), "Settled sky uses store %d's bottom color" % store_id)
	check(not sky._gradient_top.is_equal_approx(sky._gradient_bottom), "Store %d has a visible vertical gradient" % store_id)

func check_idle(store_id: int) -> void:
	check(home.preview_store == store_id and home.displayed_store == store_id, "Preview and visible destination agree at store %d" % store_id)
	check(home.get_node("%ShopPivot").position.x == 0.0 or is_zero_approx(home.get_node("%ShopPivot").position.x), "Settled shop has no leftover horizontal translation")
	check(not home.get_node("%IncomingBuildingView").visible, "Incoming duplicate retires after the slide")
	check(home.get_node("%IncomingShopViewport").render_target_update_mode == SubViewport.UPDATE_DISABLED, "Idle duplicate does not keep rendering")
	check(not home.get_node("%ShopTap").disabled, "Shop interaction returns after the slide")
	check(not home.changing_scene and current_scene == home, "Swiping leaves the main menu active")
	check(home.get_node("%StoreLabel").text.begins_with(str(store_id) + " ·"), "Caption identifies the visible store")
	check_gradient(store_id)

func run() -> void:
	state = root.get_node("ShopState")
	state.set_process(false)
	state._test_ticks_msec = 0
	state._test_unix_time = 1000000.0
	state._save_path = "res://../build/store_swipe_%d.json" % OS.get_process_id()
	check(state.reset_progress(), "The carousel starts with an isolated fresh ledger")
	root.size = Vector2i(390, 844)
	home = load("res://scenes/production/floating_home.tscn").instantiate()
	root.add_child(home)
	current_scene = home
	home.animate_shop = false
	await frames()
	check(home.has_method("_set_store_transition_progress"), "Carousel has deterministic visual progress")
	check(home.has_method("_finish_store_transition"), "Carousel has a terminal state without a late timer")
	check(is_instance_valid(home.get_node("%IncomingShopPivot")), "A reusable outgoing shop is ready")
	if not is_instance_valid(home.get_node("%IncomingShopPivot")) or not home.has_method("_finish_store_transition"):
		quit(1)
		return
	check_idle(1)
	var before: Dictionary = state._capture_state()
	var saved := FileAccess.get_file_as_bytes(state._save_path)
	var pool := resource_ids()
	var colors: Array = []
	for store_id in range(2, Rules.STORE_COUNT + 1):
		touch_swipe(Vector2(-88, 4))
		check(home.store_transition_active, "Touch swipe animates rather than replacing the shop instantly")
		check(home.preview_store == store_id, "Touch swipe targets the next shop")
		check(state.active_store == 1 and state.stores.size() == 1 and state.cash == 0, "Locked store preview grants no ownership or active branch")
		tap_shop()
		home.enter_cleaning()
		check(not home.changing_scene and not home.get_node("%Management").visible and state.active_job_id.is_empty(), "A real tap during shop motion cannot start cleaning or open a sheet")
		await settle_transition()
		check_idle(store_id)
		check(state._capture_state() == before, "Locked preview leaves the entire ledger unchanged")
		check(FileAccess.get_file_as_bytes(state._save_path) == saved, "Locked preview writes no save transaction")
		check(resource_ids() == pool, "Repeated previews reuse nodes, meshes, and material resources")
		var facade := PackedColorArray()
		for material: StandardMaterial3D in home.store_materials:
			facade.append(material.albedo_color)
		colors.append(facade)
	for index in range(colors.size() - 1):
		check(colors[index] != colors[index + 1], "Consecutive store facades have distinct colors")
	# Last/first edges consume a swipe while keeping the same store and scene.
	mouse_swipe(Vector2(-100, 0))
	await frames()
	check(not home.store_transition_active and home.preview_store == Rules.STORE_COUNT, "Swiping beyond the last store does not animate a phantom shop")
	check(not home.changing_scene and state.active_job_id.is_empty(), "A boundary swipe cannot become an accidental cleaning tap")
	for store_id in range(Rules.STORE_COUNT - 1, 0, -1):
		mouse_swipe(Vector2(94, -5))
		check(home.store_transition_active and home.preview_store == store_id, "Mouse dragging navigates backward with a real slide")
		await settle_transition()
		check_idle(store_id)
	mouse_swipe(Vector2(100, 0))
	await frames()
	check(not home.store_transition_active and home.preview_store == 1, "Swiping beyond the first store stays bounded")
	# Vertical, short, canceled, and multi-touch gestures never choose a shop.
	for delta: Vector2 in [Vector2(-36, 0), Vector2(-55, 80), Vector2(0, -100)]:
		touch_swipe(delta)
		await frames()
		check(home.preview_store == 1 and not home.store_transition_active and state.active_job_id.is_empty(), "Non-horizontal swipe stays in the current shop")
	touch_swipe(Vector2(-90, 0), true)
	await frames()
	check(home.preview_store == 1 and not home.store_transition_active, "Canceled touch never starts navigation")
	var origin: Vector2 = home.get_node("%ShopTap").get_global_rect().get_center()
	touch_at(origin, true)
	touch_at(origin + Vector2(3, 3), true, false, 1)
	touch_at(origin + Vector2(-90, 0), false)
	touch_at(origin + Vector2(-90, 3), false, false, 1)
	await frames()
	check(home.preview_store == 1 and not home.store_transition_active, "Multi-touch cannot become a shop swipe")
	# Freeze real slides to verify the model moves beyond the whole game window.
	for dimensions: Vector2i in [Vector2i(320,568),Vector2i(390,844),Vector2i(844,390),Vector2i(1024,768)]:
		root.size = dimensions
		await frames()
		home._layout()
		await frames()
		var canvas: SubViewportContainer = home.get_node("%BuildingView")
		var base_rect := canvas.get_global_rect()
		var old_store: int = home.displayed_store
		var target := old_store + 1 if old_store < Rules.STORE_COUNT else old_store - 1
		var direction := 1 if target > old_store else -1
		var old_bounds := projected_bounds(home.get_node("%ShopPivot"))
		home.preview_location(target)
		check(home.store_transition_active and home.store_transition_direction == direction, "Slide direction follows the selected neighbor")
		home.store_transition_tween.pause()
		home._set_store_transition_progress(0.0)
		var incoming: Rect2 = projected_bounds(home.get_node("%IncomingShopPivot"))
		check(incoming.position.x >= home.size.x if direction > 0 else incoming.end.x <= 0.0, "The incoming shop starts outside the entire window at " + str(dimensions))
		check(projected_bounds(home.get_node("%ShopPivot")).get_center().is_equal_approx(old_bounds.get_center()), "The outgoing shop begins at its prior visible position")
		check(home.get_node("%IncomingBuildingView").visible, "Both shop render pools are visible during motion")
		var from_top: Color = Pattern.STORE_TOP_COLORS[old_store - 1]
		var to_top: Color = Pattern.STORE_TOP_COLORS[target - 1]
		var from_bottom: Color = Pattern.STORE_BOTTOM_COLORS[old_store - 1]
		var to_bottom: Color = Pattern.STORE_BOTTOM_COLORS[target - 1]
		var sky = home.get_node("SkyPattern")
		check(sky._gradient_top.is_equal_approx(from_top) and sky._gradient_bottom.is_equal_approx(from_bottom), "The gradient begins at the outgoing shop's palette")
		home._set_store_transition_progress(0.5)
		var outgoing_half := projected_bounds(home.get_node("%ShopPivot"))
		var incoming_half := projected_bounds(home.get_node("%IncomingShopPivot"))
		check(outgoing_half.get_center().x < old_bounds.get_center().x if direction > 0 else outgoing_half.get_center().x > old_bounds.get_center().x, "The current shop physically moves in the swipe direction")
		check(incoming_half.get_center().x > old_bounds.get_center().x if direction > 0 else incoming_half.get_center().x < old_bounds.get_center().x, "The next shop approaches from the opposite edge")
		check(sky._gradient_top.is_equal_approx(from_top.lerp(to_top, 0.5)) and sky._gradient_bottom.is_equal_approx(from_bottom.lerp(to_bottom, 0.5)), "Both gradient endpoints blend continuously at mid-slide")
		check(not sky._gradient_top.is_equal_approx(from_top) and not sky._gradient_top.is_equal_approx(to_top), "Mid-slide does not snap to either store color")
		home._set_store_transition_progress(1.0)
		var outgoing_end := projected_bounds(home.get_node("%ShopPivot"))
		check(outgoing_end.end.x <= 0.0 if direction > 0 else outgoing_end.position.x >= home.size.x, "The outgoing shop finishes beyond the whole game window at " + str(dimensions))
		check(projected_bounds(home.get_node("%IncomingShopPivot")).get_center().is_equal_approx(old_bounds.get_center()), "The incoming shop arrives in exactly the same fitted position")
		check(home.get_node("%BuildingView").get_global_rect().size.is_equal_approx(base_rect.size), "Sliding preserves the fitted rendering size")
		home._finish_store_transition(false)
		check_idle(target)
		check(resource_ids() == pool, "Resizing and reversing preserve both fixed resource pools")
	# A viewport resize recomputes both travel paths without restarting the slide.
	root.size = Vector2i(390,844)
	await frames()
	home.preview_location(1 if home.displayed_store != 1 else 2)
	home.store_transition_tween.pause()
	home._set_store_transition_progress(0.4)
	var during_resize_target: int = home.store_transition_to
	root.size = Vector2i(844,390)
	await frames()
	home.preview_safe_insets = Vector4(44,0,44,16)
	home._layout()
	check(is_equal_approx(home.store_transition_progress, 0.4), "A resize keeps the current transition progress")
	check(home.get_node("%BuildingView").size.is_equal_approx(home.get_node("%IncomingBuildingView").size), "Both shops retain matching frames after rotation")
	for key: String in ["ShopTap", "TopBar", "Dock"]:
		check(home._safe_rect().grow(1).encloses(home.get_node("%" + key).get_global_rect()), key + " remains inside the safe area during a slide")
	home._set_store_transition_progress(1.0)
	var resized_outgoing := projected_bounds(home.get_node("%ShopPivot"))
	check(resized_outgoing.end.x <= 0.0 if home.store_transition_direction > 0 else resized_outgoing.position.x >= home.size.x, "Resized outgoing shop still fully leaves the new game window")
	home._finish_store_transition(false)
	check_idle(during_resize_target)
	home.preview_safe_insets = Vector4.ZERO
	root.size = Vector2i(390,844)
	await frames()
	# Rapid navigation uses the latest request, then a new complete slide.
	home.preview_location(1)
	await settle_transition()
	touch_swipe(Vector2(-90,0))
	touch_swipe(Vector2(-90,0))
	touch_swipe(Vector2(-90,0))
	check(home.preview_store == 2 and home.queued_store == 4, "Three rapid touch swipes retain every destination step")
	await settle_transition()
	check_idle(4)
	home.preview_location(1)
	await settle_transition()
	home.preview_location(2)
	home.preview_location(4)
	home.preview_location(3)
	check(home.preview_store == 2 and home.queued_store == 3, "Rapid requests keep the current destination and queue the latest next shop")
	await settle_transition()
	check_idle(3)
	check(state.active_store == 1 and state.stores.size() == 1, "Queued locked previews cannot create ownership")
	home.preview_location(2)
	home.preview_location(3)
	await settle_transition()
	check_idle(3)
	check(resource_ids() == pool, "Rapid reversals reuse the same authored pools")
	# Focus loss settles the in-flight destination and drops unstarted navigation.
	home.preview_location(2)
	home.preview_location(1)
	var focus_origin: Vector2 = home.get_node("%ShopTap").get_global_rect().get_center()
	touch_at(focus_origin, true)
	home._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not home.store_transition_active and home.queued_store == -1, "Focus loss settles animation and clears queued slides")
	check(home.displayed_store == 2 and home.touch_id == -1 and not home.mouse_store_drag, "Focus loss selects the in-flight destination and retires the pointer gesture")
	check_idle(2)
	touch_at(focus_origin, false)
	check(state.active_job_id.is_empty() and not home.changing_scene, "Late pointer release after focus loss cannot start cleaning")
	# Modal panels may be opened during a slide and retain a stable shop behind them.
	home.preview_location(3)
	home._open_settings()
	check(not home.store_transition_active and home.get_node("%SettingsSheet").visible, "Settings settles the carousel before showing the sheet")
	check(home.displayed_store == 3, "Settings background uses the arrived store")
	home._close_settings()
	home.preview_location(4)
	home.open_management("plans")
	check(not home.store_transition_active and home.get_node("%Management").visible, "Management settles the carousel before opening")
	check(home.displayed_store == 4, "Management background uses the arrived store")
	var sheet: Control = home.management
	check(sheet.get_node("%SheetNote").text.contains("0/6 stores mastered"), "Stores sheet describes first-section completion")
	for id in range(1, Rules.STORE_COUNT + 1):
		var row_id: String = sheet.PLAN_ROW_IDS[id - 1]
		check(sheet.rows[row_id].visible and sheet.actions[row_id] == "store:%d" % id, "Stores sheet exposes destination %d" % id)
		check(sheet.action_for(row_id).disabled, "Unopened destinations cannot be visited and the current store has no redundant action")
	check(sheet.rows.next_section.visible and sheet.action_for("next_section").disabled and sheet.actions.next_section.is_empty(), "The next section is visible and unavailable")
	home.close_management()
	home.enter_cleaning()
	check(home.get_node("%Management").visible and home.management.current_tab == "plans" and state.active_job_id.is_empty(), "A settled locked shop opens store milestones without starting a rug")
	home.close_management()
	# Owned store navigation selects and persists its branch once the slide starts.
	state.stores["2"] = Rules.new_branch(2)
	state.stores["3"] = Rules.new_branch(3)
	state.stores["4"] = Rules.new_branch(4)
	check(state.save_state(), "Owned-store fixture is saved through the real ledger")
	home.preview_location(4)
	check(state.active_store == 4 and not home.store_transition_active, "An unchanged preview still selects a newly owned store without replaying motion")
	# A store committed by management or another ledger action must stay visible
	# when an in-flight preview is interrupted by focus loss or a modal sheet.
	home.preview_location(1)
	await settle_transition()
	home.preview_location(2)
	check(home.store_transition_active, "External-selection regression begins during a real slide")
	check(state.select_store(3), "The ledger externally commits another owned store")
	check(state.active_store == 3, "The external store selection is already authoritative")
	home._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not home.store_transition_active and home.queued_store == -1, "Focus loss settles an external committed selection without leaving a queue")
	check(home.displayed_store == state.active_store and home.preview_store == state.active_store, "Focus loss cannot leave the visible shop behind its committed ledger store")
	check_idle(3)
	home.preview_location(1)
	await settle_transition()
	home.preview_location(2)
	check(state.select_store(4), "A second external store commits during a new slide")
	home._open_settings()
	check(not home.store_transition_active and home.queued_store == -1 and home.get_node("%SettingsSheet").visible, "Settings settles an external committed selection before opening")
	check(home.displayed_store == state.active_store and home.preview_store == state.active_store, "Settings backdrop agrees with the externally committed active store")
	check_idle(4)
	home._close_settings()
	check(resource_ids() == pool, "Interrupted external selections reuse both render pools")
	# A later user request may supersede an externally committed target.
	home.preview_location(1)
	await settle_transition()
	home.preview_location(2)
	check(state.select_store(3), "An external third-store selection can be superseded")
	home.preview_location(2)
	await settle_transition()
	check_idle(2)
	check(state.active_store == 2, "Queuing the current destination reselects its owned ledger branch")
	# Keep Store 4 locked to ensure a deliberate preview stays a preview.
	state.stores.erase("4")
	check(state.save_state(), "The locked fourth-store regression fixture is isolated")
	home.preview_location(1)
	await settle_transition()
	home.preview_location(2)
	check(state.select_store(3), "An external owned selection precedes a deliberate locked preview")
	home.preview_location(4)
	await settle_transition()
	check_idle(4)
	check(state.active_store == 3 and not state.stores.has("4"), "A queued locked preview preserves ownership and the last committed branch")
	home._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(home.displayed_store == 4 and home.preview_store == 4, "Later focus loss preserves a deliberately chosen locked preview")
	home.preview_location(2)
	home._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check_idle(2)
	check(state.active_store == 2, "A superseded external target cannot bounce a later owned slide back")
	home.preview_location(4)
	await settle_transition()
	check(state.active_store == 2, "A direct locked preview can precede an external same-store purchase")
	state.stores["4"] = Rules.new_branch(4)
	check(state.save_state(), "Restore ownership for the remaining paid-navigation regression")
	check(state.select_store(4), "The ledger externally commits the store already visible as a locked preview")
	check(not home.store_transition_active and home.displayed_store == 4 and home.preview_store == 4, "An external same-visible-store commitment needs no replacement slide")
	home.preview_location(2)
	home._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check_idle(2)
	check(state.active_store == 2, "A same-visible external commitment cannot leave stale pending navigation")

	home.preview_location(1)
	await settle_transition()
	touch_swipe(Vector2(-90,0))
	check(state.active_store == 2 and home.preview_store == 2, "A real swipe selects an owned destination in the ledger")
	check(state.active_job_id.is_empty() and not home.changing_scene, "Owned selection itself cannot start a rug")
	home.preview_location(3)
	check(state.active_store == 2, "A queued owned shop is not persisted before its slide starts")
	await settle_transition()
	check_idle(3)
	check(state.active_store == 3, "Queued owned navigation selects the branch when its slide starts")
	# Added stores use the same carousel and Stores-sheet selection contract.
	for id in range(5, Rules.STORE_COUNT + 1): state.stores[str(id)] = Rules.new_branch(id)
	check(state.save_state(), "The six-store fixture uses an isolated save")
	home.open_management("plans")
	await frames()
	check(sheet.get_node("%TravelGoals").visible and sheet.get_node("%TravelTitle").text.begins_with("Master "), "Owning six stores retains the mastery checklist needed to complete the section")
	check(sheet.actions.store_6 == "store:6" and not sheet.action_for("store_6").disabled, "Store six becomes visitable in the section sheet")
	sheet.action_for("store_6").pressed.emit()
	check(state.active_store == 6, "The Stores-sheet action selects the sixth owned store")
	home.close_management()
	await settle_transition()
	check_idle(6)
	home.preview_location(5)
	await settle_transition()
	check_idle(5)
	check(state.active_store == 5, "Carousel selects the fifth owned store")
	home.preview_location(3)
	await settle_transition()
	var reloaded := Ledger.new()
	reloaded._save_path = state._save_path
	reloaded._test_ticks_msec = 0
	reloaded._test_unix_time = 1000000.0
	reloaded._save_enabled = false
	root.add_child(reloaded)
	reloaded.set_process(false)
	check(reloaded.active_store == 3 and reloaded.stores.size() == Rules.STORE_COUNT, "Reload restores the arrived active shop and all six stores")
	reloaded.free()
	check(resource_ids() == pool, "Owned selection and save/reload keep carousel resources unchanged")
	# Entering a settled owned shop still runs the original cleaning route.
	tap_shop()
	check(home.changing_scene and current_scene == home, "A settled owned shop retains its press animation before cleaning")
	await create_timer(0.35).timeout
	await frames()
	check(current_scene.scene_file_path == "res://scenes/production/rug_cleaning.tscn" and state.active_store == 3 and not state.active_job_id.is_empty(), "A real tap opens a paid rug in the selected store")
	if is_instance_valid(current_scene):
		current_scene.free()
	current_scene = null
	# Stop the reused audio voices before a headless process exits.
	root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.05).timeout
	await frames()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("STORE_SWIPE_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
