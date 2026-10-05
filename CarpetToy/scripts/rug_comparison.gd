extends RefCounted
## A bounded render-only record of this rug on arrival, never a gameplay restore.
var coverage: ImageTexture
var wetness: ImageTexture
var extraction: ImageTexture
var before_buffer := PackedFloat32Array()
var before_count := 0
var before_visible := true
var before_dust_strengths: Array[float] = []
var before_wash_cycle := 0
var _after_wash_cycle := 0
var available := false
var showing := false
var label := "Before"
var _after_buffer := PackedFloat32Array()
var _after_count := 0
var _after_visible := true
var _after_dust_strengths: Array[float] = []

func capture(soil: Node, resumed: bool = false) -> void:
	set_before(soil, false)
	if coverage == null:
		coverage = ImageTexture.create_from_image(soil.mask)
		wetness = ImageTexture.create_from_image(soil.wet_mask)
		extraction = ImageTexture.create_from_image(soil.extraction_mask)
	else:
		coverage.update(soil.mask)
		wetness.update(soil.wet_mask)
		extraction.update(soil.extraction_mask)
	soil.refresh_visible_clumps()
	before_buffer = soil.batch.buffer.duplicate()
	before_count = soil.batch.visible_instance_count
	before_visible = soil.batch_node.visible
	before_wash_cycle = soil.wash_cycle
	before_dust_strengths.clear()
	for material: ShaderMaterial in soil.surface_materials:
		before_dust_strengths.append(float(material.get_shader_parameter("dust_strength")))
	label = "Before this session" if resumed else "Before"
	available = true

func set_before(soil: Node, enabled: bool) -> void:
	if enabled == showing or (enabled and not available): return
	if enabled:
		_after_buffer = soil.batch.buffer.duplicate()
		_after_count = soil.batch.visible_instance_count
		_after_visible = soil.batch_node.visible
		_after_wash_cycle = soil.wash_cycle
		_after_dust_strengths.clear()
		for material: ShaderMaterial in soil.surface_materials:
			_after_dust_strengths.append(float(material.get_shader_parameter("dust_strength")))
		soil.batch.buffer = before_buffer
		soil.batch.visible_instance_count = before_count
		soil.batch_node.visible = before_visible
	else:
		soil.batch.buffer = _after_buffer
		soil.batch.visible_instance_count = _after_count
		soil.batch_node.visible = _after_visible
	for index in soil.surface_materials.size():
		var material: ShaderMaterial = soil.surface_materials[index]
		material.set_shader_parameter("coverage", coverage if enabled else soil.mask_texture)
		material.set_shader_parameter("wetness", wetness if enabled else soil.wet_texture)
		material.set_shader_parameter("wash_cycle", before_wash_cycle if enabled else _after_wash_cycle)
		material.set_shader_parameter("extraction", extraction if enabled else soil.extraction_texture)
		material.set_shader_parameter("dust_strength", before_dust_strengths[index] if enabled else _after_dust_strengths[index])
	showing = enabled
