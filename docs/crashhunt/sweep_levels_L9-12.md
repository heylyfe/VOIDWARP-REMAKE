# Crash sweep - levels 9-12 (cycle 8, track U4)

Worker: test sub-agent, "crash sweep L9-12" (one of four range workers).
Branch `t3/sweep-levels-9-12`, base commit `4c15bf9` (U4's committed state, which carries
`game/tools/sweep_run.gd`). Engine `Godot 4.7.2.stable.official.ed1daf0bf`.

The bot in `tools/bot_run.gd` stalls at level 2, so these levels were driven through the
REAL app world (`app/world.gd`) by `game/tools/sweep_run.gd`, which forces the late features
on: the boss arena, the Bankai cinematic (the sim owns a 1530-tick clock, the view owns the
25.5 s animation), the platform collapse, the jump pads, the clawd swarm, Gin's sword and
the toucher floor.

## The exact commands

Run from the checkout root, twice, both vote modes:

```
"<godot>" --headless --path game --script res://tools/sweep_run.gd -- --seed-base 1 --seeds 40 --levels 9-12 --ticks 700 --vote-mode all > game/out/sweep_L9-12.log 2>&1 ; echo "EXIT=$?"
"<godot>" --headless --path game --script res://tools/sweep_run.gd -- --seed-base 1 --seeds 40 --levels 9-12 --ticks 700 --vote-mode random > game/out/sweep_L9-12_random.log 2>&1 ; echo "EXIT=$?"
```

`<godot>` is `"C:/Users/Nathan/Documents/REMAKE VWR/VOIDWARP-REMAKE/tools/godot/godot.exe"`.

One prerequisite was run once first, because this was a FRESH worktree with no import state:
`"<godot>" --headless --path game --import` (exit 0). Without it no PNG/.glb/.mp3 is imported
in a new checkout and every `load()` fails, which would have produced fake findings. This is
the same import `tools/gate.ps1` performs itself.

40 seeds x 4 levels x 2 vote modes = **320 level entries**, 160 per vote mode.

## Result summary

| vote mode | EXIT | SWEEP DONE | built < entries | build_failures |
|---|---|---|---|---|
| `all`    | 0 | `entries=160 built=160 build_failures=0` | no | 0 |
| `random` | 0 | `entries=160 built=160 build_failures=0` | no | 0 |

Both `SWEEP DONE` lines in full (they are the last stdout line before exit in each log):

```
SWEEP DONE entries=160 built=160 build_failures=0
SWEEP DONE entries=160 built=160 build_failures=0
```

**No entry failed to build and no run exited non-zero. The app layer did not crash on any of
the 320 entries** - the driver ran to its own end and called `quit(0)` in both modes.

## Per-pattern grep counts (both deliverable logs)

Counted case-sensitively with `grep -cF`. The leak-family block was re-counted after
`tr '\r' '\n'` so nothing hides inside a carriage-return chunk; the numbers did not change.

| pattern | `all` | `random` |
|---|---|---|
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

The `all` log is not merely free of the ten patterns: it contains **no `ERROR` and no
`WARNING` line at all**. Its only non-`ENTRY` lines are the engine banner, the `SWEEP start`
line, `SWEEP DONE` and `EXIT=0`.

The `random` log has zero matches on all ten patterns as written, but it does carry five
lines of the leak family the `Leaked instance` pattern is aimed at - Godot's non-verbose
leak report words them `were leaked at exit`, not `Leaked instance` (that string only appears
under `--verbose`). Counted as leak-family lines: **5 in `random`, 0 in `all`**. That is
finding F1 below; it is a finding, not a clean grep.

## Per-level feature coverage

How many of the 40 `ENTRY` rows per level report each feature true. Coverage is what the
driver actually reached, read back from the live level state, not assumed.

`--vote-mode all` (every registry enemy voted at 1, so every late feature is present):

| level | rows | boss | bankai | collapse | clawds | gin | gin_sword | beacon | died |
|---|---|---|---|---|---|---|---|---|---|
| 9  | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 26 |
| 10 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 24 |
| 11 | 40 | 40 | 40 | 40 | 40 | 38 | 38 | 40 | 21 |
| 12 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 40 | 16 |

`--vote-mode random` (empty ledger, so `world.build()` replays the lobbies):

| level | rows | boss | bankai | collapse | clawds | gin | gin_sword | beacon | died |
|---|---|---|---|---|---|---|---|---|---|
| 9  | 40 | 40 | 40 | 40 | 0 | 0 | 0 | 40 | 10 |
| 10 | 40 | 40 | 40 | 40 | 0 | 0 | 0 | 40 | 10 |
| 11 | 40 | 40 | 40 | 40 | 0 | 0 | 0 | 40 | 8 |
| 12 | 40 | 40 | 40 | 40 | 0 | 0 | 0 | 40 | 10 |

Every one of the 320 entries reached the boss arena, the Bankai cinematic, the collapse and
the beacon/300-gold completion. Level 10 - the boss-arena level - is fully covered in both
modes, which is the specific risk the brief named.

Two honest coverage notes:

- **The clawd swarm and Gin's sword are only exercised by the `all` mode.** Under `random`
  the replayed lobbies never vote a swarm-bearing enemy (`clawds=0` on all 160 rows) and
  never put Gin on the roster (`gin=0`), so no clawd or sword path is entered in that mode.
  Any claim about clawds/Gin rests entirely on the `all` log.
- **`gin` is 38/40 on level 11 in `all` mode**: seeds 2 and 23 died during the 700-tick
  locomotion pass before Gin's 360-tick spawn delay elapsed
  (`ENTRY seed=2 level=11 ... ticks=1969 died=true ... gin=false`,
  `ENTRY seed=23 level=11 ... ticks=2017 died=true ... gin=false`). Those are short entries,
  not crashes; they are named rather than counted as coverage.

## Findings

### F1 (MEDIUM, the only finding in the two deliverable logs) - 4 detached `Label` nodes leak per entry on the empty-ledger path

`--vote-mode random` reports at exit, after a perfectly clean 160-entry sweep:

```
ERROR: 2 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.
ERROR: 1360 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit.
ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.
WARNING: 680 RIDs of type "CanvasItem" were leaked.
WARNING: 1372 ObjectDB instances were leaked at exit (run with `--verbose` for details).
```

(log lines 329-339, immediately after `SWEEP DONE` on line 327; the seed/level of the last
entry before the report is `seed=40 level=12` - the leak is an at-exit report, so it is not
tied to one seed or level, and that row is named only because it is the last one.)

`--vote-mode all` with the identical driver and the identical 160 entries reports **none of
this** - no leak warnings whatsoever. So it is the vote mode, not the sweep length.

Localised with control runs (`game/out/ctl_*.log`, all exit 0):

| run | entries | CanvasItem RIDs | ShapedTextData | ObjectDB |
|---|---|---|---|---|
| `random --seeds 1 --levels 9-9`   | 1   | 4   | 8    | 32 |
| `random --seeds 2 --levels 9-12`  | 8   | 36  | 72   | 88 |
| `random --seeds 40 --levels 9-12` | 160 | 680 | 1360 | 1372 |
| `all --seeds 1 --levels 9-9`      | 1   | 0   | 0    | 16 (audio, see F2) |
| `all --seeds 2 --levels 9-12`     | 8   | 0   | 0    | 0 |
| `all --seeds 40 --levels 9-12`    | 160 | 0   | 0    | 0 |

A `--verbose` run names the leaked objects (`game/out/ctl_random_verbose_1entry.log` and
`ctl_random_verbose_L10.log`, both 1 entry, both the same 4 labels):

```
Leaked instance: Label:107860723682 - Node path:
Leaked instance: Object:107877500899
Leaked instance: Label:108280154091 - Node path:
Leaked instance: Object:108296931308
Leaked instance: Label:108699584500 - Node path:
Leaked instance: Object:108716361717
Leaked instance: Label:109119014909 - Node path:
Leaked instance: Object:109135792126
Leaked instance: FontFile:9223372059034256215 - Reference count: 8
Leaked instance: StyleBoxFlat:9223372060829418833 - Reference count: 8
Leaked instance: StyleBoxEmpty:9223372061047522654 - Reference count: 8
```

Reading: **exactly 4 `Label` nodes per entry**, each with one orphan companion `Object` and
a shared `FontFile` plus a `StyleBoxFlat`/`StyleBoxEmpty` (so the four are styled HUD-style
labels, not plain ones). Their `Node path:` is **empty**, which is Godot's marker for a
node that was never added to a parent or was detached - the engine even prints its own hint
in the same log: "Leaked instances typically happen when nodes are removed from the scene
tree (with `remove_child()`) but not freed". So the four are built and never mounted or
freed, once per `world.build()` on the empty-ledger path.

The counts are not exactly linear in entries (1 -> 4, 8 -> 36, 160 -> 680 CanvasItems;
32 -> 88 -> 1372 ObjectDB), so this report does not model the growth beyond "about four
labels per entry, plus fixed slack". What is established is the condition, not the formula.

Reproducibility: 6 runs on 3 different sizes, same-class leak in every `random` run, and 3
`all` runs clean at the same sizes. The differing code path is `world._resolve_run()`: a
non-empty ledger returns the caller's plan immediately (the `all` case), while an empty one
(`random`) replays the lobbies through `IntermissionScript.create()` and the altar/vote
loop before the level is built. This sweep pins the condition; it does not name the exact
creating line, and the fix belongs to the integrator.

Impact: no crash, no wrong state, no determinism change - 160 entries still built and ran
correctly. It is unbounded memory growth per level build on that path, and the owner-visible
symptom would be a game that gets heavier the more levels are played through the lobby flow.
Relevant to the cycle-8 crash report because a leak is a candidate cause of a late-session
failure, but this sweep does **not** show it crashing anything.

### F2 (LOW, control runs only, not present in either deliverable log) - audio resources still in use at exit

Seen in short runs of both vote modes:

```
WARNING: 16 ObjectDB instances were leaked at exit (run with `--verbose` for details).
ERROR: 3 resources still in use at exit (run with `--verbose` for details).
```

Verbose names them: `AudioStreamWAV`/`AudioStreamMP3` plus `AudioStreamPlaybackWAV`/
`AudioStreamPlaybackMP3`, holding `res://view/cinematics/custom_voiceline.mp3`,
`res://assets/audio/world/beacon_open.mp3` and `res://assets/audio/world/level_complete.wav`
still referenced at shutdown.

Caveat stated plainly: this appears in `ctl_all_1entry.log` (1 entry) and
`ctl_random_1entry.log`, and **disappears** in both 8-entry and 160-entry `all` runs. It is
therefore state-dependent (whatever is playing at `quit()`), not per-entry accumulation, and
it is not reproducible from the two commands the brief specifies. Recorded for the
integrator; not counted as a levels-9-12 finding.

## What is explicitly NOT a finding

- `died=true` rows (26/24/21/16 in `all`): the driver's own deterministic circle-walk dying
  to live enemies. The sweep records the death and revives the controller itself so the
  boss/Bankai pass still runs. Sim behaviour, not an app-layer defect.
- The `ticks=1969` / `ticks=2017` short level-11 rows: early death before Gin spawns, see
  the coverage notes.
- The 1530-tick Bankai block per entry: that is the intended 25.5 s cinematic being run to
  its end, which is why level 10 entries are the longest (~2440 ticks).
- `game/out/` is gitignored; the logs there are the raw evidence and are not committed.

## Verdict

**levels 9-12: 2 findings** - F1 (leak of 4 detached `Label` nodes per level build on the
empty-ledger/`random` path, reported as RID + ObjectDB leaks at exit) and F2 (audio streams
and playbacks still in use at exit, short runs only).

No crash, no non-zero exit, no failed build, and no parse/script error on any of the 320
entries: **the app layer did not crash on levels 9-12 under this driver.** The owner's crash
is not reproduced by these levels here; the leak in F1 is the one defect this sweep surfaces.

## Raw evidence (gitignored, on disk)

`game/out/sweep_L9-12.log`, `game/out/sweep_L9-12_random.log` (the two deliverable logs),
`game/out/ctl_all_1entry.log`, `game/out/ctl_all_2seeds.log`, `game/out/ctl_all_verbose_1entry.log`,
`game/out/ctl_random_1entry.log`, `game/out/ctl_random_2seeds.log`,
`game/out/ctl_random_verbose_1entry.log`, `game/out/ctl_random_verbose_L10.log`,
`game/out/import_L9-12.log`.
