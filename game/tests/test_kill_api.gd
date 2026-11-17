extends RefCounted
#
# KILL API (ticket T-027; DESIGN.md section 12, D-057): body contact kills; a push never
# kills; respawn invulnerability suppresses the kill. Kill tests run with LAST LIGHT ALREADY
# SPENT - otherwise the save masks the kill (D-057). There is no partial-effect call: an
# enemy either kills or applies a non-killing effect.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Util := preload("res://tests/sim_testutil.gd")


func run() -> Array[String]:
	var f: Array[String] = []
	_contact_kills(f)
	_push_never_kills(f)
	_invuln_suppresses(f)
	_lock_and_push_shape(f)
	return f


# 11x11 flat tile arena, dais at (0, 0, 0); tile tops at y = 0.
func _arena() -> Dictionary:
	var tiles: Array = []
	for x in range(-5, 6):
		for z in range(-5, 6):
			tiles.append([x, z, 0])
	var w := Util.world_from_tiles(tiles)
	w["dais"] = [0, 0, 0]
	return w


func _spent_ctl(w: Dictionary, f: Array[String]):
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	if ctl.hud_last_light() != "lit":
		f.append("killapi: fresh controller HUD %s, want lit" % ctl.hud_last_light())
	# spend the one Last Light for real (its own path sets the flag), then clear the arrival
	# state so the fixture is exactly "alive, unshielded, Last Light spent" (D-057)
	if not ctl.try_kill("D-TEST", "test", w, []):
		f.append("killapi: spending Last Light failed")
	if not ctl.last_light_spent:
		f.append("killapi: Last Light not spent after the spend")
	ctl.invuln = 0.0
	ctl.dead = false
	ctl.place(w)
	if ctl.hud_last_light() != "grey":
		f.append("killapi: HUD %s after spending, want grey" % ctl.hud_last_light())
	return ctl


func _fixture_rt(w: Dictionary, ctl, enemy_pos: Vector3):
	var rt = EnemyRuntime.new()
	rt.setup({}, w, [ctl], 4242)
	var cfg := {"world_height": 1.8, "frame_w": 256, "frame_h": 256,
			"body_rect": [0, 0, 256, 256], "contact_kill": true, "cycle_s": 0.0,
			"preferred_kind": "", "cycle_ticks": 0}
	rt.spawn_at("tbd", "TBD", EnemyRuntime.FixtureBehavior.new(), cfg, enemy_pos)
	return rt


func _contact_kills(f: Array[String]) -> void:
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	var rt = _fixture_rt(w, ctl, Vector3(0.5, 0.0, 0.5))
	rt.step(Util.DT)
	if not ctl.dead:
		f.append("killapi: body contact did not kill")
	var deaths: Array = []
	for e in rt.events:
		if e.get("e", "") == "death":
			deaths.append(e)
	if deaths.is_empty() or deaths[0]["code"] != "D-TBD" or deaths[0]["killer"] != "TBD":
		f.append("killapi: death event wrong (%s)" % str(rt.events))
	# contact only in the y band: an enemy whose body sits below the player cannot kill
	var w2 := _arena()
	var ctl2 = _spent_ctl(w2, f)
	var rt2 = _fixture_rt(w2, ctl2, Vector3(0.5, -2.0, 0.5))
	rt2.step(Util.DT)
	if ctl2.dead:
		f.append("killapi: a fully disjoint y band killed")


func _push_never_kills(f: Array[String]) -> void:
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	# enemy 1.6 u away: no contact possible, ever
	var rt = _fixture_rt(w, ctl, Vector3(2.1, 0.0, 0.5))
	var api = EnemyRuntime.Api.new()
	api.rt = rt
	api.row = rt.enemies[0]
	var x0: float = ctl.x
	api.push(ctl, Vector3(1.0, 0.0, 0.0), 3.0)
	if absf(ctl.vx - 3.0) > 1e-6:
		f.append("killapi: the push did not set the velocity to 3 u/s on +x")
	# the runtime integrates only enemies/projectiles: the player's controller is stepped by
	# the engine caller every tick (sim.gd / T-012), so the test steps it too
	ctl.step(Util.DT, Util.mk_in(), w)
	rt.step(Util.DT)
	if ctl.dead:
		f.append("killapi: a push killed the player")
	if ctl.x <= x0:
		f.append("killapi: the push did not move the player (+x, 3 u/s)")


func _invuln_suppresses(f: Array[String]) -> void:
	# the exact state after a void-fall respawn: invuln = respawn_invulnerability (1.0 s)
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	ctl.invuln = float(ctl.C["respawn_invuln"])
	var rt = _fixture_rt(w, ctl, Vector3(0.5, 0.0, 0.5))
	rt.step(Util.DT)
	if ctl.dead:
		f.append("killapi: respawn invulnerability did not suppress the kill")
	var sup: Array = []
	for e in rt.events:
		if e.get("e", "") == "kill_suppressed":
			sup.append(e)
	if sup.is_empty():
		f.append("killapi: no kill_suppressed event under invulnerability")
	# once it runs out, the same contact kills: invuln decays inside the controller's own
	# step (the engine ticks it), so both layers step together here
	for i in range(61):
		ctl.step(Util.DT, Util.mk_in(), w)
		rt.step(Util.DT)
	if not ctl.dead:
		f.append("killapi: contact still not killing after invulnerability ended")


func _lock_and_push_shape(f: Array[String]) -> void:
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	var rt = _fixture_rt(w, ctl, Vector3(2.1, 0.0, 0.5))
	var api = EnemyRuntime.Api.new()
	api.rt = rt
	api.row = rt.enemies[0]
	api.lock_abilities(ctl, 60)   # 60 ticks = 1.0 s (D-T027-7: locks are tick-denominated)
	if not ctl.ability_locked(w):
		f.append("killapi: ability lock not active after lock_abilities(60)")
	if absf(ctl.lock - 1.0) > 1e-9:
		f.append("killapi: 60-tick lock held %.6f s, want 1.0" % ctl.lock)
	# a locked dasher cannot dash
	var pressed: Dictionary = Util.mk_in(0, 0, Util.ControllerScript.BTN_ABILITY)
	ctl.step(Util.DT, pressed, w)
	if ctl.dash_ticks > 0:
		f.append("killapi: dasher dashed under an ability lock")
	# the lock expires after ~60 ticks (61 here: the per-tick decay is 1/60 s, float dust)
	for i in range(61):
		ctl.step(Util.DT, Util.mk_in(), w)
	if ctl.ability_locked(w):
		f.append("killapi: ability lock did not expire after 60 ticks")
	# a push normalises its direction and keeps its speed
	api.push(ctl, Vector3(3.0, 4.0, 0.0), 10.0)
	var sp: float = sqrt(ctl.vx * ctl.vx + ctl.vy * ctl.vy + ctl.vz * ctl.vz)
	if absf(sp - 10.0) > 1e-6:
		f.append("killapi: pushed speed %.6f, want 10.0 (direction normalised)" % sp)
