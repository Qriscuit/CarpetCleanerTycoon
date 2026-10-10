extends SceneTree
## Rebuild the editable, lightweight room asset library with the pinned engine.
## Run with the graphical renderer: the headless dummy renderer cannot persist MultiMesh buffers.
## tools/run_godot.ps1 --path CarpetToy --script ../tools/generate_room_upgrades.gd -- --shop-test

var materials: Dictionary = {}
var scene_root: Node3D
var foliage_shader: Shader

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test while rebuilding assets")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Room assets require the graphical renderer to serialize their batched terrazzo inlays.")
		quit(1)
		return
	if "--window-only" in OS.get_cmdline_user_args():
		_rebuild_window_only()
		return
	scene_root = Node3D.new()
	scene_root.name = "UpgradeRoom"
	var structure := _group(scene_root, "Structure")
	_box(structure, "Foundation", Vector3(4.56, 0.18, 5.86), Vector3(0, -0.12, 0), "667872")
	_box(structure, "IvoryEdge", Vector3(4.55, 0.055, 5.85), Vector3(0, -0.028, 0), "efe9d9")
	_box(structure, "BackSkirting", Vector3(4.5, 0.13, 0.08), Vector3(0, 0.065, -2.86), "b6c6bb")
	# The new cutaway walls get a slim foundation ledge outside the existing
	# garden and railings. The working floor and its front edge stay unchanged.
	_box(structure, "RearWallFooting", Vector3(4.98, 0.18, 0.26), Vector3(0, -0.12, -2.86), "667872")
	_box(structure, "RightWallFooting", Vector3(0.27, 0.18, 2.87), Vector3(2.355, -0.12, -1.425), "667872")
	_box(structure, "RightFootingIvoryLip", Vector3(0.28, 0.045, 2.86), Vector3(2.355, -0.028, -1.425), "efe9d9")
	for category: String in ["Floor", "Plants", "Window", "Railings", "Walls"]:
		var category_root := _group(scene_root, category)
		for level: int in range(4):
			var tier := _group(category_root, "Tier%d" % level)
			tier.visible = level == 0
			match category:
				"Floor": _floor(tier, level)
				"Plants": _plants(tier, level)
				"Window": _window(tier, level)
				"Railings": _railings(tier, level)
				"Walls": _walls(tier, level)
			_bake_tier(tier)
	scene_root.set_script(load("res://scripts/room_upgrade_visuals.gd"))
	_save_room()

func _rebuild_window_only() -> void:
	# Keep the saved floor, garden, railings and walls intact when correcting
	# casement construction. This also retains their authored material resources.
	scene_root = load("res://scenes/room/upgrade_room.tscn").instantiate()
	var old_window: Node3D = scene_root.get_node("Window")
	var category_index := old_window.get_index()
	old_window.free()
	var category_root := _group(scene_root, "Window")
	scene_root.move_child(category_root, category_index)
	for level: int in range(4):
		var tier := _group(category_root, "Tier%d" % level)
		tier.visible = level == 0
		_window(tier, level)
		_bake_tier(tier)
	_save_room()

func _save_room() -> void:
	_assign_owner(scene_root)
	var packed := PackedScene.new()
	var error := packed.pack(scene_root)
	if error != OK:
		push_error("Could not pack room assets: %s" % error)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://scenes/room")
	error = ResourceSaver.save(packed, "res://scenes/room/upgrade_room.tscn")
	print("Editable room asset library saved: ", error_string(error))
	scene_root.free()
	quit(0 if error == OK else 1)

func _group(parent: Node, label: String) -> Node3D:
	var node := Node3D.new()
	node.name = label
	parent.add_child(node)
	return node

func _assign_owner(parent: Node) -> void:
	for child: Node in parent.get_children():
		child.owner = scene_root
		_assign_owner(child)

func _bake_tier(tier: Node3D) -> void:
	# Preserve every named primitive for editing, then merge the visible geometry
	# by material. Even the flower tier renders in a handful of draw calls.
	var batches: Dictionary = {}
	var originals: Array[Node] = []
	for child: Node3D in tier.get_children():
		# Hinged leaves and flexible foliage stay independent of their fixed frame/pots.
		if child.get_meta("runtime_part", false):
			continue
		originals.append(child)
		_collect_meshes(child, Transform3D.IDENTITY, batches)
	var source := Node3D.new()
	source.name = "EditableSource"
	source.visible = false
	source.set_meta("editor_note", "Named construction meshes. Regenerate or rebake after editing; BakedModel is the rendered version.")
	tier.add_child(source)
	for child: Node in originals:
		tier.remove_child(child)
		source.add_child(child)
	var baked := ArrayMesh.new()
	for material: Material in batches:
		var surface: SurfaceTool = batches[material]
		surface.set_material(material)
		surface.commit(baked)
	var visible_model := MeshInstance3D.new()
	visible_model.name = "BakedModel"
	visible_model.mesh = baked
	tier.add_child(visible_model)

func _apply_foliage_materials(node: Node3D, soil_height: float) -> void:
	if node is MeshInstance3D:
		var source := node.material_override as StandardMaterial3D
		var key := "breeze:%s:%s" % [source.albedo_color.to_html(), soil_height]
		if not materials.has(key):
			if foliage_shader == null:
				foliage_shader = Shader.new()
				foliage_shader.code = """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 leaf_color : source_color = vec4(0.5, 0.65, 0.4, 1.0);
uniform float soil_height = 0.3;
uniform float breeze_time = 0.0;
uniform float breeze_strength = 0.0;
void vertex() {
	float stem_height = max(VERTEX.y - soil_height, 0.0);
	float phase = sign(VERTEX.x) * 0.71 + sign(VERTEX.z) * 1.17;
	float wave = sin(breeze_time * 2.8 + phase) * 0.75 + sin(breeze_time * 4.1 + phase) * 0.25;
	float bend = wave * breeze_strength * 0.62;
	float cross_bend = sin(breeze_time * 2.25 + phase + 0.8) * breeze_strength * 0.20;
	VERTEX.x += bend * stem_height * stem_height;
	VERTEX.z += cross_bend * stem_height * stem_height;
	NORMAL = normalize(vec3(NORMAL.x, NORMAL.y - 2.0 * stem_height * (bend * NORMAL.x + cross_bend * NORMAL.z), NORMAL.z));
}
void fragment() {
	ALBEDO = leaf_color.rgb;
	ROUGHNESS = 0.83;
	SPECULAR = 0.32;
}
"""
			var flexible := ShaderMaterial.new()
			flexible.resource_local_to_scene = true
			flexible.resource_name = "FlexibleFoliage_" + source.albedo_color.to_html()
			flexible.shader = foliage_shader
			flexible.set_shader_parameter("leaf_color", source.albedo_color)
			flexible.set_shader_parameter("soil_height", soil_height)
			materials[key] = flexible
		node.material_override = materials[key]
	for child: Node3D in node.get_children():
		_apply_foliage_materials(child, soil_height)

func _collect_meshes(node: Node3D, parent_transform: Transform3D, batches: Dictionary) -> void:
	var transform := parent_transform * node.transform
	if node is MeshInstance3D:
		_append_mesh(node.mesh, transform, node.material_override, batches)
	elif node is MultiMeshInstance3D:
		for index: int in node.multimesh.instance_count:
			_append_mesh(node.multimesh.mesh, transform * node.multimesh.get_instance_transform(index), null, batches)
	for child: Node3D in node.get_children():
		_collect_meshes(child, transform, batches)

func _append_mesh(mesh: Mesh, transform: Transform3D, override: Material, batches: Dictionary) -> void:
	for index: int in mesh.get_surface_count():
		var material: Material = override if override != null else mesh.surface_get_material(index)
		if not batches.has(material):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[material] = surface
		(batches[material] as SurfaceTool).append_from(mesh, index, transform)

func _material(color: String, metallic := 0.0, roughness := 0.83) -> StandardMaterial3D:
	var key := "%s:%s:%s" % [color, metallic, roughness]
	if materials.has(key):
		return materials[key]
	var mat := StandardMaterial3D.new()
	mat.resource_name = color
	mat.albedo_color = Color(color)
	mat.metallic = metallic
	mat.roughness = roughness
	mat.metallic_specular = 0.32
	materials[key] = mat
	return mat

func _mesh(parent: Node3D, label: String, mesh: Mesh, position: Vector3, color: String, metallic := 0.0) -> MeshInstance3D:
	var model := MeshInstance3D.new()
	model.name = label
	model.mesh = mesh
	model.material_override = _material(color, metallic)
	model.position = position
	parent.add_child(model)
	return model

func _box(parent: Node3D, label: String, size: Vector3, position: Vector3, color: String, metallic := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, label, mesh, position, color, metallic)

func _cylinder(parent: Node3D, label: String, radius: float, height: float, position: Vector3, color: String, top_scale := 1.0, metallic := 0.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius * top_scale
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
	return _mesh(parent, label, mesh, position, color, metallic)

func _ellipsoid(parent: Node3D, label: String, size: Vector3, position: Vector3, color: String) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var model := _mesh(parent, label, mesh, position, color)
	model.scale = size
	return model

func _torus(parent: Node3D, label: String, inside: float, outside: float, position: Vector3, color: String, metallic := 0.0) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inside
	mesh.outer_radius = outside
	mesh.rings = 20
	mesh.ring_segments = 6
	return _mesh(parent, label, mesh, position, color, metallic)

func _beam(parent: Node3D, label: String, start: Vector3, end: Vector3, width: float, color: String, metallic := 0.0) -> MeshInstance3D:
	var beam := _cylinder(parent, label, width, start.distance_to(end), (start + end) * 0.5, color, 1.0, metallic)
	var direction := (end - start).normalized()
	var axis := Vector3.UP.cross(direction)
	if axis.length_squared() > 0.000001:
		beam.quaternion = Quaternion(axis.normalized(), acos(clampf(Vector3.UP.dot(direction), -1.0, 1.0)))
	return beam

func _floor(tier: Node3D, level: int) -> void:
	if level == 0:
		_box(tier, "ConcreteGrout", Vector3(4.5, 0.02, 5.8), Vector3(0, -0.012, 0), "929d96")
		for x: int in range(3):
			for z: int in range(4):
				var tone: String = ["b9bdb3", "b4b8ae", "bfc1b8"][(x + z * 2) % 3]
				_box(tier, "ConcreteSlab_%d_%d" % [x, z], Vector3(1.488, 0.015, 1.438), Vector3(-1.5 + x * 1.5, -0.004, -2.175 + z * 1.45), tone)
	elif level == 1:
		_box(tier, "MapleUnderlay", Vector3(4.5, 0.02, 5.8), Vector3(0, -0.012, 0), "a98f6c")
		for x: int in range(10):
			for z: int in range(5):
				var tone: String = ["d5ba8f", "e0c89f", "dac296", "cdb387"][(x * 3 + z * 7) % 4]
				_box(tier, "MapleBoard_%d_%d" % [x, z], Vector3(0.438, 0.015, 1.148), Vector3(-2.025 + x * 0.45, -0.004, -2.32 + z * 1.16), tone)
		_border(tier, "MapleEdge", 4.29, 5.59, 0.032, "f0d7ae")
	elif level == 2:
		_box(tier, "TileGrout", Vector3(4.5, 0.02, 5.8), Vector3(0, -0.012, 0), "c4d1c2")
		for x: int in range(6):
			for z: int in range(8):
				_box(tier, "GlazedTile_%d_%d" % [x, z], Vector3(0.738, 0.015, 0.713), Vector3(-1.875 + x * 0.75, -0.004, -2.5375 + z * 0.725), "c4dacb" if (x + z) % 2 == 0 else "f0eadb")
		_border(tier, "CeramicEdge", 4.33, 5.63, 0.045, "faf2df")
	else:
		_box(tier, "PearlTerrazzo", Vector3(4.5, 0.028, 5.8), Vector3(0, -0.010, 0), "e7e7d7")
		_border(tier, "BrassBorder", 4.13, 5.43, 0.025, "c6a664", 0.45)
		_border(tier, "WorkAreaInset", 3.44, 4.58, 0.012, "b5caba")
		var random := RandomNumberGenerator.new()
		random.seed = 43093
		var chips: Array[Transform3D] = []
		var rose_chips: Array[Transform3D] = []
		for i: int in range(240):
			var position := Vector3(random.randf_range(-2.16, 2.16), 0.006, random.randf_range(-2.81, 2.81))
			if absf(position.x) < 1.52 and absf(position.z) < 2.12:
				continue
			var chip_scale := Vector3(random.randf_range(0.012, 0.03), 0.001, random.randf_range(0.009, 0.023))
			var transform := Transform3D(Basis(Vector3.UP, random.randf() * TAU).scaled(chip_scale), position)
			if i % 3 == 0: rose_chips.append(transform)
			else: chips.append(transform)
		_chips(tier, "SageTerrazzoChips", chips, "a8c0ae")
		_chips(tier, "RoseTerrazzoChips", rose_chips, "cfaa94")

func _border(parent: Node3D, label: String, width: float, depth: float, thickness: float, color: String, metallic := 0.0) -> void:
	for side: float in [-1.0, 1.0]:
		_box(parent, label + "Side", Vector3(thickness, 0.008, depth), Vector3(side * width * 0.5, 0.006, 0), color, metallic)
		_box(parent, label + "End", Vector3(width, 0.008, thickness), Vector3(0, 0.006, side * depth * 0.5), color, metallic)

func _chips(parent: Node3D, label: String, transforms: Array[Transform3D], color: String) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 3
	mesh.material = _material(color)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index: int in transforms.size(): multimesh.set_instance_transform(index, transforms[index])
	var model := MultiMeshInstance3D.new()
	model.name = label
	model.multimesh = multimesh
	parent.add_child(model)

func _plants(tier: Node3D, level: int) -> void:
	var foliage: Node3D
	if level > 0:
		foliage = _group(tier, "Foliage")
		foliage.set_meta("runtime_part", true)
		foliage.set_meta("editor_note", "Batched flexible stems, leaves, buds and petals. Soil-height anchored vertex bending keeps the pots still.")
	for side: float in [-1.0, 1.0]:
		for end: float in [-1.0, 1.0]:
			var plant := _group(tier, "Planter_%s_%s" % [str(side), str(end)])
			plant.position = Vector3(side * 1.94, 0.0, end * 2.42)
			var pot_color: String = ["b7866c", "b77e62", "e8ddc6", "dfb6a2"][level]
			var radius := 0.145 + float(level) * 0.018
			var height := 0.23 + float(level) * 0.025
			_cylinder(plant, "Saucer", radius * 1.28, 0.028, Vector3(0, 0.018, 0), "80785e" if level == 0 else "c2ae8b")
			_cylinder(plant, "Pot", radius * 0.78, height, Vector3(0, height * 0.5 + 0.025, 0), pot_color, 1.26)
			_torus(plant, "RoundedRim", radius * 0.91, radius * 1.08, Vector3(0, height + 0.02, 0), pot_color)
			_cylinder(plant, "Soil", radius * 0.90, 0.012, Vector3(0, height + 0.021, 0), "675c46")
			if level == 0:
				for seed: int in range(3):
					_ellipsoid(plant, "Seed", Vector3(0.028, 0.013, 0.022), Vector3(-0.055 + seed * 0.053, height + 0.033, 0.018), "a39b76")
				continue
			if level == 3:
				_torus(plant, "BrassPotBand", radius * 0.86, radius * 0.91, Vector3(0, height * 0.56, 0), "bd9653", 0.45)
			var growth := _group(foliage, "Growth_%s_%s" % [str(side), str(end)])
			growth.position = plant.position
			var stem_height := 0.13 + level * 0.065
			_cylinder(growth, "MainStem", 0.014, stem_height, Vector3(0, height + stem_height * 0.5, 0), "62855b")
			var leaf_count := 2 if level == 1 else 6
			for leaf: int in range(leaf_count):
				var angle := float(leaf) / float(leaf_count) * TAU + side * 0.45
				var leaf_center := Vector3(cos(angle) * 0.083, height + 0.075 + float(leaf % 3) * 0.045, sin(angle) * 0.083)
				var model := _ellipsoid(growth, "Leaf", Vector3(0.12, 0.028, 0.055), leaf_center, "799568" if leaf % 2 else "a0b77d")
				model.rotation = Vector3(0.2, -angle, 0.4)
			if level >= 2:
				for branch: int in range(3):
					var angle := float(branch) / 3.0 * TAU + 0.5
					var tip := Vector3(cos(angle) * 0.105, height + stem_height + 0.04 + branch * 0.017, sin(angle) * 0.105)
					_beam(growth, "FlowerStem", Vector3(0, height + 0.045, 0), tip, 0.010, "66875c")
					if level == 2:
						_ellipsoid(growth, "LeafBud", Vector3(0.045, 0.065, 0.042), tip, "afbc77")
					else:
						_flower(growth, tip, "e8927e" if branch % 2 else "efb28d")
	if foliage != null:
		_apply_foliage_materials(foliage, 0.23 + float(level) * 0.025 + 0.021)
		_bake_tier(foliage)

func _flower(parent: Node3D, center: Vector3, color: String) -> void:
	for petal: int in range(6):
		var angle := float(petal) / 6.0 * TAU
		var petal_center := center + Vector3(cos(angle) * 0.061, 0, sin(angle) * 0.061)
		var mesh := _ellipsoid(parent, "Petal", Vector3(0.064, 0.026, 0.040), petal_center, color)
		mesh.rotation.y = -angle
	_ellipsoid(parent, "GoldenFlowerHeart", Vector3(0.037, 0.032, 0.037), center + Vector3(0, 0.02, 0), "e0b85c")

func _window(tier: Node3D, level: int) -> void:
	var panel := _group(tier, "WindowFrame")
	panel.position = Vector3(0, 0.11, -2.64)
	# The fixed frame and both side hinges stand upright. A vertical hinge
	# keeps each complete edge attached while the casement swings outward.
	var frame_color: String = ["b49a7b", "bed8c9", "f0ead9", "d6b56c"][level]
	var pane_color: String = ["bac9c3", "b5d7d2", "9cc9c7", "99cdc9"][level]
	# The base tier is already wider than the actual two-metre rug. Upgrades
	# improve the casement detail without shrinking its unobstructed passage.
	var width := 3.16
	var height := 1.22
	tier.set_meta("clear_opening_width", width)
	tier.set_meta("clear_opening_bottom", 0.13)
	tier.set_meta("clear_opening_top", 1.23)
	tier.set_meta("opening_plane_z", panel.position.z)
	for side: float in [-1.0, 1.0]:
		_box(panel, "FrameStile", Vector3(0.083, height + 0.14, 0.088), Vector3(side * (width * 0.5 + 0.045), height * 0.5, 0.0), frame_color, 0.4 if level == 3 else 0.0)
		_box(panel, "FrameRail", Vector3(width + 0.17, 0.078, 0.09), Vector3(0, (height + 0.045) if side > 0 else -0.045, 0.0), frame_color, 0.4 if level == 3 else 0.0)
	_box(panel, "WindowSill", Vector3(width + 0.28, 0.060, 0.18), Vector3(0, -0.07, 0.025), "e4d9be" if level < 3 else "f4ead2")
	# Both the pane and every decorative bar belong to a moving hinge. There
	# is deliberately no fixed centre mullion or opaque backing across the exit.
	for side: float in [-1.0, 1.0]:
		var hinge := _group(tier, "LeftHinge" if side < 0 else "RightHinge")
		hinge.transform = panel.transform * Transform3D(Basis.IDENTITY, Vector3(side * width * 0.5, 0, 0.025))
		hinge.set_meta("runtime_part", true)
		hinge.set_meta("hinge_side", side)
		hinge.set_meta("closed_basis", hinge.basis)
		var leaf_width := width * 0.5 - 0.008
		var center_x := -side * leaf_width * 0.5
		_box(hinge, "OpaqueSkyGlass", Vector3(leaf_width - 0.055, height - 0.065, 0.026), Vector3(center_x, height * 0.5, 0), pane_color)
		for leaf_edge: float in [0.0, 1.0]:
			_box(hinge, "MovingStile", Vector3(0.046, height, 0.058), Vector3(-side * leaf_width * leaf_edge, height * 0.5, 0.012), frame_color, 0.4 if level == 3 else 0.0)
			_box(hinge, "MovingRail", Vector3(leaf_width, 0.046, 0.058), Vector3(center_x, leaf_edge * height, 0.012), frame_color, 0.4 if level == 3 else 0.0)
		if level >= 1:
			_box(hinge, "MovingCrossMullion", Vector3(leaf_width, 0.042, 0.046), Vector3(center_x, height * 0.54, 0.025), frame_color)
			var shine := _box(hinge, "GlassReflection", Vector3(0.19, height * 0.69, 0.008), Vector3(center_x, height * 0.51, 0.018), "d8e9df")
			shine.rotation.z = -0.32
		if level >= 2:
			_cylinder(hinge, "WindowLatch", 0.030, 0.028, Vector3(-side * (leaf_width - 0.105), height * 0.31, 0.058), "bc9c58", 1.0, 0.5).rotation_degrees.x = 90.0
		if level == 3:
			_box(hinge, "MovingFineMullion", Vector3(0.028, height, 0.038), Vector3(center_x, height * 0.5, 0.033), "d6b56c", 0.4)
		_bake_tier(hinge)
	if level >= 2:
		for index: int in range(14):
			var angle_a := PI * float(index) / 14.0
			var angle_b := PI * float(index + 1) / 14.0
			var point_a := Vector3(cos(angle_a) * (width * 0.5 + 0.09), height + 0.047 + sin(angle_a) * 0.12, 0.04)
			var point_b := Vector3(cos(angle_b) * (width * 0.5 + 0.09), height + 0.047 + sin(angle_b) * 0.12, 0.04)
			_beam(panel, "ArchedHeader", point_a, point_b, 0.036, frame_color, 0.4 if level == 3 else 0.0)
	if level == 3:
		var emblem := _torus(panel, "SunMedallion", 0.047, 0.070, Vector3(0, height + 0.13, 0.06), "e5c681", 0.4)
		emblem.rotation_degrees.x = 90.0

func _railings(tier: Node3D, level: int) -> void:
	var rail_color: String = ["b1a183", "8aac96", "e4e5d6", "eadfc5"][level]
	var post_color: String = ["9b8a6d", "7a9f87", "d2d9c6", "c2a066"][level]
	var height := 0.18 + float(level) * 0.062
	for side: float in [-1.0, 1.0]:
		var railing := _group(tier, "LeftRailing" if side < 0 else "RightRailing")
		railing.position.x = side * 2.17
		_box(railing, "FootRail", Vector3(0.13, 0.055, 3.43), Vector3(0, 0.03, 0), post_color)
		_box(railing, "HandRail", Vector3(0.14, 0.065, 3.50), Vector3(0, height, 0), rail_color)
		var count := 4 if level == 0 else (7 if level == 1 else 11)
		for index: int in range(count):
			var z := lerpf(-1.67, 1.67, float(index) / float(count - 1))
			if level < 2:
				_box(railing, "TimberPost", Vector3(0.065, height, 0.065), Vector3(0, height * 0.5, z), post_color)
			else:
				_cylinder(railing, "TurnedBaluster", 0.025, height, Vector3(0, height * 0.5, z), post_color, 0.85, 0.35 if level == 3 else 0.0)
				_ellipsoid(railing, "BalusterKnuckle", Vector3(0.035, 0.050, 0.035), Vector3(0, height * 0.45, z), post_color)
		for end: float in [-1.0, 1.0]:
			_cylinder(railing, "NewelPost", 0.061, height + 0.065, Vector3(0, (height + 0.065) * 0.5, end * 1.71), post_color, 1.0, 0.4 if level == 3 else 0.0)
			_ellipsoid(railing, "RoundedFinial", Vector3(0.069, 0.038, 0.069), Vector3(0, height + 0.09, end * 1.71), rail_color)
		if level == 3:
			_box(railing, "BrassHandrailInlay", Vector3(0.025, 0.01, 3.42), Vector3(0, height + 0.038, 0), "bb9953", 0.6)

func _walls(tier: Node3D, level: int) -> void:
	# A high, wide U-shaped rear wall supports the existing window without
	# crossing the rolled carpet's passage or the outward casements' swing.
	# A short return and shallow outward-open door leave the front open.
	var finish: String = ["b8c2b8", "c6ddcd", "e6e7d9", "f1ecdc"][level]
	var trim: String = ["d6d9cb", "f2eddd", "d6dece", "d6b56c"][level]
	var trim_metallic := 0.4 if level == 3 else 0.0
	var door_color: String = ["98b2a4", "85b99e", "a8c9bc", "c0d8c9"][level]
	var height := 1.62
	tier.set_meta("clear_exit_width", 3.06)
	tier.set_meta("clear_exit_bottom", 0.13)
	tier.set_meta("clear_exit_top", 1.23)
	tier.set_meta("rear_opening_width", 4.12)
	tier.set_meta("rear_opening_top", 1.46)
	tier.set_meta("front_open", true)
	tier.set_meta("wall_height", height)
	tier.set_meta("door_open_degrees", 12.0)
	for side: float in [-1.0, 1.0]:
		var jamb := _group(tier, "RearLeftWall" if side < 0 else "RearRightWall")
		jamb.position = Vector3(side * 2.225, 0, -2.86)
		_box(jamb, "PlasterPier", Vector3(0.33, height, 0.14), Vector3(0, height * 0.5, 0), finish)
		_box(jamb, "CornerCap", Vector3(0.35, 0.045, 0.18), Vector3(0, height + 0.01, 0), trim, trim_metallic)
		# These low feet reach the sill only outside the narrow rolling corridor.
		_box(tier, "WindowSupportFoot", Vector3(0.70, 0.15, 0.18), Vector3(side * 2.04, 0.075, -2.75), finish)
		if level >= 1:
			_box(jamb, "WainscotPanel", Vector3(0.28, 0.56, 0.028), Vector3(0, 0.31, 0.084), "eee8d7")
			_box(jamb, "WainscotCap", Vector3(0.34, 0.036, 0.045), Vector3(0, 0.61, 0.09), trim, trim_metallic)
		if level >= 2:
			for course: int in range(5):
				_box(jamb, "StoneCourse", Vector3(0.29, 0.16, 0.016), Vector3(0, 0.74 + course * 0.18, 0.08), "d1ddd3" if course % 2 == 0 else "eaf0e4")
		if level == 3:
			for edge: float in [-1.0, 1.0]:
				_box(jamb, "BrassPierInlay", Vector3(0.012, 1.48, 0.018), Vector3(edge * 0.117, 0.81, 0.096), "bc9c58", 0.5)
	_box(tier, "RearLintel", Vector3(4.78, 0.16, 0.14), Vector3(0, 1.54, -2.86), finish)
	_box(tier, "RearCornice", Vector3(4.82, 0.047, 0.19), Vector3(0, 1.645, -2.86), trim, trim_metallic)
	if level >= 1:
		_box(tier, "RearPictureRail", Vector3(4.75, 0.026, 0.026), Vector3(0, 1.48, -2.776), trim, trim_metallic)
	if level == 3:
		_box(tier, "BrassLintelInlay", Vector3(4.66, 0.018, 0.015), Vector3(0, 1.568, -2.778), "bc9c58", 0.5)
	var return_wall := _group(tier, "RightReturnWall")
	return_wall.position.x = 2.37
	_box(return_wall, "RearReturnPlaster", Vector3(0.14, 1.46, 1.63), Vector3(0, 0.73, -2.045), finish)
	_box(return_wall, "FrontReturnPier", Vector3(0.14, 1.46, 0.30), Vector3(0, 0.73, -0.20), finish)
	_box(return_wall, "DoorLintel", Vector3(0.14, 0.16, 0.90), Vector3(0, 1.38, -0.79), finish)
	_box(return_wall, "ReturnCornice", Vector3(0.18, 0.048, 2.86), Vector3(0, 1.483, -1.43), trim, trim_metallic)
	for edge_z: float in [-1.245, -0.335]:
		_box(tier, "DoorCasing", Vector3(0.10, 1.33, 0.070), Vector3(2.30, 0.665, edge_z), trim, trim_metallic)
	_box(tier, "DoorCasingHeader", Vector3(0.10, 0.070, 0.98), Vector3(2.30, 1.32, -0.79), trim, trim_metallic)
	if level >= 1:
		for segment: Vector2 in [Vector2(-2.045, 1.53), Vector2(-0.20, 0.23)]:
			_box(return_wall, "ReturnWainscot", Vector3(0.025, 0.52, segment.y), Vector3(-0.083, 0.29, segment.x), "eee8d7")
			_box(return_wall, "ReturnChairRail", Vector3(0.036, 0.034, segment.y), Vector3(-0.088, 0.58, segment.x), trim, trim_metallic)
	if level >= 2:
		for course: int in range(4):
			_box(return_wall, "ReturnTileCourse", Vector3(0.017, 0.16, 1.50), Vector3(-0.08, 0.74 + course * 0.18, -2.045), "d1ddd3" if course % 2 == 0 else "eaf0e4")
	if level == 3:
		_box(return_wall, "ReturnBrassInlay", Vector3(0.020, 0.018, 2.80), Vector3(-0.10, 1.43, -1.43), "bc9c58", 0.5)
	var door := _group(tier, "SideDoorLeaf")
	door.position = Vector3(2.305, 0.045, -1.22)
	door.rotation_degrees.y = -78.0
	door.set_meta("editor_note", "Shallow outward-ajar door; no leaf or casing crosses the existing railing or garden.")
	_box(door, "MintDoorPanel", Vector3(0.82, 1.22, 0.050), Vector3(0.41, 0.61, 0), door_color)
	for face: float in [-1.0, 1.0]:
		_box(door, "DoorLowerInset", Vector3(0.64, 0.42, 0.012), Vector3(0.41, 0.30, face * 0.03), finish)
		_box(door, "DoorUpperInset", Vector3(0.64, 0.48, 0.012), Vector3(0.41, 0.87, face * 0.03), "dce7dc" if level >= 2 else door_color)
		if face > 0.0:
			_ellipsoid(door, "DoorKnob", Vector3(0.027, 0.027, 0.033), Vector3(0.73, 0.63, 0.068), "bca268" if level >= 1 else "798e81")
		if level == 3:
			_box(door, "DoorBrassPanelLine", Vector3(0.012, 1.04, 0.012), Vector3(0.13, 0.61, face * 0.047), "bc9c58", 0.5)
