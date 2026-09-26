// 漂う残骸：カメラの周りの箱の中で折り返す
shader_type spatial;
render_mode world_vertex_coords;

uniform float box = 1400.0;
uniform vec3 base_color : source_color = vec3(0.3, 0.29, 0.28);

void vertex() {
	vec3 ip = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 w = cam + mod(ip - cam, vec3(box)) - vec3(box * 0.5);
	float dcam = length(w - cam);
	float k = smoothstep(box * 0.5, box * 0.36, dcam) * smoothstep(25.0, 120.0, dcam);
	VERTEX = w + (VERTEX - ip) * k;
}

void fragment() {
	ALBEDO = base_color * COLOR.rgb;
	ROUGHNESS = 0.85;
	METALLIC = 0.25;
}
