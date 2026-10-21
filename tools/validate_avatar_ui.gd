extends SceneTree
## Real touch, rendering bounds, save feedback and sleeping preview coverage.
var checks := 0
var failures := 0
var home: Control
var menu: Control

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func touch(point: Vector2, down: bool, canceled := false, finger := 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = finger
	event.position = point
	event.pressed = down
	event.canceled = canceled
	root.push_input(event, true)

func tap(button: Button, canceled := false) -> void:
	var point := button.get_global_rect().get_center()
	touch(point, true)
	touch(point, false, canceled)

func capture(name: String) -> void:
	await create_timer(0.05).timeout
	await settle()
	var folder := "res://../art/renders/avatar"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.get_texture().get_image().save_png(folder + "/" + name + ".png")

func run() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to isolate saves")
		quit(2)
		return
	var ledger := root.get_node("ShopState")
	ledger.reset_progress()
	home = load("res://scenes/production/floating_home.tscn").instantiate()
	root.add_child(home)
	current_scene = home
	root.size = Vector2i(390, 844)
	await settle()
	menu = home.get_node("%AvatarMenu")
	var preview: Control = menu.get_node("%Preview")
	var viewport: SubViewport = preview.get_node("AvatarViewport")
	var pivot: Node3D = viewport.get_node("Studio/Turntable")
	check(not menu.visible and not preview.is_processing(), "Wardrobe is dormant before entry")
	check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Closed avatar viewport does not render")
	check(home.get_node_or_null("%NavBonzi") == null and home.get_node_or_null("%ReturnNotice") == null, "Home removes old helper and offline payout entry")
	check(home.get_node("%NavAvatar").get_node("CaptionContent/Caption").text == "You", "Avatar is the rightmost home entry")
	tap(home.get_node("%NavAvatar"))
	await settle()
	check(menu.visible and preview.active, "Touch opens the wardrobe")
	check(home.get_node("%ShopViewport").render_target_update_mode == SubViewport.UPDATE_DISABLED and home.get_node("%IncomingShopViewport").render_target_update_mode == SubViewport.UPDATE_DISABLED, "Both home studios sleep behind wardrobe")
	check(menu.current_tab == "hats" and menu.hat_cards.size() == 3 and menu.color_cards.size() == 8, "Starter wardrobe has three hats and eight colors")
	check(ledger.appearance == {"color_id": "orange", "hat_id": "none"}, "Fresh wardrobe starts orange with no hat")
	await capture("orange_default")
	var balance: int = ledger.cash
	tap(menu.hat_cards.pirate)
	await settle()
	check(ledger.appearance.hat_id == "pirate" and ledger.cash == balance, "Pirate hat equips freely on tap")
	check(pivot.get_node("PirateHat").visible and not pivot.get_node("Beanie").visible, "Only the chosen hat is visible")
	check(menu.hat_cards.pirate.button_pressed and menu.hat_cards.pirate.get_node("Selected").visible, "Equipped card has persistent visual feedback")
	tap(menu.hat_cards.pirate)
	check(menu.hat_cards.pirate.button_pressed, "Tapping an equipped card keeps its selected treatment")
	tap(menu.get_node("%ColorTab"))
	await settle()
	check(menu.current_tab == "color" and menu.get_node("%ColorTab").button_pressed, "Horizontal color tab switches collection")
	tap(menu.color_cards.mint)
	await settle()
	check(ledger.appearance.color_id == "mint" and ledger.appearance.hat_id == "pirate", "Tint preserves equipped hat")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ledger._save_path))
	check(saved.appearance == ledger.appearance, "Every choice is durably saved immediately")
	var before: Dictionary = ledger.appearance.duplicate()
	tap(menu.color_cards.blue, true)
	check(ledger.appearance == before, "Canceled touch does not equip")
	var point: Vector2 = menu.color_cards.blue.get_global_rect().get_center()
	touch(point, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = point + Vector2(0, -30)
	drag.relative = Vector2(0, -30)
	root.push_input(drag, true)
	touch(drag.position, false)
	check(ledger.appearance == before, "Scrolling across a card does not equip")
	touch(point, true)
	touch(point, true, false, 1)
	touch(point, false)
	touch(point, false, false, 1)
	check(ledger.appearance == before, "Multitouch does not equip")
	var mouse_down := InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_LEFT
	mouse_down.position = point
	mouse_down.pressed = true
	root.push_input(mouse_down, true)
	var mouse_drag := InputEventMouseMotion.new()
	mouse_drag.position = point + Vector2(0, -30)
	mouse_drag.relative = Vector2(0, -30)
	root.push_input(mouse_drag, true)
	var mouse_up := InputEventMouseButton.new()
	mouse_up.button_index = MOUSE_BUTTON_LEFT
	mouse_up.position = mouse_drag.position
	mouse_up.pressed = false
	root.push_input(mouse_up, true)
	check(ledger.appearance == before, "Mouse drag across a card does not equip")
	var preview_point: Vector2 = preview.get_global_rect().get_center()
	var drag_angle: float = pivot.rotation.y
	touch(preview_point, true)
	drag.position = preview_point + Vector2(60, 0)
	drag.relative = Vector2(60, 0)
	root.push_input(drag, true)
	touch(drag.position, false)
	check(not is_equal_approx(pivot.rotation.y, drag_angle), "Dragging preview rotates real geometry")
	check(preview.resume_at >= Time.get_ticks_msec() + 1900, "Manual rotation pauses automatic spin for two seconds")
	var held_angle: float = pivot.rotation.y
	preview._process(0.1)
	check(is_equal_approx(pivot.rotation.y, held_angle), "Automatic spin waits after manual rotation")
	preview.resume_at = 0
	for dimensions in [Vector2i(320,568), Vector2i(390,844), Vector2i(430,932), Vector2i(768,1024), Vector2i(568,320), Vector2i(844,390), Vector2i(1024,768), Vector2i(1080,2400), Vector2i(2400,1080), Vector2i(1440,3200)]:
		root.size = dimensions
		await settle()
		home._layout()
		await settle()
		var safe: Rect2 = home._safe_rect()
		var logical: Vector2 = root.get_visible_rect().size
		var physical_scale := Vector2(root.size) / logical
		check(is_equal_approx(minf(logical.x, logical.y), 390.0), "Home preserves its readable390-unit short side at %s" % dimensions)
		for node_name in ["Back", "HatsTab", "ColorTab"]:
			var physical_target: Vector2 = menu.get_node("%" + node_name).get_global_rect().size * physical_scale
			check(minf(physical_target.x, physical_target.y) >= 43.5, "%s preserves a44px target at %s" % [node_name, dimensions])
		if dimensions.x >= 1080 or dimensions.y >= 2400:
			check(menu.get_node("%Back").get_global_rect().size.y * physical_scale.y >= minf(dimensions.x, dimensions.y) * 0.10, "High-density wardrobe controls scale with the display at %s" % dimensions)
		for node_name in ["Header", "PreviewCard", "Tabs", "CollectionPanel"]:
			check(safe.grow(1).encloses(menu.get_node("%" + node_name).get_global_rect()), "%s stays safe at %s" % [node_name, dimensions])
		check(menu.get_node("%PreviewCard").get_rect().end.y <= menu.get_node("%Tabs").position.y, "Preview remains above tabs at %s" % dimensions)
		check(maxi(viewport.size.x, viewport.size.y) <= 768, "Avatar resolution stays capped at %s" % dimensions)
		preview.set_motion(false)
		for angle in range(0, 360, 45):
			pivot.rotation.y = deg_to_rad(angle)
			var camera: Camera3D = viewport.get_node("Studio/Camera")
			for mesh: MeshInstance3D in pivot.find_children("*", "MeshInstance3D", true, false):
				for corner in 8:
					var projected := camera.unproject_position(mesh.global_transform * mesh.get_aabb().get_endpoint(corner))
					check(Rect2(Vector2.ZERO, Vector2(viewport.size)).grow(1).has_point(projected), "Every hat/model rotation stays framed at %s" % dimensions)
		preview.set_motion(false)
		if dimensions == Vector2i(390,844): await capture("colors_portrait")
		if dimensions == Vector2i(844,390): await capture("colors_landscape")
		if dimensions == Vector2i(1080,2400): await capture("colors_1080x2400")
		if dimensions == Vector2i(2400,1080): await capture("colors_2400x1080")
	root.size = Vector2i(390,844)
	home.preview_safe_insets = Vector4(0,46,0,32)
	await settle()
	home._layout()
	await settle()
	check(home._safe_rect().encloses(menu.get_node("%Header").get_global_rect()), "Header clears simulated notch")
	check(home._safe_rect().encloses(menu.get_node("%CollectionPanel").get_global_rect()), "Cards clear simulated gesture bar")
	tap(menu.get_node("%HatsTab"))
	await capture("hats_portrait_safe")
	preview.set_motion(true)
	preview.set_process(false)
	var angle: float = pivot.rotation.y
	preview.frame_elapsed = 0.0
	preview.resume_at = 0
	preview._process(0.01)
	check(is_equal_approx(pivot.rotation.y, angle), "Turntable does not exceed thirty updates per second")
	preview._process(0.03)
	check(pivot.rotation.y > angle, "Turntable advances with accumulated time")
	home._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not preview.is_processing() and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Unfocused avatar studio sleeps")
	home._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	paused = true
	check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Scene pause disables preview rendering")
	paused = false
	home._toggle_motion(false)
	await create_timer(0.06).timeout
	await settle()
	check(not preview.is_processing() and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Motion off holds one still render")
	tap(menu.hat_cards.beanie)
	await settle()
	check(pivot.get_node("Beanie").visible and not pivot.get_node("PirateHat").visible, "Motion off still renders new choices")
	tap(menu.get_node("%Back"))
	await settle()
	check(not menu.visible and not preview.is_processing() and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not preview.render_dirty, "Back sleeps the character studio")
	check(root.gui_get_focus_owner() == home.get_node("%NavAvatar"), "Close restores focus to the avatar button")
	check(home.get_node("%ShopViewport").render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Home studio resumes after closing")
	tap(home.get_node("%NavAvatar"))
	await settle()
	check(ledger.appearance.hat_id == "beanie" and menu.hat_cards.beanie.button_pressed, "Reopen retains selected appearance")
	home._back()
	check(not menu.visible and not home.get_node("%Management").visible, "Back closes without clicking the home beneath")
	home.preview_safe_insets = Vector4.ZERO
	home.open_avatar()
	menu.show_tab("color")
	await settle()
	var original_save_path: String = ledger._save_path
	var saved_appearance: Dictionary = ledger.appearance.duplicate()
	# The existing save file cannot act as a parent directory, forcing a real
	# write failure without altering permissions or touching another save.
	ledger._save_path = original_save_path + "/blocked.json"
	tap(menu.color_cards.blue)
	check(ledger.appearance == saved_appearance, "Failed card save preserves the previous appearance")
	check(menu.color_cards.mint.button_pressed and not menu.color_cards.blue.button_pressed, "Failed card save restores the previous selected card")
	check(menu.get_node("%SaveError").visible and not menu.get_node("%SaveErrorTimer").is_stopped(), "Failed card save displays brief feedback")
	ledger._save_path = original_save_path
	await create_timer(3.1).timeout
	check(not menu.get_node("%SaveError").visible, "Save error clears after its brief timeout")
	tap(menu.color_cards.blue)
	check(ledger.appearance.color_id == "blue" and not menu.get_node("%SaveError").visible, "Card can be retried successfully after a save error")
	home.close_avatar()
	var viewport_count := home.find_children("*", "SubViewport", true, false).size()
	var material_ids: Array[int] = []
	for material: StandardMaterial3D in preview.body_materials: material_ids.append(material.get_instance_id())
	var appearance_connections: int = ledger.get_signal_connection_list("appearance_changed").size()
	for cycle in 20:
		home.open_avatar()
		menu.show_tab("hats")
		await settle()
		tap(menu.hat_cards.pirate if cycle % 2 == 0 else menu.hat_cards.beanie)
		home.close_avatar()
		check(not preview.is_processing() and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not preview.render_dirty, "Repeated close leaves no preview work, cycle %d" % cycle)
	var final_material_ids: Array[int] = []
	for material: StandardMaterial3D in preview.body_materials: final_material_ids.append(material.get_instance_id())
	check(home.find_children("*", "SubViewport", true, false).size() == viewport_count, "Repeated opening reuses one avatar viewport")
	check(final_material_ids == material_ids, "Repeated opening reuses the body material instances")
	check(ledger.get_signal_connection_list("appearance_changed").size() == appearance_connections, "Repeated opening does not accumulate signal connections")
	home.open_avatar()
	preview.set_focused(true)
	preview.set_motion(true)
	preview.resume_at = 0
	for simulated_hz in [60, 90, 120]:
		preview.frame_elapsed = 0.0
		preview.render_dirty = false
		var scheduled_before: int = preview.scheduled_frame_count
		for tick in simulated_hz * 2:
			preview.request_render()
			preview.set_process(false)
			preview._process(1.0 / float(simulated_hz))
		check(preview.scheduled_frame_count - scheduled_before == 60, "Shared preview budget schedules30fps at%dHz, including continuous dirty requests" % simulated_hz)
	preview.frame_elapsed = 0.0
	preview.set_process(true)
	await settle()
	var original_max_fps := Engine.max_fps
	var original_vsync := DisplayServer.window_get_vsync_mode()
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var render_stamps: Array[int] = []
	var record_frame := func() -> void:
		var stamp: int = preview.last_render_usec
		if stamp > 0 and (render_stamps.is_empty() or render_stamps.back() != stamp): render_stamps.append(stamp)
	RenderingServer.frame_post_draw.connect(record_frame)
	var measure_start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - measure_start < 2050000:
		await process_frame
	RenderingServer.frame_post_draw.disconnect(record_frame)
	Engine.max_fps = original_max_fps
	DisplayServer.window_set_vsync_mode(original_vsync)
	var measured_fps := 0.0
	if render_stamps.size() > 1:
		measured_fps = float(render_stamps.size() - 1) * 1000000.0 / float(render_stamps.back() - render_stamps.front())
	check(render_stamps.size() >= 55 and render_stamps.size() <= 63, "Rendered preview keeps its30fps budget over two seconds")
	check(measured_fps >= 27.0 and measured_fps <= 30.5, "Rendered preview avoids systematic20fps scheduling")
	print("AVATAR_PREVIEW_FPS samples=%d measured=%.3f over=%.3fs" % [render_stamps.size(), measured_fps, float(Time.get_ticks_usec() - measure_start) / 1000000.0])
	home.close_avatar()
	print("AVATAR UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
