// 宇宙塵：カメラの周りで折り返し、進行方向に尾を引いて速度感を出す
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform float box = 360.0;
uniform vec4 color : source_color = vec4(0.6, 0.7, 0.9, 1.0);
uniform float size = 0.35;
uniform vec3 vel = vec3(0.0);
uniform float streak = 0.06;

varying float fade;

void vertex() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 ip = MODEL_MATRIX[3].xyz;
	vec3 w = cam + mod(ip - cam, vec3(box)) - vec3(box * 0.5);
	vec3 a = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	vec3 vv = (VIEW_MATRIX * vec4(vel, 0.0)).xyz;
	vec3 b = a + vv * streak;
	vec3 p = mix(a, b, VERTEX.y + 0.5);
	vec2 d2 = (b - a).xy;
	vec2 dir = length(d2) > 1e-3 ? normalize(d2) : vec2(0.0, 1.0);
	p.xy += vec2(-dir.y, dir.x) * VERTEX.x * size;
	VERTEX = p;
	float dist = length(a);
	fade = smoothstep(box * 0.5, box * 0.2, dist) * smoothstep(2.0, 12.0, dist);
}

void fragment() {
	float d = abs(UV.x - 0.5) * 2.0;
	ALBEDO = color.rgb * (1.0 - d) * fade;
}
