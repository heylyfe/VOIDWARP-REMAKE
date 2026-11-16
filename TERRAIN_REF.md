# TERRAIN_REF.md — the working terrain reference

Spec: `TERRAIN_SPEC.md`. This file says what exists, how to run it, what it measured, and how to port
and extend it. **Port and extend this. Do not invent a second generator.**

## 1. Files

| file | role | author | lines |
|---|---|---|---|
| `terrain_ref/voidgen.py` | THE ORACLE. Pure generator, stdlib only, integer-only. `generate(seed, level, players=1, extra_mines=0)` | lead (Fable 5.2) | ~1,525 |
| `terrain_ref/validate.py` | independent validator + harness (own movement graph and its own shape metrics, recomputed from the Level dict; imports only `generate`, `level_hash`, `slot_target`, `mine_chance_num`) | GLM 5.3 Flash, from TERRAIN_SPEC §10 | ~1,777 |
| `terrain_ref/test_validate.py` | plain-assert unit tests | GLM 5.3 Flash | |
| `terrain_ref/gallery.py` + `gallery.json` | 16 pinned (seed, level) goldens: `--check`, `--write`, `--render` | Inkling 2 Small | |
| `terrain_ref/render.py` | stdlib PNG top-down renderer + contact sheets | Inkling 2 Small | |
| `terrain_ref/out/` | renders and reports (gitignored) | | |
| `game/terrain/voidgen.gd`, `void_rng.gd` | GDScript port (what ships) | GLM 5.3 Flash | |
| `game/tests/test_terrain_parity.gd`, `parity_cases.json` | hash parity: 16 gallery + 40 extra cases | GLM 5.3 Flash | |
| `game/tools/terrain_hash.gd`, `dump_text.gd`, `make_parity_cases.py` | port debugging tools | GLM 5.3 Flash | |

Why the validator has a different author than the generator: the generator already contains a
movement graph (it needs one to place gifts). A validator that reused it would agree with it by
construction. Two implementations from one spec that agree on 5,000 levels is evidence.

## 2. Verify (run from the repo root; every command must exit 0)

```powershell
python terrain_ref\test_validate.py                 # unit tests -> "TESTS OK"
python terrain_ref\validate.py --selftest           # 12 planted defects must each be caught -> "SELFTEST 12/12"
python terrain_ref\gallery.py --check               # -> "GALLERY 16/16 OK"
python terrain_ref\validate.py --seeds 0:5000       # all H and D checks over 5,000 seeds, ~3 min
tools\godot\godot.exe --headless --path game --script res://tests/test_terrain_parity.gd -- "$PWD\terrain_ref\gallery.json"   # -> "PARITY 56/56 OK"
```

Look at levels:
```powershell
python terrain_ref\voidgen.py --seed 1 --level 1 --ascii
python terrain_ref\voidgen.py --seed 7 --level 30 --json terrain_ref\out\l30.json
python terrain_ref\voidgen.py --seed 7 --level 30 --text terrain_ref\out\l30.txt     # canonical text (what is hashed)
python terrain_ref\render.py --seed 7 --level 30 --out terrain_ref\out\l30.png
python terrain_ref\render.py --sheet terrain_ref\out\sheet12.png --level 12 --seeds 0:12
python terrain_ref\validate.py --one 7 30          # metrics + fails for one level
```
Render legend: cyan checker = platforms, pale cyan = dead-end platforms, blue = walkways, purple =
two-way shortcut bridges, orange = drop ledges, white = launch pads, gold dots = gifts, pink dots =
tripmines, grey = props, white/red square = beacon. Brighter = higher.

## 3. Status and measured results

STATUS (updated 2026-11-16, shape-contract session — see the Handover log in DECISIONS.md for the
latest line; if the two disagree, the Handover log wins):

<!-- STATUS-BEGIN -->
- `voidgen.py`: FROZEN at GEN_VERSION 2 (shape contract, TERRAIN_SPEC §1A). Gallery 16/16.
- `validate.py`: `TESTS OK`, selftest 12/12 (one planted defect per hard check, H3–H22).
- OFFICIAL HARNESS, 5,000 seeds (levels 1–30), run after the last generator edit, exit 0:
  H1–H22 all `failures=0/5000`. D1 max deviation 0.40 pp (limit 1.0) · D2 300/300 at cap ·
  D3 5,000 distinct hashes · D4 p99 0.400, max 0.520, 0 pairs ≥ 0.60 — anchored to the spawn root
  with all 8 symmetries (D-022 FINAL) · D5 0 identical recipes · D6 1.74% (limit 10%) ·
  D7 bucket means 78.6 < 150.7 < 182.5 < 197.4 < 208.1 < 216.3 · D8 level-1 J mean 12.6 (limit 50),
  max 67.5 (limit 80) · D9 29 ms mean, 132 ms max. 48 s wall time on 12 cores.
  Full per-bucket table: `terrain_ref/out/report.json`.
- Shape metrics over the same 5,000 seeds (bucket means, min/max): path share 0.85 (min 0.77, floor
  0.70) · path tile share 0.67–0.76 (min 0.51, floor 0.50) · flat share 0.02–0.03 (max 0.20, cap 0.35) ·
  ramp share 0.01–0.02 (max 0.09, cap 0.10) · elevation sd 9.9 → 13.9 HU (min 3.10 at L1, floor 3) ·
  junction step share 98.9–99.6% (min 71.4%, floor 50%) · platforms 4.1 → 11.5 per level ·
  walkways 21.8 → 63.6 per level.
- GDScript port: DONE. `PARITY 56/56 OK`, gallery pins 16/16, 43 ms per level (Godot 4.7.2 headless).
<!-- STATUS-END -->

Measured while tuning the shape contract (independent quick scripts, 80–600 seeds per level):

| what | measured | limit |
|---|---|---|
| generation time, Python | 0.019 s (L1) … 0.039 s (L30) mean, 0.094 s worst | mean ≤ 0.25 s |
| first gift from the beacon (H10) | ≤ 15 cells worst case | ≤ 30 |
| starvation p95 (H11) | 8.8–10.6 cells mean, 25 worst | ≤ 27 |
| starvation max (H11) | 9.8–11.0 mean, 25 worst | ≤ 54 |
| playable area (H9) | 100.0% | ≥ 98% |
| fair reach (H13) | 0 failing slots in 5,000 levels | 0 |
| jump share J at level 1 (D8) | mean 12.6%, max 67.5% | mean ≤ 50, max ≤ 80 |
| J by level | L1 25 · L6 74 · L11 90 · L16 93 · L21 94 · L26 94 | rising |
| difficulty score D by bucket (D7) | 78.6 · 150.7 · 182.5 · 197.4 · 208.1 · 216.3 | strictly increasing |
| within-level platform repetition (D6) | 1.74% mean | ≤ 10% |
| identical recipes (D5) | 0 of 5,000 same-level pairs | ≤ 0.1% |
| footprint similarity, 4-cell blocks, spawn-anchored (D4) | p99 0.400, max 0.520, 0 pairs ≥ 0.60 | p99 ≤ 0.50; ≥ 0.60 in ≤ 0.1% |
| re-roll rate (attempt > 0) | 12% at L1, 6% at L5, 0.5% at L30; max attempt seen 4 | attempt ≤ 12 |
| shortcuts per level | 0.7 (L1) · 1.0 (L6) · 2.0 (L26) | ≥ 1 |
| mine rate vs curve (D1), 5,000 seeds | max deviation 0.40 pp | ≤ 1.0 pp |
| `extra_mines = 999` (D2) | 300/300 exactly at S // 5 | all |
| path share of walkable length (H19) | 0.85 mean, 0.77 worst | ≥ 0.70 |
| walkway tiles / non-hub walkable tiles (H19) | 0.67–0.76 mean, 0.51 worst | ≥ 0.50 |
| flat share of path rows (H20) | 0.02–0.03 mean, 0.20 worst | ≤ 0.35 |
| ramp share of path rows (H20) | 0.01–0.02 mean, 0.09 worst | ≤ 0.10 |
| elevation sd over non-hub tiles (H21) | 9.9 (L1–5) → 13.9 (L26–30) HU, 3.10 worst | ≥ 3 at L1 → ≥ 6 at L10 |
| sub-area boundaries with \|Δy\| ≥ 1 (H22) | 98.9–99.6% mean, 71.4% worst | ≥ 50% |
| platforms per level (H18) | 4.1 (L1–5) → 11.5 (L26–30) | 3 … min(12, 4 + level // 3) |
| walkways per level | 21.8 (L1–5) → 63.6 (L26–30) | — |

Checks that failed on first measurement were fixed IN THE GENERATOR (D-018, D-019, D-020, D-025); one
metric definition was corrected with its reasoning on record (D-022). No threshold was moved after
measurement (D-030).

## 4. Pinned gallery (GEN_VERSION 2) — `terrain_ref/gallery.json` is authoritative

| # | seed | level | attempt | platforms | tiles | slots | mines | bridges | drops | pads | dead ends | arms | hash (first 12) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 1 | 0 | 4 | 472 | 40 | 0 | 1 | 1 | 0 | 2 | descent, grand | `dc39af142bea` |
| 2 | 2 | 1 | 2 | 4 | 526 | 40 | 0 | 0 | 1 | 1 | 3 | thin, hop, grand | `482c6bc269b5` |
| 3 | 3 | 1 | 1 | 4 | 614 | 40 | 0 | 1 | 0 | 0 | 3 | grand, descent | `11eaa0e87315` |
| 4 | 1001 | 2 | 0 | 3 | 530 | 44 | 0 | 2 | 0 | 0 | 2 | ascent, grand, maze | `3a30caacb8f2` |
| 5 | 1002 | 3 | 0 | 4 | 485 | 48 | 0 | 0 | 2 | 0 | 2 | maze, hop | `d4582d560670` |
| 6 | 1003 | 4 | 2 | 4 | 472 | 52 | 0 | 1 | 1 | 0 | 3 | thin, descent | `4519ab45eda8` |
| 7 | 1004 | 5 | 1 | 4 | 503 | 56 | 1 | 1 | 1 | 0 | 2 | descent, thin | `01c3d52f7668` |
| 8 | 1005 | 8 | 0 | 6 | 590 | 68 | 7 | 1 | 0 | 0 | 3 | descent, grand, thin, hop | `15176cd76f22` |
| 9 | 1006 | 10 | 1 | 7 | 626 | 76 | 7 | 3 | 0 | 0 | 2 | maze, grand | `2920985e848c` |
| 10 | 1007 | 12 | 4 | 7 | 614 | 84 | 3 | 1 | 1 | 0 | 4 | hop, thin, descent, maze | `cdfa8bd63b9a` |
| 11 | 7 | 12 | 0 | 8 | 649 | 84 | 8 | 0 | 3 | 0 | 3 | thin, maze | `c760b25d529b` |
| 12 | 1008 | 16 | 2 | 8 | 684 | 100 | 16 | 3 | 2 | 0 | 5 | maze, descent, hop, grand | `89f91eb6db5a` |
| 13 | 1009 | 20 | 0 | 10 | 697 | 116 | 9 | 2 | 2 | 1 | 5 | descent, maze, hop, descent | `9a1a5d95d216` |
| 14 | 1010 | 25 | 2 | 12 | 884 | 136 | 17 | 3 | 2 | 1 | 5 | hop, maze | `fe2a678ab948` |
| 15 | 7 | 30 | 1 | 12 | 907 | 156 | 17 | 1 | 1 | 0 | 6 | ascent, maze, hop, grand | `ce3a65176828` |
| 16 | 1011 | 40 | 1 | 11 | 778 | 160 | 13 | 4 | 2 | 2 | 4 | maze, ascent | `c3ad1b8fb805` |

Reading the table as a regression check without eyes: slots follow `40 + 4*(level-1)` capped at 160;
mines are 0 below level 5 and never above `slots // 5`; every entry has at least one bridge or drop;
platforms grow with level and never exceed `min(12, 4 + level // 3)`; the arms column is the sorted
trait list. The gallery pairs draw only a handful of distinct trait pairs, which is why D5 counts the
walkway-archetype multiset as well as the platform one.

## 5. Port guide (Python → engine)

The port is line-by-line, not a re-implementation. Parity is binary: SHA-256 of the canonical text
(TERRAIN_SPEC §8.2) is equal or the port is wrong.

1. Port top to bottom in file order; keep function names.
2. Keep every `& M32`. `mul32` never exceeds 2^48.
3. Python `//` and `%` are only ever applied to non-negative values; `rdiv` handles signs explicitly.
4. Tuple-keyed dicts → `Vector2i` / `Vector3i` keys or packed ints. Lookups only. Never iterate a
   dictionary to produce output.
5. RNG draw order is the contract. Where one Python expression contains several RNG calls (list
   literals of sockets, tuple assignments), evaluate them into locals left to right first.
6. Conditional draws: `x if cond else y`, `a and rng...`, and `ri(a, b)` with `b <= a` do NOT draw
   when skipped. Reproduce exactly.
7. Sorting: `rem.sort()` sorts pairs by first then second element → explicit comparator.
8. The entry-socket identity test (`s is e`) → compare indices.
9. Debug loop: `game/tools/dump_text.gd` vs `python voidgen.py --text`, diff, the first differing
   line names the phase: `ARMS` → plan stream; first differing `P`/`T` → growth (which piece → which
   archetype function); `E` with kind 1/2/3 or pieces `bridge`/`jut` → shortcut phase; `G` positions →
   gift placement; `G` last column only → mine roll.
10. Pitfalls actually hit during the port are appended below by the porting worker.

<!-- PORT-PITFALLS-BEGIN -->
Hit during the GDScript port (Godot 4.7.2) — result: PARITY 56/56, byte-identical canonical text, ~146 ms per level:
- `trait` is a reserved word in Godot 4.7: a parameter named `trait` does not parse → `trait_name`.
- A global `class_name` does not resolve in headless `--script` mode (no editor scan) → every cross-file reference uses `preload`.
- An Rng method named `range` shadows the global `range()` inside the class, so `for i in range(n)` would silently draw RNG → the method is `urange` in `void_rng.gd`.
- No list comprehensions → explicit loops, same order.
- A `var` declared inside one loop body is not visible in a later loop → declare again.
- `var ramp := a and rng.chance(...)` cannot infer a type → write `: bool`.
- Confirmed necessary: literal `-30` for `-DROP_MAX // 2`; index comparison for the entry socket; `sort_custom` for pair sorts; hoisting RNG calls out of array literals; `>=` in the deepest-socket scan; the turn-bias loop reads `op[si]` live each iteration.

Hit during the GEN_VERSION 2 port (shape contract) — result: PARITY 56/56, 43 ms per level:
- The growth loop now carries mutable state across attempts (`state` Dictionary: `placed`, `since`, `dead`, `socks`, `drift`) and a `drift` int. Pass them as parameters; do not re-derive them inside `try_grow` — the Python mutates the caller's dict.
- `state["dead"]` is a list of sockets: `append_array` for the extend, and compare sockets by index, never by value.
- `try_loop(..., ray = -1)` uses a default parameter to mean "use `tuning()["ray_len"]`". GDScript default parameters must be constants, so `-1` is the sentinel and the real value is read inside.
- Python's `if not res:` on a function that returns `False` or a list → in GDScript `typeof(res) != TYPE_BOOL` is the test; `not res` is a parse error on a Variant.
- Integer division warnings are errors in this project's settings: `@warning_ignore("integer_division")` is needed on `plat_pad`, `plat_cross`, `plat_ell`, `plat_nook`, `plat_bastion`, `try_grow`, `try_loop` and `build`.
- The elevation standard deviation uses `sqrt()` on a float accumulator; keep the integer sum of squares and divide by the count before the root, in the same order as Python, or the rejection threshold flips on a boundary seed.
- `ri(a, b)` with `b <= a` draws nothing in Python; the GDScript `ri` must keep that early return, otherwise the rejection loop desynchronises the stream.
<!-- PORT-PITFALLS-END -->

Change procedure for ANY generator edit (binding): edit `voidgen.py` → `validate.py --seeds 0:5000`
green → bump `GEN_VERSION` → `gallery.py --write` → update TERRAIN_SPEC → port the same edit to
`voidgen.gd` → parity green → `make_parity_cases.py` re-run. Never edit the GDScript first.

## 6. Extending the terrain (drop-in points inside the generator)

| to add | where | cost |
|---|---|---|
| a platform archetype | a `plat_<name>(rng, t, gentle)` function + `_plat` dispatch + `PLATS` + a `plat_w` weight (+ trait multipliers). Contract: return `(tiles, socks, props, anchors)`; bbox ≤ 7×7 and ≤ 40 tiles (H18); sockets on extreme tiles; every internal height step ≤ AUTH envelope both ways or optional (like the spire overlook); props only via `scatter` or on perimeter tiles | GEN_VERSION bump |
| a walkway archetype | a branch in `build_walkway` + `WALKS` + `walk_w` + trait multipliers. Contract: width 1 or 2 only (H17), straight, two-way inside the AUTH envelope, and it must change height by a step at each end (H22) | GEN_VERSION bump |
| an arm trait | `TRAITS` + the three trait tables (`TRAIT_LINK`, `TRAIT_ROOM`, `TRAIT_UP_PCT`) | GEN_VERSION bump |
| a slot-replacing hazard | a new `occ` value rolled in `roll_mines` (rename to `roll_hazards`) under the SAME 20% total cap | GEN_VERSION bump; H5 extended |
| a terrain-affecting modifier | new trailing int parameter of `generate` with default 0 that reproduces today's hash | goldens unchanged when 0 |
| a new anchor kind | new `AN_*` constant emitted by archetypes | GEN_VERSION bump |
| biome / palette / dressing | NOT here — view layer (DESIGN.md §10) | none |

Tuning without code: every number is in `tuning()` (TERRAIN_SPEC §9). Measured headroom (D-021) says
levels can get ~2× sparser before H11 is at risk. The shape contract's own numbers (hub size, max
walkway width, max platform size, platform count, path share, flat/ramp share, elevation floor,
junction rule) are NOT tuning knobs — they are H16–H22 and live in `validate.py` as constants.

## 7. What the engine does with a Level

1. `var L = VoidGen.generate(run_seed, level, players, extra_mines)` (≤ 0.5 s expected at level 30).
2. Mesh: `view/level_mesher.gd` (FLEET_PACK T-011) from `tiles`, `props`, `pieces[].role`.
3. Collision: `sim/collision.gd` queries the same tile/prop arrays (no physics engine).
4. Gifts: one entity per `gifts[i]` — black if `occ == 0`, tripmine if `occ == 1`; gold later at the
   same index. No code outside the generator computes a gift position.
5. Beacon at `beacon`, players at `spawns[i % 8]`.
6. Enemies read `anchors`; bots and enemy pathing may rebuild the movement graph (TERRAIN_SPEC §5).
