extends Node
## Process-wide presentation services. No physics or economy code depends on this node.

var theme := PresentationTheme.defaults()
var city := CitySkin.eastport()
var art := ArtCatalog.new()
var safe := PresentationSafeArea.new()
var fx := EffectBus.new()
var budget := PresentationBudget.new()


func _ready() -> void:
	safe.name = "SafeArea"
	fx.name = "EffectBus"
	budget.name = "Budget"
	add_child(safe)
	add_child(fx)
	add_child(budget)
	_connect_gameplay_events()


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
