extends Control
## Authored compact sheets for the active branch.
signal closed
const Pop = preload("res://scripts/ui/button_pop.gd")
const Coin = preload("res://assets/floating_shop/CoinIcon.png")
const Brush = preload("res://assets/floating_shop/BrushIcon.png")
const Buddy = preload("res://assets/floating_shop/BonziIcon.png")
const Store = preload("res://assets/floating_shop/FloatingShop.png")
const ROW_IDS := ["hand_brush", "wide_brush", "bonzi", "bonzi_mk2", "intake"]
var current_tab := "shop"
var ledger: Node
var pending_item := ""
var touch_id := -1
var touch_start := Vector2.ZERO
var touch_button: Button
var dragged := false
var scroll_start := 0
var scrolling := false
var rows: Dictionary = {}
var actions: Dictionary = {}
var view: Dictionary = {}
var sheet_focus_modes: Dictionary = {}
var focus_before_review: Control

func _ready() -> void:
	ledger = get_node("/root/ShopState")
	for row in %Rows.get_children():
		var id := str(row.get_meta("item_id"))
		rows[id] = row
		action_for(id).pressed.connect(_item_action.bind(id))
	for index in ROW_IDS.size(): %Rows.move_child(rows[ROW_IDS[index]], index)
	for button in find_children("*", "Button", true, false): Pop.bind(button)
	%CloseSheet.pressed.connect(_close)
	%Backdrop.pressed.connect(_close)
	%CancelBuild.pressed.connect(cancel_build)
	%ConfirmBuild.pressed.connect(confirm_build)
	%ConfirmBuild.focus_next = %ConfirmBuild.get_path_to(%CancelBuild)
	%ConfirmBuild.focus_previous = %ConfirmBuild.get_path_to(%CancelBuild)
	%CancelBuild.focus_next = %CancelBuild.get_path_to(%ConfirmBuild)
	%CancelBuild.focus_previous = %CancelBuild.get_path_to(%ConfirmBuild)
	ledger.changed.connect(refresh)
	resized.connect(_layout)
	show_tab("shop")

func action_for(id: String) -> Button:
	return rows[id].get_node("Row/Action")

func _row(index: int, title: String, detail: String, caption: String, action: String, enabled: bool, texture: Texture2D, price: bool = false) -> void:
	var id: String = ROW_IDS[index]
	var row: Control = rows[id]
	row.show()
	row.get_node("Row/Words/Title").text = title
	row.get_node("Row/Words/Status").text = detail
	row.get_node("Row/Artwork").texture = texture
	var button := action_for(id)
	button.text = caption
	button.icon = Coin if price else null
	button.disabled = not enabled
	actions[id] = action

func _layout() -> void:
	if not is_node_ready(): return
	var count := 0
	for row in rows.values():
		if row.visible: count += 1
	var desired := 112.0 + count * 88.0 + (94.0 if %Routine.visible else 0.0) + (44.0 if %SheetNote.visible else 0.0)
	%Sheet.size = Vector2(minf(430, size.x - 24), minf(desired, size.y - 24))
	%Sheet.position = (size - %Sheet.size) * 0.5
	%ConfirmPanel.size = Vector2(minf(336, size.x - 36), 280)
	%ConfirmPanel.position = (size - %ConfirmPanel.size) * 0.5

func show_tab(tab: String) -> void:
	if tab not in ["shop", "items", "plans", "bonzi"]: return
	current_tab = tab
	%SheetTitle.text = {"shop":"Shop", "items":"Tools", "plans":"Stores", "bonzi":"Bonzi"}[tab]
	%SheetNote.hide()
	%MenuScroll.scroll_vertical = 0
	cancel_build()
	refresh()

func refresh() -> void:
	if ledger == null: return
	var focused := get_viewport().gui_get_focus_owner()
	view = ledger.progression_view()
	%SheetCash.text = _amount(ledger.cash)
	%SheetCash.tooltip_text = "%d coins" % ledger.cash
	for row in rows.values(): row.hide()
	actions.clear()
	%Routine.visible = current_tab == "bonzi" and int(view.bonzi_tier) >= 0
	%RoutineRate.text = "%s coins / %ds" % [_amount(view.bonzi_reward), int(view.bonzi_seconds)]
	if current_tab == "shop":
		_row(0, "Rug value · %d" % view.payout_level, "85%% %s → %s\n99%% %s → %s" % [_amount(view.early_reward), _amount(view.next_early), _amount(view.full_reward), _amount(view.next_full)], _amount(view.payout_cost), "payout", _afford(view.payout_cost), Coin, true)
		_tool_row(1)
	elif current_tab == "items":
		_row(0, str(view.tool_name), "Width ×%.2f · Power ×%.2f" % [view.tool_width, view.tool_power], "Using", "", false, Brush)
		_tool_row(1)
	elif current_tab == "bonzi":
		var tier: int = view.bonzi_tier
		var detail := "%s / %s earned" % [_amount(view.bonzi_earned), _amount(view.bonzi_target)]
		var cost: int = view.bonzi_cost
		if tier < 0: detail = "3 rugs to meet Bonzi" if int(view.local_jobs) < 3 else "10 coins / 120s"
		_row(0, "Bonzi" if tier < 0 else "Bonzi · %d/3" % (tier + 1), detail, "Max" if cost < 0 else _amount(cost), "bonzi", bool(view.can_upgrade_bonzi), Buddy, cost >= 0)
		if tier >= 0 and tier < 2:
			var next_reward: int = (20 if tier == 0 else 40) * int(pow(8, int(view.store_id) - 1))
			_row(1, "Next", "%s coins / %ds" % [_amount(next_reward), 90 if tier == 0 else 60], "", "", false, Buddy)
	else:
		var owned: Array = view.owned_store_ids
		var titles := ["Neighborhood", "High Street", "Wash House", "Restoration"]
		for index in 4:
			var id := index + 1
			var selected := id == int(view.store_id)
			var available := id in owned
			_row(index, "%d · %s" % [id, titles[index]], "Brush" if id <= 2 else "Water + squeegee", "Here" if selected else ("Visit" if available else "Locked"), "store:%d" % id, available and not selected, Store)
		if bool(view.has_next_store):
			_row(4, "Next store", "Bonzi %s/%s · Tool %d/4\nFinal rugs %d/%d" % [_amount(view.bonzi_earned), _amount(view.bonzi_target), view.tool_level, view.final_tool_jobs, view.final_tool_target], _amount(view.travel_cost), "travel", bool(view.can_travel), Store, true)
	if not pending_item.is_empty(): _refresh_confirmation()
	_layout()
	if pending_item.is_empty() and is_instance_valid(focused) and %Sheet.is_ancestor_of(focused):
		_restore_sheet_focus(focused)

func _tool_row(index: int) -> void:
	var cost: int = view.tool_cost
	_row(index, "Complete" if cost < 0 else str(view.next_tool_name), "%d/4 · %s" % [view.tool_level, "Wet tools" if int(view.store_id) >= 3 else "Brush"], "Max" if cost < 0 else _amount(cost), "tool", _afford(cost), Brush, cost >= 0)

func _afford(cost: int) -> bool:
	return cost >= 0 and ledger.cash >= cost

func _amount(value: int) -> String:
	if value < 0: return "—"
	if value >= 1_000_000_000_000_000: return "%.1fQ" % (float(value) / 1_000_000_000_000_000.0)
	if value >= 1_000_000_000_000: return "%.1fT" % (float(value) / 1_000_000_000_000.0)
	if value >= 1_000_000_000: return "%.1fB" % (float(value) / 1_000_000_000.0)
	if value >= 1_000_000: return "%.1fM" % (float(value) / 1_000_000.0)
	if value >= 10_000: return "%.1fK" % (float(value) / 1_000.0)
	return str(value)

func _process(_delta: float) -> void:
	if not is_visible_in_tree() or not %Routine.visible or ledger == null: return
	var seconds: float = ledger.seconds_to_delivery()
	%RoutineProgress.value = 100.0 * (1.0 - seconds / maxf(float(view.bonzi_seconds), 1.0))
	%RoutineTime.text = "%ds" % ceili(seconds)

func _item_action(id: String) -> void:
	var action: String = actions.get(id, "")
	if action == "travel":
		pending_item = "travel"
		_refresh_confirmation()
		focus_before_review = get_viewport().gui_get_focus_owner()
		_set_review_focus(true)
		%PurchaseReview.show()
		%ConfirmBuild.grab_focus()
		return
	var success := false
	match action:
		"payout": success = ledger.buy_payout_upgrade()
		"tool": success = ledger.buy_tool_upgrade()
		"bonzi": success = ledger.buy_bonzi_upgrade()
		_:
			if action.begins_with("store:"): success = ledger.select_store(int(action.get_slice(":", 1)))
	if not success and not action.is_empty(): _notice(ledger.last_error if not ledger.last_error.is_empty() else "Not available yet")
	refresh()

func _refresh_confirmation() -> void:
	%BuildTitle.text = "Open next store?"
	%BuildBenefit.text = "Starter tools + Bonzi included"
	%BuildBalance.text = "%s coins · %s left" % [_amount(view.travel_cost), _amount(ledger.cash - int(view.travel_cost))]
	%ConfirmBuild.text = "Open · %s" % _amount(view.travel_cost)
	%ConfirmBuild.disabled = not bool(view.can_travel)

func confirm_build() -> void:
	if pending_item != "travel": return
	cancel_build()
	if ledger.open_next_store(): _notice("Store opened")
	else: _notice(ledger.last_error if not ledger.last_error.is_empty() else "Finish the store milestones first")
	refresh()

func cancel_build() -> void:
	var was_open: bool = %PurchaseReview.visible
	pending_item = ""
	%PurchaseReview.hide()
	_set_review_focus(false)
	if was_open: _restore_sheet_focus(focus_before_review)
	focus_before_review = null

func _restore_sheet_focus(previous: Control) -> void:
	if not is_visible_in_tree(): return
	if is_instance_valid(previous) and previous.is_visible_in_tree() and previous.focus_mode != Control.FOCUS_NONE and (not previous is Button or not previous.disabled):
		previous.grab_focus()
	else:
		%CloseSheet.grab_focus()

func _set_review_focus(reviewing: bool) -> void:
	for button: Button in %Sheet.find_children("*", "Button", true, false):
		if reviewing:
			sheet_focus_modes[button] = button.focus_mode
			button.focus_mode = Control.FOCUS_NONE
		elif sheet_focus_modes.has(button):
			button.focus_mode = sheet_focus_modes[button]
	if not reviewing: sheet_focus_modes.clear()

func _notice(message: String) -> void:
	%SheetNote.text = message
	%SheetNote.show()
	_layout()

func _close() -> void:
	if not pending_item.is_empty(): cancel_build()
	else:
		reset_touch()
		closed.emit()

func back() -> void:
	_close()

func _button_at(point: Vector2) -> Button:
	var candidates: Array[Button] = []
	if %PurchaseReview.visible: candidates.assign([%CancelBuild, %ConfirmBuild])
	else:
		candidates.append(%CloseSheet)
		for id: String in rows:
			if rows[id].is_visible_in_tree() and %MenuScroll.get_global_rect().has_point(point): candidates.append(action_for(id))
		if not %Sheet.get_global_rect().has_point(point): candidates.append(%Backdrop)
	for button in candidates:
		if button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(point): return button
	return null

func handle_touch(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if touch_id != -1:
				dragged = true
				if is_instance_valid(touch_button): Pop.reset(touch_button)
				return
			touch_id = event.index
			touch_start = event.position
			touch_button = _button_at(event.position)
			dragged = false
			scroll_start = %MenuScroll.scroll_vertical
			scrolling = not %PurchaseReview.visible and %MenuScroll.get_global_rect().has_point(event.position)
			if is_instance_valid(touch_button): Pop.press(touch_button)
		elif touch_id == event.index:
			var target := touch_button
			var activate: bool = not event.canceled and not dragged and touch_start.distance_to(event.position) < 12 and _button_at(event.position) == target
			reset_touch()
			if activate and is_instance_valid(target):
				Pop.release(target)
				target.pressed.emit()
	elif event is InputEventScreenDrag and event.index == touch_id:
		if touch_start.distance_to(event.position) >= 12:
			dragged = true
			if is_instance_valid(touch_button): Pop.reset(touch_button)
		if dragged and scrolling: %MenuScroll.scroll_vertical = scroll_start - roundi(event.position.y - touch_start.y)

func reset_touch() -> void:
	if is_instance_valid(touch_button): Pop.reset(touch_button)
	touch_id = -1
	touch_button = null
	dragged = false
