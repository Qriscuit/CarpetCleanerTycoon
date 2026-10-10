extends SceneTree
## Optional rendered run verifies that the room blurs while the HUD stays sharp.
## Use tools/run_godot.ps1 --path CarpetToy --script ../tools/validate_completion_focus.gd -- --shop-test.

var failures := 0
var checks := 0


func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Completion focus validation requires -- --shop-test")
		quit(2)
		return
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func frames() -> void:
	for _tick in 3:
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw


func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.0
	camera.position = Vector3(0, 0, 5)
	world.add_child(camera)
	var bars := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(12, 12)
	bars.mesh = quad
	var material := ShaderMaterial.new()
	var bars_shader := Shader.new()
	bars_shader.code = "shader_type spatial; render_mode unshaded; void fragment() { ALBEDO = vec3(step(0.5, fract(UV.x * 64.0))); }"
	material.shader = bars_shader
	bars.material_override = material
	world.add_child(bars)
	var focus := load("res://scripts/completion_focus.gd").new() as CanvasLayer
	focus.set_blur_amount(0.5)
	root.add_child(focus)
	check(is_equal_approx(focus.blur_amount, 0.5), "Blur may be set before entering the tree")
	check(focus.get_child(0).mouse_filter == Control.MOUSE_FILTER_IGNORE, "Focus never captures taps")
	check(focus.layer < 0, "Focus renders below the HUD")
	focus.set_blur_amount(-1.0)
	check(not focus.visible and is_zero_approx(focus.blur_amount), "Inactive blur does no screen-reading work")
	focus.set_blur_amount(2.0)
	check(focus.visible and is_equal_approx(focus.blur_amount, 1.0), "Blur amount is capped at one")
	focus.reset()
	check(not focus.visible and is_zero_approx(focus.blur_amount), "Reset clears interrupted transitions")
	if DisplayServer.get_name() != "headless":
		var hud := CanvasLayer.new()
		hud.layer = 1
		root.add_child(hud)
		var marker := ColorRect.new()
		marker.position = Vector2(16, 16)
		marker.size = Vector2(160, 160)
		marker.color = Color("e63258")
		var marker_shader := Shader.new()
		marker_shader.code = "shader_type canvas_item; render_mode unshaded; void fragment() { COLOR = vec4(step(0.5, fract(UV.x * 20.0)), 0.1, 0.6, 1.0); }"
		var marker_material := ShaderMaterial.new()
		marker_material.shader = marker_shader
		marker.material = marker_material
		hud.add_child(marker)
		await frames()
		var before := root.get_texture().get_image()
		focus.set_blur_amount(1.0)
		await frames()
		var after := root.get_texture().get_image()
		var world_difference := 0.0
		var hud_difference := 0.0
		for y in range(before.get_height() / 3, before.get_height() * 2 / 3, 3):
			for x in range(before.get_width() / 3, before.get_width() * 2 / 3, 3):
				world_difference += absf(before.get_pixel(x, y).r - after.get_pixel(x, y).r)
		for y in range(24, 72):
			for x in range(24, 72):
				hud_difference += absf(before.get_pixel(x, y).r - after.get_pixel(x, y).r)
		check(world_difference > 1.0, "Rendered 3D room visibly softens")
		check(is_zero_approx(hud_difference), "Rendered HUD pixels stay unchanged")
		focus.reset()
		await frames()
		var restored := root.get_texture().get_image()
		check(restored.get_data() == before.get_data(), "Reset restores the exact sharp image")
	print("Completion focus validation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
