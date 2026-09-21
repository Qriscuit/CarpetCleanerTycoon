@tool
extends Control
## Resolution-independent, quiet background; no baked screen-sized artwork.

func _ready() -> void:
	resized.connect(queue_redraw)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("acdff7"))
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
