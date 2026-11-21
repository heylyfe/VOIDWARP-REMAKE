![VOIDWRAP RUN](docs/hero.png)

# VOIDWRAP RUN

**A collectathon roguelite platformer.** Endless seeded levels of checkered causeways strung over a
foggy void. Collect every black gift to open the beacon, then leave safe — or linger for gold while
the pressure rises. You carry two void charges: a fall spends one, the beacon gives one back, and the
third fall is the end of the run.

The world is serious. The enemies are not.

> **Status: alpha — `v0.1.2-alpha.3`.** One level, playable end to end. Not yet a 30-level run.
> See [What works today](#what-works-today) for the honest list.

**VOIDWRAP RUN is a personal, non-commercial project — no money is involved, and it is not affiliated with, endorsed by, or connected to any person, brand, character, or IP referenced or depicted in the game.**

## What changed in v0.1.2-alpha.3

Waves 1–4 land together: the systems the earlier alphas built but never wired are wired now.

- **Every upgrade now has a shipped call site.** All 36 upgrades and
  all 46 curses were inert at the start of this work — the shop took gold and changed nothing.
  `world.gd` runs the modifier pass into the black-phase and gold-phase stat blocks and swaps them
  on the phase edges, and the controller consumes them. Field Dressing gives the free fall DESIGN
  section 8 promises, and the Last Light 8 u body push moves the live enemy rows instead of a
  spawn-time copy. The wiring was mutation-tested five ways; the follow-up found a real hole (stack
  repetition was unproven) and closed it.
  A final fresh-eyes review of this cycle's diff found the same defect still true for nine more:
  every sim-side consumer existed and was tested, and the call site in the shipped path did not,
  so the tests proved the sim and not the game. `pocket_beacon` — the most expensive upgrade in the
  game at 1200 g — could never teleport, because its channel was only ever advanced by the bot
  engine. `bounty_hunter`'s +50% bounty was never shown or paid, because the real Antechamber never
  ran the draw pass. Both are wired now, along with `more`, `last_call`, `straggler_scope`,
  `spring_heels`, `twin_dash`, `updraft` and `marathon`. The last gap, `quick_recovery`'s Athletic
  branch, is closed: the Athletic has no class cooldown, so the rule sentence gives it +5% run
  speed per stack instead, and the stat pipeline now takes a per-upgrade contribution for exactly
  that (DECISIONS D-B5A-1). The 46th curse, `zoomies`, is retired by design — the kiwi cat never
  dashes or lunges (DESIGN section 5, decision J6, SR-5) — and `test_curse_retired.gd` proves it
  can never be offered or dispatched, so it cannot cost a player a curse slot.
- **The curses are dispatched now.** 11 curses are pure stat modifiers and always applied through
  the modifier pass. The other 35 declare a script, and each had a module with its own unit test
  while nothing in the shipped game called any of them — the run tracked `curses_held` and handed
  it to the world, and no code walked that dict. `sim/curse_runtime.gd` is that walk: it reads the
  held ids generically, loads each module through a loader the world hands it, and runs the four
  hooks (`on_level_start`, `on_tick`, `on_beacon_open`, `on_void_fall`) in sorted id order. The
  pure queries — a blast radius, a tell distance, a rim glow, a reroll plinth, a straggler beam —
  now have their real consumers in the mines, the views and the lobby.
  34 of the 35 script curses are proven to change the game through `world.build()` and
  `world.step()`, each against a control world with the curse absent. The 35th is `zoomies`, which
  is retired from the offer pool and has no module. Two curses needed a design ruling to become
  live at all: `crumbling` reads "1-wide walkway tiles" as the outer lane of a walkway, because
  GEN_VERSION 4 makes every walkway three cells wide and the literal reading could never fire; and
  the glitched floor is no longer slippery by itself, because DESIGN section 7 reserves that
  friction for `wet_floor` and the sim was giving the curse's whole effect away for free.
- **Eight dropped stats got consumers.** `defuse_chance` and `pickup_radius` now have consumers in
  `sim/mines.gd` and `sim/gifts.gd`, `shop_price_mul` reaches the lobby shop (bargain and inflation
  move the price), the telegraph and enemy-speed multipliers reach `sim/enemy_runtime.gd`,
  `barrier_shields` absorbs a tripmine in `sim/controller.gd`, `fog_density` and `fill_light_range`
  reach the fog environment and the view's fill light.
- **The eleven enemy-linked curses get their modules** — `quarter_chimes`, `second_strike`,
  `understudies`, `wide_blast`, `spreading_rot`, `wet_floor`, `pup_pack`, `slipstream_trail`,
  `unannounced`, `token_limit` and `twin_fangs`. They were drawable and pickable but had no
  implementation, so the mandatory curse bay was a tax with no effect. They are reimplementations on
  `main`; the stale branch that once held them must never be merged.
- **Pause and the class altar.** ESC opened no pause at all — it destroyed the run. The pause
  overlay now freezes whatever is running and resumes it from the tick it stopped on. The class
  altar lets the player pick a kit instead of the app rolling one in three. Retry restarts the same
  seed into loading instead of returning to the menu, and the run log is written when a run ends.
- **Camera collision.** The camera clipped inside the level. `camera_rig.gd` now pulls in on a
  deterministic sphere sweep over the same tile-slab and prop boxes the sim moves bodies against —
  pure math, no engine physics, so the determinism rule holds. Pull-in snaps, the return eases, and
  the no-obstruction case is bit-identical to the old placement.
- **A settings screen that works.** The store had no UI and three of its four fields were inert.
  `settings_menu.gd` drives volume, FOV, fullscreen and mouse sensitivity, and each now reaches its
  consumer. The gate found seven real defects in the first version of this screen (the volume slider
  never reached the store or the master bus, the FOV slider never reached the store, nothing
  persisted, and show/close did not load or hide); all seven are fixed and `test_settings.gd` is
  green.
- **The presentation layer stops being dead code.** Every attack used to arrive with no ring, no
  line, no patch and no sound. The telegraph view draws the tells, the projectile view draws the
  balls, wind shots and the missile, the straggler beam gets its marker, danger text announces
  enemies, thicc ben's eject blurs the screen, and respawn invulnerability is visible. The ability
  cooldown bar and the curse and upgrade icon rows are fed. The audio cue layer gives every lethal
  threat a cue that precedes the attack — Coil's landing, Claude's drums and wind, gin's crack
  rumble — synthesized at runtime, with no binary assets.
- **Telegraphs expire and the nuke kills everyone in the blast.** Telegraph footprints never
  expired, so one nuke ring could block an enemy for the rest of a run. The live-telegraph filter
  now applies at the gate and the read layer; the raw list is deliberately not pruned. The nuke
  killed the nearest player rather than every player in the blast; it now hits them all.
- **Records.** `core/records.gd` is a local JSON store at `user://records.json` that ratchets the
  best level and best purse up only and never blocks on a missing or corrupt file. The menu shows
  both.
- **Safe respawns.** A void-fall respawn could land inside a lethal hazard. `level_state.gd`
  publishes the hazard footprints and the respawn search reads them.
- **The Larper's mines.** Gift Larper votes now land as extra tripmines on the next level. The sim
  keeps the vote ledger only; the app reads the roster module's own `extra_mines()` and hands the
  sum to the generator, because sim may not import `res://content/` at all.
- **Bot honesty.** The bot read the raw telegraph list, so it dodged telegraphs that had already
  ended. It now uses the same live-telegraph filter the game does.
- **Menu and ramps.** The menu shows the records store, and `test_classes.gd` now covers ramp
  kinds 1–4 (surface height, standing, and a walk in both directions) — the only gap left in the
  ramp fix.

The gate is green on this tree: `GATE OK (9 ran, 0 skipped, 327 s)`, `TESTS 89 passed 0 failed`
(was 71), `PARITY 56/56 OK`, `SPRITES OK`, `FOGCHECK OK (550 checks over 5 biomes)`, `SELFTEST
18/18`, `GALLERY 16/16`, zero SCRIPT ERROR lines. 68 changed or new files across ten commits.

## What changed in v0.1.1-alpha.3

One change: **the camera is locked to the character, and neither of them turns.**

Before this build the player figure rotated to face whatever direction it was moving while the
camera stayed put, so the character spun underneath a fixed view. Now the figure is locked to the
camera's forward: it always faces away from you and strafes. The camera does not turn either —
there is no mouse-look, so nothing can rotate it. Movement is still camera-relative, so "forward"
still means away from the camera.

The other reading of the request — the camera swinging around behind the character as it turns —
was built first and measured, then thrown away. It cannot work as a camera tweak: input is rotated
by the camera yaw, the character faces its velocity, and the camera chasing that facing closes a
loop. Holding a sideways direction spun the character at about **350°/s** and the camera never
caught up. The numbers are in `DECISIONS.md` (D-T082-4) so nobody re-derives them.

## What changed in alpha.3

Alpha.1 and alpha.2 shipped with the floor invisible. Six things were wrong; all six are fixed.

| what you saw | what it was | what it is now |
|---|---|---|
| Tiles had no texture at all | the level mesher emitted every tile **top** with its winding reversed, so the top face was back-facing and culled. You were looking at the slab **underside** — dark, flat, untextured | winding fixed; the tops carry the full detail stack: checker, per-texel grain, per-tile tone shift, seams, bevels, three-octave value noise, and a noise-derived normal and roughness |
| The ground you spawn on was flat colour | the hub shader was a single flat fill | the hub now runs the same detail stack as the platforms, and keeps its star sigil |
| Enemies froze on one frame | the billboard only read the legacy `animations[]` list; the sim drives the newer `anim.states` names, and 9 of 12 enemies had states with no matching art | both lists are merged, so every state the sim can ask for resolves to real art |
| First person, no body | the camera sat in the player's head | third person: a real player figure, a follow camera you can orbit, and a fill light so the figure reads against the fog |
| You fell through a platform | prop tops were not landing candidates | `move_body` takes prop tops as landings; pinned by `test_classes.gd` |
| Gifts were invisible | they were drawn, but on an untextured floor you could not see them | gifts, gold gifts, tripmines and the beacon column are all drawn in the level |

The README hero used to show the wrong image for **ADDRESS ME** — the explosion instead of the
enemy. It now shows the elephant, and all twelve cells are the real art.

## Play it

Download `voidwrap_run.exe` from the [releases page](https://github.com/heylyfe/VOIDWARP-REMAKE/releases)
and run it. Windows x86_64, single file, no installer and no runtime to install.

| input | action |
|---|---|
| `WASD` | move |
| `Space` | jump |
| `Shift` | ability — dash, per class |
| `F` | interact — gifts, mines, the beacon |
| `Tab` | toggle HUD |
| `Esc` | pause / back |

Gamepad works too. The menu's **HOW TO PLAY** panel shows the live bindings, read from
`game/data/bindings.json`.

## What works today

- **Menu** — PLAY / HOW TO PLAY / QUIT over a live 3D backdrop: the floating island, the open
  beacon's light column, and the full enemy roster standing on it as real billboards.
- **Loading screen** — 5.0 s on a first launch, 2.0 s on every restart, with a 2D gag scene and a
  30-tip pool that never repeats the previous gag.
- **Level 1** — generates from a seed, loads, plays, and completes. The beacon opens when every
  black gift is collected; the exit is a real transition, not a stub. The gifts, the gold gifts,
  the tripmines and the beacon's light column are drawn in the level itself.
- **12 enemies**, each with its own telegraph, attack, and death. They are the joke; the void is not.
- **Economy** — gifts, gold, void charges, tripmines, the beacon's charge refund.
- **After a level** — the world tears down and the app opens the Antechamber (the lobby); the next
  level is built from the lobby's ledger.

Known gaps, stated plainly:

- **The bot completes level 1 in 98 of 100 seeds** (seed base 60717, the pinned 4.7.2 engine,
  100 seeds re-measured on this tree). The acceptance bar is 95. The probe crashes with a Godot
  `Unreferenced static string` error at around 30 runs in one process, so long runs are measured
  in chunks; seeds are independent, so the splice loses nothing.
- **The difficulty bands are NOT met, and the probe that measures them cannot reach them.**
  Measured on this tree (seed base 60717, 20 runs, full depth): level 6 = 15% against a bar of
  ≥80%; level 12 = 0% against 40–60%; level 18 = 0% against 15–30%; median level reached 4, max 8.
  Two probe defects were found and both are fixed, which is why those numbers are the honest ones.
  The bot had no mine model at all — it advanced the sim through `MinesScript.tick()` and never
  read a mine position, so 37 of 99 deaths were tripmines it could not see. It also routed over
  unsupported tiles and fell into the void in 5 of 20 runs. With both fixed, D-MINE and D-VOID are
  ZERO and every remaining death is a genuine enemy kill (Coil 8, Kiwi 6, YOU?! 4, Toucher 1).
  The bands still fail because survival collapses in the middle of the run, not because of a bug:
  per-level survival — the share of runs that survive level N — is 95 / 80 / 65 / **35** / **15**
  percent for levels 1–5, measured in the same 20-run sweep as the band numbers above. Levels 3
  and 4 differ only by one extra enemy body, and survival drops 30 points; levels 4 and 5 drop 20
  more. No enemy-data change closes that. These are not independent trials — the ledger accumulates
  purchases and stacks as the run goes deeper, so multiplying them understates the real depth (the
  product is 2.6%, while the measured level-6 rate is 15%). The one band-safe change identified —
  moving the third enemy vote from lobby 3 to lobby 5, which preserves every DESIGN §9 row and
  would take level 6 to roughly 48% — is recorded in `PARKED.md` row 31 and NOT applied, because
  tuning the game to satisfy an instrument that cannot play it is the mistake the mine model
  already exposed. The bands are a target for a competent human and this probe cannot validate
  them.
- **Every enemy now has its own view, and the screen effects are fed.** This was the last
  presentation gap and it closed in cycle 2. Nine per-enemy view files (2,219 lines) had existed
  with nothing instantiating them, so every enemy rendered as a generic billboard; `view/enemies/
  enemy_view_host.gd` now routes a live enemy row to its own view and feeds it spawn, telegraphs
  and per-tick state, and coil got the one body it was missing (`view/coil_view.gd`). The three
  screen effects that only tests ever called — the void-edge flash, the Last Light bloom and the
  pip shatter — are wired to their real sim events. `test_app_enemy_views.gd` proves all nine
  through `world.build()`/`world.step()` and drives its own negative control, which reports 40
  failures across 10 legs. Gin's five cues were already emitted and proven by `test_audio_cues.gd`
  (an earlier version of this list said they were not — that was stale). What remains is art
  quality, not wiring: the views are procedural placeholders, not the bespoke sprite work the art
  brief describes.
- **Ten levels are proven end to end; thirty are not, and the blocker is the bot.** The intermission
  lobby is wired into the app loop: a completed level tears the world down and opens the Antechamber
  (`view/lobby/lobby_scene.gd`), and the next level is built from the lobby's ledger (class, votes,
  curses, purchases) when the player walks into the Descent Gate.
  The app cannot be driven headless at all (it reads devices only through the `Input` singleton,
  which delivers no key state without a window), so a proof has to drive the level loop directly.
  That loop is now proven: a driver that builds the real world and the real lobby, buys from the
  shop and carries the ledger forward completes **10 consecutive levels** and dies on the 11th —
  `deepest=11 completed=10 lobbies=10 purchases=2 stack_types_carried=5 purse=224 class=glider`.
  So the intermission handoff, the purchase path and the carried stacks all work at depth.
  What is not proven is 30 levels, and the reason is the bot rather than the harness: it is a
  simple heuristic and it dies on level 11. A second, simpler harness (`BotRun.play_run`, which
  does not shop between levels) does worse — across 24 seeds it enters a median of 4 levels, best
  8, worst 2 — which is itself the useful signal: shopping between levels roughly doubles the
  depth the same bot reaches. Proving a 30-level run now needs a better bot or a human
  playthrough, not more driver work.
- **PARKED.md rows 25, 26, 27 and 28 are closed.** Row 25 (the Last Light body push now reaches
  the live enemy rows), row 26 (ramp kinds 3 and 4 report the slope the mesh draws, with
  `test_classes.gd` covering all four kinds), row 27 (every enemy body mirror is refreshed each
  step so the safe-tile and SR-4 checks stop reading spawn points) and row 28 (the dead `rt_set`,
  the per-spawn `round_trip_set` rebuild, the dead `_killer_on_screen` branch and the write-only
  `spawn_deferred` field — all removed in `b2c5fa9`). Row 28's unproducible empty-C-bay stall
  outcome is a deliberate forced-gate behaviour in the bot, not a defect.
- **The tripmine needs no tuning, and the numbers say so.** The tell is visible from 12.0 u, the
  contact cylinder is 0.9 u and the player runs 9.0 u/s, so the warning is 1.23 s against a human
  reaction-plus-decision budget of 0.75 s. The tell ramps in rather than popping, fog leaves 87% of
  it at 12 u, and the minimum mine-to-mine distance across 200 levels is 2.000 u, so no wall can
  form. The bot's mine deaths are ZERO. Mines are absent for levels 1–4 and appear at level 5
  (`gift_larper` carries `min_level: 5`), which is a deliberate staircase: the counter-play (Defuse
  Kit) is first buyable at the post-L4 shop, exactly before the hazard appears.
- One exe-related row was closed by the v0.1.0-alpha.1 export.

## How a run works

1. **Spawn** on a causeway over the void. Two void charges in hand.
2. **Collect** every black gift on the level. The beacon stays shut until the last one.
3. **Decide** — walk into the open beacon and bank the run, or stay out for gold. Staying out is on
   a clock: the platform starts to crack the moment the beacon opens and every tile off the hub is
   gone five seconds later, so the gold phase is a dash, not a stroll. Enemies get faster and the
   fog closes in while you are out there.
4. **Fall** and you spend a charge. Fall with none left and the run ends.

Between levels the design calls for a lobby: class choice, enemy votes, curses, upgrades. That is
built, tested as a simulation, and wired into the app loop: completing a level opens the Antechamber,
and the next level builds from the lobby's ledger.

## Where things are

| path | what |
|---|---|
| [`DESIGN.md`](DESIGN.md) | the game: loop, economy, enemies, curses, upgrades, lobby, architecture |
| [`DECISIONS.md`](DECISIONS.md) | every significant decision with its why — read this first |
| [`ENEMIES.md`](ENEMIES.md) | the fixed enemy roster and its hard rules |
| [`TERRAIN_SPEC.md`](TERRAIN_SPEC.md) | the terrain generator spec; [`TERRAIN_REF.md`](TERRAIN_REF.md) is its reference |
| [`PARKED.md`](PARKED.md) | known bugs, each with the test that hides it and why it parked |
| [`AUDIT.md`](AUDIT.md) / [`TBD.md`](TBD.md) | the audit trail and the open questions |
| [`FLEET_PACK.md`](FLEET_PACK.md) | the ticket pack the multi-agent build ran from |
| [`terrain_ref/`](terrain_ref) | Python reference generator, validator and renderer (stdlib only) |
| [`game/`](game) | the Godot 4.7.2 project |
| [`game/app/`](game/app) | the app loop: menu → loading → world |
| [`game/sim/`](game/sim) | the simulation core — deterministic, headless, testable |
| [`game/content/enemies/`](game/content/enemies) | one folder per enemy: data, behaviour, sprites, sources |
| [`game/data/`](game/data) | tunable data — offering schedule, tips, bindings |
| `assets_src/enemies/` | the 17 source images the sprites are derived from. Not tracked — they are third-party material, not ours to redistribute, so they stay on the author's disk as the input of `game/tools/art/*.gd`. The derived sprites under `game/content` are what ships |
| [`research/`](research) | design research, the v1 retrospective, the run reports |

## Development

Engine: **Godot 4.7.2** (MIT), fetched into `tools/godot/` and never committed — see
[`tools/godot/README.md`](tools/godot/README.md). Language: GDScript. Ships as a native Windows
executable; no Electron, no browser wrapper.

```powershell
# look at a level without opening the engine
python terrain_ref\voidgen.py --seed 1 --level 1 --ascii
python terrain_ref\render.py --seed 7 --level 30 --out terrain_ref\out\l30.png

# the generator's invariants
python terrain_ref\gallery.py --check            # 16 pinned levels
python terrain_ref\validate.py --seeds 0:5000    # every invariant, 5,000 seeds
```

### Tests

```powershell
$G = "tools\godot\godot.exe"

# every discovered test (game/tests/test_*.gd; each exposes func run() -> Array[String])
& $G --headless --path game --script res://tests/run_all.gd

# terrain parity: GDScript generator against the Python goldens
& $G --headless --path game --script res://tests/test_terrain_parity.gd -- "$PWD\terrain_ref\gallery.json"

# the merge gate: every check except the 5,000-seed harness and the export
powershell -File tools\gate.ps1

# the full 5,000-seed generation harness
powershell -File tools\harness.ps1
```

The gate is the contract: 124 test files, terrain parity, sprite validation, fog readability across
five biomes, and a zero-`SCRIPT ERROR` requirement. Nothing merges red.

### Build

```powershell
& $G --headless --path game --export-release "Windows Desktop" ..\build\voidwrap_run.exe
```

The presets live in [`game/export_presets.cfg`](game/export_presets.cfg) — `Windows Desktop`, `Linux`
and `macOS` — and the output lands in `build/`, which is gitignored. `Linux` and `macOS` need the
4.7.2 export templates installed for your engine; the Windows one already ships them.

Exporting by hand needs the templates for the target platform in the engine's templates folder. CI
does not: [`.github/workflows/build.yml`](.github/workflows/build.yml) fetches the engine and its
templates for the pinned version on each runner, refuses to build if the binary does not report
`4.7.2.stable.official.ed1daf0bf`, and uploads a build per platform on every push, pull request and
tag. Tag builds are also attached to the GitHub release.

| Target | Artifact | Notes |
| --- | --- | --- |
| Linux x86_64 | `voidwrap_run.x86_64` | single binary, pck embedded |
| Windows x86_64 | `voidwrap_run.exe` | single binary, pck embedded |
| macOS universal | `voidwrap_run.zip` | `VOIDWRAP RUN.app`, x86_64 + arm64, **unsigned**, cross-built on Linux |

The macOS build is unsigned and not notarized, so Gatekeeper blocks it on a fresh machine until the
user clears it (`System Settings > Privacy & Security > Open Anyway`). Signing needs an Apple
Developer identity, which the project does not have.

macOS builds only work because [`game/project.godot`](game/project.godot) imports the ETC2/ASTC
texture variants: Godot refuses an arm64 export without them. The desktop presets do not pack those
variants, so their builds are unchanged by it.

## Credits

- **Engine** — [Godot](https://godotengine.org) 4.7.2, MIT.
- **Enemy source images** — third-party material, used without licence for a personal
  non-commercial project. Per-enemy provenance is in `game/content/enemies/*/SOURCES.md`.
- **Everything else** — generated for this project: terrain, meshes, audio cues, UI.

this is a personal, non-commercial project with no money involved. It is not affiliated with, endorsed by, or connected to any person, brand, character, or IP referenced or depicted in the game.
