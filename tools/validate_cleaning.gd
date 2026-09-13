extends SceneTree

var workshop: Node3D
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CHECK FAILED: " + message)

func settle(soil: Node) -> void:
	# Deterministic 60 Hz integration of the production motion code.
	for tick in 300:
		if not soil.is_physics_processing():
			break
		soil._physics_process(1.0 / 60.0)

func screenshot(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../art/renders/" + filename))

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	workshop = (load("res://scenes/rug_cleaning_gym.tscn") as PackedScene).instantiate()
	root.add_child(workshop)
	await process_frame
	var soil: Node = workshop.soil
	var camera: Camera3D = workshop.camera
	var brush: Node3D = workshop.brush
	check(soil.remaining == 560, "All 560 clumps initially dirty")
	check(soil.active.is_empty() and not soil.is_physics_processing(), "No idle simulation")
	check(workshop.get_node("WhiteTileFloor/CeramicTiles_576_Instances").multimesh.buffer.size() == 576 * 16, "Tiles saved as a single instanced batch")
	check(soil.batch.mesh.get_aabb().position.y >= -0.001, "Dirt pivot lies on surface")
	var tile_mesh: Mesh = workshop.get_node("WhiteTileFloor/CeramicTiles_576_Instances").multimesh.mesh
	var tile_arrays := tile_mesh.surface_get_arrays(0)
	# Shared corner normals are tilted by the bevel; test the face winding separately.
	check(tile_arrays[Mesh.ARRAY_NORMAL][-1].y > 0.8, "Smoothed tile corner normal points upward")
	var vertices: PackedVector3Array = tile_arrays[Mesh.ARRAY_VERTEX]
	var top_normal := -(vertices[-2] - vertices[-3]).cross(vertices[-1] - vertices[-3]).normalized()
	check(top_normal.y > 0.99, "Tile top face has upward clockwise winding")
	print("CLUMP AABB: ", soil.batch.mesh.get_aabb())
	# Click placement does not fling a path from the home position.
	workshop.begin_stroke(camera.unproject_position(Vector3(0, 0.067, -1.8)), false)
	check(soil.active.is_empty(), "Press alone never flings dirt")
	workshop.move_brush_to_screen(camera.unproject_position(Vector3(0.1, 0.067, 1.8)), false)
	check(brush.position.z > 1.5, "Brush travels beyond the lower fringe")
	check(is_equal_approx(brush.position.y + 0.0054, 0.0), "Brush tips touch tile height")
	check(not soil.active.is_empty(), "Fast swept brush catches dirt between events")
	for i in soil.active:
		check(soil.velocities[i].z > 0 and absf(soil.velocities[i].x) < soil.velocities[i].z * 0.6, "Positive Z fling with bounded X scatter")
	check(soil.remaining == 560, "Contact alone does not count as removed")
	workshop.end_stroke()
	settle(soil)
	check(soil.remaining > 0 and soil.remaining < 560, "Only flung-off clumps count")
	check(absf(soil.mask.get_pixel(128, 208).r - 0.5) < 0.01, "First pass removes half the dust")
	await screenshot("cleaning_partial.png")
	# A negative stroke and touch input use the same world projection.
	workshop.reset_rug()
	var screen: Vector2 = camera.unproject_position(Vector3(0.0, 0.067, 0.7)) - workshop.TOUCH_CONTACT_OFFSET
	var press := InputEventScreenTouch.new()
	press.index = 3
	press.pressed = true
	press.position = screen
	workshop._unhandled_input(press)
	var other := InputEventScreenTouch.new()
	other.index = 4
	other.pressed = false
	workshop._input(other)
	check(workshop.brush_dragging and workshop.active_touch == 3, "Other fingers cannot release the active stroke")
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = camera.unproject_position(Vector3(-0.1, 0.067, -2.8)) - workshop.TOUCH_CONTACT_OFFSET
	workshop._input(drag)
	check(brush.position.z < -2.5, "Touch can move brush beyond the upper edge")
	for i in soil.active:
		check(soil.velocities[i].z < 0 and absf(soil.velocities[i].x) < absf(soil.velocities[i].z) * 0.6, "Negative Z fling with bounded X scatter")
	press.pressed = false
	workshop._input(press)
	check(not workshop.brush_dragging, "Owning touch release stops brush")
	settle(soil)
	# Large radius must fully clear even the fringe, not just cross its center.
	check(not soil.is_fully_outside(Vector3(0, 0, 1.70), 0.10), "Overlapping clumps remain dirty")
	check(soil.is_fully_outside(Vector3(0, 0, 1.77), 0.10), "Whole clump beyond fringe is outside")
	# Sweep all lanes; don't call any completion/debug shortcut.
	workshop.reset_rug()
	for lane in [-0.85, -0.42, 0.0, 0.42, 0.85]:
		workshop.begin_stroke(camera.unproject_position(Vector3(lane, 0.067, -2.5)), false)
		workshop.move_brush_to_screen(camera.unproject_position(Vector3(lane, 0.067, 1.85)), false)
		workshop.end_stroke()
		settle(soil)
	check(soil.remaining == 0, "Every clump can be removed with real brush strokes")
	check(not workshop.dirty and workshop.state_label.text == "100%" and workshop.completion_icon.visible, "Full clearance shows 100% and completion check")
	check(soil.active.is_empty() and not soil.is_physics_processing(), "Settled dirt costs no simulation ticks")
	for i in soil.positions.size():
		check(soil.clump_is_outside(i), "All final clump footprints outside the rug")
	await screenshot("cleaning_complete.png")
	workshop.reset_rug()
	check(soil.remaining == 560 and workshop.dirty, "Reset restores dirt and progress")
	check(soil.mask.get_pixel(64, 100).r > 0.9, "Reset restores full soil cover")
	# Sub-pixel, slow strokes must still move dirt in the current direction.
	var clump: Vector3 = soil.positions[0] + soil.rug_origin
	soil.stroke(clump, clump + Vector3(0, 0, -0.001), 0.016)
	check(soil.active.has(0) and soil.velocities[0].z < 0, "Slow negative stroke catches dirt and reverses direction")
	workshop.reset_rug()
	workshop.begin_stroke(camera.unproject_position(Vector3.ZERO), false)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	workshop._input(release)
	check(not workshop.brush_dragging, "Release caught before GUI handling")
	workshop.begin_stroke(camera.unproject_position(Vector3.ZERO), false)
	workshop._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not workshop.brush_dragging, "Focus loss cancels drag")
	workshop.toggle_view()
	workshop.move_brush_to_screen(camera.unproject_position(Vector3(1.8, 0.067, 0)), false)
	check(absf(brush.position.x - 1.8) < 0.01, "Top-view projection also reaches tiles")
	print("CLEANING CHECKS COMPLETE: ", failures, " failures; mouse/touch, swept hits, both fling directions, surface contact, full removal, reset and idle sleep.")
	workshop.free()
	quit(0 if failures == 0 else 1)

