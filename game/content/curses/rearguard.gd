extends RefCounted
#
# rearguard.gd - the Rearguard script curse (DESIGN.md section 7.2, GENERAL family;
# ticket T-051).
#
# Rule: "when the beacon opens, one extra copy of a random enemy in play spawns at the beacon".
#
# "A random enemy in play" = one enemy id from this level's live spawn plan (the
# runtime's planned[] rows carry {"id", "name", "behavior", "cfg", "copies"}). The pick
# is the run's own enemy_ai RNG stream (api.rng(), D-T010-3), so replays are exact. The
# spawn itself is api.spawn_enemy(id, pos) - the DESIGN.md section 12 curse-API surface
# ("spawn entity"); the dispatcher (the run's runtime step) performs it: a REAL body of
# the SAME content id at the beacon axis (x + 0.5, floor top, z + 0.5), same kill rules
# as any copy of that enemy. With no enemy in play the hook is a no-op - never a crash,
# never an invented enemy.
#
# max_stacks is 1 (curse.json): exactly one extra copy per beacon open.

const CURSE_ID := "rearguard"


## Stacks the run holds; >= 1 while the curse is picked (the sim's {curse_id: stacks}).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## on_beacon_open(state, api): fired by the dispatcher on the same tick sim/gifts.gd
## opens the beacon. Picks one in-play enemy id at random and requests the spawn.
static func on_beacon_open(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return  # not held: no extra enemy, the beacon open stays clean
	var plan_ids := in_play_ids(state)
	if plan_ids.is_empty():
		return
	var rng = null
	if api != null and api.has_method("rng"):
		rng = api.rng()
	var id := pick_id(plan_ids, rng)
	var b = state.get("beacon", null)
	if b == null:
		return
	var pos := Vector3(float(b.cx), float(b.base_y), float(b.cz))
	if api != null and api.has_method("spawn_enemy"):
		api.spawn_enemy(id, pos)
		_announce(state, id)


## The plan rows' distinct ids this level has in play (state["spawn_plan"]; the runtime's
## planned[] shape). Read-only, insertion order kept.
static func in_play_ids(state: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for row_v in state.get("spawn_plan", []):
		if row_v == null or not (row_v is Dictionary):
			continue
		var id := str(row_v.get("id", ""))
		if id != "" and not out.has(id):
			out.append(id)
	return out


## The random pick. rng: an object with u32() (terrain/void_rng.gd's VoidRng; the enemy
## runtime's own stream shape). A null rng is NOT random - it takes the FIRST id, so a
## caller without a stream stays deterministic and honest about it.
static func pick_id(plan_ids: Array[String], rng) -> String:
	if plan_ids.is_empty():
		return ""
	if rng != null:
		return plan_ids[int(rng.u32()) % plan_ids.size()]
	return plan_ids[0]


static func _announce(state: Dictionary, id: String) -> void:
	var evs: Variant = state.get("events", null)
	if evs is Array:
		evs.append({"e": "rearguard_spawn", "id": id})
