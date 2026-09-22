extends SceneTree
## Renderer-backed, deterministic hose upgrade/soak integration checks.
## Godot --path CarpetToy --script ../tools/validate_hose_upgrades.gd -- --shop-test

const Routes = preload("res://scripts/scene_routes.gd")
const Profile = preload("res://scripts/water_hose_profile.gd")
const CONTROL_NAMES := ["HomeButton", "CleaningProgress", "FinishJobButton", "GymRug1", "GymRug2", "GymBrush", "GymHose", "GymSqueegee", "GymReset", "GymHoseLess", "GymHoseMore"]

var checks := 0
var failures := 0
var game: Node
var water: Node
var soil: Node


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to keep player saves isolated")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Hose upgrade validation requires a real renderer for layout and captures")
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
	await RenderingServer.frame_post_draw


func advance_water(seconds: float) -> void:
	# No awaits: every comparison receives exactly the same simulated duration.
	var remaining := seconds
	while remaining > 0.000001 and water.is_processing():
		var step := minf(remaining, 1.0 / 60.0)
		water._process(step)
		remaining -= step


func start_fixture(level: int, position := Vector3(0.0, 0.60, 0.0)) -> void:
	game.reset_rug()
	game.set_hose_upgrade_level(level)
	water.set_emitter(true, position, Vector3.DOWN)


func stop_fixture() -> void:
	water.set_emitter(false, water.nozzle, Vector3.DOWN)
	advance_water(1.5)
	soil._process(0.0)


func tap(button: Button, canceled := false) -> void:
	for down: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 1
		event.position = button.get_global_rect().get_center()
		event.pressed = down
		event.canceled = canceled and not down
		root.push_input(event, true)


func click(button: Button) -> void:
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = down
		root.push_input(event, true)


func mask_stats(center := Vector2.ZERO, halo_start := 0.26) -> Dictionary:
	var bytes: PackedByteArray = soil.wet_mask.get_data()
	var total := 0
	var occupied := 0
	var outside := 0
	var halo_total := 0
	var farthest := 0.0
	for y in soil.MASK_SIZE.y:
		for x in soil.MASK_SIZE.x:
			var index: int = y * soil.MASK_SIZE.x + x
			var value := int(bytes[index])
			total += value
			if soil.surface_pixels[index] == 0 and value > 0:
				outside += 1
			if value == 0:
				continue
			var point: Vector2 = (Vector2(x + 0.5, y + 0.5) / Vector2(soil.MASK_SIZE) - Vector2.ONE * 0.5) * soil.RUG_HALF * 2.0
			var distance := point.distance_to(center)
			if distance > halo_start:
				halo_total += value
			if value > 5:
				occupied += 1
				farthest = maxf(farthest, distance)
	return {"hash": hash(bytes), "total": total, "occupied": occupied, "outside": outside, "halo_total": halo_total, "farthest": farthest}


func water_at(point: Vector2) -> float:
	var uv: Vector2 = (point + soil.RUG_HALF) / (soil.RUG_HALF * 2.0)
	var pixel: Vector2i = Vector2i(uv * Vector2(soil.MASK_SIZE)).clamp(Vector2i.ZERO, soil.MASK_SIZE - Vector2i.ONE)
	return soil.water_values[pixel.y * soil.MASK_SIZE.x + pixel.x]


func node_count(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += node_count(child)
	return count


func capture(label: String) -> void:
	# Freeze simulated water during renderer waits, keeping timing reproducible.
	var resume: bool = water.is_processing()
	water.set_process(false)
	soil._process(0.0)
	await settle()
	var output := "res://../art/renders/hose_upgrade_" + label + ".png"
	check(root.get_texture().get_image().save_png(output) == OK, "Capture " + label)
	print("HOSE_UPGRADE_CAPTURE ", ProjectSettings.globalize_path(output))
	water.set_process(resume)


func check_profiles() -> void:
	check(Profile.for_level(-99) == Profile.for_level(0), "Negative upgrade levels clamp to the base spout")
	check(Profile.for_level(99) == Profile.for_level(Profile.MAX_LEVEL), "Large upgrade levels clamp to the final spout")
	for level in range(Profile.MAX_LEVEL + 1):
		var profile := Profile.for_level(level)
		check(int(profile.level) == level, "Profile %d reports its level" % level)
		check(float(profile.max_spread_radius) > float(profile.wet_radius) and float(profile.wet_radius) > float(profile.impact_radius), "Profile %d has a nested impact, wet core and wider soak halo" % level)
		if level == 0:
			continue
		var previous := Profile.for_level(level - 1)
		for key in ["stream_tip_radius", "impact_radius", "wet_radius", "max_spread_radius", "soak_multiplier", "spread_speed"]:
			check(float(profile[key]) > float(previous[key]), "%s increases at level %d" % [key, level])


func check_stationary_growth() -> void:
	start_fixture(0)
	advance_water(0.8)
	var early := mask_stats()
	var early_soak: Dictionary = water.debug_stats().soak
	check(early.occupied > 0 and early_soak.active_spots == 1, "A stationary stream creates one anchored soaking area")
	check(float(early_soak.max_radius) > float(water.profile.wet_radius), "Soaking already extends beyond the direct contact radius")
	advance_water(5.2)
	var grown := mask_stats()
	var grown_soak: Dictionary = water.debug_stats().soak
	check(int(grown.occupied) > int(early.occupied) * 1.3, "Holding the same point grows genuinely wetted carpet area")
	check(int(grown.total) > int(early.total) and int(grown.halo_total) > int(early.halo_total), "Core absorption and passive halo wetness accumulate without pointer motion")
	check(float(grown_soak.max_radius) > float(early_soak.max_radius) + 0.10, "Stationary reservoir radius expands gradually over time")
	check(float(grown_soak.max_radius) <= float(water.profile.max_spread_radius) + 0.00001, "Passive spread remains bounded by its upgrade profile")
	check(float(grown.farthest) > float(water.profile.wet_radius) + 0.06, "The carpet mask, not just a visual splash, grows beyond the initial AOE")
	check(int(grown.outside) == 0 and soil.water_clearance() < 0.50, "A held spout stays local and never paints outside the carpet")
	stop_fixture()
	check(not water.is_processing() and int(water.debug_stats().soak.active_spots) == 0, "Release retires the column, droplets and residual soaking within 1.5 seconds")
	var settled := mask_stats()
	advance_water(4.0)
	check(mask_stats().hash == settled.hash, "Retired reservoirs cannot continue wetting indefinitely")


func check_upgrade_effects() -> void:
	start_fixture(0)
	advance_water(0.34)
	var low := mask_stats()
	var low_center := water_at(Vector2.ZERO)
	var low_nozzle: float = water.ring_data[0].w
	var low_upper: float = water.ring_data[2].w
	var low_middle: float = water.ring_data[8].w
	var low_lower: float = water.ring_data[11].w
	var low_tip: float = water.ring_data[-1].w
	check(low_center > 0.0 and low_center < 1.0, "Short comparison samples absorption before the base core saturates")
	start_fixture(Profile.MAX_LEVEL)
	advance_water(0.34)
	var high := mask_stats()
	var high_center := water_at(Vector2.ZERO)
	var high_upper: float = water.ring_data[2].w
	var high_middle: float = water.ring_data[8].w
	var high_lower: float = water.ring_data[11].w
	var high_tip: float = water.ring_data[-1].w
	check(high_center > low_center + 0.1, "The upgraded spout absorbs water faster at equal elapsed time")
	check(int(high.occupied) > int(low.occupied) * 1.5 and int(high.total) > int(low.total) * 1.5, "The upgraded spout wets a wider area and deposits more water at equal time")
	check(is_equal_approx(water.ring_data[0].w, low_nozzle) and is_equal_approx(low_nozzle, water.NOZZLE_RADIUS), "Upgrades preserve the exact nozzle attachment radius")
	check(low_upper <= water.NOZZLE_RADIUS * 1.01 and high_upper <= water.NOZZLE_RADIUS * 1.01, "The first two tube spans stay seated at nozzle scale before widening")
	check(low_middle >= water.NOZZLE_RADIUS * 1.08, "Even the starter spout has a visibly fuller column midpoint")
	check(high_middle > 0.095 and high_middle > low_middle + 0.035, "The final upgrade clearly enlarges the column by its midpoint")
	check(low_lower > low_middle and low_lower < low_tip and high_lower > high_middle and high_lower < high_tip, "The lower column continues widening smoothly toward its exact contact radius")
	check(high_tip > low_tip * 1.5 and is_equal_approx(high_tip, water.profile.stream_tip_radius), "The actual lower water-column radius widens with the spout upgrade")
	var previous_middle := -1.0
	var previous_lower := -1.0
	for level in range(Profile.MAX_LEVEL + 1):
		start_fixture(level)
		advance_water(0.34)
		var level_middle: float = water.ring_data[8].w
		var level_lower: float = water.ring_data[11].w
		check(is_equal_approx(water.ring_data[0].w, water.NOZZLE_RADIUS), "Spout level %d keeps an exact nozzle joint" % (level + 1))
		check(is_equal_approx(water.ring_data[-1].w, water.profile.stream_tip_radius), "Spout level %d joins its authored contact radius exactly" % (level + 1))
		var previous_ring := float(water.ring_data[0].w)
		for ring in range(1, water.RING_COUNT):
			var current_ring := float(water.ring_data[ring].w)
			check(current_ring >= previous_ring - 0.000001, "Spout level %d widens monotonically at ring %d" % [level + 1, ring])
			check(current_ring - previous_ring <= 0.02, "Spout level %d keeps adjacent radius steps smooth at ring %d" % [level + 1, ring])
			previous_ring = current_ring
		if level > 0:
			check(level_middle > previous_middle and level_lower > previous_lower, "Spout level %d monotonically enlarges the middle and lower column" % (level + 1))
		previous_middle = level_middle
		previous_lower = level_lower
	start_fixture(0)
	advance_water(3.0)
	var low_halo := mask_stats(Vector2.ZERO, 0.46)
	var low_radius: float = water.debug_stats().soak.max_radius
	start_fixture(Profile.MAX_LEVEL)
	advance_water(3.0)
	var high_halo := mask_stats(Vector2.ZERO, 0.46)
	var held_timing: Dictionary = water.debug_stats()
	print("HOSE_UPGRADE_CPU level=5 held_total_usec=%d process_count=%d mean_usec=%.1f max_usec=%d" % [int(held_timing.cpu_usec_total), int(held_timing.process_count), float(held_timing.cpu_usec_total) / maxf(float(held_timing.process_count), 1.0), int(held_timing.cpu_usec_max)])
	check(float(water.debug_stats().soak.max_radius) > low_radius + 0.2, "A higher spout upgrade accelerates the growing soak radius")
	check(int(high_halo.halo_total) > int(low_halo.halo_total) and float(high_halo.farthest) > float(low_halo.farthest) + 0.15, "Upgrade growth increases passive absorption outside the core")
	check(int(high_halo.outside) == 0, "The largest upgrade still respects the shared carpet footprint")
	stop_fixture()
	var released_timing: Dictionary = water.debug_stats()
	print("HOSE_UPGRADE_CPU level=5 including_after_soak_total_usec=%d process_count=%d mean_usec=%.1f max_usec=%d" % [int(released_timing.cpu_usec_total), int(released_timing.process_count), float(released_timing.cpu_usec_total) / maxf(float(released_timing.process_count), 1.0), int(released_timing.cpu_usec_max)])


func check_movement_and_lifecycle() -> void:
	# A moderate move leaves room for both anchors plus interpolated deposits.
	# A longer teleport intentionally evicts the oldest of the fixed six slots.
	var old_position := Vector3(-0.30, 0.60, -0.30)
	var new_position := Vector3(0.30, 0.60, 0.30)
	start_fixture(Profile.MAX_LEVEL, old_position)
	advance_water(5.0)
	var mature_radius: float = water.debug_stats().soak.max_radius
	water.set_emitter(true, new_position, Vector3.DOWN)
	advance_water(0.40)
	var new_spots := 0
	var old_spots := 0
	for slot in water.soak.CAPACITY:
		if water.soak.active[slot] == 0:
			continue
		var position: Vector3 = water.soak.positions[slot]
		if Vector2(position.x, position.z).distance_to(Vector2(new_position.x, new_position.z)) < 0.20:
			new_spots += 1
			check(float(water.soak.fed_durations[slot]) < 0.5 and float(water.soak.radii[slot]) < mature_radius - 0.15, "A newly targeted area starts a young small reservoir instead of dragging a mature AOE")
		if Vector2(position.x, position.z).distance_to(Vector2(old_position.x, old_position.z)) < 0.10:
			old_spots += 1
	check(new_spots > 0 and old_spots > 0, "Moving preserves the previous anchored after-soak while feeding a new area")
	for step in 36:
		var position := Vector3(sin(float(step) * 1.7) * 0.75, 0.60, cos(float(step) * 1.3) * 1.15)
		water.set_emitter(true, position, Vector3.DOWN)
		advance_water(0.08)
		check(int(water.debug_stats().soak.active_spots) <= 6, "Repeated movement keeps the reservoir pool bounded (%d)" % step)
	check(int(water.debug_stats().soak.capacity) == 6 and water.soak.positions.size() == 6, "Soak storage has a fixed six-slot capacity")
	game.reset_rug()
	check(game.hose_upgrade_level == Profile.MAX_LEVEL and int(water.profile.level) == Profile.MAX_LEVEL, "Reset preserves the selected free preview upgrade")
	check(int(water.debug_stats().soak.active_spots) == 0 and not water.is_processing() and int(mask_stats().total) == 0, "Reset immediately cancels all reservoirs and airborne water")
	start_fixture(Profile.MAX_LEVEL)
	advance_water(0.6)
	game.select_rug(0)
	check(not water.enabled and not water.is_processing() and int(water.debug_stats().soak.active_spots) == 0, "Switching to dry practice clears all water and after-soak work")
	check(not game.hud.control("GymHoseUpgrades").is_visible_in_tree(), "Dry brush practice hides hose-only upgrades")
	game.select_rug(1)
	check(game.hose_upgrade_level == Profile.MAX_LEVEL and int(water.profile.level) == Profile.MAX_LEVEL and int(mask_stats().total) == 0, "Returning to wet practice keeps the upgrade but starts with a dry carpet")
	water.set_emitter(true, Vector3(0.0, 0.60, 0.0), Vector3.DOWN)
	advance_water(0.5)
	check(int(water.debug_stats().soak.active_spots) > 0, "Full-wet gate fixture starts with an active reservoir")
	check(soil.apply_water_blob(Vector3.ZERO, 5.0), "The shared production painter can saturate the practice carpet")
	game.update_contract_status()
	check(soil.water_stage_complete() and water.emission_locked and int(water.debug_stats().soak.active_spots) == 0, "The shared full-wet gate immediately clears all residual soak reservoirs")
	var full := mask_stats()
	advance_water(1.5)
	check(not water.is_processing() and mask_stats().hash == full.hash, "Full-wet completion cannot receive delayed soak deposits")
	start_fixture(Profile.MAX_LEVEL, Vector3(4.0, 0.60, 0.0))
	advance_water(1.0)
	check(water.contact_active and not water.contact_on_rug and int(water.debug_stats().soak.active_spots) == 0 and int(mask_stats().total) == 0, "Off-carpet impact cannot create a wet core or passive reservoir")
	start_fixture(Profile.MAX_LEVEL)
	for hitch in 10:
		var core_before: int = water.debug_stats().wet_events
		var halo_before: int = water.debug_stats().soak.emitted_events
		water._process(10.0)
		check(int(water.debug_stats().wet_events) - core_before <= 8 and int(water.debug_stats().soak.emitted_events) - halo_before <= 6, "A severe hitch performs bounded core and halo deposition (%d)" % hitch)
	check(int(water.debug_stats().history_count) <= int(water.debug_stats().history_capacity), "Long frames retain bounded nozzle history")
	game.reset_rug()


func check_layout(label: String) -> void:
	await settle()
	var safe: Rect2 = game.hud._safe_rect()
	var controls: Array[Control] = []
	for node_name: String in CONTROL_NAMES:
		var control: Control = game.hud.control(node_name)
		if not control.is_visible_in_tree():
			continue
		check(safe.grow(1.0).encloses(control.get_global_rect()), "%s fits the safe area in %s" % [node_name, label])
		controls.append(control)
	for index in controls.size():
		for other in range(index + 1, controls.size()):
			check(not controls[index].get_global_rect().intersects(controls[other].get_global_rect()), "%s and %s do not overlap in %s" % [controls[index].name, controls[other].name, label])
	var panel_rect: Rect2 = game.hud.control("GymPracticePanel").get_global_rect()
	for node_name in ["GymHoseUpgradeTitle", "GymHoseUpgradeStats", "GymHoseUpgradeHint"]:
		var text_label := game.hud.control(node_name) as Label
		var font := text_label.get_theme_font("font")
		var font_size := text_label.get_theme_font_size("font_size")
		var text_size := font.get_string_size(text_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
		check(text_size.x <= text_label.size.x + 1.0, "%s text fits without truncation in %s" % [node_name, label])
		check(panel_rect.encloses(text_label.get_global_rect()), "%s stays inside its upgrade panel in %s" % [node_name, label])
		for button_name in ["GymHoseLess", "GymHoseMore"]:
			var button_rect: Rect2 = game.hud.control(button_name).get_global_rect()
			check(not text_label.get_global_rect().intersects(button_rect), "%s does not overlap %s in %s" % [node_name, button_name, label])
	check(game.hud.blocks_point(game.hud.control("GymHoseMore").get_global_rect().get_center()), "Upgrade controls shield the carpet from input in " + label)
	var old_hash: int = mask_stats().hash
	game.set_hose_upgrade_level(1)
	tap(game.hud.control("GymHoseMore"))
	check(game.hose_upgrade_level == 2, "Touching plus previews the next spout in " + label)
	tap(game.hud.control("GymHoseMore"), true)
	check(game.hose_upgrade_level == 2, "A canceled touch does not change the spout in " + label)
	click(game.hud.control("GymHoseLess"))
	check(game.hose_upgrade_level == 1, "Clicking minus previews the previous spout in " + label)
	check(mask_stats().hash == old_hash and not game.brush_dragging and not water.is_processing(), "Upgrade input changes only the preview and never wets the rug in " + label)
	game.set_hose_upgrade_level(Profile.MAX_LEVEL)
	check((game.hud.control("GymHoseMore") as Button).disabled, "Plus is disabled at the final upgrade in " + label)
	game.set_hose_upgrade_level(0)
	check((game.hud.control("GymHoseLess") as Button).disabled, "Minus is disabled at the base upgrade in " + label)
	await capture(label)


func capture_real_hose(level: int, label: String) -> void:
	game.reset_rug()
	game.set_hose_upgrade_level(level)
	game.begin_stroke(game.camera.unproject_position(Vector3(0.0, 0.067, -0.25)), false)
	check(game.brush_dragging and water.emitting, "Capture uses the equipped hose and real stroke routing: " + label)
	advance_water(2.0)
	await capture(label + "_2s")
	advance_water(5.0)
	await capture(label + "_7s")
	game.end_stroke()
	advance_water(1.5)


func run() -> void:
	check_profiles()
	var state: Node = root.get_node("ShopState")
	state.set_process(false)
	state._test_unix_time = 1234567890.0
	state._test_ticks_msec = 0
	state._last_ticks = 0
	check(state.reset_progress(), "Create isolated test progress")
	state.cash = 123
	check(not state.start_job().is_empty(), "Preserve an existing paid job beside the Gym fixture")
	var saved_state: Dictionary = state._capture_state().duplicate(true)
	var saved_bytes := FileAccess.get_file_as_bytes(state._save_path)
	root.size = Vector2i(390, 844)
	game = load(Routes.GYM).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await settle()
	water = game.water
	soil = game.soil
	game.select_rug(1)
	await settle()
	var texture_id: int = soil.wet_texture.get_instance_id()
	var mesh_id: int = water.stream.mesh.get_instance_id()
	var material_id: int = water.stream_material.get_instance_id()
	var impact_id: int = water.impact.get_instance_id()
	var soak_id: int = water.soak.get_instance_id()
	var initial_nodes := node_count(water)
	check(soil.wet_mask.get_format() == Image.FORMAT_L8 and soil.wet_mask.get_size() == Vector2i(256, 416), "All upgrade levels use the original compact authoritative L8 wet mask")
	check_stationary_growth()
	check_upgrade_effects()
	check_movement_and_lifecycle()
	game.set_hose_upgrade_level(-20)
	check(game.hose_upgrade_level == 0 and water.upgrade_level == 0, "Gym clamps negative requested upgrades")
	game.set_hose_upgrade_level(20)
	check(game.hose_upgrade_level == Profile.MAX_LEVEL and water.upgrade_level == Profile.MAX_LEVEL, "Gym clamps above-range requested upgrades")
	await check_layout("portrait_controls")
	await capture_real_hose(0, "level1_portrait")
	await capture_real_hose(Profile.MAX_LEVEL, "level5_portrait")
	game.reset_rug()
	root.size = Vector2i(844, 390)
	await check_layout("landscape_controls")
	await capture_real_hose(Profile.MAX_LEVEL, "level5_landscape")
	game.reset_rug()
	root.size = Vector2i(320, 568)
	await check_layout("small_portrait_controls")
	game.hud.preview_safe_insets = Vector4(14.0, 24.0, 14.0, 28.0)
	game.hud._layout()
	game.frame_carpet()
	await check_layout("small_portrait_safe_controls")
	game.hud.preview_safe_insets = Vector4.ZERO
	check(soil.wet_texture.get_instance_id() == texture_id and water.stream.mesh.get_instance_id() == mesh_id and water.stream_material.get_instance_id() == material_id, "Levels, repeated use, resets and resizing reuse the same wet texture, tube mesh and material")
	check(water.impact.get_instance_id() == impact_id and water.soak.get_instance_id() == soak_id and node_count(water) == initial_nodes, "Hose upgrades reuse their splash and fixed reservoir objects without growing the node tree")
	check(state._capture_state() == saved_state and FileAccess.get_file_as_bytes(state._save_path) == saved_bytes, "All free Gym preview upgrades leave paid progress, cash and the on-disk save unchanged")
	game.return_to_shop()
	await settle()
	check(current_scene.scene_file_path == Routes.MAIN_MENU and FileAccess.get_file_as_bytes(state._save_path) == saved_bytes, "Leaving upgraded practice returns home without changing the paid save")
	print("HOSE_UPGRADE_VALIDATION %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
