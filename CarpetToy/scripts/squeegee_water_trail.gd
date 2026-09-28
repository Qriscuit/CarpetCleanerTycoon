extends Node3D
## Visual-only union contour of actual extraction. One bounded strip MultiMesh;
## all authoritative water/extraction/surface arrays are read, never modified.

const StreamEffect := preload("res://scripts/squeegee_runoff_streams.gd")
const GRID_SIZE := Vector2i(65, 105)
const WORLD_SIZE := Vector2(2.08, 3.44)
const CAPACITY := 2048
const REBUILD_INTERVAL := 0.10
const LINGER_SECONDS := 8.0
const FADE_SECONDS := 2.0
const FIELD_THRESHOLD := 0.35
const RUG_Y := 0.071
const FLOOR_Y := 0.006
const ROWS := 13
const MIN_CREST := 0.035
const MAX_CREST := 0.090
const TRAIL_REACH := 0.080
const SPILL_REACH := 0.220
const RUNOFF_HOLD_SECONDS := 0.12
const RUNOFF_DRAIN_SECONDS := 0.28
const RUNOFF_OUTWARD_TRAVEL := 0.08
const MOUTH_BINS := 128
const MAX_MOUTHS := 4
const MAX_MOUTH_WIDTH := 1.25

var soil: Node
var batch: MultiMesh
var node: MultiMeshInstance3D
var material: ShaderMaterial
var streams: Node3D
var clock_seconds := 0.0
var strength := 0.0
var active_segments := 0
var spill_segments := 0
var live_spill_segments := 0
var runoff_strength := 0.0
var build_count := 0
var notification_count := 0
var renewal_count := 0
var clipped_segments := 0
var _dirty := false
var _since_build := REBUILD_INTERVAL
var _last_supply := -1000.0
var _field := PackedFloat32Array()
var _extracted := PackedFloat32Array()
var _charge := PackedFloat32Array()
var _runoff_supplied := PackedFloat64Array()
var _gradients := PackedVector2Array()
var _body_surface := PackedByteArray()
var _starts := PackedVector2Array()
var _ends := PackedVector2Array()
var _normal_starts := PackedVector2Array()
var _normal_ends := PackedVector2Array()
var _spill_starts := PackedFloat32Array()
var _spill_ends := PackedFloat32Array()
var _pressure_starts := PackedFloat32Array()
var _pressure_ends := PackedFloat32Array()
var _runoff_sources_start := PackedFloat64Array()
var _runoff_sources_end := PackedFloat64Array()
var _runoff_phases_start := PackedFloat32Array()
var _runoff_phases_end := PackedFloat32Array()
var _cross_points := PackedVector2Array()
var _cross_normals := PackedVector2Array()
var _body_polygon := PackedVector2Array()
var _body_arc_offsets := PackedFloat32Array()
var _body_perimeter := 0.0
var _mouth_times := PackedFloat64Array()
var _mouth_consumed := PackedFloat64Array()
var _mouth_powers := PackedFloat32Array()
var _mouths_funded := 0
var _grid_positions := PackedVector2Array()
var _sample_offsets := PackedInt32Array()
var _sample_sources := PackedInt32Array()
var _sample_weights := PackedFloat64Array()
var _sample_support := PackedFloat64Array()


func setup(source_soil: Node, surface_texture: Texture2D) -> void:
	assert(batch == null, "Allocate trail geometry only once")
	soil = source_soil
	_cache_body_surface()
	_cache_field_samples()
	_field.resize(GRID_SIZE.x * GRID_SIZE.y)
	_extracted.resize(_field.size())
	_charge.resize(_field.size())
	_runoff_supplied.resize(_field.size())
	_gradients.resize(_field.size())
	_starts.resize(CAPACITY)
	_ends.resize(CAPACITY)
	_normal_starts.resize(CAPACITY)
	_normal_ends.resize(CAPACITY)
	_spill_starts.resize(CAPACITY)
	_spill_ends.resize(CAPACITY)
	_pressure_starts.resize(CAPACITY)
	_pressure_ends.resize(CAPACITY)
	_runoff_sources_start.resize(CAPACITY)
	_runoff_sources_end.resize(CAPACITY)
	_runoff_phases_start.resize(CAPACITY)
	_runoff_phases_end.resize(CAPACITY)
	_cross_points.resize(4)
	_cross_normals.resize(4)
	_mouth_times.resize(MOUTH_BINS)
	_mouth_consumed.resize(MOUTH_BINS)
	_mouth_powers.resize(MOUTH_BINS)
	batch = MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_custom_data = true
	batch.use_colors = true
	batch.mesh = _strip_mesh()
	batch.instance_count = CAPACITY
	batch.visible_instance_count = 0
	node = MultiMeshInstance3D.new()
	node.name = "ExtractedPathRidgesAndEdgeSpills"
	node.multimesh = batch
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-1.6, -0.1, -2.1), Vector3(3.2, 0.6, 4.2))
	material = ShaderMaterial.new()
	material.shader = preload("res://scripts/water_jet_impact.gdshader")
	material.set_shader_parameter("trail_mode", true)
	material.set_shader_parameter("rug_surface", surface_texture)
	material.set_shader_parameter("trail_reach", TRAIL_REACH)
	material.set_shader_parameter("spill_reach", SPILL_REACH)
	material.set_shader_parameter("runoff_outward_travel", RUNOFF_OUTWARD_TRAVEL)
	material.set_shader_parameter("trail_min_crest", MIN_CREST)
	material.set_shader_parameter("trail_max_crest", MAX_CREST)
	node.material_override = material
	add_child(node)
	streams = StreamEffect.new()
	streams.name = "GroupedRunoffStreams"
	add_child(streams)
	streams.setup(surface_texture, soil.footprint)
	reset()


func notify_extraction(_contact: Vector3, amount: float) -> void:
	if amount <= 0.0001 or not is_instance_valid(soil):
		return
	notification_count += 1
	_dirty = true
	# Deliberately not a wetness supply. Only an actual positive array delta
	# discovered at rebuild may renew the visual reservoir or its lifetime.


func advance(delta: float) -> void:
	if batch == null:
		return
	var step := maxf(delta, 0.0)
	clock_seconds += step
	streams.advance(step)
	_since_build += step
	if _dirty and _since_build >= REBUILD_INTERVAL:
		_rebuild()
		_since_build = 0.0
		_dirty = false
	var age := maxf(0.0, clock_seconds - _last_supply)
	strength = 1.0 - smoothstep(LINGER_SECONDS, LINGER_SECONDS + FADE_SECONDS, age)
	_update_runoff_lifetimes()
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("water_clock", fmod(clock_seconds, 100.0))
	node.visible = active_segments > 0 and strength > 0.0
	batch.visible_instance_count = active_segments if node.visible else 0


func reset() -> void:
	clock_seconds = 0.0
	strength = 0.0
	active_segments = 0
	spill_segments = 0
	live_spill_segments = 0
	runoff_strength = 0.0
	build_count = 0
	notification_count = 0
	renewal_count = 0
	clipped_segments = 0
	_last_supply = -1000.0
	_since_build = REBUILD_INTERVAL
	_dirty = false
	_field.fill(0.0)
	_extracted.fill(0.0)
	_charge.fill(0.0)
	_runoff_supplied.fill(-1000.0)
	_runoff_sources_start.fill(-1000.0)
	_runoff_sources_end.fill(-1000.0)
	_runoff_phases_start.fill(1.0)
	_runoff_phases_end.fill(1.0)
	_mouth_times.fill(-1000.0)
	_mouth_consumed.fill(-1000.0)
	_mouth_powers.fill(0.0)
	_mouths_funded = 0
	if is_instance_valid(streams):
		streams.reset()
	if batch != null:
		batch.visible_instance_count = 0
		node.hide()


func is_alive() -> bool:
	return _dirty or (active_segments > 0 and clock_seconds < _last_supply + LINGER_SECONDS + FADE_SECONDS) or (is_instance_valid(streams) and streams.is_alive())


func debug_stats() -> Dictionary:
	var crest := MIN_CREST
	for i in active_segments:
		crest = maxf(crest, lerpf(MIN_CREST, MAX_CREST, maxf(_pressure_starts[i], _pressure_ends[i])))
	return {"active_segments": active_segments if strength > 0.0 else 0,
		"stored_segments": active_segments, "spill_segments": live_spill_segments if strength > 0.0 else 0,
		"stored_spill_segments": spill_segments, "live_spill_segments": live_spill_segments if strength > 0.0 else 0,
		"runoff_strength": runoff_strength if strength > 0.0 else 0.0,
		"streams": streams.debug_stats() if is_instance_valid(streams) else {}, "mouths_funded": _mouths_funded,
		"build_count": build_count, "capacity": CAPACITY, "strength": strength,
		"crest_height": crest * strength, "notification_count": notification_count,
		"renewal_count": renewal_count, "clipped_segments": clipped_segments,
		"grid_size": GRID_SIZE, "dirty": _dirty, "age": maxf(0.0, clock_seconds - _last_supply),
		"mesh_instances": 1, "vertices_per_segment": ROWS * 2,
		"linger_seconds": LINGER_SECONDS, "fade_seconds": FADE_SECONDS,
		"runoff_hold_seconds": RUNOFF_HOLD_SECONDS, "runoff_drain_seconds": RUNOFF_DRAIN_SECONDS}


func segment_debug(index: int) -> Dictionary:
	assert(index >= 0 and index < active_segments)
	return {"start": Vector3(_starts[index].x, RUG_Y, _starts[index].y),
		"end": Vector3(_ends[index].x, RUG_Y, _ends[index].y),
		"normal_start": Vector3(_normal_starts[index].x, 0.0, _normal_starts[index].y),
		"normal_end": Vector3(_normal_ends[index].x, 0.0, _normal_ends[index].y),
		"spill": _spill_starts[index] > 0.0 or _spill_ends[index] > 0.0,
		"spill_start": _spill_starts[index], "spill_end": _spill_ends[index],
		"pressure_start": _pressure_starts[index], "pressure_end": _pressure_ends[index],
		"runoff_phase_start": _runoff_phases_start[index], "runoff_phase_end": _runoff_phases_end[index],
		"runoff_strength_start": 1.0 - smoothstep(0.0, 1.0, _runoff_phases_start[index]),
		"runoff_strength_end": 1.0 - smoothstep(0.0, 1.0, _runoff_phases_end[index]),
		"runoff_supplied_start": _runoff_sources_start[index], "runoff_supplied_end": _runoff_sources_end[index],
		"runoff_visible": (_spill_starts[index] > 0.0 and _runoff_phases_start[index] < 0.999) or (_spill_ends[index] > 0.0 and _runoff_phases_end[index] < 0.999)}


func sample_segment(index: int, along: float, across: float) -> Vector3:
	assert(index >= 0 and index < active_segments)
	var t := clampf(along, 0.0, 1.0)
	var v := clampf(across, 0.0, 1.0)
	var base := _starts[index].lerp(_ends[index], t)
	var outward := _normal_starts[index].lerp(_normal_ends[index], t).normalized()
	var pressure := lerpf(_pressure_starts[index], _pressure_ends[index], t)
	var spill := lerpf(_spill_starts[index], _spill_ends[index], t)
	var drain := lerpf(_runoff_phases_start[index], _runoff_phases_end[index], t)
	var runoff_amount := 1.0 - smoothstep(0.0, 1.0, drain)
	var phase := base.x * 32.0 + base.y * 47.0 - fmod(clock_seconds, 100.0) * 3.8
	var wave := 0.5 + 0.5 * sin(phase)
	var profile := 1.0 - cos(v * PI * 0.5)
	var ridge_distance := -0.008 + TRAIL_REACH * (0.78 + 0.22 * wave) * strength * profile
	# The leading edge advances monotonically; the trailing edge catches it.
	# Water drains OUT, rather than the old apron shrinking back onto the rug.
	var edge_wave := 0.5 + 0.5 * sin(base.x * 32.0 + base.y * 47.0)
	var front := SPILL_REACH * (0.91 + 0.09 * edge_wave) + RUNOFF_OUTWARD_TRAVEL * drain
	var back := lerpf(-0.008, front, smoothstep(0.0, 1.0, drain))
	var runoff_distance := lerpf(back, front, profile)
	var distance := lerpf(ridge_distance, runoff_distance, spill)
	var point := base + outward * distance
	var arch := pow(maxf(0.0, sin(v * PI)), 0.85)
	var ridge := lerpf(MIN_CREST, MAX_CREST, pressure) * (0.48 + 0.52 * wave) * arch * strength
	# A spill is a descending apron, never an upright dam at the exit.
	var support := lerpf(RUG_Y, FLOOR_Y, spill * smoothstep(0.006, 0.180, runoff_distance))
	# A wide apron can pass over another rounded tassel. Never lower that part
	# below the actual supporting carpet; the exposed part still reaches tile.
	if _surface_at(point):
		support = maxf(support, RUG_Y)
	var height := lerpf(ridge, 0.010 * sin(v * PI) * (0.65 + 0.35 * wave) * runoff_amount, spill)
	return Vector3(point.x, support + 0.003 + height, point.y)


func sample_segment_visible(index: int, along: float, _across: float) -> bool:
	assert(index >= 0 and index < active_segments)
	if strength <= 0.0:
		return false
	var t := clampf(along, 0.0, 1.0)
	var spill := lerpf(_spill_starts[index], _spill_ends[index], t)
	var drain := lerpf(_runoff_phases_start[index], _runoff_phases_end[index], t)
	return spill <= 0.001 or drain < 0.999


func _update_runoff_lifetimes() -> void:
	live_spill_segments = 0
	runoff_strength = 0.0
	for index in active_segments:
		if _spill_starts[index] <= 0.0 and _spill_ends[index] <= 0.0:
			# Interior ridges do not need a per-frame instance-buffer write.
			continue
		var phase_a := clampf((clock_seconds - _runoff_sources_start[index] - RUNOFF_HOLD_SECONDS) / RUNOFF_DRAIN_SECONDS, 0.0, 1.0)
		var phase_b := clampf((clock_seconds - _runoff_sources_end[index] - RUNOFF_HOLD_SECONDS) / RUNOFF_DRAIN_SECONDS, 0.0, 1.0)
		# At a ridge-to-exit join, only the true exit endpoint supplies runoff.
		# New interior work must not preserve a sliver of the already dry apron.
		if _spill_starts[index] <= 0.0:
			phase_a = phase_b
		elif _spill_ends[index] <= 0.0:
			phase_b = phase_a
		_runoff_phases_start[index] = phase_a
		_runoff_phases_end[index] = phase_b
		# Normalized COLOR channels avoid large timestamps and the Compatibility
		# half-float precision limit. The shader never multiplies ALBEDO by COLOR.
		batch.set_instance_color(index, Color(phase_a, phase_b, 1.0, 1.0))
		var freshest := minf(phase_a, phase_b)
		if freshest < 0.999:
			live_spill_segments += 1
			runoff_strength = maxf(runoff_strength, 1.0 - smoothstep(0.0, 1.0, freshest))


func _rebuild() -> void:
	build_count += 1
	var positive_delta := _refresh_field()
	if positive_delta > 0.0001:
		_last_supply = clock_seconds
		renewal_count += 1
		strength = 1.0
	for y in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var left := _field[y * GRID_SIZE.x + maxi(0, x - 1)]
			var right := _field[y * GRID_SIZE.x + mini(GRID_SIZE.x - 1, x + 1)]
			var lower := _field[maxi(0, y - 1) * GRID_SIZE.x + x]
			var upper := _field[mini(GRID_SIZE.y - 1, y + 1) * GRID_SIZE.x + x]
			_gradients[y * GRID_SIZE.x + x] = -Vector2((right - left) / (WORLD_SIZE.x / (GRID_SIZE.x - 1)), (upper - lower) / (WORLD_SIZE.y / (GRID_SIZE.y - 1)))
	active_segments = 0
	spill_segments = 0
	clipped_segments = 0
	for y in GRID_SIZE.y - 1:
		for x in GRID_SIZE.x - 1:
			var i := y * GRID_SIZE.x + x
			var bits := int(_field[i] >= FIELD_THRESHOLD) | (int(_field[i + 1] >= FIELD_THRESHOLD) << 1) | (int(_field[i + GRID_SIZE.x + 1] >= FIELD_THRESHOLD) << 2) | (int(_field[i + GRID_SIZE.x] >= FIELD_THRESHOLD) << 3)
			if bits == 0 or bits == 15:
				continue
			for edge in 4:
				_cross_edge(x, y, edge)
			match bits:
				1: _emit_segment(3, 0)
				2: _emit_segment(0, 1)
				3: _emit_segment(3, 1)
				4: _emit_segment(1, 2)
				5:
					if (_field[i] + _field[i + 1] + _field[i + GRID_SIZE.x + 1] + _field[i + GRID_SIZE.x]) * 0.25 >= FIELD_THRESHOLD:
						_emit_segment(3, 2)
						_emit_segment(0, 1)
					else:
						_emit_segment(3, 0)
						_emit_segment(1, 2)
				6: _emit_segment(0, 2)
				7: _emit_segment(3, 2)
				8: _emit_segment(2, 3)
				9: _emit_segment(2, 0)
				10:
					if (_field[i] + _field[i + 1] + _field[i + GRID_SIZE.x + 1] + _field[i + GRID_SIZE.x]) * 0.25 >= FIELD_THRESHOLD:
						_emit_segment(0, 3)
						_emit_segment(1, 2)
					else:
						_emit_segment(0, 1)
						_emit_segment(2, 3)
				11: _emit_segment(2, 1)
				12: _emit_segment(1, 3)
				13: _emit_segment(1, 0)
				14: _emit_segment(0, 3)
	batch.visible_instance_count = active_segments
	_build_runoff_sources()


func _refresh_field() -> float:
	var water: PackedFloat32Array = soil.water_values
	var extraction: PackedFloat32Array = soil.extraction_values
	var positive := 0.0
	for index in _field.size():
		var extracted := 0.0
		var total_water := 0.0
		for sample_index in range(_sample_offsets[index], _sample_offsets[index + 1]):
			var source := _sample_sources[sample_index]
			var weight := _sample_weights[sample_index]
			extracted += minf(extraction[source], water[source]) * weight
			total_water += water[source] * weight
		var added := maxf(0.0, extracted - _extracted[index])
		if added > 0.0001:
			# Stable WORLD grid storage, never pooled segment order or global
			# notification time: remote work cannot refresh an old exit.
			_runoff_supplied[index] = clock_seconds
		positive += added
		_charge[index] = clampf(_charge[index] + added * 0.90, 0.0, 1.0)
		_extracted[index] = extracted
		_field[index] = clampf(extracted / maxf(total_water, 0.08), 0.0, 1.0) * _sample_support[index] if extracted > 0.02 else 0.0
	return positive


func _grid_point(x: int, y: int) -> Vector2:
	return _grid_positions[y * GRID_SIZE.x + x]


func _cache_field_samples() -> void:
	# The silhouette and mask dimensions are immutable for this renderer, just
	# like _body_surface. If a future rug changes either, rebuild BOTH caches.
	# Float64 keeps the original bilinear arithmetic and contour thresholds;
	# only water/extraction values change during a swipe, not this mapping.
	var mask_size: Vector2i = soil.MASK_SIZE
	var count := GRID_SIZE.x * GRID_SIZE.y
	_grid_positions.resize(count)
	_sample_offsets.resize(count + 1)
	_sample_support.resize(count)
	_sample_sources.clear()
	_sample_weights.clear()
	for y in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var index := y * GRID_SIZE.x + x
			var point := (Vector2(x, y) / Vector2(GRID_SIZE - Vector2i.ONE) - Vector2(0.5, 0.5)) * WORLD_SIZE
			_grid_positions[index] = point
			_sample_offsets[index] = _sample_sources.size()
			var pixel := (point / Vector2(2.0, 3.32) + Vector2(0.5, 0.5)) * Vector2(mask_size) - Vector2(0.5, 0.5)
			var low := Vector2i(pixel.floor())
			var fraction := pixel - Vector2(low)
			var support := 0.0
			for corner in 4:
				var px := low.x + (corner & 1)
				var py := low.y + (corner >> 1)
				if px < 0 or py < 0 or px >= mask_size.x or py >= mask_size.y:
					continue
				var source := py * mask_size.x + px
				if _body_surface[source] == 0:
					continue
				var weight := (fraction.x if (corner & 1) != 0 else 1.0 - fraction.x) * (fraction.y if corner >= 2 else 1.0 - fraction.y)
				_sample_sources.append(source)
				_sample_weights.append(weight)
				support += weight
			_sample_support[index] = support
	_sample_offsets[count] = _sample_sources.size()


func _cross_edge(x: int, y: int, edge: int) -> void:
	var ax := x
	var ay := y
	var bx := x + 1
	var by := y
	if edge == 1:
		ax += 1
		by += 1
	elif edge == 2:
		ax += 1
		ay += 1
		bx -= 1
		by += 1
	elif edge == 3:
		ay += 1
		bx -= 1
	var ia := ay * GRID_SIZE.x + ax
	var ib := by * GRID_SIZE.x + bx
	var difference := _field[ib] - _field[ia]
	var fraction := clampf((FIELD_THRESHOLD - _field[ia]) / difference, 0.0, 1.0) if absf(difference) > 0.00001 else 0.5
	_cross_points[edge] = _grid_point(ax, ay).lerp(_grid_point(bx, by), fraction)
	_cross_normals[edge] = _gradients[ia].lerp(_gradients[ib], fraction).normalized()


func _emit_segment(first: int, second: int) -> void:
	if active_segments >= CAPACITY:
		clipped_segments += 1
		return
	var a := _cross_points[first]
	var b := _cross_points[second]
	var na := _cross_normals[first]
	var nb := _cross_normals[second]
	if a.distance_squared_to(b) < 0.00000001:
		return
	var spill_a := _is_spill(a, na)
	var spill_b := _is_spill(b, nb)
	if spill_a:
		a = _edge_support(a, na)
	if spill_b:
		b = _edge_support(b, nb)
	var tangent := (b - a).normalized()
	var outward := Vector2(-tangent.y, tangent.x)
	if outward.dot(na + nb) < 0.0:
		var old_a := a
		a = b
		b = old_a
		var old_na := na
		na = nb
		nb = old_na
		var old_spill := spill_a
		spill_a = spill_b
		spill_b = old_spill
		tangent = -tangent
		outward = -outward
	if na.length_squared() < 0.01:
		na = outward
	if nb.length_squared() < 0.01:
		nb = outward
	var length := a.distance_to(b)
	if length < 0.0001:
		return
	var pressure_a := float(roundi(_sample_charge(a - na * 0.035) * 31.0)) / 31.0
	var pressure_b := float(roundi(_sample_charge(b - nb * 0.035) * 31.0)) / 31.0
	var slot := active_segments
	_starts[slot] = a
	_ends[slot] = b
	_normal_starts[slot] = na
	_normal_ends[slot] = nb
	_spill_starts[slot] = float(spill_a)
	_spill_ends[slot] = float(spill_b)
	_pressure_starts[slot] = pressure_a
	_pressure_ends[slot] = pressure_b
	_runoff_sources_start[slot] = _sample_runoff_supply(a - na * 0.035)
	_runoff_sources_end[slot] = _sample_runoff_supply(b - nb * 0.035)
	_runoff_phases_start[slot] = 1.0
	_runoff_phases_end[slot] = 1.0
	batch.set_instance_color(slot, Color.WHITE)
	var midpoint := (a + b) * 0.5
	var basis := Basis(Vector3(tangent.x, 0, tangent.y) * length, Vector3.UP, Vector3(outward.x, 0, outward.y))
	batch.set_instance_transform(slot, Transform3D(basis, Vector3(midpoint.x, RUG_Y, midpoint.y)))
	# Two true endpoint normals and two quantized endpoint pressures let adjacent
	# strips agree exactly at their join without a separate node or tall miter.
	var angle_a := atan2(na.dot(outward), na.dot(tangent))
	var angle_b := atan2(nb.dot(outward), nb.dot(tangent))
	# Compatibility stores custom channels as half floats. Two five-bit values
	# fit into 0..1023 exactly; a sixteen-bit packed value would corrupt the
	# low endpoint and create a zipper of discontinuous heights at every join.
	var pressure_pair := float(roundi(pressure_a * 31.0) + roundi(pressure_b * 31.0) * 32)
	batch.set_instance_custom_data(slot, Color(angle_a, angle_b, float(int(spill_a) + 2 * int(spill_b)), pressure_pair))
	active_segments += 1
	if spill_a or spill_b:
		spill_segments += 1


func _surface_at(point: Vector2) -> bool:
	var mask_size: Vector2i = soil.MASK_SIZE
	var uv := point / Vector2(2.0, 3.32) + Vector2(0.5, 0.5)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return false
	var pixel := Vector2i(uv * Vector2(mask_size))
	return soil.surface_pixels[pixel.y * mask_size.x + pixel.x] != 0


func _cache_body_surface() -> void:
	var mask_size: Vector2i = soil.MASK_SIZE
	var full_surface: PackedByteArray = soil.surface_pixels
	var body: PackedVector2Array = soil.footprint.polygons[0]
	_body_polygon = body.duplicate()
	_body_arc_offsets.resize(body.size())
	_body_perimeter = 0.0
	for index in body.size():
		_body_arc_offsets[index] = _body_perimeter
		_body_perimeter += body[index].distance_to(body[(index + 1) % body.size()])
	_body_surface.resize(full_surface.size())
	for y in mask_size.y:
		for x in mask_size.x:
			var index := y * mask_size.x + x
			if full_surface[index] == 0:
				_body_surface[index] = 0
				continue
			var point := (Vector2(x + 0.5, y + 0.5) / Vector2(mask_size) - Vector2(0.5, 0.5)) * Vector2(2.0, 3.32)
			_body_surface[index] = 1 if Geometry2D.is_point_in_polygon(point, body) else 0


func _body_at(point: Vector2) -> bool:
	var mask_size: Vector2i = soil.MASK_SIZE
	var uv := point / Vector2(2.0, 3.32) + Vector2(0.5, 0.5)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return false
	var pixel := Vector2i(uv * Vector2(mask_size))
	return _body_surface[pixel.y * mask_size.x + pixel.x] != 0


func _is_spill(point: Vector2, normal: Vector2) -> bool:
	return _body_at(point - normal * 0.023) and not _body_at(point + normal * 0.021)


func _edge_support(point: Vector2, normal: Vector2) -> Vector2:
	var inside := point - normal * 0.035
	var outside := point + normal * 0.050
	for _iteration in 8:
		var middle := (inside + outside) * 0.5
		if _body_at(middle):
			inside = middle
		else:
			outside = middle
	return (inside + outside) * 0.5


func _sample_charge(point: Vector2) -> float:
	var grid := ((point / WORLD_SIZE + Vector2(0.5, 0.5)) * Vector2(GRID_SIZE - Vector2i.ONE)).clamp(Vector2.ZERO, Vector2(GRID_SIZE - Vector2i.ONE))
	var x := mini(floori(grid.x), GRID_SIZE.x - 2)
	var y := mini(floori(grid.y), GRID_SIZE.y - 2)
	var fraction := grid - Vector2(x, y)
	var low := lerpf(_charge[y * GRID_SIZE.x + x], _charge[y * GRID_SIZE.x + x + 1], fraction.x)
	var high := lerpf(_charge[(y + 1) * GRID_SIZE.x + x], _charge[(y + 1) * GRID_SIZE.x + x + 1], fraction.x)
	return lerpf(low, high, fraction.y)


func _sample_runoff_supply(point: Vector2) -> float:
	var grid := ((point / WORLD_SIZE + Vector2(0.5, 0.5)) * Vector2(GRID_SIZE - Vector2i.ONE)).clamp(Vector2.ZERO, Vector2(GRID_SIZE - Vector2i.ONE))
	var x := mini(floori(grid.x), GRID_SIZE.x - 2)
	var y := mini(floori(grid.y), GRID_SIZE.y - 2)
	# At most one coarse cell (~3.3cm) around the endpoint. A max avoids
	# interpolating never-supplied timestamps into otherwise valid local flow.
	return maxf(maxf(_runoff_supplied[y * GRID_SIZE.x + x], _runoff_supplied[y * GRID_SIZE.x + x + 1]),
		maxf(_runoff_supplied[(y + 1) * GRID_SIZE.x + x], _runoff_supplied[(y + 1) * GRID_SIZE.x + x + 1]))


func _build_runoff_sources() -> void:
	# A fixed map along the BODY perimeter merges adjacent contour pieces into
	# broad mouths. Individual strips never become their own long spiky fans.
	_mouth_times.fill(-1000.0)
	_mouth_powers.fill(0.0)
	_mouths_funded = 0
	for slot in active_segments:
		if _spill_starts[slot] <= 0.0 and _spill_ends[slot] <= 0.0:
			continue
		var supplied := -1000.0
		if _spill_starts[slot] > 0.0:
			supplied = maxf(supplied, _runoff_sources_start[slot])
		if _spill_ends[slot] > 0.0:
			supplied = maxf(supplied, _runoff_sources_end[slot])
		if clock_seconds - supplied > StreamEffect.SOURCE_GRACE:
			continue
		var power := maxf(_pressure_starts[slot], _pressure_ends[slot])
		_record_mouth_bin((_starts[slot] + _ends[slot]) * 0.5, supplied, power)
		if _spill_starts[slot] > 0.0:
			_record_mouth_bin(_starts[slot], supplied, power)
		if _spill_ends[slot] > 0.0:
			_record_mouth_bin(_ends[slot], supplied, power)
	streams.begin_sources(clock_seconds)
	var first := 0
	for bin in MOUTH_BINS:
		if clock_seconds - _mouth_times[bin] > StreamEffect.SOURCE_GRACE:
			first = (bin + 1) % MOUTH_BINS
			break
	var offset := 0
	var bin_length := _body_perimeter / float(MOUTH_BINS)
	while offset < MOUTH_BINS and _mouths_funded < MAX_MOUTHS:
		var start := (first + offset) % MOUTH_BINS
		if clock_seconds - _mouth_times[start] > StreamEffect.SOURCE_GRACE:
			offset += 1
			continue
		var initial_frame := _body_frame((float(start) + 0.5) * bin_length)
		var initial_normal := Vector2(initial_frame.z, initial_frame.w)
		var count := 0
		var supplied := -1000.0
		var power := 0.0
		var fresh := false
		while offset + count < MOUTH_BINS and float(count + 1) * bin_length <= MAX_MOUTH_WIDTH:
			var bin := (start + count) % MOUTH_BINS
			if clock_seconds - _mouth_times[bin] > StreamEffect.SOURCE_GRACE:
				break
			var frame := _body_frame((float(bin) + 0.5) * bin_length)
			if count > 0 and Vector2(frame.z, frame.w).dot(initial_normal) < 0.88:
				break
			fresh = fresh or _mouth_times[bin] > _mouth_consumed[bin] + 0.00001
			supplied = maxf(supplied, _mouth_times[bin])
			power = maxf(power, _mouth_powers[bin])
			count += 1
		if count == 0:
			offset += 1
			continue
		if fresh:
			var frame := _body_frame((float(start) + float(count) * 0.5) * bin_length)
			var center := Vector3(frame.x, RUG_Y, frame.y)
			var direction := Vector3(frame.z, 0.0, frame.w)
			streams.feed_source(center, direction, maxf(0.12, float(count) * bin_length), maxf(power, 0.10), supplied)
			for member in count:
				var bin := (start + member) % MOUTH_BINS
				_mouth_consumed[bin] = maxf(_mouth_consumed[bin], _mouth_times[bin])
			_mouths_funded += 1
		offset += count
	streams.end_sources()


func _record_mouth_bin(point: Vector2, supplied: float, power: float) -> void:
	var closest_distance := INF
	var arc := 0.0
	for edge in _body_polygon.size():
		var a := _body_polygon[edge]
		var b := _body_polygon[(edge + 1) % _body_polygon.size()]
		var nearest := Geometry2D.get_closest_point_to_segment(point, a, b)
		var distance := nearest.distance_squared_to(point)
		if distance < closest_distance:
			closest_distance = distance
			arc = _body_arc_offsets[edge] + a.distance_to(nearest)
	var bin := floori(fposmod(arc / _body_perimeter, 1.0) * MOUTH_BINS) % MOUTH_BINS
	_mouth_times[bin] = maxf(_mouth_times[bin], supplied)
	_mouth_powers[bin] = maxf(_mouth_powers[bin], power)


func _body_frame(distance: float) -> Vector4:
	var arc := fposmod(distance, _body_perimeter)
	for edge in _body_polygon.size():
		var a := _body_polygon[edge]
		var b := _body_polygon[(edge + 1) % _body_polygon.size()]
		var length := a.distance_to(b)
		if arc <= _body_arc_offsets[edge] + length or edge == _body_polygon.size() - 1:
			var tangent := (b - a).normalized()
			var point := a.lerp(b, clampf((arc - _body_arc_offsets[edge]) / maxf(length, 0.00001), 0.0, 1.0))
			var outward := Vector2(-tangent.y, tangent.x)
			if _body_at(point + outward * 0.020):
				outward = -outward
			return Vector4(point.x, point.y, outward.x, outward.y)
	return Vector4.ZERO


func _strip_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in ROWS:
		for side in 2:
			vertices.append(Vector3(float(side) - 0.5, 0.0, float(row) / float(ROWS - 1)))
			normals.append(Vector3.UP)
			uv.append(Vector2(float(side), float(row) / float(ROWS - 1)))
	for row in ROWS - 1:
		var a := row * 2
		indices.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
