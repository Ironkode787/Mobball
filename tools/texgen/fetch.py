#!/usr/bin/env python3
"""Fetch the table's CC0 PBR textures from Poly Haven (https://polyhaven.com, CC0 1.0) into
assets/textures/<id>/ and write Godot .import files that give them mipmaps.

    python3 tools/texgen/fetch.py            # everything in SET
    python3 tools/texgen/fetch.py dark_wood  # one asset

Every asset is listed in assets/ASSETS.md; re-running is idempotent (files are skipped when
present). Map names follow Poly Haven: Diffuse, nor_gl (OpenGL-style normal), Rough.
"""
import json
import os
import sys
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures")
UA = {"User-Agent": "kingpin-texgen/1.0"}

# id -> {map: resolution}
SET = {
	"brick_pavement_02": {"Diffuse": "2k", "nor_gl": "1k", "Rough": "1k"},   # the street
	"asphalt_02": {"Diffuse": "1k", "nor_gl": "1k", "Rough": "1k"},          # the alley
	"dark_wood": {"Diffuse": "1k", "nor_gl": "1k", "Rough": "1k"},           # cabinet
	"wood_floor_deck": {"Diffuse": "1k", "nor_gl": "1k", "Rough": "1k"},     # shooter lane
	"dirty_carpet": {"Diffuse": "1k", "nor_gl": "1k", "Rough": "1k"},        # Club, Penthouse
}

IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"
path="res://.godot/imported/{name}-{hash}.ctex"
metadata={{
"vram_texture": false
}}

[deps]

source_file="res://assets/textures/{asset}/{name}"
dest_files=["res://.godot/imported/{name}-{hash}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={normal}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode={rough}
roughness/src_normal="{src_normal}"
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


def get(url):
	return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read()


def md5_hex(s):
	import hashlib
	return hashlib.md5(s.encode()).hexdigest()


def fetch(asset, maps):
	files = json.loads(get("https://api.polyhaven.com/files/" + asset))
	folder = os.path.join(OUT, asset)
	os.makedirs(folder, exist_ok=True)
	names = {}
	for map_name, res in maps.items():
		entry = files.get(map_name, {}).get(res, {}).get("jpg")
		if entry is None:
			print("texgen: %s has no %s %s jpg" % (asset, map_name, res))
			continue
		name = "%s_%s_%s.jpg" % (asset, map_name.lower(), res)
		path = os.path.join(folder, name)
		if not os.path.exists(path):
			print("texgen: %s <- %s" % (name, entry["url"]))
			open(path, "wb").write(get(entry["url"]))
		names[map_name] = name
	for map_name, name in names.items():
		normal = "1" if map_name == "nor_gl" else "0"
		rough = "0"
		src_normal = ""
		if map_name == "Rough" and "nor_gl" in names:
			# roughness mipmaps are corrected against the normal map so distant surfaces
			# don't go glossy
			rough = "1"
			src_normal = "res://assets/textures/%s/%s" % (asset, names["nor_gl"])
		imp = IMPORT_TEMPLATE.format(name=name, asset=asset, hash=md5_hex("res://assets/textures/%s/%s" % (asset, name)),
				normal=normal, rough=rough, src_normal=src_normal)
		open(os.path.join(folder, name + ".import"), "w").write(imp)
	return names


def main():
	wanted = sys.argv[1:] or list(SET.keys())
	for asset in wanted:
		fetch(asset, SET[asset])
	print("texgen: done")


if __name__ == "__main__":
	main()
