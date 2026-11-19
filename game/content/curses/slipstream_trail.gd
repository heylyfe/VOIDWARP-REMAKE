extends RefCounted
#
# slipstream_trail.gd - script curse (DESIGN.md section 7.1 row "slipstream_trail").
# Rule sentence (spec, verbatim): "a dash leaves a slippery trail (friction ×0.4) for
# 3 s".
# Counter-play: "don't cross the line".
#
# Reading: the seal's dash is a fixed 3D line (D-069) and the row rides it 1/3 u per
# tick, so the tiles the trail covers are the tiles the row's feet pass over. Each tick
# a seal is in its own "dash" phase the curse writes the tile under the body into the
# world's slippery map (collision.gd's world["slippery"], the map the controller's
# friction_mult reads at x0.4) and stamps it to expire 180 ticks (3.0 s) later. The
# curse only ever erases keys IT wrote and only while they are not glitched (Wet Floor
# keeps the glitched tiles slippery from its own side), so the two curses never fight
# over a key.

const CURSE_ID := "slipstream_trail"

const SEAL_ID := "seal"           # the enemy the curse attaches to (content names content)
const DASH_PHASE := "dash"        # the seal's own dash phase (5.9)
const TRAIL_TICKS := 180          # 3.0 s (the rule sentence)
const FRICTION_MUL := 0.4         # the rule sentence's friction x0.4

## Per-level scratch: "st_trail" -> {tile key: tick it expires}.
const ST_KEY := "st_trail"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## The trail's life in ticks (the rule sentence's 3 s). Pure helper.
static func trail_ticks() -> int:
	return TRAIL_TICKS


## The friction multiplier a trail tile gets: 0.4 while held, 1.0 otherwise.
## Pure helper - the test target.
static func friction_mul(state: Dictionary) -> float:
	if held_stacks(state) >= 1:
		return FRICTION_MUL
	return 1.0


## The tile key under a body at (x, y, z): collision.gd's tile_key spelling
## "x,z,y_hu" with the feet height in half units. Pure helper - the test target.
static func tile_key_at(x: float, y: float, z: float) -> String:
	return "%d,%d,%d" % [int(floor(x)), int(floor(z)), int(round(y * 2.0))]


## on_tick: lay the trail under every dashing seal, then expire the old tiles.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	var world: Dictionary = rt.world
	if world.is_empty():
		return
	var st: Dictionary = state.get("curse_st", {})
	var trail: Dictionary = st.get(ST_KEY, {})
	var slip: Dictionary = world.get("slippery", {})
	var gl: Dictionary = world.get("glitched", {})
	var tick := int(state.get("tick", 0))
	# 1. a dashing seal leaves its tile slippery for 3 s
	for row in rt.enemies:
		if str(row.get("id", "")) != SEAL_ID:
			continue
		if str(row.get("phase", "")) != DASH_PHASE:
			continue
		var key := tile_key_at(float(row["x"]), float(row["y"]), float(row["z"]))
		trail[key] = tick + TRAIL_TICKS
		slip[key] = true
	# 2. expire the curse's own tiles (never a glitched one: Wet Floor owns those)
	for key in trail.keys():
		if tick < int(trail[key]):
			continue
		trail.erase(key)
		if not gl.has(key):
			slip.erase(key)
	world["slippery"] = slip
	st[ST_KEY] = trail
