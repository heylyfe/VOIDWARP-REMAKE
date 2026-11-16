# Paper fun audit — top 10 feel risks

Written 2026-11-16 by the design lead (Fable 5.2), against commit `14be164`. No playable build
exists, so every item is a prediction from the documents plus four measurements on the generator.
Each risk has: why I expect it, the **earliest cheap signal** that would confirm or kill it once the
build runs, and a **ticket-level mitigation**. Ranked by how much damage it does to the first ten
minutes of play. Mitigations that touch canon or a FINAL decision are marked NEEDS OWNER.

The lesson being applied: the earlier build passed its gates and was not fun. So every signal below
is something a player would feel, measured from the build's own event log — not a new gate.

**One enabling ticket makes eight of the ten signals free:**
T-080 — Run telemetry log. Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash).
Do: `sim` already emits events; `app/run_log.gd` appends one JSON line per event to
`user://runs/<seed>.jsonl` (level start/end, phase change, gift pickup with chain value, charge spent
with cause and nearest enemy distance, death with killer, killer on-screen yes/no in the 2 s before,
shop offers and purchases, curse offers and picks, lobby enter/exit) and `tools/run_report.gd` prints
the ten numbers named below from a folder of logs. Works for bot runs and human runs alike.
Done-when: a 100-run bot batch produces the report; a human run produces the same file.

---

### 1. Dying is instant and restarting is slow
Why: every enemy contact kills (D-051) and a run ends on death. The loading screen is shown "on
initial load and run start" for at least 5.0 s [CANON], then the pre-run lobby (class altar + enemy
altar, hold F). A new player will die in the first level repeatedly; each death costs ≥ 5 s of
loading plus a lobby walk before they can try again. One-hit games live on instant retry.
Earliest signal: `death → controllable in level 1` from the log. Above ~8 s, expect quits.
Mitigation (NEEDS OWNER — the 5 s minimum is canon): keep the 5 s minimum for the INITIAL load only;
on a restart show the tip for 1.5 s. Ticket-level, no canon change: "Retry" on the run-over screen
re-enters the pre-run lobby with the previous class preselected and the gate already open, so a retry
is: one altar, walk in.

### 2. Deaths you did not see coming
Why: enemies are billboards that float through geometry and over the void, fog hides distance, the
camera looks where the player runs, and one touch kills. A chaser arriving from behind or below
through the floor is invisible until contact. Radar Module: Threats — the only off-screen indicator —
is a T2 upgrade from level 4.
Earliest signal: share of deaths where the killer was off-screen for the whole 2 s before the kill.
Above 25% the game reads as unfair, whatever the answer windows say on paper.
Mitigation: make a minimal threat indicator baseline (screen-edge tick for any lethal body within
12 u, no upgrade needed) and turn Radar Module: Threats into its range/detail upgrade (30 u, enemy
type). One HUD ticket (T-025 follow-up, Inkling).

### 3. The terrain kills more than the enemies do
Why: D-025 makes 85% of path length 1–2 wide and stepped, 43–66% of walkway tiles 1 wide by mid game,
with 70–90% of gifts needing at least one jump. Charges are spent only by falls. If most charges are
lost with no enemy nearby, the game is a precision platformer with enemies as decoration — and the
silly-enemies-serious-world identity is lost.
Earliest signal: share of charges spent with no enemy within 10 u and no knock-back in the previous
2 s. Above 50%: the paths are the antagonist.
Mitigation, cheapest first: (a) controller forgiveness that does not touch the terrain proof — ledge
magnetism of 0.15 u on landing and when running along a 1-wide tile, in `data/player.json`;
(b) the `w1_pct` tuning knob (20% → 60% today) lowered — a generator version bump, so only after the
signal confirms.

### 4. Levels are over before the pressure starts
Why: measured greedy route time at run speed is 22 s at level 1, 43 s at level 10, 77 s at level 30
(DESIGN.md §2 assumed 90–240 s). Enemies spawn 6 s in; overtime ticks every 20 s; a full gold sweep
at level 1 finishes around the first tier. "Leave safe and poor, or linger for gold" needs lingering
to cost something.
Earliest signal: median black-phase time and median overtime tier at beacon entry, per level bucket,
from bot runs. If the median tier at entry is 0–1 through level 10, the core decision does not exist.
Mitigation: data first — overtime period 20 s → 10 s in `data/economy.json`, measure again. Longer
paths (platform count, walkway length) only if that fails, because it is a generator version bump.

### 5. Running feels like climbing stairs
Why: the shape contract makes flat runs the exception (flat-share 2–3%): a tread of 1–2 cells, then a
1–2 HU step, repeated for the whole level. With auto step-up the camera bobs on every tread; with
2 HU steps the player jumps every second or two just to move forward.
Earliest signal: jumps per minute and step-ups per minute in a bot run of level 1, and the owner's
first minute holding the controls. More than ~40 required jumps per minute is a rhythm game nobody
asked for.
Mitigation: view-only camera smoothing over step-ups (spring on camera Y, 0.12 s) in T-012/T-011
follow-up; if the jump rate itself is the problem, raise the 1-HU share of steps inside D-025's
limits (the contract fixes flat-share and elevation spread, not the mix of 1 and 2 HU steps).

### 6. Every level looks like the last one
Why: the validator proves levels differ structurally (similarity p99 0.39). A player does not see
structure; they see a hub and thin blue paths in fog. One vocabulary, one palette per six levels, no
landmarks. The earlier build's complaint was that agent-made content felt generic.
Earliest signal: the owner's blind test — eight screenshots from the hub of eight seeds at one level:
can they be told apart at a glance? Plus: distinct platform archetypes visible from the hub.
Mitigation: one LANDMARK per level, view-layer only (no hash change): the deepest dead-end platform
gets a tall beacon-like spire prop and its own light colour, visible through fog from the hub, so
each level has a "there" to go to. One ticket on T-011's mesher (GLM).

### 7. The lobby is a walk between every level
Why: the intermission is a physical hall 28 × 20 u [CANON] with up to three bays, hold-F to confirm,
and a gate at the far end — after EVERY level, including levels whose schedule offers one mandatory
curse and nothing else. The earlier build shipped 40 s of dead time and nobody questioned it because
it passed its checks.
Earliest signal: median seconds from beacon entry to controllable in the next level, by offer type.
More than ~12 s on a curse-only intermission is the old mistake again.
Mitigation (no canon change): the player arrives 6 u from the lit bay rather than at the far wall;
the gate stands beside the bays; lobby run speed × 1.3. All in the T-023 layout script.

### 8. The mine bypass is 0.1 u wide while the chain says hurry
Why: D-026 guarantees a walkable bypass, and on a 2-wide walkway that bypass passes 1.0 u from a
0.9 u trigger. The gold phase pays for speed (4.0 s chain window) on those same walkways. A player
sprinting a chain past a mine dies to a tenth of a unit of drift and will call it a hitbox bug.
Earliest signal: mine deaths per 100 mine passes on 2-wide walkways, split by chain value. If deaths
climb with the chain, the margin is the cause.
Mitigation: the stricter rule already measured in D-026 (bypass centre ≥ 1.4 u away; removes a
further 19–31% of mines). NEEDS OWNER — the 0.1 u margin was ruled as stated. Cheaper and no ruling
needed: draw the trigger radius as a faint pink ground ring inside the 12 u tell distance.

### 9. The answers depend on telegraphs nobody has seen or heard
Why: every answer window in research/fable-enemies.md starts from a telegraph. The run ships
placeholder synthesized audio (T-055) and PNG sprites whose background removal is automatic; several
cues are audio-first in ENEMIES.md (bark, chime, beep, trumpet). If a cue is unreadable, the enemy is
unanswerable in practice however generous the arithmetic.
Earliest signal: T-075's answer bots react to sim telegraph EVENTS, so they cannot see this. The
cheap human signal: after three encounters with each enemy, can the owner say what the warning was?
Mitigation: every telegraph gets a VISUAL first (ground decal or outline in danger red, already the
palette rule), audio second; add to each enemy ticket's Done-when "the telegraph is visible with
audio muted".

### 10. Content that reads as a list, and curses that decide the run at the altar
Why: 46 curses and 36 upgrades were designed on paper, a third of them reworked by workers during
the void-charge change. Under one-hit rules several curses are run-enders on pick (Hungry Void at
level 1, Crumbling, Wet Floor — preflight items 12, 14, 15), and a mandatory pick with a 100 g tithe
means the player sometimes chooses how to lose. Meanwhile the shop's T4/T5 tiers start at levels 18
and 26, which most runs may never reach.
Earliest signal: (a) share of runs that end within two levels of a Brutal pick; (b) pick rate per
curse and purchase rate per upgrade over 100 runs — anything under 3% or over 60% is dead or
mandatory; (c) highest level reached, median.
Mitigation: resolve preflight items 10–16 before the first human playtest (data only); after the
first 100 logged runs, cut every curse and upgrade under 3% rather than adding more.

---

## What I would look at first, in order

1. Risk 4's numbers from the first bot batch (they need nothing but T-026 and the log).
2. Risk 3's charge-cause histogram from the same batch.
3. Risk 1 and risk 7 with a stopwatch on the first playable build — two measurements, five minutes.
4. Then hand the controller to the owner for risks 2, 5, 6, 9, which no bot can judge.
