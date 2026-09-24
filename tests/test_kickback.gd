extends RefCounted
## Big Sal is bought for a faster kickback. The table used to reload in a flat minute whatever
## the Ledger said, so the upgrade took the money and changed nothing.


func run(t: TestCtx) -> void:
	var kick := Kickback.new()
	var nobody := Stats.new()
	nobody.recompute({})
	t.near(kick.reload_seconds(nobody), kick.cooldown_seconds, 0.001,
			"with nobody hired the kickback reloads in its own time")
	var sal := Stats.new()
	sal.recompute({"crew.big_sal": 3})
	t.ok(sal.kickback_cooldown_mult() < 1.0, "Big Sal shortens the kickback's reload in the Ledger")
	t.near(kick.reload_seconds(sal), kick.cooldown_seconds * sal.kickback_cooldown_mult(), 0.001,
			"the table reloads as fast as the Ledger promised")
	kick.free()
