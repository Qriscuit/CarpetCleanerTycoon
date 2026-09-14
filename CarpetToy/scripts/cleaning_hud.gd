extends CanvasLayer
## Presentation is authored in cleaning_hud.tscn. These inspector fields are
## the few text templates and colors that change with live cleaning state.

@export_group("Live text")
@export_multiline var contract_progress_text := "Debris %d%% · Dust %d%%"
@export var reward_text := "+%d cash"
@export var reward_received_text := "%d cash added to your shop."
@export_group("Progress colors")
@export var progress_colors: PackedColorArray = [Color("e76c62"), Color("dfb13d"), Color("63b66e"), Color("559bdd")]

func control(node_name: String) -> Control:
	return get_node("%" + node_name) as Control

func blocks_point(point: Vector2) -> bool:
	# Only actual visible panels/rails block the rug, never the full-screen root.
	for node_name in ["Heading", "CleaningProgress", "LeftRail", "ToolRail", "HomeButton"]:
		var node := control(node_name)
		if node.is_visible_in_tree() and node.get_global_rect().has_point(point):
			return true
	return false

func visible_button_at(point: Vector2, buttons: Array[Button]) -> Button:
	for button in buttons:
		if not button.is_visible_in_tree() or button.disabled or not button.get_global_rect().has_point(point):
			continue
		var ancestor := button.get_parent()
		var clipped := false
		while ancestor != null and ancestor != self:
			if ancestor is Control and ancestor.clip_contents and not ancestor.get_global_rect().has_point(point):
				clipped = true
				break
			ancestor = ancestor.get_parent()
		if not clipped:
			return button
	return null
