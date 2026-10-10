extends SceneTree
## Already-credited cleaning money counts up without queuing coins or ledger writes.
const Money := preload("res://scripts/money.gd")
var hud: CanvasLayer
var checks := 0
var failures := 0
var completed := 0

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Cleaning wallet checks require -- --shop-test")
		quit(2)
		return
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frame() -> void:
	await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func advance(seconds: float) -> void:
	var before: float = hud.displayed_gold
	hud._process(seconds)
	check(hud.displayed_gold >= before and hud.displayed_gold <= hud._actual_balance,"Count-up stays monotone and below the durable wallet")

func capture(label: String) -> void:
	if "--cleaning-wallet-capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await frame()
	var folder := ProjectSettings.globalize_path("res://../art/renders/cleaning_wallet")
	DirAccess.make_dir_recursive_absolute(folder)
	var pixels := root.get_texture().get_image()
	check(pixels.save_png(folder.path_join(label + ".png")) == OK,"The real wallet count-up preview saves")
	print("CLEANING_WALLET_CAPTURE ",label," window=",root.size," pixels=",pixels.get_size()," reference=",root.content_scale_size)

func run() -> void:
	root.size = Vector2i(591,1280)
	root.content_scale_size = Vector2i(720,1000)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	hud = load("res://scenes/ui/cleaning_hud.tscn").instantiate()
	root.add_child(hud)
	hud.reward_finished.connect(func(): completed += 1)
	await frame()
	hud.initialize_wallet(100.0)
	var nodes := hud.get_child_count()
	var coin_nodes: int = hud._coin_nodes.size()
	var camera_rect: Rect2 = hud.workshop_view_rect()
	hud.reserve_reward(10.0)
	hud.sync_wallet(110.0)
	check(hud.displayed_gold == 100.0,"A reserved saved credit does not jump before its count-up")
	hud.show_cleaning_reward(10.0,110.0)
	check(hud.displayed_gold == 100.0 and hud.pending_reward == 0.0,"Cleaning consumes its reservation and leaves purchases available")
	advance(0.06)
	check(hud.displayed_gold > 100.0 and hud.displayed_gold < 110.0,"The wallet visibly counts through intermediate values")
	var midway: float = hud.displayed_gold
	for _change: int in 30: hud.sync_wallet(110.0)
	check(hud.displayed_gold == midway,"Repeated saved-state notifications preserve the count-up")
	hud.set_wallet_paused(true)
	var pose: Vector2 = hud.control("Wallet").scale
	advance(1.0)
	check(hud.displayed_gold == midway and hud.control("Wallet").scale == pose,"Focus pause freezes number and wallet pose")
	hud.set_wallet_paused(false)
	advance(0.20)
	check(hud.displayed_gold == 110.0 and hud._cleaning_pending == 0.0,"Count-up settles to the exact durable balance")
	hud.show_cleaning_reward(10.0,120.0)
	advance(0.05)
	hud.sync_wallet(40.0)
	check(hud.displayed_gold == 40.0 and hud._cleaning_pending == 0.0,"A purchase immediately shows its exact durable remaining coins")
	hud.initialize_wallet(100.0)
	var target := 100.0
	for _credit: int in 2000:
		target += 1.0
		hud.show_cleaning_reward(1.0,target)
		advance(0.01)
	check(hud.active_coin_count() == 0 and hud._queued_rewards.is_empty() and hud._coin_nodes.size() == coin_nodes and hud.get_child_count() == nodes,"Thousands of credits cannot overflow or expand the fixed coin/node pool")
	advance(0.25)
	check(hud.displayed_gold == target and hud._cleaning_pending == 0.0,"Rapid merged credits settle without losing any display value")
	check(hud.workshop_view_rect().is_equal_approx(camera_rect),"Counting and wallet pulses leave the room camera reservation stable")
	hud.initialize_wallet(1000.0)
	hud.reserve_reward(40.0)
	hud.sync_wallet(1040.0)
	hud.show_reward(40.0,1040.0)
	hud.show_cleaning_reward(20.0,1060.0)
	for _tick: int in 160: hud._process(0.02)
	check(hud.displayed_gold == 1060.0 and hud.pending_reward == 0.0 and completed == 1,"Legacy completion coins and live count-up settle together exactly once")
	for amount: float in [1e15,1e30,1e60]:
		hud.initialize_wallet(0.0)
		hud.show_cleaning_reward(amount,amount)
		advance(0.12)
		check(is_finite(hud.displayed_gold) and hud.displayed_gold > 0.0 and hud.displayed_gold < amount,"Large currency counts smoothly without integer conversion")
		advance(0.13)
		check(hud.displayed_gold == amount and (hud.control("WalletValue") as Label).text == Money.format(amount),"Large currency ends at its exact bounded formatted balance")
	hud.initialize_wallet(120.0)
	hud.show_cleaning_reward(20.0,140.0)
	hud._process(0.07)
	root.size = Vector2i(844,390)
	await frame()
	check(is_finite(hud.displayed_gold) and hud.displayed_gold <= 140.0,"Rotation safely preserves the active target")
	hud._process(0.30)
	check(hud.displayed_gold == 140.0,"Rotation cannot lose earned money")
	hud.show_cleaning_reward(25.0,165.0)
	hud.initialize_wallet(165.0)
	check(hud.displayed_gold == 165.0 and hud._cleaning_pending == 0.0 and hud.control("Wallet").scale == Vector2.ONE,"Re-entry/reset shows saved money and restores the exact wallet pose")
	for size: Vector2i in [Vector2i(591,1280),Vector2i(390,844),Vector2i(844,390)]:
		root.size = size
		hud.initialize_wallet(100.0)
		await frame()
		await capture("before_%dx%d" % [size.x,size.y])
		hud.show_cleaning_reward(20.0,120.0)
		await frame()
		await frame()
		check(hud.control("Wallet").scale.x > 1.0 and hud.control("Wallet").scale.x <= 1.061,"The cleaning wallet has a subtle bounded pulse")
		await capture("counting_%dx%d" % [size.x,size.y])
		for _tick: int in 12: await frame()
		check(hud.displayed_gold == 120.0 and hud.control("Wallet").scale.is_equal_approx(Vector2.ONE),"The visible wallet settles promptly without lingering transform")
		await capture("settled_%dx%d" % [size.x,size.y])
	hud.free()
	root.get_node("GameAudio")._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	print("CLEANING_WALLET_VALIDATION %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
