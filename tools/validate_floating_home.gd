extends SceneTree
var failures := 0
var checks := 0
var home: Control

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frame() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func tap_at(p: Vector2, down: bool, canceled := false) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = p
	e.pressed = down
	e.canceled = canceled
	root.push_input(e, true)

func tap(button: Button) -> void:
	var p := button.get_global_rect().get_center()
	tap_at(p,true)
	tap_at(p,false)

func mouse(button: Button) -> void:
	for down in [true,false]:
		var e := InputEventMouseButton.new()
		e.button_index=MOUSE_BUTTON_LEFT
		e.position=button.get_global_rect().get_center()
		e.global_position=e.position
		e.pressed=down
		root.push_input(e,true)

func capture(name: String) -> void:
	await frame()
	root.get_texture().get_image().save_png("res://../art/renders/floating_home_"+name+".png")

func run() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test to isolate saves")
		quit(1)
		return
	var ledger := root.get_node("ShopState")
	check(ledger.reset_progress(), "Home validation starts with an isolated fresh ledger")
	check(ProjectSettings.get_setting("application/run/main_scene")=="res://scenes/production/rug_cleaning.tscn","F5 launches the current carpet; Back opens this menu")
	home=load("res://scenes/production/floating_home.tscn").instantiate()
	check(home.get_node_or_null("%ShopViewport") != null,"3D viewport authored in saved scene")
	check(home.get_node_or_null("%ShopTap") is Button,"Building tap target authored in saved scene")
	root.add_child(home)
	current_scene=home
	home.animate_shop=false
	await frame()
	check(home.get_node("%ShopPivot").get_child_count()==1,"Real imported shop is instanced")
	var meshes := home.get_node("%ShopPivot").find_children("*","MeshInstance3D",true,false)
	check(not meshes.is_empty(),"Imported shop contains a real 3D mesh")
	for dimensions in [Vector2i(320,568),Vector2i(360,800),Vector2i(390,844),Vector2i(430,932),Vector2i(768,1024),Vector2i(568,320),Vector2i(800,360),Vector2i(844,390),Vector2i(932,430),Vector2i(1024,768)]:
		root.size=dimensions
		await frame()
		home._layout()
		await frame()
		var safe: Rect2=home._safe_rect()
		for key in ["TopBar","Dock","ShopTap","BuildingView"]:
			var rect: Rect2=home.get_node("%"+key).get_global_rect()
			check(safe.grow(1).encloses(rect),"Control fits viewport %s at %s" %[key,dimensions])
		check(not home.get_node("%Dock").get_global_rect().intersects(home.get_node("%ShopTap").get_global_rect()),"Building never overlaps dock at %s"%dimensions)
		check(home.get_node("%ShopCamera").size>=4.7,"Camera keeps minimum vertical framing")
		# All 360-degree poses stay within the transparent viewport.
		var cam: Camera3D=home.get_node("%ShopCamera")
		var viewport: SubViewport=home.get_node("%ShopViewport")
		home.get_node("%ShopPivot").scale=Vector3.ONE*1.045
		for angle in [0,45,90,135,180,225,270,315]:
			home.get_node("%ShopPivot").rotation.y=deg_to_rad(angle)
			for mesh: MeshInstance3D in meshes:
				var bounds := mesh.get_aabb()
				for corner in range(8):
					var p := cam.unproject_position(mesh.global_transform*bounds.get_endpoint(corner))
					check(Rect2(Vector2.ZERO,Vector2(viewport.size)).grow(1).has_point(p),"Rotation %d stays framed at %s"%[angle,dimensions])
		home.get_node("%ShopPivot").rotation.y=0
		home.get_node("%ShopPivot").scale=Vector3.ONE
		if dimensions==Vector2i(390,844): await capture("portrait")
		if dimensions==Vector2i(844,390): await capture("landscape")
	root.size=Vector2i(390,844)
	await frame()
	home.preview_safe_insets=Vector4(0,46,0,32)
	home._layout()
	await frame()
	check(home.get_node("%TopBar").position.y>=62,"Top controls clear simulated notch")
	check(home.get_node("%Dock").get_rect().end.y<=home.size.y-32,"Dock clears simulated gesture bar")
	await capture("safe_area")
	root.size=Vector2i(844,390)
	await frame()
	home.preview_safe_insets=Vector4(44,0,44,16)
	home._layout()
	await frame()
	check(home.get_node("%TopBar").position.x>=62,"Landscape controls clear side cutouts")
	check(home.get_node("%Dock").get_rect().end.y<=home.size.y-16,"Landscape dock clears gesture bar")
	await capture("landscape_safe_area")
	root.size=Vector2i(390,844)
	await frame()
	home.preview_safe_insets=Vector4.ZERO
	home._layout()
	ledger.cash=1234567890
	home._refresh()
	await frame()
	check(home.get_node("%TopBar").get_rect().end.x<=home.size.x,"Large coin balance does not overflow header")
	check(home.get_node("%Cash").text=="1.2B","Large coin balance uses compact display")
	ledger.cash=0
	home._refresh()
	await frame()
	check(home.get_node_or_null("%ReturnNotice") == null, "Home has no offline earnings notice")
	# Motion is real geometry animation and can be stopped.
	home.animate_shop=true
	var angle_before: float=home.get_node("%ShopPivot").rotation.y
	home._process(.1)
	check(home.get_node("%ShopPivot").rotation.y!=angle_before,"Model actually rotates")
	mouse(home.get_node("%Settings"))
	await frame()
	check(home.get_node("%SettingsSheet").visible,"Mouse opens settings")
	tap(home.get_node("%MotionToggle"))
	await frame()
	check(not home.animate_shop,"Touch toggles reduced motion")
	var backdrop: Vector2 = home.get_node("%NavShop").get_global_rect().get_center()
	tap_at(backdrop,true)
	tap_at(backdrop,false)
	await frame()
	check(not home.get_node("%SettingsSheet").visible,"Touch outside closes settings")
	check(not home.get_node("%Management").visible,"Dismissal does not open the navigation underneath")
	for definition in [["NavShop","shop"],["NavItems","items"],["NavPlans","plans"]]:
		tap(home.get_node("%"+definition[0]))
		await frame()
		check(home.get_node("%Management").visible,"Touch opens "+definition[1])
		check(home.management.current_tab==definition[1],"Existing management routes to "+definition[1])
		await capture("menu_"+definition[1])
		tap(home.management.get_node("%CloseSheet"))
		await frame()
		check(not home.get_node("%Management").visible,"Touch returns home from "+definition[1])
	# The free character menu has its own input and rendering boundary.
	var selected_store: int = ledger.active_store
	var avatar_cash: float = ledger.cash
	tap(home.get_node("%NavAvatar"))
	await frame()
	var avatar: Control = home.get_node("%AvatarMenu")
	check(avatar.visible and not home.get_node("%Management").visible, "Character button opens the wardrobe")
	check(home.get_node("%ShopViewport").render_target_update_mode == SubViewport.UPDATE_DISABLED and home.get_node("%IncomingShopViewport").render_target_update_mode == SubViewport.UPDATE_DISABLED, "Both shop viewports stop while the wardrobe is visible")
	tap(avatar.hat_cards["pirate"])
	await frame()
	check(ledger.appearance.hat_id == "pirate" and ledger.cash == avatar_cash, "A hat card equips immediately without spending coins")
	await capture("menu_avatar")
	home._back()
	await frame()
	check(not avatar.visible and ledger.active_store == selected_store, "Back closes the wardrobe without changing stores")
	check(root.gui_get_focus_owner() == home.get_node("%NavAvatar"), "Wardrobe dismissal restores character-button focus")
	# Compact shop swipes never purchase; real taps buy manual upgrades once.
	ledger.cash=300
	home._refresh()
	tap(home.get_node("%NavShop"))
	await frame()
	var menu: Control=home.management
	var buy_button: Button=menu.action_for("slot_1")
	var room_price: float = ledger.room_upgrade_view("floor").cost
	var buy_point := buy_button.get_global_rect().get_center()
	tap_at(buy_point,true)
	var swipe := InputEventScreenDrag.new()
	swipe.index=0
	swipe.position=buy_point+Vector2(0,-35)
	swipe.relative=Vector2(0,-35)
	root.push_input(swipe,true)
	tap_at(swipe.position,false)
	await frame()
	check(menu.pending_item.is_empty() and ledger.cash==300, "Swiping over an upgrade button never purchases")
	tap(buy_button)
	await frame()
	check(ledger.room_upgrade_view("floor").level == 1 and ledger.cash == 300 - room_price, "A room-upgrade tap charges once and improves the room")
	menu.show_tab("items")
	await frame()
	var tool_price: float = ledger.progression_view().tool_cost
	tap(menu.action_for("slot_2"))
	await frame()
	check(ledger.progression_view().tool_level == 1 and ledger.cash == 300 - room_price - tool_price, "Tools sheet purchases the first manual brush upgrade")
	check(menu.action_for("slot_1").disabled and menu.action_for("slot_1").text == "Using", "The equipped manual tool remains clearly selected")
	menu.show_tab("plans")
	await frame()
	check(menu.get_node("%TravelGoals").visible and menu.action_for("slot_5").disabled, "Store opening waits for the manual mastery checklist")
	await capture("manual_store_requirements")
	root.size=Vector2i(844,390)
	await frame()
	await capture("menu_landscape")
	check(home._safe_rect().encloses(menu.get_node("%Sheet").get_global_rect()),"Compact sheet fits landscape")
	tap(menu.get_node("%CloseSheet"))
	root.size=Vector2i(390,844)
	await frame()
	# Dragging the building cannot purchase/start a job, nor can canceled touch.
	var p: Vector2=home.get_node("%ShopTap").get_global_rect().get_center()
	tap_at(p,true)
	await create_timer(.10).timeout
	check(home.get_node("%ShopPivot").scale.y<.96,"Touch compresses the 3D building while held")
	var drag := InputEventScreenDrag.new()
	drag.index=0
	drag.position=p+Vector2(45,0)
	drag.relative=Vector2(45,0)
	root.push_input(drag,true)
	tap_at(p+Vector2(45,0),false)
	await create_timer(.16).timeout
	check(ledger.active_job_id.is_empty(),"Drag over building does not start job")
	check(home.get_node("%ShopPivot").scale.is_equal_approx(Vector3.ONE),"Canceled press returns building to original size")
	tap_at(p,true)
	tap_at(p,false,true)
	check(ledger.active_job_id.is_empty(),"Canceled touch does not start job")
	await create_timer(.16).timeout
	# Native mouse/keyboard signals also compress and release the model.
	var mouse_down := InputEventMouseButton.new()
	mouse_down.button_index=MOUSE_BUTTON_LEFT
	mouse_down.position=p
	mouse_down.global_position=p
	mouse_down.pressed=true
	root.push_input(mouse_down,true)
	await create_timer(.10).timeout
	check(home.get_node("%ShopPivot").scale.y<.96,"Mouse compresses the building while held")
	var motion := InputEventMouseMotion.new()
	motion.position=Vector2(2,2)
	motion.global_position=motion.position
	root.push_input(motion,true)
	var mouse_up := InputEventMouseButton.new()
	mouse_up.button_index=MOUSE_BUTTON_LEFT
	mouse_up.position=Vector2(2,2)
	mouse_up.global_position=mouse_up.position
	mouse_up.pressed=false
	root.push_input(mouse_up,true)
	await create_timer(.16).timeout
	check(ledger.active_job_id.is_empty() and home.get_node("%ShopPivot").scale.is_equal_approx(Vector3.ONE),"Mouse release outside cancels the press")
	# A real building tap starts the existing paid scene and returns to this hub.
	tap(home.get_node("%ShopTap"))
	check(current_scene==home and home.changing_scene,"Building pop happens before the scene transition")
	home.enter_cleaning()
	await create_timer(.35).timeout
	await frame()
	await frame()
	check(current_scene.scene_file_path=="res://scenes/production/rug_cleaning.tscn","Building tap opens cleaning scene")
	check(not ledger.active_job_id.is_empty() and ledger.contract_mode,"Building starts a resumable paid rug")
	var job_id: String=ledger.active_job_id
	if current_scene.has_method("return_to_shop"):
		current_scene.return_to_shop()
		await frame()
		await frame()
		check(current_scene.scene_file_path=="res://scenes/production/floating_home.tscn","Cleaning returns to new home")
		check(current_scene.get_node_or_null("%Hint")==null and not current_scene.get_node("%StatusMessage").visible,"Home stays free of text beneath the house")
		check(ledger.active_job_id==job_id,"Returning preserves active rug")
	else: check(false,"Cleaning return method exists")
	print("FLOATING_HOME_VALIDATION %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
