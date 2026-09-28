extends Node3D
## Shared, opaque perimeter splash: a hose circle or all four blade edges.
## One permanent open-center strip and 24 pooled droplets; visual only.
## Keep this controller at world identity, like the hose/squeegee owners.

const DROPLET_CAPACITY := 24
const PATCH_SEGMENTS := 128
const PATCH_ROWS := 9
const PATCH_RELEASE_SECONDS := 0.20
const DROPLETS_PER_SECOND := 40.0
const DROPLET_GRAVITY := 5.5
const MAX_STEP := 0.10
const MAX_BIRTHS_PER_FRAME := 5
const RUG_Y := 0.071
const FLOOR_Y := 0.006
const APRON := 0.008

var rect_reach := 0.17
var rect_height := 0.085
var patch: MeshInstance3D
var patch_material: ShaderMaterial
var droplets: MultiMeshInstance3D
var droplet_batch: MultiMesh
var droplet_material: ShaderMaterial
var footprint: RefCounted
var surface_texture: Texture2D
var clock_seconds := 0.0
var contact_active := false
var patch_strength := 0.0
var active_droplet_count := 0
var emitted_count := 0
var _emission_accumulator := 0.0
var _next_slot := 0
var _contact_radius := 0.17
var _rectangular := false
var _half_extents := Vector2(0.34, 0.075)
var _corner_radius := 0.0225
var _perimeter_length := TAU * 0.17
var _lobes := 12.0
var _power := 1.0
var _reach := 0.17
var _crest := 0.085
var _contact_at := Vector3.ZERO
var _orientation := Basis.IDENTITY
var _ages := PackedFloat32Array()
var _durations := PackedFloat32Array()
var _sizes := PackedFloat32Array()
var _origins := PackedVector3Array()
var _velocities := PackedVector3Array()


func setup(rug_footprint: RefCounted = null, texture: Texture2D = null) -> void:
	assert(patch == null, "Impact resources must be allocated only once")
	footprint = rug_footprint
	surface_texture = texture
	if surface_texture == null and footprint != null:
		# Hose callers need not own a wetness texture. Build this immutable
		# silhouette once; wetness is never read or written by this effect.
		var mask_size := Vector2i(128, 212)
		var pixels := PackedByteArray()
		pixels.resize(mask_size.x * mask_size.y)
		for y in mask_size.y:
			for x in mask_size.x:
				var point := (Vector2(x + 0.5, y + 0.5) / Vector2(mask_size) - Vector2(0.5, 0.5)) * Vector2(2.0, 3.32)
				pixels[y * mask_size.x + x] = 255 if footprint.contains_point(point) else 0
		surface_texture = ImageTexture.create_from_image(Image.create_from_data(mask_size.x, mask_size.y, false, Image.FORMAT_L8, pixels))
	patch = MeshInstance3D.new()
	patch.name = "OpaquePerimeterSplash"
	patch.mesh = _build_patch_mesh()
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patch.custom_aabb = AABB(Vector3(-1.5, -0.2, -1.5), Vector3(3.0, 0.6, 3.0))
	patch_material = ShaderMaterial.new()
	patch_material.shader = preload("res://scripts/water_jet_impact.gdshader")
	patch_material.set_shader_parameter("use_rug_surface", surface_texture != null)
	if surface_texture != null:
		patch_material.set_shader_parameter("rug_surface", surface_texture)
	patch.material_override = patch_material
	add_child(patch)
	droplets = MultiMeshInstance3D.new()
	droplets.name = "PerimeterDroplets24"
	droplets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	droplets.custom_aabb = AABB(Vector3(-6.0, -0.2, -6.0), Vector3(12.0, 3.0, 12.0))
	droplet_batch = MultiMesh.new()
	droplet_batch.transform_format = MultiMesh.TRANSFORM_3D
	var droplet_mesh := SphereMesh.new()
	droplet_mesh.radius = 1.0
	droplet_mesh.height = 2.0
	droplet_mesh.radial_segments = 8
	droplet_mesh.rings = 4
	droplet_batch.mesh = droplet_mesh
	droplet_batch.instance_count = DROPLET_CAPACITY
	droplets.multimesh = droplet_batch
	droplet_material = ShaderMaterial.new()
	droplet_material.shader = preload("res://scripts/water_jet_droplet.gdshader")
	droplets.material_override = droplet_material
	add_child(droplets)
	_ages.resize(DROPLET_CAPACITY)
	_durations.resize(DROPLET_CAPACITY)
	_sizes.resize(DROPLET_CAPACITY)
	_origins.resize(DROPLET_CAPACITY)
	_velocities.resize(DROPLET_CAPACITY)
	reset()


func update_contact(active: bool, at: Vector3, radius: float, delta: float, outer_radius: float = -1.0) -> void:
	if patch == null:
		return
	if active:
		_rectangular = false
		_contact_radius = clampf(radius, 0.025, 0.60)
		_perimeter_length = TAU * _contact_radius
		_orientation = Basis.IDENTITY
		_power = 1.0
		# Start under the column edge, not at the outside of its old filled disk.
		# Keep the upgrade's authored landing extent without leaving a dry gap.
		_reach = clampf(outer_radius - _contact_radius + APRON, 0.06, 0.24) if outer_radius > radius else clampf(0.08 + _contact_radius * 0.30, 0.10, 0.22)
		_crest = clampf(0.038 + maxf(_contact_radius, outer_radius) * 0.12, 0.045, 0.090)
		_set_contact_pose(at)
	_advance(active, delta)


func update_rect_contact(active: bool, at: Vector3, half_extents: Vector2, heading: Vector3, power: float, delta: float) -> void:
	if patch == null:
		return
	if active:
		_rectangular = true
		_half_extents = Vector2(clampf(half_extents.x, 0.03, 0.80), clampf(half_extents.y, 0.025, 0.50))
		_corner_radius = minf(0.024, minf(_half_extents.x, _half_extents.y) * 0.30)
		_perimeter_length = 4.0 * (_half_extents.x + _half_extents.y - 2.0 * _corner_radius) + TAU * _corner_radius
		var forward := Vector3(heading.x, 0.0, heading.z).normalized()
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		_orientation = Basis(Vector3.UP.cross(forward), Vector3.UP, forward)
		_power = clampf(power, 0.0, 1.0)
		var fullness := sqrt(_power)
		_reach = clampf(rect_reach, 0.06, 0.24) * lerpf(0.65, 1.0, fullness)
		_crest = clampf(rect_height, 0.025, 0.11) * lerpf(0.50, 1.0, fullness)
		_set_contact_pose(at)
	_advance(active, delta)


func _set_contact_pose(at: Vector3) -> void:
	_contact_at = at
	patch.transform = Transform3D(_orientation, at)
	_lobes = float(clampi(roundi(_perimeter_length / 0.115), 9, 24))


func _advance(active: bool, delta: float) -> void:
	var step := clampf(delta, 0.0, MAX_STEP)
	clock_seconds += step
	var starting := active and not contact_active
	contact_active = active
	if active:
		patch_strength = 1.0
		_emission_accumulator += step * DROPLETS_PER_SECOND * lerpf(0.45, 1.0, sqrt(_power))
		if starting:
			_emission_accumulator += 4.0
	else:
		patch_strength = maxf(0.0, patch_strength - step / PATCH_RELEASE_SECONDS)
		_emission_accumulator = 0.0
	patch.visible = patch_strength > 0.0
	if patch.visible:
		patch_material.set_shader_parameter("water_clock", fmod(clock_seconds, 100.0))
		patch_material.set_shader_parameter("rectangular", _rectangular)
		patch_material.set_shader_parameter("impact_radius", _contact_radius)
		patch_material.set_shader_parameter("half_extents", _half_extents)
		patch_material.set_shader_parameter("corner_radius", _corner_radius)
		patch_material.set_shader_parameter("perimeter_length", _perimeter_length)
		patch_material.set_shader_parameter("lobe_count", _lobes)
		patch_material.set_shader_parameter("outward_reach", _reach)
		patch_material.set_shader_parameter("crest_height", _crest)
		patch_material.set_shader_parameter("strength", patch_strength)
	active_droplet_count = 0
	for slot in DROPLET_CAPACITY:
		if _durations[slot] <= 0.0:
			continue
		_ages[slot] += step
		var point := _droplet_position(slot)
		if _ages[slot] >= _durations[slot] or point.y < _surface_height(point) + 0.001:
			_durations[slot] = 0.0
			_hide_droplet(slot)
			continue
		_update_droplet(slot)
		active_droplet_count += 1
	if active:
		var births := mini(MAX_BIRTHS_PER_FRAME, floori(_emission_accumulator))
		_emission_accumulator = fmod(_emission_accumulator, 1.0)
		for _index in births:
			_spawn_droplet()
	droplet_batch.visible_instance_count = DROPLET_CAPACITY if active_droplet_count > 0 else 0
	droplets.visible = active_droplet_count > 0


func reset() -> void:
	contact_active = false
	patch_strength = 0.0
	clock_seconds = 0.0
	active_droplet_count = 0
	emitted_count = 0
	_emission_accumulator = 0.0
	_next_slot = 0
	if patch == null:
		return
	patch.visible = false
	droplets.visible = false
	for slot in DROPLET_CAPACITY:
		_durations[slot] = 0.0
		_ages[slot] = 0.0
		_hide_droplet(slot)
	droplet_batch.visible_instance_count = 0


func is_alive() -> bool:
	return contact_active or patch_strength > 0.0 or active_droplet_count > 0


func debug_stats() -> Dictionary:
	var rug_contacts := 0
	var floor_contacts := 0
	if contact_active:
		for sample_index in 16:
			var point: Vector3 = sample_perimeter(float(sample_index) / 16.0).point
			if point.y > 0.04:
				rug_contacts += 1
			else:
				floor_contacts += 1
	return {
		"contact_active": contact_active,
		"patch_strength": patch_strength,
		"active_droplets": active_droplet_count,
		"droplet_capacity": DROPLET_CAPACITY,
		"emitted_droplets": emitted_count,
		"patch_vertices": (PATCH_SEGMENTS + 1) * PATCH_ROWS,
		"mesh_instances": 2,
		"impact_radius": _contact_radius,
		"shape": "rectangle" if _rectangular else "circle",
		"active_edges": 4 if _rectangular and contact_active else (1 if contact_active else 0),
		"active_contacts": 4 if _rectangular and contact_active else (1 if contact_active else 0),
		"active_patches": 1 if patch_strength > 0.0 else 0,
		"outward_reach": _reach,
		"crest_height": _crest,
		"power": _power,
		"perimeter_only": true,
		"rug_contacts": rug_contacts,
		"floor_contacts": floor_contacts,
	}


## CPU mirrors of the shader for bounded silhouette/rotation assertions.
func sample_perimeter(u: float) -> Dictionary:
	var frame := _perimeter_at(u)
	var local_point := Vector2(frame.x, frame.y)
	var local_normal := Vector2(frame.z, frame.w)
	var point := _contact_at + _orientation * Vector3(frame.x, 0.0, frame.y)
	point.y = _surface_height(point)
	var edge := -1
	if _rectangular:
		if absf(frame.w) >= absf(frame.z):
			edge = 0 if frame.w >= 0.0 else 2
		else:
			edge = 3 if frame.z >= 0.0 else 1
	return {"point": point, "normal": _orientation * Vector3(frame.z, 0.0, frame.w),
		"edge": edge, "local_point": local_point, "local_normal": local_normal}


func sample_splash(u: float, across: float) -> Vector3:
	var frame := _perimeter_at(u)
	var wave := _lobe_wave(u)
	var t := clampf(across, 0.0, 1.0)
	var extension := _reach * (0.72 + 0.28 * wave) * patch_strength
	var distance := -APRON + extension * (1.0 - cos(t * PI * 0.5))
	var point := _contact_at + _orientation * Vector3(frame.x + frame.z * distance, 0.0, frame.y + frame.w * distance)
	var arch := pow(maxf(0.0, sin(t * PI)), 0.85)
	point.y = _surface_height(point) + 0.003 + _crest * (0.43 + 0.57 * wave) * arch * patch_strength
	return point


func _lobe_wave(u: float) -> float:
	var phase := fposmod(u, 1.0) * TAU
	var pulse := 0.5 + 0.5 * sin(phase * _lobes - clock_seconds * 5.0)
	var swell := 0.82 + 0.18 * sin(phase * 3.0 + clock_seconds * 2.4)
	return pulse * swell


func _perimeter_at(u: float) -> Vector4:
	var fraction := fposmod(u, 1.0)
	if not _rectangular:
		var angle := fraction * TAU
		return Vector4(cos(angle) * _contact_radius, sin(angle) * _contact_radius, cos(angle), sin(angle))
	var a := _half_extents.x
	var b := _half_extents.y
	var r := _corner_radius
	var horizontal := 2.0 * (a - r)
	var vertical := 2.0 * (b - r)
	var arc := PI * 0.5 * r
	var distance := fraction * _perimeter_length
	if distance < horizontal:
		return Vector4(a - r - distance, b, 0.0, 1.0)
	distance -= horizontal
	if distance < arc:
		return _corner_frame(Vector2(-a + r, b - r), PI * 0.5 + distance / r, r)
	distance -= arc
	if distance < vertical:
		return Vector4(-a, b - r - distance, -1.0, 0.0)
	distance -= vertical
	if distance < arc:
		return _corner_frame(Vector2(-a + r, -b + r), PI + distance / r, r)
	distance -= arc
	if distance < horizontal:
		return Vector4(-a + r + distance, -b, 0.0, -1.0)
	distance -= horizontal
	if distance < arc:
		return _corner_frame(Vector2(a - r, -b + r), PI * 1.5 + distance / r, r)
	distance -= arc
	if distance < vertical:
		return Vector4(a, -b + r + distance, 1.0, 0.0)
	distance -= vertical
	return _corner_frame(Vector2(a - r, b - r), distance / r, r)


func _corner_frame(center: Vector2, angle: float, radius: float) -> Vector4:
	var normal := Vector2(cos(angle), sin(angle))
	var point := center + normal * radius
	return Vector4(point.x, point.y, normal.x, normal.y)


func _surface_height(point: Vector3) -> float:
	if footprint == null:
		return _contact_at.y
	return RUG_Y if footprint.contains_point(Vector2(point.x, point.z)) else FLOOR_Y


func _droplet_perimeter_u() -> float:
	if not _rectangular:
		return fposmod(float(emitted_count) * 0.618033989, 1.0)
	# Give each blade side equal opportunities, including the short ends.
	var edge := emitted_count % 4
	var along := 0.15 + 0.70 * fposmod(floorf(float(emitted_count) / 4.0) * 0.618033989 + 0.35, 1.0)
	var horizontal := 2.0 * (_half_extents.x - _corner_radius)
	var vertical := 2.0 * (_half_extents.y - _corner_radius)
	var arc := PI * 0.5 * _corner_radius
	var distance := horizontal * along
	if edge == 1:
		distance = horizontal + arc + vertical * along
	elif edge == 2:
		distance = horizontal + vertical + 2.0 * arc + horizontal * along
	elif edge == 3:
		distance = 2.0 * horizontal + vertical + 3.0 * arc + vertical * along
	return distance / _perimeter_length


func _spawn_droplet() -> void:
	var slot := _next_slot
	var available := false
	for _attempt in DROPLET_CAPACITY:
		if _durations[slot] <= 0.0:
			available = true
			break
		slot = (slot + 1) % DROPLET_CAPACITY
	if not available:
		return
	_next_slot = (slot + 1) % DROPLET_CAPACITY
	var seed_value := float(emitted_count)
	var frame := _perimeter_at(_droplet_perimeter_u())
	var outward := _orientation * Vector3(frame.z, 0.0, frame.w)
	var origin := _contact_at + _orientation * Vector3(frame.x, 0.0, frame.y)
	origin.y = _surface_height(origin) + 0.012
	var variation := 0.5 + 0.5 * sin(seed_value * 2.39996323 + 0.7)
	var fullness := lerpf(0.68, 1.0, sqrt(_power))
	var vertical_speed := lerpf(0.64, 0.98, variation) * fullness
	_origins[slot] = origin + outward * 0.005
	_velocities[slot] = outward * lerpf(0.32, 0.58, variation) * fullness + Vector3.UP * vertical_speed
	_durations[slot] = minf(0.46, vertical_speed * 2.0 / DROPLET_GRAVITY + 0.07)
	_ages[slot] = 0.0
	_sizes[slot] = lerpf(0.006, 0.011, variation) * fullness
	_update_droplet(slot)
	active_droplet_count += 1
	emitted_count += 1


func _droplet_position(slot: int) -> Vector3:
	var age := _ages[slot]
	return _origins[slot] + _velocities[slot] * age + Vector3.DOWN * (0.5 * DROPLET_GRAVITY * age * age)


func _update_droplet(slot: int) -> void:
	var remaining := clampf((_durations[slot] - _ages[slot]) / 0.07, 0.0, 1.0)
	var size := _sizes[slot] * remaining
	var shape := Basis.from_scale(Vector3(size, size * 1.25, size))
	droplet_batch.set_instance_transform(slot, Transform3D(shape, _droplet_position(slot)))


func _hide_droplet(slot: int) -> void:
	droplet_batch.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -10.0, 0.0)))


func _build_patch_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# No central vertex or disk. Duplicate seam keeps perimeter UV continuous.
	for row in PATCH_ROWS:
		for side in PATCH_SEGMENTS + 1:
			var uv := Vector2(float(side) / float(PATCH_SEGMENTS), float(row) / float(PATCH_ROWS - 1))
			vertices.append(Vector3(uv.x, 0.0, uv.y))
			normals.append(Vector3.UP)
			uvs.append(uv)
	for row in PATCH_ROWS - 1:
		for side in PATCH_SEGMENTS:
			var a := row * (PATCH_SEGMENTS + 1) + side
			var b := a + PATCH_SEGMENTS + 1
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
