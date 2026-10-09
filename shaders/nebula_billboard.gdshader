shader_type spatial;
// 星云 billboard:面向相机的加法混合贴图板,边缘径向淡出避免矩形硬边
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 2.0) = 0.55;
uniform vec4 tint : source_color = vec4(1.0);

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * s,
		INV_VIEW_MATRIX[1] * s,
		INV_VIEW_MATRIX[2] * s,
		MODEL_MATRIX[3]);
}

void fragment() {
	float edge = smoothstep(0.5, 0.30, max(abs(UV.x - 0.5), abs(UV.y - 0.5)));
	vec3 col = texture(tex, UV).rgb * tint.rgb * strength * edge;
	ALBEDO = col;
	ALPHA = clamp(max(col.r, max(col.g, col.b)), 0.0, 1.0);
}
