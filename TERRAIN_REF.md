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
python terrain_ref\validate.py --selftest           # 18 planted defects must each be caught -> "SELFTEST 18/18"
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

STATUS (updated 2026-11-19, job J1 — GEN_VERSION 4; see the Handover log in DECISIONS.md for the
latest line; if the two disagree, the Handover log wins):

<!-- STATUS-BEGIN -->
- `voidgen.py`: GEN_VERSION 4 (job J1, out/decisions/J1.md D-J1-1): every walkway exactly 3 cells wide,
  every walkable piece at least 3 wide, every gift slot on a centre lane, the `w1_pct` ramp removed.
  Built on GEN_VERSION 3 (shape contract §1A + tripmine bypass §6.8, D-026). Gallery 16/16, regenerated.
- `validate.py`: `TESTS OK`, selftest 18/18 (one planted defect per hard check H3–H25, two for H17
  — too narrow and too wide — and three for H23). H17 is now "every walkway row exactly 3"; H24
  (min width 3 everywhere) and H25 (gift on a centre lane) are new (D-J1-2).
- OFFICIAL HARNESS, 5,000 seeds (levels 1–30), GEN_VERSION 4, exit 0, **34 PASS / 0 FAIL**:
  H1–H25 all `failures=0/5000`. D1 max deviation 0.39 pp (limit 1.0) · D2 300/300 at
  `min(S // 5, eligible)` · D3 5,000 distinct hashes · D4 p99 0.436, 0 pairs ≥ 0.60 — anchored to the
  spawn root with all 8 symmetries (D-022 FINAL) · D5 0 identical recipes · D6 0.59% (limit 10%) ·
  D7 bucket means 62.5 < 124.9 < 151.9 < 163.8 < 174.8 < 179.9 · D8 level-1 J mean 8.2 (limit 50),
  max 65.0 (limit 80) · D9 122 ms mean, 336 ms max. 779 s wall time on 4 jobs (machine shared).
  (GEN_VERSION 3, for comparison: 32 PASS, D9 55 ms mean / 191 ms max, D7 80.5 → 215.6 — D fell
  because the metric N, the width-1 share, is now 0 by construction, TERRAIN_SPEC §10.4.)
- Shape metrics over the same 5,000 seeds (bucket means, min/max): path share 0.83–0.85 (min 0.77,
  floor 0.70) · path tile share 0.78–0.80 (min 0.69, floor 0.50) · flat share 0.01–0.03 (max 0.21,
  cap 0.35) · ramp share 0.01–0.02 (max 0.08, cap 0.10) · elevation sd 9.7 → 13.7 HU (min 3.18 at L1,
  floor 3) · junction step share 99.8–99.9% (min 75%, floor 50%) · platforms 4.1 → 11.5 per level ·
  walkways 21.8 → 61.8 per level.
- Level-1 variety (J1): 200 level-1 seeds → 200 unique layouts (tile set + gift slots), 192 unique
  recipes. The app now draws a fresh run seed per run; start_run(seed) still reproduces exactly.
- Tripmines (D-026): every mine sits on a slot with a walkable bypass and the joint rule holds on every
  level (H23 0/5000). A bypass must stay outside the mine's 0.9 u trigger cylinder, so the bypass graph
  drops the mine tile **and every other tile in its column** plus every walk/jump/drop/pad edge whose
  segment passes within 0.9 u of a mine centre. Modelling assumption: the player's centre runs along
  tile-centre segments, so an edge lane of a 3-wide walkway (the mine sits on the centre lane) keeps
  1.0 u — a **0.1 u margin** (flagged [CONTESTABLE] in D-026; a 1.4 u radius would remove mines).
  **GEN_VERSION 4:** nearly every slot is now eligible (every centre-lane slot on a 3-wide path has a
  bypass), so mines per level rose toward the unchanged canon curve: measured over 1,500 seeds,
  L1–5 0.56 → 0.64, L6–10 3.54 → 3.92, L11–15 5.38 → 6.10, L16–20 7.76 → 9.11, L21–25 10.47 → 12.16,
  L26–30 12.53 → 14.68 per level (8.46% → 9.92% of slots). The GEN_VERSION 3 figures that follow are
  kept as history.
- GEN_VERSION 3 history:
  Mines per level 0.52 (L1–5) → 12.61 (L26–30); as a share of all slots 1.09% → 8.52%, because
  6.3% of slots are ineligible at level 5 and 13.6% at levels 26–30. Count band, GEN_VERSION 2 → 3 (mean/min/max per level):
  1–5 0.55/0/8 → 0.52/0/8 · 6–10 3.93/0/13 → 3.51/0/10 · 11–15 6.10/0/14 → 5.36/0/14 ·
  16–20 9.09/2/19 → 7.71/1/16 · 21–25 12.12/3/26 → 10.34/2/21 · 26–30 15.06/3/31 → 12.61/2/27.
- GDScript port: DONE for GEN_VERSION 4. `PARITY 56/56 OK`, gallery pins 16/16, 343 ms per level
  (Godot 4.7.2 headless, measured on a shared machine; it was 142 ms at GEN_VERSION 3).
<!-- STATUS-END -->

**History — GEN_VERSION 3.** The table below was measured on the official harness (5,000 seeds,
levels 1–30) at GEN_VERSION 3 and is kept as the record of that version. The GEN_VERSION 4 numbers
are in the STATUS block above; GEN_VERSION 4 re-measured every hard and distribution check.

| what | measured | limit |
|---|---|---|
| generation time, Python | 0.018 s (L1–5) … 0.084 s (L26–30) mean, 0.191 s worst | mean ≤ 0.25 s |
| first gift from the beacon (H10) | ≤ 15 cells worst case | ≤ 30 |
| starvation p95 (H11) | 8.9 cells mean, 19 worst | ≤ 27 |
| starvation max (H11) | 11.0 mean, 23 worst | ≤ 54 |
| playable area (H9) | 100.0% | ≥ 98% |
| fair reach (H13) | 0 failing slots in 5,000 levels | 0 |
| jump share J at level 1 (D8) | mean 10.4%, max 75.0% | mean ≤ 50, max ≤ 80 |
| J by level | L1 26 · L6 74 · L11 90 · L16 92 · L21 94 · L26 94 | rising |
| difficulty score D by bucket (D7) | 80.5 · 151.6 · 183.6 · 195.5 · 209.2 · 215.6 | strictly increasing |
| within-level platform repetition (D6) | 1.79% mean | ≤ 10% |
| identical recipes (D5) | 0 of 5,000 same-level pairs | ≤ 0.1% |
| footprint similarity, 4-cell blocks, spawn-anchored (D4) | p99 0.394, 0 pairs ≥ 0.60 | p99 ≤ 0.50; ≥ 0.60 in ≤ 0.1% |
| re-roll rate (attempt > 0) | 44% at L1, 43% at L5, 47% at L30; max attempt seen 12 | attempt ≤ 12 |
| shortcuts per level | 1.5 (L1–5) · 1.9 (L6–10) · 3.6 (L26–30) | ≥ 1 |
| mine rate vs curve (D1), 5,000 seeds | max deviation 0.58 pp over eligible slots | ≤ 1.0 pp |
| `extra_mines = 999` (D2) | 300/300 exactly at `min(S // 5, eligible)` | all |
| mines per level | 0.52 (L1–5) → 12.61 (L26–30); 1.09% → 8.52% of all slots | ≤ S // 5 |
| eligible slots | 93.7% (L1–5) → 86.6% (L26–30) of all slots | — |
| path share of walkable length (H19) | 0.85 mean, 0.78 worst | ≥ 0.70 |
| walkway tiles / non-hub walkable tiles (H19) | 0.67–0.75 mean, 0.51 worst | ≥ 0.50 |
| flat share of path rows (H20) | 0.02–0.03 mean, 0.18 worst | ≤ 0.35 |
| ramp share of path rows (H20) | 0.01–0.02 mean, 0.09 worst | ≤ 0.10 |
| elevation sd over non-hub tiles (H21) | 9.9 (L1–5) → 13.9 (L26–30) HU, 3.01 worst | ≥ 3 at L1 → ≥ 6 at L10 |
| sub-area boundaries with \|Δy\| ≥ 1 (H22) | 99.0–99.7% mean, 71.4% worst | ≥ 50% |
| platforms per level (H18) | 4.1 (L1–5) → 11.5 (L26–30) | 3 … min(12, 4 + level // 3) |
| walkways per level | 21.8 (L1–5) → 63.5 (L26–30) | — |

Checks that failed on first measurement were fixed IN THE GENERATOR (D-018, D-019, D-020, D-025, D-026);
two metric definitions were corrected with their reasoning and numbers on record (D-022, D-026). No
threshold was moved after measurement (D-030).

## 4. Pinned gallery (GEN_VERSION 4) — `terrain_ref/gallery.json` is authoritative

| # | seed | level | attempt | platforms | tiles | slots | mines | bridges | drops | pads | dead ends | arms | hash (first 12) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 1 | 0 | 4 | 720 | 40 | 0 | 1 | 0 | 0 | 2 | ascent, maze | `d631717c7ae4` |
| 2 | 2 | 1 | 1 | 4 | 841 | 40 | 0 | 1 | 0 | 0 | 3 | maze, ascent, descent | `887ce0e207ce` |
| 3 | 3 | 1 | 3 | 4 | 752 | 40 | 0 | 0 | 2 | 0 | 3 | maze, ascent, ascent | `687604848abb` |
| 4 | 1001 | 2 | 9 | 4 | 762 | 44 | 0 | 0 | 1 | 1 | 3 | thin, descent, grand | `0c43fbfb4ddd` |
| 5 | 1002 | 3 | 4 | 5 | 887 | 48 | 0 | 1 | 1 | 0 | 3 | descent, thin | `2d490d662082` |
| 6 | 1003 | 4 | 2 | 4 | 643 | 52 | 0 | 0 | 1 | 0 | 4 | ascent, maze, thin, ascent | `c491339b8d33` |
| 7 | 1004 | 5 | 0 | 5 | 944 | 56 | 3 | 2 | 0 | 0 | 4 | thin, grand, hop, descent | `95515bc3d709` |
| 8 | 1005 | 8 | 0 | 5 | 849 | 68 | 4 | 1 | 0 | 0 | 3 | maze, grand, descent | `0a782a3e6b0d` |
| 9 | 1006 | 10 | 0 | 7 | 933 | 76 | 7 | 1 | 0 | 0 | 3 | hop, ascent | `1f1b21d9259a` |
| 10 | 1007 | 12 | 0 | 7 | 1069 | 84 | 7 | 1 | 3 | 0 | 4 | ascent, hop, thin, hop | `e8d9d9c52a2f` |
| 11 | 7 | 12 | 2 | 8 | 1167 | 84 | 3 | 1 | 0 | 0 | 6 | maze, thin, grand, hop | `1463bc45c1e5` |
| 12 | 1008 | 16 | 0 | 9 | 1376 | 100 | 9 | 0 | 1 | 0 | 4 | ascent, ascent, maze, grand | `a0fca152303f` |
| 13 | 1009 | 20 | 2 | 10 | 1242 | 116 | 8 | 1 | 0 | 0 | 5 | hop, descent | `9910d240f73a` |
| 14 | 1010 | 25 | 0 | 11 | 1752 | 136 | 21 | 3 | 2 | 0 | 5 | descent, maze, hop, grand | `838ee9b5e7d7` |
| 15 | 7 | 30 | 2 | 12 | 1610 | 156 | 16 | 3 | 1 | 0 | 6 | grand, thin, hop, ascent | `de796dcf1a35` |
| 16 | 1011 | 40 | 0 | 12 | 1770 | 160 | 21 | 0 | 1 | 0 | 3 | maze, thin, grand | `6deee4baa4ea` |
| 13 | 1009 | 20 | 0 | 9 | 805 | 116 | 8 | 3 | 3 | 0 | 5 | grand, maze, thin | `e8b7f8208812` |
| 14 | 1010 | 25 | 0 | 11 | 823 | 136 | 11 | 3 | 1 | 0 | 4 | descent, maze, descent, thin | `f95f7250554b` |
| 15 | 7 | 30 | 0 | 11 | 807 | 156 | 17 | 0 | 1 | 0 | 5 | grand, maze, maze, ascent | `2c67cc08155e` |
| 16 | 1011 | 40 | 4 | 11 | 868 | 160 | 4 | 4 | 0 | 0 | 6 | ascent, grand, hop, hop | `94df9d3c5ff9` |

Reading the table as a regression check without eyes: slots follow `40 + 4*(level-1)` capped at 160;
mines are 0 below level 5 and never above `slots // 5`; every entry has at least one bridge or drop;
platforms grow with level and never exceed `min(12, 4 + level // 3)`; the arms column is the sorted
trait list. The gallery pairs draw only a handful of distinct trait pairs, which is why D5 counts the
walkway-archetype multiset as well as the platform one. Since GEN_VERSION 3 a mine also needs a
walkable bypass (TERRAIN_SPEC §6.8, H23). At GEN_VERSION 3 that made the mine column a lower fraction
of the slots than the raw per-slot chance suggested (4.7% of all slots at L5 rising to 8.7% at L30,
D-026); at GEN_VERSION 4 nearly every slot is eligible, so the mine column follows the per-slot chance
closely (STATUS block).

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

Hit during the GEN_VERSION 3 port (tripmine bypass, D-026) — result: PARITY 56/56, 142 ms per level:
- The mine context is a **Dictionary**, not an inner class. An inner class cannot call the outer script's static helpers (`find_tile`, `rdiv`) by bare name, and a global `class_name` does not resolve in headless `--script` mode. Keep `mine_ctx` / `mine_cross_edges` / `mine_block` / `mine_keeps_rt` / `mine_eligible` / `mine_joint_ok` as static functions taking the context Dictionary.
- `ctx["cross"]` and `ctx["elig"]` are caches. Dictionaries are reference types, so `cache[si] = out` mutates the context in place — do not reassign the local and expect the cache to persist.
- `cache.get(si)` returns `null` when the key is absent, but a cached `false` is **not** `null`. Test `!= null`, never truthiness, or every ineligible slot is recomputed on every call.
- `rdiv(a, 0)` is a division by zero: a non-walk edge with `dx = dz = 0` (a same-column pad) has `steps = 0`. Both ports use `den = 2 * steps if steps > 0 else 1`; the sampling loop then runs once and indexes the single cell. Output-neutral (no such edge occurs in 5,000 levels) but the GDScript would crash.
- `mines + [i]` concatenates Arrays; `mines.pop_back()` returns the last element. The cap un-set needs ascending order, which only the roll phase guarantees — the `extra_mines` loop appends out of order, so the safety net uses `max(mines)` instead.
- The joint test runs once per roll-passing slot, so the context must be built **lazily** (`have_ctx`): building it for levels 1–4, where no mine can exist, would pay for the whole cell index for nothing.
- `blocked` is an Array of bools (Python uses a `bytearray`); `blk` is a Dictionary of Dictionaries and the edge test is `not b.has(j)`, not `j not in b`.
- The trigger cylinder blocks **every tile in the mine's column**, not just the mine tile. `ctx["col"]` maps a packed `(x, z)` to the tile indices on that cell, and `mine_block` scans the 3×3 cell neighbourhood with `dx*dx + dz*dz <= 81` in ×10 coordinates. Blocking only the mine tile is the bug that lets a mine sit under a gift on the tile above it.
- The edge index must hold **all** edges, walk included (`ctx["edges"]`, which replaced the old non-walk-only `ctx["nw"]`). A walk edge between 4-adjacent centres is 1.0 u long, so the 0.9 u test never removes one in practice — but it is computed, never assumed, and the validator computes it too.
- `mine_keeps_rt` has a guard the pure reachability test does not: it returns `false` when the cylinder holds the beacon or another slot tile (a gift inside the cylinder is uncollectable), and `need` counts only the round-trip tiles that are **not** blocked. Both ports must keep the guard and the `need` count, or a mine can swallow a gift and still pass.

Hit during the GEN_VERSION 4 port (J1: width 3, centre-lane gifts) — result: PARITY 56/56 first time, 343 ms per level:
- The walkway lane anchor indexes the CENTRE of the middle row: `cells[(n / 2) * offs_for(w).size() + offs_for(w).size() / 2]`. With width 3 the first cell of a row is lateral −1, an edge lane; the old index (`... * size()` alone) only happened to be the centre at width 2.
- The turn socket reads its height from row n−2's first cell, `cells[(n - 2) * WALK_W][2]`; rows are uniform in height so any cell of the row works, but both ports must pick the same one.
- `try_loop` no longer reads the socket's `wmax` (every bridge and ledge is 3 wide): drop the local in GDScript too, or the unused-variable warning trips the project's warnings-as-errors setting.
- `centre_lane` calls `has_prop` per neighbour column: keep it a static function taking `W`, like `has_prop`, so the inner `World` class is not needed.
<!-- PORT-PITFALLS-END -->

Change procedure for ANY generator edit (binding): edit `voidgen.py` → `validate.py --seeds 0:5000`
green → bump `GEN_VERSION` → `gallery.py --write` → update TERRAIN_SPEC → port the same edit to
`voidgen.gd` → parity green → `make_parity_cases.py` re-run. Never edit the GDScript first.

## 6. Extending the terrain (drop-in points inside the generator)

| to add | where | cost |
|---|---|---|
| a platform archetype | a `plat_<name>(rng, t, gentle)` function + `_plat` dispatch + `PLATS` + a `plat_w` weight (+ trait multipliers). Contract: return `(tiles, socks, props, anchors)`; bbox ≤ 7×7 and ≤ 40 tiles (H18); every tile inside a full 3×3 square of the piece (H24); sockets on extreme tiles, centred on a face at least 3 cells wide (never a corner) with max link width `WALK_W`; every internal height step ≤ AUTH envelope both ways or optional (like the spire overlook); props only via `scatter` or on perimeter tiles | GEN_VERSION bump |
| a walkway archetype | a branch in `build_walkway` + `WALKS` + `walk_w` + trait multipliers. Contract: exactly 3 wide, lateral offsets −1/0/+1 (H17), straight, two-way inside the AUTH envelope, and it must change height by a step at each end (H22) | GEN_VERSION bump |
| an arm trait | `TRAITS` + the three trait tables (`TRAIT_LINK`, `TRAIT_ROOM`, `TRAIT_UP_PCT`) | GEN_VERSION bump |
| a slot-replacing hazard | a new `occ` value rolled in `roll_mines` (rename to `roll_hazards`) under the SAME 20% total cap. A hazard that kills on contact must also pass the bypass rule (§6.8, H23) — reuse `MineCtx` / `MineJudge` rather than inventing a second graph | GEN_VERSION bump; H5 and H23 extended |
| a terrain-affecting modifier | new trailing int parameter of `generate` with default 0 that reproduces today's hash | goldens unchanged when 0 |
| a new anchor kind | new `AN_*` constant emitted by archetypes. Id 3 is retired and reserved (D-026) — take the next free id, never 3 | GEN_VERSION bump |
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
