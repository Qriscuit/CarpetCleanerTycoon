extends SceneTree
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CHECK FAILED: " + message)

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to keep player saves isolated")
		quit(2)
		return
	call_deferred("run")

func run() -> void:
	var workshop := (load("res://scenes/test/rug_cleaning_gym.tscn") as PackedScene).instantiate()
	workshop.animate_rug_changes = false
	root.add_child(workshop)
	await process_frame
	var soil: Node = workshop.soil
	# Exercise the production starter recipe through the gym's input harness.
	soil.configure_rug(load("res://resources/rugs/mint_meadow.tres"))
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
	check(absf(soil.coverage_values[208 * 256 + 128] - 0.9) < 0.001, "One long pass removes one tenth of the dust despite many events")
	var feather: float = soil.coverage_values[208 * 256 + 167]
	check(feather > 0.91 and feather < 0.99, "Cleaning edge has intermediate feathered opacity")
	soil.stroke(Vector3(0,0.067,-1.6), Vector3(0,0.067,1.6), 0.5)
	check(absf(soil.coverage_values[208 * 256 + 128] - 0.9) < 0.001, "Repeated input within the same pass does not remove another layer")
	for pass_number in range(2, 11):
		soil.end_pass()
		soil.begin_pass()
		soil.stroke(Vector3(0,0.067,-1.6), Vector3(0,0.067,1.6), 0.5)
		var expected := maxf(0.0, 1.0 - float(pass_number) * 0.1)
		check(absf(soil.coverage_values[208 * 256 + 128] - expected) < 0.001, "Separate pass %d removes exactly one additional layer" % pass_number)
	check(soil.coverage_values[208 * 256 + 128] == 0.0, "Tenth separate pass fully restores the original material")
	# A small oscillation used to award fresh layers on every 0.08-unit reversal.
	# Staying inside the brush's depth must not manufacture completed passes.
	workshop.reset_rug()
	soil.begin_pass()
	soil.stroke(Vector3(0,0.067,-0.12), Vector3(0,0.067,0), 0.02)
	var held_pass: int = soil.pass_serial
	for oscillation in 20:
		soil.stroke(Vector3(0,0.067,0), Vector3(0,0.067,-0.12), 0.02)
		soil.stroke(Vector3(0,0.067,-0.12), Vector3(0,0.067,0), 0.02)
	check(soil.pass_serial == held_pass and absf(soil.coverage_values[208 * 256 + 128] - 0.9) < 0.001, "Repeated tiny reversals cannot rapidly strip extra layers")
	# A deliberate reverse movement can accumulate across input events.
	soil.stroke(Vector3(0,0.067,0), Vector3(0,0.067,-0.12), 0.02)
	soil.stroke(Vector3(0,0.067,-0.12), Vector3(0,0.067,-0.24), 0.02)
	check(soil.pass_serial == held_pass + 1 and absf(soil.coverage_values[208 * 256 + 128] - 0.8) < 0.001, "A full brush-depth reversal starts exactly one additional pass")
	workshop.reset_rug()
	soil.begin_pass()
	soil.stroke(Vector3(0,0.067,-1.6), Vector3(0,0.067,1.6), 0.5)
	soil.stroke(Vector3(0,0.067,1.6), Vector3(0,0.067,-1.6), 0.5)
	check(absf(soil.coverage_values[208 * 256 + 128] - 0.8) < 0.001, "Back-and-forth without lifting counts as two of the ten passes")
	for pass_index in range(2, 10):
		var from_z := -1.6 if pass_index % 2 == 0 else 1.6
		soil.stroke(Vector3(0,0.067,from_z), Vector3(0,0.067,-from_z), 0.5)
	check(soil.coverage_values[208 * 256 + 128] == 0.0, "Ten alternating strokes clean a spot without requiring a lift")
	workshop.reset_rug()
	var seed_slot := -1
	for i in soil.initial_growth.size():
		if soil.initial_growth[i] > 0.1:
			seed_slot = i
			break
	check(seed_slot >= 0, "A visible seed is available for the brush-contact fixture")
	if seed_slot < 0:
		workshop.free()
		quit(1)
		return
	var p: Vector3 = soil.positions[seed_slot]
	var original_size: float = soil.growth[seed_slot]
	soil.refresh_visible_clumps()
	soil.stroke(p, p + Vector3(0,0,0.02), 0.1)
	check(soil.awakened[seed_slot] and soil.growth[seed_slot] == 1.0 and soil.render_dirty, "Brush contact makes the seeded clump full-sized and schedules its render before any physics tick")
	check(soil.positions[seed_slot] == p, "Seeded dirt appears at the current brush contact point")
	soil.refresh_visible_clumps()
	var contact_visible := false
	for instance in soil.batch.visible_instance_count:
		var pose: Transform3D = soil.batch.get_instance_transform(instance)
		if pose.origin.is_equal_approx(p) and pose.basis.get_scale().is_equal_approx(soil.initial[seed_slot].basis.get_scale()):
			contact_visible = true
	check(contact_visible, "The first render after brush contact contains the full-sized clump at its contact point")
	soil._physics_process(1.0 / 60.0)
	check(soil.growth[seed_slot] == 1.0 and soil.positions[seed_slot] != p, "Touched seed moves on the first physics tick without a growth delay")
	for tick in 120:
		soil._physics_process(1.0 / 60.0)
	check(soil.growth[seed_slot] == 1.0 and soil.positions[seed_slot] != p, "Launched dirt stays full-sized without time-based retirement")
	p = soil.positions[seed_slot]
	soil.stroke(p, p + Vector3(0,0,-0.02), 0.1)
	soil._physics_process(1.0 / 60.0)
	check(soil.growth[seed_slot] == 1.0 and soil.positions[seed_slot] != p, "Repeat contact moves immediately without growing again")
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
	check(soil.growth[seed_slot] == original_size and soil.remaining == 560 and workshop.dirty, "Reset restores seeds, progress and dust")
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
	print("FEEL CHECKS COMPLETE: ", failures, " failures; ten passes, jitter protection, input-rate independence, soft edges, immediate brush contact, rug silhouette and 100 percent completion.")
	workshop.free()
	quit(0 if failures == 0 else 1)

