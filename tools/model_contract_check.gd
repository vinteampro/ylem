extends SceneTree
## Numerical contracts beyond the observational reference values in sim_check.

const Model = preload("res://scripts/universe.gd")
const Chemistry = preload("res://scripts/particle_chemistry.gd")
var checks := 0
var failures := 0
var max_event_error := 0.0


class FailingModel extends Model:
	func _nuclear_interval(_old: float, _new: float, _dt: float, _depth: int) -> bool:
		# A failed trial must not leak either its state or its events.
		Y[0] = 42.0
		events["pn_D"] = 42.0
		return false


class StiffDecayModel extends Model:
	func _coeffs(_temperature: float) -> Array:
		var zero := PackedFloat64Array()
		zero.resize(REACTIONS.size())
		return [100.0, 0.0, zero, zero.duplicate()]


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func _init() -> void:
	_rates()
	_failure_and_reset()
	_stiff_transient()
	_fluxes_and_refinement()
	print("MODEL CONTRACTS: %d checks, %d failures; maximum event/state error %s" % [checks, failures, max_event_error])
	quit(1 if failures else 0)


func _rates() -> void:
	# AlterBBN's rate_all uses fabs, including where these fits change sign.
	check(absf(Model._rate(30, 0.03) / 2310136.68950291 - 1.0) < 1e-10, "T+D low-temperature forward rate")
	check(absf(Model._rate(31, 0.03) / 99918.3492750725 - 1.0) < 1e-10, "He3+D low-temperature forward rate")
	for i in 401:
		var t9 := 0.003 * pow(27.0 / 0.003, float(i) / 400.0)
		for id in Model.REACTIONS:
			var rate := Model._rate(id, t9)
			check(is_finite(rate) and rate >= 0.0, "finite nonnegative rate %d at T9=%s" % [id, t9])
	check(Model._solve(PackedFloat64Array([0, 0, 0, 0]), PackedFloat64Array([1, 1])).is_empty(), "singular linear solve reports failure")


func _failure_and_reset() -> void:
	var u = FailingModel.new()
	var before := [u.t, u.T, u.hadron, u.xH, u.xHe, u.Y.duplicate()]
	u.events["hadron"] = 0.25
	check(not u.advance(0.01), "failed numerical trial is reported")
	check([u.t, u.T, u.hadron, u.xH, u.xHe, u.Y] == before, "failed trial restores all physical state")
	check(u.events == {"hadron": 0.25}, "failed trial preserves pending accepted events")
	check(not u.advance(0.01) and u.solver_failures == 1, "failed model stays stopped")
	u.reset()
	check(u.numerical_ok and u.numerical_error.is_empty() and u.events.is_empty(), "reset clears failure and pending events")
	var normal = Model.new()
	normal.substep = 0.0
	check(not normal.advance(0.01), "invalid step rejected without an infinite loop")
	normal.reset()
	normal.substep = 0.01
	normal.advance(0.01)
	var copy = normal.clone()
	copy.Y[0] = 0.0
	copy.events["hadron"] = 3.0
	check(copy.Y != normal.Y and copy.events != normal.events, "forecast state and event storage are independent")


func _project(u) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(Chemistry.KIND_COUNT)
	out[Chemistry.K.N] = u.Yn
	out[Chemistry.K.P] = u.Yp
	out[Chemistry.K.D] = u.YD
	out[Chemistry.K.HE3] = u.Y3
	out[Chemistry.K.HE4] = u.Y4
	out[Chemistry.K.LI7] = u.Y7
	return out


func _stiff_transient() -> void:
	# An isolated rapid decay has an analytic nonnegative solution. SDIRK2's
	# large step can be negative; this must trigger bounded smaller steps.
	var u = StiffDecayModel.new()
	u.T = 1e9
	u.hadron = 1.0
	check(u._nuclear(u.T, 1.0), "stiff decay recovers instead of accepting a clipped stage")
	check(u.solver_retries > 0 and u.solver_fallbacks > 0, "stiff transient exercises subdivision and monotone fallback")
	check(u.Yn >= 0.0 and u.Yn < 1e-8 and absf(u.Yn + u.Yp - 1.0) < 1e-12, "stiff decay preserves positivity and mass")
	check(absf(u.events.get("n_to_p", 0.0) - (0.5 - u.Yn)) < 1e-10, "fallback integrates its own event quadrature")


func _step(u, h: float) -> bool:
	var expected := _project(u)
	if not u.advance(h):
		check(false, "numerical evolution: " + u.numerical_error)
		return false
	for ch in u.events:
		if ch in ["hadron", "recH", "recHe"]:
			continue
		var pair: Array = [[Chemistry.K.N], [Chemistry.K.P]] if ch == "n_to_p" else Chemistry.rule(ch, 1)
		check(not pair.is_empty(), "every nuclear channel has a renderer rule")
		if pair.is_empty():
			continue
		for k in pair[0]:
			expected[k] -= u.events[ch]
		for k in pair[1]:
			expected[k] += u.events[ch]
	var actual := _project(u)
	var error := 0.0
	var mass := 0.0
	for i in actual.size():
		error = maxf(error, absf(expected[i] - actual[i]))
	for i in Model.NSPEC:
		mass += u.Y[i] * Model.MASS[i]
		check(is_finite(u.Y[i]) and u.Y[i] >= 0.0, "accepted abundance is finite and nonnegative")
	max_event_error = maxf(max_event_error, error)
	check(error < 1e-8, "integrated signed events reproduce composition change (%s)" % error)
	check(absf(mass - 1.0) < 1e-8, "accepted trajectory conserves baryons")
	u.take_events()
	return true


func _run_to(u, target: float, warming := false) -> void:
	for step in 12000:
		if u.T >= target if warming else u.T <= target:
			return
		if not _step(u, 0.05):
			return
	check(false, "bounded trajectory reaches temperature checkpoint")


func _fluxes_and_refinement() -> void:
	var standard = Model.new()
	_run_to(standard, 1e7)
	var fine = Model.new()
	fine.substep = 0.005
	_run_to(fine, 1e7)
	check(absf(standard.helium_mass_fraction() - fine.helium_mass_fraction()) < 0.0001, "step refinement: helium mass fraction")
	for property in ["d_to_h", "he3_to_h", "li7_to_h"]:
		check(absf(standard.call(property) / fine.call(property) - 1.0) < 0.01, "step refinement: " + property)
	print("standard solver: retries=%d, fallback steps=%d" % [standard.solver_retries, standard.solver_fallbacks])
	standard.expansion = -1.0
	_run_to(standard, 3e10, true)
	standard.expansion = 2.5
	standard.eta_mult = 0.1
	_run_to(standard, 1e7)
	check(standard.solver_failures == 0, "reheat and parameter jump converge")
