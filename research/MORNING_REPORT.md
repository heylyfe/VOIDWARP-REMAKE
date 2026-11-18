# MORNING REPORT — the overnight fleet run

> **Final check (post-run):** three read-only reviewers swept the simulation core, the app/view layer
> and the tracked tree for security and privacy. The gate is green (`GATE OK`, `TESTS 59 passed
> 0 failed`, no `SCRIPT ERROR`). Three small safe fixes landed — `.gitignore` now covers `.env`, keys,
> certificates and `*.exe`; the exact CPU/GPU/Parsec hardware fingerprint is scrubbed from every tracked
> file; and a real C-bay bug that could offer the same Mild curse twice is fixed. Five findings are
> parked with reasons (rows 25–29), including two HIGH ones that need a re-baseline rather than an
> end-of-run patch. One reported finding was a false positive and is recorded as such.

> **Post-run verification pass:** a second, independent pass re-ran the gate, re-asserted five random
> tickets, pulled the telemetry and audited every parked row. Read it at
> [research/MORNING_REPORT_POSTRUN.md](MORNING_REPORT_POSTRUN.md). It found nine paperwork and tooling
> drifts (none of them a broken build) — the most important being that the exe on disk predates
> APP-LOOP, so the built binary still cannot finish a level even though the source can.

Written at the end of the run. Every number below comes from a command run in this session; where
something could not be measured, it says so instead of guessing.

- **Repository:** https://github.com/heylyfe/VOIDWARP-REMAKE (public)
- **Branch:** `main`, 343 commits
- **Pushed head:** **`a5d68de`** — `git rev-parse HEAD` and `git ls-remote origin main` both return
  `a5d68de24f7caba1fed28d4e2605e7af5c4d9713`, and `git branch -vv` shows `main` in sync with
  `origin/main`. The night's pushes were `90212f9` (323 commits), `f4dfcda` (the final commit) and
  `a5d68de` (the final check's three fixes and the post-run reports).
- **Alpha tag `v0.1.0-alpha.1`: NOT created.** A3 fails, so the gate does not pass. See below.

---

## 1. The alpha gate: A1 to A16

**A1-A16: 15 PASS, 0 PARTIAL, 1 FAIL (A3).**

| verdict | criteria |
|---|---|
| PASS (15) | A1, A2, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14, A15, A16 |
| PARTIAL (0) | — (A12 becomes PARTIAL if you reject D-T099R-1) |
| FAIL (1) | **A3** — the bot completes level 1 in 82 of 100 seeds, 95 required |

Three criteria moved up from the first audit, each re-measured rather than taken on a ticket's word:

| criterion | first audit | now | why |
|---|---|---|---|
| A4 | PARTIAL | **PASS** | 10 recorded bot runs, 160 checkpoints identical (FIX-A4) |
| A14 | PARTIAL | **PASS** | a real content-id scan over `.gd` and `.json` in terrain/sim/core/app, red-proven by planting an id (FIX-A14, FIX-APP-BOUNDARY) |
| A15 | PARTIAL | **PASS** | the lobby About plaque is byte-identical to the README disclaimer, em dash included (FIX-A15) |

`AUDIT.md` is the full audit: 816 lines, A1 to A16 one by one with the command, the final line and the
evidence for each, plus the canon table, the roster, the boundary result, the retired-vocabulary sweep,
the `[CONTESTABLE]` index and the retro defect classes.

---

## 2. The three things that matter most

### 2.1 A3 is the one blocker, and it is a bot-competence problem, not a game problem

The bot completes level 1 in **82 of 100 seeds** (median level-1 sim time 43.4 s against the 120 s
criterion, so the time half is met). It was 1/10 at the first audit and 56/100 before the kiwi-cat
ruling. The 18 failures are `D-KIWI` 8, `D-VOID` 4, stuck 4, timeout 1, `D-COIL` 1.

Nothing was weakened to get there: no threshold moved, no criterion edited, no enemy number touched.
The residual is a competence ceiling — the bot's straight-line lead prediction cannot beat a floater
that tracks the player's feet height in flight, so it dies on the landing tile. The next lever is a
purer intercept prediction of the landing tile, recorded in `PARKED.md` row 24.

**The question for you is a design one:** 95 of 100 is a demanding bar for a bot that is not the
player. If you would rather ship alpha with a bot that clears 82 of 100, that is a criterion change and
yours to make — I did not make it.

### 2.2 The shipped exe could not finish a level — fixed tonight (APP-LOOP)

The audit found, and `game/app/world.gd`'s own header confirmed, that `step()` ticked the controller,
the enemy runtime, the billboards and the camera rig — but **not gifts, tripmines or the beacon**. In the
exe the HUD read 0/0 gifts, the beacon never opened, no level could be completed, and the lobby (with its
altars and its About plaque) was never reached. The menu also lost its Settings entry (D-MENU-1).

This was a wiring gap, not a design one: `game/tools/bot_run.gd` already ran that exact loop and is
proven by the gate and by the 100-seed sweeps. **APP-LOOP ported it and merged green** (`2e80d27`).
`step()` now runs controller -> player-row sync -> `lv.tick` -> gifts -> mines -> `beacon.try_enter` ->
on open, the enemy runtime's beacon hook and the gold phase -> economy -> enemy runtime -> economy
events. `world.gd` emits `level_completed()` once and exposes `is_complete()`; `app.gd` connects it.

`test_app_loop.gd` proves it end to end through the real `build()`/`step()`: the HUD shows the real gift
total (0/40, never 0/0), every black gift is collected, the beacon opens exactly at the last one, a gold
gift pays the economy, entry completes the level exactly once, a tripmine contact runs the ladder inside
`step()`, and a void fall costs exactly one charge. It was verified **red under three mutations** (gifts,
mines, beacon unticked): 10, 3 and 6 assertion failures. The suite is now 59 tests, all passing.

**One decision there deserves your eye (D-APP-LOOP-4):** completing a level returns to the **menu**, not
to level 2. The intermission lobby is unimplemented, so starting level 2 with fresh charges and a fresh
purse would be a lie. That is the next real piece of work.

**Why the gate never caught it:** every criterion is tested without the app. The gate was green on a
build whose exe could not complete a level. That is a real hole in the gate, and worth a ticket of its
own.

### 2.3 The paperwork is now consistent, and the one place it is not is named

`TBD.md`, `PARKED.md` and `RUNLOG.md` were reconciled during the run: `PARKED.md` row 20 (the loading
double-advance) is marked RESOLVED, row 21 (the billboard bug) is marked RESOLVED, and the three
tickets that all claimed row 20 were renumbered 20/21/22-23. `TBD.md`'s stale `babehseal.webp` rows now
name the owner's `babehseal.png`.

---

## 3. What was built tonight

| work | result |
|---|---|
| The 17 owner source images | committed on `main` (`b912b19`) so every worktree sees them |
| **ART wave — 12 enemies** | **102 real PNGs** under `game/content/enemies/*/sprites/`, one art module per enemy, every T-083 anim state with its own frame, `tbd: false` only where the frame is real. The magenta/black checker is gone except claude's three `plushie_00..02.png` |
| T-099 final audit | `AUDIT.md`, 12 PASS / 3 PARTIAL / 1 FAIL at the time |
| FIX-A15 | the T-001 disclaimer verbatim in README and the lobby plaque |
| FIX-A4 | replay determinism on 10 recorded runs, 160 checkpoints identical |
| FIX-A14 | a real content-id boundary scan, red-proven |
| APP-FLOW | the app orchestrator: menu -> loading -> level 1 |
| MENU | the floating-island main menu with the real enemy roster |
| LOADING | 5 s on first launch, exactly 2.0 s on restarts, a 2D enemy gag, 30 tips |
| FIX-APP-BOUNDARY | 26 boundary hits -> 0 |
| FIX-BILLBOARD | every enemy was drawn 1.4-7.5 u below the floor; fixed at source |
| ART-FIX-ADDRESS-ME | the office photo background kept, per your ruling |
| ART-FIX-SEAL | the new harp-seal pup, per your ruling |
| **KIWI-SLOW** | the kiwi cat is slow: 5.6 -> **3.0 u/s**, SR-5 ceiling 0.80 -> **0.40** (3.6 u/s), Zoomies burst 1.00 -> **0.55** (4.95 u/s), kitten 4.5 -> **2.4** / 0.70 -> **0.30** / burst 2.97 u/s so a kitten can never outrun its cat. Recorded FINAL as `D-KIWI-SLOW-1`, written before the code |
| **FIX-A3** | the bot's edge discipline and jump planning: 56 -> **82 of 100** seeds clear level 1, void deaths 8 -> 2 on its probe |
| **APP-LOOP** | the exe can now finish a level: gifts, tripmines, the beacon and the gold-phase economy are ticked, `level_completed()` reaches the app, and `test_app_loop.gd` proves it red-under-mutation |
| T-099R | the audit re-run: 15 PASS, 1 FAIL |

The suite is **59 tests, 59 passing, 0 failing**; the gate's nine steps all pass
(`GATE OK (9 ran, 0 skipped)`, `PARITY 56/56`, `SPRITES OK`, `FOGCHECK OK`).

---

## 4. Privacy: the Windows username

You asked for your local Windows username to be removed from the public repo. Done and committed
(`f96ae6f`, "Privacy: replace the local Windows username in docs and tools"):

- every `C:\Users\<name>` in `FLEET_PACK.md`, `game/tools/art/toucher.gd`, the T-002/T-056/T-082/T-083
  response files, `GUARDIAN.md` and `RUNLOG.md` is now `C:\Users\username`;
- `tools/build_models.ps1` no longer hard-codes the path — it builds the Blender location from
  `$env:USERPROFILE`, so it still works;
- `git grep -i` for the old name over the tracked tree returns **nothing** (verified again immediately
  before the final commit).

**One thing you should know:** git history was **not** rewritten and nothing was force-pushed, so the
old name still exists in commits that are already on GitHub. Removing it from history means a rewrite
(`git filter-repo`) plus a force-push, which rewrites every commit hash and breaks every clone. That is
your call, not mine to make at 22:30Z. If you want it, the repo is small and the rewrite is
straightforward — but do it before anyone else clones.

---

## 5. What is open, by name

| item | state |
|---|---|
| **A3** bot completes level 1 in 95/100 | **FAIL at 82/100.** Parked, row 24, with the next lever named |
| **The intermission lobby** | unimplemented, so completing a level returns to the menu (D-APP-LOOP-4). The next real piece of work |
| **The gate cannot see the app** | every criterion is tested without the exe; a build that cannot complete a level passed the gate for weeks. Needs a ticket |
| `PARKED.md` #2 | the app-menu About screen still carries the ENEMIES.md paragraph, not the T-001 disclaimer |
| `PARKED.md` #4 | T-026 |
| `PARKED.md` #17 | T-081's report-as-appendix clause: `AUDIT.md` did not exist when T-081 ran |
| `PARKED.md` #18 | T-075's answer-lab: 1 of 29 pairs meets the 95 %/5 % bar; the harness, not the design, is the gap |
| `PARKED.md` #19 | toucher's per-state frames vs the global `frame_map` |
| `PARKED.md` #22-23 | the two LOADING contradictions with DESIGN.md §2's CANON rows |
| `PARKED.md` #24 | FIX-A3's residual, with the numbers |
| claude's `plushie_00..02.png` | the only magenta frames left |
| `bot_run.gd` ignores unknown flags | FLEET_PACK §4's bot line and A3's own `--seeds`/`--enemy` silently fall through to defaults |
| `tools/verify_curses.py` | fails on `twin_fangs` (`requires_enemy` says `gin_ichimaru`, the file says `gin`) — pre-existing fallout from the FIX-A14 rename |
| Vulkan | failed in the audit session (blank window on both the exe and the editor); A1 and A13 were measured on D3D12 instead |

---

## 6. How to run it

```
tools\godot\godot.exe --path game            # the game
powershell -NoProfile -File tools/gate.ps1   # the gate (9 steps, ~230 s)
```

The gate is the contract: `GATE OK (9 ran, 0 skipped)` with `TESTS 59 passed 0 failed`, `PARITY 56/56`,
`SPRITES OK`, `FOGCHECK OK`, and no `SCRIPT ERROR` line anywhere in the log.

---

## 7. The honest summary

The build is a real game now: a floating-island menu with the actual enemy roster, a loading screen
that keeps its two-duration law, twelve enemies with real art and a distinct frame per animation state,
a lobby, five biomes, 46 curses, 36 upgrades, a level you can actually finish in the exe, and a gate
that runs 5,000 terrain seeds, the gallery, the parity check and 59 tests in about four minutes.

It is not an alpha yet, for one measured reason: the bot clears level 1 in 82 of 100 seeds and the
criterion is 95. Everything else passes. The tag was not created, because creating it would have meant
either moving the criterion or lying about it.

The two things I would do first tomorrow: build the intermission lobby so a run can go past level 1,
and give the gate a criterion that actually launches the app, because for weeks it was green on a build
whose exe could not complete a level.
