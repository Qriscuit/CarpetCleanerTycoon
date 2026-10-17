extends RefCounted
## Deform the batched room surfaces while their authored supports stay fixed.
## The node transforms remain available to picking and the casement animation.

const SETTINGS := {
	"walls": {"group": "Walls", "kind": 0, "base": 0.15, "ramp": 0.35, "pivot": Vector3(0.0, 0.15, -2.86)},
	"window": {"group": "Window", "kind": 1, "base": 0.07, "ramp": 0.35, "pivot": Vector3(0.0, 0.07, -2.64)},
	"railings": {"group": "Railings", "kind": 2, "base": 0.0575, "ramp": 0.16, "pivot": Vector3(0.0, 0.0575, 0.0)},
}
const RAIL_SIDE_X := 2.17
const CULL_MARGIN := 0.20
const SHADER_CODE := """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 room_albedo : source_color;
uniform float room_metallic;
uniform float room_roughness;
uniform float room_specular;
uniform vec3 room_scale = vec3(1.0);
uniform mat4 room_mesh_to_tier;
uniform mat4 room_tier_to_mesh;
uniform int room_kind = 0;
uniform float room_fixed_height = 0.15;
uniform float room_ramp_height = 0.35;
uniform vec3 room_pivot = vec3(0.0, 0.15, -2.86);

void vertex() {
	vec3 point = (room_mesh_to_tier * vec4(VERTEX, 1.0)).xyz;
	// Keep the complete sill, foundation feet and rail foot bands authored.
	if (point.y > room_fixed_height) {
		float height = point.y - room_fixed_height;
		float u = clamp(height / room_ramp_height, 0.0, 1.0);
		float ramp = u * u * (3.0 - 2.0 * u);
		float ramp_derivative = 6.0 * u * (1.0 - u) / room_ramp_height;
		vec3 pivot = room_pivot;
		vec3 change = room_scale - vec3(1.0);
		if (room_kind == 2) {
			// Each bank breathes about its own side; its length never grows.
			pivot.x = sign(point.x) * 2.17;
			change.z = 0.0;
		}
		float weight = ramp;
		if (weight > 0.0) {
			float weight_y = ramp_derivative;
			vec3 displacement = (point - pivot) * change;
			// The derivative includes the rooted height ramp.
			// Its inverse transpose keeps sloping wall and rail highlights correct.
			mat3 jacobian = mat3(
				vec3(1.0 + change.x * weight, 0.0, 0.0),
				vec3(displacement.x * weight_y, 1.0 + change.y * weight + displacement.y * weight_y, displacement.z * weight_y),
				vec3(0.0, 0.0, 1.0 + change.z * weight)
			);
			mat3 mesh_to_tier = mat3(room_mesh_to_tier);
			mat3 tier_to_mesh = mat3(room_tier_to_mesh);
			vec3 tier_normal = transpose(tier_to_mesh) * NORMAL;
			tier_normal = transpose(inverse(jacobian)) * tier_normal;
			NORMAL = normalize(transpose(mesh_to_tier) * tier_normal);
			point += displacement * weight;
			VERTEX = (room_tier_to_mesh * vec4(point, 1.0)).xyz;
		}
	}
}

void fragment() {
	ALBEDO = room_albedo.rgb;
	METALLIC = room_metallic;
	ROUGHNESS = room_roughness;
	SPECULAR = room_specular;
}
"""

# Records retain the exact pre-animation overrides and culling allowance.
var parts: Dictionary = {}
var amounts: Dictionary = {}
var _parts_by_mesh: Dictionary = {}
var _room: Node3D
var _shader: Shader

func setup(room: Node3D) -> void:
	if _room == room and not parts.is_empty(): return
	for category: String in parts:
		restore(category)
	parts.clear()
	amounts.clear()
	_parts_by_mesh.clear()
	_room = room
	if _room == null: return
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	for category: String in SETTINGS:
		parts[category] = {}
		amounts[category] = {}
		var settings: Dictionary = SETTINGS[category]
		for tier: int in range(4):
			var model := _room.get_node_or_null("%s/Tier%d" % [settings.group, tier]) as Node3D
			if model == null: continue
			var tier_parts: Array[Dictionary] = []
			var paths: Array[String] = ["BakedModel"]
			if category == "window":
				paths.append("LeftHinge/BakedModel")
				paths.append("RightHinge/BakedModel")
			for path: String in paths:
				var mesh := model.get_node_or_null(path) as MeshInstance3D
				if mesh == null or mesh.mesh == null: continue
				var authored: Array[Material] = []
				var animated: Array[ShaderMaterial] = []
				for surface: int in mesh.mesh.get_surface_count():
					authored.append(mesh.get_surface_override_material(surface))
					animated.append(_make_material(mesh.get_active_material(surface), settings))
				var part := {
					"mesh": mesh, "tier_node": model, "category": category, "tier": tier,
					"authored": authored, "animated": animated,
					"cull_margin": mesh.extra_cull_margin,
					"mesh_to_tier": Transform3D.IDENTITY, "tier_to_mesh": Transform3D.IDENTITY,
				}
				_update_part_transform(part)
				tier_parts.append(part)
				_parts_by_mesh[mesh.get_instance_id()] = part
			parts[category][tier] = tier_parts
			amounts[category][tier] = Vector3.ONE

func _make_material(source: Material, settings: Dictionary) -> ShaderMaterial:
	if not source is StandardMaterial3D: return null
	var standard := source as StandardMaterial3D
	var material := ShaderMaterial.new()
	material.resource_local_to_scene = true
	material.shader = _shader
	material.set_shader_parameter("room_albedo", standard.albedo_color)
	material.set_shader_parameter("room_metallic", standard.metallic)
	material.set_shader_parameter("room_roughness", standard.roughness)
	material.set_shader_parameter("room_specular", standard.metallic_specular)
	material.set_shader_parameter("room_kind", int(settings.kind))
	material.set_shader_parameter("room_fixed_height", float(settings.base))
	material.set_shader_parameter("room_ramp_height", float(settings.ramp))
	material.set_shader_parameter("room_pivot", settings.pivot)
	return material

func _update_part_transform(part: Dictionary) -> void:
	var mesh: MeshInstance3D = part.mesh
	var model: Node3D = part.tier_node
	part.mesh_to_tier = model.global_transform.affine_inverse() * mesh.global_transform
	part.tier_to_mesh = (part.mesh_to_tier as Transform3D).affine_inverse()
	for material: ShaderMaterial in part.animated:
		if material == null: continue
		material.set_shader_parameter("room_mesh_to_tier", part.mesh_to_tier)
		material.set_shader_parameter("room_tier_to_mesh", part.tier_to_mesh)

func animate(category: String, tier: int, amount: Vector3) -> void:
	if not parts.has(category) or not parts[category].has(tier): return
	amounts[category][tier] = amount
	for part: Dictionary in parts[category][tier]:
		_update_part_transform(part)
		var mesh: MeshInstance3D = part.mesh
		mesh.extra_cull_margin = float(part.cull_margin) + CULL_MARGIN
		for surface: int in part.animated.size():
			var material: ShaderMaterial = part.animated[surface]
			if material == null: continue
			material.set_shader_parameter("room_scale", amount)
			mesh.set_surface_override_material(surface, material)

func restore(category: String) -> void:
	if not parts.has(category): return
	for tier: int in parts[category]:
		amounts[category][tier] = Vector3.ONE
		for part: Dictionary in parts[category][tier]:
			var mesh: MeshInstance3D = part.mesh
			if not is_instance_valid(mesh): continue
			mesh.extra_cull_margin = float(part.cull_margin)
			for surface: int in part.authored.size():
				mesh.set_surface_override_material(surface, part.authored[surface])
			for material: ShaderMaterial in part.animated:
				if material != null:
					material.set_shader_parameter("room_scale", Vector3.ONE)

func scale_for(category: String, tier: int) -> Vector3:
	if not amounts.has(category): return Vector3.ONE
	return amounts[category].get(tier, Vector3.ONE)

func deformed_vertex(mesh: MeshInstance3D, vertex: Vector3) -> Vector3:
	if mesh == null or not _parts_by_mesh.has(mesh.get_instance_id()): return vertex
	var part: Dictionary = _parts_by_mesh[mesh.get_instance_id()]
	var amount := scale_for(str(part.category), int(part.tier))
	if amount == Vector3.ONE: return vertex
	var point: Vector3 = (part.mesh_to_tier as Transform3D) * vertex
	var settings: Dictionary = SETTINGS[part.category]
	var base := float(settings.base)
	if point.y <= base: return vertex
	var height := point.y - base
	var weight := smoothstep(0.0, float(settings.ramp), height)
	var pivot: Vector3 = settings.pivot
	var change := amount - Vector3.ONE
	if part.category == "railings":
		pivot.x = signf(point.x) * RAIL_SIDE_X
		change.z = 0.0
	if weight <= 0.0: return vertex
	point += (point - pivot) * change * weight
	return (part.tier_to_mesh as Transform3D) * point
