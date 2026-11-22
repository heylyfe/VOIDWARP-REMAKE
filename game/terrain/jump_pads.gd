extends RefCounted
#
# game/terrain/jump_pads.gd - JUMP PAD placement (D-JUMPPAD-1; DESIGN.md section 3.4).
#
# NOT the generator's launch pads. voidgen.gd's W.pads / level "pads" / canonical "X" line are
# the ballistic LAUNCH pads that make spires reachable; they are frozen with the generator
# (GEN_VERSION 4, PARITY, GALLERY_PIN) and nothing here reads or writes them except to keep
# clear of them.
#
# A jump pad is placed AFTER voidgen.generate() has built the Level dict:
#   place_jump_pads(L, cfg) -> Array of [x, z, y]   (tile coords, y in HU = the tile top)
#   attach(L)                -> stores that as L["jump_pads"] (loads data/jump_pads.json)
# It is a pure function of the Level dict (plus the data file): it draws from its own VoidRng
# stream seeded from the Level's own (seed, level, gen_version, attempt), so the level hash
# still determines the pads, and voidgen.to_text() - which never reads "jump_pads" - is
# byte-identical with or without them.
#
# Placement rule (the owner's spec, item 1: "next to paths, never on them"):
#   - the ROUTE is a walkway's middle line: the generator's own centre column (o == 0), read
#     off the packed piece's bbox for a straight 3-wide walkway, plus any tile the GEN 4
#     centre_lane() test marks (all four neighbour columns walkable, and along one axis the cell
#     two away empty on both sides);
#   - a candidate is a FLOOR tile (kind 0) of a straight walkway (kind 1) one lane to the side
#     of that middle line, with the route tile right beside it (toward the middle, same piece,
#     same height) - the lane one tile beside the route. A walkway whose bbox cannot say which
#     axis is its width (square, or not a straight run) carries no pad;
#   - never on: the hub piece (the beacon dais lives there), a `stair` (jump stairs) or `ramp`
#     walkway, a ramp tile, a tile with a 4-neighbour on its piece over 1 HU above or below
#     (a ledge / jump-stair riser edge; a stepped climb's 1 HU tread is allowed), a tile
#     carrying a prop, a gift slot or tripmine slot or the 8 tiles around one, a launch pad or
#     its landing tile (or the 8 tiles around either);
#   - headroom: no tile or prop in the 3x3 columns above it within headroom_hu (the fling must
#     not bonk a ceiling);
#   - count from count_by_level, at most one pad per walkway piece, pairwise XZ distance >=
#     min_spacing_tiles; candidates are shuffled with the pad stream and taken greedily.

const VoidRngScript := preload("res://terrain/void_rng.gd")
const VoidGenScript := preload("res://terrain/voidgen.gd")

const DATA_PATH := "res://data/jump_pads.json"
# The pad stream's tag: mixed onto the generator's own per-attempt base exactly as its ST_*
# streams are, with a value no ST_* constant uses ("JPAD").
const ST_JUMP_PADS := 0x4A504144
const CLEAR := 12                     # voidgen.CLEAR: two layers are distinct at >= 12 HU
# TERRAIN_SPEC section 2 names the walkway arches: `step` = stepped climbs (1 HU risers the
# auto step-up walks), `stair` = jump stairs (2 HU risers), `ledge` = drop ledges, `flat`, `ramp`.
# "Never on stairs" bars the jump stairs and the ramps; a stepped climb's tread is legal as long
# as no neighbour on the piece is over STEP_HU off (no pad at a ledge or stair riser).
const NO_PAD_ARCHS := ["stair", "ramp"]
const STEP_HU := 1
const N4 := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

# Mirrors data/jump_pads.json; the file wins for every key it carries.
const DEFAULTS := {
	"count_by_level": [
		{"from": 1, "count": 1}, {"from": 3, "count": 2},
		{"from": 6, "count": 3}, {"from": 10, "count": 4},
	],
	"min_spacing_tiles": 12,
	"headroom_hu": 18,
	"launch_speed": 20.0,
	"rearm_s": 0.5,
}


static func load_config() -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return out
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return out
	for k in DEFAULTS.keys():
		if (parsed as Dictionary).has(k):
			out[k] = (parsed as Dictionary)[k]
	return out


## Pads wanted on this level number: the count_by_level row with the largest from <= level.
static func count_for_level(cfg: Dictionary, level: int) -> int:
	var best_from := -1
	var n := 0
	for row in cfg.get("count_by_level", []):
		var fr := int((row as Dictionary).get("from", 0))
		if fr <= level and fr > best_from:
			best_from = fr
			n = int((row as Dictionary).get("count", 0))
	return maxi(0, n)


## Places the pads and stores them on the Level dict as L["jump_pads"]. Returns them.
static func attach(L: Dictionary, cfg: Dictionary = {}) -> Array:
	var c: Dictionary = cfg if not cfg.is_empty() else load_config()
	var pads: Array = place_jump_pads(L, c) if not L.is_empty() else []
	L["jump_pads"] = pads
	return pads


## The pad stream's seed: the generator's per-attempt base, mixed with ST_JUMP_PADS.
static func stream_seed(L: Dictionary) -> int:
	var M := VoidRngScript.M32
	var base: int = VoidRngScript.mix(VoidRngScript.mix(VoidRngScript.mix(
			int(L["seed"]) & M, int(L["level"])), int(L["gen_version"])), int(L["attempt"]))
	return VoidRngScript.mix(base, ST_JUMP_PADS)


# ---- geometry helpers over the packed Level dict ------------------------------------------

static func _index(L: Dictionary) -> Dictionary:
	var col: Dictionary = {}
	var tiles: Array = L["tiles"]
	for i in tiles.size():
		var t: Array = tiles[i]
		var key := Vector2i(int(t[0]), int(t[1]))
		if not col.has(key):
			col[key] = []
		(col[key] as Array).append(i)
	var pcol: Dictionary = {}
	for p in L["props"]:
		var key2 := Vector2i(int(p[0]), int(p[1]))
		if not pcol.has(key2):
			pcol[key2] = []
		(pcol[key2] as Array).append(p)
	return {"col": col, "pcol": pcol}


static func _has_prop(ix: Dictionary, x: int, z: int, y: int) -> bool:
	for p in ix["pcol"].get(Vector2i(x, z), []):
		if int(p[2]) == y:
			return true
	return false


# voidgen.lane_cell over the packed Level.
static func _lane_cell(L: Dictionary, ix: Dictionary, x: int, z: int, y: int) -> bool:
	for j in ix["col"].get(Vector2i(x, z), []):
		var tj: Array = L["tiles"][j]
		if absi(int(tj[2]) - y) < CLEAR and not _has_prop(ix, x, z, int(tj[2])):
			return true
	return false


## True when tile i is on a walkway's centre lane - the ROUTE (voidgen.centre_lane, GEN 4).
static func on_route(L: Dictionary, ix: Dictionary, i: int) -> bool:
	var t: Array = L["tiles"][i]
	var x := int(t[0])
	var z := int(t[1])
	var y := int(t[2])
	for d in N4:
		if not _lane_cell(L, ix, x + d.x, z + d.y, y):
			return false
	for a in [Vector2i(1, 0), Vector2i(0, 1)]:
		if not _lane_cell(L, ix, x + 2 * a.x, z + 2 * a.y, y) \
				and not _lane_cell(L, ix, x - 2 * a.x, z - 2 * a.y, y):
			return true
	return false


static func _tile_at(L: Dictionary, ix: Dictionary, x: int, z: int, y: int) -> int:
	for j in ix["col"].get(Vector2i(x, z), []):
		if int(L["tiles"][j][2]) == y:
			return j
	return -1


## Every tile index a pad may legally sit on, ascending (before count / spacing).
static func candidates(L: Dictionary, cfg: Dictionary) -> Array:
	var ix := _index(L)
	var tiles: Array = L["tiles"]
	var pieces: Array = L["pieces"]
	var headroom := int(cfg.get("headroom_hu", DEFAULTS["headroom_hu"]))
	# cells a pad must keep clear of: gift / mine slots and launch pads + landings, each with
	# its 8 neighbours (XZ only, every layer - cheap and conservative)
	var banned: Dictionary = {}
	var ban := func(x: int, z: int) -> void:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				banned[Vector2i(x + dx, z + dz)] = true
	for g in L.get("gifts", []):
		ban.call(int(g["x"]), int(g["z"]))
	for p in L.get("pads", []):
		ban.call(int(p[0]), int(p[1]))
		ban.call(int(p[3]), int(p[4]))
	var bx: Array = L.get("beacon", [0, 0, 1])
	ban.call(int(bx[0]), int(bx[1]))
	var route_cache: Dictionary = {}
	var out: Array = []
	for i in tiles.size():
		var t: Array = tiles[i]
		var x := int(t[0])
		var z := int(t[1])
		var y := int(t[2])
		var pid := int(t[4])
		if int(t[3]) != 0:
			continue                                     # a ramp tile
		var pc: Dictionary = pieces[pid]
		if int(pc["role"]) == VoidGenScript.ROLE_HUB or int(pc["kind"]) != 1:
			continue                                     # hub / beacon, or not a walkway
		if NO_PAD_ARCHS.has(str(pc["arch"])):
			continue                                     # jump stairs, ramps
		if banned.has(Vector2i(x, z)) or _has_prop(ix, x, z, y):
			continue
		var ax := lateral_axis(pc)
		if ax < 0:
			continue                                     # not a straight walkway: no lane read
		if _route(L, ix, i, route_cache):
			continue                                     # ON the path: never
		# the lane one tile beside the middle line, and the route tile right next to it
		# (toward the middle, same height) must exist on the same walkway
		var bb: Array = pc["bbox"]
		var mid2: int = int(bb[ax]) + int(bb[ax + 2])
		var lat: int = x if ax == 0 else z
		if absi(lat * 2 - mid2) != 2:
			continue
		var step_in: int = -1 if lat * 2 > mid2 else 1
		var rx: int = x + (step_in if ax == 0 else 0)
		var rz: int = z + (step_in if ax == 1 else 0)
		var r := _tile_at(L, ix, rx, rz, y)
		if r < 0 or int(tiles[r][4]) != pid or not _route(L, ix, r, route_cache):
			continue
		var flat := true
		for d in N4:
			for jj in ix["col"].get(Vector2i(x + d.x, z + d.y), []):
				var tj: Array = tiles[jj]
				if int(tj[4]) == pid and absi(int(tj[2]) - y) < CLEAR 						and (absi(int(tj[2]) - y) > STEP_HU or int(tj[3]) != 0):
					flat = false
		if not flat:
			continue
		if not _headroom_ok(L, ix, x, z, y, headroom):
			continue
		out.append(i)
	return out


## A straight walkway's lateral axis read off its packed bbox: 0 = the lanes run along z (the
## width is on x), 1 = the width is on z; -1 when the bbox cannot say (both extents or neither
## equal the width - a square walkway, or a piece that is not a straight run).
static func lateral_axis(pc: Dictionary) -> int:
	if int(pc["kind"]) != 1:
		return -1
	var bb: Array = pc["bbox"]
	var ex: int = int(bb[2]) - int(bb[0]) + 1
	var ez: int = int(bb[3]) - int(bb[1]) + 1
	var w: int = int(pc["w"])
	if ex == w and ez != w:
		return 0
	if ez == w and ex != w:
		return 1
	return -1


## The ROUTE: a walkway tile on the generator's GEN 4 centre lane, or on the middle line of a
## straight walkway (the generator's own centre column, o == 0 - the GEN 4 test misses it at a
## row whose neighbour is a gap or a prop, and that tile is still walked).
static func _route(L: Dictionary, ix: Dictionary, i: int, cache: Dictionary) -> bool:
	if not cache.has(i):
		var t: Array = L["tiles"][i]
		var pc: Dictionary = L["pieces"][int(t[4])]
		var on := false
		if int(pc["kind"]) == 1:
			var ax := lateral_axis(pc)
			if ax >= 0:
				var bb: Array = pc["bbox"]
				on = int(t[ax]) * 2 == int(bb[ax]) + int(bb[ax + 2])
			on = on or on_route(L, ix, i)
		cache[i] = on
	return bool(cache[i])


static func _headroom_ok(L: Dictionary, ix: Dictionary, x: int, z: int, y: int, hu: int) -> bool:
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(x + dx, z + dz)
			for j in ix["col"].get(key, []):
				var ty := int(L["tiles"][j][2])
				if ty > y and ty <= y + hu:
					return false
	# a prop stands on a tile, so a prop above the pad in a neighbour column already failed the
	# tile test; in the pad's own column, any prop whose span reaches above the pad top blocks
	for p in ix["pcol"].get(Vector2i(x, z), []):
		var py := int(p[2])
		if py + int(p[3]) > y and py <= y + hu:
			return false
	return true


## THE placement function. Returns Array of [x, z, y] in placement order (deterministic).
static func place_jump_pads(L: Dictionary, cfg: Dictionary) -> Array:
	var want := count_for_level(cfg, int(L.get("level", 1)))
	if want <= 0:
		return []
	var cand := candidates(L, cfg)
	if cand.is_empty():
		return []
	var rng = VoidRngScript.new(stream_seed(L))
	rng.shuffle(cand)
	var spacing := float(cfg.get("min_spacing_tiles", DEFAULTS["min_spacing_tiles"]))
	var sp2 := spacing * spacing
	var used_piece: Dictionary = {}
	var out: Array = []
	for i in cand:
		if out.size() >= want:
			break
		var t: Array = L["tiles"][i]
		var pid := int(t[4])
		if used_piece.has(pid):
			continue
		var ok := true
		for p in out:
			var dx := float(int(t[0]) - int(p[0]))
			var dz := float(int(t[1]) - int(p[1]))
			if dx * dx + dz * dz < sp2:
				ok = false
				break
		if not ok:
			continue
		used_piece[pid] = true
		out.append([int(t[0]), int(t[1]), int(t[2])])
	return out
