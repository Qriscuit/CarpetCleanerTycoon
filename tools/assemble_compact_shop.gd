extends SceneTree
var scene: Control

func _initialize() -> void:
	call_deferred("build")

func add(parent: Node, node: Node, title: String, unique := true) -> Node:
	node.name = title
	parent.add_child(node)
	node.owner = scene
	node.unique_name_in_owner = unique
	return node

func rounded(color: String, radius: int = 20) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = Color(color)
	result.set_corner_radius_all(radius)
	result.content_margin_left = 14
	result.content_margin_right = 14
	result.content_margin_top = 12
	result.content_margin_bottom = 12
	return result

func words(parent: Node, name: String, text: String, size: int, unique := true) -> Label:
	var l := add(parent,Label.new(),name,unique) as Label
	l.text = text
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",Color("355876"))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func button(parent: Node, name: String, text: String, unique := true) -> Button:
	var b := add(parent,Button.new(),name,unique) as Button
	b.text=text
	b.custom_minimum_size=Vector2(48,48)
	b.add_theme_font_size_override("font_size",15)
	b.add_theme_color_override("font_color",Color("355876"))
	b.add_theme_color_override("font_hover_color",Color("355876"))
	b.add_theme_color_override("font_pressed_color",Color("355876"))
	b.add_theme_color_override("font_focus_color",Color("355876"))
	b.add_theme_color_override("font_disabled_color",Color("687d82"))
	for mode in ["normal","hover","pressed","disabled"]:
		b.add_theme_stylebox_override(mode,rounded({"normal":"d9edce","hover":"cee8be","pressed":"bedbaa","disabled":"eaf0e8"}[mode],16))
	var focus := rounded("ffffff00",16)
	focus.set_border_width_all(2)
	focus.border_color=Color("487daa")
	b.add_theme_stylebox_override("focus",focus)
	return b

func icon(parent: Node, name: String, asset: String, size: float) -> TextureRect:
	var t := add(parent,TextureRect.new(),name,false) as TextureRect
	t.texture=load("res://assets/floating_shop/"+asset+".png")
	t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size=Vector2(size,size)
	t.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return t

func build() -> void:
	scene=Control.new()
	scene.name="CompactShop"
	var backdrop := add(scene,Button.new(),"Backdrop") as Button
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.focus_mode=Control.FOCUS_NONE
	for mode in ["normal","hover","pressed"]: backdrop.add_theme_stylebox_override(mode,rounded("31556a44",0))
	var panel := add(scene,PanelContainer.new(),"Sheet") as PanelContainer
	panel.add_theme_stylebox_override("panel",rounded("fff8e9",28))
	panel.position=Vector2(12,50)
	panel.size=Vector2(366,654)
	var content := add(panel,VBoxContainer.new(),"Content",false) as VBoxContainer
	content.add_theme_constant_override("separation",12)
	var header := add(content,HBoxContainer.new(),"Header",false) as HBoxContainer
	var title := words(header,"SheetTitle","Shop",25)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	icon(header,"Coin","CoinIcon",25)
	var cash := words(header,"SheetCash","0",17)
	cash.autowrap_mode=TextServer.AUTOWRAP_OFF
	cash.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var close := button(header,"CloseSheet","×")
	close.tooltip_text="Back to home"
	close.add_theme_font_size_override("font_size",26)
	var note := words(content,"SheetNote","",14)
	note.visible=false
	var scroll := add(content,ScrollContainer.new(),"MenuScroll") as ScrollContainer
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	var stack := add(scroll,VBoxContainer.new(),"Stack",false) as VBoxContainer
	stack.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation",12)
	var routine := add(stack,PanelContainer.new(),"Routine") as PanelContainer
	routine.add_theme_stylebox_override("panel",rounded("e3f0e8"))
	routine.visible=false
	var routine_content := add(routine,VBoxContainer.new(),"RoutineContents",false) as VBoxContainer
	words(routine_content,"RoutineRate","10 coins every 120s",22)
	words(routine_content,"RoutineTime","Next +10 in 2:00",14)
	var progress := add(routine_content,ProgressBar.new(),"RoutineProgress") as ProgressBar
	progress.custom_minimum_size.y=8
	progress.show_percentage=false
	progress.add_theme_stylebox_override("background",rounded("cfe0d4",4))
	progress.add_theme_stylebox_override("fill",rounded("85be98",4))
	var rows := add(stack,VBoxContainer.new(),"Rows") as VBoxContainer
	rows.add_theme_constant_override("separation",10)
	for data in [["hand_brush","Hand Brush","BrushIcon"],["bonzi","Bonzi","BonziIcon"],["wide_brush","Wide Brush","BrushIcon"],["bonzi_mk2","Bonzi Mk II","BonziIcon"],["intake","Welcome Sign","FloatingShop"]]:
		var card := add(rows,PanelContainer.new(),data[0],false) as PanelContainer
		card.set_meta("item_id",data[0])
		card.add_theme_stylebox_override("panel",rounded("f0f4e9",18))
		var row := add(card,HBoxContainer.new(),"Row",false) as HBoxContainer
		row.add_theme_constant_override("separation",8)
		icon(row,"Artwork",data[2],48)
		var copy := add(row,VBoxContainer.new(),"Words",false) as VBoxContainer
		copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		copy.alignment=BoxContainer.ALIGNMENT_CENTER
		words(copy,"Title",data[1],17,false)
		var status := words(copy,"Status","0 / 3 rugs",13,false)
		status.add_theme_color_override("font_color",Color("627f88"))
		var action := button(row,"Action","100",false)
		action.custom_minimum_size.x=80
		action.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		action.expand_icon=true
		action.add_theme_constant_override("icon_max_width",21)
	var review := add(scene,Control.new(),"PurchaseReview") as Control
	review.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	review.visible=false
	var dim := add(review,ColorRect.new(),"Dim",false) as ColorRect
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color=Color(.18,.30,.37,.30)
	var confirm := add(review,PanelContainer.new(),"ConfirmPanel") as PanelContainer
	confirm.add_theme_stylebox_override("panel",rounded("fff8e9",24))
	var review_content := add(confirm,VBoxContainer.new(),"ReviewContent",false) as VBoxContainer
	review_content.add_theme_constant_override("separation",14)
	words(review_content,"BuildTitle","Build Bonzi?",24).autowrap_mode=TextServer.AUTOWRAP_OFF
	words(review_content,"BuildBenefit","10 coins every 120s",18).autowrap_mode=TextServer.AUTOWRAP_OFF
	words(review_content,"BuildBalance","100 coins · 0 left",15).autowrap_mode=TextServer.AUTOWRAP_OFF
	button(review_content,"ConfirmBuild","Build · 100")
	button(review_content,"CancelBuild","Not now")
	scene.set_script(load("res://scripts/compact_shop.gd"))
	var packed := PackedScene.new()
	assert(packed.pack(scene)==OK)
	assert(ResourceSaver.save(packed,"res://scenes/ui/compact_shop.tscn")==OK)
	scene.free()
	# Patch the authored home without regenerating the user's entire scene.
	var file := FileAccess.open("res://scenes/production/floating_home.tscn",FileAccess.READ)
	var text := file.get_as_text().replace('name="NavHome"','name="NavShop"').replace('tooltip_text = "Home"','tooltip_text = "Shop"')
	file.close()
	file=FileAccess.open("res://scenes/production/floating_home.tscn",FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var home := (load("res://scenes/production/floating_home.tscn") as PackedScene).instantiate() as Control
	load("res://../tools/home_navigation_authoring.gd").decorate(home)
	var home_packed := PackedScene.new()
	assert(home_packed.pack(home)==OK)
	assert(ResourceSaver.save(home_packed,"res://scenes/production/floating_home.tscn")==OK)
	home.free()
	print("COMPACT_SHOP_SAVED")
	quit()
