shader_type canvas_item;
// Полупрозрачная дымка поверх частиц: в горячей плазме частицы
// видны «сквозь туман», и картинка обретает глубину.

uniform vec3 haze_color = vec3(1.0);
uniform float amount = 0.2;
uniform float flow_time = 0.0;
uniform vec2 resolution = vec2(1920.0, 1080.0);
uniform vec2 cam_off = vec2(0.0);
uniform float cam_zoom = 1.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.1 + vec2(3.1, 7.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = (UV - 0.5) * vec2(resolution.x / resolution.y, 1.0) / pow(cam_zoom, 0.6) + cam_off * 0.8;
	float f = fbm(uv * 1.6 + vec2(flow_time * 0.02, -flow_time * 0.015));
	float a = amount * smoothstep(0.3, 0.85, f);
	COLOR = vec4(pow(max(haze_color, vec3(0.0)), vec3(2.2)), a * a);
}
