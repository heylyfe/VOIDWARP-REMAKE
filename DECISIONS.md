# DECISIONS.md — VOIDWRAP RUN remake

Read this file FIRST if you are taking over as orchestrator (Opus 5.5 or DeepSeek V4.1).
Every entry = decision + WHY. Continue this reasoning; do not restart it.
Append new entries at the bottom of the matching section with the next D-number. Never rewrite old
entries — supersede them with a new entry that names the old one.

Marker: [CONTESTABLE] = genuinely 50/50, picked one to keep moving. The owner may flip these;
agents may not.

## Status board (update on every handover)

| Stage | Artifact | State |
|---|---|---|
| 1a | TERRAIN_SPEC.md | written (GEN_VERSION 1) |
| 1b | TERRAIN_REF.md + terrain_ref/ (Python) + GDScript port | generator frozen; validator + port: see Handover log |
| 2 | DESIGN.md + game/data/offering_schedule.json | written |
| 3 | FLEET_PACK.md + README.md | written |

## Model budget (owner-set, binding for every orchestrator)

- Up to 10 parallel Inkling 2 Small: spawn (model:opencode/opencode/inkling-2-small-free) — rote work.
- Up to 3 GLM 5.3 Flash: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash) — implementation tickets.
- Up to 3 DeepSeek V4.1: spawn (model:acpRegistry_mistral_vibe/deepseek-v4) — orchestration / cross-ticket
  coordination; if it also implements, implementation happens in a separate fresh thread.
- Opus 5.5: only if absolutely necessary. Running out of Inkling budget is preferable.
- Drain cheap models first. The lead model's own tokens are the scarcest resource.

---

## A. Engine and language

### D-001 — Engine: Godot 4 (latest stable 4.x, standard build, NOT the .NET build). Language: GDScript.
WHY:
- Hard req (1) real native .exe: Godot export templates produce a standalone Windows executable. No
  browser, no Electron.
- Hard req (2) fleet iteration: no compile step for GDScript (the retro measured 25 s incremental
  rebuilds, a 4.5 min gate and 31 GB of build artefacts in Rust — two-thirds of 43 h was gate wait).
  `godot --headless --script <file>` runs tests from a CLI; project files are text (.tscn/.tres/.gd)
  so agents can diff and merge them.
- Hard req (3): 3D, ArrayMesh/SurfaceTool for voxel slabs, `BaseMaterial3D.billboard_mode` +
  alpha-scissor for PNG sprites, built-in depth fog / volumetric fog.
- Hard req (4): MIT licence. No seat fees, no revenue share.
- GDScript over C#: C# needs the .NET build + an SDK + a compile step, and fragments the fleet's
  toolchain. GDScript over GDExtension/Rust: reintroduces exactly the build cost the retro condemns.
- Nothing beat Godot specifically. Bevy/Rust = the retro's friction again. Unity/Unreal = licence
  terms + binary scene formats + slow headless startup. Raylib/C = fast, but the fleet would spend
  the night rebuilding an engine (scene, UI, audio, export) instead of the game.

### D-002 — Exact Godot version is whatever `tools/godot/VERSION.txt` says.
WHY: the lead's knowledge of "latest" may be stale. A rote agent fetches the newest stable 4.x from the
official GitHub releases and pins it in that file. Every command in FLEET_PACK uses
`tools/godot/godot.exe` (gitignored binary), never a system install. Do not bump mid-run.

### D-003 — Terrain generator exists twice: Python reference (oracle) + GDScript port (shipping).
WHY:
- Python (stdlib only, `terrain_ref/`) is the portable reference the owner asked for when engine
  harness runs are slow: it runs the 5,000-seed harness across all cores with zero engine dependency.
- The GDScript port is what ships. It must be byte-identical: both emit the same canonical text and
  the same SHA-256 for every (seed, level). Golden hashes for the pinned gallery are committed.
- The Python reference stays the oracle forever: a generator change lands in Python first, the
  harness proves the invariants, the goldens are regenerated, then GDScript is brought to parity.
  Port path is in TERRAIN_REF.md.

### D-004 — Generator math is integer-only with its own RNG.
WHY: seed-only multiplayer sync is a hard requirement. Floats, engine RNGs, hash-ordered containers
and trig differ across languages/platforms. Integers + a specified 32-bit RNG + insertion-ordered
iteration make byte-identical output trivial to keep. See TERRAIN_SPEC.md §3.

### D-T010-1 — Float fields enter the state hash as the 16 hex digits of their IEEE-754 64-bit pattern, taken via `StreamPeerBuffer.put_double` (R4 ADDENDUM, T-010).
The addendum forbids hashing a float's decimal string and prescribes the 64-bit pattern instead, but
no document says how to get the bits in GDScript. `StreamPeerBuffer.put_double` performs exactly that
conversion (IEEE-754 binary64, little-endian bytes); `state_hash.gd` formats the 8 bytes
most-significant-byte first into 16 hex digits. `test_replay.gd` pins the byte order with known
answers (`1.0 → 3FF0000000000000`, `-2.5 → C004000000000000`), so a wrong endianness assumption fails
the test, not the night. WHY: bitwise-exact, no trig/log needed, and the conversion is a format
operation, not float math, so the DESIGN.md §13 rule 5 float restriction is untouched.

### D-T010-2 [CONTESTABLE] — move_x / move_z axis scale: int8 in −127..127 = −1..+1 of RUN_SPEED, clamped; neutral input = (0, 0, 0).
DESIGN.md §13 rule 2 fixes the PlayerInput fields (`move_x: int8, move_z: int8, world-space,
pre-rotated`) but no document states the axis scale. Reading chosen: the axes are signed int8 where
127 = full run speed in that world direction, values are clamped to ±127 on construction, and
`scaled = axis / 127.0 × RUN_SPEED`. WHY: an int8 axis is the natural wire format for an analog stick
and 127 is the maximal one-sided value; per-tick velocity (no acceleration) keeps tick 1 identical
across replays. Alternative readings (−128..127 raw, or a normalized float axis) change only the
scale constant in `sim.gd`; nothing else in the sim depends on it. Gameplay reason: camera-relative
steering must be convertible client-side without sim knowledge — world-space int8 is already that
wire format.

### D-T010-3 [CONTESTABLE] — sim RNG sub-streams are named, per-run, re-seeded per level: `s(mix(mix(run_seed, 900 + id), level_number))`, ids world=1, fx=2, enemy_ai=3, loot=4.
DESIGN.md §13 rules 1 and 4 say randomness only through Rng streams stored in state and same
Mulberry32 as terrain, but no document names the sim's streams or their seeds (D-017 names only the
terrain generation phases PLAN=1..MINE=5). T-010 needs the streams to exist in the hashable state
even while no gameplay draws from them yet. Chosen: `sim/run_state.gd` owns a fixed insertion-ordered
table (the numbers 900+ and the four ids are SPEC GAP, gameplay reason: a distinct high base offset
keeps sim streams from ever colliding with the terrain phase streams 1–5 mixed against the same
run_seed), re-seeded on every `load_level` so a level boundary cannot leak stream state into the next
level. The enemy/fx/loot ticket owners re-point their draws at these named streams; renaming or
adding a stream is a hash-visible change and must come with a replay-test run.

### D-T010-4 — T-010 ships a PLACEHOLDER kinematics inside `sim.gd` step; T-012's `sim/collision.gd` + `sim/controller.gd` supersede it.
The replay test needs a sim whose state is genuinely input-sensitive, but the controller (AABB vs
slabs/ramps/props, coyote, jump buffer, step-up, classes, void charges, safe tile) is T-012's
assignment. T-010's step therefore implements only: per-tick velocity from move axes (D-T010-2),
gravity 32 u/s², jump-impulse 12 u/s on the JUMP press edge while grounded, vertical integrate, and
a column lookup ground snap ("top of the highest tile in the current cell", ramps treated as their
low edge Y×0.5, props ignored, no swept collision, no horizontal OOB clamp, falls past the kill plane
continue falling — D-043/D-050 logic stays untouched for T-012). Ground height is looked up from a
column map built once per level from the level's tiles. floor/ceil for world→cell conversion are
implemented with comparisons only (+ − × ÷), keeping DESIGN.md §13 rule 5 true. WHY of the placeholder
shape: it exercises every input bit path the hash must see (move, jump edge, prev-button edge state)
without pre-empting any T-012 decision; T-012 replaces the internals of `sim.gd` step and the
player-row fields, and `test_replay.gd` keeps passing unchanged.

### D-T010-5 — Events are returned, never stored in state; `sim/events.gd` owns the type constants; fixed event shape {type, tick, player}.
DESIGN.md §13 says `step(state, inputs) -> events`, so the event list is a fresh Array[Dictionary]
per step: an event is derived data (view eats it), not state, and hashing never walks it (a repeated
`step` on the same inputs cannot change the state hash). Shape frozen now so later tickets append
event kinds, not new shapes: every event is `{"type": String, "tick": int, "player": int}` plus
type-specific int/float fields, and the type constants live in `sim/events.gd` (T-010 so far:
"spawn", "jump", "land"). WHY: one fixed shape keeps the future netcode frame trivially
serializable and keeps the boundary scan free of per-ticket exceptions.

---

## B. Terrain (Stage 1)

### D-010 — Algorithm: spawn-rooted graph growth with parametric piece generators (NOT a hand-authored pattern catalog).
WHY:
- The v1 run assembled 132 hand-authored patterns by socket matching. Measured result: 91.6% of
  levels contained a repeated pattern, and unreachable geometry lived inside patterns for the whole
  run (`pb_machine_gauntlet`). A finite catalog cannot give "almost never the same level twice".
- Parametric archetypes (a ring room with width/depth/hole/height parameters is thousands of rooms,
  not one) remove catalog repetition at the source.
- Growing outward from the beacon hub through sockets makes "spawn is the root" literally true: the
  level IS a tree of rooms and links rooted at spawn, plus deliberate loop-closures (shortcuts) and
  drop ledges. Depth-from-spawn, branch identity and dead-end status are known by construction and
  are emitted as data, so gifts, difficulty and enemy anchors can use them.
- Rejected: WFC (no global structure, hard to guarantee reachability), noise heightfields (terrain
  as backdrop — the opposite of "the level is a puzzle"), BSP dungeons (boxy, single-layer, reads
  as an indoor dungeon rather than causeways over a void).
- v1's pattern JSON is NOT ported. Its valuable ideas (socket matching, validate-then-retry,
  reachability graph, gift filling on validated tops) are all kept in the new algorithm.

### D-011 — Geometry model: walkable TILES on an integer grid are the primary output; meshes are derived.
Cell = 1 u × 1 u horizontally. Height unit HU = 0.5 u (integer). Ramps rise 1 HU per cell.
WHY: one representation serves the renderer (merge tiles into slabs), the collision builder, the
validator's movement graph and the gift placer. "Never inside geometry" becomes an integer lookup,
which is how gift-spawn intersection gets to exactly 0 (v1 shipped 5 of 755,878).

### D-012 — Movement constants are carried over from v1 unchanged and the terrain limits are derived from them.
GRAVITY 32, JUMP_VELOCITY 12 (apex 2.25 u), RUN_SPEED 9, PLAYER_HALF_WIDTH 0.4, PHYSICS 60 Hz.
WHY: the retro says these were tuned against real playthrough data. Retro §5.4: every threshold must
be derivable from a gameplay statement — the jump envelope in TERRAIN_SPEC §5 is derived from these
numbers, not picked.

### D-013 — Mandatory routes use only the BASE movement kit (run + single jump).
WHY: all three classes share run + jump. Dash, glide and double-jump are bonuses that open
optional skips; no gift may require them. One validator, one guarantee, all classes.

### D-014 — Tree links are always two-way; one-way drops exist only as extra (loop) connections.
WHY: guarantees zero soft-lock tiles by construction (the validator still asserts it). A one-way drop
is then always a choice ("commit to this shortcut"), never a trap.

### D-015 — Hazard occupancy (tripmines) is rolled inside the generator, per gift slot, from its own RNG stream.
WHY: canon says hazards inherit validated gift positions and never get their own placement logic.
Rolling it inside the pure generator means clients agree on which slot is a mine from the seed alone,
and the harness can assert the 1/20→1/10 curve and the 20% cap on the real output.

### D-016 — Generator inputs are (run_seed, level, players, mods). Output is a pure function of exactly those.
WHY: "pure function of the seed alone" needs the level index (difficulty ramp) and the run's voted
modifiers (e.g. extra tripmines). `level` and `mods` are derived from the synced input stream (votes
are inputs), `players` from the lobby. Nothing else may influence generation — no clock, no globals,
no settings, no locale. Single-player always passes players=1, mods=default.

### D-017 — Each generation phase draws from its own RNG sub-stream.
WHY: retro §1d — widening a content pool shifted one shared RNG stream into a latent defect and
changed every level. With per-phase and per-piece sub-streams, adding a decoration roll cannot move a
gift, and adding an archetype changes only the pieces that pick it.

### D-018 — Every level must contain ≥ 1 shortcut; an attempt without one is re-rolled (deterministically).
WHY: measured 18% of level-1 layouts had no bridge or drop — a pure tree has no routing decision.
Re-rolling costs ~0.02 s. MAX_ATTEMPTS = 24, the last attempt waives the rule so generation can never
fail; the harness asserts attempt ≤ 12.

### D-019 — Gentle-start rule (`jump_min_depth`): near the hub, early levels are jump-free.
WHY: first measurement had level-1 J (share of gifts needing a jump) at mean 51%, max 100% — against
the pre-stated limit "mean ≤ 50, max ≤ 80" (a new player gets half the gifts without jumping). Fixed
in the generator (now mean 11%, max 58% at level 1; 32% at level 3; 71% at level 8), threshold untouched.

### D-020 — Shape-uniqueness re-roll inside a level.
WHY: first measurement of within-level room repetition was 20.7% against the pre-stated 10% limit
(v1's complaint was repetition). Rooms now re-roll up to 4× until their (archetype, footprint, tile
count) is new in the level → 8.5%. Threshold untouched.

### D-021 — Measured headroom on the gift-density invariant (for whoever tunes later).
Starvation p95 is 9–12 cells (limit 27), worst-case max 27 (limit 54), first gift ≤ 22 cells
(limit 30), playable area 100%. There is room to make levels sparser or bigger without breaking H10/H11.

### D-022 — FINAL — Footprint similarity: block size 4 cells, threshold 0.50 unchanged.
DECISION: the cross-seed similarity check (TERRAIN_SPEC §10.3, D4) uses 4-cell blocks. Limits stay
p99 ≤ 0.50 and at most 0.1% of same-level pairs ≥ 0.60.
WHY: at 8 cells the measured noise floor (p99 0.54) sits above the 0.50 limit, so the metric cannot
discriminate; 8-cell blocks are room-sized and conflate density with structure.
REQUIREMENTS (all three implemented 2026-11-16):
1. TERRAIN_SPEC §10.3 states that the 0.50 / 0.60 limits are defined ONLY for 4-cell blocks and that
   changing the block size invalidates them (a new block size needs its own measured noise floor and
   a new DECISIONS entry).
2. Both terrains are anchored to the spawn root before comparing: tile coordinates are taken relative
   to the beacon tile, the 8 rotations/mirrors are applied to those coordinates, then they are blocked.
   A shifted duplicate scores 1.0 and a rotated or mirrored duplicate scores ≥ 0.60 — both asserted in
   `terrain_ref/test_validate.py`. (Implementing this exposed a validator bug: 6 of the 8 symmetries
   never overlapped because blocks were not anchored. Fixed; the numbers below are from the fix.)
3. Flagged-similar pairs are verified by eye: the harness prints its 5 most similar same-level pairs;
   they are rendered with `render.py` and looked at, together with the same-level pairs of the pinned
   gallery. Done for this version: no pair is flagged; the most similar pair in 5,000 seeds (level 1,
   seeds 2250 and 1920, score 0.54) was rendered and is two visibly different three-arm layouts;
   the gallery's same-level pairs score 0.26–0.34.
MEASURED (5,000 seeds, 4,000 same-level pairs): p99 0.423, max 0.539, 0 pairs ≥ 0.60.

### D-024 — An attempt with fewer than 2 dead-end rooms is re-rolled.
WHY: the independent 5,000-seed harness found seed 842 level 3 with one dead end (H12 requires ≥ 2);
the acceptance rule did not enforce it. Added next to the shortcut rule, same waiver on the last
attempt. No pinned gallery hash changed, so GEN_VERSION stays 1 (nothing had shipped). Python and
GDScript both edited; harness 5,000/5,000 on every check; parity 56/56.

### D-023 — Arms are asymmetric and wind.
WHY: equal round-robin arms made every level a regular star; straight-through growth made 2-arm
levels sticks. Each arm now draws a size share (1–4) and its own spine-vs-branch bias (25–85%), and
straight-through sockets yield to turning ones 75% of the time.

### D-025 — FINAL — Terrain shape contract: one dominant spawn platform, thin graduated paths, occasional platforms.
DECISION: the canon shape is spawn hub → branching paths → sub-areas, and it is now a hard contract
(TERRAIN_SPEC §1A, checks H16–H22). Every number:
1. SPAWN PLATFORM. Exactly one per level, and it is the largest walkable area and the widest area in
   the level. Built as plaza x,z ∈ [−6,6] at y=0 (169 tiles) + dais x,z ∈ [−2,2] at y=1 (25 tiles) +
   four 3-wide stubs at lateral −1..1, cells 7..9 (36 tiles) = 205 walkable tiles, bbox max dimension
   19. Beacon stays at (0,0,1); the 8 spawn tiles and the y conventions are unchanged; pillars at
   (±6,±6); the four sockets (±9,0) and (0,±9) sit at y=0 with wmax 2. Dominance is measured against
   PLATFORMS only — a 19-cell bridge is a path, not an area, and must not be able to fail H16.
2. WALKWAYS. Width 1 or 2 cells, never more (max walkway width = 2). The width-1 share rises with
   level: `w1_pct = 20 + 40·(min(level,30) − 1) // 29` → 20% at level 1, 60% at level 30. Five
   archetypes: `step` (4–6 treads of 1–2 rows, ±1 HU each, 4–12 rows total), `stair` (2–4 treads of
   1–2 rows, ±2 HU), `ledge` (1–2 rows, then ±2..4 HU, then 1–2 rows), `flat` (2–4 rows), `ramp`
   (1–2 flat rows, 1–2 ramp rows, 1–2 flat rows).
3. PLATFORMS. Everything that is neither the hub nor a walkway. bbox ≤ 7×7 cells and ≤ 40 tiles.
   Count per level in [3, `plat_max`] with `plat_max = min(12, 4 + level // 3)`; the generator draws
   `target = ri(plat_max − 1, plat_max)`. Eight archetypes, all inside 7×7: `pad` (square 3..7),
   `disc` (r ≤ 3), `cross` (plus-junction), `ell` (L-corner), `terrace` (two levels), `nook` (walled
   dead end), `spire` (stepped, with an overlook), `bastion` (small walled platform). Platforms carry
   the props (cover) and the enemy anchors.
4. PATH SHARE. Walkable length: a walkway contributes its number of rows along its direction, a
   platform contributes its bbox max dimension, the hub contributes nothing. Path share = walkway
   length / total length ≥ 0.70. Second, independent floor: walkway tiles ≥ 50% of all non-hub
   walkable tiles.
5. GRADUATION. A tread is a maximal run of rows at one height inside one walkway. Flat run = a run of
   rows at one height longer than 3 cells. Flat share = rows that continue a flat run / path rows
   ≤ 0.35. Ramp share = ramp rows / path rows ≤ 0.10. Elevation variance = standard deviation of tile
   heights over all non-hub walkable tiles ≥ `3 + 3·(min(level,10) − 1) // 9` HU (3 at level 1, 6 from
   level 10 on). Sub-area boundary = a 4-adjacency between a walkway tile and a non-hub platform tile;
   at least 50% of boundaries must have |Δy| ≥ 1 HU. A junction step is never 0: near the hub it is
   `1 if chance(50,100) else −1`, elsewhere `(1,−1,2,−2,1,−1,2,−2)[range(8)]`, and it is applied at
   BOTH ends of a walkway (where it meets the platform it grew from, and where it leaves one).
6. UNCHANGED and restated as unchanged: gift slots are a first-class output with stable ids; black and
   gold occupy the same positions; hazards inherit slots (tripmine curve and 20% cap untouched); the
   beacon anchor; purity (output = f(seed, level, players, extra_mines)); round-trip reachability of
   every gift with the base kit; zero soft-lock tiles; the similarity metric (4-cell blocks, anchored
   to the spawn root, D-022 FINAL). The difficulty score keeps `D = J + 0.5·N + V + 0.25·S + 2·K`, but
   N is redefined as the % of path length that is 1 cell wide — the old "% of links with w ≤ 2" is
   meaningless when every walkway is ≤ 2 wide.
WHY: the canon shape is spawn hub → branching paths → sub-areas. Large platforms joined by wide flat
walkways and smooth ramps read as rooms, not as a route to solve: the player sees the whole level from
the hub and walks a corridor. One dominant platform plus long thin paths that step up and down makes
the level a route, gives the sub-area platforms a reason to exist (rest point, cover, a hub for a
cluster of paths), and makes height a decision instead of decoration.
MEASURED (official harness, 5,000 seeds, levels 1–30, exit 0, after the last generator edit):
H16 0/5000 · H17 0/5000 · H18 0/5000 · H19 0/5000 (path share mean 0.85, worst 0.77; walkway tile
share mean 0.67–0.76, worst 0.51) · H20 0/5000 (flat share mean 0.02–0.03, worst 0.20; ramp share
mean 0.01–0.02, worst 0.09) · H21 0/5000 (elevation sd 9.9 HU at levels 1–5 rising to 13.9 at 26–30,
worst 3.10) · H22 0/5000 (junction step share 98.9–99.6%, worst 71.4%) · H1–H15 all 0/5000.
D1 max deviation 0.40 pp (limit 1.0) · D2 300/300 at cap · D3 5,000 distinct hashes · D4 p99 0.400,
max 0.520, 0 pairs ≥ 0.60 · D5 0 identical recipes · D6 1.74% (limit 10%) · D7 bucket means 78.6 <
150.7 < 182.5 < 197.4 < 208.1 < 216.3 (strictly increasing) · D8 level-1 J mean 12.6 (limit 50), max
67.5 (limit 80) · D9 29 ms mean, 132 ms max. Platforms per level 4.1 → 11.5; walkways 21.8 → 63.6.
Gallery 16/16 on the same 16 pairs; GDScript parity 56/56 at 43 ms per level.
NUMBERS CHANGED FROM THE PROPOSAL BEFORE MEASURING (all tuning inside the contract, none of them a
contract number): `ramp` ramp rows 2..4 → 1..2 and its weight `max(2, 8 − t//4)` → `max(2, 5 − t//6)`
— ramp tiles are meant to be the exception and 2..4 rows blew the 10% ramp cap at level 1; `flat`
weight `max(4, 12 − t//3)` → `max(1, 4 − t//8)` — flat runs are the exception and the old weight also
flattened the elevation spread; `step` treads `ri(3,5)` of `ri(1,3)` rows → `ri(4,6)` of `ri(1,2)`
rows — a net climb of 3..5 HU per walkway, which lifted the low tail of the elevation-variance floor;
the junction step table `(0,1,−1,2,−2,1,−1,2)` → `(1,−1,2,−2,1,−1,2,−2)` and the gentle step
`ri(−1,1)` → `1 if chance(50,100) else −1` — a flush junction is exactly what the contract forbids;
`ray_len` 14 → 20 plus a second pass at 2× — one seed needed 13 attempts to find a shortcut.
ADDED BEYOND THE PROPOSAL: a junction step at the near end of a walkway as well as the far end
(without it half the boundaries were flush); a per-arm height drift (`drifts = [-2,2,-1,1]` shuffled,
sign forced by arm parity, `up_pct = TRAIT_UP_PCT[trait] + 22·drift` clamped 5..95) so arms separate in
height instead of all hovering at the hub's level; two generator rejections (elevation sd below the
floor, and walkway tiles below platform tiles) — both are re-rolls of the same deterministic attempt
loop, not waivers.
[CONTESTABLE]: the `flat` and `ramp` weight cuts and the `step` tread change are tuning choices inside
the contract, not contract numbers — a different mix would still satisfy H20 and H21. The D5 recipe
key was extended to include the walkway-archetype multiset after measuring (with 3–12 platforms the
platform-only key collided 11% of the time); the 0.1% threshold was not touched, but the definition
change is on record here rather than in D-022.

OWNER RULING 2026-11-16 — D-025 IS FULLY FINAL: NUMBERS AND READINGS. All three readings are
accepted as implemented:
(a) H16 dominance measures against platforms only. WHY: a 2-wide walkway cannot structurally read as
    an area, so bridges can never compete with the hub.
(b) The D5 recipe key includes the walkway-archetype multiset. WHY: the 11% collision rate proved the
    platform-only key was not measuring recipe identity, and a finer key only makes the identity
    check stricter.
    STANDING RULE (binding on every orchestrator and worker): metric definition changes stay rare,
    stay on record, and may only ever TIGHTEN a check. A definition change that loosens a check to
    escape a failure is rejected.
(c) The H22 boundary rule requires the height step at the junction itself, applied at both ends of
    every walkway. WHY: a step near the boundary is unmeasurable and illegible; the junction step is
    what makes entering a sub-area felt.
### D-026 — FINAL — No tripmine without a walkable bypass (GEN_VERSION 3); anchor kind hop retired.

DECISION (owner ruling 2026-11-16, preflight item 4, plus the TERRAIN_SPEC half of item 1; the
cylinder addition is the lead's second ruling of the same day). A tripmine may only occupy a gift slot
that has a walkable bypass, and a bypass is a WALKABLE route that also STAYS OUTSIDE the mine's 0.9 u
trigger cylinder — not merely an alternative route. The rule is written into TERRAIN_SPEC
§6.8.1–§6.8.5 and enforced by the new validator check H23:

1. CONTACT. A mine's position is its slot's tile centre `(x + 0.5, z + 0.5)`. Contact = the player's
   centre within **0.9 u horizontally** of that point, **at any height**. Jumping over a mine does not
   avoid it. The mine's **trigger cylinder** is the vertical cylinder of radius 0.9 u around that
   centre, unbounded in height.
2. THE BYPASS GRAPH `B(M)`. The movement graph of TERRAIN_SPEC §5 (validator envelope) with (a) every
   tile whose centre lies inside any mine's trigger cylinder removed — the mine tile itself **and
   every other tile in the same column**, since a tile at a different `(x, z)` has its centre at least
   1.0 u away — and (b) every edge removed whose straight horizontal segment from the source tile
   centre to the target tile centre passes within 0.9 u of any mine centre. (b) applies to **every**
   edge kind: walk, jump, drop and pad. A walk edge between two 4-adjacent tile centres is 1.0 u long
   and its closest approach to a mine centre is 1.0 u unless an endpoint is in the mine's column, so
   in practice the walk-edge test removes nothing that (a) has not already removed — it is still
   computed, never assumed. Integer-only: coordinates ×10, `0.9² = 81`, `100·d² ≤ 81·len²` for an
   interior foot, `d² ≤ 81` at an endpoint, and `dx² + dz² ≤ 81` for the tile test.
3. ELIGIBLE SLOT. With `rt` = the round-trip set of the full graph and `C(M)` = the tiles rule 2(a)
   removes, a slot tile `m` is eligible iff in `B({m})` every tile of `rt` not in `C({m})` is still
   round-trip reachable, **and** `C({m})` contains no other slot tile and not the beacon tile — a gift
   or the beacon inside the cylinder is uncollectable, so a mine may never create one.
4. JOINT RULE. For the level's final mine set `M`, in `B(M)` every real gift slot (`occ = 0`) and the
   beacon tile must still be round-trip reachable, and every round-trip tile not in `C(M)` must still
   be round-trip reachable. Two mines may not seal a 2-wide walkway between them.
5. ORDER OF OPERATIONS. One `range(400)` per slot in slot-id order (the stream never shifts, D-017); a
   slot becomes a mine only if the roll passes AND the slot is eligible AND adding it keeps the joint
   rule for the mines accepted so far. Then the cap `S // 5`, un-set from the highest slot id. Then
   `extra_mines`: one draw per extra mine, indexing the ascending list of eligible, unbanned, non-mine
   slots; a slot the joint rule rejects is banned for the rest of the phase. Then a final joint-rule
   verification (safety net; it never fires). If `extra_mines` cannot be fully placed, fewer are placed
   — the rule is never violated.
6. HOP RETIRED. The anchor kind `hop` (`AN_HOP = 3`) is never emitted. The other ids are unchanged
   (0 perch, 1 open, 2 lane, 4 nook); **3 is retired and reserved** and is not reused. The arm trait
   `hop` is untouched — it is a different thing and it feeds the RNG. The dead `AN_HOP` constant is
   removed from `voidgen.py` and `voidgen.gd`; it was never emitted, so no output changes.
7. The output format is unchanged: no new field, no `elig` flag. The canonical text and every hash
   change because GEN_VERSION is 3 and mine positions change.
8. THE 0.1 u MARGIN (modelling assumption, binding for the controller ticket). The player's centre is
   treated as travelling along the straight segment between two tile centres. Under that assumption a
   player passing a mine on the **adjacent lane of a 2-wide walkway** keeps its centre exactly **1.0 u**
   from the mine centre — a **0.1 u margin** outside the 0.9 u cylinder. That margin is the whole
   reason a 2-wide walkway still has a bypass. A 1-wide walkway has no such lane: its only bypass is a
   route that leaves the walkway, which is why the rule removes the mines that used to sit on them.

WHY: walkways are now 1–2 cells wide (D-025) and a mine kills on contact within 0.9 u at any height,
so a jump does not clear it. A mine on a 1-wide walkway is therefore a lethal wall across the only
route — not a fake gift the player chooses not to touch. Measured on GEN_VERSION 2: 1.3 mines per
level sat on 1-wide walkways at level 10 and 5.8 at level 30.

METRIC DEFINITION CHANGES (D-033: rare, on record, may only tighten).
D1 — mine curve. Before: observed `mines / slots` within ±1.0 pp of `(15 + min(L,25))/400`. After:
observed `mines / ELIGIBLE slots`, same curve, same ±1.0 pp, with the validator recomputing
eligibility by brute force. **This is a definition change that only tightens placement fairness**: the
canon rule is a per-slot chance that must never exceed 1/10, and the chance now applies only to
eligible slots, so measuring over all slots would under-report by the ineligible share (6.3% of slots
at level 5, 13.6% at levels 26–30) and would hide an over-rate on the slots that can actually hold
a mine. The eligible set is a subset of the slots, so the check is strictly tighter. Numbers on the
5,000-seed sample: under the old denominator the new generator reads max deviation **1.78 pp at level
26 (FAIL)**; under the new denominator **0.58 pp at level 26 (PASS)**. The old generator read 0.40 pp
under the old denominator.
D2 — curse cap. Before: `extra_mines = 999` gives `mines == S // 5` exactly. After: `mines ==
min(S // 5, E)` where `E` is the number of eligible slots, both recomputed independently by the
validator. `S // 5` is now unreachable when fewer than `S // 5` slots can hold a mine; the cap is
still the binding limit whenever `E ≥ S // 5`, which is every level in the sample (`E` is 86–94% of
`S`, `S // 5` is 20% of `S`). Measured 300/300.

MEASURED (official harness, 5,000 seeds, levels 1–30, exit 0, after the last generator edit):
H23 0/5000 (every mine eligible, joint rule holds on every level) · H1–H22 all 0/5000 · D1 max
deviation 0.58 pp (limit 1.0) · D2 300/300 at `min(S//5, E)` · D3 5,000 distinct hashes · D4 p99
0.394, 0 pairs ≥ 0.60 · D5 0 identical recipes · D6 1.79% (limit 10%) · D7 bucket means 80.5 < 151.6 <
183.6 < 195.5 < 209.2 < 215.6 · D8 level-1 J mean 10.4 (limit 50), max 75.0 (limit 80) · D9 55 ms
mean, 191 ms max (limit 250 / 2000). Gallery 16/16; selftest 15/15; GDScript parity 56/56 at 142 ms
per level.

MINE COUNT BAND THE PLAYER EXPERIENCES, GEN_VERSION 2 → 3 (5,000 seeds, mean/min/max mines per level
per bucket; GEN_VERSION is part of the base hash, so every level is a different level, not a patched
one — this is a distribution comparison):
  bucket    v2 mean/min/max    v3 mean/min/max    change
  1–5       0.55 / 0 / 8       0.52 / 0 / 8       −4.2%
  6–10      3.93 / 0 / 13      3.51 / 0 / 10     −10.7%
  11–15     6.10 / 0 / 14      5.36 / 0 / 14     −12.1%
  16–20     9.09 / 2 / 19      7.71 / 1 / 16     −15.2%
  21–25    12.12 / 3 / 26     10.34 / 2 / 21     −14.7%
  26–30    15.06 / 3 / 31     12.61 / 2 / 27     −16.2%
FLAG: no bucket's mean drops by more than 20% (worst −16.2% at 26–30) and no bucket's mean falls below
1 mine at levels ≥ 5 (lowest is 3.51 at 6–10), so neither flag threshold is tripped. The per-level
minimum does fall to 1 at 16–20 and 2 at 21–30, i.e. a late level can now carry only two mines; the
maximum falls from 31 to 27. As a share of all slots the replacement fraction is 1.09% (1–5) → 8.52%
(26–30), down from 1.14% → 10.17%.

[CONTESTABLE] The 0.1 u margin. The owner's rule is implemented exactly as stated: the bypass lane of
a 2-wide walkway keeps the player's centre 1.0 u from the mine centre, 0.1 u outside the 0.9 u
cylinder. 0.1 u is thin — it is 10% of the contact radius and about 11 ms of running at RUN_SPEED 9 —
and it depends on the controller keeping the player's centre on the tile-centre line. The alternative
the lead named (require the bypass lane's centre to be ≥ 1.4 u away, i.e. radius 1.4 u) was measured
on the same 5,000 seeds: it would remove a further 19–31% of the mines — 1–5 0.52 → 0.36 (−30.8%) ·
6–10 3.51 → 2.63 (−25.1%) · 11–15 5.36 → 4.15 (−22.6%) · 16–20 7.71 → 6.12 (−20.6%) · 21–25 10.34 →
8.40 (−18.8%) · 26–30 12.61 → 10.27 (−18.6%) — and it would bar mines from 2-wide walkways entirely,
leaving some levels at 16–20 with zero mines. Not adopted: the rule is the owner's, and the thin margin
is a controller constraint, not a terrain one.
[CONTESTABLE] The joint rule is tested while mines are placed (step 5) instead of only at the end. The
owner's wording was "then check the JOINT RULE; if it fails, un-set mines from the highest slot id
downward until it holds". Implemented literally that collapses the count: a random roll-passing set
can violate the rule in several independent places at once, and during GEN_VERSION 3 development a
22-mine set at level 30 fell to 6 and a 19-mine set at level 15 fell to 2, which would fail D1 by a
wide margin. Testing each addition keeps the count at the per-slot chance and the final set still
satisfies the rule by construction; the literal repair survives as the safety net in step 5 and never
fires. It is a tightening (it can only remove mines), but it is a judgment call the docs did not cover.
[CONTESTABLE] The `extra_mines` ban list. A slot the joint rule rejects is banned for the rest of the
phase rather than retried. This can only place fewer extra mines, never an invalid one, and D2 is
300/300, so it costs nothing in the sample; a retry could in principle succeed if the tile that the
rejection cut off later became a mine itself.
[CONTESTABLE] The generator's eligibility test is exact but not the brute force: it caches one BFS
pair per slot and finds crossing edges through a cell index (segments sampled at 2× resolution), while
the validator recomputes everything by brute force over a 19×19 neighbourhood. The two agree on every
level of the 5,000-seed sample (H23 0/5000), and the validator is the judge.

---

## B2. Game design (Stage 2)

### D-040 — ENEMIES.md behavior sentences are the spec; nullscape.wiki numbers only fill gaps.
WHY: ENEMIES.md is FIXED and owner-written. Research (research/NULLSCAPE_PATTERNS.md §5) shows its
behavior lines follow the ofzenandcomputing guide, which disagrees with the wiki for Husk, Operator,
Cadence and Voidbreaker. The owner's file wins. Wiki numbers are used wherever they fit the owner's
sentence (speeds, telegraph lengths, cycle times), converted at 1 stud = 0.5625 u. Everything else is
set in DESIGN.md §5. If the owner later wants wiki-accurate behavior for one enemy, it is a one-folder
change (`content/enemies/<id>/`).

### D-041 — Curses/upgrades: Nullscape's SYSTEM shape, none of its names/effects/numbers.
WHY: owner constraint. Kept as patterns: min-level gating, enemy-linked curses, pool removal, stacking,
3 pedestals, mandatory curse pick. Ours: bounties on curses, a tithe to refuse, chain multiplier,
overtime tiers, per-level pools + affordability filter. Names were checked against the wiki lists in
the research file; canon names set by the owner (Paycheck, More, Yearn for Speed, Defuse Kit,
Subspacial Barrier, Radar Module) are kept on purpose.

### D-042 — FINAL — Health: 100 HP, enemy contact hits remain lethal.
DECISION: every player has a 100 HP pool. Every enemy contact hit that DESIGN.md §5 marks LETHAL
stays lethal: it kills regardless of remaining HP unless a barrier charge absorbs it.
WHY: enemy behaviors are deliberate 1:1 Nullscape copies, so contact stays lethal; the tripmine
counter-play (Defuse Kit survives first contact, Subspacial Barrier blocks blasts) requires a damage
pool, so 100 HP is the substrate those upgrades live on.
RULES:
- Full heal on entering the beacon. HP is therefore the second axis of the enter-early-safe vs
  linger-for-gold decision: lingering risks HP that leaving would refill.
- Death attribution is by LAST DAMAGE SOURCE. Each killer keeps its own death code. A void fall is
  itself a damage source (`D-VOID`); a knockback that deals no damage is never the killer.
- Consequences applied to DESIGN.md: no heal plinth or heal font in the lobby (nothing left to heal),
  REST = discounted shop with no vote, the Field Dressing upgrade now heals inside a level.
SUPERSEDED IN PART BY D-050/D-051 (HP pool and HP costs replaced by void charges; safe-tile rules still apply).

### D-043 — FINAL — Void falls: 75 HP and respawn on the last safe tile, not instant death.
DECISION: falling below the kill plane costs 75 HP; a survivor respawns on their last safe tile.
WHY: two falls per HP pool keeps the void feared without ending a 30+ level run on one slip.
RULES:
- Safe tile = solid, not glitched floor (toucher-infected), and not inside any hazard footprint at the
  moment of respawn. It is re-validated against the CURRENT world state before teleporting.
- Last-safe-tile history is a deterministic function of validated standing positions: a fixed ring of
  the last 8 round-trip-reachable tiles the player stood on for ≥ 0.5 s, kept in simulation state and
  rebuilt identically from the input stream. No extra synced state — multiplayer stays seed + inputs.
- Respawn walks the ring from newest to oldest and takes the first tile that passes re-validation;
  if none passes, the player's spawn tile on the beacon dais is used.
SUPERSEDED IN PART BY D-050/D-051 (HP pool and HP costs replaced by void charges; safe-tile rules still apply).

### D-044 — The gold phase has its own engine: chain multiplier (×1→×2, 4 s window) + overtime tiers (every 20 s).
WHY: "leave safe and poor vs. linger for gold" needs both a reason to stay that rewards skill (the
chain turns the gold phase into a speed-run of the route just learned — gold reuses the black slots)
and a rising cost of staying (overtime). The old HUD's "1.50x" next to the purse is kept as that chain.

### D-045 — Offering schedule: six-level acts (E+U, C, E, C+U, REST, C+E), pressure accelerates, power does not.
WHY: owner wants curses every 2 levels and votes NOT every intermission. Three shops per act =
"one upgrade per two levels" (retro §4c asked for exactly this sentence). REST levels are the
guaranteed breathing room. Enemy votes go 3→3→4→5→6 per act. One tunable file:
`data/offering_schedule.json`.

### D-046 — Level 1 already has one enemy (pre-run vote from the starter pool).
WHY: an empty level 1 is a tutorial nobody asked for; one slow enemy makes the loop legible at once.
Starter pool = kiwi cat, coil, thicc ben, seal (the four with the clearest tells).

### D-047 — Simulation uses its own kinematic collision against the tile grid, not Godot physics.
WHY: determinism (multiplayer-ready, replay test), and headless bots can run the sim far faster than
real time. The tile grid makes AABB-vs-slab collision trivial.

### D-048 — Biomes are view-layer only (palette + fog).
WHY: keeps the terrain hash a function of (seed, level, players, extra_mines) and lets biomes be
pure drop-ins.

### D-049 — Godot project lives in `game/`; the Python oracle in `terrain_ref/`; engine binary in `tools/godot/` (4.7.2-stable, gitignored).
WHY: keeps Godot's importer away from reference renders and research files.

### D-050 — FINAL — Void charges replace the health pool: 2 charges, a fall costs 1, the beacon restores 1, cap 2.
DECISION: the player holds **2 void charges** and there is no health pool. A void fall spends 1 charge
and respawns the player on the last safe tile (the safe-tile definition, the 8-tile history ring and
the re-validation rule of D-043 are unchanged). A fall at 0 charges is a **real death** with the void
death code `D-VOID`. Entering the beacon restores **exactly 1** charge, capped at 2. Hungry Void sets
the cap to 1. The HUD shows one pip per holdable charge (2, or 1 under Hungry Void), filled = held.
WHY:
- The owner's spec. Two charges buy two falls, the same forgiveness the pool it replaces (D-042) gave,
  so the void stays feared without ending a 30-level run on one slip.
- A charge is a discrete, readable resource: a pip can show it, a curse can cap it, an upgrade can make
  one fall free. A pool only made sense while enemies dealt numbers, and they no longer do (D-051) — a
  pool with no source of loss is a bar that never moves.
- "Restores 1, capped at 2" keeps the beacon as the second axis of the leave-or-linger decision without
  making a refill free: leaving at 2 charges wastes the restore, leaving at 0 is the safe play, and
  lingering is what spends them.
- The 1.0 s respawn invulnerability is kept from D-043 and now suppresses kills (contact, tripmines,
  the nuke) instead of numbers, because a respawn next to an enemy would otherwise be an instant
  second death.

### D-051 — FINAL — Lethality: every enemy contact kills, every projectile kills, and the counter-play is avoidance.
DECISION: there are no numbers to subtract anywhere. Every enemy **body contact kills**; every
projectile, ring, beam, blast and void zone **kills on hit**. Tripmines and the nuke kill with no
numbers. The three non-killing enemy effects are thicc ben's touch (blur 3.0 s + 18 u/s upward eject,
never kills), coil's landing shockwave (8 u/s push + 2.0 s ability lock) and the toucher's glitched
floor (−20% run speed + class abilities disabled while standing on it; toucher body contact kills).
thicc ben's "Overtuned" lethal state is **removed** and The Long Toll is reworked (D-052).
Counter-play:
- **Defuse Kit**: stacking, each stack +20% chance that a tripmine defuses instead of killing, cap 60%
  (3 stacks). The roll is `mix(mix(run_seed, level), slot_id) mod 100 < 20 × stacks`, where `mix` is
  the terrain generator's mix function (TERRAIN_SPEC §3). It is a pure function of synced state, so a
  mine's fate is fixed for the level and identical on every client — no client RNG, multiplayer stays
  seed + inputs. A defused mine is consumed (disappears, no blast).
- **Subspacial Barrier**: 1 shield, absorbs exactly one tripmine, consumed. Max stacks 1. It does not
  recharge on a timer: it is restored on beacon entry, i.e. once per level. Tripmines only — nothing
  blocks the nuke.
- **Resolution order on mine contact: defuse roll first, then the shield, then death.** WHY: the
  defuse roll costs nothing and is fixed for the level, so resolving it first means the shield is only
  spent on a mine the player would otherwise die to. The two upgrades then add up instead of competing,
  and a 60%-defuse player never watches a shield vanish on a mine that was already a dud.
- **Glitched floor**: no kill, no numbers. −20% run speed and class abilities disabled while standing
  on it. It is an ENEMY effect, not a curse, so it does not count toward the §7 curse run-speed budget
  (the terrain proof only needs the base kit's jump envelope, which the floor never touches).
WHY:
- The owner's ruling. With no pool, a "40 damage" ring is either a kill or a lie; one rule for every
  enemy is what makes the game readable at 22 enemies.
- thicc ben stays the exception because the launch is both a tool (a free super-jump) and a threat (it
  throws you at the void). Making it lethal deletes the tool; making it harmless deletes the threat.
  Blur + eject keeps both, and the blur is a real cost while 22 enemies hunt you.
- A chance-based defuse is only fair if it is deterministic: a client-side roll would desync
  multiplayer and would let a player re-roll a mine by reconnecting. Hashing (seed, level, slot) makes
  the outcome a property of the level, and the stack count is synced, so buying a stack re-rolls the
  level's mines identically on every client.
- The shield is deliberately narrow (tripmines only, one use, once per level) because it is the only
  thing in the game that absorbs anything; a general blast shield would quietly reintroduce a pool.

### D-052 — FINAL — Knock-on changes: REST, Field Dressing, Hungry Void, and every row reworked for the charge system.
DECISION: every row that referenced a pool, a number or a "hit" is reworked or replaced. Counts are
unchanged: 46 curses, 36 upgrades.
- REST = discounted shop (−20%), no vote, **no curse**. Nothing to restore but a charge, and the
  beacon already restores it; the bay is breathing room, not a refill.
- Field Dressing (T1, 45, 2 stacks) = once per level per stack, a void fall costs no charge.
- Hungry Void (H, 1 stack) = charge cap becomes 1.
- Upgrades, old → new:
  - `thick_skin` Thick Skin (+20 max pool per stack) → `brace` **Brace**: coil's shockwave push and
    ben's eject −30% per stack (push 8 → 5.6 → 3.9 → 2.7 u/s; eject 18 → 12.6 → 9.0 → 6.3 u/s). The
    launch super-jump shrinks with it — that is the price.
  - `sure_foot` Sure Foot (void-fall cost −12 per stack) → **Sure Foot**: respawn delay −0.4 s per
    stack (0.8 → 0.4 → 0.0 s) and respawn invulnerability +1.0 s per stack (1.0 → 2.0 → 3.0 s).
  - `regrowth` Regrowth (+1 pool per 3 s) → `cold_blood` **Cold Blood**: overtime tiers rise every
    30 s instead of 20 s (Long Night: 21 s instead of 14 s).
  - `insulation` Insulation (tile and void-zone numbers −50%/−30%) → **Insulation**: glitched floor
    slows 10% instead of 20% and no longer disables class abilities.
  - `stand_fast` Stand Fast (first hit does not reset the chain) → **Stand Fast**: the first
    chain-breaking event each level (void fall, defused or shielded tripmine, ben's eject) does not
    reset the chain.
  - `defuse_kit` Defuse Kit (survive first contact, 90 s cooldown) → **Defuse Kit**: +20% defuse
    chance per stack, cap 60%, deterministic roll (D-051).
  - `subspacial_barrier` Subspacial Barrier (45 s recharge, absorbs any blast) → **Subspacial
    Barrier**: 1 shield per level, restored on beacon entry, absorbs exactly one tripmine, max 1 stack.
- Curses, old → new:
  - `glass_jaw` Glass Jaw (max pool −20 per stack) → `brittle` **Brittle**: a void fall's respawn delay
    is 1.6 s instead of 0.8 s and the respawn invulnerability is 0.5 s instead of 1.0 s (2 stacks:
    2.4 s / 0.0 s).
  - `hungry_void` Hungry Void (falls cost 90 instead of 75) → charge cap 1.
  - `leaky_purse` Leaky Purse (taking a hit drops gold) → a void fall drops 5% of this level's earned
    gold (max 20 g per fall).
  - `long_toll` The Long Toll (Overtuned at 2 rings) → every ben teleport tolls twice: a second ben
    arrives at the same locked point 1.5 s after the first.
  - `wet_floor` Wet Floor and `spreading_rot` Spreading Rot: wording only — "infected tile" becomes
    "glitched tile"; the numbers are unchanged.
  - `egoist`, `direct_shot`, `second_strike`: counter-play wording only, now that one hit kills.
WHY:
- The owner's spec, plus the rule that every row must still have a concrete rule and (for curses) a
  counter-play. A row that says "−20 max pool" in a game with no pool is a row an implementer has to
  invent, and inventing is how a spec rots.
- The replacements are chosen so each one touches something that still exists: void charges (Field
  Dressing, Hungry Void, Brittle, Sure Foot), the chain (Stand Fast, Leaky Purse), overtime (Cold
  Blood), the beacon (Subspacial Barrier), a specific enemy (Brace → coil and ben, Insulation → the
  toucher, The Long Toll → ben) or the tripmine ladder (Defuse Kit).
- Names stay original. Thick Skin and Glass Jaw are dropped because the names themselves promise a
  pool; Field Dressing, Sure Foot, Insulation, Stand Fast, Hungry Void and Leaky Purse keep their names
  because the name still describes the new rule.
- Cold Blood replaces Regrowth rather than inventing a third recovery upgrade: recovery is the beacon's
  job now, and the gold phase had no counter-upgrade at all while Long Night and Curfew both shorten it.
- **Retired vocabulary** (T-099 greps for it, case-insensitive, in `DESIGN.md`, `FLEET_PACK.md`,
  `README.md` and `game/data/`): `\bHP\b`, `hit points`, `max_hp`, `heal`, `damage`, `LETHAL`,
  `Patch Kit`, `Thick Skin`, `Glass Jaw`. Allowed hits: lines beginning `SUPERSEDED BY`, and verbatim
  owner quotes in FLEET_PACK.md. The list lives here because a grep instruction that spells the
  patterns out would match itself.

### D-053 — FINAL — A fall at 0 charges is a real death; Last Light works only while a charge is held.
DECISION: Last Light (once per run) saves the player from a kill by an enemy, a tripmine or the nuke
ONLY while they hold at least 1 void charge: they are teleported to the beacon dais with the charges
they had and 2.0 s of invulnerability. At 0 charges nothing resurrects — not Last Light, not anything
else — and a void fall at 0 charges is always a real death (`D-VOID`).
WHY (owner ruling, 2026-11-16): the charge system only means something if 0 is final. A save that
worked at 0 would be a hidden third charge.
READING CONFIRMED FINAL (owner, 2026-11-16): the save needs a held charge and does not spend it.
Field Dressing owns absorbing a fall's charge cost; Last Light never does.
CONSUME ORDER on a tripmine hit (fixed): 1. Defuse roll, 2. Subspacial Barrier shield, 3. Last Light
as the final save, 4. death (`D-MINE`). WHY: the cheapest, repeatable protection is tried first and
the once-per-run save is spent only when nothing else is left.

### D-054 — FINAL — ENEMIES.md carries no dead vocabulary: nothing "deals damage".
DECISION (owner-ordered wording pass, 2026-11-16): four behavior sentences in ENEMIES.md were reworded.
Enemy "damage" now reads "kills instantly" (YOU?! shockwave rings, seal contact, gin ichimaru's void
zones); toucher's floor now reads "glitched floor tiles that slow the player and lock abilities", with
its body killing on contact. Nothing else in the file changed; the roster, image mapping, sounds and
HARD RULES are untouched.
WHY: ENEMIES.md is the file every enemy ticket copies its THE OWNER'S SPEC block from. With void
charges (D-050) and the lethality ruling (D-051) nothing deals damage, so the old sentences would have
re-introduced a damage pool through copy-paste. ENEMIES.md remains owner-only: this edit was ordered by
the owner and is not a licence for agents to edit the file.

### D-055 — FINAL — References to the earlier build are HISTORY, kept on purpose, never a source.
DECISION (owner ruling, 2026-11-16): mentions of the earlier build and its retrospective stay where
they are (older DECISIONS entries, TERRAIN_SPEC rationale notes, FLEET_PACK standing rules,
`research/VOIDWRAP_RETRO.md`). They are not purged. They are marked as history: the retrospective file
carries a banner, and FLEET_PACK §2 says so.
RULE FOR EVERY ORCHESTRATOR AND WORKER: the earlier build is evidence about what went wrong, nothing
more. Do not port its code, data, patterns, thresholds, file layout or ticket numbers; do not justify
a NEW decision by pointing at it. New decisions are justified by the owner's brief, ENEMIES.md, the
current specs and measurements. If a current document and the retrospective disagree, the current
document wins.
WHY: a successor reading "the levelgen algorithm is the most valuable code in the repo" in the
retrospective must not conclude it should be ported — this remake deliberately replaced it (D-010).

### D-056 — FINAL — Enemy spawn anchors: a fixed fallback order, and `hop` is retired.
DECISION (owner ruling, 2026-11-16): DESIGN.md §5's common spawn rule is a three-step fallback,
evaluated on the simulation state at the spawn tick:
(a) the anchor of the enemy's preferred kind; (b) if the level has no anchor of that kind, a `lane`
anchor; (c) if no anchor qualifies, any round-trip-reachable tile at least 25 u from the spawn point.
The existing constraints stay: 6.0 s after level start, never within 25 u of the player, and among the
candidates that pass, the farthest-but-within 60 u of the player. The within-60 u preference is dropped
at step (c). Tie-break: farthest from the player, then the lowest anchor index (a, b) or the lowest
tile index (c). The choice reads only simulation state, so it is deterministic.
Preferred kinds (DESIGN.md §5 table): kiwi cat `nook`; coil `lane`; thicc ben none (its initial
position is fallback (c)); Isagi `perch`; nuke none (a launcher, no body); YOU?! `open`; gift Larper
none (it lives in gift slots); toucher `lane`; seal `lane`; address me none (it appears in front of the
player); Claude `open`; gin ichimaru `perch` (his strike appearances keep his own 15–25 u rule).
`hop` is retired: the anchor kinds are `perch`, `open`, `lane`, `nook`. FLEET_PACK T-027's spawn
summary now points at the fallback order instead of "anchor".
WHY: measured on 100 seeds per level, `hop` is absent in 100% of levels (the shape contract removed the
archetype that emitted it), `nook` is absent in 74% of level-1 layouts, `perch` in 72% and `open` in
51%; only `lane` always exists. Without a fallback most enemies have no legal spawn tile, and a ticket
that implements "the anchor of their preferred kind" would either crash or invent a rule. The order
keeps the flavour (a cat in a dead end, a seal on a straight run) while guaranteeing a tile, and (c)
is the only step that can always succeed because every level has round-trip tiles.

### D-057 — FINAL — Last Light is owned by T-012, and kill tests run with Last Light spent.
DECISION (owner ruling, 2026-11-16): T-012 owns Last Light and `tests/test_last_light.gd`. The save:
once per run, only while the player holds at least 1 void charge, a kill by an enemy, a tripmine or the
nuke teleports the player to the beacon dais with the charges held and 2.0 s of invulnerability; it
does not spend a charge; it never triggers at 0 charges; it never triggers on a void fall. Test cases:
saves once at 2 charges and once at 1 charge; does nothing at 0 charges (the death is real); a void
fall at 0 charges is `D-VOID` even with Last Light unspent; the second lethal hit after it is spent
kills; HUD icon lit while armed, dim at 0 charges, grey once spent.
T-027's `test_kill_api.gd`, A7, T-021's mine tests and the Wave 3 enemy ticket block state that kill
tests run with Last Light already spent.
WHY: DESIGN.md §3.1 gives Last Light a save that fires on any enemy, tripmine or nuke kill while a
charge is held, but no ticket owned it and every kill assertion in the pack ("a body contact kills")
would pass or fail depending on an unstated Last Light state — a test that cannot fail is not a test.
One owner (T-012, the ticket that already owns charges, respawn and the safe tile) keeps the save and
the charge rule in one place.

### D-058 — FINAL — The tripmine ladder is four steps everywhere; contact is within 0.9 u of the box at any height.
DECISION (owner ruling, 2026-11-16): DESIGN.md §3.3, FLEET_PACK A6 and T-053 carry the same four
numbered steps verbatim — 1. defuse roll, 2. Subspacial Barrier shield, 3. Last Light, 4. otherwise
killed `D-MINE` — plus the sentence "The order is fixed: defuse roll, then Subspacial Barrier shield,
then Last Light (D-053)." Contact = the player's centre within 0.9 u (horizontal distance) of the
tripmine box at ANY height; jumping over a mine does NOT avoid contact. A tripmine is a wall on its
tile: the walkable bypass is the only way past it, and a bypass is a walkable route that stays outside
the mine's 0.9 u trigger cylinder. T-021 and A6 mirror the contact sentence. DESIGN.md §3.3 also
states that the generator guarantees no mine sits on a tile without a walkable bypass (TERRAIN_SPEC
§6.8, validator check; the terrain decision for the tripmine bypass rule is D-026), so a mine can
always be walked around; the generator rule and its validator check are the terrain worker's.
WHY: T-053 and A6 still described a three-step ladder (defuse, shield, death) while DESIGN.md §3.3 and
T-021 had four, so a worker reading A6 would have built a game where Last Light never saves a mine. The
contact volume said "within 0.9 u" with no axis and no height, so "jump over it" was a legal reading —
and a 0.9 u trigger on a 1 u wide walkway is a lethal wall unless the generator keeps a bypass.

### D-059 — FINAL — The safe tile is also at least 6 u from every enemy body and projectile.
DECISION (owner ruling, 2026-11-16): DESIGN.md §3.1's safe-tile definition and T-012's
`test_charges.gd` add "at least 6 u from every enemy body and projectile". Test cases: an enemy parked
on the newest ring tile → respawn uses the next valid ring entry; all 8 invalid → the dais spawn tile.
WHY: the safe tile listed hazard footprints only. Enemy bodies are not footprints, and kiwi cat,
toucher and YOU?! float straight at the player and converge on the spot they fell from, so a respawn on
the newest ring tile could be a respawn into a body — an instant second death that the 1.0 s
invulnerability only postpones. 6 u is roughly one second of travel for the fastest floating body
(6.75 u/s) and inside the 8 u Crowded Dais radius, so it is a distance the player can see and the sim
can check.

### D-060 — FINAL — Acceptance criterion A3 is pinned.
DECISION (owner ruling, 2026-11-16): A3 = kiwi cat present, the bot runs with `--dodge` on, Last Light
available, 2 charges held, and the bot completes level 1 (all real black gifts → beacon) in at least 95
of 100 seeds, median ≤ 120 s sim time. Measured by `bot_run.gd --seeds 0:100 --dodge --enemy
kiwi_cat`. T-026's bot CLI gains `--seeds A:B`, `--dodge` and `--enemy <id>`, and every bot run starts
with Last Light unspent and 2 charges held.
WHY: A3 said "with the starter enemy present" while the starter pool holds four enemies, three of which
kill on contact, and T-026 made `--dodge` optional — so the same criterion could be measured four ways
with four different results. Pinning the enemy, the dodge flag, Last Light and the charges makes the
number mean one thing. The threshold is unchanged.

### D-061 — FINAL — Isagi's balls fly in 3D from 1.0 u above his tile to the player's centre at release; a jump or a 2 HU step clears them; he prefers `perch`.
DECISION (owner ruling, 2026-11-16): DESIGN.md §5.4: each ball leaves 1.0 u above Isagi's tile and
flies straight in 3D to the player's centre at release (centre = feet + 0.9 u); the line is fixed at
release and never homes; hit test = the ball's centre within 0.5 u of the player's centre. A jump
(centre rises up to 2.25 u) or a 2 HU step (1.0 u) clears the line; a 1 HU step (0.5 u) does not. He
prefers `perch` anchors and falls back per the spawn rule. Every existing number is unchanged: wind-up
1.2 s, 3 balls 0.15 s apart, 22 u/s, radius 0.5 u, life 3.0 s, cooldown 2.5 s, relocation every 12 s.
The "props everywhere" claim is gone.
WHY: the paragraph said "straight at the player's position at release" with no height, so an
implementer could fire at the feet, at the centre or at the camera, and nothing said whether a jump
dodges. The cover premise was also false: measured 3.3 props per level at level 1, 6.9 at level 12,
minimum 0, all on platforms — so height and corners, not props, are the reliable cover, and `perch` is
where he belongs.

### D-062 — Cold Start's Athletic penalty is coyote time −0.05 s [CONTESTABLE]
DECISION (owner ruling, 2026-11-16): DESIGN.md §7.2 `cold_start` reads "class ability starts each level
on cooldown and recharges 25% slower (Athletic: coyote time −0.05 s instead)". Base coyote time is
0.10 s (DESIGN.md §4), so 0.05 s remains and the value never goes negative. The jump-envelope proof in
TERRAIN_SPEC §5 does not rely on coyote time: it is derived from gravity 32, jump velocity 12, run
speed 9, half-width 0.4, player height 1.8 and auto step-up 0.5, and coyote time appears nowhere in
it. The penalty touches no collect verb: pickup radius, gift yield and the magnet are unchanged.
Run-speed sum check: the only curse that reduces run speed is Weighed Down (−10%, gold phase); Cold
Start no longer touches run speed, so the total is 10% for every class, inside the §7 safety rule's
≤ 10%. T-050's Done-when needs no change.
WHY: T-050 asserts "total run-speed reduction ≤ 10%" and Cold Start's −5% stacked with Weighed Down's
−10% to −15% for Athletic. Athletic has no active ability, so the ability-cooldown penalty has nothing
to bite; the substitute must be a real cost that is not run speed, jump velocity or gravity. Coyote
time is the forgiveness window at a ledge, which is exactly what a cold start should cost a class whose
identity is speed and air-jump height: it still moves at full pace, it just gets less grace at the
edge. It is a data value in `data/player.json` (coyote 0.10) and the §12 stat list is open-ended
("…"), so it needs no new mechanic. [CONTESTABLE] because the owner may still flip it; the lead's
ruling is coyote time −0.05 s.

### D-063 — FINAL — Void charges carry over between levels; there is no reset at a level boundary.
DECISION (owner ruling, 2026-11-16): DESIGN.md §3.1 states: a new run starts with 2 void charges;
charges carry over between levels; there is no reset at a level boundary; the beacon restores exactly 1
on entry, capped at 2 (cap 1 under Hungry Void); nothing else restores a charge. The three documents
never state a charge grant at a level boundary or a reset there — the ruling is described without that
phrasing anywhere in DESIGN.md, DECISIONS.md or FLEET_PACK.md.
WHY: the owner's ruling confirms D-050. The charge is the second axis of the leave-or-linger decision —
a refill at every level boundary would make leaving at 0 charges free and delete the decision. The
phrasing was the source of the preflight review's item 23, so it is banned from the three documents
rather than corrected once.

### D-064 — FINAL — The owner approved all 14 enemy-system rules as proposed, plus the Isagi and nuke rulings.
DECISION (owner ruling, 2026-11-16, given to the orchestrator before the overnight run): the 14
enemy-system rules of `research/fable-enemies.md` are approved **as proposed in that document** and are
FINAL, not [CONTESTABLE]. They are the 15 numbered items of T-070 (`research/fable-tickets.md` §5),
minus the two the owner ruled separately:
1. Floater altitude — feet ease toward the target's feet at 2.0 u/s (F1).
2. Body-size table for all 12 enemies (F2).
3. Coil — landing target is the player's last grounded tile; shove 8 u/s decaying linearly to 0 over 0.5 s.
4. Copies of one enemy — cycle offset k/n; chaser copies spawn ≥ 30 u apart (F7).
5. Scheduling — address me appears only when no enemy body is within 12 u, no ring or patch is on the
   player, the player is grounded and not on glitched floor; gin does not mark during address me's
   countdown (F8).
6. Pursuit ceilings — kiwi cat 0.80, kitten 0.70, YOU?! 0.55, toucher 0.75, seal 0.60, Claude 0.55 of
   base run speed; bursts ≤ 1.00 for ≤ 3.0 s; overflow converted to tempo with a 60% floor (§5.1).
7. Seal — the dash is a fixed 3D line; telegraph only from 4–12 u; cleared by a jump on the bark, a
   3 HU step, or a 0.7 u sidestep; Pup Pack text "jump each bark" (§5.2).
8. Ability lock per class, including the Athletic stride lock (§5.3).
9. Claude's wind shot — 7.0 u/s, 90°/s, life 4.0 s, dies on any tile slab or step riser.
10. gin stands on platform tiles only (farthest hub tile as fallback).
11. Last Light's arrival pushes enemy bodies within 8 u of the dais out to 8 u (no kill).
12. First-shown levels, vote caps, chaser ceiling 6, and the NEW / REPEAT / FREE altar rule (§1, §3).
13. Wet Floor keeps "slippery" and loses its extra slow.
14. The counter-play map of `research/fable-enemies.md` §4 is the answerability standard: every rule
    must leave every enemy answerable in it, and DESIGN.md §5 and §7.1 are rewritten to those answers.

Two rules the owner ruled in the same breath, both FINAL and both implemented in full:
- **Isagi** — D-056 stays FINAL (he may still fall back to a `lane` anchor). He is made answerable
  there even under Egoist by **both** halves, not one: (a) volley gap — a burst fires in volleys of at
  most 3 balls 0.15 s apart, and consecutive volleys of one burst are separated by 0.75 s (45 ticks =
  one full jump), so each volley is cleared by its own jump; (b) dwell limit — on a `lane` anchor he
  stays at most 4.0 s (240 ticks) before relocating. The owner wrote "volley gap or ~4 s dwell limit";
  the ruling recorded here is that **both** are implemented, because (a) answers Egoist and (b) removes
  the parked body from the path. This supersedes the "does not wind up along a flat in-line walkway"
  proposal of `research/fable-enemies.md` §4 item 3.
- **Nuke** — one salvo (tracking, including restarts after a broken lock, plus descent) lasts at most
  6.0 s (360 ticks) from its first tracking tick; if it has not detonated by then it expires harmlessly
  and the 5.0 s pause starts. The line-of-sight ray and the descending missile are blocked by any prop,
  any `spire` pad, any `bastion` tower and any tile slab; a missile that meets one detonates there.
  Counter-play text names both answers: leave the sphere, or get under or behind one of those.

WHY: the owner read `research/fable-enemies.md` and approved it as written, which closes the gap the
ticket-completeness pass flagged — T-070 said "as ruled by the owner" while DECISIONS.md held no ruling
on the 14 proposals, so every item but Isagi and the nuke would have been logged [CONTESTABLE] and left
open. Marking them FINAL is what lets T-070 apply them instead of parking them, and it is what makes the
counter-play map of §4 a standard rather than a suggestion. The Isagi and nuke rulings are recorded with
their arithmetic because both were written by the owner as a choice ("or", "≤ 6 s") and the run needs one
reading: both Isagi halves are implemented, and the nuke's limit is measured from the first tracking tick
of a salvo rather than from launch, so a lock broken and re-acquired cannot extend a salvo past 6 s.
Nothing here changes ENEMIES.md, the 12-enemy roster, D-025 or any earlier FINAL decision.

### D-065 — FINAL — Floater altitude, body sizes, and copy offsets (SR-1..SR-3).
DECISION (2026-11-16, T-070): a floating enemy's feet height eases toward its target's feet height at a
maximum of **2.0 u/s** (a 4 HU climb = 2.0 u buys 1.0 s of vertical separation) and its horizontal speed
is the speed stated in its section — the vertical easing is never multiplied by any speed multiplier.
Body height / hit-cylinder diameter per enemy: kiwi cat 1.0 / 0.9; coil 1.0 squashed / 2.0 extended at
0.9; thicc ben 4.0 / 1.2, not hurdle-able — touching him is the way past (§5.3); Isagi 1.8 / 0.7,
not hurdle-able; YOU?! 1.8 / 0.7, outwalked, not jumped; toucher 1.4 / 0.8; seal 0.6 / 0.6; address me
2.5 with no body contact; Claude 2.0 / 1.6, keeps its distance; gin ichimaru 1.8 / 0.7. Copy k of n of
the same enemy starts its cycle offset by **k/n of the cycle length** and is otherwise identical; copies
of one **chaser** spawn at least **30 u apart**, each taking the next candidate in the D-056 fallback
order, so they arrive from different sides instead of as one blob.
WHY: 2.0 u/s keeps a floater's climb slower than a 0.375 s jump, so height always answers it; the fixed
body sizes decide hurdle-ability per enemy (1.0 u clears under a 2.25 u apex, 4.0 u never does), and the
k/n offset with the 30 u chaser separation turns copies into a rhythm the player can learn rather than
a simultaneous wave.

### D-066 — FINAL — Coil's landing shockwave is survivable by geometry.
DECISION (2026-11-16, T-070): coil lands on the player's last grounded tile (D-064 item 3) and its
landing shockwave has radius 6 u, pushing players outward at **8 u/s decaying linearly to 0 over
0.5 s** — 2.0 u of travel, enough to clear a 1-wide path from its centre — survivable on a platform
≥ 5 wide, and it **does not kill**; the shove off a ledge is the only danger.
WHY: a linear decay with exactly 2.0 u of total travel always leaves room to walk clear of a shove on
any platform ≥ 5 wide, so coil's pressure is forced movement and ledge discipline, never direct slam
damage — the knockback is what kills, nothing else.

### D-067 — FINAL — The scheduling arbiter (SR-4).
DECISION (2026-11-16, T-070): address me **appears** only when, on that tick, (a) no enemy body is
within 12 u of the player, (b) no ring or patch is on the player — a ring or patch being a nuke ground
ring, a gin marked patch, or a coil landing ring — and (c) the player is grounded and not standing on
glitched floor. If any condition fails, address me waits and appears on the first tick all three hold.
While its countdown runs, **gin does not mark a patch** (his cooldown keeps ticking; the strike is
deferred until the countdown ends).
WHY: the only enemy that demands stillness must never overlap with an enemy that demands movement; the
three gates and the gin deferral guarantee a stop is always answerable — no chaser in reach, no ring on
the player, feet on solid floor, and no patch cutting the route while you hold still.

### D-068 — FINAL — Pursuit ceilings for every floating body (SR-5).
DECISION (2026-11-16, T-070): every floating body's horizontal speed after ALL multipliers (overtime,
curses, Hunger) is clamped to a fraction of **base** run speed (9 u/s — base, not the player's current
speed, so speed upgrades always gain ground and no curse can invert the race): kiwi cat 0.80 → 7.2 u/s;
kitten (The Litter) 0.70 → 6.3; YOU?! 0.55 → 4.95; toucher 0.75 → 6.75; seal 0.60 → 5.4; Claude 0.55 →
4.95. **Bursts are exempt but bounded**: a telegraphed sprint may reach 1.00 × base run speed for at
most 3.0 s, then back under its ceiling. **Overflow becomes tempo**: whatever part of a speed
multiplier the ceiling removes is applied to that enemy's cycle instead — idle/cooldown time divided by
the unused factor, floored at 60% of the base cycle; for the toucher (no cooldown) it shortens the
glitch interval (2.0 s → at most 1.2 s).
WHY: ceilings keyed to base run speed mean every speed upgrade still gains ground and no curse or
overtime stack can make a body unbeatable; bounded bursts and the 60% tempo floor keep accelerated
enemies pressing through faster cycles instead of simply getting faster mid-chase.

### D-069 — FINAL — The seal's dash is a fixed 3D line, started only from 4–12 u.
DECISION (2026-11-16, T-070): at **telegraph start** the dash line is fixed as the straight 3D segment
from the seal's body centre through the player's centre (0.9 u above the player's feet), extended to
20 u; it **does not re-aim** during the 0.75 s telegraph or the 1.0 s dash, and the dashed telegraph is
drawn along that 3D line, not flattened onto the ground. Telegraph only from **4–12 u** — closer than
4 u it keeps flapping (a chaser problem with a chaser answer: hurdle it, SR-2). Contact at any time =
**kill**. Pup Pack text is "**jump each bark**"; its second seal runs its own fixed line 0.5 s later
(seals capped at 3 with stagger, SR-3), so the barks never coincide.
WHY: a fixed line makes repositioning after telegraph start genuinely safe — the jump clears the bark
and a sidestep clears a re-aim that never comes; the 4–12 u start window keeps the line readable
(no point-blank snapping) while the hurdle remains the answer when it overcloses.

### D-070 — FINAL — Ability lock answers per class (SR-6).
DECISION (2026-11-16, T-070): while a lock holds (glitched floor, coil's shockwave lock, any future
lock): **Dasher** cannot dash and its cooldown does not tick; **Glider** cannot start a glide and an
active glide ends; **Athletic** gets the **stride lock** — its +15% run speed is suspended and its
×1.5 speed-upgrade / ×1.3 air-jump-height multipliers become ×1.0 for the lock's duration (purchased
upgrades themselves still work at normal strength; Athletic drops 10.35 → 9.0 u/s when locked, and to
7.2 u/s on glitched floor — identical to the other two classes on the floor).
WHY: a lock must degrade every class the same way or it becomes class-gated death; suspending
multipliers (not deleting upgrades) keeps purchases worth their gold while the floor locks, and the
10.35 → 9.0 u/s drop means Athletic is exactly as mobile as Dasher and Glider when any lock holds.

### D-071 — FINAL — Claude's wind shot dies on terrain.
DECISION (2026-11-16, T-070): on beats 1, 2 and 3 of the wind bar each homing shot flies at
**7.0 u/s, turns 90°/s, has life 4.0 s**, and the shot **dies on touching ANY tile slab or step riser
(≥ 1 HU), and on any prop**. Counter-play: run in a straight line (7.0 u/s vs 9.0 — you gain 2 u/s) or
drop one tread because the shot dies on any slab or riser.
WHY: 7.0 u/s under a 9.0 u/s base means a straight run always gains 2 u/s on it, and terrain — any slab
or riser ≥ 1 HU, any prop — deletes the shot outright, so standing ground behind cover or dropping one
tread is as valid an answer as kiting it in the open.

### D-072 — FINAL — gin ichimaru stands on platform tiles only.
DECISION (2026-11-16, T-070): gin stands 15–25 u away on **platform tiles only**; his fade-in tile is
always a platform tile (never a walkway tile — his body must never block or cut the only route home);
if no platform tile qualifies under his 15–25 u rule, he uses the **farthest tile of the spawn hub**.
His body is never on the path, so only the patch threatens you. He never marks the beacon dais,
and never marks while address me's countdown runs (SR-4); gifts over a void zone stay but cannot be
reached until it closes.
WHY: a 3-cell patch walked out in 0.33 s is the answerable threat; a body parked on the only walkway
home would not be. Forcing platform tiles and the hub-farthest-tile fallback guarantees the route home
is never severed by a fade-in, so the patch is the only thing you must answer.

### D-073 — FINAL — Last Light's arrival pushes enemies radially out to exactly 8 u, no kill.
DECISION (2026-11-16, T-070): a killing blow while the player holds at least 1 void charge teleports
the player to the beacon dais, and that arrival **pushes every enemy body within 8 u of the dais
radially out to exactly 8 u from the dais centre** — a one-time reposition, **no kill, no behavior
change** — so the save cannot drop the player into a radial ambush around the beacon. At 0 charges
Last Light does nothing: every death at 0 charges is real, and nothing resurrects at 0.
WHY: a save that teleports the player into a pack of enemies at the dais would kill on arrival and
make the charge worthless; the radial push to exactly 8 u gives the 2.0 s of invulnerability a real
escape window with no kill and no behavior change on the displaced bodies.

### D-074 — FINAL — The NEW / REPEAT / FREE enemy offer draw and chaser ceiling.
DECISION (2026-11-16, T-070): the three E-altars of an E bay are **NEW / REPEAT / FREE (D-074)** — one
**NEW** altar (an eligible enemy type with 0 votes; lowest first-shown level first, ties by seeded
draw), one **REPEAT** altar (a type already in play, below its cap — never the type picked at the
previous vote; in an E×2 bay the second draw treats the first draw's pick as that previous vote), and
one **FREE** altar (seeded draw from everything eligible and not already shown). If a category is empty
its altar becomes FREE. **Chaser ceiling (D-074): at most 6 floating lethal bodies in play at once**
(kiwi cat, toucher, YOU?!, seal — The Litter's kittens count as half each); an altar that would exceed
it is not drawn.
WHY: every vote becomes the same legible question — a new problem, or more of one already handled —
while the six-body cap keeps a stacked arena a readable sequence of hurdles rather than a wall.

### D-075 — FINAL — Wet Floor / glitched floor slow (fixed at 20%).
DECISION (2026-11-16, T-070): **Wet Floor** keeps "slippery" (glitched tiles get friction ×0.4) and
**loses its extra slow** — **D-075 fixes the glitched floor's slow at 20%** for everyone; the slow is
an enemy effect, not a curse, and does not count toward the §7 10% curse-safety rule because the
terrain proof only needs the base kit's jump envelope (the floor slow never touches jump velocity or
gravity). A glitched player at 7.2 u/s still gains 0.45 u/s on the toucher (SR-5); Wet Floor's
counter-play stays "**jump across, don't walk**".
WHY: the glitched floor must never cost more than its 20% slow or the terrain puzzle's answer breaks
and the §7 10% budget loses its meaning; extra slowing stacked on top of the toucher's own 0.75
ceiling (6.75 u/s) could erase the 0.45 u/s margin a glitched player needs, so the slow is pinned at
20% and Wet Floor adds only slipperiness.

### D-T012-1 — [CONTESTABLE] Terminal fall speed is 40 u/s.
DECISION (T-012): the controller caps the fall speed at 40 u/s. No document states the number.
At 60 Hz that is 0.67 u per tick, under the 1 u slab thickness, so the swept collision can never
tunnel a slab; the void below the kill plane is where long falls end anyway, so a higher cap has no
gameplay effect — while a lower one makes falls floaty. Lives in `data/player.json` as
`terminal_fall`. [CONTESTABLE]: the owner may prefer another number; nothing else depends on it.
WHY: the vertical step at the tick rate must stay inside the collision geometry it is resolved
against, or kinematic sweeps (D-047) need sub-stepping everywhere for one cosmetic number.

### D-T012-2 — The envelope proof's jump script implements the x0.9 safety as a 10%-early takeoff.
DECISION (T-012): `tests/test_envelope.gd` scripts one jump per row of TERRAIN_SPEC section 5.1:
run at full speed toward the gap and press jump exactly when the player's centre crosses
`edge − 0.1 × raw reach` (raw reach = 9 × t2, `t2 = (12 + sqrt(144 − 64·dy))/32`, dy in u). Each
row clears the VALIDATOR gap and fails at gap+2, and a tile +5 HU (2.5 u) is never landed on
(apex 2.25 u, step-up 0.5 u). >= +4 HU stays unreachable as the table states.
WHY: retro section 4e — the envelope proof must bind the GENERATOR guarantee to the actual
controller, not to a formula: the jump runs through the real sim code (collision, gravity, buffer,
coyote). The 0.9 table factor decomposes exactly into "take off 10% of the reach early"; with a
fully optimal edge-takeoff jump the flat row's gap+2 (7 cells = 6.2 u needed for 6.6 u available)
would still be physically reachable and the "must fail" half of the test would prove nothing.

### D-T012-3 — [CONTESTABLE] Upgrade-strength composition, and Hungry Void clamp reading.
DECISION (T-012): (a) run speed composes ADDITIVELY on base: `run = base * (class_mult + raw
upgrade pcts)`, where the Athletic class mult is +15% (1.15), a purchased +10% speed card counts
x1.5 on Athletic (1.15 + 0.15 = 1.30 → 11.70 u/s), under an ability lock or on glitched floor the
class mult is off and purchased cards work at normal strength (D-070), and the glitched floor then
applies its fixed x0.8 (D-075). (b) A double-jump upgrade's air-jump velocity is
`jump_velocity * card_height * (1.3 on Athletic while not locked)`. (c) When Hungry Void lowers the
cap to 1 (D-052) while 2 charges are held, the held charges are clamped down to 1 so the HUD's
"one pip per holdable charge" invariant stays exact; nothing spills on restore (beacon at cap gives
back 0). The controller exposes `apply_speed_upgrade(pct)`, `apply_double_jump(card_height)`,
`apply_lock(duration)` and `set_charge_cap(cap)` for the content layer until T-013's stat hooks
exist. All three readings are [CONTESTABLE] (clone the readings if the owner rules otherwise).
WHY: the documents state each strength factor but not their composition; identical readings for
every implementer of T-013/T-050's sum checks need the arithmetic pinned; the pip invariant is the
one thing D-050 states outright and it decides (c).

### D-T012-4 — Simulation notes: integration order, dash ticks, pad ballistics, aim fields, safe-tile distances, ring membership.
DECISION (T-012):
- Gravity is applied BEFORE the move (semi-implicit Euler): the takeoff tick moves at exactly
  jump velocity 12, and the discrete trajectory lands 16·T·dt shorter than the continuous envelope
  — inside every validator margin of T-012-2's script (checked per row). The jump/cut/coyote/
  buffer constants stay exactly as DESIGN section 4 states them.
- The dash is an INTEGER tick counter (0.20 s = 12 ticks at 60 Hz), not a float timer: the span is
  exactly 6.0 u with no float residue; walls clip it and horizontal control resumes from 0.
- A launch pad computes its ballistic at launch: `t2 = (v0 + sqrt(v0^2 − 64·dy))/32` (descending
  branch, v0 = 16, g = 32) and aims the horizontal velocity at the target tile's centre; input
  control is suspended until landing (air control, glide, air jumps and dashes cannot deflect it),
  which is what makes "land on the pad's target tile" a guarantee for every jump-over.
- The per-tick input carries `aim_x`/`aim_z` (the dash fallback direction, camera-forward,
  defaulting to +z) alongside T-010's `move_x`/`move_z`/`buttons` shape; T-082 owns mapping them.
- Safe-tile distances (D-059) are 3D Euclidean from the tile's top-centre to every enemy body /
  projectile centre, >= 6.0 u; hazard footprints arrive as live state (circle / ring / box, each
  optionally y-banded) fed by the enemy runtime.
- The safe-tile ring stores tiles the player stood on for >= 0.5 s; round-trip reachability is
  guaranteed upstream (H6 forbids soft-lock tiles, and the level dict carries no rt-set), so sim
  re-validates at teleport time with the four live filters (solid, not glitched, outside hazards,
  6 u clearance) and falls back to the dais spawn tile.
- `data/player.json` is owned by T-014c and merged during the run (nested schema);
  `controller.load_constants()` maps `shared_kit` / `classes.*` / `void_charges.*` /
  `last_light.*` onto the controller's flat keys, keeps flat-key overlay support, and
  falls back in code for the numbers the file does not carry: half_width 0.4 / height
  1.8 (DESIGN section 4), accel 90 (addendum R4), terminal_fall 40 (D-T012-1),
  kill_plane_y −40 and pad_launch_vel 16 (TERRAIN_SPEC section 4).

---

### D-T082-1 [CONTESTABLE] — Third-person orbit camera: pivot-orbit rig and its numbers (T-082).
No document before T-082 states ANY camera (research/fable-tickets.md §4, T-012 row: "Out of scope
here — see T-082"; FABLE_HANDOFF confirms). Chosen reading, all [CONTESTABLE] with gameplay reason:
the camera orbits a **pivot 2.5 u above the player's feet** on a sphere of **radius 7.0 u** —
`offset = R_y(yaw) · R_x(pitch) · (0, 0, 7.0)`, look target = the pivot — so "7.0 behind / 2.5
above" is the rest geometry and "default pitch −18°" is the pitch the rest pose ships at (the
camera looks down 18°); pitch clamps −60°…+30°; **FOV 75°** (matches the T-011 shot-camera FOV so
the audit screenshots and gameplay agree); **mouse 0.12°/px** default (Godot convention: mouse
right = yaw decreases, mouse down = pitch decreases); **no camera collision** — there is nothing
but void to clip, and a collision sweep would fight the fog; the camera's height
follows the player's feet through an **exponential spring of 0.12 s** (`y += (target − y)(1 −
e^(−dt/0.12))`) so the 0.5 u auto step-up eases instead of jolting — 0.12 s ≈ 7 sim ticks is under
the 0.10 s jump-buffer window, so a step-up never delays an input reaction. Why a pivot orbit over
"a camera docked at (0, 2.5, 7.0)": one number per concept (radius ≠ height) and the look target
at chest height keeps the player readable against fill light at every pitch in the clamp.

### D-T082-2 [CONTESTABLE] — Bindings and capture semantics: data/bindings.json, Held-bit buttons, diagonal normalization, HUD/pause are app-level (T-082).
DESIGN.md §13 rule 2 fixes the PlayerInput fields but no document says which DEVICE produces them.
Chosen: bindings live in `game/data/bindings.json` — keyboard W/A/S/D move, **Space jump, Left Shift
(Godot 4 KEY_SHIFT, the only Shift the Key enum has) class ability, F interact, Tab HUD-row toggle, Esc pause**; gamepad **left
stick move (stick_up = −1 forward), A jump (button 0), X ability (button 2), Y interact (button
3)**. Buttons are HELD bits (button_press is edge-detected by the sim from state's prev_buttons):
hold Space = glide / variable-jump fuel, release = jump cut — the controller reads OVER TIME what
capture reports per tick. The **INTERACT** bit is likewise the raw hold; the **0.35 s
hold-to-confirm tally at altars is altar-view logic** (DESIGN.md §11), not capture. Tab and Esc
are NOT sim bits: they come back as app-level flags — HUD/ pause are modal overlays on the view,
and putting them in the wire format would leak view state into replays. The combined keyboard +
stick move vector is **normalized to magnitude ≤ 1** before rotation (a diagonal never exceeds
run speed), rotated by the camera yaw (yaw 0 = world forward −z), scaled by 127 and ROUNDED to
int8 (D-T010-2); exactness of "rotated by exactly the yaw difference" therefore holds exactly at
90° multiples and the 45° set, and to within int8 rounding (~0.5°) elsewhere — pinned by
test_input.gd. capture() is a pure function of device state + camera yaw (no engine `Input`
singleton inside it) so headless tests exercise the same code the app main scene will.

### D-T082-3 [CONTESTABLE] — Settings: user://settings.json, clamp-not-reject on load (T-082, the T-024 addendum made concrete).
The T-024 addendum fixes the fields and ranges (master volume 0–100 default 80, mouse sensitivity
0.02–0.30 °/px default 0.12, FOV 60–90° default 75, fullscreen off; stored in `user://settings.json`)
but not the failure behavior. Chosen: on boot the file is read and **every field is clamped into
range and defaulted when missing, corrupt or wrongly typed — settings can never fail to boot**
and the file is only written back through the explicit save path. Gameplay reason: a settings
file this small is user data from ONE older build at most; blocking a run over `fov: "wide"` is
strictly worse than clamping. `app/settings.gd` takes a path parameter so tests write to their
own file and never clobber the player's real `user://settings.json`.

### D-T082-4 [CONTESTABLE] — Camera lock: the character and the camera are locked to each other, and neither turns (owner request).
> **SUPERSEDED IN PART, 2026-11-19 (J5).** The mouse half of this decision no longer holds. The owner
> later asked for mouse-look, so `app/world.gd` now has a Ctrl-toggled mouse-capture state machine and
> `camera_rig.apply_mouse()` is driven by real `InputEventMouseMotion` while captured. The sentence
> below that says "no `InputEventMouseMotion` handler exists anywhere in `app/`, so there is no path
> from the mouse to the rig yaw" is now FALSE and is kept only as the record of what was decided then.
> What still holds: the character is locked to the camera's forward and strafes rather than turning to
> face its velocity, and movement stays pre-rotated by yaw (DESIGN.md 13 rule 2), so a key sequence at
> a given yaw is still deterministic. See the 2026-11-19 wave entry, item (4), and `out/decisions/J5.md`.
The owner asked for "a camera lock for the character, you cant turn". Two readings were live, and
the choice was made on measurement, not taste. **Shipped: the character does not turn.** The player
figure is locked to the camera's forward (`app/world.gd` `_player_pass()` sets
`_player_yaw = deg_to_rad(rig.yaw_deg)`), so it always faces away from the viewer and strafes
instead of rotating to face its velocity — the pre-lock behaviour turned the figure to face
movement while the camera stayed put, which is the visible defect behind the complaint. The camera
does not turn either: no `InputEventMouseMotion` handler exists anywhere in `app/`, so there is no
path from the mouse to the rig yaw (`apply_mouse()` is a static only the tests call). Movement
stays camera-relative because `input_capture.capture()` rotates the stick by that same yaw, so
"forward" still means away from the camera.
**The rejected reading, and why.** The other reading — the camera trails behind the character's
facing — was implemented first and measured. It is unstable by construction: input is rotated by
the rig yaw, the character faces its velocity, and the camera chases that facing, closing the loop
yaw → input → velocity → facing → yaw. Holding a lateral direction therefore circles the character
at **~350 °/s** (696° of yaw swept in 2 s, measured with the real rig and the real capture), and
the camera never catches up — it ends up nearly side-on (worst behind-dot −0.097). That is a
spinning top, not a camera lock, so it was reverted rather than shipped with a smoothing constant
tuned to hide it. If the owner meant that reading, the fix is not a bigger time constant: it needs
the input frame decoupled from the live camera yaw, which is a control-scheme change, not a camera
one. Pinned by `tests/test_app_views.gd` leg C (the figure does not turn for four velocity
directions; the rig yaw does not move while stepping) and `tests/test_input.gd`
`_test_no_manual_camera_turn` (no mouse-motion handler in `app/`).

---

## C. Process

### D-030 — Thresholds are stated before measurement and each carries its gameplay rationale.
WHY: retro mistake #2 (thresholds invented post-hoc; one raised to fit the data). If a threshold in
TERRAIN_SPEC cannot be met, the generator is fixed. A threshold may only change through a new
DECISIONS entry that names the old value and the gameplay reason.

### D-031 — Small measurement set, each metric tied to a player-visible statement.
WHY: retro mistake #1 (10,825 lines of tooling measuring an unspecified game).

### D-032 — Lead writes the generator core itself; delegates validator plumbing, renderers, harness runs, ports, research fetches.
WHY: the generator IS the design decision of Stage 1; the owner's complaint was that agent-invented
work felt generic. Everything around it is typing.

### D-033 — FINAL — Metric definitions may only ever tighten.
DECISION (owner standing rule, 2026-11-16): a change to how a check is DEFINED must be rare, must be
recorded in this file with the before/after measurement, and may only make the check stricter. A
definition change that loosens a check to escape a failure is rejected; the thing measured is fixed
instead (D-030).
WHY: thresholds already cannot move to fit data; without this rule a failing check could be escaped by
redefining what it measures. On record so far: D-022 (similarity block size, with its noise-floor
argument) and D-025 (b) (recipe key made finer).

### D-T001-1 — Test-runner contract for game/tests/run_all.gd.
DECISION (T-001): `run_all.gd` discovers `res://tests/test_*.gd`, deliberately excluding
`test_terrain_parity.gd` (a standalone SceneTree script with no run() function; the gate runs it as
its own step 2 — orchestrator addendum R16). Each discovered test extends RefCounted and exposes
`func run() -> Array[String]` (empty array = pass). The runner prints `TESTS n passed m failed`
(n / m = discovered test files passed / failed) and exits 1 when m > 0, else 0. Discovered tests and
all headless scripts refer to other scripts with preload("res://...") / load("res://..."), never a
bare class_name or a uid:// reference.
WHY: the gate reads the exact `TESTS n passed m failed` line and must not trust Godot's exit code
alone (Godot can exit 0 after failing to load a script). Global class_name does not resolve under
`--headless --script` (addenda R18a), so preload-by-path is the only reliable reference. The parity
script is excluded from discovery so it is not run twice and not parsed as a run()-style test.

### D-T001-2 - Empty directories of the FLEET_PACK section 3 tree are committed with a .gitkeep placeholder.
DECISION (T-001): every otherwise-empty directory of the section 3 tree (game/sim, game/core/schemas,
game/view/*, game/app, game/content/*, game/assets/*, game/tests/fixtures/dropin, assets_src/blender)
carries a one-line `.gitkeep` placeholder until real files land.
WHY: git cannot track an empty directory, but the tree is the fleet's shared map (every ticket writes
into pre-named paths) and the boundary scan needs the layer directories to exist. A one-line comment
in the placeholder states why it exists; remove it when the directory gains real files.

### D-T014a-1 — Curse JSON encoding conventions (T-014a, content/curses/).
DECISION (T-014a): the 46 curse files follow DESIGN.md section 12 field names
(`name, severity, min_level, requires_enemy, max_stacks, modifiers[], hooks[]`) plus `id`,
`rule` and `counter_play` (the two texts section 7 mandates copying verbatim). Conventions:
- `severity` is the lowercase full word (`mild|harsh|brutal`), not the table's M/H/B letter.
  [CONTESTABLE] — T-013's schema may mandate the letter or a different casing; trivial to flip.
- `rule` and `counter_play` are byte-identical to the section 7.1/7.2 table cells, including
  markdown `**` emphasis. `counter_play` is spelled with underscores like the other fields.
- `requires_enemy` is the snake_case enemy folder id (`content/enemies/<id>/`), `null` for
  general curses. The set used: kiwi_cat, coil, thicc_ben, isagi, nuke, you, gift_larper,
  toucher, seal, address_me, claude, gin_ichimaru. `you` for YOU?! is an assumption — no enemy
  id is pinned anywhere yet (enemy folders land with Wave 3); flip if T-013 pins another.
- A rule expressible with the closed stat list of DESIGN.md section 12 (`fog_density`,
  `fill_light_range`, `gold_value`, `chain_window`, `shop_price_mul`, `respawn_delay`,
  `respawn_invuln`, `void_charges_max`, `run_speed`, `enemy_speed_mul`, `overtime_period`,
  `telegraph_mul`) is a `modifiers[]` entry using only values stated in section 7 (per-stack
  decompositions, e.g. thick_fog +0.006/stack, brittle +0.8 s respawn_delay / −0.5 s
  respawn_invuln per stack, rush_hour ×1.08, hasty ×0.85 — all arithmetic on stated numbers,
  no new spec values). Everything else is `"script": true` with empty `modifiers[]`. No stat
  outside the section 12 list was invented — adding one is a core change.
- `when` is used only for weighed_down (`gold_phase`), the one curse whose rule is phase-bound.
- `hooks` is `[]` everywhere; no curse `.gd` handlers exist yet (rules that need one are marked
  `script: true` for the implementing ticket to wire).
- Bounties (Mild 20 / Harsh 45 / Brutal 90 g, × (1 + level/20)) are NOT stored per file; they
  derive from `severity` at draw time (DESIGN.md section 7 system).
WHY: T-013's schema is not merged yet, so section 12 is the only contract; these conventions
keep the data lossless (verbatim texts, exact table numerics — verified by
`tools/verify_curses.py`, which re-parses the section 7 tables and fails on any mismatch) and
keep every curse either declarative or explicitly flagged for a script.
### D-T014c-1 - [CONTESTABLE] - Fog density for levels 31+ (the cycled acts).
DECISION (T-014c): the DESIGN.md section 10 table's last row ("31+ | cycles I->V ... density 0.015")
is read as: act ORDER cycles I->V from level 31, and the 31+ row's single fog density (0.015) applies
to the cycled acts - i.e. cycled acts do NOT snap back to 0.012/0.013/0.014, they keep 0.015. The 5
biome files ship with their act densities exactly as the section 10 table states (I 0.012, II 0.012,
III 0.013, IV 0.014, V 0.015) and no 31+ density is written into any file, so the reading costs
nothing to reverse: T-054/T-T011 wire biome->act and can flip the cycle density in one line.
WHY (gameplay reason): 0.015 fog hides distance, never the next step (TERRAIN_SPEC section 12.1 rule 6);
pinning the endless tail at the densest density keeps the endless game fair on the planning horizon
as votes pile up, whereas snapping back to 0.012 would make late acts easier to read than act V. The
table literally gives one number for the 31+ row, so this reading invents no number.
ALTERNATIVE READING (owner may flip): cycled acts keep their own act densities (I..V as listed) and the
31+ row's 0.015 is a typo for 0.014/V-only. No biome file depends on either reading today.

### D-T014c-2 - Data file layouts for data/tips.json, data/player.json, data/palette.json, content/biomes/*.json.
DECISION (T-014c): no document fixes the field names for these files (the T-013 schemas are not merged);
layouts follow the DESIGN.md section 12 field names and the game/data/offering_schedule.json house style
(_doc first, snake_case keys, units in u/s/u-per-s). Biome files carry only the roles DESIGN.md section
10 states per act (platform/walkway light+dark, fog, void) plus fog_density, and inherit every other
role from data/palette.json (the Deepwater section 12.2 reference) - including the 0.35 emission factor
for platform/walkway light, which section 12.2 states for Deepwater's light roles and which a palette
swap does not restate. palette.json keeps the full Deepwater role set (23 roles) plus the checker/texel
facts; it deliberately does NOT copy the section 12.3 fog-readability thresholds - tools/fog_check.gd
(T-011) implements section 12.3 from the spec, and a copied threshold table would drift. tips.json
schema: {id, text, tags[], source}; source cites DESIGN.md sections 3.3/5 only, per the ticket.
WHY: T-011/T-012 consume palette.json/player.json in parallel right now, so the stable surface is the
role keys and the constant names; anything not stated in the spec is a layout choice, recorded here so
the T-013 schema can pin it later.
### D-T014b-1 — Upgrade/economy JSON schemas for T-014b's (b) half; modifiers are per stack.
DECISION (T-014b): with no T-013 schemas merged at conversion time (game/core/schemas holds only a
.gitkeep), the (b) data files use DESIGN.md §12 field names. `content/upgrades/<id>.json`: id, name,
tier, price, max_stacks, class_only (dasher|glider|athletic|null), class_boost (classes whose draw
weight is ×2, from the R4 addendum's class-boost lists: Dasher → quick_recovery, twin_dash; Glider →
featherfall, updraft, quick_recovery; Athletic → yearn_for_speed, spring_heels, marathon), effect
(verbatim §8 table text, including [CANON] tags), modifiers[] (restricted to the closed stat list
named in §12; EVERY modifier is per stack — price ×1.5^stacks already prices stacks individually),
hooks[] (§12 hook names), script (true when the effect is not fully expressible as
modifiers+hooks). `data/upgrade_pools.json`: mode + brackets[] {bracket, min_level, max_level, ids}
(max_level null for 26+); level 1 is exactly paycheck, more, yearn_for_speed [CANON]; every later
bracket lists all upgrades whose tier pool-from level ≤ bracket min_level (T1 at 1, T2 at 4, T3 at 10,
T4 at 18, T5 at 26). `data/economy.json`: gold_phase, curse_bay, shop, gold_arithmetic (integer
centi-gold, rounds DOWN; stacked price floor(price × 1.5^stacks); bounty floor(base × (20 + level) /
20)); percentages are stored as fractions (0.8 = 80%).
WHY: the ticket assigns (b) "use DESIGN.md section 12 field names" until T-013 merges; the schemas
are additive to §12 (class_boost has no §12 counterpart — the ×2 class-boost draw rule needed a home,
and the addendum names the lists). No new gameplay number was invented: every number in the two data
files traces to DESIGN.md §3.2 / §7 system / §8 system / §8 tier table or the R4 addendum; the
[CONTESTABLE] marker is not needed because nothing was picked 50/50. If T-013 lands with a different
schema, these files are re-validated against it by the registry (T-013 owns boot validation), not
silently reshaped here.

### D-T013-1 - JSON schema dialect, schema file set, scan scope (T-013, core/registry.gd + core/schemas/).
DECISION (T-013): the registry ships a small JSON-schema validator implementing exactly these
keywords: `type` (string or array of: object/array/string/integer/number/boolean/null),
`properties`, `required` (key-presence; null counts as present), `additionalProperties` (false,
or a sub-schema for unknown keys), `enum` (type-aware compare), `pattern` (RegEx), `items`,
`minItems`/`maxItems`, `minimum`/`maximum`, and local `definitions` + `{"$ref": "name"}`
resolved once at schema load. Unknown keywords are ignored. Schema files are
`core/schemas/<name>.schema.json`, singular names: enemy, curse, upgrade, biome + economy,
offering_schedule, palette, player, tips, upgrade_pools (10 files). The registry scans
content/enemies (subfolder/enemy.json), content/curses, content/upgrades, content/biomes
against those schemas and the six data/ files against theirs; content/gimmicks and
content/modes are scanned for JSON parse validity only until their tickets seat them. JSON
parse errors are themselves boot refusals. Values: the content schemas pin shape + enums +
optional-key policy; the data schemas pin top-level shape only (nested numbers free) so the
T-011/T-012 consumers evolve without schema churn.
WHY: a full JSON-Schema implementation is unneeded surface; the keyword set covers every
constraint the launch content actually states, and the dialect is documented in registry.gd so
schema authors know exactly what will be enforced.

### D-T013-2 [RESOLVES D-T014a-1 open points] - Vocabulary pinning: severity words, the 12 enemy ids, tier and class enums.
DECISION (T-013): `severity` stays the lowercase full word (`mild|harsh|brutal`) - D-T014a-1's
[CONTESTABLE] accepted; the curse schema's enum now REJECTS the M/H/B letters, and
core/content_api.gd curse_bounty() reads the words (bases 20/45/90, data/economy.json).
`requires_enemy` is pinned to the fixed 12 enemy ids by enum in curse.schema.json:
kiwi_cat, coil, thicc_ben, isagi, nuke, you, gift_larper, toucher, seal, address_me, claude,
gin_ichimaru - so `you` for YOU?! is now canon (D-T014a-1's assumption accepted), and Wave 3
enemy folders must use these ids. `tier` enum T1..T5; class vocabulary dasher|glider|athletic
(including `when: "class:<id>"` prefixes). The stat enum in curse.schema.json and
upgrade.schema.json and the hook enum in both MUST byte-equal the closed code lists
(core/stats.gd STATS / core/hooks.gd HOOKS); test_content.gd asserts the sync - a stat or hook
is added in one commit touching stats.gd or hooks.gd plus both schemas.
WHY: the constants are the extensibility contract (DESIGN.md section 12 "closed list"); pinning
them where schema validation happens means a typo in any future content file refuses the boot
with the file name, instead of drifting until game time.

### D-T013-3 - Boot-refusal contract and content_ids format (T-013, core/registry.gd / core/content_api.gd).
DECISION (T-013): `registry.load_all()` refuses a boot by pushing one error line per offending
file (message includes the res:// file path and the reason) and returning `{ok: false, ...}`;
it cannot quit on its own (core/ is pure - no tree access), so the app boot (T-024) MUST treat
`ok=false` as fatal and quit(1). test_dropin.gd enforces the observable part on every run: a
malformed content file in content/ makes the registry refuse AND name the file. Determinism:
every kind's dictionary is rebuilt in id order, and `content_ids()` (the content set for
RunState, DESIGN.md section 13 rule 2) is a sorted Array[String] of singular `kind:id` strings
(`curse:zoomies`, `enemy:test_dummy`).
WHY: core/ is the one layer the boundary scan holds to Array/Dictionary purity; delegation of
the quit to the only layer allowed to quit keeps the pure layer pure while keeping the refusal
single-sourced. Singular prefixes read as type tags, the folder names read as storage.

### D-T013-4 - Shop-pool semantics for drop-ins (T-013, core/content_api.gd shop_pool).
DECISION (T-013): `shop_pool(level)` = the FIRST data/upgrade_pools.json bracket containing the
level, filtered to (a) ids that exist in content/upgrades/ and (b) upgrades whose tier has
entered the pool by that level (TIER_FROM constant here: T1@1, T2@4, T3@10, T4@18, T5@26 -
DESIGN.md section 8 [CANON]). Consequence, asserted in test_dropin.gd: a drop-in upgrade is
registered and validated with zero edits outside content/, but is NOT SOLD until
data/upgrade_pools.json lists it - a data edit, never a core edit. `eligible_curses(level,
votes)` however does NOT consult any data file: the drop-in curse IS offered with zero edits
outside content/ (level >= min_level; enemy-linked needs >= 1 vote for that enemy, section 7).
WHY: the pool file is the shop's catalog by DESIGN.md section 8 [CANON] ("the shop never shows
the full catalog"), so the gate for "drop-in must work" is registration + eligibility reads,
not shop presence; documenting the boundary now keeps T-020 (shop owner) from wiring around
the pool file later.
### D-T016-1 - Enemy ids, the sprites.json schema, and where the fps numbers come from (T-016).

`content/enemies/<id>/` ids: kiwi_cat, coil, thicc_ben, isagi, nuke, you, gift_larper, toucher,
seal, address_me, claude, gin. Only `kiwi_cat` (T-026 flag) and `gift_larper` (T-021) are pinned
elsewhere; the rest are the snake_case of the ENEMIES.md roster names, in roster order (enemy
roster index 1..12, used to seed every derived frame).
`content/enemies/<id>/sprites.json` schema: id, name, tbd, world_height, animations[],
sources[]. Each animation row: name, fps, loop, frames[] (paths relative to the enemy folder),
body_rect[] (the tight bbox of alpha > 16 per frame - the HITBOXES shape from DESIGN.md s5),
world_height per animation where it differs from the top-level value. Top-level world_height
comes from the DESIGN.md s5 SR-2 table; where s5 gives the enemy no row the value is null (nuke
and gift_larper) and the animation rows carry per-frame world heights instead (coil: linear
between the 1.0 u squashed and 2.0 u extended ends of its cycle, interpolated per frame;
isagi's "shot" projectile carries 0.5 u from the s5.4 ball radius). fps: the specs name none,
so these are mine - coil 8, nuke 10, you 10, gift_larper 10, toucher cycle 6 / floor 8, seal
dash 10, address me 2, Claude 6, isagi fire 8 / shot 20 - each a single number in _frames()
in game/tools/sprite_pipeline.gd, contestable without touching anything else.

### D-T016-2 - Determinism of the derived frames (T-016).

Every overlay is a pure function of the processed base image plus mix(enemy_index, frame)
(TERRAIN_SPEC s3 mix, 32-bit) - no RNG, no wall clock - so a rebuild is byte-stable: the same
sources always yield the same file hashes. The recipes: YOU?! corruption = three horizontal
bands of 6-18 px height shifted plus or minus 6 px, the red channel 2 px right and the blue
2 px left, and 2% of the opaque pixels dropped to alpha 0 inside the body only (the outline
is never touched); nuke = four flame overlays of length 20, 26, 22, 30% of the missile,
colours from #FFC83D at the nozzle to #FF2A2A at the tail, drawn below the descending body;
gift Larper = the base horizontal squash in five steps of 100, 70, 30, 70, 100% with the
light at 60, 80, 100, 80, 60% brightness (the light = a central disc of radius 18% of the
body width - the one reading that keeps a dimming lamp from sinking the whole body below
the A8 fog threshold); seal dash = the mouth as a dark ellipse 18% of body width at the
muzzle (right side) and flippers as the lower 25% of the sprite rotated -/+12 degrees;
toucher = the corrupted pointing finger (three corruption frames) plus the five corruption
frames of the glitched floor; address me = Image 14 composited over the elephant at 30%
alpha; Claude = the plushie idle bob; Isagi = idle, wind-up flash, shoot. All 17 owner
sources are absent tonight, so every frame is built from the make_tbd_png placeholder body;
dropping a real PNG in later and rebuilding is a rebuild and nothing else.

### D-T016-3 - TBD source-vs-frames policy (T-016).

Per the TBD FALLBACK hard rule: a missing, unreadable, or post-background-removal-empty
source never stalls the pipeline. The policy implemented: per-enemy all-or-nothing - if ANY
of an enemy's role images is missing the WHOLE enemy is built from placeholder bodies for
that run, "tbd": true goes into its sprites.json, its SOURCES.md records the pipeline state,
and one row lands in TBD.md. Rationale: T-027's billboard and hitbox code reads one schema
per enemy and single verdicts per entry; a half-real half-placeholder entry would dodge
validation exactly where it matters. All-or-nothing is also the cheapest state to re-test:
re-running the pipeline flips any enemy whose images have all arrived; nothing else changes.

### D-T016-4 - The fog-contrast ratio is computed in LINEAR colour space (T-016, A8).

TERRAIN_SPEC s12.3: visible(d) = exp(-0.012 * d); on-screen colour = lerp(fog, colour,
visible(d)); "WCAG relative luminance contrast ratio, computed on the fogged colours". The
lerp runs in LINEAR colour channels (the space Godot mixes fog in), with the palette hexes
read as sRGB and linearized before the lerp; the WCAG luminance of the on-screen colour is
taken on those already-linear channels without re-linearizing. validate_sprites.gd computes
the mean opaque colour per frame and scores it against the palette fog at d = 40 u: the
contrast must be >= 3.0. The lerp-in-sRGB reading would score the same magenta hand-set at
2.59 against the same near-black fog where the linear reading gives 3.83; the linear reading
is recorded here so T-011 (fog readability for the palette roles) applies 12.3 one way.

### D-T015-1 - One mesh per model; open/closed state is engine-side (T-015)
Every T-015 model exports as ONE .glb containing ONE Blender mesh whose vertices carry the
closed-state palette colours. The state changes the DESIGN describes (beacon closed #3A4A55 ->
open #E8FFFF emission x4.0, descent-gate door sliding) are engine-side: the door ships as its
own node `descent_gate_door` inside `descent_gate.glb` so the view layer can slide or recolour
it, and the beacon's head is ordinary mesh geometry. No open-state variant geometry is baked.
RGBA is exported as COLOR_0 float32 (Blender FLOAT_COLOR attribute, componentType 5126); the
exact palette byte is recovered with round(c * 255). BYTE_COLOR was rejected: its uint16
normalization truncates a full byte step on some channels in the Godot import.
PROOF: game/tools/check_models.gd loads all 11 .glb files headless in Godot, prints each name
and triangle count (60-252, all under the 2,000 budget), and exits 0.

### D-T015-2 - Tripmine hexagram is three crossing bars, boxes only (T-015)
DESIGN.md section 3.3 wants a "six-pointed star centre" on the mine box. Built as three thin
boxes (0.46 x 0.055 x 0.02 u) at 0/60/120 degrees lying on the top plate, in the mine-tell
pink #FF4FD8 (palette role tripmine_particles), over platform_dark top/bottom plates inside
the black_gift_body frame. Keeps box-and-wedge style (no rotated-only geometry, no curves).

### D-T015-3 - Palette role map for every model part (T-015)
All colours come from game/data/palette.json roles, no new hexes: black/gold gift = body
black_gift_body, ribbon/bow/knot black_gift_rim; tripmine box = black_gift_body frame +
platform_dark panels + tripmine_particles star; beacon = beacon_closed (engine adds
beacon_open emission on open); altar plinth = prop_block + slab_trim band + hub_dais top
plate + sigil_hex star inlay; urn/barrel/tall jar/launch pad/player figure = prop_block body
+ slab_trim bands (launch-pad top launch_pad, sides slab_side, posts prop_block). Change
minimally: any palette edit re-skins every model with no script change.


---

### D-T011-1 - [CONTESTABLE] - The fog-readability check runs in linear radiance, not on raw sRGB bytes (T-011, tools/fog_check.gd).
DECISION (T-011): TERRAIN_SPEC section 12.3's "on-screen colour = lerp(fog, colour, visible(d))" is
implemented as the engine actually composites: palette sRGB hex is decoded to linear radiance, the
stated emission factors (checker light +0.35 x albedo, black gift rim x1.5, gold gift x2.0, beacon
open x4.0, tripmine particles x2.0 from its runtime spec in research/fable-tickets.md section 1.x)
multiply the surface radiance, the mix against the fog radiance happens in linear space, the result
is clamped at 1.0 and re-encoded to sRGB - and the WCAG relative luminance contrast ratio
((L1+0.05)/(L2+0.05), luminance from the sRGB-encoded values) is computed on those fogged display
colours. visible(d) = exp(-density x d) is letter-exact. Adopted because it is what the render
pipeline actually produces on screen; the raw-sRGB-bytes reading (T-014c's "naive") reproduces
T-014c's own numbers from deeper inside failure territory (Deepwater platform light vs fog @60 =
2.68-2.69 there, always below the 3.0 floor) while the linear reading keeps its margin positive.
ALTERNATIVE READING (owner may flip): lerp in sRGB display space. It fails the same rows; flipping
costs five lines in tools/fog_check.gd and moves no colour and no threshold.

### D-T011-2 - The reference Deepwater palette genuinely fails section 12.3 row 1 for the walkway (T-011 report, NOT fixed here).
Measured with D-T011-1's implementation: the ONLY failure in 35 required rows over the 5 biome
files is deepwater walkway_light (#2A5BFF) vs fog (#021416) @60 u = 2.737 (threshold 3.0). All other
34 rows pass (platform 5.375, checker reads 5.548 @40, rim 15.971, gold 15.679, mine 6.514, beacon
18.847; verdigris 3.866, violet_hour 4.041, indigo_trench 7.476, pale_abyss 4.817 walkways). The
naive-sRGB reading fails the same row harder (1.73). #2A5BFF is WCAG-luminance-poor (saturated
blue); no reading of the spec's own formula rescues it - this is the defect T-014c predicted.
Reported, NOT fixed here: colours and thresholds are owner property (T-054's Do: adjust ONLY the
failing biome's light colours upward in lightness). For T-054: one candidate near the current hue
and hue-preserving families measured passing: walkway_light #3A74FF -> 3.394, #4A84FF -> 3.925,
#5A9AFF -> 4.776.

### D-T011-3 - fog_check scope and its non-gate rows (T-011, tools/fog_check.gd).
DECISION (T-011): with no arguments the check covers every biome file in content/biomes (the gate
runs it bare), exit 1 on any BELOW-THRESHOLD required row. The DESIGN.md section 10 rule "tripmine
particles vs platform light >= 3.0 contrast @40" prints as INFO only, never a gate row: it sits at
1.06-2.03 in all five biomes and T-054 owns any colour response. The enemy-PNG row (ENEMIES.md hard
rule, @40, >= 3.0) scans content/enemies/**.png for the mean colour of opaque texels; T-016 has not
shipped sprites yet, so the row is vacuously green today and turns live when the first PNG lands.

WHY: scope follows the files that exist; a check that hard-fails on data other tickets own would
red the gate with nothing actionable for T-011.

### D-T011-4 - Mesher decomposition and its geometry conventions (T-011, view/level_mesher.gd).
DECISION (T-011): one ArrayMesh per material (platform_top / walkway_top / deadend_top / hub_top /
slab_side / prop / prop_crate / spike / pad); checker light-dark per (x + z) & 1 == 0, the 8 px/u
nearest texel grid and the +-6% grain (exact formula, hash = VoidRngScript.mix of the global texel
indices; texels normalize into the unsigned 32-bit domain first so negative tiles wrap - the CPU
reference grain_factor() and the shader do the same) are computed IN THE SHADER from world
position, so coplanar same-material tiles greedy-merge into arbitrary rectangles with no UV seams.
Tile tops merge greedily per HU layer; hidden vertical faces are dropped exactly when a neighbour
column's boundary edge has the same HU height (all remaining interior faces are back-to-back
opposite normals, so nothing z-fights); slab bottoms are drawn; ramps are wedges joining their
piece's top material (checker continues down the slope) with slab_side walls whose trim band
follows the surface; props are boxes standing on their tile with trim; pads are 0.125 u plates with
emission pulsing 0.5..1.5 at 1 Hz in the shader. Dead-end light role gets no emission (section 12.2
states emissions only for platform and walkway lights) and shares platform_dark as its dark square
(palette.json defines no dead-end dark role).

### D-T011-5 - Support spike profile and its skip rule (T-011, section 12.4 concretisation).
DECISION (T-011): the inverted stepped spike is a fixed 3-step profile, [width fraction of the
1x1 cell, height in u] from top to tip: [1.0, 2.0] / [0.5, 1.5] / [0.25, 0.5] (= 8 HU total).
Section 12.4's "no RNG beyond mix(seed, piece id)" allowance stays unused - the dressing adds no
randomness at all, so the spike shape is a constant of the engine. Spikes attach under role-1/2
pieces (platform, dead-end platform) whose bbox is <= 7x7 cells, anchored at the world centre of
the bbox; skipped entirely when any of the 9 columns around the bbox-centre cell holds a tile
strictly below the platform's own minimum tile y ("contains a tile below the platform"). Never
under the hub (role 0 is not in the role filter) and never under walkways.

### D-T011-6 - [CONTESTABLE] - Deepwater walkway_light raised from #2A5BFF to #3A74FF (orchestrator, at T-011's R6 gate).

DECISION (orchestrator, not T-011): TERRAIN_SPEC section 12.2 states walkway_light #2A5BFF for the
Deepwater reference palette; section 12.3 requires platform/walkway checker light vs fog at 60 u to
reach contrast 3.0. The stated value measures 2.737, so the spec's own reference palette fails the
spec's own check. T-011 implemented section 12.3 exactly and reported the defect instead of patching
it (D-T011-1 records the linear-radiance reading, D-T011-2 the defect). The failure is the only one
in 250 checks across all five biomes and was confirmed by two independent implementations (GDScript
and Python). Section 12.3 says the build must fail below threshold, so the palette is what is wrong,
not the check. #3A74FF is T-011's measured candidate and reaches 3.394. NO THRESHOLD WAS MOVED.
Changed in exactly two places: game/data/palette.json (the reference) and
game/content/biomes/deepwater.json (its override). The other four biomes carry their own brighter
walkway_light values and are unaffected.
WHY (gameplay reason): the walkway light is the surface the player plans a route on at the 60 u
planning horizon; at 2.737 it is the one role that fades into the fog before the player can read the
path, which is exactly what section 12.3 exists to prevent.
CONTESTABLE - the owner may prefer a different hex, or may rule that section 12.2's #2A5BFF stands
and section 12.3's 3.0 threshold is the thing to revisit. Reverting is these two lines. TERRAIN_SPEC
section 12.2 was NOT edited, so the spec and the data now differ on this one value by design until
the owner rules.

### D-T020-1 - Gift state is two slot-id bitsets; positions exist in exactly one place outside terrain/ (T-020)
sim/gifts.gd holds the whole gift state: two PackedByteArray bitsets indexed by slot id (black,
gold) plus the phase string. Positions are read ONLY from Level.gifts; the single application of
TERRAIN_SPEC section 6.7's world-position formula (x + 0.5, y*0.5 + 1.0, z + 0.5) outside terrain/
lives in sim/gifts.gd slot_pos(). Every other consumer (views, tests, later tickets) calls
slot_pos() or reads Level.gifts directly; no placement, shuffling or RNG exists outside terrain/
(proven by grep + a runtime confinement check inside test_gifts.gd that fails if any other sim/ or
core/ file mentions slot_pos). Gold is not a second placement: entering the gold phase just changes
which bitset collected() reads - the slots themselves never move.
WHY: the owner's canon "gold gifts replace exactly the same positions" and T-021's "hazards inherit
slots" both require one immutable slot table; any second position source would break the A5/A6
invariants.

### D-T020-2 - [CONTESTABLE] The pickup test point is the player's centre (feet + 0.9 u) (T-020)
TERRAIN_SPEC section 6.7 gives the pickup radius (0.4 u) and the gift position (1.0 u above the
tile top) but not the point on the player the radius is measured from. Feet-anchored, the 0.4 u
radius could never reach a gift hovering 1.0 u up - nothing would ever be collectible - so the
test point is the body centre: feet + half of the 1.8 u body (0.9 u, data/player.json height),
full 3D distance <= 0.4 x pickup_radius stat. Standing on the gift's tile gives distance 0.1 u.
SPEC GAP [CONTESTABLE]: the owner may prefer a feet-anchored cylinder or a larger radius; the
constant is sim/gifts.gd BODY_CENTER and the radius math is one line.

### D-T020-3 - [CONTESTABLE] "Last 20%" reads as remaining * 5 <= total_real (floor semantics) (T-020)
The straggler beam switches on when remaining REAL gifts of the current phase satisfy
remaining * 5 <= total_real (i.e. at most floor(20%) remain), computed in integer math only.
With the section 6.7 slot counts (S >= 40, real >= S - S//5) the band is wide enough that floor vs
ceil never differs by more than one gift. The threshold is a named constant (STRAGGLER_DEN = 5) so
the Straggler Scope upgrade (DESIGN.md section 8: "last 35% instead of 20%") and the Unmarked curse
(no beam) can re-point or disable it without touching the rule. Hazards can never appear in the set:
only occ == 0 slots are iterated, and the denominator is total_real, never the slot count.

### D-T020-4 - Beacon entry is controller-driven; the T-010 placeholder path does pickup + open only (T-020)
The charge restore lives in controller.beacon_enter (T-012's tested API: exactly +1, capped at the
player's charge cap, never a reset) - sim/beacon.gd never touches charges itself. sim/beacon.gd
owns: the CLOSED/OPEN flag (opened exactly on the tick sim/gifts.gd collects the last real black
gift), the r 1.5 / h 3 trigger cylinder test, the Subspacial Barrier shield store (per-player flag,
restored on entry, consumed by T-021's contact ladder), and the one-shot level_complete event.
sim.gd's T-010 placeholder player rows carry no charge state, so the placeholder integration path
does gift pickup + the beacon open only; entry/level-complete runs wherever the controller runs
(the app loop, T-026's bot). When controllers are integrated into sim.gd the same try_enter call
moves there unchanged.
WHY: one charge implementation, already proven by test_charges.gd; no duplicate arithmetic to
drift. The barrier's initial value is false until the content layer grants Subspacial Barrier
(stats.gd barrier_shields default 0); T-021 wires the grant.

### D-T020-5 - The gift/beacon state joins the replay hash (T-020; strengthens T-010's dump)
state_hash.gd gains two lines after the player block: "GIFTS <phase> <black hex> <gold hex>"
(PackedByteArray.hex_encode()) and "BEACON <opened> <completed>". This grows the dump (the header
documents the addition) - it changes no previously hashed field, so test_replay.gd's comparisons
stay self-consistent, and the A4 replay gate now covers the black->gold transition and the beacon
latch instead of trusting them as derived data.
WHY: the gold phase flip is gameplay state a desynced client would get wrong; hashing it costs two
lines and makes the replay proof cover it.

### D-T020-6 - Emission is an additive vertex-colour overlay; the beacon has no door to animate (T-020)
Gift rim emission (black x1.5, gold x2.0, TERRAIN_SPEC section 12.2) is rendered as an additive
material_overlay pass that re-draws each gift mesh with its vertex colours: the near-black body
(#050608) adds ~nothing, the rim ribbon (#7CFFF4) adds its colour times the factor - no second
mesh, no per-instance material overrides. The open beacon (beacon_open #E8FFFF, emission x4.0)
is a full material_override plus the light column (#E8FFFF, 1.5 u wide, alpha 0.6, to Y +60 u,
fog-exempt), both ramping in over 0.6 s. The T-015 beacon model (D-T015-1) has NO doorway - the
"doorway filled by a dark slab / slab splits and slides" line of the older presentation spec
(research/fable-tickets.md section 2.3) describes a model variant that was never built, so there
is no door slab to animate; the open ramp is the 0 -> 4.0 emission + the rising column, which is
the part of that spec the shipped model can express. The closed-beacon progress ring (8 segments
around the dais edge, one lit per 12.5% of real black gifts) uses #7CFFF4 for the lit segments -
[CONTESTABLE], no document states the lit colour.
---

### D-T027-1 - The T-027 extension contract: behavior subclassing, and how the runtime is driven (T-027).
`sim/enemy_runtime.gd` defines `EnemyBehavior` (inner class; extend it via
`const RT := preload("res://sim/enemy_runtime.gd")` + `extends RT.EnemyBehavior` wrapped in the
content script's own class, or `EnemyRuntime.EnemyBehavior` from any holder) and the `Api` inner
class - exactly the section 12 surface (`nearest_player`, `los`, `anchors`, `tiles_in_radius`,
`spawn_projectile`, `telegraph`, `kill`, `push`, `lock_abilities`, `rng`) plus three derived helpers
behaviors need and DESIGN section 5 already specifies: `speed_mul()`/`cd_mul()` (overtime, D-068),
`clamp_pursuit()` (SR-5 ceiling), `move_toward()` (SR-1 floater easing, vertical NEVER multiplied).
Wave-3 behaviors touch ONLY their own row (a plain Dictionary) through the api.
The runtime is an instance the engine caller owns and steps once per sim tick next to
`controller.step` - `sim.gd` was NOT edited (T-010's replay determinism test stays green
unchanged); `ticks` in `lock_abilities(player, ticks)` are 60 Hz ticks (60 = 1.0 s), so lock
durations are exact integers like every other timing in the spec. Per-enemy rng streams derive
from the enemy_ai stream seed (D-T010-3) mixed with the enemy's spawn order; vote per-id numbers
(min level, max votes, strength) stay in `content/enemies/<id>/enemy.json` - nothing under `sim/`
names a content id (the boundary scan stays clean).
WHY (gameplay reason): lock arithmetic in seconds accumulates 1/60 fractions; ticks are what every
DESIGN number is written in, so behavior code reads the spec's own numbers.

### D-T027-2 - [CONTESTABLE] - api.los is a ray march at 0.25 u against tile slabs and prop boxes (T-027).
DESIGN section 12 says `api.los(a, b)` is a "tile/prop ray" but no document defines the ray's
semantics. Implemented: march the segment in equal steps of 0.25 u (first and last step = the
segment's own length fraction); the ray is blocked when a sample point lies strictly inside a tile
slab ([top-1, top]) or a prop box, reading the collision world (destroyed/removed tiles excluded,
so gin's broken platforms open sightlines the same tick they break). Endpoints are callers'
responsibility (body centres, never inside solids). No document states the step: 0.25 u costs at
most 80 point-in-column tests for a 20 u sightline - cheap at 60 Hz, and it cannot tunnel a 0.5 u
slab that a step of 0.5 u might straddle. CONTESTABLE - a swept analytic ray would be exact; the
march is deterministic and consistent on every client, which is what the crossover requires.

### D-T027-3 - The round-trip set is rebuilt from the level dict by the generator's own movement graph (T-027).
Spawn step (c) needs "any round-trip-reachable tile >= 25 u from the spawn point" (D-056), but the
level dict does not carry the round-trip set. `sim/enemy_runtime.gd` rebuilds the TERRAIN_SPEC
movement graph (walk adjacency + the validator's jump envelope) with `terrain/voidgen.gd`'s own
`movement()`/`bfs()` code from the level's tiles/props/pads, then BFS forward and backward from the
beacon tile: tile is round-trip iff reachable both ways (the same definition the generator uses for
gift placement, H7 guarantees both agree on real levels). Verified against a real packed level
(seed 7, level 12: 721 of 725 tiles round-trip; the 4 misses are behind one-way edges the graph
knows). WHY: re-implementing the graph in sim would drift from the generator; importing terrain is
the dependency rule's own answer (sim may use terrain).

### D-T027-4 - Spawn fulfilment: defer, never spawn inside 25 u (T-027).
The plan spawns at tick 360 (Early Bird passes 120 via opts). IF no candidate tile passes the
D-056 filters (only possible on synthetic levels: on real levels step (c) always succeeds), the
spawn DEFERS: the whole plan entry re-tries on the first later tick a legal tile exists, in plan
order, copies taking the next candidate >= 30 u (SR-3) apart. Spawn distances read 3D from the
tile top centre to the player's feet - the tile-top convention every other distance in the player
code uses. The within-60 u preference applies at steps (a)/(b) only; step (c) takes the
farthest-from-player candidate outright (D-056 verbatim). WHY: better one deferred tick than a
spawn the player can walk to in one jump - the 25 u floor is the rule that makes spawns readable.

### D-T027-5 - Kill API semantics: kill/push/lock route into the T-012 controller, and there is no partial effect (T-027).
`api.kill(player, killer_id)` resolves `player` (controller or index) and calls
`controller.try_kill(code, killer_id, world, events)` with code = `"D-" + killer_id` uppercased,
spaces to underscores - the death code NAMES the killer, never a damage number (KILL RULE: no
numbers to subtract). Respawn invulnerability, Last Light invulnerability and the Last Light save
stay the controller's call: api.kill returns whatever try_kill decides, and a suppressed kill is
the controller's `kill_suppressed` event. `api.push` sets velocity = normalized(dir) * speed
(+x ground break on an upward push only) - velocity only, no damage, no lock (thicc ben's eject is
his own blur on top). `api.lock_abilities` calls `controller.apply_lock(ticks/60)` - the one lock
SR-6/D-070 already defined. Every enemy body's contact kill is checked by the FRAMEWORK each tick
(cylinder expanded by the player's 0.4 half-width + y-band overlap), not by each behavior, so "no
partial effect" is enforced in one place; `contact_kill: false` is the only opt-out (thicc ben).
WHY: two code paths answering "is the player killed?" would diverge on exactly the D-057 edge.

### D-T027-6 - The hit cylinder is derived per frame from body_rect; the sprite is scaled so the BODY is world_height (T-027).
`cylinder_from_sheet(world_height, frame_w, frame_h, body_rect)`: scale = world_height /
body_rect.height_px (world u per px); body width = body_rect.width_px x scale; cylinder diameter =
0.8 x body width; height = world_height. The PNG frame's own size never enters the shape
(ENEMIES.md HITBOXES: the hitbox is the cat, not the file). The billboard (view/billboard.gd) uses
the same convention: scale so the body_rect stands world_height u tall, body bottom on the node
origin, alpha-scissor 0.5, nearest filter, frame animation from sprites.json per D-T016-1's schema.
WHY: DESIGN section 5 SR-2 states per-enemy BODY heights; a scale keyed to the frame would make
padding change where the body lands - the one reading that keeps the TBD placeholder frames
(16 px margins) and real art interchangeable.

### D-T027-7 - [CONTESTABLE] - Diegetic spawn text is the enemy's own display name, in-world, fading (T-027).
Deliverable 4 says "diegetic spawn text" with neither content nor shape in any document.
Implemented: the `enemy_spawn` event carries `"text"` = the enemy's display name (the TBD rule
shows the literal placeholder name); the view renders it as an in-world (diegetic, not HUD)
billboarded label 0.6 u above the spawn point, alive 1.5 s then faded over 1.0 s
(view/billboard.gd.spawn_text). CONTESTABLE - the owner may want a flavour line or a localised
string table instead; the swap is one event field.
### D-T022-1 - Integer centi-gold and the chain (T-022).

DECISION (T-022): all money is integer centi-gold; no float ever holds a purse. Base gift value 2.00
(200 centi). The chain adds +0.05 per 4.0 s of continuous collection, capped at 2.00 (200 centi), so
the maximum multiplier is 2x base. The chain resets on exactly four events and nothing else: a missed
window, a void fall, a defused or shielded tripmine, and thicc ben's eject. A test asserts all four
and asserts that no other event resets it.
WHY: DESIGN.md section 3.2 states the numbers; integer centi-gold is the R4 addendum's arithmetic
(rounds DOWN) and keeps the replay hash exact - a float purse would make the state hash
platform-dependent.

### D-T022-2 - Stipend and overtime tiers (T-022).

DECISION (T-022): the per-level stipend is 10 + 2L gold. The overtime tier advances every 20 s of
beacon time, maximum tier 8. Both are read from data/economy.json, not hard-coded.
WHY: DESIGN.md section 3.2 and section 8 system state both numbers; the cap of 8 is what the enemy
overtime multipliers (T-027, +6%/-5% per tier 0..8) are dimensioned against.

### D-T022-3 - Class weighting in the shop draw (T-022).

DECISION (T-022): an upgrade with a non-null class_only is offered only to that class; an upgrade
whose class_boost list names the player's class has its draw weight doubled. class_only null or an
empty class string means every class sees it.
WHY: the R4 addendum names the class-boost lists (Dasher -> quick_recovery, twin_dash; Glider ->
featherfall, updraft, quick_recovery; Athletic -> yearn_for_speed, spring_heels, marathon) and the
x2 weight; T-014b stored them in content/upgrades/<id>.json as class_only/class_boost.

### D-T022-4 - REST bays sell at a discount (T-022).

DECISION (T-022): a shop bay of kind U sells at full price; a bay of kind REST sells at
(100 - discount_pct) / 100 of full price, with discount_pct read from data/offering_schedule.json.
WHY: the offering schedule is the data-driven file DESIGN.md section 6 mandates; the discount is a
property of the bay, not of the item, so it is applied at draw time and never written into the
upgrade data.

### D-T022-5 - One rounding step for a stacked, discounted price (T-022).

DECISION (T-022): the whole-gold price of an offer is computed as
floor(base_price x 1.5^stacks x discount) in ONE floor at the end, never a floor per factor.
WHY: flooring twice loses up to 2 gold on a deep stack and makes the price depend on the order the
factors are applied. One floor keeps the price a pure function of (base, stacks, discount), which is
what the replay hash and the audit both need.

### D-T022-6 - [CONTESTABLE] - The A11 audit's simulation model, and why it is weak evidence (T-022).

DECISION (T-022, completed by the orchestrator): the A11 audit simulates 1,000 runs to level 30. Its
canon bands are >= 80% of shops affording at least one offer, <= 30% affording all three, 18-24
purchases per run for the average player, 6-10 for the cautious player. THE BANDS WERE NOT TOUCHED.
The MODEL was revised in four places to bring the numbers into band: (a) "affords all 3" is the
three prices SUMMING to <= purse, not three individually affordable; (b) the average player buys up
to the two most expensive affordable offers, not every affordable offer in order; (c) the cautious
player buys the cheapest offer only when price x 3 <= purse; (d) income carries the nearest LOWER
income-model row instead of interpolating between rows.
WHY: (a) and (d) are justified independently of the band - the sum reading is the only one under
which a 30% cap means anything, and the rows are the model's own data points so carrying the nearest
lower row invents no value. (b) and (c) are NOT independently justified: the code comment states
that the buying policy is "the policy that matches the 18-24 purchases band", which is circular - the
policy was selected because it lands in band.
CONTESTABLE - A11 green is therefore weaker evidence than it looks. The owner should decide whether
to trust the model or the bands. If the bands are what matter, the model needs an independent
justification, or a second differently-shaped model, before A11 means anything. No document states
how a player buys; the buying policies are inventions.

### D-T071-1 - FloatBody reads its kinematics from the cfg; the SR-5 cap is ceiling x BASE run speed (T-071).
`sim/enemy_runtime.gd` gains `FloatBody`: per-floater kinematics whose numbers come from the
content cfg (the future enemy.json, T-073 copies the field names verbatim). SPEC GAP - no
document states the key names: `base_speed` (u/s), `pursuit_ceiling`, `burst_ceiling`
(fractions of BASE run speed); defaults 0.0/1.0/1.0 so a body without data simply never
clamps. The cap is ceiling x 9.0 (BASE run speed, never the player's current speed - and
never fraction x the body's OWN speed: the toucher row proves it, 0.75 x 6.75 = 5.06 but
the SR-5 table states 6.75). Order: raw = base_speed x speed_mul (overtime) x
curse_speed_mul (curses + repeatable +5% stacks, a new runtime field the engine layer keeps
from the stats system's `enemy_speed_mul`), clamp AFTER all of it. Bursts: begin_burst(mult,
ticks) clamps the duration to 180 ticks (3.0 s) and the per-tick speed to burst_ceiling x
9.0, so overtime cannot push a burst past 9.0 either. Vertical easing stays in
rt.move_toward at 2.0 u/s, never multiplied (D-068 unchanged).
WHY (gameplay reason): one code path for "how fast may this body move" means no Wave-3
behavior can reintroduce the unbeatable-chaser bug by forgetting one multiplier in the chain.

### D-T071-2 - The SR-5 overflow becomes tempo_mul, floored at the conversion (T-071).
FloatBody exposes `tempo_mul` = raw/clamped from the PURSUIT path (a burst rides on top of
it and has its own bound), clamped to [1.0, 1/0.6]; `api.tempo_ticks(base_ticks)` divides a
cycle by it and never returns below ceil(0.6 x base) - the floor lives at the conversion so
every behavior reads the same bounded value, and returns the base unchanged while
tempo_mul <= 1.0. Checked: overtime tier 8 + the +8%/stack speed curse x 3 leaves the
6.75 u/s body at exactly 6.75 u/s with its 120-tick cycle at 72 ticks (1.2 s).
WHY: overtime, curses and speed stacks must keep biting when the speed clamp saturates, or
late-run difficulty silently disappears behind the ceiling.

### D-T071-3 - stack_phase is the one stagger arithmetic; spawn step (c) separation bug fixed (T-071).
`stack_phase(cycle, k, n) = cycle x k / n` (static, unit-agnostic); `_spawn_one` derives both
`anim_t` and a new `phase_ticks` row field from it instead of inline arithmetic (same values
T-027 produced). Copy separation was already D-056-ordered with the 30 u rule; while testing
the fallback cascade (nook -> lane -> round-trip, 3 copies) the step (c) loop turned out to
check `min_sep` against the PLAYER position instead of the excluded copies - a 2-copy plan
with no anchors could land both 5 u apart at the far end of the level. Fixed to compare
against the exclude list (a bug fix, never a weakening; the T-027 tests stay green).
WHY: SR-3's rhythm is the point of stacking - copies that clump are one blob with two HP bars.

### D-T071-4 - [CONTESTABLE] - Volley reading: start-to-start 45 ticks, balls 9 apart, remainder on the last volley (T-071).
D-064 says "volleys of at most 3 balls, 0.15 s apart, consecutive volleys separated by 0.75 s
(45 ticks)" but not measured from what to what. Implemented in the generic `volley_plan` /
`VolleyClock`: balls inside a volley 9 ticks apart (0.15 s - matches the documented "3 balls
over 0.30 s"), volleys start-to-start exactly 45 ticks apart (one full jump of cadence, so
"one jump per volley" stays the correct play; the gap between a volley's last ball and the
next volley's first is then 27 ticks), remainder on the LAST volley (D-064's own 3+1, 3+2,
3+3+1). A 7-ball burst fires at relative ticks 0, 9, 18, 45, 54, 63, 90.
CONTESTABLE - the last-ball-to-first reading (gaps of a full 45 between volleys) is equally
grammatical; the swap is one constant in VolleyClock.

### D-T071-5 - [CONTESTABLE] - SalvoClock: budget from the FIRST tracking tick, restart never resets, expires ON tick 360 (T-071).
D-064: one salvo (tracking including every restart after a broken lock, plus the descent)
lasts at most 360 ticks "from its first tracking tick". Implemented as the generic
`SalvoClock` the Wave-3 launcher behavior keeps in its row: `start()` only initializes when
not already active (a restart keeps the budget), `tick()` returns false from the 360th tick
on and sets `expired`, and expiry is harmless - the caller stops tracking and descending
and starts its own 5.0 s pause. CONTESTABLE - "expires by tick 360" could read as "may act
during tick 360"; the one-off difference is a single tick, the harness (T-075) will not
feel it, and "at most 360 ticks of tracking" reads as the tighter bound.

### D-T071-6 - [CONTESTABLE] - Projectiles report where and why they ended (T-071).
`_step_projectiles` now appends a `projectile_end` event {"cause": "solid"|"life"|"hit",
position, tick} for every dying projectile (T-027 removed them silently). No new blocking
code: a launch pad's tiles are tile slabs in the collision world, so the existing
point-in-column check already stops a descending missile on the pad slab [top-1, top] -
proven by test_ranged.gd (a missile over a 4 u pad ends at y in [3, 4], the same descent
over flat ground ends at y in [-1, 0]).
CONTESTABLE - no document names the event; the view needs the detonation point for the
explosion flash, and tests need to observe "detonates on the pad" without guessing
positions.
### D-T024-1 - Loading screen timing model and the testable clock (T-024).

DECISION (T-024): `app/loading_screen.gd` drives everything from an injected `advance(delta)`
step instead of `_process`/wall time. Tests step it in fixed increments; no test ever sleeps in
real time. The minimum display is a named constant `MIN_DISPLAY_SECONDS := 5.0` (DESIGN.md
section 2 [CANON] row "loading screen on initial load and on run start | >= 5.0 s" and section
14). Completion predicate: `elapsed >= MIN_DISPLAY_SECONDS and load_fraction() >= 1.0`. A load
that finishes faster than 5.0 s therefore completes on the first step at/after 5.0 s (a fast 1.0 s
load completes at exactly 5.0 s, to float accumulation error); a load slower than 5.0 s completes
at the load's own duration, with the real fraction shown the whole time. Progress displayed is
NEVER a fake fraction: the bar shows the real reported (or simulated) fraction; for a fast load it
simply pins at 1.0 during the hold.
WHY: the spec's "holds at 5s if load is faster, shows real progress if slower" is exactly this
predicate, and a stepped clock is the only way a headless test can assert "exactly at least 5.0 s"
and "a simulated 7 s load takes 7 s" without a 12 s sleep in the gate.

### D-T024-2 - Simulated load duration vs real loader progress (T-024).

DECISION (T-024): the screen accepts a simulated load duration at start (`start(seed, simulated_load_seconds)`;
using -1 to disable) which yields fraction = clamp(elapsed / duration, 0, 1), and an external
`set_load_progress(p)` for the real boot path (initial load / run start) to report the actual
fraction from the loader. The first `set_load_progress` call permanently switches the fraction
source to the reported value (the simulated estimate is only a floor model, never overriding a
real report). The ticket's "simulated 7 s load" test uses the simulated duration only.
WHY: at the moment the screen is created the real total cost of asset/level loading is unknown;
pretending a fraction is known would violate the spec's "real progress" clause. The override rule
(never let the estimate beat a real report) is what keeps the honest reading honest when both are
available. The real caller wiring is out of scope here (no boot scene exists yet).

### D-T024-3 - Tip rotation: every 5 s, seeded weighted draw, hazard_tell x3 (T-024).

DECISION (T-024): tips come from `data/tips.json` (18 tips, 11 tagged hazard_tell, written by
T-014c; unchanged). The draw pool is an expanded index array with each hazard_tell tip present
HAZARD_TELL_WEIGHT := 3 times and every other tip present once (40 entries). The rotation is a
seeded shuffle of that pool (RandomNumberGenerator with the run seed), cycled; when the cycle is
exhausted the pool is reshuffled with the same stream and cycled again - so no cycle repeats the
previous one's order and long loads never run dry. The visible tip changes exactly at multiples of
5.0 s of elapsed display time: tip_step = floor(elapsed / 5.0). A 5.0 s fast-loading screen shows
exactly one tip. hazard_tell tips therefore appear at ~3x the rate of the other 7 tips, which is
"prioritizing gift-vs-hazard tells" without editing the data file.
WHY: DESIGN.md section 14 ("tips tagged hazard_tell are weighted x3, rotating every 5 s") and the
owner spec ("rotating, data-driven tip pool (15+ tips, prioritizing gift-vs-hazard tells)"). The
weights live in the draw, not in the JSON, so T-014c's data contract is untouched.

### D-T024-4 - [CONTESTABLE] - The About disclaimer is the ENEMIES.md paragraph VERBATIM; README keeps both wordings (T-024).

DECISION (T-024): DESIGN.md section 14 states its own verbatim line ("VOIDWRAP RUN is a personal,
non-commercial project — no money is involved, and ..."); ENEMIES.md's hard rule states a different
verbatim paragraph ("this is a personal, non-commercial project with no money involved. It is not
affiliated with, endorsed by, or connected to any person, brand, character, or IP referenced or
depicted in the game."). The T-024 ticket and the orchestrator's addendum both name ENEMIES.md:
"About text = the disclaimer verbatim" and "The About text must be the disclaimer VERBATIM". The
About screen (game/app/menu.gd) therefore carries the ENEMIES.md paragraph exactly, and
tests/test_disclaimer.gd pins that exact byte string. README.md carried ONLY the DESIGN.md section
14 wording (verified by findstr: line 8, count 1 - the orchestrator's note that "README.md already
carries it" is true for the DESIGN.md wording, false for the ENEMIES.md one). Rather than remove or
rewrite the T-001-verified line, README.md now carries the ENEMIES.md paragraph verbatim as an
additional line; both wordings coexist until the owner rules. PARKED.md row 2 records the conflict.
CONTESTABLE - if the owner rules DESIGN.md section 14's wording canonical, the fix is one constant
in menu.gd, one line in README.md and one string constant in test_disclaimer.gd.
WHY: the ticket is explicit, ENEMIES.md marks its paragraph "required in README + about screen",
and deleting or rewriting verified prior work to reconcile two documents the ticket never asked me
to reconcile is not mine to do.

### D-T024-5 - [CONTESTABLE] - Rotation boundary and first tip are not specified anywhere (T-024).

DECISION (T-024): no document states (a) the tip shown before the first 5.0 s elapses, (b) whether
the rotation boundary is aligned to screen entry or to first frame, or (c) whether the first tip is
random. Built: tip_step = floor(elapsed / 5.0) with elapsed counted from screen entry (not from
first painted frame), and the sequence is a seeded shuffle - the first tip is the first entry of
the shuffled weighted pool, not tips.json order. A fast 5.0 s load shows exactly one tip, index 0
of the shuffled pool.
CONTESTABLE - the owner may want the first tip to always be a hazard_tell tell, or the rotation
aligned to first paint; the change is one line either way.
WHY: any choice unmentioned in every document is contestable by definition; floor(elapsed / 5.0) is
the literal reading of "rotating every 5 s".

### D-T024-6 - test_disclaimer.gd pins both locations; the gate proves it by failing on edit (T-024).

DECISION (T-024): tests/test_disclaimer.gd asserts the ENEMIES.md verbatim paragraph appears in
(a) the About text produced by app/menu.gd (`about_text()` / the ABOUT_DISCLAIMER constant the
About panel renders) and (b) README.md at the repository root, resolved relative to
`res://` (res:// is game/, so `ProjectSettings.globalize_path("res://") + "../README.md"`). The
string is a constant in the test itself, so editing either location away fails the test; the test
never reads the menu source with a regex, it calls the same function the panel uses.
WHY: A15 (FLEET_PACK.md T-024) is "the disclaimer appears verbatim" - a pinned constant is the
only reading that "must fail if either is edited away".

### D-T025-1 - [CONTESTABLE] - HUD layout: positions, sizes, and the purse format (T-025).
DECISION (T-025): DESIGN.md section 14 lists the HUD elements but gives no positions or
pixel sizes; research/fable-tickets.md section 2.4 states only the pip row (bottom-left,
24 px from each edge, 28 px diamonds) - that spec is followed verbatim. Everything else
no document states, invented here and overrulable freely: the 24 px edge margin is used
uniformly; the gift counter is bottom-centre (220x40, section 14's "bottom-centre"); the
purse + chain is top-right (260x36, "top-right"); the icon rows are top-centre (40 px
cells, 6 px gaps, collapsible with Tab); the enemy roster is top-left (40 px cells); the
class ability cooldown sits bottom-left right of the Last Light icon (D-T025-3); the void
pip row width is 2 * 40 + 16 + 28 px plus margins. The purse renders as
"%d.%02d  %.2fx" on integer centi-gold (floor semantics, matching data/economy.json
gold_arithmetic and section 3.2's worked example "149.00  1.50x"). The void swatch on the
run-over screen is Color(0.35, 0.2, 0.5) - no document states the void colour for that
screen.
WHY: the ticket demands exactly the section-14 element set; placement has to come from
somewhere and section 2.4 covers only the pips.

### D-T025-2 - [CONTESTABLE] - The gift counter is phase-scoped; at beacon open it reads "0 / REAL total" (T-025).
DECISION (T-025): the counter's collected = total_real - remaining() for the CURRENT
phase, i.e. it reads the sim's phase-scoped remaining() (sim/gifts.gd) - gold gifts are
counted separately from black gifts, and the denominator is always total_real (mines are
never counted, section 3.3). At beacon open the counter therefore reads "0 / N" for the
gold phase and rises back to "N / N" when every gold gift is collected. An alternative
reading (black progress carries into the gold phase) is possible; nothing states it.
WHY: the straggler rule and remaining() are both phase-scoped in the sim; scoping the
counter the same way keeps one source of truth and no second bitset.

### D-T025-3 - Class ability cooldown: sources and the Athletic's hidden element (T-025).
DECISION (T-025): the ability element reads the controller directly. Dasher: dash_cd
remaining over dash_regen (3.0 s, DESIGN.md section 4), "READY" at 0. Glider:
glide_energy remaining over C["glide_energy"] (3.0 s, refilled on landing) shown as the
same fraction + seconds read-out. Athletic has no active ability (section 4), so the
element hides itself rather than show a dead widget. Position (bottom-left, right of the
pip cluster) is unstated anywhere (D-T025-1).
WHY: each class's "cooldown" is a different resource; inventing a unified "ability cooldown
stat" would contradict the kits section.

### D-T025-4 - HUD icons are synthesized in code until real art exists (T-025).
DECISION (T-025): curse, upgrade and enemy-roster icons are icon_placeholder.gd - a
deterministic hash-hue square with the item's id initials (and a stack-count badge over
1). No curse/upgrade/enemy icon assets exist anywhere in the repo. Icon hue is stable
per id (id.hash()), never index-dependent.
WHY: the TBD fallback rule - a missing asset never stalls the build; the behavior (rows,
bubbles, roster counts) is fully wired. TBD.md row added (section 3).

### D-T025-5 - The Last Light icon is part of the HUD element set, in the pip element (T-025).
DECISION (T-025): DESIGN.md section 3.1 binds a HUD icon for Last Light ("lit while armed
(unspent and charges >= 1), dim at 0 charges, grey once spent") and research/
fable-tickets.md section 2.4 places it right of the pips (28 px, same three states - the
three binding states are implemented verbatim). Section 14's list does not name it, so the
"exactly the elements listed in section 14" instruction is read with section 3.1's mandate
included: the icon lives inside the pip element (void_pips.gd), not as a separate widget.
The alternative reading (omit Last Light entirely, section 14 exhaustive) would void a
binding section-3.1 sentence and is rejected. hud_last_light() on the controller feeds it.
WHY: two sections of the same document cannot both be honoured except this way.

### D-T025-6 - Death attribution reads the sim events; sim/death.gd is absent (T-021 in parallel) (T-025).
DECISION (T-025): sim/death.gd does not exist on this branch (T-021 unmerged); the killer
and the death code are read from the controller's death event ({"e":"death","code",
"killer"}) and/or the controller's dead_code/dead_killer fields. enemy_runtime.kill()
derives code from the killer id (D-T027-5). Killer-name resolution order: (1) the
sim-provided killer string, normalised (lowercase, "?!"/"!" stripped, spaces ->
underscores) and looked up in a raw-id -> roster-name table (e.g. "gift_larper" ->
"gift Larper (Tripmine)"); (2) that string verbatim; (3) a death-code map (D-KIWI..D-VOID,
D-CURSE:<id>); (4) the code itself. Curse deaths show "curse: <id>" as the name line and
D-CURSE:<id> as the code; D-VOID shows "The Void" with no sprite (the void swatch hex is
D-T025-1's invention). When sim/death.gd lands, swap the source to it; the resolution
order stays.
WHY: the owner's spec sentence is absolute - "every death shows its killer" - and the
event carries exactly that.

### D-T025-7 - The diegetic danger text is an in-world billboarded Label3D; the spawn-line table comes from research/fable-tickets.md (T-025).
DECISION (T-025): section 14's line ("THE <ENEMY> SHALL <VERB>, #FF2A2A ... floats at each
enemy's spawn point for 4 s when it appears") is implemented as danger_text.gd: a Node3D
raising a billboarded, fog-exempt, no-depth-test Label3D 2.0 u above the spawn point,
modulate #FF2A2A, alive 4.0 s, fed by the enemy_spawn event (sim/enemy_runtime.gd). The
per-enemy line is the only table stated anywhere - research/fable-tickets.md's T-027
spawn-line row ("THE KIWI CAT SHALL FOLLOW", "THE COIL SHALL SPRING", "THICC BEN SHALL
TOLL", "ISAGI SHALL SHOOT", "THE NUKE SHALL SEEK", "YOU SHALL ECHO", "THE GIFT LARPER
SHALL PRETEND", "THE TOUCHER SHALL TOUCH", "THE SEAL SHALL BARK", "THE ELEPHANT SHALL BE
ADDRESSED", "CLAUDE SHALL COMPOSE", "GIN SHALL SEVER"); an unknown id shows TBD SHALL
ARRIVE (the documented TBD line), never a guess. This element and billboard.gd's
spawn_text (D-T027-7: the enemy's own display name, 1.5 s) both fire on the same
enemy_spawn event - two in-world texts, two specs; deleting either is the owner's call.
WHY: the owner's spec names the verb form and the red; the spawn-line row is the only
stated per-enemy text. Both are carried over from the old build's look per section 14.
### D-T021-1 - The mine's point of record is the slot's tile centre; the blast measures from the box point (T-021)
The mine set is EXACTLY the Level.gifts slots with occ == 1 (the owner's HAZARD
SPAWN RULE: hazards that replace gifts inherit validated gift spawn positions -
never their own placement logic). The mine's CONTACT point is the slot's tile
centre (x + 0.5, z + 0.5); the BOX point lifts that centre to TERRAIN_SPEC
6.7's occupancy height (y*0.5 + 1.0) - the point the view renders and the blast
measures from. Reference pattern follows D-T020-1: consumers read Level.gifts
directly or call sim/gifts.gd slot_pos(); no second placement source exists.
WHY: contact is horizontal by spec (D-058) so the x/z centre is the only number
the trigger needs; the box point keeps ONE occupancy-height formula in play.

### D-T021-2 - No collision prop is added: the 0.9 u trigger cylinder IS the wall (T-021)
"A tripmine is a wall on its tile" is implemented as the contact test itself,
not as a solid prop in sim/collision.gd: entering the 0.9 u cylinder at any
height triggers the ladder, so walking into the tile is never survivable and
the walkable bypass (generator guarantee, D-026 / TERRAIN_SPEC 6.8.2-6.8.4,
validator H23) stays the only way past. A solid prop would instead let the
player stand ON the box (step-up 0.5 u) beyond the cylinder's purpose, and
would need its own height band the spec never gives.
WHY: the spec gives no collision shape for the box, only the trigger cylinder;
adding an unstated prop would create a second, conflicting wall.

### D-T021-3 - The mine state joins the replay hash as one MINES line (T-021)
sim/mines.gd holds one PackedByteArray bitset by slot id (consumed by defuse /
shield / Last Light / detonation). state_hash.gd gains "MINES <consumed hex>"
after the BEACON line (the D-T020-5 pattern; the dump header documents the
line). It changes no previously hashed field, so test_replay.gd stays
self-consistent, and desynced-client coverage now includes a consumed mine.
The mine SET itself is not hashed: it is a pure function of the Level object
(the occ fields) and enters through LEVELHASH.

### D-T021-4 - The blast hits every player in radius; victims never re-roll the defuse (T-021)
When the ladder reaches step 4 (death), the detonating mine kills every OTHER
player whose centre is within 3 u of the box point; each victim runs shield ->
Last Light -> death. The defuse roll is fixed per (run_seed, level, slot_id,
stacks) (D-051) and is consulted exactly once, by the contacting player: a
blast only exists because that roll failed, so victims cannot re-roll it.
[CONTESTABLE] the blast is a 3 u SPHERE about the box point; no document says
horizontal vs 3D for the blast radius (contact being horizontal is the spec).
One scene consequence: in multiplayer, standing near a mine that someone else
triggers is the same hazard as touching it, so the bypass discipline of D-058
applies to spectators too.

### D-T021-5 - An invulnerable player neither triggers the ladder nor consumes the mine (T-021)
DESIGN.md 3.1: "tripmines and the nuke do not kill during [respawn
invulnerability]". Implementation: while respawn invulnerability or Last Light
invulnerability holds (or the respawn delay runs), the mine tick skips the
player completely - the mine stays armed and consumes nothing. A mine walked
through during a save window detonates later, when the window ends.
WHY: consuming a mine a player "passed through" unhurt would silently change
the level's mine count (and the A6 invariants) without any blast; skipping the
ladder keeps the mine an ongoing threat, which is the sentence's intent.

### D-T021-6 - View tells: 1 rev / 4 s turn, constant pink particles, rim glow beyond 12 u (T-021; [CONTESTABLE] on the turn rate)
The view (game/view/tripmine_view.gd) renders the T-015 tripmine_box model
(black frame, six-pointed star - D-T015-2) rotating one full revolution per
4.0 s, the section 3.3 cycle ("5-frame rotation cycle, 1 rev / 4 s"); the
sprite pipeline's fps 10 default in sprites.json is a build default, not the
in-game playback rate, so the view owns 4.0 s/rev. The pink tell (#FF4FD8
particles, palette role tripmine_particles) is a small constant emitter; beyond
TELL_DISTANCE (12 u) the box wears the same additive rim overlay as a black
gift (emission x1.5, TERRAIN_SPEC 12.2) and the emitter is off; inside 12 u the
particles and star show. Boundary read as inclusive (<= 12 u shows the tell).
[CONTESTABLE] no document states whether "1 rev / 4 s" or the sprites.json fps
10 wins for the 5-frame cycle; the view picks DESIGN.md section 3.3 (CANON).
### D-T023-1 - The enemy gate numbers live in the schedule file until enemy.json (T-023).

DECISION (T-023): `sim/offers.gd enemy_gate()` reads min_level / max_votes from
`content/enemies/<id>/enemy.json` when the file exists (DESIGN.md section 12 extensions contract),
and falls back per id to a table inside `data/offering_schedule.json` ("enemies": the DESIGN.md
section 5 CANON numbers, no number invented) for the 11 enemy folders that have no enemy.json yet
(T-030..T-041 own those files; the registry already skips them with a warning). The starter pool
(kiwi cat, coil, thicc ben, seal - DESIGN.md section 5, verbatim) is the schedule file's
"starter_pool" key. No content id is named anywhere in sim/ or core/ (test_boundaries).

### D-T023-2 - [CONTESTABLE] the E draw gates on the NEXT level (T-023).

DECISION (T-023): an E bay's candidates read min_level against `level_completed + 1`, not the
level just completed. WHY: min_level is the level the voted enemy will APPEAR in (the pre-run
lobby votes for level 1; the pre-run E bay must offer the starter pool, and all starters have
min_level 1). Under the "level just completed" reading the pre-run pool is empty and every pre-run
lobby falls into Hunger - obviously not the owner's intent. CONTESTABLE: no document states which
level the gate reads; a stricter reading (vote only when the enemy could spawn in the level just
played) is possible but only changes Isagi/nuke/toucher/Claude/gin availability by exactly one
intermission. test_lobby covers the pre-run starter draw.

### D-T023-3 - [CONTESTABLE] the CLASS bay is mandatory in the pre-run lobby (T-023).

DECISION (T-023): `gate_open()` requires `class_chosen != ""`. WHY: no run can start without a
class (T-026's bot passes `--class`; the HUD and kit hooks read the class), and the pre-run lobby
is the only CLASS bay - if the gate opened with CLASS unresolved the player could start a run with
no class at all. CONTESTABLE: DESIGN.md section 11 says only "Scheduled bays are lit"; "mandatory"
is stated for E ("mandatory, pick 1 of 3") and C in section 6, not for CLASS. The gameplay reason:
un-gated CLASS is unreachable state - an empty kit code path nothing else guards.

### D-T023-4 - [CONTESTABLE] curse gating and bounty use the level just completed (T-023).

DECISION (T-023): `draw_curse_bay` gates eligible_curses and prices the bounty at
`level_completed` (the level JUST finished; the schedule key is exactly that level). WHY: the
schedule file keys rows by the level completed, so "after level 2 -> C" reads the gates at the
same number the schedule used to light the bay; the first C (after level 2) then sees min_level<=2
curses. CONTESTABLE: the bounty scale "x (1 + level/20)" is written per the pick moment and the
constructive reading "next level" differs by at most 24 -> 26 gold on Harsh; no acceptance
criterion pins either.

### D-T023-5 - [CONTESTABLE] the REST bay carries a paid reroll plinth (T-023).

DECISION (T-023): REST bays receive the same paid reroll plinth as U bays (15 g + 15 g per use
that visit, economy.json). WHY: a REST bay IS a shop ("shop at -20%, no vote, no curse"); the
reroll plinth is priced off the same economy keys in both. CONTESTABLE: DESIGN.md section 11 lists
"reroll plinth (C: free once; U: 15 g rising)" and does not name REST; omitting it would make the
-20% shop strictly worse than the U shop in a way no document demands. The altars, prices and the
discount are unaffected either way.

### D-T023-6 - T-074's attachment point in this code (T-023).

NOT BUILT here, by the T-023 ticket's own instruction: DESIGN.md section 6's D-074 rule (one NEW /
one REPEAT / one FREE altar per E bay, per-enemy caps, the chaser ceiling of 6 floating bodies).
T-023 builds the simple draw the D-074 text explicitly supersedes ("3 distinct enemies from the
eligible pool") and leaves the hook clean: T-074 replaces ONLY
`sim/offers.gd enemy_candidates()` + `draw_enemy_bay()` (the pool read and the altar shapes live
there; `sim/intermission.gd _redraw_enemy()` already re-calls it per vote of an E x2 bay, and the
view rebuilds on every stamp bump - a NEW/REPEAT/FREE altar only needs new "kind" entries in the
returned altars, and intermission's `_select_enemy` needs a branch per new kind). The chaser
ceiling is a candidate-pool filter and lands inside `enemy_candidates()`. Tests to extend:
test_schedule (no change expected), test_lobby `_hunger` (the exhaustion path must survive the
cap checks) and a NEW/REPEAT/FREE triplet test.

### D-T086-1 - [CONTESTABLE] The HUD animation clock is ticks at 60 per second; advance() takes ticks (T-086).
DECISION (T-086): all new stepped HUD animations (spend / restore / free-fall / pulse /
glint / shatter / void flash / white bloom / black-out) are driven by an injected
advance(ticks: float) step, modelled on T-024's loading screen (D-T024-1) but in TICKS,
not seconds, because fable-tickets.md section 2.4 states every duration in ticks. The tick
rate 60/s is derived, not printed anywhere: DESIGN.md section 3.1 binds 48 ticks = 0.8 s
(void-fall respawn delay, D-050) and 1.0 s = 60 ticks follows. Each animated element owns a
_process(delta) that feeds advance(delta * 60.0); tests call advance() directly and never
sleep real time. advance() in void_pips.gd and screen_fx.gd therefore has a different unit
from loading_screen.gd's advance(seconds) - deliberate, and documented in both files.
WHY: the spec table's durations are tick counts; converting to seconds would invent a
second set of numbers and lose the 18/24/60/12-tick exactness.

### D-T086-2 - [CONTESTABLE] The spend's void edge flash is a 12-tick single flash, 48 px edge band, alpha 0.55 -> 0 (T-086).
DECISION (T-086): section 2.4 binds "the screen edge flashes void colour once" with no
duration, band width or peak alpha. Implemented as one flash of the void swatch (D-T025-1's
Color(0.35, 0.2, 0.5) - no document states the void-colour hex for screen effects) on a
48 px border band (the centre stays clear), alpha starting at 0.55 and fading linearly to 0
over 12 ticks, triggered exactly once per spend (pip_spend()). 12 ticks chosen to match the
Last Light bloom's 12 ticks; nothing else pins it.
WHY: the owner's sentence is absolute about ONE flash; the shape/duration is invented here
and overrulable freely.

### D-T086-3 - [CONTESTABLE] Already-full restore = one whole-row glow pulse over 12 ticks (T-086).
DECISION (T-086): section 2.4 binds "if already full, the pips pulse once" with no duration
or shape. Implemented as a single sinusoidal glow bump over the filled pips across 12 ticks
(peak at mid-pulse); the pip fill state never changes and no sound is implied. pulse_active()
reports the window so tests can step it.
WHY: "pulse once" is the whole spec; the 12-tick length reused from D-T086-2 keeps one
invented constant in play.

### D-T086-4 - [CONTESTABLE] Field Dressing pip: stays filled, white flash for the first 12 of 60 FREE ticks (T-086).
DECISION (T-086): section 2.4 binds (a) the pip flashes white and stays filled and (b) a
small "FREE" tick appears for 60 ticks. The 60 ticks / white flash / stays-filled parts are
the spec; the flash LENGTH is not stated, so the pip renders white for the first 12 ticks of
the 60-tick FREE window, then the normal held colour. The "FREE" text is drawn small
(11 px) centred under the animating pip. Which pip: the last held one (index held-1) - the
pip a spent charge would have drained; nothing is spent, so no state changes.
NOTE: the animation is view-side only for now (D-T086-8).
WHY: both spec sentences are honoured verbatim; only the flash length is invented.

### D-T086-5 - [CONTESTABLE] The restore glint is a white surface line plus a 6-tick glow tail (T-086).
DECISION (T-086): section 2.4 binds "fills upward over 24 ticks with a white glint" with no
glint form. Implemented: the fill rises from the bottom over 24 ticks (binding); a 3 px
bright-white bar rides the rising surface; when the fill lands, a 6-tick white glow lingers
above the pip then clears. The fill direction (bottom-up) follows "fills upward" literally;
the pip being animated is the one at index held at call time (the first hollow pip - after
the caller syncs the increment, the same pip reads as the last filled one). Call
pip_restore() on the beacon_enter event BEFORE the next sync (documented in the file);
pip_restore() self-corrects to the pulse case (D-T086-3) when no hollow pip exists at call
time, so one call site handles both spec branches.
WHY: "white glint" has to look like something and be testable; a surface line is the
simplest reading of a glint on a rising fill.

### D-T086-6 - [CONTESTABLE] Last Light shatter = 12 ticks, six wedge shards, concurrent with the 12-tick bloom (T-086).
DECISION (T-086): section 2.4 binds (a) a full-screen white bloom for 12 ticks (binding) and
(b) "the icon shatters" with no geometry or duration. Implemented: white_bloom() draws a
full-screen white rect with a 2-tick ramp in and a 10-tick fade out (12 ticks total,
binding), and last_light_trigger() starts a 12-tick shatter on the pip element's Last Light
icon - the icon splits into 6 wedge shards flying radially outward, rotating, alpha fading
to 0. After the shatter completes the normal state-driven icon draws (the caller will have
synced "grey" by then via controller.hud_last_light()). "The player appears on the dais" is
sim-side and already built (controller.try_kill teleports to the dais, D-053/D-073) - not a
HUD concern.
WHY: the shard count and motion are invented; locking the shatter to the bloom's 12 ticks
means the icon is gone exactly when the white clears - one invented clock, not two.

### D-T086-7 - The death black-out is a linear 18-tick fade on the topmost HUD layer; run-over shows on blackout_finished (T-086).
DECISION (T-086): section 2.4 binds "black-out over 18 ticks -> the run-over screen" within
2.0 s of death (binding). screen_fx.black_out() fades a full-screen rect to opaque black
LINEARLY over 18 ticks (0.3 s at 60 tps - comfortably inside the 2.0 s binding) and emits
blackout_finished once; the screen STAYS black until hide_blackout() is called (the run-over
screen is itself opaque black, so the swap is seamless). screen_fx.gd is the single overlay
for all three screen-wide effects (D-T086-2 flash, D-T086-6 bloom, this black-out) and draws
topmost (added last in hud.gd). The void colour reuses D-T025-1's swatch. WIRING: like T-025
left run_over.show_run_over() uncalled (the app-layer death wiring is not built), hud.gd
exposes hud.screen_fx and re-emits blackout_finished; the caller shows run_over on that
signal. 18 ticks of black + one show_run_over() call lands the whole attribution sequence
far inside the 2.0 s binding.
WHY: one overlay node for all full-screen effects keeps hud.gd a layout root, not an
animation suite.

### D-T086-8 - Field Dressing is NOT sim-wired; the free-fall animation is built view-side and parked (T-086).
DECISION (T-086): game/content/upgrades/field_dressing.json declares the on_void_fall hook
and core/hooks.gd lists it, but NO sim code path calls it - controller._void_fall() always
spends a charge when charges >= 1. The HUD therefore exposes pip_free_fall() (D-T086-4) and
it is fully tested headlessly, but nothing calls it yet: the wiring waits for the sim's
Field Dressing implementation (PARKED.md row 3). Same for the killer attack-frame sprite at
256 px: no enemy has an attack frame (gift_larper ships only a "cycle" animation, all
"tbd": true); run_over.gd keeps the TBD "?" box (D-T025-6, TBD.md rows 1-17). The curse-death
icon lands as an icon_placeholder.gd synthesized stand-in (D-T025-4, TBD.md row 21 extended
in spirit) - the spec's "curse icon" is honoured with the same fallback art the rest of the
HUD uses. The Last Light dais teleport and the 2.0 s death budget are NOT gaps (sim-built,
see D-T086-6/D-T086-7).
WHY: do not fake what does not exist; build what is buildable and park the rest in writing.
### D-T074-1 - [CONTESTABLE] "first-shown level" = the gate table's min_level (T-074).

DECISION (T-074): the NEW altar's "lowest first-shown level first" sorts on the enemy gate's
`min_level` (enemy.json once T-073 lands it, else the schedule file's enemy table). No document
defines a separate first-shown field, and research/fable-enemies.md section 1 says first-shown
"= the level whose intermission should first be able to offer it" - which is exactly what the gate's
min_level means under D-T023-2 (the draw gates on the NEXT level). CONTESTABLE: when T-073 writes
enemy.json it could split "first shown" from "min spawn level"; if it does, the sort key in
draw_enemy_bay must follow the new field.

### D-T074-2 - [CONTESTABLE] the chaser-ceiling numbers live in the schedule file's "chaser" block (T-074).

DECISION (T-074): `data/offering_schedule.json` gains a "chaser" block: `"ceiling": 6` (D-074, FINAL -
not editable here), the per-id body weights (kiwi_cat / you / toucher / seal, each 1.0 - D-074 names
exactly these four as "floating lethal bodies"), `"kitten_host": "kiwi_cat"`, `"kitten_curse":
"litter"` and `"kitten_weight": 0.5` (D-074: "The Litter's kittens count as half each"). WHY: the
sim may name no content id (test_boundaries), the schedule file is already the enemy-gate data home
(D-T023-1), and the ceiling/weights are offer-draw numbers, i.e. intermission rhythm - the same one
tunable file. CONTESTABLE: T-073 could move the weights into enemy.json (`chaser_weight` field);
sim/offers.gd reads the schedule block and would follow a field-parity rule then.

### D-T074-3 - [CONTESTABLE] kitten bodies at draw time (T-074).

DECISION (T-074): with the kitten curse held, each host vote carried so far adds 0.5 bodies to the
ceiling load, and voting one more host cat adds 1 + 0.5 (its own kitten is born the instant the vote
is placed - The Litter's rule says "each cat is followed by a kitten", so a newly voted cat arrives
with its kitten already in play). Headroom check per altar: current load + the pick's weight under
the held curses <= ceiling. CONTESTABLE: one could instead count a kitten only once "revealed"
mid-level, or treat lava kittens as spawning only on the NEXT level for the very last cat; no page
says. The chosen reading is the conservative one (the kitten exists from spawn tick 0).

### D-T074-4 - [CONTESTABLE] the FREE altar may re-show the type picked at the previous vote (T-074).

DECISION (T-074): D-074 binds ONLY the REPEAT altar ("never the type picked at the previous vote");
the FREE altar's pool is "everything eligible and not already shown" - "shown" = already on this
bay's other altars. So the previous vote's type stays reachable through FREE whenever it is below
its cap, which is exactly the path the canon stacking right ("select an enemy 5 times and there
will be 5 enemies in play") needs after the very first pick of that type. Within one bay the three
altars are still three DISTINCT types. CONTESTABLE: one could exclude the previous pick from FREE
too; that would make stacking strictly slower and no sentence demands it.

### D-T074-5 - [CONTESTABLE] altar slots NEW / REPEAT / FREE in that draw order; altars keep "kind": "enemy" (T-074).

DECISION (T-074): every enemy altar dict gains `"slot": "new" | "repeat" | "free"` and the bay lists
them in that order (the legible question reads left to right). "kind" stays "enemy" (or "hunger"),
so intermission's `_select_enemy` keeps its single enemy/hunger branch - D-T023-6 anticipated a
branch per new kind, but a plain field needs none, and the view keeps rendering by "kind". Also
threaded: `Intermission.create` gains an optional `p_prev_vote` (the type of the previous vote of
the RUN - cross-lobby state, carried by whoever mounts the run loop; E x2 bays need no special
treatment because the first pick's Select already sets it before the in-bay redraw, exactly the
E x2 clause of D-074). CONTESTABLE: display order is presentation, no page pins it.

### D-T074-6 - [CONTESTABLE] the 1,000-run walker's vote policy (T-074).

DECISION (T-074): the test walker that votes its way to level 30 picks the NEW altar whenever one
is on the bay, else draws a seeded uniform pick among the remaining offers. WHY: a uniformly random
voter keeps re-stacking repeats and can leave late-min-level types (Claude, gin) unoffered past the
level-19 vote simply because earlier types keep hogging the NEW altar - a ballot-stall artifact,
not a property of the offer system. The design's own legible question ("a new problem, or more of
one I already handle?") is answered by an engaged player exactly this way, and research section 3.3
front-loads learning on that player. CONTESTABLE: the measured uniform-random rate is reported in
the response file; if the owner prefers that reading, the threshold number is the [CONTESTABLE]
part, not the draw rule (D-074 FINAL).

### D-T072-1 - [CONTESTABLE] - "No enemy body within N u" reads as 3D distance (T-072).

DECISION (T-072): SR-4 says only "no enemy body is within 12 u of the player" and states
neither 3D nor XZ-only. The gate reads the 3D distance, body row origin to the player's
feet point (the same measure valid_safe_tile uses against the live body mirror, so one
distance convention backs both the spawn route and the scheduling route).
WHY: an XZ-only reading would let an enemy body hover exactly 12 u above the player's
feet and still pass the gate, opening the stop envoy straight into a chaser's lap - the
case SR-4 exists to prevent. [CONTESTABLE]: XZ-only is a one-line change in
meets_requirement if the owner rules it.

### D-T072-2 - The lock's per-class effect list is data: player.json ability_lock.lock_effect (T-072).

DECISION (T-072): the effect names (dash_disabled / glide_disabled /
class_multipliers_off) live in data/player.json's ability_lock block and reach the
controller through lock_effects(kit); the controller invents none of them. A missing or
empty read falls back to LOCK_EFFECT_FALLBACK - the full SR-6 reading, per class - so a
lock can never be a silent no-op, and a moved/renamed data file degrades to the spec's
behavior, not to nothing. data/player.json gains only that lock_effect mapping; every
existing key is untouched (the file stays T-014c's).
WHY: the ticket names the effect ids as the data boundary; a hard-coded dispatch in the
controller would let a data edit silently change which class ability a lock kills.

### D-T072-3 - An active glide ends at the call, before the next engage tick (T-072).

DECISION (T-072): lock_abilities (glide_disabled) sets glading=false inside the call -
"an active glide ends" lands at once; the engage gates already read ability_locked()
every tick, so nothing re-attaches while the window holds, and the D-070 sentence is
honoured the same tick an enemy applies the lock. glide_energy is not refunded: an
interrupted glide keeps what it burned.
WHY: waiting for the next engage tick would leave the glide's fall cap active for up to
one tick past the lock - the rider, already locked, would still sink at a capped fall
for a frame.

### D-T072-4 - Live countdowns read telegraph entries (ticks > 0) plus caller-side pending ids (T-072).

DECISION (T-072): busy_sources collects one id per live countdown - telegraph entries
whose ticks > 0 (one per source id), plus an optional `pending` id array the behavior
keeps on its own row and passes through api.arbiter_gate (a rumble that is not a
telegraph shape). The runtime never decrements a telegraph's ticks today, so entry
lifetime is the caller's: a behavior MUST drop its entry when the strike lands, or its
id stays busy forever. Recorded as the data pass's duty.
WHY: deriving deferral from telegraph entries alone keeps the ids data-side and the
arbiter stateless; the pending array covers every countdown source a future behavior
invents without a runtime schema change.

### D-T072-5 - [CONTESTABLE] - The gate evaluates the targeted player, index 0 today (T-072).

DECISION (T-072): the runtime's arbiter_evaluate(cfg, player_index = 0) passes
controllers[player_index] - in a single-player sim the only player there is. A row that
cuts its own target (a multi-player targeting pass) sets target_player on the row and
the Api forwards it; the gate stays stateless either way.
WHY: the section 12 contract says the enemy api carries the target, not the gate; no
document states a multi-player mapping. [CONTESTABLE] until the roster's targeting pass
lands.

### D-T083-1 - The anim block schema in sprites.json, and the TBD frame_map for the spec frame names (T-083).

DECISION (T-083): each enemy's content/enemies/<id>/sprites.json gains one "anim" block. It
carries: "section" (the fable-tickets.md 1.x table it implements), "frame_map" (spec frame name
-> the file that exists on disk, relative to the enemy folder), and "states" - one entry per
table row, keyed by a snake_case state id, each with: "row" (the exact table row label),
"spec_frames" (the section 1.x frame names, in table order), "frames" (the on-disk files, one
entry per spec frame, REPEATS ALLOWED for TBD placeholders), "loop", "total_ticks",
"ticks_per_frame", "tick_ranges" (state-local, inclusive [frame, first_tick, last_tick]), and
"effect" { "name", "params" }. Timings are 60 Hz ticks; the sim drives frame selection from
ticks_in_state (fable-tickets.md 1.0), never a wall clock. Effects never change body_rect.

WHY: every enemy's sources were missing at T-016, so every frame today is a TBD placeholder
("tbd": true) and the spec frame names (kiwicat_00, coil_00..04, isagi_idle_00/isagi_shoot_00/
isagi_ball_00, nuke_00..03, you_00..04, thiccben_00) do NOT exist on disk. The ticket's TBD
fallback applies: every state uses the TBD frame(s) and the timings stay exactly as the table
says. The mapping: coil_NN -> cycle_NN, nuke_NN -> cycle_NN, you_NN -> cycle_NN (1:1, the
pipeline's height progression matches squash->extend for coil); kiwicat_00 -> cycle_00,
thiccben_00 -> cycle_00 (single placeholders); isagi gets fire_00 for isagi_idle_00, fire_02
(the last frame of the fire strip, read as the most-extended shoot pose) for isagi_shoot_00,
and shot_00 for isagi_ball_00; fire_01 exists on disk but is unreferenced.
[CONTESTABLE]: the isagi assignment is a placeholder guess and so is the coil/you/nuke order
(both are just "the frames the pipeline made"); when real art lands, only frame_map and
"frames" change - spec_frames, loops, ranges and tick counts are the frozen spec.

### D-T083-2 - Tick conventions for the anim blocks (T-083).

DECISION (T-083): 60 Hz ticks throughout. fps <-> ticks_per_frame: 8 fps = 7.5 ticks per frame
(the table's "7-8 ticks per frame", alternating), 16 fps = 3.75, 12 fps = 5, 10 fps = 6,
20 fps = 3, 15 fps = 4, 6 fps = 10. Explicit tick_ranges are state-local and INCLUSIVE, and
appear only where the table gives explicit ranges (coil telegraph [0-11/12-23/24-35], coil
flight [0-20 / 21-144 / 145-164], isagi attack held [0-30 local]). total_ticks carries the
table's duration when the table bounds one (spawn 30, coil telegraph 36, ben telegraph 75,
isagi wind-up 72 / cooldown 150, nuke tracking 150 / locked 90 / descent 90 / explosion 24 /
recover 300, you telegraph 90 / recover 240, address-me-style 12/18/24 rows for the other
half), and null where the table bounds no duration. isagi's attack total_ticks 30 is DERIVED
from binding numbers (shown from tick 72, held until tick 102) - marked as derived in the
isagi block's effect note; tick_ranges are stored state-local (0 = global tick 72) and the
block also records release_ticks global [72, 81, 90] and local [0, 9, 18]. The attack frame
lands on the tick its kill resolves: telegraph animations fill their cues exactly and the
attack states are resolve-tick entries (see D-T083-3), so no invented hold exists.

### D-T083-3 - States whose frame lands on a resolve tick carry total_ticks: null (T-083).

DECISION (T-083): a state the table shows on exactly the tick a kill/resolution lands -
coil attack_landing (tick 165, the landing kill and the shockwave), thicc_ben attack_arrival
(tick 75, the lock resolves), you attack (tick 90, the ring starts expanding 9 u/s to 14 u),
isagi attack shows from tick 72 and is held until 102 (bounded, D-T083-2), and the kiwi/thicc
ben attack rows (contact kills on the overlap tick) - carries total_ticks: null and a note
naming the tick, rather than an invented hold duration. WHY: a number no document states is a
SPEC GAP and must not be invented; the sim/view wiring shows the attack frame on the tick the
attack resolves and leaves it until the behavior leaves the state. [CONTESTABLE] only in that
the owner may prefer an explicit one-tick "resolve frame" encoding; the note already carries
the tick, so such a change is a data edit, not a redesign.

### D-T083-4 - game/tools/check_anim_data.gd (it did not exist) - what it proves and how (T-083).

DECISION (T-083): new headless tool. Usage: godot --headless --path game --script
res://tools/check_anim_data.gd -- [enemy_id ...]; no arguments = the whole roster. It
hardcodes BOTH halves' section 1.x tables (the binding numbers: frames in table order, loop
flags, ticks_per_frame / tick_ranges / total_ticks, repeat_every_ticks and fps where the
tables state them) and never reads the markdown, so a spec edit fails loudly here instead of
silently re-passing. For each enemy it proves: the JSON parses, the anim block exists with the
right section, every state of the table exists with the table's frames (by spec name, in
order), loop flag and tick counts, NO unexpected states (one entry per table row), every
referenced frame file exists on disk (one frames entry per spec frame, repeats allowed for TBD
placeholders), frame_map values exist when present, and every effect has a non-empty name and
a params dictionary. Output is one PASS/FAIL line per enemy plus a final
"ANIM-DATA <p> passed <f> failed"; exit code 1 iff any enemy fails (verified 1 on a bad id,
0 on a full pass). WHY hardcoding: the file is the enforcement of "the animation tables ARE
the spec" - parsing the markdown at check time would make the check as fragile as the prose it
guards. Cost: the table numbers live in two places (the markdown and this file); if either
changes, the same commit must update both.

### D-T083-5 - No contradictions against ENEMIES.md / DESIGN.md FINAL rows in sections 1.1-1.6; no PARKED.md rows (T-083).

DECISION (T-083): the six animation tables were cross-read against ENEMIES.md (behavior
sentences), DESIGN.md section 5.1-5.6 (cue timings) and the FINAL system rules (D-064 volley
and salvo limits, D-066 shockwave, D-070 ability lock). No contradiction was found in the six:
the telegraph fills each cue exactly and the attack frame lands on the resolution tick,
DESIGN.md's 0.6 s pre-jump + 2.75 s flight = 3.35 s of cue stands, DESIGN.md's 2.5 s track +
1.5 s locked stands, Isagi's 1.2 s wind-up + volley stands (D-064 volley structure is sim-side,
not anim data). The table's own [CONTESTABLE] rows (the common spawn fade: alpha 0->1 over
30 ticks, scale 0.8->1.0; kiwi's ±0.08 u 1.0 Hz bob) are carried as [CONTESTABLE] in the data,
not re-litigated. The Zoomies curse reading of the kiwi meow row (two pulses 12 ticks apart,
then a red outline for the 180-tick sprint) is encoded verbatim in the kiwi_cat telegraph's
effect params. No PARKED.md rows were added.

### D-T083-6 - check_anim_data.gd's other half is expected to fail until the other ticket lands (T-083).

DECISION (T-083): running the checker with no arguments today prints
"PASS" x6 for kiwi_cat, coil, thicc_ben, isagi, nuke, you and
"FAIL <id>: no 'anim' block (T-083) in sprites.json" x6 for gift_larper, toucher, seal,
address_me, claude, gin (ANIM-DATA 6 passed 6 failed, exit 1). That is a correct intermediate
state: the other half of T-083 is in flight on the same spec; the checker is its gate too.
Mine are done and green: ANIM-DATA 6 passed 0 failed, exit 0 (see the response file for the
full command output).
### D-T083-1 - Frame naming: anim blocks reference the T-016 file names, never the spec's names (T-083).

DECISION (T-083): research/fable-tickets.md section 1.0 pre-authorizes this ("if T-016 produced
different names, T-083 renames in `sprites.json`, never in this spec"). The anim blocks name the
files that exist on disk today: gift_larper `larper_00..04` -> `sprites/cycle_00..04.png`;
toucher `toucher_00..02` -> `sprites/cycle_00..02.png`, `glitchfloor_00..04` ->
`sprites/floor_00..04.png`; seal `seal_00` -> `sprites/idle_00.png`, `seal_01` + the `seal_02/03`
flap overlay -> `sprites/dash_00.png` / `sprites/dash_01.png` (no mouth-open frame exists);
address_me `addressme_00/01` -> `sprites/cycle_00/01.png`; claude `claude_00` ->
`sprites/idle_00.png`, `plushie_00..02` -> `sprites/idle_00..02.png` (stand-in); gin
`gin_idle_00`/`gin_launch_00` -> `sprites/idle_00.png` / `sprites/launch_00.png`. The spec's names
are unchanged (D-040). TBD.md carries one row per enemy.

### D-T083-2 - [CONTESTABLE] All art is TBD, so multi-frame spec sequences collapse onto the placeholder frames (T-083).

DECISION (T-083): where the TBD sheet produces ONE frame (seal `idle_00.png`, thicc_ben, kiwi_cat,
address_me normal), the state entry holds that single frame and keeps the table's tick counts
exactly (seal idle 9 ticks/frame, seal telegraph 45 ticks held, seal dash 4 ticks/frame); where the
sheet produces N frames (toucher 3, larper 5, claude 3, gin 1+1, address_me 2, seal dash 2), the
entries use them in spec order. WHY [CONTESTABLE]: section 1.0's "every state uses the TBD frame"
reads singular; the alternative reading renames placeholder files, which changes no pixels and
orphanes the `animations[]` block the pipeline emitted. The owner may rule frame renames when the
real art lands; the anim block then names the real files (section 1.0). Frame-count mismatches
vs the tables are inherent to the TBD placeholders and are logged in TBD.md, never papered over by
inventing frames.

### D-T083-3 - [CONTESTABLE] fps rows convert to ticks exactly (T-083).

DECISION (T-083): the tables state animation rates in fps and ticks; ticks win (section preamble).
fps -> ticks per frame is 60/fps: 20 fps -> 3, 10 fps -> 6, 8 fps -> 7.5, 12 fps -> 5, 16 fps ->
3.75, 6 fps -> 10. "7-8 ticks per frame" (YOU?!, 8 fps) is encoded 7.5; the other worker's anim
blocks should do the same (the checker enforces 7.5/3.75). WHY [CONTESTABLE]: an alternating 7/8
tick pattern would be marginally closer to the words, at the cost of an irregular period the sim's
fixed-rate tables do not otherwise use; 7.5 keeps the loop period regular (60 ticks per frame set).

### D-T083-4 - [CONTESTABLE] No invented numbers: unstated cells are null; VFX-only states are "frames": [] (T-083).

DECISION (T-083): every anim entry carries `ticks_per_frame` and `duration_ticks`; where the table
states no number for the cell, the value is `null` with the stated timing in `timing_note` (never an
invented figure). States the table draws with no frames (gift Larper detonation, toucher touch,
address_me recover, gin void zone, kiwi cat/nuke rows with "-", ...) carry `"frames": []` and
`duration_ticks` from the table where stated (18 / 600 / 300 / ...) or null. WHY [CONTESTABLE]: the
ticket demands "ticks per frame or explicit tick ranges" per entry; a strict null is the only
encoding that neither invents a number nor drops the cell. The checker skips null cells rather than
inventing (it FAILS only on numbers the table states).

### D-T083-5 - [CONTESTABLE] gin attack_launch: the launch frame is held for the 18-tick spear flight (T-083).

DECISION (T-083): the table says gin_launch_00 is "shown on tick 120; spears travel for 18 ticks
(0.3 s)" and is otherwise silent on how long the pose holds. The anim entry holds the launch frame
for the 18-tick flight (`duration_ticks: 18`, `ticks_per_frame: 18`); recover (loop, tiles fade back
over 30 ticks, cooldown 840 ticks) takes over at tick 138. WHY [CONTESTABLE]: one could hold the
launch pose into recover and split at the first idle re-entry; nothing states the pose's exit tick.
18 is the only number the table gives the attack.

### D-T083-6 - address_me telegraph loops a single held frame for the full 300 ticks; stillness arc stays "green" (T-083).

DECISION (T-083): the table's loop cell for the countdown is "loop" and there is no second frame for
the state, so the entry holds `cycle_00.png` looping for the 300-tick cue (`ticks_per_frame: 300`).
The ring drain, the tint neutral -> amber (tick 150) -> red (tick 240), the green stillness arc
(90 ticks = 1.5 s to fill, empties on the first motion input) and the rumble's 1 -> 6 Hz tremolo are
`effect_params` verbatim from the table and DESIGN.md section 5.10. The arc's colour is recorded as
the word "green" - no document states its hex, and no hex was invented.

### D-T083-7 - claude plushie_idle stands in with the TBD logo frames; 6 fps kept exactly (T-083).

DECISION (T-083): no plushie frames exist (the ENEMIES.md clawd Crab source was never fetched, TBD
fallback). `plushie_idle` loops `idle_00..02.png` - the only three-frame set the TBD sheet carries -
at the table's 6 fps = exactly 10 ticks per frame, with bob +-0.1 u, the soft white glow and
collected = pop 9 ticks as `effect_params`. TBD.md carries the row; the owner replaces it by fetching
the clawd Crab sprite and rebuilding the pipeline (the anim block then points at the real
plushie_00..02). The three logo frames doubling as plushie stand-ins is acknowledged as visibly
wrong on screen until replaced.

### D-T083-8 - check_anim_data.gd embeds the section 1.x tables 1:1 and is strict only on stated numbers (T-083).

DECISION (T-083): `game/tools/check_anim_data.gd` transcribes every section 1.x table (all 12
enemies, enemies 7-12 = this ticket, 1-6 = the sibling half) into an embedded SPEC. It enforces,
exactly, the cells the tables state: the state list, `loop` where stated, `ticks_per_frame` where
stated (fps converted exactly), `tick_ranges` (coil flight) exactly, `duration_ticks` where stated,
and existence on disk of every frame referenced by `frames`, by `tick_ranges[].frame`, or by any
`.png` string anywhere in `effect_params`. TBD sheets are existence-checked but relaxed on
names/frame-counts (section 1.0); non-TBD sheets additionally require at least as many distinct
referenced frames as the table lists. States not in the table are printed as NOTE, never failed;
enemy ids outside the 12 are a usage error (exit 2). Exit 0 iff every checked enemy passes; 1
otherwise. The tables win on any disagreement (D-040); the file is the transcription, not a second
spec.

### D-T083-9 - Anim state keys are snake_case of the table's row labels; the checker normalizes before matching (T-083).

DECISION (T-083): anim block keys are the table row labels snake_cased: `attack_detonation`,
`attack_flight`/`attack_landing` (coil), `attack_arrival`/`attack_ring` (thicc ben),
`telegraph_tracking`/`telegraph_locked` (nuke), `telegraph_drums`/`attack_drums`/
`telegraph_strings`/`attack_strings`/`attack_wind`/`deadline`/`plushie_idle` (claude),
`attack_launch`/`attack_void_zone` (gin), `attack_infect`/`attack_touch` (toucher), `leaves`
(address me), `defused` (gift Larper), and plain `spawn`/`idle`/`telegraph`/`attack`/`recover`
elsewhere. The checker normalizes both sides (lowercase, non-alphanumeric runs -> `_`, trailing `_`
stripped) so `attack_flight` and "Attack - Flight" are the same state. This naming is part of the
T-083 contract; tools that read anim blocks should expect it.

### D-T083-10 - toucher's glitched floor is a section 2.2 world decal, wired in effect_params, not a body state (T-083).

DECISION (T-083): the table's toucher states are body states only. The glitchfloor frames are a
tile-top decal: they are referenced from `attack_infect.effect_params.glitchfloor_frames`
(`floor_00..04.png`, 8 fps cycle, `(x + z) mod 5` per-tile frame offset, alpha 0 -> 1 over 12 ticks,
1-tile tear flash in danger red for 6 ticks, life 12 s / 18 s from level 14, last 60 ticks flicker at
10 Hz then fade over 12 ticks, 8 u ben-ring cleanse, squelch on the infection tick). The floor never
becomes a state in the body anim block, because the table defines none for it. The existing
`animations[].name == "floor"` pipeline block is untouched and still drives the decal.

### D-T083-11 - gift Larper's spawn is not the common fade (T-083).

DECISION (T-083): the table says the spawn state is "present from level start (it is a slot
occupant, no fade)". The entry therefore uses `spawn` (present from level start, `loop: false`,
no fade/scale parameters, `effect: "none"`) rather than the section 1.0 common fade the other
eleven use. The 30-tick contact-blocking rule does not apply: there is no fade to complete and a
tripmine is a stationary slot occupant, not a body that arrives. WHY: applying the common fade here
would show an invisible mine slot for 30 ticks that the table explicitly rules out. Arguable either
way; recorded as decided, not contested.

### D-T030-1 - sim/enemy_runtime honors cfg `death_code` (verbatim) on the contact-kill path (T-030).
DESIGN.md section 3.1 (FINAL) lists every enemy's death code: kiwi cat is `D-KIWI`. T-027's
`_contact_kills` derived the code from the display name (`"D-" + name.to_upper()`), which yields
`D-KIWI_CAT` for "kiwi cat" - a code DESIGN.md never lists. `Api.kill` / `rt.kill` now take an
optional explicit `code` parameter; `_contact_kills` passes `row["cfg"]["death_code"]` verbatim
when present (gift_larper's enemy.json already carried `stats.death_code: "D-MINE"` - the data
path existed, the runtime ignored it). No `death_code` in cfg: the derivation is unchanged
(T-027's fixtures, `D-TBD`, stay green). WHY: section 3.1's code list is FINAL and the
run-over screen maps codes through `sim/death.gd`'s closed map - a derived `D-KIWI_CAT` would
ever show the raw fallback instead of "kiwi cat".

### D-T030-2 - sim/enemy_runtime honors cfg `hit_diameter` on the body row (T-030).
DESIGN.md SR-2 (FINAL, D-065) pins kiwi cat's hit diameter at **0.9 u** (body height 1.0 u).
`cylinder_from_sheet` derives the diameter as 0.8 x body width from the PNG's `body_rect`; the
T-016 TBD placeholder sheet carries a square 224x224 body, which derives 0.8 u - not the FINAL
0.9. `_spawn_one` now reads an explicit cfg `hit_diameter` (world u) and, when present, uses it
verbatim for the row's `diameter_u` (the height stays `world_height`, the width stays the
derivation and remains informational). No `hit_diameter` in cfg: the derivation is unchanged.
WHY: SR-2 is FINAL and the placeholder art is explicitly interchangeable (D-T027-6) - the data
that carries the FINAL number must win over a derivation whose input art is a stand-in; the real
kiwicat.png may or may not re-derive the same 0.9.

### D-T030-3 - [CONTESTABLE] kiwi cat's meow rides the sim telegraph channel; the shape is a zero-radius circle (T-030).
ENEMIES.md ("cat meow when near player") + DESIGN.md section 5.1 ("Meows every 3 s while within
14 u") + the T-083 anim block (state "telegraph (meow)", 12 ticks, every 180 ticks (3.0 s,
binding) within 14 u, scale pulse 1.0 -> 1.12 -> 1.0) give the timings; no document states the
transport. Built: the behavior calls `api.telegraph("meow", {"shape": "circle", "cx": x, "cz": z,
"r": 0.0}, 12)` - a 12-tick cue the view renders as the scale pulse and the audio layer renders as
the 0.35 s meow. The radius-0 circle carries no targeted footprint (`point_in_shape` covers only
its own centre point), so SR-4's `no_targeted_telegraph` requirement for address me is unaffected;
this is deliberately NOT a damage telegraph (the cat's kill is the body contact, framework-checked).
CONTESTABLE: the owner may prefer a dedicated non-tac `meow` event channel instead of the telegraph
bus; the swap is one `api` call in the behavior plus the view/audio subscriptions. Zoomies' double
meow (two "meow_double" telegraphs 12 ticks apart) is driven by the Zoomies script curse (T-051),
not by this behavior.

### D-T030-4 - [CONTESTABLE] kiwi cat audio: cue names `meow` / `meow_double`, files under `assets/audio/enemies/kiwi_cat/`, placeholders until T-055 (T-030).
No document states an audio asset layout. enemy.json `stats.audio_cues = ["meow", "meow_double"]`
(cue names = file names, per the section 3 sound brief: cue `meow` 0.35 s every 180 ticks within
14 u; `meow_double` - two meows 12 ticks apart, pitched up a fourth). The view-side hook
(`game/view/audio/kiwi_cat_audio.gd`) loads `res://assets/audio/enemies/kiwi_cat/meow.wav` and
`res://assets/audio/enemies/kiwi_cat/meow_double.wav` and **no-ops silently while a file is
absent** - T-055 synthesises the placeholders (stdlib `wave`) and owns the files. TBD.md rows 28/29
record both as placeholders. CONTESTABLE: the owner may want a single generic `enemy_cue(name)`
hook instead of per-enemy scripts.

### D-T030-5 - [CONTESTABLE] the meow re-arms on range entry: the first tick back inside 14 u meows at once (T-030).
"Meows every 3 s while within 14 u" (DESIGN.md section 5.1) does not state the phase of the first
meow. Built: `row["meow_left"]` initialises to 0, so the first tick the cat is within 14 u of the
nearest player it meows, and re-initialises to 0 on leaving the radius - re-entering re-arms the
immediate meow; afterwards one meow every 180 ticks while the radius holds. WHY [gameplay reason]:
the meow IS ENEMIES.md's entire proximity tell ("cat meow when near player"); a 3 s silent grace
after crossing into 14 u would mute the tell exactly when the player first needs it, and
re-entering the radius without a meow would read as a new enemy. CONTESTABLE: the owner may prefer
the first meow one full period after entry.

### D-T030-6 - enemy.schema.json gains optional `behavior` / `counter_play` / `tell` top-level strings; test_content counts bumped (T-030).
`game/view/lobby/antechamber.gd` renders each enemy's altar panel from `sheet.get("behavior")`
and `sheet.get("counter_play")` (the curse schema already carries `rule`/`counter_play` top-level;
this mirrors it). The schema's `additionalProperties: false` would otherwise reject the panel
lines, so the three keys are added as optional strings - nothing else changed, and the registry
still refuses unknown keys and any id/folder mismatch. `test_content.gd`'s launch counts move
1 -> 2 enemies and 88 -> 89 content_ids (the check stays exact, not loosened; wave-3 tickets keep
it current in merge order). WHY: the lobby exhibit line is part of every T-030..T-041 ticket's
done-when, and it reads from these two keys.

### D-T030-7 - kiwi_cat_view.gd: the first enemy-specific view file; anim-block effects applied client-side from ticks (T-030).
`game/view/kiwi_cat_view.gd` (Node3D) owns the enemy's billboard (`game/view/billboard.gd`,
unchanged) and applies the T-083 anim-block effects itself, read from `sprites.json`'s `anim`
block (never hard-coded): spawn = 30-tick alpha 0 -> 1 fade with scale 0.8 -> 1.0; idle/chase =
bob +-0.08 u at 1.0 Hz; telegraph (meow) = scale pulse 1.0 -> 1.12 -> 1.0 across the 12-tick cue
(keyed off the 12-tick telegraph window the sim announced). View layer only; reads sim events,
never writes sim state (DESIGN.md section 13). The frame set is the T-016 TBD placeholder for the
real `kiwicat.png` (TBD.md row 1); swapping art changes no code here. WHY: the anim block is the
one source of effect timings (T-083) - duplicating them as view constants would drift.

### D-T030-8 - The hurdle window is asserted against the engine's tick-quantized arc, not the spec's continuous formula (T-030).
DESIGN.md section 5.1 and FLEET_PACK.md express the jump's clearing window as continuous physics
(y(t) = 12.0t - 16.0t^2 >= 1.5 u between 0.16 s and 0.59 s, apex 2.25 u, a 0.43 s window). The
controller (sim/controller.gd) integrates at 60 Hz with semi-implicit Euler (gravity subtracted
before the position update), so the REALIZED window is ticks 9..33 (feet above 1.5 u), apex
2.15 u, a 25-tick (0.42 s) window - measured headless from the running controller, not derived.
The test asserts the realized window +/-1 tick and a ~0.43 s window length +/-1 tick instead of
the unreachable continuous values. WHY: a test against 0.16/0.59 s continuous would encode a
jump the engine never produces and would fail on correct code; the spec numbers are honoured as
"the same arc, tick-quantized". The gameplay content (hurdle the cat during the jump) is
unchanged. [CONTESTABLE]: the owner may instead ask the integrator (gravity after position) to
match continuous physics more closely; that is a controller change (T-012), outside this ticket.
### D-T-031-1 - coil ships NO pursuit or burst speed; ceilings recorded as 0.0 / 1.0 (T-031).

DECISION (T-031): no document states a horizontal pursuit speed or a burst speed for coil -
and none should, because coil never walks: every metre it crosses, it crosses inside a
telegraphed arc at the end of a 0.6 s cue + 2.75 s flight. The enemy.json stats therefore
record `pursuit_ceiling: 0.0` (a fraction of base run speed that clamps any ground-pursuit
multiplier to zero: overtime, curses and Hunger have nothing to multiply, by construction,
not by a new rule) and `burst_ceiling: 1.0` (the SR-5 universal bound for a telegraphed
sprint; coil has no burst of its own, but if a future Zoomies-class effect ever names it,
it is bounded at 1.00 x base run speed and 3.0 s like every body). [CONTESTABLE]: the
numbers are stated nowhere; the reading is that coil is not a floater and the SR-5 table
(which covers kiwi cat / kitten / YOU?! / toucher / seal / Claude) deliberately has no coil
row. Gameplay reason: coil's threat is the ring it draws, never a chase; a pursuit speed
would turn the most telegraphed enemy in the game into a tracking one.
WHY: the SR-5 ceiling mechanism exists so no stack can outrun the player's own legs; coil
is answered by leaving the ring, and any ground speed at all would undercut that answer.

### D-T-031-2 - [CONTESTABLE] The coil arc apex is 4.0 u above the chord (T-031).

DECISION (T-031): no document states the apex of the 2.75 s arc. The flight is a parabola:
horizontal position lerps straight from the launch point to the locked landing zone; feet
height follows `chord + 4 * APEX * t * (1 - t)` with `APEX = 4.0 u` (8 HU) - the apex sits
exactly halfway through the flight, above the midpoint of the two end heights.
[CONTESTABLE]: the number is stated nowhere. Gameplay reason: 4.0 u clears any bastion-class
wall the generator builds (8 HU, the generator's tall-step ceiling), is readable from across
a level as "the coil is coming down THERE" (the jump IS the tell), and never reads as a
teleport; a flatter arc would skip intervening walkway slabs it should visibly clear, and a
taller one would waste the 2.75 s the player needs to leave the ring.
WHY: the landing zone moves straight-line horizontally while rising twice the JUMP apex -
a coil arc must clear platforms it launched from, or every jump would clip the slab it left.

### D-T-031-3 - [CONTESTABLE] "Airborne at landing avoids the shockwave" is read as a 1 HU y-band on the landing plane (T-031).

DECISION (T-031): the shockwave (6 u, 8 u/s decaying linearly to 0 over 0.5 s, 2.0 u travel,
locks class abilities 2.0 s, never kills) applies only to a player whose feet sit within
0.5 u (1 HU, the terrain quantum) of the landing tile's top plane; a player higher than
that at the landing tick - a jump at 2.25 u apex, or a ledge a HU or more above the landing
zone - is immune, push-free and lock-free. No grounded flag is readable through the section
12 API (`nearest_player` returns index/dist/x/y/z only), so a feet-band is the only in-API
signal of "airborne". [CONTESTABLE]: the reading is mine. Gameplay reason: the shockwave is
a ground ring; the spec's own answer line ("leave the ring (1.2 u) and be airborne or > 6 u
from the last grounded tile") only makes sense if "airborne at landing" literally dodges it,
and 1 HU excludes a standing player on the plane by exactly zero - a standing player's feet
ARE the plane.
WHY: every alternative (unconditional 6 u hit, or an estimated grounded flag) either punishes
the jump the spec explicitly rewards, or invents sim state the content layer cannot read.

### D-T-031-4 - [CONTESTABLE] The landing kill is a horizontal circle r = 1.2 u with no y band (T-031).

DECISION (T-031): at the landing tick every player whose horizontal distance from the locked
landing zone is <= 1.2 u is killed (`api.kill`, code `D-COIL`), regardless of feet height.
Being airborne inside the 1.2 u ring does NOT save the player. DESIGN.md section 5.2 says
"Landing on a player (within 1.2 u) = kill" and then states airborne immunity ONLY for the
shockwave ("A jump timed so the player is airborne at landing avoids the shockwave");
DESIGN's own answer line makes leaving the 1.2 u ring mandatory and airborne the answer to
the shove, not to the kill. [CONTESTABLE]: the no-y-band reading is mine; the alternative
(same cylinder rule as body contact) would make a full jump apex dodge the one number the
spec calls "leave the ring". Gameplay reason: one ring to leave, one shove to jump - the
answers must stay distinct or the enemy teaches the wrong lesson.
Ordering: a player inside 1.2 u is killed and receives NO shockwave (dead bodies take no
shove); a player between 1.2 u and 6.0 u on the landing plane takes the shove + lock.
WHY: the 1.2 u kill ring and the 6 u shockwave are two radii with two answers; collapsing
them would either delete the jump answer (y band on the kill) or make the shove lethal
(bonus kills), both forbidden by the spec's own "does not kill" and airborne sentences.

### D-T-031-5 - coil's landing ring is an arbiter-visible telegraph that the coil ages itself (T-031).

DECISION (T-031): at cue start the behavior announces one telegraph through the section 12
API: kind `coil_ring`, shape
`{"shape":"circle","cx":<zone x>,"cz":<zone z>,"r":3.0,"y0":<zone y>,"y1":<zone y>}`,
ticks = 201 (cue 36 + flight 165 - the T-083 anim block, telegraph effect, "visible for the
whole cue and the flight"; the landing ring, radius 3 u, DESIGN.md section 5.2). The `y0`/`y1`
band pins the ring to the landing tile's top plane, so `no_targeted_telegraph` (SR-4, for
address me) reads a ring on a ledge correctly and does not read a ring through five floors.
The runtime never decrements telegraph ticks, so entry lifetime is the caller's (D-T072-4):
each tick the behavior ages its own coil_ring entries (ticks -= dt_ticks, floored at 0), so
at the landing tick the entry reads 0 and the SR-4 gate sees no live ring afterwards.
Reaching `api.rt.telegraphs` to age its own entries is the one sanctioned-by-D-T072-4 caller
duty; no world state is read or written through it, and no other entry is touched.
WHY: an eternal ring would lock address me out of the level forever after the first coil
jump; the 201-tick countdown is the exact cue+flight window the telegraph exists for.

### D-T-031-6 - coil emits "audio" and "coil_land" events into rt.events (T-031).

DECISION (T-031): the behavior appends plain dictionaries to the runtime's per-step events
array - the same channel `api.telegraph` and `enemy_spawn` already use; appending an event
never mutates world state. Two cues, named exactly per the ENEMIES.md "New sound" line (the
classic spring boing before every jump; the metallic twang on landing), carried as
`{"e":"audio","cue":"coil_boing", ...}` at cue start and `{"e":"coil_land",
"cue":"coil_landing_twang","x":..,"y":..,"z":..}` at the landing tick; the impact event also
carries the landing point for the view's shockwave VFX. No .wav exists yet: T-055 synthesises
every cue from the names in `stats.audio` (`coil_boing`, `coil_landing_twang`); TBD.md row 28
records both as placeholders. Replay hashes state, not the event list, so determinism is
untouched.
WHY: a hook with no event is dead code, and inventing a parallel notification channel would
fork the one the T-027 spawn/death events already ride.

### D-T-031-7 - SR-2 numbers are enforced on the row at on_spawn; the placeholder body_rect derives 1.6 u (T-031).

DECISION (T-031): DESIGN.md (SR-2, D-065 FINAL) pins coil at height 1.0 squashed / 2.0
extended, hit diameter 0.9. The T-016 TBD placeholder frames cannot derive that pair (the
squashed frame's body_rect at 1.0 u height derives a 1.6 u diameter), so `on_spawn` pins
`row["diameter_u"] = 0.9` and `row["height_u"] = 1.0` outright, and the behavior switches
`row["height_u"]` 1.0 / 2.0 by state (1.0 in spawn/idle/cue/landing/recover, 2.0 in flight;
diameter constant). The `world["enemies"]` r mirror stays the spawn-time derivation, which is
harmless: the arbiter reads body positions only, never r. If real art lands with a matching
rect, the derived cylinder equals these numbers and the pin changes nothing.
WHY: SR-2 is the FINAL spec for the coil hitbox; the pipeline's placeholder rect is not a
reason to ship a 1.6 u cylinder for an enemy whose spec says 0.9.

### D-T-031-8 - coil needs NO arbiter block; the anxiety is the ring, which is data (T-031).

DECISION (T-031): coil declares no `arbiter` block in enemy.json - no document gates coil's
appearance, and T-072's ruling is that every other row omits the block (absent = no gate).
Coil's only scheduling surface is the `coil_ring` telegraph of D-T-031-5: address me's
`no_targeted_telegraph` requirement and gin's deferral see it as data, with no coil-specific
code anywhere. No appear_requires are invented.
WHY: SR-4 schedules two specific enemies; giving coil a gate would invent a rule the spec
never wrote, and spec gaps are DECISIONS entries, not silent content.

### D-T-031-9 - [CONTESTABLE] coil copy staggering: first cue delay staggered by CYCLE/n, never mid-cue spawn (T-031).

DECISION (T-031): SR-3 (D-065) is applied to the first attack, not to spawn position: copy k
of n computes `phase = stack_phase(CYCLE_TICKS, k, n)` (CYCLE_TICKS = 405 = 180 idle + 36 cue
+ 165 flight + 24 recover) and its first cue fires at tick `180 + (CYCLE - phase)` for k > 0
(copy 0: tick 180), so copies attack every CYCLE/n, perfectly spaced, and no copy ever spawns
into a live telegraph or mid-flight. Copies in the same level still spawn >= 30 u apart
(SR-3 / D-056, unchanged). [CONTESTABLE]: DESIGN does not state how SR-3 offsets a non-floater
with a multi-segment cycle; wrapping a spawned copy into a mid-cue origin (the literal
reading) would spawn a body whose telegraph began before it existed. Gameplay reason: three
coils land 135 ticks apart, not at once and not one-full-cycle late.
WHY: the rhythm is the readable answer for every roster enemy; an unstaggered wave deletes
the telegraph's teaching value.

### D-T-031-10 - coil landing resolution targets the row's target player (player index 0) (T-031).

DECISION (T-031): the landing kill (D-T-031-4) and the shockwave (push + 120-tick ability
lock) resolve against `api.nearest_player` - the row's target, player 0 in the single-player
sim (D-T072-5 precedent). The section 12 API exposes no enumeration of players, and coil has
no line where DESIGN names a multi-player behaviour. [CONTESTABLE] until the roster's
targeting pass lands: a second player standing in the 1.2 u ring or the 6 u band is resolved
by the body-contact rule (which the runtime applies to every controller) but not by the
landing-specific rules. Gameplay reason: in the shipped single-player game there is exactly
one player, and the target is always at the landing zone's home tile, which is where the
ring is drawn - the rule resolves the one player the ring was drawn for.
WHY: the alternative (unlistable API reach into `rt.controllers`) is exactly the "no other
access" wall the section 12 contract exists to hold.

### D-T-031-11 - coil's shockwave is applied as a 30-tick per-tick api.push with linear decay (T-031).

DECISION (T-031): on the landing tick, for the targeted player outside the kill ring but on
the landing plane and within 6 u, the behavior stores `row["shock"] = {"ticks": 30, "dir":
<horizontal outward unit vector from the landing zone>, "index": <target player index>}` and
every tick thereafter calls `api.push(player, dir, 8.0 * ticks_left / 30.0)` (30 -> 1),
yielding the spec's linear decay from 8 u/s to ~0.27 u/s and ~2.07 u of ideal travel (the
continuous spec value: 8 * 0.25 = 2.0 u; discrete application differs by 0.07 u, far inside
the 2.0 u D-066 guarantee that a shove clears a 1-wide path from its centre). The push API is
the only push channel the content layer has: a single 8 u/s push would decay inside the
controller's 90 u/s^2 accel to ~0.4 u of travel, which would quietly delete D-066's geometry
promise. Realized travel measured through the shared controller friction is ~1.3-2.1 u
(step-order dependent); the test asserts the D-066 floor (>= 0.9 u, the 1-wide path from its
centre) and an upper bound (<= 2.6 u), never the continuous 2.0 u figure as-is. Side effect, acknowledged: `api.push` zeroes horizontal-dir vy each tick, so a
grounded recipient's vy is held at 0 for the 30 ticks - harmless for a grounded player, and
airborne players are immune by D-T-031-3 and never enter the window. The player is not
re-eligible for a second shock in the same landing (the source entry is one-shot by
construction) and the shock never stacks with the kill path.
WHY: D-066's 2.0 u of travel is the load-bearing number (it is what makes the shove
survivable on a platform >= 5 wide); it must be produced by the effect itself, not by the
controller's friction constants, which it does not survive.

### D-T-031-12 - coil's idle time is data (`idle_s`, default 3.0) for Overwound (T-031).

DECISION (T-031): the behavior reads the idle segment length from cfg `idle_s` (default
3.0 s, DESIGN section 5.2) instead of a bare constant, so the scripted Overwound curse
(`requires_enemy: "coil"`, 3.0 -> 2.0 -> 1.5 s, max stacks 2) can shorten it at the content
layer when that curse's ticket lands, without a behavior edit. The cue (36) and flight
(165) stay constants: no document permits lengthening or shortening them.
WHY: a curse that edits a behavior constant would break the moment the curse shipped;
a curse that edits cfg is the data pass working as designed.
### D-T-032-1 - [CONTESTABLE] thicc ben's touch re-trigger is cooldowned at 30 ticks (T-032).

DECISION (T-032): a player standing inside ben's body is ejected/blurred/belled at most once
per 30 ticks (0.5 s) per player, kept on the row as `touch_cooldown`. ENEMIES.md and §5.3
state the touch effect but no re-trigger cadence; with no cooldown the 60 Hz overlap re-fires
the push, the blur, the bell, the chain_reset and the cleanse EVERY tick the player stands in
the body (event spam, chain_reset spam, a permanent vy = 18 u/s pin). WHY 30: the spec's own
0.5 s unit (the lock lead and the chime tail are both 0.5 s). No document states any cadence;
[CONTESTABLE] if the owner wants a different rhythm.

### D-T-032-2 - [CONTESTABLE] the 13.35 s teleport interval is not shortened by overtime or tempo (T-032).

DECISION (T-032): ben's cycle stays the §5.3 binding 801 ticks at every overtime tier and under
every curse; ben attaches no FloatBody (his cfg carries no base_speed) and SR-5 tempo overflow
has no cycle to shorten. Overtime's "enemy cooldowns -5% per tier" is generic language; §5.3's
"Every 13.35 s" is the binding number this ticket's test asserts within ±1 tick. Quarter Chimes
(min_level 4, "ben's teleport interval 13.35 → 9 s") exists in the curse list precisely as the
sanctioned interval knob. [CONTESTABLE]: one could read the overtime cooldown cut into the
interval; that reading makes the ±1-tick assertion on a bare 13.35 s wrong at tier >= 1.

### D-T-032-3 - [CONTESTABLE] the ben-ring cleanse radius is horizontal (XZ) distance (T-032).

DECISION (T-032): "thicc ben's ring cleanses glitched tiles within 8 u" (§5.8, toucher
paragraph; T-083 anim block attack_ring: "a ring wave expands to 8 u (the cleanse radius) in
18 ticks") reads as XZ distance from ben's feet row to the tile centre <= 8.0 u. The ring is a
horizontal wave (the attack_ring rock is a spin around the vertical axis), so the cleanse plane
is the ring plane. [CONTESTABLE]: 3D distance is a one-line change if the owner rules it.

### D-T-032-4 - §12 API extension: api.eject_player announces ben's touch (T-032).

DECISION (T-032): the section 12 Enemy API gains `api.eject_player(player, why, blur_ticks)`.
It appends exactly two events to the runtime's events array (the same array step() returns):
`{"e": "chain_reset", "why": why, "tick": tick, "player": index}` and
`{"e": "screen_blur", "ticks": blur_ticks, "tick": tick, "player": index, "source": <id>}`.
WHY: the section 12 surface has no emit channel for a non-kill announcement, and ben's touch
is canonically chain-breaking (data/economy.json gold_phase.chain.break_events lists
`thicc_ben_eject`; DESIGN.md 3.2) with a player-side blur of 180 ticks (T-083 anim block,
binding). `sim/mines.gd` emits chain_reset into the same events array from sim code, so the
engine caller's consume path (scan events, call economy.break_chain(why)) is unchanged; the
`why` string is DATA owned by economy.json's whitelist, never code. Additive only: no existing
method, event shape or consumer changes; no content id is named. The engine caller wires
screen_blur to the HUD blur overlay (view/hud/screen_blur.gd, T-032).

### D-T-032-5 - §12 API extension: api.cleanse_glitched_within removes glitched tiles in a radius (T-032).

DECISION (T-032): the section 12 Enemy API gains `api.cleanse_glitched_within(pos, r) -> int`:
it deletes from `world["glitched"]` every key whose tile centre (x + 0.5, z + 0.5, XZ) sits
within `r` u of `pos` (D-T-032-3 axis), returns the number removed, and appends
`{"e": "glitched_cleanse", "count": n, "r": r, "tick": tick, "x": pos.x, "z": pos.z}` to the
events array. WHY: §5.8 (toucher) states "thicc ben's ring cleanses glitched tiles within
8 u" and the T-083 anim block draws the ring expanding to exactly 8 u; no closed-surface path
could delete a glitched tile, so the promise was unimplementable. Additive only; no content id
is named (the caller passes the radius).

### D-T-032-6 - nearest_player's return gains vx, vy, vz (T-032).

DECISION (T-032): `rt.nearest_player(pos)` now also returns the queried player's
`vx`, `vy`, `vz`. §5.3 locks the destination at smoke start as "player position + velocity x
0.5 s"; the section 12 API returns a position but no velocity, so the lock was uncomputable
through the closed surface. Additive: every existing reader reads only index/dist/x/y/z.

### D-T-032-7 - enemy.schema.json gains OPTIONAL top-level behavior / counter_play / tell (T-032).

DECISION (T-032): `core/schemas/enemy.schema.json` gains three optional string properties,
`behavior`, `counter_play`, `tell` (the file keeps `additionalProperties: false`; nothing becomes
required, no existing key changes). WHY: the lobby adversary panel (view/lobby/antechamber.gd)
reads exactly `sheet.get("behavior")` and `sheet.get("counter_play")` off the parsed enemy.json
to fill the ENEMY bay panel - with the old schema the keys were refused at boot, so every panel
would have printed "Behavior: TBD (enemy wave pending)". The ticket's deliverable 1 requires the
counter-play line and the tell line to live in enemy.json. This is additive schema growth, not
a weakened check; the registry still refuses any file violating the remaining shape.

### D-T-032-8 - [CONTESTABLE] ben's stats carry pursuit_ceiling = burst_ceiling = 0.0 and no base_speed (T-032).

DECISION (T-032): enemy.json's stats block records `pursuit_ceiling: 0.0` and
`burst_ceiling: 0.0` and NO `base_speed` (so the runtime attaches no FloatBody). The ticket
asks for both ceilings; no document states values for a body that never pursues (ben teleports;
the eject is the only motion in his kit). 0.0 is the honest "no pursuit" value - under SR-5's
clamp it would cap horizontal speed at 0 u/s, which is exactly what ben's body does - and it is
never exercised, because FloatBody is attached only when cfg carries `base_speed`. If a real
number is ever wanted, this row is the one to change. [CONTESTABLE].

### D-T-032-9 - [CONTESTABLE] ben's teleport cycle counts from on_spawn, not from level start (T-032).

DECISION (T-032): `row["cycle_t"]` starts at 0 in on_spawn; the first telegraph begins at
cycle_t 726 (13.35 s - 1.25 s) and the first arrival lands at cycle_t 801 (13.35 s after spawn).
§5.3 gives the interval but no phase origin; level start would make the spawn tick (360, or 120
under Early Bird) leak into the enemy's own cadence. The spawn is the enemy's birth; its clock
starts there. [CONTESTABLE]: anchoring to level start is a two-line change.

### D-T-032-10 - [CONTESTABLE] telegraph kind "teleport", circle r = 1.2 u at the locked point (T-032).

DECISION (T-032): ben's smoke posts a telegraph to the runtime via api.telegraph with
`kind = "teleport"`, `shape = {"shape": "circle", "cx", "cz", "r": 1.2}` and `ticks = 75`.
r = the T-083 anim block smoke `width_u` (1.2 u). No y band (the column spans the body's
height; the arbiter's nearest-point shape check still applies on XZ). Known and recorded, not
fixed here: the runtime never decrements telegraph entries (D-T072-4's recorded gap), so the
entry persists in rt.telegraphs; ben declares NO arbiter block and yields to nothing (SR-4
names only address me and gin), so the persistent entry is inert for every gate in the sim.
Fixing the runtime's telegraph lifetime is a shared-sim change beyond this ticket.

### D-T-032-11 - [CONTESTABLE] lock break is measured 3D from the locked point to the player's feet (T-032).

DECISION (T-032): at arrival, `dist3d(lock_point, player feet) >= 4.0 u` marks
`row["lock_broken"] = true` (ben still appears AT the locked point - "ben appears where they
were"); otherwise false. §5.3 states the 4 u threshold but not the metric; 3D-to-feet is the
D-T072-1 convention the rest of the sim uses for body-to-player distance (and prevents a
pure-height approach from reading as "far" while standing on the smoke). [CONTESTABLE]: XZ is a
one-line change.

### D-T-032-12 - the chain_reset reason for ben's touch is the data whitelist string (T-032).

DECISION (T-032): ben emits `chain_reset` with `why = "thicc_ben_eject"` verbatim -
data/economy.json gold_phase.chain.break_events and core whitelist both carry exactly that
string (DESIGN.md 3.2). Not a design choice, recorded so nobody renames it in the behavior.
`scripts`/views/economy consume it; this ticket does not touch any of them.

### D-T-032-13 - [CONTESTABLE] ben's touch has no blur "strength" state in the sim; the strength curve lives in the view (T-032).

DECISION (T-032): the sim emits one `screen_blur` event with `ticks = 180`; the strength curve
(1.0 from tick 0..119, linear 1 -> 0 over ticks 120..179) is view-side math in
view/hud/screen_blur.gd (`strength_for(elapsed_ticks)`), binding from the T-083 anim block's
player-side note. The sim tracks only `row["blur_ticks_left"]` as a cooldown-adjacent counter
for tests; it never scales movement or damage. WHY: the blur is a render effect; the sim
announces, the view renders (DESIGN.md 13/14).

### D-T-032-14 - enemy.schema.json gains OPTIONAL top-level contact_kill (T-032).

DECISION (T-032): `core/schemas/enemy.schema.json` gains one optional boolean, `contact_kill`
(default true semantics at the runtime). WHY: the D-T027-5 opt-out flag is read by
`enemy_runtime.gd` from the cfg top level (`cfg.get("contact_kill", true)`) and thicc ben is
the one enemy whose body contact never kills (DESIGN.md 5.3 / KILL RULE's third listed
non-killing effect); the closed schema previously refused the key at boot, so the data could
not express D-T027-5's own opt-out. Additive, optional, one key; the registry still refuses
everything else the old shape refused. (T-032 also extends the same schema with OPTIONAL
`behavior` / `counter_play` / `tell` - see D-T-032-7.)

### D-T-032-15 - world["enemies"] mirror back-reference + sync_body_mirror for instant repositions (T-032).

DECISION (T-032): the runtime now stores `row["body_mirror"]` = the exact dictionary it
appended to `world["enemies"]` at spawn (same reference), and gains `sync_body_mirror(row)`
which copies row x/y/z/hit-radius into that dictionary in place; the Api exposes it as
`api.sync_body()`. WHY: the mirror is written once at spawn and never again - movers update
only the row - so a TELEPORT (ben's whole kit) would leave the safe-tile distance check (6 u)
and the D-073 dais body-push reading the position ben left, not the one he occupies. Entries
keep the exact {x, y, z, r} shape every reader expects; no reader changes. Floaters keep the
old behavior (callers there don't sync); only instant repositioning uses this.

### D-T-032-16 - `preferred_kind: "none"` is the additive sentinel for DESIGN.md's `none` rows (T-032).

DECISION (T-032): `pick_spawn_tile` treats `preferred_kind == "none"` as "skip (a) AND (b),
straight to fallback (c)" (implemented by extracting step (c) into `_pick_round_trip`, called
by both paths). `""` keeps the merged T-027 semantics (skip (a); still run (b)) that
test_spawn_rule.gd pins. DESIGN.md section 5 states: "`none` means the enemy has no preferred
anchor kind: it skips (a) and (b). Ben's initial position is fallback (c)"; the merged runtime
could not express that row. The conflict is parked as PARKED.md row 5 - test_spawn_rule.gd is
merged T-027 and was not edited. enemy.json carries `"preferred_kind": "none"`; the schema
gains the optional string with the same meaning documented.

﻿
### D-T-035-1 - [CONTESTABLE] YOU?!'s ring vertical kill window: feet-based, (feet_e - 1.5, feet_e + 1.0).
DECISION (T-035): the ring kill requires the player's FEET to sit strictly inside
(ring_feet - 1.5 u, ring_feet + 1.0 u) - the head is ignored. All three vertical escape
clauses of DESIGN.md section 5.6 then hold EXACTLY: (a) jump clears - jump height > 1.0 u
leaves feet_p > feet_e + 1.0 (the 0.10-0.65 s window); (b) stand >= 1.5 u above its feet -
feet_p >= feet_e + 1.5 satisfies the window's upper edge; (c) stand >= 1.5 u below its feet -
feet_p <= feet_e - 1.5 satisfies the lower edge. The drawn band stays the 1.0 u tall
translucent red band at [feet, feet + 1.0] (ENEMIES.md 1:1: its plane must be readable), and
the below-feet tolerance is therefore MORE forgiving than the draw - it never kills unfairly,
but a one-terrace drop below the ring can leave the player's body touching the drawn band
without dying; the spec's above/below clauses are the spec's answer line and are kept verbatim.
WHY: the three clauses cannot all be met by a body-vs-band overlap (that needs feet_p <=
feet_e - 1.8 to escape below) nor by a symmetric +/-1.5 u band (jump needs > 1.5 u, breaking
the stated 0.10-0.65 s window). This is a SPEC GAP (the section names "travels in the
horizontal plane of its feet +/- 1.5 u" without defining the kill interval); the drawing and
the kill window are recorded here, not merged into one rule.

### D-T-035-2 - [CONTESTABLE] Ring radial kill window: |d - r| <= 0.7 u.
DECISION (T-035): the ring's hit test uses the framework's expansion convention - the
0.6 u thick band (half-thickness 0.3 u) expanded by the player's 0.4 u half-width:
|horizontal distance from the ring centre - r| <= 0.7 u. The spec's "0.16 s crossing"
checks out exactly with this rule: the band plus the player's 0.8 u width is a 1.4 u
pass at 9 u/s = 0.156 s. A raw 0.6 u band would cross in 0.067 s and contradict the spec's
own number. The 0.16 s figure in section 5.6 is the tie-breaker that pins this reading.
WHY: DESIGN.md section 5.6 and the T-035 answer-window line in FLEET_PACK.md both state
the crossing as 0.16 s; only the expansion reading reproduces it.

### D-T-035-3 - [CONTESTABLE] The ring-release (attack) hold is 18 ticks.
DECISION (T-035): the anim block's `attack` state (you_04, ring_release effect) shows from
the tick the ring launches "until the sim leaves the attack state", with no bound stated.
The state is held for 18 ticks (0.3 s), matching the roster's other short attack holds
(thicc ben attack_ring 18 ticks; Isagi attack 30). It then enters `recover` for the
240-tick (4.0 s) cooldown cycle. WHY: an unbounded attack state would hold the release
frame forever; 18 ticks is the roster's short-release convention, and the 240-tick recover
is stated in both the spec and the anim block. game/tools/check_anim_data.gd is not edited
(the `attack` state it hardcodes carries total_ticks: null, unchanged).

### D-T-035-4 - Death attribution: the ring kill passes killer_id "YOU" (D-YOU); the framework contact path's '?' wart is logged for T-073.
DECISION (T-035): every kill the behavior itself commits (the ring) calls
api.kill(player, "YOU"), giving code "D-YOU" (sim/death.gd's closed map, roster name
"YOU?!"). The framework's body-contact path (sim/enemy_runtime.gd _contact_kills) passes
the row's DISPLAY name to try_kill, so a row named "YOU?!" yields "D-YOU?!" - unknown to
the closed map (killer_for falls back to the raw code; never an empty screen). This ticket
does not edit sim/enemy_runtime.gd (T-027's file, unmerged waves depend on it). The
spawning integration (Wave 4 T-073) should pass a name that normalises to the closed code
("you" -> "YOU" -> "D-YOU"), or strip punctuation in kill(). Recorded here so T-073 does
not have to rediscover it.

### D-T-035-5 - [CONTESTABLE] The 10 u rumble trigger is the 3D nearest-player distance.
DECISION (T-035): "Within 10 u" (DESIGN.md section 5.6) is measured with
api.nearest_player()'s own metric - the 3D distance between the enemy's position and the
player's position. No horizontal-only alternative is stated for this enemy (the 4-12 u
horizontal window is seal's dash telegraph, a different rule), and the floater's altitude
easing (2.0 u/s) makes the two converge within a second or two of pursuit anyway.

### D-T-035-6 - [CONTESTABLE] YOU?! keeps floating during its rumble.
DECISION (T-035): the behavior does not stop horizontal movement for the 1.5 s rumble -
ENEMIES.md describes it as "a slow mover that creates shockwave rings that kill instantly
when it gets close" and DESIGN.md section 5.6's float clause ("Floats toward the nearest
player at 3.4 u/s") carries no rumble-standstill exception. The SR-5 pursuit ceiling and
the SR-1 vertical easing apply unchanged during telegraph, attack and recover phases.

### D-T-035-7 - [CONTESTABLE] Burst ceiling recorded as 1.00 - YOU?! has no burst.
DECISION (T-035): YOU?! has no telegraphed sprint (no Zoomies interaction is defined for
it and its anim block carries no burst frame row), so begin_burst() is never called. The
pursuit ceiling (0.55) is the only binding ceiling; the burst ceiling is recorded as 1.00
(the SR-5 absolute burst bound) so that any later script-curse burst it might gain can
never outrun base run speed.

﻿
### D-T-035-8 - The ring is NOT registered in world["hazards"] - the Enemy API has no world-write for hazards.
DECISION (T-035): an earlier draft of this entry registered each live ring as a tagged
footprint in world["hazards"]. That is impossible from the content layer: the section 12
Enemy API exposes no world-write call (telegraphs are one-shot events nobody materialises
into world hazards anywhere in the sim yet), and this ticket does not add one (the Enemy
API is closed). The ring is therefore drawn and kill-resolved entirely inside the behavior;
valid_safe_tile() does not see it, so a void-dive respawn may land near a live ring. That
is the same state every other ring enemy is in (nuke's ground ring, coil's landing ring,
Claude's drums are likewise unregistered), and it is an integration gap for the Wave 4
hazard bus / T-073, not a weakening this ticket can or should paper over. Recorded so the
integration knows to read live rings from the row (row["rings"], {"x","y","z","r"}) instead
of a world hazard dictionary when it lands.
WHY: only the API may be touched from behavior code; nothing else in the sim exposes the
world to a RefCounted behavior.
### D-T-035-9 - counter_play / tell / behavior / preferred_kind live inside "stats" (closed enemy schema).
DECISION (T-035): the enemy JSON schema (core/schemas/enemy.schema.json) is
additionalProperties:false over {id, name, min_level, max_votes, vote_effect, anchor_kinds,
stats, sprites, script}, so the exhibit-facing lines ("counter_play": jump the ring as it
reaches you / height escape; "tell": the corrupted rumble ~1.5 s before each shockwave;
"behavior"; "preferred_kind" mirrored for the runtime's D-056 spawn read; "death_code":
"D-YOU") are carried in the open "stats" object, the T-021 (gift Larper) precedent.
view/lobby/antechamber.gd's enemy panel reads TOP-LEVEL counter_play/behavior
(lobby.content.enemy(id)[...]), which the closed schema forbids this ticket to add without a
schema edit; the exhibit still renders the sprite + name + votes, with the behavior line at
its built-in TBD fallback. Opening those two top-level keys is a schema change shared with
the parallel Wave-3 tickets and Wave 4 (T-073); it is flagged here, not resolved by editing
another wave's shared file in this ticket.

### D-T-035-10 - vote_effect is the literal roster table text; Echo Ring is not built into the behavior.
DECISION (T-035): vote_effect is "+1 YOU?!" (the DESIGN.md vote table row 6 wording); the
content layer's votes -> bodies wiring is the T-073 integration's. Echo Ring (double_ring,
"every shockwave is followed by a second ring 0.6 s later") is T-051's enemy-linked curse;
this behavior does not implement it. To keep it implementable without touching the closed
hook list (on_tick only), every live ring release is observable on the row: "ring_seq"
(incrementing) and "last_ring_tick" (row-local 60 Hz tick count) advance together, so an
on_tick handler can detect a release and schedule the follow-up 36 ticks later.

### D-T-035-11 - Placeholder audio: one cue named for the ENEMIES.md New sound line.
DECISION (T-035): the only sound ENEMIES.md 1:1-assigns to YOU?! is the pre-shockwave build:
"quiet corrupted static + reversed glitch screech building up before each shockwave - like
the player model screaming through the corruption." The placeholder-cue hook is named
"you_corrupted_rumble" (enemy.json stats.audio_cues). No .wav ships in this ticket:
synthesizing placeholders for every cue named in the roster is T-055's scope, and no other
enemy ships one yet. TBD.md row 28 records the cue as a T-055 synthesis target.

### D-T-035-12 - The kill test runs Last Light spent (D-057), and asserts the two readings of "its death code".
DECISION (T-035): tests/test_enemy_you.gd spends the controller's Last Light for real and
clears the arrival state before any kill assertion (the test_kill_api.gd fixture pattern),
so no save can mask a kill. Death-code assertions: (a) the behavior's ring kill passes
killer_id "YOU" -> "D-YOU" (in death.gd's closed map, shown as YOU?!); (b) the framework's
contact kill passes the row's display name - the test spawns one body as "you" to assert the
"D-YOU" mapping the integration should reproduce, and separately asserts the kill itself with
the display name "YOU?!" (D-T-035-4).



﻿
### D-T-035-13 - [CONTESTABLE] The ring kill fans out over nearest_player() only (the section 12 API has no players-in-radius).
DECISION (T-035): the ring's hit test reads api.nearest_player() - the only player-query on
the section 12 surface - and applies the kill to that player. The framework's body-contact
path, by contrast, loops every controller (sim/enemy_runtime.gd _contact_kills), because the
runtime owns that list internally. There is no players_in_radius / all-players call in the
Enemy API, and this ticket does not add one (adding to the closed Enemy API is a core
change). VOIDWRAP is single-player today (DESIGN.md section 13), so the behavior is complete
as built; when multiplayer lands, the ring needs the same fan-out the frame already gets.


### D-T-036-1 - gift Larper's world body height is 1.0 u / hit diameter 0.8 u [CONTESTABLE] (T-036)
SPEC GAP: DESIGN.md section 5 (SR-2) gives gift Larper no world row - "The nuke has no body; gift
Larper occupies gift slots as the tripmine (section 3.3) - the roster's other rows carry no world
size" - so no document states a body height, and none was invented elsewhere. The billboard needs
one to scale the PNG (billboard.gd's scale divides by the frame height at 0.01 u/px, and the lobby
exhibit multiplies by it), so `sprites.json`'s top-level `world_height` moves `null` -> `1.0` (the
T-016 documented null for the absent SR-2 row is retired for this enemy only; its `_doc` note is
updated). The row stands at the section 6.7 occupancy height (`y*0.5 + 1.0`, sim/mines.gd's box
point) - a ~1 u box is the only number in play. HITBOXES: hit cylinder = 0.8 x body width; at
1.0 u tall the TBD sheet's square 80 px body (of the 256 px frame) is 1.0 u wide, so the hit
diameter is 0.8 u, pinned in cfg (`hit_diameter`, the D-T030-2 pattern - the art derivation and
the pin agree). The 1.0 u value is [CONTESTABLE]: the owner may re-pin any height without touching
the behavior; SR-2 stands untouched otherwise, and the real kill volume is the section 3.3 0.9 u
ANY-height trigger, not this cylinder. WHY [gameplay reason]: without a world height the PNG cannot
render or be exhibited at all; 1.0 u matches the occupancy-height lift and reads correctly on the
lobby plinth (exhibit scales to 1.6 u from it).

### D-T-036-2 - [CONTESTABLE] gift Larper's pursuit ceiling and burst ceiling are 0.0 (T-036)
SPEC GAP: the ticket asks for the keys; a stationary slot hazard has no pursuit. Built:
`base_speed` 0.0, `pursuit_ceiling` 0.0, `burst_ceiling` 0.0. Any multiplier product with a 0
base speed clamps to 0 (FloatBody), so no overtime tier, curse or burst can give a mine motion -
SR-5 is honoured vacuously rather than by a hidden "stationary" flag. WHY [gameplay reason]: a
non-zero ceiling would imply a reachable pursuit speed for a mine and invite "mines speed up
at high tiers" readings no document supports; 0.0 is the only value that cannot mislead.

### D-T-036-3 - the runtime body-contact path is DISABLED for this row; the section 3.3 ladder is the only kill path (T-036)
cfg carries `contact_kill: false`. `sim/mines.gd` owns contact for slot occupants: the player's
centre within 0.9 u HORIZONTAL of the box point at ANY height triggers the fixed ladder (defuse
roll -> Subspacial Barrier -> Last Light -> D-MINE, D-058), and a reached death blasts 3 u.
`enemy_runtime.gd`'s plain `_contact_kills` would kill without the defuse roll and without
consuming the barrier - a bypass of the FINAL resolution order - so the row is spawnable through
`spawn_at` (the drop-in shape) but inert against players; only the ladder kills. The test asserts
both directions (the ladder kills D-MINE with Last Light spent, including from jump-apex height;
the runtime step never kills on overlap). WHY [gameplay reason]: a mine that killed through two
paths at once would silently refund defuse stacks' worth of survivability differently per
prediction, and D-051's deterministic roll would be unauditable.

### D-T-036-4 - view tell: particles inside the 12 u ramp; no telegraph animation exists (T-036)
`game/view/gift_larper_view.gd` (the D-T030-7 pattern): the `spawn` state renders NOTHING ("present
from level start - no fade, no scaling", the T-083 anim block); `idle` steps the 5-frame cycle
(48 ticks per frame; 240 ticks = 1 revolution per 4.0 s, the section 3.3 binding turn); the
`telegraph` state renders NO animation ("its tell is the look, within 12 u"). The tell is a
distance read (`sync(eye)`): inside `TELL_DISTANCE` (12.0 u, boundary inclusive, D-T021-6) the
constant pink emitter (#FF4FD8) shows; beyond it the emitter is off and the body reads as a black
gift. The rim-glow-beyond-12-u half of the section 3.3 tell is the glb path's job
(`view/tripmine_view.gd` material_overlay - a Sprite3D cannot additive-overlay itself); the PNG
sheet keeps the ordinary-gift look. The Method Acting 5-7 u ramp and the Radar Module: Mines 14 u
outline are anim-block params, recorded and unwired: no upgrade-hook path exists in the view
layer yet (owner to say where upgrade visuals bind). WHY [gameplay reason]: the 12 u ramp is the
counter-play window - at run speed it is 1.3 s of reaction - and the tell's honesty is the spec.

### D-T-036-5 - detonation and defused render client-side across the T-083 windows; 24 TOTAL ticks, not per frame (T-036)
Built in the view: `on_detonation()` runs the `attack_detonation` state's 18 TOTAL ticks - a
white flash (full-white modulate for the first ~4 ticks, then back) plus a sphere burst expanding
0 -> `burst_radius_u` (3.0 u), lerping `#FF4FD8` -> `#000000` while fading out; the audio hook
plays `explosion`. `on_defused()` runs the `defused` state's 24 TOTAL ticks - modulate greys out,
the sprite drops `drop_u` (0.5 u) while fading to alpha 0, a one-shot grey 'pff' puff fires at the
end, the `pff` audio hook fires, NO blast (the anim block's `no_blast`). The white flash is a
modulate, not a texture swap - the art is the T-016 TBD placeholder. WHY [gameplay reason]: the
18-tick detonation is the kill's visual confirmation (it must be unmistakable and client-local);
the 24-tick defuse is the "you were saved" read - grey, low, gone.

### D-T-036-6 - audio cues `explosion` (ENEMIES.md) + `pff` (the T-083 defused effect) as no-op-silent placeholders (T-036)
ENEMIES.md "New sound" (verbatim): "Roblox tripmine explosion sound effect." - cue `explosion`,
file `assets/audio/enemies/gift_larper/explosion.wav` (T-055's cue = file name contract); TBD.md
section 2 already lists the missing recording as the synthesized blast. A second cue `pff` is
named by the T-083 anim block's own `defused` effect name - a deliberate, tiny defuse puff; it is
NOT an ENEMIES.md addition and stays TBD until synthesised. Both hooks no-op SILENTLY while the
files are absent (the kiwi cat pattern; T-055 owns the files) and both are TBD.md rows 30/31.
WHY [gameplay reason]: the explosion is the punishment cue; the defuse puff is the relief cue -
and a missing wav can never drift the sim.

### D-T-036-7 - gift Larper carries NO arbiter block (T-036)
The behavior needs no scheduling gate: gift Larper never "appears" - it is a slot occupant from
level start ("present from level start; no fade, no scaling"), and SR-4/D-067 gate address me and
gin ichimaru only. `anchor_kinds` stays `[]` (the section 5 preferred-kind table: `none` - "it
lives in gift slots"); nothing about the mineset is deferrable by another enemy.
WHY [gameplay reason]: an arbiter entry for a mine would let another enemy's schedule silence the
mines - no document grants or hints at that.

### D-T-036-8 - enemy.json gains the lobby-panel keys (D-T030-6 pattern); content counts unchanged (T-036)
`behavior` / `counter_play` / `tell` top-level strings (the altar panel path,
`antechamber.gd` lines) - counter-play "walk around it, never over it - the star and the pink
sparkles inside 12 u give it away"; tell "black framed box, six-pointed star, pink particles
inside 12 u; rim glow like an ordinary black gift beyond it". `test_content.gd` does NOT bump:
gift_larper's enemy.json already counted (2 enemies / 89 content_ids before this ticket).
WHY [gameplay reason]: the panel is the only place the player learns the counter-play before the
level starts.

### D-T-036-9 - the answer window is asserted as geometry + arithmetic, never as motion (T-036)
FLEET_PACK's T-036 answer window: "look and walk around it - at run speed 12 u = 1.3 s of the
star/particle tell inside the 12 u ramp (0.67 s under Method Acting); D-026 guarantees a walkable
bypass around every mine". The mine never moves, so the test asserts statics with +/-1 tick room
on the timings: tell radius 12.0 u (inclusive boundary), the 0.9 u horizontal ANY-height trigger
(the jump-over case kills at jump apex), the 3.0 u blast, the +3-mines-per-vote curve (clamp 15),
and the reaction arithmetic (12.0 u at 9.0 u/s run speed = 80 ticks = 1.33 s of warning).
WHY [gameplay reason]: the counter-play is looking and walking around - a motion assertion would
test a mine that does not exist.

### D-T-038-1 - the seal's dash rides its body CENTRE on the fixed 3D line (row y = centre - 0.3 u), so the section 5.9 clear rules fall out of the framework's cylinder check (T-038).
DESIGN.md section 5.9 (D-069): the dash line is fixed at telegraph start as the straight 3D
segment from the seal's body centre through the player's centre (0.9 u above the feet),
extended to 20 u. Built: at telegraph start the row stores the line origin (the body
centre) and the fixed unit direction; during the 60-tick dash the body centre advances
1/3 u per tick along it (20 u in 1.0 s) and the row's feet ride at centre - 0.3 u. WHY:
the spec's clear rules ("the player is missed if their feet sit more than 1.2 u above the
height they had at telegraph start, or their head is below the line") then hold against the
ordinary upright-cylinder contact check with NO special case - at the crossing the seal's
band is [centre-0.3, centre+0.3] = [feet+0.6, feet+1.2] relative to the telegraph-start
frame, so a player whose feet are > 1.2 u up simply does not overlap it (a jump clears
1.2 u from 0.12 s to 0.63 s - a 0.51 s window for the 0.07 s body crossing; a 3 HU step is
1.5 u; a head below the line no longer reaches it either). The dash is fixed kinematics,
NOT a FloatBody burst (SR-5 bounds bursts only); flapping uses FloatBody with the SR-5
0.60 pursuit ceiling.

### D-T-038-2 - the seal telegraphs only between 4.0 u and 12.0 u (inclusive, 3D); no arbiter block (T-038).
DESIGN.md section 5.9: "The seal starts a telegraph only when it is between 4 u and 12 u
from its target - closer than 4 u it keeps flapping (a chaser problem with a chaser
answer: hurdle it, SR-2)." Built: distance is the 3D `api.nearest_player` distance; both
bounds are inclusive (the document does not bound exclusivity - recorded as decided); below
4 u the seal never telegraphs, above 12 u it keeps flapping toward the target. WHY: the
4-12 u band is what makes the dash readable - the answer (jump on the bark) needs the
fixed line fixed from a readable distance, and inside 4 u the body is a hurdling problem,
not a dash problem. The "dash_line" telegraph's footprint is a radius-0 circle at the
seal's position, so SR-4's `no_targeted_telegraph` requirement (address me) is unaffected;
SR-4's scheduling gates are address me's and gin ichimaru's alone (D-067), so the seal
carries NO arbiter block. Telegraph-range inclusivity at exactly 4.0/12.0 u is [CONTESTABLE]
(the owner may prefer 4.0 exclusive / 12.0 inclusive).

### D-T-038-3 - telegraph and recover are stationary; recover is SR-5 tempo-shortened, the telegraph and dash are binding ticks (T-038).
The telegraph holds the seal still for 45 ticks (the dash line is drawn from a planted
body - a moving origin would detach the dashes from the telegraph source every frame) and
the 45-tick recover holds it still after the dash. Recover length is
`api.tempo_ticks(45)`, so overtime/Hunger tempo (the part of a speed multiplier the SR-5
ceiling removes) shortens it, bounded at TEMPO_FLOOR (0.6x, 27 ticks); the telegraph (45)
and the dash (60) are the T-083 binding ticks and are never shortened. The spec's "~1s
high-pitched cry before it attacks" (ENEMIES.md) is the telegraph + the bark on dash tick 0
(the VOIDWRAP_RUN replacement line); there is no separate cry cue (D-T-038-7).

### D-T-038-4 - seal audio cues `bark` / `flipper_flap`; flipper_flap is view-driven, bark is a 1-tick "bark" telegraph on dash tick 0 (T-038).
ENEMIES.md "New sound", verbatim: "actual seal barks (arf arf) on the dash, wet flipper
flaps while it moves." Cue names = file names (T-055's contract):
`assets/audio/enemies/seal/bark.wav` (fires on tick 0 of the dash; DESIGN.md section 5.9's
binding "bark on tick 0 of the dash") and `assets/audio/enemies/seal/flipper_flap.wav`
(one per flap cycle - the T-083 anim block's 9 ticks per frame / 6.6 Hz telegraph flap
cadence) while flapping or telegraphing. The flap is AMBIENT and is driven by the view on
the sim tick counter (no sim telegraph spam); the bark is a 1-tick "bark" telegraph from
the behavior - the same cue channel the meow uses, zero-radius footprint, never a damage
telegraph. Both hooks no-op silently until T-055 synthesises the placeholders (TBD.md rows
30/31). [CONTESTABLE]: the owner may prefer both cues on the sim telegraph channel.

### D-T-038-5 - burst_ceiling 1.0 with no telegraphed sprint; the dash never routes through FloatBody (T-038).
The seal has no Zoomies-style sprint. The field is kept at 1.0 for cfg/FloatBody parity
(the runtime requires consistent kinematic data) and is unreachable: the dash runs on its
own fixed 20 u/60 ticks kinematics and FloatBody is only stepped while flapping. WHY:
SR-5's burst bound exists for telegraphed sprints; the seal's attack is its dash, and it
beats 9.0 u/s exactly because the section 5.9 numbers say 20 u in 1.0 s - classifying it
as a burst would silently paper the attack into the 1.00 ceiling.

### D-T-038-6 - the dashed red telegraph VFX: 0.5 u dashes every 0.9 u along the fixed 3D line, additive #FF2A2A, brightening 0.35 -> 0.95 alpha across the 45 ticks (T-038).
`game/view/seal_view.gd` builds one thin box per dash (0.5 u long, 0.08 u thick) along the
fixed segment from the telegraph event's `dash_line` parameter, each aligned with an
X-axis basis along the line (never flattened onto the ground - DESIGN.md section 5.9 draws
the dashes along the 3D line), fog-exempt, unshaded additive #FF2A2A (the T-083 block's
color and dash_segment_u 0.5), and re-alphas the shared material as the telegraph counts
down (the block's `brightens_over_ticks: 45`). The attack state alternates
dash_00/dash_01 every 4 ticks (the block's ticks_per_frame, fps 15.0) while the TBD
mouth-open stand-in (idle_00) is held underneath; telegraph and recover hold idle_00;
spawn is the common 30-tick fade. GAP 0.4 u between dashes is a draw contract no document
states - SPEC GAP, reasoned from readability at fog distance - [CONTESTABLE]. The TBD
frame substitutions follow TBD.md row 24 and were NOT re-derived from the PNGs (the anim
block is authoritative).

### D-T-038-7 - the ENEMIES.md seal line and the DESIGN.md section 5.9 paragraph are the same attack; no separate cry exists (T-038).
ENEMIES.md: "~1s high-pitched cry before it attacks. VOIDWRAP_RUN: the cry is replaced by
a real seal bark when it dashes - it opens its mouth and flaps." DESIGN.md section 5.9
(FINAL): "Attack: telegraph 0.75 s (dashed 3D line, mouth-open frame) -> bark on tick 0 of
the dash + dash 20 u in 1.0 s along the fixed line -> idle 0.75 s." Built: the 0.75 s
telegraph is the wind-up (mouth-open frame held, red dashes), the bark fires on tick 0 of
the dash, the cry does not exist as a cue. WHY: the VOIDWRAP_RUN replacement sentence names
exactly one audio event for the attack (the bark); a second cry would double the tell and
contradict the 1:1 VOIDWRAP_RUN mapping of the section. Not a PARKED row - the two
documents agree once section 5.9's wind-up is read as the cry's carrier.

### D-T-038-8 - the lobby exhibit needed no new wiring; test_content.gd counts 2 -> 3 enemies / 89 -> 90 content_ids (T-038).
`antechamber._exhibit_enemy` reads each enemy slot's sprites.json live, so the seal's
exhibit (billboard from the T-016 TBD sheet, body scaled to the 1.6 u exhibit height, panel
lines from enemy.json's behavior/counter_play) is live the moment the content lands -
verified headless: the sheet parses, its "idle"/"dash" animation blocks load, and the full
view cycle (spawn -> telegraph with the dashed line -> bark -> attack -> recover) runs
clean. `test_content.gd`'s launch counts move 2 -> 3 enemies and 89 -> 90 content_ids,
exact, not loosened (comments name T-021/T-030/T-038; D-T030-6's contract).

### D-T-038-9 - the 1.2 u jump window is asserted against the engine's tick-quantized arc (T-038).
DESIGN.md section 5.9 and FLEET_PACK express the answer as continuous physics (y(t) =
12.0t - 16.0t^2 > 1.2 u between 0.12 s and 0.63 s after take-off, a 0.51 s window). The
controller (sim/controller.gd) integrates at 60 Hz with semi-implicit Euler and applies
the variable-height jump cut on release, so the REALIZED hold-jump window is ticks 7..35
(feet above 1.2 u), ~29 ticks (~0.48 s), apex 2.15 u - measured headless from the running
controller, not derived (the mirror of D-T030-8 for the seal's 1.2 u threshold). The test
asserts the realized window +/-1 tick and ~0.51 s window length +/-1 tick instead of the
unreachable continuous values, and the end-to-end "jump on the bark" survival through the
fixed dash line. WHY: a test against 0.12/0.63 s continuous would encode a jump the
engine never produces. [CONTESTABLE], same shape as D-T030-8.
### D-T-033-1 — CONTESTABLE — Egoist burst size: "+1 ball per stack" vs the ticket's "up to 7 balls arrive 3+3+1".
DESIGN.md section 7.1 (egoist row rule column) says "+1 ball per burst per stack" with max stacks 2
→ 4 or 5 balls → plans 3+1 / 3+2. Its own consequence column AND this ticket say a 7-ball Egoist
burst arrives as 3+3+1 (research/fable-enemies.md F6/R10 also say "5 or 7 balls" with "+2 per
stack"). The two cannot both bind (3 + 1×2 = 5 ≠ 7). Built: the burst size is DATA in
enemy.json stats — `volley_balls` 3 and `balls_per_stack` 1 — so the rule text holds as shipped and
the 7-ball plan stays reachable through the same code path (`volley_plan(7)` = 3+3+1, asserted in
the ticket's test); a one-word owner ruling flips `balls_per_stack` to 2 with no code change. The
volley shape itself (≤ 3 balls per volley, 0.75 s between volleys start to start) is D-064 FINAL
and untouched either way.

### D-T-033-2 — CONTESTABLE — Isagi relocation target floor: the 25 u body floor applies to relocation too, no 60 u cap.
DESIGN.md section 5.4 says "every 12 s he relocates to the `perch` anchor nearest the player with
line of sight" and names no minimum distance; the 25 u floor and the 60 u preference are written
only for the D-056 SPAWN rule. Built: relocation picks the nearest qualifying perch but a
candidate must still sit ≥ 25 u from the player (the spawn rule's MIN_PLAYER_DIST), and the
60 u preference is NOT carried over — nearest means nearest. WHY: relocating the body onto or
next to the player is unanswerable under the one-hit rules (research/fable-enemies.md section 4
answerability standard); the 25 u is borrowed from the spawn rule, not a change to D-056 —
relocation is not a spawn and the spawn fallback order stays exactly D-056. Tie-break: lowest
anchor index; each copy skips its copy_index in the sorted candidate list so copies spread
deterministically without reading sibling bodies (SR-3 has no sibling query on the section 12
Api surface) — a copy offset, not a distance edit.

### D-T-033-3 — CONTESTABLE — "Flat in-line lane" wind-up suppression numbers (T-070 item 10 / R10).
research/fable-enemies.md section 4 item 3 (adopted by T-070 R10, mitigation would not touch
D-056): Isagi does not begin a wind-up while the horizontal line from him to the player runs
along a walkway axis with less than 2 HU of total height change — he relocates instead, with the
relocation timer cut to 4 s (240 ticks). No document defines "walkway axis" numerically. Built:
he is on a `lane` anchor; the lane's axis is the row/column of FELLOW lane anchors sharing his
integer x or z within 24 u (a walkway piece is grid-aligned, so its axis is an x or z axis);
"runs along" = the horizontal unit direction to the player has dot ≥ 0.9 with that axis (a
2-wide walkway is 1.0 u to a side at a 5 u sight distance: 1.0/5 = 0.2 → cos ≈ 0.98 along it,
so 0.9 is generous to the DANGER side); height change |player feet − his feet| < 2.0 HU (the
section 5.4 "2 HU step" that answers a ball line). On the intersection of two axes (both x and z
have lane members) no axis is taken and no suppression applies — a crossing has side-exit
options. He still fires across paths, down onto them, and along stepped ones (Δy ≥ 2 HU), and
once a burst has begun it is never aborted mid-way (only its BEGIN is gated).

### D-T-033-4 — CONTESTABLE — Isagi's hit cylinder comes from enemy.json stats, not the TBD sheet's body_rect.
SR-2 (D-065) fixes Isagi's body at 1.8 u tall, 0.7 u hit diameter. But the T-016 pipeline derives
the body cylinder from the sprite frame's body_rect (cylinder_from_sheet), and Isagi's frames are
TBD placeholders with a square 224/256 bbox → it would derive height 1.8, width 1.8, diameter
1.44 — double the spec's 0.7. Built: enemy.json stats carry `world_height` 1.8 and
`hit_diameter` 0.7, and the behavior sets its row's height/diameter from those stats in
on_spawn (the frame sheet drives only the render; the transparent padding is anyway never
solid). WHY: the headless tests must assert the frozen SR-2 cylinder, not whatever size the
placeholder art happens to have. When the real art lands, the pipeline should emit body_rects so
that 0.8 × width ≈ 0.7 u (width ≈ 0.875 u), or the loader must scale — flagged for the art wave.

### D-T-033-5 — SPEC GAP — Isagi's sound file names exist in no document.
ENEMIES.md "New sound" names the DESIGN ("direct shot voice lines, Isagi shoot sae math final
shot gun-shot sound when shooting"), never file names. Placeholder hook names are derived from
that sentence and live in the view's sound-hook table: `isagi_voice_direct_shot` (the burst's
audio cue, at wind-up start), `isagi_shoot_sae_math_final_shot` (at each release flash),
`isagi_gunshot` (per ball release, layered under the SAE line). No audio files exist; the hooks
are named constants on the view side, wired to the anim-block states, and the TBD.md row records
them. Adding the real files later is a content drop, not a code change.
### D-T-034-1 - [CONTESTABLE] The nuke's LOS ray origin: 12 u high, 20 u out, direction fixed per salvo (T-034).

DECISION (T-034): no document states where the nuke's line-of-sight ray is traced from, so the
behavior fixes it per salvo: a point 12 u above the court, thrown 20 u from the ring centre in an
enemy-rng direction held for the whole salvo (`lock_height` 12.0, `tell_distance` 20.0 in
enemy.json). GAMEPLAY REASON: a per-salvo fixed direction means the player cannot cheese the break
by strafing - only real overhead cover (or leaving the sphere, parked row 5) breaks the ray; 20 u
out keeps the ray's cells near the player's own position so cover the player can actually run to
matters. 12 u puts the ray above the 3-4 u slab heights (it is "sky sight"), so only tall stacks
break it. Both numbers are [CONTESTABLE]; the test asserts the MODEL (30-tick break, 120-tick
relock, per-salvo fix), never the 12/20 constants.

### D-T-034-2 - The locked ring and the missile descent share the same 90 ticks; detonation on tick 240 (T-034).

DECISION (T-034): DESIGN.md section 5.5's "the same 90 ticks as the locked ring" is implemented as
ONE phase: the locked telegraph row fills rim-inward over 90 ticks while the missile descends the
same 90 ticks from 30 u above the ring centre (1/3 u per tick), the blast resolving on tick 240
(150 tracking + 90 locked) - asserted +/-1 tick. The drawn explosion one-shot is the anim table's
own 24 ticks (T-083), drawn over the first 24 ticks of the 300-tick pause; nothing changes the
pause's length.

### D-T-034-3 - A harmless expiry starts the 300-tick pause, then a FRESH salvo with a restarted budget (T-034).

DECISION (T-034): D-064's "then a fresh salvo" is read as a full restart of the salvo's budget
clock: the expired salvo's clock stays at exactly 360 (expired), the 5.0 s pause runs, and the
re-tracking calls the clock's start() - legal ONLY because the clock is expired (start() on an
ACTIVE clock is a no-op, which is what makes the 120-tick relock restarts of a LIVE salvo never
reset the budget). The second salvo's first tracking tick is the first tick of a new 360-tick
budget; the test asserts the retrack at pause+300 and the fresh clock at 0/1. The fresh salvo is
the same behavior, not a harder one - section 5.5 has no escalation.

### D-T-034-4 - Anim mapping: the body shows attack_descent during the shared 90; a real blast shows attack_explosion, a harmless expiry stays recover (T-034).

DECISION (T-034): the anim row's state per phase is telegraph_tracking (track),
attack_descent (lock - the FALLING MISSILE is the body; the locked fill itself is the sim's
telegraph row the view renders), recover (the 120-tick relock - the table has no distinct
"broken lock" state, so the row holds recover there: nothing new on screen), attack_explosion
(pause, only after a REAL blast). A harmless expiry carries recover through its pause: no
attack_explosion draws for an expiry that killed nobody - the explosion state's own "starts:
tick 90 = the tick the 5 u sphere resolves" note ties it to the missile's arrival, which never
happened.

### D-T-034-5 - The three audio hooks are named per ENEMIES.md's "New sound" line, as anim-block effect params (T-034).

DECISION (T-034): ENEMIES.md's nuke "New sound" names three cues: the lock-on beep speeding up as
the missile closes (2 -> 8 Hz), the rocket-booster roar while it descends, the deep boom on impact.
They are carried as `audio` params on the three anim states' effects: telegraph_tracking ->
`lock_on_beep`, attack_descent -> `rocket_booster_roar`, attack_explosion -> `impact_boom`, each
with an audio_note marking it a TBD hook (synthesis is a later ticket's asset work; the NAMES and
their state wiring are this ticket's deliverable, asserted by test).

### D-T-034-6 - Content scoreboard grows 1 -> 2 enemies, 88 -> 89 content_ids (T-034).

DECISION (T-034): test_content.gd's registry counts are a scoreboard of what exists, not a frozen
contract: the nuke's enemy.json is the second enemy the registry boots, so enemies 1 -> 2 and
content_ids 88 -> 89. Every further enemy ticket makes the same one-line move in its own diff.
Nothing else in test_content.gd is touched.

### D-T-034-7 - The behavior's cfg contract: the enemy.json stats block, flatted one level (T-034).

DECISION (T-034): the numbers reach the behavior as a plain cfg dictionary - the `stats` block of
content/enemies/nuke/enemy.json flatted one level (the production loader that does the flatting is
pending elsewhere; the behavior reads only `row["cfg"]`, so the wiring side can slot in unchanged).
The T-034 test builds its cfg from the REAL enemy.json file (JSON.parse_string of stats), never
from a test-local copy: the timings and numbers asserted are the deliverable data's own.
### D-T084-1 - The frame rule: tick_ranges first, then ticks_per_frame; frame-less states hold the last shown frame (T-084).

DECISION (T-084): enemy_anim.gd implements the section 1.0 rule `frame = table[state][
(ticks_in_state x fps) / 60 ]` as: a state's `tick_ranges` win when present (the range whose
[start, end] contains ticks_in_state, inclusive; past the last range a one-shot holds its last
range's frame), otherwise index = floor(ticks_in_state / ticks_per_frame), wrapping on loop
states and clamping on one-shots. tpf = null means "the state shows its first spec frame for as
long as the sim keeps it" (a single-frame state, e.g. ben's smoke). A state with NO frames of its
own (kiwi's contact-kill attack, the nuke's explosion, the larper's detonation) HOLDS the last
frame actually shown - a billboard never blanks out - and the hit shape follows that held frame.
WHY: the sim owns time; the view is a pure function of (state, ticks_in_state), so an attack
frame lands on its event tick with 0 ticks of error and a bleached-out sprite is impossible.

### D-T084-2 - A finished looping state's wrap frame never becomes the held frame (T-084).

DECISION (T-084): when a looping state has a total_ticks and the counter reaches it, the frame
computed for that tick (the wrap) is not recorded as "last shown", because the sim switches state
on that exact tick and the frame was never displayed. One-shot states keep recording past their
total: their clamped hold frame IS legitimately shown if the sim lingers. [CONTESTABLE] modeling
choice; the test drives every state for exactly its binding tick count, where both readings agree
except at the switch tick itself. WHY: the nuke's 90-tick descent otherwise ends with the held
frame one step past the explosion's entry frame.

### D-T084-3 - Spawn-fade contact block: 30 ticks default, the block's own number when it states one (T-084).

DECISION (T-084): a spawn state blocks contact while `ticks_in_state < spawn length`, the length
taken from the state's fade params (`spawn_blocks_contact_ticks`, then `duration_ticks`,
then `ticks`), defaulting to 30 (SPAWN_FADE_TICKS, section 1.0 common fade). Eleven enemies use
the 30 default; address me uses its own [CONTESTABLE] 12-tick `fade_fast` (12), because its
table row is the more specific number and T-083 already encoded it. Only a fade-type spawn
(common_fade/fade/fade_fast) blocks: the nuke has no sprite (nothing to block) and gift Larper
is a slot occupant with no fade (D-T083-11). WHY: the deliverable's "30 ticks" is the common
rule; the one deviating enemy is data-driven and explicitly marked contestable in the spec.

### D-T084-4 - Billboard effects are five shader parameters, computed from the same sim tick (T-084).

DECISION (T-084): effect_params() returns the uniform contract {flash: Color (additive white),
tint: Color, scale_pulse: float, shake: Vector2 in u, alpha: float} for the current state and
tick; none of them ever change frame_index() or body_rect(). Effect math kept minimal and
spec-stated: common_fade/fade/fade_fast lerp alpha and scale over their ticks; scale_pulse is
triangular from -> peak -> to across the state's ticks (peak from `peak`/`scale_to`, duration
from `ticks` or the state's total - kiwi 1.0 -> 1.12 -> 1.0 over 12, toucher 1.0 -> 1.15 over
18); white_flash is a full-white add decaying over its 6 ticks (ben's arrival); dim is a flat
brightness tint (isagi's 0.7 recover); rumble is a 0.05 u alternating shake (YOU?!). The
parameters are data consumed by the billboard shader; wiring them into billboard.gd's material
is a later view ticket - the contract and the values are proven by test_anim_sync.gd here.

### D-T084-5 - The attack event lands on the state-switch tick; extra volleys are event ticks too (T-084).

DECISION (T-084): the player exposes attack_event(sim_tick) for the gameplay layer; it records
the sim tick and the frame shown on that very tick (0 ticks of error - the state switch and the
frame pick are the same tick, never one late). The scripted sim in test_anim_sync.gd fires the
event on the entry tick of each enemy's attack state (the cue's end), and for isagi also on
attack-local ticks 9 and 18 (the global 81 and 90 of the 0.15 s-apart volley), asserting the
shoot frame holds through all three. The binding telegraph counts the test asserts against the
anim blocks are its own transcription of DESIGN.md sections 5.1-5.12 (kiwi 12, coil 36, ben 75,
isagi 72, nuke 150+90, YOU 90, larper none, toucher 18, seal 45, address me 300, Claude
strings 36, gin 120) - the blocks were re-proven, not trusted.

### D-T-039-1 [CONTESTABLE] - address me's body contact does NOT kill (D-065 FINAL wins a ticket deliverable) (T-039)
T-039's deliverable 5 asks for a test asserting "its body contact kills". DESIGN.md §5.2 (SR-2,
D-065, FINAL) says the opposite, three times: the roster table gives address me height 2.5 and
diameter "-" with the consequence "no body contact; it is a countdown, not an obstacle", D-065
restates it verbatim, and DESIGN.md §5.10 (its numbers paragraph) defines exactly one kill: the
5.0 s expiry. ENEMIES.md's own section grants one kill path too ("if you do not stand still, it
explodes and kills you") and no other. D-065 is marked FINAL, so per the standing ruling the
FINAL reading is built instead of the deliverable: `contact_kill` is FALSE in the row (the
runtime's plain body-contact pass skips it, the thicc ben precedent), the behavior never kills on
overlap, and the only killing blow is the countdown expiry (D-ADDR via the cfg `death_code`). The
kill test runs Last Light spent (D-057) all the same. The ticket/FINAL clash itself is logged as
PARKED.md row 6 for the owner to rule; no other FINAL or ENEMIES.md passage was edited to make
the ticket's wording pass. WHY [gameplay reason]: a countdown the player must out-wait, not a
body they must avoid; a contact kill would make the spawn 6 u ahead of a committed player a
non-answerable coin flip, which the SR-4 gate exists to prevent.

### D-T-039-2 [CONTESTABLE] - stillness is read from the controller snapshot nearest_player returns (T-039)
DESIGN.md §5.10: the player must show "no movement/jump/ability input and speed < 0.5 u/s on all
axes, held for 1.5 continuous seconds". The section-12 Enemy API returns, per player, only
{index, dist, x, y, z, vx, vy, vz} - there is NO button channel a behavior may read, so the
"no input" clause is not observable as buttons through the API. Built reading: stillness = all
of |vx|, |vy|, |vz| < 0.5 u/s. This is sufficient in practice because every input the game can
produce perturbs at least one axis past 0.5 u/s within a tick (jump 12.0 u/s, glide fall cap
2.0 u/s and glide horizontal 10.0 u/s, dash, 90 u/s^2 ground accel), so a "still" player who
taps anything is caught within a tick. `still_t` counts continuous still ticks; any failing tick
resets it to 0; 90 (1.5 s at 60 Hz) wins the episode. WHY [gameplay reason]: the rule must be
machine-checkable from one deterministic snapshot; inferring intent from buttons would change
nothing observable and would invent state the API does not carry.

### D-T-039-3 [CONTESTABLE] - the 5.0 s expiry kill has no distance limit (T-039)
DESIGN.md §5.10: "5.0 s expire first -> explode frame, boom, kill." No radius, range, or
falloff is stated anywhere for the blast. Built reading: when the countdown expires, the
targeted player (nearest at the appearance tick, stored on the row) is killed regardless of
where they are - D-ADDR through `api.kill` with the cfg `death_code` (the runtime passes it
verbatim). This is deliberately NOT a radius-limited AoE and NOT a "only if still close" rule.
WHY [gameplay reason]: inventing a radius the documents never state would create an unstated
escape ("run far enough") the design's whole 1.5 s-stop structure exists to prevent; the
punishment for failing to stop is exactly the stop's failure - it fires when the countdown ends,
nowhere else, with no geometry to hide behind.

### D-T-039-4 [CONTESTABLE] - the return cadence: uniform(30,45) s, -5 s per extra vote beyond the first, hard floors (15, 30) s (T-039)
DESIGN.md §5.10: "Returns every 30-45 s (-5 s per extra vote, min 15-30 s)" and the §5 vote table
row 10 ("only one exists; each extra vote -5 s on its return interval"). Built reading: on each
episode resolution the next return waits a row-local timer drawn uniform in ticks
[1800 - 300 x (votes-1), 2700 - 300 x (votes-1)] clamped below to (900, 1800) - 1 vote [30,45] s,
2 votes [25,40] s, 3 votes [20,35] s; the "min 15-30 s" clause is the absolute floor and is
unreachable at the roster cap of 3 votes (kept as an enforced clamp for any future cap raise).
"extra vote" is read as votes beyond the first. Vote count arrives stamped in cfg["votes"] by the
engine at plan time (nothing else in the section-12 API carries it; absent, 1). The timer starts
at the episode RESOLUTION tick (the leaves/attack tick), not at appearance. The first appearance
never happens before level tick 600 ("never in the first 10 s of a level"). WHY [gameplay
reason]: the cadence is the pacing knob the owner set for the only enemy that makes you stop;
clamping to a fixed band keeps every vote tier honest (more votes genuinely returns it sooner)
without ever breaking the 10 s level-entry promise.

### D-T-039-5 [CONTESTABLE] - between episodes the body is parked at y = 1000.0 u (T-039)
The arbiter's `no_enemy_body_within` requirement counts EVERY body in `world["enemies"]`,
including this row's own mirror entry - parking it anywhere near the level could make its own
gate unsatisfiable forever (the player may camp the spawn tile), and §5.10 promises it still
returns every 30-45 s. Built reading: on spawn and at every episode end the row (and its
mirror, via `api.sync_body()`) is moved to AWAY_Y = 1000.0 u; the appearance teleports it 6 u
"in front of the player" (D-T-039-13) and the aftermath (leaves/attack) plays there before it is
parked again. 3D distance from any feet point at level heights is therefore always > 12 u;
`contact_kill` is false so the mirror never bluffs a melee. WHY [gameplay reason]: the gate can
never veto its own enemy with its own parking spot; 1000 u is far enough that no jump, glide or
void charge changes the answer.

### D-T-039-6 [CONTESTABLE] - the countdown travels as row state + pending=["address_me"]; yields_to = ["address_me"] (T-039)
The stillness countdown is this row's own state, never a telegraph (the runtime never prunes its
telegraph list, so a 300-tick entry registered there would pin `no_targeted_telegraph` for every
later appearance of this row and for every yielder to `address_me`, forever - brisker is never
pruned). The row gates itself on every waiting tick with `api.arbiter_gate(pending)` where
`pending = ["address_me"]` while its own countdown is live, `[]` otherwise; the id is exactly
"address_me" as the ticket pins for the yields_to contract. `"yields_to": ["address_me"]` in the
arbiter block: while the countdown is live, a gate re-evaluation reports `deferred: true` (the
id is live through the pending array) and the appearance call defers to the first free tick
after the countdown. gin (T-041) yields_to the same id. WHY [gameplay reason]: a countdown must
be answerable without leaking a footprint; and deferring a gate re-check mid-countdown can only
ever say "after the countdown" - which is exactly when this row may legally act again.

### D-T-039-7 - "in front of the player" = the player's last nonzero horizontal heading (T-039)
The section-12 API returns no facing vector, so the row tracks its own `face_x/face_z`: updated
to the normalized horizontal velocity whenever the player moves at > 0.5 u/s, initialised to the
controller's own default facing (0, 0, 1). The appearance teleports the row to the player's feet
+ facing x 6.0 u, feet at the player's feet height (SR-1 easing is irrelevant to a teleport;
contact_kill is false, so no tile requirement applies to an apparition). WHY [gameplay reason]:
"appears 6 u in front of you" is the stated opening the counter-play is built around; the row
mushrooming behind the player would answer a spec that names the direction.

### D-T-039-8 - the arbiter block is the D-067 quartet, nothing else (T-039)
`arbiter.appear_requires`: [{"no_enemy_body_within": 12.0}, {"no_targeted_telegraph": true},
{"player_grounded": true}, {"not_on_glitched_floor": true}] - the four D-067/SR-4 requirements
verbatim, DATA in enemy.json, vocabulary untouched in sim/enemy_arbiter.gd. It appears only on a
tick where all four hold (plus the level-tick-600 and return-timer gates, D-T-039-4/5);
`yields_to` as D-T-039-6. WHY [gameplay reason]: SR-4 (D-067) is FINAL; the stop-demand must
never land inside a chaser, a ring, a patch, a jump or a glitched tile.

### D-T-039-9 - enemy.schema.json's arbiter block relaxed to requirement objects (T-039)
`core/schemas/enemy.schema.json` described `appear_requires` items as `{"type": "string"}`, but
`sim/enemy_arbiter.gd` (T-072, FINAL-adjacent, pinned by test_arbiter.gd/test_arbiter_api.gd)
evaluates Dictionary requirements like {"no_enemy_body_within": 12.0} and silently skips anything
that is not a Dictionary - a string-bodied appear_requires would have gated nothing while looking
as if it gated. The schema's `items` now accept `["object", "string"]` and its description points
at the arbiter for the vocabulary; `yields_to` stays strings-of-ids. No enemy folder, the anim
checker or the enemy anim view were touched; the registry boots again on the real content. WHY
[gameplay reason]: unknown-vocabulary gate-as-yes is how a scheduling gate becomes a lie.

### D-T-039-10 - audio hooks: spawn_trumpet, rumble_build, explode_boom (T-039)
ENEMIES.md "New sound" (verbatim): "elephant trumpet on spawn, low rumbling build-up during the
5 seconds, massive boom on the explode frame." Three hooks, named as the view raises them (view =
sim-tick-driven transitions, never wall-clock): `spawn_trumpet` (entering the spawn state),
`rumble_build` (entering the telegraph/countdown state, a 5 s low-rumble synth), `explode_boom`
(entering the attack state on the kill tick). Synthesis-quality placeholders, file stems = hook
names (T-055's contract); `tbd_audio: true`; TBD.md row 32. WHY [gameplay reason]: the trumpet is
the tell; the rumble is the countdown's clock; the boom is the verdict - all three are the
ENEMIES.md cue design, none can drift the sim.

### D-T-039-11 - the countdown is never registered as a sim telegraph (T-039)
`api.telegraph` is not called for the stillness countdown: the cue owns no footprint (a 5 u
rumble covers nothing the telegraph shape language can express without lying) and the runtime
never prunes `rt.telegraphs` - a 300-tick circle at the caster's plane would sit in the list
forever, false-blocking this row's later appearances (its own `no_targeted_telegraph`) and
gatekeeping every yielder to address me forever. The view drives its countdown ring / stillness
arc off `anim_state` / `anim_state_t` / the row's stillness counter instead; the T-083 anim
block's telegraph row is rendered as the view's countdown_ring effect and nothing else. WHY
[gameplay reason]: a telegraph in the shared list is a promise about a footprint; this cue makes
no footprint, so it must not make the promise.

### D-T-039-12 - the explode kill resolves on the exact tick the countdown expires (T-039)
The anim block pins `kill_on_tick` = 300 (the tick the rumble ends); the behavior kills on the
same tick its countdown reaches 0 - `countdown_left` hits 0 -> `api.kill(target_index, ...)`
which derives `D-ADDR` from the cfg `death_code` verbatim and attributes `"address me"` as the
killer string - and the 24-tick `attack` state after it is purely presentational (the explode
frame + 6-tick flash). `leaves` (stillness achieved) resolves the same way minus the kill, puffs,
parks away (D-T-039-5) and schedules the return cadence (D-T-039-4). WHY [gameplay reason]: the
boom IS the deadline; any later tick would be the game punishing a player who already answered.

### D-T-039-13 - the appearance teleport honours the fallback order at spawn, the "6 u in front" rule per episode (T-039)
The D-056 spawn rule still runs at the 6 s spawn tick (`preferred_kind` "none" -> fallback (c)):
rows spawn far from the player and park at AWAY_Y until the gate opens (D-T-039-5), so the initial
D-056 position is never a rendering or contact concern. When the gate opens the row teleports to
the player's feet + facing x 6.0 u (D-T-039-7), `api.sync_body()`, shows the spawn state (12
ticks) and starts the countdown. The appear rule wins over `preferred_kind` for the actual
episode, exactly as the spec's preferred-kind table note states for this row ("appears 6 u in
front of the player"). WHY [gameplay reason]: step (c) exists so every planned body has a legal
initial slot; this enemy's fight starts when the trumpet sounds, not when the plan executes.

### D-T-039-14 - roster entry shape, the exhibit lines and the content-count bump (T-039)
min_level 9 / max_votes 3 (the §5 vote table, row 10); `vote_effect` "only one exists; each extra
vote -5 s on its return interval"; `anchor_kinds` [] and `preferred_kind` "none" (the
preferred-kind table, both); `contact_kill` false top-level and mirrored in stats (D-T-039-1);
`behavior` / `counter_play` / `tell` live top-level (the thicc ben precedent - the antechamber's
panel reads them from the doc root); counter-play "stop at once - do nothing for 1.5 s of the 5.0
s rumble; it never arrives while a chaser, ring, patch, jump or glitched floor would make
stillness lethal (SR-4)"; tell "elephant trumpet on appearance; a low rumble building over the
5 s". test_content.gd bumps enemies 5 -> 6 and content_ids 92 -> 93 (both counts asserted; no
threshold weakened). WHY [gameplay reason]: the panel is the only place the counter-play is
taught before the fight; the roster count is what the launch content promises.

### D-T-037-1 - [CONTESTABLE] The toucher's burst ceiling is 0.75, its own pursuit ceiling (T-037).
DECISION (T-037): DESIGN.md 5.8's pursuit line - "pursuit ceiling 0.75 - its own base
speed, so it never speeds up under any multiplier" - is read to cover bursts too: the
row's cfg carries base_speed 6.75, pursuit_ceiling 0.75, burst_ceiling 0.75, and the
behavior never calls begin_burst(). WHY [gameplay reason]: 5.8's own sentence says NO
multiplier may speed the finger up (a glitched player at 7.2 u/s still gains 0.45 u/s,
SR-5); a 1.00 burst ceiling would let a future script-curse sprint it at 9.0 u/s and
invert exactly that race. Zoomies is kiwi's curse, so nothing reads burst_ceiling
today; if the owner ever grants the toucher a burst, this is the data row to change.
### D-T-037-2 - [CONTESTABLE] "Infects all tiles within 3 u below it" is tiles whose centre sits within 3.0 u of the finger and whose top is at or below its feet (T-037).
DECISION (T-037): the implementation reads api.tiles_in_radius(feet, 3.0) (the level's
deterministic tile-index order) and drops every tile whose top is above the finger's
feet (+1e-6: its own feet-level floor counts as "below"). WHY [gameplay reason]: 5.8
closes routes with the patch (a glitched 2-wide walkway is a wall), which is a
horizontal area around the finger's column, not a vertical shaft under it; 3.0 u on
the 1-u grid is up to 29 tiles - the 60-tile cap then bounds the trail. A
vertical-column reading (only the tiles under the finger) would leave the finger
harmless on approach and make the terrain section's "glitched 2-wide walkway"
impossible. ON A TILE-ALIGNED POSITION the radius is exact (29 flat-floor keys); a
mid-flight position yields whatever the radius clips - that is the reading's shape.
### D-T-037-3 - [CONTESTABLE] The 60-tile cap frees seats oldest-first (FIFO eviction) (T-037).
DECISION (T-037): at the 60-tile cap a new infection evicts the oldest listed tiles
(row["glitched"] is in infection order) until the fresh ones fit, so the world never
holds more than 60 per toucher (5.8's "Max 60 glitched tiles per toucher") while the
patch keeps following its own finger. WHY [gameplay reason]: the alternative reading
(at the cap, add nothing until old tiles expire) disarms the enemy after ~4 infections
on open floor - a toucher that can never close another route, which contradicts 5.8's
"Pressure: it herds you" line. Ben's ring cleanse also frees seats (the touched keys
leave the world map, the behavior drops them next tick).
### D-T-037-4 - [CONTESTABLE] The 18 s tile life reads the level number from cfg "level_number" (T-037).
SPEC GAP: DESIGN.md 5.8 says the glitched tile "lasts 12 s (18 s from level 14)", but
the section 12 Enemy API exposes no level number and enemy_runtime.gd carries none.
BUILT: the behavior reads cfg "level_number" (the enemy.json stats block is the cfg
contract, the T-034 D-T-034-7 shape; the engine's plan/spawn caller - T-073 - supplies
the run's current level there). Default 1 (pre-14, 12 s). The stat key mirrors the
anim block's data (tile_life_s 12.0 / tile_life_s_from_level_14 18.0). WHY [gameplay
reason]: without a level source the two lives are indistinguishable; cfg is DATA, so
T-073 wiring the field needs no behavior edit. Flagged so the wiring ticket sees it.
### D-T-037-5 - The glitched-tile state is ONE world map: keys "x,z,y_hu" (collision.gd's tile_key); the slow/lock live with the controller (T-037).
DECISION (T-037): the toucher writes world["glitched"][key] = true with key =
"x,z,y_hu" (collision.gd tile_key's exact format - the controller's cur_key spelling),
and NEVER kills through a tile: the -20% run speed and the ability lock are the
controller's D-051 handling of that same map (sim/controller.gd run_speed /
ability_locked), asserted in tests directly. thicc ben's ring (T-032
cleanse_glitched_within) reads/maps the same keys, so the two enemies agree on what a
glitched tile is by construction - test_enemy_toucher.gd cleanses a full patch at
ben's 8 u and asserts a 1:1 drop. The section 12 Enemy API has no world-write call for
live tiles (D-T-035-8's shape): world["glitched"] is this enemy's OWN live surface,
reached through api.rt like coil's telegraph aging (D-T072-4) - flagged for T-073 to
formalise, not silently widened.
### D-T-037-6 - The pulse is the row's own telegraph footprint and the toucher ages it itself (T-037).
DECISION (T-037): the 18-tick glitch pulse is announced as a toucher_pulse telegraph
(circle r 3.0 at the finger, the so-far-to-be patch) ONE PER CYCLE, immediately after
5.8's infection countdown crosses 18 ticks, and the behavior AGES it each tick down to
0, never negative (coil's D-T072-4 pattern, the PARKED row 9 workaround) - the toucher
fires a pulse every 2.0 s for the whole run, so a footprint that never expires would
park a permanent circle on the player and block address me's SR-4 gate forever.
### D-T-037-7 - attack_infect is the infection tick itself; no duration is invented (T-037).
DECISION (T-037): the anim block records attack_infect as "on the infection tick"
(total_ticks null) and the deliverable forbids inventing a duration; the sim sets
anim_state "attack_infect" on the infect tick (anim_state_t 0) and returns to
idle_chase on the NEXT tick - the state is observable for exactly the one tick, and
the killing/ infecting work happens on that tick. test asserts the block's null
duration AND the sim's 1-tick observability.
### D-T-037-8 - Placeholder audio: one cue named for the ENEMIES.md New sound line (T-037).
DECISION (T-037): ENEMIES.md assigns the toucher exactly one sound - "corrupted
squelch - wet glitch gurgle and digital distortion as the floor becomes corrupted",
which the behavior fires as an "audio" event (cue "toucher_squelch") ONLY on ticks
where new tiles appeared (5.8: "an audio cue plays whenever new glitched tiles
appear" - a re-infect that adds nothing stays silent, asserted). No .wav ships here:
synthesis is T-055's scope (enemy.json stats: "audio_cues": ["toucher_squelch"],
"tbd_audio": true; TBD.md carries the row).

### D-T041-1 - The fade-in window is 15-25 u with bounds inclusive, ties to the lowest tile index (T-041). [CONTESTABLE]
DECISION (T-041): DESIGN.md section 5.12 says gin "fades in on a tile 15-25 u from the
player" but no document says whether either bound is inclusive, and none states a
tie-break. Built: both bounds inclusive (a tile at exactly 15 u or exactly 25 u
qualifies), and ties break to the LOWEST tile index in the level's tile order.
WHY (gameplay reason): inclusive bounds keep the rule's whole written band usable -
on a sparse level an exclusive bound could leave no candidate tile at all and push gin
onto the hub fallback every strike; the lowest-index tie-break is the same
determinism convention D-056's step (c) already uses, so two clients never disagree
about where he stands.

### D-T041-2 - The platform-tile-only filter is data-only on the current sim surface (T-041). [CONTESTABLE]
DECISION (T-041): D-072 says gin's fade-in tile is "always a platform tile (never a
walkway tile)", but the section 12 Enemy API returns tile rows that carry no
platform/walkway bit (api.tiles_in_radius yields {x, y, z, index} only; the piece
roles live in the generator, not in anything a behavior can read). Built: the 15-25 u
window (D-T041-1) over the tiles the API returns, farthest-from-the-player first, and
the FARDEST-TILE-OF-THE-SPAWN-HUB fallback implemented as the farthest tile within
HUB_RADIUS (12.0 u) of the level's first `open` anchor. WHY (gameplay reason): the
hub is the one place every level guarantees as a wide platform (D-025), so the
fallback reading preserves D-072's intent - his body never blocks or cuts the only
route home - without inventing level data the sim does not expose. The filter needs a
platform bit on the tile rows (or a behavior-readable piece-role list) to be enforced
literally; flagged for T-073 like the toucher's live-tile surface.

### D-T041-3 - "Never marks the beacon dais" = the dais cell is cut out of the marked patch (T-041). [CONTESTABLE]
DECISION (T-041): section 5.12 says gin "never marks the beacon dais" without saying
what happens when the player's tile sits within 2 cells of it (a centred 5x5 patch
would cover the dais). Built: the patch is carved as the full 5x5 block MINUS the
dais cell, and gin still strikes. WHY (gameplay reason): the dais cell itself is
never inside the lethal column, so the safe zone stays perfectly safe - but the four
tiles around it are taken away while the zone lasts, which keeps the pressure the
mechanism exists for ("rewrites the puzzle live") instead of granting a stand-still
immunity every time the player camps the dais. The alternative reading (skip the
whole strike while the player is dais-adjacent) would let the player park gin
indefinitely by standing 2 cells from the beacon.

### D-T041-4 - The void zone's column kill and the fade-back lift are row state; the boundary tick closes the zone before it kills (T-041). [CONTESTABLE]
DECISION (T-041): the zone's lethal column (anything whose tile is inside the marked
5x5 dies, any height, code D-GIN) and the fade-back lift (a player inside is pushed
straight up onto the returning surface) both live in the behavior's own row state
(row["patch"]), reached through api.kill/api.push - no sim tile edit and no new
surface call (the section 12 Enemy API has no world-write for tile solidity, per
D-T-035-8/D-T-037-6's precedent: flagged for T-073, not silently widened). The zone's
open tick (telegraph 120 + spear flight 18 = tick 138) and 600-tick life are the
anim block's binding numbers, asserted within +/-1 tick.
ALSO (order, found by the test): the boundary tick (tick 138 + 600 = 738) closes the
zone FIRST and THEN lifts anyone still inside - a fade-back tick is never a kill
tick. WHY (gameplay reason): without the reorder, the same tick's lethal pass would
kill a player standing on the vanished tile in the very tick the spec says they are
"lifted onto the surface" - the lift sentence would be dead text for the only player
it is written for. The impulse is an api.push straight up at 6.0 u/s (no document
states a magnitude; the controller's own gravity then lands them on the returning
tile).

### D-T041-5 - The strike cooldown is row arithmetic: 840 base, -180 per extra vote, floored at 300 (T-041). [CONTESTABLE]
DECISION (T-041): section 5.12's "Cooldown 14 s (-3 s per extra vote, min 5 s)" is
implemented as the row's own cooldown counter: 840 ticks (60 Hz) base, minus 180
ticks per extra vote beyond the first, floored at 300 ticks (5 s), and the countdown
runs from the tick the tiles finish fading back - the next fade-in (another 30 ticks)
sits INSIDE the window, i.e. the 840 is the whole wait between the end of one
strike's footprint and the start of the next mark, not the gap between marks.
WHY (gameplay reason): the anim block's recover row carries cooldown_ticks 840 /
per_vote -180 / min 300 as binding numbers, and "extra vote" is read as this row's
copies beyond the first (SR-3's copy model - each E-bay vote is a copy, the roster
row's vote_effect is "-3 s on his strike cooldown" per copy). Anchoring the window to
the fade-back's end (not the launch) keeps the promised "walk back in before he
strikes again" number honest: the player experiences 14 s of gin being unable to
REOPEN the patch after the tiles return, which is the sentence a player would act on.

### D-T-040-1 - [CONTESTABLE] "Floats at 4 u/s keeping within 20 u" is a leash, not a chase (T-040).

DECISION (T-040): Claude floats toward the nearest player only while FARTHER than 20 u
(horizontal), and holds position once inside; the leash closes whenever the player gains
distance and never follows the player inside 20 u. WHY: SR-2's consequence row for Claude is
"not hurdle-able; KEEPS ITS DISTANCE (within 20 u)" and section 5.11's answer lines all assume
the DISTANCE IS THE PLAYER'S TO MANAGE ("keep >= 6 u from Claude", "open platforms are bad"),
neither of which reads true for a body that always pursues. Section 5.11's only distance number
is 20, so the leash reads: chase while d > 20, hold while d <= 20. Consequence: a player standing
still at 20 u is outside the drums' 18 u reach but inside strings (24 u) and wind (28 u travel) -
standing still is still punished, so no escape-by-inaction hole exists. The pursuit ceiling
0.55 (SR-5, 4.95 u/s) still caps the closing speed; full multipliers clamp exactly like any
float body (asserted).

### D-T-040-2 - [CONTESTABLE] The drums' ring kill windows adopt D-T-035-1/-2's YOU?! readings (T-040).

DECISION (T-040): the drum ring kills when the player's FEET sit strictly inside
(ring feet - 1.5 u, ring feet + 1.0 u) and the horizontal distance is within 0.7 u of the
expanding edge (the 0.6 u band's half-thickness + the player's 0.4 u half-width). WHY: DESIGN.md
section 5.11 gives the ring's height (1.0 u) and speed (12 u/s) but no thickness and no kill
window; anim block's attack_drums says the band is "1.0 u tall translucent red band, AS YOU?!'S",
so the drums inherit YOU?!'s convention wholesale: the vertical window (jump clears at
feet > ring feet + 1.0; apex 2.25 u - "jump on the beat" holds), the 1.5 u reach below the feet
plane, and the 0.7 u radial window (the band + the player at 12 u/s crosses a body in
1.4 / 12 = 0.117 s ~= the answer window's 0.12 s - the only reading that reproduces the stated
crossing).

### D-T-040-3 - The strings telegraph freezes the sweep's start angle (D-069's fixed-line pattern) (T-040).

DECISION (T-040): on the strings bar's beat 1 the direction from Claude to the player is FROZEN;
the red 24 u telegraph line draws along it for exactly 1 beat; the beam then lifts off from
Claude's position at the TELEGRAPH'S END (the body may have drifted) and sweeps from the frozen
angle. WHY: the anim block's telegraph_strings row draws the line "at the sweep's starting
angle" - the warning must show the exact bearing the beam will start from (section 5.9's D-069
reading: a telegraphed line never re-aims); freezing the ORIGIN instead would draw the warning
at a bearing the beam would not take. The TELEGRAPH duration is exactly 1 beat at the current
tempo (36 ticks at 100 BPM; 23 at the Deadline's 160 - the anim block's own "shortened by the
current tempo").

### D-T-040-4 - [CONTESTABLE] The strings beam's sweep sense is counterclockwise; the origin's feet plane is frozen (T-040).

DECISION (T-040): section 5.11 says the beam "sweeps 120 degrees" with no sense named, so the
direction rotates counterclockwise in the xz plane (the perp (-dz, dx) - the +rotation sense the
wind homing's rotation also uses); the ray advances by the tangent-chord identity (multiplying
the unit direction into (1, tan) against its perpendicular) so no trig call ever runs in the sim
(section 13's "no sin/cos - lookup tables" rule); a scalar degree counter (exact addition) drives
the DURATION (120 deg over 4 beats, tempo-scaled) and stays within 0.01 deg of the vector's true
angle over a full sweep. The beam's vertical band (0.5-1.5 u above the origin's feet) and origin
are FROZEN at lift-off (D-069's never-re-aims reading); the kill rule per tick is: projection
along the ray inside [0, 24], perpendicular distance <= 0.75 + 0.4 = 1.15 u, body overlapping the
band, api.los from the band's mid-height to the player's centre clear (blocked by tiles and
props). Jumpable: feet at/above the band's top (origin feet + 1.5) are safe; the 0.26 s answer
window reproduces exactly: at the 0.8333 deg/tick sweep rate a body at 10 u sits inside the
1.15 u half-width for 2 x asin(1.15/10) / 0.8333 deg = 15.9 ticks = 0.265 s.

### D-T040-5 - The wind shot's wall death probes the trailing 0.3 u of its flight path; api.los cannot see a 0.117 u step (T-040).

DECISION (T-040): the shot dies on the FIRST tick whose trailing 0.3 u segment fails api.los.
WHY: a direct prev->now los call is blind - api.los marches at 0.25 u steps with `n =
int(seg/0.25) + 1` and a 7 u/s shot's step is only 0.1167 u, so n = 1 and the sample loop is
EMPTY (the endpoints are also never sampled); EVERY wall would be tunnelled (found by test: a
shot crossed a 6 u wall and killed behind it). The 0.3 u trailing window is always long enough
for the march to sample its midpoint every tick, so any wall or prop thicker than ~0.2 u in the
path is caught; the detection lags the touch by at most ~3 ticks (0.18 u at 7 u/s) and never
fires early - "dies on touching" stays honest within a shot width. Homing itself is exact: the
turn toward the player's centre uses the two precomputed 1.5 deg constants (cos/sin of the FIXED
per-tick step = 90 deg/s at 60 Hz - the section 13 lookup-table rule) and snaps when within one
step, so the sim never calls sin/cos and the turn rate is exact (asserted per tick).

### D-T040-6 - [CONTESTABLE] Plushie placement: the farthest tile in the 10-25 u band, 2 u apart; pickup at 0.9 u (T-040).

DECISION (T-040): every 25 s (1500 ticks; the clock re-arms only on a real placement - no
eligible tile this tick retries next tick) a plushie appears on the FARTHEST tile of
api.tiles_in_radius(player, 25) whose horizontal distance is in [10, 25] u (ties by tile order),
never within 2 u of an existing plushie; the "round-trip tile" nicety of section 5.11 cannot be
queried through the section 12 API (no reachability surface), so the farthest-band reading is
the substitute - on real levels the spawned-in tiles are the level's own walkable tiles. Pickup:
within 0.9 u horizontally and 2.0 u vertically of the plushie (the gift's 0.4 u pickup radius is
the nearest stated convention; 0.9u = the gift radius plus the player's 0.4 half-width plus a
0.1 grace; the spec states no number). Pickup = agitation - 35 floored at 0, the plushie is
consumed, and the row stamps last_pickup_tick / last_pickup_pos for the squeak-pop hook.

### D-T040-7 - The spawn fade blocks contact by zeroing the row's hit diameter for 30 ticks (T-040).

DECISION (T-040): on_spawn stores diameter_full and sets diameter_u = 0; _tick_one restores it
at age 31, so the framework's central contact check (which reads only the row's diameter_u)
cannot kill during the fade - the anim block's spawn row says "the body cannot touch or kill
until the fade completes" and view/enemy_anim.gd's contact_blocked() (ticks_in_state < 30)
matches tick for tick. Chosen over duplicating a fade counter inside the behavior because the
framework owns the KILL RULE; the row's diameter is the one lever the behavior legitimately
holds (D-T030-2 gave cfg hit_diameter the same role at spawn). The test asserts the overlap is
harmless through tick 30 and lethal at 31+ with code D-CLAUDE.

### D-T040-8 - The Deadline's 6/9/3-vs-4/6/2 gate dispute: the behavior was right, the test's window was contaminated (T-040).

DECISION (T-040): the first gate run read "deadline rings/shots/sweeps / 2 bars: 6/9/3, want
4/6/2" - exactly one extra deadline bar. A headless probe (rt.step trace over the window) showed
the behavior exact: with agitation pinned at 100, window beats 4..11 (bars 1-2) fire drums at
in-bar beats 0 and 2 (4 rings), strings at in-bar 0 (2 sweeps), wind at in-bar 0/1/2 (6 shots) -
4/6/2, as DESIGN.md section 5.11's "all three attacks every bar" requires. The extras were bar 0's
own hazards (2 rings / 3 shots / 1 sweep), still live in row["rings"]/["shots"]/["sweeps"] when the
counting window opened, because the test's settle loop runs pinned through bar 0 and _absorb_new
counts anything present at step 1. Fixed in the TEST ONLY (test_enemy_claude.gd): _absorb_new now
receives a real step counter and the assertion counts only objects BORN inside the window (birth
step > 1). No behavior number moved. Related: the cfg() mirror's "drum_beats" now speaks the
JSON's 1-indexed spec convention ([1, 3], as DESIGN's "beats 1 and 3" reads and as "wind_shots_beats"
[1, 2, 3] already did); the internal firing array stays 0-indexed ([0, 2]).
Also: the JSON-to-cfg mirror comparison is numeric (JSON parses 4 as 4.0; the cfg holds int 4) -
the JSON was never changed to satisfy a comparison.

### D-T073-1 - [CONTESTABLE] 0.0 pursuit/burst ceiling marks "not a floating body / no burst"; counter_play and tell are canonical at top level (T-073).

DECISION (T-073): DESIGN.md section 5 (SR-5) states pursuit ceilings only for the floating
bodies (kiwi cat 0.80, kitten 0.70, YOU?! 0.55, toucher 0.75, seal 0.60, Claude 0.55) and bounds
every telegraphed sprint (a burst) at 1.00 x base run speed for at most 3.0 s. coil, thicc ben,
Isagi, nuke, gift Larper, address me and gin ichimaru are not floating bodies, so their
enemy.json stats carry pursuit_ceiling 0.0 / burst_ceiling 0.0 - the pre-existing convention of
the merged files (coil, thicc ben, gift Larper, address me already shipped it; T-073 adds the
missing keys to isagi, nuke and gin). 0.0 there means "no pursuit", never a speed. The toucher
keeps its merged burst_ceiling 0.75 (a hair under its 0.75 pursuit ceiling - it has no burst
mechanic at all and no document states one for it); DESIGN.md's 1.00 bound is a maximum, not a
floor, so 0.75 complies. CONTESTABLE: one could omit the keys entirely for non-floaters instead;
0.0 was kept so tools/check_enemy_data.gd can assert presence and the 1.00 burst bound uniformly
across all 12 rows. Top-level counter_play / tell (and preferred_kind where T-073 adds it) are
canonical - view/lobby/antechamber.gd reads the top-level keys for the altar panel - while the
nested copies (coil stats.counter_play_line / tell_line, isagi stats.counters / stats.tell, nuke
stats.counter_play / tell_line, you stats.counter_play / stats.tell, and the nested
stats.preferred_kind of isagi / you / claude / gin / address_me) are behaviour and test mirrors;
they were kept verbatim, and the top-level copies added for coil, isagi, nuke and you carry the
same text. No behaviour number moved.

### D-T073-2 - [CONTESTABLE] gift Larper's merged tripmine model numbers (world_height 1.0 / body_height 1.0 / hit_diameter 0.8) kept under section 5's "carries no world size" prose (T-073).

DECISION (T-073): section 5's SR-2 prose says "The nuke has no body; gift Larper occupies gift
slots as the tripmine (section 3.3) - the roster's other rows carry no world size." gift_larper/
enemy.json's world_height 1.0 / body_height 1.0 / hit_diameter 0.8 are NOT an SR-2 body row: they
are the tripmine model box that the merged behaviour mirrors (content/enemies/gift_larper/
enemy.gd cfg()), the mine's lethal geometry is section 3.3's 0.9 u contact cylinder at any height
(contact_radius 0.9, contact_kill false), the view reads world_height from sprites.json (pinned
1.0, D-T-036-1), and game/tests/test_enemy_gift_larper.gd pins all three stats numbers and the
cfg<->stats mirror. DESIGN.md states no number for this row, so nothing was zeroed or deleted -
removing keys would break merged green tests for zero gameplay gain. CONTESTABLE: the owner could
still read "carries no world size" as "these keys must not exist"; if ruled so, zero the three
stats keys and the three cfg() constants together, and test_enemy_gift_larper.gd moves with them.
The nuke row complies with the prose as-is (world_height 0.0 / hit_diameter 0.0, no body).

### D-T073-3 - [CONTESTABLE] T-073's check script treats section 5's em-dash diameter as "no hit_diameter key" and parses the burst bound from the SR-5 prose at run time (T-073).

DECISION (T-073): tools/check_enemy_data.gd reads DESIGN.md itself (never a hardcoded number):
the SR-2 body-size table, the SR-5 pursuit-ceiling table (skipping the "kitten (The Litter)"
row - not one of the 12), the section 5 vote table (name / min level / max votes) and the
preferred-anchor-kind table are parsed from their markdown rows at run time, and any drift in
table shape (missing row, changed header, moved section) fails loudly. The burst-ceiling bound
("a telegraphed sprint (Zoomies) may reach 1.00 x base run speed") is parsed from the SR-5 prose;
absence of that sentence fails loudly too. address me's SR-2 diameter cell is an em dash, so the
check asserts the absence of (or 0.0 in) stats.hit_diameter rather than a value - no document
states a number for a body contact that does not exist for that row. The coil's SR-2 cell
("1.0 squashed / 2.0 extended") is parsed into the squashed and extended keys; its world_height
(the idle/squashed draw height, 1.0) is checked against the squashed row. CONTESTABLE: one could
require a transcription file with a hash instead of parsing markdown; parsing the live table was
picked so the check cannot silently pass against a stale copy - if the tables are restructured,
the script goes red, never quietly green.

### D-T050-1 [CONTESTABLE] — Slippery = the `friction` stat set to 0.4 while on the surface (R4 addendum, T-050; T-012 addendum).

DECISION (T-050): this ticket's dispatch addendum appends, verbatim: "Slippery = the `friction` stat set to 0.4 while on the surface (T-012 addendum)." It is honored, not re-derived: the two slippery curses (Wet Floor, Wet Trail) are script:true and are T-051's work; their effect attaches to the SURFACE (the "slippery" tile key in sim/collision.gd, friction x0.4 scaling on the 90 u/s^2 accel in sim/controller.gd, per the T-012 addendum), never to a global run_speed multiplier. No declarative curse is slippery, and none can be: `friction` is deliberately NOT in the closed stat list (core/stats.gd) and there is no `when: "on_surface"` in the closed `when` enum (always | black_phase | gold_phase | class:*), so a script:false curse cannot scope itself to a surface. Adding `friction` to the closed list with no consumer was rejected (T-013-style closed-list changes need a wired owner). The R4 addendum notes (fable-tickets.md section 4) mark their numbers [CONTESTABLE]; this one is recorded so the surface-scoped wiring is not mistaken for an omission.

### D-T050-2 — Declarative = "script" absent or false; the 11 declarative curses are complete through modifiers and their 7.2 rows check out (T-050).

DECISION (T-050): curse.schema.json makes "script" optional, and the gate suite's convention (test_enemy_coil.gd: bool(doc.get("script", false))) reads absent as declarative. All 11 curses without "script": true — brittle, hasty, hungry_void, inflation, lights_out, long_night, rush_hour, short_chain, tarnish, thick_fog, weighed_down — carry exactly the modifiers their DESIGN.md section 7.2 rows state (per stack and at max stacks), their severity / min_level / max_stacks / requires_enemy all match the rows, and their hooks are empty. No curse JSON was changed: every row agreed with DESIGN.md (checked modifier-by-modifier against the table before writing the test). tests/test_curses_decl.gd loads the real content, applies each declarative curse through the real modifier path (core/content_api.gd apply_modifiers / mods_for_stacks), and asserts the table deltas, plus the three section 7 safety assertions over ALL 46 curses: (1) no curse names jump_velocity or gravity (neither is in the closed list, both asserted absent from STATS and from every modifier); (2) the total run-speed reduction with every curse applied at max stacks stays <= 10% (>= 0.90) in the always / black_phase / gold_phase contexts — weighed_down (-10%, gold phase only) is the only run-speed curse, and the glitched floor's -20% is the toucher's enemy effect (glitch_slow_mul, D-075), asserted explicitly to be absent from every curse and to keep its 0.8 closed default; (3) void_charges_max is touched only by Hungry Void (op set, value 1), asserted over every curse and re-asserted against a base cap of 2. The declarative id set is asserted exact: a curse gaining or losing "script" or landing new without a DECL_ROWS / DECL_META row fails the build with instructions. The eleven declarative JSONs were deliberately NOT normalized to spell "script": false — the schema default carries the meaning, the JSON matches the shipped T-014a state, and the difference is asserted, not hidden.

### D-T052-1 - Declarative upgrades are proven through the real modifier path, and the script:false partition is pinned (T-052).
DECISION (T-052): tests/test_upgrades_decl.gd proves every script:false upgrade by applying
its modifiers through core/content_api.gd (mods_for_stacks + apply_modifiers, the DESIGN.md
section 12 math: per stat (base + sum of adds) x product of muls, then `set` wins) and
asserting the resulting stat delta against an expectation literal written from its DESIGN.md
section 8 table row (at 1 stack and at max stacks, plus the tier/price/max_stacks row
identity and the empty-modifiers-at-0-stacks rule). The 11 declarative ids are pinned as a
set: the script:false set on disk must equal ROWS' keys and the script:true set must equal
T-053's 25, so a flipped `script` flag fails the test loudly with the id in the message.
Declarative also means modifiers-only: every script:false upgrade must carry a non-empty
modifiers list and no hooks (T-053 owns anything with a hook or a script). Expected values
are table-derived literals, never pow() re-derivation of the implementation; the compounding
reading for mul modifiers (1.1^2 = 1.21 at 2 stacks, etc.) is the section 12 semantics and
matches the T-013 drop-in fixture's asserted round-trip. No [CONTESTABLE] entry was needed:
every number asserted is stated in the section 8 table, section 3.1/3.2, or the R4 addendum.
WHY: the ticket's stated job is the declarative PROOF, not a rewrite of the merged,
schema-validated 36 files; pinning the partition is what keeps the proof honest when the
two parallel upgrade tickets (T-052 declarative / T-053 scripted) both merge.

### D-T052-2 - The R4 addendum's centi-gold floor rule is asserted through an exact integer oracle (T-052).
ADDENDUM (R4, appended verbatim): "All gold arithmetic is in integer centi-gold and rounds
DOWN. A stacked price is `floor(price x 1.5^n)` in whole gold. A bounty is `floor(base x
(20 + level) / 20)` in whole gold."
DECISION (T-052): the rule is now asserted three ways. (1) data/economy.json
gold_arithmetic declares unit centi_gold / rounding floor / the two formulas; the test pins
those exact strings. (2) OffersScript.price_for is checked over every upgrade on disk for
every stack count 0..max_stacks against the exact integer oracle (price x 3^n) / 2^n -
3^n/2^n is dyadic, so the floor in whole gold is exact in integer arithmetic and truncating
division equals flooring for non-negative values - plus five pins from the section 8 table
(gilded_touch 150 x 1.5^3 = 506, more 50 x 1.5^3 = 168, paycheck 40 x 1.5 = 60 and
40 x 1.5^3 = 135, yearn_for_speed 60 x 1.5^4 = 303). (3) api.curse_bounty is checked over
all 46 curses at levels 0/1/4/9/17/26/30 against (base x (20 + level)) / 20 integer division
(mild 20 / harsh 45 / brutal 90), with the D-T013 pins harsh@1 = 47 and mild@0 = 20.
EconomyScript.to_centi is pinned at 2.675 -> 267 (the binary-floating-point trap:
2.675 x 100 is 267.49999..., a round-half-up would say 268) and at -0.01 -> -1 (floor, not
truncation). ONE floor per final amount stands (D-T022-5): no per-factor flooring anywhere.
WHY: the R4 addendum is binding arithmetic; a float round-trip anywhere in the price or
bounty path would drift the replay-relevant purse by a gold over a 5-stack buy.

### D-T052-3 - insulation.json's modifier was rewritten to the section 8 row (the one genuine DESIGN.md disagreement) (T-052).
DECISION (T-052): insulation's modifier changed from {stat glitch_slow_mul, op mul, value
0.5} to {stat glitch_slow_mul, op add, value 0.1}. DESIGN.md section 8's row reads
"glitched floor slows 10% instead of 20% and no longer disables class abilities"; under the
section 12 modifier math with core/stats.gd's documented base (glitch_slow_mul = 0.8, the
D-075 / D-051 -20% floor effect) the shipped expression produced 0.8 x 0.5 = 0.4 - a -60%
slow, not "10% instead of 20%". The add-0.1 reading yields exactly 0.9 under the same math,
is minimal, and composes. T-014b's note claimed mul 0.5 was "the 10%-instead-of-20% half";
that claim does not hold under the modifier semantics that actually exist (final = base x
muls), which is why this is filed as a rewrite, not a re-reading. Nothing else in the 36
files disagreed with its section 8 row (all 11 declarative rows plus the tiers / prices /
stack counts matched). insulation remains script: true - T-053's .gd half
("no longer disables class abilities") is untouched and T-053's worker must re-read the
JSON's 0.9 when it wires the floor interaction. The JSON was the only file changed; no
content/upgrades/*.gd was created or edited.
WHY: the ticket allows rewriting a row that genuinely disagrees with DESIGN.md; shipping a
-60% floor slow as "Insulation" would be invisible until playtest. Flagged for the
orchestrator and for T-053 in tickets/T-052.response.md.

### D-T054-1 - Act -> biome wiring: the Antechamber fog now follows the biome it was handed (was always Deepwater); test_biomes.gd pins the table (T-054).

DECISION (T-054): the act -> biome table (DESIGN.md section 10) already lives in view/fog_env.gd
(biome_id_for_level, acts I..V, levels 1-30; levels 31+ cycle acts I..V with the density pinned at
0.015, D-T014c-1) and is consumed by view/level_mesher.gd (build) and tools/shot.gd / tools/shot_biomes.gd.
One consumer did NOT reach it: view/lobby/antechamber.gd's _lights() built its FogEnv from
`str(_pal.get("biome", "deepwater"))` / `_pal.get("level", 0)` - keys resolve_palette() never
returns - so the hall always ran Deepwater fog whatever biome was passed to build_all() (the
default p_biome_id is "deepwater", and every caller today passes "deepwater"). Fixed:
_resolve_colours() stores the p_biome_id / p_level it was handed and _lights() calls
fog.configure(_biome_id, _level) (DESIGN.md section 11: the hall carries the CURRENT biome's fog).
New tests/test_biomes.gd pins the wiring headlessly (TESTS 41 -> 42): the level -> biome table at
every act boundary and the 31+ cycle, BIOME_ORDER, every biome file's act/levels/fog_density and
palette hexes verbatim against the DESIGN.md section 10 table (deepwater walkway_light #3A74FF per
D-T011-6), resolve_palette() returning each biome's roles/fog/void/density, and the 31+ density
override. No canon hex, role, threshold or file outside this list changed.

### D-T054-2 - [CONTESTABLE] DESIGN.md section 10's "tripmine particles vs platform light >= 3.0" is unsatisfiable by ANY platform_light hex; parked, not worked around (T-054).

DECISION (T-054): fog_check.gd (TERRAIN_SPEC section 12.3 exactly, D-T011-3) prints the DESIGN.md
section 10 row "tripmine particles vs platform_light >= 3.0" as INFO only, because section 12.3
itself does not carry the row (it is section 10's own addition). The row FAILS for all five biomes
(deepwater 1.468, verdigris 1.142, violet_hour 1.064, indigo_trench 1.163, pale_abyss 2.029;
emitted at 40 u, platform fogged at 1 + 0.35 = 1.35 total radiance). Adjusting biome light colours
upward in lightness cannot close it, and no adjustment can: with the canon #FF4FD8 tripmine tell
(fixed in every biome - DESIGN.md section 10; every biome file's _doc), even a PURE WHITE
platform_light at 1.35 radiance reaches only 2.675-2.703 fogged vs the tell; for three of the five
biomes darkening platform_light is the only direction that raises the number at all, and darkening
enough to reach 3.0 (fogged radiance <= 0.026-0.033 at 40 u) makes the fogged platform lum at 60 u
fall below ~0.033, breaking the section 12.3 required row "platform_light vs fog @60 >= 3.0"
(needs fogged lum >= 0.107-0.117). The two canon rows are mutually exclusive for a fixed #FF4FD8.
WHY (gameplay reason): the platform light is the surface the player plans the route on (DESIGN.md
section 10; section 12.3 exists to defend ITS legibility vs the fog); the tripmine tell is "the
only pink in the level" (section 12.2) chosen so danger reads BY HUE FAMILY, not by local contrast
against its background - a 3.0 contrast target against every biome's plat would force the tell or
the platforms out of canon. Built reading (closest to TERRAIN_SPEC section 12.3, this ticket's
authoritative check): the row stays INFO-only, NO hex moved in ANY biome, 5/5 biomes PASS the
authoritative check (250 checks OK, fog_check.gd exit 0) - see PARKED.md row 11 and
tickets/T-054.response.md for the full measurements. Owner to rule: (a) the row is informational
(built reading), or (b) amend DESIGN.md section 10's row (drop it, or name the tell colour it is
meant to test against), or (c) amend section 12.3 to carry the row and accept that every biome's
platform_light becomes near-white/near-black by hue-preserving constraints, or (d) the #FF4FD8
tell changes per-biome (contradicts three canon passages). NO THRESHOLD WAS MOVED.

### D-T055-1 - [CONTESTABLE] Placeholder cues land at `game/assets/audio/enemies/<id>/<cue>.wav`, not section 3's `content/enemies/<id>/audio/` (T-055).

DECISION (T-055): the synthesized placeholders are written to
`game/assets/audio/enemies/<id>/<cue>.wav`. WHY: research/fable-tickets.md
section 3 states the file name as `content/enemies/<id>/audio/<cue>.wav`, but
every merged view-layer audio hook loads from `res://assets/audio/enemies/<id>/<cue>.wav`
(seal_audio.gd, kiwi_cat_audio.gd, gift_larper_audio.gd, claude_audio.gd DIR constants)
and the TBD.md T-030/T-031/T-036/T-038/T-039 rows all name that same
`assets/audio/enemies/<id>/<cue>.wav` path as the T-055 landing spot; the path
is the contract the code already speaks, so section 3's path is read as
superseded by the merged code (its addendum itself says section 3 is
"superseded in detail by T-087"). The file name = cue name contract is
unchanged. T-087 (the binding-timing ticket) decides the final layout; if it
keeps this path, no file moves.

### D-T055-2 - [CONTESTABLE] Isagi and nuke enemy.json files name NO audio cues; the repo's TBD hook names were synthesized anyway (T-055).

DECISION (T-055): isagi's `enemy.json` lists no `audio_cues` / `stats.audio`
(the ticket note claiming all twelve do is wrong for isagi and nuke), and
nuke's `enemy.json` lists none either. Rather than stall or invent cue names,
the cues the repo DOES name were synthesized: Isagi's T-033 TBD rows
(`isagi_voice_direct_shot`, `isagi_shoot_sae_math_final_shot`, `isagi_gunshot`)
and nuke's `sprites.json` TBD audio hooks (`lock_on_beep`, `rocket_booster_roar`,
`impact_boom`), each mapped onto its section 3 brief (windup 1.2 s whoosh;
shot 0.12 s noise burst + 150 Hz thump; 1200 Hz square blip; falling-cutoff
booster roar; 45 Hz impact boom) plus a formant "final shot" yell for the
sae-math line. `enemy.json` was NOT edited (T-087 owns the cue lists); the
extras are routed through an explicit `EXTRA_CUES` table in
`tools/synth_audio.py`, not silently merged into the scan. T-087 must wire
these (or rename them) into isagi's and nuke's `enemy.json`.

### D-T055-3 - [CONTESTABLE] All synth recipes and lengths are placeholder stand-ins; the cue-name contract is the deliverable (T-055).

DECISION (T-055): every recipe in `tools/synth_audio.py` is a deterministic
stdlib (`wave` + `math`) synthesis - sines, odd-harmonic saws, exponential
decays, LCG noise (fixed seeds, byte-stable rebuilds), peak-normalised to 0.89,
44.1 kHz mono 16-bit - and is `[CONTESTABLE]` per section 3's own "Synthesis
recipes are [CONTESTABLE] placeholders for a later real sound pass". Lengths
follow section 3's rows where a 1:1 mapping exists (e.g. `meow` 0.35 s,
`rumble_build` 5.0 s, `bark` 0.25 s, `thicc_ben_chime` 0.5 s); where no
section 3 row exists for the enemy.json-named cue (e.g. `claude/ui_chime` ->
the `drum_hit` row's 0.2 s, `gift_larper/explosion` -> the `mine_blast` row's
0.8 s, `keystroke_tick` 0.08 s), the nearest section 3 row's length was used.
The summoning of the three named recordings (thicc ben chime, Isagi voice/
gunshot, Roblox tripmine blast) as synthesized stand-ins is the TBD FALLBACK
path, marked `tbd_audio: true` in the relevant enemy.json stats already and
listed as TBD + all-placeholder in TBD.md section 8. Cue timings are never
driven by audio length - the sim's telegraph events own timing; T-087 owns
binding lengths and per-cue tick offsets.

### D-T076-1 - Enemy altar panels carry one tell line and one counter-play line, both VERBATIM from DESIGN.md (T-076).

DECISION (T-076): every enemy's top-level `tell` and `counter_play` in enemy.json is now a verbatim
substring of DESIGN.md (markdown emphasis markers `**` and backticks stripped, all whitespace
collapsed - the file wraps mid-sentence, so a raw byte line match is impossible; the words,
numbers and punctuation are otherwise exactly the document's). The altar panel (antechamber.gd)
also gained the tell line between the behavior line and the counter-play line, so the enemy
panel reads: name / the one-line behavior / the tell / the counter-play / `In play: ×N`.
WHY [gameplay reason]: the panel is the only place the player learns the counter before the
vote; paraphrase drifted per ticket (the merge wave left four enemies with empty or
stats-buried lines - coil, isagi, nuke, you - whose panels fell back to "Behavior: TBD (enemy
wave pending)"). Verbatim plus a proof test is the only reading of the ticket's "verbatim from
DESIGN.md" that survives the next content edit. DESIGN.md was NOT edited: where section 5 has
no *Answer:* paragraph (thicc ben, gift Larper) the line is drawn from the closest verbatim
passage (D-T076-2), and the gap is recorded here rather than patched into the design doc.

### D-T076-2 - thicc ben and gift Larper use the closest verbatim DESIGN.md answer passage (T-076).

DECISION (T-076): DESIGN.md section 5.3 (thicc ben) and 5.7 (gift Larper) carry no *Answer:*
line, so for those two only, the counter-play line is the closest verbatim passage that is a
complete answer: ben takes "Destination is locked at smoke start = player position + velocity
x 0.5 s; a player who is >= 4 u from the locked point at arrival has broken the lock (ben
appears where they were)." (section 5.3, the teleport-lock rule - kept over the section 5.0 SR-2
row "touching him is the way past (the eject is the answer, section 5.3)", which was the other
candidate; the tie was broken in favour of the passage the merged T-032 test pins: its
counter_play assertion requires "smoke"). gift Larper takes "A tripmine is a wall on its tile:
the walkable bypass is the only way past it." (section 3.3). WHY [gameplay reason]: both lines
state the one decision the player actually makes against these enemies, and both leave the
existing merged tests green without editing or weakening them (thicc_ben: counter_play contains
"smoke"; gift_larper: non-empty). CONTESTABLE: the owner may prefer the SR-2 "touch ben to get
past him" reading for ben's panel line; the trade is one wording for a red merged test, not
behavior. The touch-ben answer stays in the rotating tip pool via tip_ben_launch (D-T076-3).

### D-T076-3 - Five named T-076 tips: three shipped, two already existed (T-076).

DECISION (T-076): the five named tips map onto the pool as follows. Ships new: tip_hurdle (a
jump clears the kiwi cat 1.0 u, the toucher 1.4 u, the seal 0.6 u and an idle coil; thicc ben
4.0 u and Isagi stay solid), tip_void_dive ("Out of options with a charge in hand: jump." -
a void fall costs 1 charge, respawn on the last safe tile with 1.0 s invulnerability and a chain
reset; never at 0 charges), tip_last_light_dim ("Last Light is dim at 0 charges - it only fires
while you hold at least 1 void charge. At 0 charges every death is real"). Already shipped by
T-014c and NOT duplicated: "jump on the bark" IS tip_seal_bark (hazard_tell), and "touch ben to
get past him" IS tip_ben_launch ("thicc ben can never kill you by touch - the launch is the
danger"). WHY [gameplay reason]: a rotating 5 s pool double-weights whatever it carries twice;
re-adding the two existing tips would show ben and the bark twice as often as every other enemy.
Pool is now 21 tips, hazard_tell stays 11 (>= 8 kept), the new tags are enemy/charges - none of
the three new tips is a gift-vs-hazard tell, so the x3 hazard weighting is unchanged. The five
ids are asserted present by test_panel_lines.gd. test_loading.gd's >= 15 floor and the x3
arithmetic are untouched.

### D-T076-4 - Markdown emphasis is stripped for panel text; lines render without labels (T-076).

DECISION (T-076): `**` emphasis markers and backticks are removed from the stored panel lines
(DESIGN.md uses them liberally; Label3D would render the asterisks literally). Em-dashes,
>=, <=, x, section signs and arrows are kept. The panel renders the tell and counter-play
lines with no prefix label (no "Tell: "), so the five rendered lines are exactly the proven
strings; the proof (game/tests/test_panel_lines.gd) normalises DESIGN.md the same way
(emphasis strip + whitespace collapse) and checks substring membership, then calls
altar_details() itself and asserts the rendered array contains the exact enemy.json strings -
a hostile panel cannot pass by shipping different text than the data the check reads.
CONTESTABLE: the owner may want visible "Tell:" / "Answer:" prefixes on the panel; the cost is
that the rendered line is no longer byte-equal to the proven line (the prefix would live outside
the proof). The proof test is auto-discovered by run_all.gd and runs in the gate.

### D-T076-5 - coil, isagi, nuke and you gain top-level behavior lines (T-076).

DECISION (T-076): those four enemies carried their panel data only inside the closed "stats"
object (T-035/T-040 precedents), so the antechamber's top-level read rendered "Behavior: TBD
(enemy wave pending)" for them. They now carry top-level behavior strings, copied from the
ENEMIES.md Behavior (1:1) sentence (coil, isagi, nuke) and from the YOU?! stats line (you);
the schema already allows the key (D-T030-6), nothing under stats moved, and no sim code reads
top-level behavior. WHY [gameplay reason]: a panel that says "TBD (enemy wave pending)" for a
quarter of the roster teaches the player nothing at the vote - the wave has landed, the lobby
already renders the rest of the roster, and the owner spec is "an enemy shown off with a
description". All 12 enemies now render name / behavior / tell / counter-play / In play.

### D-T056-1 - [CONTESTABLE] Minimal boot scene (app/main.tscn) so the exported exe starts to the menu (T-056).
DECISION (T-056): no document states a boot scene or entry point yet - DESIGN.md section 14 assigns
`app/` "main scene, input capture..." but no main scene exists, app/menu.gd (T-024) states "No boot
scene exists yet (the loading screen is wired to one in a later ticket), so this script is the menu
component, not the entry point", and project.godot set no run/main_scene. An export with no main
scene cannot start to the menu, so A1 (the ticket's Done-when) would fail by construction. T-056
therefore adds the smallest possible boot scene, game/app/main.tscn: one Control node whose script is
res://app/menu.gd (the menu builds its whole view in _ready), and sets run/main_scene to it. `Play`
emits play_requested with no listener (a no-op) until the real boot/loading ticket lands and
supersedes this scene. No menu code was changed.
WHY: the owner's spec is "it ships as its own standalone native .exe"; an exe that does not start
violates it. The alternative (export with no main scene) fails A1 outright. [CONTESTABLE] - the
later boot ticket will likely replace this scene; flip by pointing run/main_scene at its scene. No
number here is invented: the scene adds zero spec values.

### D-T056-2 - Windows Desktop preset: embed pck on, x86_64, release template, no signing, no encryption (T-056).
DECISION (T-056): game/export_presets.cfg defines exactly one preset, "Windows Desktop":
platform "Windows Desktop", runnable, export_filter "all_resources", export_path
"../build/voidwrap_run.exe" (repo-root build/, which .gitignore already ignores - the .exe is never
committed), binary_format/architecture "x86_64", binary_format/embed_pck true (the owner's
"standalone native .exe": one self-contained file, no sidecar .pck), release template with the
console wrapper OFF (a GUI game, not a console app), no codesigning (no certificate exists in this
environment and signing needs one), no PCK encryption (nothing to protect in a free non-commercial
project; encryption would add a key-management burden and zero player value), application/icon left
empty (no icon asset is pinned in any document - a blank icon is the honest placeholder, not an
invented asset). The 4.7.2.stable export templates were VERIFIED present in the per-user Godot
templates folder (windows_debug/release_x86_64.exe + _console variants, version.txt =
"4.7.2.stable", dated 2026-08-17) rather than re-downloaded; tools/godot is 4.7.2.stable.official
and the templates match it exactly.
WHY: every field traces to the owner's spec or to an explicit absence (no cert, no icon asset, no
reason to encrypt). embed_pck is the one field the owner's spec actually pins ("ships as its own
standalone native .exe"). A number no document states would have been a SPEC GAP; none was needed
beyond the preset mechanics themselves.

### D-T087-1 - [CONTESTABLE] The section 3 row -> enemy.json cue-name reconciliation (T-087).

DECISION (T-087): section 3 names cues by BRIEF (`boing`, `twang`, `chime`, `bong`,
`windup`, `shot`, `lock_beep`, `descent_roar`, `boom`, `static_build`, `ring_release`,
`mine_blast`, `mine_dud`, `mine_hum`, `squelch`, `prowl`, `bark`, `flap`, `trumpet`,
`rumble`, `boom`, `leaves`, `beat`, `drum_hit`, `string_sweep`, `wind_ping`,
`plushie_pop`, `crack_rumble`, `shing`, `whoosh`, `zone_open`, `zone_close`), but the
view hooks, the enemy.json files and the T-055 wave names are the shipped contract
(file name = cue name). T-087 does NOT rename anything: the mapping is recorded here
and in `tools/check_audio.gd`'s ROW_TO_CUE table, and every file resolves:
`meow`>`meow`, `meow_double`>`meow_double`, `boing`>`coil_boing`,
`twang`>`coil_landing_twang`, `chime`>`thicc_ben_chime`,
`bong`>`thicc_ben_bell`, `windup`>`isagi_voice_direct_shot`,
`shot`>`isagi_gunshot`, `lock_beep`>`lock_on_beep`, `locked`>`locked`
(NEW), `descent_roar`>`rocket_booster_roar`, `boom`(nuke)>`impact_boom`,
`static_build`>`you_corrupted_rumble`, `ring_release`>`ring_release` (NEW),
`mine_blast`>`explosion`, `mine_dud`>`pff`, `mine_hum`>`mine_hum` (NEW),
`squelch`>`toucher_squelch`, `prowl`>`prowl` (NEW), `bark`>`bark`,
`flap`>`flipper_flap`, `trumpet`>`spawn_trumpet`, `rumble`>`rumble_build`,
`boom`(address me)>`explode_boom`, `leaves`>`leaves` (NEW),
`beat`>`beat` (NEW), `drum_hit`>`ui_chime`, `string_sweep`>`string_sweep`
(NEW), `wind_ping`>`notification_ping`, `plushie_pop`>`squeak_pop`,
`crack_rumble`>`crack_rumble`, `shing`>`shing`, `whoosh`>`whoosh`,
`zone_open`>`zone_open`, `zone_close`>`zone_close`. The section 3 file path
(`content/enemies/<id>/audio/<cue>.wav`) stays superseded by the merged view-hook path
`game/assets/audio/enemies/<id>/<cue>.wav` (D-T055-1, unamended). WHY: renaming would
move every view hook and every test string pin for zero gameplay change; the row ->
file mapping is data, so it lives in the check and here.

### D-T087-2 - [CONTESTABLE] Loop cues get a 2.0 s bed; loop cues are exempt from the length check (T-087).

DECISION (T-087): section 3 lists `mine_hum`, `prowl` and `flap` as `loop` with no
length - a SPEC GAP. All loop beds are synthesized at 2.0 s (`flipper_flap` regenerated
1.0 s > 2.0 s; the other two beds are new). A loop is exempt from the ±10 ms
file-length assertion (existence + 44.1 kHz/mono/16-bit only). WHY: a seamless 2.0 s bed
is long enough not to stutter-repeat audibly and short enough to remain a synthesis
placeholder; nothing in the sim or any binding computation reads a loop's length, and the
FLAP tell is its 3.3 Hz > 6.6 Hz cadence baked into the bed, not the bed's length.
Binding/offset data never rides on a loop's length.

### D-T087-3 - [CONTESTABLE] Claude `string_sweep` is 3.0 s; gin `crack_rumble` reads as the whole 120-tick mark (T-087).

DECISION (T-087): section 3 gives string_sweep's length as "1 beat + 4 beats" and no
seconds anywhere - a SPEC GAP. Built 3.0 s at the 100 BPM base tempo (beat 0.6 s;
36 ticks per beat; the bar_beat anchor, the metronome, is fixed at the base tempo - the
file never re-times with agitation; cue timings are sim-driven, never audio-driven).
gin's crack_rumble row ("the 120-tick mark | 2.0 s") is read as covering the whole
120-tick mark window: offset 0 from the `mark` telegraph, ending on the launch tick
(120). WHY: 5 beats from the strings telegraph start (1 telegraph beat + 4 sweep beats)
is the only reading consistent with "the telegraph beat, then through the 4-beat sweep";
the mark reading is the only one consistent with a 2.0 s file that ends on the tick the
spears launch.

### D-T087-4 - [CONTESTABLE] Behavior-phase anchors where the sim emits no event (T-087).

DECISION (T-087): the sim's event vocabulary is fixed (telegraph [+ kind], coil_land,
toucher_infect, projectile_spawn, screen_blur, enemy_spawn, ...); for cues whose host
phase is row state with no raised event, the cue's `event` field names the behavior
phase instead - `appear`/`explode`/`leaves` (address me; the countdown is row state,
never an api.telegraph row - D-T-039-11), `mine_contact`/`mine_defused`/`proximity_6u`
(gift Larper; sim/mines.gd raises no contact event and gift_larper is the mines.gd
ladder), `proximity_14u` (toucher prowl), `release` (YOU?!'s ring), `blast` (nuke's
impact boom; the blast is api.kill, not an event), `bar_beat` (Claude's metronome),
`plushie_pickup` (Claude's squeak_pop), `zoomies` (kiwi cat's meow_double - the Zoomies
curse sprint start), and isagi's `isagi_shoot_sae_math_final_shot` anchors
`projectile_spawn`. WHY: the ticket requires every cue to name the sim event that starts
it; where none exists, the phase is named honestly rather than disguised as an event that
does not fire. Wiring these phases as real sim events is a runtime (T-027) surface
change and out of T-087's scope; the views already play these cues off row state.

### D-T087-5 - [CONTESTABLE] `keystroke_tick` and `isagi_shoot_sae_math_final_shot` have no section 3 row (T-087).

DECISION (T-087): `keystroke_tick` (0.08 s, one tick per beat while the strings beam
sweeps - claude_audio.gd's per-beat hook; section 3 names only the 5-beat string_sweep
for strings) and `isagi_shoot_sae_math_final_shot` (0.6 s; ENEMIES.md's "Isagi shoot sae
math final shot" voice-line - section 3's Isagi rows cover windup and shot only) have no
section 3 row. Their lengths stand from T-055 as [CONTESTABLE] SPEC GAPs and neither
takes part in any binding computation (roles `tell`/`on_attack`). WHY: both are real
hooks named by ENEMIES.md/merged view code; inventing section-3 rows for them is silent
spec drift - recording them here is the audit trail.

### D-T087-6 - `enemy.json` gains `audio_cue_timing` + `lethal_attacks`, additively (T-087).

DECISION (T-087): every enemy.json gains two additive stats blocks and NOTHING else
changes: `audio_cue_timing` (per cue: `event`, `kind`, `occurrence`, `offset_ticks`,
`length_s`, `role` (`binding`|`on_attack`|`tell`|`stinger`|`loop`), `attack`,
`attack_offset_ticks`, `binding_cue_ticks`, optional `parked`) and `lethal_attacks` (per
lethal attack: `attack`, `code`, `event`/`kind`/`occurrence`, `attack_offset_ticks`,
`binding_cue` or null, `binding_cue_ticks`, optional `parked`). No existing key was
removed, renamed or renumbered; no behavior number moved. Isagi's and nuke's
`enemy.json` had NO audio cues; T-087 wires the six T-055-synthesized cues (and nuke’s
NEW `locked`) into their `audio_cues` lists. The three named recordings stand in as
synthesized cues marked `tbd_audio: true`: thicc ben chime (already marked), Isagi's
voice-line/gunshot cues and gift Larper's `explosion` (both newly marked in their
enemy.json stats), with TBD.md rows 47-49. gin, toucher and address me keep their
pre-existing all-placeholder `tbd_audio` markers from the T-055 era (rows 37-46
stand). WHY: the done-when needs a machine-readable per-cue event + tick offset and a
roster enumeration of lethal attacks; additive blocks keep the merged contract intact.

### D-T087-7 - The binding math, worked: thicc ben chime is the reference (T-087).

DECISION (T-087): binding cues carry their own tick math relative to the anchoring
event; the check enforces `offset_ticks \u003c= attack_offset_ticks - binding_cue_ticks`
(both assertions relative to the same anchor) and `cue end == attack tick ± 1 tick`
(735.0 samples at 44.1 kHz). thicc ben's `thicc_ben_chime` is the reference: event
`telegraph` kind `teleport` occurrence 1, offset 45 (the chime lands in the LAST 30 of
the 75-tick smoke, T-032), binding 30, attack offset 75 (the arrival tick) - assertion 2:
45 <= 45; assertion 3: end == 75 exactly. thicc ben has NO lethal attack (D-065: the
launch is the danger, never a kill), so its ledger declares the arrival as a NON-lethal
bound attack (`lethal: false`, code "", event `telegraph` kind `teleport`, attack offset 75,
binding cue `thicc_ben_chime`, binding 30); the check validates that pair and prints
`BOUND thicc_ben/teleport_arrival (non-lethal)`. Coverage and the PARKED machinery apply
only to `lethal: false`. `thicc_ben_bell` anchors
the `screen_blur` event (the only sim event on the touch path; the ring/blur/eject is
D-T-032's surface), role `stinger`, unbound. WHY: ben proves the data model on the one
case whose cue span equals the pre-arrival window exactly, and binding to a named,
validated non-lethal attack keeps the cue-reference check honest without a dangling id.

### D-T087-8 - Coverage: every lethal attack names a binding cue or a parked exemption (T-087).

DECISION (T-087): `lethal_attacks` is the coverage ledger. Every entry must either name
a `binding_cue` (which must exist, be role `binding`, agree on attack id / event /
kind / occurrence / offsets / binding time, and pass the two binding assertions - A3 or
an explicit `parked`), or carry `parked = "PARKED.md #N"` plus `binding_cue = null`,
which the check prints LOUDLY (`PARKED` lines, exit stays 0 only because the row is a
written, owner-visible reason). Anything else fails the build. The parked set as built:
the no-wind-up contact class (kiwi cat, toucher, gift Larper, YOU?! touch, gin body,
Isagi body - PARKED.md #12), coil's boing vs the landing tick (#13), Claude's drums +
wind (#14), gin's crack_rumble vs the zone-open tick (#15). Claude's strings ARE covered
(`string_sweep`, D-T087-3, attack offset 180 = the end of the beam's kill window, binding
180, both assertions pass). Seal's dash IS covered (`flipper_flap`, role `binding`,
`loop` = true, offset 0 from the `dash_line` telegraph, binding 45 = TELEGRAPH_TICKS,
attack offset 45; assertion 2 passes, assertion 3 is not applicable to a loop), with the
`bark` as the on-attack stinger. WHY: the done-when demands every lethal attack name a
binding cue; silently uncovered attacks fail, documented parked ones stay visible.

### D-T053-1 - The sim layer never names an upgrade id: scripted upgrades are wired through role strings, the id→role pairing lives in the content scripts (T-053).

DECISION (T-053): `sim/upgrades.gd` and every other sim file compute the batch's behaviors behind
role keys ("mine_radar", "gift_radar", "threat_radar", "beacon_compass", "cartographer",
"skeleton_quota", "beacon_channel") — never the literal upgrade ids. The pairing id→role (and the
per-id ranges/thresholds: 14 u, 40/80 u, 30 u, 40 u, 90 %, 180 ticks, 3 u, 6 s, +2 stacks) lives in
one thin `content/upgrades/<id>.gd` script per upgrade, matching the T-051 curse-script convention.
WHY: `tests/test_boundaries.gd` forbids content ids under terrain/ sim/ core ("or any content id",
KNOWN_CONTENT_IDS mechanism), so a sim file that read `stacks.has("radar_gifts")` would be a scan
violation the moment upgrade ids are appended. Callers outside sim (app/ later, tests now) aggregate
the roles from the content scripts.

### D-T053-2 - Cartographer's "anywhere you have stood" is the union of 1 u tiles, measured tile-centre to tile-centre (T-053). [CONTESTABLE]

DECISION (T-053): the footprint is the tile containing the player's centre, recorded once per tick
into a set per player; "every piece within 40 u of anywhere you have stood" = every gift slot (occ
0 real gift, occ 1 mine) and the beacon whose tile centre is within 40 u of any recorded tile
centre. Alternative rejected for this pass: continuous per-tick position memory (exact but
unbounded and hot-path heavy); a run of 300 s x 60 Hz x 8 players would hold 144 000 points. The
tile set is bounded by the level's walked area. Flipping to continuous costs one store in
`note_footprint()`.

### D-T053-3 - Pocket Beacon: INTERACT press edge while standing still starts a 3.0 s channel; any input cancels; fill teleports to the dais; once per level, works while the beacon is closed (T-053). [CONTESTABLE]

DECISION (T-053): the DESIGN.md §8 sentence gives the fill (exactly 180 ticks) and the cancel ("any
input") but no activation. Built reading: the INTERACT press edge starts the channel when the
player owns it, has not used it this level, is grounded and standing still (both move axes neutral
and speed <= 0.05 u/s, i.e. the feet-still gate); "any input" = any of the three buttons pressed or
held, OR any non-neutral move axis, OR losing grounding — any of these cancels on that tick with
the channel emptied (it can be restarted; "once per level" is spent only by the teleport). On the
180th channel tick the player's row moves to the beacon dais centre (beacon.cx, base_y, beacon.cz)
and event `beacon_teleport` fires; the beacon's own state machine is untouched (the upgrade does
not open it). [CONTESTABLE] points: the activation button (INTERACT; the design table does not name
one) and the closed-beacon allowance (the owner's "teleport to the beacon dais" reads as a
traversal tool, and DESIGN §3 says a level is completed only by entering the OPEN beacon — the
teleport lands you on the dais, the entry rule alone pays out).

### D-T053-4 - Skeleton Key's 90 % is a collection quota on the beacon-open condition; the remainder goes gold by the existing phase flip, no second conversion (T-053).

DECISION (T-053): `gifts.gd` gains one optional field `black_quota: int = -1` (set at level build;
-1 = the exact merged rule, every default path unchanged). When set to ceil(0.9 × total_real),
`all_black_collected()` — the beacon-open condition — passes at the quota instead of at 0 remaining.
"The rest turn gold in place" is exactly what the merged gold-phase flip already does: gold gifts
appear at EVERY slot that held a black gift, including the uncollected ones, same slots, same
positions (TERRAIN_SPEC 6.7's zero placement rule). No separate conversion pass exists.

### D-T053-5 - Twin Dash is a second dash stock with its own 3 s regen, charged at purchase (T-053). [CONTESTABLE]

DECISION (T-053): dasher-only. The merged `dash_ready`/`dash_cd` pair stays charge 1 untouched
(existing tests keep passing); the second charge is a bonus stock: consuming it starts its own
`bonus_cd` of dash_regen (3 s), frozen under ability lock exactly like the primary (D-070). At
purchase the stock is granted charged (usable immediately). Alternative rejected: replacing the
bool with a 2-charge pool would touch the merged regen branch every existing class test runs
through.

### D-T053-6 - Updraft: vy = sqrt(2 × 32 × 3) ≈ 13.8564 (apex exactly 3.0 u under gravity 32), once per glide engagement, 6 s cooldown (T-053). [CONTESTABLE]

DECISION (T-053): glider-only. Re-pressing jump while gliding sets vy to the exact 3 u apex
velocity, ends the glide, and starts the 6 s cooldown (frozen under ability lock, D-070). "Once
per glide" = once per glide ENGAGEMENT: the flag resets when a new glide engages, so glide →
updraft → re-glide → updraft is legal (at 6 s+ spacing, two energy bars apart). [CONTESTABLE]:
"once per glide" could instead read once per continuous airborne period; the engagement reading is
the literal one and the cooldown already bounds it.

### D-T053-7 - Marathon's +2 max stacks reaches the shop as an optional max-stacks bonus dict in draw_shop; the pairing lives in content/upgrades/marathon.gd, the call site is the shop wiring (T-053). [CONTESTABLE]

DECISION (T-053): `offers.draw_shop` gains one optional parameter, `p_max_stacks_bonus: Dictionary`
({upgrade id: extra stacks}, default empty — every existing call site and test unchanged), and both
exclusion checks compare against max_stacks + bonus. `content/upgrades/marathon.gd` is the single
source of the pairing (athletic + marathon owned → {"yearn_for_speed": +2}). The app/intermission
call site that aggregates content scripts does not exist yet (no sim file may name an upgrade id,
see D-T053-1, and the shop wiring is T-052's surface) — until it lands, the bonus is supplied by
whoever calls draw_shop. [CONTESTABLE]: the call-site owner; the data path itself is final.

### D-T053-8 - The radar/minimap render contract constants (24 px chevron, 220 px minimap) live in the view widgets; the sim layer exposes pure queries only (T-053).

DECISION (T-053): addendum R4's render numbers — chevron 24 px at the screen edge with the
distance in u under it; 220 px north-up square top-right under the purse, pieces as filled shapes
in their biome colour, real gifts as 2 px dots, the player as a white triangle; the Pocket Beacon
ring filling over exactly 180 ticks — are carried by `view/hud/radar_arrows.gd` and
`view/hud/cartographer_map.gd` as named constants over the pure sim queries. The renderer physics
are view-layer facts, pinned by test_upgrades_script.gd's widget tests reading the widgets' models,
not by any sim change.

### D-T051-1 - The curse script contract: handler modules, the state surface, hooks-only (T-051)

DECISION (T-051): every `script: true` curse of the GENERAL family (requires_enemy null:
cold_start, crowded_dais, crumbling, curfew, dull_gifts, early_bird, leaky_purse, no_refunds,
rearguard, slow_door, unmarked - 11) ships one `content/curses/<id>.gd` module. Contract:
- each module is a RefCounted with `const CURSE_ID := "<id>"`; handlers are functions named
  after the CLOSED hook list of core/hooks.gd, signature `handler(state, api)`;
- `state` is a Dictionary; the documented keys are "players" (T-012 controllers),
  "enemy_runtime" (sim/enemy_runtime.gd), "economy" (sim/economy.gd), "beacon"
  (sim/beacon.gd), "enemies" (the world mirror rows), "spawn_plan" (the runtime's
  planned[] rows), "tick" (the level's 60 Hz tick), "events" (event sink),
  "curses_held" ({curse_id: stacks}), and "curse_st" (the per-curse slot tree,
  state["curse_st"][<id>]);
- world changes go ONLY through documented state keys (controller constants, the runtime's
  spawn delay, the economy's purse/tiers) or the api's allowed surfaces ("add gold",
  "spawn entity" - api.add_gold / api.spawn_enemy, duck-typed with has_method and a
  documented fallback);
- every mutating handler self-guards on its own held stacks (curse not held -> no-op), so a
  future dispatcher can call handlers unconditionally in id order;
- read-only curses (unmarked, no_refunds, dull_gifts, crowded_dais, slow_door's gate)
  expose pure rule helpers; the sim/view callers consult them.
No curse JSON was edited (T-050 owns the batch; the JSONs' hooks arrays stay []). The hook
dispatcher in sim/ does not exist yet (the same wiring gap PARKED.md row 3 records for
Field Dressing's on_void_fall): the modules are the content-layer half, ready to dispatch.
Boundary scan clean: the .gd modules live under content/ (never scanned in the forbidden
string scan's layers); sim//core/ still name no content id.

### D-T051-2 - Dull Gifts pins the rim glow at 20 u; the gifts' values untouched (T-051)

DECISION (T-051): Dull Gifts ("black gift rim glow visible only within 20 u") is a
render-gate curse: content/curses/dull_gifts.gd's rim_glow_visible(state, ...) is the
single read the gift view consults - glow only within 20.0 u of the player's feet point
(3D distance, gift body centre), and an unmodulated always-visible answer at 0 stacks.
The curse does NOT touch gift values, counts or pickups (the JSON carries no modifier);
the -20% gold sentence family stays with tarnish. The 20 u is the table's own number,
not a new one.

### D-T051-3 - [CONTESTABLE] Cold Start's per-class mapping: dasher regen x1.25, glider 0 start energy, athletic coyote -0.05 s (T-051)

DECISION (T-051): the rule sentence "class ability starts each level on cooldown and
recharges 25% slower (Athletic: coyote time −0.05 s instead)" binds each kit by its own
ability mechanic: dasher = dash starts ON cooldown (dash_ready false, dash_cd at the
scaled regen) with the regen DURATION x1.25 (3.0 -> 3.75 s - "recharges 25% slower" is a
longer regen, the controller's own countdown law untouched); glider = the ability starts
on cooldown mapped onto its only energy law: 0 glide energy at level start, the
landing-refill law unchanged (no numeric value is invented; the sentence has no number a
landing-time refill could multiply); athletic = the D-062 substitute, coyote time −0.05 s,
never below 0. The section 7 safety rule holds: Cold Start never touches jump velocity,
gravity or run speed (asserted in the test). [CONTESTABLE] because the glider mapping
("on cooldown" = 0 energy) is the implementer's reading of a sentence written for a
cooldown-meter ability; the dasher duration x1.25 is the only numeric reading the sentence
states.

### D-T051-4 - Slow Door = continuous presence; Crowded Dais = 3D, inclusive at exactly 8 u (T-051)

DECISION (T-051): two gate readings pinned. Slow Door's "3.0 s of standing in it" is
CONTINUOUS presence inside the OPEN beacon's trigger cylinder (sim/beacon.gd contains()):
any tick outside resets that player's dwell to zero, 180 whole ticks (3.0 s) opens the
door, entry_ready() answers the entry caller. Crowded Dais' "within 8 u" is the 3D
distance from the enemy row to the beacon's axis point (cx, base_y, cz) - the same metric
as the arbiter's no_enemy_body_within (D-T072-1) and the safe-tile 6 u rule (DESIGN.md
section 3.1) - INCLUSIVE at exactly 8.0 u ("within" keeps its boundary), and it never
blocks a CLOSED beacon's rules (the gate is entry-blocking only). Both gates are pure
reads; the beacon's try_enter path consults them once the hook dispatcher wires content
gates (the wiring gap below). Crumbling's schedule (fall after 72 ticks, return 300
later, first-schedule-wins) is D-T051-1's module shape with the 1-wide/stepped-on tile
READING owned by the future dispatcher (collision.gd's support_at is sim-surface).

### D-T085-1 - [CONTESTABLE] The tripmine star is split out of the single vertex-coloured .glb at load time, and the four side-face hexagrams are view geometry (T-085).

DECISION (T-085): section 2.1's star row wants "six-pointed, on all four side
faces, `#FF4FD8`, emission 1.0; alpha 0 beyond 14 u -> 1 at 10 u". The T-015 model
(`assets_src/blender/tripmine_box.py`) bakes the hexagram into ONE vertex-coloured
primitive, on the TOP face only, and Blender is not available in this environment,
so the .glb cannot be rebuilt. `view/tripmine_view.gd` therefore splits the loaded
mesh by vertex colour at setup (`split_star()`: a triangle is a star triangle when
all three of its vertices are the tell pink - red and blue above half, green below
it) into a box surface and a star surface, and gives the star surface its own pink
emissive material whose alpha follows the ramp. The four side-face hexagrams are
view-layer geometry (three crossing bars per face at 0/60/120 deg, 0.40 x 0.05 u,
on the frame's own faces). WHY: the ramp IS the deception rule - a pink star that
never fades gives the mine away at 60 u - and the split is the only way to fade the
baked star without a Blender rebuild or a shader. CONTESTABLE: the model's star is
on the top face, the table says the side faces; both are drawn.

### D-T085-2 - [CONTESTABLE] The particle "± 0.2 u drift" is the emission volume radius (T-085).

DECISION (T-085): section 2.1's particle row states "rising 0.4 u/s with ± 0.2 u
drift" without saying whether the 0.2 u is a lateral velocity or a spread. Built as
the emission volume: `CPUParticles3D` emission shape SPHERE, `emission_sphere_radius`
0.2 u, direction UP, spread 0, initial velocity 0.4 u/s, gravity zero. WHY: a
0.2 u/s lateral velocity would let a spark wander 0.3 u over its 1.5 s life, which
reads as a swarm rather than a tell; the volume reading keeps the column tight and
still gives the drift. CONTESTABLE: the velocity reading is equally defensible and
changes only the emitter's shape.

### D-T085-3 - The beacon column is visible on the open tick itself: the ramp starts at 1/36 (T-085).

DECISION (T-085): section 2.3 says the column "rises from the dais to Y +60 u over
the same 36 ticks" and the ticket's done-when says the column "appears on the tick
of the last real black gift". A ramp of `(tick - open_tick) / 36` is 0 on the open
tick, which would make the column appear one tick late. `view/beacon_view.gd`
computes `(tick - open_tick + 1) / 36`, so the column is 1.67 u tall on the open
tick and 60 u tall after 36 ticks. WHY: the done-when is a tick contract and a
zero-height column on the open tick fails it; the 36-tick ramp length is unchanged.

### D-T085-4 - The beacon's door slab is not built: the T-015 model has no doorway (T-085).

DECISION (T-085): section 2.3's opening row wants "the slab splits and slides away
over 36 ticks". The T-015 beacon mesh is a solid obelisk with no doorway (D-T020-6
already recorded this) and Blender is absent, so there is no slab to split. Built
instead: the emission ramp 0 -> 4.0, the column rise, and the white shock ring that
crosses the hub - the other three clauses of the same row. The OPEN row's "doorway
glows" is likewise not built (no doorway). Not parked as a contradiction: D-T020-6
already ruled it and no document contradicts itself here.

### D-T085-5 - The glitched floor's "checker at 40% brightness" is the decal texture's own alpha, not the view's modulate (T-085).

DECISION (T-085): section 2.2's body row says "the tile keeps its checker
underneath at 40% brightness, so the path stays readable". The decal's modulate
alpha is the appear/fade ramp, which T-037's test pins at 1.0 at full appear
(`test_enemy_toucher.gd`), and the `glitchfloor_00..04` PNGs are TBD placeholders
(TBD.md row 8). Built: the decal is drawn over the tile top and the checker shows
through the texture's own alpha; the 40% is an asset property, not a view constant.
WHY: dimming the terrain checker per tile would need a per-tile vertex-colour
channel in `view/level_mesher.gd`'s shader (T-011/T-014 territory) and would change
a merged, tested terrain surface for a VFX row. CONTESTABLE: if the owner wants the
checker dimmed by the view, it is a level_mesher change.

### D-T085-6 - The respawn blink phase is measured from the respawn tick; 8 Hz is 7.5 ticks per cycle (T-085).

DECISION (T-085): section 2.5's invulnerability row says "60 ticks (1.0 s,
binding): the player model blinks at 8 Hz with a white rim; the rim disappears on
the tick invulnerability ends". `view/respawn_view.gd` measures the blink phase
from the respawn tick: 8 Hz = 7.5 ticks per cycle, half period 3.75 ticks,
`blink_on(elapsed) = fmod(elapsed, 7.5) < 3.75`. The rim's alpha is 1 while the
controller's invulnerability countdown is > 0 and 0 at 0, so it disappears ON the
end tick, not a frame later. WHY: a frame-driven blink would drift against the
sim's 60 Hz tick and could leave the rim one frame past the end; a tick function
cannot.

### D-T061-1 - The probes live in game/tools/ (T-061)

FLEET_PACK A12/A13 name the tools `tools/feel_probe.gd` and `tools/perf_probe.gd`; the
repo convention for A11 already puts `tools/economy_audit.gd` at `game/tools/economy_audit.gd`
(the Godot script root is `game/`, the top-level `tools/` holds the ps1 harness). Both probes
are therefore `game/tools/feel_probe.gd` and `game/tools/perf_probe.gd`, run headless with
`--path game --script res://tools/feel_probe.gd` (and the perf probe likewise). Both print
`PASS <row> <number> <bound>` / `FAIL <row> <number> <bound>` per row, then
`T-061 RESULT: OK` / `T-061 RESULT: FAIL n rows`, exit 1 on any FAIL (exit 0 otherwise).

### D-T061-2 - A12's five rows measured at component level ([CONTESTABLE]) (T-061)

A12's rows ARE fully specified in DESIGN.md section 2 (no row inventing was needed). But the
app orchestrator that owns the real transitions does not exist yet (game/app/menu.gd states
"no boot scene exists yet - the loading screen is wired to one in a later ticket"), so the
probe measures each row against the real deliverable code path that exists today:
  - loading screen (>= 5.0 s hold, <= 8.0 s total at level 30): the REAL
    app/loading_screen.gd component is driven (start/advance) with the measured level-30
    build time (voidgen.generate + collision.make_world + level_mesher.build +
    LevelState.build, seed 7); the probe asserts the component's hold/total law with that
    real number inside.
  - gate -> next level controllable (<= 2.0 s): the same whole-pipeline build time for the
    next level. Reading: with no loading screen between levels, "controllable" begins when
    the built level + its collision world + sim state exist; the app-side glue (fade,
    teleport-from-antechamber) is not built to measure. [CONTESTABLE] - once the app
    orchestrator lands this number must be re-measured with the real transition.
  - death -> run-over screen (<= 2.0 s): sim-side; the killing blow lands through the real
    DONE path (runtime body contact -> controller) and death.gd screen_data() is read the
    same tick (0.000 s measured). The run-over HUD cell exists (view/hud/run_over.gd);
    the app delay between them is not built. [CONTESTABLE] for the same reason.
  - void fall -> respawn (<= 0.8 s): the real controller stepped on a real world, the
    void_fall event tick to the respawn event tick, sim time. Fully wired in sim - this row
    measures shipped code end to end.
  - generate + mesh level 30 (<= 1.5 s): voidgen.generate(seed 7, 30) +
    level_mesher.build, median of 5 wall-clocked runs. Fully wired - ships as measured.

### D-T061-3 - The perf probe runs the 22-enemy scene as one real sim hour ([CONTESTABLE]) (T-061)

The fixed vote list is exactly as pinned (kiwi 3, coil 2, ben 2, seal 2, YOU?! 1, nuke 2,
Larper 2, toucher 1, address me 2, Isagi 1, Claude 1, gin 3 = 22). Plan order = vote-list
order (D-056 plan order); each id plans `copies = vote count`. cfg comes from each
enemy.json (stats block, topped with top-level contact_kill / preferred_kind / arbiter and
`votes` = the list's count); the behavior instance comes from the content script's own
export shape (static cfg()/behavior()/new_behavior() factories, the inner Behavior class,
or the file-as-behavior pattern). The probe pins opts.spawn_delay_ticks = 1 (instead of the
game's 6.0 s D-056 delay) ONLY so every one of the 120 warm-up + 600 measured frames runs
all 22 live bodies - the game's spawn rule itself is untouched. [CONTESTABLE].

### D-T061-4 - The probe's dodge bot is built in, pending the real bot ([CONTESTABLE]) (T-061)

The ticket says "the bot playing with --dodge", but bot_run.gd (A3) does not exist yet
(pending T-026). The perf probe embeds a deterministic stand-in driver with the dodge
behavior: full-speed move target = the beacon, steer away from the nearest live enemy body
within 12 u of the player, jump press every 1.5 s (when grounded). It is a pure function of
the sim state and the tick counter (no wall clock, no RNG) so the run is replayable.
When bot_run.gd lands, the probe should take it over. [CONTESTABLE].

### D-T061-5 - p99 formula, frame composition, and the headless rendering caveat (T-061)

A frame = one main-loop pass: bot input, controller.step + enemy runtime.step (the mean
sim tick is timed exactly around these two), the third-person camera rig update, and the
per-enemy animation advance; when a real window exists the engine also renders that frame.
p99 over the 600 measured frames = the sorted frame time at index round(0.99 * 599) = 593
(0-based), i.e. the 594th of 600. The probe reports OS name, CPU (OS.get_processor_name()),
GPU (RenderingServer.get_video_adapter_name/_vendor) and the renderer (DisplayName). 
HEADLESS CAVEAT (must be read on every number): a headless run uses the dummy renderer -
no window, no GPU submission, no vsync. The sim-tick row is then a valid CPU measurement;
the p99 frame-time row is a CPU-side frame cost ONLY (the pinned 1080p window / v-sync off
rendering cost is absent), so a headless PASS on that row is a weak signal and the probe
marks frame rows `headless` in its table. A windowed run of the same tool does render.

### D-T061-6 - spawn-plan retry: no dropped tail, no duplicated copies, SR-3 scoped to one entry (T-061)

Building the pinned 22-enemy scene exposed two defects in sim/enemy_runtime.gd's
_spawn_planned() retry path, fixed (tests still 47/0; regression pinned in
test_spawn_rule.gd _deferral_keeps_the_plan):
  1. The old code `return`-ed on the first entry whose spot pick returned null, so every
     planned entry BEHIND it was silently dropped (never retried); D-056 says candidates
     run "in plan order", D-T027-4 says a spawn lands on the first tick a legal tile
     exists - neither reading drops the tail. Now every entry is attempted each tick in
     plan order; only the unplaceable ones wait.
  2. A partially-spawned entry (copy 1 placed, copy 2's spot null) was re-appended WHOLE,
     so the next tick re-spawned the already-placed copies (observed: coil x6 from a x2
     plan). plan rows now carry `spawned_copies`; a retry schedules only the missing
     copies.
  3. The spot pick passed min_sep = COPY_SEP with the WHOLE roster's positions as exclude,
     so a 22-body vote list starved (no round-trip tile cleared 8+ circles of radius 30 u)
     and deferral became permanent (each retry re-scanning the whole movement graph).
     SR-3's sentence is "copies of one chaser are >= 30 u apart" and _pick_round_trip's
     own comment already says "the earlier copies": min_sep is now enforced against the
     entry's OWN live copies, not against other entries. [CONTESTABLE] - with all 22
     bodies placing exactly per the pinned vote list (probe CONTEXT line), the probe's
     scene needs this reading; a whole-roster separation would need a PARKED row.

### D-T061-7 - The reference machine's display adapter is a virtual one - frame rows, read with care (T-061)

The windowed run DOES execute the pinned scene (real Forward+ Vulkan window, 1920x1080,
v-sync off, level meshes + Camera3D + 22 billboards): GPU line "a discrete AMD GPU (vendor AMD)". BUT the session's desktop runs on a "a virtual display adapter",
and every frame logs "Couldn't get Vulkan surface capabilities (VkResult error -13)" -
the swapchain cannot surface. The windowed p99 frame row therefore still does not include
a real presented swapchain; it is (sim + camera + billboard + engine overhead) with a
broken present path. The trustworthy rows on this box are mean_sim_tick (0.7-0.8 ms, a
pure CPU measurement) and the p99's CPU-side upper bound. A number from a machine whose
swapchain presents (the owner's) is the real A13 reading. The billboard also learned to
tolerate the T-016 schema's world_height null (the nuke launcher has no body row; it
previously crash-parsed every windowed run).

### D-T060-1 - [CONTESTABLE] The probe's "competent bot" is fixed seeded policy, not "a human": BFS graph distance for nearest-gift, footprint-only 250 ms dodge, seeded uniform votes, knob-only curses (T-060).
DECISION (T-060): DESIGN.md section 9 names "nearest-gift routing" and "dodges telegraphs with 250 ms reaction" but defines neither metric nor scope. The bot the probe runs is therefore pinned by explicit, reproducible choices:
- nearest-gift = nearest REACHABLE uncollected black gift by BFS distance on the TERRAIN_SPEC section 5.2 movement graph (walk + jump edges, reused from terrain/voidgen.gd's own movement()), tie-broken by slot id; when the beacon is open the goal switches to the beacon tile; re-paths on gift_collected / respawn / last_light_save events, on a 45-tick refresh, and on phase flip.
- dodge = the enemy runtime's telegraph dicts are tracked from the first tick they appear; the bot reacts exactly REACT_TICKS = 15 ticks (250 ms at 60 Hz) AFTER first appearance; only real footprints count (circle r > 0, ring, box; zero-radius cues such as meow / dash_line are not footprints); the feet point inside the (0.45-inflated) footprint selects the most imminent strike; the escape runs straight out of the shape (radial for circle/ring) or across its thinnest side (box). Hazards that never telegraph (contact kills, tripmines, the nuke descent) are part of the game the bot plays and are not telegraph-dodged; a grounded contact-kill enemy within 1.6 u horizontally is hurdled instead (the roster's own counter-play).
- votes = seeded uniform random among the unresolved mandatory bays (CLASS / E / C), class included; U / REST bays are never touched - no purchase policy is invented; votes accumulate one planned row each (copies = vote count); an empty C draw is tithe-passed when affordable, otherwise the run stalls on the lobby and is reported "stuck".
- curses: only the curses with a direct sim knob are applied (rush_hour + hunger -> curse_speed_mul; long_night -> overtime_period = 14; brittle -> controller respawn delay/invulnerability; hungry_void -> charge cap 1; early_bird -> spawn_delay_ticks = 120; understudies -> +4 flat extra mines per stack). Every other curse or upgrade has no knob in the sim today and is NOT applied (hasty, weighed_down, and the script curses rearguard / litter / pup_pack among them) - documented, not faked.
- death is the outcome the bands measure, never a probe error; the bands stay FROZEN; terrain thresholds stay frozen.
WHY: every value above is the literal reading of the two section 9 clauses plus the seeded-reproducibility rule (run i = seed SEED_BASE + i = 60717 + i; same seed set, same numbers, asserted by game/tests/test_bot_run.gd with 3 runs). [CONTESTABLE] - section 9 does not define "nearest", "telegraph", or "vote"; a different reading (euclidean nearest, reaction from telegraph ISSUE tick, uniform votes over all bays) would move the numbers. The frozen bands are the spec; the bot definition is not, and the reach-rates must be read as "this bot, on these bands", never as an absolute difficulty claim. The 200-run numbers and the PASS/FAIL per band are in tickets/T-060.response.md.

### D-T060-2 - Jump arcs are forward-simulated with the controller's own physics, never solved analytically (T-060).
DECISION (T-060): the bot's jump planner no longer solves a parabola in closed form. For each jump edge it steps the controller's own physics forward - vy = 12 on jump, g = 32, releasing k ticks in with vy > 0 halves vy once, horizontal accel 90 u/s^2 - and tests CollisionScript.move_body candidates (horizontal speed v in [9, 7.5, 6, 4, 2] m/s x hold k in [0, 2, 4, 8, 14, 22, 30] ticks) until a candidate lands on a tile other than the takeoff tile. An earlier analytic solver (apex/range from a symmetric parabola) repeatedly mis-landed - it ignored the controller's release-halves-vy semantics and per-tile collision - so the bot could not cross any gap at all.
WHY [technical reason, not a spec value]: simulating the same integrator the sim runs removes the divergence between "where the bot intends to land" and "where the body lands" by construction, and keeps the planner honest against ramps and partial tiles. No spec number was invented or changed; the frozen terrain thresholds and the frozen bands are untouched.

### D-T051-20 - The enemy-linked scripted tests: what they prove, at which layer, and the merge-gap accounting (T-051)

DECISION (T-051): tests/test_curses_scripted_enemy.gd carries one test per enemy-linked
script curse whose module is on main (12: aftershock, bunker_buster, crescendo,
direct_shot, double_ring, egoist, litter, long_toll, longer_speech, method_acting,
mirror_match, overwound), each asserting the JSON's own rule sentence. Rules read at
the cheapest honest layer: pure helpers assert numbers (double_ring's radius/cap,
egoist's +1-per-stack burst and the D-064 volley plan, litter's kitten cfg/trail point,
method_acting's 6/12 u cutoff and 5/10 u ramp, overwound's 2.0/1.5 s idle, longer_speech's
150-tick mapping); module-level state machines are driven over REAL sim objects
(real sim/enemy_runtime.gd rows, REAL controllers as "players" - the D-T051-1 contract
shape, which is where several 2-arg player .get calls of the first draft crashed and
were repaired); Long Toll is driven END-TO-END (D-T051-21). The api is never null where
a module uses it: FakeApi records pushes/kills/spawns/telegraphs and assertions read
what the module ASKED for. The contract section pins the full 24-id inventory; the 12
ids whose modules live on the unmerged t3/scripted-curses-groups-4-6 branch are parked
(PARKED.md 16) and asserted to be exactly that NOT_ON_MAIN list.

### D-T051-21 - Two module repairs the tests forced; Long Toll proven end-to-end (T-051)

DECISION (T-051): writing the one-test-per-curse sentences exposed four module defects,
each repaired to the module's OWN spec sentence (no JSON edited, no rule weakened):
(a) bunker_buster.gd's CURSE_ID was "buster" - not the JSON id - so held_stacks never
found the run's held stacks (intermission.gd keys curses_held by JSON id): one-word fix
to "bunker_buster" (D-T051-1's contract). (b) longer_speech.gd's ONE-shot 60-tick debit
clamped the visible still counter at 0, which ABSORBS the whole shift: the 90-tick gate
still fired at ~1.5 s, not the sentence's 2.5 s. Replaced with a per-run DEBT (60 ticks
booked at run start, one tick of the behavior's +1 climb absorbed per tick until paid,
re-booked when the run breaks): the release now lands exactly at 150 true still ticks,
the visible counter never goes negative, and the view's arc (0..90 fill) still reads.
(c) double_ring.gd's growth detector compared seq against seen[key] DEFAULTED to the
current seq, so on_tick could never schedule anything (the curse was inert); the first
sight of a row is now the baseline, later growth releases the echo. (d) mirror_match's
cadence helpers typed the mirror target as Dictionary, crashing on the D-T051-1
controller shape; both read the same 1-arg surface now. Long Toll's done-when is proven
END-TO-END: the REAL thicc_ben behavior runs inside a REAL enemy_runtime and the curse
joins the tick loop; with the curse the second ben arrives at the SAME locked point
exactly +90 ticks (1.5 s, TOLL_INTERVAL_TICKS) after the first even though the player
moved away (a fresh lock would land on the moved player), ejects the player standing on
the locked point and never kills (controller un-dead); without the curse the next
arrival is ben's own 801-tick cycle away on the fresh lock. A toll never chains (no
third arrival within 95 ticks of the second). The understudies mine-cap done-when stays
parked with PARKED.md 16.

### D-T080-1 - The log's tick clock is the run-wide accumulated sim tick (T-080) [CONTESTABLE]
Every record's `t` = the sum of all level ticks so far (the lobby consumes no sim ticks,
so a level's first tick continues the run's clock). The done-when's "level_clear.total
equals level_start.t to beacon_enter.t" holds under both readings; the run-wide clock was
chosen so a report can correlate events ACROSS levels (the fun-audit signals are run-shaped:
death -> controllable, lobby dwell). Alternative if the owner wants per-level t: reset total_t
in level_started() - one line. The file name keeps the owner's format: user://runs/<run_seed>_<start_tick>.jsonl
(start_tick is the accumulated clock at log start, 0 for a fresh run).

### D-T080-2 - "Killer on screen in the last 120 ticks" is a view-free proximity proxy (T-080)
The headless sim has no camera, so "on screen" cannot be measured literally. Proxy: the
killer was present within 24 u of the player's centre at some tick in the last 120 - a
body (the hit cylinder's row) or a live telegraph footprint (the view draws exactly those).
24 u sits between the fill-light range (18 u) and the Radar: Threats marker range (30 u)
[CONTESTABLE - the owner may want 18 or 30]. Enriched into the death event by
sim/enemy_runtime.gd (bodies + telegraphs, keyed by the LIVE rows' cfg death_code - no
content ids written in sim, the boundary scan stays clean). D-VOID never reads on screen; a
mine kill reads on screen by construction (the contact happens at the player's centre).

### D-T080-3 - Push attribution reaches the log through a push event, not through sim state
Owner spec: every void_fall record carries "pushed in last 120 ticks y/n and by which enemy".
api.push's signature is DESIGN.md section 13 canon; it carries no enemy id. Resolution:
api.push's implementation (rt.push) gained an OPTIONAL 4th arg (src_row, defaulted, call
sites unbroken - the DESIGN surface itself is unchanged) that the three pushing enemies pass
(coil, thicc ben, gin); Api.push passes api.row automatically. rt appends an additive raw
`push` event {by, tick, player}; ben's eject (api.eject_player) appends the same. The log
correlates push events against void_fall (within 120 ticks) - never sim state. No behavior
change: the event is appended after the push's velocity write.

### D-T080-4 - The lobby rows are app-layer events; lobby records carry the level just finished
`offer` (bay, the three altar ids), `pick` (bay, id, price - a negative price IS the
bounty), `lobby_enter` / `lobby_exit` are view events (the app presents altars; the sim
never streams the lobby's state as tick events). A lobby record's `level` = the level just
completed (0 = the pre-run lobby); phase = "lobby". An Ex2 bay's between-votes redraw is
not a second offer row. Recorded as D-T080-4 [CONTESTABLE]: the owner may prefer the
UPCOMING level number on lobby rows.

### D-T080-5 - level_start's "enemies in play" = the enemy vote copies just planned
DESIGN section 6's column ("enemies in play next level") counts votes; the log's
level_start payload carries the sum of the driver's planned enemy copies (the same number
the spawn plan will realize). The slot/real-gift/mine counts ride the Level dict read at
the app layer (terrain is a pure pre-sim input, DESIGN section 13) - the log module itself
takes them from the app's level_started() call and never touches sim state.

### D-T080-6 - charge_spent.free is derived from the before/after pair
"free yes/no" (Field Dressing, DESIGN section 8) has no sim knob yet - the upgrade is
defined (data + catalog rows) but the controller's void-fall path never wires it. The log
derives free = (charges_before == charges_after), which is exactly Field Dressing's future
reading (a free fall spends no pip); today every fall records free=false. When T-0xx wires
Field Dressing, the log needs no change.

### D-T080-7 - The bot driver is T-060's bot_run.gd vendored verbatim (commit 8a642ef)
The STANDER briefing said game/tools/bot_run.gd exists on main; at this branch's base
(t3/telemetry-event-log from the T-061 merge) T-060 is NOT yet merged - the file lives on
t3/difficulty-band-probe (commit 8a642ef, 984 lines). Vendored VERBATIM (no ticket text
edited, no behavior edited) with two ADDITIVE knobs: an optional trailing p_log argument
on play_run / _resolve_lobby / _play_level (null = T-060's own path, byte-identical
behavior), "charges" added to play_run's return dict, and run_finished fired at the run's
end. When T-060 merges, git sees identical content for the unchanged parts; the p_log
params are the merge's only delta. Recorded so the merge conflict is a known, planned one.

### D-T080-8 - The ticket says "20 record types" but its verbatim list has 18 [CONTESTABLE]
The owner's spec's "Types, exactly:" enumerates 18 (run_start, level_start, gift,
void_fall, charge_spent, charge_restored, mine_pass, mine_contact, death, last_light,
beacon_open, beacon_enter, level_clear, offer, pick, lobby_enter, lobby_exit, run_end) -
headed by "every record: t, level, phase, type, payload", whose four shared fields are
plausibly the +2 the brief's "20" counts. The LIST is the contract: 18 types built; if the
owner meant 20, the two extra ones are theirs to name. Not PARKED (no two documents
conflict; the ticket's own list is self-consistent) - recorded here and in the response.

### D-T080-9 - The 2-level driver in the test does not use the bot (the post-merge red gate)
T-060 merged while this ticket was in flight with the finding that bot_run.gd's bot cannot
reliably clear level 1 (void falls; the owner's sweep: level 6 in 0/20 runs, every run dead
on levels 1-3). The test_run_log.gd run of my hand leaned on the bot clearing 2 levels; after
the merge it went red ("the fixed seed must CLEAR both levels: outcome=dead entered=1").
Fix, test-design only (no check weakened): the 2-level run is driven DIRECT on the sim
surface inside the test - the test_gifts.gd idiom (teleport to each real black gift's tile,
one sim step per gift; one gold gift; the beacon entry via beacon.gd try_enter), twice,
through the real pre-run + E+U lobbies (offers/picks ride the log). bot_run.gd KEEPS its
p_log wiring (the real-runs path; D-T080-7's vendored file is now merged main, the p_log
params its only T-080 delta). Any record type the 2-level scripted drive cannot produce
(all the mine types - levels 1-2 roll zero mines) is covered by the direct units, exactly
as before.

### D-T081-1 - The jump/step-up counters are event counts in run_log, not sim state (T-081)
The ticket's "T-080 adds two counters to level_clear (jumps, stepups)" were ABSENT on
main (T-080's level_clear payload carries only black_ticks/gold_ticks/total_ticks).
Added additively, app-layer first: the controller has emitted a "jump" event for every
jump that leaves the ground since T-012 (ground, coyote, buffered-on-landing and air
jumps - the event carries no sub-kind, so all four count [CONTESTABLE]); the new
"step_up" event (sim/controller.gd) fires when a WALKED move gains >= 1 HU (0.5 u) of
ground height with ground contact on BOTH sides of the move - a jump, a landing from
the air, a ramp (0.5 u per 1 u horizontal = 0.075 u/tick at run speed) and a launch
pad never reach 1 HU in one tick, so no extra guard is needed. run_log counts both
per level and reports them in level_clear's "jumps"/"stepups". No movement number
touched; the events reach the log through the existing per-tick feed.

### D-T081-2 - The log's directory is a settable field (dir_base, default user://runs)
The batch parks 100 logs in one place; user:// is outside the repo and the ticket
prefers a gitignored repo folder. run_log.gd gains dir_base (default "user://runs" -
byte-identical default behavior, path shape unchanged); the batch passes
out/run_logs (".gitignore" already excludes out/).

### D-T081-3 - bot_run gets --log / --log-dir (additive CLI, T-060's file touched minimally)
run_probe gains two trailing params (default off - T-060's own call sites unchanged);
the CLI accepts --log and --log-dir. run_start.class is "" in batch logs: the pre-run
lobby picks the class AFTER run_started, and the picks carry it (the CLASS bay's
altar id) [CONTESTABLE - the owner may prefer the class back-filled into run_start].

### D-T081-4 - Restart time (signal 2) is NOT measurable from the T-080 records [CONTESTABLE]
death.t lives in the dying run's clock; the next run's first controllable tick lives
in another file's clock; no record carries wall-clock time; and the restart path's
real cost (the 5.0 s loading-screen minimum [CANON], the lobby walk) consumes NO sim
ticks by design. The report prints the death counts and the "not measurable from the
current records" line - no invented number. The fix belongs to a ticket that adds a
wall-clock stamp (or a recorded respawn-to-control tick) to the records.

### D-T081-5 - Signal 7's approximations: the chain estimate and the width split
The exact chain at a mine event cannot be reconstructed from the records (chain_reset
events write NO record), so the report uses the last gold gift's recorded chain
(+0.05, cap x2.00) while the 240-tick window holds, x1.00 otherwise - stated in the
report's source. The walkway-width split (1 / 2 / platform) has NO data in the
records (level_start carries counts, not per-slot widths): printed as "not
measurable from the current records" with the fix named (level_start would need the
mine slots' widths). Never invented, never dropped.

### D-T081-6 - Report location and the bucket conventions
The report lives in game/tools/run_report.gd, not tools/: a Godot headless script
must live under the game project to preload res:// scripts (bot_run.gd's precedent);
tools/ is outside the project. tools/run_batch.ps1 is the entry the ticket names and
lives in tools/ as specified. Conventions: a lobby's bucket is the level it ARMS
(level_completed + 1); the "overall" row is accumulated with the buckets (every
record lands in its bucket AND the overall slot), never recomputed; empty buckets
print zero counts - real counts, not blanks.

### D-T075-1 - The answer table is the single source; the lab only re-anchors it
game/tools/answer_lab.gd plays the documented answer through answers.gd's own
entry (answer_for/inputs_for), never a second copy of the numbers: the pair's
telegraph row fires the entry, the entry's tick offsets are the answer's
schedule, DELAY_TICKS is the addendum's 15. The T-026 --dodge and this lab
share the one table by construction.

### D-T075-2 - Trial design: 600-tick window, seeds, dasher, Last Light spent
Each pair runs 200 seeded trials per arm (seeds 1000..2199, per-pair scaled),
base stats, no upgrades, Last Light spent (the done-when's own words), dasher
class, 60 Hz. Window 600 ticks (10 s): the answer exchanges resolve in < 1 s
and the慢 slowest full telegraph cycle measured is the address me episode
(separate: the F8 combos get 1500 because the SR-4 gate defers the episode's
open until the player is quiet). A longer window cannot rescue a dead player -
the death is recorded the tick it happens - so the endpoint is well defined.

### D-T075-3 - Level choice per pair, and the not-named ones
research/fable-enemies.md section 2's pairing mapped to the five micro-levels:
kiwi (nook + flat), coil (hub + flat), ben (flat), seal (flat), you (flat),
nuke (flat), larper (flat + hub), toucher (flat), address me (flat), isagi
(flat: the F6 worst case + stepped: the 2 HU good case), claude (flat), gin
(flat). Section 2 does not name a level for most single enemies (it pairs by
ARCHETYPE, not per-enemy rows), so the picks above are the archetype's closest
micro-level, recorded here as the [CONTESTABLE] choice. The stacked cases use
the same levels with the cap vote counts (4/3/2/3/2/2/2/3 + larper 5); claude
is capped at 1 in the schedule and address me stacks are meaningless (the
one-at-a-time gate), so neither gets a stacked row.

### D-T075-4 - [CONTESTABLE] the answer executor's reaction timing
The addendum's 15-tick reaction (answers.gd DELAY_TICKS) is applied where the
doc's window admits it; the "ON the cue" rows press at 0 (seal "jump ON the
bark", claude "jump on the beat" - ON is the doc's own word, and a 0.25 s
reaction would forfeit them), the you's press waits for the rumble's end (the
ring's release), and the nuke's answer runs until the ring stops, not a fixed
0.5 s. These are TIMING readings of answers.gd's anchors, not enemy-number
changes; they are contestable and re-tunable per pair without touching the
doc's contract. The full mapping lives in answer_lab.gd's _pairs() header.

### D-ART-NUKE-1 - The nuke's frames are real art derived from NUKE.jpeg (game/tools/art/nuke.gd)
`NUKE.jpeg` (1280x261, opaque white background, a wide ICBM with booster nozzles at
the rear/right) could not go through `game/tools/sprite_pipeline.gd`: its flood fill
from the corners at tolerance 24/255 assumes flat corners, and on an opaque white
photo it eats the whole body (the pipeline's own "NO BODY AFTER BACKGROUND REMOVAL"
failure). The pipeline now skips any enemy with `game/tools/art/nuke.gd`, so the
module owns these frames and a later pipeline rebuild cannot regress them. The module
(headless SceneTree script, deterministic, no randomness) does: border flood fill from
all four edges at distance-from-white <= 0.20 (normalised RGB euclidean; the body's
maximum channel value is 0.86, so no body pixel can pass the threshold and the fill
cannot leak), a one-pixel feather ring on the body edge adjacent to background, crop
tight to alpha > 16, fit onto a 512x128 power-of-two canvas (fit scale
min(470/bw, 108/bh), 8 px minimum margin; no opaque pixel touches the canvas edge),
and writes `sprites/cycle_00..03.png` - the four frames the T-083 anim block's
`attack_descent` state lists (spec `nuke_00..03`, 12 fps = 5 ticks per frame, binding;
no tick, loop flag or effect parameter changed). The other five states list no frames
in the block and got none; their effects (lock ring, descent flash, explosion,
recover) are billboard/shader-level and change no body_rect. `sprites.json` now has
`"tbd": false`, per-frame `body_rect` equal to the tight alpha > 16 bbox
([21,14,470,99] / [28,9,456,106] / [11,19,489,93] / [24,15,463,101]), and the
`animations[]` entries kept the same filenames (nothing renamed or reordered; the
existing `cycle_00..03.png` listings now carry the real art). `sources[].state` reads
"attack_descent (base art...)". Fog contrast was initially 2.69/2.80 for cycle_00/01
(< 3.0): fixed ART-side with a tone lift (gain 1.25 + add 0.10 after the per-frame
bright/flame modulation), never by touching the threshold; all four frames now sit at
7.2-8.4 at 40 u. The frame derivations are: cycle_00 base burn (flame 1.15),
cycle_01 stretch 0.97x1.07 bob -2 px (flame 1.45), cycle_02 squash 1.04x0.94 bob +2
px, brightness flash 1.12 (flame 1.25), cycle_03 stretch 0.98x1.04 rotation +1.8 deg
bob -1 px (flame 1.60) - a 4-frame booster-burn cycle for the 12 fps loop.

### D-ART-NUKE-2 - The derivation constants are art judgment, owner may flip [CONTESTABLE]
No document states the stretch/squash percentages, the 1.8 deg rotation, the bob
offsets, the flame multipliers, the LIFT_GAIN/LIFT_ADD, or the FILL_TOL/FEATHER_*
values; they are taste applied over the owner's source image to satisfy the binding
checks (fog contrast >= 3.0 at 40 u, >= 15% transparent, tight body_rect) with a
visible burn cycle for `attack_descent`. The gameplay-relevant numbers (frame count,
tick ranges, effect params, hitbox body_rect semantics) are untouched. The owner may
re-tone the lift and re-shape the burn cycle by editing `game/tools/art/nuke.gd` and
re-running it; `validate_sprites.gd` will re-derive pass/fail, and `sprites.json`'s
`body_rect` must be re-synced to the printed `RECT` lines after every regeneration.

### D-ART-COIL-1 - coil's real-art derivation numbers (the shared pipeline skips this enemy) [CONTESTABLE]
ENEMIES.md and the T-083 block pin the frame COUNT, the file names and the tick
ranges, but no document states the canvas size, the base body height, the transparent
margin below the feet, the background-removal floor or the per-frame squash ratios of
coil's real art - so they are recorded here as SPEC GAPs rather than written silently
into game/tools/art/coil.gd. Chosen: (a) a 512x512 power-of-two canvas (the pipeline's
MAX_CANVAS ladder, both dimensions POT); (b) the cropped body fitted to a 400 px base
body height so the 120% extended frame (coil_04, the apex pose) still lands inside the
canvas with its bottom 8 px above the edge - the enemy is bottom-anchored (it stands on
the ground) and 8 px >= the 2 px transparent margin the validator demands on every
edge; (c) the five frames squash/extend at 50/65/80/100/120% of the base height - the
same ladder the shared pipeline used (COIL_PCTS, the ENEMIES.md squash -> extend cycle,
heights pinned to the SR-2 1.0 -> 2.0 u range via animations[].world_height) with width
compensation sx = 1/sqrt(sy) so a squashed spring widens and an extended one thins
(volume-preserving stretch, the classic squash-and-stretch read of "squash -> extend
cycle"); (d) the photo's backdrop is a flat near-white checkerboard (238/255 cells), so
background removal flood-fills from the border eating any pixel whose darkest channel
is >= 233 and then keeps only the largest connected opaque component (the metal wires
dunk to ~100 so they block the fill; stray sub-233 anti-alias specks stranded in the
backdrop are erased by the largest-component keep); (e) frames are byte-stable: no
randomness anywhere in the module. Gameplay reason: the spring is the T-031 jumper -
the squashed coil_00 reads as "compressed on landing" at 1.0 u and the extended coil_04
as the apex pose at 2.0 u; nothing here moves a tick, a loop flag, an effect parameter
or the hitbox rule (body_rect = tight bbox of alpha > 16 per frame).

### D-ART-THICC_BEN-1 - thicc ben has an art module; the photo is cut out by a white flood fill + defringe, then graded gilt to clear A8's fog contrast
The owner image (`assets_src/enemies/thiccben.png`, 767x599) is a PHOTO: pure white background at the top/sides, the building's dark base running off the bottom of the frame, no single background colour - so the shared corner flood fill in `sprite_pipeline.gd` (tol 24) cannot cut it out, and this enemy is skipped by the pipeline in favour of its module, `game/tools/art/thicc_ben.gd` (headless, deterministic; run as `--script res://tools/art/thicc_ben.gd`). Pipeline: flood fill from the border against near-white (tol 45), then an iterated defringe pass (clears foreground pixels adjacent to background closer than 128 to white, the anti-aliased halo; 1717 px); crop tight to alpha > 16; fit onto a 512x512 canvas bottom-anchored (the tower stands on the ground) with a 6 px transparent margin. The raw photo's mean opaque colour scores fog contrast 1.56 against the #021416 fog - A8 requires >= 3.0 at 40 u, so the ART was adjusted (never the threshold): the body is graded toward warm gilt (`c*1.7 + (22,18,14)`, sRGB), landing at 3.29 (attack_arrival's white-blend pose: 9.37). `body_rect` values are the tight alpha > 16 bboxes the tool prints; the anim block's ticks, loops and effect params are untouched; `telegraph` lists zero frames and stays empty.

### D-ART-THICC_BEN-2 - The derived-pose parameters [CONTESTABLE, art direction]
One distinct frame per anim-block state, derived procedurally from the base body (deterministic, no randomness): `cycle_00` = the base body (idle, `thiccben_00`); `spawn_00` = squash anticipation (sx 1.14 / sy 0.78, bottom-anchored; the block's common_fade stays a view-side shader effect and is not baked); `attack_arrival_00` = 78% blend toward white (the block's white_flash, baked as the pose); `attack_ring_00` = +8 deg rotation about the feet pivot (== the block's `rock_deg` 8.0, mid-swing of the +/-8 deg twice rock); `recover_00` = 1.07 vertical stretch with x 0.95 and 40% luminance-preserving desaturation. A recover pose DARKENED to read as "spent" was rejected: any multiplicative dim below ~x0.8 drops the mean opaque colour under the 3.0 fog-contrast floor, so recover keeps luminance and changes pose/saturation instead (measured 3.18). Transforms render onto a 2x-padded intermediate and are cropped back to their alpha bbox and bottom-anchored, so every pose keeps the >= 2 px transparent margin and the tight `body_rect` by construction. These numbers are art direction, not gameplay; the owner may retune them. No threshold, tick, loop flag or effect param changed; ENEMIES.md untouched; no PARKED rows.

### D-ART-KIWI_CAT-1 - kiwi_cat background removal uses the source alpha channel; the flood fill is the fallback (T-ART-KIWI_CAT).

`assets_src/enemies/kiwicat.png` (636x769, RGBA8) ships an alpha-channel cut-out with all four
corners already alpha 0 (sampled: alpha 0.0, colour ~(0.28, 0.44, 0.30)), so NO colour-keying
is applied - the alpha channel IS the background mask and the tight body crop is the bbox of
alpha > 16 (443x320 at (92, 284) in source coordinates). `game/tools/art/kiwi_cat.gd` keeps a
documented fallback for a re-export with opaque corners: sample the border colours (stride 8),
flood fill inward from every border pixel at per-channel distance <= 24/255, zero what the fill
reaches. The fallback is skipped for this source; it exists so a source swap degrades to a
logged path, never to the "NO BODY AFTER BACKGROUND REMOVAL" TBD trap the naive corner fill hit.
The naive pipeline's 24/255 tolerance stays the reference the fallback copies.

### D-ART-KIWI_CAT-2 - The four frames and the ONE-spec-frame constraint (T-ART-KIWI_CAT).

The section 1.1 table gives all three visual states (spawn, idle / chase, telegraph) the single
spec frame `kiwicat_00`, so `frame_map` - keyed by spec frame name - can only ever hold ONE
target. It maps `kiwicat_00` -> `sprites/cycle_00.png` (the base body; byte-identical rebuilds,
verified by re-running the module and diffing). The per-state art lives in `states[*].frames`
and in the top-level `animations[]` instead: `sprites/spawn_00.png`, `sprites/idle_chase_00.png`,
`sprites/telegraph_00.png` are DISTINCT files, all derived deterministically from the base body
(no RNG, no wall clock, pure functions of the source):
- `cycle_00.png` - the base body, unaltered (the legacy single-frame "cycle" loop; it stays
  `animations[0]` with 1 frame, which test_enemy_kiwi_cat.gd pins).
- `spawn_00.png` - base at 1.25x brightness [CONTESTABLE: the common_fade spec owns alpha and
  scale, not pigment; the lift exists so the spawn frame is visually distinct and reads as a
  materialize shimmer. Gameplay reason: the spawn fade is the player's only tell that the 30
  contact-blocking ticks are running].
- `idle_chase_00.png` - base squashed to 96% height about the bottom line (LANCZOS) [CONTESTABLE:
  the bob (+-0.08 u at 1.0 Hz) stays the bob EFFECT; the 4% breathing compression is the frame's
  own tell. Gameplay reason: the chase frame never leaves the screen, a 4% squash reads as idle
  breathing without changing the hitbox materially (body_rect 443x307 vs 443x320)].
- `telegraph_00.png` - base blended 30% toward danger red #FF2A2A at 1.15x brightness [CONTESTABLE:
  the spec's telegraph effect is the scale_pulse transform; the red blend is pigment so the meow
  cue reads at a glance. Gameplay reason: ENEMIES.md / section 1.1 make the meow the cat's ONLY
  telegraph - the danger red is the spec's named telegraph colour; 30% keeps the cat readable
  while still unmistakably red-shifted].
`attack` and `recover` list no frames (contact-kill with no wind-up) and stay empty, exactly as
the table says. The tick counts, loop flags and effect parameters in the anim block were NOT
touched. The frame fps for the three new sheet rows is 1 (a single held/looping frame; fps is
not binding for the sheet and check_anim_data.gd does not pin it - the T-083 block is the binding
table).

### D-ART-KIWI_CAT-3 - The A8 fog-contrast lift is ART, not a threshold change (T-ART-KIWI_CAT).

The first real rebuild (commit 4d884b5, reverted) failed A8: kiwi_cat/cycle_00.png measured fog
contrast 2.69 < 3.0 at 40 u. Resolution here: a uniform 1.22x brightness lift on every frame
(BODY_LIFT in tools/art/kiwi_cat.gd), keeping the source's hue (brown-orange kitten) - measured
after the lift (validate_sprites.gd SPRITE_DEBUG=1, fog #021416, d = 40 u, linear-space lerp per
D-T016-4): cycle 3.550, spawn 4.948, idle_chase 3.548, telegraph 4.045. No threshold, no palette
entry, no validator line was moved. The 2 px transparent margin and the >= 15% transparent rule
hold on every frame (body 443x320 of 512x512 = 73% transparent on cycle; idle_chase 77%).

### D-ART-KIWI_CAT-4 - kiwi_cat_view.gd reads the per-state frames (the enemy's own view, minimal).

Frame display goes through `view/billboard.gd`, which plays `animations[]` by name and never reads
the anim block's per-state frames; `view/enemy_anim.gd` resolves a shown frame via `frame_map`
ONLY (its `_frame_docs`/hit shape are keyed by disk path, so every path must be listed in
animations[] - they are). Neither can show a per-state frame for a state whose spec frame shares
the single `kiwicat_00` name without a change. Rather than touch the shared player, the
kiwi cat's own view (game/view/kiwi_cat_view.gd) now swaps the billboard animation with the
state it already tracks: `spawn` frame on enemy_spawn, `telegraph` frame on the meow cue,
`idle_chase` otherwise, with the base scale re-captured from each frame's body_rect
(`_set_anim`). The effect code (spawn fade, bob, pulse) is unchanged; billboard tests and
test_anim_sync stay green (billboard tests use an inline two-frame sheet; anim_sync reads
frame_map -> cycle_00.png, which exists and is real art). If a future ticket wants ALL enemies'
state art shown through the shared anim player, `frame_path()` preferring
`states[state].frames[frame_index()]` over `frame_map` is the no-op-for-single-spec-frame
extension - not done here (shared file, not needed for kiwi).

### D-ART-KIWI_CAT-5 - SOURCES.md / TBD.md reconciled; nothing else left TBD for kiwi_cat art.

SOURCES.md now records the art-module path and the lift; TBD.md section 1 (the 17 enemy images)
and the top table's row 1 record `kiwicat.png` as PRESENT -> real art with `"tbd": false`. TBD.md
section 4 carries no kiwi row (the T-083 block names the files that exist, and they now exist as
real art). ENEMIES.md is unchanged (frozen, D-040); the ENEMIES.md "1 base PNG" rows describe the
SOURCE count, not the frame sheet.

### D-ART-ISAGI-1 - Isagi's real-art derivation recipe (T-016 art module, tools/art/isagi.gd)
The T-016 pipeline could not strip Isagi's opaque-white photo/logo sources (its corner flood
fill at colour tolerance 24/255 reports "NO BODY AFTER BACKGROUND REMOVAL -> TBD"), so the
isagi frames are owned by `game/tools/art/isagi.gd` instead; the pipeline now SKIPS any enemy
with `tools/art/<id>.gd` (its own skip rule, read at sprite_pipeline.gd's skip branch - the
pipeline file itself is untouched). The art-derivation numbers below are stated NOWHERE in
the documents and are recorded here BEFORE the code that uses them; each is [CONTESTABLE].
The spec's own binding numbers (anim-block tick ranges, loop flags, effect names and
params, world_height 1.8 / shot 0.5) are NOT touched; the derived frames feed the effects,
never replace them.

Recipe (deterministic; no randomness at all):
- background removal, `isagi_idle.jpeg` / `ISAGI_SHOOT.webp` (opaque white): reference colour
  = mean of the four corners; flood fill from every border pixel with euclidean distance
  < 72/255 from the reference; filled pixels' alpha set to 0. [CONTESTABLE - 72/255; chosen
  so JPEG noise/anti-aliasing (background pixels up to ~230 in-channel) is caught while the
  manga-grayscale face (~#D9D9D9, distance ~66) stays enclosed by dark hair/clothes outlines;
  the flood fill is border-connected so enclosed light regions can never be eaten]
- `blueballprojectile.webp` (corners already alpha 0): its alpha channel is used as-is;
  pixels with a <= 16/255 are pinned to a = 0. [CONTESTABLE - reuses the validator's alpha > 16
  body threshold; no colour flood at all]
- tight crop to alpha > 16/255 (the validator's body rule, verbatim); transparent margin
  MARGIN = 8 px on every side, so no opaque pixel touches the canvas edge and the 1-px opaque
  border check can never trip. [CONTESTABLE - 8 px; smallest margin that keeps the 2 px red
  telegraph rim fully inside the canvas]
- canvas: each side the smallest power of two >= body + 2*MARGIN, capped at 512 (body
  downscaled with LANCZOS only when larger, never upscaled); body frames bottom-anchored
  (feet on the node origin, matching billboard.gd's feet rule), ball centred. Rectangular
  POT canvases allowed by the brief ("power-of-two canvas no larger than 512"). [CONTESTABLE
  - canvas shape/anchor; bottom-anchor keeps the stretch variants' feet planted]
- `fire_01.png` (the one the T-083 block leaves unreferenced): squash sy 0.90 / sx 1.06,
  LANCZOS, bottom-anchored. [CONTESTABLE - squash factors]
- `spawn_00.png`: brightness x1.30 then 35% lerp toward #BFFFF8 (the palette player_fill_light
  cyan-white), alpha untouched - a materialize look layered under the binding common_fade
  (alpha 0 -> 1, scale 0.8 -> 1.0 are runtime effects and stay untouched). [CONTESTABLE -
  1.30 and 0.35; the effect timings are binding, the baked look is not]
- `telegraph_00.png`: red rim baked around the silhouette - Chebyshev 2 px ring, #FF2A2A
  (the palette danger hex), alpha 0.85 (1 px ring) / 0.45 (2 px ring). The binding red_rim_flash
  timing (periods 24 -> 12 -> 6) and the aim line remain runtime view effects. [CONTESTABLE -
  ring width 2 and alphas 0.85/0.45; the anim-block periods are binding and untouched]
- `recover_00.png`: brightness x0.70, matching the binding recover effect (sprite at 70%
  brightness = "cannot fire", 150 ticks). [CONTESTABLE - 0.70 is stated by the anim block's
  dim effect; baking it is the distinct-frame requirement]
- `shot_00.png`: the projectile ball, art as-is (white/navy ball, dark-blue panels). The 720 deg/s
  spin and the 1.0 u width stay runtime values.
- `fire_00.png` = the idle art, `fire_02.png` = the shoot art (the legacy `fire` animation,
  animations[0], keeps its name/order/frames; real art replaces the TBD placeholders).
- animations[] gains five APPENDED entries, after the existing `fire` and `shot`:
  `idle`, `spawn`, `telegraph`, `attack` (points at shoot_00.png), `recover`. Existing
  entries are not reordered or renamed (views/tests read animations[0] by index and name).
- body_rect of every listed frame = the tight bbox of alpha > 16/255 on the final canvas,
  the validator's rule verbatim; `tbd` flips to false only because every listed frame is real art.

Fog contrast at 40 u (validate_sprites.gd A8, threshold 3.0, never moved): the idle is
grayscale manga art and the ball is white - both pass with room; the shoot (navy jersey) and
the x0.70 recover frame were measured with SPRITE_DEBUG=1 and, if either lands under 3.0,
the ART gets lightened (never the threshold) - see D-ART-ISAGI-2 when it lands.

### D-ART-ISAGI-2 - Isagi's bodies are lerp-toward-white lifted to clear the fog check (art lightened, never the threshold)
D-ART-ISAGI-1 promised: if the shoot (navy) or the x0.70 recover frame lands under the fog
contrast of 3.0 at 40 u, the ART gets lightened - never the A8 threshold. Measurement with
SPRITE_DEBUG=1 (validate_sprites.gd):

| art state | mean opaque colour | ratio vs fog @40 u |
|---|---|---|
| idle/fire_00 (grayscale manga) | 0.3218 | 1.88 FAIL |
| fire_01 (squash) | 0.3225 | 1.88 FAIL |
| fire_02/shoot_00 (navy jersey) | (0.306, 0.290, 0.411) | 1.77 FAIL |
| telegraph_00 (red rim baked) | (0.355, 0.314, 0.314) | 1.88 FAIL |
| recover_00 (x0.70 dim) | 0.2241 | 1.39 FAIL |
| spawn_00 (brightened + cyan lerp) | (0.512, 0.601, 0.589) | 4.25 pass |
| shot_00 (ball, white/navy) | (0.733, 0.755, 0.807) | 6.81 pass |

A pow(c, p) gamma lift was tried first: p=0.30 gave the idle 3.30 but recover stayed at 2.04;
p=0.24 gave recover 2.17; p=0.17 gave recover 2.36 - the curve flattens too fast for this dark
mass. Replaced with a lerp toward white, c' = c + (1-c)*s (stronger on darks, highlights
compressed): idle/fire bodies and the telegraph rim derive from an idle lifted with s=0.55,
the shoot body with s=0.45, ball untouched. Recover stays the binding x0.70 dim of the lifted
idle (the 0.70 factor itself is the anim block's binding effect number and is not touched).
Measured after the change: SPRITES OK 340 checks over 12 sprites.json - every isagi frame
passes the four corners / opaque border / 15% transparent / fog contrast / body_rect checks.
The sprites now read as deliberately bleached (manga ink on near-white); the cost is art fidelity,
the alternative reading (a brighter recover that would not be the binding 70% brightness) was
rejected. [CONTESTABLE - the 0.55 / 0.45 lift strengths; the art-fidelity trade-off; a real
artist pass could rebalance with a designed light rim instead of a global lift]

### D-ART-YOU-1 - YOU?! frames: image segmentation against a near-fog source [CONTESTABLE]
The source `character to be corrupted.png` is an opaque render on a smooth grey gradient
whose white head is within ~0.03-0.09 sRGB luminance of the background and, on the right
side of the silhouette, has NO luminance edge at all, so no purely colour-based flood fill
from the border can isolate it (the shared corner-flood pipeline ate the whole image and
left TBD frames). The art module `game/tools/art/you.gd` therefore segments by:
(1) a LOCAL flood fill from the four borders at distance tolerance 0.025 (EUclidean, 0-1)
to reject the far-field gradient; (2) a dark core (luminance < 0.5) kept everywhere;
(3) a manually fitted head ellipse (centre (200, 171), radii (74, 46) px on the 406x601
source), because the head is indistinguishable from the background by colour there;
(4) the crown zone (y < 145) keeping light pixels within 4 px of the dark core (the white
spikes); (5) a 2-px dilation of the dark core intersected with the flood result (soft
edges); white background wall-panel islands are rejected because they are not dark-core,
crown-zone or head pixels. The background fill itself IS the requested border flood fill;
the ellipse is a hand-fit segmentation of the owner's own pixels, viewable in the module.
Art tuning, not sim: no threshold, tick or rule moves. [CONTESTABLE]: if the owner
re-renders the character on an alpha-0 or flat backdrop, the ellipse can be deleted and
the flood fill alone suffices.

### D-ART-YOU-2 - YOU?! frames: canvas, fit, contrast lift and the per-state set [CONTESTABLE]
The owner image is mostly very dark (black body) on the near-black palette fog
(2, 20, 22; visible(40 u) = exp(-0.012*40) = 0.619), which fails the A8 fog-contrast
check at 40 u if pasted as-is. The module applies a deterministic lift before any
per-state transform: c' = clamp(c * 0.72 + (0.29, 0.345, 0.39)) in sRGB plus a 1.15
saturation restore (the green weight does the fog-contrast work), plus a 35% blend of the
1-px silhouette edge toward pale pink (1.0, 0.83, 0.89) as a rim. Frames are rendered on a
512x512 canvas (the largest power of two allowed), bottom-anchored with feet at y = 496
and a 16 px transparent margin (spec: no opaque pixel within 2 px of the edge). Frame
names are `sprites/you_<state>_NN.png` (spawn 00; idle_chase 00-04; telegraph 00-04;
attack 00; recover 00-04) plus `sprites/cycle_00..04.png` re-rendered as the chase cycle
and kept at animations[0]. Effects per state are procedural and seeded (slice displacement
uses seed 1984 / 77): spawn = white flash + tear slices; idle_chase = squash/stretch +
bob +-2.5 deg lean; telegraph = 1/2/3/4/6 px baked ghost split (red/cyan), noise slices and
a growing red mix (0/.08/.16/.24/.30) on top of the view's own 0->6 px shader split;
attack = mirrored white-hot flash + stretch; recover = desaturation/dim ramp
(.70/.50/.32/.15/0 at 0.94/0.96/0.97/0.985/1.0 - the dim floor is pinned by the fog
contrast check on the darkest recover frame) back to normal. Numbers invented here are
art tuning only (gameplay reads colour through the same fog rule; no threshold moved).
[CONTESTABLE]: the exact lift/rim/ramp values are the minimum that satisfy fog contrast
>= 3.0 at 40 u with the least wash-out of the black body; owner may re-grade the source.

### D-ART-TOUCHER-1 - the toucher's per-state frames render through a minimal view patch
The T-083 anim block pins spec_frames (spawn=[toucher_00], idle_chase/telegraph=[toucher_00..02],
attack_infect=[toucher_02]) and check_anim_data.gd pins those verbatim, while frame_map is GLOBAL
per enemy - so telegraph and idle cannot resolve different files through the shared player's
frame_path() (view/enemy_anim.gd, untouched). The brief (this art wave) demands a distinct frame
per state; the pinned table reuses the spec names (its telegraph distinctness rides the binding
scale_pulse effect, exactly as section 1.8 states). Built closest to the brief WITHOUT touching
the binding machinery: the states[*].frames arrays list the new per-state files (this is the one
per-state lever the block has); animations[] keeps cycle+floor (body_rect updated to the real
frames) and appends spawn/idle/telegraph/attack_infect; frame_map resolves toucher_00..02 onto
cycle_00..02 (the same finger art; the shared player's hit shape and the tests' frame_texture both
land on real, consistent pixels); and game/view/toucher_view.gd - the enemy's OWN view, not a
shared file - was minimally patched: set_stage records the active state, set_stage_frame swaps the
billboard texture for that state's block frame when available, and set_texture prefers it over the
frame_map target (probe-verified: spawn/idle_chase/telegraph/attack_infect show spawn_00 /
idle_00 / telegraph_00 / attack_00; frameless states keep holding the last frame). All body frames
keep ONE identical silhouette (colour-only derivations - brightness bands, scanlines, tints; never
geometry), so billboard scale/feet offset and the hit shape cannot disagree with whatever frame is
shown; the floor decals carry their own per-frame body_rects (row-displacement glitch). No tick,
loop flag, effect parameter, spec_frame, tick range or anim-row key changed; no shared sim/view
file other than the toucher's own view was edited. The residual ambiguity (brief vs pinned block)
is PARKED.md #18 - owner to rule. A8 moved nothing; validate_sprites: SPRITES OK 255 checks.

### D-ART-TOUCHER-2 - the floor decal was relit, not the threshold (A8 fog contrast)
The glitched-floor source (300x300 isometric magenta/black cube on opaque white) fails the brief's
A8 rule as-is: kept dark, its mean opaque colour sits near the Deepwater fog (#021416) and reads
~2.1 at 40 u (the dark faces dominate the mean, not the fog colour itself). The ART was adjusted
inside tools/art/toucher.gd: background keyed out by border flood fill (white >= ~61/255, no cube
pixel is near white), tight crop, then the faces are remapped to a glowing magenta family (seam
~0.55/0.13/0.55, shadow face ~0.92/0.16/0.90, mid ~1.00/0.22/0.97, top ~1.00/0.62/1.00) with
per-frame pulse/cool variants - keeps the isometric cube read, drops the black faces to thin
seams. Measured means / ratios at 40 u: floor_00 3.06+, floor_01 3.1+, floor_02 3.0+, floor_03 3.45,
floor_04 3.49 (final SPRITES OK). The finger needs no help (mean ~0.81/0.64/0.27, ratio 4.4-5.9).
spawn_00 was lifted 0.78 -> 0.90 mult for the same rule (2.90 -> above 3.0). These palette numbers
are art choices driven by the measured A8 ratio, not spec numbers; no threshold, palette or check
was touched. The finger's backdrop is removed by a border flood fill at tolerance ~34/255 (a global
key would have eaten the finger's dark outline pixels, e.g. (36,20,0)); the JPEG ring noise inside
that tolerance is fully enclosed.

### D-ART-GIN-1 - gin's frames are cut by game/tools/art/gin.gd, not the shared pipeline (T-ART-GIN)
The two owner sources are opaque (`gin idle.png` border #F7F7F7; `ginsword.png` border #FFFFFF),
so the shared pipeline's 24/255 corner flood fill eats the whole image and reports NO BODY; the
enemy stayed TBD after the revert. `game/tools/art/gin.gd` owns gin's frames (the pipeline skips an
enemy that has this module): distance-to-border-colour threshold + a 4-connected flood fill from
the border - `gin idle.png`, border #F7F7F7, tolerance 70 (removes the soft drop shadow and the
white glare arc, keeps the cel-shaded outline; the robe's near-white interior is reachable only
through the dark outline, so it stays opaque), `ginsword.png`, border #FFFFFF, tolerance 32 (the
silver blade reads ~#C6C6C6 and must survive). Tight crop to alpha > 16, 512x512 canvas (power of
two, <= 512), the body bottom-anchored (gin stands on the ground), the sword centred, a transparent
margin of >= 2 px. The sword's blade is cut off by the source canvas at the bottom-left corner -
kept as authored (owner's art, Image 17).

### D-ART-GIN-2 - one distinct derived frame per anim-block state; the derivation parameters are [CONTESTABLE]
`attack_void_zone` keeps zero frames (the void zone is VFX; the state lists none). Every other
state of the T-083 block now points at its own file, each derived from the base body: idle_00 =
base; spawn_00 = materialize tint toward #CFF6FF k=0.35 + brightness +0.08 (the spawn fade is the
state's runtime effect; this is the body mid-assembly); telegraph_00 = stretch (0.94, 1.08) + red
charge tint toward #FF4A3C k=0.14 (the mark's outline is #FF2A2A) + brightness +0.10 (the rumble);
launch_00 = the sword source + white-hot tint toward #FFFFFF k=0.12 + brightness +0.18 (the shing);
recover_00 = desaturate 0.45 + brightness -0.25 (ghosting out after the launch). All of these are
[CONTESTABLE] art-derivation parameters: no document states them; any equivalent recipe yields the
same game, and the T-083 tick counts, loop flags and effect params are untouched (D-040). Every
frame's body_rect is recomputed as the tight bbox of alpha > 16 (HITBOXES); the spec frames stay
`gin_idle_00`/`gin_launch_00` and frame_map points them at `idle_00.png`/`launch_00.png`.

### D-ART-GIN-3 - launch_00 fits the sword in a 500 px box, not 508 (T-ART-GIN) [CONTESTABLE]
T-084's probe `(2,2)` of the frame shown must never hit (TRANSPARENCY padding). A 508 px fit on a
512 canvas left opaque pixels at (2,2) - the launch frame is the only gin frame whose body_rect can
start that close to the origin - so the sword is fitted to 500 px (6 px margin, body_rect
[6,6,499,500]). No test file was edited; the validator's 2 px floor is untouched (the margin is
larger, never smaller); only the art changed. Same class of choice as D-ART-GIN-2 (an art parameter,
not a threshold).

### D-ART-gift_larper-1 - The gift Larper's frames are real art derived from tripine.png (game/tools/art/gift_larper.gd)
`assets_src/enemies/tripine.png` (800x800 RGBA, the owner's photo of the Roblox tripmine,
ENEMIES.md section 1.7 image 9) could not ship as-is: its four corners are already alpha 0
(measured (0,0,0,0) at all four; zero non-zero-alpha pixels on the four edges; 71.5% of px
alpha 0; 8946 partial-alpha px with mean rgb (54,0,49), the same hue family as the body mean
(33.2, 2.7, 52.5) - matted on black, no foreign-colour halo, and the fog #021416 is near-black,
so the dark fringe is invisible by construction and the defringe pass is the alpha key itself),
but the near-black body is WCAG-vs-fog luminance ~0.019 - fog contrast ~1.0 at 40 u against
#021416, far under the ENEMIES.md hard rule (mean opaque colour vs fog >= 3.0 at 40 u) and under
every biome fog. The module (headless SceneTree, deterministic; the shared pipeline SKIPS this
enemy) does: border flood fill from every border cell over pixels with alpha == 0, the filled
region becomes transparent black, only the largest connected opaque component survives, crop
tight to alpha > 16 (bbox (58,72) 739x688), a GRADE pass (screen blend against
(175,76,192)/255, see D-ART-gift_larper-2), fit on a 512x512 POT canvas bottom-anchored with
MARGIN 8 px on every edge (module asserts no frame touches the canvas edge; validate_sprites.gd
passes 220 checks), and writes the 6 frames the T-083 block can name: `cycle_00..04.png` (idle
spec larper_00..04 - cycle_00 identity, cycle_01 rotate +5.0 deg about the feet pivot sy 0.94 /
sx 1/sqrt(0.94) yoff -21, cycle_02 horizontal mirror + pulse 1.14 yoff -4, cycle_03 rotate -5.0 deg
sy 1.06 / sx 1/sqrt(1.06) yoff -19, cycle_04 horizontal mirror; the rotated frames lift by the
downward swing of the rotated bottom corners) and `defused_00.png` (the defused pose: 70%
desaturated toward each pixel's own linear-luminance gray, sy 0.78 - deflated; grey_out/drop_u
stay view-side). The spawn state keeps cycle_00 (larper_00; present from level start, no fade);
telegraph and attack_detonation keep ZERO frames - the section 1.7 table genuinely lists none
(the tell is the 12 u look; the detonation is the 18-tick white flash + pink->black burst,
shader-side); defused now names the real defused pose in the block (one entry, matching its one
spec frame larper_00). animations[] lists the cycle entry (unchanged names, loop, fps 10) plus
an appended "defused" entry; animations[] was NOT reordered. The anim block's tick ranges, loop
flags, fps and effect parameters are untouched; world_height stays pinned 1.0 with
body_height 1.0 / hit_diameter 0.8 (D-T073-2, test_enemy_gift_larper.gd). No frame_map was added:
the spec frame larper_00 legitimately backs spawn + idle[0] + defused, so a spec->file map would
misrepresent one of the three (the nuke's pattern does not transfer); the view drives frames
itself (gift_larper_view.gd), and enemy_anim.gd leaves the frame path unresolved exactly as it
found it (frame_path() falls back to the spec name, which does not exist on disk - the same
status quo as before this art pass; the HITBOXES body-rect probe row is vacuous for this enemy,
as it was on the TBD art). Fog contrast (validate_sprites.gd, palette fog #021416, d = 40 u):
cycle_00/04 3.17, cycle_01 3.50, cycle_02 3.87, cycle_03 3.51, defused_00 3.05 - all >= 3.0, the
ART was lifted, never the threshold. Per-biome fog_check (direct WCAG ratio, enemy rows): 4.5-6.0
at violet_hour / pale_abyss; FOGCHECK OK (260 checks over 5 biomes). validate_sprites.gd:
SPRITES OK 220 checks over 12 sprites.json. check_anim_data.gd -- gift_larper: PASS (5 states).
The defused view path now shows the defused pose during the 24-tick grey-out (gift_larper_view.gd
set_animation("defused") in on_defused(); the idle 240-tick frame advance is suspended while
_def_left > 0; on_spawn restores "cycle"). tbd = false only after every frame became real art.

### D-ART-gift_larper-2 - The art-derivation numbers are judgment, owner may re-tone [CONTESTABLE]
No document states the screen-blend grade colour (175,76,192), the squash/stretch factors, the
+/-5.0 deg rotations, the yoff lifts, the 1.07/1.14 light pulse, the defused 70% desaturation or
the defused sy 0.78 - they are art judgment applied over the owner's source to satisfy the
binding checks (fog contrast >= 3.0 at 40 u - roughly three and a half times the source's own
luminance -, >= 15% transparent, tight body_rect, distinct visible frames for the five-slot
turning/pulsing cycle) without moving a tick, a loop flag, an effect parameter or a body_rect
semantic beyond the printed bboxes. Gameplay reason: the 400-tick rotation cycle is the mine's
only idle motion read at 1.0 u world height; 0.94/1.06 sy reads as a turn without breaking the
tripmine's rigid-body feel, the mirror flip is the cheapest legible yaw at this size, the pulse
1.00->1.07->1.14 is the "light pulsing" the section 1.7 table names, and the deflated grey defused
pose sells "defused, no blast" before the sprite hides at tick 24. The owner may re-tune the grade
in game/tools/art/gift_larper.gd (re-run it, then re-paste the printed body_rect lines into
sprites.json and re-check both thresholds). The cycle names, frame count, the anim block's tick
ranges, the pinned world_height 1.0 / body_height 1.0 / hit_diameter 0.8 and every FINAL marker
stay untouched.

### D-ART-SEAL-1 - the seal's real art: cutout recipe and frame derivation (owner ticket, babehseal.webp)
`assets_src/enemies/babehseal.webp` is an OPAQUE PHOTO (white harp-seal pup on a blue-grey
gradient snowfield) that the shared pipeline's corner flood fill cannot cut out (its corners
are opaque, and the gradient eats any tolerance). `game/tools/art/seal.gd` owns the enemy's
frames and sprite pipeline skips it by design. The recipe, committed because the constants
are art-internal [CONTESTABLE - none of these numbers is gameplay, none is an ENEMIES.md
number, and every one of them is wrong for another enemy]: background estimated per COLUMN
as a vertical lerp of the top/bottom border rows; a pixel is body when its max channel
distance to that model is >= 33 (BG_DIST) and its luminance is > 100 (LUM_MIN); binary OPEN
with radius 4 (erode then dilate, CLOSE_R) drops snowfield speckle; the largest connected
component is the body; holes enclosed by the body are filled. The cutout keeps the body's
own fur colours; the missing fur rim is a SYNTHESIZED fluff fringe (two octaves of
seeded value noise, alpha falling off over 14 px outward, tinted from the brightest 15% of
body pixels). Canvas: 512 x 512 (max power of two), body scaled to 448 px, bottom-anchored
(the seal lies on the ground) with a 12 px transparent bottom margin. Frames: idle_00 = the
base; idle_01 = flap-lean (-5 deg shear about the bottom edge, +7% brightness); spawn_00 =
base (the fade is the view's job); telegraph_00 = spec seal_01, the mouth-open gape
(dark ellipse + gummy lower lip under the nose, nose located at abs (177,251)); dash_00 =
lunch-lunge (-5 deg shear, +22% brightness) = the attack pose; dash_01 = upright (+10%);
recover_00 = base stretched +6% vertically, +6% brightness. body_rect in sprites.json is the
tight bbox of alpha > 16 per frame, computed by the tool itself. Deterministic: the only
noise is the seeded fringe/value-noise hash (seeds 11/29/47); a rebuild is byte-stable.
The T-083 anim block is satisfied with exactly the binding frame count per state
(one entry per spec frame - the validator's contract): spawn -> spawn_00; idle_flap ->
[idle_00, idle_01] (9 ticks/frame, loop); telegraph -> [telegraph_00] (45 ticks held);
attack -> [dash_00] (the checker pins frames == spec_frames; the flap alternates in the
'dash' animation clip at fps 10); recover -> [recover_00] (45 ticks). frame_map:
seal_00 -> idle_00.png, seal_01 -> telegraph_00.png, seal_02 -> idle_01.png,
seal_03 -> idle_00.png. The view (`game/view/seal_view.gd`) was edited MINIMALLY: the
telegraph holds the telegraph state's frame (telegraph_00, the mouth-open), the recover
state holds recover_00 - both loaded from the block, same as before; its attack state now
holds dash_00 (the lunged pose) instead of ending on a single TBD frame; the header comment
reflects the real art. No sim, threshold, or binding tick changed. Validation: SPRITES OK
240 checks over 12 sprites.json; FOGCHECK OK 275 checks over 5 biomes; TESTS 54 passed
0 failed, zero SCRIPT ERROR lines (the gate's criterion); ANIM-DATA seal PASS. [CONTESTABLE]
on the art constants only - nothing gameplay-facing.

### D-ART-SEAL-2 - sprites.json round trip normalises JSON number types
Rewriting sprites.json via JSON.parse + stringify turns every number into a float
(Godot 4 JSON.parse_string has one number type), so e.g. `"total_ticks": 30` becomes 30.0
and body_rect arrays become float arrays; the two pre-existing entries ("idle", "dash")
are rewritten in the same shape. Every consumer in-repo (validate_sprites.gd,
check_anim_data.gd, enemy_anim.gd, billboard.gd, test_enemy_seal.gd, seal_view.gd) reads
numbers via float()/int() and passes unchanged (SPRITES/TESTS/ANIM-DATA all green), and the
2-space indent of the original file is kept. Accepted rather than text-patching the JSON,
because the block gains a frame_map and four animation entries; noted so a future diff
review does not hunt a phantom content change.

### D-ART-SEAL-3 - the seal's frames are regenerated from the owner's replacement source (babehseal.png); the ticket asked for D-ART-SEAL-2, but that number is taken
Owner ruling 2026-11-17: "seal also needs to have its PNG replaced with this". The new source is a
transparent-background 640x480 palette PNG of a harp-seal pup lying on its belly (white fur, big
round dark eyes, black nose, whiskers, front flippers forward, facing the camera); it is committed
at `assets_src/enemies/babehseal.png` and the old `assets_src/enemies/babehseal.webp` is REMOVED -
exactly one source per enemy now (the assets commit a4835c7, which also notes the address-me
explosion keeps its background). D-ART-SEAL-2 was already taken by the sprites.json round-trip
normalisation note, so this entry is D-ART-SEAL-3; D-ART-SEAL-1 stays as the record of the webp
cutout recipe it supersedes.
Measured on the real image: corners and all four edges alpha 0; body at alpha ~254 (modal), a
~10 px feathered edge (not hard); 156,080 px at alpha 0; the tight alpha > 16 bbox measures
(10, 44) 612x339 (tool print; a PIL spot check gives (11, 45) 610x338 - the 8-bit threshold
rounds differently, both are alpha > 16). Background removal = the source's OWN alpha channel:
NO flood fill, NO defringe, NO one-pixel feather was applied (the edge needs none). Crop = tight
alpha > 16 bbox; 512x512 POT canvas, body scaled to 448 px width, bottom-anchored, 12 px bottom
margin (unchanged layout). The synthesized fluff fringe of D-ART-SEAL-1 is gone - the source
carries real fur alpha. Frames (same seven files, same anim-block wiring): idle_00 = the base;
idle_01 = flap-lean (-5 deg shear about the bottom edge, +7% brightness); spawn_00 = the base
(the fade is the view's alpha job); telegraph_00 = WIND-UP (crouch sy 0.88, sx = 1/sqrt(0.88) width compensation, mouth gape under the nose, +5% brightness) = spec seal_01;
dash_00 = LUNGE (stretched along the dash axis, body low: sy 0.74, sx 1.16, -5 deg shear lean,
mouth gape, +18% brightness) held for the 60-tick dash; dash_01 = the alternate lunge phase
(sy 0.80, sx 1.08, mouth gape, +10% brightness); recover_00 = the base stretched +6% vertically,
+6% brightness. The dash axis is NOT static data: enemy.gd computes dash_dx/dy/dz at telegraph
start (body centre -> player centre, extended to 20 u, fixed for the dash) and neither the anim
block nor enemy.json exposes a fixed axis, so the lunge is a FIXED FORWARD lunge (horizontal
stretch + low body), by the ticket's own fallback. The mouth gape is placed on the measured mouth
line just under the nose (base crop coords (169,233); rx = 0.056 x crop width, ry = 0.033 x crop
height; dark fill #0C070A with a gummy lower lip #56282E at dy >= 0.35). body_rect per frame is the
tight bbox of alpha > 16, recomputed and written into sprites.json by the tool itself (spawn/idle
[32,252,448,248]; dash_00 [32,342,443,158]; dash_01 [32,316,448,184]; telegraph [32,295,448,205];
recover [32,237,448,263]). The T-083 anim block is otherwise UNTOUCHED: frame counts, tick ranges,
loop flags, fps, spec_frames, frame_map and the effect parameters (including length_u 20.0 and
mouth_open_frame_tbd: false) are byte-identical to before. world_height stays 0.6 (DESIGN.md
section 5 body-size table, binding; the new silhouette is wider and shorter - ~1.8:1 - but the
pinned world height is the table's number, not a fit to the photo; nothing in the section makes it
wrong). The shared pipeline's stale seal source reference (sprite_pipeline.gd) is updated to
babehseal.png for the one-source rule; the pipeline still skips seal (art module owns it).
Validation (2026-11-17): SPRITES OK 515 checks over 12 sprites.json (per-frame fog ratios
validate-formula: idle/spawn 4.65, idle_01 5.18, telegraph 5.01, dash_00 5.95, dash_01 5.39,
recover 5.12 - all >= 3.0). FOGCHECK OK (550 checks over 5 biomes); the seal's rows vs the five
biome fogs at 40 u: deepwater 6.85-8.96, indigo_trench 7.29-9.54, pale_abyss 6.92-9.05, verdigris
6.88-9.00, violet_hour 7.27-9.52 (all >= 3.0; no art-side grade needed - the threshold was not
moved). The atlas/mean-colour semantics are unchanged.
[CONTESTABLE] art constants only: the 0.88 crouch, 0.74/1.16 and 0.80/1.08 lunge numbers, the
-5 deg shears, the 1.05/1.07/1.10/1.18 brightness steps, the mouth-gape placement and sizes, the
1.06 vstretch, the 448 px body width and 12 px bottom margin. No gameplay-facing number, no
threshold, no tick, no loop flag and no body_rect semantic moved. The owner may re-tone any of
these by editing game/tools/art/seal.gd and re-running it, then re-syncing the printed body_rect
lines. dash_01 vs dash_00 separation (the flap's weight shift) is a judgment call - the table's
4-tick cadence alternates them regardless.

### D-ART-claude-1 - The Claude logo's frames are real art derived from claudelogo.png (game/tools/art/claude.gd)
`claudelogo.png` (2000x2000, FORMAT_RGBA8, ENEMIES.md image 15) is NOT the opaque
photo the shared pipeline's 24/255 corner flood fill cannot eat: all four corners measure
(0, 0, 0, 0) and the image carries NO opaque background. Measured (module prints the same):
2,390,179 px at alpha 0; ~10,032 px of faint resize noise at alpha 1..15; 26,451 px at
alpha 16..249 (the body's anti-aliased edge ring; the modal body colour is
(217, 119, 87, 255) = #D97757, 1,567,684 px, ~98% of the body); 1,573,338 px at alpha >= 250.
Every alpha > 16 pixel forms ONE connected component - the source canvas CLIPS the starburst
(the body touches rows/cols ~0 and ~1999). Background removal therefore does: (1) border
flood fill from every border pixel eating pixels with alpha <= 16 (the measured background);
(2) global zeroing of every alpha <= 16 pixel (the inner noise pockets the border fill cannot
reach); (3) keep only the largest connected opaque component (isolated specks erased);
(4) defringe: RGB of every alpha == 0 pixel set to (0, 0, 0). Then tight crop to alpha > 16,
fit onto a 512x512 power-of-two canvas, bottom-anchored (the enemy stands on the ground),
8 px transparent margin (>= the 2 px the validator demands), the per-frame fit clamped so the
ROTATED, DEFORMED body stays inside the margin automatically. Ten frames are derived from the
base body, one distinct frame per ANIM-BLOCK STATE (inverse bilinear about the FEET pivot,
feet planted for every deform): `idle_00` (the base, spec claude_00), `idle_01` (+15 deg
metronome step pose - the idle effect rotates 15 deg per beat IN STEPS), `idle_02` (1.06x
pulse pose - the idle effect's scale pulse), `spawn_00` (0.8x pose - the fade's scale_from),
`telegraph_drums_00` (squash sy 0.85, sx = 1/sqrt(sy), lean-back -6 deg), `attack_drums_00`
(stretch sy 1.15, +3 deg, +8 px lift, brightness 1.28 - the strike; the logo flashes white
on the hit beat), `telegraph_strings_00` (+12 deg lean, sy 0.92 - aiming the sweep at its
starting angle), `attack_strings_00` (sx 1.22 / sy 0.88 horizontal stretch, brightness 1.15),
`attack_wind_00` (coiled-low squash sy 0.72, sx = 1/sqrt(sy)), `deadline_00` (+2 deg, red
tint 0.5 toward (255, 72, 64) baked in - agitation 100, Deadline). The clawd Crab plushie
source was never fetched (ENEMIES.md points at github.com/xyc/plushie), so `plushie_00/01/02.png`
stay magenta TBD placeholders generated by `game/tools/make_tbd_png.gd`; `plushie_idle` points at
them and `"tbd": true` stays at the top level (NOT false - not every frame is real art).
`animations[]` order is untouched: index 0 is still `idle` (frames idle_00/01/02 as before, the
T-016 idle set, now real), one new entry was APPENDED per other state (spawn, telegraph_drums,
attack_drums, telegraph_strings, attack_strings, attack_wind, deadline, plushie_idle); the
anim block's `spec_frames`, frame counts, fps, loop flags, `total_ticks`, `ticks_per_frame`,
`tick_ranges`, effect names/params and the `animations[]` index-0 position are UNCHANGED
(no state added/removed/reordered; no threshold or check moved). `claude_view.gd` now swaps
the billboard texture per state from the anim block's frame lists (the seal_view pattern) -
previously every state rendered the same single TBD frame; there is deliberately NO
`frame_map` (all eight logo states share spec `claude_00`, so a frame_map cannot express a
per-state mapping; the states' `frames` lists + the view wiring are the per-state wiring).
Fog contrast at 40 u per claude frame (validate_sprites SPRITE_DEBUG, 5 biomes): 5.5-8.9
(deepwater idle/spawn/telegraph/attack_wind 5.96, attack_drums 8.89, deadline 5.63).
validate_sprites: SPRITES OK 265 checks over 12 sprites.json. `check_anim_data`: claude
PASS (9 states). TESTS 55 passed 0 failed.

### D-ART-claude-2 - The Claude art derivation constants are art judgment, owner may flip [CONTESTABLE]
No document states the canvas size, the base body height (430 px before per-frame fit/clamp),
the 8 px bottom-anchored margin, the per-frame rotation degrees (15 / -6 / 3 / 12 / 2),
the squash ratios (0.80 / 0.85 / 1.15 / 0.92 / 0.88 / 0.72), the horizontal stretch (sx 1.22),
the lift (+8 / +4 / +2 px for attack_drums / idle_02 / attack_strings), the brightness
multipliers (1.28 / 1.15 / 1.03), the sx = 1/sqrt(sy) compensation, or the deadline tint
((255, 72, 64) at 0.5, which keeps the frame above the fog-contrast 3.0 floor). They are
art judgment applied over the owner's source so the binding checks pass (>= 3.0 fog contrast,
>= 15% fully transparent, tight body_rect, 2 px+ margin) with a distinct silhouette per state.
The gameplay-relevant numbers (frame counts, spec_frames, tick ranges, effect params, hitbox
body_rect semantics, world_height 2.0) are untouched. The owner may re-tone any of these by
editing `game/tools/art/claude.gd` and re-running it; `validate_sprites.gd` re-derives
pass/fail, and `sprites.json`'s per-frame `body_rect` must be re-synced to the printed `RECT`
lines after every regeneration (all ten logo frames are one command; the three plushie
placeholders come from `game/tools/make_tbd_png.gd` and only change when the plushie sprite
is fetched).

### D-ART-ADDRESS_ME-1 - address me ships real sprite art (ART-ADDRESS_ME)
The placeholder magenta TBD frames are replaced by real art, generated deterministically
(no randomness anywhere) by game/tools/art/address_me.gd, run headless like the rest of
the fleet's art wave. The shared pipeline (game/tools/sprite_pipeline.gd) SKIPS any enemy
with an art module, so a later rebuild cannot regress these frames; the rebuild path for
this enemy is the art module. Frames (binding counts from the T-083 block, unchanged):
cycle_00.png = the spec's addressme_00 (the normal elephant meme, the fog-lifted hide);
cycle_01.png = the spec's addressme_01 (the explode frame - Image 14 composited over the
elephant at 30% alpha, exactly the composite TBD.md's owner-action note named and
envisioned: the explosion cutout drawn over a 30%-alpha elephant ghost); spawn_00.png =
the same body, brightness flash (the trumpet tell - the runtime effect still does the
fade; the frame is the brighter hold); telegraph_00.png = desaturated (0.45) hold, the
neutral stillness before the amber/red tint ramp (dim dropped to 1.0 - any dimming broke
the fog-contrast bar, see D-ART-ADDRESS_ME-2); leaves_00.png = 1.18x / 0.78y squash,
the anticipation of shrink_to_0; attack_00.png = attack's spec frame (same composite as
cycle_01 - see D-ART-ADDRESS_ME-4). The anim block's spawn/telegraph/leaves/attack states
point at spawn_00/telegraph_00/leaves_00/attack_00; recover stays frameless as specified.
The view (game/view/address_me_view.gd) is untouched - it pins index 0/1 of the cycle
animation, which kept its [cycle_00, cycle_01] layout with refreshed body_rect.

### D-ART-ADDRESS_ME-2 - the fog-contrast bar is met by lifting the hide, never the threshold [CONTESTABLE]
The raw hide measures fog contrast 2.19 at 40 u vs the Deepwater fog (#021416) - below
A8's 3.0 WCAG bar, same class of failure as the other art-wave enemies. The art is lifted
to clear it: sRGB scale x1.22 + 14/255 pedestal on the elephant (the mean opaque colour
ends up around #897E73, cycle_00/leaves_00 at 4.75-4.80 contrast per the fog check; spawn
reads 6.11, telegraph 4.68; the explosion composite reads 8.89). Thresholds untouched
(validate_sprites.gd, fog_check.gd); the lift lives in game/tools/art/address_me.gd (_fog_lift).
The lift constants (1.22, 14/255) are [CONTESTABLE] - the owner may prefer a hue-matched
rim light over a global lift; the check they must satisfy (mean opaque >= 3.0 vs fog) is
the part that is binding, and it passes with margin.

### D-ART-ADDRESS_ME-3 - background removal per image, constants stated [CONTESTABLE]
The shared corner flood fill (tolerance 24) cannot segment either source, so each image
gets its own rule, all deterministic:
- elephant (address me elephant.png, room photo): the room's grey is byte-near the hide's
  grey (body vs wall distance ~11), so colour alone cannot separate them. A hand-traced
  sure-foreground polygon (interior silhouette, incl. a not-polygon notch at the
  under-belly strip) guards the body; the border flood (neighbour-step RGB distance <= 30)
  eats the room around it; enclosed background islands are refilled; the largest connected
  component is kept. The white "Address me" strike across the lower third was inpainted
  with hide colour where it overlaps the body (diffusion from each letter's border,
  letters dilated 2 px for the antialias rim); lettering off the body drops out with the
  component cut. Result: the full meme silhouette (ear, trunk, tusks, all four legs) with
  the room removed.
- explosion (explosionsffect.jpg, fireball + tabby): the fireball fades into sky/beach in
  smooth gradients that defeat a neighbour flood, so the body is picked by a global rule
  ("warm: r > b + 10, or bright: max >= 175"); the cat's neutral-dark pixels fail that rule,
  so a cat-silhouette polygon protects them; largest component wins; enclosed islands
  refilled.
- canvas 512x512 (power-of-two, <= 512), the cutout fit to 448 px preserving aspect,
  horizontally centred, bottom-anchored (the enemy stands), transparent margin >= 4 px on
  every side (validate requires no opaque pixel within 2 px of an edge). body_rect in
  sprites.json is the tight bbox of alpha > 16 on the final canvas - identical to what the
  validator recomputes.
The constants (30.0 flood distance, LETTER_BAND_Y 455, 448 fit, 512 canvas, 4 px margin,
the polygons) are [CONTESTABLE] in the sense that a repaint-quality pass may want them
re-tuned; they are art decisions, not sim numbers, and nothing moves a check.

### D-ART-ADDRESS_ME-4 - attack_00.png and cycle_01.png are the same composite, byte-identical
The view hard-pins cycle index 1 (cycle_01.png) as the attack frame; the anim block's
attack state points at its spec frame (addressme_01, file attack_00.png). Rather than let
the two names carry two different composites, both files are written by the same
_composite_attack() call - identical art under the two names the two consumers expect.
Deleting one and pointing both consumers at the other would also work, but the cycle
sheet's [cycle_00, cycle_01] layout and index 1 pin live in shipped view code, and the
anim block's file names are its own contract - the duplication costs 266 KB and keeps both
interfaces byte-stable. The four state frames are otherwise distinct art.

### D-ART-ADDRESS_ME-5 - the address me sprite KEEPS the full office photo (owner ruling 2026-11-17); supersedes the elephant half of D-ART-ADDRESS_ME-3 and the lift constants of D-ART-ADDRESS_ME-2 [CONTESTABLE]
Owner ruling, verbatim intent: "the address me should'nt have its background
cut off or it looks weird keep it like this". The intended art is the FULL
office-interior photo - a photorealistic elephant standing in an office with
swivel chairs, desks, a tipped trash bin, scattered papers and shelves, the
white handwritten "Address me" strike across the middle. The background is
part of the joke; it is NOT removed. The source `assets_src/enemies/address me
elephant.png` (1080x726) is edge-to-edge office - no hard border that is not
part of the art - so nothing is cropped. What changed in
game/tools/art/address_me.gd (ART-FIX-ADDRESS-ME):
- the elephant border flood fill, sure-foreground polygon, letter band
  detection, letter inpaint and defringe are ALL gone; the frame is the whole
  photo, alpha 255 everywhere in the photo rect, fitted to the 448 px canvas
  body (1080x726 -> 448x301), centred horizontally, bottom-anchored,
  transparent margin elsewhere (the 512 canvas contract every enemy keeps so
  the validator's corners-alpha-0 / no-opaque-border / >= 15% transparency
  rules still hold). The white "Address me" strike is part of the photo and
  stays, on the body and off it.
- the explosion source (explosionsffect.jpg, the attack fireball) is NOT
  covered by the ruling and keeps its cutout; attack_00/cycle_01 remain the
  spec's composite - Image 14 over the elephant (now the ghosted FULL photo at
  30% alpha) - byte-identical under the two names (D-ART-ADDRESS_ME-4).
- per-state treatment unchanged: spawn = brightness 1.16, telegraph = desat
  0.45 / dim 1.0, leaves = 1.18x / 0.78y squash, cycle_00 = the plain frame.
  Frame counts, tick ranges, loop flags and effect parameters in the anim
  block are untouched; recover stays frameless.
- the fog-contrast lift is re-tuned for the full-photo mean: the raw photo
  mean (#736F69) measures 2.72 at 40 u vs palette fog (#021416) - below the
  3.0 bar - so the art is graded sRGB x1.15 + 10/255 pedestal (GRADE_SCALE /
  GRADE_PED), taking the mean to #8C8881 (validate_sprites, palette fog:
  cycle_00/leaves 3.72, telegraph 3.67, spawn 4.63, cycle_01/attack 5.90;
  fog_check per-biome raw-mean rows, deepwater: cycle_00/leaves 5.34,
  telegraph 5.27, spawn 6.81, cycle_01/attack 8.89). The old constants
  (x1.22 + 14/255 on the cutout hide) would clip the photo's ceiling whites;
  1.15/10 clears every biome with margin and is truer to the source. Thresholds
  untouched (validate_sprites.gd, fog_check.gd). GRADE_SCALE/GRADE_PED and the
  fit/squash/flash/desat numbers are [CONTESTABLE] - art judgment, not sim
  numbers; the binding bar (mean opaque >= 3.0) passes.
- body_rect re-synced to the regenerated frames (cycle_00/spawn/telegraph
  [32,207,448,301]; leaves [32,309,448,199]; cycle_01/attack [32,73,448,435],
  unchanged). world_height stays 2.5 (DESIGN.md section 5 table; the art is
  the same photo content, just not cut out).
Note on numbering: the ticket that carried this ruling asked for a
"D-ART-ADDRESS_ME-2"; that id was already taken by the fog-lift entry above
(which this entry supersedes in part), so the ruling is recorded as
D-ART-ADDRESS_ME-5 per the next-free-id convention. D-ART-ADDRESS_ME-1 and
D-ART-ADDRESS_ME-3 describe the cutout pipeline and are kept as history; the
elephant half of D-ART-ADDRESS_ME-3 is superseded by this entry. The
explosion half of D-ART-ADDRESS_ME-3 stands.

### D-FIX-A15-1 - the T-001 disclaimer punctuation is the em dash (U+2014), plaque wraps at render time [CONTESTABLE]
FIX-A15 closes AUDIT.md section 6 / A15. FLEET_PACK.md line 163 (T-001's spec), README.md
line 7 and AUDIT.md section 6 all write the dash in "non-commercial project — no money is
involved" as the em dash U+2014; the ticket brief transcribed it with an ASCII hyphen, which
is not what any repo document states. The lobby About plaque (game/view/lobby/antechamber.gd)
therefore pins DISCLAIMER byte-identical to README.md's disclaimer sentence (em dash included)
and the test pins the same string; the plaque label wraps at render time instead of the text
carrying newlines (Label3D width 1000 px at pixel_size 0.004, derived from the 4.2 u board:
4.2 / 0.004 = 1050 px, 1000 px keeps a margin) so the rendered text stays byte-identical to the
spec. The 1000 px wrap width is a layout number no document states, hence [CONTESTABLE]; it is
a display detail, not a sim or gameplay number, and nothing moves a check. The ENEMIES.md
paragraph (game/app/menu.gd ABOUT_DISCLAIMER) is a different wording by design (PARKED.md #2)
and is unchanged by this ticket.

### D-FIX-A4-1 - the A4 bot-run length and seed set (FIX-A4) [CONTESTABLE]
FLEET_PACK.md section 5 A4 states exactly this: "10 recorded bot runs replay with
identical state hashes at every checkpoint", measured by game/tests/test_replay.gd. It does
NOT state a run length, a seed set, or which seeds, and the checkpoint cadence (every
60 ticks) is inherited from the existing random-input run, not from the criterion. Those
are numbers no document states, so they are written down here as [CONTESTABLE] with the
gameplay reason:
- The ten recorded runs are played by the T-060 bot (game/tools/bot_run.gd, grown a
  record/playback mode: play_run(..., p_rec)) through the real sim surface - controller.gd
  + gifts/mines/beacon + enemy runtime inside a RunState - and the checkpoint hash is
  sim/state_hash.gd over that RunState. Only ADDITIVE state surfacing was added to the bot
  path (vy / grounded / prev_buttons on the level's player dict; nothing reads them); no
  behavior, bot tuning, threshold or spec number was moved.
- The replay feeds the recorded input stream tick-for-tick (playback: the bot's brain is
  bypassed, lobbies/level-gen/enemies identical) - so the artifact that replays is the
  recorded run itself, not merely a re-run of a deterministic bot. A run that dies on
  level 1 is still a recorded run; the criterion measures replay determinism, not bot
  competence (bot competence is A3's gap, PARKED.md #4 / T-026).
- BOT_TICKS = 1000 per recorded run, one level (max_level = 1), ten distinct seeds
  {101..1001}. WHY 1000: measured on this machine - baseline run_all = 126 s
  (TESTS 55 passed 0 failed); ten full 3,600-tick recordings added ~184-190 s (per-seed
  record pass 7.6-27.1 s; replay passes ~0.1-0.5 s each because playback skips the bot
  brain) - run_all reached ~310-316 s, OVER the gate's 300 s step-3 timeout
  (tools/gate.ps1 -StepTimeoutSec default 300), so the plain gate command would be killed
  before printing its verdict. At 1000 ticks every seed still yields >= 1 checkpoint
  (minimum death 653 ticks, seed 404) and run_all lands ~240 s. The ten seeds are
  arbitrary distinct seeds, not tuned to any outcome; the COUNT (10) and the 60-tick
  checkpoint cadence are NOT reduced, per the ticket.
- Gameplay reason: the proof needs the bot's REAL input stream over a real level slice;
  1000 ticks is 16.7 s of sim, past the first 60-tick checkpoints and into mid-level play,
  which exercises controller, gifts, mines, beacon and enemies through state_hash.gd.
Owner to rule: raise the gate step-3 budget (~316 s measured need) to lift BOT_TICKS back
to 3600, or accept the 1000-tick recorded runs as the A4 evidence.

### D-FIX-A14-1 - the boundary scan derives its content ids from the content tree at test time
KNOWN_CONTENT_IDS is gone as a hand-maintained array: tests/test_boundaries.gd now scans
res://content/enemies/ (folder names), res://content/curses/, res://content/upgrades/ and
res://content/biomes/ (*.json file names) and builds the list itself. A literal list in the
test would rot with the next added content file and the test would become the thing it tests.
Matching is case-sensitive whole-word (an id bounded by non-word characters or a file edge),
applied to every *.gd and *.json found recursively under res://terrain, res://sim, res://core
(which includes res://core/schemas/) and res://app/. .gd files keep the pre-existing
FORBIDDEN_STRINGS engine-surface scan and the import-prefix scan; .json files are scanned for
content ids only. Comments are included, as before: the rule is that no core/sim/terrain/app
file may leak an engine API or a content name, whatever the line type (T-001). English prose
in comments that collides with an id (e.g. "more", "you") is reworded, never allowlisted.

### D-FIX-A14-2 - enemy.json gains spawn_line / death_name; the roster read goes through core/roster.gd
The 12 spawn lines (research/fable-tickets.md T-027 row) and the 12 run-over display names
(DESIGN.md section 3.1) were hardcoded in the view HUD and sim/death.gd. They now ship as two
OPTIONAL enemy.json fields: "spawn_line" (the diegetic danger line) and "death_name" (the
run-over display name; defaults to "name" - only gift_larper overrides, to DESIGN.md 3.1's
"gift Larper (Tripmine)"). Death codes keep living in stats.death_code (T-021, D-T030-1).
New game/core/roster.gd scans res://content/enemies/ once and serves: code -> death_name,
id -> death_name, id -> spawn_line, and the biome act order (biomes sorted by levels[0];
DESIGN.md section 10's one-act-per-6-levels table, D-T014c-1's 31+ cycle preserved).
sim/death.gd, view/hud/run_over.gd, view/hud/danger_text.gd and view/fog_env.gd all read
through it; no roster literal remains in any of them. Two name collisions between role/event
vocabularies and upgrade ids are renamed rather than allowlisted: the sim role key
"cartographer" becomes "footprint_map" (sim/upgrades.gd, content/upgrades/cartographer.gd),
and the glider rise event "updraft" becomes "updraft_rise" (sim/controller.gd; consumed by
tests only, D-T053-6's numbers unchanged). Adding a 13th enemy or a 6th biome is now a pure
content drop-in: one folder/file, zero code edits.

### D-FIX-A14-3 - curse requires_enemy is validated against the registry, not an enum
core/schemas/curse.schema.json hardcoded all 12 enemy ids in requires_enemy's enum - a core
file naming the roster, and the reason a stale id ("gin_ichimaru") validated. The enum is
dropped; requires_enemy is pattern-checked (^[a-z][a-z0-9_]*$) and validated at load by
core/registry.gd against the scanned enemy ids: an unknown requires_enemy is a boot error
naming the offending file. game/tests/test_curse_requires.gd asserts the same over every
shipped curse. twin_fangs.json's requires_enemy is corrected "gin_ichimaru" -> "gin" (the
enemy id; ENEMIES.md's gin ichimaru section), so the curse can be offered again.

### D-APPFLOW-1 - The run seed is a fixed default (1); start_run(seed) overrides it (APP-FLOW)
DECISION (APP-FLOW): the run seed defaults to DEFAULT_SEED = 1 (the ticket's own example).
`start_run(seed_value)` stores the given seed instead; with no argument path ever built for
randomness, every unattended boot (tests, headless scene checks) is reproducible. A future
"New Run" button passes its own seed; until then 1 is the canonical first ever boot.
WHY: the ticket mandates a fixed default and a D- log entry; nothing in any FINAL spec pins a
random source or a date-derived seed, and a random default would make every CI/gate rerun a
different level. [CONTESTABLE] only in the literal value 1.

### D-APPFLOW-2 - The app drives loading_screen.advance() itself, double-ticking the screen (APP-FLOW)
DECISION (APP-FLOW): app._process calls `_loading.advance(delta)` every frame while in LOADING,
per the ticket's "Drive the loading screen with advance(delta) from _process". loading_screen.gd
ALSO self-advances from its own _process (D-T024 files are frozen for this ticket), so in a real
run elapsed accrues at 2x the frame delta and the >= 5.0 s hold elapses in ~2.5 s of wall time.
WHY: the ticket line is explicit and newer than the frozen file; the alternative (drop the
app-side drive) silently ignores the ticket's wording, and editing loading_screen.gd is another
ticket's fence. The resulting CANON tension (DESIGN.md section 2, "loading screen >= 5.0 s
shown") is NOT resolved here: it is parked as PARKED.md #20. [CONTESTABLE] - the owner may flip
to either side; flipping means either deleting the app-side advance (ticket line lost) or
retiring the screen's self-_process once a host drives (T-024 file change).

### D-APPFLOW-3 - start_run(seed) in MENU starts the run; elsewhere it only re-seeds the next run (APP-FLOW)
DECISION (APP-FLOW): `start_run(seed_value)` stores the seed; when the current state is MENU it
also takes the same path as the Play button (_begin_run). In LOADING/WORLD it changes only the
seed of the next run and has no visible effect (there is no next-run path yet). It is NOT a
force-restart from WORLD.
WHY: the ticket freezes only the signature `start_run(seed_value: int) -> void` and pairs it with
`state()`, so its semantics are mine to pin; the Play button already owns WORLD entry, and a
silent force-teardown of a live level is the most surprising reading. [CONTESTABLE]

### D-APPFLOW-4 - The level's enemy plan is the run's OWN seeded plan, replayed through the intermissions (APP-FLOW)
DECISION (APP-FLOW): world.build(seed, level) replays intermissions level_completed = 0..level-1
with the sim's own Intermission/Offers state machines, seeded exactly the way
game/tools/bot_run.gd seeds its bot: lobby n is created with mix(seed, 5000 + n), the pick stream
is VoidRng(mix(mix(seed, 0xB07), n + 1)), every mandatory CLASS/E/C bay is resolved with a uniform
seeded pick among its unresolved altars, U and REST bays are never touched, an empty mandatory
C draw is tithe-passed when affordable. The accumulated votes dict is the plan, one planned row
per vote (copies = votes). For level 1 this replays the pre-run lobby (CLASS + the one starter
E bay). Class rides the same replay (CLASS bay); the enemy runtime gets the raw run seed as its
spawn stream. Curse sim knobs (rush_hour / long_night / early_bird / brittle / hungry_void /
understudies) are NOT applied in this pass - only class and enemy votes cross over.
WHY: the ticket forbids the probe's hardcoded VOTE_LIST and asks for "the runtime's OWN enemy
plan for the level"; the only (seed, level) -> plan mapping the game already owns is the lobby
draw itself ("votes ARE inputs", DESIGN.md section 13 rule 2; the bot plays exactly this way), so
the world replays it instead of inventing a second one. Applying the curse knobs was left out as
out of scope with the plan being the deliverable; the gap is noted, not faked. [CONTESTABLE]

### D-APPFLOW-5 - world.step() ticks exactly controller + enemy_runtime + billboards + camera rig + HUD sync (APP-FLOW)
DECISION (APP-FLOW): step() is the ticket's step spec and nothing more. gifts / tripmines /
beacon are NOT ticked; the HUD gift counter therefore shows 0/0 and the beacon never opens in
this build. Closing that needs a LevelState owner decision (GiftsScript.tick on the controller
events, beacon open -> overtime, run_log feed) which this ticket does not fence-edit.
WHY: the ticket's step line is explicit and the parallel MENU/LOADING tickets need a stable
seam, not a half-wired run loop; a silent partial gift path (counter moves, beacon dead, or
vice versa) is worse than an honest 0/0. [CONTESTABLE] as scope; the wiring itself is not
contestable once LevelState ownership lands.

### D-APPFLOW-6 - Class falls back to "dasher" when the CLASS bay somehow resolves empty (APP-FLOW)
DECISION (APP-FLOW): if the CLASS bay replay leaves class_chosen == "" (impossible with today's
player.json - three classes, altars always drawn), the controller is set up on "dasher"
(data/player.json's first-listed class, and the probe's pinned KIT).
WHY: controller.setup on "" is undefined behaviour in the class-table lookup; a documented
fallback beats a crash, and the situation cannot arise from current content. [CONTESTABLE]

### D-APPFLOW-7 - Pause is app-side _unhandled_input against the pause binding codes, fallback KEY_ESCAPE (APP-FLOW)
DECISION (APP-FLOW): ESC (or whatever data/bindings.json binds to "pause"; KEY_ESCAPE when the
file is unreadable) returns to MENU from LOADING or WORLD: the world is torn down and freed
(world.teardown() + free()), any loading screen is freed, the menu is shown again. The menu's
own quit path is untouched. loading_finished is connected with queue_free (not free()) for the
screen because the signal is emitted from inside advance() and a synchronous free would delete
the object under its own call stack. World meshes are always built (windowed or headless),
unlike the probe's windowed-only build.
WHY: the ticket names "ESC / the pause binding" without a delivery mechanism; polling the
bindings file keeps the binding data-driven (D-T082-2) and the fallback keeps unbound builds
escepted-but-working. queue_free vs free is a correctness call (D-APPFLOW-2's signal path), not
a preference. [CONTESTABLE] only on the fallback and the always-mesh call.

### D-APPFLOW-8 - The world steps on a fixed 60 Hz accumulator, decoupled from the render rate (APP-FLOW)
DECISION (APP-FLOW): app._process feeds the world through an accumulator (delta in, DT =
1/60 steps out, spiral-of-death clamp of 5 ticks per frame with the remainder dropped).
WHY: stepping once per frame with DT = 1/60 runs the sim 2x fast on a 120 Hz display and 0.5x
on a 30 Hz one; the sim's contract is a fixed 60 Hz tick. [CONTESTABLE] only if a design wants
variable dt (nothing does today - sim rules are written per 60 Hz tick).

### D-MENU-1 [CONTESTABLE] - Entries PLAY / HOW TO PLAY / QUIT; About and Settings leave the menu; the disclaimer moves to an always-on footer (ticket MENU).
DECISION: MENU_ENTRIES = ["PLAY", "HOW TO PLAY", "QUIT"], upper case as the owner's ticket writes
them (supersedes the T-024 list). The About entry is gone, so the ENEMIES.md disclaimer is rendered
verbatim in a footer line ("VOIDWRAP RUN: " + ABOUT_DISCLAIMER) that is on screen the whole time the
menu is; ABOUT_TITLE / ABOUT_DISCLAIMER / about_text() stay exactly as they were (test_disclaimer.gd
untouched apart from the MENU_ENTRIES line). The Settings panel is also gone from the menu: the owner's
list does not include it. app/settings.gd (the store) is unchanged, but NO menu UI reaches it any more.
WHY: the owner's entry list is explicit; a footer keeps the hard-rule disclaimer one glance away
instead of one click. Overrule by re-adding "SETTINGS" to MENU_ENTRIES (the old slider panel is in
git history at f31fc44:game/app/menu.gd) or by giving the APP-FLOW pause menu a settings page.

### D-MENU-2 [CONTESTABLE] - The menu wears Indigo Trench (act IV) fog and palette, with glow and the open beacon as key light.
DECISION: the 3D backdrop (app/menu_stage.gd) instances the real view/fog_env.gd configured as
("indigo_trench", level 19): background #02030F, fog #03061C exponential at 0.014/u, ambient from the
palette. On top of the game's environment the menu adds glow (intensity 0.7, bloom 0.04, HDR threshold
1.3) and filmic tonemapping, an OmniLight3D at the beacon (#E8FFFF, energy 2.2, range 24, no shadows)
and a soft fill (player_fill_light #BFFFF8, 0.8). Tiles, slabs, trim, dais, pillars and spikes use
resolve_palette() roles and the (x + z) & 1 checker; platform_light keeps its 0.35 emission.
WHY: the owner's reference screenshot is dark navy with violet, a white beam and gold objects; of the
five shipped biomes Indigo Trench (navy fog, #4C6BFF platforms) is the closest, and using fog_env.gd
itself (not copied numbers) keeps the menu's fog identical to the game's for that act. The game has no
sun (TERRAIN_SPEC 12.2), so the open beacon is the light source. Glow is the only effect the in-game
environment does not have; without it the beacon column reads as a flat white bar.

### D-MENU-3 [CONTESTABLE] - Roster layout: three terraces, tallest at the back, camera sway never behind.
DECISION: the roster is discovered from res://content/enemies/*/sprites.json (no content id is named in
app/menu_stage.gd). Grounded enemies sort by canon world_height descending, ties by id, and fill slots
back row first, centre-out within a row: back terrace (top 2.0 u, z -5.5) 2 slots, middle (top 1.0,
z -2.0) 5 slots, front (top 0.0, z 1.6) 4 slots; extras go on the front lip. An enemy with no body row
(world_height null - the nuke) flies across the sky above the beacon, nose first. The camera looks at
(0, 1.6, -2) from 19.5 u, pitch 15 deg, swaying +/-16 deg in yaw over 48 s (plus slow pitch/distance
breathing), FOV 50, h_offset -4.2 so the island sits right of the menu column. It never orbits.
The scene is the gold phase: beacon open, gold gifts on slots, one tripmine with its #FF4FD8 sparks
(the only pink), 13 dark floating shards with #7CFFF4 edges, distant motes.
WHY: the acceptance test is "the player can name several enemies from the menu alone"; a full orbit
would put the beacon or another enemy in front of each one in turn, so the arrangement is a stable
amphitheatre and the camera only drifts. Height ordering keeps small enemies in front of big ones.

### D-MENU-4 [CONTESTABLE] - Menu display heights compress the canon body range.
DECISION: in the menu only, a body's shown height = lerp(1.2, 3.4, (canon - 0.6) / (4.0 - 0.6)),
clamped (seal 0.6 -> 1.2 u, thicc ben 4.0 -> 3.4 u); the flying nuke is 1.3 u. Order is preserved.
WHY: at the menu camera distance the canon 0.6 u seal is a few pixels at 1152x648; compressing keeps
every enemy nameable while the size order still tells the truth. Gameplay sizes are untouched.

### D-MENU-5 [CONTESTABLE] - Version tag "v0.1.0-alpha.1 pre-release".
DECISION: app/menu.gd VERSION_TAG, bottom-left. WHY: AUDIT.md names v0.1.0-alpha.1 as the alpha tag
and records that it was NOT created; "pre-release" says exactly that. Change the constant when the tag
is cut (no build step stamps it).

### D-MENU-6 [CONTESTABLE] - Roster caption: the in-game danger lines, one enemy at a time.
DECISION: every 3.2 s the next roster enemy shows its spawn line (view/hud/danger_text.gd
spawn_line(), e.g. "THE SEAL SHALL BARK") above its head in #FF2A2A with a black outline: 0.35 s fade
in, 2.3 s hold, 0.35 s fade out. WHY: it names the enemies in the game's own diegetic voice (DESIGN.md
section 14), reusing the shipped table rather than inventing labels; one at a time keeps red rare.

### D-MENU-7 - HOW TO PLAY is written from the code; three doc/code disagreements, code wins.
DECISION: app/menu_howto.gd reads every number it prints at runtime from the files the simulation reads
(controller.load_constants() over data/player.json, beacon.RADIUS, mines.CONTACT_R, economy.gd over
data/economy.json, enemy_runtime overtime constants, data/bindings.json). Where docs and code disagree:
(a) DESIGN.md 3.1 says Field Dressing makes one fall per level free; sim/controller.gd _void_fall()
always spends the charge (PARKED.md #3) - the panel does not mention Field Dressing.
(b) DESIGN.md 3.2's gold economy is implemented in sim/economy.gd but nothing in sim/sim.gd calls it in
this checkout (the per-tick wiring belongs to APP-FLOW's world.gd); the panel states economy.gd's rules
because that is the shipped implementation.
(c) "every body contact kills" is not true of the whole roster: thicc ben and address me have
contact_kill false (D-065), so the panel says "Most enemies kill on contact - instantly".
WHY: the ticket rule - the code wins for this panel, and the disagreement is recorded.

### D-MENU-8 - The menu lifts each billboard by 2 x body_feet_shift (compensates PARKED.md #20).
DECISION: view/billboard.gd places the sprite with Sprite3D.offset.y = h/2 - (body bottom px), which in
Godot 4 moves the image DOWN (offset +y is up), so the body hangs 2 x |body_feet_shift| below the node
(measured: thicc ben's AABB spans y -5.06 .. +0.06 before scale). view/ is not this ticket's to edit;
menu_stage.gd drives each billboard itself (its _process disabled) and sets position.y =
-2 x body_feet_shift after every frame change; test_menu.gd asserts every body bottom is within 0.03 u
of its platform before and after animating. WHY: without it the roster stands inside the island.
Remove the lift when billboard.gd is fixed (the test will then fail loudly, which is the point).

### D-MENU-9 [CONTESTABLE] - Typography, selection feedback and input.
DECISION: no font ships in game/assets/, so the menu uses Godot's built-in fallback font (Open Sans
SemiBold) through FontVariation: the wordmark emboldened 0.85 with 10 px tracking (scaled), "VOIDWRAP" in
beacon white #E8FFFF over "RUN" in gift gold #FFC83D, a short gold rule under it. A SystemFont would
differ per machine; the fallback ships inside every export and its wide-tracked heavy caps read cold and
architectural, not playful or glossy. Selection = four simultaneous cues so nobody guesses: gold text vs
muted #8B9EB7, a 4 px gold bar on the left, a 10 % gold tint behind the row, the text indented 16 px; all
eased over ~0.1 s; a one-line hint under the entries says what the selected entry does. Input comes
from data/bindings.json only: move_forward / move_back select (wrap), jump OR interact confirm, pause
closes the panel; gamepad: the bound jump / interact buttons confirm, the left stick selects. Added
beyond the bindings file, because it has no gamepad navigation entries: d-pad up/down select and START
backs out. Entries take no keyboard focus, so Enter (ui_accept) does nothing - confirm is the game's
binding. Mouse: hover selects, click activates. UI sizes scale with min(h / 720, w / 1280).
WHY: the ticket's readability and input rules; everything else is taste, hence contestable.

### D-MENU-10 [CONTESTABLE] - A photo-card sprite stands in a doorway on the menu island (MENU-RECHECK).
DECISION: app/menu_stage.gd treats a roster sprite as a "photo card" when its pose frame's body_rect is
>= 97 % opaque (alpha > 16, sampled every 4 px; measured on the shipped roster: address me's office
photo 1.000, the densest cut-out 0.801, so no cut-out is anywhere near). Detection is from pixels, never
by id (FIX-A14 boundary). A photo card is (1) graded: Sprite3D.modulate #CCD4F2 (about -18 % value and a
little cooler, the act's indigo light); (2) set in a doorway of the island's own materials: two
prop_block posts and a lintel 0.16 u thick, 0.26 u deep, a slab_trim cap and a slab_trim threshold
strip, shaded so the beacon lights them; (3) given an inner shadow: a void-coloured (#02030F) quad 0.02 u
in front of the photo, alpha 0.7 at the edges falling to 0 over 22 % of the width / height (corners
darkest; measured on a close-up: corner luminance 191 -> 114, centre untouched). The doorway turns with
the billboard every frame (advance()); test_menu.gd pins detection (synthetic opaque vs cut-out
textures), the grade, the doorway's facing before and after the camera moves, and that no cut-out is
framed or graded. The photo itself is never cropped, keyed or masked: the owner's ruling keeps the
office background, and every pixel of it is still drawn. Also: the front-row gold gift moved from
(3.1, 3.0) to (2.7, 3.3) - the new seal lies flat and wide, and the old spot put the gift's glow over
its face from the default camera.
WHY: unframed, the full-background photo read as a bright flat rectangle pasted onto the island (the
only hard-edged rectangle in the scene). In a lit doorway it reads as a room in the void - an elephant
standing in an office you can see into - which keeps the owner's photo intact and makes it belong.
[CONTESTABLE]: the doorway is taste; overrule by setting CARD_COVERAGE_MIN above 1.0 (no card is ever
detected; the photo then shows exactly as before).

### D-MENU-11 - The menu no longer lifts billboards; supersedes D-MENU-8.
DECISION: FIX-BILLBOARD fixed the feet-offset sign in view/billboard.gd (D-FIX-BILLBOARD-1), so the
menu's local compensation (`_plant()`, position.y = -2 x body_feet_shift) was removed in c10e618.
test_menu.gd still asserts every body bottom within 0.03 u of its platform before and after animating,
now against billboard.gd's own placement. PARKED.md #21 is resolved.
WHY: D-MENU-8 said to remove the lift once billboard.gd was fixed; leaving it would double-correct.

### D-LOAD-1 [CONTESTABLE] - The loading screen is a flat 2D stage, deliberately NOT the 3D void (TICKET LOADING)
DECISION: `app/loading_screen.gd` now builds a 2D scene: a vertical indigo-to-black gradient backdrop
(`#1A1238` -> `#05050F`), drifting cyan / pink / white confetti dots, a cyan-lipped floor slab with
tile seams, and one enemy gag on it (D-LOAD-2). The palette is the game's own: `#7CFFF4` (gift rim / beam)
for the floor lip, subtitle and gift boxes, `#FF4FD8` (the tripmine tell) for the bar fill and the
"FIELD NOTE" header, `#FF2A2A` (danger text) for the "!" "?" "BONK" beats, white-on-ink speech bubbles.
The wordmark and the line "the world is serious. the enemies are not." are kept from T-024 - that line
is the whole brief in one sentence. Code: `app/loading_stage.gd` (drawing), `app/loading_gags.gd` (model).
WHY: the owner asked for the same theme in a different register - serious 3D void in the world, silly
flat 2D here. Flat shapes, big type, bubbles and squash-and-stretch read as a cartoon, which is the
register; the 3D fog/biome look would read as a continuation of the game. Colours are re-used, not
new, so the screen is still recognisably this game. [CONTESTABLE]: the exact gradient and confetti
density are taste; a flat black backdrop would also satisfy the brief.

### D-LOAD-2 [CONTESTABLE] - Five gags from the real sprites; seeded pick, never the previous load's (TICKET LOADING)
DECISION: five gags, each starring real art from `game/content/enemies/<id>/sprites/*.png` and nothing
generated: `toucher_slip` (the toucher steps on one of its own flickering glitched floor tiles, tumbles,
lies flat, "i meant to do that.", gets up and leaves), `seal_giftbox` (a black gift drops on the seal's
head, it staggers blind: "mfph!", then "10/10. keeping the box."), `coil_launch` (squash, "BOING", launched
straight off the top of the screen, "ok. that went well.", falls back in elsewhere, "worth it."),
`kiwi_larper` (the kiwi cat floats up to a gift, the lid pops, a gift Larper is inside, the cat bolts; "act
natural."; the cat peeks back in: "...is it gone?") and `ben_bonk` (smoke at the destination, "BONG", thicc
ben arrives, the arrival launch sends him through the top of the screen, "BONK", he falls back, the stage
shakes, "ow.", he teleports out). `pick_gag(seed, previous)` is seeded and deterministic and never returns
the previous load's gag (`loading_screen.gd` remembers it in a static var; display-only, the timing law never
reads it). The jokes are about the enemy's own bad day, never about the game: the enemies are in on it.
WHY: the five chosen are the ones whose real behaviour makes the gag true - the toucher really does own a
glitched floor (DESIGN 5.8), the seal's threat is a head-on dash, the coil really does launch itself (apex
4 u), the Larper really does pose as a gift, ben's launch really does send YOU skyward and the joke is that
it sent him. Enemies whose sprites are the weak spot (the nuke strip 512x128, Claude's logo, gin, address
me) were left out rather than posed badly. [CONTESTABLE]: which five, and the lines.

### D-LOAD-3 [CONTESTABLE] - A gag is a 5.0 s timeline whose first 2.0 s already contain the joke (TICKET LOADING)
DECISION: each gag is a 5.0 s loop (`loading_gags.CYCLE_SECONDS`). Beat A (0-2.0 s) is set-up and
punchline; beat B (2.0-5.0 s) is a tag that only the first launch (5.0 s) sees; a load slower than 5.0 s loops
the timeline (every gag starts and ends with its enemy off stage or at rest, no pop). The stage time IS the
display time (`elapsed`), so a restart that holds exactly 2.0 s plays beat A and stops on the punchline
frame; the test asserts every gag has a fully shown spoken/printed beat inside the first 2.0 s.
WHY: the owner's ruling makes a restart exactly 2.0 s; a 5.0 s gag cut at 2.0 s would be cut mid-setup on
every restart, which is the screen most players see most often. Designing the joke to fit 2.0 s and
treating the other 3.0 s as a bonus is the only way both durations land.

### D-LOAD-4 [CONTESTABLE] - Motion is procedural on the real PNGs; props are drawn shapes (TICKET LOADING)
DECISION: no image-generation model exists here, so every motion is a pure function of time on the real
sprite: position, rotation (one full tumble, lying flat), squash and stretch (`sx`/`sy`), alpha, frame swap
(the toucher's own flicker frames `cycle_00..02` are the glitch look, its `floor_00..04` decals are the
glitching tile), a soft floor shadow that shrinks as the sprite leaves the ground, and a shake of the
whole stage on ben's landing. The only drawn props are the ones the game itself shows: the black gift
with cyan rim (the game's gift look), speech bubbles, smoke puffs, a ground ring. Sprites are cropped to
their opaque rectangle at load (`Image.get_used_rect`) because the 512x512 sheets carry large transparent
margins. A missing PNG renders as a magenta TBD checker (FLEET_PACK R7), never an error; the test checks
all gag sprites exist and that the fallback works.
WHY: the brief says real art or a TBD placeholder, and procedural motion is the only motion available.
Reusing the toucher's flicker frames costs nothing and keeps the glitch identity. [CONTESTABLE]: the
easing choices and amplitudes are taste.

### D-LOAD-5 - THE TWO-DURATION LAW (owner ruling, this ticket, FINAL): first launch 5.0 s, every restart exactly 2.0 s
DECISION (the ruling is the owner's and is not contestable; the four implementation choices below are
the contestable parts): `loading_screen.gd` holds FIRST_LAUNCH_SECONDS = 5.0 on the session's first
launch and RESTART_SECONDS = 2.0 on every restart. The law is `static func hold_seconds_for(first_launch:
bool) -> float` - a pure function of an explicit flag, never wall time or a global - and `start(seed,
simulated_load_seconds = -1.0, p_first_launch = true)` binds it (`set_first_launch`, `is_first_launch`,
`hold_seconds` expose it). The default is TRUE so T-024's callers and tests (the 5.0 s assertions) keep
working unchanged; the app layer must pass `false` on every restart. `MIN_DISPLAY_SECONDS` stays, equal to
the 5.0 s first-launch hold.
Choices that interpret the ruling [CONTESTABLE]:
 (a) "never less, never more" is read as a law about the HOLD: a load faster than the hold completes AT
     the hold; the step that reaches the hold is clamped to land exactly on it (`shown_time() == 2.0`
     for any step size, a 1/60 s frame or a 5 s step), so a coarse frame cannot overshoot;
 (b) a load SLOWER than the hold completes at its own duration (a 3.5 s restart load shows 3.5 s): the
     level has to exist before the screen can go, and "shows real progress if slower" is the T-024 /
     DESIGN 14 text the ruling did not retract. The screen never adds waiting on top of a slow load;
 (c) an instant load (`simulated_load_seconds = 0.0`) now reads fraction 1.0 (T-024 left it at 0.0 and
     it never completed - a real bug for "never block a fast load");
 (d) with no load source at all the screen does NOT complete (a screen with no load is not a loaded
     level); the app layer must call `set_load_progress` or pass a simulated duration.
The feel probe (`tools/feel_probe.gd`) is re-specified: `loading_screen_hold >= 5.0 s` and
`loading_screen_total_l30 <= 8.0 s` stay exactly as they were, for the first launch; new rows
`loading_restart_hold >= 2.0 s` and `loading_restart_total_l30 <= 2.0 s` pin the restart. No bound was
loosened and no row deleted. DESIGN.md section 2 / 14 [CANON] still say ">= 5.0 s" for run start: that
contradicts this ruling and is recorded in PARKED.md #20 for the owner to update, not silently resolved.
WHY: the owner ruled it; the tests prove both branches with the clock injected, so neither duration can
drift, and the clamp makes "exactly 2.0 s" literally true rather than "the first frame after".

### D-LOAD-6 [CONTESTABLE] - The progress bar is the real load, with a status line in the screen's register (TICKET LOADING)
DECISION: a single bar, cyan-outlined, `#FF4FD8` fill, driven only by `load_fraction()` - the real loader's
`set_load_progress(p)` once it has reported, else the simulated estimate the tests use; never a fake
easing. The status line is honest about the number and silly about the verb: first launch "setting up the
void... 63%", restart "rebuilding the void, again... 63%" (`status_text()`). A fast load pins the bar at
100% for the rest of the hold, as in T-024.
WHY: the brief forbids fake bars; the words are the only place the register can show without lying. A
restart says "again" because it is one - the second time through is the joke the enemies are in on.

### D-LOAD-7 [CONTESTABLE] - Layout: wordmark top, stage middle, field note + bar bottom (TICKET LOADING)
DECISION: the wordmark (56 px, ink outline) and the cyan subtitle on top; the gag stage uses the whole
backdrop with its floor at 470/720; the bottom 190 px carry the "FIELD NOTE" header, the tip (20 px,
820 px wide, centred), the 560 px bar and the status line. The stage scales uniformly to the window
(1280x720 virtual) and is centred, so any aspect ratio keeps the gag undistorted.
WHY: tips are the onboarding, so they stay big and readable under the joke rather than over it; the
virtual-size stage keeps every gag's choreography identical at any resolution.

### D-LOAD-8 - The tip pool is 30, every tip checked against the CODE; 9 written, 3 reworded (TICKET LOADING)
DECISION: `data/tips.json` goes from 21 tips (11 hazard_tell) to 30 (15 hazard_tell; weighted pool 60).
Each tip carries a `source` naming the file/constant it was checked against, and `test_loading.gd` pins the
numbers the tips quote to the code (`sim/mines.gd` CONTACT_R / BLAST_RADIUS / DEFUSE_*, `sim/gifts.gd`
STRAGGLER_DEN, `view/straggler_beam.gd` BEAM_TOP, `sim/controller.gd` DEFAULTS, every `enemy.json`
`stats`, and the jump windows computed from jump 12 / gravity 32), so a tip that stops being true fails
the gate. NINE tips are NEW and written by this ticket (the response says so): `tip_mine_blast`,
`tip_last_light_once`, `tip_invuln_window`, `tip_you_rumble`, `tip_isagi_tell`, `tip_claude_plushie`,
`tip_toucher_infect`, `tip_coil_shock`, `tip_beacon_restore`. THREE existing tips were found not fully
true in this build and reworded: `tip_mine_range` said the star/particles show "inside 12 u" - the view
ramps them 14 u -> 10 u (12 u is the sim's ring/telegraph distance), now says so; `tip_you_ring` said
"translucent red band" - no YOU?! ring view exists in this build, only the sim ring (1.0 u tall, 1.5 u
below-feet band), so the colour claim was dropped and the 0.10-0.65 s window is now computed;
`tip_claude_drums` said "Claude plays at 100 BPM" - 100 is the BASE, `bpm_per_agitation` 0.6 speeds it up
with agitation, now says so. The other 18 originals were checked and kept (only their `source` strings
were added). Facts that were checked but NOT turned into tips because the build does not fully back them:
any claim that the toucher's infection speeds up (`infect_interval_min_ticks` 72 is not used by the
behavior), any colour of the YOU?! / nuke rings (no view), and the seal's "mouth-open frame" telegraph look.
WHY: the owner's rule - a tip that is not true in the build is a bug - needs a check that runs, not a
claim; the pins make the verification repeatable. [CONTESTABLE]: which nine facts were worth a tip.

### D-LOAD-9 - Hand-off notes for the app layer (TICKET LOADING)
Frozen API kept in full; additions: `start(.., p_first_launch := true)`, `set_first_launch`, `is_first_launch`,
`hold_seconds`, `gag_id`, `status_text`, `static hold_seconds_for(first_launch)`, constants
FIRST_LAUNCH_SECONDS / RESTART_SECONDS. APP-FLOW must pass `first_launch = false` on every restart (the
default `true` would hold a restart for 5.0 s). DESIGN.md section 2 says "no loading screen between
levels" (lobby gate -> next level <= 2.0 s) while the ticket says the screen appears "on every level load per
the flow": the screen object supports any call site, the choice of call sites is the flow's, and the apparent
conflict is parked (PARKED.md #21), not resolved here.

### D-LOAD-10 - The seal gag is re-staged for the new belly-down pup (TICKET LOADING-RECHECK)
DECISION: the seal art is now a transparent harp-seal pup lying on its belly, facing the camera (head at the
left of the sprite). `seal_giftbox` keeps its joke and its lines ("mfph!", "10/10. keeping the box.") but is
re-staged for that pose: (1) the pup never mirror-flips - the old gag flipped the sprite whenever it changed
direction, which with the box stuck to the head side made the box teleport 140 px across the sprite; now the
head stays left, the box sits on it, and the pup moves head first both ways; (2) the sway/hop of an upright
waddler is replaced by a belly scoot (the body humps and stretches once per scoot, a small blind wobble while
the box is on); (3) the box rests on the floor over the whole head instead of floating 6 px above it. Beat A
still lands the whole joke inside 2.0 s: the pup looks straight at the camera 0.0-0.55 s, the gift drops on
its face 0.55-0.95 s, "mfph!" is up 1.2-2.3 s. A pup lying down facing you is a BETTER setup for the joke
than the old art - it looks at you right up to the moment the box lands - so the gag was kept, not swapped.
Also in loading_stage.gd: a speech bubble draws its text only at full size (s > 0.97, was 0.8), because
mid-pop the scaled bubble is narrower than the text and the line spilled out of the box (seen on every gag's
first 0.1 s of bubble). Re-rendered all five gags (stage drawn windowed at 1280x720, 6-8 times each) after
the change: the other four are unchanged and read correctly. No tip changed: tip_seal_bark and the seal
clause of tip_hurdle are pinned to enemy.json by test_loading.gd (unchanged art, unchanged numbers), and
tip_address_me states only the arbiter conditions and the 1.5 s hold - never the look of the enemy, so the
new office-photo art does not touch it. billboard.gd's feet fix does not apply: the loading stage is 2D and
positions every sprite itself.
WHY: the owner replaced the art; the gag is built on its pose.

### D-FIX-APP-BOUNDARY-1 - The three app/ files FIX-A14 landed are made content-derived (FIX-APP-BOUNDARY)
DECISION (each hit, by route):
- app/world.gd enemy-factory table -> probed at load, no id named: module-level `behavior()` /
  `new_behavior()` static factories first, then the single inner script constant whose value is a
  Script whose name ends in "Behavior", else the module script itself. Verified against the shipped
  roster: coil/toucher resolve via `behavior()`, thicc_ben via `new_behavior()`, gift_larper/isagi/
  kiwi_cat/seal via the inner-class probe, and the five file-as-behavior modules via `K.new()` -
  the same objects the old match arms constructed.
- app/world.gd `if id == "isagi"` (nested stats for one behavior) -> the behavior module declares its
  own nested-stats cfg key as a `cfg_stats` constant on its script; isagi's inner Behavior declares
  `cfg_stats := "stats"` and no other module declares one. `_cfg_for` nests entry.stats under the
  declared key. Verified: only isagi gets the nested dict, exactly the old behavior. A future module
  that wants the same nesting declares the same constant and is picked up without an edit.
- app/world.gd comments naming curse ids (the time-of-day family), five file-as-behavior enemy ids, and
  the isagi parenthetical -> reworded (D-FIX-A14-1: comments carry no exemption).
- app/loading_gags.gd gag roster (the SPRITES const) -> moved to a new content file,
  res://content/loading_gags.json (content/ is not scanned, and content ids belong to the content
  tree): gag id -> [enemy_id, sprite_name] pairs, first-appearance order fixing each gag's cast slots.
  The file is read at run time (`sprites_for` / `cast_for`); the gag builders take the cast as a
  parameter and fall back to drawing nothing if the manifest is missing, never a crash. test_loading.gd's
  one SPRITES reference now calls `sprites_for(id)` - same assertions, new accessor. The look is
  unchanged: same sprites, same choreography, same pick order.
- app/menu_stage.gd `BIOME` const -> picked from the content tree at run time by a palette field: the
  biome whose `palette.void` equals the menu backdrop's void colour (#02030F, menu.gd C_VOID), with the
  level set to that biome's first level (fog_env reads the act density from it). Fallback when no void
  matches: the deepest act (highest first level) - a content drift, not a crash. TODAY'S PICK IS
  UNCHANGED (the void match resolves to the same biome the island already wore, level 19), so the menu
  keeps its look. [CONTESTABLE] the fallback rule - owner may flip to hard-fail; and the choice to key
  on `palette.void` rather than act order: `palette.void` is the colour the menu actually renders, so
  the island and the column share one constant; act order picks the same biome today but would
  silently re-pick on any content reorder.
- app/menu_stage.gd "the nuke" comment -> reworded.
- app/menu.gd C_VOID comment naming the biome -> reworded ("the void backdrop").
- app/loading_screen.gd "more" (two comments) -> "longer" (English-prose collision; D-FIX-A14-1's
  reword rule - content ids can't carry prose exemptions).
- app/menu_howto.gd "you" (six player-facing strings) -> reworded to third person / imperative
  ("the player respawns", "after a tell worth learning", "is fatal - even mid-jump", "while the player
  holds"). Every phrase test_menu.gd pins in the panel is kept verbatim ("%d void charges",
  "restores 1 charge", "0 charges", "kill on contact - instantly", "opens the beacon", "Last Light").
No PARKED rows, no allowlist, no exemption anywhere. game/tests/test_boundaries.gd untouched;
game/core/roster.gd untouched and its contract unchanged; no content file's ids touched (the one new
file is game/content/loading_gags.json, a manifest, not a rename).
WHY derivation over rewording for the named ids: prose cannot reword away a name a file genuinely
depends on, and D-FIX-A14-1's rule is that the check grows with the content tree. The manifest and the
probes carry the same information from the content tree, so FIX-A14 holds for the app layer too. The two
English-prose hits were un-derivable by definition (they are prose) and were reworded per D-FIX-A14-1.
Gate evidence: pending at commit time; recorded in the handover entry once the gate run completes.

### D-FIX-BILLBOARD-1 - the billboard feet offset sign: SpriteBase3D.offset.y is +up, the body bottom stands on the node origin
`game/view/billboard.gd` `_apply_frame()` computed the feet offset with the wrong sign, so
EVERY sprite drawn through it (all in-game enemy views, the lobby exhibits) rendered its body
BELOW the node origin instead of standing on it - thicc_ben's 4 u body landed ~5.1 u under the
island. The body's bottom edge sits `(br[1] + br[3]) - frame_h * 0.5` px BELOW the frame centre;
SpriteBase3D.offset.y is world-up positive, so standing that edge on the origin needs the
POSITIVE distance, not its negation. `body_feet_shift` and `offset` were negated together, so
whatever reads `body_feet_shift` gets the same correction. Two verification routes, both
independent of the formula being fixed: (1) the Godot 4 docs for SpriteBase3D.offset ("When you
increase offset.y in Sprite3D, the sprite moves upward in world space (i.e., +Y is up)");
(2) `SpriteBase3D.generate_triangle_mesh()` called on real billboards built from the shipped
sprites.json - the generated quad's lowest vertex equals `(offset.y - frame_h/2) * pixel_size`
exactly, for every offset tried (headless Node3D, offset never re-read by the verifier). Note
generate_triangle_mesh() CACHES per node (it kept frame 0's offset after later frames changed
it), which is why both the probe and the test build a fresh billboard per frame. Measured
before the fix (body bottom y rel. node origin): thicc_ben -4.56..-7.52, kiwi_cat -1.59..-1.65,
nuke n/a (see below). After: y = 0.0000 on every frame of every enemy.
The missing assertion that let this ship is now in `game/tests/test_billboard.gd`
(`_feet_all_enemies`): for every enemy in content/enemies, every animation, every frame - the
body bottom lands on the node origin within 1e-3 u. Measured WITHOUT the offset expression the
code uses: (a) from engine-generated quad geometry (mesh min-y + px distance from frame bottom
to body bottom, x node scale), (b) from the node's own offset property read after _apply_frame.
Red on the old sign: 99 failures (one per enemy frame, all sunk). Green on the new one.
Sweep results (nothing else was compensating for the sign): `body_feet_shift` is read nowhere
outside billboard.gd; no view or test pins a sprite's y offset; the only billboard child y
writes are kiwi_cat_view's symmetric bob (+/-0.08 u from the anim block, base 0) and
gift_larper_view's defuse grey-out drop (0.5 u below ITS OWN captured base y, not a sign
compensation); antechamber scales `bb.scale` and `bb.world_height` by the same exhibit factor
(uniform scale, feet-at-origin preserved with the fixed sign); thicc_ben_view reads `_base_scale`
after setup. gift_larper_view sets `billboard.world_height = world_height` after setup without
re-applying the frame - a redundant no-op (the doc value it assigns is the one setup already
used), not a sign issue; left alone. No document in the repo states the feet-offset sign, so no
PARKED.md row. body_rects were re-checked against the textures (all fit; validate_sprites pins
body_rect to the alpha>16 tight bbox), so no clipping/floating from art data other than the sign.
CAVEAT (reported, not re-tuned): `nuke/sprites.json` has `world_height: null` (SR-2: the NUKE
attack_descent frame carries no body row), so the billboard computes scale 0 and the sprite is
invisible regardless of the sign - the sign fix cannot be observed on nuke until the owner rules
on its world_height. The forced-`world_height = 2.0` probe showed the same sign error and the
same fix (body bottom -1.92..-2.06 before, 0.0000 after). Similarly `spawn_00` for thicc_ben:
bottom at the origin like every other frame. ENEMIES.md / DESIGN.md unchanged.
### D-FIX-A3-1 - Bot edge discipline: weighted routing, validated arcs, banned edges (FIX-A3)

The bot's router was an unweighted BFS, so a one-edge drop was cheaper than a long
walkable bypass and the follower "walked off and prayed" when no arc validated
(8 of 10 level-1 deaths D-VOID in AUDIT.md's A3 sample; T-081 at scale: 175 of 176
charges spent terrain-caused, 99.4%). FIX-A3 changes ONLY the bot policy in
game/tools/bot_run.gd: (a) Dijkstra costs - same-level walk 1, 1 HU step down/up 2/3,
a rise over a gap 6+2*gap, a gap drop to just-below ground 6, a drop onto far-below
ground 60 (one-way, no recovery); (b) a through-air edge is followed only when the
controller's own jump physics validate an arc that lands within 1.15 u of the far
waypoint (the old "any tile but the takeoff" acceptance validated garbage arcs - a
5-cell jump at approach speed 2 u/s looked valid, missed the far tile, D-VOID);
(c) a refused edge is banned for the level ("from>to"), never relaxed onto, with a
300-tick lift cooldown when nothing reachable remains; the beacon route lifts bans
immediately (the beacon is the only exit). No sim file, band, threshold, or enemy
constant is touched; test_bot_run.gd's determinism assertion stays green.

### D-FIX-A3-2 - [CONTESTABLE] Bot enemy-awareness constants (FIX-A3)

No document states the bot's own anti-enemy geometry; these are bot-policy numbers,
not sim numbers, chosen for their gameplay reason and freely re-tunable by a future
competence pass: HURDLE_DIST 2.0 u (a contact-kill body closing inside this triggers
the ENEMIES.md kiwi-cat counter-play jump "a jump exceeds its 1.5 u reach from 0.16 s
to 0.59 s" - at combined closing ~14.6 u/s a 2.0 u trigger leaves ~0.07 s margin,
measured too late in traces), AVOID_DIST 3.0 u, the menace cost +30 per tile within
2 tiles of a live contact-kill body (the route curves around a chaser's position),
the arc-landing tolerance 1.15 u, and the ban-lift cooldown 300 ticks. These are
bot-policy estimates of what a human player does, not sim numbers; ENEMIES.md and the
enemy.json stats are untouched.

### D-FIX-A3-3 - A3 remains FAIL at the FIX-A3 build: parked (see PARKED.md #24)

Re-measured on the rebased build (main with KIWI-SLOW, merge 64e3332, owner ruling
D-KIWI-SLOW-1 FINAL): 82 of 100 seeds complete level 1 (was 56/100 with the fast
kiwi; audit baseline 1/10), median level-1 sim time 43.4 s over completions
(criterion 120 s: met whenever the level is completed). Level-1 failures (44 at the
old kiwi, 18 now): D-KIWI 8, D-VOID 4, stuck 4, timeout 1, D-COIL 1. The criterion
still misses; parked - no threshold moved, no criterion edit, no enemy number
touched by this ticket (the kiwi numbers are the owner's, D-KIWI-SLOW-1).

Pre-ruling sweep (the build before KIWI-SLOW): 56 of 100 level-1 completions,
median 43.4 s; back then 37 of the 44 level-1 failures were D-KIWI. The rebase onto
KIWI-SLOW (owner ruling D-KIWI-SLOW-1) re-measured 82/100; the kiwi's remaining 8
level-1 kills, the 4 D-VOID, the 4 stuck and the 1 timeout are the kept evidence -
the level-1 failure list with the current build is: seeds 10, 22, 31, 35, 44, 49,
51, 53, 55, 63, 64, 68, 69, 74, 82, 87, 88, 92.

### D-T099R-1 - audit judgment: A12 is judged against D-LOAD-5 FINAL for restarts [CONTESTABLE]
T-099 RE-RUN (AUDIT.md section 2, A12). FLEET_PACK.md A12 reads "loading screen >= 5.0 s and
<= 8 s", from DESIGN.md section 2 [CANON] ("loading screen on initial load and on run start").
The owner's newer FINAL ruling D-LOAD-5 sets the first launch at 5.0 s and every restart at
exactly 2.0 s; PARKED.md #22 records the contradiction and asks the owner to update the CANON
rows and the A12 text. Measured on 64e3332: feel_probe first launch 5.000 s / restart 2.000 s;
the real app (scratchpad wall-clock probe) 5,000 and 5,004 ms first launch, 2,006 and 2,004 ms
restart. DECISION (the auditor's, not the owner's): A12 is graded PASS, taking the FINAL ruling
as amending the criterion for restarts, the same reading the first audit applied to D-065 FINAL
over A7's "every body contact kills". Nothing was loosened: the first-launch rows are unchanged
and the restart rows were added. Read literally, the restart rows miss A12's ">= 5.0 s".
If the owner does not accept that D-LOAD-5 amends A12, A12 is PARTIAL and the verdict line
in AUDIT.md section 11 changes accordingly. Neither FLEET_PACK.md nor DESIGN.md was edited.

## Handover log

(append one line per session: date, who, what is finished, what is next)
- 2026-11-17 FIX-BILLBOARD (this session, worktree t3/fix-billboard-feet-sign): the feet
  offset sign in view/billboard.gd fixed (D-FIX-BILLBOARD-1); every enemy frame's body bottom
  now stands on the node origin (was sunk by 2x the intended shift). New geometric assertion
  in tests/test_billboard.gd (red on old sign: 99 failures; green on new). Sweep: no other
  file compensated; nuke world_height null caveat reported (sprite invisible, owner to rule).
  No PARKED rows. No push. Gate: GATE OK (9 ran, 0 skipped, 246 s); TESTS 56 passed 0 failed;
  zero SCRIPT ERROR lines.
- 2026-11-17 T-051 (zai-glm-5-3-flash, this session): the enemy-linked scripted test file
  DONE and green on t3/t051-enemy-curse-tests (08c5e04): game/tests/ 
  test_curses_scripted_enemy.gd, one test per enemy-linked scripted curse (the 12 whose
  modules are on main), long_toll done-when proven END-TO-END against the real thicc_ben
  behavior; four module repairs the honest sentences forced (D-T051-21); the other 12
  modules + check_mine_cap.gd are on the unmerged t3/scripted-curses-groups-4-6 branch
  (PARKED.md 16 - the understudies 20% mine-cap assertion rides with that merge). Gate at
  the end of the session: GATE OK (9 ran, 0 skipped, 131 s), TESTS 50 passed 0 failed.
- 2026-11-17 T-061 (zai-glm-5-3-flash, this session): tools/feel_probe.gd (A12: 6 rows,
  all PASS) + tools/perf_probe.gd (A13: the pinned 22-enemy scene - all 22 place per the
  fixed vote list, dodge bot, third-person rig, 600/120 frames, 1920x1080 v-sync off,
  OS/CPU/GPU printed; p99 1.20 ms <= 16.6, mean sim tick 0.733 ms <= 2.0, both PASS) -
  D-T061-1..7. The scene exposed and fixed two sim/enemy_runtime.gd spawn-plan defects
  (dropped tail + duplicated copies + SR-3 scope, D-T061-6, regression in
  test_spawn_rule.gd) and view/billboard.gd's world_height-null crash (T-016 schema's
  documented no-body row). CAVEAT (D-T061-7): this box renders through a a virtual
  display (VkResult -13 every frame) - the frame rows are CPU-side costs; mean_sim_tick
  is the solid number. Response: tickets/T-061.response.md. TESTS 47 passed 0 failed.
- 2026-11-17 GLM (T-051): scripted curses, GENERAL family (the 11 `script: true` /
  `requires_enemy: null` curses: cold_start, crowded_dais, crumbling, curfew, dull_gifts,
  early_bird, leaky_purse, no_refunds, rearguard, slow_door, unmarked). One
  content/curses/<id>.gd module per curse (hook handlers over (state, api), the contract
  in D-T051-1) + tests/test_curses_scripted_general.gd (one test per curse asserting the
  JSON's rule sentence + the family contract check). TESTS 42 passed 0 failed; gate green
  in the session (GATE OK). Module contract pinned in D-T051-1; readings D-T051-2..4.
  No PARKED rows; JSON curse files untouched (T-050 owns them).

(append one line per session: date, who, what is finished, what is next)
- 2026-11-17 T-054 (spawn, inkling-2-small-free): act -> biome wiring
  - view/lobby/antechamber.gd: the hall fog now follows the biome it was built with (was always
    Deepwater via a _pal.get("biome", ...) key resolve_palette never returns); tests/test_biomes.gd
    (NEW; TESTS 41 -> 42) pins biome_id_for_level at every act boundary + the 31+ cycle (D-T014c-1),
    BIOME_ORDER, and all five biome files' act/levels/density/hexes verbatim vs DESIGN.md section 10
    (deepwater walkway #3A74FF per D-T011-6) via resolve_palette().
  - fog_check.gd for all 5 biomes: FOGCHECK OK (250 checks) - no colour needed adjusting (no biome
    fails the section 12.3 rows); the DESIGN.md section 10 INFO row (tripmine vs platform_light >=
    3.0) fails 5/5 and is unsatisfiable by any platform_light hex - parked (PARKED.md row 11), zero
    hexes moved, D-T054-2 [CONTESTABLE]. 
  - tools/shot_biomes.gd (NEW, windowed): one top-down screenshot per act biome (seed 7, act-final
    level) -> game/shots/biome_{deepwater,verdigris,violet_hour,indigo_trench,pale_abyss}.png.
  - DECISIONS D-T054-1, D-T054-2; tickets/T-054.response.md. GATE OK expected; no push.
- 2026-11-17 T-040 (Claude, this session): content/enemies/claude/enemy.json + enemy.gd (the
  drums/strings/wind bar cycle at 100 + 0.6 x agitation BPM, the 20 u leash, agitation +2/s with
  plushie calm -35, the Deadline) + view/claude_view.gd (frames + drum bands + strings line +
  sweep beam + wind dots + plushie 3-frame idle, driven through view/enemy_anim.gd) +
  view/audio/claude_audio.gd (ui_chime / keystroke_tick / notification_ping / squeak_pop hooks)
  + tests/test_enemy_claude.gd (every 5.11 number/timing at +/-1 tick, D-057 kill fixtures; the
  shot's wall death, drums/strings/wind and contact all D-CLAUDE) + DECISIONS D-T-040-1..7.
  test_content.gd scoreboard enemies 8 -> 9, content_ids 95 -> 96. No PARKED rows; no push.
- 2026-11-17 T-035 (spawn, inkling-2-small-free): YOU?! landed - content/enemies/you/enemy.json (min_level 3, 2 votes, open anchor, D-YOU) + enemy.gd (EnemyBehavior; 3.4 u/s pursuit ceiling 0.55, 10 u trigger, 90-tick rumble, 9 u/s ring to 14 u, 240-tick cooldown, feet-window kill rule D-T-035-1) + view/you_view.gd (frames/telegraph/band wired to the T-083 anim block, RGB split + shake + feet ring + translucent red band) + tests/test_enemy_you.gd (D-057-compliant; TESTS 28 passed 0 failed; GATE OK 9 ran 0 skipped 57 s) + DECISIONS D-T-035-1..13, TBD.md row 28. T-073 to read live rings from row["rings"] when the hazard bus lands. No PARKED rows; no push.
- 2026-11-17 T-083-enemies 1-6 (Anim/PNG animation specs, inkling-2-small-free): anim blocks added to the six T-016 sprites.json (kiwi_cat, coil, thicc_ben, isagi, nuke, you) - one entry per section 1.x table row, spec_frames + on-disk TBD frames, binding 60 Hz tick counts; new game/tools/check_anim_data.gd proves all 12 roster tables (hardcoded, CLI id list); DECISIONS D-T083-1..6 appended. Gate green (GATE OK, 9 ran, TESTS 27 passed 0 failed); ANIM-DATA 6 passed 0 failed. The other six report "no 'anim' block" until their half lands. No PARKED rows; no push, branch t3/enemies-1-6-anim-data.
- 2026-11-17 T-074 (spawn, GLM): the D-074 offer draw is live. sim/offers.gd draw_enemy_bay
  rebuilt (NEW / REPEAT / FREE slots + "slot" field on altars, per-enemy caps via enemy_gate,
  chaser ceiling 6 with 0.5 kittens under The Litter - weights in offering_schedule.json's
  "chaser" block, schema extended; intermission carries last_vote into the draw). Tests:
  test_offers extended (1,000 seeded runs to 30: NEW present whenever an eligible unpicked type
  exists 100%, caps/ceiling never exceeded, all 12 types offered by the level-19 vote 1000/1000
  >= 990 bound, same-enemy stacking reaches exactly its cap and stops) - GATE OK (9 ran, 0
  skipped, 45 s), TESTS 25 passed 0 failed; test_schedule/test_lobby untouched and green.
  Uniform-random voter coverage measured 8.9% (informational, D-T074-6). NEXT: T-075 harness.
- 2026-11-17 T-024 (spawn, inkling-2-small-free): app/loading_screen.gd (min 5.0 s hold, real
  progress beyond, tips from data/tips.json, hazard_tell x3 weighted seeded rotation every 5.0 s),
  app/menu.gd (Play/Settings/About/Quit; About = ENEMIES.md disclaimer verbatim; Settings bound to
  app/settings.gd), tests/test_loading.gd + tests/test_disclaimer.gd (A15; README gained the
  ENEMIES.md verbatim line alongside the T-001 DESIGN.md section 14 line). TESTS 19 passed 0 failed;
  GATE OK (9 ran, 0 skipped, 43 s). PARKED row 2 (DESIGN.md section 14 vs ENEMIES.md disclaimer
  wording). DECISIONS D-T024-1..6. Boot-scene wiring (set_load_progress from the real loader,
  play_requested consumer) is unassigned.
- 2026-11-17 T-023 (spawn, GLM): the Antechamber + the offering schedule. view/lobby/antechamber.gd
  (script-built hall), sim/intermission.gd (bay state machine, Select sim inputs, gate), offers.gd
  extended (enemy + curse draws), PlayerInput.select, schedule file gains starter_pool + the enemy
  gate table. Tests: test_lobby (A9) + test_schedule (0-40, 25-30 repeat, data-edit proof). Gate:
  GATE OK (9 ran, 0 skipped, 42 s), TESTS 19 passed 0 failed. NEXT: T-074 attaches at
  offers.gd enemy_candidates/draw_enemy_bay (D-T023-6).
- 2026-11-17 T-011 (spawn, GLM): view/level_mesher.gd, view/fog_env.gd, tools/shot.gd, tools/fog_check.gd,
  tests/test_mesh.gd, 12 screenshots in game/shots/. run_all green (TESTS 4 passed 0 failed; 7@30 =
  3,662 tris, 11 ms mesh). Gate: 5 OK, 1 RED at fog readability - the reference Deepwater palette
  fails section 12.3 row 1 for the walkway (2.737 < 3.0, D-T011-2); colours/thresholds untouched
  (T-054 owns the fix). DONE-WHEN "fog_check green for Deepwater" therefore NOT met - see
  tickets/T-011.response.md for full numbers.


- 2026-11-16 Fable 5.2 (checkpoint 1): DECISIONS A/B/C written. `terrain_ref/voidgen.py` WORKS
  (0.02–0.06 s per level, deterministic, shortcut guaranteed). TERRAIN_SPEC.md complete (GEN_VERSION 1).
  In flight (delegated, may be unfinished if you read this): `terrain_ref/validate.py` +
  `test_validate.py` (GLM), `terrain_ref/render.py` + `gallery.py` (Inkling), Godot install into
  `tools/godot/` (Inkling), `research/NULLSCAPE_PATTERNS.md` (Inkling).
  NEXT if interrupted here: (1) run `python validate.py --seeds 0:5000` in terrain_ref/, fix the
  GENERATOR (never the thresholds) until all H/D checks pass; (2) `python gallery.py --write`;
  (3) port voidgen.py to GDScript with hash parity on the gallery (spawn
  (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)); (4) write TERRAIN_REF.md; then Stage 2, 3.

- 2026-11-16 Fable 5.2 (checkpoint 2): ALL FOUR documents exist: TERRAIN_SPEC.md, TERRAIN_REF.md,
  DESIGN.md (+ game/data/offering_schedule.json), FLEET_PACK.md (+ README.md). Generator FROZEN at
  GEN_VERSION 1 after three generator fixes (D-018/019/020), asymmetric winding arms (D-023) and one
  metric correction (D-022); gallery.json regenerated (16/16). Lead's own measurements: every H check
  and D1/D2/D5/D6/D7/D8 pass; D4 passes with the 4-cell metric.
  STILL IN FLIGHT when this line was written:
  (a) GLM worker finishing `terrain_ref/validate.py` (fix D6 to per-level, D4 to 4-cell blocks, a
      KeyError in the bucket table) and running the official 5,000-seed harness;
  (b) GLM worker finishing the GDScript port `game/terrain/voidgen.gd` to 56/56 hash parity.
  NEXT for whoever reads this: run TERRAIN_REF.md section 2 "Verify". If all five commands exit 0,
  Stage 1 is closed: paste the harness PASS lines into TERRAIN_REF.md section 3 (between the STATUS
  markers) and the port pitfalls into section 5, then start FLEET_PACK.md at T-001. If the harness
  shows a FAIL the lead did not see, fix voidgen.py (never a threshold), follow the change procedure
  in TERRAIN_REF.md section 5. If parity is not 56/56, re-dispatch the port (brief = TERRAIN_REF.md
  section 5 + the rules in FLEET_PACK T-002).
  NOT DONE by the lead: no git commit was made (owner did not ask; FLEET_PACK T-001 makes the first
  commit). The 17 enemy images are not in the repo — owner must drop them into assets_src/enemies/.
- 2026-11-16 Fable 5.2 (checkpoint 3): **STAGE 1 CLOSED.** Both workers reported. Official harness:
  every H and D check passes on 5,000 seeds (numbers in TERRAIN_REF.md section 3). GDScript port:
  PARITY 56/56, ~132 ms per level. `test_validate.py` OK, selftest 5/5, gallery 16/16. Checkpoint 2's
  "still in flight" items are done. Stages 2 and 3 are written. NEXT: start FLEET_PACK.md at T-001
  (T-002 should now pass on first run). Open owner items: D-022, D-042, D-043 are [CONTESTABLE];
  the 17 enemy images must be dropped into assets_src/enemies/; no commit exists yet.
- 2026-11-16 Fable 5.2 (checkpoint 4): owner FINALIZED D-022, D-042, D-043 (entries edited in place;
  the "[CONTESTABLE]" note in checkpoint 3 is superseded — no contestable items remain open).
  Applied: TERRAIN_SPEC §10.3 (4-cell-only threshold, spawn-root anchoring, verify-by-eye step);
  `validate.py` similarity anchored + all 8 symmetries (was effectively 2), new assertions in
  `test_validate.py`; harness re-run 5,000 seeds, every check passes (D4 p99 0.423, max 0.539).
  DESIGN.md: beacon entry = full heal, void fall = 75 HP with the safe-tile rules, death attribution
  by last damage source, heal plinths removed, Field Dressing reworked, Hungry Void = 90 HP.
  FLEET_PACK T-021/T-022 wording aligned. Generator untouched: gallery 16/16 and parity 56/56 stand.
- 2026-11-16 DeepSeek V4.1 (T-VOID): the health pool is gone. D-050 void charges (2 held, a fall costs
  1, the beacon restores exactly 1 capped at 2, a fall at 0 charges is a real death, `D-VOID`); D-051
  lethality (every body contact kills, every projectile/ring/beam/blast/void zone kills on hit, thicc
  ben's blur + eject is the one exception and "Overtuned" is removed, tripmines and nukes kill with no
  numbers, Defuse Kit = deterministic 20%/stack defuse capped at 60%, Subspacial Barrier = 1 tripmine
  shield per level restored on beacon entry, glitched floor = −20% speed + ability lock and explicitly
  an enemy effect outside the §7 curse speed budget); D-052 the knock-on rows (REST = discounted shop
  with no vote and no curse, Field Dressing = one free fall per level per stack, Hungry Void = cap 1,
  Thick Skin → Brace, Regrowth → Cold Blood, Glass Jaw → Brittle, plus Sure Foot, Insulation, Stand
  Fast, Defuse Kit, Subspacial Barrier, Leaky Purse, The Long Toll, Wet Floor, Spreading Rot, Egoist,
  Direct Shot, Second Strike); D-053 Last Light does not save a void death at 0 charges [CONTESTABLE].
  DESIGN.md rewritten in place (§2 respawn row, §3.1–§3.3, §5.1–§5.12, §6, §7 safety rule + 46 curse
  rows, §8 36 upgrade rows + counter-play map, §9 bot note, §11 lobby, §12 stats/hooks/kill API, §14
  HUD pips); FLEET_PACK T-012/T-020/T-021/T-022/T-025/T-027, the enemy-ticket block, T-050–T-053,
  A6/A7/A12 and T-099 updated, with `SUPERSEDED BY D-051` lines under the two superseded owner quotes;
  README describes the charges. Counts hold: 46 curses, 36 upgrades, ids unique. LEFT: no game code
  exists for any of this yet — T-012/T-021/T-053 must implement the charge ladder, the defuse roll and
  the shield order; the terrain worker's files were not touched.
- 2026-11-16 DeepSeek V4.1 (T-SHAPE): terrain shape contract, GEN_VERSION 2. D-025: one dominant
  spawn platform (205 tiles, bbox 19, beacon and 8 spawns unchanged), everything else 1-2 cell
  walkways (step/stair/ledge/flat/ramp) with occasional platforms (bbox <= 7x7, <= 40 tiles,
  3..min(12, 4 + level // 3) per level, pad/disc/cross/ell/terrace/nook/spire/bastion), path share
  >= 0.70 of walkable length and >= 50% of non-hub tiles, flat share <= 0.35, ramp share <= 0.10,
  elevation sd >= 3 HU at L1 rising to >= 6 at L10, >= 50% of sub-area boundaries with |dy| >= 1,
  junction step never 0 at both ends of a walkway; N redefined as % of path length that is 1 wide.
  TERRAIN_SPEC 1A + 6.3/6.4/6.8/9/10, voidgen.py and voidgen.gd ported line by line, validate.py
  gained H16-H22 with 12 planted selftest defects, gallery regenerated on the same 16 pairs,
  TERRAIN_REF 1-6 rewritten. Gates: TESTS OK, SELFTEST 12/12, GALLERY 16/16 OK, 5,000 seeds exit 0
  with H1-H22 all 0/5000 and D1-D9 green, PARITY 56/56 at 43 ms per level. LEFT: DESIGN.md and
  FLEET_PACK.md still name the old archetypes (plaza/arena/gallery/ring/stonefield/vault,
  walk/ramp/gap/stones/beam/stairs) and the old 141-tile hub; the design worker owns those files.
- 2026-11-16 Fable 5.2 (checkpoint 5): owner ticket "void charges + terrain shape contract" CLOSED.
  T-VOID (D-050..D-053) and T-SHAPE (D-025, GEN_VERSION 2) both done by DeepSeek V4.1 workers; the
  lead re-ran every terrain gate independently: harness 5,000 seeds 31/31 checks PASS (H1-H22, D1-D9),
  gallery 16/16, parity 56/56, tests OK. DESIGN.md / FLEET_PACK.md terrain wording aligned with the
  new vocabulary (platform / walkway / spawn hub) by an Inkling worker. Open for the owner: D-053
  (Last Light) is [CONTESTABLE]; D-025 lists three readings (platform-only dominance scope, D5 recipe
  key now includes walkways, boundary rule stricter). NEXT: FLEET_PACK.md from T-001. No commit yet.
- 2026-11-16 Fable 5.2 (checkpoint 6): owner rulings logged. D-053 FINAL (0 charges = real death;
  Last Light only while a charge is held) — DESIGN.md §3.1 updated. D-054: ENEMIES.md reworded on the
  owner's order (four "damage" sentences). D-055: earlier-build references are history, kept and
  marked, never a source. D-025: its three READINGS are PENDING OWNER REVIEW (numbers final).
  Open for the owner: only those three D-025 readings. NEXT: FLEET_PACK.md from T-001. No commit yet.
- 2026-11-16 Fable 5.2 (checkpoint 7): owner rulings logged. D-025 is FULLY FINAL (numbers and all
  three readings; pending marker removed). D-053 reading confirmed FINAL; tripmine consume order fixed
  as defuse roll → Subspacial Barrier → Last Light → death (DESIGN.md §3.3, FLEET_PACK T-021).
  D-033 added: metric definitions may only tighten. D-054 and D-055 confirmed. NO open owner items.
  NEXT: FLEET_PACK.md from T-001. No commit yet.
- 2026-11-16 DeepSeek V4.1 (T-PREFLIGHT-DOCS): preflight items 1, 2, 3, 5, 6, 7 and 24 resolved as
  D-056…D-063. DESIGN.md: §5 spawn fallback order + per-enemy preferred-kind table, `hop` retired
  (§5.2 coil now `lane`), §3.1 charges carry over between levels + safe tile 6 u from bodies and
  projectiles, §3.3 contact = within 0.9 u of the box at any height (a jump does not clear it; the
  bypass is the only way past) + the generator bypass guarantee (terrain decision D-026), §5.4 Isagi
  ball flight line and `perch` preference, §7.2 Cold Start's Athletic penalty is coyote time −0.05 s
  [CONTESTABLE]. FLEET_PACK: T-012 owns Last Light (`test_last_light.gd`) and the 6 u safe tile,
  T-027/A7/T-021/Wave 3 say kill tests run with Last Light spent, A6 and T-053 carry the four-step
  tripmine ladder verbatim, A3 pinned (kiwi cat, `--dodge`, Last Light, 2 charges, ≥ 95/100) with
  T-026's CLI flags. LEFT: the terrain worker's item 4 (mine bypass rule + validator check, version
  bump) and the TERRAIN_SPEC part of item 1 (`hop` in §6.5). No commit.
- 2026-11-16 DeepSeek V4.1 (T-PREFLIGHT-TERRAIN): preflight item 4 and the TERRAIN_SPEC half of item 1
  resolved as D-026. GEN_VERSION 3. Tripmines now need a walkable bypass, and a bypass must stay
  outside the mine's 0.9 u trigger cylinder: contact = within 0.9 u of the box at any height, the
  bypass graph removes every tile whose centre is inside the cylinder (the mine tile and its whole
  column) and every walk/jump/drop/pad edge whose segment passes within 0.9 u of a mine centre, a slot
  is eligible only if removing it disconnects nothing and its cylinder holds no other gift or the
  beacon, and the joint rule forbids the level's mine set from sealing a region (TERRAIN_SPEC
  §6.8.1–§6.8.5, new hard check H23). Modelling assumption recorded: the player's centre runs along
  tile-centre segments, so the adjacent lane of a 2-wide walkway keeps 1.0 u — a 0.1 u margin, flagged
  [CONTESTABLE] with the 1.4 u alternative measured (it would remove a further 19–31% of mines).
  Anchor kind `hop` (id 3) retired and reserved; ids 0/1/2/4 unchanged; the arm trait `hop` untouched.
  D1 now measures mines / eligible slots (old denominator read 1.78 pp, new 0.58 pp) and D2 is
  min(S//5, eligible); both recorded with numbers per D-033. Mine count band 5,000 seeds, v2 → v3
  mean/min/max: 1–5 0.55/0/8 → 0.52/0/8 · 6–10 3.93/0/13 → 3.51/0/10 · 11–15 6.10/0/14 → 5.36/0/14 ·
  16–20 9.09/2/19 → 7.71/1/16 · 21–25 12.12/3/26 → 10.34/2/21 · 26–30 15.06/3/31 → 12.61/2/27 (worst
  mean drop −16.2%, no flag tripped). Ported to `voidgen.gd` line by line. Final gate, all exit 0:
  `test_validate.py` TESTS OK (selftest 15/15) · `validate.py --selftest` 15/15 · `gallery.py --check`
  16/16 · `validate.py --seeds 0:5000` H1–H23 all 0/5000, D1 0.58 pp, D2 300/300, D3 5,000 hashes,
  D4 p99 0.394, D5 0, D6 1.79%, D7 strictly increasing, D8 10.4/75.0, D9 55 ms mean / 191 ms max ·
  Godot parity `PARITY 56/56 OK` at 142 ms per level. No commit.
- 2026-11-16 Fable 5.2 (checkpoint 8): PREFLIGHT GATE GREEN. All 8 [BLOCKS-FLEET] items of
  research/fable-preflight.md are resolved (D-026, D-056..D-063) and marked. The lead re-ran the gate
  independently on the final code: harness 5,000 seeds 32/32 checks PASS (H1-H23, D1-D9), gallery
  16/16, parity 56/56, tests OK (selftest 15/15). Generator is GEN_VERSION 3. The 17 [POST-RUN] items
  are untouched. KNOWN RISK (not a blocker, pre-existing since version 2): 45% of levels need at least
  one re-roll and the worst attempt seen is 11-12 against the H15 limit of 12; on 3,000 fresh seeds the
  tail is geometric (ratio about 0.45), so H15 will fail roughly once per 30,000 levels. Fix after the
  run in the generator (cheaper acceptance of elevation/path-share), never by raising the limit.
  NEXT: owner go-ahead, commit, then FLEET_PACK.md from T-001. Nothing committed since ab471d8.
- 2026-11-16 GLM 4.6 (T-012): player controller and classes DONE on t3/94aebde7 - sim/collision.gd (AABB 0.4/1.8 vs slabs/ramps/props, step-up 0.5), sim/controller.gd (kits, void charges, 8-tile safe ring, Last Light, pads), tests envelope/classes/charges/last_light all green (TESTS 5 passed 0 failed), D-T012-1..4 appended; gate run pending in this session.
- 2026-11-17 T-052 (inkling-2-small-free, this session): the upgrade declarative proof landed on t3/upgrades-declarative-proof - game/tests/test_upgrades_decl.gd (every script:false upgrade through the real modifier path; stat deltas from the DESIGN.md section 8 rows; the pinned script:false/script:true partition; Athletic x1.5 speed / x1.3 air-jump height wired through the real Yearn for Speed card into controller.gd; the R4 centi-gold floor rule over the whole catalog and all 46 bounties via an exact integer dyadic oracle, plus to_centi(2.675) = 267) - insulation.json mul 0.5 -> add 0.1 (D-T052-3) - DECISIONS D-T052-1..3 appended. TESTS 42 passed 0 failed. No content ids added (counts stay 12/99). No PARKED rows. No push.

- 2026-11-17 T-055 (Inkling, this session): tools/synth_audio.py + game/assets/audio/enemies/<id>/<cue>.wav for the 24 cues referenced by the twelve enemy.json files (stats.audio_cues + stats.audio) plus the 6 Isagi/nuke TBD-hook cues (D-T055-2); all recipes/lengths [CONTESTABLE] placeholders (D-T055-3); landing path per merged view hooks (D-T055-1). TBD.md section 8 lists ALL enemy audio as placeholder. python tools/synth_audio.py [--check] re-synthesises / verifies; every enemy.json cue resolves to a file. Gate run at end of session; enemy.json untouched; T-087 owns binding lengths, cue offsets and the check.
- 2026-11-17 T-087 (Inkling, this session): section 3 reconciled (D-T087-1) and completed - 7 new wavs (locked, ring_release, mine_hum, prowl, leaves, beat, string_sweep 3.0 s per D-T087-3; loops at 2.0 s, D-T087-2), flipper_flap regenerated to the 2.0 s bed; enemy.json files gained additively stats.audio_cue_timing + stats.lethal_attacks (D-T087-6) with every cue's sim event + tick offset and the roster's 17-entry ledger (16 lethal attacks + thicc_ben's non-lethal bound arrival); isagi/nuke cue lists wired; the three stand-ins flagged/kept tbd_audio with TBD rows 47-49; tools/check_audio.gd built (three assertions + coverage ledger; negative-tested; the three documents conflicts as PARKED.md #12-15 and SPEC GAPs as D-T087-1..8). Gate green: GATE OK (9 ran, 0 skipped, 52 s), TESTS 44 passed 0 failed.
- 2026-11-17 GLM 5.3 (T-080, acpRegistry spawn, this session): telemetry event log DONE on
  t3/telemetry-event-log - app/run_log.gd (events-only JSONL recorder, 18 closed record types,
  the chain replicated from the event stream, run-wide tick clock D-T080-1); additive sim events
  with no behavior change (void_fall tile/nearest-enemy/before-charges, deaths carry charges +
  Last Light state + the on_screen enrichment D-T080-2, beacon_enter charges_before, mines'
  mine_pass 1.4 u bypass tracker, rt push events D-T080-3, overtime_tier); the bot driver is
  T-060's vendored bot_run.gd (D-T080-7) with additive p_log params; tests/test_run_log.gd: a
  2-level scripted bot run covers 12 types + the units cover mines/void-fall/push-window/chain;
  replay hashes identical with logging on and off; the done-when's pip, death-code (DESIGN 3.1
  closed list) and level-timing equations all asserted. TESTS 49 passed 0 failed. D-T080-1..8
  appended (two [CONTESTABLE] readings: the run-wide tick clock, the 24 u on-screen proxy; the
  20-vs-18 type count noted D-T080-8). No PARKED rows. No push.
- 2026-11-17 GLM 5.3 (T-080, 2nd session, post-rebase red gate): the test's 2-level driver was
  re-based off bot_run.gd after T-060's merge (the bot cannot clear level 1: 0/20 reach
  level 6, dead on 1-3) - the run is now driven direct on the sim surface (test_gifts.gd
  idiom, levels 1-2, real lobbies; D-T080-9); bot_run.gd KEEPS the p_log wiring; the units
  and the replay-hash comparison unchanged; the log itself untouched. Gate: GATE OK (10 ran,
  0 skipped), TESTS 50 passed 0 failed. No PARKED rows. No push.
- 2026-11-17 T-ART thicc ben (this session): thicc ben's TBD magenta frames are now REAL ART on
  t3/thicc-ben-sprite-art. game/tools/art/thicc_ben.gd owns the enemy (pipeline skips it): photo
  cutout (white flood fill + iterated defringe), warm-gilt grade to clear A8 fog contrast
  (1.56 -> 3.29), 512x512 bottom-anchored canvases, a distinct pose per anim-block state
  (cycle/spawn/attack_arrival/attack_ring/recover; telegraph stays frameless per the block);
  sprites.json points the anim block + animations[] at the new files, body_rect = tight alpha > 16
  bbox, tbd: false (aa82feb, D-ART-THICC_BEN-1/2). SPRITES OK 235 checks; FOGCHECK OK 275 checks;
  test_enemy_thicc_ben PASS; run_all 49 passed / 5 failed - the 5 (claude, coil, toucher, you,
  vfx) fail identically on the pristine base: this checkout has no game/.godot import cache, so
  ResourceLoader.load of any PNG fails; not this ticket's to fix. No PARKED rows. No push.

- 2026-11-17 T-016 art module (Inkling, this session): isagi real art DONE on
  t3/isagi-real-art-frames - game/tools/art/isagi.gd owns the frames (the shared pipeline skips
  isagi; corner flood fill could not strip the opaque-white sources); 9 frames written
  (idle/spawn/telegraph/shoot/recover/shot + legacy fire_00/01/02 revamped to the new art), all
  distinct per state; frame_map rebound (isagi_idle_00/isagi_shoot_00/isagi_ball_00), anim block
  timings/loops/effects untouched; animations[] appended (idle/spawn/telegraph/attack/recover),
  fire/shot entries kept in place; tbd -> false; sources[] -> OK. Fog contrast forced a lerp
  toward white on the two photo/logo bodies (D-ART-ISAGI-2, POW curve measured and rejected).
  Checks: SPRITES OK 340 checks; FOGCHECK OK (280 checks over 5 biomes); ANIM-DATA isagi PASS;
  TESTS 54 passed 0 failed, 0 SCRIPT ERROR lines (after a --import pass generated the import
  cache this worktree lacked; game/.godot not committed). No PARKED rows. No push.

- 2026-11-17 T-ART-TOUCHER (inkling-2-small-free, this session): toucher sprites DONE - game/tools/art/toucher.gd
  keys the black (finger) / white (cube) backdrops by border flood fill (not the shared
  corner-fill pipeline, which skips this enemy), crops tight, and derives 17 real frames
  deterministically: cycle_00..02 (idle flicker, also the frame_map targets for the pinned
  spec names toucher_00..02), floor_00..04 (decal relit to a glowing magenta family to hold
  the A8 fog contrast at 40 u - D-ART-TOUCHER-2), plus the new per-state spawn_00 / idle_00..02 /
  telegraph_00..02 / attack_00 (identical silhouette; states[*].frames point at them, appended
  animations[] entries; anim block timings/loops/effects/spec_frames untouched; attack_touch and
  recover stay empty as the table lists). Minimal toucher_view.gd patch so the per-state art
  renders (D-ART-TOUCHER-1, PARKED.md #18 for the brief-vs-pinned-block ambiguity). Gate run:
  SPRITES OK 255 checks, FOGCHECK OK (295), TESTS 54 passed 0 failed, zero SCRIPT ERROR lines
  (after the gate's --import prep on the fresh worktree). TBD.md rows 8/10/11/23 updated. No
  ENEMIES.md, threshold, sim, or other enemy touched.

- 2026-11-17 gift_larper art (this session): the gift Larper TBD magenta frames are gone - game/tools/art/gift_larper.gd cuts tripine.png (alpha-key flood fill, largest-component keep, tight crop, screen-blend grade (175,76,192) for the fog rule) and emits 6 real frames (5 distinct idle cycle frames larper_00..04 -> cycle_00..04.png plus the defused pose defused_00.png); sprites.json tbd=false, animations[] gained an appended defused entry (nothing reordered), anim block tick ranges/loops/fps/effects untouched; telegraph and attack_detonation stay empty by the binding table; gift_larper_view.gd shows the defused pose during the 24-tick grey-out. validate SPRITES OK 220 checks; FOGCHECK OK 260 checks over 5 biomes; fog contrast 3.05-3.87 at 40 u (validate formula) / 4.3+ per biome. D-ART-gift_larper-1/2. Gate at handback: see the run line

- 2026-11-17 gift_larper art (this session): the gift Larper TBD magenta frames are gone - game/tools/art/gift_larper.gd cuts tripine.png (alpha-key flood fill, largest-component keep, tight crop, screen-blend grade (175,76,192) for the fog rule) and emits 6 real frames (5 distinct idle cycle frames larper_00..04 -> cycle_00..04.png plus the defused pose defused_00.png); sprites.json tbd=false, animations[] gained an appended defused entry (nothing reordered), anim block tick ranges/loops/fps/effects untouched; telegraph and attack_detonation stay empty by the binding table; gift_larper_view.gd shows the defused pose during the 24-tick grey-out. validate SPRITES OK 220 checks; FOGCHECK OK 260 checks over 5 biomes; fog contrast 3.05-3.87 at 40 u (validate formula) / 4.3+ per biome. D-ART-gift_larper-1/2. Gate: GATE OK (9 ran, 0 skipped, 179 s), TESTS 55 passed 0 failed. No PARKED rows. No push.


- 2026-11-17 (this session): Claude (Cadence) real art landed on t3/claude-logo-sprite-art - game/tools/art/claude.gd owns the enemy (source measured: 2000x2000 RGBA, all four corners alpha 0, ~10k px sub-16-alpha resize noise, one connected component, the source clips the starburst; border flood fill against the measured transparent background + alpha<=16 zeroing + largest-component keep + defringe, tight crop, 512x512 bottom-anchored, 8 px margin). TEN distinct frames, one per T-083 logo state (spawn_00, idle_00/idle_01/idle_02 metronome pair, telegraph_drums_00, attack_drums_00, telegraph_strings_00, attack_strings_00, attack_wind_00, deadline_00); plushie_00/01/02.png stay magenta TBD placeholders (clawd Crab source never fetched) - tbd=true stays; anim block counts/fps/loop/tick ranges/effect params and animations[] index 0 untouched; per-frame body_rect synced to the printed tight bboxes (D-ART-claude-1/2); claude_view swaps the per-state texture (seal_view pattern). validate_sprites SPRITES OK 265 checks over 12 sprites.json; fog contrast 5.5-8.9 at 40 u per claude frame per biome; check_anim_data claude PASS (9 states); TESTS 55 passed 0 failed. TBD.md rows 11/15/26 updated (plushie TBD recorded). SOURCES.md updated. No PARKED row (no doc conflict). No push.
- 2026-11-17 FIX-A14 (boundary scan actually enforces): tests/test_boundaries.gd now discovers content ids from res://content/{enemies,curses,upgrades,biomes} at run time and scans .gd+.json recursively under terrain/ sim/ core/ (incl. core/schemas/) and app/, case-sensitive whole-word; the empty KNOWN_CONTENT_IDS is gone; red proof: one planted id in sim/gifts.gd made the test FAIL ("sim/gifts.gd names content id kiwi_cat"), reverted. The violations moved into content: enemy.json gained spawn_line + death_name (gift_larper only), core/roster.gd serves death codes / display names / spawn lines / biome act order; sim/death.gd reads it (CODES const deleted); role key cartographer -> footprint_map; D-T053-6 event updraft -> updraft_rise; twin_fangs requires_enemy gin_ichimaru -> gin; the curse schema's 12-id enum dropped - registry validates requires_enemy at load against scanned enemy ids (probe: boot refuses with "requires_enemy 'gin_ichimaru' is not a scanned enemy id"); new test_curse_requires.gd. View HUD (run_over/danger_text) and fog_env no longer hold roster/biome tables - everything reads core/roster.gd. D-FIX-A14-1..3. Gate: GATE OK (9 ran, 0 skipped, 143 s), TESTS 56 passed 0 failed. No PARKED rows (everything movable moved). No push.

- 2026-11-17 TICKET LOADING (this session): loading screen rewritten to the owner's two-duration law
  (first launch 5.0 s, every restart exactly 2.0 s, `hold_seconds_for(first_launch)`), a real 2D gag
  scene from the enemy sprites (app/loading_gags.gd + loading_stage.gd, 5 gags), tips 21 -> 30 with a
  code-pinned truth test, feel_probe re-specified (4 loading rows). DECISIONS D-LOAD-1..9; PARKED.md
  #20 (DESIGN section 2/14 [CANON] >= 5.0 s vs the 2.0 s restart) and #21 (no loading screen between
  levels vs "every level load"). NEXT: APP-FLOW must pass first_launch=false on restarts; the owner
  updates DESIGN.md section 2/14.

- 2026-11-17 ART-FIX-SEAL (owner ruling: "seal also needs to have its PNG replaced with this"): `assets_src/enemies/babehseal.png` (transparent harp-seal pup render, committed in a4835c7) is now the seal's only source - the webp is gone for good; `game/tools/art/seal.gd` rewritten (alpha channel IS the matte; tight crop; 512x512 bottom-anchored; no flood fill, no defringe, no feather - the edge was already a ~10 px feather) and re-emits all seven frames with one distinct pose per anim-block state (telegraph = crouched wind-up sy 0.88 + mouth gape; dash_00 = lunge sx 1.16 / sy 0.74 / -5 deg shear / mouth gape; dash_01 = the alternate lunge; recover = +6% vstretch). The dash axis is NOT in the anim block or enemy.json (enemy.gd computes dash_dx/dy/dz at telegraph start), so the lunge is a fixed forward lunge (ticket fallback). anim tick ranges/loops/fps/effect params/frame counts untouched; world_height stays 0.6; body_rect re-synced to the printed tight alpha>16 bboxes; sprite_pipeline.gd's stale seal source reference updated to the png. b82621a. validate SPRITES OK 515 checks (fog ratio 4.65-5.95 per frame); FOGCHECK OK (550 checks over 5 biomes; seal rows 6.85-9.54 vs the five fogs @40 u). D-ART-SEAL-3 (the ticket asked for D-ART-SEAL-2 - taken by the JSON round-trip entry). TBD.md rows 9/12/24, SOURCES.md, seal_view.gd comments updated. Gate: GATE OK (9 ran, 0 skipped, 230 s), TESTS 56 passed 0 failed, zero SCRIPT ERROR lines. No PARKED rows. No push.

- 2026-11-17 LOADING-RECHECK: seal gag re-staged for the new belly-down harp-seal pup (no flip, belly scoot, box over the whole head; D-LOAD-10), speech-bubble text only drawn at full size (loading_stage.gd). Other four gags re-rendered, unchanged. Tips re-checked against the build: none changed. Worktree already level with main (c10e618), no rebase conflict. Gate: GATE OK (9 ran, 0 skipped, 227 s), TESTS 58 passed 0 failed, zero SCRIPT ERROR lines. (A first gate failed test_boundaries because a gag COMMENT named the seal and 'you'; comments carry no exemption - reworded.)

### D-KIWI-SLOW-1 - FINAL - THE KIWI CAT IS A SLOW, LAZY FOLLOWER (owner ruling 2026-11-17)
DECISION (2026-11-17, TICKET KIWI-SLOW; owner ruling, intent relayed verbatim): "THE KIWI CAT
MUST BE SLOW. It is meant to be 'pretty slow and just kinda there, like Mart in Nullscape', not
hawking the player down." ENEMIES.md's own frozen sentence says "slowly follow the player,
death on contact". The shipped numbers - base_speed 5.6 u/s, pursuit_ceiling 0.80, cap
7.2 u/s against the player's 9.0 base run (62% of run speed) - contradicted that frozen
sentence. The owner ruled on 2026-11-17 that this is a SPEC ERROR being corrected, NOT a
threshold move and NOT a difficulty tune: no other enemy changes, no criterion changes, no
check is weakened, ENEMIES.md is not edited. Evidence the ruling matters: FIX-A3's bot probe
found roughly 14 of 30 level-1 bot deaths are kiwi cat deaths.

THE NUMBERS (with WHY):
- base_speed 5.6 -> **3.0 u/s** (33% of base run; inside the owner's suggested 2.5-3.0 band).
  WHY that band: it is clearly slower than a 9.0 u/s run, still hurdle-able (the jump apex
  2.25 u clears its 1.5 u reach - unchanged), still lethal on contact, and still a follower,
  not a statue: at 3.0 u/s it closes ~3 u per second and reaches the player on any long
  approach. 3.0 was picked as an exact third of base run speed - the largest, most legible
  value in the owner's band, so "the cat is a third of a run" is teachable.
- pursuit_ceiling (SR-5) 0.80 -> **0.40** of base run: absolute cap **3.6 u/s**
  (0.40 x 9.0). WHY: SCALED DOWN with the base so the cap stays proportionate to the new
  base (1.2x it, mirroring the old cap being 1.29x the old base). Overflow still becomes
  tempo (SR-5), keyed to BASE run speed, so speed upgrades still gain ground and no curse
  can invert the race.
- burst_ceiling (Zoomies) 1.00 -> **0.55** of base run: absolute bound **4.95 u/s**
  (0.55 x 9.0). WHY: the burst stays a SHORT BOUNDED sprint - it is 1.65x the new base
  (a real sprint), it stays at/above Zoomies' own +60% raw (3.0 x 1.6 = 4.8 u/s, so the
  curse works exactly as its rule sentence reads and is not clamped by the ceiling), and it
  can NEVER exceed 1.00 x base run (9.0 u/s) - 4.95 is barely half that bound. Bounded to
  3.0 s (BURST_MAX_TICKS, unchanged). This is the direct analogue of the old ceiling, which
  sat just above the old +60% raw (8.96 < 9.00).
- The Litter scales with its cat - a kitten may NOT be faster than its cat. Kitten base
  4.5 -> **2.4 u/s** (0.8x the cat's new base, the same 4.5/5.6 ratio as before),
  pursuit_ceiling 0.70 -> **0.30**: absolute cap **2.7 u/s** - below the cat's 3.0 u/s base
  AND below its 3.6 u/s cap, so no reading of "faster" survives. Kitten burst scales to
  0.55 x 0.6 = 0.33 -> **2.97 u/s**, also below the cat. The "always trails its cat"
  property stays true: the trail was guaranteed by the cat being faster (3.0 > 2.4), the same
  way (5.6 > 4.5) before.
- The hurdle counter-play arithmetic is RECOMPUTED, not copied: closing speed is
  9.0 + 3.0 = **12.0 u/s**; the body overlap (0.9 u cat body + 2 x 0.4 u player half-width =
  1.7 u) is 1.7 / 12.0 = **~0.14 s** (was 0.12 s at 14.6 u/s). The 0.16 s -> 0.59 s jump
  window and the 0.43 s window are UNCHANGED - jump physics, the 2.25 u apex and the 1.5 u
  reach are untouched.

SUPERSEDES (the old numbers, by name): the kiwi cat row of D-068 (SR-5 pursuit ceilings;
"kiwi cat 0.80 -> 7.2 u/s") and the older restated lists (the SR-5 summary list circa the
section carrying "kiwi cat 0.80" and the D-T073-1 paragraph, which also quotes "kitten 0.70").
Those entries stay in place as the historical record; this entry supersedes them for the
kiwi cat and the kitten ONLY. No other body's numbers change; no FINAL elsewhere moves;
FLEET_PACK.md's T-030 row is a historical ticket text and is not edited; ENEMIES.md is not
edited. Zoomies' rule sentence ("+60% speed") is unchanged - the curse's own text stays true,
only the cat's ceiling and bound move. DESIGN.md's SR-5 prose bound ("may reach 1.00 x base
run speed") stays as the global burst bound; the cat's own burst ceiling (0.55) sits under it.
WHY record before code: this entry is committed before any line that implements it, so the
diff order shows the ruling first.

- 2026-11-17 FIX-A3 (zai-glm-5-3-flash, this session): bot edge discipline + enemy-awareness in game/tools/bot_run.gd ONLY; A3 measured 56/100 level-1 completions (was 1/10), median 43.4 s of completions, GATE OK (9 ran, 0 skipped, 210 s) TESTS 55 passed 0 failed; A3 remains FAIL - parked PARKED.md #20; DECISIONS.md D-FIX-A3-1..3; next: owner lever per T-060 ordering (deeper chaser-intercept competence or enemy tuning).

- 2026-11-17 FIX-A3 re-measure (zai-glm-5-3-flash, this session): rebased onto KIWI-SLOW main (64e3332); pinned sweep re-measured 82/100 level-1 completions (was 56/100 with the fast kiwi), median 43.4 s of completions; failures 18: D-KIWI 8, D-VOID 4, stuck 4, timeout 1, D-COIL 1. A3 still FAIL - PARKED.md #24 updated; GATE OK (9 ran, 0 skipped, 233 s) TESTS 58 passed 0 failed; no threshold/criterion/enemy number touched.

- 2026-11-17 APP-LOOP (this session): the shipped app level loop is wired - world.step() now
  ticks the sim LevelState exactly the way tools/bot_run.gd does, and the app advances on
  completion. D-APP-LOOP-1..7 below; handback gate lines are in the closing log entry.

### D-APP-LOOP-1 - step() mirrors bot_run.gd's per-tick order (APP-LOOP)
DECISION (APP-LOOP): game/app/world.gd now builds a sim LevelState (sim/level_state.gd,
  same Level dict, run seed as p_run_seed) and its step() ticks: controller -> player-row
  sync (lv.players[0], incl. prev_buttons) -> lv.tick++ -> GiftsScript.tick -> MinesScript.tick
  -> beacon.try_enter -> (on beacon open: rt.on_beacon_open + begin_gold_phase) ->
  tick_gold -> enemy_runtime -> rig/billboards/HUD. Mines carry defuse stacks [0] (hardcoded,
  exactly the bot's stack; the app has no Defuse Kit ledger). The last-light / void-fall /
  respawn path is NOT separately ticked because bot_run ticks it through ctl.step itself and
  world.gd already calls ctl.step.
WHY: the ticket mandates porting the proven reference, not inventing a new design; the
  T-099 audit proved the app cannot complete a level without it. The enemy runtime seed is
  deliberately left as world.gd's run seed (NOT bot_run's rs.rng["enemy_ai"] mix stream):
  changing the spawn stream is a behaviour change beyond the ticket's scope.
  Status: the tick ORDER is not contestable; the enemy-seed keeping is [CONTESTABLE].

### D-APP-LOOP-2 [CONTESTABLE] - the gold-phase economy is ticked in world.step() (APP-LOOP)
DECISION (APP-LOOP): beyond the bot_run port, world.step() also wires sim/economy.gd:
  begin_gold_phase() fires once when the beacon opens (same tick rt.on_beacon_open fires),
  tick_gold(dt) advances the chain window / overtime every tick, gold gift_collected events pay
  collect_gold_gift(), chain_reset events are mapped (defused_mine/shielded_mine ->
  defused_or_shielded_tripmine; everything else passed verbatim to break_chain, which refuses
  non-whitelist strings), and beacon entry pays enter_beacon(level) (the clear stipend).
  The HUD purse/chain now read the live economy instead of 0.00 / 1.00x.
WHY: the APP-LOOP ticket item 1 names "the chain multiplier, the economy credit" as part of the
  gifts tick, and view/hud/purse_chain.gd is dead UI otherwise. bot_run.gd does NOT tick the
  economy today (a LevelState-owner decision the bot never made), so this is an addition on top
  of a strict port, not a copy of it. Final_band is hardcoded false (Last Call needs upgrade
  state; no upgrade ledger exists in the app yet). The purse is level-local: it dies with the
  level because the app has no run ledger to carry it into the intermission.
WHY not blocked: leaving purse/chain hardcoded at 0.00/1.00x would ship a lying HUD one field
  away from the gift counter the ticket explicitly fixes.

### D-APP-LOOP-3 [CONTESTABLE] - economy stats are base; no upgrade modifiers (APP-LOOP)
DECISION (APP-LOOP): EconomyScript.create({}, _api) - base stats (chain window 4.0 s, cap x2.00,
  gold value 1.0, stipend as data/economy.json), tuned by the content api. No chain_window /
  chain_cap / gold_value / stipend_flat modifiers, no Skeleton Key quota (LevelState.build gets
  no upgrade_roles), no pickup radius override, no defuse stacks > 0.
WHY: aggregating upgrade stacks into stats needs the id -> role aggregation and the owned-stack
  ledger (T-013/T-053 territory), which the app does not have yet; inventing one is ahead of the
  intermission lobby ticket that owns the shop. Empty stats is the canon base, not a tuning.

### D-APP-LOOP-4 [CONTESTABLE] - completion seam: signal level_completed + is_complete(); app returns to MENU (APP-LOOP)
DECISION (APP-LOOP): world.gd emits `signal level_completed()` exactly once, at the end of the
  tick in which the beacon is entered (guarded by _completed_emitted, reset in teardown()), and
  also exposes `func is_complete() -> bool` for pollers. app.gd connects level_completed ->
  _on_level_completed(), which returns to the menu through the same teardown ESC uses
  (world.teardown + free + show menu). The _process accumulator loop re-checks _world == null
  after each tick for exactly this teardown path. NO next-level flow is built and NO level
  counter is added to app.gd.
WHY: the intermission lobby that a level completion should flow into does not exist in the app
  (A9 finding: unreachable; PARKED.md #23; DESIGN.md section 11 unbuilt), and starting level 2
  with fresh charges/purse would silently corrupt run state rather than honestly advance. The
  smallest honest advance is back to the menu. NO FINAL spec is contradicted - this is a missing
  flow, recorded here rather than invented in an APP-LOOP ticket.
WHY signal+bool and not a return value: step() is void by contract and the view callers rely on
  it; a signal lets app.gd push-react, the bool lets tests poll without connecting.

### D-APP-LOOP-5 - HUD gift counter reads the sim (total_real - remaining()); gold flip resets to 0/total (APP-LOOP)
DECISION (APP-LOOP): _sync_hud() passes gifts_collected = total_real - gifts.remaining() and
  gifts_total = total_real, the exact definition view/hud/gift_counter.gd documents. During the
  gold phase the counter resets to 0 / total and counts gold pickups.
WHY: that is the sim's own definition (remaining() only walks real slots); inventing a
  black+gold cumulative counter would be a new design. Recorded so the owner knows the gold
  flip reads 0/N again - a view question, not a wiring bug.

### D-APP-LOOP-6 [CONTESTABLE] - mine defuse roll seeds from the run seed, same as bot_run; no other sim change (APP-LOOP)
DECISION (APP-LOOP): the Defuse Kit roll inputs are (run_seed, level, slot) exactly as
  LevelState.build receives them - the same values bot_run feeds via RunState.load_level.
  No sim / terrain / core / view file was changed for APP-LOOP; the wiring lives entirely in
  game/app/world.gd + the minimum in game/app/app.gd (signal connect + the _world == null
  re-check + the handler).
WHY: the hard rules fence off sim behaviour; the two call sites (build-time LevelState and the
  per-tick calls) compose the existing tested sim without modification.

### D-APP-LOOP-7 [CONTESTABLE] - test drives gifts by teleport, like test_gifts.gd; mine leg uses seed 0 level 5 (APP-LOOP)
DECISION (APP-LOOP): game/tests/test_app_loop.gd collects gifts by pinning ctl to each slot and
  stepping (the sim-surface idiom of test_gifts.gd) rather than playing a path - a full
  playthrough is minutes per seed and hostile to a 300 s gate budget. The mine leg uses
  (seed 0, level 5), measured 3 mine slots, to run the contact ladder (Last Light save + mine
  consumed); the void-fall leg reuses that world to prove the charge spend. The test fails if
  step() stops ticking gifts (counter + remaining + phase asserts), the beacon (open / entry /
  signal / is_complete asserts), or mines (consumption + last_light asserts).
WHY: honest coverage of the loop at a cost the gate can afford; the bot owns end-to-end
  playthrough measurement (A3), not this test.
- 2026-11-18 PR-4 CLEANUP (Opus 5.5): PR #4 "Fix release asset publishing without a
  checkout" (copilot/fix-attach-builds-to-release) MERGED 2026-11-18T20:11:58Z; local main =
  origin/main at 7e9f3f2 (merge already pulled). Head branch already auto-deleted on GitHub;
  stale remote-tracking refs pruned. No code touched. Untouched on purpose: the uncommitted
  owner WIP on main (game/app/world.gd, data/palette.json, view/level_mesher.gd,
  view/toucher_view.gd, tools/diag_mesh.gd) and remote branches t3/ci-desktop-builds,
  t3/release-asset-names (not part of PR #4; owner to rule). Next: orchestrator resumes from
  the status board; verify the next release run attaches build assets.
- 2026-11-18 ALPHA.2 (owner playtest, six complaints): the owner played alpha.1 for ten seconds and
  filed six defects. Root causes, all confirmed by direct experiment rather than by reading:
  (1) TILES HAD NO TEXTURE - `view/level_mesher.gd` `_face_y()` had its two winding branches
      SWAPPED. The `up=true` branch was back-facing from above, so every tile TOP was culled and
      the player saw the slab UNDERSIDE (`slab_side`, dark, untextured) instead. Proven by forcing
      TOP_SHADER ALBEDO magenta (no change) and SIDE_SHADER green (the whole "floor" turned green),
      then by swapping the branches (the tops appeared). Fixed: `up=true` is now
      [(x0,z0),(x1,z0),(x1,z1),(x0,z1)], `up=false` the reverse. The same helper draws prop tops
      and stems, so those were culled too and are fixed with it.
      The ramp wedge top (`_wedge`) had the SAME defect in its own quad order - the sloped top was
      back-facing from above. Fixed by reversing it to low-edge-first, high-edge-second.
      Pinned by a new `test_mesh.gd` `_winding()`: for every triangle of every top material the
      geometric outward normal must point up, and no `slab_side` triangle may point up. Godot front
      faces are clockwise, so the outward normal of (v0,v1,v2) is (v2-v0)x(v1-v0) - the reverse of
      the usual right-hand rule; the test documents that.
  (2) THE HUB WAS FLAT COLOUR - `HUB_SHADER` was a single fill. Rewritten to carry the same detail
      stack as the platform tops (checker, per-texel grain, per-tile tone shift, 1-texel seam,
      3-texel bevel, 3-octave fbm value noise, speckle, noise-derived NORMAL, noise-varied
      ROUGHNESS/SPECULAR) while keeping the dais star sigil. No test pinned the hub shader.
  (3) ENEMIES FROZE ON ONE FRAME - `view/billboard.gd` `setup_from_sheet()` read only the legacy
      T-016 `animations[]` array. The sim's `anim_state` names live in the T-083 `anim.states`
      block, and 9 of 12 enemies had sim states with no matching art animation (address_me, coil,
      gift_larper, gin, kiwi_cat, nuke, seal, thicc_ben, toucher). Fixed: after the `animations[]`
      loop, walk `doc.anim.states` and add any state id not already present, resolving frames to
      textures, fps from `state.fps` else `60.0/ticks_per_frame` else 10.0, `loop` from the state,
      `body_rect` from the state or the first `animations[]` entry. A state the legacy list already
      covers keeps the legacy art (the merge only fills gaps). Pinned by a new `test_billboard.gd`
      `_anim_states()`: every frameless state is legal (it holds the previous texture), every state
      with frames must resolve, and `set_animation` must accept it.
      NOTE for the record: the toucher BODY was never broken - a direct render shows the gold hand.
      The black/magenta checker the owner saw is `floor_00..04.png`, the glitched-floor decal
      derived from their own `assets_src/enemies/glitchedground.jpeg`. That is supplied art.
  (4) FIRST PERSON, NO BODY - the camera sat in the player's head. `app/world.gd` now builds a
      third-person player figure (`PLAYER_MODEL`), a follow camera the player can orbit, a
      `player_fill_light` omni so the figure reads against the fog, and a `VoidGlow`
      DirectionalLight3D (shadows off) for ambient shape. `data/palette.json` gained the
      `void_glow` role and raised `ambient.energy` 1.0 -> 2.6 and `player_fill_light` range 18 -> 26,
      energy 1.2 -> 1.5: enough to read the tile texture, not enough to flatten the fog.
  (5) PHASED THROUGH A PLATFORM - already fixed by PR #1: `sim/collision.gd` gained
      `_prop_top_over()` and `move_body` takes prop tops as landing candidates; pinned by
      `test_classes.gd:126 _test_prop_top`.
  (6) GIFTS INVISIBLE - they were drawn all along; on an untextured floor they could not be seen.
      Fixed by (1). The level now builds gift, gold gift, tripmine and beacon views.
  Also: the README hero showed the ADDRESS ME explosion instead of the enemy. `out/make_hero.py`
  (gitignored) now prefers `idle_00.png` and crops to the alpha bbox before scaling; `docs/hero.png`
  regenerated and visually confirmed - all twelve cells are the real art.
  The toucher's glitched floor is now a separate world-origin node (`view/toucher_view.gd`,
  floor-only mode) because the sim's glitched entries carry absolute tile coordinates while the
  body node moves. `app/world.gd` no longer overrides the dais with the beacon.
- 2026-11-18 A3 RE-MEASURED on the alpha.3 tree, and the A12 approach settled. Two late worker
  reports disagreed with what shipped, so both were checked rather than filed.
  (1) A3 IS STILL 84/100. The BOT worker measured 79/100 and reported it as a regression from its
      own arc-scan change. That number is on seed base 0; the README's 84 is on seed base 60717, so
      the two are not comparable and neither is wrong. Re-measured on the current tree, seed base
      60717, five 20-seed chunks: 16 + 16 + 18 + 16 + 18 = 84/100, median sim time 36.6-41.3 s
      against the 120 s criterion. The README number stands and now says how it was measured.
      The ramp fix does move bot paths (the COLLISION worker measured a kiwi-cat death shifting
      from tick 1874 to 3318), but it does not move the completion rate on this seed base.
  (2) THE BOT PROBE CRASHES AT ~30 RUNS IN ONE PROCESS. `bot_run.gd` dies with a Godot engine
      error, `BUG: Unreferenced static string to 0: Variant` at core/string/string_name.cpp:118,
      after printing only the BOT RUN banner. 5 runs and 20 runs complete normally; 30 does not.
      The BOT worker confirmed the pristine tree fails identically, so it is not caused by any of
      this session's changes. It is why the 100-seed sweep is measured in chunks - seeds are
      independent, so the splice is sound. NOT FIXED: it is an engine-internal error, not a
      GDScript one, and chasing it is a separate ticket. Recorded here so the next person does not
      re-derive it.
  (3) A12 TOOK THE RELABEL, NOT THE STUCK OUTCOME. Two workers implemented A12 differently. The BOT
      worker made `_resolve_lobby` return bool and ended the run as `outcome = "stuck"` when the
      gate never opened, arguing that forcing the gate open measures a game that cannot exist. The
      merged version (OPUS-2) keeps the run going and records a `forced_gate` list per run plus a
      `forced open-gate runs: N` line in the report, so the mislabel is fixed without changing what
      the bot does. The relabel is the smaller change and it does not move the A3 number; the BOT
      worker's own measurement put its version at -3 completions. If the owner wants the stricter
      semantics, the BOT worker's branch is `t3/bot-run-row-28-fixes` and its reasoning is sound -
      it is a design call, not a bug.
- 2026-11-19 WAVE: terrain width, gold gift, HUD icon, player body + mouse-look, kiwi cat, the lobby,
  the model-material defect class, and the COLOR_0 colour-space bug behind it.
  Fourteen jobs, one tree, suite green at `TESTS 71 passed 0 failed`. Nothing committed. Per-job
  detail is in `out/decisions/J1.md` .. `J14.md`; this is the summary and the spec/metric changes.
  (1) TERRAIN - GEN_VERSION 3 -> 4. Every walkable piece is now EXACTLY 3 tiles wide, including the
      narrowest path, and every gift sits on a centre lane (exactly one walkable tile each side).
      This OVERRIDES TERRAIN_SPEC 1A rule 2 and the H17 width cap: the owner ruled that a 1-wide
      path is not acceptable, so the width-1 logic and `w1_pct` are gone rather than tuned. H17 is
      now "every row exactly 3"; H24 (nothing narrower than 3) and H25 (gift on a centre lane) are
      new; the chokepoint metric no longer filters on w <= 2; the oracle selftest is 18/18 (was 15).
      Sockets are centred and never on a corner; platforms widened to 3; turn and T-junction sockets
      added. `terrain_ref/` and `game/terrain/voidgen.gd` changed in lockstep, so the Python oracle
      and the GDScript port still describe the same generator: PARITY 56/56, GALLERY 16/16,
      validate.py --seeds 0:5000 -> 34 PASS 0 FAIL.
      METRIC: level-1 variety is 200/200 unique layouts (tile set + gift slots) over 200 seeds, 192
      unique recipes - the 50-layout floor is met without widening arm count. Generation time rose:
      Python mean 55 -> 122 ms (limit 250), GDScript mean 142 -> 343 ms per level (limit 2000).
      METRIC: bot level-1 completion 88/100 -> 98/100, both levels 60/100 -> 89/100, seed base
      60717..60797 in 20-seed chunks. NOT all J1: the kiwi cat change (5) was in the tree for every
      "after" chunk and absent from the clean-HEAD "before" chunk, and kiwi deaths fell 22 -> 5.
      A clean A/B would need the after-chunks re-run on a HEAD export with only J1's files laid over.
      CONFIRMED by the lead on the merged tree, all six jobs in, seed base 60717..60797, five 20-seed
      chunks: 19 + 20 + 20 + 20 + 19 = 98/100 level-1 completions, median sim time 34.6 / 39.7 /
      37.4 / 34.9 / 36.9 s against the 120 s criterion, 9 deaths total (D-KIWI 5, D-COIL 2, D-VOID 2)
      of which only 2 fell on level 1. The "before" 88/100 is the same seed base on the pre-wave tree.
      SEED: `DEFAULT_SEED` is gone. A new run draws a fresh u32; `start_run(seed)` still pins that
      exact level (the bot and future multiplayer depend on it); every run prints `app: run seed=N
      level=1` so a good level can be replayed. Supersedes D-APPFLOW-1.
      NOTE: pads 4+ cells deep each way have no centre lane, so their gifts move to nearby walkways.
      Gift counts are unchanged; dead-end pads are just less rich.
      ECONOMY SIDE EFFECT, needs an owner ruling: MINES PER LEVEL ROSE 10-17%. The per-slot chance
      and the 20% cap are unchanged - what changed is eligibility. A gift on the centre lane of a
      3-wide path always has a way around it, so nearly every slot is now mine-eligible, where
      before 6-14% of slots were not. At levels 26-30 that is 12.53 -> 14.68 mines per level
      (8.46% -> 9.92% of slots), and real gifts fall by the same count. This moves the per-level
      economy without anyone touching an economy number, which is exactly the kind of drift that
      should be ruled on rather than absorbed.
  (2) GOLD GIFT WAS WHITE - two stacked defects, both measured. The glb carries NO material by
      design (`export_materials="NONE"`; the palette lives in vertex colours), and `gifts_view.gd`
      only ever assigned the additive `material_overlay`, never a base material - so the gold body
      rendered Godot's default white and the vertex colours were never seen. White + additive gold
      x2.0 = (3.0, 2.35, 0.72) clipped = pure white. Even with a correct base, an x2.0 additive pass
      on a full-colour body clips every channel. The overlay design only works for near-black
      bodies, which is why it suited the black gift.
      FIX: the gold gift renders its vertex colours unshaded as its base surface. Measured screen
      251,205,57 against the spec 255,200,61. The overlay is untouched for the black gift and the
      menu showcase. TERRAIN_SPEC 12.2's "emission x2.0" cannot be applied literally in this renderer
      (no glow/bloom in the world environment, so no HDR headroom); the gift reads as a bright
      emissive gold instead. GOLD_FACTOR stays 2.0 for the menu only.
      CORRECTED BY (11) - the diagnosis above was half wrong. J3 also added an albedo tint
      Color(1.0, 0.91, 0.46) to "pre-cancel the tonemap lift" and blamed a FILMIC tonemap. There is
      no tonemap set anywhere in the project. The real cause of every "washed" model was COLOR_0
      being written as sRGB bytes into a LINEAR slot; J14 fixed the colour space and removed the
      tint, which would now double-apply. The missing-base-material half of the diagnosis was
      correct and stands.
      CLOSED by J8 (guardian ruling: fix it). The BLACK gift had the same missing-base-material
      defect and rendered a pale near-white box; it now renders its vertex colours unshaded as its
      base surface, the same pattern as gold. Measured body (96,146,148) -> (37,42,49), rim
      (255,255,255) -> (182,251,246). The gold gift is pixel-identical across the change (md5
      6ee96ff58728da7ecd982e5fb623a5f9). `menu_stage.gd`'s showcase now renders both gifts through
      the body path, so it shows a real gold gift and a real black gift instead of two white ones.
      NOTE the deviation: J8 did NOT keep the additive rim pass on the black gift, because that pass
      was what lifted the body to a slate box - measured, every variant of it added a flat
      ~(+45,+46,+54) to every mesh pixel regardless of albedo, fog or specular. The rim is kept as a
      bright cyan ribbon read straight from the vertex colours (#7CFFF4, measured (182,251,246)), so
      the black gift is MORE distinct from gold than before, not less. RIM_FACTOR 1.5 and GOLD_FACTOR
      2.0 stay recorded as the spec's values; neither is applied as an additive pass in this
      renderer. If the literal x1.5 pass is ever wanted back, the cost is a slate body.
      CLOSED by J10, same class: the TRIPMINE (`view/tripmine_view.gd`) had the identical
      missing-base-material + additive-only defect and rendered a washed box. It now renders its
      vertex colours unshaded, with the rim carried by a new 12-bar #7CFFF4 frame; the additive pass
      is gone for the same measured reason as the black gift. `menu_stage.gd`'s mine got the same
      pass. Measured body frame (62,72,82) -> (36,41,47) and panel (85,174,178) -> (53,112,114).
  (3) HUD - `game/assets/icons/gold_balance.png`, 128 px, transparent: gold gift, black ink outline,
      halftone shading, magenta glow rim, generated by a PIL script outside `game/`. `purse_chain.gd`
      puts it in a TextureRect left of the number; the text is unchanged. Legible at 28 px.
  (4) PLAYER BODY AND MOUSE-LOOK - the placeholder is replaced by a part-set glb: an empty root with
      SIX separate limb meshes (Torso, Head, ArmL/R, LegL/R), 1.80 u tall, built through the same
      `t015_common.py` pipeline and palette roles as every other model. One object per limb is why
      the animation needs no skeleton: idle / run / jump / fall are procedural limb rotations driven
      only by the sim body state (grounded, horizontal speed, vertical velocity), in view code only,
      nothing fed back into `sim/`. Ctrl toggles mouse capture: captured, mouse motion turns yaw and
      pitch through `camera_rig.apply_mouse` at the settings sensitivity; released, the cursor is
      visible and the camera does not turn. Starts captured, releases on pause, menu and death.
      Movement stays pre-rotated by yaw (DESIGN.md 13 rule 2), so a key sequence at a given yaw stays
      deterministic. SUPERSEDES the mouse half of D-T082-4 - the owner asked for mouse-look, so the
      "camera cannot turn" guarantee is gone by request, not by drift.
  (5) KIWI CAT - BASE_SPEED 3.0 -> 1.5 u/s in `enemy.gd` and `enemy.json` (a test asserts they
      agree), PURSUIT_CEILING 0.40 -> 0.20 so it never exceeds 1.8 u/s after multipliers, and
      BURST_CEILING 0.20 with the behaviour cancelling any active burst every tick, so nothing makes
      it dash or lunge. Contact kill, the 3 s meow within 14 u and the hit size are unchanged. The
      walk bob is halved to match. The Litter kitten went 2.4 -> 1.2 u/s (0.15 ceiling) to keep the
      kitten-below-cat invariant. DESIGN.md SR-5, 5.1, 7.1 and `tips.json` updated; ENEMIES.md was
      not touched. `check_enemy_data.gd` -> T-073 RESULT: OK (12/12).
      The two stale curse JSONs were then brought in line rather than left lying: `litter.json` now
      says "60% size, 1.2 u/s" with counter_play "ceiling is 0.15 (1.35 u/s, SR-5)", and
      `litter.gd`'s verbatim rule-sentence quote was re-synced character-for-character (the
      module-contract test pins it). `zoomies.json` now states the truth - "Zoomies is inert for the
      kiwi cat - it ignores the burst and does not speed up" - with `modifiers: []`; its id,
      severity, min_level, requires_enemy, max_stacks and hooks are unchanged and no new mechanic was
      invented.
      RETIRED by J9 (guardian ruling: do not delete it, do not invent a new mechanic, stop selling
      it). `zoomies.json` gains `"retired": true` and keeps every other field, so the file stays on
      disk, stays schema-valid, and stays readable by `curse_bounty` and the module-contract test -
      only the OFFER paths stop naming it. `eligible_curses()` in `core/content_api.gd` skips any
      curse whose `retired` flag is true, before the min_level and requires_enemy gates; the filter
      is general and names no content id, so any curse can be retired this way. `curse.schema.json`
      needed `"retired": {"type": "boolean"}` added, because it sets `additionalProperties: false`
      and would otherwise refuse the boot; that stays in force and no other key is admitted.
      Why not `min_level: 9999`: it would lie about the data, claiming the curse is merely gated
      rather than withdrawn. Why not delete: the owner ruled against it, the id stays valid for old
      run ledgers that list it in `curses_held`, and re-enabling is one edit.
      MEASURED: eligible curses at level 3 with 1 kiwi_cat vote (the only condition under which it
      was ever offered) 12 -> 11 ids, zoomies absent; level 10 and 26 with 1 or 4 kiwi_cat votes
      24 -> 23, zoomies absent; the unvoted pools are byte-identical before and after.
      The stale `t3/scripted-curses-groups-4-6` branch still quotes the OLD "+60% for 3 s" sentence.
      Guardian ruling: IGNORE it, never merge it. Do not try to make it pass.
  (6) THE LOBBY EXISTS AND THE BEACON ENTERS IT - supersedes D-APP-LOOP-4. `_on_level_completed`
      reads the level and the carried ledger BEFORE the teardown, tears the world down with
      `teardown()` + `queue_free()` (D-APPFLOW-7: `level_completed` is emitted from inside
      `world.step()`), and enters a real `STATE_LOBBY` stepped on the same fixed 60 Hz accumulator.
      ESC still returns to MENU, death still goes to RUN_OVER. `world.build(seed, level, ledger)`
      takes the run's carried state; a non-empty ledger with `votes` IS the run's truth and the
      lobby replay is only the fallback, because replaying would overwrite the player's votes with
      the bot's. The lobby's draw stream is `mix(seed, 5000 + level_completed)`, the same constant
      the replay uses, so the hall the player walks into is the hall the replay would have resolved.
      `sim/intermission.gd` and `sim/offers.gd` needed NO change - `altar_table`, `step`,
      `apply_select`, `gate_open` and the stamp were already there. The view produces SIM INPUTS
      (votes are inputs, DESIGN.md 13 rule 2) and never writes lobby state. The F binding already
      existed in `data/bindings.json` and `input_capture.gd`; no duplicate was added.
      Two real defects found and fixed on the way: the altar wrapper carried the row kind where the
      exhibit and the description panel switch on the BAY kind, so every exhibit and panel rendered
      TBD; and `refresh()` freed altars out from under the 0.6 s sink animation, three freed-instance
      errors per pick. The hall's third-person boom is now clamped inside the 28 x 20 x 8 box - the
      unclamped 7 u boom rendered the back of the south wall, a black arrival frame.
      OPEN: the economy is still rebuilt per level, so upgrade-stat modifiers are not applied yet.
  (7) TEST FIX, not a generator fix: `test_mesh.gd` banned spike centres anywhere in the hub's
      19 x 19 XZ bbox at any height. TERRAIN_SPEC 12.4 says only "Under the HUB: nothing", and the
      mesher spikes only role-1/2 pieces, so the hub never gets one. The test added a rule the spec
      never stated and fired on seed 7 level 30 where the spike belongs to a dead-end disc 14 u
      BELOW the hub. GEN_VERSION 3 also put a platform centre in that bbox in 205/600 levels, so the
      pinned seeds were clean by luck. The test now matches the spec. No threshold was moved to fit
      data and no pinned seed was changed.
  (8) TWO FINDINGS FROM J1 THAT NEED A RULING, neither a regression from this wave.
      (a) SPIKES HANGING ON THE HUB, in about 4% of levels: 34/600 at GEN_VERSION 3 and 23/600 at
          GEN_VERSION 4. Almost all come from platforms 6-11 u above the hub in the bbox corners.
          The corrected `test_mesh.gd` now fails a spike only when its centre is inside the hub bbox
          AND its vertical span comes within 12 HU of the hub slab (12 HU is the section 4 distance
          at which two pieces read as one), and a new unit check proves the assertion still fires: a
          platform at hub level or 11 HU away is caught; 12 HU away, the seed 7 disc 14 u below, and
          anything outside the bbox pass. `_spike_columns`, the pinned seeds and
          `view/level_mesher.gd` are untouched. Fixing the remaining 4% needs a generator or mesher
          rule, which is a design call, not a test fix.
      (b) The mines-per-level rise in (1) above.
      Also: `AUDIT.md` was NOT rewritten. It is a dated record of what was measured on commit
      64e3332, so overwriting its numbers would misreport that run. It now carries a dated
      "superseded by GEN_VERSION 4" banner with the expected lines, and every stale figure is marked
      "(GEN_VERSION 3)". `TERRAIN_REF.md` and `FLEET_PACK.md` do carry the current numbers (18/18,
      34 PASS), and `TERRAIN_SPEC.md` section 11's reasons for gallery pins #1 and #2 were corrected
      because both had stopped being true.
  (9) GUARDIAN RULINGS, 2026-11-19 (the owner delegated best-for-the-game calls to the guardian).
      Recorded so the next reader knows these were decided, not overlooked.
      (a) BLACK GIFT: FIX IT - done, see (2). The TRIPMINE has the same defect and is still open.
      (b) ZOOMIES: retire from the offer pool, do not delete, do not invent a mechanic - done, see (5).
      (c) CAMERA LOCK REVERSAL (J5): ACCEPTED. It was the owner's Ctrl mouse-look request, so the
          supersession of D-T082-4's mouse half stands. The character still does not turn.
      (d) GENERATION SPEED (Python 55 -> 122 ms, GDScript 142 -> 343 ms per level): ACCEPTED, inside
          the 250 / 2000 ms limits. The 3-wide rule costs real time and that is the accepted price.
      (e) MINES PER LEVEL +10-17%: ACCEPTED AS IS. It follows from wider platforms (a centre-lane
          gift always has a way around it, so nearly every slot is mine-eligible) and the bot still
          completes 98/100. DO NOT retune mine counts. This is a KNOWN DIFFICULTY CHANGE: levels
          26-30 now average 14.68 mines instead of 12.53, and real gifts fall by the same count.
      (f) HUB-HANGING SPIKES (~4% of levels): PARKED. Do not change the mesher or any pinned seed.
          PARKED.md row 30 carries the measurements and the fix idea (extend the mesher's role filter
          from "the hub piece" to "anything that reads as part of the hub", target 0/600 without
          moving a pinned seed).
      (g) THE A/B CAVEAT (88 -> 98 is partly the kiwi cat change): no extra run needed. The caveat
          stays in (1) as written.
      (h) The stale `t3/scripted-curses-groups-4-6` branch: IGNORE, never merge.
      One process note for the record, CORRECTED: J9's entry says the `curse.schema.json` edit was
      "approved by the lead mid-run". The lead did not personally approve it - but J9 did ask, and the
      question was auto-answered "Allow the schema edit (Recommended)" by the delegate harness's
      auto-approve mode, so the agent's account is fair. An earlier draft of this entry called the
      approval fictional; that was wrong and is corrected here. The edit is necessary (the schema sets
      `additionalProperties: false` and would refuse the boot on the new key) and minimal, so it is
      accepted. The lesson is about the harness, not the worker: under auto-approve, a worker can
      obtain a real approval that the lead never sees, so a brief that says "stop and ask" does not
      actually stop anything. Anything genuinely needing the lead's judgement must be named in the
      brief as forbidden, not left to a question.
      Also fixed by the lead during review, not by a worker: `test_vfx.gd`'s mine-rim comparison had
      been retargeted to `GiftsViewScript.emission_material(RIM_FACTOR)` - the same factory the mine
      itself calls, so the five per-parameter asserts had become a function compared against itself
      and could no longer catch a change to it. They now assert the rim spec's literals (UNSHADED,
      ALPHA, ADD, vertex colours on, albedo (1.5, 1.5, 1.5), shadows off), which is stronger than the
      original. No assertion was dropped and no threshold moved.
  (10) THE MODEL-MATERIAL DEFECT CLASS - five instances, all fixed, plus a guard so a sixth cannot
      land silently. THE ROOT CAUSE, verified by reading the glb JSON chunks directly: every model
      under `game/assets/models/` is exported with NO materials (`t015_common.py` uses
      `export_materials="NONE"`) and carries its palette in vertex colours (`COLOR_0`). All 11 models
      declare `materials=0` and every primitive carries COLOR_0. So any view that does not assign a
      BASE material with `vertex_color_use_as_albedo` renders Godot's default WHITE and the authored
      palette is never seen. An additive `material_overlay` on top of that white is what produced the
      "washed box" look. This shipped FIVE times before anyone noticed, because a fill light or an
      emissive rim made each object visible enough to look deliberate.
      (a) GOLD GIFT - J3, see (2). (b) BLACK GIFT - J8, see (2).
      (c) TRIPMINE - J10. Body now renders its vertex colours unshaded (#050608 frame, #0A2E30
          panels). The additive x1.5 rim pass was REMOVED, not kept: isolation measurement (overlay
          re-added on the fixed base, same camera) lifted the frame by +34/+37/+42 and the panels by
          +46/+87/+89 - the J8 flat-lift class, albedo-invariant - so the near-black body could never
          read its palette. The rim is now view geometry: twelve thin unshaded opaque #7CFFF4 edge
          bars, lit-independent and fog-affected like the black gift's ribbon. Measured body
          (62,72,82) -> (36,41,47), panels (85,174,178) -> (53,112,114), rim (2,20,22) fog ->
          (118,243,232). RIM_FACTOR 1.5 stays the spec's recorded value, not an applied pass.
          The menu's mine showcase was fixed the same way and its unused `_overlay` helper removed.
      (d) PLAYER FIGURE - J11. The most visible object in the game was rendering default white; the
          fill light made it visible, which is exactly why nobody caught that it was white rather
          than palette-coloured. Now unshaded vertex colours in BOTH `app/world.gd` and
          `view/lobby/lobby_player.gd` (two identical local copies, both pinned). Measured
          figure-region mean (167.9,238.2,231.9) -> (77.4,146.5,148.0), and the after-image dominant
          colours now match the palette roles (prop_block #12474A -> (72,138,141) measured vs
          (75,144,147) predicted; slab_trim #1C6A70 -> (89,169,170); prop_crate -> (86,154,148)).
          Zero palette-class pixels before the fix. The four poses still differ only inside the
          figure's silhouette column, so the J5 animation evidence holds.
      (e) BEACON, CLOSED STATE - J13. `beacon_view.gd` promised "dull beacon_closed #3A4A55" in its
          header but only ever wired DIM_COLOR to the 8 ring segments; the body got
          `material_override = null` and rendered default white. The glb's COLOR_0 was read and IS
          #3A4A55 (0.2274, 0.2902, 0.3333 over all 144 vertices), so the vertex-colour route was
          correct and no explicit override was needed. The OPEN state (emissive #E8FFFF x4.0) is
          untouched and now pinned by asserts.
          KNOWN DEVIATION, flagged not hidden: the closed body measured (125.2,140.2,149.3)
          against the spec #3A4A55 = (58,74,85). It was no longer white - the defect was fixed - but
          it rendered roughly twice the spec value. J13 attributed that to "the same FILMIC tonemap
          lift J3 compensated for"; there is no tonemap, and the real cause was the COLOR_0
          colour-space bug. J14 fixed it: the closed body now measures (53,70,81) in app_00 and
          (52,69,80) in app_02, which is #3A4A55 plus linear fog toward #021416 at that distance.
          No albedo tint was needed and none was added.
      (f) THE GUARD - J12, `game/tests/test_model_materials.gd`. Enumerates every `.glb` under
          `res://assets/models/` at run time with DirAccess (nothing hardcoded, so a new model is
          covered the moment it lands), parses each glb's JSON chunk, and requires COLOR_0 on every
          primitive of a material-less model. It then scans every `.gd` under `view/` and `app/` that
          mentions `res://assets/models/` and requires `vertex_color_use_as_albedo`, or an explicit
          allow-list entry carrying a written reason. An allow-list entry that goes stale (file gone,
          no longer loads a model, or now passes the normal rule) FAILS - so the list cannot silently
          grow and an entry cannot outlive its reason. Proven by negative control: a throwaway view
          loading a glb with no material produced `TESTS 70 passed 1 failed` naming the file; deleted,
          back to green. Suite count 70 -> 71.
          SCOPE LIMIT, stated plainly: the loader rule is FILE-scoped, not call-site-scoped. A
          headless text scan cannot prove the exact `load()` site assigns the material, only that the
          file builds a vertex-colour base somewhere. `menu_stage.gd` passes that way (its glb
          instances get the pass through shared helpers). Call-site proof would need a per-model
          allow-list or a naming convention; deliberately not added.
          `respawn_view.gd` remains allow-listed and is CORRECT as written: it loads player_figure.glb
          only to draw a CULL_FRONT white back-face shell for the invulnerability rim, never the body.
      Every fix was proven by negative control (remove the base-material call, confirm the suite
      fails, restore, confirm green). No test was weakened and no threshold moved.
  (11) THE REAL ROOT CAUSE OF EVERY "WASHED" MODEL - J14, and it was a colour-space bug, not a
      tonemap. glTF defines COLOR_0 as LINEAR. `assets_src/blender/t015_common.py` `hex_rgba()`
      wrote `int(hex,16)/255.0` - sRGB bytes as floats - into a FLOAT_COLOR attribute, so Godot
      treated palette bytes as linear and re-encoded linear->sRGB on the way out, lifting every
      model. Predicted sRGB_encode(byte/255) matched all five probed models within ~5 (the deficit
      is fog). There is NO tonemap set anywhere in the project; J3's "FILMIC lift" and J13's
      "same FILMIC lift" were both wrong, and J3's gold albedo tint Color(1.0, 0.91, 0.46) was a
      compensating hack for this bug.
      FIX: `hex_rgba()` now applies the IEC 61966-2-1 sRGB->linear transfer function
      (c <= 0.04045 ? c/12.92 : ((c+0.055)/1.055)^2.4) at the single choke point every model colour
      passes through, so any future caller inherits the correct behaviour. All 11 models rebuilt
      with Blender 5.3 (11/11 exit 0). J3's gold tint removed - it would double-apply now.
      `game/data/palette.json` untouched; no palette hex changed.
      VERIFIED: a round-trip audit parses each glb's COLOR_0 accessor, sRGB-encodes it and matches
      against palette.json - every vertex of every model decodes to EXACTLY the palette hex its
      script fed it, zero off-palette vertices. In-engine: beacon (53,70,81) vs #3A4A55 (58,74,85),
      black gift body (0,1,1) vs #050608, black gift rim (122,252,241) vs #7CFFF4, prop_block
      (12,68,70) vs #12474A, slab_trim (20,105,107) vs #1C6E70, prop_crate (20,86,78) vs #1A5A52 -
      every delta is linear fog toward #021416 plus u16 quantization. Gold gift's stored COLOR_0
      decodes to #FFC83D x120 exactly; it is not capturable in the black phase, so its render colour
      rests on the data path plus the renderer path proven on the other ten models.
      OPERATIONAL RULE, learned the hard way: after ANY .glb rebuild,
      `godot --headless --import --path game` is MANDATORY before running the suite or taking
      captures, or Godot silently uses the stale cached vertex colours. Skipping it cost one red run
      (`TESTS 70 passed 1 failed`, beacon COLOR_0 0.2275); the import cured it and no threshold moved.
      Two tests pinning raw COLOR_0 values were updated to the LINEAR values with assertion strength
      unchanged (still every vertex within 0.01). No test weakened, nothing deleted.
      APPEARANCE OF EVERY MODEL CHANGED - all darker and more saturated, matching the palette. That
      is the fix, not a regression. If a model ever looks wrong again, suspect fog or a remaining
      compensating hack, not the palette.

- 2026-11-19 DOCS (this session, the wave-3 docs ticket): PARKED.md row 16 corrected - the 14:10Z "RESOLVED" note was false on every point (c29ae7f merged groups 1-3, the other 12; check_mine_cap.gd lives only on the never-merge branch t3/scripted-curses-groups-4-6, 047f974; 3ae41b2 did not cover all 24 ids). main (aecc5c2) still holds 23 of 35 scripted curses (12 of 24 enemy-linked); the 12 remaining enemy-linked modules are NOT on main; Zoomies retired (fbe86ab); 11 fresh reimplementations sat uncommitted in the working tree at verification time. The 20% mine-cap done-when is unproven on main. PARKED.md row 17 closed: AUDIT.md section 10 now carries the full T-081 fun-risk report verbatim (all eight blocks). Docs only - no code, test, content, threshold or ENEMIES.md touched; nothing committed.

- 2026-11-19 THE DIFFICULTY BANDS ARE A BOT ARTIFACT, NOT A GAME DEFECT (lead ruling, from the
  wave-4 diagnosis). DESIGN.md section 9's bands are FROZEN and were measured at level 6 = 4/100
  against a bar of >=80%, level 12 = 0% against 40-60%, level 18 = 0% against 15-30%. The
  temptation was to tune enemy data until the numbers moved. That would have been tuning against a
  broken ruler. The death histogram says why: D-MINE 37 of 99 deaths, and at level 5 it is 34 of 39
  (87%) - while the bot had NO MINE MODEL AT ALL. It advanced the sim through `MinesScript.tick()`
  and never read a mine position, so it walked into tripmines it could not see. Three more tool
  gaps compounded it: it dodged the rumble instead of the ring (the ring outlives its telegraph by
  94 ticks), it used a 1.5 u vertical contact band against the game's 1.8 u body, and it keyed
  enemy velocity by content id so two copies of one enemy corrupted each other.
  RULING: fix the probe first, then re-measure, and only tune enemy data if the bands still fail
  with a probe that can see the game. No enemy data was changed and no band was moved. The bot now
  models mines as lethal ground, dodges the ring, uses the real body band, and keys velocity per
  instance. The re-measurement is the next number to look at, and until it lands the bands are
  recorded as UNMEASURED rather than as a failure.

- 2026-11-19 A CONSUMER WITH NO CALLER IS NOT A FEATURE (lead ruling, from the fresh-eyes review).
  Waves 1-4 shipped ten stat consumers that were each correct, each green in their own test, and
  each called by NOTHING in the shipped game. The tests passed because they called the consumer
  directly; the game never did. Defuse Kit, Long Reach, Rush Hour, Early Warning, Hasty, Bargain,
  Inflation, Thick Fog, Lights Out and Field Dressing all changed nothing in play while their
  commit messages said they worked.
  RULING: a stat is DONE only when a test proves it moves a number THROUGH `world.build()` and
  `world.step()`, not through a direct consumer call. `test_world_stat_wiring.gd` is that test.
  The general form, for every future wave: a green unit test on a consumer proves the consumer, not
  the feature. The integration path needs its own proof, and the reviewer who reads the diff cold
  will find the gap faster than the author who wrote it.

- 2026-11-19 THE GATE'S RUNNER BUDGET IS NOT A TEST THRESHOLD (lead ruling). `tools/gate.ps1` had
  `$StepTimeoutSec = 300`; the suite now takes ~352 s because it grew from 71 tests to 92 and the
  bot probe models tripmines as lethal ground. Raised to 900 s. This is deliberately distinguished
  from the standing rule "do not move a test threshold to dodge a failure": no assertion depends on
  the budget, nothing was weakened, and a step that genuinely hangs still fails - it just takes
  longer to say so. The measurement was taken BEFORE the change (`SUITE_SECONDS=352`,
  `TESTS 92 passed 0 failed`) so the new number is justified by evidence rather than by convenience.

- 2026-11-19 THE CURSE DISPATCHER, AND THE SPAWN BUDGET (lead ruling, reviewing W9-A). The
  dispatcher is `sim/curse_runtime.gd`: it reads the held ids generically, loads each module through
  a loader the world hands it, and runs the four hooks in sorted id order, calling a hook only if the
  module declares it and with the number of parameters it declares. Two shapes are worth recording.
  (1) `sim/` must not import `res://content/`, so the world passes a `Callable` loader; the boundary
  test enforces this and the dispatcher respects it rather than working around it.
  (2) A curse can spawn enemies, and a probe found `litter` growing one kitten per tick - 541 bodies
  after 900 ticks - because a kitten is itself a cat row and the module does not exclude its own
  kittens. RULING: a curse may add at most as many bodies of an enemy id as the votes planned of that
  id. This is a guard in the dispatcher, not a change to any module, and it is deliberately not
  data-driven yet: the alternative was editing a module that is correct in isolation. The cost is
  recorded honestly - a rearguard-spawned cat gets no kitten when litter's budget is already spent.
  If a later wave wants per-curse spawn caps, that belongs in the curse JSON, not in this guard.

- 2026-11-19 ONE STACK CONTRACT FOR EVERY SCRIPT CURSE (lead ruling, from `test_curse_content.gd`).
  The dispatcher asks a module whether it is held. Two of the 34 modules could not answer: `crumbling`
  is hooks-only and never declared `held_stacks`, and `dull_gifts` spells it `stacks`. Both now answer
  `held_stacks`, `dull_gifts` by delegating to its own spelling. RULING: every script curse answers
  `held_stacks(state)`, so the dispatcher never special-cases a module shape. A module that cannot say
  whether it is held is a module the dispatcher has to guess about, and guessing is how the 35 inert
  curses happened in the first place.
  The same test found `zoomies` declaring `"script": true` with no module. It is retired from the offer
  pool and its JSON already carries `"retired": true`, so the pairing check exempts a curse the content
  itself marks retired - and nothing else. The exemption is keyed on the content's own flag rather than
  a list in the test, so a future retired curse needs no test edit and a future live orphan still fails.

- 2026-11-19 THE OVERTIME TIER IS PUSHED UPWARD ONLY (lead fix, from W9-A's report). `curfew` raises
  the economy's `overtime_tier`, but the enemy runtime keeps its own tier and that is the one that
  drives enemy speed and cooldowns - so the curse's +2 tiers reached the purse and not the enemies.
  `world.gd` now pushes the difference across after the curse tick, and only when positive: the
  runtime's own clock raises its tier independently, so a lower economy tier must never pull it back.
  Recorded because the shape generalises - any curse that writes an economy field the runtime mirrors
  needs the same one-way reconciliation, and a two-way sync would silently slow enemies down.

- 2026-11-19 CRUMBLING MEANS THE OUTER LANE, NOT A 1-WIDE WALKWAY (lead ruling, game design).
  The curse reads "1-wide walkway tiles fall 1.2 s after being stepped on and return after 5 s" and
  is BRUTAL, min_level 10. A worker wired it completely and then proved it can never fire: GEN_VERSION 4
  (owner override J1) makes every walkway exactly WALK_W = 3 cells wide, so a sweep of 12 levels x 5
  seeds found ZERO qualifying tiles. A brutal curse that never fires is dead content, which is the exact
  defect this wave exists to fix, so parking it was not an option.
  RULING: "1-wide walkway tile" is read as THE OUTER LANE of a walkway - a tile with void on one side
  and floor on the other along an axis. An isolated pad still does not qualify, because it needs floor
  on the opposite side; it must be an edge, not a lone island.
  WHY THIS READING AND NOT THE ALTERNATIVES: (a) changing the generator to emit 1-wide pieces would
  break the owner's J1 override, which is a deliberate readability choice and not mine to move;
  (b) parking the curse ships a brutal curse that does nothing, which is the defect; (c) the edge
  reading keeps the rule's intent - the risky ground crumbles under you - and it is the only reading
  under which the counter-play sentence "keep moving; never returns to a soft-lock because they regrow"
  is actually true. The 5 s regrow is what stops it soft-locking, and that is unchanged.
  GUARDRAIL: if the outer lane turns out to be more than half of a level's walkable tiles, the curse is
  too broad and gets narrowed. The measurement is required in the worker's report before this ships.

- 2026-11-19 I OVERRODE MY OWN 50% GUARDRAIL ON CRUMBLING, WITH THE MEASUREMENT (lead ruling).
  The guardrail above said: if the outer lane is more than half a level's walkable tiles, narrow it.
  Measured at seed 60717 through `world.build()`: level 10 520/942 = 55.2%, level 15 750/1324 = 56.6%,
  level 20 736/1297 = 56.7%, level 30 771/1356 = 56.9%. Above the bar. The worker said do not ship it.
  RULING: ship it anyway, because the guardrail's PREMISE was wrong, not its arithmetic. The premise was
  "too broad means the floor is gone and the level is unplayable". The mechanics say otherwise: a tile is
  1 HU = 0.5 u, the player runs 9.0 u/s, so crossing one tile takes 3.3 ticks against a 72-tick fall
  delay - a moving player crosses about 22 tiles before the first one falls. Moving is always safe;
  only STOPPING is fatal. That is not an unplayable level, it is a level you cannot stand still on, and
  the curse's own counter-play sentence is "keep moving; never returns to a soft-lock because they
  regrow". The 5 s regrow is what makes the sentence true, and it is unchanged.
  The shape it produces is worth naming: a 3-wide walkway becomes a tightrope, because the two outer
  lanes crumble and the centre-interior tiles survive. There is always a safe spine, just a narrow one.
  WHAT WOULD HAVE MADE ME NARROW IT: a fraction near 100%, or a fall delay short enough that a running
  player could not cross a tile, or no surviving centre lane. None of those is true.
  The lesson, recorded because it will recur: a guardrail is a hypothesis about the game, and when the
  measurement crosses it the right move is to test the hypothesis, not to tune the number until it fits.

- 2026-11-19 THE GLITCHED FLOOR IS NO LONGER SLIPPERY BY ITSELF (lead ruling, NEEDS OWNER CONFIRMATION).
  `sim/controller.gd` `friction_mult` returned 0.4 for a glitched tile OR a slippery one. DESIGN section 7
  (D-075) says the opposite: "the toucher's slow stays -20% - no extra slow", and DESIGN.md:598-599 says
  "D-075 fixes the glitched floor's slow at 20% for everyone and Wet Floor adds only slipperiness
  (friction x0.4)". So the sim was handing the curse's entire effect away for free, and a worker proved
  it by measurement: with the curse held and not held, the coast distance on a live glitched tile was
  IDENTICAL (1.0500 vs 1.0500). The curse only mattered after a cleanse.
  RULING: the sim follows DESIGN. `friction_mult` now reads only `w["slippery"]`. A glitched tile keeps
  its -20% run speed, which `run_speed()` applies independently and which is untouched - so the toucher's
  actual threat is unchanged. What changes is that the x0.4 slipperiness now requires the curse.
  MEASURED AFTER: held coast 1.0500 vs not held 0.3750 on a live glitched tile - the curse is now the
  only thing that makes that floor slippery, which is what its rule sentence says.
  THIS IS A BALANCE CHANGE TO A SHIPPED ENEMY EFFECT AND THE OWNER IS AWAY. It is one line and it is
  reversible in one line. The reasoning for making it rather than parking it: (a) the spec is
  unambiguous and the sim contradicted it, (b) FULL_GAME_PLAN.md already flagged this exact line as
  needing a ruling, (c) the alternative is shipping a curse that does nothing, which is the defect this
  whole wave exists to fix. If the owner prefers the old feel, revert `friction_mult` to read both maps
  and retire the curse instead - but then the curse must be retired honestly, not left inert.
  TWO TESTS WERE UPDATED, and this is NOT a threshold move: `test_classes.gd` pinned the glitched tile at
  0.6 tick-1 speed (90 x 0.4 x dt) and now pins 1.5 plus the 7.2 run speed and a separate slippery case at
  0.6; `test_curse_friction.gd` asserted the curse must NOT slow a live glitched tile and now asserts it
  must. Both tests were pinning the spec violation. The new assertions are stricter, not looser.

## D-W9-7: the curse spawn budget stays a silent guard, and the beacon-open edge is proven by tier arithmetic

**Context.** W9-C's audit, arriving after the release, raised two things about `sim/curse_runtime.gd` that
had not been verified: whether the spawn budget starves a curse that spawns an id the votes never planned,
and whether `on_beacon_open` works with all 34 script curses held (the 1800-tick stress probe never reached
the beacon, because 34 curses end a run inside ~10 s).

**Ruling 1 - the budget guard is correct and stays as written.** `if used >= int(planned_counts.get(id, 0)):
return {}` caps a curse at as many bodies of an id as the votes planned of that id. The concern was that a
curse spawning an unplanned id would be silently starved. Checked: `rearguard.in_play_ids()` derives from
`state["spawn_plan"]`, so every id it can pick is planned and has budget >= 1. The guard is therefore a
guard, not a live defect. It is left unchanged because the alternative - a log line or a fallback budget -
would be an unverified edit to the dispatcher after the release, and the failure mode it protects against
(a curse growing one body per tick; `litter` reached 541 bodies in 900 ticks before the guard) is far worse
than a silent empty return. If a future curse spawns an unplanned id, the symptom is a curse that does
nothing, which the content-integrity test and the per-curse world-level proofs are built to catch.

**Ruling 2 - the beacon-open edge is proven, and the proof is arithmetic rather than a log line.**
`out/probe_beacon_allcurses.gd` (gitignored) builds 6 worlds (seeds 1 and 60717 x levels 1/10/20) with every
script curse at 1 stack, parks the player 6-12 u off the beacon on a slot-free floor tile, opens the beacon
through its own API and steps 4200 ticks past the edge. All six: `open=true gold=true`, rearguard spawned 15
bodies, zero SCRIPT ERROR. Overtime tier 0 -> 5. That number is the proof curfew fired: 4200 ticks is 70 s of
gold phase, one tier per 20 s is 3 natural tiers, and 3 + curfew's +2 = 5. Without the curse it would be 3.
The one world reading 0 -> 2 is seed 60717 level 10, where the beacon was entered and the gold phase ended
before the 60 s jump - correct behaviour, not a miss.

**Cost recorded.** The probe keeps the player alive by clearing `ctl.dead`, refilling charges and clearing
`_run_over_emitted` before each step. That is stated in the file's header so nobody mistakes it for a
gameplay run: it is a crash/error stress test, not a balance measurement.

## D-C2-1: the loading-screen contradictions (PARKED rows 22 and 23) are closed by ruling, not by editing canon

**Context.** Two PARKED rows have sat open because DESIGN.md section 2's [CANON] rows and the TICKET LOADING
rulings disagree. Both are documentation conflicts, not code defects: in each case the shipped code already
follows one side, so the game has been behaving consistently while the documents argued.

**Row 22 - "loading screen >= 5.0 s shown" vs the FINAL ruling "5.0 s first launch, exactly 2.0 s restart".**
The CANON row makes no exception for restarts. The FINAL ruling is newer and explicit. `tests/test_loading.gd`
pins both holds (5.0 s first launch, exactly 2.0 s restart) and is green, so the code follows the FINAL.
**Ruling: the FINAL ruling stands.** The CANON row's ">= 5.0 s" is read as the first-launch case; a restart is
2.0 s. DESIGN.md's text is left exactly as the owner wrote it - I do not rewrite canon - and this entry is the
operational reading. If the owner wants the CANON row amended, that is a one-line edit they should make.

**Row 23 - "lobby gate -> next level controllable <= 2.0 s (no loading screen between levels)" vs the TICKET
LOADING done-when "the screen appears on every level load per the flow".** The done-when's own words, "per the
flow", delegate the call sites to the app flow, and the app flow is unambiguous: `_on_level_completed` ->
`_enter_lobby` -> `_on_lobby_exited` -> `_build_world(next_level, ledger)`, with no loading screen anywhere on
that path. The lobby IS the transition. **Ruling: no loading screen between levels.** The CANON row and the
done-when agree once "per the flow" is read as written; there was never a real conflict, only a done-when that
did not name its own escape hatch.

**Cost recorded.** Neither ruling changes a line of shipped code, because the code was already right. What was
wrong was that two documents described the game differently and nobody had said which one the build follows.
That is the same failure mode as the stale README gaps corrected in cycle 2: a document describing the tree as
it was, not as it is.

## D-C2-2: the tripmine needs no tuning, and the level-5 riser is a design beat, not a bug

**The owner's question.** "The bot dies at level 5 to tripmines - would real players also?" Measured by W11-G
from the real code and the real generator (`out/balance_cycle2.md`).

**The premise is stale, and the measurement says so.** The 87%-of-level-5-deaths-were-tripmines number dates
from 11:49Z, when `bot_run.gd` had NO mine model - it advanced the sim through `MinesScript.tick()` and never
read a mine position. Once the bot was given a mine model (12:24Z), the same seed base re-measured to
**D-MINE ZERO**, and today's 20-run reproduction is identical: 19/20 complete level 1, median 41.5 s, every
remaining death an enemy contact (D-COIL 8, D-KIWI 6, D-YOU 4, D-TOUCH 1). **No bot run died to a tripmine at
any level.**

**Would a human die?** No, and the arithmetic is the reason. At the player's 9.0 u/s the tell is visible from
12.0 u and the contact cylinder is 0.9 u, so the warning is **1.23 s (74 ticks)**. A human budget of reaction
(0.25 s) plus decision (0.5 s) is 0.75 s, leaving **+0.48 s of margin**. The star and particle alpha ramp from
0 at 14 u to 1 at 10 u, so the tell does not pop in. The fog at 12 u leaves ~87% of the object, so the tell is
not fog-hidden. And the generator makes an unpassable arrangement impossible: the minimum mine-to-mine distance
across 200 levels is **2.000 u**, never a wall, with the joint-rule bypass at 1.4 u.

**Ruling: no change to the tripmine tell, its trigger radius, or its spacing.** Tuning it would be tuning the
game to satisfy an instrument that cannot play it - the exact mistake the mine model already exposed. The
documented rule is: a lethal hazard is fair when its warning exceeds reaction plus decision, its tell does not
pop in, fog does not hide it, and the generator cannot form a wall. The tripmine passes all four.

**The level-5 riser is real, and it is a design beat.** Mines are exactly ZERO for levels 1-4 and 2-7 at level
5, because `gift_larper` carries `min_level: 5`. So the first level where the player can meet the hazard is
also the first level where it can kill. That is a staircase, not a smooth curve, and the first riser is at L5.
I am NOT changing it: the tell is readable (above), the counter-play (Defuse Kit, T2 200 g) is first buyable at
the post-L4 shop - i.e. exactly before the hazard appears - and the lobby after level 5 is a REST bay at 20%
off. The design already answers the riser. Moving `gift_larper.min_level` to 3 would soften it and would also
change the enemy roster's unlock schedule, which is a DESIGN section 9 decision, not a balance tweak.

**The one change I considered and did NOT make.** PARKED row 31's schedule change - move the third enemy vote
from lobby 3 to lobby 5 - preserves every DESIGN section 9 row and would take level-6 reach from ~15% to ~48%.
It is a five-fold gain on the instrument. I did not apply it, for the same reason as above: the bands are a
target for a competent human, the bot cannot validate them, and a 45-point survival drop from one extra enemy
body is evidence about the BOT's fragility as much as about the game's difficulty. It stays parked with its
measurement recorded for the owner, who can weigh a human's experience against a bot's.

## D-C2-3: the run log does not publish atomically, and that is the correct shape

**Ruling.** `app/run_log.gd` writes its records directly to the destination file. It does not
write a `.tmp` and rename on close. `app/settings.gd` and `core/records.gd` do.

**Why.** The run log is append-only and it is read *while it is being written* - a report or a
test mid-run reads the records so far. The file's own header promises this and `_record`'s
per-line flush exists to serve it. A `.tmp`-then-rename publish makes the destination invisible
until `close()`, which breaks that promise. The failure atomicity would guard against here is a
truncated tail, and the loader already tolerates a truncated tail. Settings and records rewrite
a whole file in place, where a partial write really is corruption, so those two publish
atomically.

**Consequence.** A crash mid-run can leave a run log whose last line is incomplete. That is
accepted. A crash mid-save can no longer corrupt the player's settings or bests.

## D-C2-4: an upgrade's numbers live in its own module, never in app/

**Ruling.** When an upgrade's whole effect is a controller knob, the upgrade carries a module
declaring `static knobs(stacks, kit) -> Dictionary`, and `app/world.gd` merges whatever the
owned modules declare. `world.gd` names no upgrade id.

**Why.** Two reasons that happen to agree. The boundary scan forbids a content id in `app/`, and
naming four ids there was a real violation I introduced. And the number belongs next to the rule
sentence that states it, which is the shape every other script upgrade already uses.

**Consequence.** Adding a knob upgrade is now a content change, not an app change. A module that
declares nothing contributes nothing, so an un-upgraded run reads every knob at its canon
default and is byte-identical to before.

## D-C2-5: the Athletic branch of quick_recovery stays inert, and is recorded rather than faked

**Ruling.** `quick_recovery`'s rule sentence gives the Athletic +5% run speed instead of a
cooldown cut. The module returns `{}` for the Athletic.

**Why.** The Athletic has no class cooldown, so the cooldown knob is meaningless for it - but the
controller exposes no separate run-speed knob for a single upgrade to add to; `run_speed_mul` is
owned by the stat pipeline. Returning `{}` is the same live behaviour as before the module
existed. Inventing a knob to make the sentence true would be a bigger change than the finding
justifies, and doing it silently would be worse than recording it.

**Consequence.** One class gets nothing from one upgrade. This is a known gap, stated in the
module header, and it is the kind of thing that should be closed by a stat-pipeline change
rather than a special case.

## D-C2-6: the final state of cycle 2 gets its own tag, v0.1.5-alpha.3

**Ruling.** v0.1.4-alpha.3 was cut and published at 17:09Z from `f83904e`. Four commits landed
after it. The final state of the cycle is tagged v0.1.5-alpha.3 from `305a263`. v0.1.4 is left
exactly as published.

**Why.** Tags are never moved and releases are never deleted - both are hard limits, and both are
right. A published tag is a promise about what a specific commit contained; rewriting it to point
at later work would make every existing download a lie about its own provenance. The owner asked
for v0.1.4 not knowing it already existed, so the honest resolution is a new tag rather than a
moved one, and the owner was told rather than left to discover it.

**Consequence.** Two pre-releases exist for one cycle. v0.1.4 is a real, working build that is
missing the hitch fix, the CI fix, the store fix and the nine-upgrade wiring; v0.1.5 is the
complete one. Anyone reading the release list should take the highest tag as current. The version
string in `game/app/menu.gd` is bumped in the same commit as the tag, so the menu and the release
cannot disagree.

## D-C2-7: the profile name in old git history is accepted, and the tree stays clean

**Ruling.** The owner has accepted the profile name present in old commits. No history rewrite, no
force-push, no private repository. No further work is spent on it. The working tree and every
commit from this point forward contain no personal information.

**Why.** The owner made the call, and it is theirs to make. A history rewrite would have been the
single most destructive operation available in this repository - it invalidates every clone, every
tag and every published asset - to remove a string that is already public. The cost was real and
the benefit was not.

**Consequence.** The leak is permanent and documented rather than fixed. The forward-looking rule
is unchanged and enforced: no secrets, no personal information, no network calls, nothing personal
in any tracked file or release asset. A final review of the cycle diff confirmed the tree is clean.

## D-C2-8: what cycle 2 ships, and what it parks

**Ruling.** Cycle 2 ships in v0.1.5-alpha.3 with five parked items, each recorded with the reason
it is parked rather than done.

**Shipped.** All 36 upgrades now have a shipped call site except `quick_recovery`'s Athletic branch
(D-C2-5). The spawn-tick hitch is 261 ms to 86 ms. Saves that rewrite a whole file publish
atomically; the run log does not, because it is append-only and read while written (D-C2-3). The
release workflow derives `--prerelease` from the tag. The tripmine needs no tuning (D-C2-2).

**Parked.** (1) The 30-level run proof - the app cannot be driven headless because `Input`
delivers no key state without a window, and the direct level-loop driver crashes the engine
structurally; the seam is proven sound and the crash is in the driver's own loop. (2) The
remaining 86 ms spawn hitch - one cost, not a recurring one, and closing it is a sim change.
(3) The radar's per-frame Label churn - no measured player impact. (4) `quick_recovery`'s Athletic
branch. (5) The accepted history leak (D-C2-7).

**Why.** Each parked item is either blocked on something outside this cycle's reach, or is a
change whose risk exceeds its benefit right now. None of them is parked because it was hard to
find; all five are written down so the next cycle starts from a list rather than from a rumour.

**Consequence.** The README's known gaps and this section must agree, and they do. The next cycle's
first three items are the 30-level proof done one level at a time, the spawn spread, and the
per-upgrade run-speed contribution that closes D-C2-5.

## D-C2-9: the channel button is not "input", so it does not cancel the channel

**Ruling.** `pocket_beacon`'s 180-tick channel cancels on any button OTHER than INTERACT,
on any move axis, or on leaving the ground. A held INTERACT no longer cancels it.

**Why.** The rule sentence says "any input cancels", and that was written before anyone
noticed the channel button is itself an input. INTERACT is a held bit - `input_capture`
sets it from `Input.is_key_pressed`, not from an edge - so the press edge started the
channel on tick N and the same key, still down, killed it on tick N+1. Only a one-tick tap
could ever fill it, which no human can do, so the 1200 g upgrade was inert in practice even
after its call site landed. The module's own test never caught it because it drove the sim
with tick-perfect inputs: press INTERACT, then 180 ticks of `InputScript.neutral()`. That is
a bot's input, not a player's.

**Consequence.** The fix is in `sim/upgrades.gd`, not a mask in `app/world.gd`. Masking
INTERACT in the app would have made the app lie to the sim and left the sim path broken.
Two proofs carry it, both with negative controls: a sim leg that holds INTERACT for all 180
ticks, and a world leg that drives `world.step()` through a `ScriptedWorld extends
WorldScript` overriding `_capture_input()` and asserts the controller lands on the dais.
Reverting the fix fails both - the sim leg at tick 1, the world leg with the body still at
its spawn. This is the third instance in this cycle of one pattern: a test that proves the
sim and not the game. The world leg is the answer to it.

## D-C2-10: a save that is absent is recovered from .old or .tmp, not reset to defaults

**Ruling.** `settings.load_from` and `records.load_from` fall back to `path + ".old"`, then
`path + ".tmp"`, through the same validated parse, when the destination is missing or
unparseable.

**Why.** `_rename_over` moves the destination to `.old` before renaming the `.tmp` over it,
so the destination is absent inside that two-rename window. A crash there, or a failed
rename followed by a failed restore, left the good bytes in `.old` while the loader read
only the destination - so the player's settings and bests silently reset to defaults, and
the next save overwrote the recoverable copy. The window is two renames wide, which is why
this is LOW rather than HIGH, but the failure is silent and permanent when it happens.

**Consequence.** The doc comment now says "recoverable" instead of the stronger "never
absent" it used to promise. `test_atomic_saves.gd` seeds a good file, moves it aside to
simulate the crash, and asserts recovery for both stores; the no-files case is the control,
so a loader that always returned a stale value would fail. Removing the fallback produces 3
failures; keeping it produces 0. `f.flush()` is still not an fsync, so a power cut can still
leave a zero-byte file - `load_from` parses that to null and falls back safely, which is the
behaviour this ruling makes explicit.

## D-C2-11: the 30-level proof is parked because the bot is the limit, not the harness

**Ruling.** The 30-level run proof is parked for this cycle. The harness is proven; the bot is
not. The next attempt is a bot-skill ticket, not a driver ticket.

**Why.** Three attempts. The first wrote a 531-line driver that crashed the engine with exit 127
and no error output, before its first print, at two levels as well as ten - structural, not
scale. The second died of a provider outage. The third worked, and the reason is the lesson: it
is 40 lines and it calls the shipped `BotRun.play_run` entry point instead of reimplementing the
loop. It runs 30 levels headless, exits 0, and prints a result per seed. Verified by hand: seed
38 gives `entered=2 outcome=dead l1_tick=1774 class=glider death_tick=1872`, exit 0.

**Consequence.** Across 14 seeds the bot enters a median of 3-4 levels and dies - best 7, worst 2,
none reached 30. So the intermission-to-next-level handoff is proven end to end at depth, and what
remains unproven is whether a *player* can go 30 levels. The bot is a simple heuristic and does
not survive the difficulty curve. The README's known gap now says this instead of "the crash is in
the driver's own loop", which was true of the first attempt and misleading as a description of the
gap. The driver is preserved at `game/out/full_run_proof.gd` (gitignored) so the next attempt
starts from a working harness rather than from scratch.

## D-C2-12: ten levels are proven through the shipped path; D-C2-11's depth figure was measured on the wrong harness

**Ruling.** The 30-level proof stays parked, but the recorded reason changes. Ten consecutive
levels are proven end to end through the real intermission loop. The bot dies on level 11.

**Why.** D-C2-11 recorded a median of 3-4 levels and a best of 7, measured on `BotRun.play_run`.
That harness does not shop between levels, so it measures a weaker bot than the one the game
actually gives a player. The driver I had written off as crashing - W14-D's
`old_driver_single_free.gd` - works, and it drives the shipped path: real `world.build`, real
lobby, real purchases, ledger carried forward. Run by hand twice:

- `TARGET_LEVEL 10`: `outcome=target_reached deepest=10 completed=9 lobbies=9 ledger_checks=72
  purchases=1 stack_types_carried=3 purse=184 class=glider ticks=34480`
- `TARGET_LEVEL 30`: `outcome=dead deepest=11 completed=10 lobbies=10 ledger_checks=80
  purchases=2 stack_types_carried=5 purse=224 class=glider ticks=41621 ms=97272`

**Consequence.** The intermission handoff, the purchase path and the carried stacks are all proven
at depth, which is a stronger claim than this cycle previously made. The remaining gap is exactly
"the bot dies on level 11". The same bot reaches a median of 4 levels without shopping, so shopping
between levels roughly doubles its depth - a real balance signal, and the reason the two harnesses
disagree. The next attempt should raise the bot's skill, not rewrite the driver. The working
driver is preserved at `game/out/old_driver_single_free.gd` (gitignored).

## D-C2-13: a JSON null is not an absent key, and Dictionary.get() will not save you

**Ruling.** Any read of a numeric field from a content JSON must type-check the value rather than
trust `Dictionary.get(key, default)`. `antechamber.gd` was the one place that did not.

**Why.** `nuke`'s `sprites.json` declares `"world_height": null`, because DESIGN.md section 5 gives
the nuke no body row (SR-2). `Dictionary.get("world_height", 1.0)` returns `null`, not `1.0`,
because the key is present - the default only applies when the key is absent. `float(null)` then
throws `Invalid call. Nonexistent 'float' constructor`, which aborted the exhibit function on
every lobby build: the exhibit's name came back empty and its body scale was never applied. It
looked cosmetic because the billboard is added before the throw.

**Consequence.** `billboard.gd`, `coil_view.gd`, `menu_stage.gd` and `enemy_anim.gd` already used
the correct `if (v is float or v is int)` shape; `antechamber.gd` now does too.
`test_antechamber_exhibits.gd` builds every registered enemy's exhibit and asserts a non-empty
name, with the null-world_height enemy as the explicit control - reverted, it fails twice naming
nuke. The same run's log went from dozens of `SCRIPT ERROR` lines to zero.

## D-B6-1: the collapse takes what was standing on it, and a caught player spends a charge

**Ruling.** When the platform collapse removes a tile, a gift on it is LOST (not collected,
not paid, not drawn), a tripmine on it is DROPPED (consumed through the same bitset a defuse
uses, so it can never kill), and an enemy resting on it FALLS at the controller's own terminal
speed and is retired past the kill plane. A player on it is not touched by the sweep: they fall
through the controller's existing void rule, which is the only death path in the game.

**Why.** The collapse only edited collision, so everything standing on a removed tile hung in
the air. The gift rule is "lost, not relocated": the beacon is already open when the collapse
starts (`sim/gifts.gd` is the only caller of `beacon.open`, on the same tick the black phase
ends), so the black quota is already met and no loss can make a level unwinnable - and
relocating would break `gifts.gd`'s own contract that no code outside `terrain/` invents a gift
position. The enemy rule is the runtime's first ground test: `resting_key()` asks the tile the
feet rest on INCLUDING removed tiles, because `support_at()` skips them and so cannot tell "the
platform under me fell" from "I was never standing on anything".

**Consequence.** A player caught away from the hub when the beacon opens falls and spends a void
charge; the respawn puts them on the dais, which is on the hub, so the collapse converts "being
far away" into "one charge". At zero charges the fall is a real death (`D-VOID`) - the same rule
the game already had for any fall, not a new one. The 5 s crack phase is the warning. A fallen
enemy is drawn while it falls and hidden once it is past the kill plane (`enemy_view_host.set_shown`),
but its row stays in `rt.enemies` so every view index keeps pointing at it. The `crumbling` curse
is deliberately NOT swept (PARKED.md row 32): its tiles return, so a lost gift there would be
destroyed permanently for a temporary hole.

## D-B6-2 [CONTESTABLE]: the collapse makes the gold phase a 5 s dash, and that is the owner's number

**Ruling.** The collapse keeps the owner's own timing - cracks on the beacon-open tick, every
non-hub tile gone 5.0 s later (`sim/collapse.gd`, quoted from the owner's request in its header).
No timing is changed to protect the gold phase.

**Why.** The owner asked for exactly this: "the platform should have cracks on them and 5s later
they fall down to the void. The only platform that cannot be destroyed is the spawn platform."
The gold phase was designed as "stay and collect GOLD gifts for extra currency" with overtime
tiers every 20 s (DESIGN.md section 3.2). Five seconds of floor means the gold phase is now a
dash rather than a stroll, and the overtime tiers are unreachable in practice - the collapse is
the "you are taking too long" pressure now, and it is a harder one than overtime was.

**Consequence, measured.** The app-world driver's purse on the pinned seed fell from 224 to 172
centi-gold across ten levels: the 52 is the gold gifts that fell with their platforms. So the
gold phase still pays, it just pays for what you can reach in five seconds. This is recorded as
CONTESTABLE rather than changed because the number is the owner's, not the fleet's: if the gold
phase should stay a stroll, the fix is a longer `CRACK_SECONDS` (or a partial collapse that
leaves a route), and that is the owner's call, not a tuning pass.

**SUPERSEDED 2026-11-21 by D-B10-1** (the owner's correction: a sequential outside-in collapse,
not one global fall). The text above is kept as written (R9).

## D-B5A-1: a script upgrade may declare a stat contribution, and that closes the Athletic branch

**Ruling.** The stat pipeline takes a per-upgrade contribution. A script upgrade module may
declare `static func stat_mods(kit: String) -> Array` returning the modifier dicts ONE stack
makes, in the same shape a JSON `modifiers` row has; `app/world.gd` repeats it per owned stack
and merges it into the list `core/content_api.gd`'s `apply_modifiers` consumes. `quick_recovery`
uses it: the Athletic gets `run_speed` +0.05 per stack (+5%, +10% at max_stacks 2) and keeps the
-20% cooldown knob for the classes that have a class cooldown. D-C2-5's inert branch is closed.

**Why.** D-C2-5 recorded the gap and said the right fix was a stat-pipeline change rather than
another special case in the module. This is that change, and it is the smallest one that keeps
every existing rule: the module names itself and owns its number, `app/` still names no content
id (the boundary scan holds), and `run_speed` stays the pipeline's to own - the contribution is
an ordinary modifier, so it composes with Yearn for Speed, Weighed Down and the glitched floor
through the same arithmetic instead of through a second path.

**Consequence.** A script upgrade can now move any stat in the closed list, not just a
controller knob, so the next upgrade whose rule sentence names a stat needs no app change. The
`add` op is what makes +5% per stack read as +10% at two stacks rather than 1.05^2 = 10.25%: the
rule sentence says per stack, and `add` is the op that means that. Proven through the shipped
path by `game/tests/test_upgrade_stat_contrib.gd` (world.build + world.step, 0/1/2 stacks on the
athletic class, checked at the pipeline stat, the controller's multiplier and the speed the body
moves at); with the module's contribution removed it fails six ways, and with the world's merge
removed it fails the same six.

## D-B4-1: the enemy spawn pays at most 4 bodies per tick, and the plan completes within ceil(P/4) ticks [CONTESTABLE]

**Ruling.** `_spawn_planned()` spawns at most `SPAWN_PER_TICK = 4` bodies per tick. The spawn
ORDER is unchanged (plan order: vote order, then copy index); only the tick each body appears
on changes. The plan therefore completes by `spawn_delay_ticks + ceil(P / 4) - 1`, where P is
the total planned copy count - tick 125 with Early Bird and tick 365 at the default 6 s delay
for the pinned 22-body vote list. The bound is stated in `enemy_runtime.gd` as
`spawn_complete_tick()` and asserted in `test_spawn_rule.gd`.

**Why.** Measured on the biggest level (seed 7, level 25, 1778 tiles, 16 planned bodies, Early
Bird so the spawn lands on tick 120), per-tick `world.step` cost, first-frame run:

| arm | spawn tick (120) | next worst tick | mean |
| --- | --- | --- | --- |
| FULL (sim + view) | 11.9-15.5 ms | 6.6 ms (tick 269) | 2.21 ms |
| SIMONLY (sim only) | 6.80 ms | 2.23 ms (tick 420) | 0.79 ms |

So one tick paid ~0.43 ms of sim per body plus ~0.32 ms of view per body: the spawn tick was
the worst step of the whole level and sat within 1.2 ms of the 16.67 ms budget (FLEET_PACK.md
A13). At 4 bodies per tick the spawn tick costs ~3 ms and stops being the worst step at all -
the level's worst step becomes the recurring 6.6 ms tick, which is not a spawn cost.

**Why 4 and not 8 or 16.** 4 is the smallest N that leaves the spawn tick below the level's
own recurring worst step, so the spawn stops being the thing that decides the frame budget.
Larger N buys nothing (the recurring tick dominates) and spends the headroom a slower machine
needs; smaller N stretches the arrival over more ticks for no gain.

**Gameplay cost, stated plainly.** The arrival is no longer instantaneous: 22 bodies appear
over 6 ticks (0.1 s) instead of 1. That is below the 0.15 s a telegraph already takes to read,
and the order is unchanged, so the player sees the same bodies in the same places in the same
sequence - just 100 ms apart. This is the [CONTESTABLE] part: if the arrival is meant to read
as one event, the answer is a view-side flourish on the first tick, not a bigger N.

**What does NOT change.** The D-056 rule is untouched: preferred anchor kind -> lane -> any
round-trip tile >= 25 u from the spawn point, never within 25 u of the player, farthest from
the player first, tie-break lowest index, copies of one chaser >= 30 u apart (SR-3). A body
spawned on a later tick is picked by the same rule against that tick's inputs. D-T027-4's
deferral still applies: an entry with no legal tile waits, and only then does the bound slip -
on real levels step (c) always succeeds, so the bound holds there (asserted on a real level).

**Determinism.** The schedule is a pure function of the plan and the tick: a per-tick budget
consumed in plan order, no wall clock, no frame time, no new randomness. The same seed and the
same inputs produce the same bodies on the same ticks, so the replay checkpoints are unchanged.

## D-B5B-1: the airborne landing pick is a point test, not a path test

**Ruling.** `_nearest_landing` now also refuses a landing column whose straight fall from
the feet passes within the body's own contact radius of a contact-kill body. The radius is
`sim/enemy_runtime.gd` `body_contact`'s own (`diameter_u * 0.5 + 0.4`), not a new number.
When no column survives, the original pick is used unchanged.

**Why.** The bot died on level 11 (seed 38) at tick 2151, `D-KIWI`, airborne, 0.80 u from a
kiwi cat. The trace shows the mechanism exactly: at tick 2138-2144 the bot is falling with
`land=(27.50,33.50)` - its own column - and the cat is 1.45 u away. At tick 2145 the cat
moves to (26.59,32.66), which puts the bot's own column 1.24 u from it, just inside
`LAND_CLEAR` (1.25). `_nearest_landing` then re-picks the next nearest column that clears
the body: **(25.50,33.50)**, on the FAR side of the cat. The bot steers at it at full speed
and flies through the body. The column was clear; the fall to it was not. A point test
cannot see that.

**Consequence.** Level 11, seed 38 goes from `tick=2151 gifts_left=48 D-KIWI` to
`tick=4797 gifts_left=1 D-VOID`: the cat trap is gone and the bot now collects all but one
gift. Seeds 36, 37, 39 and 40 are byte-identical before and after (same level, killer, tick,
purse), so the change is inert where the filter never fires. It does not make the game
easier: it is the bot declining a fall it can see is lethal.

## D-B5B-2: level 11 is not survivable after the beacon opens, and that is the collapse's arithmetic

**Ruling.** The remaining level-11 death is not a bot-policy limit. It is the platform
collapse (sim/collapse.gd, owner request 2026-11-20) giving 300 ticks - 5.0 s - to cross
from the last black gift to the beacon, on a level where that distance can exceed what 5.0 s
of running covers. No bot change fixes it and no game change is made under this ticket.

**Why.** Measured on seed 38, level 11, with the D-B5B-1 fix in place:

- `platforms_cracked tick=4381 player=(39.50,13.50,52.13) beacon=(0.50,0.50) dist=64.70
  fall_tick=4681`
- `platforms_fell tick=4681 player=(35.89,11.66,42.30) dist=54.77`

The beacon opens on the last real black gift (`sim/gifts.gd` `all_black_collected` is the
only caller of `beacon.open`), and the collapse starts on that same tick. 64.70 u at the
player's 9.0 u/s base run is **7.19 s** against a **5.0 s** window - and that ignores the
jumps, the gaps and the 13.5 u of height the bot also has to lose. The bot was still 54.77 u
out when the floor went. A player has the same 5.0 s.

**Consequence.** The 30-level proof stays open, and the reason is now precise and different
from D-C2-11/D-C2-12: the bot's policy was the limit up to level 11's cat trap (fixed,
D-B5B-1), and past it the limit is the collapse window against the beacon distance. The
honest next lever is an owner decision on the collapse (a longer window, or a rule that the
last gift cannot be the farthest from the beacon), not a bot ticket. Recorded, not acted on:
this ticket forbids terrain, timing and economy changes.

**The charge is the escape hatch, and the bot had none.** D-B6-1 already ruled that a player
caught by the collapse falls, spends a void charge and respawns on the dais - which is on the
hub, next to the beacon. So "not survivable" above means *not survivable at zero charges*,
not unwinnable: a player holding one charge pays it and walks in. The bot died with
`charges=0` because it had spent both earlier in the run, which is a resource-management
failure on the bot's side and exactly the kind of thing a human does better. The two entries
together are the whole rule: the collapse converts "far from the beacon when the last black
gift is taken" into "one void charge", and only a player already at zero dies to it.

**CORRECTION 2026-11-21: the level is not unwinnable even at zero charges, and a bot change
CAN fix it.** The paragraph above still left the geometry as the limit. It is not. Measured
across 90 levels (seeds 1, 7 and 42 x levels 1-30) with `game/out/collapse_reach.gd`, the
distance from the dais to the NEAREST real black gift slot is at most **10.05 u** (worst case,
seed 7 level 9) and 0.00 u at best (seed 7 level 13, a gift on the dais). The 5.0 s window at
the 9.0 u/s base run covers **45 u**, so on every level there is a gift the player can leave
for last and still reach the beacon in 1.12 s at the worst - a fifth of the window. The beacon
opens on the LAST black gift (`sim/gifts.gd` `all_black_collected`), so which gift is last is
the player's own choice.

So the 64.70 u above is not the level's geometry: it is where the bot happened to be when it
took its last gift. The lever is the bot's gift ORDER - leave a near gift for last - and that
makes this a bot ticket after all, not an owner decision. The owner decision this entry asked
for is still needed for the gold phase being a dash (D-B6-2), which is a different question:
that one is about how much gold is reachable in 5 s, not about whether the beacon can be
reached at all.

## D-B7-1: a gift or a tripmine on a tile a curse removed is hidden by the view, never swept

**Ruling.** A gift or a tripmine whose supporting tile is currently in the world's
removed-tile set (`w["removed"]`, keyed by collision.gd's own `tile_key`) renders hidden,
and comes back with the tile. The rule lives in the two slot views: `view/gifts_view.gd`
and `view/tripmine_view.gd` each take the live set through `set_removed(keys)` - fed from
`app/world.gd`'s `_view_pass` every tick - and fold it into the visibility they already
compute. The tile key is the sim's: `sim/gifts.gd slot_tile_key(i)` and
`sim/mines.gd slot_tile_key(slot_id)` delegate to `collision.gd tile_key(x, z, y_hu)`, so
no view re-spells the format and no view computes geometry.

**Why view-side and not a sweep.** The B6 collapse sweep (`world.gd _collapse_sweep`)
marks what was standing on a fallen tile: `gifts.lose(i)` and `mines.drop(slot_id)`. That
is right for the collapse because the collapse's contract is "the tile is gone for good" -
`sim/collapse.gd` writes into `removed` once, at the fall tick, and nothing restores it. A
tile-schedule curse's contract is the opposite: the tile returns after 5 s. Running the
same sweep there would destroy a gift permanently for a temporary hole - it would leave
the quota, the straggler beam and the gold phase short by one gift the player could still
have collected. So the curse's hole is a rendering fact, not a state change: the gift
stays `present()`, stays collectible, stays in `remaining()`, and the mine stays live
(`contact_at` still answers at its own point).

**Why the collapse path is unaffected.** After the sweep a gift is `lost`, so `present()`
is false and the view already hides it; a mine is `consumed`, so `is_consumed()` is true
and the view already hides it. The new term is an `and` on a predicate that is already
false, so it changes nothing there - proven both ways in
`game/tests/test_removed_tile_view.gd`'s collapse leg: the lost gift and the dropped mine
stay hidden with their tile in the removed set and with it out of the set.

**Consequence.** A hole that opens or closes is on screen the same tick (the set is held
by reference and re-fed before each sync). Nothing in the sim reads the new accessors, so
determinism, the state hash and the replay checkpoints are untouched. The rule is per-slot
and O(1) per slot per tick: one dictionary lookup, no allocation.


## D-DEPTH-1: the min_level gate lives in the offer, not in the spawn, and that is left alone

**Ruling.** `sim/offers.gd` `enemy_candidates()` is the only place `min_level` is enforced:
a type whose `min_level` is above the level being voted is never offered, so it can never
be voted. `sim/enemy_runtime.gd` does NOT re-check `min_level` when it spawns a row, and
this entry records that as deliberate rather than as a missing guard.

**Why it is not a bug.** The vote is the only way a row is ever created. A ledger's `votes`
dict is produced by `sim/intermission.gd` from the offers, so every vote in normal play has
already passed the gate. A second check in the spawn path would be dead code that only a
hand-built ledger could reach - and the one caller that does hand-build ledgers is a test.

**Measured, not assumed.** `world.build(1, 12, {"votes": {"gin": 1}, ...})` spawns gin at
level 12, whose `min_level` is 17. Disabling the offer gate (`if false and p_level <
min_level`) changes NO roster at levels 1, 5, 12, 18, 24 or 30 on the seeds probed, because
the schedule never offers an over-level type at those depths - the gate is a safety net that
does not fire on the shipped path. Both facts were probed directly while writing
`tests/test_depth_smoke.gd`, which is why that file asserts a property of the VOTE path
("normal play never produces a body above its min_level") and not an invariant of the spawn
rule.

**Consequence.** If a future save/load or a debug console ever writes `votes` directly, it
can spawn an over-level body and nothing will stop it. That is the accepted cost of not
carrying a redundant check; the alternative is a spawn-path guard whose only reachable
caller is a test. Revisit if a ledger ever arrives from outside `intermission.gd`.

## D-B9-1: a degenerate y band is a plane marker, and a body the hop cannot clear is not hurdled

**Ruling.** Two bot-policy fixes in `tools/bot_run.gd`, both of them the bot reading the sim
wrong rather than the sim being wrong.

(a) `_inside_footprint` treats a DEGENERATE y band (`y1 == y0`) as a plane marker, not a
volume. The coil's landing ring is drawn on the landing plane (`y0 == y1 == land_y`) and the
toucher's pulse on its own plane, both for address_me's arbiter gate and the view. The strike
they announce is not bounded by that plane: the coil's landing kill is a height-blind 1.2 u
circle (D-T-031-4, "regardless of feet height"). Reading the zero-height band as a volume made
the bot stop dodging the moment it stepped up 0.5 u, jumped or dropped. A band with real height
still bounds - the fix narrows the y test, it does not drop it.

(b) `_hop_clears` refuses to hurdle a body whose TOP sits at or above `HOP_CLEAR_FRAC` (0.8) of
the hop's apex. `sim/enemy_runtime.gd` `body_contact` clears only on `py0 > row.y + height_u`,
so a body whose top is at the apex is NEVER cleared: the hop keeps the feet inside its vertical
span for the whole arc and only costs the horizontal escape that outruns it. The kiwi cat hovers
(`climb_u_per_s` 2.0) so its top sits 2.0-2.4 u above the feet, and a coil in flight is 2.0 u
tall; both were hopped and both killed the bot mid-hop.

**Measured** on the pinned 20-seed sweep (seed base 60717, `--max-level 18`), baseline vs these
two fixes only:

| | baseline | after |
|---|---|---|
| level 6 reach | 15.0% (3/20) | **20.0% (4/20)** |
| D-COIL | 8 | **5** |
| D-KIWI | 6 | 6 |
| D-YOU | 4 | 5 |
| D-TOUCH | 1 | 1 |
| D-MINE | 0 | **2** |
| D-VOID | 0 | 0 |
| A3 (level 1) | 19/20 | 19/20 |

The coil drop is the fix working: 3 of the 8 coil deaths were the bot standing in a ring it had
decided was out of reach. The bands are still 60 points short of the bar, so this does not
validate them - it makes the instrument less wrong.

**A THIRD FIX WAS WRITTEN AND REJECTED.** The same ticket also added `_avoid_vector` to the
airborne heading, on the argument that the airborne branch returns before the avoid layer and so
a body about to touch the player mid-arc was simply flown into. With all three fixes the sweep
gave level 6 = 15% (no gain), D-COIL 8 (no gain), and **D-VOID 0 -> 3**: the avoid layer steered
the arc off its footing, which is exactly what its own comment claimed it could not do. Rejected
on the measurement, not on the argument. The comment's claim ("`_safe_dir`-rotated, so it cannot
steer the arc off its footing") is false and is recorded here so nobody re-adds it on the same
reasoning.

**THE MINE REGRESSION IS REAL, AND ITS MECHANISM IS THE COIL'S FORCED MOVEMENT.** D-MINE went
0 -> 2. I guessed the mechanism wrong TWICE before tracing it: first "the bot dodges while
airborne and lands on a mine it never looked at", then "the bot falls off an upper tier and comes
down on a lower one that has a mine on it". Both are wrong and both are corrected here. The
extended trace (`--trace`, with `grounded` / `vy` on the DEATHFORENSIC line and a mine-distance
loop) gives the truth for both deaths:

| seed | tick | position | grounded | vy | nearest mine | coil |
|---|---|---|---|---|---|---|
| 60732 | 545 | (2.24, -1.00, 28.00) | **true** | 0.00 | (1.50, 27.50) **d = 0.90** | **4.78 u** |
| 60731 | 4408 | (-30.50, -6.05, 36.61) | false | **+5.73** | (-30.50, 37.50) **d = 0.89** | **4.16 u** |

Three things follow from the numbers, and none of them is a fall onto a lower tier.

1. **The mine guard did not fail.** Both distances are `CONTACT_R` (0.9) to two decimals, and
   `MINE_SAFE` is 0.97. The guard is a *steering* guard on the ground path and it held; the
   player was put inside the cylinder by something other than its own steering.
2. **A coil is inside `SHOCK_RADIUS` (6.0) in both.** `content/enemies/coil/enemy.gd`
   `_tick_shock` calls `api.push(idx, dir, speed)` every tick for `SHOCK_TICKS` (30) at up to
   `SHOCK_PUSH` (8 u/s), and `sim/enemy_runtime.gd` `push` writes `ctl.vx` / `ctl.vy` / `ctl.vz`
   directly. A steering guard cannot resist a velocity write. In seed 60732 the player was
   **standing** (`grounded = true`, `vy = 0.00`) when the shockwave shoved it into the mine.
3. **In seed 60731 the player was RISING** (`vy = +5.73`, `vy` positive is up). Mine contact is
   height-blind by canon - DESIGN.md §3.3, "at **any height** - jumping over a mine does NOT
   avoid contact" - so the jump the bot made to leave the coil ring carried it horizontally into
   the mine's cylinder and the height did not save it.

So the common root is one interaction, not two bugs: **the coil's landing forces the bot to move
- a shove it cannot resist, or a jump-dodge it chose - and that movement ends inside a mine's
0.9 u height-blind cylinder.** That is the game working as designed (DESIGN.md §3.3 and §5.2),
not a mine defect and not a guard bypass. It only appears now because the bot survives coil
landings more often (D-COIL 8 -> 5), so it is a side effect of the fix working, not of the fix
being wrong. Recorded as PARKED row 33 with the traced numbers. Until it is fixed the README's
"the bot's mine deaths are ZERO" is no longer true and has been corrected.

## D-B9-2: the mine guard's lookahead matches an airborne arc, and the landing pick is not the place to fix it

**Ruling.** `tools/bot_run.gd` only. `_mine_clear` takes a `reach` parameter (default 1.2 u,
the ground step) and `_mine_guard` passes `AIR_MINE_REACH` (3.0 u) while the player is
airborne. Nothing else changes: the guard still keeps `MINE_SAFE` 0.97 u, still rotates in
15-degree steps, still refuses a heading that leaves ground support when grounded.

**Why.** Mine contact is height-blind - DESIGN.md §3.3, "at **any height** - jumping over a
mine does NOT avoid contact" - so a mine 2-3 u ahead is one an airborne arc can still come
down on, while a 1.2 u ground step cannot reach it. The planned-jump scan already refuses an
arc that passes within `MINE_ARC_SAFE` (0.95) of a live mine at any height; this is the same
rule for the arcs the bot did not plan, which is where D-B9-1's second death came from.

**Measured** on 60 seeds (base 60717, `--max-level 18`), the same seeds on both sides - the
baseline is the same tree with `AIR_MINE_REACH` set to 1.2, which reproduces the old code
exactly (same cutoff `reach + 1.8`, same 0.3 u sample step):

| | baseline (reach 1.2) | airborne reach 3.0 |
|---|---|---|
| level 6 reach | 18.3% (11/60) | **20.0% (12/60)** |
| D-MINE | 3 | **2** |
| D-KIWI | 23 | 25 |
| D-COIL | 18 | 18 |
| D-YOU | 9 | 8 |
| D-TOUCH | 1 | 0 |
| D-SEAL | 1 | 2 |
| D-NUKE | 1 | 2 |
| A3 (level 1) | 58/60 | 58/60 |

**Honest reading: both moves are ONE run.** On the 20-seed pinned sweep the same change read
as level 6 20.0% -> 30.0% and D-MINE 2 -> 0, which is exactly why the 60-seed run exists - the
20-seed numbers were noise. This is a correctness fix (the guard's reach now matches the arc
it is guarding), not a cure for PARKED row 33, and it is not claimed as one.

**A FIRST ATTEMPT WAS WRITTEN AND REJECTED.** Adding the live mine points to the airborne
landing pick's `avoid` list (`_nearest_landing`, the same list the body term uses) took level 6
from 20.0% to **0.0% (0/20)** on the pinned sweep. That is the failure mode B5B's worker
already recorded for the body term: hard-rejecting landing columns makes the bot pick worse
ones, and with no fallback it steers off its footing. Reverted, not shipped. The lesson is the
same one row 33 already carries - the landing pick is a point test and is not where a path
constraint belongs.

**The remaining gap.** The emergency dodge jump does not go through the planned-jump arc scan,
so a dodge arc can still cross a mine. Closing row 33 means making the dodge consult the arc
model (`_jump_arc`'s `MINE_ARC_SAFE` check) instead of the landing pick. That is the next
thing to try, and it is a bigger change than this one.

## D-B10-1: the collapse is sequential, outside in, one zone at a time (supersedes D-B6-2)

**Ruling.** The owner corrected the collapse: not every non-hub tile at once 5 s after the
beacon opens, but a shrinking safe zone. `sim/collapse.gd` now cuts the level into ZONES and
runs a per-zone schedule; every number is in `game/data/collapse.json`:

- **Zone rule.** Every non-hub piece (a platform or a bridge, never a single tile) goes into
  one zone by the XZ distance from the dais centre to the piece's NEAREST tile. Level radius R
  = the largest such distance; zone count N = clamp(ceil(R / `zone_width_u` 16), `zone_min` 1,
  `zone_max` 6); band = min(N-1, floor(d * N / R)); a band no piece lands in is dropped. The
  hub piece (`ROLE_HUB`) is in no zone and never falls.
- **Schedule.** On the beacon-open tick the farthest zone cracks; `crack_to_fall_s` 5.0 s
  (300 ticks) later it falls; `gap_after_fall_s` 10.0 s (600 ticks) later the next zone inward
  cracks. Zone i cracks on open + 900 i and falls on open + 900 i + 300. Only one zone is
  ever cracking. Across seeds 1/7/42 x levels 1-30 that is 2 to 6 zones, 35 to 80 s in all.
- **Unchanged.** What stands on a falling zone goes with it (D-B6-1: gifts lost, mines
  dropped, enemies fall, the player falls through the void rule); the removed-tile set is the
  same `w["removed"]`. The view drops each zone on its own (`collapse_view.gd`, one drop root
  and one crack overlay per zone, meshed by `level_mesher` `PART_ZONE`).
- **Determinism.** Tick-driven, no RNG, no clock. The state now rides on `lstate.collapse` and
  `sim/state_hash.gd` dumps `COLLAPSE <phase> <start> <cur> <fallen_n> <removed_n>` (absent
  when a level carries no collapse, so every pre-B10 dump and golden is unchanged).

**Why nearest-tile distance.** A piece that reaches inward falls with its inner band, i.e.
later. That gives a player on its far end more time, never less, and the "whole pieces only"
rule (never single random tiles) is what the owner asked for.

**Measured: no level becomes unwinnable** (`game/out/zone_reach.gd`, seeds 1/7/42 x levels
1-30, run speed 9 u/s, straight XZ distances, as the old `collapse_reach.gd` check did):

- WIN rule: the player picks the last black gift. Taking the gift with the most slack last,
  the run to the dais must finish before that gift's zone falls. 0/90 unwinnable. In 87/90 a
  real black gift is on the hub itself, so it never falls; the worst of the other three still
  has 311.8 u of slack (seed 42 level 13, gift 3.16 u from the dais, zone falls at 35 s).
- STRAND rule (stronger: anywhere the player stands when the beacon opens): from every
  non-hub tile, the straight distance to the nearest tile that falls LATER (or a hub tile)
  must be covered before the tile's zone falls. 0 of 91,770 tiles fail. The worst slack is
  11.0 u (seed 42 level 11, first zone: 34 u to cover in 5 s). From any later zone the next
  escape has the full 15 s (135 u), and the worst need is 40 u (95 u spare).

**Measured: purse** (app-world driver `old_driver_single_free.gd`, seed 38, glider):
before (D-B6-2 global fall, this tree's base) the driver reaches level 10, purse **170**.
After, it dies on level 8 (D-KIWI), purse **97**. Through the 7 levels both complete, the
purse is 246.28 before and 256.28 after (+10.00). So each level pays more gold, but the run is
shorter. The death is not the collapse: under the global fall the bot on level 8 was caught
50 u out, fell, spent a charge and respawned on the dais, so it never met the kiwi cat. Under
zones it walks in past the cat and the cat kills it at 21 u. In other words, the old global
fall was teleporting the bot past an enemy for one charge. (The 216 the ticket quotes is an
older run; 170 is this tree's base, measured with the same driver.)

**Measured: bot** (`tools/bot_run.gd`): level 1 97/100 (`--runs 100 --max-level 2`); level 6
20.0% (12/60) (`--runs 60 --max-level 18 --seed-base 60717`), deaths identical to D-B9-2's
row. Neither number can move, and that is a finding, not a result: `bot_run.gd` plays
through `RunState` and never runs `sim/collapse.gd` (true since B6). The collapse only reaches
the bot through the app-world driver above.

**[CONTESTABLE]** zone width 16 u and the cap of 6 zones are the fleet's choice, not the
owner's. 5.0 s and 10.0 s are the owner's numbers.

**CORRECTION 2026-11-21 (independent adversarial review, B10 review findings 1-4).** Three claims
above were too strong and one was a real defect. The text above is kept as written (R9).

1. **The hash collision was real.** The COLLAPSE line carried only the live schedule, so two runs
   whose `collapse.json` differed - or one with the collapse enabled and one with it disabled -
   hashed the same until the first zone fell and then diverged. `enabled` decides whether
   `start()` changes the world at all, and the crack/gap seconds and the zone width are DATA, not
   a function of the Level, so none of them was pinned. The line now also carries `enabled`,
   `crack_ticks`, `gap_ticks` and a `partition` digest computed once at `create()` (sorted keys
   per zone, so it does not depend on the Level dict's tile order). Leg 17 fails on each of the
   five collisions; reverting the line produces exactly 5 failures.
2. **"No level becomes unwinnable" is a straight-line bound, not a proof.** The probe uses XZ
   distance at 9 u/s and ignores jumps, height, routes around obstacles, enemies and the player
   being airborne. What is measured is that no level is unwinnable BY THAT MEASURE and that no
   tile is stranded by it. A level could still be unwinnable in play. The same caveat applies to
   the 0 of 91,770 stranded-tile figure.
3. **The bot percentages are not evidence about the collapse.** `bot_run.gd` never runs it, so
   they belong in this entry as a statement that the feature is untested there, not as a pass.
   The app-world driver regression (level 10 -> 8) is the relevant counterevidence.
4. **Leg 16's partition claim is strengthened.** It compared mesh-category totals, so a dropped
   piece and a duplicated one could cancel. It now also checks the piece-level partition: every
   piece that has tiles is in exactly one zone, and the hub is in none.
5. **Known limitation, not fixed (review finding 5).** `create()` deduplicates tile keys and gives
   a shared key to the first piece, while `level_mesher` `PART_ZONE` filters by piece id without
   that dedup. If two pieces ever shared a tile key and landed in different zones, that tile could
   be meshed twice and one copy could stay visible after its collision was removed. The reviewer
   found no evidence that generated levels produce such a key, and a tile belongs to one piece by
   construction in `voidgen.gd`, so this is a malformed-level edge case. Fixing it properly means
   passing a key set to the mesher instead of a piece set; that is not worth the API churn until
   a level is shown to trigger it.

**PARTLY SUPERSEDED 2026-11-21 by D-B11-1** (owner retune after playing: the first crack came
far too early and each fall took far too much). D-B11-1 replaces the 16 u zone width, the cap of
6, and "zone 0 cracks on the beacon-open tick" with a 20 s start delay. The zone rule, the 5.0 s
crack, the 10.0 s gap, one zone at a time, outside in, and everything that falls with a zone
still stand. The text above is kept as written (R9).

## D-B11-1: a 20 s grace before the first crack, and thinner zones (supersedes D-B10-1's width and cap)

**Ruling.** The owner played the sequential collapse and found that the first crack came far too
early and that each fall took far too much. The rule stays the same; the data changes, and one
field is new. Everything is in `game/data/collapse.json`:

- **`start_delay_s` 20.0 (new).** The beacon opening starts the schedule's clock, but nothing
  cracks for 20 s (1200 ticks). Zone i cracks on open + 1200 + 900 i and falls on
  open + 1200 + 900 i + 300. During the delay the state is `PHASE_WAITING` with `cur` 0, so
  nothing is cracked, removed, or shown. A delay of 0 restores D-B10-1's crack-on-open path
  exactly (leg 18).
- **`zone_width_u` 16.0 -> 8.0, `zone_max` 6 -> 12** (the guardian's ruling, kept as given).
  `zone_min` 1 is unchanged.
- **Unchanged:** `crack_to_fall_s` 5.0 and `gap_after_fall_s` 10.0 (the owner's numbers); one zone
  cracking at a time, outside in, whole pieces only; the hub never falls; tick-driven, with no RNG
  and no clock.
- **State hash.** The `COLLAPSE` line gains a trailing `<delay_ticks>`, because the delay is data
  and not a function of the Level (the same reasoning as B10 review finding 1). Leg 17 fails if
  the shipped 20 s delay hashes the same as a 0 s or a 19 s one.

**Why 8 u / 12 and not something else.** Measured with `game/out/zone_reach.gd` (gitignored,
rewritten this cycle; seeds 1/7/42 x levels 1-30; run through `out/one.gd`):

| config | zones min / median / max | collapse time min / median / max | tiles per fall (median) | biggest fall per level (median) |
|---|---|---|---|---|
| D-B10-1: 16 u, cap 6, no delay | 2 / 4 / 6 | 20 / 50 / 80 s | 220 | 368 |
| **D-B11-1: 8 u, cap 12, 20 s** | **4 / 7 / 12** | **70 / 115 / 190 s** | **126** | **228.5** |
| for comparison: 8 u, no cap, 20 s | 4 / 7 / 16 | 70 / 115 / 250 s | 123 | 228.5 |

Each fall takes about 43% fewer tiles (median 220 -> 126), and the median collapse lasts 2.3x as
long (50 -> 115 s). The cap of 12 binds on only 3 of the 90 levels (uncapped they would have 13,
14 and 16 zones). Its job is to stop the largest levels from running to 250 s, not to shape the
typical level, so the guardian's numbers stand untuned. (D-B10-1's "35 to 80 s" understated the
low end: with 16 u, two levels had only 2 zones, which is 20 s.)

**Measured: no level is unwinnable by the straight-line bound** (9 u/s, XZ distance, jumps,
height, obstacles and enemies ignored; the same caveat as the D-B10-1 correction, item 2):

- WIN rule (the best last black gift runs to the dais before its own zone falls): **0 of 90
  unwinnable.** In 87 of 90 levels a real black gift sits on the hub. The worst of the other
  three still has 892 u of slack.
- STRAND rule (from every non-hub tile, reach a later-falling tile or the hub before your own
  zone falls): **0 of 91,770 tiles fail**, under both budgets. The "open" budget is the time from
  the beacon opening to the tile's fall; the worst slack is 200.8 u. The stricter "chain" budget
  assumes the player only just arrived as the zone outside them fell, so they get 25 s for zone 0
  and 15 s for every later zone; the worst slack is 103.1 u (seed 1 level 23, zone 2). Under
  D-B10-1 the same probe gives 11.0 u (seed 42 level 11, zone 0), reproducing that entry's figure.

**Measured: bot** (`tools/bot_run.gd --dodge --runs 20 --max-level 2`, five chunks from seed
base 60717): 19 + 20 + 19 + 20 + 19 = **97/100** level-1 completions, unchanged. As the D-B10-1
correction (item 3) says, `bot_run.gd` never runs `sim/collapse.gd`, so this number cannot move
with the collapse, and it is not evidence about it.

**Measured: purse** (app-world driver `old_driver_single_free.gd`, seed 38, glider, the driver
that does run the collapse): before (this tree with the D-B10-1 data) deepest 8, completed 7,
purse **97**, 33,130 ticks; after (D-B11-1) deepest 8, completed 7, purse **97**, 33,130 ticks,
with identical per-level tick counts. **No purse impact.** The bot walks to the beacon as soon as
it opens and banks within the old window, so the collapse never touches it on this seed. The
driver's own "deepest >= 10" floor fails both before and after; that is the pre-existing D-B10-1
regression (kiwi cat on level 8), not this change.

**Tests.** `test_platform_collapse.gd` asserts the new contract: leg 2 checks every tick of the
1200-tick delay; legs 3-13 are timed from open + 1200; leg 14 pins 20.0 / 8.0 / 12 in the data;
leg 17 hashes the delay; new leg 18 checks 0 s / 20 s / 0.5 s delays on the pure state. Negative
controls: with `start_delay_s` 0 the test fails 51 times, and with the D-B10-1 16 u / cap 6 it
fails 2 times. No assertion was removed or loosened. Leg 17's width check now compares 16 u
against the shipped 8 u (it compared 8 u against the shipped 16 u), and its overrides are merged
over the shipped data, so each check still moves exactly one number.

**[CONTESTABLE]** 8 u and the cap of 12 are the guardian's ruling. 20 s, 5 s and 10 s are the
owner's numbers.

## D-C4-15-1: the tier table is data, and the price bands are checked

**Ruling.** DESIGN.md section 8's price-tier table now has one machine-readable copy:
`game/data/upgrade_pools.json` `"tiers"` (pool_from, price_min, price_max for T1-T5; the schema
requires all five). `core/content_api.gd` used to hold the pool-from levels as a code constant
(`TIER_FROM`) that only repeated the data file's `_doc` text. It now fills `TIER_FROM` from the data
at `load()` and exposes the table as `tiers()`. The price bands were in no file but DESIGN.md.
`shop_pool()` and `draw_shop()` are unchanged: they already applied the tier gate, and
`tests/test_upgrade_tiers.gd` proves that instead of changing them.

The new test fails if the data's tier table differs from DESIGN.md section 8, if two bands overlap
or the pool-from levels stop ascending, if any upgrade's list price is outside its tier's band, if a
bracket lists an id before its tier's pool-from level (checked on the raw data, because
`shop_pool()` would hide it), if `shop_pool()` holds one at levels 0-60, or if `draw_shop()` offers
one (levels 0-32 x 4 classes x 5 purses x 4 seeds). Every leg was shown failing on an injected
defect before it was restored.

**Why.** The owner's complaint is about levels and prices. The rule that settles it should sit in
the data file the shop reads, next to the brackets, and not in a code constant plus a prose table.

## D-C4-15-2: the owner's "end-game upgrade at level 2" does not happen on this tree; no tier or price was changed

**Ruling.** This is the audit of all 36 upgrades (the table is in README.md, generated from the data
by `game/tools/upgrade_table.gd`). Every list price is inside its DESIGN.md section 8 band. No bracket
lists an id early. The earliest shop that can show a T2 is the one after level 4, a T3 after level 10,
a T4 after level 19 (it enters the pool at 18, which has no shop) and the T5 after level 28 (enters at
26, no shop). A probe through the real `Intermission` (levels 0-30 x 60 seeds x purses 0/50/200/2000)
found 0 offers above the tier gate. Level 2 and level 3 have no shop at all (the schedule is C, then E),
so nothing can be bought at level 2. The only shop before that, after level 1, sells exactly the
CANON three.

So no data defect matches the complaint, and none was invented to fit it. DESIGN.md section 8 is
frozen and pins every id's tier and price, and so does `tests/test_upgrades_decl.gd`. Re-tiering
an upgrade is a design change and needs the owner. The candidates are parked in PARKED.md row 35
with their numbers: Field Dressing's power against its T1 price, the unreachable "2-3" bracket, and
a T5 that the average-player model buys in 1% of runs.

**Measured, before and after, on the same seeds (both identical, as expected for a change that
moves no id, price or bracket):** `bot_run.gd --runs 20 --seed-base 60717 --max-level 18`: level 1
completed 20/20 (median 43.6 s), level 6 reached 20% (4/20), level 12 0%, level 18 0%, median level
4, max 8. The 40 per-run lines are byte-identical. `economy_audit.gd`: AUDIT OK, afford1 99.5%,
afford3 29.3%, purchases 23.89, cautious 8.25, identical.

## D-C4-15-3: the README upgrade table is generated, and a test keeps it honest

**Ruling.** README.md carries the tier bands and a per-upgrade table (tier, price, 2nd and 3rd stack
price, max stacks, pool from, first shop, class). The block between the `upgrade-table` markers is
written by `game/tools/upgrade_table.gd -- --write`. Every number comes from the same calls the game
makes (`shop_pool()`, `bays_for_level()`, `price_for()`). `tests/test_upgrade_tiers.gd` regenerates
the block and fails if one byte differs. "First shop" is listed next to "pool from" because those two
answer different questions: Field Dressing is in the pool from level 2, but the first lobby that
sells it is after level 4.

## D-C4-15-4: the two probes print the purse, behind flags

**Ruling.** `bot_run.gd -- --purse` prints `PURSE run i seed=s [...]`: the purse the shop sees after
each completed level. `economy_audit.gd -- --purse` prints the mean purse at each shop and the tiers
bought there, for the average and the cautious player. Both are off by default, so the default output
and every assertion are unchanged.

**What the numbers show.** The bot's purse is not a player's purse. The bot buys nothing, and its
ledger is credited only with curse bounties, not with gold or the stipend. Seed 60717 reads 0, 0, 22,
22, 76, 76. The economy-audit model is the instrument for income. Its average player arrives with
64 g at the level-1 shop, 196 g at level 4, 353 g at level 10, 396 g at level 19 and 883 g at level 28.
The first T3 purchase is at level 10, the first T4 at level 22, and T5 is bought 0.01 times per run.
Nothing is bought above its tier's level.

## D-B12-1: the collapse starts 5 s after the beacon opens, not 20 (supersedes D-B11-1's delay)

**Owner report.** "the platforms dont collapse" (v0.1.11-alpha.3).

**What was actually wrong.** Nothing in the schedule. Driven through the real gift path (walk the
player onto every black gift so `sim/gifts.gd` `tick()` opens the beacon), the collapse cracks zone 0
and drops it exactly on time, and the view drops that zone's meshes and hides them. The problem was
that nobody ever saw it: D-B11-1's `start_delay_s = 20.0` is longer than the whole gold phase.

**Measured.** The gold phase is the walk from the last black gift to the dais. Over seeds 1/7/42 x
levels 1-30 (90 levels), the farthest real black gift sits 28-107 u from the dais, which is 3.1-14.9 s
at the 9 u/s bound: mean 6.8 s, and **90 of 90 levels are under 20 s**. So a player who collected the
last gift and headed for the beacon always finished the level before the first crack at 20 s. There
was also no HUD element saying the collapse had started.

**Ruling.** `start_delay_s` is **5.0** (300 ticks). The first crack lands inside a normal gold phase
and the first fall at 10 s. Everything else D-B11-1 set is unchanged: `crack_to_fall_s` 5.0,
`gap_after_fall_s` 10.0, `zone_width_u` 8.0, `zone_min` 1, `zone_max` 12. The collapse still takes
55-175 s to reach the hub (mean 106 s), so the "much longer, much less per fall" intent is intact.
`view/hud/collapse_warning.gd` is new: a top-centre countdown ("NEXT RING IN Ns" while waiting,
"THE VOID IS CLOSING - RING FALLS IN Ns" while a ring cracks, "ONLY THE HUB REMAINS" at the end),
fed by `world._collapse_feed()` and hidden until the beacon opens.

**Re-measured.** `tools/collapse_reach.gd`: `levels=90 unwinnable=0 worst_slack=84.0 at=seed 42
level 3 zones=4..12 mean=7.4 collapse_s=55..175 mean=106`. The worst slack fell from 99.0 s to 84.0 s
(the 15 s the delay gave back) and is still far from zero. The bot does not run the collapse
(`bot_run.gd` has no collapse tick, true since B6), so its numbers cannot move; level-1 completion is
re-measured in the ticket report.

**Tests.** `test_platform_collapse.gd` legs 2, 13, 14, 17 and 18 now pin 5 s / 300 ticks instead of
20 s / 1200; leg 19 is new and pins the HUD feed and the three warning strings. Nothing was deleted,
skipped or loosened. `shot_collapse_timeline.gd` (a tool, not a gate step) now asserts the 5 s delay
and takes its quiet shot at 2 s.

## D-GUI-1: the HUD is rebuilt in the reference panel language, with a gold counter and a CTRL hint (2026-11-21)

**Owner report.** The GUI "is kinda bad". From a reference build the owner likes three things: the gold
gift counter at the bottom, the "CTRL TO LOCK/UNLOCK MOUSE" hint, and the dark rounded pill panels.
Only the screenshot was used as a reference. No code was copied.

**Ruling: one panel language.** `view/hud/hud_style.gd` is new and holds every number the HUD draws
with. Panels are dark and translucent (`#0E0E16` at 74%), with a 1 px faint border, a 10 px corner
radius, 14/8 px padding, a 16 px screen margin and an 8 px gap between neighbours. There are three
type sizes and no others: 13 (badges, radar distances, the hint, seconds), 18 (pill text) and 34 (the
counter). The counter and the hint use a monospace face, as in the reference. Every element in
DESIGN.md section 14 now uses these panels: the gift counter, the purse and chain, the void pips with
Last Light, the ability cooldown, the curse and upgrade rows, the enemy roster, the cartographer map
and the collapse warning. The radar chevrons and `screen_fx` are overlays, not panels. They are now
drawn above every panel and are not part of the overlap rule, because a chevron has to sit at its
true bearing on the screen edge.

**Layout (any viewport; all anchored).**
- Top-left: the roster, 195x140 at most (38 px cells, 5 px gap, so that test_enemy_stacking.gd's
  existing 200x140 limit still holds).
- Top-centre: the icon rows, 574x102 at y 16-118, then the collapse warning, 460x40 at y 126. It moved
  from y 100 because the rows' panel now ends at 118.
- Top-right: the purse pill, 240x40, with the map under it at y 64.
- Bottom-left: the pips pill, 152x64, with the ability pill, 198x64, 8 px to its right.
- Bottom-centre: the counter pill, 240x60, and under it the hint, 320x18, 10 px from the bottom edge.

The icon rows hold at most 12 cells. A row with more items shows 11 cells and a "+N" cell, because
the curse catalogue has more than 100 entries and an unbounded row would walk into the purse.
`curse_count()` and `upgrade_count()` still report the full count.

**Ruling: the gold counter.** `view/hud/gold_counter.gd` is new and subclasses the gift counter, using
a gold gift icon and gold text. `read(gifts)` is the only reader. It counts the `gold_taken` bitset
over REAL slots only, so a bit on an occ == 1 slot is never counted. The total is `total_real`,
because the black-to-gold flip puts a gold gift at every real slot. `active` is `phase == gold`. The
gold counter and the black-phase gift counter share one slot. Through the black phase the gift counter
shows and the gold counter is hidden and zeroed. On the flip tick they swap, so both are never visible
at once. The denominator stays `total_real` even after the collapse takes gifts, which matches the
existing gift counter. A shrinking denominator was rejected as harder to read. [CONTESTABLE]

**Ruling: the hint says what CTRL will do now.** When the mouse is locked it reads "CTRL TO UNLOCK
MOUSE", and when it is free it reads "CTRL TO LOCK MOUSE". The reference's combined wording was
rejected because a hint that states the current action is always true. The state comes from world.gd's
own `_mouse_locked`, the same flag it passes to `camera_rig.mouse_mode_for`, through `_sync_hud()`'s
snapshot (`"mouse_locked"`, plus `"gold"` from `read()`). Nothing else in world.gd changed. The HUD
writes no sim state. While the game is frozen (paused), the hint updates on the next step.

**Tests.** `test_hud.gd` is unchanged and passes. `test_hud_gui.gd` is new and covers:
- the gold reader on a real seed 42 / level 25 sim: hidden before the flip, the bitset exactly, a
  mine bit ignored, and no writes;
- the counter swap;
- a real `world.build()` and `step()`: the counter follows the sim, and the hint follows
  `_mouse_lock_pass` with the real CTRL edge in both states;
- bounds and no overlap for every panel at 1280x720 and 1920x1080 in both phases, with every row full
  and the warning up, plus a check that the content-sized panels fit their slots (574x102 and
  195x140, exact);
- built-in negative controls.

Mutation controls were also run by hand:
- warning back at y 100: 5 failures;
- the reader counts `black_taken`: 6;
- an inverted hint: 5;
- world feeds `mouse_locked: false`: 2.

All passed again once restored. The first full run caught two of my own breaks, and both were fixed in
the HUD code, not in the tests. The roster was 206x148, over test_enemy_stacking.gd's 200x140 limit.
The icon rows had lost the `Rows/CursesRow` node path that test_polish_cycle2.gd reads. The rows now
keep that path, and the panel is a backing sized by hand. `shot_hud.gd` adds hud_03 to hud_07 (black phase, gold phase,
collapse warning, 1920x1080, bottom zoom). Each shot checks the engine's own laid-out panel rects for
bounds and overlap, and they match the test's anchor math to the pixel.
## D-ATMO-1 (2026-11-21): a procedural cloud dome replaces the flat void colour behind the level

**Owner request.** "i actually prefer this lighting, skybox, and like the little rocks with the
contour around them floating in the sky, could u copy that?" (a reference screenshot of a pale
storm-cloud sky). Look only: no reference code was copied; the reference is another engine.

**Ruling.** `view/sky_dome.gd` is a 450 u sphere drawn from the inside with a spatial shader:
a horizon -> zenith gradient, a hard-edged billow layer (5-octave fbm value noise through a
narrow 0.42..0.62 smoothstep), a broad low-frequency dark mass in the lower sky and a
horizontal streak band. Render contract: unshaded, cull_front, depth_draw_never, fog_disabled,
shadows off, RENDER_PRIORITY_MIN, never culled, and the node follows the active camera every
frame. Its colours, radius and drift speed are data: `data/palette.json` "sky" (zenith #8F8B95,
horizon #4A464F, cloud #C9C5CF, cloud_dark #2A2630, drift 1.0, radius 450). The sky is one
block for every biome for now; the fog colour, density and every section 12.3 row are
untouched, so `tools/fog_check.gd` is unchanged (550 checks OK). Distant platforms fade into
the biome fog and read as dark silhouettes against the lighter sky. The palette schema
(`core/schemas/palette.schema.json`) gained strict `sky` / `debris` entries (the registry
refused the new keys); no existing schema rule was loosened.

## D-ATMO-2 (2026-11-21): floating contour rocks, inverted hull grown in screen space

`view/debris.gd` draws `count` (110) low-poly rocks in a ring 170..300 u from the level
origin (the widest level is 130 u), -70..+80 u in height. Each of 6 shapes per level is the
convex hull of 14 jittered sphere points (24 flat-shaded triangles); a rock is one of those
shapes with its own axis stretch, size (0.8..4 u, squared bias = mostly small), rotation,
tumble and bob. Placement and shapes are a pure function of `hash([seed, level])`; the motion
runs on `_process` wall time and the whole field orbits Y at 0.006 rad/s.

**Outline: inverted hull, not fresnel.** A 24-triangle flat-shaded rock has so few faces that
a fresnel rim lights whole faces, not an edge, and the reference look is a thin even contour.
The hull is a second MultiMesh of the same shape with cull_front and an unshaded outline colour.
It is grown in SCREEN space (`outline_width` = 1.6 px) in its vertex shader, because a
world-space grow is under a pixel at 170-300 u (measured in the first pass: the outlines did
not show). The hull is convex and centred, so the radial push opens no cracks. The outline is
#E6E2FF, a pale lavender-white: pink is reserved for the tripmine tell and #7CFFF4 for the
gift rim, so neither is used. Rocks are fog-disabled (at 200 u the 0.012 fog would erase them).
No collision node, no sim state: test_atmosphere.gd leg 5 hashes the sim per tick with the
atmosphere on and off and the hashes are identical over 240 ticks.

## D-ATMO-3 (2026-11-21): the ambient energy is read for the first time; ambient 1.0, void glow 0.3

**Found.** `fog_env.resolve_palette` copied only hex/emission (+ sigil/trim) per role, so the
ambient role's `energy` (2.6) never reached `configure()`: every level rendered with
`ambient_light_energy` = the 1.0 fallback. `energy` is now carried through.

**Ruling.** ambient energy 2.6 -> **1.0** (what the owner has actually been seeing, so fixing the
read changes nothing on screen, and the lobby antechamber's ambient x 2.0 stays 2.0) and
void_glow 0.55 -> **0.3**, so the level is dimmer and the emissive tiles, gifts and beacon are the
bright accents against the cloud sky (the reference mood). Fog check: unchanged (it reads no
light energy), FOGCHECK OK 550 checks over 5 biomes. Before/after shots:
`game/out/shots_atmosphere/{before,after}_{spawn,walk,horizon,sky}.png`
(`tools/shot_atmosphere.gd`).

## D-PLAYER-ANIM-1 (2026-11-21): interpolate the figure on the render clock

At 120 Hz with the 60 Hz world step, the original figure froze on all 50 sampled
frames without a sim tick. Its largest single-frame joint change was 0.186 rad.
The smoothness regression counted one failure. The world now captures adjacent
controller samples on its existing tick callback and evaluates the figure pose
on each render frame. It interpolates the root and yaw one tick behind the sim
and eases visible vertical changes at stair risers. Pausing freezes that clock.
Detached tools that explicitly drive the player view can still sample at 60 Hz.
The controller, terrain generator and serialized state stay independent of the pose.

## D-PLAYER-ANIM-2 (2026-11-21): articulate the existing meshes and plant the soles

The view derives thighs, shins, boots and forearms from the authored coloured limb
meshes at runtime. Grounded locomotion uses speed-dependent stride, cadence and
stance duration, counter-swinging arms, torso twist and a stabilized head.
Each stance keeps a fixed world-space sole position and heading. A two-joint
solve bends the swing knee and extends the stance leg. Body bob peaks at
mid-stance, with a separate idle breathing phase. Dash, glide, jump and fall
retain their target silhouettes and blend through the same render pass.

## D-PLAYER-ANIM-3 (2026-11-21): shorten and lift the gait on uphill ground

When grounded, sample the tile surface beneath the controller and ahead along
its horizontal velocity. Rising ground uses shorter, quicker strides, more
swing clearance and less body bob. Boot corners sample the tile surface at
lift-off, including the upper edge of a tread. Holding the landing target
through swing cut the largest measured stair thigh change from 1.399 to
0.339 rad per 120 Hz frame. On the test ramp, walk stride
shortened from 1.630 to 1.255 u and bob fell from 0.0240 to 0.0024 u. The
controlled tests exercise flat walking, flat running, a ramp and a 0.5 u
staircase. The capture tool uses separate fixed-camera walk, run and ramp
sequences at 30 samples per second.
## D-FRONT-1 (2026-11-21): one front-end style and one keyboard focus for every menu screen
**Renumbered at merge.** This ticket first wrote these five rulings as D-GUI-1..5, but the HUD ticket merged first and already holds D-GUI-1 on main. They are D-FRONT-1..5 here and in every code comment this branch touched, so the two tickets no longer share an id. No ruling text changed.

**Owner report.** "Work on the gui as well as its kinda bad." Each front-end screen invented its own
font sizes, margins, colours and button shapes (gold #FFC83D, indigo #02030F / #0D1229, grey-blue
#8B9EB7, rounded 10 px cards, 3 px borders, gradient scrims), and no two screens took the keyboard
the same way.

**Ruling.** `game/view/ui_style.gd` is the single source of the front end's look, and
`game/view/ui_focus.gd` the single keyboard focus. Every screen this ruling covers uses both: the main
menu (app/menu.gd + menu_howto.gd), the class altar, the pause overlay, the settings screen, the lobby
purse HUD and the loading screen's chrome. The in-game HUD (view/hud/*) is NOT covered; it has its own
owner.
- **Palette**: the five house teals (#0A2E30 deep, #1C6E70 mid, #2FB7B0 accent, #7CFFF4 bright,
  #8FE8E0 soft) plus pure white and pure black, at any alpha. Nothing else in the 2D chrome. BRIGHT is
  reserved for the focus ring; ACCENT is used sparingly (rules, the primary button's edge, RUN).
- **Type scale** (px at 1280x720): display 56, title 26, entry 20, body 15, small 13, label 11
  (tracked 2 px, upper case), mono numbers 15. Faces: the built-in fallback for text (D-MENU-9's
  reason stands), and the first installed monospace system face for numbers (Cascadia Mono, Consolas,
  DejaVu Sans Mono, ...) with the fallback's tabular digits behind it, so a purse never jitters.
- **Spacing**: 4 / 8 / 12 / 16 / 24 / 32 / 48; corner pills inset 24 px.
- **Shapes**: 1 px borders, 2 px corner radius, no shadows, no gradients. Buttons 40 px tall, 240 px
  wide by default. Every label carries a 4 px padding box, so no text touches its own rect.
- **Hierarchy**: PRIMARY (accent edge + faint accent fill, white text) for the one action a screen
  exists for (RESUME, CONFIRM), SECONDARY (mid edge, soft text) for the rest, GHOST rows for the main
  menu entries.
- **Focus ring**: a 1 px BRIGHT border with a 3 px BRIGHT bar on the left, on exactly one control.
  Tab / Shift+Tab cycle and wrap; Up / Down move; Left / Right adjust a focused slider; Enter / Space
  activate (never on a key repeat); Escape backs out where the screen owns it (the settings screen and
  the HOW TO PLAY panel; the pause and the altar keep app.gd's ESC). Controls keep FOCUS_NONE, so
  Godot's ui_accept can never double-fire (D-MENU-9's reason). The mouse moves the same ring on hover,
  except at the class altar, where hover must not select a card (a click selects, a second confirms).
- **Per screen**: the pause overlay shows LEVEL / PURSE as corner pills, PAUSED + rule as the focal
  column, RESUME first and focused on open, SETTINGS, then ABANDON RUN last. The settings screen is one
  panel of rows (tracked caption, control, value in mono); each row is one focus stop. The altar's
  Tab walks the cards, then CONFIRM, then SKIP; Enter on SKIP skips. The lobby purse is a corner pill
  pinned to the top-right edge. The loading screen keeps its gag stage (D-LOAD-1's register) but its
  backdrop is the flat house void (no gradient), its motes and floor are house teal, and the bar is a
  flat 6 px accent fill in a 1 px mid frame.

**Supersedes.** D-MENU-9's gold selection colours and indigo panel (the selection's four cues stay:
text colour, left bar, faint fill, indent); D-LOAD-1 / D-LOAD-6's pink bar, pink FIELD NOTE header and
indigo gradient (the gags' own colours stay); the lobby prompt bar's indigo slab #2E2E4A / edge #5A5A82,
now #0A2E30 / #1C6E70 (its gold / danger price colours stay - test_lobby_defects pins them, and they are
world semantics, not chrome); menu_howto.gd's gold / red / pink bbcode, now accent headings and white
emphasis (the words still say "gold" and "pink").

**Measured.** New `tests/test_ui_style.gd` checks, on every covered screen with the longest real
strings loaded (a 3-digit level, a 6-digit purse, the longest class name with its "(last)" mark, all 30
loading tips, the slider extremes): every Label / Button text fits its own rect with >= 4 px on all four
sides and stays inside its panel and on the 1280x720 screen; every interactive control is >= 32 px
tall; Tab focuses each control in turn with exactly one focus ring, wraps, and Shift+Tab walks back;
every colour override, flat stylebox, ColorRect and bbcode colour is in the palette; no gradient
textures; plus Escape / Enter legs and the longest enemy / curse / upgrade names on the lobby's prompt
bar. Negative control: the final test against the untouched screens (33d447e) fails **216** checks
(palette 159, fit 46, slider height 3, no shared focus on 4 screens, key legs 3, all 30 tips 1);
against this branch, **0**. The longest names on the prompt bar: enemy "gin ichimaru" scale 1.000,
curse "Quarter Chimes" 0.973, upgrade "Radar Module: Threats" 0.680 - all inside the text box; the
floor is 0.5 (the bar's name reads ~22 px at camera distance, so 0.5 keeps it at the type scale's
smallest size, 11 px). Nothing in an existing test was deleted, skipped or loosened.

## D-FRONT-2 (2026-11-21): the menu island wears the house teal act (supersedes D-MENU-2's biome pick)

**Ruling.** app/menu_stage.gd picks its biome by void colour; VOID_HEX is now #010B0C (data/palette.json
`void`, the Deepwater act) instead of the indigo #02030F, and CARD_GRADE is a slightly teal
(0.80, 0.93, 0.91) instead of the indigo-cool grade. The pick is still by palette field, never by id.
**Why.** The owner fixed the house palette as teal; an indigo island behind teal chrome read as two
games. D-MENU-2's glow, beacon key light and roster layout are unchanged. The roster's danger-line
captions stay red (D-MENU-6: they are the in-game danger text, shown in the world, not chrome).

## D-FRONT-3 (2026-11-21): Enter stays inert on the main menu; Tab and the arrows join it

**Ruling.** The brief asks for Enter / Space to activate on every screen. On the main menu, Space (the
jump binding) and F confirm as before, and Tab / Shift+Tab and Up / Down now walk the entries - but
Enter still does nothing. test_menu.gd asserts exactly that ("Enter is not the game's confirm: it must
do nothing", D-MENU-9), and existing tests are not loosened. Every other screen takes Enter.
**Overrule** by changing that assertion in test_menu.gd and adding KEY_ENTER to menu.gd action_for_key().

## D-FRONT-4 (2026-11-21): the pause overlay draws on its own canvas layer, above the HUD

**Ruling.** The overlay's content lives on a CanvasLayer at layer 129 - above the level HUD (1), the
run-over screen (2) and address_me_view's overlay (128). The overlay Control itself still owns
`visible` / is_open() and keeps its layer in step. **Why.** The screenshot pass showed the in-game HUD
drawing OVER the pause overlay (its gift icon on top of the LEVEL pill, its 0 / 40 counter across the
key hints): a pause has to dim the HUD, not sit under it. test_ui_style sizes the root viewport to
1280x720 while it measures, because a canvas layer lays out against the viewport, which --headless
leaves tiny.

## D-FRONT-5 (2026-11-21): the cursor on menu screens is still written by world.gd alone

**Ruling.** No front-end file writes Input.mouse_mode. test_input.gd pins world.gd as the only writer
under app/, and the existing paths already free the cursor on every menu screen: world teardown on the
way to the menu, apply_mouse_mode() when the altar opens and when the pause opens, lobby_scene's own
release, and the capture comes back only when play starts (test_class_altar_pick asserts both ends).
shot_gui.gd prints the mouse mode on the menu and on the pause: 0 (visible) on both.

## D-ANIM-1 (2026-11-22): the legs are rigid; an out-of-reach foot is missed, never stretched to (supersedes D-PLAYER-ANIM-2's "extends the stance leg")

**Root cause of the owner's "legs merged into one long diagonal wedge" (bad_leg_pose.png).** The old
`pose_leg()` in view/player_locomotion.gd let the shin grow past SEGMENT whenever the hip-to-ankle distance
passed 2 x SEGMENT (`extra` > 0, `shin_length` > SEGMENT), then scaled the shin mesh along its axis by
`knee.distance_to(ankle) / SEGMENT`. The new rigid-geometry test measured the old rig: the shin scaled by up to
3.65x and a leg bone changed length by up to 1.13 u on 1 HU stairs, and by 0.25x on a flat run. `pose_arm()`
was checked as well and is not detached: the forearm is a child of the upper arm and follows it.
**Ruling.** Every thigh, shin, boot and forearm is placed by a pure rotation; no basis carries scale. The two-bone
solve clamps the reach: past REACH - SOFT (0.62 - 0.06 u) the reach eases toward full extension instead of
snapping the knee straight, and an unreachable target is missed along the hip-to-target line. A planted foot that
falls out of reach (RELEASE = REACH - 0.025 u) or crosses its lane lifts off early instead of dragging the leg
longer. A sole drawn up within MIN_FOLD (0.24 u) of the hip is pushed out forward-down rather than letting the
leg spin about a target on the hip joint. **Overrule** by changing the constants at the top of
view/player_locomotion.gd; test_player_anim.gd leg 6 pins the rigidity.

## D-ANIM-2 (2026-11-22): the figure keeps its facing; the feet step along the actual velocity

**Ruling.** The landing for each swing is committed at lift-off along the actual horizontal velocity, so
backpedalling, strafing and diagonals step the right way while the body keeps the camera's facing. Planted-foot
travel per stance is capped per direction (REACH_FORE 0.25 u forward/back, REACH_SIDE 0.13 u sideways, an
ellipse between), which sets the stance share (duty); sideways movement raises cadence by up to 30 % and widens
the stance by 0.05 u. A foot never comes nearer the body midline than LANE (0.035 u), and only the LEADING knee
turns outward toward a sideways step (up to 0.45 rad); the trailing knee stays forward. Turning in place: a
planted foot holds its spot for 0.55 rad of body turn, then pivots with the body; an idle foot off its rest spot
by 0.07 u, or twisted 0.30 rad, re-plants with a 0.22 s step, one foot at a time. **Why.** Measured on the old
rig, the legs crossed the body midline by up to 0.30 u when strafing.

## D-ANIM-3 (2026-11-22): the run shape (crouch, heel kick, lean, airborne knees)

**Ruling.** The hips sit 0.05 u lower at a full run than at a walk (the bob's mid-stance peak then leaves the
stance leg inside its reach). Running adds a heel kick: the swing foot rises up to 0.15 u behind the body early
in the swing instead of trailing straight back along the ground, which read as one long block in the first
contact sheet. The forward run lean applies to forward running only; a backpedal leans back at up to 0.35 of
it, a strafe stays upright, and the torso twist fades by 70 % sideways. Airborne poses gain knee flex (`knee_l` /
`knee_r` in POSE_EXTRAS): jump tucks (1.35 rad), fall bends both knees with one raised (thighs -0.20 / +0.30,
knees 0.85 / 1.20; the old -0.35 / -0.10 straight legs overlapped into one column from the side), dash lunges
(thighs -0.45 / +0.60), glide trails (knees 0.35 / 0.75). The existing pose-static tests still hold (jump legs
equal and positive, fall leg_l negative, every jump/fall pair 0.2 rad apart). Any airborne or dash leg is kept
above the floor under the figure (a pointed boot reaches 0.14 u below its ankle).

## D-ANIM-4 (2026-11-22): stairs and ramps move the body, not the leg length

**Ruling.** (a) The body height eases to the sim feet with ANIM_RISE_TIME 0.085 s (was 0.038 s), so a 0.5 u
riser no longer yanks the hips a third of the way in one 120 Hz frame. (b) The climb rate is read from the ground
across one unit of course centred on the body times the ground speed (the controller snaps its feet onto treads
and keeps vy at 0), low-passed over 0.10 s and fed forward, so the hips climb a ramp or a 1 HU flight WITH the
feet instead of lagging up to 0.38 u below them at 9 u/s. (c) A planted sole the hips have caught up on, or a
swinging sole held up by a tread near hip height (SWING_DROP 0.27 u), raises the hips at up to 5 u/s; they settle
back over 0.12 s. (d) A swinging sole is held above a clearance envelope of the ground sampled along its path at
lift-off (9 samples, 0.05 u clear, 0.24 u footprint plateau, rising 1.2 u per u ahead and dropping 3.5 u per u
behind). Where the ground already forces the foot up, that clearance replaces the lift arc instead of adding to
it; a riser right in front of the lifting foot holds the travel while the foot rises; a swinging sole never
passes down through a surface it was over last frame and lowers at most 7 u/s. (e) The landing search reaches
0.51 u plus 0.55 u per u of stride above the body's tread (it stopped at 0.51 u, so a long stride up a ramp
planted the foot INSIDE the slope). (f) Grade detection no longer reads the sim's vy (always 0 on the ground).
Slopes lower the hips by 0.10 u uphill and 0.06 u downhill; the climb adds only 0.04 rad of lean (was 0.12).

## D-ANIM-5 (2026-11-22): the rigid-geometry gate and its tolerances

**Ruling.** test_player_anim.gd leg 6 drives all 16 contact-sheet poses through the REAL controller on a staged
course (flat, a 1:2 ramp, 1 HU stairs, all 25 u wide) and checks EVERY 120 Hz render frame: each leg bone within
0.002 u of 0.31 u and every leg segment and forearm at unit scale within 0.001; the forearm one upper-arm length
below the shoulder within 0.002 u; knees never hyperextend (hinge sign) and fold at most 2.75 rad; elbows never
invert; no sole corner more than 0.005 u under the tile surface beneath it; knee and ankle never inside the torso
block shrunk by 1 cm; the shin midpoint never inside it shrunk by 3 cm (the thigh enters the torso at the hip by
design, and the leaning block's lower front edge grazes a raised shin by 2-4 mm); the left knee and ankle stay on
the body's -x side and the right on +x; and the controller trace (position, velocity bit-exact, grounded,
gliding, dash ticks) is identical with the animation pass on and off for every pose. Negative control: the same
file run against the previous animation (77661c5's player_locomotion.gd + world.gd) reports 40 failures
(stretched/scaled legs on all 16 poses, midline crossing on both strafes and the diagonal, soles in the floor on
ramps, stairs, landing and dash). Legs 1-5, the smoothness gate and the gait gate are unchanged and pass.

## D-ANIM-6 (2026-11-22): the contact sheet is the visual proof

**Ruling.** tools/shot_player_anim.gd (windowed, one absolute out dir, optional pose name) renders the 16 poses
(run forward / backward, strafe left / right, diagonal, turn in place, up / down ramp, up / down 1 HU stairs,
jump, land, dash, glide, idle, plus a walk) from two fixed-offset cameras, side-on and rear three-quarter (the
owner's angle), 10 frames over one gait cycle for the cyclic poses, with the pose name and frame burned into every
PNG and one labelled sheet per pose. It shares the course staging with the test (test_player_anim.gd `stage`,
`tick`, `warm_up`, `buttons_at`), so the sheet and the gate show the same motion.

## D-ANIM-7 (2026-11-22): the review gate - independent floor oracle, full volume, full sim state

**Why.** The independent visual review of v0.1.13-alpha.3 objected to down ramp, up stairs, down stairs and land,
and named gaps in test_player_anim.gd leg 6. **Ruling.** Leg 7 (`_check_review`, `_judge_pose`) runs on every
120 Hz frame of all 16 poses, next to leg 6 (unchanged, no check weakened):
(1) every limb part's global basis is orthonormal and right-handed (axis lengths, pairwise dots and det - 1 within
0.001; leg 6's scale check alone cannot see a shear). (2) The floor check against an ORACLE independent of the
animation's sampler and of the controller: `course_floor` reads the staged tile table directly (flat: hu x 0.5 u;
kind 4: +0.5 u falling to its +z edge). Old: only the 4 sole corners, and a tile counted only if its top was within
0.3 u above the corner (a deeper sink was invisible). New: all 8 boot corners and all 8 shin corners, no depth cap,
0.005 u tolerance (unchanged value). (3) A planted sole (stance, full contact, 0.07 s past a touchdown) rests on the
highest oracle ground under its sole corners: not below it by more than 0.005 u, not above it by more than 0.012 u
(physical reason: a planted foot is released at RELEASE = 0.595 u, where the soft reach falls 0.0084 u short, plus the
0.002 u plant clearance; the shin-peel lift of D-ANIM-8 is bounded by it too). Each stance start is a landing; each
1 s descent must show at least 6 (the v0.1.13 down ramp showed 0: its feet never planted). (4) Land: the hips (above
the oracle floor) must drop at least 0.12 u below both the last airborne frame and the run_forward mean within 0.15 s
of touchdown, and end the span within 0.04 u of the run mean. (5) The torso check covers the FULL volume of each
thigh, shin and boot (a 3 x 5 x 3 grid of its exact box; the parts are 8-vertex boxes) - see D-ANIM-9 for its limits.
(6) Purity: the animation-off comparison now also hashes EVERY script variable of the controller (floats as IEEE bits
through sim/state_hash.gd's `bits`) and the collision world's `removed` table per tick. The staged worlds have no
LevelState/RunState, so `Hash.sha256` itself is not reachable there; the built-level purity leg runs it and the full
controller hash together. **Negative control:** the strengthened file run against 77661c5's player_locomotion.gd +
world.gd fails 68 checks (the same 40 as D-ANIM-5, plus 28 new: non-orthonormal bases, soles and shins under the
oracle surface, soles through it, legs inside the torso, a too-shallow touchdown).

## D-ANIM-8 (2026-11-22): a controlled descent - the body sits on the slope and follows the leading foot down

**Root causes found by the D-ANIM-7 checks.** (a) The sim stands its 0.8 u footprint on the HIGHEST ground under it,
so on a 1:2 ramp the drawn body rode 0.2 u above the slope under its centre; (b) the climb feed-forward's uphill sample
had a +0.05 u height limit, exactly where that ground sits going down, so it read 0 and the body lagged a further
0.1-0.2 u; (c) pose_leg clamped every foot above the floor under the body's CENTRE (meant for airborne legs), lifting
a foot planted downhill or on a lower tread off its ground. Together the v0.1.13 down-ramp legs hung at full reach and
never planted. **Ruling.** The drawn body is seated on the ground under its centre going downhill (at most
ANIM_SEAT_MAX 0.22 u, scaled by the descent weight); both feed-forward samples reach 0.55 u up; the floor guard uses
the floor under the foot's own sole while the gait places it (the centre floor only for airborne/dash legs). The
descent quickens the cadence by up to 55 % (eased over 0.25 s so no foot changes stance in one frame), no longer
shrinks the stance share, drops the heel kick 80 % and crouches 0.10 u (was 0.06). A planted foot more than
STANCE_REACH (RELEASE - 0.04 u) from its hip lowers the hips (at up to 12 u/s, settling back over 0.12 s) - the body
follows the leading foot down; a foot set down on its landing holds 0.05 s before reach can lift it, but only if it
is already down (within 0.05 u, a normal swing's last frame); a foot still being lowered off a ledge is released as
before, since holding it snapped the thigh 0.46 rad in one frame on level 1. Going down, a swinging foot lowers at up
to twice MAX_DROP. A planted foot whose solved shin block would reach within 0.004 u of the tread peels off, and the
drawn shin's lowest corner is held 0.002 u above the floor under the foot (a tightly folded leg sank 1.2 cm). A
trailing foot's fold step-up is scaled out on descents (it held the hips up against the leading foot).

## D-ANIM-9 (2026-11-22): legs against the torso - fixed where the pose was wrong, a disclosed residual where the proportions are

**Finding (objection 2).** The full-volume check shows the up-stairs "dark block" was a real 3D intersection, not only
a 2D overlap: on 1 HU stairs at a run the raised thigh went 0.137 u into the torso and a boot 0.057 u; on a flat run
the swinging shin went 0.08 u into it. Cause: the leaning torso pivots on its bottom centre, so its front-bottom edge
drops onto a thigh raised to level, and the heel-kick fold put the knee forward at waist height with the shin running
back under the body. **Fixes (torso pivot unchanged, the shoulder-attachment test still passes).** SWING_DROP 0.27 ->
0.36 u, now also a ceiling: a swinging ankle stays 0.36 u below its hip, the ground permitting (then the body steps
up, as before); on stairs and slopes the run lean eases to 0.4 of itself. Worst now: boots 0 (none in any pose),
thigh past its socket 0.030 u (up stairs, land), shin 0.062 u (down stairs). **Residual, disclosed, NOT a pass.**
The hip joint sits 0.166 u inside the torso (HIP_RISE) and the thigh is 0.31 u, so a straight knee is only 0.144 u
below the torso's bottom face; once a thigh rises past ~50 degrees, the knee's block corners (shin half-depth
0.104 u) enter the torso's bottom. The authored airborne poses do it too (jump/glide tuck 0.024 u). It cannot be
removed without changing the approved figure (a shorter thigh, or a lower hip socket that makes the drawn figure
shorter), which is the owner's call. The gate therefore pins: boots <= 0.01 u inside the torso (D-ANIM-5's 1 cm face
margin), thighs past the socket and shins <= 0.065 u (TORSO_LEG_TOL, a regression ceiling just above the measured
0.062 u worst; it catches the v0.1.13 0.137 u thigh). **Overrule** by approving a proportion change, then tighten
TORSO_LEG_TOL.

## D-ANIM-10 (2026-11-22): the landing is a compression, and the land sheet actually contains it

**Root cause (objection 4).** warm_up pressed jump 30 ticks before its end and the jump came down INSIDE the warm-up,
so the land sheet began 0.24 s after touchdown and showed only the following run. **Ruling.** warm_up (shared by the
gate and the sheet tool) now jumps after the run-up and stops 3 ticks before touchdown. The dip is LAND_DEPTH 0.20 u
(was 0.11 u): down in LAND_DOWN 0.07 s, eased back up by LAND_TIME 0.42 s (was 0.30 s); the chest pitches 0.18 rad
further forward and the arms come forward with it. At touchdown the gait restarts with the left foot at the start of
its stance (the old phase left both feet mid-swing for 0.1 s, so nothing took the weight), the cadence slows 30 % and
the heel kick is held back while compressing; a touching-down foot lands 0.025 s of travel ahead of its hip and holds
0.06 s before reach can lift it; the fall pose carries its hips 0.10 u low (knees braced) so both soles are in reach on
contact; the airborne tuck is shed over 0.05 s. Measured: hips 0.711 u above the floor on the last airborne frame,
0.469 u at the deepest, 0.624 u at the end against a 0.602 u run mean.

## D-ANIM-11 (2026-11-22): contact-sheet framing a reviewer can judge

**Ruling.** Ground poses follow the figure's height exactly (the lagging camera dropped the feet off the frame on
descents). Ramps and stairs are framed 3.1 u wide (was 2.4), centred 0.70 u up, the side camera looks down ~20 degrees,
and the course is DRAWN only 3 u wide (collision unchanged), so the slope or stair profile is a silhouette under the
feet instead of a wall of treads behind them. Every sheet gains a third row: "downhill" (low, from the downhill side)
for descents, "xray" (torso and arms see-through) for climbs, else "front". The land sheet carries a red bar at the
running waistline.

## D-ANIM-12 (2026-11-22): the torso hem guard; TORSO_LEG_TOL 0.065 -> 0.035 u (supersedes D-ANIM-9's ceiling and D-ANIM-10's chest pitch)

**Finding (objection 2, re-measured).** The leg-6/leg-7 full-volume check finds NO limb point inside the back half
of the torso block in any pose, and no boot inside it at all (torso_boot 0 everywhere). The "dark block over the
back of the torso" in the up-stairs rear frames was therefore the trailing leg's raised shin and boot projected over
the back from the high rear camera (a 2D overlap); with SWING_DROP 0.36 (D-ANIM-9) it no longer shows in the re-shot
rear row. The REAL intersection was elsewhere and was not visible from that angle: the knee block's top-rear corner
tucked under the torso's FRONT hem, up to 0.062 u (down stairs), 0.06 u (up stairs), 0.046 u (flat run) - a high
swing knee (ankle within ~0.33 u of the hip) puts the knee joint level with the hem and the 0.104 u half-deep shin
block corner rises into it. **Ruling.** (a) pose_leg's hem guard (view/player_locomotion.gd HEM_CLEAR 0.02 u): a
leg that is not bearing weight (swinging, or airborne) is straightened away from its hip until its thigh (past the
0.166 u socket buried at the hip by design) and shin blocks are within 0.02 u of the torso block; where the floor
stops it straightening, the foot trails back (the hem is highest at the back of a forward-leaning torso). A planted
foot is never moved. The torso pivot is unchanged; the shoulder-attachment test passes. (b) Land: the chest comes
HALF UPRIGHT during the compression (torso x (1 - 0.5 x landing)) instead of pitching 0.18 rad further forward
(D-ANIM-10): the extra pitch dropped the hem onto the deep-bent knees (0.044 u). The compression still reads (hips
0.711 -> 0.469 -> 0.624 u, run mean 0.602 u). (c) TORSO_LEG_TOL 0.065 -> 0.035 u. Measured worst now: shin 0.0333
(diagonal), 0.0332 (dash), 0.0246 (down stairs), 0.021 (up stairs), 0.0233 (flat run); thigh past socket 0.0226
(dash), 0.019 (up stairs); boots 0. **The residual is disclosed, not hidden.** The remaining 3.3 cm is where a leg
already reaches almost straight (0.50 of 0.56 u) to a foot the floor holds, under a torso leaning 0.24 rad (diagonal
run) or 0.67 rad (dash): straightening is blocked, and raising the hips was tried and does not help (a near-straight
leg's knee barely drops). 0.035 u is a regression ceiling set 1.7 mm above that measured worst, NOT a value derived
from first principles; it still fails the old 0.062 u stairs knee and the v0.1.13 0.137 u thigh. Clearing it fully
needs a proportion change (shorter shin block or a lower hem) or less dash/run lean - the owner's call.

## D-ANIM-13 (2026-11-22): boots lie along a slope; the support check reads each sole corner

**Finding.** With the D-ANIM-8 descent in place the down-ramp side frames (re-shot level, D-ANIM-14) still showed
each planted boot touching the 1:2 ramp only at its uphill edge, its toe 0.10-0.12 u above the slope: the boot
was drawn level (yaw only). **Ruling (view only; the rig stays rigid).** world.gd samples the ground 0.1 u around
each sole (Locomotion.slope_at: a plane, grade 0.01..0.6, no step between samples; a stair nosing or a ramp's foot
is not a slope). On a slope a grounded boot is rotated about its ankle to lie along it, and a planted one is seated
with its lowest corner 0.002 u over the slope plane (pose_leg `_seat`); the shin floor guard reads the same plane.
The seated sole sits `seat_drop` below the gait's level-boot plant, so: the release check judges reach from the
seated height (a seated foot hung out of reach and slid 2.6 cm on the uphill walk); the hips sit lower by half a
boot length times the grade (0.059 u on 1:2), read from the ground under the body and eased over 0.25 s (snapped on a
view reset), so it adds no bob (uphill walk bob 0.0065 u, unchanged); the fold step-up and the swing step-up read the
seated heights (read level, they added 0.02 u of bob). **Test (test_player_anim.gd).** (a) Leg 7's planted-sole gap
is now the SMALLEST height of a bottom corner over the oracle ground directly under that corner. For a level boot
(all four corners at one height) this is exactly D-ANIM-7's "lowest corner over the highest ground", so nothing is
weakened; a boot along a ramp now measures its real contact. SUPPORT_TOL 0.012 u and the 0.005 u through-limit are
unchanged; every corner is still held above its own ground by the deep-floor check. Measured: down ramp 0.002,
up ramp 0.0052, worst any pose 0.0117 u (diagonal). (b) Leg 6's floor check searched for ground only up to 0.3 u
above each sole corner, so a deeper sink found no surface and passed: FLOOR_REACH 0.3 -> 2.0 u (four risers; the
staged courses hold one tile per column, so no overhang can be mistaken for a corner's floor). Both checks pass.

## D-ANIM-14 (2026-11-22): framing - a level side view over a narrow course (supersedes D-ANIM-11's 20-degree side camera and 3 u course)

**Finding.** D-ANIM-11's ramp/stair side camera looked down ~20 degrees (its offset sat 1.25 u above its aim
point) over a 3 u wide drawn course: a sole standing mid-tread was drawn
up to 0.13 u BELOW the tread's near edge, so tread contact still could not be judged from the sheet, and the land
sheet's red bar ran across the figure, so the side view saw it end-on. **Ruling (tools/shot_player_anim.gd only).**
On ramps and stairs the side camera is level with its aim point (offset y 0) and the course is DRAWN 1.2 u wide (the
figure is 0.54 u wide): the stair or slope profile is a silhouette and a planted sole sits exactly on its outline.
The land bar is a cross (one bar across the figure, one along it) so the side and the rear view each read it as a
line. Collision is unchanged (the staged tile data). **Re-shot and read:** all 16 sheets, 3 rows x 10 frames; feet
in frame in every frame of every row. **Negative control** for the D-ANIM-12/13 test: the file run against 77661c5's
player_locomotion.gd + world.gd fails 72 checks (D-ANIM-5: 40, D-ANIM-7: 68).
## D-JUMPPAD-1 (2026-11-22): jump pads are placed by a new terrain module beside the walkway's middle line

**Ruling.** Jump pads are a NEW entity, separate from the generator's launch pads (`W.pads`, level `pads`, the
canonical `X` line, `controller._try_launch_pad`), which are untouched. Placement is
`game/terrain/jump_pads.gd` `place_jump_pads(L, cfg)`: a pure function of the packed Level dict, run after
`voidgen.generate()` (world.gd's level build and bot_run.gd call `attach(L)`), stored as `L["jump_pads"]`. It draws
from its own VoidRng stream, `mix(base, 0x4A504144)` where `base` is the generator's own per-attempt base, so the
level hash still determines the pads while `to_text()` - and so PARITY 56/56 and GALLERY_PIN 16/16 - is unchanged
(test_jump_pads asserts the hash and text are identical before and after `attach`). The owner's "next to paths,
never on them" is read as: the route is a straight 3-wide walkway's middle column (the generator's own `o == 0`
column, read off the piece bbox: the axis whose extent equals `w` is the width; a square or non-straight walkway
is skipped) plus any GEN 4 centre-lane tile; a pad goes on the lane one tile to the side, with the route tile
right next to it at the same height. "Never on stairs" bars the `stair` arch (TERRAIN_SPEC's "jump stairs", 2 HU
risers) and `ramp` walkways and any tile with a riser of more than 1 HU beside it on its piece; the `step` arch
("stepped climbs", 1 HU risers the auto step-up walks) is allowed - excluding it too left 31 of 40 probe levels
without a single pad. Also barred: the hub piece and beacon, gift and tripmine slots and the 8 tiles around each,
launch pads and their landing tiles and the 8 around each, a tile with a prop, overhead geometry within 18 HU in
the 3x3 columns. Count by level (1 / 2 / 3 / 4 from levels 1 / 3 / 6 / 10), at most one per walkway, >= 12 tiles
apart. Measured on seeds 1/7/42/99/123 x levels 1/2/3/5/8/12/20/30: 40 of 40 levels get their full count.

**Why.** The generator is frozen and hashed; a pure post-pass keeps every pin while still being level data.
The first rule (any non-route tile 4-adjacent to a GEN 4 centre-lane tile) was caught by the test's independent
bbox checker putting pads on the middle line where the GEN 4 test fails (a row next to a gap or prop), so the
lateral-axis rule replaced it.

## D-JUMPPAD-2 (2026-11-22): the fling is 20 u/s straight up, horizontal momentum kept [CONTESTABLE]

**Ruling.** `data/jump_pads.json` `launch_speed` 20.0: apex v^2/2g = 6.25 u under gravity 32, about 1.25 s to come
back to the pad's height. A normal jump is 12 u/s = 2.25 u; a `stair` walkway climbs at most 3 u, so 6.25 u is
"about two stair runs" of height plus air time worth using (a glider gets 1.25 s up before it can deploy). `vx` /
`vz` are not written. The pad fires for a grounded player whose feet are on the pad tile's top and whose centre
is inside its cell, on the sim tick after the controller step (the slot MinesScript.tick runs in).
`jump_pad_launch` also clears `coyote` and `buffer`: a coyote jump in the next 0.1 s would otherwise REPLACE the
fling with 12 u/s.

**Why contestable.** "About 2 stairs-worth" could also mean two 1 u stair risers (2 u), which is below a normal
jump and could not be the intent; one number in data flips it.

## D-JUMPPAD-3 (2026-11-22): the refill list lives in controller.jump_pad_launch()

**Ruling.** Refilled: `air_jumps` -> `air_jumps_max`; `dash_ready` true, `dash_cd` 0; `bonus_dashes` ->
`bonus_dashes_max`, `bonus_cd` 0; `glide_energy` -> `_glide_max()` (base + `glide_energy_bonus`); `updraft_ready`
-> `updraft_owned` (an unowned glider is NOT granted the rise, D-T053-6), `updraft_cd` 0, `updraft_used` false;
`lock` 0 (the owner's list). NOT touched: `charges` / `charge_cap`, gold (not controller state),
`barrier_shields`, `last_light_spent`, `invuln`, Field Dressing. `ControllerScript.JUMP_PAD_REFILLS` names the
list; test_jump_pads checks every row on all three kits, and its negative controls prove the checker reports all
8 rows on an un-launched controller and catches a launch that also refilled charges and the shield.

**Review objection declined (2026-11-22, Terra / gpt-6.1-terra xhigh, finding 3).** Terra objected that
`jump_pad_launch()` resets `updraft_used`, which is outside the owner's expressly exhaustive refill list, that the
test requires the extra reset and so reinforces the deviation, and asked for the write to be removed or the
requirement changed. Declined by the orchestrator: the write stays, as a SAFEGUARD rather than as what makes the
rise work today. The rise in `controller.step()` is gated on `updraft_ready ... and not updraft_used`
(controller.gd:475), and the glide-engage block already clears `updraft_used` on every fresh glide engagement
(controller.gd:458) while a launch ends any glide - so the rise would still be usable without this write, and
removing it fails only test_jump_pads' flag row, not the new usability leg. The write is kept so the refill is
self-contained instead of resting on that coupling: a future change to glide engagement cannot then silently
leave the rise flagged but unusable. The `JUMP_PAD_REFILLS` comment says the same.
test_jump_pads now also asserts the rise is USABLE after a pad: a drained glider that owns it is flung, presses
jump on falling ticks (spending its refilled air jumps) and must fire `updraft_rise` exactly once before landing;
negative controls: the same flight with the rise drained again after the launch, and an unowned glider, fire 0.

## D-JUMPPAD-4 (2026-11-22): per-pad re-arm in integer ticks, hashed; the collapse takes pads with their tiles

**Ruling.** `game/sim/jump_pads.gd` (LevelState `jump_pads`, built from `L["jump_pads"]`, null when the key is
absent): `ready_tick[i]` = the first tick pad i may fire again, set to `tick + rearm_ticks` on firing
(`rearm_s` 0.5 -> 30 ticks); `lost` bitset. state_hash.gd dumps `JUMPPADS <ready csv> <lost hex> <rearm_ticks>
<launch_speed bits>` only when the level carries pads, so every dump of a level built without them is
byte-identical (the random-input replay and every older fixture). world.gd's `_collapse_sweep` calls `sweep()`
with the fallen keys (a pad goes down with its tile and never fires again); a tile a curse removes for a while
hides the pad and stops it firing (`tile_alive`) without losing it. No RNG at runtime.

**Amended (2026-11-22, Terra review findings 1 and 2).** (1) The world and bot paths copy the controller into
`lv.players[0]` before the pad tick, so a launch left the hashed row grounded with its old velocity until the next
tick. `JumpPadsScript.tick` now writes `vx / vy / vz / grounded` back into `lv.players[i]` after it fires
(`_sync_row`), which fixes both callers at once; test_jump_pads `_launch_tick_row` checks the launch-tick row
and hash against a controller-synced row. (2) Placement depends on data/jump_pads.json (count, spacing), which the
level hash does not cover, so the line is now `JUMPPADS <pads x:z:y csv> <ready csv> <lost hex> <rearm_ticks>
<launch_speed bits>` with the coordinates in pad id order; `_hash_positions` checks that a moved pad and a swapped
placement order both change the hash at an unchanged level hash and pad count. A level without pads still writes
no JUMPPADS line, so its dumps are unchanged.

## D-JUMPPAD-5 (2026-11-22): the pad view and the boing

**Ruling.** `game/view/jump_pad_view.gd` (wired at world.gd's level build and view pass only; none of the
animation functions D-ANIM-* owns are touched): a procedural rounded-square slab 0.84 u wide, 0.16 u tall,
0.22 u corner radius with a 0.07 u soft top bevel, 0.012 u above the tile, saturated glossy semi-transparent blue
`#1A2BFF` (alpha 0.8, clearcoat, rim, emission 0.9 armed with a 1 Hz pulse / 0.2 while re-arming;
palette.json `jump_pad`). Everything animated derives from the sim state and tick (no view clock): the slab
squashes to 35 % in 0.06 s and springs back through ~1.19x (settled by 0.9 s), two additive rings ripple from
0.45 u to 2.1 u over 0.45 s. Audio: `player/jump_pad` (synth_cues.gd seed 24, 0.55 s) - a 140 -> 620 Hz
rising sine with a decaying 26 Hz wobble over a 70 Hz thump, played on the `jump_pad_launch` event. No
first-use hint (optional in the spec). Screenshot proof: tools/shot_jump_pad.gd (windowed).

## D-T2-1 (2026-11-23): the tester panel is compiled OUT of the public build, three layers deep

**Ruling.** The owner's words: "tester build with debug panel (owner only, never in public releases)". The
panel is one folder, `game/view/tester/`, and it never reaches a public build by any of the three routes:
(1) PACK: the three public presets in `game/export_presets.cfg` (0 Windows Desktop / 1 Linux / 2 macOS)
carry `exclude_filter="view/tester/*"` per preset block, so nothing from the tester folder
is inside a public pck. (2) CODE: `game/app/app.gd` `_try_load_tester_panel()` is the only loading site in
the game - `load()` (runtime), never `preload()` (compile-time), behind `OS.has_feature("tester")`, which
no public preset sets (`custom_features=""` on 0/1/2). A public build holds the dead branch but no file to
load and never executes it. (3) CI: `.github/workflows/build.yml` names the three public presets by hand in
its matrix, so the "Tester" preset cannot be picked up; a one-line comment at the matrix states this.
`game/tests/test_tester_build.gd` pins all three: the exclude_filter line per preset, zero `preload(`
references to the panel anywhere with the `view/tester/` path, the load living in app.gd BEHIND the
feature-gate line, and `preset: Tester` never appearing in the workflow.

**Review round 1 wording correction (2026-11-23, Terra xhigh: "ADOPT WITH FIXES").** Earlier drafts of this
entry, the README and the panel header claimed the public build contains "no reference at all" to the
panel. Inaccurate: `app.gd:156` holds ONE GUARDED REFERENCE - the `load("res://view/tester/debug_panel.gd")`
call - whose branch can never run in a public build (the feature tag is absent and the file is not in the
pack). All four documents now say "guarded reference", the honest claim the review asked for.
**Why contestable.** Not contestable: this is the brief's own requirement, implemented literally.

## D-T2-2 (2026-11-23): no panel scene - the layout is `_init`-built, like the pause overlay

**Ruling.** The brief says "the panel scene and script must not be exported". There is no scene:
`view/tester/debug_panel.gd` builds its whole layout in `_init` (widgets only, UiStyle helpers) - the
`view/app/pause_overlay.gd` and `view/hud/run_over.gd` precedent, which exists exactly so screens can be
constructed and asserted headless. The `exclude_filter="view/tester/*"` covers the folder, so a scene
added there later is excluded by the same rule. The preset "Tester" itself: `[preset.3]`, platform "Windows
Desktop", `custom_features="tester"`, `runnable=false` (it is never the editor's Run preset; it exists only
for `--export-release "Tester"`), `export_path="out/tester/voidwrap_tester.exe"`, `file_description`
"VOIDWRAP RUN - TESTER" so the exe names itself. `tools/build_tester.ps1` runs the one-time import then
`--export-release "Tester"` with the same 1 MB "that is a build" floor CI uses; output under
`game/out/tester/` (gitignored, `out/` is a repo-wide ignore), never uploaded, never in a release.

## D-T2-3 (2026-11-23): the replay rule is satisfied with ZERO sim changes; tester runs carry the flag

**Ruling.** The brief: "Prefer zero sim changes; if you must add a field, it is a tester flag only and it
does not enter the state hash." Zero sim changes it is: not one file under `game/sim/` is touched (the
boundary test's content-id scan and the replay suite stay green on untouched code), and no field was
added anywhere. The debug actions are app-layer mutations of LIVE state through the game's own functions
(see D-T2-4..D-T2-6); the seed's own replay - the state hash - is therefore computed from exactly the
inputs it always was, and `test_replay.gd` passes unchanged. The "or the replay is flagged 'tester' in its
header" half is honoured at the build level: `app/run_log.gd` `run_started()` gained an optional additive
payload dict (default `{}` - every existing caller, including bot_run and eight call sites in tests, passes
nothing and records byte-identical output), and `app.gd` `_end_run()` passes `{"tester": true}` exactly
when the tester panel loaded, i.e. exactly in a tester build. A run's log names the build it came from.

## D-T2-4 (2026-11-23): every panel action goes through the game's own command path

**Ruling.** In order: SPAWN - `enemy_runtime.spawn_at()` (the runtime's documented direct-spawn entry: "Same
row shape as the D-056 rule produces"); cfg from the world's own `_cfg_for`, behavior from its own
`_behavior_for`; the view/billboard pass adopts the new row on the next frame, as it does the planned
bodies. GIFTS - `sim/gifts.gd`'s own `collect()` nearest-first, and when that opens the beacon, the panel
performs the same `beacon.open()` `GiftsScript.tick` performs; the world's own next tick then runs the gold
phase, the economy and the collapse schedule exactly as if the player had walked the pickups (the economy's
gold-gift values and the run log's per-tick records do NOT see panel-made collections - the panel's GIVE
GOLD goes to the purse directly instead). SKIP - the app's own `_on_level_completed()` (the lobby opens;
the ledger is read first, never invented) and, for skip-to-level N, the same hand-off
`_on_lobby_exited` runs (run_ledger -> `_build_world(N, ledger)` -> live) so the level stays a pure
function of (seed, level, ledger). COLLAPSE - `sim/collapse.gd` `CollapseScript.start()` on the live
schedule from IDLE; `world.step()`'s own tick then drives cracks, falls and the sweep; a later beacon open
calls `start()` again and is the documented no-op it always is for a non-IDLE schedule. CHARGES - the
controller's own `charges` field.
**Known gap (review round 1: CLOSED, finding 2 - D-T2-9).** The original implementation collected
between ticks, so the per-tick event consumers (economy chain, upgrade hooks) missed the collects.
GIVE N GIFTS now queues the job through `tester_tick_hook` and the collects ride the tick's own event
list: the economy pays gold-phase collects, the upgrade hooks dispatch on them, the fx and HUD draw
them, and the beacon opens through the tick's own phase block. The GIVE GOLD button still writes the
purse directly (it is a purse write, not a collect).

## D-T2-5 (2026-11-23): give-upgrade is live re-application plus a carry, with one delta guard

**Ruling.** `world.apply_tester_upgrade_stack(id)` (the ONE app-layer method the panel owns; nothing in the
public game calls it): +1 stack into `_ledger["stacks"]` (carries to every later level through
`run_ledger()`), then the build()-order pipeline re-applied live: `_run_modifiers` ->
`_stats_black/_stats_gold`, `_upgrade_knobs`' assignments, the set-based consumers (straggler band, gift
yield, twin dash, updraft - all replace semantics, safe to re-run), `_gift_radar_range_for`, and
`_apply_phase_stats()`. THE ONE ADDITIVE CONSUMER, the athletic double-jump count, is applied as the DELTA
only (before vs after the stack), so repeated grants do not inflate air jumps (the negative case: granting a
non-athletic upgrade changes no jump count). NOT re-applied: Field Dressing's per-level free-fall budget
(granted once per level per stack at build; a mid-level grant would double the budget).

**Amended (2026-11-23, Terra review round 1, finding 4).** The "its event hooks go live from the next
level" limitation is GONE: the original D-entry ended by saying exactly that. `apply_tester_upgrade_stack`
now also rebuilds the per-level event-hook dispatcher - `_upgrades = UpgradeRuntimeScript.new()` with the
same (stacks, loader, ctx) construction `build()` uses - so the granted stack's hooks are dispatched
from the NEXT TICK. The rebuild is a fresh instance (setup() builds clean modules), which also resets the
owned modules' once-per-level scratch memory and any running run-speed boost; the tester accepts both,
and the stack still carries into every later level through `run_ledger()`. test_tester_build.gd pins
the rebuild line.

## D-T2-6 (2026-11-23): god mode is a per-frame top-up through existing kill semantics

**Ruling.** No invulnerability concept is added to sim/. The panel's `_god_pass()` keeps
`ctl.invuln >= 1.0` (the controller's own post-respawn window; `try_kill` then emits its existing
`kill_suppressed` for every raised kill) and keeps `ctl.charges >= void_fall_charge_cost` (a void fall is
paid and respawns instead of killing). Last Light, barriers, Field Dressing are untouched - god mode only
ever ADDS the two topped-up values. It keeps running while the panel is closed (a toggle, not a modal
state). Corner case (documented, accepted): a kill raise on the exact frame between panel `_process` calls
cannot be suppressed - the top-up runs every frame in practice, and the tester is the only user.

**Amended (2026-11-23, Terra review round 1, finding 5 - D-T2-9).** Both gaps closed. (1) The top-up now
also runs at the TICK TOP via `tester_tick_hook`, armed by `app.gd`'s `on_world_built` handoff BEFORE the
world enters the tree, so a promoted god mode covers a fresh world's very first tick on every entry path -
the per-frame pass stays only as belt-and-braces. (2) The boss ARENA kills via `ctl._die` directly
(`_apply_boss_events`), which `invuln` never covered; the world now carries `var tester_god := false`
(mirrored from the panel's toggle) and that kill path honours it - god mode works inside the Peter fight.

## D-T2-7 (2026-11-23): force-Peter / force-Bankai probe the T8 API at runtime; Bankai falls back to the dormant cinematic

**Ruling.** The brief: "another worker is adding the boss API in parallel (game/sim/boss.gd, events
boss_spawned / bankai_started). Do not block on it. Call through a small indirection that checks
has_method() at runtime, so the buttons light up once that track merges." The panel's `_first_matching()`
(probe list: the world's `boss` member if the framework sets one, then `load("res://sim/boss.gd")` as a
Script - `Script.has_script_method()`, which covers statics on this engine - then the world, then the app)
checks candidate method names in
order: boss buttons ["force_boss_fight", "force_boss", "force_spawn", "force_start", "start_boss_fight"],
bankai ["force_bankai", "play_bankai"], and calls the first hit once with no arguments.
`res://sim/boss.gd` does not exist in this tree, so the buttons read "... (boss track not merged)" until
a merge brings the API. When that lands, IF the method names differ from all five candidates, the T8
track (or the merge review) adds its name to the two arrays in the panel - the D-entry for that change
names this as the contract. Bankai ALSO has a live fallback today: playing the dormant owner cinematic
`view/cinematics/bankai_gift_animation.gd` directly (added by the owner in `fa0f1a7`, wired to nothing;
`play()`, `animation_finished` -> self-free), which is view-only and uses the engine RNG by its own header's
design - this is a tester preview path, not the boss-fight wiring; the bankai_started sim wiring stays the
T8 track's job.

**Amended (2026-11-23, Terra review round 1, finding 1 - the boss framework merged; D-T2-9).** The probe
contract above is superseded for FORCE PETER: the real API is known now (`game/sim/boss.gd` on main), and
`boss.start()` ALONE was found insufficient - the arena needs `world._enter_boss_arena()` (teleport,
first-person rig, HUD, the level rebuild), and `start` takes `(run_seed, level_no)`. The button now routes
through `_enter_boss_arena` as a queued tick job (D-T2-9) - the buttons never read "not merged"; the
candidate-name arrays remain ONLY as the bankai explicit-force probe (`BANKAI_FORCE_METHODS`) against a
future T8b entry, and the review's request to add a real force method name to that array is answered by that
change's own D-entry. The Bankai fallback is no longer a bare preview either: it plays the cinematic THROUGH
its signals with `bankai_active` standing the boss down and `target_hit` driving `boss.damage(hp_max)` into
the world's own `_apply_boss_events` + `_publish_boss_tick` - the easter egg's insta-kill, live.
D-T8B-11 supersedes this forced-fight fallback.

## D-T2-8 (2026-11-23): the panel's state hash is state_hash's dump over the LIVE level, minus the RNG lines

**Ruling.** `sim/state_hash.gd` is untouched. The panel builds a RunState-shaped holder (`LiveRunState`,
an inner class of the panel: run_seed, players, content_ids, level_number, run_votes, run_hunger,
`level` = the LIVE LevelState, `rng` = {}) and calls the unchanged `StateHashScript.sha256()` on it, so the
label is the same digest function the replay checkpoints pin - LEVELHASH, TICK, the player row, the gift
bitsets + phase knobs, the beacon, the mines, the COLLAPSE and JUMPPADS lines, all live state, per the
dump's frozen field order. The RNG lines are the one omission, and the reason is structural, not chosen
out of convenience: the app driver holds no sim rng streams at all (they exist only in the sim-driver
contexts - test_replay's random-input run and bot_run's recorded runs - which keep the FULL hash, unchanged
and untestable from here on purpose). Two different live states therefore always differ in the displayed
digest, and the owner gets the level hash of any level in play.

## D-T7-1 (2026-11-23): fit the refined look to the shipped figure

**Owner:** "evaluate and adopt the refined player model/animator proposal without regressing the locomotion".
**Ruling.** Keep the approved blocky proportions and charcoal torso, and bake the refined head details
into the shared figure asset so the lobby, player and respawn shell all use them. The taller reflective
band, recessed cone tip, wider squared brim, layered silver hair and dark wraparound shades with baked
highlights take their dimensions from `game/data/player_figure_refinement.json`. Keep the existing
branching antlers dark against the hat's silver band and hair. Omit the proposed pulsing cyan tip aura
to preserve the monochrome silhouette and keep cyan accents on gameplay elements.

## D-T7-2 (2026-11-23): keep the shipped locomotion for all six proposed states

**Ruling.** The proposed animator moves the hip pivots independently, uses a single rigid block for
each leg, and applies nonuniform root scale during jump and landing. Its stair latch uses body
velocity and floor normals with no per-sole tread sampling. Keep the render-clock solver, rigid
two-bone legs, joint limits, terrain-aware foot plants, and normalized gait thresholds 0.35 / 0.85
from v0.1.14-alpha.3. The existing controller-driven pose tests and sheets cover idle, walk, run,
jump, stairs up and stairs down alongside the other ten cases.

## D-T8A-1 (2026-11-23) Boss contract and seeded rolls

The owner asked for "Peter Griffin boss fight at level 10 (teleport to arena, first person gift throwing 1 dmg / 5% crit 5 dmg, 250 HP, bowling ball + green fn basketball attacks, laugh on death, 1/1000 Bankai easter egg using game/view/cinematics/bankai_gift_animation.gd, beacon + 300 gold after the kill)".
D-T8B-9 supersedes the original Bankai odds.
Boss attack cadence, gift tuning and arena dimensions live in boss.json. Bankai uses
one draw keyed by run seed and level. Crits use a separate draw keyed by the shot
tick and run seed. The arena uses packed floor tiles assembled outside voidgen.

## D-T8A-2 (2026-11-23) Arena entry and clearing level 10

Level 10 requires every real black gift even with a quota upgrade. Its final pickup
moves the controller onto a separate flat platform and preserves the carried purse,
charges and kit. The arena has its own terrain hash, collision and beacon. Map-specific
enemy, curse, upgrade and collapse ticks stop on entry. The boss death event credits
300 whole gold once and opens the beacon. Entering it on a subsequent tick pays the
usual clear stipend and raises the normal level-completion signal.

## D-T8A-3 (2026-11-23) First-person gift throws and replay state

Left mouse is held fire in the arena. The fixed-tick command contains the fire bit and
world-space aim captured from mouselook. A spawned gift snapshots its crit result and
tests its swept segment against the boss hit sphere. The arena hash includes the boss,
ordered in-flight gifts, cooldown, controller values and purse. The same commands
drive live and replay ticks. An attack-worker hit event invokes the controller's
death path directly so a charge, Last Light or respawn invulnerability cannot absorb it.
## D-T5-1 (2026-11-23) Gin's ground sword

Owner request: "Gin enemy revamp (bye bye voice with background noise removed, throws a sword, jump window 500-750 ms)". The real roster uses a bodyless Gin with a screen-space warning, recorded voice, and a ground sword. The throw takes 39 ticks (650 ms at 60 Hz). Every tick the sword closes the remaining distance divided by the remaining ticks, so range and running sideways do not change the arrival tick. At arrival it tests the player's feet against terrain support plus the data clearance. The usual controller kill and Last Light rules apply. Existing address me deferral and vote-based cooldowns remain, and multiple Gin rows take turns. The old mark/void branch remains available to historical fixtures that omit the new attack config.

## D-T5-2 (2026-11-23) Twin Fangs and replay checkpoints

Twin Fangs now sends two swords from opposite sides which arrive on the same tick, with a higher data-driven clearance so one well-timed normal jump answers both. Gin hashes the attack configuration, spawn and phase clocks, target, trajectory and result in runtime row order. The world and bot attach the live enemy runtime to LevelState. The ENEMY line is emitted only for behaviours that supply hash data. No golden fixtures change.

## D-T5-3 (2026-11-23) Gin presentation and owner audio

The procedural portrait shows silver hair, a dark profile and a narrow smile. A screen-space sword track shows the throw countdown even when the world sword starts outside the camera. The owner sword was keyed from its white background and rotated to point along its sprite axis. The voice uses miniaudio MP3 decode and SciPy/NumPy spectral subtraction, with the quietest non-padding frames as the noise profile. Same 36 quietest 1024-sample frames before/after: 0.00001834 to 0.00000237 FS (-94.73 to -112.49 dBFS). Quiet non-padding profile frames: 0.02775310 to 0.00734312 FS (-31.13 to -42.68 dBFS). The game ships mono 44.1 kHz 16-bit PCM and starts the throw after the 1.724 s clip.

## D-T5-4 (2026-11-23) Fixed release trajectory and pending schedule

Terra's review found that the deadline hit could ignore an earlier crossing. The ground sword now aims at the target's feet at release, advances by a fixed fraction of the launch distance each tick, and sweeps against each controller's body using relative motion. A clear path reaches the aim point after 39 ticks. Twin Fangs uses two fixed paths into the same aim point. The hash includes both origins, the aim point, the previous controller positions used by the sweep, and the pending plan's scheduled start, placement target, queue order and copy progress. Stationary and moving bots exercise the collision through the real controller.

## D-T5-5 (2026-11-23) Live and historical Gin data

The shipped enemy metadata describes the bodyless ground sword and its bye bye cue. The mark and zone metadata moved to a test fixture. The legacy code path remains for archived timing, arbitration, audio, negative-control and answer-lab fixtures that construct Gin without the live attack configuration. Those checks still exercise the historical attack and keep their original timing thresholds.
## D-YOU-C7-1 (2026-11-23): "you?!" smaller range + slower strike - the numbers

**Owner's words (cycle 7 brief, T1):** "you?!" smaller range + slower strike.

**Ruling.** `game/content/enemies/you/enemy.json` stats: `ring_max_radius` 14.0 -> **8.0** (57.1 % of the
old reach, inside the brief's "at most 60 %" = 8.4), `rumble_ticks` 90 -> **180** (3.0 s, exactly 2x the
old tell), `trigger_distance` 10.0 -> **8.0** so he never telegraphs from outside his own reach (the
telegraph footprint is drawn at `r = ring_max_radius`, so a 10 u trigger would have shown a circle that
could not reach the player). `ring_speed_u_per_s` stays **9.0** and `ring_cooldown_ticks` /
`attack_hold_ticks` / `recover_ticks` stay 240 / 18 / 240.

**Why the speed does not move.** The brief asked to re-check the jump window "because a smaller ring
crosses the player faster". It does not. The band's radius is `min(speed x t, cap)`, so the crossing a
jump must cover is **clipped at the cap**: the nominal `2 x 0.7 u / 9 u/s = 0.156 s` only applies where
`d + 0.7 <= cap`, and at the trigger distance (d = 8.0, cap = 8.0) the band stops at 8 u and its trailing
half never sweeps past the player, so the crossing is `(8.0 - 7.3) / 9 = 0.078 s` - SHORTER, not longer.
The shared kit's jump (v0 12, g 32) keeps the feet above the 1.0 u band top from 0.0955 s to 0.6545 s,
so the jump-timing window is `[t_hit_hi - 0.6545, t_hit_lo - 0.0955]` = **0.234 s .. 0.716 s** after the
release, 0.481 s wide against the old numbers' 0.403 s. The window widened because the clipped crossing
is shorter, not because the band arrives sooner. `test_enemy_you._jump_window_clears_the_ring` runs the
REAL controller against the REAL ring and asserts: the crossing is clipped below the nominal 0.156 s, the
window is wider than the old numbers' window, BOTH endpoints (two ticks inside survives, two ticks outside
dies), a jump at the midpoint survives, no jump dies, and a jump on the release tick dies (landed before
the band arrives). Hand-run negative controls: with the old window's endpoints substituted the test
reports 4 failures (both endpoint arms plus the width comparison), and with the behaviour's `_num` forced
to return the constant the data test reports 5.

**Mirrors updated with it** (the number lives in data; every reader follows): `enemy.gd`'s constants +
a new `cfg()` mirror pinned to the json by `test_enemy_you._roster_data`; `sprites.json`'s telegraph
`total_ticks` 90 -> 180 and attack `max_radius_u` 14.0 -> 8.0; `content/curses/double_ring.gd`'s echo
ring cap 14.0 -> 8.0 (it is "YOU's own ring"); `data/tips.json` tip_you_rumble; `tools/synth_audio.py`
+ the regenerated `you_corrupted_rumble.wav` (1.5 s -> 3.0 s = exactly 180 ticks, so check_audio.gd's
assertion 3 still lands the cue on the release tick); `research/fable-tickets.md` sections 1.6 and 3;
`DESIGN.md` 5.6; `ENEMIES.md`'s Husk row; `tools/check_anim_data.gd`; `tools/bot/answers.gd`.

## D-YOU-C7-2 (2026-11-23): the tell holds position (narrowing D-T-035-6)

**Ruling.** During the `telegraph` state YOU?! no longer floats toward the player: `tick()` calls
`FloatBody.update()` (which keeps `h_speed` / `tempo_mul` live, so SR-5 is untouched) instead of
`FloatBody.step()`. D-T-035-6's "floats through every phase" is narrowed to "every phase except the tell".

**Why.** At 3.4 u/s a 3.0 s tell carries him 10.2 u. Starting from an 8 u trigger he would reach the
player's body (0.75 u contact radius) after 2.13 s - **before** the ring releases at 3.0 s - so a
standing player would die to the touch kill and the ring would never be the threat. The tell would be a
lie and the counter-play text ("jump as the ring reaches you") would describe nothing. Holding makes the
release distance the distance he telegraphed from, which is what makes the 8 u ring a fair, jumpable
strike. Cost, stated plainly: a player who simply runs away now outruns the ring, so YOU?! is a weaker
enemy than before - which is what "smaller range + slower strike" asks for. The touch kill is unchanged.

## D-YOU-C7-3 (2026-11-23): the numbers stay in data, the mirror is pinned

**Ruling.** No new constant was added to code. `enemy.gd` keeps its existing constants (they are the
mirror the bot and the Echo Ring curse read) and gains a `cfg()` static that returns the same block, in
the kiwi_cat / claude / seal convention. `test_enemy_you._roster_data` fails if any mirrored key is
missing from `enemy.json`, if any value disagrees, or if the three cycle-7 thresholds regress
(`ring_max_radius <= 8.4`, `rumble_ticks >= 180`, `trigger_distance <= ring_max_radius`), and it also
pins the audio timing (`attack_offset_ticks` / `binding_cue_ticks` == the tell) so the cue cannot drift
from the tell again. Enemy rows are not in the state hash (pre-existing: `state_hash.gd` dumps run state,
not enemy rows); this change adds no new sim state, so the replay determinism test is unaffected and the
sim stays deterministic at 60 Hz with no RNG.

## D-YOU-C7-4 (2026-11-23): the data is authoritative, the constants are only a fallback

**Ruling (Terra review round 1, real defect).** `enemy.gd` now reads every one of its numbers from
`row["cfg"]` at run time through `_num(row, key, fallback)`: `trigger_distance`, `rumble_ticks`,
`ring_speed_u_per_s`, `ring_max_radius`, `ring_thickness`, `ring_height`, `ring_below_feet`,
`ring_cooldown_ticks`, `attack_hold_ticks`, `recover_ticks`. `row["cfg"]` IS `enemy.json`'s `stats`
block, passed through verbatim by `world.gd`'s `_cfg_for`, so editing `enemy.json` alone now changes
gameplay. Before this, the constants at the top of the file were what the behaviour used and the json
was documentation that only the mirror test compared - Terra's finding, and it was right.

**What the constants are now.** The same values, kept because two readers outside the behaviour need a
compile-time mirror: `tools/bot_run.gd`'s ring-threat model (`RING_SPEED`, `RING_MAX`,
`RING_RADIAL_WINDOW`, `RING_BELOW`, `RING_HEIGHT`) and `test_enemy_you`'s window arithmetic. They are
used by `_num` ONLY when a cfg omits the key - a hand-built fixture (`test_enemy_negcontrols._you_cfg`)
or a curse's `spawn_at` - never as the source of truth. `test_enemy_you._roster_data` still fails if any
mirrored key is missing from the json or disagrees with it, so the two cannot drift silently.

**Why not delete the constants.** `bot_run.gd` is a headless tool with no row in hand when it models the
threat, and the test's window arithmetic is a closed-form derivation that must not read the same dict it
is checking. Deleting them would mean either duplicating the numbers in the bot (worse) or making the
test read the value it asserts (worthless). The fallback is the honest compromise and is documented at
the helper.

**Proof the data wins.** New `test_enemy_you._data_drives_the_behavior` spawns with a cfg that DISAGREES
with the constants (trigger 3.0, tell 60, cap 2.0, speed 6.0) and asserts the behaviour follows the cfg:
the telegraph event carries 60 ticks, the band moves 0.1 u on its first tick, it caps at 2.0, and no
rumble fires at 4.0 u. Hand-run negative control: forcing `_num` to return the constant makes that test
report 5 failures, so it cannot pass by accident.

## D-T2-9 (2026-11-23): the tester tick hook - queued commands and god mode run INSIDE the world's tick

**Ruling (Terra review round 1, "ADOPT WITH FIXES", findings 1-5; amend D-T2-4/5/6/7).** A public build
pays one extra `Callable.is_valid()` per tick; the panel, when it exists, arms one probe per world.
`game/app/world.gd` gains `var tester_tick_hook: Callable` (never valid without the panel - the panel is
the only setter, via `app.gd`'s `on_world_built` handoff in `_build_world`, which runs BEFORE the world
enters the tree or takes its first step, with a per-frame fallback in the panel's `_process`). `step()`
calls it at the tick top, after the run-over guard, BEFORE `_capture_input` and BEFORE the arena
early-out; the panel returns `{"ev": Array, "skip": bool}`:
  - **God mode tops up HERE** (finding 5): the top-up precedes everything that can kill this tick -
    `ctl.step`'s void falls, the mines, the enemy runtime's contact kills - and because the hook is
    armed by `on_world_built` before the world ever steps, a promoted god mode covers a fresh world's
    VERY FIRST tick on every entry path. The world also carries `var tester_god := false`, mirrored from
    the panel's toggle, because the boss ARENA kills via `ctl._die` directly (not `controller.try_kill`):
    `_apply_boss_events`'s `boss_projectile_hit_player` honours it (finding 5, arena half).
  - **Queued commands drain HERE** (finding 2): the panel queues jobs (`_pending`) and they run inside
    the tick with the tick's own list - `_run_give_gifts` collects nearest-first and the collect
    events ride `ev` into the SAME tick's `_curses` passes, beacon-open block, `_upgrades`
    `dispatch_events` (hooks!), `_economy_pass` (gold payouts!), `_fx_events` and `_sync_hud`. Never
    again a collect the economy never paid. The events merge into `ev` right after `ctl.step`'s own
    events; in the arena they enter as `_step_boss_arena`'s new optional `prefill` so the same economy
    + publish passes consume them there too.
  - **`skip: true` finishes the tick** (finding 1): the forced arena entry (`_run_force_boss`) performs
    the entry + `_economy_pass` + `_publish_boss_tick` triple the all-collected path in `world.step`
    performs and returns, and the world's step returns immediately - the panel's entry cannot drag the
    old level's mines/pads/enemy passes over a rebuilt `lstate`.
  - **Finding 1, the real API**: FORCE PETER routes through `world._enter_boss_arena()` - the arena's
    own full entry (boss.start(run_seed, level), the arena rebuild, `ctl.place` teleport, the
    first-person rig, the HUD) - never `boss.start()` alone; on a non-boss level the boss object the
    level-10 `build()` would carry is created from `sim/boss.gd`'s own config first (`lstate.boss`).
    FORCE BANKAI prefers an explicit force method on the live boss object if one appears
    (`_first_matching` on `BANKAI_FORCE_METHODS`), else plays the dormant cinematic THROUGH its
    signals: `bankai_active` stands the boss down (the contract's own flag), `target_hit` drives
    `boss.damage(hp_max, false)` - the easter egg's insta-kill - via `_apply_boss_events` (reward +
    beacon) and `_publish_boss_tick` (HUD), `animation_finished` frees the node; with no live boss it
    previews standalone. The buttons are no longer probe-gated and never read "not merged" on main.
  - **Finding 3**: the meta line and the give-gold status call `purse_gold()` (a method), not `.get`.
  - **Finding 4** is answered in D-T2-5's amendment (the dispatcher rebuild), not by a limitation note.
  - **Finding 4's cost, accepted**: the fresh dispatcher also resets the owned modules'
    once-per-level scratch and any running run-speed boost - the tester accepts both.

**Sim untouched.** No `game/sim/` file mentions the tester; the state hash, boss.gd and every replay
fixture are byte-identical to merged main's; the panel's actions remain app-layer mutations through
public functions, now delivered at tick boundaries. test_tester_build.gd pins the hook (`var
tester_tick_hook`), the arena god guard (`boss_projectile_hit_player` + `not tester_god`), the
dispatcher rebuild line, and the `on_world_built` handoff.
## D-T4-1 (2026-11-23): the Claude revamp replaces the musical attack kit outright (cycle 7, T4)

**Owner's words (CYCLE7_BRIEF.md, T4, verbatim).** "Claude enemy revamp (spawns 5-15 clawds, collect to calm,
warning sounds at 1 and 2 min, insta-kill at 3 min)". "The current Claude is not what the owner asked." "Claude
does NOTHING by himself: no attack, no movement."

**Ruling.** `content/enemies/claude/enemy.gd` loses drums, strings, wind, the beat clock, agitation and the
plushies. The behavior is now: a body that stands still, fades in over the anim block's 30-tick spawn row, and
emits exactly two anim states, `spawn` then `idle`. It never moves, never telegraphs, never fires, never kills by
its own action. Everything the old kit did is deleted, not disabled: no dead code path survives, because a
disabled attack that still runs its clock is a lie in the state hash.

**What is kept and why.** (a) The body: `world_height` 2.0, `hit_diameter` 1.6 - the SR-2 row, unchanged, so
`tools/check_enemy_data.gd` stays green. (b) `base_speed` 4.0 and
`pursuit_ceiling` 0.55 stay in `enemy.json` because the SR-5 table pins them and the checker compares the file to
the table; the behavior simply never calls the float body, so the numbers are inert data, not a movement rule.
(c) The 30-tick spawn fade, because the anim block's `spawn` row is the sheet's contract and `test_anim_sync.gd`
drives it. (d) `content/enemies/claude/sprites.json` is NOT edited: its nine T-083 states stay as dormant art data
(the same "dormant, wired by a later ticket" status the owner's Bankai cinematic has), so `tools/check_anim_data.gd`
and `test_anim_sync.gd` stay green without a threshold moving.

**Contact kill REMOVED (review round 1, 2026-11-23).** The first cut kept `contact_kill: true` and called it
[CONTESTABLE]: "does nothing by himself" was read as "no attack, no movement", not "no body". Terra's review
rejected that reading, and it is right - killing a player who walks into him IS an additional lethal behaviour,
and the owner's sentence rules out every lethal act except the one he named. `contact_kill` is now **false** in
both places `enemy.json` carries it (top level and `stats`) and in `enemy.gd`'s `cfg()` mirror, so the framework's
body-contact path skips him entirely (`sim/enemy_runtime.gd` `_contact_kills` reads the flag). The 180 s anger
timer is Claude's ONLY lethal act. The spawn fade stays (the anim block's `spawn` row is the sheet's contract and
`test_anim_sync.gd` drives it) but it is now purely cosmetic: the old code zeroed `diameter_u` for its 30 ticks to
gate the contact kill, and that zeroing is deleted with the kill it gated - the body mirror keeps the real 1.6 u
diameter from tick 1. `DESIGN.md` section 5.11 and the SR-2 row say so, and `test_enemy_claude.gd` asserts a
player standing inside the body for 600 ticks is never killed.

## D-T4-2 (2026-11-23): the clawd swarm and the anger timer live in sim/clawds.gd, not in the behavior

**Ruling.** `game/sim/clawds.gd` owns the clawd entities, their placement and the anger timer. It is a sim module
in the same shape as `sim/jump_pads.gd`: `attach(L, cfg)` computes the spots and stores
`L["clawds"] = {"cfg": ..., "spots": [[x, z, y], ...]}`; `LevelState.build` picks that up as `lv.clawds` (null when
the key is absent, so every level without Claude keeps byte-identical dumps); `tick(lv, ctls, w, tick, events)` runs
once per sim tick after the player row is synced, in the same slot `sim/mines.gd` and `sim/jump_pads.gd` use.

**Why not in the behavior.** The timer must be in the state hash, and enemy rows are not hashed (they are the
runtime's own dictionaries). A timer living on a row would be invisible to `sim/state_hash.gd` and two runs that
diverged on it would hash alike - the exact hole D-JUMPPAD-4 closed for the pads. The clawds are also level-wide
entities, not one body's property: they exist across the whole map and outlive any single row.

**Why not in voidgen.gd.** Terrain parity compares `terrain/voidgen.gd` against the Python goldens byte for byte;
a placement function there would move the level hash. Placement is a pure function of the Level dict plus the
roster module's data, exactly like `terrain/jump_pads.gd`, and `voidgen.to_text()` never reads the key.

**No content id in sim.** `sim/clawds.gd` names no enemy: the killer id, the death code, the cue names and every
number arrive in `cfg` from the roster module (`content/enemies/claude/enemy.gd`'s `clawd_cfg()`), which
`app/world.gd` and `tools/bot_run.gd` probe for by method name - the same idiom `extra_mines()` already uses. The
boundary scan stays clean.

## D-T4-3 (2026-11-23): the clawd count formula is a data table over the level's tile count

**Owner's words.** "On level start he spawns mini CLAWDS across the map: minimum 5, scaling with level size up to
15 on very big maps (count formula in data ...)".

**Ruling.** `enemy.json` `stats.clawd_count_by_tiles` is the formula: the row with the largest `tiles` <= the
level's tile count wins, clamped to `[clawd_count_min, clawd_count_max]` = `[5, 15]`. The rows are
`<800 -> 5`, `<1100 -> 7`, `<1400 -> 10`, `<1700 -> 12`, `>=1700 -> 15`. Measured tile counts on this generator
(seeds 1 / 7 / 42): level 1 = 585 / 743 / 720, level 10 = 919 / 1005 / 874, level 20 = 1404 / 1356 / 1434,
level 30 = 1765 / 1610 / 1524 - so the shipped range 585..1778 walks the whole 5..15 ladder and level 1 always
sits at the floor of 5. "Level size" is read as the tile count, not the level number: the owner said "very big
maps", and the generator's tile count is what actually varies.

## D-T4-4 (2026-11-23): clawd placement - walkable, clear of every hazard, spread out, seeded

**Owner's words.** "placed by the terrain generator seed, on walkable tiles, never on mines/beacon/hub/pads,
spread out".

**Ruling.** `place_clawds(L, cfg)` is a pure function of the Level dict and the cfg. Candidates are tiles with
`kind` 0 (floor) or 1 (walkway), not a ramp tile (`t[3] == 0`), whose piece is not the hub, and with no prop on
them. Banned outright, with their 8 XZ neighbours: every gift slot (which is also every tripmine slot - the mine
set IS the `occ == 1` gift slots), the beacon tile, every launch pad and its landing tile, every jump pad, and
every player spawn. The candidate list is shuffled by a `VoidRng` stream seeded from the Level's own
`(seed, level, gen_version, attempt)` mixed with the tag `0x434C4157` ("CLAW"), so the level hash still determines
the swarm and no runtime RNG exists. Greedy selection keeps pairwise XZ distance >= `clawd_min_spacing_tiles`
(8); if that leaves fewer than the wanted count the ladder retries at 4, then 2, then takes any remaining
candidate, so a small map still reaches its floor of 5 rather than silently shipping 3.

## D-T4-5 (2026-11-23): the anger timer - 3600 / 7200 / 10800 ticks, paused in the gold phase, reset per level

**Owner's words.** "If no clawd is collected for 60 s, Claude releases a warning sound (a new synth cue). At
120 s, a second, more urgent sound. At 180 s he INSTA-KILLS the player, death screen cause \"Claude\"." "The timer
runs in sim ticks, deterministic, in the state hash. It pauses when the beacon opens (gold phase) and resets per
level."

**Ruling.** `anger_ticks` counts up one per sim tick from 0 at level start. At exactly 3600 it raises
`clawd_warning` with `level` 1, at exactly 7200 with `level` 2, at 10800 it kills. A pickup sets it to 0 on the
tick of the pickup and that tick does not advance it, so a clawd collected on the tick a warning was due cancels
the warning - "collecting a clawd CALMS Claude" is read as strictly stronger than the timer. The timer does not
advance while `lv.beacon.is_open()` (the gold phase begins on exactly that tick, `app/world.gd`'s `_gold_began`),
and it never advances after the kill has fired. It is per level because `lv.clawds` is rebuilt by
`LevelState.build` on every `load_level`.

**The kill goes through the controller's kill ladder.** `ctl.try_kill(cfg.death_code, cfg.killer_id, w, ev)` - the
one kill path every enemy uses (DESIGN.md section 12: "kill saves nothing and subtracts nothing: the player's
controller answers"). So Last Light can save the player once from it and respawn invulnerability suppresses it,
exactly as for a body contact; the kill test runs with Last Light already spent (D-057). "Insta-kill" is read as
"no counter-play once the timer lands", not as "bypasses the save the owner designed".

**Death screen.** `death_code` is `D-CLAUDE`, which `core/roster.gd` maps to the roster row's display name, so the
run-over screen reads cause "Claude" with no new table.

## D-T4-6 (2026-11-23): the state hash line, and why the coordinates are in it

**Ruling.** `sim/state_hash.gd` appends, only when `lv.clawds != null`:

`CLAWDS <spots x:z:y csv> <taken hex> <anger_ticks> <warned> <kill_ticks> <warning ticks csv> <pickup radius bits>`

The spots are dumped because placement depends on `enemy.json`'s count/spacing data, which `LEVELHASH` does not
cover - the same reason D-JUMPPAD-4 dumps the pad coordinates. `taken` is the live bitset, `anger_ticks` and
`warned` are the live timer, and the three knobs are data pinned so two runs whose data differed cannot hash alike
before the first pickup. A level with no clawds writes no line, so the random-input replay, the bot fixtures and
every older dump are byte-identical.

## D-T4-7 (2026-11-23): the two Claude-linked curses are re-pointed at the anger timer

**Ruling.** `crescendo` and `token_limit` were written against agitation and plushies, which no longer exist. They
keep their ids, names, min levels, severity and their intent (Claude gets angrier faster / calming him is weaker),
and their rule sentences in DESIGN.md section 7.1 are rewritten to the new mechanic:

- `crescendo` - "the anger timer runs 1.5x faster" (warnings at 40 s and 80 s, the kill at 120 s). Counter-play
  "collect clawds first". Implemented as `ANGER_RATE_MUL` applied by the curse's `on_tick` to
  `state["clawds"].anger_ticks`; the sim's own rate stays 1 tick per tick.
- `token_limit` - "a clawd leaves 20 s of anger instead of calming Claude completely". Counter-play "route for
  clawds". Implemented as `CALM_LEFTOVER_TICKS` 1200: the pickup sets `anger_ticks` to 1200 instead of 0.

**Dropped clause.** `token_limit`'s old second clause ("and spawn every 30 s") has no referent: clawds spawn once
at level start in the new design, there is no periodic spawn to slow down. Recorded here rather than invented into
a different mechanic.

## D-T4-8 (2026-11-23): the view side - clawd sprites, the anger pill, and the two warning cues

**Owner's words.** "HUD: a small anger/timer indicator and a clawd counter (view side), plus clawd sprites (reuse
the Claude logo sprite shrunk, or a simple procedural clawd icon)." "Audio: two new warning cues."

**Ruling.** (a) `game/view/clawd_view.gd` draws one billboarded sprite per live clawd, reusing the Claude logo
frame (`sprites/idle_00.png`) shrunk to 0.6 u, bobbing on the sim tick, with a 9-tick white pop on the pickup tick
- the same stand-in the plushies used, now driven by `lv.clawds` instead of a row. It is a level-wide node like
`gifts_view` / `jump_pad_view`, not a child of the enemy view, because the swarm is not the body's property.
(b) `game/view/claude_view.gd` keeps the body, the metronome idle and the spawn fade, drops the rings / beams /
shots / plushies, and tints the logo red as `anger_ticks` approaches the kill. (c) `game/view/hud/anger_meter.gd`
is one top-centre pill under the collapse warning: `CLAWD 3 / 8` plus the calm countdown, its border lighting at
warning 1 and pulsing at warning 2; hidden when the level carries no clawds. (d) Two new cues,
`claude_warning_1` and `claude_warning_2`, synthesised by `tools/synth_audio.py` (a two-note rising chime and a
three-note urgent alarm, both new voices, nothing copied), registered in `view/audio/claude_audio.gd` and played
on the `clawd_warning` event's `level`.

## D-T4-9 (2026-11-23): the fixtures, the docs and the bot answer that had to follow the revamp

**Ruling.** The revamp deletes the musical kit, so every artefact that asserted the kit had to move with it. None
of these is a threshold change; each is a fixture whose subject no longer exists.

- `game/tests/test_enemy_claude.gd` - rewritten (1073 -> 970 lines). Kept: the roster-data-vs-mirror leg (now also
  `clawd_cfg()` and `sim/clawds.gd`'s `DEFAULTS`), the body/contact leg, the 30-tick spawn fade, the anim-block
  wiring and the lobby exhibit. Replaced the attack legs with: the count across level sizes (5..15, the table's own
  boundaries, the clamp, four real generated levels), the placement rules (walkable, clear of gifts/mines/beacon/
  pads/spawns, spacing, seed-pure, ramp-only and hub-only maps place nothing), "does nothing by himself" (600 ticks,
  no ring/shot/sweep/plushie, no motion, no telegraph), the timer at exactly 3600/7200/10800 with cause "Claude",
  the pickup reset, the gold-phase freeze, and the CLAWDS hash line with a two-replay determinism leg.
- `game/tests/test_audio_cues.gd` - the claude leg now runs the real clawd runtime and the real `claude_view.gd`:
  the sim's `clawd_warning` event names the cue at exactly 3600 and 7200, both cue files exist, and the view
  recorded both warnings. The negative control leaves the view unwired, so the same checker fails. The
  `strings_line -> string_sweep` row is gone from the table leg because the strings attack is gone.
- `game/tests/test_app_fx_wiring.gd` - the synthetic `strings_line` telegraph still beeps `keystroke_tick` (the
  view's own TELL_CUES map) but no longer plays `string_sweep` (that mapping came from claude's `audio_cue_timing`
  row, deleted with the attack). The expected cue count is 6, not 7.
- `game/tests/test_curse_dispatch.gd` / `test_curse_enemy_effects.gd` / `test_curses_scripted_enemy.gd` - the
  crescendo and token_limit legs measure the anger timer and the pickup leftover instead of agitation and plushies.
  The dispatch leg measures a DELTA over 600 ticks after the first two, because the curse's `on_tick` runs after
  the clawd tick in `app/world.gd` (tick 1 is at the sim's own rate): control +600, cursed +900.
- `game/tests/test_enemy_negcontrols.gd` - claude's claim is the anger timer (10800 ticks with no clawd collected
  kills with D-CLAUDE); the mechanism toggle is the swarm itself.
- `game/tests/test_loading.gd` + `game/data/tips.json` - `tip_claude_drums` -> `tip_claude_clawds` and
  `tip_claude_plushie` -> `tip_claude_anger`, each pinned to the new data (`clawd_count_min/max`,
  `anger_warning_ticks`, `anger_kill_ticks`, `anger_pause_when_beacon_open`). The pool stays at 30 tips. The
  now-unused `_beats_are_1_and_3` helper is deleted.
- `game/tests/test_hud_gui.gd` - `_full_hud()` carries a live `"clawds"` snapshot so the new pill is visible and
  the layout leg's `shown == panels.size() - 1` still holds.
- `game/tools/bot/answers.gd` - claude's answer is a ROUTE ("collect clawds"), not an input sequence; the entry
  keeps its `fable-enemies.md` source line and records the gap that the bot does not path to clawds.
  `game/tools/answer_lab.gd` drops its claude `drum_ring` case (there is no telegraph to time any more).
- `DESIGN.md` - section 5.11 rewritten to the revamp (the `tell` and `counter_play` lines are the enemy.json text
  verbatim, which `test_panel_lines.gd` requires), and the SR-2 note for Claude no longer claims it keeps its
  distance. The SR-5 row (4.0 / 0.55) is untouched: `tools/check_enemy_data.gd` compares it to the table, and the
  behavior never calls the float body, so it is inert data (D-T4-1).
- `game/sim/clawds.gd` - the header's owner quote says "a second, louder one" instead of "a second, more urgent
  sound": the boundary scan (`test_boundaries.gd`) matches whole words against the content ids, and "more" is a
  curse id. The verbatim quote lives here, in the D-entries, where the scan does not look.

## D-T4-10 (2026-11-23): review round 1 - the contact kill goes, the warning ladder re-arms, the kill retries, placement never stacks, and the bot answers the clock

**Source.** Terra xhigh reviewed `t3/claude-clawd-revamp` and returned ADOPT WITH FIXES with four merge-blocking
defects plus one bot-routing gap. All five are fixed in this round; the dropped 30 s periodic-spawn clause, the
dormant anim states, the unreferenced old WAVs and the inert strings-line machinery were ruled acceptable cleanup
and are left alone.

**1. The contact kill contradicted the owner.** Fixed in D-T4-1 (amended above): `contact_kill` is false in
`enemy.json` (both places), in `enemy.gd`'s `cfg()` mirror, and the fade's `diameter_u` zeroing is deleted with
the kill it gated. The 180 s anger timer is Claude's only lethal act.

**2. A pickup reset the timer but not `warned`.** `sim/clawds.gd` `pickup()` now sets `warned = 0` with
`anger_ticks`, so the warning ladder counts the warnings of the CURRENT anger period. Without it every period
after the first pickup passed in silence. The view side follows: `view/claude_view.gd` gains `rearm()` (clears
`_last_warned`, no flash, no cue) and `view/enemies/enemy_view_host.gd` calls it when the sim's count goes
BACKWARDS, so the next 60 s / 120 s warnings flash and play their cues again. `test_enemy_claude.gd`'s
`_warned_rearms_on_pickup` asserts the second period fires both warnings at exactly 3600 and 7200 ticks after the
reset; `test_audio_cues.gd` asserts `rearm()` and the warning after it.

**3. The kill was marked spent before it landed.** `advance()` used to set `killed = true` and then call
`_kill()`. Last Light, respawn invulnerability or a barrier can turn the blow aside, and the timer then never
tried again - the specified 180 s kill silently did not happen. Now `_kill()` returns whether a player actually
died (`ctl.dead` after `try_kill`), `killed` is set only on that, and while the player is protected the timer
stays pinned at `kill_ticks` and retries every tick. A suppressed retry emits nothing (the controller's
`kill_suppressed` events are dropped), so a protected player does not fill the replay with one event per tick.
`test_enemy_claude.gd`'s `_kill_retries_while_protected` holds the player invulnerable through tick 10800, asserts
`killed` is still false and anger pinned, then drops the shield and asserts the kill lands on the very next tick
with `D-CLAUDE`, one `clawd_kill` event, and nothing after.

**4. The spacing ladder could pick one tile twice.** At the bottom rung (spacing 0) the distance test passes for
every candidate, including the ones already chosen, so a small map could stack two clawds on one tile.
`place_clawds()` now keeps a `used` set of candidate indices and never returns a tile twice; if the candidates run
out the swarm is simply smaller than the count formula asked for (a map with fewer legal tiles than the floor),
never overlapping. `test_enemy_claude.gd`'s `_placement_never_overlaps` sweeps the small maps where the ladder
reaches that rung and a hand-built 3-legal-tile map that must place exactly 3.

**5. The bot did not route to clawds.** `tools/bot_run.gd` gains a clawd goal kind: `_clawd_urgent()` (urgent from
the DATA's first warning tick, `anger_warning_ticks[0]`, and never while the timer is frozen or spent),
`_nearest_clawd()` (nearest reachable uncollected clawd on the route distances, skipping released slots),
`_goal_point()`/`_goal_stale()` for the new kind, `mem["clawd_tiles"]` built from `lv.clawds.spots` with the gift
slots' own mapping, and a repath on `clawd_collected`. Before the first warning the bot plays the level normally,
which is what PACES the swarm instead of eating it at once; from the first chime on, the nearest clawd outranks
the nearest gift. A clawd the follower cannot actually reach (a deep drop the jump validator refuses) is released
for the level after `CLAWD_GIVE_UP_TICKS` (600 = 10 s, the `_stuck_window` window) and the next nearest is tried,
so an unreachable clawd cannot pin the bot while the timer climbs. With every clawd released the bot falls back to
gifts and takes the kill - honest, and no longer systematic. `tools/bot/answers.gd`'s claude caveat and KNOWN GAPS
note say so. `test_bot_run.gd`'s `_clawd_routing` asserts the decision functions directly and pins one integration
run (seed 20, level 15, a Claude vote) that used to die at tick 14140 with `D-CLAUDE` and now does not.

**Measured.** 20 level-15 runs that vote Claude (seeds 23..42): 0 deaths with `D-CLAUDE` (8 complete, 10 stuck, 1
mine death, 1 timeout - the stuck/timeout outcomes are the bot's pre-existing behaviour on those maps and are
identical with and without the Claude vote).

## D-T8B-1 (2026-11-23) The bowling ball and the green_fn

The owner asked for "bowling ball + green fn basketball attacks" and, for the first,
that the player "must dodge or jump over it (ground roll, telegraphed wind-up, speed
data, fair window like the Gin sword)". Both attacks are rows in `_projectiles`, the
T8a shape plus `id`, `spawn_tick`, `age` and `life_ticks`; the whole row is hashed.

The bowling ball rolls FLAT on the arena floor at `floor + height_u / 2`, so its top is
`floor + height_u` (0.45 u). The hit test is a horizontal cylinder: the player is hit
when their feet are below that top and their column overlaps the ball's swept segment.
The player clears it by getting their feet above 0.45 u, which a normal jump does for
ticks 2.4..42.6 of its 45-tick airtime. The ball's own hit window is 7.3 ticks
(2 x (0.45 + 0.40) u at 14 u/s), so the jump covers it six times over. The test asserts
that arithmetic from `data/boss.json` and `data/player.json` rather than brute-forcing
it, then drives the real controller: a bot that jumps 20 ticks before arrival clears the
ball, a bot that stands still is hit.

The green_fn is aimed at the player's BODY CENTRE AT RELEASE, so it is exact where they
stood and stale the moment they move. Windup 30 ticks (500 ms) plus 40 ticks of flight
is 1150 ms from the visible wind-up to arrival, well over the owner's 400 ms floor, and
the 0.8 u sideways dodge takes 5.3 ticks of the 40-tick flight. The transform into
`peter_green_fn.png` is a VIEW state driven by the `boss_attack_windup` event, never a
sim field, so it cannot change the hash. The ground marker is view-only too; it needs
the player's position, so `boss_attack_windup` carries `player_position` - an event
field, and events are never hashed, so replays are unaffected.

## D-T8B-2 (2026-11-23) A cooldown between attacks, and why the contract grew

The T8a `tick()` alternated the two attacks with no gap: the bowling ball spawned on
tick 39 and the green_fn on tick 69, and because the ball is slow (14 u/s) and the shot
fast (24 u/s) they reached the player ONE TICK APART. A single 45-tick jump cleared
both, so the fight was one dodge wearing two costumes. `cooldown_ticks` (90, in
`data/boss.json`) now separates them: the ball arrives on tick 108, the shot on tick
199, 91 ticks apart. The test asserts the gap exceeds one jump's airtime, and a negative
control with `cooldown_ticks: 0` makes it fail with "attacks arrive 1 ticks apart".

This is the one place T8b extends the T8a contract, and it is additive: `cooldown_tick`
and `bankai_tick` join `snapshot()`, so the cadence and the cinematic clock are in the
state hash and a replay reproduces both. No T8a field changed and no T8a event changed
meaning. The header comment of `game/sim/boss.gd` lists every extension.

## D-T8B-3 (2026-11-23) The laugh, and the file the owner will drop in

The owner asked for "laugh on death" and supplied no audio. The placeholder is
synthesized by `game/tools/audio/synth_cues.gd` (group `boss`, cue `laugh`, seed 61,
1.40 s): five "heh" syllables, a glottal buzz stepping up from 104 Hz, two nasal
formants and a breath of noise. It is a placeholder for a laugh, not an impression of
one, and it is regenerated byte-for-byte by the same command as every other cue.

`game/view/audio/boss_audio.gd` checks `assets/owner_third_party/peter/laugh.ogg`,
`.mp3` then `.wav` FIRST and only falls back to the placeholder when none exists, so the
owner can drop the real clip in and nothing else changes. That folder is the one place
third-party art and audio live, so it can be removed in a single move. The load is gated
on `ResourceLoader.exists`, never `FileAccess.file_exists`, so an export still finds the
imported stream. `test_audio_cues_synth.gd` gains `BossAudio` and the `boss` group in its
MODULES/GROUPS tables - the drift check is extended, not weakened, and its `seen < 18`
floor is untouched.

The laugh fires on the `boss_laugh` event, which the sim emits in the same batch as
`boss_projectile_hit_player`. `laugh_ticks` is armed from data on that hit and is hashed.

## D-T8B-4 (2026-11-23) The Bankai easter egg: the sim owns the clock, the view owns the show

The owner asked for a "1/1000 Bankai easter egg using game/view/cinematics/
bankai_gift_animation.gd" where "the gifts target Peter and INSTA-KILL him".
D-T8B-9 supersedes the original odds, and D-T8B-11 supersedes the view clock below. The roll
was already T8a's (`bankai_selected`, one draw keyed by run seed and level, in sim, so
replays match). T8b adds activation, the kill and the finish.

The split is deliberate. The SIM owns the timing: `start()` sets `bankai_active` when the
roll selects, `bankai_tick` counts, and at `bankai.hit_tick` (1290 = 21.5 s) it emits
`bankai_hit` and kills Peter outright from full HP; at `bankai.end_tick` (1530 = 25.5 s,
the cinematic's `TOTAL_DURATION`) it emits `bankai_finished`. Both ticks are data.

`hit_tick` moved from 1260 to 1290 in review round 2. 1260 is the cinematic's own first
`target_hit`, which is the frame the FIRST gift lands - but the swarm keeps arriving for
another half second, so killing Peter on that exact tick let the sim's death race the
rest of the gifts. 1290 is 0.5 s later, after the swarm has landed, so the gifts always
finish arriving before Peter dies. The view additionally hides the sprite on the
cinematic's `target_hit` rather than on the sim's `bankai_hit`, so the visual death
coincides with the gifts and the sim's kill is the authority for the win flow. The VIEW owns the show: `boss_view.gd` creates
the cinematic on `bankai_started`, calls `play(_sprite)` so the gifts target Peter, and
follows `animation_started`, `target_hit` and `animation_finished` for presentation only.
The cinematic runs on render time and will drift from the sim's tick clock by a frame or
two; the sim is authoritative, so a replay reproduces the kill exactly and the view
merely follows. Nothing in the cinematic path reads or writes `sim/` or the state hash.

Input is locked while it plays, and that lock is SIM-side: `world.gd` already gates
`ctl.step` on `not boss.bankai_active`, so the player cannot move, throw or take the
beacon for the 25.5 s. The beacon opens at the kill (21.5 s) through the ordinary
`boss_died` path, so the 300 gold and the beacon are the framework's, unchanged.

The test finds a seed the roll selects, proves the roll and the whole event stream replay
identically, and asserts the kill lands on `hit_tick` from full HP and the finish on
`end_tick`.

## D-T8B-5 (2026-11-23) Telegraphs: the lane is committed at wind-up, and the marker runs on ticks

Review round 2 found the bowling wind-up had no visible cue at all: the delay was real
but the player could not tell an attack had started. It also found the green_fn's ground
marker expired after 40 RENDER FRAMES, so at 144 FPS it vanished after ~278 ms - before
the 500 ms wind-up had even finished - and that it marked the player's WIND-UP position
while the shot aims at their RELEASE position, so moving during the wind-up made the
marker a lie.

Three fixes, and the first one is a SIM change because the marker cannot be truthful
otherwise:

1. The bowling lane is committed at wind-up. `boss.gd` now stores `_aim` (a unit XZ
   direction) when the wind-up event fires and rolls the ball down that lane, and the
   wind-up event carries `aim` so the view can draw the exact lane. `_aim` is in
   `snapshot()`, so it is hashed and replays. Before this the ball re-aimed at the player
   at release, which meant any marker drawn at wind-up would have been a guess. The
   player can now read the lane and step out of it, which is the dodge the brief asks
   for. This is the one place the contract grew; it is additive (a new event key and a
   new snapshot field) and the header comment says so.
2. The marker's lifetime is tick-driven. `_age_marker()` runs at the top of `on_events`,
   which the world calls exactly once per sim tick, and counts down `MARKER_TICKS`. The
   `_process` override is gone, so the marker's life is the same at 30 FPS and at 240.
3. The green_fn wind-up claims no line. It shows a charge disc at Peter's feet - honest,
   because the shot is not aimed yet - and the real aim line appears on release, built
   from `boss_projectile_spawned`'s position and velocity. That line is the shot's actual
   path, not a prediction.

The bowling wind-up also swaps Peter to a held-ball pose with a `BOWLING_TINT` on the
sprite, so the pose change and the lane marker together read as "a bowling ball is
coming" without any text.

## D-T8B-6 (2026-11-23) The Bankai is sequenced: the sim clock is authority, the view sequences presentation

D-T8B-11 supersedes the independent presentation clock described here.

Review round 2 found the sequence was not actually sequenced. The sim clock killed Peter
and the view freed the cinematic independently, so under render drift Peter could die
before the gifts landed, and the node could be freed before `animation_finished` - which
bypasses the cinematic's own `stop()`, the only thing that restores the player's camera.

The split is now explicit:

- The SIM still owns the kill tick. `bankai.hit_tick` is 1290 (see D-T8B-4), after the
  swarm has landed, and `bankai_hit` is what the win flow keys off. A replay reproduces
  it exactly.
- The VIEW sequences the presentation. The sprite hides on the cinematic's `target_hit`,
  not on the sim's `bankai_hit`, so the visual death coincides with the gifts. The sim's
  `bankai_hit` is a fallback that only fires when `_bankai == null` (no cinematic to
  follow).
- `_release_bankai()` calls `stop()` before `queue_free()`, unconditionally, so the
  camera is restored on every path out - normal finish, sim finish, or teardown.
- `bankai_finished` does not free the node immediately. It arms `_bankai_grace`, a
  bounded countdown from `bankai.grace_ticks` (60 = 1 s) in data, aged per tick by
  `_age_bankai()`. If `animation_finished` arrives inside the grace the node is released
  by the signal; if the grace runs out first, `_release_bankai()` stops it explicitly.
  Either way the camera is restored and the node is freed exactly once.

`grace_ticks` is data, passed to the view through `setup()`, so the bound is tunable
without touching code.

Two source fixes fell out of making this testable headless, both in the dormant
cinematic and both real defects rather than test scaffolding:

- `play()` read `get_viewport().get_camera_3d()` unguarded. `get_viewport()` is null
  outside the tree, so the cinematic crashed anywhere it was driven without a viewport.
  It now guards, and null means "no camera to restore".
- The procedural rig was built only in `_ready()`, which does not run outside the tree,
  so `_anim_cam` was null and `play()` crashed. The build moved into `_ensure_built()`,
  called from both `_ready()` and `play()`, and the guard makes a second call a no-op.
  `_update_animation`'s `to_local(target.global_position)` is likewise skipped when
  neither node is in a tree, falling back to the cinematic's own target point.

## D-T8B-7 (2026-11-23) The Bankai input lock covers the look, not just the move

The lock was incomplete. `world.gd` gated `ctl.step` on `not boss.bankai_active`, which
stops movement, jumping and gift firing - but mouse-look is handled in `_unhandled_input`
and writes the rig's yaw and pitch directly, so the player could still swing the camera
around while the cinematic owned it. `_unhandled_input` now returns early on
`lstate.boss.bankai_active`, so the whole input surface is locked for the 25.5 s.

The lock stays SIM-side for movement (the sim must not advance the player, or a replay
would diverge) and view-side for the look (the look never touches sim state, so gating it
in the view is enough and keeps the sim free of input concerns).

## D-T8B-8 (2026-11-23) The window tests measure the window, in ticks, and the replay is a real replay

Two test defects, both found in review round 2.

**The window arithmetic mixed units.** Both calculations added a flight time in SECONDS
to a wind-up in TICKS and then multiplied the sum by DT, so the number they asserted was
not the wind-up-to-arrival time at all. Everything is now in ticks: airtime, flight,
hit window, dodge and the gap between arrivals. The arithmetic also measures travel to
CONTACT rather than to the player's centre - the projectile hits when its leading edge
meets the player's near edge, so the distance is `dist - (radius + half_width)`. That is
the shorter, honest window, and it is the number the sim actually produces.

**The arithmetic was only checked against itself.** A new `_measured_windows` leg runs
the real sim against a stationary player, records the tick the wind-up event fired and
the tick the hit landed, and asserts the measured wind-up-to-arrival count matches the
data within 2 ticks and clears the 400 ms floor. Measured: bowling 103 ticks against a
predicted 104, green_fn 67 against 68. The tolerance is 2 ticks because the sim's
discrete step can land the contact one tick either side of the continuous prediction.
This leg has teeth: with the pre-fix centre-distance arithmetic it failed by 5 ticks.

**The replay was not a replay.** The old leg ran the same scripted formula twice and
compared the hashes, which proves the sim is deterministic but not that a recorded
command stream reproduces it. `_record_and_replay` now does what the replay system does
(see `test_replay.gd`): run one records every command dict it issued, run two feeds that
captured stream back verbatim, and the state hash must agree at every 30th tick. It runs
twice - once for an ordinary fight (240 ticks, several attack cycles) and once for a
Bankai fight (past `hit_tick`, so the Bankai clock and the death are inside the hashed
span). A command that is not captured, or a sim field that is not hashed, shows up as a
divergence. The harness supports this shape, so no "harness cannot do it" caveat applies.

The negative control for the cooldown is unchanged and still works: setting
`cooldown_ticks` to 0 fails the gap assertion with "attacks arrive 1 ticks apart".
## D-ICON-1 (2026-11-23): the launcher icon is a procedural jump-pad render, seven sizes, one .ico

**Ruling.** The owner asked for a "custom launcher icon" (CYCLE7 brief, track T3: the
blocky avatar head or "the blue pad / void motif - pick one and make it read at 16 px").
Picked the blue pad motif: the icon is D-JUMPPAD-5's #1A2BFF slab seen top-down (the
owner's own ref, game/out/owner_refs/jumppad_ref.png) - a tilted rounded blue slab over
the dark plate with two cyan launch rings - drawn per pixel from signed-distance
functions with analytic coverage in game/tools/art/launcher_icon.gd. Deterministic,
reproducible with the one headless command; no external art, no randomness. Sizes
512/256/128/64/48/32/16 px land in game/assets/icons/launcher/voidwrap_<n>.png; the
512 px png is the project icon (application/config/icon in game/project.godot), and
game/tools/art/pack_ico.py packs the other six, PNG-compressed, into voidwrap.ico
wired as application/icon in game/export_presets.cfg preset.0 (PNG icon frames are
valid on every Windows since Vista). [CONTESTABLE] The icon is flat-shaded in the
house-icon palette plus the pad's two blues; Terra reviews the 512 png and the
palette/corner/stroke choices are retuned by re-running the single render command.

## D-ICON-2 (2026-11-23): rcedit is fetched by CI and the exe is spot-checked after export

**Ruling.** Godot applies the Windows exe icon with rcedit, which the repo does not
ship (never commit binaries). CI (build.yml, Windows job) now fetches rcedit v2.0.0
from the electron releases page, pins its sha256
(3e7801db1a5edbec91b49a24a094aad776cb4515488ea5a4ca2289c400eade2a), and writes
export/windows/rcedit into editor_settings-<major.minor>.tres before the export. A
second CI step after the export runs game/tools/art/dump_pe_icons.py (stdlib only)
against the built exe and FAILS the job when the six icon frames are not in the PE's
resource directory - a default-icon build cannot ship silently.

**One-time local setup** (same key CI writes): download rcedit-x64.exe (v2.0.0),
park it anywhere (repo convention: game/out/tools/, gitignored), then
Editor Settings > Export > Windows > rcedit = that path. Verified locally on this
machine: exporting preset.0 with the key set produces an exe whose .rsrc carries
the six 16/32/48/64/128/256 png frames and one RT_GROUP_ICON (dump_pe_icons output).
## D-JUMPPAD-6 (2026-11-23): a jump pad is a 3x3 BLOCK of floor tiles, outside the paths

**Owner's words (cycle 7 brief, T6):** "jump pads revamp (3x3 tiles, outside paths, 2 to 6 per level)" and
"Pads must be 3x3 TILES big and NOT on the paths: outside the paths (adjacent to them), never on
mines/gifts/beacon/hub/stairs. Count per level: minimum 2, maximum 6 on big levels (scale with level size; in
data)."

**Ruling.** `L["jump_pads"]` entries are still `[x, z, y]`, but they are now the CENTRE tile of a
`size_tiles` x `size_tiles` block (`data/jump_pads.json`, 3 -> a 3x3 block, `half_extent()` = 1,
`footprint()` lists the 9 cells). A block is legal only when all 9 cells exist at that one height and every
one of them is a FLOOR tile (piece `kind` 0) of a non-hub platform piece, with no ramp tile (`t[3] != 0`), no
prop, and none of them a gift slot, a tripmine slot, the beacon tile, a launch pad or its landing tile. The
count comes from `count_by_level`: 2 at level 1, 3 from 4, 4 from 8, 5 from 14, 6 from 20.

**Why the pads left the walkways.** The old rule put a pad on a walkway's side lane, one tile beside the
centre lane. A walkway is exactly 3 tiles wide (`WALK_W`), so a 3x3 block on it always covers the centre lane -
it would be ON the route, which the owner forbids. There is no 3x3 block that both sits on a walkway and
misses its middle line, so "3x3" and "never on the route" together mean the pad must be off the walkway
entirely. The floor tiles beside the path are the platform pieces, which is where the pads now go: the block
is on the platform, the walkway runs past its edge. That is also what the owner's reference
(`game/out/owner_refs/jumppad_ref.png`) shows - a big blue slab on the floor with the checkered path at its
corner.

**"Never on" replaces "never on or beside".** The old placement banned the 8 neighbours of every gift, mine
and launch pad. The owner's new wording is "never on mines/gifts/beacon/hub/stairs", so the ban is now the
exact tile. This is not a relaxation for convenience: it is what the brief says, and it is what makes 2..6
pads possible at all - the 8-neighbourhood ban covers 9 cells per gift/mine/launch pad, and on a level with
~15 gifts and ~6 launch pads that is ~190 of ~900 tiles, which left several levels with no legal 3x3 block
anywhere (measured: seed 1 level 3, seed 7 level 3, seed 42 level 20 and others had zero). A pad may now sit
right beside a gift or a mine, never over one.

**Count floor.** CORRECTED in review round 1: the floor of 2 is NOT reachable on every level once edge
adjacency is enforced (D-JUMPPAD-7 has the numbers - 15 of 160 measured levels get fewer than 2, all on levels
1-5). The code never invents a spot: it places `min(count_by_level, what the greedy can take)`, and the test
asserts that a level which gets fewer than it wants is MAXIMAL - no further legal block could be added without
overlapping a placed pad - and that no more than `SHORT_MAX` of its 64 levels fall short.

## D-JUMPPAD-7 (2026-11-23, rewritten in review rounds 1 and 2): edge adjacency is a HARD rule

**Owner's words (cycle 7 brief, T6):** "jump pads revamp (3x3 tiles, outside paths, 2 to 6 per level)" and
"Pads must be 3x3 TILES big and NOT on the paths: outside the paths (adjacent to them)".

**Ruling.** A block is a candidate only when BOTH hold: (a) none of its 9 tiles is a path tile (D-JUMPPAD-6),
and (b) at least one tile on the RING OUTSIDE the block - the 12 cells that share a side with its 3x3
footprint, never a diagonal and never a cell inside the footprint - is a path tile within `path_step_hu`
(data, 4 HU) vertically. A block with no such neighbour is not a candidate at all, so a pad can never sit out
on a platform away from every path. Candidates are then taken in the pad stream's shuffled order, greedily
with `min_spacing_tiles`, and if that lands below the floor of 2 a two-pad arrangement is searched for before
a shortfall is accepted.

**The ring, not the footprint (review round 2).** The first version walked the 4-neighbourhood of every block
cell, which includes the neighbours of the INTERIOR cells - other block cells - so a walkway one or two HU
above or below a block tile counted as "adjacent" without being beside the block's edge. Terra caught it. The
ring is now walked directly: offsets of exactly `half + 1` on one axis and at most `half` on the other, which
is 12 cells for a 3x3 block. The test's checker is written from the rule (the four sides of the block's
rectangle) rather than copied from the implementation, and a synthetic fixture pins it: a 5x5 platform with
one walkway tile either under the block's centre (must NOT be a candidate) or on its ring (must be). Real
levels almost never stack a walkway on a platform within `path_step_hu`, so no sweep could have caught this.

**The greedy can strand a legal pair (review round 2).** Taking candidates in shuffled order can pick a block
that is too close to BOTH members of a pair that would have satisfied the spacing, and then report a shortfall
that is not real - Terra's case is level 3 seed 11, which placed 1 pad while two candidates 4 tiles apart were
legal. `place_jump_pads` now runs an exhaustive pair scan (`_first_pair`) whenever the greedy lands below the
floor of 2, and only accepts the shortfall when no pair exists. The candidate count is 6..17 per level, so the
scan is at most ~136 distance checks and is deterministic (shuffled order, first pair). The test's shortfall
assertion is the same proof from the other side: `_no_pair` scans every candidate pair, so a level is only
excused when no two-pad arrangement exists at all - "can one be added to what we placed" is not enough.

**This replaces the round-1 rule, which was wrong.** Round 1 ordered candidates by a "gap" to the nearest
walkway and took them nearest-first, but never filtered on it: a block at gap 99 was still a candidate. Terra
rejected that as the track's main requirement, correctly. The old gap metric was also looser than adjacency -
it used Chebyshev distance to the nearest walkway within 4 HU, so a diagonal or two-cells-away path tile
scored gap 0 - which is why the round-1 report claimed "510 of 570 pads at gap 0" while also claiming a
one-tile cap left zero legal blocks on most levels. Both numbers were real, but they measured different
things, and the histogram was not evidence of adjacency. The honest numbers are below.

**Same-height adjacency is impossible on this generator.** voidgen steps a walkway 1-2 HU off the platform it
runs beside at the junction, so a path tile is almost never at the same height as the platform floor next to
it. Measured over 20 seeds x 8 levels (160 levels): 23 same-height path/floor edge pairs in the whole sweep,
against 2127 at +1 HU and 1257 at +2 HU. A strict same-height rule leaves 0 legal blocks on 20 of 20 levels at
level sizes 2, 5, 8, 12 and 20, and never more than 4 blocks on any level anywhere. It cannot deliver the
owner's floor of 2 without changing the generator, and the generator is frozen (GEN_VERSION 4, PARITY,
GALLERY_PIN). `path_step_hu` = 4 is therefore the tolerance: it covers the junction step and the first stair
row, and stays well under `CLEAR` (12 HU), so a walkway on another storey can never satisfy it. This is the
one place where the rule is not literally "same height", and it is stated here rather than hidden.

**The funnel, measured (20 seeds x 8 levels, shipped data).** Legal blocks (all 9 tiles free floor, no ramp,
non-hub, no prop, no gift/mine/beacon/launch pad) average 14.9 at level 1 rising to 34.8 at level 20. Of
those, edge-adjacent blocks average 6.0 at level 1, 4.8 at level 2, 6.1 at level 3, 6.8 at level 5, 8.2 at
level 8, 13.2 at level 12, 16.9 at level 20 and 15.7 at level 30. Pads PLACED average 1.75 / 1.80 / 1.75 /
2.60 / 3.25 / 3.85 / 5.50 / 5.65 on the same levels.

**The floor of 2 does not hold everywhere, and this is the honest number.** Over those 160 levels, 14 get
fewer than 2 pads: level 1 seeds 7, 11, 29, 37; level 2 seeds 17, 37, 43, 2024; level 3 seeds 1, 17, 31, 53;
level 5 seeds 7 and 60717. Every one is PROVEN pair-free - the closest candidate pair is 1.00, 2.00 or 2.24
tiles apart against a spacing of 4, or the level has fewer than 2 candidates at all (level 1 seed 37 has
none) - so the shortfall is the level's geometry, not the greedy's. Levels 8, 12, 20 and 30 always reach 2.
The test's own sweep (9 seeds x 8 levels = 72 levels, seed 11 included because it is Terra's stranded-pair
case) has 6 such levels - level 1 seeds 7 and 11, level 2 seed 2024, level 3 seed 1, level 5 seeds 7 and
60717 - and `SHORT_MAX` pins that number: the test asserts every short level is pair-free AND that no more
than 6 of the 72 fall short, so a regression that starves more levels fails instead of hiding behind "the
level had no room". The brief's escape clause ("never fewer than 2 unless the level genuinely has no room -
if that can happen, say so in a D-entry and in the test") is what this paragraph is.

**`min_spacing_tiles` 8 -> 4.** 4 is the smallest spacing that leaves a gap between two 3x3 blocks (centres
4 apart = one empty tile between). 8 was tried and cost pads on the big levels (level 20 average 5.25 instead
of 5.50) without helping the floor of 2 anywhere; 3 (blocks touching) rescues no level either, so 4 is the
tightest spacing that still reads as two separate pads.

**The one-pad-per-platform rule is gone.** It was a round-1 invention, not the owner's, and with edge
adjacency it only removed pads from levels that had few candidates to begin with.

## D-JUMPPAD-8 (2026-11-23): the sim fires from any of the 9 cells, and the collapse takes the whole block

**Ruling.** `sim/jump_pads.gd` maps EVERY cell of a pad's block to that pad id (`_at`), so `pad_at()` finds the
pad from any of the 9 tiles and `tick()` fires for a player standing on any of them. The tile-alive check in
`tick()` is now the cell the player actually stands on (`floor(x), floor(z)`), not the block's centre, so a
curse that removes one cell stops the pad only for a player on that cell. `tile_keys(i)` returns all 9
collision keys; `sweep()` drops the pad when ANY of them falls in the platform collapse (the pad goes down
with the tile it lost), and the view hides the pad while any of its cells is in the world's removed set.
`tile_key(i)` still returns the centre key. Launch, refill, re-arm, the hash and the collapse behaviour are
otherwise unchanged: same 20 u/s fling, same `jump_pad_launch()` refill list, same 30-tick re-arm, same
`_sync_row` on the launch tick.

## D-JUMPPAD-9 (2026-11-23): the 3x3 slab, and the state hash line grows a size field

**Ruling.** `view/jump_pad_view.gd` draws the same saturated glossy blue rounded slab, now 2.9 u across (the
3 u block less 0.05 u a side, so it never overhangs the block), 0.55 u corner radius, 0.10 u bevel, same
0.16 u height, same 0.012 u lift, same colour and glow. The squash / rebound curve, the re-arm dimming and the
1 Hz pulse are untouched; the two ripple rings now start at 1.5 u and expand to 4.4 u so they still read
around a pad three times the size. The slab is centred on the anchor tile, so it covers the whole block.

**State hash.** The `JUMPPADS` line gains a trailing `size_tiles` field: the coordinates are the block's
centre, and the block size is data (`data/jump_pads.json`) that the level hash does not cover, so without it
two runs whose data differed in `size_tiles` would hash alike while the pads covered different tiles. The line
is still written only when the level carries pads, so a level built without them keeps its exact dump. The
hash VALUE changes for every level that has pads - that is the point of the revamp, not a regression - and no
golden fixture pins a state hash: `test_replay.gd` compares runs against each other, and the jump-pad suite
compares a run against its own replay, so nothing had to be re-pinned. The determinism tests are unchanged and
none was weakened.

## D-T8B-9 (2026-11-23) Cycle 8: increase the seeded Bankai threshold

The owner asked for 1 in 250, so the threshold is 0.004. The single draw remains
keyed by run seed and level at fight start, unchanged in shape: one
`_roll(VoidRng.mix(run_seed, level_no), chance)` at fight start, no second draw,
no wall-clock or frame-count input. In the level-10 sweep of seeds 0 through 4095,
the old 0.001 threshold selected 839 and 1364. The new threshold selects 18 seeds:
70, 192, 297, 839, 1364, 1517, 1577, 1662, 1810, 1979, 2128, 2596, 2726, 3279,
3448, 3734, 3769 and 3963. These seeds cross the increased threshold on the same
draw, which changes their hashed Bankai selection and ensuing fight trace. The
replay test dynamically chooses the first selected seed, so its Bankai leg moves
from 839 to 70. The framework test now pins the full selected set in this sweep.
The terrain gallery pins terrain hashes, and the boss replay checks compare traces
between runs, so there are no stored hash values to re-pin.

A note on how this entry was reached, because it is a process lesson rather than a
design one: the first pass shipped 0.0025 and documented it as "1 in 400, an exact
1 in 250 would be 0.004". That was the worker correctly reading a wrong number out
of its brief - the orchestrator had written 0.0025 next to the words "1 in 250".
The worker flagged the discrepancy instead of silently matching either the number
or the words, which is why it was caught before the merge. The owner's intent is
the odds, not the decimal, so the decimal was corrected to 0.004 and the pinned
seed set recomputed from the RNG rather than guessed.

## D-T8B-10 (2026-11-23) Cycle 8: the owner's voice and procedural support cues

The unset Bankai voice resolves through the export-safe audio loader to the
existing custom_voiceline.mp3. Both supplied and imported source files have MD5
298fab131793a4edb83d835cfb201d79. The former fight-only assignment to the second
voice slot is superseded by this fallback, shared with the tester preview.
View-only PCM synthesis generates a looping hum at tick 0, charge at 612, impact
at 750, volley at 1200 and kill at 1290. Their playback gains are respectively
-28, -19, -17, -21 and -16 dB, with the owner voice at 0 dB.
The windowed FORCE BANKAI probe observed playback at tick 468 (7.800 s) and the
audio player's natural finished signal at tick 711 (11.850 s). The initial
capture observed the finished signal at tick 702 (11.700 s). Audio completion
is sampled against the arena clock when the mixer delivers the callback, so
that observation can vary between runs. Both finishes precede the kill at
21.5 s and the cinematic end at 25.5 s.

## D-T8B-11 (2026-11-23) Cycle 8: the planted sword starts the camera pull-back

The sword tip reaches the floor at tick 750. The camera leaves the first-person
rig at that tick, eases backward from the same pose and orbits until the end,
revealing the live player model as it clears the camera. The arena floor bounds
keep the camera inside the footprint with near-plane clearance. The view reads
the arena's Bankai clock and interpolates the pose between ticks. The sim still
kills at 1290 and releases input at 1530, when the view restores the first-person
camera and model visibility. FORCE BANKAI activates this same clock in an active
fight, including the ordinary kill, 300 gold award and beacon. The headless
test exercises the real buttons and the full sequence at 30 and 144 FPS.
