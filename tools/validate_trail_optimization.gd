extends SceneTree
## Exact numerical/output comparison with the original, uncached trail sampler.
## The reference is deliberately independent of the production sampling cache.
const Trail := preload("res://scripts/squeegee_water_trail.gd")
const Footprint := preload("res://scripts/rug_footprint.gd")

class SoilFixture:
	extends Node
	const MASK_SIZE := Vector2i(256, 416)
	var water_values := PackedFloat32Array()
	var extraction_values := PackedFloat32Array()
	var surface_pixels := PackedByteArray()
	var footprint := Footprint.new()

class LegacyTrail:
	extends "res://scripts/squeegee_water_trail.gd"

	func _refresh_field() -> float:
		var water: PackedFloat32Array = soil.water_values
		var extraction: PackedFloat32Array = soil.extraction_values
		var surface: PackedByteArray = _body_surface
		var mask_size: Vector2i = soil.MASK_SIZE
		var positive := 0.0
		for y in GRID_SIZE.y:
			for x in GRID_SIZE.x:
				var index := y * GRID_SIZE.x + x
				# Do not call _grid_point: the production version may cache it.
				var point := (Vector2(x, y) / Vector2(GRID_SIZE - Vector2i.ONE) - Vector2(0.5, 0.5)) * WORLD_SIZE
				var pixel := (point / Vector2(2.0, 3.32) + Vector2(0.5, 0.5)) * Vector2(mask_size) - Vector2(0.5, 0.5)
				var low := Vector2i(pixel.floor())
				var fraction := pixel - Vector2(low)
				var extracted := 0.0
				var total_water := 0.0
				var support := 0.0
				for corner in 4:
					var px := low.x + (corner & 1)
					var py := low.y + (corner >> 1)
					if px < 0 or py < 0 or px >= mask_size.x or py >= mask_size.y:
						continue
					var source := py * mask_size.x + px
					var weight := (fraction.x if (corner & 1) != 0 else 1.0 - fraction.x) * (fraction.y if corner >= 2 else 1.0 - fraction.y)
					if surface[source] == 0:
						continue
					support += weight
					extracted += minf(extraction[source], water[source]) * weight
					total_water += water[source] * weight
				var added := maxf(0.0, extracted - _extracted[index])
				if added > 0.0001:
					_runoff_supplied[index] = clock_seconds
				positive += added
				_charge[index] = clampf(_charge[index] + added * 0.90, 0.0, 1.0)
				_extracted[index] = extracted
				_field[index] = clampf(extracted / maxf(total_water, 0.08), 0.0, 1.0) * support if extracted > 0.02 else 0.0
		return positive

var checks := 0
var failures := 0
var soil: SoilFixture
var cached: Node3D
var legacy: Node3D


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Run the isolated validator with -- --shop-test")
		quit(2)
		return
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func make_soil() -> void:
	soil = SoilFixture.new()
	root.add_child(soil)
	var count := soil.MASK_SIZE.x * soil.MASK_SIZE.y
	soil.water_values.resize(count)
	soil.extraction_values.resize(count)
	soil.surface_pixels.resize(count)
	for y in soil.MASK_SIZE.y:
		for x in soil.MASK_SIZE.x:
			var index := y * soil.MASK_SIZE.x + x
			var point := (Vector2(x + 0.5, y + 0.5) / Vector2(soil.MASK_SIZE) - Vector2(0.5, 0.5)) * Vector2(2.0, 3.32)
			soil.surface_pixels[index] = int(soil.footprint.contains_point(point))
			soil.water_values[index] = (0.015 + float((x * 13 + y * 37) % 101) / 103.0) * soil.surface_pixels[index]
			soil.extraction_values[index] = 0.0


func add_extraction(rect: Rect2, amount: float) -> void:
	for y in soil.MASK_SIZE.y:
		for x in soil.MASK_SIZE.x:
			var point := (Vector2(x + 0.5, y + 0.5) / Vector2(soil.MASK_SIZE) - Vector2(0.5, 0.5)) * Vector2(2.0, 3.32)
			if not rect.has_point(point):
				continue
			var index := y * soil.MASK_SIZE.x + x
			soil.extraction_values[index] = minf(soil.water_values[index], soil.extraction_values[index] + amount)


func compare_output(label: String) -> void:
	check(cached._field == legacy._field, label + ": exact field samples")
	check(cached._extracted == legacy._extracted, label + ": exact extracted amounts")
	check(cached._charge == legacy._charge, label + ": exact pressure reservoir")
	check(cached._runoff_supplied == legacy._runoff_supplied, label + ": exact local supply timestamps")
	check(cached._gradients == legacy._gradients, label + ": exact contour gradients")
	check(cached.debug_stats() == legacy.debug_stats(), label + ": exact contour/runoff state")
	var segments_equal: bool = cached.active_segments == legacy.active_segments
	if segments_equal:
		for index in cached.active_segments:
			segments_equal = segments_equal and cached.segment_debug(index) == legacy.segment_debug(index)
			segments_equal = segments_equal and cached.batch.get_instance_transform(index) == legacy.batch.get_instance_transform(index)
			segments_equal = segments_equal and cached.batch.get_instance_custom_data(index) == legacy.batch.get_instance_custom_data(index)
			segments_equal = segments_equal and cached.batch.get_instance_color(index) == legacy.batch.get_instance_color(index)
	check(segments_equal, label + ": exact segment geometry and renderer data")
	var packets_equal := true
	for index in cached.streams.CAPACITY:
		packets_equal = packets_equal and cached.streams.packet_debug(index) == legacy.streams.packet_debug(index)
	check(packets_equal, label + ": exact long-runoff packets")


func benchmark(target: Node, method: StringName, count: int) -> float:
	for iteration in 3:
		target.call(method)
	var begin := Time.get_ticks_usec()
	for iteration in count:
		target.call(method)
	return float(Time.get_ticks_usec() - begin) / float(count) / 1000.0


func run() -> void:
	root.get_node("ShopState").set_process(false)
	make_soil()
	cached = Trail.new()
	legacy = LegacyTrail.new()
	root.add_child(cached)
	root.add_child(legacy)
	cached.setup(soil, null)
	legacy.setup(soil, null)
	check(cached._body_surface == legacy._body_surface, "Original body silhouette is unchanged")
	var water_before := soil.water_values.duplicate()
	var surface_before := soil.surface_pixels.duplicate()
	var regions := [Rect2(-0.28, -0.9, 0.56, 1.8), Rect2(-0.28, -0.9, 0.56, 1.8), Rect2(-0.65, -0.8, 0.55, 1.6), Rect2(-1.1, -0.2, 2.2, 0.4), Rect2(-0.28, 0.8, 0.56, 0.9), Rect2(0.65, 1.1, 0.5, 0.6), Rect2(-1.2, -1.8, 2.4, 3.6)]
	for iteration in regions.size():
		add_extraction(regions[iteration], 0.30 if iteration < 4 else 1.0)
		for target in [cached, legacy]:
			target.notify_extraction(Vector3.ZERO, 1.0)
			target.advance(0.11)
		compare_output("Fixture %d" % iteration)
	# Unchanged arrays and remote/expired supplies must retain the same lifetime.
	for seconds in [0.15, 0.4, 3.0, 11.0, 100.0]:
		for target in [cached, legacy]:
			target.notify_extraction(Vector3.ZERO, 100.0)
			target.advance(seconds)
		compare_output("Unchanged arrays after %.2fs" % seconds)
	check(soil.water_values == water_before and soil.surface_pixels == surface_before, "Visual sampling never changes source water or surface arrays")
	var original_batch: int = cached.batch.get_instance_id()
	var original_mesh: int = cached.batch.mesh.get_instance_id()
	for target in [cached, legacy]:
		target.reset()
	soil.extraction_values.fill(0.0)
	add_extraction(Rect2(-0.22, -1.7, 0.44, 3.4), 1.0)
	for target in [cached, legacy]:
		target.notify_extraction(Vector3.ZERO, 1.0)
		target.advance(0.11)
	compare_output("Reset and fresh extraction")
	check(cached.batch.get_instance_id() == original_batch and cached.batch.mesh.get_instance_id() == original_mesh, "Reset preserves all fixed geometry")
	var legacy_sample := benchmark(legacy, &"_refresh_field", 60)
	var cached_sample := benchmark(cached, &"_refresh_field", 60)
	var legacy_rebuild := benchmark(legacy, &"_rebuild", 30)
	var cached_rebuild := benchmark(cached, &"_rebuild", 30)
	print("TRAIL_CPU_BENCHMARK sample_legacy_ms=%.4f sample_current_ms=%.4f rebuild_legacy_ms=%.4f rebuild_current_ms=%.4f" % [legacy_sample, cached_sample, legacy_rebuild, cached_rebuild])
	print("TRAIL_OPTIMIZATION_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
