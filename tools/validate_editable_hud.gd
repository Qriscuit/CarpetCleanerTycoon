extends SceneTree
## Production UI must exist before _ready and retain authored transforms/copy.
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("EDITABLE HUD: " + message)

func _initialize() -> void:
	call_deferred("run")

func touch(index: int, point: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)

func drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	root.push_input(event, true)

func run() -> void:
	if not "--shop-test" in OS.get_cmdline_user_args():
		push_error("Use -- --shop-test for an isolated UI run.")
		quit(2)
		return
	for scene_path in ["res://scenes/production/rug_cleaning.tscn", "res://scenes/test/starter_workshop.tscn"]:
		var authored := (load(scene_path) as PackedScene).instantiate()
		var hud: CanvasLayer = authored.get_node("GymUI")
		check(hud.get_node("%HomeButton") is Button, "Home exists in the local scene before gameplay starts")
		check(hud.get_node("%RugButton2") is Button and hud.get_node("%FinishJobButton") is Button, "Practice and paid menus are both authored")
		check(hud.get_node("%NextRugButton") is Button, "Completion button is editor-selectable")
		authored.free()
	var game := (load("res://scenes/production/rug_cleaning.tscn") as PackedScene).instantiate()
	var pre_hud: CanvasLayer = game.get_node("GymUI")
	var heading: Control = pre_hud.control("Heading")
	heading.position += Vector2(0, 5)
	var edited_position := heading.position
	(pre_hud.control("HomeButton") as Button).text = "Edited home label"
	var brush_caption: Label = pre_hud.get_node("HUD/ToolRail/BrushButton/Caption")
	brush_caption.text = "My brush"
	root.add_child(game)
	await process_frame
	await process_frame
	check(heading.position == edited_position, "Runtime preserves an edited top-level UI position")
	check(game.hud.control("HomeButton").text == "Edited home label" and brush_caption.text == "My brush", "Runtime preserves authored button and icon-caption text")
	for button in game.touch_buttons:
		check(button.custom_minimum_size.y >= 56, "Every cleaning action has a minimum 56 logical-pixel target")
	var target: Button = game.tool_buttons[1]
	var point := target.get_global_rect().get_center()
	touch(0, point, true)
	check(game.selected_tool == 0 and not game.brush_dragging, "Finger down does not select or paint")
	touch(0, point, false)
	check(game.selected_tool == 1 and not game.brush_dragging, "Finger release selects exactly the intended tool")
	game.select_tool(0)
	touch(0, point, true)
	drag(0, point + Vector2(0, 35))
	drag(0, point)
	touch(0, point, false)
	check(game.selected_tool == 0 and not game.brush_dragging, "Drag out and back permanently cancels a button gesture")
	touch(0, point, true)
	touch(1, point + Vector2(5, 5), true)
	touch(1, point, false)
	touch(0, point, false)
	check(game.selected_tool == 0 and not game.brush_dragging, "A second finger cancels the pending menu tap")
	var carpet_point: Vector2 = game.camera.unproject_position(Vector3.ZERO) - game.TOUCH_CONTACT_OFFSET
	touch(0, carpet_point, true)
	check(game.brush_dragging, "An unblocked finger starts a carpet stroke")
	touch(1, point, true)
	check(not game.brush_dragging, "A second finger ends cleaning before a UI gesture can interfere")
	drag(0, carpet_point + Vector2(0, 20))
	touch(1, point, false)
	touch(0, carpet_point, false)
	check(not game.brush_dragging and game.selected_tool == 0, "Multitouch never leaves a ghost stroke or activates a tool")
	game.select_rug(0)
	var rail: ScrollContainer = game.hud.control("LeftRail")
	var old_height := rail.offset_bottom
	rail.offset_bottom = -500
	await process_frame
	point = game.rug_buttons[1].get_global_rect().get_center()
	touch(0, point, true)
	drag(0, point - Vector2(0, 65))
	touch(0, point - Vector2(0, 65), false)
	check(game.selected_rug == 0 and not game.brush_dragging, "Swipe starting on a rug option cannot switch rugs or clean")
	check(rail.scroll_vertical > 0, "The left rail scrolls under a touch swipe")
	rail.offset_bottom = old_height
	rail.scroll_vertical = 0
	game.soil.start_vacuum(true)
	for tick in 150:
		game.soil._physics_process(1.0 / 60.0)
	check(game.hud.control("CompletionCard").visible, "Completed practice presents a next-rug choice")
	game.next_rug()
	check(game.selected_rug == 1 and not game.soil.completion_started, "Next rug advances practice without a trip through the shop")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../art/renders/editable_cleaning_hud.png"))
	game.free()
	var studio := (load("res://scenes/test/carpet_studio.tscn") as PackedScene).instantiate()
	check(studio.get_node("StudioUI/%TurntableButton") is Button, "Art studio controls are authored too")
	root.add_child(studio)
	await process_frame
	studio._toggle_turntable()
	check(studio.turn and studio.ui.get_node("%TurntableButton").button_pressed, "Art studio binds its editable controls")
	studio._reset()
	check(not studio.turn and not studio.ui.get_node("%TurntableButton").button_pressed, "Reset clears the turntable selection")
	studio.free()
	print("EDITABLE HUD CHECKS COMPLETE: ", failures, " failures; preauthored hierarchy, preserved edits, tap release, drag cancellation, multitouch, scrolling, progression and studio.")
	quit(0 if failures == 0 else 1)
