extends Control
## Visual wardrobe: one preview, immediate choices, and no purchase flow.
signal closed
const Catalog = preload("res://scripts/avatar_catalog.gd")
const Pop = preload("res://scripts/ui/button_pop.gd")
const INK := Color("355876")
const SELECTED := Color("add99c")
var ledger: Node
var current_tab := "hats"
var safe_rect := Rect2()
var touch_id := -1
var touch_origin := Vector2.ZERO
var touch_button: Button
var touch_dragged := false
var scrolling := false
var scroll_start := 0
var hat_cards: Dictionary = {}
var color_cards: Dictionary = {}
var preview_dragging := false
var pointer_last := Vector2.ZERO
var mouse_down := false
var mouse_start := Vector2.ZERO
var mouse_button: Button
var mouse_dragged := false
var mouse_scrolling := false
var mouse_scroll_start := 0

func _ready() -> void:
	ledger = get_node("/root/ShopState")
	for card: Button in %Cards.get_children():
		Pop.bind(card)
		var id := str(card.get_meta("item_id"))
		if str(card.get_meta("category")) == "hats":
			hat_cards[id] = card
			card.pressed.connect(_equip_hat.bind(id))
		else:
			color_cards[id] = card
			card.pressed.connect(_equip_color.bind(id))
			for entry: Dictionary in Catalog.COLORS:
				if str(entry.id) == id:
					card.get_node("Artwork/Swatch").color = entry.color
					card.get_node("Name").text = entry.name
					card.tooltip_text = entry.name
	for button in [%Back, %HatsTab, %ColorTab]: Pop.bind(button)
	%Back.pressed.connect(back)
	%HatsTab.pressed.connect(show_tab.bind("hats"))
	%ColorTab.pressed.connect(show_tab.bind("color"))
	%SaveErrorTimer.timeout.connect(%SaveError.hide)
	ledger.appearance_changed.connect(_refresh)
	resized.connect(_layout)
	visibility_changed.connect(_on_visibility_changed)
	_refresh(ledger.appearance)
	show_tab("hats")
	_on_visibility_changed()

func set_safe_rect(rect: Rect2) -> void:
	safe_rect = rect
	_layout()

func open(motion_enabled: bool) -> void:
	show()
	%Preview.set_motion(motion_enabled)
	%Preview.set_active(true)
	_refresh(ledger.appearance)
	%Back.grab_focus()

func close() -> void:
	reset_touch()
	hide()
	%Preview.set_active(false)

func back() -> void:
	reset_touch()
	closed.emit()

func set_focused(enabled: bool) -> void:
	if not enabled: reset_touch()
	%Preview.set_focused(enabled)

func _on_visibility_changed() -> void:
	if not is_node_ready(): return
	%Preview.set_active(is_visible_in_tree())
	for button: Button in find_children("*", "Button", true, false):
		button.focus_mode = Control.FOCUS_ALL if is_visible_in_tree() else Control.FOCUS_NONE

func show_tab(tab: String) -> void:
	if tab not in ["hats", "color"]: return
	reset_touch()
	current_tab = tab
	%HatsTab.set_pressed_no_signal(tab == "hats")
	%ColorTab.set_pressed_no_signal(tab == "color")
	for card: Button in hat_cards.values(): card.visible = tab == "hats"
	for card: Button in color_cards.values(): card.visible = tab == "color"
	%CollectionScroll.scroll_vertical = 0
	_layout()

func _refresh(appearance: Dictionary) -> void:
	%Preview.set_appearance(appearance)
	for id: String in hat_cards: _set_selected(hat_cards[id], id == str(appearance.hat_id))
	for id: String in color_cards: _set_selected(color_cards[id], id == str(appearance.color_id))

func _set_selected(card: Button, selected: bool) -> void:
	card.set_pressed_no_signal(selected)
	card.get_node("Selected").visible = selected

func _equip_hat(id: String) -> void:
	_choose(str(ledger.appearance.color_id), id)

func _equip_color(id: String) -> void:
	_choose(id, str(ledger.appearance.hat_id))

func _choose(color_id: String, hat_id: String) -> void:
	if ledger.set_appearance(color_id, hat_id):
		%SaveError.hide()
		%SaveErrorTimer.stop()
		_refresh(ledger.appearance)
	else:
		%SaveError.text = "Couldn’t save. Try again."
		%SaveError.show()
		%SaveErrorTimer.start()
		_refresh(ledger.appearance)

func _layout() -> void:
	if not is_node_ready(): return
	var safe := safe_rect if safe_rect.size.x > 0 else Rect2(Vector2.ZERO, size)
	var wide := safe.size.x > safe.size.y * 1.2
	var margin := 16.0
	var content_width := maxf(safe.size.x - margin * 2.0, 1.0)
	# Home uses a390-unit short side. Preserve a44px minimum target even
	# when a smaller physical display scales that canvas down.
	var logical_size := get_viewport().get_visible_rect().size
	var physical_size := Vector2(get_window().size)
	var pixels_per_unit := minf(physical_size.x / maxf(logical_size.x, 1.0), physical_size.y / maxf(logical_size.y, 1.0))
	var target_height := maxf(44.0, 44.0 / maxf(pixels_per_unit, 0.1))
	%Header.position = safe.position + Vector2(margin, 8)
	%Header.size = Vector2(content_width, target_height)
	%Back.size = Vector2.ONE * target_height
	%Header.get_node("Title").position = Vector2(target_height + 14.0, 0)
	%Header.get_node("Title").size = Vector2(maxf(content_width - target_height - 14.0, 1.0), target_height)
	var preview_height := clampf(safe.size.y * (0.33 if wide else 0.41), 96.0, 376.0)
	var preview_width := minf(content_width, 640.0)
	%PreviewCard.position = Vector2(safe.get_center().x - preview_width * 0.5, safe.position.y + target_height + 16.0)
	%PreviewCard.size = Vector2(preview_width, preview_height)
	var collection_width := minf(content_width, 680.0)
	%Tabs.position = Vector2(safe.get_center().x - collection_width * 0.5, %PreviewCard.position.y + preview_height + 12.0)
	%HatsTab.custom_minimum_size.y = target_height
	%ColorTab.custom_minimum_size.y = target_height
	%Tabs.size = Vector2(collection_width, target_height)
	var collection_top: float = %Tabs.position.y + target_height
	%CollectionPanel.position = Vector2(safe.get_center().x - collection_width * 0.5, collection_top)
	%CollectionPanel.size = Vector2(collection_width, maxf(safe.end.y - collection_top - 14.0, 64.0))
	%Cards.columns = 3 if current_tab == "hats" else (8 if wide else 4)
	var card_height := (104.0 if wide else 140.0) if current_tab == "hats" else (78.0 if wide else 96.0)
	for card: Button in %Cards.get_children(): card.custom_minimum_size.y = card_height
	%SaveError.position = Vector2(safe.position.x + margin, safe.end.y - 32)
	%SaveError.size = Vector2(content_width, 26)

func _button_at(point: Vector2) -> Button:
	for button in [%Back, %HatsTab, %ColorTab]:
		if button.is_visible_in_tree() and button.get_global_rect().has_point(point): return button
	if %CollectionScroll.get_global_rect().has_point(point):
		for card: Button in %Cards.get_children():
			if card.is_visible_in_tree() and card.get_global_rect().has_point(point): return card
	return null

func handle_touch(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if touch_id >= 0:
				touch_dragged = true
				if is_instance_valid(touch_button): Pop.reset(touch_button)
				return
			touch_id = event.index
			touch_origin = event.position
			touch_button = _button_at(event.position)
			touch_dragged = false
			scroll_start = %CollectionScroll.scroll_vertical
			scrolling = %CollectionScroll.get_global_rect().has_point(event.position)
			preview_dragging = %Preview.get_global_rect().has_point(event.position)
			pointer_last = event.position
			if preview_dragging: %Preview.begin_drag()
			if is_instance_valid(touch_button): Pop.press(touch_button)
		elif event.index == touch_id:
			var target := touch_button
			var activate: bool = not event.canceled and not touch_dragged and touch_origin.distance_to(event.position) < 12.0 and _button_at(event.position) == target
			reset_touch()
			if activate and is_instance_valid(target):
				Pop.release(target)
				target.pressed.emit()
	elif event is InputEventScreenDrag and event.index == touch_id:
		if preview_dragging:
			%Preview.drag_by(event.position.x - pointer_last.x)
			pointer_last = event.position
		if touch_origin.distance_to(event.position) >= 12.0:
			touch_dragged = true
			if is_instance_valid(touch_button): Pop.reset(touch_button)
		if touch_dragged and scrolling: %CollectionScroll.scroll_vertical = scroll_start - roundi(event.position.y - touch_origin.y)

func reset_touch() -> void:
	if is_instance_valid(touch_button): Pop.reset(touch_button)
	if is_instance_valid(mouse_button): Pop.reset(mouse_button)
	if preview_dragging: %Preview.end_drag()
	touch_id = -1
	touch_button = null
	touch_dragged = false
	scrolling = false
	preview_dragging = false
	mouse_down = false
	mouse_button = null
	mouse_dragged = false
	mouse_scrolling = false

func handle_mouse(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			mouse_down = true
			mouse_start = event.position
			pointer_last = event.position
			mouse_button = _button_at(event.position)
			mouse_dragged = false
			mouse_scrolling = %CollectionScroll.get_global_rect().has_point(event.position)
			mouse_scroll_start = %CollectionScroll.scroll_vertical
			preview_dragging = %Preview.get_global_rect().has_point(event.position)
			if preview_dragging: %Preview.begin_drag()
			if is_instance_valid(mouse_button): Pop.press(mouse_button)
		else:
			var target := mouse_button
			var activate: bool = mouse_down and not mouse_dragged and mouse_start.distance_to(event.position) < 12.0 and _button_at(event.position) == target
			reset_touch()
			if activate and is_instance_valid(target):
				Pop.release(target)
				target.pressed.emit()
		return true
	if event is InputEventMouseMotion and mouse_down:
		if preview_dragging:
			%Preview.drag_by(event.position.x - pointer_last.x)
			pointer_last = event.position
		if mouse_start.distance_to(event.position) >= 12.0:
			mouse_dragged = true
			if is_instance_valid(mouse_button): Pop.reset(mouse_button)
		if mouse_dragged and mouse_scrolling: %CollectionScroll.scroll_vertical = mouse_scroll_start - roundi(event.position.y - mouse_start.y)
		return true
	return false
