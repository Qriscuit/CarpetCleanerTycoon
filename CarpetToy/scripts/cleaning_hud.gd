extends CanvasLayer
## Sparse, phone-safe overlay for the rug-cleaning window.

signal reward_finished
signal coin_arrived(value: int)
signal upgrades_changed(is_open: bool)

const COIN_POOL_SIZE := 24
const COIN_TEXTURE := preload("res://assets/floating_shop/CoinIcon.png")

@export var preview_safe_insets := Vector4.ZERO
@export_group("Progress colors")
@export var progress_colors: PackedColorArray = [Color("e76c62"), Color("dfb13d"), Color("63b66e"), Color("559bdd")]

var displayed_gold := 0
var _actual_balance := 0
var pending_reward := 0
var _reserved_reward := 0
var _queued_rewards: Array[int] = []
var _coin_nodes: Array[TextureRect] = []
var _coin_flights: Array[Dictionary] = []
var _wallet_tween: Tween
var _modal_tween: Tween
var _reward_running := false
var _coin_rng := RandomNumberGenerator.new()
var _focus_before_modal: Control
var _background_focus_modes: Dictionary = {}


func _ready() -> void:
	_coin_rng.randomize()
	_create_coin_pool()
	set_process(false)
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


func control(node_name: String) -> Control:
	return get_node("%" + node_name) as Control


func initialize_wallet(balance: int) -> void:
	# Re-entering shows the durable balance, even if the previous view closed
	# halfway through a purely cosmetic payout.
	_actual_balance = maxi(balance, 0)
	pending_reward = 0
	_reserved_reward = 0
	_queued_rewards.clear()
	_reward_running = false
	set_process(false)
	for index in _coin_nodes.size():
		_coin_nodes[index].hide()
		_coin_flights[index].clear()
	_refresh_wallet()


func reserve_reward(amount: int) -> void:
	# Call before the ledger emits its balance change so those coins wait for
	# their flight. Ordinary automation income is never held back.
	var value := maxi(amount, 0)
	_reserved_reward += value
	pending_reward += value


func cancel_reserved_reward(amount: int) -> void:
	var value := mini(maxi(amount, 0), _reserved_reward)
	_reserved_reward -= value
	pending_reward -= value
	_refresh_wallet()


func sync_wallet(balance: int) -> void:
	_actual_balance = maxi(balance, 0)
	_refresh_wallet()


func show_reward(amount: int, balance: int) -> void:
	if amount <= 0:
		sync_wallet(balance)
		return
	# Direct callers may omit reservation; the live game reserves before commit.
	if _reserved_reward < amount:
		reserve_reward(amount - _reserved_reward)
	_reserved_reward -= amount
	_actual_balance = maxi(balance, 0)
	_queued_rewards.append(amount)
	_reward_running = true
	set_process(true)
	_refresh_wallet()
	_launch_queued_rewards()


func active_coin_count() -> int:
	var count := 0
	for flight in _coin_flights:
		if not flight.is_empty(): count += 1
	return count


func _refresh_wallet() -> void:
	displayed_gold = maxi(_actual_balance - pending_reward, 0)
	if not is_node_ready(): return
	(control("WalletValue") as Label).text = str(displayed_gold)
	_layout()


func _create_coin_pool() -> void:
	for index in COIN_POOL_SIZE:
		var coin := TextureRect.new()
		coin.name = "RewardCoin%d" % index
		coin.texture = COIN_TEXTURE
		coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		coin.size = Vector2(38, 38)
		coin.pivot_offset = coin.size * 0.5
		coin.hide()
		control("CoinLayer").add_child(coin)
		_coin_nodes.append(coin)
		_coin_flights.append({})


func _launch_queued_rewards() -> void:
	while not _queued_rewards.is_empty():
		var amount := _queued_rewards[0]
		var count := mini(16, maxi(1, ceili(float(amount) / 2.0)))
		var available: Array[int] = []
		for index in _coin_flights.size():
			if _coin_flights[index].is_empty(): available.append(index)
		if available.size() < count: return
		_queued_rewards.pop_front()
		var base_value := floori(float(amount) / float(count))
		var remainder := amount % count
		var phase := _coin_rng.randf_range(0.0, TAU)
		for order in count:
			var angle := phase + TAU * float(order) / float(count)
			var radius := _coin_rng.randf_range(0.085, 0.15)
			var slot := available[order]
			_coin_flights[slot] = {
				"time": -float(order) * 0.024,
				"value": base_value + (1 if order < remainder else 0),
				"offset": Vector2(cos(angle), sin(angle)) * radius,
				"linger": 0.34 + float(order) * 0.013,
				"spin": _coin_rng.randf_range(-0.7, 0.7),
			}


func _process(delta: float) -> void:
	if upgrades_open(): return
	var safe := _safe_rect()
	var origin := safe.position + safe.size * Vector2(0.5, 0.49)
	# Read the target every frame: coins still reach the wallet after rotation,
	# a safe-area change, or a wider balance label from automation income.
	var target := control("WalletIcon").get_global_rect().get_center()
	for index in _coin_flights.size():
		var flight := _coin_flights[index]
		if flight.is_empty(): continue
		flight.time += delta
		var elapsed: float = flight.time
		if elapsed < 0.0: continue
		var coin := _coin_nodes[index]
		coin.show()
		var burst_end: Vector2 = origin + flight.offset * minf(safe.size.x, safe.size.y)
		var linger: float = flight.linger
		var point: Vector2
		var coin_scale := 1.0
		if elapsed < 0.30:
			var fraction := elapsed / 0.30
			var eased := 1.0 - pow(1.0 - fraction, 3.0)
			point = origin.lerp(burst_end, eased) + Vector2(0, -sin(fraction * PI) * 18.0)
			coin_scale = lerpf(0.2, 1.0, eased)
		elif elapsed < 0.30 + linger:
			point = burst_end + Vector2(0, sin((elapsed - 0.30) * 8.0) * 3.0)
		else:
			var fraction := clampf((elapsed - 0.30 - linger) / 0.46, 0.0, 1.0)
			var eased := fraction * fraction
			var bend := burst_end.lerp(target, 0.46) + Vector2(-36.0, -62.0)
			point = burst_end.lerp(bend, eased).lerp(bend.lerp(target, eased), eased)
			coin_scale = lerpf(1.0, 0.52, eased)
			if fraction >= 1.0:
				_arrive_coin(index)
				continue
		coin.position = control("CoinLayer").get_global_transform().affine_inverse() * point - coin.size * 0.5
		coin.scale = Vector2.ONE * coin_scale
		coin.rotation = float(flight.spin) * (1.0 - minf(elapsed, 1.0))
	_launch_queued_rewards()
	if _queued_rewards.is_empty() and active_coin_count() == 0:
		set_process(false)
		if _reward_running and _reserved_reward == 0:
			_reward_running = false
			reward_finished.emit()


func _arrive_coin(index: int) -> void:
	var value: int = _coin_flights[index].value
	_coin_nodes[index].hide()
	_coin_flights[index].clear()
	pending_reward = maxi(pending_reward - value, 0)
	_refresh_wallet()
	var wallet := control("Wallet")
	if _wallet_tween != null and _wallet_tween.is_valid(): _wallet_tween.kill()
	wallet.scale = Vector2.ONE * 1.10
	_wallet_tween = create_tween()
	_wallet_tween.tween_property(wallet, "scale", Vector2.ONE, 0.19).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	coin_arrived.emit(value)


func open_upgrades() -> void:
	if upgrades_open(): return
	_focus_before_modal = get_viewport().gui_get_focus_owner()
	_background_focus_modes.clear()
	for node_name in ["HomeButton", "FinishJobButton", "UpgradeButton"]:
		var button := control(node_name)
		_background_focus_modes[button] = button.focus_mode
		button.focus_mode = Control.FOCUS_NONE
	control("UpgradeSheet").show()
	_layout()
	var panel := control("UpgradesPanel")
	panel.scale = Vector2.ONE * 0.94
	panel.modulate.a = 0.0
	if _modal_tween != null and _modal_tween.is_valid(): _modal_tween.kill()
	_modal_tween = create_tween().set_parallel(true)
	_modal_tween.tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_modal_tween.tween_property(panel, "modulate:a", 1.0, 0.12)
	control("CloseUpgradesButton").grab_focus()
	upgrades_changed.emit(true)


func close_upgrades() -> void:
	if not upgrades_open(): return
	if _modal_tween != null and _modal_tween.is_valid(): _modal_tween.kill()
	control("UpgradeSheet").hide()
	for button in _background_focus_modes:
		if is_instance_valid(button): button.focus_mode = _background_focus_modes[button]
	_background_focus_modes.clear()
	if is_instance_valid(_focus_before_modal) and _focus_before_modal.is_visible_in_tree() and _focus_before_modal.focus_mode != Control.FOCUS_NONE:
		_focus_before_modal.grab_focus()
	else:
		control("UpgradeButton").grab_focus()
	_focus_before_modal = null
	upgrades_changed.emit(false)


func upgrades_open() -> bool:
	return is_node_ready() and control("UpgradeSheet").visible


func blocks_point(point: Vector2) -> bool:
	# The full-screen root ignores input. Only the visible controls keep a press
	# from starting a brush stroke beneath them.
	if upgrades_open(): return true
	for node_name in ["CleaningProgress", "HomeButton", "FinishJobButton", "Wallet", "UpgradeButton"]:
		var node := control(node_name)
		if node.is_visible_in_tree() and node.get_global_rect().has_point(point):
			return true
	return false


func visible_button_at(point: Vector2, buttons: Array[Button]) -> Button:
	for button in buttons:
		if upgrades_open() and button != control("CloseUpgradesButton"): continue
		if button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(point):
			return button
	return null


func _safe_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2()
	var viewport_size := viewport.get_visible_rect().size
	var inset := preview_safe_insets
	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var window_size := Vector2(DisplayServer.window_get_size())
		if safe.size.x > 0 and safe.size.y > 0 and window_size.x > 0 and window_size.y > 0:
			var ratio := viewport_size / window_size
			var origin := Vector2(safe.position - DisplayServer.window_get_position()) * ratio
			var end := origin + Vector2(safe.size) * ratio
			inset = Vector4(maxf(origin.x, 0.0), maxf(origin.y, 0.0), maxf(viewport_size.x - end.x, 0.0), maxf(viewport_size.y - end.y, 0.0))
	return Rect2(Vector2(inset.x, inset.y), Vector2(maxf(viewport_size.x - inset.x - inset.z, 1.0), maxf(viewport_size.y - inset.y - inset.w, 1.0)))


func _layout() -> void:
	if not is_node_ready() or get_viewport() == null:
		return
	# The world keeps its 720x1000 reference canvas. Scale this overlay alone
	# so a 56-unit button remains at least 44 screen pixels in phone landscape.
	var viewport_size := get_viewport().get_visible_rect().size
	var window_size := Vector2(DisplayServer.window_get_size())
	var pixels_per_unit := minf(window_size.x / maxf(viewport_size.x, 1.0), window_size.y / maxf(viewport_size.y, 1.0))
	var ui_scale := clampf(44.0 / (56.0 * maxf(pixels_per_unit, 0.01)), 1.0, 2.5)
	(get_node("HUD") as Control).scale = Vector2.ONE * ui_scale
	var raw_safe := _safe_rect()
	var safe := Rect2(raw_safe.position / ui_scale, raw_safe.size / ui_scale)
	var edge := 16.0
	var home := control("HomeButton")
	home.position = safe.position + Vector2(edge, edge)
	home.size = Vector2(56.0, 56.0)
	var progress := control("CleaningProgress")
	var progress_width := minf(340.0, maxf(160.0, safe.size.x - edge * 2.0))
	progress.position = Vector2(safe.get_center().x - progress_width * 0.5, safe.position.y + edge)
	progress.size = Vector2(progress_width, 56.0)
	var wallet := control("Wallet")
	var wallet_value := control("WalletValue") as Label
	var max_wallet_width := maxf(112.0, safe.size.x - home.size.x - edge * 3.0 - 12.0)
	var number_width := wallet_value.get_theme_font("font").get_string_size(wallet_value.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 23).x
	var font_size := clampi(floori(23.0 * minf(1.0, (max_wallet_width - 68.0) / maxf(number_width, 1.0))), 12, 23)
	if wallet_value.get_theme_font_size("font_size") != font_size:
		wallet_value.add_theme_font_size_override("font_size", font_size)
	wallet.size = Vector2(maxf(112.0, wallet.get_combined_minimum_size().x), 56.0)
	wallet.position = Vector2(safe.end.x - wallet.size.x - edge, safe.position.y + edge)
	wallet.pivot_offset = wallet.size * 0.5
	if Rect2(wallet.position, wallet.size).intersects(Rect2(progress.position, progress.size).grow(12.0)) or Rect2(home.position, home.size).intersects(Rect2(progress.position, progress.size).grow(12.0)):
		progress.position.y += 68.0
	var finish := control("FinishJobButton")
	finish.size = Vector2(148.0, 56.0)
	finish.position = Vector2(safe.get_center().x - finish.size.x * 0.5, safe.end.y - finish.size.y - 20.0)
	var upgrade := control("UpgradeButton")
	upgrade.size = Vector2(116.0, 56.0)
	upgrade.position = Vector2(safe.end.x - upgrade.size.x - edge, safe.end.y - upgrade.size.y - 20.0)
	if Rect2(upgrade.position, upgrade.size).intersects(Rect2(finish.position, finish.size).grow(12.0)):
		finish.position.x = safe.position.x + edge
	var panel := control("UpgradesPanel")
	panel.size = Vector2(minf(360.0, safe.size.x - edge * 2.0), maxf(280.0, panel.get_combined_minimum_size().y))
	panel.position = safe.get_center() - panel.size * 0.5
	panel.pivot_offset = panel.size * 0.5
