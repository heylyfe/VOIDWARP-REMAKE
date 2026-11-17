# T-083 — enemies 1-6 — response

Scope: kiwi_cat, coil, thicc_ben, isagi, nuke, you (sections 1.1-1.6 of
research/fable-tickets.md). Branch `t3/enemies-1-6-anim-data`; no branch created or
switched, nothing pushed. The other six enemies were not touched.

## 1. VERDICT

DONE, for my six.

- An "anim" block was added to each of the six `game/content/enemies/<id>/sprites.json`:
  one entry per state of that enemy's section 1.x table, with frames (by spec frame name in
  `spec_frames`, by on-disk file in `frames`), loop yes/no, ticks per frame or explicit tick
  ranges / total ticks, and effect name + parameters. No code. All timings are exactly the
  table's binding numbers.
- `game/tools/check_anim_data.gd` did NOT exist; it was created (deliverable 2). It proves
  every state of every section 1.x table exists with the listed frames and tick counts, and
  that every referenced frame file exists on disk. It accepts a list of enemy ids on the
  command line so the other worker's six can be checked too, prints a clear per-enemy
  PASS/FAIL plus a final count, and exits 1 on any failure.
- Gate: `GATE OK (9 ran, 0 skipped, 45 s)`, TESTS 27 passed 0 failed.
- `check_anim_data.gd` for my six: `ANIM-DATA 6 passed 0 failed` (exit 0).

The other six currently print `FAIL <id>: no 'anim' block (T-083) in sprites.json`
(`ANIM-DATA 6 passed 6 failed`, exit 1) — the correct mid-flight state for the other half of
T-083, not a defect in this one (D-T083-6).

Every frame today is a T-016 TBD placeholder (`"tbd": true` everywhere; all 17 owner images
are absent). Every state therefore uses the TBD frame(s) and the timings stay exactly as the
table says — which is the spec's own rule for this case. No frames were invented and no
number was invented: where the table bounds no duration, `total_ticks` is null and a note
names the resolving tick (see section 5).

## 2. WHAT SHIPPED (files)

- `game/content/enemies/kiwi_cat/sprites.json` — anim block, section 1.1 (5 states:
  spawn, idle_chase, telegraph, attack, recover)
- `game/content/enemies/coil/sprites.json` — anim block, section 1.2 (6 states: spawn,
  idle, telegraph, attack_flight, attack_landing, recover)
- `game/content/enemies/thicc_ben/sprites.json` — anim block, section 1.3 (6 states:
  spawn, idle, telegraph, attack_arrival, attack_ring, recover)
- `game/content/enemies/isagi/sprites.json` — anim block, section 1.4 (5 states: spawn,
  idle, telegraph, attack, recover)
- `game/content/enemies/nuke/sprites.json` — anim block, section 1.5 (6 states: spawn,
  telegraph_tracking, telegraph_locked, attack_descent, attack_explosion, recover)
- `game/content/enemies/you/sprites.json` — anim block, section 1.6 (5 states: spawn,
  idle_chase, telegraph, attack, recover)
- `game/tools/check_anim_data.gd` — the new checker (all 12 tables hardcoded)
- `tickets/T-083-enemies 1-6.response.md` — this file
- `DECISIONS.md` — D-T083-1 through D-T083-6 appended before the Handover log, plus one
  Handover log line

No other file was edited. `TBD.md` was deliberately NOT edited: the "say so in TBD.md"
clause applies only when a table's numbers cannot be satisfied by the frames T-016 produced —
all of mine can (the timings live in the anim data; frame art is irrelevant to them), so the
conditional did not trigger. No PARKED.md rows: no passage in ENEMIES.md / DESIGN.md / FINAL
decisions contradicts sections 1.1-1.6 (checked against ENEMIES.md's behavior sentences,
DESIGN.md §5.1-5.6 and the D-064/D-066/D-070 FINAL rules; see D-T083-5).

## 3. DONE-WHEN — PROOF (real command output)

Engine: `C:\Users\Nathan\Documents\REMAKE VWR\VOIDWARP-REMAKE\tools\godot\godot.exe`
(Godot Engine v4.7.2.stable.official.ed1daf0bf), run from this checkout.

### 3.1 The checker, my six

```
> godot.exe --headless --path game --script res://tools/check_anim_data.gd -- kiwi_cat coil thicc_ben isagi nuke you
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

PASS kiwi_cat (5 states)
PASS coil (6 states)
PASS thicc_ben (6 states)
PASS isagi (5 states)
PASS nuke (6 states)
PASS you (5 states)
ANIM-DATA 6 passed 0 failed
```

Exit code 0 (verified with `Start-Process -Wait -PassThru; $p.ExitCode`).

### 3.2 Exit code on failure

```
> godot.exe --headless --path game --script res://tools/check_anim_data.gd -- kiwi_cat bad_id
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

PASS kiwi_cat (5 states)
FAIL bad_id: unknown enemy id (known: kiwi_cat, coil, thicc_ben, isagi, nuke, gift_larper, toucher, seal, address_me, claude, gin, you)
ANIM-DATA 1 passed 1 failed
```

`$p.ExitCode` = 1 (via `Start-Process -Wait -PassThru -RedirectStandardOutput ...`). A full
pass of the six returns 0, as in 3.1.

### 3.3 The all-12 run (both halves of T-083)

```
> godot.exe --headless --path game --script res://tools/check_anim_data.gd
FAIL address_me: no 'anim' block (T-083) in sprites.json
FAIL claude: no 'anim' block (T-083) in sprites.json
PASS coil (6 states)
FAIL gift_larper: no 'anim' block (T-083) in sprites.json
FAIL gin: no 'anim' block (T-083) in sprites.json
PASS isagi (5 states)
PASS kiwi_cat (5 states)
PASS nuke (6 states)
FAIL seal: no 'anim' block (T-083) in sprites.json
PASS thicc_ben (6 states)
FAIL toucher: no 'anim' block (T-083) in sprites.json
PASS you (5 states)
ANIM-DATA 6 passed 6 failed
```

This is the other half's to turn green; the checker is written for it (it hardcodes sections
1.7-1.12 as well) and its failure mode is explicit and per-enemy.

### 3.4 The merge gate

```
> powershell -File tools\gate.ps1
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
GATE OK (9 ran, 0 skipped, 45 s)
```

Exit code 0. The gate does not run `check_anim_data.gd` (it is not one of its steps and
`tools/gate.ps1` is not this ticket's to edit); it was run standalone as above.

## 4. THE TICK COUNTS (binding — as shipped)

Section 1.0 of the spec: 60 Hz; `frame = table[state][(ticks_in_state × fps) / 60]`; the
telegraph fills its cue exactly and the attack frame lands on the tick the attack resolves.
What the six blocks encode:

**1.1 kiwi cat** — spawn 30 (common fade, 30 ticks, scale 0.8→1.0); idle/chase loops with no
fixed tick count (one frame) with the ±0.08 u 1.0 Hz bob [CONTESTABLE in the table];
telegraph = one-shot 12 ticks, `repeat_every_ticks: 180` (3.0 s, binding) `repeat_when`
"while within 14 u of the player", scale pulse 1.0→1.12→1.0; Zoomies note carried verbatim
(double meow = two pulses 12 ticks apart, then a red outline for the 180-tick sprint);
attack = no frames (contact kills on the overlap tick; the cat has no wind-up); recover = no
frames.

**1.2 coil** — spawn coil_02, 30 ticks; idle coil_01↔coil_02, loop, 30 ticks per frame,
`cycle_ticks: 180` (swap every 30, 3.0 s); telegraph coil_02→coil_01→coil_00, 12 ticks per
frame, 36 ticks total, explicit inclusive ranges `coil_02 [0-11]`, `coil_01 [12-23]`,
`coil_00 [24-35]` — coil_00 reached on tick 24 and held, exactly as the table; red landing
ring radius 3 u at the target for the whole cue and the flight; attack — flight with explicit
ranges `coil_03 [0-20]`, `coil_04 [21-144]`, `coil_03 [145-164]`, 165 ticks total (coil_04
fully extended spans the apex); attack — landing shows coil_00 on tick 165 (`total_ticks`
null — the resolve tick), shockwave ring expanding to 6 u over 12 ticks; recover
coil_00→coil_01 over the first 24 ticks of the next idle (12 ticks per frame).

**1.3 thicc ben** — spawn thiccben_00, 30 ticks; idle (parked), loop, no bob, until 75 ticks
before the next teleport (interval 801 ticks = 13.35 s); telegraph = no frames (the smoke at
the DESTINATION is the telegraph): 75 ticks, 24 dark puffs `#031A1B`, 1.2 u wide, rising
2 u, ben's sprite fades alpha 1→0 over the first 30 ticks at his old position, and in the
last 30 ticks (0.5 s, the chime) the smoke pulses red twice; attack — arrival shows
thiccben_00 at full alpha on tick 75 (the tick the lock resolves), white flash 6 ticks;
attack — ring (on touch), 18 ticks, sprite rocks ±8° twice, ring wave expands to 8 u in
18 ticks; recover = single frame, no timing (table: —).

**1.4 Isagi** — spawn / relocate-in isagi_idle_00, 30 ticks (relocation note: fade out 18,
fade in 30); idle, loop; telegraph (wind-up) isagi_idle_00 held for 72 ticks (1.2 s), red rim
flash period 24→12→6 ticks (three accelerating thirds), a thin red aim line re-aimed each
tick until release; attack (burst) isagi_shoot_00 shown from tick 72, balls leave on ticks
72, 81, 90 (0.15 s apart, D-064 volley structure stays sim-side), held until tick 102 —
`total_ticks: 30` is DERIVED from the binding 72→102 window and is labelled as derived in the
block (tick_ranges stored state-local, `isagi_shoot_00 [0-30]`; the block also records
release ticks local [0, 9, 18] and global [72, 81, 90]); each ball is the isagi_ball_00
billboard, 1.0 u wide, spinning 720°/s, blue trail 0.6 u; recover (cooldown), loop,
`total_ticks: 150` (2.5 s), sprite at 70% brightness.

**1.5 nuke** — spawn = no sprite (the first lock ring is its entrance); telegraph — tracking:
loop, `total_ticks: 150` (2.5 s), a red ring radius 5 u follows the player and blinks with
the beep from 2 Hz at tick 0 rising linearly to 8 Hz at tick 150; telegraph — locked:
one-shot, `total_ticks: 90` (1.5 s), ring stops and fills from the rim inward, full on
tick 90; attack — descent: nuke_00→01→02→03 loop at 12 fps (5 ticks per frame) over the same
90 ticks, the 3 u billboard travels from 30 u above the ring centre to the ground, arriving
on tick 90; attack — explosion: one-shot, `total_ticks: 24`, starts on tick 90 (the tick the
5 u sphere resolves), white core 6 ticks, then an orange-to-red sphere expanding to 5 u, then
smoke; recover: `total_ticks: 300` (5.0 s), nothing on screen.

**1.6 YOU?!** — spawn you_00, 30 ticks, common fade + horizontal tear; idle / chase
you_00→you_04 loop at 8 fps (`ticks_per_frame: 7.5`, the table's "7–8 ticks per frame"
alternating; `fps: 8`), run-cycle bob; telegraph (rumble) you_00→you_04 loop at 16 fps
(`ticks_per_frame: 3.75`, double speed), `total_ticks: 90` (1.5 s), sprite shakes ±0.05 u,
RGB-split grows 0→6 px, a thin red ring at its feet shows the plane the shockwave will
travel in; attack (ring release) you_04 shown on tick 90 = the tick the ring starts
expanding (9 u/s to 14 u), drawn as a 1.0 u tall translucent red band (not a ground decal) —
`total_ticks` null (the table names no hold tick; see section 5); recover you_00→you_04 at
8 fps, loop, `total_ticks: 240` (4.0 s cooldown).

Every attack frame is placed on the tick the kill resolves; no hold the table does not state
was invented. The telegraph animations fill their cues exactly.

## 5. NUMBERS THE TABLE STATES vs NUMBERS THE TABLE DOES NOT (spec gaps, none invented)

- **Resolve-tick frames carry `total_ticks: null`** rather than an invented hold:
  coil attack_landing (tick 165), thicc_ben attack_arrival (tick 75), you attack (tick 90),
  and the no-duration rows (kiwi attack/recover, thicc_ben recover). Each block carries a
  note naming the resolving tick. Recorded as D-T083-3. The sim/view wiring shows the attack
  frame on that tick and leaves it until the behavior leaves the state. [CONTESTABLE] only in
  encoding; the tick itself is binding.
- **isagi attack `total_ticks: 30` is derived** (102 − 72), not stated; labelled as derived
  in the block. tick_ranges are state-local [0-30]; global 72/81/90 and local 0/9/18 are both
  recorded. Recorded as part of D-T083-2.
- **you idle / telegraph `ticks_per_frame: 7.5` and `3.75`** are the exact 8 fps / 16 fps
  averages; the table's own "7–8 ticks per frame" alternation is noted in the block.
- **you attack:** the table gives the ring's speed (9 u/s), its max radius (14 u) and the
  band's look, but no hold tick for the you_04 frame — `total_ticks: null`, no invented
  number.
- **thicc_ben recover:** the table states frames only ("—" loop, "—" timing); single frame,
  no tick count, `loop: false`.
- **kiwi telegraph**: "one-shot, 12 ticks every 180 ticks (3.0 s, binding) while within 14 u"
  — encoded as `total_ticks: 12` + `repeat_every_ticks: 180` + `repeat_when`; the cadence is
  data, the 180-tick gate itself is the sim's.
- **nuke attack_descent `fps: 12`** is written next to `ticks_per_frame: 5` exactly as the
  table says ("12 fps (5 ticks per frame)").
- No other gaps were found. ENEMIES.md, DESIGN.md §5.1-5.6 and the FINAL decisions
  (D-064 volley/salvo, D-066, D-070) contradict none of sections 1.1-1.6;
  PARKED.md gained no rows. If the owner wants an explicit one-tick "resolve frame" encoding
  for D-T083-3, it is a data edit, not a redesign.

## 6. TBD PLACEHOLDERS (what is and is not satisfied)

All frames are T-016 placeholders (`"tbd": true`): kiwi/thicc_ben/isagi-fire/isagi-shot/you/
nuke/coil pipeline placeholders. The spec frame names in `spec_frames` (kiwicat_00,
coil_00..04, thiccben_00, isagi_idle_00/isagi_shoot_00/isagi_ball_00, nuke_00..03, you_00..04)
do not exist on disk; `frame_map` points each at the placeholder that does
(coil_NN→cycle_NN, nuke_NN→cycle_NN, you_NN→cycle_NN, kiwicat_00→cycle_00,
thiccben_00→cycle_00, isagi_idle_00→fire_00, isagi_shoot_00→fire_02, isagi_ball_00→shot_00;
isagi fire_01 exists but is unreferenced). The mapping is [CONTESTABLE] (D-T083-1): when the
owner drops the real 17 images into `assets_src/enemies/` and the T-016 pipeline is rebuilt,
only `frame_map` and `frames` change — `spec_frames`, loops, ranges and tick counts are the
frozen spec. The placeholders differ per frame for coil/nuke/you (the body_rects move), so
even today the frame index advances per the binding tick counts and the sim/view wiring is
exercised end to end; no visual readability is implied.

## 7. HANDOFFS / NOT MINE

- Sections 1.7-1.12 (gift_larper, toucher, seal, address_me, claude, gin) are the other
  worker's; `check_anim_data.gd` already checks them and will print their PASS once their
  anim blocks land.
- The anim blocks are consumed by nothing yet: `game/view/billboard.gd` implements the T-016
  `animations[]` schema, not the T-083 `anim` block; the behavior/view wiring is a later
  ticket. T-083's deliverable is the data + the proof, not the consumer.
- `tools/gate.ps1` was not edited (not this ticket's file); the checker is standalone.
- `game/tests/test_terrain_parity.gd` untouched; no `.godot/` committed; no `.uid` files
  added; files were added by name only.

## 8. FILES TO COMMIT

game/content/enemies/kiwi_cat/sprites.json
game/content/enemies/coil/sprites.json
game/content/enemies/thicc_ben/sprites.json
game/content/enemies/isagi/sprites.json
game/content/enemies/nuke/sprites.json
game/content/enemies/you/sprites.json
game/tools/check_anim_data.gd
tickets/T-083-enemies 1-6.response.md
DECISIONS.md


