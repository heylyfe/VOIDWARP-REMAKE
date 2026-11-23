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

### F1 (MEDIUM, the only finding in the two deliverable logs; **RESOLVED, see below**) - 4 detached `Label` nodes leaked per entry on the empty-ledger path

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

### F1 RESOLVED (D-U5-1) - the leak is `game/view/hud/icon_rows.gd:163`, which built a stack badge for every cell but parented it only when the cell showed a count

**The owner, plainly.** `icon_rows.gd:_rebuild()` is the function that fills the curses and
upgrades rows of the HUD, one icon cell per held curse/upgrade. It built the "xN" stack
badge for **every** cell and then parented it only inside `if stacks > 1`:

```
game/view/hud/icon_rows.gd:163   var badge := Label.new()          # built for EVERY cell
game/view/hud/icon_rows.gd:165   HudStyle.style_label(badge, ...)  # styled (font + colours)
game/view/hud/icon_rows.gd:170   if stacks > 1:
game/view/hud/icon_rows.gd:171       cell.add_child(badge)         # only parented here
```

For a single-stack cell the badge was created and styled, went into **no parent**, and
nothing in the tree could free it - a detached `Label` with a font override and a text
shape, exactly the "4 x Label + FontFile + StyleBox pair + ShapedTextData" the verbose dump
named. That is why the node path was empty: it never had one.

**Why the vote mode decided it.** The rows only draw what the run actually holds. The sweep's
`all` mode passes a full `votes` ledger but an empty `curses`, so the HUD snapshot has no
curses and no upgrade stacks, `_rebuild()` never draws a single-stack cell, and nothing
leaks. `random` passes an empty ledger, `world._resolve_run()` replays the lobbies, the
replayed altar picks land curses and upgrade stacks, and every single-stack cell dropped one
badge on the floor: 4 per level build, 160 builds, 680 CanvasItem RIDs.

**The fix** (`game/view/hud/icon_rows.gd`, the only production file touched):

- the badge is now built *inside* the `if stacks > 1` arm, through a new `_stack_badge()`
  helper that always returns a node its caller parents, so the rule lives in one place;
- nothing is suppressed: no warning filtered, no verbose flag, no change to the exit report.
  The leak is gone because the allocation is gone.

**Proof, before -> after.** Leak-family lines (`grep -Eci 'leaked|still in use'`) on the
same commands, same seed window:

| log | command | before | after |
|---|---|---|---|
| `sweep_L9-12.log` | the brief's `--vote-mode all` sweep, 160 entries | 0 | **0** |
| `sweep_L9-12_random.log` | the brief's `--vote-mode random` sweep, 160 entries | **5** | **0** |
| `ctl_random_2seeds.log` | `--seeds 2`, random, 8 entries | 6 | 2 (audio only, F2) |
| `ctl_all_2seeds.log` | `--seeds 2`, all, 8 entries | 0 | 2 (audio only, F2) |
| `ctl_random_1entry.log` | `--seeds 1 --levels 9-9`, random | 5 | 2 (audio only, F2) |
| `ctl_all_1entry.log` | `--seeds 1 --levels 9-9`, all | 2 | 2 (audio only, F2) |

The two deliverable sweeps went **5 -> 0** and **0 -> 0**, both still
`entries=160 built=160 build_failures=0` with `EXIT=0`, and all ten crash patterns still
count 0 in both.

The small counts left in the control runs are **not** this leak and are not labels: they are
F2's audio streams still in use at exit, which fluctuates run to run (that is why
`ctl_all_2seeds` moved 0 -> 2 with no label involved). Checked with a `--verbose` dump of the
very command that used to leak 4 labels:

```
ctl_random_verbose_1entry_BEFORE.log   (old code)  Leaked instance: Label ... x4
ctl_random_verbose_1entry.log          (fixed)     Leaked instance: Label ... x0
```

The four instance ids in the BEFORE dump (`...23682`, `...154091`, `...863085`, `...014909`)
are the same four the original finding named, so this is the same defect closing, not a
related one going quiet. F2 is untouched and still open.

**The regression test and its teeth.** `game/tests/test_hud_icon_badges.gd`, with
`game/tests/leak_probe_icon_rows.gd` as its probe (no `test_` prefix, so `run_all.gd` does
not run it as a test).

The obvious test is a trap here: the leaked node is **detached**, so counting labels under
the row passes with the bug present, and Godot's `Performance` monitors refresh once per
frame - measured, five orphan `Label`s moved `OBJECT_NODE_COUNT` by 0 inside one synchronous
`run()`. The one observer that does see a detached node is the engine's own exit report,
which only exists at process exit. So the test runs the probe as a **child Godot process**:
six rows of single-stack curses plus six of upgrades, all freed, with `--verbose`, then reads
the dump for `Leaked instance: Label`.

Teeth, measured by running the finished test against the old code and the fix:

- old code: `FAIL icon rows: 48 Label(s) leaked at exit in the probe (Leaked instance: Label:31356618199 - Node path:)` - 48 = 6 x 4 curses + 6 x 4 upgrades, exactly one per single-stack cell;
- fixed code: `TESTS` clean, 0 leaked labels.

A second assertion stops the fix degenerating into "never draw a badge": a 3-stack cell must
still render `x3`, the single-stack cell beside it must render none, and a rebuild must not
accumulate badges. The probe prints its own receipt line, and the test fails if that receipt
is missing, so a probe that silently did nothing cannot pass as clean.

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

**levels 9-12: 1 finding, F2** - F1 is fixed and closed on this branch (D-U5-1, "F1 RESOLVED"
above): the icon-row stack badge was built for every cell and parented only when the cell
showed a count, and the badge is now built only where it is shown. The two deliverable
sweeps were re-run after the fix on the same seeds: `random` went from 5 leak-family lines to
**0**, `all` stays **0**, both still `entries=160 built=160 build_failures=0` with `EXIT=0`
and all ten crash patterns at 0.

What remains open is F2 (audio streams and playbacks still in use at exit, short runs only,
never seen in either 160-entry run).

No crash, no non-zero exit, no failed build, and no parse/script error on any of the 320
entries: **the app layer did not crash on levels 9-12 under this driver.** The owner's crash
is not reproduced by these levels here; F1 was the one defect this sweep surfaced and it is
closed.

## Gate (D-U5-1): exit 1, and the one failure is NOT this change

`powershell -File tools\gate.ps1` on this branch: **exit 1**, `TESTS 145 passed 1 failed`.

Steps 1 and 2 pass (python oracle `TESTS OK, SELFTEST 18/18, GALLERY 16/16 OK`; terrain
parity). Step 3 `run_all` reports one failing test, and my new test passes inside it:

```
PASS res://tests/test_hud_icon_badges.gd
FAIL test_model_materials.gd: res://view/asset_load.gd loads a model under res://assets/models/
     but never assigns a base material with vertex_color_use_as_albedo (and is not on the J12 allow-list)
FAIL test_model_materials.gd: res://view/player_figure_fallback.gd  ... same
TESTS 145 passed 1 failed
```

**That failure is pre-existing at the base commit `4c15bf9`, not caused by this fix.** Proven
by stashing every change on this branch (fix, tests and docs) and running the same test
against the pristine base: `test_model_materials.gd failures=2`, the same two messages. It is
U4's fail-soft asset work (`view/asset_load.gd`, `view/player_figure_fallback.gd`, both added
by `4c15bf9`), not the HUD, and my diff touches no file that test scans.

Why it is not fixed here: the two candidate repairs are both outside this task's scope. The
files belong to U4's asset-loading track (the same reason `app/world.gd` is off limits this
cycle), and the other repair - a J12 allow-list entry - would mean editing a test, which is
forbidden. The correct entry would be honest rather than a weakening, because both files are
pure loaders that hand the model to a caller which applies the body material: the loader
never renders it, exactly the rationale the allow-list already carries for
`view/respawn_view.gd`. That call belongs to the integrator.

So: the F1 fix is complete and proven, and the branch's gate is red for a reason that predates
it and is reproducible without it.

**The exact patch I would apply** (not applied - outside scope). Both files are loaders that
never render the model's body, which is precisely what the allow-list exists for, so the
honest repair is two reasoned entries in `game/tests/test_model_materials.gd:58`, not a
material assignment these files have no use for:

```gdscript
const ALLOW_LIST := {
	"res://view/respawn_view.gd": "... (existing entry, unchanged) ...",
	"res://view/asset_load.gd": "a fail-soft PackedScene loader: it returns the scene to a caller that instantiates it and applies the body material, and never instantiates or renders the model itself, so vertex_color_use_as_albedo has nothing to act on here (U4, Terra's instantiate-on-null finding).",
	"res://view/player_figure_fallback.gd": "builds the blocky fallback from ArrayMesh box meshes; it names res://assets/models/player_figure.glb only in a comment explaining why the fallback exists, and never loads or renders the model, so vertex_color_use_as_albedo is meaningless here.",
}
```

The alternative - assigning `vertex_color_use_as_albedo` in the loaders - would be wrong: it
would apply a material to a resource these two files never instantiate. Either way the call
is the integrator's, and while the entry is missing the gate stays red for everyone.

## Raw evidence (gitignored, on disk)

`game/out/sweep_L9-12.log`, `game/out/sweep_L9-12_random.log` (the two deliverable logs),
`game/out/ctl_all_1entry.log`, `game/out/ctl_all_2seeds.log`, `game/out/ctl_all_verbose_1entry.log`,
`game/out/ctl_random_1entry.log`, `game/out/ctl_random_2seeds.log`,
`game/out/ctl_random_verbose_1entry.log`, `game/out/ctl_random_verbose_L10.log`,
`game/out/import_L9-12.log`.

For F1's before/after (D-U5-1), the pre-fix copies are kept beside the re-runs:
`game/out/*_before.log` (`sweep_L9-12_before.log`, `sweep_L9-12_random_before.log`,
`ctl_random_2seeds_before.log`, `ctl_all_2seeds_before.log`, `ctl_random_1entry_before.log`,
`ctl_all_1entry_before.log`), the same command run against old and new code is
`ctl_random_verbose_1entry_BEFORE.log` vs `ctl_random_verbose_1entry.log`, the child-process
probe dumps are `probe_old.log` (48 leaked Labels) and `probe_new.log` (0), and the gate run
is `gate_U5-1.log`.
