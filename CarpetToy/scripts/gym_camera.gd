extends RefCounted
## Fit the same playable rug into a HUD-safe rectangle in either camera view.
## All coordinates are world/viewport units; drag input still raycasts the rug.

const RUG_CENTER := Vector3(0.0, 0.067, 0.0)
const TOP_CLEARANCE := AABB(Vector3(-1.5, 0.067, -2.1), Vector3(3.0, 0.0, 4.2))
const ANGLED_CLEARANCE := AABB(Vector3(-1.25, 0.0, -1.85), Vector3(2.5, 0.70, 3.7))
const ANGLED_EYE := Vector3(1.65, 2.07, 2.5)
const WORKSHOP_PITCH_FROM_TOP := 20.0
const WORKSHOP_YAW_DEGREES := 0.0
# Closed-room geometry across all four upgrade tiers, with a small edge margin.
# Open casement tips have their own departure fit and do not shrink cleaning.
const WORKSHOP_CLEARANCE := AABB(Vector3(-1.94, -0.24, -2.51), Vector3(3.88, 2.05, 4.78))
const DEPARTURE_CLEARANCE := AABB(Vector3(-1.94, -0.24, -3.38), Vector3(3.88, 2.05, 5.65))


static func frame(camera: Camera3D, viewport_size: Vector2, space: Rect2, oblique: bool) -> void:
	# An exact top-down basis avoids look_at's parallel-up singularity.
	var view_basis := Basis(Vector3.RIGHT, -PI * 0.5)
	if oblique:
		view_basis = Basis.looking_at(-ANGLED_EYE.normalized(), Vector3.UP)
	_frame_bounds(camera, viewport_size, space, view_basis, ANGLED_CLEARANCE if oblique else TOP_CLEARANCE)


static func workshop_basis(pitch_from_top: float = WORKSHOP_PITCH_FROM_TOP, yaw_degrees: float = WORKSHOP_YAW_DEGREES) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(yaw_degrees)) * Basis(Vector3.RIGHT, deg_to_rad(-90.0 + pitch_from_top))


static func frame_workshop(camera: Camera3D, viewport_size: Vector2, space: Rect2, bounds: AABB = WORKSHOP_CLEARANCE, pitch_from_top: float = WORKSHOP_PITCH_FROM_TOP, yaw_degrees: float = WORKSHOP_YAW_DEGREES) -> void:
	# Show Bonzi's body and rotating brushes while keeping the carpet readable.
	# Fit every accessory, including its tallest upgrade, at the same room angle.
	var view_basis := workshop_basis(pitch_from_top, yaw_degrees)
	_frame_bounds(camera, viewport_size, space, view_basis, bounds)


static func frame_reveal(camera: Camera3D, viewport_size: Vector2, space: Rect2, workshop_size: float, pitch_from_top: float = WORKSHOP_PITCH_FROM_TOP, yaw_degrees: float = WORKSHOP_YAW_DEGREES) -> void:
	# A modest ten-percent push keeps the whole design and fringe in view,
	# without changing the room's angle or snapping into a top-down closeup.
	var view_basis := workshop_basis(pitch_from_top, yaw_degrees)
	var rug_bounds := AABB(Vector3(-1.10, 0.067, -1.76), Vector3(2.20, 0.0, 3.52))
	_frame_bounds(camera, viewport_size, space, view_basis, rug_bounds)
	var fit_size := camera.size
	camera.size = maxf(workshop_size * 0.90, fit_size)
	var offset := Vector2(viewport_size.x * 0.5 - space.get_center().x, space.get_center().y - viewport_size.y * 0.5) * camera.size / viewport_size.y
	camera.global_transform = Transform3D(view_basis, RUG_CENTER + view_basis.x * offset.x + view_basis.y * offset.y + view_basis.z * 9.0)


static func frame_departure(camera: Camera3D, viewport_size: Vector2, space: Rect2, workshop_size: float, bounds: AABB = DEPARTURE_CLEARANCE, pitch_from_top: float = WORKSHOP_PITCH_FROM_TOP, yaw_degrees: float = WORKSHOP_YAW_DEGREES) -> void:
	var view_basis := workshop_basis(pitch_from_top, yaw_degrees)
	_frame_bounds(camera, viewport_size, space, view_basis, bounds)
	var fitted_size := camera.size
	# Keep the pullback broad while shifting just enough to include the tips of
	# the open casements. The cleaning camera never pays for this extra margin.
	camera.size = maxf(workshop_size, fitted_size)
	var center := bounds.get_center()
	var projected_center := Vector2(view_basis.x.dot(center - RUG_CENTER), view_basis.y.dot(center - RUG_CENTER))
	var offset := Vector2(viewport_size.x * 0.5 - space.get_center().x, space.get_center().y - viewport_size.y * 0.5) * camera.size / viewport_size.y
	camera.global_transform = Transform3D(view_basis, RUG_CENTER + view_basis.x * (projected_center.x + offset.x) + view_basis.y * (projected_center.y + offset.y) + view_basis.z * 9.0)


static func _frame_bounds(camera: Camera3D, viewport_size: Vector2, space: Rect2, view_basis: Basis, bounds: AABB) -> void:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0 or space.size.x <= 0.0 or space.size.y <= 0.0:
		return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.h_offset = 0.0
	camera.v_offset = 0.0
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
