extends RefCounted
#
# pup_pack.gd - script curse (DESIGN.md section 7.1 row "pup_pack").
# Rule sentence (spec, verbatim): "every seal has a second seal that dashes 0.5 s
# after it".
# Counter-play: "**jump each bark** — each seal's line is fixed at its own telegraph
# start and the barks never coincide (caps + stagger, D-069/SR-3)".
#
# Reading: the second seal is a REAL seal row (api.spawn_enemy, guarded - a stubbed
# harness schedules it for the next tick instead of failing), spawned on its partner's
# spot with the partner's own cfg plus the pairing marker. Its dash is staggered, not
# re-aimed: the curse holds it in the seal's own "recover" phase (a legitimate row
# state - the behavior only counts that phase down) until its partner's telegraph
# starts, then starts the second seal's OWN telegraph with phase_left = 45 + 30, so the
# behavior's own dash lands exactly 30 ticks (0.5 s) after the first seal's. The line is
# fixed at that telegraph start from the second seal's own position (D-069), so the two
# barks never coincide and each line is its own.
#
# The second seal is never paired again (its cfg carries the marker), so the pack is
# exactly one extra body per seal - no growth. A partner that never strikes (the player
# outside its own 4-12 u band) leaves the second seal holding still: it mirrors its
# partner's strike, it does not hunt on its own.

const CURSE_ID := "pup_pack"

const SEAL_ID := "seal"              # the enemy the curse attaches to (content names content)
const DASH_DELAY_TICKS := 30         # 0.5 s after the first seal's dash (the rule sentence)
const TELEGRAPH_TICKS := 45          # the seal's own 0.75 s telegraph (5.9)
const DASH_TICKS := 60               # the seal's own 1.0 s dash (5.9)
const DASH_LENGTH_U := 20.0          # the seal's own 20 u fixed line (5.9)
const BODY_HEIGHT := 0.6             # the seal's own body height (SR-2)
const PLAYER_CENTRE_U := 0.9         # the seal's own aim point above the feet (5.9)
const KIND := "dash_line"            # the seal's own telegraph kind (5.9)
const HOLD_TICKS := 100000           # the parked phase_left: the second seal waits still
const SECOND_MARK := "pup_pack_of"   # the spawned cfg's pairing marker (never re-paired)

## Per-level scratch, keyed by the FIRST seal's row index:
##   "pp_pair_<i>" true once the spawn was requested   "pp_prev_<i>" its last phase
##   "pp_start_<i>" its telegraph start tick           "pp_released_<i>" true once driven
const ST_KEY := "pup_pack"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## The stagger in ticks (the rule sentence's 0.5 s). Pure helper.
static func dash_delay_ticks() -> int:
	return DASH_DELAY_TICKS


## The second seal's telegraph length: its own 45 ticks plus the 30-tick stagger, so the
## behavior's own dash lands 0.5 s after its partner's. Pure helper - the test target.
static func second_telegraph_ticks() -> int:
	return TELEGRAPH_TICKS + DASH_DELAY_TICKS


## on_tick: pair every seal once, then stagger its partner's dash.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	var st: Dictionary = state.get("curse_st", {})
	var tick := int(state.get("tick", 0))
	for i in range(rt.enemies.size()):
		var row = rt.enemies[i]
		if str(row.get("id", "")) != SEAL_ID:
			continue
		var cfg: Dictionary = row.get("cfg", {})
		if cfg.has(SECOND_MARK):
			continue   # a second seal is never paired again (no growth)
		var phase := str(row.get("phase", "flap"))
		var prev_key := "pp_prev_%d" % i
		var prev := str(st.get(prev_key, ""))
		st[prev_key] = phase
		# 1. one second seal per seal, spawned on its partner's spot
		var pair_key := "pp_pair_%d" % i
		if not st.has(pair_key):
			if api != null and api.has_method("spawn_enemy"):
				st[pair_key] = true
				api.spawn_enemy(_second_def(row, i))
		# 2. the partner's telegraph start fixes the second seal's dash tick
		var start_key := "pp_start_%d" % i
		if prev != "telegraph" and phase == "telegraph":
			st[start_key] = tick
		# 3. drive the second seal: hold it still, then start its own telegraph
		var released_key := "pp_released_%d" % i
		if st.has(released_key):
			continue
		var second: Variant = _find_second(rt, i)
		if second == null:
			continue   # the spawn has not landed yet: retry next tick
		if not st.has(start_key):
			_park(second)
			continue
		var due := int(st[start_key]) + TELEGRAPH_TICKS + DASH_DELAY_TICKS
		_release(second, api, maxi(due - tick, 1))
		st[released_key] = true


## The spawn request: a real seal row on its partner's spot, carrying the partner's own
## cfg plus the pairing marker (so the pack never grows).
static func _second_def(row: Dictionary, partner: int) -> Dictionary:
	var cfg: Dictionary = (row.get("cfg", {}) as Dictionary).duplicate()
	cfg[SECOND_MARK] = partner
	return {"id": SEAL_ID, "name": str(row.get("name", "seal")), "copy_index": 0,
			"copies": 1, "x": float(row["x"]), "y": float(row["y"]), "z": float(row["z"]),
			"cfg": cfg}


## The live second seal of `partner`, or null while the spawn has not landed.
static func _find_second(rt, partner: int) -> Variant:
	for e in rt.enemies:
		if str(e.get("id", "")) != SEAL_ID:
			continue
		var cfg: Dictionary = e.get("cfg", {})
		if int(cfg.get(SECOND_MARK, -1)) == partner:
			return e
	return null


## Hold the second seal still in the seal's own "recover" phase (the behavior only
## counts that phase down, so it never telegraphs or dashes while parked).
static func _park(second: Dictionary) -> void:
	second["phase"] = "recover"
	second["phase_left"] = HOLD_TICKS


## Start the second seal's OWN telegraph: the line is fixed now, from its own body
## centre through the player's centre and extended 20 u (D-069), and the behavior's own
## _telegraph_tick counts `ticks_left` down and dashes along it.
static func _release(second: Dictionary, api, ticks_left: int) -> void:
	var c0 := Vector3(float(second["x"]), float(second["y"]) + BODY_HEIGHT * 0.5,
			float(second["z"]))
	var p1 := c0 + Vector3(0.0, 0.0, 1.0)
	if api != null and api.has_method("nearest_player"):
		var near: Dictionary = api.nearest_player(c0)
		if not near.is_empty():
			p1 = Vector3(float(near["x"]), float(near["y"]) + PLAYER_CENTRE_U, float(near["z"]))
	var dir := p1 - c0
	if dir.length() < 1e-9:
		dir = Vector3(0.0, 0.0, 1.0)
	dir = dir.normalized()
	second["line_x0"] = c0.x
	second["line_y0"] = c0.y
	second["line_z0"] = c0.z
	second["dash_dx"] = dir.x
	second["dash_dy"] = dir.y
	second["dash_dz"] = dir.z
	second["phase"] = "telegraph"
	second["phase_left"] = maxi(ticks_left, 1)
	if api != null and api.has_method("telegraph"):
		var end := c0 + dir * DASH_LENGTH_U
		api.telegraph(KIND, {"shape": "circle", "cx": c0.x, "cz": c0.z, "r": 0.0,
				"dash_line": [c0.x, c0.y, c0.z, end.x, end.y, end.z]}, maxi(ticks_left, 1))
