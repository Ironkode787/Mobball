class_name InsertField
extends Node3D
## The playfield inserts (docs/19 §6, docs/20 §6): lamps under the clear coat that carry the
## board's state, one meaning each, with a shape or cadence cue as well as a colour.
##
##   * shot arrows at every entrance (lit by Jobs, the Commission, the Big Score…), Lucky's
##     the biggest
##   * the Empire Wheel: eight districts round the BIG SCORE centre
##   * the fuse: six inserts up the centre line, the Job timer
##   * the Take: ×2 ×3 ×4 ×5 ×8
##   * the can levels behind Lucky's: what a can pays, 1× 2× 4× 8×
##
## Words on a lamp are only ever as big as a phone can read (docs/20 §6): a multiplier or two
## words. The Wheel's districts are told apart by colour and named by the HUD.

enum Mode { OFF, PULSE, BLINK, SOLID }

const SHOTS: Array[StringName] = [&"getaway", &"beat_cop", &"staircase", &"nonnas", &"luckys",
		&"fat_tonys", &"wire", &"truck_route", &"alley"]
## Where each arrow sits and which way it points (plan space). The Alley's is on the plaza behind
## Lucky's: it is fed, not aimed at, and the arrow says where the ball is wanted.
const ARROWS := {
	&"getaway": [Vector2(-2.32, 0.08), Vector2(0.0, -1.0)],
	&"beat_cop": [Vector2(-1.70, -0.24), Vector2(-0.346, -0.938)],
	&"staircase": [Vector2(-1.22, -0.36), Vector2(-0.26, -0.966)],
	&"nonnas": [Vector2(-0.78, -1.36), Vector2(-0.196, -0.981)],
	&"luckys": [Vector2(-0.185, -0.453), Vector2(0.0, -1.0)],
	&"fat_tonys": [Vector2(0.41, -1.36), Vector2(0.196, -0.981)],
	&"wire": [Vector2(1.10, -0.50), Vector2(0.311, -0.950)],
	&"truck_route": [Vector2(1.94, 0.08), Vector2(0.0, -1.0)],
	&"alley": [Vector2(-0.185, -2.80), Vector2(0.0, -1.0)],
}
const DISTRICTS: PackedStringArray = ["ALLEY", "CORNER", "NUMBERS", "BLOCK", "CLUB", "DOCKS", "PENTHOUSE", "CITY HALL"]
const DISTRICT_COLORS: Array[Color] = [Color("D9C9A3"), Color("FF9A3D"), Color("F2D14B"), Color("FF4F7A"),
		Color("B37BFF"), Color("35D6C8"), Color("C79BFF"), Color("F5C542")]
const TAKE_LABELS: PackedStringArray = ["×2", "×3", "×4", "×5", "×8"]
const LEVEL_LABELS: PackedStringArray = ["1×", "2×", "4×", "8×"]
## Arrow size (plan units, tip to tail) and the one that owns the middle of the board.
const ARROW_SCALE := 1.35
const LUCKY_ARROW_SCALE := 1.9
const TAKE_RADIUS := 0.15
## Label sizes (Label3D font px at pixel_size LABEL_PIXEL): about 0.1 u of cap height.
const LABEL_PIXEL := 0.0016
const TAKE_FONT := 92
const LEVEL_FONT := 78
const CENTRE_FONT := 64
const Y := 0.003
const COL_EMBER := Color(1.0, 0.45, 0.15)     ## heat ember: the fuse and the bribe (docs/19 §6)
const WHEEL_HELD := 0.42

var _lib: MaterialLib = null
var _arrow_lamps: Dictionary = {}          ## shot -> StandardMaterial3D
var _arrow_sources: Dictionary = {}        ## shot -> {source: [mode, color, priority]}
var _wheel_lamps: Array[StandardMaterial3D] = []
var _wheel_modes: Array[int] = []
var _centre_lamp: StandardMaterial3D = null
var _centre_mode: int = Mode.OFF
var _fuse_lamps: Array[StandardMaterial3D] = []
var _fuse_fraction: float = 0.0
var _fuse_burning: bool = false
var _take_lamps: Array[StandardMaterial3D] = []
var _take_level: int = 0
var _level_lamps: Array[StandardMaterial3D] = []
var _can_level: int = 0
var _can_decay: float = 0.0
var _flash: Dictionary = {}                ## shot -> seconds of hit flash


func _ready() -> void:
	_lib = MaterialLib.shared()
	for shot: StringName in SHOTS:
		var spec: Array = ARROWS[shot]
		_arrow_lamps[shot] = _arrow(spec[0], spec[1], String(shot))
		_arrow_sources[shot] = {}
	_build_wheel()
	_build_fuse()
	_build_take()
	_build_levels()


## The arrow's outline, tip first, `k` times the base size (shared with the printed keyline).
static func arrow_points(at: Vector2, dir: Vector2, k: float) -> Dictionary:
	var d := dir.normalized()
	var side := Vector2(-d.y, d.x)
	return {
		"tip": at + d * 0.13 * k, "wing_l": at + side * 0.085 * k, "wing_r": at - side * 0.085 * k,
		"notch": at + d * 0.03 * k, "tail_l": at - d * 0.09 * k + side * 0.035 * k,
		"tail_r": at - d * 0.09 * k - side * 0.035 * k, "head_l": at + side * 0.035 * k,
		"head_r": at - side * 0.035 * k,
	}


static func arrow_scale(shot: StringName) -> float:
	return LUCKY_ARROW_SCALE if shot == &"luckys" else ARROW_SCALE


func _arrow(at: Vector2, dir: Vector2, label: String) -> StandardMaterial3D:
	var lamp := _lamp(Color.WHITE)
	var st := MeshLib.begin()
	st.set_normal(Vector3.UP)
	var a := arrow_points(at, dir, arrow_scale(StringName(label)))
	var tip: Vector2 = a["tip"]
	var wing_l: Vector2 = a["wing_l"]
	var wing_r: Vector2 = a["wing_r"]
	var notch: Vector2 = a["notch"]
	var tail_l: Vector2 = a["tail_l"]
	var tail_r: Vector2 = a["tail_r"]
	var head_l: Vector2 = a["head_l"]
	var head_r: Vector2 = a["head_r"]
	for tri: Array in [[tip, wing_r, notch], [tip, notch, wing_l], [head_l, tail_l, tail_r], [head_l, tail_r, head_r]]:
		for q: Vector2 in [tri[0], tri[2], tri[1]]:
			st.add_vertex(Vector3(q.x, Y, q.y))
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.finish(st, lamp)
	mi.name = "Arrow_%s" % label
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return lamp


func _lamp(color: Color) -> StandardMaterial3D:
	var m := _lib.lamp(color)
	m.albedo_color = color.darkened(0.78)
	m.albedo_color.a = 1.0
	m.roughness = 0.2
	m.metallic_specular = 0.8
	return m


## Newsprint with an ink outline, so it reads on a dark insert and a lit one alike.
func _label(text: String, at: Vector2, size: int, yaw: float = 0.0, color: Color = Color(0.96, 0.92, 0.84)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = LABEL_PIXEL
	l.modulate = color
	l.outline_size = int(round(float(size) * 0.14))
	l.outline_modulate = Color(0.05, 0.04, 0.03, 0.92)
	l.position = Vector3(at.x, Y + 0.002, at.y)
	l.rotation = Vector3(-PI * 0.5, yaw, 0.0)
	l.double_sided = false
	l.shaded = false
	add_child(l)
	return l


func _build_wheel() -> void:
	var c := Layout.WHEEL_CENTER
	var r_out := Layout.WHEEL_RADIUS
	var r_in := r_out * 0.52
	var n := DISTRICTS.size()
	for i in range(n):
		var lamp := _lamp(DISTRICT_COLORS[i])
		var st := MeshLib.begin()
		st.set_normal(Vector3.UP)
		var a0 := -PI * 0.5 + TAU * (float(i) - 0.5) / float(n) + 0.04
		var a1 := -PI * 0.5 + TAU * (float(i) + 0.5) / float(n) - 0.04
		var steps := 6
		for k in range(steps):
			var t0 := lerpf(a0, a1, float(k) / float(steps))
			var t1 := lerpf(a0, a1, float(k + 1) / float(steps))
			var p0 := c + Vector2(cos(t0), sin(t0)) * r_in
			var p1 := c + Vector2(cos(t1), sin(t1)) * r_in
			var p2 := c + Vector2(cos(t1), sin(t1)) * r_out
			var p3 := c + Vector2(cos(t0), sin(t0)) * r_out
			for q: Vector2 in [p0, p2, p1, p0, p3, p2]:
				st.add_vertex(Vector3(q.x, Y, q.y))
		var mi := MeshInstance3D.new()
		mi.mesh = MeshLib.finish(st, lamp)
		mi.name = "Wheel%d" % i
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_wheel_lamps.append(lamp)
		_wheel_modes.append(Mode.OFF)
	_centre_lamp = _lamp(Color(1.0, 0.82, 0.3))
	var cst := MeshLib.begin()
	MeshLib.disc(cst, Vector3(c.x, Y, c.y), r_in - 0.05, 28)
	var cm := MeshInstance3D.new()
	cm.mesh = MeshLib.finish(cst, _centre_lamp)
	cm.name = "BigScore"
	cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cm)
	_label("BIG\nSCORE", c, CENTRE_FONT)


func _build_fuse() -> void:
	for i in range(Layout.FUSE_AT.size()):
		var p: Vector2 = Layout.FUSE_AT[i]
		var lamp := _lamp(COL_EMBER)
		var st := MeshLib.begin()
		MeshLib.box(st, Vector3(p.x, Y - 0.004, p.y), Vector3(0.16, 0.008, 0.10))
		var mi := MeshInstance3D.new()
		mi.mesh = MeshLib.finish(st, lamp)
		mi.name = "Fuse%d" % i
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_fuse_lamps.append(lamp)


func _build_take() -> void:
	for i in range(Layout.TAKE_AT.size()):
		var p: Vector2 = Layout.TAKE_AT[i]
		var lamp := _lamp(Color(1.0, 0.78, 0.35))
		var st := MeshLib.begin()
		MeshLib.disc(st, Vector3(p.x, Y, p.y), TAKE_RADIUS, 24)
		var mi := MeshInstance3D.new()
		mi.mesh = MeshLib.finish(st, lamp)
		mi.name = "Take%d" % i
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_take_lamps.append(lamp)
		_label(TAKE_LABELS[i], p, TAKE_FONT)


func _build_levels() -> void:
	for i in range(Layout.CAN_LEVEL_AT.size()):
		var p: Vector2 = Layout.CAN_LEVEL_AT[i]
		var lamp := _lamp(Bumper.LEVEL_COLORS[i])
		var st := MeshLib.begin()
		MeshLib.box(st, Vector3(p.x, Y - 0.004, p.y), Vector3(0.20, 0.008, 0.15))
		var mi := MeshInstance3D.new()
		mi.mesh = MeshLib.finish(st, lamp)
		mi.name = "CanLevel%d" % i
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_level_lamps.append(lamp)
		_label(LEVEL_LABELS[i], p, LEVEL_FONT)


# ------------------------------------------------------------------ state -----


## One source's say on a shot arrow. The arrow shows the highest-priority source.
func light(shot: StringName, source: StringName, mode: int, color: Color, priority: int = 0) -> void:
	if not _arrow_sources.has(shot):
		return
	var srcs: Dictionary = _arrow_sources[shot]
	if mode == Mode.OFF:
		srcs.erase(source)
	else:
		srcs[source] = [mode, color, priority]


func clear_source(source: StringName) -> void:
	for shot: StringName in _arrow_sources:
		(_arrow_sources[shot] as Dictionary).erase(source)


func flash_shot(shot: StringName) -> void:
	_flash[shot] = 0.35


func set_wheel(index: int, mode: int) -> void:
	if index >= 0 and index < _wheel_modes.size():
		_wheel_modes[index] = mode


func set_big_score(mode: int) -> void:
	_centre_mode = mode


func set_fuse(fraction: float, burning: bool) -> void:
	_fuse_fraction = clampf(fraction, 0.0, 1.0)
	_fuse_burning = burning


func set_take(level: int) -> void:
	_take_level = clampi(level, 0, _take_lamps.size())


func set_can_level(level: int, decay_fraction: float) -> void:
	_can_level = level
	_can_decay = decay_fraction


func arrow_mode(shot: StringName) -> int:
	var top := _top(shot)
	return int(top[0]) if not top.is_empty() else Mode.OFF


func _top(shot: StringName) -> Array:
	var best: Array = []
	var srcs: Dictionary = _arrow_sources.get(shot, {})
	for key: StringName in srcs:
		var v: Array = srcs[key]
		if best.is_empty() or int(v[2]) > int(best[2]):
			best = v
	return best


static func energy(mode: int, t: float, phase: float = 0.0) -> float:
	match mode:
		Mode.PULSE:
			return 0.35 + 0.9 * (0.5 + 0.5 * sin((t + phase) * TAU * 0.8))
		Mode.BLINK:
			return 2.4 if fmod(t * 3.0 + phase, 1.0) < 0.5 else 0.15
		Mode.SOLID:
			return 1.8
	return 0.0


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var i := 0
	for shot: StringName in SHOTS:
		var lamp: StandardMaterial3D = _arrow_lamps[shot]
		var top := _top(shot)
		var f := float(_flash.get(shot, 0.0))
		if f > 0.0:
			_flash[shot] = maxf(f - delta, 0.0)
		if top.is_empty():
			lamp.emission_energy_multiplier = f * 6.0
		else:
			var c: Color = top[1]
			lamp.emission = c
			lamp.albedo_color = c.darkened(0.78)
			lamp.emission_energy_multiplier = energy(int(top[0]), t, float(i) * 0.09) + f * 6.0
		i += 1
	for k in range(_wheel_lamps.size()):
		var m := _wheel_modes[k]
		# a district the empire holds is a steady low glow; only what is happening now is bright
		var held := 0.55 if m == Mode.PULSE else (WHEEL_HELD if m == Mode.SOLID else 1.0)
		_wheel_lamps[k].emission_energy_multiplier = energy(m, t, float(k) * 0.12) * held
	_centre_lamp.emission_energy_multiplier = energy(_centre_mode, t) * (1.4 if _centre_mode == Mode.BLINK else 1.0)
	var lit := int(ceil(_fuse_fraction * float(_fuse_lamps.size()) - 0.001))
	var hurry := _fuse_burning and _fuse_fraction < 0.34
	for k in range(_fuse_lamps.size()):
		var on := k < lit
		var e := 0.0
		if on:
			e = energy(Mode.BLINK, t) if hurry and k == lit - 1 else (1.6 if _fuse_burning else 0.6)
		_fuse_lamps[k].emission_energy_multiplier = e
	for k in range(_take_lamps.size()):
		_take_lamps[k].emission_energy_multiplier = 1.8 if k < _take_level else 0.0
	for k in range(_level_lamps.size()):
		var e2 := 0.0
		if k < _can_level:
			e2 = 1.2
		elif k == _can_level:
			e2 = 1.6 if _can_level > 0 else 0.9
			if _can_level > 0 and _can_decay < 0.3:
				e2 = energy(Mode.BLINK, t)
		_level_lamps[k].emission_energy_multiplier = e2
