# AUDIT.md — T-099 RE-RUN, the final conformance audit before alpha, re-measured on current main

Auditor: implementation sub-agent (T-099 re-run), own worktree, read-only except this file.
Branch: `t3/9a991a4d`. Commit audited: **`64e3332`** ("Merge KIWI-SLOW: kiwi cat is a slow, lazy follower
(owner ruling FINAL)") — the tip of `main` when this run started.
First audit: commit `8fb49d3`, merged as `b0c6b3d`, verdict 12 PASS / 3 PARTIAL / 1 FAIL. This file
replaces it. Where a verdict changed, the old verdict is kept visible ("was X, now Y, because …").
Date of run: 2026-11-17. Machine: a 6-core AMD CPU, a discrete AMD GPU, Windows 11, Godot 4.7.2-stable.

**This file is the only tracked file the audit wrote.** No code, test, content, document, threshold or
data file was edited. Every number below comes from a command run in this session; the logs are in
`out/` (gitignored). Where something could not be measured, the text says so and says why.

**FIX-A3 (the bot-competence fix) is NOT on `main` and was not touched.** A3 is measured against what
`main` holds.

---

## 0. Method, and the document defects of the first audit — re-checked

Every command of FLEET_PACK.md §4 was run on this checkout. Long output was redirected to files under
`out/` and grepped; nothing was piped through `tail` in PowerShell. The gate ran while another worker's
bot sweep (FIX-A3, two `bot_run.gd` processes in the main checkout) was running on the same machine; it
still went green on the first try, so no re-run was needed.

| # | first-audit defect | status now | evidence |
|---|---|---|---|
| D1 | FLEET_PACK §4's bot command `-- --seed 1 --levels 1 --class dasher` has stale flags, silently ignored | **STILL TRUE** | `game/tools/bot_run.gd:1153-1175` parses only `--dodge --log --log-dir --runs --seed-base --max-level --trace` (+ `=` forms); nothing rejects an unknown flag. A3's own `--seeds 0:100 --enemy kiwi_cat` are also unknown flags. FLEET_PACK.md is unchanged since the first audit (`git diff b0c6b3d..HEAD -- FLEET_PACK.md` is empty). |
| D2 | the export fails on a clean checkout because `build/` is gitignored | **STILL TRUE** | `ls build` → "No such file or directory" on this worktree; `mkdir -p build` first, then the export exits 0. |
| D3 | RUNLOG.md did not exist | **FIXED** | RUNLOG.md exists (392 lines). New paperwork gap: **the KIWI-SLOW merge (`64e3332`) has no MERGED-GREEN line** — the last line is 01:36Z "Still running … KIWI-SLOW", although KIWI-SLOW is on `main`. That is an R1 gap (§2 A16). |
| D4 | the owner's VOIDWRAP_CANON list is not in the repository | **STILL TRUE** | `grep -rln VOIDWRAP_CANON --include=*.md` hits only AUDIT.md, DESIGN.md:3, FLEET_PACK.md:352 and RUNLOG.md — references, never the list. §3 audits against DESIGN.md's `[CANON]` markers, as before. |
| D5 | *(new)* Vulkan reports `VK_ERROR_SURFACE_LOST_KHR` on this machine in this session | **ENVIRONMENT, not the build** | Both the exported exe and the editor binary print `ERROR: Couldn't get Vulkan surface capabilities (VkResult error -13)` every frame when windowed (exe: 120,002 stderr lines in 60 s; `perf_probe.gd`: 721). The same exe on `--rendering-driver d3d12` renders the menu with **0** stderr lines. The first audit rendered the menu on Vulkan on the same machine. A1's visual check and A13's frame times are therefore taken on D3D12; the Vulkan frame times are reported but not used (frames whose swap chain is lost are not presented, so their timings prove nothing). |

---

## 1. Every §4 command, its real final line, its real exit code

| # | command (as run) | real final line | exit |
|---|---|---|---|
| 1 | `godot --headless --path game --script res://tests/run_all.gd` | `TESTS 58 passed 0 failed` (214 s wall) | 0 |
| 2 | `godot --headless --path game --script res://tests/test_terrain_parity.gd -- <abs>\terrain_ref\gallery.json` | `PARITY 56/56 OK` (line above: `GALLERY_PIN 16/16 pinned-gallery records match`) | 0 |
| 3 | `python terrain_ref/test_validate.py` | `SELFTEST 15/15` then `TESTS OK` | 0 |
| 4 | `python terrain_ref/gallery.py --check` | `GALLERY 16/16 OK` | 0 |
| 5 | `python terrain_ref/validate.py --selftest` | `SELFTEST 15/15` | 0 |
| 6 | `python terrain_ref/validate.py --seeds 0:5000` | `total wall time 194.9 s` (32 `PASS` / 0 `FAIL` lines above it) | 0 |
| 7 | `godot --headless --path game --script res://tools/bot_run.gd -- --dodge --runs 100 --seed-base 0 --max-level 2` (the working form of §4's bot line, at A3's 100 seeds — D1) | `BOT_RUN OK (100 runs, deterministic seed set seed_base=0..99)` (2,097 s wall) | 0 |
| 8 | `mkdir -p build` then `godot --headless --path game --export-release "Windows Desktop" ../build/voidwrap_run.exe` | `[ DONE ] savepack` | 0 |
| 9 | `powershell -NoProfile -File tools/gate.ps1 > out/gate1.log` | `GATE OK (9 ran, 0 skipped, 377 s)` | 0 |

Notes on the numbers:

- **The gate: `GATE OK (9 ran, 0 skipped, 377 s)`, TESTS line `TESTS 58 passed 0 failed`.** Summary block:
  `OK python oracle checks (TESTS OK, SELFTEST 15/15, GALLERY 16/16 OK)`, `OK terrain parity (PARITY 56/56 OK)`,
  `OK run_all (TESTS 58 passed 0 failed)`, `OK boundary scan`, `OK content schema`, `OK drop-in fixture`,
  `OK replay determinism`, `OK sprite validator` (`SPRITES OK 515 checks over 12 sprites.json`),
  `OK fog readability` (`FOGCHECK OK (550 checks over 5 biomes)`). 377 s includes the cold `--import` of a
  fresh worktree and ran beside FIX-A3's two bot processes. The first audit's `WARN resource import did not
  finish cleanly` did **not** appear this time.
- **Gate margin, a risk rather than a failure:** `run_all` alone takes **214 s** against the gate's
  **300 s** step-3 timeout (`tools/gate.ps1 -StepTimeoutSec 300`). RUNLOG 23:21Z records one red gate at
  320 s under contention, and D-FIX-A4-1 shortened A4's recorded runs to 1,000 ticks so that `run_all`
  would fit the timeout (§9.1).
- **The 5,000-seed harness: 32 PASS / 0 FAIL, 194.9 s.** `grep -c '^PASS '` = 32, `grep -c '^FAIL '` = 0.
- **`run_all` prints `TESTS 58 passed 0 failed`** (55 at the first audit; the 3 new files are
  `test_curse_requires.gd`, `test_app_flow.gd`, `test_menu.gd`). Engine teardown still prints
  `WARNING: 31 ObjectDB instances were leaked at exit` and `ERROR: 8 resources still in use at exit`; the
  exit code is 0.
- **The export produces `build/voidwrap_run.exe`, 117,997,952 bytes**, self-contained.

### 1.1 A1's smoke run

A1's "measured by" column: *"T-056 smoke run: process alive 10 s, exit code 0 on `--quit-after 600`"*.

| run | wall clock | exit | alive at 10 s |
|---|---|---|---|
| `voidwrap_run.exe --quit-after 600` | 6,132 ms | 0 | n/a (ended at 6.1 s) |
| `voidwrap_run.exe --quit-after 6000` | 9,084 ms | 0 | n/a (ended at 9.1 s) |
| `voidwrap_run.exe --quit-after 20000` | 23,478 ms | 0 | **yes** (window title `VOIDWRAP RUN`) |
| `voidwrap_run.exe --quit-after 20000 --rendering-driver d3d12` | 16,898 ms | 0 | **yes** |

The exe now takes about 5.8 s to start (the menu is a 3D island scene with the 12 enemies, D-MENU-2/3),
then runs at about 1,800 fps, so `--quit-after 600` lasts 6.1 s. **The literal "alive 10 s on
`--quit-after 600`" is still not achievable** — this time because of the frame count, not the start
time. The 10 s liveness rests on the `--quit-after 20000` runs (alive at 10 s, exit 0). Nothing was faked.

**"Starts to the menu" is visually verified on D3D12** (`out/exe_menu_d3d12.png`, captured at 10 s):
window `VOIDWRAP RUN`, the wordmark VOIDWRAP / RUN, the tagline "collect every black gift. mind the
void.", the entries **PLAY / HOW TO PLAY / QUIT**, the 3D island with the enemy roster, "v0.1.0-alpha.1
pre-release", and the disclaimer footer. **On the default Vulkan driver the window stayed blank**
(`out/exe_menu.png` at 8 s, `out/exe_menu_18.png` at 18 s) because of D5. The editor binary fails the
same way, so the cause is this machine's Vulkan state today, not the build. It is stated here because
the default-driver render could not be confirmed in this session.

---

## 2. A1 to A16, one by one

Verdicts: **PASS** = the criterion's own number is met and a test or a command proves it. **PARTIAL** = the
behaviour exists and is tested, but the criterion's stated number, scope or proof is not met.
**FAIL** = the criterion's number is not met.

### A1 — native export, starts to the menu — **PASS** (unchanged; two stated limitations)

- Export: `[ DONE ] savepack`, exit **0**; `build/voidwrap_run.exe`, **117,997,952 bytes**, a native Godot
  export (stdout: `Godot Engine v4.7.2.stable.official.ed1daf0bf`, `D3D12 12_0 - Forward+ - Using Device #0: AMD - a discrete AMD GPU`, or the Vulkan 1.4.359 line on the default driver). No browser or Electron wrapper.
- Smoke: `--quit-after 600` → exit **0**, 6.13 s; `--quit-after 20000` → exit **0**, alive at 10 s, 23.48 s.
- Menu: visually confirmed on D3D12 (§1.1). `game/project.godot:7` `run/main_scene="res://app/app.tscn"`;
  `app/app.gd` starts in `MENU`.
- **Limitations:** (1) 600 frames last 6.1 s, not 10 s; (2) the default-Vulkan render could not be shown
  in this session (D5, environmental).
- Proof: `game/export_presets.cfg`, `game/app/app.tscn`, `game/app/app.gd`, `game/app/menu.gd`.

### A2 — terrain: 5,000-seed harness + GDScript parity — **PASS** (unchanged)

- `python terrain_ref/validate.py --seeds 0:5000` → **32 PASS / 0 FAIL**, `total wall time 194.9 s`, exit **0**.
  Every H check `failures=0/5000` (H1–H23); D1 max dev 0.00576 ≤ 0.01000; D2 300/300; D3 5000; D4 0.3935 ≤ 0.5
  and 0 ≤ 4; D5 0 ≤ 4; D6 0.0179 ≤ 0.1; D7 bucket means strictly increasing (80.53 → 215.555); D8 10.374 ≤ 50 and
  75.0 ≤ 80; D9 83.0 ≤ 250 and 350.5 ≤ 2000.
- `test_terrain_parity.gd` → `GALLERY_PIN 16/16`, `PARITY 56/56 OK`, exit **0** (16 pinned gallery records + 40 parity cases).
- Proof: `terrain_ref/validate.py`, `game/tests/test_terrain_parity.gd`.

### A3 — the bot completes level 1 in ≥ 95 of 100 seeds, median ≤ 120 s — **FAIL** (unchanged: was FAIL at 1/10, now FAIL at 19/100 on the audited tree and 82/100 after FIX-A3 merged)

- **A3's literal command cannot be run** (D1): `bot_run.gd` has no `--seeds` and no `--enemy` flag, and
  silently ignores both. The working form is
  `godot --headless --path game --script res://tools/bot_run.gd -- --dodge --runs 100 --seed-base 0 --max-level 2`
  → `BOT_RUN OK (100 runs, deterministic seed set seed_base=0..99)`, exit **0**, **2,097 s** wall
  (`out/a3_100.log`). It ran on the `main` bot (FIX-A3's bot is not on `main`) with the slow kiwi cat of
  D-KIWI-SLOW-1.
- **Result: 19 of 100 seeds complete level 1** (`entered=2`): seeds 2, 10, 13, 16, 20, 40, 52, 55, 59, 65,
  66, 68, 70, 73, 86, 91, 92, 94, 96. **That is 19%, against a required 95%.**
- **The 81 that did not complete level 1 all died on it:** `D-VOID` **60**, `D-KIWI` **14**, `D-COIL` **7**.
  Across all 100 runs, end codes are `D-VOID` 68, `D-KIWI` 21, `D-COIL` 8, and 3 runs ended `complete`
  (seeds 13, 40, 65 entered level 2 and stopped at `--max-level 2`). By class: dasher 7/31, athletic 8/34,
  glider 4/35 complete level 1.
- **The median-time half (≤ 120 s) was not measured.** `bot_run.gd` prints a run's end tick, not its
  level-1 clear tick. With 19/100 the criterion fails on the completion rate alone.
- **The "kiwi cat present" precondition cannot be forced.** Level 1's enemy is one seeded-random vote from
  `starter_pool ["kiwi_cat", "coil", "thicc_ben", "seal"]` (`game/data/offering_schedule.json`), and the
  bot has no `--enemy`. The kiwi cat was present on at least the 21 seeds it killed on. The 100 seeds are
  therefore a mixed-enemy sample, not the kiwi-only sample A3 describes.
- **Against the first audit:** seeds 0-9 give the same 1 of 10 as before (only seed 2 completes; seed 0
  `D-VOID` tick 1728 and seed 3 `D-COIL` tick 2548 are identical). The first audit never finished its
  extension past 10 seeds, so the 19/100 cannot be split into "KIWI-SLOW's effect" and "the first 10 seeds
  were unlucky". **The slow cat did not remove kiwi deaths: 14 of the 81 level-1 deaths are still `D-KIWI`.**
  Terrain is still the main killer: 60 of the 81 (74%) are `D-VOID`.
- Still parked: PARKED.md #4 (T-026). FIX-A3 (edge discipline + charge-aware routing; RUNLOG 00:56Z
  reports 5/10 on its own 10-seed probe) is in flight on its own branch and is not measured here.
- Proof: `game/tools/bot_run.gd`, `game/tests/test_bot_run.gd`, `out/a3_100.log`.
- **Post-audit addendum (orchestrator, after this audit was written): FIX-A3 merged as `b9c6470` and the
  number is now 82 of 100, still FAIL.** The audit above measured the tree without FIX-A3. FIX-A3's own
  re-measure on the merged tree reports **82/100 seeds complete level 1** (up from 56 with the fast kiwi
  cat and 1/10 at the first audit's baseline), median level-1 sim time **43.4 s** over the 82 completions
  against the 120 s criterion, and 18 failures: `D-KIWI` 8, `D-VOID` 4, stuck 4, timeout 1, `D-COIL` 1.
  Nothing was weakened, no threshold moved, no criterion edited and no enemy number touched; the kiwi
  values in that sweep are exactly D-KIWI-SLOW-1's (base 3.0, ceiling 0.40, burst 0.55). The verdict does
  not change: **82 < 95, so A3 is FAIL and the alpha tag is not created.** PARKED.md row 24 carries the
  numbers and the next competence lever (a purer intercept prediction of the landing tile). The median
  half of the criterion is now measured and met; only the completion rate fails.

### A4 — replay determinism: 10 recorded bot runs, identical hashes at every checkpoint — **PASS** (was PARTIAL, now PASS, because the test now records and replays ten bot runs)

- `game/tests/test_replay.gd` now has, besides the random-input run, `BOT_SEEDS := [101, 202, 303, 404, 505, 606, 707, 808, 909, 1001]`
  (line 43), duplicate-seed guard, and for each seed a **record** pass (the bot plays through `bot_run.gd`'s
  `play_run(..., rec)` on the real sim surface) and a **replay** pass (the recorded input stream fed
  tick-for-tick, the bot's brain bypassed), comparing the `state_hash.gd` hash at every 60th tick.
- Gate log, verbatim:

```
REPLAY 60 checkpoints identical across 2 replays
REPLAY-BOT seed=101 outcome=cut ticks=1000 checkpoints=16 identical record/replay
  … (seeds 202 … 909 identical lines) …
REPLAY-BOT seed=1001 outcome=cut ticks=1000 checkpoints=16 identical record/replay
REPLAY-BOT 10 recorded bot runs (cap 1000 ticks), 160 checkpoints identical between record and replay
```

- **10 runs, 160 checkpoints, all identical.** The test fails on a duplicate seed, an empty recording, a
  run with no checkpoint, a checkpoint-count mismatch, a tick-count mismatch, an outcome mismatch, or any
  differing hash (`test_replay.gd:107-152`). The random-input run keeps its perturbation proof (one input
  changed at tick 1201 → every later checkpoint must differ).
- **Stated, not hidden:** each recorded run is capped at **1,000 ticks** (16.7 s of sim), and on `main`
  today **all ten end at the cap** (`outcome=cut`), so no recorded bot run reaches a death, the gold phase or
  a beacon entry. The criterion names no run length; D-FIX-A4-1 `[CONTESTABLE]` records why 1,000 (a full
  3,600-tick recording pushed `run_all` past the gate's 300 s timeout) and asks the owner to rule. See §9.1.
- Proof: `game/tests/test_replay.gd`, `game/tools/bot_run.gd`, `game/sim/state_hash.gd`.

### A5 — black→gold at the same slot ids/positions on 100 seeds; beacon CLOSED→OPEN exactly then — **PASS** (unchanged)

- `test_gifts.gd` (`const SEED_COUNT := 100`, `_test_a5_100_seeds`) passes in `run_all` (`PASS res://tests/test_gifts.gd`).
- Proof: `game/tests/test_gifts.gd`, `game/sim/gifts.gd`, `game/sim/beacon.gd`.

### A6 — tripmines: occ-only, 0.9 u any-height contact, the fixed four-step ladder, deterministic roll, ±2 points at 1/2/3 stacks — **PASS** (unchanged)

- `test_mines.gd` passes; gate log line: `MINE determinism: 1000 seeds, same seed -> same outcome`. Since the
  first audit, its only change is one line reading the killer name through `DeathScript.killer_for("D-MINE")`
  instead of the deleted `CODES` map; the asserted value `"gift Larper (Tripmine)"` is unchanged.
- Proof: `game/tests/test_mines.gd`, `game/sim/mines.gd`.

### A7 — all 12 enemies: timings within ±1 tick, contact kills except thicc ben and the three non-killing effects, Last Light spent, sprites.json with body_rect, hitbox padding test — **PASS** (unchanged)

- All twelve `test_enemy_*.gd` and `test_hitbox.gd` pass in `run_all`.
- **The kiwi cat changed numbers, not timings.** D-KIWI-SLOW-1 (FINAL, owner ruling 2026-11-17) moves
  `content/enemies/kiwi_cat/enemy.json:16-18` to `base_speed 3.0`, `pursuit_ceiling 0.4`, `burst_ceiling 0.55`.
  `test_enemy_kiwi_cat.gd` is re-pinned to the new numbers with the **same tolerances** (`1e-9` on speeds,
  `1e-6` on per-tick distance): h_speed 3.0, never above 3.6, burst peak exactly 4.8 (3.0 × 1.6) and capped at
  exactly 4.95 under overtime, closing speed 12.0. The meow cadence and contact kill are untouched.
  **This is a spec-error correction, not a threshold move:** ENEMIES.md:56's frozen sentence is "slowly
  follow the player, death on contact", and the old 5.6 u/s was 62% of the player's 9.0 u/s run. It is an
  enemy behaviour number, not an acceptance threshold, and the owner ruled it FINAL. ENEMIES.md is unchanged
  (`git diff b0c6b3d..HEAD -- ENEMIES.md` is empty); DESIGN.md:280 now reads `kiwi cat | 3.0 | 0.40 | 3.6`.
- The first audit's wording note still holds: `address_me` has no contact kill by D-065 FINAL (PARKED #10).
- Proof: the twelve `game/tests/test_enemy_*.gd`, `game/tests/test_hitbox.gd`, `game/content/enemies/*/enemy.json`.

### A8 — sprite validator: alpha 0 in all four corners, no opaque 1-px border, fog contrast ≥ 3.0 at 40 u — **PASS** (unchanged)

- Gate step 8: `SPRITES OK 515 checks over 12 sprites.json`; gate step 9: `FOGCHECK OK (550 checks over 5 biomes)`.
- The art wave is real art: 102 PNGs under `game/content/enemies/*/sprites/`, derived from the 17 images in
  `assets_src/enemies/`. My own pixel census (PIL, opaque pixels ≥ 50% alpha) finds **no magenta/black
  checker frame anywhere**, and only five magenta-dominant frames: claude's `plushie_00..02` (the
  documented TBD, §9.6), and toucher's `floor_00` / `floor_04`, which are 4-colour posterised derivations of
  `assets_src/enemies/glitchedground.jpeg` — a magenta glitch texture by design, not a placeholder.
- Proof: `game/tools/validate_sprites.gd`, `game/tools/fog_check.gd`.

### A9 — lobby: physical scene, F-hold 0.35 s altars, schedule from data/offering_schedule.json, mandatory bays gate the Descent Gate — **PASS** (unchanged; see the reachability finding)

- `test_lobby.gd` passes in `run_all`.
- **Finding, not a criterion miss:** the lobby is not reachable in the shipped app. `app/app.gd` runs
  MENU → LOADING → WORLD (level 1) and back to MENU on ESC; nothing under `game/app/` instantiates the
  antechamber, and `app/world.gd` never completes a level (§11, finding 2). A9 is measured by
  `test_lobby.gd`, and that test passes.
- Proof: `game/tests/test_lobby.gd`, `game/view/lobby/antechamber.gd`, `game/sim/intermission.gd`.

### A10 — 46 curses, 36 upgrades, 12 enemies, 5 biomes load and pass schema; level-1 shop pool is exactly Paycheck, More, Yearn for Speed — **PASS** (unchanged)

- `test_content.gd` passes; gate step 5 `OK content schema`. On disk: `content/curses/*.json` = 46,
  `upgrades/*.json` = 36, `biomes/*.json` = 5, `enemies/` = 12 folders (plus `.gitkeep`).
- New since the first audit: `test_curse_requires.gd` asserts that every curse's `requires_enemy` names a
  real enemy id, and `twin_fangs.json`'s `"gin_ichimaru"` is corrected to `"gin"` (D-FIX-A14-3), so the
  first audit's unreachable curse is now reachable.
- Proof: `game/tests/test_content.gd`, `game/tests/test_curse_requires.gd`, `game/core/schemas/*.json`.

### A11 — economy audit: ≥ 1 item affordable in ≥ 80% of shops, all 3 in ≤ 30%, 1,000 runs to level 30 — **PASS** (unchanged)

- `godot --headless --path game --script res://tools/economy_audit.gd` → `AUDIT OK (runs=1000 shops/run=15 afford1=99.5% afford3=29.3% purchases=23.89 cautious=8.25)`, exit **0** — the same numbers as the first audit.
- afford3 29.3% ≤ 30% still has a **0.7-point** margin.
- Proof: `game/tools/economy_audit.gd`.

### A12 — feel budget: loading ≥ 5.0 s and ≤ 8 s, gate→level ≤ 2.0 s, death→run-over ≤ 2.0 s, void fall→respawn ≤ 0.8 s, generate+mesh L30 ≤ 1.5 s — **PASS** (unchanged verdict; it now rests on an owner FINAL, recorded as D-T099R-1)

- `godot --headless --path game --script res://tools/feel_probe.gd` → `T-061 RESULT: OK`, exit **0**:

```
PASS loading_screen_hold 5.000 s >= 5.0 s (first launch)
PASS loading_screen_total_l30 5.000 s <= 8.0 s (first launch: hold 5.0 + build 0.178 s)
PASS loading_restart_hold 2.000 s >= 2.0 s (restart, never less)
PASS loading_restart_total_l30 2.000 s <= 2.0 s (restart, never more: a fast load never waits past it; build 0.178 s)
PASS gate_to_level 0.178 s <= 2.0 s (gen+world+mesh+sim state, level 30)
PASS death_to_run_over 0.0042 s <= 2.0 s (kill tick -> screen_data + run-over build; kiwi cat)
PASS void_fall_to_respawn 0.800 s <= 0.80 s (void_fall -> respawn; landed on 1,1,1)
PASS generate_mesh_l30 0.162 s <= 1.5 s (voidgen + level_mesher, seed 7)
```

- **Wall clock in the real app** (a scratchpad SceneTree script, not committed: it instantiates
  `res://app/app.tscn`, lets the menu idle 120 frames, calls `start_run(1)`, times MENU→WORLD, returns to the
  menu and starts again): two runs gave **first launch 5,000 ms and 5,004 ms; restart 2,006 ms and
  2,004 ms**. The orchestrator's integration fix (RUNLOG 23:47Z: the app no longer double-ticks the screen)
  is real: `app/app.gd:54-58` does not call `advance()`.
  - Caveat, measured: when the run was started on the menu's **first** frame, first launch measured
    **4,859 ms**. The screen's own `_process` counts the delta of the frame it was created in, including
    time that passed before the screen existed. In steady play that is one frame (6.9 ms here); after a
    hitch it is more. This is a small defect in `loading_screen.gd`, not an A12 miss. It is reported and
    was not fixed.
- **The judgment call (D-T099R-1):** A12's text, from DESIGN.md §2 `[CANON]`, says "loading screen ≥ 5.0 s".
  The owner's newer FINAL ruling D-LOAD-5 says first launch 5.0 s and **every restart exactly 2.0 s**.
  **Read literally, A12 fails on restarts (2.0 s < 5.0 s).** The verdict PASS takes the FINAL ruling as
  amending the criterion for restarts — the same way the first audit took D-065 FINAL over A7's
  "every body contact kills" wording. The first-launch rows were kept exactly and nothing was loosened.
  PARKED.md #22 records the contradiction and asks the owner to update DESIGN.md §2/§14 and the A12 text.
  **If the owner does not accept that D-LOAD-5 amends A12, A12 is PARTIAL.**
- `void_fall_to_respawn` is still **exactly at the bound** (0.800 vs 0.80).
- Proof: `game/tools/feel_probe.gd`, `game/app/loading_screen.gd`, `game/app/app.gd`, `game/tests/test_loading.gd`.

### A13 — performance: level 30, 22 enemies, 600 frames, p99 ≤ 16.6 ms windowed 1080p, mean sim tick ≤ 2.0 ms — **PASS** (unchanged)

- `godot --path game --rendering-driver d3d12 --script res://tools/perf_probe.gd` (a real window), exit **0**, 0 error lines:

```
D3D12 12_0 - Forward+ - Using Device #0: AMD - a discrete AMD GPU
PASS p99_frame_time 1.11 ms <= 16.6 ms (windowed 1080p, v-sync off; n=600)
PASS mean_sim_tick 0.751 ms <= 2.0 ms (ctl+enemy runtime step; 22 enemy rows)
T-061 RESULT: OK
```

- The same probe on the default Vulkan driver printed `PASS p99_frame_time 1.22 ms` / `PASS mean_sim_tick 0.797 ms`
  **with 721 swap-chain errors** (D5). Those frames were not presented, so that run is **not** used as evidence.
- The FIX-A3 bot sweep was running on the same CPU during both runs.
- Proof: `game/tools/perf_probe.gd`.

### A14 — drop-in proof: fixture enemy/curse/upgrade/biome copied into content/ are offered and work with zero core edits; boundary scan clean — **PASS** (was PARTIAL, now PASS, because the boundary scan is real and the core is clean)

- `test_dropin.gd` passes (gate step 6 `OK drop-in fixture`), unchanged in scope: four fixtures copied in,
  registered and functional, one corrupted file refused with its name, all removed.
- **The scan is no longer vacuous.** `game/tests/test_boundaries.gd` derives its ids from the content tree at
  run time (folder names under `res://content/enemies/`, `*.json` names under curses/upgrades/biomes — 99 ids)
  and fails if none are found (line 73). It scans every `.gd` **and `.json`** under `res://terrain`,
  `res://sim`, `res://core` (including `core/schemas/`) and `res://app` (lines 39-40).
- **My independent grep agrees:** the same 99 ids, matched whole-word against every `.gd`/`.json` under
  `game/terrain`, `game/sim`, `game/core`, `game/app` → **0 files with a hit**. The first audit's four
  violations are gone: `curse.schema.json`'s 12-id enum is replaced by a pattern plus a registry check
  (D-FIX-A14-3); `sim/death.gd` reads names through the new `core/roster.gd`; `"cartographer"` →
  `"footprint_map"` and `"updraft"` → `"updraft_rise"` (D-FIX-A14-2).
- **Red-proof, run by me:** an untracked temp file `game/app/zz_t099r_plant.gd` naming `kiwi_cat` and
  `twin_fangs`, with `test_boundaries.gd` run alone → `BOUNDARY_PROOF failures=2` (both ids named, with the
  file); the file deleted → `failures=0`. `git status --porcelain` was empty afterwards.
- The view layer (FLEET_PACK §3: "view and app may use everything"): the first audit's three roster-wide
  files are clean (`run_over.gd`, `danger_text.gd` and `fog_env.gd` read `core/roster.gd`; 0 id hits).
  The view files that still name an id are per-content files: the 12 per-enemy `*_view.gd` and audio
  files, `hud/cartographer_map.gd` (the Cartographer upgrade's map), `vfx/pocket_ring.gd` (Pocket Beacon),
  `vfx/coil_telegraph.gd` (a comment), `tripmine_view.gd` (a `method_acting` parameter name), and
  `hud/icon_rows.gd` (the English word "more" in a comment).
- **Remaining limit, stated:** `test_dropin.gd` still proves that a fixture *registers and works in the
  sim*, not that it *renders*. Not measured here.
- Proof: `game/tests/test_dropin.gd`, `game/tests/test_boundaries.gd`, `game/tests/test_curse_requires.gd`, `game/core/roster.gd`.

### A15 — README and the lobby About plaque contain the disclaimer verbatim — **PASS** (was PARTIAL, now PASS, because the plaque is byte-identical and the test reads it)

- `game/view/lobby/antechamber.gd:65` `const DISCLAIMER` is, measured byte by byte (Python, UTF-8):
  206 characters / 208 bytes, exactly one U+2014 em dash, **equal** to the T-001 string in FLEET_PACK.md and
  **a substring of README.md** (README.md:8, inside `**…**` bold).
- `test_disclaimer.gd` now preloads `antechamber.gd`, asserts `DISCLAIMER == T001_DISCLAIMER` byte-identical
  (line 67) and asserts the rendered plaque text contains it (line 69). It passes in `run_all`.
- **Finding, not a criterion miss:** in the shipped app nobody sees the plaque, because the lobby is never
  reached (A9). What the player does see is the menu footer, which renders `menu.gd:33` `ABOUT_DISCLAIMER`
  — the **ENEMIES.md** paragraph, a different wording (PARKED #2, D-MENU-1) — visible in
  `out/exe_menu_d3d12.png`. So ENEMIES.md's hard rule (disclaimer on an about screen) is met by the footer,
  and A15's T-001 string is met in code and tests but not on screen.
- Proof: `game/tests/test_disclaimer.gd`, `README.md`, `game/view/lobby/antechamber.gd`, `game/app/menu.gd`.

### A16 — TBD.md lists every TBD substitution; 0 tickets stalled on a refusal — **PASS** (unchanged; the documentation defects are not fixed)

- The only `"tbd": true` sprites.json is `claude` (checked in all 12). Its three TBD frames
  (`plushie_00..02`, the clawd Crab plushie source was never fetched) are listed in TBD.md (§1 row 11).
- **0 tickets stalled on a refusal.**
- **Still not fixed, reported again:**
  1. TBD.md:29's heading still reads `## 1. The 17 enemy images - 4 MISSING (…; only the clawd Crab plushie and the four remaining source rows are still TBD)`, contradicting its own table (every row REAL except the plushie).
  2. The body still says "the other fourteen remain MISSING -> TBD", and now also carries duplicated,
     out-of-order sentence fragments (lines starting `body_rect).`, `change.`, `unchanged, and fog contrast …`), the leftovers of several workers editing the same paragraph.
  3. TBD.md has two sections numbered `## 1.` and two numbered `## 2.`.
- **New paperwork gaps (R1):** RUNLOG.md has no MERGED-GREEN line for KIWI-SLOW (on `main` as `64e3332`).
  PARKED.md #20 (the loading screen's double tick) still reads as open, though RUNLOG 23:47Z and
  `app/app.gd:55-58` show it fixed. None of tonight's new tickets (FIX-A4, FIX-A14, FIX-A15, FIX-BILLBOARD,
  FIX-APP-BOUNDARY, APP-FLOW, MENU, LOADING, the 12 ART tickets, KIWI-SLOW) has a
  `tickets/<id>.response.md`; their records are RUNLOG lines and DECISIONS entries. The 51 response files
  are the same as at the first audit, so T-053 and T-060 still have none.
- Proof: `TBD.md`, `game/content/enemies/*/sprites.json`, `RUNLOG.md`, `PARKED.md`.

---

## 3. The canon table

**The owner's VOIDWRAP_CANON list is still not in this repository** (D4). The rows are DESIGN.md's
`[CANON]` markers plus the ENEMIES.md hard rules, as in the first audit. All cited test files exist and pass
in `run_all` (`TESTS 58 passed 0 failed`). Rows changed since the first audit are marked **(changed)**.

| # | canon bullet (source) | file that implements it | test that proves it |
|---|---|---|---|
| C1 **(changed)** | Loading screen on initial load and on run start, ≥ 5.0 s, ≤ 8 s total at L30 (DESIGN §2, §14) — **amended by D-LOAD-5 FINAL: first launch 5.0 s, every restart exactly 2.0 s**; the contradiction is PARKED #22 | `game/app/loading_screen.gd`, `game/app/app.gd` | `test_loading.gd`; `feel_probe.gd` rows `loading_screen_hold 5.000 s`, `loading_restart_hold 2.000 s`; real-app wall clock 5,000/5,004 ms and 2,006/2,004 ms (§2 A12) |
| C2 | Core loop: spawn on the dais, beacon CLOSED; collect every black gift; the last real black gift opens the beacon; gold at the same slots; entering the beacon completes the level; no timer ends a level (DESIGN §3) | `game/sim/gifts.gd`, `game/sim/beacon.gd` | `test_gifts.gd` (100 seeds) — **in the sim only: `app/world.gd` does not tick gifts or the beacon (D-APPFLOW-5), so the shipped app cannot play this loop (§11 finding 2)** |
| C3 | Hazards inherit validated gift positions (DESIGN §3.3) | `game/sim/mines.gd` + `terrain_ref/voidgen.py` stream MINE | `test_mines.gd` |
| C4 | Dasher: dash 6 u in 0.20 s, one charge, 3.0 s regen (DESIGN §4) | `game/sim/controller.gd` | `test_classes.gd` |
| C5 | Athletic: +15% run speed; speed upgrades ×1.5; double-jump ×1.3 (DESIGN §4) | `game/sim/controller.gd`, `game/sim/upgrades.gd` | `test_classes.gd` |
| C6 | Per-level pools (DESIGN §8) | `game/data/upgrade_pools.json`, `game/sim/offers.gd` | `test_content.gd`, `test_offers.gd` |
| C7 | Affordability filter `price ≤ max(2 × purse, 80)` (DESIGN §8) | `game/sim/offers.gd:31` (`AFFORD_FLOOR := 80`) | `test_offers.gd` |
| C8 | Level-1 pool exactly Paycheck, More, Yearn for Speed (DESIGN §8) | `game/data/upgrade_pools.json` | `test_content.gd` |
| C9 | Paycheck +25 g per stack (DESIGN §8) | `game/sim/upgrades.gd` | `test_upgrades_script.gd` |
| C10 | More +10% gift yield per stack (DESIGN §8) | `game/sim/upgrades.gd` | `test_upgrades_script.gd` |
| C11 | Yearn for Speed +10% run speed per stack (DESIGN §8) | `game/sim/upgrades.gd` | `test_upgrades_script.gd` |
| C12 | Defuse Kit +20%/stack, cap 60%, deterministic roll (DESIGN §8, §3.3) | `game/sim/mines.gd` | `test_mines.gd` |
| C13 | Subspacial Barrier: 1 shield per level, after the defuse roll (DESIGN §8) | `game/sim/mines.gd` | `test_mines.gd` |
| C14 | Radar Module: Mines, 14 u pink outline (DESIGN §8) | `game/view/tripmine_view.gd:70` (`RADAR_RANGE := 14.0`) | `test_vfx.gd` |
| C15 | Counter-play map: tripmines ← Defuse Kit / Barrier / Last Light (DESIGN §8) | `game/sim/mines.gd` | `test_mines.gd` |
| C16 | The intermission lobby is a physical place (DESIGN §11) | `game/view/lobby/antechamber.gd` | `test_lobby.gd` — **not reachable from the shipped app (§2 A9)** |
| C17 | Void charges: 2 held, cap 2, a fall spends 1, beacon restores 1 (DESIGN §3.1) | `game/sim/controller.gd`, `game/sim/beacon.gd` | `test_charges.gd` |
| C18 | Last Light (DESIGN §3.1) | `game/sim/controller.gd` | `test_last_light.gd` |
| C19 **(changed)** | BILLBOARDING: every PNG enemy faces the player (ENEMIES.md hard rule) — **and now stands on its feet** | `game/view/billboard.gd` (sign fixed, D-FIX-BILLBOARD-1) | `test_billboard.gd` incl. `_feet_all_enemies`: every frame of every enemy, body bottom on the node origin within 1e-3 u (red on the old sign: 99 failures, per D-FIX-BILLBOARD-1) |
| C20 | HITBOXES: body only, never padding (ENEMIES.md hard rule) | `game/sim/enemy_runtime.gd` + per-frame `body_rect` | `test_hitbox.gd` |
| C21 | TRANSPARENCY (ENEMIES.md hard rule) | `game/tools/validate_sprites.gd` | gate: `SPRITES OK 515 checks over 12 sprites.json` |
| C22 **(changed)** | DISCLAIMER in README + about screen (ENEMIES.md hard rule) | `README.md`, `game/app/menu.gd` (footer), `game/view/lobby/antechamber.gd` (plaque) | `test_disclaimer.gd` — now covers README (both wordings), the menu `ABOUT_DISCLAIMER`, and the plaque byte-identical |
| C23 | TBD FALLBACK (ENEMIES.md hard rule) | `game/tools/make_tbd_png.gd`, `TBD.md` | TBD.md; `claude` the one live `"tbd": true` |
| C24 **(changed)** | Seed in, world out: deterministic, input-driven sim (DESIGN §1.6, §13) | `game/sim/state_hash.gd`, `game/sim/sim.gd` | `test_replay.gd`: 60 checkpoints + perturbation, **plus 10 recorded bot runs, 160 checkpoints identical** |
| C25 **(changed)** | Drop-in content without touching the core (DESIGN §1.5) | `game/core/registry.gd`, `game/core/content_api.gd`, `game/core/roster.gd` | `test_dropin.gd` + `test_boundaries.gd` (now real, red-proven §2 A14) |

**MISSING: none.** C22 and C25, which the first audit marked weaker than claimed, are now proven. C2 and
C16 are proven in the sim and the lobby scene, but **the shipped app does not reach either** (§11 finding 2).

---

## 4. The 12-enemy roster, name by name

Re-checked against `game/content/enemies/*/enemy.json` `name` and `sprites.json` `tbd`, on this commit.

| # | ENEMIES.md name | content folder id | `enemy.json` `name` | `sprites.json` `tbd` | verdict |
|---|---|---|---|---|---|
| 1 | kiwi cat | `kiwi_cat` | kiwi cat | false | MATCH (base_speed 3.0, D-KIWI-SLOW-1) |
| 2 | coil | `coil` | coil | false | MATCH |
| 3 | thicc ben | `thicc_ben` | thicc ben | false | MATCH |
| 4 | Isagi | `isagi` | Isagi | false | MATCH |
| 5 | nuke | `nuke` | nuke | false | MATCH |
| 6 | YOU?! | `you` | YOU?! | false | MATCH |
| 7 | gift Larper | `gift_larper` | gift Larper | false | MATCH |
| 8 | toucher | `toucher` | toucher | false | MATCH |
| 9 | seal | `seal` | seal | false | MATCH (new source `babehseal.png`, owner ruling, RUNLOG 23:45Z) |
| 10 | address me | `address_me` | address me | false | MATCH (keeps the office photo, D-ART-ADDRESS_ME-5) |
| 11 | Claude | `claude` | Claude | **true** | MATCH, documented TBD (plushie frames only) |
| 12 | gin ichimaru | `gin` | gin ichimaru | false | MATCH |

**No enemy was silently renamed.** **The first audit's id inconsistency is fixed:** `twin_fangs.json`
now has `"requires_enemy": "gin"`, and `test_curse_requires.gd` asserts every curse names a real enemy id.

**Carried caveat (D-FIX-BILLBOARD-1, not re-measured here):** `nuke/sprites.json` has `world_height: null`,
so its billboard computes scale 0 and the nuke sprite is invisible until the owner rules on its height.

---

## 5. Boundary result: no core file names a content id — **CLEAN** (was FAIL)

- **Gate step 4:** `OK boundary scan (ran in run_all: game/tests/test_boundaries.gd)`, and the scan is now
  real (§2 A14): ids derived from the content tree (99), `.gd` + `.json`, `terrain/ sim/ core/ app/`.
- **Independent grep:** 0 files with a content-id hit under `game/terrain`, `game/sim`, `game/core`, `game/app`.
- **Red-proof:** planted ids → 2 failures; removed → 0.

| first-audit violation | now |
|---|---|
| `core/schemas/curse.schema.json` enum of all 12 enemy ids | enum removed; pattern `^[a-z][a-z0-9_]*$` + registry validation (D-FIX-A14-3) |
| `sim/death.gd` `CODES` map of 12 roster names | names come from `enemy.json` `death_name` via `core/roster.gd`; `DeathScript.killer_for(code)` |
| `sim/upgrades.gd` `"cartographer"` | renamed to the role key `"footprint_map"` |
| `sim/controller.gd` `"updraft"` | renamed to the event `"updraft_rise"` |
| `view/hud/run_over.gd` (13), `danger_text.gd` (12), `view/fog_env.gd` (5) | 0 hits; all read `core/roster.gd` (`fog_env.biome_order()` is derived from content) |
| `app/` files that FIX-A14 found red after the merge (`world.gd` 15, `loading_gags.gd` 6, …, RUNLOG 23:52Z) | 0 hits; the gag roster is data (`content/loading_gags.json`, FIX-APP-BOUNDARY) |

**Verdict: CLEAN under FLEET_PACK §3's rule.** Under the first audit's stricter brief rule (no id in `view/`
except per-enemy files), the remaining hits are per-content view files (listed under §2 A14). None of them
hardcodes the roster or the biome list, and none would need editing to add a 13th enemy or a 6th biome.

---

## 6. Disclaimer result — **verbatim and tested** (was PARTIAL)

The T-001 string (FLEET_PACK.md T-001's spec, em dash U+2014):

> VOIDWRAP RUN is a personal, non-commercial project — no money is involved, and it is not affiliated with, endorsed by, or connected to any person, brand, character, or IP referenced or depicted in the game.

| location | present? | byte-exact? | tested? |
|---|---|---|---|
| `README.md:8` | yes | **YES** (substring check, Python UTF-8) | yes, `test_disclaimer.gd` |
| lobby About plaque, `game/view/lobby/antechamber.gd:65` `const DISCLAIMER` | yes | **YES** — 206 chars / 208 bytes, one U+2014, `== FLEET_PACK spec` is `True` (was: ASCII `-` at index 51) | **yes, now**: `test_disclaimer.gd:66-69` preloads the plaque and asserts equality + the rendered text |
| app menu, `game/app/menu.gd:33` `ABOUT_DISCLAIMER` → footer (`menu.gd:283`, always on screen) | yes | carries the **ENEMIES.md** paragraph, by design (PARKED #2, D-T024-4); verbatim-asserted by `test_disclaimer.gd:34-37` | yes |

**Verdict: PASS.** The one remaining observation is reachability: the plaque is in code and tests, but
the shipped app never reaches the lobby (§2 A15).

---

## 7. Retired vocabulary — every hit

Re-run: the D-052 patterns (`\bHP\b`, `hit points`, `max_hp`, `heal`, `damage`, `LETHAL`, `Patch Kit`,
`Thick Skin`, `Glass Jaw`), case-insensitive, over `DESIGN.md`, `FLEET_PACK.md`, `README.md`, `game/data/`
(including the LOADING ticket's new `game/data/tips.json`). **The same seven hits as the first audit, no new
ones.** None is a `SUPERSEDED BY` line and none is an owner quote.

| # | pattern | file:line | the line (trimmed) | classification |
|---|---|---|---|---|
| 1 | `\bHP\b` | `FLEET_PACK.md:645` | `Zero hits for "damage", "HP", "rooms", "hop", "2 per level" across all docs and code (allowed` | **Not allowed.** T-091's own grep instruction text. |
| 2 | `damage` | `FLEET_PACK.md:645` | same line as #1 | **Not allowed**, same reason. |
| 3 | `LETHAL` | `DESIGN.md:471` | `… makes stillness lethal.` | ordinary-English adjective. |
| 4 | `LETHAL` | `DESIGN.md:574` | `- **Chaser ceiling (D-074): at most 6 floating lethal bodies in play at once** …` | ordinary-English adjective. |
| 5 | `LETHAL` | `FLEET_PACK.md:196` | `… the second lethal hit after it is spent kills …` | ordinary-English adjective. |
| 6 | `LETHAL` | `FLEET_PACK.md:321` | `… or airborne/glitched floor would make stillness lethal.` | ordinary-English adjective. |
| 7 | `LETHAL` | `game/data/offering_schedule.json:7` | `"_doc": "D-074 chaser ceiling (FINAL): … the floating lethal bodies in play …"` | ordinary-English adjective. |

**Verdict: 7 hits, 0 allowed — unchanged.** Nothing was edited (FLEET_PACK.md is frozen for this audit;
DESIGN.md and `game/data/` are not this audit's to edit).

---

## 8. Every `[CONTESTABLE]` entry added during the run

`grep -c "\[CONTESTABLE\]" DECISIONS.md` = **252** occurrences (216 at the first audit);
`grep -c "^### D-.*\[CONTESTABLE\]"` = **147 headings** (130 at the first audit). The 105 other occurrences
are inline markers inside entries whose heading is not marked (for example D-APPFLOW-1..5) and are not
counted twice. Rows 1–130 are the first audit's list, unchanged; rows 131–147 were added since.

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
| 131 | `D-ART-ADDRESS_ME-5` | address me keeps the full office photo (owner ruling); supersedes part of D-ART-ADDRESS_ME-2/-3 |
| 132 | `D-FIX-A15-1` | the T-001 disclaimer dash is U+2014; the plaque wraps at render time (1000 px) |
| 133 | `D-FIX-A4-1` | A4's recorded bot runs are 1,000 ticks × 10 seeds {101..1001}, sized to the gate's 300 s step timeout — owner to rule |
| 134 | `D-MENU-1` | menu entries PLAY / HOW TO PLAY / QUIT; About and **Settings** leave the menu; disclaimer to an always-on footer |
| 135 | `D-MENU-2` | the menu wears Indigo Trench fog and palette |
| 136 | `D-MENU-3` | roster layout: three terraces |
| 137 | `D-MENU-4` | menu display heights compress the canon body range |
| 138 | `D-MENU-5` | version tag "v0.1.0-alpha.1 pre-release" |
| 139 | `D-MENU-6` | roster caption: the in-game danger lines |
| 140 | `D-MENU-9` | typography, selection feedback and input |
| 141 | `D-MENU-10` | a photo-card sprite stands in a doorway on the menu island |
| 142 | `D-LOAD-1` | the loading screen is a flat 2D stage, not the 3D void |
| 143 | `D-LOAD-2` | five gags from the real sprites, seeded pick |
| 144 | `D-LOAD-3` | a gag is a 5.0 s timeline whose first 2.0 s contain the joke |
| 145 | `D-LOAD-4` | motion is procedural on the real PNGs |
| 146 | `D-LOAD-6` | the progress bar is the real load |
| 147 | `D-LOAD-7` | loading layout: wordmark top, stage middle, field note + bar bottom |

**147 open owner rulings.** The ones added since the first audit that matter most for alpha:
`D-FIX-A4-1` (A4's evidence is sized to fit a gate timeout), `D-MENU-1` (the Settings UI is no longer
reachable from the menu, and `app/settings.gd` has no UI path), and `D-MENU-5` (the menu prints
"v0.1.0-alpha.1 pre-release" although the alpha gate has not passed). Also relevant, though not
`[CONTESTABLE]` headings: D-APPFLOW-5 (gifts, mines and beacon are not ticked in the shipped app) and
D-LOAD-5 (FINAL, the two-duration law, PARKED #22).

---

## 9. Retro defect classes checked

### 9.1 Was a threshold moved to fit data? — **No.** Two items to watch.

- The 5,000-seed harness limits are the documented ones (§2 A2). A11's caps are unchanged (`afford3 29.3% <= 30%`).
  A12's bounds are unchanged: the first-launch rows are exactly as before, the restart rows were added, none
  were loosened, and `void_fall_to_respawn 0.800 s <= 0.80 s` still sits on its bound.
- **KIWI-SLOW is not a threshold move.** It changes an enemy's behaviour numbers to match the frozen
  ENEMIES.md:56 sentence ("slowly follow the player"), by a FINAL owner ruling recorded **before** the code
  (`3f2c739` before `ba02e84`). No acceptance criterion and no check was touched. `test_enemy_kiwi_cat.gd`
  is re-pinned at the same tolerances (§2 A7). Its effect on A3 is measured, not assumed (§2 A3).
- **To watch (1): A4's run length was sized to a gate budget.** D-FIX-A4-1 cut each recorded bot run from
  3,600 to 1,000 ticks because the longer runs pushed `run_all` past the gate's 300 s timeout. The criterion's
  count (10) and cadence (60 ticks) were not reduced, and the entry is `[CONTESTABLE]` with an owner question.
  The consequence: **all ten runs end at the cap**, so the replay never covers a death or a beacon entry.
- **To watch (2): margins.** A11 afford3 0.7 points; A12 void fall 0.0 s; the gate's step 3 at 214 s of 300 s
  standalone.

### 9.2 Is any dead time over its budget? — **No.**

| row | measured (feel_probe) | budget |
|---|---|---|
| loading_screen_hold (first launch) | 5.000 s (real app: 5.000 / 5.004 s) | ≥ 5.0 s |
| loading_screen_total_l30 (first launch) | 5.000 s | ≤ 8.0 s |
| loading_restart_hold | 2.000 s (real app: 2.006 / 2.004 s) | ≥ 2.0 s (D-LOAD-5) |
| loading_restart_total_l30 | 2.000 s | ≤ 2.0 s (D-LOAD-5) |
| gate_to_level | 0.178 s | ≤ 2.0 s |
| death_to_run_over | 0.0042 s | ≤ 2.0 s |
| void_fall_to_respawn | 0.800 s | ≤ 0.80 s |
| generate_mesh_l30 | 0.162 s | ≤ 1.5 s |

The exe's ~5.8 s start-up before the menu appears is not a DESIGN §2 row. It is noted here, not judged.

### 9.3 Is a gift inside geometry? — **No.**

The generator's invariant (`terrain_ref/validate.py`) and the 5,000-seed harness (32/32 PASS, every H check
0/5000) still hold; the bucket 26-30 reachability row is unchanged (first_gift 215.56, starve_p95 142.30,
starve_max 246.73).

### 9.4 Is a check weakened or skipped? — **Four of the first audit's five are fixed; one is still true; two new gaps.**

| # | first-audit item | now |
|---|---|---|
| 1 | `KNOWN_CONTENT_IDS` was an empty array | **FIXED** — ids derived from the content tree; red-proven by me (§2 A14) |
| 2 | the boundary scan read only `*.gd` | **FIXED** — `.gd` and `.json`, `core/schemas/` included |
| 3 | `test_disclaimer.gd` never read the plaque | **FIXED** — preloads `antechamber.gd`, asserts byte-identity |
| 4 | A4 recorded 1 run, not 10 | **FIXED** — 10 runs, 160 checkpoints; but each run is capped at 1,000 ticks and all end at the cap (§9.1) |
| 5 | `bot_run.gd` silently ignores unknown flags | **STILL TRUE** — `bot_run.gd:1153-1175`; FLEET_PACK §4's bot line and A3's `--seeds/--enemy` flags still fall through to defaults (200 runs to level 18) |

New gaps found by this audit (missing checks, not weakened ones):

| # | what | where | effect |
|---|---|---|---|
| 6 | **no test asserts the real app's loading hold in wall time** | `game/tests/test_app_flow.gd:59-74` drives `loading.advance(0.25)` by hand | the double-tick bug (5 s shown in ~2.5 s) shipped through a green gate and was found by reading code (RUNLOG 23:22Z); it is fixed now, but nothing would catch its return. My scratchpad probe also found the creation-frame delta defect (§2 A12). |
| 7 | **no test asserts that the shipped app can finish a level** | `game/app/world.gd:33-37`, `:409-416` (D-APPFLOW-5) | every A-criterion runs against the sim headless, so the gate is green while the exe's world never ticks gifts, mines or the beacon (§11 finding 2) |

### 9.5 Does any test assert something it documents as broken? — **Yes, the same three. None is fixed.**

| # | test | still true? | evidence on this commit |
|---|---|---|---|
| 1 | `game/tests/test_enemy_nuke.gd:24-27` | **yes** | header still says "the sim never expires telegraph footprints … the runtime's to fix, never this test's" |
| 2 | `game/tests/test_spawn_rule.gd:90-93` | **yes** | still asserts `pick_spawn_tile(lv, "", player)` → anchor index 2 (the farthest lane), the behaviour PARKED #5 says DESIGN §5 contradicts |
| 3 | `game/tests/test_enemy_toucher.gd:240` | **yes** | "rows in rt.telegraphs never expire and would pair across cycles" |

The underlying defect is live: `game/sim/enemy_runtime.gd:958` still carries "Rows in rt.telegraphs never
expire". PARKED #8 and #9 are still open.

### 9.6 Is any placeholder still magenta? — **Yes. The same three frames; nothing else.**

```
plushie_00.png (256, 256) distinct colours 3 [((255, 0, 255), 45872), ((168, 0, 168), 3520), ((5, 5, 5), 784)]
```

`game/content/enemies/claude/sprites/plushie_00..02.png` are still `make_tbd_png.gd` output (`#FF00FF`
45,872 of 50,176 opaque pixels each). The ART wave removed every other placeholder: 102 PNGs scanned, **no
magenta/black checker frame**. The two other magenta-dominant frames (toucher `floor_00`, `floor_04`, 4
distinct colours) are posterised from `glitchedground.jpeg`, whose own dominant non-white colours are
`(198,0,199)` and `(150,0,151)`. They are real art. The plushie still passes the fog check (contrast 5.864 at
40 u in violet_hour), so no gate flags it.

---

## 10. Appendix — T-081's fun-risk report (information only, not gated)

Pasted unchanged from the first audit; source `tickets/T-081.response.md`. **It predates FIX-BILLBOARD and
KIWI-SLOW** (5.6 u/s cat) and was not re-run by this audit (it is not an A-criterion, and FLEET_PACK §0.7
forbids building more measurement than §5 lists).

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

The first audit's reading still stands as history: of 176 charges spent across 100 bot runs, 175 (99.4%)
were terrain-caused; 59 of 99 deaths were `D-VOID`; no run reached level 6. For the current-main picture of
level 1, see §2 A3.

---

## 11. Final verdict

**A1-A16: 15 PASS, 0 PARTIAL, 1 FAIL (A3).**

| verdict | criteria |
|---|---|
| PASS (15) | A1, A2, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14, A15, A16 |
| PARTIAL (0) | — (A12 becomes PARTIAL if the owner rejects D-T099R-1) |
| FAIL (1) | **A3** — the bot completes level 1 in 19 of 100 seeds on the audited tree, 82 of 100 after FIX-A3 merged (`b9c6470`), against a required 95 of 100 |

**THE ALPHA GATE DOES NOT PASS. The tag `v0.1.0-alpha.1` was NOT created.**

### What changed since the first audit (12 PASS / 3 PARTIAL / 1 FAIL)

| criterion | first audit | now | why |
|---|---|---|---|
| A3 | FAIL (1/10) | **FAIL (19/100 audited, 82/100 after FIX-A3 `b9c6470`)** | measured on all 100 seeds this time; 81 level-1 deaths (60 `D-VOID`) on the audited tree; FIX-A3 merged afterwards and re-measured at 82/100, still short of 95 |
| A4 | PARTIAL | **PASS** | 10 recorded bot runs, 160 checkpoints identical (FIX-A4); runs capped at 1,000 ticks |
| A14 | PARTIAL | **PASS** | real content-id scan over `.gd`+`.json` in terrain/sim/core/app, red-proven; core violations removed (FIX-A14, FIX-APP-BOUNDARY) |
| A15 | PARTIAL | **PASS** | plaque byte-identical to README (U+2014), asserted by `test_disclaimer.gd` (FIX-A15) |
| A12 | PASS | PASS, now resting on D-LOAD-5 FINAL | restarts hold 2.0 s by owner ruling; literal A12 text says ≥ 5.0 s (D-T099R-1, PARKED #22) |
| others | PASS | PASS | re-measured; numbers in §2 |

### The three findings that matter most for the owner

1. **The bot still cannot finish level 1, and the terrain is still what kills it.** On the audited tree,
   **19 of 100** seeds complete level 1 (95 required). Of the 81 that fail, 60 fall into the void
   (`D-VOID`), 14 are caught by the kiwi cat and 7 by coil. The slow-cat ruling is in (3.0 u/s), and the cat
   still accounts for 14 of the 81 deaths. FIX-A3, the bot-competence fix, has since merged (`b9c6470`) and
   re-measured at **82 of 100** — a real gain, still 13 short of the criterion, so A3 remains the one
   criterion that blocks the alpha. The remaining question is a design one for the owner: how forgiving the
   level-1 terrain is.
2. **The shipped exe is a menu and a walk-around, not a game loop, and the gate cannot see it.**
   `game/app/world.gd:33-37` and D-APPFLOW-5 state it plainly: the world ticks the controller and the
   enemies, but **not gifts, tripmines or the beacon** (read from the code and the decision; I did not play
   the exe by hand, and what happens on an enemy contact in the exe was not measured). So in the exe the HUD reads 0/0 gifts, the beacon never
   opens, no level can be completed, and the lobby — with its altars (A9) and its About plaque (A15) — is
   never reached. The menu also lost its Settings entry (D-MENU-1), so `app/settings.gd` has no UI path.
   Every A-criterion is measured headless against the sim, so all of them pass while the player cannot do
   the core loop the canon defines (C2). No test asserts that the app can finish a level (§9.4 #7). This is
   the largest gap between "the audit is green" and "the alpha is playable".
3. **The proofs got real, and three known-broken behaviours are still pinned as expected.** FIX-A4, FIX-A14
   and FIX-A15 turned three hollow checks into real ones: I red-proved the boundary scan myself. The ART wave
   left no checker placeholder, and FIX-BILLBOARD fixed every enemy being drawn 1.4-7.5 u under the floor.
   Still open: (a) the three self-documenting tests (`test_enemy_nuke.gd`, `test_spawn_rule.gd`,
   `test_enemy_toucher.gd`) still encode the never-expiring telegraph rows and the spawn-rule contradiction
   as expected behaviour; (b) **three magenta `plushie_00..02.png` blocks** still ship in the Claude fight;
   (c) A4's ten recorded runs are capped at 1,000 ticks to fit the gate's 300 s timeout, so all ten end at
   the cap; (d) TBD.md's section-1 heading and body still contradict its table, RUNLOG.md has no
   MERGED-GREEN line for KIWI-SLOW, and PARKED #20 still reads open although it is fixed.

### What the audit did not do

- It did not fix anything: no code, test, content, threshold or document other than this file (and one
  D-T099R-1 entry in DECISIONS.md recording the A12 judgment call).
- It did not create the tag, and did not merge, rebase or touch FIX-A3's branch.
- It did not re-run T-081's 100-run fun-risk report.
- It did not visually verify the default-Vulkan render (D5, environmental); the menu was verified on D3D12.
- It did not measure whether a drop-in enemy *renders* (`test_dropin.gd` proves registration and sim behaviour).
