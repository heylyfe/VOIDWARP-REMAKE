# Enemy ecosystem pass

Written 2026-11-16 by the design lead (Fable 5.2), against commit `14be164` (generator version 3, all
rulings through D-063 FINAL). Paper analysis: nothing here was play-tested, because no playable build
exists. Numbers are derived from DESIGN.md §5 and the movement constants (run 9 u/s, jump velocity 12,
gravity 32 → apex 2.25 u, air time 0.75 s). Where I compute a timing window I show the arithmetic.

Frozen and not touched: ENEMIES.md behavior sentences (D-040), the 12-enemy roster, the shape contract
(D-025), every ruling through D-063. This pass designs the SYSTEMS around the enemies. Anything that
would need a frozen item to change is listed under "Parked for the owner", not resolved.

Tags: **[BLOCKS-FLEET]** = an enemy ticket would be built wrong or has to invent a number.
**[CONTESTABLE]** = a judgment call the specs do not cover.

Section status (updated as each section is written to disk):
- 0 Systemic findings — WRITTEN
- 1 Pressure profiles — WRITTEN
- 2 Terrain pairing — WRITTEN
- 3 Vote economy — WRITTEN
- 4 Counter-play map — WRITTEN
- 5 Rulings on preflight items 8, 17, 18 — WRITTEN
- 6 Tickets, parked items — WRITTEN (complete; no section was cut short)

---

## 0. Systemic findings (read these first; the per-enemy sections refer to them)

**F1. Floating enemies have no altitude rule. [BLOCKS-FLEET]**
DESIGN.md §5 says "Floats = moves in a straight line through geometry and over the void at the stated
speed". Nothing says at what HEIGHT. Five enemies float (kiwi cat, YOU?!, toucher, seal between
dashes, Claude). On graduated walkways the height difference between player and enemy decides whether
a body touches, whether YOU?!'s ring plane (±1.5 u of its feet) reaches, and whether a jump clears a
chaser. Every floater ticket (T-030, T-035, T-037, T-038, T-040) would invent this.
Proposed rule [CONTESTABLE]: a floater's feet height eases toward its target's feet height at a
maximum of **2.0 u/s**; horizontal speed is the stated speed. So height is a real escape axis: a
4 HU climb (2.0 u) buys 1.0 s of vertical separation.

**F2. No enemy has a world size. [BLOCKS-FLEET]**
The hard rule says the hit cylinder is "diameter = 0.8 × body width, height = body height, in world
units after sprite scaling" — and no document gives a single sprite's world height. Whether a chaser
can be jumped over, whether a parked body blocks a 1-wide walkway, and whether Isagi can be passed
all depend on it. Proposed table [CONTESTABLE], body height / hit-cylinder diameter in u:

| enemy | height | diameter | consequence |
|---|---|---|---|
| kiwi cat | 1.0 | 0.9 | hurdle-able (apex 2.25 u) |
| coil | 1.0 squashed / 2.0 extended | 0.9 | hurdle-able while idle |
| thicc ben | 4.0 | 1.2 | not hurdle-able; touching him is the way past (eject) |
| Isagi | 1.8 | 0.7 | not hurdle-able; never stands on a walkway (see F6) |
| YOU?! | 1.8 | 0.7 | not hurdle-able; slow, so it is outwalked, not jumped |
| toucher | 1.4 | 0.8 | hurdle-able only with a clean jump (0.85 u margin at apex) |
| seal | 0.6 | 0.6 | easily hurdle-able |
| address me | 2.5 | — | no body contact; it is a countdown, not an obstacle |
| Claude | 2.0 | 1.6 | not hurdle-able; keeps its distance (20 u) |
| gin ichimaru | 1.8 | 0.7 | stands 15–25 u away; contact is not his threat |

**F3. Path-bound running loses to straight-line floating, so "outrun it" is not an answer in a dead end.**
A chaser at 62–75% of run speed flies the chord; the player runs the winding path (turn bias 75%,
steps, jumps). In a tree branch the player must also come BACK the way they went, i.e. toward the
chaser, on a path 1–2 cells wide. Without a way past a body, every dead end is a forced void dive
(a charge) or a death. With F1 + F2 the learnable answer exists: **hurdle it** — jump over a low
chaser as it arrives. Arithmetic for the kiwi cat: closing speed 9 + 5.6 = 14.6 u/s; the bodies
overlap horizontally for (0.45 + 0.4) × 2 / 14.6 = 0.12 s; jump height exceeds 1.5 u (cat 1.0 u +
0.5 u it can rise in 0.25 s) from t = 0.16 s to 0.59 s of the jump — a 0.43 s window for a 0.12 s
event. Learnable. This is the single most important enemy rule for fun: it turns the dead end from
a coin flip into a skill check.

**F4. Enemy bodies are walls on 1-wide walkways.**
Body contact kills, walkways are 1–2 wide, and several enemies come to rest ON the path (idle coil,
parked thicc ben, Isagi at a `lane` anchor). The player cannot kill anything. Each such enemy needs a
stated way past: hurdle (coil, idle), spring off (ben), or "is never there" (Isagi — F6).

**F5. The void dive is a real, unlisted answer.**
A fall costs a charge and respawns the player on the last safe tile at least 6 u from every enemy
(D-059) with 1.0 s of invulnerability. That is a deliberate escape from any cornering. It should be
named in the tips and the counter-play text: "out of options, with a charge in hand: jump." It is
also why Field Dressing's price matters (preflight item 10) — a free fall per level is a free escape
per level.

**F6. Isagi at a `lane` anchor fires along the walkway he stands on. [BLOCKS-FLEET for T-033]**
Spawn fallback (D-056, FINAL) sends him to a `lane` anchor when the level has no `perch` (24% of
levels at level 12, measured on version 2). A lane anchor is the middle of a long straight walkway:
his body then blocks the path and his burst travels down its axis, where a 1-wide walkway gives no
sidestep. D-061 says a jump or a 2 HU step clears a ball. The jump window is 0.43 s (height above
1.5 u); three balls arrive over 0.30 s — clearable. With Egoist (+2 balls per stack → 5 or 7 balls
over 0.60–0.90 s) no single jump clears the burst on a flat in-line lane. See section 4 and the
parked list: the clean fix changes a FINAL fallback order, so it is parked, and a ticket-level
mitigation that does not touch D-056 is given instead.

**F7. Stacked copies of timed enemies have no phase rule.**
"+1 coil", "+1 nuke launcher", "+1 Isagi", "+1 seal": DESIGN.md does not say whether copies run in
phase, at random phase, or staggered. Random phase produces unreadable overlaps (two nuke rings
stopping 0.3 s apart on a 1-wide path). Proposed rule [CONTESTABLE]: copy k of n of the same enemy
starts its cycle offset by k/n of the cycle length. Attacks then arrive as a rhythm the player can
learn, and "more of the same enemy" raises tempo instead of noise.

**F8. Two enemies make opposite demands with no arbitration.**
address me requires 1.5 s of stillness; every chaser, the nuke's stopped ring, gin's marked patch and
ben's eject require movement. When both land at once the player has no legal move. Proposed system
rule [CONTESTABLE]: address me does not APPEAR while (a) any enemy body is within 12 u of the player,
(b) a nuke ring, gin patch or coil landing ring is on the player, or (c) the player is airborne or on
glitched floor; it waits and appears at the first tick none of these holds. gin does not mark a patch
while address me's countdown runs. (This follows the pattern of the two alternating in the reference
game; it adds no behavior to either enemy, it only schedules them.)

---

## 1. Pressure profile per enemy

"First shown" = the level whose intermission should first be able to offer it (today's `min level` in
DESIGN.md §5 in brackets). All first-shown changes are [CONTESTABLE]: min levels are ours, not
ENEMIES.md's. Reasoning for the order: under one-hit rules an enemy should arrive only after the
player has met the answer it needs (run → hurdle → jump-on-cue → leave-the-zone → stop).

| # | enemy | role | first shown | what one-hit contact does to it | what 2 carried charges do | what Last Light does |
|---|---|---|---|---|---|---|
| 1 | kiwi cat | slow clock; punishes lingering and dead ends | 1 (1) | unchanged — it always killed; it is now the tutor for "hurdle" (F3) | a void dive is the escape from a cornering; cat costs a charge, not the run | first mistake is free once; teleport to the dais puts the cat 20+ u away |
| 2 | coil | punishes staying in one spot (gift clusters, nooks) | 1 (1) | landing kill radius 1.2 u is easy to leave (3.35 s from cue to landing); the real cost is the shockwave shove off a thin path | it is a charge tax, like ben — rarely a killer | rarely triggers |
| 3 | thicc ben | charge tax; chain breaker; never kills (D-051) | 1 (1) | n/a | each eject on a 1-wide path risks a charge; with Hungry Void one eject can end the run two falls later | never triggers (ben cannot kill) |
| 4 | seal | burst killer on straight lines | 3 (1) | was 60 damage, now a kill: too sharp for the first level, fine once the player hurdles | none directly | the natural first use — players will lose Last Light to a seal |
| 5 | YOU?! | rhythm tax: jump the ring on its beat | 3 (3) | ring was 40 damage; now each missed jump is a death. Window is generous (0.56 s) | none | saves one missed beat |
| 6 | nuke | area denial metronome: forbids staying | 5 (3) | unchanged (always a kill); needs the player to already read ground telegraphs | none | saves one |
| 7 | gift Larper | speed tax on the gold chain | 5 (5) | unchanged | none | third rung of the mine ladder (D-053) |
| 8 | toucher | fast chaser + area slow; herds | 7 (5) | touch was 10 damage; now the fastest lethal body in the game (75% of run). The floor no longer hurts but its slow is what gets you caught | void dive escape; respawn tile must not be glitched (D-043) — it glitches the ring tiles near you, so respawns land farther back | saves one |
| 9 | address me | the only "stop" in a game of "go" | 9 (5) | unchanged (always a kill) — but every chaser is now also a kill, so the stop is far more dangerous than when it was designed; needs F8 | a void dive does not satisfy stillness and does not stop the countdown | saves one |
| 10 | Isagi | ranged denial of open ground and long lanes | 11 (8) | balls were 50 damage (two to kill); now one. The burst must be fully avoided every time | none | saves one burst |
| 11 | Claude | second collectible (plushies) competing with gifts; three patterns on a beat | 15 (15) | all three attacks were partial damage; now each is a kill. Wind shots are the problem (section 4) | none | saves one |
| 12 | gin ichimaru | rewrites the route live | 17 (15) | void zone was 70 damage/s; now entering it kills. Leaving a marked patch in 2.0 s is easy (3 cells) | a cut walkway can force a dive to get home | saves one |

Reading the table as a whole:
- **Charges are spent by three things only**: missteps on thin paths, ben, and coil's shove. Nothing
  else touches them. So charges measure platforming and positioning; Last Light measures enemy
  reading. That separation is clean and should be kept — do not add enemy effects that drain charges.
- **Last Light dims at 0 charges** (D-053), so ben and coil indirectly disarm it: a player ejected
  twice has no Last Light until the next beacon. That interaction is the strongest argument for
  leaving a level early, and the HUD must make it obvious (icon lit / dim / grey).
- **The starter pool should be kiwi cat, coil, thicc ben** — one chaser, one "don't stand still", one
  non-lethal tax. Seal moves to level 3. Acceptance criterion A3 (kiwi cat at level 1) already matches.

---

## 2. Terrain pairing with the D-025 archetypes

Vocabulary (TERRAIN_SPEC §1A): spawn hub (13×13 + dais); walkways `step`, `stair`, `ledge`, `flat`,
`ramp`, 1–2 cells wide; platforms `pad`, `disc`, `cross`, `ell`, `terrace`, `nook`, `spire`,
`bastion` (≤ 7×7); shortcuts `bridge` (two-way), drop ledge (one-way), launch pad. Anchor kinds:
`perch`, `open`, `lane`, `nook`. Measured anchor availability (version 2, 100 seeds per level; the
shape is unchanged in version 3): `lane` always present; `nook` missing in 74% of level-1 and 29% of
level-30 layouts; `perch` missing in 72% / 2%; `open` missing in 51% / 21%.

| enemy | best on | why | degenerate or impossible? |
|---|---|---|---|
| kiwi cat | dead-end `nook` and `spire`; long `step` runs it can cut across | the player must come back through it; F3 hurdle is the test | **Degenerate without F1+F2**: in a dead end on a 1-wide path it is an unpassable lethal wall. With them: fine. Preferred `nook` anchor is missing in most early levels, so it usually spawns on a `lane` — acceptable, it floats to the player anyway |
| coil | `pad`, `disc`, `nook`, the hub — anywhere the player loiters over a gift cluster | it lands where you WERE 3.35 s ago; only a stationary player is in danger | **Two gaps [BLOCKS-FLEET for T-031]**: (1) "the player's position at cue start" can be mid-air over the void — the landing zone must be the player's last grounded tile; (2) the shockwave "pushes players outward at 8 u/s" has no duration. Proposed [CONTESTABLE]: push velocity 8 u/s decaying linearly to 0 over 0.5 s (2.0 u of travel) — enough to clear a 1-wide path from its centre (0.5 u) but survivable on a platform ≥ 5 wide. An idle coil is a body on the path for 3.6 s: hurdle-able (1.0 u squashed, F2) |
| thicc ben | `step`/`ledge` walkways 1 wide, `spire` tops | the eject is a fall risk exactly where there is no floor to come down on | Not degenerate. Parked on a 1-wide path he is a 13 s toll gate: touching him ejects you 5 u up with full air control, which is ALSO the way past him. That is the fun reading of ben and should be the tip text. "under bridges the launch slams you into the slab above" still holds but overlaps are rarer on thin paths |
| seal | long straight `flat`/`step` walkways (`lane`) | the dash line coincides with the only way forward | **Degenerate as written** (preflight 17): "sidestep" is impossible on a 1-wide path. Resolved in section 5 (the dash is a fixed 3D line; a jump or a 2 HU step clears it) |
| YOU?! | the hub, `pad`, `disc` (flat, nowhere to change height) | the ring plane is ± 1.5 u of its feet | On graduated walkways the ring frequently passes above or below the player (a `stair` run changes 2 HU per tread). That is the terrain doing its job, but it must be LEGIBLE: the ring needs a visible height (draw it as a 1.0 u tall band, not a ground decal). Not degenerate. Its preferred `open` anchor is missing in half of early levels → falls back to `lane` |
| nuke | the hub and `pad`/`disc` clusters (a 5 u sphere covers a whole 7×7 platform and its doorways) | on a platform there is one or two ways out; on a walkway you just keep running | **Weak, not broken**: ENEMIES.md's answer is "Break line of sight". On thin paths there is almost nothing overhead and walls exist only on `nook` and as scattered props (3–10 per level). In practice the answer is "leave the 5 u sphere in 1.5 s" (13.5 u of running — always possible on a path that continues, see dead-end check below). Line-of-sight breaking survives as a bonus near `bastion` towers, `nook` walls and under `bridge`s. Dead-end check: from the back wall of a 6-wide `nook` the exit is ≤ 6 u away and the sphere centre is where you stood, so you need ≤ 11 u of running in 1.5 s — possible (13.5 u), with 0.28 s to spare. Tight but fair |
| gift Larper | dead-end clusters (tier-2 slots) and platforms | D-026 guarantees a walkable bypass | Resolved by D-026. One remaining risk is feel, not possibility: the bypass on a 2-wide walkway has 0.1 u of margin (see fun risks) |
| toucher | 2-wide `step` walkways and platform doorways | it glitches the tiles under and around itself (3 u), so the place you are about to step is slow | **Degenerate as written** (preflight 8 and 18), resolved in section 5. Also: its glitched tiles invalidate the newest entries of the safe-tile ring, so a void dive near a toucher respawns the player far back. That is acceptable (it is a real cost) but the tip text must say it |
| address me | anywhere the player is committed: mid-`ledge` jump, mid-glide, on a `spire` | stillness needs solid ground within 3.5 s | **Unanswerable combinations** with any chaser, nuke ring or gin patch — resolved by F8 (it does not appear until the player can answer it) |
| Isagi | `bastion` tower, `spire` top (`perch`) | height gives him sightlines over the stepped paths; steps of ≥ 2 HU break his line | **Degenerate at a `lane` fallback** (F6). On `perch` he is good: graduated walkways are natural cover because any 2 HU rise between him and the player blocks the ball line (D-061) |
| Claude | the hub and `pad`/`disc` (nothing blocks drums and strings) | all three attacks are blocked or shortened by geometry and height | **Wind shots are unanswerable on open walkways** as numbered: 10 u/s homing against a 9 u/s runner on a winding path, 5.0 s life, "destroyed by geometry" where there is none. See section 4 for the fix (a number change inside DESIGN.md §5.11, not an ENEMIES.md change) |
| gin ichimaru | 1–2 wide walkways between sub-areas; `bridge`s | a 5×5 patch removes 5 cells of path for 10 s | Not degenerate alone: leaving the patch takes 0.33 s of running. With 3 votes (cooldown 8 s, zone 10 s) two cuts overlap and can isolate a path segment for several seconds with a chaser inbound → forced dive. Acceptable at that level of the game, and it is what makes shortcuts matter. He must not mark while address me counts down (F8) |

Hunt results, by rule rather than by enemy:
1. **Anything that parks a lethal body on a walkway** needs a way past (F4): coil idle (hurdle), ben
   (spring off), Isagi (must not be there — F6), gin (he stands 15–25 u away "on a tile"; if that tile
   is on the player's only route his body kills). Proposed [CONTESTABLE]: gin's fade-in tile must not
   be on a walkway tile that is a cut vertex of the player's route to the beacon; simplest exact rule —
   gin stands only on platform tiles, falling back to the farthest tile of the hub.
2. **Anything aimed along a straight line** (seal dash, Isagi ball, Claude strings) is at its harshest
   on `flat` walkways and weakest on `stair` runs. `flat` is weighted low by D-025 (flat-share 2–3% of
   path length), so these enemies are mostly fighting stepped ground. Good for fairness; it means their
   kills will come from the hub and from platforms, not from the paths.
3. **Anything radial on a plane** (YOU?! ring, Claude drums, coil shockwave) is at its harshest on the
   hub (13×13, flat). The hub is also the spawn point, the Last Light destination, the respawn
   fallback and the beacon. Three radial enemies converging on the dais at beacon-open time is the
   most dangerous moment of a level by construction. That is good drama for "linger or leave", but
   Last Light must not drop the player into it: its 2.0 s of invulnerability is the only protection.
   Proposed [CONTESTABLE]: Last Light's teleport also pushes every enemy body within 8 u of the dais
   out to 8 u (a one-time knock-back, no kill, no behavior change).
4. **Nothing in the roster uses `nook` or `open` as more than a spawn point.** After D-056 those two
   anchor kinds only decide where a chaser starts. They are cheap to keep; do not add generator work
   to guarantee them.

---

## 3. Vote economy

The CADENCE is not touched: D-045 fixes when enemy votes happen (22 votes by level 30: one each after
levels 0, 1, 3, 6, 7, 9, 12, 13, 15, 21 and two each after 18, 19, 24, 25, 27, 30). This section
recommends WHAT the three altars show at each vote and what stacking should do. Everything here is
data in `content/enemies/*/enemy.json` and the offer draw; all of it is [CONTESTABLE].

### 3.1 What stacking does to fun, per enemy

| enemy | what a 2nd / 3rd copy adds | where it stops being fun | cap today → proposed |
|---|---|---|---|
| kiwi cat | a second cat makes hurdling a rhythm (two jumps); a third closes the gap between them | 4+ cats arrive as an unbroken line on a 1-wide path: no gap to land in after a hurdle | 6 → **4** |
| coil | more landings per minute; with stagger (F7) a readable beat | 4 coils = a landing every 1.6 s; the shove chain becomes a charge drain with no skill in it | 4 → **3** |
| thicc ben | a second toll gate; doubles the chain breaks | already capped | 2 → 2 |
| seal | staggered barks, one jump each | 4 dashes inside one jump's air time cannot all be cleared | 4 → **3** |
| YOU?! | a second ring plane; two beats to jump | three rings from three heights are unreadable | 3 → **2** |
| nuke | staggered rings (F7): a ring stops every 4.5 s | 3 launchers: the player is leaving a blast a third of the time and cannot stop for anything | 3 → **2** |
| gift Larper | +3 mines per vote under the cap and the bypass rule | self-limiting (D-026, 20% cap) | 5 → 5 |
| toucher | a second herd direction; more glitched floor | 3 touchers at 75% speed from three sides on a tree-shaped level leave no un-glitched respawn tile | 3 → **2** |
| address me | shorter return interval (−5 s per vote) | at 15–30 s it interrupts every gold sweep; fine with F8 | 3 → 3 |
| Isagi | crossfire from two perches; steps still break each line | 4 Isagi = 12 balls per 3.7 s from four angles; some burst always has a clear line | 4 → **2** |
| Claude | — | one only | 1 → 1 |
| gin ichimaru | shorter cooldown (−3 s per vote) | at 3 votes two cuts overlap — intended late-game | 3 → 3 |

Proposed caps sum to 32 votes, against 22 needed by level 30 and +6 per act afterwards; "Hunger"
(DESIGN.md §6) takes over when the pool is exhausted, about level 40.

**Chaser ceiling** [CONTESTABLE]: at most **6 floating lethal bodies** in play at once (kiwi cat,
toucher, YOU?!, seal, plus The Litter's kittens count as half each). An altar that would exceed it
is not drawn. Reason: F3 — every chaser on a thin path is one hurdle; six is a sequence a player can
read, ten is a wall.

**Stagger** (F7): copies of one enemy run their cycles offset by 1/n of the cycle. **Spawn
separation**: copies of one chaser spawn at least 30 u from each other (next anchor in the fallback
order), so they arrive from different sides instead of as one blob.

### 3.2 What the three altars show

Draw rule, replacing "3 distinct enemies from the eligible pool":
1. **One NEW altar**: an eligible enemy type with 0 votes, if any exists (lowest first-shown level
   first, ties by seeded draw).
2. **One REPEAT altar**: a type already in play, below its cap — never the type picked at the
   previous vote.
3. **One FREE altar**: seeded draw from everything eligible and not already shown.
If a category is empty its altar becomes FREE. Reason: every vote is then the same legible question —
"a new problem, or more of one I already handle?" — which is the only interesting enemy decision in
a game where enemies cannot be killed. It also guarantees variety (a new type is always on offer
while one exists) without removing the canon right to stack one enemy five times.

### 3.3 Recommended offering across 30 levels

"Newly eligible" uses the first-shown levels of section 1. The offer for the level-N intermission
affects level N+1.

| after level | votes | newly eligible | expected types in play after | note |
|---|---|---|---|---|
| 0 (pre-run) | 1 | kiwi cat, coil, thicc ben | 1 | all three starters shown; no repeat exists yet |
| 1 | 1 | — | 2 | the two starters not yet picked + a repeat |
| 3 | 1 | seal, YOU?! | 2–3 | first "jump on the cue" enemies |
| 6 | 1 | nuke, gift Larper (from 5) | 3–4 | act finale: first area denial |
| 7 | 1 | toucher | 4–5 | first fast chaser, after the player has hurdled cats for six levels |
| 9 | 1 | address me | 5–6 | the first "stop" arrives only once F8 can protect it |
| 12 | 1 | Isagi (from 11) | 6–7 | act finale: first ranged denial |
| 13 | 1 | — | 7–8 | |
| 15 | 1 | Claude | 8–9 | |
| 18 | 2 | gin ichimaru (from 17) | 9–11 | first double vote; the NEW altar guarantees gin or Claude is on offer |
| 19 | 2 | — | 11–12 | by here every type has been offered at least twice |
| 21 | 1 | — | 12 | all 12 types plausibly in play; votes are now repeats |
| 24 | 2 | — | 12 | repeats; the chaser ceiling starts to bind |
| 25 | 2 | — | 12 | |
| 27 | 2 | — | 12 | |
| 30 | 2 | — | 12 | 22 votes placed; typical end state ≈ kiwi 3, coil 2, ben 2, seal 2, YOU?! 1, nuke 2, Larper 2, toucher 1, address me 2, Isagi 1, Claude 1, gin 3 |

What this does to the squeeze: under one-hit rules the dangerous step is not "more votes", it is
"a type whose answer I have not learned". The table front-loads learning (9 types offered by level
12, one at a time) and makes the double votes of acts IV–V mostly repeats of known problems. If the
bot data later shows runs dying at levels 13–19, that is where — the stretch where new types and
double votes overlap — and the first knob to turn is Claude's and gin's first-shown level, not the
cadence.

---

## 4. Counter-play map

Rule for this table: an answer counts only if a player with the base kit (run + one jump), 2 charges
and no upgrades can execute it from the telegraph alone. "Window" = how long the correct input stays
correct. The void dive (F5) is available against everything and is not repeated in each row.

| enemy | the tell | the answer | window / arithmetic | survivable today? |
|---|---|---|---|---|
| kiwi cat | meow within 14 u; it is always visible, always slow | open ground: walk away. Thin path or dead end: **hurdle it** as it arrives | 0.43 s jump window for a 0.12 s overlap (F3) | only with F1 + F2 |
| coil | "boing" + landing ring at your feet, 0.6 s; arc 2.75 s | leave the ring (1.2 u) — and be airborne or > 6 u away when it lands | 3.35 s to move 6 u: trivial unless you are pinned by something else | yes, once the push has a duration (section 2) |
| thicc ben | smoke at the destination 1.25 s, chime in the last 0.5 s | be ≥ 4 u from the smoke when it clears; if he is parked on your path, touch him on purpose and steer the launch | running in a straight line clears the lock by itself (6.75 u away at arrival) | yes — he cannot kill |
| seal | dashed line + mouth-open frame 0.75 s, then a bark | **jump on the bark**, or stand a 2 HU step above/below the line | section 5: 0.5 s jump window for a 0.07 s crossing | only after the section-5 ruling |
| YOU?! | rumble 1.5 s; the ring is visible as it expands | jump as the ring reaches you; or stand ≥ 1.5 u above or below its feet | jump height > 1.0 u from 0.10 s to 0.65 s of the jump = 0.56 s window for a 0.16 s crossing | yes. With Echo Ring: jump 0.25–0.65 s before the first ring and jump again on landing (worked out: the second ring arrives 0.6 s later, the second jump is high from 0.85 s) — hard but learnable |
| nuke | ground ring follows you 2.5 s with a rising beep; the ring stops | leave the 5 u sphere within 1.5 s; bonus: put a wall, a tower or a bridge between you and the sky | 13.5 u of running available, 5 u needed (≤ 11 u from the back of a nook) | yes |
| gift Larper | pink particles and the star inside 12 u; slow rotation | look before you grab; walk around it — never over it | at run speed 12 u = 1.3 s of warning (0.67 s under Method Acting) | yes (D-026) |
| toucher | squelch when tiles glitch; glitched floor is visible | keep off its floor, keep height between you (F1), hurdle it on a path | hurdle margin is thin: 1.4 u body, apex 2.25 u | only after the section-5 rulings |
| address me | trumpet, then a 5.0 s rumble | **stop at once**; do nothing for 1.5 s | 3.5 s of slack | only with F8 — otherwise it can arrive with a chaser 3 u away and both kill |
| Isagi | flash + voice cue 1.2 s | get a 2 HU step between you and him, or jump after the release flash, or sidestep ≥ 0.9 u where the path allows | 0.43 s window against a 0.30 s burst (3 balls) | yes for 3 balls from a `perch`. **No** for Egoist bursts down a flat in-line lane (F6) |
| Claude — drums | chime on beats 1 and 3 | jump on the beat | same window as YOU?!'s ring (ring is faster: 12 u/s, crossing 0.12 s) | yes |
| Claude — strings | telegraph line for one beat (0.6 s) | get behind a height step or a prop; jump it when you are ≥ 6 u from Claude | at 10 u the beam crosses a body in 0.26 s (< 0.43 s window); at 3 u it takes 0.88 s (not jumpable) — so "keep your distance" is part of the answer | yes, at distance |
| Claude — wind | ping on beats 1, 2, 3 | **none on an open walkway as numbered** — see below | 10 u/s homing vs 9 u/s running on a winding path; 5.0 s life; nothing to break it on | **no** |
| gin ichimaru | red outline + cracking rumble 2.0 s on a 5×5 patch | walk out of the patch (3 cells) | 0.33 s needed of 2.0 s | yes |

### Unanswerable under one-hit rules (the list the owner asked for)

1. **Any floating chaser in a dead end on a 1–2 wide path** — until floaters have an altitude rule and
   a body size (F1, F2). [BLOCKS-FLEET]
2. **Claude's wind shots on open walkways.** DESIGN.md §5.11: "10 u/s, turn 90°/s, life 5.0 s, kills,
   destroyed by geometry". The shot is faster than the player, homes in 3D, and thin walkways over the
   void offer no geometry. Over a 5.0 s life it gains 5 u on a straight runner and far more on a
   winding path; Claude stays within 20 u. These are OUR numbers, not ENEMIES.md's ("wind = homing
   projectiles"), so they can change without touching frozen canon. Proposed [CONTESTABLE]: speed
   **7.0 u/s** (78% of run — the same band as a chaser), turn rate 90°/s, life **4.0 s**, and a shot
   dies on touching ANY tile slab including the riser of a height step ≥ 1 HU. Then the answers are
   "run in a straight line for 4 s" and "drop one tread". [BLOCKS-FLEET for T-040]
3. **Isagi with Egoist firing down a flat in-line lane** (5–7 balls, no sidestep, no single jump
   covers the burst). Mitigation that does not touch D-056 [CONTESTABLE]: Isagi does not begin a
   wind-up while the horizontal line from him to the player runs along a walkway axis with less than
   2 HU of total height change between them — he relocates instead (his relocation timer is cut to
   4 s in that case). He still fires across paths, down onto them, and along stepped ones.
4. **address me arriving while another enemy demands movement** — until F8.
5. **Toucher + Wet Floor** (a 40% slow puts the player at 5.4 u/s against a 6.75 u/s lethal body that
   creates the slow). Preflight item 15 already flags Wet Floor's rating; under one-hit rules it is
   not a rating problem but an answerability one. Proposed [CONTESTABLE]: Wet Floor keeps "slippery"
   and drops the extra slow (the floor stays at 20%).
6. **Overtime and speed curses pushing chasers past the player** — preflight item 8, ruled in section 5.

Everything else in the roster has a learnable answer on paper. "On paper" is the honest limit of this
pass: the windows above assume the controller hits its specified numbers and the telegraphs are as
readable in fog as the spec says. The answerability harness in the tickets (section 6) is what turns
this table into a test.

---

## 5. Rulings on the three parked preflight items

These are the design lead's proposed resolutions. None is applied to DESIGN.md yet; the tickets in
section 6 apply them after the owner accepts. All three are [CONTESTABLE] by nature.

### 5.1 Preflight item 8 — floating chasers outrunning the player

Problem: toucher floats at 6.75 u/s and kills on touch; overtime adds +6% per tier (max +48%), Rush
Hour +8% × 3, Hunger +5% repeatable, Zoomies +60%. At overtime tier 6 the toucher does 9.2 u/s against
a 9 u/s player who is bound to a winding path. The quick fix was "cap at 85% of run speed". That is
not enough, for two reasons: the toucher makes its own slow (a glitched player runs 7.2 u/s, below an
85% cap of 7.65), and a flat cap silently deletes overtime, Rush Hour and Hunger once it binds.

**Ruling: pursuit ceilings, with the overflow converted into tempo.**
1. Every floating body has a **pursuit ceiling**: its horizontal speed after ALL multipliers is
   clamped to a fraction of BASE run speed (9 u/s — base, not the player's current speed, so the
   player's own speed upgrades always gain ground and no curse can invert the race):

   | body | base speed | ceiling (× 9 u/s) | ceiling in u/s | why this number |
   |---|---|---|---|---|
   | kiwi cat | 5.6 | 0.80 | 7.2 | stays below Weighed Down's 8.1 u/s |
   | kitten (The Litter) | 4.5 | 0.70 | 6.3 | always behind its cat |
   | YOU?! | 3.4 | 0.55 | 4.95 | it is a ring enemy; its body must stay walkable-away |
   | toucher | 6.75 | **0.75** | **6.75** | it never speeds up at all: it must stay below a glitched player's 7.2 u/s |
   | seal (flapping; the dash is an attack, not pursuit) | 4.0 | 0.60 | 5.4 | |
   | Claude | 4.0 | 0.55 | 4.95 | |

2. **Bursts are exempt but bounded**: a telegraphed sprint (Zoomies) may reach 1.00 × base run speed
   for at most 3.0 s. A burst is answerable by height (F1) and the hurdle; a sustained speed is not.
3. **Overflow becomes tempo**: whatever part of a speed multiplier the ceiling removes is applied to
   that enemy's cycle instead — idle/cooldown time is divided by the unused factor, floored at 60% of
   the base cycle. For the toucher, which has no cooldown, it shortens the glitch interval
   (2.0 s → at most 1.2 s). So overtime, Rush Hour and Hunger keep biting at every tier; they stop
   being able to make a body unbeatable.
4. Vertical tracking (F1, 2.0 u/s) is never multiplied by anything.

Check against the cases that broke: overtime tier 8 + Rush Hour × 3 on a toucher → still 6.75 u/s,
glitch interval 1.2 s. Kiwi cat under the same → 7.2 u/s, below a Weighed Down player (8.1). Zoomies
→ 8.96 u/s for 3 s, clamped to 9.0. Player on glitched floor (7.2) vs toucher (6.75) → the player
still gains 0.45 u/s, i.e. the floor is a pressure, not a sentence.

### 5.2 Preflight item 17 — the seal on 1-wide paths

Problem: DESIGN.md §5.9 and Pup Pack give "sidestep" as the answer. On a 1-wide walkway there is no
side. The quick fix was "the dash holds its starting height". Worked through, that is incomplete: it
does not say what the line IS, how far away the seal may start it, or how much height clears it.

**Ruling: the dash is a fixed 3D line, started only from a readable distance, and a jump is the answer.**
1. At telegraph start the dash line is fixed as the straight 3D segment from the seal's body centre
   through the player's centre (0.9 u above the player's feet), extended to 20 u. It does not re-aim
   during the 0.75 s telegraph or the 1.0 s dash. The dashed telegraph is drawn along that 3D line,
   not flattened onto the ground.
2. The seal starts a telegraph only when it is **between 4 u and 12 u** from its target. Closer than
   4 u it keeps flapping (4 u/s, body contact kills — that is a chaser problem with a chaser answer).
   Reason: with the bark at dash start and 20 u/s, the seal reaches a target 4–12 u away 0.2–0.6 s
   after the bark — inside one jump.
3. What clears it: the seal's body radius is 0.3 u (F2), so the player is missed if their feet are
   more than 1.2 u above the height their feet had at telegraph start, or their head is below the
   line. Jump height exceeds 1.2 u from 0.12 s to 0.63 s after take-off (12t − 16t² > 1.2): a
   **0.51 s window** for a 0.07 s crossing. **"Jump on the bark"** is therefore correct for every
   legal telegraph distance. A height step also clears it: **3 HU up or 3 HU down** (2 HU is not
   enough — worked out: at +2 HU the feet are 1.0 u up, 0.2 u short). Sidestepping ≥ 0.7 u works
   wherever the path is 2 wide or the player is on a platform.
4. Pup Pack's counter-play text becomes "jump each bark" (its second seal runs its own line 0.5 s
   later). With seals capped at 3 and staggered (F7) the barks never coincide.

### 5.3 Preflight item 18 — the glitched floor against Athletic

Problem: the floor "slows the player and locks abilities" (D-051). Dasher loses the dash, Glider the
glide, Athletic nothing — the class has no active ability, so half of the toucher's floor and all of
coil's 2.0 s ability lock do not exist for one class in three. The quick fix was "give Athletic an
equivalent penalty", unspecified.

**Ruling: "abilities" means the class's signature, and Athletic's signature is its stride.**
While abilities are locked (glitched floor, coil's shockwave lock, any future lock):
- Dasher: the dash cannot be used; its cooldown does not tick.
- Glider: a glide cannot start and an active glide ends.
- **Athletic: stride lock** — the class's +15% run speed is suspended, its ×1.5 multiplier on speed
  upgrades becomes ×1.0, and its ×1.3 air-jump height becomes ×1.0. Upgrades themselves still work
  at their normal strength.

Why this and not a flat penalty: it is symmetric (each class loses exactly what its class gives it,
and nothing it bought), it needs no new stat (it switches existing class multipliers off), and it
reads correctly in the fiction of a "lock". Numbers: an Athletic with no upgrades drops from 10.35 to
9.0 u/s when locked, and to 7.2 u/s on the floor — identical to the other two classes on the floor.
With four Yearn for Speed stacks: 16.6 → 12.6 u/s locked.

One check this ruling exposes, for the harness (not a change): the terrain proof guarantees
AUTHORING-envelope jumps at run speed 9 × 0.9. A player who takes off from glitched floor runs
7.2 u/s. Reach at 7.2 u/s is 5.4 u flat, 4.7 u at +2 HU, 3.6 u at +4 HU, against authored maximums
of 4, 3 and 2 cells — still clearable. Under Wet Floor's 40% (5.4 u/s) the flat case is 4.05 u for a
4-cell gap: no margin. That is a second, independent reason for the Wet Floor change in section 4.

---

## 6. Implementation tickets (house format)

Standing clause, part of EVERY ticket below — copy it into the dispatch verbatim:
> **FROZEN:** ENEMIES.md behavior sentences are the spec (D-040). The 12-enemy roster, the shape
> contract (D-025) and every ruling through D-063 are FINAL. You build the systems around the
> enemies; you do not redesign an enemy. If anything in this ticket contradicts ENEMIES.md or a FINAL
> decision, do NOT resolve it: add a row to `PARKED.md` (ticket, the two conflicting passages, what
> you built in the meantime), build the reading closest to ENEMIES.md, and continue.
> If you are blocked on a name or an asset: TBD fallback, never stall.

Order: T-070 must be accepted by the owner and merged BEFORE Wave 3 (the enemy tickets T-030…T-041)
is dispatched — it supplies numbers those tickets would otherwise invent. T-071 and T-072 extend
T-027 and can run in Wave 2 beside it. T-073–T-075 run with Wave 4.

**T-070 — Enemy systems spec amendment [BLOCKS-FLEET for Wave 3]**
THE OWNER'S SPEC: "You design the systems around the enemies, not the enemies." "every enemy needs a survivable answer a player can learn. List any enemy that is unanswerable under one-hit rules." "Every judgment call the specs do not cover gets a [CONTESTABLE] tag."
Assignment: spawn (model:acpRegistry_mistral_vibe/deepseek-v4) — document ticket, fresh thread, no code.
Read: research/fable-enemies.md (all), DESIGN.md §5 and §7, DECISIONS.md D-040, D-051, D-053, D-056, D-061.
Do: write into DESIGN.md §5, each as a numbered system rule with its numbers and each logged as a new DECISIONS entry marked [CONTESTABLE] until the owner rules: (1) floater altitude rule, F1 (2.0 u/s vertical easing); (2) the body-size table, F2; (3) coil's landing target = last grounded tile and push = 8 u/s decaying to 0 over 0.5 s; (4) stagger and spawn separation for copies, F7; (5) address me / gin scheduling, F8; (6) pursuit ceilings and overflow-to-tempo, §5.1; (7) the seal dash line, 4–12 u start range and what clears it, §5.2; (8) ability lock per class incl. Athletic stride lock, §5.3; (9) Claude wind shot numbers (7.0 u/s, 4.0 s, dies on any slab), section 4 item 2; (10) Isagi does not wind up along a flat in-line walkway, section 4 item 3; (11) gin stands on platform tiles only; (12) Last Light's 8 u knock-back at the dais; (13) first-shown levels, caps, chaser ceiling and the NEW / REPEAT / FREE altar rule, sections 1 and 3; (14) Wet Floor loses its extra slow. Update every counter-play line in §5 and §7.1 to the answers of section 4, and the T-030…T-041 block in FLEET_PACK.md so each enemy test asserts its answer window.
Done-when: every item above is in DESIGN.md with a number; `grep` finds no "sidestep" as the only answer for the seal; DESIGN.md §7.1 + §7.2 still has 46 rows and §8 has 36; no ENEMIES.md line changed (`git diff --stat ENEMIES.md` empty); PARKED.md lists the two parked items of this document.

**T-071 — Floater kinematics, pursuit ceilings, stagger (extends T-027)**
THE OWNER'S SPEC: "item 8 (floating chasers outspeeding the player at high curse tiers, toucher 6.75 u/s vs run 9 u/s)". "what stacking the same enemy multiple times does to fun; propose caps or scaling."
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: DESIGN.md §5 (after T-070), §12 Enemy API; research/fable-enemies.md §0 F1/F7 and §5.1.
Do: in `sim/enemy_runtime.gd`: `FloatBody` (horizontal speed from `enemy.json`, vertical easing 2.0 u/s toward the target's feet, both in sim ticks); `pursuit_ceiling` and `burst_ceiling` fields read from `enemy.json`; the clamp applied after overtime, curses and Hunger; the overflow factor exposed as `tempo_mul` to the behavior (floor 0.6 of base cycle); `stack_phase(k, n)` = cycle × k / n; spawn separation ≥ 30 u between copies using the D-056 fallback order. `tests/test_floaters.gd`: at overtime tier 8 + Rush Hour × 3 the toucher's speed is exactly 6.75 u/s and its glitch interval 1.2 s; a kiwi cat never exceeds 7.2 u/s; Zoomies never exceeds 9.0 u/s nor lasts more than 3.0 s; a 4 HU climb opens ≥ 1.0 s of vertical separation; two coils land half a cycle apart.
Done-when: test green; boundary scan clean (no enemy id in `sim/`); replay determinism test still green.

**T-072 — Enemy scheduling arbiter and class ability lock (extends T-027, T-012)**
THE OWNER'S SPEC: "item 18 (toucher's floor vs Athletic, who has no ability to lock)". "Counter-play map: every enemy needs a survivable answer a player can learn."
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: DESIGN.md §4, §5.2, §5.8, §5.10, §5.12 (after T-070); research/fable-enemies.md §0 F8 and §5.3.
Do: `sim/enemy_arbiter.gd`: a declarative gate each enemy.json may set (`appear_requires`: no enemy body within N u; no targeted telegraph on the player; player grounded; not on glitched floor / `yields_to`: enemy ids supplied by DATA, never named in code) — used by address me and gin through data only. `sim/controller.gd`: `lock_abilities(ticks)` implemented per class from `data/player.json` (`lock_effect`: dash_disabled / glide_disabled / class_multipliers_off). `tests/test_arbiter.gd`: address me never appears with a body within 12 u, with a nuke ring or gin patch on the player, or while airborne; gin never marks during address me's countdown. `tests/test_lock.gd`: Athletic 10.35 → 9.0 u/s when locked and 7.2 u/s on glitched floor; speed upgrades count ×1.0 while locked; Dasher cooldown does not tick; an active glide ends.
Done-when: both tests green; `core/` and `sim/` name no content id (boundary scan).

**T-073 — Enemy data pass**
THE OWNER'S SPEC: "Vote economy: recommended enemy offering per intermission across 30 levels … propose caps or scaling."
Assignment: spawn (model:opencode/opencode/inkling-2-small-free)
Read: DESIGN.md §5 tables (after T-070).
Do: copy into each `content/enemies/<id>/enemy.json` exactly: body height and hit diameter, pursuit ceiling, burst ceiling, first-shown level, max votes, preferred anchor kind, counter-play line, tell line. No behavior code. A script `tools/check_enemy_data.gd` compares every field to the DESIGN.md tables.
Done-when: the script prints 12/12 and exits 0.

**T-074 — Offer draw: NEW / REPEAT / FREE altars, caps, chaser ceiling (extends T-023)**
THE OWNER'S SPEC: "VOTING RULES (canon): enemies can be voted/selected multiple times — select an enemy 5 times and there will be 5 enemies in play." and "propose caps or scaling."
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: DESIGN.md §6 (after T-070); research/fable-enemies.md §3.
Do: in `sim/offers.gd` the three-altar rule of §3.2, the per-enemy caps, the chaser ceiling (6, kittens ½), never the previously picked type on the REPEAT altar, seeded. `tests/test_offers.gd`: 1,000 seeded runs to level 30 — a NEW altar is present at every vote while an eligible unpicked type exists; no cap or ceiling is ever exceeded; all 12 types have been offered at least once by the level-19 vote in ≥ 99% of runs; picking the same enemy at every vote reaches exactly its cap and then is no longer offered.
Done-when: test green; `test_schedule.gd` (T-023) still green — the cadence is untouched.

**T-075 — Answerability harness**
THE OWNER'S SPEC: "every enemy needs a survivable answer a player can learn." "The old build failed on fun, not gates."
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: research/fable-enemies.md §4 (the counter-play table is the test list); TERRAIN_SPEC.md §4–5.
Do: `tools/answer_lab.gd`: five hand-written micro-levels as tile lists (a 1-wide flat lane 24 u; a 2-wide stepped lane; a dead-end nook on a 1-wide walkway; a 7×7 pad; the hub) and, per enemy, one scripted "answer bot" that plays ONLY the documented answer from the telegraph event (hurdle on arrival; jump on the bark; leave the ring; stop at once; step behind a 2 HU rise…). For each (enemy, micro-level) pair that section 2 calls relevant: 200 seeded trials at base stats, no upgrades, Last Light spent. Also the stacked cases at the proposed caps, and the three combination cases of F8.
Done-when: every pair survives ≥ 95% of trials with the documented answer AND ≤ 5% with no input (the enemy must actually be dangerous); a pair that fails either bound is reported with its numbers and parked — the harness is not tuned to pass, and no enemy number is changed by this ticket.

**T-076 — Counter-play text: lobby panels and tips**
THE OWNER'S SPEC: "Mini altars stand in the lobby; each altar exhibits one option: an enemy shown off as its PNG sprite model with a description". "a rotating, data-driven tip pool (15+ tips, prioritizing gift-vs-hazard tells)."
Assignment: spawn (model:opencode/opencode/inkling-2-small-free)
Read: DESIGN.md §5 counter-play lines (after T-070), `data/tips.json`.
Do: one tell line and one answer line per enemy on its altar panel, verbatim from DESIGN.md; add tips for: the hurdle, "jump on the bark", "touch ben to get past him", "out of options with a charge in hand: jump" (the void dive), "Last Light is dim at 0 charges". Keep ≥ 8 tips tagged `hazard_tell`.
Done-when: `test_content.gd` green; tips count ≥ 18; a script proves each panel line equals its DESIGN.md line.

### Parked for the owner (not resolved here, because the clean fix touches something FINAL)

| # | item | why it is parked | what the tickets do meanwhile |
|---|---|---|---|
| P1 | Isagi's spawn fallback sends him to a `lane` anchor (D-056, FINAL), where his body blocks the path and he fires along it | the clean fix is a different fallback for Isagi (nearest platform tile), which changes D-056's order | T-070 item 10: he does not wind up along a flat in-line walkway and relocates sooner; D-056 untouched |
| P2 | ENEMIES.md's answer to the nuke is "Break line of sight"; D-025 terrain has almost nothing overhead, so the working answer is "leave the sphere" | changing either the canon sentence or the shape contract is not this pass's call | counter-play text names both; the harness measures how often line of sight can actually be broken, per level bucket, and reports it |

### What is and is not established by this document

Established on paper, with arithmetic shown: which enemies have an answer under one-hit rules, the
jump windows for each, the six unanswerable cases, and three rulings for preflight items 8, 17, 18.
Not established: that any of it is fun or readable in fog — no playable build exists. T-075 is the
first point at which these claims meet a simulation; until it runs, every "yes" in section 4 is a
prediction.

