extends SceneTree
## The sparse cleaning HUD stays authored, touch-safe, and responsive.
var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("EDITABLE HUD: " + message)


func _initialize() -> void:
	call_deferred("run")


func touch(index: int, point: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)


func drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	root.push_input(event, true)


func run() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test for an isolated UI run.")
		quit(2)
		return
	for scene_path in ["res://scenes/production/rug_cleaning.tscn", "res://scenes/test/rug_cleaning_gym.tscn"]:
		var authored := (load(scene_path) as PackedScene).instantiate()
		var hud: CanvasLayer = authored.get_node("GymUI")
		check(hud.get_node("%HomeButton") is Button and hud.get_node("%HomeButton").text.is_empty(), "Back is an authored icon-only button")
		check(hud.get_node("%ProgressBar") is ProgressBar and hud.get_node("%ProgressValue") is Label, "The one progress bar and number are authored")
		check(hud.get_node("%FinishJobButton") is Button, "Finish job is editor-selectable")
		check(hud.get_node_or_null("%Heading") == null and hud.get_node_or_null("%LeftRail") == null and hud.get_node_or_null("%ToolRail") == null and hud.get_node_or_null("%CompletionCard") == null, "Text panels, side rails, and the completion prompt were removed")
		authored.free()

	var game := (load("res://scenes/production/rug_cleaning.tscn") as PackedScene).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	await process_frame
	await process_frame
	for button in game.touch_buttons:
		check(button.custom_minimum_size.y >= 56.0, "Every cleaning action has a 56-pixel touch target")
	for viewport_size in [Vector2i(360, 800), Vector2i(800, 360), Vector2i(720, 1000)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		await process_frame
		game.hud._layout()
		game.frame_carpet()
		var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
		for name in ["HomeButton", "CleaningProgress", "FinishJobButton"]:
			var control: Control = game.hud.control(name)
			check(bounds.encloses(control.get_global_rect()), name + " stays on-screen at " + str(viewport_size))
		check(is_zero_approx(game.camera.position.x), "The rug remains horizontally centered at " + str(viewport_size))
		if "--capture" in OS.get_cmdline_user_args() and viewport_size in [Vector2i(360, 800), Vector2i(800, 360)]:
			await RenderingServer.frame_post_draw
			var orientation := "portrait" if viewport_size.y > viewport_size.x else "landscape"
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../art/renders/cleaning_minimal_" + orientation + ".png"))

	# The single number uses the less-clean of debris and dust.
	game.soil.remaining = 0
	game.soil.surface_coverage_total = float(game.soil.surface_pixel_count) * 0.16
	game.update_contract_status()
	check(game.state_label.text == "84%" and not game.finish_button.visible, "Finish stays hidden below 85%")
	game.soil.surface_coverage_total = float(game.soil.surface_pixel_count) * 0.15
	game.update_contract_status()
	check(game.state_label.text == "85%" and game.finish_button.visible, "Finish appears at 85%")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../art/renders/cleaning_finish_85.png"))

	var target: Button = game.finish_button
	target.pressed.disconnect(game.finish_contract)
	var point := target.get_global_rect().get_center()
	touch(0, point, true)
	check(game.hud_button == target and not game.brush_dragging, "Finger down owns the button without painting")
	touch(0, point, false)
	check(target.has_focus() and not game.brush_dragging, "Finger release activates the intended button only")
	target.pressed.connect(game.finish_contract)
	# Use the Back button for cancellation checks; Finish may have started takeaway.
	target = game.hud.control("HomeButton") as Button
	point = target.get_global_rect().get_center()
	target.release_focus()
	touch(0, point, true)
	drag(0, point + Vector2(0, 35))
	drag(0, point)
	touch(0, point, false)
	check(not target.has_focus() and not game.brush_dragging, "Dragging away permanently cancels a HUD tap")
	touch(0, point, true)
	touch(1, point + Vector2(4, 4), true)
	touch(1, point, false)
	touch(0, point, false)
	check(not target.has_focus() and not game.brush_dragging, "A second finger cancels the pending HUD tap")

	# A practice scene avoids the completed paid rug and verifies clear carpet input.
	game.free()
	var practice := (load("res://scenes/test/rug_cleaning_gym.tscn") as PackedScene).instantiate()
	practice.animate_rug_changes = false
	root.add_child(practice)
	await process_frame
	var carpet_point: Vector2 = practice.camera.unproject_position(Vector3.ZERO) - practice.TOUCH_CONTACT_OFFSET
	touch(0, carpet_point, true)
	check(practice.brush_dragging, "An unblocked finger starts a carpet stroke")
	touch(0, carpet_point, false)
	check(not practice.brush_dragging, "Release ends the carpet stroke")
	practice.free()
	root.content_scale_size = Vector2i(720, 1000)
	root.size = Vector2i(720, 1000)
	print("EDITABLE HUD CHECKS COMPLETE: ", failures, " failures; sparse authored controls, phone layouts, thresholds and touch routing.")
	quit(0 if failures == 0 else 1)
