extends SceneTree
## Exercise the authored buttons, including direct F6 entry and stale legacy state.
const Routes = preload("res://scripts/scene_routes.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	await process_frame
	await process_frame

func run() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to isolate player saves")
		quit(2)
		return
	var state := root.get_node("ShopState")
	check(ProjectSettings.get_setting("application/run/main_scene") == Routes.MAIN_MENU, "F5 starts the production menu")
	check(not state.start_job().is_empty(), "Create an isolated resumable job")
	var job_id: String = state.active_job_id
	var cases := [
		[Routes.CLEANING, true],
		["res://scenes/test/rug_cleaning_gym.tscn", false],
		["res://scenes/test/starter_workshop.tscn", false],
	]
	for entry: Array in cases:
		state.contract_mode = not entry[1]
		# Practice must stay free even if a paid-mode flag was left behind.
		if entry[0] != Routes.CLEANING: state.contract_mode = true
		state.set_meta("return_home_scene", "res://scenes/test/shop_hub.tscn")
		check(change_scene_to_file(entry[0]) == OK, "Load " + entry[0])
		await settle()
		var game := current_scene
		check(game.paid_contract == entry[1], "Expected paid/practice mode in " + entry[0])
		var button: Button = game.hud.control("HomeButton")
		check(button.pressed.is_connected(game.back), "Icon Home is bound to modal-aware Back")
		button.pressed.emit()
		await settle()
		check(current_scene.scene_file_path == Routes.MAIN_MENU, "Icon Home ignores stale legacy routing and opens production home")
		check(not state.contract_mode and state.active_job_id == job_id, "Home preserves the saved job and clears paid mode")
	# Back remains navigation, even if persistence is temporarily unavailable.
	check(change_scene_to_file(Routes.CLEANING) == OK, "Reload production cleaning for failed-save Back")
	await settle()
	var unsaved_game := current_scene
	unsaved_game.soil.remaining = unsaved_game.soil.initial.size() - 1
	state._save_enabled = false
	unsaved_game.hud.control("HomeButton").pressed.emit()
	await settle()
	check(current_scene.scene_file_path == Routes.MAIN_MENU, "Back still opens the main menu when disk save fails")
	check(state.active_job_id == job_id and not state.job_snapshot.is_empty(), "Failed disk save keeps the current rug snapshot in memory")
	state._save_enabled = true
	for action: String in ["enter_gym", "enter_cleaning"]:
		check(change_scene_to_file("res://scenes/test/shop_hub.tscn") == OK, "Legacy hub remains available for testing")
		await settle()
		current_scene.call(action)
		await settle()
		check(current_scene.paid_contract == (action == "enter_cleaning"), "Legacy action keeps its intended practice/paid behavior")
		current_scene.hud.control("HomeButton").pressed.emit()
		await settle()
		check(current_scene.scene_file_path == Routes.MAIN_MENU, action + " also returns to production home")
	state.remove_meta("return_home_scene")
	print("SCENE_ROUTES_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
