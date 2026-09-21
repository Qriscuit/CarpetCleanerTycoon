extends SceneTree
## Isolated with: Godot --headless --path CarpetToy --script ../tools/validate_wet_cleaning.gd -- --shop-test

var checks := 0
var failures := 0
var changed_signals := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	if "--shop-test" not in OS.get_cmdline_user_args():
		push_error("Refusing to run without --shop-test")
		quit(2)
		return
	call_deferred("run")

func run() -> void:
	var rug := Node3D.new()
	var dirty := (load("res://scenes/dirty_carpet.tscn") as PackedScene).instantiate()
	dirty.name = "Dirty"
	rug.add_child(dirty)
	root.add_child(rug)
	var soil := preload("res://scripts/dirt_controller.gd").new()
	root.add_child(soil)
	soil.automatic_completion_enabled = false
	soil.setup(rug)
	soil.surface_changed.connect(func(): changed_signals += 1)
	var pool_id := soil.batch.get_instance_id()
	var wet_texture_id := soil.wet_texture.get_instance_id()

	soil.set_recipe(true)
	check(soil.wet_recipe and soil.overall_clearance() == 0.0 and soil.recommended_tool() == 0, "Wet jobs begin with the brush stage at zero progress")
	soil.set_tool_strength(4.41)
	check(is_equal_approx(soil.tool_strength, 4.41), "Store 4 capstone power is applied without clipping")
	soil.set_tool_strength(1.0)
	soil.apply_water_stroke(Vector3(-1, 0.067, 0), Vector3(1, 0.067, 0), 0.08)
	soil.apply_squeegee_stroke(Vector3(-1, 0.067, 0), Vector3(1, 0.067, 0), 0.08)
	check(soil.water_clearance() == 0.0 and soil.extraction_clearance() == 0.0, "Water and extraction cannot skip the dry stage")

	# Isolate wet interaction after a completed brush pass. Existing dry tests
	# cover physical clumps and dust painting in detail.
	soil.remaining = 0
	soil.credited.fill(true)
	soil.cleared.fill(true)
	soil.coverage_values.fill(0.0)
	soil.surface_coverage_total = 0.0
	soil.mask.fill(Color.BLACK)
	soil.mask_changed = true
	soil._process(0.0)
	check(soil.overall_clearance() > 0.329 and soil.overall_clearance() < 0.334 and soil.recommended_tool() == 2, "A clean dry layer contributes the first third and recommends water")

	soil.set_tool_strength(1.0)
	for z_step in range(19):
		var z := -1.62 + float(z_step) * 0.18
		for pass_index in 3:
			soil.apply_water_stroke(Vector3(-1.15, 0.067, z), Vector3(1.15, 0.067, z), 0.08)
	soil._process(0.0)
	check(soil.water_clearance() >= 0.99 and soil.extraction_clearance() == 0.0, "Overlapping spray passes wet the full loosened rug without extracting it")
	check(soil.overall_clearance() > 0.659 and soil.overall_clearance() < 0.668 and soil.recommended_tool() == 1, "Water contributes the second third and recommends the squeegee")
	check(bool(soil.surface_materials[0].get_shader_parameter("wet_recipe")), "Wet recipe enables the shader layer")

	for z_step in range(34):
		var z := -1.65 + float(z_step) * 0.10
		soil.apply_squeegee_stroke(Vector3(-1.15, 0.067, z), Vector3(1.15, 0.067, z), 0.08)
	soil._process(0.0)
	check(soil.extraction_clearance() > 0.50 and soil.overall_clearance() >= 0.83, "The first extraction pass advances into the early-finish range")
	var snapshot: Dictionary = soil.make_snapshot()
	var progress: Dictionary = soil.make_progress_snapshot()
	for key: String in ["unique_clearance", "surface_clearance", "water_clearance", "extraction_clearance", "overall_clearance", "wet_recipe"]:
		check(progress.has(key), "Lightweight progress includes " + key)
	check(snapshot.has("water") and snapshot.has("extracted") and snapshot.wet_recipe, "Full snapshots persist both wet masks and the recipe")
	var extraction_before := soil.extraction_clearance()
	soil.reset()
	soil.set_recipe(true)
	check(soil.restore_snapshot(snapshot), "Wet snapshot restores")
	check(absf(soil.extraction_clearance() - extraction_before) < 0.005 and soil.recommended_tool() == 1, "Wet snapshot restores stage progress and recommendation")

	for pass_index in 2:
		for z_step in range(34):
			var z := -1.65 + float(z_step) * 0.10
			soil.apply_squeegee_stroke(Vector3(-1.15, 0.067, z), Vector3(1.15, 0.067, z), 0.08)
	soil._process(0.0)
	check(soil.extraction_clearance() >= 0.99 and soil.overall_clearance() >= 0.99, "A second extraction pass reaches perfect-clean eligibility")
	check(soil.batch.get_instance_id() == pool_id and soil.wet_texture.get_instance_id() == wet_texture_id, "Wet cleaning reuses the dirt pool and texture allocation")
	check(changed_signals >= 4, "Dry, water and extraction changes emit surface progress")

	var brush_root := Node3D.new()
	var authored := MeshInstance3D.new()
	brush_root.add_child(authored)
	root.add_child(brush_root)
	var visual := preload("res://scripts/tool_progression_visual.gd").new()
	visual.setup(brush_root)
	var variant_ids: Array[int] = []
	for model in visual.variants:
		variant_ids.append(model.get_instance_id())
	for tier in 9:
		visual.apply_tier(tier, 1.0 + tier * 0.05)
		var visible_count := 0
		for model in visual.variants:
			visible_count += 1 if model.visible else 0
		check(visual.active_tier == tier and visible_count == 1, "Tier %d swaps to one visible authored model" % tier)
	var ids_after: Array[int] = []
	for model in visual.variants:
		ids_after.append(model.get_instance_id())
	check(variant_ids == ids_after and visual.variants.size() == 9 and not authored.visible, "Tool tiers instantiate once and replace the starter mesh without churn")

	soil.queue_free()
	rug.queue_free()
	brush_root.queue_free()
	print("WET CLEANING VERIFIED: ", checks, " checks, ", failures, " failures; staged masks, persistence, pooled resources and nine visual tiers.")
	quit(1 if failures else 0)
