extends Control
## Authored compact sheets for the active branch.
signal closed
const Pop = preload("res://scripts/ui/button_pop.gd")
const Progression = preload("res://scripts/progression.gd")
const Money = preload("res://scripts/money.gd")
const Coin = preload("res://assets/floating_shop/CoinIcon.png")
const Brush = preload("res://assets/floating_shop/BrushIcon.png")
const Buddy = preload("res://assets/floating_shop/BonziIcon.png")
const Store = preload("res://assets/floating_shop/FloatingShop.png")
const RoomUpgrades = preload("res://scripts/room_upgrades.gd")
const ROOM_ICONS := {
	"floor": preload("res://assets/ui/room_upgrades/floor.svg"),
	"plants": preload("res://assets/ui/room_upgrades/plants.svg"),
	"window": preload("res://assets/ui/room_upgrades/window.svg"),
	"railings": preload("res://assets/ui/room_upgrades/railings.svg"),
	"walls": preload("res://assets/ui/room_upgrades/walls.svg"),
}
const ROOM_TITLES := {"floor": "Floor", "plants": "Plants", "window": "Window", "railings": "Railings", "walls": "Walls"}
const ROW_IDS := ["hand_brush", "wide_brush", "bonzi", "bonzi_mk2", "intake"]
const PLAN_ROW_IDS := ["hand_brush", "wide_brush", "bonzi", "bonzi_mk2", "store_5", "store_6", "intake", "next_section"]
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
	# Reuse the authored offer layout for every store and the future section.
	# Copies have no connected actions until the shared row setup below.
	for id: String in ["store_5", "store_6", "next_section"]:
		var row := %Rows.get_child(0).duplicate(0) as Control
		row.name = id
		row.set_meta("item_id", id)
		%Rows.add_child(row)
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
	var id: String = PLAN_ROW_IDS[index] if current_tab == "plans" else ROW_IDS[index]
	var row: Control = rows[id]
	row.show()
	row.get_node("Row/Words/Title").text = title
	row.get_node("Row/Words/Status").text = detail
	row.get_node("Row/Artwork").texture = texture
	var button := action_for(id)
	button.text = caption
	button.icon = Coin if price else null
	button.disabled = not enabled
	button.tooltip_text = ""
	actions[id] = action

func _layout() -> void:
	if not is_node_ready(): return
	var count := 0
	for row in rows.values():
		if row.visible: count += 1
	var desired := 112.0 + count * 88.0 + (94.0 if %Routine.visible else 0.0) + (130.0 if %TravelGoals.visible else 0.0) + (44.0 if %SheetNote.visible else 0.0)
	%Sheet.size = Vector2(minf(500 if current_tab == "plans" else 430, size.x - 24), minf(desired, size.y - 24))
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
	%SheetCash.tooltip_text = "%s coins" % _amount(ledger.cash)
	for row in rows.values(): row.hide()
	var ordered_rows: Array = PLAN_ROW_IDS if current_tab == "plans" else ROW_IDS
	for index in ordered_rows.size(): %Rows.move_child(rows[ordered_rows[index]], index)
	actions.clear()
	%SheetNote.visible = current_tab == "plans"
	%TravelGoals.hide()
	%Routine.visible = current_tab == "bonzi" and int(view.bonzi_tier) >= 0
	%RoutineRate.text = "%s coins / %ds" % [_amount(view.bonzi_reward), int(view.bonzi_seconds)]
	if current_tab == "shop":
		for index in RoomUpgrades.IDS.size():
			var room_id: String = RoomUpgrades.IDS[index]
			var offer: Dictionary = ledger.room_upgrade_view(room_id)
			var cost := float(offer.cost)
			var milestone := int(offer.get("next_visual_level", -1))
			var look := "New look at Lv %d" % milestone if milestone > 0 else "Final look"
			var earnings := "Clean %s" % _amount(float(offer.full_reward)) if cost < 0 else "Clean %s → %s" % [_amount(float(offer.full_reward)), _amount(float(offer.next_full))]
			var detail := earnings + "\n" + look
			_row(index, "%s · Lv %d" % [ROOM_TITLES[room_id], int(offer.level)], detail, "Max" if cost < 0 else _amount(cost), "room:" + room_id, bool(offer.can_upgrade), ROOM_ICONS[room_id], cost >= 0)
			action_for(ROW_IDS[index]).tooltip_text = "This feature has its own upgrade price and earnings."
	elif current_tab == "items":
		var current_detail := "Soak ×%.2f · Width %.2f m" % [float(view.get("hose_power", 1.0)), float(view.get("hose_radius", 0.19)) * 2.0] if int(view.store_id) >= Progression.WET_FIRST_STORE else "Width ×%.2f · Power ×%.2f" % [view.tool_width, view.tool_power]
		_row(0, str(view.tool_name), current_detail, "Using", "", false, Brush)
		_tool_row(1)
		_wet_rows(2)
	elif current_tab == "bonzi":
		var tier: int = view.bonzi_tier
		var detail := "%s / %s earned" % [_amount(view.bonzi_earned), _amount(view.bonzi_target)]
		var cost: float = float(view.bonzi_cost)
		var full_reward: float = float(view.full_reward)
		if tier < 0:
			detail = "%s coins / 120s" % _amount(full_reward)
			if int(view.local_jobs) < 3: detail = "3 rugs to meet Bonzi\n" + detail
		_row(0, "Bonzi" if tier < 0 else "Bonzi · %d/3" % (tier + 1), detail, "Max" if cost < 0 else _amount(cost), "bonzi", bool(view.can_upgrade_bonzi), Buddy, cost >= 0)
		if tier >= 0 and tier < 2:
			_row(1, "Faster cycle", "%s coins / %ds" % [_amount(full_reward), 90 if tier == 0 else 60], "", "", false, Buddy)
	else:
		var owned: Array = view.owned_store_ids
		var section_id := Progression.section_for(int(view.store_id))
		var section: Dictionary = ledger.section_progress(section_id)
		%SheetNote.text = "Section %d · %s\n%d/%d stores mastered" % [section_id, Progression.section_name(section_id), int(section.completed), int(section.total)]
		for index in Progression.STORES_PER_SECTION:
			var id := (section_id - 1) * Progression.STORES_PER_SECTION + index + 1
			var selected := id == int(view.store_id)
			var available := id in owned
			var recipe := "Brush cleaning" if id < Progression.WET_FIRST_STORE else "Water + squeegee"
			var progress := "Mastered" if ledger.store_mastered(id) else ("In progress" if available else "Open the previous store first")
			_row(index, "%d · %s" % [id, Progression.store_name(id)], recipe + " · " + progress, "Here" if selected else ("Visit" if available else "Locked"), "store:%d" % id, available and not selected, Store)
		if bool(view.has_next_store) and int(view.store_id) + 1 not in owned:
			%TravelGoals.show()
			%TravelTitle.text = "Open %s" % str(view.next_store_name)
			%TravelRequirements.text = str(view.get("travel_requirements", "Complete the store upgrades to continue."))
			%TravelRequirements.tooltip_text = str(view.get("travel_requirements", ""))
			%TravelHelp.text = "Fully upgrade every room feature. Paid rugs must use the max-level %s." % ("hose" if int(view.store_id) >= Progression.WET_FIRST_STORE else "brush")
			%TravelHelp.tooltip_text = "Upgrading during a rug counts once you use the upgraded tool. Stationary watering counts too."
			_row(6, "Open next store", "All requirements met" if bool(view.can_travel) else "Complete the checklist above", _amount(view.travel_cost), "travel", bool(view.can_travel), Store, true)
			action_for("intake").tooltip_text = "\n".join(view.get("travel_blockers", []))
		elif owned.size() < Progression.STORE_COUNT:
			# Visiting an older shop must not hide how to reach the next opening.
			var latest_store := int(owned.back())
			var latest_name := Progression.store_name(latest_store)
			%TravelGoals.show()
			%TravelTitle.text = "Open %s" % Progression.store_name(latest_store + 1)
			%TravelRequirements.text = "Visit %s to see its requirements." % latest_name
			%TravelRequirements.tooltip_text = ""
			%TravelHelp.text = "Requirements are tracked per store."
			%TravelHelp.tooltip_text = ""
			_row(6, "Next store requirements", "Visit " + latest_name, "View", "store:%d" % latest_store, true, Store)
			action_for("intake").tooltip_text = "View " + latest_name + " requirements"
		elif not bool(section.complete):
			%TravelGoals.show()
			%TravelTitle.text = "Master %s" % str(view.store_name)
			var mastery_requirements: PackedStringArray = []
			for requirement: String in str(view.get("travel_requirements", "")).split("\n"):
				if not requirement.begins_with("Opening coins:"): mastery_requirements.append(requirement)
			%TravelRequirements.text = "\n".join(mastery_requirements)
			%TravelRequirements.tooltip_text = %TravelRequirements.text
			%TravelHelp.text = "Master every store to complete this section."
			%TravelHelp.tooltip_text = ""
		else:
			%TravelGoals.show()
			%TravelTitle.text = "Section %d complete" % section_id
			%TravelRequirements.text = "All six stores are mastered."
			%TravelRequirements.tooltip_text = ""
			%TravelHelp.text = "The next section is coming later."
			%TravelHelp.tooltip_text = ""
		var future_detail := "Section complete. New mechanics come later." if bool(section.complete) else "Master all six stores. New mechanics come later."
		_row(7, "Section %d" % (section_id + 1), future_detail, "Soon", "", false, Store)
		action_for("next_section").tooltip_text = "This section is not available yet."
	if not pending_item.is_empty(): _refresh_confirmation()
	_layout()
	if pending_item.is_empty() and is_instance_valid(focused) and %Sheet.is_ancestor_of(focused):
		_restore_sheet_focus(focused)

func _tool_row(index: int) -> void:
	var cost: float = float(view.tool_cost)
	var wet := int(view.store_id) >= Progression.WET_FIRST_STORE
	var detail := "Soak %.2f× → %.2f×" % [float(view.get("hose_power", 1.0)), float(view.get("next_hose_power", 1.0))] if wet else "%d/4 · Brush" % view.tool_level
	_row(index, "Water hose · Max" if wet and cost < 0 else ("Complete" if cost < 0 else str(view.next_tool_name)), detail, "Max" if cost < 0 else _amount(cost), "tool", _afford(cost), Brush, cost >= 0)

func _wet_rows(start: int) -> void:
	if not bool(view.get("wet_unlocked", false)): return
	var index := start
	for kind in ["hose", "squeegee"]:
		if kind == "hose" and int(view.store_id) >= Progression.WET_FIRST_STORE: continue
		var cost := float(view.get(kind + "_cost", -1.0))
		var level := int(view.get(kind + "_level", 0))
		var power := float(view.get(kind + "_power", 1.0))
		var next_power := float(view.get("next_" + kind + "_power", power))
		var title := ("Water hose" if kind == "hose" else "Squeegee") + " · Lv %d / 5" % (level + 1)
		var detail := ("Soak" if kind == "hose" else "Extraction") + (" %.2f× → %.2f×" % [power, next_power] if cost >= 0 else " %.2f× · Maximum" % power)
		_row(index, title, detail, "Max" if cost < 0 else _amount(cost), kind, bool(view.get("can_upgrade_" + kind, false)), Brush, cost >= 0)
		index += 1

func _afford(cost: float) -> bool:
	return cost >= 0 and ledger.cash >= cost

func _amount(value: float) -> String:
	if value < 0: return "—"
	return Money.format(value)

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
		"tool": success = ledger.buy_tool_upgrade()
		"hose": success = ledger.buy_hose_upgrade()
		"squeegee": success = ledger.buy_squeegee_upgrade()
		"bonzi": success = ledger.buy_bonzi_upgrade()
		_:
			if action.begins_with("room:"): success = ledger.buy_room_upgrade(action.get_slice(":", 1))
			elif action.begins_with("store:"): success = ledger.select_store(int(action.get_slice(":", 1)))
	if not success and not action.is_empty(): _notice(ledger.last_error if not ledger.last_error.is_empty() else "Not available yet")
	refresh()

func _refresh_confirmation() -> void:
	%BuildTitle.text = "Open next store?"
	%BuildBenefit.text = "Starter tools + Bonzi included"
	%BuildBalance.text = "%s coins · %s left" % [_amount(view.travel_cost), _amount(ledger.cash - float(view.travel_cost))]
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
