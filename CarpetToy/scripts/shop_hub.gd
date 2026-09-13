extends Control
## The outside view and all first-shop management live here; cleaning stays separate.
const INK := Color("284c47")
const MUTED := Color("738b84")
const GREEN := Color("58bc69")
const PAPER := Color("fffcf4")
const LINE := Color("dce7dc")
const ART = preload("res://scripts/shop_illustration.gd")
const TITLES := {"shop": "A little shop. Big plans.", "items": "Your trusty toolkit", "plans": "Good things to build", "bonzi": "Meet your new teammate", "expansion": "A bigger little dream"}
const SUBTITLES := {"shop": "NEIGHBORHOOD / SHOP 01", "items": "THE TOOL BENCH", "plans": "BLUEPRINT COLLECTION", "bonzi": "BONZI'S WORK LANE", "expansion": "LOOKING AHEAD"}
var state: Node
var current_tab := "shop"
var page: VBoxContainer
var scroll: ScrollContainer
var cash_label: Label
var title_label: Label
var eyebrow: Label
var toast_label: Label
var tabs: Dictionary = {}
var buttons: Array[Button] = []
var dirty_ui := false
var delivery_label: Label
var delivery_bar: ProgressBar
var shell: MarginContainer
var touch_candidate: Button
var touch_start := Vector2.ZERO
var touch_id := -1

func _ready() -> void:
	state = get_node("/root/ShopState")
	state.contract_mode = false
	build_shell()
	state.changed.connect(func(): dirty_ui = true)
	resized.connect(layout_shell)
	layout_shell()
	show_tab("shop")
	if not state.last_error.is_empty():
		toast(state.last_error)

func box(fill: Color, border: Color = LINE, radius: int = 22, depth: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(2)
	s.border_width_bottom = 2 + depth
	s.set_corner_radius_all(radius)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 16
	s.content_margin_bottom = 16 + depth
	return s

func text_label(value: String, font_size: int = 18, color: Color = INK, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = value
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func copy(parent: Node, value: String, font_size: int = 18, color: Color = INK) -> Label:
	var l := text_label(value, font_size, color, true)
	parent.add_child(l)
	return l

func vertical(parent: Node, separation: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(v)
	return v

func horizontal(parent: Node, separation: int = 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	parent.add_child(h)
	return h

func card(parent: Node, color: Color = Color.WHITE) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	return vertical(p, 10)

func pill(parent: Node, value: String, fill: Color, ink: Color = INK) -> void:
	var p := PanelContainer.new()
	var s := box(fill, fill, 10)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", s)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(p)
	p.add_child(text_label(value, 12, ink))

func action(parent: Node, value: String, handler: Callable, primary: bool = false, enabled: bool = true, node_name: String = "") -> Button:
	var b := Button.new()
	b.text = value
	if not node_name.is_empty(): b.name = node_name
	b.custom_minimum_size.y = 54
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", Color.WHITE if primary else INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE if primary else INK)
	b.add_theme_color_override("font_pressed_color", Color.WHITE if primary else INK)
	b.add_theme_color_override("font_disabled_color", MUTED)
	b.add_theme_stylebox_override("normal", box(GREEN if primary else Color.WHITE, Color("3b9852") if primary else LINE, 16, 4))
	b.add_theme_stylebox_override("hover", box(Color("65c976") if primary else Color("f0f7ea"), Color("3b9852") if primary else Color("b6d6b4"), 16, 4))
	b.add_theme_stylebox_override("pressed", box(Color("4fac60") if primary else Color("e6f2df"), Color("3b9852") if primary else Color("b6d6b4"), 16))
	b.add_theme_stylebox_override("disabled", box(Color("eef1e9"), LINE, 16, 2))
	var focus := box(Color(0, 0, 0, 0), Color("479ec3"), 16)
	focus.set_border_width_all(3)
	b.add_theme_stylebox_override("focus", focus)
	b.disabled = not enabled
	b.pressed.connect(handler)
	parent.add_child(b)
	buttons.append(b)
	return b

func illustration(parent: Node, kind: String, height: float, working: bool = false) -> Control:
	var a := Control.new()
	a.set_script(ART)
	a.kind = kind
	a.working = working
	a.custom_minimum_size = Vector2(0, height)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(a)
	return a

func build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = PAPER
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell = MarginContainer.new()
	add_child(shell)
	for side in ["left", "right", "top", "bottom"]:
		shell.add_theme_constant_override("margin_" + side, 24)
	var layout := vertical(shell, 18)
	var top := horizontal(layout)
	var brand := text_label("mint meadow", 23)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(brand)
	var wallet := PanelContainer.new()
	var wallet_style := box(Color("fff0b7"), Color("edd385"), 16)
	wallet_style.content_margin_top = 6
	wallet_style.content_margin_bottom = 6
	wallet.add_theme_stylebox_override("panel", wallet_style)
	top.add_child(wallet)
	cash_label = text_label("0  cash", 21, Color("8c7024"))
	cash_label.name = "Wallet"
	wallet.add_child(cash_label)
	var headings := vertical(layout, 4)
	eyebrow = text_label("", 13, MUTED)
	headings.add_child(eyebrow)
	title_label = text_label("", 32, INK, true)
	headings.add_child(title_label)
	scroll = ScrollContainer.new()
	scroll.name = "PageScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	page = vertical(scroll, 16)
	toast_label = text_label("", 15, Color("458857"), true)
	toast_label.visible = false
	layout.add_child(toast_label)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	layout.add_child(nav)
	for tab in ["shop", "items", "plans", "bonzi"]:
		var b := action(nav, {"shop":"SHOP", "items":"ITEMS", "plans":"PLANS", "bonzi":"BONZI"}[tab], show_tab.bind(tab), false, true, "Tab_" + tab)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 62
		b.add_theme_font_size_override("font_size", 14)
		tabs[tab] = b

func layout_shell() -> void:
	var width := minf(size.x, 800.0)
	shell.position = Vector2((size.x - width) / 2, 0)
	shell.size = Vector2(width, size.y)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled and touch_id == -1:
			touch_id = event.index
			touch_start = event.position
			touch_candidate = button_at(event.position)
		elif event.index == touch_id and (not event.pressed or event.canceled):
			var candidate := touch_candidate
			touch_id = -1
			touch_candidate = null
			if not event.canceled and is_instance_valid(candidate) and button_at(event.position) == candidate and touch_start.distance_to(event.position) < 14.0:
				candidate.pressed.emit()
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == touch_id and touch_start.distance_to(event.position) >= 14.0:
		touch_candidate = null

func button_at(point: Vector2) -> Button:
	for b in buttons:
		if is_instance_valid(b) and b.is_visible_in_tree() and not b.disabled and b.get_global_rect().has_point(point):
			if scroll.is_ancestor_of(b) and not scroll.get_global_rect().has_point(point): continue
			return b
	return null

func _process(_delta: float) -> void:
	if dirty_ui:
		dirty_ui = false
		var old_scroll := scroll.scroll_vertical
		show_tab(current_tab)
		scroll.set_deferred("scroll_vertical", old_scroll)
	if is_instance_valid(delivery_label) and state.owns("bonzi"):
		var seconds: int = ceili(state.seconds_to_delivery())
		delivery_label.text = "Next delivery in %d:%02d  /  +10 cash" % [seconds / 60, seconds % 60]
	if is_instance_valid(delivery_bar):
		delivery_bar.value = state.routine_remainder * 100.0

func show_tab(tab: String) -> void:
	current_tab = tab
	buttons = buttons.filter(func(b): return is_instance_valid(b) and not scroll.is_ancestor_of(b))
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	delivery_label = null
	delivery_bar = null
	cash_label.text = "%d  cash" % state.cash
	eyebrow.text = SUBTITLES[tab]
	title_label.text = TITLES[tab]
	for key in tabs:
		var selected: bool = key == tab or (key == "shop" and tab == "expansion")
		tabs[key].add_theme_stylebox_override("normal", box(Color("e3f4d9") if selected else Color.WHITE, Color("89bf78") if selected else LINE, 16, 4))
		tabs[key].add_theme_color_override("font_color", Color("3e8247") if selected else MUTED)
	match tab:
		"shop": build_shop()
		"items": build_items()
		"plans": build_plans()
		"bonzi": build_bonzi()
		"expansion": build_expansion()
	if tab == "shop" and state.return_reward > 0:
		show_return_card()
	scroll.scroll_vertical = 0

func progress(parent: Node, value: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 14
	bar.show_percentage = false
	bar.value = value * 100
	var track := box(Color("e5eddf"), Color("e5eddf"), 7)
	track.content_margin_top = 0
	track.content_margin_bottom = 0
	bar.add_theme_stylebox_override("background", track)
	var fill := track.duplicate()
	fill.bg_color = GREEN
	fill.border_color = GREEN
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar

func build_shop() -> void:
	var hero := card(page, Color("edf7e6"))
	var meta := horizontal(hero)
	var shop_name := text_label("Neighborhood Shop", 22)
	shop_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(shop_name)
	pill(meta, "OPEN", Color("d3efc8"), Color("488342"))
	illustration(hero, "store", 198, state.owns("bonzi"))
	var stats := horizontal(hero, 24)
	for pair in [[str(state.manual_jobs), "rugs cleaned"], [str(state.automated_jobs), "Bonzi deliveries"], [str(roundi(state.output_per_hour() * 10)), "cash / hour"]]:
		var cell := vertical(stats, 2)
		copy(cell, pair[0], 25)
		copy(cell, pair[1], 12, MUTED)
	action(page, "RESUME YOUR RUG  /  +20 cash" if not state.active_job_id.is_empty() else "CLEAN A RUG  /  +20 cash", enter_cleaning, true, true, "CleanRugButton")
	var goal := card(page)
	if not state.owns("bonzi"):
		pill(goal, "YOUR NEXT LITTLE WIN", Color("fff0c5"), Color("95772c"))
		copy(goal, "A helping hand named Bonzi", 22)
		if not state.blueprint_known("bonzi"):
			copy(goal, "Finish 3 customer rugs to discover his blueprint. Then build your buddy for 100 cash.", 16, MUTED)
			progress(goal, float(state.manual_jobs) / 3.0)
			copy(goal, "%d / 3 rugs cleaned" % mini(state.manual_jobs, 3), 13, MUTED)
		else:
			copy(goal, "Blueprint found! Bonzi handles routine orders while you enjoy your own rugs.", 16, MUTED)
			action(goal, "MEET BONZI", show_tab.bind("bonzi"), false, true, "MeetBonziButton")
	else:
		pill(goal, "A GOOD DAY AT THE SHOP", Color("e3f4d9"))
		copy(goal, "Bonzi has the routine covered", 22)
		copy(goal, "%d orders per hour. Your customer rugs are a separate lane." % roundi(state.output_per_hour()), 16, MUTED)
		delivery_bar = progress(goal, state.routine_remainder)
		delivery_label = copy(goal, "", 14, MUTED)
	var footer := horizontal(page)
	var gym := action(footer, "Rug Cleaning Gym", enter_gym, false, true, "GymButton")
	gym.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var plan := action(footer, "Shop plans", show_expansion, false, true, "ExpansionButton")
	plan.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func build_items() -> void:
	copy(page, "Keep the tools you build. Each one has a job to do.", 17, MUTED)
	item_card("hand_brush", "Hand Brush", "Your reliable starter. Sweep loose dirt off small rugs.", "brush", "Always ready", false)
	item_card("wide_brush", "Wide Brush", "A broader brush head cleans a wider strip with every sweep.", "brush", "Wider cleaning footprint", false)
	var future := card(page, Color("f2f4ee"))
	pill(future, "NEXT SHOP'S KIT", Color("e0e6df"), MUTED)
	copy(future, "Jet spray + squeegee", 22)
	copy(future, "Washable rugs need a different approach. This kit belongs to the planned High Street shop.", 16, MUTED)
	action(future, "Try the models in the gym", enter_gym, false, true, "TryToolsButton")

func item_card(id: String, title: String, description: String, art_kind: String, benefit: String, module: bool) -> void:
	var c := card(page)
	var row := horizontal(c)
	var art := illustration(row, art_kind, 100)
	art.custom_minimum_size.x = 118
	art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var detail := vertical(row, 5)
	pill(detail, "INSTALLED" if state.owns(id) and module else ("OWNED" if state.owns(id) else ("BLUEPRINT READY" if state.blueprint_known(id) else "BLUEPRINT LOCKED")), Color("e3f4d9") if state.owns(id) else Color("eef2ed"))
	copy(detail, title, 23)
	copy(detail, description, 16, MUTED)
	copy(c, benefit, 15, Color("54824d"))
	if state.owns(id):
		copy(c, "Installed in this shop" if module else "Available on your cleaning pad", 13, MUTED)
	else:
		build_control(c, id)

func build_control(parent: Node, id: String) -> void:
	var cost: int = state.build_cost(id)
	if not state.blueprint_known(id):
		var required: int = state.unlock_requirement(id)
		var gate := "Unlocks after %d customer rugs (%d / %d)" % [required, mini(state.manual_jobs, required), required]
		if id in ["bonzi_mk2", "intake"] and not state.owns("bonzi"):
			gate += " and building Bonzi"
		copy(parent, gate, 14, MUTED)
		action(parent, "BLUEPRINT LOCKED  /  %d cash to build" % cost, func(): pass, false, false)
	elif state.cash < cost:
		copy(parent, "Blueprint collected. Save %d more cash to build it." % (cost - state.cash), 14, MUTED)
		action(parent, "BUILD  /  %d cash" % cost, buy.bind(id), false, false, "Build_" + id)
	else:
		action(parent, "BUILD  /  %d cash" % cost, buy.bind(id), true, true, "Build_" + id)

func build_plans() -> void:
	var intro := card(page, Color("eaf4f8"))
	var row := horizontal(intro)
	var art := illustration(row, "blueprint", 100)
	art.custom_minimum_size.x = 118
	art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var words := vertical(row, 6)
	copy(words, "Find it. Keep it. Build it.", 23)
	copy(words, "Blueprints unlock at milestones and stay yours. Cash turns a plan into something useful.", 16, MUTED)
	for data in [["bonzi", "Bonzi", "Your first automated cleaner", 3], ["wide_brush", "Wide Brush", "A little more sweep per stroke", 8], ["bonzi_mk2", "Bonzi Mk II", "A faster cleaner for this shop", 10], ["intake", "Welcome Sign", "Help more routine orders find you", 10]]:
		var c := card(page)
		var row_title := horizontal(c)
		var title := text_label(data[1], 23)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_title.add_child(title)
		pill(row_title, "BUILT" if state.owns(data[0]) else ("FOUND" if state.blueprint_known(data[0]) else "%d RUGS" % data[3]), Color("e3f4d9") if state.blueprint_known(data[0]) else Color("eef2ed"))
		copy(c, data[2], 16, MUTED)
		if state.owns(data[0]):
			copy(c, "Blueprint kept in your collection", 14, MUTED)
		else:
			build_control(c, data[0])

func build_bonzi() -> void:
	var hero := card(page, Color("edf7e6"))
	pill(hero, "ON DUTY" if state.owns("bonzi") else "YOUR FIRST CLEANING BUDDY", Color("d6eecb"))
	illustration(hero, "bonzi", 205, state.owns("bonzi"))
	copy(hero, "You do the satisfying stuff.", 25)
	copy(hero, "Bonzi takes care of routine orders. He keeps working while you clean, browse, or step away.", 17, MUTED)
	if not state.owns("bonzi"):
		copy(hero, "30 orders / hour   ·   10 cash / delivery", 17, Color("54824d"))
		build_control(hero, "bonzi")
	else:
		copy(hero, "%d cash / hour  ·  %d orders / hour" % [roundi(state.output_per_hour() * 10), roundi(state.output_per_hour())], 22, Color("54824d"))
		delivery_bar = progress(hero, state.routine_remainder)
		delivery_label = copy(hero, "", 15, MUTED)
		var rates := card(page)
		copy(rates, "What sets the pace?", 22)
		copy(rates, "Incoming orders: %d / hour\nCleaner capacity: %d / hour\nCurrent limit: %s" % [roundi(state.demand_per_hour()), roundi(state.capacity_per_hour()), state.bottleneck()], 17, MUTED)
		copy(rates, "Cash arrives after each completed delivery. Away earnings are capped at 8 hours per visit.", 14, MUTED)
	var mk_benefit := "+100 cash / hour at current demand" if not state.owns("intake") else "+150 cash / hour with your Welcome Sign"
	item_card("bonzi_mk2", "Bonzi Mk II", "Cleaner capacity grows from 30 to 45 orders per hour.", "upgrade", mk_benefit, true)
	var intake_benefit := "+50 cash / hour with Bonzi Mk II" if state.owns("bonzi_mk2") else "No income increase until Bonzi Mk II is built"
	item_card("intake", "Welcome Sign", "Raise routine demand from 40 to 60 orders per hour.", "intake", intake_benefit, true)

func buy(id: String) -> void:
	if state.build(id):
		toast("Built! Your shop just got a little better.")
	else:
		toast("Couldn't build that yet. Check the blueprint, cash, and save storage.")
	dirty_ui = true

func toast(value: String) -> void:
	toast_label.text = value
	toast_label.visible = true

func enter_cleaning() -> void:
	if state.start_job().is_empty():
		toast("Couldn't save this job. Please check save storage and try again.")
		return
	state.contract_mode = true
	get_tree().change_scene_to_file("res://scenes/rug_cleaning_gym.tscn")

func enter_gym() -> void:
	state.contract_mode = false
	get_tree().change_scene_to_file("res://scenes/rug_cleaning_gym.tscn")

func show_expansion() -> void:
	show_tab("expansion")

func build_expansion() -> void:
	var c := card(page, Color("fff0e4"))
	pill(c, "FUTURE LOCATION", Color("f8d8c5"), Color("a56c4b"))
	illustration(c, "store", 235)
	copy(c, "Busy High Street", 29)
	copy(c, "Sunny windows, washable rugs, and a jet + squeegee opening kit. Your Neighborhood Shop will stay yours.", 18, MUTED)
	copy(c, "Planned opening price: 600 cash", 21)
	copy(c, "%s Bonzi built\n%d / 15 customer rugs\n%d / 5 routine deliveries" % ["✓" if state.owns("bonzi") else "○", mini(state.manual_jobs, 15), mini(state.automated_jobs, 5)], 18, MUTED)
	copy(c, "This build focuses on one working shop. High Street opens in a future update.", 15, MUTED)
	action(page, "BACK TO MY SHOP", show_tab.bind("shop"), true)

func show_return_card() -> void:
	var c := card(page, Color("fff1bd"))
	page.move_child(c.get_parent(), 0)
	copy(c, "Welcome back!", 25)
	copy(c, "Bonzi delivered +%d cash while you were away. It's already in your wallet." % state.return_reward, 17)
	action(c, "NICE WORK, BONZI", acknowledge_return, true, true, "AcknowledgeReturnButton")

func acknowledge_return() -> void:
	if not state.acknowledge_return():
		toast(state.last_error)
	dirty_ui = true
