extends SceneTree
## Isolated purchase-feedback invariants: deferred milestone swap, motion, world
## anchors, focus pause, interruption, completion coexistence and bounded reuse.
var checks := 0
var failures := 0
var finished: Array[String] = []
const IDS := ["floor", "plants", "window", "railings", "walls"]
const RoomRules := preload("res://scripts/room_upgrades.gd")

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to protect the player's save")
		quit(2)
		return
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var room: Node3D = load("res://scenes/room/upgrade_room.tscn").instantiate()
	room.scale = Vector3(0.9, 1.0, 0.9)
	root.add_child(room)
	room.set_process(false)
	room.upgrade_finished.connect(func(id: String): finished.append(id))
	var transforms := {}
	for id: String in IDS:
		for tier in range(4):
			var path := "%s/Tier%d" % [room.GROUP_NAMES[id], tier]
			transforms[path] = room.get_node(path).transform
	var structure_transform: Transform3D = room.get_node("Structure").transform
	var child_count := room.get_child_count()
	check(room.upgrade_effects.size() == IDS.size(), "Exactly one effect instance per feature is preallocated")
	for id: String in IDS:
		var milestone := RoomRules.visual_milestones(id)[0]
		var before := {}
		for category: String in IDS: before[category] = milestone - 1
		room.set_levels(before)
		check(room.visual_tiers[id] == 0, id + " stays original before its first milestone")
		var after := before.duplicate()
		after[id] = milestone
		# Exercise the synchronous ledger.changed ordering too.
		room.set_levels(after)
		var anchor: Vector3 = room.to_global(Vector3(1.94, 0.7, 2.42)) if id == "plants" else room.anchor_world(id)
		room.play_upgrade(id, after, anchor, before)
		room.set_process(false)
		check(room.visual_tiers[id] == 0 and room.levels[id] == milestone, id + " durable value changes while prior model remains visible")
		var effect: Node3D = room.upgrade_effects[id]
		var ring_mesh_id: int = effect.ring.mesh.get_instance_id()
		var pillar_mesh_id: int = effect.pillar.mesh.get_instance_id()
		check(effect.visible and effect.global_position.is_equal_approx(Vector3(anchor.x, 0.035, anchor.z)), id + " feedback sits at tapped footprint on the floor")
		check(is_equal_approx(effect.global_basis.x.length(), effect.global_basis.z.length()), id + " ring remains round under decorative room scaling")
		room._process(0.09)
		room.set_process(false)
		check(room.upgrade_scale(id).y < 1.0 and room.visual_tiers[id] == 0, id + " first squeezes without swapping")
		room._process(0.09)
		room.set_process(false)
		check(room.visual_tiers[id] == 1, id + " changes model at compressed midpoint")
		var next: Node3D = room.get_node("%s/Tier1" % room.GROUP_NAMES[id])
		check(room.upgrade_scale(id).y < 1.0, id + " new model arrives compressed, without a pop")
		check(is_equal_approx(effect.opacity, 1.0), id + " pillar reaches full brightness and alpha envelope")
		check(effect.pillar_material.shader.code.contains("pow(1.0 - pillar_height"), id + " shader fades white pillar toward its top")
		room._process(0.20)
		room.set_process(false)
		check(room.upgrade_scale(id).y > 1.0, id + " gently stretches after the change")
		var paused_transform: Transform3D = next.transform
		var paused_scale: Vector3 = room.upgrade_scale(id)
		var paused_phase: float = effect.phase
		room.set_completion_paused(true)
		room._process(2.0)
		room.set_process(false)
		check(next.transform == paused_transform and room.upgrade_scale(id) == paused_scale and effect.phase == paused_phase, id + " focus loss pauses object and shader wave")
		room.set_completion_paused(false)
		room._process(0.60)
		check(not room.is_upgrade_active(id) and not effect.visible, id + " finishes and releases its effect")
		check(not room.is_processing(), id + " leaves no idle animation processing")
		for path: String in transforms:
			check(room.get_node(path).transform == transforms[path], id + " settlement restores exact authored transform " + path)
		check(room.get_node("Structure").transform == structure_transform, id + " purchase never moves structural floor")
		for restart in range(20):
			after[id] += 1
			room.play_upgrade(id, after, anchor)
			room.set_process(false)
			room._process(0.05)
			room.set_process(false)
		check(effect.ring.mesh.get_instance_id() == ring_mesh_id and effect.pillar.mesh.get_instance_id() == pillar_mesh_id, id + " rapid purchases reuse the same geometry")
		check(room.get_child_count() == child_count and room.upgrade_effects.size() == IDS.size(), id + " rapid purchases keep allocation bounded")
		room.cancel_upgrade_effects()
		check(not effect.visible and not room.is_upgrade_active(), id + " cancellation hides all feedback")
		check(room.visual_tiers[id] == RoomRules.visual_tier(id, int(after[id])), id + " interrupted animation settles latest durable target")
	check(finished.size() >= 8, "Finishes and interruptions notify the purchase UI")
	room.set_levels({"floor": 5, "plants": 10, "window": 15, "railings": 0})
	room.set_window_open_amount(0.5)
	var hinge: Node3D = room.get_node("Window/Tier3/LeftHinge")
	var hinge_transform := hinge.transform
	room.start_completion_breeze()
	room.play_upgrade("plants", {"floor": 5, "plants": 11, "window": 15, "railings": 0})
	room.play_upgrade("window", {"floor": 5, "plants": 11, "window": 16, "railings": 0})
	room.set_process(false)
	room._process(0.38)
	room.set_process(false)
	check(hinge.transform == hinge_transform, "Upgrade pulse preserves independently opened window hinge pose")
	check(room.breeze_strength > 0.0, "Purchase and completion foliage breeze can coexist")
	room.clear_selection()
	check(room.is_processing(), "Clearing selection preserves active purchase motion")
	room.reset_completion_motion()
	check(not room.is_upgrade_active() and is_zero_approx(room.window_open_amount) and is_zero_approx(room.breeze_strength), "Scene reset cancels feedback, closes windows and stills foliage")
	for id: String in IDS:
		check(not room.upgrade_effects[id].visible, "Scene reset hides " + id + " effect")
	for path: String in transforms:
		check(room.get_node(path).transform == transforms[path], "Reset restores exact authored transform " + path)
	check(not room.is_processing(), "Reset leaves no idle processing")
	room.free()
	print("ROOM UPGRADE VFX: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
