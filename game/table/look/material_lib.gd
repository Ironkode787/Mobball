class_name MaterialLib
extends RefCounted
## The material library for the 3D playfield: PAPERBACK NOIR × ELECTRIC BRASS (docs/07).
## Matter is unsaturated — felt, wood, steel, ink plastic, brass — and only earned light
## glows. Textures are generated once at boot from noise so the build carries no new binary
## assets; the city skin supplies the ambient colours so a re-themed city re-themes the room.

static var _shared: MaterialLib = null

var _cache: Dictionary = {}
var _noise := FastNoiseLite.new()


## One library per process: textures are generated once and every piece shares materials.
static func shared() -> MaterialLib:
	if _shared == null:
		_shared = MaterialLib.new()
	return _shared


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = 0x51A7E
	_noise.frequency = 0.02


func city_color(role: StringName, fallback: Color) -> Color:
	if Presentation != null and Presentation.city != null:
		var c: Color = Presentation.city.material_for(role)
		if c.a > 0.0:
			return c
	return fallback


# ------------------------------------------------------------------- textures -----


## A tileable noise texture around `base`, ±`variation` in value.
func noise_texture(key: String, size: int, base: Color, variation: float, freq: float,
		grain: float = 0.0) -> ImageTexture:
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = key.hash()
	for y in range(size):
		for x in range(size):
			# sampled on a torus so the tile wraps without a seam
			var ax := TAU * float(x) / float(size)
			var ay := TAU * float(y) / float(size)
			var n := _noise.get_noise_3d(cos(ax) * freq, sin(ax) * freq, cos(ay) * freq * 0.7 + sin(ay) * freq * 0.7)
			var v := 1.0 + n * variation + (rng.randf() - 0.5) * grain
			img.set_pixel(x, y, Color(base.r * v, base.g * v, base.b * v))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Straight-grained wood: long streaks along U, broken up by low-frequency noise.
func wood_texture(key: String, base: Color, streak: Color) -> ImageTexture:
	if _cache.has(key):
		return _cache[key]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in range(size):
		var ay := TAU * float(y) / float(size)
		for x in range(size):
			var ax := TAU * float(x) / float(size)
			# streaks run along U: tight noise across V, long along U, sampled on a torus so the
			# tile wraps both ways
			var g := _noise.get_noise_3d(cos(ax) * 1.6, sin(ax) * 1.6, float(y) * 0.55)
			var g2 := _noise.get_noise_3d(cos(ay) * 6.0 + 40.0, sin(ay) * 6.0, float(x) * 0.02)
			var t := clampf(0.5 + g * 1.8 + g2 * 0.5, 0.0, 1.0)
			var c := base.lerp(streak, t * 0.75)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Equirectangular skin for a guy's ball: metallic base, one high-contrast band, a crest.
func ball_texture(design: Dictionary) -> ImageTexture:
	var key := "ball:%s" % [str(design.get("id", 0))]
	if _cache.has(key):
		return _cache[key]
	var w := 128
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var base: Color = design.get("base_color", Color("#C7C9CC"))
	var band: Color = design.get("band_color", Color("#303238"))
	var anonymous := bool(design.get("anonymous", true))
	var band_kind := int(design.get("band", 0))
	var crest := int(design.get("crest", 0))
	for y in range(h):
		var lat := float(y) / float(h)
		for x in range(w):
			var lon := float(x) / float(w)
			var c := base
			if not anonymous:
				var in_band := false
				match band_kind % 4:
					0: in_band = absf(lat - 0.5) < 0.06
					1: in_band = absf(lat - 0.5) < 0.04 or absf(lat - 0.3) < 0.03 or absf(lat - 0.7) < 0.03
					2: in_band = fmod(lon * 4.0, 1.0) < 0.12
					_: in_band = absf(lat - 0.5 - sin(lon * TAU) * 0.12) < 0.05
				if in_band:
					c = band
				var dx := lon - 0.25
				var dy := (lat - 0.5) * 2.0
				if crest % 2 == 0 and dx * dx + dy * dy * 0.25 < 0.004:
					c = band
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## The storm grate: ink with red-lit slits.
func grate_texture() -> ImageTexture:
	var key := "grate"
	if _cache.has(key):
		return _cache[key]
	var w := 128
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var ink := Color("12100E")
	var glow := Color("E23D3D")
	for y in range(h):
		for x in range(w):
			var slit := (x % 16) > 10 and y > 6 and y < h - 6
			img.set_pixel(x, y, glow if slit else ink.lightened(0.08))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


# ---------------------------------------------------------------- PBR sets -------

const TEX_DIR := "res://assets/textures/"


## One map of a Poly Haven set fetched by tools/texgen/fetch.py, or null when it is not there.
func tex(asset: String, map: String, res: String = "1k") -> Texture2D:
	var path := "%s%s/%s_%s_%s.jpg" % [TEX_DIR, asset, asset, map, res]
	var key := "tex:" + path
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_cache[key] = t
	return t


func has_set(asset: String) -> bool:
	return tex(asset, "diffuse") != null or tex(asset, "diffuse", "2k") != null


## A lit surface from a PBR set: albedo tinted by `tint`, normal and roughness maps when the
## set carries them. `tiles_per_unit` sets the UV scale for meshes whose UVs are in units.
func pbr(key: String, asset: String, tint: Color, tiles_per_unit: float = 1.0,
		diffuse_res: String = "1k") -> StandardMaterial3D:
	return _std(key, func(m: StandardMaterial3D) -> void:
		m.albedo_color = tint
		m.albedo_texture = tex(asset, "diffuse", diffuse_res)
		var n := tex(asset, "nor_gl")
		if n != null:
			m.normal_enabled = true
			m.normal_texture = n
			m.normal_scale = 0.7
		var r := tex(asset, "rough")
		if r != null:
			m.roughness_texture = r
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness = 1.0
		m.metallic = 0.0
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.uv1_scale = Vector3(tiles_per_unit, tiles_per_unit, tiles_per_unit))


# ------------------------------------------------------------------ materials -----


func _std(key: String, builder: Callable) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	builder.call(m)
	_cache[key] = m
	return m


func felt() -> StandardMaterial3D:
	return _std("felt", func(m: StandardMaterial3D) -> void:
		var base := city_color(&"felt", Feel.COL_FELT)
		m.albedo_texture = noise_texture("felt_tex", 256, base.darkened(0.12), 0.07, 2.5, 0.06)
		m.roughness = 0.96
		m.metallic = 0.0
		m.uv1_scale = Vector3(2.0, 2.0, 2.0))


func wood() -> StandardMaterial3D:
	if has_set("dark_wood"):
		return pbr("wood", "dark_wood", city_color(&"wood_edge", Color("6D3F23")).lightened(0.45), 1.0)
	return _std("wood", func(m: StandardMaterial3D) -> void:
		var base := city_color(&"wood", Color("21150F"))
		var edge := city_color(&"wood_edge", Color("6D3F23"))
		m.albedo_texture = wood_texture("wood_tex", base.lightened(0.10), edge.darkened(0.15))
		m.roughness = 0.55
		m.metallic = 0.0
		m.uv1_scale = Vector3(1.0, 1.0, 1.0))


func wood_dark() -> StandardMaterial3D:
	if has_set("dark_wood"):
		return pbr("wood_dark", "dark_wood", Color("7A6658"), 0.5)
	return _std("wood_dark", func(m: StandardMaterial3D) -> void:
		var base := city_color(&"wood_dark", Color("0B0908"))
		m.albedo_texture = wood_texture("wood_dark_tex", base.lightened(0.06), base.lightened(0.16))
		m.roughness = 0.6)


## Deck planks for a floor whose UVs span 0..1 over `size` units (a PlaneMesh).
func lane_wood(size: Vector2) -> StandardMaterial3D:
	if not has_set("wood_floor_deck"):
		return wood()
	var m := pbr("lane_wood:%.2fx%.2f" % [size.x, size.y], "wood_floor_deck", Color("9C8672"), 1.0)
	m.uv1_scale = Vector3(size.x * 0.9, size.y * 0.9, 1.0)
	return m


## Room carpet (the Club, the Penthouse) tinted per room; felt-like when the set is missing.
func carpet(tint: Color) -> StandardMaterial3D:
	if has_set("dirty_carpet"):
		return pbr("carpet:%s" % tint.to_html(false), "dirty_carpet", tint.lightened(0.25), 1.6)
	var m := felt().duplicate() as StandardMaterial3D
	m.albedo_color = tint
	return m


func brass() -> StandardMaterial3D:
	return _std("brass", func(m: StandardMaterial3D) -> void:
		m.albedo_color = city_color(&"brass", Feel.COL_BRASS)
		m.metallic = 0.92
		m.metallic_specular = 0.7
		m.roughness = 0.34)


func brass_dark() -> StandardMaterial3D:
	return _std("brass_dark", func(m: StandardMaterial3D) -> void:
		m.albedo_color = city_color(&"brass", Feel.COL_BRASS).darkened(0.45)
		m.metallic = 0.88
		m.roughness = 0.42)


func steel() -> StandardMaterial3D:
	return _std("steel", func(m: StandardMaterial3D) -> void:
		m.albedo_color = Color("B9BEC4")
		m.metallic = 1.0
		m.metallic_specular = 0.9
		m.roughness = 0.12)


func chrome_dark() -> StandardMaterial3D:
	return _std("chrome_dark", func(m: StandardMaterial3D) -> void:
		m.albedo_color = Color("5A5E63")
		m.metallic = 0.95
		m.roughness = 0.22)


func rubber() -> StandardMaterial3D:
	return _std("rubber", func(m: StandardMaterial3D) -> void:
		m.albedo_color = Color("1A1A1C")
		m.roughness = 0.82)


func rubber_red() -> StandardMaterial3D:
	return _std("rubber_red", func(m: StandardMaterial3D) -> void:
		m.albedo_color = Color("7A2020")
		m.roughness = 0.78)


func ink() -> StandardMaterial3D:
	return _std("ink", func(m: StandardMaterial3D) -> void:
		m.albedo_color = city_color(&"ink_glass", Feel.COL_INK).lightened(0.05)
		m.roughness = 0.5
		m.metallic = 0.1)


func paper() -> StandardMaterial3D:
	return _std("paper", func(m: StandardMaterial3D) -> void:
		m.albedo_color = city_color(&"paper", Feel.COL_NEWSPRINT)
		m.roughness = 0.9)


func plastic(color: Color, rough: float = 0.45) -> StandardMaterial3D:
	return _std("plastic:%s:%.2f" % [color.to_html(false), rough], func(m: StandardMaterial3D) -> void:
		m.albedo_color = color
		m.roughness = rough
		m.metallic = 0.05)


## A lamp material owned by one proxy: it animates `emission_energy_multiplier` itself.
func lamp(color: Color, rough: float = 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.55)
	m.roughness = rough
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.0
	return m


## Neon: unlit signage that glows on its own and blooms.
func neon(color: Color, energy: float = 2.6) -> StandardMaterial3D:
	return _std("neon:%s:%.1f" % [color.to_html(false), energy], func(m: StandardMaterial3D) -> void:
		m.albedo_color = color
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy)


## Authored art printed onto a piece's own surface (a cap, a blade): opaque, lit, mipmapped
## by the importer so it stays calm at table scale.
func decal(texture: Texture2D, two_sided: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture
	m.roughness = 0.6
	m.metallic = 0.1
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Authored art on a standing quad. Alpha-scissored so the cut-out edge stays crisp.
func art(texture: Texture2D, emissive: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.roughness = 0.75
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission_texture = texture
		m.emission = Color.WHITE
		m.emission_energy_multiplier = emissive
	return m


func ball(design: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = ball_texture(design)
	m.metallic = 1.0
	m.metallic_specular = 1.0
	m.roughness = 0.08
	return m


func water() -> StandardMaterial3D:
	return _std("water", func(m: StandardMaterial3D) -> void:
		m.albedo_color = Color("173A4A")
		m.metallic = 0.6
		m.roughness = 0.15)
