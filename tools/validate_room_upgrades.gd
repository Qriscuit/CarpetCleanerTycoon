extends SceneTree
## Checks room tier visibility and screen-space picking without touching the real save.
## Add --room-render after --shop-test to save four previews using a graphical renderer.

var room: Node3D
var camera: Camera3D
var failures: Array[String] = []
const RoomRules := preload("res://scripts/room_upgrades.gd")

func levels_at(level: int) -> Dictionary:
	var values := {}
	for category: String in RoomRules.IDS: values[category] = level
	return values

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test for isolated validation")
		quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	print("Room validation user arguments: ", OS.get_cmdline_user_args())
	root.size = Vector2i(720, 1000)
	var stage := Node3D.new()
	root.add_child(stage)
	room = load("res://scenes/room/upgrade_room.tscn").instantiate()
	room.scale = Vector3(0.9, 1.0, 0.9)
	stage.add_child(room)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("d7e2d8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.91, 0.97, 0.94)
	environment.ambient_light_energy = 0.25
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-62, -35, 0)
	light.light_color = Color(1, 0.99, 0.97)
	light.light_energy = 0.16
	light.shadow_enabled = true
	stage.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-42, 145, 0)
	fill.light_color = Color(0.79, 0.92, 1.0)
	fill.light_energy = 0.04
	stage.add_child(fill)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 4.2
	camera.position = Vector3(0, 10.0, 1.7633)
	stage.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true
	var rug := MeshInstance3D.new()
	var rug_mesh := BoxMesh.new()
	rug_mesh.size = Vector3(1.95, 0.05, 3.18)
	rug.mesh = rug_mesh
	rug.position.y = 0.035
	var rug_material := StandardMaterial3D.new()
	rug_material.albedo_color = Color("6e9f8d")
	rug.material_override = rug_material
	stage.add_child(rug)
	await process_frame
	for tier: int in range(4):
		var purchase_level: int = 0 if tier == 0 else RoomRules.visual_milestones("floor")[tier - 1]
		room.set_levels(levels_at(purchase_level))
		var rendered_surfaces := 0
		for category: String in room.CATEGORIES:
			for other: int in range(4):
				var visible: bool = room.get_node("%s/Tier%d" % [room.GROUP_NAMES[category], other]).visible
				_expect(visible == (other == tier), "%s tier visibility %d/%d" % [category, tier, other])
			var active_model: Node3D = room.get_node("%s/Tier%d" % [room.GROUP_NAMES[category], tier])
			_expect(not active_model.get_node("EditableSource").visible, "Construction meshes must not duplicate rendered models")
			rendered_surfaces += active_model.get_node("BakedModel").mesh.get_surface_count()
			var screen: Vector2 = camera.unproject_position(room.anchor_world(category))
			var hit: String = room.pick_upgrade(camera, screen)
			_expect(hit == category, "%s anchor picked %s at tier %d" % [category, hit, tier])
		for x: float in [-1.03, 0.0, 1.03]:
			for z: float in [-1.67, 0.0, 1.68]:
				var rug_screen := camera.unproject_position(Vector3(x, 0.067, z))
				_expect(room.pick_upgrade(camera, rug_screen).is_empty(), "Rug stroke must not pick an upgrade")
		for apron: Vector3 in [Vector3(-1.14, 0.0, 0.0), Vector3(1.14, 0.0, 0.0), Vector3(0.0, 0.0, 1.78)]:
			_expect(room.pick_upgrade(camera, camera.unproject_position(apron)) == "floor", "Exposed floor apron remains tappable")
		_expect(rendered_surfaces <= 48, "Room material batches stay bounded: %d" % rendered_surfaces)
		print("Room tier %d: %d material batches" % [tier, rendered_surfaces])
		if OS.get_cmdline_user_args().has("--room-render"):
			await process_frame
			await RenderingServer.frame_post_draw
			var output := "res://../art/renders/room_upgrade_tier_%d.png" % tier
			var error := root.get_texture().get_image().save_png(output)
			_expect(error == OK, "Preview saved: %s" % output)
	room.set_selected("window")
	await process_frame
	room.clear_selection()
	for purchase_level: int in [1, 14, 16, 29, 31, 44]:
		room.set_levels(levels_at(purchase_level))
		var expected_tier := RoomRules.visual_tier("floor", purchase_level)
		for category: String in room.CATEGORIES:
			_expect(room.levels[category] == purchase_level and room.visual_tiers[category] == expected_tier, "%s retains its purchased level and only changes appearance at an authored milestone" % category)
			_expect(room.get_node("%s/Tier%d" % [room.GROUP_NAMES[category], expected_tier]).visible, "%s intermediate purchase keeps the earned model visible" % category)
	room.set_levels({"floor": 999, "plants": -8})
	_expect(room.levels.floor == RoomRules.Progression.room_level_cap(1) and room.visual_tiers.floor == 3 and room.levels.plants == 0 and room.visual_tiers.plants == 0, "Purchased levels and visual tiers clamp safely at the store ladder bounds")
	if failures.is_empty():
		print("PASS: 16 tier variants, 16 category targets, 36 protected rug/fringe points, 12 floor apron taps, bounded material batches, selection and clamping")
	else:
		for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
