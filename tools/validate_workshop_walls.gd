extends SceneTree
## Validate authored walls, preserved window passage, touch targets and milestones.
## Required: -- --shop-test. Optional: --walls-capture for graphical previews.

const WORKSHOP := preload("res://scenes/production/rug_cleaning.tscn")
const RoomRules := preload("res://scripts/room_upgrades.gd")

var checks := 0
var failures := 0
var game: Node
var ledger: Node
var room: Node3D
var save_path := ""


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Workshop wall validation requires -- --shop-test to protect player progress.")
		quit(2)
		return
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("WORKSHOP_WALLS: " + message)


func settle() -> void:
	await process_frame
	await process_frame


func all_levels(level: int) -> Dictionary:
	var result := {}
	for category: String in RoomRules.IDS:
		result[category] = level
	return result


func meshes_under(node: Node, found: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		found.append(node)
	for child: Node in node.get_children():
		meshes_under(child, found)


func wall_sources(tier: int) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	meshes_under(room.get_node("Walls/Tier%d/EditableSource" % tier), result)
	return result


func local_mesh_bounds(model: MeshInstance3D) -> AABB:
	return room.global_transform.affine_inverse() * (model.global_transform * model.mesh.get_aabb())


func validate_wall_geometry(tier: int) -> void:
	var model: Node3D = room.get_node("Walls/Tier%d" % tier)
	check(model.visible and not model.get_node("EditableSource").visible, "Wall tier%d displays its baked model once" % tier)
	check(model.get_node("BakedModel").mesh.get_surface_count() <= 10, "Wall tier%d uses a bounded set of material batches" % tier)
	check(bool(model.get_meta("front_open", false)), "Wall tier%d leaves the diorama front open" % tier)
	check(float(model.get_meta("clear_exit_width", 0.0)) >= 3.06, "Wall tier%d preserves the existing roll corridor" % tier)
	var corridor := AABB(Vector3(-1.53, 0.13, -3.05), Vector3(3.06, 1.10, 0.62))
	var rug_keepout := AABB(Vector3(-1.04, 0.0, -1.69), Vector3(2.08, 1.9, 3.38))
	var fit: AABB = room.geometry_fit_bounds_local()
	var no_exit_obstruction := true
	var no_rug_obstruction := true
	var all_inside_fit := true
	var front_open := true
	for source: MeshInstance3D in wall_sources(tier):
		var bounds := local_mesh_bounds(source)
		no_exit_obstruction = no_exit_obstruction and not corridor.intersects(bounds)
		no_rug_obstruction = no_rug_obstruction and not rug_keepout.intersects(source.global_transform * source.mesh.get_aabb())
		all_inside_fit = all_inside_fit and fit.grow(0.004).encloses(bounds)
		front_open = front_open and bounds.end.z < 0.05
	check(no_exit_obstruction, "Every wall tier%d primitive stays outside the real window rolling aperture" % tier)
	check(no_rug_obstruction, "Every wall tier%d primitive stays outside the playable rug" % tier)
	check(all_inside_fit, "Every wall tier%d primitive fits the declared room bounds" % tier)
	check(front_open, "Wall tier%d has no geometry across the front apron" % tier)
	var door: Node3D = model.get_node("EditableSource/SideDoorLeaf")
	check(is_equal_approx(door.rotation_degrees.y, -78.0), "The authored door opens shallowly outward instead of crossing the railing")
	var door_point: Vector3 = door.to_global(Vector3(0.41, 0.66, 0.03))
	check(room.pick_upgrade(game.camera, game.camera.unproject_position(door_point)) == "walls", "The visible door opens the walls offer at tier%d" % tier)
	for category: String in RoomRules.IDS:
		var point: Vector2 = game.camera.unproject_position(room.anchor_world(category))
		check(room.pick_upgrade(game.camera, point) == category, "Walls preserve the distinct %s target at tier%d" % [category, tier])
	for x: float in [-1.03, 0.0, 1.03]:
		for z: float in [-1.67, 0.0, 1.68]:
			var picked: String = room.pick_upgrade(game.camera, game.camera.unproject_position(Vector3(x, 0.067, z)))
			check(picked.is_empty(), "Wall tier%d preserves rug/fringe x%.2f z%.2f (picked '%s')" % [tier, x, z, picked])


func validate_hinge_clearance(tier: int) -> void:
	var walls: Array[MeshInstance3D] = wall_sources(tier)
	var moving: Array[MeshInstance3D] = []
	for side: String in ["LeftHinge", "RightHinge"]:
		meshes_under(room.get_node("Window/Tier%d/%s/EditableSource" % [tier, side]), moving)
	for amount: float in [0.0, 0.25, 0.50, 0.75, 1.0]:
		room.set_window_open_amount(amount)
		var collision := false
		for piece: MeshInstance3D in moving:
			for surface: int in piece.mesh.get_surface_count():
				var arrays: Array = piece.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for vertex: Vector3 in vertices:
					var world_point: Vector3 = piece.to_global(vertex)
					for wall: MeshInstance3D in walls:
						if wall.mesh.get_aabb().grow(-0.002).has_point(wall.to_local(world_point)):
							collision = true
		check(not collision, "Tier%d window vertices stay clear of walls at opening%.2f" % [tier, amount])
	var aperture: Dictionary = room.window_clear_aperture_world()
	check(float(aperture.width) > 2.08, "The fully open tier%d window stays wider than the carpet and fringe" % tier)
	room.set_window_open_amount(0.0)


func first_standard_surface(category: String) -> Dictionary:
	var mesh: MeshInstance3D = room.get_node("%s/Tier3/BakedModel" % room.GROUP_NAMES[category])
	for surface: int in mesh.mesh.get_surface_count():
		var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
		if material != null:
			return {"mesh": mesh, "surface": surface, "source": material}
	return {}


func validate_final_appearance() -> void:
	var last: int = RoomRules.visual_milestones("walls")[-1]
	var cap := RoomRules.Progression.room_level_cap(1)
	room.set_levels(all_levels(last))
	var samples := {}
	for category: String in RoomRules.IDS:
		samples[category] = first_standard_surface(category)
		check(not samples[category].is_empty(), category + " has an authored standard finish surface")
	var foliage: MeshInstance3D = room.get_node("Plants/Tier3/Foliage/BakedModel")
	var foliage_shader: Material = foliage.mesh.surface_get_material(0)
	var hinge: Node3D = room.get_node("Window/Tier3/LeftHinge")
	var hinge_basis := hinge.basis
	for level: int in range(last, cap + 1):
		room.set_levels(all_levels(level))
		for category: String in RoomRules.IDS:
			var sample: Dictionary = samples[category]
			var material := sample.mesh.get_surface_override_material(int(sample.surface)) as StandardMaterial3D
			check(material == null and sample.mesh.mesh.surface_get_material(int(sample.surface)) == sample.source, "%s preserves its authored final material through income level%d" % [category, level])
			check(int(room.visual_tiers[category]) == 3 and sample.mesh == room.get_node("%s/Tier3/BakedModel" % room.GROUP_NAMES[category]), "%s retains its last authored mesh at level%d" % [category, level])
	check(foliage.mesh.surface_get_material(0) == foliage_shader and foliage.get_surface_override_material(0) == null, "Remaining income purchases preserve the shared foliage breeze shader")
	check(hinge.basis.is_equal_approx(hinge_basis), "Remaining income purchases preserve the window hinge pose")
	room.start_completion_breeze()
	room._process(0.1)
	check(room.breeze_strength > 0.0, "Foliage still receives completion breeze after the final makeover")
	room.reset_completion_motion()


func validate_wall_milestone_swap_timing() -> void:
	var milestone: int = RoomRules.visual_milestones("walls")[-1]
	var before := all_levels(milestone - 1)
	var after: Dictionary = before.duplicate()
	after.walls = milestone
	room.set_levels(before)
	room.play_upgrade("walls", after, Vector3.INF, before)
	room.set_process(false)
	check(room.get_node("Walls/Tier2").visible and not room.get_node("Walls/Tier3").visible, "A final makeover retains its prior mesh when feedback begins")
	room._process(room.UPGRADE_SWAP_TIME * 0.5)
	room.set_process(false)
	check(room.get_node("Walls/Tier2").visible and not room.get_node("Walls/Tier3").visible, "The prior wall mesh remains through the squeeze")
	room._process(room.UPGRADE_SWAP_TIME * 0.5)
	room.set_process(false)
	check(not room.get_node("Walls/Tier2").visible and room.get_node("Walls/Tier3").visible, "The final authored wall mesh appears at the compressed swap point")
	room._process(room.UPGRADE_DURATION)
	check(not room.is_upgrade_active("walls"), "Final makeover feedback completes with the authored mesh")


func touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = pressed
	root.push_input(event, true)


func validate_real_wall_purchase() -> void:
	room.set_levels(ledger.room_upgrade_levels())
	var original: Dictionary = game.soil.make_snapshot()
	var point: Vector2 = game.camera.unproject_position(room.anchor_world("walls"))
	touch(point, true)
	touch(point, false)
	room.set_process(false)
	await settle()
	check(game.hud.upgrades_open() and game.hud.room_panel.selected_id == "walls", "A real wall tap opens the floating walls offer")
	var quote: Dictionary = ledger.room_upgrade_view("walls")
	var before: int = ledger.cash
	var buy: Button = game.hud.room_panel.get_node("%Buy")
	point = buy.get_global_rect().get_center()
	touch(point, true)
	touch(point, false)
	room.set_process(false)
	await settle()
	check(int(ledger.room_upgrade_levels().walls) == 1 and ledger.cash == before - int(quote.cost), "The wall gesture buys exactly one independent upgrade")
	check(room.is_upgrade_active("walls") and not buy.disabled, "The wall success animation leaves the next affordable purchase available immediately")
	room.set_process(false)
	room._process(0.1)
	room.set_process(false)
	check(room.upgrade_effects.walls.opacity > 0.0 and room.get_node("Walls/Tier0").scale.y < 1.0, "Walls use the white ring/pillar and a gentle squeeze")
	await capture("purchase_feedback")
	room._process(0.9)
	check(not room.is_upgrade_active("walls") and room.get_node("Walls/Tier0").scale.is_equal_approx(Vector3.ONE), "Walls return to their exact authored pose after the effect")
	game.hud.close_upgrades()
	check(game.soil.make_snapshot() == original, "Wall picking and purchase leave the carpet state unchanged")


func capture(label: String) -> void:
	if "--walls-capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	var folder := ProjectSettings.globalize_path("res://../art/renders")
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join("workshop_walls_" + label + ".png")) == OK, "Save wall capture " + label)


func run() -> void:
	ledger = root.get_node("ShopState")
	ledger.set_process(false)


	save_path = ProjectSettings.globalize_path("res://.godot/workshop_walls_%d.json" % OS.get_process_id())
	ledger._save_path = save_path
	check(ledger.reset_progress(), "Create an isolated wall validation ledger")
	ledger.cash = 50000
	root.size = Vector2i(648, 900)
	game = WORKSHOP.instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	await settle()
	room = game.room
	check(room.get_node_or_null("Walls/Tier3/BakedModel") != null, "The generated room installs all four editable wall tiers")
	if room.get_node_or_null("Walls/Tier3/BakedModel") == null:
		await finish_tests()
		return
	for tier: int in range(4):
		var level: int = 0 if tier == 0 else RoomRules.visual_milestones("walls")[tier - 1]
		room.set_levels(all_levels(level))
		validate_wall_geometry(tier)
		validate_hinge_clearance(tier)
		await capture("tier%d" % tier)
	validate_final_appearance()
	await capture("final_appearance")
	validate_wall_milestone_swap_timing()
	room.set_levels(all_levels(RoomRules.visual_milestones("walls")[-1]))
	root.size = Vector2i(800, 360)
	await settle()
	game.frame_carpet()
	# Camera projection uses the stretched logical viewport, not the physical
	# window dimensions. Keep the production content scaling in this fixture.
	var frame: Rect2 = game.get_viewport().get_visible_rect()
	for index in 8:
		var corner: Vector3 = room.to_global(room.geometry_fit_bounds_local().get_endpoint(index))
		var projected: Vector2 = game.camera.unproject_position(corner)
		check(frame.grow(1.0).has_point(projected), "The wall room fits the landscape camera at corner%d (%s in %s)" % [index, projected, frame])
	await capture("landscape")
	root.size = Vector2i(648, 900)
	await settle()
	game.frame_carpet()
	await validate_real_wall_purchase()
	await finish_tests()


func finish_tests() -> void:
	if is_instance_valid(game):
		game.free()
	current_scene = null
	root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	DirAccess.remove_absolute(save_path)
	DirAccess.remove_absolute(save_path + ".bak")
	print("WORKSHOP_WALLS_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
