extends Node3D
## Bounded visual water: GPU-only density stamps and vertex-animated droplets.
## No physics bodies, per-frame image uploads, or production GPU readbacks.
const FIELD_SIZE := Vector2i(192, 320)
const RUG_SIZE := Vector2(2.0, 3.32)
const DROP_CAPACITY := 32
const STAMP_CAPACITY := DROP_CAPACITY * 3
const EMISSION_RATE := 16.0
const FIELD_INTERVAL := 1.0 / 30.0
const CLOCK_PERIOD := 8.0
const LAUNCH_HEIGHT := 0.30
const FLIGHT_SECONDS := 0.24
const MAX_BIRTHS_PER_FRAME := 2

var enabled := false
var emitting := false
var field_viewport: SubViewport
var drop_batch: MultiMesh
var stamp_batch: MultiMesh
var drops: MultiMeshInstance3D
var drop_material: ShaderMaterial
var surface_materials: Array[ShaderMaterial] = []
var footprint: RefCounted
var nozzle := Vector3.ZERO
var target := Vector3.ZERO
var previous_target := Vector3.ZERO
var active_slots: Array[int] = []
var pending_stamps: Array[Vector4] = []
var targets := PackedVector3Array()
var land_at := PackedFloat64Array()
var radii := PackedFloat32Array()
var clock_seconds := 0.0
var emission_accumulator := 0.0
var field_cooldown := 0.0
var next_slot := 0
var clear_pending := false
var field_frame_pending := false
var rng := RandomNumberGenerator.new()
var emitted_count := 0
var landed_count := 0
var field_update_count := 0
var process_count := 0
var cpu_usec_total := 0
var cpu_usec_max := 0

func setup(materials: Array[ShaderMaterial], rug_footprint: RefCounted) -> void:
	assert(field_viewport == null, "Water resources are allocated only once")
	surface_materials = materials
	footprint = rug_footprint
	rng.randomize()
	targets.resize(DROP_CAPACITY)
	land_at.resize(DROP_CAPACITY)
	radii.resize(DROP_CAPACITY)
	field_viewport = SubViewport.new()
	field_viewport.name = "WaterDensity192x320"
	field_viewport.size = FIELD_SIZE
	field_viewport.disable_3d = true
	field_viewport.world_2d = World2D.new()
	field_viewport.transparent_bg = true
	field_viewport.gui_disable_input = true
	field_viewport.msaa_2d = Viewport.MSAA_DISABLED
	field_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(field_viewport)
	var stamps := MultiMeshInstance2D.new()
	stamps.name = "NewLandingStamps"
	stamp_batch = MultiMesh.new()
	stamp_batch.transform_format = MultiMesh.TRANSFORM_2D
	stamp_batch.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	stamp_batch.mesh = quad
	stamp_batch.instance_count = STAMP_CAPACITY
	stamp_batch.visible_instance_count = 0
	stamps.multimesh = stamp_batch
	var density_material := ShaderMaterial.new()
	density_material.shader = preload("res://scripts/water_density.gdshader")
	stamps.material = density_material
	field_viewport.add_child(stamps)
	drops = MultiMeshInstance3D.new()
	drops.name = "FallingWater32"
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drops.custom_aabb = AABB(Vector3(-1.5, -0.1, -2.2), Vector3(3.0, 1.0, 4.4))
	drop_batch = MultiMesh.new()
	drop_batch.transform_format = MultiMesh.TRANSFORM_3D
	drop_batch.use_custom_data = true
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	drop_batch.mesh = sphere
	drop_batch.instance_count = DROP_CAPACITY
	drop_batch.visible_instance_count = 0
	drops.multimesh = drop_batch
	drop_material = ShaderMaterial.new()
	drop_material.shader = preload("res://scripts/water_drop.gdshader")
	drop_material.set_shader_parameter("launch_height", LAUNCH_HEIGHT)
	drops.material_override = drop_material
	add_child(drops)
	for material in surface_materials:
		material.set_shader_parameter("blob_density", field_viewport.get_texture())
		material.set_shader_parameter("blob_texel_size", Vector2.ONE / Vector2(FIELD_SIZE))
		material.set_shader_parameter("blob_enabled", false)
	reset()

func set_enabled(value: bool) -> void:
	enabled = value
	reset()
	for material in surface_materials:
		material.set_shader_parameter("blob_enabled", value)

func set_emitter(active: bool, from: Vector3, to: Vector3) -> void:
	nozzle = from
	target = to
	var start := active and enabled and not emitting
	emitting = active and enabled
	if start:
		previous_target = target
		# A fresh press releases a drop promptly; a stationary hose keeps pouring.
		emission_accumulator = 1.0 / EMISSION_RATE
	if not emitting: emission_accumulator = 0.0
	_refresh_processing()

func reset() -> void:
	if field_viewport == null: return
	emitting = false
	active_slots.clear()
	pending_stamps.clear()
	emission_accumulator = 0.0
	clock_seconds = 0.0
	field_cooldown = 0.0
	next_slot = 0
	emitted_count = 0
	landed_count = 0
	field_update_count = 0
	process_count = 0
	cpu_usec_total = 0
	cpu_usec_max = 0
	for slot in DROP_CAPACITY:
		drop_batch.set_instance_custom_data(slot, Color(0, 0, 0, 0))
	drop_batch.visible_instance_count = 0
	drop_material.set_shader_parameter("water_clock", 0.0)
	stamp_batch.visible_instance_count = 0
	# ONCE clears exactly one render, then automatically becomes NEVER.
	clear_pending = true
	field_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_submit_field_frame()
	_refresh_processing()

func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	# A slow frame cannot create an emission backlog or unbounded landing work.
	var step := minf(delta, 0.1)
	clock_seconds += step
	field_cooldown = maxf(0.0, field_cooldown - step)
	if emitting:
		emission_accumulator += step
		var births := mini(MAX_BIRTHS_PER_FRAME, floori(emission_accumulator * EMISSION_RATE))
		if births > 0:
			emission_accumulator = fmod(emission_accumulator, 1.0 / EMISSION_RATE)
			for i in births:
				var at := previous_target.lerp(target, float(i + 1) / float(births))
				_spawn_drop(at)
		previous_target = target
	for index in range(active_slots.size() - 1, -1, -1):
		var slot := active_slots[index]
		if clock_seconds < land_at[slot]: continue
		var point := targets[slot]
		if pending_stamps.size() < DROP_CAPACITY:
			pending_stamps.append(Vector4(point.x, point.z, radii[slot], rng.randf_range(0.0, TAU)))
		landed_count += 1
		drop_batch.set_instance_custom_data(slot, Color(0, 0, 0, 0))
		active_slots.remove_at(index)
	drop_batch.visible_instance_count = DROP_CAPACITY if not active_slots.is_empty() else 0
	if not active_slots.is_empty():
		drop_material.set_shader_parameter("water_clock", fmod(clock_seconds, CLOCK_PERIOD))
	if not clear_pending and not field_frame_pending and field_cooldown <= 0.0 and not pending_stamps.is_empty():
		_flush_stamps()
	process_count += 1
	var elapsed := Time.get_ticks_usec() - started
	cpu_usec_total += elapsed
	cpu_usec_max = maxi(cpu_usec_max, elapsed)
	_refresh_processing()

func _spawn_drop(at: Vector3) -> void:
	# The shader is attached to the rug itself, so empty fringe gaps and rounded
	# corners cannot receive floating rectangular puddles.
	if not footprint.contains_point(Vector2(at.x, at.z)): return
	if active_slots.size() >= DROP_CAPACITY: return
	var slot := next_slot
	for _attempt in DROP_CAPACITY:
		if slot not in active_slots: break
		slot = (slot + 1) % DROP_CAPACITY
	next_slot = (slot + 1) % DROP_CAPACITY
	var jitter := Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(0.015, 0.065)
	var landing := Vector3(at.x + jitter.x, 0.068, at.z + jitter.y)
	if not footprint.contains_point(Vector2(landing.x, landing.z)):
		landing = Vector3(at.x, 0.068, at.z)
	var radius := rng.randf_range(0.032, 0.050)
	var duration := FLIGHT_SECONDS + rng.randf_range(-0.025, 0.025)
	targets[slot] = landing
	radii[slot] = rng.randf_range(0.14, 0.19)
	land_at[slot] = clock_seconds + duration
	drop_batch.set_instance_transform(slot, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), landing))
	# Compatibility stores custom data at half precision: birth wraps every 8s.
	var offset := nozzle - landing
	# Fast mouse jumps must not stretch the stream all the way across the rug.
	var planar := Vector2(offset.x, offset.z).limit_length(0.22)
	drop_batch.set_instance_custom_data(slot, Color(fmod(clock_seconds, CLOCK_PERIOD), duration, planar.x, planar.y))
	active_slots.append(slot)
	emitted_count += 1

func _flush_stamps() -> void:
	var count := 0
	for stamp in pending_stamps:
		var center := Vector2(stamp.x, stamp.y)
		var radius := stamp.z
		var direction := Vector2.from_angle(stamp.w)
		_write_stamp(count, center, radius, 0.65)
		_write_stamp(count + 1, center + direction * radius * 0.44, radius * 0.72, 0.30)
		_write_stamp(count + 2, center - direction * radius * 0.38, radius * 0.66, 0.28)
		count += 3
	# Only this frame's NEW landings are redrawn into the preserved field.
	stamp_batch.visible_instance_count = count
	pending_stamps.clear()
	field_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	field_cooldown = FIELD_INTERVAL
	field_update_count += 1
	_submit_field_frame()

func _write_stamp(index: int, center: Vector2, radius: float, strength: float) -> void:
	var pixel_center := (center / RUG_SIZE + Vector2.ONE * 0.5) * Vector2(FIELD_SIZE)
	var pixel_radius := Vector2.ONE * radius / RUG_SIZE * Vector2(FIELD_SIZE)
	stamp_batch.set_instance_transform_2d(index, Transform2D(Vector2(pixel_radius.x, 0), Vector2(0, pixel_radius.y), pixel_center))
	stamp_batch.set_instance_color(index, Color(strength, strength, strength, 1.0))

func _submit_field_frame() -> void:
	field_frame_pending = true
	field_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not RenderingServer.frame_post_draw.is_connected(_field_rendered):
		RenderingServer.frame_post_draw.connect(_field_rendered, CONNECT_ONE_SHOT)

func _field_rendered() -> void:
	field_frame_pending = false
	clear_pending = false
	_refresh_processing()

func _refresh_processing() -> void:
	set_process(enabled and (emitting or not active_slots.is_empty() or not pending_stamps.is_empty()))

func debug_stats() -> Dictionary:
	return {
		"emitted": emitted_count, "landed": landed_count,
		"field_updates": field_update_count, "active_drops": active_slots.size(),
		"pool_capacity": DROP_CAPACITY, "field_size": FIELD_SIZE,
		"processing": is_processing(), "pending_stamps": pending_stamps.size(),
		"process_count": process_count, "cpu_usec_total": cpu_usec_total,
		"cpu_usec_max": cpu_usec_max, "field_pending": field_frame_pending,
	}

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_field_rendered):
		RenderingServer.frame_post_draw.disconnect(_field_rendered)
