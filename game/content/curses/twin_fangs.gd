extends RefCounted
#
# twin_fangs.gd - script curse (DESIGN.md section 7.1 row "twin_fangs").
# Rule sentence (spec, verbatim): "each strike marks two patches: yours and where you
# will be in 1.0 s".
# Counter-play: "change direction during the mark".
#
# Reading: gin's strike marks the 5x5 tile patch centred on the player's tile (5.12) and
# that patch becomes the lethal void zone 138 ticks later. The curse adds a SECOND patch
# at the mark's start: the 5x5 block centred on the tile the player will occupy in 1.0 s
# (their position plus velocity x 60 ticks), minus the beacon dais cell exactly as gin's
# own patch is (D-T041-3). The second patch is announced with gin's own "mark" telegraph
# for the strike's own 120 ticks, and it is lethal for the same void window as the first
# - the same tile-column rule, the same D-GIN code. Changing direction during the mark
# is the counter-play: the point is fixed at the mark's start and never re-aims.

const CURSE_ID := "twin_fangs"

const GIN_ID := "gin"                # the enemy the curse attaches to (content names content)
const MARK_PHASE := "mark"           # gin's own 120-tick telegraph phase (5.12)
const VOID_PHASE := "void"           # gin's own 600-tick lethal zone (5.12)
const PREDICT_TICKS := 60            # 1.0 s ahead (the rule sentence)
const PATCH_HALF := 2                # gin's own 5x5 patch: centre +/- 2 (5.12)
const TELEGRAPH_TICKS := 120         # gin's own 2.0 s mark (5.12)
const DEATH_CODE := "D-GIN"          # gin's own code (3.1 FINAL)
const KIND := "mark"                 # gin's own telegraph kind (5.12)

## Per-level scratch, keyed by the row index:
##   "tf_patch_<i>" {"cells": [[x, z], ...], "cx", "cz"}   "tf_prev_<i>" the last phase
const ST_KEY := "twin_fangs"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## Where the player will be in 1.0 s: their position plus velocity x 60 ticks (the rule
## sentence's "where you will be in 1.0 s"). Pure helper - the test target.
static func predict_point(player: Dictionary) -> Vector3:
	return Vector3(float(player.get("x", 0.0)) + float(player.get("vx", 0.0))
			* float(PREDICT_TICKS) / 60.0, float(player.get("y", 0.0)),
			float(player.get("z", 0.0)) + float(player.get("vz", 0.0))
			* float(PREDICT_TICKS) / 60.0)


## The 5x5 tile block centred on (cx, cz), minus the beacon dais cell - gin's own patch
## shape (5.12 / D-T041-3). Pure helper - the test target.
static func patch_cells(cx: int, cz: int, dais: Array) -> Array:
	var cells: Array = []
	for dx in range(-PATCH_HALF, PATCH_HALF + 1):
		for dz in range(-PATCH_HALF, PATCH_HALF + 1):
			var tx: int = cx + dx
			var tz: int = cz + dz
			if dais.size() >= 2 and int(dais[0]) == tx and int(dais[1]) == tz:
				continue   # never marks the beacon dais (D-T041-3)
			cells.append([tx, tz])
	return cells


## True when the tile under (x, z) is inside the patch - gin's own column rule (5.12).
## Pure helper - the test target.
static func tile_inside(cells: Array, x: float, z: float) -> bool:
	var cx := int(floor(x))
	var cz := int(floor(z))
	for cell in cells:
		if int(cell[0]) == cx and int(cell[1]) == cz:
			return true
	return false


## on_tick: mark the second patch at each strike's start, then make it lethal for the
## strike's own void window.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	var st: Dictionary = state.get("curse_st", {})
	for i in range(rt.enemies.size()):
		var row = rt.enemies[i]
		if str(row.get("id", "")) != GIN_ID:
			continue
		var phase := str(row.get("phase", ""))
		var prev_key := "tf_prev_%d" % i
		var patch_key := "tf_patch_%d" % i
		var prev := str(st.get(prev_key, ""))
		st[prev_key] = phase
		# 1. the strike's start: mark the second patch where the player will be
		if prev != MARK_PHASE and phase == MARK_PHASE:
			var patch: Variant = _mark(row, state, api)
			if patch != null:
				st[patch_key] = patch
		# 2. the void window: the second patch is lethal exactly like the first
		if phase == VOID_PHASE and st.has(patch_key):
			_void_kills(st[patch_key], state, api)
		# 3. the window closed: the patch is spent
		if prev == VOID_PHASE and phase != VOID_PHASE:
			st.erase(patch_key)


## Build and announce the second patch: the 5x5 block on the tile the player will hold
## in 1.0 s, minus the dais, announced with gin's own "mark" telegraph.
static func _mark(row: Dictionary, state: Dictionary, api) -> Variant:
	var near: Dictionary = {}
	if api != null and api.has_method("nearest_player"):
		near = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
	if near.is_empty():
		return null
	var p: Vector3 = predict_point(near)
	var cx := int(floor(p.x))
	var cz := int(floor(p.z))
	var dais: Array = []
	var rt = state.get("enemy_runtime")
	if rt != null and (rt.world as Dictionary).has("dais"):
		dais = rt.world["dais"]
	var patch := {"cells": patch_cells(cx, cz, dais), "cx": cx, "cz": cz}
	if api.has_method("telegraph"):
		api.telegraph(KIND, {"shape": "circle", "cx": float(cx) + 0.5,
				"cz": float(cz) + 0.5, "r": float(PATCH_HALF) + 0.5}, TELEGRAPH_TICKS)
	return patch


## The second patch's void window: anything whose tile is inside it dies, at any height
## (gin's own rule, 5.12).
static func _void_kills(patch: Dictionary, state: Dictionary, api) -> void:
	if api == null or not api.has_method("kill"):
		return
	var cells: Array = patch.get("cells", [])
	if cells.is_empty():
		return
	var players: Array = state.get("players", [])
	for i in range(players.size()):
		var p = players[i]
		if bool(p.get("dead")):
			continue
		if tile_inside(cells, _num(p, "x"), _num(p, "z")):
			api.kill(i, GIN_ID, DEATH_CODE)


## Read a numeric key off a controller (Object) or a dict row; 0.0 when absent.
static func _num(p, key: String) -> float:
	var v: Variant = p.get(key)
	return float(v) if v != null else 0.0
