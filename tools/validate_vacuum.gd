extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game := (load("res://scenes/rug_cleaning_gym.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	var soil: Node = game.soil
	check(game.overhead and game.hud.control("HomeButton").visible, "Overhead gameplay provides a persistent route home")
	soil.positions[0] = Vector3(30, 0, 30)
	soil.refresh_visible_clumps()
	check(soil.batch.visible_instance_count == 559, "Offscreen clump omitted from submitted batch")
	soil.positions[0] = Vector3.ZERO
	soil.refresh_visible_clumps()
	check(soil.batch.visible_instance_count == 560, "Returning clump rendered again")
	game.reset_rug()
	game.update_progress(280, 560)
	check(game.dirty and not game.completion_icon.visible, "Halfway is not complete")
	game.reset_rug()
	for lane in [-0.85, -0.42, 0.0, 0.42, 0.85]:
		soil.stroke(Vector3(lane, 0.067, -2.5), Vector3(lane, 0.067, 1.85), 0.04)
		soil.end_pass()
		for tick in 300:
			if soil.completion_started or not soil.is_physics_processing():
				break
			soil._physics_process(1.0 / 60.0)
	check(soil.remaining == 0 and soil.completion_started, "Real sweeps trigger vacuum at 100 percent")
	check(not game.brush_dragging and not game.brush.visible, "Completion ends input and hides tool")
	var origin: Vector3 = soil.positions[0]
	soil._physics_process(0.3)
	check(soil.positions[0].y > origin.y, "Dirt lifts into the air first")
	soil._physics_process(0.5)
	check(soil.positions[0].z < origin.z, "Dirt travels toward top of screen")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../art/renders/vacuum_midpoint.png")
	for tick in 100:
		soil._physics_process(1.0 / 60.0)
	check(soil.vacuum_complete and soil.batch.visible_instance_count == 0, "All debris disappears")
	check(not soil.is_physics_processing(), "Completed vacuum sleeps")
	check(game.hud.control("InstructionComplete").visible and game.hud.control("CompletionCard").visible, "Editor-authored completion UI and next-rug choices shown")
	soil.start_vacuum()
	check(soil.vacuum_complete, "Completion cannot restart")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../art/renders/vacuum_complete.png")
	game.reset_rug()
	soil.refresh_visible_clumps()
	check(not soil.completion_started and soil.batch.visible_instance_count == 560, "Reset restores all instances")
	check(game.brush.visible and not game.tool_buttons[0].disabled, "Reset restores tool interaction")
	soil.remaining = 0
	soil.start_vacuum()
	soil._physics_process(0.4)
	game.reset_rug()
	check(not soil.is_physics_processing() and not soil.completion_started, "Reset cancels an in-flight vacuum")
	print("UI / VACUUM CHECKS: ", failures, " failures")
	game.free()
	quit(0 if failures == 0 else 1)
