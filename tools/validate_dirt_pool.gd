extends SceneTree
## Resource lifetime, randomized refill, saved scatter and staged presentation.
var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func expose_source(soil: Node, position: Vector3) -> void:
	# Mask-only passes expose a dormant source without touching its physical slot.
	# Real contact must still release original dirt above an already-clean mask.
	var point := Vector2(position.x, position.z)
	for pass_number in ceili(1.0 / soil.rug_definition.removal_per_pass) + 1:
		soil.begin_pass()
		soil.paint_stroke(point, point + Vector2(0.0, 0.02))
	soil.end_pass()

func is_full_clump_visible_at(soil: Node, position: Vector3, expected_scale: Vector3) -> bool:
	for instance in soil.batch.visible_instance_count:
		var pose: Transform3D = soil.batch.get_instance_transform(instance)
		if pose.origin.is_equal_approx(position) and pose.basis.get_scale().is_equal_approx(expected_scale):
			return true
	return false

func run() -> void:
	var rug := Node3D.new()
	var dirty := (load("res://scenes/dirty_carpet.tscn") as PackedScene).instantiate()
	dirty.name = "Dirty"
	rug.add_child(dirty)
	root.add_child(rug)
	var soil := preload("res://scripts/dirt_controller.gd").new()
	root.add_child(soil)
	soil.automatic_completion_enabled = false
	soil.setup(rug)
	var pool_id := soil.batch.get_instance_id()
	var node_id := soil.batch_node.get_instance_id()
	var mesh_id := soil.batch.mesh.get_instance_id()
	var texture_id := soil.mask_texture.get_instance_id()
	var material_ids: Array[int] = []
	for material in soil.surface_materials:
		material_ids.append(material.get_instance_id())
	var previous_positions: Array[Vector3] = soil.positions.duplicate()
	var previous_bases: Array[Basis] = []
	for pose in soil.initial:
		previous_bases.append(pose.basis)
	var reuse_valid := true
	var scatter_valid := true
	var scatter_changes := true
	for cycle in 12:
		soil.configure_rug(load("res://resources/rugs/mint_meadow.tres"))
		reuse_valid = reuse_valid and soil.batch.get_instance_id() == pool_id and soil.batch_node.get_instance_id() == node_id and soil.batch.mesh.get_instance_id() == mesh_id and soil.mask_texture.get_instance_id() == texture_id and soil.batch.instance_count == 560 and soil.positions.size() == 560
		for i in soil.surface_materials.size():
			reuse_valid = reuse_valid and soil.surface_materials[i].get_instance_id() == material_ids[i]
		scatter_changes = scatter_changes and soil.positions != previous_positions
		for i in soil.positions.size():
			scatter_valid = scatter_valid and soil.footprint.contains_point(Vector2(soil.positions[i].x, soil.positions[i].z)) and soil.initial[i].basis == previous_bases[i]
		previous_positions.assign(soil.positions)
	check(reuse_valid, "Twelve rug refills reuse the same node, MultiMesh, mesh, texture, materials and 560 slots")
	check(scatter_changes, "Every new rug gets a different scatter")
	check(scatter_valid, "Refilled clumps remain on the rug with their original shapes and hulls")
	var seed_slot := -1
	var dormant_slot := -1
	for i in soil.initial_growth.size():
		if seed_slot == -1 and soil.initial_growth[i] > 0.1:
			seed_slot = i
		if dormant_slot == -1 and soil.initial_growth[i] == 0.0:
			dormant_slot = i
	check(seed_slot >= 0 and dormant_slot >= 0, "Pool contains visible starter seeds and dormant slots")
	if seed_slot < 0 or dormant_slot < 0:
		soil.free()
		rug.free()
		quit(1)
		return
	soil.refresh_visible_clumps()
	check(soil.batch.visible_instance_count == 25 and soil.batch.instance_count == 560, "Fresh rug renders only 25 starter seeds while retaining all 560 pool slots")
	soil.positions[seed_slot] += Vector3(0.1, 0.2, 0.1)
	soil.velocities[seed_slot] = Vector3(0.1, 0.2, 0.1)
	soil.growth[seed_slot] = 1.0
	soil.moving[seed_slot] = true
	soil.active.append(seed_slot)
	var before := soil.make_snapshot()
	soil.suspend_simulation(true)
	soil.set_reveal_progress(0.0)
	soil.refresh_visible_clumps()
	check(soil.batch.visible_instance_count == 0, "Rolled entrance keeps starter rocks hidden")
	check(is_equal_approx(float(soil.surface_materials[0].get_shader_parameter("dust_strength")), soil.rug_definition.dust_strength), "Rug enters already dust-textured before starter rocks appear")
	soil._physics_process(0.25)
	soil.stroke(Vector3(0, 0.067, -1), Vector3(0, 0.067, 1), 0.2)
	check(soil.make_snapshot() == before, "Entrance presentation cannot move dirt, clean pixels or alter a saved job")
	soil.set_reveal_progress(0.5)
	soil.refresh_visible_clumps()
	var midpoint_scale := soil.batch.get_instance_transform(0).basis.get_scale().length()
	check(soil.batch.visible_instance_count == 25 and midpoint_scale > 0.0 and midpoint_scale < soil.initial[seed_slot].basis.get_scale().length(), "Only starter rocks grow through intermediate sizes during reveal")
	check(is_equal_approx(float(soil.surface_materials[0].get_shader_parameter("dust_strength")), soil.rug_definition.dust_strength), "Dust remains fully present while starter rocks grow")
	soil.set_reveal_progress(1.0)
	soil.refresh_visible_clumps()
	check(soil.batch.visible_instance_count == 25 and is_equal_approx(soil.batch.get_instance_transform(0).basis.get_scale().length(), soil.initial[seed_slot].basis.get_scale().length()), "Reveal ends at saved physical growth while dormant clumps stay absent")
	check(is_equal_approx(float(soil.surface_materials[0].get_shader_parameter("dust_strength")), soil.rug_definition.dust_strength), "Finishing the rock reveal does not change surface dust")
	soil.suspend_simulation(false)
	check(soil.is_physics_processing() and soil.active.has(seed_slot), "Resuming keeps in-flight saved dirt active")
	soil._physics_process(0.01)
	check(soil.make_snapshot() != before, "In-flight dirt resumes only after entrance finishes")
	soil.configure_rug(load("res://resources/rugs/indigo_weave.tres"))
	check(soil.restore_snapshot(before), "A job restores after the pool was refilled with another scatter")
	check(soil.make_snapshot() == before, "Restore keeps exact positions, growth, coverage and scatter baseline")
	var old_snapshot: Dictionary = before.duplicate(true)
	old_snapshot.erase("spawn_positions")
	old_snapshot.erase("recycled")
	old_snapshot.erase("debris_age")
	old_snapshot.erase("debris_policy")
	old_snapshot.erase("floor_debris")
	check(soil.restore_snapshot(old_snapshot), "Older version-1 saves remain loadable without scatter baseline or debris lifecycle")
	var invalid: Dictionary = before.duplicate(true)
	invalid.spawn_positions[0] = [0.0, "broken", 0.0]
	check(not soil.restore_snapshot(invalid), "Malformed scatter baseline is rejected before changing the pool")
	soil.restore_snapshot(before)
	var before_invalid := soil.make_snapshot()
	invalid = before.duplicate(true)
	invalid.debris_age[seed_slot] = NAN
	check(not soil.restore_snapshot(invalid) and soil.make_snapshot() == before_invalid, "Non-finite debris age is rejected without mutating the job")
	invalid = before.duplicate(true)
	invalid.erase("recycled")
	check(not soil.restore_snapshot(invalid) and soil.make_snapshot() == before_invalid, "Incomplete lifecycle fields are rejected without mutating the job")
	soil.restore_snapshot(before)
	soil.reset()
	var restored_baseline := true
	for i in soil.positions.size():
		var p: Array = before.spawn_positions[i]
		restored_baseline = restored_baseline and soil.positions[i] == Vector3(p[0], p[1], p[2])
	check(restored_baseline, "Reset preserves the restored rug's original scatter")
	check(soil.timed_debris.is_empty() and soil.recycled.count(true) == 0 and soil.debris_age.count(-1.0) == soil.initial.size(), "Reset clears all recycled flags and debris timers")
	soil.refresh_visible_clumps()
	check(soil.batch.visible_instance_count == 25 and soil.growth[dormant_slot] == 0.0 and not soil.awakened[dormant_slot], "Dormant clumps remain absent after a new rug is ready to brush")
	var dormant_position: Vector3 = soil.positions[dormant_slot]
	expose_source(soil, dormant_position)
	soil.refresh_visible_clumps()
	soil.stroke(dormant_position, dormant_position + Vector3(0, 0, 0.02), 0.1)
	check(soil.awakened[dormant_slot] and soil.growth[dormant_slot] == 1.0 and soil.render_dirty, "Contact immediately awakens full-sized original dirt and requests rendering before a physics tick")
	soil.refresh_visible_clumps()
	check(is_full_clump_visible_at(soil, dormant_position, soil.initial[dormant_slot].basis.get_scale()), "Original dormant dirt renders at its brush contact point even after the surface mask was cleaned")
	soil._physics_process(1.0 / 60.0)
	check(soil.positions[dormant_slot] != dormant_position, "Original dormant dirt moves on the first physics tick after contact")
	soil.reset()
	# Older snapshots saved dormant clumps at 0.025. Keep their semantic state,
	# but do not turn those hidden pool slots into a field of visible pellets.
	soil.growth[dormant_slot] = 0.025
	var legacy_before := soil.make_snapshot()
	soil.refresh_visible_clumps()
	check(soil.batch.visible_instance_count == 25 and soil.make_snapshot() == legacy_before, "Legacy dormant pellets stay hidden without rewriting saved progress")
	dormant_position = soil.positions[dormant_slot]
	expose_source(soil, dormant_position)
	soil.stroke(dormant_position, dormant_position + Vector3(0, 0, 0.02), 0.1)
	soil.refresh_visible_clumps()
	check(soil.awakened[dormant_slot] and soil.growth[dormant_slot] == 1.0 and is_full_clump_visible_at(soil, dormant_position, soil.initial[dormant_slot].basis.get_scale()), "Legacy dormant dirt becomes fully visible during the brush-contact event without a growth delay")
	soil._physics_process(1.0 / 60.0)
	check(soil.positions[dormant_slot] != dormant_position, "Legacy dormant dirt moves on the first physics tick after contact")
	# Legacy saves predate scatter baselines. Dormant slots still contain their
	# original source positions, even when another rug has since refilled the pool.
	soil.reset()
	dormant_position = soil.positions[dormant_slot]
	expose_source(soil, dormant_position)
	var legacy_exposed := soil.make_snapshot()
	legacy_exposed.erase("spawn_positions")
	legacy_exposed.erase("recycled")
	legacy_exposed.erase("debris_age")
	legacy_exposed.erase("debris_policy")
	legacy_exposed.erase("floor_debris")
	soil.configure_rug(load("res://resources/rugs/mint_meadow.tres"))
	check(soil.initial[dormant_slot].origin != dormant_position, "Legacy restore fixture replaces the original scatter before resuming")
	check(soil.restore_snapshot(legacy_exposed), "Legacy exposed source restores over a different rug scatter")
	check(soil.positions[dormant_slot] == dormant_position and soil.initial[dormant_slot].origin == dormant_position, "Legacy dormant slot recovers its source from its saved untouched position")
	soil.stroke(dormant_position, dormant_position + Vector3(0, 0, 0.02), 0.1)
	soil._physics_process(1.0 / 60.0)
	check(soil.awakened[dormant_slot] and soil.growth[dormant_slot] > 0.0, "Legacy dormant dirt samples its own exposed patch and remains brushable after resume")
	soil.reset()
	var camera := Camera3D.new()
	camera.position = Vector3(0, 9, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	root.add_child(camera)
	camera.make_current()
	var sizes_before_vacuum: Array[float] = soil.growth.duplicate()
	soil.suspend_simulation(true)
	soil.start_vacuum(true)
	soil.animate_vacuum(0.0)
	check(soil.growth == sizes_before_vacuum, "Vacuum begins with current rock sizes instead of inflating untouched seeds")
	soil.animate_vacuum(1.3)
	var no_inflation := true
	for i in soil.growth.size():
		no_inflation = no_inflation and soil.growth[i] <= sizes_before_vacuum[i]
	check(no_inflation and soil.growth[seed_slot] < sizes_before_vacuum[seed_slot], "Vacuum shrinks original clumps without growing any new rocks")
	soil.animate_vacuum(0.6)
	check(soil.vacuum_complete and soil.batch.visible_instance_count == 0, "Vacuum clears the pool before the next refill")
	camera.free()
	soil.free()
	rug.free()
	print("DIRT POOL CHECKS: ", checks, " checks, ", failures, " failures; 12 refills retained one 560-slot GPU pool.")
	quit(0 if failures == 0 else 1)
