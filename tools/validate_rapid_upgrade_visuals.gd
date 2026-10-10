extends SceneTree
## Exercise continuous upgrade motion independently of purchase UI timing.
## Always use -- --shop-test, even though this fixture never changes the ledger.

const ROOM := preload("res://scenes/room/upgrade_room.tscn")
const RoomRules := preload("res://scripts/room_upgrades.gd")
var checks := 0
var failures := 0
var room: Node3D
var finished := {}


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Rapid visual validation requires -- --shop-test.")
		quit(2)
		return
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("RAPID_UPGRADE_VISUALS: " + message)


func levels_at(level: int) -> Dictionary:
	var result := {}
	for category: String in room.CATEGORIES:
		result[category] = level
	return result


func advance(delta: float) -> void:
	room._process(delta)
	room.set_process(false)


func model(category: String) -> Node3D:
	return room.get_node("%s/Tier%d" % [room.GROUP_NAMES[category], int(room.visual_tiers[category])])


func on_finished(category: String) -> void:
	finished[category] = int(finished.get(category, 0)) + 1


func exact_rest(category: String) -> bool:
	if room.upgrade_scale(category) != Vector3.ONE: return false
	for tier: int in range(4):
		var path := "%s/Tier%d" % [room.GROUP_NAMES[category], tier]
		if room.get_node(path).transform != room._tier_transforms[path]:
			return false
	return true


func run() -> void:
	room = ROOM.instantiate()
	root.add_child(room)
	room.set_process(false)
	room.upgrade_finished.connect(on_finished)
	var child_count := room.get_child_count()
	var effect_ids := {}
	for category: String in room.CATEGORIES:
		effect_ids[category] = room.upgrade_effects[category].get_instance_id()
	for category: String in room.CATEGORIES:
		var milestone := RoomRules.visual_milestones(category)[0]
		room.set_levels(levels_at(milestone - 1))
		var old := levels_at(milestone - 1)
		var next := old.duplicate()
		next[category] = milestone
		room.play_upgrade(category, next, Vector3.INF, old)
		room.set_process(false)
		advance(0.09)
		check(int(room.visual_tiers[category]) == 0 and room.upgrade_scale(category).y < 1.0, category + " keeps the old model during the initial squeeze")
		advance(0.09)
		check(int(room.visual_tiers[category]) == 1, category + " reveals its new model at the compressed point")
		advance(0.20)
		check(room.upgrade_scale(category).y > 1.0 and room.upgrade_scale(category).x < 1.0, category + " becomes tall and narrow")
		advance(0.17)
		check(room.upgrade_scale(category).y < 1.0 and room.upgrade_scale(category).x > 1.0, category + " becomes wider after the tall pop")
		advance(0.35)
		check(not room.is_upgrade_active(category) and exact_rest(category), category + " returns all tiers to their exact authored pose")
		check(not room.upgrade_effects[category].visible, category + " hides its reusable effect after settling")
		check(int(finished.get(category, 0)) == 1, category + " emits one single-purchase completion")

	finished.clear()
	var cap := RoomRules.Progression.room_level_cap(6)
	room.set_levels(levels_at(0), 6)
	# Fifty taps per second across the later store's visual milestones are
	# faster than human input. The effect pool and spring still remain bounded.
	for purchase: int in range(1, cap + 1):
		for category: String in room.CATEGORIES:
			var old: Dictionary = room.levels.duplicate()
			var next := old.duplicate()
			next[category] = purchase
			var was_active: bool = room.is_upgrade_active(category)
			var before_pose := model(category).transform
			var before_scale: Vector3 = room.upgrade_scale(category)
			var effect: Node3D = room.upgrade_effects[category]
			var opacity_before: float = effect.opacity
			var phase_before: float = effect.phase
			var pillar_before: Vector3 = effect.pillar.scale
			var ring_before: Vector3 = effect.ring.scale
			room.play_upgrade(category, next, Vector3.INF, old)
			room.set_process(false)
			if was_active:
				check(model(category).transform == before_pose and room.upgrade_scale(category) == before_scale, category + " preserves its current pose on purchase%d" % purchase)
				check(is_equal_approx(effect.opacity, opacity_before) and is_equal_approx(effect.phase, phase_before), category + " preserves glow and wave phase on purchase%d" % purchase)
				check(effect.pillar.scale == pillar_before and effect.ring.scale == ring_before, category + " preserves effect geometry on purchase%d" % purchase)
			check(effect.get_instance_id() == effect_ids[category], category + " reuses its one effect on purchase%d" % purchase)
		advance(0.02)
		for category: String in room.CATEGORIES:
			var scale_now: Vector3 = room.upgrade_scale(category)
			check(scale_now.is_finite() and scale_now.y >= 0.85 and scale_now.y <= 1.19 and scale_now.x >= 0.94 and scale_now.x <= 1.07, category + " keeps repeated motion bounded on purchase%d" % purchase)
			check(int(finished.get(category, 0)) == 0, category + " never ends feedback between rapid taps")
		check(room.get_child_count() == child_count and room._upgrade_animations.size() == 5 and room.upgrade_effects.size() == 5, "Rapid taps keep a fixed five-effect/five-animation pool")
	advance(0.18)
	for category: String in room.CATEGORIES:
		check(int(room.visual_tiers[category]) == RoomRules.visual_count(category), category + " reveals its latest paid authored model during continuous motion")
		check(room.upgrade_effects[category].opacity > 0.0, category + " retains a visible continuous effect after the last tap")
	advance(0.75)
	for category: String in room.CATEGORIES:
		check(exact_rest(category) and not room.is_upgrade_active(category) and not room.upgrade_effects[category].visible, category + " settles exactly after the final rapid purchase")
		check(int(finished.get(category, 0)) == 1, category + " emits one final completion for the continuous burst")

	# Closing/cancelling feedback is also synchronous, with no pending impulse.
	for category: String in room.CATEGORIES:
		room.play_upgrade(category, levels_at(cap))
	advance(0.11)
	room.cancel_upgrade_effects()
	for category: String in room.CATEGORIES:
		check(exact_rest(category) and not room.upgrade_effects[category].visible, category + " cancels to its paid model's authored rest")
	check(not room.is_upgrade_active(), "Cancellation clears every animation")
	print("RAPID_UPGRADE_VISUALS_RESULT checks=%d failures=%d" % [checks, failures])
	room.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
