extends SceneTree
## Real paid-room integration without a renderer or production clock overrides.
const State := preload("res://scripts/shop_state.gd")
const Cleaning := preload("res://scenes/production/rug_cleaning.tscn")
var checks := 0
var failures := 0
var game: Node
var ledger: Node
var save_path := ""

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MANUAL ONLY: " + message)

func settle() -> void:
	await process_frame
	if is_instance_valid(game): game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await process_frame
	await process_frame

func enter_room() -> void:
	game = Cleaning.instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await settle()
	check(game.paid_contract and game.rug_phase == game.RugPhase.CLEANING and game.soil.reveal_progress >= 1.0, "The configured paid room reaches playable cleaning")

func stable_clearance(expected_cash: float, expected_surface: float, expected_debris: float, message: String) -> void:
	check(ledger.cash == expected_cash and game.soil.surface_clearance() == expected_surface and game.soil.unique_clearance() == expected_debris, message)

func leave_room() -> void:
	if is_instance_valid(game): game.free()
	game = null
	current_scene = null
	await process_frame

func run() -> void:
	ledger = root.get_node("ShopState")
	save_path = "res://.godot/manual_only_%d.json" % OS.get_process_id()
	ledger._save_path = save_path
	check(ledger.reset_progress(), "Manual-only integration uses a disposable current save")
	await enter_room()
	check(game.find_children("*Bonzi*", "", true, false).is_empty(), "The paid room contains no automatic-cleaner nodes")
	check(is_instance_valid(game.companion) and game.companion.visible, "The visual companion is present in paid cleaning")
	var companion_stats: Dictionary = game.companion.debug_stats()
	check(companion_stats.rig_ready and companion_stats.physical_body_count == 9, "The visual companion uses its fixed nine-body rig")
	var view: Dictionary = ledger.progression_view()
	for field: String in ["bonzi_tier", "bonzi_reward", "bonzi_seconds", "bonzi_cost", "bonzi_earned", "bonzi_target", "can_upgrade_bonzi"]:
		check(not view.has(field), "Progression has no automated offer: " + field)
	var saved: Dictionary = ledger._capture_state()
	for field: String in ["automated_jobs", "routine_remainder", "return_reward", "return_seconds", "saved_wall", "banked_orders", "bonzi_tier", "bonzi_earned"]:
		check(not saved.has(field) and not saved.stores["1"].has(field), "Current save has no production field: " + field)
	check(not ledger.is_processing(), "The ledger has no periodic income processing")
	var cash: float = ledger.cash
	var surface: float = game.soil.surface_clearance()
	var debris: float = game.soil.unique_clearance()
	var job: String = ledger.active_job_id
	await create_timer(0.12).timeout
	stable_clearance(cash,surface,debris,"Idle paid gameplay changes neither wallet nor dirt clearance")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	ledger._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await create_timer(0.12).timeout
	stable_clearance(cash,surface,debris,"Background gameplay changes neither wallet nor dirt clearance")
	ledger._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(0.12).timeout
	stable_clearance(cash,surface,debris,"Returning from background grants no money or cleaning")
	check(game.save_contract_progress(), "The untouched current rug checkpoints before appearance selection")
	var branch: Dictionary = ledger._branch().duplicate(true)
	check(ledger.set_appearance("coral","pirate") and ledger.active_job_id == job and ledger._branch() == branch, "A free color and hat leave the current paid rug and store progress unchanged")
	stable_clearance(cash,surface,debris,"Appearance selection changes no wallet or dirt clearance")
	await leave_room()
	ledger.free()
	ledger = State.new()
	ledger.name = "ShopState"
	ledger._save_path = save_path
	root.add_child(ledger)
	check(ledger.cash == cash and ledger.active_job_id == job and ledger.appearance == {"color_id":"coral","hat_id":"pirate"}, "Restarting the ledger retains the reservation and appearance without extra income")
	await enter_room()
	var mask_before: PackedByteArray = game.soil.mask.get_data()
	var surface_before: float = game.soil.surface_clearance()
	for _pass_number in 3:
		for x: float in [-0.65,-0.25,0.25,0.65]:
			game.soil.begin_pass()
			game.apply_selected_tool_stroke(Vector3(x,game.CARPET_PLANE_Y,-0.8),Vector3(x,game.CARPET_PLANE_Y,0.8),0.15)
			game.soil.end_pass()
			# Freeze only cosmetic physics; mask removal and the actual ledger run.
			game.soil.set_physics_process(false)
	check(game.soil.surface_clearance() > surface_before and game.soil.mask.get_data() != mask_before, "Real manual brush strokes remove surface dust")
	check(game._flush_cleaning_earnings() and ledger.cash > cash and ledger.cash <= ledger.current_job_full_reward()/2.0, "Actual manual removal credits its saved cleaning share")
	var paid: float = ledger.cash
	check(game._flush_cleaning_earnings() and ledger.cash == paid, "Repeated flushes cannot pay the same manual work twice")
	check(ledger.active_job_id == job and ledger.manual_jobs == 0, "A partly cleaned rug remains the same unpaid-completion job")
	await leave_room()
	var audio := root.get_node_or_null("GameAudio")
	if audio != null: audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await process_frame
	await process_frame
	for suffix: String in ["", ".tmp"]:
		if FileAccess.file_exists(save_path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path+suffix))
	print("MANUAL_ONLY_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
