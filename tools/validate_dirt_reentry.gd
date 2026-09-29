extends SceneTree
## Regression: live debris remains movable, while re-entry and recycling preserve earned credit.
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CHECK FAILED: " + message)

func settle(soil: Node) -> void:
	for tick in 300:
		if not soil.is_physics_processing():
			break
		soil._physics_process(1.0 / 60.0)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var workshop := (load("res://scenes/test/rug_cleaning_gym.tscn") as PackedScene).instantiate()
	workshop.animate_rug_changes = false
	root.add_child(workshop)
	await process_frame
	var soil: Node = workshop.soil
	for edge_sign in [-1.0, 1.0]:
		for already_complete in [false, true]:
			workshop.reset_rug()
			# Reproduce a settled clump just outside either fringe, including after CLEAN.
			if already_complete:
				for i in soil.positions.size():
					soil.positions[i] = Vector3(4.0, 0.0, 4.0)
					soil.cleared[i] = true
					soil.credited[i] = true
				soil.remaining = 0
				soil.surface_coverage_total = 0.0
			else:
				soil.cleared[0] = true
				soil.credited[0] = true
				soil.remaining -= 1
			soil.positions[0] = Vector3(0.0, 0.0, 1.82 * edge_sign)
			soil.radii[0] = 0.04
			soil.awakened[0] = true
			soil.growth[0] = 1.0
			soil.free_slots.erase(0)
			# Preserve this fixture through completion so its physical re-entry can be inspected.
			workshop.auto_finish_queued = true
			workshop.update_progress(soil.remaining, soil.positions.size())
			var before: int = soil.remaining
			var outside: Vector3 = soil.positions[0] + soil.rug_origin
			soil.stroke(outside, outside + Vector3(0, 0, -0.015 * edge_sign), 0.1)
			check(soil.moving[0], "Cleared clump on tiles responds to an inward stroke")
			settle(soil)
			check(not soil.is_fully_outside(soil.positions[0], soil.radii[0]), "Inward fling lands back on rug")
			check(not soil.cleared[0] and soil.remaining == before, "Returning clump preserves earned cleanliness")
			check(not soil.recycled[0] and soil.debris_age[0] < 0.0 and not soil.floor_debris.has(0), "Returning dirt leaves the reclaimable floor queue while it rests on the rug")
			check(workshop.dirty == (not already_complete), "Returning dirt never revokes completion")
			var returned: Vector3 = soil.positions[0] + soil.rug_origin
			soil.stroke(returned, returned + Vector3(0, 0, 0.30 * edge_sign), 0.03)
			check(soil.moving[0] and soil.velocities[0].z * edge_sign > 0.0, "Returned dirt can be brushed back off")
			settle(soil)
			check(soil.cleared[0] and soil.clump_is_outside(0) and not soil.recycled[0], "Rebrushed clump clears the edge again and stays visible without extraction demand")
			check(soil.growth[0] == 1.0 and soil.awakened[0] and soil.floor_debris.has(0) and soil.debris_age[0] < 0.0, "Settled floor debris remains full-sized in the reclaimable queue")
			check(soil.remaining == soil.credited.count(false), "Progress agrees with clump states")
			if already_complete:
				check(not workshop.dirty and soil.remaining == 0, "Rug can complete again after re-entry")
			var final_count: int = soil.remaining
			var retained_position: Vector3 = soil.positions[0]
			for tick in 600:
				soil._physics_process(1.0 / 60.0)
			check(soil.remaining == final_count, "Settled clumps cannot be counted twice")
			check(soil.positions[0] == retained_position and soil.growth[0] == 1.0 and not soil.recycled[0], "Ten idle seconds never retire retained debris")
			check(soil.active.is_empty() and soil.timed_debris.is_empty() and not soil.is_physics_processing(), "Retained floor debris returns to idle sleep")
	# Saves can arrive after a clump earns credit but before its floor slide stops.
	# Such a live clump cannot enter the settled-only reclamation queue yet.
	workshop.reset_rug()
	workshop.auto_finish_queued = true
	soil.positions[0] = Vector3(3.0, 0.0, 3.0)
	soil.velocities[0] = Vector3(2.0, 0.0, 0.0)
	soil.growth[0] = 1.0
	soil.awakened[0] = true
	soil.moving[0] = true
	soil.cleared[0] = true
	soil.credited[0] = true
	soil.remaining -= 1
	soil.active.append(0)
	soil.free_slots.erase(0)
	soil._physics_process(1.0 / 60.0)
	check(soil.moving[0] and not soil.floor_debris.has(0), "Credited sliding dirt stays outside the settled-only reclaimable queue")
	var sliding_snapshot: Dictionary = soil.make_snapshot()
	check(soil.restore_snapshot(sliding_snapshot) and soil.make_snapshot() == sliding_snapshot, "A save made during an off-rug slide restores its exact valid state")
	settle(soil)
	check(not soil.moving[0] and soil.floor_debris.has(0), "Resumed sliding debris becomes reclaimable once it settles")
	# Fill the pool with legitimate already-earned floor debris. A new extraction
	# request may now reclaim a buffer, but its credit must remain permanent.
	workshop.reset_rug()
	workshop.auto_finish_queued = true
	soil.automatic_completion_enabled = false
	soil.free_slots.clear()
	soil.floor_debris.clear()
	soil.active.clear()
	for i in soil.positions.size():
		soil.positions[i] = Vector3(3.0 + float(i % 20) * 0.05, 0.0, 3.0 + float(i / 20) * 0.05)
		soil.velocities[i] = Vector3.ZERO
		soil.growth[i] = 1.0
		soil.awakened[i] = true
		soil.moving[i] = false
		soil.cleared[i] = true
		soil.credited[i] = true
		soil.recycled[i] = false
		soil.cooldown[i] = 0.0
		soil.debris_age[i] = -1.0
		soil.floor_debris.append(i)
	soil.remaining = 0
	soil._request_pool_space()
	check(not soil.timed_debris.is_empty() and soil.debris_age[0] >= 0.0, "Extraction pressure starts reclaiming the oldest eligible floor debris")
	soil._physics_process(0.3)
	check(soil._visible_debris_growth(0) > 0.0 and soil._visible_debris_growth(0) < 1.0 and not soil.recycled[0], "Demand-triggered reclamation visibly shrinks debris before reuse")
	soil._physics_process(0.31)
	check(soil.recycled[0] and soil.growth[0] == 0.0 and not soil.awakened[0] and soil.free_slots.has(0), "Finished fade returns an invisible clump to available supply")
	check(soil.remaining == 0 and soil.credited.count(false) == 0, "Reclaiming floor debris never changes previously earned progress")
	var retained_count: int = soil.recycled.count(false)
	soil._physics_process(10.0)
	check(soil.recycled.count(false) == retained_count and retained_count > 0 and soil.timed_debris.is_empty(), "Idle time after one pressure request never reclaims additional floor debris")
	print("DIRT RE-ENTRY CHECKS COMPLETE: ", failures, " failures; both fringe edges, return/rebrush, persistent completion and stable progress.")
	workshop.free()
	quit(0 if failures == 0 else 1)
