extends SceneTree
## Ten-pass extraction, natural disappearance, permanent credit and bounded reuse.
var checks := 0
var failures := 0
var soil: Node
var rug: Node3D
var removal_events := 0

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
	if DisplayServer.get_name() == "headless":
		push_error("Brush recycling needs the real renderer for authored MultiMesh clump radii")
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
			soil.retired_credits[i] = true
			soil.growth[i] = 0.0
			soil.awakened[i] = false
			soil.recycled[i] = true
			soil.positions[i] = soil.initial[i].origin
			soil.free_slots.append(i)
		else:
			soil.floor_debris.append(i)
	soil.retired_credit_count = supply

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
	soil.cleaning_material_removed.connect(func(): removal_events += 1)
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
	soil._process(0.0)
	swipe()
	var immediate := true
	for i in 560:
		if soil.awakened[i]:
			immediate = immediate and soil.growth[i] == 1.0
	check(immediate and soil.render_dirty and not soil.active.is_empty(), "Original dirt is fully visible and scheduled to render during brush contact, before physics")
	soil._process(0.0)
	check(soil.batch.visible_instance_count > 25, "New contact dirt reaches the GPU batch without waiting for a physics tick")
	var supply_after_first: int = soil.free_slots.size()
	swipe()
	var borrowed := false
	var borrowed_slot := -1
	for i in range(100, 560):
		if soil.awakened[i] and absf(soil.positions[i].x) < 0.1:
			borrowed = true
			borrowed_slot = i
	check(borrowed and soil.free_slots.size() < supply_after_first, "A second dirty pass borrows unused slots before the earlier contact settles")
	if borrowed_slot >= 0:
		check(soil.growth[borrowed_slot] == 1.0 and soil.render_dirty, "Borrowed clump appears at full size in the brush's input event")
		var contact_position: Vector3 = soil.positions[borrowed_slot]
		soil._physics_process(1.0 / 60.0)
		check(soil.positions[borrowed_slot] != contact_position, "Borrowed dirt moves on the first physics tick instead of growing in place")
	check(soil.timed_debris.is_empty(), "Airborne contact cannot disappear or grant retirement credit prematurely")
	check(soil.retired_credit_count == 0 and removal_events == 0,"Birth and brush contact alone cannot count as removed dirt")
	advance(10.0)
	check(soil.timed_debris.is_empty() and soil.floor_debris.is_empty() and soil.recycled.count(true) > 0, "Settled outside clumps naturally disappear and return their slots")
	check(soil.retired_credit_count == soil.retired_credits.count(true) and soil.retired_credit_count > 0 and removal_events > 0,"Natural disappearance emits removal and retires each original credit once")
	check(not soil.is_physics_processing(), "Finished natural fades need no idle physics")
	for pass_index in 6:
		swipe()
	check(soil.free_slots.is_empty(), "Repeated extraction can draw the entire available pool before reuse")
	check(soil.make_snapshot().pending_emissions.is_empty() and soil.timed_debris.size() <= soil.batch.instance_count, "Natural fades stay within the fixed pool and no delayed births are queued")
	check(soil.remaining == soil.credited.count(false), "Borrowing visual identities preserves the one-time progress ledger")
	# Actual dirty strokes, not a test call to the reclamation helper, cause pressure.
	floor_fixture(64)
	# A saved retained floor now resumes all eligible clumps' natural timers;
	# its64 previously retired slots remain immediately available to contact.
	check(soil.restore_snapshot(JSON.parse_string(JSON.stringify(soil.make_snapshot()))),"Retained-floor fixture resumes through the production JSON loader")
	check(soil.timed_debris.size() == 496 and soil.floor_debris.is_empty(),"Every eligible retained clump resumes a natural fade without new brush demand")
	soil.begin_pass()
	soil.stroke(Vector3(0, 0.067, -1.9), Vector3(0, 0.067, 1.9), 0.2)
	check(soil.free_slots.is_empty() and soil.timed_debris.size() == 496 and soil.make_snapshot().pending_emissions.is_empty(), "New dirt uses the reserve while bounded natural fades finish without queueing late births")
	var fading: int = soil.timed_debris[0]
	var born: int = soil.awakened.count(true)
	soil.stroke(Vector3(0, 0.067, -1.9), Vector3(0, 0.067, 1.9), 0.2)
	check(soil.awakened.count(true) == born and soil.make_snapshot().pending_emissions.is_empty(), "Duplicate same-pass events cannot manufacture extra extraction requests")
	soil.end_pass()
	advance(0.30)
	check(soil._visible_debris_growth(fading) > 0.0 and soil._visible_debris_growth(fading) < 1.0, "A naturally retiring clump shrinks smoothly before0.6 seconds")
	check(not soil.retired_credits[fading],"A partially visible clump has not earned its disappearance credit")
	var mid_fade: Dictionary = soil.make_snapshot()
	soil.suspend_simulation(true)
	advance(10.0)
	check(soil.make_snapshot() == mid_fade, "Pause freezes fades and earned progress")
	soil.suspend_simulation(false)
	var json_snapshot: Dictionary = JSON.parse_string(JSON.stringify(mid_fade))
	check(soil.restore_snapshot(json_snapshot), "Natural fade and retirement state survive the real JSON save format")
	check(soil.floor_debris == mid_fade.floor_debris and soil.make_snapshot().pending_emissions.is_empty() and absf(soil.debris_age[fading] - 0.3) < 0.00001 and soil.retired_credit_count == 64, "Resume preserves the partial shrink and permanent credits without delayed extraction")
	advance(0.4)
	check(soil.free_slots.size() >= 496 and soil.recycled[fading] and soil.growth[fading] == 0.0 and soil.retired_credits[fading], "Disappeared slots stay invisible and retain credit after release")
	check(soil.remaining == 0 and soil.credited.count(true) == 560, "Reclamation and replacement never grant duplicate credit")
	check(soil.retired_credit_count == 560,"Previously retired reserve slots cannot earn retirement credit a second time")
	advance(8.0)
	var returned_slots: Array[int] = soil.free_slots.duplicate()
	soil.begin_pass()
	soil.stroke(Vector3(0.8, 0.067, -1.9), Vector3(0.8, 0.067, 1.9), 0.2)
	soil.end_pass()
	var current_contact := true
	var respawned := 0
	for i in returned_slots:
		if soil.awakened[i]:
			respawned += 1
			current_contact = current_contact and soil.growth[i] == 1.0 and absf(soil.positions[i].x - 0.8) < 0.001
		else:
			current_contact = current_contact and soil.growth[i] == 0.0
	check(current_contact and respawned > 0, "Returned slots spawn immediately at new contact; unused returned slots stay hidden")
	advance(8.0)
	check(soil.retired_credit_count == 560,"Reused cosmetic dirt never increases the original retirement ledger")
	var idle: Dictionary = soil.make_snapshot()
	advance(20.0)
	check(soil.make_snapshot() == idle and not soil.is_physics_processing(), "After motion and fades finish, elapsed time creates no dirt or further reclamation")
	check(soil.batch.instance_count == 560 and soil.batch.get_instance_id() == pool_id and soil.batch.mesh.get_instance_id() == mesh_id and soil.batch_node.get_instance_id() == node_id, "Extraction retains exactly the same 560-slot GPU batch, mesh and node")
	# A genuinely clean patch has no new demand, even when every slot is busy.
	floor_fixture(0)
	soil.coverage_values.fill(0.0)
	soil.surface_coverage_total = 0.0
	swipe()
	check(soil.timed_debris.is_empty() and soil.make_snapshot().pending_emissions.is_empty(), "A clean stroke cannot manufacture extraction or demand reclamation")
	# Older elapsed-time and retained-floor saves resume natural disappearance.
	floor_fixture(0)
	var legacy: Dictionary = soil.make_snapshot()
	legacy.erase("debris_policy")
	legacy.erase("floor_debris")
	legacy.erase("pending_emissions")
	legacy.erase("retired_credits")
	legacy.debris_age[0] = 3.3
	check(soil.restore_snapshot(legacy) and soil.debris_age[0] == 0.0 and soil.floor_debris.is_empty() and soil.timed_debris.size() == 560, "Old floor snapshots resume all natural fades without carrying obsolete lifetime ages")
	advance(10.0)
	check(soil.growth[0] == 0.0 and soil.timed_debris.is_empty() and soil.retired_credit_count == 560, "Migrated floor dirt disappears naturally and preserves every original credit")
	var stable: Dictionary = soil.make_snapshot()
	var hidden_legacy: Dictionary = JSON.parse_string(JSON.stringify(stable))
	hidden_legacy.erase("retired_credits")
	check(soil.restore_snapshot(hidden_legacy) and soil.retired_credit_count == 560,"Old hidden credited slots infer prior retirement rather than becoming fresh income")
	var events_before_idle := removal_events
	advance(10.0)
	check(removal_events == events_before_idle and soil.retired_credit_count == 560,"Restoring already-hidden old dirt cannot replay removal income")
	stable = soil.make_snapshot()
	for field: String in ["debris_age", "floor_debris", "pending_emissions", "debris_policy", "retired_credits", "retired_count"]:
		var invalid: Dictionary = JSON.parse_string(JSON.stringify(stable))
		match field:
			"debris_age": invalid.debris_age[0] = 3.3
			"floor_debris": invalid.floor_debris.append(0)
			"pending_emissions": invalid.pending_emissions = [{"source": 560, "velocity": [0, 0, 0]}]
			"debris_policy": invalid.debris_policy = 3
			"retired_credits": invalid.retired_credits[0] = "retired"
			"retired_count": invalid.retired_credits.pop_back()
		check(not soil.restore_snapshot(invalid) and soil.make_snapshot() == stable, "Invalid %s is rejected atomically" % field)
	# Older valid saves may contain deferred cosmetic requests. Preserve earned
	# progress and fade state, but never replay those obsolete contact positions.
	var queued_legacy: Dictionary = JSON.parse_string(JSON.stringify(mid_fade))
	queued_legacy.pending_emissions = [{"source": 0, "velocity": [0, 0.9, 4]}]
	check(soil.restore_snapshot(queued_legacy) and soil.make_snapshot().pending_emissions.is_empty(), "Old valid queued requests load safely and are discarded")
	advance(8.0)
	check(soil.free_slots.size() == 560 and soil.recycled[fading] and soil.remaining == 0 and soil.retired_credit_count == 560, "Loading an old queue cannot spawn stale dirt or duplicate earned retirement credit")
	soil.set_recipe(true, true)
	check(soil.free_slots.is_empty() and soil.floor_debris.is_empty() and soil.timed_debris.is_empty() and not soil.is_physics_processing(), "Water-only recipe clears all dry pool demand and simulation")
	soil.free()
	rug.free()
	print("BRUSH RECYCLING: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
