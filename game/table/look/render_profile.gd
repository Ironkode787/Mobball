class_name RenderProfile
extends RefCounted
## The rendering tier. Phones (any `mobile` export) run the low tier: no glow, a small hard
## shadow map, the 3D view rendered at a fraction of the screen and stretched; desktop keeps
## the full look. `KINGPIN_GFX=low|high` forces a tier for probes (tools/perf.sh).

const LOW_SCALE_3D := 0.75
const LOW_SHADOW_SIZE := 1024
const HIGH_SHADOW_SIZE := 2048


const GROUP_ENVIRONMENT := &"render_profile_environment"
const GROUP_KEY_LIGHT := &"render_profile_key_light"


static func low() -> bool:
	var forced := OS.get_environment("KINGPIN_GFX")
	if forced == "low":
		return true
	if forced == "high":
		return false
	if Presentation != null and Presentation.settings != null:
		return Presentation.settings.fast_graphics
	return OS.has_feature("mobile")


static func name() -> StringName:
	return &"low" if low() else &"high"


## Probe knobs (`KINGPIN_GFX_OFF=shadows,fill_lights,...`): switch a cost off to measure it.
static func off(feature: String) -> bool:
	return feature in OS.get_environment("KINGPIN_GFX_OFF").split(",", false)


## The key light's shadow map: the one shadow-casting light on the table.
static func shadows() -> bool:
	return not off("shadows")


## The fill omni lamps (GI pools, storefront neon spill): the look wants them, the phone tier
## trims the count.
static func fill_lights() -> bool:
	return not off("fill_lights")


## Viewport-wide settings; the table applies it once when it enters the tree.
static func apply(viewport: Viewport) -> void:
	if viewport == null:
		return
	if low():
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = LOW_SCALE_3D
		viewport.positional_shadow_atlas_size = 0
		RenderingServer.directional_shadow_atlas_set_size(LOW_SHADOW_SIZE, false)
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	else:
		viewport.scaling_3d_scale = 1.0
		RenderingServer.directional_shadow_atlas_set_size(HIGH_SHADOW_SIZE, true)
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)


## Re-apply the tier to a running table (the settings toggle): the environment and key
## light register themselves in the groups above when they are built.
static func apply_live() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	apply(tree.root)
	for n in tree.get_nodes_in_group(GROUP_ENVIRONMENT):
		if n is WorldEnvironment and (n as WorldEnvironment).environment != null:
			(n as WorldEnvironment).environment.glow_enabled = not low()
	for n in tree.get_nodes_in_group(GROUP_KEY_LIGHT):
		if n is Light3D:
			(n as Light3D).shadow_enabled = shadows()
