shader_type spatial;
// v0.9.1 等离子弹体:视向核心增亮 + 沿弹轴滚动的能量条带(GDQuest projectile 手法,MIT)
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.2, 1.0);
uniform float energy = 1.6;

void fragment() {
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float bands = 0.72 + 0.28 * sin((UV.y * 7.0 - TIME * 0.35) * 6.2831);
	float e = (0.22 + 0.78 * pow(facing, 1.4)) * bands;
	vec3 col = mix(tint.rgb * 1.5, vec3(1.35), pow(facing, 3.0) * 0.55);
	ALBEDO = col * e;
	ALPHA = clamp(e * energy * 0.85, 0.0, 1.0);
}
