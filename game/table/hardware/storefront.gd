class_name Storefront
extends Node2D
## A protection-racket storefront (docs/02 §2 R3): a three-target drop bank across the
## table's waist. Knock the bank down and the shop's door stands open for a few seconds —
## put the ball through the door and you collect, which is worth minutes of that racket's
## idle income. Then the shutters come down and the block cools off before you can shake
## them again.
##
## Lucky's Laundromat is the same object with the wash loop wired to its door, so the R2
## "slow wash cycle" (`laundromat_loop`) and the R3 storefront are one piece of hardware at
## two levels of build-out: with only the loop bought, the doorway is there without a bank
## in front of it.

signal collected(id: StringName, amount: BigMoney)
signal washed(id: StringName)
signal door_opened(id: StringName)
signal door_closed(id: StringName)

enum State { ARMED, OPEN, COOLDOWN }

const TARGET_PITCH := 52.0
const TARGET_LENGTH := 44.0
const DOOR_DEPTH := 70.0
const WASH_COOLDOWN := 1.6

@export var id: StringName = &"storefront"

var open_seconds: float = 6.0
var rearm_seconds: float = 20.0
var sign_text: StringName = &"SHOP"

var bank_enabled: bool = true         ## storefront_<id> owned: the drop bank is fitted
var wash_enabled: bool = false        ## laundromat_loop owned: the door washes money

var _targets: Array[DropTarget] = []
var _door: Area2D = null
var _state: State = State.ARMED
var _timer: float = 0.0
var _wash_cool: float = 0.0
var _present: bool = true
var _glow: float = 0.0


func configure(p_id: StringName, center: Vector2, facing: Vector2, rake_deg: float,
		p_sign: StringName) -> void:
	id = p_id
	position = center
	sign_text = p_sign
	rotation = facing.normalized().angle() - PI * 0.5 + deg_to_rad(rake_deg)


func half_span() -> float:
	return TARGET_PITCH + TARGET_LENGTH * 0.5


func _ready() -> void:
	for i in range(3):
		var t := DropTarget.new()
		t.name = "Target%d" % (i + 1)
		# local space: the bank's own rake is on this node, the targets sit square in it
		t.configure(StringName("%s_t%d" % [id, i + 1]),
				Vector2((float(i) - 1.0) * TARGET_PITCH, 0.0), Vector2.DOWN, TARGET_LENGTH)
		add_child(t)
		t.dropped.connect(_on_target_dropped)
		_targets.append(t)

	_door = Area2D.new()
	_door.name = "Door"
	_door.collision_layer = Feel.LAYER_ZONES
	_door.collision_mask = Feel.LAYER_BALL
	_door.monitorable = false
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(half_span() * 2.0, DOOR_DEPTH)
	cs.shape = rect
	cs.position = Vector2(0.0, -DOOR_DEPTH * 0.5 - 14.0)
	_door.add_child(cs)
	add_child(_door)
	_door.body_entered.connect(_on_door_entered)
	apply_build()


## Re-read `bank_enabled` / `wash_enabled` after a purchase.
func apply_build() -> void:
	for t in _targets:
		t.set_hardware_active(_present and bank_enabled)
	if not bank_enabled:
		# a doorway with no shutters: the wash loop is always open for business
		_state = State.OPEN
		_timer = -1.0
	elif _state == State.OPEN and _timer < 0.0:
		_close(true)
	_apply_door()
	queue_redraw()


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
	queue_redraw()


func _on_door_entered(body: Node2D) -> void:
	if not (body is Ball) or not _present or _state != State.OPEN:
		return
	var ball := body as Ball
	if wash_enabled and _wash_cool <= 0.0:
		_wash_cool = WASH_COOLDOWN
		AudioDirector.play(&"laundromat_wash")
		TableScore.hit(&"laundromat_loop", ball)
		washed.emit(id)
	if not bank_enabled:
		return
	var amount := TableScore.storefront_collect_value(id)
	AudioDirector.play(&"storefront_collect")
	TableScore.earn_big(TableScore.GROUP_STOREFRONTS, amount,
			StringName(String(id) + "_collect"), ball)
	Events.storefront_collected.emit(id)
	collected.emit(id, amount)
	_state = State.COOLDOWN
	_timer = rearm_seconds
	_glow = 1.0
	_apply_door()
	_raise_all()
	queue_redraw()


func _close(quiet: bool = false) -> void:
	_state = State.ARMED
	_timer = -1.0
	_raise_all()
	_apply_door()
	if not quiet:
		AudioDirector.play(&"drop_bank_reset")
	door_closed.emit(id)
	queue_redraw()


func _raise_all() -> void:
	for t in _targets:
		t.raise()


func _physics_process(delta: float) -> void:
	_wash_cool = maxf(_wash_cool - delta, 0.0)
	if _glow > 0.0:
		_glow = maxf(_glow - delta * 1.5, 0.0)
		queue_redraw()
	if _timer < 0.0:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = -1.0
	match _state:
		State.OPEN:
			_close()                    # nobody came through: shutters back up
		State.COOLDOWN:
			_state = State.ARMED
			_apply_door()
			AudioDirector.play(&"drop_bank_reset")
			queue_redraw()


func _apply_door() -> void:
	if _door == null:
		return
	var live := _present and _state == State.OPEN
	_door.collision_layer = Feel.LAYER_ZONES if live else 0
	_door.collision_mask = Feel.LAYER_BALL if live else 0


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	for t in _targets:
		t.set_hardware_active(active and bank_enabled)
	_apply_door()


func _draw() -> void:
	var w := half_span()
	var lit := _state == State.OPEN
	var frame := Feel.COL_INK.lightened(0.18)
	# the shopfront behind the bank: a dark doorway that lights up when it is open
	var door_rect := Rect2(Vector2(-w, -DOOR_DEPTH - 16.0), Vector2(w * 2.0, DOOR_DEPTH + 4.0))
	draw_rect(door_rect, Feel.COL_INK.darkened(0.35))
	if lit:
		var glow := Feel.COL_BRASS.lerp(Feel.COL_NEWSPRINT, 0.25 + _glow * 0.4)
		draw_rect(door_rect.grow(-6.0), Color(glow.r, glow.g, glow.b, 0.30))
	draw_rect(door_rect, frame, false, 4.0)
	var sign_col := Feel.COL_CLEAN if wash_enabled else Feel.COL_BRASS
	if _state == State.COOLDOWN:
		sign_col = sign_col.darkened(0.6)
	draw_line(Vector2(-w + 8.0, -DOOR_DEPTH - 8.0), Vector2(w - 8.0, -DOOR_DEPTH - 8.0),
			sign_col, 7.0)
