extends SceneTree
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CHECK FAILED: " + message)

func click_button(button: Button) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = pressed
		root.push_input(event, true)

func anchor(workshop: Node, index: int) -> Vector3:
	return workshop.tool_nodes[index].to_global(workshop.TOOL_PIVOTS[index])

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var workshop := (load("res://scenes/rug_cleaning_gym.tscn") as PackedScene).instantiate()
	root.add_child(workshop)
	await process_frame
	await process_frame
	var camera: Camera3D = workshop.camera
	var soil: Node = workshop.soil
	workshop.move_brush_to_screen(camera.unproject_position(Vector3(0, 0.067, 0.15)), false)
	for index in 3:
		var old_contact: Vector3 = workshop.contact_point
		click_button(workshop.tool_buttons[index])
		check(workshop.selected_tool == index, "Mouse button equips the matching tool")
		check(workshop.contact_point.is_equal_approx(old_contact), "Switch retains working contact point")
		check(not workshop.brush_dragging and soil.active.is_empty(), "Picker click never starts a cleaning stroke")
		for other in 3:
			check(workshop.tool_nodes[other].visible == (index == other), "Exactly one model is visible")
			check(workshop.tool_buttons[other].button_pressed == (index == other), "Selected button stays highlighted")
		var expected: Vector3 = workshop.contact_point + Vector3.UP * (0.14 if index == 2 else 0.0)
		check(anchor(workshop, index).distance_to(expected) < 0.0001, "Blade/bristles/nozzle align to contact point")
		var lowest := INF
		for mesh in workshop.tool_nodes[index].get_children():
			if mesh is MeshInstance3D:
				for vertex in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					lowest = minf(lowest, mesh.to_global(vertex).y)
		check(absf(lowest - 0.067) < 0.002 if index < 2 else lowest > 0.067, "Actual mesh touches rug or hovers safely for sprayer")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../art/renders/equipped_%d.png" % index))
	# Real touchscreen events must work with mouse emulation disabled.
	for index in [1, 2, 0]:
		var tap := InputEventScreenTouch.new()
		tap.index = 4
		tap.pressed = true
		tap.position = workshop.tool_buttons[index].get_global_rect().get_center()
		var before_touch: int = workshop.selected_tool
		root.push_input(tap, true)
		check(workshop.selected_tool == before_touch and not workshop.brush_dragging, "Touch down waits for release without cleaning behind UI")
		tap.pressed = false
		root.push_input(tap, true)
		check(workshop.selected_tool == index and not workshop.brush_dragging, "Touch release equips tool without dragging behind UI")
	for index in [1, 2]:
		workshop.select_tool(index)
		workshop.begin_stroke(camera.unproject_position(Vector3(0, 0.067, -1.2)), false)
		workshop.move_brush_to_screen(camera.unproject_position(Vector3(0, 0.067, 1.2)), false)
		check(soil.active.is_empty() and soil.coverage_values[208 * 256 + 128] == 1.0, "Other tools do not invoke brush cleaning")
		workshop.move_brush_to_screen(camera.unproject_position(Vector3(1.8, 0.067, 0.2)), false)
		check(absf(anchor(workshop, index).y - (0.14 if index == 2 else 0.0)) < 0.0001, "Equipped tool lowers to tile surface")
		workshop.reset_rug()
		check(workshop.selected_tool == index and not workshop.brush_dragging, "Reset preserves selected item and ends dragging")
	workshop.select_tool(0)
	workshop.begin_stroke(camera.unproject_position(Vector3.ZERO), false)
	workshop.select_tool(1)
	check(not workshop.brush_dragging and not soil.pass_active, "Switching mid-drag closes the brush pass")
	workshop.toggle_view()
	workshop.move_brush_to_screen(camera.unproject_position(Vector3(0.3, 0.067, 0.4)) - workshop.TOUCH_CONTACT_OFFSET, true)
	check(anchor(workshop, 1).distance_to(Vector3(0.3, 0.067, 0.4)) < 0.001, "Selected tool follows touch in top view")
	print("TOOL SELECTION CHECKS COMPLETE: ", failures, " failures; mouse/touch buttons, equipped mesh contact, tile movement, selection and brush-only interaction.")
	workshop.free()
	quit(0 if failures == 0 else 1)
