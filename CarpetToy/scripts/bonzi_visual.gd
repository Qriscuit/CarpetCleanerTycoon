extends Node3D
## Bonzi's editable mesh art faces local -Z. Place its root on the rug surface.
## Twelve reusable dust puffs keep the brush swirl bounded on mobile hardware.

const DUST_COUNT := 12
const DUST_PER_BRUSH := 6
const BRUSH_SPIN_SPEED := 5.2
const DUST_CYCLE_SPEED := 0.9

@onready var left_motor: Node3D = $LeftBrushMotor
@onready var right_motor: Node3D = $RightBrushMotor
@onready var dust: MultiMeshInstance3D = $DustSwirls
@onready var body: Node3D = $Body

var cleaning := false
var paused := false
var animation_time := 0.0
var _dust_mesh: MultiMesh
var _body_height := 0.0

func _ready() -> void:
	_body_height = body.position.y
	# This is the only allocation of the puff pool; subsequent updates reuse it.
	# Allocate the color/transform layout before the instance buffer. Duplicating
	# an authored empty pool can deserialize its buffer in the wrong order.
	var authored_pool := dust.multimesh
	_dust_mesh = MultiMesh.new()
	_dust_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_dust_mesh.use_colors = true
	_dust_mesh.mesh = authored_pool.mesh
	_dust_mesh.custom_aabb = authored_pool.custom_aabb
	_dust_mesh.instance_count = DUST_COUNT
	_dust_mesh.visible_instance_count = 0
	dust.multimesh = _dust_mesh
	dust.visible = false
	_sync_animation_state()

func set_cleaning(active: bool) -> void:
	cleaning = active
	_sync_animation_state()

func set_paused(active: bool) -> void:
	paused = active
	_sync_animation_state()

func _sync_animation_state() -> void:
	set_process(cleaning and not paused)
	if _dust_mesh == null:
		return
	dust.visible = cleaning and not paused
	_dust_mesh.visible_instance_count = DUST_COUNT if cleaning and not paused else 0
	if not cleaning:
		body.position.y = _body_height

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	animation_time = fposmod(animation_time + delta, 120.0)
	left_motor.rotation.y = fposmod(left_motor.rotation.y + delta * BRUSH_SPIN_SPEED, TAU)
	right_motor.rotation.y = fposmod(right_motor.rotation.y - delta * BRUSH_SPIN_SPEED, TAU)
	body.position.y = _body_height + sin(animation_time * 7.0) * 0.0012
	for index: int in range(DUST_COUNT):
		var brush_index := 0 if index < DUST_PER_BRUSH else 1
		var slot := index % DUST_PER_BRUSH
		var direction := 1.0 if brush_index == 0 else -1.0
		var age := fposmod(animation_time * DUST_CYCLE_SPEED + float(slot) / DUST_PER_BRUSH, 1.0)
		var angle := direction * (age * TAU * 0.8 + float(slot) * 0.34)
		var orbit := lerpf(0.028, 0.106, age)
		var center_x := -0.124 if brush_index == 0 else 0.124
		var point := Vector3(center_x + cos(angle) * orbit, 0.022 + age * 0.035, -0.205 + sin(angle) * orbit)
		var puff_size := lerpf(0.006, 0.023, age)
		var puff_basis := Basis.from_scale(Vector3(puff_size * 1.2, puff_size * 0.65, puff_size))
		_dust_mesh.set_instance_transform(index, Transform3D(puff_basis, point))
		var opacity := 0.55 * smoothstep(0.0, 0.16, age) * pow(1.0 - age, 1.6)
		_dust_mesh.set_instance_color(index, Color(0.77, 0.72, 0.61, opacity))
