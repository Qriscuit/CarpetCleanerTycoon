extends SceneTree
## Fixed-size companion physics and real paid-room lifecycle integration.
## Run through tools/run_godot.ps1 with isolated APPDATA and -- --shop-test.
const State := preload("res://scripts/shop_state.gd")
const Rules := preload("res://scripts/progression.gd")
const Catalog := preload("res://scripts/avatar_catalog.gd")
const Cleaning := preload("res://scenes/production/rug_cleaning.tscn")
var checks := 0
var failures := 0
var ledger: Node
var game: Node
var save_path := ""

class PendingVideo extends RefCounted:
	var callback: Callable
	var job := ""
	var nonce := ""
	func is_rewarded_ad_available() -> bool: return true
	func request_verified_reward(id: String, token: String, result: Callable) -> bool:
		job = id
		nonce = token
		callback = result
		return true
	func verify_reward_receipt(_id: String, _token: String, _receipt: Dictionary) -> bool: return false
	func cancel() -> void:
		var result := callback
		callback = Callable() # Release the disposable provider/service cycle.
		result.call(job, nonce, {"status":"cancelled"})

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("LEVEL COMPANION: " + message)

func frames(count: int) -> void:
	for _frame in count:
		await physics_frame
		await process_frame

func enter_room() -> void:
	game = Cleaning.instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await process_frame
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await frames(3)

func leave_room() -> void:
	if is_instance_valid(game): game.free()
	game = null
	current_scene = null
	await process_frame

func count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children(): count += count_nodes(child)
	return count

func pose_snapshot(node: Node) -> Array:
	var result: Array = []
	if node is Node3D: result.append(node.global_transform)
	if node is Skeleton3D:
		for bone in node.get_bone_count(): result.append(node.get_bone_pose(bone))
	for child in node.get_children(): result.append_array(pose_snapshot(child))
	return result

func scale_reference(companion: Node3D) -> Dictionary:
	var skeleton: Skeleton3D = companion.find_children("*", "Skeleton3D", true, false)[0]
	var local_scales: Array[Vector3] = []
	var world_scales: Array[Vector3] = []
	var lengths: Array[float] = []
	for bone in skeleton.get_bone_count():
		var rest := skeleton.get_bone_global_rest(bone)
		local_scales.append(rest.basis.get_scale().abs())
		world_scales.append((skeleton.global_transform * rest).basis.get_scale().abs())
		var parent := skeleton.get_bone_parent(bone)
		lengths.append((skeleton.global_transform * rest.origin - skeleton.global_transform * skeleton.get_bone_global_rest(parent).origin).length() if parent >= 0 else 0.0)
	return {"skeleton":skeleton, "local":local_scales, "world":world_scales, "lengths":lengths}

func pose_scale_error(reference: Dictionary) -> float:
	var skeleton: Skeleton3D = reference.skeleton
	var worst := 0.0
	for bone in skeleton.get_bone_count():
		var pose := skeleton.get_bone_global_pose(bone)
		var actual := pose.basis.get_scale().abs()
		var world := (skeleton.global_transform * pose).basis.get_scale().abs()
		var expected: Vector3 = reference.local[bone]
		var expected_world: Vector3 = reference.world[bone]
		for axis in 3:
			worst = maxf(worst, absf(actual[axis] / maxf(expected[axis], 0.000001) - 1.0))
			worst = maxf(worst, absf(world[axis] / maxf(expected_world[axis], 0.000001) - 1.0))
	return worst

func bone_stretch(reference: Dictionary) -> Dictionary:
	var skeleton: Skeleton3D = reference.skeleton
	var worst := {"excess":0.0, "bone":"", "actual":0.0, "rest":0.0, "point":Vector3.ZERO, "parent_point":Vector3.ZERO, "phase":""}
	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		if parent < 0: continue
		# The pelvis is the unjointed physical root. Its animation root remains
		# in place during a free fall; that distance is world motion, not a limb.
		if skeleton.get_bone_name(bone) == "pelvis": continue
		var point := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		var parent_point := skeleton.global_transform * skeleton.get_bone_global_pose(parent).origin
		var distance := point.distance_to(parent_point)
		var expected: float = reference.lengths[bone]
		var excess := distance - expected * 1.15
		if excess > float(worst.excess): worst = {"excess":excess, "bone":skeleton.get_bone_name(bone), "actual":distance, "rest":expected, "point":point, "parent_point":parent_point, "phase":""}
	return worst

func physical_joint_stretch(companion: Node3D, reference: Dictionary) -> Dictionary:
	var skeleton: Skeleton3D = reference.skeleton
	var physical_by_bone := {}
	for i in companion._bodies.size(): physical_by_bone[int(companion._body_bone_ids[i])] = companion._bodies[i]
	var worst := {"excess":0.0, "bone":"", "actual":0.0, "rest":0.0, "point":Vector3.ZERO, "parent_point":Vector3.ZERO, "phase":"FALLING physics"}
	for id: int in physical_by_bone:
		var parent := skeleton.get_bone_parent(id)
		if not physical_by_bone.has(parent): continue
		var body: PhysicalBone3D = physical_by_bone[id]
		var parent_body: PhysicalBone3D = physical_by_bone[parent]
		var point := (body.global_transform * body.body_offset.affine_inverse()).origin
		var parent_point := (parent_body.global_transform * parent_body.body_offset.affine_inverse()).origin
		var distance := point.distance_to(parent_point)
		var expected: float = reference.lengths[id]
		var excess := distance - expected * 1.15
		if excess > float(worst.excess): worst = {"excess":excess, "bone":skeleton.get_bone_name(id), "actual":distance, "rest":expected, "point":point, "parent_point":parent_point, "phase":"FALLING physics"}
	return worst

func unchanged_play(cash: float, surface: float, debris: float, mask: PackedByteArray, message: String) -> void:
	check(ledger.cash == cash and game.soil.surface_clearance() == surface and game.soil.unique_clearance() == debris and game.soil.mask.get_data() == mask, message)

func pointer_button(point: Vector2, pressed: bool, touch_input := false, canceled := false) -> void:
	if touch_input:
		var event := InputEventScreenTouch.new()
		event.index = 3
		event.position = point
		event.pressed = pressed
		event.canceled = canceled
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)

func pointer_drag(point: Vector2, previous: Vector2, touch_input: bool) -> void:
	if touch_input:
		var event := InputEventScreenDrag.new()
		event.index = 3
		event.position = point
		event.relative = point - previous
		root.push_input(event, true)
	else:
		var event := InputEventMouseMotion.new()
		event.position = point
		event.relative = point - previous
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event, true)

func input_point(x: float, z: float, touch_input: bool) -> Vector2:
	var point: Vector2 = game.camera.unproject_position(Vector3(x, game.CARPET_PLANE_Y, z))
	return point - game.TOUCH_CONTACT_OFFSET if touch_input else point

func check_paid_instance(message: String) -> void:
	check(is_instance_valid(game.companion) and game.companion.visible, message)
	if not is_instance_valid(game.companion): return
	var stats: Dictionary = game.companion.debug_stats()
	check(bool(stats.get("rig_ready", false)) and int(stats.get("physical_body_count", 0)) == 9, "Each paid scene has one fixed nine-body rig")
	check(str(stats.get("state_name", "")) == "RIDING" and int(stats.get("simulating_body_count", -1)) == 0, "A fresh paid scene begins seated with no active ragdoll simulation")

func check_animation_contract() -> void:
	var companion: Node3D = game.companion
	var player: AnimationPlayer = companion._animation
	for key: String in ["idle", "ride", "run"]:
		var clip: Animation = player.get_animation(companion._clips[key])
		check(clip.loop_mode == Animation.LOOP_LINEAR, "Runtime " + key + " animation loops continuously")
	for key: String in ["get_up", "dust_off", "climb"]:
		var clip: Animation = player.get_animation(companion._clips[key])
		check(clip.loop_mode == Animation.LOOP_NONE, "Runtime " + key + " animation finishes as a single action")
	for key: String in ["ride", "run"]:
		var clip: Animation = player.get_animation(companion._clips[key])
		player.play(companion._clips[key], 0.0)
		player.seek(0.0, true)
		player.advance(0.0)
		var start := pose_snapshot(companion)
		player.advance(clip.length * 2.27)
		var ongoing := player.is_playing() and player.current_animation_position > clip.length * 0.20 and player.current_animation_position < clip.length * 0.35
		# Ride may intentionally hold a static seated pose. Running must still
		# change the authored pose beyond a complete cycle.
		check(ongoing and (key == "ride" or pose_snapshot(companion) != start), "The " + key + " clip keeps playing after more than two complete cycles")
	player.play(companion._clips.ride, 0.0)
	player.advance(0.0)

func check_pause_and_appearance() -> void:
	var companion: Node3D = game.companion
	var nodes := count_nodes(companion)
	var job: String = ledger.active_job_id
	var cash: float = ledger.cash
	var surface: float = game.soil.surface_clearance()
	var debris: float = game.soil.unique_clearance()
	var mask: PackedByteArray = game.soil.mask.get_data()
	check(ledger.set_appearance("violet", "pirate"), "A free wardrobe selection commits while the paid room is open")
	await frames(2)
	check(ledger.active_job_id == job and ledger.appearance == {"color_id":"violet", "hat_id":"pirate"}, "Live appearance preserves the paid rug identity")
	var appearance_stats: Dictionary = companion.debug_stats()
	check(appearance_stats.appearance == ledger.appearance and bool(appearance_stats.hat_head_attached), "The live companion equips the saved appearance with a head-attached hat")
	var tinted := true
	for material: StandardMaterial3D in companion._materials:
		tinted = tinted and material.albedo_color.is_equal_approx(Catalog.color_for("violet"))
	check(tinted and not companion._materials.is_empty(), "The in-level body uses the selected tint on per-instance materials")
	unchanged_play(cash, surface, debris, mask, "Equipping a companion color and hat cannot earn or remove dirt")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(2)
	var paused := pose_snapshot(companion)
	await frames(6)
	check(not bool(companion.debug_stats().active) and pose_snapshot(companion) == paused, "Focus loss freezes the complete companion pose")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await frames(2)
	check(bool(companion.debug_stats().active), "Focus return reactivates the companion")
	game.hud.open_upgrades()
	await frames(2)
	paused = pose_snapshot(companion)
	await frames(6)
	check(not bool(companion.debug_stats().active) and pose_snapshot(companion) == paused, "The purchase drawer freezes the companion")
	game.hud.close_upgrades()
	await frames(2)
	var provider := PendingVideo.new()
	check(ledger.register_reward_ad_provider(provider) and ledger.request_carpet_reward_ad(ledger.active_job_id), "A real disposable provider holds the current carpet video pending")
	await frames(2)
	paused = pose_snapshot(companion)
	await frames(6)
	check(not bool(companion.debug_stats().active) and pose_snapshot(companion) == paused, "Rewarded-video suspension freezes the companion")
	provider.cancel()
	await frames(2)
	for phase: int in [game.RugPhase.ARRIVING, game.RugPhase.GROWING, game.RugPhase.TOOL_ENTERING, game.RugPhase.VACUUMING, game.RugPhase.REVEAL, game.RugPhase.DEPARTING]:
		game.rug_phase = phase
		game._sync_companion(0.0, true)
		await frames(1)
		check(companion.visible and not bool(companion.debug_stats().active), "Rug presentation phase %d keeps an inactive visible companion" % phase)
	game.rug_phase = game.RugPhase.CLEANING
	game._sync_companion(0.0, true)
	await frames(2)
	check(companion.visible and bool(companion.debug_stats().active) and str(companion.debug_stats().state_name) == "RIDING", "Returning from presentation reseats the persistent companion")
	check(count_nodes(companion) == nodes, "Appearance and lifecycle changes reuse the existing rig nodes")
	unchanged_play(cash, surface, debris, mask, "Idle, focus, menus and video resume cannot grant money or clean the paid rug")

func check_motion() -> void:
	var companion: Node3D = game.companion
	var nodes := count_nodes(companion)
	var cash: float = ledger.cash
	var surface: float = game.soil.surface_clearance()
	var debris: float = game.soil.unique_clearance()
	var mask: PackedByteArray = game.soil.mask.get_data()
	var seat := Transform3D(game.brush.global_basis.orthonormalized(), game.brush.global_transform * game.COMPANION_SEAT)
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var scale_reference_data := scale_reference(companion)
	check(pose_scale_error(scale_reference_data) < 0.05, "The seated skeleton preserves authored local and world bone scale")
	check(float(bone_stretch(scale_reference_data).excess) < 0.03, "The seated skeleton keeps connected joints at their authored distances")
	# The production workshop normally supplies this transform. Keep the real
	# companion's physics tick running while supplying deterministic input here.
	game.set_physics_process(false)
	companion.set_active(true)
	companion.update_tool_transform(seat, delta, true)
	companion.reset_to_tool()
	await frames(2)
	var falls: int = companion.debug_stats().falls
	for offset: float in [-1.2, 1.2, -0.8, 0.0]:
		var teleported := seat
		teleported.origin.x += offset
		companion.update_tool_transform(teleported, delta, true)
		await frames(1)
	check(int(companion.debug_stats().falls) == falls and str(companion.debug_stats().state_name) == "RIDING", "Explicit tool placement and teleports never fling the rider")
	for step in 18:
		var lifted := seat
		lifted.origin.y += 0.20 if step % 2 == 0 else 0.0
		companion.update_tool_transform(lifted, delta)
		await frames(1)
	check(int(companion.debug_stats().falls) == falls, "Brush lowering and raising cannot trigger a horizontal fling")
	companion.update_tool_transform(seat, delta, true)
	await frames(110) # Respect the intentional reseat cooldown.
	for step in 18:
		var dragged := seat
		dragged.origin.x += 0.18 if step % 2 == 0 else -0.18
		companion.update_tool_transform(dragged, delta)
		await frames(1)
		if int(companion.debug_stats().falls) > falls: break
	var stats: Dictionary = companion.debug_stats()
	check(int(stats.falls) == falls + 1 and str(stats.state_name) == "FALLING", "A genuinely fast horizontal reversal flings the rider once")
	check(int(stats.simulating_body_count) == 9, "Only the fling activates all nine physical bodies")
	var worst_scale_error := pose_scale_error(scale_reference_data)
	check(worst_scale_error < 0.05, "Starting a ragdoll cannot enlarge or shrink the character (relative scale error %.3f)" % worst_scale_error)
	var worst_stretch := bone_stretch(scale_reference_data)
	worst_stretch.phase = "FALLING start"
	check(float(worst_stretch.excess) < 0.03, "Starting a ragdoll preserves joint connection lengths")
	var visited := {str(stats.state_name): true}
	companion.set_active(false)
	await frames(2)
	var paused := pose_snapshot(companion)
	await frames(6)
	check(pose_snapshot(companion) == paused and not bool(companion.debug_stats().active), "Suspending a live ragdoll freezes its body and bone poses")
	worst_scale_error = maxf(worst_scale_error, pose_scale_error(scale_reference_data))
	check(pose_scale_error(scale_reference_data) < 0.05, "Freezing the ragdoll preserves the authored skeleton scale")
	var frozen_stretch := bone_stretch(scale_reference_data)
	frozen_stretch.phase = "frozen FALLING"
	if float(frozen_stretch.excess) > float(worst_stretch.excess): worst_stretch = frozen_stretch
	check(float(frozen_stretch.excess) < 0.03, "Freezing the ragdoll keeps every joint connected")
	companion.set_active(true)
	var bounded := true
	var boundary_detail := ""
	var worst_physical_stretch := physical_joint_stretch(companion, scale_reference_data)
	var fixed_nodes := true
	var recovered := false
	for step in 1440:
		# Move the actual destination gently during the return, below fling speed.
		var moving_seat := seat
		moving_seat.origin.x += sin(float(step) * delta * 0.8) * 0.18
		companion.update_tool_transform(moving_seat, delta)
		await frames(1)
		stats = companion.debug_stats()
		worst_scale_error = maxf(worst_scale_error, pose_scale_error(scale_reference_data))
		var stretch := bone_stretch(scale_reference_data)
		stretch.phase = str(stats.state_name)
		if float(stretch.excess) > float(worst_stretch.excess): worst_stretch = stretch
		visited[str(stats.state_name)] = true
		fixed_nodes = fixed_nodes and count_nodes(companion) == nodes
		if str(stats.state_name) == "FALLING":
			var physical_stretch := physical_joint_stretch(companion, scale_reference_data)
			if float(physical_stretch.excess) > float(worst_physical_stretch.excess): worst_physical_stretch = physical_stretch
			for body: Node3D in companion.find_children("*", "PhysicalBone3D", true, false):
				var p := Vector2(body.global_position.x, body.global_position.z)
				var arena: Rect2 = stats.physics_bounds
				var inside: bool = arena.grow(0.10).has_point(p) and body.global_position.y >= game.CARPET_PLANE_Y - 0.3
				if not inside and boundary_detail.is_empty(): boundary_detail = "%s at %s, arena %s" % [body.name, body.global_position, arena]
				bounded = bounded and inside
		if str(stats.state_name) == "RUNNING":
			var walking: Rect2 = stats.walking_bounds
			var p: Vector3 = stats.position
			var inside: bool = walking.grow(0.001).has_point(Vector2(p.x, p.z)) and absf(p.y - game.CARPET_PLANE_Y) < 0.001
			if not inside and boundary_detail.is_empty(): boundary_detail = "Running root at %s, walking bounds %s" % [p, walking]
			bounded = bounded and inside
		if str(stats.state_name) == "RIDING":
			recovered = true
			break
	for phase: String in ["FALLING", "GETTING_UP", "DUSTING", "RUNNING", "CLIMBING", "RIDING"]:
		check(visited.has(phase), "Fling recovery visits " + phase)
	check(recovered and int(companion.debug_stats().simulating_body_count) == 0, "Recovery reaches the moving tool and disables ragdoll simulation")
	check(worst_scale_error < 0.05, "All fall, get-up, dust, run and climb poses retain consistent character scale (worst relative error %.3f)" % worst_scale_error)
	check(float(worst_stretch.excess) < 0.03, "Fall and recovery cannot stretch disconnected limbs: %s during %s actual %.3fm, rest %.3fm, excess %.3fm, joint %s parent %s" % [worst_stretch.bone, worst_stretch.phase, worst_stretch.actual, worst_stretch.rest, worst_stretch.excess, worst_stretch.point, worst_stretch.parent_point])
	check(float(worst_physical_stretch.excess) < 0.03, "Live physics keeps connected joint anchors together: %s actual %.3fm, rest %.3fm, excess %.3fm, joint %s parent %s" % [worst_physical_stretch.bone, worst_physical_stretch.actual, worst_physical_stretch.rest, worst_physical_stretch.excess, worst_physical_stretch.point, worst_physical_stretch.parent_point])
	check(bounded, "Ragdoll bodies remain within the bounded room and above its floor tolerance: " + boundary_detail)
	check(fixed_nodes, "The full fling, recovery and climb reuse the fixed node population")
	check(int(companion.debug_stats().falls) == falls + 1, "Returning to a moving tool cannot create a second unintended fall")
	companion.reset_to_tool()
	companion.update_tool_transform(seat, delta, true)
	await frames(2)
	check(str(companion.debug_stats().state_name) == "RIDING" and count_nodes(companion) == nodes, "A rug/tool reset safely reseats the same rig")
	for repetition in 2:
		var outer_seat := seat
		outer_seat.origin.x = 2.2 if repetition == 0 else -2.2
		outer_seat.origin.z = 2.55 if repetition == 0 else -2.55
		companion.update_tool_transform(outer_seat, delta, true)
		companion.reset_to_tool()
		await frames(110)
		var prior: int = companion.debug_stats().falls
		for step in 18:
			var dragged := outer_seat
			dragged.origin.x += 0.18 if step % 2 == 0 else -0.18
			companion.update_tool_transform(dragged, delta)
			await frames(1)
			if int(companion.debug_stats().falls) > prior: break
		check(int(companion.debug_stats().falls) == prior + 1, "Repeated fling %d reuses the working ragdoll" % (repetition + 1))
		var outer_bounded := true
		var outer_detail := ""
		for _step in 45:
			await frames(1)
			stats = companion.debug_stats()
			var arena: Rect2 = stats.physics_bounds
			for body: Node3D in companion.find_children("*", "PhysicalBone3D", true, false):
				var inside: bool = arena.grow(0.10).has_point(Vector2(body.global_position.x, body.global_position.z)) and body.global_position.y >= game.CARPET_PLANE_Y - 0.3
				if not inside and outer_detail.is_empty(): outer_detail = "%s at %s, arena %s" % [body.name, body.global_position, arena]
				outer_bounded = outer_bounded and inside
		check(outer_bounded, "An outer-edge fling is caught by the private collision boundary: " + outer_detail)
		companion.reset_to_tool()
		companion.update_tool_transform(seat, delta, true)
		await frames(2)
		check(count_nodes(companion) == nodes and int(companion.debug_stats().simulating_body_count) == 0, "Repeated fling reset allocates no nodes and leaves no simulating bodies")
	game.companion_motion_reset = true
	game.set_physics_process(true)
	await frames(2)
	unchanged_play(cash, surface, debris, mask, "The complete companion fling and recovery cannot earn coins or remove dirt")

func check_production_input() -> void:
	var companion: Node3D = game.companion
	for touch_input: bool in [false, true]:
		var label := "touch" if touch_input else "mouse"
		companion.reset_to_tool()
		game.companion_motion_reset = true
		await frames(110)
		var falls: int = companion.debug_stats().falls
		var point := input_point(-0.45, 0.0, touch_input)
		pointer_button(point, true, touch_input)
		await frames(5)
		check(game.brush_dragging and int(companion.debug_stats().falls) == falls, "A real %s pickup teleports the brush without flinging the rider" % label)
		pointer_button(point, false, touch_input, touch_input)
		await frames(18)
		check(not game.brush_dragging and int(companion.debug_stats().falls) == falls, "A %s release/cancellation and hover lift cannot create a fall" % label)
		pointer_button(point, true, touch_input)
		await frames(2)
		for step in 12:
			var next := input_point(0.55 if step % 2 == 0 else -0.55, 0.0, touch_input)
			pointer_drag(next, point, touch_input)
			point = next
			await frames(1)
			if int(companion.debug_stats().falls) > falls: break
		check(int(companion.debug_stats().falls) == falls + 1, "Real %s drag events reach the workshop socket and trigger a fling" % label)
		pointer_button(point, false, touch_input)
		await frames(2)
		companion.reset_to_tool()
		game.companion_motion_reset = true
	await frames(110)
	var falls: int = companion.debug_stats().falls
	var point := input_point(0.0, 0.0, false)
	pointer_button(point, true)
	await frames(2)
	game.hud.open_upgrades()
	await frames(3)
	check(not game.brush_dragging and not bool(companion.debug_stats().active) and int(companion.debug_stats().falls) == falls, "Opening a panel during real pointer contact releases and pauses without a spurious fall")
	game.hud.close_upgrades()
	await frames(2)
	pointer_button(point, true)
	await frames(2)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(3)
	check(not game.brush_dragging and not bool(companion.debug_stats().active) and int(companion.debug_stats().falls) == falls, "Focus loss during real pointer contact releases and freezes without a spurious fall")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	pointer_button(point, false)
	await frames(3)

func run() -> void:
	ledger = root.get_node("ShopState")
	save_path = "res://.godot/level_companion_%d.json" % OS.get_process_id()
	ledger._save_path = save_path
	check(ledger.reset_progress(), "Companion integration uses a disposable current save")
	await enter_room()
	check_paid_instance("The default paid room contains its visible companion")
	if is_instance_valid(game.companion):
		check_animation_contract()
		await check_pause_and_appearance()
		await check_motion()
		await check_production_input()
	check(game.save_contract_progress(), "The companion's current paid rug checkpoints normally")
	var job: String = ledger.active_job_id
	var cash: float = ledger.cash
	await leave_room()
	ledger.free()
	ledger = State.new()
	ledger.name = "ShopState"
	ledger._save_path = save_path
	root.add_child(ledger)
	check(ledger.cash == cash and ledger.active_job_id == job and ledger.appearance == {"color_id":"violet", "hat_id":"pirate"}, "A cold ledger reload preserves appearance and the paid rug without companion income")
	await enter_room()
	check_paid_instance("Relaunching paid cleaning always restores the companion")
	await leave_room()
	# Isolated scene fixtures cover all existing paid branches without changing
	# progression gates or spending production rewards to prepare the fixture.
	for store_id in range(2, Rules.STORE_COUNT + 1):
		ledger.stores[str(store_id)] = Rules.new_branch(store_id)
		check(ledger.select_store(store_id), "Disposable fixture selects paid store %d" % store_id)
		await enter_room()
		check_paid_instance("Paid store %d includes the companion" % store_id)
		await leave_room()
	var audio := root.get_node_or_null("GameAudio")
	if audio != null: audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(2)
	await create_timer(0.15).timeout # Drain asynchronous audio from real strokes.
	for suffix: String in ["", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	print("LEVEL_COMPANION_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
