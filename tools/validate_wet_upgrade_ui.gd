extends SceneTree
## Phone layouts and input contracts for the separate wet-tool upgrades.
var checks := 0
var failures := 0

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Wet upgrade UI validation requires a real window for phone layout scaling")
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func fixture(store_id: int) -> Dictionary:
	return {
		"store_id": store_id, "payout_cost": 800, "early_reward": 160, "next_early": 200,
		"full_reward": 320, "next_full": 400, "tool_cost": 640, "tool_level": 0,
		"tool_name": "Water hose" if store_id >= 2 else "Brush",
		"next_tool_name": "Water hose II" if store_id >= 2 else "Wide brush",
		"can_upgrade_payout": true, "can_upgrade_tool": true,
		"wet_unlocked": store_id >= 2, "hose_level": 0, "squeegee_level": 0,
		"hose_cost": 640, "squeegee_cost": 800,
		"can_upgrade_hose": true, "can_upgrade_squeegee": true,
		"hose_power": 1.0, "next_hose_power": 1.5, "hose_radius": 0.19,
		"next_hose_radius": 0.24, "squeegee_power": 1.0, "next_squeegee_power": 1.5,
	}

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await settle()
	root.get_texture().get_image().save_png("res://../art/renders/wet_upgrades_" + label + ".png")

func run() -> void:
	# Match Workshop's runtime canvas policy before measuring landscape layouts.
	root.content_scale_size = Vector2i(720, 1000)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var hud: Node = load("res://scenes/ui/cleaning_hud.tscn").instantiate()
	root.add_child(hud)
	await settle()
	hud.initialize_wallet(1000000)
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(568, 320), Vector2i(390, 844), Vector2i(844, 390)]:
		root.size = dimensions
		await settle()
		for store_id in [1, 2, 3, 4]:
			hud.set_progression(fixture(store_id), true)
			hud.open_upgrades()
			await create_timer(0.21).timeout
			await settle()
			var label := "%s store %d" % [str(dimensions), store_id]
			check(not hud.control("FullValue").is_visible_in_tree(), "Double-reward row stays hidden " + label)
			check(hud.control("EarlyValue").text.contains("160") and hud.control("EarlyValue").text.contains("200"), "Single payout preview shows from and to " + label)
			check(not hud.control("HoseUpgradeRow").is_visible_in_tree(), "No duplicate hose upgrade " + label)
			check(hud.control("ToolDrawerTitle").text == ("Hose" if store_id >= 2 else "Brush"), "Main upgrade matches store tool " + label)
			check(hud.control("SqueegeeUpgradeRow").is_visible_in_tree() == (store_id >= 2), "Squeegee unlocks in second store " + label)
			var panel: Rect2 = hud.control("UpgradesPanel").get_global_rect()
			check(hud._safe_rect().grow(1.0).encloses(panel), "Drawer fits safe area " + label)
			var buttons: Array[Control] = []
			for node_name in ["CloseUpgradesButton", "ToolUpgradeButton", "HoseUpgradeButton", "SqueegeeUpgradeButton"]:
				var button: Button = hud.control(node_name)
				if not button.is_visible_in_tree(): continue
				check(panel.grow(1.0).encloses(button.get_global_rect()), node_name + " fits drawer " + label)
				check(hud.visible_button_at(button.get_global_rect().get_center(), hud.action_buttons()) == button, node_name + " has working touch hit test " + label)
				check(not button.focus_next.is_empty() and not button.focus_previous.is_empty(), node_name + " participates in modal focus trap " + label)
				buttons.append(button)
			for index in buttons.size():
				for other in range(index + 1, buttons.size()):
					check(not buttons[index].get_global_rect().intersects(buttons[other].get_global_rect()), "Drawer buttons do not overlap " + label)
			if store_id == 2:
				if dimensions.x <= dimensions.y:
					check(hud.control("SqueegeeUpgradeRow").global_position.y > hud.control("ToolUpgradeButton").global_position.y, "Portrait squeegee is below the main hose offer " + label)
				else:
					check(hud.control("SqueegeeUpgradeRow").global_position.x > hud.control("ToolUpgradeButton").global_position.x, "Landscape wet upgrades use adjacent columns " + label)
				await capture("store2_" + str(dimensions.x) + "x" + str(dimensions.y))
			hud.close_upgrades()
	hud.free()
	var gym: Node = load("res://scenes/ui/gym_hud.tscn").instantiate()
	root.add_child(gym)
	await settle()
	gym.set_practice_rug(1)
	gym.set_hose_upgrade(0, {})
	gym.set_squeegee_upgrade(0, 1.0)
	check(gym.control("GymSqueegeeLess").disabled and not gym.control("GymSqueegeeMore").disabled, "Gym squeegee controls clamp at base level")
	gym.set_squeegee_upgrade(4, 2.8)
	check(not gym.control("GymSqueegeeLess").disabled and gym.control("GymSqueegeeMore").disabled, "Gym squeegee controls clamp at max level")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(568, 320), Vector2i(390, 844), Vector2i(844, 390)]:
		root.size = dimensions
		await settle()
		var controls: Array[Control] = []
		for node_name in ["HomeButton", "CleaningProgress", "GymCameraAngle", "GymRug1", "GymRug2", "GymHose", "GymSqueegee", "GymReset", "GymHoseLess", "GymHoseMore", "GymSqueegeeLess", "GymSqueegeeMore"]:
			var node: Control = gym.control(node_name)
			check(gym._safe_rect().grow(1.0).encloses(node.get_global_rect()), node_name + " fits " + str(dimensions))
			controls.append(node)
		for index in controls.size():
			for other in range(index + 1, controls.size()):
				check(not controls[index].get_global_rect().intersects(controls[other].get_global_rect()), "Gym controls do not overlap: %s / %s %s" % [controls[index].name, controls[other].name, str(dimensions)])
		check(gym.control("GymSqueegeeUpgrades").global_position.y > gym.control("GymHoseUpgrades").global_position.y, "Gym squeegee follows hose " + str(dimensions))
		await capture("gym_" + str(dimensions.x) + "x" + str(dimensions.y))
	gym.set_practice_rug(0)
	check(not gym.control("GymSqueegeeUpgrades").visible, "Brush gym hides wet upgrades")
	gym.free()
	await check_store_checklist()
	print("WET_UPGRADE_UI_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check_store_checklist() -> void:
	var state := root.get_node("ShopState")
	state.set_process(false)
	state._test_ticks_msec = 0
	state._test_unix_time = 1000000.0
	check(state.reset_progress(), "Checklist uses an isolated fresh ledger")
	state.stores["2"] = preload("res://scripts/progression.gd").new_branch(2)
	state.active_store = 2
	state._load_active_branch()
	# Reproduce the reported state: every requirement except the three jobs.
	state.cash = 57400
	state.stores["2"].hose_level = 4
	state.stores["2"].squeegee_level = 4
	state.stores["2"].bonzi_earned = 150560
	var sheet: Control = load("res://scenes/ui/compact_shop.tscn").instantiate()
	root.add_child(sheet)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.show_tab("plans")
	await settle()
	check(sheet.get_node("%TravelGoals").visible, "Locked next store has a visible checklist")
	check(sheet.get_node("%TravelTitle").text.contains("Wash House"), "Checklist names the destination")
	var text: String = sheet.get_node("%TravelRequirements").text
	check(text.contains("Water hose") and text.contains("0/3") and text.contains("800") and text.contains("16000"), "Checklist names the hose, paid jobs, Bonzi target and opening cash")
	check(text.split("\n").size() == 2, "Requirements use two compact lines")
	check(sheet.get_node("%TravelHelp").text.contains("Paid rugs") and sheet.get_node("%TravelHelp").text.contains("max-level hose"), "Compact hint explains qualifying paid work")
	check(sheet.get_node("%TravelHelp").tooltip_text.contains("during a rug"), "Detailed current-rug qualification remains available")
	check(sheet.get_node("%TravelRequirements").tooltip_text.contains("57400/16000"), "Exact balances remain available without inflating the compact completed counters")
	check(sheet.action_for("intake").disabled, "Opening stays disabled while jobs are missing")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(390, 844), Vector2i(844, 390)]:
		root.size = dimensions
		await settle()
		var label := "travel " + str(dimensions)
		var rect: Rect2 = sheet.get_node("%Sheet").get_global_rect()
		check(sheet.get_global_rect().grow(1.0).encloses(rect), "Store sheet fits " + label)
		var goals: Rect2 = sheet.get_node("%TravelGoals").get_global_rect()
		check(rect.size.x <= 501.0 and goals.size.y <= 145.0, "Requirements card stays compact " + label)
		for name: String in ["TravelTitle", "TravelRequirements", "TravelHelp"]:
			check(goals.grow(1.0).encloses(sheet.get_node("%" + name).get_global_rect()), name + " stays inside checklist " + label)
		check(sheet.get_node("%MenuScroll").size.y > 80.0, "Checklist and stores can scroll " + label)
		await capture("checklist_" + str(dimensions.x) + "x" + str(dimensions.y))
	state.cash = 15999
	sheet.refresh()
	check(sheet.get_node("%TravelRequirements").text.contains("15999/16000"), "Compact currency does not round an unmet requirement into a completed one")
	check(sheet.get_node("%TravelRequirements").text.contains("Bonzi here"), "Local Bonzi requirement stays explicit without a tooltip")
	state.cash = 57400
	state.stores["2"].final_tool_jobs = 3
	sheet.refresh()
	check(not sheet.action_for("intake").disabled, "Opening enables when all visible requirements pass")
	sheet.show_tab("shop")
	check(not sheet.get_node("%TravelGoals").visible, "Checklist is only shown in Stores")
	check(sheet.rows["wide_brush"].get_node("Row/Words/Title").text.contains("Water hose"), "Shop 2 main offer is hose")
	check(sheet.rows["bonzi"].get_node("Row/Words/Title").text.contains("Squeegee"), "Shop 2 squeegee is directly below hose")
	check(state.select_store(1), "Checklist navigation visits an earlier owned store")
	sheet.show_tab("plans")
	check(sheet.get_node("%TravelGoals").visible and sheet.get_node("%TravelRequirements").text.contains("Visit High Street"), "Older stores explain where to find the next opening requirements")
	check(not sheet.action_for("intake").disabled and sheet.actions["intake"] == "store:2", "A visible View action leads to the relevant owned store")
	sheet._item_action("intake")
	check(state.active_store == 2 and sheet.get_node("%TravelRequirements").text.contains("Water hose"), "View opens the correct checklist without buying a store")
	state.stores["3"] = preload("res://scripts/progression.gd").new_branch(3)
	state.select_store(3)
	state.cash = 127999
	sheet.refresh()
	root.size = Vector2i(320, 568)
	await settle()
	check(sheet.get_node("%TravelRequirements").text.contains("127999/128000"), "Largest travel price remains exact in the compact summary")
	check(sheet.get_node("%TravelGoals").size.y <= 145.0, "Largest travel requirements still fit a compact phone card")
	sheet.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state._save_path))
