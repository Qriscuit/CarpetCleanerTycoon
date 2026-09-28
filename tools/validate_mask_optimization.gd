extends SceneTree
## Frozen pre-optimization painter verifies authoritative masks without a renderer.
## Run with pinned tools/run_godot.ps1 --headless ... -- --shop-test.
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
	soil.coverage_values.fill(0.0)
	soil.water_values.resize(count)
	soil.water_values.fill(1.0)
	soil.extraction_values.resize(count)
	soil.extraction_values.fill(0.0)
	soil.wet_mask = Image.create(Soil.MASK_SIZE.x, Soil.MASK_SIZE.y, false, Image.FORMAT_L8)
	soil.wet_mask.fill(Color.WHITE)
	for y in Soil.MASK_SIZE.y:
		for x in Soil.MASK_SIZE.x:
			var p := (Vector2(x + 0.5, y + 0.5) / Vector2(Soil.MASK_SIZE) - Vector2.ONE * 0.5) * Soil.RUG_HALF * 2.0
			if soil.footprint.contains_point(p):
				soil.surface_pixels[y * Soil.MASK_SIZE.x + x] = 1
				soil.surface_pixel_count += 1
	soil.water_coverage_total = soil.surface_pixel_count
	soil.set_process(false)
	return soil

func reset_extraction(soil: Node, fully_extracted: bool = false) -> void:
	soil.extraction_values.fill(1.0 if fully_extracted else 0.0)
	soil.extraction_coverage_total = float(soil.surface_pixel_count) if fully_extracted else 0.0
	soil.wet_mask.fill(Color.BLACK if fully_extracted else Color.WHITE)
	soil.wet_mask_changed = false
	soil.set_process(false)

func heading(angle: float) -> Vector3:
	return Vector3(cos(angle), 0.0, sin(angle))

func run() -> void:
	var actual := make_soil()
	var reference := make_soil()
	var rng := RandomNumberGenerator.new()
	rng.seed = 91627
	# Straight, diagonal, reversing, edge-clipped, tiny and off-rug strokes.
	var cases := [
		[Vector3(-0.2, 0.067, 0.3), Vector3(-0.2, 0.067, 0.28), -PI / 2.0, -PI / 2.0, 1.0 / 60.0, 1.0],
		[Vector3.ZERO, Vector3(0.015, 0.0, 0.014), 0.75, 0.6, 1.0 / 60.0, 2.1],
		[Vector3.ZERO, Vector3(0.01, 0.0, -0.01), PI / 2.0, -PI / 2.0, 0.08, 16.0],
		[Vector3(0.98, 0.0, 1.57), Vector3(1.2, 0.0, 1.8), 0.25, 1.1, 0.2, 4.41],
		[Vector3(5, 0, 5), Vector3(6, 0, 6), 0.0, PI, -1.0, 1.0],
		[Vector3.ZERO, Vector3(0.00001, 0, 0), 0.0, 0.0, 0.0, 1.0],
		[Vector3(-1.3, 0, -1.7), Vector3(1.3, 0, 1.7), 0.75, -1.2, 0.08, 1.0],
	]
	for i in 28:
		var a := Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.8, 1.8))
		var b := a + Vector3(rng.randf_range(-0.09, 0.09), 0, rng.randf_range(-0.09, 0.09))
		cases.append([a, b, rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(0.001, 0.1), rng.randf_range(1.0, 9.261)])
	for transformed in [false, true]:
		var basis := Basis(Vector3.UP, 0.63) if transformed else Basis.IDENTITY
		for soil in [actual, reference]:
			soil.rug_node.transform = Transform3D(basis, Vector3(2, 0.5, -3) if transformed else Vector3.ZERO)
		for mode in ["fresh", "overlapping", "fully_extracted"]:
			reset_extraction(actual, mode == "fully_extracted")
			reset_extraction(reference, mode == "fully_extracted")
			for i in cases.size():
				if mode == "fresh":
					reset_extraction(actual)
					reset_extraction(reference)
				var args: Array = cases[i]
				var a: Vector3 = actual.rug_node.to_global(args[0])
				var b: Vector3 = actual.rug_node.to_global(args[1])
				var direction: Vector3 = basis * heading(args[2])
				var previous: Vector3 = basis * heading(args[3])
				actual.tool_strength = args[5]
				reference.tool_strength = args[5]
				reference_paint(reference, a, b, args[4], direction, previous)
				actual._paint_rotated_squeegee_stroke(a, b, args[4], direction, previous)
				var label := "%s transformed=%s case=%d" % [mode, transformed, i]
				check(actual.extraction_values == reference.extraction_values, "Exact extracted mask: " + label)
				check(absf(actual.extraction_coverage_total - reference.extraction_coverage_total) < 0.000001, "Identical reward total: " + label)
				check(actual.wet_mask.get_data() == reference.wet_mask.get_data(), "Identical visible water: " + label)
				check(actual.wet_mask_changed == reference.wet_mask_changed, "Identical dirty flag: " + label)
	for soil in [actual, reference]:
		soil.rug_node.transform = Transform3D.IDENTITY
		soil.tool_strength = 1.0
	for profile in ["steady", "turning", "cleared"]:
		var original: Array[int] = []
		var optimized: Array[int] = []
		var direction := heading(-PI / 2.0 + (0.22 if profile == "turning" else 0.0))
		var previous := heading(-PI / 2.0)
		for sample in 24:
			reset_extraction(actual, profile == "cleared")
			reset_extraction(reference, profile == "cleared")
			var start_us := Time.get_ticks_usec()
			reference_paint(reference, Vector3.ZERO, Vector3(0.005, 0, -0.012), 1.0 / 60.0, direction, previous)
			original.append(Time.get_ticks_usec() - start_us)
			start_us = Time.get_ticks_usec()
			actual._paint_rotated_squeegee_stroke(Vector3.ZERO, Vector3(0.005, 0, -0.012), 1.0 / 60.0, direction, previous)
			optimized.append(Time.get_ticks_usec() - start_us)
		original.sort()
		optimized.sort()
		print("MASK_BENCH profile=%s reference_median_us=%d current_median_us=%d reference_p95_us=%d current_p95_us=%d" % [profile, original[12], optimized[12], original[22], optimized[22]])
	for soil in [actual, reference]:
		soil.rug_node.free()
		soil.free()
	check_full_wet_preparation()
	print("MASK_OPTIMIZATION_VALIDATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func make_full_soil() -> Node:
	var rug := Node3D.new()
	var dirty := (load("res://scenes/dirty_carpet.tscn") as PackedScene).instantiate()
	dirty.name = "Dirty"
	rug.add_child(dirty)
	root.add_child(rug)
	var soil := Soil.new()
	root.add_child(soil)
	soil.automatic_completion_enabled = false
	soil.setup(rug)
	soil.set_recipe(true)
	return soil

func check_full_wet_preparation() -> void:
	var actual := make_full_soil()
	var reference := make_full_soil()
	var original: Array[int] = []
	var optimized: Array[int] = []
	var events := {"progress": 0, "surface": 0}
	actual.progress_changed.connect(func(_remaining, _total): events.progress += 1)
	actual.surface_changed.connect(func(): events.surface += 1)
	var image_id: int = actual.wet_mask.get_instance_id()
	var texture_id: int = actual.wet_texture.get_instance_id()
	var pool_id: int = actual.batch.get_instance_id()
	for sample in 12:
		actual.reset()
		reference.reset()
		events.progress = 0
		events.surface = 0
		var start_us := Time.get_ticks_usec()
		reference.prepare_water_stage()
		reference.apply_water_blob(reference.rug_node.to_global(Vector3.ZERO), Soil.RUG_HALF.length() * 2.0, 1.0, 0.01)
		original.append(Time.get_ticks_usec() - start_us)
		start_us = Time.get_ticks_usec()
		actual.prepare_extraction_stage()
		optimized.append(Time.get_ticks_usec() - start_us)
		check(actual.water_values == reference.water_values, "Bulk preparation preserves full wet mask, sample %d" % sample)
		check(actual.extraction_values == reference.extraction_values and actual.coverage_values == reference.coverage_values, "Bulk preparation preserves clear dry/extraction masks")
		check(actual.wet_mask.get_data() == reference.wet_mask.get_data(), "Bulk preparation keeps empty rounded corners and fringe gaps dry")
		check(actual.make_progress_snapshot() == reference.make_progress_snapshot(), "Bulk preparation has identical stage/reward progress")
		check(actual.credited == reference.credited and actual.cleared == reference.cleared and actual.growth == reference.growth and actual.remaining == 0, "Bulk preparation hides and credits existing dirt pool")
		check(actual.recommended_tool() == 1 and not actual.is_physics_processing() and not actual.automatic_completion_enabled, "Bulk preparation selects extraction without automatic completion")
		check(events.progress == 1 and events.surface == 0, "Bulk preparation emits progress once and defers surface upload")
		actual._process(0.0)
		check(events.surface == 1 and not actual.is_processing(), "Bulk preparation emits one surface update then sleeps")
		check(actual.wet_mask.get_instance_id() == image_id and actual.wet_texture.get_instance_id() == texture_id and actual.batch.get_instance_id() == pool_id, "Bulk preparation retains image, GPU texture and clump pool")
	check(actual.make_snapshot() == reference.make_snapshot(), "Bulk preparation preserves complete save schema and bytes")
	actual.apply_squeegee_stroke(Vector3(0, 0, 0), Vector3(0, 0, -0.05), 0.08)
	check(actual.extraction_clearance() > 0.0, "Prepared carpet accepts normal squeegee extraction")
	actual.prepare_water_stage()
	check(actual.water_clearance() == 0.0 and actual.extraction_clearance() == 0.0, "Hose shortcut still dries the prepared carpet")
	actual.prepare_extraction_stage()
	check(actual.water_clearance() == 1.0 and actual.extraction_clearance() == 0.0, "Repeated preparation does not mutate cached full-water template")
	original.sort()
	optimized.sort()
	print("MASK_BENCH profile=gym_full_wet reference_median_us=%d current_median_us=%d reference_p95_us=%d current_p95_us=%d" % [original[6], optimized[6], original[11], optimized[11]])
	for soil in [actual, reference]:
		soil.rug_node.free()
		soil.free()

func reference_paint(soil: Node, world_from: Vector3, world_to: Vector3, elapsed: float, direction: Vector3, previous_heading: Vector3) -> void:
	# Original implementation as of 2026-09-27. Keep independent of optimized helpers.
	if soil.completion_started or soil.simulation_suspended or soil.reveal_progress < 1.0:
		return
	var a3: Vector3 = soil.rug_node.to_local(world_from)
	var b3: Vector3 = soil.rug_node.to_local(world_to)
	var start := Vector2(a3.x, a3.z)
	var finish := Vector2(b3.x, b3.z)
	if start.distance_squared_to(finish) < 0.00000001:
		return
	var current_direction: Vector2 = soil._squeegee_local_heading(direction, Vector2(0.0, -1.0))
	var old_direction := current_direction
	if previous_heading.length_squared() >= 0.00000001:
		old_direction = soil._squeegee_local_heading(previous_heading, current_direction)
	var old_angle := old_direction.angle()
	var angle_delta := wrapf(current_direction.angle() - old_angle, -PI, PI)
	var rotation_steps := clampi(ceili(absf(angle_delta) / Soil.SQUEEGEE_ROTATION_STEP), 1, Soil.SQUEEGEE_MAX_ROTATION_STEPS)
	var sides := PackedVector2Array()
	var headings := PackedVector2Array()
	var starts := PackedVector2Array()
	var finishes := PackedVector2Array()
	var bounds_low := Vector2(INF, INF)
	var bounds_high := Vector2(-INF, -INF)
	var turning := absf(angle_delta) >= 0.00001
	for sample in rotation_steps:
		var ta := float(sample) / float(rotation_steps)
		var tb := float(sample + 1) / float(rotation_steps)
		var center_a := start.lerp(finish, ta)
		var center_b := start.lerp(finish, tb)
		var mid_t := (float(sample) + 0.5) / float(rotation_steps)
		var sweep_heading := Vector2.from_angle(old_angle + angle_delta * mid_t)
		var sweep_side := Vector2(-sweep_heading.y, sweep_heading.x)
		sides.append(sweep_side)
		headings.append(sweep_heading)
		starts.append(Vector2(center_a.dot(sweep_side), center_a.dot(sweep_heading)))
		finishes.append(Vector2(center_b.dot(sweep_side), center_b.dot(sweep_heading)))
		var extent := sweep_side.abs() * Soil.SQUEEGEE_HALF.x + sweep_heading.abs() * Soil.SQUEEGEE_HALF.y + Vector2.ONE * Soil.EDGE_FEATHER
		bounds_low = bounds_low.min(center_a.min(center_b) - extent)
		bounds_high = bounds_high.max(center_a.max(center_b) + extent)
	if turning:
		for sample in range(rotation_steps + 1):
			var t := float(sample) / float(rotation_steps)
			var center := start.lerp(finish, t)
			var pose_heading := Vector2.from_angle(old_angle + angle_delta * t)
			var pose_side := Vector2(-pose_heading.y, pose_heading.x)
			var local_center := Vector2(center.dot(pose_side), center.dot(pose_heading))
			sides.append(pose_side)
			headings.append(pose_heading)
			starts.append(local_center)
			finishes.append(local_center)
			var extent := pose_side.abs() * Soil.SQUEEGEE_HALF.x + pose_heading.abs() * Soil.SQUEEGEE_HALF.y + Vector2.ONE * Soil.EDGE_FEATHER
			bounds_low = bounds_low.min(center - extent)
			bounds_high = bounds_high.max(center + extent)
	var low := (bounds_low + Soil.RUG_HALF) / (Soil.RUG_HALF * 2.0)
	var high := (bounds_high + Soil.RUG_HALF) / (Soil.RUG_HALF * 2.0)
	var from_pixel := Vector2i((low * Vector2(Soil.MASK_SIZE)).floor()).clamp(Vector2i.ZERO, Soil.MASK_SIZE)
	var to_pixel := Vector2i((high * Vector2(Soil.MASK_SIZE)).ceil()).clamp(Vector2i.ZERO, Soil.MASK_SIZE)
	var seconds := clampf(elapsed if elapsed > 0.0 else 1.0 / 60.0, 1.0 / 240.0, 0.08)
	var amount: float = seconds * Soil.EXTRACTION_RATE * soil.tool_strength
	var any_changed := false
	for y in range(from_pixel.y, to_pixel.y):
		for x in range(from_pixel.x, to_pixel.x):
			var index := y * Soil.MASK_SIZE.x + x
			if soil.surface_pixels[index] == 0:
				continue
			var point := (Vector2(x + 0.5, y + 0.5) / Vector2(Soil.MASK_SIZE) - Vector2.ONE * 0.5) * Soil.RUG_HALF * 2.0
			var distance := INF
			for sweep in sides.size():
				var local_point := Vector2(point.dot(sides[sweep]), point.dot(headings[sweep]))
				var closest := Geometry2D.get_closest_point_to_segment(local_point, starts[sweep], finishes[sweep])
				var q := (local_point - closest).abs() - Soil.SQUEEGEE_HALF
				var next_distance := q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0)
				distance = minf(distance, next_distance)
			var weight := 1.0 - smoothstep(-Soil.EDGE_FEATHER, Soil.EDGE_FEATHER, distance)
			if soil._apply_wet_pixel(index, x, y, amount, weight, false):
				any_changed = true
	if any_changed:
		soil.wet_mask_changed = true
		soil.set_process(true)
