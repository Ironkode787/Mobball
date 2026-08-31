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
##
## The two build-outs are deliberately **independent**. The wash pass fires on any pass
## through the doorway for as long as the loop is owned; the bank only adds the collection on
## top of it. Gating the wash on the bank's door cycle made buying the protection racket a
## laundering *downgrade* — a 26 s armed/open/cooldown loop where there had been an always-
## open door (SIM lane balance report, design-approved). Owning more of a racket may never
## make it work worse.

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
	if not (body is Ball) or not _present:
		return
	var ball := body as Ball
	if wash_enabled and _wash_cool <= 0.0:
		_wash_cool = WASH_COOLDOWN
		AudioDirector.play(&"laundromat_wash")
		TableScore.hit(&"laundromat_loop", ball)
		washed.emit(id)
	collect_now(ball)


## Work the till. Normally a ball through the open door does this; Manny (the flow lane's
## `auto_collect_interval` specialist, specs/m2-content.md §2) does it without one, which is
## the whole point of hiring him. Returns what it paid — zero if the shutters were down.
func collect_now(ball: Node2D = null) -> BigMoney:
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
	queue_redraw()
	return paid


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
	# The doorway is a live switch whenever there is a wash loop behind it, open shutters or
	# not; the bank decides collections, never washes.
	var live := _present and (_state == State.OPEN or wash_enabled)
	_door.collision_layer = Feel.LAYER_ZONES if live else 0
	_door.collision_mask = Feel.LAYER_BALL if live else 0


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	for t in _targets:
		t.set_hardware_active(active and bank_enabled)
	_apply_door()


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
	return {
		&"cooldown": _state == State.COOLDOWN,
		&"pulse": _glow > 0.02,
	}


func visual_token() -> Dictionary:
	return TableVisualState.state_token(visual_state(), visual_modifiers())


func _ambient(role: StringName, fallback: Color) -> Color:
	if Presentation != null and Presentation.city != null:
		var candidate := Presentation.city.material_for(role)
		if candidate.a > 0.0:
			return candidate
	return fallback


func _draw_hatch(rect: Rect2, color: Color, spacing: float = 14.0) -> void:
	var x := rect.position.x - rect.size.y
	while x < rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x + rect.size.y, rect.end.y), color, 2.0)
		x += spacing


func _draw_state_cue(center: Vector2, radius: float, token: Dictionary, color: Color) -> void:
	var mark := String(token["mark"])
	var pattern := String(token["pattern"])
	if mark == "invitation_pin":
		draw_circle(center, radius, color)
		draw_colored_polygon(PackedVector2Array([
		center + Vector2(-radius * 0.45, radius * 0.20),
		center + Vector2(radius * 0.45, radius * 0.20),
		center + Vector2(0.0, radius * 1.35),
	]), color)
	elif mark == "contact_pulse":
		draw_arc(center, radius, 0.0, TAU, 20, color, 4.0)
		draw_circle(center, radius * 0.28, color)
	elif mark == "cooldown_clock":
		draw_arc(center, radius, -PI * 0.5, PI * 1.2, 20, color, 4.0)
		draw_line(center, center + Vector2(0.0, -radius * 0.48), color, 3.0)
		draw_line(center, center + Vector2(radius * 0.34, radius * 0.20), color, 3.0)
	elif mark == "lock_offline":
		draw_rect(Rect2(center - Vector2(radius * 0.7, radius * 0.42),
			Vector2(radius * 1.4, radius * 1.05)), color, false, 3.0)
		draw_arc(center + Vector2(0.0, -radius * 0.30), radius * 0.46, PI, TAU, 12, color, 3.0)
	else:
		draw_arc(center, radius, 0.0, TAU, 20, color, 3.0)
	if pattern == "offline_hatch" or pattern == "cooldown_dash":
		for i in range(3):
			var y := center.y - radius * 0.35 + float(i) * radius * 0.35
			draw_line(Vector2(center.x - radius * 0.42, y), Vector2(center.x + radius * 0.42, y), color, 2.0)


func _draw() -> void:
	var w := half_span()
	var token := visual_token()
	var state := String(token["state"])
	var lit := state == "active"
	var ink := _ambient(&"ink_glass", Feel.COL_INK)
	var wood := _ambient(&"wood", Feel.COL_INK.darkened(0.10))
	var wood_edge := _ambient(&"wood_edge", Feel.COL_BRASS.darkened(0.58))
	var brass := _ambient(&"brass", Feel.COL_BRASS)
	var paper := _ambient(&"paper", Feel.COL_NEWSPRINT)
	var frame := brass.darkened(0.32)
	var state_col := brass if state == "armed" else paper
	if state == "disabled":
		state_col = paper.darkened(0.35)
	if state == "danger":
		state_col = Feel.COL_DIRTY
	# A complete little building gives the bank a silhouette: cornice, sign box, shop window,
	# striped awning and the working doorway. Each racket is now a place on the Block.
	var facade := Rect2(Vector2(-w - 10.0, -DOOR_DEPTH - 82.0),
			Vector2(w * 2.0 + 20.0, DOOR_DEPTH + 78.0))
	draw_rect(Rect2(facade.position + Vector2(7.0, 9.0), facade.size),
			Color(ink.r, ink.g, ink.b, 0.55))
	var art_id := &"front.laundromat"
	if String(id).contains("pizzeria"):
		art_id = &"front.pizzeria"
	elif String(id).contains("pawn"):
		art_id = &"front.pawn"
	var facade_art := Presentation.art.resolve(art_id, null, false)
	if facade_art != null:
		draw_texture_rect(facade_art, facade, false, Color(1.0, 1.0, 1.0, 0.64))
	else:
		draw_rect(facade, wood)
	draw_rect(facade, wood_edge, false, 4.0)
	if state == "disabled":
		_draw_hatch(facade.grow(-8.0), Color(paper.r, paper.g, paper.b, 0.18))
	draw_rect(facade, frame, false, 4.0)
	draw_line(Vector2(facade.position.x - 5.0, facade.position.y),
			Vector2(facade.end.x + 5.0, facade.position.y), brass, 7.0)

	var sign_box := Rect2(Vector2(-w + 4.0, -DOOR_DEPTH - 70.0),
			Vector2(w * 2.0 - 8.0, 34.0))
	var sign_col := Feel.COL_CLEAN if wash_enabled else brass
	if String(id).contains("pizzeria"):
		sign_col = Feel.COL_DIRTY.darkened(0.10)
	elif String(id).contains("pawn"):
		sign_col = brass.lightened(0.10)
	if state == "disabled":
		sign_col = sign_col.darkened(0.6)
	draw_rect(sign_box, Color(sign_col.r, sign_col.g, sign_col.b, 0.22))
	draw_rect(sign_box, sign_col, false, 3.0)
	var font := Presentation.theme.font_for(&"headline")
	if font != null:
		draw_string(font, sign_box.position + Vector2(0.0, 25.0), String(sign_text),
				HORIZONTAL_ALIGNMENT_CENTER, sign_box.size.x, 18, sign_col.lightened(0.32))

	# the shopfront behind the bank: a dark doorway that lights up when it is open
	var door_rect := Rect2(Vector2(-w, -DOOR_DEPTH - 31.0), Vector2(w * 2.0, DOOR_DEPTH + 19.0))
	draw_rect(door_rect, ink.darkened(0.35))
	if lit:
		var glow := brass.lerp(paper, 0.25 + _glow * 0.4)
		draw_rect(door_rect.grow(-6.0), Color(glow.r, glow.g, glow.b, 0.34))
	draw_rect(door_rect, frame, false, 4.0)
	if state == "disabled":
		_draw_hatch(door_rect.grow(-8.0), Color(paper.r, paper.g, paper.b, 0.26), 16.0)

	# Canvas awning; the bank targets sit directly along its lower edge.
	var awning_y := -DOOR_DEPTH - 27.0
	draw_line(Vector2(-w + 2.0, awning_y), Vector2(w - 2.0, awning_y), state_col, 10.0)
	for i in range(7):
		var x := lerpf(-w + 8.0, w - 8.0, float(i) / 6.0)
		draw_line(Vector2(x, awning_y - 4.0), Vector2(x - 4.0, awning_y + 7.0),
				paper.darkened(0.20), 3.0)

	# Shop-specific window marks stay small and readable even with the bank raised.
	if String(id).contains("laundromat"):
		for side in [-1.0, 1.0]:
			draw_arc(Vector2(side * 39.0, -47.0), 18.0, 0.0, TAU, 20,
					sign_col.darkened(0.18), 4.0)
	elif String(id).contains("pizzeria"):
		draw_colored_polygon(PackedVector2Array([
			Vector2(-22.0, -61.0), Vector2(24.0, -61.0), Vector2(2.0, -26.0),
		]), sign_col.darkened(0.22))
		draw_circle(Vector2(0.0, -51.0), 3.0, Feel.COL_NEWSPRINT)
	else:
		for side in [-1.0, 1.0]:
			draw_circle(Vector2(side * 17.0, -48.0), 11.0, sign_col.darkened(0.08), false, 4.0)
		draw_circle(Vector2(0.0, -32.0), 11.0, sign_col.darkened(0.08), false, 4.0)

	# A compact, non-colour state mark sits above the door and survives grayscale.
	_draw_state_cue(Vector2(w - 18.0, -DOOR_DEPTH - 52.0), 12.0, token, state_col)
	for i in range(_targets.size()):
		var target := _targets[i]
		if target == null or not is_instance_valid(target) or not target.visible:
			continue
		var target_col := brass if not target.down else paper.darkened(0.28)
		draw_line(Vector2((float(i) - 1.0) * TARGET_PITCH - 15.0, -DOOR_DEPTH + 3.0),
				Vector2((float(i) - 1.0) * TARGET_PITCH + 15.0, -DOOR_DEPTH + 3.0),
				target_col, 4.0)
