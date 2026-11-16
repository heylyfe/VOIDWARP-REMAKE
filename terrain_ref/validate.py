"""VOIDWRAP RUN terrain validator (TERRAIN_SPEC.md section 10).

Independent, headless judge. It reads ONLY the Level dict returned by
voidgen.generate and rebuilds the movement graph from scratch with its own
implementation of TERRAIN_SPEC section 5. The only names imported from the
generator are:

    generate, level_hash, slot_target, mine_chance_num

Everything else (walk/boundary/jump/drop/pad edges, clear-path test, Dijkstra,
articulation points, footprint similarity) is written here independently.

Ambiguity resolutions (stricter readings, see final report):
  * H4 "no prop in its cell": any prop in the slot column with
    slot.y <= base < slot.y + 12 (equality included, since a prop standing on
    the slot tile is the canonical v1 bug).
  * H3 "not a pad tile": a pad tile is the tile the pad STANDS on (the pad's
    [x,z,y] triple); pad target tiles stay legal gift candidates, matching
    the generator's own candidate filter.
  * H3 "distinct existing tile": no two slots may share a column (x,z),
    matching the generator's spacing key, which is the stricter reading.
  * chokepoints: literal reading - link pieces (kind 1) with w <= 2 whose
    REMOVAL disconnects the undirected piece graph built from Level["edges"],
    i.e. articulation points, not cut edges.
  * "pads" metric counts Level["pads"] (launch pads), as instructed.
  * p99 (D4) uses the same index convention as the p95 of H11:
    floor(0.99*(n-1)) of the sorted list.
  * D2 sample seeds: 1000..1099 at levels 5, 15, 30 (spec fixes count and
    levels, not the seeds; choice deterministic and documented here).
  * D4 footprint per DECISIONS D-022: 4-cell coarse blocks, hub tiles
    excluded by piece id 0. D6 share is computed per generated level and
    averaged over the sample.
  * D7/D8/J and the difficulty score treat a NULL distance (unreachable) as
    9999 in aggregates; unreachable gifts fail H10/H11 outright.

CLI:
    python validate.py --seeds A:B [--jobs N] [--out out/report.json]
    python validate.py --selftest
    python validate.py --one SEED LEVEL
"""
import argparse
import copy
import heapq
import json
import os
import random
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

from voidgen import generate, level_hash, slot_target, mine_chance_num  # noqa: E402

DX = (1, 0, -1, 0)
DZ = (0, 1, 0, -1)
CLEAR = 12          # HU, min height difference of two tiles in one column
SLAB = 2            # HU, slab thickness (part of the clear-path test)
JUMP_UP_MAX = 4     # HU, maximum jump-up of a jump/drop edge
DROP_MAX = 60       # HU, maximum drop of a jump/drop edge
VALIDATOR_GAP = (5, 4, 3)   # section 5.1 validator envelope
AUTHORING_GAP = (4, 3, 2)   # section 5.1 authoring envelope (H13)
INF = 1 << 60
BIG = 9999.0        # sentinel reported for unreachable-ish distances

HARD_CHECKS = ("H2", "H3", "H4", "H5", "H6", "H7", "H8", "H9", "H10",
               "H11", "H12", "H13", "H14", "H16", "H17", "H18", "H19",
               "H20", "H21", "H22", "H23")
HARNESS_CHECKS = ("H1",) + HARD_CHECKS + ("H15",)
METRIC_NAMES = ("walkable", "playable_pct", "platforms", "walkways", "dead_ends",
                "max_depth", "arms", "loops", "drops", "pads", "chokepoints",
                "J", "N", "V", "K", "gift_density", "first_gift",
                "starve_p95", "starve_max", "path_share", "path_tile_share",
                "flat_share", "ramp_share", "elev_var", "junction_step_pct",
                "D", "gen_ms")

# ---- shape contract constants (TERRAIN_SPEC section 1A) ----
HUB_TILES = 205            # hub piece tile count
HUB_DAIS = 25              # dais tiles at y=1
MAX_WALK_W = 2             # max walkway width in cells
MAX_PLAT_DIM = 7           # max platform bbox dimension in cells
MAX_PLAT_TILES = 40        # max platform tile count
PLAT_MIN = 3               # min platforms per level
PATH_SHARE_MIN = 0.70      # walkway length / (walkway + platform length)
PATH_TILE_MIN = 0.50       # walkway tiles / non-hub walkable tiles
FLAT_SHARE_MAX = 0.35      # flat-continuing rows / path rows
RAMP_SHARE_MAX = 0.10      # ramp rows / path rows
JUNCTION_STEP_MIN = 0.50   # share of sub-area boundaries with |dy| >= 1


def plat_max(level):
    """Platform ceiling (TERRAIN_SPEC section 9): min(12, 4 + level // 3)."""
    n = 4 + level // 3
    return n if n < 12 else 12


def elev_var_floor(level):
    """Elevation-variance floor (TERRAIN_SPEC section 1A rule 3): 3 HU at L1, 6 HU at L10+."""
    t = level if level < 10 else 10
    return 3 + 3 * (t - 1) // 9
BUCKETS = ((1, 5), (6, 10), (11, 15), (16, 20), (21, 25), (26, 30))


# ---------------------------------------------------------------------------
# movement graph, rebuilt from the Level dict per TERRAIN_SPEC section 5
# ---------------------------------------------------------------------------

def rdiv(a, n):
    """round(a / n) for n > 0, never dividing a negative number (spec 5.3)."""
    if a >= 0:
        return (2 * a + n) // (2 * n)
    return -((-2 * a + n) // (2 * n))


_OFFS_CACHE = {}


def jump_offsets(gaps):
    """(dx, dz, dx^2+dz^2) offsets bounded by the widest lim of the envelope."""
    if gaps in _OFFS_CACHE:
        return _OFFS_CACHE[gaps]
    m = (max(gaps) + 1) * (max(gaps) + 1)
    offs = []
    for dx in range(-6, 7):
        for dz in range(-6, 7):
            d2 = dx * dx + dz * dz
            if 0 < d2 <= m:
                offs.append((dx, dz, d2))
    _OFFS_CACHE[gaps] = offs
    return offs


def walk_layer(L):
    """Walk edges + boundary flags + walkability. Independent of the gap envelope."""
    tiles = L["tiles"]
    props = L["props"]
    n = len(tiles)
    col = {}
    for i, t in enumerate(tiles):
        c = (t[0], t[1])
        if c in col:
            col[c].append(i)
        else:
            col[c] = [i]
    pcol = {}
    for pi, p in enumerate(props):
        c = (p[0], p[1])
        if c in pcol:
            pcol[c].append(pi)
        else:
            pcol[c] = [pi]
    walkable = [True] * n
    for p in props:
        for i in col.get((p[0], p[1]), ()):
            if tiles[i][2] == p[2]:
                walkable[i] = False
    wn = [None] * n          # walk adjacency sets
    boundary = [False] * n
    for i in range(n):
        if not walkable[i]:
            continue
        t = tiles[i]
        s = set()
        for d in range(4):
            lst = col.get((t[0] + DX[d], t[1] + DZ[d]))
            found = False
            if lst:
                for j in lst:
                    if walkable[j] and abs(tiles[j][2] - t[2]) <= 1:
                        s.add(j)
                        found = True
            if not found:
                boundary[i] = True
        wn[i] = s
    return {"n": n, "tiles": tiles, "props": props, "col": col, "pcol": pcol,
            "walkable": walkable, "wn": wn, "boundary": boundary}


def find_tile(base, x, z, y):
    for i in base["col"].get((x, z), ()):
        if base["tiles"][i][2] == y:
            return i
    return -1


def build_adj(L, base, gaps):
    """Full directed move graph: (j, cost) per edge.
    Walk cost 1; jump/drop/pad cost max(|dx|,|dz|)."""
    tiles = base["tiles"]
    col = base["col"]
    pcol = base["pcol"]
    props = base["props"]
    n = base["n"]
    walkable = base["walkable"]
    boundary = base["boundary"]
    wn = base["wn"]
    adj = [[] for _ in range(n)]
    for i in range(n):
        if walkable[i]:
            adj[i] = [(j, 1) for j in wn[i]]
    offs = jump_offsets(gaps)
    for i in range(n):
        if not boundary[i] or not walkable[i]:
            continue
        t = tiles[i]
        ax, az, ay = t[0], t[1], t[2]
        wi = wn[i]
        for dx, dz, d2 in offs:
            lst = col.get((ax + dx, az + dz))
            if not lst:
                continue
            for j in lst:
                if not walkable[j] or not boundary[j] or j in wi:
                    continue
                b = tiles[j]
                dy = b[2] - ay
                if dy > JUMP_UP_MAX or dy < -DROP_MAX:
                    continue
                if dy <= 0:
                    lim = gaps[0]
                elif dy <= 2:
                    lim = gaps[1]
                else:
                    lim = gaps[2]
                if d2 > (lim + 1) * (lim + 1):
                    continue
                # clear-path test (spec 5.3); hi = max(yA, yB)
                hi = ay if dy <= 0 else ay + dy
                steps = abs(dx) if abs(dx) > abs(dz) else abs(dz)
                clear = True
                for s in range(1, steps):
                    cx = ax + rdiv(dx * s, steps)
                    cz = az + rdiv(dz * s, steps)
                    lk = col.get((cx, cz))
                    if lk:
                        for k in lk:
                            ty = tiles[k][2]
                            if ty > hi and ty - SLAB < hi + 8:
                                clear = False
                                break
                    if not clear:
                        break
                    lp = pcol.get((cx, cz))
                    if lp:
                        for k in lp:
                            p = props[k]
                            if p[2] + p[3] > hi and p[2] < hi + 8:
                                clear = False
                                break
                    if not clear:
                        break
                if clear:
                    adj[i].append((j, steps))
    for p in L["pads"]:
        a = find_tile(base, p[0], p[1], p[2])
        b = find_tile(base, p[3], p[4], p[5])
        if a >= 0 and b >= 0:
            c = max(abs(p[3] - p[0]), abs(p[4] - p[1]))
            adj[a].append((b, c if c > 0 else 1))
    return adj


def neighbors(adj):
    return [[j for j, _ in a] for a in adj]


def reversed_adj(adj, n):
    rev = [[] for _ in range(n)]
    for i in range(n):
        for j, c in adj[i]:
            rev[j].append((i, c))
    return rev


def bfs(nbrs, starts):
    n = len(nbrs)
    seen = bytearray(n)
    q = []
    for s in starts:
        if not seen[s]:
            seen[s] = 1
            q.append(s)
    h = 0
    while h < len(q):
        c = q[h]
        h += 1
        for j in nbrs[c]:
            if not seen[j]:
                seen[j] = 1
                q.append(j)
    return seen


def dijkstra(adj, sources, n):
    dist = [INF] * n
    h = []
    for s in sources:
        if dist[s]:
            dist[s] = 0
            heapq.heappush(h, (0, s))
    push = heapq.heappush
    pop = heapq.heappop
    while h:
        d, i = pop(h)
        if d > dist[i]:
            continue
        for j, c in adj[i]:
            nd = d + c
            if nd < dist[j]:
                dist[j] = nd
                push(h, (nd, j))
    return dist


def articulation_points(nodes, adj):
    """Iterative Tarjan articulation points. adj: node -> set of nodes."""
    disc = {}
    low = {}
    parent = {}
    aps = set()
    counter = [0]
    for root in nodes:
        if root in disc:
            continue
        root_children = 0
        parent[root] = -1
        disc[root] = low[root] = counter[0]
        counter[0] += 1
        stack = [(root, iter(sorted(adj.get(root, ()))))]
        while stack:
            u, it = stack[-1]
            advanced = False
            for v in it:
                if v not in disc:
                    parent[v] = u
                    if u == root:
                        root_children += 1
                    disc[v] = low[v] = counter[0]
                    counter[0] += 1
                    stack.append((v, iter(sorted(adj.get(v, ())))))
                    advanced = True
                    break
                elif v != parent[u] and disc[v] < low[u]:
                    low[u] = disc[v]
            if not advanced:
                stack.pop()
                if stack:
                    p = stack[-1][0]
                    if low[u] < low[p]:
                        low[p] = low[u]
                    if parent[p] != -1 and low[u] >= disc[p]:
                        aps.add(p)
        if root_children > 1:
            aps.add(root)
    return aps


# ---------------------------------------------------------------------------
# tripmine bypass (TERRAIN_SPEC section 6.8): H23, and the D1/D2 denominators.
# Brute force by construction: for a mine set M, remove the tiles and every
# jump/drop/pad edge whose horizontal segment passes within 0.9 u of a mine
# centre, then recompute the round-trip set from scratch.
# ---------------------------------------------------------------------------

MINE_SCALE = 10     # coordinates scaled by 10 so the 0.9 u test is integer-only
MINE_R2 = 81        # 0.9 u squared, in scaled coordinates


def seg_hits_mine(ax, az, bx, bz, mx, mz):
    """True iff the segment between tile centres (ax,az)-(bx,bz) passes within 0.9 u of (mx,mz).
    Clamp the projection parameter with integer dot products; compare 100*d^2 to 81*len^2 for an
    interior foot and d^2 to 81 for a foot at either endpoint."""
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


class MineJudge:
    """Independent brute-force judge for the tripmine bypass rule (spec 6.8.2-6.8.4).

    A slot tile m is ELIGIBLE iff the bypass graph B({m}) keeps every tile that was round-trip
    reachable in the full graph (except m itself) round-trip reachable. The JOINT RULE is the same
    statement for the level's whole mine set.
    """

    def __init__(self, base, adj, slot_tiles=None):
        self.base = base
        self.n = base["n"]
        self.tiles = base["tiles"]
        self.nb = neighbors(adj)
        self.nb_rev = [[] for _ in range(self.n)]
        for i in range(self.n):
            for j in self.nb[i]:
                self.nb_rev[j].append(i)
        self.beacon = find_tile(base, 0, 0, 1)
        self.slot_tiles = slot_tiles if slot_tiles is not None else []
        # every out-edge, walk included: the cylinder test is applied to all of them, never assumed
        self.out_edges = [[] for _ in range(self.n)]
        for i in range(self.n):
            for j in self.nb[i]:
                self.out_edges[i].append(j)
        # tile bucket by cell, so a slot only looks at the tiles an edge could start from
        self.cell = {}
        for i in range(self.n):
            c = (self.tiles[i][0], self.tiles[i][1])
            if c in self.cell:
                self.cell[c].append(i)
            else:
                self.cell[c] = [i]
        self._cross = {}
        self._elig = {}
        self._rt = None

    def rt_full(self):
        if self._rt is None:
            f = bfs(self.nb, [self.beacon])
            b = bfs(self.nb_rev, [self.beacon])
            self._rt = [f[i] and b[i] for i in range(self.n)]
        return self._rt

    def cross(self, m):
        """Every non-walk edge whose horizontal segment passes within 0.9 u of tile m's centre.
        A jump is at most 6 cells long, so its source tile is within Chebyshev 9 of m."""
        v = self._cross.get(m)
        if v is not None:
            return v
        mx = self.tiles[m][0]
        mz = self.tiles[m][1]
        out = []
        for ox in range(-9, 10):
            for oz in range(-9, 10):
                lst = self.cell.get((mx + ox, mz + oz))
                if lst is None:
                    continue
                for i in lst:
                    for j in self.out_edges[i]:
                        if seg_hits_mine(self.tiles[i][0], self.tiles[i][1],
                                         self.tiles[j][0], self.tiles[j][1], mx, mz):
                            out.append((i, j))
        self._cross[m] = out
        return out

    def _bfs(self, nb, blocked, blk):
        seen = bytearray(self.n)
        seen[self.beacon] = 1
        q = [self.beacon]
        h = 0
        while h < len(q):
            c = q[h]
            h += 1
            d = blk.get(c)
            for j in nb[c]:
                if seen[j] or blocked[j]:
                    continue
                if d is not None and j in d:
                    continue
                seen[j] = 1
                q.append(j)
        return seen

    def keeps_rt(self, mines):
        rt = self.rt_full()
        blocked = bytearray(self.n)
        blk_f = {}
        blk_b = {}
        for m in mines:
            mx = self.tiles[m][0]
            mz = self.tiles[m][1]
            for ox in (-1, 0, 1):
                for oz in (-1, 0, 1):
                    lst = self.cell.get((mx + ox, mz + oz))
                    if lst is None:
                        continue
                    for t in lst:
                        dx = MINE_SCALE * (self.tiles[t][0] - mx)
                        dz = MINE_SCALE * (self.tiles[t][1] - mz)
                        if dx * dx + dz * dz <= MINE_R2:
                            blocked[t] = 1
            for (i, j) in self.cross(m):
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
        # the beacon and every real gift slot must survive the cylinder: a gift inside it is
        # uncollectable, so a mine may never create one
        if blocked[self.beacon]:
            return False
        ms = {}
        for m in mines:
            ms[m] = 1
        for t in self.slot_tiles:
            if t not in ms and blocked[t]:
                return False
        need = sum(1 for i in range(self.n) if rt[i] and not blocked[i])
        f = self._bfs(self.nb, blocked, blk_f)
        cnt = 0
        for i in range(self.n):
            if rt[i] and not blocked[i] and f[i]:
                cnt += 1
        if cnt != need:
            return False
        b = self._bfs(self.nb_rev, blocked, blk_b)
        cnt = 0
        for i in range(self.n):
            if rt[i] and not blocked[i] and b[i]:
                cnt += 1
        return cnt == need

    def eligible(self, m):
        v = self._elig.get(m)
        if v is None:
            v = self.keeps_rt([m])
            self._elig[m] = v
        return v


def slot_tiles_of(L, base):
    """Tile index of every gift slot, in slot-id order (-1 when the slot is not on a tile)."""
    return [find_tile(base, g["x"], g["z"], g["y"]) for g in L["gifts"]]


# ---------------------------------------------------------------------------
# shape contract (TERRAIN_SPEC section 1A): walkways vs platforms, treads, flat
# runs, elevation variance, sub-area boundaries. Recomputed from the Level dict
# alone -- pieces and tiles, never generator internals.
# ---------------------------------------------------------------------------

def piece_tiles(L):
    """piece id -> tile indices, in tile order."""
    out = {}
    for i, t in enumerate(L["tiles"]):
        pid = t[4]
        if pid in out:
            out[pid].append(i)
        else:
            out[pid] = [i]
    return out


def bbox_of(tiles, idxs):
    x0 = z0 = 1 << 30
    x1 = z1 = -(1 << 30)
    for i in idxs:
        t = tiles[i]
        if t[0] < x0:
            x0 = t[0]
        if t[0] > x1:
            x1 = t[0]
        if t[1] < z0:
            z0 = t[1]
        if t[1] > z1:
            z1 = t[1]
    return x0, z0, x1, z1


def walkway_rows(tiles, idxs):
    """Rows of a straight walkway along its dominant axis.
    Returns (rows, width): rows = [(coord, y, has_ramp)] sorted by coord,
    width = most tiles sharing one row."""
    x0, z0, x1, z1 = bbox_of(tiles, idxs)
    axis = 0 if (x1 - x0) >= (z1 - z0) else 1
    groups = {}
    for i in idxs:
        t = tiles[i]
        c = t[0] if axis == 0 else t[1]
        g = groups.get(c)
        if g is None:
            groups[c] = [t[2], 1, 1 if t[3] else 0]
        else:
            g[1] += 1
            if t[3]:
                g[2] = 1
    rows = []
    width = 0
    for c in sorted(groups):
        g = groups[c]
        rows.append((c, g[0], g[2]))
        if g[1] > width:
            width = g[1]
    return rows, width


def flat_stats(rows):
    """(n_rows, flat_continuing, ramp_rows) for one walkway.
    A row is flat-continuing when it sits at position >= 3 inside its tread."""
    n = len(rows)
    flat = 0
    ramp = 0
    run_start = 0
    for k in range(n):
        if rows[k][2]:
            ramp += 1
        if k and rows[k][1] != rows[k - 1][1]:
            run_start = k
        if k - run_start >= 3:
            flat += 1
    return n, flat, ramp


def tread_heights(rows):
    """Height of each tread (maximal run of equal-height rows), in order."""
    out = []
    for k in range(len(rows)):
        if k == 0 or rows[k][1] != rows[k - 1][1]:
            out.append(rows[k][1])
    return out


def dy_hist(heights):
    """Histogram of |delta| between consecutive entries; bucket 4 means >= 4."""
    hist = {}
    for k in range(1, len(heights)):
        d = heights[k] - heights[k - 1]
        if d < 0:
            d = -d
        b = d if d < 4 else 4
        hist[b] = hist.get(b, 0) + 1
    return hist


def flat_components(base):
    """4-connected components of walkable tiles at one height.
    Returns (sizes, comp) with comp[i] = component id, or -1 if not walkable."""
    tiles = base["tiles"]
    col = base["col"]
    walkable = base["walkable"]
    n = base["n"]
    comp = [-1] * n
    sizes = []
    for i in range(n):
        if not walkable[i] or comp[i] >= 0:
            continue
        cid = len(sizes)
        comp[i] = cid
        y = tiles[i][2]
        q = [i]
        h = 0
        while h < len(q):
            c = q[h]
            h += 1
            t = tiles[c]
            for d in range(4):
                for j in col.get((t[0] + DX[d], t[1] + DZ[d]), ()):
                    if comp[j] < 0 and walkable[j] and tiles[j][2] == y:
                        comp[j] = cid
                        q.append(j)
        sizes.append(len(q))
    return sizes, comp


def junctions(base, walk_set, plat_set):
    """Sub-area boundaries: 4-adjacent (walkway tile, non-hub platform tile) pairs.
    Returns {(walk_pid, plat_pid): min |dy| over the pair's touching tiles}."""
    tiles = base["tiles"]
    col = base["col"]
    out = {}
    for i in range(base["n"]):
        t = tiles[i]
        pi = t[4]
        if pi not in walk_set:
            continue
        for d in range(4):
            for j in col.get((t[0] + DX[d], t[1] + DZ[d]), ()):
                pj = tiles[j][4]
                if pj not in plat_set:
                    continue
                dy = tiles[j][2] - t[2]
                if dy < 0:
                    dy = -dy
                key = (pi, pj)
                cur = out.get(key)
                if cur is None or dy < cur:
                    out[key] = dy
    return out


def shape_checks(L, base, hub_pid):
    """H16-H22 plus the shape metrics. Returns (fails, metrics)."""
    tiles = L["tiles"]
    pieces = L["pieces"]
    level = L["level"]
    fails = []
    m = {}

    pt = piece_tiles(L)
    walk_ids = [p["id"] for p in pieces if p["kind"] == 1]
    plat_ids = [p["id"] for p in pieces if p["kind"] == 0 and p["id"] != hub_pid]
    walk_set = set(walk_ids)
    plat_set = set(plat_ids)

    # ---- H16: spawn platform uniqueness and dominance ----
    sizes, comp = flat_components(base)
    hub_idxs = pt.get(hub_pid, [])
    hub_comp = -1
    for i in hub_idxs:
        if comp[i] >= 0:
            hub_comp = comp[i]
            break
    best = -1
    best_sz = -1
    second = -1
    for cid in range(len(sizes)):
        sz = sizes[cid]
        if sz > best_sz:
            second = best_sz
            best_sz = sz
            best = cid
        elif sz > second:
            second = sz
    hub_flat = sizes[hub_comp] if hub_comp >= 0 else 0
    if hub_pid < 0:
        fails.append("H16: no spawn platform (role 0) piece")
    elif hub_comp < 0:
        fails.append("H16: spawn platform has no walkable flat area")
    elif best != hub_comp:
        fails.append("H16: largest flat walkable area is %d tiles, spawn platform's is %d"
                     % (best_sz, hub_flat))
    elif second >= best_sz:
        fails.append("H16: another flat area ties the spawn platform at %d tiles" % best_sz)
    hub_dim = 0
    if hub_idxs:
        bb = bbox_of(tiles, hub_idxs)
        hub_dim = max(bb[2] - bb[0], bb[3] - bb[1]) + 1
    widest = 0
    widest_pid = -1
    for p in pieces:
        pid = p["id"]
        if pid == hub_pid or p["kind"] != 0:
            continue          # only areas compete with the spawn platform; a path is not an area
        idxs = pt.get(pid, [])
        if not idxs:
            continue
        bb = bbox_of(tiles, idxs)
        d = max(bb[2] - bb[0], bb[3] - bb[1]) + 1
        if d > widest:
            widest = d
            widest_pid = pid
        if len(idxs) >= hub_flat:
            fails.append("H16: platform %d has %d tiles, spawn platform's flat area is %d"
                         % (pid, len(idxs), hub_flat))
    if widest >= hub_dim:
        fails.append("H16: piece %d is %d cells wide, spawn platform is %d"
                     % (widest_pid, widest, hub_dim))

    # ---- H17: max walkway width ----
    maxw = 0
    maxw_pid = -1
    walk_rows = {}
    for pid in walk_ids:
        rows, w = walkway_rows(tiles, pt[pid])
        walk_rows[pid] = rows
        if w > maxw:
            maxw = w
            maxw_pid = pid
    if maxw > MAX_WALK_W:
        fails.append("H17: walkway %d is %d cells wide (max %d)"
                     % (maxw_pid, maxw, MAX_WALK_W))

    # ---- H18: platform size and count bounds ----
    pm = plat_max(level)
    nplat = len(plat_ids)
    if nplat < PLAT_MIN:
        fails.append("H18: %d platforms < %d" % (nplat, PLAT_MIN))
    if nplat > pm:
        fails.append("H18: %d platforms > plat_max(level=%d)=%d" % (nplat, level, pm))
    for pid in plat_ids:
        idxs = pt[pid]
        bb = bbox_of(tiles, idxs)
        dim = max(bb[2] - bb[0], bb[3] - bb[1]) + 1
        if dim > MAX_PLAT_DIM:
            fails.append("H18: platform %d bbox %d cells > %d"
                         % (pid, dim, MAX_PLAT_DIM))
            break
        if len(idxs) > MAX_PLAT_TILES:
            fails.append("H18: platform %d has %d tiles > %d"
                         % (pid, len(idxs), MAX_PLAT_TILES))
            break

    # ---- H19: path share ----
    walk_len = 0
    w1_len = 0
    for pid in walk_ids:
        rows = walk_rows[pid]
        walk_len += len(rows)
        if len(rows) and len(pt[pid]) == len(rows):
            w1_len += len(rows)
    plat_len = 0
    for pid in plat_ids:
        bb = bbox_of(tiles, pt[pid])
        plat_len += max(bb[2] - bb[0], bb[3] - bb[1]) + 1
    total_len = walk_len + plat_len
    path_share = (walk_len / float(total_len)) if total_len else 0.0
    walk_tiles = 0
    for pid in walk_ids:
        walk_tiles += len(pt[pid])
    plat_tiles = 0
    for pid in plat_ids:
        plat_tiles += len(pt[pid])
    nonhub_tiles = walk_tiles + plat_tiles
    path_tile_share = (walk_tiles / float(nonhub_tiles)) if nonhub_tiles else 0.0
    if path_share < PATH_SHARE_MIN:
        fails.append("H19: path share %.3f < %.2f (%d of %d length)"
                     % (path_share, PATH_SHARE_MIN, walk_len, total_len))
    if path_tile_share < PATH_TILE_MIN:
        fails.append("H19: path tile share %.3f < %.2f (%d of %d tiles)"
                     % (path_tile_share, PATH_TILE_MIN, walk_tiles, nonhub_tiles))

    # ---- H20: flat-share and ramp-share caps ----
    rows_n = 0
    flat_n = 0
    ramp_n = 0
    tread_hist = {}
    for pid in walk_ids:
        a, b, c = flat_stats(walk_rows[pid])
        rows_n += a
        flat_n += b
        ramp_n += c
        h = dy_hist(tread_heights(walk_rows[pid]))
        for k in h:
            tread_hist[k] = tread_hist.get(k, 0) + h[k]
    flat_share = (flat_n / float(rows_n)) if rows_n else 0.0
    ramp_share = (ramp_n / float(rows_n)) if rows_n else 0.0
    if flat_share > FLAT_SHARE_MAX:
        fails.append("H20: flat share %.3f > %.2f (%d of %d path rows)"
                     % (flat_share, FLAT_SHARE_MAX, flat_n, rows_n))
    if ramp_share > RAMP_SHARE_MAX:
        fails.append("H20: ramp share %.3f > %.2f (%d of %d path rows)"
                     % (ramp_share, RAMP_SHARE_MAX, ramp_n, rows_n))

    # ---- H21: elevation variance floor ----
    ys = []
    for t in tiles:
        if t[4] != hub_pid:
            ys.append(t[2])
    if ys:
        mean = sum(ys) / float(len(ys))
        var = 0.0
        for y in ys:
            var += (y - mean) * (y - mean)
        sd = (var / float(len(ys))) ** 0.5
    else:
        sd = 0.0
    floor = elev_var_floor(level)
    if sd < floor:
        fails.append("H21: elevation sd %.2f < floor %d HU at level %d"
                     % (sd, floor, level))

    # ---- H22: sub-area boundaries step ----
    jn = junctions(base, walk_set, plat_set)
    stepped = 0
    jhist = {}
    for key in jn:
        d = jn[key]
        if d >= 1:
            stepped += 1
        b = d if d < 4 else 4
        jhist[b] = jhist.get(b, 0) + 1
    jstep = (stepped / float(len(jn))) if jn else 0.0
    if jstep < JUNCTION_STEP_MIN:
        fails.append("H22: %d of %d sub-area boundaries step (%.3f < %.2f)"
                     % (stepped, len(jn), jstep, JUNCTION_STEP_MIN))

    m["platforms"] = nplat
    m["walkways"] = len(walk_ids)
    m["path_share"] = round(path_share, 4)
    m["path_tile_share"] = round(path_tile_share, 4)
    m["flat_share"] = round(flat_share, 4)
    m["ramp_share"] = round(ramp_share, 4)
    m["elev_var"] = round(sd, 4)
    m["junction_step_pct"] = round(100.0 * jstep, 4)
    m["N"] = round((100.0 * w1_len / walk_len) if walk_len else 0.0, 4)
    m["hub_dim"] = hub_dim
    m["hub_flat"] = hub_flat
    m["max_walk_w"] = maxw
    m["tread_dy_hist"] = tread_hist
    m["junction_dy_hist"] = jhist
    return fails, m


# ---------------------------------------------------------------------------
# check_level
# ---------------------------------------------------------------------------

def check_level(L):
    """Judge one Level dict. Returns {"fails": ["H<id>: msg", ...], "metrics": {...}}."""
    fails = []
    metrics = {}
    level = L["level"]
    players = L["players"]
    gifts = L["gifts"]
    pieces = L["pieces"]
    S = len(gifts)

    def fail(msg):
        fails.append(msg)

    hub_pid = -1
    for p in pieces:
        if p["role"] == 0:
            hub_pid = p["id"]
            break

    # ---- H2: slot count ----
    st = slot_target(level, players)
    if S != st:
        fail("H2: %d slots != slot_target(level=%d, players=%d)=%d"
             % (S, level, players, st))

    # ---- graphs ----
    base = walk_layer(L)
    n = base["n"]
    walkable = base["walkable"]
    adj = build_adj(L, base, VALIDATOR_GAP)
    nb_full = neighbors(adj)
    nb_rev = [[] for _ in range(n)]
    for i in range(n):
        for j in nb_full[i]:
            nb_rev[j].append(i)
    beacon = find_tile(base, 0, 0, 1)
    graph_ok = beacon >= 0 and walkable[beacon]
    fwd = back = None
    rt = bytearray(n)
    if graph_ok:
        fwd = bfs(nb_full, [beacon])
        back = bfs(nb_rev, [beacon])
        for i in range(n):
            if fwd[i] and back[i]:
                rt[i] = 1

    # per-gift tile indices (reused by several checks / metrics)
    gtile = [find_tile(base, g["x"], g["z"], g["y"]) for g in gifts]
    prop_at = {}
    for p in L["props"]:
        prop_at.setdefault((p[0], p[1]), []).append(p)
    padset = set()
    for p in L["pads"]:
        padset.add((p[0], p[1], p[2]))
    roles = [p["role"] for p in pieces] if pieces else []

    # ---- H8: hub intact ----
    h8 = []
    if hub_pid < 0:
        h8.append("no hub piece")
    else:
        hub_tiles = sum(1 for t in L["tiles"] if t[4] == hub_pid)
        if hub_tiles != HUB_TILES:
            h8.append("hub has %d tiles (want %d)" % (hub_tiles, HUB_TILES))
    if beacon < 0:
        h8.append("beacon tile (0,0,1) missing")
    elif not walkable[beacon]:
        h8.append("beacon tile (0,0,1) not walkable")
    for sp in L["spawns"]:
        b = find_tile(base, sp[0], sp[1], sp[2])
        if b < 0:
            h8.append("spawn tile (%d,%d,%d) missing" % (sp[0], sp[1], sp[2]))
        elif not walkable[b]:
            h8.append("spawn tile (%d,%d,%d) not walkable" % (sp[0], sp[1], sp[2]))
    if h8:
        fail("H8: " + "; ".join(h8[:4]))

    # ---- H7: column clearance ----
    bad_cols = 0
    bad_ex = None
    for c, lst in base["col"].items():
        if len(lst) > 1:
            ys = sorted(base["tiles"][i][2] for i in lst)
            for k in range(1, len(ys)):
                if ys[k] - ys[k - 1] < CLEAR:
                    bad_cols += 1
                    if bad_ex is None:
                        bad_ex = (c[0], c[1], ys[k - 1], ys[k])
                    break
    if bad_cols:
        fail("H7: %d columns with tiles < %d HU apart (first at (%d,%d): %d vs %d)"
             % (bad_cols, CLEAR, bad_ex[0], bad_ex[1], bad_ex[2], bad_ex[3]))

    # ---- H6: soft-lock tiles ----
    soft = 0
    soft_ex = None
    if graph_ok:
        for i in range(n):
            if fwd[i] and not back[i]:
                soft += 1
                if soft_ex is None:
                    soft_ex = base["tiles"][i]
        if soft:
            fail("H6: %d soft-lock tiles (first at (%d,%d,%d))"
                 % (soft, soft_ex[0], soft_ex[1], soft_ex[2]))

    # ---- H3: every slot on a valid, distinct, round-trip tile ----
    bad3 = 0
    ex3 = None
    seen_cols = set()
    for gi, g in enumerate(gifts):
        t = gtile[gi]
        col_key = (g["x"], g["z"])
        dup = col_key in seen_cols
        seen_cols.add(col_key)
        ok = False
        if t >= 0 and not dup:
            tile = base["tiles"][t]
            pid = tile[4]
            on_dais = pid == hub_pid and tile[2] == 1
            on_pad = (g["x"], g["z"], g["y"]) in padset
            has_prop = False
            for p in prop_at.get((g["x"], g["z"]), ()):
                if p[2] == tile[2]:
                    has_prop = True
                    break
            if (tile[3] == 0 and not has_prop and not on_dais and not on_pad
                    and rt[t]):
                ok = True
        if not ok:
            bad3 += 1
            if ex3 is None:
                ex3 = (g["id"], g["x"], g["z"], g["y"],
                       "duplicate column" if dup else "invalid/reachable tile")
    if bad3:
        fail("H3: %d bad slots (first id=%d at (%d,%d,%d): %s)"
             % (bad3, ex3[0], ex3[1], ex3[2], ex3[3], ex3[4]))

    # ---- H4: clearance above every slot ----
    bad4 = 0
    ex4 = None
    for gi, g in enumerate(gifts):
        y = g["y"]
        hit = None
        if gtile[gi] >= 0:
            for i in base["col"].get((g["x"], g["z"]), ()):
                ty = base["tiles"][i][2]
                if y < ty < y + 12:
                    hit = ("tile at y=%d" % ty)
                    break
        if hit is None:
            for p in prop_at.get((g["x"], g["z"]), ()):
                if p[2] >= y and p[2] < y + 12:
                    hit = "prop base y=%d h=%d" % (p[2], p[3])
                    break
        if hit is not None:
            bad4 += 1
            if ex4 is None:
                ex4 = (g["id"], g["x"], g["z"], y, hit)
    if bad4:
        fail("H4: %d slots with < 12 HU headroom (first id=%d at (%d,%d,%d): %s)"
             % (bad4, ex4[0], ex4[1], ex4[2], ex4[3], ex4[4]))

    # ---- H5: mine caps ----
    mines = sum(1 for g in gifts if g["occ"])
    cap = S // 5
    h5 = []
    if mines > cap:
        h5.append("mines %d > S//5 %d" % (mines, cap))
    if level < 5 and mines:
        h5.append("mines %d at level %d < 5" % (mines, level))
    if S - mines < S - cap:
        h5.append("real gifts %d < %d" % (S - mines, S - cap))
    if h5:
        fail("H5: " + "; ".join(h5))

    # ---- H9: playable area ----
    walk_count = sum(1 for i in range(n) if walkable[i])
    rt_count = sum(1 for i in range(n) if rt[i])
    playable_pct = (100.0 * rt_count / walk_count) if walk_count else 0.0
    if playable_pct < 98.0:
        fail("H9: playable %.3f%% < 98%% (%d/%d tiles)"
             % (playable_pct, rt_count, walk_count))

    # ---- H10 / H11: distances to real gifts ----
    real_tiles = sorted(set(t for gi, g in enumerate(gifts)
                            if g["occ"] == 0 and gtile[gi] >= 0
                            for t in (gtile[gi],)))
    first_gift = None
    starve_p95 = None
    starve_max = None
    if graph_ok and real_tiles:
        dist_b = dijkstra(adj, [beacon], n)
        first_gift = min(dist_b[t] for t in real_tiles)
        if first_gift >= INF:
            fail("H10: no real gift is path-reachable from the beacon")
        elif first_gift > 30:
            fail("H10: first gift at distance %d > 30" % first_gift)
        rev = reversed_adj(adj, n)
        dist_g = dijkstra(rev, real_tiles, n)
        vals = sorted(dist_g[i] for i in range(n) if rt[i])
        if vals:
            p95 = vals[(95 * (len(vals) - 1)) // 100]
            vmax = vals[-1]
            n_inf = sum(1 for v in vals if v >= INF)
            h11 = []
            if n_inf:
                h11.append("%d rt tiles cannot reach any real gift" % n_inf)
            if p95 < INF:
                starve_p95 = p95
            if vmax < INF:
                starve_max = vmax
            if not n_inf:
                if p95 > 27:
                    h11.append("starve_p95=%d > 27" % p95)
                if vmax > 54:
                    h11.append("starve_max=%d > 54" % vmax)
            if h11:
                fail("H11: " + "; ".join(h11))
    elif graph_ok:
        fail("H10: no real gift on an existing tile")
    if starve_p95 is None:
        starve_p95 = BIG
    if starve_max is None:
        starve_max = BIG
    if first_gift is None:
        first_gift = BIG

    # ---- H12: structure ----
    room_pieces = [p for p in pieces if p["kind"] == 0 and p["role"] != 0]
    dead_ends = [p for p in pieces if p["kind"] == 0 and p["role"] == 2]
    loop_pieces = [p for p in pieces if p["role"] in (4, 5)]
    loops = sum(1 for p in pieces if p["role"] == 4)
    drops = sum(1 for p in pieces if p["role"] == 5)
    arms_n = len(L["arms"])
    max_depth = max((p["depth"] for p in pieces), default=0)
    h12 = []
    if arms_n < 2:
        h12.append("arms %d < 2" % arms_n)
    if len(dead_ends) < 2:
        h12.append("dead-end rooms %d < 2" % len(dead_ends))
    if len(room_pieces) < plat_max(level) - 1:
        h12.append("platforms %d < plat_max(level=%d)-1 = %d"
                   % (len(room_pieces), level, plat_max(level) - 1))
    if max_depth < 3:
        h12.append("max piece depth %d < 3" % max_depth)
    if h12:
        fail("H12: " + "; ".join(h12))

    # ---- H14: shortcuts ----
    if loops + drops < 1:
        fail("H14: no shortcuts (0 loop bridges, 0 drop ledges)")

    # ---- H13: authoring-envelope round trip for every slot ----
    adj_auth = build_adj(L, base, AUTHORING_GAP)
    nb_auth = neighbors(adj_auth)
    nb_auth_rev = [[] for _ in range(n)]
    for i in range(n):
        for j in nb_auth[i]:
            nb_auth_rev[j].append(i)
    bad13 = 0
    ex13 = None
    if graph_ok:
        f13 = bfs(nb_auth, [beacon])
        b13 = bfs(nb_auth_rev, [beacon])
        for gi, g in enumerate(gifts):
            t = gtile[gi]
            if t < 0 or not f13[t] or not b13[t]:
                bad13 += 1
                if ex13 is None:
                    ex13 = g
        if bad13:
            fail("H13: %d slots not round-trip reachable at authoring gap %s "
                 "(first id=%d at (%d,%d,%d))"
                 % (bad13, AUTHORING_GAP, ex13["id"], ex13["x"], ex13["z"], ex13["y"]))

    # ---- H16-H22: shape contract ----
    shape_fails, shape_m = shape_checks(L, base, hub_pid)
    for msg in shape_fails:
        fail(msg)
    N = shape_m["N"]

    # ---- H23: no tripmine without a walkable bypass (spec 6.8) ----
    mine_slots = [gi for gi, g in enumerate(gifts) if g["occ"]]
    eligible_slots = 0
    if S:
        judge = MineJudge(base, adj, [t for t in gtile if t >= 0])
        mine_tiles = []
        bad23 = []
        for gi in mine_slots:
            t = gtile[gi]
            if t < 0:
                bad23.append((gi, "mine slot is not on an existing tile"))
                continue
            mine_tiles.append(t)
            if not judge.eligible(t):
                bad23.append((gi, "no walkable bypass: removing the mine's trigger cylinder (its "
                                  "tile, every tile in its column, and every edge that crosses it) "
                                  "disconnects a round-trip tile or swallows another gift"))
        if mine_tiles and not bad23:
            if not judge.keeps_rt(mine_tiles):
                bad23.append((-1, "joint rule: the level's mine set seals off a round-trip tile"))
        if bad23:
            gi, why = bad23[0]
            where = ("slot id=%d at (%d,%d,%d)" % (gi, gifts[gi]["x"], gifts[gi]["z"], gifts[gi]["y"])
                     if gi >= 0 else "mine set")
            fail("H23: %d bad mines (first %s: %s)" % (len(bad23), where, why))
        # D1 denominator: the number of slots that can hold a mine at all
        for gi in range(S):
            t = gtile[gi]
            if t >= 0 and judge.eligible(t):
                eligible_slots += 1

    # ---- metrics ----
    chokepoints = 0
    pg = {}
    for e in L["edges"]:
        pg.setdefault(e[0], set()).add(e[1])
        pg.setdefault(e[1], set()).add(e[0])
    aps = articulation_points(list(pg.keys()), pg)
    for pid in aps:
        p = pieces[pid]
        if p["kind"] == 1 and p["w"] <= 2:
            chokepoints += 1
    link_pieces = [p for p in pieces if p["kind"] == 1]

    walk_nbrs = [sorted(s) if s else [] for s in base["wn"]]
    walk_rev = [[] for _ in range(n)]
    for i in range(n):
        for j in walk_nbrs[i]:
            walk_rev[j].append(i)
    jump_slots = S
    if graph_ok:
        wfw = bfs(walk_nbrs, [beacon])
        wbk = bfs(walk_rev, [beacon])
        jump_slots = 0
        for gi, g in enumerate(gifts):
            t = gtile[gi]
            if t < 0 or not (wfw[t] and wbk[t]):
                jump_slots += 1
    J = (100.0 * jump_slots / S) if S else 0.0

    ys_all = [t[2] for t in L["tiles"]]
    V = ((max(ys_all) - min(ys_all)) / 2.0) if ys_all else 0.0
    K = 0.0
    if S:
        K = sum(pieces[g["piece"]]["depth"] for g in gifts) / float(S)
    gift_density = (100.0 * (S - mines) / walk_count) if walk_count else 0.0
    D = J + 0.5 * N + V + 0.25 * S + 2.0 * K

    metrics["walkable"] = walk_count
    metrics["playable_pct"] = round(playable_pct, 4)
    metrics["platforms"] = len(room_pieces)
    metrics["walkways"] = len(link_pieces)
    metrics["dead_ends"] = len(dead_ends)
    metrics["max_depth"] = max_depth
    metrics["arms"] = arms_n
    metrics["loops"] = loops
    metrics["drops"] = drops
    metrics["pads"] = len(L["pads"])
    metrics["chokepoints"] = chokepoints
    metrics["J"] = round(J, 4)
    metrics["N"] = round(N, 4)
    metrics["V"] = round(V, 4)
    metrics["K"] = round(K, 4)
    metrics["gift_density"] = round(gift_density, 4)
    metrics["eligible_slots"] = eligible_slots
    metrics["mines"] = mines
    metrics["first_gift"] = first_gift
    metrics["starve_p95"] = starve_p95
    metrics["starve_max"] = starve_max
    metrics["path_share"] = shape_m["path_share"]
    metrics["path_tile_share"] = shape_m["path_tile_share"]
    metrics["flat_share"] = shape_m["flat_share"]
    metrics["ramp_share"] = shape_m["ramp_share"]
    metrics["elev_var"] = shape_m["elev_var"]
    metrics["junction_step_pct"] = shape_m["junction_step_pct"]
    metrics["hub_dim"] = shape_m["hub_dim"]
    metrics["hub_flat"] = shape_m["hub_flat"]
    metrics["max_walk_w"] = shape_m["max_walk_w"]
    metrics["tread_dy_hist"] = shape_m["tread_dy_hist"]
    metrics["junction_dy_hist"] = shape_m["junction_dy_hist"]
    metrics["D"] = round(D, 4)
    return {"fails": fails, "metrics": metrics}


# ---------------------------------------------------------------------------
# selftest: planted defects (spec 10.5)
# ---------------------------------------------------------------------------

def _defect_slot_on_prop(L):
    g = L["gifts"][0]
    if L["props"]:
        p = L["props"][0]
        g["x"], g["z"], g["y"] = p[0], p[1], p[2]
    else:
        L["props"].append([g["x"], g["z"], g["y"], 4, 0, g["piece"]])


def _defect_slot_isolated(L):
    g = L["gifts"][0]
    L["tiles"].append([200, 200, 0, 0, g["piece"]])
    g["x"], g["z"], g["y"] = 200, 200, 0


def _defect_tile_4hu_above(L):
    t = L["tiles"][0]
    L["tiles"].append([t[0], t[1], t[2] + 4, 0, t[4]])


def _defect_too_many_mines(L):
    S = len(L["gifts"])
    cap = S // 5
    flipped = 0
    for g in L["gifts"]:
        if flipped > cap:
            break
        if g["occ"] == 0:
            g["occ"] = 1
            flipped += 1


def _defect_drop_only_ledge(L):
    """Append a 2x2 tile group 20 HU below a reachable boundary tile, in an
    empty pocket: forward-reachable via a drop from the boundary tile, with no
    walk or jump edge back out. Soft-lock -> H6 must fire."""
    base = walk_layer(L)
    adj = build_adj(L, base, VALIDATOR_GAP)
    nb = neighbors(adj)
    nb_rev = [[] for _ in range(base["n"])]
    for i in range(base["n"]):
        for j in nb[i]:
            nb_rev[j].append(i)
    beacon = find_tile(base, 0, 0, 1)
    fwd = bfs(nb, [beacon])
    back = bfs(nb_rev, [beacon])
    tiles = base["tiles"]
    for i in range(base["n"]):
        if not (base["walkable"][i] and base["boundary"][i] and fwd[i] and back[i]):
            continue
        bx, bz, by = tiles[i][0], tiles[i][1], tiles[i][2]
        for d in range(4):
            lat = (d + 1) % 4
            ny = by - 20
            cells = ((bx + DX[d], bz + DZ[d]),
                     (bx + DX[d] + DX[lat], bz + DZ[d] + DZ[lat]),
                     (bx + DX[d] + DX[d], bz + DZ[d] + DZ[d]),
                     (bx + DX[d] + DX[d] + DX[lat],
                      bz + DZ[d] + DZ[d] + DZ[lat]))
            ok = True
            for gx, gz in cells:
                if base["col"].get((gx, gz)):
                    ok = False
                    break
                for t2 in tiles:
                    cd = max(abs(t2[0] - gx), abs(t2[1] - gz))
                    if cd <= 7 and abs(t2[2] - ny) <= 4:
                        ok = False
                        break
                    if cd <= 6 and ny - 60 <= t2[2] <= ny - 4:
                        ok = False
                        break
                if not ok:
                    break
            if ok:
                pid = tiles[i][4]
                for gx, gz in cells:
                    L["tiles"].append([gx, gz, ny, 0, pid])
                return
    raise RuntimeError("selftest defect e: no valid pocket found in level")


def _defect_second_hub(L):
    """H16: a second flat area as large as the spawn platform."""
    hub = -1
    for p in L["pieces"]:
        if p["role"] == 0:
            hub = p["id"]
            break
    pid = len(L["pieces"])
    L["pieces"].append({"id": pid, "kind": 0, "arch": "pad", "parent": hub, "depth": 1,
                        "arm": 0, "role": 1, "y": 0, "center": [], "jumps": 0, "w": 0})
    for t in list(L["tiles"]):
        if t[4] == hub:
            L["tiles"].append([t[0] + 200, t[1] + 200, t[2], t[3], pid])


def _defect_wide_walkway(L):
    """H17: a walkway three cells wide."""
    pt = piece_tiles(L)
    for p in L["pieces"]:
        if p["kind"] != 1:
            continue
        idxs = pt[p["id"]]
        rows, w = walkway_rows(L["tiles"], idxs)
        if w != 1 or len(rows) < 3:
            continue
        x0, z0, x1, z1 = bbox_of(L["tiles"], idxs)
        axis = 0 if (x1 - x0) >= (z1 - z0) else 1
        mid = rows[len(rows) // 2]
        for i in idxs:
            t = L["tiles"][i]
            c = t[0] if axis == 0 else t[1]
            if c != mid[0]:
                continue
            lat = 1 if axis == 0 else 0
            for o in (1, 2):
                nx = t[0] + (o if lat == 0 else 0)
                nz = t[1] + (o if lat == 1 else 0)
                L["tiles"].append([nx, nz, t[2], 0, p["id"]])
            return


def _defect_big_platform(L):
    """H18: a 9x9 platform, over the 7x7 / 40-tile cap."""
    pid = len(L["pieces"])
    L["pieces"].append({"id": pid, "kind": 0, "arch": "pad", "parent": 0, "depth": 1,
                        "arm": 0, "role": 1, "y": 0, "center": [], "jumps": 0, "w": 0})
    for x in range(9):
        for z in range(9):
            L["tiles"].append([200 + x, 200 + z, 0, 0, pid])


def _defect_no_paths(L):
    """H19: every walkway relabelled as a platform, so the path share collapses."""
    for p in L["pieces"]:
        if p["kind"] == 1:
            p["kind"] = 0


def _defect_flat_paths(L):
    """H20: every walkway flattened to its first row's height."""
    pt = piece_tiles(L)
    for p in L["pieces"]:
        if p["kind"] != 1:
            continue
        idxs = pt[p["id"]]
        rows, w = walkway_rows(L["tiles"], idxs)
        if not rows:
            continue
        y = rows[0][1]
        for i in idxs:
            L["tiles"][i][2] = y


def _defect_flat_level(L):
    """H21: every non-hub tile at one height, so the elevation variance is zero."""
    hub = -1
    for p in L["pieces"]:
        if p["role"] == 0:
            hub = p["id"]
            break
    for t in L["tiles"]:
        if t[4] != hub:
            t[2] = 0


def _defect_flush_junctions(L):
    """H22: every platform levelled with the walkway it touches, so no boundary steps."""
    pt = piece_tiles(L)
    tiles = L["tiles"]
    col = {}
    for i, t in enumerate(tiles):
        col.setdefault((t[0], t[1]), []).append(i)
    hub = -1
    for p in L["pieces"]:
        if p["role"] == 0:
            hub = p["id"]
            break
    for p in L["pieces"]:
        if p["kind"] != 0 or p["id"] == hub:
            continue
        idxs = pt[p["id"]]
        y = None
        for i in idxs:
            t = tiles[i]
            for d in range(4):
                for j in col.get((t[0] + DX[d], t[1] + DZ[d]), ()):
                    if tiles[j][4] != p["id"] and L["pieces"][tiles[j][4]]["kind"] == 1:
                        y = tiles[j][2]
                        break
                if y is not None:
                    break
            if y is not None:
                break
        if y is None:
            continue
        for i in idxs:
            tiles[i][2] = y


def _defect_mine_no_bypass(L):
    """H23: flip occ to 1 on a slot whose tile has no walkable bypass (a 1-wide walkway tile)."""
    base = walk_layer(L)
    adj = build_adj(L, base, VALIDATOR_GAP)
    judge = MineJudge(base, adj, [t for t in slot_tiles_of(L, base) if t >= 0])
    S = len(L["gifts"])
    cap = S // 5
    target = -1
    for gi, g in enumerate(L["gifts"]):
        t = find_tile(base, g["x"], g["z"], g["y"])
        if t >= 0 and not judge.eligible(t):
            target = gi
            break
    if target < 0:
        raise RuntimeError("selftest defect: no ineligible slot in the level")
    mines = sum(1 for g in L["gifts"] if g["occ"])
    i = S - 1
    while mines >= cap and i >= 0:
        if L["gifts"][i]["occ"] and i != target:
            L["gifts"][i]["occ"] = 0
            mines -= 1
        i -= 1
    L["gifts"][target]["occ"] = 1


def _defect_mine_cylinder_swallows_gift(L):
    """H23 (cylinder rule): a mine whose trigger cylinder swallows another gift slot. Another tile in
    the mine's column becomes a slot, so the gift there is uncollectable; the mine tile alone has a
    fine bypass, so only the cylinder rule catches this."""
    base = walk_layer(L)
    adj = build_adj(L, base, VALIDATOR_GAP)
    st = slot_tiles_of(L, base)
    judge = MineJudge(base, adj, [t for t in st if t >= 0])
    tiles = base["tiles"]
    S = len(L["gifts"])
    cap = S // 5
    col = {}
    for i in range(base["n"]):
        col.setdefault((tiles[i][0], tiles[i][1]), []).append(i)
    target = -1
    above = -1
    for gi in range(S):
        t = st[gi]
        if t < 0 or not judge.eligible(t):
            continue
        for u in col[(tiles[t][0], tiles[t][1])]:
            if u != t:
                target = gi
                above = u
                break
        if target >= 0:
            break
    if target < 0:
        raise RuntimeError("selftest defect: no eligible slot with another tile in its column")
    mover = S - 1
    while mover == target:
        mover -= 1
    L["gifts"][mover]["x"] = tiles[above][0]
    L["gifts"][mover]["z"] = tiles[above][1]
    L["gifts"][mover]["y"] = tiles[above][2]
    mines = sum(1 for g in L["gifts"] if g["occ"])
    i = S - 1
    while mines >= cap and i >= 0:
        if L["gifts"][i]["occ"] and i != target and i != mover:
            L["gifts"][i]["occ"] = 0
            mines -= 1
        i -= 1
    L["gifts"][target]["occ"] = 1
    L["gifts"][mover]["occ"] = 1


def _defect_two_mines_seal(L):
    """H23 (joint rule): two mines side by side seal a 2-wide walkway. Each is eligible alone.
    Gift slots are never 4-adjacent (placement keeps them 2 apart), so the defect moves the
    highest-id slot onto the tile beside another slot before flipping both to occ = 1."""
    base = walk_layer(L)
    adj = build_adj(L, base, VALIDATOR_GAP)
    judge = MineJudge(base, adj, [t for t in slot_tiles_of(L, base) if t >= 0])
    tiles = base["tiles"]
    S = len(L["gifts"])
    cap = S // 5
    rt = judge.rt_full()
    slot_cols = set((g["x"], g["z"]) for g in L["gifts"])
    padset = set((p[0], p[1], p[2]) for p in L["pads"])
    prop_at = set((p[0], p[1], p[2]) for p in L["props"])
    hub = -1
    for p in L["pieces"]:
        if p["role"] == 0:
            hub = p["id"]
            break
    pair = None
    for gi, g in enumerate(L["gifts"]):
        t = find_tile(base, g["x"], g["z"], g["y"])
        if t < 0 or not judge.eligible(t):
            continue
        for d in range(4):
            u = find_tile(base, tiles[t][0] + DX[d], tiles[t][1] + DZ[d], tiles[t][2])
            if u < 0 or not rt[u] or not base["walkable"][u]:
                continue
            tu = tiles[u]
            if tu[3] != 0 or (tu[0], tu[1]) in slot_cols:
                continue
            if (tu[0], tu[1], tu[2]) in padset or (tu[0], tu[1], tu[2]) in prop_at:
                continue
            if tu[4] == hub and tu[2] == 1:
                continue
            if not judge.eligible(u):
                continue
            if not judge.keeps_rt([t, u]):
                pair = (gi, u)
                break
        if pair is not None:
            break
    if pair is None:
        raise RuntimeError("selftest defect: no adjacent slot pair breaks the joint rule")
    gi, u = pair
    # move the highest-id slot that is not `gi` onto tile u, then flip both to occ = 1
    mover = S - 1
    while mover == gi:
        mover -= 1
    tu = tiles[u]
    L["gifts"][mover]["x"] = tu[0]
    L["gifts"][mover]["z"] = tu[1]
    L["gifts"][mover]["y"] = tu[2]
    L["gifts"][mover]["piece"] = tu[4]
    mines = sum(1 for g in L["gifts"] if g["occ"])
    i = S - 1
    while mines >= cap and i >= 0:
        if L["gifts"][i]["occ"] and i not in (gi, mover):
            L["gifts"][i]["occ"] = 0
            mines -= 1
        i -= 1
    L["gifts"][gi]["occ"] = 1
    L["gifts"][mover]["occ"] = 1


def run_selftest():
    L = generate(5, 12)
    defects = (
        ("slot on a prop tile", _defect_slot_on_prop, "H3"),
        ("slot on isolated far tile", _defect_slot_isolated, "H3"),
        ("tile 4 HU above another", _defect_tile_4hu_above, "H7"),
        ("mine cap exceeded", _defect_too_many_mines, "H5"),
        ("drop-only ledge group", _defect_drop_only_ledge, "H6"),
        ("second area as large as the hub", _defect_second_hub, "H16"),
        ("walkway three cells wide", _defect_wide_walkway, "H17"),
        ("9x9 platform", _defect_big_platform, "H18"),
        ("no walkways left", _defect_no_paths, "H19"),
        ("every path flattened", _defect_flat_paths, "H20"),
        ("every non-hub tile at one height", _defect_flat_level, "H21"),
        ("every platform flush with its path", _defect_flush_junctions, "H22"),
        ("mine on a tile with no walkable bypass", _defect_mine_no_bypass, "H23"),
        ("two mines sealing a 2-wide walkway", _defect_two_mines_seal, "H23"),
        ("mine whose cylinder swallows another gift", _defect_mine_cylinder_swallows_gift, "H23"),
    )
    ok = 0
    for name, fn, hid in defects:
        Lc = copy.deepcopy(L)
        fn(Lc)
        ids = [f.split(":", 1)[0] for f in check_level(Lc)["fails"]]
        if hid in ids:
            ok += 1
        else:
            print("selftest: defect '%s' did NOT trigger %s (got %r)"
                  % (name, hid, ids))
    print("SELFTEST %d/%d" % (ok, len(defects)))
    return ok == len(defects)


# ---------------------------------------------------------------------------
# harness helpers (top level: Windows multiprocessing pickles these)
# ---------------------------------------------------------------------------

def footprint_blocks(tiles, beacon=(0, 0), xf=0):
    """Footprint (TERRAIN_SPEC 10.3, DECISIONS D-022): 4-cell blocks, hub tiles
    (piece id 0) excluded. Coordinates are first ANCHORED TO THE SPAWN ROOT (taken
    relative to the beacon tile), then dihedral transform `xf` (index into XFORMS)
    is applied to the TILE coordinates, then they are blocked."""
    f = XFORMS[xf]
    s = set()
    for t in tiles:
        if t[4] == 0:
            continue
        x, z = f(t[0] - beacon[0], t[1] - beacon[1])
        s.add(((x + 128) // 4, (z + 128) // 4))
    return s


def footprints8(L):
    b = (L["beacon"][0], L["beacon"][1])
    return [footprint_blocks(L["tiles"], b, k) for k in range(8)]


def recipe_key(L):
    arms = ",".join(sorted(L["arms"]))
    rooms = ",".join(sorted(p["arch"] for p in L["pieces"]
                            if p["kind"] == 0 and p["role"] != 0))
    walks = ",".join(sorted(p["arch"] for p in L["pieces"] if p["kind"] == 1))
    return arms + "|" + rooms + "|" + walks


def room_keys(L):
    out = []
    for p in L["pieces"]:
        if p["kind"] == 0 and p["role"] != 0:
            w = p["bbox"][2] - p["bbox"][0]
            d = p["bbox"][3] - p["bbox"][1]
            out.append((p["arch"], w, d) if w <= d else (p["arch"], d, w))
    return out


XFORMS = (
    lambda x, z: (x, z), lambda x, z: (-x, z),
    lambda x, z: (x, -z), lambda x, z: (-x, -z),
    lambda x, z: (z, x), lambda x, z: (-z, x),
    lambda x, z: (z, -x), lambda x, z: (-z, -x),
)


def similarity(fa, fb8):
    """fa = identity footprint of level A; fb8 = the 8 transformed footprints of
    level B. Returns max over the 8 of |A n B'| / |A u B'|."""
    best = 0.0
    for tb in fb8:
        if not fa and not tb:
            return 1.0
        inter = 0
        for xy in fa:
            if xy in tb:
                inter += 1
        union = len(fa) + len(tb) - inter
        sim = (inter / union) if union else 1.0
        if sim > best:
            best = sim
    return best


def _seed_worker(s):
    level = 1 + (s % 30)
    t0 = time.perf_counter()
    L = generate(s, level)
    gen_ms = (time.perf_counter() - t0) * 1000.0
    L2 = generate(s, level)
    h1 = level_hash(L)
    h2 = level_hash(L2)
    r = check_level(L)
    r["metrics"]["gen_ms"] = gen_ms
    rk = room_keys(L)
    cnt = {}
    for k in rk:
        cnt[k] = cnt.get(k, 0) + 1
    rep = 0
    for c in cnt.values():
        if c >= 2:
            rep += c
    d6_share = (rep / len(rk)) if rk else 0.0
    return {"seed": s, "level": level, "hash": h1, "hash2": h2,
            "attempt": L["attempt"], "gen_ms": gen_ms,
            "fails": r["fails"], "metrics": r["metrics"],
            "slots": len(L["gifts"]),
            "mines": sum(1 for g in L["gifts"] if g["occ"]),
            "eligible": r["metrics"]["eligible_slots"],
            "fp": footprints8(L),
            "recipe": recipe_key(L),
            "d6_share": d6_share}


def _d2_worker(args):
    seed, level = args
    L = generate(seed, level, 1, 999)
    S = len(L["gifts"])
    mines = sum(1 for g in L["gifts"] if g["occ"])
    base = walk_layer(L)
    adj = build_adj(L, base, VALIDATOR_GAP)
    judge = MineJudge(base, adj, [t for t in slot_tiles_of(L, base) if t >= 0])
    elig = 0
    for g in L["gifts"]:
        t = find_tile(base, g["x"], g["z"], g["y"])
        if t >= 0 and judge.eligible(t):
            elig += 1
    return {"seed": seed, "level": level, "slots": S, "mines": mines, "eligible": elig}


def _fmt(v):
    if isinstance(v, float):
        return ("%.2f" % v)
    return str(v)


# ---------------------------------------------------------------------------
# harness
# ---------------------------------------------------------------------------

def run_harness(a, b, jobs, out_path):
    t0 = time.perf_counter()
    seeds = list(range(a, b))
    results = []
    gen_errors = []
    if jobs > 1:
        import multiprocessing as mp
        chunk = max(1, len(seeds) // (jobs * 4))
        with mp.Pool(jobs) as pool:
            for k, r in enumerate(pool.imap_unordered(_seed_worker, seeds,
                                                      chunksize=chunk)):
                results.append(r)
                if (k + 1) % 250 == 0 or k + 1 == len(seeds):
                    el = time.perf_counter() - t0
                    print("  seeds %d/%d (%.0fs)" % (k + 1, len(seeds), el),
                          flush=True)
    else:
        for k, s in enumerate(seeds):
            try:
                results.append(_seed_worker(s))
            except Exception as e:
                gen_errors.append((s, 1 + (s % 30), str(e)))
            if (k + 1) % 100 == 0 or k + 1 == len(seeds):
                el = time.perf_counter() - t0
                print("  seeds %d/%d (%.0fs)" % (k + 1, len(seeds), el),
                      flush=True)
    results.sort(key=lambda r: r["seed"])
    total = len(results)

    # ---- per check failures ----
    fail_map = {cid: [] for cid in HARNESS_CHECKS}
    for r in results:
        ids = set()
        if r["hash"] != r["hash2"]:
            ids.add("H1")
        for f in r["fails"]:
            ids.add(f.split(":", 1)[0])
        if r["attempt"] > 12:
            ids.add("H15")
        for cid in ids:
            fail_map[cid].append(r)

    check_records = []

    def record(cid, fails, first_msg=None, measured=None, threshold=None):
        ok = not fails
        rec = {"id": cid, "passed": ok, "failures": len(fails), "total": len(results),
               "measured": measured, "threshold": threshold,
               "first": None, "seeds": []}
        if fails:
            f0 = fails[0]
            # gather a first-failure message even for harness-level checks
            if first_msg is None:
                m0 = f0["fails"][0] if f0["fails"] else \
                    ("hash mismatch" if cid == "H1" else
                     "attempt=%d" % f0["attempt"])
            else:
                m0 = first_msg
            rec["first"] = {"seed": f0["seed"], "level": f0["level"], "msg": m0}
            for f in fails[:20]:
                mm = None
                if cid in ("H1", "H15"):
                    mm = ("hash mismatch" if cid == "H1"
                          else "attempt=%d" % f["attempt"])
                else:
                    for ff in f["fails"]:
                        if ff.split(":", 1)[0] == cid:
                            mm = ff
                            break
                rec["seeds"].append({"seed": f["seed"], "level": f["level"],
                                     "hash": f["hash"], "attempt": f["attempt"],
                                     "msg": mm})
        check_records.append(rec)

    for cid in HARNESS_CHECKS:
        fl = fail_map[cid]
        if not fl:
            record(cid, [])
        else:
            record(cid, fl)

    # ---- D checks ----
    dist_records = []

    # D1: mine curve. GEN_VERSION 3 (D-026): the per-slot chance applies only to ELIGIBLE slots, so
    # the denominator is the number of slots that can hold a mine (recomputed here by brute force).
    per_level = {}
    for r in results:
        d = per_level.setdefault(r["level"], [0, 0, 0])
        d[0] += r["mines"]
        d[1] += r["eligible"]
        d[2] += r["slots"]
    d1_bad = []
    d1_dev = 0.0
    d1_rows = []
    for lvl in sorted(per_level):
        if lvl < 5:
            continue
        m, e, sl = per_level[lvl]
        obs = (m / e) if e else 0.0
        exp = (15 + min(lvl, 25)) / 400.0
        dev = abs(obs - exp)
        d1_dev = max(d1_dev, dev)
        d1_rows.append({"level": lvl, "mines": m, "eligible": e, "slots": sl,
                        "obs": round(obs, 5), "exp": round(exp, 5),
                        "obs_all_slots": round((m / sl) if sl else 0.0, 5)})
        if dev > 0.01:
            d1_bad.append((lvl, obs, exp))
    table_ok = (mine_chance_num(4) == 0 and mine_chance_num(5) == 20 and
                mine_chance_num(15) == 30 and mine_chance_num(25) == 40 and
                mine_chance_num(26) == 40 and mine_chance_num(99) == 40)
    rec = {"id": "D1", "passed": not d1_bad and table_ok,
           "measured": round(d1_dev, 5), "threshold": 0.01,
           "detail": "max |mines/eligible - curve| over levels >= 5", "levels": [],
           "rows": d1_rows}
    for lvl, obs, exp in d1_bad:
        rec["levels"].append({"level": lvl, "observed": round(obs, 5),
                              "expected": round(exp, 5)})
        rec["passed"] = False
    rec["table_ok"] = table_ok
    dist_records.append(rec)

    # D2: mine cap under the curse. GEN_VERSION 3 (D-026): the target is min(S // 5, eligible slots),
    # because a slot with no walkable bypass can never hold a mine.
    d2_args = [(seed, lvl) for lvl in (5, 15, 30) for seed in range(1000, 1100)]
    d2_res = []
    if jobs > 1:
        import multiprocessing as mp
        with mp.Pool(jobs) as pool:
            d2_res = pool.map(_d2_worker, d2_args, chunksize=max(1, len(d2_args) // (jobs * 4)))
    else:
        d2_res = [_d2_worker(x) for x in d2_args]
    d2_bad = [r for r in d2_res
              if r["mines"] != min(r["slots"] // 5, r["eligible"])]
    dist_records.append({"id": "D2", "passed": not d2_bad,
                         "measured": "%d/%d at min(S//5, eligible)"
                                     % (len(d2_res) - len(d2_bad), len(d2_res)),
                         "threshold": "all == min(S//5, eligible)",
                         "seeds": [{"seed": r["seed"], "level": r["level"],
                                    "mines": r["mines"], "cap": r["slots"] // 5,
                                    "eligible": r["eligible"]}
                                   for r in d2_bad[:20]]})

    # D3: distinct hashes
    hashes = [r["hash"] for r in results]
    dup = total - len(set(hashes))
    dist_records.append({"id": "D3", "passed": dup == 0, "measured": len(set(hashes)),
                         "threshold": total})

    # D4/D5: same-level pairs
    by_level = {}
    for r in results:
        by_level.setdefault(r["level"], []).append(r)
    rng = random.Random(12345)
    levels_present = sorted(lvl for lvl, lst in by_level.items() if len(lst) >= 2)
    pairs = []
    sims = []
    simpairs = []
    same_recipe = 0
    for _ in range(4000 if levels_present else 0):
        lvl = levels_present[rng.randrange(len(levels_present))]
        lst = by_level[lvl]
        i, j = rng.sample(range(len(lst)), 2)
        pairs.append((lst[i], lst[j]))
    note = None
    if not pairs:
        note = "no same-level pairs in sample"
    for ra, rb in pairs:
        sims.append(similarity(ra["fp"][0], rb["fp"]))
        simpairs.append((sims[-1], ra["seed"], rb["seed"], ra["level"]))
        if ra["recipe"] == rb["recipe"]:
            same_recipe += 1
    sims.sort()
    simpairs.sort(reverse=True)
    print("D4 most similar same-level pairs (render these and look, TERRAIN_SPEC 10.3):")
    for sp in simpairs[:5]:
        print("   sim=%.3f level=%d seeds=%d,%d" % (sp[0], sp[3], sp[1], sp[2]))
    p99 = sims[(99 * (len(sims) - 1)) // 100] if sims else 0.0
    high = sum(1 for v in sims if v >= 0.60)
    limit_high = int(0.001 * len(pairs))
    rec_d4 = {"id": "D4", "passed": p99 <= 0.50 and high <= limit_high,
              "measured": round(p99, 4), "threshold": 0.50,
              "measured2": high, "threshold2": limit_high, "pairs": len(pairs)}
    if not pairs:
        rec_d4["note"] = note
    dist_records.append(rec_d4)
    dist_records.append({"id": "D5", "passed": same_recipe <= limit_high,
                         "measured": same_recipe, "threshold": limit_high,
                         "pairs": len(pairs)})

    # D6: within-level room repetition (per generated level, D6 share computed in worker)
    d6_shares = [r["d6_share"] for r in results]
    d6_mean = sum(d6_shares) / len(d6_shares) if d6_shares else 0.0
    d6_mean = sum(d6_shares) / len(d6_shares) if d6_shares else 0.0
    dist_records.append({"id": "D6", "passed": d6_mean <= 0.10,
                         "measured": round(d6_mean, 4), "threshold": 0.10})

    # D7: difficulty ramp over buckets
    bmeans = []
    for lo, hi in BUCKETS:
        dv = [r["metrics"]["D"] for r in results if lo <= r["level"] <= hi]
        bmeans.append(sum(dv) / len(dv) if dv else 0.0)
    d7_ok = all(bmeans[k] < bmeans[k + 1] for k in range(len(bmeans) - 1))
    dist_records.append({"id": "D7", "passed": d7_ok,
                         "measured": [round(x, 3) for x in bmeans],
                         "threshold": "strictly increasing"})

    # D8: gentle start
    l1 = [r for r in results if r["level"] == 1]
    jmean = (sum(r["metrics"]["J"] for r in l1) / len(l1)) if l1 else 0.0
    jmax = max((r["metrics"]["J"] for r in l1), default=0.0)
    dist_records.append({"id": "D8", "passed": jmean <= 50 and jmax <= 80,
                         "measured": round(jmean, 3), "threshold": 50,
                         "measured2": round(jmax, 3), "threshold2": 80})

    # D9: generation time
    gm = [r["gen_ms"] for r in results]
    gmean = sum(gm) / len(gm) if gm else 0.0
    gmax = max(gm) if gm else 0.0
    dist_records.append({"id": "D9", "passed": gmean <= 250.0 and gmax <= 2000.0,
                         "measured": round(gmean, 1), "threshold": 250,
                         "measured2": round(gmax, 1), "threshold2": 2000})

    # ---- print ----
    print()
    for rec in check_records:
        if rec["passed"]:
            print("PASS %s failures=0/%d" % (rec["id"], rec["total"]))
        else:
            f0 = rec["first"]
            print("FAIL %s failures=%d/%d first: seed=%d level=%d %s"
                  % (rec["id"], rec["failures"], rec["total"],
                     f0["seed"], f0["level"], f0["msg"]))
    for rec in dist_records:
        bits = [rec["id"], "PASS " if rec["passed"] else "FAIL "]
        parts = []
        for mk, tk in (("measured", "threshold"), ("measured2", "threshold2")):
            if mk in rec:
                parts.append("%s (limit %s)" % (rec[mk], rec[tk]))
        if rec["id"] == "D7":
            parts = ["%s (bucket means %s)" % (rec["measured"], rec["threshold"])]
        if rec["id"] == "D1":
            parts = ["max dev %.5f (limit %.5f), table %s"
                     % (rec["measured"], rec["threshold"],
                        "ok" if rec["table_ok"] else "BAD")]
        print("%s %s: %s" % ("PASS" if rec["passed"] else "FAIL", rec["id"],
                             "; ".join(parts)))
    if gen_errors:
        print("FAIL GEN %d seeds failed to generate, first: seed=%d level=%d %s"
              % (len(gen_errors), gen_errors[0][0], gen_errors[0][1],
                 gen_errors[0][2]))

    # ---- bucket table ----
    print()
    def stats_for(lo, hi, name):
        vs = []
        for r in results:
            if lo <= r["level"] <= hi:
                v = r["metrics"].get(name)
                if v is None:
                    v = BIG
                vs.append(float(v))
        if not vs:
            return None
        vs.sort()
        return (sum(vs) / len(vs), vs[0], vs[-1])

    per_bucket = []
    for lo, hi in BUCKETS:
        row = {"level_bucket": "%d-%d" % (lo, hi)}
        for name in METRIC_NAMES:
            s = stats_for(lo, hi, name)
            row[name] = None if s is None else {
                "mean": round(s[0], 3), "min": round(s[1], 3), "max": round(s[2], 3)}
        per_bucket.append(row)

    names = METRIC_NAMES
    colw = max(len(nm) + 3 for nm in names) + 14
    header = "bucket".ljust(10)
    print(header + "".join(nm.rjust(19) for nm in names))
    maxes = {}
    for name in names:
        allv = []
        for r in results:
            v = r["metrics"].get(name)
            allv.append(BIG if v is None else float(v))
        maxes[name] = max(allv) if allv else 0.0
    for row in per_bucket:
        line = row["level_bucket"].ljust(10)
        for name in names:
            if row[name] is None:
                line += "n/a".rjust(19)
                continue
            m, mn, mx = row[name]["mean"], row[name]["min"], row[name]["max"]
            cell = "%s/%s/%s" % (_fmt(round(m, 2)), _fmt(round(mn, 2)),
                                 _fmt(round(mx, 2)))
            line += cell.rjust(19)
        print(line)

    # ---- report json ----
    all_ok = (all(r["passed"] for r in check_records)
              and all(r["passed"] for r in dist_records) and not gen_errors)
    report = {
        "seeds": [a, b], "jobs": jobs,
        "levels": {r["seed"]: r["level"] for r in results},
        "wall_s": round(time.perf_counter() - t0, 1),
        "all_pass": all_ok,
        "gen_errors": [{"seed": s, "level": l, "error": e} for s, l, e in gen_errors[:20]],
        "checks": check_records,
        "distribution": dist_records,
        "buckets": per_bucket,
        "n_results": total,
    }
    out_dir = os.path.dirname(out_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(out_path, "w", newline="\n") as fh:
        json.dump(report, fh, indent=1)
    print("report written to %s" % out_path)
    print("total wall time %.1f s" % (time.perf_counter() - t0))
    return 0 if all_ok else 1


def run_one(seed, level):
    t0 = time.perf_counter()
    L = generate(seed, level)
    gen_ms = (time.perf_counter() - t0) * 1000.0
    r = check_level(L)
    m = dict(r["metrics"])
    m["gen_ms"] = round(gen_ms, 1)
    m["attempt"] = L["attempt"]
    m["slots"] = len(L["gifts"])
    m["mines"] = sum(1 for g in L["gifts"] if g["occ"])
    for k in m:
        if isinstance(m[k], float):
            m[k] = round(m[k], 3)
    print(json.dumps(m, indent=1))
    if r["fails"]:
        for f in r["fails"]:
            print("FAIL " + f)
        return 1
    print("ALL CHECKS PASS")
    return 0


def main():
    ap = argparse.ArgumentParser(description="VOIDWRAP terrain validator")
    ap.add_argument("--seeds", metavar="A:B", help="harness over [A, B)")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 1)
    ap.add_argument("--out", default="out/report.json")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--one", nargs=2, type=int, metavar=("SEED", "LEVEL"))
    args = ap.parse_args()
    if args.selftest:
        sys.exit(0 if run_selftest() else 1)
    if args.one:
        sys.exit(run_one(args.one[0], args.one[1]))
    if args.seeds:
        a, b = (int(x) for x in args.seeds.split(":"))
        sys.exit(run_harness(a, b, args.jobs, args.out))
    ap.print_help()


if __name__ == "__main__":
    main()
