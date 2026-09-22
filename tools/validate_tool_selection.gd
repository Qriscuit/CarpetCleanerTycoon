extends SceneTree
## Each gym exercise exposes its own tools with the same surface contact rules.
var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CHECK FAILED: " + message)


func anchor(workshop: Node, index: int) -> Vector3:
	return workshop.tool_nodes[index].to_global(workshop.TOOL_PIVOTS[index])


func saturate_wet_rug(workshop: Node, soil: Node) -> void:
	# Use the public blob-painting path with a radius that covers every valid
	# footprint pixel, avoiding timing or renderer dependence in this model test.
	check(soil.apply_water_blob(Vector3(0.0, 0.067, 0.0), 5.0), "A deterministic water blob saturates the practice rug")
	soil._process(0.0)
	workshop.update_contract_status()


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var workshop := (load("res://scenes/test/rug_cleaning_gym.tscn") as PackedScene).instantiate()
	workshop.animate_rug_changes = false
	root.add_child(workshop)
	await process_frame
	var camera: Camera3D = workshop.camera
	var soil: Node = workshop.soil
	check(workshop.tool_buttons.size() == 3 and workshop.rug_buttons.size() == 2, "The gym exposes two exercises and their practice tools")
	workshop.move_brush_to_screen(camera.unproject_position(Vector3(0, 0.067, 0.15)), false)
	for index in 3:
		workshop.select_rug(0 if index == 0 else 1)
		var old_contact: Vector3 = workshop.contact_point
		if index == 1:
			saturate_wet_rug(workshop, soil)
		workshop.select_tool(index)
		check(workshop.selected_tool == index, "Gameplay code equips the requested practice tool")
		check(workshop.contact_point.is_equal_approx(old_contact), "Switch retains the working contact point")
		check(not workshop.brush_dragging and soil.active.is_empty(), "Switching never starts a cleaning stroke")
		for other in 3:
			check(workshop.tool_nodes[other].visible == (index == other), "Exactly one model is visible")
		var expected: Vector3 = workshop.contact_point + Vector3.UP * (workshop.WaterJet.LAUNCH_HEIGHT if index == 2 else 0.0)
		check(anchor(workshop, index).distance_to(expected) < 0.0001, "Blade, bristles, or nozzle align to the contact point")
		var lowest := INF
		for mesh in workshop.tool_nodes[index].get_children():
			if mesh is MeshInstance3D:
				for vertex in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					lowest = minf(lowest, mesh.to_global(vertex).y)
		check(absf(lowest - 0.067) < 0.002 if index < 2 else lowest > 0.067, "The model touches the rug or hovers safely")

	workshop.select_rug(1)
	check(workshop.selected_tool == 2 and not soil.water_stage_complete(), "The wet exercise starts with the hose")
	var extraction_before_gate: PackedFloat32Array = soil.extraction_values.duplicate()
	var wet_mask_before_gate := hash(soil.wet_mask.get_data())
	workshop.select_tool(1)
	check(workshop.selected_tool == 2 and workshop.hud.control("GymSqueegee").disabled, "The squeegee cannot be selected before full water coverage")
	soil.apply_squeegee_stroke(Vector3(0.0, 0.067, -1.2), Vector3(0.0, 0.067, 1.2), 0.08)
	check(soil.extraction_values == extraction_before_gate and hash(soil.wet_mask.get_data()) == wet_mask_before_gate, "A pre-gate squeegee request is a complete no-op")

	workshop.begin_stroke(camera.unproject_position(Vector3(0, 0.067, -1.2)), false)
	workshop.move_brush_to_screen(camera.unproject_position(Vector3(0, 0.067, 1.2)), false)
	check(soil.active.is_empty() and soil.coverage_values[208 * 256 + 128] == 0.0, "The hose does not invoke brush cleaning")
	workshop.move_brush_to_screen(camera.unproject_position(Vector3(1.8, 0.067, 0.2)), false)
	check(absf(anchor(workshop, 2).y - workshop.WaterJet.LAUNCH_HEIGHT) < 0.0001, "The selected hose follows safely above the tile surface")
	workshop.end_stroke()

	saturate_wet_rug(workshop, soil)
	check(soil.water_stage_complete() and soil.recommended_tool() == 1, "Full wet coverage unlocks the extraction stage")
	workshop.select_tool(1)
	check(workshop.selected_tool == 1 and not workshop.hud.control("GymSqueegee").disabled, "The squeegee can be selected after the water gate")
	var extraction_at_gate: float = soil.extraction_clearance()
	var wet_mask_at_gate := hash(soil.wet_mask.get_data())
	workshop.begin_stroke(camera.unproject_position(Vector3(0, 0.067, -1.2)), false)
	workshop.move_brush_to_screen(camera.unproject_position(Vector3(0, 0.067, 1.2)), false)
	workshop.end_stroke()
	check(soil.active.is_empty() and soil.coverage_values[208 * 256 + 128] == 0.0, "The squeegee does not invoke brush cleaning")
	check(soil.extraction_clearance() > extraction_at_gate and hash(soil.wet_mask.get_data()) != wet_mask_at_gate, "An enabled squeegee removes water through the shared wet mask")
	workshop.reset_rug()
	check(workshop.selected_tool == 2 and not workshop.brush_dragging, "Reset returns the wet exercise to the hose")
	check(soil.water_clearance() == 0.0 and soil.extraction_clearance() == 0.0 and workshop.hud.control("GymSqueegee").disabled, "Reset clears wet progress and gates the squeegee again")
	workshop.select_rug(0)
	workshop.begin_stroke(camera.unproject_position(Vector3.ZERO), false)
	workshop.select_rug(1)
	saturate_wet_rug(workshop, soil)
	workshop.select_tool(1)
	check(not workshop.brush_dragging and not soil.pass_active, "Switching mid-drag closes the brush pass")
	workshop.move_brush_to_screen(camera.unproject_position(Vector3(0.3, 0.067, 0.4)) - workshop.TOUCH_CONTACT_OFFSET, true)
	check(anchor(workshop, 1).distance_to(Vector3(0.3, 0.067, 0.4)) < 0.001, "Selected model follows touch in top view")
	print("TOOL MODEL CHECKS COMPLETE: ", failures, " failures; gated wet tools, model contact, selection API and brush-only cleaning.")
	workshop.free()
	quit(0 if failures == 0 else 1)
