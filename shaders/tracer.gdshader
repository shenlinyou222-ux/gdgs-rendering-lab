shader_type spatial;
// v0.9 机炮曳光:亮头渐尾能量 streak + 残影淡出(power),替代平色盒
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.5, 1.0, 0.8, 1.0);
uniform float length_m = 10.0;   // streak 全长(头尾归一)
uniform float power = 1.0;       // 残影淡出
uniform float time = 0.0;

varying float v_h;   // -1=头(目标端) +1=尾

void vertex() {
	v_h = clamp(VERTEX.z * 2.0 / max(length_m, 0.001), -1.0, 1.0);
}

void fragment() {
	float head = smoothstep(0.9, -0.85, v_h);   // 头亮尾淡
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float n = 0.78 + 0.22 * sin(v_h * 44.0 + time * 36.0);
	float e = power * head * (0.35 + 0.65 * pow(facing, 1.6)) * n;
	vec3 col = mix(tint.rgb * 1.7, vec3(1.45), pow(head, 3.0) * 0.65);   // 弹头白热
	ALBEDO = col * e;
	ALPHA = clamp(e * 1.3, 0.0, 1.0);
}
