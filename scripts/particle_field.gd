extends Node2D
## Видимые частицы, камера и «рука» игрока.
##
## The screen shows a sample of the physics model: about 1000 baryons, scaled
## by matter density. Model events drive animations; the current model state
## determines the sample composition. Periodic reconciliation corrects rounding,
## isotope grouping and animations skipped during large steps.
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
signal follow_ended

const Fmt := preload("res://scripts/fmt.gd")
const I18n := preload("res://scripts/i18n.gd")
const Structure := preload("res://scripts/structure.gd")
const Chemistry := preload("res://scripts/particle_chemistry.gd")
const UniverseModel := preload("res://scripts/universe.gd")

const K = Chemistry.K

const KIND_COUNT := Chemistry.KIND_COUNT
const CAP := 5200
const BASE_BARYONS := 1000
const MAX_FLASH := 192
const MAX_ANIM_PER_FRAME := 10
const MAX_REACTIONS_PER_FRAME := 80
const RECONCILE_INTERVAL := 0.5
const CORRECTIONS_PER_SECOND := 2400.0
const MAX_CORRECTIONS_PER_FRAME := 128
const MAX_PENDING_EVENTS := 5200.0
const FLOATS := 12  # 8 на Transform2D + 4 на цвет

## Множитель яркости всех частиц. В браузере кадр не хранит яркость выше 1,
## поэтому там main.gd уменьшает её здесь и возвращает в конце кадра.
static var gain := 1.0
const BOX_SCALE := 1.2
const GW := 64
const GH := 36
const HAND_R := 150.0
const TAU_N := UniverseModel.TAU_N

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
const CHARGE = Chemistry.CHARGE
const BARYON = Chemistry.BARYON
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
var _reconcile_timer := RECONCILE_INTERVAL
var _reconciling := false
var _resync_requested := false
var reconciliations := 0
var event_overflows := 0
var invalid_events := 0
var _reaction_cursor := 0

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
var fluct := PackedFloat32Array()     # что видно на карте сгущений (см. Structure.visible)
var structure                        # рост сгущений: тёмная материя и барионы по клеткам
var _struct_u = null                 # модель Вселенной, по которой растут сгущения
var _struct_t := -1.0                # космическое время последнего шага роста
var fluct_tex: ImageTexture
var _grad_x := PackedFloat32Array()
var _grad_y := PackedFloat32Array()
var _fluct_dirty := true
var _fluct_timer := 0.0

var _flicker_acc := 0.0
var _core_mm: MultiMesh
var _halo_mm: MultiMesh
var _flash_mm: MultiMesh
var _ring_mm: MultiMesh
var _core_buf := PackedFloat32Array()
# sin(i) и cos(i) по номеру слота: мерцание sin(ωt + i) = sin ωt·cos i + cos ωt·sin i.
var _phase_s := PackedFloat32Array()
var _phase_c := PackedFloat32Array()
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
	_phase_s.resize(CAP)
	_phase_c.resize(CAP)
	for i in CAP:
		_phase_s[i] = sin(float(i))
		_phase_c[i] = cos(float(i))
	_halo_buf.resize(CAP * FLOATS)
	_flash_buf.resize(MAX_FLASH * FLOATS)
	_ring_buf.resize(MAX_FLASH * FLOATS)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	fluct.resize(GW * GH)
	_grad_x.resize(GW * GH)
	_grad_y.resize(GW * GH)
	structure = Structure.new(GW * GH)
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
	_reconcile_timer = RECONCILE_INTERVAL
	_reconciling = false
	_resync_requested = false
	reconciliations = 0
	event_overflows = 0
	invalid_events = 0
	_reaction_cursor = 0
	follow = -1
	follow_log.clear()


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
	sync(u)
	baryons_nominal = baryons_target
	var target := Chemistry.sample(u, roundi(baryons_nominal))
	for k in KIND_COUNT:
		for i in target[k]:
			_spawn(k, _rand_pos(), _rand_vel(40.0), false)
	_rebuild_lists()


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
	atom_dim = clampf((lt - 2.5) / 1.1, 0.16, 1.0)
	# Сгущения растут по structure.gd; здесь — только то, насколько вещество уже
	# свободно от света и частицы могут стекаться к сгущениям.
	_struct_u = u
	gravity = 1.2 * (1.0 - structure.coupling)
	baryons_target = BASE_BARYONS * clampf(pow(u.eta_mult, 0.3), 0.5, 1.35)
	# «Узкое горлышко»: дейтроны рождаются и сразу же разбиваются светом.
	bottleneck = 1.0 if (u.T > 9.5e8 and u.T < 4.0e9 and u.hadron > 0.99) else 0.0


func apply_events(ev: Dictionary) -> void:
	for ch in ev.keys():
		if ch not in ["hadron", "n_to_p"] and not Chemistry.RULES.has(ch):
			invalid_events += 1
			push_error("Unknown visual reaction: " + str(ch))
			continue
		var amount := float(ev[ch]) * baryons_nominal
		if not is_finite(amount):
			invalid_events += 1
			push_error("Non-finite visual reaction: " + str(ch))
			continue
		if _resync_requested:
			continue # the current model snapshot supersedes this animation backlog
		var pending := float(acc.get(ch, 0.0)) + amount
		if absf(pending) > MAX_PENDING_EVENTS:
			event_overflows += 1
			_resync_requested = true
			acc.clear()
		else:
			acc[ch] = pending


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
	structure.reset()
	for i in GW * GH:
		structure.add(i, fluct[i])
	_struct_t = -1.0
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
			structure.add(idx, amount * exp(-d2 / (2.0 * sigma * sigma)), 1.0)
			fluct[idx] = clampf(structure.visible(idx), -1.0, 1.0)
	_fluct_dirty = true


func _update_fluct_texture(delta: float) -> void:
	_fluct_timer -= delta
	if _fluct_timer > 0.0:
		return
	_fluct_timer = 0.05
	if _struct_u != null:
		var t: float = _struct_u.t
		if _struct_t >= 0.0 and t > _struct_t and structure.step(_struct_u, t - _struct_t):
			for i in GW * GH:
				fluct[i] = clampf(structure.visible(i), -1.0, 1.0)
			_fluct_dirty = true
		_struct_t = t
	if not _fluct_dirty:
		return
	_fluct_dirty = false
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


## Сколько сгущений вещества с контрастом не меньше threshold (связные области карты).
## 0,35 — заметное сгущение, 1 — уже схлопнулось в облако.
func count_clumps(threshold := 0.35) -> int:
	# Сгущение — связная область карты выше порога (не меньше 3 клеток).
	var seen_cell := PackedByteArray()
	seen_cell.resize(GW * GH)
	var n := 0
	for start in GW * GH:
		if seen_cell[start] == 1 or structure.matter(start) < threshold:
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
				if seen_cell[i] == 0 and structure.matter(i) >= threshold:
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
	step_chemistry(delta)
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
	for i in CAP:
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
	if best < 0:
		return _pick(k)
	return best


## The rendering clock only controls how quickly a finite sample catches up.
## Finish in-flight bonds before rebasing, then clear events represented by that
## snapshot. No chemistry is inferred from random cloning or frame frequency.
func step_chemistry(delta: float) -> void:
	_update_bonds(delta)
	_rebuild_lists()
	baryons_nominal = lerpf(baryons_nominal, baryons_target, 1.0 - exp(-0.8 * delta))
	_reconcile_timer -= delta
	if _struct_u != null and (_reconciling or _resync_requested or _reconcile_timer <= 0.0):
		_reconciling = true
		if not bonds.is_empty():
			return
		acc.clear()
		var target := Chemistry.sample(_struct_u, roundi(baryons_nominal))
		var budget := clampi(ceili(CORRECTIONS_PER_SECOND * delta), 1, MAX_CORRECTIONS_PER_FRAME)
		_reconcile_sample(target, budget)
		if counts == target:
			_reconciling = false
			_resync_requested = false
			_reconcile_timer = RECONCILE_INTERVAL
			reconciliations += 1
		return
	_run_reactions()


func _reconcile_sample(target: PackedInt32Array, budget: int) -> void:
	# Keep every unaffected slot, especially the particle being followed. A
	# representative absent from the new sample ends observation explicitly;
	# resampling must never invent a reaction in its history.
	for k in KIND_COUNT:
		if counts[k] <= target[k]:
			continue
		for i in range(CAP - 1, -1, -1):
			if budget == 0 or counts[k] <= target[k]:
				break
			if alive[i] == 1 and busy[i] == 0 and kind[i] == k and i != follow:
				_kill(i)
				counts[k] -= 1
				budget -= 1
		if budget > 0 and counts[k] > target[k] and follow >= 0 and kind[follow] == k:
			_kill(follow)
			counts[k] -= 1
			budget -= 1
			follow_ended.emit()
	for k in KIND_COUNT:
		while counts[k] < target[k] and budget > 0 and not _free.is_empty():
			_spawn(k, _rand_pos(), _rand_vel(40.0), true, true)
			counts[k] += 1
			budget -= 1


func _run_reactions() -> void:
	var channels := acc.keys()
	if channels.is_empty():
		return
	var budget := MAX_ANIM_PER_FRAME
	var stalled := 0
	# A global work bound and round-robin scheduling prevent a hot channel from
	# starving the others. Unfinished work is kept until executed or rebased.
	for operation in MAX_REACTIONS_PER_FRAME:
		_reaction_cursor %= channels.size()
		var ch: String = channels[_reaction_cursor]
		_reaction_cursor += 1
		var amount: float = acc[ch]
		if absf(amount) >= 1.0 and _react(ch, 1 if amount > 0.0 else -1, budget <= 0):
			acc[ch] = amount - signf(amount)
			budget -= 1
			stalled = 0
		else:
			stalled += 1
			if stalled >= channels.size():
				break


func _react(ch: String, direction: int, instant: bool) -> bool:
	var pair: Array
	if ch == "hadron":
		var nucleon := K.N if randf() < n_fraction else K.P
		if direction < 0 and _pick(nucleon) < 0:
			nucleon = K.P if nucleon == K.N else K.N
		pair = [[K.QR, K.QG, K.QB], [nucleon]]
		if direction < 0:
			pair = [pair[1], pair[0]]
	elif ch == "n_to_p":
		pair = [[K.N], [K.P]] if direction > 0 else [[K.P], [K.N]]
	else:
		pair = Chemistry.rule(ch, direction)
	if pair.is_empty():
		return false
	var inputs: Array = pair[0]
	var outputs: Array = pair[1]
	# Capacity is checked BEFORE consuming anything, including a followed source.
	if _free.size() + inputs.size() < outputs.size():
		return false
	var members := PackedInt32Array()
	for k in inputs:
		var index := _pick(k) if members.is_empty() else _nearest(k, pos[members[0]])
		if index < 0:
			for reserved in members:
				busy[reserved] = 0
			return false
		busy[index] = 1
		members.append(index)
	var center := Vector2.ZERO
	for index in members:
		center += pos[index]
	center /= members.size()
	var style := _reaction_style(ch, direction)
	var bond := {"m": members, "c": center, "t": 0.0, "dur": randf_range(0.45, 0.85),
		"out": outputs, "col": style[0], "size": style[1], "cause": style[2],
		"ch": ch if direction > 0 and not ch.ends_with("_melt") else ch + "_split", "d": depth[members[0]]}
	if instant or inputs.size() == 1 or outputs.size() > inputs.size():
		_finish_bond(bond, not instant)
	else:
		bonds.append(bond)
	return true


func _reaction_style(ch: String, direction: int) -> Array:
	var col := Color(1.8, 1.4, 2.6)
	var size := 1
	var cause := "c_nuclear"
	if ch in ["pn_D", "Dp", "Dn", "A3n", "A3p", "Li"]:
		cause = "c_fusion" if direction > 0 else "c_photo"
	elif direction > 0 and ch in ["DDn", "DDp", "A3Dn", "A3Dp", "He3He3"]:
		cause = "c_fusion"
	match ch:
		"hadron":
			col = Color(1.7, 1.4, 2.4) if direction > 0 else Color(1.5, 1.2, 2.6)
			size = 0
			cause = "c_quarks" if direction > 0 else "c_melted"
		"n_to_p":
			col = Color(0.6, 1.2, 2.0) if direction > 0 else Color(1.2, 1.0, 1.8)
			size = 0
			cause = "c_weak"
		"pn_D":
			col = Color(0.9, 2.0, 2.4) if direction > 0 else Color(1.5, 1.8, 2.6)
		"He3n":
			col = Color(1.4, 1.3, 2.4)
		"A3Dn", "A3Dp", "A3n", "A3p":
			col = Color(3.6, 2.6, 1.0)
			size = 2
		"Li":
			col = Color(3.2, 0.8, 1.4)
			size = 2
		"He_melt":
			col = Color(2.6, 2.0, 1.2)
		"A3_melt", "T_melt":
			col = Color(2.0, 1.5, 2.4)
		"Li_melt", "Be_melt":
			col = Color(2.6, 1.0, 1.4)
		"recH", "recHe":
			col = Color(3.0, 0.45, 0.55) if ch == "recH" else Color(2.8, 2.3, 0.7)
			if direction < 0:
				col = Color(1.0, 0.7, 1.8) if ch == "recH" else Color(1.6, 1.4, 2.0)
			cause = ("c_capture" if ch == "recH" else "c_capture2") if direction > 0 else "c_ionized"
	if ch.ends_with("_melt"):
		cause = "c_broke" if direction > 0 else "c_fusion"
	return [col, size, cause]


func _finish_bond(b: Dictionary, animated: bool) -> void:
	var members: PackedInt32Array = b["m"]
	var outputs: Array = b["out"]
	var center: Vector2 = b["c"]
	var followed := follow >= 0 and members.has(follow)
	var old_kind := kind[follow] if followed else -1
	var v := Vector2.ZERO
	for index in members:
		v += vel[index]
		_kill(index)
	v /= members.size()
	var next_follow := -1
	for k in outputs:
		var offset := _rand_vel(6.0) if outputs.size() > 1 else Vector2.ZERO
		var index := _spawn(k, center + offset, v * 0.5 + offset * 10.0)
		assert(index >= 0, "Reaction capacity must be reserved before consuming inputs")
		depth[index] = b["d"]
		if next_follow < 0 or k == old_kind:
			next_follow = index
	if followed:
		_follow_to(next_follow, String(b["cause"]))
	if not animated:
		return
	var sc: int = b["size"]
	var col: Color = b["col"]
	var d: float = b["d"]
	if members.size() == 1:
		# Preserve the existing split/weak effects without changing chemistry.
		if outputs.size() > 1:
			_flash(center, col, 34.0, 0.5, false, d)
		else:
			_flash(center, col, 20.0, 0.4, false, d)
			if b["ch"] == "n_to_p":
				_streak(center, Vector2.from_angle(randf() * TAU), Color(0.5, 1.3, 2.2), 0.7, 170.0, 40.0, d)
		reaction_shown.emit(String(b["ch"]), center)
		return
	_flash(center, col, 30.0 + 26.0 * sc, 0.55 + 0.4 * sc, false, d)
	if sc >= 1:
		_flash(center, col * 0.6, 34.0 + 46.0 * sc, 1.0 + 0.5 * sc, true, d)
	if sc >= 2:
		_gamma(center, col, 3, d)
	reaction_shown.emit(String(b["ch"]), center)


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
	# Самый горячий цикл игры (в браузере GDScript в разы медленнее), поэтому
	# вызовы _to_screen/_write и константные таблицы развёрнуты здесь вручную.
	var jitter := 30.0 + 170.0 * heat
	var flow := 16.0 + 34.0 * heat
	var damp := pow(0.45, delta)
	var t := flow_t
	var bc := box * 0.5
	var bx := box.x
	var by_ := box.y
	var hub := hubble
	var hs := hand_screen
	var hm := hand_mode
	var hr2 := HAND_R * HAND_R
	var hv := hand_vel
	var inv_zoom := 1.0 / cam_zoom
	var grav := gravity * 170.0
	var size_zoom := pow(cam_zoom, 0.75)
	var halo_zoom := 1.0 / sqrt(size_zoom)
	var glow_boost := 1.0 + 0.12 * squeeze
	var n_tick := 3.0 + 14.0 * n_clock
	var margin := 80.0 * cam_zoom
	var zoom := cam_zoom
	var vc := view * 0.5
	var cam_off := bc - cam_center
	var vmax := view + Vector2(margin, margin)
	var gx_scale := GW / bx
	var gy_scale := GH / by_
	var touch_glow := 0.9 if hm > 0 else 0.0
	var tw_s := sin(t * 2.3)
	var tw_c := cos(t * 2.3)
	var nt_s := sin(t * n_tick)
	var nt_c := cos(t * n_tick)
	var ph_s := _phase_s
	var ph_c := _phase_c
	# Цвет и размер видов на этот кадр (с учётом красного/синего смещения).
	var cr := PackedFloat32Array()
	var cg := PackedFloat32Array()
	var cb := PackedFloat32Array()
	var sz := PackedFloat32Array()
	cr.resize(KIND_COUNT)
	cg.resize(KIND_COUNT)
	cb.resize(KIND_COUNT)
	sz.resize(KIND_COUNT)
	for k in KIND_COUNT:
		var c: Color = COLORS[k]
		cr[k] = c.r * color_mul.x
		cg[k] = c.g * color_mul.y
		cb[k] = c.b * color_mul.z
		sz[k] = SIZES[k] * 4.0 * size_zoom
	var core := _core_buf
	var halo := _halo_buf
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
		var cell := clampi(int(p.y * gy_scale), 0, GH - 1) * GW + clampi(int(p.x * gx_scale), 0, GW - 1)
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
		if p.x < 0.0 or p.x > bx or p.y < 0.0 or p.y > by_:
			if drifts and hub > 0.0005:
				p = _rand_pos()
				fade[i] = 0.0
			else:
				p.x = fposmod(p.x, bx)
				p.y = fposmod(p.y, by_)
		elif drifts and hub < -0.0005 and (p - bc).length_squared() < 4900.0:
			p = Vector2(randf() * bx, 0.0 if randf() < 0.5 else by_)
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

		var sp := vc + ((p - bc) + cam_off * (0.55 + 0.45 * d)) * zoom
		spos[i] = sp
		if sp.x < -margin or sp.y < -margin or sp.x > vmax.x or sp.y > vmax.y:
			continue

		var k := kind[i]
		# Вспышка рождения: через 4 с exp(-3a) < 10⁻⁵, считать её незачем.
		var young := a < 4.0
		var bright := (0.35 + 0.65 * d) * f * glow_boost
		if young:
			bright *= 1.0 + 2.5 * exp(-a * 3.0)
		if touch > 0.0:
			bright *= 1.0 + touch_glow * touch
		if busy[i] == 1 and dying[i] == 0:
			bright *= 1.6
		if k == K.E:
			bright *= electron_alpha
			if bright < 0.01:
				continue
		elif k == K.H or k == K.HE:
			bright *= atom_dim * (1.0 + maxf(fluct[cell], 0.0) * gravity * 1.5)
		elif k == K.N:
			# Часы распада: чем дольше живёт нейтрон, тем тревожнее мерцает.
			bright *= 0.8 + 0.2 * (nt_s * ph_c[i] + nt_c * ph_s[i])
		bright *= 0.85 + 0.15 * (tw_s * ph_c[i] + tw_c * ph_s[i])
		var r := cr[k] * bright
		var g := cg[k] * bright
		var bl := cb[k] * bright
		var s := sz[k] * (0.55 + 0.45 * d)
		if young:
			s *= 1.0 + 1.2 * exp(-a * 5.0)
		var o := j * FLOATS
		core[o] = s
		core[o + 1] = 0.0
		core[o + 2] = 0.0
		core[o + 3] = sp.x
		core[o + 4] = 0.0
		core[o + 5] = s
		core[o + 6] = 0.0
		core[o + 7] = sp.y
		core[o + 8] = r
		core[o + 9] = g
		core[o + 10] = bl
		core[o + 11] = 1.0
		j += 1
		if k == K.HE4 or k == K.LI7 or k == K.H or k == K.HE:
			var atom := k == K.H or k == K.HE
			var hsz := s * (1.12 if atom else 1.1) * halo_zoom
			var hb := 0.05 if atom else 0.07
			o = hj * FLOATS
			halo[o] = hsz
			halo[o + 1] = 0.0
			halo[o + 2] = 0.0
			halo[o + 3] = sp.x
			halo[o + 4] = 0.0
			halo[o + 5] = hsz
			halo[o + 6] = 0.0
			halo[o + 7] = sp.y
			halo[o + 8] = r * hb
			halo[o + 9] = g * hb
			halo[o + 10] = bl * hb
			halo[o + 11] = 1.0
			hj += 1
	_core_buf = core
	_halo_buf = halo
	_core_mm.buffer = core
	_core_mm.visible_instance_count = j
	_halo_mm.buffer = halo
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
