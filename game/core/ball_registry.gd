extends Node
## The Balls autoload (specs/ball-registry.md): bookkeeping for every live ball so that
## multiball is a count, not a special case. Pure registry — it never moves, spawns or
## frees a ball. With zero registered balls every consumer falls back to its M0/M1
## single-ref path, so tables that never register (the alley debug scene) are untouched.

signal ball_registered(ball: Ball)
signal ball_unregistered(ball: Ball)
signal count_changed(n: int)
## Fires when the count falls back to exactly 1 — the cue that ends multiball modes.
signal last_ball(ball: Ball)

var _balls: Array[Ball] = []
var _guys: Dictionary = {}


func register(ball: Ball, guy: Dictionary = {}) -> void:
	if ball == null or _balls.has(ball):
		return
	_balls.append(ball)
	if not guy.is_empty():
		_guys[ball.get_instance_id()] = guy
	# Leak guard: a ball freed by anyone (drain, despawn, scene teardown) self-unregisters.
	if not ball.tree_exiting.is_connected(_on_ball_exiting):
		ball.tree_exiting.connect(_on_ball_exiting.bind(ball))
	ball_registered.emit(ball)
	count_changed.emit(count())


func unregister(ball: Ball) -> void:
	if ball == null or not _balls.has(ball):
		return
	_balls.erase(ball)
	_guys.erase(ball.get_instance_id())
	ball_unregistered.emit(ball)
	var n := count()
	count_changed.emit(n)
	if n == 1:
		last_ball.emit(live()[0])


## The Bench guy riding this ball (multiball = named guys, docs/01 §4). Set by the flow
## layer at serve time; the table stays guy-agnostic.
func set_guy(ball: Ball, guy: Dictionary) -> void:
	if ball != null:
		_guys[ball.get_instance_id()] = guy


func guy_for(ball: Ball) -> Dictionary:
	if ball == null:
		return {}
	return _guys.get(ball.get_instance_id(), {})


func live() -> Array[Ball]:
	_prune()
	return _balls.duplicate()


func count() -> int:
	_prune()
	return _balls.size()


## The ball nearest danger (largest y — closest to the flipper line). Camera and player
## attention belong to the ball that can die next.
func primary() -> Ball:
	_prune()
	var best: Ball = null
	var best_y := -INF
	for b in _balls:
		var y := b.global_position.y if b.is_inside_tree() else b.position.y
		if best == null or y > best_y:
			best = b
			best_y = y
	return best


func clear() -> void:
	_balls.clear()
	_guys.clear()
	count_changed.emit(0)


func _on_ball_exiting(ball: Ball) -> void:
	unregister(ball)


## Freed balls normally leave via tree_exiting → unregister; this catches anything that
## slipped past (guy entries for such strays are cleaned by the next clear()).
func _prune() -> void:
	for i in range(_balls.size() - 1, -1, -1):
		if not is_instance_valid(_balls[i]):
			_balls.remove_at(i)
