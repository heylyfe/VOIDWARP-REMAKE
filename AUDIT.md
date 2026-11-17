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
