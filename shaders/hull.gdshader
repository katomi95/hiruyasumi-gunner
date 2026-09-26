// 艦体：物体空間の三面投影で装甲板の継ぎ目と窓明かりを描く。遠いほど細部を落とす
shader_type spatial;
render_mode cull_back;

uniform vec3 base_color : source_color = vec3(0.6);
uniform vec3 light_color : source_color = vec3(0.6, 0.9, 1.0);
uniform float panel_size = 4.0;
uniform float light_density = 0.03;
uniform float light_energy = 4.0;
uniform float metal = 0.5;

varying vec3 opos;
varying vec3 onrm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

void fragment() {
	vec3 an = abs(onrm);
	vec2 uv;
	float fs;
	if (an.x > an.y && an.x > an.z) { uv = opos.zy; fs = 1.0; }
	else if (an.y > an.z) { uv = opos.xz; fs = 2.0; }
	else { uv = opos.xy; fs = 3.0; }
	vec2 g = uv / panel_size * vec2(1.0, 1.7);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	vec2 fw = fwidth(g);
	float detail = clamp(1.0 - max(fw.x, fw.y) * 2.5, 0.0, 1.0);
	vec2 e = smoothstep(vec2(0.0), fw * 1.2 + 0.02, f) * smoothstep(vec2(0.0), fw * 1.2 + 0.02, 1.0 - f);
	float seam = mix(1.0, min(e.x, e.y), detail);
	float r = hash12(cell + fs * 17.0);
	float r2 = hash12(floor(g / 5.0) + fs * 5.0);
	vec3 c = base_color * COLOR.rgb * (0.7 + 0.28 * r + 0.14 * r2);
	c *= mix(0.45, 1.0, seam);
	ALBEDO = c;
	METALLIC = metal;
	ROUGHNESS = 0.36 + 0.36 * r;
	vec2 wg = uv / (panel_size * 0.32);
	vec2 wc = floor(wg);
	vec2 wf = fract(wg);
	vec2 wfw = fwidth(wg);
	float wdetail = clamp(1.4 - max(wfw.x, wfw.y) * 1.5, 0.0, 1.0);
	float lit = step(1.0 - light_density, hash12(wc * 1.37 + fs * 7.0));
	float dotm = step(0.28, wf.x) * step(wf.x, 0.72) * step(0.36, wf.y) * step(wf.y, 0.64);
	EMISSION = light_color * lit * dotm * light_energy * wdetail * COLOR.a;
}
