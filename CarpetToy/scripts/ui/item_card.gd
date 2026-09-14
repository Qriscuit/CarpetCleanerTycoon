@tool
extends PanelContainer
## Layout, artwork, copy, and state variants belong to the saved card hierarchy.
signal build_requested(item_id: String)
signal clean_requested
signal equip_requested(item_id: String)

@export var item_id: String = "bonzi"
@export var personal_tool := false
@export_enum("As authored", "Locked", "Need cash", "Ready", "Owned", "Equipped") var editor_state: int = 0:
	set(value):
		editor_state = value
		if Engine.is_editor_hint() and is_inside_tree(): _preview()
var ledger: Node
var templates: Dictionary = {}
var state_nodes: Array[Node] = []

func _ready() -> void:
	for node in find_children("*", "", true, false):
		if node.has_meta("show_when"): state_nodes.append(node)
		if node is Label or node is Button:
			templates[node] = node.text
		if node is Button and not Engine.is_editor_hint():
			match str(node.get_meta("action", "")):
				"build": node.pressed.connect(func(): build_requested.emit(item_id))
				"clean": node.pressed.connect(func(): clean_requested.emit())
				"equip": node.pressed.connect(func(): equip_requested.emit(item_id))
	if Engine.is_editor_hint():
		_preview()
		return
	ledger = get_node("/root/ShopState")
	ledger.changed.connect(refresh)
	refresh()

func _preview() -> void:
	if editor_state == 0: return
	var mode: String = ["", "locked", "short", "ready", "owned", "equipped"][editor_state]
	for node in find_children("*", "", true, false):
		if node.has_meta("show_when"):
			var key := str(node.get_meta("show_when"))
			node.visible = key == mode or (key == "owned" and mode == "equipped") or (key == "equip" and mode == "owned" and personal_tool)

func refresh() -> void:
	if ledger == null: return
	var built: bool = ledger.owns(item_id)
	var known: bool = ledger.blueprint_known(item_id)
	var equipped: bool = personal_tool and ledger.equipped_brush == item_id
	var cost: int = ledger.build_cost(item_id)
	var shortfall: int = maxi(cost - ledger.cash, 0)
	var left: int = maxi(ledger.unlock_requirement(item_id) - ledger.manual_jobs, 0)
	var flags := {"owned": built, "locked": not built and not known, "short": not built and known and shortfall > 0, "ready": not built and known and shortfall == 0,
		"equip": built and personal_tool and not equipped, "equipped": built and equipped,
		"needs_bonzi": not built and item_id in ["bonzi_mk2", "intake"] and not ledger.owns("bonzi"),
		"zero_gain": item_id == "intake" and not ledger.owns("bonzi_mk2") and not built}
	for node in state_nodes:
		node.visible = flags.get(str(node.get_meta("show_when")), false)
	var values := {"cost": cost, "shortfall": shortfall, "jobs": ceili(float(shortfall) / 20.0), "rugs_left": left,
		"done": mini(ledger.manual_jobs, ledger.unlock_requirement(item_id)), "gate": ledger.unlock_requirement(item_id), "gain": income_gain()}
	for node in templates:
		if "{" in str(templates[node]): node.text = str(templates[node]).format(values)

func income_gain() -> int:
	if ledger == null or ledger.owns(item_id): return 0
	var demand: float = ledger.demand_per_hour()
	var capacity: float = ledger.capacity_per_hour()
	if item_id == "bonzi": capacity = 30.0
	elif item_id == "bonzi_mk2": capacity = 45.0
	elif item_id == "intake": demand = 60.0
	return roundi((minf(demand, capacity) - ledger.output_per_hour()) * 10.0)
