shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// v1.1 星鲸细胞层: (s,θ,径向系数m,种子) 参数化 —— 截面跟随脊线切向, 任意航向不变形
// s: 0=头 1=尾鳍端; θ: 截面角; m: 径向系数(1=体表, >1 鳍/尾鳍/荧光点列外扩)

uniform vec3 baz = vec3(0.0, 0.0, 1.0);  // 体侧向(波幅方向)
uniform sampler2D env_tex : filter_linear, repeat_disable;  // R=体半径m G=压扁比
uniform float time_phase = 0.0;
uniform float reveal = 0.0;
uniform float amp = 40.0;
uniform float size_mul = 1.0;
uniform float wlen = 1300.0;

float flk(float s) {
	return 1.0 + max(s - 0.86, 0.0) * 9.0;   // 尾鳍水平展开系数
}

varying vec3 v_color;
varying float v_rev;

void vertex() {
	vec4 cust = INSTANCE_CUSTOM;
	float s = clamp(cust.x, 0.0, 1.0);
	float th = cust.y;
	float m = cust.z;
	float seed = cust.w;
	float rr = texture(env_tex, vec2(s, 0.5)).r * m;
	float sq = texture(env_tex, vec2(s, 0.5)).g;
	// 体轴: 头 +x(wlen*0.45 前) → 尾
	float x = (0.45 - s) * wlen;
	// 游泳波(体侧向, 头小尾大) + 尾鳍强摆
	float wave = amp * pow(s, 1.3) * sin(s * 8.5 - time_phase);
	wave += max(s - 0.80, 0.0) * 260.0 * sin(time_phase * 1.15 + 1.0);
	float bob = sin(time_phase * 0.45 + s * 2.4) * 18.0;
	// 截面: Sd 水平侧向(尾鳍展开方向), Vd 垂直(压扁)
	vec3 T = normalize(vec3(-wlen, 0.0, -amp * pow(max(s, 0.001), 1.3) * 8.5 * cos(s * 8.5 - time_phase)));
	vec3 Sd = normalize(cross(vec3(0.0, 1.0, 0.0), T));
	vec3 Vd = cross(Sd, T);
	vec3 center = vec3(x, bob, 0.0) + (Sd * cos(th) * flk(s) + Vd * sin(th) * sq) * rr;
	vec3 anchor_w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;   // 鲸中心(节点每帧跟随)
	vec3 wpos = anchor_w + center;
	vec3 crv = vec3(VIEW_MATRIX[0][0], VIEW_MATRIX[1][0], VIEW_MATRIX[2][0]);
	vec3 cuv = vec3(VIEW_MATRIX[0][1], VIEW_MATRIX[1][1], VIEW_MATRIX[2][1]);
	float ps = (30.0 + 30.0 * fract(seed * 0.317)) * size_mul;
	wpos += (crv * UV.x + cuv * (UV.y - 0.5)) * ps;
	VERTEX = (VIEW_MATRIX * vec4(wpos, 1.0)).xyz;
	// 配色: 背深靛蓝 / 腹青白辉光 / 鳍尾荧光青 / 荧光点列 / 稀有琥珀斑
	float upf = clamp(sin(th) * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(vec3(0.58, 0.80, 0.86), vec3(0.035, 0.08, 0.17), upf);
	if (m > 1.4) col = mix(col, vec3(0.20, 0.75, 0.95), 0.8);              // 鳍/尾鳍荧光
	if (fract(seed * 7.13) > 0.93) col = vec3(0.30, 1.0, 1.0);             // 荧光点列
	if (fract(seed * 3.77) > 0.985) col = vec3(1.0, 0.62, 0.28);           // 稀有琥珀斑
	v_color = col;
	v_rev = clamp(reveal * 1.5 - s * 0.5, 0.0, 1.0);
}
