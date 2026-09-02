shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

// The Block's street, painted on the playfield: dark setts, a lighter worn asphalt alley down
// the mirror line, and a brass ornament border along the cabinet. With `textured` on the
// surfaces come from the CC0 PBR set in assets/textures (tools/texgen), pushed through the
// house ink treatment (docs/07: desaturated matter, posterised tones, halftone in the darks);
// without it the procedural cobbles below are the look, so the build never depends on the
// textures being present.
uniform bool textured = false;
uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D alley_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D alley_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D alley_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
// field units per texture tile
uniform float stone_repeat = 2.0;
uniform float alley_repeat = 2.2;
uniform vec4 stone_tint : source_color = vec4(0.58, 0.62, 0.70, 1.0);
uniform vec4 alley_tint : source_color = vec4(0.62, 1.05, 0.82, 1.0);
uniform float normal_depth = 0.7;
// ink treatment
uniform float desaturate = 0.35;
uniform float ink_levels = 7.0;
uniform float ink_mix = 0.45;
uniform float halftone_scale = 70.0;
uniform float halftone_strength = 0.22;

uniform vec4 stone_a : source_color = vec4(0.11, 0.115, 0.125, 1.0);
uniform vec4 stone_b : source_color = vec4(0.15, 0.155, 0.165, 1.0);
uniform vec4 mortar : source_color = vec4(0.06, 0.06, 0.06, 1.0);
uniform vec4 alley : source_color = vec4(0.12, 0.25, 0.19, 1.0);
uniform vec4 border : source_color = vec4(0.72, 0.56, 0.15, 1.0);
uniform vec4 border_dark : source_color = vec4(0.16, 0.11, 0.05, 1.0);
uniform vec2 field_size = vec2(5.2, 10.8);
uniform float mirror_x = -0.185;
uniform float alley_half = 0.62;
uniform float border_width = 0.22;
uniform float cobble_scale = 6.5;

varying vec2 field_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 procedural_cobbles(vec2 p) {
	vec2 g = p * cobble_scale;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float best = 9.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 n = vec2(float(x), float(y));
			vec2 c = n + vec2(0.5) + (vec2(hash21(cell + n), hash21(cell + n + 7.0)) - 0.5) * 0.55;
			vec2 d = c - f;
			float dist = length(d * vec2(1.0, 1.25));
			if (dist < best) {
				best = dist;
				id = hash21(cell + n + 13.0);
			}
		}
	}
	float stone_mix = smoothstep(0.40, 0.52, best);
	vec3 stone = mix(stone_a.rgb, stone_b.rgb, id) * (0.9 + 0.2 * hash21(floor(p * 40.0)));
	return mix(stone, mortar.rgb, stone_mix);
}

// Paperback Noir: pull the saturation, posterise the tone, and screen the shadows with a
// halftone dot whose size follows the darkness.
vec3 ink_treatment(vec3 col, vec2 p) {
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), desaturate);
	float q = floor(lum * ink_levels + 0.5) / ink_levels;
	col *= mix(1.0, q / max(lum, 0.004), ink_mix);
	vec2 cellp = fract(p * halftone_scale) - vec2(0.5);
	float dot_r = (1.0 - smoothstep(0.05, 0.55, lum)) * 0.42;
	float ink = 1.0 - smoothstep(dot_r - 0.10, dot_r + 0.02, length(cellp));
	return col * (1.0 - ink * halftone_strength);
}

void vertex() {
	field_pos = (UV - vec2(0.5)) * field_size;
}

void fragment() {
	vec2 p = field_pos;
	float alley_t = 1.0 - smoothstep(alley_half - 0.25, alley_half + 0.15, abs(p.x - mirror_x));
	float edge = min(min(p.x - (-field_size.x * 0.5), field_size.x * 0.5 - p.x),
			field_size.y * 0.5 - p.y);
	float border_t = 1.0 - smoothstep(border_width - 0.02, border_width + 0.02, edge);
	vec3 col;
	float rough = 0.72;
	if (textured) {
		vec2 uv_s = p / stone_repeat;
		vec2 uv_a = p / alley_repeat;
		vec3 stone = texture(stone_albedo, uv_s).rgb * stone_tint.rgb;
		vec3 road = texture(alley_albedo, uv_a).rgb * alley_tint.rgb;
		col = mix(stone, road, alley_t * 0.92);
		col = ink_treatment(col, p);
		vec3 n = mix(texture(stone_normal, uv_s).rgb, texture(alley_normal, uv_a).rgb, alley_t);
		NORMAL_MAP = n;
		NORMAL_MAP_DEPTH = normal_depth * (1.0 - border_t);
		rough = mix(texture(stone_rough, uv_s).r, texture(alley_rough, uv_a).r, alley_t);
		rough = clamp(rough * 0.9 + 0.1, 0.35, 0.95);
	} else {
		col = procedural_cobbles(p);
		col = mix(col, alley.rgb * (0.85 + 0.3 * hash21(floor(p * 60.0))), alley_t * 0.85);
	}
	// ornament border along the sides
	float stripe = 0.5 + 0.5 * sin(p.y * 44.0) * sin(p.x * 44.0);
	vec3 ornament = mix(border_dark.rgb, border.rgb, smoothstep(0.55, 0.75, stripe));
	col = mix(col, ornament, border_t);
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.42, border_t);
	METALLIC = 0.6 * border_t;
	SPECULAR = 0.45;
}
