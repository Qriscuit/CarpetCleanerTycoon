extends SceneTree
var failures := 0


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func set_cleanliness(game: Node, amount: float) -> void:
	game.soil.remaining = roundi(float(game.soil.initial.size()) * (1.0 - amount))
	game.soil.surface_coverage_total = float(game.soil.surface_pixel_count) * (1.0 - amount)
	game.update_contract_status()


func run() -> void:
	var game := (load("res://scenes/test/rug_cleaning_gym.tscn") as PackedScene).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	await process_frame
	var soil: Node = game.soil
	check(game.overhead and game.hud.control("HomeButton").visible, "Overhead gameplay provides a persistent route home")
	var seed_slot := -1
	for i in soil.initial_growth.size():
		if soil.initial_growth[i] > 0.1:
			seed_slot = i
			break
	check(seed_slot >= 0, "Fresh rug supplies a visible starter seed")
	if seed_slot < 0:
		game.free()
		quit(1)
		return
	soil.refresh_visible_clumps()
	check(soil.batch.visible_instance_count == 25 and soil.batch.instance_count == 560, "Only 25 starter rocks render from the 560-slot dirt pool")
	soil.positions[seed_slot] = Vector3(30, 0, 30)
	soil.refresh_visible_clumps()
	check(soil.batch.visible_instance_count == 24, "Offscreen starter rock omitted from submitted batch")
	soil.positions[seed_slot] = Vector3.ZERO
	soil.refresh_visible_clumps()
	check(soil.batch.visible_instance_count == 25, "Returning starter rock rendered again")

	set_cleanliness(game, 0.5)
	check(game.dirty and game.state_label.text == "50%" and not game.finish_button.visible, "Halfway is not complete")
	set_cleanliness(game, 0.85)
	game.finish_contract()
	check(soil.completion_started and not game.brush_dragging and not game.brush.visible, "Finish ends input and starts automatic takeaway")
	var origin: Vector3 = soil.positions[seed_slot]
	soil._physics_process(0.3)
	check(soil.positions[seed_slot].y > origin.y, "Dirt lifts into the air first")
	soil._physics_process(0.5)
	check(soil.positions[seed_slot].z < origin.z, "Dirt travels toward the top of the screen")
	for _tick in 100:
		if soil.vacuum_complete:
			break
		soil._physics_process(1.0 / 60.0)
	check(soil.vacuum_complete and soil.batch.visible_instance_count == 0, "All debris disappears before replacement")
	check(not soil.is_physics_processing(), "Completed vacuum sleeps")
	check(game.hud.get_node_or_null("%CompletionCard") == null and game.hud.get_node_or_null("%NextRugButton") == null, "No completion prompt interrupts the rug loop")
	await process_frame
	check(game.selected_rug == 1 and not soil.completion_started and soil.batch.visible_instance_count == 25, "A fresh practice rug appears automatically with only its starter rocks")
	check(game.brush.visible, "The new rug restores tool interaction")

	soil.start_vacuum(true)
	soil._physics_process(0.4)
	game.reset_rug()
	check(not soil.is_physics_processing() and not soil.completion_started, "Reset cancels an in-flight practice vacuum")
	print("UI / VACUUM CHECKS: ", failures, " failures; takeaway and automatic next rug verified")
	game.free()
	quit(0 if failures == 0 else 1)
