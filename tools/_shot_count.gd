extends Node2D
## Throwaway screenshot rig for the flow lane's screens (deleted after use).

func _ready() -> void:
	var main: Main = load("res://game/main.tscn").instantiate()
	main.auto_start = false
	add_child(main)
	await get_tree().process_frame
	main.start_session("user://shot_count.json")
	Game.new_game(4242)
	Game.buy_upgrade("muscle.real_plunger", BigMoney.zero())
	Game.buy_upgrade("rackets.trash_2", BigMoney.zero())
	Game.start_night()
	Game.earn_switch(&"bumpers", BigMoney.from_float(1800.0))
	Game.earn_switch(&"slings", BigMoney.from_float(900.0))
	Game.earn_switch(&"spinner", BigMoney.from_float(600.0))
	Game.add_respect(12, &"job")
	Game.night_jobs.append("Send a Message")
	Game.launder(0.2, BigMoney.parse("5K"))
	if main.night != null:
		for g in main.night.lineup:
			Game.bench.pinch(g)
	Game.end_night({"guys_lost": 3, "tilts": 0, "raid": "", "guys_fielded": 3})
	await get_tree().process_frame
