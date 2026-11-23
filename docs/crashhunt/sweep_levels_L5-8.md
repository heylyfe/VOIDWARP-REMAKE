# Crash sweep: levels 5-8 (cycle 8, U4, worker 5-8)

Started from the U4 track's committed state `4c15bf9` ("U4: fail-soft asset loads, the
blocky player fallback, and the crash breadcrumb"), branch `t3/sweep-levels-5-8`. Engine:
`C:/Users/Nathan/Documents/REMAKE VWR/VOIDWARP-REMAKE/tools/godot/godot.exe`,
Godot v4.7.2.stable.official.ed1daf0bf.

## Verdict

levels 5-8 CLEAN

320 level entries (40 seeds x 4 levels x 2 vote modes), both runs `EXIT=0`, both
`SWEEP DONE entries=160 built=160 build_failures=0`, and every one of the ten error
patterns the brief names has **0** matches in both logs. The late features were
*entered*, not assumed: on vote-mode `all` all 160 entries show boss, bankai, collapse,
clawds, gin and gin_sword true.

## The exact commands

Both were run from the checkout root, after one import pass (see the environment note):

```sh
"<godot>" --headless --path game --script res://tools/sweep_run.gd -- --seed-base 1 --seeds 40 --levels 5-8 --ticks 700 --vote-mode all > game/out/sweep_L5-8.log 2>&1 ; echo "EXIT=$?"
"<godot>" --headless --path game --script res://tools/sweep_run.gd -- --seed-base 1 --seeds 40 --levels 5-8 --ticks 700 --vote-mode random > game/out/sweep_L5-8_random.log 2>&1 ; echo "EXIT=$?"
```

with `<godot>` =
`"C:/Users/Nathan/Documents/REMAKE VWR/VOIDWARP-REMAKE/tools/godot/godot.exe"`.
Logs were not trimmed or filtered before grepping.

## Exit codes and SWEEP DONE tails

| run | exit | SWEEP start | SWEEP DONE tail |
| --- | --- | --- | --- |
| `--vote-mode all` | 0 | `seeds=1..40 levels=5-8 ticks=700 vote_mode=all` | `entries=160 built=160 build_failures=0` |
| `--vote-mode random` | 0 | `seeds=1..40 levels=5-8 ticks=700 vote_mode=random` | `entries=160 built=160 build_failures=0` |

`built` equals `entries` on both runs and `build_failures` is 0, so no `world.build()`
failed on any seed at any level in this range.

## Per-pattern grep counts

Counts are `grep -cF` (fixed strings) over each whole log.

| pattern | vote-mode all | vote-mode random |
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

Log sizes: 164 lines (`all`: banner, blank line, 160 ENTRY, SWEEP start/DONE - nothing
else) and 171 lines (`random`: the same plus 5 exit-time leak lines, below). There are
**no** unaccounted lines in either log.

## Per-level feature coverage (ENTRY rows showing the feature `true`)

40 rows per level per run. `died` is the driver recording that the controller died during
the run - the sweep driver revives it afterwards (documented in `tools/sweep_run.gd`) so
the arena pass can still run; a death is not a crash and not a finding.

### vote-mode `all` (every registry enemy voted in)

| level | rows | boss | bankai | collapse | clawds | gin | gin_sword | beacon | died |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 5 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 30 |
| 6 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 28 |
| 7 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 25 |
| 8 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 21 |

### vote-mode `random` (empty ledger, `world.build()` replays the lobbies)

| level | rows | boss | bankai | collapse | clawds | gin | gin_sword | beacon | died |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 5 | 40 | 40 | 40 | 40 | 0 | 0 | 0 | 40 | 7 |
| 6 | 40 | 40 | 40 | 40 | 0 | 0 | 0 | 40 | 5 |
| 7 | 40 | 40 | 40 | 40 | 0 | 0 | 0 | 40 | 6 |
| 8 | 40 | 40 | 40 | 40 | 0 | 0 | 0 | 40 | 9 |

`clawds`/`gin` are 0 on every `random` row by construction, not by failure: the swarm is
attached at level construction from the voted plan and the empty ledger carries no votes,
so no swarm-bearing enemy exists on those levels. The swarm and Gin's sword are covered by
the `all` run (40/40 rows on each of the four levels, `gin_sword` included), which is why
both vote modes were run. `collapse`, `boss`, `bankai` and `beacon` are reached on every
row in both modes.

## Findings

None. No seed/level/pattern triple to report: no non-zero exit, no `built < entries`, no
`build_failures > 0`, no line matching any of the ten patterns. The last ENTRY line before
exit is always the final `seed=40 level=8`, followed by `SWEEP DONE`, on both runs.

## Secondary observations (not counted as findings)

1. **Exit-time leak accounting appears intermittently.** The literal pattern
   `Leaked instance` matches 0 lines because Godot phrases this differently; the logs do
   carry such lines, so they are reported here in full rather than hidden behind a pattern
   that cannot match. `random`, 5 lines after `SWEEP DONE` (7 lines counted with the `at:`
   context lines): `2 RID allocations ... DummyTexture were leaked at exit`,
   `752 ... ShapedTextDataAdvanced were leaked at exit`,
   `1 ... FontAdvanced were leaked at exit`,
   `376 RIDs of type "CanvasItem" were leaked`,
   `764 ObjectDB instances were leaked at exit`. The `all` run printed **none** of these.
   Two small probes show it is shutdown accounting, not a mode: `--seeds 2 --levels 5-6
   --vote-mode random` printed 44 ObjectDB / 8 CanvasItem / 16 ShapedText leaks and
   `--vote-mode all` printed 18 ObjectDB leaks. All of it happens *after* `SWEEP DONE`,
   exit code stays 0, and the counts scale with the run, so it is unreleased views at
   process exit rather than a crash in a level. Worth a look by whoever owns teardown
   (`world.gd` teardown / `view` frees) - it is not a level 5-8 crash.
2. **First `--import` on a fresh checkout segfaults (exit 139) before importing anything.**
   The second pass is clean: `EXIT=0`, 580 files under `game/.godot/imported`. This is the
   known first-pass editor bootstrap on a checkout with no `game/.godot`, it happens before
   any game code runs, and `tools/gate.ps1` re-runs the import itself. Not a game finding,
   but recorded because a worker who only runs one import pass will see `load()` failures
   for every PNG/`.glb` afterwards.

## What this sweep does NOT cover

- **Levels 1-4 and 9-12**: other workers' ranges. Nothing here says anything about them.
- **Jump pads, the toucher floor, the mines and the gifts**: the 700-tick locomotion pass
  (a deterministic circle, a jump every 30 ticks, an ability every 90) drives the
  controller over them, but the ENTRY line carries no flag for them, so this report claims
  only that they were exercised, not that each was individually confirmed reached.
- **Rendered/audio paths**: everything ran `--headless`. A crash that needs a real
  renderer, a real audio device or an exported build is invisible to this sweep.
- **The owner's actual crash**: not reproduced in this range. The report is evidence that
  levels 5-8 survive 320 app-layer entries with the late features forced on, not proof
  that the game never crashes.

## Evidence on disk (gitignored, not committed)

- `game/out/sweep_L5-8.log` - vote-mode `all`, 164 lines
- `game/out/sweep_L5-8_random.log` - vote-mode `random`, 171 lines
- `game/out/probe_random_small.log`, `game/out/probe_all_small.log` - the two leak probes
- `game/out/import_L5-8.log` (the segfaulted first pass), `game/out/import_L5-8_2.log`
