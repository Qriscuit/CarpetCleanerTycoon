extends SceneTree
## Tool models remain usable by gameplay code while the production picker is hidden.
var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CHECK FAILED: " + message)


func anchor(workshop: Node, index: int) -> Vector3:
	return workshop.tool_nodes[index].to_global(workshop.TOOL_PIVOTS[index])


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var workshop := (load("res://scenes/test/rug_cleaning_gym.tscn") as PackedScene).instantiate()
	workshop.animate_rug_changes = false
	root.add_child(workshop)
	await process_frame
	var camera: Camera3D = workshop.camera
	var soil: Node = workshop.soil
	check(workshop.tool_buttons.is_empty() and workshop.hud.get_node_or_null("%ToolRail") == null, "The cleaning window has no tool-picker UI")
	workshop.move_brush_to_screen(camera.unproject_position(Vector3(0, 0.067, 0.15)), false)
	for index in 3:
		var old_contact: Vector3 = workshop.contact_point
		workshop.select_tool(index)
		check(workshop.selected_tool == index, "Gameplay code equips the requested practice tool")
		check(workshop.contact_point.is_equal_approx(old_contact), "Switch retains the working contact point")
		check(not workshop.brush_dragging and soil.active.is_empty(), "Switching never starts a cleaning stroke")
		for other in 3:
			check(workshop.tool_nodes[other].visible == (index == other), "Exactly one model is visible")
		var expected: Vector3 = workshop.contact_point + Vector3.UP * (0.14 if index == 2 else 0.0)
		check(anchor(workshop, index).distance_to(expected) < 0.0001, "Blade, bristles, or nozzle align to the contact point")
		var lowest := INF
		for mesh in workshop.tool_nodes[index].get_children():
			if mesh is MeshInstance3D:
				for vertex in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					lowest = minf(lowest, mesh.to_global(vertex).y)
		check(absf(lowest - 0.067) < 0.002 if index < 2 else lowest > 0.067, "The model touches the rug or hovers safely")

	for index in [1, 2]:
		workshop.select_tool(index)
		workshop.begin_stroke(camera.unproject_position(Vector3(0, 0.067, -1.2)), false)
		workshop.move_brush_to_screen(camera.unproject_position(Vector3(0, 0.067, 1.2)), false)
		check(soil.active.is_empty() and soil.coverage_values[208 * 256 + 128] == 1.0, "Preview tools do not invoke brush cleaning")
		workshop.move_brush_to_screen(camera.unproject_position(Vector3(1.8, 0.067, 0.2)), false)
		check(absf(anchor(workshop, index).y - (0.14 if index == 2 else 0.0)) < 0.0001, "Selected tool follows over the tile surface")
		workshop.reset_rug()
		check(workshop.selected_tool == index and not workshop.brush_dragging, "Reset preserves the selected practice model")
	workshop.select_tool(0)
	workshop.begin_stroke(camera.unproject_position(Vector3.ZERO), false)
	workshop.select_tool(1)
	check(not workshop.brush_dragging and not soil.pass_active, "Switching mid-drag closes the brush pass")
	workshop.move_brush_to_screen(camera.unproject_position(Vector3(0.3, 0.067, 0.4)) - workshop.TOUCH_CONTACT_OFFSET, true)
	check(anchor(workshop, 1).distance_to(Vector3(0.3, 0.067, 0.4)) < 0.001, "Selected model follows touch in top view")
	print("TOOL MODEL CHECKS COMPLETE: ", failures, " failures; hidden picker, model contact, selection API and brush-only cleaning.")
	workshop.free()
	quit(0 if failures == 0 else 1)
