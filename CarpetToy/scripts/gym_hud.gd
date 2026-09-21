extends "res://scripts/cleaning_hud.gd"
## Authored practice controls layered over the shared cleaning HUD.

var practice_rug := 0


func _ready() -> void:
	super._ready()
	set_practice_rug(practice_rug)


func action_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for node_name in ["GymRug1", "GymRug2", "GymBrush", "GymHose", "GymSqueegee", "GymReset"]:
		buttons.append(control(node_name) as Button)
	return buttons


func set_practice_rug(index: int) -> void:
	practice_rug = clampi(index, 0, 1)
	if not is_node_ready(): return
	var wet := practice_rug == 1
	(control("GymRug1") as Button).set_pressed_no_signal(not wet)
	(control("GymRug2") as Button).set_pressed_no_signal(wet)
	(control("GymDescription") as Label).text = "Hold the hose to pour blobs" if wet else "Dust + dirt pellets"
	control("GymStatus").visible = wet
	control("GymBrush").visible = not wet
	control("GymHose").visible = wet
	control("GymSqueegee").visible = wet
	control("CleaningProgress").visible = not wet
	_layout()


func blocks_point(point: Vector2) -> bool:
	for node_name in ["GymPracticePanel", "HomeButton", "CleaningProgress", "FinishJobButton"]:
		var node := control(node_name)
		if node.is_visible_in_tree() and node.get_global_rect().has_point(point):
			return true
	return false


func set_practice_tool(index: int) -> void:
	if practice_rug == 1:
		(control("GymDescription") as Label).text = "Squeegee comes next" if index == 1 else "Hold the hose to pour blobs"


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
	# held sideways. All controls retain the same two-row arrangement.
	var panel_width := clampf(safe.size.x * 0.45, 420.0, 500.0) if landscape else minf(720.0, safe.size.x - 32.0)
	panel.size = Vector2(panel_width, 200.0)
	panel.position = Vector2(safe.end.x - panel_width - 16.0, safe.get_center().y - panel.size.y * 0.5) if landscape else Vector2(safe.get_center().x - panel_width * 0.5, safe.end.y - panel.size.y - 16.0)
	var inside := panel_width - 32.0
	for node_name in ["GymHose", "GymSqueegee", "GymReset", "GymBrush"]:
		control(node_name).add_theme_font_size_override("font_size", 15 if inside < 360.0 else 16)
	for node_name in ["GymRug1", "GymRug2"]:
		control(node_name).add_theme_font_size_override("font_size", 16 if inside < 360.0 else 17)
	var title := control("GymTitle")
	title.position = Vector2(16.0, 12.0)
	title.size = Vector2(inside, 28.0)
	var description := control("GymDescription")
	description.position = Vector2(16.0, 40.0)
	description.size = Vector2(inside, 24.0)
	var status := control("GymStatus")
	status.position = Vector2(panel_width - 194.0, 14.0)
	status.size = Vector2(178.0, 24.0)
	var rug_width := (inside - 8.0) * 0.5
	_place("GymRug1", Vector2(16.0, 68.0), Vector2(rug_width, 56.0))
	_place("GymRug2", Vector2(24.0 + rug_width, 68.0), Vector2(rug_width, 56.0))
	var reset_width := 118.0
	var active_area := inside - reset_width - 8.0
	_place("GymBrush", Vector2(16.0, 132.0), Vector2(active_area, 56.0))
	_place("GymHose", Vector2(16.0, 132.0), Vector2((active_area - 8.0) * 0.5, 56.0))
	_place("GymSqueegee", Vector2(16.0 + (active_area + 8.0) * 0.5, 132.0), Vector2((active_area - 8.0) * 0.5, 56.0))
	_place("GymReset", Vector2(panel_width - 16.0 - reset_width, 132.0), Vector2(reset_width, 56.0))
	var progress := control("CleaningProgress")
	var play_width := panel.position.x - safe.position.x - 32.0 if landscape else safe.size.x - 32.0
	var progress_width := minf(340.0, play_width - 72.0)
	var play_center := safe.position.x + 16.0 + play_width * 0.5
	progress.position = Vector2(maxf(play_center - progress_width * 0.5, safe.position.x + 88.0), safe.position.y + 16.0)
	progress.size = Vector2(progress_width, 56.0)
	var finish := control("FinishJobButton")
	finish.position = Vector2(panel.get_rect().get_center().x - finish.size.x * 0.5, panel.position.y + panel.size.y + 12.0) if landscape else Vector2(safe.get_center().x - finish.size.x * 0.5, panel.position.y - 68.0)


func _landscape(safe: Rect2) -> bool:
	return safe.size.x > safe.size.y * 1.35


func _place(node_name: String, at: Vector2, dimensions: Vector2) -> void:
	var node := control(node_name)
	node.position = at
	node.size = dimensions
