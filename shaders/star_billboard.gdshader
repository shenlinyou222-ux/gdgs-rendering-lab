shader_type spatial;
// 点星/尘埃 billboard:永远面向相机,径向衰减发光,叠加混合
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * s,
		INV_VIEW_MATRIX[1] * s,
		INV_VIEW_MATRIX[2] * s,
		MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p) * 2.0;
	float glow = smoothstep(1.0, 0.2, d);
	float core = smoothstep(0.35, 0.0, d);
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(glow * 0.45 + core, 0.0, 1.0) * COLOR.a;
}
