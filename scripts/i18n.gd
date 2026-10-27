extends RefCounted
## Все тексты игры на двух языках: интерфейс, эпохи, реплики рассказчика, кодекс.
## Язык по умолчанию — язык системы (русский или английский), его можно сменить
## кнопкой в панели рычагов; выбор запоминается в user://settings.cfg.

static var lang := "en"

const SETTINGS := "user://settings.cfg"


static func load_language() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		lang = String(cfg.get_value("ui", "language", ""))
	if lang != "ru" and lang != "en":
		lang = "ru" if OS.get_locale_language() == "ru" else "en"


static func set_language(code: String) -> void:
	lang = code
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("ui", "language", code)
	cfg.save(SETTINGS)


static func is_ru() -> bool:
	return lang == "ru"


## Строка интерфейса по ключу.
static func t(key: String) -> String:
	var item: Array = UI.get(key, [key, key])
	return item[0] if lang == "ru" else item[1]


static func epoch(i: int) -> Dictionary:
	var e: Array = EPOCHS[i]
	var k := 0 if lang == "ru" else 3
	return {"num": e[k], "title": e[k + 1], "sub": e[k + 2]}


static func species(k: int) -> Array:
	var item: Array = SPECIES[k]
	return [item[0], item[1]] if lang == "ru" else [item[2], item[3]]


static func has_species(k: int) -> bool:
	return SPECIES.has(k)


static func line(id: String) -> String:
	var item: Array = LINES[id]
	return item[0] if lang == "ru" else item[1]


static func particle(k: int) -> String:
	var item: Array = PARTICLES[k]
	return item[0] if lang == "ru" else item[1]


# ---------------------------------------------------------------- интерфейс

const UI := {
	"title": ["Ylem", "Ylem"],
	"subtitle": ["первые 400 000 лет · медитация на научной основе", "the first 400,000 years · a meditation built on real physics"],
	"composition": ["СОСТАВ ВЕЩЕСТВА", "COMPOSITION"],
	"controls": ["РЫЧАГИ", "CONTROLS"],
	"expansion": ["Темп расширения", "Expansion rate"],
	"density": ["Плотность вещества", "Matter density"],
	"speed": ["Ход времени", "Flow of time"],
	"music": ["Музыка · M", "Music · M"],
	"music_off": ["выключена", "off"],
	"pause": ["Пауза · Пробел", "Pause · Space"],
	"release": ["Отпустить", "Let go"],
	"release_tip": ["Рычаги плавно вернутся к значениям нашей Вселенной", "The controls drift back to the values of our Universe"],
	"hide": ["Скрыть · H", "Hide · H"],
	"lang_button": ["English", "Русский"],
	"hint_touch": ["Коснись света.", "Touch the light."],
	"hint_more": ["Ещё. Разбуди его.", "Again. Wake it up."],
	"hint_faster": ["Чаще.", "Faster."],
	"hint_help": ["Щёлкай по свету часто — или нажми Enter.", "Click the light rapidly — or press Enter."],
	"preparing": ["Готовим вакуум…  %d%%", "Preparing the vacuum…  %d%%"],
	"mouse_hint": ["ЛКМ (держать) — сжать  ·  ПКМ — разредить\nколесо — масштаб  ·  клик по частице — следить  ·  стрелки — сдвиг",
		"Hold LMB — compress  ·  RMB — rarefy\nwheel — zoom  ·  click a particle — follow it  ·  arrows — pan"],
	"mood_ours": ["как у нас", "like ours"],
	"mood_contract": ["сжатие", "contracting"],
	"mood_slow": ["медленнее", "slower"],
	"mood_fast": ["быстрее", "faster"],
	"paused": ["пауза", "paused"],
	"discovered": ["ОТКРЫТО", "DISCOVERED"],
	"observing": ["НАБЛЮДЕНИЕ  ·  Esc — отпустить", "OBSERVING  ·  Esc to release"],
	"result": ["ИТОГ", "RESULT"],
	"your_universe": ["Ваша Вселенная", "Your Universe"],
	"yours": ["Ваша", "Yours"],
	"ours": ["Наша", "Ours"],
	"again": ["Новая Вселенная", "Another Universe"],
	"stay": ["Остаться и смотреть", "Stay and watch"],
	# шкала времени
	"tick_us": ["1 мкс", "1 μs"],
	"tick_ms": ["1 мс", "1 ms"],
	"tick_s": ["1 с", "1 s"],
	"tick_min": ["1 мин", "1 min"],
	"tick_h": ["1 ч", "1 h"],
	"tick_day": ["1 сут", "1 day"],
	"tick_year": ["1 год", "1 year"],
	"tick_kyr": ["1000 лет", "1000 years"],
	"tick_myr": ["1 млн лет", "1 Myr"],
	"mark_hadrons": ["адроны", "hadrons"],
	"mark_bbn": ["нуклеосинтез", "nucleosynthesis"],
	"mark_recomb": ["рекомбинация", "recombination"],
	# единицы
	"u_us": [" мкс", " μs"],
	"u_ms": [" мс", " ms"],
	"u_s": [" с", " s"],
	"u_min_s": ["%d мин %d с", "%d min %d s"],
	"u_h": [" ч", " h"],
	"u_day": [" сут", " days"],
	"u_yr": [" лет", " years"],
	"u_kyr": [" тыс. лет", " thousand years"],
	"u_myr": [" млн лет", " million years"],
	"u_gyr": [" млрд лет", " billion years"],
	"u_K": [" К", " K"],
	"u_MeV": [" МэВ", " MeV"],
	"u_keV": [" кэВ", " keV"],
	"u_eV": [" эВ", " eV"],
	# строки состава
	"row_quarks": ["Кварки", "Quarks"],
	"row_nucleons": ["Нуклоны", "Nucleons"],
	"row_hydrogen": ["Водород · протоны", "Hydrogen · protons"],
	"row_neutrons": ["Нейтроны", "Neutrons"],
	"row_deuterium": ["Дейтерий · D/H", "Deuterium · D/H"],
	"row_he3": ["Гелий-3 · ³He/H", "Helium-3 · ³He/H"],
	"row_li7": ["Литий-7 · ⁷Li/H", "Lithium-7 · ⁷Li/H"],
	"row_electrons": ["Свободные электроны", "Free electrons"],
	"row_he4": ["Гелий-4 · масса", "Helium-4 · mass"],
	# итоги
	"res_he4": ["Гелий-4, доля массы", "Helium-4, mass fraction"],
	"res_d": ["Дейтерий, D/H", "Deuterium, D/H"],
	"res_he3": ["Гелий-3, ³He/H", "Helium-3, ³He/H"],
	"res_li": ["Литий-7, ⁷Li/H (наша — по старым звёздам)", "Lithium-7, ⁷Li/H (ours: from old stars)"],
	"res_expansion": ["Темп расширения при нуклеосинтезе", "Expansion rate during fusion"],
	"res_eta": ["Плотность вещества η", "Matter density η"],
	"res_clumps": ["Сгущения — будущие звёзды", "Clumps — future stars"],
	"res_transparent": ["Вселенная стала прозрачной", "Universe became transparent"],
	"res_transparent_ours": ["≈370–380 тыс. лет", "≈370,000–380,000 years"],
	"verdict_ours": ["Очень похоже на нашу Вселенную. Возможно, через 13,8 миллиарда лет здесь тоже кто-то будет изучать реликтовый свет.",
		"Very much like our own Universe. In 13.8 billion years, someone in it might look up at its relic light."],
	"verdict_h": ["Почти чистый водород: нейтроны распались, не дождавшись синтеза. Первые звёзды здесь будут тусклее и проживут дольше.",
		"Almost pure hydrogen: the neutrons decayed before fusion could catch them. The first stars here will burn dimmer and live longer."],
	"verdict_less_he": ["Гелия меньше, чем у нас: звёзды будут чуть холоднее и долговечнее.",
		"Less helium than ours: stars will be slightly cooler and longer-lived."],
	"verdict_he": ["Гелиевая Вселенная: водорода мало, звёзды проживут короткую яркую жизнь, а воды и органики будет меньше.",
		"A helium universe: little hydrogen left, so stars will live short, bright lives, and there will be less water and organic matter."],
	"verdict_more_he": ["Гелия больше, чем у нас: звёзды будут гореть жарче и быстрее.",
		"More helium than ours: stars will burn hotter and faster."],
	"verdict_more_d": ["Много несгоревшего дейтерия — в такой Вселенной было бы полно тяжёлой воды.",
		"Lots of unburned deuterium: this universe would be rich in heavy water."],
	"verdict_less_d": ["Дейтерий почти весь выгорел: в плотной Вселенной от первых минут почти не осталось следов.",
		"Almost all deuterium burned away: a dense universe left no witnesses of its first minutes."],
	"verdict_own": ["Похожа на нашу, но всё-таки другая.",
		"A universe of its own: close to ours, but not the same."],
	# наблюдение за частицей
	"since_start": ["с первой микросекунды", "since the first microsecond"],
	"appeared": ["появление", "appeared"],
	"c_quarks": ["собран из трёх кварков", "built from three quarks"],
	"c_melted": ["распался на кварки", "dissolved into quarks"],
	"c_fusion": ["слияние", "fusion"],
	"c_photo": ["свет разбил ядро", "light broke it apart"],
	"c_broke": ["ядро распалось", "nucleus fell apart"],
	"c_capture": ["захват электрона", "captured an electron"],
	"c_capture2": ["захват электронов", "captured electrons"],
	"c_ionized": ["ионизация", "ionized"],
	"c_beta": ["β-распад", "β-decay"],
	"c_positron": ["захват позитрона", "positron capture"],
}

const PARTICLES := [
	["кварк", "quark"], ["кварк", "quark"], ["кварк", "quark"], ["протон", "proton"], ["нейтрон", "neutron"],
	["дейтрон", "deuteron"], ["ядро гелия-3", "helium-3 nucleus"], ["ядро гелия-4", "helium-4 nucleus"],
	["ядро лития-7", "lithium-7 nucleus"], ["электрон", "electron"], ["атом водорода", "hydrogen atom"],
	["атом гелия", "helium atom"],
]

# ---------------------------------------------------------------- эпохи

const EPOCHS := [
	["Эпоха I", "Кварк-глюонная плазма", "первая микросекунда",
		"Epoch I", "Quark–Gluon Plasma", "the first microsecond"],
	["Эпоха II", "Рождение нуклонов", "от микросекунды до минуты",
		"Epoch II", "Birth of Nucleons", "from a microsecond to a minute"],
	["Эпоха III", "Первичный нуклеосинтез", "первые минуты",
		"Epoch III", "Primordial Nucleosynthesis", "the first minutes"],
	["Интерлюдия", "Долгое остывание", "сотни тысяч лет",
		"Interlude", "The Long Cooling", "hundreds of thousands of years"],
	["Эпоха IV", "Рекомбинация", "380 тысяч лет",
		"Epoch IV", "Recombination", "380,000 years"],
	["Эпилог", "Тёмные века", "до первых звёзд — сто миллионов лет",
		"Epilogue", "The Dark Ages", "a hundred million years until the first stars"],
]

# ---------------------------------------------------------------- кодекс
## Индексы совпадают с перечислением видов частиц в particle_field.gd.

const SPECIES := {
	0: ["Кварки", "Красный, зелёный, синий — это «цветовой заряд», а не настоящий цвет. Поодиночке кварки не встречаются: природа допускает только бесцветные сочетания.",
		"Quarks", "Red, green, blue: this is “colour charge”, not real colour. Quarks never live alone; nature only allows colourless combinations."],
	3: ["Протон", "Три кварка, связанные глюонами. Стабилен — возможно, вечен. Ядро атома водорода — это и есть один протон.",
		"Proton", "Three quarks bound by gluons. Stable, perhaps forever. Every hydrogen nucleus will be a proton."],
	4: ["Нейтрон", "Чуть тяжелее протона и поэтому нестабилен: свободный нейтрон живёт в среднем 14,6 минуты. Отсчёт пошёл.",
		"Neutron", "Slightly heavier than a proton, and therefore mortal: a free neutron lives 14.6 minutes on average. The clock is ticking."],
	5: ["Дейтерий", "Протон и нейтрон. Связь слабая — всего 2,2 МэВ, поэтому поначалу свет разбивает дейтроны, едва они образуются.",
		"Deuterium", "A proton and a neutron. The bond is fragile, only 2.2 MeV, so light kept smashing deuterons as soon as they formed."],
	6: ["Гелий-3", "Два протона и нейтрон. Редкий и лёгкий — сегодня его ищут в лунном грунте как топливо для термоядерных реакторов.",
		"Helium-3", "Two protons and a neutron. Rare and light; today people look for it in lunar soil as fuel for fusion reactors."],
	7: ["Гелий-4", "Самое прочное из лёгких ядер. Внутри него нейтрон не распадается, поэтому почти все нейтроны Вселенной в итоге оказались в гелии-4.",
		"Helium-4", "The most tightly bound of the light nuclei. Inside it a neutron cannot decay, so almost every neutron in the Universe ended up in helium-4."],
	8: ["Литий-7", "Самый тяжёлый элемент первых минут. В старых звёздах лития втрое меньше, чем предсказывает теория. Это «литиевая проблема», и она до сих пор не решена.",
		"Lithium-7", "The heaviest element of the first minutes. Old stars hold three times less lithium than theory predicts: the “lithium problem”, still unsolved."],
	9: ["Электроны", "Они были здесь всегда, но двигались слишком быстро, чтобы ядро могло их удержать. Теперь Вселенная остыла достаточно.",
		"Electrons", "They were always here, but moving too fast for any nucleus to hold them. Now the Universe has cooled enough."],
	10: ["Атом водорода", "Электрон, связанный с протоном. Опускаясь на нижние уровни при рекомбинации, электрон излучает в том числе линию H-альфа — 656 нм, тот самый красный цвет туманностей на снимках телескопов.",
		"Hydrogen atom", "An electron bound to a proton. The recombination cascade emits the H-alpha line at 656 nm, the red glow of nebulae in telescope images."],
	11: ["Атом гелия", "Первый нейтральный атом во Вселенной: гелий держит электроны крепче водорода и поэтому становится нейтральным раньше.",
		"Helium atom", "The first neutral atom in the Universe: helium holds its electrons tighter than hydrogen, so it settles down first."],
}

# ---------------------------------------------------------------- рассказчик

const LINES := {
	"inflation": ["Инфляция: за ничтожную долю секунды пространство растянулось как минимум в 10²⁶ раз, а её энергия превратилась в горячую плазму.",
		"Inflation: in a sliver of a second, space stretched at least 10²⁶-fold, and its energy turned into hot plasma."],
	"start": ["Первая микросекунда. Кварки и глюоны свободны — протонов и нейтронов ещё нет.",
		"The first microsecond. Quarks and gluons roam free; there are no protons or neutrons yet."],
	"touch": ["Коснись плазмы: зажми левую кнопку — сожмёшь вещество, правую — разредишь. Колесо мыши — приблизить. Клик по частице — проследить её судьбу.",
		"Touch the plasma: hold the left button to compress matter, the right to thin it out. Scroll to zoom. Click a particle to follow its fate."],
	"cooling_qgp": ["Плазма остывает. Скоро кварки начнут связываться в тройки.",
		"The plasma is cooling. Soon quarks will begin to bind in threes."],
	"hadron": ["Адронизация. Кварки объединяются по трое в протоны и нейтроны.",
		"Hadronization. Quarks join in threes to form protons and neutrons."],
	"neutrinos": ["Нейтрино перестают взаимодействовать с веществом и свободно разлетаются. Они летят до сих пор.",
		"Neutrinos stop interacting with matter and stream away freely. They are still travelling today."],
	"freeze": ["Слабые реакции прекращаются. На шесть протонов приходится примерно один нейтрон, и свободные нейтроны уже начали распадаться.",
		"The weak interaction freezes out. About one neutron for every six protons, and the decay clock is already ticking."],
	"annihilation": ["Электроны и позитроны аннигилируют. Остаётся лишь крошечный избыток электронов — примерно один на два миллиарда фотонов.",
		"Electrons and positrons annihilate. Only a tiny excess of electrons survives: about one for every two billion photons."],
	"bottleneck": ["Дейтериевый барьер: дейтроны образуются, но свет тут же их разбивает.",
		"The deuterium bottleneck: deuterons form, but light smashes them at once."],
	"d_survives": ["Барьер пройден: свет больше не разбивает дейтерий, и он почти сразу превращается в гелий.",
		"The bottleneck breaks. Deuterium survives, and almost immediately burns into helium."],
	"helium": ["Почти все уцелевшие нейтроны теперь в ядрах гелия. Гелий — это четверть всей массы вещества.",
		"Nearly all surviving neutrons are now locked up in helium nuclei. Helium makes up a quarter of all matter by mass."],
	"bbn_done": ["Ядерные реакции затихают. Состав вещества больше не изменится, пока не зажгутся первые звёзды.",
		"Nuclear reactions fade out. The Universe’s composition is now set, until the first stars are born."],
	"long": ["Вселенную заполняет горячий туман из света, электронов и ядер. Фотон не может уйти далеко: его снова и снова рассеивают электроны.",
		"Light, electrons and nuclei share one hot fog. A photon cannot get far: electrons scatter it again and again."],
	"he_atoms": ["Ядра гелия первыми захватывают электроны. Так появляются первые нейтральные атомы.",
		"Helium nuclei catch electrons first. Helium is the first neutral atom."],
	"recomb": ["Рекомбинация. Протоны захватывают электроны и становятся атомами водорода — туман рассеивается.",
		"Recombination. Protons capture electrons and become hydrogen atoms, and the fog begins to clear."],
	"transparent": ["Вселенная стала прозрачной. Этот свет дошёл до нас — сегодня это реликтовое излучение с температурой 2,7 кельвина.",
		"The Universe is transparent. We still see this light today as the cosmic microwave background, at 2.7 kelvin."],
	"imprint": ["Видишь холодные пятна? Это следы твоих прикосновений. Свет теряет энергию, выбираясь из сгущений, а скоро к ним начнёт стягиваться и вещество.",
		"See the cold spots? Those are your touches. The clumps hold back the light, and soon they will pull in matter."],
	"dark": ["Тёмные века. Свет краснеет и гаснет. Гравитация медленно собирает облака для первых звёзд…",
		"The Dark Ages. The light reddens and fades. Gravity slowly gathers clouds for the first stars…"],
	"gather": ["Сгущения растут: гравитация стягивает в них всё больше вещества. Там, где ты касался плазмы, через сотню миллионов лет зажгутся первые звёзды.",
		"The clumps grow as space expands, and gravity draws matter into them. Where you touched the plasma, the first stars will ignite a hundred million years from now."],
	"hint_slow": ["Расширение медленное — нейтроны успевают распасться, гелия будет меньше.",
		"Slow expansion: neutrons have time to decay, so there will be less helium."],
	"hint_fast": ["Расширение быстрое — нейтроны не успевают распасться, гелия будет больше.",
		"Fast expansion: neutrons have no time to decay, so there will be more helium."],
	"hint_compress": ["Сжатие разогревает Вселенную, и частицы снова распадаются.",
		"Contraction heats the Universe. Bonds break apart."],
	"hint_dense": ["Плотная Вселенная: дейтерий сгорает почти без остатка.",
		"A dense universe: deuterium burns away almost completely."],
	"hint_sparse": ["Разреженная Вселенная: частицам трудно встретиться, дейтерия останется много.",
		"A sparse universe: particles rarely meet, so plenty of deuterium will remain."],
	"reheat": ["Вселенная снова разогревается…", "The Universe is heating up again…"],
}
