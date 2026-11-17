extends RefCounted
#
# aftershock.gd - script curse (ticket T-051; DESIGN.md section 7.1 row "aftershock").
# Rule sentence (spec, verbatim): "landing sends a second shockwave 0.5 s later,
# radius 9 u".
# Counter-play: "double jump".
#
# Reading (recorded in DECISIONS.md): coil's landing and its first shockwave are
# observable on the coil row (the landing snaps the row onto the locked zone and
# builds row["shock"] = {"ticks": 30, "index", "dir"}, state
# "recover" - D-T-031-11). On the landing tick this curse records the wave point
# and a 30-tick (0.5 s) delay in its state["curse_st"] scratch. On the due tick it
# re-pushes every player still inside a WAVE_RADIUS sphere of the wave point with
# coil's own 8 u/s linear-to-zero decay over 30 ticks. A push never kills
# (DESIGN.md section 12), so the second shockwave never kills either.

const CURSE_ID := "aftershock"

const COIL_ID := "coil"           # the enemy the curse attaches to (content names content)
const WAVE_DELAY_TICKS := 30      # 0.5 s after the first landing (the rule sentence)
const WAVE_RADIUS := 9.0          # u, the second shockwave's radius
const SHOCK_PUSH := 8.0           # u/s, coil's own push strength
const SHOCK_TICKS := 30           # 0.5 s linear decay window (coil's own)

## Per-level scratch key inside state["curse_st"]: [{ "due": int, "x", "y", "z" }, ...].
const ST_KEY := "aftershock"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## on_tick: watch coil rows for a landing; 30 ticks later fire the second wave.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	var st: Dictionary = state.get("curse_st", {})
	var entries: Array = st.get(ST_KEY, [])
	var tick := int(state.get("tick", 0))
	# 1. detect this tick's landings, schedule each at due = tick + 30
	for i in range(rt.enemies.size()):
		var row = rt.enemies[i]
		if str(row.get("id", "")) != COIL_ID:
			continue
		var shock: Variant = row.get("shock", null)
		if not (shock is Dictionary):
			continue
		var key := "as_landed_%d" % (i + 1)
		if int(shock.get("ticks", 0)) != SHOCK_TICKS or st.has(key):
			continue   # an aged or already-served shock, not this tick's landing
		st[key] = true
		entries.append({"due": tick + WAVE_DELAY_TICKS, "x": float(row["x"]),
				"y": float(row["y"]), "z": float(row["z"])})
	# 2. fire every entry that comes due
	var kept: Array = []
	for e in entries:
		if int(e["due"]) > tick:
			kept.append(e)
			continue
		_fire_wave(e, state, api)
	st[ST_KEY] = kept


## The second wave itself: every player still within WAVE_RADIUS of the wave point
## is pushed the same way coil's first wave pushed (speed decaying linearly to 0
## over 30 ticks, horizontal outward direction). Never a kill.
static func _fire_wave(e: Dictionary, state: Dictionary, api) -> void:
	var players: Array = state.get("players", [])
	for i in range(players.size()):
		var p = players[i]
		var dx: float = _num(p, "x") - float(e["x"])
		var dz: float = _num(p, "z") - float(e["z"])
		var dy: float = _num(p, "y") - float(e["y"])
		var d2: float = dx * dx + dz * dz + dy * dy
		if d2 > WAVE_RADIUS * WAVE_RADIUS:
			continue
		var d := sqrt(d2)
		if d <= 1e-6:
			continue   # dead centre: no meaningful outward direction, push plays out tick by tick
		var dir: Vector3 = Vector3(dx / d, 0.0, dz / d)
		if api.has_method("push"):
			api.push(i, dir, SHOCK_PUSH)
	if api.has_method("telegraph"):
		_announce(e, api)


## A player row is a T-012 controller (an Object: .get takes ONE argument) or a
## plain dict - read a numeric key off either, 0.0 when absent.
static func _num(p, key: String) -> float:
	var v: Variant = p.get(key)
	return float(v) if v != null else 0.0


## The view's echo ring so the second wave is readable: a one-tick telegraph of the
## same shape vocabulary coil uses (a circle on the landing plane).
static func _announce(e: Dictionary, api) -> void:
	var shape: Dictionary = {"shape": "circle", "cx": float(e["x"]), "cz": float(e["z"]),
			"r": WAVE_RADIUS, "y0": float(e["y"]), "y1": float(e["y"])}
	if api.has_method("telegraph"):
		api.telegraph("aftershock_ring", shape, 30)
