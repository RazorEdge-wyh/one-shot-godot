shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// 目标的能量外壳：菲涅尔边缘发光 + 缓慢呼吸。

uniform vec3 halo_color : source_color = vec3(0.2, 0.9, 1.0);
uniform float power = 2.4;
uniform float strength = 1.0;
uniform float breathe_speed = 2.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), power);
	float breathe = 0.75 + 0.25 * sin(TIME * breathe_speed);
	ALBEDO = halo_color * (fres * strength * breathe);
	ALPHA = clamp(fres * strength * breathe, 0.0, 1.0);
}
