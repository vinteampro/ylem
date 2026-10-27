extends Control
## Интерфейс: шкала космического времени, показания приборов, состав вещества,
## рычаги, реплики рассказчика, карточки кодекса и экран итогов.
## Всё собирается в коде, чтобы прототип был одним понятным файлом.

signal expansion_changed(value: float)
signal density_changed(log_mult: float)
signal speed_changed(value: float)
signal music_volume_changed(value: float)
signal pause_toggled
signal autopilot_toggled(on: bool)
signal restart_requested
signal continue_requested
signal language_toggled
signal detent

const Fmt := preload("res://scripts/fmt.gd")
const I18n := preload("res://scripts/i18n.gd")

const ACCENT := Color(1.0, 0.84, 0.6)
const TEXT := Color(0.88, 0.9, 0.97, 0.94)
const DIM := Color(0.75, 0.78, 0.88, 0.62)

var font_light: Font
var font_regular: Font
var font_semi: Font
var font_caps: Font

var _root: Control
var _epoch_num: Label
var _epoch_title: Label
var _readout: Label
var _timeline: Timeline
var _composition: Composition
var _narration: Label
var _card: VBoxContainer
var _card_num: Label
var _card_title: Label
var _card_sub: Label
var _codex: PanelContainer
var _codex_title: Label
var _codex_text: Label
var _inspect: PanelContainer
var _inspect_title: Label
var _inspect_text: Label
var _end: PanelContainer
var _end_grid: GridContainer
var _end_verdict: Label
var _sl_exp: HSlider
var _sl_den: HSlider
var _sl_speed: HSlider
var _sl_music: HSlider
var _lb_exp: Label
var _lb_den: Label
var _lb_speed: Label
var _lb_music: Label
var _btn_pause: Button
var _btn_auto: Button

var _lines: Array[String] = []
var _line_timer := 0.0
var _codex_queue: Array = []
var _codex_timer := 0.0
var _card_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_make_fonts()
	theme = _make_theme()

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_timeline()
	_build_header()
	_build_composition()
	_build_controls()
	_build_narration()
	_build_codex()
	_build_inspect()
	_build_card()
	_build_end()


# ---------------------------------------------------------------- шрифты и тема

func _sys_font(weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI", "Helvetica Neue", "Arial", "Noto Sans"])
	f.font_weight = weight
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f


func _make_fonts() -> void:
	font_light = _sys_font(300)
	font_regular = _sys_font(400)
	font_semi = _sys_font(600)
	var caps := FontVariation.new()
	caps.base_font = _sys_font(600)
	caps.spacing_glyph = 3
	font_caps = caps
	if OS.has_feature("web") or not font_regular.has_char(0x207B):
		Fmt.sup_minus = "¯"
	if OS.has_feature("web") or not font_regular.has_char(0x2192):
		Fmt.arrow = "»"


func _dot_tex(size: int, col: Color) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var r := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(r - 1.0 - d, 0.0, 1.0) * col.a))
	return ImageTexture.create_from_image(img)


func _box(bg: Color, border: Color, radius: int, margin: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1 if border.a > 0.0 else 0)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = font_regular
	th.default_font_size = 17
	th.set_color("font_color", "Label", TEXT)
	th.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	th.set_constant("shadow_outline_size", "Label", 4)
	th.set_constant("shadow_offset_x", "Label", 0)
	th.set_constant("shadow_offset_y", "Label", 1)
	th.set_stylebox("panel", "PanelContainer", _box(Color(0.012, 0.012, 0.035, 0.78), Color(1, 1, 1, 0.08), 14, 20.0))

	var track := _box(Color(1, 1, 1, 0.13), Color(0, 0, 0, 0), 2, 0.0)
	track.content_margin_top = 2.0
	track.content_margin_bottom = 2.0
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.5)
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	th.set_icon("grabber", "HSlider", _dot_tex(16, Color(1.0, 0.93, 0.82)))
	th.set_icon("grabber_highlight", "HSlider", _dot_tex(18, Color(1.0, 1.0, 1.0)))
	th.set_icon("grabber_disabled", "HSlider", _dot_tex(16, Color(1, 1, 1, 0.4)))
	th.set_stylebox("focus", "HSlider", StyleBoxEmpty.new())

	th.set_stylebox("normal", "Button", _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.13), 8, 9.0))
	th.set_stylebox("hover", "Button", _box(Color(1, 1, 1, 0.09), Color(1, 1, 1, 0.22), 8, 9.0))
	th.set_stylebox("pressed", "Button", _box(Color(1.0, 0.8, 0.5, 0.16), Color(1.0, 0.8, 0.5, 0.45), 8, 9.0))
	th.set_stylebox("hover_pressed", "Button", _box(Color(1.0, 0.8, 0.5, 0.22), Color(1.0, 0.8, 0.5, 0.55), 8, 9.0))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", Color(1, 1, 1))
	th.set_color("font_pressed_color", "Button", ACCENT)
	th.set_color("font_hover_pressed_color", "Button", ACCENT)
	th.set_font_size("font_size", "Button", 15)
	return th


func _label(text: String, font: Font, size: int, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------- построение

func _build_timeline() -> void:
	_timeline = Timeline.new()
	_timeline.font = font_regular
	_timeline.anchor_right = 1.0
	_timeline.offset_left = 48.0
	_timeline.offset_right = -48.0
	_timeline.offset_top = 18.0
	_timeline.offset_bottom = 58.0
	_timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_timeline)


func _build_header() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(48.0, 76.0)
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_epoch_num = _label("", font_caps, 14, ACCENT)
	_epoch_title = _label("", font_light, 38)
	_readout = _label("", font_regular, 17, Color(0.86, 0.88, 0.95, 0.85))
	box.add_child(_epoch_num)
	box.add_child(_epoch_title)
	box.add_child(_readout)
	_root.add_child(box)


func _build_composition() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -440.0
	panel.offset_right = -40.0
	panel.offset_top = 76.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(_label(I18n.t("composition"), font_caps, 13, ACCENT))
	_composition = Composition.new()
	_composition.font = font_regular
	_composition.font_value = font_semi
	_composition.custom_minimum_size = Vector2(360.0, 40.0)
	v.add_child(_composition)
	panel.add_child(v)
	_root.add_child(panel)


func _slider_row(parent: VBoxContainer, title: String, mn: float, mx: float, step: float, value: float) -> Array:
	var head := HBoxContainer.new()
	var t := _label(title, font_regular, 16)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := _label("", font_semi, 15, ACCENT)
	head.add_child(t)
	head.add_child(val)
	parent.add_child(head)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(0.0, 22.0)
	parent.add_child(s)
	return [s, val]


func _build_controls() -> void:
	var panel := PanelContainer.new()
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 40.0
	panel.offset_right = 520.0
	panel.offset_bottom = -40.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(_label(I18n.t("controls"), font_caps, 13, ACCENT))

	var r := _slider_row(v, I18n.t("expansion"), -1.0, 2.5, 0.01, 1.0)
	_sl_exp = r[0]
	_lb_exp = r[1]
	r = _slider_row(v, I18n.t("density"), -1.0, 1.0, 0.01, 0.0)
	_sl_den = r[0]
	_lb_den = r[1]
	r = _slider_row(v, I18n.t("speed"), 0.0, 2.0, 0.05, 1.0)
	_sl_speed = r[0]
	_lb_speed = r[1]
	_sl_exp.value_changed.connect(func(x: float) -> void:
		x = _snap(_sl_exp, x, 1.0, 0.05)
		_refresh_slider_labels()
		expansion_changed.emit(x))
	_sl_den.value_changed.connect(func(x: float) -> void:
		x = _snap(_sl_den, x, 0.0, 0.05)
		_refresh_slider_labels()
		density_changed.emit(x))
	_sl_speed.value_changed.connect(func(x: float) -> void:
		x = _snap(_sl_speed, x, 1.0, 0.05)
		_refresh_slider_labels()
		speed_changed.emit(x))
	r = _slider_row(v, I18n.t("music"), 0.0, 1.0, 0.01, 1.0)
	_sl_music = r[0]
	_lb_music = r[1]
	_sl_music.value_changed.connect(func(x: float) -> void:
		_refresh_slider_labels()
		music_volume_changed.emit(x))
	for item in [[_sl_exp, 1.0], [_sl_den, 0.0], [_sl_speed, 1.0], [_sl_music, 1.0]]:
		_fine_control(item[0], item[1])

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_btn_pause = Button.new()
	_btn_pause.text = I18n.t("pause")
	_btn_pause.toggle_mode = true
	_btn_pause.focus_mode = Control.FOCUS_NONE
	_btn_pause.pressed.connect(func() -> void: pause_toggled.emit())
	_btn_auto = Button.new()
	_btn_auto.text = I18n.t("release")
	_btn_auto.tooltip_text = I18n.t("release_tip")
	_btn_auto.toggle_mode = true
	_btn_auto.focus_mode = Control.FOCUS_NONE
	_btn_auto.toggled.connect(func(on: bool) -> void: autopilot_toggled.emit(on))
	var hide_btn := Button.new()
	hide_btn.text = I18n.t("hide")
	hide_btn.focus_mode = Control.FOCUS_NONE
	hide_btn.pressed.connect(toggle_visible)
	var lang_btn := Button.new()
	lang_btn.text = I18n.t("lang_button")
	lang_btn.focus_mode = Control.FOCUS_NONE
	lang_btn.pressed.connect(func() -> void: language_toggled.emit())
	buttons.add_child(_btn_pause)
	buttons.add_child(_btn_auto)
	buttons.add_child(hide_btn)
	buttons.add_child(lang_btn)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	v.add_child(spacer)
	v.add_child(buttons)
	var hint := _label(I18n.t("mouse_hint"),
		font_regular, 13, Color(0.8, 0.83, 0.92, 0.55))
	v.add_child(hint)
	panel.add_child(v)
	_root.add_child(panel)
	_refresh_slider_labels()


## «Магнит»: рядом со значением нашей Вселенной ползунок прилипает к нему.
var _at_ours: Dictionary = {}


func _snap(s: HSlider, x: float, ours: float, width: float) -> float:
	var at := absf(x - ours) < width
	if at and x != ours:
		s.set_value_no_signal(ours)
		x = ours
	if at and not bool(_at_ours.get(s, true)):
		detent.emit()
	_at_ours[s] = at
	return x


## Двойной клик — вернуть значение нашей Вселенной; колесо — шаг, с Shift — мелкий шаг.
func _fine_control(s: HSlider, ours: float) -> void:
	s.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb == null or not mb.pressed:
			return
		if mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
			s.value = ours
			s.accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var dir := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			var stride := s.step if mb.shift_pressed else (s.max_value - s.min_value) / 40.0
			s.value += dir * stride
			s.accept_event())


func _refresh_slider_labels() -> void:
	var e := _sl_exp.value
	var mood := I18n.t("mood_ours")
	if e < 0.0:
		mood = I18n.t("mood_contract")
	elif e < 0.85:
		mood = I18n.t("mood_slow")
	elif e > 1.15:
		mood = I18n.t("mood_fast")
	_lb_exp.text = "%s ×%s" % [mood, Fmt.comma("%.2f" % e)]
	var mult := pow(10.0, _sl_den.value)
	_lb_den.text = "η = %s  (×%s)" % [Fmt.sci(6.12e-10 * mult, 2), Fmt.comma("%.2f" % mult)]
	_lb_speed.text = I18n.t("paused") if _sl_speed.value <= 0.0 else "×" + Fmt.comma("%.2f" % _sl_speed.value)
	_lb_music.text = I18n.t("music_off") if _sl_music.value <= 0.0 else "%d%%" % roundi(_sl_music.value * 100.0)


func _build_narration() -> void:
	_narration = _label("", font_light, 25, Color(0.97, 0.97, 1.0))
	_narration.anchor_left = 0.5
	_narration.anchor_right = 0.5
	_narration.anchor_top = 1.0
	_narration.anchor_bottom = 1.0
	_narration.offset_left = -470.0
	_narration.offset_right = 470.0
	_narration.offset_top = -170.0
	_narration.offset_bottom = -50.0
	_narration.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_narration.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_narration.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_narration.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	_narration.add_theme_constant_override("outline_size", 3)
	_narration.modulate.a = 0.0
	_root.add_child(_narration)


func _build_codex() -> void:
	_codex = PanelContainer.new()
	_codex.anchor_left = 1.0
	_codex.anchor_right = 1.0
	_codex.anchor_top = 1.0
	_codex.anchor_bottom = 1.0
	_codex.offset_left = -440.0
	_codex.offset_right = -40.0
	_codex.offset_bottom = -40.0
	_codex.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_codex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(_label(I18n.t("discovered"), font_caps, 12, ACCENT))
	_codex_title = _label("", font_semi, 21)
	_codex_text = _label("", font_light, 16, Color(0.86, 0.88, 0.95, 0.85))
	_codex_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_codex_text.custom_minimum_size = Vector2(360.0, 0.0)
	v.add_child(_codex_title)
	v.add_child(_codex_text)
	_codex.add_child(v)
	_codex.modulate.a = 0.0
	_root.add_child(_codex)


func _build_inspect() -> void:
	_inspect = PanelContainer.new()
	_inspect.anchor_left = 1.0
	_inspect.anchor_right = 1.0
	_inspect.offset_left = -440.0
	_inspect.offset_right = -40.0
	_inspect.offset_top = 520.0
	_inspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(_label(I18n.t("observing"), font_caps, 12, ACCENT))
	_inspect_title = _label("", font_semi, 21)
	_inspect_text = _label("", font_light, 15, Color(0.86, 0.88, 0.95, 0.85))
	_inspect_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspect_text.custom_minimum_size = Vector2(360.0, 0.0)
	v.add_child(_inspect_title)
	v.add_child(_inspect_text)
	_inspect.add_child(v)
	_inspect.visible = false
	_root.add_child(_inspect)


func _build_card() -> void:
	_card = VBoxContainer.new()
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 0.5
	_card.anchor_bottom = 0.5
	_card.offset_left = -600.0
	_card.offset_right = 600.0
	_card.offset_top = -110.0
	_card.offset_bottom = 60.0
	_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_num = _label("", font_caps, 18, ACCENT)
	_card_title = _label("", font_light, 64)
	_card_sub = _label("", font_light, 22, DIM)
	for l in [_card_num, _card_title, _card_sub]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.3))
		l.add_theme_constant_override("outline_size", 4)
		_card.add_child(l)
	_card.modulate.a = 0.0
	add_child(_card)  # не прячется по H


func _build_end() -> void:
	_end = PanelContainer.new()
	_end.anchor_left = 0.5
	_end.anchor_right = 0.5
	_end.anchor_top = 0.5
	_end.anchor_bottom = 0.5
	_end.offset_left = -380.0
	_end.offset_right = 380.0
	_end.offset_top = -250.0
	_end.offset_bottom = 250.0
	_end.add_theme_stylebox_override("panel", _box(Color(0.02, 0.02, 0.05, 0.72), Color(1, 1, 1, 0.1), 16, 30.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.add_child(_label(I18n.t("result"), font_caps, 13, ACCENT))
	v.add_child(_label(I18n.t("your_universe"), font_light, 40))
	_end_grid = GridContainer.new()
	_end_grid.columns = 3
	_end_grid.add_theme_constant_override("h_separation", 34)
	_end_grid.add_theme_constant_override("v_separation", 8)
	v.add_child(_end_grid)
	_end_verdict = _label("", font_light, 18)
	_end_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_verdict.custom_minimum_size = Vector2(680.0, 0.0)
	v.add_child(_end_verdict)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var again := Button.new()
	again.text = I18n.t("again")
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(func() -> void: restart_requested.emit())
	var stay := Button.new()
	stay.text = I18n.t("stay")
	stay.focus_mode = Control.FOCUS_NONE
	stay.pressed.connect(func() -> void:
		_end.visible = false
		continue_requested.emit())
	buttons.add_child(again)
	buttons.add_child(stay)
	v.add_child(buttons)
	_end.add_child(v)
	_end.visible = false
	add_child(_end)


# ---------------------------------------------------------------- API для main

func set_cinematic(on: bool) -> void:
	for c in _root.get_children():
		if c != _narration and c != _inspect:
			c.visible = not on


func toggle_visible() -> void:
	_root.visible = not _root.visible


func set_epoch(num: String, title: String) -> void:
	_epoch_num.text = num.to_upper()
	_epoch_title.text = title


func set_readout(text: String) -> void:
	_readout.text = text


func set_time(log_t: float) -> void:
	_timeline.log_t = log_t
	_timeline.queue_redraw()


func set_rows(rows: Array) -> void:
	_composition.rows = rows
	_composition.custom_minimum_size.y = rows.size() * 46.0
	_composition.queue_redraw()


func set_controls(expansion: float, density_log: float, speed: float) -> void:
	_sl_exp.set_value_no_signal(expansion)
	_sl_den.set_value_no_signal(density_log)
	_sl_speed.set_value_no_signal(speed)
	_refresh_slider_labels()


func set_music_volume(v: float) -> void:
	_sl_music.set_value_no_signal(v)
	_refresh_slider_labels()


func set_paused(on: bool) -> void:
	_btn_pause.set_pressed_no_signal(on)


func set_autopilot(on: bool) -> void:
	_btn_auto.set_pressed_no_signal(on)


func say(text: String) -> void:
	if not _lines.has(text):
		# Если события обгоняют рассказчика, устаревшие реплики выбрасываем.
		if _lines.size() >= 2:
			_lines.pop_front()
		_lines.append(text)


func show_inspect(title: String, lines: Array[String]) -> void:
	_inspect.visible = true
	_inspect_title.text = title
	_inspect_text.text = "\n".join(lines)


func hide_inspect() -> void:
	_inspect.visible = false


func show_codex(title: String, text: String) -> void:
	_codex_queue.append([title, text])


func show_card(num: String, title: String, sub: String) -> void:
	_card_num.text = num.to_upper()
	_card_title.text = title
	_card_sub.text = sub
	if _card_tween:
		_card_tween.kill()
	_card_tween = create_tween()
	_card_tween.tween_property(_card, "modulate:a", 1.0, 1.6).set_trans(Tween.TRANS_SINE)
	_card_tween.tween_interval(3.2)
	_card_tween.tween_property(_card, "modulate:a", 0.0, 2.0).set_trans(Tween.TRANS_SINE)


func show_results(rows: Array, verdict: String) -> void:
	for c in _end_grid.get_children():
		c.queue_free()
	for head in ["", I18n.t("yours"), I18n.t("ours")]:
		_end_grid.add_child(_label(head.to_upper(), font_caps, 12, ACCENT))
	for r in rows:
		_end_grid.add_child(_label(r[0], font_regular, 17, DIM))
		_end_grid.add_child(_label(r[1], font_semi, 17))
		_end_grid.add_child(_label(r[2], font_regular, 17, DIM))
	_end_verdict.text = verdict
	_end.modulate.a = 0.0
	_end.visible = true
	create_tween().tween_property(_end, "modulate:a", 1.0, 2.0)


func hide_results() -> void:
	_end.visible = false


func clear_messages() -> void:
	_lines.clear()
	_codex_queue.clear()
	_line_timer = 0.0
	_codex_timer = 0.0
	_narration.modulate.a = 0.0
	_codex.modulate.a = 0.0


# ---------------------------------------------------------------- реплики и кодекс

func _process(delta: float) -> void:
	# Реплика: проявляется, держится, растворяется; следующая — после паузы.
	if _line_timer > 0.0:
		_line_timer -= delta
		var shown := 7.5 - _line_timer
		_narration.modulate.a = clampf(minf(shown / 1.4, _line_timer / 1.6), 0.0, 1.0)
	elif not _lines.is_empty():
		_narration.text = _lines.pop_front()
		_line_timer = 7.5
	if _codex_timer > 0.0:
		_codex_timer -= delta
		var shown_c := 9.0 - _codex_timer
		_codex.modulate.a = clampf(minf(shown_c / 1.0, _codex_timer / 1.5), 0.0, 1.0)
	elif not _codex_queue.is_empty():
		var item: Array = _codex_queue.pop_front()
		_codex_title.text = item[0]
		_codex_text.text = item[1]
		_codex_timer = 9.0


# ---------------------------------------------------------------- рисованные элементы

## Логарифмическая шкала времени от микросекунды до миллиона лет.
class Timeline extends Control:
	const LMIN := -6.0
	const LMAX := 14.0
	const TICKS := [[-6.0, "tick_us"], [-3.0, "tick_ms"], [0.0, "tick_s"], [1.778, "tick_min"], [3.556, "tick_h"],
		[4.936, "tick_day"], [7.499, "tick_year"], [10.499, "tick_kyr"], [13.499, "tick_myr"]]
	const MARKS := [[-4.73, "mark_hadrons"], [2.4, "mark_bbn"], [13.07, "mark_recomb"]]
	var font: Font
	var log_t := -6.0

	func _x(l: float) -> float:
		return clampf((l - LMIN) / (LMAX - LMIN), 0.0, 1.0) * size.x

	func _draw() -> void:
		var y := size.y - 8.0
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(1, 1, 1, 0.14), 1.0, true)
		var cx := _x(log_t)
		draw_line(Vector2(0.0, y), Vector2(cx, y), Color(1.0, 0.85, 0.6, 0.55), 1.5, true)
		for t in TICKS:
			var x := _x(float(t[0]))
			draw_line(Vector2(x, y - 3.0), Vector2(x, y + 3.0), Color(1, 1, 1, 0.3), 1.0)
			draw_string(font, Vector2(x + 4.0, y - 6.0), I18n.t(String(t[1])), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.38))
		for m in MARKS:
			var x := _x(float(m[0]))
			var passed := log_t >= float(m[0])
			draw_circle(Vector2(x, y), 3.0, Color(1.0, 0.85, 0.6, 0.9 if passed else 0.3))
			draw_string(font, Vector2(x - 60.0, y + 20.0), I18n.t(String(m[1])), HORIZONTAL_ALIGNMENT_CENTER, 120, 11,
				Color(1.0, 0.85, 0.6, 0.75 if passed else 0.3))
		for i in 4:
			draw_circle(Vector2(cx, y), 9.0 - i * 2.0, Color(1.0, 0.9, 0.7, 0.08 + i * 0.12))
		draw_circle(Vector2(cx, y), 2.5, Color(1, 1, 1, 1))


## Состав вещества: строки «цвет — название — значение» с тонкой шкалой.
class Composition extends Control:
	var font: Font
	var font_value: Font
	var rows: Array = []

	func _draw() -> void:
		var y := 0.0
		for r in rows:
			var col: Color = r[3]
			var frac: float = r[2]
			draw_circle(Vector2(6.0, y + 13.0), 4.5, Color(col.r, col.g, col.b, 0.95))
			draw_string(font, Vector2(20.0, y + 19.0), String(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.88, 0.9, 0.97, 0.85))
			draw_string(font_value, Vector2(0.0, y + 19.0), String(r[1]), HORIZONTAL_ALIGNMENT_RIGHT, size.x, 16, Color(1, 1, 1, 0.95))
			var bar_w := size.x - 20.0
			draw_rect(Rect2(20.0, y + 28.0, bar_w, 2.0), Color(1, 1, 1, 0.08))
			draw_rect(Rect2(20.0, y + 28.0, bar_w * clampf(frac, 0.0, 1.0), 2.0), Color(col.r, col.g, col.b, 0.8))
			var extra: Dictionary = r[4] if r.size() > 4 else {}
			if extra.has("ref"):
				# Засечка: значение в нашей Вселенной.
				var rx := 20.0 + bar_w * clampf(float(extra["ref"]), 0.0, 1.0)
				draw_line(Vector2(rx, y + 24.0), Vector2(rx, y + 34.0), Color(1, 1, 1, 0.45), 1.0)
			if extra.has("ghost"):
				# Прогноз: куда придёт значение, если оставить рычаги так.
				var gx := 20.0 + bar_w * clampf(float(extra["ghost"]), 0.0, 1.0)
				var gy := y + 29.0
				draw_colored_polygon(PackedVector2Array([Vector2(gx, gy - 6.0), Vector2(gx + 5.0, gy), Vector2(gx, gy + 6.0), Vector2(gx - 5.0, gy)]),
					Color(1.0, 0.85, 0.6, 0.95))
			if extra.has("clock"):
				# Часы распада нейтронов: полный круг — среднее время жизни, ~15 минут.
				var c := float(extra["clock"])
				draw_arc(Vector2(6.0, y + 13.0), 9.0, -PI / 2.0, -PI / 2.0 + TAU * c, 32, Color(col.r, col.g, col.b, 0.9), 1.5, true)
			y += 46.0
