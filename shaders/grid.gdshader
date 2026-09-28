shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// 深色金属 + 世界坐标网格线：竞技场的"测试舱"质感，不依赖任何贴图素材。

uniform vec3 base_color : source_color = vec3(0.035, 0.045, 0.072);
uniform vec3 line_color : source_color = vec3(0.16, 0.62, 0.85);
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float grid_size = 2.0;
uniform float line_width = 1.0;
uniform float emission_energy = 0.30;
uniform float surface_roughness = 0.42;
uniform float panel_variation = 0.35;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	vec3 c = v_world / grid_size;
	vec3 d = abs(fract(c - 0.5) - 0.5);
	vec3 fw = max(fwidth(c) * line_width, vec3(0.0001));
	vec3 lines = 1.0 - smoothstep(vec3(0.0), fw, d);

	// 用表面法线挑两个轴，否则整面墙会落在同一个网格面上、整片发光
	vec3 n = abs(NORMAL);
	float g;
	if (n.y > 0.5) {
		g = max(lines.x, lines.z);
	} else if (n.x > 0.5) {
		g = max(lines.y, lines.z);
	} else {
		g = max(lines.x, lines.y);
	}
	g = pow(clamp(g, 0.0, 1.0), 1.3);

	// 每个格子一点随机亮度，看起来像拼装的面板
	float panel = mix(1.0, hash13(floor(c)), panel_variation);

	ALBEDO = base_color * tint * panel;
	ROUGHNESS = surface_roughness;
	METALLIC = 0.20;
	EMISSION = line_color * tint * g * emission_energy;
}
