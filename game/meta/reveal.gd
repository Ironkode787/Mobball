class_name Reveal
extends RefCounted
## The suspense engine (docs/04 "Milestone reveals"): decides whether a Ledger node is
## HIDDEN, FACEDOWN or REVEALED.
##
##   REVEALED — owned, or its `reveal` condition is met (a node with no `reveal` block is
##              revealed once your rank reaches its tier: "default: visible with tier").
##   FACEDOWN — the condition is not met yet, but at least one node it `requires` IS
##              revealed. This is the card you can see string running to.
##   HIDDEN   — nothing points at it yet. The player has no idea it exists.
##
## Two of the four conditions are *sticky*: `event` marks and `dirty_held` thresholds fire
## once and stay fired, because "the first time you held $10k" is a memory, not a balance.
## `rank` and `purchased` are read live — they only ever go up. The sticky half serializes
## through `to_dict` / `from_dict` so a save keeps the board it earned.
##
## `observe` / `take_pending_cluster` add the other half of docs/04: a card may become
## revealed mid-Night, but it is only *shown* to flip mid-Count, with a stinger. See the
## stinger-queue section.
##
## RefCounted and autoload-free: the UI feeds it rank/dirty/marks, it never reaches for Game.

enum State { HIDDEN, FACEDOWN, REVEALED }

static var _shared: Reveal = null

var catalog: Upgrades = null
var rank: int = 0

## Sticky milestone marks, e.g. &"first_tilt".
var _marks: Dictionary = {}
## Sticky dirty_held thresholds already crossed, keyed by the literal content string.
var _crossed: Dictionary = {}
## Thresholds the catalog declares, gathered once per catalog — note_dirty_held runs on
## every dirty payout of a Night, so it may not walk the node list each time.
var _thresholds: PackedStringArray = []
var _thresholds_for: Upgrades = null

## Ids `observe` has already seen face-up, and the ones that flipped since the Count last
## drained the queue. Both are runtime-only: a reload re-baselines off the board it loads.
var _seen: Dictionary = {}
var _pending: PackedStringArray = []
var _baselined: bool = false


## Process-wide instance. The reveal history has to outlive the Ledger UI, which is
## instantiated and freed per visit.
static func shared() -> Reveal:
	if _shared == null:
		_shared = Reveal.new()
	return _shared


static func reset_shared() -> void:
	_shared = null


func _init(from_catalog: Upgrades = null) -> void:
	catalog = from_catalog


# --- conditions ---------------------------------------------------------------


## Records a milestone (docs/04: first TILT, first survived raid...). Returns true the
## first time, so callers can fire the reveal stinger exactly once.
func mark_event(id: StringName) -> bool:
	if _marks.has(id):
		return false
	_marks[id] = true
	return true


func has_mark(id: StringName) -> bool:
	return _marks.has(id)


## Feed held dirty whenever it changes (or on open). Marks every dirty_held threshold in
## the catalog at or below `amount`; returns how many fired for the first time.
func note_dirty_held(amount: BigMoney) -> int:
	if amount == null or not amount.is_positive():
		return 0
	var thresholds := dirty_thresholds()
	if _crossed.size() >= thresholds.size():
		return 0
	var fired := 0
	for threshold in thresholds:
		if _crossed.has(threshold):
			continue
		if amount.cmp(BigMoney.parse(threshold)) >= 0:
			_crossed[threshold] = true
			fired += 1
	return fired


## Every distinct `dirty_held` string used by the catalog, cached after the first walk.
func dirty_thresholds() -> PackedStringArray:
	var cat := _catalog()
	if _thresholds_for == cat:
		return _thresholds
	_thresholds = PackedStringArray()
	for n in cat.nodes:
		var reveal: Dictionary = n["reveal"]
		if reveal.has("dirty_held") and not _thresholds.has(String(reveal["dirty_held"])):
			_thresholds.append(String(reveal["dirty_held"]))
	_thresholds_for = cat
	return _thresholds


# --- evaluation ---------------------------------------------------------------


func state_of(id: String, owned: Dictionary) -> State:
	return states(owned).get(id, State.HIDDEN)


## The whole board in one pass — what the Ledger asks for on every refresh.
##
## Reveal cascades down the requires graph: a node is revealed when its own condition is
## met AND something it hangs off is already on the board. Without that gate a tier-1 card
## with no `reveal` block would pop into view at R1 with its red string running to a card
## nobody can see, which is exactly backwards — the string is supposed to be the clue.
func states(owned: Dictionary) -> Dictionary:
	var cat := _catalog()
	var revealed: Dictionary = {}
	for n in cat.nodes:
		if int(owned.get(String(n["id"]), 0)) >= 1:
			revealed[String(n["id"])] = true

	var changed := true
	while changed:
		changed = false
		for n in cat.nodes:
			var id := String(n["id"])
			if revealed.has(id):
				continue
			if not _condition_met(n, owned):
				continue
			if not _anchored(n, revealed):
				continue
			revealed[id] = true
			changed = true

	var out: Dictionary = {}
	for n in cat.nodes:
		var id := String(n["id"])
		var parents: PackedStringArray = n["requires"]
		if revealed.has(id):
			out[id] = State.REVEALED
		elif not parents.is_empty() and _anchored(n, revealed):
			out[id] = State.FACEDOWN
		else:
			out[id] = State.HIDDEN
	return out


func is_revealed(id: String, owned: Dictionary) -> bool:
	return state_of(id, owned) == State.REVEALED


# --- the stinger queue (docs/04 "Milestone reveals") --------------------------
#
# "Face-down clusters flip at scripted moments, always mid-Count with a stinger" — so the
# flip is NOT allowed to happen where the reveal condition is met (mid-Night, mid-tilt).
# `observe` is the recorder: call it wherever rank, marks or held dirty move, and it banks
# whatever went face-up. The Count then drains one branch at a time with
# `take_pending_cluster` and plays it as one reveal. Pure bookkeeping — no signals, no
# timers, no autoloads: what the Count does with a cluster is the flow lane's business.


## The same board `states()` reports, plus the memory of what flipped. The FIRST call is the
## baseline — the cards a player already has are not news — so a fresh session (or one just
## restored with `from_dict`) should observe once before anything can be pending.
func observe(owned: Dictionary) -> Dictionary:
	var out := states(owned)
	for id: Variant in out:
		if int(out[id]) != State.REVEALED or _seen.has(id):
			continue
		_seen[id] = true
		if _baselined:
			_pending.append(String(id))
	_baselined = true
	return out


## Everything waiting for a stinger, in catalog order, without draining it.
func pending_ids() -> PackedStringArray:
	return _pending.duplicate()


func pending_count() -> int:
	return _pending.size()


## One cluster for The Count: `{"branch": String, "ids": PackedStringArray, "names":
## PackedStringArray}`, and it leaves the queue. Empty `{}` when nothing is waiting.
##
## One branch per take, because a stinger reveals a *place* — "you got a money problem, kid"
## is the FRONTS branch lighting up, not a shopping list. A reveal that spans branches comes
## back over consecutive takes, so the Count can flip one, sting, and ask again.
func take_pending_cluster() -> Dictionary:
	if _pending.is_empty():
		return {}
	var cat := _catalog()
	var branch := String(cat.def(_pending[0]).get("branch", ""))
	var ids: PackedStringArray = []
	var names: PackedStringArray = []
	var rest: PackedStringArray = []
	for id in _pending:
		var node := cat.def(id)
		if String(node.get("branch", "")) == branch:
			ids.append(id)
			names.append(String(node.get("name", id)))
		else:
			rest.append(id)
	_pending = rest
	return {"branch": branch, "ids": ids, "names": names}


## Drops the queue without playing it (a Night abandoned, a respec, a test).
func clear_pending() -> void:
	_pending.clear()


# --- serialization ------------------------------------------------------------


func to_dict() -> Dictionary:
	var marks: PackedStringArray = []
	for m: Variant in _marks:
		marks.append(String(m))
	marks.sort()
	var crossed: PackedStringArray = PackedStringArray(_crossed.keys())
	crossed.sort()
	return {"marks": marks, "dirty_crossed": crossed}


func from_dict(d: Dictionary) -> void:
	_marks.clear()
	_crossed.clear()
	# The board that comes out of a save is the new baseline: it is history, not a stinger
	# waiting to fire. The next `observe` re-arms the queue against it.
	_seen.clear()
	_pending.clear()
	_baselined = false
	if d == null:
		return
	var marks: Variant = d.get("marks", [])
	if marks is Array or marks is PackedStringArray:
		for m: Variant in marks:
			_marks[StringName(String(m))] = true
	var crossed: Variant = d.get("dirty_crossed", [])
	if crossed is Array or crossed is PackedStringArray:
		for c: Variant in crossed:
			_crossed[String(c)] = true


# --- internals ----------------------------------------------------------------


func _catalog() -> Upgrades:
	return catalog if catalog != null else Upgrades.shared()


## A root node hangs off nothing and is its own anchor; anything else needs one visible
## card it descends from (the requires list is an AND for buying, an OR for seeing).
func _anchored(node: Dictionary, revealed: Dictionary) -> bool:
	var parents: PackedStringArray = node["requires"]
	if parents.is_empty():
		return true
	for parent in parents:
		if revealed.has(parent):
			return true
	return false


func _condition_met(node: Dictionary, owned: Dictionary) -> bool:
	if int(owned.get(String(node["id"]), 0)) >= 1:
		return true
	var reveal: Dictionary = node["reveal"]
	if reveal.is_empty():
		return rank >= int(node["tier"])
	if reveal.has("rank"):
		return rank >= int(reveal["rank"])
	if reveal.has("event"):
		return _marks.has(StringName(String(reveal["event"])))
	if reveal.has("purchased"):
		return int(owned.get(String(reveal["purchased"]), 0)) >= 1
	if reveal.has("dirty_held"):
		return _crossed.has(String(reveal["dirty_held"]))
	return false
