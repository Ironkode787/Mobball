class_name Alley
extends Node3D
## THE ALLEY (docs/19 §3.2): the Space Cadet nest. Three trash cans in a tight triangle (two
## up, one down) walled in on both sides, with the three Drop-Off lanes directly above.
##
## The board develops here: roll all three lanes and every can goes up a level (Trash Can →
## Dumpster → Armored Truck → Vault); a level decays after Feel.CAN_LEVEL_DECAY without another
## completion. The flipper buttons rotate the lit lanes (lane change). The same lanes are the
## Drop-Off skill shot: the flow lights one (`set_skill_lane`) and hears which one the plunge
## took (`lane_rolled`).

signal lane_rolled(index: int, was_lit: bool)
signal lanes_completed()
signal level_changed(level: int)

const ID_CAN_2 := &"bumper_2"
const ID_CAN_3 := &"bumper_3"
const ID_LANES := &"rollovers"

var cans: Array[Bumper] = []
var lanes: Array[Rollover] = []
var level: int = 0
var lane_lit: Array[bool] = [false, false, false]
## Lit lanes stay lit when rolled again (the Ledger's Full Load); by default a lit lane rolled
## again stays lit too — completing needs the other two, which is what lane change is for.
var decay_seconds: float = Feel.CAN_LEVEL_DECAY

var _skill_lane: int = -1
var _decay_left: float = 0.0
var _lib: MaterialLib = null
var _skill_lamps: Array[StandardMaterial3D] = []
var _flash: float = 0.0


func _ready() -> void:
	_lib = MaterialLib.shared()
	_build_walls()
	_build_cans()
	_build_lanes()
	Events.flipper_fired.connect(_on_flipper)


func _build_walls() -> void:
	var walls := WallPiece.new(Layout.WALL_HEIGHT, 0.0, _lib.brass_dark(), _lib.brass())
	walls.name = "NestWalls"
	add_child(walls)
	var mx := Layout.MIRROR_X
	for s: float in [-1.0, 1.0]:
		walls.bar(Vector2(mx + s * Layout.NEST_HALF, Layout.NEST_TOP),
				Vector2(mx + s * Layout.NEST_HALF, Layout.NEST_BOTTOM), Layout.GUIDE_THICK)
		# shoulders from the outer lane guides down to the side walls keep the lanes' spill in
		var gx: float = Layout.DROPOFF_GUIDE_X[0] if s < 0.0 else Layout.DROPOFF_GUIDE_X[3]
		walls.bar(Vector2(gx, Layout.NEST_TOP), Vector2(mx + s * Layout.NEST_HALF, Layout.NEST_SHOULDER_Z),
				Layout.GUIDE_THICK)
	# the lane block: four guides from the ring road's inner edge down to the nest
	var guides := WallPiece.new(Layout.GUIDE_HEIGHT, 0.0, _lib.brass_dark(), _lib.brass())
	guides.name = "DropOffGuides"
	add_child(guides)
	for gx: float in Layout.DROPOFF_GUIDE_X:
		guides.bar(Vector2(gx, Layout.ring_top_z(gx) + 0.03), Vector2(gx, Layout.NEST_TOP), Layout.GUIDE_THICK)
		guides.post(Vector2(gx, Layout.NEST_TOP), Layout.POST_RADIUS)


func _build_cans() -> void:
	for i in range(Layout.BUMPER_AT.size()):
		var b := Bumper.new()
		b.id = StringName("bumper_%d" % (i + 1))
		b.group = TableScore.GROUP_BUMPERS
		b.value = int(TableScore.BUMPER)
		b.position = Layout.p3(Layout.BUMPER_AT[i])
		b.name = "Can%d" % (i + 1)
		add_child(b)
		cans.append(b)


func _build_lanes() -> void:
	for i in range(Layout.DROPOFF_X.size()):
		var r := Rollover.new()
		r.name = "DropOff%d" % (i + 1)
		r.configure(StringName("rollover_%d" % (i + 1)), i, Vector2(Layout.DROPOFF_X[i], Layout.DROPOFF_ROLLOVER_Z))
		add_child(r)
		r.rolled.connect(_on_lane)
		lanes.append(r)
	# the Drop-Off skill-shot window: a small arrow insert at the top of each lane
	for i in range(Layout.DROPOFF_X.size()):
		var lamp := _lib.lamp(Color(1.0, 0.78, 0.30))
		lamp.emission_energy_multiplier = 0.0
		var st := MeshLib.begin()
		var x: float = Layout.DROPOFF_X[i]
		var z := Layout.DROPOFF_ROLLOVER_Z - 0.17
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(x, 0.004, z - 0.07))
		st.add_vertex(Vector3(x + 0.07, 0.004, z + 0.05))
		st.add_vertex(Vector3(x - 0.07, 0.004, z + 0.05))
		var mi := MeshInstance3D.new()
		mi.mesh = MeshLib.finish(st, lamp)
		mi.name = "SkillArrow%d" % (i + 1)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_skill_lamps.append(lamp)


## The cans the table's owner has bought: the first one is the machine as found.
func cans_live() -> int:
	var n := 0
	for c in cans:
		if c.is_hardware_active():
			n += 1
	return n


func set_skill_lane(index: int) -> void:
	_skill_lane = index


func skill_lane() -> int:
	return _skill_lane


func _on_lane(index: int, _was_lit: bool) -> void:
	var skill := index == _skill_lane
	lane_rolled.emit(index, skill)
	if not lanes[index].is_hardware_active():
		return
	lane_lit[index] = true
	_apply_lane_lamps()
	if lane_lit.count(true) >= lane_lit.size():
		_complete()


func _complete() -> void:
	for i in range(lane_lit.size()):
		lane_lit[i] = false
	_flash = 1.0
	_apply_lane_lamps()
	lanes_completed.emit()
	AudioDirector.play(&"knocker")
	raise_level()


func raise_level(steps: int = 1) -> void:
	var was := level
	level = clampi(level + steps, 0, Feel.CAN_LEVEL_MAX)
	_decay_left = decay_seconds
	if level != was:
		_apply_level()
		level_changed.emit(level)


func reset_night() -> void:
	level = 0
	_decay_left = 0.0
	for i in range(lane_lit.size()):
		lane_lit[i] = false
	_apply_level()
	_apply_lane_lamps()


func _apply_level() -> void:
	for c in cans:
		c.set_level(level)


func _apply_lane_lamps() -> void:
	for i in range(lanes.size()):
		lanes[i].set_lit(lane_lit[i])


## Lane change: the flipper buttons rotate the lit lanes (left button left, right button right),
## the Drop-Off's lit lane with them — steering it under a plunge is the skill shot.
func _on_flipper(side: StringName) -> void:
	if not is_visible_in_tree() or not lanes[0].is_hardware_active():
		return
	var lit := lane_lit.duplicate()
	var n := lit.size()
	for i in range(n):
		var from := (i + 1) % n if side == &"left" else (i - 1 + n) % n
		lane_lit[i] = lit[from]
	if _skill_lane >= 0:
		_skill_lane = (_skill_lane + (-1 if side == &"left" else 1) + n) % n
	_apply_lane_lamps()


func _physics_process(delta: float) -> void:
	if level > 0 and decay_seconds > 0.0:
		_decay_left -= delta
		if _decay_left <= 0.0:
			level -= 1
			_decay_left = decay_seconds
			_apply_level()
			level_changed.emit(level)


func decay_fraction() -> float:
	if level <= 0 or decay_seconds <= 0.0:
		return 0.0
	return clampf(_decay_left / decay_seconds, 0.0, 1.0)


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 1.5, 0.0)
	var t := Time.get_ticks_msec() * 0.001
	for i in range(_skill_lamps.size()):
		var on := 1.0 if i == _skill_lane and fmod(t * 3.0, 1.0) < 0.6 else 0.0
		_skill_lamps[i].emission_energy_multiplier = on * 2.2 + _flash * 2.0
