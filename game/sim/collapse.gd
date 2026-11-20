extends RefCounted
#
# sim/collapse.gd - the platform collapse after the beacon opens (owner request,
# 2026-11-20: "the platform should have cracks on them and 5s later they fall down to
# the void. The only platform that cannot be destroyed is the spawn platform").
#
# Pure, tick-driven state (a Dictionary; static functions only; no engine clock, no RNG):
#   create(level)        - built once per level from the Level dict. Every tile and prop
#                          of every piece EXCEPT the hub (voidgen ROLE_HUB, the one spawn
#                          platform) is listed here; the hub is excluded at the source, so
#                          no later filter can leak a hub tile into either set.
#   start(st, tick)      - phase 1 CRACKS, on the tick the beacon opens (once).
#   tick(st, tick, w)    - phase 2 FALL: on start_tick + FALL_TICKS every listed tile key
#                          is written into w["removed"] (collision.tile_alive / support_at
#                          already honour it) and every listed prop box leaves
#                          w["prop_cols"]. Nothing here touches a player: a body left
#                          without support drops through the controller's own kill plane
#                          and the existing void-fall rule runs.
#
# Timing: the sim runs at a fixed 60 Hz (collision.gd header, world.gd DT = 1/60), so the
# 5.0 s crack phase is FALL_TICKS = 300 ticks. A tile is cracked on ticks
# [start_tick, start_tick + 299] and gone from start_tick + 300 on.

const VoidGenScript := preload("res://terrain/voidgen.gd")
const CollisionScript := preload("res://sim/collision.gd")

const TICK_HZ := 60
const CRACK_SECONDS := 5.0
const FALL_TICKS := 300   # CRACK_SECONDS * TICK_HZ

const EV_CRACKED := "platforms_cracked"   # + n: int (tiles cracked), fall_tick: int
const EV_FELL := "platforms_fell"         # + n: int (tiles removed from collision)

const PHASE_IDLE := 0
const PHASE_CRACKING := 1
const PHASE_FALLEN := 2


## The hub piece id of a Level dict (-1 when the dict carries none). Identified by the
## generator's own role tag, never by coordinates.
static func hub_piece(level: Dictionary) -> int:
	for p in level.get("pieces", []):
		if int(p.get("role", -1)) == VoidGenScript.ROLE_HUB:
			return int(p["id"])
	return -1


## A fresh collapse state for one level. keys are the non-hub tile keys "x,z,y_hu" in the
## Level dict's tile order (deterministic); props are [col key, y, h] for non-hub props.
static func create(level: Dictionary) -> Dictionary:
	var hub := hub_piece(level)
	var keys: Array = []
	var seen := {}
	var hub_keys := {}
	for t in level.get("tiles", []):
		var key: String = CollisionScript.tile_key(int(t[0]), int(t[1]), int(t[2]))
		if int(t[4]) == hub:
			hub_keys[key] = true
			continue
		if seen.has(key):
			continue
		seen[key] = true
		keys.append(key)
	var props: Array = []
	for p in level.get("props", []):
		if int(p[5]) == hub:
			continue
		props.append(["%d,%d" % [int(p[0]), int(p[1])], int(p[2]), int(p[3])])
	return {
		"enabled": true,
		"hub_piece": hub,
		"hub_keys": hub_keys,   # read-only reference for views and tests
		"keys": keys,
		"key_set": seen,
		"props": props,
		"phase": PHASE_IDLE,
		"start_tick": -1,
		"fall_tick": -1,
		"removed_n": 0,
	}


## Phase 1: cracks begin on this tick. Returns the platforms_cracked event ({} when the
## state is disabled, already started, or has nothing to crack).
static func start(st: Dictionary, tick: int) -> Dictionary:
	if st.is_empty() or not bool(st.get("enabled", true)):
		return {}
	if int(st["phase"]) != PHASE_IDLE:
		return {}
	st["phase"] = PHASE_CRACKING
	st["start_tick"] = tick
	st["fall_tick"] = tick + FALL_TICKS
	return {"e": EV_CRACKED, "tick": tick, "n": (st["keys"] as Array).size(),
			"fall_tick": tick + FALL_TICKS}


## Phase 2: on the fall tick (or the first tick past it) every listed tile leaves
## collision. Returns the removed tile keys on that one tick, [] on every other tick.
## Appends a platforms_fell event to ev when given.
static func tick(st: Dictionary, p_tick: int, w: Dictionary, ev: Variant = null) -> Array:
	if st.is_empty() or int(st["phase"]) != PHASE_CRACKING:
		return []
	if p_tick < int(st["fall_tick"]):
		return []
	st["phase"] = PHASE_FALLEN
	var out: Array = []
	var removed: Dictionary = w["removed"]
	for key in st["keys"]:
		if not removed.has(key):
			removed[key] = true
		out.append(key)
	var pcols: Dictionary = w.get("prop_cols", {})
	for pr in st["props"]:
		var lst: Array = pcols.get(pr[0], [])
		for i in range(lst.size() - 1, -1, -1):
			if int(lst[i]["y"]) == int(pr[1]) and int(lst[i]["h"]) == int(pr[2]):
				lst.remove_at(i)
				break
		if lst.is_empty() and pcols.has(pr[0]):
			pcols.erase(pr[0])
	st["removed_n"] = out.size()
	if ev is Array:
		(ev as Array).append({"e": EV_FELL, "tick": p_tick, "n": out.size()})
	return out


# ---- read-only queries (views and tests) ------------------------------------------

static func phase(st: Dictionary) -> int:
	return PHASE_IDLE if st.is_empty() else int(st["phase"])


## True while the cracks are showing (start tick through fall tick - 1).
static func is_cracking(st: Dictionary) -> bool:
	return phase(st) == PHASE_CRACKING


## The tile keys currently cracked: every listed key from the start tick until the fall.
static func cracked_keys(st: Dictionary) -> Array:
	if phase(st) != PHASE_CRACKING:
		return []
	return st["keys"]


## True when tile key "x,z,y_hu" is part of the collapse (never a hub tile).
static func listed(st: Dictionary, key: String) -> bool:
	return not st.is_empty() and (st["key_set"] as Dictionary).has(key)


## 0..1 progress through the crack phase on p_tick (1.0 once fallen, 0.0 before start).
static func crack_progress(st: Dictionary, p_tick: int) -> float:
	match phase(st):
		PHASE_CRACKING:
			return clampf(float(p_tick - int(st["start_tick"])) / float(FALL_TICKS), 0.0, 1.0)
		PHASE_FALLEN:
			return 1.0
	return 0.0


## Ticks since the fall (-1 before it).
static func ticks_since_fall(st: Dictionary, p_tick: int) -> int:
	if phase(st) != PHASE_FALLEN:
		return -1
	return p_tick - int(st["fall_tick"])
