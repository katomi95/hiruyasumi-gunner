// 制御装置を守るシールド：縁だけが光る薄い膜
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.6, 0.45, 1.0, 1.0);

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float band = 0.5 + 0.5 * sin(TIME * 3.0 + UV.y * 40.0);
	ALBEDO = color.rgb * (0.04 + f * 1.4) * (0.8 + 0.2 * band);
}
