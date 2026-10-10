extends SceneTree
## Check the prominent balance and cart route across phone sizes and safe areas.
const Money := preload("res://scripts/money.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		printerr("Home header validation requires a renderer and -- --shop-test")
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func run() -> void:
	var ledger := root.get_node("ShopState")
	ledger._save_path = "res://.godot/home_header_%d.json" % OS.get_process_id()
	check(ledger.reset_progress(), "Disposable home ledger resets")
	var home: Control = load("res://scenes/production/floating_home.tscn").instantiate()
	root.add_child(home)
	current_scene = home
	home.animate_shop = false
	await frames()
	var cash: Label = home.get_node("%Cash")
	var wallet: Control = home.get_node("TopBar/WalletPill")
	var icon: TextureRect = home.get_node("%NavShop").get_node("CaptionContent/Icon")
	check(icon.texture != null and icon.texture.resource_path == "res://assets/ui/room_upgrades/cart.svg", "Home Shop uses the matching cart illustration")
	for dimensions: Vector2i in [Vector2i(320,568), Vector2i(390,844), Vector2i(430,932), Vector2i(768,1024), Vector2i(568,320), Vector2i(844,390), Vector2i(1024,768)]:
		root.size = dimensions
		await frames()
		for insets: Vector4 in [Vector4.ZERO, Vector4(20,24,20,20)]:
			home.preview_safe_insets = insets
			for amount: float in [0.0, 740.0, 9999.0, 4.0e32, 9.999e32, 1.0e60]:
				ledger.cash = amount
				home._refresh()
				home._layout()
				await frames()
				var safe: Rect2 = home._safe_rect()
				var label_rect := cash.get_global_rect()
				var settings: Control = home.get_node("%Settings")
				var store: Label = home.get_node("%StoreLabel")
				check(cash.text == Money.format(amount), "Home formats %s at %s" % [amount,dimensions])
				check(cash.get_theme_font_size("font_size") >= 20, "Large balance remains readable at %s" % dimensions)
				check(safe.encloses(wallet.get_global_rect()) and wallet.get_global_rect().encloses(label_rect), "Balance stays inside the safe header at %s" % dimensions)
				check(not wallet.get_global_rect().intersects(settings.get_global_rect()) and not wallet.get_global_rect().intersects(store.get_global_rect()), "Balance clears settings and the store caption at %s" % dimensions)
				check(store.size.x >= 80.0 and store.get_line_count() * store.get_line_height() <= store.size.y + 1.0, "Store caption remains readable beside the balance at %s" % dimensions)
				for key: String in ["TopBar", "Dock", "BuildingView", "ShopTap"]:
					check(safe.grow(1).encloses(home.get_node("%"+key).get_global_rect()), "%s fits the safe area at %s" % [key,dimensions])
			if insets == Vector4.ZERO and dimensions in [Vector2i(390,844), Vector2i(568,320)]:
				var folder := ProjectSettings.globalize_path("res://../art/renders")
				DirAccess.make_dir_recursive_absolute(folder)
				check(root.get_texture().get_image().save_png(folder.path_join("home_header_%dx%d.png" % [dimensions.x,dimensions.y])) == OK, "Home header capture saves")
		home.preview_safe_insets = Vector4.ZERO
	home.get_node("%NavShop").pressed.emit()
	await frames()
	check(home.get_node("%Management").visible and home.management.current_tab == "shop", "Cart opens the existing Shop")
	home.management.get_node("%CloseSheet").pressed.emit()
	await frames()
	check(not home.get_node("%Management").visible, "Shop closes back to the same home")
	home.free()
	current_scene = null
	root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.06).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ledger._save_path))
	print("HOME HEADER: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
