extends SceneTree
## Authored makeovers span each store's accessory ladder; extra income levels
## retain the final mesh and never promise a nonexistent visual milestone.

const Room := preload("res://scripts/room_upgrades.gd")
const Progression := preload("res://scripts/progression.gd")
const EXPECTED := [[15, 30, 45], [25, 50, 75], [30, 60, 90], [40, 80, 120], [50, 100, 150], [50, 100, 150]]
var checks := 0
var failures := 0


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Visual milestone validation requires -- --shop-test.")
		quit(2)
		return
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("VISUAL_MILESTONES: " + message)


func all_levels(level: int) -> Dictionary:
	var levels := {}
	for id: String in Room.IDS: levels[id] = level
	return levels


func panel_offer(id: String, level: int, store_id: int) -> Dictionary:
	var cap := Progression.room_level_cap(store_id)
	return {"id": id, "store_id": store_id, "level": level, "next_level": mini(level + 1, cap),
		"max_level": cap, "maxed": level >= cap, "cost": 10 if level < cap else -1,
		"can_upgrade": level < cap, "visual_step": Room.visual_step_for(id, store_id),
		"next_visual_level": Room.next_visual_level(id, level, store_id),
		"milestone_progress": Room.milestone_progress(id, level, store_id)}


func run() -> void:
	check(Room.visual_milestones_for(50, 5) == [10, 20, 30, 40, 50], "Five makeovers over50 upgrades demarcate every ten levels")
	check(Room.visual_milestones_for(175, 3) == [50, 100, 150], "Three makeovers over175 upgrades demarcate50,100,150")
	check(Room.visual_milestones_for(0, 3).is_empty() and Room.visual_milestones_for(50, 0).is_empty(), "Empty upgrade or visual ladders have no phantom milestones")
	check(Room.visual_milestones_for(3, 5) == [1, 2, 3], "More authored models than purchases cannot create duplicate or unreachable milestones")
	check(Room.visual_milestones_for(7, 3) == [2, 4, 6], "Short ladders preserve unique in-range milestones")
	check(Room.visual_count("missing") == 0 and Room.next_visual_level("missing", 0) == -1, "Unknown accessories have no makeover offer")
	var room: Node3D = load("res://scenes/room/upgrade_room.tscn").instantiate()
	root.add_child(room)
	room.set_process(false)
	for store_id: int in range(1, 7):
		var cap := Progression.room_level_cap(store_id)
		for id: String in Room.IDS:
			var milestones := Room.visual_milestones(id, store_id)
			check(milestones == EXPECTED[store_id - 1] and milestones.size() == Room.visual_count(id), "%s store%d distributes every authored makeover across its cap" % [id, store_id])
			for index: int in milestones.size():
				var milestone := milestones[index]
				check(Room.visual_tier(id, milestone - 1, store_id) == index and Room.visual_tier(id, milestone, store_id) == index + 1, "%s store%d reveals tier%d only at level%d" % [id, store_id, index + 1, milestone])
				check(Room.next_visual_level(id, milestone - 1, store_id) == milestone, "%s store%d names the real next mesh milestone%d" % [id, store_id, milestone])
				var expected_progress := 0.0 if index < milestones.size() - 1 else 1.0
				check(Room.milestone_progress(id, milestone, store_id) == expected_progress, "%s store%d resets real segments and fills after its last mesh" % [id, store_id])
			var last := milestones[-1]
			for level: int in range(last, cap + 1):
				check(Room.visual_tier(id, level, store_id) == Room.visual_count(id) and Room.next_visual_level(id, level, store_id) == -1 and not Room.tier_name(id, level, store_id).contains("Finish"), "%s store%d retains its last authored look without extra makeover at%d" % [id, store_id, level])
			if last < cap:
				check(Room.next_description(id, last, store_id).contains("Remaining upgrades increase carpet earnings"), "%s store%d explicitly describes the final income-only stretch" % [id, store_id])
			check(Room.next_description(id, cap, store_id) == "This feature is fully upgraded.", "%s store%d explicitly ends its ladder" % [id, store_id])
		for tier: int in range(4):
			var level: int = 0 if tier == 0 else int(EXPECTED[store_id - 1][tier - 1])
			room.set_levels(all_levels(level), store_id)
			for id: String in Room.IDS:
				for visible_tier: int in range(Room.visual_count(id) + 1):
					var model: Node3D = room.get_node("%s/Tier%d" % [room.GROUP_NAMES[id], visible_tier])
					check(model.visible == (visible_tier == tier), "%s store%d shows only earned model%d at%d" % [id, store_id, tier, level])
		room.set_levels(all_levels(cap + 20), store_id)
		check(room.levels.floor == cap and room.visual_tiers.floor == Room.visual_count("floor"), "Store%d room clamps to its own upgrade cap" % store_id)
	# A later store's first makeover must use its ladder when bought/retriggered.
	room.set_levels(all_levels(49), 6)
	var previous: Dictionary = room.levels.duplicate()
	var purchased := previous.duplicate()
	purchased.walls = 50
	room.play_upgrade("walls", purchased, Vector3.INF, previous)
	room.set_process(false)
	check(room.visual_tiers.walls == 0 and room.store_id == 6, "Store6 purchase defers its first real mesh at50")
	room._process(room.UPGRADE_SWAP_TIME)
	room.set_process(false)
	check(room.visual_tiers.walls == 1, "Store6 animation reveals the mesh using store6 milestones")
	room.set_levels(all_levels(15), 1)
	check(not room.is_upgrade_active() and room.store_id == 1 and room.visual_tiers.walls == 1, "Switching stores cancels pending feedback and immediately uses the new milestones")
	var panel: Control = load("res://scenes/ui/room_upgrade_panel.tscn").instantiate()
	root.add_child(panel)
	panel.show_offer({"id": "walls", "level": 14, "next_level": 15, "cost": 10, "can_upgrade": true, "visual_step": 15, "next_visual_level": 15, "milestone_progress": 14.0 / 15.0}, true)
	check(panel.get_node("%ProgressState").text == "14 / 15", "Panel counts purchases across the actual authored segment")
	for store_id: int in range(1, 7):
		var cap := Progression.room_level_cap(store_id)
		for id: String in Room.IDS:
			var milestones := Room.visual_milestones(id, store_id)
			var last := milestones[-1]
			if last < cap:
				for level: int in [last, mini(last + 1, cap - 1), cap - 1]:
					panel.refresh_offer(panel_offer(id, level, store_id), true)
					check(panel.get_node("%ProgressState").text == "%d / %d" % [level, cap]
						and not panel.get_node("%Buy").disabled and panel.get_node("%Buy").text != "Fully upgraded",
						"%s store%d final look at%d shows the remaining real upgrade ladder" % [id, store_id, level])
					check(is_equal_approx(panel._last_progress, float(level) / float(cap)) and panel._last_progress < 1.0,
						"%s store%d income progress at%d stays incomplete until its cap" % [id, store_id, level])
			panel.refresh_offer(panel_offer(id, cap, store_id), true)
			check(panel.get_node("%ProgressState").text == "Fully upgraded" and panel.get_node("%Buy").disabled
				and panel.get_node("%Buy").text == "Fully upgraded" and panel._last_progress == 1.0,
				"%s store%d completes only at its actual level%d cap" % [id, store_id, cap])
	await create_timer(0.3).timeout
	check(panel.get_node("%TransformationProgress").value == 1.0, "The actual cap fills the displayed progress bar")
	panel.free()
	room.free()
	print("VISUAL_MILESTONES_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
