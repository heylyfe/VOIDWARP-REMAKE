# T-083 - Enemy animation data (enemies 7-12: gift Larper, toucher, seal, address me, Claude, gin ichimaru)

Delivered on the working branch (this worktree). NO CODE was added to the game; the `anim` blocks
are data. Gate green (output at the bottom of this file).

## What landed

- An `anim` block in each of `game/content/enemies/{gift_larper,toucher,seal,address_me,claude,gin}/sprites.json`:
  one entry per state of its section 1.x table (the tables in research/fable-tickets.md, sections
  1.7-1.12 - the animation tables ARE the spec), each entry carrying:
  - `frames` - file names relative to the enemy folder (the T-016 names; the section 1.0 rename
    is done in sprites.json, never in the spec - D-T083-1);
  - `loop` - yes/no (skipped on "-" cells, enforced where the table states one);
  - `ticks_per_frame` or explicit `tick_ranges` (coil has none of mine; the table's fps rows are
    converted exactly: D-T083-3);
  - `duration_ticks`;
  - `effect` - the billboard/world effect name - and `effect_params` with the table's parameters
    (and section 2.x where the table points there, e.g. gift Larper's particles per section 2.1);
  - `timing_note` - the table's stated timing in prose, verbatim numbers, including [CONTESTABLE]
    markers where the table carries them (e.g. address me's 12-tick spawn).
- `game/tools/check_anim_data.gd` (new; did not exist): proves every state of every section 1.x
  table exists with the tables' tick counts and that every referenced frame file exists on disk.
  Accepts a list of enemy ids on the command line (`-- kiwi_cat coil ...`) so the sibling half
  (enemies 1-6) can be checked with the same binary; no arguments = all 12. Per-enemy PASS/FAIL
  plus a final count line; exit 0 iff every checked enemy passes, 1 otherwise, 2 on usage errors.
  The section 1.x tables for all 12 enemies are embedded (transcribed 1:1, fps converted exactly).
  TBD sheets (all 12 today) are existence-checked but relaxed on frame names/counts; non-TBD
  sheets additionally require at least as many distinct referenced frames as the table lists.
  States an anim block carries that are NOT in its table are printed as NOTE, never failed.
  See D-T083-8/D-T083-9 for the contract details.
- DECISIONS.md: entries D-T083-1 .. D-T083-11 (before `## Handover log`).
- TBD.md: rows 22-27 (this ticket).
- PARKED.md: no rows added - no ENEMIES.md/FINAL/other-ticket contradiction was found for these
  six enemies.
- ENEMIES.md, DESIGN.md, FLEET_PACK.md: untouched.

## Anim states per enemy (36 total) and the binding timings kept exactly

| enemy | states | binding tick counts (from the table) |
|---|---|---|
| gift Larper (1.7) | spawn, idle, telegraph, attack_detonation, defused | idle 1 rev / 4.0 s (binding) = 48 ticks/frame; detonation 18 ticks on the contact tick; defused 24 ticks |
| toucher (1.8) | spawn, idle, telegraph, attack_infect, attack_touch, recover | idle 10 fps = 6 ticks/frame; telegraph = the 18 ticks before each infection (infection every 120 ticks = 2.0 s, binding) at 20 fps = 3 ticks/frame; infection on the infection tick |
| seal (1.9) | spawn, idle, telegraph, attack, recover | flap 9 ticks/frame; telegraph 45 ticks (0.75 s) binding; attack (dash) 60 ticks (1.0 s) binding, 20 u, bark on tick 0, 4 ticks/frame flap overlay; recover 45 ticks |
| address me (1.10) | spawn, telegraph, leaves, attack, recover | spawn 12 ticks ([CONTESTABLE] in the table); countdown 300 ticks (5.0 s) binding; attack shown on tick 300 = the tick the kill resolves, 24 ticks; leaves 18 ticks |
| claude (1.11) | spawn, idle, telegraph_drums, attack_drums, telegraph_strings, attack_strings, attack_wind, deadline, plushie_idle | beat = 36 ticks at 100 BPM, shortened by tempo = 100 + 0.6 x agitation (2/s, Deadline at 100); drums telegraph = the beat BEFORE beats 1 and 3; strings telegraph = one full beat (36 ticks), sweep = 120 deg over 4 beats (144 ticks at 100 BPM); wind shots on beats 1/2/3; plushie_idle 6 fps = 10 ticks/frame |
| gin ichimaru (1.12) | spawn, idle, telegraph, attack_launch, attack_void_zone, recover | telegraph (mark) 120 ticks (2.0 s) binding; launch shown on tick 120, spears travel 18 ticks (0.3 s); void zone starts on tick 138 (the tick the tiles become non-solid), lasts 600 ticks (10 s); recover: tiles fade back over 30 ticks, cooldown 840 ticks (14 s) |

The telegraph fills its cue exactly and the attack frame lands on the tick the attack resolves,
by construction: every timing in the tables above is copied into `duration_ticks` /
`ticks_per_frame` unchanged, and the checker enforces them.

## Verification (real command output, run in this worktree)

The checker, my six:

    > "C:\Users\username\Documents\REMAKE VWR\VOIDWARP-REMAKE\tools\godot\godot.exe" --headless --path game --script res://tools/check_anim_data.gd -- gift_larper toucher seal address_me claude gin
    Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

    PASS gift_larper (5 states)
    PASS toucher (6 states)
    PASS seal (5 states)
    PASS address_me (5 states)
    PASS claude (9 states)
    PASS gin (6 states)
    CHECK-ANIM-DATA 6/6 enemies passed, 36 states checked

The full run today (the sibling half has not landed its anim blocks yet; expected, clean failure):

    > ... --script res://tools/check_anim_data.gd -- kiwi_cat coil thicc_ben isagi nuke you
    FAIL kiwi_cat: no "anim" block in content/enemies/kiwi_cat/sprites.json (T-083 adds one per enemy)
    FAIL coil: no "anim" block in content/enemies/coil/sprites.json (T-083 adds one per enemy)
    FAIL thicc_ben: no "anim" block in content/enemies/thicc_ben/sprites.json (T-083 adds one per enemy)
    FAIL isagi: no "anim" block in content/enemies/isagi/sprites.json (T-083 adds one per enemy)
    FAIL nuke: no "anim" block in content/enemies/nuke/sprites.json (T-083 adds one per enemy)
    FAIL you: no "anim" block in content/enemies/you/sprites.json (T-083 adds one per enemy)
    CHECK-ANIM-DATA 0/6 enemies passed, 0 states checked     (exit code 1)

The gate, in full:

    > powershell -File tools\gate.ps1
    STEP 3 run_all
    OK run_all (TESTS 27 passed 0 failed)
    ...
    OK   sprite validator
    OK   fog readability
    ---- gate summary ----
    OK   python oracle checks (TESTS OK, SELFTEST 15/15, GALLERY 16/16 OK)
    OK   terrain parity (PARITY 56/56 OK)
    OK   run_all (TESTS 27 passed 0 failed)
    OK   boundary scan (ran in run_all: game/tests/test_boundaries.gd)
    OK   content schema (ran in run_all: game/tests/test_content.gd)
    OK   drop-in fixture (ran in run_all: game/tests/test_dropin.gd)
    OK   replay determinism (ran in run_all: game/tests/test_replay.gd)
    OK   sprite validator
    OK   fog readability
    GATE OK (9 ran, 0 skipped, 47 s)

(The ERROR/WARNING lines from `sim/intermission.gd` in the gate's run_all output are pre-existing
log noise from test_schedule.gd's fixture flushing a full inbox, unrelated to this ticket and
present before it; the gate's assertions all pass.)

## Frames: where the tables' numbers could NOT be satisfied by what T-016 produced

All 12 enemies are TBD placeholders today, so no table's frame list can be satisfied by name; every
state uses the TBD frames and the timings stay exactly as the tables say. Per enemy:

| enemy | spec frames | T-016 files referenced | mismatch |
|---|---|---|---|
| gift Larper | larper_00..04 | sprites/cycle_00..04.png | name only; 1:1 frames, order preserved |
| toucher | toucher_00..02; glitchfloor_00..04 | sprites/cycle_00..02.png; sprites/floor_00..04.png | names only; floor decal is a section 2.2 world decal wired via `attack_infect.effect_params.glitchfloor_frames`, not a body state |
| seal | seal_00, seal_01, seal_02, seal_03 | sprites/idle_00.png (base), sprites/dash_00.png/dash_01.png (dash stand-in) | **real gap**: no mouth-open frame, no flipper frames. idle holds idle_00 at the table's 9 ticks/frame; telegraph holds idle_00 for the 45-tick cue; attack alternates dash_00/01 at the table's 4 ticks/frame for the 60-tick dash (D-T083-2, TBD.md row 24) |
| address me | addressme_00, addressme_01 | sprites/cycle_00.png, sprites/cycle_01.png | names only; both frames are identical placeholder art (the explode composite is unbuilt) |
| claude | claude_00; plushie_00..02 | sprites/idle_00.png (logo); plushie_idle loops sprites/idle_00..02.png | **real gap**: NO plushie frames exist (the clawd Crab source was never fetched); the three TBD logo frames stand in at the table's exact 6 fps / 10 ticks per frame (D-T083-7, TBD.md row 26) |
| gin ichimaru | gin_idle_00, gin_launch_00 | sprites/idle_00.png, sprites/launch_00.png | none - names and counts match exactly |

No frames were invented; nothing was renamed on disk (the pipeline's `animations[]` block is untouched);
no table number was restated. TBD.md rows 22-27 carry the per-enemy rows, D-T083-1/2/5/7 carry the reasons.

## Decisions and rules applied

- D-040 (ENEMIES.md frozen): no behavior sentence was edited; no roster/decision change anywhere.
- Section 1.0 (common rules): TBD reading of "every state uses the TBD frame" applied verbatim;
  telegraph/attack sync by construction; the diegetic spawn lines and the 30-tick contact block are
  the view/sim's (T-084) job, only carried as `effect_params` here.
- D-T083-1..D-T083-11 in DECISIONS.md (frame naming; TBD sequence collapse; exact fps->ticks; null
  for unstated cells; gin's launch pose held for the 18-tick flight; address me's single held
  telegraph frame; claude plushie stand-in; checker SPEC contract; anim key naming; toucher floor as
  effect params; gift Larper's non-fade spawn).
- SPEC GAPs: none. Every number in these six entries comes from the tables or DESIGN.md section 5;
  unstated cells are `null`, never an invented figure.
- CONTESTABLE items carried over from the tables themselves stay marked: address me's 12-tick spawn;
  gift Larper has no [CONTESTABLE] of its own; claude Detection/tempo is binding arithmetic.

## For the sibling half (enemies 1-6)

`check_anim_data.gd` embeds their sections 1.1-1.6 tables and checks them the same way. Two things
they should know: (a) anim state keys are snake_case of the table's row labels (`attack_flight`,
`attack_landing`, `attack_arrival`, `attack_ring`, `telegraph_tracking`, `telegraph_locked`,
`attack_descent`, `attack_explosion`, ...) - the checker normalizes keys before matching and prints
NOTE (never FAIL) for extras; (b) frame names will be their TBD placeholder names (existence is
checked; names/counts are relaxed while `tbd=true`); timings/loop/tick-ranges/durations are strict.
Run `<godot> --headless --path game --script res://tools/check_anim_data.gd -- kiwi_cat coil thicc_ben isagi nuke you`.
Any FAIL line names the state, the field, and the table's number - the table wins.

## Not done / out of scope

- T-084 (the animation player) is not started; nothing reads `anim` at runtime yet; 0 lines of sim
  or view code changed.
- The `animations[]` pipeline blocks are untouched, so `validate_sprites.gd` and `test_billboard.gd`
  stay green as before.
- A fresh `.godot` import was produced by the gate run as usual; nothing in `.godot/` is committed;
  no `.uid` files are committed.

