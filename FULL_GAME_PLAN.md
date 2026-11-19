# FULL_GAME_PLAN.md — VOIDWRAP RUN, the road to a shippable alpha

Written 2026-11-19 against `main` at `aecc5c2`. This is the plan for the full-game mission: take the
build from "the loop runs" to "a stranger can play it and nothing is obviously missing", then commit
and publish the next alpha.

Three sources feed it, and each is named where it is used:

- **The gap analysis** (`out/gap_analysis.md`, gitignored): a read-only worker compared every promise
  in DESIGN.md, TERRAIN_SPEC.md and ENEMIES.md against the code and located 24 defects. Every finding
  below was found in the code, not inferred.
- **PARKED.md**: 30 rows of known leftovers, each with a disposition here.
- **Measurement**: the A3 bot probe, run today on 100 seeds.

---

## 1. Definition of done for the alpha

Each line is a check someone can run. The alpha ships when every line is PASS or explicitly parked
with a reason in §4.

| # | check | how it is measured | state today |
|---|---|---|---|
| D1 | Full loop, no dead ends: menu → level → beacon → lobby/altars → descent → next level → death/win → results → menu | a scripted playthrough test that walks every transition and asserts none returns to a dead screen | **PARTIAL** — the loop exists; Retry returns to the menu instead of retrying (gap 22) |
| D2 | Every biome in DESIGN.md §10 exists and plays | one test per biome asserting it generates, meshes and passes fog readability | **PASS** — `FOGCHECK OK (550 checks over 5 biomes)` |
| D3 | Every enemy in ENEMIES.md exists, plays, and has a test | one test per enemy asserting its behaviour against its ENEMIES.md row | **PARTIAL** — 12 enemy dirs; the telegraph/VFX/audio layer that makes them readable is dead code (gap 1) |
| D4 | Every curse in the offer pool works and has a test | a test per curse proving its modifier reaches a live stat | **FAIL** — all 46 are inert (gap 3) |
| D5 | Every upgrade in the offer pool works and has a test | a test per upgrade proving its modifier reaches a live stat | **FAIL** — all 36 are inert (gap 2) |
| D6 | Bot probe meets the A3 bar | 100 seeds from base 60717 in 20-seed chunks; level 1 completed in ≥95, median ≤120 s | **PASS** — 98/100, median 36.9 s (§3) |
| D6b | Bot probe meets the DESIGN §9 difficulty bands | same 100 seeds at full depth; level 6 ≥80%, level 12 40–60%, level 18 15–30% | **FAIL** — 3%, 0%, 0% (§6). The largest gameplay problem in the build. |
| D7 | Save/load works | a test that writes state, restarts, and reads it back | **FAIL** — no persistent store exists (gap 20) |
| D8 | Settings work | a test per field proving the value reaches its consumer | **FAIL** — no UI, 3 of 4 fields inert (gap 16) |
| D9 | Audio works | every lethal threat's cue precedes the attack by the binding cue time | **FAIL** — the audio layer is dead code (gap 1) |
| D10 | Controls work | a test per binding, including Ctrl mouse-look and pause | **PARTIAL** — no pause; ESC destroys the run (gap 4) |
| D11 | Tips work | the tip system shows, rotates and dismisses | **PARTIAL** — diegetic danger text absent in-game (gap 13) |
| D12 | Suite 0 failed | `run_all.gd` | **PASS** — `TESTS 71 passed 0 failed` |
| D13 | Gate green | `tools/gate.ps1` | **PASS** — `GATE OK (9 ran, 0 skipped, 321 s)` |
| D14 | CI builds pass | the tag push builds all three platforms | **PASS at v0.1.1-alpha.3** — re-verify on the new tag |

---

## 2. The 24 gaps, and which wave takes each

Classes: **A** promised-not-built · **B** built-but-broken · **C** built-but-unreachable ·
**D** placeholder · **E** player-visible defect · **F** polish.
Size: **S** under an hour · **M** a few hours · **L** a day or more.

| # | class | gap | size | wave |
|---|---|---|---|---|
| 1 | C | The entire enemy telegraph / VFX / audio layer is dead code — every attack arrives with no ring, no line, no patch, no sound | L | 2 |
| 2 | B | All 36 upgrades are inert — the shop takes gold and changes nothing | L | **1 (D1) — PARTLY CLOSED**, see gap 27 |
| 3 | B | All 46 curses are inert — the mandatory curse bay is a tax with no effect | L | **1 (D1) — PARTLY CLOSED**, see gaps 26 and 27 |
| 4 | E | There is no pause; ESC destroys the run with no confirmation and no resume | S | 2 |
| 5 | C | The player never chooses a class — DESIGN §4 promises a class altar, the app rolls 1-in-3 | M | 2 |
| 6 | E | Projectiles are invisible — Isagi's balls, Claude's wind shots, the nuke missile | M | 2 |
| 7 | C | The straggler beam is never drawn — the hardest 20% of every level has no marker | S | 2 |
| 8 | E | A void-fall respawn can land inside a lethal hazard | S | **1 (I3)** |
| 9 | B | gift Larper votes add no mines — `extra_mines` hardcoded 0 | S | 2 |
| 10 | E | gift Larper and nuke spawn inert bodies — a tripmine sprite that does nothing | S | 2 |
| 11 | C | The ability cooldown HUD is never fed — the dash bar always reads ready | S | 2 |
| 12 | C | The curse and upgrade icon rows are never fed — Tab collapses an empty row | S | 2 |
| 13 | C | Diegetic danger text is absent in-game — enemies appear with no announcement | S | 2 |
| 14 | C | thicc ben's screen blur is absent — the eject reads as a bug | S | 2 |
| 15 | C | Respawn invulnerability has no visual | S | 2 |
| 16 | D | The settings store has no UI and 3 of its 4 fields are inert | M | **1 (G2)** |
| 17 | E | The camera has no collision — the view clips inside the level | M | **1 (G1)** |
| 18 | A | Field Dressing is not implemented — DESIGN §8 promises a free fall | S | 2 |
| 19 | A | Telegraph footprints never expire, so "address me" can be blocked for a run | M | **1 (I2)** |
| 20 | A | "Best level and best purse recorded locally" is absent | S | **1 (I4)** |
| 21 | C | The run log is never written — `app/run_log.gd` is never instantiated | S | **1 (I4)** |
| 22 | F | "Retry" does not retry — it returns to the main menu | S | **1 (I1)** |
| 23 | F | The version tag on screen says v0.1.0-alpha.3; the README says v0.1.1-alpha.3 | S | **1 (I1)** |
| 24 | F | The README's "known gaps" are stale in both directions | S | **1 (I1)** |
| 25 | B | **The difficulty curve collapses after level 5** — the bot reaches level 6 in 3% of runs against a band of ≥80%, and never reaches level 12 or 18 | L | 2 (diagnose after gaps 1 and 19) |
| 26 | A | **11 enemy-linked curses have no implementation module** — drawable and pickable but inert; the branch holding them must never be merged | L | 2 (11 small tickets, one per curse) |
| 27 | B | **8 stats are computed and then dropped** — no consumer in `controller.gd` or `economy.gd`, so 5 upgrades and 5 curses still change nothing | M | 2 |

Counts: A 4 · B 5 · C 9 · D 1 · E 5 · F 3 · total 27.

### Gap 27 in detail — the residual after D1

D1 wired every stat that already had a consumer. Eight have none, so they are computed into
`_stats_black`/`_stats_gold` and then thrown away. Until they are wired, these still do nothing:

| stat | emitted by | consumer it needs |
|---|---|---|
| `barrier_shields` | upgrade `subspacial_barrier` | the beacon / barrier restore path |
| `defuse_chance` | upgrade `defuse_kit` | `sim/mines.gd` |
| `pickup_radius` | upgrade `long_reach` | `sim/gifts.gd` |
| `shop_price_mul` | upgrade `bargain`, curse `inflation` | the lobby shop |
| `telegraph_mul` | upgrade `early_warning`, curse `hasty` | `sim/enemy_runtime.gd` |
| `enemy_speed_mul` | curse `rush_hour` | `sim/enemy_runtime.gd` |
| `fill_light_range` | curse `lights_out` | the view's fill light |
| `fog_density` | curse `thick_fog` | the view's fog environment |

Each is a small, independent wiring job in a different file, which makes them good parallel tickets.
`void_fall_charge_cost` is wired in `controller.gd` but no content entry emits it — harmless, noted.

One behavioural note from D1b worth keeping: `apply_stats` calls `set_charge_cap`, which clamps
`charges` down, and it runs on both gold-phase edges. Nothing grants charges during the gold phase
today, so it is harmless — but it is a side effect of applying a stat rather than a deliberate rule,
and a future mechanic that grants charges mid-gold-phase would be silently clamped.

**The shape of it.** Nine of the 24 are class C — built, working, and unreachable. That is the
signature of a project that built its systems and never wired them to the screen. The three L-sized
items (1, 2, 3) are the same disease at scale: the enemy presentation layer, the upgrades and the
curses all exist as tested code that nothing calls. Fixing those three is most of the distance
between "the loop runs" and "the game is complete".

---

## 3. The A3 measurement, taken today

A3 is pinned by D-060: kiwi cat present, `--dodge` on, Last Light available, 2 charges held, the bot
completes level 1 in **≥95 of 100 seeds, median ≤120 s**.

The literal command D-060 names (`--seeds 0:100 --dodge --enemy kiwi_cat`) **cannot be run**:
`bot_run.gd` parses only `--dodge --log --log-dir --runs --seed-base --max-level --trace` and silently
ignores unknown flags (AUDIT D1, still true). The measurable form is the chunked one the owner
specified. Measured on `main` at `aecc5c2`, five chunks of 20 seeds, `--max-level 2`:

| seed base | level 1 completed | median sim time |
|---|---|---|
| 60717 | 19/20 | 34.6 s |
| 60737 | 20/20 | 39.7 s |
| 60757 | 20/20 | 37.4 s |
| 60777 | 20/20 | 34.9 s |
| 60797 | 19/20 | 36.9 s |
| **total** | **98/100** | **~36 s** |

**A3 PASSES: 98 ≥ 95, median 36.9 s ≤ 120 s.** For context, AUDIT.md records 82/100 before the
GEN_VERSION 4 terrain widening and 19/100 before FIX-A3. The 3-wide walkways closed the last 13 seeds.

Two honest caveats:

- **The kiwi-cat condition is unenforceable.** The probe uses seeded random votes, so this is a
  mixed-enemy sample, not the kiwi-only sample D-060 describes. Making A3 mean what it says needs
  `--seeds A:B` and `--enemy <id>` added to `bot_run.gd` — a small job, and the right fix rather than
  restating the criterion.
- **The gain is not all terrain.** Another worker's kiwi-cat change (half speed, no dash) was in the
  tree for the "after" measurements. The two cannot be separated from this data, and the guardian
  ruled no extra run is needed. The caveat stands in the handover.

The DESIGN §9 difficulty bands (level 6 ≥80%, level 12 40–60%, level 18 15–30%) are a separate bar and
are being measured now at full depth; results go in §6.

---

## 4. PARKED.md — all 30 rows, with a disposition

Every row gets a size and an owner. "Owner" is who acts: a wave, the owner, or nobody.

| row | subject | size | disposition |
|---|---|---|---|
| 1 | ENEMIES.md contradicts itself on which side enemy logic runs | S | **OWNER RULING.** The build follows the global notes (logic in `sim/`, rendering in `view/`). No code change until the owner picks a passage. |
| 2 | DESIGN §14 disclaimer vs ENEMIES.md DISCLAIMER wording | S | **OWNER RULING.** Both texts are pinned by `test_disclaimer.gd`. Do not touch. |
| 3 | Field Dressing "free fall" pip cannot be wired | S | **Wave 2** with gap 18. Resolves itself when the sim implements `on_void_fall`. |
| 4 | The walker bot does not complete a level (0 of 4 seeds) | — | **CLOSED.** The bot now completes 98 of 100. Superseded by §3. |
| 5 | DESIGN §5 "none" anchor kind | S | **Wave 2.** Small behaviour fix. |
| 6 | Nuke "break line of sight" vs the terrain contract | M | **OWNER RULING.** Design conflict, not a bug. |
| 7 | The nuke kills the nearest player, not every player in the blast | S | **Wave 2.** Single-player today, so low impact; fix for correctness. |
| 8 | The sim never expires telegraph footprints (nuke ground ring) | M | **Wave 1 (I2).** Same defect as gap 19. |
| 9 | The sim never expires telegraph footprints (found independently) | M | **Wave 1 (I2).** Duplicate of row 8. |
| 10 | `test_enemy_address_me.gd` body-containment assertion | S | **Wave 2.** Test-strength gap. |
| 11 | Biome fog-readability rule | S | **PASS** — `FOGCHECK OK (550 checks over 5 biomes)`. Close. |
| 12 | Every lethal threat's audio cue is learnable and precedes the attack | M | **Wave 2** with gap 1. Part of the dead audio layer. |
| 13 | Coil landing kill cue timing | S | **Wave 2** with gap 1. |
| 14 | Claude drums + wind attack cue timing | S | **Wave 2** with gap 1. |
| 15 | gin `crack_rumble` as the zone-kill pre-attack cue | S | **Wave 2** with gap 1. |
| 16 | T-051 "modules are done and on main" claim | S | **Wave 3 (docs).** Verify the claim, correct the record. |
| 17 | T-081 AUDIT.md appendix | S | **Wave 3 (docs).** |
| 18 | T-075 answer pairs ≥95% with the answer, ≤5% with no input | M | **Wave 3 (balance).** Needs the answer lab, not a code change. |
| 19 | T-ART-TOUCHER distinct frame per state | M | **PARKED for the alpha.** Art scope; the sprites are placeholders by design (TBD.md). |
| 20 | The loading screen is driven twice per frame | S | **Wave 2.** |
| 21 | `view/billboard.gd` stands every billboard below its node | S | **Wave 2.** Visible misalignment. |
| 22 | Loading screen duration row | S | **Wave 2** with row 20. |
| 23 | Lobby gate → next level controllable | S | **Wave 2.** |
| 24 | A3 measures 82/100 | — | **CLOSED.** Now 98/100 (§3). |
| 25 | **HIGH** — Last Light's 8 u body push does nothing to live enemies | M | **Wave 2.** A class ability that does nothing. |
| 26 | **HIGH** — `_ramp_top_over` treats ramp kinds 3 and 4 as ascending | M | **Wave 2.** Collision correctness. |
| 27 | **MEDIUM** — instant reposition teleports never call `sync_body()` | S | **Wave 2.** |
| 28 | **MEDIUM/LOW/INFO** cleanup, `enemy_runtime.gd` | S | **Wave 3.** |
| 29 | **The exe on disk cannot finish a level** | S | **Wave 3.** Rebuild from the new tag; the CI artifact supersedes it. |
| 30 | Spikes hanging on the hub, ~4% of levels | M | **PARKED by guardian ruling.** Do not change the mesher or any pinned seed. Fix idea recorded: a mesher rule for spikes under dead-end discs near the hub. |

**Summary:** 2 closed by measurement (4, 24), 1 already passing (11), 3 need an owner ruling (1, 2, 6),
1 parked for the alpha (19), 1 parked by ruling (30), and 22 go into waves 1–3.

---

## 5. Wave plan

Disjoint file ownership per worker. Gate after every merge. Both sides kept in conflicts. New files
preferred over shared-file edits, so two workers never fight over the same script.

### Wave 1 — the foundation (landed)

| ticket | model | owns | gap | outcome |
|---|---|---|---|---|
| D1 | DeepSeek V4 | `app/world.gd`, `sim/economy.gd`, `sim/controller.gd`, `sim/intermission.gd` | 2, 3 | **done, verified.** Modifiers reach the live run. Mutation-tested five ways; the follow-up found a real hole (stack repetition unproven) and closed it. 8 stats still unconsumed -> gap 27. |
| I1 | Inkling | `README.md`, the menu file(s) | 22, 23, 24 | **done, verified.** Retry restarts the same seed into LOADING->WORLD; version string matches; README corrected. Leg C of `test_app_death` moved to the new contract by the lead. |
| I2 | Inkling | `sim/enemy_runtime.gd` | 19 | **done, verified.** Telegraph footprints expire at the gate/read layer; `rt.telegraphs` deliberately not pruned. Found a consequence: the bot reads the raw list and now dodges ghosts. |
| I3 | Inkling | `sim/level_state.gd` | 8 | **done, verified.** Producer `hazard_footprints()` + test. The one-line wiring into `world.gd` was done by the lead and proven by negative control. |
| I4 | Inkling | `app/app.gd`, `app/run_log.gd`, `core/records.gd` | 20, 21 | **done, verified.** Records persist to `user://records.json`; run log instantiated. Found and fixed a test-isolation defect: three app tests were writing the player's real records file. |
| G1 | GLM 5.3 | `app/camera_rig.gd` | 17 | **done, verified.** Pure pull decision + pure-math query over the sim collision table; no-obstruction case bit-identical. |
| G2 | GLM 5.3 | settings store + new screen | 16 | **partial.** Store methods and a 300-line screen built; the test is outstanding. |
| G3 | GLM 5.3 | read-only | - | **done.** `out/design_features.md`, 139 rows. |

`app/world.gd` is the hub every wave wants. It has exactly one owner per wave; anyone else who needs
it exposes an API and reports the wiring.

**Two integration fixes the lead made rather than spending a delegate on them** (small review
findings, per the T3 rule): the `test_app_death` leg C contract update, and the `world.gd` hazard
publish line. The second was proven by negative control - with the line commented out the new test
fails with "world.step did not publish w[\"hazards\"] - the respawn search is blind".

### Wave 2 — the presentation layer (the big one)
Gap 1 is the largest single item and the one a player notices first: the enemy telegraph, VFX and
audio layer is dead code. It takes `world.gd`, so it owns that file for the wave. Alongside it, the
items that need `world.gd`'s neighbours but not `world.gd` itself:

- gap 1 + 6 + 7 + 13 + 14 + 15 + PARKED 12–15 — telegraphs, projectiles, straggler beam, danger text,
  screen blur, invulnerability visual, audio cues. **One owner for `game/view/` and `world.gd`.**
- gap 4 — pause and a real ESC menu.
- gap 5 — the class altar.
- gap 9, 10 — gift Larper mines and inert bodies.
- gap 11, 12 — HUD feeds (cooldown bar, curse/upgrade icon rows).
- gap 18 + PARKED 3 — Field Dressing.
- PARKED 20–23, 25–27 — loading screen, billboard offset, lobby gate, Last Light push, ramp collision,
  `sync_body` on teleport.

### Wave 3 — polish and the alpha

Balance pass, bug sweep, a fresh-eyes bug and security review of the whole diff, README and release
notes, PARKED 16–18 and 28–29, then commit, push and tag.

---

## 6. Difficulty bands (DESIGN §9) — MISSED BY A MILE

Measured on the same 100 seeds at full depth (`--max-level 18`). The bands are FROZEN by DESIGN §9:
"if a band is missed, tune enemy speeds/cooldowns/telegraphs in `content/enemies/*/enemy.json`, never
the bands and never the terrain thresholds."

| seed base | level 6 | level 12 | level 18 | median level reached | max |
|---|---|---|---|---|---|
| 60717 | 0/20 | 0/20 | 0/20 | 4 | 5 |
| 60737 | 1/20 | 0/20 | 0/20 | 4 | 6 |
| 60757 | 1/20 | 0/20 | 0/20 | 4 | 6 |
| 60777 | 0/20 | 0/20 | 0/20 | 5 | 5 |
| 60797 | 1/20 | 0/20 | 0/20 | 5 | 6 |
| **total** | **3/100 = 3%** | **0/100 = 0%** | **0/100 = 0%** | **4–5** | **6** |
| **band** | **≥80%** | **40–60%** | **15–30%** | — | — |

**This is the single largest gameplay problem in the build, and it is new information.** The bot
completes level 1 in 98 of 100 runs and then dies at level 4–5 almost every time. It never sees level
12 or 18 at all, so the entire late game — 6 to 9 enemy votes, 5 to 8 curses held, the higher mine
chances — is unreachable in practice and therefore untested by play.

The enemy-vote ramp is the obvious suspect: level 1 carries 1 vote, level 6 carries 3, level 12
carries 6. The bot dies in the 2-vote band, before the ramp even gets steep.

**Diagnose before tuning.** Three explanations fit the data and they need different fixes:

1. **The game is genuinely too hard at 2+ enemies.** Fix: tune enemy speeds, cooldowns and telegraphs
   in `content/enemies/*/enemy.json`. This is the path DESIGN §9 sanctions.
2. **The bot is not competent at multi-enemy levels.** Its dodge policy reacts to one most-imminent
   strike at a time (250 ms reaction, one footprint). With two enemies it may be dodging into the
   second. Fix: the bot, not the game — and tuning the game to suit a weak bot would be the wrong
   answer.
3. **A defect in multi-enemy levels.** The telegraph/VFX layer is dead code (gap 1), so the bot is
   dodging telegraphs it can only see through the sim's dicts. If a telegraph is malformed or never
   expires (gap 19), the bot's dodge could be actively wrong.

The order matters: **fix gap 1 and gap 19 first**, then re-measure. A bot dodging against a broken
telegraph layer is not a fair test of the enemy numbers, and tuning enemy data to compensate for a
dead presentation layer would bake the bug into the balance. Only after that re-measurement is it
honest to say whether the enemy numbers or the bot need work.

**One prerequisite found while merging gap 19.** The telegraph-expiry fix filters at the gate/read
layer and deliberately does not prune `rt.telegraphs`, because caller-aging loops and index-based
consumers depend on that list. But `bot_run.gd` reads the raw list (`:792`, `:879`), so the bot now
dodges telegraphs that have already expired — it reacts to ghosts. That would understate the game's
playability in exactly the measurement I am about to use to judge the difficulty curve. **Fix the bot
to use the same live-telegraph filter before re-measuring the bands.** Small job, and it must land
before the re-measurement or the numbers are not trustworthy.

Recorded as gap 25 below.

---

## 7. DESIGN feature enumeration

Produced by a read-only worker into `out/design_features.md` (gitignored): 139 evidence rows, every
one located in code or in a test.

**DONE 128 · PARTIAL 7 · MISSING 4.**

### The 7 PARTIAL rows

| DESIGN ref | feature | why partial |
|---|---|---|
| §2 | first gift within 8 s (H10) | validated only in the Python harness, not suite-gated |
| §2 | performance targets | manual probe, not suite-gated |
| §2 | black-phase / run-length targets | the band tool exists, the numbers are not asserted |
| §3.3 | generator-level bypass guarantee | validator implemented, the over-seed assert lives in the Python harness |
| §8 | declarative-upgrade end-to-end behaviour | the math is tested; the live wiring was the gap (D1) |
| §14 | asset provenance | tool-gated, not suite-gated |
| §14 | icon art for curses and upgrades | placeholders per the TBD rule (D-T025-4) |

### The 4 MISSING rows

1. **§7.1 — 11 enemy-linked curses are declared but have no implementation module.** `quarter_chimes`,
   `second_strike`, `understudies`, `wide_blast`, `spreading_rot`, `wet_floor`, `pup_pack`,
   `slipstream_trail`, `unannounced`, `token_limit`, `twin_fangs`. No `.gd` module, no `sim/enemy`
   handling. They are **drawable and pickable but inert** — a player can be offered a curse that does
   nothing. The modules live on the stale `t3/scripted-curses-groups-4-6` branch, which the guardian
   ruled must never be merged. So they must be reimplemented on `main` or retired from the pool.
2. **§9 — meta-progression "best level and best purse recorded locally".** No implementation. This is
   gap 20, in wave 1 (I4).
3. §10 future gimmicks — MISSING **by design**, not a gap.
4. §13 multiplayer transport — MISSING **by design**, DESIGN defers it.

### Two deviations worth recording

- **Zoomies** is `retired: true` and excluded from every offer pool, while DESIGN §7.1 still lists it
  as offerable. Its inert-burst behaviour is implemented and tested. This is a deliberate, documented
  deviation (guardian ruling), stronger than the DESIGN text.
- **`sim/controller.gd:263` `friction_mult` returns 0.4 on glitched tiles unconditionally**, whereas
  DESIGN §7 (D-075) reserves the ×0.4 slipperiness for Wet Floor. `test_classes.gd` pins the 0.4
  behaviour, so sim and test agree with each other but not with DESIGN's letter. Needs an owner
  ruling: change the sim, or amend DESIGN.

### What this changes about the plan

The 11 unimplemented curses are a **new gap class** the first gap analysis could not see, because it
looked for defects in what exists rather than for declared content with no module behind it. They are
not the same as gap 3: gap 3 is "the modifier math is never applied" (one wiring fix, D1). These 11
have no behaviour to apply at all.

**Disposition: implement them, one small ticket each.** Retiring 11 of 46 curses would gut the pool
and the mission's definition of done says every curse in the pool must work. Each module follows the
existing pattern, so each is a small, mechanical, parallelisable job — exactly the shape the owner's
model plan assigns to Inkling. Recorded as gap 26.

---

## 8. Model plan

Per the owner's override: Inkling is free and unlimited, so it takes every small and mechanical job,
split into many small tickets rather than a few large ones. GLM 5.3 Flash (max 3) takes medium
implementation. DeepSeek V4 (max 3) takes wave planning, merge and conflict handling, and balance
reasoning. Opus 5.5 is held for the hard or risky parts that a cheaper model has already failed once —
terrain generation, the sim/lobby core, anything that broke the gate twice.

A failed Inkling ticket is split smaller or goes up one tier. No check is ever weakened to make a
ticket pass.
