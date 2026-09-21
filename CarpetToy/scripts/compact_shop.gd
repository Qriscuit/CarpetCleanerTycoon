extends Control
## Concise native sheets, backed by the existing transactional shop ledger.
signal closed
const Pop = preload("res://scripts/ui/button_pop.gd")
const NAMES := {"hand_brush":"Hand Brush", "wide_brush":"Wide Brush", "bonzi":"Bonzi", "bonzi_mk2":"Bonzi Mk II", "intake":"Welcome Sign"}
const PAGES := {"shop":["bonzi","wide_brush","bonzi_mk2","intake"], "items":["hand_brush","wide_brush"], "plans":["bonzi","wide_brush","bonzi_mk2","intake"], "bonzi":["bonzi","bonzi_mk2","intake"]}
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

func _ready() -> void:
	ledger = get_node("/root/ShopState")
	for row in %Rows.get_children():
		var id := str(row.get_meta("item_id"))
		rows[id] = row
		action_for(id).pressed.connect(_item_action.bind(id))
	for b in find_children("*","Button",true,false): Pop.bind(b)
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
	_layout()

func action_for(id: String) -> Button:
	return rows[id].get_node("Row/Action")

func _layout() -> void:
	var desired_height: float = 112 + PAGES[current_tab].size()*82 + (94 if %Routine.visible else 0) + (32 if %SheetNote.visible else 0)
	var sheet_size := Vector2(minf(430,size.x-24), minf(desired_height,size.y-24))
	%Sheet.position = (size-sheet_size)*.5
	%Sheet.size = sheet_size
	%ConfirmPanel.size = Vector2(minf(336,size.x-36),280)
	%ConfirmPanel.position = (size-%ConfirmPanel.size)*.5

func show_tab(tab: String) -> void:
	if not PAGES.has(tab): return
	%CloseSheet.grab_focus()
	current_tab = tab
	%SheetTitle.text = {"shop":"Shop", "items":"Tools", "plans":"Blueprints", "bonzi":"Bonzi"}[tab]
	%SheetNote.text = ""
	%SheetNote.hide()
	%MenuScroll.scroll_vertical = 0
	cancel_build()
	refresh()

func refresh() -> void:
	%SheetCash.text = str(ledger.cash) if ledger.cash < 10000 else "%.1fK" % (float(ledger.cash)/1000.0)
	%SheetCash.tooltip_text = "%d coins" % ledger.cash
	for id: String in rows:
		var row: Control = rows[id]
		row.visible = id in PAGES[current_tab]
		if not row.visible: continue
		var status: Label = row.get_node("Row/Words/Status")
		var action := action_for(id)
		var owned: bool = ledger.owns(id)
		var known: bool = ledger.blueprint_known(id)
		var cost: int = ledger.build_cost(id)
		action.disabled = false
		action.icon = null
		if current_tab == "plans":
			status.text = "Blueprint found" if known else _unlock_text(id)
			action.text = "Built" if owned else ("Shop" if known else "Locked")
			action.disabled = owned or not known
		elif owned:
			var tool: bool = id in ["hand_brush","wide_brush"]
			var equipped: bool = tool and ledger.equipped_brush == id
			status.text = "Ready to clean" if tool else "Installed"
			action.text = "Using" if equipped else ("Equip" if tool else "Built")
			action.disabled = not tool or equipped
		else:
			status.text = _unlock_text(id) if not known else ("Ready to build" if ledger.cash >= cost else "%d more coins" % (cost-ledger.cash))
			action.text = str(cost)
			action.icon = preload("res://assets/floating_shop/CoinIcon.png")
			action.disabled = not known or ledger.cash < cost
	%Routine.visible = current_tab == "bonzi" and ledger.owns("bonzi")
	%RoutineRate.text = "%d coins every %ds" % [ledger.ROUTINE_REWARD, roundi(3600.0 / maxf(ledger.output_per_hour(), 1.0))]
	if not pending_item.is_empty(): _refresh_confirmation()
	_layout()

func _unlock_text(id: String) -> String:
	if id in ["bonzi_mk2","intake"] and not ledger.owns("bonzi"): return "Build Bonzi first"
	return "%d / %d rugs" % [mini(ledger.manual_jobs,ledger.unlock_requirement(id)),ledger.unlock_requirement(id)]

func _process(_delta: float) -> void:
	if not is_visible_in_tree() or not %Routine.visible: return
	var seconds := ceili(ledger.seconds_to_delivery())
	%RoutineTime.text = "Next +%d in %d:%02d" % [ledger.ROUTINE_REWARD, seconds/60,seconds%60]
	%RoutineProgress.value = ledger.routine_remainder*100

func _item_action(id: String) -> void:
	if current_tab == "plans":
		show_tab("shop")
		%MenuScroll.ensure_control_visible(rows[id])
	elif ledger.owns(id):
		if id in ["hand_brush","wide_brush"]:
			if ledger.equip_brush(id): _notice("%s equipped" % NAMES[id])
			else: _notice(ledger.last_error)
	else: request_build(id)

func request_build(id: String) -> void:
	if not NAMES.has(id) or ledger.owns(id) or not ledger.blueprint_known(id) or ledger.cash < ledger.build_cost(id): return
	pending_item = id
	_refresh_confirmation()
	%PurchaseReview.show()
	%ConfirmBuild.grab_focus()

func _benefit(id: String) -> String:
	if id == "wide_brush": return "44% wider cleaning"
	var capacity: float = ledger.capacity_per_hour()
	var demand: float = ledger.demand_per_hour()
	if id == "bonzi": capacity = 30
	elif id == "bonzi_mk2": capacity = 45
	elif id == "intake": demand = 60
	var rate := minf(capacity,demand)
	return "%d coins every %ds" % [ledger.ROUTINE_REWARD, roundi(3600.0/rate)] if rate > ledger.output_per_hour() else "No extra income until Mk II"

func _refresh_confirmation() -> void:
	%BuildTitle.text = "Build %s?" % NAMES[pending_item]
	%BuildBenefit.text = _benefit(pending_item)
	var cost: int = ledger.build_cost(pending_item)
	%BuildBalance.text = "%d coins  ·  %d left" % [cost, ledger.cash-cost]
	%ConfirmBuild.text = "Build · %d" % cost
	%ConfirmBuild.disabled = ledger.owns(pending_item) or not ledger.blueprint_known(pending_item) or ledger.cash < cost

func confirm_build() -> void:
	if pending_item.is_empty(): return
	var id := pending_item
	cancel_build()
	if ledger.build(id): _notice("%s built" % NAMES[id])
	else: _notice(ledger.last_error if not ledger.last_error.is_empty() else "Could not build yet")
	refresh()

func cancel_build() -> void:
	var id := pending_item
	pending_item = ""
	%PurchaseReview.hide()
	if rows.has(id) and rows[id].is_visible_in_tree(): action_for(id).grab_focus()

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
	if %PurchaseReview.visible:
		candidates.append(%CancelBuild)
		candidates.append(%ConfirmBuild)
	else: candidates.append(%CloseSheet)
	if not %PurchaseReview.visible:
		for id: String in rows:
			if rows[id].is_visible_in_tree() and %MenuScroll.get_global_rect().has_point(point): candidates.append(action_for(id))
		if not %Sheet.get_global_rect().has_point(point): candidates.append(%Backdrop)
	for b in candidates:
		if b.is_visible_in_tree() and not b.disabled and b.get_global_rect().has_point(point): return b
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
			var activate: bool = not event.canceled and not dragged and touch_start.distance_to(event.position)<12 and _button_at(event.position)==target
			reset_touch()
			if activate and is_instance_valid(target):
				Pop.release(target)
				target.pressed.emit()
	elif event is InputEventScreenDrag and event.index == touch_id:
		if touch_start.distance_to(event.position)>=12:
			dragged = true
			if is_instance_valid(touch_button): Pop.reset(touch_button)
		if dragged and scrolling: %MenuScroll.scroll_vertical = scroll_start-roundi(event.position.y-touch_start.y)

func reset_touch() -> void:
	if is_instance_valid(touch_button): Pop.reset(touch_button)
	touch_id = -1
	touch_button = null
	dragged = false
