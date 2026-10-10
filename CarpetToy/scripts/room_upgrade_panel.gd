extends Control
## A small offer tethered to the room object the player selected.
signal purchase_requested(id: String)
signal close_requested

const Money := preload("res://scripts/money.gd")
const ICON_PATH := "res://assets/ui/room_upgrades/"
const ICONS := {
	"floor": preload(ICON_PATH + "floor.svg"),
	"plants": preload(ICON_PATH + "plants.svg"),
	"window": preload(ICON_PATH + "window.svg"),
	"railings": preload(ICON_PATH + "railings.svg"),
	"walls": preload(ICON_PATH + "walls.svg"),
}
const CARD_SIZE := Vector2(272.0, 212.0)
const TITLES := {"floor": "Floor", "plants": "Corner garden", "window": "Window", "railings": "Railings", "walls": "Walls"}
const INK := Color("24464a")
const PAPER := Color("fffdf4")

var selected_id := ""
var offer: Dictionary = {}
var purchases_allowed := false
var anchor_point := Vector2.ZERO
var _has_anchor := false
var _safe := Rect2()
var _fill_tween: Tween
var _last_progress := -1.0

func _ready() -> void:
	%Buy.pressed.connect(_buy)
	%Close.pressed.connect(func(): close_requested.emit())
	%Shade.gui_input.connect(_shade_input)
	%Card.resized.connect(queue_redraw)
	visibility_changed.connect(queue_redraw)

func action_buttons() -> Array[Button]:
	return [%Buy, %Close]

func set_item_anchor(point: Vector2) -> void:
	anchor_point = point
	_has_anchor = true
	if _safe.has_area():
		layout_in(_safe)

func show_offer(view: Dictionary, allowed: bool) -> void:
	selected_id = str(view.get("id", ""))
	_last_progress = -1.0
	%Scroll.scroll_vertical = 0
	refresh_offer(view, allowed)
	show()
	%Close.grab_focus()

func refresh_offer(view: Dictionary, allowed: bool) -> void:
	offer = view.duplicate(true)
	purchases_allowed = allowed
	%Icon.texture = ICONS.get(str(view.get("id", selected_id)), ICONS.floor)
	%Title.text = TITLES.get(str(view.get("id", selected_id)), str(view.get("title", "Workshop")))
	var cost := float(view.get("cost", -1.0))
	%Tier.text = "LEVEL %d · MAX" % int(view.get("level", 0)) if cost < 0 else "LEVEL %d  →  %d" % [int(view.get("level", 0)), int(view.get("next_level", 1))]
	%Icon.tooltip_text = str(view.get("description", ""))
	%CleanValue.text = _money(float(view.get("full_reward", 0.0))) if cost < 0 else "%s → %s" % [_money(float(view.get("full_reward", 0.0))), _money(float(view.get("next_full", 0.0)))]
	var wallet := maxf(0.0, float(view.get("wallet_before", 0.0)))
	var affordable := bool(view.get("can_upgrade", false))
	%Buy.disabled = not allowed or not affordable or cost < 0
	%Buy.text = "Upgrade   ·   %s" % _money(cost) if cost >= 0 else "Fully upgraded"
	%Buy.tooltip_text = "Spend %s coins to upgrade" % _money(cost) if cost >= 0 else "Fully upgraded"
	var visual_step := maxi(1, int(view.get("visual_step", 1)))
	var progress := clampf(float(view.get("milestone_progress", 0.0)), 0.0, 1.0)
	var makeovers_complete := int(view.get("next_visual_level", -1)) < 0
	%ProgressState.text = "Makeovers complete" if makeovers_complete else "%d / %d" % [roundi(progress * float(visual_step)), visual_step]
	%ProgressState.tooltip_text = str(view.get("description", ""))
	_set_progress(progress)
	%Status.text = ""
	if not allowed:
		%Status.text = "Collecting your coins…"
	elif not affordable and cost >= 0 and wallet >= cost:
		%Status.text = "Couldn't save. Reopen the store."
	%Status.visible = not %Status.text.is_empty()
	%Close.focus_next = %Close.get_path_to(%Buy) if not %Buy.disabled else NodePath("")
	%Close.focus_previous = %Close.focus_next
	%Buy.focus_next = %Buy.get_path_to(%Close)
	%Buy.focus_previous = %Buy.focus_next
	if _safe.has_area():
		layout_in(_safe)

func _set_progress(value: float) -> void:
	if is_equal_approx(value, _last_progress):
		return
	if _fill_tween != null and _fill_tween.is_valid():
		_fill_tween.kill()
	# Start a fresh segment after each authored visual transformation.
	if _last_progress < 0.0 or value < _last_progress:
		%TransformationProgress.value = 0.0
	_last_progress = value
	_fill_tween = create_tween()
	_fill_tween.tween_property(%TransformationProgress, "value", value, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func layout_in(safe: Rect2) -> void:
	_safe = safe
	position = Vector2.ZERO
	size = safe.end
	var bounds := safe.grow(-8.0)
	var card := %Card as PanelContainer
	var status_height := 20.0 if %Status.visible else 0.0
	var desired := Vector2(minf(CARD_SIZE.x, bounds.size.x), minf(CARD_SIZE.y + status_height, bounds.size.y))
	%Content.custom_minimum_size.x = maxf(0.0, desired.x - 28.0)
	card.size = desired
	var point := anchor_point if _has_anchor else safe.get_center()
	var gap := 22.0
	var candidates: Array[Vector2] = [
		Vector2(point.x - desired.x * 0.5, point.y - desired.y - gap),
		Vector2(point.x - desired.x * 0.5, point.y + gap),
		Vector2(point.x + gap, point.y - desired.y * 0.5),
		Vector2(point.x - desired.x - gap, point.y - desired.y * 0.5),
	]
	var best := bounds.get_center() - desired * 0.5
	var best_score := INF
	for index in candidates.size():
		var candidate := candidates[index]
		var fitted := Vector2(clampf(candidate.x, bounds.position.x, bounds.end.x - desired.x), clampf(candidate.y, bounds.position.y, bounds.end.y - desired.y))
		var rect := Rect2(fitted, desired)
		# Prefer a close card that leaves the selected point uncovered.
		var score := candidate.distance_to(fitted) + float(index) * 3.0
		if rect.grow(10.0).has_point(point):
			score += 1000.0
		if score < best_score:
			best_score = score
			best = fitted
	card.position = best.round()
	queue_redraw()

func _draw() -> void:
	if not is_node_ready() or not _has_anchor or not visible:
		return
	var rect := (%Card as Control).get_rect()
	if rect.has_point(anchor_point):
		return
	var point := Vector2(clampf(anchor_point.x, _safe.position.x + 4.0, _safe.end.x - 4.0), clampf(anchor_point.y, _safe.position.y + 4.0, _safe.end.y - 4.0))
	var edge := Vector2(clampf(point.x, rect.position.x + 20.0, rect.end.x - 20.0), clampf(point.y, rect.position.y + 20.0, rect.end.y - 20.0))
	var side := Vector2.RIGHT
	if point.y < rect.position.y:
		edge.y = rect.position.y + 1.0
	elif point.y > rect.end.y:
		edge.y = rect.end.y - 2.0
	else:
		edge.x = rect.position.x + 1.0 if point.x < rect.position.x else rect.end.x - 1.0
		side = Vector2.DOWN
	var tip := edge.move_toward(point, minf(24.0, edge.distance_to(point)))
	draw_line(tip, point, INK, 2.0, true)
	draw_circle(point, 5.0, INK)
	draw_circle(point, 3.0, Color("77d8bd"))
	var triangle := PackedVector2Array([edge - side * 10.0, tip, edge + side * 10.0])
	draw_colored_polygon(triangle, PAPER)
	draw_polyline(triangle, INK, 2.0, true)

func _buy() -> void:
	if visible and not %Buy.disabled:
		purchase_requested.emit(selected_id)

func drag_contents(relative: Vector2) -> void:
	%Scroll.scroll_vertical -= roundi(relative.y / maxf(get_global_transform().get_scale().y, 0.01))

func _shade_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		close_requested.emit()

func _money(amount: float) -> String:
	return Money.format(amount)
