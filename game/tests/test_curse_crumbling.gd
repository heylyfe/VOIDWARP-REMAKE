extends RefCounted
#
# CURSE-CRUMBLING test (headless, W10-C): "1-wide walkway tiles fall 1.2 s after being
# stepped on and return after 5 s" (content/curses/crumbling.json).
#
# The module (content/curses/crumbling.gd) owns the schedule only. This file proves the
# three pieces the shipped game was missing, never by calling the module directly:
#   1. the step_on caller   - sim/controller.gd tile_step_hook, fired when the feet settle
#                             on a new tile; app/world.gd arms 1-wide tiles through it;
#   2. the tile applicator  - app/world.gd turns tile_fell / tile_returned into
#                             w["removed"] writes (collision.gd reads that set);
#   3. the edge predicate   - app/world.gd edge_lane_keys (void on one side, floor on the
#                             opposite side, along one axis).
#
# DECISION (lead, W10, DECISIONS.md): "1-wide walkway tiles" reads as THE OUTER LANE OF A
# WALKWAY. GEN_VERSION 4 makes every walkway WALK_W = 3 cells wide, so the literal reading
# matched zero tiles in every shipped level (the W10-C finding) and the curse could never
# fire. _shipped_levels_have_edges asserts the edge set is now non-empty on real levels
# and that every member is an edge; _real_edge_falls drives a real level's edge lane.
# The cut-bridge cases still CARVE a 1-wide bridge into a real built level (w["cols"]
# edited after build(), then tile_step_rescan()) - a labelled fixture - proving the
# literal 1-wide strip still qualifies and pinning the exact 72 / 300 tick schedule.
#
# Every mechanism case runs twice: curses {} (the negative control - the same carved
# bridge, the same feet, the tile never falls) and the curse held.

const WorldScript := preload("res://app/world.gd")
const CollisionScript := preload("res://sim/collision.gd")

const CURSE := "crumbling"
const SEED := 1
const LEVEL := 10          # the curse's min_level
const DT := 1.0 / 60.0
const FALL_TICKS := 72     # 1.2 s (the rule sentence)
const RETURN_TICKS := 300  # 5.0 s (the rule sentence)
const CARVE_HALF := 2      # the carved bridge spans x-2 .. x+2 (5 tiles)

# Shipped levels from the curse's min_level up, through world.build().
const SWEEP_WORLD := [[10, 1], [15, 7], [20, 42], [30, 12345], [10, 60717]]


func run() -> Array[String]:
	var f: Array[String] = []
	_predicate_shapes(f)
	_shipped_levels_have_edges(f)
	_mechanism(f)
	_wide_tile_never_falls(f)
	_real_edge_falls(f)
	return f


# ---- helpers -------------------------------------------------------------------------------

func _check(f: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		f.append(msg)


func _build(curses: Dictionary, level: int = LEVEL, seed_value: int = SEED):
	var world = WorldScript.new()
	var ledger := {
		"class": "dasher", "votes": {}, "curses": curses, "stacks": {},
		"purse": 0, "tithes": 0, "hunger": 0, "last_vote": "",
	}
	if not world.build(seed_value, level, ledger):
		world.free()
		return null
	return world


func _drop(world) -> void:
	if world != null:
		world.teardown()
		world.free()


## A hand-made world dict from [x, z, y] flat tiles (and [x, z] prop cells).
func _hand_world(cells: Array, prop_cells: Array = []) -> Dictionary:
	var tiles: Array = []
	for c in cells:
		tiles.append([c[0], c[1], c[2], 0, 0])
	var props: Array = []
	for p in prop_cells:
		props.append([p[0], p[1], 0, 4, 0, 0])
	return CollisionScript.make_world(tiles, props, [])


# ---- 3. the predicate on hand-made shapes ---------------------------------------------------

func _predicate_shapes(f: Array[String]) -> void:
	# A 1 x 5 strip along x at y 0: the literal 1-wide reading - every tile qualifies.
	var strip: Array = []
	for x in range(0, 5):
		strip.append([x, 0, 0])
	var k1: Dictionary = WorldScript.edge_lane_keys(_hand_world(strip))
	_check(f, k1.size() == 5, "predicate: a 1x5 strip must give 5 tiles, got %d" % k1.size())
	_check(f, k1.has("2,0,0"), "predicate: the strip's middle tile 2,0,0 must qualify")
	# A 3 x 5 walkway (the generator's WALK_W): both outer lanes (10) plus the centre
	# lane's two open ends (2) qualify; the 3 centre-lane interior tiles do not.
	var wide: Array = []
	for x in range(0, 5):
		for z in range(-1, 2):
			wide.append([x, z, 0])
	var k3: Dictionary = WorldScript.edge_lane_keys(_hand_world(wide))
	_check(f, k3.size() == 12, "predicate: a 3x5 walkway must give 12 edge tiles, got %d" % k3.size())
	for x in range(0, 5):
		_check(f, k3.has("%d,1,0" % x) and k3.has("%d,-1,0" % x),
				"predicate: the outer lanes at x %d must qualify" % x)
	for x in range(1, 4):
		_check(f, not k3.has("%d,0,0" % x), "predicate: centre-lane tile %d,0,0 must not qualify" % x)
	# A 3-wide 2 HU staircase along x reads like the flat walkway (treads are floor).
	var stairs: Array = []
	for x in range(0, 5):
		for z in range(-1, 2):
			stairs.append([x, z, x * 2])
	var ks: Dictionary = WorldScript.edge_lane_keys(_hand_world(stairs))
	_check(f, ks.size() == 12, "predicate: a 3-wide 2 HU staircase must give 12 edge tiles, got %d" % ks.size())
	_check(f, not ks.has("2,0,4"), "predicate: the staircase's centre tread 2,0,4 must not qualify")
	# A lone pad (void on all four sides) is a stepping stone, not a walkway edge.
	var kp: Dictionary = WorldScript.edge_lane_keys(_hand_world([[0, 0, 0]]))
	_check(f, kp.is_empty(), "predicate: an isolated pad must not qualify")
	# A 5 x 5 slab: its 16 rim tiles are edges, its 3 x 3 interior is not.
	var slab: Array = []
	for x in range(0, 5):
		for z in range(0, 5):
			slab.append([x, z, 0])
	var kb: Dictionary = WorldScript.edge_lane_keys(_hand_world(slab))
	_check(f, kb.size() == 16, "predicate: a 5x5 slab must give its 16 rim tiles, got %d" % kb.size())
	_check(f, not kb.has("2,2,0"), "predicate: the slab's centre must not qualify")
	# A strip with a prop wall on z+1 and void on z-1: void one side, floor the other -
	# every tile is an edge (the wall side is ground, the open side is the drop).
	var walled: Dictionary = WorldScript.edge_lane_keys(
			_hand_world(strip, [[0, 1], [1, 1], [2, 1], [3, 1], [4, 1]]))
	_check(f, walled.size() == 5, "predicate: a strip against a prop wall must give 5 edges, got %d" % walled.size())
	# A strip between two prop walls has floor on every lateral side mid-strip: not an edge.
	var boxed: Dictionary = WorldScript.edge_lane_keys(_hand_world(strip,
			[[0, 1], [1, 1], [2, 1], [3, 1], [4, 1], [0, -1], [1, -1], [2, -1], [3, -1], [4, -1]]))
	_check(f, not boxed.has("2,0,0"), "predicate: a strip between two prop walls must not qualify mid-strip")


## The edge rule read independently of world.gd: along one axis one neighbour is void and
## the opposite is floor, or (the literal strip) both lateral neighbours void with floor
## along the other axis. Both reduce to: not under a prop, at least one floor neighbour,
## at least one void neighbour, and not void on all four sides.
func _is_edge(wd: Dictionary, key: String) -> bool:
	var p: PackedStringArray = key.split(",")
	var x := int(p[0])
	var z := int(p[1])
	var y := int(p[2])
	var cols: Dictionary = wd["cols"]
	var props: Dictionary = wd["prop_cols"]
	var px: bool = WorldScript._floor_beside(cols, props, x + 1, z, y)
	var nx: bool = WorldScript._floor_beside(cols, props, x - 1, z, y)
	var pz: bool = WorldScript._floor_beside(cols, props, x, z + 1, y)
	var nz: bool = WorldScript._floor_beside(cols, props, x, z - 1, y)
	var any_floor := px or nx or pz or nz
	var any_void := not (px and nx and pz and nz)
	return any_floor and any_void and not props.has("%d,%d" % [x, z])


# ---- shipped levels: the edge set is live (replaces the W10-C empty-set finding) -------------

func _shipped_levels_have_edges(f: Array[String]) -> void:
	for pair in SWEEP_WORLD:
		var lvl := int(pair[0])
		var sd := int(pair[1])
		var world = _build({CURSE: 1}, lvl, sd)
		if world == null:
			f.append("shipped: world.build(%d, %d) failed" % [sd, lvl])
			continue
		_check(f, world._tile_step_mods.size() == 1,
				"shipped L%d s%d: the held curse's step_on module must be subscribed, got %d"
				% [lvl, sd, world._tile_step_mods.size()])
		_check(f, world.ctl.tile_step_hook.is_valid(),
				"shipped L%d s%d: the controller's tile-step hook must be set" % [lvl, sd])
		var keys: Dictionary = world._tile_step_keys
		_check(f, not keys.is_empty(),
				"shipped L%d s%d: the level has no walkway-edge tile - the curse cannot fire" % [lvl, sd])
		var bad := 0
		for k in keys.keys():
			if not _is_edge(world.w, str(k)):
				bad += 1
		_check(f, bad == 0, "shipped L%d s%d: %d qualifying tiles are not edges" % [lvl, sd, bad])
		_drop(world)


# ---- the fixture: a carved 1-wide bridge in a real built level -------------------------------

## A flat tile in the middle of a straight walkway running along x: the 7 tiles x-3..x+3
## on row z and both side rows z +/- 1 are all flat at the same height, no prop on any.
## Returns [x, z, y_hu] or [] when the level has none.
func _pick_bridge(world) -> Array:
	var wd: Dictionary = world.w
	var cols: Dictionary = wd["cols"]
	var props: Dictionary = wd["prop_cols"]
	var dais: Array = wd["dais"]
	for t in world.lv["tiles"]:
		if int(t[3]) != 0:
			continue
		var x := int(t[0])
		var z := int(t[1])
		var y := int(t[2])
		if absi(x - int(dais[0])) + absi(z - int(dais[1])) < 8:
			continue
		var ok := true
		for dx in range(-3, 4):
			for dz in range(-1, 2):
				var k := "%d,%d" % [x + dx, z + dz]
				if props.has(k) or not _flat_at(cols.get(k, []), y):
					ok = false
					break
			if not ok:
				break
		if ok:
			return [x, z, y]
	return []


## The column holds exactly one tile, flat, at height y.
func _flat_at(col: Array, y: int) -> bool:
	return col.size() == 1 and int(col[0]["y"]) == y and int(col[0]["kind"]) == 0


## Cut the side rows z +/- 1 out of x-CARVE_HALF .. x+CARVE_HALF: row z becomes a 1-wide
## bridge of 5 tiles. Then rescan so the world's 1-wide set sees the carved geometry.
func _carve(world, t: Array) -> void:
	for dx in range(-CARVE_HALF, CARVE_HALF + 1):
		world.w["cols"].erase("%d,%d" % [int(t[0]) + dx, int(t[1]) + 1])
		world.w["cols"].erase("%d,%d" % [int(t[0]) + dx, int(t[1]) - 1])
	world.tile_step_rescan()


## Drop the player onto tile t from 0.25 u above (no input: the feet settle and stay), and
## step `limit` ticks, recording LevelState ticks:
##   arm   the tick of the controller step on which the feet settled on t (-1 = never)
##   fell  the tick after which t was first missing from collision (-1 = never)
##   ret   the tick after which t was first back in collision after falling (-1 = never)
##   min_y the lowest feet height seen after the fall (INF = no fall)
##   stood true when the feet never left the tile top before the fall
func _drive(world, t: Array, limit: int, reset_key: bool = true) -> Dictionary:
	var x := int(t[0])
	var z := int(t[1])
	var y := int(t[2])
	var top := CollisionScript.tile_top(y)
	var key := CollisionScript.tile_key(x, z, y)
	var ctl = world.ctl
	ctl.x = float(x) + 0.5
	ctl.z = float(z) + 0.5
	ctl.y = top + 0.25
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0
	ctl.grounded = false
	if reset_key:
		ctl.cur_key = ""     # a teleport into the air: the last-stood tile is forgotten
	ctl.invuln = 1000.0      # no mine / enemy may end the run mid-measurement
	ctl.sync_body()
	var out := {"arm": -1, "fell": -1, "ret": -1, "min_y": INF, "stood": true}
	for _i in limit:
		var before := int(world.lstate.tick)
		world.step(DT)
		if bool(world.ctl.dead):
			out["dead"] = true
			break
		if int(out["arm"]) < 0 and bool(ctl.grounded) and str(ctl.cur_key) == key:
			out["arm"] = before
		var alive := CollisionScript.tile_alive(world.w, x, z, y)
		var now := int(world.lstate.tick)
		if int(out["fell"]) < 0:
			if not alive:
				out["fell"] = now
			elif int(out["arm"]) >= 0 and float(ctl.y) < top - 0.01:
				out["stood"] = false
		else:
			out["min_y"] = minf(float(out["min_y"]), float(ctl.y))
			if alive and int(out["ret"]) < 0:
				out["ret"] = now
				break
	return out


# ---- 1 + 2: the step_on caller and the tile applicator, through world.step() ------------------

func _mechanism(f: Array[String]) -> void:
	var limit := FALL_TICKS + RETURN_TICKS + 60
	for held in [false, true]:
		var tag := "held" if held else "control"
		var world = _build({CURSE: 1} if held else {})
		if world == null:
			f.append("mechanism %s: world.build failed" % tag)
			continue
		var t := _pick_bridge(world)
		if t.is_empty():
			f.append("mechanism %s: no straight walkway to carve in L%d s%d" % [tag, LEVEL, SEED])
			_drop(world)
			continue
		_carve(world, t)
		var key := CollisionScript.tile_key(int(t[0]), int(t[1]), int(t[2]))
		# The predicate sees the carved bridge in both builds (it is pure geometry).
		_check(f, (WorldScript.edge_lane_keys(world.w) as Dictionary).has(key),
				"mechanism %s: the carved 1-wide tile %s must qualify" % [tag, key])
		var top := CollisionScript.tile_top(int(t[2]))
		var r := _drive(world, t, limit)
		_check(f, not r.has("dead"), "mechanism %s: the player died during the measurement" % tag)
		_check(f, int(r["arm"]) >= 0, "mechanism %s: the feet never settled on %s" % [tag, key])
		if not held:
			# Negative control: the same bridge, the same feet, 432 ticks: never falls.
			_check(f, int(r["fell"]) < 0,
					"mechanism control: the tile fell at tick %d without the curse" % int(r["fell"]))
			_check(f, bool(r["stood"]),
					"mechanism control: the feet left the tile top without the curse")
			_check(f, float(world.ctl.y) >= top - 0.01 and bool(world.ctl.grounded),
					"mechanism control: the player must still stand on the tile (y %.3f, top %.3f)"
					% [float(world.ctl.y), top])
			_drop(world)
			continue
		var arm := int(r["arm"])
		var fell := int(r["fell"])
		var ret := int(r["ret"])
		_check(f, fell >= 0, "mechanism held: the 1-wide tile never fell")
		_check(f, fell - arm == FALL_TICKS,
				"mechanism held: the tile must fall %d ticks after the step, fell %d after (arm %d, fell %d)"
				% [FALL_TICKS, fell - arm, arm, fell])
		_check(f, bool(r["stood"]), "mechanism held: the feet left the tile before it fell")
		# The body falls through the hole (support_at finds nothing under it).
		_check(f, float(r["min_y"]) < top - 1.0,
				"mechanism held: the body must fall through the fallen tile (lowest y %.3f, top %.3f)"
				% [float(r["min_y"]), top])
		_check(f, ret >= 0, "mechanism held: the fallen tile never returned")
		_check(f, ret - fell == RETURN_TICKS,
				"mechanism held: the tile must return %d ticks after the fall, returned %d after"
				% [RETURN_TICKS, ret - fell])
		# After the return the tile carries a body again: drop onto it and stand.
		if ret >= 0:
			var probe = CollisionScript.support_at(world.w, float(t[0]) + 0.5, float(t[1]) + 0.5,
					top + 0.1, 0.5)
			_check(f, absf(float(probe) - top) < 1e-6,
					"mechanism held: support_at must find the returned tile top %.3f, got %s"
					% [top, str(probe)])
		_drop(world)


## Held curse, the SAME tile before the carve (a 3-wide walkway's CENTRE lane): standing on it
## for the full fall + return window never drops it - the predicate gates the rule.
func _wide_tile_never_falls(f: Array[String]) -> void:
	var world = _build({CURSE: 1})
	if world == null:
		f.append("wide: world.build failed")
		return
	var t := _pick_bridge(world)
	if t.is_empty():
		f.append("wide: no walkway tile found")
		_drop(world)
		return
	var key := CollisionScript.tile_key(int(t[0]), int(t[1]), int(t[2]))
	_check(f, not world._tile_step_keys.has(key), "wide: the centre-lane tile %s must not qualify" % key)
	var r := _drive(world, t, FALL_TICKS + RETURN_TICKS + 30)
	_check(f, int(r["arm"]) >= 0, "wide: the feet never settled on %s" % key)
	_check(f, int(r["fell"]) < 0, "wide: a 3-wide walkway tile fell at tick %d" % int(r["fell"]))
	_check(f, bool(r["stood"]), "wide: the feet left the 3-wide tile")
	_drop(world)


## Held curse, SHIPPED geometry (no carve): a flat walkway-edge tile of the real level -
## void on one side, the walkway on the other - falls FALL_TICKS after the feet settle,
## the body drops through, and it returns RETURN_TICKS later.
func _real_edge_falls(f: Array[String]) -> void:
	var world = _build({CURSE: 1})
	if world == null:
		f.append("real edge: world.build failed")
		return
	var t := _pick_edge(world)
	if t.is_empty():
		f.append("real edge: no flat walkway-edge tile in L%d s%d" % [LEVEL, SEED])
		_drop(world)
		return
	var key := CollisionScript.tile_key(int(t[0]), int(t[1]), int(t[2]))
	_check(f, _is_edge(world.w, key), "real edge: %s must be an edge tile" % key)
	var top := CollisionScript.tile_top(int(t[2]))
	var r := _drive(world, t, FALL_TICKS + RETURN_TICKS + 60)
	_check(f, not r.has("dead"), "real edge: the player died during the measurement")
	_check(f, int(r["arm"]) >= 0, "real edge: the feet never settled on %s" % key)
	_check(f, int(r["fell"]) >= 0, "real edge: the shipped edge tile %s never fell" % key)
	_check(f, int(r["fell"]) - int(r["arm"]) == FALL_TICKS,
			"real edge: must fall %d ticks after the step, fell %d after"
			% [FALL_TICKS, int(r["fell"]) - int(r["arm"])])
	_check(f, bool(r["stood"]), "real edge: the feet left the tile before it fell")
	_check(f, float(r["min_y"]) < top - 1.0,
			"real edge: the body must fall through (lowest y %.3f, top %.3f)" % [float(r["min_y"]), top])
	_check(f, int(r["ret"]) - int(r["fell"]) == RETURN_TICKS,
			"real edge: must return %d ticks after the fall, returned %d after"
			% [RETURN_TICKS, int(r["ret"]) - int(r["fell"])])
	_drop(world)


## A flat, single-tile-column walkway-edge tile of the built level, away from the dais,
## whose inner neighbour along the void axis is flat floor at the same height (an outer
## lane with the walkway beside it). Returns [x, z, y_hu] or [].
func _pick_edge(world) -> Array:
	var wd: Dictionary = world.w
	var cols: Dictionary = wd["cols"]
	var props: Dictionary = wd["prop_cols"]
	var dais: Array = wd["dais"]
	var keys: Dictionary = world._tile_step_keys
	for t in world.lv["tiles"]:
		if int(t[3]) != 0:
			continue
		var x := int(t[0])
		var z := int(t[1])
		var y := int(t[2])
		if not keys.has(CollisionScript.tile_key(x, z, y)):
			continue
		if not _flat_at(cols.get("%d,%d" % [x, z], []), y):
			continue
		if absi(x - int(dais[0])) + absi(z - int(dais[1])) < 8:
			continue
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var ink := "%d,%d" % [x + int(d[0]), z + int(d[1])]
			var outk := "%d,%d" % [x - int(d[0]), z - int(d[1])]
			if props.has(ink) or props.has(outk):
				continue
			if _flat_at(cols.get(ink, []), y) and not cols.has(outk):
				return [x, z, y]
	return []
