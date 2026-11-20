# B5A - quick_recovery's Athletic branch is closed through the stat pipeline

**Verdict: DONE**

## What changed

- `game/app/world.gd` - the stat pipeline takes a per-upgrade contribution. `_run_modifiers(plan,
  kit)` now also merges whatever an owned script upgrade's module declares through
  `static func stat_mods(kit) -> Array` (one stack's modifier dicts, in the same shape a JSON
  `modifiers` row has), repeated per owned stack by `mods_for_stacks` exactly like the JSON half.
  New helper `_upgrade_stat_mods(id, kit)` loads the module and returns its declaration; a module
  that declares none, or an upgrade with no module, contributes nothing. `app/` still names no
  content id - the module names itself.
- `game/content/upgrades/quick_recovery.gd` - `stat_mods(kit)` returns
  `[{"stat": "run_speed", "op": "add", "value": 0.05}]` for the athletic class and `[]` for every
  other class; `knobs()` keeps the -20%/stack cooldown knob for dasher and glider. Header rewritten
  to describe both halves and to record that D-C2-5 is closed.
- `game/tests/test_upgrade_stat_contrib.gd` (new) - the shipped-path proof.
- `DECISIONS.md` - D-B5A-1.
- `README.md` - the v0.1.2 changelog paragraph no longer says the Athletic purchase does nothing.
- `game/tests/test_upgrade_consumers.gd` - the "reported world.gd lines" comment for
  quick_recovery now describes the shape that landed.

`add` rather than `mul` is deliberate: the rule sentence says +5% per stack, so two stacks are
+10%, not 1.05^2 = 10.25%. `run_speed`'s base is 1.0, so `add` 0.05 per stack lands on 1.05 and
1.10 exactly.

## Verified

### The new test, green (contribution present)

```
$ "C:/Users/Nathan/Documents/REMAKE VWR/VOIDWARP-REMAKE/tools/godot/godot.exe" --headless --path game --script res://out/one.gd
STAT CONTRIBUTION legs complete, failures=0
ONE 0 failure(s)
```

`res://out/one.gd` is a throwaway single-test runner in the gitignored `game/out/`; the same test
inside the suite prints `STAT CONTRIBUTION legs complete, failures=0` and the suite reports
`TESTS 122 passed 0 failed`.

The test builds three real worlds with `world.build()` (athletic, 0 / 1 / 2 stacks of
quick_recovery), drives each through 30 `world.step()` ticks, and then asserts at three layers:
the pipeline's own `_stats_black["run_speed"]` (1.05 / 1.10), the controller's live
`run_speed_mul` (1.05 / 1.10), and the controller's actual `run_speed(w.w)` against the 0-stack
world (x1.05 / x1.10). The steps matter: `world.step()` runs `_upgrade_speed_pass`, which rewrites
`run_speed_mul` from the phase stats whenever a boost is live, so a build-time read would not prove
the contribution survives the tick. A second leg asserts the contribution is class-scoped: dasher
and glider with 2 stacks move run speed by nothing and keep their cooldown knob at 0.6.

### Negative control 1 - the module's contribution removed (`stat_mods` returns `[]`)

```
STAT CONTRIBUTION legs complete, failures=6
FAIL athletic_speed: 1 stack left the pipeline's run_speed at 1.0000, want 1.05
FAIL athletic_speed: 2 stacks left the pipeline's run_speed at 1.0000, want 1.10
FAIL athletic_speed: 1 stack left the controller's run_speed_mul at 1.0000, want 1.05
FAIL athletic_speed: 2 stacks left the controller's run_speed_mul at 1.0000, want 1.10
FAIL athletic_speed: 1 stack moved the controller's run speed 10.3500 -> 10.3500 (x1.0000), want x1.05
FAIL athletic_speed: 2 stacks moved the controller's run speed 10.3500 -> 10.3500 (x1.0000), want x1.10
ONE 6 failure(s)
```

### Negative control 2 - the world's merge removed (the `_upgrade_stat_mods` append deleted)

```
STAT CONTRIBUTION legs complete, failures=6
FAIL athletic_speed: 1 stack left the pipeline's run_speed at 1.0000, want 1.05
FAIL athletic_speed: 2 stacks left the pipeline's run_speed at 1.0000, want 1.10
FAIL athletic_speed: 1 stack left the controller's run_speed_mul at 1.0000, want 1.05
FAIL athletic_speed: 2 stacks left the controller's run_speed_mul at 1.0000, want 1.10
FAIL athletic_speed: 1 stack moved the controller's run speed 10.3500 -> 10.3500 (x1.0000), want x1.05
FAIL athletic_speed: 2 stacks moved the controller's run speed 10.3500 -> 10.3500 (x1.0000), want x1.10
ONE 6 failure(s)
```

Both halves are load-bearing: neither the module alone nor the pipeline alone makes the test pass.
Both files were restored and the test re-run green before the gate.

### The existing upgrade tests

`TESTS 122 passed 0 failed` in the gate's step 3, which is every `res://tests/test_*.gd` including
`test_upgrade_hooks.gd`, `test_upgrade_consumers.gd`, `test_upgrades_world.gd`,
`test_upgrades_script.gd`, `test_stats_consumers.gd` and `test_boundaries.gd`.

### The gate

```
$ powershell -NoProfile -ExecutionPolicy Bypass -File tools/gate.ps1
---- gate summary ----
OK   python oracle checks (TESTS OK, SELFTEST 18/18, GALLERY 16/16 OK)
OK   terrain parity (PARITY 56/56 OK)
OK   run_all (TESTS 122 passed 0 failed)
OK   boundary scan (ran in run_all: game/tests/test_boundaries.gd)
OK   content schema (ran in run_all: game/tests/test_content.gd)
OK   drop-in fixture (ran in run_all: game/tests/test_dropin.gd)
OK   replay determinism (ran in run_all: game/tests/test_replay.gd)
OK   sprite validator
OK   fog readability
GATE OK (9 ran, 0 skipped, 371 s)
```

Exit code 0.

## Deviations

- **README.** There is no known-gaps line about quick_recovery - the only mention is the
  v0.1.2-alpha.3 changelog paragraph, which said the Athletic purchase "does nothing for that one
  class". Deleting it would have removed the record of a real release; leaving it would have left a
  false present-tense claim on the front page. I rewrote that sentence to say the gap is closed and
  by what, and dropped "with one recorded exception" from the bullet's heading.
- **`test_upgrade_consumers.gd`.** Its "reported world.gd lines" block described quick_recovery's
  Athletic half as `apply_speed_upgrade(0.05 * n)`. That is not the shape that landed, so the two
  comment lines now describe the cooldown knob plus the stat contribution. Comment only.
- **`test_upgrades_world.gd` left alone.** Its quick_recovery leg still prints an INERT FINDING
  claiming the cooldown consumer is never called by the world, which is stale (the world sets
  `ctl.cooldown_mul` from the module's knobs). That file's header declares its INERT list a
  historical snapshot and says not to chase the wiring, so I did not touch it.
- No threshold was moved and no check was weakened. `terrain_ref/voidgen.py` and
  `game/terrain/voidgen.gd` were not touched.

## New DECISIONS entries

- **D-B5A-1** - a script upgrade may declare a stat contribution, and that closes the Athletic
  branch. Records the shape (`static stat_mods(kit)`, one stack's worth, merged by the world), why
  `add` rather than `mul`, and the two negative controls.
