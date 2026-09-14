extends SceneTree
## Offline scene authoring. Saves MultiMesh transforms; no runtime generation cost.
const OUTPUT := "res://scenes/"
const CLUMP_COUNT := 560

func own(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		# Keep authored scene instances and their %unique control ownership intact.
		if child.scene_file_path.is_empty():
			own(child, scene_root)

func save_scene(node: Node, path: String) -> void:
	own(node, node)
	var packed := PackedScene.new()
	assert(packed.pack(node) == OK)
	assert(ResourceSaver.save(packed, path) == OK)

func mesh_copy(path: String) -> Node3D:
	# Copy mesh references into plain nodes: avoid nested imported-scene overrides.
	var imported := (load(path) as PackedScene).instantiate()
	var result := Node3D.new()
	for original in imported.find_children("*", "MeshInstance3D", true, false):
		var copy := MeshInstance3D.new()
		copy.name = original.name
		copy.mesh = original.mesh
		var pose: Transform3D = original.transform
		var parent: Node = original.get_parent()
		while parent is Node3D:
			pose = parent.transform * pose
			parent = parent.get_parent()
		copy.transform = pose
		result.add_child(copy)
	imported.free()
	return result

func tiled_floor() -> Node3D:
	var floor_root := Node3D.new()
	floor_root.name = "WhiteTileFloor"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("f5f5f2")
	mat.roughness = 0.88
	mat.metallic_specular = 0.15
	mat.vertex_color_use_as_albedo = true
	# Keep the floor white under soft lighting without bleaching the toys.
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 0.45
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(mat)
	# One low-poly ceramic slab: real shallow bevels and a flat white top.
	var rings: Array[PackedVector3Array] = []
	for ring in [Vector2(0.313, -0.026), Vector2(0.313, -0.005), Vector2(0.308, 0.0)]:
		rings.append(PackedVector3Array([Vector3(-ring.x,ring.y,-ring.x),Vector3(ring.x,ring.y,-ring.x),Vector3(ring.x,ring.y,ring.x),Vector3(-ring.x,ring.y,ring.x)]))
	for level in 2:
		for side in 4:
			var next := (side + 1) % 4
			for point in [rings[level][side],rings[level+1][next],rings[level+1][side],rings[level][side],rings[level][next],rings[level+1][next]]:
				surface.add_vertex(point)
	for index in [0,1,2,0,2,3]:
		surface.add_vertex(rings[2][index])
	surface.generate_normals()
	var tiles := MultiMeshInstance3D.new()
	tiles.name = "CeramicTiles_576_Instances"
	tiles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = surface.commit()
	mm.instance_count = 24 * 24
	for row in 24:
		for column in 24:
			var index := row * 24 + column
			mm.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3((column-11.5)*0.64,0,(row-11.5)*0.64)))
			var tint := 1.0 - float((row * 7 + column * 3) % 5) * 0.006
			mm.set_instance_color(index, Color(tint,tint,tint,1.0))
	tiles.multimesh = mm
	floor_root.add_child(tiles)
	return floor_root

func _initialize() -> void:
	var soil := StandardMaterial3D.new()
	soil.resource_name = "Dry soil • opaque baked surface"
	soil.albedo_texture = load("res://assets/dirt/dry_soil_albedo.png")
	soil.normal_enabled = true
	soil.normal_texture = load("res://assets/dirt/dry_soil_normal.png")
	soil.normal_scale = 0.45
	soil.roughness = 1.0
	soil.metallic_specular = 0.12
	soil.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ResourceSaver.save(soil, "res://assets/dirt/dry_soil.tres")
	var edge := StandardMaterial3D.new()
	edge.resource_name = "Dust-covered binding and fringe"
	edge.albedo_color = Color("a28562")
	edge.roughness = 1.0
	edge.metallic_specular = 0.1
	ResourceSaver.save(edge, "res://assets/dirt/dust_edges.tres")
	var dirty := Node3D.new()
	dirty.name = "DirtyCarpet"
	var carpet := mesh_copy("res://assets/carpet/mint_meadow.glb")
	carpet.name = "CarpetMesh"
	dirty.add_child(carpet)
	# Material substitution covers the whole carpet without another overdraw layer.
	for mesh in carpet.find_children("*", "MeshInstance3D", true, false):
		var clean_material := mesh.mesh.surface_get_material(0) as StandardMaterial3D
		var dust := ShaderMaterial.new()
		dust.shader = load("res://scripts/soil_surface.gdshader")
		dust.set_shader_parameter("soil_map", soil.albedo_texture)
		dust.set_shader_parameter("clean_color", clean_material.albedo_color)
		if clean_material.albedo_texture:
			dust.set_shader_parameter("clean_map", clean_material.albedo_texture)
		mesh.material_override = dust
	var source := (load("res://assets/dirt/soil_clump.glb") as PackedScene).instantiate()
	var crumb_mesh := (source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var crumb_mat := StandardMaterial3D.new()
	crumb_mat.vertex_color_use_as_albedo = true
	crumb_mat.roughness = 1.0
	crumb_mat.metallic_specular = 0.05
	crumb_mesh.surface_set_material(0, crumb_mat)
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = crumb_mesh
	batch.instance_count = CLUMP_COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 421
	for i in batch.instance_count:
		# Independent positions create natural little clusters and gaps, with no grid.
		var position := Vector3(rng.randf_range(-0.89, 0.89), 0.067, rng.randf_range(-1.38, 1.38))
		var radius := rng.randf_range(0.022, 0.048)
		if rng.randf() < 0.045: radius = rng.randf_range(0.055, 0.068)
		# Squat, round and elongated silhouettes still share one cheap mesh batch.
		var shape := Vector3(rng.randf_range(0.72, 1.28), rng.randf_range(0.55, 1.25), rng.randf_range(0.72, 1.28)) * radius
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(shape)
		batch.set_instance_transform(i,Transform3D(basis,position))
		var shade := rng.randf_range(0.82,1.1)
		batch.set_instance_color(i,Color(0.63*shade,0.48*shade,0.33*shade,1))
	var crumbs := MultiMeshInstance3D.new()
	crumbs.name = "SoilClumps"
	crumbs.multimesh = batch
	crumbs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dirty.add_child(crumbs)
	save_scene(dirty,OUTPUT+"dirty_carpet.tscn")
	source.free()
	# Reuse the established lighting, but provide a taller work area for the tool row.
	var previous := (load(OUTPUT+"carpet_studio.tscn") as PackedScene).instantiate()
	var studio := Node3D.new()
	for child_name in ["WorldEnvironment","Ground","KeyLight","FillLight","Camera3D"]:
		var child := previous.get_node(child_name)
		child.owner = null
		previous.remove_child(child)
		studio.add_child(child)
	previous.free()
	var ground := studio.get_node("Ground") as MeshInstance3D
	ground.position.y = -0.029
	var grout := StandardMaterial3D.new()
	grout.albedo_color = Color("bdc4c2")
	grout.roughness = 1.0
	ground.material_override = grout
	var floor_root := tiled_floor()
	save_scene(floor_root, OUTPUT+"tiled_floor.tscn")
	studio.add_child(floor_root)
	studio.name = "RugCleaningGym"
	var subject := Node3D.new()
	subject.name = "RugDisplay"
	subject.position = Vector3.ZERO
	studio.add_child(subject)
	var clean := mesh_copy("res://assets/carpet/mint_meadow.glb")
	clean.name = "Clean"
	clean.visible = false
	subject.add_child(clean)
	dirty.name = "Dirty"
	subject.add_child(dirty)
	var rack := Node3D.new()
	rack.name = "StarterTools"
	studio.add_child(rack)
	for i in 3:
		var tool_name: String = ["large_brush","squeegee","jet_spray"][i]
		var tool := mesh_copy("res://assets/tools/"+tool_name+".glb")
		tool.name = ["LargeBrush","Squeegee","JetSpray"][i]
		if i<2:
			tool.position = Vector3(-0.85+i*0.85,0.18,1.28)
			tool.rotation.x = deg_to_rad(111)
			tool.scale = Vector3.ONE*0.77
		else:
			tool.position = Vector3(0.85,0.20,1.9)
			tool.rotation = Vector3(0,0,deg_to_rad(-75))
			tool.scale = Vector3.ONE*1.12
		if i == 0:
			tool.position = Vector3(-0.6, 0.0616, 0.65)
			tool.rotation = Vector3.ZERO
		tool.position.z += 0.52
		rack.add_child(tool)
	var camera := studio.get_node("Camera3D") as Camera3D
	camera.position = Vector3(0.65,8.0335,5.45)
	camera.look_at_from_position(camera.position,Vector3(0,0.0335,0))
	camera.size = 6.2
	studio.set_script(load("res://scripts/workshop.gd"))
	var hud := (load("res://scenes/ui/cleaning_hud.tscn") as PackedScene).instantiate()
	studio.add_child(hud)
	studio.set_editable_instance(hud, true)
	save_scene(studio,OUTPUT+"rug_cleaning_gym.tscn")
	print("WORKSHOP SAVED: white tiles, ", batch.instance_count, " batched soil clumps, light surface dust.")
	studio.free()
	quit.call_deferred()
