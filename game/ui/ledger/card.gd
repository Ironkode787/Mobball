class_name LedgerCard
extends Control
## One card on the corkboard. Draws itself in every state the board can put it in:
## face-down (kraft back, hatched, no information), revealed (index card with name + cost),
## affordable (the pushpin glints), owned (yellowed, stamped DONE, pinned FLAT — the tilt
## every other card has goes to zero, which is the whole "pinned flat" gag from docs/04).
##
## No textures: everything here is draw_rect / draw_line / draw_string against the palette.

const W := 236.0
const H := 158.0

enum Face { HIDDEN, FACEDOWN, REVEALED }

var id: String = ""
var face: int = Face.HIDDEN
var level: int = 0
var max_level: int = 1
var cost: BigMoney = BigMoney.zero()
var block: int = Upgrades.Block.NONE
var selected: bool = false

var _def: Dictionary = {}
var _tilt: float = 0.0
var _pulse: float = 0.0
var _font: Font = null


func _ready() -> void:
	_font = get_theme_default_font()
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


func set_state(p_face: int, p_level: int, p_cost: BigMoney, p_block: int) -> void:
	face = p_face
	level = p_level
	cost = p_cost if p_cost != null else BigMoney.zero()
	block = p_block
	visible = face != Face.HIDDEN
	rotation = 0.0 if is_owned() else _tilt
	set_process(is_glinting())
	queue_redraw()


func set_selected(v: bool) -> void:
	if selected == v:
		return
	selected = v
	queue_redraw()


func is_owned() -> bool:
	return level > 0


## Buyable right now, money in hand — the pushpin glint case.
func is_glinting() -> bool:
	return face == Face.REVEALED and block == Upgrades.Block.NONE


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * 1.6, TAU)
	queue_redraw()


func _draw() -> void:
	if face == Face.HIDDEN:
		return
	draw_rect(Rect2(Vector2(5.0, 7.0), size), LedgerStyle.SHADOW)
	if face == Face.FACEDOWN:
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
	_text("?", Vector2(c.x - 11.0, c.y + 16.0), 46, LedgerStyle.CARD_BACK_INK)
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

	_text(LedgerStyle.branch_title(branch), Vector2(20.0, 28.0), 15, accent.darkened(0.15))
	_text("T%d" % int(_def["tier"]), Vector2(size.x - 44.0, 28.0), 15, LedgerStyle.INK_SOFT)

	# A hire gives up type size for his portrait: "Skids the Wheelman" has to survive the
	# narrower column, and a name clipped mid-word is worse than a name set one size down.
	var specialist: Dictionary = _def["specialist"]
	var named := specialist.is_empty()
	draw_multiline_string(
		_font, Vector2(20.0, 64.0), String(_def["name"]), HORIZONTAL_ALIGNMENT_LEFT,
		(size.x - 46.0) if named else (size.x - 98.0), 26 if named else 21, 2, LedgerStyle.INK
	)
	if not specialist.is_empty():
		_draw_portrait(accent, String(specialist["instrument"]))

	if owned and level >= max_level:
		_text("BOUGHT", Vector2(20.0, size.y - 20.0), 22, LedgerStyle.INK_SOFT)
	else:
		var cost_col := LedgerStyle.CLEAN
		if block == Upgrades.Block.MONEY:
			cost_col = LedgerStyle.DIRTY
		elif locked:
			cost_col = LedgerStyle.INK_SOFT
		_text(cost.text(), Vector2(20.0, size.y - 20.0), 26, cost_col)

	# Why you cannot buy it beats how many you own: the badge slot goes to the blocker first.
	if block == Upgrades.Block.RANK:
		_badge("R%d" % int(_def["tier"]), LedgerStyle.DIRTY, LedgerStyle.PAPER)
	elif block == Upgrades.Block.REQUIRES:
		_badge("LOCKED", LedgerStyle.INK, LedgerStyle.PAPER_EDGE)
	elif max_level > 1:
		_badge("%d/%d" % [level, max_level], LedgerStyle.INK, LedgerStyle.BRASS)

	if locked and not owned:
		draw_rect(r, Color(LedgerStyle.INK.r, LedgerStyle.INK.g, LedgerStyle.INK.b, 0.22))
	if owned:
		_draw_stamp()


## A hire gets a face. Until the mugshot art exists (docs/07 §3 "specialist portraits"), that
## face is an initials medallion in his branch colour with his instrument-voice under it
## (docs/08 §5) — the portrait slot at final size, so the art drops straight in.
func _draw_portrait(accent: Color, instrument: String) -> void:
	var c := Vector2(size.x - 46.0, 78.0)
	draw_circle(c + Vector2(2.0, 3.0), 27.0, Color(0.0, 0.0, 0.0, 0.22))
	draw_circle(c, 26.0, accent.darkened(0.18))
	draw_arc(c, 26.0, 0.0, TAU, 40, LedgerStyle.PAPER, 2.0)
	var mark := _initials(String(_def["name"]))
	var w := _font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24).x
	draw_string(_font, c + Vector2(-w * 0.5, 9.0), mark, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, LedgerStyle.PAPER)
	var voice := LedgerStyle.pretty(instrument).to_upper()
	var vw := _font.get_string_size(voice, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14).x
	draw_string(_font, Vector2(c.x - vw * 0.5, c.y + 40.0), voice, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, LedgerStyle.INK_SOFT)


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
	var c := Vector2(size.x * 0.58, size.y * 0.70)
	draw_set_transform(c, deg_to_rad(-13.0), Vector2.ONE)
	var stamp := Color(LedgerStyle.DIRTY.r, LedgerStyle.DIRTY.g, LedgerStyle.DIRTY.b, 0.78)
	draw_rect(Rect2(-57.0, -21.0, 114.0, 42.0), stamp, false, 3.0)
	draw_rect(Rect2(-52.0, -16.0, 104.0, 32.0), stamp, false, 1.0)
	var w := _font.get_string_size("DONE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28).x
	draw_string(_font, Vector2(-w * 0.5, 10.0), "DONE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, stamp)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_pin() -> void:
	var p := Vector2(size.x * 0.5, 13.0)
	if is_glinting():
		var t := (sin(_pulse) + 1.0) * 0.5
		draw_circle(p, 12.0 + t * 9.0, Color(LedgerStyle.CLEAN.r, LedgerStyle.CLEAN.g, LedgerStyle.CLEAN.b, 0.42 * (1.0 - t)))
	var head := LedgerStyle.BRASS
	if is_owned():
		head = LedgerStyle.DIRTY
	elif face == Face.FACEDOWN:
		head = LedgerStyle.CARD_BACK_INK
	draw_circle(p, 9.0, head.darkened(0.45))
	draw_circle(p, 7.0, head)
	draw_circle(p + Vector2(-2.0, -2.0), 2.2, head.lightened(0.55))


# --- helpers ------------------------------------------------------------------


func _text(s: String, at: Vector2, px: int, col: Color) -> void:
	draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, col)


func _badge(s: String, bg: Color, fg: Color) -> void:
	var px := 18
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x + 16.0
	var box := Rect2(size.x - w - 14.0, size.y - 34.0, w, 26.0)
	draw_rect(box, bg)
	draw_string(_font, box.position + Vector2(8.0, 19.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, fg)
