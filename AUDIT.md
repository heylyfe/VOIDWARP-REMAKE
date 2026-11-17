# AUDIT.md — T-099, the final conformance audit before alpha

Auditor: implementation sub-agent, zero prior context, own checkout.
Branch: `t3/69dd5808`. Commit audited: `8fb49d3` ("Merge T-ART address_me: real sprite art and per-state frames").
Date of run: 2026-11-17. Machine: AMD Ryzen 5 9600X 6-Core, AMD Radeon RX 9060 XT, Windows, Godot 4.7.2-stable.

**This file is the only thing the audit wrote.** No code, test, document, threshold or data file was
edited. Every defect found is written here and left in place.

---

## 0. Method, and four document defects worked around

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

- **1 of 10 seeds completed level 1** (`entered=2`, seed 2). The other nine died on level 1. That is **10%**, against a required **95%**. All ten runs died; **8 of the 10 deaths are `D-VOID`** (a void fall at 0 charges), and **7 of the 9 level-1 deaths are `D-VOID`** (the other two are `D-KIWI` and `D-COIL`).
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
- **The "boundary scan clean" half does not hold.** The scan is green only because `KNOWN_CONTENT_IDS` is empty and it reads only `.gd` files; `game/core/schemas/curse.schema.json` hardcodes all 12 enemy ids, and `game/sim/death.gd` hardcodes the 12 roster display names. A 13th enemy therefore needs a core edit to `death.gd` (and to the curse schema if any curse requires it). The view layer is worse: `game/view/hud/run_over.gd` (13 ids), `game/view/hud/danger_text.gd` (12 ids) and `game/view/fog_env.gd` (5 biome ids) hardcode the whole roster and biome list, so a drop-in enemy registers but cannot render. See section 5.
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
for content ids, and my own grep finds four violations it cannot see in `sim/` and `core/`, plus a
further ten non-per-enemy files in `view/` that hardcode the roster and the biome list.**

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

### 5.3 The view and app layers (the brief's stricter rule)

The audit brief says `game/sim/`, `game/core/`, `game/view/` (except per-enemy view files) and
`game/app/` must not hardcode an enemy/curse/upgrade/biome id. **FLEET_PACK.md section 3's own dependency
rule is looser** — it forbids content ids only under `terrain/ sim/ core/` and says "view and app may use
everything". So the rows below are violations of the brief's rule, not of FLEET_PACK section 3. Both are
reported because the brief is the instruction this audit runs under.

Whole-word id matches in `game/view` and `game/app`, excluding the twelve per-enemy `*_view.gd` files:

| file | ids named | note |
|---|---|---|
| `game/view/hud/run_over.gd` | **13** | the full 12-enemy roster plus `D-COIL`/`D-GIN` codes; a 13th enemy needs this file edited |
| `game/view/hud/danger_text.gd` | **12** | the full 12-enemy roster mapped to danger strings |
| `game/view/fog_env.gd` | **5** | all five biome ids hardcoded, plus `biome_id := "deepwater"` as the default |
| `game/view/hud/cartographer_map.gd` | 2 | the `cartographer` upgrade id, and a `preload` of its script |
| `game/view/enemy_anim.gd` | 2 | `coil` in comments only |
| `game/view/audio/claude_audio.gd` | 2 | the `claude` audio directory |
| `game/view/vfx/pocket_ring.gd` | 1 | `pocket_beacon` |
| `game/view/vfx/coil_telegraph.gd` | 1 | `coil` |
| `game/view/lobby/antechamber.gd` | 1 | `"deepwater"` default biome |
| `game/view/level_mesher.gd` | 1 | `"deepwater"` fallback palette |
| `game/view/hud/icon_rows.gd` | 1 | an upgrade id |
| `game/view/billboard.gd` | 1 | an enemy id |
| `game/view/audio/{seal,kiwi_cat,gin,gift_larper}_audio.gd` | 1 each | per-enemy audio directories; arguably per-enemy files |

**Verdict under the brief's rule: FAIL.** The two HUD files (`run_over.gd`, `danger_text.gd`) and
`fog_env.gd` hardcode the entire enemy roster and the entire biome list. Adding a 13th enemy or a 6th
biome requires editing view code, which is exactly what "drop-in content" (DESIGN section 1.5, canon C25)
forbids. `test_dropin.gd` does not catch it because it only asserts that a fixture *registers*, never
that it *renders*.

**Verdict under FLEET_PACK section 3's rule: FAIL anyway**, on the `sim/` and `core/` rows in section 5.2.

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

---

## 8. Every `[CONTESTABLE]` entry added during the run

`grep -c "\[CONTESTABLE\]" DECISIONS.md` = **216 occurrences**; **130 of them are section
headings** (`grep -c "^### D-.*\[CONTESTABLE\]"` = 130). The 130 headings are the owner's open
rulings and are listed one per line below. The other 86 occurrences are inline `[CONTESTABLE]`
markers inside entries whose heading is not itself marked; they are the same rulings restated in
prose and are not counted twice.

| # | id | one-clause summary |
|---|---|---|
| 1 | `D-T010-2` | move_x / move_z axis scale: int8 in −127..127 = −1..+1 of RUN_SPEED, clamped |
| 2 | `D-T010-3` | sim RNG sub-streams are named, per-run, re-seeded per level: `s(mix(mix(run_seed, 900 + id), level_number))`, ids w... |
| 3 | `D-062` | Cold Start's Athletic penalty is coyote time −0.05 s |
| 4 | `D-T012-1` | Terminal fall speed is 40 u/s. |
| 5 | `D-T012-3` | Upgrade-strength composition, and Hungry Void clamp reading. |
| 6 | `D-T082-1` | Third-person orbit camera: pivot-orbit rig and its numbers (T-082). |
| 7 | `D-T082-2` | Bindings and capture semantics: data/bindings.json, Held-bit buttons, diagonal normalization, HUD/pause are app-lev... |
| 8 | `D-T082-3` | Settings: user://settings.json, clamp-not-reject on load (T-082, the T-024 addendum made concrete). |
| 9 | `D-T014c-1` | Fog density for levels 31+ (the cycled acts). |
| 10 | `D-T011-1` | The fog-readability check runs in linear radiance, not on raw sRGB bytes (T-011, tools/fog_check.gd). |
| 11 | `D-T011-6` | Deepwater walkway_light raised from #2A5BFF to #3A74FF (orchestrator, at T-011's R6 gate). |
| 12 | `D-T020-2` | The pickup test point is the player's centre (feet + 0.9 u) (T-020) |
| 13 | `D-T020-3` | "Last 20%" reads as remaining * 5 <= total_real (floor semantics) (T-020) |
| 14 | `D-T027-2` | api.los is a ray march at 0.25 u against tile slabs and prop boxes (T-027). |
| 15 | `D-T027-7` | Diegetic spawn text is the enemy's own display name, in-world, fading (T-027). |
| 16 | `D-T022-6` | The A11 audit's simulation model, and why it is weak evidence (T-022). |
| 17 | `D-T071-4` | Volley reading: start-to-start 45 ticks, balls 9 apart, remainder on the last volley (T-071). |
| 18 | `D-T071-5` | SalvoClock: budget from the FIRST tracking tick, restart never resets, expires ON tick 360 (T-071). |
| 19 | `D-T071-6` | Projectiles report where and why they ended (T-071). |
| 20 | `D-T024-4` | The About disclaimer is the ENEMIES.md paragraph VERBATIM |
| 21 | `D-T024-5` | Rotation boundary and first tip are not specified anywhere (T-024). |
| 22 | `D-T025-1` | HUD layout: positions, sizes, and the purse format (T-025). |
| 23 | `D-T025-2` | The gift counter is phase-scoped |
| 24 | `D-T021-6` | View tells: 1 rev / 4 s turn, constant pink particles, rim glow beyond 12 u (T-021 |
| 25 | `D-T023-2` | the E draw gates on the NEXT level (T-023). |
| 26 | `D-T023-3` | the CLASS bay is mandatory in the pre-run lobby (T-023). |
| 27 | `D-T023-4` | curse gating and bounty use the level just completed (T-023). |
| 28 | `D-T023-5` | the REST bay carries a paid reroll plinth (T-023). |
| 29 | `D-T086-1` | The HUD animation clock is ticks at 60 per second |
| 30 | `D-T086-2` | The spend's void edge flash is a 12-tick single flash, 48 px edge band, alpha 0.55 -> 0 (T-086). |
| 31 | `D-T086-3` | Already-full restore = one whole-row glow pulse over 12 ticks (T-086). |
| 32 | `D-T086-4` | Field Dressing pip: stays filled, white flash for the first 12 of 60 FREE ticks (T-086). |
| 33 | `D-T086-5` | The restore glint is a white surface line plus a 6-tick glow tail (T-086). |
| 34 | `D-T086-6` | Last Light shatter = 12 ticks, six wedge shards, concurrent with the 12-tick bloom (T-086). |
| 35 | `D-T074-1` | "first-shown level" = the gate table's min_level (T-074). |
| 36 | `D-T074-2` | the chaser-ceiling numbers live in the schedule file's "chaser" block (T-074). |
| 37 | `D-T074-3` | kitten bodies at draw time (T-074). |
| 38 | `D-T074-4` | the FREE altar may re-show the type picked at the previous vote (T-074). |
| 39 | `D-T074-5` | altar slots NEW / REPEAT / FREE in that draw order |
| 40 | `D-T074-6` | the 1,000-run walker's vote policy (T-074). |
| 41 | `D-T072-1` | "No enemy body within N u" reads as 3D distance (T-072). |
| 42 | `D-T072-5` | The gate evaluates the targeted player, index 0 today (T-072). |
| 43 | `D-T083-2` | All art is TBD, so multi-frame spec sequences collapse onto the placeholder frames (T-083). |
| 44 | `D-T083-3` | fps rows convert to ticks exactly (T-083). |
| 45 | `D-T083-4` | No invented numbers: unstated cells are null |
| 46 | `D-T083-5` | gin attack_launch: the launch frame is held for the 18-tick spear flight (T-083). |
| 47 | `D-T030-3` | kiwi cat's meow rides the sim telegraph channel |
| 48 | `D-T030-4` | kiwi cat audio: cue names `meow` / `meow_double`, files under `assets/audio/enemies/kiwi_cat/`, placeholders until... |
| 49 | `D-T030-5` | the meow re-arms on range entry: the first tick back inside 14 u meows at once (T-030). |
| 50 | `D-T-031-2` | The coil arc apex is 4.0 u above the chord (T-031). |
| 51 | `D-T-031-3` | "Airborne at landing avoids the shockwave" is read as a 1 HU y-band on the landing plane (T-031). |
| 52 | `D-T-031-4` | The landing kill is a horizontal circle r = 1.2 u with no y band (T-031). |
| 53 | `D-T-031-9` | coil copy staggering: first cue delay staggered by CYCLE/n, never mid-cue spawn (T-031). |
| 54 | `D-T-032-1` | thicc ben's touch re-trigger is cooldowned at 30 ticks (T-032). |
| 55 | `D-T-032-2` | the 13.35 s teleport interval is not shortened by overtime or tempo (T-032). |
| 56 | `D-T-032-3` | the ben-ring cleanse radius is horizontal (XZ) distance (T-032). |
| 57 | `D-T-032-8` | ben's stats carry pursuit_ceiling = burst_ceiling = 0.0 and no base_speed (T-032). |
| 58 | `D-T-032-9` | ben's teleport cycle counts from on_spawn, not from level start (T-032). |
| 59 | `D-T-032-10` | telegraph kind "teleport", circle r = 1.2 u at the locked point (T-032). |
| 60 | `D-T-032-11` | lock break is measured 3D from the locked point to the player's feet (T-032). |
| 61 | `D-T-032-13` | ben's touch has no blur "strength" state in the sim |
| 62 | `D-T-035-1` | YOU?!'s ring vertical kill window: feet-based, (feet_e - 1.5, feet_e + 1.0). |
| 63 | `D-T-035-2` | Ring radial kill window: /d - r/ <= 0.7 u. |
| 64 | `D-T-035-3` | The ring-release (attack) hold is 18 ticks. |
| 65 | `D-T-035-5` | The 10 u rumble trigger is the 3D nearest-player distance. |
| 66 | `D-T-035-6` | YOU?! keeps floating during its rumble. |
| 67 | `D-T-035-7` | Burst ceiling recorded as 1.00 - YOU?! has no burst. |
| 68 | `D-T-035-13` | The ring kill fans out over nearest_player() only (the section 12 API has no players-in-radius). |
| 69 | `D-T-036-1` | gift Larper's world body height is 1.0 u / hit diameter 0.8 u (T-036) |
| 70 | `D-T-036-2` | gift Larper's pursuit ceiling and burst ceiling are 0.0 (T-036) |
| 71 | `D-T-034-1` | The nuke's LOS ray origin: 12 u high, 20 u out, direction fixed per salvo (T-034). |
| 72 | `D-T-039-1` | address me's body contact does NOT kill (D-065 FINAL wins a ticket deliverable) (T-039) |
| 73 | `D-T-039-2` | stillness is read from the controller snapshot nearest_player returns (T-039) |
| 74 | `D-T-039-3` | the 5.0 s expiry kill has no distance limit (T-039) |
| 75 | `D-T-039-4` | the return cadence: uniform(30,45) s, -5 s per extra vote beyond the first, hard floors (15, 30) s (T-039) |
| 76 | `D-T-039-5` | between episodes the body is parked at y = 1000.0 u (T-039) |
| 77 | `D-T-039-6` | the countdown travels as row state + pending=["address_me"] |
| 78 | `D-T-037-1` | The toucher's burst ceiling is 0.75, its own pursuit ceiling (T-037). |
| 79 | `D-T-037-2` | "Infects all tiles within 3 u below it" is tiles whose centre sits within 3.0 u of the finger and whose top is at o... |
| 80 | `D-T-037-3` | The 60-tile cap frees seats oldest-first (FIFO eviction) (T-037). |
| 81 | `D-T-037-4` | The 18 s tile life reads the level number from cfg "level_number" (T-037). |
| 82 | `D-T041-1` | The fade-in window is 15-25 u with bounds inclusive, ties to the lowest tile index (T-041). |
| 83 | `D-T041-2` | The platform-tile-only filter is data-only on the current sim surface (T-041). |
| 84 | `D-T041-3` | "Never marks the beacon dais" = the dais cell is cut out of the marked patch (T-041). |
| 85 | `D-T041-4` | The void zone's column kill and the fade-back lift are row state |
| 86 | `D-T041-5` | The strike cooldown is row arithmetic: 840 base, -180 per extra vote, floored at 300 (T-041). |
| 87 | `D-T-040-1` | "Floats at 4 u/s keeping within 20 u" is a leash, not a chase (T-040). |
| 88 | `D-T-040-2` | The drums' ring kill windows adopt D-T-035-1/-2's YOU?! readings (T-040). |
| 89 | `D-T-040-4` | The strings beam's sweep sense is counterclockwise |
| 90 | `D-T040-6` | Plushie placement: the farthest tile in the 10-25 u band, 2 u apart |
| 91 | `D-T073-1` | 0.0 pursuit/burst ceiling marks "not a floating body / no burst" |
| 92 | `D-T073-2` | gift Larper's merged tripmine model numbers (world_height 1.0 / body_height 1.0 / hit_diameter 0.8) kept under sect... |
| 93 | `D-T073-3` | T-073's check script treats section 5's em-dash diameter as "no hit_diameter key" and parses the burst bound from t... |
| 94 | `D-T050-1` | Slippery = the `friction` stat set to 0.4 while on the surface (R4 addendum, T-050 |
| 95 | `D-T054-2` | DESIGN.md section 10's "tripmine particles vs platform light >= 3.0" is unsatisfiable by ANY platform_light hex |
| 96 | `D-T055-1` | Placeholder cues land at `game/assets/audio/enemies/<id>/<cue>.wav`, not section 3's `content/enemies/<id>/audio/`... |
| 97 | `D-T055-2` | Isagi and nuke enemy.json files name NO audio cues |
| 98 | `D-T055-3` | All synth recipes and lengths are placeholder stand-ins |
| 99 | `D-T056-1` | Minimal boot scene (app/main.tscn) so the exported exe starts to the menu (T-056). |
| 100 | `D-T087-1` | The section 3 row -> enemy.json cue-name reconciliation (T-087). |
| 101 | `D-T087-2` | Loop cues get a 2.0 s bed |
| 102 | `D-T087-3` | Claude `string_sweep` is 3.0 s |
| 103 | `D-T087-4` | Behavior-phase anchors where the sim emits no event (T-087). |
| 104 | `D-T087-5` | `keystroke_tick` and `isagi_shoot_sae_math_final_shot` have no section 3 row (T-087). |
| 105 | `D-T053-2` | Cartographer's "anywhere you have stood" is the union of 1 u tiles, measured tile-centre to tile-centre (T-053). |
| 106 | `D-T053-3` | Pocket Beacon: INTERACT press edge while standing still starts a 3.0 s channel |
| 107 | `D-T053-5` | Twin Dash is a second dash stock with its own 3 s regen, charged at purchase (T-053). |
| 108 | `D-T053-6` | Updraft: vy = sqrt(2 × 32 × 3) ≈ 13.8564 (apex exactly 3.0 u under gravity 32), once per glide engagement, 6 s cool... |
| 109 | `D-T053-7` | Marathon's +2 max stacks reaches the shop as an optional max-stacks bonus dict in draw_shop |
| 110 | `D-T051-3` | Cold Start's per-class mapping: dasher regen x1.25, glider 0 start energy, athletic coyote -0.05 s (T-051) |
| 111 | `D-T085-1` | The tripmine star is split out of the single vertex-coloured .glb at load time, and the four side-face hexagrams ar... |
| 112 | `D-T085-2` | The particle "± 0.2 u drift" is the emission volume radius (T-085). |
| 113 | `D-T061-2` | A12's five rows measured at component level () (T-061) |
| 114 | `D-T061-3` | The perf probe runs the 22-enemy scene as one real sim hour () (T-061) |
| 115 | `D-T061-4` | The probe's dodge bot is built in, pending the real bot () (T-061) |
| 116 | `D-T060-1` | The probe's "competent bot" is fixed seeded policy, not "a human": BFS graph distance for nearest-gift, footprint-o... |
| 117 | `D-T080-1` | The log's tick clock is the run-wide accumulated sim tick (T-080) |
| 118 | `D-T080-8` | The ticket says "20 record types" but its verbatim list has 18 |
| 119 | `D-T081-4` | Restart time (signal 2) is NOT measurable from the T-080 records |
| 120 | `D-T075-4` | the answer executor's reaction timing |
| 121 | `D-ART-NUKE-2` | The derivation constants are art judgment, owner may flip |
| 122 | `D-ART-COIL-1` | coil's real-art derivation numbers (the shared pipeline skips this enemy) |
| 123 | `D-ART-YOU-1` | YOU?! frames: image segmentation against a near-fog source |
| 124 | `D-ART-YOU-2` | YOU?! frames: canvas, fit, contrast lift and the per-state set |
| 125 | `D-ART-GIN-2` | one distinct derived frame per anim-block state |
| 126 | `D-ART-GIN-3` | launch_00 fits the sword in a 500 px box, not 508 (T-ART-GIN) |
| 127 | `D-ART-gift_larper-2` | The art-derivation numbers are judgment, owner may re-tone |
| 128 | `D-ART-claude-2` | The Claude art derivation constants are art judgment, owner may flip |
| 129 | `D-ART-ADDRESS_ME-2` | the fog-contrast bar is met by lifting the hide, never the threshold |
| 130 | `D-ART-ADDRESS_ME-3` | background removal per image, constants stated |

**130 open owner rulings.** The ones that matter most for alpha, in the auditor's order:
`D-T054-2` (DESIGN section 10's fog row is unsatisfiable by any hex — parked, not worked around),
`D-T039-1` (address me has no contact kill; D-065 FINAL beats a ticket deliverable),
`D-T075-4` (the answer lab's reaction timing), `D-T024-4` (two disclaimer wordings),
`D-T083-2` (art was TBD when the anim block was written), and the ten `D-ART-*` derivation-constant
entries (art judgment the owner may re-tone).

---

## 9. Retro defect classes checked

Six classes, each with what was looked for and what was found.

### 9.1 Was a threshold moved to fit data? — **No.**

- The 5,000-seed harness limits are the documented ones and none was relaxed: D1 max dev 0.00576 vs limit 0.01000; D4 0.3935 vs 0.5; D6 0.0179 vs 0.1; D8 10.374 vs 50 and 75.0 vs 80; D9 112.5 vs 250 and 1139.5 vs 2000.
- A11's caps are unchanged: `afford1 99.5% >= 80%`, `afford3 29.3% <= 30%`. The 30% cap was **not** widened to fit the 29.3% result.
- A12's bounds are unchanged: `void_fall_to_respawn 0.800 s <= 0.80 s` sits **exactly on** the bound. It passes; it was not moved to 0.85.
- The one place a threshold could have been moved is DESIGN.md section 10's "tripmine particles vs platform light >= 3.0" row, which `D-T054-2` proves is unsatisfiable by any `platform_light` hex. It was **left as INFO-only in `fog_check.gd` and parked**, not deleted and not lowered. That is the correct handling and it is recorded.
- **Risk, not a move:** two criteria pass with margins of 0.7 points (A11 afford3) and 0.0 s (A12 void fall). A future tuning pass that touches either will flip a PASS to a FAIL with no warning.

### 9.2 Is any dead time over its budget? — **No.**

`tools/feel_probe.gd`, all six rows PASS, `T-061 RESULT: OK`:

| row | measured | budget |
|---|---|---|
| loading_screen_hold | 5.050 s | >= 5.0 s |
| loading_screen_total_l30 | 5.050 s | <= 8.0 s |
| gate_to_level | 0.160 s | <= 2.0 s |
| death_to_run_over | 0.0044 s | <= 2.0 s |
| void_fall_to_respawn | 0.800 s | <= 0.80 s |
| generate_mesh_l30 | 0.159 s | <= 1.5 s |

The 5.0 s loading hold is a mandated minimum (DESIGN section 2 `[CANON]`), not dead time. No mandatory non-interactive wait exceeds its budget.

### 9.3 Is a gift inside geometry? — **No.**

- The generator's own invariant forbids it: `terrain_ref/validate.py:507-516` — "the beacon and every real gift slot must survive the cylinder: a gift inside it is uncollectable, so a mine may never create one" — and the 5,000-seed harness passes 32/32.
- Gift reachability is measured per level bucket and passes in all six: `gift_density`, `first_gift`, `starve_p95`, `starve_max` all PASS (e.g. bucket 26-30: first_gift 215.56, starve_p95 142.30, starve_max 246.73, all inside their limits).
- `test_gifts.gd` additionally runs a slot-position confinement scan (no file under `sim/` or `core/` other than `sim/gifts.gd` mentions `slot_pos`).

### 9.4 Is a check weakened or skipped? — **Yes, five instances.**

| # | what | where | effect |
|---|---|---|---|
| 1 | `KNOWN_CONTENT_IDS` is an **empty array** | `game/tests/test_boundaries.gd` | the "names content id" half of the boundary scan asserts nothing; the gate's boundary step is green vacuously |
| 2 | the boundary scan reads only `*.gd` | `test_boundaries.gd` `_gd_files()` | `game/core/schemas/*.json` is outside it, which is why the 12 hardcoded enemy ids in `curse.schema.json` are invisible |
| 3 | `test_disclaimer.gd` never reads the lobby plaque | `game/tests/test_disclaimer.gd` | A15's "lobby About plaque" half has no test; the ASCII-hyphen/em-dash difference is exactly what it would catch |
| 4 | A4 says 10 recorded bot runs; the test records 1 | `game/tests/test_replay.gd` | determinism is proven on one 3,600-tick run with 60 checkpoints, not on ten runs |
| 5 | `bot_run.gd` silently ignores unknown flags | `game/tools/bot_run.gd` | FLEET_PACK section 4's stale `--seed/--levels/--class` command does not error; it runs a 200-run level-18 sweep (defect D1) |

Also noted, not counted: the gate prints `WARN resource import did not finish cleanly; continuing` before step 3. The import step is non-fatal by design and every downstream step still ran and passed.

### 9.5 Does any test assert something it documents as broken? — **Yes, three.**

| # | test | what it documents | what it asserts |
|---|---|---|---|
| 1 | `game/tests/test_enemy_nuke.gd:24-27` | "the sim never expires telegraph footprints (the ring's footprint stays live after it resolved) - both are the runtime's to fix, never this test's" | the test passes while the stale-footprint defect (PARKED.md #8, #9) is live |
| 2 | `game/tests/test_spawn_rule.gd:90-95` | PARKED.md #5: DESIGN.md section 5's note says `""` skips steps (a)/(b); the merged code runs (b) | the test pins `""` -> the farthest in-range lane (anchor index 2), i.e. the behaviour the doc contradicts |
| 3 | `game/tests/test_enemy_toucher.gd:240` | "rows in `rt.telegraphs` never expire and would pair across cycles" | the test works around the same defect rather than failing on it |

None of these is a false pass on a criterion the audit gates on, but all three are tests that encode a known defect as expected behaviour. They will keep passing after the defect is fixed unless they are rewritten.

### 9.6 Is any placeholder still magenta? — **Yes. Three frames.**

`game/content/enemies/claude/sprites/plushie_00.png`, `plushie_01.png`, `plushie_02.png` are the
`make_tbd_png.gd` output. Decoded pixel census (8-bit RGBA, 256x256, 50,176 opaque pixels each):

```
plushie_00.png  opaque px 50176  top colours [((255, 0, 255), 45872), ((168, 0, 168), 3520), ((5, 5, 5), 784)]
plushie_01.png  opaque px 50176  top colours [((255, 0, 255), 45872), ((168, 0, 168), 3520), ((5, 5, 5), 784)]
plushie_02.png  opaque px 50176  top colours [((255, 0, 255), 45872), ((168, 0, 168), 3520), ((5, 5, 5), 784)]
```

`(255,0,255)` is `#FF00FF` magenta, `(168,0,168)` is the darker rim, `(5,5,5)` is the "TBD" ink — exactly
`make_tbd_png.gd`'s `BODY := 0xFF00FFFF`, `BODY_EDGE := 0xA800A8FF`, `INK := 0x050505FF`. For contrast,
claude's real logo frame `idle_00.png` is `(217,119,87)`-dominant.

This is the **documented** TBD (TBD.md row 15 and row 26: the clawd Crab plushie source was never
fetched), so it is not a hidden defect and it is judged under A16, not A8. But the plushie is a
gameplay element — ENEMIES.md: "pick up clawd Crab to calm it down" — so **three magenta blocks ship in
the alpha build**, and the player will see them.

---

## 10. Appendix — T-081's fun-risk report (information only, not gated)

PARKED.md #17 records that T-081's done-when wanted this report pasted into AUDIT.md, which did not
exist. It is pasted here. Source: `tickets/T-081.response.md`, the `out/run_report.txt` block, 100 bot
runs with `--dodge`, seeds 0-99.

```
FUN-RISK REPORT (T-081, research/fable-funrisks.md; INFORMATION ONLY - no pass/fail, no threshold)
runs: 100
1. terrain vs enemy (risk 3)
  overall   charges spent    176 | terrain-caused   175 ( 99.4%) | enemy-caused     1 (  0.6%)
  overall   deaths           99 | terrain-caused    59 ( 59.6%) | every other code    40 ( 40.4%)
3. unseen deaths (risk 2)
  overall   deaths     99 | killer on screen = no    59 ( 59.6%)
4. level length and pressure (risk 4)
  1-5       black-phase median   36.9 s (n=14) | gold-phase median    3.6 s (n=14)
  6-10 .. 26-30   n=0 (no run reached level 6)
```

**The headline, and it is a design signal for the owner, not an acceptance criterion:** of 176 charges
spent across 100 bot runs, **175 (99.4%) were terrain-caused and 1 (0.6%) enemy-caused**; of 99 deaths,
**59 (59.6%) were `D-VOID`**. Every one of the 100 runs died on levels 1-5; none reached level 6. The
terrain is killing the player, not the enemies — and the audit's own A3 sample agrees (8 of 9 level-1
deaths were `D-VOID`).

---

## 11. Final verdict

**A1-A16: 12 PASS, 3 PARTIAL, 1 FAIL.**

| verdict | criteria |
|---|---|
| PASS (12) | A1, A2, A5, A6, A7, A8, A9, A10, A11, A12, A13, A16 |
| PARTIAL (3) | A4 (1 recorded run, not 10), A14 (boundary scan vacuous for content ids), A15 (plaque not verbatim, untested) |
| FAIL (1) | **A3** — the bot completes level 1 in 1 of 10 seeds (10%), against a required 95 of 100 |

12 + 3 + 1 = 16.

**THE ALPHA GATE DOES NOT PASS. The tag `v0.1.0-alpha.1` was NOT created.**

A3 is the blocking failure and it is not a measurement artefact: PARKED.md #4 (T-026) already recorded
`BOT-RUNS completed=0 failed=4`, and this audit's independent 10-seed sample reproduces it at 1/10. The
bot cannot finish level 1, so the game's core loop has never been demonstrated end-to-end by an
automated player. A4, A14 and A15 are conformance gaps in the *proofs*, not in the behaviour, and each
is a small fix (record ten runs; populate `KNOWN_CONTENT_IDS` and scan the schemas; add the plaque to
`test_disclaimer.gd` and make the dash match).

### The three findings that matter most for the owner

1. **The game cannot be finished by the bot, and the terrain is what kills it.** 1 of 10 seeds completes
   level 1; 8 of the 10 deaths are `D-VOID` and 7 of the 9 level-1 deaths are `D-VOID`. T-081's 100-run report says the same thing at scale:
   175 of 176 charges (99.4%) are terrain-caused, 59 of 99 deaths (59.6%) are `D-VOID`, and **no run
   reached level 6**. This is the single largest risk to the alpha being fun, and it is a design signal
   the owner must rule on — the audit does not gate on it, but A3 does fail because of it.
2. **The boundary scan is a green light wired to nothing.** `KNOWN_CONTENT_IDS` is empty and the scan
   reads only `.gd` files, so the "no core file names a content id" rule is unenforced. It is already
   violated: `game/core/schemas/curse.schema.json` hardcodes all 12 enemy ids, `game/sim/death.gd`
   hardcodes the 12 roster display names, and two sim files name upgrade ids. The view layer is worse —
   `run_over.gd` (13 ids), `danger_text.gd` (12 ids) and `fog_env.gd` (5 biome ids) hardcode the whole
   roster and biome list, so a drop-in enemy registers but cannot render. The same schema is why
   `twin_fangs`'s `requires_enemy: "gin_ichimaru"` (the enemy id is `gin`) passes validation — **one of
   the 46 curses can never be offered in play**, and no test notices.
3. **Three magenta placeholder blocks ship in the alpha.** `claude`'s `plushie_00..02.png` are still
   `make_tbd_png.gd` output (`#FF00FF`, 45,872 of 50,176 opaque pixels). It is documented in TBD.md, so
   it is not a hidden defect — but the plushie is the mechanic that calms Claude down, so the player will
   meet three magenta rectangles in the first Claude fight.

### What the audit did not do

- It did not fix anything. Every defect above is written here and left in place.
- It did not create the tag.
- It did not run A3's literal 100-seed sweep (the bot does not finish; a 30-seed extension ran ~60
  minutes without completing and was stopped). The 10-seed sample is decisive at 10% vs 95%.
- It did not visually verify anything except A1's menu.
