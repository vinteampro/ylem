extends Node2D
## Видимые частицы, камера и «рука» игрока.
##
## На экране — «выборка» из физической модели: ~1000 барионов (больше или меньше —
## в зависимости от плотности вещества). Модель сообщает, сколько реакций каждого
## типа произошло, и поле разыгрывает ровно столько слияний и распадов со вспышками.
##
## Мир — прямоугольник чуть больше экрана (box). Камера своя: зум, панорама,
## параллакс по глубине частиц. Рисуется всё через MultiMesh с аддитивным
## смешиванием и HDR-цветами, которые подхватывает свечение (glow).
##
## Рука: зажатая левая кнопка сжимает и закручивает плазму, правая — разрежает.
## Касания рисуют карту флуктуаций плотности: она проступит на реликтовом
## излучении, а в тёмных веках гравитация стянет туда вещество.

signal reaction_shown(channel: String, pos: Vector2)
signal species_seen(kind: int)
signal follow_changed(active: bool)

const Fmt := preload("res://scripts/fmt.gd")
const I18n := preload("res://scripts/i18n.gd")

enum K { QR, QG, QB, P, N, D, HE3, HE4, LI7, E, H, HE }

const KIND_COUNT := 12
const CAP := 5200
const BASE_BARYONS := 1000
const MAX_FLASH := 192
const MAX_ANIM_PER_FRAME := 10
const FLOATS := 12  # 8 на Transform2D + 4 на цвет

## Множитель яркости всех частиц. В браузере кадр не хранит яркость выше 1,
## поэтому там main.gd уменьшает её здесь и возвращает в конце кадра.
static var gain := 1.0
const BOX_SCALE := 1.2
const GW := 64
const GH := 36
const HAND_R := 150.0
const TAU_N := 879.4

const COLORS := [
	Color(2.4, 0.55, 0.5),   # кварк «красный»
	Color(0.55, 2.2, 0.7),   # кварк «зелёный»
	Color(0.6, 0.8, 2.6),    # кварк «синий»
	Color(1.9, 1.55, 1.15),  # протон
	Color(0.95, 1.2, 1.8),   # нейтрон
	Color(1.1, 2.0, 2.3),    # дейтерий
	Color(2.0, 1.4, 2.6),    # гелий-3
	Color(3.2, 2.3, 0.9),    # гелий-4
	Color(3.0, 0.7, 1.3),    # литий-7 (литий окрашивает пламя в малиновый)
	Color(0.5, 1.5, 2.4),    # электрон
	Color(2.2, 0.75, 0.8),   # атом водорода (H-альфа)
	Color(2.4, 1.9, 1.0),    # атом гелия
]
const SIZES := [6.0, 6.0, 6.0, 10.0, 10.0, 13.0, 14.0, 17.0, 19.0, 4.0, 12.0, 16.0]
const CHARGE := [0, 0, 0, 1, 0, 1, 2, 2, 3, -1, 0, 0]
const BARYON := [1, 1, 1, 3, 3, 6, 9, 12, 21, 0, 3, 12]  # в третях: кварк = 1/3 бариона
# Состояние частиц (фиксированные слоты, чтобы индексы не «плыли»).
var alive := PackedByteArray()
var busy := PackedByteArray()
var dying := PackedByteArray()
var kind := PackedInt32Array()
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var spos := PackedVector2Array()    # где частица нарисована на экране (для руки и клика)
var age := PackedFloat32Array()
var fade := PackedFloat32Array()
var depth := PackedFloat32Array()
var birth := PackedFloat64Array()
var counts := PackedInt32Array()
var seen := PackedByteArray()
var _free := PackedInt32Array()

# Свободные частицы, сгруппированные по видам (пересобирается каждый кадр).
var _order := PackedInt32Array()
var _start := PackedInt32Array()
var _avail := PackedInt32Array()

var bonds: Array[Dictionary] = []
var flashes: Array[Dictionary] = []
var streaks: Array[Dictionary] = []
var acc: Dictionary = {}

# Параметры, которые выставляет main по состоянию модели.
var heat := 1.0
var hubble := 0.014
var squeeze := 0.0
var gravity := 0.0
var electron_alpha := 0.0
var atom_dim := 1.0
var n_fraction := 0.5
var n_clock := 0.0
var bottleneck := 0.0
var cosmic_t := 0.0
var flow_t := 0.0
var baryons_target := float(BASE_BARYONS)
var baryons_nominal := float(BASE_BARYONS)

# Камера.
var view := Vector2(1920.0, 1080.0)
var box := view * BOX_SCALE
var cam_center := box * 0.5
var cam_zoom := 1.0
var intro_zoom := 1.0   # < 1 — идёт Большой взрыв, камерой управляет main.gd
var _zoom_target := 1.0
var _cam_target := box * 0.5
var _user_cam_t := 100.0

# Рука.
var hand_screen := Vector2(-1.0e5, -1.0e5)
var hand_mode := 0          # 1 — сжатие, -1 — разрежение
var hand_vel := Vector2.ZERO
var _hand_prev := Vector2.ZERO
var _hand_glow := 0.0
var show_cursor := true
var color_mul := Vector3.ONE   # красное/синее смещение от рычага расширения

# Наблюдение за частицей.
var follow := -1
var follow_log: Array[String] = []
var _was_following := false

# Карта флуктуаций плотности (δ) в координатах мира.
var fluct := PackedFloat32Array()
var fluct_tex: ImageTexture
var _grad_x := PackedFloat32Array()
var _grad_y := PackedFloat32Array()
var _fluct_dirty := true
var _fluct_timer := 0.0

var _electrons_ready := false
var _flicker_acc := 0.0
var _core_mm: MultiMesh
var _halo_mm: MultiMesh
var _flash_mm: MultiMesh
var _ring_mm: MultiMesh
var _core_buf := PackedFloat32Array()
var _halo_buf := PackedFloat32Array()
var _flash_buf := PackedFloat32Array()
var _ring_buf := PackedFloat32Array()


func _ready() -> void:
	var glow := _radial([0.0, 0.1, 0.22, 0.5, 1.0], [1.0, 1.0, 0.4, 0.08, 0.0])
	var ring := _radial([0.0, 0.6, 0.76, 0.84, 1.0], [0.0, 0.0, 0.9, 0.25, 0.0])
	_halo_mm = _make_layer(CAP, ring)
	_core_mm = _make_layer(CAP, glow)
	_ring_mm = _make_layer(MAX_FLASH, ring)
	_flash_mm = _make_layer(MAX_FLASH, glow)
	_core_buf.resize(CAP * FLOATS)
	_halo_buf.resize(CAP * FLOATS)
	_flash_buf.resize(MAX_FLASH * FLOATS)
	_ring_buf.resize(MAX_FLASH * FLOATS)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	fluct.resize(GW * GH)
	_grad_x.resize(GW * GH)
	_grad_y.resize(GW * GH)
	_alloc()
	_seed_fluct()


func _radial(offsets: Array, alphas: Array) -> GradientTexture2D:
	var g := Gradient.new()
	var cols := PackedColorArray()
	for a in alphas:
		# Спад свечения — с поправкой на линейный цвет кадра (экран показывает его в sRGB).
		cols.append(Color(1.0, 1.0, 1.0, pow(a, 1.6)))
	g.offsets = PackedFloat32Array(offsets)
	g.colors = cols
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	return tex


func _make_layer(count: int, tex: Texture2D) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = mm
	mmi.texture = tex
	mmi.self_modulate = Color(gain, gain, gain)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mmi.material = mat
	add_child(mmi)
	return mm


func _alloc() -> void:
	alive.resize(CAP)
	alive.fill(0)
	busy.resize(CAP)
	busy.fill(0)
	dying.resize(CAP)
	dying.fill(0)
	kind.resize(CAP)
	pos.resize(CAP)
	vel.resize(CAP)
	spos.resize(CAP)
	age.resize(CAP)
	fade.resize(CAP)
	depth.resize(CAP)
	birth.resize(CAP)
	_order.resize(CAP)
	counts.resize(KIND_COUNT)
	counts.fill(0)
	_start.resize(KIND_COUNT)
	_avail.resize(KIND_COUNT)
	seen.resize(KIND_COUNT)
	seen.fill(0)
	_free.clear()
	for i in range(CAP - 1, -1, -1):
		_free.append(i)
	bonds.clear()
	flashes.clear()
	streaks.clear()
	acc.clear()
	follow = -1
	follow_log.clear()
	_electrons_ready = false


func _update_view() -> void:
	view = get_viewport_rect().size
	box = view * BOX_SCALE


# ---------------------------------------------------------------- наполнение

## Начало игры: только кварки, по три на будущий барион.
func reset_field() -> void:
	_update_view()
	_alloc()
	_seed_fluct()
	cam_center = box * 0.5
	_cam_target = cam_center
	cam_zoom = 1.0
	_zoom_target = 1.0
	baryons_nominal = baryons_target
	for b in roundi(baryons_target):
		_spawn_triple(_rand_pos(), false)


## Расставить частицы по текущему составу модели (для перемотки).
func rebuild_from(u) -> void:
	_update_view()
	_alloc()
	var total := roundi(baryons_target)
	var nuc := roundi(u.hadron * total)
	for b in total - nuc:
		_spawn_triple(_rand_pos(), false)
	if nuc <= 0:
		return
	var n_d := roundi(u.YD * nuc)
	var n_3 := roundi(u.Y3 * nuc)
	var n_4 := roundi(u.Y4 * nuc)
	var n_7 := roundi(u.Y7 * nuc)
	var n_n := roundi(u.Yn * nuc)
	var n_p := maxi(0, nuc - n_n - 2 * n_d - 3 * n_3 - 4 * n_4 - 7 * n_7)
	var atoms_h := 0
	var atoms_he := 0
	if u.T < 3.0e5:
		atoms_h = roundi((1.0 - u.xH) * n_p)
		atoms_he = roundi((1.0 - u.xHe) * n_4)
	var plan := [[K.P, n_p - atoms_h], [K.H, atoms_h], [K.N, n_n], [K.D, n_d], [K.HE3, n_3],
		[K.HE4, n_4 - atoms_he], [K.HE, atoms_he], [K.LI7, n_7]]
	for item in plan:
		for i in int(item[1]):
			_spawn(int(item[0]), _rand_pos(), _rand_vel(40.0), false)
	if u.T < 2.0e5:
		_ensure_electrons()


## Большой взрыв: частицы рождаются из плазмы не разом, а вразброс за spread секунд.
## Пока возраст отрицательный, частица невидима, потом плавно проявляется.
func stagger_birth(spread: float) -> void:
	for i in CAP:
		if alive[i] == 1:
			age[i] = -randf() * spread
			fade[i] = 0.0


func _spawn_triple(center: Vector2, fade_in: bool) -> void:
	for c in 3:
		_spawn(K.QR + c, center + _rand_vel(30.0), _rand_vel(60.0), false, fade_in)


func _ensure_electrons() -> void:
	_electrons_ready = true
	var charge := 0
	for i in CAP:
		if alive[i] == 1:
			charge += CHARGE[kind[i]]
	for i in maxi(0, charge):
		_spawn(K.E, _rand_pos(), _rand_vel(120.0), false)


func _rand_pos() -> Vector2:
	return Vector2(randf() * box.x, randf() * box.y)


func _rand_vel(speed: float) -> Vector2:
	return Vector2.from_angle(randf() * TAU) * randf() * speed


func _spawn(k: int, p: Vector2, v: Vector2 = Vector2.ZERO, fresh: bool = true, fade_in: bool = false) -> int:
	if _free.is_empty():
		return -1
	var i := _free[_free.size() - 1]
	_free.resize(_free.size() - 1)
	alive[i] = 1
	busy[i] = 0
	dying[i] = 0
	kind[i] = k
	pos[i] = p
	vel[i] = v
	spos[i] = _to_screen(p, 1.0)
	age[i] = 0.0 if fresh else 10.0 + randf() * 10.0
	fade[i] = 0.0 if fade_in else 1.0
	depth[i] = randf_range(0.35, 1.0)
	birth[i] = cosmic_t
	_mark_seen(k, fresh)
	return i


func _mark_seen(k: int, announce: bool) -> void:
	if seen[k] == 0:
		seen[k] = 1
		if announce:
			species_seen.emit(k)


func _kill(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	busy[i] = 0
	dying[i] = 0
	_free.append(i)
	if i == follow:
		follow = -1


# ---------------------------------------------------------------- синхронизация с моделью

func sync(u) -> void:
	var lt := log(u.T) / log(10.0)
	cosmic_t = u.t
	heat = clampf((lt - 2.5) / 10.5, 0.03, 1.0)
	hubble = 0.014 * u.expansion
	squeeze = clampf(1.0 - u.expansion, -1.5, 2.0)
	n_fraction = u.Yn / maxf(u.Yn + u.Yp, 1.0e-9)
	n_clock = clampf(u.t / TAU_N, 0.0, 3.0)
	electron_alpha = clampf((5.3 - lt) / 0.6, 0.0, 1.0)
	if electron_alpha > 0.0 and not _electrons_ready:
		_ensure_electrons()
	atom_dim = clampf((lt - 2.5) / 1.1, 0.16, 1.0)
	# После рекомбинации свет больше не мешает — гравитация начинает собирать вещество.
	# В эпоху вещества контраст сгущений растёт как масштабный фактор: δ ∝ a ∝ 1/T.
	gravity = clampf(0.25 * (2900.0 / u.T - 1.0), 0.0, 1.5)
	baryons_target = BASE_BARYONS * clampf(pow(u.eta_mult, 0.3), 0.5, 1.35)
	# «Узкое горлышко»: дейтроны рождаются и сразу же разбиваются светом.
	bottleneck = 1.0 if (u.T > 9.5e8 and u.T < 4.0e9 and u.hadron > 0.99) else 0.0


func apply_events(ev: Dictionary) -> void:
	for ch in ev.keys():
		acc[ch] = clampf(float(acc.get(ch, 0.0)) + float(ev[ch]) * baryons_nominal, -60.0, 60.0)


# ---------------------------------------------------------------- камера

func _to_screen(p: Vector2, d: float) -> Vector2:
	var k := 0.55 + 0.45 * d
	return view * 0.5 + ((p - box * 0.5) + (box * 0.5 - cam_center) * k) * cam_zoom


func screen_to_world(s: Vector2) -> Vector2:
	return (s - view * 0.5) / cam_zoom + cam_center


func zoom_at(screen: Vector2, factor: float) -> void:
	var before := screen_to_world(screen)
	_zoom_target = clampf(_zoom_target * factor, 1.0, 3.5)
	if follow < 0:
		_cam_target = before - (screen - view * 0.5) / _zoom_target
	_user_cam_t = 0.0


func pan(screen_delta: Vector2) -> void:
	if follow >= 0:
		stop_follow()
	cam_center -= screen_delta / cam_zoom
	_cam_target = cam_center
	_user_cam_t = 0.0


func _update_camera(delta: float) -> void:
	_user_cam_t += delta
	# Большой взрыв: камера смотрит в центр, а масштаб, растущий от точки, ведёт main.gd.
	if intro_zoom < 1.0:
		cam_zoom = intro_zoom
		_zoom_target = 1.0
		cam_center = box * 0.5
		_cam_target = cam_center
		return
	if follow >= 0 and alive[follow] == 1:
		_cam_target = pos[follow]
	elif _user_cam_t > 20.0:
		# Медленное «дыхание» камеры — живой параллакс, когда игрок ничего не трогает.
		var room := (box - view / cam_zoom) * 0.38
		_cam_target = box * 0.5 + Vector2(sin(flow_t * 0.031) * room.x, cos(flow_t * 0.023) * room.y)
	cam_zoom = lerpf(cam_zoom, _zoom_target, 1.0 - exp(-4.0 * delta))
	var half := view * 0.5 / cam_zoom
	_cam_target = _cam_target.clamp(half, box - half)
	cam_center = cam_center.lerp(_cam_target, 1.0 - exp(-(3.0 if follow >= 0 else 1.5) * delta))
	cam_center = cam_center.clamp(half, box - half)


# ---------------------------------------------------------------- наблюдение

func try_pick(screen: Vector2) -> bool:
	var best := -1
	var best_d := 30.0 * 30.0
	for i in CAP:
		if alive[i] == 0 or dying[i] == 1 or fade[i] < 0.3:
			continue
		if kind[i] == K.E and electron_alpha < 0.3:
			continue
		var d := spos[i].distance_squared_to(screen)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		stop_follow()
		return false
	follow = best
	follow_log.clear()
	var born := I18n.t("since_start") if birth[best] < 2.0e-6 else Fmt.duration(birth[best])
	_log_follow("%s — %s: %s" % [born, I18n.t("appeared"), I18n.particle(kind[best])])
	_zoom_target = maxf(_zoom_target, 2.2)
	_user_cam_t = 0.0
	return true


func stop_follow() -> void:
	follow = -1


func followed_kind() -> int:
	return kind[follow] if follow >= 0 else -1


func _log_follow(text: String) -> void:
	follow_log.append(text)
	if follow_log.size() > 7:
		follow_log.pop_front()


func _follow_to(new_index: int, cause: String) -> void:
	if new_index < 0:
		return
	follow = new_index
	_log_follow("%s — %s %s %s" % [Fmt.duration(cosmic_t), I18n.t(cause), Fmt.arrow, I18n.particle(kind[new_index])])


# ---------------------------------------------------------------- рука и флуктуации

func set_hand(screen: Vector2, mode: int) -> void:
	hand_screen = screen
	hand_mode = mode


func _seed_fluct() -> void:
	# Первичные флуктуации (наследие инфляции): слабая волнистая рябь.
	var waves := []
	for w in 6:
		waves.append([randf_range(0.15, 0.6), randf_range(0.15, 0.5), randf() * TAU, randf_range(0.5, 1.0)])
	for y in GH:
		for x in GW:
			var v := 0.0
			for w in waves:
				v += float(w[3]) * sin(x * float(w[0]) + y * float(w[1]) + float(w[2]))
			fluct[y * GW + x] = v * 0.025
	_fluct_dirty = true


func _paint_hand(delta: float) -> void:
	_hand_glow = lerpf(_hand_glow, absf(float(hand_mode)), 1.0 - exp(-6.0 * delta))
	if hand_mode == 0:
		return
	var w := screen_to_world(hand_screen)
	var cx := w.x / box.x * GW
	var cy := w.y / box.y * GH
	var sigma := (HAND_R * 0.55 / cam_zoom) / box.x * GW
	var r := ceili(sigma * 2.5)
	var amount := 0.55 * delta * hand_mode
	for y in range(maxi(0, floori(cy) - r), mini(GH, floori(cy) + r + 1)):
		for x in range(maxi(0, floori(cx) - r), mini(GW, floori(cx) + r + 1)):
			var d2 := (x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy)
			var idx := y * GW + x
			fluct[idx] = clampf(fluct[idx] + amount * exp(-d2 / (2.0 * sigma * sigma)), -1.0, 1.0)
	_fluct_dirty = true


func _update_fluct_texture(delta: float) -> void:
	_fluct_timer -= delta
	if not _fluct_dirty or _fluct_timer > 0.0:
		return
	_fluct_dirty = false
	_fluct_timer = 0.05
	var img := Image.create_from_data(GW, GH, false, Image.FORMAT_RF, fluct.to_byte_array())
	if fluct_tex == null:
		fluct_tex = ImageTexture.create_from_image(img)
	else:
		fluct_tex.update(img)
	for y in GH:
		for x in GW:
			var idx := y * GW + x
			_grad_x[idx] = fluct[y * GW + mini(x + 1, GW - 1)] - fluct[y * GW + maxi(x - 1, 0)]
			_grad_y[idx] = fluct[mini(y + 1, GH - 1) * GW + x] - fluct[maxi(y - 1, 0) * GW + x]


## Сколько заметных сгущений нарисовал игрок (локальные максимумы δ).
func count_clumps() -> int:
	# Сгущение — связная область карты выше порога (не меньше 3 клеток).
	var seen_cell := PackedByteArray()
	seen_cell.resize(GW * GH)
	var n := 0
	for start in GW * GH:
		if seen_cell[start] == 1 or fluct[start] < 0.35:
			continue
		var stack := PackedInt32Array([start])
		seen_cell[start] = 1
		var size := 0
		while not stack.is_empty():
			var c := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			size += 1
			var cx := c % GW
			var cy := c / GW
			for nb in [[cx - 1, cy], [cx + 1, cy], [cx, cy - 1], [cx, cy + 1]]:
				var x: int = nb[0]
				var y: int = nb[1]
				if x < 0 or y < 0 or x >= GW or y >= GH:
					continue
				var i := y * GW + x
				if seen_cell[i] == 0 and fluct[i] >= 0.35:
					seen_cell[i] = 1
					stack.append(i)
		if size >= 3:
			n += 1
	return n


# ---------------------------------------------------------------- кадр

func _process(delta: float) -> void:
	_update_view()
	flow_t += delta * (0.25 + 0.75 * heat)
	if delta > 0.0:
		hand_vel = hand_vel.lerp((hand_screen - _hand_prev) / delta, 0.25).limit_length(2500.0)
	_hand_prev = hand_screen
	_update_camera(delta)
	_rebuild_lists()
	_adjust_population(delta)
	_run_reactions()
	_update_bonds(delta)
	_update_flicker(delta)
	_paint_hand(delta)
	_update_fluct_texture(delta)
	_move_and_draw(delta)
	_update_flashes(delta)
	var following := follow >= 0
	if following != _was_following:
		_was_following = following
		follow_changed.emit(following)
	queue_redraw()


func _rebuild_lists() -> void:
	counts.fill(0)
	_avail.fill(0)
	for i in CAP:
		if alive[i] == 1 and dying[i] == 0:
			var k := kind[i]
			counts[k] += 1
			if busy[i] == 0:
				_avail[k] += 1
	var s := 0
	for k in KIND_COUNT:
		_start[k] = s
		s += _avail[k]
	var fill := _start.duplicate()
	for i in CAP:
		if alive[i] == 1 and busy[i] == 0:
			var k := kind[i]
			_order[fill[k]] = i
			fill[k] += 1


func _valid(i: int, k: int) -> bool:
	return alive[i] == 1 and busy[i] == 0 and kind[i] == k


func _pick(k: int) -> int:
	var n := _avail[k]
	if n == 0:
		return -1
	# Пока игрок сжимает плазму, реакции охотнее случаются у него под рукой.
	if hand_mode > 0 and randf() < 0.65:
		var near := _nearest(k, screen_to_world(hand_screen))
		if near >= 0 and spos[near].distance_squared_to(hand_screen) < HAND_R * HAND_R * 2.0:
			return near
	for s in 16:
		var i := _order[_start[k] + randi() % n]
		if _valid(i, k):
			return i
	return -1


func _nearest(k: int, from: Vector2) -> int:
	var n := _avail[k]
	if n == 0:
		return -1
	var best := -1
	var best_d := INF
	var tries := mini(n, 40)
	for s in tries:
		var i := _order[_start[k] + (s if n <= 40 else randi() % n)]
		if not _valid(i, k):
			continue
		var d := pos[i].distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = i
	return best


# Плотность вещества меняет число частиц на экране: плавно добавляем или убираем.
func _adjust_population(delta: float) -> void:
	baryons_nominal = lerpf(baryons_nominal, baryons_target, 1.0 - exp(-0.8 * delta))
	var thirds := 0
	for k in KIND_COUNT:
		thirds += counts[k] * BARYON[k]
	var diff := baryons_nominal - thirds / 3.0
	if absf(diff) < 8.0:
		return
	for n in mini(int(absf(diff) / 4.0) + 1, 5):
		if diff > 0.0:
			_clone_random()
		else:
			_remove_random()


func _random_baryonic() -> int:
	for t in 24:
		var i := randi() % CAP
		if alive[i] == 1 and busy[i] == 0 and kind[i] != K.E and i != follow:
			return i
	return -1


func _clone_random() -> void:
	var i := _random_baryonic()
	if i < 0:
		return
	var k := kind[i]
	var p := _rand_pos()
	if k <= K.QB:
		_spawn_triple(p, true)
		return
	_spawn(k, p, _rand_vel(40.0), false, true)
	if _electrons_ready:
		for c in maxi(0, CHARGE[k]):
			_spawn(K.E, p + _rand_vel(40.0), _rand_vel(120.0), false, true)


func _remove_random() -> void:
	var i := _random_baryonic()
	if i < 0:
		return
	var k := kind[i]
	if k <= K.QB:
		for c in 3:
			_fade_out(_pick(K.QR + c))
		return
	_fade_out(i)
	if _electrons_ready:
		for c in maxi(0, CHARGE[k]):
			_fade_out(_pick(K.E))


func _fade_out(i: int) -> void:
	if i < 0 or i == follow:
		return
	busy[i] = 1
	dying[i] = 1


func _run_reactions() -> void:
	var budget := MAX_ANIM_PER_FRAME
	for ch in acc.keys():
		var a: float = acc[ch]
		var guard := 0
		while a >= 1.0 and guard < 80:
			guard += 1
			if not _react(ch, 1, budget <= 0):
				break
			a -= 1.0
			budget -= 1
		while a <= -1.0 and guard < 80:
			guard += 1
			if not _react(ch, -1, budget <= 0):
				break
			a += 1.0
			budget -= 1
		acc[ch] = a


func _react(ch: String, dir: int, instant: bool) -> bool:
	match ch:
		"hadron":
			if dir > 0:
				var product := K.N if randf() < n_fraction else K.P
				return _bond([K.QR, K.QG, K.QB], product, -1, Color(1.7, 1.4, 2.4), 0, ch, instant, "c_quarks")
			return _split([K.P, K.N] if randf() < 0.5 else [K.N, K.P], [K.QR, K.QG, K.QB], Color(1.5, 1.2, 2.6), ch, "c_melted")
		"n_to_p":
			if dir > 0:
				return _transmute(K.N, K.P, Color(0.6, 1.2, 2.0), true)
			return _transmute(K.P, K.N, Color(1.2, 1.0, 1.8), false)
		"pn_D":
			if dir > 0:
				return _bond([K.N, K.P], K.D, -1, Color(0.9, 2.0, 2.4), 1, ch, instant, "c_fusion")
			return _split([K.D], [K.P, K.N], Color(1.5, 1.8, 2.6), ch, "c_photo")
		# Ядра с A = 3 на экране одного вида: тритий показан как гелий-3 (потом он им и станет).
		"DDn":
			return _bond([K.D, K.D], K.HE3, K.N, Color(1.8, 1.4, 2.6), 1, ch, instant, "c_fusion")
		"DDp":
			return _bond([K.D, K.D], K.HE3, K.P, Color(1.8, 1.4, 2.6), 1, ch, instant, "c_fusion")
		"Dp":
			return _bond([K.D, K.P], K.HE3, -1, Color(1.8, 1.4, 2.6), 1, ch, instant, "c_fusion")
		"Dn":
			return _bond([K.D, K.N], K.HE3, -1, Color(1.8, 1.4, 2.6), 1, ch, instant, "c_fusion")
		"He3n":
			return _bond([K.HE3, K.N], K.HE3, K.P, Color(1.4, 1.3, 2.4), 1, ch, instant, "c_fusion")
		"A3Dn":
			return _bond([K.HE3, K.D], K.HE4, K.N, Color(3.6, 2.6, 1.0), 2, ch, instant, "c_fusion")
		"A3Dp":
			return _bond([K.HE3, K.D], K.HE4, K.P, Color(3.6, 2.6, 1.0), 2, ch, instant, "c_fusion")
		"A3n":
			return _bond([K.HE3, K.N], K.HE4, -1, Color(3.6, 2.6, 1.0), 2, ch, instant, "c_fusion")
		"A3p":
			return _bond([K.HE3, K.P], K.HE4, -1, Color(3.6, 2.6, 1.0), 2, ch, instant, "c_fusion")
		"Li":
			return _bond([K.HE4, K.HE3], K.LI7, -1, Color(3.2, 0.8, 1.4), 2, ch, instant, "c_fusion")
		"He_melt":
			return _split([K.HE4], [K.P, K.P, K.N, K.N], Color(2.6, 2.0, 1.2), ch, "c_broke")
		"A3_melt":
			return _split([K.HE3], [K.P, K.P, K.N], Color(2.0, 1.5, 2.4), ch, "c_broke")
		"Li_melt":
			return _split([K.LI7], [K.P, K.P, K.P, K.N, K.N, K.N, K.N], Color(2.6, 1.0, 1.4), ch, "c_broke")
		"recH":
			if dir > 0:
				return _bond([K.P, K.E], K.H, -1, Color(3.0, 0.45, 0.55), 1, ch, instant, "c_capture")
			return _split([K.H], [K.P, K.E], Color(1.0, 0.7, 1.8), ch, "c_ionized")
		"recHe":
			if dir > 0:
				return _bond([K.HE4, K.E, K.E], K.HE, -1, Color(2.8, 2.3, 0.7), 1, ch, instant, "c_capture2")
			return _split([K.HE], [K.HE4, K.E, K.E], Color(1.6, 1.4, 2.0), ch, "c_ionized")
	return false


## Слияние: участники стягиваются к общему центру, затем рождается продукт.
func _bond(kinds: Array, product: int, extra: int, col: Color, size_class: int, ch: String, instant: bool, cause: String) -> bool:
	var first := _pick(kinds[0])
	if first < 0:
		return false
	var members := PackedInt32Array([first])
	busy[first] = 1
	for j in range(1, kinds.size()):
		var m := _nearest(kinds[j], pos[first])
		if m < 0:
			for x in members:
				busy[x] = 0
			return false
		busy[m] = 1
		members.append(m)
	var center := Vector2.ZERO
	for x in members:
		center += pos[x]
	center /= members.size()
	var b := {"m": members, "c": center, "t": 0.0, "dur": randf_range(0.45, 0.85), "product": product,
		"extra": extra, "col": col, "size": size_class, "ch": ch, "d": depth[first], "cause": cause}
	if instant:
		_finish_bond(b, false)
	else:
		bonds.append(b)
	return true


func _finish_bond(b: Dictionary, animated: bool) -> void:
	var members: PackedInt32Array = b["m"]
	var center: Vector2 = b["c"]
	var followed := members.has(follow) and follow >= 0
	var v := Vector2.ZERO
	for x in members:
		v += vel[x]
		_kill(x)
	v /= members.size()
	var prod := _spawn(int(b["product"]), center, v * 0.5)
	if prod >= 0:
		depth[prod] = b["d"]
	var extra: int = b["extra"]
	if extra >= 0:
		var dir := Vector2.from_angle(randf() * TAU)
		var e := _spawn(extra, center + dir * 6.0, dir * randf_range(90.0, 160.0))
		if e >= 0:
			depth[e] = b["d"]
	if followed:
		_follow_to(prod, String(b["cause"]))
	if not animated:
		return
	var sc: int = b["size"]
	var col: Color = b["col"]
	var d: float = b["d"]
	_flash(center, col, 30.0 + 26.0 * sc, 0.55 + 0.4 * sc, false, d)
	if sc >= 1:
		_flash(center, col * 0.6, 34.0 + 46.0 * sc, 1.0 + 0.5 * sc, true, d)
	if sc >= 2:
		_gamma(center, col, 3, d)
	reaction_shown.emit(String(b["ch"]), center)


## Распад: частица разлетается на осколки.
func _split(sources: Array, products: Array, col: Color, ch: String, cause: String) -> bool:
	var src := -1
	for k in sources:
		src = _pick(k)
		if src >= 0:
			break
	if src < 0:
		return false
	var c := pos[src]
	var v := vel[src]
	var d := depth[src]
	var followed := src == follow
	_kill(src)
	var first := -1
	for pk in products:
		var dir := Vector2.from_angle(randf() * TAU)
		var i := _spawn(int(pk), c + dir * 4.0, v + dir * randf_range(60.0, 130.0))
		if i >= 0:
			depth[i] = d
			if first < 0:
				first = i
	if followed:
		_follow_to(first, cause)
	_flash(c, col, 34.0, 0.5, false, d)
	reaction_shown.emit(ch + "_split", c)
	return true


## Превращение одной частицы в другую (бета-распад нейтрона и обратный процесс).
func _transmute(from: int, to: int, col: Color, beta: bool) -> bool:
	var i := _pick(from)
	if i < 0:
		return false
	kind[i] = to
	age[i] = 0.0
	_mark_seen(to, true)
	if i == follow:
		_log_follow("%s — %s %s %s" % [Fmt.duration(cosmic_t), I18n.t("c_beta" if beta else "c_positron"), Fmt.arrow, I18n.particle(to)])
	_flash(pos[i], col, 20.0, 0.4, false, depth[i])
	if beta:
		_streak(pos[i], Vector2.from_angle(randf() * TAU), Color(0.5, 1.3, 2.2), 0.7, 170.0, 40.0, depth[i])
	reaction_shown.emit("n_to_p" if beta else "p_to_n", pos[i])
	return true


func _update_bonds(delta: float) -> void:
	var k := 1.0 - exp(-7.0 * delta)
	for bi in range(bonds.size() - 1, -1, -1):
		var b := bonds[bi]
		var t: float = b["t"] + delta
		b["t"] = t
		var members: PackedInt32Array = b["m"]
		var c: Vector2 = b["c"]
		for x in members:
			pos[x] = pos[x].lerp(c, k)
			vel[x] *= 0.85
		if t >= float(b["dur"]):
			bonds.remove_at(bi)
			_finish_bond(b, true)


# Косметика «узкого горлышка»: мимолётные дейтроны, которые тут же разбивает свет.
func _update_flicker(delta: float) -> void:
	if bottleneck <= 0.0:
		return
	_flicker_acc += delta * (7.0 + 10.0 * _hand_glow) * bottleneck
	while _flicker_acc >= 1.0:
		_flicker_acc -= 1.0
		var n := _pick(K.N)
		if n < 0:
			return
		var p := _nearest(K.P, pos[n])
		if p < 0:
			return
		var c := (pos[n] + pos[p]) * 0.5
		_flash(c, Color(0.8, 1.7, 2.2), 22.0, 0.35, false, depth[n])
		_streak(c, Vector2.from_angle(randf() * TAU), Color(1.6, 1.6, 2.4), 0.45, 520.0, 60.0, depth[n])
		reaction_shown.emit("flicker", c)


func _move_and_draw(delta: float) -> void:
	var jitter := 30.0 + 170.0 * heat
	var flow := 16.0 + 34.0 * heat
	var damp := pow(0.45, delta)
	var t := flow_t
	var bc := box * 0.5
	var hub := hubble
	var hs := hand_screen
	var hm := hand_mode
	var hr2 := HAND_R * HAND_R
	var hv := hand_vel
	var inv_zoom := 1.0 / cam_zoom
	var grav := gravity * 170.0
	var size_zoom := pow(cam_zoom, 0.75)
	var glow_boost := 1.0 + 0.12 * squeeze
	var n_tick := 3.0 + 14.0 * n_clock
	var margin := 80.0 * cam_zoom
	var cm := color_mul
	var j := 0
	var hj := 0
	for i in CAP:
		if alive[i] == 0:
			continue
		var p := pos[i]
		var v := vel[i]
		var d := depth[i]

		# Рука: сжатие с закруткой, разрежение, размешивание.
		var touch := 0.0
		if hm != 0:
			var dv := hs - spos[i]
			var d2 := dv.length_squared()
			if d2 < hr2 and d2 > 1.0:
				var dist := sqrt(d2)
				touch = 1.0 - dist / HAND_R
				var dir := dv / dist
				if hm > 0:
					v += (dir * 380.0 + Vector2(-dir.y, dir.x) * 240.0 + hv * 1.3) * touch * delta * inv_zoom
					v += Vector2(randf() - 0.5, randf() - 0.5) * 260.0 * touch * delta
				else:
					v -= (dir * 460.0 - hv * 0.6) * touch * delta * inv_zoom

		# Тёмные века: вещество скатывается в сгущения.
		var cell := clampi(int(p.y / box.y * GH), 0, GH - 1) * GW + clampi(int(p.x / box.x * GW), 0, GW - 1)
		if grav > 0.0:
			v += Vector2(_grad_x[cell], _grad_y[cell]) * grav * delta

		# Вихревое течение (ротор функции тока) + тепловое дрожание.
		var ax := p.x * 0.0029 + t * 0.21
		var by := p.y * 0.0031 - t * 0.17
		var cc := cos((p.x + p.y) * 0.0021 - t * 0.13) * 0.6
		var fx := sin(ax) * cos(by) + cc
		var fy := -(cos(ax) * sin(by) + cc)
		v += Vector2((randf() - 0.5) * jitter, (randf() - 0.5) * jitter) * delta
		v *= damp
		p += (v + Vector2(fx, fy) * flow) * delta * (0.4 + 0.6 * d)

		# Поток Хаббла: всё разбегается от всего. Ушедшие за край заменяются
		# частицами из «нового пространства», при сжатии — наоборот.
		var drifts := busy[i] == 0 and i != follow
		if drifts:
			p += (p - bc) * hub * delta
		if p.x < 0.0 or p.x > box.x or p.y < 0.0 or p.y > box.y:
			if drifts and hub > 0.0005:
				p = _rand_pos()
				fade[i] = 0.0
			else:
				p.x = fposmod(p.x, box.x)
				p.y = fposmod(p.y, box.y)
		elif drifts and hub < -0.0005 and (p - bc).length_squared() < 4900.0:
			p = Vector2(randf() * box.x, 0.0 if randf() < 0.5 else box.y)
			fade[i] = 0.0
		pos[i] = p
		vel[i] = v

		var f := fade[i]
		if dying[i] == 1:
			f -= delta * 1.6
			if f <= 0.0:
				_kill(i)
				continue
		elif f < 1.0:
			f = minf(1.0, f + delta * 1.2)
		fade[i] = f
		var a := age[i] + delta
		age[i] = a
		if a < 0.0:
			fade[i] = 0.0
			continue   # ещё не родилась (stagger_birth)

		var sp := _to_screen(p, d)
		spos[i] = sp
		if sp.x < -margin or sp.y < -margin or sp.x > view.x + margin or sp.y > view.y + margin:
			continue

		var k := kind[i]
		var bright := (0.35 + 0.65 * d) * (1.0 + 2.5 * exp(-a * 3.0)) * f * glow_boost
		bright *= 1.0 + 0.9 * touch * (1.0 if hm > 0 else 0.0)
		if busy[i] == 1 and dying[i] == 0:
			bright *= 1.6
		match k:
			K.E:
				bright *= electron_alpha
				if bright < 0.01:
					continue
			K.H, K.HE:
				bright *= atom_dim * (1.0 + maxf(fluct[cell], 0.0) * gravity * 1.5)
			K.N:
				# Часы распада: чем дольше живёт нейтрон, тем тревожнее мерцает.
				bright *= 0.8 + 0.2 * sin(t * n_tick + float(i))
		bright *= 0.85 + 0.15 * sin(t * 2.3 + float(i))
		var base_col: Color = COLORS[k]
		var col := Color(base_col.r * cm.x, base_col.g * cm.y, base_col.b * cm.z)
		var s: float = SIZES[k] * 4.0 * (0.55 + 0.45 * d) * (1.0 + 1.2 * exp(-a * 5.0)) * size_zoom
		_write(_core_buf, j, sp, s, col.r * bright, col.g * bright, col.b * bright, 1.0)
		j += 1
		if k == K.HE4 or k == K.LI7 or k == K.H or k == K.HE:
			var atom := k == K.H or k == K.HE
			var hsz := s * (1.12 if atom else 1.1) / sqrt(size_zoom)
			var hb := bright * (0.05 if atom else 0.07)
			_write(_halo_buf, hj, sp, hsz, col.r * hb, col.g * hb, col.b * hb, 1.0)
			hj += 1
	_core_mm.buffer = _core_buf
	_core_mm.visible_instance_count = j
	_halo_mm.buffer = _halo_buf
	_halo_mm.visible_instance_count = hj


static func _write(buf: PackedFloat32Array, idx: int, p: Vector2, s: float, r: float, g: float, b: float, a: float) -> void:
	var o := idx * FLOATS
	buf[o] = s
	buf[o + 1] = 0.0
	buf[o + 2] = 0.0
	buf[o + 3] = p.x
	buf[o + 4] = 0.0
	buf[o + 5] = s
	buf[o + 6] = 0.0
	buf[o + 7] = p.y
	buf[o + 8] = r
	buf[o + 9] = g
	buf[o + 10] = b
	buf[o + 11] = a


# ---------------------------------------------------------------- вспышки и гамма-кванты

func _flash(p: Vector2, col: Color, size: float, life: float, ring: bool = false, d: float = 1.0) -> void:
	if flashes.size() >= MAX_FLASH:
		flashes.remove_at(0)
	flashes.append({"p": p, "c": col, "s": size, "life": life, "age": 0.0, "ring": ring, "d": d})


func _gamma(p: Vector2, col: Color, n: int, d: float) -> void:
	for i in n:
		_streak(p, Vector2.from_angle(randf() * TAU), col, 0.8, 620.0, 90.0, d)


func _streak(p: Vector2, dir: Vector2, col: Color, life: float, speed: float, length: float, d: float) -> void:
	if streaks.size() > 80:
		streaks.remove_at(0)
	streaks.append({"p": p, "dir": dir, "c": col, "life": life, "age": 0.0, "speed": speed, "len": length, "d": d})


func _update_flashes(delta: float) -> void:
	var fj := 0
	var rj := 0
	var size_zoom := pow(cam_zoom, 0.4)
	for fi in range(flashes.size() - 1, -1, -1):
		var f := flashes[fi]
		var a: float = f["age"] + delta
		var life: float = f["life"]
		if a >= life:
			flashes.remove_at(fi)
			continue
		f["age"] = a
		var x := a / life
		var col: Color = f["c"]
		var p := _to_screen(f["p"], f["d"])
		var size: float = f["s"] * size_zoom
		var fade_out := (1.0 - x) * (1.0 - x)
		if f["ring"]:
			var rs := size * (0.3 + 1.6 * (1.0 - pow(1.0 - x, 3.0)))
			var rb := fade_out * 0.45
			_write(_ring_buf, rj, p, rs, col.r * rb, col.g * rb, col.b * rb, 1.0)
			rj += 1
		else:
			var fs := size * (0.6 + 0.9 * sqrt(x))
			var fb := fade_out * 1.8
			_write(_flash_buf, fj, p, fs, col.r * fb, col.g * fb, col.b * fb, 1.0)
			fj += 1
	_flash_mm.buffer = _flash_buf
	_flash_mm.visible_instance_count = fj
	_ring_mm.buffer = _ring_buf
	_ring_mm.visible_instance_count = rj

	for si in range(streaks.size() - 1, -1, -1):
		var s := streaks[si]
		var a: float = s["age"] + delta
		if a >= float(s["life"]):
			streaks.remove_at(si)
		else:
			s["age"] = a


func _draw() -> void:
	for s in streaks:
		var a: float = s["age"]
		var p: Vector2 = s["p"]
		var dir: Vector2 = s["dir"]
		var d: float = s["d"]
		var zs := 1.0 / sqrt(cam_zoom)
		var travelled: float = float(s["speed"]) * a * zs
		var head := _to_screen(p + dir * travelled, d)
		var tail := _to_screen(p + dir * maxf(0.0, travelled - float(s["len"]) * zs), d)
		var fd := (1.0 - a / float(s["life"])) * 0.8
		var col: Color = s["c"]
		draw_line(tail, head, Color(col.r * fd, col.g * fd, col.b * fd, 1.0), 1.6, true)

	# Рука: тёплое кольцо при сжатии, холодное при разрежении.
	if _hand_glow > 0.02 and show_cursor:
		var warm := hand_mode >= 0
		var c := Color(1.6, 1.1, 0.6) if warm else Color(0.5, 0.9, 1.8)
		var pulse := 0.85 + 0.15 * sin(flow_t * 6.0)
		for k in 6:
			draw_circle(hand_screen, HAND_R * (0.25 + 0.12 * k), c * (0.035 * _hand_glow))
		draw_arc(hand_screen, HAND_R * 0.62 * pulse, 0.0, TAU, 72, c * (0.8 * _hand_glow), 2.0, true)
		draw_arc(hand_screen, HAND_R * 0.95, 0.0, TAU, 72, c * (0.3 * _hand_glow), 1.2, true)

	# Наблюдаемая частица — тонкое кольцо.
	if follow >= 0 and alive[follow] == 1:
		var r := 16.0 + 3.0 * sin(flow_t * 3.0)
		draw_arc(spos[follow], r * pow(cam_zoom, 0.6), 0.0, TAU, 48, Color(1.0, 0.85, 0.6, 0.8), 1.5, true)
