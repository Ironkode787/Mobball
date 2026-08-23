class_name CountScreen
extends CanvasLayer
## THE COUNT — the tally room (docs/01 §3). The dopamine ritual and the natural stopping
## point: the numbers roll up with the bill counter, the paper prints the night's headline,
## and the "one more Night" button sits right there lit like a jukebox.
##
## Reads `Game.last_night` (built by NightController + Game.end_night) and renders it. It
## decides nothing — money, respect and laundering are already settled by the time this
## screen exists.

signal ledger_pressed
signal next_night_pressed
## The Commission is asking (specs/m2-content.md §5). The next Night is the fight.
signal boss_pressed
## The war room booked a job for the next Night (docs/05 §5): target, approach, inside man.
signal heist_pressed(target: StringName, approach: StringName, guy: Dictionary)
## The player is getting on the train (docs/06 §1). `keep` is the one guy who comes along.
signal skip_town_pressed(keep: Dictionary)

## Seconds each line takes to roll up, and the gap between the bill-counter ticks.
const LINE_TIME := 0.55
const TICK_INTERVAL := 0.07
const LINE_GAP := 0.12
## Jobs offered on the page at once. The board holds five targets; a Count screen that is
## mostly heist buttons is a menu, not a newspaper.
const HEIST_SLOTS := 2

var summary: Dictionary = {}

var _rows: Array[Dictionary] = []
var _row_index: int = -1
var _row_time: float = 0.0
var _tick_time: float = 0.0
var _headline: Label = null
var _headline_shown: bool = false
var _buttons: HBoxContainer = null
var _roster: VBoxContainer = null
var _safe: PanelContainer = null
var _body: VBoxContainer = null
var _counter: AudioStreamPlayer = null
var _board: VBoxContainer = null


func _ready() -> void:
	layer = 20
	summary = Game.last_night.duplicate() if not Game.last_night.is_empty() else {}
	_build()
	_row_index = 0
	_row_time = 0.0
	# The counter runs under the tally and stops when the last line lands (audio-wave2 §1).
	_counter = AudioDirector.play(&"bill_counter", {"loop": true})


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Feel.COL_NEWSPRINT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 14)
	margin.add_child(_body)

	_body.add_child(PaperKit.label("THE COUNT", PaperKit.FONT_TITLE, Feel.COL_INK))
	_body.add_child(PaperKit.label(
			"NIGHT %d   ·   %s" % [int(summary.get("night", Game.night_no)), Game.rank_title()],
			PaperKit.FONT_SMALL, Feel.COL_INK.lightened(0.35)))
	_body.add_child(PaperKit.rule(Feel.COL_INK, 4.0))

	_build_safe_banner()
	_build_lines()

	_body.add_child(PaperKit.rule(Feel.COL_INK, 4.0))
	_headline = PaperKit.label("", PaperKit.FONT_BIG, Feel.COL_INK)
	_headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_headline.custom_minimum_size = Vector2(0.0, 190.0)
	_headline.modulate.a = 0.0
	_body.add_child(_headline)

	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 8)
	_body.add_child(_roster)
	_build_roster()

	_board = VBoxContainer.new()
	_board.add_theme_constant_override("separation", 6)
	_body.add_child(_board)
	_build_board()

	# The Commission's call sits above the spacer, so it is always on the page: below the
	# buttons it could be pushed off the bottom of a tall tally.
	_build_boss_call()
	_build_war_room()
	_build_train()

	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(grow)

	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 24)
	_body.add_child(_buttons)

	var ledger := PaperKit.button("THE LEDGER")
	ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ledger.pressed.connect(func() -> void: ledger_pressed.emit())
	_buttons.add_child(ledger)

	var next := PaperKit.button("NEXT NIGHT", PaperKit.FONT_BIG, Feel.COL_CLEAN)
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next.pressed.connect(func() -> void: next_night_pressed.emit())
	_buttons.add_child(next)


## THE COMMISSION. The ☆ are in the bank and a rival family wants a word: the next Night is
## the fight, and it stands apart from the ordinary buttons in his own colour so it can never
## be pressed by muscle memory (docs/05 §6 — the fight is a decision, not a step).
func _build_boss_call() -> void:
	var f := Game.boss_waiting()
	if f.is_empty():
		return
	var again := Game.commission.attempts_at(StringName(f["id"])) > 0
	var call_text := String(f.get("call", "THE COMMISSION IS ASKING"))
	if again:
		call_text = "%s   ·   AGAIN" % call_text
	var b := PaperKit.button(call_text, PaperKit.FONT_BIG, Feel.COL_DIRTY)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: boss_pressed.emit())
	_body.add_child(b)
	_body.add_child(PaperKit.label(
			"NO EARNING. NO CLOCK. BEAT HIM AND THE RANK IS YOURS.",
			PaperKit.FONT_SMALL, Feel.COL_INK.lightened(0.35)))


## THE WAR ROOM (docs/05 §5). One button per job that is actually on the board tonight, each
## with what it will cost to set up; the approach and the inside man are picked for you until
## the planning screen lands (TODO(UI): target + approach + crew picker).
func _build_war_room() -> void:
	if not Game.heists_unlocked():
		return
	var offered := 0
	for row in Game.heists.board(Game.night_no):
		if not bool(row["available"]) or offered >= HEIST_SLOTS:
			continue
		offered += 1
		var target := StringName(row["id"])
		var stake := Heists.stake_for(target, Game.stats.idle_rate_total())
		var guy := _inside_man()
		var b := PaperKit.button("%s   ·   %s" % [String(row["name"]), stake.text()],
				PaperKit.FONT_BODY, Feel.COL_CLEAN)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = not Game.wallet.can_afford_dirty(stake)
		b.pressed.connect(func() -> void:
			heist_pressed.emit(target, Heists.QUIET, guy))
		_body.add_child(b)
		var who := "" if guy.is_empty() else "   ·   INSIDE MAN: %s" % String(guy.get("name", ""))
		_body.add_child(PaperKit.label("%s%s" % [String(row["blurb"]), who],
				PaperKit.FONT_SMALL, Feel.COL_INK.lightened(0.35)))


## The best man for the job: whoever on the Bench has a trait the war room can use.
func _inside_man() -> Dictionary:
	if Game.bench == null:
		return {}
	var free := Game.bench.available()
	for g in free:
		if not Heists.inside_man_effect(g).is_empty():
			return g
	return free[0] if not free.is_empty() else {}


## SKIP TOWN (docs/06 §1). Never a step, never in the flow of the ordinary buttons, and it
## says out loud what it costs — a player has to be able to read this and still want it.
func _build_train() -> void:
	if not Game.skip_town_available():
		return
	var preview := Game.skip_town_preview()
	var keep := _inside_man()
	var b := PaperKit.button("SKIP TOWN   ·   %d JUICE" % int(preview["juice"]),
			PaperKit.FONT_BIG, Feel.COL_BRASS)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: skip_town_pressed.emit(keep))
	_body.add_child(b)
	var line := "EVERYTHING GOES. THE BOOK, THE JUICE AND ONE GUY COME WITH YOU"
	if not keep.is_empty():
		line += "   ·   %s" % String(keep.get("name", ""))
	if Game.federal.raids_lost > 0:
		line = "THE CITY IS CLOSING IN.   " + line
	_body.add_child(PaperKit.label(line, PaperKit.FONT_SMALL, Feel.COL_INK.lightened(0.35)))


## Tonight's work, and the Consigliere's rerolls (`job_reroll_add`). Only drawn when there is
## a reroll to spend — an un-hired career sees the board it always saw.
func _build_board() -> void:
	for c in _board.get_children():
		c.queue_free()
	if Game.night_rerolls <= 0:
		return
	var slips := Game.jobs.active_jobs()
	if slips.is_empty():
		return
	_board.add_child(PaperKit.label("THE BOARD   ·   %d REROLL%s" % [Game.night_rerolls,
			"" if Game.night_rerolls == 1 else "S"], PaperKit.FONT_SMALL,
			Feel.COL_INK.lightened(0.35)))
	for i in range(slips.size()):
		var slip: Dictionary = slips[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var name_label := PaperKit.label(String(slip.get("name", slip.get("id", "job"))),
				PaperKit.FONT_SMALL, Feel.COL_INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var b := PaperKit.button("REROLL", PaperKit.FONT_SMALL, Feel.COL_BRASS.darkened(0.2))
		b.pressed.connect(_on_reroll.bind(i))
		row.add_child(b)
		_board.add_child(row)


func _on_reroll(index: int) -> void:
	if not Game.reroll_job(index).is_empty():
		_build_board()


## The Safe: offline earnings waiting since last session (docs/03 §6).
func _build_safe_banner() -> void:
	if Game.safe_pending == null or not Game.safe_pending.is_positive():
		return
	_safe = PaperKit.panel(Feel.COL_INK, Feel.COL_BRASS)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_safe.add_child(row)
	var text := PaperKit.label("THE SAFE  " + Game.safe_pending.text(),
			PaperKit.FONT_BODY, Feel.COL_BRASS)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var collect := PaperKit.button("COLLECT", PaperKit.FONT_BODY)
	collect.pressed.connect(_on_collect_safe)
	row.add_child(collect)
	_body.add_child(_safe)


func _on_collect_safe() -> void:
	Game.collect_safe()
	if _safe != null and is_instance_valid(_safe):
		_safe.queue_free()
		_safe = null


func _build_lines() -> void:
	_rows.clear()
	_add_money_row("DIRTY EARNED", summary.get("dirty", BigMoney.zero()), Feel.COL_DIRTY)
	_add_money_row("LAUNDERED TONIGHT", summary.get("laundered", BigMoney.zero()), Feel.COL_CLEAN)
	if _money(summary.get("pocket", null)).is_positive():
		_add_money_row("   incl. pocket money", summary.get("pocket", BigMoney.zero()),
				Feel.COL_INK.lightened(0.35), PaperKit.FONT_SMALL)
	if _money(summary.get("raid_payout", null)).is_positive():
		_add_money_row("BEAT THE RAP", summary.get("raid_payout", BigMoney.zero()), Feel.COL_CLEAN)
	if _money(summary.get("confiscated", null)).is_positive():
		_add_money_row("CONFISCATED", summary.get("confiscated", BigMoney.zero()), Feel.COL_DIRTY)
	if bool(summary.get("insured", false)):
		_body.add_child(PaperKit.label("THE POLICY COVERED IT — NOTHING WAS TAKEN",
				PaperKit.FONT_SMALL, Feel.COL_CLEAN))
	_build_boss_lines()
	_build_club_lines()
	_build_endgame_lines()
	_add_money_row("CLEAN BALANCE", summary.get("clean", Game.wallet.clean), Feel.COL_CLEAN)
	_add_int_row("RESPECT GAINED", int(summary.get("respect", 0)), Feel.COL_BRASS.darkened(0.25))
	_add_int_row("JOBS DONE", int(summary.get("jobs_done", 0)), Feel.COL_INK)
	for name: Variant in summary.get("jobs", []):
		_body.add_child(PaperKit.label("   " + String(name), PaperKit.FONT_SMALL,
				Feel.COL_INK.lightened(0.35)))


## The Commission's night, when there was one. A win is the loudest line on the page: the
## purse, the spoil that cannot be bought, and the rank it just unlocked. A loss is one line
## and no scolding — the rematch is on the button below (docs/05 §6).
func _build_boss_lines() -> void:
	var boss: Dictionary = summary.get("boss", {})
	if boss.is_empty() or String(boss.get("id", "")).is_empty():
		return
	var who := String(boss.get("name", "THE COMMISSION"))
	if bool(boss.get("won", false)):
		_add_money_row("%s — BEATEN" % who, boss.get("purse", null), Feel.COL_CLEAN)
		var spoil := String(boss.get("spoil_name", ""))
		if not spoil.is_empty():
			_body.add_child(PaperKit.label("   TOOK HIS %s" % spoil, PaperKit.FONT_SMALL,
					Feel.COL_BRASS))
		if _money(summary.get("boss_paid", null)).cmp(_money(boss.get("purse", null))) > 0:
			_add_money_row("   incl. cold storage", summary.get("boss_paid", null),
					Feel.COL_CLEAN, PaperKit.FONT_SMALL)
	else:
		_body.add_child(PaperKit.label("%s IS STILL STANDING" % who, PaperKit.FONT_BODY,
				Feel.COL_DIRTY))


## The M2 modes, each only when it happened. The casino gets three numbers because a
## gambler reads all three: what went in, what came out, and how much of it came out clean.
func _build_club_lines() -> void:
	var casino: Dictionary = summary.get("casino", {})
	if int(casino.get("spins", 0)) > 0:
		_add_money_row("CASINO STAKED", casino.get("staked", null), Feel.COL_DIRTY)
		_add_money_row("   won  (%d of %d spins)" % [int(casino.get("wins", 0)),
				int(casino.get("spins", 0))], casino.get("won", null), Feel.COL_BRASS,
				PaperKit.FONT_SMALL)
		if _money(casino.get("washed", null)).is_positive():
			_add_money_row("   washed clean", casino.get("washed", null), Feel.COL_CLEAN,
					PaperKit.FONT_SMALL)
		if int(casino.get("jackpots", 0)) > 0:
			_add_int_row("   JACKPOTS", int(casino.get("jackpots", 0)), Feel.COL_BRASS,
					PaperKit.FONT_SMALL)

	var meeting: Dictionary = summary.get("meeting", {})
	if int(meeting.get("meetings", 0)) > 0:
		_add_int_row("FAMILY MEETINGS", int(meeting.get("meetings", 0)), Feel.COL_BRASS)
		if _money(meeting.get("paid", null)).is_positive():
			_add_money_row("   back room", meeting.get("paid", null), Feel.COL_CLEAN,
					PaperKit.FONT_SMALL)
	elif bool(meeting.get("lit", false)):
		_body.add_child(PaperKit.label("BACK ROOM STILL LIT", PaperKit.FONT_SMALL,
				Feel.COL_INK.lightened(0.35)))

	var wire: Dictionary = summary.get("wire", {})
	if int(wire.get("draws", 0)) > 0:
		_add_int_row("WIRE DRAWS", int(wire.get("draws", 0)), Feel.COL_INK)
		if int(wire.get("hits", 0)) > 0:
			_add_money_row("   %d hit%s (%d exact)" % [int(wire.get("hits", 0)),
					"" if int(wire.get("hits", 0)) == 1 else "s", int(wire.get("exacts", 0))],
					wire.get("won", null), Feel.COL_BRASS, PaperKit.FONT_SMALL)

	var rounds: Dictionary = summary.get("collection", {})
	if int(rounds.get("rounds", 0)) > 0:
		_add_int_row("COLLECTION ROUNDS RUN", int(rounds.get("rounds", 0)), Feel.COL_INK)
		_add_int_row("   perfect", int(rounds.get("won", 0)), Feel.COL_CLEAN,
				PaperKit.FONT_SMALL)


## The M3 lines, each only when it happened. Same rule as the Club's: a mode that did not
## run does not get a row saying it did not run.
func _build_endgame_lines() -> void:
	var docks: Dictionary = summary.get("smuggling", {})
	if int(docks.get("shipments", 0)) > 0:
		_add_money_row("SHIPMENTS OUT   ·   %d" % int(docks.get("shipments", 0)),
				docks.get("paid", null), Feel.COL_DIRTY)
	elif int(docks.get("runs", 0)) > 0:
		_body.add_child(PaperKit.label("THE SHIPMENT DID NOT MAKE IT", PaperKit.FONT_SMALL,
				Feel.COL_INK.lightened(0.35)))

	var job: Dictionary = summary.get("heist", {})
	if not job.is_empty() and not String(job.get("name", "")).is_empty():
		var line := "%s — %s" % [String(job["name"]),
				"CLEARED" if bool(job.get("cleared", false)) else "BLOWN OUT"]
		_add_money_row(line, job.get("paid", null), Feel.COL_CLEAN)
		if int(job.get("blown", 0)) > 0:
			_body.add_child(PaperKit.label("   %d beat%s got away" % [int(job["blown"]),
					"" if int(job["blown"]) == 1 else "s"], PaperKit.FONT_SMALL,
					Feel.COL_INK.lightened(0.35)))
		if not String(job.get("relic", "")).is_empty():
			_body.add_child(PaperKit.label("   SOMETHING FOR THE COLLECTION",
					PaperKit.FONT_SMALL, Feel.COL_BRASS))

	var chairs: Dictionary = summary.get("chairs", {})
	if int(chairs.get("tonight", 0)) > 0:
		_add_int_row("CHAIRS CLAIMED   ·   %d of %d" % [int(chairs.get("claimed", 0)),
				int(chairs.get("chairs", CommissionChairs.CHAIRS))],
				int(chairs.get("tonight", 0)), Feel.COL_BRASS)

	var election: Dictionary = summary.get("election", {})
	if int(election.get("term_left", 0)) > 0:
		_add_int_row("CITY HALL   ·   NIGHTS LEFT IN THE TERM",
				int(election["term_left"]), Feel.COL_BRASS)
	elif int(election.get("lit", 0)) > 0:
		_add_int_row("DISTRICTS CANVASSED   ·   of %d" % int(election.get("districts", 5)),
				int(election["lit"]), Feel.COL_INK)

	var crown: Dictionary = summary.get("empire", {})
	if int(crown.get("runs", 0)) > 0:
		_add_money_row("EMPIRE MODE   ·   %d" % int(crown["runs"]), crown.get("paid", null),
				Feel.COL_BRASS)

	if _money(summary.get("rico_payout", null)).is_positive():
		_add_money_row("UNTOUCHABLE", summary.get("rico_payout", null), Feel.COL_CLEAN)
	elif String(summary.get("rico", "")) == "lost":
		_body.add_child(PaperKit.label("THE CASE STICKS", PaperKit.FONT_BODY, Feel.COL_DIRTY))

	var cases: Dictionary = summary.get("briefcases", {})
	if int(cases.get("opened", 0)) > 0:
		_add_money_row("BRIEFCASES   ·   %d" % int(cases["opened"]), cases.get("paid", null),
				Feel.COL_DIRTY)
		if int(cases.get("setups", 0)) > 0:
			_body.add_child(PaperKit.label("   %d of them were a setup"
					% int(cases["setups"]), PaperKit.FONT_SMALL, Feel.COL_INK.lightened(0.35)))
	if int(cases.get("missed", 0)) > 0:
		_body.add_child(PaperKit.label("HE LEFT WITH IT", PaperKit.FONT_SMALL,
				Feel.COL_INK.lightened(0.35)))

	var calls: Dictionary = summary.get("phone", {})
	if int(calls.get("answered", 0)) > 0:
		_add_int_row("CALLS TAKEN", int(calls["answered"]), Feel.COL_INK)

	var rat: Dictionary = summary.get("rat", {})
	if bool(rat.get("caught", false)):
		_body.add_child(PaperKit.label("THE RAT IS FLIPPED", PaperKit.FONT_BODY, Feel.COL_CLEAN))
	elif _money(rat.get("skimmed", null)).is_positive():
		_add_money_row("SOMEBODY IS SKIMMING", rat.get("skimmed", null), Feel.COL_DIRTY)

	var fbi: Dictionary = summary.get("federal", {})
	if bool(fbi.get("enabled", false)) and float(fbi.get("value", 0.0)) > 0.0:
		_add_int_row("FEDERAL HEAT   ·   of 200", int(round(float(fbi.get("meter", 100.0)))),
				Color("6EA8FF"))


func _add_money_row(text: String, value: Variant, color: Color, size: int = PaperKit.FONT_BODY) -> void:
	_rows.append(_row(text, color, size, _money(value), 0))


func _add_int_row(text: String, value: int, color: Color, size: int = PaperKit.FONT_BODY) -> void:
	_rows.append(_row(text, color, size, null, value))


static func _money(v: Variant) -> BigMoney:
	return v if v is BigMoney else BigMoney.zero()


func _row(text: String, color: Color, size: int, money: BigMoney, count: int) -> Dictionary:
	var line := HBoxContainer.new()
	var left := PaperKit.label(text, size, Feel.COL_INK)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := PaperKit.label("", size, color, HORIZONTAL_ALIGNMENT_RIGHT)
	right.custom_minimum_size = Vector2(300.0, 0.0)
	line.add_child(left)
	line.add_child(right)
	_body.add_child(line)
	return {"label": right, "money": money, "count": count}


func _build_roster() -> void:
	for c in _roster.get_children():
		c.queue_free()
	_build_crew_strip()
	var held: Array[Dictionary] = []
	if Game.bench != null:
		held = Game.bench.holding()
	if held.is_empty():
		return
	_roster.add_child(PaperKit.label("IN HOLDING", PaperKit.FONT_SMALL,
			Feel.COL_INK.lightened(0.35)))
	for guy: Dictionary in held:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var name_label := PaperKit.label(String(guy["name"]), PaperKit.FONT_SMALL, Feel.COL_INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		# Through `Game`, not the Bench: Cohen's discount is the session's, not the roster's.
		var cost := Game.bail_cost(guy)
		var b := PaperKit.button("BAIL " + cost.text(), PaperKit.FONT_SMALL, Feel.COL_DIRTY)
		b.disabled = not Game.wallet.can_afford_dirty(cost)
		b.pressed.connect(_on_bail.bind(guy))
		row.add_child(b)
		_roster.add_child(row)


## Who was out tonight, with the one line each of them has (docs/01 §4: one visible trait
## line, never a menu). A guy who came in through the back room is marked as such — he was
## not on the card at roll call.
func _build_crew_strip() -> void:
	var crew: Variant = summary.get("guys", [])
	if not (crew is Array) or (crew as Array).is_empty():
		return
	_roster.add_child(PaperKit.label("TONIGHT'S CREW", PaperKit.FONT_SMALL,
			Feel.COL_INK.lightened(0.35)))
	for raw: Variant in crew as Array:
		if not (raw is Dictionary):
			continue
		var g: Dictionary = raw
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var who := String(g.get("name", ""))
		if bool(g.get("meeting", false)):
			who += "  (family meeting)"
		var name_label := PaperKit.label(who, PaperKit.FONT_SMALL, Feel.COL_INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var trait_id := String(g.get("trait", ""))
		row.add_child(PaperKit.label(GuyTraits.label(trait_id).to_upper(),
				PaperKit.FONT_SMALL, Feel.COL_BRASS.darkened(0.2),
				HORIZONTAL_ALIGNMENT_RIGHT))
		_roster.add_child(row)
	_roster.add_child(PaperKit.spacer(10.0))


func _on_bail(guy: Dictionary) -> void:
	if Game.bail_guy(guy):
		_build_roster()


# --- the roll-up --------------------------------------------------------------


func _process(delta: float) -> void:
	if _row_index < 0 or _row_index >= _rows.size():
		if not _headline_shown:
			_show_headline()
		return
	_row_time += delta
	_tick_time += delta
	var t := clampf(_row_time / LINE_TIME, 0.0, 1.0)
	_paint_row(_rows[_row_index], t)
	if _tick_time >= TICK_INTERVAL and t < 1.0:
		_tick_time = 0.0
		AudioDirector.play(&"cash_tick")
	if _row_time >= LINE_TIME + LINE_GAP:
		_row_index += 1
		_row_time = 0.0
		AudioDirector.play(&"coin_drop")


func _paint_row(row: Dictionary, t: float) -> void:
	var l: Label = row["label"]
	if not is_instance_valid(l):
		return
	var money: Variant = row["money"]
	if money is BigMoney:
		l.text = (money as BigMoney).mul(t).text()
	else:
		l.text = str(int(round(float(int(row["count"])) * t)))


## True once every line has rolled up and the paper has printed.
func finished() -> bool:
	return _headline_shown


## Tap anywhere to stop the theatre and see the numbers — the ritual is a gift, not a toll.
func _input(event: InputEvent) -> void:
	var tapped := (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if not tapped:
		return
	if _row_index >= 0 and _row_index < _rows.size():
		skip()


## Finish every roll-up now.
func skip() -> void:
	for row in _rows:
		_paint_row(row, 1.0)
	_row_index = _rows.size()
	_show_headline()


func _show_headline() -> void:
	if _headline_shown:
		return
	_headline_shown = true
	_stop_counter()
	for row in _rows:
		_paint_row(row, 1.0)
	_headline.text = String(summary.get("headline", ""))
	_headline.modulate.a = 1.0
	AudioDirector.play(&"headline_sting")


func _stop_counter() -> void:
	if _counter != null and is_instance_valid(_counter):
		_counter.stop()
	_counter = null


## The screen can be torn down mid-tally (NEXT NIGHT on the first frame).
func _exit_tree() -> void:
	_stop_counter()
