extends Node3D
## A cosmetic player companion. Its private physics never touches carpet/economy.
enum State { RIDING, FALLING, GETTING_UP, DUSTING, RUNNING, CLIMBING, PARKED }
signal state_changed(state: int)
const Catalog = preload("res://scripts/avatar_catalog.gd")
const RIG_PATH := "res://assets/character/avatar_rig.glb"
const PIRATE = preload("res://assets/character/pirate_hat.glb")
const BEANIE = preload("res://assets/character/beanie.glb")
const PRIVATE_LAYER := 1 << 15
const ANIMATION_STEP := 1.0 / 30.0
const RIDE_PELVIS_Y := 0.88
const MAX_RAGDOLL_SECONDS := 2.8
const PHYSICS_MARGIN := 0.90
const FLOOR_THICKNESS := 0.24
@export_range(0.1, 0.5) var model_scale := 0.32
@export_range(2.0, 12.0) var fling_speed := 6.5
@export_range(0.03, 0.20) var fling_strain_seconds := 0.07
var state := State.RIDING
var active := false
var rig_ready := false
var falls := 0
var bounds := Rect2(-1.85, -2.3, 3.7, 4.6)
var floor_y := 0.067
var _rig: Node3D
var _skeleton: Skeleton3D
var _animation: AnimationPlayer
var _simulator: PhysicalBoneSimulator3D
var _bodies: Array[PhysicalBone3D] = []
var _body_bone_ids: Array[int] = []
var _saved_body_transforms: Array[Transform3D] = []
var _saved_velocities: Array[Vector3] = []
var _frozen_poses: Array[Transform3D] = []
var _recovery_world_poses: Array[Transform3D] = []
var _recovery_local_poses: Array[Transform3D] = []
var _animation_poses: Array[Transform3D] = []
var _materials: Array[StandardMaterial3D] = []
var _clips: Dictionary = {}
var _hat_pirate: Node3D
var _hat_beanie: Node3D
var _floor: StaticBody3D
var _floor_shape: BoxShape3D
var _walls: Array[CollisionShape3D] = []
var _seat := Transform3D.IDENTITY
var _has_seat := false
var _previous_seat := Vector3.ZERO
var _tool_velocity := Vector3.ZERO
var _previous_velocity := Vector3.ZERO
var _has_motion := false
var _strain := 0.0
var _cooldown := 1.6
var _age := 0.0
var _settled_age := 0.0
var _animation_elapsed := 0.0
var _climb_start := Vector3.ZERO
var _climb_rotation := Quaternion.IDENTITY
var _recover_blend := 0.0
var _suspended_fall := false
var _current_clip := ""
var _appearance: Dictionary = Catalog.default_appearance()

func _ready() -> void:
	set_physics_process(false)
	if not ResourceLoader.exists(RIG_PATH):
		push_error("Player companion rig is missing: " + RIG_PATH)
		return
	_rig = load(RIG_PATH).instantiate()
	_rig.name = "Character"
	add_child(_rig)
	var skeletons := _rig.find_children("*", "Skeleton3D", true, false)
	var players := _rig.find_children("*", "AnimationPlayer", true, false)
	if skeletons.is_empty() or players.is_empty():
		push_error("Player companion requires a skeleton and authored animation clips")
		return
	_skeleton = skeletons[0]
	_animation = players[0]
	_bake_runtime_scale()
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for animation_name: StringName in _animation.get_animation_list():
		for key: String in ["idle", "ride", "run", "get_up", "dust_off", "climb"]:
			if str(animation_name).to_lower().ends_with(key): _clips[key] = animation_name
	for mesh: MeshInstance3D in _rig.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			var material: StandardMaterial3D = source.duplicate() if source != null else StandardMaterial3D.new()
			mesh.set_surface_override_material(surface, material)
			_materials.append(material)
	_build_hats()
	_build_physics()
	for bone in _skeleton.get_bone_count():
		_recovery_world_poses.append(Transform3D.IDENTITY)
		_recovery_local_poses.append(Transform3D.IDENTITY)
		_animation_poses.append(Transform3D.IDENTITY)
	rig_ready = _bodies.size() == 9 and _clips.size() == 6
	if not rig_ready: push_error("Player companion rig does not satisfy the bone/animation contract")
	_play("ride", 0.0)
	_animation.advance(0.0)
	set_appearance(Catalog.default_appearance())

func _bake_runtime_scale() -> void:
	# Physics bodies return unit world bases. Bake the display size into this
	# instance's geometry/rest/skin/animation data so animation and ragdoll use
	# exactly the same unit-scale skeleton, without changing imported resources.
	for node: Node3D in _rig.find_children("*", "Node3D", true, false): node.position *= model_scale
	for id in _skeleton.get_bone_count():
		var rest := _skeleton.get_bone_rest(id)
		rest.origin *= model_scale
		_skeleton.set_bone_rest(id, rest)
		var pose := _skeleton.get_bone_pose(id)
		pose.origin *= model_scale
		_skeleton.set_bone_pose(id, pose)
	for instance: MeshInstance3D in _rig.find_children("*", "MeshInstance3D", true, false):
		var source := instance.mesh as ArrayMesh
		if source == null: continue
		var mesh := ArrayMesh.new()
		for surface in source.get_surface_count():
			var arrays := source.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in vertices.size(): vertices[i] *= model_scale
			arrays[Mesh.ARRAY_VERTEX] = vertices
			var flags := source.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
			mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [], {}, flags)
			mesh.surface_set_material(surface, source.surface_get_material(surface))
		instance.mesh = mesh
		if instance.skin != null:
			var skin := instance.skin.duplicate() as Skin
			for bind in skin.get_bind_count():
				var pose := skin.get_bind_pose(bind)
				pose.origin *= model_scale
				skin.set_bind_pose(bind, pose)
			instance.skin = skin
	for library_name: StringName in _animation.get_animation_library_list():
		var source := _animation.get_animation_library(library_name)
		var library := AnimationLibrary.new()
		for animation_name: StringName in source.get_animation_list():
			var clip := source.get_animation(animation_name).duplicate() as Animation
			var clip_name := str(animation_name).to_lower()
			var loops := clip_name.ends_with("idle") or clip_name.ends_with("ride") or clip_name.ends_with("run")
			clip.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
			for track in clip.get_track_count():
				if clip.track_get_type(track) != Animation.TYPE_POSITION_3D: continue
				for key in clip.track_get_key_count(track): clip.track_set_key_value(track, key, clip.track_get_key_value(track, key) * model_scale)
			library.add_animation(animation_name, clip)
		_animation.remove_animation_library(library_name)
		_animation.add_animation_library(library_name, library)

func setup(world_bounds: Rect2, ground_y: float, appearance: Dictionary) -> void:
	bounds = world_bounds
	floor_y = ground_y
	if not rig_ready: return
	# Include the tool's outer travel range; recovery feet use the tighter
	# walking bounds while a genuine fall can contact these private walls.
	var physics_bounds := bounds.grow(PHYSICS_MARGIN)
	_floor_shape.size = Vector3(physics_bounds.size.x + 0.2, FLOOR_THICKNESS, physics_bounds.size.y + 0.2)
	_floor.global_position = Vector3(bounds.get_center().x, floor_y - FLOOR_THICKNESS * 0.5, bounds.get_center().y)
	for i in 4:
		var shape: BoxShape3D = _walls[i].shape
		var x_wall := i < 2
		shape.size = Vector3(0.12, 2.4, physics_bounds.size.y + 0.24) if x_wall else Vector3(physics_bounds.size.x + 0.24, 2.4, 0.12)
		var sign := -1.0 if i % 2 == 0 else 1.0
		_walls[i].position = Vector3(sign * physics_bounds.size.x * 0.5, 1.2, 0) if x_wall else Vector3(0, 1.2, sign * physics_bounds.size.y * 0.5)
	set_appearance(appearance)

func _build_hats() -> void:
	var head_id := _skeleton.find_bone("head")
	var socket := BoneAttachment3D.new()
	socket.name = "HeadAccessories"
	socket.bone_name = "head"
	_skeleton.add_child(socket)
	var offset := _skeleton.get_bone_global_rest(head_id).affine_inverse() * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * model_scale), Vector3.ZERO)
	_hat_pirate = PIRATE.instantiate()
	_hat_beanie = BEANIE.instantiate()
	socket.add_child(_hat_pirate)
	socket.add_child(_hat_beanie)
	_hat_pirate.transform = offset
	_hat_beanie.transform = offset
	for mesh: MeshInstance3D in socket.find_children("*", "MeshInstance3D", true, false): mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_physics() -> void:
	_floor = StaticBody3D.new()
	_floor.name = "CompanionFloor"
	_floor.collision_layer = PRIVATE_LAYER
	_floor.collision_mask = 0
	var floor_collision := CollisionShape3D.new()
	_floor_shape = BoxShape3D.new()
	floor_collision.shape = _floor_shape
	_floor.add_child(floor_collision)
	for i in 4:
		var wall := CollisionShape3D.new()
		wall.name = "PrivateBoundary%d" % i
		wall.shape = BoxShape3D.new()
		_floor.add_child(wall)
		_walls.append(wall)
	add_child(_floor)
	_simulator = PhysicalBoneSimulator3D.new()
	_simulator.name = "FallSimulation"
	_skeleton.add_child(_simulator)
	_add_body("pelvis", 0.24, 0.14, 2.0)
	_add_body("spine", 0.50, 0.17, 2.0)
	_add_body("head", 0.40, 0.23, 1.0)
	_add_body("upper_arm_l", 0.48, 0.075, 0.5)
	_add_body("upper_arm_r", 0.48, 0.075, 0.5)
	_add_body("thigh_l", 0.40, 0.10, 0.8)
	_add_body("thigh_r", 0.40, 0.10, 0.8)
	_add_body("shin_l", 0.31, 0.08, 0.6)
	_add_body("shin_r", 0.31, 0.08, 0.6)
	_simulator.physical_bones_stop_simulation()
	_simulator.active = false

func _add_body(bone_name: String, length: float, radius: float, mass: float) -> void:
	var id := _skeleton.find_bone(bone_name)
	if id < 0: return
	length *= model_scale
	radius *= model_scale
	var body := PhysicalBone3D.new()
	body.name = "Physical_" + bone_name
	body.set("bone_name", bone_name)
	body.mass = mass
	body.collision_layer = 0
	body.collision_mask = PRIVATE_LAYER
	body.friction = 0.85
	body.bounce = 0.05
	body.linear_damp = 0.8
	body.angular_damp = 1.7
	body.body_offset = Transform3D(Basis.IDENTITY, Vector3(0, length * 0.5, 0))
	body.joint_offset = body.body_offset.affine_inverse()
	body.joint_type = PhysicalBone3D.JOINT_TYPE_NONE if bone_name == "pelvis" else PhysicalBone3D.JOINT_TYPE_CONE
	if bone_name != "pelvis":
		# The seated hips/knees already bend about85degrees. A narrower cone
		# starts outside its limits and injects violent corrective energy at handoff.
		var leg := bone_name.begins_with("thigh") or bone_name.begins_with("shin")
		body.set("joint_constraints/swing_span", 120.0 if leg else (95.0 if bone_name.begins_with("upper_arm") else 45.0))
		body.set("joint_constraints/twist_span", 55.0 if leg else 35.0)
		body.set("joint_constraints/bias", 0.10)
		body.set("joint_constraints/softness", 0.60)
		body.set("joint_constraints/relaxation", 0.80)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(length, radius * 2.0)
	shape.margin = 0.002
	collision.shape = shape
	body.add_child(collision)
	_simulator.add_child(body)
	PhysicsServer3D.body_set_enable_continuous_collision_detection(body.get_rid(), true)
	_bodies.append(body)
	_body_bone_ids.append(id)
	_saved_body_transforms.append(Transform3D.IDENTITY)
	_saved_velocities.append(Vector3.ZERO)
	_frozen_poses.append(Transform3D.IDENTITY)

func set_appearance(appearance: Dictionary) -> void:
	if not rig_ready: return
	_appearance = Catalog.sanitize_appearance(appearance)
	var color := Catalog.color_for(str(appearance.get("color_id", "orange")))
	for material in _materials: material.albedo_color = color
	_hat_pirate.visible = str(appearance.get("hat_id", "none")) == "pirate"
	_hat_beanie.visible = str(appearance.get("hat_id", "none")) == "beanie"

func update_tool_transform(seat: Transform3D, delta: float, reset_motion := false) -> void:
	if not seat.origin.is_finite(): return
	var first := not _has_seat
	_seat = seat.orthonormalized()
	_has_seat = true
	var displacement := _seat.origin - _previous_seat
	displacement.y = 0.0
	if first or reset_motion or delta <= 0.0 or delta > 0.25 or displacement.length() > 2.8:
		_has_motion = false
		_strain = 0.0
		_tool_velocity = Vector3.ZERO
		_previous_velocity = Vector3.ZERO
	else:
		_tool_velocity = displacement / maxf(delta, 0.008)
		if active and state == State.RIDING and _cooldown <= 0.0 and _has_motion:
			var speed := _tool_velocity.length()
			var acceleration := (_tool_velocity - _previous_velocity).length() / maxf(delta, 0.008)
			if speed > fling_speed or (speed > 4.5 and acceleration > 80.0):
				_strain += delta * maxf(speed / fling_speed, acceleration / 100.0)
			else: _strain = maxf(0.0, _strain - delta * 3.0)
			if _strain >= fling_strain_seconds: _start_fall(_tool_velocity)
		_previous_velocity = _tool_velocity
		_has_motion = true
	_previous_seat = _seat.origin
	if first and rig_ready: reset_to_tool()

func set_active(enabled: bool) -> void:
	if not rig_ready or enabled == active: return
	active = enabled
	_has_motion = false
	_strain = 0.0
	if not enabled and state == State.FALLING:
		_capture_physics_pose()
		_stop_physics()
		_apply_frozen_pose(1.0)
		_suspended_fall = true
	elif enabled and _suspended_fall:
		_skeleton.clear_bones_global_pose_override()
		_simulator.active = true
		_simulator.physical_bones_start_simulation()
		for i in _bodies.size():
			_bodies[i].global_transform = _saved_body_transforms[i]
			_bodies[i].linear_velocity = _saved_velocities[i].limit_length(4.0)
			_bodies[i].angular_velocity = Vector3.ZERO
		_suspended_fall = false
	set_physics_process(enabled)

func reset_to_tool() -> void:
	if not rig_ready or not _has_seat: return
	_stop_physics()
	_skeleton.clear_bones_global_pose_override()
	_suspended_fall = false
	_recover_blend = 0.0
	_has_motion = false
	_strain = 0.0
	_cooldown = 1.6
	_set_state(State.RIDING)
	_play("ride", 0.12)
	_animation.advance(0.0)
	_place_on_seat()

func park_at(world_position: Vector3) -> void:
	if not rig_ready: return
	set_active(false)
	_stop_physics()
	_skeleton.clear_bones_global_pose_override()
	_suspended_fall = false
	_recover_blend = 0.0
	_set_state(State.PARKED)
	_rig.global_transform = Transform3D(Basis.IDENTITY, _bounded_ground(world_position))
	_play("idle", 0.0)
	_animation.advance(0.0)

func _place_on_seat() -> void:
	_rig.global_transform = Transform3D(_seat.basis, _seat.origin - Vector3.UP * (RIDE_PELVIS_Y * model_scale - 0.015))

func _start_fall(velocity: Vector3) -> void:
	if not rig_ready or state != State.RIDING: return
	falls += 1
	_set_state(State.FALLING)
	_settled_age = 0.0
	_animation.advance(0.0)
	_skeleton.force_update_all_bone_transforms()
	for i in _bodies.size():
		_saved_body_transforms[i] = _skeleton.global_transform * _skeleton.get_bone_global_pose(_body_bone_ids[i]) * _bodies[i].body_offset
	_simulator.active = true
	_simulator.physical_bones_start_simulation()
	var launch := velocity.limit_length(3.7) + Vector3.UP * 1.35
	for i in _bodies.size():
		var body := _bodies[i]
		body.global_transform = _saved_body_transforms[i]
		body.linear_velocity = launch
		body.angular_velocity = Vector3(3.0, 1.0, -1.5)

func _capture_physics_pose() -> void:
	var inverse := _skeleton.global_transform.affine_inverse()
	for i in _bodies.size():
		var transform := _bodies[i].global_transform
		if not transform.is_finite(): transform = _skeleton.global_transform * _skeleton.get_bone_global_rest(_body_bone_ids[i]) * _bodies[i].body_offset
		_saved_body_transforms[i] = transform
		_saved_velocities[i] = _bodies[i].linear_velocity if _bodies[i].linear_velocity.is_finite() else Vector3.ZERO
		_frozen_poses[i] = inverse * transform * _bodies[i].body_offset.affine_inverse()

func _apply_frozen_pose(weight: float) -> void:
	for i in _bodies.size(): _skeleton.set_bone_global_pose_override(_body_bone_ids[i], _frozen_poses[i], weight, true)

func _stop_physics() -> void:
	if _simulator == null: return
	_simulator.physical_bones_stop_simulation()
	_simulator.active = false
	for body in _bodies:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

func _recover() -> void:
	_capture_physics_pose()
	var position := _bodies[0].global_position
	var point := _bounded_ground(position if position.is_finite() else _seat.origin)
	# Capture the complete hierarchy before changing the standing root. Physical
	# bones supply world poses; children without physics retain their local pose.
	for bone in _skeleton.get_bone_count():
		_recovery_world_poses[bone] = _skeleton.global_transform * _skeleton.get_bone_global_pose(bone)
	for i in _bodies.size(): _recovery_world_poses[_body_bone_ids[i]] = _saved_body_transforms[i] * _bodies[i].body_offset.affine_inverse()
	for bone in _skeleton.get_bone_count():
		var parent := _skeleton.get_bone_parent(bone)
		if parent >= 0 and not _body_bone_ids.has(bone):
			_recovery_world_poses[bone] = _recovery_world_poses[parent] * _skeleton.get_bone_pose(bone)
	_stop_physics()
	_skeleton.clear_bones_global_pose_override()
	var direction := _seat.origin - point
	direction.y = 0.0
	var yaw := atan2(-direction.x, -direction.z) if direction.length_squared() > 0.0001 else 0.0
	_rig.global_transform = Transform3D(Basis(Vector3.UP, yaw), point)
	var inverse := _skeleton.global_transform.affine_inverse()
	for bone in _skeleton.get_bone_count():
		var parent := _skeleton.get_bone_parent(bone)
		var pose := inverse * _recovery_world_poses[bone] if parent < 0 else _recovery_world_poses[parent].affine_inverse() * _recovery_world_poses[bone]
		# Only the free pelvis can translate. Interpolate rotations in the local
		# hierarchy so independent ancestor overrides never stretch connected limbs.
		if _skeleton.get_bone_name(bone) == "root": pose = _skeleton.get_bone_rest(bone)
		elif _skeleton.get_bone_name(bone) == "pelvis": pose = inverse * _recovery_world_poses[bone]
		else: pose.origin = _skeleton.get_bone_rest(bone).origin
		pose.basis = pose.basis.orthonormalized()
		_recovery_local_poses[bone] = pose
	_recover_blend = 0.22
	_set_state(State.GETTING_UP)
	_play("get_up", 0.0)
	_animation.advance(0.0)
	_capture_animation_poses()
	_apply_recovery_pose(1.0)

func _capture_animation_poses() -> void:
	for bone in _skeleton.get_bone_count(): _animation_poses[bone] = _skeleton.get_bone_pose(bone)

func _apply_recovery_pose(weight: float) -> void:
	for bone in _skeleton.get_bone_count():
		_skeleton.set_bone_pose(bone, _animation_poses[bone].interpolate_with(_recovery_local_poses[bone], weight))

func _physics_process(delta: float) -> void:
	if not active or not rig_ready: return
	_age += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	match state:
		State.RIDING: _place_on_seat()
		State.FALLING:
			var unstable := false
			for body in _bodies:
				if not body.global_transform.is_finite() or not body.linear_velocity.is_finite(): unstable = true
				elif body.linear_velocity.length_squared() > 64.0: body.linear_velocity = body.linear_velocity.limit_length(8.0)
				if body.angular_velocity.length_squared() > 196.0: body.angular_velocity = body.angular_velocity.limit_length(14.0)
			var velocity := _bodies[0].linear_velocity.length()
			_settled_age = _settled_age + delta if _age > 0.5 and velocity < 0.35 else 0.0
			var point := _bodies[0].global_position
			if unstable or not point.is_finite() or point.y < floor_y - 0.2 or _age > MAX_RAGDOLL_SECONDS or _settled_age > 0.28: _recover()
		State.GETTING_UP:
			if _age >= _clip_length("get_up", 1.4):
				_set_state(State.DUSTING)
				_play("dust_off", 0.10)
		State.DUSTING:
			if _age >= _clip_length("dust_off", 1.0):
				_set_state(State.RUNNING)
				_play("run", 0.12)
		State.RUNNING: _run_toward_tool(delta)
		State.CLIMBING:
			var progress := clampf(_age / _clip_length("climb", 1.2), 0.0, 1.0)
			var destination := _seat.origin - Vector3.UP * (RIDE_PELVIS_Y * model_scale - 0.015)
			var point := _climb_start.lerp(destination, smoothstep(0.0, 1.0, progress))
			point.y += sin(progress * PI) * 0.07
			var rotation := _climb_rotation.slerp(_seat.basis.get_rotation_quaternion(), smoothstep(0.0, 0.5, progress))
			_rig.global_transform = Transform3D(Basis(rotation), point)
			if progress >= 1.0: reset_to_tool()
	_animation_elapsed += delta
	if _animation_elapsed + 0.000001 >= ANIMATION_STEP and state != State.FALLING:
		var step := floorf((_animation_elapsed + 0.000001) / ANIMATION_STEP) * ANIMATION_STEP
		_animation_elapsed = maxf(_animation_elapsed - step, 0.0)
		if _recover_blend > 0.0: _apply_recovery_pose(0.0)
		_animation.advance(step)
		if _recover_blend > 0.0: _capture_animation_poses()
	if _recover_blend > 0.0:
		_recover_blend = maxf(_recover_blend - delta, 0.0)
		_apply_recovery_pose(_recover_blend / 0.22)

func _run_toward_tool(delta: float) -> void:
	var goal := _bounded_ground(_seat.origin + _seat.basis.z * 0.20)
	var direction := goal - _rig.global_position
	direction.y = 0.0
	var distance := direction.length()
	if distance < 0.17 or _age > 12.0:
		_climb_start = _rig.global_position
		_climb_rotation = _rig.global_basis.get_rotation_quaternion()
		_set_state(State.CLIMBING)
		_play("climb", 0.10)
		return
	var speed := 1.65 if _age < 6.0 else 3.0
	_rig.global_position = _bounded_ground(_rig.global_position + direction.normalized() * minf(distance, speed * delta))
	var desired := Basis(Vector3.UP, atan2(-direction.x, -direction.z)).get_rotation_quaternion()
	var current := _rig.global_basis.orthonormalized().get_rotation_quaternion()
	_rig.global_basis = Basis(current.slerp(desired, minf(delta * 12.0, 1.0)))

func _bounded_ground(point: Vector3) -> Vector3:
	return Vector3(clampf(point.x, bounds.position.x, bounds.end.x), floor_y, clampf(point.z, bounds.position.y, bounds.end.y))

func _set_state(next: State) -> void:
	state = next
	_age = 0.0
	_animation_elapsed = 0.0
	state_changed.emit(state)

func _play(key: String, blend: float) -> void:
	_current_clip = key
	if _clips.has(key): _animation.play(_clips[key], blend)

func _clip_length(key: String, fallback: float) -> float:
	return _animation.get_animation(_clips[key]).length if _clips.has(key) else fallback

func debug_stats() -> Dictionary:
	var simulating := 0
	var max_bone_scale := 0.0
	for body in _bodies:
		if body.is_simulating_physics(): simulating += 1
	if _skeleton != null:
		for id in _skeleton.get_bone_count():
			var scale := _skeleton.get_bone_global_pose(id).basis.get_scale()
			max_bone_scale = maxf(max_bone_scale, maxf(scale.x, maxf(scale.y, scale.z)))
	return {"state": state, "state_name": State.keys()[state], "active": active,
		"rig_ready": rig_ready, "physical_body_count": _bodies.size(),
		"simulating_body_count": simulating, "falls": falls, "animation": _current_clip,
		"position": _rig.global_position if _rig != null else Vector3.ZERO,
		"walking_bounds": bounds, "physics_bounds": bounds.grow(PHYSICS_MARGIN),
		"rig_scale": _rig.global_basis.get_scale() if _rig != null else Vector3.ONE,
		"max_bone_scale": max_bone_scale,
		"appearance": _appearance.duplicate(), "hat_head_attached": _hat_pirate != null and _hat_pirate.get_parent() is BoneAttachment3D}

func _notification(what: int) -> void:
	if not is_node_ready(): return
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_PAUSED]: set_active(false)

func _exit_tree() -> void:
	_stop_physics()
