class_name BallDesign
extends RefCounted
## Deterministic visual identity for a Bench guy's ball.
##
## The descriptor is deliberately plain data: it can be handed to a preview control without
## constructing a physics body, and it never becomes save data.  The guy's persistent numeric
## id is the only identity input; traits and names are not identity because they can repeat.

const _BASE_COLORS := [
	Color("#BFC5CC"), Color("#C9A227"), Color("#B86F52"), Color("#6D9A9A"),
	Color("#897BA8"), Color("#82956C"), Color("#C18443"), Color("#75879B"),
]
const _ACCENT_COLORS := [
	Color("#242124"), Color("#F2E8D5"), Color("#241C18"), Color("#172C32"),
	Color("#241D35"), Color("#203021"), Color("#2B1B12"), Color("#17222E"),
]
const BAND_COUNT := 8
const CREST_COUNT := 8
const RECOGNIZABLE_VARIANTS := BAND_COUNT * CREST_COUNT


static func anonymous() -> Dictionary:
	return {
		"id": 0,
		"identity_key": &"steel",
		"base_color": Color("#C7C9CC"),
		"band_color": Color("#303238"),
		"band": 0,
		"band_geometry": &"steel",
		"crest": 0,
		"crest_mark": &"none",
		"angle": 0.0,
		"anonymous": true,
	}


static func for_guy(guy: Dictionary) -> Dictionary:
	if guy.is_empty():
		return anonymous()
	var id := int(guy.get("id", 0))
	if id <= 0:
		return anonymous()
	return for_id(id)


static func for_id(id: int) -> Dictionary:
	if id <= 0:
		return anonymous()
	# Treat the id as a mixed-radix visual serial rather than independently hashing each
	# field.  That makes the visible tuple collision-free for the whole supported career
	# range (8 bands × 8 crests × 8 base colours × 8 accents × 360 angles), while remaining
	# integer-only and therefore stable across save/load and platforms.
	var slot := id - 1
	var band := posmod(slot, BAND_COUNT)
	var crest := posmod(slot / BAND_COUNT, CREST_COUNT)
	var palette := posmod(slot / RECOGNIZABLE_VARIANTS, _BASE_COLORS.size())
	var accent_stride := RECOGNIZABLE_VARIANTS * _BASE_COLORS.size()
	var accent_palette := posmod(slot / accent_stride, _ACCENT_COLORS.size())
	var angle_stride := accent_stride * _ACCENT_COLORS.size()
	return {
		"id": id,
		"identity_key": StringName("guy_%d" % id),
		"base_color": _BASE_COLORS[palette],
		"band_color": _ACCENT_COLORS[accent_palette],
		"band": band,
		"band_geometry": _band_name(band),
		"crest": crest,
		"crest_mark": _crest_name(crest),
		"angle": deg_to_rad(float(posmod(slot / angle_stride, 360))),
		"anonymous": false,
	}


static func _band_name(index: int) -> StringName:
	return [&"equator", &"diagonal", &"split", &"meridian", &"double", &"slash",
		&"crown", &"cross"][index]


static func _crest_name(index: int) -> StringName:
	return [&"diamond", &"triangle", &"cross", &"chevron", &"target", &"star", &"bars",
		&"bolt"][index]


## Draws both live balls and previews.  `target` owns the CanvasItem draw API; this helper
## contains the grammar so a Roll Call preview cannot drift from the table's ball art.
static func draw_ball(target: CanvasItem, center: Vector2, radius: float, design: Dictionary,
		pulse: float = 1.0) -> void:
	var r := maxf(radius * pulse, 1.0)
	if bool(design.get("anonymous", false)):
		# Keep anonymous/debug balls byte-for-byte in the original steel grammar.
		target.draw_circle(center + Vector2(0.0, 2.0), r, Color(0.0, 0.0, 0.0, 0.35))
		target.draw_circle(center, r, Color(0.78, 0.79, 0.82))
		target.draw_circle(center + Vector2(-r * 0.28, -r * 0.3), r * 0.34,
			Color(0.94, 0.95, 0.97))
		target.draw_arc(center, r - 2.0, 0.0, TAU, 32, Color(0.32, 0.33, 0.36), 4.0)
		return
	var base: Color = design.get("base_color", anonymous()["base_color"])
	var band: Color = design.get("band_color", anonymous()["band_color"])
	var crest := int(design.get("crest", 0))
	var band_id := int(design.get("band", 0))
	var angle := float(design.get("angle", 0.0))
	var ink := Color("#171512")
	target.draw_circle(center + Vector2(0.0, r * 0.08), r, Color(0.0, 0.0, 0.0, 0.35))
	target.draw_circle(center, r, base)
	_draw_band(target, center, r, band, band_id, angle)
	_draw_crest(target, center, r, band, ink, crest, angle)
	# The spec's fake reflection is retained for steel and carried over the identity finish.
	target.draw_circle(center + Vector2(-r * 0.28, -r * 0.3), r * 0.34,
		Color(0.96, 0.97, 0.99, 0.82))
	target.draw_arc(center, r - maxf(r * 0.14, 1.5), 0.0, TAU, 32, ink.lightened(0.15),
		maxf(r * 0.12, 2.0))


static func _draw_band(target: CanvasItem, center: Vector2, radius: float, color: Color,
		band: int, angle: float) -> void:
	var width := maxf(radius * 0.14, 2.5)
	var ring := radius * 0.71
	match band:
		0: # Equator
			target.draw_arc(center, ring, 0.0, TAU, 28, color, width)
		1: # A single diagonal sash, visibly unlike a ring.
			target.draw_arc(center, ring, angle + 0.25, angle + PI - 0.25, 18, color, width)
		2: # Two opposing short arcs.
			target.draw_arc(center, ring, angle, angle + PI * 0.72, 14, color, width)
			target.draw_arc(center, ring, angle + PI, angle + PI * 1.72, 14, color, width)
		3: # Vertical meridian.
			target.draw_arc(center, ring, angle - PI * 0.5, angle + PI * 0.5, 18, color, width)
		4: # Double rings.
			target.draw_arc(center, radius * 0.57, 0.0, TAU, 24, color, width * 0.72)
			target.draw_arc(center, radius * 0.79, 0.0, TAU, 24, color, width * 0.72)
		5: # Slash crossing the face in two separated halves.
			target.draw_arc(center, ring, angle - 0.48, angle + 0.48, 12, color, width)
			target.draw_arc(center, ring, angle + PI - 0.48, angle + PI + 0.48, 12, color, width)
		6: # Crown: upper arc plus lower anchor arc.
			target.draw_arc(center, ring, angle + PI * 0.9, angle + PI * 1.8, 14, color, width)
			target.draw_arc(center, ring, angle + PI * 0.1, angle + PI * 0.4, 8, color, width)
		7: # Crossed meridians.
			target.draw_arc(center, ring, angle - PI * 0.5, angle + PI * 0.5, 18, color, width * 0.8)
			target.draw_arc(center, ring, angle + PI * 0.5, angle + PI * 1.5, 18, color, width * 0.8)


static func _draw_crest(target: CanvasItem, center: Vector2, radius: float, accent: Color,
		ink: Color, crest: int, angle: float) -> void:
	var mark := accent if accent.get_luminance() < 0.45 else ink
	var size := radius * 0.26
	var points := PackedVector2Array()
	match crest:
		0: # Diamond
			points = _points(center, [Vector2(0, -size), Vector2(size, 0), Vector2(0, size),
				Vector2(-size, 0)], angle)
		1: # Triangle
			points = _points(center, [Vector2(0, -size), Vector2(size, size),
				Vector2(-size, size)], angle)
		2: # Cross
			points = _points(center, [Vector2(-size, -size * 0.35), Vector2(-size * 0.35, -size * 0.35),
				Vector2(-size * 0.35, -size), Vector2(size * 0.35, -size),
				Vector2(size * 0.35, -size * 0.35), Vector2(size, -size * 0.35),
				Vector2(size, size * 0.35), Vector2(size * 0.35, size * 0.35),
				Vector2(size * 0.35, size), Vector2(-size * 0.35, size),
				Vector2(-size * 0.35, size * 0.35), Vector2(-size, size * 0.35)], angle)
		3: # Chevron
			points = _points(center, [Vector2(-size, -size * 0.45), Vector2(0, size * 0.55),
				Vector2(size, -size * 0.45), Vector2(size, size * 0.15), Vector2(0, size),
				Vector2(-size, size * 0.15)], angle)
		4: # Target
			target.draw_circle(center, size, ink)
			target.draw_circle(center, size * 0.62, mark)
			target.draw_circle(center, size * 0.22, ink)
			return
		5: # Four-point star
			points = _points(center, [Vector2(0, -size), Vector2(size * 0.34, -size * 0.34),
				Vector2(size, 0), Vector2(size * 0.34, size * 0.34), Vector2(0, size),
				Vector2(-size * 0.34, size * 0.34), Vector2(-size, 0),
				Vector2(-size * 0.34, -size * 0.34)], angle)
		6: # Twin bars
			points = _points(center, [Vector2(-size, -size), Vector2(-size * 0.45, -size),
				Vector2(-size * 0.45, size), Vector2(-size, size)], angle)
			target.draw_colored_polygon(points, ink)
			points = _points(center, [Vector2(size * 0.45, -size), Vector2(size, -size),
				Vector2(size, size), Vector2(size * 0.45, size)], angle)
			target.draw_colored_polygon(points, mark)
			return
		7: # Lightning bolt
			points = _points(center, [Vector2(size * 0.2, -size), Vector2(-size * 0.1, -size * 0.1),
				Vector2(-size * 0.55, -size * 0.1), Vector2(-size * 0.1, size),
				Vector2(size * 0.1, size * 0.1), Vector2(size * 0.55, size * 0.1)], angle)
	if points.is_empty():
		return
	target.draw_colored_polygon(points, ink)
	# A smaller, contrasting inset keeps each mark readable at table scale.
	var inner := PackedVector2Array()
	for p: Vector2 in points:
		inner.append(center + (p - center) * 0.55)
	target.draw_colored_polygon(inner, mark)


static func _points(center: Vector2, local: Array, angle: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for value: Variant in local:
		var p: Vector2 = value
		out.append(center + p.rotated(angle))
	return out
