extends RefCounted
## Физическая модель ранней Вселенной.
##
## Здесь нет графики, только числа. Состояние описывается температурой фотонов T,
## космическим временем t и распространённостями ядер Y (штук на один барион).
##  - Расширение — уравнение Фридмана: H² = 8πG/3 · ρ, где ρ складывается из фотонов,
##    e±, мюонов, кварков и адронов, нейтрино (N_eff = 3,044), вещества и Λ.
##    Температура падает по закону сохранения энтропии, поэтому при аннигиляции e±
##    фотоны подогреваются, а отщепившиеся нейтрино — нет: T_ν/T → (4/11)^⅓.
##  - Слабые реакции n ⇄ p — интегралы по спектрам электронов, позитронов и нейтрино
##    (борновское приближение с кулоновской поправкой, нормировка на время жизни нейтрона).
##  - Сеть из 18 ядерных реакций для n, p, D, T, ³He, ⁴He, ⁷Li, ⁷Be. Скорости — из
##    NACRE, Coc 2015, Serpico 2004, Ando 2006, Cyburt 2008 и др. в той же записи, что
##    в AlterBBN 2.2; обратные реакции — по детальному равновесию. Система жёсткая,
##    поэтому решается неявным методом (Ньютон с матрицей Якоби).
##  - Рекомбинация: водород по уравнению Пиблса, гелий по Саха. Момент, когда
##    Вселенная становится прозрачной, — пик функции видимости g = τ'·e^(−τ).
##
## Константы — по PDG 2024 и Planck 2018 (см. README, раздел «Научные данные»).
## Проверка против AlterBBN — tools/sim_check.gd.
##
## Игрок влияет на два параметра: темп расширения (expansion умножает H)
## и плотность вещества (eta_mult — во сколько раз барионов больше, чем у нас).

enum Epoch { QUARK, HADRON, NUCLEO, PLASMA, RECOMB, DARK }

const K_PER_MEV := 1.160452e10    # кельвинов в 1 МэВ
const T_START := 1.5e13           # стартовая температура, К (~1,3 ГэВ)
const T_QCD := 1.816e12           # 156,5 МэВ: кварки связываются в адроны (HotQCD, 2019)
const M_E := 0.51099895           # МэВ, масса электрона
const M_MU := 105.658             # МэВ, масса мюона
const M_PI := 138.0               # МэВ, средняя масса пионов
const G_QGP := 47.5               # степени свободы кварков u, d, s и глюонов
const Q_NP := 1.29333             # МэВ: на столько нейтрон тяжелее протона
const TAU_N := 878.4              # с, время жизни свободного нейтрона (PDG 2024)
const N_EFF := 3.044              # эффективное число нейтрино (с учётом неполного отщепления)
const T_NU_DEC := 2.0             # МэВ: нейтрино перестают обмениваться энергией с плазмой
const ETA_STD := 6.12e-10         # барионов на фотон в нашей Вселенной (Planck 2018: Ωb·h² = 0,02237)
const OMEGA_B := 0.04924          # доля барионов сегодня (0,02237 / 0,674²)
const H0 := 2.184e-18             # 67,4 км/с/Мпк в 1/с (Planck 2018)
const OMEGA_M := 0.315            # доля вещества сегодня (Planck 2018)
const T_CMB := 2.7255             # К, температура реликтового излучения сегодня (FIRAS)
const M_PL := 1.220890e22         # МэВ, планковская масса
const HBAR := 6.582120e-22        # МэВ·с
const N_A := 6.02214e23
const ALPHA := 7.2973526e-3       # постоянная тонкой структуры
const I_H := 157800.0             # энергия ионизации водорода (13,6 эВ) в кельвинах
const I_HE := 285300.0            # то же для гелия (24,6 эВ)
const SIGMA_T := 6.6524587e-25    # см², томсоновское сечение
const C_CM := 2.99792458e10       # см/с
const T9_NETWORK := 27.0          # выше 27 млрд К ядра не выживают: считаем только n ⇄ p

# Номера ядер в векторе распространённостей.
const NN := 0
const NP := 1
const ND := 2
const NT := 3
const NHE3 := 4
const NHE4 := 5
const NLI7 := 6
const NBE7 := 7
const NSPEC := 8
const MASS := [1, 1, 2, 3, 3, 4, 7, 7]

## Реакции: [реагент a, кратность, реагент b, кратность, продукт c, кратность,
## продукт d, кратность, коэф. обратной реакции, Q/k в 10⁹ К, канал для графики].
## Номер скорости в _rate() совпадает с номером реакции в AlterBBN.
const REACTIONS := {
	2:  [NT, 1, -1, 0, NHE3, 1, -1, 0, 0.0, 0.0, ""],          # T → ³He + e + ν̄ (12,3 года)
	12: [NN, 1, NP, 1, ND, 1, -1, 0, 0.477, 25.815, "pn_D"],   # p + n → D + γ
	13: [ND, 1, NN, 1, NT, 1, -1, 0, 1.65, 72.612, "Dn"],      # D + n → T + γ
	14: [NHE3, 1, NN, 1, NHE4, 1, -1, 0, 2.63, 238.794, "A3n"], # ³He + n → ⁴He + γ
	16: [NHE3, 1, NN, 1, NT, 1, NP, 1, 1.001, 8.863, "He3n"],  # ³He + n → T + p
	17: [NBE7, 1, NN, 1, NLI7, 1, NP, 1, 1.001, 19.080, ""],   # ⁷Be + n → ⁷Li + p
	19: [NBE7, 1, NN, 1, NHE4, 2, -1, 0, 4.68, 220.382, ""],   # ⁷Be + n → ⁴He + ⁴He
	20: [ND, 1, NP, 1, NHE3, 1, -1, 0, 1.65, 63.749, "Dp"],    # D + p → ³He + γ
	21: [NT, 1, NP, 1, NHE4, 1, -1, 0, 2.63, 229.931, "A3p"],  # T + p → ⁴He + γ
	24: [NLI7, 1, NP, 1, NHE4, 2, -1, 0, 4.68, 201.302, ""],   # ⁷Li + p → ⁴He + ⁴He
	26: [NT, 1, NHE4, 1, NLI7, 1, -1, 0, 1.13, 28.629, "Li"],  # T + ⁴He → ⁷Li + γ
	27: [NHE3, 1, NHE4, 1, NBE7, 1, -1, 0, 1.13, 18.412, "Li"], # ³He + ⁴He → ⁷Be + γ
	28: [ND, 2, -1, 0, NHE3, 1, NN, 1, 1.73, 37.934, "DDn"],   # D + D → ³He + n
	29: [ND, 2, -1, 0, NT, 1, NP, 1, 1.73, 46.798, "DDp"],     # D + D → T + p
	30: [NT, 1, ND, 1, NHE4, 1, NN, 1, 5.51, 204.116, "A3Dn"], # T + D → ⁴He + n
	31: [NHE3, 1, ND, 1, NHE4, 1, NP, 1, 5.51, 212.979, "A3Dp"], # ³He + D → ⁴He + p
	32: [NHE3, 2, -1, 0, NHE4, 1, NP, 2, 0.0, 149.229, ""],    # ³He + ³He → ⁴He + 2p
	33: [NLI7, 1, ND, 1, NHE4, 2, NN, 1, 0.0, 175.487, ""],    # ⁷Li + D → n + 2 ⁴He
	34: [NBE7, 1, ND, 1, NHE4, 2, NP, 1, 0.0, 194.566, ""],    # ⁷Be + D → p + 2 ⁴He
}

# Узлы таблиц Coc et al. 2015 (T9) для D + p и D + D.
const COC_T9 := [0.001, 0.002, 0.003, 0.004, 0.005, 0.006, 0.007, 0.008, 0.009, 0.010,
	0.011, 0.012, 0.013, 0.014, 0.015, 0.016, 0.018, 0.020, 0.025, 0.030, 0.040, 0.050,
	0.060, 0.070, 0.080, 0.090, 0.100, 0.110, 0.120, 0.130, 0.140, 0.150, 0.160, 0.180,
	0.200, 0.250, 0.300, 0.350, 0.400, 0.450, 0.500, 0.600, 0.700, 0.800, 0.900, 1.000,
	1.250, 1.500, 1.750, 2.000, 2.500, 3.000, 3.500, 4.000, 5.000, 6.000, 7.000, 8.000,
	9.000, 10.00]
const COC_DP := [4.815e-14, 6.409e-9, 4.525e-7, 4.896e-6, 2.444e-5, 8.086e-5, 2.078e-4,
	4.499e-4, 8.619e-4, 1.506e-3, 2.450e-3, 3.767e-3, 5.531e-3, 7.816e-3, 1.070e-2, 1.425e-2,
	2.366e-2, 3.659e-2, 8.753e-2, 1.701e-1, 4.476e-1, 8.915e-1, 1.510, 2.302, 3.265, 4.392,
	5.676, 7.109, 8.685, 1.040e1, 1.224e1, 1.420e1, 1.628e1, 2.076e1, 2.565e1, 3.941e1,
	5.505e1, 7.225e1, 9.076e1, 1.104e2, 1.310e2, 1.748e2, 2.212e2, 2.700e2, 3.207e2,
	3.729e2, 5.093e2, 6.522e2, 8.000e2, 9.517e2, 1.265e3, 1.587e3, 1.914e3, 2.244e3,
	2.905e3, 3.557e3, 4.194e3, 4.812e3, 5.410e3, 5.988e3]
const COC_DDN := [1.142e-8, 5.470e-5, 3.021e-3, 3.732e-2, 2.212e-1, 8.546e-1, 2.505, 6.066,
	1.278e1, 2.424e1, 4.237e1, 6.936e1, 1.077e2, 1.600e2, 2.291e2, 3.179e2, 5.667e2, 9.310e2,
	2.504e3, 5.301e3, 1.568e4, 3.369e4, 6.013e4, 9.527e4, 1.390e5, 1.912e5, 2.513e5, 3.190e5,
	3.938e5, 4.753e5, 5.631e5, 6.568e5, 7.559e5, 9.691e5, 1.200e6, 1.842e6, 2.555e6, 3.318e6,
	4.119e6, 4.946e6, 5.792e6, 7.517e6, 9.260e6, 1.100e7, 1.272e7, 1.442e7, 1.850e7, 2.235e7,
	2.595e7, 2.932e7, 3.546e7, 4.093e7, 4.585e7, 5.031e7, 5.816e7, 6.488e7, 7.072e7, 7.583e7,
	8.037e7, 8.437e7]
# В AlterBBN 2.2 при T9 = 1,5 стоит 2,882e7 — выпадает из гладкого ряда (и выше соседней
# ветви D + D → ³He + n), похоже на опечатку вместо 1,882e7. Берём 1,882e7.
const COC_DDP := [1.173e-8, 5.609e-5, 3.092e-3, 3.814e-2, 2.257e-1, 8.707e-1, 2.549, 6.164,
	1.297e1, 2.458e1, 4.290e1, 7.016e1, 1.088e2, 1.615e2, 2.310e2, 3.202e2, 5.698e2, 9.343e2,
	2.502e3, 5.276e3, 1.549e4, 3.307e4, 5.868e4, 9.246e4, 1.343e5, 1.837e5, 2.404e5, 3.039e5,
	3.737e5, 4.493e5, 5.304e5, 6.165e5, 7.072e5, 9.011e5, 1.110e6, 1.682e6, 2.309e6, 2.974e6,
	3.663e6, 4.371e6, 5.089e6, 6.543e6, 8.001e6, 9.448e6, 1.087e7, 1.228e7, 1.565e7, 1.882e7,
	2.181e7, 2.461e7, 2.976e7, 3.440e7, 3.863e7, 4.251e7, 4.946e7, 5.552e7, 6.077e7, 6.529e7,
	6.912e7, 7.228e7]

# Таблицы термодинамики и слабых скоростей: считаются один раз на всю игру.
const TAB_LN_T0 := -9.2103404     # ln(10⁻⁴ МэВ)
const TAB_STEP := 0.03
const TAB_N := 640
const WEAK_T_MIN := 0.008         # МэВ: ниже — только распад нейтрона
const WEAK_T_MAX := 60.0          # МэВ: выше скорости растут как T⁵
static var _tab_ready := false
static var _rho_pl := PackedFloat64Array()   # плотность энергии плазмы без нейтрино, МэВ⁴
static var _dlnT := PackedFloat64Array()     # d ln T / d ln a
static var _ln_a := PackedFloat64Array()     # ln масштабного фактора (a = 1 сегодня)
static var _ln_tnu := PackedFloat64Array()   # ln температуры нейтрино, МэВ
static var _lam_np := PackedFloat64Array()   # n → p, 1/с
static var _lam_pn := PackedFloat64Array()   # p → n, 1/с
static var _ln_a_d := 0.0

var t: float          # космическое время, с
var T: float          # температура излучения, К
var expansion := 1.0  # множитель скорости расширения (1 = как у нас, < 0 = сжатие)
var substep := 0.01   # шаг по ln t; для быстрого прогноза берётся крупнее (0,05)
var eta_mult := 1.0   # множитель плотности вещества
var dN_extra := 0.0   # лишние сорта нейтрино (только для проверки против AlterBBN)

var hadron: float     # доля вещества, уже собранного в нуклоны
var Y := PackedFloat64Array()  # распространённости n, p, D, T, ³He, ⁴He, ⁷Li, ⁷Be
var xH: float         # доля ионизованного водорода (1 = плазма, 0 = атомы)
var xHe: float        # доля ионизованного гелия

## Поверхность последнего рассеяния: пик функции видимости g = τ'·e^(−τ).
## Ищется по ходу времени: пик g там, где перестаёт расти ln τ' + τ.
var ls_found := false
var t_ls := 0.0       # с
var z_ls := 0.0
var _vis_tau := 0.0
var _vis_best := -INF
var _vis_t := 0.0
var _vis_z := 0.0

## Накопленные с прошлого кадра изменения по каналам реакций
## (в долях от числа барионов). По ним графика решает, сколько вспышек показать.
var events: Dictionary = {}
var _hubble := 1.0e-13  # текущий темп расширения H, 1/с

var Yn: float:
	get: return Y[NN]
var Yp: float:
	get: return Y[NP]
var YD: float:
	get: return Y[ND]
## Ядра с A = 3: ³He и тритий (тритий потом распадается в ³He).
var Y3: float:
	get: return Y[NT] + Y[NHE3]
var Y4: float:
	get: return Y[NHE4]
## Ядра с A = 7: ⁷Li и ⁷Be (⁷Be потом захватывает электрон и становится ⁷Li).
var Y7: float:
	get: return Y[NLI7] + Y[NBE7]


func _init() -> void:
	_build_tables()
	reset()


func reset() -> void:
	T = T_START
	t = 0.5 / hubble_std(T)
	hadron = 0.0
	Y = PackedFloat64Array()
	Y.resize(NSPEC)
	Y[NN] = 0.5
	Y[NP] = 0.5
	xH = 1.0
	xHe = 1.0
	ls_found = false
	t_ls = 0.0
	z_ls = 0.0
	_vis_tau = 0.0
	_vis_best = -INF
	events.clear()


## Копия состояния — для прогноза «что будет, если оставить рычаги так».
func clone():
	var c = get_script().new()
	for prop in ["t", "T", "expansion", "eta_mult", "dN_extra", "hadron", "xH", "xHe", "ls_found",
			"t_ls", "z_ls", "_vis_tau", "_vis_best", "_vis_t", "_vis_z"]:
		c.set(prop, get(prop))
	c.Y = Y.duplicate()
	return c


func eta() -> float:
	return ETA_STD * eta_mult


## Продвинуть Вселенную на dlnt «е-фолдов» космического времени (t → t·e^dlnt).
func advance(dlnt: float) -> void:
	if dlnt <= 0.0:
		return
	var steps := maxi(1, ceili(dlnt / substep))
	var h := dlnt / steps
	for i in steps:
		_step(h)


func take_events() -> Dictionary:
	var e := events
	events = {}
	return e


func _emit(channel: String, amount: float) -> void:
	if amount != 0.0 and channel != "":
		events[channel] = float(events.get(channel, 0.0)) + amount


func _step(h: float) -> void:
	# Шаг — доля h от характерного времени. Обычно это возраст t (при расширении
	# t ≈ 1/2H), но если игрок сжимал Вселенную, возраст намного больше хаббловского
	# времени, и шагать надо по последнему, иначе одна ступенька перескочит всю эволюцию.
	var h_eff := absf(expansion) * hubble(T)
	# Порог 0,7/H: при обычном расширении t·H = ½ … ⅔, и шаг остаётся долей возраста.
	var tau := t if h_eff <= 0.0 else minf(t, 0.7 / h_eff)
	var dt := tau * (exp(h) - 1.0)
	t += dt

	var temp_old := T
	# Охлаждение: d ln T/dt = H · d ln T/d ln a. Второе — из сохранения энтропии
	# (обычно −1, но при аннигиляции e± фотоны остывают медленнее).
	# Игрок умножает H на expansion; при отрицательном — сжатие и разогрев.
	var k1 := expansion * hubble(T) * _tab(_dlnT, T)
	var t_mid := clampf(T * exp(0.5 * dt * k1), 1.0, 2.0e13)
	var k2 := expansion * hubble(t_mid) * _tab(_dlnT, t_mid)
	T = clampf(T * exp(dt * k2), 1.0, 2.0e13)
	_hubble = absf(expansion) * hubble(T)

	var nb := baryon_density()

	_hadronize(h)
	_nuclear(temp_old, dt)
	_recombine(nb, dt)


# ---------------------------------------------------------------- расширение

## Энергия фотонов, e±, мюонов, кварков и адронов (без нейтрино) при температуре T, МэВ.
static func _plasma(tm: float) -> Vector2:
	var pi2 := PI * PI
	var rho := pi2 / 15.0 * pow(tm, 4.0)
	var p := rho / 3.0
	var e := _fermi(tm, M_E, 4.0, false)
	var mu := _fermi(tm, M_MU, 4.0, false)
	# Кварк-адронный переход — плавный (crossover): пионный газ ↔ кварк-глюонная плазма.
	var w := 1.0 / (1.0 + exp(-clampf(log(tm / 156.5) / 0.08, -60.0, 60.0)))
	var pion := _fermi(tm, M_PI, 3.0, true)
	var qgp := G_QGP * pi2 / 30.0 * pow(tm, 4.0)
	rho += e.x + mu.x + (1.0 - w) * pion.x + w * qgp
	p += e.y + mu.y + (1.0 - w) * pion.y + w * qgp / 3.0
	return Vector2(rho, p)


## Плотность энергии и давление газа частиц массы m с g степенями свободы, МэВ⁴.
static func _fermi(tm: float, m: float, g: float, boson: bool) -> Vector2:
	var x := m / tm
	if x > 80.0:
		return Vector2.ZERO
	var umax := 45.0 + sqrt(80.0 * x)
	var n := 160
	var du := umax / n
	var s_rho := 0.0
	var s_p := 0.0
	for i in n + 1:
		var u := i * du
		var en := sqrt(u * u + x * x)
		var f := 1.0 / (exp(minf(en, 700.0)) + (-1.0 if boson else 1.0))
		var wgt := 1.0 if (i == 0 or i == n) else (4.0 if i % 2 == 1 else 2.0)
		var u2 := u * u
		s_rho += wgt * u2 * en * f
		s_p += wgt * u2 * u2 / en * f
	var t4 := pow(tm, 4.0)
	return Vector2(g / (2.0 * PI * PI) * t4 * s_rho * du / 3.0, g / (6.0 * PI * PI) * t4 * s_p * du / 3.0)


## Энтропия плазмы (МэВ³); нейтрино входят, пока не отщепились.
static func _entropy(tm: float, with_nu: bool) -> float:
	var rp := _plasma(tm)
	var s := (rp.x + rp.y) / tm
	if with_nu:
		s += 2.0 * PI * PI / 45.0 * 5.25 * pow(tm, 3.0)
	return s


static func _build_tables() -> void:
	if _tab_ready:
		return
	_tab_ready = true
	_rho_pl.resize(TAB_N)
	_dlnT.resize(TAB_N)
	_ln_a.resize(TAB_N)
	_ln_tnu.resize(TAB_N)
	_lam_np.resize(TAB_N)
	_lam_pn.resize(TAB_N)
	# a = 1 сегодня: после отщепления нейтрино энтропия плазмы сохраняется сама по себе.
	var s_d := _entropy(T_NU_DEC, false)
	var s_dc := _entropy(T_NU_DEC, true)
	_ln_a_d = log(_entropy(T_CMB / K_PER_MEV, false) / s_d) / 3.0
	for i in TAB_N:
		var tm := exp(TAB_LN_T0 + i * TAB_STEP)
		var coupled := tm >= T_NU_DEC
		_rho_pl[i] = _plasma(tm).x
		var e1 := 1.0005
		var ds := log(_entropy(tm * e1, coupled) / _entropy(tm / e1, coupled)) / (2.0 * log(e1))
		_dlnT[i] = -3.0 / ds
		var la: float
		if coupled:
			la = _ln_a_d + log(s_dc / _entropy(tm, true)) / 3.0
		else:
			la = _ln_a_d + log(s_d / _entropy(tm, false)) / 3.0
		_ln_a[i] = la
		_ln_tnu[i] = log(tm) if coupled else log(T_NU_DEC) + _ln_a_d - la
	_build_weak()


# Слабые реакции n ⇄ p. Интегрируем по энергии электрона ε (в единицах m_e):
# n → p: распад и ν + n → p + e⁻ (одна формула), e⁺ + n → p + ν̄;
# p → n: e⁻ + p → n + ν (и редкий трёхчастичный захват), ν̄ + p → n + e⁺.
# Кулоновская поправка (функция Ферми) — там, где электрон и протон по одну сторону реакции.
static func _build_weak() -> void:
	var q := Q_NP / M_E
	var i0 := _weak_integral(q, INF, INF, true)
	var last := -1
	for i in TAB_N:
		var tm := exp(TAB_LN_T0 + i * TAB_STEP)
		if tm < WEAK_T_MIN:
			_lam_np[i] = 1.0 / TAU_N
			_lam_pn[i] = 0.0
		elif tm <= WEAK_T_MAX:
			var z := M_E / tm
			var znu := M_E / exp(_ln_tnu[i])
			_lam_np[i] = _weak_integral(q, z, znu, true) / i0 / TAU_N
			_lam_pn[i] = _weak_integral(q, z, znu, false) / i0 / TAU_N
			last = i
		else:
			var k := pow(tm / exp(TAB_LN_T0 + last * TAB_STEP), 5.0)
			_lam_np[i] = _lam_np[last] * k
			_lam_pn[i] = _lam_pn[last] * k


static func _weak_integral(q: float, z: float, znu: float, n_to_p: bool) -> float:
	# ε = 1 + u²: убирает корень у порога.
	var emax := q + 1.0 + (0.0 if z == INF else 45.0 / minf(z, znu))
	if z == INF:
		emax = q
	var umax := sqrt(emax - 1.0)
	var n := 400
	var du := umax / n
	var s := 0.0
	for i in range(1, n + 1):
		var u := i * du
		var e := 1.0 + u * u
		var p := u * sqrt(e + 1.0)
		var eta_c := 2.0 * PI * ALPHA * e / p
		var fermi := eta_c / (1.0 - exp(-eta_c))
		var a := e - q
		var b := e + q
		var v: float
		if z == INF:
			v = a * a * fermi
		elif n_to_p:
			v = a * a * fermi / ((1.0 + exp(clampf(-e * z, -700.0, 700.0))) * (1.0 + exp(clampf(a * znu, -700.0, 700.0))))
			v += b * b / ((1.0 + exp(clampf(e * z, -700.0, 700.0))) * (1.0 + exp(clampf(-b * znu, -700.0, 700.0))))
		else:
			v = a * a * fermi / ((1.0 + exp(clampf(e * z, -700.0, 700.0))) * (1.0 + exp(clampf(-a * znu, -700.0, 700.0))))
			v += b * b / ((1.0 + exp(clampf(-e * z, -700.0, 700.0))) * (1.0 + exp(clampf(b * znu, -700.0, 700.0))))
		var wgt := 1.0 if i == n else (4.0 if i % 2 == 1 else 2.0)
		s += wgt * v * e * p * 2.0 * u
	return s * du / 3.0


static func _tab_at(arr: PackedFloat64Array, tm: float) -> float:
	var x := (log(tm) - TAB_LN_T0) / TAB_STEP
	if x <= 0.0:
		return arr[0]
	if x >= TAB_N - 1:
		return arr[TAB_N - 1]
	var i := floori(x)
	var f := x - i
	return arr[i] * (1.0 - f) + arr[i + 1] * f


## Значение таблицы при температуре temp (К).
static func _tab(arr: PackedFloat64Array, temp: float) -> float:
	return _tab_at(arr, temp / K_PER_MEV)


## Масштабный фактор (a = 1 сегодня). Ниже таблицы остаются только фотоны: a ∝ 1/T.
static func scale_factor(temp: float) -> float:
	var tm := temp / K_PER_MEV
	var t_low := exp(TAB_LN_T0)
	if tm < t_low:
		return exp(_ln_a[0]) * t_low / tm
	return exp(_tab_at(_ln_a, tm))


static func t_nu(temp: float) -> float:
	var tm := temp / K_PER_MEV
	var t_low := exp(TAB_LN_T0)
	if tm < t_low:
		return exp(_ln_tnu[0]) * tm / t_low
	return exp(_tab_at(_ln_tnu, tm))


## Темп расширения нашей Вселенной при температуре temp (К), 1/с.
static func hubble_std(temp: float) -> float:
	return _hubble_of(temp, OMEGA_M, 0.0)


func hubble(temp: float) -> float:
	return _hubble_of(temp, OMEGA_M + (eta_mult - 1.0) * OMEGA_B, dN_extra)


static func _hubble_of(temp: float, omega_m: float, dn: float) -> float:
	var tm := temp / K_PER_MEV
	var t_low := exp(TAB_LN_T0)
	var rho_pl: float
	if tm < t_low:
		rho_pl = PI * PI / 15.0 * pow(tm, 4.0)
	else:
		rho_pl = _tab_at(_rho_pl, tm)
	var tn := t_nu(temp)
	var rho_nu := (N_EFF + dn) * 7.0 / 8.0 * PI * PI / 15.0 * pow(tn, 4.0)
	var h0 := H0 * HBAR
	var rho_c0 := 3.0 * h0 * h0 * M_PL * M_PL / (8.0 * PI)
	var a := scale_factor(temp)
	var rho := rho_pl + rho_nu + rho_c0 * (omega_m / (a * a * a) + (1.0 - OMEGA_M - 9.1e-5))
	return sqrt(8.0 * PI / 3.0 * rho) / M_PL / HBAR


## Барионов в см³: их число сохраняется, плотность падает как a⁻³.
func baryon_density() -> float:
	var a := scale_factor(T)
	return eta() * 20.28 * pow(T_CMB, 3.0) / (a * a * a)


# ---------------------------------------------------------------- кварки

# Кварки → протоны и нейтроны. Обратимо: если разогреть, нуклоны «расплавятся».
func _hadronize(h: float) -> void:
	var h_eq := 1.0 / (1.0 + exp(clampf((T - T_QCD) / (0.12 * T_QCD), -60.0, 60.0)))
	var h_new := h_eq + (hadron - h_eq) * exp(-6.0 * h)
	_emit("hadron", h_new - hadron)
	hadron = h_new


# ---------------------------------------------------------------- ядра

## Скорость реакции N_A⟨σv⟩, см³/(моль·с), при температуре t9 (млрд К).
static func _rate(id: int, t9: float) -> float:
	var t13 := pow(t9, 1.0 / 3.0)
	var t23 := t13 * t13
	var sq := sqrt(t9)
	match id:
		2:
			return 1.78141141239e-9
		12:  # Ando et al. 2006
			if t9 <= 1.5:
				return 44216.0 * (1.0 + 3.75191 * t9 + 1.92934 * t9 * t9 + 0.746503 * pow(t9, 3.0) + 0.0197023 * pow(t9, 4.0) + 3.00491e-6 * pow(t9, 5.0)) \
					/ (1.0 + 5.4678 * t9 + 5.62395 * t9 * t9 + 0.489312 * pow(t9, 3.0) + 0.00747806 * pow(t9, 4.0))
			return (1.0 - 0.8504 * sq + 0.4895 * t9 - 0.09623 * pow(t9, 1.5) + 0.008471 * t9 * t9 - 2.8e-4 * pow(t9, 2.5)) * 47420.0
		13:  # Wagoner 1969
			return (18.9 * t9 + 1.0) * 66.2
		14:  # Wagoner 1969
			return (905.0 * t9 + 1.0) * 6.62
		16:  # Serpico et al. 2004
			if t9 < 2.5:
				return 7.064935e8 + 6.733213571736319e8 * t9 + 1.7181155480346258e9 * t9 * t9 - 4.5367658146835446e8 * pow(t9, 3.0) \
					- 1.2216728981712557e8 * pow(t9, 4.0) - 4.92736677238425e8 * sq - 1.3659670893994067e9 * pow(t9, 1.5) \
					- 6.629932739639357e8 * pow(t9, 2.5) + 4.834951929033479e8 * pow(t9, 3.5)
			return 4.81732e8
		17:  # Serpico et al. 2004
			if t9 < 2.5:
				return 6.8423032e9 + 1.7674863e10 * t9 + 2.6622006e9 * t9 * t9 - 3.3561608e8 * pow(t9, 3.0) - 5.9309139e6 * pow(t9, 4.0) \
					- 1.4987996e10 * sq - 1.0576906e10 * pow(t9, 1.5) + 2.7447598e8 * pow(t9, 2.5) + 7.6425157e7 * pow(t9, 3.5) \
					- 2.282944e7 * pow(t9, -1.5) / exp(0.050351813 / t9)
			return 1.28039e9
		19:  # Hou et al. 2015
			if t9 > 10.0:
				return 0.0
			return exp(-17.8984 + 0.2711 / t9 - 23.8918 / t13 + 62.2135 * t13 - 5.2888 * t9 + 0.3869 * pow(t9, 5.0 / 3.0) - 22.6197 * log(t9))
		20:  # Coc et al. 2015
			return _coc(COC_DP, t9)
		21:  # Caughlan & Fowler 1988
			return 2.2e4 / t23 * exp(-3.869 / t13) * (1.0 + 0.108 * t13 + 1.68 * t23 + 1.26 * t9 + 0.551 * pow(t9, 4.0 / 3.0) + 1.06 * pow(t9, 5.0 / 3.0))
		24:  # Serpico et al. 2004
			if t9 < 2.5:
				var r := (-8.9654123e7 - 2.5851582e8 * t9 - 2.6831252e7 * t9 * t9 + 3.8691673e8 * t13 + 4.9721269e8 * t23 \
					+ 2.6444808e7 * pow(t9, 4.0 / 3.0) - 1.2946419e6 * pow(t9, 5.0 / 3.0) - 1.0941088e8 * pow(t9, 7.0 / 3.0) \
					+ 9.9899564e7 * pow(t9, 8.0 / 3.0)) / t23 / exp(7.73389632 / t13)
				r += exp(-1.137519 * t9 * t9 - 8.6256687 / t13) * (3.0014189e7 - 1.8366119e8 * t9 + 1.7688138e9 * t9 * t9 \
					- 8.4772261e9 * pow(t9, 3.0) + 2.0237351e10 * pow(t9, 4.0) - 1.9650068e10 * pow(t9, 5.0) + 7.9452762e8 * pow(t9, 6.0) \
					+ 1.3132468e10 * pow(t9, 7.0) - 8.209351e9 * pow(t9, 8.0) - 9.1099236e8 * pow(t9, 9.0) + 2.7814079e9 * pow(t9, 10.0) \
					- 1.0785293e9 * pow(t9, 11.0) + 1.3993392e8 * pow(t9, 12.0)) / t23
				return r
			return 1.53403e6 + 84516.7
		26:  # Serpico et al. 2004
			if t9 < 2.5:
				return (0.094614248 - 4.9273133 * t9 + 99.358965 * t9 * t9 - 989.81236 * pow(t9, 3.0) + 4368.45 * pow(t9, 4.0) \
					+ 931.93597 * pow(t9, 5.0) - 391.07855 * pow(t9, 6.0) + 159.23101 * pow(t9, 7.0) - 34.407594 * pow(t9, 8.0) \
					+ 3.3919004 * pow(t9, 9.0) + 0.017556217 * pow(t9, 10.0) - 0.036253427 * pow(t9, 11.0) \
					+ 0.0031118827 * pow(t9, 12.0) - 0.00008714468 * pow(t9, 13.0)) / sq / (exp(8.4e-7 * t9) * pow(1.0 + 1.78616593 * t9, 3.0))
			return 807.406
		27:  # Cyburt & Davids 2008
			return exp(15.609867 - 12.82707707 / t13 - 0.6666667 * log(t9)) \
				* ((1.0 - 0.020478 * t23 + 0.211995 * pow(t9, 4.0 / 3.0)) / (1.0 + 0.255059 * t23 + 0.338573 * pow(t9, 4.0 / 3.0)))
		28:  # Coc et al. 2015
			return _coc(COC_DDN, t9)
		29:  # Coc et al. 2015
			return _coc(COC_DDP, t9)
		30:  # Serpico et al. 2004
			if t9 < 2.5:
				return 6.2265733e8 / (exp(0.49711597 / t9) * pow(t9, 0.56785403)) + exp(-0.23309803 * t9 * t9 - 1.342742 / t13) \
					* (-8.1144927e7 + 2.2315324e9 * t9 - 2.9439669e9 * t9 * t9 + 1.8764462e9 * pow(t9, 3.0) - 6.0511612e8 * pow(t9, 4.0) \
					+ 9.5196576e7 * pow(t9, 5.0) - 5.2901086e6 * pow(t9, 6.0)) / t23
			return 3.40249e8
		31:  # Serpico et al. 2004
			if t9 < 2.5:
				return 3.1038385e8 / (exp(1.6190981 / t9) * pow(t9, 0.12159455)) + exp(-0.0062340825 * t9 * t9 - 1.4540617 / t13) \
					* (-3.1335916e7 - 6.2051071e8 * t9 - 1.8782248e9 * t9 * t9 + 6.5642773e8 * pow(t9, 3.0) + 1.530887e8 * pow(t9, 4.0) \
					- 4.9542138e8 * pow(t9, 10.0 / 3.0) - 1.770285e8 * pow(t9, 11.0 / 3.0) + 1.14185e8 * t13 - 2.516526e7 * pow(t9, 13.0 / 3.0) \
					+ 1.7500204e8 * t23 - 1.7513362e9 * pow(t9, 4.0 / 3.0) + 5.2792247e9 * pow(t9, 5.0 / 3.0) - 3.32382e9 * pow(t9, 7.0 / 3.0) \
					+ 2.0346284e9 * pow(t9, 8.0 / 3.0)) / t23
			return 1.55167e8
		32:  # NACRE 1999
			return 5.59e10 / t23 * exp(-12.277 / t13) * (1.0 - 0.135 * t9 + 2.54e-2 * t9 * t9 - 1.29e-3 * pow(t9, 3.0))
		33:  # Serpico et al. 2004
			if t9 < 2.5:
				return 1.66e11 / t23 * exp(-10.254 / t13) + 1.71e6 * pow(t9, -1.5) * exp(-3.246 / t9) + 1.49e10 * pow(t9, -1.5) * exp(-4.0894 / t9) \
					* (2.57e-2 / t9 + 2.6314 / t23 - 4.1929 / t13 - 2.1241 + 4.1136 * t13)
			return 1.37518e9
		34:  # Caughlan & Fowler 1988
			return 1.07e12 / t23 * exp(-12.428 / t13)
	return 0.0


## Табличная скорость Coc et al. 2015: интерполяция в логарифмах.
static func _coc(tab: Array, t9: float) -> float:
	if t9 <= COC_T9[0]:
		return tab[0]
	var last := COC_T9.size() - 1
	if t9 >= COC_T9[last]:
		return tab[last]
	var i := COC_T9.bsearch(t9) - 1
	var f := log(t9 / COC_T9[i]) / log(COC_T9[i + 1] / COC_T9[i])
	return exp(log(tab[i]) * (1.0 - f) + log(tab[i + 1]) * f)


# Ядерная сеть. Система жёсткая (дейтерий рождается и разбивается светом в миллионы раз
# быстрее, чем меняется температура), поэтому шаг неявный: двухстадийная схема SDIRK2
# второго порядка (Alexander, 1977), каждая стадия решается методом Ньютона.
# Пока горячо (выше 27 млрд К), ядра не живут: считаем только n ⇄ p.
const SDIRK_G := 0.29289321881   # γ = 1 − 1/√2


func _nuclear(temp_old: float, dt: float) -> void:
	var t9 := T / 1.0e9
	if t9 > T9_NETWORK:
		_dissociate_all()
		var lam_np := _tab(_lam_np, T)
		var lam_pn := _tab(_lam_pn, T)
		var free := Y[NN] + Y[NP]
		var k := lam_np + lam_pn
		var yn_eq := free * lam_pn / maxf(k, 1.0e-300)
		var yn := yn_eq + (Y[NN] - yn_eq) * exp(-minf(k * dt, 300.0))
		_emit("n_to_p", Y[NN] - yn)
		Y[NN] = yn
		Y[NP] = free - yn
		return
	if t9 < 0.003:
		# Термоядерные реакции давно погасли; остаются распады нейтрона и трития.
		var dn := Y[NN] * (1.0 - exp(-dt / TAU_N))
		var dtr := Y[NT] * (1.0 - exp(-_rate(2, t9) * dt))
		Y[NN] -= dn
		Y[NP] += dn
		Y[NT] -= dtr
		Y[NHE3] += dtr
		_emit("n_to_p", dn)
		return

	var g := SDIRK_G
	var y0 := Y.duplicate()
	# Стадия 1: в момент t + γ·dt.
	var t1 := temp_old * pow(T / temp_old, g)
	var c1 := _coeffs(t1)
	var y1 := _implicit(y0, g * dt, c1)
	# Стадия 2: в конце шага, с наклоном первой стадии.
	var c2 := _coeffs(T)
	var start := PackedFloat64Array()
	start.resize(NSPEC)
	var r := (1.0 - g) / g
	for i in NSPEC:
		start[i] = y0[i] + r * (y1[i] - y0[i])
	var y := _implicit(start, g * dt, c2)

	# Сколько реакций каждого вида случилось — для вспышек на экране.
	var lam_np: float = c2[0]
	var lam_pn: float = c2[1]
	_emit("n_to_p", (lam_np * y[NN] - lam_pn * y[NP]) * dt)
	var he_made := 0.0
	var a3_made := 0.0
	var li_made := 0.0
	var kf: PackedFloat64Array = c2[2]
	var kr: PackedFloat64Array = c2[3]
	var keys := REACTIONS.keys()
	for k in keys.size():
		var re: Array = REACTIONS[keys[k]]
		var net := _net_flux(re, kf[k], kr[k], y) * dt
		var ch: String = re[10]
		match ch:
			"pn_D", "Dp", "Dn", "He3n":
				_emit(ch, net)
			"DDn", "DDp":
				if net >= 0.0:
					_emit(ch, net)
				else:
					a3_made += net
			"A3Dn", "A3Dp", "A3n", "A3p":
				if net >= 0.0:
					_emit(ch, net)
				else:
					he_made += net
			"Li":
				if net >= 0.0:
					_emit(ch, net)
				else:
					li_made += net
	_emit("He_melt", -he_made)
	_emit("A3_melt", -a3_made)
	_emit("Li_melt", -li_made)
	Y = y


## Коэффициенты реакций при температуре temp: [λ(n→p), λ(p→n), прямые, обратные].
func _coeffs(temp: float) -> Array:
	var t9 := temp / 1.0e9
	var a := scale_factor(temp)
	var rho := eta() * 20.28 * pow(T_CMB, 3.0) / (a * a * a) / N_A
	var keys := REACTIONS.keys()
	var kf := PackedFloat64Array()
	var kr := PackedFloat64Array()
	kf.resize(keys.size())
	kr.resize(keys.size())
	var tt := 0.987e10 * pow(t9, 1.5)
	for k in keys.size():
		var id: int = keys[k]
		var re: Array = REACTIONS[id]
		var f := _rate(id, t9)
		var n_in: int = int(re[1]) + int(re[3])
		var n_out: int = int(re[5]) + int(re[7])
		kf[k] = f * (pow(rho, n_in - 1) if n_in > 1 else 1.0)
		if float(re[8]) > 0.0:
			kr[k] = float(re[8]) * pow(rho, n_out - 1) * pow(tt, n_in - n_out) * exp(-minf(float(re[9]) / t9, 700.0)) * f
	return [_tab(_lam_np, temp), _tab(_lam_pn, temp), kf, kr]


## Решить y = start + c·F(y) методом Ньютона.
func _implicit(start: PackedFloat64Array, c: float, co: Array) -> PackedFloat64Array:
	var lam_np: float = co[0]
	var lam_pn: float = co[1]
	var kf: PackedFloat64Array = co[2]
	var kr: PackedFloat64Array = co[3]
	var keys := REACTIONS.keys()
	var y := PackedFloat64Array()
	y.resize(NSPEC)
	for i in NSPEC:
		y[i] = maxf(start[i], 0.0)
	for it in 4:
		var fv := PackedFloat64Array()
		fv.resize(NSPEC)
		var jac := PackedFloat64Array()
		jac.resize(NSPEC * NSPEC)
		# n ⇄ p
		var w := lam_np * y[NN] - lam_pn * y[NP]
		fv[NN] -= w
		fv[NP] += w
		jac[NN * NSPEC + NN] -= lam_np
		jac[NN * NSPEC + NP] += lam_pn
		jac[NP * NSPEC + NN] += lam_np
		jac[NP * NSPEC + NP] -= lam_pn
		for k in keys.size():
			_add_reaction(REACTIONS[keys[k]], kf[k], kr[k], y, fv, jac)
		# (I − c·J)·Δ = −(y − start − c·F)
		var m := PackedFloat64Array()
		m.resize(NSPEC * NSPEC)
		var rhs := PackedFloat64Array()
		rhs.resize(NSPEC)
		var resid := 0.0
		for i in NSPEC:
			rhs[i] = -(y[i] - start[i] - c * fv[i])
			resid = maxf(resid, absf(rhs[i]) / maxf(absf(y[i]), 1.0e-14))
			for j in NSPEC:
				m[i * NSPEC + j] = (1.0 if i == j else 0.0) - c * jac[i * NSPEC + j]
		if it > 0 and resid < 1.0e-10:
			break
		var dy := _solve(m, rhs)
		for i in NSPEC:
			y[i] = maxf(y[i] + dy[i], 0.0)
	return y


static func _add_reaction(re: Array, kf: float, kr: float, y: PackedFloat64Array, fv: PackedFloat64Array, jac: PackedFloat64Array) -> void:
	var a: int = re[0]
	var ma: int = re[1]
	var b: int = re[2]
	var mb: int = re[3]
	var c: int = re[4]
	var mc: int = re[5]
	var d: int = re[6]
	var md: int = re[7]
	# Прямой поток: kf · Y_a^ma/ma! · Y_b^mb/mb!  и его производные.
	var pa := _pw(y[a], ma)
	var pb := _pw(y[b], mb) if b >= 0 else 1.0
	var ff := kf * pa * pb
	var dfa := kf * _dpw(y[a], ma) * pb
	var dfb := kf * pa * _dpw(y[b], mb) if b >= 0 else 0.0
	var fr := 0.0
	var drc := 0.0
	var drd := 0.0
	if kr > 0.0:
		var pc := _pw(y[c], mc)
		var pd := _pw(y[d], md) if d >= 0 else 1.0
		fr = kr * pc * pd
		drc = kr * _dpw(y[c], mc) * pd
		drd = kr * pc * _dpw(y[d], md) if d >= 0 else 0.0
	var net := ff - fr
	var species := [[a, -ma], [b, -mb], [c, mc], [d, md]]
	for s in species:
		var i: int = s[0]
		if i < 0:
			continue
		var nu: float = s[1]
		fv[i] += nu * net
		jac[i * NSPEC + a] += nu * dfa
		if b >= 0:
			jac[i * NSPEC + b] += nu * dfb
		jac[i * NSPEC + c] -= nu * drc
		if d >= 0:
			jac[i * NSPEC + d] -= nu * drd


static func _net_flux(re: Array, kf: float, kr: float, y: PackedFloat64Array) -> float:
	var ff := kf * _pw(y[int(re[0])], int(re[1])) * (_pw(y[int(re[2])], int(re[3])) if int(re[2]) >= 0 else 1.0)
	var fr := 0.0
	if kr > 0.0:
		fr = kr * _pw(y[int(re[4])], int(re[5])) * (_pw(y[int(re[6])], int(re[7])) if int(re[6]) >= 0 else 1.0)
	return ff - fr


## Y^m / m!  (для двух одинаковых частиц — половина пар).
static func _pw(v: float, m: int) -> float:
	return v if m == 1 else v * v * 0.5


static func _dpw(v: float, m: int) -> float:
	return 1.0 if m == 1 else v


## Решение линейной системы методом Гаусса с выбором главного элемента.
static func _solve(m: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var n := b.size()
	for col in n:
		var piv := col
		for r in range(col + 1, n):
			if absf(m[r * n + col]) > absf(m[piv * n + col]):
				piv = r
		if piv != col:
			for k in n:
				var tmp := m[col * n + k]
				m[col * n + k] = m[piv * n + k]
				m[piv * n + k] = tmp
			var tb := b[col]
			b[col] = b[piv]
			b[piv] = tb
		var d := m[col * n + col]
		if absf(d) < 1.0e-300:
			continue
		for r in range(col + 1, n):
			var f := m[r * n + col] / d
			if f == 0.0:
				continue
			for k in range(col, n):
				m[r * n + k] -= f * m[col * n + k]
			b[r] -= f * b[col]
	var x := PackedFloat64Array()
	x.resize(n)
	for i in range(n - 1, -1, -1):
		var s := b[i]
		for k in range(i + 1, n):
			s -= m[i * n + k] * x[k]
		var d := m[i * n + i]
		x[i] = s / d if absf(d) > 1.0e-300 else 0.0
	return x


# Если игрок сжал и разогрел Вселенную выше 27 млрд К, ядра разваливаются на нуклоны.
func _dissociate_all() -> void:
	var melted := {"He_melt": Y[NHE4], "A3_melt": Y[NT] + Y[NHE3], "Li_melt": Y[NLI7] + Y[NBE7]}
	if Y[ND] + Y[NT] + Y[NHE3] + Y[NHE4] + Y[NLI7] + Y[NBE7] <= 0.0:
		return
	_emit("pn_D", -Y[ND])
	for ch in melted:
		_emit(ch, melted[ch])
	Y[NN] += Y[ND] + 2.0 * Y[NT] + Y[NHE3] + 2.0 * Y[NHE4] + 4.0 * Y[NLI7] + 3.0 * Y[NBE7]
	Y[NP] += Y[ND] + Y[NT] + 2.0 * Y[NHE3] + 2.0 * Y[NHE4] + 3.0 * Y[NLI7] + 4.0 * Y[NBE7]
	for i in [ND, NT, NHE3, NHE4, NLI7, NBE7]:
		Y[i] = 0.0


# ---------------------------------------------------------------- рекомбинация

# Рекомбинация: ядра захватывают электроны.
# Свободные электроны рассеивают свет — пока их много, Вселенная непрозрачна.
# Гелий — по уравнению Саха. Водород — по уравнению Пиблса (1968): электрон, упавший
# сразу на основной уровень, испускает фотон, который тут же ионизует соседний атом,
# поэтому рекомбинация идёт через уровень n = 2 и запаздывает относительно Саха.
func _recombine(nb: float, dt: float) -> void:
	if T > 3.0e5:
		xH = 1.0
		xHe = 1.0
		return
	var th := 2.415e15 * pow(T, 1.5)        # (m_e kT / 2πħ²)^3/2, см⁻³
	var yh := maxf(Y[NP] + Y[ND], 1.0e-6)
	var s_h := th * exp(-minf(I_H / T, 700.0)) / (nb * yh)
	var x_saha := 2.0 / (1.0 + sqrt(1.0 + 4.0 / maxf(s_h, 1.0e-300)))
	var xh_new: float
	if x_saha > 0.985:
		xh_new = x_saha
	else:
		var n_h := nb * yh * 1.0e6                                  # м⁻³
		var tt := T / 1.0e4
		var alpha := 1.14e-19 * 4.309 * pow(tt, -0.6166) / (1.0 + 0.6703 * pow(tt, 0.53))  # м³/с (RECFAST)
		var beta := alpha * th * 1.0e6 * exp(-minf(39450.0 / T, 700.0))                   # фотоионизация с n = 2
		var k_lya := 7.15e-23 / maxf(_hubble, 1.0e-30)            # λα³ / 8πH
		var one_x := maxf(1.0 - xH, 1.0e-12)
		var c := (1.0 + k_lya * 8.227 * n_h * one_x) / (1.0 + k_lya * (8.227 + beta) * n_h * one_x)
		var ion := c * beta * exp(-minf(118350.0 / T, 700.0)) * dt  # ионизация (10,2 эВ — переход Лайман-альфа)
		var rec := c * alpha * n_h * dt
		# Неявная схема: rec·x² + (1 + ion)·x − (xH + ion) = 0
		xh_new = (-(1.0 + ion) + sqrt((1.0 + ion) * (1.0 + ion) + 4.0 * rec * (xH + ion))) / (2.0 * maxf(rec, 1.0e-300))
		if rec < 1.0e-12:
			xh_new = (xH + ion) / (1.0 + ion)
		xh_new = clampf(xh_new, 1.0e-5, 1.0)
	var ne := maxf(nb * (xh_new * yh + Y[NHE4] * xHe), 1.0e-30)
	var r_he := 4.0 * th * exp(-minf(I_HE / T, 700.0)) / ne
	var xhe_eq := 1.0 if r_he > 1.0e15 else r_he / (1.0 + r_he)
	_emit("recHe", (xHe - xhe_eq) * Y[NHE4])
	_emit("recH", (xH - xh_new) * yh)
	xH = xh_new
	xHe = xhe_eq
	_visibility(nb, dt)


# Функция видимости g = τ'·e^(−τ): вероятность, что фотон рассеялся в последний раз
# именно сейчас. Её пик — поверхность последнего рассеяния. Пик g там же, где пик
# ln τ' + τ (τ отсчитываем от любого момента), — это можно поймать, идя вперёд по времени.
func _visibility(nb: float, dt: float) -> void:
	if ls_found or T > 6000.0:
		return
	var ne := nb * (xH * maxf(Y[NP] + Y[ND], 1.0e-6) + Y[NHE4] * xHe)
	var tau_dot := ne * SIGMA_T * C_CM
	_vis_tau += tau_dot * dt
	var g := log(maxf(tau_dot, 1.0e-300)) + _vis_tau
	if g > _vis_best:
		_vis_best = g
		_vis_t = t
		_vis_z = redshift()
	elif g < _vis_best - 0.02:
		ls_found = true
		t_ls = _vis_t
		z_ls = _vis_z


# ---------------------------------------------------------------- показания

func epoch() -> int:
	if hadron < 0.97:
		return Epoch.QUARK
	if T > 1.6e9:
		return Epoch.HADRON
	if T > 1.5e8:
		return Epoch.NUCLEO
	if T > 2.0e4:
		return Epoch.PLASMA
	if T > 2200.0:
		return Epoch.RECOMB
	return Epoch.DARK


func helium_mass_fraction() -> float:
	return 4.0 * Y[NHE4]


func d_to_h() -> float:
	return Y[ND] / maxf(Y[NP], 1.0e-9)


func he3_to_h() -> float:
	return (Y[NHE3] + Y[NT]) / maxf(Y[NP], 1.0e-9)


func li7_to_h() -> float:
	return (Y[NLI7] + Y[NBE7]) / maxf(Y[NP], 1.0e-9)


func years() -> float:
	return t / 3.156e7


func redshift() -> float:
	return 1.0 / scale_factor(T) - 1.0


func kt_mev() -> float:
	return T / K_PER_MEV
