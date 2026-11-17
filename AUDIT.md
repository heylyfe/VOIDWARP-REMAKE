# AUDIT.md — T-099, the final conformance audit before alpha

Auditor: implementation sub-agent, zero prior context, own checkout.
Branch: `t3/69dd5808`. Commit audited: `8fb49d3` ("Merge T-ART address_me: real sprite art and per-state frames").
Date of run: 2026-11-17. Machine: AMD Ryzen 5 9600X 6-Core, AMD Radeon RX 9060 XT, Windows, Godot 4.7.2-stable.

**This file is the only thing the audit wrote.** No code, test, document, threshold or data file was
edited. Every defect found is written here and left in place.

---

## 0. Method and two document defects worked around

Every command of FLEET_PACK.md §4 was run on this checkout. Long output was redirected to a file under
`out/` (gitignored) and grepped; nothing was piped through `tail` in PowerShell.

**Defect D1 — FLEET_PACK.md §4's bot command has stale flags.** §4 says
`bot_run.gd -- --seed 1 --levels 1 --class dasher`. `game/tools/bot_run.gd` accepts
`--dodge`, `--runs N`, `--seed-base S`, `--max-level N` (its own header, lines 8-16). The stale flags are
**not rejected** — they are silently ignored and the tool falls back to its defaults, so the literal §4
command starts a **200-run, level-18 sweep** instead of one level-1 run. I stopped it after 180 s. The
working form used below is
`-- --runs 1 --seed-base 1 --max-level 1`.

**Defect D2 — the export fails on a clean checkout.** `build/` is in `.gitignore`, so
`--export-release "Windows Desktop" ../build/voidwrap_run.exe` has no target directory. `mkdir -p build`
first, then the export succeeds.

**Defect D3 — RUNLOG.md does not exist in this checkout.** The brief says the two §4 defects are
"already recorded in RUNLOG.md". `find . -name 'RUNLOG*'` returns nothing, and FLEET_PACK.md §10.3
instructs workers to "Write the findings in RUNLOG.md". The file was never created. Recorded here
because the audit is the last place it can be recorded.

**Defect D4 — the owner's VOIDWRAP_CANON list is not in the repository.** The brief says "The canon list
is in FLEET_PACK.md (search 'VOIDWRAP_CANON')". `grep -rn VOIDWRAP_CANON` returns exactly two hits, both
of them *references* to the list, never the list itself: `DESIGN.md:3` ("Canon sources, in priority
order: the owner's brief (VOIDWRAP_CANON + constraints) → …") and `FLEET_PACK.md:352` (T-099's own Do
line). The canon bullets are therefore audited against the repo's own canonical record of them —
DESIGN.md's `[CANON]` markers — in §3 below. That is a proxy, and it is stated as one.

---

## 1. Every §4 command, its real final line, its real exit code

| # | command (as run) | real final line | exit |
|---|---|---|---|
| 1 | `godot --headless --path game --script res://tests/run_all.gd` | `TESTS 55 passed 0 failed` | 0 |
| 2 | `godot --headless --path game --script res://tests/test_terrain_parity.gd -- <abs>/terrain_ref/gallery.json` | `PARITY 56/56 OK` | 0 |
| 3 | `python terrain_ref/test_validate.py` | `SELFTEST 15/15` then `TESTS OK` | 0 |
| 4 | `python terrain_ref/gallery.py --check` | `GALLERY 16/16 OK` | 0 |
| 5 | `python terrain_ref/validate.py --selftest` | `SELFTEST 15/15` | 0 |
| 6 | `python terrain_ref/validate.py --seeds 0:5000` | `total wall time 255.7 s` (32 PASS / 0 FAIL above it) | 0 |
| 7 | `godot --headless --path game --script res://tools/bot_run.gd -- --runs 1 --seed-base 1 --max-level 1` | `BOT_RUN OK (1 runs, deterministic seed set seed_base=1..1)` | 0 |
| 8 | `mkdir -p build` then `godot --headless --path game --export-release "Windows Desktop" ../build/voidwrap_run.exe` | `[ DONE ] savepack` | 0 |
| 9 | `powershell -File tools/gate.ps1` | `GATE OK (9 ran, 0 skipped, 336 s)` | 0 |

Notes on the numbers, because they differ from the orchestrator's report:

- **The 5,000-seed harness: 32 PASS / 0 FAIL, 255.7 s.** `grep -c '^PASS '` = 32, `grep -c '^FAIL '` = 0.
  Every H check reports `failures=0/5000`; every D check reports PASS with its limit. The orchestrator
  reported 234.9 s; this run took 255.7 s. Same verdict, different wall time.
- **The gate: GATE OK, 336 s, not 138 s.** The difference is the cold `--import` step on a fresh
  checkout (FLEET_PACK §4's "≤ 120 s warm" target is a warm-cache target; this checkout had no
  `.godot/`). The gate also printed `WARN resource import did not finish cleanly; continuing` before
  step 3 — the import step is non-fatal by design, and every downstream step still passed.
- **`run_all` prints `TESTS 55 passed 0 failed`** and the gate repeats it. Godot also prints
  `WARNING: 45 ObjectDB instances were leaked at exit` and `ERROR: 9 resources still in use at exit`
  on shutdown. Those are engine teardown diagnostics, not test failures; the exit code is 0.
- **The export produces `build/voidwrap_run.exe`, 118,145,528 bytes (112.7 MiB)**, self-contained.

### 1.1 A1's smoke run — the literal measurement is not achievable, and neither is the substitute

A1's "measured by" column says: *"T-056 smoke run: process alive 10 s, exit code 0 on `--quit-after 600`"*.
The frame rate is uncapped on this hardware, so `--quit-after 600` does not last 10 s. Measured wall
clock, warm cache, two runs each:

| `--quit-after` | run 1 | run 2 | exit |
|---|---|---|---|
| 600 | 927 ms | 906 ms | 0 |
| 6000 | 2384 ms | 2537 ms | 0 |
| 12000 | 4554 ms | 4407 ms | 0 |
| 60000 | 15974 ms | — | 0 |

That is ~0.27 ms per frame, i.e. roughly **3,700 fps**. The brief's suggested substitute
("`--quit-after 6000` stays alive ~10.3 s") **does not reproduce here**: 6000 frames is 2.4 s, not
10.3 s. The honest evidence for A1 is therefore:

- `--quit-after 600` → exit 0, 0.92 s wall.
- `--quit-after 6000` → exit 0, 2.45 s wall.
- `--quit-after 12000` → exit 0, 4.41 s wall.
- `--quit-after 60000` → exit 0, **15.97 s wall** — the only setting that keeps the process alive past
  the 10 s check.

**Limitation, stated plainly:** A1's literal "process alive 10 s on `--quit-after 600`" is unachievable
on this machine and no run of it was faked. The 10 s liveness claim is evidenced by `--quit-after 60000`
(15.97 s alive, exit 0) instead.

**"Starts to the menu" is visually verified**, not inferred. The exported exe was launched with
`--quit-after 60000` and the primary screen captured 6 s in (`out/exe_menu.png`): a window titled
"VOIDWRAP RUN" showing the title, the tagline "collect every black gift. mind the void.", and the four
entries **Play / Settings / About / Quit**. The exe's stdout is the clean Vulkan init line
(`Vulkan 1.4.359 - Forward+ - Using Device #0: AMD - AMD Radeon RX 9060 XT`) with no script errors.

---

## 2. A1 to A16, one by one

Verdicts: **PASS** = the criterion's own number is met and a test proves it. **PARTIAL** = the
behaviour exists and is tested, but the criterion's stated number, scope or proof is not met.
**FAIL** = the criterion's number is not met.

### A1 — native export, starts to the menu — **PASS** (with a stated measurement limitation)

- Command: `mkdir -p build` then `godot --headless --path game --export-release "Windows Desktop" ../build/voidwrap_run.exe` → `[ DONE ] savepack`, exit **0**.
- Artifact: `build/voidwrap_run.exe`, **118,145,528 bytes**. Native Godot export (Vulkan 1.4.359, Forward+), no browser or Electron wrapper.
- Smoke: `--quit-after 600` → exit **0**; `--quit-after 6000` → exit **0**; `--quit-after 12000` → exit **0**; `--quit-after 60000` → exit **0**, **15.97 s alive**.
- Menu: visually confirmed from `out/exe_menu.png` — title, tagline, **Play / Settings / About / Quit**.
- **Limitation:** A1's literal "process alive 10 s on `--quit-after 600`" is unachievable here (~3,700 fps; 600 frames = 0.92 s). The brief's substitute (6000 → ~10.3 s) also does not reproduce (2.45 s). The 10 s liveness claim rests on `--quit-after 60000`. Nothing was faked.
- Proof: `game/export_presets.cfg`, `game/app/main.tscn` (`run/main_scene`), `game/app/menu.gd`.

### A2 — terrain: 5,000-seed harness + GDScript parity — **PASS**

- `python terrain_ref/validate.py --seeds 0:5000` → **32 PASS / 0 FAIL**, `total wall time 255.7 s`, exit **0**. Every H check `failures=0/5000`; every D check PASS with its limit (D1 max dev 0.00576 ≤ 0.01000; D2 300/300; D3 5000; D4 0.3935 ≤ 0.5; D5 0; D6 0.0179 ≤ 0.1; D7 strictly increasing; D8 10.374 ≤ 50 and 75.0 ≤ 80; D9 112.5 ≤ 250 and 1139.5 ≤ 2000).
- `godot --headless --path game --script res://tests/test_terrain_parity.gd -- <abs>/terrain_ref/gallery.json` → `GALLERY_PIN 16/16` and `PARITY 56/56 OK`, exit **0**. 56 = the 16 pinned gallery records + the 40 parity cases, so A2's "16/16 + 40/40" is met.
- Proof: `terrain_ref/validate.py`, `game/tests/test_terrain_parity.gd`.

### A3 — the bot completes level 1 in ≥ 95 of 100 seeds, median ≤ 120 s — **FAIL**

- Command (A3's literal command does not exist — see D1): `godot --headless --path game --script res://tools/bot_run.gd -- --dodge --runs 10 --seed-base 0 --max-level 2`, exit 0, 181 s.
- Pasted evidence, all ten runs:

```
run 0 seed=0 class=dasher   entered=1 outcome=dead tick=1728 killer=void     code=D-VOID
run 1 seed=1 class=dasher   entered=1 outcome=dead tick=1554 killer=kiwi cat code=D-KIWI
run 2 seed=2 class=athletic entered=2 outcome=dead tick=1284 killer=void     code=D-VOID
run 3 seed=3 class=athletic entered=1 outcome=dead tick=2548 killer=coil     code=D-COIL
run 4 seed=4 class=glider   entered=1 outcome=dead tick=2048 killer=void     code=D-VOID
run 5 seed=5 class=glider   entered=1 outcome=dead tick=2326 killer=void     code=D-VOID
run 6 seed=6 class=glider   entered=1 outcome=dead tick=1849 killer=void     code=D-VOID
run 7 seed=7 class=dasher   entered=1 outcome=dead tick=2307 killer=void     code=D-VOID
run 8 seed=8 class=athletic entered=1 outcome=dead tick=1034 killer=void     code=D-VOID
run 9 seed=9 class=glider   entered=1 outcome=dead tick=1216 killer=void     code=D-VOID
```

- **1 of 10 seeds completed level 1** (`entered=2`, seed 2). The other nine died on level 1. That is **10%**, against a required **95%**. 8 of the 9 deaths are `D-VOID` (a void fall at 0 charges).
- A 30-seed extension (`--runs 30 --seed-base 10 --max-level 2`) was started and had **not finished after 35 minutes** — the bot hits its 7,199-tick cap on many seeds, which is itself consistent with the failure. It is not needed to decide the criterion.
- This is **already parked**: PARKED.md #4 (T-026) records `BOT-RUNS completed=0 failed=4` and states A3 is not met. The audit confirms the park is honest and the criterion still fails.
- Proof: `game/tools/bot_run.gd`, `game/tests/test_bot_run.gd`.

### A4 — replay determinism: 10 recorded bot runs, identical hashes at every checkpoint — **PARTIAL**

- `test_replay.gd` runs inside `run_all` (`TESTS 55 passed 0 failed`). It records **one** 3,600-tick run with a deterministic bot-input generator, replays it twice from a fresh `RunState`, and compares the state hash at **every 60th tick (60 checkpoints)**; it then perturbs one input at tick 1200 and asserts every checkpoint from there on differs.
- **The criterion says 10 recorded bot runs. The test does 1.** Determinism is proven strongly (60 checkpoints plus a must-diverge perturbation), but not on the number of runs the criterion names.
- Proof: `game/tests/test_replay.gd` (`TICKS := 3600`, `CHECK_EVERY := 60`, `PERTURB_AT := 1200`).

### A5 — black→gold at the same slot ids/positions on 100 seeds; beacon CLOSED→OPEN exactly then — **PASS**

- `test_gifts.gd` has `const SEED_COUNT := 100` and `_test_a5_100_seeds(f)`; it also asserts the beacon entry restores exactly 1 charge (0→1, 1→2, 2→2), the straggler rule marks only real gifts (`occ == 0`) and only the last 20%, and a slot-position confinement scan.
- Proof: `game/tests/test_gifts.gd`, `game/sim/gifts.gd`, `game/sim/beacon.gd`.

### A6 — tripmines: occ-only occupancy, 0.9 u any-height contact, the fixed four-step ladder, deterministic roll, ±2 points at 1/2/3 stacks — **PASS**

- `test_mines.gd` asserts: the mine set is exactly the `occ == 1` slots; contact is the player's centre within 0.9 u horizontal at any height; the ladder order defuse → Subspacial Barrier → Last Light → death with `D-MINE`; determinism over **1,000 seeds** (`for seed in range(1000)`, prints `MINE determinism: 1000 seeds, same seed -> same outcome`); the defuse rate at 1/2/3 stacks within **±0.02** of 20/40/60% over 300 seeds × 10 slots = 3,000 samples per stack, plus the 60% cap at 4 stacks.
- Kill tests run with Last Light already spent (D-057), as the criterion requires.
- Proof: `game/tests/test_mines.gd`, `game/sim/mines.gd`.

### A7 — all 12 enemies: timings within ±1 tick, contact kills except thicc ben and the three non-killing effects, Last Light spent, sprites.json with body_rect, hitbox padding test — **PASS**

- Twelve per-enemy tests exist and run: `test_enemy_kiwi_cat, coil, thicc_ben, isagi, nuke, you, gift_larper, toucher, seal, address_me, claude, gin`. Each header pins its DESIGN §5 numbers "within ±1 tick" and each states "KILL TESTS RUN WITH LAST LIGHT ALREADY SPENT (D-057)".
- `test_hitbox.gd` proves a probe inside the PNG rect but outside `body_rect` never hits, using ENEMIES.md's own 512×512 / 300×400 example.
- `contact_kill` per `enemy.json`: true for `claude, gin, isagi, kiwi_cat, seal, toucher, you`; false for `address_me, gift_larper, nuke, thicc_ben`; `coil` kills by landing (`landing_kill_radius_u: 1.2`), not by contact.
- **Note on the criterion's wording:** "every body contact kills except thicc ben" is not literally true — `address_me` also has no contact kill, because DESIGN §5.2 / D-065 (FINAL) gives it "no body contact; it is a countdown, not an obstacle". That is the spec's own text, and PARKED.md #10 records the ticket-vs-FINAL clash. The build follows the FINAL. Not a defect; recorded so the wording is not mistaken for a miss.
- Proof: the twelve `game/tests/test_enemy_*.gd`, `game/tests/test_hitbox.gd`, `game/content/enemies/*/enemy.json`.

### A8 — sprite validator: alpha 0 in all four corners, no opaque 1-px border, fog contrast ≥ 3.0 at 40 u — **PASS**

- Gate step 8: `SPRITES OK 515 checks over 12 sprites.json`, exit 0.
- `validate_sprites.gd` checks exactly the criterion's clauses plus two more: four corners alpha 0; no edge pixel with alpha ≥ 16; ≥ 15% fully transparent; **fog contrast ≥ 3.0 at 40 u** (`FOG_CONTRAST := 3.0`, `FOG_DIST := 40.0`, `FOG_DENSITY := 0.012`); and per-frame `body_rect` equals the tight bbox of alpha > 16.
- Proof: `game/tools/validate_sprites.gd`.

### A9 — lobby: physical scene, F-hold 0.35 s altars, schedule from data/offering_schedule.json, mandatory bays gate the Descent Gate — **PASS**

- `test_lobby.gd` drives inputs: "nothing under 0.35 s, exactly one Select at the hold" (`for _i in 3: # 3 x 0.1 s = 0.30 s < 0.35 s`), the schedule read from `data/offering_schedule.json`, and the mandatory-bay gate.
- Proof: `game/tests/test_lobby.gd`, `game/view/lobby/antechamber.gd`, `game/sim/intermission.gd`.

### A10 — 46 curses, 36 upgrades, 12 enemies, 5 biomes load and pass schema; level-1 shop pool is exactly Paycheck, More, Yearn for Speed — **PASS**

- `test_content.gd`: `var counts := {"curses": 46, "upgrades": 36, "biomes": 5, "enemies": 12}` and the level-1 pool assertion `ids == ["paycheck", "more", "yearn_for_speed"]`.
- Independent count on disk: `ls game/content/curses/*.json` = 46, `upgrades/*.json` = 36, `biomes/*.json` = 5, `enemies/` = 12 folders.
- Gate step 5: `OK content schema (ran in run_all: game/tests/test_content.gd)`.
- Proof: `game/tests/test_content.gd`, `game/core/schemas/*.json`.

### A11 — economy audit: >= 1 item affordable in >= 80% of shops, all 3 in <= 30%, 1,000 runs to level 30 — **PASS**

- `godot --headless --path game --script res://tools/economy_audit.gd` -> `AUDIT OK (runs=1000 shops/run=15 afford1=99.5% afford3=29.3% purchases=23.89 cautious=8.25)`, exit **0**.
- afford1 99.5% >= 80% PASS; afford3 29.3% <= 30% PASS (margin 0.7 points — tight, but inside); purchases 23.89 in 18-24 PASS; cautious 8.25 in 6-10 PASS.
- Proof: `game/tools/economy_audit.gd`.

### A12 — feel budget: loading >= 5.0 s and <= 8 s, gate->level <= 2.0 s, death->run-over <= 2.0 s, void fall->respawn <= 0.8 s, generate+mesh L30 <= 1.5 s — **PASS**

- `godot --headless --path game --script res://tools/feel_probe.gd` -> `T-061 RESULT: OK`, exit **0**:

```
PASS loading_screen_hold 5.050 s >= 5.0 s
PASS loading_screen_total_l30 5.050 s <= 8.0 s (hold 5.0 + build 0.160 s)
PASS gate_to_level 0.160 s <= 2.0 s (gen+world+mesh+sim state, level 30)
PASS death_to_run_over 0.0044 s <= 2.0 s (kill tick -> screen_data + run-over build; kiwi cat)
PASS void_fall_to_respawn 0.800 s <= 0.80 s (void_fall -> respawn; landed on 1,1,1)
PASS generate_mesh_l30 0.159 s <= 1.5 s (voidgen + level_mesher, seed 7)
```

- `void_fall_to_respawn` is **exactly at the bound** (0.800 vs 0.80). It passes, but with zero margin.
- Proof: `game/tools/feel_probe.gd`, `game/app/loading_screen.gd`.

### A13 — performance: level 30, 22 enemies, 600 frames, p99 <= 16.6 ms windowed 1080p, mean sim tick <= 2.0 ms — **PASS**

- `godot --path game --script res://tools/perf_probe.gd` (a real window, not headless), exit **0**:

```
MACHINE[OS] Windows
MACHINE[CPU] AMD Ryzen 5 9600X 6-Core Processor
MACHINE[GPU] AMD Radeon RX 9060 XT (vendor AMD)
PASS p99_frame_time 1.47 ms <= 16.6 ms (windowed 1080p, v-sync off; n=600)
PASS mean_sim_tick 0.779 ms <= 2.0 ms (ctl+enemy runtime step; 22 enemy rows)
T-061 RESULT: OK
```

- Proof: `game/tools/perf_probe.gd`.

### A14 — drop-in proof: fixture enemy/curse/upgrade/biome copied into content/ are offered and work with zero core edits; boundary scan clean — **PARTIAL**

- Gate step 6: `OK drop-in fixture (ran in run_all: game/tests/test_dropin.gd)`. `test_dropin.gd` copies one enemy, one curse, one upgrade and one biome into `content/`, re-boots, asserts all four register and are functional, corrupts one file and asserts the boot refuses with the file named, then removes everything.
- **The "boundary scan clean" half does not hold.** The scan is green only because `KNOWN_CONTENT_IDS` is empty and it reads only `.gd` files; `game/core/schemas/curse.schema.json` hardcodes all 12 enemy ids, and `game/sim/death.gd` hardcodes the 12 roster display names. A 13th enemy therefore needs a core edit to `death.gd` (and to the curse schema if any curse requires it). See section 5.
- Proof: `game/tests/test_dropin.gd`, `game/tests/test_boundaries.gd`.

### A15 — README and the lobby About plaque contain the disclaimer verbatim — **PARTIAL**

- README: **verbatim**, em dash included, and `test_disclaimer.gd` asserts it.
- Lobby About plaque (`game/view/lobby/antechamber.gd:63`): present, but **one character differs** — ASCII hyphen `-` at index 51 where the spec has em dash. **No test reads `antechamber.gd`**, so A15's stated proof does not cover the plaque at all.
- Full detail in section 6.
- Proof: `game/tests/test_disclaimer.gd`, `README.md`, `game/app/menu.gd`, `game/view/lobby/antechamber.gd`.

### A16 — TBD.md lists every TBD substitution; 0 tickets stalled on a refusal — **PASS** (with two documentation defects)

- `TBD.md` has 8 sections and 49 numbered rows covering: the 17 enemy source images (section 1), placeholder audio hooks (section 2), and the synthesized audio stand-ins (rows 36-49). The one live `"tbd": true` is `claude` (the clawd Crab plushie, row 15 / row 26) — a documented TBD, not a failure.
- **0 tickets stalled on a refusal.** Every ticket in `tickets/` has a response file; the refusals that did occur were handled by the TBD FALLBACK rule (name kept, placeholder wired, row written).
- **Two documentation defects in TBD.md, reported not fixed:**
  1. Section 1's heading reads `## 1. The 17 enemy images - 4 MISSING (coil, thicc ben, kiwi cat, isagi, YOU?!, toucher, gin, gift Larper, seal, the Claude logo and address me are real art since 2026-11-17; only the clawd Crab plushie and the four remaining source rows are still TBD)`. "4 MISSING" contradicts the eleven names it then lists as real art, and contradicts its own table, where all 17 rows are PRESENT/REAL except the plushie.
  2. The section 1 body text still says "the other fourteen remain MISSING -> TBD" and "Isagi's rows below say REAL ART; the other fourteen remain MISSING -> TBD", which the table below it contradicts. The heading and body were not updated when the art wave landed.
- Proof: `TBD.md`, `game/content/enemies/*/sprites.json`.

---

## 3. The canon table

**The owner's VOIDWRAP_CANON list is not in this repository** (defect D4 above). The rows below are the
repo's own canonical record of it: every `[CANON]` marker in DESIGN.md, which DESIGN.md:3 defines as
"owner-set facts", plus the ENEMIES.md hard rules. One row per canon bullet.

| # | canon bullet (source) | file that implements it | test that proves it |
|---|---|---|---|
| C1 | Loading screen shown on initial load and on run start, visible ≥ 5.0 s, ≤ 8 s total at L30 (DESIGN §2, §14) | `game/app/loading_screen.gd` | `test_loading.gd`; `tools/feel_probe.gd` row `loading_screen_hold 5.050 s` |
| C2 | Core loop: spawn on the beacon dais, beacon CLOSED; collect every black gift; the last real black gift opens the beacon; gold appears at the same slots; entering the beacon (1.5 u) completes the level; no timer ends a level (DESIGN §3) | `game/sim/gifts.gd`, `game/sim/beacon.gd` | `test_gifts.gd` (100 seeds) |
| C3 | Hazards inherit validated gift positions and never get their own placement logic (DESIGN §3.3) | `game/sim/mines.gd` + `terrain_ref/voidgen.py` stream MINE | `test_mines.gd` (`_test_contact_geometry`) |
| C4 | Dasher: dash 6 u in 0.20 s, one charge, regenerates in 3.0 s (DESIGN §4) | `game/sim/controller.gd` | `test_classes.gd` (`dash moved 6.0`) |
| C5 | Athletic: +15% run speed from the start (10.35 u/s); speed upgrades ×1.5; double-jump upgrades ×1.3 height (DESIGN §4) | `game/sim/controller.gd`, `game/sim/upgrades.gd` | `test_classes.gd` |
| C6 | Per-level pools: the shop never shows the full catalog; `data/upgrade_pools.json` maps the brackets (DESIGN §8) | `game/data/upgrade_pools.json`, `game/sim/offers.gd` | `test_content.gd` (`_pools_and_api`), `test_offers.gd` |
| C7 | Affordability filter: offered only if `price ≤ max(2 × purse, 80)` (DESIGN §8) | `game/sim/offers.gd` (`AFFORD_FLOOR := 80`) | `test_offers.gd` |
| C8 | Level-1 pool is exactly Paycheck, More, Yearn for Speed (DESIGN §8) | `game/data/upgrade_pools.json` | `test_content.gd` (`ids == ["paycheck","more","yearn_for_speed"]`) |
| C9 | Paycheck: +25 g on beacon entry per stack (DESIGN §8) | `game/sim/upgrades.gd` | `test_upgrades_script.gd` |
| C10 | More: +10% gift yield per stack (DESIGN §8) | `game/sim/upgrades.gd` | `test_upgrades_script.gd` |
| C11 | Yearn for Speed: +10% run speed per stack (DESIGN §8) | `game/sim/upgrades.gd` | `test_upgrades_script.gd` |
| C12 | Defuse Kit: +20% defuse chance per stack, cap 60%, deterministic roll per (seed, level, slot) (DESIGN §8, §3.3) | `game/sim/mines.gd` | `test_mines.gd` (`_test_determinism`, `_test_rates`) |
| C13 | Subspacial Barrier: 1 shield per level, restored on beacon entry, absorbs exactly one tripmine, checked after the defuse roll (DESIGN §8) | `game/sim/mines.gd` | `test_mines.gd` (`_test_ladder`) |
| C14 | Radar Module: Mines: disguised tripmines within 14 u get a pink outline through fog (DESIGN §8) | `game/view/tripmine_view.gd` (`RADAR_RANGE := 14.0`) | `test_vfx.gd` |
| C15 | Counter-play map: tripmines ← Defuse Kit / Subspacial Barrier / Last Light (DESIGN §8) | `game/sim/mines.gd` four-step ladder | `test_mines.gd` (`_test_ladder`) |
| C16 | The intermission lobby is a physical place (DESIGN §11) | `game/view/lobby/antechamber.gd` | `test_lobby.gd` |
| C17 | Void charges: 2 held, cap 2; a fall spends 1; beacon restores 1; charges carry over between levels (DESIGN §3.1) | `game/sim/controller.gd`, `game/sim/beacon.gd` | `test_charges.gd` |
| C18 | Last Light: once per run, only while ≥ 1 charge is held, saves an enemy/tripmine/nuke kill, never a void fall (DESIGN §3.1) | `game/sim/controller.gd` | `test_last_light.gd` |
| C19 | BILLBOARDING: every PNG enemy always faces the player, never seen edge-on (ENEMIES.md hard rule) | `game/view/billboard.gd`, `game/view/enemy_view.gd` | `test_billboard.gd` |
| C20 | HITBOXES: the hitbox covers only the body in the PNG, never the transparent padding (ENEMIES.md hard rule) | `game/sim/enemy_runtime.gd` + per-frame `body_rect` | `test_hitbox.gd` |
| C21 | TRANSPARENCY: every PNG has a fully transparent background, validated against fog and palette (ENEMIES.md hard rule) | `game/tools/validate_sprites.gd` | gate step 8: `SPRITES OK 515 checks over 12 sprites.json` |
| C22 | DISCLAIMER required in README + about screen (ENEMIES.md hard rule) | `README.md`, `game/app/menu.gd`, `game/view/lobby/antechamber.gd` | `test_disclaimer.gd` — **partial, see §6** |
| C23 | TBD FALLBACK: a refusal never stalls the run; name "TBD", placeholder PNG, `"tbd": true`, listed in TBD.md (ENEMIES.md hard rule) | `game/tools/make_tbd_png.gd`, `TBD.md` | `TBD.md` rows 1-17 + §2 audio rows; `claude` is the one live `"tbd": true` |
| C24 | Seed in, world out: deterministic, input-driven simulation; multiplayer later = sync seed + inputs (DESIGN §1.6, §13) | `game/sim/state_hash.gd`, `game/sim/sim.gd` | `test_replay.gd` (60 checkpoints, plus a perturbation that must diverge) |
| C25 | Drop-in content: enemies, curses, upgrades, biomes, gimmicks and modes added without touching the core (DESIGN §1.5) | `game/core/registry.gd`, `game/core/content_api.gd` | `test_dropin.gd` — **but see §5, the core is not clean** |

**MISSING: none.** Every canon bullet has an implementing file and a proving test. Two rows (C22, C25)
are implemented but their proof is weaker than the criterion claims; both are detailed in §5 and §6.

---

## 4. The 12-enemy roster, name by name

ENEMIES.md's Overview table is the fixed roster. Checked against `game/content/enemies/`, each
`enemy.json`'s `name`, and each `sprites.json`'s `tbd` flag.

| # | ENEMIES.md name | content folder id | `enemy.json` `name` | `sprites.json` `tbd` | verdict |
|---|---|---|---|---|---|
| 1 | kiwi cat | `kiwi_cat` | kiwi cat | false | MATCH |
| 2 | coil | `coil` | coil | false | MATCH |
| 3 | thicc ben | `thicc_ben` | thicc ben | false | MATCH |
| 4 | Isagi | `isagi` | Isagi | false | MATCH |
| 5 | nuke | `nuke` | nuke | false | MATCH |
| 6 | YOU?! | `you` | YOU?! | false | MATCH |
| 7 | gift Larper | `gift_larper` | gift Larper | false | MATCH |
| 8 | toucher | `toucher` | toucher | false | MATCH |
| 9 | seal | `seal` | seal | false | MATCH |
| 10 | address me | `address_me` | address me | false | MATCH |
| 11 | Claude | `claude` | Claude | **true** | MATCH, documented TBD (TBD.md row 15 / row 26: the clawd Crab plushie source was never fetched; the logo frames are real art) |
| 12 | gin ichimaru | `gin` | gin ichimaru | false | MATCH |

**No enemy was silently renamed.** All twelve ENEMIES.md names appear verbatim as `enemy.json` `name`
values. The one `"tbd": true` is `claude`, and it is listed in TBD.md (row 15, and row 26 for the
plushie). Judged under A16, not A8.

**One id inconsistency, found here and not by any test:** the content folder id is `gin`, and
`game/data/offering_schedule.json` gates it as `"gin"`, but `game/content/curses/twin_fangs.json` sets
`"requires_enemy": "gin_ichimaru"`. `content_api.eligible_curses()` matches `requires_enemy` against the
vote dictionary, and votes are keyed by the altar id (`intermission.gd:275`, `votes[eid]`), which is the
enemy id `gin`. **`twin_fangs` can therefore never become eligible: one of the 46 curses is unreachable
in play.** `test_content.gd` only exercises `zoomies`/`kiwi_cat`, so nothing catches it. The same
`gin_ichimaru` string is hardcoded in `game/core/schemas/curse.schema.json`'s enum, which is why the
schema accepts the bad value.

---

## 5. Boundary result: no core file names a content id

**Gate step 4 passes:** `OK boundary scan (ran in run_all: game/tests/test_boundaries.gd)`, and
`test_boundaries.gd` is part of the `TESTS 55 passed 0 failed` run. **The scan is nonetheless vacuous
for content ids, and my own grep finds four violations it cannot see.**

### 5.1 Why the existing proof does not prove the claim

`game/tests/test_boundaries.gd` has:

```gdscript
# Content ids that scenery code may never name. Empty today; every ticket that adds content
# appends its ids here (registry ids only, e.g. "kiwi_cat"), and the scan grows with them.
const KNOWN_CONTENT_IDS: Array[String] = []
```

The list is **empty**. The loop `for id in KNOWN_CONTENT_IDS` therefore never executes, so the
"names content id" half of the scan asserts nothing. The comment says every ticket appends its ids;
none did. The scan also reads only `*.gd` files (`_gd_files` filters `f.ends_with(".gd")`), so the
`core/schemas/*.json` files are outside it entirely. The forbidden-engine-string half of the scan
(`Node`, `get_tree`, `Engine.`, `Time.`, `randf`, `randi`, `PhysicsServer`, `Input.`) is real and does
pass.

### 5.2 My own grep: every content id against sim/, core/, terrain/

Ids taken from the content tree (12 enemy folders, 46 curse files, 36 upgrade files, 5 biome files),
matched whole-word against every `.gd` under `game/sim`, `game/core`, `game/terrain`:

| file | what it names | verdict |
|---|---|---|
| `game/core/schemas/curse.schema.json:11` | `"requires_enemy"` enum hardcodes **all 12 enemy ids**: `kiwi_cat, coil, thicc_ben, isagi, nuke, you, gift_larper, toucher, seal, address_me, claude, gin_ichimaru` | **VIOLATION** — a core file naming content ids. Not scanned (it is `.json`). It is also why the bad `gin_ichimaru` value in §4 passes validation. |
| `game/sim/death.gd:29-41` | the `CODES` map hardcodes **all 12 roster display names** (`"kiwi cat"`, `"coil"`, `"Isagi"`, `"nuke"`, `"YOU?!"`, `"gift Larper (Tripmine)"`, `"toucher"`, `"seal"`, `"address me"`, `"Claude"`, `"gin ichimaru"`) | **VIOLATION in spirit** — display names, not ids, so the literal rule is met; but the roster is hardcoded in `sim/`, so a 13th enemy needs a `sim/death.gd` edit. That breaks drop-in (A14). |
| `game/sim/upgrades.gd:37` | `const ROLE_CARTOGRAPHER := "cartographer"` — `cartographer` is an upgrade id (`content/upgrades/cartographer.json`) | **VIOLATION** — a sim file naming an upgrade id. |
| `game/sim/controller.gd:396` | `ev.append({"e": "updraft"})` — `updraft` is an upgrade id (`content/upgrades/updraft.json`) | **VIOLATION** — a sim file naming an upgrade id. |
| `game/core/schemas/upgrade_pools.schema.json:2` | `$comment` names `paycheck, more, yearn_for_speed` | comment only; noted, not counted. |
| `game/sim/death.gd:77` | comment names `D-CURSE:hungry_void` | comment only; noted, not counted. |

**Verdict: FAIL.** The rule "nothing under `terrain/ sim/ core/` may contain … any content id" is
violated by `core/schemas/curse.schema.json` (all 12 enemy ids) and by two sim files naming upgrade ids.
The gate's boundary step is green because the check that would catch this is an empty array.

---

## 6. Disclaimer result

The exact string, from FLEET_PACK.md T-001's spec (em dash, as the repo writes it):

> VOIDWRAP RUN is a personal, non-commercial project — no money is involved, and it is not affiliated with, endorsed by, or connected to any person, brand, character, or IP referenced or depicted in the game.

| location | present? | byte-exact? |
|---|---|---|
| `README.md` line 7 | yes | **YES** — `t001 in readme` is `True`; em dash `—` (U+2014) present |
| lobby About plaque, `game/view/lobby/antechamber.gd:63` (`const DISCLAIMER`, rendered at line 290 as `"ABOUT\n\n" + DISCLAIMER`) | yes | **NO — one character differs.** At index 51 the plaque has ASCII hyphen `-` where the spec has em dash `—`. Everything else matches; `flat.replace(" - ", " — ") == t001` is `True`. |
| app menu About screen, `game/app/menu.gd:18` (`ABOUT_DISCLAIMER`) | yes | it carries the **ENEMIES.md** paragraph ("this is a personal, non-commercial project with no money involved. …"), a *different* wording from the T-001 string. PARKED.md #2 records the two-document disagreement. |

**A15's stated proof does not cover the plaque.** `test_disclaimer.gd` asserts three things: that
`menu.gd`'s `ABOUT_DISCLAIMER` equals the ENEMIES.md paragraph, that `about_text()` contains it, and
that `README.md` contains it. **It never reads `antechamber.gd`.** So the "lobby About plaque" half of
A15 has no test at all, and the one-character difference above is exactly what such a test would catch.

**Verdict: PARTIAL.** README is verbatim and tested. The lobby plaque is present but is not verbatim
(ASCII hyphen for em dash) and is untested.

---

## 7. Retired vocabulary — every hit

Patterns from DECISIONS.md D-052 ("Retired vocabulary"), case-insensitive, over `DESIGN.md`,
`FLEET_PACK.md`, `README.md`, `game/data/`. Allowed hits: lines beginning `SUPERSEDED BY`, and verbatim
owner quotes in FLEET_PACK.md. **Seven hits. None of the seven is a `SUPERSEDED BY` line and none is an
owner quote.**

| # | pattern | file:line | the line (trimmed) | classification |
|---|---|---|---|---|
| 1 | `\bHP\b` | `FLEET_PACK.md:645` | `Zero hits for "damage", "HP", "rooms", "hop", "2 per level" across all docs and code (allowed` | **Not allowed.** This is T-091's own instruction text naming the retired words as grep targets. It is not an owner quote and not a `SUPERSEDED BY` line. |
| 2 | `damage` | `FLEET_PACK.md:645` | same line as #1 | **Not allowed**, same reason. |
| 3 | `LETHAL` | `DESIGN.md:471` | `while a chaser, a nuke ring, a gin patch or a coil ring makes stillness lethal.` | ordinary-English adjective, lowercase; not the retired Overtuned "LETHAL" state. Still a hit under a case-insensitive grep. |
| 4 | `LETHAL` | `DESIGN.md:574` | `- **Chaser ceiling (D-074): at most 6 floating lethal bodies in play at once** (kiwi cat, toucher,` | ordinary-English adjective. |
| 5 | `LETHAL` | `FLEET_PACK.md:196` | `… the second lethal hit after it is spent kills; HUD icon lit while armed …` | ordinary-English adjective. |
| 6 | `LETHAL` | `FLEET_PACK.md:321` | `… or airborne/glitched floor would make stillness lethal.` | ordinary-English adjective. |
| 7 | `LETHAL` | `game/data/offering_schedule.json:7` | `"_doc": "D-074 chaser ceiling (FINAL): an E altar is not drawn when picking it would push the floating lethal bodies in play past 'ceiling'. …"` | ordinary-English adjective. |

Zero hits for `hit points`, `max_hp`, `heal`, `Patch Kit`, `Thick Skin`, `Glass Jaw` in any of the four
targets. The retired *mechanic* term (thicc ben's "Overtuned" LETHAL state) does not appear anywhere.

**Verdict: 7 hits, 0 allowed.** Two are a self-referential grep instruction in FLEET_PACK.md; five are
the ordinary English word "lethal" used as an adjective. Nothing was edited.
