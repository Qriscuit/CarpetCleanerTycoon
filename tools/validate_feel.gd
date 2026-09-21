extends SceneTree
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CHECK FAILED: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var workshop := (load("res://scenes/test/rug_cleaning_gym.tscn") as PackedScene).instantiate()
	workshop.animate_rug_changes = false
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
	soil.end_pass()
	soil.begin_pass()
	soil.stroke(Vector3(0,0.067,-1.6), Vector3(0,0.067,1.6), 0.5)
	check(soil.coverage_values[208 * 256 + 128] == 0.0, "Second separate pass restores original material")
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
	soil.remaining = 281
	soil.surface_coverage_total = float(soil.surface_pixel_count) * 0.5
	workshop.update_contract_status()
	check(workshop.dirty, "Below 50 percent is incomplete")
	soil.remaining = 280
	workshop.update_contract_status()
	check(workshop.dirty, "Exactly 50 percent is still incomplete")
	check(workshop.state_label.text == "50%" and workshop.progress_bar.value == 50.0, "Meter and number reflect combined cleanliness")
	check(soil.coverage_values[0] == 1.0, "Completion never auto-erases untouched surface dust")
	workshop.reset_rug()
	check(soil.growth[1] == original_size and soil.remaining == 560 and workshop.dirty, "Reset restores seeds, progress and dust")
	for overhead in [false, true]:
		workshop.overhead = overhead
		workshop.frame_carpet()
		check(workshop.overhead and is_equal_approx(workshop.camera.rotation_degrees.x, -90.0), "Gameplay remains locked overhead")
	workshop.overhead = false
	workshop.frame_carpet()
	for fraction in [0.0, 1.0 / 3.0, 2.0 / 3.0, 0.98]:
		soil.remaining = roundi(float(soil.initial.size()) * (1.0 - fraction))
		soil.surface_coverage_total = float(soil.surface_pixel_count) * (1.0 - fraction)
		workshop.update_contract_status()
		check(workshop.progress_fill.bg_color.is_equal_approx(workshop.progress_color(workshop.progress_fraction)), "Bar follows the live red-yellow-green-blue gradient")
		await process_frame
		check(workshop.progress_card.get_global_rect().encloses(workshop.state_label.get_global_rect()), "Stable top-left number remains inside its editor-authored card")
		check(workshop.progress_fill.shadow_size > 0 and workshop.progress_fill.shadow_color.a > 0.0, "Progress fill has a matching glow")
	print("FEEL CHECKS COMPLETE: ", failures, " failures; two passes, soft edges, seeded growth, rug silhouette and 100 percent completion.")
	workshop.free()
	quit(0 if failures == 0 else 1)

