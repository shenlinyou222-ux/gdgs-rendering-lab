shader_type sky;
// 双全景天空:NASA 全天巡天图(地基,覆盖全方向)+ 星云拼接全景(氛围层)相加混合
uniform sampler2D pan_mosaic : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D pan_nasa : source_color, filter_linear_mipmap, repeat_enable;
uniform float mosaic_gain : hint_range(0.0, 2.0) = 0.85;
uniform float sky_black_point : hint_range(0.0, 0.6) = 0.28;
uniform float sky_knee : hint_range(0.1, 4.0) = 0.9;
uniform float nasa_gain : hint_range(0.0, 3.0) = 1.30;

void sky() {
	vec3 d = normalize(EYEDIR);
	vec2 uv = vec2(atan(d.x, -d.z), asin(clamp(d.y, -1.0, 1.0)))
			* vec2(0.15915494, 0.31830989) + 0.5;
	vec3 c = texture(pan_mosaic, uv).rgb * mosaic_gain;
	c += texture(pan_nasa, uv).rgb * nasa_gain;
	// v6.11:软黑电平 —— 巡天图/EXR 的弥漫天光把太空抬成白雾(实测 mean~0.4),
	// 减去黑电平后底色归黑、星点与银河核保留;平滑无拼缝台阶
	float lum = max(max(c.r, c.g), c.b);
	c *= clamp((lum - sky_black_point) / max(lum, 1e-5), 0.0, 1.0);
	// v6.11:软肩 —— EXR 银河核峰值 HDR≥5,FILMIC 也压到 1.0(全屏 11% 像素爆白);
	// 超过 knee 的部分 Reinhard 式滚降,天空永不过曝,亮带边缘梯度同步变缓(消突变)
	float l2 = max(max(c.r, c.g), c.b);
	c *= sky_knee / (sky_knee + max(l2 - sky_knee, 0.0));
	COLOR = c;
}
