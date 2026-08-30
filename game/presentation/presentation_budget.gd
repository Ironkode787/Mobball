class_name PresentationBudget
extends Node
## Explicit effect accounting. This is intentionally separate from RenderingServer metrics;
## effect implementations register what they own and the device profiler audits the rest.

signal budget_exceeded(kind: StringName, count: int, limit: int)

const LIMITS := {
	&"draw_calls": 120,
	&"lights": 8,
	&"emitters": 12,
	&"audio_voices": 24,
}

var _counts: Dictionary = {}


func register(kind: StringName, amount: int = 1) -> bool:
	if amount <= 0:
		return within(kind)
	var next := count(kind) + amount
	_counts[kind] = next
	var limit := limit_for(kind)
	if limit >= 0 and next > limit:
		budget_exceeded.emit(kind, next, limit)
		return false
	return true


func release(kind: StringName, amount: int = 1) -> void:
	_counts[kind] = maxi(0, count(kind) - maxi(amount, 0))


func count(kind: StringName) -> int:
	return int(_counts.get(kind, 0))


func limit_for(kind: StringName) -> int:
	return int(LIMITS.get(kind, -1))


func within(kind: StringName) -> bool:
	var limit := limit_for(kind)
	return limit < 0 or count(kind) <= limit


func violations() -> Dictionary:
	var out := {}
	for kind: StringName in LIMITS:
		if not within(kind):
			out[kind] = {"count": count(kind), "limit": limit_for(kind)}
	return out


func snapshot() -> Dictionary:
	var out := {}
	for kind: StringName in LIMITS:
		out[kind] = {"count": count(kind), "limit": limit_for(kind), "ok": within(kind)}
	return out


func reset() -> void:
	_counts.clear()
