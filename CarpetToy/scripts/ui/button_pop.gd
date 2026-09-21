extends RefCounted
## Shared mouse, keyboard and real-touch feedback without moving layout anchors.
static func bind(button: BaseButton) -> void:
	button.button_down.connect(press.bind(button))
	button.button_up.connect(release.bind(button))
	button.mouse_exited.connect(reset.bind(button))
	button.focus_exited.connect(reset.bind(button))

static func _tween(button: Control) -> Tween:
	var previous: Tween = button.get_meta("pop_tween") if button.has_meta("pop_tween") else null
	if previous != null and previous.is_valid(): previous.kill()
	button.pivot_offset = button.size * .5
	var tween := button.create_tween()
	button.set_meta("pop_tween", tween)
	return tween

static func press(button: BaseButton) -> void:
	if button.disabled: return
	_tween(button).tween_property(button, "scale", Vector2.ONE*.94, .07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

static func release(button: BaseButton) -> void:
	var tween := _tween(button)
	tween.tween_property(button, "scale", Vector2.ONE*1.035, .10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE, .12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

static func reset(button: BaseButton) -> void:
	if not button.is_visible_in_tree():
		var previous: Tween = button.get_meta("pop_tween") if button.has_meta("pop_tween") else null
		if previous != null and previous.is_valid(): previous.kill()
		button.scale = Vector2.ONE
		return
	_tween(button).tween_property(button, "scale", Vector2.ONE, .10)
