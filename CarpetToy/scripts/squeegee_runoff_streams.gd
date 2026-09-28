extends Node3D
## Fixed pool of broad, fast, matte runoff ribbons. Sources are funded by fresh
## LOCAL extraction; emitted packets remain world anchored and never follow tools.

const CAPACITY := 16
const STATIONS := 18
const LANES := 7
const SPEED := 5.2
const LIFETIME := 2.50
const MAX_DISTANCE := 12.60
const FADE_START := 1.65
const SOURCE_GRACE := 0.36
const MAX_FEED_AGE := 0.70
const CAP_RADIUS := 0.17
const CAP_INTERVALS := 4.0
const TILE_EDGE := 7.67
const TILE_SUPPORT_MARGIN := 0.55
const FLOOR_BLEND_DISTANCE := 0.40
const DRAW_BOUNDS := AABB(Vector3(-15.5, -0.2, -15.5), Vector3(31.0, 0.8, 31.0))

var batch: MultiMesh
var node: MultiMeshInstance3D
var material: ShaderMaterial
var clock_seconds := 0.0
var active_packets := 0
var emitted_packets := 0
var rejected_packets := 0
var source_updates := 0
var sources_this_frame := 0
var _surface_texture: Texture2D
var _footprint: RefCounted
var _active := PackedByteArray()
var _feeding := PackedByteArray()
var _origins := PackedVector3Array()
var _directions := PackedVector3Array()
var _widths := PackedFloat32Array()
var _powers := PackedFloat32Array()
var _births := PackedFloat64Array()
var _stops := PackedFloat64Array()
var _deadlines := PackedFloat64Array()
var _last_supplied := PackedFloat64Array()
var _bends := PackedFloat32Array()


func setup(texture: Texture2D = null, footprint: RefCounted = null) -> void:
	assert(batch == null, "Allocate runoff packets only once")
	_surface_texture = texture
	_footprint = footprint
	_active.resize(CAPACITY)
	_feeding.resize(CAPACITY)
	_origins.resize(CAPACITY)
	_directions.resize(CAPACITY)
	_widths.resize(CAPACITY)
	_powers.resize(CAPACITY)
	_births.resize(CAPACITY)
	_stops.resize(CAPACITY)
	_deadlines.resize(CAPACITY)
	_last_supplied.resize(CAPACITY)
	_bends.resize(CAPACITY)
	batch = MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_custom_data = true
	batch.use_colors = true
	batch.mesh = _build_mesh()
	batch.instance_count = CAPACITY
	node = MultiMeshInstance3D.new()
	node.name = "FastMatteRunoffPackets16"
	node.multimesh = batch
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = DRAW_BOUNDS
	material = ShaderMaterial.new()
	material.shader = preload("res://scripts/squeegee_runoff_streams.gdshader")
	material.set_shader_parameter("packet_lifetime", LIFETIME)
	material.set_shader_parameter("fade_start", FADE_START)
	material.set_shader_parameter("cap_radius", CAP_RADIUS)
	material.set_shader_parameter("floor_blend_start", TILE_EDGE + TILE_SUPPORT_MARGIN)
	material.set_shader_parameter("floor_blend_end", TILE_EDGE + TILE_SUPPORT_MARGIN + FLOOR_BLEND_DISTANCE)
	material.set_shader_parameter("use_rug_surface", texture != null)
	if texture != null:
		material.set_shader_parameter("rug_surface", texture)
	node.material_override = material
	add_child(node)
	reset()


func begin_sources(_at: float) -> void:
	sources_this_frame = 0


func feed_source(center: Vector3, outward: Vector3, width: float, power: float, supplied_at: float) -> void:
	if batch == null or clock_seconds - supplied_at > SOURCE_GRACE or power <= 0.0:
		return
	var heading := Vector3(outward.x, 0.0, outward.z).normalized()
	if heading.length_squared() < 0.5:
		return
	var slot := -1
	for index in CAPACITY:
		if _active[index] == 0 or _feeding[index] == 0:
			continue
		if _origins[index].distance_squared_to(center) < 0.28 * 0.28 and _directions[index].dot(heading) > 0.88:
			if supplied_at <= _last_supplied[index] + 0.00001:
				return
			if clock_seconds - _births[index] < MAX_FEED_AGE:
				slot = index
			else:
				_feeding[index] = 0
				_stops[index] = clock_seconds
			break
	if slot < 0:
		for index in CAPACITY:
			if _active[index] == 0:
				slot = index
				break
		if slot < 0:
			rejected_packets += 1
			return
		_active[slot] = 1
		_feeding[slot] = 1
		_origins[slot] = Vector3(center.x, 0.0, center.z)
		_directions[slot] = heading
		_births[slot] = clock_seconds - 0.025
		_stops[slot] = -1.0
		_widths[slot] = clampf(width, 0.12, 1.25)
		_powers[slot] = clampf(power, 0.0, 1.0)
		_bends[slot] = sin(center.x * 2.3 + center.z * 1.7) * 0.105
		active_packets += 1
		emitted_packets += 1
	else:
		# Old emitted geometry never jumps to a new center/direction on rebuild.
		_widths[slot] = lerpf(_widths[slot], clampf(width, 0.12, 1.25), 0.40)
		_powers[slot] = lerpf(_powers[slot], clampf(power, 0.0, 1.0), 0.40)
	_last_supplied[slot] = supplied_at
	_deadlines[slot] = supplied_at + SOURCE_GRACE
	sources_this_frame += 1
	source_updates += 1
	_update_packet(slot)
	node.show()
	batch.visible_instance_count = CAPACITY


func end_sources() -> void:
	# A source keeps only the short grace funded by its last actual delta.
	# Missing/remote notifications never extend its deadline.
	pass


func advance(delta: float) -> void:
	clock_seconds += maxf(delta, 0.0)
	active_packets = 0
	for slot in CAPACITY:
		if _active[slot] == 0:
			continue
		var age := clock_seconds - _births[slot]
		if _feeding[slot] != 0 and (clock_seconds >= _deadlines[slot] or age >= MAX_FEED_AGE):
			_feeding[slot] = 0
			_stops[slot] = minf(_deadlines[slot], _births[slot] + MAX_FEED_AGE)
		if age >= LIFETIME:
			_active[slot] = 0
			_feeding[slot] = 0
			_hide_packet(slot)
			continue
		_update_packet(slot)
		active_packets += 1
	if batch != null:
		material.set_shader_parameter("water_clock", fmod(clock_seconds, 100.0))
		batch.visible_instance_count = CAPACITY if active_packets > 0 else 0
		node.visible = active_packets > 0


func reset() -> void:
	clock_seconds = 0.0
	active_packets = 0
	emitted_packets = 0
	rejected_packets = 0
	source_updates = 0
	sources_this_frame = 0
	_active.fill(0)
	_feeding.fill(0)
	_last_supplied.fill(-1000.0)
	if batch != null:
		for slot in CAPACITY:
			_hide_packet(slot)
		batch.visible_instance_count = 0
		node.hide()


func is_alive() -> bool:
	return active_packets > 0


func debug_stats() -> Dictionary:
	var front := 0.0
	for slot in CAPACITY:
		if _active[slot] != 0:
			front = maxf(front, _front_distance(slot))
	return {"active_packets": active_packets, "emitted_packets": emitted_packets,
		"capacity": CAPACITY, "speed": SPEED, "lifetime": LIFETIME,
		"max_distance": MAX_DISTANCE, "furthest_front": front,
		"rejected_packets": rejected_packets, "source_updates": source_updates,
		"sources_this_frame": sources_this_frame, "mesh_instances": 1,
		"vertices_per_packet": STATIONS * LANES, "bounds": DRAW_BOUNDS}


func packet_debug(slot: int) -> Dictionary:
	assert(slot >= 0 and slot < CAPACITY)
	return {"active": _active[slot] != 0, "feeding": _feeding[slot] != 0,
		"origin": _origins[slot], "direction": _directions[slot],
		"age": maxf(0.0, clock_seconds - _births[slot]),
		"front_distance": _front_distance(slot), "back_distance": _back_distance(slot),
		"width": _widths[slot], "lifetime": LIFETIME, "power": _powers[slot],
		"supplied_at": _last_supplied[slot]}


func sample_packet(slot: int, along: float, across: float) -> Vector3:
	assert(slot >= 0 and slot < CAPACITY)
	var lateral := clampf(across, 0.0, 1.0) * 2.0 - 1.0
	var back := _back_distance(slot)
	var front := _front_distance(slot)
	var distance := _station_distance(back, front, along)
	var fade := 1.0 - smoothstep(FADE_START, LIFETIME, clock_seconds - _births[slot])
	var cap_length := minf(CAP_RADIUS, maxf(front - back, 0.00001) * 0.5)
	var cap := clampf(minf(distance - back, front - distance) / cap_length, 0.0, 1.0)
	var round_cap := sqrt(maxf(0.0, cap * (2.0 - cap)))
	var ripple := 1.0 + 0.07 * sin(distance * 4.4 - fmod(clock_seconds, 100.0) * 5.4 + _origins[slot].x * 1.9 + _origins[slot].z * 0.8)
	var half_width := _widths[slot] * 0.5 * round_cap * sqrt(fade) * lerpf(0.82, 1.0, sqrt(_powers[slot])) * ripple
	var bend := _bends[slot] * sin(distance * 0.85) * smoothstep(0.0, 0.45, distance)
	var side := Vector3.UP.cross(_directions[slot])
	var point := _origins[slot] + _directions[slot] * distance + side * (bend + lateral * half_width)
	# Keep every triangle spanning the tile boundary above the tiles. The extra
	# support margin exceeds the longest longitudinal/cross-lane interval, so
	# interpolation cannot start descending until all of that span is off tile.
	var floor_distance := maxf(absf(point.x), absf(point.z))
	var floor_blend := smoothstep(TILE_EDGE + TILE_SUPPORT_MARGIN, TILE_EDGE + TILE_SUPPORT_MARGIN + FLOOR_BLEND_DISTANCE, floor_distance)
	var support := lerpf(0.006, -0.029, floor_blend)
	if _footprint != null and _footprint.contains_point(Vector2(point.x, point.z)):
		support = 0.071
	var dome := (1.0 - lateral * lateral) * 0.010 * fade
	point.y = support + 0.003 + dome
	return point


func sample_packet_visible(slot: int, _along: float, _across: float) -> bool:
	return _active[slot] != 0 and clock_seconds - _births[slot] < LIFETIME - 0.005


func _front_distance(slot: int) -> float:
	return minf(MAX_DISTANCE, maxf(0.0, clock_seconds - _births[slot]) * SPEED)


func _station_distance(back: float, front: float, along: float) -> float:
	# Fixed physical cap sampling: long packets never turn their rounded ends
	# into a one-triangle trapezoid as the front moves farther from the tail.
	var station := clampf(along, 0.0, 1.0) * float(STATIONS - 1)
	var cap := minf(CAP_RADIUS, maxf(front - back, 0.0) * 0.5)
	if station <= CAP_INTERVALS:
		return back + cap * (1.0 - cos(station / CAP_INTERVALS * PI * 0.5))
	if station >= float(STATIONS - 1) - CAP_INTERVALS:
		return front - cap * (1.0 - cos((float(STATIONS - 1) - station) / CAP_INTERVALS * PI * 0.5))
	return lerpf(back + cap, front - cap, (station - CAP_INTERVALS) / (float(STATIONS - 1) - 2.0 * CAP_INTERVALS))


func _back_distance(slot: int) -> float:
	return 0.0 if _feeding[slot] != 0 or _stops[slot] < 0.0 else minf(_front_distance(slot), maxf(0.0, clock_seconds - _stops[slot]) * SPEED)


func _update_packet(slot: int) -> void:
	var side := Vector3.UP.cross(_directions[slot])
	var frame := Basis(side, Vector3.UP, _directions[slot])
	batch.set_instance_transform(slot, Transform3D(frame, _origins[slot]))
	batch.set_instance_custom_data(slot, Color(_front_distance(slot), _back_distance(slot), _widths[slot], clampf((clock_seconds - _births[slot]) / LIFETIME, 0.0, 1.0)))
	batch.set_instance_color(slot, Color(_powers[slot], (_bends[slot] + 0.12) / 0.24, 1.0, 1.0))


func _hide_packet(slot: int) -> void:
	batch.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -10, 0)))


func _build_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for station in STATIONS:
		for lane in LANES:
			var uv := Vector2(float(station) / float(STATIONS - 1), float(lane) / float(LANES - 1))
			vertices.append(Vector3(uv.y - 0.5, 0, uv.x))
			normals.append(Vector3.UP)
			uvs.append(uv)
	for station in STATIONS - 1:
		for lane in LANES - 1:
			var a := station * LANES + lane
			indices.append_array(PackedInt32Array([a, a + LANES, a + 1, a + 1, a + LANES, a + LANES + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
