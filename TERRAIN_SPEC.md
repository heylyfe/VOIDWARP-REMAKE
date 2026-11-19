# TERRAIN_SPEC.md — VOIDWRAP RUN terrain generator (GEN_VERSION 4)

The terrain IS the level. This document specifies a pure, deterministic, seeded generator and the
headless validator that judges it. The working reference implementation is `terrain_ref/voidgen.py`
(see TERRAIN_REF.md). Where this text and the reference code disagree, **the reference code wins**
and this text gets a fix — the code is executable and hash-pinned, prose is not.

Words used exactly: **tile** = one walkable 1 u × 1 u surface cell. **piece** = a room or a link.
**room** = a platform area. **link** = a connection between two pieces. **slot** = a gift slot.
**u** = world unit (1 u = 1 m). **HU** = height unit = 0.5 u.

---

## 1. Contract

```
generate(seed: u32, level: int >= 1, players: int >= 1 = 1, extra_mines: int >= 0 = 0) -> Level
```

- **Pure function of exactly these four integers.** No clock, no globals, no engine RNG, no settings,
  no locale, no file reads, no player data. Same inputs → byte-identical canonical text (§8) on every
  machine and in every language port.
- **Seed-only multiplayer sync is a HARD REQUIREMENT.** A future netcode layer transmits `seed` once.
  `level` is derived from synced game state, `players` from the lobby, `extra_mines` from the synced
  vote history. Geometry is NEVER transmitted. Any change that makes output depend on anything else
  is a rejected change.
- Self-contained module. Imports nothing from the game. The game imports it.
- The run seed is one u32. The per-level stream is derived inside the generator (§3), so level N of a
  run never depends on levels 1..N-1 having been generated.
- `mods` in DECISIONS D-016 = `extra_mines` today. New terrain-affecting modifiers are added as new
  trailing integer parameters with default 0 (default must reproduce the old hash).

## 1A. Shape contract (GEN_VERSION 2)

The canon shape is **spawn hub → branching paths → sub-areas**. A level is ONE dominant spawn
platform, long thin paths that constantly step up and down, and a few small platforms that act as rest
points and as the hubs of sub-areas. Large platforms joined by wide flat walkways read as rooms, not
as a route to solve; this section is the contract that forbids them. Every number here was fixed
before measurement (D-030); a failing check is fixed in the generator, never by moving a number.

**GEN_VERSION 4 (job J1, owner override, recorded in out/decisions/J1.md):** every walkway is
exactly **3 cells wide** (it was 1..2), every walkable piece is at least 3 cells wide, and every gift
slot sits on a **centre lane** (§6.7). The width-1 share `w1_pct` is gone. Everything else in this
section stands.

### 1A.1 Vocabulary (exact)

- **Spawn platform (hub)** — piece 0, role 0, arch `hub`. Exactly one per level. §6.1 fixes its
  geometry: plaza x,z ∈ [−6,6] at y=0, dais x,z ∈ [−2,2] at y=1, four 3-wide stubs at cells 7..9.
  205 tiles, bbox max dimension 19.
- **Walkway** — a piece with `kind = 1`. A straight run of **rows** along one direction; every row is
  exactly 3 cells wide (lateral offsets −1, 0, +1) and every cell of a row has the same height. Its
  **length** is its number of rows. Its **width** is the number of cells in a row, counted along the
  walkway's **travel axis** (the axis along which it touches its parent piece). Walkways are the
  paths; they include the shortcut bridges and drop ledges (roles 4 and 5).
- **Centre lane** — the middle cells of a 3-wide part. A tile is on a centre lane when all four
  neighbour columns hold a walkable tile on its layer (within 12 HU of it) and, along at least one
  axis, the columns two away on both sides hold none: exactly one walkable tile on each side.
- **Platform** — a piece with `kind = 0` that is not the hub. A compact area: bbox at most 7×7 cells
  and at most 40 tiles. Its **length** (for the path-share metric) is its bbox max dimension.
- **At least 3 wide** — every tile of a piece lies inside a full 3×3 square of cells, each holding a
  tile of the same piece or of a piece joined to it by an edge (a walkway's first row may lean on its
  parent). Footprint only: heights and props do not narrow a piece.
- **Sub-area** — a platform plus the walkways that leave it. A level is the hub plus 3..12 sub-areas.
- **Sub-area boundary (junction)** — a pair of 4-adjacent tiles where one belongs to a walkway and
  the other to a non-hub platform. Its **delta** is the smallest |Δy| over the adjacent tile pairs of
  that (walkway, platform) piece pair. Hub junctions are not sub-area boundaries and are excluded.
- **Tread** — a maximal run of consecutive rows of one walkway at the same height.
- **Path rows** — the rows of every walkway piece (roles 3, 4 and 5). The hub and platforms have no
  rows.
- **Path length** — Σ walkway length. **Platform length** — Σ platform bbox max dimension.
- **Path share** — path length / (path length + platform length). The hub is excluded from both.
- **Flat run** — a tread longer than 3 rows. A row is **flat-continuing** when it sits at position ≥ 3
  (0-based) inside its tread, i.e. it continues a flat run longer than 3 cells.
- **flat-share** — flat-continuing rows / path rows.
- **ramp-share** — rows containing at least one ramp tile (`kind ≠ 0`) / path rows.
- **Elevation variance** — σ = sqrt(Σ(y − ȳ)² / N) over the **non-hub** tiles of the level (paths and
  platforms), in HU. The hub is excluded because it is a fixed anchor and would dominate the count.
- **Height delta distribution** — two histograms: (a) |Δy| between consecutive treads along every
  walkway, (b) junction deltas. Both are reported per level and per bucket; only the junction rule
  below is a hard check.

### 1A.2 The four rules

1. **One spawn platform.** Exactly one hub per level. It is strictly the largest walkable area and
   strictly the widest piece in the level: its tile count (205) and its bbox max dimension (19) are
   both strictly greater than every other piece's, and its largest flat walkable component is
   strictly larger than every other flat walkable component. It contains the beacon dais (25 tiles at
   y=1), the beacon tile (0,0,1) and the 8 spawn tiles. No other area may equal it in width or
   walkable area. (H16)
2. **Everything else is paths.** Walkway width is exactly 3 cells (H17), and every walkable piece is
   at least 3 cells wide (H24). (GEN_VERSION 2–3 had 1..2 and a width-1 share `w1_pct` that rose
   with level; the owner overrode it in GEN_VERSION 4: a 1–2 cell path read as a balance beam, not a
   route.) The upper bound stays at 3 so the centre lane is unique and the hub stays the widest
   piece. Platforms are
   at most 7×7 cells and at most 40 tiles, and there are between 3 and `plat_max = min(12, 4 +
   level // 3)` of them per level (H18). Path share ≥ 70% of centre-line length and path tiles ≥ 50%
   of non-hub walkable tiles (H19).
3. **Graduation.** Paths gain and lose height as they travel: flat runs and ramps are the exception.
   flat-share ≤ 35% and ramp-share ≤ 10% of path rows (H20). Elevation variance ≥
   `3 + 3·(min(level,10) − 1) // 9` HU — 3 HU at level 1, 4 at level 4, 5 at level 7, 6 at level 10
   and above (H21). At least 50% of sub-area boundaries have |Δy| ≥ 1 HU (H22).
4. **Unchanged.** Gift-slot placement stays a first-class output with stable ids (§6.7); black and
   gold gifts share the same positions; hazards inherit slots; the tripmine curve and its 20% cap
   (§6.8); the beacon anchor (§6.1); purity — output is a function of (seed, level, players,
   extra_mines) only (§1); every gift is round-trip reachable with the base kit (§5.4, H3, H13);
   zero soft-lock tiles (H6); the footprint similarity metric (4-cell blocks, anchored to the spawn
   root, D-022 FINAL, §10.3). **Added in GEN_VERSION 3:** a tripmine may only occupy a slot with a
   walkable bypass (§6.8.2–§6.8.5, H23) — the hazard still inherits a gift slot and still never gets
   its own placement logic, but the slot set it may inherit from is now filtered.

### 1A.3 How the generator meets it

- The hub is enlarged (§6.1) and its sockets take a 3-wide walkway centred on the stub.
- Every platform socket sits in the middle of a face at least 3 cells wide, so the 3-wide walkway
  leaving it meets three platform tiles (no corner sockets).
- Growth builds a **walkway** out of a socket and then either attaches a **platform** at its far end
  or leaves the walkway's far end as a socket that the next step grows from. So a path between two
  platforms is 2..4 walkways long, and the piece graph is hub → walkway → … → platform → walkway → …
- Walkway archetypes are stepped (§6.4): treads of 1..2 rows, each tread 1 or 2 HU above or below the
  previous one. `flat` and `ramp` exist but are weighted low.
- Each arm carries a **height drift** (`-2..+2`, dealt from a shuffled table so the level always has
  one climbing and one descending arm). The drift tilts the per-walkway up-chance by `22 x drift`, so
  a path gains or loses height as it travels instead of jittering around the hub's height.
- A platform is placed at the walkway's end height **plus a junction step** of ±1 or ±2 HU (never 0;
  in the gentle-start zone exactly ±1). A walkway leaving a platform starts at the platform's height
  **plus a near-end junction step** of ±1 or ±2 HU (never 0). So every platform junction steps.
- Platform archetypes are small (§6.5): pad, disc, cross, ell, terrace, nook, spire, bastion.
- A platform is **terminal** (its sockets are not grown from, so it becomes a dead end) with 35%
  chance, and the last platform of a level is always terminal. Dead ends are therefore platforms.
- An attempt is rejected (and the next of the 24 deterministic attempts is tried) when the finished
  level misses the elevation-variance floor (§1A rule 3) or the path-tile share (§1A rule 2), exactly
  as it is already rejected for a soft-lock tile, a missing shortcut or fewer than two dead ends.

## 2. Why this algorithm

**Spawn-rooted graph growth with parametric piece archetypes.** (DECISIONS D-010.)

1. A fixed beacon hub is placed at the origin (§6.1). It is the only large area in the level.
2. 2–4 **arms** grow outward from the hub's sockets. Each arm has a **trait** that biases what it is
   built from (stepped climbs, jump stairs, drop ledges, flat runs, ramps, and which platform
   archetypes it prefers).
3. Each growth step takes an open socket and builds a **walkway** out of it (§6.4): 3 cells wide,
   treads of 1–3 rows, each tread 1–2 HU above or below the previous one. At the walkway's far end the
   step either attaches a small **platform** (§6.5, bbox ≤ 7×7, ≤ 40 tiles) or leaves the walkway's
   far end as a socket that the next step grows from. So paths are long and thin, and platforms are
   occasional rest points and sub-area hubs. Pieces never overlap.
4. Unused sockets then cast rays; where a ray meets another piece a **shortcut** is built: a two-way
   bridge, or a one-way drop ledge (sometimes with a launch pad that makes it two-way).
5. A movement graph is built from the tiles. Gift slots are placed only on tiles proven round-trip
   reachable from the beacon. Tripmine occupancy is rolled per slot.

Why not the alternatives: a hand-authored pattern catalog repeats (v1: 91.6% of levels had a repeated
pattern) and hides unreachable geometry inside patterns; WFC has no global structure; a noise
heightfield is a backdrop, not a puzzle; BSP rooms read as an indoor dungeon.

What makes it a puzzle rooted at spawn:
- The level is a tree rooted at the beacon → the player always has a "home" and every gift has a
  depth (distance from home). Deeper = more gifts per tile (§6.2) = more reward for more exposure.
- Arms have identity (trait + colour-coded links) → the player plans "which arm first".
- The route itself is the puzzle: every path steps up and down (§1A), so moving along it is a
  continuous read of the next tread, not a walk across a floor.
- Dead ends carry the richest gift clusters and exactly one way in → they are risks, not filler.
- Shortcuts change routing: a bridge joins two arms; a drop ledge is a fast one-way return.
- Because gold gifts reuse the black slots, the player who lingers runs the same puzzle again under
  more pressure — route knowledge earned in the black phase pays off in the gold phase.

## 3. Determinism rules (binding for every port)

1. Integers only. No float, no trig, no sqrt, no engine vector types inside the generator.
2. Never divide or modulo a negative number (Python floors, GDScript/C truncate). Use `rdiv` (§5.3)
   or keep operands ≥ 0.
3. Never iterate an unordered container. Dictionaries are used for lookup only, or iterated strictly
   in insertion order. Sorting uses total orders on integers only.
4. RNG = Mulberry32 over 32-bit state, with every multiply done by `mul32` so no intermediate exceeds
   2^48 (safe in int64 and in IEEE doubles):

```
M32 = 0xFFFFFFFF
mul32(a,b) = ((a & 0xFFFF)*b + ((((a >> 16)*b) & 0xFFFF) << 16)) & M32
fmix(x):  x ^= x>>16; x = mul32(x,0x85EBCA6B); x ^= x>>13; x = mul32(x,0xC2B2AE35); x ^= x>>16
mix(a,b) = fmix((a ^ mul32((b + 0x9E3779B9) & M32, 0x01000193)) & M32)
Rng(seed): s = seed & M32
u32():   s = (s + 0x6D2B79F5) & M32; z = s
         z = mul32(z ^ (z>>15), z | 1)
         z ^= (z + mul32(z ^ (z>>7), z | 61)) & M32
         return (z ^ (z>>14)) & M32
range(n) = (u32()*n) >> 32            # n in 1..2^20
ri(a,b)  = a if b <= a else a + range(b-a+1)
chance(num,den) = range(den) < num
pick(seq) = seq[range(len(seq))]
wpick(names, weights): r = range(sum(weights)); walk the list subtracting weights; first r < 0 wins
shuffle(lst): for i = len-1 down to 1: j = range(i+1); swap(lst[i], lst[j])
```

5. Sub-streams (D-017). `base = mix(mix(mix(seed, level), GEN_VERSION), attempt)`.
   Phase stream = `Rng(mix(base, STREAM))` with PLAN=1, GROW=2, LOOP=3, GIFT=4, MINE=5.
   The GROW phase re-seeds per growth step: `Rng(mix(mix(base, 2), step_counter))`.
6. Draw order inside a function is part of the contract. Do not reorder RNG calls when porting.
7. Any output-changing edit bumps `GEN_VERSION` and regenerates `terrain_ref/gallery.json`.

## 4. Geometry model

- Grid: integer cells. Cell (x, z) covers world X ∈ [x, x+1), Z ∈ [z, z+1). 1 cell = 1 u.
- Height: integer HU. World Y of a tile's top surface = y × 0.5 u.
- **Tile** `[x, z, y, kind, piece]`. `kind` 0 = flat. `kind` 1+d = ramp ascending toward direction d;
  a ramp tile's `y` is its LOW edge, its high edge is y+1 (slope 0.5 u per 1 u = 26.57°).
- Directions: 0 = +x, 1 = +z, 2 = −x, 3 = −z. `DX=(1,0,-1,0)`, `DZ=(0,1,0,-1)`.
- Every tile is the top of a solid slab `SLAB = 2 HU` (1 u) thick. Visual thickness = collision.
- **Prop** `[x, z, y, h, kind, piece]`: a blocking 1-cell box standing on the tile at (x,z,y), `h` HU
  tall. Kinds: 0 block (4–6 HU), 1 wall (6–8), 2 crate (2), 3 pillar (10–12). A tile under a prop is
  not walkable. Props are line-of-sight cover — they exist for gameplay (Isagi, nuke), not decor.
- **Pad** `[x, z, y, tx, tz, ty]`: a launch pad on tile (x,z,y) that throws the player onto tile
  (tx,tz,ty). Rise is 5–7 HU (v1 `PAD_LAUNCH_VEL = 16`, apex 4.0 u = 8 HU).
- Clearance: `CLEAR = 12 HU`. Two tiles in the same column always differ by ≥ 12 HU (6 u), leaving
  5 u of headroom under a slab — more than standing height 1.8 u + jump apex 2.25 u. Tiles of
  unrelated pieces that are 8-neighbours also differ by ≥ 12 HU, so pieces never visually fuse.
- Bounds: `Y_MIN = -48`, `Y_MAX = 72` HU; |x|, |z| ≤ `radius` (§9). Kill plane at world Y = −40 u.
- Non-gameplay dressing (support spikes under platforms, trim, sigils) is derived by the ENGINE from this
  data and must never collide in a column that contains a tile below it (§11.4).

## 5. Movement model (the single source of truth for "reachable")

Controller constants carried over from v1 (D-012): `GRAVITY 32 u/s²`, `JUMP_VELOCITY 12 u/s` (apex
2.25 u), `RUN_SPEED 9 u/s`, `PLAYER_HALF_WIDTH 0.4 u`, player height 1.8 u, auto step-up 0.5 u (1 HU).

### 5.1 Derivation of the jump envelope
Air time to land at height +h: `t = (12 + sqrt(144 − 64h)) / 32`. Reach = 9·t, × 0.9 safety:

| landing height | air time | reach × 0.9 | VALIDATOR max gap (cells) | AUTHORING max gap |
|---|---|---|---|---|
| ≤ 0 (level or lower) | 0.750 s | 6.07 u | 5 | 4 |
| ≤ +2 HU (+1.0 u) | 0.654 s | 5.30 u | 4 | 3 |
| ≤ +4 HU (+2.0 u) | 0.500 s | 4.05 u | 3 | 2 |
| > +4 HU | unreachable (apex 2.25 u) | — | — | — |

Gap = empty cells between the two tiles, edge to edge. The **validator envelope** is what the base
kit can physically do with margin. The **authoring envelope** is one cell tighter and is the most the
generator may BUILD into a link or room. Rationale: retro §4e — v1's bot envelope was narrower than
its generator's guarantee. Here the guarantee (authoring) is strictly inside the proof (validator).

### 5.2 Edges of the movement graph (nodes = walkable tiles)
- Walkable tile = tile with no prop standing on it.
- **Walk**: 4-neighbour tiles with |Δy| ≤ 1 HU.
- **Boundary tile**: a walkable tile with at least one of its 4 directions lacking a walk edge.
- **Jump/drop** from boundary tile A to boundary tile B (dx, dz ∈ −6..6, not both 0):
  `Δy = yB − yA`; require `−60 ≤ Δy ≤ 4`; `lim = 5 if Δy ≤ 0, 4 if Δy ≤ 2, else 3`;
  require `dx² + dz² ≤ (lim+1)²`; skip if it is already a walk edge; the path must be clear (§5.3).
- **Pad**: directed edge pad tile → target tile.
- Drops are one-way by nature (the reverse edge exists only if it is itself a legal jump).

### 5.3 Clear-path test
`steps = max(|dx|,|dz|)`. For s = 1..steps−1 visit cell `(xA + rdiv(dx·s, steps), zA + rdiv(dz·s, steps))`.
`hi = max(yA, yB)`. The jump is blocked if any tile in that cell has `y > hi and y − 2 < hi + 8`, or
any prop there has `base + h > hi and base < hi + 8`.
`rdiv(a,n) = (2a+n)//(2n) if a ≥ 0 else −((−2a+n)//(2n))`.

### 5.4 Reachability sets
`fwd` = BFS from the beacon tile (0,0,1). `back` = BFS on the reversed graph from the beacon tile.
`rt = fwd ∩ back` = **round-trip reachable** (you can get there AND get home, base kit only).
A tile in `fwd` but not in `back` is a **soft-lock tile**. Soft-lock tiles are forbidden (H6).

All classes share run + jump, so one proof covers Dasher, Glider and Athletic (D-013).

## 6. Generation pipeline (exact; mirror `voidgen.py`)

### 6.0 Attempts
`for attempt in 0..23: r = build(...); if r: return`. An attempt is rejected when: fewer platforms
were placed than the level's target (§6.2); a soft-lock tile exists; the slot target cannot be met;
no shortcut was built; or fewer than 2 dead-end platforms exist (the last two are waived on attempt
23). The accepted `attempt` is part of the output.

### 6.1 Hub — the beacon anchor (fixed, identical in every level)
- Piece 0, arch `hub`. Plaza x,z ∈ [−6,6] at y=0 (169 cells); dais x,z ∈ [−2,2] at y=1 (25 cells, a
  0.5 u walk-up step); four stubs 3 wide × 3 long (cells 7..9 along each axis, lateral −1..1) at y=0
  (36 cells). **205 tiles**, bbox max dimension **19** — strictly the largest and widest piece in
  every level (§1A rule 1, H16).
- Four pillar props (h=10) at (±6, ±6).
- **Beacon** stands at tile (0,0,1). It is a state machine owned by the game, not the generator:
  `CLOSED` (run start; all black gifts not yet collected) → `OPEN` (last real black gift collected).
  Trigger volume: cylinder radius 1.5 u, height 3 u, centred on the beacon tile; entering it while
  OPEN completes the level. It never blocks movement.
- **Spawns** (8, in this order; player i uses spawn i mod 8), all at y=1:
  (1,1) (−1,−1) (−1,1) (1,−1) (2,0) (−2,0) (0,2) (0,−2).
- No gift slot is ever placed on the dais. The hub's outer ring does receive slots (so the first
  gift is seconds away — feel budget "level start → first gift ≤ 8 s").
- Hub sockets: (9,0,dir0) (0,9,dir1) (−9,0,dir2) (0,−9,dir3), y=0, link width 3 (every walkway is
  exactly 3 wide, §1A rule 2), centred on the 3-wide stub.

### 6.2 Plan (stream PLAN)
`n_arms = ri(arms_min, arms_max)`. Shuffle the four hub socket indices; the first `n_arms` become arm
roots, the rest are spare (they may host shortcuts). Each arm draws a trait by weight
(grand 10, ascent 8, descent 8, hop 4 + t//2, maze 8, thin 3 + t//3; a trait already used this level
has its weight quartered; every weight +1). Right after its trait, each arm draws `share = ri(1,4)`
and `deep = 25 + 15·range(5)` (25..85%).
**Platform target**: `plat_max = min(12, 4 + level // 3)`; the level's target is
`target = ri(plat_max − 1, plat_max)` (so 3..4 at level 1, 11..12 at level 30). §1A rule 2 allows any
count in [3, plat_max]; the generator aims at the top of that range so gift capacity is never the
binding constraint.
**Asymmetric arms**: every arm gets a quota of 1 platform; the remaining `target − n_arms` platforms
are dealt in proportion to `share` (integer floor), leftovers one by one from arm 0. → levels have
major and minor arms instead of an even star.

Traits (multipliers are in quarter units; 4 = ×1; unlisted walkway/platform archetypes = 4):

| trait | walkways favoured | platforms favoured | up-chance | width |
|---|---|---|---|---|
| grand | step ×2, flat ×2, ramp ×1, stair ×0.5, ledge ×0.5 | pad ×2, cross ×2, disc ×2 | 50% | 3 |
| ascent | step ×2, stair ×2, ledge ×1, ramp ×1 | terrace ×3, spire ×3, bastion ×2 | 85% | 3 |
| descent | same as ascent | terrace ×3, disc ×1.5, pad ×1.5 | 15% | 3 |
| hop | stair ×2.5, ledge ×2, step ×1 | spire ×5, cross ×2, disc ×1.5 | 55% | 3 |
| maze | step ×1.5, flat ×1.5, others ×1 | cross ×3, ell ×3, pad ×1.5 | 50% | 3 |
| thin | step ×2.5, ledge ×1.25, stair ×1 | nook ×4, ell ×2, bastion ×2 | 50% | 3 |

The width column is 3 for every trait since GEN_VERSION 4 (it was: grand always 2, thin always 1,
the rest random 1..2). `thin` keeps its walkway and platform weights; it no longer means narrow.

### 6.3 Growth (stream GROW, re-seeded per step)
Loop until the platform target is met, no arm has an open socket, or `60 × plat_max` steps passed:
1. Pick the arm with the largest `quota − rooms` among arms that have open sockets (ties: lowest index).
2. Pick a socket: with the ARM's `deep` chance the open socket whose owner piece is deepest (ties:
   latest added), else a uniformly random open socket. → some arms are long spines, some are bushy.
   **Turn bias**: if the deep pick chose a socket that continues straight through its room (its
   direction equals the direction the room was entered) then with `turn_pct` (75%) it yields to the
   last sibling socket of the same room that turns. → arms wind instead of running out as sticks,
   which also makes shortcut rays hit more often.
3. Up to `grow_tries` (5) times, `try_grow`:
   0. `gentle = (parent depth + 1) < jump_min_depth`. **Gentle-start rule**: while gentle, the
      platform archetype `spire` has weight 0, the walkway archetypes `stair` and `ledge` have weight
      0, every terrace step is 1 HU instead of 2, and the junction step is
      −1..+1 instead of −2..+2. So on level 1 the whole level is walkable without jumping; the rule
      is off from level 9 (`jump_min_depth = max(1, 10 − t)`).
   a. Walkway archetype by weight = `walk_w[arch] × trait multiplier`, then the gentle rule's
      zeroing. Build it (§6.4) from the cell in front of the source socket.
   b. Walkway width: always 3 (GEN_VERSION 4). No RNG is drawn for it (the `w1_pct` draw of
      GEN_VERSION 3 is gone, so every later draw moved up by one).
   c. **Attach a platform?** `roll = chance(plat_pct = 40, 100)` is always drawn. Attach when
      `placed < target` and `since ≥ 2` and (`since ≥ 4` or `roll` or `placed ≥ target − 1`), where
      `since` counts walkways grown since the last platform. Otherwise the walkway is committed on
      its own and its far end becomes a socket (the path continues). Two draws follow, always:
      `turn = range(2)` and `do_turn = chance(turn_pct, 100)`. When `do_turn` and the walkway has
      ≥ 4 rows, TWO sockets are returned, in this order: the straight-ahead socket (on the last row's
      centre, pointing along the walkway) and a turn socket on the outer tile of row n−2 on side
      `turn` (lateral +1 for 0, −1 for 1), pointing sideways, at row n−2's height — the 3-wide
      walkway that grows from it covers rows n−3..n−1 flush, a clean L corner, and ≥ 4 rows keeps
      its 8-neighbour ring off this walkway's parent. The turn socket is the later one, so the deep
      pick takes it first; the straight socket is grown when the turn fails, and a random pick may
      grow both, which makes a T junction. Otherwise only the straight-ahead socket is returned.
   d. Platform archetype by weight = `plat_w[arch] × trait multiplier`, ÷4 if same archetype as the
      parent piece, ÷count if that archetype already appears ≥ 2 times in the level, then +1
      (then the gentle rule's zeroing).
      **Shape uniqueness**: the pick + local generation is repeated up to 4 times until
      `(arch, min bbox dim, max bbox dim, tile count)` is not already used by a platform of this
      level; the 4th result is accepted regardless. Committed platforms record their shape key.
   e. Generate the platform in local coordinates (§6.5). Draw mirror ∈ {0,1}. Pick a random platform
      socket `e` as the entry; rotate the platform so `e` faces back toward the source socket.
   f. **Junction step**: `step = ri(−1,1)` when gentle, else `(0,1,−1,2,−2,1,−1,2)[range(8)]`. The
      platform is translated so its entry tile sits at the cell after the walkway's last row, at
      height `walkway end height + step`.
   g. Reject if any tile leaves the bounds, the platform shares a column with the walkway, the
      walkway fails `fits(allow = {source piece})`, or the platform fails `fits(allow = {})`.
   h. Commit: walkway piece (depth = parent depth + 1), platform piece (depth = walkway depth + 1),
      props, anchors, tree edges source↔walkway↔platform. `placed += 1`, `since = 0`.
      **Terminal**: `term_roll = chance(term_pct = 35, 100)` is always drawn; the platform is
      terminal when `placed ≥ target` or `term_roll`. A terminal platform's sockets are NOT added to
      the arm's frontier (they go to the shortcut pool), so the platform becomes a dead end.
4. The chosen socket leaves the frontier whether or not it succeeded (failed sockets are kept for §6.6).

`fits(cells, allow)`: for every new cell, no existing tile in the same column within `CLEAR`, and no
existing tile in the 8 neighbouring columns within `CLEAR` unless its piece is in `allow`.

After growth: every platform that is nobody's parent gets role DEADEND. An attempt that placed fewer
than `target` platforms is rejected (§6.0).

### 6.4 Walkway archetypes (all straight; bends come from platforms)
Lateral offsets: width 3 → [−1, 0, +1]; offset 0 is the centre lane (the breadcrumb line of §6.7).
`up` = one `chance(up_pct, 100)` draw per walkway; the
generator forces `up_pct = 0` at y ≥ 24 and `up_pct = 100` at y ≤ −24 so paths stay inside the height
band. A **tread** is a run of rows at one height; consecutive treads differ by the step shown.

| arch | construction (in order of RNG draws) | step | rows | jumps |
|---|---|---|---|---|
| step | `k = ri(4,6)` treads; each tread `ln = ri(1,2)` rows | ±1 HU | 4..12 | 0 |
| stair | `k = ri(2,4)` treads; each tread `ln = ri(1,2)` rows | ±2 HU | 2..8 | k−1 |
| ledge | `a = ri(1,2)` rows, `mag = ri(2,4)`, `b = ri(1,2)` rows | ±mag HU | 2..4 | 1 |
| flat | `ln = ri(2,4)` rows | 0 | 2..4 | 0 |
| ramp | `a = ri(1,2)` rows, `n = ri(1,2)` ramp rows, `b = ri(1,2)` rows | ±1 HU per ramp row | 3..6 | 0 |

Every step respects the AUTHORING envelope in BOTH directions, so tree links are two-way (D-014).
`flat` and `ramp` are the exception by weight (§9), not the default. A walkway is never longer than
15 rows, so the hub (19) stays the widest piece in the level (§1A rule 1).

### 6.5 Platform archetypes (8; each is a parametric family, not a fixed shape)
Sockets always sit on a tile behind which the whole platform lies (so a walkway can never overlap its
own platform). Each socket = (tile, outward dir, height offset, max link width = 3). Since GEN_VERSION 4
a socket is never on a corner: it sits in the middle of a face at least 3 cells wide. Every archetype
respects §1A rule 2: bbox ≤ 7×7 cells, ≤ 40 tiles, and is at least 3 cells wide (H24).

| arch | parameters (RNG order) | what it is / what it is for |
|---|---|---|
| pad | w ∈ 3..7, d ∈ 3..min(7, 40//w); sockets at 1..w−2 / 1..d−2 on each face; 0–2 props | rest point / sub-area hub; `open` anchor if w·d ≥ 25 |
| disc | radius 2..3 (cells with x²+z² ≤ r²+r); 0–1 props | round rest point; `open` anchor if r ≥ 3 |
| cross | arm width 3 (no draw); four arm lengths 1..3 (bbox ≤ 7) | four-way junction; routing decisions |
| ell | arm width 3 (no draw); arm lengths 4..6 | corner; breaks sightlines |
| terrace | w 3..5; band depths d1 ∈ 3..4, d2 ∈ 3..7−d1, upper band +2 HU (+1 HU when gentle); sockets centred on 3-cell faces | height gain inside a sub-area |
| nook | 5..6 square walled on three sides (walled interior ≥ 3 wide); ONE socket | guaranteed dead end; `nook` anchor |
| spire | 2..3 pads 3×3 spiralling up, +3 HU each, gap 1; top socket | vertical climb; `perch` anchor on top |
| bastion | 5..6 square with a 3×3 tower +4 HU in the middle | overlook; `perch` anchor on the tower |

Prop scatter rule: props go only on flat tiles whose 8 neighbours are same-platform flat tiles at the
same height, never within Chebyshev 2 of a socket tile, never within Chebyshev 3 of another prop.
A lone 1-cell prop on an interior tile can always be walked around → props never cut a platform.

**Anchors** `[kind, x, z, y, piece]` — hints for the enemy spawner (DESIGN.md §enemies):
0 perch (high ground, long sightlines), 1 open (wide floor), 2 lane (long straight),
4 nook (enclosed/isolated). **Kind 3 is retired and reserved**: the `hop` anchor kind is never
emitted (GEN_VERSION 3) because the shape contract removed the only archetype that produced it; the
id is not reused, so old and new data can never be confused. Also: any `step` or `flat` walkway
consuming ≥ 8 rows emits a `lane` anchor.

### 6.6 Shortcuts (stream LOOP)
Collect every unused socket (spare hub sockets, failed sockets, sockets still open), shuffle, and for
each call `try_loop` until `loops_max` bridges and `drops_max` drops exist:
1. Walk a ray up to `ray_len` (20) cells out of the socket. If the first pass over the socket pool
   finds no shortcut at all, a second pass doubles the ray. In each column ignore tiles ≥ 12 HU above
   the socket height (we pass under them); the highest remaining tile is the hit. First hit ends the ray.
2. Reject if the hit belongs to the socket's own piece, is a ramp, or has a prop on it.
3. With `n = cells between socket and hit`, `dy = hit.y − socket.y`:
   - **Bridge** (two-way, role LOOP): if `|dy| ≤ n`, `n ≥ 2`, bridges < `loops_max`, and the piece
     graph distance between the two pieces ≥ 4: build n rows, width 3 (lateral −1..+1, no
     fallback), with the height
     change spread as `|dy|` single-HU steps (row k sits at `y + sign(dy)·(|dy|·(k+1)) // n`), so the
     bridge is stepped, not ramped. `fits(allow = {source, target})`.
   - **Drop ledge** (role DROP): else if `−30 ≤ dy ≤ −5`, `n ≥ 1`, drops < `drops_max`, graph
     distance ≥ 3: build a flat ledge of n rows, width 3 (lateral −1..+1). Walking off
     its end lands on the hit tile. If `dy ≥ −7`, 50%: add a **pad** on the hit tile that launches
     back up to the ledge's last centre tile (edge kind PAD, two-way); otherwise edge kind DROP.
4. A level with zero shortcuts is rejected (§6.0).

### 6.7 Gift slots — first-class output (stream GIFT)
A slot is a **stable, identified position**: `{id, x, z, y, piece, tier, occ}`.

- World position of whatever occupies the slot: `(x + 0.5, y·0.5 + 1.0, z + 0.5)`; pickup radius 0.4 u.
- `id` = 0..S−1, assigned after sorting by (piece id, tile index). Ids are stable for the level.
- **Black → gold needs zero placement logic**: black gifts spawn at every slot with `occ = 0`. When
  the beacon opens, a gold gift spawns at every slot with `occ = 0`, same position, same id.
  Collected-state is a bitset indexed by slot id (one for black, one for gold).
- **Hazards inherit slots**: `occ = 1` means the slot holds a tripmine instead of a gift, for the whole
  level (black and gold phase). Hazards never have their own placement logic. New slot-replacing
  hazards add new `occ` values; they do not add positions.

Slot target: `S = min(160, 40 + 4·(level−1)) · (1 + players) // 2`.

Candidates = tiles that are round-trip reachable, flat, prop-free, not on the dais, not a pad tile,
and (GEN_VERSION 4) **on a centre lane** (§1A.1): all four neighbour columns hold a walkable tile
within 12 HU of the candidate and, along at least one axis, the columns two away on both sides hold
none — exactly one walkable tile on each side of the gift. On a walkway that is the middle lane; on
the hub it is the middle of each stub; a platform contributes only its 3-wide strips (cross and ell
arms, spire pads, 3-deep pad/terrace strips, disc rims). Slot count, apportionment and spacing are
unchanged; only the candidate set is narrower.
Because candidates come from `rt`, a slot is never inside geometry and never unreachable by
construction; the validator re-proves both independently.

Quota per piece by largest-remainder apportionment of S over weights:
`hub: n//2` · `dead-end platform: 5n` · `shortcut walkway: 3n` · `anything else: 2n`, and every non-hub
weight × `(4 + min(depth, 8))`; n = candidate count. → depth and dead ends are richer.

Placement inside a piece: links first lay `min(quota, (len+1)//2)` slots evenly along their centre
line (a breadcrumb trail that pulls the player down the walkway); then shuffled candidates are taken
greedily with no other slot within Chebyshev 1 (spacing 2). Shortfall is filled round-robin over all
pieces at spacing 2, then spacing 1. If S still cannot be met the attempt is rejected.

`tier`: 2 = on a dead-end platform (jackpot), 1 = on a walkway or on a boundary tile (exposed), 0 = interior.

### 6.8 Tripmine occupancy (stream MINE) — canon curve, exact
- Per-slot chance = `num/400` where `num = 0` for level < 5, else `15 + min(level, 25)`.
  Level 5 → 20/400 = **1/20**. Level 25 → 40/400 = **1/10**. Linear between. Level ≥ 25 → 1/10 forever.
- One `range(400)` is drawn for every slot at every level (so the stream never shifts).
- **Hard cap**: mines ≤ `S // 5` (20%). If the rolls exceed it, mines are un-set from the highest
  slot id downward.
- `extra_mines` (the "more tripmines" curse) converts that many additional random gift slots, one at
  a time, and stops at the same cap. It never changes the per-slot chance.
- Real gifts = `S − mines ≥ S − S//5`. The game's remaining-gift counter, the beacon-open condition
  and the straggler beam (last 20% of REAL gifts) count only `occ = 0` slots.

#### 6.8.1 Contact volume and the trigger cylinder (the reason for the rule below)
A tripmine's **position** is its slot's tile centre `(x + 0.5, z + 0.5)`. **Contact** = the player's
centre is within **0.9 u horizontally** of that point, **at any height**. Height never saves the
player: **jumping over a mine does not avoid it.** The mine's **trigger cylinder** is the vertical
cylinder of radius 0.9 u around that centre, unbounded in height.

**Modelling assumption (binding for the controller ticket).** The player's centre is treated as
travelling along the straight segment between two tile centres when it moves from one tile to the
next. Under that assumption a player passing a mine on an **edge lane of a 3-wide walkway** (the mine
sits on the centre lane, §6.7) keeps its centre exactly **1.0 u** from the mine centre — a **0.1 u
margin** outside the 0.9 u cylinder. That margin is the whole reason a walkway has a bypass, so it is
stated here as a number the controller ticket depends on. (Until GEN_VERSION 3 the same margin held
for the adjacent lane of a 2-wide walkway, and a 1-wide walkway had none; neither width exists any
more.)

#### 6.8.2 The bypass graph (definition)
For a set `M` of mine tiles, the **bypass graph** `B(M)` is the movement graph of §5 (validator
envelope) with
1. every tile whose centre lies **inside** any mine's trigger cylinder removed. That is the mine tile
   itself **and every other tile in the same column** — a tile at a different `(x, z)` has its centre
   at least 1.0 u away, so the cylinder can only ever reach the mine's own column. The implementation
   still tests each candidate tile's centre with the integer distance test rather than assuming it;
2. every edge removed whose straight horizontal segment, from the source tile centre to the target
   tile centre, passes **within 0.9 u** of any mine centre. This applies to **every** edge kind —
   walk, jump, drop and pad — not only to jumps. A walk edge between two 4-adjacent tile centres is
   1.0 u long and its closest approach to a mine centre is 1.0 u unless one of its endpoints is in the
   mine's column, so in practice the walk-edge test removes nothing that rule 1 has not already
   removed; it is still computed, never assumed.

The test is integer-only: coordinates are scaled by 10 (`0.9 → 9`, `0.9² → 81`), the projection
parameter is clamped with integer dot products, and the comparison is `100·d² ≤ 81·len²` for an
interior foot, `d² ≤ 81` for a foot at either endpoint. The tile test is `dx² + dz² ≤ 81` in the same
scaled coordinates.

#### 6.8.3 Eligibility (the "walkable bypass")
Let `rt` be the round-trip set of the full graph (§5.4) and let `C(M)` be the set of tiles that rule 1
of §6.8.2 removes. A slot tile `m` is **eligible** iff
1. in `B({m})` every tile of `rt` that is **not** in `C({m})` is still round-trip reachable, and
2. `C({m})` contains no other slot tile and not the beacon tile — a gift or the beacon inside the
   cylinder is uncollectable, so a mine may never create one.

In words: a mine may never sit on a tile with no walkable bypass — removing its cylinder must
disconnect nothing that was reachable, and must not swallow another gift.

#### 6.8.4 The joint rule
For the final mine set `M` of a level, in `B(M)` every **real gift slot** (`occ = 0`) and the
**beacon tile** must still be round-trip reachable, and every round-trip tile not in `C(M)` must still
be round-trip reachable. Three mines side by side may not seal a 3-wide walkway.

#### 6.8.5 Order of operations (exact; mirror `roll_mines` in `voidgen.py`)
1. One `range(400)` is drawn per slot, in slot-id order, at every level. A slot becomes a mine only
   if its roll passes **and** the slot is eligible **and** adding it keeps the joint rule (§6.8.4) for
   the mines accepted so far. An ineligible slot is never a mine. The joint test draws no RNG.
2. Enforce the cap `S // 5`: un-set mines from the highest slot id downward.
3. `extra_mines`: while `e < extra` and `mines < cap`, build the **eligible free list** = the slot ids
   with `occ = 0`, not banned by step 3, and an eligible tile, in ascending id order; if it is empty,
   stop (place fewer — never violate the rule); otherwise draw one `range(len(free))` and try
   `free[k]`. If the joint rule rejects it, the slot is **banned** for the rest of the phase and the
   next iteration draws again. Exactly one draw per extra mine attempted. Banning can only reduce the
   number of extra mines, never break the rule.
4. Verify the joint rule for the final set; if it fails, un-set the mine with the highest slot id and
   re-check, until it holds. Deterministic; no RNG is drawn in this step. With steps 1 and 3 in force
   this never fires — it is the safety net.
5. `extra_mines` is never re-applied after step 4, so a level may end below the cap.

Why the joint rule is tested while mines are placed rather than only at the end: a random set of
roll-passing mines can violate the rule in several independent places at once, and un-setting one
mine at a time from the top then collapses the count (measured on GEN_VERSION 3 development: a
22-mine set at level 30 fell to 6, a 19-mine set at level 15 to 2). Testing each addition keeps the
count at the per-slot chance while the final set still satisfies §6.8.4 by construction.

Eligibility is a property of the level geometry, not of the roll, so an implementation may compute it
lazily and cache it per slot; the result must equal §6.8.3 exactly (the validator re-derives it by
brute force, H23).

## 7. How terrain serves the core loop

| loop moment | what the terrain data provides |
|---|---|
| spawn at closed beacon | fixed hub; spawns on the dais; ≥ 1 gift within 30 cells (H10) |
| collect all black gifts | S slots, all round-trip reachable with run + jump; breadcrumb lines on walkways teach the route outward; depth-weighted density pulls the player to the edges; every tread is a small decision (step up, drop, jump) |
| beacon opens: leave or linger | every real slot becomes a gold slot → "how many of these do I dare re-run?"; dead ends hold the most gold AND have one entrance |
| return to the beacon | tree walkways are two-way; drops and pads are faster ways home → knowing them is skill |
| enemies | props = line-of-sight cover; anchors mark perches, lanes, open floors, nooks (kind 3 `hop` is retired, §6.5) |
| tripmines | occupy slots, so a mine is always somewhere a gift would plausibly be |

## 8. Output

### 8.1 Level object (JSON field names; engine structs mirror them)
```
gen_version, seed, level, players, extra_mines, attempt
beacon [x,z,y]            spawns [[x,z,y] × 8]          arms [trait name per arm]
pieces [{id, kind(0 platform/hub,1 walkway), arch, parent, depth, arm, role, y, bbox[minx,minz,maxx,maxz], tiles, jumps, w}]
tiles  [[x,z,y,kind,piece]]        props [[x,z,y,h,kind,piece]]
edges  [[a,b,kind]]  kind 0 tree, 1 loop, 2 drop, 3 pad
gifts  [{id,x,z,y,piece,tier,occ}]
anchors [[kind,x,z,y,piece]]       pads [[x,z,y,tx,tz,ty]]
```
Roles: 0 hub, 1 platform, 2 dead-end platform, 3 walkway, 4 loop bridge, 5 drop ledge.

### 8.2 Canonical text and hash
Lines, LF-terminated, in this order, integers in decimal:
```
VOIDGEN <gen_version>
IN <seed> <level> <players> <extra_mines>
ATTEMPT <attempt>
BEACON x z y
SPAWN x z y                     (8 lines)
ARMS <trait> <trait> ...
P id kind arch parent depth arm role y minx minz maxx maxz tiles jumps w     (per piece)
T x z y kind piece              (per tile, creation order)
O x z y h kind piece            (per prop)
E a b kind                      (per edge)
G id x z y piece tier occ       (per slot)
A kind x z y piece              (per anchor)
X x z y tx tz ty                (per pad)
END
```
`hash = SHA-256(text as UTF-8)`, lowercase hex. Two implementations agree iff hashes agree.

## 9. Tuning knobs (all in `tuning(level, players)`; `t = min(level, 30)`)

| knob | value | meaning |
|---|---|---|
| plat_max | min(12, 4 + level//3) | platform ceiling; the level's target is `ri(plat_max−1, plat_max)` (§6.2) |
| arms_min / arms_max | 2/3 below level 4, else 2/4 | arms out of the hub |
| radius | 70 + 2t | max \|x\|, \|z\| |
| slots | §6.7 | gift slot target |
| loops_max | 2 + t//6 | max two-way bridges |
| drops_max | 2 + t//8 | max drop ledges |
| ray_len | 20 | shortcut ray length (doubled on a second pass when the first finds nothing) |
| loop_min_graph_dist | 4 | a bridge must skip at least one platform |
| grow_tries | 5 | attempts per socket |
| arm `share` / `deep` | ri(1,4) / 25,40,55,70,85 % | per-arm size weight / spine-vs-branch bias |
| turn_pct | 75 | chance a straight-through socket yields to a turning sibling |
| walk_w | step 20 · stair 6+t//3 · ledge 5 · flat max(1, 4−t//8) · ramp max(2, 5−t//6) | walkway mix; `flat` and `ramp` are the exception at every level |
| plat_w | pad 10 · disc 7 · cross 10 · ell 8 · terrace 8 · nook 5 · spire 3+t//5 · bastion 5 | platform mix |
>>>

| plat_pct | 40 | chance a walkway's far end gets a platform once `since ≥ 2` |
| term_pct | 35 | chance a platform is terminal (a dead end) |
| jump_min_depth | max(1, 10 − t) | pieces shallower than this are jump-free: 9 (L1), 8 (L2), … 2 (L8), 1 = off (L9+) |

Global constants: CLEAR 12, SLAB 2, Y_MIN −48, Y_MAX 72, MAX_ATTEMPTS 24, JUMP_GAP (5,4,3),
AUTH_GAP (4,3,2), JUMP_UP_MAX 4, DROP_MAX 60, height band ±24 HU for the `up` bias.

Difficulty ramps through: more platforms and slots; more `stair` and `ledge`
walkways and fewer `flat`/`ramp` ones; more shortcuts to learn; `hop`/`thin` arms more likely; the
gentle-start zone shrinking to nothing by level 9.

## 10. Headless validator (`terrain_ref/validate.py`)

The validator is an INDEPENDENT implementation: it reads only the Level object, rebuilds the movement
graph from §5 with its own code, and judges. It must not import generator internals except
`generate`, `level_hash`, `slot_target`, `mine_chance_num`.

Every threshold below was fixed BEFORE measuring and carries its gameplay reason (D-030). If one
fails, fix the generator. Changing a threshold requires a new DECISIONS.md entry.

### 10.1 Hard checks — must hold for EVERY generated level (0 failures over the harness)

| id | check | reason |
|---|---|---|
| H1 | generating twice gives the same hash | determinism / seed-only sync |
| H2 | slot count == `slot_target(level, players)` | economy is computed from S |
| H3 | every slot sits on a distinct existing tile that is flat, prop-free, not on the dais, not a pad tile, and in `rt` | "validated, never inside geometry", reachable by all classes |
| H4 | for every slot: no other tile in its column with y in (slot.y, slot.y + 12) and no prop in its cell → **0 intersections, not 0.01%** | v1 shipped 5 intersecting gifts |
| H5 | mines ≤ S // 5; mines == 0 when level < 5; real gifts ≥ S − S//5 | canon caps; gift-density invariant |
| H6 | soft-lock tiles == 0 | a player can never be stranded alive |
| H7 | any two tiles in one column differ by ≥ 12 HU | headroom |
| H8 | hub intact: 205 hub tiles, beacon tile (0,0,1) and all 8 spawn tiles exist and are walkable | fixed anchor |
| H9 | playable area: `|rt| / |walkable| ≥ 0.98` | geometry you can see, you can stand on |
| H10 | path distance from beacon to the nearest REAL gift ≤ 30 cells | first gift within ~3.5 s of running (feel budget ≤ 8 s) |
| H11 | starvation: for tiles in `rt`, path distance to the nearest REAL gift has p95 ≤ 27 cells and max ≤ 54 cells | "always collecting": ≤ 3 s of running to the next gift almost everywhere, ≤ 6 s in the worst spot (RUN_SPEED 9) |
| H12 | structure: arms ≥ 2; dead-end platforms ≥ 2; platforms ≥ `plat_max − 1`; max piece depth ≥ 3 | it is a branching puzzle, not a corridor |
| H13 | fair reach: every slot is also round-trip reachable when the graph is rebuilt with AUTH_GAP (4,3,2) | no gift demands a limit-of-physics jump |
| H14 | shortcuts (loop bridges + drop ledges) ≥ 1 | every level has a routing decision |
| H15 | attempt ≤ 12 | the re-roll loop has huge headroom before MAX_ATTEMPTS |
| H16 | spawn platform: exactly one role-0 piece; its tile count and bbox max dimension are strictly greater than every other **platform**'s (a path is not an area); its largest flat walkable component is strictly larger than every other flat walkable component; it holds the beacon tile, the 8 spawn tiles and the 25-tile dais | the canon shape has ONE dominant spawn platform (§1A rule 1) |
| H17 | every row of every walkway piece is **exactly 3** cells wide (recomputed from its tiles; rows are taken along the walkway's travel axis, the axis along which it touches its parent piece — the bbox long axis is wrong for a 3-wide walkway of 1–2 rows). GEN_VERSION 2–3: "at most 2". Min 3 is the owner's rule (J1); max 3 keeps a unique centre lane and keeps paths from becoming rooms | paths are 3-wide walkways, never rooms and never balance beams (§1A rule 2) |
| H18 | every platform piece has bbox ≤ 7×7 and ≤ 40 tiles; the platform count is in [3, `plat_max`] | platforms are rest points, not rooms (§1A rule 2) |
| H19 | path share: Σ walkway length / (Σ walkway length + Σ platform length) ≥ 0.70, and walkway tiles ≥ 50% of non-hub walkable tiles | the level is mostly route (§1A rule 2) |
| H20 | flat-share ≤ 0.35 and ramp-share ≤ 0.10 of path rows | flat runs and ramps are the exception (§1A rule 3) |
| H21 | elevation variance σ over non-hub tiles ≥ `3 + 3·(min(level,10)−1)//9` HU | paths gain and lose height (§1A rule 3) |
| H22 | at least 50% of sub-area boundaries have |Δy| ≥ 1 HU | a sub-area is entered by a step, not a walk (§1A rule 3) |
| H23 | **no tripmine without a walkable bypass**: for every level, every mine slot is eligible by the brute-force definition of §6.8.3 (remove every tile inside the mine's trigger cylinder — the mine tile and every tile in its column — and every edge, walk included, whose segment passes within 0.9 u of the mine centre, then recompute the round-trip set) **and** the joint rule of §6.8.4 holds for the level's mine set | with a 0.9 u contact radius that a jump does not clear, a mine on a path with no way around is a lethal wall, not a fake gift the player chooses not to touch |
| H24 | **every walkable piece is at least 3 cells wide**: every tile lies inside a full 3×3 square of cells, each holding a tile of the same piece or of a piece joined to it by an edge (§1A.1). Footprint only | owner rule (J1, GEN_VERSION 4): nothing narrower than 3 anywhere — the walkway check H17 alone cannot see a narrow platform part |
| H25 | **every gift slot is on a centre lane** (§1A.1, §6.7): all four neighbour columns hold a walkable tile within 12 HU and, along at least one axis, exactly one walkable tile on each side | owner rule (J1, GEN_VERSION 4): gifts sit in the middle of the path, never on an edge |

Path distance = Dijkstra over the movement graph; walk edge cost 1, jump/drop/pad cost
`max(|dx|,|dz|)`. For H11 run one multi-source Dijkstra from all real-gift tiles on the REVERSED graph.

H16–H22 are recomputed from the Level dict alone: walkways are the pieces with `kind = 1`, platforms
the pieces with `kind = 0` that are not the hub, and every width, length, tread, flat run and height
delta is derived from `tiles` (never from generator internals).

### 10.2 Distribution checks — over the whole harness sample

| id | check | reason |
|---|---|---|
| D1 | mine curve: for each level L ≥ 5 in the sample, observed **mines / eligible slots** is within ±1.0 percentage point of `(15 + min(L,25))/400`; exact table check `mine_chance_num`: L4→0, L5→20, L15→30, L25→40, L26→40, L99→40. The validator recomputes eligibility itself (§6.8.3) to get the denominator. **Definition change (GEN_VERSION 3, D-026):** the denominator was `slots`; the per-slot chance now applies only to eligible slots, so measuring over all slots would under-report and hide an over-rate on the slots that can actually hold a mine. This tightens the check (the eligible set is a subset of the slots). | canon 1/20 → 1/10, capped |
| D2 | with `extra_mines = 999` (100 seeds at levels 5, 15, 30): `mines == min(S // 5, E)` where `E` = the number of eligible slots, both computed independently by the validator. **Definition change (GEN_VERSION 3, D-026):** the old form was `mines == S // 5` exactly, which is now impossible when fewer than `S // 5` slots can hold a mine; the cap is still the binding limit whenever `E ≥ S // 5`. If the joint rule (§6.8.4) forces the generator below that number, the level is reported as a D2 failure with its seed — the check is not relaxed. | the curse can never beat the 20% cap |
| D3 | all hashes distinct across the sample | never the same level twice |
| D4 | footprint similarity (§10.3) over 4,000 random same-level pairs: p99 ≤ 0.50 and share of pairs ≥ 0.60 is ≤ 0.1% | two levels "feel the same" when > 60% of their coarse footprint coincides under any rotation/mirror |
| D5 | recipe repetition: share of same-level pairs with identical (sorted arm traits, sorted platform-archetype multiset, sorted walkway-archetype multiset) ≤ 0.1% | same ingredients = same feel |
| D6 | within-level repetition: per level, share of platforms whose (arch, bbox width, bbox depth — sorted so rotation does not matter) equals another platform's in that level; mean over sample ≤ 10% | v1: 91.6% of levels had a repeated pattern |
| D7 | difficulty ramp: mean D (§10.4) is strictly increasing over level buckets 1–5, 6–10, 11–15, 16–20, 21–25, 26–30 | later levels are measurably harder |
| D8 | gentle start: at level 1, mean J ≤ 50 and max J ≤ 80 (J = % of slots that need ≥ 1 jump, §10.4) | a new player gets half the gifts without jumping |
| D9 | generation time: mean ≤ 0.25 s and max ≤ 2.0 s per level in Python | harness stays fast; load screen is never the generator |

### 10.3 Footprint similarity
1. **Anchor to the spawn root**: every tile coordinate is taken relative to the level's beacon tile
   `(x − beacon.x, z − beacon.z)`, so a shifted duplicate still scores as a duplicate.
2. Apply one of the 8 dihedral transforms (rotations/mirrors about the beacon) to those TILE
   coordinates.
3. Block: (bx, bz) = (floor((x+128)/4), floor((z+128)/4)); a block is ON if it contains any non-hub
   tile (tiles of piece 0 are skipped).

**The 0.50 and 0.60 limits of D4 are defined ONLY for 4-cell blocks.** Changing the block size
invalidates them: at 8 cells a block is room-sized, the metric measures density instead of structure
and its noise floor (p99 0.54) is above the limit. A different block size needs its own measured
noise floor and a new DECISIONS entry (D-022, FINAL).

**Verify by eye**: the harness prints its 5 most similar same-level pairs. Render them
(`render.py --seed S --level L`) and look, together with the same-level pairs of the pinned gallery
(§11). A pair scoring ≥ 0.60 that also looks alike is a generator defect; a pair that scores high but
looks different is a metric defect — record either in DECISIONS.md.

Similarity
of A and B = max over the 8 dihedral transforms of B (apply to tile coordinates before blocking) of
`|A ∩ B'| / |A ∪ B'|`.

### 10.4 Reported metrics (per level, and mean/min/max per level bucket in the report)
- `walkable`, `playable_pct` (H9), `platforms`, `walkways`, `dead_ends`, `max_depth`, `arms`
- `loops`, `drops`, `pads`
- `chokepoints` = walkway pieces whose removal disconnects the piece graph (bridges of
  the undirected piece graph restricted to walkways). These are the places enemies trap you.
- `J` = % of slots NOT round-trip reachable using walk edges only
- `N` = **% of path length that is 1 cell wide**. **Since GEN_VERSION 4 N is 0 by construction**
  (every walkway is 3 wide) and adds nothing to `D`; it is still computed and reported, so a
  regression to narrow paths would show. The D7 ramp is carried by S, K, V and J alone (measured:
  still strictly increasing). The old note: (redefined for GEN_VERSION 2: when every walkway is
  ≤ 2 wide, "% of links with w ≤ 2" is always 100 and measures nothing; the width-1 share is the
  quantity that actually rises with level, §1A rule 2)
- `V` = (max tile y − min tile y) / 2, in u
- `K` = mean slot piece depth
- `gift_density` = real gifts per 100 walkable tiles
- `first_gift` (H10), `starve_p95`, `starve_max` (H11)
- `path_share` (H19), `path_tile_share` (H19), `flat_share` (H20), `ramp_share` (H20),
  `elev_var` (H21), `junction_step_pct` (H22)
- `tread_dy_hist` = histogram of |Δy| between consecutive treads along every walkway (buckets
  0, 1, 2, 3, 4+), `junction_dy_hist` = histogram of junction deltas (same buckets)
- **Difficulty score** `D = J + 0.5·N + V + 0.25·S + 2·K`
- `gen_ms`

### 10.5 Harness
`python validate.py --seeds 0:5000` → level for seed s is `1 + (s mod 30)`; prints one PASS/FAIL line
per check with the measured number and the threshold; writes `out/report.json`; exit code 0 iff all
pass. `--jobs N` uses multiprocessing. `--selftest` plants defects into a generated level (a slot
moved onto a prop; a slot moved to a tile cut off from the hub; a tile inserted 4 HU above another;
occ flipped to exceed the cap; a ledge tile group reachable only by a drop with no return; a second
area as large as the hub; a walkway narrowed to 2 cells; a walkway widened to 4 cells; a platform grown past 7×7; every walkway
relabelled as a platform; every walkway flattened; every non-hub tile set to y=0; every platform
flush with its path; a mine flipped onto a tile with no bypass (when no slot lacks one, the side
lanes of a walkway are carved away around a slot first); three mines placed side by side sealing a
3-wide walkway; a mine whose trigger cylinder swallows another gift slot (a tile is planted 12 HU above
a slot when no slot shares its column); a one-cell-wide strip of tiles; a gift moved onto an edge
lane) and
asserts the matching H-check FAILS for each — a validator that cannot fail is not a validator.
18 defects.

## 11. Pinned gallery (`terrain_ref/gallery.json`)

16 fixed (seed, level) pairs. For each the file stores: `hash`, `attempt`, `platforms`, `tiles`, `slots`,
`mines`, `loops`, `drops`, `pads`, `arms`, `dead_ends`. `python gallery.py --check` regenerates all 16
and compares every field; any difference = regression, visible without eyes. `python gallery.py
--write` is run only together with a GEN_VERSION bump.

| # | seed | level | why it is pinned |
|---|---|---|---|
| 1 | 1 | 1 | the old fixed first level (DEFAULT_SEED 1, retired in J1: each run now draws a fresh seed); still what start_run(1) and the pinned app tests build |
| 2 | 2 | 1 | level 1 with a bridge (pinned in GEN_VERSION 3 as a two-arm level with bridges AND a drop; at GEN_VERSION 4 it is three arms, one bridge) |
| 3 | 3 | 1 | three-arm level 1 |
| 4 | 1001 | 2 | early |
| 5 | 1002 | 3 | `stair` walkways become legal |
| 6 | 1003 | 4 | four arms become legal |
| 7 | 1004 | 5 | first tripmines (1/20) |
| 8 | 1005 | 8 | the gentle-start zone is nearly gone |
| 9 | 1006 | 10 | elevation-variance floor reaches its cap (6 HU) |
| 10 | 1007 | 12 | mid game |
| 11 | 7 | 12 | mid game, four arms |
| 12 | 1008 | 16 | mid-late (pinned in GEN_VERSION 3 for the width-1 share, which no longer exists) |
| 13 | 1009 | 20 | late |
| 14 | 1010 | 25 | tripmine chance reaches 1/10 |
| 15 | 7 | 30 | platform ceiling reached (12) |
| 16 | 1011 | 40 | beyond every cap: must equal level-30 tuning except slots and seed stream |

Expected properties asserted for ALL gallery entries (in addition to the pinned fields): every H-check
passes; `mines == 0` for entries 1–6; `slots == slot_target(level, 1)`; entry 16 has `slots == 160`.

## 12. Art direction — serious, moody, readable

The world is solemn. Nothing in the terrain is a joke. The enemies (bright, silly PNG billboards) are
the only comedy, and they work BECAUSE the world never winks.

### 12.1 Rules
1. One hue family per level. The default family is **Deepwater** (teal/cyan). Other families are
   palette swaps of the same roles (DESIGN.md §biomes).
2. The void is a coloured atmosphere, never pure black.
3. Structure is legible from colour: **platforms are cyan checker, walkways are blue checker**. A player
   reads the level graph at a glance.
4. Danger is the only warm/pink/red thing in the frame. Gold is reserved for gold gifts and the open
   beacon.
5. Blocky voxel: all geometry is axis-aligned boxes and 26.57° ramps. No bevels, no curves, no
   smooth shading. Textures use nearest filtering.
6. Fog hides distance, never the next step.

### 12.2 Deepwater palette (sRGB hex)

| role | colour | notes |
|---|---|---|
| void / clear colour | `#010B0C` | |
| fog colour | `#021416` | exponential depth fog, density 0.012 per u |
| platform checker light | `#2FB7B0` | emission 0.35 × albedo |
| platform checker dark | `#0A2E30` | |
| walkway checker light | `#2A5BFF` | emission 0.35 × albedo |
| walkway checker dark | `#0B1A66` | |
| dead-end platform checker light | `#8FE8E0` | paler = "something is here" |
| slab side | `#0E3F42` | 1 u tall |
| slab trim band (top 0.125 u of the side) | `#1C6E70` | |
| hub dais | `#1C6E70` with star sigil `#031A1B` | 12-point star, 5×5 tiles |
| prop block / wall / pillar | `#12474A` | side trim `#1C6E70` |
| prop crate | `#1A5A52` | |
| support spike under platforms | `#0A2E30` | |
| launch pad | `#2A5BFF` top, pulsing emission 0.5–1.5 at 1 Hz | |
| black gift | body `#050608`, rim emission `#7CFFF4` × 1.5 | |
| gold gift | `#FFC83D`, emission × 2.0 | |
| tripmine tell | particles `#FF4FD8` | the only pink in the level |
| beacon closed | `#3A4A55`, emission 0 | |
| beacon open | `#E8FFFF`, emission × 4.0, light column to Y +60 u | |
| danger text / kill indicators | `#FF2A2A` | |
| ambient light | `#0B3A3C`, energy 1.0 | no sun, no directional shadows |
| player fill light | `#BFFFF8`, omni, range 18 u, energy 1.2 | follows the player |

Checker: 1 tile = 1 square; light if `(x + z) & 1 == 0`. Texel density 8 px per u, nearest filter.
Surface grain: per-texel value noise ±6% lightness (hash of texel coords; static, not animated).

### 12.3 Fog-readability check (applies to every model and terrain element)
`visible(d) = exp(−0.012 · d)`; on-screen colour = `lerp(fog, colour, visible(d))`.
Requirement (WCAG relative luminance contrast ratio, computed on the fogged colours):
- platform/walkway checker light vs fog colour at d = 60 u: contrast ≥ 3.0
- platform checker light vs platform checker dark at d = 40 u: contrast ≥ 2.0 (the checker still reads)
- black gift rim, gold gift, tripmine particles, open beacon vs fog at d = 60 u: contrast ≥ 4.5
- every enemy PNG's mean opaque colour vs fog at d = 40 u: contrast ≥ 3.0 (ENEMIES.md hard rule)
A script computes these from the palette file; the build fails if any is below threshold.
Rationale: 60 u ≈ 6.7 s of running = the planning horizon; 40 u ≈ the dodge horizon.

### 12.4 Engine dressing derived from the data (deterministic, no RNG beyond `mix(seed, piece id)`)
- Under each PLATFORM (role 1 or 2, bbox ≤ 7×7): an inverted stepped spike below the bbox centre —
  1×1 cell for 8 HU. Skipped entirely if any of its 9 columns contains a tile below the platform.
  Platforms are small, so the spike is small: the silhouette stays a thin causeway, not a tower.
- Under the HUB: nothing. The spawn platform is the anchor of the level and reads as a solid mass on
  its own; a spike under a 19×19 slab would dominate the frame.
- Under each WALKWAY: nothing (thin causeways floating over the void are the look).
- Slab sides get the trim band. Hub dais gets the star sigil decal.
- Far backdrop: 0 geometry. Only fog + sparse drifting motes (`#2FB7B0`, alpha 0.25, 40 per 100 u³
  near the camera). No skybox image.
