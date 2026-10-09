shader_type spatial;
// v6.9 行星表面:太阳方向光照(昼夜半球+柔和晨昏线)—— 三级 LOD 共用同一 shader,切换零差异
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded, fog_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(0.0, 0.0, -1.0);
uniform float night_ambient : hint_range(0.0, 0.3) = 0.07;
uniform float terminator_soft : hint_range(0.0, 0.5) = 0.18;
uniform float day_pow : hint_range(0.25, 4.0) = 1.25;    // v6.14:参数化(行星设 1.0=线性 Lambert, 与 splat relight 严格一致)
uniform float day_gain : hint_range(0.0, 3.0) = 1.08;   // v6.14:同上(网格与高斯切层零亮度差)
void fragment() {
	vec3 n = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);	// v6.13: NORMAL是视线空间, 转世界空间再与sun_dir点积(修晨昏线随相机摆动)
	float ndl = dot(n, sun_dir);
	float wrap = clamp((ndl + terminator_soft) / (1.0 + terminator_soft), 0.0, 1.0);
	float day = pow(wrap, day_pow);
	ALBEDO = texture(tex, UV).rgb * (day * day_gain + night_ambient);
}
