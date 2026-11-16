class_name VoidGen
extends RefCounted

## VOIDWRAP RUN terrain generator - GDScript port of terrain_ref/voidgen.py (the oracle).
## Pure function of (seed, level, players, extra_mines). Byte-identical canonical text.
## Porting contract: TERRAIN_SPEC.md section 3. Python's self.range(n) is rng.urange(n) here.

const VoidRngScript := preload("res://terrain/void_rng.gd")

const GEN_VERSION := 3
const M32 := 0xFFFFFFFF

# ---- units ---------------------------------------------------------------
const MAX_ATTEMPTS := 24
const CLEAR := 12
const SLAB := 2
const Y_MIN := -48
const Y_MAX := 72
const DX := [1, 0, -1, 0]  # dir 0:+x 1:+z 2:-x 3:-z
const DZ := [0, 1, 0, -1]
const N8 := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), \
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]

# validator / reachability envelope
const JUMP_UP_MAX := 4
const JUMP_GAP := [5, 4, 3]
const DROP_MAX := 60
const AUTH_GAP := [4, 3, 2]

const ROLE_HUB := 0
const ROLE_ROOM := 1
const ROLE_DEADEND := 2
const ROLE_LINK := 3
const ROLE_LOOP := 4
const ROLE_DROP := 5
const EDGE_TREE := 0
const EDGE_LOOP := 1
const EDGE_DROP := 2
const EDGE_PAD := 3

const WALKS := ["step", "stair", "ledge", "flat", "ramp"]
const PLATS := ["pad", "disc", "cross", "ell", "terrace", "nook", "spire", "bastion"]
const TRAITS := ["grand", "ascent", "descent", "hop", "maze", "thin"]

const ST_PLAN := 1
const ST_GROW := 2
const ST_LOOP := 3
const ST_GIFT := 4
const ST_MINE := 5

const PROP_BLOCK := 0
const PROP_WALL := 1
const PROP_CRATE := 2
const PROP_PILLAR := 3
const AN_PERCH := 0
const AN_OPEN := 1
const AN_LANE := 2
# 3 is retired and reserved (the `hop` anchor kind is never emitted, TERRAIN_SPEC 6.5)
const AN_NOOK := 4

# trait multipliers, quarter units (4 = x1)
const TRAIT_LINK := {
	"grand": {"step": 8, "stair": 2, "ledge": 2, "flat": 8, "ramp": 4},
	"ascent": {"step": 8, "stair": 8, "ledge": 4, "flat": 3, "ramp": 4},
	"descent": {"step": 8, "stair": 8, "ledge": 4, "flat": 3, "ramp": 4},
	"hop": {"step": 4, "stair": 10, "ledge": 8, "flat": 2, "ramp": 2},
	"maze": {"step": 6, "stair": 4, "ledge": 4, "flat": 6, "ramp": 4},
	"thin": {"step": 10, "stair": 4, "ledge": 5, "flat": 3, "ramp": 4},
}
const TRAIT_ROOM := {
	"grand": {"pad": 8, "cross": 8, "disc": 8, "terrace": 4},
	"ascent": {"terrace": 12, "spire": 12, "bastion": 8},
	"descent": {"terrace": 12, "disc": 6, "pad": 6},
	"hop": {"spire": 20, "cross": 8, "disc": 6},
	"maze": {"cross": 12, "ell": 12, "pad": 6},
	"thin": {"nook": 16, "ell": 8, "bastion": 8},
}
const TRAIT_UP_PCT := {"grand": 50, "ascent": 85, "descent": 15, "hop": 55, "maze": 50, "thin": 50}
const TRAIT_W := {"grand": 10, "ascent": 8, "descent": 8, "hop": 4, "maze": 8, "thin": 3}

const SPAWNS := [[1, 1], [-1, -1], [-1, 1], [1, -1], [2, 0], [-2, 0], [0, 2], [0, -2]]

const SPIRE_Q := [Vector2i(0, 0), Vector2i(4, 0), Vector2i(4, 4), Vector2i(0, 4)]
const SPIRE_OUT := [Vector2i(2, 3), Vector2i(0, 3), Vector2i(0, 1), Vector2i(2, 1)]

static var _jump_offs: Array = []


# ---- tuning knobs (TERRAIN_SPEC section 9) ---------------------------------
@warning_ignore("integer_division")
static func plat_max(level: int) -> int:
	var n: int = 4 + level / 3
	return n if n < 12 else 12


@warning_ignore("integer_division")
static func elev_var_floor(level: int) -> int:
	var t: int = level if level < 10 else 10
	return 3 + 3 * (t - 1) / 9


@warning_ignore("integer_division")
static func tuning(level: int, players: int) -> Dictionary:
	var t: int = level if level < 30 else 30
	return {
		"t": t,
		"plat_max": plat_max(level),
		"arms_min": 2,
		"arms_max": 3 if level < 4 else 4,
		"radius": 70 + 2 * t,
		"slots": slot_target(level, players),
		"loops_max": 2 + t / 6,
		"drops_max": 2 + t / 8,
		"ray_len": 20,
		"loop_min_graph_dist": 4,
		"grow_tries": 5,
		"turn_pct": 75,
		"walk_w": {
			"step": 20, "stair": 6 + t / 3, "ledge": 5,
			"flat": maxi(1, 4 - t / 8), "ramp": maxi(2, 5 - t / 6),
		},
		"plat_w": {
			"pad": 10, "disc": 7, "cross": 10, "ell": 8, "terrace": 8,
			"nook": 5, "spire": 3 + t / 5, "bastion": 5,
		},
		"w1_pct": 20 + 40 * (t - 1) / 29,
		"plat_pct": 40,
		"term_pct": 35,
		"jump_min_depth": maxi(1, 10 - t),
	}


@warning_ignore("integer_division")
static func slot_target(level: int, players: int) -> int:
	var base: int = mini(160, 40 + 4 * (level - 1))
	return base * (1 + players) / 2


static func mine_chance_num(level: int) -> int:
	# per-slot tripmine chance = num/400. 0 below level 5, 1/20 at 5, 1/10 at 25, capped.
	if level < 5:
		return 0
	return 15 + (level if level < 25 else 25)


# ---- RNG helpers are in terrain/void_rng.gd (mul32, fmix, mix, Rng) --------


@warning_ignore("integer_division")
static func offs_for(w: int) -> Array:
	# lateral offsets for a link of width w: 1->[0] 2->[0,1] 3->[-1,0,1] 4->[-1,0,1,2] 5->[-2..2]
	var lo: int = (w - 1) / 2
	var out: Array = []
	for k in range(-lo, w - lo):
		out.append(k)
	return out


# ---- room archetypes ---------------------------------------------------------
# Each returns [tiles, socks, props, anchors]:
#   tiles   [lx, lz, dy, kind]   kind 0 = flat, 1+dir = ramp ascending toward dir
#   socks   [lx, lz, dir, dy, wmax]  (lx,lz) is an edge tile; dir points outward
#   props  [lx, lz, dy, h, kind]
#   anchors [kind, lx, lz, dy]


@warning_ignore("integer_division")
static func scatter(rng, tiles: Array, socks: Array, count: int, props: Array) -> void:
	# place up to `count` blocking props on interior flat tiles, Chebyshev >= 3 apart,
	# never within Chebyshev 2 of a socket tile.
	var d: Dictionary = {}
	for t in tiles:
		d[Vector2i(t[0], t[1])] = t
	var cand: Array = []
	for t in tiles:
		if t[3] != 0:
			continue
		var ok := true
		for o in N8:
			var nb: Variant = d.get(Vector2i(t[0] + o.x, t[1] + o.y))
			if nb == null or nb[2] != t[2] or nb[3] != 0:
				ok = false
				break
		if not ok:
			continue
		for s in socks:
			if absi(s[0] - t[0]) <= 2 and absi(s[1] - t[1]) <= 2:
				ok = false
				break
		if ok:
			cand.append(t)
	rng.shuffle(cand)
	var placed: Array = []
	for t in cand:
		if placed.size() >= count:
			break
		var ok2 := true
		for p in placed:
			if absi(p[0] - t[0]) < 3 and absi(p[1] - t[1]) < 3:
				ok2 = false
				break
		if ok2:
			placed.append(t)
			var kind: int = rng.wpick([PROP_BLOCK, PROP_WALL, PROP_CRATE, PROP_PILLAR], [5, 2, 4, 2])
			# (4, 6, 2, 10)[kind] + (rng.urange(2) * 2 only when kind != crate)
			var h: int = [4, 6, 2, 10][kind]
			if kind != PROP_CRATE:
				h += rng.urange(2) * 2
			props.append([t[0], t[1], t[2], h, kind])


@warning_ignore("integer_division")
static func plat_pad(rng, _t: int, _gentle: bool) -> Array:
	# Square rest point. bbox <= 7x7 and <= 40 tiles (TERRAIN_SPEC section 1A rule 2).
	var w: int = rng.ri(3, 7)
	var dmax: int = 40 / w
	if dmax > 7:
		dmax = 7
	var d: int = rng.ri(3, dmax)
	var tiles: Array = []
	for x in range(w):
		for z in range(d):
			tiles.append([x, z, 0, 0])
	var jx: int = rng.ri(0, w - 1)
	var jz: int = rng.ri(0, d - 1)
	var jx2: int = rng.ri(0, w - 1)
	var jz2: int = rng.ri(0, d - 1)
	var socks: Array = [[w - 1, jz, 0, 0, 2], [jx, d - 1, 1, 0, 2], [0, jz2, 2, 0, 2], [jx2, 0, 3, 0, 2]]
	var props: Array = []
	scatter(rng, tiles, socks, rng.ri(0, 2), props)
	var anchors: Array = []
	if w * d >= 25:
		anchors.append([AN_OPEN, w / 2, d / 2, 0])
	return [tiles, socks, props, anchors]


static func plat_disc(rng, _t: int, _gentle: bool) -> Array:
	# Round rest point, radius 2..3 (bbox 5x5 or 7x7).
	var r: int = rng.ri(2, 3)
	var tiles: Array = []
	for x in range(-r, r + 1):
		for z in range(-r, r + 1):
			if x * x + z * z <= r * r + r:
				tiles.append([x, z, 0, 0])
	var socks: Array = [[r, 0, 0, 0, 2], [0, r, 1, 0, 2], [-r, 0, 2, 0, 2], [0, -r, 3, 0, 2]]
	var props: Array = []
	scatter(rng, tiles, socks, rng.ri(0, 1), props)
	var anchors: Array = []
	if r >= 3:
		anchors.append([AN_OPEN, 0, 0, 0])
	return [tiles, socks, props, anchors]


@warning_ignore("integer_division")
static func plat_cross(rng, _t: int, _gentle: bool) -> Array:
	# Four-way junction. Arm width 1..2, arm lengths 1..3, bbox <= 7x7.
	var a: int = rng.ri(1, 2)
	var rem: int = 7 - a
	var l0: int = rng.ri(1, 3)
	if l0 > rem - 1:
		l0 = rem - 1
	var l2: int = rng.ri(1, 3)
	if l2 > rem - l0:
		l2 = rem - l0
	var l1: int = rng.ri(1, 3)
	if l1 > rem - 1:
		l1 = rem - 1
	var l3: int = rng.ri(1, 3)
	if l3 > rem - l1:
		l3 = rem - l1
	var tiles: Array = []
	for x in range(-l2, a + l0):
		for z in range(-l3, a + l1):
			if (0 <= x and x < a) or (0 <= z and z < a):
				tiles.append([x, z, 0, 0])
	var m: int = a / 2
	var socks: Array = [[a + l0 - 1, m, 0, 0, a], [m, a + l1 - 1, 1, 0, a], [-l2, m, 2, 0, a], [m, -l3, 3, 0, a]]
	var props: Array = []
	if a >= 2:
		scatter(rng, tiles, socks, rng.ri(0, 1), props)
	return [tiles, socks, props, []]


@warning_ignore("integer_division")
static func plat_ell(rng, _t: int, _gentle: bool) -> Array:
	# Corner. Arm width 1..2, arm lengths 2..5.
	var a: int = rng.ri(1, 2)
	var la: int = rng.ri(2, 5)
	var lb: int = rng.ri(2, 5)
	var tiles: Array = []
	for x in range(la):
		for z in range(lb):
			if z < a or x < a:
				tiles.append([x, z, 0, 0])
	var m: int = a / 2
	var socks: Array = [[la - 1, m, 0, 0, a], [m, lb - 1, 1, 0, a], [0, m, 2, 0, a], [m, 0, 3, 0, a]]
	var props: Array = []
	if a >= 2:
		scatter(rng, tiles, socks, rng.ri(0, 1), props)
	return [tiles, socks, props, []]


static func plat_terrace(rng, _t: int, gentle: bool) -> Array:
	# Two-level platform: the upper band is one step up (1 HU when gentle, else 2 HU).
	var w: int = rng.ri(3, 6)
	var d1: int = rng.ri(2, 3)
	var d2: int = rng.ri(2, 3)
	var up: int = 1 if gentle else 2
	var tiles: Array = []
	for x in range(w):
		for z in range(d1):
			tiles.append([x, z, 0, 0])
		for z in range(d1, d1 + d2):
			tiles.append([x, z, up, 0])
	var r0: int = rng.ri(0, w - 1)
	var socks: Array = [[w - 1, 0, 0, 0, 2], [0, 0, 2, 0, 2],
		[r0, d1 + d2 - 1, 1, up, 2], [w - 1, d1, 0, up, 2]]
	return [tiles, socks, [], []]


@warning_ignore("integer_division")
static func plat_nook(rng, _t: int, _gentle: bool) -> Array:
	# Walled on three sides, ONE socket: a guaranteed dead end.
	var s: int = rng.ri(4, 6)
	var tiles: Array = []
	var props: Array = []
	for x in range(s):
		for z in range(s):
			tiles.append([x, z, 0, 0])
			if x >= 1 and (x == s - 1 or z == 0 or z == s - 1):
				props.append([x, z, 0, 6, PROP_WALL])
	var socks: Array = [[0, s / 2, 2, 0, 2]]
	return [tiles, socks, props, [[AN_NOOK, s / 2, s / 2, 0]]]


static func plat_spire(rng, _t: int, _gentle: bool) -> Array:
	# 2..3 pads of 3x3 spiralling up, +3 HU each, gap 1: a vertical climb with an overlook.
	var n: int = rng.ri(2, 3)
	var tiles: Array = []
	for k in range(n):
		var qv: Vector2i = SPIRE_Q[k % 4]
		for x in range(3):
			for z in range(3):
				tiles.append([qv.x + x, qv.y + z, 3 * k, 0])
	var socks: Array = [[0, 1, 2, 0, 2], [1, 0, 3, 0, 2]]
	var kq: int = (n - 1) % 4
	var q: Vector2i = SPIRE_Q[kq]
	var od: int = SPIRE_OUT[kq][rng.urange(2)]
	var top: int = 3 * (n - 1)
	if od == 0:
		socks.append([q.x + 2, q.y + 1, 0, top, 2])
	elif od == 1:
		socks.append([q.x + 1, q.y + 2, 1, top, 2])
	elif od == 2:
		socks.append([q.x, q.y + 1, 2, top, 2])
	else:
		socks.append([q.x + 1, q.y, 3, top, 2])
	var anchors: Array = [[AN_PERCH, q.x + 1, q.y + 1, top]]
	return [tiles, socks, [], anchors]


@warning_ignore("integer_division")
static func plat_bastion(rng, _t: int, _gentle: bool) -> Array:
	# Small square with a 3x3 tower +4 HU in the middle: an overlook.
	var s: int = rng.ri(5, 6)
	var c: int = s / 2
	var tiles: Array = []
	for x in range(s):
		for z in range(s):
			var tower := absi(x - c) <= 1 and absi(z - c) <= 1  # optional high ground, never on a route
			tiles.append([x, z, 4 if tower else 0, 0])
	var r0: int = rng.ri(1, s - 2)
	var r1: int = rng.ri(1, s - 2)
	var r2: int = rng.ri(1, s - 2)
	var r3: int = rng.ri(1, s - 2)
	var socks: Array = [[s - 1, r0, 0, 0, 2], [r1, s - 1, 1, 0, 2], [0, r2, 2, 0, 2], [r3, 0, 3, 0, 2]]
	return [tiles, socks, [], [[AN_PERCH, c, c, 4]]]


static func _plat(arch: String, rng, t: int, gentle: bool) -> Array:
	match arch:
		"pad":
			return plat_pad(rng, t, gentle)
		"disc":
			return plat_disc(rng, t, gentle)
		"cross":
			return plat_cross(rng, t, gentle)
		"ell":
			return plat_ell(rng, t, gentle)
		"terrace":
			return plat_terrace(rng, t, gentle)
		"nook":
			return plat_nook(rng, t, gentle)
		"spire":
			return plat_spire(rng, t, gentle)
		"bastion":
			return plat_bastion(rng, t, gentle)
	return [[], [], [], []]


# ---- walkways ---------------------------------------------------------------
static func build_walkway(rng, arch: String, x: int, z: int, d: int, y: int, w: int, tn: Dictionary, up_pct: int) -> Variant:
	# Build a straight walkway starting at cell (x,z) heading dir d at height y.
	# Returns [cells, n, y_end, jumps, w] where cells = [x,z,y,kind,is_center], n = rows consumed
	# along d (the platform's entry tile goes at index n), or null.
	# A tread is a run of rows at one height; consecutive treads differ by the arch's step
	# (TERRAIN_SPEC section 6.4). Every step is inside the AUTHORING envelope both ways.
	var lat: int = (d + 1) % 4
	var offs: Array = offs_for(w)
	var cells: Array = []
	var row := func(i: int, yy: int, kind: int) -> void:
		for o in offs:
			cells.append([x + DX[d] * i + DX[lat] * o, z + DZ[d] * i + DZ[lat] * o, yy, kind, 1 if o == 0 else 0])
	var up: bool = rng.chance(up_pct, 100)
	var i: int = 0
	var cy: int = y
	var jumps: int = 0
	if arch == "step":
		var k: int = rng.ri(4, 6)
		for s in range(k):
			if s > 0:
				cy += 1 if up else -1
			var ln: int = rng.ri(1, 2)
			for q in range(ln):
				row.call(i, cy, 0)
				i += 1
	elif arch == "stair":
		var k: int = rng.ri(2, 4)
		for s in range(k):
			if s > 0:
				cy += 2 if up else -2
				jumps += 1
			var ln: int = rng.ri(1, 2)
			for q in range(ln):
				row.call(i, cy, 0)
				i += 1
	elif arch == "ledge":
		var a: int = rng.ri(1, 2)
		for q in range(a):
			row.call(i, cy, 0)
			i += 1
		var mag: int = rng.ri(2, 4)
		cy = cy + mag if up else cy - mag
		jumps += 1
		var b: int = rng.ri(1, 2)
		for q in range(b):
			row.call(i, cy, 0)
			i += 1
	elif arch == "flat":
		var ln: int = rng.ri(2, 4)
		for q in range(ln):
			row.call(i, cy, 0)
			i += 1
	elif arch == "ramp":
		var a: int = rng.ri(1, 2)
		for q in range(a):
			row.call(i, cy, 0)
			i += 1
		var n: int = rng.ri(1, 2)
		for q in range(n):
			if up:
				row.call(i, cy, 1 + d)
				cy += 1
			else:
				cy -= 1
				row.call(i, cy, 1 + (d + 2) % 4)
			i += 1
		var b: int = rng.ri(1, 2)
		for q in range(b):
			row.call(i, cy, 0)
			i += 1
	else:
		return null
	if cy < Y_MIN or cy > Y_MAX:
		return null
	return [cells, i, cy, jumps, w]


# ---- world -------------------------------------------------------------------
class World extends RefCounted:
	var tiles: Array = []     # [x, z, y, kind, pid]
	var col: Dictionary = {}  # Vector2i(x,z) -> Array[tile index]
	var props: Array = []     # [x, z, y, h, kind, pid]
	var pcol: Dictionary = {} # Vector2i(x,z) -> Array[prop index]
	var pieces: Array = []    # Dictionary per piece
	var edges: Array = []     # [a, b, kind]
	var anchors: Array = []   # [kind, x, z, y, pid]
	var pads: Array = []      # [x, z, y, tx, tz, ty]
	var nbr: Dictionary = {}  # pid -> Array[pid] (undirected piece graph)
	var shapes: Dictionary = {}  # "arch:min:max:count" -> 1, lookup only

	func fits(cells: Array, allow: Array) -> bool:
		var T: Array = tiles
		for c in cells:
			var x: int = c[0]
			var z: int = c[1]
			var y: int = c[2]
			var lst: Variant = col.get(Vector2i(x, z))
			if lst != null:
				for i in lst:
					if absi(T[i][2] - y) < CLEAR:
						return false
			for o in N8:
				var lst2: Variant = col.get(Vector2i(x + o.x, z + o.y))
				if lst2 != null:
					for i in lst2:
						var tt: Array = T[i]
						if absi(tt[2] - y) < CLEAR and not allow.has(tt[4]):
							return false
		return true

	func add_piece(kind: int, arch: String, parent: int, depth: int, arm: int, role: int, y: int) -> int:
		var pid: int = pieces.size()
		pieces.append({"id": pid, "kind": kind, "arch": arch, "parent": parent, "depth": depth,
			"arm": arm, "role": role, "y": y, "center": [], "jumps": 0, "w": 0})
		nbr[pid] = []
		return pid

	func add_tile(x: int, z: int, y: int, kind: int, pid: int) -> int:
		var i: int = tiles.size()
		tiles.append([x, z, y, kind, pid])
		var key := Vector2i(x, z)
		var lst: Variant = col.get(key)
		if lst == null:
			col[key] = [i]
		else:
			lst.append(i)
		return i

	func add_prop(x: int, z: int, y: int, h: int, kind: int, pid: int) -> void:
		var i: int = props.size()
		props.append([x, z, y, h, kind, pid])
		var key := Vector2i(x, z)
		var lst: Variant = pcol.get(key)
		if lst == null:
			pcol[key] = [i]
		else:
			lst.append(i)

	func add_edge(a: int, b: int, kind: int) -> void:
		edges.append([a, b, kind])
		nbr[a].append(b)
		nbr[b].append(a)

	@warning_ignore("integer_division")
	func graph_dist(a: int, b: int, cap: int) -> int:
		if a == b:
			return 0
		var seen: Dictionary = {a: 0}
		var q: Array = [a]
		var h: int = 0
		while h < q.size():
			var c: int = q[h]
			h += 1
			var dc: int = seen[c]
			if dc >= cap:
				continue
			for n in nbr[c]:
				if not seen.has(n):
					if n == b:
						return dc + 1
					seen[n] = dc + 1
					q.append(n)
		return cap + 1


static func xform(lx: int, lz: int, mir: int, rot: int) -> Vector2i:
	if mir != 0:
		lx = -lx
	if rot == 0:
		return Vector2i(lx, lz)
	if rot == 1:
		return Vector2i(-lz, lx)
	if rot == 2:
		return Vector2i(-lx, -lz)
	return Vector2i(lz, -lx)


static func xdir(d: int, mir: int, rot: int) -> int:
	if mir != 0 and (d == 0 or d == 2):
		d = 2 - d
	return (d + rot) % 4


static func build_hub(W: World) -> Array:
	# The one dominant spawn platform (TERRAIN_SPEC section 6.1): 205 tiles, bbox 19x19.
	# Plaza [-6,6]^2 at y=0, dais [-2,2]^2 at y=1, four 3-wide stubs at cells 7..9.
	var pid: int = W.add_piece(0, "hub", -1, 0, -1, ROLE_HUB, 0)
	for x in range(-6, 7):
		for z in range(-6, 7):
			W.add_tile(x, z, 1 if (absi(x) <= 2 and absi(z) <= 2) else 0, 0, pid)
	for d in range(4):
		var lat: int = (d + 1) % 4
		for i in range(7, 10):
			for o in range(-1, 2):
				W.add_tile(DX[d] * i + DX[lat] * o, DZ[d] * i + DZ[lat] * o, 0, 0, pid)
	for c in [[6, 6], [-6, 6], [-6, -6], [6, -6]]:
		W.add_prop(c[0], c[1], 0, 10, PROP_PILLAR, pid)
	return [pid, [[9, 0, 0, 0, pid, 2, 0], [0, 9, 1, 0, pid, 2, 0], [-9, 0, 2, 0, pid, 2, 0], [0, -9, 3, 0, pid, 2, 0]]]


@warning_ignore("integer_division")
static func try_grow(W: World, rng, sock: Array, arm: int, trait_name: String, tn: Dictionary, arch_count: Dictionary, state: Dictionary, drift: int) -> Variant:
	# Grow one step out of `sock`: build a walkway, then either attach a platform at its far end
	# or leave the walkway's far end as a socket the next step grows from (TERRAIN_SPEC 6.3).
	# Returns an Array of new sockets (possibly empty), or false if nothing could be built.
	var x: int = sock[0]
	var z: int = sock[1]
	var d: int = sock[2]
	var y: int = sock[3]
	var pid: int = sock[4]
	var wmax: int = sock[5]
	var lat: int = (d + 1) % 4
	var parent: Dictionary = W.pieces[pid]
	var t: int = tn["t"]
	var gentle: bool = parent["depth"] + 1 < tn["jump_min_depth"]
	# walkway archetype
	var lw: Array = []
	var tl: Dictionary = TRAIT_LINK[trait_name]
	for name in WALKS:
		var wv: int = tn["walk_w"][name] * int(tl[name])
		if gentle and (name == "stair" or name == "ledge"):
			wv = 0  # paths near the hub are walkable on early levels (D8 gentle start)
		lw.append(wv)
	var larch: String = rng.wpick(WALKS, lw)
	# width: 1 or 2 cells, never more (TERRAIN_SPEC section 1A rule 2)
	var hi: int = wmax if wmax < 2 else 2
	var w: int = hi
	if not gentle:
		w = 1 if rng.chance(tn["w1_pct"], 100) else 2
		if w > hi:
			w = hi
	if trait_name == "thin":
		w = 1
	elif trait_name == "grand":
		w = hi
	if w > hi:
		w = hi
	var up_pct: int = TRAIT_UP_PCT[trait_name] + 22 * drift
	if up_pct < 5:
		up_pct = 5
	elif up_pct > 95:
		up_pct = 95
	if y >= 24:
		up_pct = 0
	elif y <= -24:
		up_pct = 100
	# junction step at the near end: a path leaves a platform 0..2 HU above or below it, so
	# sub-area boundaries step instead of meeting flush (section 1A rule 3)
	var y0: int = y
	if parent["kind"] == 0:
		if gentle:
			y0 = y + (1 if rng.chance(50, 100) else -1)
		else:
			y0 = y + [1, -1, 2, -2, 1, -1, 2, -2][rng.urange(8)]
		if y0 < Y_MIN or y0 > Y_MAX:
			return false
	var lk: Variant = build_walkway(rng, larch, x + DX[d], z + DZ[d], d, y0, w, tn, up_pct)
	if lk == null:
		return false
	var cells: Array = lk[0]
	var n: int = lk[1]
	var y1: int = lk[2]
	var jumps: int = lk[3]
	w = lk[4]
	var px: int = x + DX[d] * (1 + n)
	var pz: int = z + DZ[d] * (1 + n)
	var R: int = tn["radius"]
	# attach a platform at the far end? (the roll is always drawn: draw order is contract)
	var roll: bool = rng.chance(tn["plat_pct"], 100)
	var attach: bool = false
	if state["placed"] < state["target"] and state["since"] >= 3:
		attach = state["since"] >= 6 or roll or state["placed"] >= state["target"] - 1
	if not attach:
		# walkway only: its far end becomes a socket and the path continues. The socket turns 90
		# degrees with turn_pct, so a path winds instead of running out as a straight stick.
		if not W.fits(cells, [pid]):
			return false
		var depth: int = parent["depth"] + 1
		var lid: int = W.add_piece(1, larch, pid, depth, arm, ROLE_LINK, y)
		var lp: Dictionary = W.pieces[lid]
		lp["jumps"] = jumps
		lp["w"] = w
		for c in cells:
			var ti: int = W.add_tile(c[0], c[1], c[2], c[3], lid)
			if c[4]:
				lp["center"].append(ti)
		if (larch == "step" or larch == "flat") and n >= 8:
			var m: Array = cells[(n / 2) * offs_for(w).size()]
			W.anchors.append([AN_LANE, m[0], m[1], m[2], lid])
		W.add_edge(pid, lid, EDGE_TREE)
		state["since"] += 1
		var turn: int = rng.urange(2)
		var do_turn: bool = rng.chance(tn["turn_pct"], 100)
		if do_turn:
			# the socket sits on the last row's outer tile on the chosen side and points sideways
			var sd: int = lat if turn == 0 else (lat + 2) % 4
			var so: int = w - 1 if turn == 0 else 0
			var sx: int = x + DX[d] * n + DX[lat] * so
			var sz: int = z + DZ[d] * n + DZ[lat] * so
			return [[sx, sz, sd, y1, lid, w, 0]]
		return [[px - DX[d], pz - DZ[d], d, y1, lid, w, 1]]
	# platform archetype
	var rw: Array = []
	var tr: Dictionary = TRAIT_ROOM[trait_name]
	for name in PLATS:
		var wv2: int = tn["plat_w"][name] * int(tr.get(name, 4))
		if name == parent["arch"]:
			wv2 = wv2 / 4
		var c2: int = arch_count.get(name, 0)
		if c2 >= 2:
			wv2 = wv2 / c2
		wv2 += 1
		if gentle and name == "spire":
			wv2 = 0  # no jump-only platform near the hub on early levels
		rw.append(wv2)
	# no two platforms of one level may share (archetype, footprint, tile count): re-roll up to 4x
	var shape: String = ""
	var arch: String = ""
	var tiles: Array = []
	var socks: Array = []
	var props: Array = []
	var anchors: Array = []
	for _reroll in range(4):
		arch = rng.wpick(PLATS, rw)
		var res: Array = _plat(arch, rng, t, gentle)
		tiles = res[0]
		socks = res[1]
		props = res[2]
		anchors = res[3]
		var x0: int = tiles[0][0]
		var x1: int = tiles[0][0]
		var z0: int = tiles[0][1]
		var z1: int = tiles[0][1]
		for q in tiles:
			if q[0] < x0:
				x0 = q[0]
			if q[0] > x1:
				x1 = q[0]
			if q[1] < z0:
				z0 = q[1]
			if q[1] > z1:
				z1 = q[1]
		var a: int = x1 - x0
		var b: int = z1 - z0
		if a > b:
			var tmp: int = a
			a = b
			b = tmp
		shape = "%s:%d:%d:%d" % [arch, a, b, tiles.size()]
		if not W.shapes.has(shape):
			break
	var mir: int = rng.urange(2)
	var e: Array = socks[rng.urange(socks.size())]
	var rot: int = ((d + 2) - xdir(e[2], mir, 0) + 4) % 4
	# junction step: the platform sits 1..2 HU above or below the walkway's end (section 6.3 step f)
	var step: int
	if gentle:
		step = 1 if rng.chance(50, 100) else -1
	else:
		step = [1, -1, 2, -2, 1, -1, 2, -2][rng.urange(8)]
	var ex: Vector2i = xform(e[0], e[1], mir, rot)
	var ox: int = px - ex.x
	var oz: int = pz - ex.y
	var oy: int = y1 + step - e[3]
	var linkcols: Dictionary = {}
	for c in cells:
		linkcols[Vector2i(c[0], c[1])] = 1
	var wt: Array = []
	for tl2 in tiles:
		var tv: Vector2i = xform(tl2[0], tl2[1], mir, rot)
		var tx: int = tv.x + ox
		var tz: int = tv.y + oz
		var ty: int = tl2[2] + oy
		if ty < Y_MIN or ty > Y_MAX or absi(tx) > R or absi(tz) > R:
			return false
		if linkcols.has(Vector2i(tx, tz)):
			return false
		var kk: int = tl2[3]
		if kk:
			kk = 1 + xdir(kk - 1, mir, rot)
		wt.append([tx, tz, ty, kk])
	if not W.fits(cells, [pid]):
		return false
	if not W.fits(wt, []):
		return false
	# commit
	var depth2: int = parent["depth"] + 1
	var lid2: int = W.add_piece(1, larch, pid, depth2, arm, ROLE_LINK, y)
	var lp2: Dictionary = W.pieces[lid2]
	lp2["jumps"] = jumps
	lp2["w"] = w
	for c in cells:
		var ti2: int = W.add_tile(c[0], c[1], c[2], c[3], lid2)
		if c[4]:
			lp2["center"].append(ti2)
	var rid: int = W.add_piece(0, arch, lid2, depth2 + 1, arm, ROLE_ROOM, oy)
	for c in wt:
		W.add_tile(c[0], c[1], c[2], c[3], rid)
	for p in props:
		var pv: Vector2i = xform(p[0], p[1], mir, rot)
		W.add_prop(pv.x + ox, pv.y + oz, p[2] + oy, p[3], p[4], rid)
	for a2 in anchors:
		var av: Vector2i = xform(a2[1], a2[2], mir, rot)
		W.anchors.append([a2[0], av.x + ox, av.y + oz, a2[3] + oy, rid])
	if (larch == "step" or larch == "flat") and n >= 8:
		var m2: Array = cells[(n / 2) * offs_for(w).size()]
		W.anchors.append([AN_LANE, m2[0], m2[1], m2[2], lid2])
	W.add_edge(pid, lid2, EDGE_TREE)
	W.add_edge(lid2, rid, EDGE_TREE)
	arch_count[arch] = arch_count.get(arch, 0) + 1
	W.shapes[shape] = 1
	state["placed"] += 1
	state["since"] = 0
	var term_roll: bool = rng.chance(tn["term_pct"], 100)
	var terminal: bool = state["placed"] >= state["target"] or term_roll
	var out: Array = []
	for s in socks:
		if s == e:
			continue
		var sv: Vector2i = xform(s[0], s[1], mir, rot)
		var sd2: int = xdir(s[2], mir, rot)
		out.append([sv.x + ox, sv.y + oz, sd2, s[3] + oy, rid, s[4], 1 if sd2 == d else 0])
	if terminal:
		state["dead"].append_array(out)  # a terminal platform is a dead end; its sockets feed shortcuts
		return []
	return out


static func has_prop(W: World, x: int, z: int, y: int) -> bool:
	var lst: Variant = W.pcol.get(Vector2i(x, z))
	if lst == null:
		return false
	for i in lst:
		if W.props[i][2] == y:
			return true
	return false


@warning_ignore("integer_division")
static func try_loop(W: World, rng, sock: Array, tn: Dictionary, counts: Array, ray: int = -1) -> bool:
	# Cast a ray out of an unused socket. If it meets another piece: build a two-way bridge
	# (EDGE_LOOP) when a stepped span fits, or a one-way drop ledge (EDGE_DROP) when the target is
	# >= 5 HU lower. Returns true if something was built.
	var x: int = sock[0]
	var z: int = sock[1]
	var d: int = sock[2]
	var y: int = sock[3]
	var pid: int = sock[4]
	var wmax: int = sock[5]
	if ray < 0:
		ray = tn["ray_len"]
	var T: Array = W.tiles
	var hit: Variant = null
	for i in range(1, ray + 1):
		var cx: int = x + DX[d] * i
		var cz: int = z + DZ[d] * i
		var lst: Variant = W.col.get(Vector2i(cx, cz))
		if lst == null:
			continue
		var best: int = -1
		for j in lst:
			var dy: int = T[j][2] - y
			if dy >= CLEAR:
				continue  # far above: we pass underneath
			if best < 0 or T[j][2] > T[best][2]:
				best = j  # highest tile at or below our ceiling
		if best >= 0:
			hit = [i, best]
			break
	if hit == null:
		return false
	var i2: int = hit[0]
	var j2: int = hit[1]
	var tt: Array = T[j2]
	var q: int = tt[4]
	if q == pid or tt[3] != 0 or has_prop(W, tt[0], tt[1], tt[2]):
		return false
	var dy2: int = tt[2] - y
	var n: int = i2 - 1
	var lat: int = (d + 1) % 4
	var src: Dictionary = W.pieces[pid]
	if absi(dy2) <= n and n >= 2 and counts[0] < tn["loops_max"]:
		if W.graph_dist(pid, q, tn["loop_min_graph_dist"]) < tn["loop_min_graph_dist"]:
			return false
		var ady: int = dy2 if dy2 >= 0 else -dy2
		var sgn: int = 1 if dy2 > 0 else -1
		var widths: Array = [2, 1] if wmax >= 2 else [1]
		for w in widths:
			var cells: Array = []
			for k in range(n):
				var yy: int = y + 1 + sgn * ((ady * (k + 1)) / n)  # |dy| single-HU steps over n rows
				for o in range(w):
					cells.append([x + DX[d] * (k + 1) + DX[lat] * o, z + DZ[d] * (k + 1) + DZ[lat] * o, yy, 0, 1 if o == 0 else 0])
			if W.fits(cells, [pid, q]):
				var lid: int = W.add_piece(1, "bridge", pid, src["depth"], src["arm"], ROLE_LOOP, y)
				W.pieces[lid]["w"] = w
				for c in cells:
					var ti: int = W.add_tile(c[0], c[1], c[2], c[3], lid)
					if c[4]:
						W.pieces[lid]["center"].append(ti)
				W.add_edge(pid, lid, EDGE_LOOP)
				W.add_edge(lid, q, EDGE_LOOP)
				counts[0] += 1
				return true
		return false
	if -DROP_MAX / 2 <= dy2 and dy2 <= -5 and n >= 1 and counts[1] < tn["drops_max"]:
		if W.graph_dist(pid, q, 3) < 3:
			return false
		var w2: int = 2 if wmax >= 2 else 1
		var cells2: Array = []
		for k in range(n):
			for o in range(w2):
				cells2.append([x + DX[d] * (k + 1) + DX[lat] * o, z + DZ[d] * (k + 1) + DZ[lat] * o, y + 1, 0, 1 if o == 0 else 0])
		if not W.fits(cells2, [pid, q]):
			return false
		var lid2: int = W.add_piece(1, "jut", pid, src["depth"], src["arm"], ROLE_DROP, y)
		W.pieces[lid2]["w"] = w2
		var last: int = -1
		for c in cells2:
			var ti2: int = W.add_tile(c[0], c[1], c[2], c[3], lid2)
			if c[4]:
				W.pieces[lid2]["center"].append(ti2)
				last = ti2
		W.add_edge(pid, lid2, EDGE_TREE)
		var kind: int = EDGE_DROP
		if dy2 >= -7 and rng.chance(50, 100):
			var e: Array = T[last]
			W.pads.append([tt[0], tt[1], tt[2], e[0], e[1], e[2]])
			kind = EDGE_PAD
		W.add_edge(lid2, q, kind)
		counts[1] += 1
		return true
	return false

## round(a / n) for n > 0 without dividing a negative number.
@warning_ignore("integer_division")
static func rdiv(a: int, n: int) -> int:
	if a >= 0:
		return (2 * a + n) / (2 * n)
	return -((-2 * a + n) / (2 * n))


static func jump_offs() -> Array:
	if _jump_offs.is_empty():
		for dx in range(-6, 7):
			for dz in range(-6, 7):
				var d2: int = dx * dx + dz * dz
				if 0 < d2 and d2 <= 36:
					_jump_offs.append([dx, dz, d2])
	return _jump_offs


static func movement(W: World) -> Array:
	# returns [walkable, adj, boundary]. adj[i] = Array of tile indices reachable in one move.
	var T: Array = W.tiles
	var n: int = T.size()
	var col: Dictionary = W.col
	var walkable: Array = []
	walkable.resize(n)
	for i in range(n):
		walkable[i] = true
	for p in W.props:
		var lst0: Variant = col.get(Vector2i(p[0], p[1]))
		if lst0 != null:
			for i in lst0:
				if T[i][2] == p[2]:
					walkable[i] = false
	var adj: Array = []
	adj.resize(n)
	var boundary: Array = []
	boundary.resize(n)
	for i in range(n):
		adj[i] = []
		boundary[i] = false
	for i in range(n):
		if not walkable[i]:
			continue
		var t: Array = T[i]
		for d in range(4):
			var lst: Variant = col.get(Vector2i(t[0] + DX[d], t[1] + DZ[d]))
			var found := false
			if lst != null:
				for j in lst:
					if walkable[j] and absi(T[j][2] - t[2]) <= 1:
						adj[i].append(j)
						found = true
			if not found:
				boundary[i] = true
	var props: Array = W.props
	var pcol: Dictionary = W.pcol
	for i in range(n):
		if not boundary[i]:
			continue
		var a: Array = T[i]
		var ax: int = a[0]
		var az: int = a[1]
		var ay: int = a[2]
		for o in jump_offs():
			var lstj: Variant = col.get(Vector2i(ax + o[0], az + o[1]))
			if lstj == null:
				continue
			for j in lstj:
				if not boundary[j]:
					continue
				var dy: int = T[j][2] - ay
				if dy > JUMP_UP_MAX or dy < -DROP_MAX:
					continue
				var lim: int = JUMP_GAP[0] if dy <= 0 else (JUMP_GAP[1] if dy <= 2 else JUMP_GAP[2])
				if o[2] > (lim + 1) * (lim + 1):
					continue
				if o[2] == 1 and dy >= -1 and dy <= 1:
					continue
				var hi: int = ay if dy <= 0 else ay + dy
				var steps: int = absi(o[0]) if absi(o[0]) > absi(o[1]) else absi(o[1])
				var ok := true
				for s in range(1, steps):
					var cx: int = ax + rdiv(o[0] * s, steps)
					var cz: int = az + rdiv(o[1] * s, steps)
					var l2: Variant = col.get(Vector2i(cx, cz))
					if l2 != null:
						for k in l2:
							var ty: int = T[k][2]
							if ty > hi and ty - SLAB < hi + 8:
								ok = false
					var l3: Variant = pcol.get(Vector2i(cx, cz))
					if l3 != null:
						for k in l3:
							var p2: Array = props[k]
							if p2[2] + p2[3] > hi and p2[2] < hi + 8:
								ok = false
					if not ok:
						break
				if ok:
					adj[i].append(j)
	for p in W.pads:
		var pa: int = find_tile(W, p[0], p[1], p[2])
		var pb: int = find_tile(W, p[3], p[4], p[5])
		if pa >= 0 and pb >= 0:
			adj[pa].append(pb)
	return [walkable, adj, boundary]


static func find_tile(W: World, x: int, z: int, y: int) -> int:
	var lst: Variant = W.col.get(Vector2i(x, z))
	if lst != null:
		for i in lst:
			if W.tiles[i][2] == y:
				return i
	return -1


static func bfs(adj: Array, start: int) -> Array:
	var seen: Array = []
	seen.resize(adj.size())
	for i in range(seen.size()):
		seen[i] = false
	seen[start] = true
	var q: Array = [start]
	var h: int = 0
	while h < q.size():
		var c: int = q[h]
		h += 1
		for nb in adj[c]:
			if not seen[nb]:
				seen[nb] = true
				q.append(nb)
	return seen


# ---- gifts ---------------------------------------------------------------------


static func _gift_far(T: Array, taken: Dictionary, i: int, sp: int) -> bool:
	var t: Array = T[i]
	for ox in range(-sp + 1, sp):
		for oz in range(-sp + 1, sp):
			if taken.has(Vector2i(t[0] + ox, t[1] + oz)):
				return false
	return true


static func _gift_take(T: Array, chosen: Array, taken: Dictionary, pid: int, i: int) -> void:
	chosen[pid].append(i)
	taken[Vector2i(T[i][0], T[i][1])] = 1


@warning_ignore("integer_division")
static func place_gifts(W: World, rng, tn: Dictionary, rt: Array) -> Variant:
	# rt[i] = tile i is round-trip reachable. Returns Array of slots [tile_index, pid] or null.
	var T: Array = W.tiles
	var S: int = tn["slots"]
	var padset: Dictionary = {}
	for p in W.pads:
		padset[Vector3i(p[0], p[1], p[2])] = 1
	var cands: Array = []
	cands.resize(W.pieces.size())
	for i in range(cands.size()):
		cands[i] = []
	for i in range(T.size()):
		var t: Array = T[i]
		if not rt[i] or t[3] != 0:
			continue
		if t[4] == 0 and t[2] == 1:
			continue  # beacon dais stays clean
		if padset.has(Vector3i(t[0], t[1], t[2])):
			continue
		cands[t[4]].append(i)
	var weights: Array = []
	var tot: int = 0
	for p in W.pieces:
		var ncnt: int = cands[p["id"]].size()
		var role: int = p["role"]
		var w: int
		if role == ROLE_HUB:
			w = ncnt / 2
		elif role == ROLE_DEADEND:
			w = 5 * ncnt
		elif role == ROLE_LOOP or role == ROLE_DROP:
			w = 3 * ncnt
		else:
			w = 2 * ncnt
		if role != ROLE_HUB:
			w = w * (4 + (p["depth"] if p["depth"] < 8 else 8))
		weights.append(w)
		tot += w
	if tot == 0:
		return null
	var quota: Array = []
	var rem: Array = []
	var used: int = 0
	for i in range(weights.size()):
		var qi: int = S * weights[i] / tot
		quota.append(qi)
		rem.append([-(S * weights[i] % tot), i])
		used += qi
	# Python rem.sort() on [a, i] pairs: by a then i
	rem.sort_custom(func(p, q2): return p[0] < q2[0] or (p[0] == q2[0] and p[1] < q2[1]))
	var k: int = 0
	while used < S and k < rem.size():
		quota[rem[k][1]] += 1
		used += 1
		k += 1
	var chosen: Array = []
	chosen.resize(W.pieces.size())
	for i in range(chosen.size()):
		chosen[i] = []
	var taken: Dictionary = {}
	for p in W.pieces:
		var pid: int = p["id"]
		var q: int = quota[pid]
		var c: Array = cands[pid]
		if q == 0 or c.is_empty():
			continue
		if p["kind"] == 1:
			var cs: Dictionary = {}
			for i in c:
				cs[i] = 1
			var line: Array = []
			for i in p["center"]:
				if cs.has(i):
					line.append(i)
			var nline: int = line.size()
			if nline > 0:
				var half: int = (nline + 1) / 2
				var qq: int = q if q < half else half
				for j in range(qq):
					var idx: int = (j * nline + nline / 2) / qq if qq > 0 else 0
					var i2: int = line[idx]
					if _gift_far(T, taken, i2, 2):
						_gift_take(T, chosen, taken, pid, i2)
		var order: Array = c.duplicate()
		rng.shuffle(order)
		for i in order:
			if chosen[pid].size() >= q:
				break
			if _gift_far(T, taken, i, 2):
				_gift_take(T, chosen, taken, pid, i)
		p["_order"] = order
	var total: int = 0
	for c in chosen:
		total += c.size()
	for sp in [2, 1]:
		var progress := true
		while total < S and progress:
			progress = false
			for p in W.pieces:
				if total >= S:
					break
				var order: Variant = p.get("_order")
				if order == null:
					order = cands[p["id"]].duplicate()
					rng.shuffle(order)
					p["_order"] = order
				for i in order:
					if _gift_far(T, taken, i, sp):
						_gift_take(T, chosen, taken, p["id"], i)
						total += 1
						progress = true
						break
	for p in W.pieces:
		p.erase("_order")
	if total != S:
		return null
	var slots: Array = []
	for pid in range(chosen.size()):
		var lst: Array = chosen[pid].duplicate()
		lst.sort()
		for i in lst:
			slots.append([i, pid])
	return slots


# ---- tripmine eligibility (TERRAIN_SPEC section 6.8) ---------------------------
# Contact = the player's centre within 0.9 u horizontally of the mine's tile centre, at ANY height
# (jumping over a mine does not avoid it). Coordinates are scaled by 10 so the whole test is
# integer-only: 0.9 -> 9, 0.9^2 -> 81.
const MINE_SCALE := 10
const MINE_R2 := 81


static func seg_hits_mine(ax: int, az: int, bx: int, bz: int, mx: int, mz: int) -> bool:
	# True iff the segment between tile centres (ax,az)-(bx,bz) passes within 0.9 u of (mx,mz).
	var px: int = MINE_SCALE * ax + 5
	var pz: int = MINE_SCALE * az + 5
	var qx: int = MINE_SCALE * bx + 5
	var qz: int = MINE_SCALE * bz + 5
	var tx: int = MINE_SCALE * mx + 5
	var tz: int = MINE_SCALE * mz + 5
	var vx: int = qx - px
	var vz: int = qz - pz
	var wx: int = tx - px
	var wz: int = tz - pz
	var len2: int = vx * vx + vz * vz
	var dot: int = wx * vx + wz * vz
	if dot <= 0:
		return wx * wx + wz * wz <= MINE_R2
	if dot >= len2:
		var ux: int = tx - qx
		var uz: int = tz - qz
		return ux * ux + uz * uz <= MINE_R2
	return (wx * wx + wz * wz) * len2 - dot * dot <= MINE_R2 * len2


static func bfs_bypass(nb: Array, start: int, blocked: Array, blk: Dictionary) -> Array:
	# BFS from `start` skipping every tile flagged in `blocked` and every edge listed in `blk`
	# (source tile -> Dictionary of blocked targets).
	var n: int = nb.size()
	var seen: Array = []
	seen.resize(n)
	for i in range(n):
		seen[i] = false
	seen[start] = true
	var q: Array = [start]
	var h: int = 0
	while h < q.size():
		var c: int = q[h]
		h += 1
		var b: Variant = blk.get(c)
		if b == null:
			for j in nb[c]:
				if not seen[j] and not blocked[j]:
					seen[j] = true
					q.append(j)
		else:
			for j in nb[c]:
				if not seen[j] and not blocked[j] and not b.has(j):
					seen[j] = true
					q.append(j)
	return seen


static func mine_ctx(W, adj: Array, rt: Array, slots: Array) -> Dictionary:
	# The tripmine eligibility rule of TERRAIN_SPEC section 6.8, computed once per level.
	var T: Array = W.tiles
	var n: int = T.size()
	var ctx: Dictionary = {}
	ctx["T"] = T
	ctx["n"] = n
	ctx["rt"] = rt
	var rt_count := 0
	for i in range(n):
		if rt[i]:
			rt_count += 1
	ctx["rt_count"] = rt_count
	ctx["beacon"] = find_tile(W, 0, 0, 1)
	ctx["nb"] = adj
	var nb_rev: Array = []
	nb_rev.resize(n)
	for i in range(n):
		nb_rev[i] = []
	for i in range(n):
		for j in adj[i]:
			nb_rev[j].append(i)
	ctx["nb_rev"] = nb_rev
	var slot_tiles: Array = []
	for s in slots:
		slot_tiles.append(s[0])
	ctx["slot_tiles"] = slot_tiles
	# column index: (x, z) -> tile indices. The trigger cylinder is unbounded in height, so a mine
	# also removes every other tile in its own column.
	var col: Dictionary = {}
	for i in range(n):
		var ckey := Vector2i(T[i][0], T[i][1])
		var clst: Variant = col.get(ckey)
		if clst == null:
			col[ckey] = [i]
		else:
			clst.append(i)
	ctx["col"] = col
	# every edge, walk included: the cylinder test is applied to all of them, never assumed
	var edges: Array = []
	for i in range(n):
		for j in adj[i]:
			edges.append([i, j])
	ctx["edges"] = edges
	# cell -> edge ids whose segment passes through that cell
	var idx: Dictionary = {}
	for eid in range(edges.size()):
		var i3: int = edges[eid][0]
		var j3: int = edges[eid][1]
		var ax: int = T[i3][0]
		var az: int = T[i3][1]
		var dx3: int = T[j3][0] - ax
		var dz3: int = T[j3][1] - az
		var adx: int = dx3 if dx3 >= 0 else -dx3
		var adz: int = dz3 if dz3 >= 0 else -dz3
		var steps: int = adx if adx > adz else adz
		var den: int = 2 * steps if steps > 0 else 1
		var px: int = -1073741824
		var pz: int = -1073741824
		for s in range(0, 2 * steps + 1):
			var cx: int = ax + rdiv(dx3 * s, den)
			var cz: int = az + rdiv(dz3 * s, den)
			if cx == px and cz == pz:
				continue
			px = cx
			pz = cz
			var key := Vector2i(cx, cz)
			var lst: Variant = idx.get(key)
			if lst == null:
				idx[key] = [eid]
			else:
				lst.append(eid)
	ctx["idx"] = idx
	ctx["cross"] = {}
	ctx["elig"] = {}
	return ctx


static func mine_cross_edges(ctx: Dictionary, si: int) -> Array:
	var cache: Dictionary = ctx["cross"]
	var got: Variant = cache.get(si)
	if got != null:
		return got
	var T: Array = ctx["T"]
	var edges: Array = ctx["edges"]
	var idx: Dictionary = ctx["idx"]
	var slot_tiles: Array = ctx["slot_tiles"]
	var m: int = slot_tiles[si]
	var mx: int = T[m][0]
	var mz: int = T[m][1]
	var seen: Dictionary = {}
	var out: Array = []
	for ox in [-1, 0, 1]:
		for oz in [-1, 0, 1]:
			var cell: Variant = idx.get(Vector2i(mx + ox, mz + oz))
			if cell == null:
				continue
			for eid in cell:
				if seen.has(eid):
					continue
				seen[eid] = true
				var i: int = edges[eid][0]
				var j: int = edges[eid][1]
				if seg_hits_mine(T[i][0], T[i][1], T[j][0], T[j][1], mx, mz):
					out.append(eid)
	cache[si] = out
	return out


static func mine_block(ctx: Dictionary, mines: Array) -> Array:
	# [blocked, forward blocked-edge map, reverse blocked-edge map] for a mine set. A tile is blocked
	# when its centre lies inside any mine's trigger cylinder.
	var n: int = ctx["n"]
	var T: Array = ctx["T"]
	var slot_tiles: Array = ctx["slot_tiles"]
	var edges: Array = ctx["edges"]
	var col: Dictionary = ctx["col"]
	var blocked: Array = []
	blocked.resize(n)
	for i in range(n):
		blocked[i] = false
	var blk_f: Dictionary = {}
	var blk_b: Dictionary = {}
	for si in mines:
		var m: int = slot_tiles[si]
		var mx: int = T[m][0]
		var mz: int = T[m][1]
		for ox in [-1, 0, 1]:
			for oz in [-1, 0, 1]:
				var clst: Variant = col.get(Vector2i(mx + ox, mz + oz))
				if clst == null:
					continue
				for t in clst:
					var ddx: int = MINE_SCALE * (T[t][0] - mx)
					var ddz: int = MINE_SCALE * (T[t][1] - mz)
					if ddx * ddx + ddz * ddz <= MINE_R2:
						blocked[t] = true
		for eid in mine_cross_edges(ctx, si):
			var i: int = edges[eid][0]
			var j: int = edges[eid][1]
			var d: Variant = blk_f.get(i)
			if d == null:
				blk_f[i] = {j: true}
			else:
				d[j] = true
			var d2: Variant = blk_b.get(j)
			if d2 == null:
				blk_b[j] = {i: true}
			else:
				d2[i] = true
	return [blocked, blk_f, blk_b]


static func mine_keeps_rt(ctx: Dictionary, mines: Array) -> bool:
	var blk: Array = mine_block(ctx, mines)
	var blocked: Array = blk[0]
	var blk_f: Dictionary = blk[1]
	var blk_b: Dictionary = blk[2]
	var rt: Array = ctx["rt"]
	var n: int = ctx["n"]
	var slot_tiles: Array = ctx["slot_tiles"]
	# the beacon and every real gift slot must survive the cylinder: a gift inside it is
	# uncollectable, so a mine may never create one
	if blocked[ctx["beacon"]]:
		return false
	var mine_set: Dictionary = {}
	for si in mines:
		mine_set[si] = true
	for si in range(slot_tiles.size()):
		if not mine_set.has(si) and blocked[slot_tiles[si]]:
			return false
	var need := 0
	for t in range(n):
		if rt[t] and not blocked[t]:
			need += 1
	var fwd: Array = bfs_bypass(ctx["nb"], ctx["beacon"], blocked, blk_f)
	var cnt := 0
	for t in range(n):
		if rt[t] and not blocked[t] and fwd[t]:
			cnt += 1
	if cnt != need:
		return false
	var back: Array = bfs_bypass(ctx["nb_rev"], ctx["beacon"], blocked, blk_b)
	cnt = 0
	for t in range(n):
		if rt[t] and not blocked[t] and back[t]:
			cnt += 1
	return cnt == need


static func mine_eligible(ctx: Dictionary, si: int) -> bool:
	var cache: Dictionary = ctx["elig"]
	var got: Variant = cache.get(si)
	if got != null:
		return bool(got)
	var v: bool = mine_keeps_rt(ctx, [si])
	cache[si] = v
	return v


static func mine_joint_ok(ctx: Dictionary, mines: Array) -> bool:
	return mine_keeps_rt(ctx, mines)


@warning_ignore("integer_division")
static func roll_mines(rng, level: int, n: int, extra: int, W, adj: Array, rt: Array,
		slots: Array) -> Array:
	# returns occ list (0 gift, 1 tripmine). Per-slot chance (15+min(L,25))/400 from level 5,
	# applied only to slots with a walkable bypass (TERRAIN_SPEC section 6.8.5). Total mines
	# hard-capped at n // 5. Extra (curse) mines are flat adds under the same cap.
	var occ: Array = []
	occ.resize(n)
	for i in range(n):
		occ[i] = 0
	var num: int = mine_chance_num(level)
	var cap: int = n / 5
	var count := 0
	var ctx: Dictionary = {}
	var have_ctx := false
	var mines: Array = []
	for i in range(n):
		var r: int = rng.urange(400)  # always drawn, so the stream does not depend on level
		if r < num:
			if not have_ctx:
				ctx = mine_ctx(W, adj, rt, slots)
				have_ctx = true
			if mine_eligible(ctx, i) and mine_joint_ok(ctx, mines + [i]):
				occ[i] = 1
				mines.append(i)
				count += 1
	# cap: un-set from the highest slot id
	while count > cap:
		var i2: int = mines.pop_back()
		occ[i2] = 0
		count -= 1
	# extra (curse) mines: one draw per extra mine, indexing the ascending list of eligible free
	# slots. A slot that breaks the joint rule is banned for the rest of the phase: banning can only
	# place fewer mines, never an invalid one.
	var e := 0
	var banned: Dictionary = {}
	while e < extra and count < cap:
		if not have_ctx:
			ctx = mine_ctx(W, adj, rt, slots)
			have_ctx = true
		var free: Array = []
		for i in range(n):
			if occ[i] == 0 and not banned.has(i) and mine_eligible(ctx, i):
				free.append(i)
		if free.is_empty():
			break  # no eligible slot left: place fewer, never break the rule
		var k: int = free[rng.urange(free.size())]
		if mine_joint_ok(ctx, mines + [k]):
			occ[k] = 1
			mines.append(k)
			count += 1
		else:
			banned[k] = true
		e += 1
	# safety net: the joint rule must hold for the final set
	while count > 0 and not mine_joint_ok(ctx, mines):
		var mx: int = -1
		for i in mines:
			if i > mx:
				mx = i
		mines.erase(mx)
		occ[mx] = 0
		count -= 1
	return occ


# ---- top level -----------------------------------------------------------------


@warning_ignore("integer_division")
static func build(seed: int, level: int, players: int, extra_mines: int, attempt: int) -> Variant:
	var tn: Dictionary = tuning(level, players)
	var base: int = VoidRngScript.mix(VoidRngScript.mix(VoidRngScript.mix(seed & M32, level), GEN_VERSION), attempt)
	var W: World = World.new()
	var hub_res: Array = build_hub(W)
	var rp = VoidRngScript.new(VoidRngScript.mix(base, ST_PLAN))
	var n_arms: int = rp.ri(tn["arms_min"], tn["arms_max"])
	var order: Array = [0, 1, 2, 3]
	rp.shuffle(order)
	var tw: Array = []
	for name in TRAITS:
		var wt: int = TRAIT_W[name]
		if name == "hop":
			wt += tn["t"] / 2
		if name == "thin":
			wt += tn["t"] / 3
		tw.append(wt)
	var arms: Array = []
	var spare: Array = []
	var used_traits: Dictionary = {}
	var drifts: Array = [-2, 2, -1, 1]
	rp.shuffle(drifts)
	for k in range(4):
		var hs: Array = hub_res[1][order[k]]
		if k < n_arms:
			var w2: Array = []
			for i2 in range(TRAITS.size()):
				w2.append(tw[i2] / 4 if used_traits.has(TRAITS[i2]) else tw[i2])
			var w2p: Array = []
			for ww in w2:
				w2p.append(ww + 1)
			var trait_name: String = rp.wpick(TRAITS, w2p)
			used_traits[trait_name] = 1
			var share: int = rp.ri(1, 4)
			var deep: int = 25 + 15 * rp.urange(5)
			var dr: int = drifts[k]
			if (dr > 0) != (k % 2 == 0):
				dr = -dr
			arms.append({"trait": trait_name, "open": [hs], "quota": 0, "rooms": 0,
				"share": share, "deep": deep, "drift": dr})
		else:
			spare.append(hs)
	# platform target (TERRAIN_SPEC section 6.2): ri(plat_max - 1, plat_max)
	var pm: int = tn["plat_max"]
	var target: int = rp.ri(pm - 1, pm)
	# asymmetric arms: every arm gets 1 platform, the rest is dealt by share (major and minor arms)
	var tot_share: int = 0
	for A in arms:
		A["quota"] = 1
		tot_share += A["share"]
	var left: int = target - n_arms
	var given: int = 0
	for A in arms:
		var q: int = left * A["share"] / tot_share
		A["quota"] += q
		given += q
	var k3: int = 0
	while given < left:
		arms[k3 % n_arms]["quota"] += 1
		given += 1
		k3 += 1
	var state: Dictionary = {"placed": 0, "target": target, "since": 0, "dead": []}
	var arch_count: Dictionary = {}
	var guard: int = 0
	while state["placed"] < target and guard < pm * 60:
		guard += 1
		var best: int = -1
		for a in range(n_arms):
			var A: Dictionary = arms[a]
			if A["open"].is_empty():
				continue
			if best < 0 or A["quota"] - A["rooms"] > arms[best]["quota"] - arms[best]["rooms"]:
				best = a
		if best < 0:
			break
		var Abest: Dictionary = arms[best]
		var rg = VoidRngScript.new(VoidRngScript.mix(VoidRngScript.mix(base, ST_GROW), guard))
		var op: Array = Abest["open"]
		var si: int
		if rg.chance(Abest["deep"], 100):
			# the LAST deepest socket wins (>=)
			si = 0
			for k2 in range(op.size()):
				if W.pieces[op[k2][4]]["depth"] >= W.pieces[op[si][4]]["depth"]:
					si = k2
			# turn bias: a socket that continues straight through its room yields to a sibling
			# socket that turns, so arms wind instead of running out as sticks
			if op[si][6] == 1 and rg.chance(tn["turn_pct"], 100):
				for k4 in range(op.size()):
					if op[k4][4] == op[si][4] and op[k4][6] == 0:
						si = k4
		else:
			si = rg.urange(op.size())
		var sock: Array = op[si]
		var res: Variant = false
		var before: int = state["placed"]
		for tr in range(tn["grow_tries"]):
			res = try_grow(W, rg, sock, best, Abest["trait"], tn, arch_count, state, Abest["drift"])
			if typeof(res) != TYPE_BOOL:
				break
		op.pop_at(si)
		if typeof(res) == TYPE_BOOL:
			state["dead"].append(sock)
		else:
			Abest["rooms"] += state["placed"] - before
			for s2 in res:
				op.append(s2)
	if state["placed"] < target:
		return null  # the level must place its platform target (TERRAIN_SPEC section 6.0)
	# leaf platforms are dead ends
	var child: Dictionary = {}
	for p in W.pieces:
		if p["parent"] >= 0:
			child[p["parent"]] = 1
	for p in W.pieces:
		if p["kind"] == 0 and p["role"] == ROLE_ROOM and not child.has(p["id"]):
			p["role"] = ROLE_DEADEND
	# loop closure
	var rl = VoidRngScript.new(VoidRngScript.mix(base, ST_LOOP))
	var opens: Array = spare.duplicate()
	opens.append_array(state["dead"])
	for A in arms:
		for s in A["open"]:
			opens.append(s)
	rl.shuffle(opens)
	var counts: Array = [0, 0]
	for s in opens:
		if counts[0] >= tn["loops_max"] and counts[1] >= tn["drops_max"]:
			break
		try_loop(W, rl, s, tn, counts)
	if counts[0] + counts[1] == 0:
		# second pass with a longer ray: a small level has few sockets and a short ray misses
		for s in opens:
			try_loop(W, rl, s, tn, counts, tn["ray_len"] * 2)
			if counts[0] + counts[1]:
				break
	if counts[0] + counts[1] == 0 and attempt < MAX_ATTEMPTS - 1:
		return null  # every level must contain at least one shortcut (TERRAIN_SPEC H14)
	var n_dead: int = 0
	for pc in W.pieces:
		if pc["role"] == ROLE_DEADEND:
			n_dead += 1
	if n_dead < 2 and attempt < MAX_ATTEMPTS - 1:
		return null  # a level needs at least two dead ends (TERRAIN_SPEC H12)
	# elevation variance floor (TERRAIN_SPEC section 1A rule 3): paths gain and lose height
	var ys: Array = []
	for t in W.tiles:
		if t[4] != 0:
			ys.append(t[2])
	if not ys.is_empty():
		var total: int = 0
		for yv in ys:
			total += yv
		var mean: float = float(total) / float(ys.size())
		var var_sum: float = 0.0
		for yv in ys:
			var dv: float = float(yv) - mean
			var_sum += dv * dv
		if sqrt(var_sum / float(ys.size())) < float(elev_var_floor(level)):
			return null
	# path share floor (TERRAIN_SPEC section 1A rule 2): walkways carry most walkable tiles
	var wt2: int = 0
	var pt2: int = 0
	for t in W.tiles:
		if t[4] == 0:
			continue
		if W.pieces[t[4]]["kind"] == 1:
			wt2 += 1
		else:
			pt2 += 1
	if wt2 < pt2:
		return null
	# reachability
	var mv: Array = movement(W)
	var walkable: Array = mv[0]
	var adj: Array = mv[1]
	var boundary: Array = mv[2]
	var start: int = find_tile(W, 0, 0, 1)
	var fwd: Array = bfs(adj, start)
	var radj: Array = []
	radj.resize(adj.size())
	for i in range(radj.size()):
		radj[i] = []
	for i in range(adj.size()):
		for j in adj[i]:
			radj[j].append(i)
	var back: Array = bfs(radj, start)
	var rt: Array = []
	for i in range(fwd.size()):
		rt.append(fwd[i] and back[i])
	for i in range(fwd.size()):
		if fwd[i] and not back[i]:
			return null  # a soft-lock tile exists: reject the attempt (D-014)
	var rgift = VoidRngScript.new(VoidRngScript.mix(base, ST_GIFT))
	var slots: Variant = place_gifts(W, rgift, tn, rt)
	if slots == null:
		return null
	var occ: Array = roll_mines(VoidRngScript.new(VoidRngScript.mix(base, ST_MINE)), level, slots.size(), extra_mines, W, adj, rt, slots)
	return [W, slots, occ, boundary, arms, counts]


static func generate(seed: int, level: int, players: int = 1, extra_mines: int = 0) -> Dictionary:
	# THE entry point. Pure function of its four integer arguments.
	for attempt in range(MAX_ATTEMPTS):
		var r: Variant = build(seed, level, players, extra_mines, attempt)
		if r != null:
			return pack(seed, level, players, extra_mines, attempt, r)
	push_error("voidgen: no valid level for seed=%d level=%d" % [seed, level])
	return {}


@warning_ignore("integer_division")
static func pack(seed: int, level: int, players: int, extra_mines: int, attempt: int, r: Array) -> Dictionary:
	var W: World = r[0]
	var slots: Array = r[1]
	var occ: Array = r[2]
	var boundary: Array = r[3]
	var arms: Array = r[4]
	var T: Array = W.tiles
	var bb: Dictionary = {}
	var cnt: Dictionary = {}
	for t in T:
		var key: int = t[4]
		var b: Variant = bb.get(key)
		if b == null:
			bb[key] = [t[0], t[1], t[0], t[1]]
			cnt[key] = 1
		else:
			if t[0] < b[0]:
				b[0] = t[0]
			if t[1] < b[1]:
				b[1] = t[1]
			if t[0] > b[2]:
				b[2] = t[0]
			if t[1] > b[3]:
				b[3] = t[1]
			cnt[key] += 1
	var pieces: Array = []
	for p in W.pieces:
		var pb: Array = bb[p["id"]]
		pieces.append({
			"id": p["id"], "kind": p["kind"], "arch": p["arch"], "parent": p["parent"],
			"depth": p["depth"], "arm": p["arm"], "role": p["role"], "y": p["y"],
			"bbox": pb, "tiles": cnt[p["id"]], "jumps": p["jumps"], "w": p["w"],
		})
	var gifts: Array = []
	for k in range(slots.size()):
		var i: int = slots[k][0]
		var pid: int = slots[k][1]
		var t: Array = T[i]
		var role: int = W.pieces[pid]["role"]
		var tier: int = 2 if role == ROLE_DEADEND else (1 if (W.pieces[pid]["kind"] == 1 or boundary[i]) else 0)
		gifts.append({"id": k, "x": t[0], "z": t[1], "y": t[2], "piece": pid, "tier": tier, "occ": occ[k]})
	var tiles_out: Array = []
	for t in T:
		tiles_out.append(t.duplicate())
	var props_out: Array = []
	for p in W.props:
		props_out.append(p.duplicate())
	var edges_out: Array = []
	for e in W.edges:
		edges_out.append(e.duplicate())
	var anchors_out: Array = []
	for a in W.anchors:
		anchors_out.append(a.duplicate())
	var pads_out: Array = []
	for p in W.pads:
		pads_out.append(p.duplicate())
	var spawns_out: Array = []
	for s in SPAWNS:
		spawns_out.append([s[0], s[1], 1])
	return {
		"gen_version": GEN_VERSION,
		"seed": seed, "level": level, "players": players, "extra_mines": extra_mines,
		"attempt": attempt,
		"beacon": [0, 0, 1],
		"spawns": spawns_out,
		"arms": arms_by_trait(arms),
		"pieces": pieces,
		"tiles": tiles_out,
		"props": props_out,
		"edges": edges_out,
		"gifts": gifts,
		"anchors": anchors_out,
		"pads": pads_out,
	}


static func arms_by_trait(arms: Array) -> Array:
	var out: Array = []
	for a in arms:
		out.append(a["trait"])
	return out


static func to_text(L: Dictionary) -> String:
	# canonical text. SHA-256 of this (UTF-8, LF) is the level hash.
	var o: Array = []
	o.append("VOIDGEN %d" % L["gen_version"])
	o.append("IN %d %d %d %d" % [L["seed"], L["level"], L["players"], L["extra_mines"]])
	o.append("ATTEMPT %d" % L["attempt"])
	o.append("BEACON %d %d %d" % [L["beacon"][0], L["beacon"][1], L["beacon"][2]])
	for s in L["spawns"]:
		o.append("SPAWN %d %d %d" % [s[0], s[1], s[2]])
	var arm_names: PackedStringArray = PackedStringArray()
	for a in L["arms"]:
		arm_names.append(str(a))
	o.append("ARMS " + " ".join(arm_names))
	for p in L["pieces"]:
		o.append("P %d %d %s %d %d %d %d %d %d %d %d %d %d %d %d" % [
			p["id"], p["kind"], p["arch"], p["parent"], p["depth"], p["arm"], p["role"], p["y"],
			p["bbox"][0], p["bbox"][1], p["bbox"][2], p["bbox"][3], p["tiles"], p["jumps"], p["w"]])
	for t in L["tiles"]:
		o.append("T %d %d %d %d %d" % [t[0], t[1], t[2], t[3], t[4]])
	for p in L["props"]:
		o.append("O %d %d %d %d %d %d" % [p[0], p[1], p[2], p[3], p[4], p[5]])
	for e in L["edges"]:
		o.append("E %d %d %d" % [e[0], e[1], e[2]])
	for g in L["gifts"]:
		o.append("G %d %d %d %d %d %d %d" % [g["id"], g["x"], g["z"], g["y"], g["piece"], g["tier"], g["occ"]])
	for a in L["anchors"]:
		o.append("A %d %d %d %d %d" % [a[0], a[1], a[2], a[3], a[4]])
	for p in L["pads"]:
		o.append("X %d %d %d %d %d %d" % [p[0], p[1], p[2], p[3], p[4], p[5]])
	o.append("END")
	return "\n".join(PackedStringArray(o)) + "\n"


static func level_hash(L: Dictionary) -> String:
	return to_text(L).sha256_text()
