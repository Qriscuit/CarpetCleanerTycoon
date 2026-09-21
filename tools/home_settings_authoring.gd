extends RefCounted
## Edits the saved controls; no UI is generated during normal play.
static func decorate(home: Control) -> void:
	var tap: Button = home.get_node("%ShopTap")
	for state_name in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		tap.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	var message: Label = home.get_node_or_null("%StatusMessage")
	if message == null:
		message = home.get_node("%Hint")
		message.name = "StatusMessage"
	message.visible = false
	message.text = ""
	message.position = Vector2(18, 74)
	message.size = Vector2(354,44)
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message.add_theme_font_size_override("font_size",16)
	var timer := home.get_node_or_null("%StatusTimer")
	if timer == null: home.get_node("%HintTimer").name = "StatusTimer"
	if home.get_node_or_null("%ResetProgress") != null:
		for name: String in ["ResetProgress","CancelReset","ConfirmReset"]:
			for color_name: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
				home.get_node("%"+name).add_theme_color_override(color_name,Color("355876"))
		return
	var column: VBoxContainer = home.get_node("SettingsSheet/SettingsPanel/SettingsContents")
	var reset := _button(home,column,"ResetProgress","Reset progress",Color("f5ded8"))
	column.move_child(reset,2)
	var review := VBoxContainer.new()
	review.name = "ResetReview"
	column.add_child(review)
	review.owner = home
	review.unique_name_in_owner = true
	review.visible = false
	review.add_theme_constant_override("separation",12)
	var detail := Label.new()
	detail.name = "ResetDetail"
	review.add_child(detail)
	detail.owner = home
	detail.text = "Erase coins, tools, upgrades\nand rug progress?"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_color_override("font_color",Color("355876"))
	detail.add_theme_font_size_override("font_size",16)
	var error := Label.new()
	error.name = "ResetError"
	review.add_child(error)
	error.owner = home
	error.unique_name_in_owner = true
	error.visible = false
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.add_theme_color_override("font_color",Color("a34f4b"))
	error.add_theme_font_size_override("font_size",14)
	_button(home,review,"CancelReset","Keep playing",Color("dbedce"))
	_button(home,review,"ConfirmReset","Reset",Color("f5ded8"))
	var panel: Control = home.get_node("%SettingsPanel")
	panel.size = Vector2(300,280)
	panel.position = Vector2(45,282)

static func _button(home: Control, parent: Control, node_name: String, caption: String, color: Color) -> Button:
	var button := Button.new()
	button.name = node_name
	parent.add_child(button)
	button.owner = home
	button.unique_name_in_owner = true
	button.text = caption
	button.custom_minimum_size.y = 48
	button.add_theme_color_override("font_color",Color("355876"))
	for color_name: String in ["font_hover_color","font_pressed_color","font_focus_color"]:
		button.add_theme_color_override(color_name,Color("355876"))
	button.add_theme_font_size_override("font_size",16)
	for state_name in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color.darkened(.08) if state_name == "pressed" else color
		style.set_corner_radius_all(16)
		if state_name == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = Color("487daa")
			style.set_border_width_all(2)
		button.add_theme_stylebox_override(state_name,style)
	return button
