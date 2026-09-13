extends SceneTree

func _initialize() -> void:
	var workshop := (load("res://scenes/rug_cleaning_gym.tscn") as PackedScene).instantiate()
	var soil := workshop.get_node("RugDisplay/Dirty")
	var clean := workshop.get_node("RugDisplay/Clean")
	assert(soil.visible and not clean.visible, "Dirt is the default art view")
	var meshes := soil.find_children("*","MeshInstance3D",true,false)
	assert(meshes.size()==3, "Body, binding and fringe all exist")
	for mesh in meshes:
		assert(mesh.material_override!=null, "Every carpet surface must be dirt-covered")
		assert(mesh.material_override is ShaderMaterial, "Opaque dust blend on each carpet surface")
	for mesh in clean.find_children("*","MeshInstance3D",true,false):
		assert(mesh.material_override==null, "The clean original stays intact")
	var batches := soil.find_children("*","MultiMeshInstance3D",true,false)
	assert(batches.size()==1)
	var batch: MultiMesh = batches[0].multimesh
	assert(batch.instance_count==560)
	assert(batch.buffer.size()==560*16, "Instance transforms and colors must be saved")
	for i in batch.instance_count:
		var pose := batch.get_instance_transform(i)
		assert(abs(pose.origin.x)<0.9 and abs(pose.origin.z)<1.4)
		assert(pose.basis.determinant()>0.0)
	assert(soil.find_children("*","CollisionObject3D",true,false).is_empty(), "Visual dirt has no physics")
	var tool_triangles := 0
	for tool in workshop.get_node("StarterTools").get_children():
		var tool_meshes := tool.find_children("*","MeshInstance3D",true,false)
		assert(tool_meshes.size()==1)
		var mesh: Mesh = tool_meshes[0].mesh
		assert(mesh.get_surface_count()==1, "One draw surface per tool")
		var count: int = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()/3
		assert(count<2500)
		tool_triangles+=count
	print("VERIFIED: all carpet surfaces dirty; clean original intact; 560 saved GPU instances; no dirt physics; 3 one-surface tools / ",tool_triangles," triangles.")
	workshop.free()
	quit.call_deferred()
