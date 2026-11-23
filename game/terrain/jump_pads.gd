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
#   - count from count_by_level (2 at level 1 up to 6 on big levels), at most one pad per
#     platform piece, pairwise XZ distance >= min_spacing_tiles;
#   - NEAREST THE PATH FIRST (D-JUMPPAD-7): candidates carry their XZ gap to the nearest
#     walkway tile within path_step_hu vertically, and are taken nearest first (ties broken by
#     the pad stream), so a pad is as close to the path as the level allows. The gap is a
#     preference, not a filter: a hard "within N tiles" cap leaves some levels with no legal
#     spot at all (measured, D-JUMPPAD-7), and the owner's floor is 2 pads per level.

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


## Every legal pad BLOCK, as [x, z, y, gap, piece_id] (the anchor is the block's centre tile),
## ascending by tile index (before count / spacing / ordering). `gap` is the XZ distance from
## the block's footprint to the nearest walkway tile within path_step_hu vertically: 0 = the
## path runs right against the block, 1 = one empty cell between, and so on (D-JUMPPAD-7).
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
	# the path: every walkway tile, as Vector3i(x, y, z)
	var walk: Array = []
	for i in tiles.size():
		if int(pieces[int(tiles[i][4])]["kind"]) == 1:
			walk.append(Vector3i(int(tiles[i][0]), int(tiles[i][2]), int(tiles[i][1])))
	var out: Array = []
	for i in tiles.size():
		var t: Array = tiles[i]
		var x := int(t[0])
		var z := int(t[1])
		var y := int(t[2])
		if not _block_ok(L, ix, x, z, y, half, banned):
			continue
		if not _headroom_ok(L, ix, x, z, y, headroom):
			continue
		out.append([x, z, y, _path_gap(walk, x, z, y, half, step_hu), int(t[4])])
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


## The XZ gap from the block's footprint to the nearest walkway tile within step_hu vertically:
## 0 = the path runs right against the block, 1 = one empty cell between, ... 99 = no walkway
## within step_hu of this height (a spire reached only by a launch pad).
static func _path_gap(walk: Array, x: int, z: int, y: int, half: int, step_hu: int) -> int:
	var best := 99
	for w in walk:
		if absi(int(w.y) - y) > step_hu:
			continue
		var d: int = maxi(absi(int(w.x) - x), absi(int(w.z) - z)) - half - 1
		if d < best:
			best = d
			if best <= 0:
				return 0
	return best


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
## order (deterministic): nearest the path first, ties broken by the pad stream.
static func place_jump_pads(L: Dictionary, cfg: Dictionary) -> Array:
	var want := count_for_level(cfg, int(L.get("level", 1)))
	if want <= 0:
		return []
	var cand := candidates(L, cfg)
	if cand.is_empty():
		return []
	var rng = VoidRngScript.new(stream_seed(L))
	rng.shuffle(cand)
	# nearest the path first; the shuffled index breaks ties, so the order is total
	var order: Array = []
	for i in cand.size():
		order.append([int(cand[i][3]), i])
	order.sort_custom(func(a, b) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var spacing := float(cfg.get("min_spacing_tiles", DEFAULTS["min_spacing_tiles"]))
	var sp2 := spacing * spacing
	var used_piece: Dictionary = {}
	var out: Array = []
	for o in order:
		if out.size() >= want:
			break
		var c: Array = cand[int(o[1])]
		var pid := int(c[4])
		if used_piece.has(pid):
			continue
		var ok := true
		for p in out:
			var dx := float(int(c[0]) - int(p[0]))
			var dz := float(int(c[1]) - int(p[1]))
			if dx * dx + dz * dz < sp2:
				ok = false
				break
		if not ok:
			continue
		used_piece[pid] = true
		out.append([int(c[0]), int(c[1]), int(c[2])])
	return out
