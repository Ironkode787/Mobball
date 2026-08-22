extends SceneTree
## The balance autoplayer's front door (docs/09-TECH.md §7).
##
##     tools/balance.sh --days 14 --profile all --seed 1 --seeds 3
##     godot --headless --path . --script game/sim/balance_cli.gd -- --days 14 --profile all
##
## Prints a per-day career table per profile, the docs/03 §9 target verdicts and a findings
## block; writes the long form to `--report` (default /tmp/kingpin_balance_report.md).
##
## Deliberately NOT part of tools/check.sh — a 14-day × 3-profile × 3-seed run is seconds,
## not milliseconds, and balance is not a build gate yet. `tests/test_sim_smoke.gd` keeps the
## sim compiling and deterministic inside the normal harness instead.
##
## Exit code is 0 unless the run itself broke (bad arguments, unloadable content). Target
## FAILs are reported, not fatal — until the numbers are tuned, a red target is the point of
## the tool, not a build break. `--strict` flips that for CI.

const DEFAULT_REPORT := "/tmp/kingpin_balance_report.md"


func _initialize() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	if args.has("_error"):
		printerr("balance: %s" % args["_error"])
		_usage()
		quit(2)
		return
	if args.has("help"):
		_usage()
		quit(0)
		return

	# `--content` runs the whole sweep against a candidate upgrades.json without touching the
	# shipped one: that is how a proposed data patch gets numbers behind it before anybody
	# commits it. The file is validated by the real loader, so a bad patch fails loudly here.
	var content := String(args.get("content", ""))
	var catalog := Upgrades.from_file(content) if content != "" else Upgrades.shared()
	if not catalog.is_valid():
		printerr("balance: the upgrades catalog %s does not load — fix content first"
				% (content if content != "" else Upgrades.DEFAULT_PATH))
		for e in catalog.errors:
			printerr("  " + e)
		quit(3)
		return

	var days := int(args.get("days", 14))
	var seed_count := maxi(int(args.get("seeds", 3)), 1)
	var base_seed := int(args.get("seed", 1))
	# Flat is the production rule now (balance ruling); --rank-skill re-enables the old
	# ×rank_scale behavior for A/B archaeology.
	SimState.skill_shot_scales_with_rank = bool(args.get("rank-skill", false))
	var wanted := _profiles(String(args.get("profile", "all")))
	if wanted.is_empty():
		printerr("balance: no such profile — have %s" % ", ".join(SimProfile.ids()))
		quit(2)
		return

	var seeds := PackedInt64Array()
	for i in seed_count:
		seeds.append(base_seed + i)

	var started := Time.get_ticks_msec()
	var careers: Dictionary = {}
	for id in wanted:
		var runs: Array = []
		for s in seeds:
			runs.append(SimCareer.run(id, int(s), days, catalog))
		careers[id] = runs
	var elapsed := Time.get_ticks_msec() - started

	var targets := SimTargets.evaluate(careers, catalog)
	if not bool(args.get("quiet", false)):
		print(SimReport.console(careers, targets, catalog, days, seeds, elapsed))

	var report_path := String(args.get("report", DEFAULT_REPORT))
	var text := SimReport.markdown(careers, targets, catalog, days, seeds, elapsed)
	if _write(report_path, text):
		print("\nreport: %s (%d bytes)" % [report_path, text.length()])
	else:
		printerr("balance: could not write %s" % report_path)

	var nights := 0
	for id: Variant in careers:
		for c: Variant in careers[id] as Array:
			nights += (c as SimCareer).nights_played
	print("simulated %d Nights in %.2fs (%.0f Nights/minute)" % [
			nights, float(elapsed) / 1000.0,
			float(nights) * 60000.0 / maxf(float(elapsed), 1.0)])

	var failed := 0
	for t in targets:
		if String(t["verdict"]) == SimTargets.FAIL:
			failed += 1
	if failed > 0:
		print("%d target(s) FAILING — see the report" % failed)
	quit(1 if (failed > 0 and bool(args.get("strict", false))) else 0)


func _profiles(want: String) -> PackedStringArray:
	var all := SimProfile.ids()
	if want == "all":
		return all
	var out: PackedStringArray = []
	for id in want.split(",", false):
		var name := id.strip_edges()
		if all.has(name):
			out.append(name)
	return out


## `--days 14 --profile all --seed 1 --seeds 3 --report path --quiet --strict`.
func _parse(argv: PackedStringArray) -> Dictionary:
	const VALUED: PackedStringArray = ["days", "profile", "seed", "seeds", "report", "content"]
	const FLAGS: PackedStringArray = ["quiet", "strict", "help", "flat-skill"]
	var out: Dictionary = {}
	var i := 0
	while i < argv.size():
		var raw := argv[i]
		if not raw.begins_with("--"):
			return {"_error": "unexpected argument `%s`" % raw}
		var key := raw.substr(2)
		var value := ""
		var eq := key.find("=")
		if eq >= 0:
			value = key.substr(eq + 1)
			key = key.substr(0, eq)
		if FLAGS.has(key):
			out[key] = true
			i += 1
			continue
		if not VALUED.has(key):
			return {"_error": "unknown option `--%s`" % key}
		if value == "":
			i += 1
			if i >= argv.size():
				return {"_error": "`--%s` needs a value" % key}
			value = argv[i]
		if key == "days" or key == "seed" or key == "seeds":
			if not value.is_valid_int():
				return {"_error": "`--%s` wants a whole number, got `%s`" % [key, value]}
			out[key] = value.to_int()
		else:
			out[key] = value
		i += 1
	return out


func _write(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


func _usage() -> void:
	print("""usage: tools/balance.sh [options]
  --days N        simulated days per career (default 14)
  --profile ID    duffer | decent | shark | all | a,b (default all)
  --seed N        first seed (default 1)
  --seeds K       careers per profile, seeds N..N+K-1 (default 3)
  --report PATH   markdown report path (default %s)
  --quiet         skip the console tables
  --strict        exit non-zero when a docs/03 §9 target FAILs
  --content PATH  run against a candidate upgrades.json instead of the shipped one
  --flat-skill    experiment: pin the skill shot to its R0 value instead of ×10 per rank""" % DEFAULT_REPORT)
