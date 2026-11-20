# B5B - the bot dies on level 11; raise the bot, not the game

**Verdict: PARTIAL.** The level-11 death was measured, its cause was found and fixed, and
level 11 now falls to a *different* and precisely measured limit that is not the bot's
policy. Level 11 is still not green, so the 30-level proof stays open. No game number was
touched.

## 1. Measured first: where the bot dies, per seed

Driver: `game/out/b5b_driver.gd` (a copy of the working `old_driver_single_free.gd`, made
parameterised and given death attribution + a tick trace + a geometry dump). It drives the
shipped path: real `world.build`, real lobby, real purchases, ledger carried forward.
Runner: `game/out/b5b_run.gd`. Both gitignored, both in `game/out/`, nothing in
`game/tests/`.

```
<godot> --headless --path game --script res://out/b5b_run.gd -- <seed> <target_level> <min_level> <legs>
```

| seed | died on level | killer | code | tick | void charges | Last Light | purse | owned stacks | gifts left |
|---|---|---|---|---|---|---|---|---|---|
| 36 | 7 | seal | D-SEAL | 1629 | 1 | grey (spent) | 183 | ledge_grace=1 | 24 |
| 37 | 5 | kiwi cat | D-KIWI | 3084 | 2 | grey (spent) | 71 | yearn_for_speed=1 | 4 |
| 38 **before** | 11 | kiwi cat | D-KIWI | 2151 | 1 | grey (spent) | 212 | radar_threats=1, yearn_for_speed=1 | 48 |
| 38 **after** | 11 | void | D-VOID | 4797 | 0 | grey (spent) | 218 | radar_threats=1, yearn_for_speed=1 | 1 |
| 39 | 8 | seal | D-SEAL | 3202 | 2 | grey (spent) | 150 | brace=1, paycheck=1 | 1 |
| 40 | 3 | kiwi cat | D-KIWI | 3211 | 2 | grey (spent) | 83 | (none) | 1 |

Seed 38 is the outlier that reaches 11; the others die at 3-8. That matches D-C2-12's
recorded "no seed in 1..38 reaches 12 with this bot policy".

## 2. The cause of the level-11 death, from the trace

`B5B DEATH leg=A level=11 killer=kiwi cat code=D-KIWI tick=2151 charges=1 last_light=grey
purse=212 stacks=[radar_threats=1 yearn_for_speed=1] gifts_left=48 pos=(27.02,5.51,33.50)
grounded=false`

The bot is airborne, 0.80 u from a kiwi cat. The tick trace shows the mechanism:

```
t=2138 p=(27.54,6.61,33.50) g=false mv=(0,0)   land=(27.50,33.50) near[kiwi_cat d=1.45]
t=2144 p=(27.54,6.29,33.50) g=false mv=(0,0)   land=(27.50,33.50) near[kiwi_cat d=1.30]
t=2145 p=(27.54,6.21,33.50) g=false mv=(0,0)   land=(25.50,33.50) near[kiwi_cat d=1.27]
t=2146 p=(27.52,6.11,33.50) g=false mv=(-127,0) land=(25.50,33.50) near[kiwi_cat d=1.23]
...
t=2151 p=(27.02,5.51,33.50) g=false mv=(-127,0) land=(25.50,33.50) near[kiwi_cat d=0.80]
```

At tick 2145 the cat moves to (26.59,32.66), which puts the bot's own column 1.24 u from it
- just inside `LAND_CLEAR` (1.25). `_nearest_landing` re-picks the next nearest column that
clears the body: **(25.50,33.50)**, on the far side of the cat. The bot steers at it at full
speed and flies through the body.

The landing pick is a **point test, not a path test**. The column is clear; the fall to it is
not.

## 3. The fix (D-B5B-1), and what it bought

`game/tools/bot_run.gd` only. `_nearest_landing` gains a `block`/`block_r` pair and refuses a
column whose straight fall from the feet passes within the body's own contact radius
(`sim/enemy_runtime.gd` `body_contact`: `diameter_u * 0.5 + 0.4` - the cat's 0.85, not a new
number). When no column survives, the original pick is used unchanged.

```
B5B DEATH leg=A level=11 killer=void code=D-VOID tick=4797 charges=0 last_light=grey
purse=218 stacks=[radar_threats=1 yearn_for_speed=1] gifts_left=1 pos=(35.48,-40.51,41.45)
grounded=false
RUN30 A end: outcome=dead deepest=11 completed=10 lobbies=10 ledger_checks=80 purchases=2
stack_types_carried=5 purse=218 class=glider ticks=43560 ms=118318
```

The cat trap is gone. Level 11 goes from tick 2151 with 48 gifts left to tick 4797 with **1
gift left** - the bot now collects the whole level and dies on the way out.

**No regression.** Seeds 36, 37, 39 and 40 are byte-identical before and after the change
(same level, same killer, same tick, same purse, same stacks) - the filter never fires there:

```
--- seed 36  B5B DEATH level=7 killer=seal code=D-SEAL tick=1629 ... purse=183
--- seed 37  B5B DEATH level=5 killer=kiwi cat code=D-KIWI tick=3084 ... purse=71
--- seed 39  B5B DEATH level=8 killer=seal code=D-SEAL tick=3202 ... purse=150
--- seed 40  B5B DEATH level=3 killer=kiwi cat code=D-KIWI tick=3211 ... purse=83
```

## 4. Why level 11 still does not fall (D-B5B-2) - not the bot's policy

The remaining death is the platform collapse. Measured on seed 38, level 11:

```
B5B COLLAPSE ev=platforms_cracked tick=4381 player=(39.50,13.50,52.13) beacon=(0.50,0.50)
dist=64.70 fall_tick=4681
B5B COLLAPSE ev=platforms_fell tick=4681 player=(35.89,11.66,42.30) beacon=(0.50,0.50)
dist=54.77
```

The beacon opens on the last real black gift (`sim/gifts.gd` `all_black_collected` is the
only caller of `beacon.open`), and `sim/collapse.gd` starts on that same tick with
`FALL_TICKS = 300` - 5.0 s. The bot was **64.70 u** from the beacon. At the player's 9.0 u/s
base run that is **7.19 s**, before counting the jumps, the gaps, or the 13.5 u of height it
also has to lose. It was still 54.77 u out when the floor went. A player has the same 5.0 s.

So the honest statement is: the bot's policy was the limit up to the cat trap, and past it
the limit is the collapse window against the beacon distance. Fixing that means changing the
game (a longer window, or a rule that the last gift cannot be the farthest from the beacon),
which this ticket forbids. Recorded as D-B5B-2, not acted on.

## 5. What I tried and reverted (so the next attempt does not repeat it)

Each of these was measured on seed 38 and each made the bot die *earlier*:

| attempt | result | why it failed |
|---|---|---|
| refuse to hurdle a body whose feet are above the player's | level 4, D-KIWI, tick 2704 | the hop is load-bearing: it is what keeps the cat off the bot on a ledge |
| apply the avoid layer to the airborne heading | level 5, D-KIWI, tick 4716 | `_avoid_vector` returns a *perpendicular* ("run around it"), which is meaningless mid-fall |
| hard-reject landing columns whose fall crosses a body | level 4, D-KIWI, tick 2216 | with no fallback the bot picks a worse column |
| prefer the gift farther from the beacon when two remain | level 11, D-KIWI, tick 3240, 29 gifts left | reorders the whole run, which changes the lobby draws (purchases 2 -> 3) |

The last one is the interesting negative result: the bot's depth is chaotic in its own
choices, so a change that is right in isolation can still lose depth. The shipped fix is the
one that is inert on every seed where it does not fire.

## 6. Gate

`powershell -NoProfile -ExecutionPolicy Bypass -File tools/gate.ps1` - see the pasted final
lines below.

## 7. Deviations

- The driver is a **copy** (`game/out/b5b_driver.gd`), not `old_driver_single_free.gd`
  itself, because the original is gitignored and absent from a fresh worktree and I needed
  it parameterised (seed / target level / legs) and instrumented. It is the same code path.
- `MIN_LEVEL_REACHED` is a command-line argument here (1 for measurement runs) instead of
  the pinned 10, so a measurement run reports rather than fails. The proof run sets it to
  `TARGET_LEVEL`.
- Purse on seed 38 reads 212/218 here against D-C2-12's recorded 224. The antechamber
  `float(null)` fix (D-C2-13) landed after that measurement and changes the lobby build, so
  the lobby draws differ. Not investigated further; it does not affect the death.

## 8. New DECISIONS entries

- **D-B5B-1** - the airborne landing pick is a point test, not a path test.
- **D-B5B-2** - level 11 is not survivable after the beacon opens, and that is the
  collapse's arithmetic.
