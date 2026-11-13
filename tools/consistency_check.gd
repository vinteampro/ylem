extends SceneTree
## Deterministic contracts for the boundary between physics and visible particles.

const Model = preload("res://scripts/universe.gd")
const Field = preload("res://scripts/particle_field.gd")
const Chemistry = preload("res://scripts/particle_chemistry.gd")
const Structure = preload("res://scripts/structure.gd")
var failures := 0
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func _init() -> void:
	seed(1729)
	_reverse_reactions()
	_all_reactions()
	_capacity_and_budget()
	print("reaction and capacity contracts complete")
	_sampling()
	print("finite sample contracts complete")
	_event_streams()
	_evolution()
	print("CONSISTENCY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _field(kinds: Array):
	var f = Field.new()
	f.structure = Structure.new(0)
	f._alloc()
	for k in kinds:
		f._spawn(k, Vector2(100, 100), Vector2.ZERO, false)
	f._rebuild_lists()
	return f


func _reverse_reactions() -> void:
	# Expected products are independent of the renderer's reaction definitions.
	for spec in [
		["Dp", [Field.K.HE3], [Field.K.D, Field.K.P]],
		["Dn", [Field.K.HE3], [Field.K.D, Field.K.N]],
		["He3n", [Field.K.HE3, Field.K.P], [Field.K.HE3, Field.K.N]],
	]:
		var f = _field(spec[1])
		check(f._react(spec[0], -1, true), "%s reverse reaction can run" % spec[0])
		f._rebuild_lists()
		var expected := PackedInt32Array()
		expected.resize(Field.KIND_COUNT)
		for k in spec[2]:
			expected[k] += 1
		check(f.counts == expected, "%s reverse reaction has the correct products" % spec[0])
		f.free()
	var f = _field([])
	check(f._reaction_style("He3n", -1)[2] == "c_nuclear", "exchange history does not invent a photon")
	check(f._reaction_style("n_to_p", -1)[2] == "c_weak", "weak history does not invent a specific capture mechanism")
	f.free()


func _mass(counts: PackedInt32Array) -> int:
	var total := 0
	for k in Field.KIND_COUNT:
		total += counts[k] * Chemistry.BARYON[k]
	return total


func _particle_count(counts: PackedInt32Array) -> int:
	var total := 0
	for count in counts:
		total += count
	return total


func _inventory(kinds: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(Field.KIND_COUNT)
	for k in kinds:
		out[k] += 1
	return out


func _all_reactions() -> void:
	# Independent stoichiometric expectations, including two-to-two exchanges.
	var cases := [
		["pn_D", [Field.K.P, Field.K.N], [Field.K.D]],
		["Dp", [Field.K.D, Field.K.P], [Field.K.HE3]],
		["Dn", [Field.K.D, Field.K.N], [Field.K.HE3]],
		["He3n", [Field.K.HE3, Field.K.N], [Field.K.HE3, Field.K.P]],
		["DDn", [Field.K.D, Field.K.D], [Field.K.HE3, Field.K.N]],
		["DDp", [Field.K.D, Field.K.D], [Field.K.HE3, Field.K.P]],
		["A3Dn", [Field.K.HE3, Field.K.D], [Field.K.HE4, Field.K.N]],
		["A3Dp", [Field.K.HE3, Field.K.D], [Field.K.HE4, Field.K.P]],
		["A3n", [Field.K.HE3, Field.K.N], [Field.K.HE4]],
		["A3p", [Field.K.HE3, Field.K.P], [Field.K.HE4]],
		["Li", [Field.K.HE4, Field.K.HE3], [Field.K.LI7]],
		["He_melt", [Field.K.HE4], [Field.K.P, Field.K.P, Field.K.N, Field.K.N]],
		["A3_melt", [Field.K.HE3], [Field.K.P, Field.K.P, Field.K.N]],
		["Li_melt", [Field.K.LI7], [Field.K.P, Field.K.P, Field.K.P, Field.K.N, Field.K.N, Field.K.N, Field.K.N]],
		["Be7n", [Field.K.LI7, Field.K.N], [Field.K.LI7, Field.K.P]],
		["Be7n_He", [Field.K.LI7, Field.K.N], [Field.K.HE4, Field.K.HE4]],
		["Li7p_He", [Field.K.LI7, Field.K.P], [Field.K.HE4, Field.K.HE4]],
		["He3He3", [Field.K.HE3, Field.K.HE3], [Field.K.HE4, Field.K.P, Field.K.P]],
		["Li7D", [Field.K.LI7, Field.K.D], [Field.K.HE4, Field.K.HE4, Field.K.N]],
		["Be7D", [Field.K.LI7, Field.K.D], [Field.K.HE4, Field.K.HE4, Field.K.P]],
		["T_melt", [Field.K.HE3], [Field.K.P, Field.K.N, Field.K.N]],
		["Be_melt", [Field.K.LI7], [Field.K.P, Field.K.P, Field.K.P, Field.K.P, Field.K.N, Field.K.N, Field.K.N]],
		["recH", [Field.K.P, Field.K.E], [Field.K.H]],
		["recHe", [Field.K.HE4, Field.K.E, Field.K.E], [Field.K.HE]],
		["n_to_p", [Field.K.N], [Field.K.P]],
	]
	for item in cases:
		for direction in [1, -1]:
			var source: Array = item[1] if direction == 1 else item[2]
			var target: Array = item[2] if direction == 1 else item[1]
			for animated in [false, true]:
				var f = _field(source)
				var before := _mass(f.counts)
				f.follow = 0
				check(f._react(item[0], direction, not animated), "%s direction %d starts" % [item[0], direction])
				f._update_bonds(1.0)
				f._rebuild_lists()
				check(f.counts == _inventory(target), "%s direction %d products" % [item[0], direction])
				check(_mass(f.counts) == before, "%s conserves baryons" % item[0])
				check(f.follow >= 0 and f.alive[f.follow] == 1 and f.follow_log.size() == 1, "%s preserves a real descendant's history" % item[0])
				f.free()
	for neutron in [0.0, 1.0]:
		var f = _field([Field.K.QR, Field.K.QG, Field.K.QB])
		f.n_fraction = neutron
		check(f._react("hadron", 1, true), "hadronization")
		f._rebuild_lists()
		check(f.counts[Field.K.P if neutron == 0.0 else Field.K.N] == 1, "nucleon selection")
		check(f._react("hadron", -1, true), "quark reheating")
		f._rebuild_lists()
		check(f.counts == _inventory([Field.K.QR, Field.K.QG, Field.K.QB]), "quark colors and mass restored")
		f.free()


func _capacity_and_budget() -> void:
	var f = _field([Field.K.HE4])
	for i in Field.CAP - 1:
		f._spawn(Field.K.H, Vector2.ZERO, Vector2.ZERO, false)
	f._rebuild_lists()
	f.follow = 0
	var before = f.counts.duplicate()
	check(not f._react("He_melt", 1, true), "full pool rejects split atomically")
	f._rebuild_lists()
	check(f.counts == before and f.follow == 0 and f.busy[0] == 0, "failed split retains source and observation")
	f.free()
	f = _field([Field.K.D])
	check(not f._react("Dp", 1, false) and f.busy[0] == 0, "missing reactant releases reservations")
	f.free()
	f = _field([])
	for i in 500:
		f._spawn(Field.K.N, Vector2.ZERO, Vector2.ZERO, false)
	f._rebuild_lists()
	f.apply_events({"n_to_p": 0.5})
	check(f.acc["n_to_p"] == 500.0, "event burst is not silently clamped to 60")
	f._run_reactions()
	f._rebuild_lists()
	check(f.counts[Field.K.P] == Field.MAX_REACTIONS_PER_FRAME, "global per-frame work bound")
	check(f.acc["n_to_p"] == 500.0 - Field.MAX_REACTIONS_PER_FRAME, "unprocessed events retained")
	f.apply_events({"n_to_p": 100.0})
	check(f.event_overflows == 1 and f._resync_requested and f.acc.is_empty(), "overflow explicitly requests authoritative rebase")
	f.free()


func _settle(f, u, fps: int, seconds := 12.0) -> void:
	f.sync(u)
	for frame in ceili(seconds * fps):
		f.step_chemistry(1.0 / fps)
		if frame > fps and absf(f.baryons_nominal - f.baryons_target) < 0.25 and f.counts == Chemistry.sample(u, roundi(f.baryons_target)) and f.bonds.is_empty():
			break
	f._rebuild_lists()
	var expected := Chemistry.sample(u, roundi(f.baryons_nominal))
	check(f.counts == expected, "sample converges at %d FPS, T=%s" % [fps, u.T])
	check(_mass(f.counts) == 3 * roundi(f.baryons_nominal), "finite sample has exact baryon budget")
	check(f._free.size() + _particle_count(f.counts) == Field.CAP, "pool has no lost or duplicated slots")
	check(f.invalid_events == 0, "all emitted channels are recognized")


func _sampling() -> void:
	var u = Model.new()
	u.hadron = 1.0
	u.Y = PackedFloat64Array([0.0, 0.75, 0.00001, 0.0, 0.0, 0.062495, 0.0, 0.0])
	u.xH = 0.0
	u.xHe = 0.0
	u.T = 1000.0
	for n in [0, 1, 10, 501, 1000, 1350]:
		var sample := Chemistry.sample(u, n)
		check(_mass(sample) == 3 * n, "quantization conserves %d baryons" % n)
		check(sample[Field.K.D] == 0, "sub-particle traces stay in the numeric model")
		check(sample[Field.K.P] == 0 and sample[Field.K.HE4] == 0 and sample[Field.K.E] == 0, "neutral sample has no free charges")
	for fps in [30, 60, 144]:
		var f = _field([Field.K.H])
		f.follow = 0
		_settle(f, u, fps)
		check(f.follow == 0 and f.follow_log.is_empty(), "sampling keeps an unaffected observed particle")
		u.eta_mult = 10.0
		_settle(f, u, fps)
		u.eta_mult = 0.1
		_settle(f, u, fps)
		u.xH = 1.0
		u.xHe = 1.0
		u.T = 1e6
		f.apply_events({"recH": -100.0, "recHe": -100.0})
		_settle(f, u, fps)
		check(f.follow == -1 and f.follow_log.is_empty(), "resampling never invents an observed reaction")
		check(f.counts[Field.K.H] == 0 and f.counts[Field.K.HE] == 0, "no atoms survive reheating")
		f.free()
		u.eta_mult = 1.0
		u.xH = 0.0
		u.xHe = 0.0
		u.T = 1000.0


func _advance_to(u, temperature: float, warming := false) -> void:
	var steps := 0
	while (u.T < temperature if warming else u.T > temperature) and steps < 12000:
		if not u.advance(0.05):
			break
		u.take_events()
		steps += 1
	check(steps < 12000 and (u.T >= temperature if warming else u.T <= temperature), "bounded evolution reaches T=%s" % temperature)
	var total := 0.0
	for i in Model.NSPEC:
		check(is_finite(u.Y[i]) and u.Y[i] >= 0.0, "finite nonnegative abundance")
		total += u.Y[i] * Model.MASS[i]
	check(absf(total - 1.0) < 2e-6, "numerical baryon conservation")
	check(is_finite(u.T) and is_finite(u.t) and u.xH >= 0.0 and u.xH <= 1.0, "finite thermal/ionization state")
	check(u.solver_failures == 0, "nonlinear stages converge (%d failures, residual %s)" % [u.solver_failures, u.solver_max_residual])


func _evolution() -> void:
	for cfg in [[0.2, 0.1], [0.2, 10.0], [2.5, 0.1], [2.5, 10.0]]:
		var u = Model.new()
		u.expansion = cfg[0]
		u.eta_mult = cfg[1]
		_advance_to(u, 1e7)
	var u = Model.new()
	var f = _field([])
	for temperature in [1e8, 1000.0]:
		_advance_to(u, temperature)
		_settle(f, u, 60, 4.0)
	u.expansion = -1.0
	for temperature in [1e6, 1e10, 2e12]:
		_advance_to(u, temperature, true)
		_settle(f, u, 30, 4.0)
	u.expansion = 1.0
	_advance_to(u, 1000.0)
	_settle(f, u, 144, 4.0)
	var t: float = u.t
	var temp: float = u.T
	u.advance(0.0)
	check(u.t == t and u.T == temp, "pause does not advance the model")
	u.expansion = 0.0
	for i in 20:
		u.advance(0.01)
	check(u.T == temp and u.t > t, "zero expansion stops cooling but allows physical time")
	u.reset()
	_settle(f, u, 60, 4.0)
	check(not u.ls_found and u.solver_failures == 0, "new universe clears diagnostics and transparency")
	f.free()


func _event_streams() -> void:
	# Deliver real integrated fluxes while the model changes, at different render
	# rates and with a long frame. The final sample must still match each model.
	var initial = Model.new()
	_advance_to(initial, 1e9)
	for fps in [30, 60, 144]:
		var u = initial.clone()
		var f = _field([])
		_settle(f, u, fps, 3.0)
		for frame in 2 * fps:
			var delta: float = 0.4 if frame == fps else 1.0 / fps
			check(u.advance(delta), "live model advances across a render stall")
			f.sync(u)
			f.apply_events(u.take_events())
			f.step_chemistry(delta)
		_settle(f, u, fps, 4.0)
		check(f.reconciliations > 0 and f.bonds.is_empty(), "live flux backlog settles at %d FPS" % fps)
		f.free()
