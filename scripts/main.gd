extends Node2D
## Режиссёр: связывает физическую модель, частицы, фон, звук и интерфейс.
##
## Отладочные аргументы (после «--» в командной строке):
##   --start-T=1e9           начать сразу с температуры 10⁹ К
##   --speed=2               ход времени
##   --shot=путь_%d.png --shot-at=5,20   сохранить скриншоты на этих секундах и выйти
##   --launch-at=2           нажать «Запустить Вселенную» сам на 2-й секунде (как только готов звук);
##                           с --demo и --write-movie Вселенная запускается сама сразу

const UniverseModel := preload("res://scripts/universe.gd")
const StartScreenScript := preload("res://scripts/start_screen.gd")
const ParticleFieldScript := preload("res://scripts/particle_field.gd")
const HudScript := preload("res://scripts/hud.gd")
const AudioScript := preload("res://scripts/audio_director.gd")
const Palette := preload("res://scripts/palette.gd")
const Fmt := preload("res://scripts/fmt.gd")
const I18n := preload("res://scripts/i18n.gd")
const Epoch := UniverseModel.Epoch
const PK := ParticleFieldScript.K

## Темп игры: сколько «е-фолдов» космического времени проходит за секунду
## при данной температуре (lg T). Интересные эпохи идут медленно, переходы — быстро.
const PACE := [
	[13.3, 0.16], [12.6, 0.14], [12.35, 0.07], [12.0, 0.07], [11.7, 0.5], [10.6, 0.5],
	[10.3, 0.22], [9.5, 0.22], [9.25, 0.1], [8.9, 0.075], [8.5, 0.075], [8.2, 0.2],
	[7.8, 0.8], [5.0, 0.8], [4.5, 0.3], [4.2, 0.11], [3.4, 0.11], [3.25, 0.12], [2.0, 0.12]]
const END_T := 450.0
const STOP_T := 40.0
const WEB_GAIN := 0.25
## Большой взрыв: узор плазмы растягивается из масштаба INTRO_ZOOM до обычного за
## INFLATION_LEN секунд, сначала экспоненциально. Частицы родятся из плазмы по всему
## экрану, а их поле растягивается лишь от FIELD_ZOOM0: оно конечно, и при сильном
## отдалении стали бы видны его края.
const INTRO_ZOOM := 0.004
const FIELD_ZOOM0 := 0.85
const INFLATION_LEN := 2.8

var u
var start
var field
var hud
var audio
var env: Environment
var bg_mat: ShaderMaterial
var haze_mat: ShaderMaterial
var _hud_layer: CanvasLayer
var _tint_rect: ColorRect
var _shift_tint := 0.0       # > 0 — красное смещение (ускорили расширение), < 0 — синее

var speed := 1.0
var paused := false
var autopilot := false
var intro_t := 0.0
var flow_time := 0.0
var max_epoch := -1
var shown_epoch := -1
var finished := false
var fired: Dictionary = {}
var _silent := false
var _hud_timer := 0.0
var _e_at_bbn := 1.0
var _eta_at_bbn := 1.0
var _t_transparent := 0.0
var _banged := false
var _launch_at := -1.0
var _space_zoom := 1.0       # < 1 — идёт инфляция: масштаб узора плазмы

var _elapsed := 0.0
var _shot_path := ""
var _shot_times: Array[float] = []
var _start_T := 0.0
var _shot_index := 0

# Прогноз: копия модели, которую в фоне досчитывают до конца нуклеосинтеза.
var _fc = null
var _fc_out: Dictionary = {}

# Мышь.
var _lmb_down := false
var _lmb_t := 0.0
var _lmb_start := Vector2.ZERO
var _panning := false
var _demo := ""
var _arg_E := 1.0
var _arg_eta := 1.0


func _ready() -> void:
	I18n.load_language()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="):
			I18n.lang = arg.substr(7)
	DisplayServer.window_set_title(I18n.t("title"))
	# Окно 1600×900 по центру экрана — кроме записи видео и явного --resolution.
	var args := OS.get_cmdline_args()
	var shooting := false
	for arg in OS.get_cmdline_user_args():
		shooting = shooting or arg.begins_with("--shot=")
	if shooting:
		DisplayServer.window_set_size(Vector2i(1920, 1080))     # скриншоты — всегда в 1080p
	elif not args.has("--write-movie") and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		var screen := DisplayServer.screen_get_usable_rect()
		var size := Vector2i(mini(1600, screen.size.x - 80), mini(900, screen.size.y - 80))
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
	u = UniverseModel.new()
	_build_world()
	_parse_args()
	_start()


func _build_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		env.set_glow_level(i, [0.0, 1.0, 1.0, 1.0, 0.7, 0.5, 0.0][i])
	# В браузере (WebGL) кадр не хранит яркость выше 1, и без HDR пропадают свечение
	# и мягкие ореолы частиц. Там рисуем частицы и фон в WEB_GAIN раз тусклее,
	# во столько же раз снижаем порог свечения и в конце кадра поднимаем яркость обратно.
	# Поправка яркости поднимает не строго линейно — показатель подобран по скриншотам.
	if OS.has_feature("web"):
		ParticleFieldScript.gain = WEB_GAIN
		env.glow_hdr_threshold *= WEB_GAIN
		env.adjustment_enabled = true
		env.adjustment_brightness = pow(1.0 / WEB_GAIN, 0.75)
	we.environment = env
	add_child(we)

	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_mat = ShaderMaterial.new()
	bg_mat.shader = load("res://shaders/plasma.gdshader")
	bg_mat.set_shader_parameter("gain", ParticleFieldScript.gain)
	bg.material = bg_mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(bg)

	field = ParticleFieldScript.new()
	add_child(field)
	field.reaction_shown.connect(_on_reaction)
	field.species_seen.connect(_on_species)
	field.follow_changed.connect(func(active: bool) -> void:
		if not active:
			hud.hide_inspect())

	var haze_layer := CanvasLayer.new()
	haze_layer.layer = 1
	add_child(haze_layer)
	var haze := ColorRect.new()
	haze.set_anchors_preset(Control.PRESET_FULL_RECT)
	haze_mat = ShaderMaterial.new()
	haze_mat.shader = load("res://shaders/haze.gdshader")
	haze.material = haze_mat
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	haze_layer.add_child(haze)
	# Красная/синяя подсветка всего кадра, когда двигаешь темп расширения.
	_tint_rect = ColorRect.new()
	_tint_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_tint_rect.material = add
	_tint_rect.color = Color(0, 0, 0, 0)
	haze_layer.add_child(_tint_rect)

	audio = AudioScript.new()
	add_child(audio)

	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10
	add_child(_hud_layer)
	_make_hud()

	start = StartScreenScript.new()
	start.fonts_from(hud)
	add_child(start)
	start.language_toggled.connect(_toggle_language)
	start.stirred.connect(func(level: float, hover: bool) -> void: audio.play_touch(level, hover))


func _make_hud() -> void:
	hud = HudScript.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_layer.add_child(hud)
	hud.expansion_changed.connect(func(v: float) -> void:
		_manual()
		_shift_tint += (v - u.expansion) * 2.5
		u.expansion = v
		audio.nudge_expansion(v)
		_fc = null)
	hud.detent.connect(func() -> void: audio.play_detent())
	hud.density_changed.connect(func(v: float) -> void:
		_manual()
		u.eta_mult = pow(10.0, v)
		_fc = null)
	hud.speed_changed.connect(func(v: float) -> void:
		_manual()
		speed = v)
	hud.pause_toggled.connect(_toggle_pause)
	hud.autopilot_toggled.connect(func(on: bool) -> void: autopilot = on)
	hud.restart_requested.connect(_restart)
	hud.continue_requested.connect(func() -> void: pass)
	hud.language_toggled.connect(_toggle_language)
	hud.music_volume_changed.connect(func(v: float) -> void: audio.set_music_volume(v))
	hud.set_music_volume(audio.music_volume)


## Смена языка: пересобираем интерфейс и возвращаем в него текущее состояние.
func _toggle_language() -> void:
	I18n.set_language("en" if I18n.is_ru() else "ru")
	DisplayServer.window_set_title(I18n.t("title"))
	hud.queue_free()
	_make_hud()
	hud.set_controls(u.expansion, Palette.log10(u.eta_mult), speed)
	hud.set_paused(paused)
	hud.set_autopilot(autopilot)
	if shown_epoch >= 0:
		var e := I18n.epoch(shown_epoch)
		hud.set_epoch(e["num"], e["title"])
	if finished:
		_show_results()
	_hud_timer = 0.0
	hud.visible = _banged
	start.refresh_texts()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-at="):
			for s in a.substr(10).split(","):
				_shot_times.append(s.to_float())
		elif a.begins_with("--start-T="):
			_start_T = a.substr(10).to_float()
		elif a.begins_with("--expansion="):
			_arg_E = a.substr(12).to_float()
		elif a.begins_with("--density="):
			_arg_eta = a.substr(10).to_float()
		elif a == "--cinematic":
			hud.set_cinematic(true)
		elif a == "--clean":
			_hud_layer.visible = false
			field.show_cursor = false
		elif a.begins_with("--zoom="):
			field.cam_zoom = a.substr(7).to_float()
			field._zoom_target = field.cam_zoom
		elif a.begins_with("--demo="):
			_demo = a.substr(7)
		elif a.begins_with("--speed="):
			speed = clampf(a.substr(8).to_float(), 0.0, 2.0)
		elif a.begins_with("--launch-at="):
			_launch_at = a.substr(12).to_float()
	if _launch_at < 0.0 and (_demo != "" or OS.get_cmdline_args().has("--write-movie")):
		_launch_at = 0.0


func _start() -> void:
	u.reset()
	u.expansion = _arg_E
	u.eta_mult = _arg_eta
	speed = maxf(speed, 0.05)
	paused = false
	autopilot = false
	finished = false
	fired.clear()
	max_epoch = -1
	shown_epoch = -1
	intro_t = 0.0
	_t_transparent = 0.0
	_fc = null
	_fc_out = {}
	field.sync(u)
	field.reset_field()
	hud.clear_messages()
	hud.hide_inspect()
	hud.hide_results()
	hud.set_controls(u.expansion, Palette.log10(u.eta_mult), speed)
	hud.set_paused(false)
	hud.set_autopilot(false)
	hud.set_epoch("", "")
	# Вселенной ещё нет: частицы спрятаны и стоят, интерфейс проявится после вспышки.
	_banged = false
	_space_zoom = 1.0
	field.intro_zoom = 1.0
	field.visible = false
	field.process_mode = Node.PROCESS_MODE_DISABLED
	hud.visible = false
	start.reset()
	if _start_T > 0.0:
		_skip_intro()
		while u.T > _start_T:
			u.advance(0.02)
		u.take_events()
		field.rebuild_from(u)
		if u.ls_found:
			_t_transparent = -1.0
		intro_t = 100.0
		max_epoch = u.epoch() - 1
		_silent = true
		_update_story(0.0)
		_silent = false
		_start_T = 0.0


## Сразу к игре, без стартового экрана (--start-T): как будто взрыв давно прошёл.
func _skip_intro() -> void:
	start.dismiss()
	_banged = true
	field.visible = true
	field.process_mode = Node.PROCESS_MODE_INHERIT
	hud.visible = true
	hud.modulate.a = 1.0


## Точку разбудили кликами, или нажали Enter / пробел. Если звук ещё готовится,
## точка остаётся разбуженной и взрыв случится, как только он будет готов.
func _try_launch() -> void:
	if not start.can_launch():
		return
	if not audio.is_ready():
		start.charge_full()
		return
	start.launch(true)
	audio.play_swell()


## «Ещё раз» после итогов: сразу новая точка и новый взрыв, без стартового экрана.
func _restart() -> void:
	_start()
	start.launch(false)
	audio.play_swell()
	audio.prime_music()


## Вспышка: пространство начинает раздуваться, частицы рождаются из плазмы вразброс.
func _bang() -> void:
	_banged = true
	intro_t = 0.0
	field.visible = true
	field.process_mode = Node.PROCESS_MODE_INHERIT
	_space_zoom = INTRO_ZOOM
	field.intro_zoom = FIELD_ZOOM0
	field.stagger_birth(1.5)
	audio.play_boom()
	hud.visible = true
	hud.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(hud, "modulate:a", 1.0, 2.0).set_trans(Tween.TRANS_SINE)


# ---------------------------------------------------------------- кадр

func _process(delta: float) -> void:
	_elapsed += delta
	var s: float = start.since_bang()
	if s < 0.0:
		# Стартовый экран и «вдох» перед взрывом: Вселенной ещё нет.
		start.set_progress(audio.ready_progress, audio.is_ready())
		if start.wants_launch() or (_launch_at >= 0.0 and _elapsed >= _launch_at):
			_try_launch()
		_update_visuals(Palette.log10(u.T), delta)
		_check_shots()
		return
	if not _banged:
		_bang()
	# Инфляция: пространство растягивается — сначала экспоненциально, потом всё медленнее.
	if _space_zoom < 1.0:
		var x := clampf(s / INFLATION_LEN, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - x, 3.0)
		_space_zoom = 1.0 if x >= 1.0 else INTRO_ZOOM * pow(1.0 / INTRO_ZOOM, e)
		field.intro_zoom = 1.0 if x >= 1.0 else lerpf(FIELD_ZOOM0, 1.0, e)
	intro_t += delta
	_autopilot(delta)

	_update_mouse(delta)
	_run_demo()
	var lt := Palette.log10(u.T)
	if not paused and u.T > STOP_T:
		var ramp := smoothstep(2.5, 8.0, intro_t)
		u.advance(_pace(lt) * speed * ramp * delta)
		lt = Palette.log10(u.T)
	_forecast_step()

	field.sync(u)
	field.apply_events(u.take_events())
	var fog := _update_visuals(lt, delta)
	_update_story(delta)
	_update_hud(delta)
	audio.set_state(lt, fog, maxi(max_epoch, 0), delta, u.expansion, absf(float(field.hand_mode)), Palette.log10(u.eta_mult))
	_check_end()
	_check_shots()


## Множитель цвета для смещения: > 0 — краснее (расширение ускорили), < 0 — синее.
func _shift_mul() -> Vector3:
	var r := maxf(_shift_tint, 0.0)
	var b := maxf(-_shift_tint, 0.0)
	return Vector3(1.0 + 0.8 * r - 0.4 * b, 1.0 - 0.35 * r - 0.05 * b, 1.0 + 0.6 * b - 0.6 * r)


func _pace(lt: float) -> float:
	if lt >= PACE[0][0]:
		return PACE[0][1]
	for i in range(1, PACE.size()):
		var hi: Array = PACE[i - 1]
		var lo: Array = PACE[i]
		if lt >= float(lo[0]):
			var k := (lt - float(lo[0])) / (float(hi[0]) - float(lo[0]))
			return lerpf(float(lo[1]), float(hi[1]), k)
	return PACE[PACE.size() - 1][1]


func _update_visuals(lt: float, delta: float) -> float:
	var heat := clampf((lt - 2.5) / 10.5, 0.03, 1.0)
	var hot := Palette.plasma_color(u.T)
	var deep := Palette.plasma_deep(u.T)
	var inten := Palette.plasma_intensity(u.T)
	# Большой взрыв: до вспышки фона нет, после — он разгорается из белого каления.
	var s: float = start.since_bang()
	var appear := smoothstep(0.0, 1.8, s)
	var white := exp(-s / 0.7) if s >= 0.0 else 0.0
	hot = hot.lerp(Color(2.0, 1.35, 0.75), white)
	var cz: float = _space_zoom if _space_zoom < 1.0 else field.cam_zoom
	inten *= appear * (1.0 + 1.5 * white)
	var fog := smoothstep(0.01, 0.4, u.xH)
	var cmb := (1.0 - fog) * clampf((lt - 2.45) / 1.1, 0.0, 1.0) * 0.6 * appear
	flow_time += delta * (0.12 + 0.6 * heat)
	var res := get_viewport_rect().size

	# Красное/синее смещение, пока игрок двигает темп расширения.
	var sm := _shift_mul()
	bg_mat.set_shader_parameter("hot_color", Vector3(hot.r * sm.x, hot.g * sm.y, hot.b * sm.z))
	bg_mat.set_shader_parameter("deep_color", Vector3(deep.r * sm.x, deep.g * sm.y, deep.b * sm.z))
	field.color_mul = sm
	bg_mat.set_shader_parameter("intensity", inten)
	bg_mat.set_shader_parameter("fog", fog)
	var cc := Palette.blackbody(u.T)
	bg_mat.set_shader_parameter("cmb_color", Vector3(cc.r, cc.g, cc.b))
	bg_mat.set_shader_parameter("cmb", cmb)
	bg_mat.set_shader_parameter("flow_time", flow_time)
	bg_mat.set_shader_parameter("zoom", clampf(1.25 - 0.035 * (13.2 - lt), 0.85, 1.3))
	bg_mat.set_shader_parameter("turbulence", 0.6 + 0.6 * heat)
	bg_mat.set_shader_parameter("resolution", res)
	bg_mat.set_shader_parameter("squeeze", clampf(1.0 - u.expansion, -1.5, 2.0))
	bg_mat.set_shader_parameter("box_size", field.box)
	bg_mat.set_shader_parameter("cam_center", field.cam_center)
	bg_mat.set_shader_parameter("cam_zoom", cz)
	if field.fluct_tex != null:
		bg_mat.set_shader_parameter("fluct", field.fluct_tex)

	haze_mat.set_shader_parameter("haze_color", Vector3(hot.r, hot.g, hot.b) * inten)
	haze_mat.set_shader_parameter("amount", 0.2 * fog * clampf((lt - 3.3) / 0.5, 0.0, 1.0) * appear)
	haze_mat.set_shader_parameter("flow_time", flow_time)
	haze_mat.set_shader_parameter("resolution", res)
	haze_mat.set_shader_parameter("cam_off", (field.cam_center - field.box * 0.5) / res.y)
	haze_mat.set_shader_parameter("cam_zoom", cz)

	env.glow_intensity = lerpf(0.75, 1.0, heat) * (1.0 + 0.4 * white)

	_shift_tint = clampf(_shift_tint, -1.0, 1.0) * exp(-2.0 * delta)
	var k := absf(_shift_tint)
	var tint := Color(0.03, 0.004, 0.002) if _shift_tint > 0.0 else Color(0.002, 0.008, 0.035)
	_tint_rect.color = Color(tint.r * k, tint.g * k, tint.b * k, 1.0)
	return fog


# ---------------------------------------------------------------- сюжет

func _once(id: String, cond: bool) -> void:
	if cond and not fired.has(id):
		fired[id] = true
		if not _silent:
			hud.say(I18n.line(id))


func _update_story(_delta: float) -> void:
	var ep: int = u.epoch()
	if intro_t > 7.0:
		if ep > max_epoch:
			max_epoch = ep
			print("EPOCH %d at elapsed=%.1f s" % [ep, _elapsed])
			var e := I18n.epoch(ep)
			hud.show_card(e["num"], e["title"], e["sub"])
		if ep != shown_epoch:
			var e2 := I18n.epoch(ep)
			hud.set_epoch(e2["num"], e2["title"])
			if ep < shown_epoch:
				_once("reheat", true)
			shown_epoch = ep

	_once("inflation", intro_t > 2.2)
	_once("start", intro_t > 10.0)
	if intro_t > 12.0 and not fired.has("codex_q"):
		fired["codex_q"] = true
		if not _silent:
			_on_species(PK.QR)
	_once("touch", intro_t > 24.0)
	_once("cooling_qgp", u.T < 4.0e12)
	_once("hadron", u.hadron > 0.4)
	_once("neutrinos", u.T < 1.2e10 and u.hadron > 0.97)
	_once("freeze", u.T < 8.0e9)
	_once("annihilation", u.T < 3.0e9)
	_once("bottleneck", u.T < 1.6e9 and u.YD < 1.0e-3)
	_once("d_survives", u.YD > 2.0e-3)
	_once("helium", u.helium_mass_fraction() > 0.18)
	_once("bbn_done", u.T < 2.5e8 and fired.has("helium"))
	_once("long", u.T < 3.0e6)
	_once("he_atoms", u.xHe < 0.5)
	_once("recomb", u.xH < 0.6)
	_once("transparent", u.ls_found)
	if not fired.has("imprint") and u.ls_found and u.T < 2600.0:
		_once("imprint", field.count_clumps() > 0)
	_once("dark", u.T < 1200.0)
	_once("gather", u.T < 900.0)
	if u.T < 2.0e5 and not fired.has("codex_e"):
		fired["codex_e"] = true
		if not _silent:
			_on_species(PK.E)

	# Подсказки — по одной за игру, когда игрок заметно увёл рычаг.
	var bbn: bool = ep == Epoch.HADRON or ep == Epoch.NUCLEO
	_once("hint_compress", u.expansion < 0.0)
	_once("hint_slow", bbn and u.expansion < 0.75 and u.expansion >= 0.0)
	_once("hint_fast", bbn and u.expansion > 1.3)
	_once("hint_dense", ep == Epoch.NUCLEO and u.eta_mult > 3.0)
	_once("hint_sparse", ep == Epoch.NUCLEO and u.eta_mult < 0.33)

	if u.T < 9.0e8 and not fired.has("bbn_params"):
		fired["bbn_params"] = true
		_e_at_bbn = u.expansion
		_eta_at_bbn = u.eta_mult
	# Прозрачность — пик функции видимости (поверхность последнего рассеяния).
	if _t_transparent == 0.0 and u.ls_found:
		_t_transparent = u.t_ls


func _on_species(k: int) -> void:
	var key := 0 if k <= PK.QB else k
	if I18n.has_species(key):
		var item: Array = I18n.species(key)
		hud.show_codex(item[0], item[1])


func _on_reaction(channel: String, _pos: Vector2) -> void:
	audio.play_event(channel)


# ---------------------------------------------------------------- интерфейс

func _ui_color(k: int) -> Color:
	var c: Color = ParticleFieldScript.COLORS[k]
	var m := maxf(c.r, maxf(c.g, c.b))
	return Color(c.r / m, c.g / m, c.b / m)


func _logbar(v: float) -> float:
	return clampf((Palette.log10(maxf(v, 1.0e-30)) + 11.0) / 11.0, 0.0, 1.0)


func _pct(v: float) -> String:
	if v <= 0.0:
		return "0%"
	if v < 0.001:
		return Fmt.sci(v * 100.0) + "%"
	return Fmt.percent(v)


func _energy(mev: float) -> String:
	if mev >= 1.0:
		return Fmt.num(mev) + I18n.t("u_MeV")
	if mev >= 1.0e-3:
		return Fmt.num(mev * 1.0e3) + I18n.t("u_keV")
	return Fmt.num(mev * 1.0e6) + I18n.t("u_eV")


func _update_hud(delta: float) -> void:
	hud.set_time(Palette.log10(u.t))
	_hud_timer -= delta
	if _hud_timer > 0.0:
		return
	_hud_timer = 0.1

	var s: String = "t = " + Fmt.duration(u.t) + "\nT = " + Fmt.sci(u.T) + I18n.t("u_K")
	if u.T > 1.0e5:
		s += "   ·   kT ≈ " + _energy(u.kt_mev())
	else:
		s += "   ·   z ≈ " + Fmt.sci(u.redshift())
	hud.set_readout(s)

	var rows: Array = []
	var fc_ok: bool = not _fc_out.is_empty() and u.T > 2.5e8
	if u.hadron < 0.97:
		rows.append([I18n.t("row_quarks"), _pct(1.0 - u.hadron), 1.0 - u.hadron, _ui_color(PK.QB)])
		rows.append([I18n.t("row_nucleons"), _pct(u.hadron), u.hadron, _ui_color(PK.P)])
	else:
		rows.append([I18n.t("row_hydrogen"), _pct(u.Yp), u.Yp, _ui_color(PK.P)])
		if u.Yn > 1.0e-6 or u.T > 1.0e8:
			var clock := {"clock": clampf(u.t / 879.4, 0.0, 1.0)} if u.T > 2.5e8 else {}
			rows.append([I18n.t("row_neutrons"), _pct(u.Yn), u.Yn * 2.0, _ui_color(PK.N), clock])
		var dh_text := Fmt.sci(u.d_to_h())
		var dh_extra := {}
		if fc_ok:
			dh_text += "  %s  " % Fmt.arrow + Fmt.sci(float(_fc_out["dh"]))
			dh_extra = {"ghost": _logbar(float(_fc_out["dh"])), "ref": _logbar(2.5e-5)}
		rows.append([I18n.t("row_deuterium"), dh_text, _logbar(u.d_to_h()), _ui_color(PK.D), dh_extra])
		rows.append([I18n.t("row_he3"), Fmt.sci(u.he3_to_h()), _logbar(u.he3_to_h()), _ui_color(PK.HE3)])
		rows.append([I18n.t("row_li7"), Fmt.sci(u.li7_to_h()), _logbar(u.li7_to_h()), _ui_color(PK.LI7)])
		if u.T < 3.0e5:
			rows.append([I18n.t("row_electrons"), _pct(u.xH), u.xH, _ui_color(PK.E)])
	# Гелий — главный итог: показываем и его прогноз, пока синтез не закончился.
	var yp: float = u.helium_mass_fraction()
	var he_text := _pct(yp) if yp > 0.001 else "—"
	var he_extra := {}
	if fc_ok:
		he_text += "  %s  " % Fmt.arrow + _pct(float(_fc_out["yp"]))
		he_extra = {"ghost": float(_fc_out["yp"]) * 2.5, "ref": 0.247 * 2.5}
	if u.hadron >= 0.97 or fc_ok:
		var at := 2 if u.hadron < 0.97 else mini(rows.size(), 3)
		rows.insert(at, [I18n.t("row_he4"), he_text, yp * 2.5, _ui_color(PK.HE4), he_extra])
	hud.set_rows(rows)

	if field.follow >= 0:
		var pname := I18n.particle(field.followed_kind())
		hud.show_inspect(pname.substr(0, 1).to_upper() + pname.substr(1), field.follow_log)


# ---------------------------------------------------------------- управление

func _manual() -> void:
	if autopilot:
		autopilot = false
		hud.set_autopilot(false)


func _autopilot(delta: float) -> void:
	if not autopilot:
		return
	var k := 1.0 - exp(-0.6 * delta)
	u.expansion = lerpf(u.expansion, 1.0, k)
	var dlog := lerpf(Palette.log10(u.eta_mult), 0.0, k)
	u.eta_mult = pow(10.0, dlog)
	speed = lerpf(speed, 1.0, k)
	hud.set_controls(u.expansion, dlog, speed)


func _toggle_pause() -> void:
	paused = not paused
	hud.set_paused(paused)


func _unhandled_input(event: InputEvent) -> void:
	if start.since_bang() < 0.0:
		_title_input(event)
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					field.zoom_at(mb.position, 1.12)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					field.zoom_at(mb.position, 1.0 / 1.12)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_lmb_down = true
					_lmb_t = _elapsed
					_lmb_start = mb.position
				else:
					# Короткий клик — выбрать частицу, долгое нажатие — рука.
					if field.hand_mode == 0 and mb.position.distance_to(_lmb_start) < 8.0:
						field.try_pick(mb.position)
					_lmb_down = false
					field.set_hand(mb.position, 0)
			MOUSE_BUTTON_RIGHT:
				field.set_hand(mb.position, -1 if mb.pressed else 0)
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		if _panning:
			field.pan(mm.relative)
		field.set_hand(mm.position, field.hand_mode)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			_toggle_pause()
		KEY_H:
			hud.toggle_visible()
		KEY_M:
			hud.set_music_volume(audio.toggle_music_mute())
		KEY_F11, KEY_F:
			_toggle_fullscreen()
		KEY_ESCAPE:
			if field.follow >= 0:
				field.stop_follow()
			elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## Стартовый экран: клик — коснуться точки, Enter или пробел — запуск, F — полный экран.
func _title_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		start.poke()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_try_launch()
		KEY_F11, KEY_F:
			_toggle_fullscreen()
		KEY_ESCAPE:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _update_mouse(delta: float) -> void:
	if _lmb_down and field.hand_mode == 0:
		var mouse := get_viewport().get_mouse_position()
		if _elapsed - _lmb_t > 0.18 or mouse.distance_to(_lmb_start) > 8.0:
			field.set_hand(mouse, 1)
	var dir := Vector2(
		float(Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)))
	if dir != Vector2.ZERO:
		field.pan(-dir * 700.0 * delta)


## Отладка без мыши: --demo=touch (рука рисует круг), --demo=follow (выбор частицы).
func _run_demo() -> void:
	if _demo == "touch":
		var c := get_viewport_rect().size * 0.5 + Vector2(cos(_elapsed * 1.3), sin(_elapsed * 1.3)) * 260.0
		field.set_hand(c, 1 if _elapsed > 1.5 and _elapsed < 9.0 else 0)
	elif _demo == "auto":
		_run_autoplayer()
	elif _demo == "shift":
		# Ползунок расширения: 1 → 2,2 (красное смещение) → 0,3 (синее) → обратно к 1.
		var e := 1.0
		if _elapsed > 3.0 and _elapsed < 6.0:
			e = lerpf(1.0, 2.2, (_elapsed - 3.0) / 3.0)
		elif _elapsed >= 6.0 and _elapsed < 7.0:
			e = 2.2
		elif _elapsed >= 7.0 and _elapsed < 10.0:
			e = lerpf(2.2, 0.3, (_elapsed - 7.0) / 3.0)
		elif _elapsed >= 10.0 and _elapsed < 12.0:
			e = lerpf(0.3, 0.97, (_elapsed - 10.0) / 2.0)
		if _elapsed > 3.0 and absf(hud._sl_exp.value - e) > 0.005 and _elapsed < 12.5:
			hud._sl_exp.value = e
	elif _demo == "press":
		field.set_hand(get_viewport_rect().size * Vector2(0.5, 0.42), 1 if _elapsed > 1.0 else 0)
	elif _demo == "follow" and _elapsed > 3.0:
		_demo = ""
		var view := get_viewport_rect().size
		for r in range(0, 400, 20):
			if field.try_pick(view * 0.5 + Vector2(r, 0)):
				break


## «Автопилот» для видео-прохождения: время от времени касается плазмы
## и один раз следит за частицей во время нуклеосинтеза.
var _auto_state := 0
var _auto_t := 0.0


func _run_autoplayer() -> void:
	var view := get_viewport_rect().size
	# Каждое касание — в своём месте, с небольшим кругом вокруг точки.
	var spot := -1
	if _elapsed > 16.0 and _elapsed < 23.0:
		spot = 0                                           # кварковая плазма
	elif u.T < 2.0e11 and u.T > 8.0e9:
		spot = 1                                           # эпоха нуклонов
	elif u.T < 9.0e3 and u.T > 5.0e3:
		spot = 2                                           # перед рекомбинацией
	elif u.T < 2000.0 and u.T > 700.0:
		spot = 3                                           # тёмные века: гравитация отвечает руке
	var spots := [Vector2(0.24, 0.27), Vector2(0.76, 0.27), Vector2(0.74, 0.76), Vector2(0.26, 0.76)]
	var p := view * 0.5
	if spot >= 0:
		p = view * spots[spot] + Vector2(cos(_elapsed * 1.1), sin(_elapsed * 1.1)) * 50.0
	var pressing := spot >= 0
	match _auto_state:
		0:
			if u.T < 1.3e9:
				for r in range(0, 400, 20):
					if field.try_pick(view * 0.5 + Vector2(r, 0)):
						break
				_auto_t = _elapsed
				_auto_state = 1
		1:
			if _elapsed - _auto_t > 22.0:
				field.stop_follow()
				field.zoom_at(view * 0.5, 1.0 / 2.2)
				_auto_state = 2
	field.set_hand(p, 1 if pressing and field.follow < 0 else 0)


## Досчитываем копию модели до конца нуклеосинтеза — понемногу, ~3 мс за кадр.
func _forecast_step() -> void:
	if u.T < 2.5e8:
		_fc = null
		return
	if _fc == null:
		if u.expansion < 0.05:
			_fc_out = {}
			return
		_fc = u.clone()
		_fc.substep = 0.05
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 3000:
		_fc.advance(0.05)
		_fc.take_events()
		if _fc.T < 2.0e8:
			_fc_out = {"yp": _fc.helium_mass_fraction(), "dh": _fc.d_to_h()}
			_fc = null
			return
		if _fc.t > 1.0e6:
			_fc_out = {}
			_fc = null
			return


# ---------------------------------------------------------------- финал

func _check_end() -> void:
	if finished or u.T > END_T or u.epoch() != Epoch.DARK:
		return
	finished = true
	print("RESULTS_SHOWN at elapsed=%.1f s, clumps=%d" % [_elapsed, field.count_clumps()])
	if not OS.get_cmdline_user_args().has("--no-results"):
		_show_results()


## Итоги. Колонка «наша» — наблюдения (PDG 2024, Planck 2018). Литий в старых звёздах
## втрое меньше, чем даёт любая модель нуклеосинтеза, — это «литиевая проблема».
func _show_results() -> void:
	var yp: float = u.helium_mass_fraction()
	var dh: float = u.d_to_h()
	var rows := [
		[I18n.t("res_he4"), _pct(yp), Fmt.comma("24.5%")],
		[I18n.t("res_d"), Fmt.sci(dh, 2), Fmt.sci(2.55e-5, 2)],
		[I18n.t("res_he3"), Fmt.sci(u.he3_to_h()), "≈1×10" + Fmt.sup(-5)],
		[I18n.t("res_li"), Fmt.sci(u.li7_to_h()), Fmt.sci(1.6e-10)],
		[I18n.t("res_expansion"), "×" + Fmt.comma("%.2f" % _e_at_bbn), "×" + Fmt.comma("1.00")],
		[I18n.t("res_eta"), Fmt.sci(UniverseModel.ETA_STD * _eta_at_bbn, 2), Fmt.sci(6.12e-10, 2)],
		[I18n.t("res_clumps"), str(field.count_clumps()), "—"],
		[I18n.t("res_transparent"), Fmt.duration(_t_transparent) if _t_transparent > 0.0 else "—", I18n.t("res_transparent_ours")],
	]
	hud.show_results(rows, _verdict(yp, dh))


func _verdict(yp: float, dh: float) -> String:
	if absf(yp - 0.247) < 0.02 and dh > 1.2e-5 and dh < 5.0e-5:
		return I18n.t("verdict_ours")
	var parts: Array[String] = []
	if yp < 0.12:
		parts.append(I18n.t("verdict_h"))
	elif yp < 0.22:
		parts.append(I18n.t("verdict_less_he"))
	elif yp > 0.4:
		parts.append(I18n.t("verdict_he"))
	elif yp > 0.27:
		parts.append(I18n.t("verdict_more_he"))
	if dh > 1.0e-4:
		parts.append(I18n.t("verdict_more_d"))
	elif dh < 5.0e-6:
		parts.append(I18n.t("verdict_less_d"))
	if parts.is_empty():
		parts.append(I18n.t("verdict_own"))
	return " ".join(parts)


# ---------------------------------------------------------------- скриншоты для отладки

func _check_shots() -> void:
	if _shot_path == "" or _shot_times.is_empty():
		return
	if _elapsed >= _shot_times[0]:
		_shot_index += 1
		_shot_times.pop_front()
		_save_shot(_shot_path.replace("%d", str(_shot_index)), _shot_times.is_empty())


func _save_shot(path: String, quit_after: bool) -> void:
	await RenderingServer.frame_post_draw
	# При HDR 2D кадр хранится в линейном цвете — переводим в sRGB, как на экране.
	var img := get_viewport().get_texture().get_image()
	if get_viewport().use_hdr_2d:
		img.convert(Image.FORMAT_RGBA8)
		img.linear_to_srgb()
	img.save_png(path)
	print("screenshot: ", path, "  fps=", Engine.get_frames_per_second(), "  zoom=", field.cam_zoom,
		"  counts=", field.counts, "  nominal=", field.baryons_nominal, "  T=", u.T, "  proc_ms=", Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	if quit_after:
		get_tree().quit()
