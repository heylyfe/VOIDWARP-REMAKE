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
