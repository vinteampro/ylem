extends SceneTree
## Проверка физической модели без графики:
##   godot --headless --path . --script res://tools/sim_check.gd
## 1. Нуклеосинтез на сетке η и N_eff против AlterBBN 2.2 (Arbey et al.), с допусками.
## 2. Рекомбинация и времена эпох при параметрах нашей Вселенной против Planck 2018.
## 3. Что дают рычаги игры.

const UniverseModel := preload("res://scripts/universe.gd")

## Эталон: AlterBBN 2.2, alter_etannutau с η = 6,12·10⁻¹⁰ × множитель, N_ν = 3,044,
## τ_n = 878,4 с, failsafe = 1. Колонки: множитель η, ΔN_ν, Yp, D/H, ³He/H, ⁷Li/H.
const ALTERBBN := [
	[0.1, 0.0, 0.2065, 9.838e-4, 5.414e-5, 1.244e-9],
	[0.3, 0.0, 0.2331, 1.671e-4, 2.288e-5, 1.480e-10],
	[1.0, 0.0, 0.2469, 2.422e-5, 1.028e-5, 5.501e-10],
	[3.0, 0.0, 0.2568, 2.507e-6, 6.124e-6, 2.665e-9],
	[10.0, 0.0, 0.2670, 6.127e-9, 3.887e-6, 6.724e-9],
	[1.0, -2.0, 0.2156, 1.758e-5, 9.292e-6, 6.570e-10],
	[1.0, -1.0, 0.2325, 2.095e-5, 9.803e-6, 6.000e-10],
	[1.0, 1.0, 0.2594, 2.750e-5, 1.074e-5, 5.015e-10],
	[1.0, 3.0, 0.2802, 3.409e-5, 1.160e-5, 4.202e-10],
	[1.0, 6.0, 0.3045, 4.358e-5, 1.273e-5, 3.399e-10],
]
# Допуски: Yp — абсолютный, остальное — относительный.
const TOL_YP := 0.0025
const TOL_D := 0.06
const TOL_HE3 := 0.06
const TOL_LI := 0.12

var _fails := 0


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	UniverseModel.new()
	print("таблицы термодинамики и слабых скоростей: %d мс" % (Time.get_ticks_msec() - t0))
	_check_bbn()
	_check_recombination()
	_check_levers()
	print("\nИТОГ: %s" % ("всё в допусках" if _fails == 0 else "%d отклонений за допусками" % _fails))
	quit(1 if _fails > 0 else 0)


func _run_bbn(e: float, eta_mult: float, dn: float, substep := 0.01):
	var u = UniverseModel.new()
	u.expansion = e
	u.eta_mult = eta_mult
	u.dN_extra = dn
	u.substep = substep
	while u.T > 1.0e7:
		u.advance(0.05)
		u.take_events()
	return u


func _check_bbn() -> void:
	print("\n1. Нуклеосинтез против AlterBBN 2.2")
	print("   η×    ΔN  |  Yp модель / эталон     |  D/H                    |  ³He/H                  |  ⁷Li/H")
	for ref in ALTERBBN:
		var t0 := Time.get_ticks_msec()
		var u = _run_bbn(1.0, ref[0], ref[1])
		var ok_yp: bool = absf(u.helium_mass_fraction() - ref[2]) <= TOL_YP
		var ok_d: bool = _rel(u.d_to_h(), ref[3]) <= TOL_D
		var ok_3: bool = _rel(u.he3_to_h(), ref[4]) <= TOL_HE3
		var ok_li: bool = _rel(u.li7_to_h(), ref[5]) <= TOL_LI
		for ok in [ok_yp, ok_d, ok_3, ok_li]:
			if not ok:
				_fails += 1
		print("   %4.1f %4.0f  |  %.4f / %.4f %s  |  %s / %s %s %+4.0f%%  |  %s / %s %s %+4.0f%%  |  %s / %s %s %+4.0f%%   (%d мс)" % [
			ref[0], ref[1], u.helium_mass_fraction(), ref[2], _mark(ok_yp),
			_e(u.d_to_h()), _e(ref[3]), _mark(ok_d), 100.0 * (u.d_to_h() / ref[3] - 1.0),
			_e(u.he3_to_h()), _e(ref[4]), _mark(ok_3), 100.0 * (u.he3_to_h() / ref[4] - 1.0),
			_e(u.li7_to_h()), _e(ref[5]), _mark(ok_li), 100.0 * (u.li7_to_h() / ref[5] - 1.0),
			Time.get_ticks_msec() - t0])
	# Прогноз в игре идёт крупным шагом — он должен давать то же самое.
	var fine = _run_bbn(1.0, 1.0, 0.0)
	var coarse = _run_bbn(1.0, 1.0, 0.0, 0.05)
	var d_yp: float = absf(coarse.helium_mass_fraction() - fine.helium_mass_fraction())
	var d_d: float = _rel(coarse.d_to_h(), fine.d_to_h())
	var ok: bool = d_yp < 0.001 and d_d < 0.03
	if not ok:
		_fails += 1
	print("   шаг прогноза 0,05 против 0,01: ΔYp = %.4f, ΔD/H = %.1f%% %s" % [d_yp, 100.0 * d_d, _mark(ok)])


func _check_recombination() -> void:
	print("\n2. Наша Вселенная от кварков до тёмных веков")
	var u = UniverseModel.new()
	var t_hadron := 0.0
	var t_bbn := 0.0
	var z_half := 0.0
	var nu_ratio: float = 0.0
	while u.T > 300.0:
		u.advance(0.01)
		u.take_events()
		if t_hadron == 0.0 and u.hadron > 0.5:
			t_hadron = u.t
		if t_bbn == 0.0 and u.helium_mass_fraction() > 0.12:
			t_bbn = u.t
		if z_half == 0.0 and u.xH < 0.5:
			z_half = u.redshift()
		if nu_ratio == 0.0 and u.T < 1.0e8:
			nu_ratio = UniverseModel.t_nu(u.T) / (u.T / UniverseModel.K_PER_MEV)
	var ok_z: bool = absf(u.z_ls / 1089.8 - 1.0) < 0.01
	var ok_nu: bool = absf(nu_ratio / pow(4.0 / 11.0, 1.0 / 3.0) - 1.0) < 0.003
	var ok_x: bool = u.xH > 1.0e-4 and u.xH < 6.0e-4
	for ok in [ok_z, ok_nu, ok_x]:
		if not ok:
			_fails += 1
	print("   адронизация (половина кварков в нуклонах): %.1f мкс   (решёточная КХД: ~10–20 мкс)" % (t_hadron * 1.0e6))
	print("   синтез гелия (половина итога): %.0f с" % t_bbn)
	print("   T_ν/T после аннигиляции e±: %.4f   ((4/11)^⅓ = %.4f) %s" % [nu_ratio, pow(4.0 / 11.0, 1.0 / 3.0), _mark(ok_nu)])
	print("   половина водорода нейтральна: z = %.0f" % z_half)
	print("   пик функции видимости: z* = %.1f, t* = %.0f тыс. лет   (Planck 2018: z* = 1089,8) %s" % [u.z_ls, u.t_ls / 3.156e10, _mark(ok_z)])
	print("   остаточная ионизация: %s   (RECFAST: ~2–3·10⁻⁴) %s" % [_e(u.xH), _mark(ok_x)])


func _check_levers() -> void:
	print("\n3. Рычаги игры (эталона нет: темп расширения умножает H во все эпохи сразу)")
	for cfg in [[1.0, 1.0], [0.6, 1.0], [1.6, 1.0], [1.0, 0.3], [1.0, 3.0]]:
		var u = UniverseModel.new()
		u.expansion = cfg[0]
		u.eta_mult = cfg[1]
		while u.T > 300.0:
			u.advance(0.02)
			u.take_events()
		print("   расширение ×%.1f, плотность ×%.1f:  Yp = %.4f  D/H = %s  ³He/H = %s  ⁷Li/H = %s  прозрачность: z* = %.0f, %.0f тыс. лет" % [
			cfg[0], cfg[1], u.helium_mass_fraction(), _e(u.d_to_h()), _e(u.he3_to_h()), _e(u.li7_to_h()), u.z_ls, u.t_ls / 3.156e10])


func _rel(a: float, b: float) -> float:
	return absf(a / b - 1.0)


func _mark(ok: bool) -> String:
	return "✓" if ok else "✗"


func _e(v: float) -> String:
	if v <= 0.0:
		return "0"
	var ex := floori(log(v) / log(10.0))
	return "%.2fe%d" % [v / pow(10.0, ex), ex]
