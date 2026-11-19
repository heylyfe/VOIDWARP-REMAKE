extends RefCounted
#
# test_level_shape.gd - job J1 (GEN_VERSION 4, out/decisions/J1.md):
#   1. determinism: the same (seed, level) twice gives an identical level (hash and layout key);
#   2. variety: 200 level-1 seeds give >= 50 unique layouts (key = the tile set plus the gift
#      slots, nothing else - no seed, no ids);
#   3. width: over 200 seeds across levels 1..30 every walkway row is exactly 3 cells wide
#      (rows taken along the axis the walkway touches its parent on) and every tile lies in a
#      full 3x3 square of its own piece or a piece joined to it by an edge (nothing narrower);
#   4. centre lane: every gift slot has a walkable tile in all four neighbour columns and,
#      along at least one axis, exactly one walkable tile on each side (TERRAIN_SPEC 6.7);
#   5. level 1 starts at the hub: piece 0 is the hub holding the beacon, at least two arms
#      leave it, and every other piece's parent chain leads back to it.
# These re-derive every property from the Level dict with their own code (never voidgen
# internals), like terrain_ref/validate.py's H17 / H24 / H25.

const VoidGenScript := preload("res://terrain/voidgen.gd")

const WALK_W := 3
const CLEAR := 12
const VARIETY_SEEDS := 200
const VARIETY_MIN := 50
const WIDTH_SEEDS := 200
const WIDTH_SEED_BASE := 4000
const DX := [1, 0, -1, 0]
const DZ := [0, 1, 0, -1]


func run() -> Array[String]:
	var f: Array[String] = []
	_test_determinism(f)
	_test_level1_variety_and_hub(f)
	_test_width_and_lanes(f)
	return f


# ---- 1. determinism --------------------------------------------------------------------------

func _test_determinism(f: Array[String]) -> void:
	for sl in [[1, 1], [2, 1], [777, 2], [60717, 12], [31337, 30]]:
		var a: Dictionary = VoidGenScript.generate(sl[0], sl[1])
		var b: Dictionary = VoidGenScript.generate(sl[0], sl[1], 1, 0)
		if a.is_empty() or b.is_empty():
			f.append("determinism: seed %d level %d did not generate" % [sl[0], sl[1]])
			continue
		if VoidGenScript.level_hash(a) != VoidGenScript.level_hash(b):
			f.append("determinism: seed %d level %d hashed differently on a second run"
					% [sl[0], sl[1]])
		if layout_key(a) != layout_key(b):
			f.append("determinism: seed %d level %d laid out differently on a second run"
					% [sl[0], sl[1]])


## The layout of a level: its tile set and its gift slots, as text, hashed. No seed, no ids.
static func layout_key(L: Dictionary) -> String:
	var parts: PackedStringArray = []
	for t in L["tiles"]:
		parts.append("%d,%d,%d,%d" % [t[0], t[1], t[2], t[3]])
	parts.append("|")
	for g in L["gifts"]:
		parts.append("%d,%d,%d" % [g["x"], g["z"], g["y"]])
	return ";".join(parts).sha256_text()


# ---- 2 + 5. level 1: variety, and every layout starts at the hub -----------------------------

func _test_level1_variety_and_hub(f: Array[String]) -> void:
	var keys: Dictionary = {}
	var bad_hub: int = 0
	for s in range(VARIETY_SEEDS):
		var L: Dictionary = VoidGenScript.generate(s, 1)
		if L.is_empty():
			f.append("variety: level 1 seed %d did not generate" % s)
			continue
		keys[layout_key(L)] = 1
		var why := _hub_start_fail(L)
		if why != "":
			bad_hub += 1
			if bad_hub <= 3:
				f.append("hub start: level 1 seed %d: %s" % [s, why])
	print("test_level_shape: %d level-1 seeds -> %d unique layouts (need >= %d)"
			% [VARIETY_SEEDS, keys.size(), VARIETY_MIN])
	if keys.size() < VARIETY_MIN:
		f.append("variety: %d level-1 seeds gave only %d unique layouts (need >= %d)"
				% [VARIETY_SEEDS, keys.size(), VARIETY_MIN])


## "" when the level starts at the hub and grows out of it, else the reason.
static func _hub_start_fail(L: Dictionary) -> String:
	var pieces: Array = L["pieces"]
	if pieces.is_empty():
		return "no pieces"
	var hub: Dictionary = pieces[0]
	if str(hub["arch"]) != "hub" or int(hub["role"]) != 0 or int(hub["parent"]) != -1:
		return "piece 0 is not the hub (arch %s role %d)" % [hub["arch"], hub["role"]]
	var b: Array = L["beacon"]
	var on_hub := false
	for t in L["tiles"]:
		if t[0] == b[0] and t[1] == b[1] and t[2] == b[2]:
			on_hub = int(t[4]) == 0
			break
	if not on_hub:
		return "the beacon tile is not on the hub"
	var arms_out: int = 0
	for p in pieces:
		var pid: int = p["id"]
		if pid == 0:
			continue
		if int(p["parent"]) == 0 and int(p["role"]) == 3:
			arms_out += 1
		var cur: int = pid
		var guard: int = 0
		while cur != 0 and cur >= 0 and guard <= pieces.size():
			cur = int(pieces[cur]["parent"])
			guard += 1
		if cur != 0:
			return "piece %d does not lead back to the hub" % pid
	if arms_out < 2:
		return "only %d walkways leave the hub" % arms_out
	return ""


# ---- 3 + 4. width >= 3 everywhere, gifts on centre lanes, 200 seeds over levels 1..30 ---------

func _test_width_and_lanes(f: Array[String]) -> void:
	var bad_w: int = 0
	var bad_g: int = 0
	var walkways: int = 0
	var slots: int = 0
	for k in range(WIDTH_SEEDS):
		var s: int = WIDTH_SEED_BASE + k
		var lvl: int = 1 + k % 30
		var L: Dictionary = VoidGenScript.generate(s, lvl)
		if L.is_empty():
			f.append("width: seed %d level %d did not generate" % [s, lvl])
			continue
		var ctx := _ctx(L)
		for p in L["pieces"]:
			if int(p["kind"]) == 1:
				walkways += 1
		var ww := _width_fail(L, ctx)
		if ww != "":
			bad_w += 1
			if bad_w <= 3:
				f.append("width: seed %d level %d: %s" % [s, lvl, ww])
		for g in L["gifts"]:
			slots += 1
			if not _centre_lane(ctx, int(g["x"]), int(g["z"]), int(g["y"])):
				bad_g += 1
				if bad_g <= 3:
					f.append("centre lane: seed %d level %d gift %d at (%d,%d,%d) is not on a centre lane"
							% [s, lvl, g["id"], g["x"], g["z"], g["y"]])
	if walkways == 0 or slots == 0:
		f.append("width: the sample held %d walkways and %d slots - the check did not run"
				% [walkways, slots])
	if bad_w > 3 or bad_g > 3:
		f.append("width: %d levels too narrow, %d gifts off a centre lane in total" % [bad_w, bad_g])


## Lookups shared by the width and lane checks: columns, props, joined pieces, piece tiles.
static func _ctx(L: Dictionary) -> Dictionary:
	var col: Dictionary = {}     # Vector2i -> Array[tile index]
	var colp: Dictionary = {}    # Vector2i -> {piece: 1}
	var ptiles: Dictionary = {}  # piece -> Array[tile index]
	var tiles: Array = L["tiles"]
	for i in range(tiles.size()):
		var t: Array = tiles[i]
		var c := Vector2i(t[0], t[1])
		if not col.has(c):
			col[c] = []
			colp[c] = {}
		col[c].append(i)
		colp[c][int(t[4])] = 1
		var pid: int = t[4]
		if not ptiles.has(pid):
			ptiles[pid] = []
		ptiles[pid].append(i)
	var props: Dictionary = {}
	for p in L["props"]:
		props[Vector3i(p[0], p[1], p[2])] = 1
	var joined: Dictionary = {}
	for p in L["pieces"]:
		joined[int(p["id"])] = {int(p["id"]): 1}
	for e in L["edges"]:
		joined[int(e[0])][int(e[1])] = 1
		joined[int(e[1])][int(e[0])] = 1
	return {"tiles": tiles, "col": col, "colp": colp, "ptiles": ptiles, "props": props,
		"joined": joined}


## "" when every walkway row is exactly WALK_W cells and every tile sits in a full 3x3 square.
static func _width_fail(L: Dictionary, ctx: Dictionary) -> String:
	var tiles: Array = ctx["tiles"]
	for p in L["pieces"]:
		if int(p["kind"]) != 1:
			continue
		var idxs: Array = ctx["ptiles"].get(int(p["id"]), [])
		if idxs.is_empty():
			return "walkway %d has no tiles" % p["id"]
		var axis := _travel_axis(ctx, idxs, int(p["parent"]))
		var rows: Dictionary = {}
		for i in idxs:
			var c: int = tiles[i][axis]
			rows[c] = int(rows.get(c, 0)) + 1
		for c in rows:
			if int(rows[c]) != WALK_W:
				return "walkway %d has a row %d cells wide (want exactly %d)" % [p["id"], rows[c], WALK_W]
	for t in tiles:
		if not _in_full_square(ctx, t):
			return "tile (%d,%d,%d) of piece %d is on a part narrower than 3 cells" % [t[0], t[1], t[2], t[4]]
	return ""


## The walkway's travel axis: 0 when it touches its parent along x, 1 along z.
static func _travel_axis(ctx: Dictionary, idxs: Array, parent: int) -> int:
	var tiles: Array = ctx["tiles"]
	var votes := [0, 0]
	for i in idxs:
		var t: Array = tiles[i]
		for d in range(4):
			for j in ctx["col"].get(Vector2i(t[0] + DX[d], t[1] + DZ[d]), []):
				var u: Array = tiles[j]
				if int(u[4]) == parent and absi(int(u[2]) - int(t[2])) < CLEAR:
					votes[d % 2] += 1
					break
	if votes[0] != votes[1]:
		return 0 if votes[0] > votes[1] else 1
	var x0: int = tiles[idxs[0]][0]
	var x1: int = x0
	var z0: int = tiles[idxs[0]][1]
	var z1: int = z0
	for i in idxs:
		x0 = mini(x0, tiles[i][0])
		x1 = maxi(x1, tiles[i][0])
		z0 = mini(z0, tiles[i][1])
		z1 = maxi(z1, tiles[i][1])
	return 0 if (x1 - x0) >= (z1 - z0) else 1


static func _in_full_square(ctx: Dictionary, t: Array) -> bool:
	var jp: Dictionary = ctx["joined"].get(int(t[4]), {int(t[4]): 1})
	for ox in [-2, -1, 0]:
		for oz in [-2, -1, 0]:
			var full := true
			for a in range(3):
				for b in range(3):
					var cp: Variant = ctx["colp"].get(Vector2i(t[0] + ox + a, t[1] + oz + b))
					var hit := false
					if cp != null:
						for q in cp:
							if jp.has(q):
								hit = true
								break
					if not hit:
						full = false
						break
				if not full:
					break
			if full:
				return true
	return false


static func _lane(ctx: Dictionary, x: int, z: int, y: int) -> bool:
	for j in ctx["col"].get(Vector2i(x, z), []):
		var u: Array = ctx["tiles"][j]
		if absi(int(u[2]) - y) < CLEAR and not ctx["props"].has(Vector3i(u[0], u[1], u[2])):
			return true
	return false


static func _centre_lane(ctx: Dictionary, x: int, z: int, y: int) -> bool:
	for d in range(4):
		if not _lane(ctx, x + DX[d], z + DZ[d], y):
			return false
	for a in range(2):
		if not _lane(ctx, x + 2 * DX[a], z + 2 * DZ[a], y) \
				and not _lane(ctx, x - 2 * DX[a], z - 2 * DZ[a], y):
			return true
	return false
