extends RefCounted
#
# double_ring.gd - script curse (ticket T-051; DESIGN.md section 7.1 row "double_ring",
# the curse DESIGN.md names "Echo Ring" - the content id stays double_ring).
# Rule sentence (spec, verbatim): "every shockwave is followed by a second ring
# 0.6 s later".
# Counter-play: "two jumps".
#
# Reading (the one D-T-035-10 anticipated): every live ring release is observable on
# the YOU?! row - "ring_seq" increments and "last_ring_tick" advances together. On
# the release tick this curse schedules a second ring from the SAME origin 36 ticks
# (0.6 s) later, hosted in its state["curse_st"] scratch. The second ring grows at
# YOU?!'s own 9 u/s to the 8 u cap and kills exactly like the first: the radial
# window |d - r| <= 0.7 u (D-T-035-2) with the feet window (ring feet - 1.5, ring
# feet + 1.0) (D-T-035-1). Killer id stays "YOU" (DESIGN.md section 3.1's closed
# list carries D-YOU) - the second ring is still the shockwave's own echo.

const CURSE_ID := "double_ring"

const YOU_ID := "you"             # the enemy the curse attaches to (content names content)
const SECOND_DELAY_TICKS := 36    # 0.6 s after the first ring (the rule sentence)
const RING_SPEED := 9.0           # u/s, YOU's own ring speed
const RING_MAX := 8.0             # u, the hard cap (YOU's own, cycle 7: 14 -> 8)
const RADIAL_WINDOW := 0.7        # u: |d - r| <= 0.6/2 + 0.4 (D-T-035-2)
const FEET_BELOW := 1.5           # u below the ring's feet plane, kill extends (D-T-035-1)
const FEET_ABOVE := 1.0           # u above the ring's feet plane, kill extends (D-T-035-1)
const KILLER_ID := "YOU"          # api.kill -> "D-YOU" (D-T-035-4), the closed death code

## Per-level scratch key inside state["curse_st"]:
## [{ "due": int, "x", "y", "z", "seq": int }, ...] - one entry per echoing ring.
const ST_KEY := "double_ring"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## on_tick: detect ring releases on the row (ring_seq), schedule +36, fly the echo.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	var st: Dictionary = state.get("curse_st", {})
	var entries: Array = st.get(ST_KEY, [])
	var tick := int(state.get("tick", 0))
	var seen: Dictionary = st.get("double_ring_seen", {})
	# 1. a row whose ring_seq grew since last sight releases a ring: schedule the echo.
	# The FIRST sight of a row is only the baseline (a ring released before the curse
	# watched is not echoed - the sentence echoes every LIVE release).
	for i in range(rt.enemies.size()):
		var row = rt.enemies[i]
		if str(row.get("id", "")) != YOU_ID:
			continue
		var seq := int(row.get("ring_seq", 0))
		var key := "%d" % i
		var prev := int(seen.get(key, -1))
		if prev < 0:
			seen[key] = seq   # baseline sight
			continue
		if seq <= prev:
			continue
		seen[key] = seq
		entries.append({"due": tick + SECOND_DELAY_TICKS, "seq": seq,
				"x": float(row["x"]), "y": float(row["y"]), "z": float(row["z"])})
	st["double_ring_seen"] = seen
	# 2. fly every echo that has reached its due tick; the ring lives until the cap
	var kept: Array = []
	for e in entries:
		if tick < int(e["due"]):
			kept.append(e)
			continue
		var r: float = minf(RING_SPEED * float(tick - int(e["due"])) / 60.0, RING_MAX)
		_ring_kill(e, r, state, api)
		if r < RING_MAX:
			kept.append(e)
	st[ST_KEY] = kept


## Pure helper (test target): who dies under the ring at radius r, and the ring's
## own progress line. The kill runs through api.kill, guarded for stubbed apis.
## Player rows are T-012 controllers (Object: .get takes ONE argument) or dicts.
static func ring_hits(e: Dictionary, r: float, players: Array) -> Array:
	var out: Array = []
	for i in range(players.size()):
		var p = players[i]
		var dx: float = _num(p, "x") - float(e["x"])
		var dz: float = _num(p, "z") - float(e["z"])
		var d := sqrt(dx * dx + dz * dz)
		if absf(d - r) > RADIAL_WINDOW:
			continue
		var feet: float = _num(p, "y")
		if feet <= float(e["y"]) - FEET_BELOW or feet >= float(e["y"]) + FEET_ABOVE:
			continue
		out.append(i)
	return out


## Read a numeric key off a controller (Object) or a dict row; 0.0 when absent.
static func _num(p, key: String) -> float:
	var v: Variant = p.get(key)
	return float(v) if v != null else 0.0


## The ring's radius at t ticks after release (capped), for tests and views.
static func radius_at(t: int) -> float:
	return minf(RING_SPEED * float(maxi(t, 0)) / 60.0, RING_MAX)


static func _ring_kill(e: Dictionary, r: float, state: Dictionary, api) -> void:
	if r <= 0.0 or not api.has_method("kill"):
		return
	var hits := ring_hits(e, r, state.get("players", []))
	for i in hits:
		api.kill(i, KILLER_ID, "D-YOU")
