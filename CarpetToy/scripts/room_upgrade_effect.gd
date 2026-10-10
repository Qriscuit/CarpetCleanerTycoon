extends Node3D
## A bounded, reusable success pulse. Time is driven by the room so focus pauses
## both the mesh motion and shader wave, without Godot's global shader TIME.
const GLOW_SHADER = preload("res://scripts/room_upgrade_effect.gdshader")
var ring: MeshInstance3D
var pillar: MeshInstance3D
var ring_material: ShaderMaterial
var pillar_material: ShaderMaterial
var radius := 0.3
var height := 0.9
var phase := 0.0
var opacity := 0.0
var _phase_origin := 0.0
var _start_opacity := 0.0
var _start_pillar_scale := Vector3.ONE
var _start_ring_scale := Vector3.ONE
var _retriggered := false

func _ready() -> void:
	var ring_mesh := TorusMesh.new()
	# Constant world width reads clearly on a pot without a thick window halo.
	ring_mesh.inner_radius = 1.0 - 0.012 / radius
	ring_mesh.outer_radius = 1.0 + 0.012 / radius
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 6
	ring = MeshInstance3D.new()
	ring.name = "WhiteFootprintRing"
	ring.mesh = ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_material = ShaderMaterial.new()
	ring_material.shader = GLOW_SHADER
	ring_material.set_shader_parameter("ring_mode", true)
	ring_material.render_priority = 1
	ring.material_override = ring_material
	add_child(ring)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	cylinder.radial_segments = 48
	cylinder.rings = 8
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	pillar = MeshInstance3D.new()
	pillar.name = "FadingWhitePillar"
	pillar.mesh = cylinder
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pillar_material = ShaderMaterial.new()
	pillar_material.shader = GLOW_SHADER
	pillar.material_override = pillar_material
	add_child(pillar)
	hide()
	set_process(false)

func start(world_anchor: Vector3, footprint_radius: float, pillar_height: float) -> void:
	# World units keep the glow round despite the diorama's decorative x/z scale.
	_retriggered = visible
	_phase_origin = phase if _retriggered else 0.0
	_start_opacity = opacity if _retriggered else 0.0
	_start_pillar_scale = pillar.scale
	_start_ring_scale = ring.scale
	global_transform = Transform3D(Basis.IDENTITY, world_anchor)
	radius = footprint_radius
	height = pillar_height
	show()
	update_phase(0.0)

func update_phase(value: float) -> void:
	var elapsed := clampf(value, 0.0, 1.0)
	# Preserve the shader wave and current brightness through another purchase.
	# Wrapping the clock at four preserves an identical, bounded wave position.
	phase = fposmod(_phase_origin + elapsed, 4.0)
	opacity = lerpf(_start_opacity, 1.0, smoothstep(0.0, 0.10, elapsed)) * (1.0 - smoothstep(0.60, 1.0, elapsed))
	var wave := sin(phase * TAU * 1.5)
	var width := radius * (1.0 + 0.045 * wave)
	var rise := height * ((1.0 if _retriggered else 0.94 + 0.06 * smoothstep(0.0, 0.25, elapsed)) + 0.025 * wave)
	var pillar_scale := Vector3(width, rise, width)
	var ring_scale := Vector3.ONE * radius * ((1.02 if _retriggered else 0.92 + 0.18 * elapsed) + 0.03 * wave)
	if _retriggered:
		var blend := smoothstep(0.0, 0.12, elapsed)
		pillar_scale = _start_pillar_scale.lerp(pillar_scale, blend)
		ring_scale = _start_ring_scale.lerp(ring_scale, blend)
	pillar.scale = pillar_scale
	pillar.position.y = pillar_scale.y * 0.5
	ring.scale = ring_scale
	ring.position.y = 0.014
	for material: ShaderMaterial in [ring_material, pillar_material]:
		material.set_shader_parameter("opacity", opacity)
		material.set_shader_parameter("phase", phase)

func stop() -> void:
	update_phase(1.0)
	hide()
