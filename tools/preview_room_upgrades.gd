extends SceneTree
## Open a disposable, funded workshop for reviewing the renovation pass.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test. This preview never uses the player save.")
		quit(2)
		return
	var ledger := root.get_node("ShopState")
	ledger._save_path = "user://room_preview_%d.json" % OS.get_process_id()
	ledger.reset_progress()
	ledger.cash = 5000
	var game: Node = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	root.title = "Carpet Cleaner · Room upgrade preview (test save)"
