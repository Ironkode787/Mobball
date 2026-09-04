class_name TestCtx
extends RefCounted
## Tiny assertion collector used by tests/run_tests.gd.

var checks: int = 0
var failures: PackedStringArray = []
var skips: PackedStringArray = []
var _current: String = ""


func begin(name: String) -> void:
	_current = name


func ok(cond: bool, msg: String = "") -> void:
	checks += 1
	if not cond:
		failures.append("%s: %s" % [_current, msg if msg != "" else "expected true"])


func eq(got: Variant, want: Variant, msg: String = "") -> void:
	checks += 1
	if got != want:
		failures.append("%s: %s — got %s, want %s" % [_current, msg, str(got), str(want)])


func near(got: float, want: float, tol: float = 1e-6, msg: String = "") -> void:
	checks += 1
	if not is_finite(got) or not is_finite(want) or not is_finite(tol) \
			or tol < 0.0 or absf(got - want) > tol:
		failures.append("%s: %s — got %f, want %f (tol %f)" % [_current, msg, got, want, tol])


func fail(msg: String) -> void:
	checks += 1
	failures.append("%s: %s" % [_current, msg])


func skip(reason: String) -> void:
	skips.append("%s: %s" % [_current, reason])
