// 宇宙背景：星・星雲・銀河の帯・惑星・恒星
shader_type sky;

uniform vec3 sun_dir = vec3(-0.45, 0.55, 0.7);
uniform vec3 planet_dir = vec3(0.55, -0.32, -0.77);
uniform float planet_size = 0.3;
uniform float gain = 1.0;   // Web（Compatibility）では星雲が暗く出るので持ち上げる
// 跳躍ごとに変わる景色
uniform vec3 planet_a : source_color = vec3(0.42, 0.33, 0.26);
uniform vec3 planet_b : source_color = vec3(0.72, 0.6, 0.46);
uniform vec3 planet_c : source_color = vec3(0.3, 0.36, 0.44);
uniform vec3 nebula_a : source_color = vec3(0.11, 0.045, 0.16);
uniform vec3 nebula_b : source_color = vec3(0.02, 0.07, 0.11);
uniform float bands = 7.0;

float h31(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
vec3 h33(vec3 p) { p = fract(p * vec3(0.1031, 0.1030, 0.0973)); p += dot(p, p.yxz + 33.33); return fract((p.xxy + p.yxx) * p.zyx); }
float vn(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 5; i++) { s += a * vn(p); p = p * 2.03 + vec3(1.7, 9.2, 3.1); a *= 0.5; } return s; }

float stars(vec3 d, float sc, float thr, float sz) {
	vec3 p = d * sc;
	vec3 c = floor(p);
	float h = h31(c);
	if (h < thr) return 0.0;
	vec3 o = h33(c) * 0.5 + 0.25;
	float dd = length(fract(p) - o);
	return smoothstep(sz, 0.0, dd) * (0.3 + 0.7 * (h - thr) / (1.0 - thr));
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col = vec3(0.004, 0.005, 0.011);
	float n = fbm(d * 2.2);
	float n2 = fbm(d * 4.5 + vec3(3.0));
	float band = exp(-pow(dot(d, normalize(vec3(0.25, 1.0, 0.35))) * 3.2, 2.0));
	col += nebula_a * pow(n, 3.0) * 1.6;
	col += nebula_b * pow(n2, 4.0) * 2.4;
	col += vec3(0.05, 0.045, 0.07) * band * (0.4 + n);
	float dark = smoothstep(0.45, 0.7, fbm(d * 7.0 + 9.0));
	col *= mix(1.0, 0.5, dark * band) * gain;
	float s = stars(d, 170.0, 0.985, 0.22) * 2.2 + stars(d, 420.0, 0.94, 0.28) * 0.7 + stars(d, 900.0, 0.9, 0.3) * 0.25 * (0.4 + band);
	vec3 sc = mix(vec3(1.0, 0.85, 0.7), vec3(0.75, 0.85, 1.0), h31(floor(d * 170.0)));
	col += sc * s;

	vec3 sd = normalize(sun_dir);
	vec3 pd = normalize(planet_dir);
	float R = sin(planet_size);
	float b = dot(d, pd);
	float disc = b * b - (1.0 - R * R);
	if (disc > 0.0 && b > 0.0) {
		float tt = b - sqrt(disc);
		vec3 nrm = normalize(d * tt - pd);
		float lam = max(dot(nrm, sd), 0.0);
		vec3 q = nrm;
		float lat = q.y * bands + fbm(q * 3.0) * 2.5;
		vec3 surf = mix(planet_a, planet_b, 0.5 + 0.5 * sin(lat));
		surf = mix(surf, planet_c, smoothstep(0.55, 0.75, fbm(q * 6.0)));
		float rim = pow(1.0 - max(dot(nrm, -d), 0.0), 2.5);
		col = surf * lam * 1.1 + vec3(0.35, 0.55, 1.0) * rim * (lam * 0.9 + 0.03) + vec3(0.004, 0.005, 0.01);
	} else {
		float ang = acos(clamp(b, -1.0, 1.0));
		float x = max(ang - planet_size, 0.0);
		vec3 toward = normalize(d - pd * b + vec3(1e-5));
		float lit = max(dot(toward, sd) * 0.8 + 0.25, 0.0);
		col += vec3(0.25, 0.45, 1.0) * exp(-x * 60.0) * 0.5 * lit;
	}

	float su = dot(d, sd);
	col += vec3(1.0, 0.92, 0.8) * (smoothstep(0.99975, 0.99985, su) * 30.0 + pow(max(su, 0.0), 400.0) * 1.5 + pow(max(su, 0.0), 12.0) * 0.06);
	COLOR = col;
}
