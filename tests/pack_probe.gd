extends SceneTree
## Runs INSIDE an exported pack to verify what the device sees: resource existence,
## remap resolution, and scene instantiation for the paths gameplay loads lazily.


func _initialize() -> void:
	var failures := 0
	for path in [
		"res://game/ui/ledger/ledger.tscn",
		"res://game/content/upgrades.json",
		"res://game/content/blackbook.json",
		"res://game/content/jobs.json",
		"res://game/content/names.json",
		"res://game/content/headlines.json",
		"res://game/meta/prestige.gd",
		"res://game/meta/ledger_state.gd",
		"res://game/meta/reveal.gd",
	]:
		var ex := ResourceLoader.exists(path)
		var fa := FileAccess.file_exists(path)
		var loaded: Resource = null
		if path.ends_with(".json"):
			# JSON is not a Resource: gameplay reads it via FileAccess.
			print("%s | exists=%s file_access=%s" % [path, ex, fa])
			if not fa:
				failures += 1
			continue
		loaded = load(path)
		var inst := "n/a"
		if loaded is PackedScene:
			var node := (loaded as PackedScene).instantiate()
			inst = "ok" if node != null else "NULL"
			if node != null:
				node.free()
		print("%s | exists=%s file_access=%s load=%s inst=%s"
				% [path, ex, fa, loaded != null, inst])
		if not ex or loaded == null:
			failures += 1
	print("PACK PROBE: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(0 if failures == 0 else 1)
