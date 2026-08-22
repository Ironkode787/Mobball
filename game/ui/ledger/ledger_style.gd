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


static func percent(value: float) -> String:
	var pct := (value - 1.0) * 100.0
	if absf(pct - roundf(pct)) < 0.05:
		return "%+d%%" % int(roundf(pct))
	return "%+.1f%%" % pct


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
			return "+%d Bench slot%s" % [int(roundf(num)), each]
		&"ball_save_charges":
			return "+%d ball save a Night%s" % [int(roundf(num)), each]
		&"tilt_leans_add":
			return "+%d lean before the Inspector calls it%s" % [int(roundf(num)), each]
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
	return String(kind)


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
