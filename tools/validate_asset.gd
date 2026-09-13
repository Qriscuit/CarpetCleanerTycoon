extends SceneTree

func _initialize() -> void:
	var packed := load("res://scenes/carpet.tscn") as PackedScene
	assert(packed != null, "Reusable carpet scene must load")
	var carpet := packed.instantiate()
	root.add_child(carpet)
	var meshes := carpet.find_children("*", "MeshInstance3D", true, false)
	assert(meshes.size() == 3, "Expected pile, binding and fringe")
	var triangle_count := 0
	var textured := 0
	for node in meshes:
		var mesh := (node as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(i)
			triangle_count += arrays[Mesh.ARRAY_INDEX].size() / 3
			assert(arrays[Mesh.ARRAY_TEX_UV].size() > 0, "UVs must survive export")
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			assert(mat != null, "GLB must carry standard materials")
			assert(mat.roughness > 0.8, "Carpet must remain matte")
			if mat.albedo_texture != null:
				textured += 1
				assert(mat.normal_enabled and mat.normal_texture != null)
	assert(textured == 1, "Pile needs albedo and woven normal")
	assert(triangle_count < 4000, "Simple asset geometry budget")
	print("ASSET VERIFIED: ", meshes.size(), " meshes, ", triangle_count, " triangles, packed albedo + normal, matte materials and UVs.")
	carpet.queue_free()
	quit()
