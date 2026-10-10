extends SceneTree
## Every batched corner planter bounces about its own foot, including foliage,
## model milestones, uninterrupted purchases, pause and exact material cleanup.
## Add --plant-capture with the graphical renderer to save bounce previews.

const Rules := preload("res://scripts/room_upgrades.gd")
var room: Node3D
var checks := 0
var failures := 0


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Plant pivot validation requires -- --shop-test.")
		quit(2)
		return
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PLANT_PIVOTS: " + message)


func levels_at(level: int) -> Dictionary:
	var values := {}
	for id: String in Rules.IDS: values[id] = level
	return values


func shader_pivot(material: ShaderMaterial, point: Vector3) -> Vector3:
	var nearest: Vector3 = material.get_shader_parameter("room_plant_pivot_0")
	for index: int in range(1, 4):
		var candidate: Vector3 = material.get_shader_parameter("room_plant_pivot_%d" % index)
		if Vector2(candidate.x, candidate.z).distance_squared_to(Vector2(point.x, point.z)) < Vector2(nearest.x, nearest.z).distance_squared_to(Vector2(point.x, point.z)):
			nearest = candidate
	return nearest


func shader_position(material: ShaderMaterial, point: Vector3) -> Vector3:
	var pivot := shader_pivot(material, point)
	var scale: Vector3 = material.get_shader_parameter("room_plant_scale")
	return pivot + (point - pivot) * scale


func verify_active(tier: int, label: String) -> void:
	var model: Node3D = room.get_node("Plants/Tier%d" % tier)
	check(model.transform == room._tier_transforms["Plants/Tier%d" % tier], label + " keeps the batched tier transform at its authored origin")
	var shape: Vector3 = room.upgrade_scale("plants")
	for part: Dictionary in room._plant_upgrade_parts[tier]:
		var mesh: MeshInstance3D = part.mesh
		check(mesh.extra_cull_margin >= float(part.cull_margin) + 0.15, label + " includes shader expansion in culling bounds")
		for surface: int in part.animated.size():
			var material := mesh.get_surface_override_material(surface) as ShaderMaterial
			check(material == part.animated[surface] and material.get_shader_parameter("room_plant_scale") == shape, label + " draws with the cached local-bounce material")
			if material == null: continue
			check(material.shader.code.contains("vertex = pivot + (vertex - pivot) * room_plant_scale"), label + " uses local-foot vertex deformation")
			for index: int in range(4):
				var foot: Vector3 = part.pivots[index]
				var actual: Vector3 = material.get_shader_parameter("room_plant_pivot_%d" % index)
				check(actual.is_equal_approx(foot), label + " uses authored planter%d's own saucer foot" % index)
				check(shader_position(material, foot).is_equal_approx(foot), label + " keeps planter%d's complete foot stationary" % index)
				var stem := shader_position(material, foot + Vector3(0, 0.2, 0))
				check(is_equal_approx(stem.x, foot.x) and is_equal_approx(stem.z, foot.z) and is_equal_approx(stem.y, foot.y + 0.2 * shape.y), label + " keeps planter%d's centerline fixed while changing height" % index)
				var edge := shader_position(material, foot + Vector3(0.1, 0.1, 0.1))
				check(edge.is_equal_approx(foot + Vector3(0.1, 0.1, 0.1) * shape), label + " widens planter%d around its own center" % index)
			var source := mesh.mesh.surface_get_material(surface)
			if source is StandardMaterial3D:
				check(material.get_shader_parameter("pot_color") == source.albedo_color and material.get_shader_parameter("pot_metallic") == source.metallic and material.get_shader_parameter("pot_roughness") == source.roughness and material.get_shader_parameter("pot_specular") == source.metallic_specular, label + " preserves the authored opaque material values")
			elif source is ShaderMaterial:
				check(material.get_shader_parameter("leaf_color") == source.get_shader_parameter("leaf_color") and material.get_shader_parameter("soil_height") == source.get_shader_parameter("soil_height"), label + " preserves authored foliage color and anchoring")
				check(material.shader.code.contains("float stem_height = max(VERTEX.y - soil_height") and material.get_shader_parameter("breeze_strength") == room.breeze_strength, label + " retains the independent completion breeze")


func verify_rest(label: String) -> void:
	for tier: int in room._plant_upgrade_parts:
		check(room._plant_upgrade_scales[tier] == Vector3.ONE, label + " clears tier%d's local deformation" % tier)
		for part: Dictionary in room._plant_upgrade_parts[tier]:
			check(part.mesh.extra_cull_margin == part.cull_margin, label + " restores the exact authored culling margin")
			for surface: int in part.authored.size():
				check(part.mesh.get_surface_override_material(surface) == part.authored[surface], label + " restores the exact authored surface material")


func advance(delta: float) -> void:
	room._process(delta)
	room.set_process(false)


func capture(label: String) -> void:
	if "--plant-capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../art/renders")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join("plant_pivot_" + label + ".png")) == OK, "Save graphical plant-pivot preview " + label)


func run() -> void:
	root.size = Vector2i(720, 1000)
	room = load("res://scenes/room/upgrade_room.tscn").instantiate()
	room.scale = Vector3(0.9, 1, 0.9)
	root.add_child(room)
	room.set_process(false)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.6
	camera.position = Vector3(0, 9, 1.6)
	root.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("d7e2d8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.91, 0.97, 0.94)
	environment.ambient_light_energy = 0.25
	var world := WorldEnvironment.new()
	world.environment = environment
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-62, -35, 0)
	light.light_energy = 0.2
	light.shadow_enabled = true
	root.add_child(light)
	await process_frame
	check(room._plant_upgrade_parts.size() == 4, "All four authored plant tiers have cached local pivots")
	var nodes := room.find_children("*", "", true, false).size()
	var materials := {}
	var meshes := {}
	for tier: int in room._plant_upgrade_parts:
		for part: Dictionary in room._plant_upgrade_parts[tier]:
			meshes[part.mesh.get_instance_id()] = part.mesh.mesh
			for surface: int in part.animated.size(): materials[part.animated[surface].get_instance_id()] = true
		var vertices_valid := true
		for part: Dictionary in room._plant_upgrade_parts[tier]:
			for surface: int in part.animated.size():
				var arrays: Array = part.mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for point: Vector3 in vertices:
					var nearest := shader_pivot(part.animated[surface], point)
					vertices_valid = vertices_valid and absf(nearest.x - point.x) < 0.4 and absf(nearest.z - point.z) < 0.4
		check(vertices_valid, "Tier%d's baked geometry assigns every pot/leaf vertex to a nearby authored planter" % tier)
	for tier: int in range(4):
		var level: int = 0 if tier == 0 else Rules.visual_milestones("plants")[tier - 1]
		room.set_levels(levels_at(level))
		var old: Dictionary = room.levels.duplicate()
		var purchased := old.duplicate()
		purchased.plants = level + 1
		if tier == 3: await capture("authored")
		room.play_upgrade("plants", purchased, room.to_global(Vector3(1.94, 0.7, 2.42)), old)
		room.set_process(false)
		room.start_completion_breeze()
		room.set_process(false)
		var previous_time := 0.0
		for time: float in [0.09, 0.18, 0.38, 0.55, 0.8]:
			advance(time - previous_time)
			previous_time = time
			verify_active(tier, "Tier%d time%.2f" % [tier, time])
			if tier == 3 and is_equal_approx(time, 0.38): await capture("tall")
			if tier == 3 and is_equal_approx(time, 0.55): await capture("wide")
		var shape: Vector3 = room.upgrade_scale("plants")
		var breeze_time: float = room.breeze_time
		room.set_completion_paused(true)
		advance(0.4)
		check(room.upgrade_scale("plants") == shape and room.breeze_time == breeze_time, "Tier%d focus pause freezes local bounce and foliage together" % tier)
		room.set_completion_paused(false)
		advance(0.2)
		verify_rest("Tier%d settlement" % tier)
		room.reset_completion_motion()
	for milestone: int in Rules.visual_milestones("plants"):
		room.set_levels(levels_at(milestone - 1))
		var old: Dictionary = room.levels.duplicate()
		var purchased := old.duplicate()
		purchased.plants = milestone
		room.play_upgrade("plants", purchased, Vector3.INF, old)
		room.set_process(false)
		advance(0.09)
		verify_active(Rules.visual_tier("plants", milestone - 1), "Before milestone%d" % milestone)
		advance(0.09)
		verify_active(Rules.visual_tier("plants", milestone), "After milestone%d" % milestone)
		room.cancel_upgrade_effects()
		verify_rest("Milestone%d cancel" % milestone)
	room.set_levels(levels_at(0))
	for level: int in range(1, 51):
		var old: Dictionary = room.levels.duplicate()
		var purchased := old.duplicate()
		purchased.plants = level
		var before: Vector3 = room.upgrade_scale("plants")
		room.play_upgrade("plants", purchased, Vector3.INF, old)
		room.set_process(false)
		check(room.upgrade_scale("plants") == before, "Rapid purchase%d retains its current local deformation" % level)
		advance(0.06)
		verify_active(int(room.visual_tiers.plants), "Rapid purchase%d" % level)
		check(room.find_children("*", "", true, false).size() == nodes, "Rapid purchase%d allocates no new scene nodes" % level)
		for tier: int in room._plant_upgrade_parts:
			for part: Dictionary in room._plant_upgrade_parts[tier]:
				check(part.mesh.mesh == meshes[part.mesh.get_instance_id()], "Rapid purchase%d retains its authored baked mesh" % level)
	room.reset_completion_motion()
	verify_rest("Complete reset")
	var final_materials := {}
	for tier: int in room._plant_upgrade_parts:
		for part: Dictionary in room._plant_upgrade_parts[tier]:
			for material: ShaderMaterial in part.animated: final_materials[material.get_instance_id()] = true
	check(materials == final_materials, "All milestone/retrigger motion reuses the same bounded material cache")
	room.free()
	print("PLANT_PIVOTS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
