class_name PaperKit
extends RefCounted
## Paperback-noir UI primitives. Typography and controls resolve through Presentation.
##
## The M1 screens are functional, not finished: newsprint on ink, brass rules, reserved
## colors used only for what they mean. Everything is built in code so the .tscn files stay
## stubs and the layout is one source of truth.
##
## No Unicode dingbats anywhere — the default theme font has no star glyph, so ☆ is drawn
## (see `draw_star`) rather than typed.

const FONT_HUGE := 78
const FONT_TITLE := 56
const FONT_BIG := 44
const FONT_BODY := 34
const FONT_SMALL := 28

const PAD := 28.0
const RULE := 3.0


static func label(text: String, size: int = FONT_BODY, color: Color = Feel.COL_NEWSPRINT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_override("font", _font_for_label(size))
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A pressable slab: ink body, brass rule, newsprint type.
static func button(text: String, size: int = FONT_BIG, accent: Color = Feel.COL_BRASS) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", Presentation.theme.font_for(
			&"headline" if size >= FONT_BIG else &"ui"))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Feel.COL_NEWSPRINT)
	b.add_theme_color_override("font_hover_color", accent)
	b.add_theme_color_override("font_pressed_color", Feel.COL_INK)
	b.add_theme_stylebox_override("normal", box(Feel.COL_INK.lightened(0.10), accent))
	b.add_theme_stylebox_override("hover", box(Feel.COL_INK.lightened(0.18), accent))
	b.add_theme_stylebox_override("pressed", box(accent, accent))
	b.add_theme_stylebox_override("disabled", box(Feel.COL_INK.lightened(0.04), accent.darkened(0.6)))
	b.custom_minimum_size = Vector2(0.0, 96.0)
	b.focus_mode = Control.FOCUS_ALL
	return b


static func _font_for_label(size: int) -> Font:
	if size >= FONT_TITLE:
		return Presentation.theme.font_for(&"headline")
	if size <= FONT_SMALL:
		return Presentation.theme.font_for(&"annotation")
	return Presentation.theme.font_for(&"body")


static func box(fill: Color, border: Color, width: float = RULE) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(int(width))
	s.set_corner_radius_all(6)
	s.content_margin_left = PAD * 0.6
	s.content_margin_right = PAD * 0.6
	s.content_margin_top = PAD * 0.35
	s.content_margin_bottom = PAD * 0.35
	return s


static func panel(fill: Color = Feel.COL_INK.lightened(0.06),
		border: Color = Feel.COL_BRASS.darkened(0.35)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(fill, border))
	return p


static func rule(color: Color = Feel.COL_BRASS.darkened(0.4), height: float = RULE) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0.0, height)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A five-point brass star, drawn because the default font has no glyph for one.
static func draw_star(on: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var r := radius if i % 2 == 0 else radius * 0.44
		var a := -PI * 0.5 + float(i) * PI / 5.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	on.draw_colored_polygon(pts, color)
