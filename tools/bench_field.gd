extends SceneTree
## Сколько стоит кадр поля частиц (без отрисовки):
##   godot --headless --path . --script res://tools/bench_field.gd
## Кварковая эпоха — самый тяжёлый момент игры: ~3000 частиц, полный жар.
## В браузере (wasm) GDScript медленнее в несколько раз, поэтому важна не цифра,
## а то, как она меняется после правок.

const ParticleField := preload("res://scripts/particle_field.gd")
const FRAMES := 300
const DT := 1.0 / 60.0


var field: Node2D


func _initialize() -> void:
	field = ParticleField.new()
	root.add_child(field)
	field.set_process(false)


# Замер — в первом кадре, когда поле уже в дереве сцены и знает размер экрана.
func _process(_delta: float) -> bool:
	field.reset_field()
	print("частиц: %d" % (ParticleField.CAP - field._free.size()))

	var sections := {
		"rebuild_lists": func() -> void: field._rebuild_lists(),
		"reactions": func() -> void:
			field._adjust_population(DT)
			field._run_reactions()
			field._update_bonds(DT),
		"move_and_draw": func() -> void: field._move_and_draw(DT),
		"flashes": func() -> void: field._update_flashes(DT),
	}
	var total := {}
	for name in sections:
		total[name] = 0
	# Прогрев, чтобы частицы «родились» и разошлись.
	for f in 30:
		for name in sections:
			sections[name].call()
	for f in FRAMES:
		field.flow_t += DT
		for name in sections:
			var t0 := Time.get_ticks_usec()
			sections[name].call()
			total[name] += Time.get_ticks_usec() - t0
	var sum := 0.0
	for name in sections:
		var ms: float = total[name] / 1000.0 / FRAMES
		sum += ms
		print("%-14s %6.2f мс/кадр" % [name, ms])
	print("%-14s %6.2f мс/кадр" % ["всего", sum])
	return true
