extends Node
## Process-wide presentation services. No physics or economy code depends on this node.

const PHASE_ONE_ART := {
	&"table.backglass.eastport": preload("res://assets/art/eastport/backglass.png"),
	&"ui.count_room_plate": preload("res://assets/art/eastport/count_room.png"),
	&"prop.trash_can": preload("res://assets/art/eastport/trash_can_bumper.png"),
	&"prop.bicycle_spinner": preload("res://assets/art/eastport/bicycle_spinner.png"),
	&"prop.payphone_bank": preload("res://assets/art/eastport/payphone.png"),
	&"ui.job_board": preload("res://assets/art/eastport/job_board.png"),
	&"front.laundromat": preload("res://assets/art/eastport/laundromat.png"),
	&"front.pizzeria": preload("res://assets/art/eastport/pizzeria.png"),
	&"front.pawn": preload("res://assets/art/eastport/pawn_shop.png"),
	&"mugshot.starter_01": preload("res://assets/art/portraits/starter_01.png"),
	&"mugshot.starter_02": preload("res://assets/art/portraits/starter_02.png"),
	&"mugshot.starter_03": preload("res://assets/art/portraits/starter_03.png"),
	&"mugshot.starter_04": preload("res://assets/art/portraits/starter_04.png"),
}

var theme := PresentationTheme.defaults()
var city := CitySkin.eastport()
var art := ArtCatalog.new()
var safe := PresentationSafeArea.new()
var fx := EffectBus.new()
var budget := PresentationBudget.new()


func _init() -> void:
	_register_phase_one_art()


func _ready() -> void:
	safe.name = "SafeArea"
	fx.name = "EffectBus"
	budget.name = "Budget"
	add_child(safe)
	add_child(fx)
	add_child(budget)
	_connect_gameplay_events()


func _register_phase_one_art() -> void:
	for id: StringName in PHASE_ONE_ART:
		art.register(id, PHASE_ONE_ART[id] as Texture2D)


func set_city(next: CitySkin) -> void:
	if next != null:
		city = next


func _connect_gameplay_events() -> void:
	Events.switch_hit.connect(func(id: StringName, _ball: Node2D, strength: float) -> void:
		fx.request(&"impact", {"id": id, "strength": strength}))
	Events.dirty_earned.connect(func(amount: BigMoney, group: StringName) -> void:
		fx.request(&"currency", {"currency": &"dirty", "amount": amount, "group": group}))
	Events.laundered.connect(func(amount: BigMoney) -> void:
		fx.request(&"currency", {"currency": &"clean", "amount": amount}))
	Events.combo_changed.connect(func(count: int) -> void:
		fx.request(&"combo", {"count": count}))
	Events.rank_changed.connect(func(rank: int) -> void:
		fx.request(&"rank", {"rank": rank}))
	Events.raid_started.connect(func() -> void: fx.request(&"mode", {"id": &"raid", "active": true}))
	Events.raid_ended.connect(func(survived: bool) -> void:
		fx.request(&"mode", {"id": &"raid", "active": false, "survived": survived}))
	Events.tilted.connect(func() -> void: fx.request(&"mode", {"id": &"tilt", "active": true}))
