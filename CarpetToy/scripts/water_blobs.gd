extends Node3D
## Pooled phone-friendly water visuals. Wetness and extraction live in the
## existing DirtController L8 mask; this node owns only charge, fall and splash.

signal drop_charge_changed(fraction: float, active: bool)
signal blob_absorbed(world_position: Vector3, radius: float)

const DROP_CAPACITY := 16
const SPLASH_CAPACITY := 16
const EMISSION_RATE := 1.5
const CLOCK_PERIOD := 8.0
const LAUNCH_HEIGHT := 0.50
const FLIGHT_SECONDS := 0.42
const SPLASH_SECONDS := 0.30
const MAX_BIRTHS_PER_FRAME := 2
const SURFACE_HEIGHT := 0.071
const DROP_RADIUS_MIN := 0.095
const DROP_RADIUS_MAX := 0.125
const WET_RADIUS_MIN := 0.30
const WET_RADIUS_MAX := 0.38
const SPLASH_RADIUS_SCALE := 1.28

var enabled := false
var emitting := false
var emission_locked := false
var drop_batch: MultiMesh
var splash_batch: MultiMesh
var drops: MultiMeshInstance3D
var splashes: MultiMeshInstance3D
var drop_material: ShaderMaterial
var splash_material: ShaderMaterial
var footprint: RefCounted

var nozzle := Vector3.ZERO
var target := Vector3.ZERO
var previous_target := Vector3.ZERO
var active_drop_slots: Array[int] = []
var active_splash_slots: Array[int] = []
var drop_targets := PackedVector3Array()
var drop_land_at := PackedFloat64Array()
var drop_wet_radii := PackedFloat32Array()
var splash_centers := PackedVector2Array()
var splash_absorb_at := PackedFloat64Array()
var splash_wet_radii := PackedFloat32Array()

var clock_seconds := 0.0
var emission_accumulator := 0.0
var next_drop_slot := 0
var next_splash_slot := 0
var rng := RandomNumberGenerator.new()

var emitted_count := 0
var landed_count := 0
var splash_started_count := 0
var absorbed_count := 0
var process_count := 0
var cpu_usec_total := 0
var cpu_usec_max := 0


func setup(rug_footprint: RefCounted) -> void:
	assert(drop_batch == null, "Water resources are allocated only once")
	footprint = rug_footprint
	rng.randomize()
	drop_targets.resize(DROP_CAPACITY)
	drop_land_at.resize(DROP_CAPACITY)
	drop_wet_radii.resize(DROP_CAPACITY)
	splash_centers.resize(SPLASH_CAPACITY)
	splash_absorb_at.resize(SPLASH_CAPACITY)
	splash_wet_radii.resize(SPLASH_CAPACITY)

	drops = MultiMeshInstance3D.new()
	drops.name = "FallingWater16"
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drops.custom_aabb = AABB(Vector3(-1.7, -0.1, -2.4), Vector3(3.4, 1.4, 4.8))
	drop_batch = MultiMesh.new()
	drop_batch.transform_format = MultiMesh.TRANSFORM_3D
	drop_batch.use_custom_data = true
	var drop_mesh := SphereMesh.new()
	drop_mesh.radius = 1.0
	drop_mesh.height = 2.0
	drop_mesh.radial_segments = 12
	drop_mesh.rings = 7
	drop_batch.mesh = drop_mesh
	drop_batch.instance_count = DROP_CAPACITY
	drop_batch.visible_instance_count = 0
	drops.multimesh = drop_batch
	drop_material = ShaderMaterial.new()
	drop_material.shader = preload("res://scripts/water_drop.gdshader")
	drop_material.set_shader_parameter("launch_height", LAUNCH_HEIGHT)
	drops.material_override = drop_material
	add_child(drops)

	splashes = MultiMeshInstance3D.new()
	splashes.name = "WaterSplashes16"
	splashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	splashes.custom_aabb = AABB(Vector3(-1.7, 0.0, -2.4), Vector3(3.4, 0.4, 4.8))
	splash_batch = MultiMesh.new()
	splash_batch.transform_format = MultiMesh.TRANSFORM_3D
	splash_batch.use_custom_data = true
	var splash_mesh := QuadMesh.new()
	splash_mesh.size = Vector2(2.0, 2.0)
	splash_batch.mesh = splash_mesh
	splash_batch.instance_count = SPLASH_CAPACITY
	splash_batch.visible_instance_count = 0
	splashes.multimesh = splash_batch
	splash_material = ShaderMaterial.new()
	splash_material.shader = preload("res://scripts/water_splash.gdshader")
	splashes.material_override = splash_material
	add_child(splashes)
	reset()


func set_enabled(value: bool) -> void:
	enabled = value
	reset()


func set_emission_locked(value: bool) -> void:
	emission_locked = value
	if value and emitting:
		emitting = false
		emission_accumulator = 0.0
		drop_charge_changed.emit(0.0, false)
	_refresh_processing()


func set_emitter(active: bool, from: Vector3, to: Vector3) -> void:
	nozzle = from
	target = to
	var can_emit := active and enabled and not emission_locked
	var starting := can_emit and not emitting
	emitting = can_emit
	if starting:
		previous_target = target
		# The first large blob uses the same readable charge cycle as later blobs.
		emission_accumulator = 0.0
	if not emitting:
		emission_accumulator = 0.0
	drop_charge_changed.emit(charge_fraction(), emitting)
	_refresh_processing()


func charge_fraction() -> float:
	return clampf(emission_accumulator * EMISSION_RATE, 0.0, 1.0) if emitting else 0.0


func reset() -> void:
	if drop_batch == null:
		return
	emitting = false
	emission_locked = false
	active_drop_slots.clear()
	active_splash_slots.clear()
	emission_accumulator = 0.0
	clock_seconds = 0.0
	next_drop_slot = 0
	next_splash_slot = 0
	emitted_count = 0
	landed_count = 0
	splash_started_count = 0
	absorbed_count = 0
	process_count = 0
	cpu_usec_total = 0
	cpu_usec_max = 0
	for slot in DROP_CAPACITY:
		drop_batch.set_instance_custom_data(slot, Color(0.0, 0.0, 0.0, 0.0))
	for slot in SPLASH_CAPACITY:
		splash_batch.set_instance_custom_data(slot, Color(0.0, 0.0, 0.0, 0.0))
	drop_batch.visible_instance_count = 0
	splash_batch.visible_instance_count = 0
	drop_material.set_shader_parameter("water_clock", 0.0)
	splash_material.set_shader_parameter("water_clock", 0.0)
	drop_charge_changed.emit(0.0, false)
	_refresh_processing()


func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	# A slow frame cannot replay seconds of drops or create an emission backlog.
	var step := minf(delta, 0.1)
	clock_seconds += step
	if emitting:
		emission_accumulator += step
		var births := mini(MAX_BIRTHS_PER_FRAME, floori(emission_accumulator * EMISSION_RATE))
		if births > 0:
			emission_accumulator = fmod(emission_accumulator, 1.0 / EMISSION_RATE)
			for index in births:
				var at := previous_target.lerp(target, float(index + 1) / float(births))
				_spawn_drop(at)
		previous_target = target
		drop_charge_changed.emit(charge_fraction(), true)

	for index in range(active_drop_slots.size() - 1, -1, -1):
		var slot := active_drop_slots[index]
		if clock_seconds < drop_land_at[slot]:
			continue
		landed_count += 1
		drop_batch.set_instance_custom_data(slot, Color(0.0, 0.0, 0.0, 0.0))
		active_drop_slots.remove_at(index)
		_spawn_splash(Vector2(drop_targets[slot].x, drop_targets[slot].z), drop_wet_radii[slot])

	for index in range(active_splash_slots.size() - 1, -1, -1):
		var slot := active_splash_slots[index]
		if clock_seconds < splash_absorb_at[slot]:
			continue
		var center := splash_centers[slot]
		blob_absorbed.emit(Vector3(center.x, SURFACE_HEIGHT, center.y), splash_wet_radii[slot])
		absorbed_count += 1
		splash_batch.set_instance_custom_data(slot, Color(0.0, 0.0, 0.0, 0.0))
		active_splash_slots.remove_at(index)

	drop_batch.visible_instance_count = DROP_CAPACITY if not active_drop_slots.is_empty() else 0
	splash_batch.visible_instance_count = SPLASH_CAPACITY if not active_splash_slots.is_empty() else 0
	var wrapped_clock := fmod(clock_seconds, CLOCK_PERIOD)
	if not active_drop_slots.is_empty():
		drop_material.set_shader_parameter("water_clock", wrapped_clock)
	if not active_splash_slots.is_empty():
		splash_material.set_shader_parameter("water_clock", wrapped_clock)
	process_count += 1
	var elapsed := Time.get_ticks_usec() - started
	cpu_usec_total += elapsed
	cpu_usec_max = maxi(cpu_usec_max, elapsed)
	_refresh_processing()


func _spawn_drop(at: Vector3) -> void:
	if not footprint.contains_point(Vector2(at.x, at.z)) or active_drop_slots.size() >= DROP_CAPACITY:
		return
	var slot := next_drop_slot
	for _attempt in DROP_CAPACITY:
		if slot not in active_drop_slots:
			break
		slot = (slot + 1) % DROP_CAPACITY
	next_drop_slot = (slot + 1) % DROP_CAPACITY
	var jitter := Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(0.018, 0.055)
	var landing := Vector3(at.x + jitter.x, SURFACE_HEIGHT - 0.003, at.z + jitter.y)
	if not footprint.contains_point(Vector2(landing.x, landing.z)):
		landing = Vector3(at.x, SURFACE_HEIGHT - 0.003, at.z)
	var visual_radius := rng.randf_range(DROP_RADIUS_MIN, DROP_RADIUS_MAX)
	var duration := FLIGHT_SECONDS + rng.randf_range(-0.035, 0.035)
	drop_targets[slot] = landing
	drop_wet_radii[slot] = rng.randf_range(WET_RADIUS_MIN, WET_RADIUS_MAX)
	drop_land_at[slot] = clock_seconds + duration
	drop_batch.set_instance_transform(slot, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * visual_radius), landing))
	# Compatibility stores custom data at half precision, so birth wraps every
	# eight seconds. The shader uses modulo age and duration prevents revival.
	var offset := nozzle - landing
	var planar := Vector2(offset.x, offset.z).limit_length(0.30)
	drop_batch.set_instance_custom_data(slot, Color(fmod(clock_seconds, CLOCK_PERIOD), duration, planar.x, planar.y))
	active_drop_slots.append(slot)
	emitted_count += 1


func _spawn_splash(center: Vector2, wet_radius: float) -> void:
	splash_started_count += 1
	if active_splash_slots.size() >= SPLASH_CAPACITY:
		blob_absorbed.emit(Vector3(center.x, SURFACE_HEIGHT, center.y), wet_radius)
		absorbed_count += 1
		return
	var slot := next_splash_slot
	for _attempt in SPLASH_CAPACITY:
		if slot not in active_splash_slots:
			break
		slot = (slot + 1) % SPLASH_CAPACITY
	next_splash_slot = (slot + 1) % SPLASH_CAPACITY
	splash_centers[slot] = center
	splash_wet_radii[slot] = wet_radius
	splash_absorb_at[slot] = clock_seconds + SPLASH_SECONDS
	var radius := wet_radius * SPLASH_RADIUS_SCALE
	var basis := Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3(radius, radius, 1.0))
	splash_batch.set_instance_transform(slot, Transform3D(basis, Vector3(center.x, SURFACE_HEIGHT + 0.006, center.y)))
	splash_batch.set_instance_custom_data(slot, Color(fmod(clock_seconds, CLOCK_PERIOD), SPLASH_SECONDS, rng.randf_range(0.0, TAU), 1.0))
	active_splash_slots.append(slot)


func _refresh_processing() -> void:
	set_process(enabled and (emitting or not active_drop_slots.is_empty() or not active_splash_slots.is_empty()))


func debug_stats() -> Dictionary:
	return {
		"emitted": emitted_count,
		"landed": landed_count,
		"splashed": splash_started_count,
		"splash_started": splash_started_count,
		"absorbed": absorbed_count,
		"active_drops": active_drop_slots.size(),
		"active_splashes": active_splash_slots.size(),
		"pending_absorptions": active_splash_slots.size(),
		"drop_capacity": DROP_CAPACITY,
		"pool_capacity": DROP_CAPACITY,
		"splash_capacity": SPLASH_CAPACITY,
		"emission_rate": EMISSION_RATE,
		"charge": charge_fraction(),
		"emission_locked": emission_locked,
		"drop_radius_min": DROP_RADIUS_MIN,
		"drop_radius_max": DROP_RADIUS_MAX,
		"wet_radius_min": WET_RADIUS_MIN,
		"wet_radius_max": WET_RADIUS_MAX,
		"processing": is_processing(),
		"process_count": process_count,
		"cpu_usec_total": cpu_usec_total,
		"cpu_usec_max": cpu_usec_max,
	}
