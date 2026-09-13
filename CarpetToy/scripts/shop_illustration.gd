extends Control
## Resolution-independent illustrations shared by the shop's menu cards.
## Set kind to store, bonzi, brush, blueprint, upgrade, or intake.

@export var kind: String = "store":
	set(value):
		kind = value
		queue_redraw()
@export var working: bool = false:
	set(value):
		working = value
		set_process(value)
		queue_redraw()

const INK := Color("285754")
const MINT := Color("7edca3")
const MINT_DARK := Color("47b681")
const PALE := Color("e2f4df")
const CREAM := Color("fff9e9")
const CORAL := Color("fa8c73")
const CORAL_DARK := Color("df6b59")
const GOLD := Color("f8cc65")
const BLUE := Color("b9e4ec")
const SKY := Color("e6f3ed")

var _phase: float = 0.0
var _canvas_transform := Transform2D.IDENTITY


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	set_process(working)
	queue_redraw()


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _draw() -> void:
	var design_size := Vector2(640, 320) if kind == "store" else Vector2(200, 160)
	var unit := minf(size.x / design_size.x, size.y / design_size.y)
	var offset := (size - design_size * unit) * 0.5
	_canvas_transform = Transform2D(Vector2(unit, 0), Vector2(0, unit), offset)
	draw_set_transform_matrix(_canvas_transform)
	match kind:
		"store": _store()
		"bonzi": _bonzi_card()
		"brush": _brush()
		"blueprint": _blueprint()
		"upgrade": _upgrade()
		"intake": _intake()
		_: _bonzi_card()


func _round(x: float, y: float, width: float, height: float, fill: Color,
		radius: int = 12, border: int = 3, drop: float = 0.0) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = INK
	box.set_border_width_all(border)
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	if drop > 0:
		box.shadow_color = INK
		box.shadow_size = 0
		# A second rounded shape gives a crisp pressed-toy edge.
		var shadow := box.duplicate() as StyleBoxFlat
		shadow.bg_color = INK
		draw_style_box(shadow, Rect2(x, y + drop, width, height))
	draw_style_box(box, Rect2(x, y, width, height))


func _line(from: Vector2, to: Vector2, color: Color = INK, width: float = 3.0) -> void:
	draw_line(from, to, color, width, true)
	draw_circle(from, width * 0.5, color)
	draw_circle(to, width * 0.5, color)


func _ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(48):
		var angle := TAU * float(i) / 48.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radii)
	draw_colored_polygon(points, color)


func _poly(points: PackedVector2Array, fill: Color, border: float = 3.0) -> void:
	draw_colored_polygon(points, fill)
	if border > 0:
		var edge := points.duplicate()
		edge.append(points[0])
		draw_polyline(edge, INK, border, true)


func _spark(at: Vector2, radius: float = 8.0, color: Color = GOLD) -> void:
	var inner := radius * 0.29
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(0, -radius), at + Vector2(inner, -inner),
		at + Vector2(radius, 0), at + Vector2(inner, inner),
		at + Vector2(0, radius), at + Vector2(-inner, inner),
		at + Vector2(-radius, 0), at + Vector2(-inner, -inner),
	]), color)


func _local(at: Vector2, scale_factor: float = 1.0) -> void:
	draw_set_transform_matrix(_canvas_transform * Transform2D(
		Vector2(scale_factor, 0), Vector2(0, scale_factor), at))


func _reset_transform() -> void:
	draw_set_transform_matrix(_canvas_transform)


func _cloud(at: Vector2, scale_factor: float = 1.0) -> void:
	_ellipse(at, Vector2(33, 11) * scale_factor, CREAM)
	draw_circle(at + Vector2(-9, -8) * scale_factor, 13 * scale_factor, CREAM)
	draw_circle(at + Vector2(11, -12) * scale_factor, 16 * scale_factor, CREAM)


func _store() -> void:
	_round(9, 8, 622, 291, SKY, 32, 0)
	draw_circle(Vector2(550, 57), 25, GOLD)
	draw_circle(Vector2(550, 57), 16, Color("ffdf87"))
	_cloud(Vector2(98, 70), 1.15)
	_cloud(Vector2(484, 35), 0.75)
	_cloud(Vector2(602, 105), 0.55)
	# Rounded neighboring hedges frame this one-shop neighborhood.
	_round(27, 217, 131, 50, Color("bbdfb0"), 24, 0)
	draw_circle(Vector2(91, 218), 28, Color("bbdfb0"))
	_round(487, 224, 127, 46, Color("bbdfb0"), 23, 0)
	draw_circle(Vector2(544, 223), 24, Color("bbdfb0"))
	_round(40, 265, 561, 24, Color("cbdcc6"), 12, 0)
	_ellipse(Vector2(322, 280), Vector2(230, 14), Color("bbd2bd"))
	# Cream facade, mint inset roof and a substantial dark lower edge.
	_round(153, 88, 335, 183, CREAM, 14, 4, 8)
	_round(165, 75, 311, 35, MINT_DARK, 13, 4, 3)
	_round(196, 47, 250, 51, CREAM, 15, 4, 4)
	_round(207, 56, 228, 32, MINT, 8, 0)
	# Rug emblem rather than copy, so all text remains localizable UI.
	_round(296, 57, 51, 29, CREAM, 6, 2)
	_line(Vector2(304, 62), Vector2(304, 81), MINT_DARK, 2)
	_line(Vector2(339, 62), Vector2(339, 81), MINT_DARK, 2)
	_poly(PackedVector2Array([Vector2(321, 61), Vector2(332, 71), Vector2(321, 81), Vector2(310, 71)]), CORAL, 0)
	for y in [62, 68, 75, 81]:
		_line(Vector2(290, y), Vector2(296, y), INK, 2)
		_line(Vector2(347, y), Vector2(353, y), INK, 2)
	_spark(Vector2(248, 72), 10, MINT_DARK)
	_spark(Vector2(394, 72), 10, MINT_DARK)
	# Shop window: the rug itself is the feature in the display.
	_round(174, 141, 177, 101, INK, 10, 0)
	_round(179, 146, 167, 91, BLUE, 6, 0)
	_poly(PackedVector2Array([Vector2(184, 151), Vector2(229, 151), Vector2(184, 204)]), Color("e9f8f2"), 0)
	_poly(PackedVector2Array([Vector2(304, 151), Vector2(321, 151), Vector2(262, 231), Vector2(245, 231)]), Color("d6f2ed"), 0)
	_round(205, 162, 115, 62, MINT_DARK, 8, 2, 3)
	_round(213, 169, 99, 47, MINT, 5, 0)
	_poly(PackedVector2Array([Vector2(262, 177), Vector2(280, 192), Vector2(262, 207), Vector2(244, 192)]), CREAM, 0)
	draw_circle(Vector2(262, 192), 5, CORAL)
	for x in range(216, 316, 9):
		_line(Vector2(x, 161), Vector2(x, 156), CREAM, 2)
		_line(Vector2(x, 225), Vector2(x, 230), CREAM, 2)
	_round(169, 239, 188, 11, CORAL, 4, 2, 2)
	# Friendly tall entrance with a little hanging open indicator.
	_round(372, 137, 94, 131, MINT_DARK, 9, 4)
	_round(381, 146, 76, 80, BLUE, 5, 3)
	_line(Vector2(389, 151), Vector2(389, 171), Color("ecf8f2"), 5)
	_round(390, 175, 57, 25, CREAM, 7, 2)
	draw_circle(Vector2(402, 187), 4, MINT_DARK)
	_line(Vector2(413, 187), Vector2(436, 187), INK, 3)
	draw_circle(Vector2(451, 237), 4, GOLD)
	_round(365, 263, 111, 9, INK, 4, 0)
	# Scalloped awning, alternating cheerful canvas panels.
	_poly(PackedVector2Array([Vector2(162, 106), Vector2(480, 106), Vector2(498, 139), Vector2(144, 139)]), CREAM, 4)
	for i in range(7):
		var start := 162.0 + float(i) * 45.4
		var lower := 144.0 + float(i) * 50.5
		if i % 2 == 0:
			_poly(PackedVector2Array([Vector2(start, 108), Vector2(start + 44, 108), Vector2(lower + 49, 137), Vector2(lower, 137)]), CORAL, 0)
		_round(lower, 135, 50.5, 18, CORAL if i % 2 == 0 else CREAM, 8, 2)
	_line(Vector2(164, 106), Vector2(478, 106), INK, 4)
	_plant(Vector2(139, 267), 0.86)
	_plant(Vector2(509, 266), 0.66)
	# Little Bonzi waves from the front walk once the shop has its cleaner.
	_local(Vector2(513, 207), 0.48)
	_bonzi(working)
	_reset_transform()
	_spark(Vector2(95, 148), 10, CREAM)
	_spark(Vector2(550, 162), 8, MINT_DARK)
	_line(Vector2(189, 291), Vector2(268, 291), Color("b2cbb5"), 3)
	_line(Vector2(384, 291), Vector2(410, 291), Color("b2cbb5"), 3)


func _plant(base: Vector2, scale_factor: float) -> void:
	_local(base, scale_factor)
	_line(Vector2(0, -24), Vector2(-1, -68), INK, 4)
	_line(Vector2(-1, -47), Vector2(-17, -61), INK, 3)
	_ellipse(Vector2(-18, -64), Vector2(13, 8), MINT_DARK)
	_ellipse(Vector2(12, -76), Vector2(12, 17), MINT)
	_ellipse(Vector2(18, -47), Vector2(15, 9), MINT_DARK)
	_ellipse(Vector2(-11, -84), Vector2(8, 13), MINT_DARK)
	_poly(PackedVector2Array([Vector2(-22, -31), Vector2(22, -31), Vector2(16, 0), Vector2(-16, 0)]), CORAL, 3)
	_round(-25, -36, 50, 12, CORAL, 5, 3)
	_line(Vector2(-10, -19), Vector2(-8, -8), Color("ffb099"), 4)
	_reset_transform()


func _bonzi_card() -> void:
	draw_circle(Vector2(100, 77), 66, PALE)
	_spark(Vector2(31, 46), 8, GOLD)
	_spark(Vector2(164, 65), 6, MINT_DARK)
	_round(37, 122, 134, 19, BLUE, 9, 0)
	for x in [47, 66, 85, 104, 123, 142, 161]:
		_line(Vector2(x, 141), Vector2(x, 146), Color("85b8c0"), 2)
	var travel := sin(_phase * 1.6) * 8.0 if working else 0.0
	_local(Vector2(40 + travel, 22), 0.9)
	_bonzi(working)
	_reset_transform()
	if working:
		_spark(Vector2(37 + travel, 116), 6.0 + sin(_phase * 4) * 2, CREAM)
		_spark(Vector2(156 + travel, 126), 5.0 + cos(_phase * 4) * 2, CREAM)


func _bonzi(is_working: bool) -> void:
	var bob := sin(_phase * 3.2) * 2.0 if is_working else 0.0
	_ellipse(Vector2(64, 126), Vector2(53, 7), Color("b6d7c3"))
	# Stubby wheel feet, little side arms, rounded coral shell.
	_round(24, 104 + bob, 25, 23, INK, 8, 0)
	_round(79, 104 + bob, 25, 23, INK, 8, 0)
	_line(Vector2(30, 119 + bob), Vector2(41, 119 + bob), Color("658681"), 3)
	_line(Vector2(87, 119 + bob), Vector2(97, 119 + bob), Color("658681"), 3)
	_round(7, 65 + bob, 18, 32, MINT, 8, 3)
	_round(103, 64 + bob, 18, 32, MINT, 8, 3)
	_line(Vector2(64, 21 + bob), Vector2(64, 9 + bob), INK, 4)
	draw_circle(Vector2(64, 8 + bob), 7, INK)
	draw_circle(Vector2(64, 7 + bob), 4, GOLD)
	_round(19, 25 + bob, 91, 84, CORAL, 27, 4, 6)
	_round(27, 32 + bob, 75, 53, CREAM, 18, 3)
	_round(37, 48 + bob, 13, 20, INK, 6, 0)
	_round(79, 48 + bob, 13, 20, INK, 6, 0)
	draw_circle(Vector2(41, 52 + bob), 2, CREAM)
	draw_circle(Vector2(83, 52 + bob), 2, CREAM)
	_ellipse(Vector2(36, 70 + bob), Vector2(7, 3), Color("ffbaa1"))
	_ellipse(Vector2(92, 70 + bob), Vector2(7, 3), Color("ffbaa1"))
	draw_arc(Vector2(65, 64 + bob), 8, 0.15, PI - 0.15, 16, INK, 3, true)
	_round(49, 91 + bob, 32, 10, CORAL_DARK, 5, 0)
	draw_circle(Vector2(57, 96 + bob), 2.3, CREAM)
	draw_circle(Vector2(65, 96 + bob), 2.3, CREAM)
	draw_circle(Vector2(73, 96 + bob), 2.3, CREAM)
	# The rotating bottom brush is visible without distracting from the face.
	_round(31, 109 + bob, 67, 10, MINT_DARK, 4, 2)
	for i in range(8):
		var brush_x := 36.0 + float(i) * 8.0
		var lean := sin(_phase * 7 + float(i) * 0.4) * 2.5 if is_working else 0.0
		_line(Vector2(brush_x, 114 + bob), Vector2(brush_x + lean, 120 + bob), CREAM, 2)


func _brush() -> void:
	draw_circle(Vector2(100, 80), 63, PALE)
	_ellipse(Vector2(105, 132), Vector2(61, 7), Color("c3dec5"))
	# Long-handled carpet brush and a cheerful refill bottle.
	_line(Vector2(93, 107), Vector2(118, 27), INK, 14)
	_line(Vector2(93, 107), Vector2(118, 27), GOLD, 8)
	_round(108, 18, 22, 31, CORAL, 8, 3, 2)
	_round(116, 23, 6, 16, CREAM, 3, 0)
	_round(51, 99, 85, 22, MINT, 8, 3, 4)
	for x in range(58, 133, 9):
		_round(x, 119, 5, 10, CREAM, 2, 0)
	_line(Vector2(53, 130), Vector2(134, 130), INK, 3)
	_round(135, 91, 31, 40, CORAL, 8, 3, 2)
	_round(141, 81, 18, 15, MINT, 4, 3)
	_round(140, 104, 21, 15, CREAM, 4, 0)
	_spark(Vector2(150, 111), 6, MINT_DARK)
	_spark(Vector2(51, 56), 9, GOLD)
	draw_circle(Vector2(61, 80), 4, BLUE)
	draw_circle(Vector2(157, 58), 6, BLUE)


func _blueprint() -> void:
	draw_circle(Vector2(100, 80), 63, Color("e0eff5"))
	_ellipse(Vector2(99, 135), Vector2(58, 7), Color("c0dbe2"))
	_round(43, 27, 111, 105, Color("72bbd0"), 8, 3, 5)
	for x in range(54, 149, 16):
		_line(Vector2(x, 37), Vector2(x, 121), Color("9fd4e0"), 1)
	for y in range(42, 128, 16):
		_line(Vector2(49, y), Vector2(147, y), Color("9fd4e0"), 1)
	_round(62, 53, 70, 54, Color(0, 0, 0, 0), 13, 3)
	_round(72, 62, 49, 27, CREAM, 8, 0)
	_round(80, 70, 6, 11, INK, 3, 0)
	_round(107, 70, 6, 11, INK, 3, 0)
	_line(Vector2(97, 53), Vector2(97, 44), CREAM, 3)
	draw_circle(Vector2(97, 43), 4, CREAM)
	_line(Vector2(74, 114), Vector2(121, 114), CREAM, 2)
	_line(Vector2(74, 110), Vector2(74, 118), CREAM, 2)
	_line(Vector2(121, 110), Vector2(121, 118), CREAM, 2)
	_round(137, 24, 20, 111, BLUE, 9, 3, 2)
	_round(41, 24, 17, 16, BLUE, 7, 3)
	# A chunky pencil rests against the plan.
	_poly(PackedVector2Array([Vector2(139, 116), Vector2(164, 65), Vector2(174, 70), Vector2(149, 121), Vector2(138, 129)]), GOLD, 3)
	_line(Vector2(162, 74), Vector2(170, 78), CORAL, 6)
	_poly(PackedVector2Array([Vector2(140, 121), Vector2(145, 125), Vector2(138, 129)]), INK, 0)
	_spark(Vector2(27, 63), 8, GOLD)
	_spark(Vector2(175, 40), 6, MINT_DARK)


func _upgrade() -> void:
	draw_circle(Vector2(100, 80), 64, PALE)
	_ellipse(Vector2(102, 136), Vector2(60, 7), Color("c3dec5"))
	_round(42, 88, 116, 43, CREAM, 10, 3, 4)
	_round(52, 97, 96, 25, MINT, 6, 0)
	for x in [63, 77, 91]:
		draw_circle(Vector2(x, 109), 4, MINT_DARK)
	_round(116, 102, 24, 14, CORAL, 4, 0)
	_poly(PackedVector2Array([Vector2(99, 24), Vector2(134, 60), Vector2(115, 60), Vector2(115, 91), Vector2(83, 91), Vector2(83, 60), Vector2(64, 60)]), MINT_DARK, 4)
	_poly(PackedVector2Array([Vector2(99, 31), Vector2(121, 54), Vector2(109, 54), Vector2(109, 83), Vector2(91, 83), Vector2(91, 54), Vector2(78, 54)]), MINT, 0)
	_line(Vector2(99, 51), Vector2(99, 71), Color("bdf1b9"), 5)
	_spark(Vector2(47, 52), 8, GOLD)
	_spark(Vector2(152, 66), 10, GOLD)


func _intake() -> void:
	draw_circle(Vector2(100, 80), 64, Color("fff0d4"))
	_ellipse(Vector2(101, 134), Vector2(62, 7), Color("e4d8b6"))
	# Two rolled rugs in a mint job intake bin, each with its own weave.
	_round(58, 41, 33, 86, CORAL, 15, 3)
	_ellipse(Vector2(74.5, 43), Vector2(16.5, 11), INK)
	_ellipse(Vector2(74.5, 42), Vector2(13, 8), Color("ffb49d"))
	draw_arc(Vector2(75, 43), 6, 0, TAU * 0.86, 20, CORAL_DARK, 3, true)
	_line(Vector2(65, 58), Vector2(65, 94), Color("ffb49d"), 3)
	_round(98, 28, 39, 96, Color("91bccf"), 16, 3)
	_ellipse(Vector2(117.5, 30), Vector2(19.5, 12), INK)
	_ellipse(Vector2(117.5, 29), Vector2(16, 9), BLUE)
	draw_arc(Vector2(118, 30), 7, 0, TAU * 0.85, 20, Color("679eb5"), 3, true)
	_line(Vector2(107, 48), Vector2(107, 88), BLUE, 4)
	_line(Vector2(126, 49), Vector2(126, 88), BLUE, 2)
	_round(43, 91, 113, 44, MINT, 10, 3, 4)
	_round(39, 86, 121, 15, MINT_DARK, 6, 3)
	_round(82, 106, 36, 20, CREAM, 6, 2)
	_line(Vector2(91, 116), Vector2(97, 121), MINT_DARK, 3)
	_line(Vector2(97, 121), Vector2(109, 110), MINT_DARK, 3)
	_spark(Vector2(38, 48), 8, GOLD)
	_spark(Vector2(160, 64), 8, CORAL)
