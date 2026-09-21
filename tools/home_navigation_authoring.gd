extends RefCounted
## Saved short captions make the icon routes understandable on touch devices.
static func decorate(home: Control) -> void:
	for definition in [["NavShop","Shop","FloatingShop"],["NavItems","Tools","BrushIcon"],["NavPlans","Plans","BlueprintIcon"],["NavBonzi","Bonzi","BonziIcon"]]:
		var b: Button = home.get_node("%"+definition[0])
		b.icon=null
		b.custom_minimum_size=Vector2(64,72)
		if b.has_node("CaptionContent"): continue
		var column := VBoxContainer.new()
		column.name="CaptionContent"
		b.add_child(column)
		column.owner=home
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.mouse_filter=Control.MOUSE_FILTER_IGNORE
		column.alignment=BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation",0)
		var art := TextureRect.new()
		art.name="Icon"
		column.add_child(art)
		art.owner=home
		art.texture=load("res://assets/floating_shop/"+definition[2]+".png")
		art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size.y=44
		art.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var caption := Label.new()
		caption.name="Caption"
		column.add_child(caption)
		caption.owner=home
		caption.text=definition[1]
		caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size",12)
		caption.add_theme_color_override("font_color",Color("355876"))
		caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
