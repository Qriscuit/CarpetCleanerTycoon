extends Node3D
## A slow, reusable serpentine route. Only the workshop authorizes cleaning.
const VISUAL_SCENE := preload("res://scenes/tools/bonzi_cleaner.tscn")
const SPEED := 0.12
const TURN_SPEED := 2.0
const BRUSH_RADIUS := 0.29
const CLEAN_RATE := 1.4
const CLEAN_INTERVAL := 0.05
enum RoutePhase { TURN, MOVE }

var soil: Node
var visual: Node3D
var running := false
var route_phase := RoutePhase.MOVE
var completed_sweeps := 0
var travelled_distance := 0.0
var _points := PackedVector2Array()
var _point := Vector2.ZERO
var _target_index := 1
var _route_direction := 1
var _heading := 0.0
var _clean_elapsed := 0.0
var _last_stamp := Vector2.ZERO

func setup(dirt: Node) -> void:
	soil = dirt
	visual = VISUAL_SCENE.instantiate()
	add_child(visual)
	for lane in 5:
		var x := lerpf(-0.78, 0.78, float(lane) / 4.0)
		var start_z := 1.43 if lane % 2 == 0 else -1.43
		_points.append(Vector2(x, start_z))
		_points.append(Vector2(x, -start_z))
	reset_route()
	hide()

func reset_route() -> void:
	set_running(false)
	_point = _points[0]
	_target_index = 1
	_route_direction = 1
	_heading = 0.0
	_clean_elapsed = 0.0
	_last_stamp = _point
	completed_sweeps = 0
	travelled_distance = 0.0
	_apply_pose()

func set_running(active: bool) -> void:
	if running == active:
		return
	running = active
	_clean_elapsed = 0.0
	_last_stamp = _point
	if is_instance_valid(visual):
		visual.set_cleaning(active)

func advance(delta: float) -> void:
	if not running or not is_instance_valid(soil):
		return
	# A stalled frame must never jump across the carpet or deposit a long burst.
	var seconds := clampf(delta, 0.0, 0.1)
	var target := _points[_target_index]
	var direction := target - _point
	var wanted_heading := atan2(-direction.x, -direction.y)
	var turn := wrapf(wanted_heading - _heading, -PI, PI)
	if absf(turn) > 0.025:
		route_phase = RoutePhase.TURN
		_heading += clampf(turn, -TURN_SPEED * seconds, TURN_SPEED * seconds)
	else:
		route_phase = RoutePhase.MOVE
		_heading = wanted_heading
		var next := _point.move_toward(target, SPEED * seconds)
		travelled_distance += _point.distance_to(next)
		_point = next
		if _point.distance_squared_to(target) < 0.000001:
			_target_index += _route_direction
			if _target_index == _points.size() or _target_index < 0:
				completed_sweeps += 1
				_route_direction *= -1
				_target_index += _route_direction * 2
	_apply_pose()
	_clean_elapsed += seconds
	if _clean_elapsed >= CLEAN_INTERVAL:
		var previous: Vector3 = soil.rug_node.to_global(Vector3(_last_stamp.x, soil.RUG_Y, _last_stamp.y))
		var current: Vector3 = soil.rug_node.to_global(Vector3(_point.x, soil.RUG_Y, _point.y))
		soil.apply_bonzi_stroke(previous, current, _clean_elapsed, BRUSH_RADIUS, CLEAN_RATE)
		_last_stamp = _point
		_clean_elapsed = 0.0

func _apply_pose() -> void:
	if not is_instance_valid(soil) or not is_inside_tree():
		return
	global_transform = soil.rug_node.global_transform * Transform3D(Basis(Vector3.UP, _heading), Vector3(_point.x, soil.RUG_Y, _point.y))
