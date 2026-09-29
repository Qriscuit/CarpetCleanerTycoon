extends SceneTree
## Real ten-pass extraction plus bounded, demand-only pool reclamation/save cases.
var checks := 0
var failures := 0
var soil: Node
var rug: Node3D

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to keep player saves isolated")
		quit(2)
		return
	call_deferred("run")

func advance(seconds: float) -> void:
	for tick in ceili(seconds * 120.0):
		soil._physics_process(1.0 / 120.0)

func swipe() -> void:
	soil.begin_pass()
	for step in 40:
		soil.stroke(Vector3(0, 0.067, -1.9 + step * 0.095), Vector3(0, 0.067, -1.805 + step * 0.095), 0.016)
	soil.end_pass()

func floor_fixture(supply: int) -> void:
	# A fully used visual pool over a rug which still has surface dirt.
	soil.reset()
	soil.free_slots.clear()
	soil.floor_debris.clear()
	soil.remaining = 0
	for i in 560:
		soil.credited[i] = true
		soil.cleared[i] = true
		soil.positions[i] = Vector3(-2.5 + (i % 20) * 0.1, 0, 2.8 + (i / 20) * 0.02)
		soil.growth[i] = 1.0
		soil.awakened[i] = true
		if i < supply:
			soil.growth[i] = 0.0
			soil.awakened[i] = false
			soil.recycled[i] = true
			soil.positions[i] = soil.initial[i].origin
			soil.free_slots.append(i)
		else:
			soil.floor_debris.append(i)

func run() -> void:
	rug = Node3D.new()
	var dirty := (load("res://scenes/dirty_carpet.tscn") as PackedScene).instantiate()
	dirty.name = "Dirty"
	rug.add_child(dirty)
	root.add_child(rug)
	soil = preload("res://scripts/dirt_controller.gd").new()
	root.add_child(soil)
	soil.automatic_completion_enabled = false
	soil.setup(rug)
	var pool_id: int = soil.batch.get_instance_id()
	var mesh_id: int = soil.batch.mesh.get_instance_id()
	var node_id: int = soil.batch_node.get_instance_id()
	check(is_equal_approx(soil.rug_definition.removal_per_pass, 0.1), "Starter surface removes ten percent per full pass")
	check(is_equal_approx(soil.rug_definition.dust_strength, 0.94), "Starter soil uses the much stronger dark surface veil")
	for pass_index in 10:
		soil.begin_pass()
		soil.paint_stroke(Vector2(0, -1.9), Vector2(0, 1.9))
		check(absf(soil.coverage_values[208 * 256 + 128] - maxf(0.0, 1.0 - (pass_index + 1) * 0.1)) < 0.00001, "Pass %d removes exactly one tenth" % (pass_index + 1))
	soil.end_pass()
	check(soil.coverage_values[208 * 256 + 128] == 0.0, "Ten full passes leave no floating-point residue")
	soil.reset()
	soil.set_tool_strength(2.25)
	for pass_index in 5:
		soil.begin_pass()
		soil.paint_stroke(Vector2(0, -1.9), Vector2(0, 1.9))
		if pass_index == 3:
			check(soil.coverage_values[208 * 256 + 128] > 0.09, "Strongest brush still needs more than four full passes")
	check(soil.coverage_values[208 * 256 + 128] == 0.0, "Strongest brush retains its five-pass advantage")
	soil.set_tool_strength(1.0)
	# Concentrate samples in a stripe and keep the remainder away from it.
	for i in 560:
		soil.initial[i].origin = Vector3(0 if i < 100 else 0.8, 0.067, -1.4 + (i % 100) * 0.028)
	soil.reset()
	swipe()
	advance(10.0)
	check(soil.timed_debris.is_empty() and soil.recycled.count(true) == 0 and not soil.floor_debris.is_empty(), "First-pass floor dirt stays visible after ten idle seconds")
	check(not soil.is_physics_processing(), "Retained settled dirt needs no idle physics")
	var supply_after_first: int = soil.free_slots.size()
	swipe()
	var borrowed := false
	for i in range(100, 560):
		if soil.awakened[i] and absf(soil.positions[i].x) < 0.1:
			borrowed = true
	check(borrowed and soil.free_slots.size() < supply_after_first, "A second dirty pass borrows unused slots from outside its stripe")
	check(soil.timed_debris.is_empty(), "Pool with ample supply does not reclaim old floor dirt")
	for pass_index in 5:
		swipe()
	check(soil.free_slots.is_empty(), "Repeated extraction can draw the entire available pool before reuse")
	check(soil.pending_emissions.size() <= soil.DEBRIS_POOL_BUFFER and soil.timed_debris.size() <= soil.DEBRIS_POOL_BUFFER, "Full-pool fade and pending work are bounded by the reserve")
	check(soil.remaining == soil.credited.count(false), "Borrowing visual identities preserves the one-time progress ledger")
	# Actual dirty strokes, not a test call to the reclamation helper, cause pressure.
	floor_fixture(64)
	soil.begin_pass()
	soil.stroke(Vector3(0, 0.067, -1.9), Vector3(0, 0.067, 1.9), 0.2)
	check(soil.free_slots.is_empty() and soil.timed_debris.size() == 64 and not soil.pending_emissions.is_empty(), "New dirt uses the reserve and requests a bounded batch of old floor clumps")
	var fading: int = soil.timed_debris[0]
	var born: int = soil.awakened.count(true)
	var pending: int = soil.pending_emissions.size()
	soil.stroke(Vector3(0, 0.067, -1.9), Vector3(0, 0.067, 1.9), 0.2)
	check(soil.awakened.count(true) == born and soil.pending_emissions.size() == pending, "Duplicate same-pass events cannot manufacture extra extraction requests")
	soil.end_pass()
	advance(0.30)
	check(soil._visible_debris_growth(fading) > 0.0 and soil._visible_debris_growth(fading) < 1.0, "Pressure-selected old clump shrinks smoothly")
	var mid_fade: Dictionary = soil.make_snapshot()
	soil.suspend_simulation(true)
	advance(10.0)
	check(soil.make_snapshot() == mid_fade, "Pause freezes fades, pending demand and earned progress")
	soil.suspend_simulation(false)
	var json_snapshot: Dictionary = JSON.parse_string(JSON.stringify(mid_fade))
	check(soil.restore_snapshot(json_snapshot), "Demand state survives the real JSON save format")
	check(soil.floor_debris == mid_fade.floor_debris and soil.pending_emissions.size() == pending and absf(soil.debris_age[fading] - 0.3) < 0.00001, "Resume preserves floor order, queued extraction and partial shrink")
	advance(0.4)
	check(soil.pending_emissions.is_empty(), "Returned slots fulfill already requested extraction without another input event")
	check(soil.remaining == 0 and soil.credited.count(true) == 560, "Reclamation and replacement never grant duplicate credit")
	advance(8.0)
	var idle: Dictionary = soil.make_snapshot()
	advance(20.0)
	check(soil.make_snapshot() == idle and not soil.is_physics_processing(), "After pending work finishes, elapsed time never starts further reclamation")
	check(soil.batch.instance_count == 560 and soil.batch.get_instance_id() == pool_id and soil.batch.mesh.get_instance_id() == mesh_id and soil.batch_node.get_instance_id() == node_id, "Extraction retains exactly the same 560-slot GPU batch, mesh and node")
	# A genuinely clean patch has no demand, even when every visual slot is busy.
	floor_fixture(0)
	soil.coverage_values.fill(0.0)
	soil.surface_coverage_total = 0.0
	swipe()
	check(soil.timed_debris.is_empty() and soil.pending_emissions.is_empty(), "Clean strokes cannot trigger fading or new dirt")
	# Legacy elapsed-time saves migrate into retained floor dirt.
	floor_fixture(0)
	var legacy: Dictionary = soil.make_snapshot()
	legacy.erase("debris_policy")
	legacy.erase("floor_debris")
	legacy.erase("pending_emissions")
	legacy.debris_age[0] = 3.3
	check(soil.restore_snapshot(legacy) and soil.debris_age[0] == -1.0 and soil.floor_debris.size() == 560, "Old timed snapshots become retained debris under the new policy")
	advance(10.0)
	check(soil.growth[0] == 1.0 and soil.timed_debris.is_empty(), "Migrated old timers cannot resume automatic disappearance")
	var stable: Dictionary = soil.make_snapshot()
	for field: String in ["debris_age", "floor_debris", "pending_emissions", "debris_policy"]:
		var invalid: Dictionary = JSON.parse_string(JSON.stringify(stable))
		match field:
			"debris_age": invalid.debris_age[0] = 3.3
			"floor_debris": invalid.floor_debris.append(0)
			"pending_emissions": invalid.pending_emissions = [{"source": 560, "velocity": [0, 0, 0]}]
			"debris_policy": invalid.debris_policy = 3
		check(not soil.restore_snapshot(invalid) and soil.make_snapshot() == stable, "Invalid %s is rejected atomically" % field)
	# Canceling all fades cannot strand previously queued real extraction.
	soil._request_pool_space()
	soil.pending_emissions.append({"source": 0, "velocity": Vector3(0, 0.9, 4)})
	for i: int in soil.timed_debris.duplicate():
		soil._cancel_debris_timer(i)
		soil._launch_debris(i, Vector3(2.5, 0, 2.5), Vector3.ZERO)
	advance(0.2)
	check(not soil.timed_debris.is_empty(), "Previously queued extraction restarts supply after rebrushed clumps settle")
	advance(1.0)
	check(soil.pending_emissions.is_empty(), "Rebrushing cannot strand the pending extraction queue")
	soil.set_recipe(true, true)
	check(soil.free_slots.is_empty() and soil.floor_debris.is_empty() and soil.pending_emissions.is_empty() and soil.timed_debris.is_empty() and not soil.is_physics_processing(), "Water-only recipe clears all dry pool demand and simulation")
	soil.free()
	rug.free()
	print("BRUSH RECYCLING: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
