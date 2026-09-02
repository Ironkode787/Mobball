"""Shared helpers for the mesh builders (runs inside Blender, see build_all.py).

Conventions (specs/meshes.md): 1 unit = 10 cm, Blender Z-up, -Y is the piece's front, the
origin sits on the felt at the piece's pivot. Builders return a list of objects whose names
are the node contract the game binds to (Lamp*, Art*, Spin, Door, ...).
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

# --- palette: unsaturated matter, docs/07 ------------------------------------------------
INK = (0.07, 0.063, 0.055)
INK_GLASS = (0.05, 0.05, 0.06)
ZINC = (0.62, 0.64, 0.66)
STEEL = (0.72, 0.74, 0.76)
CHROME = (0.85, 0.87, 0.90)
BRASS = (0.79, 0.64, 0.15)
BRASS_DARK = (0.42, 0.33, 0.09)
RUST = (0.66, 0.33, 0.18)
RUBBER_RED = (0.48, 0.13, 0.13)
RUBBER = (0.10, 0.10, 0.11)
CREAM = (0.91, 0.87, 0.78)
ENAMEL = (0.86, 0.85, 0.80)
WOOD_DARK = (0.16, 0.10, 0.07)
BURGUNDY = (0.29, 0.12, 0.14)
OLIVE = (0.33, 0.35, 0.22)
TEAL_DULL = (0.12, 0.33, 0.33)
NAVY = (0.16, 0.19, 0.25)
BRICK = (0.55, 0.23, 0.18)
CHEESE = (0.93, 0.78, 0.38)
CRUST = (0.72, 0.52, 0.28)
LAMP = (0.95, 0.80, 0.50)

_materials = {}


def srgb_to_linear(c):
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def mat(name, rgb, metallic=0.0, roughness=0.5):
	"""A cached Principled material: the exporter turns it into glTF PBR. `rgb` is sRGB like
	the rest of the project's palette; Blender and glTF store base colour linear."""
	if name in _materials:
		return _materials[name]
	lin = tuple(srgb_to_linear(c) for c in rgb)
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	bsdf = m.node_tree.nodes["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
	bsdf.inputs["Metallic"].default_value = metallic
	bsdf.inputs["Roughness"].default_value = roughness
	m.diffuse_color = (*lin, 1.0)
	m.metallic = metallic
	m.roughness = roughness
	_materials[name] = m
	return m


def m_ink():
	return mat("ink", INK, 0.1, 0.55)


def m_glass():
	return mat("ink_glass", INK_GLASS, 0.3, 0.2)


def m_zinc():
	return mat("zinc", ZINC, 0.7, 0.55)


def m_steel():
	return mat("steel", STEEL, 1.0, 0.25)


def m_chrome():
	return mat("chrome", CHROME, 1.0, 0.12)


def m_brass():
	return mat("brass", BRASS, 0.9, 0.35)


def m_brass_dark():
	return mat("brass_dark", BRASS_DARK, 0.85, 0.45)


def m_rust():
	return mat("rust", RUST, 0.2, 0.8)


def m_rubber_red():
	return mat("rubber_red", RUBBER_RED, 0.0, 0.8)


def m_rubber():
	return mat("rubber", RUBBER, 0.0, 0.85)


def m_lamp():
	return mat("lamp", LAMP, 0.0, 0.4)


# --- geometry ------------------------------------------------------------------------------

def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	_materials.clear()


def _finish(name, bm, material, smooth=False):
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	if smooth:
		for p in me.polygons:
			p.use_smooth = True
	ob = bpy.data.objects.new(name, me)
	bpy.context.collection.objects.link(ob)
	if material is not None:
		me.materials.append(material)
	if smooth:
		mod = ob.modifiers.new("EdgeSplit", "EDGE_SPLIT")
		mod.split_angle = math.radians(38.0)
	return ob


def box(name, size, center, material, bevel=0.0, segments=2):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
	if bevel > 0.0:
		bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=bevel, segments=segments,
				affect="EDGES", profile=0.7)
	bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
	return _finish(name, bm, material, smooth=bevel > 0.0)


def cyl(name, radius, height, center, material, segments=24, radius_top=None, axis="Z",
		cap=True):
	"""A cylinder (or cone) whose `center` is the middle of its axis."""
	bm = bmesh.new()
	r2 = radius if radius_top is None else radius_top
	bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segments, radius1=radius,
			radius2=r2, depth=height)
	if axis == "X":
		bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), verts=bm.verts)
	elif axis == "Y":
		bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"), verts=bm.verts)
	bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
	return _finish(name, bm, material, smooth=True)


def lathe(name, profile, material, segments=24, center=(0, 0, 0), closed_top=True,
		closed_bottom=True):
	"""Spin a (radius, z) profile about the Z axis. Radii of 0 close the surface."""
	bm = bmesh.new()
	verts = [bm.verts.new((r, 0.0, z)) for r, z in profile]
	edges = [bm.edges.new((verts[i], verts[i + 1])) for i in range(len(verts) - 1)]
	geom = verts + edges
	bmesh.ops.spin(bm, geom=geom, cent=(0, 0, 0), axis=(0, 0, 1), angle=math.tau, steps=segments,
			use_duplicate=False)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)

	def cap(r, z):
		# only the ring the profile ends on: a second ring at the same height (an annulus
		# profile) must not be swept into the same polygon
		ring = [v for v in bm.verts if abs(v.co.z - z) < 1e-5 and abs(v.co.xy.length - r) < 1e-4]
		if len(ring) >= 3:
			bm.faces.new(ring)

	if closed_bottom and profile[0][0] > 1e-6:
		cap(profile[0][0], profile[0][1])
	if closed_top and profile[-1][0] > 1e-6:
		cap(profile[-1][0], profile[-1][1])
	bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
	return _finish(name, bm, material, smooth=True)


def profile_extrude(name, points, width, material, center_y=0.0, bevel=0.0):
	"""Extrude a side profile drawn in (x, z) across Y by `width`, centred on `center_y`."""
	bm = bmesh.new()
	verts = [bm.verts.new((x, center_y - width * 0.5, z)) for x, z in points]
	face = bm.faces.new(verts)
	res = bmesh.ops.extrude_face_region(bm, geom=[face])
	moved = [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]
	bmesh.ops.translate(bm, vec=Vector((0.0, width, 0.0)), verts=moved)
	if bevel > 0.0:
		bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=bevel, segments=2,
				affect="EDGES", profile=0.7)
	return _finish(name, bm, material, smooth=bevel > 0.0)


def disc_uv(name, radius, z, material, segments=32):
	"""A flat disc facing up with UVs mapping the unit square's inscribed circle onto it."""
	bm = bmesh.new()
	bmesh.ops.create_circle(bm, cap_ends=True, cap_tris=True, segments=segments, radius=radius)
	uv = bm.loops.layers.uv.new("UVMap")
	for f in bm.faces:
		for loop in f.loops:
			co = loop.vert.co
			loop[uv].uv = (0.5 + co.x / (2.0 * radius), 0.5 - co.y / (2.0 * radius))
	bmesh.ops.translate(bm, vec=Vector((0.0, 0.0, z)), verts=bm.verts)
	return _finish(name, bm, material)


def torus(name, major, minor, center, material, segments=24, ring=8, axis="Z"):
	bm = bmesh.new()
	prof = [(major + minor * math.cos(t), minor * math.sin(t))
			for t in [i * math.tau / ring for i in range(ring)]]
	prof.append(prof[0])
	verts = [bm.verts.new((r, 0.0, z)) for r, z in prof[:-1]]
	edges = [bm.edges.new((verts[i], verts[(i + 1) % len(verts)])) for i in range(len(verts))]
	bmesh.ops.spin(bm, geom=verts + edges, cent=(0, 0, 0), axis=(0, 0, 1), angle=math.tau,
			steps=segments, use_duplicate=False)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
	if axis == "X":
		bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), verts=bm.verts)
	elif axis == "Y":
		bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"), verts=bm.verts)
	bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
	return _finish(name, bm, material, smooth=True)


def join(name, objects):
	"""Join objects into one mesh named `name`, keeping their material slots."""
	objects = [o for o in objects if o is not None]
	bpy.ops.object.select_all(action="DESELECT")
	for o in objects:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objects[0]
	if len(objects) > 1:
		bpy.ops.object.join()
	ob = bpy.context.view_layer.objects.active
	ob.name = name
	ob.data.name = name
	return ob


def set_origin(ob, point):
	"""Move an object's origin to `point` (world) without moving its geometry."""
	ob.data.transform(Matrix.Translation(-Vector(point)))
	ob.location = Vector(point)


def tri_count(objects):
	total = 0
	dg = bpy.context.evaluated_depsgraph_get()
	for ob in objects:
		ev = ob.evaluated_get(dg)
		me = ev.to_mesh()
		me.calc_loop_triangles()
		total += len(me.loop_triangles)
		ev.to_mesh_clear()
	return total


# --- export & preview ----------------------------------------------------------------------

def export_glb(objects, path):
	os.makedirs(os.path.dirname(path), exist_ok=True)
	bpy.ops.object.select_all(action="DESELECT")
	for o in objects:
		o.select_set(True)
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
			export_apply=True, export_yup=True, export_materials="EXPORT", export_normals=True,
			export_texcoords=True, export_cameras=False, export_lights=False, export_animations=False,
			export_skins=False, export_morph=False)


def preview(objects, path, size=512):
	"""Workbench render from the player's angle (above, in front, looking down-field)."""
	scene = bpy.context.scene
	scene.render.engine = "BLENDER_WORKBENCH"
	scene.display.shading.light = "STUDIO"
	scene.display.shading.color_type = "MATERIAL"
	scene.display.shading.show_shadows = True
	scene.display.shading.show_cavity = True
	scene.render.resolution_x = size
	scene.render.resolution_y = size
	scene.render.film_transparent = False
	scene.view_settings.view_transform = "Standard"
	scene.world = bpy.data.worlds.new("Preview") if scene.world is None else scene.world
	scene.world.color = (0.12, 0.14, 0.12)
	lo = Vector((1e9, 1e9, 1e9))
	hi = Vector((-1e9, -1e9, -1e9))
	for ob in objects:
		for c in ob.bound_box:
			w = ob.matrix_world @ Vector(c)
			lo = Vector(map(min, lo, w))
			hi = Vector(map(max, hi, w))
	centre = (lo + hi) * 0.5
	extent = max((hi - lo).length, 0.2)
	cam_data = bpy.data.cameras.new("PreviewCam")
	cam_data.lens = 50.0
	cam = bpy.data.objects.new("PreviewCam", cam_data)
	scene.collection.objects.link(cam)
	direction = Vector((-0.55, -1.0, 0.9)).normalized()
	cam.location = centre + direction * extent * 1.9
	cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
	scene.camera = cam
	os.makedirs(os.path.dirname(path), exist_ok=True)
	scene.render.filepath = path
	bpy.ops.render.render(write_still=True)
	bpy.data.objects.remove(cam)
	bpy.data.cameras.remove(cam_data)
