extends SceneTree
## Verify the rendered structural meshes breathe while their authored base and
## attachments stay fixed. Requires -- --shop-test; --structure-capture saves
## phone-size geometry previews with the graphical renderer.

const Rules := preload("res://scripts/room_upgrades.gd")
const CameraFit := preload("res://scripts/gym_camera.gd")
const CATEGORIES := ["walls", "window", "railings"]
const FIXED_HEIGHT := {"walls": 0.15, "window": 0.07, "railings": 0.0575}
const RAMP_HEIGHT := {"walls": 0.35, "window": 0.35, "railings": 0.16}
const TIMES := [0.09, 0.18, 0.38, 0.55, 0.80]
const EPSILON := 0.00001

var room: Node3D
var camera: Camera3D
var checks := 0
var failures: Array[String] = []
var authored: Dictionary = {}
var material_ids: Dictionary = {}
var node_count := 0
var structure_pose := Transform3D.IDENTITY


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Structural pivot validation requires -- --shop-test to protect player progress.")
		quit(2)
		return
	if "--structure-capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() == "headless":
		push_error("Structural pivot captures require the graphical renderer.")
		quit(2)
		return
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message): failures.append(message)


func levels_at(level: int) -> Dictionary:
	var values := {}
	for category: String in Rules.IDS: values[category] = level
	return values


func baked_parts(category: String, tier: int) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var model: Node3D = room.get_node("%s/Tier%d" % [room.GROUP_NAMES[category], tier])
	result.append(model.get_node("BakedModel") as MeshInstance3D)
	if category == "window":
		for side: String in ["LeftHinge", "RightHinge"]:
			result.append(model.get_node(side + "/BakedModel") as MeshInstance3D)
	return result


func snapshot_authored() -> void:
	for category: String in CATEGORIES:
		for tier: int in range(Rules.visual_count(category) + 1):
			var key := "%s/Tier%d" % [room.GROUP_NAMES[category], tier]
			var records: Array[Dictionary] = []
			for mesh: MeshInstance3D in baked_parts(category, tier):
				var surfaces: Array[Material] = []
				var sources: Array[Material] = []
				for surface: int in mesh.mesh.get_surface_count():
					surfaces.append(mesh.get_surface_override_material(surface))
					sources.append(mesh.get_active_material(surface))
				records.append({"mesh": mesh, "resource": mesh.mesh, "transform": mesh.transform,
					"surfaces": surfaces, "sources": sources, "cull_margin": mesh.extra_cull_margin})
			authored[key] = {"transform": room.get_node(key).transform, "parts": records}
	structure_pose = room.get_node("Structure").transform
	node_count = room.find_children("*", "", true, false).size()
	for category: String in CATEGORIES:
		for tier: int in room._structural_motion.parts[category]:
			for part: Dictionary in room._structural_motion.parts[category][tier]:
				for material: ShaderMaterial in part.animated:
					material_ids[material.get_instance_id()] = true


func independent_tier_position(category: String, point: Vector3, amount: Vector3) -> Vector3:
	# Expected constraints are expressed in the room's authored coordinates,
	# independently of the helper's CPU implementation and cached matrices.
	var base: float = FIXED_HEIGHT[category]
	var height := maxf(point.y - base, 0.0)
	var weight := smoothstep(0.0, float(RAMP_HEIGHT[category]), height)
	var pivot := Vector3(0, base, -2.86 if category == "walls" else -2.64)
	if category == "railings":
		pivot = Vector3(-2.17 if point.x < 0.0 else 2.17, base, 0)
	var delta := (point - pivot) * (amount - Vector3.ONE) * weight
	if category == "railings": delta.z = 0.0
	return point + delta


func verify_vertices(category: String, tier: int, label: String) -> void:
	var key := "%s/Tier%d" % [room.GROUP_NAMES[category], tier]
	var model: Node3D = room.get_node(key)
	var amount: Vector3 = room.upgrade_scale(category)
	check(model.transform == authored[key].transform, label + " keeps the authored tier transform")
	check(amount.is_equal_approx(room._structural_motion.scale_for(category, tier)), label + " exposes the visible local deformation")
	var moved := 0
	var grounded := 0
	var end_anchors := 0
	var side_motion := {"left": 0, "right": 0}
	for record: Dictionary in authored[key].parts:
		var mesh: MeshInstance3D = record.mesh
		check(mesh.mesh == record.resource and mesh.transform == record.transform, label + " retains mesh and child transform " + str(mesh.get_path()))
		check(mesh.extra_cull_margin > float(record.cull_margin), label + " expands shader culling bounds")
		var mesh_to_tier := model.global_transform.affine_inverse() * mesh.global_transform
		var tier_to_mesh := mesh_to_tier.affine_inverse()
		for surface: int in mesh.mesh.get_surface_count():
			var material := mesh.get_surface_override_material(surface) as ShaderMaterial
			check(material != null, label + " animates every rendered surface")
			if material == null: continue
			check(material_ids.has(material.get_instance_id()), label + " reuses a preallocated surface material")
			check((material.get_shader_parameter("room_scale") as Vector3).is_equal_approx(amount), label + " draws the current breathing phase")
			check((material.get_shader_parameter("room_mesh_to_tier") as Transform3D).is_equal_approx(mesh_to_tier), label + " shader follows the current hinge pose")
			check((material.get_shader_parameter("room_tier_to_mesh") as Transform3D).is_equal_approx(tier_to_mesh), label + " returns shader geometry to its authored mesh coordinates")
			check(is_equal_approx(float(material.get_shader_parameter("room_fixed_height")), float(FIXED_HEIGHT[category])) and is_equal_approx(float(material.get_shader_parameter("room_ramp_height")), float(RAMP_HEIGHT[category])), label + " roots the rendered base band with a smooth height ramp")
			var expected_pivot := Vector3(0, float(FIXED_HEIGHT[category]), -2.86 if category == "walls" else (-2.64 if category == "window" else 0.0))
			check((material.get_shader_parameter("room_pivot") as Vector3).is_equal_approx(expected_pivot) and int(material.get_shader_parameter("room_kind")) == CATEGORIES.find(category), label + " renders the correct category attachment pivot")
			var source_material := record.sources[surface] as StandardMaterial3D
			check(source_material != null, label + " samples an authored structural material")
			if source_material != null:
				check(material.get_shader_parameter("room_albedo") == source_material.albedo_color and material.get_shader_parameter("room_metallic") == source_material.metallic and material.get_shader_parameter("room_roughness") == source_material.roughness and material.get_shader_parameter("room_specular") == source_material.metallic_specular, label + " preserves authored colour and surface shading")
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var all_match := true
			var fixed_band := true
			var fixed_end_feet := true
			var fixed_length := true
			var above_base := true
			var inside_cull_bounds := true
			var expanded_bounds := mesh.mesh.get_aabb().grow(mesh.extra_cull_margin + EPSILON)
			for point: Vector3 in vertices:
				var source := mesh_to_tier * point
				var expected := independent_tier_position(category, source, amount)
				var actual_local: Vector3 = room._structural_motion.deformed_vertex(mesh, point)
				var actual := mesh_to_tier * actual_local
				all_match = all_match and actual_local.distance_to(tier_to_mesh * expected) < EPSILON
				inside_cull_bounds = inside_cull_bounds and expanded_bounds.has_point(actual_local)
				above_base = above_base and actual.y >= minf(source.y, float(FIXED_HEIGHT[category])) - EPSILON
				if source.y <= float(FIXED_HEIGHT[category]) + 0.000001:
					grounded += 1
					fixed_band = fixed_band and actual.distance_to(source) < EPSILON and mesh.to_global(actual_local).distance_to(mesh.to_global(point)) < EPSILON
				if category == "railings":
					fixed_length = fixed_length and absf(actual.z - source.z) < EPSILON
					if absf(source.z) >= 1.63 and source.y <= float(FIXED_HEIGHT[category]) + 0.000001:
						end_anchors += 1
						fixed_end_feet = fixed_end_feet and actual.distance_to(source) < EPSILON
				if actual.distance_to(source) > 0.000001:
					moved += 1
					if category == "railings":
						var side := "left" if source.x < 0.0 else "right"
						side_motion[side] += 1
			check(all_match, label + " matches independent deformation of actual surface%d geometry" % surface)
			check(fixed_band, label + " fixes every base-band vertex in world space")
			check(above_base, label + " keeps geometry above its authored foundation")
			check(inside_cull_bounds, label + " includes every animated vertex in expanded culling bounds")
			if category == "railings":
				check(fixed_length and fixed_end_feet, label + " fixes end-post feet and the wall-side rail length")
	check(grounded > 0, label + " samples real base vertices")
	check(moved > 0, label + " has visible motion above the base")
	if category == "railings":
		check(end_anchors > 0, label + " samples real end-post and footrail base vertices")
		check(int(side_motion.left) > 0 and int(side_motion.right) > 0, label + " independently breathes both banks")
		var mesh := baked_parts(category, tier)[0]
		for side: float in [-1.0, 1.0]:
			var center := Vector3(side * 2.17, 0.20, 0)
			var actual: Vector3 = room._structural_motion.deformed_vertex(mesh, center)
			check(absf(actual.x - center.x) < EPSILON and absf(actual.z - center.z) < EPSILON, label + " keeps each bank's wall-side centreline fixed")
	check(room.get_node("Structure").transform == structure_pose, label + " preserves the fixed foundation")


func verify_rest(label: String) -> void:
	for key: String in authored:
		check(room.get_node(key).transform == authored[key].transform, label + " restores authored " + key)
		for record: Dictionary in authored[key].parts:
			var mesh: MeshInstance3D = record.mesh
			check(mesh.mesh == record.resource and mesh.transform == record.transform, label + " preserves mesh resources and child transforms")
			check(mesh.extra_cull_margin == record.cull_margin, label + " restores the exact culling margin")
			for surface: int in record.surfaces.size():
				check(mesh.get_surface_override_material(surface) == record.surfaces[surface], label + " restores the exact original material")
	for category: String in CATEGORIES:
		for tier: int in room._structural_motion.parts[category]:
			check(room._structural_motion.scale_for(category, tier) == Vector3.ONE, label + " clears every cached deformation")


func advance(delta: float) -> void:
	room._process(delta)
	room.set_process(false)


func start_purchase(category: String, level: int) -> void:
	var before: Dictionary = room.levels.duplicate()
	var after := before.duplicate()
	after[category] = level
	room.play_upgrade(category, after, Vector3.INF, before)
	room.set_process(false)


func capture(label: String) -> void:
	if "--structure-capture" not in OS.get_cmdline_user_args(): return
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../art/renders/structural_upgrade_pivots")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK, "Save phone structural preview " + label)


func verify_window_opening(tier: int) -> void:
	room.set_levels(levels_at(0 if tier == 0 else Rules.visual_milestones("window")[tier - 1]))
	room.set_window_open_amount(0.0)
	start_purchase("window", int(room.levels.window) + 1)
	advance(0.38)
	var poses := {}
	var closed_axes := {}
	for side: String in ["LeftHinge", "RightHinge"]:
		var hinge: Node3D = room.get_node("Window/Tier%d/%s" % [tier, side])
		poses[side] = hinge.transform
		var mesh: MeshInstance3D = hinge.get_node("BakedModel")
		var points: Array[Vector3] = []
		for height: float in [0.0, 0.15, 0.61, 1.22]:
			points.append(mesh.to_global(room._structural_motion.deformed_vertex(mesh, Vector3(0, height, 0))))
		closed_axes[side] = points
	for opening: float in [0.12, 0.50, 1.0, 0.0]:
		room.set_window_open_amount(opening)
		# Refresh only shader matrices; advancing the pulse by zero preserves
		# its measured phase while the completion hinge changes independently.
		advance(0.0)
		verify_vertices("window", tier, "Window tier%d opening%.2f" % [tier, opening])
		for side: String in poses:
			var hinge: Node3D = room.get_node("Window/Tier%d/%s" % [tier, side])
			var mesh: MeshInstance3D = hinge.get_node("BakedModel")
			var closed_basis: Basis = hinge.get_meta("closed_basis")
			var sign: float = hinge.get_meta("hinge_side")
			check(hinge.position == (poses[side] as Transform3D).origin and hinge.basis.is_equal_approx(closed_basis * Basis(Vector3.UP, -sign * room.WINDOW_OPEN_ANGLE * opening)), "Window purchase preserves functional authored opening tier%d %s" % [tier, side])
			var index := 0
			for height: float in [0.0, 0.15, 0.61, 1.22]:
				var current := mesh.to_global(room._structural_motion.deformed_vertex(mesh, Vector3(0, height, 0)))
				check(current.distance_to(closed_axes[side][index]) < EPSILON, "Window tier%d %s breathing hinge axis stays attached while opening" % [tier, side])
				index += 1
	room.cancel_upgrade_effects()
	verify_rest("Window tier%d opening cancel" % tier)
	room.reset_completion_motion()


func run() -> void:
	root.get_node("ShopState").set_process(false)
	root.size = Vector2i(390, 844)
	room = load("res://scenes/room/upgrade_room.tscn").instantiate()
	room.scale = Vector3(0.9, 1.0, 0.9)
	root.add_child(room)
	room.set_process(false)
	camera = Camera3D.new()
	root.add_child(camera)
	camera.current = true
	CameraFit.frame_workshop(camera, Vector2(root.size), Rect2(16, 60, 358, 724), room.global_transform * room.geometry_fit_bounds_local())
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("d7e2d8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.91, 0.97, 0.94)
	environment.ambient_light_energy = 0.45
	var world := WorldEnvironment.new()
	world.environment = environment
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-62, -35, 0)
	light.light_energy = 0.7
	light.shadow_enabled = true
	root.add_child(light)
	await process_frame
	check(room._structural_motion != null and room._structural_motion.parts.size() == 3, "All structural categories cache their authored geometry")
	snapshot_authored()
	for category: String in CATEGORIES:
		for tier: int in range(Rules.visual_count(category) + 1):
			var level: int = 0 if tier == 0 else Rules.visual_milestones(category)[tier - 1]
			room.set_levels(levels_at(level))
			start_purchase(category, level + 1)
			var previous := 0.0
			for time: float in TIMES:
				advance(time - previous)
				previous = time
				verify_vertices(category, tier, "%s tier%d time%.2f" % [category, tier, time])
				if tier == 0 and time == 0.38: await capture(category + "_first_stretch")
			var amount: Vector3 = room.upgrade_scale(category)
			var effect_phase: float = room.upgrade_effects[category].phase
			room.set_completion_paused(true)
			advance(0.6)
			check(room.upgrade_scale(category) == amount and room.upgrade_effects[category].phase == effect_phase, category + " pauses geometry and feedback together")
			verify_vertices(category, tier, category + " paused")
			room.set_completion_paused(false)
			advance(0.11)
			check(not room.is_upgrade_active(category), category + " finishes after its quiet timeout")
			verify_rest(category + " settlement")
		for milestone: int in Rules.visual_milestones(category):
			room.set_levels(levels_at(milestone - 1))
			start_purchase(category, milestone)
			advance(0.09)
			verify_vertices(category, Rules.visual_tier(category, milestone - 1), category + " before milestone%d" % milestone)
			advance(0.09)
			check(int(room.visual_tiers[category]) == Rules.visual_tier(category, milestone), category + " swaps the paid tier at the compressed phase")
			verify_vertices(category, Rules.visual_tier(category, milestone), category + " after milestone%d" % milestone)
			advance(0.20)
			if milestone == int(Rules.visual_milestones(category)[0]): await capture(category + "_milestone_stretch")
			room.cancel_upgrade_effects()
			verify_rest(category + " milestone cancel")
	for tier: int in range(Rules.visual_count("window") + 1): verify_window_opening(tier)
	room.set_levels(levels_at(0))
	for level: int in range(1, 23):
		for category: String in CATEGORIES:
			var before: Vector3 = room.upgrade_scale(category)
			start_purchase(category, level)
			check(room.upgrade_scale(category) == before, category + " retrigger retains the current pose synchronously")
		advance(0.06)
		for category: String in CATEGORIES:
			verify_vertices(category, int(room.visual_tiers[category]), category + " rapid purchase%d" % level)
		check(room.find_children("*", "", true, false).size() == node_count, "Concurrent rapid structural purchases allocate no scene nodes")
	room.reset_completion_motion()
	verify_rest("Full completion reset")
	var final_ids := {}
	for category: String in CATEGORIES:
		for tier: int in room._structural_motion.parts[category]:
			for part: Dictionary in room._structural_motion.parts[category][tier]:
				for material: ShaderMaterial in part.animated: final_ids[material.get_instance_id()] = true
	check(material_ids == final_ids, "Retriggers, milestones and resets reuse a bounded material cache")
	room.free()
	for index: int in mini(failures.size(), 20): push_error("STRUCTURAL_PIVOTS: " + failures[index])
	print("STRUCTURAL_PIVOTS_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
