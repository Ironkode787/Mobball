#!/usr/bin/env python3
"""The printed playfield: shot names, lane paint, the Empire dial, the wordmark.

Reads tools/texgen/playfield_layout.json (the table's geometry as the game evaluates it,
written by playfield_layout.tscn) and paints assets/textures/playfield/playfield.png over the
street mesh's UV rectangle. Everything is printed matter in the house register (docs/07):
newsprint and brass ink on the street, black keylines round the inserts; the only colour on
the table stays in the lamps. Run through tools/texgen/playfield.sh; never hand-edit the PNG.
"""

import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
LAYOUT = os.path.join(ROOT, "tools", "texgen", "playfield_layout.json")
OUT = os.path.join(ROOT, "assets", "textures", "playfield", "playfield.png")
FONTS = os.path.join(ROOT, "assets", "fonts")

W, H = 1024, 2048
SS = 2                                   # supersampling, for clean edges after the resize

INK = (18, 16, 14)
NEWSPRINT = (242, 232, 213)
BRASS = (201, 162, 39)

IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://c7kpfart0v4pf"
path.s3tc="res://.godot/imported/playfield.png-{h}.s3tc.ctex"
path.etc2="res://.godot/imported/playfield.png-{h}.etc2.ctex"
metadata={{
"imported_formats": ["s3tc_bptc", "etc2_astc"],
"vram_texture": true
}}

[deps]

source_file="res://assets/textures/playfield/playfield.png"
dest_files=["res://.godot/imported/playfield.png-{h}.s3tc.ctex", "res://.godot/imported/playfield.png-{h}.etc2.ctex"]

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


class Paper:
    """A canvas in table plan units (x across, z down the table toward the player)."""

    def __init__(self, field):
        self.x0, self.z0 = field["x0"], field["z0"]
        self.sx = W * SS / field["w"]
        self.sz = H * SS / field["d"]
        self.img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
        self.draw = ImageDraw.Draw(self.img)
        self._fonts = {}

    def px(self, p):
        return ((p[0] - self.x0) * self.sx, (p[1] - self.z0) * self.sz)

    def u(self, units):
        return units * (self.sx + self.sz) * 0.5

    def font(self, name, size_px):
        key = (name, int(size_px))
        if key not in self._fonts:
            self._fonts[key] = ImageFont.truetype(os.path.join(FONTS, name), int(size_px))
        return self._fonts[key]

    def poly(self, pts, fill):
        self.draw.polygon([self.px(p) for p in pts], fill=fill)

    def line(self, pts, width, fill):
        self.draw.line([self.px(p) for p in pts], fill=fill, width=max(1, int(self.u(width))), joint="curve")

    def circle(self, c, r, fill=None, outline=None, width=0.0):
        x, y = self.px(c)
        rx, ry = r * self.sx, r * self.sz
        self.draw.ellipse([x - rx, y - ry, x + rx, y + ry], fill=fill, outline=outline,
                          width=max(1, int(self.u(width))) if outline else 0)

    def arc(self, c, r, a0, a1, width, fill):
        x, y = self.px(c)
        rx, ry = r * self.sx, r * self.sz
        self.draw.arc([x - rx, y - ry, x + rx, y + ry], a0, a1, fill=fill, width=max(1, int(self.u(width))))

    def spaced(self, s, at, height, angle=0.0, fill=NEWSPRINT + (200,), font="Oswald-SemiBold.ttf",
               tracking=0.02):
        """Tracked caps; `height` is the cap height in plan units, `angle` turns them
        counter-clockwise about their centre at `at`."""
        f = self.font(font, self.u(height) * 1.38)
        widths = [f.getlength(ch) for ch in s]
        total = sum(widths) + self.u(tracking) * (len(s) - 1)
        asc, desc = f.getmetrics()
        pad = int(self.u(0.05))
        tile = Image.new("RGBA", (int(total) + pad * 2, asc + desc + pad * 2), (0, 0, 0, 0))
        d = ImageDraw.Draw(tile)
        x = pad
        for ch, w in zip(s, widths):
            d.text((x, pad), ch, font=f, fill=fill)
            x += w + self.u(tracking)
        if angle:
            tile = tile.rotate(angle, resample=Image.BICUBIC, expand=True)
        cx, cy = self.px(at)
        self.img.alpha_composite(tile, (int(cx - tile.width / 2), int(cy - tile.height / 2)))

    def save(self, path):
        out = self.img.resize((W, H), Image.LANCZOS)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        out.save(path, optimize=True)


def add(a, b, k=1.0):
    return (a[0] + b[0] * k, a[1] + b[1] * k)


def norm(v):
    l = math.hypot(v[0], v[1]) or 1.0
    return (v[0] / l, v[1] / l)


def heading_deg(d):
    """The counter-clockwise turn that stands text upright along an arrow pointing `d`."""
    return math.degrees(math.atan2(-d[0], -d[1]))


def arrow_outline(at, d, k):
    d = norm(d)
    side = (-d[1], d[0])
    tip = add(at, d, 0.13 * k)
    wing_l = add(at, side, 0.085 * k)
    wing_r = add(at, side, -0.085 * k)
    tail_l = add(add(at, d, -0.09 * k), side, 0.035 * k)
    tail_r = add(add(at, d, -0.09 * k), side, -0.035 * k)
    head_l = add(at, side, 0.035 * k)
    head_r = add(at, side, -0.035 * k)
    return [tip, wing_l, head_l, tail_l, tail_r, head_r, wing_r]


SHOT_NAMES = {
    "getaway": "GETAWAY",
    "wire": "THE WIRE",
    "staircase": "STAIRCASE",
    "nonnas": "NONNA'S",
    "fat_tonys": "FAT TONY'S",
    "luckys": "LUCKY'S",
    "beat_cop": "BEAT COP",
    "truck_route": "TRUCK ROUTE",
}
# Where a name sits relative to the default spot behind its arrow, where two would collide or a
# name would touch its neighbour's hardware.
NAME_NUDGE = {"beat_cop": (-0.06, 0.16), "nonnas": (-0.12, 0.03), "fat_tonys": (0.16, 0.03)}
# Cap heights, plan units (docs/20 §6): nothing printed on the street smaller than a phone reads.
NAME_H = 0.10
LANE_H = 0.13
LABEL_H = 0.085


def paint(L):
    pf = Paper(L["field"])
    mirror = L["MIRROR_X"]

    # the ring road: a street's broken centre line round the top of the city
    mids = [(a, tuple(p)) for a, p in L["channel_mid"] if 182.0 <= a <= 358.0]
    dash = 0.11
    gap = 0.09
    run = 0.0
    on = True
    seg = [mids[0][1]]
    for (a0, p0), (a1, p1) in zip(mids, mids[1:]):
        run += math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        if on:
            seg.append(p1)
        if run >= (dash if on else gap):
            if on and len(seg) >= 2:
                pf.line(seg, 0.018, NEWSPRINT + (95,))
            on = not on
            run = 0.0
            seg = [p1]

    # the two orbit lanes, painted up the lane under their arrows
    for key, name, x in (("getaway", "GETAWAY", L["LANE_L_X"]), ("truck_route", "TRUCK ROUTE", L["LANE_R_X"])):
        pf.spaced(name, (x, -0.66 if key == "getaway" else -0.86), LANE_H, angle=90.0,
                  fill=NEWSPRINT + (160,), tracking=0.03)
        for k in range(3):
            z = 0.62 + k * 0.16
            c = (x, z)
            pf.poly([add(c, (0.0, -0.07)), add(c, (0.09, 0.02)), add(c, (0.05, 0.02)),
                     add(c, (0.0, -0.025)), add(c, (-0.05, 0.02)), add(c, (-0.09, 0.02))],
                    BRASS + (120 - k * 30,))

    # a black keyline round every insert, so the lamps read as set into the wood
    for shot, (at, d) in L["arrows"].items():
        pf.poly(arrow_outline(tuple(at), tuple(d), L["arrow_scale"][shot] * 1.1), INK + (215,))
    for p in L["TAKE_AT"]:
        pf.circle(tuple(p), L["take_radius"] + 0.025, fill=INK + (215,))
    for p in L["FUSE_AT"]:
        x, z = p
        pf.poly([(x - 0.10, z - 0.065), (x + 0.10, z - 0.065), (x + 0.10, z + 0.065), (x - 0.10, z + 0.065)],
                INK + (215,))
    for p in L["CAN_LEVEL_AT"]:
        x, z = p
        pf.poly([(x - 0.12, z - 0.09), (x + 0.12, z - 0.09), (x + 0.12, z + 0.09), (x - 0.12, z + 0.09)],
                INK + (215,))

    # the shot names, printed level behind each arrow: turned text is the first thing a phone
    # screen loses
    for shot, (at, d) in L["arrows"].items():
        if shot not in SHOT_NAMES or shot in ("getaway", "truck_route"):
            continue
        d = norm(d)
        pos = add(add(tuple(at), d, -(0.09 * L["arrow_scale"][shot] + 0.11)), NAME_NUDGE.get(shot, (0.0, 0.0)))
        pf.spaced(SHOT_NAMES[shot], pos, NAME_H, fill=NEWSPRINT + (215,), tracking=0.012)

    # the Empire dial: a brass bezel with the hour ticks of a clock
    c = tuple(L["WHEEL_CENTER"])
    r = L["WHEEL_RADIUS"]
    pf.circle(c, r + 0.05, fill=INK + (225,))
    pf.circle(c, r + 0.085, outline=BRASS + (200,), width=0.018)
    for k in range(48):
        a = math.radians(k * 7.5)
        long = k % 6 == 0
        p0 = add(c, (math.cos(a), math.sin(a)), r + 0.10)
        p1 = add(c, (math.cos(a), math.sin(a)), r + (0.16 if long else 0.125))
        pf.line([p0, p1], 0.012 if long else 0.007, BRASS + (190 if long else 120,))

    # the fuse: a brass channel either side of the lamps it burns down, toward Lucky's door
    fuse = [tuple(p) for p in L["FUSE_AT"]]
    for sx in (-0.125, 0.125):
        pf.line([add(fuse[0], (sx, 0.07)), add(fuse[-1], (sx, -0.07))], 0.010, BRASS + (140,))
    mid_z = (fuse[0][1] + fuse[-1][1]) * 0.5
    pf.spaced("FUSE", (fuse[0][0] - 0.23, mid_z), LABEL_H, angle=90.0, fill=NEWSPRINT + (175,), tracking=0.02)

    # the Take: a brass rail under the row
    take = [tuple(p) for p in L["TAKE_AT"]]
    pf.line([add(take[0], (-0.15, 0.22)), add(take[-1], (0.15, 0.22))], 0.012, BRASS + (170,))
    pf.spaced("THE TAKE", add(((take[0][0] + take[-1][0]) * 0.5, take[0][1]), (0.0, 0.33)), LABEL_H + 0.015,
              fill=NEWSPRINT + (195,), tracking=0.03)

    # the can ladder behind Lucky's: what a can pays
    lv = [tuple(p) for p in L["CAN_LEVEL_AT"]]
    pf.spaced("CANS PAY", add(((lv[0][0] + lv[-1][0]) * 0.5, lv[0][1]), (0.0, 0.19)),
              LABEL_H * 0.8, fill=NEWSPRINT + (170,), tracking=0.02)

    # the outlanes: Big Sal's post on the left, the kickback on the right
    for key, label in (("KICKBACK_AT", "BIG SAL"), ("KICKBACK_R_AT", "KICKBACK")):
        p = tuple(L[key])
        pf.spaced(label, (p[0], p[1] - 0.66), LABEL_H, angle=90.0, fill=NEWSPRINT + (130,), tracking=0.02)

    # the sewer: a stencilled ring round each manhole
    for p in L["MANHOLE_AT"]:
        pf.circle(tuple(p), 0.215, outline=NEWSPRINT + (70,), width=0.012)
        if p[1] > -3.0:
            pf.spaced("SEWER", add(tuple(p), (0.0, 0.31)), LABEL_H * 0.8, fill=NEWSPRINT + (120,), tracking=0.015)

    # the wordmark between the slings, above the flippers
    wz = 3.55
    pf.spaced("KINGPIN", (mirror, wz), 0.20, fill=BRASS + (185,), tracking=0.04)
    pf.line([(mirror - 0.62, wz + 0.19), (mirror + 0.62, wz + 0.19)], 0.010, BRASS + (140,))
    pf.spaced("THE  CITY  PAYS  WHO  RUNS  IT", (mirror, wz + 0.31), 0.055, fill=NEWSPRINT + (140,),
              tracking=0.01)

    return pf


def main():
    if not os.path.exists(LAYOUT):
        sys.exit("no %s: run tools/texgen/playfield.sh" % LAYOUT)
    L = json.load(open(LAYOUT))
    pf = paint(L)
    pf.save(OUT)
    imp = OUT + ".import"
    if not os.path.exists(imp):
        import hashlib
        h = hashlib.md5(b"res://assets/textures/playfield/playfield.png").hexdigest()
        open(imp, "w").write(IMPORT.format(h=h))
    print("playfield art -> %s" % os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
