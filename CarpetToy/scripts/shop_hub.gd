@tool
extends Control
## Scenes own presentation. This controller binds data and routes user intent only.
@export_enum("Shop", "Items", "Blueprints", "Bonzi", "Future shop") var editor_page := 0:
	set(value):
		editor_page = value
		if Engine.is_editor_hint() and is_inside_tree(): _show_editor_page()
const PAGE_KEYS := ["shop", "items", "plans", "bonzi", "expansion"]
var state: Node
var current_tab := "shop"
var page: VBoxContainer
var scroll: ScrollContainer
var shell: MarginContainer
var tabs: Dictionary = {}
var buttons: Array[Button] = []
var cards: Array[Node] = []
var templates: Dictionary = {}
var dirty_ui := false
var pending_item := ""
var touch_id := -1
var touch_start := Vector2.ZERO
var touch_candidate: Button
var touch_scroll: ScrollContainer
var scroll_start := 0
var gesture_dragged := false
var gesture_blocked := false
var goal_stage := "DiscoverGoal"
var cash_label: Label

func _ready() -> void:
	if Engine.is_editor_hint():
		_show_editor_page()
		set_process(false)
		return
	state = get_node("/root/ShopState")
	state.contract_mode = false
	shell = %Shell
	cash_label = %Wallet
	for node in find_children("*", "", true, false):
		if node is Button: buttons.append(node)
		if node.has_signal("build_requested"):
			cards.append(node)
			node.build_requested.connect(request_build)
			node.clean_requested.connect(enter_cleaning)
			node.equip_requested.connect(equip_brush)
		if (node is Label or node is Button) and not _inside_card(node):
			templates[node] = node.text
	for b in buttons:
		if _inside_card(b): continue
		var action := str(b.get_meta("action", ""))
		if not action.is_empty(): b.pressed.connect(_act.bind(action))
	for key in ["shop", "items", "plans", "bonzi"]:
		tabs[key] = get_node("%Tab_" + key)
	state.changed.connect(func(): dirty_ui = true)
	%NoticeTimer.timeout.connect(func(): %Notice.hide())
	show_tab("shop")
	refresh_state()
	if not state.last_error.is_empty(): toast(state.last_error)

func _inside_card(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null and parent != self:
		if parent.has_signal("build_requested"): return true
		parent = parent.get_parent()
	return false

func _show_editor_page() -> void:
	var pages := get_node_or_null("%Pages") as TabContainer
	if pages != null: pages.current_tab = editor_page

func _act(action: String) -> void:
	if action.begins_with("tab:"):
		show_tab(action.trim_prefix("tab:"))
		return
	match action:
		"clean": enter_cleaning()
		"gym": enter_gym()
		"expansion": show_expansion()
		"shop": show_tab("shop")
		"goal": follow_goal()
		"acknowledge": acknowledge_return()
		"confirm": confirm_build()
		"cancel": cancel_build()

func show_tab(tab: String) -> void:
	if not PAGE_KEYS.has(tab): return
	current_tab = tab
	%Pages.current_tab = PAGE_KEYS.find(tab)
	scroll = %Pages.get_child(%Pages.current_tab)
	page = scroll.get_child(0)
	%CleanDock.visible = tab != "expansion"
	for key in tabs:
		tabs[key].set_pressed_no_signal(key == tab or (key == "shop" and tab == "expansion"))
	# ScrollContainers and controls stay alive; their authored layout and scroll survive.

func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	if dirty_ui:
		dirty_ui = false
		refresh_state()
	if state.owns("bonzi"):
		var seconds := ceili(state.seconds_to_delivery())
		_format(%DeliveryTime, {"time": "%d:%02d" % [seconds / 60, seconds % 60]})
		%DeliveryProgress.value = state.routine_remainder * 100.0

func _format(node: Node, values: Dictionary) -> void:
	if templates.has(node):
		node.text = str(templates[node]).format(values)

func refresh_state() -> void:
	var values := {
		"cash": state.cash, "manual_jobs": state.manual_jobs, "automated_jobs": state.automated_jobs,
		"income": roundi(state.output_per_hour() * 10), "orders": roundi(state.output_per_hour()),
		"demand": roundi(state.demand_per_hour()), "capacity": roundi(state.capacity_per_hour()),
		"bottleneck": state.bottleneck(), "return_reward": state.return_reward,
		"bonzi_rugs_left": maxi(3 - state.manual_jobs, 0), "bonzi_shortfall": maxi(100 - state.cash, 0),
		"bonzi_jobs_left": ceili(float(maxi(100 - state.cash, 0)) / 20.0),
		"wide_rugs_left": maxi(8 - state.manual_jobs, 0)}
	for node in templates:
		if node in [%PurchaseTitle, %PurchaseBenefit, %PurchaseTotalsText, %ConfirmBuildButton, %DeliveryTime]: continue
		if "{" in str(templates[node]): _format(node, values)
	%ReturnCard.visible = state.return_reward > 0
	%BonziWorking.visible = state.owns("bonzi")
	%BonziNotBuilt.visible = not state.owns("bonzi")
	%CapacityCard.visible = state.owns("bonzi")
	%BonziArt.working = state.owns("bonzi")
	%Storefront.working = state.owns("bonzi")
	%ResumeHint.visible = not state.active_job_id.is_empty()
	%ResumeRugButton.visible = not state.active_job_id.is_empty()
	%CleanRugButton.visible = state.active_job_id.is_empty()
	refresh_goal()
	if not pending_item.is_empty(): _refresh_purchase()

func refresh_goal() -> void:
	var fraction := 0.0
	if not state.owns("bonzi"):
		if not state.blueprint_known("bonzi"):
			goal_stage = "DiscoverGoal"
			fraction = float(state.manual_jobs) / 3.0
		elif state.cash < state.build_cost("bonzi"):
			goal_stage = "SaveGoal"
			fraction = float(state.cash) / 100.0
		else:
			goal_stage = "BuildGoal"
			fraction = 1.0
	elif state.manual_jobs < 8:
		goal_stage = "WideGoal"
		fraction = float(state.manual_jobs) / 8.0
	elif not (state.owns("wide_brush") and state.owns("bonzi_mk2") and state.owns("intake")):
		goal_stage = "UpgradeGoal"
		fraction = minf(float(state.manual_jobs) / 10.0, 1.0)
	else:
		goal_stage = "SettledGoal"
		fraction = 1.0
	for name in ["DiscoverGoal", "SaveGoal", "BuildGoal", "WideGoal", "UpgradeGoal", "SettledGoal"]:
		get_node("%" + name).visible = name == goal_stage
	%GoalProgress.value = fraction * 100.0
	%GoalProgress.visible = goal_stage != "SettledGoal"

func follow_goal() -> void:
	if goal_stage == "BuildGoal": request_build("bonzi")
	elif goal_stage in ["DiscoverGoal", "SaveGoal"]: show_tab("bonzi")
	elif goal_stage in ["WideGoal", "SettledGoal"]: show_tab("items")
	else: show_tab("plans")

func request_build(id: String) -> void:
	if not state.blueprint_known(id) or state.owns(id) or state.cash < state.build_cost(id): return
	pending_item = id
	%PurchaseSheet.show()
	%Notice.hide()
	_refresh_purchase()
	%ConfirmBuildButton.grab_focus()

func buy(id: String) -> void:
	request_build(id)

func _refresh_purchase() -> void:
	if state.owns(pending_item):
		cancel_build()
		return
	var title := pending_item.capitalize()
	var benefit := ""
	for item in cards:
		if item.item_id == pending_item:
			title = item.find_child("ItemTitle", true, false).text
			benefit = item.find_child("Benefit", true, false).text
			break
	var values := {"item": title, "benefit": benefit, "cost": state.build_cost(pending_item),
		"remaining": state.cash - state.build_cost(pending_item)}
	for node in [%PurchaseTitle, %PurchaseBenefit, %PurchaseTotalsText, %ConfirmBuildButton]:
		_format(node, values)
	%ConfirmBuildButton.disabled = not state.blueprint_known(pending_item) or state.cash < state.build_cost(pending_item)

func confirm_build() -> void:
	if pending_item.is_empty(): return
	var id := pending_item
	# Close the review first so a repeated release cannot purchase twice.
	cancel_build()
	if state.build(id):
		%BuiltNotice.show()
		%ErrorNotice.hide()
		%EquipNotice.hide()
		show_notice()
	else:
		toast(state.last_error if not state.last_error.is_empty() else %PurchaseErrorCopy.text)
	refresh_state()

func cancel_build() -> void:
	pending_item = ""
	%PurchaseSheet.hide()
	if tabs.has(current_tab): tabs[current_tab].grab_focus()

func equip_brush(id: String) -> void:
	if state.equip_brush(id):
		%EquipNotice.show()
		%BuiltNotice.hide()
		%ErrorNotice.hide()
		show_notice()
	else: toast(state.last_error)

func show_notice() -> void:
	%Notice.show()
	%NoticeTimer.start()

func toast(message: String) -> void:
	%ToastLabel.text = message
	%ErrorNotice.show()
	%BuiltNotice.hide()
	%EquipNotice.hide()
	show_notice()

func enter_cleaning() -> void:
	if state.start_job().is_empty():
		toast(state.last_error)
		return
	state.contract_mode = true
	get_tree().change_scene_to_file("res://scenes/rug_cleaning_gym.tscn")

func enter_gym() -> void:
	state.contract_mode = false
	get_tree().change_scene_to_file("res://scenes/rug_cleaning_gym.tscn")

func show_expansion() -> void:
	show_tab("expansion")

func acknowledge_return() -> void:
	if not state.acknowledge_return(): toast(state.last_error)
	refresh_state()

func _notification(what: int) -> void:
	if Engine.is_editor_hint(): return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset_touch()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_back()
		get_viewport().set_input_as_handled()

func _back() -> void:
	if %PurchaseSheet.visible: cancel_build()
	elif current_tab != "shop": show_tab("shop")

func _reset_touch() -> void:
	touch_id = -1
	touch_candidate = null
	touch_scroll = null
	gesture_dragged = false
	gesture_blocked = false

func button_at(point: Vector2) -> Button:
	for b in buttons:
		if not is_instance_valid(b) or not b.is_visible_in_tree() or b.disabled: continue
		if %PurchaseSheet.visible and not %PurchaseSheet.is_ancestor_of(b): continue
		if not b.get_global_rect().has_point(point): continue
		var clipped := false
		var ancestor := b.get_parent()
		while ancestor != null and ancestor != self:
			if ancestor is Control and ancestor.clip_contents and not ancestor.get_global_rect().has_point(point):
				clipped = true
				break
			ancestor = ancestor.get_parent()
		if not clipped: return b
	return null

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			if touch_id != -1:
				gesture_blocked = true
				touch_candidate = null
				get_viewport().set_input_as_handled()
				return
			touch_id = event.index
			touch_start = event.position
			touch_candidate = button_at(event.position)
			touch_scroll = scroll if not %PurchaseSheet.visible and scroll.get_global_rect().has_point(event.position) else null
			scroll_start = touch_scroll.scroll_vertical if touch_scroll != null else 0
			gesture_dragged = false
			gesture_blocked = false
			get_viewport().set_input_as_handled()
		elif event.index == touch_id:
			var candidate := touch_candidate
			var activate: bool = not event.canceled and not gesture_dragged and not gesture_blocked and touch_start.distance_to(event.position) < 14.0
			_reset_touch()
			if activate and is_instance_valid(candidate) and button_at(event.position) == candidate:
				candidate.pressed.emit()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == touch_id:
		if touch_start.distance_to(event.position) >= 14.0:
			gesture_dragged = true
			touch_candidate = null
		if gesture_dragged and not gesture_blocked and touch_scroll != null:
			touch_scroll.scroll_vertical = scroll_start - roundi(event.position.y - touch_start.y)
		get_viewport().set_input_as_handled()
