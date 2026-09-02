class_name Storefront
extends Node3D
## A protection racket as pinball hardware: a three-bank of drop targets in front of a shop.
## Knock the bank down and the shutters open — roll through the doorway to collect minutes of
## that racket's idle income. Lucky's doorway also washes money (laundromat_loop).
##
## Local frame: targets along +X, the ball approaches along +Z, the shop stands at -Z.

signal collected(id: StringName, amount: BigMoney)
signal washed(id: StringName)
signal door_opened(id: StringName)
signal door_closed(id: StringName)

enum State { ARMED, OPEN, COOLDOWN }

const TARGET_PITCH := 0.26
const TARGET_LENGTH := 0.22
const DOOR_DEPTH := 0.36
const WASH_COOLDOWN := 1.6
const ART := {
	&"storefront_laundromat": &"front.laundromat",
	&"storefront_pizzeria": &"front.pizzeria",
	&"storefront_pawn": &"front.pawn",
}
const NEON := {
	&"storefront_laundromat": Color("2EE6D6"),
	&"storefront_pizzeria": Color("FF2E63"),
	&"storefront_pawn": Color("FFC341"),
}

@export var id: StringName = &"storefront"

var open_seconds: float = 6.0
var rearm_seconds: float = 20.0
var sign_text: StringName = &"SHOP"
var bank_enabled: bool = true
var wash_enabled: bool = false

var _targets: Array[DropTarget] = []
var _door: Area3D = null
var _state: State = State.ARMED
var _timer: float = 0.0
var _wash_cool: float = 0.0
var _present: bool = true
var _glow: float = 0.0
var _door_lamp: StandardMaterial3D = null
var _neon: StandardMaterial3D = null
var _light: OmniLight3D = null


func configure(p_id: StringName, center: Vector2, facing: Vector2, rake_deg: float,
		p_sign: StringName) -> void:
	id = p_id
	position = Layout.p3(center)
	sign_text = p_sign
	rotation.y = Layout.yaw_facing(facing.normalized()) + deg_to_rad(rake_deg)


func half_span() -> float:
	return TARGET_PITCH + TARGET_LENGTH * 0.5


func _ready() -> void:
	for i in range(3):
		var t := DropTarget.new()
		t.name = "Target%d" % (i + 1)
		t.configure(StringName("%s_t%d" % [id, i + 1]),
				Vector2((float(i) - 1.0) * TARGET_PITCH, 0.0), Vector2(0.0, 1.0), TARGET_LENGTH)
		add_child(t)
		t.dropped.connect(_on_target_dropped)
		_targets.append(t)
	_door = Area3D.new()
	_door.name = "Door"
	_door.collision_layer = Feel.LAYER_ZONES
	_door.collision_mask = Feel.LAYER_BALL
	_door.monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(half_span() * 2.0, 0.5, DOOR_DEPTH)
	cs.shape = box
	cs.position = Vector3(0.0, 0.25, -DOOR_DEPTH * 0.5 - 0.08)
	_door.add_child(cs)
	add_child(_door)
	_door.body_entered.connect(_on_door_entered)
	_build_look()
	apply_build()


func _build_look() -> void:
	var lib := MaterialLib.shared()
	var span := half_span() * 2.0 + 0.2
	var depth := 0.34
	var front_z := -(DOOR_DEPTH + 0.08 + 0.14)
	var height := 0.62
	var neon_col: Color = NEON.get(id, Color("FF2E63"))
	# the shop: a block with the storefront art on its face and a lit sign box on the roof
	var st := MeshLib.begin()
	MeshLib.box(st, Vector3(0.0, height * 0.5, front_z - depth * 0.5), Vector3(span, height, depth), 0.6)
	var building := MeshInstance3D.new()
	building.mesh = MeshLib.finish(st, lib.wood())
	building.name = "Building"
	add_child(building)
	var art_key: StringName = ART.get(id, &"")
	var tex: Texture2D = null
	if art_key != &"" and Presentation != null and Presentation.art != null:
		tex = Presentation.art.resolve(art_key, null, false)
	if tex != null:
		var quad := PlaneMesh.new()
		var w := span * 0.94
		quad.size = Vector2(w, w * float(tex.get_height()) / float(tex.get_width()))
		quad.orientation = PlaneMesh.FACE_Z
		var facade := MeshInstance3D.new()
		facade.mesh = quad
		facade.material_override = lib.art(tex, 0.45)
		facade.position = Vector3(0.0, quad.size.y * 0.5 + 0.02, front_z + 0.012)
		facade.name = "Facade"
		add_child(facade)
	# side pilasters and a roof cornice in brass: the building reads as a building
	var trim := MeshLib.begin()
	for sx in [-1.0, 1.0]:
		MeshLib.box(trim, Vector3(sx * (span * 0.5 + 0.02), height * 0.5, front_z - depth * 0.5),
				Vector3(0.05, height + 0.02, depth + 0.06))
	MeshLib.box(trim, Vector3(0.0, height + 0.02, front_z - depth * 0.5), Vector3(span + 0.1, 0.05, depth + 0.08))
	var trim_mi := MeshInstance3D.new()
	trim_mi.mesh = MeshLib.finish(trim, lib.brass_dark())
	trim_mi.name = "Trim"
	add_child(trim_mi)
	# doorway threshold lamp
	_door_lamp = lib.lamp(neon_col.lerp(Color.WHITE, 0.25))
	var door := BoxMesh.new()
	door.size = Vector3(span * 0.5, 0.012, DOOR_DEPTH * 0.6)
	var dm := MeshInstance3D.new()
	dm.mesh = door
	dm.material_override = _door_lamp
	dm.position = Vector3(0.0, 0.006, -(DOOR_DEPTH * 0.5 + 0.08))
	dm.name = "Threshold"
	add_child(dm)
	# neon sign on the roof
	var sign := TextMesh.new()
	sign.text = String(sign_text)
	sign.font = load("res://assets/fonts/Oswald-SemiBold.ttf")
	sign.font_size = 64
	sign.pixel_size = 0.0055
	sign.depth = 0.03
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_neon = lib.neon(neon_col, 2.6).duplicate() as StandardMaterial3D
	var sm := MeshInstance3D.new()
	sm.mesh = sign
	sm.material_override = _neon
	sm.position = Vector3(0.0, height + 0.24, front_z - 0.02)
	sm.name = "Neon"
	add_child(sm)
	var backer := BoxMesh.new()
	backer.size = Vector3(span * 0.92, 0.36, 0.04)
	var bk := MeshInstance3D.new()
	bk.mesh = backer
	bk.material_override = lib.ink()
	bk.position = Vector3(0.0, height + 0.24, front_z - 0.06)
	bk.name = "SignBacker"
	add_child(bk)
	_light = OmniLight3D.new()
	_light.light_color = neon_col
	_light.light_energy = 1.0
	_light.omni_range = 2.2
	_light.omni_attenuation = 1.4
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, height + 0.5, front_z + 0.3)
	_light.name = "NeonLight"
	add_child(_light)


func apply_build() -> void:
	for t in _targets:
		t.set_hardware_active(_present and bank_enabled)
	if not bank_enabled:
		_state = State.OPEN
		_timer = -1.0
	elif _state == State.OPEN and _timer < 0.0:
		_close(true)
	_apply_door()


func is_open() -> bool:
	return _state == State.OPEN


func state_name() -> StringName:
	match _state:
		State.OPEN:
			return &"open"
		State.COOLDOWN:
			return &"cooldown"
		_:
			return &"armed"


func down_count() -> int:
	var n := 0
	for t in _targets:
		if t.down:
			n += 1
	return n


func targets() -> Array[DropTarget]:
	return _targets


func _on_target_dropped(_t: DropTarget) -> void:
	if not _present or not bank_enabled or _state != State.ARMED:
		return
	if down_count() < _targets.size():
		return
	_state = State.OPEN
	_timer = open_seconds
	_glow = 1.0
	_apply_door()
	AudioDirector.play(&"drop_bank_down")
	door_opened.emit(id)


func _on_door_entered(body: Node3D) -> void:
	if not (body is Ball) or not _present:
		return
	var ball := body as Ball
	if wash_enabled and _wash_cool <= 0.0:
		_wash_cool = WASH_COOLDOWN
		AudioDirector.play(&"laundromat_wash")
		TableScore.hit(&"laundromat_loop", ball)
		washed.emit(id)
	collect_now(ball)


func collect_now(ball: Node3D = null) -> BigMoney:
	if not _present or not bank_enabled or _state != State.OPEN:
		return BigMoney.zero()
	var amount := TableScore.storefront_collect_value(id)
	AudioDirector.play(&"storefront_collect")
	var paid := TableScore.earn_big(TableScore.GROUP_STOREFRONTS, amount,
			StringName(String(id) + "_collect"), ball)
	Events.storefront_collected.emit(id)
	collected.emit(id, amount)
	_state = State.COOLDOWN
	_timer = rearm_seconds
	_glow = 1.0
	_apply_door()
	_raise_all()
	return paid


func _close(quiet: bool = false) -> void:
	_state = State.ARMED
	_timer = -1.0
	_raise_all()
	_apply_door()
	if not quiet:
		AudioDirector.play(&"drop_bank_reset")
	door_closed.emit(id)


func _raise_all() -> void:
	for t in _targets:
		t.raise()


func _physics_process(delta: float) -> void:
	_wash_cool = maxf(_wash_cool - delta, 0.0)
	if _glow > 0.0:
		_glow = maxf(_glow - delta * 1.5, 0.0)
	if _timer < 0.0:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = -1.0
	match _state:
		State.OPEN:
			_close()
		State.COOLDOWN:
			_state = State.ARMED
			_apply_door()
			AudioDirector.play(&"drop_bank_reset")


func _process(delta: float) -> void:
	if _door_lamp != null:
		var wanted := 0.15
		if is_open():
			wanted = 1.5 + _glow
		elif _state == State.COOLDOWN:
			wanted = 0.0
		_door_lamp.emission_energy_multiplier = lerpf(_door_lamp.emission_energy_multiplier, wanted,
				1.0 - exp(-10.0 * delta))
	if _light != null:
		var flicker := 0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.021 + float(get_instance_id() % 97))
		_light.light_energy = (0.0 if _state == State.COOLDOWN else 1.1) * flicker
	if _neon != null:
		_neon.emission_energy_multiplier = 0.6 if _state == State.COOLDOWN else 2.6


func _apply_door() -> void:
	if _door == null:
		return
	var live := _present and (_state == State.OPEN or wash_enabled)
	_door.collision_layer = Feel.LAYER_ZONES if live else 0
	_door.collision_mask = Feel.LAYER_BALL if live else 0


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	for t in _targets:
		t.set_hardware_active(active and bank_enabled)
	_apply_door()
	if _light != null:
		_light.visible = active


func is_hardware_active() -> bool:
	return _present


func visual_state() -> int:
	if not _present:
		return TableVisualState.VisualState.DISABLED
	match _state:
		State.OPEN:
			return TableVisualState.VisualState.ACTIVE
		State.COOLDOWN:
			return TableVisualState.VisualState.DISABLED
		_:
			return TableVisualState.VisualState.ARMED


func visual_modifiers() -> Dictionary:
	return {&"cooldown": _state == State.COOLDOWN, &"pulse": _glow > 0.02}


func visual_token() -> Dictionary:
	return TableVisualState.state_token(visual_state(), visual_modifiers())
