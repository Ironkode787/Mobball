shader_type canvas_item;

uniform float edge : hint_range(0.0, 0.08) = 0.02;

void fragment() {
	vec4 ink = texture(TEXTURE, UV) * COLOR;
	float radius = length(UV - vec2(0.5));
	ink.a *= 1.0 - smoothstep(0.5 - edge, 0.5, radius);
	COLOR = ink;
}
