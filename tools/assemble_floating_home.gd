extends SceneTree
## One-time authoring utility. Normal play uses the saved, editable scene.
const ASSETS := "res://assets/floating_shop/"
var home: Control

func _initialize() -> void:
	call_deferred("build")

func add(parent: Node, node: Node, title: String, unique := false) -> Node:
	node.name = title
	parent.add_child(node)
	node.owner = home
	node.unique_name_in_owner = unique
	return node

func full(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func style(color: Color, radius: int, shadow := false) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(radius)
	result.content_margin_left = 10
	result.content_margin_right = 10
	result.content_margin_top = 6
	result.content_margin_bottom = 6
	if shadow:
		result.shadow_color = Color(0.22,0.47,0.59,.13)
		result.shadow_size = 5
		result.shadow_offset = Vector2(0,4)
	return result

func button(parent: Node, title: String, asset: String, tooltip: String) -> Button:
	var b := add(parent, Button.new(), title, true) as Button
	b.custom_minimum_size = Vector2(52,52)
	b.tooltip_text = tooltip
	b.icon = load(ASSETS+asset+".png")
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 62)
	b.add_theme_stylebox_override("normal", style(Color(1,1,1,0),20))
	b.add_theme_stylebox_override("hover", style(Color("e6f1d9"),20))
	b.add_theme_stylebox_override("pressed", style(Color("c9e7b7"),20))
	var focus := style(Color(1,1,1,0),20)
	focus.border_color = Color("487daa")
	focus.set_border_width_all(2)
	b.add_theme_stylebox_override("focus",focus)
	return b

func label(parent: Node, title: String, text: String, font_size: int) -> Label:
	var node := add(parent, Label.new(), title, true) as Label
	node.text = text
	node.add_theme_color_override("font_color",Color("355876"))
	node.add_theme_font_size_override("font_size",font_size)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func readable_button_text(control: Control) -> void:
	for color_name: String in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color","font_disabled_color"]:
		control.add_theme_color_override(color_name,Color("355876"))

func build() -> void:
	home = Control.new()
	home.name = "FloatingHome"
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	theme.default_font_size = 18
	home.theme = theme
	var pattern := add(home, Control.new(), "SkyPattern") as Control
	full(pattern)
	pattern.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pattern.set_script(load("res://scripts/ui/home_pattern.gd"))
	var view := add(home, SubViewportContainer.new(), "BuildingView", true) as SubViewportContainer
	view.position = Vector2(18,86)
	view.size = Vector2(354,594)
	view.stretch = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := add(view, SubViewport.new(), "ShopViewport", true) as SubViewport
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var world := add(viewport, Node3D.new(), "ShopStudio") as Node3D
	var env_node := add(world, WorldEnvironment.new(), "SoftDaylight") as WorldEnvironment
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("acdff7")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e5f2ff")
	env.ambient_light_energy = 0.60
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_node.environment = env
	var light := add(world, DirectionalLight3D.new(), "LargeSoftbox") as DirectionalLight3D
	light.rotation_degrees = Vector3(-48,-36,0)
	light.light_color = Color("fff3de")
	light.light_energy = 0.30
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 24
	light.shadow_blur = 3.0
	var fill := add(world, DirectionalLight3D.new(), "CoolFill") as DirectionalLight3D
	fill.rotation_degrees = Vector3(-25,130,0)
	fill.light_energy = .10
	fill.light_color = Color("d6edff")
	var pivot := add(world, Node3D.new(), "ShopPivot", true) as Node3D
	var shop := (load(ASSETS+"FloatingShop.glb") as PackedScene).instantiate()
	add(pivot,shop,"FloatingShopAsset")
	var shadow := add(world, MeshInstance3D.new(), "FloatingShadow") as MeshInstance3D
	var plane := PlaneMesh.new()
	plane.size = Vector2(5.4,4.5)
	shadow.mesh = plane
	shadow.position.y = -.38
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never; void fragment(){ float d = length((UV-vec2(0.5))*2.0); ALBEDO=vec3(0.25,0.52,0.68); ALPHA=0.17*exp(-5.0*d*d)*smoothstep(1.0,0.7,d); }"
	var shadow_mat := ShaderMaterial.new()
	shadow_mat.shader = shader
	shadow.material_override = shadow_mat
	var camera := add(world, Camera3D.new(), "ShopCamera", true) as Camera3D
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 8.98
	camera.position = Vector3(6,5.6,8)
	camera.transform = camera.transform.looking_at(Vector3(0,1.6,0),Vector3.UP)
	camera.current = true
	camera.near = .1
	camera.far = 50
	var tap := add(home, Button.new(),"ShopTap",true) as Button
	tap.position = Vector2(53,134)
	tap.size = Vector2(283,499)
	tap.tooltip_text = "Open your rug"
	tap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state_name in ["normal","hover","pressed"]:
		tap.add_theme_stylebox_override(state_name,StyleBoxEmpty.new())
	var tap_focus := style(Color(1,1,1,0),36)
	tap_focus.border_color=Color(.22,.43,.59,.55)
	tap_focus.set_border_width_all(2)
	tap.add_theme_stylebox_override("focus",tap_focus)
	var hint := label(home,"Hint","Tap to clean",20)
	hint.position = Vector2(18,683)
	hint.size = Vector2(354,30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var top := add(home,HBoxContainer.new(),"TopBar",true) as HBoxContainer
	top.position=Vector2(18,16)
	top.size=Vector2(354,52)
	top.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var wallet := add(top,PanelContainer.new(),"WalletPill") as PanelContainer
	wallet.add_theme_stylebox_override("panel",style(Color("fff8e9"),26,true))
	var wallet_row := add(wallet,HBoxContainer.new(),"WalletContents") as HBoxContainer
	wallet_row.add_theme_constant_override("separation",4)
	var coin := add(wallet_row,TextureRect.new(),"Coin") as TextureRect
	coin.texture=load(ASSETS+"CoinIcon.png")
	coin.custom_minimum_size=Vector2(37,37)
	coin.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var cash := label(wallet_row,"Cash","0",23)
	cash.custom_minimum_size.x=28
	cash.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var spacer := add(top,Control.new(),"Spacer") as Control
	spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	spacer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var settings := button(top,"Settings","SettingsIcon","Settings")
	settings.add_theme_stylebox_override("normal",style(Color("fff8e9"),26,true))
	settings.add_theme_constant_override("icon_max_width",38)
	var dock := add(home,PanelContainer.new(),"Dock",true) as PanelContainer
	dock.position=Vector2(25,750)
	dock.size=Vector2(340,76)
	dock.add_theme_stylebox_override("panel",style(Color("fff8e9"),28,true))
	var nav := add(dock,HBoxContainer.new(),"Navigation") as HBoxContainer
	nav.add_theme_constant_override("separation",6)
	for definition in [["NavShop","FloatingShop","Shop"],["NavItems","BrushIcon","Tools"],["NavPlans","BlueprintIcon","Blueprints"],["NavBonzi","BonziIcon","Bonzi"]]:
		var b := button(nav,definition[0],definition[1],definition[2])
		b.custom_minimum_size=Vector2(64,64)
		b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if definition[0]=="NavShop": b.add_theme_stylebox_override("normal",style(Color("dbedce"),22))
	var notice := add(home,Button.new(),"ReturnNotice",true) as Button
	notice.visible=false
	notice.text="While away"
	notice.add_theme_font_size_override("font_size",15)
	notice.add_theme_color_override("font_color",Color("355876"))
	notice.add_theme_stylebox_override("normal",style(Color("fff3ce"),22,true))
	var timer := add(home,Timer.new(),"HintTimer",true) as Timer
	timer.one_shot=true
	timer.wait_time=5
	var settings_sheet := add(home,Control.new(),"SettingsSheet",true) as Control
	full(settings_sheet)
	settings_sheet.visible=false
	var dim := add(settings_sheet,ColorRect.new(),"Dim") as ColorRect
	full(dim)
	dim.color=Color(.15,.30,.42,.25)
	var panel := add(settings_sheet,PanelContainer.new(),"SettingsPanel",true) as PanelContainer
	panel.position=Vector2(45,322)
	panel.size=Vector2(300,200)
	panel.add_theme_stylebox_override("panel",style(Color("fff8e9"),26,true))
	var column := add(panel,VBoxContainer.new(),"SettingsContents") as VBoxContainer
	column.add_theme_constant_override("separation",12)
	label(column,"SettingsTitle","Settings",24)
	var motion := add(column,CheckButton.new(),"MotionToggle",true) as CheckButton
	motion.text="Animate shop"
	motion.button_pressed=true
	motion.custom_minimum_size.y=48
	readable_button_text(motion)
	var close := add(column,Button.new(),"CloseSettings",true) as Button
	close.text="Done"
	close.custom_minimum_size.y=48
	close.add_theme_stylebox_override("normal",style(Color("dbedce"),16))
	readable_button_text(close)
	var management := add(home,Control.new(),"Management",true) as Control
	full(management)
	management.visible=false
	var back := add(management,Button.new(),"CloseManagement",true) as Button
	back.text="‹  Home"
	back.visible=false
	back.size=Vector2(104,48)
	back.position=Vector2(18,12)
	back.add_theme_stylebox_override("normal",style(Color("dbedce"),18))
	back.add_theme_color_override("font_color",Color("355876"))
	home.set_script(load("res://scripts/floating_home.gd"))
	load("res://../tools/home_navigation_authoring.gd").decorate(home)
	load("res://../tools/home_settings_authoring.gd").decorate(home)
	var packed := PackedScene.new()
	assert(packed.pack(home)==OK)
	assert(ResourceSaver.save(packed,"res://scenes/production/floating_home.tscn")==OK)
	home.free()
	print("FLOATING_HOME_SCENE_SAVED")
	quit()
