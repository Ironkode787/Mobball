extends Node
## Dumps the table's geometry, as the game evaluates it, for the playfield art
## (tools/texgen/playfield_art.py). Run through tools/texgen/playfield.sh.

const OUT := "res://tools/texgen/playfield_layout.json"


func _ready() -> void:
	var d := {}
	var consts: Dictionary = (load("res://game/table/layout.gd") as GDScript).get_script_constant_map()
	for k: String in consts:
		var v: Variant = _plain(consts[k])
		if v != null:
			d[k] = v
	var w := Layout.PLAY_RIGHT - Layout.PLAY_LEFT + Layout.OUTER_THICK
	var depth := Layout.PLAY_BOTTOM - Layout.PLAY_TOP + Layout.OUTER_THICK
	var center_z := (Layout.PLAY_TOP + Layout.PLAY_BOTTOM) * 0.5
	# the street mesh's UV rectangle (ProgressionTable._build_cabinet)
	d["field"] = {"x0": -w * 0.5, "z0": center_z - depth * 0.5, "w": w, "d": depth}
	var arrows := {}
	for shot: StringName in InsertField.ARROWS:
		arrows[String(shot)] = _plain(InsertField.ARROWS[shot])
	d["arrows"] = arrows
	var mid := []
	var a := 150.0
	while a <= 390.0:
		mid.append([a, _plain(Layout.channel_mid(a))])
		a += 2.0
	d["channel_mid"] = mid
	d["rail"] = _plain(Layout.rail_points(Layout.RAIL_TOP_DEG, 360.0, 48))
	d["launch_wall"] = _plain(Layout.launch_wall_points(20))
	d["club_outline"] = _plain(ClubDeck.outline())
	d["club"] = {"front": ClubDeck.DECK_FRONT, "left": ClubDeck.DECK_LEFT, "right": ClubDeck.DECK_RIGHT,
			"return_path": _plain(ClubDeck.RETURN_PATH)}
	var sides := {}
	for s: float in [-1.0, 1.0]:
		sides["%d" % int(s)] = {
			"sling": _plain([Layout.mx(Layout.SLING_OUTER_BOTTOM, s), Layout.mx(Layout.SLING_INNER, s),
					Layout.mx(Layout.SLING_OUTER_TOP, s)]),
			"inlane_x": Layout.inlane_guide_x(s),
		}
	d["sides"] = sides
	d["dome_at"] = _plain(CityHall.DOME_AT)
	d["crates_origin"] = _plain(Docks.CRATES_ORIGIN)
	d["penthouse_table"] = _plain(Penthouse.TABLE_AT)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t", true))
	f.close()
	print("playfield layout: %d keys -> %s" % [d.size(), ProjectSettings.globalize_path(OUT)])
	get_tree().quit(0)


static func _plain(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT, TYPE_INT, TYPE_BOOL:
			return v
		TYPE_STRING, TYPE_STRING_NAME:
			return String(v)
		TYPE_VECTOR2:
			return [snappedf((v as Vector2).x, 0.0001), snappedf((v as Vector2).y, 0.0001)]
		TYPE_VECTOR3:
			var v3 := v as Vector3
			return [snappedf(v3.x, 0.0001), snappedf(v3.y, 0.0001), snappedf(v3.z, 0.0001)]
		TYPE_RECT2:
			var r := v as Rect2
			return [r.position.x, r.position.y, r.size.x, r.size.y]
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var out := []
			for e: Variant in v:
				out.append(_plain(e))
			return out
	return null
