# MORNING REPORT — POST-RUN VERIFICATION PASS

Written after the overnight run finished, by a fresh verification worker. The brief was: verify it,
don't trust it. Every number below comes from a command run in this session; where something could not
be measured, the text says so and says why. Nothing was committed, pushed, branched or merged. No
tracked file was modified. This file is the only new file.

- **Checkout:** `C:\Users\username\Documents\REMAKE VWR\VOIDWARP-REMAKE` (the main checkout, not a worktree)
- **HEAD:** `f4dfcda` — "RUNLOG and MORNING_REPORT: the final push hash and the privacy check"
- **Working tree:** clean except `RUNLOG.md` and `GUARDIAN.md`, which carry the three uncommitted
  post-run dispatch lines (23:40Z/23:41Z/23:42Z). That is expected, not drift.
- **Logs:** every command's output is under `out/` (gitignored): `gate_postrun.log`,
  `harness_postrun.log`, `batch_postrun.log`, `run_report_postrun.txt`, `run_logs/` (25 JSONL run logs).

---

## 1. GATE STATUS — green, and it is green for real

I re-ran the full gate myself on the final state, redirected to a file (never piped through `tail`):

```
powershell -NoProfile -File tools/gate.ps1 > out/gate_postrun.log 2>&1
```

**Final line: `GATE OK (9 ran, 0 skipped, 235 s)`** — exit 0.

| line | value |
|---|---|
| GATE | `GATE OK (9 ran, 0 skipped, 235 s)` |
| TESTS | `TESTS 59 passed 0 failed` |
| PARITY | `PARITY 56/56 OK` (plus `GALLERY_PIN 16/16`) |
| SPRITES | `SPRITES OK 515 checks over 12 sprites.json` |
| FOGCHECK | `FOGCHECK OK (550 checks over 5 biomes)` |
| oracle | `TESTS OK`, `SELFTEST 15/15`, `GALLERY 16/16 OK` |

**One correction to the brief.** The brief says the gate "covers the validator's 5,000 seeds". It does
not. `tools/gate.ps1`'s own header says the 5,000-seed harness is *deliberately* not a gate step; it
lives in `tools/harness.ps1`. I ran it separately so A2 is actually verified:

```
python terrain_ref/validate.py --seeds 0:5000   ->  EXIT 0, 32 PASS lines, 0 FAIL lines, 173.1 s
```

So: gate green, and the 5,000-seed harness green, measured separately. Nothing failed. There is no
"first line of the report is a failure" to write.

---

## 2. DRIFT AND FAILURES

Nothing in the build is broken. Nine things in the *paperwork and tooling* are wrong or stale, and two
of them matter for what you can actually ship.

### 2.1 The exe on disk cannot finish a level — it predates the fix that makes it possible

This is the one to read first.

| fact | evidence |
|---|---|
| `build/voidwrap_run.exe` mtime | `2026-11-17 14:48:42` |
| APP-LOOP merge commit `2e80d27` | `2026-11-17 23:08:36` |
| APP-LOOP's own commit `3501a5f` | `2026-11-17 22:55:12` |
| symbols APP-LOOP added to `world.gd` | `is_complete`, `level_completed`, `try_enter` |
| those symbols in the exe | `is_complete` 0, `level_completed` 0, `try_enter` 0 |

The exe is **8 h 20 m older** than the merge that wired gifts, tripmines and the beacon into
`world.gd`, and a binary grep finds none of the three symbols that fix introduced. The exe starts and
exits 0 (`--quit-after 600` → exit 0, 1205 lines of the known Vulkan `VkResult error -13` noise), but
it is the pre-APP-LOOP build: HUD 0/0 gifts, beacon never opens, no level completable.

**The code can finish a level. The exe you have cannot.** A re-export is needed before anyone plays it.
I did not run the export (that writes a binary, and the brief says verification only).

### 2.2 `tools/run_batch.ps1` reports before the runs finish — reproduced

T-081 shipped this as "one command for the owner". On this machine it does not work:

```
powershell -NoProfile -File tools/run_batch.ps1 -Runs 25 -SeedBase 0
  -> "RUN REPORT: no .jsonl run logs under ...\out\run_logs"
  -> "BATCH OK: 25 runs requested"          (printed while the bot was still running)
```

Cause, isolated with a controlled test: PowerShell's `&` does **not** wait for `godot.exe` (a
GUI-subsystem binary). `& './tools/godot/godot.exe' ... --runs 1` returned in **0 s** with the process
still alive. So the report step always runs against an empty or partial log directory.

Workaround I used: run the bot, wait for the process to exit, then run `run_report.gd` separately. That
is how the telemetry in section 3 was produced. `tools/gate.ps1` is unaffected — it uses
`System.Diagnostics.Process` with `WaitForExit`, which does wait.

### 2.3 Death attribution shows two names for one enemy

The 25 fresh run logs contain both `YOU` (2 deaths) and `YOU?!` (1 death) as the killer string for the
same `D-YOU` code. Cause: `game/content/enemies/you/enemy.json` has `name: "YOU?!"` and **no**
`death_name`, and only `gift_larper` has a `death_name` at all:

```
gift_larper  death_name = 'gift Larper (Tripmine)'
all 11 others  death_name = None
```

T-035's `D-T035-4` predicted exactly this and asked T-073 to normalise it; T-073 added `death_name` to
gift_larper only. The run-over screen therefore shows two different names for the same enemy. Small,
real, and a one-line data fix per enemy.

### 2.4 `TBD.md` contradicts itself

- Section 1's heading reads **"4 MISSING"**; its own table shows **0 missing** (all 12 enemies real art,
  only Claude's `plushie_00..02` still TBD).
- Section numbering is out of order: `## 2. Placeholder audio hooks` (line 21) comes *before*
  `## 1. The 17 enemy images` (line 29), and there are two `## 2.` sections.
- Orphaned prose fragments left by the merge resolver still say "the other fourteen remain MISSING ->
  TBD", which the table contradicts.

AUDIT.md already flagged this as an unfixed documentation defect. I did not fix it (not mine to edit).

### 2.5 `RUNLOG.md` breaks its own stated format for KIWI-SLOW

The file's header says a ticket ends in `MERGED-GREEN` or `PARKED`, "nothing else". KIWI-SLOW has no
line containing `MERGED-GREEN` (`grep -c` → 0). The merge itself is real and present — `64e3332`,
"Merge KIWI-SLOW: kiwi cat is a slow, lazy follower (owner ruling FINAL)" — so this is a paperwork gap,
not a missing merge.

### 2.6 `AUDIT.md` is stale on its own headline finding

AUDIT.md's finding #2 says "the shipped exe is a menu and a walk-around, not a game loop… the world
ticks the controller and the enemies, but **not gifts, tripmines or the beacon**". That was true when
the audit ran and is **false now**: `game/app/world.gd:205` `step()` ticks `GiftsScript.tick`,
`MinesScript.tick` and the beacon, and `test_app_loop.gd` passes in the gate. APP-LOOP landed after the
audit. Anyone reading AUDIT.md alone will believe the game loop is still missing.

### 2.7 `AUDIT.md`'s own defect list is partly stale

AUDIT.md §11 (d) claims "PARKED #20 still reads open although it is fixed". It does not — row 20 ends
with "**RESOLVED 2026-11-17, kept for the record:** … Nothing is parked here any more." The other two
claims in that sentence (TBD.md's heading, RUNLOG's missing MERGED-GREEN token) are still true.

### 2.8 Two corrections to the brief itself

- The gate does not cover the 5,000 seeds (section 1 above).
- The brief says "the 17 [POST-RUN] items". There are **16**, numbered 8–23 in
  `research/fable-preflight.md`. Items 1–7 and 24 are `[BLOCKS-FLEET]` and all carry
  `RESOLVED (D-0xx)`.

### 2.9 Every "merged green" claim I checked exists in the working tree

I resolved all 30 merge hashes named in RUNLOG.md against `git log` — every one exists with the subject
the log claims (`c6d95ce` T-070 … `2e80d27` APP-LOOP, `53672e3` final, `f4dfcda` HEAD). Spot-checked
contents match the claims: kiwi `base_speed 3.0 / ceiling 0.4 / burst 0.55`, `billboard.gd:151` carries
the corrected offset sign, `twin_fangs.requires_enemy == "gin"`, `test_replay.gd:43` has the ten
`BOT_SEEDS`, `run_log.gd` emits all 18 record types, `world.gd` ticks gifts/mines/beacon. No claim I
tested was false.

---

## 3. TELEMETRY — the headline numbers

T-081's own 100-run report predates FIX-A3 and KIWI-SLOW, and its logs are gone (`out/` is gitignored
and was cleaned). So I produced **fresh runs on current main**: 25 seeds (0–24), `bot_run.gd --dodge
--log`, then `run_report.gd` over the logs. 4,243 records, all 18 record types present.

### 3.1 Terrain vs enemy — the split has flipped

| signal | T-081 (old bot, 100 runs) | **fresh (current main, 25 runs)** |
|---|---|---|
| charges spent | 176 | 46 |
| terrain-caused | 175 (**99.4 %**) | 42 (**91.3 %**) |
| enemy-caused | 1 (0.6 %) | 4 (8.7 %) |
| deaths | 99 | 25 |
| terrain-caused deaths | 59 (**59.6 %**) | 4 (**16.0 %**) |
| every other code | 40 (40.4 %) | 21 (84.0 %) |

**The terrain still spends the charges (91.3 %), but the enemies now do the killing (84 %).** That is a
real change from the audit's picture and it matters for how you read A3.

### 3.2 Deaths by killer, across levels

| killer | code | deaths | share |
|---|---|---|---|
| kiwi cat | D-KIWI | 10 | 40 % |
| coil | D-COIL | 7 | 28 % |
| void | D-VOID | 4 | 16 % |
| YOU / YOU?! | D-YOU | 3 | 12 % |
| seal | D-SEAL | 1 | 4 % |

By level: **L1 2, L2 6, L3 6, L4 9, L5 2.** Deaths cluster at levels 2–4, not level 1.

Last Light saved 21 kills (D-KIWI 13, D-COIL 6, D-YOU 1, D-MINE 1) against 25 deaths — so 46 lethal
events, 21 absorbed.

### 3.3 Falls and charge economy

- **Falls per run: 1.84** (46 `void_fall` over 25 runs). Every one spent a charge: 46 `charge_spent`,
  **0 free falls** (Field Dressing is inert — see PARKED #3).
- `charge_restored`: 53 records, of which **24 actually gained** a charge (the other 29 were already at
  the cap of 2). That is 0.96 real gains per run against 1.84 spends.

### 3.4 Level clear times against the DESIGN.md §2 targets

Targets: **L1 90 s · L10 150 s · L20 200 s · L30 240 s.**

| level | n | median | min | max | vs target |
|---|---|---|---|---|---|
| L1 | 23 | **45.0 s** | 30.5 | 64.5 | 50 % of 90 s |
| L2 | 17 | 45.7 s | 32.9 | 72.9 | — |
| L3 | 11 | 55.0 s | 34.2 | 88.9 | — |
| L4 | 2 | 91.8 s | 74.1 | 109.4 | — |
| L10 / L20 / L30 | **0** | — | — | — | **not measurable: no run reached level 6** |

**Level 1 clears in 45.0 s against a 90 s target — half the intended length.** The L10/20/30 targets
cannot be measured at all because the bot never gets there.

### 3.5 Mine bypasses

Only 4 mine events in 25 runs (levels 1–2 roll zero mines by design; the bot rarely reaches the levels
that do). The three bypasses passed at **1.006, 1.003 and 0.983 u** from the mine centre against a
0.9 u trigger — **0.08–0.11 u of clearance**. Zero bypasses came within 0.5 u. One contact, absorbed by
Last Light. So the "0.1 u wide bypass" concern is confirmed with real numbers, on a very small sample.

### 3.6 How far runs got

**Median level reached 3, maximum 5.** No run reached level 6. Lobbies: 78 (C 17, C+U 2, E 36, E+U 23).

### 3.7 A3 independently reproduced

My 25 seeds overlap FIX-A3's published failure list. FIX-A3 reports 82/100 with 18 failures at seeds
10, 22, 31, 35, 44, 49, 51, 53, 55, 63, 64, 68, 69, 74, 82, 87, 88, 92.

**My batch cleared level 1 in 23 of 25 (92 %), and the two failures are exactly seeds 10 (D-VOID) and
22 (D-KIWI)** — the only two of FIX-A3's 18 that fall in 0–24, with the same death codes. That is a
clean independent confirmation of the 82/100 figure, not a contradiction of it.

---

## 4. THE FIVE TICKETS I RE-ASSERTED

Picked from the mandatory merge log, each re-measured against the build rather than the log.

| # | ticket | verdict | evidence |
|---|---|---|---|
| 1 | **T-020** gifts / slots / beacon / straggler | **CONFIRMED** | `test_gifts.gd:29` `SEED_COUNT := 100`, `_test_a5_100_seeds` runs in the gate; `test_gifts.gd:231` asserts "BEACON entry restores exactly 1 charge: 0->1 1->2 2->2, capped, latched"; `slot_pos` exists only in `game/sim/gifts.gd:87` — no gift-position code outside terrain. |
| 2 | **T-022** economy / chain / overtime / shop | **CONFIRMED** | `economy_audit.gd` → `AUDIT OK (runs=1000 shops/run=15 afford1=99.5% afford3=29.3% purchases=23.89 cautious=8.25)` against bands ≥80 % / ≤30 % / 18–24 / 6–10. `test_offers.gd:53` pins the canon three (`paycheck`, `more`, `yearn_for_speed`); `test_economy.gd` asserts all four chain-reset events plus `_test_nothing_else_resets`. |
| 3 | **T-030** kiwi cat | **CONFIRMED** | `enemy.json`: `base_speed 3.0`, `pursuit_ceiling 0.4`, `burst_ceiling 0.55` (the KIWI-SLOW ruling), `body_height 1.0`, `hit_diameter 0.9`, `death_code D-KIWI`, `contact_kill true`. `test_enemy_kiwi_cat.gd` asserts every §5.1 number ±1 tick, contact kill, and sets `ctl.last_light_spent = true` (D-057). |
| 4 | **T-074** three-altar draw | **CONFIRMED** | `test_offers.gd:208+` asserts NEW / REPEAT / FREE, the per-enemy caps and the chaser ceiling against real content; the 1,000-run walk prints `T074 walk: level-19 coverage N / 1000 runs offered all 12 types (bound >= 990)`. |
| 5 | **T-080** telemetry log | **CONFIRMED** | `run_log.gd` emits all 18 record types (verified by counting them in the source and by finding all 18 in the fresh logs); `test_run_log.gd:586` is the replay proof — identical hashes with logging on and off. |

**5 of 5 CONFIRMED. No DRIFT in the ticket work itself.** The drift I found is in the paperwork and the
tooling (section 2), not in what the tickets built.

---

## 5. PARKED — 24 rows, 3 resolved, 21 open, 1 unblocked

`PARKED.md` has **24 rows**. Every row has a non-empty "why" and "what was tried" — **no parked ticket
was left without a written reason** (checked cell by cell).

**Resolved (3):** #16 T-051 (the 12 missing curse modules landed at `c29ae7f`/`3ae41b2`), #20 APP-FLOW
(the double-advance closed in `app.gd`), #21 MENU (FIX-BILLBOARD fixed the sign at source, `_plant()`
deleted).

**Open (21).** One paragraph each, why it parked and whether it is unblocked now:

1. **T-027** — ENEMIES.md's intro says enemy logic is client-sided, its global notes say server-sided.
   Built the global-notes reading. **Still blocked: needs your ruling on which passage stands.**
2. **T-024** — DESIGN.md §14's disclaimer line and ENEMIES.md's DISCLAIMER paragraph are two different
   "verbatim" texts. Both kept, both pinned. **Still blocked: your ruling on which wording stands.**
3. **T-086** — Field Dressing's free-fall pip animation has no call site because the sim has no Field
   Dressing path. **Still blocked, and I verified it: `on_void_fall` appears only in `core/hooks.gd`
   and the two schemas — nothing in `game/sim/` calls it.** The upgrade is purchasable data that does
   nothing. Resolves itself when the sim implements it; no ruling needed, but it is real work.
4. **T-026** — the walker bot completed 0 of 4 seeds. **Partially unblocked:** blocker (a) is gone
   (kiwi_cat has behaviour since T-030), and blocker (b) improved from 0/4 to 82/100 via FIX-A3. The
   row's numbers are stale; the criterion still fails. Fold into #24.
5. **T-032** — DESIGN.md says a `none` preferred kind skips spawn steps (a)/(b); merged T-027 always
   runs (b) and its test pins that. Built the DESIGN reading as an additive sentinel. **Still blocked:
   your ruling on which spelling stands.**
6. **T-034** — ENEMIES.md answers the nuke with "break line of sight", but D-025 terrain has almost
   nothing overhead. Both sentences kept. **Still blocked: your ruling on the working answer.**
7. **T-034** — the nuke's blast kills only the nearest player inside it; the §12 API has no player
   enumeration. **Still blocked on a runtime API addition; no observable difference in a single-player
   sim today.**
8. **T-034** — the sim never expires telegraph footprints. Duplicate of #9. **Still blocked.**
9. **T-032 + T-034** — the same telegraph-expiry defect, found independently. Two central fixes were
   tried and both broke merged tests (coil double-decrements, nuke's ring is deleted mid-descent), so
   `enemy_runtime.gd` is untouched. **Still blocked: your decision on whether behaviours own their
   footprint lifetime or the runtime does.** This one can wedge address_me's SR-4 gate.
10. **T-039** — the ticket asks the test to assert address me's body contact kills; D-065 (FINAL) says
    it has no body contact. Built the FINAL reading. **Still blocked: your ruling.**
11. **T-054** — DESIGN.md §10 wants "tripmine particles vs platform light ≥ 3.0", which is unsatisfiable
    by any platform hex given the fixed `#FF4FD8` tell (measured 1.064–2.029 across five biomes; even
    pure white caps at 2.675–2.703). No colour or threshold moved. **Still blocked: your ruling.**
12. **T-087** — contact kills (kiwi cat, toucher, gift Larper, YOU?!, gin, Isagi) have no wind-up, so a
    "binding cue that precedes the attack" cannot exist for them. Built them as proximity tells with
    `binding_cue = null`. **Still blocked: accept as uncueable, or commission pre-attack cues.**
13. **T-087** — coil's 0.6 s boing cannot both match the §3 row length and span the 36-tick cue plus
    165-tick flight. Exempted via the parked field. **Still blocked: your ruling.**
14. **T-087** — Claude's drums and wind fire ON the beat, and their kill ticks are distance-dependent,
    so "cue ends on the attack tick ±1" is unsatisfiable in principle. **Still blocked: your ruling.**
15. **T-087** — gin's `crack_rumble` ends on the launch tick (120), 18 ticks before the zone opens
    (138). `shing` is the clean binding witness for the same attack. **Still blocked: your ruling.**
16. **T-051** — RESOLVED, kept for the record.
17. **T-081** — the done-when says "AUDIT.md receives the report as an appendix", but AUDIT.md did not
    exist. **UNBLOCKED NOW: AUDIT.md exists (`b0c6b3d`, 817 lines) and already carries T-081's report as
    its §10 appendix.** This row can be closed with no ruling.
18. **T-075** — the answer lab passes 1 of 29 pairs (nuke on flat_lane, 100 %/0 %). Two named causes:
    four enemies are not lethal to a still player by design, and the executor's press timing does not
    model the contact windows. **Still blocked: your reading of D-T075-4, plus harness work.**
19. **T-ART-TOUCHER** — the brief wants a distinct frame per state, but `frame_map` is global per enemy
    and the spec names are pinned. Built per-state files with `frame_map` resolving the pinned names.
    **Still blocked: your ruling on which reading stands.**
20. **APP-FLOW** — RESOLVED.
21. **MENU** — RESOLVED.
22. **TICKET LOADING** — the 2.0 s restart contradicts DESIGN.md §2's CANON "≥ 5.0 s shown". Built your
    FINAL ruling. **Still blocked: you need to update DESIGN.md §2, §14, AUDIT.md C1 and FLEET_PACK
    A12 to the two-duration law.**
23. **TICKET LOADING** — "no loading screen between levels" vs "the screen appears on every level load".
    **Still blocked: your reading, and it interacts with A12's `gate_to_level ≤ 2.0 s` budget.**
24. **FIX-A3** — A3 measures 82/100 against a required 95. **Still blocked: a design ruling from you**
    (bot competence vs terrain/enemy tuning). This is the one criterion blocking the alpha tag.

**Count: 24 parked rows, 3 resolved, 21 open, 1 unblocked now (#17), 1 partially unblocked (#4).**
The other 19 need a ruling from you or unimplemented work.

---

## 6. THE 16 [POST-RUN] PREFLIGHT ITEMS

`research/fable-preflight.md` items 8–23. For each: does the night's telemetry confirm or refute it, and
what I recommend. **I applied none of these fixes.** Each is written as a proposed ticket marked
`[OWNER-RULING-NEEDED]`.

| # | item | telemetry verdict | proposed ticket |
|---|---|---|---|
| 8 | Overtime/chaser curses make floaters faster than the player | **NOT MEASURABLE.** Overtime tier at beacon entry was **median 0 (n=53)** — overtime never engaged in any bot run, so the tier-6 case never occurred. The arithmetic in the data is unchanged (toucher 6.75 u/s at ceiling 0.75). | `[OWNER-RULING-NEEDED]` TUNE-OT-CAP: cap any floating enemy at 85 % of base run speed. **Recommend: defer** — no run reached the regime, so there is no evidence either way. |
| 9 | Levels are far shorter than the timings the economy assumes | **CONFIRMED, strongly.** L1 median **45.0 s** against a **90 s** target (50 %). L10/20/30 unmeasurable — no run reached level 6. | `[OWNER-RULING-NEEDED]` TUNE-LENGTH: lengthen paths or shorten the overtime period (20 s → 10 s). **Recommend: do the cheap data change first** (overtime period), because lengthening paths is a generator version bump. |
| 10 | Field Dressing is priced for the old game | **WORSE THAN MIS-PRICED — IT IS INERT.** `on_void_fall` is called from nowhere in `game/sim/`; 0 free falls in 46 falls. Purchase data is unavailable (the bot buys nothing). | `[OWNER-RULING-NEEDED]` IMPL-FIELD-DRESSING: implement the `on_void_fall` call site, then re-price. **Recommend: implement first, price second** — re-pricing an upgrade that does nothing is wasted. |
| 11 | Sure Foot + free falls turns the void into a dodge | **NOT MEASURABLE.** No purchase data (bot buys nothing); 0 free falls observed. | `[OWNER-RULING-NEEDED]` TUNE-SUREFOOT: cap invulnerability at 2.0 s, none on a free fall. **Recommend: fold into IMPL-FIELD-DRESSING** — both are the same void-fall economy. |
| 12 | Hungry Void is still rated a mid-severity opener | **PARTIAL SIGNAL.** `hungry_void` was offered 5 times and picked **0 times (0 %)** in 25 runs. That is consistent with it being a trap, but 5 offers is too few to conclude. | `[OWNER-RULING-NEEDED]` TUNE-HUNGRY-VOID: Brutal, min level 8. **Recommend: yes** — 0/5 picks plus the paper argument is enough for a data change. |
| 13 | Brittle breaks the feel budget (2.4 s respawn vs ≤ 2.0 s) | **NOT MEASURABLE from bot runs.** `feel_probe.gd` measures the base `void_fall_to_respawn 0.800 s ≤ 0.80`; Brittle's 2.4 s is not exercised. | `[OWNER-RULING-NEEDED]` TUNE-BRITTLE: 2.0 s. **Recommend: yes** — it is a one-number data fix against a stated budget. |
| 14 | Crumbling now covers most of the level | **NOT MEASURABLE.** T-081's own report says walkway width is not in the records; I confirmed the same gap. | `[OWNER-RULING-NEEDED]` TUNE-CRUMBLING: restrict to shortcut bridges and drop ledges. **Recommend: yes on the paper argument**, but add slot width to `level_start` first so it can be measured. |
| 15 | Slippery curses are rated Mild | **NOT MEASURABLE.** No friction stat exists in the controller or the stat list; no telemetry field. | `[OWNER-RULING-NEEDED]` TUNE-SLIPPERY: Harsh + add a friction stat. **Recommend: yes** — the missing stat is the real defect. |
| 16 | Bunker Buster pays a Brutal bounty for almost nothing | **NOT MEASURABLE.** No purchase data. | `[OWNER-RULING-NEEDED]` TUNE-BUNKER-BUSTER: replace the effect or make it Mild. **Recommend: make it Mild** — cheapest, no new mechanic. |
| 17 | Seal's counter-play is impossible on 1-wide paths | **WEAK SIGNAL.** Seal caused **1 death of 25 (4 %)**; no sidestep attempts are recorded. | `[OWNER-RULING-NEEDED]` TUNE-SEAL-TEXT: the dash holds its starting height; reword. **Recommend: reword only** — the death rate does not justify a mechanic change. |
| 18 | Toucher's write-up still describes a wall | **NO SIGNAL.** Toucher caused **0 deaths** in 25 runs and was not in the level-1..5 roster draws. | `[OWNER-RULING-NEEDED]` TUNE-TOUCHER-TEXT: reword the counter-play. **Recommend: reword only.** |
| 19 | The last-safe-tile ring rarely updates on thin paths | **NOT MEASURABLE.** No telemetry field for safe-tile ring updates. | `[OWNER-RULING-NEEDED]` TUNE-SAFE-TILE: 0.1 s as a data value. **Recommend: yes** — one data value, no code. |
| 20 | Binding timings versus tune-to-band | **CONFIRMED as a live tension.** T-075's answer lab passes **1 of 29 pairs**; the timings are binding and the bands are not met. | `[OWNER-RULING-NEEDED]` RULE-TIMINGS: timings binding, bands are a report in run 1. **Recommend: adopt this reading explicitly** — it is already how the build behaves. |
| 21 | Late-game content may be unreachable | **CONFIRMED.** Median level reached **3**, maximum **5**. T4 starts at level 18, T5 at 26. **No run has ever seen them.** | `[OWNER-RULING-NEEDED]` TUNE-LATEGAME: wait for bot data, then lower the tier gates or accept. **Recommend: lower T4/T5 gates** once A3 is fixed — right now they are unreachable content. |
| 22 | Small wording contradictions | **DOC-ONLY, not telemetry.** Still present (e.g. "re-rolls the level's mines"). | `[OWNER-RULING-NEEDED]` DOC-SWEEP: fold into T-091 (the dead-vocabulary sweep in the backlog). **Recommend: yes, as part of T-091.** |
| 23 | The owner's summary said "2 per level" | **CONFIRMED as built.** Charges carry over; the beacon restores exactly 1 (0→1, 1→2, 2→2), pinned by `test_gifts.gd:231`. 24 real gains over 53 beacon entries. | `[OWNER-RULING-NEEDED]` CONFIRM-D-050: confirm charges carry over with no per-level reset. **Recommend: confirm D-050 as built** — the code and the test already agree. |

**Summary: 4 confirmed by telemetry (9, 20, 21, 23), 1 confirmed-worse (10), 1 partial (12), 9 not
measurable from the current records (8, 11, 13, 14, 15, 16, 19, 22, and 17/18 weak), 0 refuted.**
The honest headline: **most of these cannot be settled by bot telemetry**, because the bot buys nothing,
never reaches overtime, and never gets past level 5.

---

## 7. FUN RISKS 1–3

From `research/fable-funrisks.md`, with whatever signal data exists.

### Risk 1 — "Dying is instant and restarting is slow" (threshold: above ~8 s, expect quits)

**REFUTED as stated, with one unmeasured gap.** The risk's premise is "each death costs ≥ 5 s of
loading". Your own later FINAL ruling (D-LOAD-5) made restarts **2.0 s**, not 5.0 s. Measured
components from `feel_probe.gd`:

| component | measured |
|---|---|
| death → run-over screen | **0.0068 s** |
| restart loading hold | **2.000 s** |
| gate → level controllable | **0.182 s** |
| **measured pipeline total** | **≈ 2.19 s** |

That is well under the 8 s threshold. **The gap: the lobby walk is not measured** — it consumes no sim
ticks, so no record carries it (T-081 says the same). A stopwatch on the first playable build is still
the only way to close it.

### Risk 2 — "Deaths you did not see coming" (threshold: above 25 % reads as unfair)

**REFUTED on current main — 16.0 %, down from 59.6 %.** Fresh logs: **4 of 25 deaths (16.0 %)** had the
killer off-screen, against T-081's 59 of 99 (59.6 %). The improvement tracks the death-cause flip: the
killer is now usually an enemy body in view rather than the void. Caveat: n=25 is small, and a bot's
camera is not a player's.

### Risk 3 — "The terrain kills more than the enemies do" (threshold: above 50 % of charges, paths are the antagonist)

**CONFIRMED on the charge signal, REFUTED on the death signal.**

- **Charges: 42 of 46 (91.3 %) were terrain-caused** — no enemy within 10 u, no push in the previous
  120 ticks. Against a 50 % threshold, **the paths are still the antagonist.** This is the risk's own
  stated signal and it fires hard.
- **Deaths: only 4 of 25 (16.0 %) were terrain-caused**, down from 59.6 %. The enemies now do the
  killing.

So the game is no longer "a precision platformer with enemies as decoration" in its *lethality* — but it
still is in its *economy*: the terrain is what costs you the charges you need to survive the enemies.

---

## 8. ART WAVE — re-verified, not redone

The 17 source images are present in `assets_src/enemies/` (17 images + `README.md` = 18 entries). I
re-ran the validation rather than trusting the log:

| check | real final line |
|---|---|
| `validate_sprites.gd` | **`SPRITES OK 515 checks over 12 sprites.json`** (exit 0) |
| `fog_check.gd` | **`FOGCHECK OK (550 checks over 5 biomes)`** (exit 0) |
| `test_billboard.gd` | **PASS** (in the gate's `TESTS 59 passed 0 failed`) |
| `test_hitbox.gd` | **PASS** |
| `test_anim_sync.gd` | **PASS** |
| `test_kill_api.gd` | **PASS** |

Per-enemy state: **11 of 12 enemies are `tbd: false`** with real art — address_me 6 frames, coil 5,
gift_larper 6, gin 5, isagi 9, kiwi_cat 4, nuke 4, seal 7, thicc_ben 5, toucher 16, you 22 = **102
frames**. **Claude is the one exception** (`tbd: true`, 13 frames): its 10 logo-derived frames are real,
but `plushie_00..02` are still magenta placeholders because the clawd Crab source was never fetched
(TBD.md row 26). That is the only placeholder art left in the build, and it is the mechanic that calms
Claude — so a player meets three magenta rectangles in the first Claude fight.

---

## 9. WHAT THE BUILD CAN AND CANNOT DO RIGHT NOW

| question | answer | evidence |
|---|---|---|
| **Does level 1 load?** | **Yes.** MENU → LOADING → WORLD works, and the world builds a real level. | `test_app_flow.gd` PASS in the gate; `app.gd` state machine MENU/LOADING/WORLD. |
| **Is it completable by the bot?** | **Mostly — 82 of 100 seeds (A3 FAIL, needs 95).** My independent 25-seed sample: 23/25, failing on exactly the two seeds FIX-A3 predicts. | `PARKED.md` #24; my `out/run_logs/` analysis. |
| **Does the exe finish a level now that APP-LOOP landed?** | **The code can. The exe on disk cannot.** `world.gd` ticks gifts/mines/beacon and `test_app_loop.gd` passes — but `build/voidwrap_run.exe` is dated 14:48, APP-LOOP merged at 23:08, and the binary contains none of APP-LOOP's symbols. **It needs a re-export.** | `stat` on the exe; `git log -1 --format=%ci 2e80d27`; binary grep for `is_complete`/`level_completed`/`try_enter` → 0. |
| **Does a full 30-level run exist?** | **No.** Completing a level returns to the MENU (D-APP-LOOP-4: the intermission lobby is unimplemented). The bot's best is level 5; median 3. | `app.gd:156` `_on_level_completed` → MENU; `run_end.level_reached` median 3, max 5. |

**One sentence: this build is a green, well-tested game engine with real art and a working single level
that a bot clears 82 % of the time — but the exe you have predates the fix that makes a level
completable, and there is no second level to go to.**

---

## 10. THE BACKLOG — BLOCKED, and I did not start it

**Phase 3 step 8 was blocked by the no-commits rule and needs your go-ahead.** The brief says to
continue the `[OPTIONAL-BACKLOG]` in FLEET_PACK.md §10.3 "one ticket at a time with a gate re-run after
each merge". A merge is a commit, and I may not commit. So I started none of them.

The seven tickets, with a one-line recommendation each:

| ticket | what it is | recommendation |
|---|---|---|
| **T-090** | Cross-ticket bug review — re-read all merged diffs, hunt contradictions | **Do it.** This pass already found four cross-ticket defects (stale exe, `run_batch.ps1`, the `YOU`/`YOU?!` split, TBD.md) that a systematic sweep would have caught. |
| **T-091** | Dead vocabulary sweep — zero hits for "damage", "HP", "rooms", "hop", "2 per level" | **Do it, and fold in preflight #22.** Cheap, and it is the kind of thing that embarrasses a public repo. |
| **T-092** | Validator selftest expansion — 15 → 25+ planted defects | **Do it.** The selftest is the only thing proving the validator can fail; 15 is thin for a 5,000-seed oracle. |
| **T-093** | Determinism fuzz — 10 seeds × 3 byte-identical, plus a 20,000-seed pass | **Do it.** Determinism is load-bearing for A4 and the replay proof. |
| **T-094** | Loading tip pool — 30 tips, one per death attribution screen, each true | **Do it after the `YOU`/`YOU?!` fix**, or the tips will name a killer the screen does not. |
| **T-095** | README and HOW-TO-PLAY rewritten to match charges/instakill/beacon restore | **Do it.** The README is the first thing a public visitor reads. |
| **T-096** | Death attribution edge cases — every killer name renders, no orphan codes | **Do it first of the seven.** It is the direct fix for the `YOU`/`YOU?!` drift I found, and it is small. |

**My ordering if you green-light it: T-096 → T-090 → T-091 → T-095 → T-092 → T-093 → T-094.**

---

## 11. WHAT I DID NOT DO

- No commits, no pushes, no branches, no merges. `git status --short` shows only the two pre-existing
  modified run-record files.
- No tracked file modified. This report is the only new file.
- No design-shaped fix applied. Every recommendation above is a proposal, not a change.
- I did not re-export the exe (that writes a binary), did not fix `run_batch.ps1`, did not fix the
  `YOU`/`YOU?!` data, and did not touch TBD.md's contradictions — all are reported, none applied.
- I did not run the 100-seed A3 sweep (≈35 min); I ran 25 seeds and cross-checked them against FIX-A3's
  published failure list instead, which reproduced it exactly.
- I did not measure the lobby walk (risk 1's remaining gap) — it consumes no sim ticks and needs a
  stopwatch on a real build.
