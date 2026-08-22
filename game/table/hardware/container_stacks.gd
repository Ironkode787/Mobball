class_name ContainerStacks
extends Node2D
## The Docks' cargo (docs/02 §2 R5): three container stacks, two crates each, built out of
## drop targets and laid along the quay's own rake so the whole deck is one continuous
## surface stepping down-field.
##
## Two rules decide the geometry, and both come from the M1/M2 banks before it:
##
##   * **Crates inside a stack are sealed together, stacks are sealed to each other.** Every
##     gap in the standing deck is far narrower than a ball, so a full deck is a floor the
##     ball works across rather than a comb it can wedge in. Clearing one stack opens a hole
##     wider than `dia + 20`, which is the only route down — knocking a stack down *is* the
##     shot, and which stack you cleared decides where the ball lands.
##   * **One rake for the whole deck.** The slot reels alternate their targets' rake because
##     their columns are lanes apart; here they touch, and two opposed rakes meeting would
##     make a V-notch at every junction. One sign, and each crate stepped down by exactly the
##     rake, keeps the deck a plane.
##
## Stacks reset independently on their own clock (the slot reels' rule) so there is always
## cargo standing to shoot at, and the flow lane's smuggling runs get a live board.

## The set of cleared stacks changed — one went down, or one came back up.
signal state_changed(cleared_stacks: Array)
signal stack_cleared(stack: int)

const STACKS := 3
const PER_STACK := 2
const CRATE_LENGTH := 30.0
const CRATE_THICK := 20.0
## Crate-to-crate inside one stack, and stack-to-stack along the quay. Both are sealed:
## `CRATE_PITCH` and (`STACK_PITCH` - the crate span) are each well under a ball.
const CRATE_PITCH := 30.0
const STACK_PITCH := 81.0
## The quay's rake. The deck steps down-field with it so the crates read as cargo standing
## on the dock rather than as a bank floating over it.
const RAKE_DEG := 12.0

@export var id: StringName = &"containers"

var reset_seconds: float = 6.0
var crate_value: float = TableScore.SMUGGLING_CONTAINER
var group: StringName = TableScore.GROUP_SMUGGLING

var _targets: Array[DropTarget] = []         ## stack-major: [stack * PER_STACK + crate]
var _reset_in: PackedFloat32Array = PackedFloat32Array()
var _present: bool = true


## `origin` is the centre of the first (up-field) crate; everything else steps off it.
func configure(p_id: StringName, origin: Vector2) -> void:
	id = p_id
	position = origin


func _ready() -> void:
	_reset_in.resize(STACKS)
	var rake := deg_to_rad(RAKE_DEG)
	for s in range(STACKS):
		_reset_in[s] = -1.0
		for c in range(PER_STACK):
			var along := float(s) * STACK_PITCH + float(c) * CRATE_PITCH
			var t := DropTarget.new()
			t.name = "Stack%dCrate%d" % [s + 1, c + 1]
			t.thickness = CRATE_THICK
			# Local space: the crate faces up-field (the ball comes down onto the deck) and
			# is tipped by the deck's own rake, so nothing lands on a level lid.
			t.configure(StringName("%s_%d%d" % [id, s + 1, c + 1]),
					Vector2(along, along * tan(rake)), Vector2.UP.rotated(rake), CRATE_LENGTH)
			add_child(t)
			t.dropped.connect(_on_dropped)
			_targets.append(t)


func targets() -> Array[DropTarget]:
	return _targets


func target_at(stack: int, crate: int) -> DropTarget:
	return _targets[stack * PER_STACK + crate]


func stack_down(stack: int) -> int:
	var n := 0
	for c in range(PER_STACK):
		if target_at(stack, c).down:
			n += 1
	return n


func stack_is_clear(stack: int) -> bool:
	return stack_down(stack) == PER_STACK


func cleared_stacks() -> Array:
	var out: Array = []
	for s in range(STACKS):
		if stack_is_clear(s):
			out.append(s)
	return out


func reset_now() -> void:
	for s in range(STACKS):
		_reset_in[s] = -1.0
	for t in _targets:
		t.raise()


func _on_dropped(target: DropTarget) -> void:
	if not _present:
		return
	var stack := _targets.find(target) / PER_STACK
	# The target announced its own closure from `drop()`; paying quietly keeps one hit one
	# switch, which is what the Jobs counter and the smuggling runs count.
	TableScore.earn_quiet(group, crate_value, target.id)
	if not stack_is_clear(stack):
		return
	_reset_in[stack] = reset_seconds
	AudioDirector.play(&"container_break")
	stack_cleared.emit(stack)
	state_changed.emit(cleared_stacks())


func _physics_process(delta: float) -> void:
	for s in range(STACKS):
		if _reset_in[s] < 0.0:
			continue
		_reset_in[s] -= delta
		if _reset_in[s] > 0.0:
			continue
		_reset_in[s] = -1.0
		for c in range(PER_STACK):
			target_at(s, c).raise()
		if _present:
			AudioDirector.play(&"drop_bank_reset")
		state_changed.emit(cleared_stacks())


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	for t in _targets:
		t.set_hardware_active(active)
	if not active:
		reset_now()


func is_hardware_active() -> bool:
	return _present


func _draw() -> void:
	var rake := deg_to_rad(RAKE_DEG)
	for s in range(STACKS):
		var lit := stack_is_clear(s)
		for c in range(PER_STACK):
			var along := float(s) * STACK_PITCH + float(c) * CRATE_PITCH
			var at := Vector2(along, along * tan(rake))
			var box := Rect2(at - Vector2(CRATE_PITCH * 0.5, CRATE_THICK * 0.9),
					Vector2(CRATE_PITCH, CRATE_THICK * 1.8))
			draw_set_transform(at, rake, Vector2.ONE)
			var body := Rect2(-box.size * 0.5, box.size)
			draw_rect(body, Feel.COL_INK.darkened(0.2) if lit else Feel.COL_BRASS.darkened(0.62))
			draw_rect(body, Feel.COL_BRASS.darkened(0.25) if not lit else Feel.COL_INK, false, 2.0)
			for r in range(3):
				var rx := lerpf(body.position.x + 4.0, body.end.x - 4.0, float(r) / 2.0)
				draw_line(Vector2(rx, body.position.y + 3.0), Vector2(rx, body.end.y - 3.0),
						Feel.COL_INK.lightened(0.10), 2.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
