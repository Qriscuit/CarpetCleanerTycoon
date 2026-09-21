extends CanvasLayer
## Sparse, phone-safe overlay for the rug-cleaning window.

signal reward_finished
signal coin_arrived(value: int)
signal upgrades_changed(is_open: bool)
signal request_payout_upgrade
signal request_tool_upgrade
signal request_rewarded_ad

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
var _progression: Dictionary = {}
var _purchases_allowed := false
var _ad_available := false
var _ad_amount := 0
var _tool_textures: Dictionary = {}


func _ready() -> void:
	_coin_rng.randomize()
	_create_coin_pool()
	set_process(false)
	(control("PayoutUpgradeButton") as Button).pressed.connect(_on_payout_upgrade_pressed)
	(control("ToolUpgradeButton") as Button).pressed.connect(_on_tool_upgrade_pressed)
	(control("AdRewardButton") as Button).pressed.connect(_on_ad_reward_pressed)
	control("RugValueIcon").texture = _svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48"><g stroke="#4f8875" stroke-width="3" stroke-linecap="round"><path d="M11 5v5m9-5v5m9-5v5m9-5v5M11 38v5m9-5v5m9-5v5m9-5v5"/><rect x="7" y="10" width="34" height="28" rx="7" fill="#bee1c4"/><path d="M15 17h18v14H15z" fill="#f8f3db"/></g><circle cx="34" cy="33" r="10" fill="#ffd468" stroke="#d4a342" stroke-width="2"/><path d="m34 27 2 4 4 1-3 3v4l-3-2-4 2 1-4-3-3 4-1z" fill="#fff8d9"/></svg>')
	set_progression({}, false)
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


func control(node_name: String) -> Control:
	return get_node("%" + node_name) as Control


func action_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for node_name in ["UpgradeButton", "CloseUpgradesButton", "PayoutUpgradeButton", "ToolUpgradeButton", "AdRewardButton"]:
		buttons.append(control(node_name) as Button)
	return buttons


func set_progression(view: Dictionary, purchases_allowed: bool = true) -> void:
	if not view.is_empty() and view == _progression and purchases_allowed == _purchases_allowed:
		return
	_progression = view.duplicate(true)
	_purchases_allowed = purchases_allowed
	if not is_node_ready(): return
	# An unaffordable offer still shows its benefit and price. A negative cost
	# means the progression is complete; can_upgrade_* controls interaction only.
	var payout_available := int(view.get("payout_cost", -1)) >= 0
	var tool_available := int(view.get("tool_cost", -1)) >= 0
	var early := int(view.get("early_reward", 20))
	var full := int(view.get("full_reward", 40))
	(control("EarlyValue") as Label).text = "%s → %s" % [_money_text(early), _money_text(int(view.get("next_early", early)))] if payout_available else _money_text(early)
	(control("FullValue") as Label).text = "%s → %s" % [_money_text(full), _money_text(int(view.get("next_full", full)))] if payout_available else _money_text(full)
	var payout_button := control("PayoutUpgradeButton") as Button
	payout_button.text = "Buy %s" % _money_text(int(view.get("payout_cost", 0))) if payout_available else "Max"
	payout_button.tooltip_text = "Increase rug earnings · %d coins" % int(view.get("payout_cost", 0)) if payout_available else "Maximum rug earnings"
	payout_button.icon = COIN_TEXTURE if payout_available else null
	var store_id := int(view.get("store_id", 1))
	var wet := store_id >= 3
	var tier := clampi(int(view.get("wet_tool_level", 0)) + (4 if store_id == 4 else 0), 0, 8) if wet else clampi(int(view.get("global_tool_tier", 0)), 0, 8)
	var next_tier := mini(tier + 1, 8) if wet else clampi(maxi(tier, (store_id - 1) * 4 + int(view.get("tool_level", 0)) + 1), 0, 8)
	var current_texture := _tool_texture(tier, wet)
	(control("UpgradeButton") as Button).icon = current_texture
	control("CurrentToolPreview").texture = current_texture
	control("NextToolPreview").texture = _tool_texture(next_tier, wet)
	(control("CurrentToolName") as Label).text = str(view.get("tool_name", "Hand brush"))
	(control("NextToolName") as Label).text = str(view.get("next_tool_name", "Wide brush"))
	(control("CurrentToolStats") as Label).text = "✦ %.2f×" % float(view.get("wet_power", 1.0)) if wet else _tool_stats(float(view.get("tool_width", 1.0)), float(view.get("tool_power", 1.0)))
	(control("NextToolStats") as Label).text = "✦ %.2f×" % float(view.get("next_wet_power", view.get("wet_power", 1.0))) if wet else _tool_stats(float(view.get("next_tool_width", view.get("tool_width", 1.0))), float(view.get("next_tool_power", view.get("tool_power", 1.0))))
	(control("ToolDrawerTitle") as Label).text = "Wet tools" if wet else "Brush"
	control("NextToolCard").visible = tool_available
	var tool_button := control("ToolUpgradeButton") as Button
	tool_button.text = "Buy %s" % _money_text(int(view.get("tool_cost", 0))) if tool_available else "Max"
	tool_button.tooltip_text = "%s · %d coins" % [str(view.get("next_tool_name", "Upgrade brush")), int(view.get("tool_cost", 0))] if tool_available else "Maximum tool level"
	tool_button.icon = COIN_TEXTURE if tool_available else null
	_refresh_availability()
	_layout()


func set_ad_offer(amount: int, available: bool) -> void:
	var next_amount := maxi(amount, 0)
	var next_available := available and next_amount > 0
	if next_amount == _ad_amount and next_available == _ad_available: return
	_ad_amount = next_amount
	_ad_available = next_available
	if not is_node_ready(): return
	(control("AdRewardButton") as Button).text = "▶  +%s" % _money_text(_ad_amount)
	control("AdRewardButton").tooltip_text = "Watch an ad for %d coins" % _ad_amount
	control("AdRewardButton").visible = _ad_available
	_refresh_availability()
	_layout()


func _tool_stats(width: float, power: float) -> String:
	return "↔ %.2f×\n✦ %.2f×" % [width, power]


func _money_text(amount: int) -> String:
	var divisor := 1.0
	var suffix := ""
	if amount >= 1_000_000_000_000_000:
		divisor = 1_000_000_000_000_000.0
		suffix = "Q"
	elif amount >= 1_000_000_000_000:
		divisor = 1_000_000_000_000.0
		suffix = "T"
	elif amount >= 1_000_000_000:
		divisor = 1_000_000_000.0
		suffix = "B"
	elif amount >= 1_000_000:
		divisor = 1_000_000.0
		suffix = "M"
	elif amount >= 10_000:
		divisor = 1000.0
		suffix = "K"
	if suffix.is_empty(): return str(amount)
	var number := "%.1f" % (float(amount) / divisor)
	if number.ends_with(".0"): number = number.left(number.length() - 2)
	return number + suffix


func _refresh_availability() -> void:
	if not is_node_ready(): return
	var ready := _purchases_allowed and pending_reward == 0 and not _progression.is_empty()
	var payout_cost := int(_progression.get("payout_cost", -1))
	var tool_cost := int(_progression.get("tool_cost", -1))
	var payout := control("PayoutUpgradeButton") as Button
	var tool := control("ToolUpgradeButton") as Button
	payout.disabled = not ready or upgrades_open() or not bool(_progression.get("can_upgrade_payout", payout_cost >= 0)) or payout_cost < 0 or _actual_balance < payout_cost
	tool.disabled = not ready or not bool(_progression.get("can_upgrade_tool", tool_cost >= 0)) or tool_cost < 0 or _actual_balance < tool_cost
	(control("AdRewardButton") as Button).disabled = not _ad_available or not _purchases_allowed or pending_reward > 0 or upgrades_open()
	var done := control("CloseUpgradesButton")
	var next_focus := done.get_path_to(tool) if not tool.disabled else done.get_path_to(done)
	done.focus_next = next_focus
	done.focus_previous = next_focus
	tool.focus_next = tool.get_path_to(done)
	tool.focus_previous = tool.get_path_to(done)
	if upgrades_open() and tool.disabled and tool.has_focus():
		done.grab_focus()


func _on_payout_upgrade_pressed() -> void:
	if not (control("PayoutUpgradeButton") as Button).disabled:
		request_payout_upgrade.emit()


func _on_tool_upgrade_pressed() -> void:
	if upgrades_open() and not (control("ToolUpgradeButton") as Button).disabled:
		request_tool_upgrade.emit()


func _on_ad_reward_pressed() -> void:
	if _ad_available and not (control("AdRewardButton") as Button).disabled:
		request_rewarded_ad.emit()


func _svg_texture(source: String) -> Texture2D:
	var artwork := Image.new()
	artwork.load_svg_from_string(source, 2.0)
	return ImageTexture.create_from_image(artwork)


func _tool_texture(tier: int, wet: bool) -> Texture2D:
	var key := "%d-%s" % [tier, str(wet)]
	if _tool_textures.has(key): return _tool_textures[key]
	var source: String
	if wet:
		source = '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="104" viewBox="0 0 128 104"><ellipse cx="65" cy="94" rx="47" ry="6" fill="#dbe8dc"/><path d="M21 73 62 20q5-6 10-2t0 10L34 83" fill="#8cd1cd" stroke="#447d75" stroke-width="3"/><rect x="13" y="73" width="63" height="15" rx="6" fill="#fbda9c" stroke="#a78755" stroke-width="3"/><path d="M18 87h54" stroke="#4c7067" stroke-width="6" stroke-linecap="round"/><path d="m79 56 14-21 15 10-10 17 8 18-11 7-9-15-11 1-7-9z" fill="#6fa6d6" stroke="#477697" stroke-width="3"/><path d="M111 23q-14 17-7 22t12-4q1-6-5-18" fill="#a3dfec" stroke="#5ea6bc" stroke-width="2"/></svg>'
		var spray_colors := ["#6fa6d6", "#6fb9cf", "#8298d0", "#b490c6", "#d995a3", "#d5ab6e", "#b49072", "#97836c", "#7c7168"]
		source = source.replace("#6fa6d6", spray_colors[clampi(tier, 0, 8)])
	else:
		# Match the authored 3D progression: mint plastic, carved timber, then
		# jade cloud/lattice work and the gold-inlaid final brush.
		var colors := ["#69b79f", "#69b79f", "#69b79f", "#b69366", "#b69366", "#916d48", "#916d48", "#916d48", "#916d48"]
		var color: String = colors[clampi(tier, 0, 8)]
		var widths := [60, 86, 93, 99, 105, 105, 105, 105, 105]
		var head_width: int = widths[clampi(tier, 0, 8)]
		var head_x := 64 - head_width / 2
		var bristles := ""
		var count := 8 + tier * 2
		var accent := "#ebd4a8" if tier <= 2 else ("#644932" if tier <= 4 else ("#dda747" if tier == 8 else "#70b6a3"))
		var shaft := "#ebd4a8" if tier <= 2 else "#795536"
		for index in count:
			var x := float(head_x + 5) + float(index) * float(head_width - 10) / float(count - 1)
			var bristle_color := ("#f3dcb3" if index % 2 == 0 else "#e7c69e") if tier == 0 else ("#b29160" if tier <= 4 else "#526157")
			bristles += '<path d="M%.1f 77v12" stroke="%s" stroke-width="4" stroke-linecap="round"/>' % [x, bristle_color]
		var carving := '<path d="m79 27-14 21m16-15-9 13M43 68q3-5 9-2 2-9 11-6 4 1 5 5 10-3 12 3h-8" fill="none" stroke="%s" stroke-width="2" stroke-linecap="round"/>' % accent if tier >= 4 else ""
		if tier in [6, 8]:
			carving += '<path d="m30 64 14 9 14-9 14 9 14-9 14 9m-70 0 14-9 14 9 14-9 14 9 14-9" fill="none" stroke="%s" stroke-width="1.8"/>' % accent
		source = '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="104" viewBox="0 0 128 104"><ellipse cx="64" cy="94" rx="47" ry="6" fill="#dbe8dc"/>%s<path d="m53 64 22-42q4-8 11-4t3 11L70 69" fill="%s" stroke="#526f61" stroke-width="3" stroke-linejoin="round"/><path d="m76 24 9 5" stroke="%s" stroke-width="9" stroke-linecap="round"/><rect x="%d" y="59" width="%d" height="20" rx="8" fill="%s" stroke="#526f61" stroke-width="3"/><path d="M%d 75h%d" stroke="%s" stroke-width="4" stroke-linecap="round"/>%s</svg>' % [bristles, shaft, color, head_x, head_width, color, head_x + 6, head_width - 12, accent, carving]
	var texture := _svg_texture(source)
	_tool_textures[key] = texture
	return texture


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
	_refresh_availability()


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
	(control("WalletValue") as Label).text = _money_text(displayed_gold)
	control("Wallet").tooltip_text = "%d coins" % displayed_gold
	_refresh_availability()
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
	# Coins keep travelling while the drawer pauses the rug, so purchase buttons
	# can unlock as soon as the displayed wallet catches up with the ledger.
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
	for node_name in ["HomeButton", "FinishJobButton", "UpgradeButton", "PayoutUpgradeButton", "AdRewardButton"]:
		var button := control(node_name)
		_background_focus_modes[button] = button.focus_mode
		button.focus_mode = Control.FOCUS_NONE
	control("UpgradeSheet").show()
	_refresh_availability()
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
	_refresh_availability()
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
	for node_name in ["CleaningProgress", "HomeButton", "FinishJobButton", "Wallet", "UpgradeButton", "PayoutCard", "PayoutUpgradeButton", "AdRewardButton"]:
		var node := control(node_name)
		if node.is_visible_in_tree() and node.get_global_rect().has_point(point):
			return true
	return false


func visible_button_at(point: Vector2, buttons: Array[Button]) -> Button:
	for button in buttons:
		if upgrades_open() and button not in [control("CloseUpgradesButton"), control("ToolUpgradeButton")]: continue
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
	var upgrade := control("UpgradeButton")
	upgrade.size = Vector2(64.0, 64.0)
	upgrade.position = Vector2(safe.position.x + edge, progress.position.y + progress.size.y + 12.0)
	var payout := control("PayoutCard")
	var buy := control("PayoutUpgradeButton")
	var finish := control("FinishJobButton")
	finish.size = Vector2(maxf(148.0, finish.get_combined_minimum_size().x), 56.0)
	var buy_button := buy as Button
	# expand_icon does not reserve icon width in a Button's minimum size. Keep
	# the coin legible even when a later store has a five- or six-digit price.
	var buy_text_width := buy_button.get_theme_font("font").get_string_size(buy_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, buy_button.get_theme_font_size("font_size")).x
	buy.size = Vector2(maxf(128.0, buy_text_width + (70.0 if buy_button.icon != null else 40.0)), 56.0)
	var landscape := safe.size.x > safe.size.y * 1.35
	if landscape:
		payout.size = Vector2(280.0, 84.0)
		payout.position = Vector2(safe.end.x - payout.size.x - edge, safe.end.y - edge - 152.0)
		buy.position = Vector2(payout.position.x + (payout.size.x - buy.size.x) * 0.5, payout.position.y + 96.0)
		finish.position = Vector2(safe.position.x + edge, safe.end.y - finish.size.y - edge)
	else:
		var total_width := minf(620.0, safe.size.x - edge * 2.0)
		payout.size = Vector2(total_width - buy.size.x - 10.0, 84.0)
		payout.position = Vector2(safe.get_center().x - total_width * 0.5, safe.end.y - payout.size.y - edge)
		buy.position = Vector2(payout.position.x + payout.size.x + 10.0, payout.position.y + (payout.size.y - buy.size.y) * 0.5)
		finish.position = Vector2(safe.get_center().x - finish.size.x * 0.5, payout.position.y - finish.size.y - 12.0)
	for node_name in ["EarlyValue", "FullValue"]:
		var label := control(node_name) as Label
		var current := int(_progression.get("early_reward" if node_name == "EarlyValue" else "full_reward", 20 if node_name == "EarlyValue" else 40))
		var next := int(_progression.get("next_early" if node_name == "EarlyValue" else "next_full", current))
		var offered := int(_progression.get("payout_cost", -1)) >= 0
		var available := maxf(48.0, (payout.size.x - 68.0) * 0.5)
		var font := label.get_theme_font("font")
		var preview := "%s → %s" % [_money_text(current), _money_text(next)] if offered else _money_text(current)
		label.tooltip_text = "%d → %d coins" % [current, next] if offered else "%d coins" % current
		var base_font := 18
		if offered and font.get_string_size(preview, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x > available:
			preview = "%s\n→ %s" % [_money_text(current), _money_text(next)]
			base_font = 16
		label.text = preview
		var width := 1.0
		for line in preview.split("\n"):
			width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, base_font).x)
		label.add_theme_font_size_override("font_size", clampi(floori(float(base_font) * minf(1.0, available / width)), 12, base_font))
	var ad := control("AdRewardButton")
	ad.size = Vector2(maxf(128.0, ad.get_combined_minimum_size().x), 56.0)
	ad.position = Vector2(safe.end.x - ad.size.x - edge, progress.position.y + progress.size.y + 12.0)
	var panel := control("UpgradesPanel")
	panel.size = Vector2(minf(272.0, safe.size.x - edge * 2.0), minf(370.0 if control("NextToolCard").visible else 260.0, safe.size.y - edge * 2.0))
	panel.position = Vector2(safe.position.x + edge, clampf(safe.get_center().y - panel.size.y * 0.5, safe.position.y + edge, safe.end.y - panel.size.y - edge))
	panel.pivot_offset = panel.size * 0.5
