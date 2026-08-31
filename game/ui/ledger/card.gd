class_name LedgerCard
extends Control
## One card on the corkboard. Draws itself in every state the board can put it in:
## face-down (kraft back, hatched, no information), revealed (index card with name + cost),
## affordable (the pushpin glints), owned (yellowed, stamped DONE, pinned FLAT — the tilt
## every other card has goes to zero, which is the whole "pinned flat" gag from docs/04).
##
## A TROPHY is the other kind of card: a boss's signature spoil (`spoil.*`), which was never
## for sale (docs/05 §6). It hangs on the same board in gold trim, always face-up, with no
## price and no BUY — "TAKEN, NOT BOUGHT" where the cost would be.
##
## No textures: everything here is draw_rect / draw_line / draw_string against the palette.

## A card has to survive the compact 486 px capture after the 1080 logical canvas is
## scaled. 300x204 leaves room for a three-line title, an explicit state row, and the
## price without falling back to ellipses.
const W := 300.0
const H := 204.0

enum Face { HIDDEN, FACEDOWN, REVEALED }
## What this card IS: a Ledger node you buy, or a spoil you took off somebody.
enum Kind { NODE, TROPHY }

var id: String = ""
var kind: int = Kind.NODE
var face: int = Face.HIDDEN
var level: int = 0
var max_level: int = 1
var cost: BigMoney = BigMoney.zero()
var block: int = Upgrades.Block.NONE
var selected: bool = false
var newly_unlocked: bool = false

var _def: Dictionary = {}
var _tilt: float = 0.0
var _pulse: float = 0.0
var _font: Font = null


func _ready() -> void:
	_font = Presentation.theme.font_for(&"annotation_bold")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	pivot_offset = size * 0.5


## Binds the card to a catalog node. The pin angle is hashed off the id so a card sits at
## the same jaunty angle every time the board is built — deterministic, never twitchy.
func setup(node_def: Dictionary) -> void:
	_def = node_def
	id = String(node_def["id"])
	max_level = int(node_def["max_level"])
	_tilt = deg_to_rad((float(hash(id) % 1000) / 1000.0 - 0.5) * 5.4)
	queue_redraw()


## Binds the card to a spoil the career took: `{"id", "name", "from"}` — the trophy's own
## name and the boss it came off. A trophy is owned the moment it exists, so it is set up
## face-up, pinned flat, and never asks the board for a state again.
func setup_trophy(descriptor: Dictionary) -> void:
	kind = Kind.TROPHY
	_def = descriptor
	id = String(descriptor.get("id", ""))
	max_level = 1
	level = 1
	face = Face.REVEALED
	newly_unlocked = false
	block = Upgrades.Block.MAXED
	cost = BigMoney.zero()
	visible = true
	rotation = 0.0
	set_process(false)
	queue_redraw()


func set_state(p_face: int, p_level: int, p_cost: BigMoney, p_block: int,
		p_newly_unlocked: bool = false) -> void:
	face = p_face
	level = p_level
	cost = p_cost if p_cost != null else BigMoney.zero()
	block = p_block
	newly_unlocked = p_newly_unlocked and p_face == Face.REVEALED and p_level <= 0
	visible = face != Face.HIDDEN
	rotation = 0.0 if is_owned() else _tilt
	set_process(is_glinting())
	queue_redraw()


func set_selected(v: bool) -> void:
	if selected == v:
		return
	selected = v
	rotation = 0.0 if v or is_owned() else _tilt
	queue_redraw()


func is_owned() -> bool:
	return level > 0


## Buyable right now, money in hand — the pushpin glint case.
func is_glinting() -> bool:
	return face == Face.REVEALED and block == Upgrades.Block.NONE


func _process(delta: float) -> void:
	if Presentation.fx != null and Presentation.fx.reduced_motion:
		_pulse = 0.0
		set_process(false)
		queue_redraw()
		return
	_pulse = fmod(_pulse + delta * 1.6, TAU)
	queue_redraw()


func _draw() -> void:
	if face == Face.HIDDEN:
		return
	draw_rect(Rect2(Vector2(5.0, 7.0), size), LedgerStyle.SHADOW)
	if kind == Kind.TROPHY:
		_draw_trophy()
	elif face == Face.FACEDOWN:
		_draw_back()
	else:
		_draw_front()
	if selected:
		draw_rect(Rect2(Vector2(-5.0, -5.0), size + Vector2(10.0, 10.0)), LedgerStyle.BRASS, false, 3.0)
	_draw_pin()


# --- faces --------------------------------------------------------------------


func _draw_back() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, LedgerStyle.CARD_BACK)
	# 45° hatch, clipped by hand: the card is a rect, not a clip node.
	var step := 22.0
	var x := -size.y
	while x < size.x:
		var x0 := maxf(x, 0.0)
		var x1 := minf(x + size.y, size.x)
		if x1 > x0:
			draw_line(Vector2(x0, x0 - x), Vector2(x1, x1 - x), LedgerStyle.CARD_BACK_LINE, 1.5)
		x += step
	draw_rect(Rect2(Vector2(9.0, 9.0), size - Vector2(18.0, 18.0)), LedgerStyle.CARD_BACK_LINE, false, 2.0)
	var c := size * 0.5
	var d := 26.0
	draw_polyline(PackedVector2Array([
		c + Vector2(0.0, -d), c + Vector2(d, 0.0), c + Vector2(0.0, d), c + Vector2(-d, 0.0),
		c + Vector2(0.0, -d),
	]), LedgerStyle.CARD_BACK_LINE, 2.0)
	_text("?", Vector2(c.x - 11.0, c.y + 16.0), _px(46, &"title"), LedgerStyle.CARD_BACK_INK)
	_text("FILE NOT REVEALED", Vector2(20.0, size.y - _baseline(&"metadata", 20.0)),
		_px(16, &"metadata"), LedgerStyle.CARD_BACK_INK)
	draw_rect(r, LedgerStyle.INK * Color(1, 1, 1, 0.5), false, 2.0)


func _draw_front() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var owned := is_owned()
	var locked := block == Upgrades.Block.RANK or block == Upgrades.Block.REQUIRES
	draw_rect(r, LedgerStyle.PAPER_OWNED if owned else LedgerStyle.PAPER)
	draw_rect(r, LedgerStyle.PAPER_EDGE, false, 2.0)

	var branch := String(_def["branch"])
	var accent := LedgerStyle.branch_color(branch)
	draw_rect(Rect2(Vector2.ZERO, Vector2(7.0, size.y)), accent)

	_text(LedgerStyle.branch_title(branch), Vector2(20.0, 28.0), _px(16, &"metadata"),
		accent.darkened(0.15))
	_text("T%d" % int(_def["tier"]), Vector2(size.x - 44.0, 28.0), _px(16, &"metadata"),
		LedgerStyle.INK_SOFT)

	# A hire gives up type size for his portrait. Titles are wrapped deliberately rather than
	# clipped: this is the face a player uses to decide, not a debug label.
	var specialist: Dictionary = _def["specialist"]
	var title_width := (size.x - 110.0) if not specialist.is_empty() else (size.x - 42.0)
	var title_px := _px(25 if specialist.is_empty() else 22, &"title")
	var title_lines := _wrap_lines(String(_def["name"]), title_width, title_px, 3)
	for i in title_lines.size():
		_text(title_lines[i], Vector2(20.0, 62.0 + float(i) * float(title_px) * 25.0 / 25.0),
			title_px, LedgerStyle.INK)
	if not specialist.is_empty():
		_draw_portrait(accent, String(specialist["instrument"]))
	if owned:
		# The stamp is a material cue, but it never gets to cover the state or cost rows.
		_draw_stamp()

	var state_px := _px(16, &"metadata")
	var state_y := 137.0
	var state_text := _state_text()
	var state_color := _state_color()
	_text(state_text, Vector2(20.0, state_y), state_px, state_color)
	if level > 0 and max_level > 1 and level < max_level:
		_text("LEVEL %d / %d" % [level, max_level], Vector2(size.x - 112.0, state_y),
			_px(14, &"metadata"),
			LedgerStyle.INK_SOFT)
	if newly_unlocked:
		_badge("NEW", LedgerStyle.BRASS, LedgerStyle.INK, state_y - 25.0)
	elif max_level > 1 and level <= 0 and block != Upgrades.Block.RANK and block != Upgrades.Block.REQUIRES:
		# Repeatability is useful context, but it is secondary to the state and price. Keep it
		# in the reserved state row at a compact semantic size rather than over the cost line.
		_badge("REPEATABLE", LedgerStyle.INK, LedgerStyle.PAPER_EDGE, state_y - 22.0, 12)

	if owned and level >= max_level:
		_text("MAXED", Vector2(20.0, size.y - _baseline(&"primary_value", 20.0)),
			_px(23, &"primary_value"), LedgerStyle.INK_SOFT)
	else:
		var cost_col := LedgerStyle.CLEAN
		if block == Upgrades.Block.MONEY:
			cost_col = LedgerStyle.DIRTY
		elif locked:
			cost_col = LedgerStyle.INK_SOFT
		var cost_px := _px(24, &"primary_value")
		_text("COST  " + cost.text(), Vector2(20.0, size.y - _baseline(&"primary_value", 20.0)),
			cost_px, cost_col)

	# Why you cannot buy it beats how many you own: the badge slot goes to the blocker first.
	if block == Upgrades.Block.RANK:
		_badge("R%d" % int(_def["tier"]), LedgerStyle.DIRTY, LedgerStyle.PAPER)
	elif block == Upgrades.Block.REQUIRES:
		_badge("LOCKED", LedgerStyle.INK, LedgerStyle.PAPER_EDGE)

	if locked and not owned:
		draw_rect(r, Color(LedgerStyle.INK.r, LedgerStyle.INK.g, LedgerStyle.INK.b, 0.22))


## The trophy face: the same index card in gold trim, with the price line replaced by the
## only thing a spoil has instead of a price. The corner ticks are the frame of a photograph
## in an evidence file — this is the one card on the board that is a picture of a win.
func _draw_trophy() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, LedgerStyle.PAPER_OWNED)
	draw_rect(r, LedgerStyle.BRASS, false, 3.0)
	draw_rect(Rect2(Vector2(7.0, 7.0), size - Vector2(14.0, 14.0)), Color(LedgerStyle.BRASS, 0.55), false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(7.0, size.y)), LedgerStyle.BRASS)
	for corner: Vector2 in [Vector2(14.0, 14.0), Vector2(size.x - 14.0, 14.0),
			Vector2(14.0, size.y - 14.0), Vector2(size.x - 14.0, size.y - 14.0)]:
		draw_line(corner + Vector2(-8.0, 0.0), corner + Vector2(8.0, 0.0), LedgerStyle.BRASS, 2.0)
		draw_line(corner + Vector2(0.0, -8.0), corner + Vector2(0.0, 8.0), LedgerStyle.BRASS, 2.0)

	_text("SPOIL  ·  TAKEN", Vector2(20.0, 30.0), _px(16, &"metadata"),
		LedgerStyle.BRASS.darkened(0.25))
	var trophy_title_px := _px(25, &"title")
	var trophy_lines := _wrap_lines(String(_def.get("name", id)), size.x - 42.0, trophy_title_px, 3)
	for i in trophy_lines.size():
		_text(trophy_lines[i], Vector2(20.0, 68.0 + float(i) * float(trophy_title_px) * 26.0 / 25.0),
			trophy_title_px, LedgerStyle.INK)
	var from := String(_def.get("from", ""))
	if not from.is_empty():
		_text("OFF %s" % from.to_upper(), Vector2(20.0, size.y - 44.0), _px(16, &"metadata"),
			LedgerStyle.INK_SOFT)
	_text("TAKEN, NOT BOUGHT", Vector2(20.0, size.y - _baseline(&"primary_value", 20.0)),
		_px(20, &"primary_value"), LedgerStyle.BRASS.darkened(0.3))


## A hire gets a face. Until the mugshot art exists (docs/07 §3 "specialist portraits"), that
## face is an initials medallion in his branch colour with his instrument-voice under it
## (docs/08 §5) — the portrait slot at final size, so the art drops straight in.
func _draw_portrait(accent: Color, instrument: String) -> void:
	var c := Vector2(size.x - 46.0, 78.0)
	draw_circle(c + Vector2(2.0, 3.0), 27.0, Color(0.0, 0.0, 0.0, 0.22))
	draw_circle(c, 26.0, accent.darkened(0.18))
	draw_arc(c, 26.0, 0.0, TAU, 40, LedgerStyle.PAPER, 2.0)
	var mark := _initials(String(_def["name"]))
	var mark_px := _px(24, &"title")
	var w := _font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1.0, mark_px).x
	draw_string(_font, c + Vector2(-w * 0.5, 9.0), mark, HORIZONTAL_ALIGNMENT_LEFT, -1.0, mark_px,
		LedgerStyle.PAPER)
	var voice := LedgerStyle.pretty(instrument).to_upper()
	var voice_px := _px(14, &"metadata")
	var vw := _font.get_string_size(voice, HORIZONTAL_ALIGNMENT_LEFT, -1.0, voice_px).x
	draw_string(_font, Vector2(c.x - vw * 0.5, c.y + 40.0), voice, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		voice_px, LedgerStyle.INK_SOFT)


## "Big Sal" -> BS, '"Numbers" Nussbaum' -> NN, "The Professor" -> P: letters only, and the
## article is not a name.
static func _initials(from_name: String) -> String:
	var out := ""
	for raw: String in from_name.split(" ", false):
		var word := ""
		for i in raw.length():
			var ch := raw[i]
			if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z"):
				word += ch
		if word.is_empty() or word.to_lower() == "the":
			continue
		out += word[0].to_upper()
		if out.length() >= 2:
			break
	return out if out != "" else "?"


## The DONE stamp: rubber-stamp red, off-square, over the top of everything.
func _draw_stamp() -> void:
	var c := Vector2(size.x * 0.67, size.y * 0.43)
	draw_set_transform(c, deg_to_rad(-13.0), Vector2.ONE)
	var stamp := Color(LedgerStyle.DIRTY.r, LedgerStyle.DIRTY.g, LedgerStyle.DIRTY.b, 0.78)
	draw_rect(Rect2(-57.0, -21.0, 114.0, 42.0), stamp, false, 3.0)
	draw_rect(Rect2(-52.0, -16.0, 104.0, 32.0), stamp, false, 1.0)
	var stamp_px := _px(28, &"title")
	var w := _font.get_string_size("DONE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, stamp_px).x
	draw_string(_font, Vector2(-w * 0.5, 10.0), "DONE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, stamp_px, stamp)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_pin() -> void:
	var p := Vector2(size.x - 20.0, 18.0)
	if is_glinting():
		var t := (sin(_pulse) + 1.0) * 0.5
		draw_circle(p, 12.0 + t * 9.0, Color(LedgerStyle.CLEAN.r, LedgerStyle.CLEAN.g, LedgerStyle.CLEAN.b, 0.42 * (1.0 - t)))
	var head := LedgerStyle.BRASS
	if kind == Kind.TROPHY:
		head = LedgerStyle.BRASS
	elif is_owned():
		head = LedgerStyle.DIRTY
	elif face == Face.FACEDOWN:
		head = LedgerStyle.CARD_BACK_INK
	draw_circle(p, 9.0, head.darkened(0.45))
	draw_circle(p, 7.0, head)
	draw_circle(p + Vector2(-2.0, -2.0), 2.2, head.lightened(0.55))


# --- helpers ------------------------------------------------------------------


func _text(s: String, at: Vector2, px: int, col: Color) -> void:
	draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, col)


func _px(base: int, role: StringName) -> int:
	if Presentation.theme == null:
		return base
	var authored := 34.0
	match role:
		&"title": authored = 44.0
		&"section": authored = 38.0
		&"primary_value": authored = 44.0
		&"caption": authored = 24.0
		&"metadata": authored = 22.0
		&"button": authored = 28.0
		&"micro": authored = 20.0
		_: authored = 34.0
	return maxi(1, roundi(float(base) * float(Presentation.theme.size_for(role)) / authored))


func _baseline(role: StringName, base: float) -> float:
	if Presentation.theme == null:
		return base
	var px := float(Presentation.theme.size_for(role))
	var authored := 34.0
	match role:
		&"title": authored = 44.0
		&"section": authored = 38.0
		&"primary_value": authored = 44.0
		&"caption": authored = 24.0
		&"metadata": authored = 22.0
		&"button": authored = 28.0
		&"micro": authored = 20.0
	return base * maxf(1.0, px / authored)


func _wrap_lines(value: String, max_width: float, px: int, max_lines: int) -> PackedStringArray:
	var out := PackedStringArray()
	var words := value.split(" ", false)
	var line := ""
	for word: String in words:
		var candidate := word if line.is_empty() else line + " " + word
		if not line.is_empty() and _font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x > max_width:
			out.append(line)
			line = word
		else:
			line = candidate
	if not line.is_empty():
		out.append(line)
	if out.size() <= max_lines:
		return out
	# The catalog has finite copy and the third line is the last safe baseline. Put the
	# remaining words there at a smaller size rather than drawing an ellipsis or clipping.
	var compact := out.slice(0, max_lines - 1)
	var rest := " ".join(out.slice(max_lines - 1))
	compact.append(rest)
	return compact


func _state_text() -> String:
	if newly_unlocked:
		return "NEWLY UNLOCKED"
	if level >= max_level and is_owned():
		return "MAXED OUT"
	if is_owned():
		return "OWNED"
	match block:
		Upgrades.Block.NONE:
			return "READY TO BUY"
		Upgrades.Block.MONEY:
			return "CLEAN CASH SHORT"
		Upgrades.Block.RANK:
			return "RANK LOCKED"
		Upgrades.Block.REQUIRES:
			return "REQUIRES ANOTHER CARD"
		Upgrades.Block.UNKNOWN:
			return "UNAVAILABLE"
	return "AVAILABLE"


func _state_color() -> Color:
	if newly_unlocked:
		return LedgerStyle.BRASS.darkened(0.20)
	if is_owned():
		return LedgerStyle.DIRTY
	match block:
		Upgrades.Block.NONE:
			return LedgerStyle.CLEAN.darkened(0.12)
		Upgrades.Block.MONEY:
			return LedgerStyle.DIRTY.darkened(0.1)
	return LedgerStyle.INK_SOFT


func _badge(s: String, bg: Color, fg: Color, top: float = -1.0, base_px: int = 18) -> void:
	var px := _px(base_px, &"metadata")
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x + 16.0
	var box_top := top if top >= 0.0 else size.y - 34.0
	var box := Rect2(size.x - w - 14.0, box_top, w, 26.0 * float(px) / 18.0)
	draw_rect(box, bg)
	draw_string(_font, box.position + Vector2(8.0, float(px) + 1.0), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, fg)
