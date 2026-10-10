@tool
extends Control
## Resolution-independent, quiet background; no baked screen-sized artwork.

const STORE_TOP_COLORS: Array[Color] = [
	Color("c5eafb"),
	Color("daf1e4"),
	Color("e1dffa"),
	Color("fce5d5"),
	Color("e1f4cc"),
	Color("f4dff0"),
]
const STORE_BOTTOM_COLORS: Array[Color] = [
	Color("99d4ef"),
	Color("b5ddd5"),
	Color("c9c2e9"),
	Color("f1c4b7"),
	Color("badca6"),
	Color("dcaed2"),
]

var _gradient_top: Color = STORE_TOP_COLORS[0]
var _gradient_bottom: Color = STORE_BOTTOM_COLORS[0]

func _ready() -> void:
	resized.connect(queue_redraw)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_store(id: int) -> void:
	set_store_blend(id, id, 0.0)

func set_store_blend(from_store: int, to_store: int, progress: float) -> void:
	var from_index := clampi(from_store, 1, STORE_TOP_COLORS.size()) - 1
	var to_index := clampi(to_store, 1, STORE_TOP_COLORS.size()) - 1
	var blend := clampf(progress, 0.0, 1.0)
	_gradient_top = STORE_TOP_COLORS[from_index].lerp(STORE_TOP_COLORS[to_index], blend)
	_gradient_bottom = STORE_BOTTOM_COLORS[from_index].lerp(STORE_BOTTOM_COLORS[to_index], blend)
	queue_redraw()

func _draw() -> void:
	# Vertex colors interpolate continuously across the screen. The matching
	# diagonal weights avoid a visible seam where the rectangle triangulates.
	var gradient_points := PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		size,
		Vector2(0.0, size.y),
	])
	var gradient_colors := PackedColorArray([
		_gradient_top,
		_gradient_top.lerp(_gradient_bottom, 0.18),
		_gradient_bottom,
		_gradient_top.lerp(_gradient_bottom, 0.82),
	])
	if size.x > 0.0 and size.y > 0.0:
		draw_polygon(gradient_points, gradient_colors)
	var ink := Color(1.0, 1.0, 1.0, 0.19)
	for row in range(-1, ceili(size.y / 150.0) + 1):
		for col in range(-1, ceili(size.x / 140.0) + 1):
			var p := Vector2(col * 140.0 + 32.0 + (row % 2) * 65.0, row * 150.0 + 46.0)
			var kind := posmod(row * 3 + col, 4)
			if kind == 0:
				draw_circle(p, 12.0, Color(1, 1, 1, 0.08))
				draw_arc(p, 12.0, 3.5, 5.9, 20, ink, 1.6, true)
			elif kind == 1:
				var points := PackedVector2Array([p + Vector2(0,-9), p + Vector2(3,-3), p + Vector2(9,0), p + Vector2(3,3), p + Vector2(0,9), p + Vector2(-3,3), p + Vector2(-9,0), p + Vector2(-3,-3)])
				draw_colored_polygon(points, ink)
			elif kind == 2:
				draw_arc(p, 15.0, 0.3, 1.7, 16, ink, 2.0, true)
			else:
				draw_circle(p, 3.0, ink)
