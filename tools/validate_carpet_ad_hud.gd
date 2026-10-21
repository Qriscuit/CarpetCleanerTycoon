extends SceneTree
## Current-carpet video states, real touch routing and physical phone bounds.
## Pinned Mono renderer and -- --shop-test; optional --ad-hud-capture.
const Routes := preload("res://scripts/scene_routes.gd")
var checks := 0
var failures := 0
var game: Node
var state: Node
var requested := 0
var save_path := ""

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Carpet video HUD validation requires a renderer and -- --shop-test")
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CARPET VIDEO HUD: " + message)

func frames(count: int = 2) -> void:
	for _frame in count:
		await process_frame
		await RenderingServer.frame_post_draw

func tap(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = button.get_global_rect().get_center()
		event.index = 0
		event.pressed = pressed
		root.push_input(event, true)

func capture(label: String) -> void:
	if "--ad-hud-capture" not in OS.get_cmdline_user_args(): return
	await frames()
	check(root.get_texture().get_image().save_png("res://../art/renders/carpet_ad_" + label + ".png") == OK, "Actual renderer preview saved: " + label)

func physical_scale() -> Vector2:
	return Vector2(root.size) / root.get_visible_rect().size

func footer_bounds(label: String) -> void:
	var hud: Node = game.hud
	var safe: Rect2 = hud.layout_metrics().safe_rect
	var world: Rect2 = hud.workshop_view_rect()
	var scale := physical_scale()
	var cart: Rect2 = hud.control("UpgradeButton").get_global_rect()
	var video: Rect2 = hud.control("AdRewardButton").get_global_rect()
	var finish: Rect2 = hud.control("FinishJobButton").get_global_rect()
	for name: String in ["UpgradeButton", "AdRewardButton", "FinishJobButton"]:
		var rectangle: Rect2 = hud.control(name).get_global_rect()
		var physical := rectangle.size * scale
		check(physical.x >= 43.99 and physical.y >= 43.99, label + ": " + name + " has at least44 physical pixels for touch")
		check(safe.grow(0.5).encloses(rectangle), label + ": " + name + " stays inside the safe area")
		check(not rectangle.intersects(world), label + ": " + name + " leaves the diorama clear")
	check((video.position.x - cart.end.x) * scale.x >= 5.99 and (finish.position.x - video.end.x) * scale.x >= 5.99, label + ": video sits physically between cart and Finish with breathing room")
	check(absf(cart.position.y - video.position.y) < 0.1 and absf(finish.position.y - video.position.y) < 0.1, label + ": all three actions share the same row")
	check((hud.control("FinishJobButton") as Button).text == "Finish", label + ": Finish contains no payout amount")

func quote_view(boosted: bool = false) -> Dictionary:
	var view: Dictionary = state.progression_view()
	view.carpet_full_reward = 80.0 if boosted else 40.0
	return view

func validate_states(label: String) -> void:
	var hud: Node = game.hud
	var button: Button = hud.control("AdRewardButton")
	var finish: Button = hud.control("FinishJobButton")
	hud.set_progression(quote_view(), true)
	hud.set_carpet_ad_offer(hud.CarpetAdState.LOCKED)
	finish.show()
	hud._layout()
	await frames()
	var original_world: Rect2 = hud.workshop_view_rect()
	var original_video: Rect2 = button.get_global_rect()
	var original_camera: Transform3D = game.camera.global_transform
	var original_camera_size: float = game.camera.size
	var original_cash: float = state.cash
	var original_mask: PackedByteArray = game.soil.mask.get_data()
	var original_request := requested
	check(button.visible and button.disabled and button.text == "2×" and button.icon.resource_path.ends_with("video_locked.svg"), label + ": no provider leaves a readable video2× button with a padlock")
	footer_bounds(label + " locked")
	tap(button)
	await frames()
	check(requested == original_request and state.cash == original_cash and game.soil.mask.get_data() == original_mask and not game.brush_dragging, label + ": locked touch neither requests a video nor cleans or invents money")
	await capture("locked_" + label)
	for ad_state: int in [hud.CarpetAdState.READY, hud.CarpetAdState.REQUESTING, hud.CarpetAdState.ACTIVE]:
		hud.set_carpet_ad_offer(ad_state)
		await frames()
		check(button.visible and button.get_global_rect().is_equal_approx(original_video) and hud.workshop_view_rect().is_equal_approx(original_world), label + ": every video state keeps its fixed button and room space")
		check(game.camera.global_transform.is_equal_approx(original_camera) and is_equal_approx(game.camera.size, original_camera_size), label + ": offer feedback cannot move the camera")
		if ad_state == hud.CarpetAdState.READY:
			check(not button.disabled and button.text == "2×" and button.icon.resource_path.ends_with("video_play.svg"), label + ": ready shows an enabled play illustration")
			tap(button)
			await create_timer(0.30).timeout
			check(requested == original_request + 1 and state.cash == original_cash and not game.brush_dragging, label + ": real touch requests once while the absent provider cannot invent a reward")
		elif ad_state == hud.CarpetAdState.REQUESTING:
			check(button.disabled and button.text == "…", label + ": pending verification is clearly waiting and cannot be requested twice")
			hud._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
			hud._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
			check(hud._wallet_paused, label + ": focus return preserves a pending video's wallet pause")
		else:
			hud.set_progression(quote_view(true), true)
			check(button.disabled and button.text == "2×" and button.icon.resource_path.ends_with("video_active.svg"), label + ": an active boost remains visibly marked with its check")
			check((hud.control("CarpetEarningsValue") as Label).text == "80", label + ": the current-carpet quote doubles")
			await capture("active_" + label)
		footer_bounds(label + " state%d" % ad_state)
	hud.set_wallet_paused(false)
	hud.initialize_wallet(9.999e56)
	await frames()
	footer_bounds(label + " maximum wallet")
	check(hud.workshop_view_rect().is_equal_approx(original_world) and game.camera.global_transform.is_equal_approx(original_camera), label + ": a very large wallet cannot move the action row or camera")
	finish.hide()
	hud._layout()
	check(hud.workshop_view_rect().is_equal_approx(original_world) and button.get_global_rect().is_equal_approx(original_video), label + ": reserving hidden Finish keeps the row and room stable")
	finish.show()
	hud.set_carpet_ad_offer(hud.CarpetAdState.READY)
	hud.open_upgrades()
	check(hud.upgrades_open() and button.disabled and hud.blocks_point(hud.workshop_view_rect().get_center()), label + ": the shop popup blocks video actions and cleaning below it")
	var before_modal := requested
	hud._on_ad_reward_pressed()
	check(requested == before_modal, label + ": popup cannot forward a background video request")
	hud.close_upgrades()
	hud.set_carpet_ad_offer(hud.CarpetAdState.LOCKED)
	hud.initialize_wallet(state.cash)
	await frames()

func run() -> void:
	state = root.get_node("ShopState")
	state.set_process(false)

	state._save_path = "res://../art/carpet_ad_hud_test_%d.json" % OS.get_process_id()
	save_path = state._save_path
	check(state.reset_progress(), "Use an isolated video HUD save")
	game = load(Routes.CLEANING).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frames()
	game.hud.request_rewarded_ad.connect(func(): requested += 1)
	check(game.hud.control("AdRewardButton").visible and game.hud.control("AdRewardButton").disabled, "Production paid cleaning displays its locked video control without a provider")
	for size: Vector2i in [Vector2i(390,844), Vector2i(591,1280), Vector2i(844,390), Vector2i(320,568)]:
		root.size = size
		root.content_scale_size = Vector2i(720,1000)
		await frames()
		for use_insets: bool in [false,true]:
			var scale := Vector2(root.get_visible_rect().size) / Vector2(root.size)
			var landscape := size.x > size.y
			var physical_insets := Vector4(20,0,12,12) if landscape else Vector4(10,24,10,20)
			game.hud.preview_safe_insets = Vector4(physical_insets.x * scale.x,physical_insets.y * scale.y,physical_insets.z * scale.x,physical_insets.w * scale.y) if use_insets else Vector4.ZERO
			game.hud._layout()
			game.frame_carpet()
			await frames()
			await validate_states("%dx%d_720canvas%s" % [size.x,size.y,"_safe" if use_insets else ""])
	game.free()
	current_scene = null
	await frames()
	game = load(Routes.GYM).instantiate()
	game.animate_rug_changes = false
	root.add_child(game)
	current_scene = game
	await frames()
	check(not game.hud.control("AdRewardButton").visible, "Free Gym hides paid video offers")
	game.free()
	current_scene = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("CARPET_AD_HUD_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
