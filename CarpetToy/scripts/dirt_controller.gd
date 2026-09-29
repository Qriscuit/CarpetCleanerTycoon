extends Node
## One fixed GPU pool, no rigid bodies. Only airborne/sliding clumps are simulated.
signal progress_changed(remaining: int, total: int)
signal vacuum_started
signal vacuum_finished
signal surface_changed

const VACUUM_SECONDS := 1.8
var completion_started := false
var automatic_completion_enabled := true
var head_half := Vector2(0.305, 0.11)
var vacuum_complete := false
var vacuum_elapsed := 0.0
var vacuum_origins: Array[Vector3] = []
var vacuum_growth: Array[float] = []
var vacuum_target := Vector3.ZERO
var clump_colors: Array[Color] = []
var render_dirty := false
var surface_materials: Array[ShaderMaterial] = []
var rug_definition: Resource = preload("res://resources/rugs/mint_meadow.tres")
var reveal_progress := 1.0
var simulation_suspended := false
var scatter_rng := RandomNumberGenerator.new()

func configure_rug(definition: Resource) -> void:
	rug_definition = definition
	# Refill the existing slots. Their mesh, bases, hulls and GPU allocation stay put.
	for i in initial.size():
		initial[i].origin = Vector3(scatter_rng.randf_range(-0.90, 0.90), initial[i].origin.y, scatter_rng.randf_range(-1.39, 1.39))
	reset()

const MASK_SIZE := Vector2i(256, 416)
const EDGE_FEATHER := 0.045
const DEBRIS_FADE_SECONDS := 0.6
const DEBRIS_POOL_BUFFER := 64
const LEGACY_DEBRIS_LIFETIME := 3.6
const COVERAGE_EPSILON := 0.000001
const COMPLETION_FRACTION := 1.0
const RUG_HALF := Vector2(1.0, 1.66) # Includes the fringe.
const HEAD_HALF := Vector2(0.305, 0.11)
const RUG_Y := 0.067
const GRAVITY := 9.8
const SLIDE_FRICTION := 3.8
const WET_STAGE_TARGET := 0.99
const WATER_HALF := Vector2(0.19, 0.13)
const SQUEEGEE_HALF := Vector2(0.34, 0.075)
const WATER_RATE := 6.2
const EXTRACTION_RATE := 7.4
const MAX_TOOL_STRENGTH := 16.0
const WATER_BLOB_EDGE_FRACTION := 0.18
const SQUEEGEE_ROTATION_STEP := PI / 12.0
const SQUEEGEE_MAX_ROTATION_STEPS := 12

var batch: MultiMesh
var batch_node: MultiMeshInstance3D
var initial: Array[Transform3D] = []
var positions: Array[Vector3] = []
var velocities: Array[Vector3] = []
var radii: Array[float] = []
var cleared: Array[bool] = []
var cooldown: Array[float] = []
var active: Array[int] = []
var moving: Array[bool] = []
var growth: Array[float] = []
var initial_growth := PackedFloat32Array()
var awakened: Array[bool] = []
var credited: Array[bool] = []
# Physical slots can be reused; their original one-time progress credit cannot.
var recycled: Array[bool] = []
var debris_age: Array[float] = []
var timed_debris: Array[int] = []
var free_slots: Array[int] = []
var floor_debris: Array[int] = []
# Source samples and visual identities can differ when borrowing a free slot.
var source_emitted_pass: Array[int] = []
var pass_serial := 0
var clump_hulls: Array[PackedVector2Array] = []
var footprint := preload("res://scripts/rug_footprint.gd").new()
var rug_node: Node3D
var coverage_values := PackedFloat32Array()
var pass_base := PackedFloat32Array()
var pass_strength := PackedFloat32Array()
var pass_active := false
var pass_direction := Vector2.ZERO
var reversal_distance := 0.0
var reversal_start := Vector2.ZERO
var remaining := 0
var rug_origin := Vector3.ZERO
var mask: Image
var mask_texture: ImageTexture
var mask_changed := false
var last_z_direction := 1.0
var surface_pixels := PackedByteArray()
var surface_pixel_count := 0
var surface_coverage_total := 0.0
var wet_recipe := false
var skip_dry_stage := false
var tool_strength := 1.0
var water_values := PackedFloat32Array()
var extraction_values := PackedFloat32Array()
var water_coverage_total := 0.0
var extraction_coverage_total := 0.0
var wet_mask: Image
var wet_texture: ImageTexture
var wet_mask_changed := false
var _full_water_values := PackedFloat32Array()
var _full_wet_pixels := PackedByteArray()
var _sweep_sides := PackedVector2Array()
var _sweep_headings := PackedVector2Array()
var _sweep_local_starts := PackedVector2Array()
var _sweep_local_finishes := PackedVector2Array()
var _water_pixel_x := PackedFloat32Array()
var _water_pixel_z := PackedFloat32Array()

func _init() -> void:
	# Maximum twelve midpoint sweeps plus thirteen boundary poses. Fixed
	# buffers avoid four growing packed-array allocations for every input event.
	var sweep_capacity := SQUEEGEE_MAX_ROTATION_STEPS * 2 + 1
	_sweep_sides.resize(sweep_capacity)
	_sweep_headings.resize(sweep_capacity)
	_sweep_local_starts.resize(sweep_capacity)
	_sweep_local_finishes.resize(sweep_capacity)
	# Keep the original Vector2/Float32 coordinate rounding, but compute it only
	# once for each row and column instead of for every overlapping hose stamp.
	_water_pixel_x.resize(MASK_SIZE.x)
	_water_pixel_z.resize(MASK_SIZE.y)
	for x in MASK_SIZE.x:
		_water_pixel_x[x] = ((Vector2(x + 0.5, 0.5) / Vector2(MASK_SIZE) - Vector2.ONE * 0.5) * RUG_HALF * 2.0).x
	for y in MASK_SIZE.y:
		_water_pixel_z[y] = ((Vector2(0.5, y + 0.5) / Vector2(MASK_SIZE) - Vector2.ONE * 0.5) * RUG_HALF * 2.0).y

func setup(rug: Node3D) -> void:
	assert(batch == null, "Dirt pool must be set up only once per cleaning scene")
	scatter_rng.randomize()
	rug_node = rug
	rug_origin = rug.global_position
	batch_node = rug.get_node("Dirty/SoilClumps")
	batch = batch_node.multimesh.duplicate()
	batch_node.multimesh = batch
	# Fling trajectories extend well beyond the original static batch bounds.
	batch_node.custom_aabb = AABB(Vector3(-6, -0.1, -6), Vector3(12, 3, 12))
	for i in batch.instance_count:
		var pose := batch.get_instance_transform(i)
		initial.append(pose)
		clump_colors.append(batch.get_instance_color(i) if batch.use_colors else Color.WHITE)
		radii.append(maxf(pose.basis.get_scale().x, pose.basis.get_scale().z) * 1.2)
		var points := PackedVector2Array()
		for vertex in batch.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var p: Vector3 = pose.basis * vertex
			points.append(Vector2(p.x, p.z))
		clump_hulls.append(Geometry2D.convex_hull(points))
	# Choose the visible seeds without periodic indices or a repeating size pattern.
	# Keep the authored scatter stable on Reset so feel comparisons are repeatable.
	initial_growth.resize(initial.size())
	# Unseeded slots stay latent until the brush lifts them out of the dust.
	initial_growth.fill(0.0)
	var candidates := range(initial.size())
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = 8137
	for selected in mini(25, candidates.size()):
		var pick := seed_rng.randi_range(selected, candidates.size() - 1)
		var chosen: int = candidates[pick]
		candidates[pick] = candidates[selected]
		candidates[selected] = chosen
		initial_growth[chosen] = seed_rng.randf_range(0.24, 0.44)
	mask = Image.create(MASK_SIZE.x, MASK_SIZE.y, false, Image.FORMAT_L8)
	mask.fill(Color.WHITE)
	mask_texture = ImageTexture.create_from_image(mask)
	wet_mask = Image.create(MASK_SIZE.x, MASK_SIZE.y, false, Image.FORMAT_L8)
	wet_mask.fill(Color.BLACK)
	wet_texture = ImageTexture.create_from_image(wet_mask)
	# Empty rounded corners and fringe gaps are not dirty carpet surface.
	surface_pixels.resize(MASK_SIZE.x * MASK_SIZE.y)
	_full_water_values.resize(surface_pixels.size())
	_full_wet_pixels.resize(surface_pixels.size())
	for y in MASK_SIZE.y:
		for x in MASK_SIZE.x:
			var point := (Vector2(x + 0.5, y + 0.5) / Vector2(MASK_SIZE) - Vector2.ONE * 0.5) * RUG_HALF * 2.0
			if footprint.contains_point(point):
				var index := y * MASK_SIZE.x + x
				surface_pixels[index] = 1
				_full_water_values[index] = 1.0
				_full_wet_pixels[index] = 255
				surface_pixel_count += 1
	for mesh in rug.get_node("Dirty/CarpetMesh").get_children():
		if not mesh is MeshInstance3D:
			continue
		var clean := mesh.mesh.surface_get_material(0) as StandardMaterial3D
		var material := ShaderMaterial.new()
		material.shader = preload("res://scripts/soil_surface.gdshader")
		material.set_shader_parameter("coverage", mask_texture)
		material.set_shader_parameter("wetness", wet_texture)
		material.set_shader_parameter("wet_recipe", wet_recipe)
		material.set_shader_parameter("soil_map", preload("res://assets/dirt/dry_soil_albedo.png"))
		material.set_shader_parameter("rug_origin", rug_origin)
		material.set_shader_parameter("clean_color", clean.albedo_color)
		if clean.albedo_texture:
			material.set_shader_parameter("clean_map", clean.albedo_texture)
		mesh.material_override = material
		surface_materials.append(material)
	reset()

func set_reveal_progress(value: float) -> void:
	# Only the starter rocks emerge after unrolling. The rug's dirty surface is
	# already visible on arrival; presentation never changes saved cleanliness.
	reveal_progress = clampf(value, 0.0, 1.0)
	request_render()
	if reveal_progress <= 0.0:
		batch.visible_instance_count = 0

func suspend_simulation(value: bool) -> void:
	simulation_suspended = value
	end_pass()
	set_physics_process(not value and ((completion_started and not vacuum_complete) or not active.is_empty() or not timed_debris.is_empty()))

func update_surface_dust() -> void:
	var vacuum_fade := 1.0 - smoothstep(0.15, 1.2, vacuum_elapsed) if completion_started else 1.0
	for material in surface_materials:
		material.set_shader_parameter("dust_strength", rug_definition.dust_strength * vacuum_fade)

func reset() -> void:
	completion_started = false
	vacuum_complete = false
	vacuum_elapsed = 0.0
	vacuum_origins.resize(initial.size())
	vacuum_growth.resize(initial.size())
	update_surface_dust()
	for material in surface_materials:
		material.set_shader_parameter("surface_tint", rug_definition.surface_tint)
	# Keep capacity across jobs instead of rebuilding 560 clumps or their buffers.
	positions.resize(initial.size())
	velocities.resize(initial.size())
	cleared.resize(initial.size())
	cooldown.resize(initial.size())
	active.clear()
	moving.resize(initial.size())
	growth.resize(initial.size())
	awakened.resize(initial.size())
	credited.resize(initial.size())
	recycled.resize(initial.size())
	debris_age.resize(initial.size())
	source_emitted_pass.resize(initial.size())
	timed_debris.clear()
	free_slots.clear()
	floor_debris.clear()
	pass_serial = 0
	for i in initial.size():
		positions[i] = initial[i].origin
		velocities[i] = Vector3.ZERO
		cleared[i] = false
		cooldown[i] = 0.0
		moving[i] = false
		growth[i] = initial_growth[i]
		awakened[i] = false
		credited[i] = false
		recycled[i] = false
		debris_age[i] = -1.0
		source_emitted_pass[i] = -1
		if initial_growth[i] == 0.0:
			free_slots.append(i)
	remaining = initial.size()
	last_z_direction = 1.0
	mask.fill(Color.WHITE)
	mask_texture.update(mask)
	mask_changed = false
	coverage_values.resize(MASK_SIZE.x * MASK_SIZE.y)
	coverage_values.fill(1.0)
	surface_coverage_total = float(surface_pixel_count)
	water_values.resize(coverage_values.size())
	water_values.fill(0.0)
	extraction_values.resize(coverage_values.size())
	extraction_values.fill(0.0)
	water_coverage_total = 0.0
	extraction_coverage_total = 0.0
	wet_mask.fill(Color.BLACK)
	wet_texture.update(wet_mask)
	wet_mask_changed = false
	pass_strength.resize(coverage_values.size())
	pass_active = false
	if skip_dry_stage:
		_clear_dry_stage()
	set_physics_process(false)
	request_render()
	progress_changed.emit(remaining, initial.size())

func begin_pass() -> void:
	pass_serial += 1
	pass_base = coverage_values.duplicate()
	pass_strength.fill(0.0)
	pass_active = true
	pass_direction = Vector2.ZERO
	reversal_distance = 0.0

func end_pass() -> void:
	pass_active = false

func update_clump_transform(_i: int) -> void:
	request_render()

func request_render() -> void:
	render_dirty = true
	set_process(true)

func refresh_visible_clumps() -> void:
	# Compact visible instances; simulation IDs and earned credit stay stable.
	var camera := get_viewport().get_camera_3d()
	var planes: Array[Plane] = []
	if camera != null:
		planes = camera.get_frustum()
	var count := 0
	for i in positions.size():
		if vacuum_complete or growth[i] <= 0.0:
			continue
		# Older saves used near-invisible 2.5% seeds for the dormant slots.
		# Keep those hidden too until a stroke actually awakens them.
		if not awakened[i] and not moving[i] and initial_growth[i] == 0.0 and growth[i] <= 0.025:
			continue
		# Offset each seed's growth slightly so the rug fills in organically.
		var delay := float((i * 37) % 101) / 100.0 * 0.32
		var visible_growth := _visible_debris_growth(i) * smoothstep(delay, delay + 0.68, reveal_progress)
		if visible_growth <= 0.0:
			continue
		var world := batch_node.to_global(positions[i])
		var radius := maxf(radii[i] * visible_growth * 2.0, 0.12)
		var visible := true
		for plane in planes:
			if plane.distance_to(world) > radius:
				visible = false
				break
		if not visible:
			continue
		var pose := initial[i]
		pose.basis = pose.basis.scaled(Vector3.ONE * visible_growth)
		pose.origin = positions[i]
		batch.set_instance_transform(count, pose)
		if batch.use_colors:
			batch.set_instance_color(count, clump_colors[i])
		count += 1
	batch.visible_instance_count = count
	render_dirty = false

func start_vacuum(accepted_contract: bool = false) -> void:
	if completion_started or (remaining != 0 and not accepted_contract):
		return
	completion_started = true
	end_pass()
	vacuum_origins.assign(positions)
	for i in growth.size():
		vacuum_growth[i] = _visible_debris_growth(i)
		growth[i] = vacuum_growth[i]
	timed_debris.clear()
	floor_debris.clear()
	debris_age.fill(-1.0)
	active.clear()
	moving.fill(false)
	velocities.fill(Vector3.ZERO)
	var camera := get_viewport().get_camera_3d()
	var top := camera.project_position(Vector2(get_viewport().get_visible_rect().size.x * 0.5, -100), 7.5)
	vacuum_target = batch_node.to_local(top)
	set_physics_process(not simulation_suspended)
	vacuum_started.emit()

func animate_vacuum(delta: float) -> void:
	vacuum_elapsed += delta
	update_surface_dust()
	for i in positions.size():
		var delay := float(i % 19) / 18.0 * 0.22
		var t := clampf((vacuum_elapsed - delay) / 1.5, 0.0, 1.0)
		var lift := smoothstep(0.0, 0.28, t)
		var pull := pow(smoothstep(0.18, 1.0, t), 1.7)
		var raised := vacuum_origins[i] + Vector3.UP * (0.45 + float(i % 7) * 0.045) * lift
		positions[i] = raised.lerp(vacuum_target, pull)
		# Collect the dirt that was actually visible; untouched seeds must not
		# become full-sized rocks just because the job is finishing.
		growth[i] = vacuum_growth[i] * (1.0 - smoothstep(0.72, 1.0, t))
	request_render()
	if vacuum_elapsed >= VACUUM_SECONDS:
		vacuum_complete = true
		batch.visible_instance_count = 0
		set_physics_process(false)
		vacuum_finished.emit()

func clump_is_outside(i: int) -> bool:
	if recycled[i]:
		return true # A hidden free slot has no physical footprint on the rug.
	var polygon := PackedVector2Array()
	for p in clump_hulls[i]:
		polygon.append(p * growth[i] + Vector2(positions[i].x, positions[i].z))
	return not footprint.overlaps_polygon(polygon)

func brush_surface_height(world_point: Vector3, head_half: Vector2 = HEAD_HALF) -> float:
	var p := rug_node.to_local(world_point)
	var polygon := PackedVector2Array()
	for offset in [Vector2(-head_half.x,-head_half.y),Vector2(head_half.x,-head_half.y),head_half,Vector2(-head_half.x,head_half.y)]:
		polygon.append(Vector2(p.x,p.z) + offset)
	return RUG_Y if footprint.overlaps_polygon(polygon) else 0.0

func squeegee_surface_height(world_point: Vector3, heading: Vector3) -> float:
	var p := rug_node.to_local(world_point)
	var center := Vector2(p.x, p.z)
	var local_heading := _squeegee_local_heading(heading, Vector2(0.0, -1.0))
	var side := Vector2(-local_heading.y, local_heading.x)
	var polygon := PackedVector2Array()
	for offset in [
		Vector2(-SQUEEGEE_HALF.x, -SQUEEGEE_HALF.y),
		Vector2(SQUEEGEE_HALF.x, -SQUEEGEE_HALF.y),
		SQUEEGEE_HALF,
		Vector2(-SQUEEGEE_HALF.x, SQUEEGEE_HALF.y),
	]:
		polygon.append(center + side * offset.x + local_heading * offset.y)
	return RUG_Y if footprint.overlaps_polygon(polygon) else 0.0

func stroke(world_from: Vector3, world_to: Vector3, elapsed: float) -> void:
	if completion_started or simulation_suspended or reveal_progress < 1.0:
		return
	var local_from := rug_node.to_local(world_from)
	var local_to := rug_node.to_local(world_to)
	var start := Vector2(local_from.x, local_from.z)
	var finish := Vector2(local_to.x, local_to.z)
	var travel := finish - start
	if travel.length_squared() < 0.00000001:
		return
	if not pass_active:
		begin_pass()
	var paint_from := start
	if pass_direction == Vector2.ZERO:
		pass_direction = travel.normalized()
	if travel.normalized().dot(pass_direction) < -0.5:
		if reversal_distance == 0.0:
			reversal_start = start
		reversal_distance += travel.length()
		if reversal_distance >= maxf(0.22, head_half.y * 2.0):
			paint_from = reversal_start
			begin_pass()
			pass_direction = travel.normalized()
	else:
		reversal_distance = 0.0
	if absf(travel.y) > 0.00005:
		last_z_direction = signf(travel.y)
	# A rake throws forwards/backwards; sideways strokes add a bounded fan.
	var direction := Vector2(clampf(travel.normalized().x * 0.38, -0.38, 0.38), last_z_direction).normalized()
	var speed := clampf(travel.length() / maxf(elapsed, 0.016), 0.0, 10.0)
	var impulse := clampf(1.9 + speed * 0.36, 2.0, 5.0) * sqrt(tool_strength)
	paint_stroke(paint_from, finish)
	for i in positions.size():
		# "Cleared" tracks progress, not whether a clump can still be brushed.
		if recycled[i] or cooldown[i] > 0.0 or positions[i].y > RUG_Y + 0.14:
			continue
		var point := Vector2(positions[i].x, positions[i].z)
		if not swept_head_hits(start, finish, point, head_half + Vector2.ONE * radii[i] * growth[i]):
			continue
		if not awakened[i] and not moving[i]:
			# Original dirt is all available immediately, including a legacy
			# source whose surface was already cleaned before physical contact.
			source_emitted_pass[i] = pass_serial
			free_slots.erase(i)
		_cancel_debris_timer(i)
		var fan := sin(float(i) * 7.13) * 0.09
		_launch_debris(i, positions[i], Vector3((direction.x + fan) * impulse, 0.45 + impulse * 0.10, direction.y * impulse))
	# Original scatter points sample fresh extraction, but any available visual
	# may serve that demand. Repeated work in one stripe can use the entire pool.
	for source in initial.size():
		if source_emitted_pass[source] == pass_serial:
			continue
		var point := Vector2(initial[source].origin.x, initial[source].origin.z)
		if not swept_head_hits(start, finish, point, head_half):
			continue
		var pixel := _source_pixel(source)
		if pass_base[pixel] - coverage_values[pixel] <= COVERAGE_EPSILON:
			continue
		var fan := sin(float(source) * 7.13) * 0.09
		var launch := Vector3((direction.x + fan) * impulse, 0.45 + impulse * 0.10, direction.y * impulse)
		if _emit_from_pool(source, launch):
			source_emitted_pass[source] = pass_serial
	set_physics_process(not active.is_empty() or not timed_debris.is_empty())

func _source_pixel(i: int) -> int:
	var source := Vector2(initial[i].origin.x, initial[i].origin.z)
	var pixel := Vector2i(((source + RUG_HALF) / (RUG_HALF * 2.0) * Vector2(MASK_SIZE)).floor())
	pixel = pixel.clamp(Vector2i.ZERO, MASK_SIZE - Vector2i.ONE)
	return pixel.y * MASK_SIZE.x + pixel.x

func _source_dust(i: int) -> float:
	return coverage_values[_source_pixel(i)]

func _launch_debris(i: int, origin: Vector3, velocity: Vector3) -> void:
	positions[i] = origin
	velocities[i] = velocity
	# Contact and extraction share one input event. No invisible growth period
	# may leave a newly pulled clump behind a brush that has already moved on.
	growth[i] = 1.0
	cleared[i] = false
	recycled[i] = false
	cooldown[i] = 0.14
	awakened[i] = true
	if not moving[i]:
		active.append(i)
		moving[i] = true
	request_render()

func _emit_from_pool(source: int, velocity: Vector3) -> bool:
	# Demand, never elapsed time, starts reclamation. The reserve covers the
	# shrink animation while currently free slots supply immediate feedback.
	_request_pool_space()
	if free_slots.is_empty():
		# Never queue a birth at a historical brush position. Returned slots
		# are available to subsequent contact, not to a delayed replay.
		return false
	var i: int = source if free_slots.has(source) else free_slots.back()
	free_slots.erase(i)
	_launch_debris(i, initial[source].origin, velocity)
	_request_pool_space()
	return true

func _request_pool_space() -> void:
	var needed := DEBRIS_POOL_BUFFER - free_slots.size() - timed_debris.size()
	while needed > 0 and not floor_debris.is_empty():
		var i: int = floor_debris.pop_front()
		if moving[i] or not credited[i] or not cleared[i] or recycled[i] or debris_age[i] >= 0.0 or growth[i] <= 0.0 or not clump_is_outside(i):
			continue
		debris_age[i] = 0.0
		timed_debris.append(i)
		needed -= 1
	if not timed_debris.is_empty():
		set_physics_process(not simulation_suspended)

func _visible_debris_growth(i: int) -> float:
	var fade := smoothstep(0.0, DEBRIS_FADE_SECONDS, debris_age[i]) if debris_age[i] >= 0.0 else 0.0
	return growth[i] * (1.0 - fade)

func _cancel_debris_timer(i: int) -> void:
	floor_debris.erase(i)
	if debris_age[i] < 0.0:
		return
	debris_age[i] = -1.0
	timed_debris.erase(i)
	request_render()

func _age_debris(delta: float) -> void:
	for slot in range(timed_debris.size() - 1, -1, -1):
		var i := timed_debris[slot]
		debris_age[i] += delta
		request_render()
		if debris_age[i] < DEBRIS_FADE_SECONDS:
			continue
		# Return the same shape and permanent progress ID to global supply.
		# Its next emission can serve fresh cleaning at any source on the rug.
		positions[i] = initial[i].origin
		velocities[i] = Vector3.ZERO
		growth[i] = 0.0
		awakened[i] = false
		moving[i] = false
		cleared[i] = true
		cooldown[i] = 0.0
		recycled[i] = true
		debris_age[i] = -1.0
		active.erase(i)
		timed_debris.remove_at(slot)
		free_slots.append(i)

static func swept_head_hits(start: Vector2, finish: Vector2, point: Vector2, half: Vector2) -> bool:
	# Segment versus expanded rectangle: fast swipes cannot tunnel between events.
	var delta := finish - start
	var near_t := 0.0
	var far_t := 1.0
	for axis in 2:
		var low := point[axis] - half[axis]
		var high := point[axis] + half[axis]
		if absf(delta[axis]) < 0.00001:
			if start[axis] < low or start[axis] > high:
				return false
		else:
			var a := (low - start[axis]) / delta[axis]
			var b := (high - start[axis]) / delta[axis]
			near_t = maxf(near_t, minf(a, b))
			far_t = minf(far_t, maxf(a, b))
			if near_t > far_t:
				return false
	return true

func paint_stroke(start: Vector2, finish: Vector2) -> void:
	var efficiency: float = rug_definition.stroke_efficiency(finish - start)
	var soft_half := head_half + Vector2.ONE * EDGE_FEATHER
	var low := (start.min(finish) - soft_half + RUG_HALF) / (RUG_HALF * 2.0)
	var high := (start.max(finish) + soft_half + RUG_HALF) / (RUG_HALF * 2.0)
	var from_pixel := Vector2i((low * Vector2(MASK_SIZE)).floor()).clamp(Vector2i.ZERO, MASK_SIZE)
	var to_pixel := Vector2i((high * Vector2(MASK_SIZE)).ceil()).clamp(Vector2i.ZERO, MASK_SIZE)
	for y in range(from_pixel.y, to_pixel.y):
		for x in range(from_pixel.x, to_pixel.x):
			var point := (Vector2(x + 0.5, y + 0.5) / Vector2(MASK_SIZE) - Vector2.ONE * 0.5) * RUG_HALF * 2.0
			var index := y * MASK_SIZE.x + x
			if coverage_values[index] <= 0.0:
				continue
			var closest := Geometry2D.get_closest_point_to_segment(point, start, finish)
			var q := (point - closest).abs() - head_half
			var distance := q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0)
			var weight := (1.0 - smoothstep(-EDGE_FEATHER, EDGE_FEATHER, distance)) * efficiency
			if weight > pass_strength[index]:
				pass_strength[index] = weight
				var old_value := coverage_values[index]
				coverage_values[index] = maxf(0.0, pass_base[index] - rug_definition.removal_per_pass * weight * tool_strength)
				if coverage_values[index] <= COVERAGE_EPSILON:
					coverage_values[index] = 0.0
				var value := coverage_values[index]
				if surface_pixels[index] == 1:
					surface_coverage_total += value - old_value
				mask.set_pixel(x, y, Color(value, value, value))
				mask_changed = true
	set_process(mask_changed or render_dirty)

func _process(_delta: float) -> void:
	if render_dirty:
		refresh_visible_clumps()
	var changed_surface := mask_changed or wet_mask_changed
	if mask_changed:
		mask_texture.update(mask)
		mask_changed = false
	if wet_mask_changed:
		wet_texture.update(wet_mask)
		wet_mask_changed = false
	if changed_surface:
		surface_changed.emit()
	set_process(false)

func is_fully_outside(point: Vector3, radius: float) -> bool:
	return footprint.circle_is_outside(Vector2(point.x, point.z), radius)

func _physics_process(delta: float) -> void:
	if simulation_suspended:
		return
	if completion_started:
		if not vacuum_complete:
			animate_vacuum(delta)
		return
	# Only already-requested fades advance; settled dirt otherwise stays put.
	_age_debris(delta)
	var changed := false
	for slot in range(active.size() - 1, -1, -1):
		var i := active[slot]
		cooldown[i] = maxf(0.0, cooldown[i] - delta)
		if growth[i] < 1.0:
			# Legacy saves may contain a launch mid-growth. Resume its motion
			# immediately, just like a new contact, instead of waiting in place.
			growth[i] = 1.0
		velocities[i].y -= GRAVITY * delta
		positions[i] += velocities[i] * delta
		var outside := clump_is_outside(i)
		# Physical location is reversible; earned cleanliness is permanent.
		if not outside:
			cleared[i] = false
			_cancel_debris_timer(i)
		var surface := 0.0 if outside else RUG_Y
		if positions[i].y <= surface:
			positions[i].y = surface
			velocities[i].y = 0.0
			var friction := 12.0 if outside else SLIDE_FRICTION
			var horizontal := Vector2(velocities[i].x, velocities[i].z).move_toward(Vector2.ZERO, friction * delta)
			velocities[i].x = horizontal.x
			velocities[i].z = horizontal.y
			if outside and not cleared[i]:
				cleared[i] = true
				if not credited[i]:
					credited[i] = true
					remaining -= 1
					changed = true
		update_clump_transform(i)
		if velocities[i].length_squared() < 0.0001 and cooldown[i] <= 0.0:
			moving[i] = false
			active.remove_at(slot)
			if outside and credited[i] and debris_age[i] < 0.0 and not floor_debris.has(i):
				floor_debris.append(i)
	if changed:
		progress_changed.emit(remaining, initial.size())
	if remaining == 0 and automatic_completion_enabled:
		start_vacuum()
	elif active.is_empty() and timed_debris.is_empty():
		set_physics_process(false)

func unique_clearance() -> float:
	return clampf(1.0 - float(remaining) / maxf(initial.size(), 1), 0.0, 1.0)

func surface_clearance() -> float:
	return clampf(1.0 - surface_coverage_total / maxf(surface_pixel_count, 1), 0.0, 1.0)

func set_recipe(value: bool, skip_dry: bool = false) -> void:
	var next_skip_dry := value and skip_dry
	if wet_recipe == value and skip_dry_stage == next_skip_dry:
		_update_wet_materials()
		return
	var wet_changed := wet_recipe != value
	wet_recipe = value
	skip_dry_stage = next_skip_dry
	if wet_changed and not water_values.is_empty():
		water_values.fill(0.0)
		extraction_values.fill(0.0)
		water_coverage_total = 0.0
		extraction_coverage_total = 0.0
		wet_mask.fill(Color.BLACK)
		wet_mask_changed = true
		set_process(true)
	if skip_dry_stage and not coverage_values.is_empty():
		_clear_dry_stage()
		progress_changed.emit(remaining, initial.size())
	_update_wet_materials()


func _clear_dry_stage() -> void:
	# Water-only recipes still share the production dirt masks so saves and
	# shaders stay compatible, but their no-longer-required dry work is complete.
	# Wet/extraction arrays are intentionally untouched during save migration.
	active.clear()
	timed_debris.clear()
	free_slots.clear()
	floor_debris.clear()
	debris_age.fill(-1.0)
	recycled.fill(false)
	for i in initial.size():
		velocities[i] = Vector3.ZERO
		cleared[i] = true
		credited[i] = true
		moving[i] = false
		growth[i] = 0.0
		awakened[i] = false
	remaining = 0
	coverage_values.fill(0.0)
	surface_coverage_total = 0.0
	mask.fill(Color.BLACK)
	mask_changed = true
	pass_strength.fill(0.0)
	pass_active = false
	set_physics_process(false)
	request_render()


func prepare_water_stage() -> void:
	# Gym Rug 2 starts at the water lesson. Reuse the production masks and stage
	# logic, but begin after dry cleaning without simulating hundreds of strokes.
	if not wet_recipe:
		return
	completion_started = false
	vacuum_complete = false
	_clear_dry_stage()
	water_values.fill(0.0)
	extraction_values.fill(0.0)
	water_coverage_total = 0.0
	extraction_coverage_total = 0.0
	wet_mask.fill(Color.BLACK)
	wet_mask_changed = true
	pass_strength.fill(0.0)
	pass_active = false
	set_physics_process(false)
	request_render()
	progress_changed.emit(remaining, initial.size())

func prepare_extraction_stage() -> void:
	# Gym's instant-wet shortcut uses the same valid carpet pixels as a full
	# water blob, without testing distances and writing 106,496 pixels on tap.
	# These fixed buffers are built with the footprint during setup, not on use.
	if not wet_recipe or _full_water_values.is_empty():
		return
	completion_started = false
	vacuum_complete = false
	_clear_dry_stage()
	water_values = _full_water_values.duplicate()
	extraction_values.fill(0.0)
	water_coverage_total = float(surface_pixel_count)
	extraction_coverage_total = 0.0
	wet_mask.set_data(MASK_SIZE.x, MASK_SIZE.y, false, Image.FORMAT_L8, _full_wet_pixels)
	wet_mask_changed = true
	set_physics_process(false)
	request_render()
	progress_changed.emit(remaining, initial.size())

func set_tool_strength(multiplier: float) -> void:
	# Three wet stores now reach 9.261x. Retain a finite ceiling with enough room
	# for later tuning instead of silently weakening an earned capstone tier.
	tool_strength = clampf(multiplier if is_finite(multiplier) else 1.0, 0.25, MAX_TOOL_STRENGTH)

func water_clearance() -> float:
	if not wet_recipe:
		return 1.0
	return clampf(water_coverage_total / maxf(surface_pixel_count, 1), 0.0, 1.0)

func extraction_clearance() -> float:
	if not wet_recipe:
		return 1.0
	return clampf(extraction_coverage_total / maxf(surface_pixel_count, 1), 0.0, 1.0)

func overall_clearance() -> float:
	var dry := minf(unique_clearance(), surface_clearance())
	if not wet_recipe:
		return dry
	if skip_dry_stage:
		return clampf((water_clearance() + extraction_clearance()) / 2.0, 0.0, 1.0)
	# Each required action owns one third of the visible progress. Stage gates
	# below preserve the order while still rewarding the player's first stroke.
	return clampf((dry + water_clearance() + extraction_clearance()) / 3.0, 0.0, 1.0)

func make_progress_snapshot() -> Dictionary:
	return {
		"unique_clearance": unique_clearance(),
		"surface_clearance": surface_clearance(),
		"overall_clearance": overall_clearance(),
		"wet_recipe": wet_recipe,
		"skip_dry_stage": skip_dry_stage,
		"water_clearance": water_clearance(),
		"extraction_clearance": extraction_clearance(),
	}

func recommended_tool() -> int:
	if not wet_recipe:
		return 0
	if not skip_dry_stage and minf(unique_clearance(), surface_clearance()) < WET_STAGE_TARGET:
		return 0
	if not water_stage_complete():
		return 2
	return 1

func water_stage_complete() -> bool:
	return wet_recipe and water_clearance() >= WET_STAGE_TARGET

func water_stage_progress() -> float:
	return clampf(water_clearance() / WET_STAGE_TARGET, 0.0, 1.0) if wet_recipe else 1.0

func extraction_stage_complete() -> bool:
	return wet_recipe and extraction_clearance() >= WET_STAGE_TARGET

func extraction_stage_progress() -> float:
	return clampf(extraction_clearance() / WET_STAGE_TARGET, 0.0, 1.0) if wet_recipe else 1.0

func apply_water_blob(world_center: Vector3, radius: float, strength: float = 1.0, edge_fraction: float = WATER_BLOB_EDGE_FRACTION) -> bool:
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
	if amount <= 0.0:
		return false
	# Direct impact keeps its readable core; capillary soaking uses a wide soft
	# feather in the same authoritative mask, not an extra transparent overlay.
	var inner_radius := radius * (1.0 - clampf(edge_fraction, 0.01, 1.0))
	var any_changed := false
	var radius_squared := radius * radius
	for y in range(from_pixel.y, to_pixel.y):
		var row := y * MASK_SIZE.x
		var point_z := _water_pixel_z[y]
		# The original bounding square includes empty circle corners. A one-pixel
		# guard keeps these row bounds conservative despite Float32 coordinates;
		# the original distance test below still decides every affected pixel.
		var dz := point_z - center.y
		var row_radius := sqrt(maxf(0.0, radius_squared - dz * dz))
		var row_from := maxi(from_pixel.x, floori((center.x - row_radius + RUG_HALF.x) / (RUG_HALF.x * 2.0) * MASK_SIZE.x) - 1)
		var row_to := mini(to_pixel.x, ceili((center.x + row_radius + RUG_HALF.x) / (RUG_HALF.x * 2.0) * MASK_SIZE.x) + 1)
		for x in range(row_from, row_to):
			var index := row + x
			if surface_pixels[index] == 0:
				continue
			var loosened := 1.0 - coverage_values[index]
			var old_water := water_values[index]
			if old_water >= loosened:
				continue
			var point := Vector2(_water_pixel_x[x], point_z)
			var distance := point.distance_to(center)
			if distance >= radius:
				continue
			var weight := 1.0 if distance <= inner_radius else 1.0 - smoothstep(inner_radius, radius, distance)
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

func apply_water_stroke(world_from: Vector3, world_to: Vector3, elapsed: float) -> void:
	if not wet_recipe or (not skip_dry_stage and minf(unique_clearance(), surface_clearance()) < WET_STAGE_TARGET):
		return
	_paint_wet_stroke(world_from, world_to, elapsed, WATER_HALF, true)

func apply_squeegee_stroke(
	world_from: Vector3,
	world_to: Vector3,
	elapsed: float,
	heading: Vector3 = Vector3.FORWARD,
	previous_heading: Vector3 = Vector3.ZERO
) -> void:
	if not water_stage_complete():
		return
	# The optional arguments keep every existing caller bit-for-bit on the old
	# local X/Z footprint. New callers provide the blade's world-space heading.
	if heading == Vector3.FORWARD and previous_heading == Vector3.ZERO:
		_paint_wet_stroke(world_from, world_to, elapsed, SQUEEGEE_HALF, false)
		return
	_paint_rotated_squeegee_stroke(world_from, world_to, elapsed, heading, previous_heading)

func _squeegee_local_heading(world_heading: Vector3, fallback: Vector2) -> Vector2:
	if not is_finite(world_heading.x) or not is_finite(world_heading.y) or not is_finite(world_heading.z):
		return fallback
	var local_heading := rug_node.global_transform.basis.inverse() * world_heading
	var flat := Vector2(local_heading.x, local_heading.z)
	if not is_finite(flat.x) or not is_finite(flat.y) or flat.length_squared() < 0.00000001:
		return fallback
	return flat.normalized()

static func _projected_swept_box_distance(
	point: Vector2,
	side: Vector2,
	heading: Vector2,
	local_start: Vector2,
	local_finish: Vector2,
	half: Vector2
) -> float:
	var local_point := Vector2(point.dot(side), point.dot(heading))
	var closest := Geometry2D.get_closest_point_to_segment(local_point, local_start, local_finish)
	var q := (local_point - closest).abs() - half
	return q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0)

func _paint_rotated_squeegee_stroke(
	world_from: Vector3,
	world_to: Vector3,
	elapsed: float,
	heading: Vector3,
	previous_heading: Vector3
) -> void:
	if completion_started or simulation_suspended or reveal_progress < 1.0:
		return
	var a3 := rug_node.to_local(world_from)
	var b3 := rug_node.to_local(world_to)
	var start := Vector2(a3.x, a3.z)
	var finish := Vector2(b3.x, b3.z)
	if start.distance_squared_to(finish) < 0.00000001:
		return
	var current_direction := _squeegee_local_heading(heading, Vector2(0.0, -1.0))
	var old_direction := current_direction
	if previous_heading.length_squared() >= 0.00000001:
		old_direction = _squeegee_local_heading(previous_heading, current_direction)
	var old_angle := old_direction.angle()
	var angle_delta := wrapf(current_direction.angle() - old_angle, -PI, PI)
	var rotation_steps := clampi(ceili(absf(angle_delta) / SQUEEGEE_ROTATION_STEP), 1, SQUEEGEE_MAX_ROTATION_STEPS)
	# Each entry is one fixed-orientation rectangle swept between two centers.
	# All basis vectors and segment projections are prepared once here instead
	# of being recomputed for every candidate pixel.
	var sweep_count := 0
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
		_sweep_sides[sweep_count] = sweep_side
		_sweep_headings[sweep_count] = sweep_heading
		_sweep_local_starts[sweep_count] = Vector2(center_a.dot(sweep_side), center_a.dot(sweep_heading))
		_sweep_local_finishes[sweep_count] = Vector2(center_b.dot(sweep_side), center_b.dot(sweep_heading))
		sweep_count += 1
		var extent := sweep_side.abs() * SQUEEGEE_HALF.x + sweep_heading.abs() * SQUEEGEE_HALF.y + Vector2.ONE * EDGE_FEATHER
		bounds_low = bounds_low.min(center_a.min(center_b) - extent)
		bounds_high = bounds_high.max(center_a.max(center_b) + extent)
	# During a turn, boundary poses fill the small angular wedges between the
	# midpoint sweeps. With a steady heading, the single segment above is exact.
	if turning:
		for sample in range(rotation_steps + 1):
			var t := float(sample) / float(rotation_steps)
			var center := start.lerp(finish, t)
			var pose_heading := Vector2.from_angle(old_angle + angle_delta * t)
			var pose_side := Vector2(-pose_heading.y, pose_heading.x)
			var local_center := Vector2(center.dot(pose_side), center.dot(pose_heading))
			_sweep_sides[sweep_count] = pose_side
			_sweep_headings[sweep_count] = pose_heading
			_sweep_local_starts[sweep_count] = local_center
			_sweep_local_finishes[sweep_count] = local_center
			sweep_count += 1
			var extent := pose_side.abs() * SQUEEGEE_HALF.x + pose_heading.abs() * SQUEEGEE_HALF.y + Vector2.ONE * EDGE_FEATHER
			bounds_low = bounds_low.min(center - extent)
			bounds_high = bounds_high.max(center + extent)
	var low := (bounds_low + RUG_HALF) / (RUG_HALF * 2.0)
	var high := (bounds_high + RUG_HALF) / (RUG_HALF * 2.0)
	var from_pixel := Vector2i((low * Vector2(MASK_SIZE)).floor()).clamp(Vector2i.ZERO, MASK_SIZE)
	var to_pixel := Vector2i((high * Vector2(MASK_SIZE)).ceil()).clamp(Vector2i.ZERO, MASK_SIZE)
	var seconds := clampf(elapsed if elapsed > 0.0 else 1.0 / 60.0, 1.0 / 240.0, 0.08)
	var amount := seconds * EXTRACTION_RATE * tool_strength
	var any_changed := false
	for y in range(from_pixel.y, to_pixel.y):
		for x in range(from_pixel.x, to_pixel.x):
			var index := y * MASK_SIZE.x + x
			if surface_pixels[index] == 0 or extraction_values[index] >= water_values[index]:
				continue
			var point := (Vector2(x + 0.5, y + 0.5) / Vector2(MASK_SIZE) - Vector2.ONE * 0.5) * RUG_HALF * 2.0
			var distance := INF
			# Apply only once after finding the union's strongest coverage. This
			# prevents a multi-sample turn from multiplying extraction strength.
			for sweep in sweep_count:
				var local_point := Vector2(point.dot(_sweep_sides[sweep]), point.dot(_sweep_headings[sweep]))
				var closest := Geometry2D.get_closest_point_to_segment(local_point, _sweep_local_starts[sweep], _sweep_local_finishes[sweep])
				var q := (local_point - closest).abs() - SQUEEGEE_HALF
				distance = minf(distance, q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0))
				# All smaller distances produce exactly weight=1. Stop evaluating
				# the union once this pixel has full coverage, not an approximation.
				if distance <= -EDGE_FEATHER:
					break
			var weight := 1.0 - smoothstep(-EDGE_FEATHER, EDGE_FEATHER, distance)
			if _apply_wet_pixel(index, x, y, amount, weight, false):
				any_changed = true
	if any_changed:
		wet_mask_changed = true
		set_process(true)

func _paint_wet_stroke(world_from: Vector3, world_to: Vector3, elapsed: float, half: Vector2, applying_water: bool) -> void:
	if completion_started or simulation_suspended or reveal_progress < 1.0:
		return
	var a3 := rug_node.to_local(world_from)
	var b3 := rug_node.to_local(world_to)
	var start := Vector2(a3.x, a3.z)
	var finish := Vector2(b3.x, b3.z)
	if start.distance_squared_to(finish) < 0.00000001:
		return
	var soft_half := half + Vector2.ONE * EDGE_FEATHER
	var low := (start.min(finish) - soft_half + RUG_HALF) / (RUG_HALF * 2.0)
	var high := (start.max(finish) + soft_half + RUG_HALF) / (RUG_HALF * 2.0)
	var from_pixel := Vector2i((low * Vector2(MASK_SIZE)).floor()).clamp(Vector2i.ZERO, MASK_SIZE)
	var to_pixel := Vector2i((high * Vector2(MASK_SIZE)).ceil()).clamp(Vector2i.ZERO, MASK_SIZE)
	var seconds := clampf(elapsed if elapsed > 0.0 else 1.0 / 60.0, 1.0 / 240.0, 0.08)
	var rate := WATER_RATE if applying_water else EXTRACTION_RATE
	var amount := seconds * rate * tool_strength
	var any_changed := false
	for y in range(from_pixel.y, to_pixel.y):
		for x in range(from_pixel.x, to_pixel.x):
			var index := y * MASK_SIZE.x + x
			if surface_pixels[index] == 0:
				continue
			var point := (Vector2(x + 0.5, y + 0.5) / Vector2(MASK_SIZE) - Vector2.ONE * 0.5) * RUG_HALF * 2.0
			var closest := Geometry2D.get_closest_point_to_segment(point, start, finish)
			var q := (point - closest).abs() - half
			var distance := q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0)
			var weight := 1.0 - smoothstep(-EDGE_FEATHER, EDGE_FEATHER, distance)
			if _apply_wet_pixel(index, x, y, amount, weight, applying_water):
				any_changed = true
	if any_changed:
		wet_mask_changed = true
		set_process(true)

func _apply_wet_pixel(index: int, x: int, y: int, amount: float, weight: float, applying_water: bool) -> bool:
	if weight <= 0.0:
		return false
	var loosened := 1.0 - coverage_values[index]
	if applying_water:
		var old_water := water_values[index]
		var new_water := minf(loosened, old_water + amount * weight)
		if new_water <= old_water:
			return false
		water_values[index] = new_water
		water_coverage_total += new_water - old_water
	else:
		var old_extracted := extraction_values[index]
		var new_extracted := minf(water_values[index], old_extracted + amount * weight)
		if new_extracted <= old_extracted:
			return false
		extraction_values[index] = new_extracted
		extraction_coverage_total += new_extracted - old_extracted
	var visible_water := clampf(water_values[index] - extraction_values[index], 0.0, 1.0)
	wet_mask.set_pixel(x, y, Color(visible_water, visible_water, visible_water))
	return true

func _update_wet_materials() -> void:
	for material in surface_materials:
		material.set_shader_parameter("wet_recipe", wet_recipe)

func make_snapshot() -> Dictionary:
	var saved_positions: Array = []
	var saved_velocities: Array = []
	var spawn_positions: Array = []
	for i in positions.size():
		saved_positions.append([positions[i].x, positions[i].y, positions[i].z])
		saved_velocities.append([velocities[i].x, velocities[i].y, velocities[i].z])
		spawn_positions.append([initial[i].origin.x, initial[i].origin.y, initial[i].origin.z])
	var pixels := PackedByteArray()
	pixels.resize(coverage_values.size())
	for i in coverage_values.size():
		pixels[i] = clampi(roundi(coverage_values[i] * 255.0), 0, 255)
	var result: Dictionary = {
		"version": 1, "positions": saved_positions, "velocities": saved_velocities,
		"spawn_positions": spawn_positions,
		"growth": growth.duplicate(), "awakened": awakened.duplicate(),
		"credited": credited.duplicate(), "cleared": cleared.duplicate(),
		"cooldown": cooldown.duplicate(), "moving": moving.duplicate(),
		"recycled": recycled.duplicate(), "debris_age": debris_age.duplicate(),
		"debris_policy": 2, "floor_debris": floor_debris.duplicate(),
		# Keep the old save shape, but births now require current brush contact.
		"pending_emissions": [],
		"coverage": Marshalls.raw_to_base64(pixels),
		"wet_recipe": wet_recipe,
		"skip_dry_stage": skip_dry_stage,
		"unique_clearance": unique_clearance(), "surface_clearance": surface_clearance(),
		"water_clearance": water_clearance(), "extraction_clearance": extraction_clearance(),
		"overall_clearance": overall_clearance(),
	}
	if wet_recipe:
		var water_pixels := PackedByteArray()
		water_pixels.resize(water_values.size())
		var extraction_pixels := PackedByteArray()
		extraction_pixels.resize(extraction_values.size())
		for i in water_values.size():
			water_pixels[i] = clampi(roundi(water_values[i] * 255.0), 0, 255)
			extraction_pixels[i] = clampi(roundi(extraction_values[i] * 255.0), 0, 255)
		result["water"] = Marshalls.raw_to_base64(water_pixels)
		result["extracted"] = Marshalls.raw_to_base64(extraction_pixels)
	return result

func restore_snapshot(snapshot: Dictionary) -> bool:
	if int(snapshot.get("version", 0)) != 1:
		return false
	for key in ["positions", "velocities", "growth", "awakened", "credited", "cleared", "cooldown", "moving"]:
		if not snapshot.get(key) is Array or snapshot[key].size() != initial.size():
			return false
	var pixels := Marshalls.base64_to_raw(str(snapshot.get("coverage", "")))
	if pixels.size() != coverage_values.size():
		return false
	var has_water := snapshot.has("water") or snapshot.has("extracted")
	var water_pixels := PackedByteArray()
	var extraction_pixels := PackedByteArray()
	if has_water:
		if not snapshot.has("water") or not snapshot.has("extracted"):
			return false
		water_pixels = Marshalls.base64_to_raw(str(snapshot.get("water", "")))
		extraction_pixels = Marshalls.base64_to_raw(str(snapshot.get("extracted", "")))
		if water_pixels.size() != coverage_values.size() or extraction_pixels.size() != coverage_values.size():
			return false
		for i in water_pixels.size():
			if extraction_pixels[i] > water_pixels[i]:
				return false
	if snapshot.has("wet_recipe") and not snapshot.wet_recipe is bool:
		return false
	if snapshot.has("skip_dry_stage") and not snapshot.skip_dry_stage is bool:
		return false
	# Older saves omit the scatter baseline; their live positions still restore.
	var vector_keys := ["positions", "velocities"]
	if snapshot.has("spawn_positions"):
		if not snapshot.spawn_positions is Array or snapshot.spawn_positions.size() != initial.size():
			return false
		vector_keys.append("spawn_positions")
	for key in vector_keys:
		for value in snapshot[key]:
			if not value is Array or value.size() != 3:
				return false
			for component in value:
				if not (component is float or component is int) or not is_finite(float(component)) or absf(float(component)) > 100.0:
					return false
	for key in ["growth", "cooldown"]:
		for value in snapshot[key]:
			if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.0:
				return false
	for key in ["awakened", "credited", "cleared", "moving"]:
		for value in snapshot[key]:
			if not value is bool:
				return false
	# Additive version-1 fields preserve older rug saves. Validate every new
	# value before mutating live progress, including impossible free-slot states.
	var has_lifecycle := snapshot.has("recycled") or snapshot.has("debris_age")
	var demand_policy := snapshot.has("debris_policy")
	if demand_policy and (not snapshot.debris_policy is int and not snapshot.debris_policy is float):
		return false
	if demand_policy and (float(snapshot.debris_policy) != 2.0 or not has_lifecycle):
		return false
	if has_lifecycle:
		for key in ["recycled", "debris_age"]:
			if not snapshot.get(key) is Array or snapshot[key].size() != initial.size():
				return false
		for i in initial.size():
			if not snapshot.recycled[i] is bool:
				return false
			var age: Variant = snapshot.debris_age[i]
			var age_limit := DEBRIS_FADE_SECONDS if demand_policy else LEGACY_DEBRIS_LIFETIME
			if not (age is float or age is int) or not is_finite(float(age)) or (float(age) < 0.0 and float(age) != -1.0) or float(age) > age_limit:
				return false
			if float(age) >= 0.0 and (snapshot.recycled[i] or not snapshot.credited[i] or not snapshot.cleared[i]):
				return false
			if demand_policy and float(age) >= 0.0 and (snapshot.moving[i] or float(snapshot.growth[i]) <= 0.0):
				return false
			if snapshot.recycled[i] and (not snapshot.credited[i] or not snapshot.cleared[i] or snapshot.awakened[i] or snapshot.moving[i] or float(snapshot.growth[i]) != 0.0):
				return false
	if demand_policy:
		if not snapshot.get("floor_debris") is Array or snapshot.floor_debris.size() > initial.size() or not snapshot.get("pending_emissions") is Array or snapshot.pending_emissions.size() > DEBRIS_POOL_BUFFER:
			return false
		var seen: Dictionary = {}
		for value in snapshot.floor_debris:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)) or float(value) < 0 or float(value) >= initial.size():
				return false
			var i := int(value)
			if seen.has(i) or not snapshot.credited[i] or not snapshot.cleared[i] or snapshot.moving[i] or snapshot.recycled[i] or float(snapshot.debris_age[i]) >= 0.0 or float(snapshot.growth[i]) <= 0.0:
				return false
			seen[i] = true
		for request in snapshot.pending_emissions:
			if not request is Dictionary or not (request.get("source") is int or request.get("source") is float):
				return false
			var source := float(request.source)
			if not is_finite(source) or source != floorf(source) or source < 0 or source >= initial.size() or not request.get("velocity") is Array or request.velocity.size() != 3:
				return false
			for component in request.velocity:
				if not (component is float or component is int) or not is_finite(float(component)) or absf(float(component)) > 100.0:
					return false
	active.clear()
	timed_debris.clear()
	free_slots.clear()
	floor_debris.clear()
	pass_serial = 0
	source_emitted_pass.fill(-1)
	remaining = initial.size()
	for i in initial.size():
		var p: Array = snapshot.positions[i]
		var v: Array = snapshot.velocities[i]
		if snapshot.has("spawn_positions"):
			var spawn: Array = snapshot.spawn_positions[i]
			initial[i].origin = Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2]))
		positions[i] = Vector3(float(p[0]), float(p[1]), float(p[2]))
		if not snapshot.has("spawn_positions") and not snapshot.awakened[i] and not snapshot.moving[i] and not snapshot.credited[i]:
			# Old dormant sources never left their original spot. Recover that
			# spot before dust-band checks use the newly randomized scatter.
			initial[i].origin = positions[i]
		velocities[i] = Vector3(float(v[0]), float(v[1]), float(v[2]))
		growth[i] = float(snapshot.growth[i])
		awakened[i] = snapshot.awakened[i]
		credited[i] = snapshot.credited[i]
		cleared[i] = snapshot.cleared[i]
		cooldown[i] = float(snapshot.cooldown[i])
		moving[i] = snapshot.moving[i]
		recycled[i] = snapshot.recycled[i] if has_lifecycle else false
		# Old elapsed-time ages become retained debris. New saves resume only
		# the fades that a real extraction request has already started.
		debris_age[i] = float(snapshot.debris_age[i]) if demand_policy else -1.0
		if debris_age[i] >= 0.0:
			timed_debris.append(i)
		if recycled[i] or (not awakened[i] and not moving[i] and not credited[i] and initial_growth[i] == 0.0 and growth[i] <= 0.025):
			free_slots.append(i)
		if not demand_policy and credited[i] and cleared[i] and not moving[i] and growth[i] > 0.0:
			floor_debris.append(i)
		if credited[i]:
			remaining -= 1
		if moving[i]:
			active.append(i)
	if demand_policy:
		for value in snapshot.floor_debris:
			floor_debris.append(int(value))
		# Older saves may carry validated cosmetic extraction requests. Drop
		# them: replay would spawn dirt after the original contact has ended.
	surface_coverage_total = 0.0
	water_coverage_total = 0.0
	extraction_coverage_total = 0.0
	wet_recipe = bool(snapshot.get("wet_recipe", wet_recipe))
	skip_dry_stage = wet_recipe and bool(snapshot.get("skip_dry_stage", skip_dry_stage))
	_update_wet_materials()
	for i in coverage_values.size():
		coverage_values[i] = float(pixels[i]) / 255.0
		mask.set_pixel(i % MASK_SIZE.x, i / MASK_SIZE.x, Color(coverage_values[i], coverage_values[i], coverage_values[i]))
		water_values[i] = float(water_pixels[i]) / 255.0 if has_water else 0.0
		extraction_values[i] = float(extraction_pixels[i]) / 255.0 if has_water else 0.0
		var visible_water := clampf(water_values[i] - extraction_values[i], 0.0, 1.0)
		wet_mask.set_pixel(i % MASK_SIZE.x, i / MASK_SIZE.x, Color(visible_water, visible_water, visible_water))
		if surface_pixels[i] == 1:
			surface_coverage_total += coverage_values[i]
			water_coverage_total += water_values[i]
			extraction_coverage_total += extraction_values[i]
	if skip_dry_stage:
		_clear_dry_stage()
	end_pass()
	mask_changed = true
	wet_mask_changed = true
	request_render()
	set_physics_process(not simulation_suspended and (not active.is_empty() or not timed_debris.is_empty()))
	progress_changed.emit(remaining, initial.size())
	return true
