shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// 诊断 shader: 不用 world_vertex_coords, 直接读 INSTANCE_CUSTOM 沿 X 展开
void vertex() {
	vec4 cust = INSTANCE_CUSTOM;
	VERTEX = (VIEW_MATRIX * vec4(cust.x * 2.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	ALBEDO = vec3(1.0, 0.0, 1.0);
	ALPHA = 1.0;
}
