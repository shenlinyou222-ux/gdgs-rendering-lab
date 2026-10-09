shader_type spatial;
// v6.7 云层 + v6.9 昼夜因子:夜面云随行星一起暗
render_mode blend_mix, depth_draw_never, cull_back, unshaded, fog_disabled;
uniform float coverage : hint_range(0.0, 1.0) = 0.5;
uniform float drift : hint_range(0.0, 10.0) = 0.6;
uniform vec4 cloud_tint : source_color = vec4(1.0, 1.0, 1.0, 0.75);
uniform vec3 sun_dir = vec3(0.0, 0.0, -1.0);
// v6.12b: 相机贴近行星时整壳淡出(1.6r 起渐隐, 1.05r 全隐)
uniform vec3 planet_pos_v612 = vec3(0.0);
uniform float surface_r = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int k = 0; k < 5; k++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 uv = UV * vec2(6.0, 3.0);
	float n = fbm(uv + vec2(TIME * drift * 0.01, 0.0));
	float ndl = dot(normalize(mat3(INV_VIEW_MATRIX) * NORMAL), sun_dir);	// v6.13: 世界空间晨昏线
	float dayf = clamp((ndl + 0.25) / 1.25, 0.0, 1.0);
	ALBEDO = cloud_tint.rgb;
	float veil_fade = smoothstep(surface_r * 1.05, surface_r * 1.6, distance(CAMERA_POSITION_WORLD, planet_pos_v612));
	ALPHA = smoothstep(coverage, coverage + 0.25, n) * cloud_tint.a * (0.12 + 0.88 * dayf) * veil_fade;
}
