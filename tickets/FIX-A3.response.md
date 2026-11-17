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

Re-measured after the rebase onto main (KIWI-SLOW merged, 64e3332, owner ruling
D-KIWI-SLOW-1 FINAL; the kiwi numbers are the owner's and were not touched again).
The sweep ran in four 25-run chunks of one godot process each (the T-081 chunking);
seeds 0-9 re-run byte-identical against the sweep rows.

| what | fast kiwi (pre-ruling build) | KIWI-SLOW (rebased build) |
|---|---|---|
| level-1 completions | 56 / 100 (audit baseline 1/10) | **82 / 100** |
| median level-1 sim time | 43.4 s | **43.4 s** over completions (min 27.3, max 145.5) - the criterion's 120 s is met whenever the level IS completed |
| level-1 failures | 44 (D-KIWI 37) | **18: D-KIWI 8, D-VOID 4, stuck 4, timeout 1, D-COIL 1** (seeds 10, 22, 31, 35, 44, 49, 51, 53, 55, 63, 64, 68, 69, 74, 82, 87, 88, 92) |
| gate | GATE OK (9 ran, 0 skipped, 210 s) | see the gate line at the bottom of this file |

**A3 still does NOT pass (82 against a required 95 of 100). Nothing was weakened,
no threshold moved, no criterion edit, and no enemy number touched by this ticket**
(ticket clause c; the kiwi numbers are the owner's D-KIWI-SLOW-1). The residual, in
order: the flying kiwi cat still intercepts validated arcs at their landing tile
(straight-line leading is not enough - the floater tracks the PLAYER's feet height
in flight, so its intercept of the landing must be predicted, not linearly led);
4 D-VOID remain on steep multi-hop drop chains; 5 runs stall in the banned-edge
lift cycle (4 stuck + 1 timeout). Next lever per T-060's own ordering: a deeper
chaser-intercept competence pass, or the owner's further ruling on the kiwi. The
park keeps the evidence: PARKED.md #24, DECISIONS.md D-FIX-A3-1..3,
out/kiwislow_{0,25,50,75}.txt (per-seed rows), out/trace2c.txt (kill trace).