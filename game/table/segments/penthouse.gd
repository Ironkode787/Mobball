class_name Penthouse
extends Node3D
## THE PENTHOUSE (R6): a raised room in the top-left corner, reached from the Club deck by
## the Penthouse stairs, a wireform across the back of the machine. Two chair targets
## around the long table, the Sit-Down saucer, and the return wireform down the left side.

signal chair_taken(index: int)
signal chairs_completed()
signal sitdown_entered()
signal penthouse_entered(speed: float)
signal penthouse_returned()

const ID_PENTHOUSE := &"penthouse"
const ID_CHAIRS := &"commission_chairs"
const ID_SITDOWN := &"sitdown_saucer"
const ID_STAIRS := &"penthouse_stairs"

const ROOM_H := 0.90
const ROOM_LEFT := -2.45
const ROOM_RIGHT := -0.55
const ROOM_TOP := -5.25
const ROOM_BOTTOM := -3.60
const WALL_THICK := 0.06
const WALL_HEIGHT := 0.26
const CHAIR_LENGTH := 0.16
const CHAIR_THICK := 0.05
## Two chairs inside the City Hall ring, facing the front, raked so that anything rolling
## back out of the ring's mouth slides off their backs into the gap between them and on
## down the room — nothing can rest behind them.
const CHAIR_ROW_A: Array = [Vector2(-1.90, -4.36), Vector2(-1.10, -4.36)]
const CHAIR_ROW_A_RAKE: PackedFloat32Array = [-20.0, 20.0]
const CHAIR_ROW_B: Array = []
const CHAIR_ROW_B_RAKE: PackedFloat32Array = [-16.0, 16.0]
const TABLE_AT := Vector2(-1.5, -4.48)
const TABLE_SIZE := Vector2(0.9, 0.3)
const SITDOWN_AT := Vector2(-2.15, -3.95)
const SITDOWN_R := 0.15
const SITDOWN_HOLD := 1.0
const SITDOWN_EJECT := Vector2(0.8, -0.6)
const SITDOWN_SPEED := 7.0
## The stairs: a mini-flipper shot off the Club deck, over the back, into this room.
const STAIR_MOUTH := ClubDeck.PENTHOUSE_MOUTH
const STAIR_MOUTH_SIZE := Vector2(0.34, 0.3)
const STAIR_ENTRY_SPEED := 4.0
## Leaves the deck diagonally through its top-left corner, sweeps along the back of the
## machine in one long arc and comes into the room through the open corner behind its
## back wall, level with the floor — the stairs never climb, so the ball keeps its pace.
const STAIR_PATH: PackedVector3Array = [
	Vector3(0.82, 0.90, -4.98), Vector3(0.62, 0.94, -5.18), Vector3(0.38, 1.00, -5.38),
	Vector3(0.08, 1.03, -5.50), Vector3(-0.25, 1.02, -5.54), Vector3(-0.55, 1.00, -5.44),
	Vector3(-0.85, 0.97, -5.24), Vector3(-1.12, 0.94, -5.06), Vector3(-1.28, 0.92, -4.96),
	Vector3(-1.40, 0.92, -4.94),
]
## A short chute off the room's front-left corner that drops the ball into the left lane
## above the spinner: it rolls down past the Getaway Loop entry and into the Docks.
const RETURN_PATH: PackedVector3Array = [
	Vector3(-2.20, 0.87, -3.58), Vector3(-2.34, 0.74, -3.34), Vector3(-2.38, 0.58, -3.10),
	Vector3(-2.38, 0.46, -2.90),
]
const CHUTE_LEFT := -2.40
const CHUTE_RIGHT := -1.98
const COL_GLASS := Color("2A3550")

var chairs: TargetBank = null
var sitdown: HoldSaucer = null
var stairs: RampLane = null
var return_lane: RampLane = null

var _present: bool = false
var _floor: StaticBody3D = null
var _shell: WallPiece = null
var _ball: Ball = null
var _look: Node3D = null


func _ready() -> void:
	_build_floor()
	_build_shell()
	_build_chairs()
	_build_sitdown()
	_build_ramps()
	_build_look()


func _build_floor() -> void:
	_floor = WallBuilder.make_body("RoomFloor", Feel.LAYER_WALLS,
			Feel.make_material(Feel.FELT_FRICTION, Feel.FELT_BOUNCE))
	add_child(_floor)
	var w := ROOM_RIGHT - ROOM_LEFT
	var d := ROOM_BOTTOM - ROOM_TOP
	var center := Vector3((ROOM_LEFT + ROOM_RIGHT) * 0.5, ROOM_H - 0.06, (ROOM_TOP + ROOM_BOTTOM) * 0.5)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, 0.12, d)
	cs.shape = box
	cs.position = center
	_floor.add_child(cs)
	var lib := MaterialLib.shared()
	var carpet := lib.plastic(Color("3A2E5C"), 0.9)
	var st := MeshLib.begin()
	MeshLib.box(st, center, Vector3(w, 0.12, d), 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.finish(st, carpet)
	mi.name = "Slab"
	_floor.add_child(mi)
	var posts := MeshLib.begin()
	for i in range(4):
		var x := lerpf(ROOM_LEFT, ROOM_RIGHT, (float(i) + 0.5) / 4.0)
		MeshLib.post(posts, Vector2(x, ROOM_BOTTOM - 0.04), 0.035, ROOM_H - 0.12, 0.0, 10)
	var pm := MeshInstance3D.new()
	pm.mesh = MeshLib.finish(posts, lib.brass_dark())
	_floor.add_child(pm)


func _build_shell() -> void:
	_shell = WallPiece.new(WALL_HEIGHT, ROOM_H, MaterialLib.shared().plastic(COL_GLASS.lightened(0.2), 0.2),
			MaterialLib.shared().brass())
	_shell.name = "PenthouseShell"
	add_child(_shell)
	var t := WALL_THICK
	# the back wall stops short of the right corner: the stairs come in through that gap
	_shell.bar(Vector2(ROOM_LEFT, ROOM_TOP), Vector2(-1.30, ROOM_TOP), t)
	_shell.bar(Vector2(ROOM_LEFT, ROOM_TOP), Vector2(ROOM_LEFT, ROOM_BOTTOM), t)
	# right wall: open from the top corner down to where the stairs land
	_shell.bar(Vector2(ROOM_RIGHT, -5.10), Vector2(ROOM_RIGHT, ROOM_BOTTOM), t)
	# bottom wall either side of the return chute (bottom-left)
	_shell.bar(Vector2(CHUTE_RIGHT, ROOM_BOTTOM), Vector2(ROOM_RIGHT, ROOM_BOTTOM), t)
	# a raked floor lip that rolls everything toward the chute
	_shell.bar(Vector2(ROOM_RIGHT - 0.03, -3.75), Vector2(-1.6, -3.62), 0.04)


func _build_chairs() -> void:
	chairs = TargetBank.new()
	chairs.name = "CommissionChairs"
	chairs.id = ID_CHAIRS
	chairs.group = TableScore.GROUP_PENTHOUSE
	chairs.target_value = TableScore.PENTHOUSE_CHAIR
	chairs.complete_value = 0.0
	chairs.reset_seconds = 8.0
	add_child(chairs)
	for i in range(CHAIR_ROW_A.size()):
		chairs.add_target(_make_chair(i, CHAIR_ROW_A[i], CHAIR_ROW_A_RAKE[i], Vector2(0.0, 1.0)))
	for i in range(CHAIR_ROW_B.size()):
		chairs.add_target(_make_chair(CHAIR_ROW_A.size() + i, CHAIR_ROW_B[i], CHAIR_ROW_B_RAKE[i], Vector2(0.0, -1.0)))
	chairs.target_struck.connect(func(index: int) -> void:
		AudioDirector.play(&"chair_take")
		chair_taken.emit(index))
	chairs.bank_completed.connect(func() -> void: chairs_completed.emit())


func _make_chair(index: int, at: Vector2, rake_deg: float, face: Vector2) -> StandupTarget:
	var t := StandupTarget.new()
	t.name = "Chair%d" % (index + 1)
	t.thickness = CHAIR_THICK
	t.lamp_color = Feel.COL_VIOLET.lerp(Color.WHITE, 0.3)
	t.configure(StringName("%s_%d" % [ID_CHAIRS, index + 1]), at, face.rotated(deg_to_rad(rake_deg)), CHAIR_LENGTH)
	t.position.y = ROOM_H
	return t


func _build_sitdown() -> void:
	sitdown = HoldSaucer.new()
	sitdown.name = "SitDown"
	sitdown.hold_seconds = SITDOWN_HOLD
	sitdown.eject_speed = SITDOWN_SPEED
	sitdown.configure(ID_SITDOWN, SITDOWN_AT, SITDOWN_R, SITDOWN_EJECT, ROOM_H)
	add_child(sitdown)
	sitdown.captured.connect(func() -> void:
		AudioDirector.play(&"sitdown")
		sitdown_entered.emit())


func _build_ramps() -> void:
	stairs = RampLane.new()
	stairs.name = "PenthouseStairs"
	stairs.entry_speed = STAIR_ENTRY_SPEED
	stairs.entry_size = STAIR_MOUTH_SIZE
	stairs.flare_width = 0.46
	stairs.color = Feel.COL_BRASS.lightened(0.10)
	stairs.configure(ID_STAIRS, STAIR_PATH)
	add_child(stairs)
	stairs.crested.connect(_on_stairs_crested)
	return_lane = RampLane.new()
	return_lane.name = "PenthouseReturn"
	return_lane.entry_speed = -100000.0
	return_lane.wall_height = 0.26         # the City Hall ring passes right over this chute
	return_lane.entry_size = Vector2(CHUTE_RIGHT - CHUTE_LEFT, 0.25)
	return_lane.color = Feel.COL_NEON_TEAL.darkened(0.2)
	return_lane.configure(&"penthouse_return", RETURN_PATH)
	add_child(return_lane)
	return_lane.crested.connect(_on_returned)


func _build_look() -> void:
	var lib := MaterialLib.shared()
	_look = Node3D.new()
	_look.name = "Look"
	add_child(_look)
	var top := BoxMesh.new()
	top.size = Vector3(TABLE_SIZE.x, 0.05, TABLE_SIZE.y)
	var tm := MeshInstance3D.new()
	tm.mesh = top
	tm.material_override = lib.wood()
	tm.position = Layout.p3(TABLE_AT, ROOM_H + 0.30)
	_look.add_child(tm)
	var legs := MeshLib.begin()
	for sx in [-0.42, 0.42]:
		for sz in [-0.35, 0.35]:
			MeshLib.post(legs, TABLE_AT + Vector2(TABLE_SIZE.x * sx, TABLE_SIZE.y * sz), 0.02, 0.28, ROOM_H, 6)
	var lm := MeshInstance3D.new()
	lm.mesh = MeshLib.finish(legs, lib.wood_dark())
	_look.add_child(lm)
	var sign := TextMesh.new()
	sign.text = "THE PENTHOUSE"
	sign.font = load("res://assets/fonts/Oswald-SemiBold.ttf")
	sign.font_size = 56
	sign.pixel_size = 0.0058
	sign.depth = 0.03
	var sm := MeshInstance3D.new()
	sm.mesh = sign
	sm.material_override = lib.neon(Feel.COL_VIOLET, 2.4)
	sm.position = Vector3((ROOM_LEFT + ROOM_RIGHT) * 0.5, ROOM_H + 0.62, ROOM_TOP + 0.05)
	_look.add_child(sm)
	var light := OmniLight3D.new()
	light.light_color = Feel.COL_VIOLET
	light.light_energy = 1.1
	light.omni_range = 2.6
	light.shadow_enabled = false
	light.position = Vector3((ROOM_LEFT + ROOM_RIGHT) * 0.5, ROOM_H + 0.9, ROOM_TOP + 0.7)
	_look.add_child(light)


func set_ball(b: Ball) -> void:
	_ball = b
	for holder: Node in [sitdown, stairs, return_lane]:
		if holder != null:
			holder.call(&"set_ball", b)


func pieces() -> Array[Dictionary]:
	return [
		{"ids": [ID_CHAIRS], "node": chairs},
		{"ids": [ID_SITDOWN], "node": sitdown},
		{"ids": [ID_STAIRS], "node": stairs},
	]


func bounds() -> AABB:
	return AABB(Vector3(ROOM_LEFT, ROOM_H - 0.15, ROOM_TOP - 0.2), Vector3(ROOM_RIGHT - ROOM_LEFT, 1.2, ROOM_BOTTOM - ROOM_TOP + 0.2))


func chairs_standing() -> int:
	if chairs == null:
		return 0
	return chairs.targets().size() - chairs.marked_count()


func holds_ball() -> bool:
	if sitdown != null and sitdown.holds_ball():
		return true
	return (stairs != null and stairs.riding()) or (return_lane != null and return_lane.riding())


func search_exempt(ball: Ball) -> bool:
	if ball == null or not is_instance_valid(ball) or not _present:
		return false
	return BallHold.is_held(ball) and holds_ball()


func _on_stairs_crested(speed: float) -> void:
	AudioDirector.play(&"staircase_crest")
	TableScore.earn(TableScore.GROUP_RAMPS, TableScore.RAMP_CLIMB, ID_STAIRS, _ball, speed)
	penthouse_entered.emit(speed)


func _on_returned(_speed: float) -> void:
	AudioDirector.play(&"wall_tap")
	penthouse_returned.emit()


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	if _floor != null:
		_floor.collision_layer = Feel.LAYER_WALLS if active else 0
	for piece: Node in [_shell, return_lane]:
		if piece != null:
			Dormant.apply(piece, active)
	if not active:
		_release_everything()


func is_hardware_active() -> bool:
	return _present


func _release_everything() -> void:
	var was_holding := holds_ball()
	for holder: Node in [sitdown, stairs, return_lane]:
		if holder != null and holder.has_method(&"set_hardware_active"):
			holder.call(&"set_hardware_active", false)
	if was_holding and _ball != null and is_instance_valid(_ball):
		BallHold.release(_ball, RETURN_PATH[RETURN_PATH.size() - 1] + Vector3(0, Feel.BALL_RADIUS, 0), Vector3.ZERO)
