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
## The quay's rake. The deck *steps* down-field with it, so the crates read as cargo standing
## on the dock rather than as a bank floating over it.
const DECK_RAKE_DEG := 12.0
## Each crate is tipped harder than the deck it stands on. The deck's step is set by the yard
## (and by what Lucky's underside leaves room for above it); a crate lid has to outrun the
## ball's friction on its own account, and 12° only just does.
const CRATE_RAKE_DEG := 18.0

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
	var step := tan(deg_to_rad(DECK_RAKE_DEG))
	var rake := deg_to_rad(CRATE_RAKE_DEG)
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
					Vector2(along, along * step), Vector2.UP.rotated(rake), CRATE_LENGTH)
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
	if _reset_in.size() < STACKS:
		_reset_in.resize(STACKS)
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


## Presentation-only stack classification. The target children still own their collision,
## drop/raise, payout, reset, and signal contracts; this aggregate read is for the cargo
## dressing and evidence probes only.
func visual_state(stack: int = -1) -> Dictionary:
	var state := TableVisualState.VisualState.ARMED
	var down := false
	if not _present:
		state = TableVisualState.VisualState.DISABLED
	elif stack >= 0 and stack < STACKS:
		if _targets.size() < STACKS * PER_STACK:
			return TableVisualState.state_token(state, {&"down": false})
		var count := stack_down(stack)
		down = count > 0
		if count >= PER_STACK:
			state = TableVisualState.VisualState.COMPLETED
		elif down:
			state = TableVisualState.VisualState.ACTIVE
	elif stack >= STACKS:
		state = TableVisualState.VisualState.DISABLED
	else:
		if _targets.size() < STACKS * PER_STACK:
			return TableVisualState.state_token(state, {&"down": false})
		var cleared := cleared_stacks()
		down = not cleared.is_empty()
		if cleared.size() >= STACKS:
			state = TableVisualState.VisualState.COMPLETED
		elif down:
			state = TableVisualState.VisualState.ACTIVE
	return TableVisualState.state_token(state, {&"down": down})


func visual_token(stack: int = -1) -> Dictionary:
	return visual_state(stack)


func _ambient(role: StringName, fallback: Color) -> Color:
	if Presentation != null and Presentation.city != null:
		var city_col := Presentation.city.material_for(role)
		if city_col.a > 0.0:
			return city_col
	if Presentation != null and Presentation.theme != null:
		var material := Presentation.theme.material_for(role)
		var fill: Variant = material.get("fill", fallback)
		if fill is Color:
			return fill as Color
	return fallback


func _hatch(rect: Rect2, color: Color, spacing: float = 10.0) -> void:
	var x := rect.position.x - rect.size.y
	while x < rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x + rect.size.y, rect.end.y), color, 2.0)
		x += spacing


func _draw_state_cue(center: Vector2, radius: float, token: Dictionary, color: Color) -> void:
	var mark := String(token["mark"])
	if mark == "invitation_pin":
		draw_circle(center, radius * 0.42, color)
		draw_line(center + Vector2(0.0, radius * 0.38), center + Vector2(0.0, radius), color, 3.0)
	elif mark == "contact_pulse":
		draw_arc(center, radius, 0.0, TAU, 20, color, 3.0)
		draw_circle(center, radius * 0.2, color)
	elif mark == "marked_stamp" or mark == "check_stamp":
		draw_rect(Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)),
				color, false, 3.0)
		draw_line(center + Vector2(-radius * 0.55, 0.0),
				center + Vector2(-radius * 0.10, radius * 0.42), color, 3.0)
		draw_line(center + Vector2(-radius * 0.10, radius * 0.42),
				center + Vector2(radius * 0.58, -radius * 0.48), color, 3.0)
	elif mark == "lock_offline":
		draw_rect(Rect2(center - Vector2(radius * 0.72, radius * 0.34),
				Vector2(radius * 1.44, radius * 0.9)), color, false, 3.0)
		draw_arc(center + Vector2(0.0, -radius * 0.25), radius * 0.42, PI, TAU, 12, color, 3.0)
	else:
		draw_arc(center, radius, 0.0, TAU, 20, color, 3.0)


## How far a standing crate reaches above and below its own centre — what the sim measures
## the yard's headroom and its under-deck lane against.
static func half_extent_y() -> float:
	return (CRATE_LENGTH + CRATE_THICK) * 0.5 * sin(deg_to_rad(CRATE_RAKE_DEG)) \
			+ CRATE_THICK * 0.5


func _draw() -> void:
	var step := tan(deg_to_rad(DECK_RAKE_DEG))
	var rake := deg_to_rad(CRATE_RAKE_DEG)
	var ink := _ambient(&"ink_glass", Feel.COL_INK)
	var brass := _ambient(&"brass", Feel.COL_BRASS)
	var paper := _ambient(&"paper", Feel.COL_NEWSPRINT)
	var wood := _ambient(&"wood", Feel.COL_INK.darkened(0.15))
	var font := Presentation.theme.font_for(&"annotation") if Presentation != null \
			and Presentation.theme != null else ThemeDB.fallback_font
	for s in range(STACKS):
		var token := visual_token(s)
		var state := String(token["state"])
		var state_col := paper if state == "completed" else brass
		for c in range(PER_STACK):
			var along := float(s) * STACK_PITCH + float(c) * CRATE_PITCH
			var at := Vector2(along, along * step)
			var target := target_at(s, c)
			var box := Rect2(Vector2(-CRATE_LENGTH * 0.5, -CRATE_THICK * 0.5),
					Vector2(CRATE_LENGTH, CRATE_THICK))
			draw_set_transform(at, rake, Vector2.ONE)
			if target.down:
				# An empty bay is visibly empty; the child DropTarget supplies the completed bar.
				draw_rect(box.grow(4.0), wood.darkened(0.45), false, 3.0)
				_hatch(box.grow(-2.0), Color(paper.r, paper.g, paper.b, 0.14), 10.0)
			else:
				var body := brass.darkened(0.48) if state == "armed" else brass.darkened(0.26)
				if state == "active":
					body = brass.lerp(paper, 0.18)
				draw_rect(box.grow(4.0), ink, true)
				draw_rect(box, body, true)
				draw_line(Vector2(box.position.x + 2.0, box.position.y + 3.0),
						Vector2(box.end.x - 2.0, box.position.y + 3.0), paper.darkened(0.25), 3.0)
				for r in range(3):
					var rx := lerpf(box.position.x + 5.0, box.end.x - 5.0, float(r) / 2.0)
					draw_line(Vector2(rx, box.position.y + 5.0), Vector2(rx, box.end.y - 4.0),
							ink.lightened(0.14), 2.0)
				# A small stencil makes each two-crate stack read as one unit at phone scale.
				if font != null:
					draw_string(font, Vector2(-CRATE_LENGTH * 0.28, 5.0), "%d-%d" % [s + 1, c + 1],
							HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, paper.darkened(0.10))
			_draw_state_cue(Vector2(CRATE_LENGTH * 0.58, 0.0), 7.0, token, state_col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
