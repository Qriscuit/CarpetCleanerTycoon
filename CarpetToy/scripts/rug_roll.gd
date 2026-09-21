extends RefCounted
## Subdivide the authored rug once so its long faces can curl around a roll.
## The same meshes and materials then serve every job in this cleaning window.
const STRIP_WIDTH := 0.065
var materials: Array[ShaderMaterial] = []

func setup(carpet: Node3D) -> void:
	for node: MeshInstance3D in carpet.get_children():
		node.mesh = _subdivide(node.mesh)
		node.custom_aabb = AABB(Vector3(-2,-0.2,-4),Vector3(4,2,8))
		var material := node.material_override as ShaderMaterial
		material.set_shader_parameter("roll_enabled",true)
		material.set_shader_parameter("roll_mesh_offset",node.position)
		materials.append(material)

func set_roll(amount: float, direction: float = -1.0) -> void:
	for material in materials:
		material.set_shader_parameter("roll_amount",amount)
		material.set_shader_parameter("roll_direction",direction)

func _subdivide(source: Mesh) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count := indices.size() if not indices.is_empty() else vertices.size()
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		for triangle in range(0,count,3):
			var polygon: Array = []
			var min_z := INF
			var max_z := -INF
			for corner in 3:
				var index := indices[triangle+corner] if not indices.is_empty() else triangle+corner
				var p := vertices[index]
				polygon.append([p,normals[index],uvs[index] if not uvs.is_empty() else Vector2.ZERO])
				min_z = minf(min_z,p.z)
				max_z = maxf(max_z,p.z)
			for strip in range(floori(min_z/STRIP_WIDTH),floori(max_z/STRIP_WIDTH)+1):
				var clipped := _clip(_clip(polygon,strip*STRIP_WIDTH,true),(strip+1)*STRIP_WIDTH,false)
				for i in range(1,clipped.size()-1):
					for point: Array in [clipped[0],clipped[i],clipped[i+1]]:
						builder.set_normal(point[1].normalized())
						builder.set_uv(point[2])
						builder.add_vertex(point[0])
		builder.index()
		builder.set_material(source.surface_get_material(surface))
		builder.commit(result)
	return result

func _clip(polygon: Array, edge: float, above: bool) -> Array:
	var result: Array = []
	if polygon.is_empty(): return result
	var previous: Array = polygon.back()
	var was_inside: bool = previous[0].z >= edge if above else previous[0].z <= edge
	for point: Array in polygon:
		var inside: bool = point[0].z >= edge if above else point[0].z <= edge
		if inside != was_inside:
			var weight: float = (edge-previous[0].z)/(point[0].z-previous[0].z)
			result.append([previous[0].lerp(point[0],weight),previous[1].lerp(point[1],weight),previous[2].lerp(point[2],weight)])
		if inside: result.append(point)
		previous = point
		was_inside = inside
	return result
