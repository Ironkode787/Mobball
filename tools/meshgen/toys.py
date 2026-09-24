"""The tier-1 toys (specs/meshes.md §2). Each builder returns the objects to export; the
object names are the node contract the game binds to."""
import math

from common import (BRICK, BURGUNDY, CHEESE, CREAM, CRUST, ENAMEL, NAVY, OLIVE, TEAL_DULL,
		WOOD_DARK, box, cyl, disc_uv, join, lathe, m_brass, m_brass_dark, m_chrome, m_glass,
		m_ink, m_lamp, m_rubber, m_rubber_red, m_rust, m_steel, m_zinc, mat, profile_extrude,
		set_origin, torus)


# ------------------------------------------------------------------ bumper_can -----------
def build_bumper_can():
	"""Galvanised trash can, r 0.29 at scale 1: ribbed body, rubber skirt, lid, lit band."""
	prof = [(0.0, 0.03), (0.165, 0.03), (0.17, 0.06)]
	z = 0.06
	for i in range(4):
		r = 0.172 + i * 0.005
		prof += [(r, z + 0.03), (r + 0.014, z + 0.045), (r + 0.014, z + 0.06), (r, z + 0.075)]
		z += 0.09
	prof += [(0.195, 0.41), (0.0, 0.41)]
	body = lathe("Body", prof, m_zinc(), segments=20)
	skirt = lathe("Skirt", [(0.19, 0.03), (0.30, 0.03), (0.30, 0.075), (0.27, 0.10), (0.19, 0.10),
			(0.19, 0.03)], m_rubber_red(), segments=20, closed_top=False, closed_bottom=False)
	band = lathe("LampBand", [(0.19, 0.41), (0.205, 0.415), (0.205, 0.475), (0.19, 0.48)],
			m_lamp(), segments=20, closed_top=False, closed_bottom=False)
	lid = lathe("Lid", [(0.0, 0.48), (0.26, 0.48), (0.315, 0.49), (0.32, 0.53), (0.30, 0.555),
			(0.0, 0.555)], m_zinc(), segments=24)
	art = disc_uv("ArtLid", 0.295, 0.557, m_ink(), segments=24)
	return [body, skirt, band, lid, art]


# ------------------------------------------------------------------- container -----------
def build_container():
	"""A stack of three corrugated shipping containers, 0.16 long x 0.10 deep x 0.40 tall."""
	colours = [mat("box_rust", (0.62, 0.30, 0.16), 0.1, 0.8), mat("box_teal", TEAL_DULL, 0.1, 0.8),
			mat("box_olive", OLIVE, 0.1, 0.8)]
	parts = []
	h = 0.40 / 3.0
	for i in range(3):
		z0 = i * h
		m = colours[i]
		parts.append(box("c%d" % i, (0.16, 0.10, h - 0.01), (0.0, 0.0, z0 + (h - 0.01) * 0.5), m))
		for k in range(5):
			x = -0.064 + k * 0.032
			parts.append(box("r%d%d" % (i, k), (0.012, 0.012, h - 0.03), (x, -0.052, z0 + (h - 0.01) * 0.5), m))
		parts.append(box("d%d" % i, (0.006, 0.006, h - 0.02), (0.012, -0.056, z0 + (h - 0.01) * 0.5), m_steel()))
		parts.append(box("e%d" % i, (0.006, 0.006, h - 0.02), (-0.012, -0.056, z0 + (h - 0.01) * 0.5), m_steel()))
		parts.append(box("f%d" % i, (0.17, 0.11, 0.006), (0.0, 0.0, z0 + 0.003), m_ink()))
	body = join("Body", parts)
	stripe = box("LampStripe", (0.13, 0.008, 0.02), (0.0, -0.055, 0.365), m_lamp())
	return [body, stripe]


# ---------------------------------------------------------------------- cars -------------
def _wheels(name, xs, ys, r, w, z=None):
	z = r if z is None else z
	parts = []
	for x in xs:
		for y in ys:
			parts.append(cyl("t", r, w, (x, y, z), m_rubber(), segments=16, axis="Y"))
			parts.append(cyl("h", r * 0.55, w + 0.006, (x, y, z), m_chrome(), segments=12, axis="Y"))
	return join(name, parts)


def build_sedan():
	"""70s two-door, 0.72 long (front +X) x 0.24 wide, roof 0.30."""
	paint = mat("paint_burgundy", BURGUNDY, 0.4, 0.35)
	lower = [(-0.36, 0.06), (-0.36, 0.13), (-0.34, 0.16), (-0.14, 0.17), (0.12, 0.17), (0.34, 0.155),
			(0.36, 0.13), (0.36, 0.06)]
	body = profile_extrude("b", lower, 0.22, paint, bevel=0.008)
	cabin = profile_extrude("g", [(-0.22, 0.165), (-0.16, 0.29), (0.05, 0.29), (0.13, 0.165)], 0.19, m_glass())
	roof = profile_extrude("roof", [(-0.165, 0.285), (-0.155, 0.305), (0.045, 0.305), (0.055, 0.285)], 0.20, paint)
	pillars = [box("p%d" % i, (0.012, 0.194, 0.12), (x, 0.0, 0.225), paint) for i, x in enumerate([-0.19, 0.09])]
	body = join("Body", [body, cabin, roof] + pillars)
	chrome = [box("bf", (0.03, 0.235, 0.035), (0.365, 0.0, 0.095), m_chrome()),
			box("bb", (0.03, 0.235, 0.035), (-0.365, 0.0, 0.095), m_chrome()),
			box("grille", (0.01, 0.16, 0.05), (0.362, 0.0, 0.135), m_ink()),
			cyl("hl", 0.022, 0.012, (0.362, 0.085, 0.14), m_lamp(), segments=12, axis="X"),
			cyl("hr", 0.022, 0.012, (0.362, -0.085, 0.14), m_lamp(), segments=12, axis="X"),
			box("tl", (0.01, 0.05, 0.02), (-0.362, 0.08, 0.14), m_rubber_red()),
			box("tr", (0.01, 0.05, 0.02), (-0.362, -0.08, 0.14), m_rubber_red()),
			box("trim", (0.66, 0.226, 0.006), (0.0, 0.0, 0.14), m_chrome())]
	chrome = join("Chrome", chrome)
	wheels = _wheels("Wheels", [-0.23, 0.24], [-0.105, 0.105], 0.055, 0.045)
	lamp = box("LampRoof", (0.08, 0.08, 0.05), (-0.055, 0.0, 0.33), m_lamp(), bevel=0.01)
	return [body, chrome, wheels, lamp]


def build_truck():
	"""Box truck, 0.64 long (front +X) x 0.28 wide, roof 0.36."""
	paint = mat("paint_truck", (0.20, 0.22, 0.20), 0.3, 0.45)
	cab = profile_extrude("cab", [(0.10, 0.07), (0.10, 0.30), (0.20, 0.30), (0.27, 0.20), (0.32, 0.16),
			(0.32, 0.07)], 0.26, paint, bevel=0.006)
	glass = profile_extrude("glass", [(0.205, 0.175), (0.205, 0.285), (0.215, 0.285), (0.265, 0.19)], 0.22, m_glass())
	cargo = box("cargo", (0.42, 0.28, 0.30), (-0.11, 0.0, 0.21), mat("reefer", ENAMEL, 0.2, 0.6), bevel=0.006)
	ribs = [box("rib%d" % i, (0.006, 0.284, 0.26), (-0.30 + i * 0.065, 0.0, 0.21), m_zinc()) for i in range(7)]
	doors = box("doors", (0.006, 0.26, 0.26), (-0.323, 0.0, 0.21), m_zinc())
	body = join("Body", [cab, glass, cargo, doors] + ribs)
	chrome = join("Chrome", [box("bf", (0.03, 0.27, 0.04), (0.325, 0.0, 0.085), m_chrome()),
			box("grille", (0.01, 0.18, 0.07), (0.322, 0.0, 0.13), m_ink()),
			cyl("hl", 0.02, 0.012, (0.322, 0.10, 0.13), m_lamp(), segments=12, axis="X"),
			cyl("hr", 0.02, 0.012, (0.322, -0.10, 0.13), m_lamp(), segments=12, axis="X")])
	wheels = _wheels("Wheels", [-0.19, 0.22], [-0.115, 0.115], 0.06, 0.05)
	lamp = box("LampRoof", (0.07, 0.07, 0.045), (0.16, 0.0, 0.32), m_lamp(), bevel=0.01)
	return [body, chrome, wheels, lamp]


def build_van():
	"""Panel van, 0.50 long (front +X) x 0.26 wide x 0.28 tall, a light bar on the roof."""
	paint = mat("paint_van", NAVY, 0.3, 0.45)
	shell = profile_extrude("shell", [(-0.25, 0.07), (-0.25, 0.24), (-0.23, 0.265), (0.10, 0.27),
			(0.18, 0.22), (0.24, 0.15), (0.25, 0.07)], 0.25, paint, bevel=0.008)
	glass = profile_extrude("glass", [(0.11, 0.17), (0.105, 0.255), (0.125, 0.255), (0.19, 0.19)], 0.22, m_glass())
	side_glass = [box("sg%d" % i, (0.09, 0.256, 0.06), (0.03, 0.0, 0.215), m_glass()) for i in range(1)]
	body = join("Body", [shell, glass] + side_glass +
			[box("bf", (0.03, 0.25, 0.035), (0.25, 0.0, 0.09), m_chrome()),
			box("bb", (0.03, 0.25, 0.035), (-0.25, 0.0, 0.09), m_chrome())])
	wheels = _wheels("Wheels", [-0.16, 0.16], [-0.115, 0.115], 0.055, 0.045)
	bar = box("LampBar", (0.14, 0.06, 0.035), (0.0, 0.0, 0.29), m_lamp(), bevel=0.008)
	return [body, wheels, bar]


# --------------------------------------------------------------- slot_machine ------------
def build_slot_machine():
	"""One-armed bandit standing behind the reels: 0.76 wide x 0.12 deep x 0.55 tall."""
	wood = mat("wood", WOOD_DARK, 0.0, 0.6)
	cab = box("cab", (0.76, 0.12, 0.46), (0.0, 0.0, 0.23), wood, bevel=0.01)
	panel = box("panel", (0.70, 0.02, 0.36), (0.0, -0.06, 0.24), mat("panel", (0.10, 0.10, 0.11), 0.2, 0.5))
	tray = box("tray", (0.30, 0.10, 0.04), (0.0, -0.09, 0.05), m_brass_dark(), bevel=0.006)
	trims = [box("tr%d" % i, (0.78, 0.13, 0.015), (0.0, 0.0, z), m_brass()) for i, z in enumerate([0.008, 0.455])]
	edges = [box("te%d" % i, (0.015, 0.13, 0.46), (x, 0.0, 0.23), m_brass()) for i, x in enumerate([-0.385, 0.385])]
	cabinet = join("Cabinet", [cab, panel, tray] + trims + edges)
	top = profile_extrude("marq", [(-0.40, 0.46), (-0.40, 0.58), (-0.30, 0.66), (0.30, 0.66), (0.40, 0.58),
			(0.40, 0.46)], 0.12, wood, bevel=0.006)
	marquee = join("Marquee", [top, box("mt", (0.81, 0.13, 0.012), (0.0, 0.0, 0.465), m_brass())])
	lamp = box("LampMarquee", (0.64, 0.02, 0.12), (0.0, -0.062, 0.575), m_lamp(), bevel=0.006)
	arm = cyl("arm", 0.016, 0.30, (0.42, -0.02, 0.44), m_chrome(), segments=12)
	knob = cyl("knob", 0.035, 0.035, (0.42, -0.02, 0.60), m_rubber_red(), segments=16)
	pivot = cyl("pivot", 0.03, 0.05, (0.40, 0.0, 0.30), m_brass_dark(), segments=12, axis="X")
	lever = join("Lever", [arm, knob, pivot])
	return [cabinet, marquee, lamp, lever]


# ------------------------------------------------------------------- payphone ------------
def build_payphone():
	"""Pedestal payphone: post, coin box, hood wings, receiver. 0.30 x 0.22 x 0.52 tall."""
	steel_blue = mat("phone_steel", (0.20, 0.22, 0.24), 0.6, 0.45)
	post = cyl("post", 0.028, 0.24, (0.0, 0.02, 0.12), m_ink(), segments=12)
	foot = cyl("foot", 0.07, 0.02, (0.0, 0.02, 0.01), m_ink(), segments=16)
	phone = box("phone", (0.18, 0.10, 0.28), (0.0, 0.02, 0.38), steel_blue, bevel=0.008)
	hood_back = box("hb", (0.30, 0.02, 0.26), (0.0, 0.085, 0.42), steel_blue)
	hood_l = box("hl", (0.02, 0.18, 0.26), (-0.15, -0.005, 0.42), steel_blue)
	hood_r = box("hr", (0.02, 0.18, 0.26), (0.15, -0.005, 0.42), steel_blue)
	hood_top = box("ht", (0.30, 0.18, 0.02), (0.0, -0.005, 0.56), steel_blue)
	body = join("Body", [post, foot, phone, hood_back, hood_l, hood_r, hood_top])
	slot = box("slot", (0.05, 0.012, 0.012), (0.03, -0.035, 0.49), m_chrome())
	cradle = box("cradle", (0.04, 0.03, 0.10), (-0.06, -0.04, 0.42), m_chrome())
	ear = cyl("ear", 0.022, 0.03, (-0.06, -0.075, 0.48), m_ink(), segments=12, axis="Y")
	mouth = cyl("mouth", 0.022, 0.03, (-0.06, -0.075, 0.36), m_ink(), segments=12, axis="Y")
	handle = cyl("handle", 0.012, 0.12, (-0.06, -0.085, 0.42), m_ink(), segments=8)
	cord = cyl("cord", 0.004, 0.10, (-0.03, -0.06, 0.32), m_chrome(), segments=6, axis="X")
	chrome = join("Chrome", [slot, cradle, ear, mouth, handle, cord])
	face = box("LampFace", (0.07, 0.01, 0.07), (0.03, -0.075, 0.41), m_lamp(), bevel=0.004)
	return [body, chrome, face]


# ------------------------------------------------------------------ pizza_sign -----------
def build_pizza_sign():
	"""Pole with a pie on top; `Spin` turns about the pole."""
	pole = join("Pole", [cyl("pole", 0.02, 0.55, (0.0, 0.0, 0.275), m_brass_dark(), segments=12),
			cyl("base", 0.06, 0.03, (0.0, 0.0, 0.015), m_brass_dark(), segments=16)])
	crust = lathe("crust", [(0.0, 0.55), (0.23, 0.55), (0.26, 0.565), (0.26, 0.60), (0.24, 0.61), (0.0, 0.60)],
			mat("crust", CRUST, 0.0, 0.8), segments=28)
	cheese = cyl("cheese", 0.235, 0.012, (0.0, 0.0, 0.605), mat("cheese", CHEESE, 0.0, 0.7), segments=28)
	parts = [crust, cheese]
	for i in range(8):
		a = i * math.tau / 8.0 + 0.3
		r = 0.15 if i % 2 == 0 else 0.09
		parts.append(cyl("pep%d" % i, 0.035, 0.012, (math.cos(a) * r, math.sin(a) * r, 0.615), mat("pepperoni", BRICK, 0.0, 0.7), segments=12))
	for i in range(4):
		a = i * math.pi / 4.0
		parts.append(box("cut%d" % i, (0.47, 0.006, 0.004), (0.0, 0.0, 0.612), mat("crust_dark", (0.45, 0.30, 0.15), 0.0, 0.8)))
		parts[-1].rotation_euler = (0.0, 0.0, a)
	spin = join("Spin", parts)
	return [pole, spin]


# ------------------------------------------------------------- washing_machine -----------
def build_washing_machine():
	"""Front loader, 0.40 wide x 0.34 deep x 0.40 tall; `Door` is the porthole and spins."""
	enamel = mat("enamel", ENAMEL, 0.1, 0.4)
	body = box("body", (0.40, 0.34, 0.38), (0.0, 0.0, 0.19), enamel, bevel=0.012)
	top = box("top", (0.40, 0.34, 0.02), (0.0, 0.0, 0.39), mat("panel_ink", (0.10, 0.10, 0.11), 0.2, 0.5))
	console = box("console", (0.40, 0.06, 0.06), (0.0, 0.14, 0.43), enamel, bevel=0.008)
	knobs = [cyl("k%d" % i, 0.014, 0.02, (x, 0.10, 0.43), m_brass(), segments=12, axis="Y") for i, x in enumerate([-0.12, -0.04, 0.10])]
	feet = [cyl("ft%d" % i, 0.02, 0.02, (x, y, -0.005), m_rubber(), segments=8) for i, (x, y) in enumerate([(-0.16, -0.13), (0.16, -0.13), (-0.16, 0.13), (0.16, 0.13)])]
	ring = lathe("ring", [(0.10, 0.0), (0.155, 0.0), (0.155, 0.02), (0.14, 0.03), (0.10, 0.03), (0.10, 0.0)],
			m_chrome(), segments=28, closed_top=False, closed_bottom=False)
	ring.rotation_euler = (math.pi / 2, 0.0, 0.0)
	body = join("Body", [body, top, console] + knobs + feet)
	glass = cyl("glass", 0.105, 0.016, (0.0, -0.005, 0.0), m_glass(), segments=28, axis="Y")
	paddles = [box("pd%d" % i, (0.02, 0.01, 0.16), (0.0, 0.0, 0.0), mat("paddle", TEAL_DULL, 0.1, 0.6)) for i in range(3)]
	for i, p in enumerate(paddles):
		p.rotation_euler = (0.0, i * math.pi / 3.0, 0.0)
	door = join("Door", [ring, glass] + paddles)
	door.location = (0.0, -0.18, 0.20)
	return [body, door]


# ---------------------------------------------------------------------- safe -------------
def build_safe():
	"""Strongbox 0.36 wide x 0.30 deep x 0.40 tall with a brass dial and handle."""
	paint = mat("safe_paint", (0.16, 0.19, 0.17), 0.3, 0.45)
	body = box("body", (0.36, 0.30, 0.38), (0.0, 0.0, 0.21), paint, bevel=0.014)
	door = box("door", (0.30, 0.02, 0.32), (0.0, -0.155, 0.22), paint, bevel=0.008)
	hinges = [box("hg%d" % i, (0.02, 0.03, 0.06), (-0.165, -0.155, z), m_brass_dark()) for i, z in enumerate([0.12, 0.32])]
	feet = [cyl("f%d" % i, 0.025, 0.02, (x, y, 0.01), m_ink(), segments=8) for i, (x, y) in enumerate([(-0.14, -0.11), (0.14, -0.11), (-0.14, 0.11), (0.14, 0.11)])]
	plate = box("plate", (0.14, 0.006, 0.05), (0.0, -0.168, 0.36), m_brass())
	body = join("Body", [body, door, plate] + hinges + feet)
	dial = lathe("Dial", [(0.0, 0.0), (0.07, 0.0), (0.07, 0.02), (0.05, 0.03), (0.02, 0.03), (0.02, 0.05), (0.0, 0.05)],
			m_brass(), segments=24)
	dial.rotation_euler = (math.pi / 2, 0.0, 0.0)
	dial.location = (0.04, -0.165, 0.22)
	handle = join("Handle", [cyl("hs", 0.012, 0.05, (-0.08, -0.19, 0.22), m_brass(), segments=10, axis="Y"),
			cyl("hb", 0.012, 0.12, (-0.08, -0.21, 0.22), m_brass(), segments=10)])
	return [body, dial, handle]


# ---------------------------------------------------------------- city_hall_dome ---------
def build_city_hall_dome():
	"""CityHall's corner rotunda (v4): stepped podium, a colonnade of twelve, the drum and a
	gilt dome under the Getaway's dome loop. The loop's wireform runs at r 0.40 from z 0.78,
	so the building stays inside r 0.26 above z 0.64; only the lantern and the flag rise
	through the middle, where the ball never goes."""
	stone = mat("hall_stone", ENAMEL, 0.0, 0.7)
	shade = mat("hall_shade", (0.62, 0.60, 0.55), 0.0, 0.8)
	parts = [
		lathe("podium", [(0.0, 0.0), (0.30, 0.0), (0.30, 0.025), (0.285, 0.025), (0.285, 0.05),
				(0.27, 0.05), (0.27, 0.075), (0.0, 0.075)], stone, segments=24),
		cyl("core", 0.19, 0.225, (0.0, 0.0, 0.1875), shade, segments=16),
	]
	for k in range(12):
		a = k * math.tau / 12.0
		x, y = math.cos(a) * 0.235, math.sin(a) * 0.235
		parts.append(cyl("col%d" % k, 0.017, 0.215, (x, y, 0.1825), stone, segments=8))
		parts.append(box("cap%d" % k, (0.042, 0.042, 0.012), (x, y, 0.294), stone))
	parts.append(lathe("entablature", [(0.0, 0.30), (0.262, 0.30), (0.262, 0.335), (0.272, 0.345),
			(0.272, 0.355), (0.0, 0.355)], stone, segments=24))
	parts.append(lathe("drum", [(0.0, 0.355), (0.225, 0.355), (0.225, 0.425), (0.238, 0.432),
			(0.238, 0.44), (0.0, 0.44)], stone, segments=24))
	body = join("Body", parts)
	dome = lathe("LampDome", [(0.222, 0.44)] + [
			(0.222 * math.cos(t), 0.44 + 0.195 * math.sin(t))
			for t in [math.radians(a) for a in (12, 24, 36, 48, 60, 72, 84)]] + [(0.0, 0.635)],
			m_lamp(), segments=24)
	ribs = []
	for k in range(8):
		a = k * math.tau / 8.0
		pts = []
		for t in (4, 26, 48, 70, 86):
			tr = math.radians(t)
			r = 0.227 * math.cos(tr)
			pts.append((math.cos(a) * r, math.sin(a) * r, 0.44 + 0.2 * math.sin(tr)))
		for j in range(len(pts) - 1):
			ribs.append(_strut("rib%d_%d" % (k, j), pts[j], pts[j + 1], 0.011, m_brass()))
	lantern = [
		cyl("lantern", 0.04, 0.07, (0.0, 0.0, 0.665), stone, segments=10),
		cyl("lantern_cap", 0.05, 0.02, (0.0, 0.0, 0.71), m_brass(), segments=10, radius_top=0.018),
		cyl("pole", 0.005, 0.22, (0.0, 0.0, 0.83), m_steel(), segments=6),
		box("flag", (0.001, 0.09, 0.05), (0.0, -0.047, 0.91), mat("hall_flag", CREAM, 0.0, 0.9)),
	]
	trim = join("Trim", lantern + ribs)
	return [body, dome, trim]


# ------------------------------------------------------------------ pier_crane -----------
def _strut(name, a, b, t, material):
	"""A square strut from `a` to `b` (Blender space): built on the origin, turned, then
	moved, so `join` bakes it where it belongs."""
	from mathutils import Vector
	va, vb = Vector(a), Vector(b)
	d = vb - va
	ob = box(name, (t, t, d.length), (0.0, 0.0, 0.0), material)
	ob.rotation_mode = "QUATERNION"
	ob.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized())
	ob.location = (va + vb) * 0.5
	return ob


def build_pier_crane():
	"""Pier 9's tower (v4): a lattice mast 1.05 tall on a concrete foot, the slewing ring on
	top. The boom is its own mesh (`pier_boom`) so the code can swing it."""
	paint = mat("crane_paint", (0.74, 0.58, 0.16), 0.2, 0.55)
	h = 1.05
	w = 0.05
	parts = [box("foot", (0.15, 0.15, 0.04), (0.0, 0.0, 0.02), mat("crane_foot", (0.42, 0.41, 0.38), 0.0, 0.9))]
	corners = [(-w, -w), (w, -w), (w, w), (-w, w)]
	for i, (x, y) in enumerate(corners):
		parts.append(_strut("leg%d" % i, (x, y, 0.04), (x, y, h - 0.04), 0.014, paint))
	levels = 8
	for k in range(levels):
		z0 = 0.04 + (h - 0.08) * k / levels
		z1 = 0.04 + (h - 0.08) * (k + 1) / levels
		for i in range(4):
			a = corners[i]
			b = corners[(i + 1) % 4]
			parts.append(_strut("h%d_%d" % (k, i), (a[0], a[1], z1), (b[0], b[1], z1), 0.008, paint))
			if k % 2 == 0:
				parts.append(_strut("d%d_%d" % (k, i), (a[0], a[1], z0), (b[0], b[1], z1), 0.007, paint))
			else:
				parts.append(_strut("d%d_%d" % (k, i), (b[0], b[1], z0), (a[0], a[1], z1), 0.007, paint))
	parts.append(cyl("ring", 0.075, 0.03, (0.0, 0.0, h - 0.015), m_steel(), segments=16))
	return [join("Body", parts)]


def build_pier_boom():
	"""Pier 9's boom: a triangular lattice jib reaching 1.40 out over the ring road (Blender -Y,
	the table's +Z), the operator's cab under the pivot, the counter-jib and its weight behind.
	The origin is the slewing pivot; the trolley and its cable stay code-built."""
	paint = mat("crane_paint", (0.74, 0.58, 0.16), 0.2, 0.55)
	length = 1.40
	hw = 0.03
	lo = -0.025
	hi = 0.03
	parts = []
	chords = [(-hw, lo), (hw, lo), (0.0, hi)]
	for i, (x, z) in enumerate(chords):
		parts.append(_strut("chord%d" % i, (x, 0.02, z), (x, -length, z), 0.010, paint))
	bays = 14
	for k in range(bays):
		y0 = -length * k / bays
		y1 = -length * (k + 1) / bays
		ya, yb = (y0, y1) if k % 2 == 0 else (y1, y0)
		parts.append(_strut("s%da" % k, (-hw, ya, lo), (0.0, yb, hi), 0.006, paint))
		parts.append(_strut("s%db" % k, (hw, ya, lo), (0.0, yb, hi), 0.006, paint))
		parts.append(_strut("s%dc" % k, (-hw, y1, lo), (hw, y1, lo), 0.006, paint))
	# the counter-jib, its weight, and the cab
	parts.append(_strut("cj0", (-hw, 0.0, lo), (-hw, 0.34, lo), 0.012, paint))
	parts.append(_strut("cj1", (hw, 0.0, lo), (hw, 0.34, lo), 0.012, paint))
	parts.append(box("weight", (0.11, 0.08, 0.07), (0.0, 0.30, lo - 0.02), mat("crane_weight", (0.36, 0.35, 0.33), 0.1, 0.9)))
	parts.append(_strut("tie0", (0.0, -0.60, hi), (0.0, 0.0, 0.16), 0.005, m_steel()))
	parts.append(_strut("tie1", (0.0, 0.30, hi), (0.0, 0.0, 0.16), 0.005, m_steel()))
	parts.append(_strut("apex", (0.0, 0.0, lo), (0.0, 0.0, 0.16), 0.014, paint))
	cab = box("cab", (0.075, 0.07, 0.06), (0.0, -0.05, lo - 0.045), paint)
	glass = box("cab_glass", (0.07, 0.004, 0.035), (0.0, -0.086, lo - 0.04), m_glass())
	return [join("Body", [cab, glass] + parts)]


BUILDERS = {
	"bumper_can": build_bumper_can,
	"container": build_container,
	"sedan": build_sedan,
	"truck": build_truck,
	"van": build_van,
	"slot_machine": build_slot_machine,
	"payphone": build_payphone,
	"pizza_sign": build_pizza_sign,
	"washing_machine": build_washing_machine,
	"safe": build_safe,
	"city_hall_dome": build_city_hall_dome,
	"pier_crane": build_pier_crane,
	"pier_boom": build_pier_boom,
}
