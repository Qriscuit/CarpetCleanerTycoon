extends SceneTree
## Whole-carpet hose progress with bounded fresh-patch bonuses; extraction remains local.
## tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/validate_hose_painter_optimization.gd -- --shop-test
const Soil := preload("res://scripts/dirt_controller.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Refusing to run without --shop-test")
		quit(2)
		return
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func make_soil() -> Node:
	var soil := Soil.new()
	root.add_child(soil)
	var rug := Node3D.new()
	root.add_child(rug)
	soil.rug_node = rug
	soil.wet_recipe = true
	soil.skip_dry_stage = true
	var count: int = Soil.MASK_SIZE.x * Soil.MASK_SIZE.y
	soil.surface_pixels.resize(count)
	soil.coverage_values.resize(count)
	soil.water_values.resize(count)
	soil.extraction_values.resize(count)
	soil.mask = Image.create(Soil.MASK_SIZE.x, Soil.MASK_SIZE.y, false, Image.FORMAT_L8)
	soil.mask.fill(Color.BLACK)
	soil.wet_mask = Image.create(Soil.MASK_SIZE.x, Soil.MASK_SIZE.y, false, Image.FORMAT_L8)
	soil.extraction_mask = Image.create(Soil.MASK_SIZE.x, Soil.MASK_SIZE.y, false, Image.FORMAT_L8)
	soil.mask_texture = ImageTexture.create_from_image(soil.mask)
	soil.wet_texture = ImageTexture.create_from_image(soil.wet_mask)
	soil.extraction_texture = ImageTexture.create_from_image(soil.extraction_mask)
	for y in Soil.MASK_SIZE.y:
		for x in Soil.MASK_SIZE.x:
			var p := (Vector2(x + 0.5, y + 0.5) / Vector2(Soil.MASK_SIZE) - Vector2.ONE * 0.5) * Soil.RUG_HALF * 2.0
			if soil.footprint.contains_point(p):
				soil.surface_pixels[y * Soil.MASK_SIZE.x + x] = 1
				soil.surface_pixel_count += 1
	reset_soil(soil, "fresh")
	return soil

func reset_soil(soil: Node, mode: String) -> void:
	soil.wash_cycle = 0
	soil.global_water_level = 1.0 if mode == "saturated" else (0.37 if mode == "partial" else 0.0)
	soil.hose_patch_water.resize(Soil.HOSE_PATCH_SIZE.x * Soil.HOSE_PATCH_SIZE.y)
	soil.hose_patch_water.fill(soil.global_water_level)
	soil.water_coverage_total = soil.global_water_level * soil.surface_pixel_count
	soil.surface_coverage_total = 0.0
	soil.extraction_coverage_total = 0.0
	soil.coverage_values.fill(0.0)
	soil.extraction_values.fill(0.0)
	# Production global supply intentionally fills the whole native buffer.
	# Surface totals count only valid carpet; padding is not a cleaning target.
	soil.water_values.fill(soil.global_water_level)
	soil.wet_mask.fill(Color(soil.global_water_level, soil.global_water_level, soil.global_water_level))
	soil.extraction_mask.fill(Color.BLACK)
	if mode == "partial":
		# Nonzero extraction history makes the unchanged-mask guards meaningful.
		for y in Soil.MASK_SIZE.y:
			for x in Soil.MASK_SIZE.x:
				var index := y * Soil.MASK_SIZE.x + x
				if soil.surface_pixels[index] == 0: continue
				var extracted := float(index % 29) / 128.0
				soil.extraction_values[index] = extracted
				soil.extraction_coverage_total += soil.extraction_values[index]
				soil.extraction_mask.set_pixel(x, y, Color(extracted, extracted, extracted))
	soil.wet_mask_changed = false
	soil.extraction_mask_changed = false
	soil.mask_changed = false
	soil.set_process(false)

func pooled_ids(soil: Node) -> Array:
	return [soil.mask.get_instance_id(), soil.wet_mask.get_instance_id(), soil.extraction_mask.get_instance_id(),
		soil.mask_texture.get_instance_id(), soil.wet_texture.get_instance_id(), soil.extraction_texture.get_instance_id()]

func other_masks(soil: Node) -> Dictionary:
	return {"coverage": soil.coverage_values.duplicate(), "extraction": soil.extraction_values.duplicate(),
		"extraction_total": soil.extraction_coverage_total, "dry_image": soil.mask.get_data(),
		"extraction_image": soil.extraction_mask.get_data(), "dry_dirty": soil.mask_changed,
		"extraction_dirty": soil.extraction_mask_changed, "surface_total": soil.surface_coverage_total}

func uniform_expected(soil: Node, level: float, label: String) -> void:
	var expected := PackedFloat32Array()
	expected.resize(soil.water_values.size())
	expected.fill(level)
	var image := Image.create(Soil.MASK_SIZE.x, Soil.MASK_SIZE.y, false, Image.FORMAT_L8)
	image.fill(Color(level, level, level))
	check(soil.water_values == expected, "Exact native uniform water values: " + label)
	check(soil.wet_mask.get_data() == image.get_data(), "Exact native visible water bytes: " + label)
	check(is_equal_approx(soil.global_water_level, level), "Whole-rug level: " + label)
	check(is_equal_approx(soil.water_coverage_total, level * soil.surface_pixel_count), "Authoritative total counts valid surface only: " + label)
	check(absf(soil.water_clearance() - (level if soil.wet_recipe else 1.0)) < 0.000001, "Meter follows uniform supply or bypasses dry recipes: " + label)

# Independent coarse-grid oracle. The global supply stays uniform; only the
# optional acceleration tracks where direct hose water has landed this round.
func contact_expected(soil: Node, local_center: Vector3, radius: float, strength: float) -> Dictionary:
	var expected_patches: PackedFloat32Array = soil.hose_patch_water.duplicate()
	var level: float = soil.global_water_level
	var center := Vector2(local_center.x, local_center.z)
	var eligible: bool = soil.footprint.contains_point(center) and radius > 0.0 and is_finite(radius) and strength > 0.0 and is_finite(strength) and level < Soil.WET_STAGE_TARGET
	if not eligible:
		return {"level": level, "patches": expected_patches, "eligible": false}
	var touched: Array[int] = []
	var nearest := -1
	var nearest_distance := INF
	for y in Soil.HOSE_PATCH_SIZE.y:
		for x in Soil.HOSE_PATCH_SIZE.x:
			var point := (Vector2(x + 0.5, y + 0.5) / Vector2(Soil.HOSE_PATCH_SIZE) - Vector2.ONE * 0.5) * Soil.RUG_HALF * 2.0
			if not soil.footprint.contains_point(point):
				continue
			var index := y * Soil.HOSE_PATCH_SIZE.x + x
			var distance := point.distance_squared_to(center)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = index
			if distance <= radius * radius:
				touched.append(index)
	if touched.is_empty() and nearest >= 0:
		touched.append(nearest)
	var integrated_fresh := 0.0
	for index in touched:
		var old := float(expected_patches[index])
		var next := minf(1.0, old + strength / Soil.HOSE_PATCH_SATURATION)
		# Integral of remaining local dryness over the supplied water, rather
		# than a per-event reward that could increase with deposit frequency.
		integrated_fresh += (next - old) * (1.0 - (old + next) * 0.5) * Soil.HOSE_PATCH_SATURATION / strength
		expected_patches[index] = next
	var mean_fresh := integrated_fresh / maxf(float(touched.size()), 1.0)
	level = minf(1.0, level + strength * Soil.GLOBAL_WATER_GAIN * (1.0 + Soil.FRESH_WATER_BONUS * mean_fresh))
	if level >= Soil.WET_STAGE_TARGET:
		level = 1.0
		expected_patches.fill(1.0)
	return {"level": level, "patches": expected_patches, "eligible": true}

func check_patch_values(actual: PackedFloat32Array, expected: PackedFloat32Array, label: String) -> void:
	var maximum_error := 0.0
	check(actual.size() == expected.size(), "Fixed local history size: " + label)
	for index in mini(actual.size(), expected.size()):
		maximum_error = maxf(maximum_error, absf(actual[index] - expected[index]))
	check(maximum_error <= 0.000001, "Independent local exposure oracle: " + label)

func check_contact(soil: Node, local_center: Vector3, radius: float, strength: float, edge: float, label: String) -> void:
	var before_other := other_masks(soil)
	var before_ids := pooled_ids(soil)
	var expected := contact_expected(soil, local_center, radius, strength)
	var actual: bool = soil.apply_water_blob(soil.rug_node.to_global(local_center), radius, strength, edge)
	check(actual == bool(expected.eligible), "Contact result: " + label)
	uniform_expected(soil, float(expected.level), label)
	check_patch_values(soil.hose_patch_water, expected.patches, label)
	check(other_masks(soil) == before_other, "Dry and extraction values, images, totals and flags unchanged: " + label)
	check(pooled_ids(soil) == before_ids, "Image and texture pools retained: " + label)
	check(soil.wet_mask_changed == bool(expected.eligible) and soil.is_processing() == bool(expected.eligible), "Water dirty/processing flags: " + label)
func validate_contacts(soil: Node) -> void:
	var contacts := [
		[Vector3.ZERO, 0.17, 0.3, 0.18],
		[Vector3(0.82, 0, 1.25), 0.51, 0.3, 0.82],
		[Vector3(-0.75, 0, -1.2), 0.00001, 0.0037, 0.01],
		[Vector3(0, 0, 1.56), 0.23, 0.8, 0.01],
		[Vector3(4, 0, 4), 8.0, 0.5, 0.18],
		[Vector3(1.01, 0, 1.67), 0.14, 1.0, 1.0],
		[Vector3.ZERO, -0.1, 0.7, 0.2],
		[Vector3.ZERO, 0.0, 0.7, 0.2],
		[Vector3.ZERO, 0.24, 0.0, 0.2],
		[Vector3.ZERO, 0.24, -1.0, -1.0],
		[Vector3.ZERO, 0.24, 2.0, 2.0],
		[Vector3(0.82, 0, 1.25), 0.24, 9.261, 0.18],
		[Vector3.ZERO, 0.24, 100.0, 0.18],
		[Vector3.ZERO, 0.24, INF, 0.18],
		[Vector3.ZERO, 0.24, -INF, 0.18],
		[Vector3.ZERO, 0.24, NAN, 0.18],
		[Vector3.ZERO, 4.0, 1.0, 0.01],
	]
	for transform in [Transform3D.IDENTITY, Transform3D(Basis(Vector3.UP, 0.63), Vector3(2, 0.5, -3)), Transform3D(Basis(Vector3.UP, -0.91).scaled(Vector3(1.7, 0.8, 0.6)), Vector3(-2, 1.1, 4))]:
		soil.rug_node.transform = transform
		for mode in ["fresh", "partial", "saturated"]:
			for index in contacts.size():
				reset_soil(soil, mode)
				var args: Array = contacts[index]
				check_contact(soil, args[0], args[1], args[2], args[3], "%s transform=%s case=%d" % [mode, transform, index])
	soil.rug_node.transform = Transform3D.IDENTITY

func validate_steady_supply(soil: Node) -> void:
	var baseline := PackedFloat32Array()
	var baseline_bytes := PackedByteArray()
	var baseline_total := 0.0
	for center in [Vector3.ZERO, Vector3(0.82, 0, 1.25), Vector3(-0.75, 0, -1.2), Vector3(0, 0, 1.56)]:
		for radius in [0.00001, 0.19, 0.65]:
			reset_soil(soil, "fresh")
			for contact in 8:
				soil.wet_mask_changed = false
				soil.set_process(false)
				var previous: float = soil.water_clearance()
				var expected := contact_expected(soil, center, radius, 0.3)
				soil.apply_water_blob(soil.rug_node.to_global(center), radius, 0.3, 0.82)
				uniform_expected(soil, float(expected.level), "steady %s radius=%s contact=%d" % [center, radius, contact])
				check_patch_values(soil.hose_patch_water, expected.patches, "steady local exposure")
				var gain: float = soil.water_clearance() - previous
				check(gain >= 0.3 * Soil.GLOBAL_WATER_GAIN - 0.000001 and gain <= 0.3 * Soil.GLOBAL_WATER_GAIN * (1.0 + Soil.FRESH_WATER_BONUS) + 0.000001, "Every repeated corner/fringe contact gains steady base flow with a bounded optional bonus")
				if contact >= 5:
					check(absf(gain - 0.3 * Soil.GLOBAL_WATER_GAIN) < 0.000001, "A locally saturated patch keeps the constant base rate")
			if baseline.is_empty():
				baseline = soil.water_values.duplicate()
				baseline_bytes = soil.wet_mask.get_data()
				baseline_total = soil.water_coverage_total
			else:
				check(soil.water_values == baseline and soil.wet_mask.get_data() == baseline_bytes and soil.water_coverage_total == baseline_total, "Uniformly fresh repeated center, corner, fringe and radius contacts share the same whole-rug rate")
	reset_soil(soil, "fresh")
	var supplied := 0
	while not soil.water_stage_complete() and supplied < 100:
		check(soil.apply_water_blob(Vector3(0.82, 0, 1.25), 0.00001, 1.0), "Tiny repeated corner contact continues supplying the whole carpet")
		supplied += 1
	var expected_contacts := ceili((Soil.WET_STAGE_TARGET / Soil.GLOBAL_WATER_GAIN) - Soil.FRESH_WATER_BONUS * Soil.HOSE_PATCH_SATURATION * 0.5)
	check(supplied == expected_contacts and soil.water_stage_complete() and soil.water_stage_progress() == 1.0, "One corner eventually saturates every part of the rug at the slower base rate")
	uniform_expected(soil, 1.0, "complete corner soak")
	var before := other_masks(soil)
	var before_patches: PackedFloat32Array = soil.hose_patch_water.duplicate()
	soil.wet_mask_changed = false
	soil.set_process(false)
	check(not soil.apply_water_blob(Vector3.ZERO, 0.55, 1.0) and not soil.wet_mask_changed and not soil.is_processing(), "Saturated stage rejects extra water and stays asleep")
	check(other_masks(soil) == before and soil.hose_patch_water == before_patches, "Saturation never changes local history, extraction or dry work")

func validate_fresh_patch_bonus(soil: Node) -> void:
	check(Soil.GLOBAL_WATER_GAIN < 0.08 and Soil.GLOBAL_WATER_GAIN >= 0.06, "Constant base watering is modestly slower than the previous rate")
	check(Soil.FRESH_WATER_BONUS > 0.0 and Soil.FRESH_WATER_BONUS <= 0.25, "Fresh-patch acceleration is modest and capped")
	reset_soil(soil, "fresh")
	for contact in 12:
		check_contact(soil, Vector3.ZERO, 0.14, 0.3, 0.18, "held history %d" % contact)
		soil.wet_mask_changed = false
		soil.set_process(false)
	var held: float = soil.water_clearance()
	reset_soil(soil, "fresh")
	for contact in 12:
		var point := Vector3(-0.60 + float(contact % 4) * 0.40, 0, -0.90 + floorf(float(contact) / 4.0) * 0.90)
		check_contact(soil, point, 0.14, 0.3, 0.18, "fresh sweep %d" % contact)
		soil.wet_mask_changed = false
		soil.set_process(false)
	var swept: float = soil.water_clearance()
	check(swept > held * 1.08 and swept <= held * (1.0 + Soil.FRESH_WATER_BONUS) + 0.000001, "Equal landed water accelerates modestly when it reaches fresh sections")
	reset_soil(soil, "fresh")
	soil.apply_water_blob(Vector3.ZERO, 0.19, 2.1)
	var whole: float = soil.water_clearance()
	var whole_patches: PackedFloat32Array = soil.hose_patch_water.duplicate()
	reset_soil(soil, "fresh")
	for parcel in 8:
		soil.apply_water_blob(Vector3.ZERO, 0.19, 2.1 / 8.0)
	check(absf(soil.water_clearance() - whole) < 0.000001, "Splitting one stationary deposit retains total water and integrated freshness bonus")
	check_patch_values(soil.hose_patch_water, whole_patches, "partitioned stationary deposit")
	# Returning to used carpet retains base progress, while a new section gives
	# the optional boost even though rendered/global water is uniform everywhere.
	var used_before: float = soil.water_clearance()
	soil.apply_water_blob(Vector3.ZERO, 0.19, 0.3)
	var used_gain: float = soil.water_clearance() - used_before
	var fresh_before: float = soil.water_clearance()
	soil.apply_water_blob(Vector3(0.65, 0, 1.0), 0.19, 0.3)
	var fresh_gain: float = soil.water_clearance() - fresh_before
	check(absf(used_gain - 0.3 * Soil.GLOBAL_WATER_GAIN) < 0.000001 and fresh_gain > used_gain, "Returning to used sections cannot refresh their bonus")
func validate_strokes(soil: Node) -> void:
	for elapsed in [1.0 / 60.0, 0.08, 0.0, 0.001]:
		for power in [1.0, 4.41, 9.261]:
			var center_level := 0.0
			for center in [Vector3.ZERO, Vector3(0.82, 0, 1.25)]:
				reset_soil(soil, "fresh")
				soil.tool_strength = power
				var before := other_masks(soil)
				var seconds := clampf(elapsed if elapsed > 0.0 else 1.0 / 60.0, 1.0 / 240.0, 0.08)
				var expected := contact_expected(soil, center, Soil.WATER_HALF.x, seconds * Soil.WATER_RATE * power)
				soil.apply_water_stroke(center, center, elapsed)
				uniform_expected(soil, float(expected.level), "stationary stroke elapsed=%s power=%s center=%s" % [elapsed, power, center])
				check(other_masks(soil) == before, "Stationary hose keeps extraction and dry masks unchanged")
				if center == Vector3.ZERO: center_level = soil.water_clearance()
				else: check(soil.water_clearance() == center_level, "Stationary center and corner hose grow at the same rate")
	reset_soil(soil, "fresh")
	soil.apply_water_stroke(Vector3(4, 0, 4), Vector3(5, 0, 5), 0.08)
	uniform_expected(soil, 0.0, "off-rug stroke")
	check(not soil.wet_mask_changed and not soil.is_processing(), "Wholly off-carpet strokes never supply water")
	soil.tool_strength = 1.0

func validate_gates(soil: Node) -> void:
	for gate in ["wet_recipe", "completion_started", "simulation_suspended", "reveal_progress", "skip_dry_stage"]:
		reset_soil(soil, "fresh")
		var saved: Variant = soil.get(gate)
		soil.set(gate, 0.5 if gate == "reveal_progress" else not saved)
		if gate == "skip_dry_stage": soil.surface_coverage_total = soil.surface_pixel_count
		var before := other_masks(soil)
		var before_patches: PackedFloat32Array = soil.hose_patch_water.duplicate()
		check(not soil.apply_water_blob(Vector3.ZERO, 0.17, 0.3), "Gate blocks global blob supply: " + gate)
		soil.apply_water_stroke(Vector3.ZERO, Vector3(0.1, 0, 0.1), 0.08)
		uniform_expected(soil, 0.0, "blocked " + gate)
		check(other_masks(soil) == before and soil.hose_patch_water == before_patches and not soil.wet_mask_changed and not soil.is_processing(), "Gate leaves every mask and flag untouched: " + gate)
		soil.set(gate, saved)
	soil.surface_coverage_total = 0.0

func benchmark(soil: Node) -> void:
	var before_ids := pooled_ids(soil)
	for profile in ["direct", "wide_circle", "rapid_sweep", "saturated"]:
		var times: Array[int] = []
		for sample in 24:
			reset_soil(soil, "saturated" if profile == "saturated" else "fresh")
			var start := Time.get_ticks_usec()
			if profile == "rapid_sweep":
				for contact in 14: soil.apply_water_blob(Vector3(-0.65 + float(contact) * 0.09, 0, 0), 0.3, 0.05)
			else:
				soil.apply_water_blob(Vector3.ZERO, 0.55 if profile == "wide_circle" else 0.3, 0.14, 0.82 if profile == "wide_circle" else 0.18)
			times.append(Time.get_ticks_usec() - start)
		times.sort()
		print("HOSE_PAINTER_BENCH profile=%s current_median_us=%d current_p95_us=%d" % [profile, times[12], times[22]])
	check(pooled_ids(soil) == before_ids, "Repeated whole-rug fills retain every image/texture allocation")

func run() -> void:
	var soil := make_soil()
	validate_contacts(soil)
	validate_steady_supply(soil)
	validate_fresh_patch_bonus(soil)
	validate_strokes(soil)
	validate_gates(soil)
	benchmark(soil)
	soil.rug_node.free()
	soil.free()
	print("HOSE_PAINTER_OPTIMIZATION_VALIDATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
