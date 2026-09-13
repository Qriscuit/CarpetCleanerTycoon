extends SceneTree
## Regression: cleared edge clumps must remain movable and count again on re-entry.
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CHECK FAILED: " + message)

func settle(soil: Node) -> void:
	for tick in 300:
		if soil.active.is_empty():
			break
		soil._physics_process(1.0 / 60.0)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var workshop := (load("res://scenes/rug_cleaning_gym.tscn") as PackedScene).instantiate()
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
			else:
				soil.cleared[0] = true
				soil.credited[0] = true
				soil.remaining -= 1
			soil.positions[0] = Vector3(0.0, 0.0, 1.82 * edge_sign)
			soil.radii[0] = 0.04
			workshop.update_progress(soil.remaining, soil.positions.size())
			var before: int = soil.remaining
			var outside: Vector3 = soil.positions[0] + soil.rug_origin
			soil.stroke(outside, outside + Vector3(0, 0, -0.015 * edge_sign), 0.1)
			check(soil.moving[0], "Cleared clump on tiles responds to an inward stroke")
			settle(soil)
			check(not soil.is_fully_outside(soil.positions[0], soil.radii[0]), "Inward fling lands back on rug")
			check(not soil.cleared[0] and soil.remaining == before, "Returning clump preserves earned cleanliness")
			check(workshop.dirty == (not already_complete), "Returning dirt never revokes completion")
			var returned: Vector3 = soil.positions[0] + soil.rug_origin
			soil.stroke(returned, returned + Vector3(0, 0, 0.03 * edge_sign), 0.03)
			check(soil.moving[0] and soil.velocities[0].z * edge_sign > 0.0, "Returned dirt can be brushed back off")
			settle(soil)
			check(soil.cleared[0] and soil.is_fully_outside(soil.positions[0], soil.radii[0]), "Rebrushed clump clears the edge again")
			check(soil.remaining == soil.credited.count(false), "Progress agrees with clump states")
			if already_complete:
				check(not workshop.dirty and soil.remaining == 0, "Rug can complete again after re-entry")
			var final_count: int = soil.remaining
			for tick in 10:
				soil._physics_process(1.0 / 60.0)
			check(soil.remaining == final_count, "Settled clumps cannot be counted twice")
			check(soil.active.is_empty() and not soil.is_physics_processing(), "Rebrushed clumps return to idle sleep")
	print("DIRT RE-ENTRY CHECKS COMPLETE: ", failures, " failures; both fringe edges, return/rebrush, persistent completion and stable progress.")
	workshop.free()
	quit(0 if failures == 0 else 1)
