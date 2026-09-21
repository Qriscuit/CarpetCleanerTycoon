@tool
extends Control
## Main menu. The .tscn owns all visible controls and 3D assets.
const Pop = preload("res://scripts/ui/button_pop.gd")
const Routes = preload("res://scripts/scene_routes.gd")
@export var animate_shop := true
@export_range(0.0, 20.0) var rotation_speed_degrees := 7.0
@export var preview_safe_insets := Vector4.ZERO
var elapsed := 0.0
var state: Node
var management: Control
var touch_id := -1
var touch_origin := Vector2.ZERO
var touch_target: Button
var touch_dragged := false
var changing_scene := false
var original_scale_size := Vector2i.ZERO
var original_scale_aspect := 0
var original_scale_mode := 0
var original_orientation := -1
var reset_pending := false
var shop_tween: Tween
var shop_pressed := false
var preview_store := 1
var last_active_store := 1
var mouse_store_drag := false
var mouse_store_origin := Vector2.ZERO
var touch_multitouch := false
var touch_outside_settings := false
var mouse_outside_settings := false
var mouse_settings_origin := Vector2.ZERO
var mouse_settings_dragged := false
var store_materials: Array[StandardMaterial3D] = []
var store_colors: Array[Color] = []
const STORE_NAMES := ["Neighborhood", "High Street", "Wash House", "Restoration"]

func _ready() -> void:
	resized.connect(_layout)
	%SettingsPanel.minimum_size_changed.connect(_layout.call_deferred)
	if not Engine.is_editor_hint():
		var window := get_window()
		original_scale_size = window.content_scale_size
		original_scale_aspect = window.content_scale_aspect
		original_scale_mode = window.content_scale_mode
		window.content_scale_size = Vector2i(390, 390)
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		if OS.has_feature("mobile"):
			original_orientation = DisplayServer.screen_get_orientation()
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
		state = get_node("/root/ShopState")
		preview_store = state.active_store
		last_active_store = state.active_store
		_prepare_store_materials()
		state.contract_mode = false
		state.changed.connect(_refresh)
		animate_shop = bool(state.get_meta("home_animate", true))
		%ShopTap.pressed.connect(enter_cleaning)
		%ShopTap.button_down.connect(_press_shop)
		%ShopTap.button_up.connect(_release_shop)
		%ShopTap.mouse_exited.connect(_release_shop)
		%ShopTap.focus_exited.connect(_release_shop)
		for button in [%Settings,%NavShop,%NavItems,%NavPlans,%NavBonzi,%ReturnNotice,%MotionToggle,%OpenGym,%ResetProgress,%CancelReset,%ConfirmReset]: Pop.bind(button)
		%Settings.pressed.connect(_open_settings)
		%MotionToggle.toggled.connect(_toggle_motion)
		%MotionToggle.set_pressed_no_signal(animate_shop)
		%OpenGym.pressed.connect(enter_gym)
		%ResetProgress.pressed.connect(_request_reset)
		%CancelReset.pressed.connect(_cancel_reset)
		%ConfirmReset.pressed.connect(_confirm_reset)
		%ConfirmReset.focus_next = %ConfirmReset.get_path_to(%CancelReset)
		%ConfirmReset.focus_previous = %ConfirmReset.get_path_to(%CancelReset)
		%CancelReset.focus_next = %CancelReset.get_path_to(%ConfirmReset)
		%CancelReset.focus_previous = %CancelReset.get_path_to(%ConfirmReset)
		%NavShop.pressed.connect(open_management.bind("shop"))
		%NavItems.pressed.connect(open_management.bind("items"))
		%NavPlans.pressed.connect(open_management.bind("plans"))
		%NavBonzi.pressed.connect(open_management.bind("bonzi"))
		%CloseManagement.hide()
		%ReturnNotice.pressed.connect(acknowledge_return)
		%StatusTimer.timeout.connect(_clear_status)
		%NavPlans.get_node("CaptionContent/Caption").text = "Stores"
		_refresh()
		_update_store_preview()
		if not state.last_error.is_empty(): _show_error(state.last_error)
	call_deferred("_layout")

func _exit_tree() -> void:
	if Engine.is_editor_hint() or original_scale_size == Vector2i.ZERO: return
	if resized.is_connected(_layout): resized.disconnect(_layout)
	if is_instance_valid(state) and state.changed.is_connected(_refresh): state.changed.disconnect(_refresh)
	var window := get_window()
	window.content_scale_size = original_scale_size
	window.content_scale_aspect = original_scale_aspect
	window.content_scale_mode = original_scale_mode
	if original_orientation >= 0: DisplayServer.screen_set_orientation(original_orientation)

func _toggle_motion(enabled: bool) -> void:
	animate_shop = enabled
	state.set_meta("home_animate", enabled)
	if not enabled:
		%ShopPivot.rotation.y = 0.0
		%ShopPivot.position.y = 0.0

func _process(delta: float) -> void:
	if not is_node_ready() or not animate_shop or %Management.visible or shop_pressed or changing_scene: return
	elapsed += minf(delta, 0.1)
	%ShopPivot.rotation.y = deg_to_rad(rotation_speed_degrees) * elapsed
	%ShopPivot.position.y = sin(elapsed * 1.25) * 0.055

func _safe_rect() -> Rect2:
	var inset := preview_safe_insets
	if not Engine.is_editor_hint() and OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var window_size := Vector2(DisplayServer.window_get_size())
		if safe.size.x > 0 and safe.size.y > 0 and window_size.x > 0 and window_size.y > 0:
			var ratio := size / window_size
			var origin := Vector2(safe.position - DisplayServer.window_get_position()) * ratio
			var end := origin + Vector2(safe.size) * ratio
			inset = Vector4(maxf(origin.x,0), maxf(origin.y,0), maxf(size.x-end.x,0), maxf(size.y-end.y,0))
	return Rect2(Vector2(inset.x, inset.y), Vector2(maxf(size.x-inset.x-inset.z,1), maxf(size.y-inset.y-inset.w,1)))

func _layout() -> void:
	if not is_node_ready() or get_node_or_null("%TopBar") == null: return
	var safe := _safe_rect()
	var margin := 18.0
	var wide := safe.size.x > safe.size.y * 1.2
	%TopBar.position = safe.position + Vector2(margin, 16)
	%TopBar.size = Vector2(maxf(safe.size.x-margin*2, 0), 52)
	var dock_width := minf(340.0, safe.size.x-margin*2)
	%Dock.position = Vector2(safe.get_center().x-dock_width/2, safe.end.y-102)
	%Dock.size = Vector2(dock_width, 84)
	var top := safe.position.y + (18.0 if wide else 86.0)
	var bottom: float = %Dock.position.y - (14.0 if wide else 34.0)
	var area := Rect2(Vector2(safe.position.x+margin, top), Vector2(safe.size.x-margin*2, maxf(bottom-top, 100)))
	# The render is fitted using both available dimensions, never cropped to fill.
	var render_height := maxf(minf(area.size.y-36, area.size.x*1.20), 64)
	var render_width := minf(area.size.x, render_height*1.28)
	%BuildingView.position = Vector2(safe.get_center().x-render_width/2, area.position.y+maxf(area.size.y-render_height-36,0)*.4)
	%BuildingView.size = Vector2(render_width, render_height)
	%ShopCamera.size = maxf(6.2, 6.2 / maxf(render_width/render_height, 0.1))
	%ShopTap.position = %BuildingView.position + %BuildingView.size * Vector2(.10,.08)
	%ShopTap.size = %BuildingView.size * Vector2(.80,.84)
	%StatusMessage.position = safe.position+Vector2(margin,74)
	%StatusMessage.size = Vector2(safe.size.x-margin*2, 44)
	%ReturnNotice.position = Vector2(safe.get_center().x-130, safe.position.y+74)
	%ReturnNotice.size = Vector2(260, 44)
	%SettingsPanel.size = Vector2(minf(300,safe.size.x-36),280)
	%SettingsPanel.position = safe.get_center()-%SettingsPanel.size*.5
	%CloseManagement.position = safe.position+Vector2(18,12)
	if is_instance_valid(management):
		management.position = safe.position
		management.size = safe.size

func _open_settings() -> void:
	if changing_scene: return
	if %SettingsSheet.visible:
		_close_settings()
		return
	%SettingsSheet.show()
	_set_home_focus(false)
	%MotionToggle.grab_focus()

func _close_settings() -> void:
	_cancel_reset()
	%SettingsSheet.hide()
	_set_home_focus(true)
	%Settings.grab_focus()

func _request_reset() -> void:
	reset_pending = true
	%SettingsTitle.text = "Reset progress?"
	%MotionToggle.hide()
	%ResetProgress.hide()
	%OpenGym.hide()
	%ResetReview.show()
	%ResetError.hide()
	%CancelReset.grab_focus()
	_layout()

func _cancel_reset() -> void:
	reset_pending = false
	%SettingsTitle.text = "Settings"
	%ResetReview.hide()
	%ResetError.hide()
	%MotionToggle.show()
	%ResetProgress.show()
	%OpenGym.show()
	%ResetProgress.grab_focus()
	_layout()

func _confirm_reset() -> void:
	if not reset_pending: return
	if not state.reset_progress():
		%ResetError.text = "Could not save. Progress kept."
		%ResetError.show()
		return
	if is_instance_valid(management):
		management.cancel_build()
		management.refresh()
	_close_settings()
	_show_error("Progress reset")

func _set_home_focus(enabled: bool) -> void:
	for button in [%ShopTap,%Settings,%NavShop,%NavItems,%NavPlans,%NavBonzi,%ReturnNotice]:
		button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE

func _new_shop_tween() -> Tween:
	if shop_tween != null and shop_tween.is_valid(): shop_tween.kill()
	shop_tween = create_tween()
	return shop_tween

func _press_shop() -> void:
	if changing_scene: return
	shop_pressed = true
	_new_shop_tween().tween_property(%ShopPivot,"scale",Vector3(.96,.90,.96),.075).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _release_shop() -> void:
	if changing_scene: return
	shop_pressed = false
	_new_shop_tween().tween_property(%ShopPivot,"scale",Vector3.ONE,.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _refresh() -> void:
	%Cash.text = _cash_text(state.cash)
	%Cash.tooltip_text = "%d coins" % state.cash
	%ReturnNotice.visible = state.return_reward > 0 and not %StatusMessage.visible
	%ReturnNotice.text = "+%s while away · Got it" % _cash_text(state.return_reward)
	if last_active_store != state.active_store:
		last_active_store = state.active_store
		preview_store = state.active_store
		_update_store_preview()
	_refresh_store_caption()

func _prepare_store_materials() -> void:
	for mesh: MeshInstance3D in %ShopPivot.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		for index in mesh.mesh.get_surface_count():
			var original := mesh.get_active_material(index) as StandardMaterial3D
			if original == null: continue
			var material := original.duplicate() as StandardMaterial3D
			mesh.set_surface_override_material(index, material)
			store_materials.append(material)
			store_colors.append(material.albedo_color)

func _update_store_preview() -> void:
	_refresh_store_caption()
	var hues := [0.0, -0.16, 0.09, 0.22]
	for index in store_materials.size():
		var original := store_colors[index]
		store_materials[index].albedo_color = Color.from_hsv(fposmod(original.h + hues[preview_store - 1], 1.0), original.s, original.v, original.a) if original.s > 0.15 else original
	%ShopPivot.rotation.y = 0.0

func _refresh_store_caption() -> void:
	%StoreLabel.text = "%d · %s" % [preview_store, STORE_NAMES[preview_store - 1]]
	var owned: Array = state.progression_view().owned_store_ids
	%ShopTap.tooltip_text = "Open " + STORE_NAMES[preview_store - 1] if preview_store in owned else "View store milestones"

func preview_location(id: int) -> void:
	if changing_scene or id < 1 or id > 4: return
	preview_store = id
	var owned: Array = state.progression_view().owned_store_ids
	if id in owned and state.active_store != id:
		if not state.select_store(id):
			preview_store = state.active_store
			_show_error(state.last_error)
	_update_store_preview()
	_release_shop()

func _swipe_store(delta: Vector2) -> bool:
	if absf(delta.x) < 48 or absf(delta.x) < absf(delta.y) * 1.4: return false
	preview_location(clampi(preview_store + (1 if delta.x < 0 else -1), 1, 4))
	return true

func _cash_text(amount: int) -> String:
	if amount >= 1_000_000_000_000_000: return "%.1fQ" % (float(amount) / 1_000_000_000_000_000.0)
	if amount >= 1_000_000_000_000: return "%.1fT" % (float(amount) / 1_000_000_000_000.0)
	if amount >= 1_000_000_000: return "%.1fB" % (float(amount)/1_000_000_000.0)
	if amount >= 1_000_000: return "%.1fM" % (float(amount)/1_000_000.0)
	if amount >= 10_000: return "%.1fK" % (float(amount)/1_000.0)
	return str(amount)

func acknowledge_return() -> void:
	if not state.acknowledge_return():
		_show_error(state.last_error)
		return
	_refresh()

func _clear_status() -> void:
	%StatusMessage.hide()
	_refresh()

func _show_error(message: String) -> void:
	%StatusMessage.text = message
	%StatusMessage.show()
	%ReturnNotice.hide()
	%StatusTimer.start()

func enter_cleaning() -> void:
	if changing_scene: return
	if preview_store not in state.progression_view().owned_store_ids:
		open_management("plans")
		return
	changing_scene = true
	shop_pressed = false
	%ShopTap.disabled = true
	var pop := _new_shop_tween()
	pop.tween_property(%ShopPivot,"scale",Vector3.ONE*1.045,.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop.tween_property(%ShopPivot,"scale",Vector3.ONE,.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await pop.finished
	if state.start_job().is_empty():
		changing_scene = false
		%ShopTap.disabled = false
		_show_error(state.last_error)
		return
	state.contract_mode = true
	var result := get_tree().change_scene_to_file(Routes.CLEANING)
	if result != OK:
		changing_scene = false
		%ShopTap.disabled = false
		state.contract_mode = false
		_show_error("Could not open the rug. Try again.")

func enter_gym() -> void:
	if changing_scene or reset_pending: return
	changing_scene = true
	state.contract_mode = false
	var result := get_tree().change_scene_to_file(Routes.GYM)
	if result != OK:
		changing_scene = false
		_show_error("Could not open the gym. Try again.")

func open_management(tab: String) -> void:
	if changing_scene: return
	%SettingsSheet.hide()
	if not is_instance_valid(management):
		management = load("res://scenes/ui/compact_shop.tscn").instantiate()
		%Management.add_child(management)
		%Management.move_child(management, 0)
		management.closed.connect(close_management)
	management.show_tab(tab)
	%Management.show()
	_set_home_focus(false)
	management.process_mode = Node.PROCESS_MODE_INHERIT
	_layout()
	management.get_node("%CloseSheet").grab_focus()

func close_management() -> void:
	%Management.hide()
	_set_home_focus(true)
	if is_instance_valid(management):
		management.reset_touch()
		management.process_mode = Node.PROCESS_MODE_DISABLED
	%NavShop.grab_focus()

func _button_at(point: Vector2) -> Button:
	var candidates: Array[Button] = []
	if %Management.visible:
		return null
	elif %SettingsSheet.visible:
		if reset_pending: candidates = [%CancelReset, %ConfirmReset]
		else: candidates = [%MotionToggle, %ResetProgress, %OpenGym]
	else:
		candidates = [%Settings, %NavShop, %NavItems, %NavPlans, %NavBonzi, %ReturnNotice, %ShopTap]
	for button in candidates:
		if button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(point): return button
	return null

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	if changing_scene:
		get_viewport().set_input_as_handled()
		return
	# Keep the backdrop in place until release and consume the whole gesture.
	# A drag or canceled touch must not dismiss the sheet or reach the home controls.
	if mouse_outside_settings:
		if event is InputEventMouseMotion:
			mouse_settings_dragged = mouse_settings_dragged or event.position.distance_to(mouse_settings_origin) >= 12.0
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
			if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
				mouse_outside_settings = false
				if not mouse_settings_dragged and event.position.distance_to(mouse_settings_origin) < 12.0 and not %SettingsPanel.get_global_rect().has_point(event.position):
					_close_settings()
			return
	if %SettingsSheet.visible and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not %SettingsPanel.get_global_rect().has_point(event.position):
		mouse_outside_settings = true
		mouse_settings_origin = event.position
		mouse_settings_dragged = false
		get_viewport().set_input_as_handled()
		return
	if %Management.visible and is_instance_valid(management):
		if event is InputEventScreenDrag or event is InputEventScreenTouch:
			get_viewport().set_input_as_handled()
			management.handle_touch(event)
			return
	if not %Management.visible and not %SettingsSheet.visible:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and %ShopTap.get_global_rect().has_point(event.position):
				mouse_store_drag = true
				mouse_store_origin = event.position
				_press_shop()
				get_viewport().set_input_as_handled()
				return
			elif not event.pressed and mouse_store_drag:
				mouse_store_drag = false
				var delta: Vector2 = event.position - mouse_store_origin
				_release_shop()
				if not _swipe_store(delta) and delta.length() < 12: enter_cleaning()
				get_viewport().set_input_as_handled()
				return
		elif event is InputEventMouseMotion and mouse_store_drag:
			if event.position.distance_to(mouse_store_origin) > 12: _release_shop()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventScreenTouch:
		if event.pressed:
			if touch_id != -1:
				touch_multitouch = true
				touch_dragged = true
				_cancel_touch_feedback()
				get_viewport().set_input_as_handled()
				return
			var candidate := _button_at(event.position)
			if candidate == null and not %SettingsSheet.visible: return
			touch_id = event.index
			touch_origin = event.position
			touch_target = candidate
			touch_dragged = false
			touch_multitouch = false
			touch_outside_settings = %SettingsSheet.visible and not %SettingsPanel.get_global_rect().has_point(event.position)
			if candidate == %ShopTap: _press_shop()
			elif candidate != null: Pop.press(candidate)
			get_viewport().set_input_as_handled()
		elif event.index == touch_id:
			var button := touch_target
			var swiped: bool = button == %ShopTap and not event.canceled and not touch_multitouch and _swipe_store(event.position - touch_origin)
			var activate: bool = not event.canceled and not touch_dragged and touch_origin.distance_to(event.position)<12.0 and _button_at(event.position)==button
			var dismiss_settings: bool = touch_outside_settings and activate and not %SettingsPanel.get_global_rect().has_point(event.position)
			touch_id = -1
			touch_target = null
			touch_outside_settings = false
			get_viewport().set_input_as_handled()
			if dismiss_settings:
				_close_settings()
			elif activate and not swiped and is_instance_valid(button):
				if button != %ShopTap: Pop.release(button)
				if button.toggle_mode: button.button_pressed = not button.button_pressed
				button.pressed.emit()
			elif is_instance_valid(button):
				if button == %ShopTap: _release_shop()
				else: Pop.reset(button)
	elif event is InputEventScreenDrag and event.index == touch_id:
		if touch_origin.distance_to(event.position)>12.0:
			touch_dragged = true
			_cancel_touch_feedback()
		get_viewport().set_input_as_handled()

func _cancel_touch_feedback() -> void:
	if not is_instance_valid(touch_target): return
	if touch_target == %ShopTap: _release_shop()
	else: Pop.reset(touch_target)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
	elif not %Management.visible and not %SettingsSheet.visible:
		if event.is_action_pressed("ui_left"): preview_location(maxi(1, preview_store - 1))
		elif event.is_action_pressed("ui_right"): preview_location(mini(4, preview_store + 1))

func _back() -> void:
	if %SettingsSheet.visible:
		if reset_pending: _cancel_reset()
		else: _close_settings()
	elif %Management.visible: management.back()

func _notification(what: int) -> void:
	if Engine.is_editor_hint(): return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		mouse_store_drag = false
		mouse_outside_settings = false
		touch_outside_settings = false
		_cancel_touch_feedback()
		_release_shop()
		touch_id = -1
		touch_target = null
		if is_instance_valid(management): management.reset_touch()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST: _back()
