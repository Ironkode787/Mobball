class_name LedgerStyle
extends RefCounted
## Shared presentation vocabulary for the Ledger board: the palette it paints with and the
## English it turns effect dictionaries into. Consts and statics only — no state, no nodes.
##
## The four reserved colors (dirty / clean / heat / cop) mirror docs/07 §1 and Feel.COL_*;
## they are repeated here rather than read off the Feel autoload so the board's palette is
## one block a reader can check against the doc.

# --- palette (docs/07 §1) -----------------------------------------------------

const INK := Color("12100E")
const NEWSPRINT := Color("F2E8D5")
const BRASS := Color("C9A227")
const DIRTY := Color("E23D3D")
const CLEAN := Color("3FBF6F")
const NEON_TEAL := Color("2EE6D6")
const NEON_ROSE := Color("FF2E63")
const COP_BLUE := Color("3A8DFF")
const VIOLET := Color("8C4DFF")

## Cork: the board's ground, and the kraft-paper back of an undiscovered card.
const CORK := Color("32241A")
const CORK_LIGHT := Color("46331F")
const CORK_SPECK := Color("5A4229")
const CARD_BACK := Color("5A4632")
const CARD_BACK_LINE := Color("6E5740")
const CARD_BACK_INK := Color("8A7355")

## Paper: a live index card, and the yellowed one a purchase has been stamped onto.
const PAPER := Color("F2E8D5")
const PAPER_OWNED := Color("D6C9AE")
const PAPER_EDGE := Color("BFB194")
const INK_SOFT := Color("5A5248")
const SHADOW := Color(0.0, 0.0, 0.0, 0.38)

## One accent per branch — districts on the map under the cork.
const BRANCH_COLORS := {
	"rackets": Color("C9A227"),
	"fronts": Color("2EE6D6"),
	"muscle": Color("E2703D"),
	"crew": Color("8C4DFF"),
	"influence": Color("3A8DFF"),
	"blackbook": Color("FF2E63"),
}

const BRANCH_TITLES := {
	"rackets": "RACKETS",
	"fronts": "FRONTS",
	"muscle": "MUSCLE",
	"crew": "CREW",
	"influence": "INFLUENCE",
	"blackbook": "BLACK BOOK",
}


static func branch_color(branch: String) -> Color:
	return BRANCH_COLORS.get(branch, BRASS)


static func branch_title(branch: String) -> String:
	return BRANCH_TITLES.get(branch, branch.to_upper())


# --- effect English -----------------------------------------------------------


## "storefront_laundromat" -> "Storefront Laundromat".
static func pretty(id: String) -> String:
	return id.replace("_", " ").capitalize()


## A multiplier as the change it makes: 1.25 reads "+25%", 0.9 reads "-10%".
static func percent(value: float) -> String:
	return _points((value - 1.0) * 100.0)


## One human line per effect, for the docket. `per_level` effects say so — the player is
## reading this to decide whether a repeat is worth the escalating price.
static func effect_line(effect: Dictionary) -> String:
	var kind: StringName = effect["kind"]
	var target := String(effect["target"])
	var num := float(effect["num"])
	var money: BigMoney = effect["money"]
	var each := " per level" if bool(effect["per_level"]) else ""
	match kind:
		&"unlock_hardware":
			return "Installs %s on the table" % pretty(target)
		&"feature_flag":
			return "Unlocks %s" % pretty(target)
		&"value_mult":
			return "%s on %s hits%s" % [percent(num), target, each]
		&"value_add":
			return "%s flat on every %s hit" % [money.text(), target]
		&"idle_rate_add":
			return "%s/sec idle from %s" % [money.text(), target]
		&"launder_rate_add":
			return "+%d%% washed per loop pass%s" % [int(roundf(num * 100.0)), each]
		&"launder_cap_add":
			return "+%s wash cap per Night%s" % [money.text(), each]
		&"pocket_money_set":
			return "Pocket Money becomes %s a Night" % money.text()
		&"passive_wash_add":
			return "+%.1f%%/sec passive wash while armed%s" % [num * 100.0, each]
		&"safe_hours_set":
			return "The Safe holds %dh of idle%s" % [int(roundf(num)), each]
		&"bench_slot_add":
			return "+%d Bench slot%s%s" % [int(roundf(num)), _s(num), each]
		&"ball_save_charges":
			return "+%d ball save%s a Night%s" % [int(roundf(num)), _s(num), each]
		&"tilt_leans_add":
			return "+%d lean%s before the Inspector calls it%s" % [int(roundf(num)), _s(num), each]
		&"flipper_power_mult":
			return "%s flipper power%s" % [percent(num), each]
		&"kickback_unlock":
			return "Kickback on the %s outlane" % target
		&"bribe_unlock":
			return "The Beat Cop takes a bribe (hit the donut shop)"
		&"job_slots_set":
			return "Job board holds %d slips" % int(roundf(num))
		&"collect_minutes_mult":
			return "%s storefront collect%s" % [percent(num), each]
		&"heat_decay_mult":
			return "%s Heat decay%s" % [percent(num), each]
		&"bail_discount":
			return "Bail costs %s less%s" % [_pct(num), each]
		&"auto_collect_interval":
			# The MIN bucket divides by level, so a level is another award in the same window.
			var window := " (one more award per level)" if bool(effect["per_level"]) else ""
			return "A lit award collects itself every %s%s" % [_secs(num), window]
		&"casino_edge_add":
			return "+%s casino edge your way%s" % [_pct(num), each]
		&"casino_pocket_add":
			return "+%d wheel pocket%s pays you instead of the house%s" % [int(roundf(num)), _s(num), each]
		&"job_reroll_add":
			return "+%d Job reroll%s a Night%s" % [int(roundf(num)), _s(num), each]
		&"job_respect_mult":
			return "%s Respect from Jobs%s" % [percent(num), each]
		&"serve_speed_mult":
			return "%s faster ball service%s" % [percent(num), each]
		&"auto_launder_per_sec":
			return "%s/sec of held dirty washes itself%s" % [_pct(num), each]
		&"kickback_cooldown_mult":
			return "%s kickback cooldown%s" % [percent(num), each]
		&"aim_line":
			return "Case the Joint draws a ghost aim line (strength %d)%s" % [int(roundf(num)), each]
		&"all_dirty_mult":
			return "%s on ALL dirty%s" % [percent(num), each]
		&"launder_cap_mult":
			return "%s wash cap per Night%s" % [percent(num), each]
		&"clean_share":
			# Said as what the player sees happen, not as the accounting: a slice of the
			# payout is already clean when it lands. The cap it draws against is the
			# docket's next line down, not this one's job.
			return "%s of every dirty payout lands clean%s" % [_pct(num), each]
	return String(kind)


## The same sentence, but with the effect folded to what owning `level` of it actually gives:
## "+25% per level" at level 3 reads "+95%". Uses the engine's own fold shapes, so the docket
## can never promise a curve Stats does not apply.
static func effect_line_at(effect: Dictionary, level: int) -> String:
	return effect_line(_at_level(effect, level))


## What one more level moves the number by, in the unit the two lines above are printed in —
## so "+95%" → "+144%" is annotated "+49%" and the three numbers agree on screen.
static func effect_delta(effect: Dictionary, level: int) -> String:
	var kind: StringName = effect["kind"]
	if not bool(effect["per_level"]):
		return ""
	var money: BigMoney = effect["money"]
	if money != null and money.is_positive():
		return "+%s" % money.text()
	var now := Stats.scaled_value(effect, maxi(level, 1))
	var next := Stats.scaled_value(effect, maxi(level, 1) + 1)
	match kind:
		&"value_mult", &"flipper_power_mult", &"collect_minutes_mult", &"heat_decay_mult", \
		&"job_respect_mult", &"serve_speed_mult", &"kickback_cooldown_mult", &"all_dirty_mult", \
		&"launder_cap_mult":
			# Off the ROUNDED percentages, not the raw floats: the delta has to be the gap
			# between the two numbers printed above it, or the docket does not add up.
			return _points(_shown((next - 1.0) * 100.0) - _shown((now - 1.0) * 100.0))
		&"launder_rate_add", &"passive_wash_add", &"auto_launder_per_sec", &"bail_discount", \
		&"casino_edge_add", &"clean_share":
			return _points(_shown(next * 100.0) - _shown(now * 100.0))
		&"safe_hours_set":
			return "%+dh" % int(roundf(next - now))
		&"auto_collect_interval":
			var shaved := next - now
			return ("%+.1fs" % shaved) if absf(shaved) < 10.0 else ("%+.0fs" % shaved)
	return "%+d" % int(roundf(next - now))


# --- formatting -----------------------------------------------------------------


## A plain fraction as a percentage, unsigned: 0.05 reads "5%", 0.004 reads "0.4%".
static func _pct(value: float) -> String:
	var pct := value * 100.0
	if absf(pct - roundf(pct)) < 0.05:
		return "%d%%" % int(roundf(pct))
	return "%.1f%%" % pct


## A signed percentage, whole numbers where whole numbers will do.
static func _points(pct: float) -> String:
	if absf(pct - roundf(pct)) < 0.05:
		return "%+d%%" % int(roundf(pct))
	return "%+.1f%%" % pct


## The value a percentage actually prints as, so a delta can be taken between two of them.
static func _shown(pct: float) -> float:
	return roundf(pct) if absf(pct - roundf(pct)) < 0.05 else roundf(pct * 10.0) / 10.0


## Plural "s" — the next-level preview folds counts, so "+4 Bench slot" would show up a lot.
static func _s(count: float) -> String:
	return "" if is_equal_approx(absf(count), 1.0) else "s"


static func _secs(value: float) -> String:
	return ("%.0fs" % value) if absf(value - roundf(value)) < 0.05 else ("%.1fs" % value)


## The effect as owning `level` of it leaves it: the numbers folded, the "per level" dropped.
static func _at_level(effect: Dictionary, level: int) -> Dictionary:
	var out := effect.duplicate()
	out["num"] = Stats.scaled_value(effect, level)
	out["money"] = Stats.scaled_money(effect, level)
	out["per_level"] = false
	return out


## Godot's default button theme is a grey box; every button on this screen is repainted
## from the palette instead, in one place.
static func style_button(b: Button, bg: Color, fg: Color) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		var c := bg
		match state:
			"hover":
				c = bg.lightened(0.10)
			"pressed":
				c = bg.darkened(0.18)
			"disabled":
				c = Color(INK, 0.14)
			"focus":
				c = Color(0.0, 0.0, 0.0, 0.0)
				sb.border_color = BRASS
				sb.set_border_width_all(2)
		sb.bg_color = c
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 18.0
		sb.content_margin_right = 18.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(INK, 0.55))


# --- the Black Book (docs/06) -------------------------------------------------


## Juice, the prestige currency: a plain count, never a money string. "1 JUICE", "15 JUICE".
static func juice(amount: int) -> String:
	return "%d JUICE" % amount


## One human line per prestige-perk effect — the Black Book's half of `effect_line`. The
## shipped board prints each perk's own `note` (docs/06 §3's rule text, verbatim), so this is
## what a Skip Town screen or a debug dump says about the vocabulary itself.
static func perk_line(effect: Dictionary) -> String:
	var kind: StringName = effect["kind"]
	var num := float(effect["num"])
	var each := " per level" if bool(effect["per_level"]) else ""
	match kind:
		&"start_rank":
			return "Start each city at +%d rank%s%s" % [int(roundf(num)), _s(num), each]
		&"kept_specialist":
			return "%d specialist%s comes with you%s" % [int(roundf(num)), _s(num), each]
		&"pocket_city_scale":
			return "Pocket Money scales with the city number"
		&"boss_start_phase":
			return "The city's first Commission fight opens at phase %d" % int(roundf(num))
		&"stash_fraction":
			return "Start with %s of the last city's clean, as dirty" % _pct(num)
		&"bench_starters":
			return "The Bench opens with %d levelled guy%s%s" % [int(roundf(num)), _s(num), each]
		&"star_requirement_mult":
			return "%s ☆ needed in a city you have beaten" % percent(num)
		&"idle_carryover":
			return "The last city keeps paying %s of its idle" % _pct(num)
		&"saint_statue":
			return "%d retired specialist%s watches every future table%s" % [
				int(roundf(num)), _s(num), each]
		&"museum":
			return "Opens the Museum: heist relics socket into set bonuses"
		&"golden_ball_tier":
			return "The Golden Ball unlocks at T%d" % int(roundf(num))
		&"safe_cap_mult":
			return "%s offline Safe cap" % percent(num)
		&"safe_clean_share":
			return "%s of the Safe arrives clean" % _pct(num)
		&"gauntlet":
			return "Opens the Sixth Family: every Commission at one table"
	return String(kind)


## Why the BUY button on a Black Book page is dark, in the player's words.
static func perk_block_reason(block: BlackBook.Block, book: BlackBook, id: String,
		prestige: Prestige) -> String:
	match block:
		BlackBook.Block.DEFERRED:
			return "NOT IN THIS LIFE. YET."
		BlackBook.Block.MAXED:
			return "IN THE BOOK"
		BlackBook.Block.JUICE:
			var short := book.next_cost(id, prestige.owned()) - prestige.juice
			return "NEEDS %d MORE JUICE" % maxi(short, 1)
		BlackBook.Block.REQUIRES:
			var missing: PackedStringArray = []
			for parent in book.parents_of(id):
				if prestige.level_of(parent) < 1:
					missing.append(String(book.def(parent).get("name", parent)))
			return "NEEDS " + ", ".join(missing).to_upper()
		BlackBook.Block.UNKNOWN:
			return "NOT IN THE BOOK"
	return ""


# --- spoils (the trophies) ----------------------------------------------------
##
## A spoil is flow-lane truth (`Commission.FIGHTS`), so the names are READ from there rather
## than copied here — by path, not by class, exactly the way `game/flow/game.gd` reaches the
## meta lane's stores. If that file ever moves, a trophy loses its proper name and keeps its
## card; nothing breaks.

const COMMISSION_PATH := "res://game/flow/bosses/commission.gd"

## Spoil id -> {"name", "from"}, read once per process. Cached because the board asks for
## every trophy on every build and a script constant map is not free.
static var _spoils: Dictionary = {}
static var _spoils_read: bool = false


## The trophy card's descriptor for a `spoil.*` id: its name and whose it was.
static func spoil_descriptor(id: String) -> Dictionary:
	_read_spoils()
	var known: Dictionary = _spoils.get(id, {})
	if known.is_empty():
		# An unknown spoil still gets a card: the career owns it, so the board owes it a nail.
		return {"id": id, "name": pretty(id.trim_prefix("spoil.")).to_upper(), "from": ""}
	return {"id": id, "name": String(known["name"]), "from": String(known["from"])}


static func _read_spoils() -> void:
	if _spoils_read:
		return
	_spoils_read = true
	if not ResourceLoader.exists(COMMISSION_PATH):
		return
	var script: GDScript = load(COMMISSION_PATH)
	if script == null:
		return
	var fights: Variant = script.get_script_constant_map().get("FIGHTS", null)
	if not (fights is Array):
		return
	for f: Variant in fights as Array:
		if not (f is Dictionary):
			continue
		var d := f as Dictionary
		var spoil := String(d.get("spoil", ""))
		if spoil.is_empty():
			continue
		_spoils[spoil] = {
			"name": String(d.get("spoil_name", spoil)),
			"from": String(d.get("name", "")),
		}


## Why the BUY button is dark, in the player's words.
static func block_reason(block: Upgrades.Block, node: Dictionary, catalog: Upgrades, owned: Dictionary) -> String:
	match block:
		Upgrades.Block.RANK:
			return "NEEDS RANK R%d" % int(node["tier"])
		Upgrades.Block.MAXED:
			return "MAXED OUT"
		Upgrades.Block.MONEY:
			return "NOT ENOUGH CLEAN"
		Upgrades.Block.REQUIRES:
			var missing: PackedStringArray = []
			var parents: PackedStringArray = node["requires"]
			for parent in parents:
				if int(owned.get(parent, 0)) < 1:
					var pdef := catalog.def(parent)
					missing.append(String(pdef["name"]) if not pdef.is_empty() else parent)
			return "NEEDS " + ", ".join(missing).to_upper()
		Upgrades.Block.UNKNOWN:
			return "NOT IN THE BOOK"
	return ""
