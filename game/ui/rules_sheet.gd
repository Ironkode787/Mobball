class_name RulesSheet
extends CanvasLayer
## HOW IT WORKS (docs/20 §5): the machine's rules, one card per thing on the board, in the order
## the Ledger builds them. Only what this career has built is explained; what is still to come
## is named in one line at the end, so the sheet grows with the table.
##
## Opened from the front door and, mid-Night, from the HUD's RULES button (the Night waits).

signal closed

## Each rule: the card's title, the one-line promise under it, the body, and the Ledger
## hardware it needs: `needs` is any of them (none means it is always on the board), `needs_all`
## every one. Cards run in the order the Ledger builds the board.
const RULES: Array[Dictionary] = [
	{
		"id": &"basics", "title": "THE BASICS", "eyebrow": "HOW THE MACHINE PAYS",
		"body": "Each guy on your crew is one ball. Everything you hit earns DIRTY cash (red). Only CLEAN cash (green) buys upgrades in the Ledger. The Count washes a little of each Night's dirty cash; Lucky's washes more once it opens.",
		"needs": [],
	},
	{
		"id": &"controls", "title": "THE CONTROLS", "eyebrow": "TWO THUMBS",
		"body": "Hold the lower left or lower right of the screen for that flipper. Pull down in the shooter lane on the right and let go to launch. Flick up or sideways near the top of the screen, or tap a top corner, to nudge the table. Too much and it TILTS: you lose that ball.",
		"needs": [],
	},
	{
		"id": &"combos", "title": "COMBOS", "eyebrow": "CLEAN WORK",
		"body": "Hit different things one after another, each within 4 seconds of the last, and every hit in the chain pays more, up to ×8. Hitting the same kind of thing twice starts the chain again.",
		"needs": [],
	},
	{
		"id": &"alley", "title": "THE ALLEY", "eyebrow": "THE TRASH CANS AT THE TOP",
		"body": "The trash cans are pop bumpers, and every pop pays. The Ledger sells you the second and third cans.",
		"needs": [],
	},
	{
		"id": &"heat", "title": "HEAT", "eyebrow": "THE COPS ARE WATCHING",
		"body": "Dirty cash you earn on the table raises Heat, and Heat raises what the table pays: ×1.5 from 40, ×2.5 from 70, ×4 from 90. It cools when you go quiet. At 100 the cops raid on the spot: keep a ball in play for 45 seconds, or they take 30% of the dirty cash you are holding.",
		"needs": [],
	},
	{
		"id": &"briefcases", "title": "BRIEFCASES", "eyebrow": "THE MAN IN THE TRENCH COAT",
		"body": "Now and then a man leaves a briefcase on the table. Hit it before he comes back for it, about a minute later. Mostly it is cash; sometimes a bonus; now and then a setup that brings Heat.",
		"needs": [],
	},
	{
		"id": &"dropoff", "title": "THE DROP-OFF", "eyebrow": "THE THREE LANES ABOVE THE CANS",
		"body": "Roll through all three Drop-Off lanes to raise what every can pays, from 1× up to 8× (CANS PAY, just below the cans). A level fades after a minute. The flipper buttons shift the lit lanes. Plunge into the lane with the flashing arrow for the skill shot: it pays and raises the cans a level.",
		"needs": [&"rollovers"],
	},
	{
		"id": &"luckys", "title": "LUCKY'S", "eyebrow": "THE LAUNDROMAT IN THE MIDDLE",
		"body": "Shoot the laundromat's door, straight up the middle from either flipper. Each visit washes a share of your dirty cash clean, up to a limit each Night. It hands you a Job when there is one and sends the ball out into the Alley.",
		"needs": [&"laundromat_loop"],
	},
	{
		"id": &"spinner", "title": "THE NUMBERS", "eyebrow": "THE SPINNER",
		"body": "The spinner in the left lane pays every turn. While a Job is running, each turn buys a little time back on its fuse, up to 20 seconds a Job.",
		"needs": [&"spinner_numbers"],
	},
	{
		"id": &"kickbacks", "title": "KICKBACKS", "eyebrow": "THE ENFORCER AND THE RIGHT-HAND MAN",
		"body": "When lit, the kickback at the bottom of an outlane throws a ball that would drain back up the table. It lights again a minute after it fires; Big Sal makes that quicker.",
		"needs": [&"kickback_left", &"kickback_right"],
	},
	{
		"id": &"beat_cop", "title": "THE BEAT COP", "eyebrow": "ON THE LEFT",
		"body": "Hit the Beat Cop to slip him a bribe: −20 Heat for some dirty cash, and the price doubles with each bribe in a Night. He takes it on every hit, even when your Heat is low.",
		"needs": [&"bribe_target"],
	},
	{
		"id": &"jobs", "title": "JOBS", "eyebrow": "TONIGHT'S WORK",
		"body": "Lucky's gives you a Job: its shots light up with flashing arrows. Make them before the fuse burns down for Respect and cash. Hit a payphone on the right first to pick which Job it gives you. A blown fuse costs nothing but time.",
		"needs_all": [&"wire_bank", &"laundromat_loop"],
	},
	{
		"id": &"phone", "title": "THE PHONE", "eyebrow": "IT RINGS",
		"body": "Every couple of minutes a payphone rings for a few seconds. Hit a payphone to answer it: a tip, a bet or a job, always worth something. Letting it ring out is free, unless it was your grandmother.",
		"needs": [&"wire_bank"],
	},
	{
		"id": &"big_score", "title": "THE BIG SCORE", "eyebrow": "ALL THREE JOBS DONE",
		"body": "Finish all three of Tonight's Work and Lucky's lights BIG SCORE. Shoot it: a second ball comes into the Alley and every other lit arrow is a jackpot. Collect them all, then shoot Lucky's for the vault (five jackpots) and the arrows light again. It ends when you are down to one ball.",
		"needs_all": [&"wire_bank", &"laundromat_loop"],
	},
	{
		"id": &"shops", "title": "THE SHOPS", "eyebrow": "NONNA'S AND FAT TONY'S",
		"body": "Knock down all three drops on a shop's front and it pays its protection on the spot. PAID lights and the drops come back up a few seconds later.",
		"needs": [&"storefront_pizzeria", &"storefront_pawn"],
	},
	{
		"id": &"take", "title": "THE TAKE", "eyebrow": "×2 TO ×8",
		"body": "Every shop that pays raises the Take one step. It multiplies Job pay and Big Score jackpots, and it resets when you lose your last ball in play.",
		"needs": [&"storefront_pizzeria", &"storefront_pawn"],
	},
	{
		"id": &"collection", "title": "COLLECTION", "eyebrow": "BOTH SHOPS IN 25 SECONDS",
		"body": "The first shop to pay starts a 25-second COLLECTION. Collect the other before the clock runs out and it pays double; the first perfect round of a Night is worth ☆10. Miss it and nothing is lost.",
		"needs_all": [&"storefront_pizzeria", &"storefront_pawn"],
	},
	{
		"id": &"orbits", "title": "THE ORBITS", "eyebrow": "GETAWAY AND TRUCK ROUTE",
		"body": "The lanes up either side loop round the top of the board and bring the ball back to the flipper that shot it.",
		"needs": [&"orbit_left", &"orbit_right"],
	},
	{
		"id": &"sewer", "title": "THE SEWER", "eyebrow": "A SHORTCUT",
		"body": "Two Getaways inside 15 seconds open the Sewer for 30 seconds: roll over a lit manhole in the Street and the ball comes up in the Alley, among the cans.",
		"needs_all": [&"sewer", &"orbit_left"],
	},
	{
		"id": &"club", "title": "THE CLUB", "eyebrow": "UP THE STAIRCASE",
		"body": "The Staircase ramp on the left climbs to the casino deck: the slot reels, the roulette wheel and the back room. Every roulette landing bets 5% of your dirty cash. Stop all three reels in one visit for the jackpot. Whatever rolls off the deck comes home to the left flipper.",
		"needs": [&"staircase_ramp", &"club_deck"],
	},
	{
		"id": &"meeting", "title": "THE FAMILY MEETING", "eyebrow": "THE BACK ROOM",
		"body": "Two slot jackpots or a perfect Collection light the back room. Get the ball into it on the deck: a second guy joins, all dirty cash doubles while both are working, and every trip back into the back room pays a bigger clean jackpot.",
		"needs": [&"backroom_saucer"],
	},
	{
		"id": &"pier", "title": "PIER 9", "eyebrow": "THE DOCKS",
		"body": "The crane at the top right grabs a ball that comes up the right lane and loads a container. Load all three inside 40 seconds and the load ships; a Getaway during the run doubles it.",
		"needs": [&"docks"],
	},
	{
		"id": &"penthouse", "title": "THE PENTHOUSE", "eyebrow": "LUCKY'S ROOF",
		"body": "Raise the cans to 4× or finish a Job and Lucky's roof lights. Shoot Lucky's: the lift carries the ball up to the Sit-Down and Heat stands still for a minute. For 45 seconds the Getaway, Staircase, Nonna's, Fat Tony's and Truck Route each take a family's chair.",
		"needs": [&"penthouse"],
	},
	{
		"id": &"city_hall", "title": "CITY HALL", "eyebrow": "THE DOME",
		"body": "A Getaway at full speed rides the wire round City Hall's dome. A slower one rolls on past.",
		"needs": [&"city_hall"],
	},
]

const BASE_SAFE_MARGINS := Vector4(54.0, 70.0, 54.0, 54.0)

## Whether a piece of the board is built. Defaults to the career's Ledger.
var has_hardware: Callable = func(id: StringName) -> bool: return Game.stats.hardware_unlocked(id)

var _content: MarginContainer = null
var _scroll: ScrollContainer = null
var _body: VBoxContainer = null
var _back: Button = null
var _closed := false


## The rules this board has (in order), and the titles still to come.
static func sort_rules(has: Callable) -> Dictionary:
	var shown: Array[Dictionary] = []
	var later := PackedStringArray()
	for rule: Dictionary in RULES:
		var built := true
		var any: Array = rule.get("needs", [])
		if not any.is_empty():
			built = false
			for id: Variant in any:
				built = built or bool(has.call(StringName(id)))
		for id: Variant in rule.get("needs_all", []):
			built = built and bool(has.call(StringName(id)))
		if built:
			shown.append(rule)
		else:
			later.append(String(rule["title"]))
	return {"shown": shown, "later": later}


func _ready() -> void:
	layer = 96
	process_mode = Node.PROCESS_MODE_ALWAYS

	var shade := ColorRect.new()
	shade.name = "RulesShade"
	shade.color = Color(Feel.COL_INK, 0.97)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	_content = MarginContainer.new()
	_content.name = "SafeContent"
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	_apply_safe_area()
	Presentation.safe.margins_changed.connect(_on_safe_margins_changed)

	var layout := VBoxContainer.new()
	layout.name = "RulesLayout"
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_16")))
	_content.add_child(layout)
	layout.add_child(_type_label("KP // THE RULES", &"metadata", Presentation.theme.brass,
			HORIZONTAL_ALIGNMENT_CENTER, "ProjectMark"))
	layout.add_child(_type_label("HOW IT WORKS", &"hero", Presentation.theme.brass,
			HORIZONTAL_ALIGNMENT_CENTER, "HeroTitle"))
	layout.add_child(PaperKit.rule(Feel.COL_BRASS.darkened(0.42), Presentation.theme.rule_width))

	_scroll = ScrollContainer.new()
	_scroll.name = "RulesScroll"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.clip_contents = true
	layout.add_child(_scroll)

	_body = VBoxContainer.new()
	_body.name = "RulesBody"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_24")))
	_scroll.add_child(_body)
	_build_rules()

	layout.add_child(PaperKit.rule(Feel.COL_BRASS.darkened(0.42), Presentation.theme.rule_width))
	var footer := PaperKit.bottom_action_bar("", "BACK TO THE TABLE" if Game.state == &"night" else "DONE")
	footer.name = "RulesFooter"
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.custom_minimum_size.y = Presentation.theme.touch_min
	_back = footer.get_node_or_null("Actions/Secondary") as Button
	if _back != null:
		_back.name = "RulesBack"
		_back.pressed.connect(_on_back_pressed)
		PaperKit.apply_state(_back, &"focus")
	layout.add_child(footer)
	call_deferred("_focus_back")


func _build_rules() -> void:
	var sorted := sort_rules(has_hardware)
	for rule: Dictionary in sorted["shown"]:
		var section := VBoxContainer.new()
		section.name = "%sRule" % String(rule["id"]).capitalize().replace(" ", "")
		section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
		_body.add_child(section)
		var header := PaperKit.section_header(String(rule["title"]), String(rule["eyebrow"]))
		header.name = "RuleHeader"
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section.add_child(header)
		var card := PaperKit.paper_card()
		card.name = "RuleCard"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card_content := card.get_node("Content") as VBoxContainer
		card_content.add_child(_type_label(String(rule["body"]), &"body", Presentation.theme.ink,
				HORIZONTAL_ALIGNMENT_LEFT, "Copy"))
		section.add_child(card)
		section.set_meta("rule_id", rule["id"])
	var later: PackedStringArray = sorted["later"]
	if not later.is_empty():
		var coming := _type_label("STILL TO BE BUILT AS YOU RISE:  " + "  ·  ".join(later), &"caption",
				Presentation.theme.newsprint.darkened(0.12), HORIZONTAL_ALIGNMENT_CENTER, "StillToCome")
		_body.add_child(coming)


func _type_label(text: String, role: StringName, color: Color,
		align: HorizontalAlignment, node_name: String) -> Label:
	var label := PaperKit.type_label(text, role, color, align)
	label.name = node_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 0.0
	label.clip_text = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _on_back_pressed() -> void:
	if _closed:
		return
	_closed = true
	var viewport := get_viewport()
	if viewport != null and viewport.gui_get_focus_owner() != null:
		var focus := viewport.gui_get_focus_owner()
		if focus == self or is_ancestor_of(focus):
			viewport.gui_release_focus()
	closed.emit()


func _focus_back() -> void:
	if _back != null and is_instance_valid(_back) and _back.is_inside_tree() and _back.visible:
		_back.grab_focus()


func _on_safe_margins_changed(_margins: Vector4) -> void:
	_apply_safe_area()


func _apply_safe_area() -> void:
	Presentation.safe.apply_to_margin_container(_content, BASE_SAFE_MARGINS)


func back_button() -> Button:
	return _back


func scroll_container() -> ScrollContainer:
	return _scroll


## The rule ids the sheet is showing, in order.
func shown_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	if _body == null:
		return out
	for c in _body.get_children():
		if c.has_meta("rule_id"):
			out.append(StringName(c.get_meta("rule_id")))
	return out
