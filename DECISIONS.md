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

---

## Handover log

(append one line per session: date, who, what is finished, what is next)

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
