// 質量兵器の岩肌。crack で内部の赤熱した亀裂が光る
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.36, 0.32, 0.29);
uniform float crack = 0.0;
uniform float scale = 0.012;

varying vec3 opos;

float h31(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
float vn(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 5; i++) { s += a * vn(p); p = p * 2.07 + vec3(3.1, 1.7, 7.3); a *= 0.5; } return s; }

void vertex() { opos = VERTEX; }

void fragment() {
	float n = fbm(opos * scale);
	float n2 = fbm(opos * scale * 5.0 + 11.0);
	vec3 c = base_color * COLOR.rgb * (0.55 + 0.6 * n) * (0.8 + 0.3 * n2);
	ALBEDO = c;
	ROUGHNESS = 0.92;
	float ridge = 1.0 - abs(fbm(opos * scale * 2.3 + 5.0) * 2.0 - 1.0);
	float cr = smoothstep(0.93 - crack * 0.12, 1.0, ridge) * crack;
	EMISSION = vec3(1.0, 0.36, 0.1) * cr * 6.0;
}
