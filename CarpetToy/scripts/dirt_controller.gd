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
const GROW_SECONDS := 0.18
const COMPLETION_FRACTION := 1.0
const RUG_HALF := Vector2(1.0, 1.66) # Includes the fringe.
const HEAD_HALF := Vector2(0.305, 0.11)
const RUG_Y := 0.067
const GRAVITY := 9.8
const SLIDE_FRICTION := 3.8

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
	# Empty rounded corners and fringe gaps are not dirty carpet surface.
	surface_pixels.resize(MASK_SIZE.x * MASK_SIZE.y)
	for y in MASK_SIZE.y:
		for x in MASK_SIZE.x:
			var point := (Vector2(x + 0.5, y + 0.5) / Vector2(MASK_SIZE) - Vector2.ONE * 0.5) * RUG_HALF * 2.0
			if footprint.contains_point(point):
				surface_pixels[y * MASK_SIZE.x + x] = 1
				surface_pixel_count += 1
	for mesh in rug.get_node("Dirty/CarpetMesh").get_children():
		if not mesh is MeshInstance3D:
			continue
		var clean := mesh.mesh.surface_get_material(0) as StandardMaterial3D
		var material := ShaderMaterial.new()
		material.shader = preload("res://scripts/soil_surface.gdshader")
		material.set_shader_parameter("coverage", mask_texture)
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
	set_physics_process(not value and ((completion_started and not vacuum_complete) or not active.is_empty()))

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
	for i in initial.size():
		positions[i] = initial[i].origin
		velocities[i] = Vector3.ZERO
		cleared[i] = false
		cooldown[i] = 0.0
		moving[i] = false
		growth[i] = initial_growth[i]
		awakened[i] = false
		credited[i] = false
	remaining = initial.size()
	last_z_direction = 1.0
	mask.fill(Color.WHITE)
	mask_texture.update(mask)
	mask_changed = false
	coverage_values.resize(MASK_SIZE.x * MASK_SIZE.y)
	coverage_values.fill(1.0)
	surface_coverage_total = float(surface_pixel_count)
	pass_strength.resize(coverage_values.size())
	pass_active = false
	set_physics_process(false)
	request_render()
	progress_changed.emit(remaining, initial.size())

func begin_pass() -> void:
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
		var visible_growth := growth[i] * smoothstep(delay, delay + 0.68, reveal_progress)
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
	vacuum_growth.assign(growth)
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
		if reversal_distance >= 0.08:
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
	var impulse := clampf(1.9 + speed * 0.36, 2.0, 5.0)
	for i in positions.size():
		# "Cleared" tracks progress, not whether a clump can still be brushed.
		if cooldown[i] > 0.0 or positions[i].y > RUG_Y + 0.14:
			continue
		var point := Vector2(positions[i].x, positions[i].z)
		if not swept_head_hits(start, finish, point, head_half + Vector2.ONE * radii[i] * growth[i]):
			continue
		var fan := sin(float(i) * 7.13) * 0.09
		velocities[i] = Vector3((direction.x + fan) * impulse, 0.45 + impulse * 0.10, direction.y * impulse)
		cooldown[i] = 0.14
		awakened[i] = true
		if not moving[i]:
			active.append(i)
			moving[i] = true
	paint_stroke(paint_from, finish)
	set_physics_process(not active.is_empty())

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
				coverage_values[index] = maxf(0.0, pass_base[index] - rug_definition.removal_per_pass * weight)
				var value := coverage_values[index]
				if surface_pixels[index] == 1:
					surface_coverage_total += value - old_value
				mask.set_pixel(x, y, Color(value, value, value))
				mask_changed = true
	set_process(mask_changed or render_dirty)

func _process(_delta: float) -> void:
	if render_dirty:
		refresh_visible_clumps()
	if mask_changed:
		mask_texture.update(mask)
		mask_changed = false
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
	var changed := false
	for slot in range(active.size() - 1, -1, -1):
		var i := active[slot]
		cooldown[i] = maxf(0.0, cooldown[i] - delta)
		if growth[i] < 1.0:
			growth[i] = move_toward(growth[i], 1.0, delta / GROW_SECONDS)
			update_clump_transform(i)
			if growth[i] < 1.0:
				continue
		velocities[i].y -= GRAVITY * delta
		positions[i] += velocities[i] * delta
		var outside := clump_is_outside(i)
		# Physical location is reversible; earned cleanliness is permanent.
		if not outside:
			cleared[i] = false
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
	if changed:
		progress_changed.emit(remaining, initial.size())
	if remaining == 0 and automatic_completion_enabled:
		start_vacuum()
	elif active.is_empty():
		set_physics_process(false)

func unique_clearance() -> float:
	return clampf(1.0 - float(remaining) / maxf(initial.size(), 1), 0.0, 1.0)

func surface_clearance() -> float:
	return clampf(1.0 - surface_coverage_total / maxf(surface_pixel_count, 1), 0.0, 1.0)

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
	return {
		"version": 1, "positions": saved_positions, "velocities": saved_velocities,
		"spawn_positions": spawn_positions,
		"growth": growth.duplicate(), "awakened": awakened.duplicate(),
		"credited": credited.duplicate(), "cleared": cleared.duplicate(),
		"cooldown": cooldown.duplicate(), "moving": moving.duplicate(),
		"coverage": Marshalls.raw_to_base64(pixels),
		"unique_clearance": unique_clearance(), "surface_clearance": surface_clearance(),
	}

func restore_snapshot(snapshot: Dictionary) -> bool:
	if int(snapshot.get("version", 0)) != 1:
		return false
	for key in ["positions", "velocities", "growth", "awakened", "credited", "cleared", "cooldown", "moving"]:
		if not snapshot.get(key) is Array or snapshot[key].size() != initial.size():
			return false
	var pixels := Marshalls.base64_to_raw(str(snapshot.get("coverage", "")))
	if pixels.size() != coverage_values.size():
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
	active.clear()
	remaining = initial.size()
	for i in initial.size():
		var p: Array = snapshot.positions[i]
		var v: Array = snapshot.velocities[i]
		if snapshot.has("spawn_positions"):
			var spawn: Array = snapshot.spawn_positions[i]
			initial[i].origin = Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2]))
		positions[i] = Vector3(float(p[0]), float(p[1]), float(p[2]))
		velocities[i] = Vector3(float(v[0]), float(v[1]), float(v[2]))
		growth[i] = float(snapshot.growth[i])
		awakened[i] = snapshot.awakened[i]
		credited[i] = snapshot.credited[i]
		cleared[i] = snapshot.cleared[i]
		cooldown[i] = float(snapshot.cooldown[i])
		moving[i] = snapshot.moving[i]
		if credited[i]:
			remaining -= 1
		if moving[i]:
			active.append(i)
	surface_coverage_total = 0.0
	for i in coverage_values.size():
		coverage_values[i] = float(pixels[i]) / 255.0
		mask.set_pixel(i % MASK_SIZE.x, i / MASK_SIZE.x, Color(coverage_values[i], coverage_values[i], coverage_values[i]))
		if surface_pixels[i] == 1:
			surface_coverage_total += coverage_values[i]
	end_pass()
	mask_changed = true
	request_render()
	set_physics_process(not simulation_suspended and not active.is_empty())
	progress_changed.emit(remaining, initial.size())
	return true
