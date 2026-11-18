extends SceneTree
#
# Feel probe A12 (FLEET_PACK.md section 4; ticket T-061) - headless:
#
#   <godot> --headless --path game --script res://tools/feel_probe.gd
#
# One PASS/FAIL row per A12 feel-budget item (DESIGN.md section 2), the measured number
# next to the bound:
#
#   PASS loading_screen_hold       5.000 s  >= 5.0 s (first launch)
#   PASS loading_screen_total_l30  5.000 s  <= 8.0 s (first launch)
#   PASS loading_restart_hold      2.000 s  >= 2.0 s (restart, never less)
#   PASS loading_restart_total_l30 2.000 s  <= 2.0 s (restart, never more)
#   PASS gate_to_level             0.310 s  <= 2.0 s
#   PASS death_to_run_over         0.000 s  <= 2.0 s
#   PASS void_fall_to_respawn      0.800 s  <= 0.80 s
#   PASS generate_mesh_l30         0.292 s  <= 1.5 s
#   T-061 RESULT: OK    (or: T-061 RESULT: FAIL n rows, exit 1)
#
# Measurement method per row (DECISIONS D-T061-2 - the app orchestrator that owns the real
# screen-to-screen transitions does not exist yet, so each row measures the real shipped
# code path that exists today):
#   - loading_screen_hold / loading_screen_total_l30 (first launch, 5.0 s) and
#     loading_restart_hold / loading_restart_total_l30 (every restart, exactly 2.0 s): the REAL
#     app/loading_screen.gd two-duration law (owner ruling, D-LOAD-5), driven with the measured
#     level-30 build time as its load duration; the hold is the loading screen's shown time at
#     completion.
#   - gate_to_level: the whole "make the next level controllable" pipeline for level 30,
#     seed 7 - voidgen.generate + collision.make_world + level_mesher.build +
#     LevelState.build. No loading screen sits between levels (DESIGN.md section 2).
#   - death_to_run_over: a real contact kill through PlayerRuntime (kiwi cat, burst body
#     rule) with Last Light spent; wall clock from the killing tick through
#     sim/death.gd screen_data() to the view/hud/run_over.gd screen build.
#   - void_fall_to_respawn: the real controller stepped on a real world; sim time from
#     the void_fall event (the void-fall moment, the controller's own kill-plane crossing)
#     to the respawn event.
#   - generate_mesh_l30: voidgen.generate(seed 7, 30) + level_mesher.build, the MEDIAN of
#     5 wall-clocked runs (the first of which has been preceded by one warm-up level 12
#     generate, so first-call costs are not measured).

const VoidGenScript := preload("res://terrain/voidgen.gd")
const CollisionScript := preload("res://sim/collision.gd")
const MesherScript := preload("res://view/level_mesher.gd")
const LevelStateScript := preload("res://sim/level_state.gd")
const ControllerScript := preload("res://sim/controller.gd")
const LoadingScript := preload("res://app/loading_screen.gd")
const EnemyRuntimeScript := preload("res://sim/enemy_runtime.gd")
const KiwiScript := preload("res://content/enemies/kiwi_cat/enemy.gd")
const DeathScript := preload("res://sim/death.gd")
const RunOverScript := preload("res://view/hud/run_over.gd")
const Util := preload("res://tests/sim_testutil.gd")

const DT := 1.0 / 60.0
const SEED := 7
const LEVEL := 30
const REPS := 5      # median-of-5 per generated-level row
const STEP := 0.05   # the loading screen's advance step, as in tests/test_loading.gd
const WARM_LEVEL := 12   # one warm-up generate: pre-caches/outlines the generator, level mid-range

var rows: Array = []   # [passed, name, number_string, bound_string]


func _init() -> void:
	# One warm-up run through the pipeline so first-call import costs are not measured.
	VoidGenScript.generate(SEED, WARM_LEVEL, 1, 0)
	# The pipeline numbers feed three of the six rows.
	var t := _time_pipeline()
	print("CONTEXT seed=%d level=%d median generate=%.3f s mesh=%.3f s full-pipeline=%.3f s (%d runs)"
			% [SEED, LEVEL, t["gen"], t["mesh"], t["full"], REPS])
	_loading_rows(t["gen"] + t["mesh"], t["full"])
	_gate_to_level_row(t["full"])
	_death_row()
	_void_fall_row()
	_generate_mesh_row(t["gen"] + t["mesh"])
	_finish()


# ---- rows -------------------------------------------------------------------------------------

func _loading_rows(load_s: float, full_s: float) -> void:
	# The real loading screen component, driven exactly as tests/test_loading.gd drives it, under the
	# owner's two-duration law (D-LOAD-5): the session's FIRST launch holds 5.0 s, EVERY RESTART holds
	# exactly 2.0 s (never less, never more). Four rows: the first-launch pair keeps its original
	# bounds (>= 5.0 s hold, <= 8.0 s total at level 30); the restart pair is the new law's bounds.
	var first := _loading_run(true, load_s)
	if first < 0.0:
		_row(false, "loading_screen_hold", "never", ">= 5.0 s (first launch)")
		_row(false, "loading_screen_total_l30", "never", "<= 8.0 s (first launch)")
	else:
		_row(first >= 5.0, "loading_screen_hold", "%.3f s" % first, ">= 5.0 s (first launch)")
		_row(first <= 8.0, "loading_screen_total_l30", "%.3f s" % first,
				"<= 8.0 s (first launch: hold 5.0 + build %.3f s)" % full_s)
	var restart := _loading_run(false, load_s)
	if restart < 0.0:
		_row(false, "loading_restart_hold", "never", ">= 2.0 s (restart)")
		_row(false, "loading_restart_total_l30", "never", "<= 2.0 s (restart)")
	else:
		_row(restart >= 2.0 - 1e-6, "loading_restart_hold", "%.3f s" % restart, ">= 2.0 s (restart, never less)")
		_row(restart <= 2.0 + 1e-6, "loading_restart_total_l30", "%.3f s" % restart,
				"<= 2.0 s (restart, never more: a fast load never waits past it; build %.3f s)" % full_s)


## Shown time at completion of one load of `load_s` seconds on the real loading screen, or -1.0 when it
## never completes inside 60 s.
func _loading_run(first_launch: bool, load_s: float) -> float:
	var ls := LoadingScript.new()
	ls.start(SEED, load_s, first_launch)
	while not ls.is_complete() and ls.shown_time() < 60.0:
		ls.advance(STEP)
	if not ls.is_complete():
		return -1.0
	return ls.shown_time()


func _gate_to_level_row(full_s: float) -> void:
	# lobby gate -> next level controllable = the no-loading-screen build pipeline itself.
	# A negative number is _time_pipeline's failed-pipeline sentinel: a failed build is never a PASS.
	_row(full_s >= 0.0 and full_s <= 2.0, "gate_to_level", "%.3f s" % full_s,
			"<= 2.0 s (gen+world+mesh+sim state, level %d)" % LEVEL)


func _death_row() -> void:
	# Real kill chain: kiwi cat body contact -> dead + code -> screen_data -> run-over screen.
	var lv := _strip_level()
	var w := CollisionScript.make_world(lv["tiles"], lv["props"], lv["pads"])
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true   # D-057: kill tests run with Last Light spent
	var rt = EnemyRuntimeScript.new()
	rt.setup(lv, w, [ctl], SEED)
	rt.spawn_at("kiwi_cat", "kiwi cat", KiwiScript.KiwiCatBehavior.new(),
			KiwiScript.cfg().duplicate(true), Vector3(ctl.x + 1.6, 0.0, ctl.z))
	var t0 := Time.get_ticks_usec()
	var tick := 0
	var dead_tick := -1
	while tick < 600:
		ctl.step(DT, {"move_x": 0, "move_z": 0, "buttons": 0, "aim_x": 0.0, "aim_z": 1.0}, w)
		rt.step(DT)
		tick += 1
		if ctl.dead:
			dead_tick = tick
			break
	if dead_tick < 0:
		_row(false, "death_to_run_over", "no kill in 600 ticks", "<= 2.0 s")
		return
	var sd := DeathScript.screen_data(ctl, LEVEL)
	var screen := RunOverScript.new()   # the HUD cell builds its whole tree in _init
	screen.show_run_over(sd)
	var num := float(Time.get_ticks_usec() - t0) / 1.0e6
	var ok := num <= 2.0 and not sd.is_empty() and screen.visible
	_row(ok, "death_to_run_over", "%.4f s" % num,
			"<= 2.0 s (kill tick -> screen_data + run-over build; %s)" % str(sd.get("killer", "")))


func _void_fall_row() -> void:
	# The controller's own void-fall moment (its kill-plane crossing) to the respawn event.
	var lv := _strip_level()
	var w := CollisionScript.make_world(lv["tiles"], lv["props"], lv["pads"])
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.charges = 1   # one charge: the respawn path, not the D-VOID death
	var ev_target := {"fell": -1, "respawn": -1}
	var tick := 0
	while tick < 1200:
		ctl.step(DT, {"move_x": 127, "move_z": 0, "buttons": 0, "aim_x": 1.0, "aim_z": 0.0}, w)
		tick += 1
		# cbStep events come back from the step - read the controller's live state instead:
		if ev_target["fell"] < 0 and ctl.respawn_t >= 0.0:
			ev_target["fell"] = tick
		if ev_target["fell"] >= 0 and ev_target["respawn"] < 0 and ctl.respawn_t < 0.0 \
				and ctl.grounded and tick > ev_target["fell"]:
			ev_target["respawn"] = tick
			break
	if ev_target["fell"] < 0 or ev_target["respawn"] < 0:
		_row(false, "void_fall_to_respawn", "never (%s)" % str(ev_target), "<= 0.80 s")
		return
	var num := float(ev_target["respawn"] - ev_target["fell"]) * DT
	_row(num <= 0.80 + 1e-9, "void_fall_to_respawn", "%.3f s" % num,
			"<= 0.80 s (void_fall -> respawn; landed on %s)" % ctl.cur_key)


func _generate_mesh_row(gen_mesh_s: float) -> void:
	# median-of-5, computed in _time_pipeline; re-asserted here as its own row.
	# A negative number is _time_pipeline's failed-pipeline sentinel: a failed build is never a PASS.
	_row(gen_mesh_s >= 0.0 and gen_mesh_s <= 1.5, "generate_mesh_l30", "%.3f s" % gen_mesh_s,
			"<= 1.5 s (voidgen + level_mesher, seed %d)" % SEED)


# ---- helpers ----------------------------------------------------------------------------------

## Wall-clocks the REPS-runs median of the level-%d pipeline. gen = voidgen.generate,
## mesh = level_mesher.build (of the last generated level), full = one consecutive pass of
## generate + make_world + mesher + LevelState.build (an independent run, not the sum of
## the two separate medians). Returns {"gen", "mesh", "full"} in seconds.
func _time_pipeline() -> Dictionary:
	var gens: Array = []
	var meshs: Array = []
	var fulls: Array = []
	for i in range(REPS):
		var t0 := Time.get_ticks_usec()
		var L: Dictionary = VoidGenScript.generate(SEED, LEVEL, 1, 0)
		var t1 := Time.get_ticks_usec()
		# The empty-level check comes before L's keys are read: {} must reach the sentinel too.
		if L.is_empty():
			return {"gen": -1.0, "mesh": -1.0, "full": -1.0}
		var w := CollisionScript.make_world(L["tiles"], L["props"], L["pads"])
		var m: Dictionary = MesherScript.build(L)
		var t2 := Time.get_ticks_usec()
		var st = LevelStateScript.build(L, LEVEL, 1, SEED)
		var t3 := Time.get_ticks_usec()
		if m.get("meshes", {}).is_empty() or st == null:
			return {"gen": -1.0, "mesh": -1.0, "full": -1.0}
		gens.append(float(t1 - t0) / 1.0e6)
		meshs.append(float(t2 - t1) / 1.0e6)
		fulls.append(float(t3 - t0) / 1.0e6)
	return {"gen": _median(gens), "mesh": _median(meshs), "full": _median(fulls)}


func _median(v: Array) -> float:
	var a := v.duplicate()
	a.sort()
	return float(a[int(a.size() / 2)])


## A small synthetic level (the shape the sim tests use): a walkable strip of tiles at
## y = 0 that ends in void to the +x side, no props, no pads.
func _strip_level() -> Dictionary:
	var tiles: Array = []
	for x in range(-4, 10):
		tiles.append([x, 0, 0, 0, 0])
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": tiles, "props": [], "pads": []}


func _row(passed: bool, name: String, number: String, bound: String) -> void:
	rows.append([passed, name, number, bound])


func _finish() -> void:
	var fails := 0
	for r in rows:
		if not bool(r[0]):
			fails += 1
		print("%s %s %s %s" % ["PASS" if bool(r[0]) else "FAIL", str(r[1]), str(r[2]), str(r[3])])
	if fails > 0:
		print("T-061 RESULT: FAIL %d rows" % fails)
		quit(1)
	else:
		print("T-061 RESULT: OK")
		quit(0)
