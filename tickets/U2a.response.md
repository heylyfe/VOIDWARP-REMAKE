# U2a response - the tester panel's enemy list (cycle 8, U2a)

**Verdict: DONE** (see VERIFY below for the tails)

Branch `t3/u2a-scrollable-registry-list`, started on `925ce91` (the ticket's own WIP commit, kept
as-is), one finishing commit on top; working tree clean at report time. The predecessor base
`97ecabd` had been reset to as the first command (R11) and read in full before anything changed;
nothing of D-T2-10's work was redone - the popup cap, the row-fit restructure and the Peter routing
carry forward inside the new shape.

## What changed

1. **The picker is an in-panel scroll list, not a popup.** The enemy OptionButton is
   gone. Choosing an enemy now happens inside the panel's own column: a plain `Control`
   host (fixed minimum height - a plain Control never grows with its children, D-T2-10's
   row-fit rule used vertically), a `ScrollContainer` with horizontal scrolling DISABLED
   anchoring it (rows can never run past the 370-px column), and a `VBoxContainer` of
   full-width row Buttons inside it at full height. The host is bounded at
   `LIST_CAP_H = 176` px (`min(height, cap)`); the list above shows every registry enemy
   plus the pinned Peter row at its full computed height (13 rows, 568 px measured), so it
   always overflows and scrolls IN PLACE; the LAST row is one wheel-turn away at any window
   size. F10, SPAWN AHEAD and SPAWN AT CURSOR are unchanged; the upgrade picker keeps its
   OptionButton and its D-T2-10 popup cap (the owner's complaint names the ENEMY list).
   *Not an ItemList, on measured facts:* this engine build has no
   `ItemList.fixed_item_height` (runtime assignment error) and `ItemList` reports a
   (0, 0) combined minimum for a 13-item list even with the fork's `set_auto_height(true)`,
   so neither the bound nor the reachability arithmetic can be built on it
   deterministically. Row Buttons in a VBox use the same deterministic minimum-size
   arithmetic D-T2-10's 409-px diagnosis used, and a row's own `pressed` signal IS the
   panel's selection path (`_pick_enemy_row`).
2. **The spawn path is ONE call, unguarded.** `_spawn()` computes the position (unchanged
   geometry: ahead along the look's ground shadow, or at the cursor's ground point) and
   makes exactly one call - `world.tester_spawn_enemy(id, pos)` (U2b, D-T2-13). The panel
   keeps no second spawn path (its own `_behavior_for`/`_cfg_for`/`rt.spawn_at` chain is
   deleted from the file) and no `has_method` guard. The pinned Peter row routes to the
   FORCE PETER machinery exactly as before. Per the brief's merge order, the U2b branch
   (tip 316ac26, gate-green, finalized; the method was not on main yet) was merged as
   `de333fc` - merge order U2b first, exactly what the owner's merge will replay.
3. **Tests (`game/tests/test_tester_build.gd`, the (h) leg rebuilt on the real boot).**
   The suite boots the real app to a live WORLD level (that boot IS the
   tester-build-still-starts leg) and then, in one deterministic session (seed 7311,
   level 1):
   - every `enemy_ids()` id is listed EXACTLY ONCE, plus exactly one pinned Peter row
     (and Peter is asserted to be NOT registry content);
   - Claude and gin are additionally asserted BY NAME (the owner names them): id in the
     registry, the registry display name says the name, the row's label says the name;
   - no Window-mode node anywhere in the enemy-picking subtree (a PopupMenu is a Window
     in this engine), the viewport is bounded at 176 px while the list content carries
     every row, vertical scrolling is on, horizontal scrolling is off, and the
     overflow-plus-scroll arithmetic that puts the LAST row in the wheel range is
     asserted explicitly;
   - the widest-row rule at BOTH 1280x720 and 1920x1080 (root size set and restored):
     no HBox row of the panel column is wider than the 370-px column;
   - for EVERY registry id, BOTH spawn buttons: the row's own `pressed` signal selects,
     `_spawn` runs, and the enemy is read BACK BY ID from `world.rt.enemies` (+1 row per
     id per button, in play, finite position, body mirror grown, status line reporting);
   - Peter routes to the boss machinery: the boss instance exists after the press, the
     arena is NOT entered before the tick, IS entered after one `world.step`, and NO
     `peter` row EVER appears in the enemy runtime;
   - the no-regression pins on the SAME boot: meta line + sha256 hash probe, GIVE GOLD
     purse delta, GIVE N GIFTS through the queued tick job (exactly one more slot reads
     `collected()`, the phase stays black, the level stays alive), GIVE +1 STACK into
     the run ledger, SET CHARGES on the controller, GOD MODE mirror + invuln window,
     FORCE COLLAPSE leaving the schedule's idle phase, FORCE BANKAI's honest no-boss
     fallback, the level's jump pads (this seed pins 2), and SKIP LEVEL opening the
     Antechamber (last - it tears the world down).
4. **A real bug found and fixed by the new pin (D-T2-12).** The queued give-gifts job
   was `Callable(self, "_run_give_gifts").bind(n)` called as `run.call(ev)`, but
   `Callable.bind()` appends its values AFTER the call-time argument - so the
   `(n: int, ev: Array)` signature had `n` receiving the event Array and the job died
   with "Cannot convert argument 1 from Array to int" the first time anyone drove it
   through a real `world.step()`. Fixed by swapping the signature to `(ev, n)` - when the
   new gift pin ran, it failed loudly with the panel's own status line still promising
   "giving 1 gift(s) on the next tick".
5. **Garbage reads can no longer fake a pass.** Mid-suite work on this file exposed that
   a torn-down world swallowed errors into false passes (found while the gift leg swept
   all 40 gifts - the level's own completion path - and the spawn legs then "passed"
   against Nil reads). Every leg that reads the live world now guards
   `is_inside_tree()` first and reports the death as a failure.
6. **The finishing pass: one hole in the geometry teeth, closed (and the panel's header
   comment corrected).** Re-running the negative controls on the finished tree showed the
   third one was only half true: the bound could not GROW past the cap, but REMOVING the
   bound outright (`custom_minimum_size` left unset, i.e. a 0-px viewport that shows no
   row at all - the owner's "cut off" failure from the other side) still PASSED. The
   geometry leg now also asserts the viewport is at least one `LIST_ROW_H` tall, and that
   mutation fails loudly. The file's header block still described an `ItemList` in the
   picking chain (the code has had row Buttons since 19:25Z); it now describes the real
   chain. No threshold moved and no assertion was removed - one assertion was added.

## Negative controls (each fired, then reverted with `git checkout`)

| mutation | result |
|---|---|
| bypass the Peter routing to the runtime | Peter leg fails: "the Peter row did not create the boss instance" |
| double the pinned Peter row | contents leg fails TWICE: "the enemy list holds 14 rows; want the 12 registry ids plus Peter (13)" + "the pinned Peter row must list EXACTLY once (got 2 rows)" |
| make the bound stop capping (`maxf` for `minf`) | geometry leg fails TWICE: "the enemy list viewport grew to 568 px" + "a 13-row list claims to fit its 568-px viewport" |
| remove the bound outright (viewport collapsed to 0 px) | **passed before the finishing pass**; now fails: "the enemy list viewport is 0 px tall - it must show at least one 26-px row (a bound of nothing hides the whole roster)" |

## Files touched

- `game/view/tester/debug_panel.gd` - the picker chain, the row buttons + selection, the
  single `tester_spawn_enemy` call, the gift-job signature fix, the header comment (this pass).
- `game/tests/test_tester_build.gd` - the (h) leg rebuilt; regression pins; guards; the
  not-collapsed viewport tooth (this pass).
- `DECISIONS.md` - D-T2-11 and D-T2-12 (inserted before U2b's D-T2-13 so the section's
  numbering stays ascending); D-T2-11 updated with the measured 568-px content height, the
  fourth negative control and the tooth it added (this pass).
- `RUNLOG.md` - the U2a event lines, including this pass.
- `tickets/U2a.response.md` - this file.
- Merge commit `de333fc` brings U2b's own files in (`game/app/world.gd`,
  `game/sim/clawds.gd`, `game/tests/test_tester_claude_swarm.gd`,
  `tickets/U2b.response.md` and U2b's docs) - that is U2b's gate-verified work, merged
  per the brief's merge order, not edited by me.

## Deviations

- The merge commit of U2b's branch (not main, which has not received U2b yet) - without
  it the spawn legs cannot run at my tip, and the brief pins the order U2b first.
- The list is a VBox of row Buttons, not an ItemList; the brief said "for example an
  ItemList", and this engine build's ItemList cannot carry the measured proof (no
  `fixed_item_height`, zero content minimum). D-T2-11 records the measurement.
- The gift regression pin reads the gift bitset, not the purse: black-phase gifts pay
  nothing by design (the chain is gold-phase), and sweeping ALL gifts is the level's
  own completion path. The gold payout path stays pinned in sim/economy's own suite.
  (The live evidence run below prints the purse delta too - it is 0, which is why the
  pin reads the bitset.)
- The queued give-gifts job's parameter order changed in the panel (D-T2-12) - strictly
  inside my two owned files.

## The D- entries

- `D-T2-11` - the picker is an in-panel bounded scroll list; why the popup is gone; why
  not an ItemList (measured); the test teeth; the negative controls (now four).
- `D-T2-12` - the queued gift job's argument order (`bind()` appends AFTER the call
  argument), found by the new pin, fixed by swapping the signature.

## VERIFY

### 1. Targeted suites, one file each (real boot, real sim)

`<godot> --headless --path game --script res://tests/_probe_one.gd -- res://tests/test_tester_build.gd`

(`_probe_one.gd` is a throwaway one-file runner - it loads the given test and calls its `run()`
exactly as `run_all.gd`'s `_run_one` does - untracked, and deleted before this commit; only its
output is quoted here.)

```
app: run seed=7311 level=1
app: lobby level_completed=1 purse=25
PROBE PASS res://tests/test_tester_build.gd
```

`... -- res://tests/test_tester_claude_swarm.gd` (U2b's swarm coverage, unchanged by this pass)

```
PROBE PASS res://tests/test_tester_claude_swarm.gd
```

### 2. Live evidence readout from the REAL panel in the REAL booted app

A throwaway readout (untracked, deleted before the commit) booted the app to a live WORLD level,
hosted the real `view/tester/debug_panel.gd`, opened it, and pressed the real rows - no assertions,
only printed observations, so the claims above are recorded from the UI itself:

```
EVIDENCE boot state=WORLD advances=20 seed=7311 level=1
EVIDENCE row  0 id=address_me     label=address me (address_me)
EVIDENCE row  1 id=claude         label=Claude (claude)
EVIDENCE row  2 id=coil           label=coil (coil)
EVIDENCE row  3 id=gift_larper    label=gift Larper (gift_larper)
EVIDENCE row  4 id=gin            label=gin ichimaru (gin)
EVIDENCE row  5 id=isagi          label=Isagi (isagi)
EVIDENCE row  6 id=kiwi_cat       label=kiwi cat (kiwi_cat)
EVIDENCE row  7 id=nuke           label=nuke (nuke)
EVIDENCE row  8 id=seal           label=seal (seal)
EVIDENCE row  9 id=thicc_ben      label=thicc ben (thicc_ben)
EVIDENCE row 10 id=toucher        label=toucher (toucher)
EVIDENCE row 11 id=you            label=YOU?! (you)
EVIDENCE row 12 id=peter          label=Peter Griffin (peter)
EVIDENCE registry_ids=12 rows=13 (registry + 1 pinned Peter) list_content_h=568 viewport_cap=176
EVIDENCE spawn id=address_me     rows 0->1 status=spawned address me at (1.5, 0.0, -2.5) ahead of the player clawds=none
EVIDENCE spawn id=claude         rows 0->1 status=spawned Claude at (1.5, 0.0, -2.5) ahead of the player clawds=none
EVIDENCE spawn id=coil           rows 0->1 status=spawned coil at (1.5, 0.0, -2.5) ahead of the player clawds=none
EVIDENCE spawn id=gift_larper    rows 0->1 status=spawned gift Larper at (1.5, 0.0, -2.5) ahead of the player clawds=none
EVIDENCE spawn id=gin            rows 0->1 status=spawned gin ichimaru at (1.5, 0.0, -2.5) ahead of the player clawds=none
EVIDENCE spawn id=isagi          rows 0->1 status=spawned Isagi at (1.5, 0.0, -2.5) ahead of the player clawds=none
EVIDENCE spawn id=kiwi_cat       rows 0->1 status=spawned kiwi cat at (1.5, 0.0, -2.5) ahead of the player clawds=none
EVIDENCE spawn id=nuke           rows 0->1 status=spawned nuke at (1.5, 0.0, -2.5) ahead of the player clawds=none
EVIDENCE spawn id=seal           rows 0->1 status=spawned seal at (1.5, 0.0, -2.5) ahead of the player clawds=none
EVIDENCE spawn id=thicc_ben      rows 0->1 status=spawned thicc ben at (1.5, 0.0, -2.5) ahead of the player clawds=none
EVIDENCE spawn id=toucher        rows 0->1 status=spawned toucher at (1.5, 0.0, -2.5) ahead of the player clawds=none
EVIDENCE spawn id=you            rows 0->1 status=spawned YOU?! at (1.5, 0.0, -2.5) ahead of the player clawds=none
EVIDENCE unlisted=0
EVIDENCE claude_swarm after_one_tick spots=7 anger_ticks=1
EVIDENCE gift present=40 collected 0->1 phase=black purse 0->0 status=collected 1 gift(s) nearest-first
EVIDENCE peter boss_before_tick=true status=boss fight queued - the arena entry runs on the next tick
EVIDENCE peter boss=true arena_entered=true runtime_rows 12->12 peter_rows=0
EVIDENCE done state=WORLD live=true
```

Read it as the owner's three asks: 12 registry enemies + Peter = 13 rows, `unlisted=0`, every id
spawned (runtime rows 0->1 by id, status line naming the enemy), the Claude row grew the clawd swarm
on the next tick (7 spots, anger timer already at 1 - the attach really ran in the tick), the gift
button collected exactly one gift through the queued job, and Peter entered the boss arena with
`peter_rows=0` (he never reached the enemy runtime).

### 3. Full gate

`powershell -File tools/gate.ps1` (this checkout's tree, main-checkout engine, run last - after every
code and doc change of this pass):

```
GATE C:\Users\Nathan\.t3\worktrees\VOIDWARP-REMAKE\t3-1be8a270-af0e0baf1f3f511a
STEP 1 python oracle checks
  > python.exe terrain_ref\test_validate.py            SELFTEST 18/18   TESTS OK
  > python.exe terrain_ref\validate.py --selftest       SELFTEST 18/18
  > python.exe terrain_ref\gallery.py --check           GALLERY 16/16 OK
OK   python oracle checks (TESTS OK, SELFTEST 18/18, GALLERY 16/16 OK)
STEP 2 terrain parity
    PARITY 56/56 OK
    GALLERY_PIN 16/16 pinned-gallery records match
OK   terrain parity (PARITY 56/56 OK)
STEP 3 run_all
    PASS res://tests/test_tester_build.gd
    PASS res://tests/test_tester_claude_swarm.gd
    TESTS 143 passed 0 failed
OK   run_all (TESTS 143 passed 0 failed)
OK   boundary scan (ran in run_all: game/tests/test_boundaries.gd)
OK   content schema (ran in run_all: game/tests/test_content.gd)
OK   drop-in fixture (ran in run_all: game/tests/test_dropin.gd)
OK   replay determinism (ran in run_all: game/tests/test_replay.gd)
STEP 8 sprite validator                              OK   sprite validator
STEP 9 fog readability                               OK   fog readability
GATE OK (9 ran, 0 skipped)
GATE_EXIT=0
```

`GATE_EXIT=0`, `TESTS 143 passed 0 failed`, no `SCRIPT ERROR` line anywhere in the suite tail, no
step skipped. Two earlier runs of the same gate in this pass were also green (`GATE OK (9 ran, 0
skipped, 560 s)` and `... 626 s`, `TESTS 143 passed 0 failed` each) - the pass re-ran it after every
tree change instead of trusting the first. The elapsed-seconds figure printed by the last run
(`29371 s`) is the runner's `Get-Date` arithmetic after a clock correction on this machine, not a
measurement of anything the gate asserts; the two earlier runs printed 560 s and 626 s for the same
work. No threshold is involved.
