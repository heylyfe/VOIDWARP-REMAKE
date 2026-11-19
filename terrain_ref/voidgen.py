"""VOIDWRAP RUN terrain generator - Python reference (the oracle).

Pure function: generate(seed, level, players, extra_mines) -> dict.
Integer-only math, own RNG, no globals mutated, stdlib only.
Spec: TERRAIN_SPEC.md. Any behavior change here MUST bump GEN_VERSION and regenerate goldens.

RULES (portability, see TERRAIN_SPEC section 3):
  * no floats anywhere
  * never divide or modulo a negative number (Python floors, GDScript truncates)
  * never iterate a set; dicts are only iterated in insertion order
"""
import hashlib
import json
import sys

GEN_VERSION = 4
M32 = 0xFFFFFFFF

# ---- units ---------------------------------------------------------------
# cell = 1 u x 1 u horizontally. HU = 0.5 u vertically. All ints.
MAX_ATTEMPTS = 24   # deterministic re-rolls; the last attempt waives the shortcut rule
CLEAR = 12          # min |dy| between two tiles in one column, and between adjacent tiles of unrelated pieces
SLAB = 2            # collision thickness of every tile slab, HU
Y_MIN, Y_MAX = -48, 72
DX = (1, 0, -1, 0)  # dir 0:+x 1:+z 2:-x 3:-z
DZ = (0, 1, 0, -1)
N8 = ((1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1))

# validator / reachability envelope (derived in TERRAIN_SPEC section 5)
JUMP_UP_MAX = 4       # HU
JUMP_GAP = (5, 4, 3)  # max edge-to-edge gap in cells for dy<=0, dy<=2, dy<=4
DROP_MAX = 60         # HU
# authoring envelope (what the generator is allowed to BUILD on mandatory routes): one cell tighter
AUTH_GAP = (4, 3, 2)

ROLE_HUB, ROLE_ROOM, ROLE_DEADEND, ROLE_LINK, ROLE_LOOP, ROLE_DROP = 0, 1, 2, 3, 4, 5
EDGE_TREE, EDGE_LOOP, EDGE_DROP, EDGE_PAD = 0, 1, 2, 3

# GEN_VERSION 2 vocabulary (TERRAIN_SPEC section 1A): walkways are stepped, platforms are small
# (bbox <= 7x7, <= 40 tiles). The hub is the only large area.
# GEN_VERSION 4 (owner override, out/decisions/J1.md): every walkway is exactly WALK_W = 3 cells
# wide, every walkable piece is at least 3 cells wide, and every gift slot sits on a centre lane.
WALK_W = 3
WALKS = ("step", "stair", "ledge", "flat", "ramp")
PLATS = ("pad", "disc", "cross", "ell", "terrace", "nook", "spire", "bastion")
TRAITS = ("grand", "ascent", "descent", "hop", "maze", "thin")

# stream ids (each phase has its own RNG sub-stream, D-017)
ST_PLAN, ST_GROW, ST_LOOP, ST_GIFT, ST_MINE = 1, 2, 3, 4, 5


# ---- tuning knobs (TERRAIN_SPEC section 9). Every number the generator uses lives here. ----
def plat_max(level):
    """Platform ceiling (TERRAIN_SPEC section 9): min(12, 4 + level // 3)."""
    n = 4 + level // 3
    return n if n < 12 else 12


def elev_var_floor(level):
    """Elevation-variance floor (TERRAIN_SPEC section 1A rule 3): 3 HU at L1, 6 HU at L10+."""
    t = level if level < 10 else 10
    return 3 + 3 * (t - 1) // 9


def tuning(level, players):
    t = level if level < 30 else 30
    return {
        "t": t,
        "plat_max": plat_max(level),
        "arms_min": 2,
        "arms_max": 3 if level < 4 else 4,
        "radius": 70 + 2 * t,
        "slots": slot_target(level, players),
        "loops_max": 2 + t // 6,
        "drops_max": 2 + t // 8,
        "ray_len": 20,
        "loop_min_graph_dist": 4,
        "grow_tries": 5,
        "turn_pct": 75,
        "walk_w": {
            "step": 20, "stair": 6 + t // 3, "ledge": 5,
            "flat": max(1, 4 - t // 8), "ramp": max(2, 5 - t // 6),
        },
        "plat_w": {
            "pad": 10, "disc": 7, "cross": 10, "ell": 8, "terrace": 8,
            "nook": 5, "spire": 3 + t // 5, "bastion": 5,
        },
        "plat_pct": 40,
        "term_pct": 35,
        "jump_min_depth": max(1, 10 - t),
    }


def slot_target(level, players):
    base = min(160, 40 + 4 * (level - 1))
    return base * (1 + players) // 2


def mine_chance_num(level):
    """per-slot tripmine chance = num/400. 0 below level 5, 1/20 at 5, 1/10 at 25, capped."""
    if level < 5:
        return 0
    return 15 + (level if level < 25 else 25)


# trait multipliers, quarter units (4 = x1)
TRAIT_LINK = {
    "grand":   {"step": 8, "stair": 2, "ledge": 2, "flat": 8, "ramp": 4},
    "ascent":  {"step": 8, "stair": 8, "ledge": 4, "flat": 3, "ramp": 4},
    "descent": {"step": 8, "stair": 8, "ledge": 4, "flat": 3, "ramp": 4},
    "hop":     {"step": 4, "stair": 10, "ledge": 8, "flat": 2, "ramp": 2},
    "maze":    {"step": 6, "stair": 4, "ledge": 4, "flat": 6, "ramp": 4},
    "thin":    {"step": 10, "stair": 4, "ledge": 5, "flat": 3, "ramp": 4},
}
TRAIT_ROOM = {
    "grand":   {"pad": 8, "cross": 8, "disc": 8, "terrace": 4},
    "ascent":  {"terrace": 12, "spire": 12, "bastion": 8},
    "descent": {"terrace": 12, "disc": 6, "pad": 6},
    "hop":     {"spire": 20, "cross": 8, "disc": 6},
    "maze":    {"cross": 12, "ell": 12, "pad": 6},
    "thin":    {"nook": 16, "ell": 8, "bastion": 8},
}
TRAIT_UP_PCT = {"grand": 50, "ascent": 85, "descent": 15, "hop": 55, "maze": 50, "thin": 50}
TRAIT_W = {"grand": 10, "ascent": 8, "descent": 8, "hop": 4, "maze": 8, "thin": 3}  # + level-scaled below


# ---- RNG -------------------------------------------------------------------
def mul32(a, b):
    return ((a & 0xFFFF) * b + ((((a >> 16) * b) & 0xFFFF) << 16)) & M32


def fmix(x):
    x ^= x >> 16
    x = mul32(x, 0x85EBCA6B)
    x ^= x >> 13
    x = mul32(x, 0xC2B2AE35)
    x ^= x >> 16
    return x


def mix(a, b):
    return fmix((a ^ mul32((b + 0x9E3779B9) & M32, 0x01000193)) & M32)


class Rng:
    def __init__(self, seed):
        self.s = seed & M32

    def u32(self):
        self.s = (self.s + 0x6D2B79F5) & M32
        z = self.s
        z = mul32(z ^ (z >> 15), z | 1)
        z ^= (z + mul32(z ^ (z >> 7), z | 61)) & M32
        return (z ^ (z >> 14)) & M32

    def range(self, n):
        """uniform int in [0, n). n must be 1..2^20."""
        return (self.u32() * n) >> 32

    def ri(self, a, b):
        """uniform int in [a, b] inclusive. If b < a returns a."""
        if b <= a:
            return a
        return a + self.range(b - a + 1)

    def chance(self, num, den):
        return self.range(den) < num

    def pick(self, seq):
        return seq[self.range(len(seq))]

    def wpick(self, names, weights):
        """names: sequence, weights: parallel ints >= 0. Total must be > 0."""
        tot = 0
        for w in weights:
            tot += w
        r = self.range(tot)
        for i in range(len(names)):
            r -= weights[i]
            if r < 0:
                return names[i]
        return names[len(names) - 1]

    def shuffle(self, lst):
        i = len(lst) - 1
        while i > 0:
            j = self.range(i + 1)
            lst[i], lst[j] = lst[j], lst[i]
            i -= 1


def offs_for(w):
    """lateral offsets for a link of width w: 1->[0] 2->[0,1] 3->[-1,0,1] 4->[-1,0,1,2] 5->[-2..2]"""
    lo = (w - 1) // 2
    return list(range(-lo, w - lo))


# ---- room archetypes ---------------------------------------------------------
# Each returns (tiles, socks, props, anchors):
#   tiles   [lx, lz, dy, kind]   kind 0 = flat, 1+dir = ramp ascending toward dir
#   socks   [lx, lz, dir, dy, wmax]  (lx,lz) is an edge tile; dir points outward; the whole room
#           lies at or behind that tile along dir (so a link leaving it can never overlap the room)
#   props   [lx, lz, dy, h, kind]  blocking 1-cell boxes standing on the tile at (lx,lz,dy)
#   anchors [kind, lx, lz, dy]
PROP_BLOCK, PROP_WALL, PROP_CRATE, PROP_PILLAR = 0, 1, 2, 3
# anchor kinds (TERRAIN_SPEC section 6.5). 3 is RETIRED and reserved: the `hop` anchor kind is never
# emitted since GEN_VERSION 3 (the shape contract removed the only archetype that produced it). The
# id is not reused, so old and new data can never be confused.
AN_PERCH, AN_OPEN, AN_LANE, AN_NOOK = 0, 1, 2, 4


def scatter(rng, tiles, socks, count, props):
    """place up to `count` blocking props on interior flat tiles, Chebyshev >= 3 apart,
    never within Chebyshev 2 of a socket tile. A single 1-cell prop on an interior tile can
    always be walked around, so props never cut a room."""
    d = {}
    for t in tiles:
        d[(t[0], t[1])] = t
    cand = []
    for t in tiles:
        if t[3] != 0:
            continue
        ok = True
        for o in N8:
            n = d.get((t[0] + o[0], t[1] + o[1]))
            if n is None or n[2] != t[2] or n[3] != 0:
                ok = False
                break
        if not ok:
            continue
        for s in socks:
            if abs(s[0] - t[0]) <= 2 and abs(s[1] - t[1]) <= 2:
                ok = False
                break
        if ok:
            cand.append(t)
    rng.shuffle(cand)
    placed = []
    for t in cand:
        if len(placed) >= count:
            break
        ok = True
        for p in placed:
            if abs(p[0] - t[0]) < 3 and abs(p[1] - t[1]) < 3:
                ok = False
                break
        if ok:
            placed.append(t)
            kind = rng.wpick((PROP_BLOCK, PROP_WALL, PROP_CRATE, PROP_PILLAR), (5, 2, 4, 2))
            h = (4, 6, 2, 10)[kind] + (rng.range(2) * 2 if kind != PROP_CRATE else 0)
            props.append([t[0], t[1], t[2], h, kind])


def plat_pad(rng, t, gentle):
    """Square rest point. bbox <= 7x7 and <= 40 tiles (TERRAIN_SPEC section 1A rule 2)."""
    w = rng.ri(3, 7)
    dmax = 40 // w
    if dmax > 7:
        dmax = 7
    d = rng.ri(3, dmax)
    tiles = []
    for x in range(w):
        for z in range(d):
            tiles.append([x, z, 0, 0])
    # a socket is never on a corner: the 3-wide walkway leaving it meets 3 platform tiles
    jx = rng.ri(1, w - 2)
    jz = rng.ri(1, d - 2)
    jx2 = rng.ri(1, w - 2)
    jz2 = rng.ri(1, d - 2)
    socks = [[w - 1, jz, 0, 0, WALK_W], [jx, d - 1, 1, 0, WALK_W], [0, jz2, 2, 0, WALK_W],
             [jx2, 0, 3, 0, WALK_W]]
    props = []
    scatter(rng, tiles, socks, rng.ri(0, 2), props)
    anchors = [[AN_OPEN, w // 2, d // 2, 0]] if w * d >= 25 else []
    return tiles, socks, props, anchors


def plat_disc(rng, t, gentle):
    """Round rest point, radius 2..3 (bbox 5x5 or 7x7)."""
    r = rng.ri(2, 3)
    tiles = []
    for x in range(-r, r + 1):
        for z in range(-r, r + 1):
            if x * x + z * z <= r * r + r:
                tiles.append([x, z, 0, 0])
    socks = [[r, 0, 0, 0, WALK_W], [0, r, 1, 0, WALK_W], [-r, 0, 2, 0, WALK_W], [0, -r, 3, 0, WALK_W]]
    props = []
    scatter(rng, tiles, socks, rng.ri(0, 1), props)
    anchors = [[AN_OPEN, 0, 0, 0]] if r >= 3 else []
    return tiles, socks, props, anchors


def plat_cross(rng, t, gentle):
    """Four-way junction. Arm width 3 (GEN_VERSION 4), arm lengths 1..3, bbox <= 7x7."""
    a = WALK_W
    rem = 7 - a
    l0 = rng.ri(1, 3)
    if l0 > rem - 1:
        l0 = rem - 1
    l2 = rng.ri(1, 3)
    if l2 > rem - l0:
        l2 = rem - l0
    l1 = rng.ri(1, 3)
    if l1 > rem - 1:
        l1 = rem - 1
    l3 = rng.ri(1, 3)
    if l3 > rem - l1:
        l3 = rem - l1
    tiles = []
    for x in range(-l2, a + l0):
        for z in range(-l3, a + l1):
            if (0 <= x < a) or (0 <= z < a):
                tiles.append([x, z, 0, 0])
    m = a // 2
    socks = [[a + l0 - 1, m, 0, 0, a], [m, a + l1 - 1, 1, 0, a], [-l2, m, 2, 0, a], [m, -l3, 3, 0, a]]
    props = []
    if a >= 2:
        scatter(rng, tiles, socks, rng.ri(0, 1), props)
    return tiles, socks, props, []


def plat_ell(rng, t, gentle):
    """Corner. Arm width 3 (GEN_VERSION 4), arm lengths 4..6."""
    a = WALK_W
    la = rng.ri(4, 6)
    lb = rng.ri(4, 6)
    tiles = []
    for x in range(la):
        for z in range(lb):
            if z < a or x < a:
                tiles.append([x, z, 0, 0])
    m = a // 2
    socks = [[la - 1, m, 0, 0, a], [m, lb - 1, 1, 0, a], [0, m, 2, 0, a], [m, 0, 3, 0, a]]
    props = []
    if a >= 2:
        scatter(rng, tiles, socks, rng.ri(0, 1), props)
    return tiles, socks, props, []


def plat_terrace(rng, t, gentle):
    """Two-level platform: the upper band is one step up (1 HU when gentle, else 2 HU).
    GEN_VERSION 4: each band is at least 3 deep and every socket is centred on a 3-cell face."""
    w = rng.ri(3, 5)
    d1 = rng.ri(3, 4)
    d2 = rng.ri(3, 7 - d1)
    up = 1 if gentle else 2
    tiles = []
    for x in range(w):
        for z in range(d1):
            tiles.append([x, z, 0, 0])
        for z in range(d1, d1 + d2):
            tiles.append([x, z, up, 0])
    socks = [[w - 1, 1, 0, 0, WALK_W], [0, 1, 2, 0, WALK_W],
             [rng.ri(1, w - 2), d1 + d2 - 1, 1, up, WALK_W],
             [w - 1, d1 + 1, 0, up, WALK_W]]
    return tiles, socks, [], []


def plat_nook(rng, t, gentle):
    """Walled on three sides, ONE socket: a guaranteed dead end."""
    s = rng.ri(5, 6)   # GEN_VERSION 4: the walled interior is at least 3 cells wide
    tiles = []
    props = []
    for x in range(s):
        for z in range(s):
            tiles.append([x, z, 0, 0])
            if x >= 1 and (x == s - 1 or z == 0 or z == s - 1):
                props.append([x, z, 0, 6, PROP_WALL])
    socks = [[0, s // 2, 2, 0, WALK_W]]
    return tiles, socks, props, [[AN_NOOK, s // 2, s // 2, 0]]


SPIRE_Q = ((0, 0), (4, 0), (4, 4), (0, 4))
SPIRE_OUT = ((2, 3), (0, 3), (0, 1), (2, 1))  # outward dirs per quadrant


def plat_spire(rng, t, gentle):
    """2..3 pads of 3x3 spiralling up, +3 HU each, gap 1: a vertical climb with an overlook."""
    n = rng.ri(2, 3)
    tiles = []
    for k in range(n):
        q = SPIRE_Q[k % 4]
        for x in range(3):
            for z in range(3):
                tiles.append([q[0] + x, q[1] + z, 3 * k, 0])
    socks = [[0, 1, 2, 0, WALK_W], [1, 0, 3, 0, WALK_W]]
    kq = (n - 1) % 4
    q = SPIRE_Q[kq]
    od = SPIRE_OUT[kq][rng.range(2)]
    top = 3 * (n - 1)
    if od == 0:
        socks.append([q[0] + 2, q[1] + 1, 0, top, WALK_W])
    elif od == 1:
        socks.append([q[0] + 1, q[1] + 2, 1, top, WALK_W])
    elif od == 2:
        socks.append([q[0], q[1] + 1, 2, top, WALK_W])
    else:
        socks.append([q[0] + 1, q[1], 3, top, WALK_W])
    anchors = [[AN_PERCH, q[0] + 1, q[1] + 1, top]]
    return tiles, socks, [], anchors


def plat_bastion(rng, t, gentle):
    """Small square with a 3x3 tower +4 HU in the middle: an overlook."""
    s = rng.ri(5, 6)
    c = s // 2
    tiles = []
    for x in range(s):
        for z in range(s):
            tower = abs(x - c) <= 1 and abs(z - c) <= 1   # optional high ground, never on a route
            tiles.append([x, z, 4 if tower else 0, 0])
    socks = [[s - 1, rng.ri(1, s - 2), 0, 0, WALK_W], [rng.ri(1, s - 2), s - 1, 1, 0, WALK_W],
             [0, rng.ri(1, s - 2), 2, 0, WALK_W], [rng.ri(1, s - 2), 0, 3, 0, WALK_W]]
    return tiles, socks, [], [[AN_PERCH, c, c, 4]]


PLAT_FN = {
    "pad": plat_pad, "disc": plat_disc, "cross": plat_cross, "ell": plat_ell,
    "terrace": plat_terrace, "nook": plat_nook, "spire": plat_spire, "bastion": plat_bastion,
}


# ---- links -----------------------------------------------------------------
def build_walkway(rng, arch, x, z, d, y, w, tn, up_pct):
    """Build a straight walkway starting at cell (x,z) heading dir d at height y.
    Returns (cells, n, y_end, jumps, w) where cells = [x,z,y,kind,is_center], n = rows consumed
    along d (the platform's entry tile goes at index n), or None.
    A tread is a run of rows at one height; consecutive treads differ by the arch's step
    (TERRAIN_SPEC section 6.4). Every step is inside the AUTHORING envelope both ways."""
    lat = (d + 1) % 4
    offs = offs_for(w)
    cells = []

    def row(i, yy, kind):
        for o in offs:
            cells.append([x + DX[d] * i + DX[lat] * o, z + DZ[d] * i + DZ[lat] * o, yy, kind, 1 if o == 0 else 0])

    up = rng.chance(up_pct, 100)
    i = 0
    cy = y
    jumps = 0
    if arch == "step":
        k = rng.ri(4, 6)
        for s in range(k):
            if s > 0:
                cy += 1 if up else -1
            ln = rng.ri(1, 2)
            for q in range(ln):
                row(i, cy, 0)
                i += 1
    elif arch == "stair":
        k = rng.ri(2, 4)
        for s in range(k):
            if s > 0:
                cy += 2 if up else -2
                jumps += 1
            ln = rng.ri(1, 2)
            for q in range(ln):
                row(i, cy, 0)
                i += 1
    elif arch == "ledge":
        a = rng.ri(1, 2)
        for q in range(a):
            row(i, cy, 0)
            i += 1
        mag = rng.ri(2, 4)
        cy = cy + mag if up else cy - mag
        jumps += 1
        b = rng.ri(1, 2)
        for q in range(b):
            row(i, cy, 0)
            i += 1
    elif arch == "flat":
        ln = rng.ri(2, 4)
        for q in range(ln):
            row(i, cy, 0)
            i += 1
    elif arch == "ramp":
        a = rng.ri(1, 2)
        for q in range(a):
            row(i, cy, 0)
            i += 1
        n = rng.ri(1, 2)
        for q in range(n):
            if up:
                row(i, cy, 1 + d)
                cy += 1
            else:
                cy -= 1
                row(i, cy, 1 + (d + 2) % 4)
            i += 1
        b = rng.ri(1, 2)
        for q in range(b):
            row(i, cy, 0)
            i += 1
    else:
        return None
    if cy < Y_MIN or cy > Y_MAX:
        return None
    return cells, i, cy, jumps, w


# ---- world -------------------------------------------------------------------
class World:
    def __init__(self):
        self.tiles = []     # [x, z, y, kind, pid]
        self.col = {}       # (x,z) -> [tile index]
        self.props = []     # [x, z, y, h, kind, pid]
        self.pcol = {}      # (x,z) -> [prop index]
        self.pieces = []    # dict
        self.edges = []     # [a, b, kind]
        self.anchors = []   # [kind, x, z, y, pid]
        self.pads = []      # [x, z, y, tx, tz, ty]
        self.nbr = {}       # pid -> [pid] (undirected piece graph)
        self.shapes = {}    # (arch, min dim, max dim, tile count) -> 1, lookup only

    def fits(self, cells, allow):
        col = self.col
        T = self.tiles
        for c in cells:
            x, z, y = c[0], c[1], c[2]
            lst = col.get((x, z))
            if lst is not None:
                for i in lst:
                    if abs(T[i][2] - y) < CLEAR:
                        return False
            for o in N8:
                lst = col.get((x + o[0], z + o[1]))
                if lst is not None:
                    for i in lst:
                        tt = T[i]
                        if abs(tt[2] - y) < CLEAR and tt[4] not in allow:
                            return False
        return True

    def add_piece(self, kind, arch, parent, depth, arm, role, y):
        pid = len(self.pieces)
        self.pieces.append({"id": pid, "kind": kind, "arch": arch, "parent": parent, "depth": depth,
                            "arm": arm, "role": role, "y": y, "center": [], "jumps": 0, "w": 0})
        self.nbr[pid] = []
        return pid

    def add_tile(self, x, z, y, kind, pid):
        i = len(self.tiles)
        self.tiles.append([x, z, y, kind, pid])
        lst = self.col.get((x, z))
        if lst is None:
            self.col[(x, z)] = [i]
        else:
            lst.append(i)
        return i

    def add_prop(self, x, z, y, h, kind, pid):
        i = len(self.props)
        self.props.append([x, z, y, h, kind, pid])
        lst = self.pcol.get((x, z))
        if lst is None:
            self.pcol[(x, z)] = [i]
        else:
            lst.append(i)

    def add_edge(self, a, b, kind):
        self.edges.append([a, b, kind])
        self.nbr[a].append(b)
        self.nbr[b].append(a)

    def graph_dist(self, a, b, cap):
        if a == b:
            return 0
        seen = {a: 0}
        q = [a]
        h = 0
        while h < len(q):
            c = q[h]
            h += 1
            dc = seen[c]
            if dc >= cap:
                continue
            for n in self.nbr[c]:
                if n not in seen:
                    if n == b:
                        return dc + 1
                    seen[n] = dc + 1
                    q.append(n)
        return cap + 1


def xform(lx, lz, mir, rot):
    if mir:
        lx = -lx
    if rot == 0:
        return lx, lz
    if rot == 1:
        return -lz, lx
    if rot == 2:
        return -lx, -lz
    return lz, -lx


def xdir(d, mir, rot):
    if mir and (d == 0 or d == 2):
        d = 2 - d
    return (d + rot) % 4


def build_hub(W):
    """The one dominant spawn platform (TERRAIN_SPEC section 6.1): 205 tiles, bbox 19x19.
    Plaza [-6,6]^2 at y=0, dais [-2,2]^2 at y=1, four 3-wide stubs at cells 7..9."""
    pid = W.add_piece(0, "hub", -1, 0, -1, ROLE_HUB, 0)
    for x in range(-6, 7):
        for z in range(-6, 7):
            W.add_tile(x, z, 1 if (abs(x) <= 2 and abs(z) <= 2) else 0, 0, pid)
    for d in range(4):
        lat = (d + 1) % 4
        for i in range(7, 10):
            for o in range(-1, 2):
                W.add_tile(DX[d] * i + DX[lat] * o, DZ[d] * i + DZ[lat] * o, 0, 0, pid)
    for c in ((6, 6), (-6, 6), (-6, -6), (6, -6)):
        W.add_prop(c[0], c[1], 0, 10, PROP_PILLAR, pid)
    return pid, [[9, 0, 0, 0, pid, WALK_W, 0], [0, 9, 1, 0, pid, WALK_W, 0],
                 [-9, 0, 2, 0, pid, WALK_W, 0], [0, -9, 3, 0, pid, WALK_W, 0]]


SPAWNS = ((1, 1), (-1, -1), (-1, 1), (1, -1), (2, 0), (-2, 0), (0, 2), (0, -2))


def try_grow(W, rng, sock, arm, trait, tn, arch_count, state, drift):
    """Grow one step out of `sock`: build a walkway, then either attach a platform at its far end
    or leave the walkway's far end as a socket the next step grows from (TERRAIN_SPEC section 6.3).
    Returns a list of new sockets (possibly empty), or False if nothing could be built."""
    x, z, d, y, pid, wmax = sock[0], sock[1], sock[2], sock[3], sock[4], sock[5]
    lat = (d + 1) % 4
    parent = W.pieces[pid]
    t = tn["t"]
    gentle = parent["depth"] + 1 < tn["jump_min_depth"]
    # walkway archetype
    lw = []
    tl = TRAIT_LINK[trait]
    for name in WALKS:
        w = tn["walk_w"][name] * tl[name]
        if gentle and (name == "stair" or name == "ledge"):
            w = 0          # paths near the hub are walkable on early levels (D8 gentle start)
        lw.append(w)
    larch = rng.wpick(WALKS, lw)
    # width: exactly WALK_W = 3 cells (GEN_VERSION 4, TERRAIN_SPEC section 1A rule 2). No RNG draw.
    w = WALK_W
    up_pct = TRAIT_UP_PCT[trait] + 22 * drift
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
    if parent["kind"] == 0:
        if gentle:
            y0 = y + (1 if rng.chance(50, 100) else -1)
        else:
            y0 = y + (1, -1, 2, -2, 1, -1, 2, -2)[rng.range(8)]
        if y0 < Y_MIN or y0 > Y_MAX:
            return False
    else:
        y0 = y
    lk = build_walkway(rng, larch, x + DX[d], z + DZ[d], d, y0, w, tn, up_pct)
    if lk is None:
        return False
    cells, n, y1, jumps, w = lk
    px = x + DX[d] * (1 + n)
    pz = z + DZ[d] * (1 + n)
    R = tn["radius"]
    # attach a platform at the far end? (the roll is always drawn: draw order is contract)
    roll = rng.chance(tn["plat_pct"], 100)
    attach = False
    if state["placed"] < state["target"] and state["since"] >= 3:
        attach = state["since"] >= 6 or roll or state["placed"] >= state["target"] - 1
    if not attach:
        # walkway only: its far end becomes a socket and the path continues. The socket turns 90
        # degrees with turn_pct, so a path winds instead of running out as a straight stick.
        if not W.fits(cells, (pid,)):
            return False
        depth = parent["depth"] + 1
        lid = W.add_piece(1, larch, pid, depth, arm, ROLE_LINK, y)
        lp = W.pieces[lid]
        lp["jumps"] = jumps
        lp["w"] = w
        for c in cells:
            i = W.add_tile(c[0], c[1], c[2], c[3], lid)
            if c[4]:
                lp["center"].append(i)
        if larch in ("step", "flat") and n >= 8:
            m = cells[(n // 2) * len(offs_for(w)) + len(offs_for(w)) // 2]
            W.anchors.append([AN_LANE, m[0], m[1], m[2], lid])
        W.add_edge(pid, lid, EDGE_TREE)
        state["since"] += 1
        turn = rng.range(2)
        do_turn = rng.chance(tn["turn_pct"], 100)
        if do_turn and n >= 4:
            # the socket sits on the outer tile of row n-2 on the chosen side and points sideways,
            # so the 3-wide walkway that grows from it covers rows n-3..n-1 flush (a clean L corner).
            # n >= 4 keeps the new walkway's 8-neighbour ring (rows n-4..n) off this walkway's parent.
            sd = lat if turn == 0 else (lat + 2) % 4
            so = 1 if turn == 0 else -1
            sx = x + DX[d] * (n - 1) + DX[lat] * so
            sz = z + DZ[d] * (n - 1) + DZ[lat] * so
            sy = cells[(n - 2) * WALK_W][2]
            # the straight-ahead socket stays open too: it is grown when the turn fails, and a
            # random pick may grow it as well, which makes a T junction (GEN_VERSION 4)
            return [[px - DX[d], pz - DZ[d], d, y1, lid, w, 1], [sx, sz, sd, sy, lid, w, 0]]
        return [[px - DX[d], pz - DZ[d], d, y1, lid, w, 1]]
    # platform archetype
    rw = []
    tr = TRAIT_ROOM[trait]
    for name in PLATS:
        wv = tn["plat_w"][name] * tr.get(name, 4)
        if name == parent["arch"]:
            wv = wv // 4
        c = arch_count.get(name, 0)
        if c >= 2:
            wv = wv // c
        wv += 1
        if gentle and name == "spire":
            wv = 0         # no jump-only platform near the hub on early levels
        rw.append(wv)
    # no two platforms of one level may share (archetype, footprint, tile count): re-roll up to 4x
    shape = None
    for reroll in range(4):
        arch = rng.wpick(PLATS, rw)
        tiles, socks, props, anchors = PLAT_FN[arch](rng, t, gentle)
        x0 = x1 = tiles[0][0]
        z0 = z1 = tiles[0][1]
        for q in tiles:
            if q[0] < x0:
                x0 = q[0]
            if q[0] > x1:
                x1 = q[0]
            if q[1] < z0:
                z0 = q[1]
            if q[1] > z1:
                z1 = q[1]
        a, b = x1 - x0, z1 - z0
        if a > b:
            a, b = b, a
        shape = (arch, a, b, len(tiles))
        if shape not in W.shapes:
            break
    mir = rng.range(2)
    entry = rng.range(len(socks))
    e = socks[entry]
    rot = ((d + 2) - xdir(e[2], mir, 0) + 4) % 4
    # junction step: the platform sits 0..2 HU above or below the walkway's end (section 6.3 step f)
    if gentle:
        step = 1 if rng.chance(50, 100) else -1
    else:
        step = (1, -1, 2, -2, 1, -1, 2, -2)[rng.range(8)]
    ex, ez = xform(e[0], e[1], mir, rot)
    ox, oz, oy = px - ex, pz - ez, y1 + step - e[3]
    linkcols = {}
    for c in cells:
        linkcols[(c[0], c[1])] = 1
    wt = []
    for tl_ in tiles:
        tx, tz = xform(tl_[0], tl_[1], mir, rot)
        tx += ox
        tz += oz
        ty = tl_[2] + oy
        if ty < Y_MIN or ty > Y_MAX or abs(tx) > R or abs(tz) > R:
            return False
        if (tx, tz) in linkcols:
            return False
        k = tl_[3]
        if k:
            k = 1 + xdir(k - 1, mir, rot)
        wt.append([tx, tz, ty, k])
    if not W.fits(cells, (pid,)):
        return False
    if not W.fits(wt, ()):
        return False
    # commit
    depth = parent["depth"] + 1
    lid = W.add_piece(1, larch, pid, depth, arm, ROLE_LINK, y)
    lp = W.pieces[lid]
    lp["jumps"] = jumps
    lp["w"] = w
    for c in cells:
        i = W.add_tile(c[0], c[1], c[2], c[3], lid)
        if c[4]:
            lp["center"].append(i)
    rid = W.add_piece(0, arch, lid, depth + 1, arm, ROLE_ROOM, oy)
    for c in wt:
        W.add_tile(c[0], c[1], c[2], c[3], rid)
    for p in props:
        tx, tz = xform(p[0], p[1], mir, rot)
        W.add_prop(tx + ox, tz + oz, p[2] + oy, p[3], p[4], rid)
    for a in anchors:
        tx, tz = xform(a[1], a[2], mir, rot)
        W.anchors.append([a[0], tx + ox, tz + oz, a[3] + oy, rid])
    if larch in ("step", "flat") and n >= 8:
        m = cells[(n // 2) * len(offs_for(w)) + len(offs_for(w)) // 2]
        W.anchors.append([AN_LANE, m[0], m[1], m[2], lid])
    W.add_edge(pid, lid, EDGE_TREE)
    W.add_edge(lid, rid, EDGE_TREE)
    arch_count[arch] = arch_count.get(arch, 0) + 1
    W.shapes[shape] = 1
    state["placed"] += 1
    state["since"] = 0
    term_roll = rng.chance(tn["term_pct"], 100)
    terminal = state["placed"] >= state["target"] or term_roll
    # drop the entry socket by index (TERRAIN_REF porting rule 8): a value compare would also
    # drop a second socket that happens to be equal, which the port cannot express
    out = []
    for si in range(len(socks)):
        if si == entry:
            continue
        s = socks[si]
        sx, sz = xform(s[0], s[1], mir, rot)
        sd = xdir(s[2], mir, rot)
        out.append([sx + ox, sz + oz, sd, s[3] + oy, rid, s[4], 1 if sd == d else 0])
    if terminal:
        state["dead"].extend(out)   # a terminal platform is a dead end; its sockets feed shortcuts
        return []
    return out


def has_prop(W, x, z, y):
    lst = W.pcol.get((x, z))
    if lst is None:
        return False
    for i in lst:
        if W.props[i][2] == y:
            return True
    return False


def try_loop(W, rng, sock, tn, counts, ray=None):
    """Cast a ray out of an unused socket. If it meets another piece: build a two-way bridge
    (EDGE_LOOP) when a ramp fits, or a one-way drop ledge (EDGE_DROP) when the target is >= 5 HU
    lower. Returns True if something was built."""
    x, z, d, y, pid, wmax = sock[0], sock[1], sock[2], sock[3], sock[4], sock[5]
    if ray is None:
        ray = tn["ray_len"]
    T = W.tiles
    hit = None
    for i in range(1, ray + 1):
        cx, cz = x + DX[d] * i, z + DZ[d] * i
        lst = W.col.get((cx, cz))
        if lst is None:
            continue
        best = None
        for j in lst:
            dy = T[j][2] - y
            if dy >= CLEAR:
                continue          # far above: we pass underneath
            if best is None or T[j][2] > T[best][2]:
                best = j          # highest tile at or below our ceiling
        if best is not None:
            hit = (i, best)
            break
    if hit is None:
        return False
    i, j = hit
    tt = T[j]
    q = tt[4]
    if q == pid or tt[3] != 0 or has_prop(W, tt[0], tt[1], tt[2]):
        return False
    dy = tt[2] - y
    n = i - 1
    lat = (d + 1) % 4
    src = W.pieces[pid]
    if abs(dy) <= n and n >= 2 and counts[0] < tn["loops_max"]:
        if W.graph_dist(pid, q, tn["loop_min_graph_dist"]) < tn["loop_min_graph_dist"]:
            return False
        ady = dy if dy >= 0 else -dy
        sgn = 1 if dy > 0 else -1
        for w in (WALK_W,):
            cells = []
            for k in range(n):
                yy = y + 1 + sgn * ((ady * (k + 1)) // n)   # |dy| single-HU steps spread over n rows
                for o in offs_for(w):
                    cells.append([x + DX[d] * (k + 1) + DX[lat] * o, z + DZ[d] * (k + 1) + DZ[lat] * o, yy, 0, 1 if o == 0 else 0])
            if W.fits(cells, (pid, q)):
                lid = W.add_piece(1, "bridge", pid, src["depth"], src["arm"], ROLE_LOOP, y)
                W.pieces[lid]["w"] = w
                for c in cells:
                    ti = W.add_tile(c[0], c[1], c[2], c[3], lid)
                    if c[4]:
                        W.pieces[lid]["center"].append(ti)
                W.add_edge(pid, lid, EDGE_LOOP)
                W.add_edge(lid, q, EDGE_LOOP)
                counts[0] += 1
                return True
        return False
    if -DROP_MAX // 2 <= dy <= -5 and n >= 1 and counts[1] < tn["drops_max"]:
        if W.graph_dist(pid, q, 3) < 3:
            return False
        w = WALK_W
        cells = []
        for k in range(n):
            for o in offs_for(w):
                cells.append([x + DX[d] * (k + 1) + DX[lat] * o, z + DZ[d] * (k + 1) + DZ[lat] * o, y + 1, 0, 1 if o == 0 else 0])
        if not W.fits(cells, (pid, q)):
            return False
        lid = W.add_piece(1, "jut", pid, src["depth"], src["arm"], ROLE_DROP, y)
        W.pieces[lid]["w"] = w
        last = -1
        for c in cells:
            ti = W.add_tile(c[0], c[1], c[2], c[3], lid)
            if c[4]:
                W.pieces[lid]["center"].append(ti)
                last = ti
        W.add_edge(pid, lid, EDGE_TREE)
        kind = EDGE_DROP
        if dy >= -7 and rng.chance(50, 100):
            e = T[last]
            W.pads.append([tt[0], tt[1], tt[2], e[0], e[1], e[2]])
            kind = EDGE_PAD
        W.add_edge(lid, q, kind)
        counts[1] += 1
        return True
    return False


# ---- movement graph (same model as the validator, TERRAIN_SPEC section 5) ----------------
def rdiv(a, n):
    """round(a / n) for n > 0 without dividing a negative number."""
    if a >= 0:
        return (2 * a + n) // (2 * n)
    return -((-2 * a + n) // (2 * n))


JUMP_OFFS = []
for _dx in range(-6, 7):
    for _dz in range(-6, 7):
        _d2 = _dx * _dx + _dz * _dz
        if 0 < _d2 <= 36:
            JUMP_OFFS.append((_dx, _dz, _d2))


def movement(W):
    """returns (walkable, adj, boundary). adj[i] = list of tile indices reachable in one move."""
    T = W.tiles
    n = len(T)
    col = W.col
    walkable = [True] * n
    for p in W.props:
        lst = col.get((p[0], p[1]))
        if lst is not None:
            for i in lst:
                if T[i][2] == p[2]:
                    walkable[i] = False
    adj = [[] for _ in range(n)]
    boundary = [False] * n
    for i in range(n):
        if not walkable[i]:
            continue
        t = T[i]
        for d in range(4):
            lst = col.get((t[0] + DX[d], t[1] + DZ[d]))
            found = False
            if lst is not None:
                for j in lst:
                    if walkable[j] and abs(T[j][2] - t[2]) <= 1:
                        adj[i].append(j)
                        found = True
            if not found:
                boundary[i] = True
    props = W.props
    pcol = W.pcol
    for i in range(n):
        if not boundary[i]:
            continue
        a = T[i]
        ax, az, ay = a[0], a[1], a[2]
        for o in JUMP_OFFS:
            lst = col.get((ax + o[0], az + o[1]))
            if lst is None:
                continue
            for j in lst:
                if not boundary[j]:
                    continue
                dy = T[j][2] - ay
                if dy > JUMP_UP_MAX or dy < -DROP_MAX:
                    continue
                lim = JUMP_GAP[0] if dy <= 0 else (JUMP_GAP[1] if dy <= 2 else JUMP_GAP[2])
                if o[2] > (lim + 1) * (lim + 1):
                    continue
                if o[2] == 1 and -1 <= dy <= 1:
                    continue
                hi = ay if dy <= 0 else ay + dy
                steps = abs(o[0]) if abs(o[0]) > abs(o[1]) else abs(o[1])
                ok = True
                for s in range(1, steps):
                    cx = ax + rdiv(o[0] * s, steps)
                    cz = az + rdiv(o[1] * s, steps)
                    l2 = col.get((cx, cz))
                    if l2 is not None:
                        for k in l2:
                            ty = T[k][2]
                            if ty > hi and ty - SLAB < hi + 8:
                                ok = False
                    l3 = pcol.get((cx, cz))
                    if l3 is not None:
                        for k in l3:
                            p = props[k]
                            if p[2] + p[3] > hi and p[2] < hi + 8:
                                ok = False
                    if not ok:
                        break
                if ok:
                    adj[i].append(j)
    for p in W.pads:
        a = find_tile(W, p[0], p[1], p[2])
        b = find_tile(W, p[3], p[4], p[5])
        if a >= 0 and b >= 0:
            adj[a].append(b)
    return walkable, adj, boundary


def find_tile(W, x, z, y):
    lst = W.col.get((x, z))
    if lst is not None:
        for i in lst:
            if W.tiles[i][2] == y:
                return i
    return -1


def bfs(adj, start):
    seen = [False] * len(adj)
    seen[start] = True
    q = [start]
    h = 0
    while h < len(q):
        c = q[h]
        h += 1
        for n in adj[c]:
            if not seen[n]:
                seen[n] = True
                q.append(n)
    return seen


# ---- gifts ---------------------------------------------------------------------
def lane_cell(W, x, z, y):
    """True when column (x, z) holds a walkable (prop-free) tile on the same layer as height y,
    i.e. within CLEAR of it. A tile a full layer above or below is a different floor."""
    lst = W.col.get((x, z))
    if lst is None:
        return False
    for j in lst:
        tj = W.tiles[j]
        if abs(tj[2] - y) < CLEAR and not has_prop(W, x, z, tj[2]):
            return True
    return False


def centre_lane(W, i):
    """TERRAIN_SPEC section 6.7 (GEN_VERSION 4): tile i is on a centre lane when all four neighbour
    columns hold a walkable tile on its layer (it is not on an edge) and, along at least one axis,
    there is exactly one walkable tile on each side of it (the cell two away is empty on both sides).
    On a 3-wide walkway that is the middle lane."""
    t = W.tiles[i]
    x, z, y = t[0], t[1], t[2]
    for d in range(4):
        if not lane_cell(W, x + DX[d], z + DZ[d], y):
            return False
    for a in range(2):
        if not lane_cell(W, x + 2 * DX[a], z + 2 * DZ[a], y) and \
                not lane_cell(W, x - 2 * DX[a], z - 2 * DZ[a], y):
            return True
    return False


def place_gifts(W, rng, tn, rt):
    """rt[i] = tile i is round-trip reachable. Returns list of slots [tile_index, pid] or None."""
    T = W.tiles
    S = tn["slots"]
    padset = {}
    for p in W.pads:
        padset[(p[0], p[1], p[2])] = 1
    cands = [[] for _ in W.pieces]
    for i in range(len(T)):
        t = T[i]
        if not rt[i] or t[3] != 0:
            continue
        if t[4] == 0 and t[2] == 1:
            continue  # beacon dais stays clean
        if (t[0], t[1], t[2]) in padset:
            continue
        if not centre_lane(W, i):
            continue  # a gift sits on a centre lane, never on an edge (GEN_VERSION 4)
        cands[t[4]].append(i)
    weights = []
    tot = 0
    for p in W.pieces:
        n = len(cands[p["id"]])
        role = p["role"]
        if role == ROLE_HUB:
            w = n // 2
        elif role == ROLE_DEADEND:
            w = 5 * n
        elif role == ROLE_LOOP or role == ROLE_DROP:
            w = 3 * n
        else:
            w = 2 * n
        if role != ROLE_HUB:
            w = w * (4 + (p["depth"] if p["depth"] < 8 else 8))
        weights.append(w)
        tot += w
    if tot == 0:
        return None
    quota = []
    rem = []
    used = 0
    for i in range(len(weights)):
        q = S * weights[i] // tot
        quota.append(q)
        rem.append([-(S * weights[i] % tot), i])
        used += q
    rem.sort()
    k = 0
    while used < S and k < len(rem):
        quota[rem[k][1]] += 1
        used += 1
        k += 1
    chosen = [[] for _ in W.pieces]
    taken = {}

    def far(i, sp):
        t = T[i]
        for ox in range(-sp + 1, sp):
            for oz in range(-sp + 1, sp):
                if (t[0] + ox, t[1] + oz) in taken:
                    return False
        return True

    def take(pid, i):
        chosen[pid].append(i)
        taken[(T[i][0], T[i][1])] = 1

    for p in W.pieces:
        pid = p["id"]
        q = quota[pid]
        c = cands[pid]
        if q == 0 or len(c) == 0:
            continue
        if p["kind"] == 1:
            cs = {}
            for i in c:
                cs[i] = 1
            line = [i for i in p["center"] if i in cs]
            n = len(line)
            if n > 0:
                qq = q if q < (n + 1) // 2 else (n + 1) // 2
                for j in range(qq):
                    i = line[(j * n + n // 2) // qq if qq > 0 else 0]
                    if far(i, 2):
                        take(pid, i)
        order = list(c)
        rng.shuffle(order)
        for i in order:
            if len(chosen[pid]) >= q:
                break
            if far(i, 2):
                take(pid, i)
        p["_order"] = order
    total = 0
    for c in chosen:
        total += len(c)
    for sp in (2, 1):
        progress = True
        while total < S and progress:
            progress = False
            for p in W.pieces:
                if total >= S:
                    break
                order = p.get("_order")
                if order is None:
                    order = list(cands[p["id"]])
                    rng.shuffle(order)
                    p["_order"] = order
                for i in order:
                    if far(i, sp):
                        take(p["id"], i)
                        total += 1
                        progress = True
                        break
    for p in W.pieces:
        if "_order" in p:
            del p["_order"]
    if total != S:
        return None
    slots = []
    for pid in range(len(chosen)):
        lst = sorted(chosen[pid])
        for i in lst:
            slots.append([i, pid])
    return slots


# ---- tripmine eligibility (TERRAIN_SPEC section 6.8) ---------------------------
# Contact = the player's centre within 0.9 u horizontally of the mine's tile centre, at ANY height
# (jumping over a mine does not avoid it). Coordinates are scaled by 10 so the whole test is
# integer-only: 0.9 -> 9, 0.9^2 -> 81.
MINE_SCALE = 10
MINE_R2 = 81        # 0.9 u squared, in coordinates scaled by MINE_SCALE


def seg_hits_mine(ax, az, bx, bz, mx, mz):
    """True iff the segment between tile centres (ax,az)-(bx,bz) passes within 0.9 u of (mx,mz).
    Integer-only: clamp the projection parameter with dot products, then compare 100*d^2 to 81*len^2
    (interior foot) or d^2 to 81 (foot at an endpoint)."""
    px = MINE_SCALE * ax + 5
    pz = MINE_SCALE * az + 5
    qx = MINE_SCALE * bx + 5
    qz = MINE_SCALE * bz + 5
    tx = MINE_SCALE * mx + 5
    tz = MINE_SCALE * mz + 5
    vx = qx - px
    vz = qz - pz
    wx = tx - px
    wz = tz - pz
    len2 = vx * vx + vz * vz
    dot = wx * vx + wz * vz
    if dot <= 0:
        return wx * wx + wz * wz <= MINE_R2
    if dot >= len2:
        ux = tx - qx
        uz = tz - qz
        return ux * ux + uz * uz <= MINE_R2
    return (wx * wx + wz * wz) * len2 - dot * dot <= MINE_R2 * len2


def bfs_bypass(nb, start, blocked, blk):
    """BFS from `start` skipping every tile flagged in `blocked` (bytearray) and every edge listed
    in `blk` (dict: source tile -> dict of blocked targets)."""
    n = len(nb)
    seen = bytearray(n)
    seen[start] = 1
    q = [start]
    h = 0
    while h < len(q):
        c = q[h]
        h += 1
        b = blk.get(c)
        if b is None:
            for j in nb[c]:
                if not seen[j] and not blocked[j]:
                    seen[j] = 1
                    q.append(j)
        else:
            for j in nb[c]:
                if not seen[j] and not blocked[j] and j not in b:
                    seen[j] = 1
                    q.append(j)
    return seen


class MineCtx:
    """The tripmine eligibility rule of TERRAIN_SPEC section 6.8, computed once per level.

    The bypass graph B(M) is the movement graph with the mine tiles removed and every jump/drop/pad
    edge removed whose horizontal segment passes within 0.9 u of a mine centre. A slot is eligible
    iff B({m}) keeps every round-trip tile except m itself round-trip reachable; the joint rule is
    the same statement for the level's whole mine set.
    """

    def __init__(self, W, adj, rt, slots):
        T = W.tiles
        n = len(T)
        self.T = T
        self.n = n
        self.rt = rt
        self.rt_count = 0
        for i in range(n):
            if rt[i]:
                self.rt_count += 1
        self.beacon = find_tile(W, 0, 0, 1)
        self.nb = adj
        self.nb_rev = [[] for _ in range(n)]
        for i in range(n):
            for j in adj[i]:
                self.nb_rev[j].append(i)
        self.slot_tiles = [s[0] for s in slots]
        # column index: (x, z) -> tile indices. The trigger cylinder is unbounded in height, so a
        # mine also removes every other tile in its own column.
        self.col = {}
        for i in range(n):
            key = (T[i][0], T[i][1])
            lst = self.col.get(key)
            if lst is None:
                self.col[key] = [i]
            else:
                lst.append(i)
        # every edge, walk included: the cylinder test is applied to all of them, never assumed
        self.edges = []
        for i in range(n):
            for j in adj[i]:
                self.edges.append((i, j))
        # cell -> edge ids whose segment passes through that cell. A segment that comes within 0.9 u
        # of a tile centre always passes through that tile's 3x3 cell block, so the per-slot query
        # only has to look at 9 cells.
        self.idx = {}
        for eid in range(len(self.edges)):
            i, j = self.edges[eid]
            ax = T[i][0]
            az = T[i][1]
            dx = T[j][0] - ax
            dz = T[j][1] - az
            adx = dx if dx >= 0 else -dx
            adz = dz if dz >= 0 else -dz
            steps = adx if adx > adz else adz
            den = 2 * steps if steps > 0 else 1
            px = -1 << 30
            pz = -1 << 30
            for s in range(0, 2 * steps + 1):
                cx = ax + rdiv(dx * s, den)
                cz = az + rdiv(dz * s, den)
                if cx == px and cz == pz:
                    continue
                px = cx
                pz = cz
                key = (cx, cz)
                lst = self.idx.get(key)
                if lst is None:
                    self.idx[key] = [eid]
                else:
                    lst.append(eid)
        self.cross = {}     # slot index -> list of edge ids crossing that slot's trigger cylinder
        self.elig = {}      # slot index -> bool

    def cross_edges(self, si):
        lst = self.cross.get(si)
        if lst is not None:
            return lst
        T = self.T
        m = self.slot_tiles[si]
        mx = T[m][0]
        mz = T[m][1]
        seen = {}
        out = []
        for ox in (-1, 0, 1):
            for oz in (-1, 0, 1):
                cell = self.idx.get((mx + ox, mz + oz))
                if cell is None:
                    continue
                for eid in cell:
                    if eid in seen:
                        continue
                    seen[eid] = 1
                    i, j = self.edges[eid]
                    if seg_hits_mine(T[i][0], T[i][1], T[j][0], T[j][1], mx, mz):
                        out.append(eid)
        self.cross[si] = out
        return out

    def _block(self, mines):
        """(blocked bytearray, forward blocked-edge map, reverse blocked-edge map) for a mine set.
        A tile is blocked when its centre lies inside any mine's trigger cylinder."""
        blocked = bytearray(self.n)
        blk_f = {}
        blk_b = {}
        T = self.T
        for si in mines:
            m = self.slot_tiles[si]
            mx = T[m][0]
            mz = T[m][1]
            for ox in (-1, 0, 1):
                for oz in (-1, 0, 1):
                    lst = self.col.get((mx + ox, mz + oz))
                    if lst is None:
                        continue
                    for t in lst:
                        dx = MINE_SCALE * (T[t][0] - mx)
                        dz = MINE_SCALE * (T[t][1] - mz)
                        if dx * dx + dz * dz <= MINE_R2:
                            blocked[t] = 1
            for eid in self.cross_edges(si):
                i, j = self.edges[eid]
                d = blk_f.get(i)
                if d is None:
                    blk_f[i] = {j: 1}
                else:
                    d[j] = 1
                d = blk_b.get(j)
                if d is None:
                    blk_b[j] = {i: 1}
                else:
                    d[i] = 1
        return blocked, blk_f, blk_b

    def _keeps_rt(self, mines):
        blocked, blk_f, blk_b = self._block(mines)
        rt = self.rt
        # the beacon and every real gift slot must survive the cylinder: a gift inside it is
        # uncollectable, so a mine may never create one
        if blocked[self.beacon]:
            return False
        mine_set = {}
        for si in mines:
            mine_set[si] = 1
        for si in range(len(self.slot_tiles)):
            if si not in mine_set and blocked[self.slot_tiles[si]]:
                return False
        need = 0
        for t in range(self.n):
            if rt[t] and not blocked[t]:
                need += 1
        fwd = bfs_bypass(self.nb, self.beacon, blocked, blk_f)
        cnt = 0
        for t in range(self.n):
            if rt[t] and not blocked[t] and fwd[t]:
                cnt += 1
        if cnt != need:
            return False
        back = bfs_bypass(self.nb_rev, self.beacon, blocked, blk_b)
        cnt = 0
        for t in range(self.n):
            if rt[t] and not blocked[t] and back[t]:
                cnt += 1
        return cnt == need

    def eligible(self, si):
        v = self.elig.get(si)
        if v is None:
            v = self._keeps_rt([si])
            self.elig[si] = v
        return v

    def joint_ok(self, mines):
        return self._keeps_rt(mines)


def roll_mines(rng, level, n, extra, W, adj, rt, slots):
    """returns occ list (0 gift, 1 tripmine). Per-slot chance (15+min(L,25))/400 from level 5,
    applied only to slots with a walkable bypass (TERRAIN_SPEC section 6.8.5). Total mines
    hard-capped at n // 5. Extra (curse) mines are flat adds under the same cap."""
    occ = [0] * n
    num = mine_chance_num(level)
    cap = n // 5
    count = 0
    ctx = None
    mines = []               # accepted mine slot ids, ascending
    for i in range(n):
        r = rng.range(400)   # always drawn, so the stream does not depend on level
        if r < num:
            if ctx is None:
                ctx = MineCtx(W, adj, rt, slots)
            if ctx.eligible(i) and ctx.joint_ok(mines + [i]):
                occ[i] = 1
                mines.append(i)
                count += 1
    # cap: un-set from the highest slot id
    while count > cap:
        i = mines.pop()
        occ[i] = 0
        count -= 1
    # extra (curse) mines: one draw per extra mine, indexing the ascending list of eligible free
    # slots. A slot that breaks the joint rule is banned for the rest of the phase: banning can only
    # place fewer mines, never an invalid one.
    e = 0
    banned = {}
    while e < extra and count < cap:
        if ctx is None:
            ctx = MineCtx(W, adj, rt, slots)
        free = []
        for i in range(n):
            if occ[i] == 0 and i not in banned and ctx.eligible(i):
                free.append(i)
        if not free:
            break            # no eligible slot left: place fewer, never break the rule
        k = free[rng.range(len(free))]
        if ctx.joint_ok(mines + [k]):
            occ[k] = 1
            mines.append(k)
            count += 1
        else:
            banned[k] = 1
        e += 1
    # safety net: the joint rule must hold for the final set. Removing a mine can in principle
    # re-open a tile that the remaining mines still cut off, so verify and repair from the top.
    while count > 0 and not ctx.joint_ok(mines):
        i = max(mines)
        mines.remove(i)
        occ[i] = 0
        count -= 1
    return occ


# ---- top level -----------------------------------------------------------------
def build(seed, level, players, extra_mines, attempt):
    tn = tuning(level, players)
    base = mix(mix(mix(seed & M32, level), GEN_VERSION), attempt)
    W = World()
    hub, hub_socks = build_hub(W)
    rp = Rng(mix(base, ST_PLAN))
    n_arms = rp.ri(tn["arms_min"], tn["arms_max"])
    order = [0, 1, 2, 3]
    rp.shuffle(order)
    tw = []
    for name in TRAITS:
        w = TRAIT_W[name]
        if name == "hop":
            w += tn["t"] // 2
        if name == "thin":
            w += tn["t"] // 3
        tw.append(w)
    arms = []
    spare = []
    used_traits = {}
    drifts = [-2, 2, -1, 1]
    rp.shuffle(drifts)
    for k in range(4):
        s = hub_socks[order[k]]
        if k < n_arms:
            w2 = [tw[i] // 4 if TRAITS[i] in used_traits else tw[i] for i in range(len(TRAITS))]
            trait = rp.wpick(TRAITS, [w + 1 for w in w2])
            used_traits[trait] = 1
            arms.append({"trait": trait, "open": [s], "quota": 0, "rooms": 0,
                         "share": rp.ri(1, 4), "deep": 25 + 15 * rp.range(5),
                         "drift": drifts[k] if (drifts[k] > 0) == (k % 2 == 0) else -drifts[k]})
        else:
            spare.append(s)
    # platform target (TERRAIN_SPEC section 6.2): ri(plat_max - 1, plat_max)
    pm = tn["plat_max"]
    target = rp.ri(pm - 1, pm)
    # asymmetric arms: every arm gets 1 platform, the rest is dealt by share (major and minor arms)
    tot_share = 0
    for A in arms:
        A["quota"] = 1
        tot_share += A["share"]
    left = target - n_arms
    given = 0
    for A in arms:
        q = left * A["share"] // tot_share
        A["quota"] += q
        given += q
    k = 0
    while given < left:
        arms[k % n_arms]["quota"] += 1
        given += 1
        k += 1
    state = {"placed": 0, "target": target, "since": 0, "dead": []}
    arch_count = {}
    guard = 0
    while state["placed"] < target and guard < pm * 60:
        guard += 1
        best = -1
        for a in range(n_arms):
            A = arms[a]
            if len(A["open"]) == 0:
                continue
            if best < 0 or A["quota"] - A["rooms"] > arms[best]["quota"] - arms[best]["rooms"]:
                best = a
        if best < 0:
            break
        A = arms[best]
        rg = Rng(mix(mix(base, ST_GROW), guard))
        op = A["open"]
        if rg.chance(A["deep"], 100):
            si = 0
            for k in range(len(op)):
                if W.pieces[op[k][4]]["depth"] >= W.pieces[op[si][4]]["depth"]:
                    si = k
            # turn bias: a socket that continues straight through its room yields to a sibling
            # socket that turns, so arms wind instead of running out as sticks
            if op[si][6] == 1 and rg.chance(tn["turn_pct"], 100):
                for k in range(len(op)):
                    if op[k][4] == op[si][4] and op[k][6] == 0:
                        si = k
        else:
            si = rg.range(len(op))
        sock = op[si]
        res = False
        before = state["placed"]
        for tr in range(tn["grow_tries"]):
            res = try_grow(W, rg, sock, best, A["trait"], tn, arch_count, state,
                           A["drift"])
            if res is not False:
                break
        op.pop(si)
        if res is False:
            state["dead"].append(sock)
        else:
            A["rooms"] += state["placed"] - before
            for s in res:
                op.append(s)
    if state["placed"] < target:
        return None   # the level must place its platform target (TERRAIN_SPEC section 6.0)
    # leaf platforms are dead ends
    child = {}
    for p in W.pieces:
        if p["parent"] >= 0:
            child[p["parent"]] = 1
    for p in W.pieces:
        if p["kind"] == 0 and p["role"] == ROLE_ROOM and p["id"] not in child:
            p["role"] = ROLE_DEADEND
    # loop closure
    rl = Rng(mix(base, ST_LOOP))
    opens = list(spare) + state["dead"]
    for A in arms:
        for s in A["open"]:
            opens.append(s)
    rl.shuffle(opens)
    counts = [0, 0]
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
        return None   # every level must contain at least one shortcut (TERRAIN_SPEC H14)
    n_dead = 0
    for p in W.pieces:
        if p["role"] == ROLE_DEADEND:
            n_dead += 1
    if n_dead < 2 and attempt < MAX_ATTEMPTS - 1:
        return None   # a level needs at least two dead ends (TERRAIN_SPEC H12)
    # elevation variance floor (TERRAIN_SPEC section 1A rule 3): paths gain and lose height
    ys = [t[2] for t in W.tiles if t[4] != 0]
    if ys:
        mean = sum(ys) / float(len(ys))
        var = 0.0
        for y in ys:
            var += (y - mean) * (y - mean)
        if (var / float(len(ys))) ** 0.5 < elev_var_floor(level):
            return None
    # path share floor (TERRAIN_SPEC section 1A rule 2): walkways carry most walkable tiles
    wt = 0
    pt = 0
    for t in W.tiles:
        if t[4] == 0:
            continue
        if W.pieces[t[4]]["kind"] == 1:
            wt += 1
        else:
            pt += 1
    if wt < pt:
        return None
    # reachability
    walkable, adj, boundary = movement(W)
    start = find_tile(W, 0, 0, 1)
    fwd = bfs(adj, start)
    radj = [[] for _ in adj]
    for i in range(len(adj)):
        for j in adj[i]:
            radj[j].append(i)
    back = bfs(radj, start)
    rt = [fwd[i] and back[i] for i in range(len(fwd))]
    for i in range(len(fwd)):
        if fwd[i] and not back[i]:
            return None   # a soft-lock tile exists: reject the attempt (D-014)
    rgift = Rng(mix(base, ST_GIFT))
    slots = place_gifts(W, rgift, tn, rt)
    if slots is None:
        return None
    occ = roll_mines(Rng(mix(base, ST_MINE)), level, len(slots), extra_mines, W, adj, rt, slots)
    return W, slots, occ, boundary, arms, counts


def generate(seed, level, players=1, extra_mines=0):
    """THE entry point. Pure function of its four integer arguments."""
    for attempt in range(MAX_ATTEMPTS):
        r = build(seed, level, players, extra_mines, attempt)
        if r is not None:
            return pack(seed, level, players, extra_mines, attempt, r)
    raise RuntimeError("voidgen: no valid level for seed=%d level=%d" % (seed, level))


def pack(seed, level, players, extra_mines, attempt, r):
    W, slots, occ, boundary, arms, counts = r
    T = W.tiles
    bb = {}
    cnt = {}
    for t in T:
        b = bb.get(t[4])
        if b is None:
            bb[t[4]] = [t[0], t[1], t[0], t[1]]
            cnt[t[4]] = 1
        else:
            if t[0] < b[0]:
                b[0] = t[0]
            if t[1] < b[1]:
                b[1] = t[1]
            if t[0] > b[2]:
                b[2] = t[0]
            if t[1] > b[3]:
                b[3] = t[1]
            cnt[t[4]] += 1
    pieces = []
    for p in W.pieces:
        b = bb[p["id"]]
        pieces.append({"id": p["id"], "kind": p["kind"], "arch": p["arch"], "parent": p["parent"],
                       "depth": p["depth"], "arm": p["arm"], "role": p["role"], "y": p["y"],
                       "bbox": b, "tiles": cnt[p["id"]], "jumps": p["jumps"], "w": p["w"]})
    gifts = []
    for k in range(len(slots)):
        i, pid = slots[k]
        t = T[i]
        role = W.pieces[pid]["role"]
        tier = 2 if role == ROLE_DEADEND else (1 if (W.pieces[pid]["kind"] == 1 or boundary[i]) else 0)
        gifts.append({"id": k, "x": t[0], "z": t[1], "y": t[2], "piece": pid, "tier": tier, "occ": occ[k]})
    return {
        "gen_version": GEN_VERSION,
        "seed": seed, "level": level, "players": players, "extra_mines": extra_mines,
        "attempt": attempt,
        "beacon": [0, 0, 1],
        "spawns": [[s[0], s[1], 1] for s in SPAWNS],
        "arms": [a["trait"] for a in arms],
        "pieces": pieces,
        "tiles": [list(t) for t in T],
        "props": [list(p) for p in W.props],
        "edges": [list(e) for e in W.edges],
        "gifts": gifts,
        "anchors": [list(a) for a in W.anchors],
        "pads": [list(p) for p in W.pads],
    }


def to_text(L):
    """canonical text. SHA-256 of this (UTF-8, LF) is the level hash."""
    o = []
    o.append("VOIDGEN %d" % L["gen_version"])
    o.append("IN %d %d %d %d" % (L["seed"], L["level"], L["players"], L["extra_mines"]))
    o.append("ATTEMPT %d" % L["attempt"])
    o.append("BEACON %d %d %d" % tuple(L["beacon"]))
    for s in L["spawns"]:
        o.append("SPAWN %d %d %d" % tuple(s))
    o.append("ARMS " + " ".join(L["arms"]))
    for p in L["pieces"]:
        o.append("P %d %d %s %d %d %d %d %d %d %d %d %d %d %d %d" % (
            p["id"], p["kind"], p["arch"], p["parent"], p["depth"], p["arm"], p["role"], p["y"],
            p["bbox"][0], p["bbox"][1], p["bbox"][2], p["bbox"][3], p["tiles"], p["jumps"], p["w"]))
    for t in L["tiles"]:
        o.append("T %d %d %d %d %d" % tuple(t))
    for p in L["props"]:
        o.append("O %d %d %d %d %d %d" % tuple(p))
    for e in L["edges"]:
        o.append("E %d %d %d" % tuple(e))
    for g in L["gifts"]:
        o.append("G %d %d %d %d %d %d %d" % (g["id"], g["x"], g["z"], g["y"], g["piece"], g["tier"], g["occ"]))
    for a in L["anchors"]:
        o.append("A %d %d %d %d %d" % tuple(a))
    for p in L["pads"]:
        o.append("X %d %d %d %d %d %d" % tuple(p))
    o.append("END")
    return "\n".join(o) + "\n"


def level_hash(L):
    return hashlib.sha256(to_text(L).encode("utf-8")).hexdigest()


def ascii_map(L):
    xs = [t[0] for t in L["tiles"]]
    zs = [t[1] for t in L["tiles"]]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    grid = [[" "] * (x1 - x0 + 1) for _ in range(z1 - z0 + 1)]
    top = {}
    for t in L["tiles"]:
        k = (t[0], t[1])
        if k not in top or t[2] > top[k][2]:
            top[k] = t
    for k, t in top.items():
        ch = "#" if L["pieces"][t[4]]["kind"] == 0 else "="
        if t[3]:
            ch = "/"
        grid[k[1] - z0][k[0] - x0] = ch
    for p in L["props"]:
        grid[p[1] - z0][p[0] - x0] = "o"
    for g in L["gifts"]:
        grid[g["z"] - z0][g["x"] - x0] = "x" if g["occ"] else "*"
    grid[0 - z0][0 - x0] = "B"
    return "\n".join("".join(r) for r in grid)


def main(argv):
    seed, level, players, extra = 1, 1, 1, 0
    out = None
    mode = "hash"
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--seed":
            seed = int(argv[i + 1]); i += 1
        elif a == "--level":
            level = int(argv[i + 1]); i += 1
        elif a == "--players":
            players = int(argv[i + 1]); i += 1
        elif a == "--extra-mines":
            extra = int(argv[i + 1]); i += 1
        elif a == "--json":
            out = argv[i + 1]; mode = "json"; i += 1
        elif a == "--text":
            out = argv[i + 1]; mode = "text"; i += 1
        elif a == "--ascii":
            mode = "ascii"
        i += 1
    L = generate(seed, level, players, extra)
    if mode == "json":
        with open(out, "w", newline="\n") as f:
            json.dump(L, f, separators=(",", ":"))
    elif mode == "text":
        with open(out, "w", newline="\n") as f:
            f.write(to_text(L))
    elif mode == "ascii":
        print(ascii_map(L))
    rooms = sum(1 for p in L["pieces"] if p["kind"] == 0)
    loops = sum(1 for e in L["edges"] if e[2] == EDGE_LOOP) // 2
    drops = sum(1 for e in L["edges"] if e[2] in (EDGE_DROP, EDGE_PAD))
    mines = sum(g["occ"] for g in L["gifts"])
    print("seed=%d level=%d attempt=%d rooms=%d tiles=%d gifts=%d mines=%d loops=%d drops=%d pads=%d arms=%s hash=%s" % (
        seed, level, L["attempt"], rooms, len(L["tiles"]), len(L["gifts"]), mines, loops, drops,
        len(L["pads"]), ",".join(L["arms"]), level_hash(L)))


if __name__ == "__main__":
    main(sys.argv)
