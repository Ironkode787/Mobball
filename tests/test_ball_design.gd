extends RefCounted
## Ball faces are identity, not gameplay state: deterministic, high-contrast and shared with UI.


func run(t: TestCtx) -> void:
	var first := BallDesign.for_guy({"id": 7, "name": "Sal", "trait": "heavy"})
	var loaded := BallDesign.for_guy({"id": 7, "name": "Different Name", "trait": "lucky"})
	t.eq(first, loaded, "the numeric id is the stable identity seed")

	var signatures := {}
	for id in range(1, 257):
		var d := BallDesign.for_id(id)
		var signature := "%d/%d/%d/%s" % [int(d["band"]), int(d["crest"]),
			int(d["base_color"].to_rgba32()), String(d["band_geometry"])]
		t.ok(not signatures.has(signature), "roster id %d has a distinct band/crest design" % id)
		signatures[signature] = id
	t.eq(signatures.size(), 256, "ids 1..256 all have recognizable identities")

	var anonymous := BallDesign.for_guy({})
	t.eq(bool(anonymous["anonymous"]), true, "anonymous guys use the fallback descriptor")
	t.eq(int(anonymous["id"]), 0, "anonymous fallback has no identity id")
	t.eq(String(anonymous["crest_mark"]), "none", "anonymous fallback has no crest")
	t.eq(String(anonymous["band_geometry"]), "steel", "anonymous fallback has no identity band")

	var ball := Ball.new()
	ball.apply_guy_design({"id": 12, "name": "Franny"})
	t.eq(ball.design(), BallDesign.for_id(12), "Ball accepts and retains the guy design")
	ball.apply_guy_design({})
	t.eq(ball.design(), BallDesign.anonymous(), "empty guy restores steel")
	ball.free()

	var preview_script: GDScript = load("res://game/ui/ball_preview.gd")
	var preview: Control = preview_script.new()
	preview.call("set_guy", {"id": 12, "name": "Franny"})
	t.eq(preview.call("design"), BallDesign.for_id(12), "preview uses the same design descriptor")
	preview.free()
