shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded, shadows_disabled;

// v0.9 星鲸外壳层: 球形战机低模壳(近看形体), 与细胞层同一脊线数学

uniform vec3 whale_pos = vec3(0.0);
uniform vec3 bax = vec3(1.0, 0.0, 0.0);
uniform vec3 bay = vec3(0.0, 1.0, 0.0);
uniform vec3 baz = vec3(0.0, 0.0, 1.0);
uniform float wlen = 1800.0;
uniform float time_phase = 0.0;
uniform float reveal = 0.0;
uniform float amp = 26.0;
uniform vec3 sun_dir = vec3(0.4, 0.75, 0.35);

varying vec3 v_n;
varying vec3 v_color;
varying float v_rev;

vec3 spine_point(float s, out vec3 T) {
	float x = (s - 0.5) * wlen;
	float w0 = amp * pow(max(s, 0.0), 1.4) * sin(s * 7.0 - time_phase);
	float w1 = amp * pow(max(s + 0.002, 0.0), 1.4) * sin((s + 0.002) * 7.0 - time_phase);
	float y = sin(time_phase * 0.45 + s * 2.6) * wlen * 0.012;
	T = normalize(vec3(wlen, 0.0, (w1 - w0) / 0.002));
	return vec3(x, y, w0);
}

void vertex() {
	vec4 cust = INSTANCE_CUSTOM;
	float s = cust.x;
	float th = cust.y;
	float rc = cust.z;
	float cs = cust.w;
	vec3 T;
	vec3 P = spine_point(s, T);
	vec3 Sd = normalize(cross(vec3(0.0, 1.0, 0.0), T));
	vec3 Vd = normalize(cross(T, Sd));
	float flk = 1.0 + max(s - 0.86, 0.0) * 11.0;
	vec3 center = P + (Sd * cos(th) * flk + Vd * sin(th) * 0.75) * rc;
	vec3 world_c = whale_pos + bax * center.x + bay * center.y + baz * center.z;
	mat3 B = mat3(bax, bay, baz) * cs;
	vec3 local = VERTEX * vec3(1.3, 1.0, 1.0);
	vec3 wpos = world_c + B * local;
	v_n = (VIEW_MATRIX * vec4(normalize(B * NORMAL), 0.0)).xyz;
	VERTEX = (VIEW_MATRIX * vec4(wpos, 1.0)).xyz;
	float upness = clamp(sin(th) * 0.5 + 0.5, 0.0, 1.0);
	v_color = mix(vec3(0.10, 0.18, 0.26), vec3(0.62, 0.76, 0.82), upness);
	v_rev = clamp(reveal * 1.55 - s * 0.55, 0.0, 1.0);
}

void fragment() {
	float ndl = clamp(dot(normalize(v_n), normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz)), 0.0, 1.0);
	vec3 col = mix(vec3(0.045, 0.07, 0.105), vec3(0.42, 0.55, 0.64), ndl);
	float rim = pow(1.0 - clamp(dot(normalize(v_n), normalize(VERTEX)), 0.0, 1.0), 3.0);
	col += vec3(0.25, 0.7, 0.85) * rim * 0.8;
	ALBEDO = col;
	ALPHA = clamp(v_rev * 1.2, 0.0, 1.0) * 0.45;   // 半透能量膜: 不挡自身细胞高斯球
}
