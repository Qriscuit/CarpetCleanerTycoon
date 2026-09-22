extends Node3D
## Fixed-cost opaque impact sheet and secondary droplets for the coherent jet.
## The owner calls update_contact every frame until is_alive() is false.
## Position and all pooled droplet trajectories are in world coordinates; keep
## this node at an identity transform alongside the world-space jet controller.

const DROPLET_CAPACITY := 24
const PATCH_SEGMENTS := 32
const PATCH_RING_RADII := [0.25, 0.62, 0.90, 1.0]
const PATCH_RELEASE_SECONDS := 0.20
const DROPLETS_PER_SECOND := 48.0
const DROPLET_GRAVITY := 5.5
const MAX_STEP := 0.10
const MAX_BIRTHS_PER_FRAME := 5

var patch: MeshInstance3D
var patch_material: ShaderMaterial
var droplets: MultiMeshInstance3D
var droplet_batch: MultiMesh
var droplet_material: ShaderMaterial
var clock_seconds := 0.0
var contact_active := false
var patch_strength := 0.0
var active_droplet_count := 0
var emitted_count := 0
var _emission_accumulator := 0.0
var _next_slot := 0
var _contact_radius := 0.17
var _ages := PackedFloat32Array()
var _durations := PackedFloat32Array()
var _sizes := PackedFloat32Array()
var _origins := PackedVector3Array()
var _velocities := PackedVector3Array()


func setup() -> void:
	assert(patch == null, "Impact resources must be allocated only once")
	patch = MeshInstance3D.new()
	patch.name = "OpaqueImpactCrown"
	patch.mesh = _build_patch_mesh()
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patch.custom_aabb = AABB(Vector3(-0.7, -0.05, -0.7), Vector3(1.4, 0.4, 1.4))
	patch_material = ShaderMaterial.new()
	patch_material.shader = preload("res://scripts/water_jet_impact.gdshader")
	patch.material_override = patch_material
	add_child(patch)

	droplets = MultiMeshInstance3D.new()
	droplets.name = "OpaqueJetDroplets24"
	droplets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Positions are world-space, and the entire fixed batch covers the gym.
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


func update_contact(active: bool, at: Vector3, radius: float, delta: float) -> void:
	if patch == null:
		return
	var step := clampf(delta, 0.0, MAX_STEP)
	clock_seconds += step
	var starting := active and not contact_active
	contact_active = active
	if active:
		_contact_radius = clampf(radius, 0.025, 0.60)
		patch.position = at + Vector3.UP * 0.002
		# The central sheet appears immediately on contact; the shallow crown
		# and scalloped edge are continuously deformed by the vertex shader.
		patch_strength = 1.0
		_emission_accumulator += step * DROPLETS_PER_SECOND
		if starting:
			_emission_accumulator += 3.0
	else:
		patch_strength = maxf(0.0, patch_strength - step / PATCH_RELEASE_SECONDS)
		_emission_accumulator = 0.0
	patch.visible = patch_strength > 0.0
	if patch.visible:
		patch_material.set_shader_parameter("water_clock", fmod(clock_seconds, 100.0))
		patch_material.set_shader_parameter("impact_radius", _contact_radius)
		patch_material.set_shader_parameter("strength", patch_strength)

	active_droplet_count = 0
	for slot in DROPLET_CAPACITY:
		if _durations[slot] <= 0.0:
			continue
		_ages[slot] += step
		if _ages[slot] >= _durations[slot]:
			_durations[slot] = 0.0
			_hide_droplet(slot)
			continue
		_update_droplet(slot)
		active_droplet_count += 1
	if active:
		var births := mini(MAX_BIRTHS_PER_FRAME, floori(_emission_accumulator))
		_emission_accumulator = fmod(_emission_accumulator, 1.0)
		for _index in births:
			_spawn_droplet(at)
	droplet_batch.visible_instance_count = DROPLET_CAPACITY if active_droplet_count > 0 else 0


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
	for slot in DROPLET_CAPACITY:
		_durations[slot] = 0.0
		_ages[slot] = 0.0
		_hide_droplet(slot)
	droplet_batch.visible_instance_count = 0


func is_alive() -> bool:
	return contact_active or patch_strength > 0.0 or active_droplet_count > 0


func debug_stats() -> Dictionary:
	return {
		"contact_active": contact_active,
		"patch_strength": patch_strength,
		"active_droplets": active_droplet_count,
		"droplet_capacity": DROPLET_CAPACITY,
		"emitted_droplets": emitted_count,
		"patch_vertices": 1 + PATCH_SEGMENTS * PATCH_RING_RADII.size(),
		"mesh_instances": 2,
		"impact_radius": _contact_radius,
	}


func _spawn_droplet(at: Vector3) -> void:
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
	# Golden-angle distribution produces a lively spray without a random
	# allocation or synchronized circular bursts. Each slot keeps its origin.
	var seed_value := float(emitted_count)
	var angle := seed_value * 2.39996323 + clock_seconds * 1.2
	var outward := Vector3(cos(angle), 0.0, sin(angle))
	var variation := 0.5 + 0.5 * sin(seed_value * 5.173 + 0.7)
	var vertical_speed := lerpf(0.64, 1.12, variation)
	_origins[slot] = at + outward * _contact_radius * lerpf(0.38, 0.73, variation) + Vector3.UP * 0.008
	_velocities[slot] = outward * lerpf(0.26, 0.55, variation) + Vector3.UP * vertical_speed
	_durations[slot] = vertical_speed * 2.0 / DROPLET_GRAVITY
	_ages[slot] = 0.0
	_sizes[slot] = lerpf(0.007, 0.014, 1.0 - variation * 0.6)
	_update_droplet(slot)
	active_droplet_count += 1
	emitted_count += 1


func _update_droplet(slot: int) -> void:
	var age := _ages[slot]
	var life := age / _durations[slot]
	var remaining := clampf((1.0 - life) / 0.18, 0.0, 1.0)
	var size := _sizes[slot] * remaining
	var point := _origins[slot] + _velocities[slot] * age + Vector3.DOWN * (0.5 * DROPLET_GRAVITY * age * age)
	var shape := Basis.from_scale(Vector3(size, size * 1.35, size))
	droplet_batch.set_instance_transform(slot, Transform3D(shape, point))


func _hide_droplet(slot: int) -> void:
	droplet_batch.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -10.0, 0.0)))


func _build_patch_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	uvs.append(Vector2.ZERO)
	for ring_radius in PATCH_RING_RADII:
		for side in PATCH_SEGMENTS:
			var angle := float(side) / float(PATCH_SEGMENTS) * TAU
			vertices.append(Vector3(cos(angle), 0.0, sin(angle)) * ring_radius)
			normals.append(Vector3.UP)
			uvs.append(Vector2(angle, ring_radius))
	for side in PATCH_SEGMENTS:
		var next := (side + 1) % PATCH_SEGMENTS
		indices.append_array(PackedInt32Array([0, 1 + next, 1 + side]))
	for ring in range(PATCH_RING_RADII.size() - 1):
		var inner := 1 + ring * PATCH_SEGMENTS
		var outer := inner + PATCH_SEGMENTS
		for side in PATCH_SEGMENTS:
			var next := (side + 1) % PATCH_SEGMENTS
			indices.append_array(PackedInt32Array([inner + side, inner + next, outer + side, inner + next, outer + next, outer + side]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
