extends SceneTree
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CHECK FAILED: " + message)

func _initialize() -> void:
	call_deferred("run")

func capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../art/renders/" + filename))

func run() -> void:
	var workshop := (load("res://scenes/rug_cleaning_gym.tscn") as PackedScene).instantiate()
	root.add_child(workshop)
	await process_frame
	var soil: Node = workshop.soil
	check(workshop.get_node("RugDisplay").position == Vector3.ZERO, "Rug is at world origin")
	var visible_seeds := 0
	for amount in soil.growth:
		if amount > 0.1:
			visible_seeds += 1
	check(visible_seeds == 25, "Only 25 tiny starter rocks visibly seeded")
	check(soil.footprint.contains_point(Vector2.ZERO), "Rug center is inside")
	check(not soil.footprint.contains_point(Vector2(0.99, 1.49)), "Empty rounded corner is outside")
	check(not soil.footprint.contains_point(Vector2(0.067, 1.57)), "Gap between fringe tassels is outside")
	check(soil.footprint.contains_point(Vector2(0, 1.57)), "Actual fringe tassel is inside")
	check(soil.is_fully_outside(Vector3(0.99, 0, 1.49), 0.005), "Small clump outside curved corner is clear")
	check(not soil.is_fully_outside(Vector3(0.997, 0, 0), 0.015), "Clump touching binding is still inside")
	# Many input events in one pass must not multiply cleaning strength.
	soil.begin_pass()
	for step in 40:
		soil.stroke(Vector3(0,0.067,-1.6 + step * 0.08), Vector3(0,0.067,-1.52 + step * 0.08), 0.02)
	check(absf(soil.coverage_values[208 * 256 + 128] - 0.5) < 0.001, "One long pass leaves half the dust despite many events")
	var feather: float = soil.coverage_values[208 * 256 + 167]
	check(feather > 0.55 and feather < 0.95, "Cleaning edge has intermediate feathered opacity")
	await capture("two_pass_first.png")
	soil.end_pass()
	soil.begin_pass()
	soil.stroke(Vector3(0,0.067,-1.6), Vector3(0,0.067,1.6), 0.5)
	check(soil.coverage_values[208 * 256 + 128] == 0.0, "Second separate pass restores original material")
	await capture("two_pass_second.png")
	workshop.reset_rug()
	soil.begin_pass()
	soil.stroke(Vector3(0,0.067,-1.6), Vector3(0,0.067,1.6), 0.5)
	soil.stroke(Vector3(0,0.067,1.6), Vector3(0,0.067,-1.6), 0.5)
	check(soil.coverage_values[208 * 256 + 128] == 0.0, "Back-and-forth without lifting counts as two passes")
	workshop.reset_rug()
	var p: Vector3 = soil.positions[1]
	var original_size: float = soil.growth[1]
	soil.stroke(p, p + Vector3(0,0,0.02), 0.1)
	soil._physics_process(1.0 / 60.0)
	check(soil.growth[1] > original_size and soil.growth[1] < 1.0, "Touched seed grows smoothly")
	check(soil.positions[1] == p, "Clump finishes growing before launch")
	for tick in 240:
		soil._physics_process(1.0 / 60.0)
	check(soil.growth[1] == 1.0 and soil.positions[1] != p, "Growth caps at 1 and clump moves")
	p = soil.positions[1]
	soil.stroke(p, p + Vector3(0,0,-0.02), 0.1)
	soil._physics_process(1.0 / 60.0)
	check(soil.growth[1] == 1.0 and soil.positions[1] != p, "Repeat contact moves immediately without growing again")
	workshop.update_progress(281, 560)
	check(workshop.dirty, "Below 50 percent is incomplete")
	workshop.update_progress(280, 560)
	check(workshop.dirty, "Exactly 50 percent is still incomplete")
	check(workshop.state_label.text == "50%" and workshop.progress_bar.value == 50.0 and not workshop.completion_icon.visible, "Meter and number reflect cleanliness")
	check(soil.coverage_values[0] == 1.0, "Completion never auto-erases untouched surface dust")
	workshop.reset_rug()
	check(soil.growth[1] == original_size and soil.remaining == 560 and workshop.dirty, "Reset restores seeds, progress and dust")
	for overhead in [false, true]:
		workshop.overhead = overhead
		workshop.frame_carpet()
		check(workshop.overhead and is_equal_approx(workshop.camera.rotation_degrees.x, -90.0), "Gameplay remains locked overhead")
	workshop.overhead = false
	workshop.frame_carpet()
	for stage in 4:
		workshop.update_progress(300 - stage * 100, 300)
		check(workshop.progress_fill.bg_color.is_equal_approx(workshop.PROGRESS_COLORS[stage]), "Bar follows red-yellow-green-blue color stops")
		check(workshop.state_label.get_theme_color("font_color").is_equal_approx(workshop.progress_fill.bg_color), "Number matches bar color")
		await process_frame
		var marker_center: float = workshop.progress_value_marker.position.x + workshop.progress_value_marker.size.x * 0.5
		var expected_center: float = lerpf(workshop.progress_value_marker.size.x * 0.5, workshop.progress_track.size.x - workshop.progress_value_marker.size.x * 0.5, stage / 3.0)
		check(absf(marker_center - expected_center) < 0.5, "Number follows the bar fill while staying inside its track")
		check(workshop.progress_fill.shadow_size > 0 and workshop.progress_fill.shadow_color.a > 0.0, "Progress fill has a matching glow")
		await capture("cleanliness_meter_%d.png" % stage)
	print("FEEL CHECKS COMPLETE: ", failures, " failures; two passes, soft edges, seeded growth, rug silhouette and 100 percent completion.")
	workshop.free()
	quit(0 if failures == 0 else 1)

