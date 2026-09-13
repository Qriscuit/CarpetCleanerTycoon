extends RefCounted
## Local X/Z silhouette, matching build_carpet.py's outer binding and 26 tassels.
var polygons: Array[PackedVector2Array] = []
var bounds: Array[Rect2] = []

func _init() -> void:
	add_outline(Vector2(1.0, 1.5), 0.17, 10, Vector2.ZERO, 0.0)
	for side in [-1.0, 1.0]:
		for i in 13:
			var length := 0.165 + 0.013 * cos(i * 1.7)
			add_outline(Vector2(0.039, length / 2.0), 0.036, 3, Vector2((i - 6) * 0.134, side * (1.476 + length / 2.0)), sin(i * 2.2) * 0.045)

func add_outline(half: Vector2, radius: float, steps: int, center: Vector2, angle: float) -> void:
	var polygon := PackedVector2Array()
	for corner in 4:
		var sign_x := 1.0 if corner == 0 or corner == 3 else -1.0
		var sign_y := 1.0 if corner < 2 else -1.0
		var arc_center := Vector2(sign_x * (half.x - radius), sign_y * (half.y - radius))
		for step in steps + 1:
			var theta := deg_to_rad(corner * 90.0 + step * 90.0 / steps)
			var p := (arc_center + Vector2(cos(theta), sin(theta)) * radius).rotated(angle) + center
			polygon.append(Vector2(p.x, -p.y)) # Blender XY to Godot XZ.
	polygons.append(polygon)
	bounds.append(polygon_bounds(polygon))

static func polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	var result := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		result = result.expand(p)
	return result

func contains_point(point: Vector2) -> bool:
	for i in polygons.size():
		if bounds[i].grow(0.0001).has_point(point) and Geometry2D.is_point_in_polygon(point, polygons[i]):
			return true
	return false

func overlaps_polygon(polygon: PackedVector2Array) -> bool:
	var box := polygon_bounds(polygon)
	# Most clumps are fully within the rug's flat central area.
	if Rect2(-0.83, -1.33, 1.66, 2.66).encloses(box):
		return true
	for i in polygons.size():
		if bounds[i].intersects(box, true) and not Geometry2D.intersect_polygons(polygon, polygons[i]).is_empty():
			return true
	return false

func circle_is_outside(point: Vector2, radius: float) -> bool:
	if contains_point(point):
		return false
	for i in polygons.size():
		if not bounds[i].grow(radius + 0.0001).has_point(point):
			continue
		var polygon := polygons[i]
		for j in polygon.size():
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[j], polygon[(j + 1) % polygon.size()])) <= radius:
				return false
	return true
