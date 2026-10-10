extends CanvasLayer
## A brief soft focus over the room during the completion camera move.
## The HUD stays sharp: its CanvasLayers render after this world-only layer.

const FOCUS_SHADER := preload("res://scripts/completion_focus.gdshader")

@export_range(0.0, 12.0, 0.25) var max_radius_pixels := 4.0:
	set(value):
		max_radius_pixels = clampf(value, 0.0, 12.0)
		if _focus_material != null:
			_focus_material.set_shader_parameter("max_radius_pixels", max_radius_pixels)

var blur_amount := 0.0
var _focus_material: ShaderMaterial
var _overlay: ColorRect


func _init() -> void:
	layer = -1
	visible = false


func _ready() -> void:
	_focus_material = ShaderMaterial.new()
	_focus_material.shader = FOCUS_SHADER
	_focus_material.set_shader_parameter("max_radius_pixels", max_radius_pixels)
	_overlay = ColorRect.new()
	_overlay.name = "WorldSoftFocus"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.focus_mode = Control.FOCUS_NONE
	_overlay.material = _focus_material
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_blur_amount(blur_amount)


func set_blur_amount(amount: float) -> void:
	blur_amount = clampf(amount, 0.0, 1.0)
	if _focus_material != null:
		_focus_material.set_shader_parameter("blur_amount", blur_amount)
	# A hidden screen-reading material needs no screen copy or blur mipmaps.
	visible = blur_amount > 0.001 and max_radius_pixels > 0.0


func reset() -> void:
	set_blur_amount(0.0)
