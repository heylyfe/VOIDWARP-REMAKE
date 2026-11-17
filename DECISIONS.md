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

## Handover log

(append one line per session: date, who, what is finished, what is next)
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
