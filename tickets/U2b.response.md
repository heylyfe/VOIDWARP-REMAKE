# U2b RESPONSE — tester-spawned Claude must get clawds (cycle 8, Terra finding 1)

**Verdict: DONE.** Branch `t3/tester-claude-swarm`. Gate exit code **0**.

## What was built

`world.tester_spawn_enemy(id: String, at: Vector3) -> bool` in `game/app/world.gd` (D-T2-13):

- **The spawn half** is the panel's own path verbatim: `_behavior_for(id)` + `_cfg_for(entry, id,
  _level_number, votes=1, beh)` + `enemy_runtime.spawn_at()` - the same row shape the vote plan
  produces. It returns false and changes nothing when no level is live (no ctl / lstate / rt /
  registry) or the id is not in the registry.
- **The swarm half** fires only when the id's module declares `clawd_cfg()` (the `extra_mines()`
  probe idiom; app/world.gd names no content id) and `lstate.clawds == null`. The attach is NOT
  immediate: it is appended to `_tester_jobs`, a WORLD-owned queue drained at the top of
  `step()` in the same slot as the panel's `tester_tick_hook`, so the attach happens inside a
  real tick and that SAME tick's `ClawdsScript.tick` already sees the swarm. The job runs the
  three steps level construction runs, nothing bespoke: `ClawdsScript.attach(lv, cfg)` (build()'s
  own placement step, D-T4-2), `lstate.clawds = ClawdsScript.create(lv)` (the exact create
  `LevelState.build` performs), `clawd_view.setup(lstate.clawds)` (build()'s view-setup step).
- **Idempotent at both ends**: the entry queues nothing while a swarm exists, and the job
  re-checks the same guard at run time - a second spawn of the owner adds its enemy row but
  never duplicates/does not replace the swarm. `teardown()` clears the queue so a torn-down
  level's job never lands on the next build's state.
- **No sim file touched, no threshold moved, no determinism change**: the queue is appended to
  only by this tester-only entry point; a public tick pays one emptiness check. The swarm joins
  the state hash only after it exists, exactly as a voted swarm does.

## The proof (all headless, real world + real sim, no stub)

`game/tests/test_tester_claude_swarm.gd`, seed 7419, an EMPTY-votes level that plans no enemy
of its own - the exact repro the ticket states:

- **A (no live level)**: an unbuilt world refuses the spawn (false), leaves no state, no job.
- **B (spawn + queued attach)**: `tester_spawn_enemy("claude", <far tile top>)` → true, one
  claude row in the runtime (cfg id/level_number/votes match the panel's shape). BEFORE the
  tick the swarm is still null (the attach is queued); after ONE `step` the swarm EXISTS with
  exactly the body count the module's own `clawd_cfg` asks for on this level's tile count
  (`ClawdsScript.count_for_tiles`, every body untaken), and the spots are spot-for-spot
  identical to a fresh `ClawdsScript.attach()` on a duplicate Level dict - the same placement
  path build() uses. The level-wide clawd view drew the bodies.
- **C (REALLY ticks - not the null guard's skip)**: the anger timer climbed 1 on the attach
  tick and EXACTLY 1 per calm tick to 6; standing the player on an untaken spot for one tick
  produced the `clawd_collected` event in the world's own `last_events` (clawd id and remaining
  correct), took the spot, dropped remaining, and calmed anger_ticks to 0; back at the
  proven-clear point the timer resumed to 2.
- **D (idempotence)**: a second `tester_spawn_enemy("claude", ...)` returned true and added the
  second row, but queued NO job; after a step the swarm OBJECT is still the same instance,
  same spots, same count, same taken.
- **E (non-swarm ids)**: two registry ids with no `clawd_cfg()` (`address_me`, `coil`, picked
  live from the registry) spawn normally through the same entry and leave the swarm untouched.

## Verified (tails pasted)

run_all (discovered suite, includes the new file):

```
PASS res://tests/test_tester_build.gd
PASS res://tests/test_tester_claude_swarm.gd
...
PASS res://tests/test_upgrade_hooks.gd
PASS res://tests/test_upgrade_stat_contrib.gd
PASS res://tests/test_upgrade_tiers.gd
PASS res://tests/test_upgrades_decl.gd
PASS res://tests/test_upgrades_script.gd
PASS res://tests/test_upgrades_world.gd
PASS res://tests/test_vfx.gd
PASS res://tests/test_world_stat_wiring.gd
TESTS 143 passed 0 failed
```

(143 = the previous 142 plus this suite's new file; run before this branch had 142 files.)

Gate (`powershell -File tools\gate.ps1`, exit code 0, read by me):

```
---- gate summary ----
OK   python oracle checks (TESTS OK, SELFTEST 18/18, GALLERY 16/16 OK)
OK   terrain parity (PARITY 56/56 OK)
OK   run_all (TESTS 143 passed 0 failed)
OK   boundary scan (ran in run_all: game/tests/test_boundaries.gd)
OK   content schema (ran in run_all: game/tests/test_content.gd)
OK   drop-in fixture (ran in run_all: game/tests/test_dropin.gd)
OK   replay determinism (ran in run_all: game/tests/test_replay.gd)
OK   sprite validator
OK   fog readability
GATE OK (9 ran, 0 skipped, 633 s)
```

Error-string scan over this run's output and over the whole gate log: `SCRIPT ERROR` 0,
`Parse Error` 0, `null instance` 0.

## Files touched

- `game/app/world.gd` - `tester_spawn_enemy()`, `_tester_attach_swarm()` (the queued job),
  the `_tester_jobs` member + its drain at the top of `step()`, the queue clear in `teardown()`.
- `game/tests/test_tester_claude_swarm.gd` - NEW suite (legs A-E above).
- `DECISIONS.md` - D-T2-13 appended at the end of the T2 section.
- `RUNLOG.md` - one line per event (dispatch, code commit, results, verdict).
- `tickets/U2b.response.md` - this file.

No view helper was needed: the existing level-wide `clawd_view` re-setup path suffices.

## Deviations

- None from the deliverable. Scope respected: `game/view/tester/debug_panel.gd`,
  `game/tests/test_tester_build.gd`, and `game/sim/clawds.gd` (rules/thresholds) are untouched.
- Outside observation, recorded in D-T2-13, NOT fixed here (U2a's file): this engine build
  (4.7.2) passes a `Callable`'s call-time arguments BEFORE its `.bind()` arguments, so the
  panel's `_run_give_gifts(n: int, ev: Array)` + `_queue_job(...bind(n))` +
  `run.call(out["ev"])` looks like it receives (ev, n) - the give-gifts job may need its
  parameter order swapped by the panel track. U2b's own job already uses the engine's order.

## New DECISIONS entries

- **D-T2-13** - the entry point's contract (false outside a live level; panel-shaped row; the
  swarm only from a `clawd_cfg()` id when no swarm exists), why the attach is queued from the
  app layer (same placement/create/view-setup path as build(), inside a real tick), and the
  idempotence rule (guard at queue time AND at job-run time; no second swarm ever).

No D-T2-14 was needed: one decision covers the contract, the queue and the idempotence rule.
