# FIX-A3 — response

Driver: `game/tools/bot_run.gd` (the T-060 bot; the sim, generator, enemies and every
enemy number untouched).

## What the fix did

- **Edge discipline (the A3 brief): every move-graph edge through air is paid for.**
  Routing is Dijkstra with per-edge costs: the movement graph's walk edges (TERRAIN_SPEC
  5.2) cost 1-2; a hop over a small rise 3; the section 5.1 jump envelope 6; wide jumps
  and deep drops up to 60. The route never crosses air when a walkable bypass exists.
- **No edge is followed on faith.** Every through-air edge is taken only when the
  controller's own physics (the same integration the controller runs per tick) find an
  arc that lands on a tile within 1.15 u of the far waypoint. With no validated arc the
  edge is banned (per level) and the route re-plans; bans lift after a 300-tick cooldown
  so a wrong ban cannot soft-lock a level (tried both ways on many seeds).
- **Grounded takeoffs.** The old follower only pressed the jump after its feet had left
  the takeoff tile, so it reached the tile edge before the press fired (or did not fire
  at all) and walked off gap edges instead of leaping. Takeoffs now press while still on
  the takeoff tile, with the validated arc's own approach speed.
- **A contact-kill counter-play**: a closing contact-kill body inside HURDLE_DIST (2.0 u)
  is jumped over at the current run speed - never stopped for - and grounded only when
  the body is within the arc it already has.
- **Route-level menace**: tiles near a contact-kill body cost extra in the route
  (the body's 5x5 tile neighbourhood +30), so the walking line curves away from a live
  chaser instead of meeting it head-on. The avoidance reads the bot's own per-enemy
  velocity estimate (last-tick position delta) and never a guessed direction.
- **Keep existing behavior: dodge stays reactive (REACT_TICKS), determinism is kept
  (byte-identical reports, pinned by game/tests/test_bot_run.gd), no bot mode is added
  to the sim, the sim and enemies are untouched.**

## The measured numbers (the pinned set: `bot_run.gd --dodge`, seeds 0-99, `--max-level 2`)

The sweep ran in four 25-run chunks of one godot process each (the T-081 chunking;
the single long-process death mode is recorded there). A re-run of seeds 0-9 is
byte-identical to the sweep rows (determinism re-proved outside the gate too;
test_bot_run.gd stayed green in the gate).

| what | measured |
|---|---|
| level-1 completions | **56 / 100** (audit baseline: 1/10 = 10%) |
| median level-1 sim time | **43.4 s** over the 56 completions (min 27.3, max 145.5) - the criterion's 120 s is met whenever the level IS completed |
| level-1 death codes (44 failures) | D-KIWI 37, D-VOID 2, D-COIL 1, stuck 4 |
| deaths after completing level 1 (levels 2+) | D-KIWI 22, D-COIL 7, D-VOID 1, stuck 1 |
| gate | GATE OK (9 ran, 0 skipped, 210 s) - TESTS 55 passed 0 failed |

**A3 does NOT pass. Nothing was weakened, no threshold moved, no enemy number
touched** (ticket clause c). Void-competence - the ticket's named gap - is fixed and
the number proves it: 8 of 10 audit deaths were D-VOID; the fix leaves 2 D-VOID in
100 runs (and out of 132 total recorded deaths across this sweep, 71 are D-KIWI).
The residual is the flying pure-pursuit kiwi cat: it floats toward the player's feet
height at base_speed 5.6 (pursuit_ceiling 0.8), crosses void gaps, eases toward the
player's height in flight (FLOATER_CLIMB 2.0 u/s closes the vertical gap inside a
0.6 s jump), and meets a validated arc at its landing tile. The bot's hurdle-over
(ENEMIES.md/SR-2's own counter-play) is measured too late at a 2.0 u trigger against
a combined closing speed of 14.6 u/s (SR-2's own numbers), and no stationary
avoidance solves a pursuer at the corners of a route. Per T-060's own ordering the
next lever is owner-owned: either a deeper trajectory-prediction competence pass
(predict the chaser's intercept of the LANDING tile, not a straight-line lead), or
the enemy tuning T-060 reserved for the case where the bands still miss - and the
bands still miss. PARKED.md #20 carries the row; DECISIONS.md carries
D-FIX-A3-1 (edge discipline), D-FIX-A3-2 ([CONTESTABLE] bot constants), D-FIX-A3-3
(the honest FAIL).