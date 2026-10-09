shader_type spatial;
// v6.7 大气边缘光:fresnel 壳(略大于行星),加色渲染,独立于 LOD 层级常驻
render_mode blend_add, depth_draw_never, cull_back, unshaded, fog_disabled;
uniform vec3 rim_color : source_color = vec3(0.35, 0.55, 1.0);
uniform float rim_power : hint_range(1.0, 8.0) = 3.2;
uniform float rim_strength : hint_range(0.0, 3.0) = 1.1;
// v6.12b: 相机贴近行星时整壳淡出(1.6r 起渐隐, 1.05r 全隐)
uniform vec3 planet_pos_v612 = vec3(0.0);
uniform float surface_r = 1.0;
uniform vec3 sun_dir = vec3(0.0, 0.0, -1.0);	// v6.12d: 夜面大气不再自发光(与云同款昼夜因子)
void fragment() {
	float f = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), rim_power);
	float veil_fade = smoothstep(surface_r * 1.05, surface_r * 1.6, distance(CAMERA_POSITION_WORLD, planet_pos_v612));
	float sun_f = clamp((dot(normalize(mat3(INV_VIEW_MATRIX) * NORMAL), sun_dir) + 0.25) / 1.25, 0.0, 1.0);	// v6.13
	ALBEDO = rim_color * rim_strength * f * veil_fade * (0.10 + 0.90 * sun_f);
}
