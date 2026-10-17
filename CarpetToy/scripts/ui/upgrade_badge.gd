extends TextureRect
## A quiet affordability cue. It never captures taps intended for the upgrade.

const BADGE_TEXTURE: Texture2D = preload("res://assets/ui/room_upgrades/upgrade_available.svg")
const DEFAULT_SIZE := Vector2(26.0, 26.0)

var available: bool = false
var _visibility_tween: Tween


func _init() -> void:
	texture = BADGE_TEXTURE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = DEFAULT_SIZE
	size = DEFAULT_SIZE
	scale = Vector2.ZERO
	visible = false
	resized.connect(_center_pivot)
	_center_pivot()


func _ready() -> void:
	_center_pivot()
	# A state supplied before add_child is applied immediately on first ready.
	_apply_without_animation()


func _exit_tree() -> void:
	_stop_tween()
	_apply_without_animation()


func set_available(value: bool) -> void:
	if available == value:
		return
	available = value
	_stop_tween()
	_center_pivot()
	if not is_node_ready() or not is_inside_tree():
		_apply_without_animation()
		return
	_visibility_tween = create_tween()
	if available:
		if not visible:
			scale = Vector2.ZERO
		show()
		_visibility_tween.tween_property(self, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_visibility_tween.tween_property(self, "scale", Vector2.ZERO, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_visibility_tween.tween_callback(_hide_if_unavailable)


func _center_pivot() -> void:
	pivot_offset = size * 0.5


func _stop_tween() -> void:
	if _visibility_tween != null and _visibility_tween.is_valid():
		_visibility_tween.kill()
	_visibility_tween = null


func _apply_without_animation() -> void:
	visible = available
	scale = Vector2.ONE if available else Vector2.ZERO


func _hide_if_unavailable() -> void:
	if not available:
		hide()
