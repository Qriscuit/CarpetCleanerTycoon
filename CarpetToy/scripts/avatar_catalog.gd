extends RefCounted
## Free starter appearance choices. IDs are saved independently of menu order.

const COLORS := [
	{"id": "orange", "name": "Orange", "color": Color("f28c28")},
	{"id": "gold", "name": "Gold", "color": Color("edbd52")},
	{"id": "coral", "name": "Coral", "color": Color("e87867")},
	{"id": "pink", "name": "Pink", "color": Color("e694b3")},
	{"id": "mint", "name": "Mint", "color": Color("78c9ae")},
	{"id": "blue", "name": "Blue", "color": Color("79addb")},
	{"id": "violet", "name": "Violet", "color": Color("a18acb")},
	{"id": "ivory", "name": "Ivory", "color": Color("f5edda")},
]
const HATS := [
	{"id": "none", "name": "No hat"},
	{"id": "pirate", "name": "Pirate hat"},
	{"id": "beanie", "name": "Beanie"},
]


static func default_appearance() -> Dictionary:
	return {"color_id": "orange", "hat_id": "none"}


static func has_color(id: String) -> bool:
	for entry: Dictionary in COLORS:
		if entry.id == id: return true
	return false


static func has_hat(id: String) -> bool:
	for entry: Dictionary in HATS:
		if entry.id == id: return true
	return false


static func color_for(id: String) -> Color:
	for entry: Dictionary in COLORS:
		if entry.id == id: return entry.color
	return COLORS[0].color


static func sanitize_appearance(value: Variant) -> Dictionary:
	var result := default_appearance()
	if not value is Dictionary: return result
	var color: Variant = value.get("color_id")
	var hat: Variant = value.get("hat_id")
	if color is String and has_color(color): result.color_id = color
	if hat is String and has_hat(hat): result.hat_id = hat
	return result
