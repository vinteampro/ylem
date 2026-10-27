shader_type canvas_item;
// Фон: тёмная плазма со светящимися волокнами (fbm-шум с искажением координат),
// а после рекомбинации — реликтовое излучение. Карта флуктуаций, которую рисует
// игрок, подсвечивает плазму и проступает пятнами на реликтовом свете.

uniform vec3 hot_color = vec3(1.0, 0.9, 0.8);
uniform vec3 deep_color = vec3(0.005, 0.005, 0.015);
uniform float intensity = 0.4;
uniform float fog = 1.0;          // 1 — непрозрачная плазма, 0 — прозрачная Вселенная
uniform vec3 cmb_color = vec3(1.0, 0.5, 0.2);
uniform float cmb = 0.0;          // яркость реликтового света
uniform float flow_time = 0.0;
uniform float zoom = 1.0;
uniform float turbulence = 1.0;
uniform float squeeze = 0.0;      // > 0 — сжатие (ярче, плотнее), < 0 — быстрое расширение
uniform vec2 resolution = vec2(1920.0, 1080.0);
uniform vec2 box_size = vec2(2304.0, 1296.0);
uniform vec2 cam_center = vec2(1152.0, 648.0);
uniform float cam_zoom = 1.0;
uniform sampler2D fluct : filter_linear, hint_default_black;
uniform float gain = 1.0;         // < 1 в браузере: там кадр не хранит яркость выше 1

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
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = r * p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = (UV - 0.5) * vec2(resolution.x / resolution.y, 1.0);
	// Камера: фон дальше частиц, поэтому сдвигается и приближается слабее (параллакс).
	vec2 cam_off = (cam_center - box_size * 0.5) / resolution.y;
	vec2 p = (uv / pow(cam_zoom, 0.35) + cam_off * 0.45) * 2.4 * zoom;
	// Та же точка в координатах мира — для карты флуктуаций.
	vec2 world = (UV - 0.5) * resolution / cam_zoom + cam_center;
	float dens = texture(fluct, world / box_size).r;
	float t = flow_time;

	vec3 col = vec3(0.0);

	if (fog > 0.001) {
		vec2 q = vec2(fbm(p + vec2(0.0, t * 0.05)), fbm(p + vec2(5.2, 1.3) - t * 0.04));
		vec2 r = vec2(fbm(p + 3.0 * q * turbulence + vec2(1.7, 9.2) + t * 0.03),
					  fbm(p + 3.0 * q * turbulence + vec2(8.3, 2.8) - t * 0.035));
		float f = fbm(p + 2.5 * r);
		float body = smoothstep(0.32, 0.95, f * f * 1.7 + 0.08 * length(q) + 0.25 * dens);
		float fil = smoothstep(0.55, 0.92, f);
		vec3 plasma = mix(deep_color, hot_color, body) * (0.12 + 0.88 * body * body);
		plasma += hot_color * pow(fil, 3.0) * 0.55;
		float press = 1.0 + 0.12 * squeeze + 0.9 * max(dens, 0.0) - 0.4 * max(-dens, 0.0);
		col += plasma * intensity * fog * press;
	}

	if (cmb > 0.001) {
		// Неоднородности реликтового излучения (в реальности ~0,001%, здесь усилены).
		// Знак — как на больших масштабах (плато Сакса — Вольфа, ΔT/T = Φ/3); на масштабах
		// меньше звукового горизонта знак зависел бы от фазы акустических колебаний.
		// Сгущения выглядят холодными пятнами: свет теряет энергию, выбираясь из их
		// гравитационной ямы (эффект Сакса — Вольфа).
		float an = (fbm(uv * 5.0 + 11.0) - 0.5) + 0.6 * (fbm(uv * 13.0 - 3.0) - 0.5) - 0.9 * dens;
		vec3 cold = vec3(0.10, 0.25, 0.9);
		vec3 warm = vec3(1.0, 0.5, 0.15);
		vec3 tint = mix(cold, warm, smoothstep(-0.22, 0.22, an));
		vec3 c = mix(cmb_color, tint, 0.5) * (0.4 + 1.2 * abs(an));
		col += c * cmb * (1.0 - fog);
	}

	float vig = smoothstep(1.35, 0.2, length(uv * vec2(0.85, 1.0)));
	col *= mix(0.35, 1.0, vig);
	// Кадр хранится в линейном цвете и при выводе на экран переводится в sRGB.
	// Цвета выше подобраны «на глаз» как экранные, поэтому возводим в 2,2.
	COLOR = vec4(pow(max(col, vec3(0.0)), vec3(2.2)) * gain, 1.0);
}
