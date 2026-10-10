extends CanvasLayer
## Sparse, phone-safe overlay for the rug-cleaning window.

signal reward_finished
signal coin_arrived(value: float)
signal upgrades_changed(is_open: bool)
signal request_room_upgrade(id: String)
signal request_tool_upgrade
signal request_hose_upgrade
signal request_squeegee_upgrade
signal request_bonzi_upgrade
signal request_rewarded_ad
signal composition_changed

const COIN_POOL_SIZE := 24
const CLEANING_COUNT_SECONDS := 0.24
const COIN_TEXTURE := preload("res://assets/floating_shop/CoinIcon.png")
const Money := preload("res://scripts/money.gd")
const Progression := preload("res://scripts/progression.gd")
const AD_VIDEO_PLAY := preload("res://assets/ui/room_upgrades/video_play.svg")
const AD_VIDEO_LOCKED := preload("res://assets/ui/room_upgrades/video_locked.svg")
const AD_VIDEO_ACTIVE := preload("res://assets/ui/room_upgrades/video_active.svg")
enum CarpetAdState { HIDDEN, LOCKED, READY, REQUESTING, ACTIVE }

@export var preview_safe_insets := Vector4.ZERO
@export_group("Responsive layout")
@export_range(360.0, 440.0, 10.0) var phone_portrait_width := 390.0
@export_range(340.0, 400.0, 10.0) var phone_landscape_height := 360.0
@export_range(560.0, 800.0, 20.0) var tablet_short_side := 640.0
@export_range(8.0, 32.0, 1.0) var layout_edge := 16.0
@export_range(8.0, 24.0, 1.0) var layout_gap := 12.0
@export_range(4.0, 12.0, 1.0) var earnings_gap := 6.0
@export_range(240.0, 320.0, 1.0) var landscape_rail_width := 280.0
@export_range(240.0, 400.0, 1.0) var progress_max_width := 340.0
@export_range(40.0, 56.0, 1.0) var progress_height := 44.0
@export_range(40.0, 56.0, 1.0) var earnings_height := 48.0
@export_range(56.0, 72.0, 1.0) var action_height := 56.0
@export_range(60.0, 84.0, 1.0) var wallet_height := 68.0
@export_range(8.0, 32.0, 1.0) var world_gutter := 16.0
@export_range(1.15, 1.6, 0.05) var landscape_aspect_threshold := 1.35
@export_group("Progress colors")
@export var progress_colors: PackedColorArray = [Color("e76c62"), Color("dfb13d"), Color("63b66e"), Color("559bdd")]

var displayed_gold := 0.0
var _actual_balance := 0.0
var pending_reward := 0.0
var _reserved_reward := 0.0
var _queued_rewards: Array[float] = []
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
var _carpet_ad_state := CarpetAdState.HIDDEN
var _tool_textures: Dictionary = {}
var _room_anchor_screen := Vector2.ZERO
var _layout_info: Dictionary = {}
var _shop_stacked := false
var _cleaning_pending := 0.0
var _cleaning_count_start := 0.0
var _cleaning_count_time := 0.0
var _wallet_paused := false
@onready var room_panel: Control = $HUD/RoomUpgradePanel


func _ready() -> void:
	_coin_rng.randomize()
	_create_coin_pool()
	set_process(false)
	room_panel.purchase_requested.connect(func(id: String): request_room_upgrade.emit(id))
	room_panel.close_requested.connect(close_upgrades)
	(control("ToolUpgradeButton") as Button).pressed.connect(_on_tool_upgrade_pressed)
	(control("HoseUpgradeButton") as Button).pressed.connect(_on_wet_upgrade_pressed.bind("hose"))
	(control("SqueegeeUpgradeButton") as Button).pressed.connect(_on_wet_upgrade_pressed.bind("squeegee"))
	(control("BonziUpgradeButton") as Button).pressed.connect(_on_bonzi_upgrade_pressed)
	(control("AdRewardButton") as Button).pressed.connect(_on_ad_reward_pressed)
	set_progression({}, false)
	_refresh_carpet_ad()
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


func control(node_name: String) -> Control:
	return get_node("%" + node_name) as Control


func action_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for node_name in ["UpgradeButton", "CloseUpgradesButton", "ToolUpgradeButton", "HoseUpgradeButton", "SqueegeeUpgradeButton", "BonziUpgradeButton", "AdRewardButton"]:
		buttons.append(control(node_name) as Button)
	buttons.append_array(room_panel.action_buttons())
	return buttons


func set_wet_stage(round_number: int, round_count: int, ready: bool, complete: bool = false) -> void:
	if not is_node_ready(): return
	var count := maxi(round_count, 1)
	var current_round := clampi(round_number, 1, count)
	var caption := "Clean" if complete else "%s · %d/%d" % ["Squeegee" if ready else "Wet", current_round, count]
	var stage := control("ProgressStage") as Label
	if stage.text == caption and stage.visible: return
	stage.text = caption
	stage.show()
	var value := control("ProgressValue") as Label
	value.offset_top = 14.0
	value.add_theme_font_size_override("font_size", 22)
	control("CleaningProgress").tooltip_text = "Clean water · carpet restored" if complete else "Wash %d of %d · %s" % [current_round, count, "Squeegee out the water" if ready else "Spray anywhere on the carpet to soak the whole rug"]
	_layout()


func clear_wet_stage() -> void:
	if not is_node_ready(): return
	control("ProgressStage").hide()
	var value := control("ProgressValue") as Label
	value.offset_top = 0.0
	value.add_theme_font_size_override("font_size", 24)
	control("CleaningProgress").tooltip_text = ""
	_layout()


func set_progression(view: Dictionary, purchases_allowed: bool = true) -> void:
	if not view.is_empty() and view == _progression and purchases_allowed == _purchases_allowed:
		return
	_progression = view.duplicate(true)
	_purchases_allowed = purchases_allowed
	if not is_node_ready(): return
	# An unaffordable offer still shows its benefit and price. A negative cost
	# means the progression is complete; can_upgrade_* controls interaction only.
	var tool_available := float(view.get("tool_cost", -1.0)) >= 0.0
	var store_id := int(view.get("store_id", 1))
	var wet := bool(view.get("wet_unlocked", false))
	var tier := clampi(int(view.get("wet_tool_level", 0)) + (4 if store_id == 4 else 0), 0, 8) if wet else clampi(int(view.get("global_tool_tier", 0)), 0, 8)
	var next_tier := mini(tier + 1, 8) if wet else clampi(int(view.get("next_global_tool_tier", tier)), 0, 8)
	var current_texture := _tool_texture(tier, wet)
	control("CurrentToolPreview").texture = current_texture
	control("NextToolPreview").texture = _tool_texture(next_tier, wet)
	(control("CurrentToolName") as Label).text = str(view.get("tool_name", "Hand brush"))
	(control("NextToolName") as Label).text = str(view.get("next_tool_name", "Wide brush"))
	(control("CurrentToolStats") as Label).text = "Soak %.2f×\nWidth %.2f m" % [float(view.get("hose_power", 1.0)), float(view.get("hose_radius", 0.19)) * 2.0] if wet else _tool_stats(float(view.get("tool_width", 1.0)), float(view.get("tool_power", 1.0)))
	(control("NextToolStats") as Label).text = "Soak %.2f×\nWidth %.2f m" % [float(view.get("next_hose_power", view.get("hose_power", 1.0))), float(view.get("next_hose_radius", view.get("hose_radius", 0.19))) * 2.0] if wet else _tool_stats(float(view.get("next_tool_width", view.get("tool_width", 1.0))), float(view.get("next_tool_power", view.get("tool_power", 1.0))))
	(control("ToolDrawerTitle") as Label).text = "Hose" if wet else "Brush"
	control("NextToolCard").visible = tool_available
	var tool_button := control("ToolUpgradeButton") as Button
	tool_button.text = "Buy %s" % _money_text(float(view.get("tool_cost", 0.0))) if tool_available else "Max"
	tool_button.tooltip_text = "%s · %s coins" % [str(view.get("next_tool_name", "Upgrade brush")), _money_text(float(view.get("tool_cost", 0.0)))] if tool_available else "Maximum tool level"
	tool_button.icon = COIN_TEXTURE if tool_available else null
	var wet_unlocked := bool(view.get("wet_unlocked", false))
	control("HoseUpgradeRow").visible = wet_unlocked and not wet
	control("SqueegeeUpgradeRow").visible = wet_unlocked
	control("WetUpgradeRows").visible = wet_unlocked
	for kind in ["hose", "squeegee"]:
		var prefix := "Hose" if kind == "hose" else "Squeegee"
		var level := int(view.get(kind + "_level", 0))
		var cost := float(view.get(kind + "_cost", -1.0))
		(control(prefix + "UpgradeTitle") as Label).text = "%s · Lv %d / 5" % [prefix, level + 1]
		var power := float(view.get(kind + "_power", 1.0))
		var next_power := float(view.get("next_" + kind + "_power", power))
		(control(prefix + "UpgradeStats") as Label).text = ("Soak" if kind == "hose" else "Extract") + (" %.2f× → %.2f×" % [power, next_power] if cost >= 0 else " %.2f× · Max" % power)
		var button := control(prefix + "UpgradeButton") as Button
		button.text = "Buy %s" % _money_text(cost) if cost >= 0 else "Max"
		button.icon = COIN_TEXTURE if cost >= 0 else null
		button.tooltip_text = ("Wider water + faster soaking" if kind == "hose" else "Remove more water with every pass") + (" · %s coins" % _money_text(cost) if cost >= 0 else " · Maximum level")
	control("UpgradeButton").tooltip_text = "Shop for tools + Bonzi upgrades"
	var full_reward := float(view.get("carpet_full_reward", view.get("full_reward", 0.0)))
	control("EarningsPerCarpet").visible = full_reward > 0.0
	(control("CarpetEarningsValue") as Label).text = _money_text(full_reward)
	control("EarningsPerCarpet").tooltip_text = "%s coins per fully cleaned carpet" % _money_text(full_reward)
	_set_bonzi_offer(view)
	_refresh_availability()
	_layout()


func set_carpet_ad_offer(state: CarpetAdState) -> void:
	if state == _carpet_ad_state: return
	_carpet_ad_state = state
	if not is_node_ready(): return
	_refresh_carpet_ad()
	_refresh_availability()
	_layout()


func set_ad_offer(amount: float, available: bool) -> void:
	# Compatibility for detached legacy HUD previews. Production supplies the
	# current carpet's verified offer state and never displays a receipt amount.
	set_carpet_ad_offer(CarpetAdState.READY if available and amount > 0.0 else CarpetAdState.HIDDEN)


func _refresh_carpet_ad() -> void:
	var button := control("AdRewardButton") as Button
	button.visible = _carpet_ad_state != CarpetAdState.HIDDEN
	button.text = "…" if _carpet_ad_state == CarpetAdState.REQUESTING else "2×"
	button.icon = AD_VIDEO_LOCKED if _carpet_ad_state == CarpetAdState.LOCKED else (AD_VIDEO_ACTIVE if _carpet_ad_state == CarpetAdState.ACTIVE else AD_VIDEO_PLAY)
	match _carpet_ad_state:
		CarpetAdState.LOCKED: button.tooltip_text = "Watch a video for 2× on this carpet · video unavailable"
		CarpetAdState.READY: button.tooltip_text = "Watch a video for 2× earnings on this carpet"
		CarpetAdState.REQUESTING: button.tooltip_text = "Waiting for the video reward to be verified"
		CarpetAdState.ACTIVE: button.tooltip_text = "2× earnings active on this carpet"
		_: button.tooltip_text = ""


func _tool_stats(width: float, power: float) -> String:
	return "↔ %.2f×\n✦ %.2f×" % [width, power]


func _money_text(amount: float) -> String:
	return Money.format(amount)


func _set_bonzi_offer(view: Dictionary) -> void:
	control("BonziContents").visible = view.has("bonzi_tier")
	var tier := int(view.get("bonzi_tier", -1))
	var next_tier := mini(tier + 1, 2)
	var cost := float(view.get("bonzi_cost", -1.0))
	var hired := tier >= 0
	var locked := not hired and int(view.get("local_jobs", 0)) < 3
	var titles := ["Bonzi I", "Bonzi II", "Bonzi III"]
	(control("CurrentBonziName") as Label).text = titles[clampi(tier, 0, 2)] if hired else "Not hired"
	(control("NextBonziName") as Label).text = titles[clampi(next_tier, 0, 2)]
	(control("CurrentBonziStats") as Label).text = "%s coins\nEvery %ds" % [_money_text(float(view.get("bonzi_reward", 0.0))), int(view.get("bonzi_seconds", 0))] if hired else "No earnings yet"
	(control("NextBonziStats") as Label).text = "%s coins\nEvery %ds" % [_money_text(float(view.get("full_reward", 0.0))), int(Progression.bot_seconds(next_tier))]
	control("CurrentBonziPreview").modulate = Color.WHITE if hired else Color(1,1,1,0.35)
	(control("CurrentBonziPreview").get_parent().get_node("Words/State") as Label).text = "Working" if hired else "Current"
	(control("NextBonziPreview").get_parent().get_node("Words/State") as Label).text = "Next" if hired else "Hire"
	control("NextBonziCard").visible = cost >= 0.0
	var button := control("BonziUpgradeButton") as Button
	button.text = ("Hire " if not hired else "Buy ") + _money_text(cost) if cost >= 0.0 else "Max"
	button.icon = COIN_TEXTURE if cost >= 0.0 else null
	button.tooltip_text = "Complete 3 paid carpets to hire Bonzi" if locked else ("%s coins · automatic cleaning every %ds" % [_money_text(cost), int(Progression.bot_seconds(next_tier))] if cost >= 0.0 else "Bonzi is at maximum speed")


func _refresh_availability() -> void:
	if not is_node_ready(): return
	var ready := _purchases_allowed and pending_reward == 0 and not _progression.is_empty()
	var tool_cost := float(_progression.get("tool_cost", -1.0))
	var tool := control("ToolUpgradeButton") as Button
	tool.disabled = not ready or not bool(_progression.get("can_upgrade_tool", tool_cost >= 0)) or tool_cost < 0 or _actual_balance < tool_cost
	var bonzi_cost := float(_progression.get("bonzi_cost", -1.0))
	(control("BonziUpgradeButton") as Button).disabled = not ready or not bool(_progression.get("can_upgrade_bonzi", false)) or bonzi_cost < 0.0 or _actual_balance < bonzi_cost
	var bonzi_locked := int(_progression.get("bonzi_tier", -1)) < 0 and int(_progression.get("local_jobs", 0)) < 3
	var bonzi_status := control("BonziStatus") as Label
	bonzi_status.text = "Paid carpets: %d / 3 to hire" % mini(int(_progression.get("local_jobs", 0)), 3) if bonzi_locked else ("Max speed" if bonzi_cost < 0.0 else ("Need %s coins" % _money_text(bonzi_cost) if _actual_balance < bonzi_cost else ""))
	bonzi_status.visible = not bonzi_status.text.is_empty()
	(control("AdRewardButton") as Button).disabled = _carpet_ad_state != CarpetAdState.READY or not _purchases_allowed or pending_reward > 0 or upgrades_open()
	for kind in ["hose", "squeegee"]:
		var button := control(("Hose" if kind == "hose" else "Squeegee") + "UpgradeButton") as Button
		var cost := float(_progression.get(kind + "_cost", -1.0))
		button.disabled = not ready or not bool(_progression.get("wet_unlocked", false)) or not bool(_progression.get("can_upgrade_" + kind, false)) or cost < 0 or _actual_balance < cost
	var done := control("CloseUpgradesButton")
	var focusable: Array[Control] = [done]
	for node_name in ["ToolUpgradeButton", "HoseUpgradeButton", "SqueegeeUpgradeButton", "BonziUpgradeButton"]:
		var button := control(node_name) as Button
		if button.is_visible_in_tree() and not button.disabled: focusable.append(button)
		elif upgrades_open() and button.has_focus(): done.grab_focus()
	for index in focusable.size():
		var button := focusable[index]
		button.focus_next = button.get_path_to(focusable[(index + 1) % focusable.size()])
		button.focus_previous = button.get_path_to(focusable[(index + focusable.size() - 1) % focusable.size()])


func _on_tool_upgrade_pressed() -> void:
	if upgrades_open() and not (control("ToolUpgradeButton") as Button).disabled:
		request_tool_upgrade.emit()


func _on_bonzi_upgrade_pressed() -> void:
	if upgrades_open() and not (control("BonziUpgradeButton") as Button).disabled:
		request_bonzi_upgrade.emit()


func _on_wet_upgrade_pressed(kind: String) -> void:
	var button := control(("Hose" if kind == "hose" else "Squeegee") + "UpgradeButton") as Button
	if not upgrades_open() or not button.is_visible_in_tree() or button.disabled: return
	if kind == "hose": request_hose_upgrade.emit()
	else: request_squeegee_upgrade.emit()


func _on_ad_reward_pressed() -> void:
	if _carpet_ad_state == CarpetAdState.READY and not (control("AdRewardButton") as Button).disabled:
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


func initialize_wallet(balance: float) -> void:
	# Re-entering shows the durable balance, even if the previous view closed
	# halfway through a purely cosmetic payout.
	_actual_balance = maxf(balance, 0.0)
	pending_reward = 0.0
	_reserved_reward = 0.0
	_queued_rewards.clear()
	_reward_running = false
	_cleaning_pending = 0.0
	_cleaning_count_start = 0.0
	_cleaning_count_time = 0.0
	if _wallet_tween != null and _wallet_tween.is_valid(): _wallet_tween.kill()
	if is_node_ready(): control("Wallet").scale = Vector2.ONE
	set_process(false)
	for index in _coin_nodes.size():
		_coin_nodes[index].hide()
		_coin_flights[index].clear()
	_refresh_wallet()


func reserve_reward(amount: float) -> void:
	# Call before the ledger emits its balance change so those coins wait for
	# their flight. Ordinary automation income is never held back.
	var value := maxf(amount, 0.0)
	_reserved_reward += value
	pending_reward += value
	_refresh_availability()


func cancel_reserved_reward(amount: float) -> void:
	var value := minf(maxf(amount, 0.0), _reserved_reward)
	_reserved_reward = maxf(_reserved_reward - value, 0.0)
	pending_reward = maxf(pending_reward - value, 0.0)
	_refresh_wallet()


func sync_wallet(balance: float) -> void:
	var next_balance := maxf(balance, 0.0)
	# Buying spends already-earned money. Its durable result is shown at once,
	# rather than deducting a cosmetic cleaning credit for a second time.
	if next_balance < _actual_balance:
		_cleaning_pending = 0.0
		_cleaning_count_start = 0.0
	_actual_balance = next_balance
	_refresh_wallet()


func show_cleaning_reward(amount: float, balance: float, _origin_screen: Vector2 = Vector2.INF) -> void:
	# The ledger has already credited this money. One bounded count accumulator
	# handles arbitrary repeated removals without consuming coin-pool slots.
	if not Money.is_valid(amount) or not Money.is_valid(balance): return
	if amount <= 0.0:
		sync_wallet(balance)
		return
	var reserved := minf(amount,_reserved_reward)
	_reserved_reward = maxf(_reserved_reward - reserved,0.0)
	pending_reward = maxf(pending_reward - reserved,0.0)
	_actual_balance = balance
	_cleaning_pending = minf(_cleaning_pending + amount,maxf(balance - pending_reward,0.0))
	_cleaning_count_start = _cleaning_pending
	_cleaning_count_time = 0.0
	set_process(true)
	_pulse_wallet(1.06)
	_refresh_wallet()


func set_wallet_paused(paused: bool) -> void:
	_wallet_paused = paused
	if _wallet_tween != null and _wallet_tween.is_valid():
		if paused: _wallet_tween.pause()
		else: _wallet_tween.play()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: set_wallet_paused(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: set_wallet_paused(_carpet_ad_state == CarpetAdState.REQUESTING)


func _pulse_wallet(peak: float) -> void:
	if not is_node_ready(): return
	var wallet := control("Wallet")
	if _wallet_tween != null and _wallet_tween.is_valid(): _wallet_tween.kill()
	_wallet_tween = create_tween()
	_wallet_tween.tween_property(wallet,"scale",Vector2.ONE * peak,0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_wallet_tween.tween_property(wallet,"scale",Vector2.ONE,0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _wallet_paused: _wallet_tween.pause()


func show_reward(amount: float, balance: float) -> void:
	if amount <= 0:
		sync_wallet(balance)
		return
	# Direct callers may omit reservation; the live game reserves before commit.
	if _reserved_reward < amount:
		reserve_reward(amount - _reserved_reward)
	_reserved_reward = maxf(_reserved_reward - amount, 0.0)
	_actual_balance = maxf(balance, 0.0)
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
	displayed_gold = maxf(_actual_balance - pending_reward - _cleaning_pending, 0.0)
	if not is_node_ready(): return
	(control("WalletValue") as Label).text = _money_text(displayed_gold)
	control("Wallet").tooltip_text = "%s coins" % _money_text(displayed_gold)
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
		# Clamp the visual count before integer conversion; even AF rewards use
		# the same small pool and never cast a monetary value to int64.
		var count := clampi(ceili(minf(amount / 2.0, 16.0)), 1, 16)
		var available: Array[int] = []
		for index in _coin_flights.size():
			if _coin_flights[index].is_empty(): available.append(index)
		if available.size() < count: return
		_queued_rewards.pop_front()
		var base_value := floorf(amount / float(count))
		var remainder := amount - base_value * float(count)
		var assigned := 0.0
		var phase := _coin_rng.randf_range(0.0, TAU)
		for order in count:
			var angle := phase + TAU * float(order) / float(count)
			var radius := _coin_rng.randf_range(0.085, 0.15)
			var slot := available[order]
			var coin_value := base_value + (1.0 if float(order) < remainder else 0.0)
			if order == count - 1:
				coin_value = maxf(amount - assigned, 0.0)
			assigned += coin_value
			_coin_flights[slot] = {
				"time": -float(order) * 0.024,
				"value": coin_value,
				"offset": Vector2(cos(angle), sin(angle)) * radius,
				"linger": 0.34 + float(order) * 0.013,
				"spin": _coin_rng.randf_range(-0.7, 0.7),
			}


func _process(delta: float) -> void:
	if _wallet_paused: return
	if _cleaning_pending > 0.0:
		_cleaning_count_time = minf(_cleaning_count_time + maxf(delta,0.0),CLEANING_COUNT_SECONDS)
		var fraction := _cleaning_count_time / CLEANING_COUNT_SECONDS
		_cleaning_pending = _cleaning_count_start * (1.0 - fraction) * (1.0 - fraction)
		if _cleaning_count_time >= CLEANING_COUNT_SECONDS: _cleaning_pending = 0.0
		_refresh_wallet()
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
		set_process(_cleaning_pending > 0.0)
		# The durable wallet is authoritative. Reset by completed flight state
		# instead of letting high-value subtraction residue keep buying locked.
		pending_reward = _reserved_reward
		_refresh_wallet()
		if _reward_running and _reserved_reward == 0:
			_reward_running = false
			reward_finished.emit()


func _arrive_coin(index: int) -> void:
	var value: float = float(_coin_flights[index].value)
	_coin_nodes[index].hide()
	_coin_flights[index].clear()
	pending_reward = maxf(pending_reward - value, 0.0)
	_refresh_wallet()
	var wallet := control("Wallet")
	if _wallet_tween != null and _wallet_tween.is_valid(): _wallet_tween.kill()
	wallet.scale = Vector2.ONE * 1.10
	_wallet_tween = create_tween()
	_wallet_tween.tween_property(wallet, "scale", Vector2.ONE, 0.19).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	coin_arrived.emit(value)


func open_upgrades() -> void:
	if upgrades_open(): return
	_begin_modal()
	(control("ToolCardsScroll") as ScrollContainer).scroll_vertical = 0
	(control("BonziCardsScroll") as ScrollContainer).scroll_vertical = 0
	(control("ShopContentsScroll") as ScrollContainer).scroll_vertical = 0
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


func open_room_upgrade(view: Dictionary, allowed: bool, anchor_screen: Vector2 = Vector2.INF) -> void:
	if upgrades_open() or view.is_empty(): return
	_begin_modal()
	_room_anchor_screen = anchor_screen if anchor_screen.is_finite() else _safe_rect().get_center()
	room_panel.show_offer(view, allowed)
	_refresh_availability()
	_layout()
	upgrades_changed.emit(true)


func set_room_upgrade_anchor(anchor_screen: Vector2) -> void:
	_room_anchor_screen = anchor_screen
	room_panel.set_item_anchor((get_node("HUD") as Control).get_global_transform().affine_inverse() * anchor_screen)


func refresh_room_upgrade(view: Dictionary, allowed: bool) -> void:
	if room_panel.visible:
		room_panel.refresh_offer(view, allowed and pending_reward == 0)


func _begin_modal() -> void:
	_focus_before_modal = get_viewport().gui_get_focus_owner()
	_background_focus_modes.clear()
	for node_name in ["HomeButton", "FinishJobButton", "UpgradeButton", "AdRewardButton"]:
		var button := control(node_name)
		_background_focus_modes[button] = button.focus_mode
		button.focus_mode = Control.FOCUS_NONE


func close_upgrades() -> void:
	if not upgrades_open(): return
	if _modal_tween != null and _modal_tween.is_valid(): _modal_tween.kill()
	control("UpgradeSheet").hide()
	room_panel.hide()
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
	_layout()


func upgrades_open() -> bool:
	return is_node_ready() and (control("UpgradeSheet").visible or room_panel.visible)


func drag_tool_contents(origin: Vector2, relative: Vector2) -> void:
	if not control("UpgradeSheet").visible: return
	var scroll_names := ["ShopContentsScroll", "ToolCardsScroll", "BonziCardsScroll"] if _shop_stacked else ["ToolCardsScroll", "BonziCardsScroll", "ShopContentsScroll"]
	for name: String in scroll_names:
		var scroll := control(name) as ScrollContainer
		if not scroll.is_visible_in_tree() or not scroll.get_global_rect().has_point(origin): continue
		if scroll.get_v_scroll_bar().max_value <= scroll.get_v_scroll_bar().page: continue
		scroll.scroll_vertical -= roundi(relative.y / maxf(scroll.get_global_transform().get_scale().y, 0.01))
		return


func modal_contains_point(point: Vector2) -> bool:
	if room_panel.visible: return room_panel.get_node("%Card").get_global_rect().has_point(point)
	return control("UpgradeSheet").visible and control("UpgradesPanel").get_global_rect().has_point(point)


func _button_contains_point(button: Control, point: Vector2) -> bool:
	if not button.get_global_rect().has_point(point): return false
	var parent := button.get_parent()
	while parent is Control:
		if parent.clip_contents and not parent.get_global_rect().has_point(point): return false
		parent = parent.get_parent()
	return true


func blocks_point(point: Vector2) -> bool:
	# The full-screen root ignores input. Only the visible controls keep a press
	# from starting a brush stroke beneath them.
	if upgrades_open(): return true
	for node_name in ["CleaningProgress", "EarningsPerCarpet", "HomeButton", "FinishJobButton", "Wallet", "UpgradeButton", "AdRewardButton"]:
		var node := control(node_name)
		if node.is_visible_in_tree() and node.get_global_rect().has_point(point):
			return true
	return false


func visible_button_at(point: Vector2, buttons: Array[Button]) -> Button:
	for button in buttons:
		if room_panel.visible and button not in room_panel.action_buttons(): continue
		if control("UpgradeSheet").visible and button not in [control("CloseUpgradesButton"), control("ToolUpgradeButton"), control("HoseUpgradeButton"), control("SqueegeeUpgradeButton"), control("BonziUpgradeButton")]: continue
		if button.is_visible_in_tree() and not button.disabled and _button_contains_point(button, point):
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


func progress_block_rect() -> Rect2:
	var block := control("CleaningProgress").get_global_rect()
	# Keep the cleaning frame reserved while completion temporarily hides
	# the entire HUD, so the next rug returns to the same camera position.
	if control("EarningsPerCarpet").visible:
		block = block.merge(control("EarningsPerCarpet").get_global_rect())
	return block


func layout_metrics() -> Dictionary:
	# Viewport rectangles are the single composition contract for the camera.
	# Local visibility keeps the frame stable while completion hides the HUD.
	if _layout_info.is_empty() and is_node_ready(): _layout()
	return _layout_info.duplicate(true)


func workshop_view_rect() -> Rect2:
	var metrics := layout_metrics()
	return metrics.get("world_rect", _safe_rect())


func _viewport_rect(local_rect: Rect2) -> Rect2:
	var transform := (get_node("HUD") as Control).get_global_transform()
	return Rect2(transform * local_rect.position, local_rect.size * transform.get_scale())


func _maximum_wallet_width(font: Font) -> float:
	var width := 136.0
	for suffix: String in Money.SUFFIXES:
		width = maxf(width, font.get_string_size("999.9" + suffix, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 32).x + 76.0)
	return width


func _layout() -> void:
	if not is_node_ready() or get_viewport() == null:
		return
	# Size the overlay from screen proportions, independently of the world's
	# 720x1000 canvas. A high-density phone must have the same readable HUD as
	# its small preview; raw pixel count is only a minimum-touch fallback.
	var viewport_size := get_viewport().get_visible_rect().size
	var window_size := Vector2(DisplayServer.window_get_size())
	if DisplayServer.get_name() == "headless": window_size = Vector2(get_window().size)
	var pixels_per_unit := minf(window_size.x / maxf(viewport_size.x, 1.0), window_size.y / maxf(viewport_size.y, 1.0))
	var raw_safe := _safe_rect()
	var landscape := raw_safe.size.x > raw_safe.size.y * landscape_aspect_threshold
	var short_side := minf(raw_safe.size.x, raw_safe.size.y)
	var elongation := maxf(raw_safe.size.x, raw_safe.size.y) / maxf(short_side, 1.0)
	# Squarer tablet screens retain room for the diorama; elongated phones use
	# a compact design canvas with larger labels and thumb-sized actions.
	var phone_weight := clampf((elongation - 1.45) / 0.30, 0.0, 1.0)
	var phone_reference := phone_landscape_height if landscape else phone_portrait_width
	var reference_short_side := lerpf(tablet_short_side, phone_reference, phone_weight)
	var ui_scale := maxf(short_side / reference_short_side, 44.0 / (56.0 * maxf(pixels_per_unit, 0.01)))
	(get_node("HUD") as Control).scale = Vector2.ONE * ui_scale
	var safe := Rect2(raw_safe.position / ui_scale, raw_safe.size / ui_scale)
	var edge := layout_edge
	var rail_left := safe.position.x + edge
	var home := control("HomeButton")
	home.position = safe.position + Vector2(edge, edge)
	home.size = Vector2(56.0, 56.0)
	var wallet := control("Wallet")
	var wallet_value := control("WalletValue") as Label
	if wallet_value.get_theme_font_size("font_size") != 32:
		wallet_value.add_theme_font_size_override("font_size", 32)
	var wallet_font := wallet_value.get_theme_font("font")
	# Reserve the widest compact amount once for the composition, regardless
	# of the current balance. Currency changes cannot move the cleaning frame.
	var minimum_rail := home.size.x + layout_gap + _maximum_wallet_width(wallet_font)
	var rail_width := minf(maxf(landscape_rail_width, minimum_rail), safe.size.x - edge * 2.0)
	var rail_right := rail_left + rail_width
	var progress := control("CleaningProgress")
	var progress_width := minf(progress_max_width, rail_width if landscape else safe.size.x - edge * 2.0)
	var number_width := wallet_font.get_string_size(wallet_value.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 32).x
	wallet.size = Vector2(maxf(136.0, number_width + 76.0), wallet_height)
	wallet.position = Vector2((rail_right if landscape else safe.end.x - edge) - wallet.size.x, safe.position.y + edge)
	wallet.pivot_offset = wallet.size * 0.5
	var header_bottom := safe.position.y + edge + maxf(home.size.y, wallet_height)
	progress.size = Vector2(progress_width, maxf(progress_height, 56.0 if control("ProgressStage").visible else 0.0))
	progress.position = Vector2(rail_left + (rail_width - progress_width) * 0.5 if landscape else safe.get_center().x - progress_width * 0.5, header_bottom + layout_gap)
	var earnings := control("EarningsPerCarpet")
	earnings.size = Vector2(minf(280.0, progress_width), earnings_height)
	earnings.position = Vector2(progress.position.x + (progress.size.x - earnings.size.x) * 0.5, progress.position.y + progress.size.y + earnings_gap)
	var upgrade := control("UpgradeButton")
	upgrade.size = Vector2(action_height, action_height)
	var action_y := safe.end.y - edge - action_height
	upgrade.position = Vector2(rail_left, action_y)
	var finish := control("FinishJobButton")
	finish.size = Vector2(maxf(104.0, finish.get_combined_minimum_size().x), action_height)
	finish.position = Vector2((rail_right if landscape else safe.end.x - edge) - finish.size.x, action_y)
	room_panel.set_item_anchor((get_node("HUD") as Control).get_global_transform().affine_inverse() * _room_anchor_screen)
	room_panel.layout_in(safe)
	var hint := control("RoomHint")
	var ad := control("AdRewardButton")
	ad.size = Vector2(maxf(96.0, ad.get_combined_minimum_size().x), action_height)
	var action_rect := Rect2(upgrade.position, upgrade.size).merge(Rect2(finish.position, finish.size))
	var ad_gap_left := upgrade.position.x + upgrade.size.x + layout_gap
	var ad_gap_right := finish.position.x - layout_gap
	ad.position = Vector2((ad_gap_left + ad_gap_right - ad.size.x) * 0.5, action_y)
	if ad.visible: action_rect = action_rect.merge(Rect2(ad.position, ad.size))
	hint.size = Vector2(safe.end.x - edge - ad_gap_left, 22.0)
	hint.position = Vector2(ad_gap_left, action_y + (action_height - hint.size.y) * 0.5)
	hint.visible = not landscape and not finish.visible and not ad.visible and not upgrades_open()
	var header_rect := Rect2(home.position, home.size).merge(Rect2(wallet.position, wallet.size)).merge(Rect2(progress.position, progress.size))
	if earnings.visible: header_rect = header_rect.merge(Rect2(earnings.position, earnings.size))
	var world_rect: Rect2
	var rail_rect := Rect2()
	if landscape:
		rail_rect = Rect2(Vector2(safe.position.x, safe.position.y), Vector2(edge + rail_width, safe.size.y))
		world_rect = Rect2(Vector2(rail_right + world_gutter, safe.position.y + edge), Vector2(maxf(1.0, safe.end.x - edge - rail_right - world_gutter), maxf(1.0, safe.size.y - edge * 2.0)))
	else:
		var world_top := header_rect.end.y + world_gutter
		var world_bottom := action_rect.position.y - world_gutter
		world_rect = Rect2(Vector2(safe.position.x + edge, world_top), Vector2(maxf(1.0, safe.size.x - edge * 2.0), maxf(1.0, world_bottom - world_top)))
	var content_rects := {}
	for node_name: String in ["HomeButton", "Wallet", "CleaningProgress", "EarningsPerCarpet", "UpgradeButton", "FinishJobButton", "AdRewardButton", "RoomHint"]:
		var node := control(node_name)
		# Finishing a rug reveals its button without moving the room. Wallet
		# pulses are presentation only and never change the camera reservation.
		if node.visible or node_name == "FinishJobButton":
			content_rects[node_name] = _viewport_rect(Rect2(node.position, node.size))
	var previous_world: Rect2 = _layout_info.get("world_rect", Rect2())
	_layout_info = {"mode": "landscape" if landscape else "portrait", "safe_rect": raw_safe, "world_rect": _viewport_rect(world_rect), "header_rect": _viewport_rect(header_rect), "action_rect": _viewport_rect(action_rect), "rail_rect": _viewport_rect(rail_rect), "content_rects": content_rects, "ui_scale": ui_scale}
	if not previous_world.is_equal_approx(_layout_info.world_rect): composition_changed.emit()
	var panel := control("UpgradesPanel")
	_layout_shop(panel, safe, edge)
	panel.position = Vector2(safe.position.x + edge, clampf(safe.get_center().y - panel.size.y * 0.5, safe.position.y + edge, safe.end.y - panel.size.y - edge))
	panel.pivot_offset = panel.size * 0.5


func _layout_shop(panel: Control, safe: Rect2, edge: float) -> void:
	var contents := control("Contents")
	var bonzi := control("BonziContents")
	var wet_rows := control("WetUpgradeRows")
	var has_bonzi := bonzi.visible
	var has_wet := wet_rows.visible
	var available := safe.size - Vector2.ONE * edge * 2.0
	var adjacent := (has_bonzi or has_wet) and available.x >= 584.0
	_shop_stacked = has_bonzi and not adjacent
	var tool_height := 300.0 if control("NextToolCard").visible else 204.0
	var bonzi_height := 326.0 if control("NextBonziCard").visible else 230.0
	var wet_height := (178.0 if control("HoseUpgradeRow").visible else 84.0) if has_wet else 0.0
	var requested_width := 584.0 if adjacent else (340.0 if has_wet else 304.0)
	var requested_body := maxf(tool_height,bonzi_height) if adjacent and has_bonzi else tool_height
	if _shop_stacked: requested_body += bonzi_height + 16.0
	if has_wet: requested_body += wet_height + 12.0
	panel.size = Vector2(minf(requested_width, available.x), minf(requested_body + 96.0, available.y))
	var heading := control("ShopHeading")
	heading.position = Vector2(16,16)
	heading.size = Vector2(panel.size.x - 32.0,56.0)
	var scroll := control("ShopContentsScroll") as ScrollContainer
	scroll.position = Vector2(16,80)
	scroll.size = Vector2(panel.size.x - 32.0,maxf(panel.size.y - 96.0,40.0))
	var columns := control("ShopColumns")
	var usable_width := scroll.size.x - scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var column_width := (usable_width - 16.0) * 0.5 if adjacent else usable_width
	var body_height := scroll.size.y if adjacent or not has_bonzi else requested_body
	var tool_min := contents.get_combined_minimum_size().y
	var bonzi_min := bonzi.get_combined_minimum_size().y if has_bonzi else 0.0
	if adjacent and has_bonzi:
		body_height = maxf(body_height,maxf(tool_min,bonzi_min) + (wet_height + 12.0 if has_wet else 0.0))
	var tools_end := tool_height if _shop_stacked else maxf(tool_min,body_height - (wet_height + 12.0 if has_wet and not adjacent else 0.0))
	contents.position = Vector2.ZERO
	contents.size = Vector2(column_width,tools_end)
	bonzi.position = Vector2(column_width + 16.0,0.0) if adjacent else Vector2(0,tools_end + 16.0)
	bonzi.size = Vector2(column_width,bonzi_height if _shop_stacked else maxf(bonzi_min,body_height - (wet_height + 12.0 if has_wet else 0.0)))
	if has_wet:
		wet_rows.position = Vector2(column_width + 16.0,body_height - wet_height) if adjacent else Vector2(0,(bonzi.position.y + bonzi.size.y if has_bonzi else tools_end) + 12.0)
		wet_rows.size = Vector2(column_width,wet_height)
	var content_height := maxf(contents.position.y + contents.size.y,bonzi.position.y + bonzi.size.y if has_bonzi else 0.0)
	if has_wet: content_height = maxf(content_height,wet_rows.position.y + wet_rows.size.y)
	columns.custom_minimum_size = Vector2(0,content_height)
