extends RefCounted
## Рост сгущений: что происходит с касанием руки.
##
## Касание — возмущение плотности δ одного характерного масштаба (K_MODE). В каждой
## клетке карты два компонента: тёмная материя (δc) и барионы вместе со светом (δb).
## Уравнения линейные и одинаковые для всех клеток, поэтому за шаг считается одна
## матрица перехода 4×4 и применяется ко всей карте.
##   Тёмная материя:  δc̈ + 2H·δċ = 4πGρm·δm
##   Барионы:         δb̈ + (2H + C·γ)·δḃ + C·ω²·δb = 4πGρm·δm
## δm = (1 − fb)·δc + fb·δb; 4πGρm = 3/2·H0²·Ωm/a³; H — с множителем расширения игрока.
##  - Пока барионы связаны со светом (C ≈ 1), давление света раскачивает их: по плазме
##    бегут звуковые волны с частотой ω = k·cs/a, cs = c/√(3(1+R)), R = 3ρb/4ρ_γ.
##  - Фотоны просачиваются из сгущений и размывают их (затухание Силка):
##    d(k_D⁻²)/dt = c·(R²/(1+R) + 16/15) / (6(1+R)·ne·σT·a²), амплитуда ∝ exp(−k²/k_D²).
##  - Связь C гаснет вместе со свободными электронами (по ионизации из universe.gd):
##    барионы освобождаются и падают в ямы тёмной материи, которую свет не трогал.
## Чем быстрее расширение, тем сильнее «хаббловское трение» 2H·δ̇ и тем медленнее рост;
## при сжатии трение меняет знак и сгущения схлопываются быстрее. Плотность барионов
## действует в обе стороны: вещества больше и рост раньше, но большая его доля —
## барионы, которые свет размывает; в итоге при ×10 сгущения слабее, при ×0,1 — сильнее.
## Амплитуды сильно преувеличены (у нас δ ~ 10⁻⁵), чтобы касания были видны.
## Нелинейный коллапс не моделируется: δ ограничено (CAP), δ > 1 — сгущение схлопнулось.

const UniverseModel := preload("res://scripts/universe.gd")

const K_MODE := 0.15             # Мпк⁻¹ (сопутствующий): характерный масштаб касания
const MPC_CM := 3.0857e24
const C_CM := 2.99792458e10
const SIGMA_T := 6.6524587e-25
const CAP := 6.0                 # дальше линейная теория не работает: облако уже схлопнулось

var n := 0
var dc := PackedFloat64Array()   # тёмная материя
var vc := PackedFloat64Array()   # её скорость роста, 1/с
var db := PackedFloat64Array()   # барионы (до рекомбинации — вместе со светом)
var vb := PackedFloat64Array()
var coupling := 1.0              # C: 1 — барионы связаны со светом, 0 — свободны
var fb := 0.157                  # доля барионов в веществе
var _m := PackedFloat64Array()   # матрица перехода за последний шаг (4×4, по строкам)


func _init(cells: int) -> void:
	n = cells
	for arr in [dc, vc, db, vb]:
		arr.resize(n)
	_m.resize(16)


func reset() -> void:
	dc.fill(0.0)
	vc.fill(0.0)
	db.fill(0.0)
	vb.fill(0.0)
	coupling = 1.0


## Касание: вещество сжимается целиком — и тёмная материя, и барионы, без скорости.
## limit — выше рука не поднимает (дальше сгущение растёт само).
func add(i: int, amount: float, limit := CAP) -> void:
	dc[i] = clampf(dc[i] + amount, -1.0, maxf(dc[i], limit))
	db[i] = clampf(db[i] + amount, -1.0, maxf(db[i], limit))


## Полное возмущение вещества.
func matter(i: int) -> float:
	return (1.0 - fb) * dc[i] + fb * db[i]


## Что видно: пока вещество связано со светом — колебания плазмы (барионы),
## после рекомбинации — всё вещество.
func visible(i: int) -> float:
	return lerpf(matter(i), db[i], coupling)


## Продвинуть все клетки на dt секунд космического времени при текущем состоянии u.
## Возвращает false, если за шаг ничего заметно не изменилось (пока сгущения больше
## горизонта, они заморожены, — тогда карту не трогаем).
func step(u, dt: float) -> bool:
	if dt <= 0.0 or n == 0:
		return false
	var co := coefficients(u)
	coupling = co["C"]
	fb = co["fb"]
	_transfer(co, dt)
	var m := _m
	# Как сильно шаг меняет сами контрасты (скорости до горизонта почти нулевые).
	var change := maxf(maxf(absf(m[0] - 1.0), absf(m[10] - 1.0)), maxf(absf(m[2]), absf(m[8])))
	if change < 1.0e-6:
		return false
	for i in n:
		var a0 := dc[i]
		var a1 := vc[i]
		var a2 := db[i]
		var a3 := vb[i]
		dc[i] = clampf(m[0] * a0 + m[1] * a1 + m[2] * a2 + m[3] * a3, -1.0, CAP)
		vc[i] = m[4] * a0 + m[5] * a1 + m[6] * a2 + m[7] * a3
		db[i] = clampf(m[8] * a0 + m[9] * a1 + m[10] * a2 + m[11] * a3, -1.0, CAP)
		vb[i] = m[12] * a0 + m[13] * a1 + m[14] * a2 + m[15] * a3
	return true


## Коэффициенты уравнений при текущем состоянии модели (все — в секундах).
static func coefficients(u) -> Dictionary:
	var a: float = UniverseModel.scale_factor(u.T)
	var h_eff: float = u.expansion * u.hubble(u.T)
	var omega_m: float = UniverseModel.OMEGA_M + (u.eta_mult - 1.0) * UniverseModel.OMEGA_B
	var f_b: float = UniverseModel.OMEGA_B * u.eta_mult / omega_m
	var g4: float = 1.5 * UniverseModel.H0 * UniverseModel.H0 * omega_m / (a * a * a)
	# Свободные электроны — как в функции видимости universe.gd.
	var nb: float = u.baryon_density()
	var ne: float = maxf(nb * (u.xH * maxf(u.Y[UniverseModel.NP] + u.Y[UniverseModel.ND], 1.0e-6) + u.Y[UniverseModel.NHE4] * u.xHe), 1.0e-30)
	var tau_dot := ne * SIGMA_T * C_CM
	var r: float = 704.6 * u.eta_mult * a                  # 3ρb/4ργ = 31 500·Ωb·h²·a
	var k := K_MODE / MPC_CM
	var omega := k * C_CM / sqrt(3.0 * (1.0 + r)) / a
	var silk: float = C_CM * (r * r / (1.0 + r) + 16.0 / 15.0) / (6.0 * (1.0 + r) * ne * SIGMA_T * a * a)
	var gamma: float = 2.0 * k * k * silk
	# Барионы держит свет, пока «сопротивление» τ̇/R велико по сравнению с H.
	var drag: float = tau_dot / (maxf(r, 1.0e-6) * u.hubble(u.T) * 20.0)
	var c: float = drag * drag / (1.0 + drag * drag)
	return {"a": a, "H": h_eff, "g4": g4, "fb": f_b, "omega": omega, "gamma": gamma, "C": c}


## Матрица перехода за dt: полунеявная схема (трение — неявно), шаг мельче периода
## колебаний и хаббловского времени.
func _transfer(co: Dictionary, dt: float) -> void:
	var h_eff: float = co["H"]
	var g4: float = co["g4"]
	var f_b: float = co["fb"]
	var c: float = co["C"]
	var w2: float = c * co["omega"] * co["omega"]
	var fr_c := 2.0 * h_eff
	var fr_b := 2.0 * h_eff + c * float(co["gamma"])
	var rate := maxf(maxf(sqrt(w2), 2.0 * absf(h_eff)), sqrt(g4))
	var steps := clampi(ceili(dt * rate / 0.2), 1, 400)
	var hs := dt / steps
	for col in 4:
		var x := [0.0, 0.0, 0.0, 0.0]
		x[col] = 1.0
		for s in steps:
			var src: float = g4 * ((1.0 - f_b) * x[0] + f_b * x[2])
			x[1] = (x[1] + hs * src) / (1.0 + hs * fr_c)
			x[3] = (x[3] + hs * (src - w2 * x[2])) / (1.0 + hs * fr_b)
			x[0] += hs * x[1]
			x[2] += hs * x[3]
		for row in 4:
			_m[row * 4 + col] = x[row]
