# Preflight review — contradictions between the owner's rulings (D-022…D-055) and the design

Written 2026-11-16 by the design lead (Fable 5.2). Review only; nothing was fixed when this was
written. Read against DESIGN.md, FLEET_PACK.md and TERRAIN_SPEC.md at commit `ab471d8` plus the
uncommitted ruling edits. Measurements: 100 seeds per level for anchors and props, 12 seeds per level
for route times and mine positions, on generator version 2.

Tags: **[BLOCKS-FLEET]** = a ticket would be built wrong, has no owner, or has an acceptance test that
cannot pass or does not mean anything. **[POST-RUN]** = data-only tuning.

Status column: `OPEN` or `RESOLVED (D-0xx)`. Whoever resolves an item edits ONLY its status line.

---

## Must resolve before the run

### 1. Enemy spawn anchors no longer exist for most enemies [BLOCKS-FLEET]
Status: RESOLVED (D-056; TERRAIN_SPEC part by the terrain worker)
- DESIGN.md §5: "enemies appear 6.0 s after level start, at the anchor of their preferred kind"; coil
  uses "`hop` anchors", kiwi cat "Spawns at `nook`".
- TERRAIN_SPEC.md §6.5 still lists "3 hop (pads)", but the shape contract removed the only archetype
  that emitted it.
- Measured: `hop` absent in 100% of levels; `nook` absent in 74% of level-1 layouts, `perch` in 72%,
  `open` in 51%. Only `lane` always exists.
- Recommend: a fallback order in the spawn rule; retire `hop` from both documents.

### 2. Last Light has no owning ticket and contradicts the kill tests [BLOCKS-FLEET]
Status: RESOLVED (D-057)
- DESIGN.md §3.1: Last Light saves an enemy, tripmine or nuke kill while a charge is held.
- FLEET_PACK.md T-027 `test_kill_api.gd` asserts "a body contact kills"; the enemy ticket block and A7
  say the same. T-012's work list has charges but no Last Light.
- Recommend: T-012 owns Last Light with its own test; T-027, A7 and the enemy block state that kill
  tests run with Last Light spent.

### 3. T-053 and A6 still describe a three-step tripmine ladder [BLOCKS-FLEET]
Status: RESOLVED (D-058)
- DESIGN.md §3.3 and T-021: defuse roll, then Subspacial Barrier, then Last Light, then death.
- T-053: "defuse roll first, shield second, death third". A6: "contact kills unless the defuse roll
  passes or a Subspacial Barrier shield absorbs it".
- Recommend: the four-step order in both.

### 4. Tripmines on 1-wide walkways cannot be walked past [BLOCKS-FLEET]
Status: RESOLVED (D-026)
- DESIGN.md §3.3: "Contact (player within 0.9 u) … kills".
- TERRAIN_SPEC.md §1A: walkways are 1–2 cells wide; §6.8 rolls mines on any slot.
- Measured: 1.3 mines per level sit on 1-wide walkways at level 10, 5.8 at level 30. A 1 u wide path
  with a 0.9 u trigger is a lethal wall.
- Recommend: forbid mines on tiles with no walkable bypass (generator rule + validator check, version
  bump), and define the contact volume.

### 5. Respawn can place the player on top of an enemy [BLOCKS-FLEET]
Status: RESOLVED (D-059)
- DESIGN.md §3.1: safe tile is "not inside any hazard footprint (mine blast radius, nuke ring, void
  zone, shockwave ring, telegraphed patch)". Enemy bodies are not listed.
- DESIGN.md §5: every body contact kills; kiwi cat, toucher and YOU?! float straight at the player
  and converge on the spot they fell from.
- Recommend: add a minimum distance from every enemy body and projectile to the safe-tile test.

### 6. A3 does not say which enemy, whether the bot dodges, or the Last Light state [BLOCKS-FLEET]
Status: RESOLVED (D-060)
- FLEET_PACK.md A3: "a bot completes level 1 … in ≥ 95 of 100 seeds with the starter enemy present".
- T-026 makes `--dodge` optional; the starter pool has four enemies, three of which kill on contact.
- Recommend: pin the enemy, the dodge flag, Last Light and the charges.

### 7. Isagi's ball height is unspecified and his cover premise is gone [BLOCKS-FLEET]
Status: RESOLVED (D-061)
- DESIGN.md §5.4: "Line of sight is why props exist"; he "Holds a `perch` or `lane` anchor".
- Measured: 3.3 props per level at level 1, 6.9 at level 12, minimum 0, all on platforms.
- Nothing says how high the balls travel or whether a jump or a height step clears them.
- Recommend: specify the 3D flight line, what clears it, and prefer `perch`.

### 24. T-050's safety assertion fails on the current curse list [BLOCKS-FLEET]
Status: RESOLVED (D-062)
(Found while reading; not caused by the rulings.)
- FLEET_PACK.md T-050: "total run-speed reduction ≤ 10%".
- DESIGN.md §7.2: Weighed Down is −10% and Cold Start gives Athletic −5% → Athletic can reach −15%.
- Recommend: Cold Start's Athletic penalty becomes something other than run speed.

---

## Can wait until after the run (all OPEN, all [POST-RUN] — do not touch in the preflight ticket)

8. **Overtime and chaser-speed curses make floating killers faster than the player.** Overtime +6% per
   tier (max 8), Rush Hour +8% ×3, "Hunger" +5% repeatable, Zoomies +60%; toucher floats at 6.75 u/s
   and its touch kills; the player runs 9 u/s. At overtime tier 6 the toucher reaches 9.2 u/s.
   Recommend: cap the final speed of any floating enemy at 85% of base run speed.
9. **Levels are far shorter than the timings the economy assumes.** DESIGN.md §2 targets 90/150/200/240 s
   black phase; measured greedy route at run speed: 22 s (L1), 43 s (L10), 77 s (L30), ignoring jump
   and dodge time. Overtime ticks every 20 s. Recommend: measure with the bot, then lengthen paths or
   shorten the overtime period.
10. **Field Dressing is priced for the old game.** T1, 45 g, 2 stacks = two free falls every level for
    113 g. Recommend: 1 stack, T3, about 320 g.
11. **Sure Foot plus free falls turns the void into a dodge.** 0.0 s respawn and 3.0 s invulnerability
    at two stacks. Recommend: cap invulnerability at 2.0 s; none on a free fall.
12. **Hungry Void is still rated a mid-severity opener.** Min level 1, Harsh, counter-play "enter the
    beacon at 0 charges". Recommend: Brutal, min level 8, counter-play "Field Dressing".
13. **Brittle breaks the feel budget.** Two stacks = 2.4 s respawn against "≤ 2.0 s". Recommend: 2.0 s.
14. **Crumbling now covers most of the level.** 1-wide tiles are 43% of walkway tiles at level 12 and
    66% at level 30. Recommend: restrict to shortcut bridges and drop ledges.
15. **Slippery curses are rated Mild.** Wet Floor and Wet Trail on 1–2 wide paths cost charges; no
    friction value exists in the controller or the stat list. Recommend: Harsh; add a friction stat.
16. **Bunker Buster pays a Brutal bounty for almost nothing.** Levels hold 3–10 props. Recommend:
    replace the effect or make it Mild.
17. **Seal's counter-play is impossible on 1-wide paths.** "sidestep twice". Recommend: the dash holds
    its starting height; reword.
18. **Toucher's write-up still describes a wall.** "a glitched 2-wide walkway is a wall" against "does
    not kill". Athletic has no ability, so the ability lock (and coil's) does nothing to that class.
19. **The last-safe-tile ring rarely updates on thin paths.** "stood on for ≥ 0.5 s" against 0.11 s per
    tile at run speed. Recommend: 0.1 s, as a data value.
20. **Binding timings versus tune-to-band.** §5 "cue TIMINGS below are binding" against §9 "tune enemy
    speeds/cooldowns/telegraphs". Recommend: timings binding; bands are a report in run 1.
21. **Late-game content may be unreachable.** 22 enemies by level 30, T4 from 18, T5 from 26, with
    everything lethal and two charges. Recommend: wait for bot data.
22. **Small wording contradictions.** "re-rolls the level's mines" (the roll is fixed, the threshold
    moves); Leaky Purse lists Stand Fast as counter-play; "One charge" (dash) collides with void
    charges; TERRAIN_SPEC line 8 and §6.3/§6.5 still say room/link; FLEET_PACK §9 plans
    "GEN_VERSION 2" which already exists.
23. **The owner's summary said "2 per level".** DESIGN.md §3.1 and D-050: the player holds 2, they
    carry over, the beacon restores 1. Recommend: confirm D-050 stands. (Owner ruling requested in the
    preflight ticket: charges carry over, no per-level reset.)
