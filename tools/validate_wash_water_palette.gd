extends SceneTree
## Runtime material/pool validation without a renderer window or player-save writes.
const Water := preload("res://scripts/squeegee_water.gd")
const Impact := preload("res://scripts/water_jet_impact.gd")
const EXPECTED := [
	[Color(0.27, 0.13, 0.04), Color(0.53, 0.34, 0.16), Color(0.53, 0.34, 0.16), Color(0.24, 0.10, 0.025), Color(0.45, 0.25, 0.08)],
	[Color(0.55, 0.33, 0.12), Color(0.79, 0.60, 0.32), Color(0.79, 0.60, 0.32), Color(0.46, 0.29, 0.11), Color(0.64, 0.46, 0.23)],
	[Color(0.20, 0.76, 0.83), Color(0.72, 0.97, 0.96), Color(0.65, 0.91, 0.97), Color(0.16, 0.69, 0.79), Color(0.40, 0.84, 0.88)],
]

class VisualSource:
	extends Node
	const MASK_SIZE := Vector2i(32, 52)
	var footprint := preload("res://scripts/rug_footprint.gd").new()
	var surface_pixels := PackedByteArray()
	var water_values := PackedFloat32Array()
	var extraction_values := PackedFloat32Array()

var checks := 0
var failures := 0
var water: Node3D
var hose: Node3D
var original_ids: Dictionary

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args() or DisplayServer.get_name() != "headless":
		push_error("Use --headless and -- --shop-test")
		quit(2)
		return
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func color_of(material: ShaderMaterial, key: String) -> Color:
	var value: Variant = material.get_shader_parameter(key)
	if value is Color:
		return value
	if value is Vector4:
		return Color(value.x, value.y, value.z, value.w)
	if value == null:
		# Dummy RenderingServer keeps untouched parameters unset. Resolve the
		# real shader declaration instead of inventing a test-side default.
		var expression := RegEx.new()
		expression.compile("uniform\\s+vec4\\s+" + key + "\\s*:\\s*source_color\\s*=\\s*vec4\\(([^)]*)\\)")
		var declaration := expression.search(material.shader.code)
		if declaration != null:
			var components := declaration.get_string(1).split(",")
			if components.size() == 4:
				return Color(float(components[0]), float(components[1]), float(components[2]), float(components[3]))
	push_error("Unsupported color uniform value: %s" % str(value))
	failures += 1
	return Color(-1, -1, -1)

func ids() -> Dictionary:
	return {
		"owner": water.get_instance_id(),
		"surface_texture": water.surface_texture.get_instance_id(),
		"impact": water.impact.get_instance_id(),
		"patch": water.impact.patch.get_instance_id(),
		"patch_mesh": water.impact.patch.mesh.get_instance_id(),
		"patch_material": water.impact.patch_material.get_instance_id(),
		"droplets": water.impact.droplets.get_instance_id(),
		"droplet_batch": water.impact.droplet_batch.get_instance_id(),
		"droplet_mesh": water.impact.droplet_batch.mesh.get_instance_id(),
		"droplet_material": water.impact.droplet_material.get_instance_id(),
		"trail": water.trail.get_instance_id(),
		"trail_batch": water.trail.batch.get_instance_id(),
		"trail_mesh": water.trail.batch.mesh.get_instance_id(),
		"trail_material": water.trail.material.get_instance_id(),
		"streams": water.trail.streams.get_instance_id(),
		"stream_batch": water.trail.streams.batch.get_instance_id(),
		"stream_mesh": water.trail.streams.batch.mesh.get_instance_id(),
		"stream_material": water.trail.streams.material.get_instance_id(),
	}

func check_palette(cycle: int, label: String) -> void:
	var expected: Array = EXPECTED[cycle]
	var materials: Array[ShaderMaterial] = [water.impact.patch_material, water.impact.droplet_material, water.trail.material, water.trail.streams.material]
	var names := ["head splash", "droplets", "ridge and apron", "runoff"]
	for index in materials.size():
		var tint: Color = expected[3] if index == 3 else expected[0]
		var highlight: Color = expected[4] if index == 3 else (expected[2] if index == 1 else expected[1])
		check(color_of(materials[index], "water_tint").is_equal_approx(tint), "%s round %d %s tint" % [label, cycle + 1, names[index]])
		check(color_of(materials[index], "water_highlight").is_equal_approx(highlight), "%s round %d %s highlight" % [label, cycle + 1, names[index]])
	check(water.wash_cycle == cycle and int(water.debug_stats().wash_cycle) == cycle, "%s palette reports selected wash" % label)
	check(ids() == original_ids, "%s retains all nodes, materials, texture and mesh pools" % label)
	check(hose.patch_material.get_shader_parameter("water_tint") == null and hose.patch_material.get_shader_parameter("water_highlight") == null and hose.droplet_material.get_shader_parameter("water_tint") == null and hose.droplet_material.get_shader_parameter("water_highlight") == null, "%s hose retains untouched shader defaults" % label)
	check(color_of(hose.patch_material, "water_tint").is_equal_approx(Color(0.20, 0.76, 0.83)), "%s hose splash remains blue" % label)
	check(color_of(hose.patch_material, "water_highlight").is_equal_approx(Color(0.72, 0.97, 0.96)), "%s hose crest remains blue" % label)
	check(color_of(hose.droplet_material, "water_tint").is_equal_approx(Color(0.20, 0.76, 0.83)), "%s hose droplets remain blue" % label)
	check(color_of(hose.droplet_material, "water_highlight").is_equal_approx(Color(0.65, 0.91, 0.97)), "%s hose droplet rim remains blue" % label)

func run() -> void:
	var source := VisualSource.new()
	root.add_child(source)
	source.surface_pixels.resize(source.MASK_SIZE.x * source.MASK_SIZE.y)
	for y in source.MASK_SIZE.y:
		for x in source.MASK_SIZE.x:
			var point := (Vector2(x + 0.5, y + 0.5) / Vector2(source.MASK_SIZE) - Vector2(0.5, 0.5)) * Vector2(2.0, 3.32)
			source.surface_pixels[y * source.MASK_SIZE.x + x] = 1 if source.footprint.contains_point(point) else 0
	source.water_values.resize(source.surface_pixels.size())
	source.extraction_values.resize(source.surface_pixels.size())
	water = Water.new()
	root.add_child(water)
	water.setup(source.footprint, source.surface_pixels, source.MASK_SIZE, source)
	hose = Impact.new()
	root.add_child(hose)
	hose.setup(source.footprint, water.surface_texture)
	original_ids = ids()
	check(water.impact.patch_material != hose.patch_material and water.impact.droplet_material != hose.droplet_material, "Shared shaders retain separate hose/squeegee material state")
	check(water.impact.patch_material.shader == hose.patch_material.shader and water.impact.droplet_material.shader == hose.droplet_material.shader, "Hose and squeegee use the same shader implementation")
	check(water.impact.droplet_batch.instance_count == 24 and water.trail.batch.instance_count == 2048 and water.trail.streams.batch.instance_count == 16, "Original pooled geometry budgets remain fixed")
	check_palette(0, "setup")
	for cycle in 3:
		water.set_wash_cycle(cycle)
		check_palette(cycle, "select")
		water.set_wash_cycle(cycle)
		check_palette(cycle, "repeat selection")
		water.reset()
		check_palette(cycle, "reset")
		water.set_enabled(true)
		check(water.enabled and not water.is_processing(), "Enabling waits for funded strokes")
		check_palette(cycle, "enabled")
		water.set_enabled(false)
		check(not water.enabled and not water.impact.is_alive() and not water.trail.is_alive(), "Disabling retires all current water effects")
		check_palette(cycle, "disabled")
	water.set_wash_cycle(-10)
	check_palette(0, "clamp low")
	water.set_wash_cycle(10)
	check_palette(2, "clamp high")
	var muddy: Color = EXPECTED[0][0]
	var rinsed: Color = EXPECTED[1][0]
	var clean: Color = EXPECTED[2][0]
	check(muddy.r > muddy.g and muddy.g > muddy.b and rinsed.r > rinsed.g and rinsed.g > rinsed.b, "Early runoff palettes are brown")
	check(muddy.get_luminance() < rinsed.get_luminance() and rinsed.get_luminance() < clean.get_luminance(), "Successive washes produce brighter water")
	check(clean.b > clean.r and clean.g > clean.r, "Final wash produces clean blue water")
	water.free()
	hose.free()
	source.free()
	print("WASH_WATER_PALETTE_VALIDATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
