extends SceneTree
## Production meshes, touch routing, and responsive composition use an isolated save.
const RoomRules := preload("res://scripts/room_upgrades.gd")
const CameraFit := preload("res://scripts/gym_camera.gd")
const Money := preload("res://scripts/money.gd")
const FIXED_CANVAS := Vector2i(720, 1000)
const CONTROLS := ["HomeButton", "CleaningProgress", "EarningsPerCarpet", "Wallet", "UpgradeButton", "FinishJobButton", "AdRewardButton"]
const ACTIONS := ["HomeButton", "UpgradeButton", "FinishJobButton", "AdRewardButton"]
var game: Node
var ledger: Node
var checks := 0
var failures := 0
var save_path := ""
var capture_folder := ""
var points := PackedVector3Array()
var point_paths: Array[String] = []
var plant_parts: Dictionary = {}
var rug_transform := Transform3D.IDENTITY
var rug_size := Vector2.ZERO
var rug_meshes: Array[Dictionary] = []
var levels := {}

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		printerr("Responsive composition requires a renderer and -- --shop-test.")
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("RESPONSIVE COMPOSITION: " + message)

func frame() -> void:
	await process_frame
	if is_instance_valid(game) and not game.application_focused: game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await RenderingServer.frame_post_draw

func settle_layout() -> void:
	await frame()
	await frame()
	game.hud._layout()
	game.frame_carpet()
	await frame()

func set_example(example: Dictionary) -> void:
	root.content_scale_size = FIXED_CANVAS if bool(example.get("reference", false)) else example.size
	root.size = example.size
	await frame()
	var units_per_pixel: Vector2 = root.get_visible_rect().size / Vector2(root.size)
	var inset: Vector4 = example.get("insets", Vector4.ZERO)
	game.hud.preview_safe_insets = Vector4(inset.x * units_per_pixel.x, inset.y * units_per_pixel.y, inset.z * units_per_pixel.x, inset.w * units_per_pixel.y)
	await settle_layout()

func capture(label: String) -> void:
	if "--composition-capture" not in OS.get_cmdline_user_args(): return
	await frame()
	check(root.get_texture().get_image().save_png(capture_folder.path_join(label + ".png")) == OK, "The new composition preview saves: " + label)

func touch(point: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)

func cache_plant_parts() -> void:
	plant_parts.clear()
	for tier: int in game.room._plant_upgrade_parts:
		for part: Dictionary in game.room._plant_upgrade_parts[tier]:
			plant_parts[part.mesh.get_instance_id()] = {"pivots":part.pivots, "tier":tier}

func deformed_vertex(mesh: MeshInstance3D, vertex: Vector3) -> Vector3:
	vertex = game.room._structural_motion.deformed_vertex(mesh, vertex)
	if not plant_parts.has(mesh.get_instance_id()): return vertex
	var part: Dictionary = plant_parts[mesh.get_instance_id()]
	var scale: Vector3 = game.room._plant_upgrade_scales.get(part.tier, Vector3.ONE)
	var pivot: Vector3 = part.pivots[0]
	var distance := INF
	for candidate: Vector3 in part.pivots:
		var next_distance := Vector2(vertex.x - candidate.x, vertex.z - candidate.z).length_squared()
		if next_distance < distance:
			distance = next_distance
			pivot = candidate
	return pivot + (vertex - pivot) * scale

func collect_visible(node: Node3D) -> void:
	if node.name == "EditableSource" or node.name == "UpgradeSelectionRing" or node.get_script() == preload("res://scripts/room_upgrade_effect.gd"): return
	if node is MeshInstance3D and node.mesh != null and node.is_visible_in_tree():
		for surface: int in node.mesh.get_surface_count():
			var vertices: PackedVector3Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				points.append(node.to_global(deformed_vertex(node, vertex)))
				point_paths.append(str(game.room.get_path_to(node)))
	for child: Node in node.get_children():
		if child is Node3D: collect_visible(child)

func projected_room() -> Rect2:
	points.clear()
	point_paths.clear()
	collect_visible(game.room)
	if points.is_empty(): return Rect2()
	var result := Rect2(game.camera.unproject_position(points[0]), Vector2.ZERO)
	for point: Vector3 in points: result = result.expand(game.camera.unproject_position(point))
	return result

func projected_rug() -> Rect2:
	var result := Rect2(game.camera.unproject_position(Vector3(-1.06, game.CARPET_PLANE_Y, -1.72)), Vector2.ZERO)
	for x: float in [-1.06, 1.06]:
		for z: float in [-1.72, 1.72]: result = result.expand(game.camera.unproject_position(Vector3(x, game.CARPET_PLANE_Y, z)))
	return result

func check_mesh_frame(label: String, target: Rect2, allow_hud: bool = false) -> void:
	var room_screen := projected_room()
	check(not points.is_empty(), label + ": independently sampled visible authored vertices exist")
	var clipped := ""
	for index: int in points.size():
		var screen: Vector2 = game.camera.unproject_position(points[index])
		if not target.grow(0.75).has_point(screen):
			clipped = "%s vertex=%s projected=%s target=%s" % [point_paths[index],points[index],screen,target]
			break
	check(clipped.is_empty(), label + ": every currently visible room vertex is framed " + clipped)
	if not allow_hud:
		for name: String in CONTROLS:
			var control: Control = game.hud.control(name)
			if control.is_visible_in_tree(): check(not control.get_global_rect().grow(1.0).intersects(room_screen), label + ": " + name + " leaves the entire authored room clear")

func check_layout(label: String) -> void:
	var metrics: Dictionary = game.hud.layout_metrics()
	var safe: Rect2 = metrics.safe_rect
	var world: Rect2 = metrics.world_rect
	var pixel_ratio: Vector2 = Vector2(root.size) / root.get_visible_rect().size
	check(world.size.x > 0 and world.size.y > 0 and safe.grow(0.5).encloses(world), label + ": the world has a positive reserved rectangle inside the safe area")
	check(game.hud.workshop_view_rect().is_equal_approx(world), label + ": public view rectangle agrees with composition metrics")
	check(game.camera.global_basis.is_equal_approx(CameraFit.workshop_basis(game.room_view_pitch_from_top, game.room_view_yaw_degrees)), label + ": every size uses the authored camera angle")
	game.finish_button.show()
	game.hud._layout()
	var rug := projected_rug()
	for index: int in CONTROLS.size():
		var name: String = CONTROLS[index]
		var control: Control = game.hud.control(name)
		if not control.is_visible_in_tree(): continue
		var rect := control.get_global_rect()
		check(safe.grow(0.75).encloses(rect), label + ": " + name + " respects safe screen edges")
		check(not rect.grow(2.0).intersects(rug), label + ": " + name + " clears the playable rug and its fringe")
		if name in ACTIONS:
			var physical: Vector2 = rect.size * pixel_ratio
			check(minf(physical.x, physical.y) >= 43.5, label + ": " + name + " is at least 44 physical pixels to touch (" + str(physical) + ")")
		for other_index: int in range(index + 1, CONTROLS.size()):
			var other: Control = game.hud.control(CONTROLS[other_index])
			if other.is_visible_in_tree(): check(not rect.grow(0.5).intersects(other.get_global_rect()), label + ": " + name + " remains separate from " + CONTROLS[other_index])
	var earnings: Control = game.hud.control("CarpetEarningsValue")
	var wallet: Control = game.hud.control("WalletValue")
	check(earnings.size.x + 0.5 >= earnings.get_combined_minimum_size().x, label + ": per-carpet earnings fit their label")
	check(wallet.size.x + 0.5 >= wallet.get_combined_minimum_size().x, label + ": long wallet amounts fit their label")
	check_mesh_frame(label, world)
	game.finish_button.hide()

func set_tier(tier: int) -> void:
	game.room.cancel_upgrade_effects()
	game.room.reset_completion_motion()
	for id: String in RoomRules.IDS: levels[id] = 0 if tier == 0 else RoomRules.visual_milestones(id)[tier - 1]
	game.room.set_levels(levels, 1)
	game.frame_carpet()

func check_carpet_input(label: String) -> void:
	for target: Vector3 in [Vector3.ZERO, Vector3(-0.7,0,-1.1), Vector3(0.7,0,-1.1), Vector3(-0.7,0,1.1), Vector3(0.7,0,1.1)]:
		target.y = game.CARPET_PLANE_Y
		var contact: Vector2 = game.camera.unproject_position(target)
		var finger: Vector2 = contact - game.TOUCH_CONTACT_OFFSET
		check(not game.hud.blocks_point(contact) and not game.hud.blocks_point(finger), label + ": carpet contact and raised finger stay outside the HUD")
		touch(finger, true)
		var reached: bool = game.brush_dragging and Vector2(game.contact_point.x,game.contact_point.z).distance_to(Vector2(target.x,target.z)) < 0.015
		if not reached: print("COMPOSITION_TOUCH %s target=%s actual=%s dragging=%s finger=%s picked=%s room_press=%s" % [label,target,game.contact_point,game.brush_dragging,finger,game.room.pick_upgrade(game.camera,finger),game.room_press_id])
		check(reached, label + ": a real touch ray reaches its intended carpet point")
		touch(finger, false, true)
		check(not game.brush_dragging, label + ": release ends a carpet stroke")
	for name: String in ["HomeButton", "UpgradeButton"]:
		var control: Control = game.hud.control(name)
		touch(control.get_global_rect().get_center(), true)
		check(game.hud_button == control and not game.brush_dragging, label + ": " + name + " owns its touch without painting the carpet")
		touch(control.get_global_rect().get_center(), false, true)

func check_stability(label: String) -> void:
	game.finish_button.hide()
	game.frame_carpet()
	var initial_transform: Transform3D = game.camera.global_transform
	var initial_size: float = game.camera.size
	var initial_world: Rect2 = game.hud.workshop_view_rect()
	game.finish_button.show()
	game.hud._layout()
	game.frame_carpet()
	check(game.camera.global_transform.is_equal_approx(initial_transform) and is_equal_approx(game.camera.size, initial_size), label + ": Finish appearing preserves the world camera")
	game.finish_button.hide()
	for amount: float in [0.0, 999.0, 9.999e32, 9.999e53, 9.999e56]:
		game.hud.sync_wallet(amount)
		game.frame_carpet()
		check(game.hud.workshop_view_rect().is_equal_approx(initial_world) and game.camera.global_transform.is_equal_approx(initial_transform) and is_equal_approx(game.camera.size, initial_size), label + ": wallet magnitude cannot move the room")
		var wallet: Label = game.hud.control("WalletValue")
		check(wallet.text == Money.format(amount), label + ": wallet value refreshes immediately")
		# Godot Containers assign a changed Label its size at the next layout pass.
		await frame()
		check(wallet.text == Money.format(amount) and wallet.size.x + 0.5 >= wallet.get_combined_minimum_size().x, label + ": even wide AM and AN suffixes fit the enlarged wallet")
		check(game.camera.global_transform.is_equal_approx(initial_transform) and is_equal_approx(game.camera.size, initial_size), label + ": rendered wallet updates leave the world camera fixed")
	game.hud.reserve_reward(40.0)
	game.hud.sync_wallet(40.0)
	game.hud.show_reward(40.0, 40.0)
	for _tick: int in 55:
		game.hud._process(0.04)
		game.frame_carpet()
		check(game.camera.global_transform.is_equal_approx(initial_transform) and is_equal_approx(game.camera.size, initial_size), label + ": coin animation leaves the camera fixed")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game.frame_carpet()
	check(game.hud.workshop_view_rect().is_equal_approx(initial_world) and game.camera.global_transform.is_equal_approx(initial_transform) and is_equal_approx(game.camera.size, initial_size), label + ": resume restores the same layout and room camera")
	game.hud.sync_wallet(ledger.cash)

func check_room_input(label: String) -> void:
	var targets := [
		{"id":"floor","local":Vector3(-1.6,0.025,0)},
		{"id":"floor","local":Vector3(1.6,0.025,0)},
		{"id":"railings","local":Vector3(-2.16,0.44,0)},
		{"id":"railings","local":Vector3(2.16,0.44,0)},
		{"id":"window","local":game.room.ANCHORS.window},
		{"id":"walls","local":Vector3(0,1.58,-2.86)},
	]
	for x: float in [-1.94,1.94]:
		for z: float in [-2.42,2.42]: targets.append({"id":"plants","local":Vector3(x,0.70,z)})
	for target: Dictionary in targets:
		var point: Vector2 = game.camera.unproject_position(game.room.to_global(target.local))
		check(game.room.pick_upgrade(game.camera,point) == target.id, label + ": authored " + target.id + " can be picked at its visible point")
		touch(point,true)
		check(game.room_press_id == target.id and not game.brush_dragging, label + ": " + target.id + " owns an accessory touch outside the carpet")
		touch(point,false)
		check(game.hud.room_panel.visible and game.hud.room_panel.selected_id == target.id and game.soil.simulation_suspended, label + ": releasing " + target.id + " opens its own offer and pauses cleaning")
		game.hud.close_upgrades()
		game.room.clear_selection()
		check(not game.hud.upgrades_open() and not game.soil.simulation_suspended, label + ": closing the accessory offer resumes carpet input")

func check_upgrade_poses(label: String) -> void:
	game.room.set_process(false)
	for tier: int in range(1,4):
		for id: String in RoomRules.IDS:
			set_tier(tier - 1)
			var previous: Dictionary = levels.duplicate()
			var next: Dictionary = levels.duplicate()
			next[id] = RoomRules.visual_milestones(id)[tier - 1]
			game.room.play_upgrade(id, next, Vector3.INF, previous)
			game.room.set_process(false)
			var elapsed := 0.0
			for time: float in [0.0,0.18,0.38,0.55,0.90]:
				game.room._process_upgrades(time - elapsed)
				elapsed = time
				check_mesh_frame("%s %s tier%d pose%.2f" % [label,id,tier,time], game.hud.workshop_view_rect())
				check(game.get_node("RugDisplay").global_transform.is_equal_approx(rug_transform) and game.soil.RUG_HALF == rug_size, label + ": room animation preserves carpet geometry and cleaning contact")
				var unchanged := true
				for model: Dictionary in rug_meshes:
					unchanged = unchanged and model.node.global_transform.is_equal_approx(model.transform) and model.node.mesh.get_aabb().is_equal_approx(model.bounds)
				check(unchanged, label + ": actual binding, pile and fringe meshes retain their original bounds and world transforms")
			game.room.cancel_upgrade_effects()

func check_open_window(label: String) -> void:
	var safe: Rect2 = game.hud._safe_rect().grow(-16.0)
	for tier: int in range(4):
		set_tier(tier)
		for amount: float in [0.0,0.25,0.5,0.75,1.0]:
			game.room.set_window_open_amount(amount)
			CameraFit.frame_departure(game.camera,root.get_visible_rect().size,safe,game.camera.size,game._workshop_geometry_bounds(true),game.room_view_pitch_from_top,game.room_view_yaw_degrees)
			check_mesh_frame("%s open-window tier%d %.2f" % [label,tier,amount],safe,true)
		var opening: Dictionary = game.room.window_clear_aperture_world()
		check(opening.width > 2.12, label + ": every window leaves the unchanged rug a clear departure corridor")
	game.room.reset_completion_motion()
	game.frame_carpet()

func check_automatic_resize() -> void:
	game.hud.preview_safe_insets = Vector4.ZERO
	root.content_scale_size = FIXED_CANVAS
	set_tier(3)
	for size: Vector2i in [Vector2i(320,568),Vector2i(568,320),Vector2i(768,1024),Vector2i(390,844)]:
		root.size = size
		await frame()
		await frame()
		await frame()
		var metrics: Dictionary = game.hud.layout_metrics()
		check(metrics.safe_rect.size.is_equal_approx(root.get_visible_rect().size), "Automatic resize updates the safe rectangle before a manual layout call at " + str(size))
		check_mesh_frame("Automatic resize " + str(size), metrics.world_rect)

func normalized_rect(rect: Rect2) -> Rect2:
	var viewport: Vector2 = root.get_visible_rect().size
	return Rect2(rect.position / viewport, rect.size / viewport)

func density_sample() -> Dictionary:
	var result := {}
	var viewport: Vector2 = root.get_visible_rect().size
	for name: String in ["HomeButton","UpgradeButton","FinishJobButton","Wallet","CleaningProgress","EarningsPerCarpet"]:
		var control: Control = game.hud.control(name)
		result[name] = normalized_rect(control.get_global_rect())
	for name: String in ["WalletValue","ProgressValue","CarpetEarningsValue","PerCarpetLabel"]:
		var label: Label = game.hud.control(name)
		# Use the visible font scale rather than an implementation scale formula.
		result[name] = label.get_theme_font_size("font_size") * label.get_global_transform().get_scale().y / viewport.x
	var metrics: Dictionary = game.hud.layout_metrics()
	for name: String in ["safe_rect","header_rect","action_rect","world_rect"]:
		result[name] = normalized_rect(metrics[name])
	result["mode"] = metrics.mode
	return result

func compare_density(actual: Dictionary, expected: Dictionary, label: String) -> void:
	check(actual.mode == "portrait" and actual.mode == expected.mode, label + ": an equivalent phone keeps its portrait composition")
	for name: String in expected:
		if name == "mode": continue
		if expected[name] is Rect2:
			var a: Rect2 = actual[name]
			var b: Rect2 = expected[name]
			var relative_size := (a.size - b.size).abs() / b.size.max(Vector2(0.01,0.01))
			var delta_position := (a.position - b.position).abs()
			check(maxf(relative_size.x,relative_size.y) <= 0.03 and maxf(delta_position.x,delta_position.y) <= 0.005, label + ": " + name + " retains its screen proportions (actual=" + str(a) + ", baseline=" + str(b) + ")")
		else:
			var ratio := float(actual[name]) / float(expected[name])
			check(absf(ratio - 1.0) <= 0.03, label + ": " + name + " text retains its readable screen proportion")

func check_density_invariance() -> void:
	set_tier(3)
	var phone_sizes := [Vector2i(390,844),Vector2i(591,1280),Vector2i(1080,2340),Vector2i(1440,3120)]
	for with_safe_area: bool in [false,true]:
		for large_amounts: bool in [false,true]:
			game.hud.set_progression({"store_id":6 if large_amounts else 1,"full_reward":4e32 if large_amounts else 40.0,"tool_cost":-1.0},true)
			game.hud.initialize_wallet(9.999e56 if large_amounts else 40.0)
			game.hud.set_ad_offer(0.0,false)
			var baseline := {}
			for size: Vector2i in phone_sizes:
				var physical_factor := float(size.x) / 390.0
				var insets := Vector4(0,44,0,34) * physical_factor if with_safe_area else Vector4.ZERO
				for reference: bool in [true,false]:
					var example := {"size":size,"insets":insets,"reference":reference}
					await set_example(example)
					var label := "Density %dx%d %s %s %s" % [size.x,size.y,"reference" if reference else "native","safe" if with_safe_area else "plain","large" if large_amounts else "ordinary"]
					check(root.size == size, label + ": the renderer actually exercises the requested physical resolution")
					var sample := density_sample()
					if baseline.is_empty():
						baseline = sample
						var home: Control = game.hud.control("HomeButton")
						var pixels: Vector2 = home.get_global_rect().size * Vector2(root.size) / root.get_visible_rect().size
						check(absf(pixels.y - 56.0) <= 1.0, label + ": the390px phone keeps a readable56px action")
					else:
						compare_density(sample,baseline,label)
					check_layout(label)
					if not with_safe_area and size != Vector2i(390,844) and reference:
						await capture("density_%s_%dx%d_reference" % ["large" if large_amounts else "ordinary",size.x,size.y])
	game.hud.set_progression(ledger.progression_view(),true)
	game.hud.initialize_wallet(ledger.cash)

func canvas_z(item: CanvasItem) -> int:
	var total := item.z_index
	var current := item
	while current.z_as_relative:
		var parent := current.get_parent() as CanvasItem
		if parent == null: break
		total += parent.z_index
		current = parent
	return total

func drawer_fixture(variant: String) -> Dictionary:
	var wet := variant in ["wet","wet_max"]
	var maximum := variant in ["max","wet_max"]
	return {
		"store_id":7 if wet else 1, "full_reward":400000.0,
		"tool_cost":-1.0 if maximum else 80.0, "can_upgrade_tool":not maximum,
		"tool_name":"Water hose" if wet else "Hand brush",
		"next_tool_name":"Water hose II" if wet else "Wide brush",
		"wet_unlocked":wet,
		"tool_width":1.0, "next_tool_width":1.25, "tool_power":1.0, "next_tool_power":1.5,
		"hose_cost":-1.0 if maximum else 80.0, "can_upgrade_hose":not maximum, "hose_power":1.0, "next_hose_power":1.5,
		"squeegee_cost":-1.0 if maximum else 80.0, "can_upgrade_squeegee":not maximum, "squeegee_power":1.0, "next_squeegee_power":1.5,
	}

func assert_drawer_geometry(label: String) -> Array[Button]:
	var hud: CanvasLayer = game.hud
	var safe: Rect2 = hud._safe_rect()
	var panel: Control = hud.control("UpgradesPanel")
	var panel_rect := panel.get_global_rect()
	var scroll := hud.get_node("%ToolCardsScroll") as ScrollContainer
	check(safe.grow(0.75).encloses(panel_rect), label + ": the whole drawer remains inside the safe display")
	check(canvas_z(hud.control("UpgradeSheet")) > canvas_z(hud.control("Wallet")), label + ": the sheet and its dimmer draw above the wallet")
	check(scroll.clip_contents and panel_rect.grow(0.75).encloses(scroll.get_global_rect()), label + ": tool artwork scrolls inside a clipped region fully covered by its panel")
	var buttons: Array[Button] = []
	for name: String in ["CloseUpgradesButton","ToolUpgradeButton","HoseUpgradeButton","SqueegeeUpgradeButton"]:
		var button := hud.control(name) as Button
		if not button.is_visible_in_tree(): continue
		var rect := button.get_global_rect()
		check(safe.grow(0.75).encloses(rect) and panel_rect.grow(0.75).encloses(rect), label + ": " + name + " is fully covered by its own panel and safe screen")
		var physical: Vector2 = rect.size * Vector2(root.size) / root.get_visible_rect().size
		check(minf(physical.x,physical.y) >= 43.5, label + ": " + name + " keeps a44px physical target")
		if not button.disabled: check(hud.visible_button_at(rect.get_center(),game.touch_buttons) == button, label + ": " + name + " is the intended modal hit target")
		buttons.append(button)
	for index: int in buttons.size():
		for other: int in range(index + 1,buttons.size()):
			check(not buttons[index].get_global_rect().grow(0.5).intersects(buttons[other].get_global_rect()), label + ": " + buttons[index].name + " does not overlap " + buttons[other].name)
	var done: Control = hud.control("CloseUpgradesButton")
	var buy: Control = hud.control("ToolUpgradeButton")
	check(not scroll.is_ancestor_of(done) and not scroll.is_ancestor_of(buy), label + ": Done and the main Buy remain fixed outside the artwork scroller")
	return buttons

func check_tool_drawer() -> void:
	var requested: Array[String] = []
	var observers := {
		"tool":func() -> void: requested.append("tool"),
		"hose":func() -> void: requested.append("hose"),
		"squeegee":func() -> void: requested.append("squeegee"),
	}
	var handlers := {"tool":Callable(game,"_purchase_tool"),"hose":Callable(game,"_purchase_hose"),"squeegee":Callable(game,"_purchase_squeegee")}
	# Exercise real input routing while synthetic wet/max offers remain read-only.
	for kind: String in handlers:
		var signal_name := "request_" + kind + "_upgrade"
		game.hud.disconnect(signal_name,handlers[kind])
		game.hud.connect(signal_name,observers[kind])
	var cases := [
		{"size":Vector2i(320,568),"reference":true},
		{"size":Vector2i(568,320),"reference":true},
		{"size":Vector2i(1080,2340),"reference":true},
		{"size":Vector2i(568,320),"insets":Vector4(20,0,20,16),"reference":true},
		{"size":Vector2i(844,390),"insets":Vector4(44,0,34,20),"reference":true},
	]
	for example: Dictionary in cases:
		await set_example(example)
		for variant: String in ["ordinary","wet","max","wet_max"]:
			var label := "Drawer %dx%d %s%s" % [example.size.x,example.size.y,variant," safe" if example.get("insets",Vector4.ZERO) != Vector4.ZERO else ""]
			game.hud.set_progression(drawer_fixture(variant),true)
			game.hud.initialize_wallet(1000000.0)
			game.hud.open_upgrades()
			await create_timer(0.22).timeout
			await frame()
			var buttons := assert_drawer_geometry(label)
			var scroll := game.hud.get_node("%ToolCardsScroll") as ScrollContainer
			var fixed_done: Rect2 = game.hud.control("CloseUpgradesButton").get_global_rect()
			var fixed_buy: Rect2 = game.hud.control("ToolUpgradeButton").get_global_rect()
			check(scroll.scroll_vertical == 0, label + ": reopening the drawer starts its cards at the top")
			var overflow: float = scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page
			var origin := scroll.get_global_rect().get_center()
			var relative := Vector2(0.0,-minf(scroll.get_global_rect().size.y * 0.30,60.0 * root.get_visible_rect().size.y / root.size.y))
			touch(origin,true)
			var swipe := InputEventScreenDrag.new()
			swipe.index = 0
			swipe.position = origin + relative
			swipe.relative = relative
			root.push_input(swipe,true)
			touch(origin + relative,false,true)
			await frame()
			check(scroll.scroll_vertical > 0 if overflow > 0.5 else scroll.scroll_vertical == 0, label + ": a real finger swipe scrolls overflowing cards and respects a fitted body")
			check(game.hud.upgrades_open() and not game.brush_dragging, label + ": scrolling stays inside the modal and never paints the carpet")
			check(game.hud.control("CloseUpgradesButton").get_global_rect().is_equal_approx(fixed_done) and game.hud.control("ToolUpgradeButton").get_global_rect().is_equal_approx(fixed_buy), label + ": scrolling cards cannot move Done or Buy")
			for button: Button in buttons:
				if button.name == "CloseUpgradesButton": continue
				requested.clear()
				var kind := "tool" if button.name == "ToolUpgradeButton" else ("hose" if button.name == "HoseUpgradeButton" else "squeegee")
				var point := button.get_global_rect().get_center()
				touch(point,true)
				check(not game.brush_dragging, label + ": pressing Buy never paints the rug beneath the modal")
				touch(point,false)
				check(requested.is_empty() if button.disabled else requested == [kind], label + ": a real release requests only its intended " + kind + " upgrade")
			await capture("drawer_%s_%dx%d%s" % [variant,example.size.x,example.size.y,"_safe" if example.get("insets",Vector4.ZERO) != Vector4.ZERO else ""])
			var done: Button = game.hud.control("CloseUpgradesButton")
			touch(done.get_global_rect().get_center(),true)
			touch(done.get_global_rect().get_center(),false)
			check(not game.hud.upgrades_open() and not game.soil.simulation_suspended, label + ": a real Done touch closes the drawer and resumes carpet input")
	for kind: String in handlers:
		var signal_name := "request_" + kind + "_upgrade"
		game.hud.disconnect(signal_name,observers[kind])
		game.hud.connect(signal_name,handlers[kind])
	game.hud.set_progression(ledger.progression_view(),true)
	game.hud.initialize_wallet(ledger.cash)

func check_practice() -> void:
	game.free()
	current_scene = null
	game = load("res://scenes/test/rug_cleaning_gym.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frame()
	for size: Vector2i in [Vector2i(320,568),Vector2i(568,320)]:
		await set_example({"size":size,"reference":true})
		check(not game.hud.control("EarningsPerCarpet").visible, "Free practice has no paid earnings plaque at " + str(size))
		var safe: Rect2 = game.hud.layout_metrics().safe_rect
		var world: Rect2 = game.hud.workshop_view_rect()
		check(safe.grow(0.5).encloses(world), "Free practice also reserves a safe world rectangle")
		var carpet := projected_rug()
		for name: String in ["HomeButton","CleaningProgress","Wallet","UpgradeButton"]:
			var control: Control = game.hud.control(name)
			if control.is_visible_in_tree(): check(safe.grow(0.75).encloses(control.get_global_rect()) and not control.get_global_rect().grow(2.0).intersects(carpet), "Free practice " + name + " stays reachable and clears the carpet")
		var finger: Vector2 = game.camera.unproject_position(Vector3(0,game.CARPET_PLANE_Y,0)) - game.TOUCH_CONTACT_OFFSET
		touch(finger,true)
		check(game.brush_dragging, "Free practice retains real carpet touch input after resize")
		touch(finger,false,true)

func run() -> void:
	ledger = root.get_node("ShopState")
	ledger.set_process(false)
	ledger._test_ticks_msec = 0
	ledger._test_unix_time = 1800000000.0
	save_path = "res://.godot/responsive_composition_%d.json" % OS.get_process_id()
	ledger._save_path = save_path
	check(ledger.reset_progress(), "The layout run uses a disposable player ledger")
	ledger.cash = 1000.0
	ledger.save_state()
	game = load("res://scenes/production/rug_cleaning.tscn").instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frame()
	await frame()
	if not game.hud.has_method("layout_metrics") or not game.hud.has_method("workshop_view_rect"):
		check(false,"The responsive HUD exposes its production layout rectangles")
		finish()
		return
	cache_plant_parts()
	rug_transform = game.get_node("RugDisplay").global_transform
	rug_size = game.soil.RUG_HALF
	for node: Node in game.get_node("RugDisplay").find_children("*", "MeshInstance3D", true, false):
		rug_meshes.append({"node":node,"transform":node.global_transform,"bounds":node.mesh.get_aabb()})
	check(is_equal_approx(rug_size.x,1.0) and is_equal_approx(rug_size.y,1.66), "The playable soil keeps the authored carpet dimensions")
	capture_folder = ProjectSettings.globalize_path("res://../art/renders/composition_after")
	DirAccess.make_dir_recursive_absolute(capture_folder)
	var cases := [
		{"size":Vector2i(320,568)}, {"size":Vector2i(568,320)},
		{"size":Vector2i(390,844)}, {"size":Vector2i(844,390)},
		{"size":Vector2i(320,900)}, {"size":Vector2i(900,320)},
		{"size":Vector2i(768,1024)}, {"size":Vector2i(1024,768)},
		{"size":Vector2i(390,844),"insets":Vector4(0,44,0,34)},
		{"size":Vector2i(844,390),"insets":Vector4(44,0,34,20)},
		{"size":Vector2i(320,568),"reference":true},
		{"size":Vector2i(568,320),"reference":true},
		{"size":Vector2i(390,844),"insets":Vector4(0,44,0,34),"reference":true},
		{"size":Vector2i(844,390),"insets":Vector4(44,0,34,20),"reference":true},
		{"size":Vector2i(768,1024),"reference":true}, {"size":Vector2i(1024,768),"reference":true},
	]
	for example: Dictionary in cases:
		await set_example(example)
		var label := "%dx%d%s%s" % [example.size.x,example.size.y,"_reference" if bool(example.get("reference",false)) else "", "_safe" if example.get("insets",Vector4.ZERO) != Vector4.ZERO else ""]
		game.hud.sync_wallet(999900000000000000000000000000000.0)
		for tier: int in range(4):
			set_tier(tier)
			check_layout(label + " tier%d" % tier)
			if tier in [0,3]: await capture(("starter_" if tier == 0 else "mastered_") + label)
		check_carpet_input(label)
		check_room_input(label)
		await check_stability(label)
		game.hud.set_ad_offer(400000.0, true)
		game.frame_carpet()
		check_layout(label + " optional ad")
		game.hud.set_ad_offer(0.0, false)
		game.frame_carpet()
		if example.size in [Vector2i(320,568),Vector2i(568,320)] and not bool(example.get("reference",false)):
			check_upgrade_poses(label)
			check_open_window(label)
	await check_automatic_resize()
	await check_density_invariance()
	await check_tool_drawer()
	await check_practice()
	finish()

func finish() -> void:
	if is_instance_valid(game): game.free()
	current_scene = null
	var audio := root.get_node_or_null("GameAudio")
	if audio != null: audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if FileAccess.file_exists(save_path + ".tmp"): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + ".tmp"))
	print("RESPONSIVE_COMPOSITION_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
