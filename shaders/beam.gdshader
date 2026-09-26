// ビーム：単位長の板をカメラ向きの帯に広げる（原点 → ローカル -Z 方向が射線）
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform float intensity = 3.0;
uniform float alpha = 1.0;
uniform float flow = 0.0;
uniform float core = 0.3;
uniform float tail = 0.0;   // 1 で根元側を暗く（弾の尾）

varying float vlen;

void vertex() {
	vec3 a = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 b = (MODEL_MATRIX * vec4(0.0, 0.0, -1.0, 1.0)).xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	float s = VERTEX.y + 0.5;
	vec3 p = mix(a, b, s);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 side = normalize(cross(b - a, p - cam) + vec3(1e-5, 0.0, 0.0));
	p += side * VERTEX.x * w;
	VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	vlen = length(b - a);
}

void fragment() {
	float d = abs(UV.x - 0.5) * 2.0;
	float s = 1.0 - UV.y;
	float halo = exp(-d * d * 4.0);
	float c = smoothstep(core, 0.0, d);
	float n = 1.0;
	if (flow > 0.0) {
		n = 0.78 + 0.22 * sin(s * vlen * 0.03 - TIME * 60.0 * flow) + 0.1 * sin(s * vlen * 0.011 + TIME * 23.0);
	}
	float tl = mix(1.0, smoothstep(0.0, 1.0, s), tail);
	vec3 col = mix(color.rgb, vec3(1.0), c * 0.85) * (halo * 0.55 + c * 1.6) * intensity * n * tl;
	ALBEDO = col * alpha;
}
