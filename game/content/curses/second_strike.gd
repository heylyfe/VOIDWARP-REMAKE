extends RefCounted
#
# second_strike.gd - script curse (DESIGN.md section 7.1 row "second_strike").
# Rule sentence (spec, verbatim): "a second missile lands 1.0 s after the first on
# your new position".
# Counter-play: "keep running after the first — the second kills too".
#
# Reading: the first missile detonates on the point the nuke locked 1.5 s earlier
# (the ring, 5.5), so "your new position" is where the player STANDS when the first
# blast resolves - not the ring's centre. The curse catches the blast tick (the nuke
# row entering its pause with paused_by "blast"), records the targeted player's
# current position, announces the nuke's own ground ring there for the 1.0 s, and on
# the due tick kills every player inside the nuke's own 5 u blast sphere. Running for
# that second is the counter-play: the point never re-aims after the blast tick.
#
# The second missile is the nuke's own language throughout - the same "ground_ring"
# telegraph kind, the same 5 u sphere, the same D-NUKE death code - so nothing new is
# invented; only the timing and the aim point are the curse's.

const CURSE_ID := "second_strike"

const NUKE_ID := "nuke"              # the enemy the curse attaches to (content names content)
const SECOND_DELAY_TICKS := 60       # 1.0 s after the first blast (the rule sentence)
const BLAST_RADIUS := 5.0            # the nuke's own blast sphere (5.5 / enemy.json)
const DEATH_CODE := "D-NUKE"         # the nuke's own code (3.1 FINAL)
const RING_KIND := "ground_ring"     # the nuke's own telegraph kind (5.5)
const PAUSE := "pause"               # the nuke's post-blast phase (5.5)

## Per-level scratch: ST_KEY -> [{ "due": int, "x", "y", "z", "player": int }, ...];
## "ss_prev_<row index>" -> the row's last seen phase (the blast-tick transition).
const ST_KEY := "second_strike"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## on_tick: catch each blast, then land every second missile that comes due.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	var st: Dictionary = state.get("curse_st", {})
	var entries: Array = st.get(ST_KEY, [])
	var tick := int(state.get("tick", 0))
	# 1. this tick's blasts: a nuke row ENTERING its blast pause (the transition, so a
	# 300-tick pause schedules exactly one second missile)
	for i in range(rt.enemies.size()):
		var row = rt.enemies[i]
		if str(row.get("id", "")) != NUKE_ID:
			continue
		var phase := str(row.get("phase", ""))
		var key := "ss_prev_%d" % i
		var prev := str(st.get(key, ""))
		st[key] = phase
		if phase != PAUSE or prev == PAUSE:
			continue
		if str(row.get("paused_by", "")) != "blast":
			continue   # an expired salvo never fired: nothing to echo
		var e: Variant = _schedule(row, state, api, tick)
		if e != null:
			entries.append(e)
	# 2. land every missile that has reached its due tick
	var kept: Array = []
	for e in entries:
		if int(e["due"]) > tick:
			kept.append(e)
			continue
		_land(e, state, api)
	st[ST_KEY] = kept


## Record the targeted player's NEW position (where they stand on the blast tick) and
## announce the nuke's own ground ring there for the 1.0 s. The target is the player
## the first blast aimed at: the nearest one to the detonation point.
static func _schedule(row: Dictionary, state: Dictionary, api, tick: int) -> Variant:
	var origin := Vector3(float(row["x"]), float(row["y"]), float(row["z"]))
	var det: Variant = row.get("det", null)
	if det is Dictionary and det.has("x"):
		origin = Vector3(float(det["x"]), float(det["y"]), float(det["z"]))
	var near: Dictionary = {}
	if api != null and api.has_method("nearest_player"):
		near = api.nearest_player(origin)
	if near.is_empty():
		return null
	var idx := int(near.get("index", 0))
	var p = _player(state, idx)
	if p == null:
		return null
	var e := {"due": tick + SECOND_DELAY_TICKS, "x": _num(p, "x"), "y": _num(p, "y"),
			"z": _num(p, "z"), "player": idx}
	if api.has_method("telegraph"):
		api.telegraph(RING_KIND, {"shape": "circle", "cx": float(e["x"]),
				"cz": float(e["z"]), "r": BLAST_RADIUS, "y0": float(e["y"]),
				"y1": float(e["y"]) + 0.6}, SECOND_DELAY_TICKS)
	return e


## The second missile: every player inside the nuke's own 5 u sphere of the recorded
## point dies with the nuke's own code. A player who ran is outside it.
static func _land(e: Dictionary, state: Dictionary, api) -> void:
	if api == null or not api.has_method("kill"):
		return
	var players: Array = state.get("players", [])
	for i in range(players.size()):
		var p = players[i]
		var dx: float = _num(p, "x") - float(e["x"])
		var dy: float = _num(p, "y") - float(e["y"])
		var dz: float = _num(p, "z") - float(e["z"])
		if sqrt(dx * dx + dy * dy + dz * dz) > BLAST_RADIUS:
			continue
		api.kill(i, NUKE_ID, DEATH_CODE)


## The player row at `idx` (a T-012 controller or a plain dict), or null.
static func _player(state: Dictionary, idx: int):
	var players: Array = state.get("players", [])
	if idx < 0 or idx >= players.size():
		return null
	return players[idx]


## Read a numeric key off a controller (Object) or a dict row; 0.0 when absent.
static func _num(p, key: String) -> float:
	var v: Variant = p.get(key)
	return float(v) if v != null else 0.0
