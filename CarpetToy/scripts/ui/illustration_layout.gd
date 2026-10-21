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

func _ready() -> void:
	if not resized.is_connected(_fit_artwork):
		resized.connect(_fit_artwork)
	_fit_artwork()
	set_process(false)


func _fit_artwork() -> void:
	var artwork := get_node_or_null("Artwork") as Node2D
	if artwork == null:
		return
	var unit := maxf(0.0, minf(size.x / reference_size.x, size.y / reference_size.y))
	artwork.scale = Vector2.ONE * unit
	artwork.position = (size - reference_size * unit) * 0.5
