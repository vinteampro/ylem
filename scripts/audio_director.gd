extends Node
## Звук.
##
## 1. Музыка: если в res://audio/music/ лежат треки epoch_1 … epoch_6
##    (.ogg, .mp3 или .wav), они плавно сменяют друг друга по эпохам.
## 2. Эмбиент: тихий гудящий аккорд и шорох плазмы — синтезируются при запуске,
##    поэтому игра звучит и без музыки. С остыванием аккорд опускается — как красное смещение.
## 3. «Колокольчики» реакций в ми-мажорной пентатонике. Атомы звучат своими
##    настоящими спектральными линиями, перенесёнными на 40 октав вниз:
##    H-альфа (656 нм) → 415 Гц (соль-диез), H-бета (486 нм) → 561 Гц (до-диез).
## 4. Рычаги звучат. Пока тянешь «темп расширения», поёт линия H-альфа и скользит
##    вниз при ускорении (красное смещение) и вверх при замедлении (синее); музыка
##    постоянно чуть смещена по высоте. Плотность меняет «тесноту»: плотнее — глуше
##    и суше, разреженнее — воздушнее и с длинным эхом.
## 5. Громкость музыки задаёт игрок (ползунок «Музыка», клавиша M); она
##    запоминается в user://settings.cfg.
## 6. Запуск Вселенной: «вдох» — нарастающий шум — и удар Большого взрыва,
##    низкий тон, уходящий вниз, с долгим рокотом.

const RATE := 22050
const MUSIC_DIR := "res://audio/music/"
const SETTINGS := "user://settings.cfg"
const MUSIC_BUS_DB := -4.0

var music_volume := 1.0
var _volume_before_mute := 1.0
var _save_at := -1

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active: AudioStreamPlayer
var _music_epoch := -1
var _has_music := false
var _pad: AudioStreamPlayer
var _hiss: AudioStreamPlayer
var _chimes: AudioStreamPlayer
var _poly: AudioStreamPlaybackPolyphonic
var _bells: Dictionary = {}
var _cooldown: Dictionary = {}
var _budget := 0.0
var _clock := 0.0
var _lowpass: AudioEffectLowPassFilter
var _music_lp: AudioEffectLowPassFilter
var _reverb: AudioEffectReverb
var _thread: Thread
var ready_progress := 0.0      # доля синтезированных звуков, 0…1 — для кнопки на стартовом экране
var _steps: Array[Callable] = []
var _step_i := 0
var _synth_ms := 0
var _made: Dictionary = {}     # готовые звуки: pad, hiss, shift, swell, boom
var _music_cache: Dictionary = {}
var _pad_buf := PackedFloat32Array()
var _shift_buf := PackedFloat32Array()
var _shift: AudioStreamPlayer
var _shift_anchor := 1.0
var _shift_pitch := 1.0
var _shift_last := -100.0
var _music_pitch := 1.0


func _ready() -> void:
	_setup_buses()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		music_volume = clampf(float(cfg.get_value("audio", "music_volume", 1.0)), 0.0, 1.0)
	_apply_music_volume()
	_music_a = _player("Music", null, -80.0)
	_music_b = _player("Music", null, -80.0)
	_music_active = _music_a
	if not OS.get_cmdline_user_args().has("--no-music"):
		for i in range(1, 7):
			if _music_path(i) != "":
				_has_music = true
	# Синтез звуков занимает несколько секунд, пока игрок смотрит на стартовый экран.
	# Где есть потоки — он идёт в фоне; в браузере потоков нет, там он идёт
	# маленькими шагами между кадрами, чтобы экран не замирал.
	_steps = _synth_steps()
	_synth_ms = Time.get_ticks_msec()
	if not OS.has_feature("web"):
		_thread = Thread.new()
		_thread.start(_run_steps)


func _run_steps() -> void:
	while _step_i < _steps.size():
		_steps[_step_i].call()
		_step_i += 1


func _process(_delta: float) -> void:
	if _save_at >= 0 and Time.get_ticks_msec() >= _save_at:
		_save_volume()
	if _thread != null:
		if not _thread.is_alive():
			_thread.wait_to_finish()
			_thread = null
			_finish_synthesis()
	elif _poly == null:
		var t0 := Time.get_ticks_usec()
		while _step_i < _steps.size() and Time.get_ticks_usec() - t0 < 6000:
			_steps[_step_i].call()
			_step_i += 1
		if _step_i == _steps.size():
			_finish_synthesis()
	ready_progress = float(_step_i) / _steps.size()


## Все звуки готовы: запускаем эмбиент и колокольчики.
func is_ready() -> bool:
	return _poly != null


func _finish_synthesis() -> void:
	_pad = _player("Ambience", _made["pad"], -40.0)
	_hiss = _player("Ambience", _made["hiss"], -40.0)
	_pad.play()
	_hiss.play()
	_shift = _player("Chimes", _made["shift"], -80.0)
	_shift.play()
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 24
	_chimes = _player("Chimes", poly, 0.0)
	_chimes.play()
	_poly = _chimes.get_stream_playback()
	prime_music()
	print("SOUNDS_READY in %.1f s" % ((Time.get_ticks_msec() - _synth_ms) / 1000.0))


## Беззвучно запускаем первый трек заранее. При запуске mp3 файл просматривается
## целиком (в браузере — полсекунды); пусть это случится на стартовом экране или во
## время «вдоха», а не в кадре вспышки. Громкость поднимет _update_music.
func prime_music() -> void:
	var s := _music_stream(1)
	var idle := _music_b if _music_active == _music_a else _music_a
	if s == null or (idle.stream == s and idle.playing):
		return
	s.set("loop", true)
	idle.stream = s
	idle.volume_db = -80.0
	idle.play()


func _exit_tree() -> void:
	if _save_at >= 0:
		_save_volume()
	if _thread != null:
		_thread.wait_to_finish()
	# Останавливаем звук и отпускаем потоки — иначе при выходе они числятся утечками.
	for c in get_children():
		if c is AudioStreamPlayer:
			c.stop()
			c.stream = null
	_poly = null
	_made.clear()
	_bells.clear()


## Громкость музыки 0…1; громкость на шине идёт по кривой громкости (в дБ).
func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_music_volume()
	# Пока тянут ползунок, файл не переписываем — сохраняем через полсекунды покоя.
	_save_at = Time.get_ticks_msec() + 500


## M: выключить музыку или вернуть прежнюю громкость.
func toggle_music_mute() -> float:
	if music_volume > 0.0:
		_volume_before_mute = music_volume
		set_music_volume(0.0)
	else:
		set_music_volume(maxf(_volume_before_mute, 0.05))
	return music_volume


func _apply_music_volume() -> void:
	var bus := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_mute(bus, music_volume <= 0.0)
	AudioServer.set_bus_volume_db(bus, MUSIC_BUS_DB + linear_to_db(maxf(music_volume, 0.001)))


func _save_volume() -> void:
	_save_at = -1
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.save(SETTINGS)


func _player(bus: String, stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func _setup_buses() -> void:
	for spec in [["Music", -4.0], ["Ambience", -6.0], ["Chimes", -9.0]]:
		var name: String = spec[0]
		if AudioServer.get_bus_index(name) != -1:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")
		AudioServer.set_bus_volume_db(idx, spec[1])
	var amb := AudioServer.get_bus_index("Ambience")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 3000.0
	AudioServer.add_bus_effect(amb, _lowpass)
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.95
	rev.damping = 0.35
	rev.spread = 1.0
	rev.wet = 0.55
	rev.dry = 0.75
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Chimes"), rev)
	_reverb = rev
	_music_lp = AudioEffectLowPassFilter.new()
	_music_lp.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Music"), _music_lp)


# ---------------------------------------------------------------- синтез

## Порядок синтеза: сначала звуки запуска — они нужны первыми.
func _synth_steps() -> Array[Callable]:
	var steps: Array[Callable] = [_make_swell, _make_boom]
	for key in BELLS:
		for spec in BELLS[key]:
			steps.append(_make_bell.bind(key, spec))
	_pad_buf.resize(8 * RATE)
	for v in PAD_VOICES:
		steps.append(_tone.bind(_pad_buf, float(v[0]), float(v[1])))
	steps.append(_finish_pad)
	_shift_buf.resize(4 * RATE)
	for v in SHIFT_VOICES:
		steps.append(_tone.bind(_shift_buf, float(v[0]), float(v[1])))
	steps.append(_finish_shift)
	steps.append(_make_noise)
	return steps


func _wav(samples: PackedFloat32Array, loop: bool, gain: float = 1.0) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


## Колокольчик: несколько обертонов с экспоненциальным затуханием.
func _bell(freqs: Array, dur: float, bright: float = 1.0) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var partials := [[1.0, 1.0, 1.0], [2.0, 0.32 * bright, 1.8], [3.01, 0.12 * bright, 2.7], [4.17, 0.05 * bright, 3.6]]
	var tau := dur / 5.0
	for f in freqs:
		for pr in partials:
			# Осциллятор поворотом вектора — без sin()/exp() на каждый сэмпл.
			var w: float = TAU * float(f) * float(pr[0]) / RATE
			var decay: float = 1.0 / (tau / float(pr[2]) * RATE)
			var cr := cos(w)
			var sr := sin(w)
			var dk := exp(-decay)
			var c := 1.0
			var s := 0.0
			var env: float = pr[1]
			for i in mini(n, int(7.0 / decay)):
				out[i] += s * env
				var nc := c * cr - s * sr
				s = c * sr + s * cr
				c = nc
				env *= dk
	var peak := 0.0
	for i in n:
		var env := minf(1.0, i / (0.006 * RATE))
		out[i] *= env
		peak = maxf(peak, absf(out[i]))
	var g := 0.5 / maxf(peak, 1.0e-6)
	for i in n:
		out[i] *= g
	return _wav(out, false)


## Аккорд ми-мажор (E2 B2 E3 G#3) с медленными биениями; длина 8 с, частоты кратны 1/8 Гц,
## поэтому петля бесшовная.
const PAD_VOICES := [[82.375, 0.5], [82.625, 0.35], [123.5, 0.35], [164.75, 0.25], [165.0, 0.18], [207.625, 0.12]]
## Тон смещения: линия H-альфа (415 Гц) с октавой и квинтой и медленными биениями.
## Длина петли 4 с, частоты кратны 1/4 Гц — петля бесшовная.
const SHIFT_VOICES := [[415.25, 0.5], [415.75, 0.35], [830.5, 0.14], [622.75, 0.1]]


## Добавить к буферу синусоиду: осциллятор поворотом вектора, без sin() на каждый сэмпл.
static func _tone(out: PackedFloat32Array, freq: float, amp: float) -> void:
	var w := TAU * freq / RATE
	var cr := cos(w)
	var sr := sin(w)
	var c := 1.0
	var s := 0.0
	for i in out.size():
		out[i] += amp * s
		var nc := c * cr - s * sr
		s = c * sr + s * cr
		c = nc


func _finish_pad() -> void:
	var lfo_w := TAU * 0.25 / RATE
	var peak := 0.0
	for i in _pad_buf.size():
		_pad_buf[i] *= 0.8 + 0.2 * sin(lfo_w * i)
		peak = maxf(peak, absf(_pad_buf[i]))
	_made["pad"] = _wav(_pad_buf, true, 0.6 / peak)


func _finish_shift() -> void:
	var peak := 0.0
	for i in _shift_buf.size():
		peak = maxf(peak, absf(_shift_buf[i]))
	_made["shift"] = _wav(_shift_buf, true, 0.5 / peak)


func _make_noise() -> void:
	_made["hiss"] = _noise_loop()


## «Вдох» перед взрывом: шум, который за 0,8 с становится громче и ярче, и тон, ползущий вверх.
func _make_swell() -> void:
	var n := int(0.8 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var k := float(i) / n
		ph += TAU * (35.0 + 80.0 * k * k) / RATE
		lp += (0.01 + 0.3 * k * k) * ((randf() * 2.0 - 1.0) - lp)
		var env := k * k * k * minf(1.0, (n - i) / (0.02 * RATE))
		out[i] = env * (0.5 * sin(ph) + 1.4 * lp)
	_made["swell"] = _wav(out, false, 0.8)


## Удар Большого взрыва: низкий тон, падающий с 100 до 26 Гц, вспышка шума под
## закрывающимся фильтром — удар «тускнеет», как остывающий свет, — и долгий рокот.
func _make_boom() -> void:
	var n := 7 * RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var lp := 0.0
	var brown := 0.0
	var peak := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * (26.0 + 74.0 * exp(-t / 0.35)) / RATE
		var wn := randf() * 2.0 - 1.0
		lp += (0.02 + 0.5 * exp(-t / 0.25)) * (wn - lp)
		brown += 0.02 * (wn - brown)
		var v := minf(1.0, t / 0.004) * (0.9 * sin(ph) * exp(-t / 1.8) + 0.7 * lp * exp(-t / 0.9) + 1.6 * brown * exp(-t / 2.5))
		out[i] = v
		peak = maxf(peak, absf(v))
	_made["boom"] = _wav(out, false, 0.95 / peak)


func play_swell() -> void:
	_oneshot(_made.get("swell"), -5.0)


func play_boom() -> void:
	_oneshot(_made.get("boom"), 0.0)


func _oneshot(stream: AudioStream, db: float) -> void:
	if stream == null:
		return
	var p := _player("Master", stream, db)
	p.finished.connect(p.queue_free)
	p.play()


## Шорох плазмы: сглаженный шум с перекрёстным затуханием на стыке петли.
func _noise_loop() -> AudioStreamWAV:
	var n := 4 * RATE
	var fade := RATE / 2
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var y := 0.0
	for i in raw.size():
		y += 0.08 * ((randf() * 2.0 - 1.0) - y)
		raw[i] = y * 3.0
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		if i < fade:
			var k := float(i) / fade
			out[i] = raw[i] * k + raw[n + i] * (1.0 - k)
		else:
			out[i] = raw[i]
	return _wav(out, true)


## Колокольчики реакций: варианты [частоты, длительность, яркость обертонов].
const BELLS := {
	"hadron": [[[82.41], 3.0, 0.6], [[123.47], 3.0, 0.6], [[164.81], 3.0, 0.6]],
	"n_to_p": [[[987.77], 0.9, 0.3], [[1108.73], 0.9, 0.3]],
	"pn_D": [[[246.94], 2.2, 1.0], [[277.18], 2.2, 1.0]],
	"DD": [[[329.63], 2.5, 1.0], [[369.99], 2.5, 1.0]],
	"A3D": [[[415.30, 659.26], 4.0, 1.3], [[493.88, 739.99], 4.0, 1.3]],
	"Li": [[[554.37, 830.61], 4.5, 1.4]],
	"recH": [[[415.3], 3.0, 0.5], [[560.9], 3.0, 0.5]],
	"recHe": [[[408.3], 3.2, 0.5], [[554.0], 3.2, 0.5]],
	"flicker": [[[739.99], 0.6, 0.2], [[830.61], 0.6, 0.2]],
	"split": [[[61.74], 1.5, 0.4]],
	"detent": [[[1318.51], 0.7, 0.3]],
	"touch": [[[329.63, 493.88], 2.5, 0.5]],
	"hover": [[[164.81], 3.0, 0.25]],
}

## Ступени пентатоники (в полутонах): каждый клик по точке звучит на ступень выше.
const TOUCH_STEPS := [0, 2, 4, 7, 9, 12]


## Отклик точки на стартовом экране: чем ближе к пробуждению, тем выше и громче.
func play_touch(level: float, hover: bool) -> void:
	var key := "hover" if hover else "touch"
	if _poly == null or not _bells.has(key):
		return
	var step: int = TOUCH_STEPS[clampi(roundi(level * 5.0), 0, 5)]
	var db := -20.0 if hover else -13.0 + 7.0 * level
	_poly.play_stream(_bells[key][0], 0.0, db, pow(2.0, step / 12.0))


func _make_bell(key: String, spec: Array) -> void:
	if not _bells.has(key):
		_bells[key] = []
	_bells[key].append(_bell(spec[0], spec[1], spec[2]))


# ---------------------------------------------------------------- управление

const VOLUMES := {"hadron": -16.0, "n_to_p": -24.0, "pn_D": -12.0, "DD": -12.0, "A3D": -6.0,
	"Li": -4.0, "recH": -15.0, "recHe": -12.0, "flicker": -26.0, "split": -18.0, "detent": -14.0}
const RATES := {"hadron": 0.18, "n_to_p": 0.3, "pn_D": 0.25, "DD": 0.25, "A3D": 0.35,
	"Li": 0.5, "recH": 0.16, "recHe": 0.3, "flicker": 0.2, "split": 0.4, "detent": 0.15}
const SOUND_OF := {"DDn": "DD", "DDp": "DD", "Dp": "DD", "Dn": "DD", "He3n": "DD",
	"A3Dn": "A3D", "A3Dp": "A3D", "A3n": "A3D", "A3p": "A3D"}


func play_event(channel: String) -> void:
	# Реакции, рождающие ядра с A = 3, звучат как D + D, а рождающие гелий-4 — как ³He + D.
	var key: String = SOUND_OF.get(channel, channel)
	if channel.ends_with("_split") or channel == "p_to_n":
		key = "split"
	if not _bells.has(key) or _poly == null:
		return
	var now := _clock
	if now < float(_cooldown.get(key, 0.0)) or _budget > 6.0:
		return
	_cooldown[key] = now + float(RATES[key])
	_budget += 1.0
	var variants: Array = _bells[key]
	var stream: AudioStreamWAV = variants[randi() % variants.size()]
	_poly.play_stream(stream, 0.0, float(VOLUMES[key]) + randf_range(-2.0, 1.0), 1.0 + randf_range(-0.004, 0.004))


## Игрок двигает «темп расширения»: тон скользит от точки, где он начал тянуть.
## Быстрее расширение — длиннее волны — ниже тон (красное смещение), и наоборот.
func nudge_expansion(value: float) -> void:
	if _clock - _shift_last > 1.2:
		_shift_anchor = value
	_shift_last = _clock
	_shift_pitch = clampf(pow(2.0, -(value - _shift_anchor) * 0.9), 0.4, 2.2)


## Тихий отклик, когда ползунок «прилипает» к значению нашей Вселенной.
func play_detent() -> void:
	play_event("detent")


## Вызывается каждый кадр: подстраивает эмбиент под температуру и эпоху.
func set_state(lt: float, fog: float, epoch: int, delta: float, expansion: float = 1.0, touch: float = 0.0, density_log: float = 0.0) -> void:
	_clock += delta
	_budget = maxf(0.0, _budget - delta * 4.0)
	_update_music(epoch, delta)
	# Музыка постоянно чуть смещена по высоте: быстрое расширение — ниже, сжатие — выше.
	_music_pitch = lerpf(_music_pitch, clampf(1.0 - 0.05 * (expansion - 1.0), 0.9, 1.1), delta * 1.5)
	_music_a.pitch_scale = _music_pitch
	_music_b.pitch_scale = _music_pitch
	# Плотность: плотнее — глуше и суше, разреженнее — длинное эхо.
	var dense := clampf(density_log, -1.0, 1.0)
	_reverb.wet = lerpf(_reverb.wet, 0.55 - 0.3 * dense, delta * 2.0)
	_reverb.room_size = lerpf(_reverb.room_size, clampf(0.95 - 0.25 * dense, 0.6, 0.99), delta * 2.0)
	_music_lp.cutoff_hz = lerpf(_music_lp.cutoff_hz, lerpf(20000.0, 3500.0, maxf(dense, 0.0)), delta * 2.0)
	if _shift != null:
		var active := _clock - _shift_last < 0.35
		_shift.volume_db = lerpf(_shift.volume_db, -16.0 if active else -70.0, delta * (8.0 if active else 1.5))
		_shift.pitch_scale = lerpf(_shift.pitch_scale, _shift_pitch, delta * 10.0)
	if _pad == null:
		return
	var heat := clampf((lt - 2.5) / 10.5, 0.0, 1.0)
	# Расширение звучит как красное смещение: быстрее расширяешь — ниже тон.
	_pad.pitch_scale = lerpf(_pad.pitch_scale, lerpf(0.75, 1.0, heat) * clampf(1.0 - 0.06 * (expansion - 1.0), 0.85, 1.12), delta * 2.0)
	_lowpass.cutoff_hz = lerpf(500.0, 5000.0, heat)
	# Под музыку эмбиент тише; если музыку убавили, он возвращается.
	var music_duck := -8.0 * music_volume if _has_music else 0.0
	_pad.volume_db = lerpf(_pad.volume_db, -10.0 + music_duck - (1.0 - heat) * 6.0, delta)
	_hiss.volume_db = lerpf(_hiss.volume_db, linear_to_db(maxf(fog * heat + touch * 0.6, 0.002)) - 16.0 + music_duck, delta * (1.0 + 3.0 * touch))


func _music_path(epoch_num: int) -> String:
	for ext in ["ogg", "mp3", "wav"]:
		var path := "%sepoch_%d.%s" % [MUSIC_DIR, epoch_num, ext]
		if ResourceLoader.exists(path):
			return path
	return ""


## Трек загружаем только когда он нужен: все шесть сразу — лишние секунды на старте.
func _music_stream(epoch_num: int) -> AudioStream:
	if _music_cache.has(epoch_num):
		return _music_cache[epoch_num]
	var path := _music_path(epoch_num)
	var s: AudioStream = load(path) if path != "" and _has_music else null
	if epoch_num == 1:
		_music_cache[1] = s   # первый трек нужен мгновенно — при каждом запуске Вселенной
	return s


func _update_music(epoch: int, delta: float) -> void:
	if not _has_music:
		return
	if epoch != _music_epoch:
		_music_epoch = epoch
		var s := _music_stream(epoch + 1)
		if s != null:
			if s is AudioStreamOggVorbis or s is AudioStreamMP3:
				s.set("loop", true)
			var next := _music_b if _music_active == _music_a else _music_a
			if next.stream != s or not next.playing:   # иначе трек уже запущен prime_music()
				next.stream = s
				next.volume_db = -60.0
				next.play()
			_music_active = next
	var other := _music_b if _music_active == _music_a else _music_a
	_music_active.volume_db = lerpf(_music_active.volume_db, 0.0, delta * 0.4)
	other.volume_db = lerpf(other.volume_db, -60.0, delta * 0.4)
	if other.volume_db < -55.0 and other.playing:
		other.stop()
