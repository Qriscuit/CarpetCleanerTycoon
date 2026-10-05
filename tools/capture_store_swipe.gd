extends SceneTree
## Actual renderer snapshots of the production store carousel and gradient.
const HOME := preload("res://scenes/production/floating_home.tscn")
const Pattern := preload("res://scripts/ui/home_pattern.gd")
var home: Control
var checks := 0
var failures := 0
var animation_frame := 0

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Renderer capture requires -- --shop-test and a graphics window")
		quit(2)
		return
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func frames() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func capture(path: String) -> Image:
	await frames()
	var screenshot := root.get_texture().get_image()
	check(screenshot.save_png(path) == OK, "Save renderer capture " + path)
	return screenshot

func check_gradient(image: Image, id: int) -> void:
	var pixel := Vector2i(8, image.get_height() / 2)
	var blend := 0.18 * float(pixel.x) / image.get_width() + 0.82 * float(pixel.y) / image.get_height()
	var expected := Pattern.STORE_TOP_COLORS[id - 1].lerp(Pattern.STORE_BOTTOM_COLORS[id - 1], blend)
	var actual := image.get_pixelv(pixel)
	check(absf(actual.r - expected.r) < 0.04 and absf(actual.g - expected.g) < 0.04 and absf(actual.b - expected.b) < 0.04,
		"The actual rendered background matches the store's continuous gradient")

func slide_to(id: int, prefix: String, animate: bool = false) -> void:
	home.preview_location(id)
	check(home.store_transition_active, "Navigation starts the authored two-store slide")
	home.store_transition_tween.pause()
	for sample in 21:
		var linear := float(sample) / 20.0
		var progress := 1.0 - pow(1.0 - linear, 3.0)
		home._set_store_transition_progress(progress)
		if animate:
			await capture("res://../art/renders/store_swipe_frames/frame_%03d.png" % animation_frame)
			animation_frame += 1
		elif sample not in [0, 4, 10, 20]:
			continue
		if sample in [0, 4, 10, 20]:
			await capture("res://../art/renders/store_swipe_%s_%02d.png" % [prefix, sample])
	home._settle_store_transition()
	check(not home.get_node("%IncomingBuildingView").visible and not home.store_transition_active,
		"Only the centered destination remains visible after the slide")
	var final := await capture("res://../art/renders/store_swipe_%s_settled.png" % prefix)
	check_gradient(final, id)
	if animate:
		for hold_frame in 8:
			await capture("res://../art/renders/store_swipe_frames/frame_%03d.png" % animation_frame)
			animation_frame += 1

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../art/renders/store_swipe_frames"))
	root.size = Vector2i(390, 844)
	home = HOME.instantiate()
	root.add_child(home)
	current_scene = home
	home.animate_shop = false
	await frames()
	home._layout()
	var source := await capture("res://../art/renders/store_swipe_neighborhood.png")
	check_gradient(source, 1)
	var palette_ids: Array = []
	for material: Material in home.store_materials + home.incoming_store_materials:
		palette_ids.append(material.get_instance_id())
	await slide_to(2, "portrait_1_to_2", true)
	await slide_to(3, "portrait_2_to_3", true)
	await slide_to(2, "portrait_3_to_2", true)
	await slide_to(1, "portrait_2_to_1", true)
	await slide_to(4, "portrait_1_to_4")
	root.size = Vector2i(844, 390)
	await frames()
	home._layout()
	await slide_to(3, "landscape_4_to_3")
	home.preview_safe_insets = Vector4(44, 0, 44, 16)
	home._layout()
	await slide_to(2, "landscape_safe_3_to_2")
	check(home._safe_rect().encloses(home.get_node("%TopBar").get_global_rect())
		and home._safe_rect().encloses(home.get_node("%Dock").get_global_rect()), "Stationary controls fit the landscape safe area after sliding")
	var retained: Array = []
	for material: Material in home.store_materials + home.incoming_store_materials:
		retained.append(material.get_instance_id())
	check(palette_ids == retained, "All store changes retain both fixed sets of materials")
	print("STORE_SWIPE_RENDERER %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)