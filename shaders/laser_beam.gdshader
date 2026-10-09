shader_type spatial;
// v0.9.4 常驻激光能量光束:白炽核心+彩色辉光+能量噪波;亮度压暗+沿程指数衰减
// (视觉权重集中准星附近 fade_dist 内, 远段淡出不可见 —— 用户反馈"太亮看不清")
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 beam_color : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform float power = 1.0;       // 总强度:出射斜坡/微闪/熄灭共用
uniform float coreness = 1.0;    // 1=核心层(细而白),0=辉光层(宽而柔)
uniform float noise_scale = 12.0;
uniform float scroll_speed = 3.0;
uniform float flicker = 0.0;
uniform float time = 0.0;
uniform float beam_len = 300.0;   // 当前光束全长(m)
uniform float fade_dist = 800.0;  // 衰减特征距离(m):e^(-2d/fade) —— 交战区可见,远段淡出

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float n = vnoise(vec2(UV.y * noise_scale - time * scroll_speed, UV.x * 6.0 + time * 0.9));
	n = 0.62 + 0.38 * n + 0.22 * vnoise(vec2(UV.y * noise_scale * 2.6 + time * scroll_speed * 1.6, UV.x * 9.0 - time * 1.3));
	float cap = smoothstep(0.0, 0.05, UV.y) * smoothstep(1.0, 0.95, UV.y);
	// 沿程衰减:炮口全亮 → fade_dist 处 exp 衰减,远段淡出
	float att = exp(-2.0 * UV.y * beam_len / max(fade_dist, 1.0));   // v0.9.7:常驻束恢复可见(260m 处 att~0.52)
	float core = pow(facing, 5.0 + 4.0 * coreness);
	float body = pow(facing, 1.35 + 0.55 * coreness);
	float glow = power * cap * body * n * att * (1.0 - flicker * 0.45);
	vec3 col = mix(beam_color.rgb * (1.3 - 0.5 * coreness), vec3(1.35), core * (0.45 + 0.55 * n));   // v0.9.7:恢复亮度
	ALBEDO = col * glow;
	ALPHA = clamp(glow, 0.0, 1.0);
}
