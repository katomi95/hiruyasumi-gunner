// 噴射口・灯火などの発光部
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float energy = 3.0;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	ALBEDO = COLOR.rgb * tint.rgb * energy;
}
