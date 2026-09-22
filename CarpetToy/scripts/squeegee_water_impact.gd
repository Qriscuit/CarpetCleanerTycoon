extends Node3D
## One shared splash batch and 24 world-space droplets, independent of tool pose.

const PATCH_CAPACITY := 21
const DROP_CAPACITY := 24
const RELEASE := 0.20
const DROP_GRAVITY := 5.8

class Patch:
	extends RefCounted
	var strength := 0.0
	var touched := false
	var point := Vector3.ZERO
	var side := Vector3.RIGHT
	var width := 0.10
	var power := 0.0

var patches: Array[Patch] = []
var patch_batch: MultiMesh
var patch_node: MultiMeshInstance3D
var patch_material: ShaderMaterial
var drop_batch: MultiMesh
var drop_node: MultiMeshInstance3D
var footprint: RefCounted
var clock_seconds := 0.0
var active_contacts := 0
var active_patches := 0
var active_droplets := 0
var emitted_droplets := 0
var _credit := 0.0
var _cursor := 0
var _ages := PackedFloat32Array()
var _durations := PackedFloat32Array()
var _sizes := PackedFloat32Array()
var _origins := PackedVector3Array()
var _velocities := PackedVector3Array()
var _landing_points := PackedVector4Array()
var _landing_sides := PackedVector4Array()

func setup(rug_footprint: RefCounted, texture: ImageTexture) -> void:
	footprint = rug_footprint
	patch_batch = MultiMesh.new()
	patch_batch.transform_format = MultiMesh.TRANSFORM_3D
	patch_batch.use_custom_data = true
	patch_batch.mesh = _patch_mesh()
	# One continuous strip per sheet, split into rug/tile layers by a fixed mask.
	patch_batch.instance_count = 6
	patch_node = MultiMeshInstance3D.new()
	patch_node.name = "ContinuousLandingStrips6"
	patch_node.multimesh = patch_batch
	patch_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patch_node.custom_aabb = AABB(Vector3(-6, -0.1, -6), Vector3(12, 3, 12))
	patch_material = ShaderMaterial.new()
	patch_material.shader = preload("res://scripts/squeegee_water_impact.gdshader")
	patch_material.set_shader_parameter("rug_surface", texture)
	patch_node.material_override = patch_material
	add_child(patch_node)
	for slot in PATCH_CAPACITY:
		patches.append(Patch.new())
	drop_batch = MultiMesh.new()
	drop_batch.transform_format = MultiMesh.TRANSFORM_3D
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	drop_batch.mesh = sphere
	drop_batch.instance_count = DROP_CAPACITY
	drop_node = MultiMeshInstance3D.new()
	drop_node.name = "LandingDroplets24"
	drop_node.multimesh = drop_batch
	drop_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drop_node.custom_aabb = patch_node.custom_aabb
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/water_jet_droplet.gdshader")
	drop_node.material_override = material
	add_child(drop_node)
	_ages.resize(DROP_CAPACITY)
	_durations.resize(DROP_CAPACITY)
	_sizes.resize(DROP_CAPACITY)
	_origins.resize(DROP_CAPACITY)
	_velocities.resize(DROP_CAPACITY)
	_landing_points.resize(PATCH_CAPACITY)
	_landing_sides.resize(3)
	reset()

func reset() -> void:
	clock_seconds = 0.0
	active_contacts = 0
	active_patches = 0
	active_droplets = 0
	emitted_droplets = 0
	_credit = 0.0
	_cursor = 0
	for slot in patches.size():
		patches[slot].strength = 0.0
		patches[slot].touched = false
	for slot in 6:
		_hide_instance(patch_batch, slot)
	for slot in DROP_CAPACITY:
		_durations[slot] = 0.0
		_hide_instance(drop_batch, slot)
	patch_node.hide()
	drop_node.hide()

func begin_frame(delta: float) -> void:
	clock_seconds += delta
	active_contacts = 0
	for patch in patches:
		patch.touched = false
		patch.strength = maxf(0.0, patch.strength - delta / RELEASE)
	active_droplets = 0
	for slot in DROP_CAPACITY:
		if _durations[slot] <= 0.0: continue
		_ages[slot] += delta
		var point := _drop_position(slot)
		var plane := 0.071 if footprint.contains_point(Vector2(point.x, point.z)) else 0.006
		if _ages[slot] >= _durations[slot] or point.y < plane:
			_durations[slot] = 0.0
			_hide_instance(drop_batch, slot)
		else:
			_update_drop(slot)
			active_droplets += 1

func contact(slot: int, at: Vector3, side: Vector3, width: float, power: float) -> void:
	var patch := patches[slot]
	patch.point = at
	patch.side = side
	patch.width = width
	patch.power = power
	patch.strength = 1.0
	patch.touched = true
	active_contacts += 1

func finish_frame(delta: float) -> void:
	active_patches = 0
	var maximum_power := 0.0
	for slot in PATCH_CAPACITY:
		var patch := patches[slot]
		if patch.strength <= 0.0:
			continue
		active_patches += 1
		if patch.touched: maximum_power = maxf(maximum_power, patch.power)
	for segment in 3:
		var reference := -1
		for lane in 7:
			if patches[segment * 7 + lane].strength > 0.0:
				reference = segment * 7 + lane
				break
		if reference < 0:
			_hide_instance(patch_batch, segment * 2)
			_hide_instance(patch_batch, segment * 2 + 1)
			continue
		var anchor := patches[reference]
		_landing_sides[segment] = Vector4(anchor.side.x, anchor.side.y, anchor.side.z, anchor.width)
		for lane in 7:
			var patch := patches[segment * 7 + lane]
			var at := patch.point if patch.strength > 0.0 else anchor.point + anchor.side * float(segment * 7 + lane - reference) * anchor.width
			var fullness := smoothstep(0.0, 1.0, patch.strength) * lerpf(0.65, 1.0, sqrt(patch.power))
			_landing_points[segment * 7 + lane] = Vector4(at.x, at.y, at.z, fullness)
		for layer in 2:
			patch_batch.set_instance_transform(segment * 2 + layer, Transform3D.IDENTITY)
			patch_batch.set_instance_custom_data(segment * 2 + layer, Color(float(segment), float(layer), 0.0, 0.0))
	patch_material.set_shader_parameter("landing_points", _landing_points)
	patch_material.set_shader_parameter("landing_sides", _landing_sides)
	patch_material.set_shader_parameter("water_clock", fmod(clock_seconds, 100.0))
	patch_node.visible = active_patches > 0
	if active_contacts > 0:
		_credit += delta * 32.0 * sqrt(maximum_power)
		var births := mini(4, floori(_credit))
		_credit = fmod(_credit, 1.0)
		for _birth in births:
			for _attempt in PATCH_CAPACITY:
				_cursor = (_cursor + 5) % PATCH_CAPACITY
				if patches[_cursor].touched:
					_spawn_drop(patches[_cursor])
					break
	else:
		_credit = 0.0
	drop_node.visible = active_droplets > 0

func is_alive() -> bool:
	return active_patches > 0 or active_droplets > 0

func debug_stats() -> Dictionary:
	var rug := 0
	var floor_count := 0
	for patch in patches:
		if patch.touched:
			if patch.point.y > 0.04: rug += 1
			else: floor_count += 1
	return {"active_contacts": active_contacts, "active_patches": active_patches,
		"active_droplets": active_droplets, "emitted_droplets": emitted_droplets,
		"rug_contacts": rug, "floor_contacts": floor_count, "droplet_capacity": DROP_CAPACITY}

func _spawn_drop(patch: Patch) -> void:
	var slot := -1
	for index in DROP_CAPACITY:
		if _durations[index] <= 0.0:
			slot = index
			break
	if slot < 0: return
	var seed_value := float(emitted_droplets)
	var variation := 0.5 + 0.5 * sin(seed_value * 5.173 + 0.7)
	var sideways := sin(seed_value * 2.399963)
	var forward := patch.side.cross(Vector3.UP).normalized()
	_origins[slot] = patch.point + forward * 0.05 + patch.side * sideways * patch.width * 0.4 + Vector3.UP * 0.012
	_velocities[slot] = forward * lerpf(0.23, 0.48, variation) + patch.side * sideways * 0.25 + Vector3.UP * lerpf(0.62, 0.96, variation)
	_sizes[slot] = lerpf(0.009, 0.016, variation) * lerpf(0.65, 1.0, sqrt(patch.power))
	_durations[slot] = 0.46
	_ages[slot] = 0.0
	_update_drop(slot)
	active_droplets += 1
	emitted_droplets += 1

func _drop_position(slot: int) -> Vector3:
	var age := _ages[slot]
	return _origins[slot] + _velocities[slot] * age + Vector3.DOWN * (0.5 * DROP_GRAVITY * age * age)

func _update_drop(slot: int) -> void:
	var size := _sizes[slot] * clampf((_durations[slot] - _ages[slot]) / 0.07, 0.0, 1.0)
	drop_batch.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3(size, size * 1.4, size)), _drop_position(slot)))

func _hide_instance(batch: MultiMesh, slot: int) -> void:
	batch.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -10, 0)))

func _patch_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in 9:
		for column in 33:
			var uv := Vector2(float(column) / 32.0, float(row) / 8.0)
			vertices.append(Vector3(uv.x, 0, uv.y))
			normals.append(Vector3.UP)
			uvs.append(uv)
	for row in 8:
		for column in 32:
			var a := row * 33 + column
			indices.append_array(PackedInt32Array([a, a + 33, a + 1, a + 1, a + 33, a + 34]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
