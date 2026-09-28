extends SceneTree
## Isolated with: Godot --headless --path CarpetToy --script ../tools/validate_rotated_squeegee.gd -- --shop-test

const MASK_SIZE := Vector2i(256, 416)
const RUG_HALF := Vector2(1.0, 1.66)
const RUG_Y := 0.067
const STROKE_SECONDS := 0.08
const EXPECTED_FULL_EXTRACTION := STROKE_SECONDS * 7.4

var checks := 0
var failures := 0
var soil: Node
var rug: Node3D

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

func world_point(point: Vector2) -> Vector3:
	return Vector3(point.x, RUG_Y, point.y)

func pixel_index(point: Vector2) -> int:
	var uv := (point + RUG_HALF) / (RUG_HALF * 2.0)
	var pixel := Vector2i((uv * Vector2(MASK_SIZE)).floor()).clamp(Vector2i.ZERO, MASK_SIZE - Vector2i.ONE)
	return pixel.y * MASK_SIZE.x + pixel.x

func extracted_at(point: Vector2) -> float:
	return soil.extraction_values[pixel_index(point)]

func clear_extraction() -> void:
	soil.extraction_values.fill(0.0)
	soil.extraction_coverage_total = 0.0

func apply_stroke(
	start: Vector2,
	finish: Vector2,
	heading: Vector3 = Vector3.FORWARD,
	previous_heading: Vector3 = Vector3.ZERO
) -> void:
	soil.apply_squeegee_stroke(world_point(start), world_point(finish), STROKE_SECONDS, heading, previous_heading)

func max_array_difference(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var difference := 0.0
	for i in a.size():
		difference = maxf(difference, absf(a[i] - b[i]))
	return difference

func run() -> void:
	rug = Node3D.new()
	var dirty := (load("res://scenes/dirty_carpet.tscn") as PackedScene).instantiate()
	dirty.name = "Dirty"
	rug.add_child(dirty)
	root.add_child(rug)
	soil = preload("res://scripts/dirt_controller.gd").new()
	root.add_child(soil)
	soil.automatic_completion_enabled = false
	soil.setup(rug)
	soil.set_recipe(true)
	soil.prepare_water_stage()

	apply_stroke(Vector2(-0.04, 0.0), Vector2(0.04, 0.0), Vector3.RIGHT)
	check(soil.extraction_coverage_total == 0.0, "Rotated extraction cannot skip the water-stage gate")
	check(soil.apply_water_blob(Vector3.ZERO, 5.0), "Test rug accepts the shared water mask")
	check(soil.water_stage_complete(), "Full wet mask unlocks extraction")
	check(is_equal_approx(soil.squeegee_surface_height(Vector3(1.2, RUG_Y, 0.0), Vector3.FORWARD), RUG_Y), "Wide forward blade detects a rug-edge overlap")
	check(soil.squeegee_surface_height(Vector3(1.2, RUG_Y, 0.0), Vector3.RIGHT) == 0.0, "Rotated narrow blade at the same edge resolves to floor height")

	# Forward means the blade spans local X, preserving the production footprint.
	clear_extraction()
	apply_stroke(Vector2(0.0, 0.04), Vector2(0.0, -0.04), Vector3.FORWARD, Vector3.FORWARD)
	check(extracted_at(Vector2(0.25, 0.0)) > 0.55, "Forward blade extracts across its wide X axis")
	check(extracted_at(Vector2(0.0, 0.24)) < 0.001, "Forward blade remains narrow along its heading")

	clear_extraction()
	apply_stroke(Vector2(-0.04, 0.0), Vector2(0.04, 0.0), Vector3.RIGHT, Vector3.RIGHT)
	check(extracted_at(Vector2(0.0, 0.25)) > 0.55, "Side-facing blade rotates its wide axis into Z")
	check(extracted_at(Vector2(0.25, 0.0)) < 0.001, "Side-facing blade remains narrow along X")

	clear_extraction()
	var diagonal_heading := Vector3(1.0, 0.0, -1.0).normalized()
	var diagonal_2d := Vector2(diagonal_heading.x, diagonal_heading.z)
	var diagonal_side := Vector2(-diagonal_2d.y, diagonal_2d.x)
	apply_stroke(-diagonal_2d * 0.04, diagonal_2d * 0.04, diagonal_heading, diagonal_heading)
	check(extracted_at(diagonal_side * 0.25) > 0.55, "Diagonal blade extracts across its rotated width")
	check(extracted_at(diagonal_2d * 0.25) < 0.001, "Diagonal blade preserves its short front-to-back depth")

	# A 90-degree turn must include the intermediate diagonal pose, not just
	# either endpoint rectangle.
	var turn_start := Vector2(-0.02, 0.0)
	var turn_finish := Vector2(0.02, 0.0)
	var turn_probe := Vector2(0.17, 0.17)
	clear_extraction()
	apply_stroke(turn_start, turn_finish, Vector3.FORWARD, Vector3.FORWARD)
	var forward_only := extracted_at(turn_probe)
	clear_extraction()
	apply_stroke(turn_start, turn_finish, Vector3.RIGHT, Vector3.RIGHT)
	var side_only := extracted_at(turn_probe)
	clear_extraction()
	apply_stroke(turn_start, turn_finish, Vector3.RIGHT, Vector3.FORWARD)
	var turn_value := extracted_at(turn_probe)
	check(forward_only < 0.001 and side_only < 0.001 and turn_value > 0.50, "Turn sweep includes intermediate blade orientations")
	check(absf(extracted_at(Vector2.ZERO) - EXPECTED_FULL_EXTRACTION) < 0.002, "Rotation samples apply one bounded extraction amount per pixel")

	# Heading magnitude and vertical component do not change the projected blade.
	clear_extraction()
	apply_stroke(Vector2(-0.08, 0.0), Vector2(0.08, 0.0), Vector3.RIGHT, Vector3.RIGHT)
	var normalized_mask: PackedFloat32Array = soil.extraction_values.duplicate()
	clear_extraction()
	apply_stroke(Vector2(-0.08, 0.0), Vector2(0.08, 0.0), Vector3(25.0, 9.0, 0.0), Vector3(10.0, -3.0, 0.0))
	check(max_array_difference(normalized_mask, soil.extraction_values) < 0.000001, "World heading is projected and normalized before painting")

	# Shared per-pixel water caps remain authoritative even on a sampled turn.
	clear_extraction()
	var center_index := pixel_index(Vector2.ZERO)
	var original_center_water: float = soil.water_values[center_index]
	soil.water_values[center_index] = 0.2
	soil.water_coverage_total += 0.2 - original_center_water
	apply_stroke(turn_start, turn_finish, Vector3.RIGHT, Vector3.FORWARD)
	check(absf(extracted_at(Vector2.ZERO) - 0.2) < 0.0001, "Turn extraction is capped by water present in the shared mask")
	var caps_hold := true
	for i in soil.extraction_values.size():
		if soil.extraction_values[i] > soil.water_values[i] + 0.000001:
			caps_hold = false
			break
	check(caps_hold, "No rotated footprint can extract more water than was applied")
	soil.water_coverage_total += original_center_water - soil.water_values[center_index]
	soil.water_values[center_index] = original_center_water

	# Three-argument production calls must remain identical to the original
	# axis-aligned painter, including feather weights and extraction totals.
	clear_extraction()
	var legacy_from := Vector3(-0.72, RUG_Y, -0.31)
	var legacy_to := Vector3(0.63, RUG_Y, 0.27)
	soil.apply_squeegee_stroke(legacy_from, legacy_to, STROKE_SECONDS)
	var default_mask: PackedFloat32Array = soil.extraction_values.duplicate()
	var default_total: float = soil.extraction_coverage_total
	clear_extraction()
	soil._paint_wet_stroke(legacy_from, legacy_to, STROKE_SECONDS, Vector2(0.34, 0.075), false)
	check(max_array_difference(default_mask, soil.extraction_values) == 0.0, "Default API preserves the original axis-aligned footprint exactly")
	check(default_total == soil.extraction_coverage_total, "Default API preserves original extraction accounting")

	soil.queue_free()
	rug.queue_free()
	print("ROTATED SQUEEGEE VERIFIED: ", checks, " checks, ", failures, " failures; orientation, turn sweep, gates, caps and legacy behavior.")
	quit(1 if failures else 0)
