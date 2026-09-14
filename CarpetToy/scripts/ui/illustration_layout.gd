@tool
extends Control
## Art is authored in the scene's Artwork subtree. Move, recolor, hide, or replace
## any of those nodes in Godot; this script never creates or rebuilds art.
## Only Artwork itself is scaled and centered to fit this Control's rectangle.

@export var reference_size := Vector2(200, 160):
	set(value):
		reference_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		if is_inside_tree():
			_fit_artwork()

@export var working := false:
	set(value):
		working = value
		if is_inside_tree() and not Engine.is_editor_hint():
			set_process(working and is_instance_valid(_animated_part))
			if not working and is_instance_valid(_animated_part):
				_animated_part.position = _rest_position

## Optional artwork group that gently travels while Bonzi is working.
@export_node_path("Node2D") var animation_target_path: NodePath

var _animated_part: Node2D
var _rest_position := Vector2.ZERO
var _phase := 0.0


func _ready() -> void:
	if not resized.is_connected(_fit_artwork):
		resized.connect(_fit_artwork)
	_fit_artwork()
	set_process(false)
	if Engine.is_editor_hint():
		return
	if not animation_target_path.is_empty():
		_animated_part = get_node_or_null(animation_target_path) as Node2D
	if is_instance_valid(_animated_part):
		_rest_position = _animated_part.position
		set_process(working)


func _fit_artwork() -> void:
	var artwork := get_node_or_null("Artwork") as Node2D
	if artwork == null:
		return
	var unit := maxf(0.0, minf(size.x / reference_size.x, size.y / reference_size.y))
	artwork.scale = Vector2.ONE * unit
	artwork.position = (size - reference_size * unit) * 0.5


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(_animated_part):
		return
	_phase += delta
	_animated_part.position = _rest_position + Vector2(sin(_phase * 1.6) * 7.0, sin(_phase * 3.2) * 1.4)

