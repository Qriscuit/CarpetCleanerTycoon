extends SceneTree
var failures := 0
var checks := 0
var game: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../art/renders/rug_transition_"+label+".png")

func wait_ready() -> void:
	for tick in 300:
		if game.rug_phase == game.RugPhase.CLEANING: return
		await create_timer(0.02).timeout
	check(false,"Rug becomes ready within six seconds")

func finish_now(amount: float = 1.0) -> void:
	game.soil.remaining = roundi(float(game.soil.initial.size()) * (1.0-amount))
	game.soil.surface_coverage_total = float(game.soil.surface_pixel_count) * (1.0-amount)
	game.update_contract_status()
	if amount < 0.99: game.finish_rug()
	await process_frame

func run() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		quit(2)
		return
	var state := root.get_node("ShopState")
	state._save_path = "res://../art/rug_transition_test_%d.json" % OS.get_process_id()
	check(state.reset_progress(),"Isolated ledger reset")
	root.size = Vector2i(390,844)
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var scene_id: int = game.get_instance_id()
	var soil_id: int = game.soil.get_instance_id()
	var batch_id: int = game.soil.batch.get_instance_id()
	var mesh_ids: Array = []
	for mesh in game.get_node("RugDisplay/Dirty/CarpetMesh").get_children():
		mesh_ids.append(mesh.mesh.get_instance_id())
	check(game.rug_phase == game.RugPhase.ARRIVING and not game.brush.visible,"First entrance hides brush")
	check(game.soil.batch.visible_instance_count == 0,"Entrance hides pooled dirt")
	check(is_equal_approx(float(game.soil.surface_materials[0].get_shader_parameter("dust_strength")), game.soil.rug_definition.dust_strength),"Rug enters with the dirty surface already visible")
	game.begin_stroke(Vector2(190,400),false)
	check(not game.brush_dragging,"Input cannot brush arriving rug")
	await create_timer(0.46).timeout
	await capture("unrolling")
	check(game.rug_phase == game.RugPhase.ARRIVING,"Rug unrolls before dirt grows")
	check(not game.brush.visible,"Brush stays hidden throughout unroll")
	check(is_equal_approx(float(game.soil.surface_materials[0].get_shader_parameter("dust_strength")), game.soil.rug_definition.dust_strength),"Dirt texture remains fully applied while the rug unrolls")
	await create_timer(0.15).timeout
	await capture("mid_unroll")
	await create_timer(0.42).timeout
	await capture("growing")
	game.begin_stroke(Vector2(190,400),false)
	check(not game.brush_dragging and not game.brush.visible,"Growing dirt cannot be brushed early")
	await wait_ready()
	await capture("ready")
	check(game.brush.visible and game.soil.reveal_progress == 1.0,"Dirt and brush are ready after arrival")
	check(game.soil.batch.visible_instance_count == 25,"Only small starter rocks emerge; dormant pool slots wait for brushing")
	check(game.get_node("RugDisplay").position.is_equal_approx(Vector3.ZERO),"Arrived rug is centered")
	var old_scatter: Array = game.soil.positions.duplicate()
	var job_id: String = game.contract_job_id
	await finish_now()
	check(game.rug_phase == game.RugPhase.VACUUMING and not game.brush.visible,"Finishing hides brush for suction")
	game.finish_rug()
	check(state.cash == 40 and state.manual_jobs == 1,"Auto finish pays double once even on repeat request")
	await create_timer(0.5).timeout
	await capture("suction")
	check(game.get_node("RugDisplay").position.is_equal_approx(Vector3.ZERO),"Rug stays put until debris is sucked out")
	await create_timer(1.45).timeout
	await capture("rolling_away")
	check(game.rug_phase == game.RugPhase.DEPARTING,"Clean rug rolls away after suction")
	for tick in 150:
		if game.contract_job_id != job_id: break
		await create_timer(0.02).timeout
	await capture("reward")
	check(game.hud.control("Wallet").visible,"Gold counter remains visible during the reward celebration")
	await wait_ready()
	check(game.get_instance_id() == scene_id and current_scene == game,"Job completion keeps the same scene")
	check(game.soil.get_instance_id() == soil_id and game.soil.batch.get_instance_id() == batch_id,"Job completion reuses the dirt controller and GPU pool")
	var index := 0
	for mesh in game.get_node("RugDisplay/Dirty/CarpetMesh").get_children():
		check(mesh.mesh.get_instance_id() == mesh_ids[index],"Rug mesh is reused")
		index += 1
	check(game.soil.positions != old_scatter and game.soil.positions.size() == 560,"New rug randomizes the same 560 dirt slots")
	check(game.progress_fraction == 0.0 and game.contract_job_id != job_id,"Replacement rug starts a new job at zero")
	root.size = Vector2i(844,390)
	await process_frame
	await finish_now(0.85)
	await create_timer(2.95).timeout
	await capture("landscape_arrival")
	await wait_ready()
	await capture("landscape_ready")
	check(game.get_instance_id() == scene_id and state.cash == 60,"Another orientation and 85% cycle keep scene and rewards stable")
	# Leaving halfway through arrival must preserve its fresh job and pool data.
	game.start_rug_arrival()
	await create_timer(0.2).timeout
	job_id = game.contract_job_id
	var saved_scatter: Array = game.soil.positions.duplicate()
	game.return_to_shop()
	await process_frame
	await process_frame
	check(current_scene.scene_file_path == "res://scenes/production/floating_home.tscn","Back works during arrival")
	check(state.active_job_id == job_id and not state.job_snapshot.is_empty(),"Back during arrival keeps the current job")
	change_scene_to_file("res://scenes/production/rug_cleaning.tscn")
	await process_frame
	await process_frame
	game = current_scene
	check(game.soil.positions == saved_scatter,"Reentry restores the exact dirt scatter before reveal")
	await wait_ready()
	check(state.cash == 60,"Returning never duplicates a completion reward")
	game.free()
	current_scene = null
	state.set_process(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
	print("RUG_TRANSITION_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
