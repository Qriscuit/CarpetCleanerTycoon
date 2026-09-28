extends RefCounted
## Fit the same playable rug into a HUD-safe rectangle in either camera view.
## All coordinates are world/viewport units; drag input still raycasts the rug.

const RUG_CENTER := Vector3(0.0, 0.067, 0.0)
const TOP_CLEARANCE := AABB(Vector3(-1.5, 0.067, -2.1), Vector3(3.0, 0.0, 4.2))
const ANGLED_CLEARANCE := AABB(Vector3(-1.25, 0.0, -1.85), Vector3(2.5, 0.70, 3.7))
const ANGLED_EYE := Vector3(1.65, 2.07, 2.5)


static func frame(camera: Camera3D, viewport_size: Vector2, space: Rect2, oblique: bool) -> void:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0 or space.size.x <= 0.0 or space.size.y <= 0.0:
		return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	# An exact top-down basis avoids look_at's parallel-up singularity.
	var view_basis := Basis(Vector3.RIGHT, -PI * 0.5)
	if oblique:
		view_basis = Basis.looking_at(-ANGLED_EYE.normalized(), Vector3.UP)
	var bounds := ANGLED_CLEARANCE if oblique else TOP_CLEARANCE
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for index in 8:
		var point := bounds.get_endpoint(index) - RUG_CENTER
		var projected := Vector2(view_basis.x.dot(point), view_basis.y.dot(point))
		low = low.min(projected)
		high = high.max(projected)
	var extent := high - low
	camera.size = maxf(extent.x * viewport_size.y / space.size.x, extent.y * viewport_size.y / space.size.y)
	var projected_center := (low + high) * 0.5
	# Move parallel to the image plane, not along the ground: this keeps the
	# fit exact for asymmetric HUD layouts and both phone orientations.
	var screen_offset := Vector2(viewport_size.x * 0.5 - space.get_center().x, space.get_center().y - viewport_size.y * 0.5) * camera.size / viewport_size.y
	var center := RUG_CENTER + view_basis.x * (projected_center.x + screen_offset.x) + view_basis.y * (projected_center.y + screen_offset.y)
	camera.global_transform = Transform3D(view_basis, center + view_basis.z * 9.0)
