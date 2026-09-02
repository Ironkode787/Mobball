shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

// The Block's street, painted on the playfield: dark cobbles, a lighter worn alley down the
// mirror line, and a brass ornament border along the cabinet. Everything is procedural so
// the build carries no big textures and the look re-themes from these colours.
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

void vertex() {
	field_pos = (UV - vec2(0.5)) * field_size;
}

void fragment() {
	vec2 p = field_pos;
	// cobbles: jittered grid cells, mortar where the cell edges are
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
	vec3 col = mix(stone, mortar.rgb, stone_mix);
	// the alley: worn lighter felt down the middle, with soft edges
	float alley_t = 1.0 - smoothstep(alley_half - 0.25, alley_half + 0.15, abs(p.x - mirror_x));
	col = mix(col, alley.rgb * (0.85 + 0.3 * hash21(floor(p * 60.0))), alley_t * 0.85);
	// ornament border along the sides
	float edge = min(min(p.x - (-field_size.x * 0.5), field_size.x * 0.5 - p.x),
			field_size.y * 0.5 - p.y);
	float border_t = 1.0 - smoothstep(border_width - 0.02, border_width + 0.02, edge);
	float stripe = 0.5 + 0.5 * sin(p.y * 44.0) * sin(p.x * 44.0);
	vec3 ornament = mix(border_dark.rgb, border.rgb, smoothstep(0.55, 0.75, stripe));
	col = mix(col, ornament, border_t);
	ALBEDO = col;
	ROUGHNESS = mix(0.72, 0.42, border_t);
	METALLIC = 0.6 * border_t;
	SPECULAR = 0.45;
}
