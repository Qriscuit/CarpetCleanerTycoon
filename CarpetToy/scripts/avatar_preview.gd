extends Control
## One small studio render. The viewport sleeps between requested frames.
const Catalog = preload("res://scripts/avatar_catalog.gd")
const FRAME_SECONDS := 1.0 / 30.0
const MAX_RENDER_EDGE := 768
const REST_ANGLE := -0.32
const ROTATION_SPEED := 0.24
var active := false
var focused := true
var motion_enabled := true
var frame_elapsed := 0.0
var body_materials: Array[StandardMaterial3D] = []
var model_height := 2.5
var model_radius := 0.9
var model_center := Vector3(0, 1.2, 0)
var dragging := false
var resume_at := 0
var paused := false
var frame_pending := false
var render_dirty := false
var scheduled_frame_count := 0
var rendered_frame_count := 0
var last_render_usec := 0

func _ready() -> void:
	$Picture.texture = $AvatarViewport.get_texture()
	for mesh: MeshInstance3D in $AvatarViewport/Studio/Turntable/Avatar.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			var material := source.duplicate() as StandardMaterial3D if source != null else StandardMaterial3D.new()
			material.roughness = 0.7
			mesh.set_surface_override_material(surface, material)
			body_materials.append(material)
	_measure_model()
	$AvatarViewport/Studio/Turntable.rotation.y = REST_ANGLE
	resized.connect(_resize_render)
	set_process(false)
	_resize_render()

func _measure_model() -> void:
	var bounds := AABB()
	var found := false
	var pivot: Node3D = $AvatarViewport/Studio/Turntable
	for mesh: MeshInstance3D in pivot.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var transform := pivot.global_transform.affine_inverse() * mesh.global_transform
		for corner in 8:
			var point := transform * mesh.get_aabb().get_endpoint(corner)
			if found: bounds = bounds.expand(point)
			else:
				bounds = AABB(point, Vector3.ZERO)
				found = true
	if found:
		model_height = maxf(bounds.size.y, 0.1)
		model_radius = maxf(Vector2(bounds.position.x, bounds.position.z).length(), Vector2(bounds.end.x, bounds.end.z).length())
		model_center = Vector3(0, bounds.get_center().y, 0)
	var camera: Camera3D = $AvatarViewport/Studio/Camera
	camera.position = model_center + Vector3(0, model_height * 0.10, -8)
	camera.look_at(model_center)

func _resize_render() -> void:
	if not is_node_ready() or size.x < 1 or size.y < 1: return
	var pixels := size * 1.5
	pixels *= minf(1.0, float(MAX_RENDER_EDGE) / maxf(pixels.x, pixels.y))
	var dimensions := Vector2i(maxi(1, roundi(pixels.x)), maxi(1, roundi(pixels.y)))
	if $AvatarViewport.size != dimensions: $AvatarViewport.size = dimensions
	var aspect := float(dimensions.x) / maxf(float(dimensions.y), 1.0)
	$AvatarViewport/Studio/Camera.size = maxf(model_height * 1.22, model_radius * 2.28 / maxf(aspect, 0.1))
	request_render()

func set_appearance(appearance: Dictionary) -> void:
	var color := Catalog.color_for(str(appearance.get("color_id", "orange")))
	for material in body_materials: material.albedo_color = color
	$AvatarViewport/Studio/Turntable/PirateHat.visible = str(appearance.get("hat_id", "none")) == "pirate"
	$AvatarViewport/Studio/Turntable/Beanie.visible = str(appearance.get("hat_id", "none")) == "beanie"
	request_render()

func set_active(enabled: bool) -> void:
	active = enabled
	if not enabled:
		dragging = false
		render_dirty = false
	frame_elapsed = 0.0
	_sync_activity()
	if enabled: request_render()

func set_focused(enabled: bool) -> void:
	focused = enabled
	frame_elapsed = 0.0
	_sync_activity()
	if enabled: request_render()

func set_motion(enabled: bool) -> void:
	motion_enabled = enabled
	if not enabled: $AvatarViewport/Studio/Turntable.rotation.y = REST_ANGLE
	_sync_activity()
	request_render()

func _sync_activity() -> void:
	set_process(active and focused and (motion_enabled or render_dirty) and not paused)
	if not active or not focused or paused:
		$AvatarViewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func request_render() -> void:
	if not active or not focused or paused: return
	# Every source shares one budget. Millisecond deadlines can turn a30Hz
	# preview into20Hz on a60Hz display by missing every second frame.
	render_dirty = true
	_sync_activity()

func _draw_frame() -> void:
	if not active or not focused or paused: return
	scheduled_frame_count += 1
	$AvatarViewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not frame_pending:
		frame_pending = true
		RenderingServer.frame_post_draw.connect(_finish_frame, CONNECT_ONE_SHOT)

func _finish_frame() -> void:
	frame_pending = false
	rendered_frame_count += 1
	last_render_usec = Time.get_ticks_usec()
	$AvatarViewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func begin_drag() -> void:
	dragging = true
	frame_elapsed = 0.0

func drag_by(horizontal_pixels: float) -> void:
	$AvatarViewport/Studio/Turntable.rotation.y -= horizontal_pixels * 0.014
	request_render()

func end_drag() -> void:
	if not dragging: return
	dragging = false
	resume_at = Time.get_ticks_msec() + 2000
	frame_elapsed = 0.0

func _notification(what: int) -> void:
	if not is_node_ready(): return
	if what == NOTIFICATION_PAUSED:
		paused = true
		_sync_activity()
	elif what == NOTIFICATION_UNPAUSED:
		paused = false
		_sync_activity()
		request_render()

func _process(delta: float) -> void:
	frame_elapsed += minf(delta, 0.1)
	if frame_elapsed + 0.000001 < FRAME_SECONDS: return
	var steps := floori((frame_elapsed + 0.000001) / FRAME_SECONDS)
	var step := float(steps) * FRAME_SECONDS
	frame_elapsed = maxf(frame_elapsed - step, 0.0)
	if motion_enabled and not dragging and Time.get_ticks_msec() >= resume_at:
		$AvatarViewport/Studio/Turntable.rotation.y += ROTATION_SPEED * step
		render_dirty = true
	if render_dirty:
		render_dirty = false
		_draw_frame()
	_sync_activity()
