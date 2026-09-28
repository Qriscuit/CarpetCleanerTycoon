extends SceneTree
## Exact-output comparison with the original hose mask painter, without a renderer.
## tools/run_godot.ps1 --headless --path CarpetToy --script ../tools/validate_hose_painter_optimization.gd -- --shop-test
const Soil := preload("res://scripts/dirt_controller.gd")
var checks := 0
var failures := 0

class OriginalSoil:
	extends "res://scripts/dirt_controller.gd"

	func apply_water_blob(world_center: Vector3, radius: float, strength: float = 1.0, edge_fraction: float = WATER_BLOB_EDGE_FRACTION) -> bool:
		# Frozen 2026-09-27 implementation. Do not share optimized helpers.
		if not wet_recipe or (not skip_dry_stage and minf(unique_clearance(), surface_clearance()) < WET_STAGE_TARGET):
			return false
		if completion_started or simulation_suspended or reveal_progress < 1.0 or radius <= 0.0:
			return false
		var center3 := rug_node.to_local(world_center)
		var center := Vector2(center3.x, center3.z)
		var low := (center - Vector2.ONE * radius + RUG_HALF) / (RUG_HALF * 2.0)
		var high := (center + Vector2.ONE * radius + RUG_HALF) / (RUG_HALF * 2.0)
		var from_pixel := Vector2i((low * Vector2(MASK_SIZE)).floor()).clamp(Vector2i.ZERO, MASK_SIZE)
		var to_pixel := Vector2i((high * Vector2(MASK_SIZE)).ceil()).clamp(Vector2i.ZERO, MASK_SIZE)
		var amount := clampf(strength, 0.0, 1.0)
		var inner_radius := radius * (1.0 - clampf(edge_fraction, 0.01, 1.0))
		var any_changed := false
		for y in range(from_pixel.y, to_pixel.y):
			for x in range(from_pixel.x, to_pixel.x):
				var index := y * MASK_SIZE.x + x
				if surface_pixels[index] == 0:
					continue
				var loosened := 1.0 - coverage_values[index]
				var old_water := water_values[index]
				if old_water >= loosened:
					continue
				var point := (Vector2(x + 0.5, y + 0.5) / Vector2(MASK_SIZE) - Vector2.ONE * 0.5) * RUG_HALF * 2.0
				var distance := point.distance_to(center)
				if distance >= radius:
					continue
				var weight := 1.0 - smoothstep(inner_radius, radius, distance)
				var new_water := minf(loosened, old_water + amount * weight)
				if new_water <= old_water:
					continue
				water_values[index] = new_water
				water_coverage_total += new_water - old_water
				var visible_water := clampf(new_water - extraction_values[index], 0.0, 1.0)
				wet_mask.set_pixel(x, y, Color(visible_water, visible_water, visible_water))
				any_changed = true
		if any_changed:
			wet_mask_changed = true
			set_process(true)
		return any_changed

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

func make_soil(original: bool) -> Node:
	var soil := OriginalSoil.new() if original else Soil.new()
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
	for y in Soil.MASK_SIZE.y:
		for x in Soil.MASK_SIZE.x:
			var p := (Vector2(x + 0.5, y + 0.5) / Vector2(Soil.MASK_SIZE) - Vector2.ONE * 0.5) * Soil.RUG_HALF * 2.0
			if soil.footprint.contains_point(p):
				soil.surface_pixels[y * Soil.MASK_SIZE.x + x] = 1
				soil.surface_pixel_count += 1
	reset_soil(soil, "fresh")
	return soil

func reset_soil(soil: Node, mode: String) -> void:
	soil.water_coverage_total = 0.0
	soil.coverage_values.fill(0.0)
	soil.extraction_values.fill(0.0)
	soil.water_values.fill(0.0)
	soil.wet_mask.fill(Color.BLACK)
	if mode != "fresh":
		for y in Soil.MASK_SIZE.y:
			for x in Soil.MASK_SIZE.x:
				var index := y * Soil.MASK_SIZE.x + x
				if soil.surface_pixels[index] == 0:
					continue
				var dirt := float(index % 37) / 51.0 if mode == "partial" else 0.0
				var water := 1.0 if mode == "saturated" else float(index % 43) / 71.0
				water = minf(water, 1.0 - dirt)
				var extracted := water * 0.37 if mode == "partial" else 0.0
				soil.coverage_values[index] = dirt
				soil.water_values[index] = water
				soil.extraction_values[index] = extracted
				soil.water_coverage_total += soil.water_values[index]
				var visible := clampf(water - soil.extraction_values[index], 0.0, 1.0)
				soil.wet_mask.set_pixel(x, y, Color(visible, visible, visible))
	soil.wet_mask_changed = false
	soil.mask_changed = false
	soil.set_process(false)

func compare(actual: Node, reference: Node, args: Array, label: String) -> void:
	var center: Vector3 = actual.rug_node.to_global(args[0])
	var expected: bool = reference.apply_water_blob(center, args[1], args[2], args[3])
	var result: bool = actual.apply_water_blob(center, args[1], args[2], args[3])
	check(result == expected, "Return value: " + label)
	check(actual.water_values == reference.water_values, "Exact water mask: " + label)
	check(actual.water_coverage_total == reference.water_coverage_total, "Exact authoritative water total: " + label)
	check(actual.wet_mask.get_data() == reference.wet_mask.get_data(), "Exact visible water pixels: " + label)
	check(actual.coverage_values == reference.coverage_values and actual.extraction_values == reference.extraction_values, "Other masks unchanged: " + label)
	check(actual.wet_mask_changed == reference.wet_mask_changed and actual.is_processing() == reference.is_processing(), "Dirty/processing flags: " + label)
	check(actual.mask.get_data() == reference.mask.get_data() and actual.mask_changed == reference.mask_changed, "Dry image unchanged: " + label)

func run() -> void:
	var actual := make_soil(false)
	var reference := make_soil(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260927
	var cases := [
		[Vector3.ZERO, 0.17, 0.3, 0.18],
		[Vector3(0.8, 0, 1.4), 0.51, 0.1, 0.82],
		[Vector3(-0.98, 0, -1.63), 0.23, 0.8, 0.01],
		[Vector3(1.01, 0, 1.67), 0.14, 1.0, 1.0],
		[Vector3(5, 0, 5), 0.3, 0.5, 0.18],
		[Vector3.ZERO, 0.00001, 0.7, 0.2],
		[Vector3.ZERO, -0.1, 0.7, 0.2],
		[Vector3.ZERO, 0.0, 0.7, 0.2],
		[Vector3.ZERO, 0.24, 0.0, 0.2],
		[Vector3.ZERO, 0.24, -1.0, -1.0],
		[Vector3.ZERO, 0.24, 2.0, 2.0],
		[Vector3(-0.21, 0, 0.73), 0.24, 0.0037, 0.0001],
		[Vector3.ZERO, 4.0, 1.0, 0.01],
		[Vector3(-0.96, 0, 1.63), 1.2, 0.005, 0.82],
	]
	var pixel_point := (Vector2(153.5, 272.5) / Vector2(Soil.MASK_SIZE) - Vector2.ONE * 0.5) * Soil.RUG_HALF * 2.0
	cases.append([Vector3(pixel_point.x, 0.0, pixel_point.y), 0.00001, 0.7, 0.2])
	for boundary_offset in [-0.0000001, 0.0, 0.0000001]:
		cases.append([Vector3.ZERO, pixel_point.length() + boundary_offset, 0.7, 0.18])
	for i in 24:
		cases.append([Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.8, 1.8)), rng.randf_range(0.05, 0.64), rng.randf_range(0.001, 0.81), rng.randf_range(0.01, 1.0)])
	# Identity, rotated/translated, and nonuniformly scaled local-space mapping.
	for transform in [Transform3D.IDENTITY, Transform3D(Basis(Vector3.UP, 0.63), Vector3(2, 0.5, -3)), Transform3D(Basis(Vector3.UP, -0.91).scaled(Vector3(1.7, 0.8, 0.6)), Vector3(-2, 1.1, 4))]:
		actual.rug_node.transform = transform
		reference.rug_node.transform = transform
		for mode in ["fresh", "partial", "saturated", "overlap"]:
			reset_soil(actual, "fresh" if mode == "overlap" else mode)
			reset_soil(reference, "fresh" if mode == "overlap" else mode)
			for i in cases.size():
				# Keep random overlap cases meaningful: the full-rug stamp would
				# otherwise saturate every pixel before those cases are exercised.
				if mode == "overlap" and float(cases[i][1]) > 2.0:
					continue
				if mode == "fresh" or mode == "partial":
					reset_soil(actual, mode)
					reset_soil(reference, mode)
				compare(actual, reference, cases[i], "%s transform=%s case=%d" % [mode, transform, i])
	for soil in [actual, reference]:
		soil.rug_node.transform = Transform3D.IDENTITY
	for gate in ["wet_recipe", "completion_started", "simulation_suspended", "reveal_progress", "skip_dry_stage"]:
		reset_soil(actual, "fresh")
		reset_soil(reference, "fresh")
		var saved = actual.get(gate)
		var blocked = 0.5 if gate == "reveal_progress" else not saved
		actual.set(gate, blocked)
		reference.set(gate, blocked)
		if gate == "skip_dry_stage":
			actual.surface_coverage_total = actual.surface_pixel_count
			reference.surface_coverage_total = reference.surface_pixel_count
		compare(actual, reference, cases[0], "blocked " + gate)
		check(actual.water_coverage_total == 0.0, "Gate prevents painting: " + gate)
		actual.set(gate, saved)
		reference.set(gate, saved)
	for profile in ["direct", "soak", "rapid_sweep", "saturated"]:
		var old_times: Array[int] = []
		var new_times: Array[int] = []
		for sample in 24:
			reset_soil(actual, "saturated" if profile == "saturated" else "fresh")
			reset_soil(reference, "saturated" if profile == "saturated" else "fresh")
			var start := Time.get_ticks_usec()
			profile_paint(reference, profile)
			old_times.append(Time.get_ticks_usec() - start)
			start = Time.get_ticks_usec()
			profile_paint(actual, profile)
			new_times.append(Time.get_ticks_usec() - start)
		old_times.sort()
		new_times.sort()
		print("HOSE_PAINTER_BENCH profile=%s reference_median_us=%d current_median_us=%d reference_p95_us=%d current_p95_us=%d" % [profile, old_times[12], new_times[12], old_times[22], new_times[22]])
	for soil in [actual, reference]:
		soil.rug_node.free()
		soil.free()
	print("HOSE_PAINTER_OPTIMIZATION_VALIDATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func profile_paint(soil: Node, profile: String) -> void:
	if profile == "rapid_sweep":
		for i in 8:
			soil.apply_water_blob(Vector3(-0.65 + i * 0.18, 0, 0), 0.3, 0.14, 0.18)
		for i in 6:
			soil.apply_water_blob(Vector3(-0.65 + i * 0.25, 0, 0), 0.55, 0.055, 0.82)
	else:
		soil.apply_water_blob(Vector3.ZERO, 0.55 if profile == "soak" else 0.3, 0.14, 0.82 if profile == "soak" else 0.18)
