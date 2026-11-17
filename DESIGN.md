# DESIGN.md — VOIDWRAP RUN

Canon sources, in priority order: the owner's brief (VOIDWRAP_CANON + constraints) → ENEMIES.md (fixed
roster and hard rules) → TERRAIN_SPEC.md → this file. Every number here is a specification, not a
suggestion. `[CONTESTABLE]` marks a 50/50 call the owner may flip. `[CANON]` marks owner-set facts.

Units: 1 u = 1 m. Roblox reference speeds are converted at **1 stud = 0.5625 u** (player run speed
16 studs/s ↔ our 9 u/s). Currency is stored as integer hundredths of a gold ("centi") and displayed
with two decimals.

---

## 1. Pillars

1. **The terrain is the puzzle.** Spawn is the root; everything branches from the beacon.
2. **Silly enemies, serious world.** Bright meme PNG billboards hunting you through a solemn, foggy,
   checkered voxel abyss. The contrast is the game's identity. The terrain never jokes.
3. **Leave safe and poor, or linger for gold.** The one decision the whole loop exists to create.
4. **Always collecting.** No mechanic may starve the level of real gifts.
5. **Drop-in content.** Enemies, curses, upgrades, biomes, gimmicks and modes are added without
   touching the core.
6. **Seed in, world out.** Deterministic, input-driven simulation. Multiplayer later = sync seed + inputs.

## 2. Feel budget (acceptance numbers — retro §5.1)

| moment | target |
|---|---|
| loading screen on initial load and on run start | ≥ 5.0 s shown [CANON]; ≤ 8 s total at level 30 |
| lobby gate → next level controllable | ≤ 2.0 s (no loading screen between levels) |
| level start → first gift collected (competent player) | ≤ 8 s (terrain H10 guarantees a gift ≤ 30 cells away) |
| any other mandatory non-interactive wait | ≤ 2.0 s. There are NO vote timers in single-player |
| death → run-over screen with killer shown | ≤ 2.0 s |
| void fall → respawn on the last safe tile | ≤ 0.8 s (0.0 s at Sure Foot ×2) |
| beacon entry → lobby controllable | ≤ 3.0 s |
| frame time, level 30, 22 enemies, 1080p | p99 ≤ 16.6 ms |
| simulation tick (60 Hz), 22 enemies | ≤ 2.0 ms mean |
| generate + mesh a level-30 level | ≤ 1.5 s |
| target black-phase time, competent player | L1 90 s · L10 150 s · L20 200 s · L30 240 s |
| target run length | median 20–30 min |

Who decides "fun": the owner, by playing the alpha. Agents optimise the numbers above and nothing
else; a metric that is green while a row above is violated is a bug in the metric.

## 3. Core loop [CANON]

1. Spawn on the beacon dais. The beacon is **CLOSED**.
2. Collect every **black gift** (all slots with `occ = 0`).
3. The last real black gift opens the beacon (**OPEN**: white, emissive, light column — visible from
   anywhere through the fog). At the same instant a **gold gift** appears at every slot that held a
   black gift — same slot id, same position. Tripmines stay where they are.
4. The player chooses: enter the beacon now, or stay for gold.
5. Entering the beacon (trigger radius 1.5 u) completes the level → intermission lobby.

A level is complete **only** by entering the open beacon. No timer ends a level. Death ends the run.

### 3.1 Player state
- **Void charges: 2.** A new run starts with **2** void charges and the HUD shows them as **2 pips**
  (filled = held, hollow = spent). **Charges carry over between levels: there is no reset at a level
  boundary** — the only ways to gain a charge are the beacon's restore (below) and the start of a new
  run. Charges are the second axis of the leave-or-linger decision: lingering risks charges that
  leaving would restore.
- **Void fall** (below the kill plane): **−1 charge**; the player respawns on the last safe tile after
  0.8 s with 1.0 s of respawn invulnerability (enemy contact, tripmines and the nuke do not kill during
  it) and a chain reset. **A fall at 0 charges is a real death** (`D-VOID`) — no respawn, run over.
  Two charges therefore buy two falls; the third kills.
  - Safe tile = solid, not glitched floor (toucher-infected), not inside any hazard footprint (mine
    blast radius, nuke ring, void zone, shockwave ring, telegraphed patch) at the moment of respawn,
    and **at least 6 u from every enemy body and projectile**; re-validated against the current world
    state before teleporting.
  - History = a ring of the last 8 round-trip-reachable tiles the player stood on for ≥ 0.5 s, held
    in simulation state (a pure function of the inputs — no extra synced state). Respawn takes the
    newest entry that passes re-validation; if none does, the player's spawn tile on the dais.
- **Entering the beacon restores exactly 1 charge on entry, capped at 2** (Hungry Void: cap 1). It also
  restores the Subspacial Barrier shield (§8). Nothing else restores a charge; Field Dressing (§8) only
  makes one fall per level free.
- **Last Light**: once per run, and ONLY while the player holds at least 1 void charge, a killing blow
  from an enemy, a tripmine or the nuke instead teleports the player to the beacon dais with the
  charges they had and 2.0 s of invulnerability. **The arrival also pushes every enemy body within
  8 u of the dais radially out to exactly 8 u from the dais centre — a one-time reposition, no kill,
  no behavior change (D-073)** — so the save cannot drop the player into a radial ambush around the
  beacon. At 0 charges Last Light does nothing: every death at
  0 charges is real, and a void fall at 0 charges is always a real death (`D-VOID`). Nothing
  resurrects at 0. HUD icon: lit while armed (unspent and charges ≥ 1), dim at 0 charges, grey once spent.
- Every death records its **killer** and a **death code**, shown on the run-over screen:
  `D-KIWI D-COIL D-ISAGI D-NUKE D-YOU D-MINE D-TOUCH D-SEAL D-ADDR D-CLAUDE D-GIN D-VOID`
  plus `D-CURSE:<curse id>` when a curse caused the death. The killer is the last thing that killed
  the player: a void fall is its own killer (`D-VOID`), and a knockback or launch that does not kill
  is never the killer. thicc ben has no death code because ben cannot kill (§5.3). Killer names shown
  are the roster names (e.g. "gift Larper (Tripmine)").

### 3.2 The gold phase — the risk/reward engine
- Gold gift base value **2.00 g**.
- **Chain multiplier**: starts ×1.00 at beacon open; each gold gift collected within **4.0 s** of the
  previous one adds +0.05; cap **×2.00**; missing the window resets to ×1.00, and so does each of the
  three chain-breaking events that still exist: **a void fall**, **a defused or shielded tripmine**,
  and **thicc ben's eject**. HUD shows it next to the purse (e.g. `149.00  1.50x`). → the gold phase is
  a speed-run of the route the player just learned in the black phase.
- **Overtime**: at beacon open the overtime tier is 0; every **20 s** it rises by 1 (max 8). Each tier:
  enemy movement speed +6%, enemy cooldowns −5%. Resets next level. → every extra second costs more.
- **Clear stipend** on beacon entry: `10 + 2 × level` g. Leaving immediately is poor, not broke.
- Economy upgrades (§8) raise gold value, chain window/cap and stipend.

Income model the economy is tuned against ("average player" = collects 50% of gold at mean chain ×1.4):

| level | slots S | stipend | gold income (avg) | total per level | cumulative |
|---|---|---|---|---|---|
| 1 | 40 | 12 | 52 | 64 | 64 |
| 5 | 56 | 20 | 74 | 94 | 394 |
| 10 | 76 | 30 | 99 | 129 | 969 |
| 15 | 96 | 40 | 121 | 161 | 1,694 |
| 20 | 116 | 50 | 146 | 196 | 2,589 |
| 25 | 136 | 60 | 171 | 231 | 3,660 |
| 30 | 156 | 70 | 197 | 267 | 4,900 |

A greedy player (100% gold, chain ×1.8) earns ≈ 2.4× the gold income; a cautious player earns only
the stipend + Paycheck.

### 3.3 Hazards on gift slots [CANON]
- Tripmines = the enemy **gift Larper**. They occupy gift slots (`occ = 1`), never their own positions.
- Chance per slot: 0 below level 5; 1/20 at level 5 → 1/10 at level 25, linear; exactly 1/10 forever
  after. Total replaced slots ≤ 20%. Curses/votes add flat mines under the same cap (TERRAIN_SPEC §6.8).
- Tell: black framed box, six-pointed star centre, constant pink particles (`#FF4FD8`), slow rotation
  (5-frame cycle, 1 rev / 4 s). Beyond **12 u** it shows the same rim glow as a black gift; inside
  12 u the particles and star are visible.
- **Contact** = the player's centre within **0.9 u** (horizontal distance) of the tripmine box, at
  **any height** — jumping over a mine does NOT avoid contact. A tripmine is a wall on its tile: the
  walkable bypass is the only way past it. A bypass is a walkable route that stays outside the mine's
  0.9 u trigger cylinder. On contact: blast radius 3 u, **kills**. Resolution order on contact:
  1. **Defuse roll** (Defuse Kit, §8): `roll = mix(mix(run_seed, level), slot_id) mod 100`; if
     `roll < 20 × stacks` (cap 60) the mine is **defused** — it is consumed, there is no blast and no
     death, and the chain resets. With 0 stacks the roll can never pass.
  2. **Subspacial Barrier** (§8): if a shield is held, the shield is consumed and the mine is consumed
     with no blast; the chain resets.
  3. **Last Light** (§3.1): if it is unspent and the player holds at least 1 void charge, it is
     spent as the final save (teleport to the beacon dais); the mine is consumed.
  4. Otherwise the player is **killed** (`D-MINE`).
  The order is fixed: defuse roll, then Subspacial Barrier shield, then Last Light (D-053).
  The generator guarantees that no mine sits on a tile without a walkable bypass (TERRAIN_SPEC §6.8,
  validator check; the terrain decision for the tripmine bypass rule is D-026) — a mine can always be
  walked around.
  The defuse roll is a pure function of `(run_seed, level, slot_id, stacks owned)` — all synced state,
  so every client computes the same outcome and a mine's fate is fixed for the whole level. `mix` is
  the terrain generator's mix function (TERRAIN_SPEC §3). Buying a stack re-rolls the level's mines
  deterministically; that is intended — the upgrade visibly turns some mines into duds.
- **Nothing absorbs the nuke** (§5.5) — the Subspacial Barrier applies to tripmines only — but the
  missile's line-of-sight ray and its descent are blocked by any prop, any `spire` pad, any `bastion`
  tower and any tile slab (D-064); a missile that meets one detonates there.
- Mines are never highlighted, never counted in "gifts remaining", never needed to open the beacon.
- **Straggler beam**: when ≤ 20% of REAL black gifts remain, each remaining one emits a vertical beam
  (`#7CFFF4`, to Y +40 u). Same rule for gold gifts in the gold phase.

## 4. Classes [CANON roster]

Shared kit: run 9 u/s, jump velocity 12 (apex 2.25 u), gravity 32, coyote 0.10 s, jump buffer 0.10 s,
variable jump cut (release = vertical speed × 0.5), auto step-up 0.5 u, air control 100%.

| class | kit |
|---|---|
| **Dasher** | Dash: 6 u in 0.20 s in the input direction (camera-forward if none), usable in air, vertical speed held at 0 during the dash. One charge, regenerates in **3.0 s** [CANON]. |
| **Glider** | Hold jump while falling: fall speed capped at 2.0 u/s, horizontal speed 10 u/s. Glide energy 3.0 s per airtime, refills on landing. (30 u of travel for 6 u of height.) |
| **Athletic** | +15% run speed from the start (10.35 u/s) [CANON]. Speed upgrades are ×1.5 as strong; double-jump upgrades give ×1.3 height [CANON]. No active ability. |

Class is chosen at a class altar in the pre-run lobby. No class is ever required by terrain (D-013).

**Ability lock (D-070, SR-6):** while a lock holds (the toucher's glitched floor, coil's landing
shockwave, any future lock) Dasher cannot dash and its cooldown does not tick; Glider cannot start a
glide and an active glide ends; Athletic gets the **stride lock** — its +15% run speed is suspended
and its ×1.5 speed-upgrade / ×1.3 air-jump-height multipliers become ×1.0 for the lock's duration
(purchased upgrades still work at normal strength; the airborne drop is 10.35 → 9.0 u/s, and 7.2 u/s
on glitched floor — the same as every class).

## 5. Enemies — the fixed 12 (ENEMIES.md is the roster; this section is the numbers)

Rules that apply to all 12 (ENEMIES.md HARD RULES, restated because they bind every enemy ticket):
- **KILL RULE**: every enemy effect is either a **kill** or a **non-killing effect** — there is no
  middle state and no numbers to subtract. Every enemy **body contact kills**, and every projectile,
  ring, beam, blast and void zone **kills on hit**. The only non-killing enemy effects are the three
  listed per enemy: thicc ben's touch (blur + eject, §5.3), coil's landing shockwave (knockback +
  ability lock, §5.2) and the toucher's glitched floor (slow + ability lock, §5.8). Nothing is
  absorbed except a tripmine by the Subspacial Barrier (§3.3).
- **BILLBOARDING**: every enemy is a PNG sprite that always faces the viewer. No side view exists.
- **HITBOXES**: the hit shape covers only the body in the PNG (the tight bounding box of pixels with
  alpha > 16), never the transparent padding. Hit shape = upright cylinder: diameter = 0.8 × body
  width, height = body height, in world units after sprite scaling.
- **TRANSPARENCY**: fully transparent backgrounds; validated in a test scene against fog and palette.
- **DISCLAIMER** in README and on the lobby's About plaque.
- **TBD FALLBACK**: if any agent refuses or is blocked on a name/asset: name "TBD", placeholder TBD
  PNG, full behavior wired, entry marked TBD. Never stall.
- Sounds are new designs per ENEMIES.md "New sound" lines; cue TIMINGS below are binding.
- Enemy logic runs in the deterministic simulation (the future server). Sprites, billboarding and
  gin ichimaru's spears are view-layer only (ENEMIES.md global notes).

Behavior source rule (DECISIONS D-040): the behavior sentence in ENEMIES.md is the spec. Numbers come
from nullscape.wiki where they fit that sentence (research/NULLSCAPE_PATTERNS.md §5), otherwise they
are set here. Image references use number + exact filename as ENEMIES.md requires.

Common spawn rule: enemies appear 6.0 s after level start (Early Bird: 2.0 s). The spawn tile is
chosen by a fixed fallback order, evaluated on the simulation state at that tick:
(a) the anchor of the enemy's preferred kind (table below);
(b) if the level has no anchor of that kind: a `lane` anchor;
(c) if no anchor qualifies: any round-trip-reachable tile at least 25 u from the spawn point.
The existing constraints stay: never within 25 u of the player, and among the candidates that pass,
the farthest-but-within 60 u of the player. The within-60 u preference is dropped at step (c) — a
round-trip tile farther than 60 u is still a legal spawn when no anchor qualifies. Tie-break so two
implementers pick the same tile: farthest from the player first, then the lowest anchor index (steps
(a) and (b)) or the lowest tile index in the level's tile order (step (c)). The choice reads only
simulation state — the player position, the level's anchor list and round-trip set, and the enemy's
own seeded stream — so it is deterministic and identical on every client. The anchor kinds that exist
are `perch`, `open`, `lane` and `nook` (D-056). "Floats" = moves in a straight line
through geometry and over the void at the stated speed.

Preferred anchor kind per enemy (this table is the spec; a paragraph that names a kind must agree):

| enemy | preferred kind | note |
|---|---|---|
| kiwi cat | `nook` | |
| coil | `lane` | stepped walkways and stair runs (§5.2) |
| thicc ben | none | teleports to the player; its initial position is fallback (c) |
| Isagi | `perch` | falls back per the order above (§5.4) |
| nuke | none | a launcher, no body on the map |
| YOU?! | `open` | |
| gift Larper | none | it lives in gift slots (§3.3) |
| toucher | `lane` | |
| seal | `lane` | |
| address me | none | appears 6 u in front of the player |
| Claude | `open` | |
| gin ichimaru | `perch` | his strike appearances keep his own 15–25 u rule (§5.12) |

`none` means the enemy has no preferred anchor kind: it skips (a) and (b). Ben's initial position is
fallback (c); the nuke has no body on the map; gift Larper lives in gift slots; address me appears in
front of the player.

### 5.0 System rules that apply to every enemy (FINAL via D-064…D-075)

**SR-1 — Floater altitude (D-065).** A floating enemy's feet height eases toward its target's feet
height at a maximum of **2.0 u/s** (a 4 HU climb = 2.0 u buys 1.0 s of vertical separation); its
horizontal speed is the speed stated in its section. The vertical easing is **never multiplied** by
any speed multiplier (overtime, curses, Hunger, bursts — D-068).

**SR-2 — Body sizes (D-065).** Body height / hit-cylinder diameter in u (the hit cylinder is 0.8 ×
body width per the HITBOXES hard rule, height = body height):

| enemy | height (u) | diameter (u) | consequence |
|---|---|---|---|
| kiwi cat | 1.0 | 0.9 | hurdle-able (apex 2.25 u) |
| coil | 1.0 squashed / 2.0 extended | 0.9 | hurdle-able while idle |
| thicc ben | 4.0 | 1.2 | not hurdle-able; touching him is the way past (the eject is the answer, §5.3) |
| Isagi | 1.8 | 0.7 | not hurdle-able; on a `lane` anchor he never stays past the dwell limit (§5.4) |
| YOU?! | 1.8 | 0.7 | not hurdle-able; slow (ceiling 0.55), so it is outwalked, not jumped |
| toucher | 1.4 | 0.8 | hurdle-able only with a clean jump (0.85 u margin at apex) |
| seal | 0.6 | 0.6 | easily hurdle-able; its dash is the threat (§5.9) |
| address me | 2.5 | — | no body contact; it is a countdown, not an obstacle |
| Claude | 2.0 | 1.6 | not hurdle-able; keeps its distance (within 20 u) |
| gin ichimaru | 1.8 | 0.7 | stands 15–25 u away on platform tiles only (D-072); contact is not his threat |

The nuke has no body; gift Larper occupies gift slots as the tripmine (§3.3) — the roster's other
rows carry no world size.

**SR-3 — Copies of one enemy (D-065).** Copy k of n of the same enemy starts its cycle offset by
**k/n of the cycle length**. The copy's behaviour is otherwise identical. Copies of one **chaser**
spawn at least **30 u apart** — each copy beyond the first takes the next candidate in the D-056
fallback order that satisfies the 30 u separation — so they arrive from different sides instead of as
one blob. Attacks then arrive as a rhythm the player can learn.

**SR-4 — Scheduling arbiter (D-067).** address me **appears** only when, on that tick, (a) no enemy
body is within 12 u of the player, (b) no ring or patch is on the player — a ring or patch is a nuke
ground ring, a gin marked patch, or a coil landing ring — and (c) the player is grounded and not
standing on glitched floor. If any condition fails, address me waits and appears on the first tick
all three hold. While address me's countdown runs, **gin does not mark a patch** (his cooldown keeps
ticking; the strike is deferred until the countdown ends). Neither enemy gains or loses any other
behavior: this only schedules them, so a "stop" and a "move" demand never overlap.

**SR-5 — Pursuit ceilings (D-068).** Every floating body has a pursuit ceiling: its horizontal speed
after ALL multipliers (overtime, curses, Hunger) is clamped to a fraction of **base** run speed
(9 u/s — base, not the player's current speed, so speed upgrades always gain ground and no curse can
invert the race):

| body | base speed (u/s) | ceiling | ceiling in u/s |
|---|---|---|---|
| kiwi cat | 3.0 | 0.40 | 3.6 |
| kitten (The Litter) | 2.4 | 0.30 | 2.7 |
| YOU?! | 3.4 | 0.55 | 4.95 |
| toucher | 6.75 | 0.75 | 6.75 |
| seal (flapping; the dash is an attack, not pursuit) | 4.0 | 0.60 | 5.4 |
| Claude | 4.0 | 0.55 | 4.95 |

**Bursts are exempt but bounded**: a telegraphed sprint (Zoomies) may reach 1.00 × base run speed for
at most 3.0 s. **Overflow becomes tempo**: whatever part of a speed multiplier the ceiling removes is
applied to that enemy's cycle instead — idle/cooldown time is divided by the unused factor, floored
at 60% of the base cycle; for the toucher (no cooldown) it shortens the glitch interval (2.0 s → at
most 1.2 s). So overtime, Rush Hour and Hunger keep biting at every tier; they can never make a body
unbeatable.

**SR-6 — Ability lock per class (D-070).** While a lock holds (glitched floor, coil's shockwave lock,
any future lock): **Dasher** cannot dash and its cooldown does not tick; **Glider** cannot start a
glide and an active glide ends; **Athletic** gets the **stride lock** — its +15% run speed is
suspended and its ×1.5 speed-upgrade multiplier and ×1.3 air-jump-height multiplier become ×1.0
(purchased upgrades themselves still work at their normal strength; Athletic drops 10.35 → 9.0 u/s
when locked, and to 7.2 u/s on glitched floor — identical to the other two classes on the floor).

| # | name (Nullscape) | min level | max votes | each vote adds |
|---|---|---|---|---|
| 1 | kiwi cat (Mart) | 1 | 4 | +1 cat |
| 2 | coil (Springer) | 1 | 3 | +1 coil |
| 3 | thicc ben (Bell) | 1 | 2 | +1 ben |
| 4 | Isagi (Guardian) | 11 | 2 | +1 Isagi |
| 5 | nuke (ICBM) | 5 | 2 | +1 launcher |
| 6 | YOU?! (Husk) | 3 | 2 | +1 YOU?! |
| 7 | gift Larper (Tripmine) | 5 | 5 | +3 flat extra mines (`extra_mines += 3`), under the 20% cap |
| 8 | toucher (Flesh) | 7 | 2 | +1 toucher |
| 9 | seal (Baby) | 3 | 3 | +1 seal |
| 10 | address me (Operator) | 9 | 3 | only one exists; each extra vote −5 s on its return interval |
| 11 | Claude (Cadence) | 15 | 1 | the one Claude |
| 12 | gin ichimaru (Voidbreaker) | 17 | 3 | −3 s on his strike cooldown |

Starter pool (pre-run and level-1 votes): kiwi cat, coil, thicc ben, seal.

### 5.1 kiwi cat — Image 1 = "kiwicat.png"
Floats toward the nearest player at **3.0 u/s** (33% of run speed; pursuit ceiling 0.40 → never above
3.6 u/s after multipliers, SR-5). Contact = **kill**. Meows every 3 s while within 14 u. Feet ease
toward the target's feet at 2.0 u/s (SR-1). 1 PNG.
*Pressure on the loop:* a slow clock that never stops; lingering in the gold phase lets it arrive.
*Where terrain makes it shine:* it cuts straight across the void while you must follow the walkways —
dead ends (`nook` platforms) and long detours turn a slow cat into a trap. Spawns at `nook`.
*Answer:* open ground — walk away. Thin path or dead end — **hurdle it** as it arrives: a jump
exceeds its 1.5 u reach from 0.16 s to 0.59 s of the jump, a 0.43 s window over a 0.14 s overlap
(closing speed 12.0 u/s, SR-2).

### 5.2 coil — Image 2 = "springer.png"
Cycle: idle 3.0 s → pre-jump cue 0.6 s ("boing", squash frames, a ring of radius 3 u drawn at the
landing zone) → arc flight 2.75 s → landing. **The landing zone is the player's last grounded tile**
(the tile the player most recently stood on when the cue started — never a mid-air position over the
void, never a predicted position). Landing on a player (within 1.2 u) = **kill**. Landing shockwave:
radius 6 u, pushes players outward at **8 u/s decaying linearly to 0 over 0.5 s** (2.0 u of travel —
enough to clear a 1-wide path from its centre, survivable on a platform ≥ 5 wide, D-066), **does not
kill**, locks class abilities for 2.0 s (SR-6). A jump timed so the player is airborne at landing
avoids the shockwave. 5-frame squash→extend cycle.
*Pressure:* forces movement; the knockback is what kills (off ledges).
*Terrain:* stepped walkways, ledges and stair runs (`lane` anchors) — anywhere a shove means the void.
*Answer:* leave the ring (1.2 u) and be airborne or > 6 u from the last grounded tile when it lands —
3.35 s of cue covers 6 u at a walk. An idle coil parked on the path is **hurdle-able** (1.0 u
squashed, SR-2).

### 5.3 thicc ben — Image 3 = "thiccben.png"
Every 13.35 s teleports to the closest player. Telegraph: black smoke at the destination for 1.25 s,
Westminster chime during the final 0.5 s. Destination is locked at smoke start = player position +
velocity × 0.5 s; a player who is ≥ 4 u from the locked point at arrival has broken the lock (ben
appears where they were). Touching ben: screen blur 3.0 s, player launched upward at 18 u/s (apex
≈ 5 u), bell rings. **Ben never kills by touch** — the launch is the danger, because it can throw you
into the void or into another enemy. 1 PNG; teleport is VFX.
*Pressure:* punishes standing still; the launch is a risky free super-jump for players who learn it.
*Terrain:* narrow 1-wide walkways and spire tops (a launch there usually ends in the void); under bridges the
launch slams you into the slab above.

### 5.4 Isagi — Image 4 = "isagi_idle.jpeg", Image 5 = "ISAGI_SHOOT.webp", Image 6 = "blueballprojectile.webp"
Prefers `perch` anchors (spawn rule §5, D-056 stays FINAL — he may fall back to a `lane` anchor);
every 12 s he relocates to the `perch` anchor nearest the player with line of sight, and falls back
to `lane` only when no perch qualifies. **Dwell limit: on a `lane` anchor he stays at most 4.0 s
(240 ticks) before relocating** — the parked body is removed from the path quickly.
**Volley gap (D-064):** a burst is fired in **volleys of at most 3 balls, 0.15 s apart, and
consecutive volleys of one burst are separated by 0.75 s (45 ticks — one full jump)**, so each volley
is cleared by its own jump. With Egoist (+1 ball per stack → 4, 5 or 7 balls) the burst arrives as
3 + 1, 3 + 2 or 3 + 3 + 1 across volleys 0.75 s apart, never as one longer unbroken volley.
With line of sight from any anchor: wind-up 1.2 s (idle sprite flashes + voice cue) → the volleying
burst, 22 u/s, radius 0.5 u, life 3.0 s, stopped by any tile or prop → cooldown 2.5 s. Ball hit =
**kill**.
**Ball flight:** each ball leaves from **1.0 u above Isagi's tile** and flies **straight in 3D** to
the player's **centre at release** (centre = feet + 0.9 u); the line is fixed at release and never
homes. Hit test: the ball's centre within **0.5 u** of the player's centre. A **jump** (centre rises
up to 2.25 u) or a **2 HU step** (1.0 u) therefore clears the line — the ball passes under the
player; a 1 HU step (0.5 u) does not.
*Pressure:* denies open ground; turns the gold-phase sprint into cover-to-cover movement.
*Terrain:* bastion platforms and spire tops (perches) are his ground; nooks and `ell` corners break
his line. Props are sparse (0–7 per level, all on platforms), so height and corners are the cover you
can count on and a prop is a bonus.
*Answer:* get a 2 HU step between you and him, or jump after the release flash (the jump stays above
1.5 u for 0.43 s — longer than a volley's 0.30 s spread), or sidestep ≥ 0.9 u where the path allows;
on a `lane` anchor a jump per volley (0.75 s apart) clears Egoist bursts too, and he is gone within
4.0 s.

### 5.5 nuke — Image 7 = "NUKE.jpeg"
Loop: lock a player (ground ring follows them) and track 2.5 s with a beep rising 2 → 8 Hz → the ring
stops → missile descends 1.5 s (4-frame looping sprite) → explosion: sphere radius 5 u, **kills** →
5.0 s pause → repeat. Line of sight is traced from a point 12 u above and 20 u away (direction fixed
per salvo); if terrain or a prop blocks it for 0.5 s continuous during tracking, the lock breaks and
tracking restarts after 2.0 s. **Salvo life limit (D-064): one salvo — tracking, including every
restart after a broken lock, plus the descent — lasts at most 6.0 s (360 ticks) from its first
tracking tick; if it has not detonated by then it expires harmlessly and the 5.0 s pause starts.**
**Blocking (D-064): the line-of-sight ray and the descending missile are blocked by any prop, any
`spire` pad and any `bastion` tower — and by any tile slab or step riser standing between the ray
(or the missile) and the ring centre; a missile that meets one detonates there.**
*Pressure:* a metronome that forbids staying in one place.
*Terrain:* overlapping pieces — passing under a bridge or a higher platform breaks the lock; walls,
pillars and props do too. Wide platforms and the spawn hub (`open` anchors) are where it is deadliest.
*Answer:* **leave the 5 u sphere within 1.5 s** (13.5 u of running at full speed; ≤ 11 u even from the
back of a 6-wide `nook`), or **put a prop, a `spire` pad, a `bastion` wall or a tile slab between you
and the sky** — both answers are named because either works on its own.

### 5.6 YOU?! — Image 8 = "character to be corrupted.png"
Floats toward the nearest player at 3.4 u/s (pursuit ceiling 0.55 → never above 4.95 u/s, SR-5);
feet ease at 2.0 u/s (SR-1). Within 10 u: corrupted rumble 1.5 s → shockwave ring from its position:
expands 9 u/s to radius 14 u, 1.0 u tall, 0.6 u thick, travels in the horizontal plane of its feet
± 1.5 u, drawn as a 1.0 u **tall translucent red band, not a ground decal** (its plane must be
readable); hit = **kill**. Jumpable. Ring cooldown 4.0 s. Touch = **kill**. 5-frame corrupted run
cycle.
*Pressure:* rhythm tax — you must jump on its beat while doing everything else.
*Terrain:* open platforms and the spawn hub (nowhere to break the plane); terraces and stair runs are the answer — one
step up of ≥ 1.5 u and the ring passes below.
*Answer:* jump as the ring reaches you (jump height > 1.0 u from 0.10 s to 0.65 s — a 0.56 s window
for a 0.16 s crossing), or stand ≥ 1.5 u above or below its feet. Under Echo Ring: jump 0.25–0.65 s
before the first ring and jump again on landing — hard but learnable.

### 5.7 gift Larper — Image 9 = "tripine.png"
The tripmine (§3.3). Stationary, sits in gift slots. 5-frame rotation cycle. Each vote = +3 flat mines.
*Pressure:* taxes speed — the gold-phase chain rewards rushing, mines punish not looking.
*Terrain:* dead-end jackpots (dense slots = dense mines) and breadcrumb lines on walkways.

### 5.8 toucher — Image 10 = "toucher.jpeg", Image 11 = "glitchedground.jpeg"
Floats toward the nearest player at 6.75 u/s (pursuit ceiling 0.75 — its own base speed, so it never
speeds up under any multiplier: a glitched player at 7.2 u/s still gains 0.45 u/s, SR-5); feet ease
at 2.0 u/s (SR-1). Touch = **kill**. Every 2.0 s (at most 1.2 s once tempo conversion binds, SR-5) it
infects all tiles within 3 u below it (squelch cue when new tiles appear). Glitched tile:
lasts 12 s (18 s from level 14). Standing on it **does not kill**: it slows the player **−20% run
speed** and **disables class abilities** for as long as they stand on it (SR-6). Max 60 glitched
tiles per toucher. thicc ben's ring cleanses glitched tiles within 8 u. Finger: 3 flicker frames;
floor: 5 frames.
*Pressure:* closes routes; it herds you.
*Terrain:* chokepoints (narrow bridge walkways) and 1-wide walkways — a glitched 2-wide walkway is a wall, so
shortcuts and drops become the way home.
*Answer:* keep off its floor, keep height between you (it rises 2.0 u/s at most; you jump 2.25 u in
0.375 s), and **hurdle it on a path** — its 1.4 u body meets a clean jump with 0.85 u to spare at
apex (SR-2). Its glitched tiles invalidate the newest safe-tile ring entries, so a void dive near it
respawns you farther back — a real cost, and the tip text says so.

### 5.9 seal — Image 12 = "babehseal.webp"
**The dash is a fixed 3D line, started only from a readable distance, and a jump is the answer
(D-069).** Flaps toward the nearest player at 4 u/s (pursuit ceiling 0.60 → never above 5.4 u/s while
flapping, SR-5). At **telegraph start** the dash line is fixed as the straight 3D segment from the
seal's body centre through the player's centre (0.9 u above the player's feet), extended to 20 u; it
does **not re-aim** during the 0.75 s telegraph or the 1.0 s dash, and the dashed telegraph is drawn
along that 3D line, not flattened onto the ground. The seal starts a telegraph only when it is
**between 4 u and 12 u** from its target — closer than 4 u it keeps flapping (a chaser problem with a
chaser answer: hurdle it, SR-2). Attack: telegraph 0.75 s (dashed 3D line, mouth-open frame) →
**bark** on tick 0 of the dash + dash 20 u in 1.0 s along the fixed line → idle 0.75 s. Contact at any
time = **kill**. Small hitbox (0.6 u diameter, 0.3 u radius, SR-2).
*What clears it:* the player is missed if their feet sit more than 1.2 u above the height they had at
telegraph start, or their head is below the line. **Jump on the bark** — jump height exceeds 1.2 u
from 0.12 s to 0.63 s after take-off, a 0.51 s window for the 0.07 s body crossing, correct at every
legal telegraph distance. A **3 HU step** (1.5 u, up or down) also clears it (2 HU = 1.0 u is not
enough). A **sidestep ≥ 0.7 u** works wherever the path is 2 wide or the player is on a platform.
*Pressure:* burst threat that punishes straight-line running — exactly what a breadcrumb trail invites.
*Terrain:* long straight walkways (`lane` anchors). Height breaks the line: steps,
terraces, ledges.
*Answer:* jump on the bark, or stand a 3 HU step above/below the line, or sidestep ≥ 0.7 u on a
2-wide path or platform. Pup Pack's counter-play text is "**jump each bark**" — its second seal runs
its own fixed line 0.5 s later, and seals capped at 3 with stagger (SR-3) keep the barks from
coinciding.

### 5.10 address me — Image 13 = "address me elephant.png", Image 14 = "explosionsffect.jpg"
One at a time. Appears 6 u in front of the player with an elephant trumpet — but ONLY under the
scheduling gate of SR-4 (D-067): it waits until no enemy body is within 12 u of the player, no ring
or patch is on the player, and the player is grounded and not on glitched floor, then appears on the
first tick all three hold. A 5.0 s rumble counts
down. The player must become **still**: no movement/jump/ability input and speed < 0.5 u/s on all
axes, held for 1.5 continuous seconds. Achieved → it leaves. 5.0 s expire first → explode frame, boom,
**kill**. Returns every 30–45 s (−5 s per extra vote, min 15–30 s); never in the first 10 s of a level.
While its countdown runs, gin does not mark (SR-4).
*Pressure:* the only enemy that makes you STOP — while everything else says move.
*Terrain:* being caught mid-walkway, mid-glide or mid-jump is the danger; `nook`s are the answer.
*Answer:* **stop at once** — do nothing for 1.5 s, 3.5 s of slack. SR-4 guarantees it never arrives
while a chaser, a nuke ring, a gin patch or a coil ring makes stillness lethal.

### 5.11 Claude — Image 15 = "claudelogo.png" (+ clawd Crab plushie sprite, 3 idle frames, source in ENEMIES.md)
One only. Floats at 4 u/s keeping within 20 u of the player. Music loop at 100 BPM (beat 0.6 s, bar =
4 beats). One attack per bar, cycling:
- **Drums** (UI chimes): on beats 1 and 3 a radial ring from Claude — 12 u/s to radius 18 u, 1.0 u
  tall, **kills**. Jump on the beat.
- **Strings** (keystroke ticks): telegraph line for 1 beat, then a beam 24 u long × 1.5 u wide sweeps
  120° over 4 beats at 0.5–1.5 u height, **kills**. Blocked by tiles and props. Jumpable.
- **Wind** (notification pings): beats 1, 2, 3 each launch a homing shot — **7.0 u/s, turn 90°/s,
  life 4.0 s (D-071), kills; the shot dies on touching ANY tile slab or step riser (≥ 1 HU), and on
  any prop**.
**Agitation** 0–100 rises 2/s. Tempo = 100 + 0.6 × agitation BPM. At 100 ("Deadline"): all three
attacks every bar. A clawd Crab plushie spawns every 25 s on a round-trip tile 10–25 u from the
player (max 3 present); picking one up (squeak-pop) = −35 agitation.
*Pressure:* a second collectible that competes with gifts for your route.
*Terrain:* open platforms are bad, props and height are good — it makes you re-value every platform.
*Answer:* its floats keep its body at ceiling 0.55 (4.95 u/s — outwalkable, SR-5); **drums**: jump on
the beat; **strings**: keep ≥ 6 u from Claude and put a height step or a prop between you and the
telegraph line; **wind**: run in a straight line (7.0 u/s vs 9.0 — you gain 2 u/s) or drop one tread
—a shot dies on any slab or riser (D-071).

### 5.12 gin ichimaru — Image 16 = "gin idle.png", Image 17 = "ginsword.png"
Fades in on a tile 15–25 u from the player. **He stands on platform tiles only (D-072):** his
fade-in tile is always a platform tile (never a walkway tile — his body must never block or cut the
only route home); if no platform tile qualifies under his 15–25 u rule, he uses the **farthest tile of
the spawn hub** (farthest from the player). Strike: the 5×5 tile patch centred on the player's tile
is marked (red outline `#FF2A2A`, deep cracking rumble) for 2.0 s → launch pose, sword-spears streak
to the patch in 0.3 s (view-layer VFX only) → the patch is a **void zone** for 10 s: its tiles are
non-solid and anything that enters its column is **killed** → tiles fade back over 0.5 s (a player
inside is lifted onto the surface). Cooldown 14 s (−3 s per extra vote, min 5 s). Never marks the
beacon dais, and never marks while address me's countdown runs (SR-4). Gifts over a void zone stay
but cannot be reached until it closes.
*Pressure:* rewrites the puzzle live.
*Terrain:* walkways — cutting a 2-wide causeway severs an arm for 10 s; loops, drops and pads become
survival tools.
*Answer:* walk out of the patch — 3 cells, 0.33 s of running inside a 2.0 s mark — and change
direction during a Twin Fangs double mark; his body is never on the path (D-072), so only the patch
threatens you.

## 6. Intermissions and the OFFERING SCHEDULE

Data: `data/offering_schedule.json` — one tunable file. Specific enemies/curses/upgrades are drawn
randomly (seeded) from their pools; the schedule fixes only the CATEGORY.

Bays: **E** enemy vote (mandatory, pick 1 of 3; "×2" = two votes back to back, re-drawn between) ·
**C** curse (mandatory, pick 1 of 3 — or pay the tithe) · **U** upgrade shop (optional) ·
**REST** shop at −20%, no vote, no curse (the beacon already restored your charge) · **CLASS** pre-run only.

| after level | offers | enemies in play next level | act |
|---|---|---|---|
| 0 (pre-run) | CLASS + E (starter pool) | 1 | |
| 1 | E + U | 2 | I — learn |
| 2 | C | 2 | |
| 3 | E | 3 | |
| 4 | C + U | 3 | |
| 5 | REST | 3 | breather |
| 6 | C + E | 4 | act finale |
| 7 | E + U | 5 | II — settle |
| 8 | C | 5 | |
| 9 | E | 6 | |
| 10 | C + U | 6 | |
| 11 | REST | 6 | breather |
| 12 | C + E | 7 | act finale |
| 13 | E + U | 8 | III — squeeze |
| 14 | C | 8 | |
| 15 | E | 9 | |
| 16 | C + U | 9 | |
| 17 | REST | 9 | breather |
| 18 | C + E×2 | 11 | act finale |
| 19 | E×2 + U | 13 | IV — crowd |
| 20 | C | 13 | |
| 21 | E | 14 | |
| 22 | C + U | 14 | |
| 23 | REST | 14 | breather |
| 24 | C + E×2 | 16 | act finale |
| 25 | E×2 + U | 18 | V — flood |
| 26 | C | 18 | |
| 27 | E×2 | 20 | |
| 28 | C + U | 20 | |
| 29 | REST | 20 | breather |
| 30 | C + E×2 | 22 | act finale |
| 31+ | rows 25–30 repeat forever | +6 per act | endless |

Logic:
- **Six-level acts.** Each act: open with pressure + power (E+U), then pain (C), pressure (E), pain +
  power (C+U), a breather (REST — nothing bad happens here, ever), and a finale that stacks pain and
  pressure with no shop (C+E).
- **Pain is a metronome**: a curse after every even level, exactly [owner: "every 2 levels"].
- **Pressure accelerates**: 3 votes per act in acts I–II, 4 in III, 5 in IV, 6 from V on (E×2).
- **Power is steady**: 3 shops per act (one per two levels — retro §4c). Power never accelerates, so
  the squeeze is real; the economy answers with bigger purses, not more shops.
- **Breathing room** is guaranteed at levels 5, 11, 17, 23, 29: discounted shop, no vote, no curse.
- The level after a finale is the hardest step of each act; the player just had a REST two levels
  earlier and carries the purse from two shop-less levels into the E+U that follows.
- **Enemy offer draw — NEW / REPEAT / FREE (D-074).** The three E-altars of an E bay are no longer
  "3 distinct enemies from the eligible pool"; each vote shows: one **NEW** altar (an eligible enemy
  type with 0 votes; lowest first-shown level first, ties by seeded draw), one **REPEAT** altar
  (a type already in play, below its cap — never the type picked at the previous vote; in an E×2 bay
  the second draw treats the first draw's pick as that previous vote), and one **FREE** altar
  (seeded draw from everything eligible and not already shown). If a category is empty its altar
  becomes FREE. Every vote is then the same legible question: a new problem, or more of one already
  handled — while a stacked-type vote stays possible.
- **Chaser ceiling (D-074): at most 6 floating lethal bodies in play at once** (kiwi cat, toucher,
  YOU?!, seal — The Litter's kittens count as half each). An altar that would exceed it is not drawn.
  Six is a sequence of hurdles a player can read; ten is a wall.
- If an enemy pool is exhausted (all at max votes), an E bay offers "Hunger" instead: +5% speed for
  all enemies, repeatable.

## 7. Curses (46 at launch)

System (inspired by the Nullscape pattern, not copied — DECISIONS D-041):
- Offered at C bays: 3 curse altars. Picking one is mandatory to open the gate…
- …unless the player pays the **tithe**: `100 + 75 × (tithes paid this run)` g to walk past. Spend
  vs. save pressure from the pain side.
- Every curse altar shows a **bounty** paid on pick: Mild 20 g, Harsh 45 g, Brutal 90 g, each ×
  `(1 + level/20)`. The harshest curse is always the richest.
- Gating: `min_level`; enemy-linked curses appear only if that enemy has ≥ 1 vote.
- Picking removes a curse from the pool unless it stacks; stackable ones leave at max stacks.
- One reroll of the whole bay per C intermission, free.
- Draw: 3 distinct curses from the eligible pool; at least one Mild if any Mild is eligible.
- **Safety rule (binding on all future curses):** no curse may reduce jump velocity, raise gravity,
  or reduce run speed by more than 10% in total — the terrain proof (TERRAIN_SPEC §5) assumes the
  base kit. No curse may remove real gifts or raise the per-slot mine chance. **The glitched floor's
  −20% is an enemy effect, not a curse, and does not count toward the 10%:** the terrain proof only
  needs the base kit's jump envelope, and the floor slow never touches jump velocity or gravity.
  Wet Floor does NOT raise that enemy slow: D-075 fixes the glitched floor's slow at 20% for
  everyone and Wet Floor adds only slipperiness (friction ×0.4) — still an enemy effect, still
  outside the curse budget.

Severity: M = Mild, H = Harsh, B = Brutal. "st" = max stacks.

### 7.1 Enemy-linked (24)

| id | name | needs | min lvl | sev | st | rule | counter-play |
|---|---|---|---|---|---|---|---|
| zoomies | Zoomies | kiwi cat | 3 | M | 2 | every 12 s each cat sprints at +60% speed for 3 s after a double meow | a burst is bounded: ≤ 0.55 × base run (4.95 u/s) for ≤ 3.0 s, then back under its 0.40 ceiling (SR-5) — gain height (it rises 2.0 u/s, SR-1) or hurdle it as it arrives |
| litter | The Litter | kiwi cat | 8 | H | 1 | each cat is followed by a kitten (60% size, 2.4 u/s, kills on contact) 6 u behind | a kitten's ceiling is 0.30 (2.7 u/s, SR-5) — it always trails its cat: hurdle cat then kitten in one rhythm, or kite them into a line and cross |
| overwound | Overwound | coil | 2 | M | 2 | coil idle time 3.0 → 2.0 s (then 1.5 s) | leave the ring and be airborne or > 6 u away at landing (§5.2); the shove decays over 0.5 s and never kills |
| aftershock | Aftershock | coil | 9 | H | 1 | landing sends a second shockwave 0.5 s later, radius 9 u | double jump |
| quarter_chimes | Quarter Chimes | thicc ben | 4 | M | 1 | ben's teleport interval 13.35 → 9 s | keep moving |
| long_toll | The Long Toll | thicc ben | 10 | H | 1 | every ben teleport tolls twice: a second ben arrives at the same locked point 1.5 s after the first | air control is 100% — steer ≥ 4 u sideways during the launch |
| egoist | Egoist | Isagi | 8 | H | 2 | +1 ball per burst per stack | the volley gap (D-064): a burst arrives as volleys of ≤ 3 balls, 0.75 s (45 ticks — one full jump) apart, so each volley is cleared by its own jump (§5.4) |
| direct_shot | Direct Shot | Isagi | 14 | B | 1 | balls ricochet once off tiles/props | break sightline entirely — a ricochet kills too, so don't hug cover |
| second_strike | Second Strike | nuke | 6 | H | 1 | a second missile lands 1.0 s after the first on your new position | keep running after the first — the second kills too |
| bunker_buster | Bunker Buster | nuke | 12 | B | 1 | explosions delete props within the blast for the rest of the level | fight in the open on purpose, save cover |
| double_ring | Echo Ring | YOU?! | 5 | M | 1 | every shockwave is followed by a second ring 0.6 s later | two jumps |
| mirror_match | Mirror Match | YOU?! | 12 | H | 1 | YOU?! uses your class kit: dashes 6 u every 5 s / ignores height (glides) / moves +15% | watch your own cooldown |
| method_acting | Method Acting | gift Larper | 6 | H | 1 | mine tells are visible only within 6 u (was 12 u) | Radar Module: Mines; slow down at jackpots |
| understudies | Understudies | gift Larper | 5 | M | 3 | +4 flat extra mines per stack (20% cap still holds) | Defuse Kit |
| wide_blast | Stage Presence | gift Larper | 9 | H | 1 | mine blast radius 3 → 4.5 u and the blast chain-detonates mines inside it | never stand near a second mine |
| spreading_rot | Spreading Rot | toucher | 7 | H | 1 | each glitched tile infects one adjacent tile after 6 s (max 2 generations) | leave early, use ben's ring |
| wet_floor | Wet Floor | toucher | 5 | M | 1 | glitched tiles are slippery (friction ×0.4); the toucher's slow stays −20% — no extra slow (D-075) | jump across, don't walk; the slow stays 20%, so a glitched player at 7.2 u/s still gains 0.45 u/s on the toucher (SR-5) |
| pup_pack | Pup Pack | seal | 4 | H | 1 | every seal has a second seal that dashes 0.5 s after it | **jump each bark** — each seal's line is fixed at its own telegraph start and the barks never coincide (caps + stagger, D-069/SR-3) |
| slipstream_trail | Wet Trail | seal | 2 | M | 1 | a dash leaves a slippery trail (friction ×0.4) for 3 s | don't cross the line |
| longer_speech | Filibuster | address me | 7 | H | 1 | you must hold still 2.5 s instead of 1.5 s | stop sooner |
| unannounced | Unannounced | address me | 10 | B | 1 | no trumpet — only the sprite and the rumble | keep it on screen; Radar Module: Threats |
| crescendo | Crescendo | Claude | 16 | H | 1 | agitation rises 3/s instead of 2/s | plushies first |
| token_limit | Token Limit | Claude | 18 | B | 1 | plushies remove 20 agitation instead of 35 and spawn every 30 s | route for plushies |
| twin_fangs | Twin Fangs | gin ichimaru | 17 | B | 1 | each strike marks two patches: yours and where you will be in 1.0 s | change direction during the mark |

### 7.2 General (22)

| id | name | min lvl | sev | st | rule | counter-play |
|---|---|---|---|---|---|---|
| thick_fog | Thick Fog | 1 | M | 2 | fog density 0.012 → 0.018 (→ 0.024) | radar modules; beacon light column still shows |
| lights_out | Lights Out | 2 | M | 1 | player fill light range 18 → 11 u | learn the route in the black phase |
| unmarked | Unmarked | 1 | M | 1 | no straggler beam | Radar Module: Gifts |
| dull_gifts | Dull Gifts | 3 | M | 1 | black gift rim glow visible only within 20 u | sweep platforms methodically |
| tarnish | Tarnish | 2 | M | 2 | gold gift value −20% per stack | chain harder; More |
| short_chain | Short Chain | 4 | M | 1 | chain window 4.0 → 3.0 s | Hot Streak |
| inflation | Inflation | 3 | M | 3 | shop prices +15% per stack | Bargain; save |
| no_refunds | Sealed Deals | 6 | M | 1 | shop reroll plinth is gone | — |
| brittle | Brittle | 2 | H | 2 | a void fall's respawn delay is 1.6 s instead of 0.8 s and the respawn invulnerability is 0.5 s instead of 1.0 s (2 stacks: 2.4 s / 0.0 s) | Sure Foot; don't fall inside a platform you have not cleared |
| hungry_void | Hungry Void | 1 | H | 1 | charge cap becomes 1 (the beacon restores 1, capped at 1) | Field Dressing; enter the beacon at 0 charges |
| weighed_down | Weighed Down | 5 | H | 1 | −10% run speed during the gold phase | leave earlier |
| rush_hour | Rush Hour | 4 | H | 3 | all enemies +8% movement speed per stack | — |
| early_bird | Early Bird | 2 | M | 1 | enemies spawn 2 s after level start instead of 6 s | move first, plan later |
| long_night | Long Night | 6 | H | 1 | overtime tiers every 14 s instead of 20 s | shorter gold runs |
| curfew | Curfew | 8 | H | 1 | 60 s after the beacon opens, overtime jumps +2 tiers | plan a 60 s gold route |
| rearguard | Rearguard | 5 | H | 1 | when the beacon opens, one extra copy of a random enemy in play spawns at the beacon | don't finish next to the beacon |
| crowded_dais | Crowded Dais | 7 | H | 1 | the beacon cannot be entered while any enemy is within 8 u of it | lead them away first |
| slow_door | Slow Door | 3 | M | 1 | entering the beacon takes 3.0 s of standing in it | clear the area |
| hasty | Hasty | 9 | B | 2 | every enemy telegraph is 15% shorter per stack | Early Warning |
| crumbling | Crumbling | 10 | B | 1 | 1-wide walkway tiles fall 1.2 s after being stepped on and return after 5 s | keep moving; never returns to a soft-lock because they regrow |
| leaky_purse | Leaky Purse | 4 | M | 1 | a void fall drops 5% of this level's earned gold (max 20 g per fall) | Stand Fast; Field Dressing |
| cold_start | Cold Start | 3 | M | 1 | class ability starts each level on cooldown and recharges 25% slower (Athletic: coyote time −0.05 s instead) | Quick Recovery |

## 8. Upgrades (36 at launch) and the shop

System:
- Currency: gold from gold gifts (+ stipend, bounties). Bought at U and REST bays: 3 upgrade altars.
- Each altar sells once per visit. Optional. A reroll plinth redraws all three for 15 g (+15 g per
  use that visit).
- Stacking upgrades cost `price × 1.5^(stacks owned)`, rounded to whole gold.
- **Per-level pools [CANON]**: the shop never shows the full catalog. `data/upgrade_pools.json` maps
  level brackets to the eligible ids; an upgrade also needs `tier min level ≤ level`.
- **Affordability filter [CANON]**: an item is offered only if `price ≤ max(2 × purse, 80)`; if fewer
  than 3 items pass, the cheapest remaining pool items fill the altars.
- Draw: 3 distinct, not at max stacks, weighted ×2 for items the current class boosts, seeded.

Price tiers and when they enter the pool:

| tier | price range | pool from level | intent |
|---|---|---|---|
| T1 | 40–80 g | 1 | foundational; one per early shop |
| T2 | 120–200 g | 4 | a real choice vs. two T1 |
| T3 | 280–400 g | 10 | build-defining |
| T4 | 550–800 g | 18 | must be saved for (skip a shop) |
| T5 | 1,100–1,500 g | 26 | run-warping; two acts of saving |

Economy targets (the economy-audit bot in FLEET_PACK asserts these with the §3.2 income model):
- The average player can afford ≥ 1 offered item in ≥ 80% of shops.
- The average player can afford all 3 offered items in ≤ 30% of shops (spend-vs-save stays real).
- Average purchases per run to level 30: 18–24. Cautious player (stipend + Paycheck only): 6–10.

Level-1 pool [CANON]: Paycheck, More, Yearn for Speed.

| id | name | tier | price | st | effect |
|---|---|---|---|---|---|
| paycheck | Paycheck | T1 | 40 | 3 | +25 g on beacon entry per stack [CANON] |
| more | More | T1 | 50 | 5 | +10% gift yield per stack [CANON] |
| yearn_for_speed | Yearn for Speed | T1 | 60 | 4 | +10% run speed per stack (Athletic +15%) [CANON] |
| field_dressing | Field Dressing | T1 | 45 | 2 | once per level per stack, a void fall costs no charge |
| long_reach | Long Reach | T1 | 60 | 3 | pickup radius +40% per stack |
| radar_beacon | Radar Module: Beacon | T1 | 40 | 1 | HUD compass and distance to the beacon |
| radar_gifts | Radar Module: Gifts | T1 | 70 | 2 | arrow to the nearest real gift within 40 u (80 u at 2) |
| ledge_grace | Ledge Grace | T1 | 50 | 2 | coyote time +0.08 s per stack |
| brace | Brace | T1 | 80 | 3 | coil's shockwave push and ben's eject −30% per stack (push 8 → 5.6 → 3.9 → 2.7 u/s; eject 18 → 12.6 → 9.0 → 6.3 u/s) — the launch super-jump shrinks with it |
| sure_foot | Sure Foot | T1 | 70 | 2 | void-fall respawn delay −0.4 s per stack (0.8 → 0.4 → 0.0 s) and respawn invulnerability +1.0 s per stack (1.0 → 2.0 → 3.0 s) |
| gilded_touch | Gilded Touch | T2 | 150 | 3 | gold gift base value +1.00 g per stack |
| hot_streak | Hot Streak | T2 | 140 | 2 | chain window +1.0 s per stack |
| nest_egg | Nest Egg | T2 | 160 | 2 | on beacon entry gain 5% of unspent gold, max 30 g, per stack |
| bounty_hunter | Bounty Hunter | T2 | 130 | 1 | curse bounties +50% |
| bargain | Bargain | T2 | 120 | 2 | shop prices −10% per stack |
| spring_heels | Spring Heels | T2 | 180 | 2 | +1 air jump per stack at 80% jump height (Athletic: 104%) |
| featherfall | Featherfall | T2 | 150 | 1 | hold jump to cap fall speed at 6 u/s (Glider: +1.5 s glide energy instead) |
| quick_recovery | Quick Recovery | T2 | 160 | 2 | class ability cooldown −20% per stack (Athletic: +5% speed instead) |
| defuse_kit | Defuse Kit | T2 | 200 | 3 | +20% chance per stack that a tripmine defuses instead of killing (cap 60%); the roll is fixed per (seed, level, slot) — §3.3 [CANON] |
| stand_fast | Stand Fast | T2 | 170 | 1 | the first chain-breaking event each level (void fall, defused or shielded tripmine, ben's eject) does not reset the chain |
| insulation | Insulation | T2 | 150 | 1 | glitched floor slows 10% instead of 20% and no longer disables class abilities |
| radar_threats | Radar Module: Threats | T2 | 160 | 1 | screen-edge markers for enemies within 30 u |
| straggler_scope | Straggler Scope | T2 | 140 | 1 | straggler beams start at the last 35% instead of 20% |
| early_warning | Early Warning | T2 | 180 | 2 | enemy telegraphs last 15% longer per stack |
| subspacial_barrier | Subspacial Barrier | T3 | 350 | 1 | 1 shield per level, restored on beacon entry: absorbs exactly one tripmine (checked after the defuse roll), consumed; tripmines only — nothing absorbs the nuke [CANON] |
| radar_mines | Radar Module: Mines | T3 | 300 | 1 | disguised tripmines within 14 u get a pink outline through fog [CANON] |
| high_ceiling | High Ceiling | T3 | 320 | 1 | chain cap ×2.00 → ×2.50 |
| last_call | Last Call | T3 | 300 | 1 | the final 20% of gold gifts in a level are worth double |
| slipstream | Slipstream | T3 | 300 | 1 | +20% speed for 2.0 s after any gift pickup |
| cold_blood | Cold Blood | T3 | 280 | 1 | overtime tiers rise every 30 s instead of 20 s (Long Night: 21 s instead of 14 s) |
| twin_dash | Twin Dash | T3 | 340 | 1 | Dasher only: 2 dash charges |
| updraft | Updraft | T3 | 340 | 1 | Glider only: once per glide, press jump to rise 3 u (6 s cooldown) |
| marathon | Marathon | T3 | 340 | 1 | Athletic only: +2 max stacks of Yearn for Speed |
| cartographer | Cartographer | T4 | 600 | 1 | minimap of every piece within 40 u of anywhere you have stood, with real gifts |
| skeleton_key | Skeleton Key | T4 | 750 | 1 | the beacon opens at 90% of real black gifts; the rest turn gold in place |
| pocket_beacon | Pocket Beacon | T5 | 1,200 | 1 | once per level: 3.0 s channel (must stand still) to teleport to the beacon dais |

Counter-play map [CANON]: tripmines ← Defuse Kit (20%/stack defuse, deterministic), Subspacial Barrier
(1 shield), Radar Module: Mines · the nuke ← leave the 5 u sphere, or put a prop, a `spire` pad, a
`bastion` wall or a tile slab between you and the sky — nothing ABSORBS its blast (D-064) · glitched
floor ← Insulation · fog/information curses ← radar family · economy curses ← Bargain, More, Hot
Streak · overtime ← Cold Blood.

## 9. Progression and difficulty curve

"Harder" is defined by five dials, all data:

| level | terrain D (TERRAIN_SPEC §10.4, measured) | slots | enemy votes | curses held | mine chance |
|---|---|---|---|---|---|
| 1 | bucket 1–5 mean | 40 | 1 | 0 | 0 |
| 6 | | 60 | 3 | 2 | 21/400 |
| 12 | | 84 | 6 | 5 | 27/400 |
| 18 | | 108 | 9 | 8 | 33/400 |
| 24 | | 132 | 14 | 11 | 39/400 |
| 30 | | 156 | 20 | 14 | 1/10 |

Targets for the tuning bot (FLEET_PACK defines the bot): a scripted "competent" bot (collects by
nearest-gift routing, dodges telegraphs with 250 ms reaction) reaches level 6 in ≥ 80% of runs,
level 12 in 40–60%, level 18 in 15–30%. The bot's survival model is the game's: any enemy contact,
projectile, ring, beam, blast or void zone kills it, and it has the same 2 void charges. These bands
are the bar the enemy numbers must meet — if a band is missed, tune enemy speeds/cooldowns/telegraphs
in `content/enemies/*/enemy.json`, never the bands and never the terrain thresholds.

Meta-progression: none at launch (pure roguelite; best level and best purse are recorded locally).

## 10. Biomes and level variety

Variety comes from three independent layers:
1. **Terrain**: arm traits × 8 platform archetypes × 5 walkway archetypes × parameters × shortcuts.
2. **Biome** = a palette family + fog density, swapped per act. Geometry is unaffected (biome is
   view-layer only, so it never touches the terrain hash).
3. **Roster/curses**: which enemies and curses the player voted in re-values every platform type (§5).

| act | biome | platform light / dark | walkway light / dark | fog | void | density |
|---|---|---|---|---|---|---|
| I (1–6) | Deepwater | `#2FB7B0` / `#0A2E30` | `#2A5BFF` / `#0B1A66` | `#021416` | `#010B0C` | 0.012 |
| II (7–12) | Verdigris | `#5E9E6A` / `#0E2A14` | `#B45CFF` / `#2E0F52` | `#04140A` | `#020A05` | 0.012 |
| III (13–18) | Violet Hour | `#C13CFF` / `#2A0A3A` | `#FF3C7A` / `#4A0A22` | `#12021A` | `#0A0110` | 0.013 |
| IV (19–24) | Indigo Trench | `#4C6BFF` / `#0A1040` | `#2FE0D0` / `#06332F` | `#03061C` | `#02030F` | 0.014 |
| V (25–30) | Pale Abyss | `#B8C7CC` / `#1E2A2E` | `#6FA8FF` / `#14284A` | `#0A1114` | `#05090B` | 0.015 |
| 31+ | cycles I→V | | | | | 0.015 |

Rules for every biome: one hue family for platforms, one contrasting family for walkways; danger stays
red/pink (so Violet Hour's walkway colour is hot pink-red but mines keep `#FF4FD8` particles AND the star
— a biome must pass the fog-readability check, TERRAIN_SPEC §12.3, including "tripmine particles vs
platform light ≥ 3.0 contrast"); gold stays gold; the beacon stays white.

Future gimmicks (NOT built now; listed so the extensibility contract has concrete customers): moving
platforms on walkway pieces, wind lanes, ice tiles, grind rails, a second beacon. Each is a gimmick
drop-in (§12) that reads anchors/pieces and never edits tiles.

## 11. The intermission lobby — a physical place [CANON]

**The Antechamber.** One fixed scene, built by a deterministic script (no hand-placed nodes).

- Hall 28 u (x) × 20 u (z), ceiling 8 u. Checkered floor in the CURRENT biome's platform colours, walls in
  slab-side colour with the trim band. A 9 u star sigil (walkway-light colour) on the floor centre.
  Urns, barrels and tall jars (procedural props) along the walls. Same fog and fill light as levels.
- The player arrives at (0, +8) facing −z. The **Descent Gate** stands at (0, −9.5): closed (dull)
  until every mandatory bay is resolved, then open (white, same visual language as the beacon). Walk
  in → next level. No timers. No menus. The mouse is never freed.
- **Bays** at x = −9 (left), 0 (centre), +9 (right), each with a floating banner at y = 5 u (display
  serif capitals, emissive; subtitle in italic below):
  `ENEMIES — Choose an adversary.` · `CURSES — Become accursed.` · `UPGRADES — Arm yourself.` ·
  `RESPITE — Catch your breath.` · `CLASSES — Choose who falls.`
  Scheduled bays are lit and populated; unscheduled bays are dark with empty plinths. With one bay
  it uses the centre; with two, left and right.
- **Altars**: 3 per bay at x offsets −3, 0, +3, z = −4. Plinth 1.2 × 1.0 × 1.2 u. The exhibit hovers
  1.8 u above the plinth top, bobbing ±0.1 u at 0.5 Hz.
  - Enemy exhibit: the enemy's actual billboarded PNG sprite, animated with its real frames, scaled to
    1.6 u body height. Panel: name, the one-line behavior, one counter-play line, `In play: ×N`.
  - Curse exhibit: icon billboard 1.2 u with pink border. Panel: name, rule, counter-play, bounty.
  - Upgrade exhibit: icon billboard 1.2 u with aqua border. Panel: name, effect, price, `Owned: N/max`.
  - Class exhibit: the player model in that class's colours on the plinth.
- **Interaction**: within 2.5 u of an altar and looking within 60° of it → prompt `[F] Choose — <name>`
  and the panel (world-space, 2.4 u wide, above the exhibit). **Hold F for 0.35 s** (radial fill) to
  confirm. On confirm: the altar flares; in mandatory bays the other two altars sink into the floor
  over 0.6 s. In E×2 bays the three altars then rise again with a new draw.
- Extra plinths: tithe plinth (C bay, right side), reroll plinth (C: free once; U: 15 g rising).
  No restore plinth exists: the beacon restores a void charge on entry, and nothing else in the lobby
  touches charges.

- **About plaque** on the south wall, readable up close, with the disclaimer text (§14).
- Multiplayer later: every player selects; ties resolved by seeded draw; a 45 s timer appears only
  when 2+ players are present.

## 12. Extensibility contract

All `content/` and `data/` paths in this document are relative to the Godot project root `game/`.
New content is a new folder/file under `content/`. **Nothing under `core/` or `sim/` may name a
content id.** A CI test greps for every content id in those folders and fails on a hit. A second CI
test copies fixture content from `tests/fixtures/dropin/` into `content/`, boots headless, and asserts
each fixture is offered, selectable and functional — proving drop-in works without core edits.

```
content/
  enemies/<id>/enemy.json        # name, min_level, max_votes, vote_effect, anchor_kinds, stats{}, sprites
  enemies/<id>/enemy.gd          # extends EnemyBehavior: tick(state, self, dt_ticks, api), on_spawn, on_vote
  enemies/<id>/sprites/*.png     # frames; enemies/<id>/sprites.json = frame lists + body_rect per frame
  enemies/<id>/SOURCES.md        # where each PNG came from (ENEMIES.md image number + exact filename)
  curses/<id>.json               # name, severity, min_level, requires_enemy, max_stacks, modifiers[], hooks[]
  curses/<id>.gd                 # optional, only if modifiers/hooks cannot express it
  upgrades/<id>.json             # name, tier, price, max_stacks, class_only, modifiers[], hooks[]
  upgrades/<id>.gd               # optional
  biomes/<id>.json               # palette roles + fog density (TERRAIN_SPEC §12.2 role names)
  gimmicks/<id>/gimmick.json+.gd # level gimmick: on_level_built(level, api) may add sim entities at
                                 # anchors/pieces; may NOT add/remove tiles or slots
  modes/<id>/mode.json           # rule overrides + which offering_schedule / upgrade_pools files to use
data/
  offering_schedule.json  upgrade_pools.json  tips.json  economy.json  player.json
```

- **Registry**: at boot, scan each folder, sort by id (determinism), validate against a JSON schema,
  refuse to boot on a schema error with the file name in the message.
- **Modifiers** (declarative, cover ~80% of curses/upgrades): `{stat, op: add|mul|set, value, when?}`.
  Final stat = `(base + Σ add) × Π mul`, then `set` wins. `when` ∈ `always | black_phase | gold_phase |
  class:<id>`. Stat names are a closed list in `core/stats.gd` (run_speed, void_charges_max,
  void_fall_charge_cost, defuse_chance, barrier_shields, glitch_slow_mul, respawn_delay,
  respawn_invuln, pickup_radius, gold_value, chain_window, chain_cap, stipend_flat, shop_price_mul,
  fog_density, fill_light_range, enemy_speed_mul, telegraph_mul, overtime_period, …); adding a stat is
  a core change, using one is not.
- **Hooks** (for the rest): `on_level_start, on_gift_collected, on_beacon_open, on_beacon_enter,
  on_void_fall, on_charge_spent, on_charge_restored, on_mine_contact, on_mine_defused,
  on_barrier_absorbed, on_player_death, on_enemy_spawn, on_tick, on_shop_draw, on_curse_draw`. A hook
  handler receives `(state, api)` and may only change the world through `api` (spawn entity, kill,
  push, add gold, set flag) — never by touching nodes or globals. Handlers run in id order.
- **Enemy API**: `api.nearest_player(pos)`, `api.los(a, b)`, `api.anchors(kind)`, `api.tiles_in_radius`,
  `api.spawn_projectile(def)`, `api.telegraph(kind, shape, ticks)`, `api.kill(player, killer_id)`,
  `api.push(player, dir, speed)`, `api.lock_abilities(player, ticks)`, `api.rng()` (the enemy's own
  seeded stream). There is no partial-effect call: an enemy either kills or applies a non-killing
  effect. No other access.
- **Terrain archetypes** are the one exception: a new platform/walkway archetype changes level hashes, so it
  ships as a generator change (Python oracle first, GEN_VERSION bump, goldens, then GDScript parity).
- **Modes** (Standard only now): a mode = schedule file + pool file + rule overrides. Adding
  "Extreme" later = one folder.

## 13. Architecture — single-player first, multiplayer nearly free

```
terrain/   pure generator (GDScript port of terrain_ref). No Node, no engine types beyond Array/Dictionary.
sim/       deterministic simulation. RefCounted classes only. No Node, no scene tree, no engine physics,
           no Time, no randf(). Fixed 60 Hz tick. step(state, inputs) -> events.
core/      registry, stats, hooks, content loading, run/offer logic (pure, deterministic).
view/      everything Node-based: meshes from tiles, billboards, VFX, audio, HUD, lobby scene. Reads sim
           state and events; never writes sim state.
app/       main scene, input capture → input structs, loading screen, menus, settings.
content/ data/   (§12)
tools/     headless scripts: tests, bots, asset validators, Blender scripts.
tests/     run via tools/godot/godot.exe --headless
```

Determinism rules for `sim/` and `core/`:
1. State is one object tree (`RunState` → `LevelState` → players, enemies, projectiles, tiles-modified
   set, rng streams). No autoload singletons hold gameplay state. No static mutable variables.
2. The only inputs: the run seed, the content set, and per-tick `PlayerInput {move_x: int8, move_z:
   int8 (world-space, pre-rotated by the client's camera), buttons: bitmask, }` plus lobby choices
   (`Select {altar_index}`) — votes ARE inputs.
3. Movement and collision are our own kinematic code against the tile grid (AABB vs. tile slabs and
   props). Godot physics is used for nothing in `sim/`.
4. Randomness only through `Rng` streams stored in state (same Mulberry32 as the terrain).
5. Float math in `sim/` is limited to + − × ÷ and sqrt on 64-bit floats (IEEE-exact); no sin/cos/atan
   (use the input vector and lookup tables). Iteration only over arrays or id-sorted keys.
6. **Replay test** = the determinism proof: record inputs for a bot run, replay twice, state hashes
   must match at every 60th tick. This test is the multiplayer readiness gate.

What multiplayer needs later, and why it is nearly free: a transport that delivers
`{seed, content hash}` once and `PlayerInput`/`Select` per tick; the host runs `sim/` as authority,
clients run the same `sim/` for prediction, `view/` is already per-client (billboards, spears, audio).
Terrain is never sent. Nothing in `sim/` changes.

## 14. Presentation rules that are also acceptance criteria

- **Loading screen** [CANON]: shown on initial load and on run start; visible ≥ 5.0 s (holds at 5 s if
  loading is faster, shows real progress if slower); shows one tip from `data/tips.json` (≥ 15 tips;
  tips tagged `hazard_tell` are weighted ×3), rotating every 5 s if the load runs long.
- **HUD**: gifts `collected / real total` bottom-centre; purse + chain multiplier top-right; **void
  charge pips** bottom-left (one pip per holdable charge — 2, or 1 under Hungry Void; filled = held,
  hollow = spent); class ability cooldown; curse and upgrade icon rows top (collapsible with Tab);
  enemy roster icons with counts. Diegetic danger text (`THE <ENEMY> SHALL <VERB>`, `#FF2A2A`) floats
  at each enemy's spawn point for 4 s when it appears — carried over from the old build's look.
- **Disclaimer** (README and About plaque, verbatim): "VOIDWRAP RUN is a personal, non-commercial
  project — no money is involved, and it is not affiliated with, endorsed by, or connected to any
  person, brand, character, or IP referenced or depicted in the game."
- **Assets**: enemies = PNG sprite frames (committed, sources documented). Everything else (props,
  beacon, altars, gifts, player) = Blender-procedural: headless `.py` scripts are the source of truth,
  `.glb` files are build artifacts, no downloaded models. Terrain is generated meshes, not assets.
