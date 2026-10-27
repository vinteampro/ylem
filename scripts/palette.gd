extends RefCounted
## Цвета Вселенной. Плазма светится как абсолютно чёрное тело:
## при остывании цвет идёт от голубовато-белого к оранжевому и тёмно-красному.


## Цвет излучения абсолютно чёрного тела (аппроксимация Таннера Хелланда), sRGB 0..1.
static func blackbody(temp_k: float) -> Color:
	var t := clampf(temp_k, 800.0, 40000.0) / 100.0
	var r: float
	var g: float
	var b: float
	if t <= 66.0:
		r = 255.0
		g = 99.4708025861 * log(t) - 161.1195681661
	else:
		r = 329.698727446 * pow(t - 60.0, -0.1332047592)
		g = 288.1221695283 * pow(t - 60.0, -0.0755148492)
	if t >= 66.0:
		b = 255.0
	elif t <= 19.0:
		b = 0.0
	else:
		b = 138.5177312231 * log(t - 10.0) - 305.0447927307
	return Color(clampf(r, 0.0, 255.0) / 255.0, clampf(g, 0.0, 255.0) / 255.0, clampf(b, 0.0, 255.0) / 255.0)


static func log10(v: float) -> float:
	return log(maxf(v, 1.0e-300)) / log(10.0)


## Температура, которой «красим» плазму. Ниже 6500 К — настоящая,
## выше — сжатая логарифмически, иначе всё ранее рекомбинации было бы одинаково голубым.
static func display_temp(T: float) -> float:
	if T < 6500.0:
		return T
	var lt := log10(T)
	var l0 := log10(6500.0)
	return 6500.0 + (lt - l0) / (13.2 - l0) * 33500.0


## Основной цвет плазмы для температуры T.
static func plasma_color(T: float) -> Color:
	var c := blackbody(display_temp(T))
	var lt := log10(T)
	if lt > 11.6:
		# Кварк-глюонная плазма — условный фиолетовый оттенок.
		c = c.lerp(Color(0.72, 0.55, 1.0), clampf((lt - 11.6) / 1.4, 0.0, 1.0) * 0.65)
	return c


## Глубокий (тёмный) цвет плазмы — «тени» между волокнами.
static func plasma_deep(T: float) -> Color:
	var lt := log10(T)
	var hot := plasma_color(T)
	var base := Color(0.004, 0.004, 0.012).lerp(Color(0.03, 0.012, 0.05), clampf((lt - 9.0) / 4.0, 0.0, 1.0))
	return base.lerp(hot * 0.1, 0.25)


## Яркость свечения плазмы.
static func plasma_intensity(T: float) -> float:
	var lt := log10(T)
	var v := 0.17 + 0.024 * (lt - 3.4)
	if lt < 3.6:
		v *= clampf((lt - 2.3) / 1.3, 0.04, 1.0)
	return clampf(v, 0.02, 0.8)
