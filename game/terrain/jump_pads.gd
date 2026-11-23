extends RefCounted
#
# game/terrain/jump_pads.gd - JUMP PAD placement (D-JUMPPAD-1, -6, -7; DESIGN.md section 3.4).
#
# NOT the generator's launch pads. voidgen.gd's W.pads / level "pads" / canonical "X" line are
# the ballistic LAUNCH pads that make spires reachable; they are frozen with the generator
# (GEN_VERSION 4, PARITY, GALLERY_PIN) and nothing here reads or writes them except to keep
# clear of them.
#
# A jump pad is placed AFTER voidgen.generate() has built the Level dict:
#   place_jump_pads(L, cfg) -> Array of [x, z, y]   (the ANCHOR = the block's centre tile)
#   attach(L)                -> stores that as L["jump_pads"] (loads data/jump_pads.json)
# It is a pure function of the Level dict (plus the data file): it draws from its own VoidRng
# stream seeded from the Level's own (seed, level, gen_version, attempt), so the level hash
# still determines the pads, and voidgen.to_text() - which never reads "jump_pads" - is
# byte-identical with or without them.
#
# Placement rule (the owner's words, cycle 7: "jump pads revamp (3x3 tiles, outside paths,
# 2 to 6 per level)"):
#   - a pad is a size_tiles x size_tiles BLOCK of tiles (3x3, D-JUMPPAD-6) at ONE height, and
#     the stored [x, z, y] is its centre tile; footprint() lists the 9 cells;
#   - OUTSIDE the paths: every tile of the block is a FLOOR tile (kind 0) of a platform piece.
#     A walkway tile (kind 1) IS the path and a walkway's middle line is the ROUTE, so a block
#     of floor tiles can never cover either - the 3-wide walkway has no room for a 3x3 block
#     that misses its centre lane, which is why the pads moved off the walkways entirely;
#   - never on: the hub piece (the beacon dais lives there), a ramp tile, a tile carrying a
#     prop, a gift slot, a tripmine slot, the beacon tile, a launch pad or its landing tile;
#   - headroom: no tile or prop in the block's own columns above it within headroom_hu (the
#     fling must not bonk a ceiling);
#   - ADJACENT TO THE PATHS, as a HARD rule (D-JUMPPAD-7): at least one tile EDGE-adjacent to
#     the block - the 4-neighbourhood of its 9 cells, never a diagonal - is a path tile within
#     path_step_hu vertically. A block with no such neighbour is not a candidate at all, so a
#     pad can never sit out on a platform away from every path;
#   - count from count_by_level (2 at level 1 up to 6 on big levels), pairwise XZ distance
#     >= min_spacing_tiles, taken in the pad stream's shuffled order.

const VoidRngScript := preload("res://terrain/void_rng.gd")
const VoidGenScript := preload("res://terrain/voidgen.gd")

const DATA_PATH := "res://data/jump_pads.json"
# The pad stream's tag: mixed onto the generator's own per-attempt base exactly as its ST_*
# streams are, with a value no ST_* constant uses ("JPAD").
const ST_JUMP_PADS := 0x4A504144
const CLEAR := 12                     # voidgen.CLEAR: two layers are distinct at >= 12 HU

# Mirrors data/jump_pads.json; the file wins for every key it carries.
const DEFAULTS := {
	"size_tiles": 3,
	"count_by_level": [
		{"from": 1, "count": 2}, {"from": 4, "count": 3}, {"from": 8, "count": 4},
		{"from": 14, "count": 5}, {"from": 20, "count": 6},
	],
	"min_spacing_tiles": 8,
	"path_step_hu": 4,
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


## The block's half extent in tiles: 1 for the 3x3 pad (D-JUMPPAD-6). Odd sizes only; an even
## size_tiles is rounded down to the odd block below it, so the anchor is always a real tile.
static func half_extent(cfg: Dictionary) -> int:
	var n := int(cfg.get("size_tiles", DEFAULTS["size_tiles"]))
	if n < 1:
		n = 1
	if n % 2 == 0:
		n -= 1
	return (n - 1) / 2


## The cells a pad anchored at (x, z, y) covers, as [[x, z, y], ...] in row-major order. The
## anchor is the centre tile; the sim triggers on any of them and the view draws the whole block.
static func footprint(x: int, z: int, y: int, half: int) -> Array:
	var out: Array = []
	for dx in range(-half, half + 1):
		for dz in range(-half, half + 1):
			out.append([x + dx, z + dz, y])
	return out


## The pad stream's seed: the generator's per-attempt base, mixed with ST_JUMP_PADS.
static func stream_seed(L: Dictionary) -> int:
	var M := VoidRngScript.M32
	var base: int = VoidRngScript.mix(VoidRngScript.mix(VoidRngScript.mix(
			int(L["seed"]) & M, int(L["level"])), int(L["gen_version"])), int(L["attempt"]))
	return VoidRngScript.mix(base, ST_JUMP_PADS)


# ---- geometry helpers over the packed Level dict ------------------------------------------

## Three lookups over the packed Level: `cell` (x, z, y) -> tile index, `col` (x, z) -> tile
## indices in that column (the headroom test), `pcol` (x, z) -> props in that column.
static func _index(L: Dictionary) -> Dictionary:
	var cell: Dictionary = {}
	var col: Dictionary = {}
	var tiles: Array = L["tiles"]
	for i in tiles.size():
		var t: Array = tiles[i]
		cell[Vector3i(int(t[0]), int(t[1]), int(t[2]))] = i
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
	return {"cell": cell, "col": col, "pcol": pcol}


static func _has_prop(ix: Dictionary, x: int, z: int, y: int) -> bool:
	for p in ix["pcol"].get(Vector2i(x, z), []):
		if int(p[2]) == y:
			return true
	return false


## Every legal pad BLOCK, as [x, z, y, piece_id] (the anchor is the block's centre tile),
## ascending by tile index (before count / spacing / ordering). A block is legal only when it
## is EDGE-ADJACENT to a path tile (D-JUMPPAD-7), so every entry here touches the path.
static func candidates(L: Dictionary, cfg: Dictionary) -> Array:
	var ix := _index(L)
	var tiles: Array = L["tiles"]
	var pieces: Array = L["pieces"]
	var half := half_extent(cfg)
	var headroom := int(cfg.get("headroom_hu", DEFAULTS["headroom_hu"]))
	var step_hu := int(cfg.get("path_step_hu", DEFAULTS["path_step_hu"]))
	# tiles a pad must keep clear of: gift / mine slots, the beacon, launch pads + landings.
	# "Never ON" (the owner's words): the block may sit right beside one, never over it.
	var banned: Dictionary = {}
	for g in L.get("gifts", []):
		banned[Vector2i(int(g["x"]), int(g["z"]))] = true
	for p in L.get("pads", []):
		banned[Vector2i(int(p[0]), int(p[1]))] = true
		banned[Vector2i(int(p[3]), int(p[4]))] = true
	var bx: Array = L.get("beacon", [0, 0, 1])
	banned[Vector2i(int(bx[0]), int(bx[1]))] = true
	# the path: every walkway tile, as Vector3i(x, z, y) - the same key order as _index's cell
	# map - for an O(1) adjacency lookup
	var walk: Dictionary = {}
	for i in tiles.size():
		if int(pieces[int(tiles[i][4])]["kind"]) == 1:
			walk[Vector3i(int(tiles[i][0]), int(tiles[i][1]), int(tiles[i][2]))] = true
	var out: Array = []
	for i in tiles.size():
		var t: Array = tiles[i]
		var x := int(t[0])
		var z := int(t[1])
		var y := int(t[2])
		if not _block_ok(L, ix, x, z, y, half, banned):
			continue
		if not _edge_adjacent(walk, x, z, y, half, step_hu):
			continue
		if not _headroom_ok(L, ix, x, z, y, headroom):
			continue
		out.append([x, z, y, int(t[4])])
	return out


## True when the whole block anchored at (x, z, y) is legal: every cell is a FLOOR tile of one
## non-hub platform piece at that height, no ramp tile, no prop, and none of the banned cells.
## A walkway tile (kind 1) is the PATH and a walkway's middle line is the ROUTE, so this one
## test is what keeps a pad outside the paths and off the route (D-JUMPPAD-6).
static func _block_ok(L: Dictionary, ix: Dictionary, x: int, z: int, y: int, half: int,
		banned: Dictionary) -> bool:
	var tiles: Array = L["tiles"]
	var pieces: Array = L["pieces"]
	var cell: Dictionary = ix["cell"]
	for dx in range(-half, half + 1):
		for dz in range(-half, half + 1):
			var key := Vector3i(x + dx, z + dz, y)
			if not cell.has(key):
				return false
			var tj: Array = tiles[int(cell[key])]
			var pc: Dictionary = pieces[int(tj[4])]
			if int(tj[3]) != 0:
				return false                       # a ramp tile
			if int(pc["kind"]) != 0:
				return false                       # a walkway tile IS the path: never
			if int(pc["role"]) == VoidGenScript.ROLE_HUB:
				return false                       # the hub / beacon dais
			if _has_prop(ix, x + dx, z + dz, y):
				return false
			if banned.has(Vector2i(x + dx, z + dz)):
				return false
	return true


## True when at least one tile on the RING OUTSIDE the block is a path tile: the 4-neighbourhood
## of the block's 9 cells MINUS the 9 cells themselves - 12 cells, three along each side, never a
## diagonal. This is the owner's "outside the paths (adjacent to them)" as a HARD rule
## (D-JUMPPAD-7).
##
## The ring, not the footprint. A walkway directly above or below a block tile is in the block's
## own column, not beside its edge, and must not satisfy adjacency (Terra review round 2): the
## first version walked the 4-neighbourhood of every block cell, so an interior cell's neighbour
## - another block cell - let a walkway one step up or down count as "adjacent".
##
## The height tolerance is not a loophole. voidgen steps a walkway 1-2 HU off the platform it
## runs beside at the junction, so a path tile is NEVER at the same height as the platform
## floor next to it: measured over 20 seeds x 8 levels, a same-height edge neighbour exists on
## 0 of 20 levels at 5 of the 8 sizes and at most 4 blocks anywhere (D-JUMPPAD-7).
## step_hu (4 HU) covers that junction step and the first stair row and stays well under
## CLEAR (12 HU), so a walkway on another storey can never satisfy it.
static func _edge_adjacent(walk: Dictionary, x: int, z: int, y: int, half: int,
		step_hu: int) -> bool:
	for dx in range(-half - 1, half + 2):
		for dz in range(-half - 1, half + 2):
			if absi(dx) <= half and absi(dz) <= half:
				continue                       # inside the block: not the ring
			if absi(dx) == half + 1 and absi(dz) == half + 1:
				continue                       # a corner: diagonal, not edge-adjacent
			var nx := x + dx
			var nz := z + dz
			for dy in range(-step_hu, step_hu + 1):
				if walk.has(Vector3i(nx, nz, y + dy)):
					return true
	return false


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


## THE placement function. Returns Array of [x, z, y] (the block's centre tile) in placement
## order (deterministic): the pad stream's shuffled candidate order, greedily filtered by
## min_spacing_tiles. Every candidate already touches the path (D-JUMPPAD-7).
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
	var out: Array = []
	for c in cand:
		if out.size() >= want:
			break
		var ok := true
		for p in out:
			var dx := float(int(c[0]) - int(p[0]))
			var dz := float(int(c[1]) - int(p[1]))
			if dx * dx + dz * dz < sp2:
				ok = false
				break
		if not ok:
			continue
		out.append([int(c[0]), int(c[1]), int(c[2])])
	# D-JUMPPAD-7: the greedy can strand a legal pair - it takes a block that is too close to
	# BOTH members of a pair that would have satisfied the spacing, and then reports a shortfall
	# that is not real (Terra review round 2: level 3 seed 11 placed 1 pad while two candidates
	# 4 tiles apart were legal). Below the owner's floor of 2, search for a two-pad arrangement
	# before accepting the shortfall. The candidate count is 6..17 per level, so the exhaustive
	# pair scan is at most ~136 distance checks and is deterministic (shuffled order, first pair).
	if out.size() < mini(want, 2):
		var pair := _first_pair(cand, sp2)
		if not pair.is_empty():
			out = pair
	return out


## The first two candidates, in the pad stream's shuffled order, that satisfy min_spacing_tiles -
## as [[x, z, y], [x, z, y]] - or [] when no pair exists at all. Exhaustive, so a shortfall it
## reports is a property of the level, not of the greedy.
static func _first_pair(cand: Array, sp2: float) -> Array:
	for i in cand.size():
		for j in range(i + 1, cand.size()):
			var dx := float(int(cand[i][0]) - int(cand[j][0]))
			var dz := float(int(cand[i][1]) - int(cand[j][1]))
			if dx * dx + dz * dz >= sp2:
				return [[int(cand[i][0]), int(cand[i][1]), int(cand[i][2])],
						[int(cand[j][0]), int(cand[j][1]), int(cand[j][2])]]
	return []
