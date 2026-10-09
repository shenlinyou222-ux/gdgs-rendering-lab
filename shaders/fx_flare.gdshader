shader_type spatial;
// v0.9 通用光晕告示板:炮口/弹着/充能 —— 径向辉光+四芒星+可选冲击环+呼吸脉冲
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(1.0);
uniform float intensity = 1.0;
uniform float spike = 1.0;      // 十字星芒强度
uniform float ring = 0.0;       // 冲击环强度(弹着)
uniform float progress = 1.0;   // 充能进度包络 0-1
uniform float time = 0.0;

void vertex() {
	// 面向相机(保持模型缩放),同 nebula_billboard 手法
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * s,
		INV_VIEW_MATRIX[1] * s,
		INV_VIEW_MATRIX[2] * s,
		MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float breathe = 0.85 + 0.15 * sin(time * 6.2831);
	float glow = exp(-r * r * 5.5);                                   // 中心软辉光
	float star = (pow(abs(cos(a)), 18.0) + 0.55 * pow(abs(cos(a * 2.0 + 0.7854)), 24.0)) * exp(-r * 2.6);
	float halo = 0.35 * exp(-r * 1.6);                               // 宽域泛光
	float ringv = ring * smoothstep(0.03, 0.0, abs(r - (0.35 + 0.55 * fract(time * 0.8)))) * 0.9;
	float e = intensity * progress * breathe;
	vec3 col = tint.rgb * (glow * 1.6 + halo) + vec3(1.0, 0.97, 0.92) * star * 0.85 + tint.rgb * ringv;
	float lum = e * (glow + star * spike + halo * 0.7 + ringv);
	ALBEDO = col * e;
	ALPHA = clamp(lum, 0.0, 1.0);
}
