extends RefCounted
## The save file (game/flow/save.gd): atomic writes, rolling backups, salvage on damage.

const PATH := "user://test_flow_save.json"


func run(t: TestCtx) -> void:
	var save := SaveGame.new(PATH)
	save.erase()
	_round_trip(t, save)
	_backups(t, save)
	_salvage(t, save)
	_migration(t)
	_numbers(t)
	save.erase()
	t.ok(not save.exists(), "erase clears the save and its backups")


func _round_trip(t: TestCtx, save: SaveGame) -> void:
	t.ok(not save.exists(), "a fresh career has no file")
	t.eq(save.read(), {}, "and reading it yields nothing rather than junk")

	var payload := {"respect": 42, "owned": {"muscle.real_plunger": 1}, "night_no": 3}
	t.ok(save.write(payload), "write succeeded: %s" % save.last_error)
	t.ok(save.exists(), "the file is there")

	var back := save.read()
	t.eq(int(back.get("respect", 0)), 42, "ints survive")
	t.eq(int(back.get("version", 0)), SaveGame.VERSION, "the version is stamped on write")
	t.ok(float(back.get("saved_at", 0.0)) > 0.0, "so is the timestamp")
	t.eq(String(save.salvaged_from), "", "a healthy read needs no salvage")


func _backups(t: TestCtx, save: SaveGame) -> void:
	save.write({"n": 2})
	t.ok(FileAccess.file_exists(save.backup1()), "the previous save rolls into bak1")
	save.write({"n": 3})
	t.ok(FileAccess.file_exists(save.backup2()), "and the one before that into bak2")
	t.eq(int(save.read().get("n", 0)), 3, "the newest file is the one that loads")
	t.ok(not FileAccess.file_exists(save.temp_path()), "the temp file never survives a write")


func _salvage(t: TestCtx, save: SaveGame) -> void:
	var f := FileAccess.open(save.path, FileAccess.WRITE)
	t.ok(f != null, "could open the save for damaging")
	if f != null:
		f.store_string("{\"n\": 4, truncated…")
		f.close()
	var got := save.read()
	t.eq(int(got.get("n", 0)), 2, "a shredded save falls back to the newest good backup")
	t.eq(save.salvaged_from, save.backup1(), "and says which file saved the day")

	t.ok(save.write({"n": 5}), "writing over a damaged save works")
	t.eq(int(save.read().get("n", 0)), 5, "and the new file is the one that loads")


func _migration(t: TestCtx) -> void:
	var save := SaveGame.new(PATH)
	var old := save.migrate({"version": 0, "respect": 1})
	t.eq(int(old.get("version", -1)), SaveGame.VERSION, "an older file is stamped forward")
	t.eq(int(old.get("respect", 0)), 1, "and keeps its contents")
	var future := save.migrate({"version": SaveGame.VERSION + 5, "respect": 9})
	t.eq(int(future.get("respect", 0)), 9, "a newer file loads what we understand")


## uint64 RNG state has to survive JSON, which only has doubles.
func _numbers(t: TestCtx) -> void:
	var big := 1234567890123456789
	t.eq(SaveGame.to_i64(str(big), 0), big, "a uint64 rides through as text, exactly")
	t.eq(SaveGame.to_i64(7, 0), 7, "plain numbers still load")
	t.eq(SaveGame.to_i64(null, 99), 99, "a missing field falls back")
