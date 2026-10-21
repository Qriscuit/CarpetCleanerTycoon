extends SceneTree
## Appearance transactions and the separate fresh-save namespace, with no UI.
const State := preload("res://scripts/shop_state.gd")
const Catalog := preload("res://scripts/avatar_catalog.gd")
var checks := 0
var failures := 0
var changed_count := 0
var appearance_count := 0
var emitted := {}

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("AVATAR STATE: " + message)

func observe_appearance(value: Dictionary) -> void:
	appearance_count += 1
	emitted = value.duplicate(true)
	# A listener cannot mutate the authoritative appearance through its event.
	value.color_id = "listener-only"

func run() -> void:
	check(State.SAVE_PATH == "user://carpet_cleaner_v1.json" and State.SAVE_VERSION == 1, "Fresh game uses its own save namespace and schema")
	check(Catalog.default_appearance() == {"color_id":"orange", "hat_id":"none"}, "The starter is orange with no hat")
	check(Catalog.COLORS.size() == 8 and Catalog.HATS.size() == 3, "All eight colors and three hat choices are available")
	for bad: Variant in [null, 9, "orange", [], {"color_id":9,"hat_id":true}, {"color_id":"missing","hat_id":"missing"}]:
		check(Catalog.sanitize_appearance(bad) == Catalog.default_appearance(), "Malformed appearance falls back safely")
	check(Catalog.sanitize_appearance({"color_id":"mint","hat_id":"missing"}) == {"color_id":"mint","hat_id":"none"}, "Sanitizing one invalid slot retains the other selection")
	var folder := "res://.godot/avatar_state_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var old_path := folder.path_join("neighborhood_shop_v1.json")
	var new_path := folder.path_join("carpet_cleaner_v1.json")
	var old_bytes := "{\"version\":3,\"cash\":987654321,\"obsolete_progress\":true}"
	var file := FileAccess.open(old_path, FileAccess.WRITE)
	file.store_string(old_bytes)
	file.close()
	var state := State.new()
	state._save_path = new_path
	root.add_child(state)
	check(state.cash == 0.0 and state.stores.size() == 1 and state.appearance == Catalog.default_appearance(), "A fresh namespace ignores the neighboring old progress")
	state.cash = 321.0
	var job: String = state.start_job()
	state.save_job_snapshot({"unique_clearance":0.2,"surface_clearance":0.3,"marker":"unfinished"})
	var branch: Dictionary = state._branch().duplicate(true)
	state.appearance_changed.connect(observe_appearance)
	state.changed.connect(func(): changed_count += 1)
	for color: Dictionary in Catalog.COLORS:
		for hat: Dictionary in Catalog.HATS:
			check(state.set_appearance(color.id, hat.id), "Every starter combination equips for free")
			check(state.appearance == {"color_id":color.id,"hat_id":hat.id} and state.cash == 321.0, "Selections update only appearance")
			check(state.active_job_id == job and state._branch() == branch, "Appearance changes preserve the unfinished rug and all store progression")
			check(FileAccess.get_file_as_string(old_path) == old_bytes, "The previous save remains byte-for-byte untouched")
	check(emitted == state.appearance and appearance_count == changed_count, "Committed changes emit the saved selection and normal state notification")
	var before: Dictionary = state._capture_state()
	var disk := FileAccess.get_file_as_string(new_path)
	var notifications := appearance_count
	check(state.set_appearance(state.appearance.color_id,state.appearance.hat_id) and appearance_count == notifications, "Equipping the current combination is idempotent")
	check(not state.set_appearance("unknown","none") and not state.set_appearance("orange","unknown") and state._capture_state() == before, "Unknown cosmetic IDs cannot alter the save")
	state._save_path = folder.path_join("missing/ledger.json")
	check(not state.set_appearance("orange","pirate") and state._capture_state() == before and appearance_count == notifications, "A real storage failure rolls back appearance and emits no success")
	state._save_path = new_path
	check(FileAccess.get_file_as_string(new_path) == disk, "A failed selection preserves the last durable save")
	state.free()
	state = State.new()
	state._save_path = new_path
	root.add_child(state)
	check(state.appearance == before.appearance and state.cash == 321.0 and state.active_job_id == job and state.job_snapshot.marker == "unfinished", "Appearance and the unfinished paid rug survive a cold reload together")
	var stable: Dictionary = state._capture_state()
	state._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await create_timer(0.03).timeout
	state._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(state._capture_state() == stable and not state.is_processing(), "Idle time and background/resume produce no money or carpet work")
	check(state.reset_progress() and state.cash == 0.0 and state.appearance == Catalog.default_appearance() and state.active_job_id.is_empty(), "Reset restores the free orange starter and clears current progression")
	check(FileAccess.get_file_as_string(old_path) == old_bytes, "Reset does not modify the previous save namespace")
	state.free()
	for path: String in [new_path, new_path + ".tmp", old_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	print("AVATAR_STATE_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
