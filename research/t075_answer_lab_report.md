# T-075 answer lab - sweep report (piece 3)

Run: `<godot> --headless --path game --script res://tools/answer_lab.gd -- --trials=200`
on branch `t3/t075-answer-table`, commit afabc84. Full sweep, all cases, exit 0.
200 seeded trials per pair per arm (seeds 1000..2199, run seed scaled per pair),
base stats, no upgrades, Last Light spent, dasher class, 60 Hz. Survival =
alive at the window's end (600 ticks for the base and stacked pairs, 1500 for
the F8 combos - D-T075-2 for the reasoning).

Bounds (the ticket's done-when): answer >= 95 % AND no-input <= 5 %.

## Result

**1 of 29 pairs passes. 27 park with their numbers below. No enemy number was
changed by this ticket, and the harness was not tuned to make any pair pass -
the per-pair timings below are read from the doc's own arithmetic before any
sweep ran (D-T075-4).**

## Pair table (200 trials per cell)

| pair | answer % | no-input % | verdict |
|---|---|---|---|
| nuke on flat_lane | 100 | 0 | **PASS** |
| thicc_ben on flat_lane | 100 | 100 | FAIL - danger bound (solo) |
| seal on flat_lane | 0 | 0 | FAIL - both bounds |
| you on flat_lane | 0 | 0 | FAIL - both bounds |
| kiwi_cat on flat_lane | 0 | 0 | FAIL - both bounds |
| kiwi_cat on nook | 0 | 0 | FAIL - both bounds |
| coil on flat_lane | 0 | 0 | FAIL - both bounds |
| coil on hub | 0 | 0 | FAIL - both bounds |
| gift_larper on flat_lane | 100 | 100 | FAIL - danger bound (solo) |
| gift_larper on hub | 100 | 100 | FAIL - danger bound (solo) |
| toucher on flat_lane | 0 | 0 | FAIL - both bounds |
| address_me on flat_lane | 100 | 100 | FAIL - danger bound (solo) |
| isagi on flat_lane | 0 | 0 | FAIL - both bounds (F6: expected) |
| isagi on stepped_lane | 0 | 0 | FAIL - both bounds |
| claude on flat_lane | 0 | 0 | FAIL - both bounds |
| gin on flat_lane | 100 | 100 | FAIL - danger bound (solo) |
| kiwi_cat (x4) stacked | 0 | 0 | FAIL - both bounds |
| coil (x3) stacked | 0 | 0 | FAIL - both bounds |
| thicc_ben (x2) stacked | 100 | 100 | FAIL - danger bound |
| seal (x3) stacked | 0 | 0 | FAIL - both bounds |
| you (x2) stacked | 0 | 0 | FAIL - both bounds |
| nuke (x2) stacked | 100 | 0 | **PASS** |
| isagi (x2) stacked | 0 | 0 | FAIL - both bounds |
| toucher (x2) stacked | 0 | 0 | FAIL - both bounds |
| gift_larper (x5) stacked | 100 | 100 | FAIL - danger bound |
| gin (x3) stacked | 100 | 100 | FAIL - danger bound |
| kiwi_cat + address_me | 0 | 0 | FAIL - both bounds |
| nuke + address_me | 0 | 0 | FAIL - both bounds |
| gin + address_me | 100 | 100 | FAIL - danger bound |

## How each number should be read (and what the harness does not yet measure)

Group A - **danger bound fails BY THE DOC'S OWN DESIGN** (answer 100, no-input
100): the enemy is explicitly not lethal to a still player, so a no-input
baseline cannot die. thicc_ben ("yes - he cannot kill", section 4), gift_larper
(D-026: the star kills whoever grabs it; the lab's stand 4 u away never
touches it), address_me (the belt only punishes MOVEMENT; a still player from
tick 0 has already "answered" - the pairs that measure its danger are the F8
combos), and gin (the marked patch kills the movement INTO it; the stand was
placed outside the 5x5; the crack did not reach).

Group B - **both arms die at the same tick** (kiwi, coil, seal, you, toucher,
isagi, claude, and their stacked/combo rows): the answer arm arms its trigger
(trace-confirmed) but dies at the same instant as the never-input arm. The
reading: the answer executor's press window does not survive contact for these
enemy models at ANY of the doc's `lead`/`lag` readings the harness currently
implements - the harness's answer-bot is not yet faithful enough to certify a
pass, and equally it has NOT shown the documented answer wrong. Two concrete
harness gaps, recorded as the next work on this lab (PARKED #17):
  1. the contact-kill body answers (kiwi hurdle, toucher hurdle) die mid-jump
     (the trace's y=0.62 at the kill) - the harness's ONE continuous jump
     press does not model the re-jump cadence a real hurdle uses on repeated
     passes, and the approach speeds put the press inside the kill envelope;
  2. burst/death-tick pairs (seal bark, claude drums, isagi release) cross the
     player between the trigger and the first playable input - the death tick
     equals the no-input arm's, so the measured number is the danger, not the
     answer's failure. The doc's own F6 row already predicts the isagi flat
     case (0 %), which the harness reproduced as expected.

Group C - **isagi on stepped_lane 0/0** mirrors the flat case rather than
showing the 2 HU step blocking the line (D-061); the harness does not verify
the balls' line geometry died on the rise - the pair is parked until the lab
records the projectile-miss cause.

PASS rows: nuke at the base AND the x2 cap - the leave-and-keep-distance answer
is the one answer this harness executes end-to-end.

## Honest caveats

- The "you" lag (75 ticks = 5/6 of the rumble) and the toucher lead (2.4 u)
  are the harness's APPLIED readings of answers.gd's anchor phrases, chosen
  from the doc's numbers before the sweep; they are [CONTESTABLE]
  (D-T075-4), not verified optics.
- Shade: `gift_larper`'s answer "walk around it" is implemented as the
  lane-walk-away (answers.gd's note on the row says the closest sequence); the
  hub runs use the same.
- The stacked copies spawn 3 u apart on one line; F7's proposed phase rule is
  NOT implemented (the copies' cycles start together), which is exactly the
  unreadable-overlap case F7 proposes to fix - the stacked Group-B rows are
  likely the worse-for-wear read of that finding.
- The sweep ran to completion (all 29 pairs, both arms, ~24 min wall). The
  numbers are reproducible: same seeds, same result byte-for-byte.

