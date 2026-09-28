extends RefCounted
## Distance-sensitive intent filter shared by the blade, paint footprint and jet.
## Keep the last heading at rest; reject tiny jitter, never invent lateral speed.
const RESPONSE_SECONDS := 0.070
const MAX_TURN_SPEED := 14.0
const MAX_SPEED := 2.5

var heading := Vector3.FORWARD
var speed := 0.0
var tracking := false
var velocity := Vector3.ZERO

func reset() -> void:
	heading = Vector3.FORWARD
	end_stroke()

func end_stroke() -> void:
	tracking = false
	speed = 0.0
	velocity = Vector3.ZERO

func update(displacement: Vector3, elapsed: float) -> void:
	displacement.y = 0.0
	if displacement.length_squared() <= 0.00001: return
	var seconds := clampf(elapsed if elapsed > 0.0 else 1.0 / 60.0, 1.0 / 240.0, 0.08)
	var input_velocity := (displacement / seconds).limit_length(MAX_SPEED)
	if not tracking:
		heading = displacement.normalized()
		velocity = input_velocity
		speed = input_velocity.length()
		tracking = true
		return
	var response := 1.0 - exp(-seconds / RESPONSE_SECONDS)
	velocity = velocity.lerp(input_velocity, response)
	speed = lerpf(speed, input_velocity.length(), response)
	if velocity.length_squared() < 0.000025: return
	var target := velocity.normalized()
	var angle := heading.signed_angle_to(target, Vector3.UP)
	# A stable turn rate prevents reversal noise or a single tiny event from
	# spinning the blade (and the entire stream) through an arbitrary angle.
	heading = heading.rotated(Vector3.UP, clampf(angle, -MAX_TURN_SPEED * seconds, MAX_TURN_SPEED * seconds)).normalized()

func projected_half_extents(half: Vector2) -> Vector2:
	var across := Vector3.UP.cross(heading)
	return Vector2(absf(across.x) * half.x + absf(heading.x) * half.y,
		absf(across.z) * half.x + absf(heading.z) * half.y)
