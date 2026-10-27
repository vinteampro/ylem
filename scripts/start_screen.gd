extends Node2D
## Стартовый экран: Вселенную запускает сам игрок.
##
## Заставка с названием растворяется в темноту, где вдали светится точка — область,
## из которой вырастет всё, что сегодня видно в телескопы. Вокруг неё вспыхивают
## и гаснут виртуальные частицы — квантовая пена. Точка откликается на курсор
## тихим звуком, а на клики — разгорается и приближается. Частые клики будят её;
## если кликать редко, напряжение спадает. Подсказки появляются по мере надобности,
## Enter и пробел запускают сразу.
##
## Запуск: «вдох» — точка сжимается и разгорается, — затем вспышка, ударные волны
## и лучи. Пространство и частицы разворачивает main.gd.
##
## Сам узел рисуется в основном холсте, поэтому светится (glow), как частицы;
## подсказки и кнопка языка — на отдельном слое поверх.

signal language_toggled
signal stirred(level: float, hover: bool)   # точку потрогали — для звука

const ParticleFieldScript := preload("res://scripts/particle_field.gd")
const I18n := preload("res://scripts/i18n.gd")

const BANG_AT := 0.75      # «вдох» до вспышки, с
const BANG_LEN := 3.2      # сколько длятся вспышка, волны и лучи
const SPARKS := 42
const RAYS := 72
const SPARK_COLORS := [Color(2.0, 0.55, 0.45), Color(0.55, 1.8, 0.7), Color(0.6, 0.8, 2.2)]
const POKE := 0.2          # прибавка «пробуждения» за клик: пять частых кликов
const DECAY := 0.22        # спад в секунду, если игрок медлит
const DECAY_AFTER := 0.7   # …дольше стольких секунд
const HINT_AFTER := 3.5    # первая подсказка, если игрок ничего не делает
const HELP_AFTER := 45.0   # прямая подсказка, если так и не догадался

var _t := 0.0
var _launch_t := -1.0      # время с запуска; < 0 — ещё не запускали
var _glow: GradientTexture2D
var _sparks: Array = []    # [смещение, возраст, срок, цвет, размер]
var _rays: Array = []      # [угол, длина, яркость, толщина]
var _ripples: Array[float] = []

var _energy := 0.0         # 0…1 — насколько точка «проснулась»
var _stir := 0.0           # всплеск от последнего касания
var _hover_k := 0.0
var _hovered := false
var _hover_sound_t := -10.0
var _pokes := 0
var _last_poke := -10.0
var _missed_t := -100.0
var _progress := 0.0
var _sounds_ready := false

var _hud                   # шрифт и стиль берём у интерфейса
var _ui: Control
var _hint: Label
var _hint_text := ""
var _lang: Button
var _splash: TextureRect


func fonts_from(hud) -> void:
	_hud = hud


func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_glow = _radial()
	for i in SPARKS:
		_sparks.append(_new_spark(randf()))
	for i in RAYS:
		_rays.append([randf() * TAU, randf_range(0.35, 1.0), randf_range(0.3, 1.0), randf_range(1.0, 2.6)])
	_build_ui()
	refresh_texts()


func _radial() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.1, 0.22, 0.5, 1.0])
	var cols := PackedColorArray()
	for a in [1.0, 1.0, 0.4, 0.08, 0.0]:
		cols.append(Color(1.0, 1.0, 1.0, pow(a, 1.6)))
	g.colors = cols
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	return tex


func _new_spark(age_k: float) -> Array:
	var off := Vector2.from_angle(randf() * TAU) * (18.0 + 120.0 * pow(randf(), 1.5))
	var life := randf_range(0.5, 1.6)
	return [off, life * age_k, life, SPARK_COLORS[randi() % 3], randf_range(7.0, 13.0)]


# ---------------------------------------------------------------- интерфейс

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 11
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = _hud.theme
	layer.add_child(_ui)

	_hint = _hud._label("", _hud.font_light, 24, Color(0.88, 0.9, 0.97, 0.85))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_right = 1.0
	_hint.anchor_top = 0.5
	_hint.anchor_bottom = 0.5
	_hint.offset_top = 190.0
	_hint.offset_bottom = 226.0
	_hint.modulate.a = 0.0
	_ui.add_child(_hint)

	_lang = Button.new()
	_lang.focus_mode = Control.FOCUS_NONE
	_lang.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_lang.offset_left = -170.0
	_lang.offset_right = -40.0
	_lang.offset_top = -82.0
	_lang.offset_bottom = -40.0
	_lang.pressed.connect(func() -> void: language_toggled.emit())
	_ui.add_child(_lang)

	# Заставка с названием растворяется, открывая пустоту и точку, — без резкой смены кадра.
	var path := String(ProjectSettings.get_setting("application/boot_splash/image", ""))
	if bool(ProjectSettings.get_setting("application/boot_splash/show_image", false)) and ResourceLoader.exists(path):
		_splash = TextureRect.new()
		_splash.texture = load(path)
		_splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_splash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_splash)
		var tw := create_tween()
		tw.tween_interval(0.6)
		tw.tween_property(_splash, "modulate:a", 0.0, 2.2).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(_splash.queue_free)


func refresh_texts() -> void:
	_lang.text = I18n.t("lang_button")
	_hint_text = ""


## Готовность звуков. Пока их нет, точка всё равно откликается, а взрыв подождёт.
func set_progress(progress: float, ready: bool) -> void:
	_progress = progress
	_sounds_ready = ready


## Подсказка по ходу дела: ничего не делает — «коснись», начал — «ещё»,
## медлит — «чаще», давно не догадался — прямо.
func _hint_key() -> String:
	if _energy >= 1.0 and not _sounds_ready:
		return "preparing"
	if _t > HELP_AFTER:
		return "hint_help"
	if _pokes == 0:
		return "hint_touch" if _t > HINT_AFTER or _t - _missed_t < 4.0 else ""
	if _t - _missed_t < 3.0:
		return "hint_touch"
	if _t - _last_poke > 2.0 and _energy < 0.15:
		return "hint_faster"
	return "hint_more"


func _update_hint(delta: float) -> void:
	var key := _hint_key()
	var text := ""
	if key == "preparing":
		text = I18n.t(key) % roundi(_progress * 100.0)
	elif key != "":
		text = I18n.t(key)
	# Смена подсказки: старая растворяется, новая проявляется. Проценты меняем на месте.
	if text != _hint_text and _hint.modulate.a > 0.02 and key != "preparing":
		_hint.modulate.a = maxf(0.0, _hint.modulate.a - delta * 3.0)
		return
	_hint_text = text
	_hint.text = text
	_hint.modulate.a = minf(1.0, _hint.modulate.a + delta * 1.2) if text != "" else 0.0


# ---------------------------------------------------------------- касания

func _point() -> Vector2:
	return get_viewport_rect().size * 0.5


func _reach() -> float:
	return 70.0 + 120.0 * _energy


## Клик: попал в свет — он разгорается; промах — подсказка «коснись света».
func poke() -> void:
	if _launch_t >= 0.0 or not visible:
		return
	if get_global_mouse_position().distance_to(_point()) > _reach():
		_missed_t = _t
		return
	_energy = minf(1.0, _energy + POKE)
	_stir = 1.0
	_pokes += 1
	_last_poke = _t
	_ripples.append(0.0)
	stirred.emit(_energy, false)


## Enter или пробел: разбудить сразу.
func charge_full() -> void:
	_energy = 1.0
	_last_poke = _t


func wants_launch() -> bool:
	return _energy >= 1.0 and can_launch()


func can_launch() -> bool:
	return _launch_t < 0.0 and visible


## Запуск. На повторном (после итогов) подсказок уже нет — только точка и взрыв.
func launch(with_ui: bool) -> void:
	_launch_t = 0.0
	_energy = 1.0
	_set_hovered(false)
	if not with_ui:
		_ui.visible = false


## Секунды после вспышки; отрицательно — стартовый экран или «вдох».
func since_bang() -> float:
	return _launch_t - BANG_AT if _launch_t >= 0.0 else -100.0


## Новая Вселенная: снова точка в пустоте.
func reset() -> void:
	_launch_t = -1.0
	_energy = 0.0
	_ripples.clear()
	visible = true
	_ui.visible = true
	_ui.modulate.a = 1.0


## Без стартового экрана (--start-T): как будто взрыв давно прошёл.
func dismiss() -> void:
	_launch_t = 1000.0
	visible = false
	_ui.visible = false
	_set_hovered(false)
	if _splash != null:
		_splash.visible = false


func _set_hovered(on: bool) -> void:
	if on == _hovered:
		return
	_hovered = on
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if on else Input.CURSOR_ARROW)
	# Тихий отклик на наведение — не чаще раза в секунду.
	if on and _t - _hover_sound_t > 1.0:
		_hover_sound_t = _t
		_stir = maxf(_stir, 0.35)
		stirred.emit(_energy, true)


# ---------------------------------------------------------------- кадр

func _process(delta: float) -> void:
	_t += delta
	if _launch_t >= 0.0:
		_launch_t += delta
	if not visible:
		return
	if _launch_t > BANG_AT + BANG_LEN:
		visible = false
		_ui.visible = false
		return
	if _launch_t < 0.0:
		_set_hovered(get_global_mouse_position().distance_to(_point()) < _reach())
		if _energy < 1.0 and _t - _last_poke > DECAY_AFTER:
			_energy = maxf(0.0, _energy - DECAY * delta)
		_update_hint(delta)
		_ui.modulate.a = 1.0
	else:
		_ui.modulate.a = 1.0 - clampf(_launch_t / BANG_AT * 2.0, 0.0, 1.0)
	_hover_k = lerpf(_hover_k, 1.0 if _hovered else 0.0, 1.0 - exp(-6.0 * delta))
	_stir *= exp(-4.0 * delta)
	for i in range(_ripples.size() - 1, -1, -1):
		_ripples[i] += delta
		if _ripples[i] > 0.9:
			_ripples.remove_at(i)
	# Чем сильнее точка проснулась, тем быстрее кипит пена вокруг.
	var foam := delta * (1.0 + 2.0 * _energy)
	for i in _sparks.size():
		var sp: Array = _sparks[i]
		sp[1] += foam
		if sp[1] > sp[2]:
			_sparks[i] = _new_spark(0.0)
	queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	var c := view * 0.5
	var g: float = ParticleFieldScript.gain
	var s := since_bang()
	if s >= 0.0:
		_draw_bang(view, c, s, g)
		return
	var inhale := clampf(_launch_t / BANG_AT, 0.0, 1.0) if _launch_t >= 0.0 else 0.0
	var e := _energy
	# Проснувшаяся точка дрожит.
	var core_c := c + Vector2(sin(_t * 53.0), cos(_t * 47.0)) * 2.5 * e * e

	# Круги от касаний.
	for a in _ripples:
		var k := 1.0 - a / 0.9
		_ring(c, 18.0 + 320.0 * a, 2.0 + 6.0 * k, _hdr(1.4, 1.1, 0.8, 0.45 * k * k * g))

	# Квантовая пена: виртуальные частицы вспыхивают и гаснут; при «вдохе» их втягивает в точку.
	var spread := (0.45 + 0.75 * e) * (1.0 - inhale * inhale)
	var foam_a := 0.12 + 0.45 * e + 0.25 * _hover_k
	for sp in _sparks:
		var f := sin(PI * float(sp[1]) / float(sp[2]))
		var col: Color = sp[3]
		_blob(c + Vector2(sp[0]) * spread, float(sp[4]) * (0.7 + 0.5 * e), _hdr(col.r, col.g, col.b, foam_a * f * f * g))

	# Точка «дышит», откликается на курсор и клики, при «вдохе» сжимается и разгорается.
	var breath := 0.5 + 0.5 * sin(_t * TAU / 4.5)
	var boost := (1.0 + 2.5 * e + 0.4 * _hover_k + 2.0 * _stir) * (1.0 + 4.0 * inhale * inhale)
	_blob(c, (90.0 + 260.0 * e + 30.0 * breath) * (1.0 - 0.75 * inhale), _hdr(0.30, 0.19, 0.12, (0.6 + 0.3 * breath) * boost * g))
	_blob(core_c, (12.0 + 30.0 * e + 4.0 * breath + 8.0 * _stir) * (1.0 - 0.6 * inhale * inhale), _hdr(3.0, 2.7, 2.3, (0.85 + 0.3 * breath) * boost * g))


## Вспышка, огненный шар, ударные волны и лучи.
func _draw_bang(view: Vector2, c: Vector2, s: float, g: float) -> void:
	var diag := view.length()
	# Весь кадр раскалён добела и быстро остывает.
	var flash := 2.0 * exp(-s / 0.12) + 0.2 * exp(-s / 0.7)
	draw_rect(Rect2(Vector2.ZERO, view), _hdr(1.0, 0.94, 0.86, flash * g))
	_blob(c, 160.0 + 2400.0 * (1.0 - exp(-s / 0.4)), _hdr(2.0, 1.6, 1.2, exp(-s / 0.35) * g))
	# Ударные волны: тёплая и чуть позже холодная.
	_ring(c, diag * 0.62 * (1.0 - exp(-s / 0.45)), 4.0 + 30.0 * exp(-s / 0.5), _hdr(2.2, 1.7, 1.15, exp(-s / 0.75) * g))
	if s > 0.12:
		var s2 := s - 0.12
		_ring(c, diag * 0.5 * (1.0 - exp(-s2 / 0.6)), 3.0 + 16.0 * exp(-s2 / 0.6), _hdr(0.9, 1.25, 2.0, 0.5 * exp(-s2 / 0.9) * g))
	# Лучи разлетаются из точки и гаснут.
	var reach := diag * 0.7 * (1.0 - exp(-s / 0.28))
	var fade := exp(-s / 0.4)
	for r in _rays:
		var dir := Vector2.from_angle(float(r[0]))
		var k: float = r[1]
		draw_line(c + dir * reach * 0.12 * k, c + dir * reach * k, _hdr(1.6, 1.4, 1.1, fade * float(r[2]) * g), float(r[3]), true)


func _blob(p: Vector2, size: float, col: Color) -> void:
	draw_texture_rect(_glow, Rect2(p - Vector2(size, size) * 0.5, Vector2(size, size)), false, col)


## Мягкое кольцо: яркая середина и два всё более широких и тусклых слоя вокруг.
func _ring(p: Vector2, radius: float, width: float, col: Color) -> void:
	if radius <= 1.0:
		return
	for layer in [[4.0, 0.08], [2.2, 0.2], [1.0, 0.55]]:
		var k: float = layer[1]
		draw_arc(p, radius, 0.0, TAU, 160, Color(col.r * k, col.g * k, col.b * k, 1.0), width * float(layer[0]), true)


## Цвет ярче 1 — его подхватывает свечение. Альфа всегда 1: смешивание сложением.
static func _hdr(r: float, g: float, b: float, k: float) -> Color:
	return Color(r * k, g * k, b * k, 1.0)
