shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// 弹道轨迹线：逐顶点颜色（每段的颜色就是子弹当时的颜色），叠加发光。

varying vec4 v_col;

void vertex() {
	v_col = COLOR;
}

void fragment() {
	ALBEDO = v_col.rgb;
	ALPHA = v_col.a;
}
