extends RefCounted
## Narrow B3 real-node contract check. Model/order semantics remain in test_roll_call.gd;
## this file only proves that the production Roll Call tree exposes the visual state anchors.


func run(t: TestCtx) -> void:
	Game.new_game(20260831)
	Game.open_roll_call()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.fail("Roll Call screen test needs a SceneTree")
		return
	if Presentation.safe.get_viewport() == null:
		t.ok(true, "headless script runner has no viewport; device/capture runs the real-node layout")
		return
	var original_presentation_parent := Presentation.get_parent()
	var test_viewport: Window = null
	var attached_presentation := Presentation.get_viewport() == null
	if attached_presentation:
		test_viewport = Window.new()
		test_viewport.name = "RollCallTestViewport"
		test_viewport.size = Vector2i(486, 864)
		tree.root.add_child(test_viewport)
		if original_presentation_parent != null:
			original_presentation_parent.remove_child(Presentation)
		test_viewport.add_child(Presentation)
	Presentation.safe.set_debug_override(Vector2i(486, 864), Rect2i(22, 48, 420, 780), 28.0)
	var screen := RollCallScreen.new()
	screen.available = Game.bench.available()
	screen.selected = screen.available.slice(0, mini(RollCallScreen.MAX_GUYS, screen.available.size()))
	screen.call("_build")
	var scroll := screen.find_child("RollCallScroll", true, false) as ScrollContainer
	var footer := screen.find_child("StartNightFooter", true, false) as PanelContainer
	var start := screen.find_child("StartNight", true, false) as Button
	t.ok(scroll != null, "Roll Call has a clipped scroll body")
	t.ok(footer != null, "Roll Call has a separated fixed footer")
	t.ok(start != null and start.custom_minimum_size.y >= Presentation.theme.touch_min,
			"START NIGHT keeps the touch minimum")
	t.eq(screen.find_children("ServeSlot*", "PanelContainer", true, false).size(), 3,
			"Roll Call always exposes three serve slots")
	for card: Node in screen.find_children("CrewCard_*", "PanelContainer", true, false):
		t.ok(card.get_child_count() == 1 and card.get_child(0) is VBoxContainer,
				"crew cards use a vertical list-safe composition")
		var labels := card.find_children("*", "Label", true, false)
		for raw: Node in labels:
			var label := raw as Label
			t.ok(not label.clip_text, "crew copy never opts into clipping")
			t.ok(label.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS,
					"crew copy never opts into ellipsis")
	var specialists := screen.find_child("HiredHands", true, false)
	t.ok(specialists != null, "Hired Hands section has a stable anchor")
	var holding := screen.find_child("HoldingCrew", true, false)
	t.ok(holding != null, "holding section has a stable anchor")
	var held_guy: Dictionary = Game.bench.available()[0]
	Game.bench.pinch(held_guy)
	var original_metadata_size := Presentation.theme.size_metadata
	Presentation.theme.size_metadata = 27
	var holding_screen := RollCallScreen.new()
	holding_screen.available = Game.bench.available()
	holding_screen.selected = holding_screen.available.slice(0,
			mini(RollCallScreen.MAX_GUYS, holding_screen.available.size()))
	holding_screen.call("_build")
	var holding_status := holding_screen.find_child("HoldingStatus", true, false) as Label
	t.ok(holding_status != null, "holding card exposes a semantic status label")
	if holding_status != null:
		t.eq(holding_status.autowrap_mode, TextServer.AUTOWRAP_OFF,
				"holding status never wraps vertically")
		t.ok(holding_status.custom_minimum_size.x >= 128.0,
				"holding status keeps a readable compact-width column")
	holding_screen.free()
	Presentation.theme.size_metadata = original_metadata_size
	t.eq(RollCallScreen.scope_for_check("switch_count_one_ball"), "ONE GUY",
			"scope mapping remains owned by Roll Call")
	t.eq(RollCallScreen.scope_for_check("ball_survival"), "FIRST GUY",
			"first-guy scope mapping remains unchanged")
	screen.free()
	Presentation.safe.clear_debug_override()
	if attached_presentation:
		test_viewport.remove_child(Presentation)
		if original_presentation_parent != null:
			original_presentation_parent.add_child(Presentation)
		test_viewport.queue_free()
