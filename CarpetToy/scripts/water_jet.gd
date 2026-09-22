extends Node3D
## One fixed tube, sampled from the nozzle's emission history. The carpet owns
## wetness; this controller owns only flight, contact timing and presentation.

signal water_contact(world_position: Vector3, radius: float, strength: float)
signal soak_contact(world_position: Vector3, radius: float, strength: float)

const ImpactEffect = preload("res://scripts/water_jet_impact.gd")
const HoseProfile = preload("res://scripts/water_hose_profile.gd")
const SoakEffect = preload("res://scripts/water_soak.gd")
const RING_COUNT := 16
const RADIAL_SIDES := 10
const HISTORY_CAPACITY := 96
const HISTORY_STEP := 1.0 / 120.0
const LAUNCH_HEIGHT := 0.50
const NOZZLE_RADIUS := 0.056
const EXIT_SPEED := 2.4
const GRAVITY := Vector3(0.0, -9.8, 0.0)
const MAX_FLIGHT_TIME := 0.65
const SURFACE_HEIGHT := 0.071
const FLOOR_HEIGHT := 0.006
const CONTACT_PLANES := [SURFACE_HEIGHT, FLOOR_HEIGHT]
const COLUMN_WIDEN_START := 0.18
const COLUMN_FULL_AT := 0.88
const COLUMN_WIDEN_POWER := 0.82
const DEPOSIT_INTERVAL := 0.05
const WET_STRENGTH_PER_SECOND := 2.6

var enabled := false
var emitting := false
var emission_locked := false
var nozzle := Vector3.ZERO
var direction := Vector3(0.0, -0.819, 0.574)
var footprint: RefCounted
var stream: MeshInstance3D
var stream_material: ShaderMaterial
var impact: Node3D
var ring_centers := PackedVector3Array()
var ring_data := PackedVector4Array()
var ring_sides := PackedVector3Array()
var history_positions := PackedVector3Array()
var history_velocities := PackedVector3Array()
var history_times := PackedFloat64Array()
var history_count := 0
var history_head := 0
var clock_seconds := 0.0
var started_at := -1.0
var stopped_at := -1.0
var previous_nozzle := Vector3.ZERO
var previous_velocity := Vector3.ZERO
var contact_active := false
var contact_position := Vector3.ZERO
var contact_on_rug := false
var visible_rings := 0
var wet_events := 0
var process_count := 0
var cpu_usec_total := 0
var cpu_usec_max := 0
var deposit_accumulator := 0.0
var previous_contact := Vector3.ZERO
var had_contact := false
var upgrade_level := 0
var profile: Dictionary = HoseProfile.for_level(0)
var soak: RefCounted


func setup(rug_footprint: RefCounted) -> void:
	assert(stream == null, "Jet resources must only be allocated once")
	footprint = rug_footprint
	history_positions.resize(HISTORY_CAPACITY)
	history_velocities.resize(HISTORY_CAPACITY)
	history_times.resize(HISTORY_CAPACITY)
	ring_centers.resize(RING_COUNT)
	ring_data.resize(RING_COUNT)
	ring_sides.resize(RING_COUNT)
	stream = MeshInstance3D.new()
	stream.name = "ContinuousWater"
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stream.mesh = _make_tube()
	stream.custom_aabb = AABB(Vector3(-4.0, -0.2, -4.0), Vector3(8.0, 3.0, 8.0))
	stream_material = ShaderMaterial.new()
	stream_material.shader = preload("res://scripts/water_jet.gdshader")
	stream.material_override = stream_material
	add_child(stream)
	impact = ImpactEffect.new()
	impact.name = "WaterImpact"
	add_child(impact)
	impact.setup()
	soak = SoakEffect.new()
	soak.setup(footprint)
	soak.set_profile(profile)
	soak.soak_contact.connect(_on_soak_contact)
	reset()


func _make_tube() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring in RING_COUNT:
		var along := float(ring) / float(RING_COUNT - 1)
		for side in RADIAL_SIDES:
			var angle := TAU * float(side) / float(RADIAL_SIDES)
			vertices.append(Vector3(cos(angle), along, sin(angle)))
			normals.append(Vector3(cos(angle), 0.0, sin(angle)))
			uv.append(Vector2(float(side) / float(RADIAL_SIDES), along))
	for ring in RING_COUNT - 1:
		for side in RADIAL_SIDES:
			var a := ring * RADIAL_SIDES + side
			var b := ring * RADIAL_SIDES + (side + 1) % RADIAL_SIDES
			var c := a + RADIAL_SIDES
			var d := b + RADIAL_SIDES
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	# Shared topology includes two caps so startup and drained tails stay solid.
	for cap in 2:
		var center := vertices.size()
		vertices.append(Vector3(0.0, float(cap), 0.0))
		normals.append(Vector3.DOWN if cap == 0 else Vector3.UP)
		uv.append(Vector2(-1.0, float(cap)))
		var ring := 0 if cap == 0 else RING_COUNT - 1
		for side in RADIAL_SIDES:
			var a := ring * RADIAL_SIDES + side
			var b := ring * RADIAL_SIDES + (side + 1) % RADIAL_SIDES
			indices.append_array(PackedInt32Array([center, b, a] if cap == 0 else [center, a, b]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func set_enabled(value: bool) -> void:
	enabled = value
	reset()


func set_upgrade_level(level: int) -> void:
	upgrade_level = clampi(level, 0, HoseProfile.MAX_LEVEL)
	profile = HoseProfile.for_level(upgrade_level)
	if soak != null:
		soak.reset()
		soak.set_profile(profile)
	_refresh_processing()


func set_emission_locked(value: bool) -> void:
	if value and not emission_locked and soak != null:
		soak.reset()
	emission_locked = value
	if value and emitting:
		_stop_emitting()
	_refresh_processing()


func set_emitter(active: bool, from: Vector3, exit_direction: Vector3) -> void:
	nozzle = from
	direction = exit_direction.normalized() if exit_direction.length_squared() > 0.0001 else Vector3.DOWN
	var can_emit := active and enabled and not emission_locked
	if can_emit and not emitting:
		# A rapid re-press reconnects the new flow to the still-draining stream.
		# Preserve the emitted parcels so the old impact cannot snap or vanish.
		var reconnecting := started_at >= 0.0 and history_count > 0
		emitting = true
		if not reconnecting:
			started_at = clock_seconds
			history_count = 0
			history_head = 0
		stopped_at = -1.0
		previous_nozzle = nozzle
		previous_velocity = direction * EXIT_SPEED
		_append_history(clock_seconds, nozzle, previous_velocity)
		if not reconnecting:
			deposit_accumulator = 0.0
	elif not can_emit and emitting:
		_stop_emitting()
	_refresh_processing()


func _stop_emitting() -> void:
	emitting = false
	stopped_at = clock_seconds
	_append_history(clock_seconds, nozzle, direction * EXIT_SPEED)


func reset() -> void:
	emitting = false
	emission_locked = false
	clock_seconds = 0.0
	started_at = -1.0
	stopped_at = -1.0
	history_count = 0
	history_head = 0
	visible_rings = 0
	contact_active = false
	contact_on_rug = false
	had_contact = false
	deposit_accumulator = 0.0
	wet_events = 0
	process_count = 0
	cpu_usec_total = 0
	cpu_usec_max = 0
	if soak != null:
		soak.reset()
	if stream != null:
		stream.hide()
		impact.reset()
	set_process(false)


func _append_history(at: float, position: Vector3, velocity: Vector3) -> void:
	if history_count > 0 and absf(history_times[history_head] - at) < 0.00001:
		history_positions[history_head] = position
		history_velocities[history_head] = velocity
		return
	if history_count > 0:
		history_head = (history_head + 1) % HISTORY_CAPACITY
	history_positions[history_head] = position
	history_velocities[history_head] = velocity
	history_times[history_head] = at
	history_count = mini(history_count + 1, HISTORY_CAPACITY)


func _point_at_age(age: float) -> Vector3:
	var at := clock_seconds - age
	var origin := nozzle
	var velocity := direction * EXIT_SPEED
	if not emitting or at < history_times[history_head]:
		var newer := history_head
		origin = history_positions[newer]
		velocity = history_velocities[newer]
		for offset in range(1, history_count):
			var older := (history_head - offset + HISTORY_CAPACITY) % HISTORY_CAPACITY
			if history_times[older] <= at:
				var fraction := clampf((at - history_times[older]) / maxf(history_times[newer] - history_times[older], 0.00001), 0.0, 1.0)
				origin = history_positions[older].lerp(history_positions[newer], fraction)
				velocity = history_velocities[older].lerp(history_velocities[newer], fraction)
				break
			newer = older
			origin = history_positions[older]
			velocity = history_velocities[older]
	elif at < clock_seconds:
		var fraction := clampf((at - history_times[history_head]) / maxf(clock_seconds - history_times[history_head], 0.00001), 0.0, 1.0)
		origin = history_positions[history_head].lerp(nozzle, fraction)
		velocity = history_velocities[history_head].lerp(direction * EXIT_SPEED, fraction)
	return origin + velocity * age + GRAVITY * (0.5 * age * age)


func _surface_height(point: Vector3) -> float:
	return SURFACE_HEIGHT if footprint.contains_point(Vector2(point.x, point.z)) else FLOOR_HEIGHT


func _process(delta: float) -> void:
	var begin_usec := Time.get_ticks_usec()
	var step := clampf(delta, 0.0, 0.1)
	var before := clock_seconds
	clock_seconds += step
	if emitting:
		var last_time := history_times[history_head]
		var next_time := last_time + HISTORY_STEP
		while next_time <= clock_seconds:
			var fraction := clampf((next_time - before) / maxf(step, 0.00001), 0.0, 1.0)
			_append_history(next_time, previous_nozzle.lerp(nozzle, fraction), previous_velocity.lerp(direction * EXIT_SPEED, fraction))
			next_time += HISTORY_STEP
		previous_nozzle = nozzle
		previous_velocity = direction * EXIT_SPEED
	_update_stream()
	impact.update_contact(contact_active, contact_position, float(profile.impact_radius), step)
	_update_wetting(step)
	if not emission_locked:
		soak.update(step)
	process_count += 1
	var elapsed := Time.get_ticks_usec() - begin_usec
	cpu_usec_total += elapsed
	cpu_usec_max = maxi(cpu_usec_max, elapsed)
	_refresh_processing()


func _update_stream() -> void:
	contact_active = false
	contact_on_rug = false
	visible_rings = 0
	if started_at < 0.0 or history_count == 0:
		stream.hide()
		return
	var youngest := 0.0 if emitting else clock_seconds - stopped_at
	var oldest := minf(clock_seconds - started_at, MAX_FLIGHT_TIME)
	if oldest <= youngest + 0.0001:
		stream.hide()
		if not emitting:
			started_at = -1.0
		return
	var first := _point_at_age(youngest)
	if first.y <= _surface_height(first):
		stream.hide()
		started_at = -1.0
		return
	# The Gym has a flat carpet and tiled floor, so analytic plane intersection
	# gives exact contact without physics bodies or ray queries per tube ring.
	var previous := first
	var previous_age := youngest
	for sample_index in range(1, 33):
		var age := lerpf(youngest, oldest, float(sample_index) / 32.0)
		var point := _point_at_age(age)
		# Test the elevated rug first, accepting a crossing only inside its
		# silhouette. The lower tile plane remains available outside the rug.
		for height in CONTACT_PLANES:
			if previous.y < height or point.y > height:
				continue
			var fraction := clampf((previous.y - height) / maxf(previous.y - point.y, 0.00001), 0.0, 1.0)
			var crossing := previous.lerp(point, fraction)
			var on_rug: bool = footprint.contains_point(Vector2(crossing.x, crossing.z))
			if (height == SURFACE_HEIGHT) != on_rug:
				continue
			oldest = lerpf(previous_age, age, fraction)
			contact_position = Vector3(crossing.x, height, crossing.z)
			contact_on_rug = on_rug
			contact_active = true
			break
		if contact_active:
			break
		previous = point
		previous_age = age
	for ring in RING_COUNT:
		var along := float(ring) / float(RING_COUNT - 1)
		var age := lerpf(youngest, oldest, along)
		var center := _point_at_age(age)
		if ring == RING_COUNT - 1 and contact_active:
			center = contact_position
		ring_centers[ring] = center
		var radius := _column_radius(along, contact_active)
		ring_data[ring] = Vector4(center.x, center.y, center.z, radius)
	var side_axis := Vector3.RIGHT
	for ring in RING_COUNT:
		var tangent := (ring_centers[mini(ring + 1, RING_COUNT - 1)] - ring_centers[maxi(ring - 1, 0)]).normalized()
		if tangent.length_squared() < 0.0001:
			tangent = Vector3.DOWN
		# Parallel transport prevents visible tube twists during tight drags.
		side_axis = side_axis - tangent * side_axis.dot(tangent)
		if side_axis.length_squared() < 0.0001:
			side_axis = tangent.cross(Vector3.FORWARD)
		side_axis = side_axis.normalized()
		ring_sides[ring] = side_axis
	stream_material.set_shader_parameter("ring_data", ring_data)
	stream_material.set_shader_parameter("ring_sides", ring_sides)
	stream_material.set_shader_parameter("water_clock", fmod(clock_seconds, 60.0))
	stream.show()
	visible_rings = RING_COUNT


func _column_radius(along: float, has_contact: bool) -> float:
	# Keep the exit seated in the physical nozzle. Once the jet is established,
	# open it gradually so about half of the upgrade's added width is already
	# visible halfway to the carpet instead of appearing as a terminal flare.
	var distance := clampf(along, 0.0, 1.0)
	var narrow_core := NOZZLE_RADIUS * lerpf(1.0, 0.96, distance)
	if not has_contact or distance <= 0.0:
		return narrow_core
	var tip_radius := float(profile.stream_tip_radius)
	var opening := pow(smoothstep(COLUMN_WIDEN_START, COLUMN_FULL_AT, distance), COLUMN_WIDEN_POWER)
	# The monotone curve makes the middle look substantial without forming a
	# bulb that would have to pinch again before it reaches the impact crown.
	return lerpf(NOZZLE_RADIUS, tip_radius, opening)


func _update_wetting(step: float) -> void:
	var wet_radius := float(profile.wet_radius)
	var wet_rate := WET_STRENGTH_PER_SECOND * float(profile.soak_multiplier)
	if not contact_active or not contact_on_rug or emission_locked:
		# A short tap still delivers its final fraction of water on landing.
		if had_contact and deposit_accumulator > 0.0 and not emission_locked:
			soak.feed(previous_contact, deposit_accumulator)
			water_contact.emit(previous_contact, wet_radius, deposit_accumulator * wet_rate)
			wet_events += 1
		had_contact = false
		deposit_accumulator = 0.0
		return
	if not had_contact:
		previous_contact = contact_position
		had_contact = true
	deposit_accumulator += step
	if deposit_accumulator < DEPOSIT_INTERVAL:
		return
	var duration := minf(deposit_accumulator, 0.1)
	deposit_accumulator = 0.0
	var distance := previous_contact.distance_to(contact_position)
	var stamps := clampi(ceili(distance / (wet_radius * 0.45)), 1, 8)
	for stamp in stamps:
		if emission_locked:
			break
		var position := previous_contact.lerp(contact_position, float(stamp + 1) / float(stamps))
		if not footprint.contains_point(Vector2(position.x, position.z)):
			continue
		soak.feed(position, duration / float(stamps))
		water_contact.emit(position, wet_radius, duration * wet_rate / float(stamps))
		wet_events += 1
	previous_contact = contact_position


func _on_soak_contact(position: Vector3, radius: float, strength: float) -> void:
	if enabled and not emission_locked:
		soak_contact.emit(position, radius, strength)


func _refresh_processing() -> void:
	set_process(enabled and (emitting or started_at >= 0.0 or (impact != null and impact.is_alive()) or (soak != null and soak.is_alive())))


func debug_stats() -> Dictionary:
	var impact_stats: Dictionary = impact.debug_stats() if impact != null else {}
	return {
		"processing": is_processing(), "contact_active": contact_active,
		"contact_on_rug": contact_on_rug, "contact_position": contact_position,
		"visible_rings": visible_rings, "ring_count": RING_COUNT,
		"ring_centers": ring_centers, "history_count": history_count,
		"history_capacity": HISTORY_CAPACITY, "wet_events": wet_events,
		"process_count": process_count, "active_droplets": impact_stats.get("active_droplets", 0),
		"emitting": emitting, "emission_locked": emission_locked,
		"upgrade_level": upgrade_level, "profile": profile.duplicate(),
		"soak": soak.debug_stats() if soak != null else {},
		"cpu_usec_total": cpu_usec_total, "cpu_usec_max": cpu_usec_max,
	}
