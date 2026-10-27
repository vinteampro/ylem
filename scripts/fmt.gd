extends RefCounted
## Форматирование чисел: 9,1×10⁸ (по-русски) или 9.1×10⁸, «3 мин 12 с», «380 тыс. лет».

const I18n := preload("res://scripts/i18n.gd")

const SUP := ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]

## Надстрочный минус и стрелка. Во встроенном шрифте Godot (им пользуется веб-сборка,
## где нет системных шрифтов) этих знаков нет, и вместо них рисуется квадратик с кодом —
## там hud.gd подставляет «¯» и «»».
static var sup_minus := "⁻"
static var arrow := "→"


static func sup(e: int) -> String:
	var s := ""
	if e < 0:
		s = sup_minus
		e = -e
	for ch in str(e):
		s += SUP[int(ch)]
	return s


static func comma(s: String) -> String:
	return s.replace(".", ",") if I18n.is_ru() else s


## Число с тремя значащими цифрами, без экспоненты.
static func num(v: float) -> String:
	var a := absf(v)
	if a >= 100.0:
		return str(roundi(v))
	if a >= 10.0:
		return comma("%.1f" % v)
	return comma("%.2f" % v)


## Научная запись: 9,1×10⁸.
static func sci(v: float, digits: int = 1) -> String:
	if v == 0.0 or is_nan(v):
		return "0"
	var e := floori(log(absf(v)) / log(10.0) + 1.0e-9)
	if e >= -2 and e <= 3:
		return num(v)
	var m := v / pow(10.0, e)
	if absf(m) >= 9.95 and digits <= 1:
		m /= 10.0
		e += 1
	var fmt := "%." + str(digits) + "f"
	return comma(fmt % m) + "×10" + sup(e)


## Космическое время в понятных единицах.
static func duration(sec: float) -> String:
	if sec < 1.0e-3:
		return num(sec * 1.0e6) + I18n.t("u_us")
	if sec < 1.0:
		return num(sec * 1.0e3) + I18n.t("u_ms")
	if sec < 120.0:
		return num(sec) + I18n.t("u_s")
	if sec < 7200.0:
		var m := floori(sec / 60.0)
		return I18n.t("u_min_s") % [m, floori(sec - m * 60.0)]
	if sec < 2.0 * 86400.0:
		return num(sec / 3600.0) + I18n.t("u_h")
	var years := sec / 3.156e7
	if years < 2.0:
		return num(sec / 86400.0) + I18n.t("u_day")
	if years < 1000.0:
		return num(years) + I18n.t("u_yr")
	if years < 1.0e6:
		return num(years / 1000.0) + I18n.t("u_kyr")
	if years < 1.0e9:
		return num(years / 1.0e6) + I18n.t("u_myr")
	return num(years / 1.0e9) + I18n.t("u_gyr")


static func percent(v: float) -> String:
	return comma("%.1f" % (v * 100.0)) + "%"
