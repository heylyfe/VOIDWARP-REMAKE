# Crash sweep, levels 1-4 (app layer)

Worker: sweep L1-4, cycle 8, fleet of four (L1-4 / L5-8 / L9-12 / reviewer).
Base commit: `4c15bf9` ("U4: fail-soft asset loads, the blocky player fallback, and the crash
breadcrumb"), the U4 track's committed state. Branch `t3/sweep-levels-1-4`.
Run at 2026-11-23 18:44Z - 18:55Z. Engine: Godot 4.7.2.stable, `--headless`.

Driver: `game/tools/sweep_run.gd` (read, not modified). It builds the REAL app world
(`app/world.gd`) once per seed/level, steps locomotion for 700 ticks, then forces the late
features so they are actually entered: the collapse schedule from IDLE, the boss arena entry,
the Bankai cinematic, Peter's kill and the beacon/300-gold completion. `--vote-mode all`
votes every registry enemy at 1 (clawd swarm, Gin's sword, toucher floor, mines present);
`--vote-mode random` leaves the ledger empty so `world.build()` replays the lobbies.

## Exact commands

Run from the worktree root. The `--import` step came first and only because a fresh worktree
has no `game/.godot`, so PNG and `.glb` files are not imported and every asset load would
have fallen back (R18b). It printed `IMPORT_EXIT=0` and touched only the gitignored
`game/.godot`.

```sh
mkdir -p game/out

# once, so assets are real rather than fail-soft fallbacks
"C:/Users/Nathan/Documents/REMAKE VWR/VOIDWARP-REMAKE/tools/godot/godot.exe" \
  --headless --path game --import

"C:/Users/Nathan/Documents/REMAKE VWR/VOIDWARP-REMAKE/tools/godot/godot.exe" \
  --headless --path game --script res://tools/sweep_run.gd -- \
  --seed-base 1 --seeds 40 --levels 1-4 --ticks 700 --vote-mode all \
  > game/out/sweep_L1-4.log 2>&1 ; echo "EXIT=$?"

"C:/Users/Nathan/Documents/REMAKE VWR/VOIDWARP-REMAKE/tools/godot/godot.exe" \
  --headless --path game --script res://tools/sweep_run.gd -- \
  --seed-base 1 --seeds 40 --levels 1-4 --ticks 700 --vote-mode random \
  > game/out/sweep_L1-4_random.log 2>&1 ; echo "EXIT=$?"
```

Coverage: 40 seeds (1-40) x 4 levels x 2 vote modes = 320 level entries, ~2 400 ticks each
(700 locomotion + 120 collapse + Bankai out to `end_tick` + the kill and beacon passes).

## Exit codes

| Run | Log | EXIT |
| --- | --- | --- |
| `--vote-mode all` | `game/out/sweep_L1-4.log` | 0 |
| `--vote-mode random` | `game/out/sweep_L1-4_random.log` | 0 |

## SWEEP DONE lines (tails)

```
sweep_L1-4.log:164        SWEEP DONE entries=160 built=160 build_failures=0
sweep_L1-4_random.log:164 SWEEP DONE entries=160 built=160 build_failures=0
```

`built == entries` and `build_failures == 0` in both modes: no cut-short run, no level that
failed to construct, and no non-zero exit. Both logs contain exactly 160 `ENTRY` lines and
no other line between `SWEEP start` and `SWEEP DONE`.

## Per-pattern grep counts

Fixed-string, case-sensitive, whole file, no filtering or trimming first:

```sh
for p in "SCRIPT ERROR" "Parse Error" "Invalid access to an object" "null instance" \
         'Parameter "' "Attempt to call" 'Condition "' "Index p_out of bounds" \
         "Cannot instantiate" "Leaked instance" ; do
  printf '%-32s all=%s random=%s\n' "$p" \
    "$(grep -c -F "$p" game/out/sweep_L1-4.log)" \
    "$(grep -c -F "$p" game/out/sweep_L1-4_random.log)"
done
```

| Pattern | all | random |
| --- | --- | --- |
| `SCRIPT ERROR` | 0 | 0 |
| `Parse Error` | 0 | 0 |
| `Invalid access to an object` | 0 | 0 |
| `null instance` | 0 | 0 |
| `Parameter "` | 0 | 0 |
| `Attempt to call` | 0 | 0 |
| `Condition "` | 0 | 0 |
| `Index p_out of bounds` | 0 | 0 |
| `Cannot instantiate` | 0 | 0 |
| `Leaked instance` | 0 | 0 |
| *(superset)* `ERROR` | 0 | 3 |
| *(superset)* `WARNING` | 0 | 2 |

The two superset rows are the whole reason they are listed: `ERROR`/`WARNING` are not in the
required pattern set, but they are the only non-crash noise either log carries, and the three
`ERROR` lines in the random log are engine-shutdown diagnostics that appear *after* the final
`SWEEP DONE` (line 164) at lines 165-170. They are documented under "Exit-time diagnostics"
below, not counted as findings.

## Per-level feature coverage

How many `ENTRY` rows on each level show the feature actually reached (`true`), out of 40:

`--vote-mode all` (every registry enemy voted, so the swarm and Gin are on every level):

| level | rows | built | collapse | boss | bankai | beacon | clawds | gin | gin_sword | died |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 28 |
| 2 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 39 | 39 | 33 |
| 3 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 25 |
| 4 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 26 |

`--vote-mode random` (empty ledger: `world.build()` replays the lobbies, which carry no
swarm-bearing vote, so `clawds`/`gin`/`gin_sword` are 0 by construction, not by failure):

| level | rows | built | collapse | boss | bankai | beacon | clawds | gin | died |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 40 | 40 | 40 | 40 | 40 | 40 | 0 | 0 | 0 |
| 2 | 40 | 40 | 40 | 40 | 40 | 40 | 0 | 0 | 0 |
| 3 | 40 | 40 | 40 | 40 | 40 | 40 | 0 | 0 | 1 |
| 4 | 40 | 40 | 40 | 40 | 40 | 40 | 0 | 0 | 1 |

The boss arena, the Bankai cinematic, the collapse and the beacon/300-gold completion were
entered on all 160 entries of both modes. One coverage gap in the all-mode run, reported
rather than rounded up:

```
ENTRY seed=34 level=2 built=true ticks=2289 died=true collapse=true boss=true bankai=true beacon=true clawds=true gin=false gin_sword=false
```

Gin's sword needs the row's 108-tick voice phase on top of the 360-tick spawn delay, and this
entry died inside the locomotion pass before that window closed, so `gin`/`gin_sword` read
`false`. The sword was reached on the other 39 level-2 rows and on 40/40 of levels 1, 3 and 4.
Tick totals across the all-mode run ran 2 250-2 440 per entry; deaths are the ordinary
enemy kills the driver records (it revives before the arena pass so the boss path is not lost),
not crashes.

## Findings

Against the finding definition (non-zero exit; `built < entries` or `build_failures > 0`; any
line matching the pattern list): **none**. No seed/level/pattern/line tuple to report. Every
run completed all 160 entries, built all 160 levels, and exited 0.

### Exit-time diagnostics (observation, not a finding)

Not a crash, and outside the finding definition on every count - it follows the last
`SWEEP DONE`, so no seed or level can be named for it, and the process still exits 0. Recorded
because the owner's report is "the game sometimes crashes" and an integrator should not have
to rediscover the one class of `ERROR` text in the evidence.

`game/out/sweep_L1-4_random.log:165-170`:

```
ERROR: 2 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.
ERROR: 160 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit.
ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.
WARNING: 80 RIDs of type "CanvasItem" were leaked.
WARNING: 172 ObjectDB instances were leaked at exit (run with `--verbose` for details).
```

Reproducibility, measured rather than assumed (2 seeds x 4 levels, twice per mode, logs kept as
`game/out/probe_leak_*.log`):

| run | mode | lines | ERROR/WARNING lines at exit |
| --- | --- | --- | --- |
| 1 | all | 12 | 0 |
| 2 | all | 16 | 2 (`18 ObjectDB instances leaked`, `4 resources still in use`) |
| 1 | random | 21 | 6 (RID + ObjectDB + 3 `resources still in use`) |
| 2 | random | 21 | 6 (identical) |

So the counts are stable within a mode for the same workload but vary between runs and modes:
the 40-seed all-mode log shows zero, while the small all-mode rerun already shows two. That
shape - varying counts, only ever after the final `SWEEP DONE` - is the orbit of the LOW
teardown finding Terra already queued (`world.gd:1381`, the null-material renderer errors),
not a new mid-run crash. Nothing here touches a level, a seed or a tick inside a run.

## Verdict

**levels 1-4 CLEAN**

No run-time crash, no `SCRIPT ERROR`, no failed build, no non-zero exit, and no finding on any
of the 320 level entries across both vote modes. The only `ERROR` text in either log is the
engine's shutdown leak report after `SWEEP DONE`, documented above as an observation.


