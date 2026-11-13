extends SceneTree
## Exercise the actual scene, including controls, forecasts and restart state.

var checks := 0
var failures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._skip_intro()
	game.intro_t = 100.0
	game.field.set_process(false)
	game._fc_out = {"yp": 0.1, "dh": 0.001}
	game.hud.expansion_changed.emit(1.8)
	check(game._fc == null and game._fc_out.is_empty(), "expansion change immediately removes stale forecast")
	game._fc_out = {"yp": 0.1, "dh": 0.001}
	game.hud.density_changed.emit(-1.0)
	check(game._fc == null and game._fc_out.is_empty(), "density change immediately removes stale forecast")
	game.u.expansion = -1.0
	game._fc_out = {"yp": 0.1, "dh": 0.001}
	game._forecast_step()
	check(game._fc == null and game._fc_out.is_empty(), "contraction has no cooling forecast")
	game.u.expansion = 0.0
	game._forecast_step()
	check(game._fc == null, "zero expansion does not create a nonterminating forecast")
	game.u.expansion = 1.0
	game.u.eta_mult = 1.0
	for i in 5000:
		game._forecast_step()
		if not game._fc_out.is_empty():
			break
	check(not game._fc_out.is_empty(), "forecast completes within bounded work")
	check(absf(float(game._fc_out.get("yp", 0.0)) - 0.2457) < 0.001, "forecast agrees with standard helium result")
	game.autopilot = true
	game.u.expansion = 1.8
	game._autopilot(0.1)
	game._forecast_step()
	check(game._fc_out.is_empty(), "autopilot invalidates a previous forecast")
	game.autopilot = false
	game.paused = true
	var before: float = game.u.t
	game._process(1.0 / 60.0)
	check(game.u.t == before, "pause freezes physical time")
	game.field._alloc()
	var observed: int = game.field._spawn(game.PK.H, Vector2(100, 100), Vector2.ZERO, false)
	game.field.follow = observed
	var observation_lines: Array[String] = []
	game.hud.show_inspect("Observed atom", observation_lines)
	game.u.T = 1e6
	game.u.hadron = 1.0
	game.field.sync(game.u)
	game.field._resync_requested = true
	game.field.step_chemistry(1.0 / 60.0)
	check(game.field.follow == -1 and not game.hud._inspect.visible, "reconciliation ends the actual observation panel")
	check(game.hud._lines.has(game.I18n.t("observation_ended")), "ended observation is explained in the scene")
	game.paused = false
	game.u.T = 39.0
	game.u.t = 1e16
	game.u.expansion = -1.0
	game._process(1.0 / 60.0)
	check(game.u.T > 39.0, "contraction can reheat below the cooling stop temperature")
	game._lmb_down = true
	game._panning = true
	game.field.hand_mode = 1
	game.field.follow = 0
	game.field.follow_log.append("previous universe")
	game._fc_out = {"yp": 0.1}
	game.u.numerical_ok = false
	game._numerical_stop()
	check(game.paused and game._fc_out.is_empty(), "failed calculation pauses and removes forecasts")
	game._toggle_pause()
	check(game.paused, "failed calculation cannot silently resume")
	game._start()
	check(game.u.numerical_ok and not game.paused, "restart restores a valid calculation")
	check(not game._lmb_down and not game._panning and game.field.hand_mode == 0, "restart releases input state")
	check(game.field.follow == -1 and game.field.follow_log.is_empty(), "restart clears observation history")
	check(game._fc == null and game._fc_out.is_empty() and game.field.acc.is_empty(), "restart clears forecasts and events")
	check(not game.hud._inspect.visible and not game.field.visible, "restart returns to the initial scene")
	# Let Godot release the scene and audio resources before ending the process.
	game.queue_free()
	for i in 4:
		await process_frame
	print("LIFECYCLE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
