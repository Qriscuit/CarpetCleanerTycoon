extends "res://scripts/cleaning_hud.gd"
## Authored practice controls layered over the shared cleaning HUD.

signal hose_level_requested(level: int)
signal squeegee_level_requested(level: int)
signal camera_angle_requested(oblique: bool)

var practice_rug := 0
var practice_design_name := "Practice gym"
var wet_fraction := 0.0
var extraction_fraction := 0.0
var wet_ready := false
var wash_round := 1
var wash_round_count := 3
var wash_complete := false
var hose_upgrade_level := 0
var squeegee_upgrade_level := 0
var squeegee_upgrade_power := 1.0
var _hose_upgrade_profile: Dictionary = {}
var camera_oblique := false


func _ready() -> void:
	super._ready()
	control("WaterDropCharge").hide()
	(control("GymHoseLess") as Button).pressed.connect(_request_hose_level.bind(-1))
	(control("GymHoseMore") as Button).pressed.connect(_request_hose_level.bind(1))
	(control("GymSqueegeeLess") as Button).pressed.connect(_request_squeegee_level.bind(-1))
	(control("GymSqueegeeMore") as Button).pressed.connect(_request_squeegee_level.bind(1))
	(control("GymCameraAngle") as Button).pressed.connect(_request_camera_angle)
	set_camera_angle(camera_oblique)
	set_hose_upgrade(hose_upgrade_level, _hose_upgrade_profile)
	set_squeegee_upgrade(squeegee_upgrade_level, squeegee_upgrade_power)
	set_practice_rug(practice_rug)
	set_practice_design(practice_design_name)


func action_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for node_name in ["GymRug1", "GymRug2", "GymBrush", "GymHose", "GymSqueegee", "GymReset", "GymHoseLess", "GymHoseMore", "GymSqueegeeLess", "GymSqueegeeMore", "GymCameraAngle"]:
		buttons.append(control(node_name) as Button)
	return buttons


func set_camera_angle(oblique: bool) -> void:
	camera_oblique = oblique
	if not is_node_ready(): return
	var button := control("GymCameraAngle") as Button
	button.set_pressed_no_signal(oblique)
	button.text = "Top" if oblique else "Angle"
	button.tooltip_text = "Switch to top-down view" if oblique else "Switch to angled view · drag tools the same way"


func _request_camera_angle() -> void:
	camera_angle_requested.emit(not camera_oblique)


func set_practice_design(design_name: String) -> void:
	practice_design_name = design_name
	if not is_node_ready(): return
	(control("GymTitle") as Label).text = design_name
	control("GymTitle").tooltip_text = "Practice gym · " + design_name
	control("GymReset").tooltip_text = "Replace this carpet with a random design from any level. Keep your practice mode, camera and upgrades."
	_layout()


func set_practice_rug(index: int) -> void:
	practice_rug = clampi(index, 0, 1)
	if not is_node_ready(): return
	var wet := practice_rug == 1
	wet_fraction = 0.0
	extraction_fraction = 0.0
	wet_ready = false
	wash_round = 1
	wash_round_count = 3
	wash_complete = false
	(control("GymRug1") as Button).set_pressed_no_signal(not wet)
	(control("GymRug2") as Button).set_pressed_no_signal(wet)
	(control("GymDescription") as Label).text = "Wash 1/3 · Spray fresh areas" if wet else "Dust + dirt pellets"
	control("GymStatus").visible = wet
	control("GymBrush").visible = not wet
	control("GymHose").visible = wet
	control("GymSqueegee").visible = wet
	control("GymHose").tooltip_text = "Restart all three washes with a dry carpet and the hose."
	control("GymSqueegee").tooltip_text = "Restart the three-wash exercise with wash 1 soaked and the squeegee ready."
	control("GymHoseUpgrades").visible = wet
	control("GymSqueegeeUpgrades").visible = wet
	control("CleaningProgress").visible = true
	control("WaterDropCharge").hide()
	if wet:
		set_wet_progress(0.0, 0.0, false)
	else:
		clear_wet_stage()
	_layout()


func set_hose_upgrade(level: int, profile: Dictionary) -> void:
	hose_upgrade_level = clampi(level, 0, 4)
	_hose_upgrade_profile = profile.duplicate()
	if not is_node_ready(): return
	(control("GymHoseUpgradeTitle") as Label).text = "Hose upgrades · Spout Lv %d / 5" % (hose_upgrade_level + 1)
	(control("GymHoseUpgradeStats") as Label).text = "Circle %.2f m · Flow %.1f×" % [float(profile.get("impact_radius", 0.19)) * 2.0, float(profile.get("soak_multiplier", 1.0))]
	control("GymHoseUpgradeStats").tooltip_text = "Whole-rug flow %.2f× versus Lv 1. Holding anywhere gives steady progress; spraying fresh areas adds a small speed bonus." % float(profile.get("soak_multiplier", 1.0))
	control("GymHoseUpgradeHint").tooltip_text = "The influence circle spreads up to %.2f m. Watering anywhere soaks the whole carpet. Sweep across fresh areas to wet it a little faster." % float(profile.get("max_spread_radius", 0.70))
	(control("GymHoseLess") as Button).disabled = hose_upgrade_level <= 0
	(control("GymHoseMore") as Button).disabled = hose_upgrade_level >= 4
	control("GymHoseUpgrades").tooltip_text = "Free gym preview. Stronger flow fills the whole carpet faster. Hold anywhere, or sweep fresh areas for a small speed bonus."
	_layout()


func _request_hose_level(step: int) -> void:
	var next_level := clampi(hose_upgrade_level + step, 0, 4)
	if next_level != hose_upgrade_level:
		hose_level_requested.emit(next_level)


func set_squeegee_upgrade(level: int, power: float) -> void:
	squeegee_upgrade_level = clampi(level, 0, 4)
	squeegee_upgrade_power = maxf(power, 1.0)
	if not is_node_ready(): return
	(control("GymSqueegeeUpgradeTitle") as Label).text = "Squeegee · Lv %d / 5" % (squeegee_upgrade_level + 1)
	(control("GymSqueegeeUpgradeStats") as Label).text = "Extraction %.2f×" % squeegee_upgrade_power
	(control("GymSqueegeeLess") as Button).disabled = squeegee_upgrade_level <= 0
	(control("GymSqueegeeMore") as Button).disabled = squeegee_upgrade_level >= 4
	_layout()


func _request_squeegee_level(step: int) -> void:
	var next_level := clampi(squeegee_upgrade_level + step, 0, 4)
	if next_level != squeegee_upgrade_level:
		squeegee_level_requested.emit(next_level)


func blocks_point(point: Vector2) -> bool:
	for node_name in ["GymPracticePanel", "HomeButton", "CleaningProgress", "FinishJobButton", "GymCameraAngle"]:
		var node := control(node_name)
		if node.is_visible_in_tree() and node.get_global_rect().has_point(point):
			return true
	return false


func set_practice_tool(index: int) -> void:
	if practice_rug != 1: return
	var instruction := "Spray fresh areas"
	if wash_complete:
		instruction = "Fresh and clean"
	elif index == 1:
		instruction = ["Push out dark mud", "Push out brown water", "Rinse clear blue"][clampi(wash_round - 1, 0, 2)]
	(control("GymDescription") as Label).text = "Wash %d/%d · %s" % [wash_round, wash_round_count, instruction]


func set_wet_progress(water: float, extracted: float, ready: bool, round_number: int = 1, round_count: int = 3, complete: bool = false) -> void:
	wet_fraction = clampf(water, 0.0, 1.0)
	extraction_fraction = clampf(extracted, 0.0, 1.0)
	wet_ready = ready
	wash_round_count = maxi(round_count, 1)
	wash_round = clampi(round_number, 1, wash_round_count)
	wash_complete = complete
	if practice_rug != 1:
		return
	# Gym buttons remain repeatable setup shortcuts; internal auto-advance
	# follows the same three wash gates as a paid carpet.
	(control("GymHose") as Button).disabled = false
	(control("GymSqueegee") as Button).disabled = false
	(control("GymStatus") as Label).text = (
		"Clean" if wash_complete
		else "Removed %d%%" % floori(minf(extraction_fraction / 0.99, 1.0) * 100.0 + 0.0001) if ready
		else "Wet %d%%" % floori(minf(wet_fraction / 0.99, 1.0) * 100.0 + 0.0001)
	)
	set_wet_stage(wash_round, wash_round_count, ready, wash_complete)
	set_practice_tool(1 if ready else 2)
	if ready:
		control("WaterDropCharge").hide()


func set_water_drop_charge(fraction: float, viewport_position: Vector2, active: bool) -> void:
	var charge := control("WaterDropCharge") as TextureProgressBar
	if practice_rug != 1 or wet_ready or not active:
		charge.value = 0.0
		charge.hide()
		return
	charge.value = clampf(fraction, 0.0, 1.0) * 100.0
	charge.show()
	var ui_scale := (get_node("HUD") as Control).scale.x
	var screen_size := charge.size * ui_scale
	var viewport_rect := get_viewport().get_visible_rect()
	var desired := viewport_position + Vector2(30.0, -78.0) * ui_scale - screen_size * 0.5
	desired.x = clampf(desired.x, viewport_rect.position.x + 8.0, viewport_rect.end.x - screen_size.x - 8.0)
	desired.y = clampf(desired.y, viewport_rect.position.y + 8.0, viewport_rect.end.y - screen_size.y - 8.0)
	var panel_rect := control("GymPracticePanel").get_global_rect()
	if Rect2(desired, screen_size).intersects(panel_rect.grow(6.0)):
		desired.y = maxf(viewport_rect.position.y + 8.0, panel_rect.position.y - screen_size.y - 8.0)
	charge.global_position = desired


func rug_view_rect() -> Rect2:
	# Coordinates are viewport units, including the shared HUD's touch scaling.
	_layout()
	var safe := _safe_rect()
	var ui_scale := (get_node("HUD") as Control).scale.x
	var panel_rect := control("GymPracticePanel").get_global_rect()
	var top := safe.position.y + 88.0 * ui_scale
	if _landscape(safe):
		return Rect2(Vector2(safe.position.x + 16.0 * ui_scale, top), Vector2(maxf(1.0, panel_rect.position.x - safe.position.x - 32.0 * ui_scale), maxf(1.0, safe.end.y - 16.0 * ui_scale - top)))
	var bottom := panel_rect.position.y - 80.0 * ui_scale
	return Rect2(Vector2(safe.position.x + 16.0 * ui_scale, top), Vector2(maxf(1.0, safe.size.x - 32.0 * ui_scale), maxf(1.0, bottom - top)))


func _layout() -> void:
	super._layout()
	if not is_node_ready() or get_viewport() == null: return
	for node_name in ["Wallet", "PayoutCard", "PayoutUpgradeButton", "UpgradeButton", "AdRewardButton", "UpgradeSheet"]:
		control(node_name).hide()
	var ui_scale := (get_node("HUD") as Control).scale.x
	var raw_safe := _safe_rect()
	var safe := Rect2(raw_safe.position / ui_scale, raw_safe.size / ui_scale)
	var panel := control("GymPracticePanel")
	var landscape := _landscape(safe)
	# A side panel leaves enough height to clean a full-sized rug on a phone
	# held sideways. Two compact rows preview the wet tools independently.
	var panel_width := clampf(safe.size.x * 0.45, 420.0, 500.0) if landscape else minf(720.0, safe.size.x - 32.0)
	panel.size = Vector2(panel_width, 348.0 if practice_rug == 1 else 200.0)
	panel.position = Vector2(safe.end.x - panel_width - 16.0, safe.get_center().y - panel.size.y * 0.5) if landscape else Vector2(safe.get_center().x - panel_width * 0.5, safe.end.y - panel.size.y - 16.0)
	# Centering the taller wet panel on a 320px-high phone put it over the
	# camera button. Keep a 12-unit gap below the 56-unit toolbar when it fits.
	var toolbar_bottom := safe.position.y + 84.0
	if landscape and toolbar_bottom + panel.size.y <= safe.end.y - 16.0:
		panel.position.y = maxf(panel.position.y, toolbar_bottom)
	var inside := panel_width - 32.0
	var compact := inside < 400.0
	(control("GymHose") as Button).text = "Hose" if compact else "Water hose"
	(control("GymReset") as Button).text = "Reset" if compact else "Reset carpet"
	for node_name in ["GymHose", "GymSqueegee", "GymReset", "GymBrush"]:
		control(node_name).add_theme_font_size_override("font_size", 15 if inside < 360.0 else 16)
	for node_name in ["GymRug1", "GymRug2"]:
		control(node_name).add_theme_font_size_override("font_size", 16 if inside < 360.0 else 17)
	var title := control("GymTitle")
	title.add_theme_font_size_override("font_size", 18 if compact else 20)
	title.position = Vector2(16.0, 12.0)
	title.size = Vector2(inside - 104.0 if practice_rug == 1 else inside, 28.0)
	var description := control("GymDescription")
	description.position = Vector2(16.0, 40.0)
	description.size = Vector2(inside, 24.0)
	var status := control("GymStatus")
	status.position = Vector2(panel_width - 112.0, 14.0)
	status.size = Vector2(96.0, 24.0)
	var rug_width := (inside - 8.0) * 0.5
	_place("GymRug1", Vector2(16.0, 68.0), Vector2(rug_width, 56.0))
	_place("GymRug2", Vector2(24.0 + rug_width, 68.0), Vector2(rug_width, 56.0))
	var reset_width := 88.0 if compact else 118.0
	var active_area := inside - reset_width - 8.0
	_place("GymBrush", Vector2(16.0, 132.0), Vector2(active_area, 56.0))
	_place("GymHose", Vector2(16.0, 132.0), Vector2((active_area - 8.0) * 0.5, 56.0))
	_place("GymSqueegee", Vector2(16.0 + (active_area + 8.0) * 0.5, 132.0), Vector2((active_area - 8.0) * 0.5, 56.0))
	_place("GymReset", Vector2(panel_width - 16.0 - reset_width, 132.0), Vector2(reset_width, 56.0))
	# Apply compact copy and font sizes before placement; Label's intrinsic
	# minimum width would otherwise preserve a wider size from the old layout.
	control("GymHoseUpgradeTitle").add_theme_font_size_override("font_size", 16)
	control("GymHoseUpgradeStats").add_theme_font_size_override("font_size", 13)
	control("GymHoseUpgradeHint").add_theme_font_size_override("font_size", 12)
	(control("GymHoseUpgradeTitle") as Label).text = "Hose · Spout Lv %d / 5" % (hose_upgrade_level + 1)
	(control("GymHoseUpgradeHint") as Label).text = "Whole rug · Hold to soak"
	_place("GymHoseUpgrades", Vector2(16.0, 198.0), Vector2(inside, 68.0))
	_place("GymHoseUpgradeDivider", Vector2.ZERO, Vector2(inside, 1.0))
	_place("GymHoseUpgradeTitle", Vector2(0.0, 4.0), Vector2(inside - 132.0, 20.0))
	_place("GymHoseUpgradeStats", Vector2(0.0, 25.0), Vector2(inside - 132.0, 20.0))
	_place("GymHoseUpgradeHint", Vector2(0.0, 46.0), Vector2(inside - 132.0, 20.0))
	_place("GymHoseLess", Vector2(inside - 120.0, 8.0), Vector2(56.0, 56.0))
	_place("GymHoseMore", Vector2(inside - 56.0, 8.0), Vector2(56.0, 56.0))
	_place("GymSqueegeeUpgrades", Vector2(16.0, 272.0), Vector2(inside, 64.0))
	_place("GymSqueegeeUpgradeDivider", Vector2.ZERO, Vector2(inside, 1.0))
	_place("GymSqueegeeUpgradeTitle", Vector2(0.0, 7.0), Vector2(inside - 132.0, 24.0))
	_place("GymSqueegeeUpgradeStats", Vector2(0.0, 33.0), Vector2(inside - 132.0, 24.0))
	_place("GymSqueegeeLess", Vector2(inside - 120.0, 6.0), Vector2(56.0, 56.0))
	_place("GymSqueegeeMore", Vector2(inside - 56.0, 6.0), Vector2(56.0, 56.0))
	var progress := control("CleaningProgress")
	var play_width := panel.position.x - safe.position.x - 32.0 if landscape else safe.size.x - 32.0
	# The view toggle stays outside the play rectangle and has a full 44px
	# touch target after scaling, including on short landscape phones.
	var camera_left := safe.end.x - 104.0
	if landscape and panel.position.y < toolbar_bottom:
		# A very short/notched safe area cannot lower the panel. Keep the view
		# button in the free left toolbar, narrowing progress instead of overlap.
		camera_left = panel.position.x - 104.0
	_place("GymCameraAngle", Vector2(camera_left, safe.position.y + 16.0), Vector2(88.0, 56.0))
	var progress_left := safe.position.x + 88.0
	var progress_right := minf(safe.position.x + 16.0 + play_width, control("GymCameraAngle").position.x - 12.0)
	var progress_width := minf(340.0, maxf(1.0, progress_right - progress_left))
	var play_center := safe.position.x + 16.0 + play_width * 0.5
	progress.position = Vector2(clampf(play_center - progress_width * 0.5, progress_left, progress_right - progress_width), safe.position.y + 16.0)
	progress.size = Vector2(progress_width, 56.0)
	var finish := control("FinishJobButton")
	finish.position = Vector2(safe.position.x + 16.0, safe.end.y - finish.size.y - 16.0) if landscape else Vector2(safe.get_center().x - finish.size.x * 0.5, panel.position.y - 68.0)


func _landscape(safe: Rect2) -> bool:
	return safe.size.x > safe.size.y * 1.35


func _place(node_name: String, at: Vector2, dimensions: Vector2) -> void:
	var node := control(node_name)
	node.position = at
	node.size = dimensions
