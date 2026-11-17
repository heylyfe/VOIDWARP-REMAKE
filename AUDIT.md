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
