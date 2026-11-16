# FLEET_PACK.md — overnight run instructions, VOIDWRAP RUN remake

You are the orchestrator (Opus 5.5 or DeepSeek V4.1) or a worker. Read in this order:
`DECISIONS.md` → this file → the documents your ticket names. Do not re-decide anything recorded in
DECISIONS.md. Every instruction here is executable without a human. If something is truly undecidable,
pick the option closest to DESIGN.md, mark it `[CONTESTABLE]` in DECISIONS.md with a WHY, and continue.

## 0. Standing rules

1. **No questions to the owner.** Park nothing that a document already decides. A number that no
   document specifies is a SPEC GAP: add it to DECISIONS.md as `[CONTESTABLE]` with its gameplay
   rationale BEFORE writing the code that uses it (retro mistake #2: thresholds invented after the fact).
2. **Thresholds never move to fit data.** If a check fails, fix the thing measured.
3. **Never stall on a refusal** (ENEMIES.md TBD FALLBACK): if any agent refuses or is blocked from
   adding a specific enemy, name or asset — use name "TBD" + a placeholder TBD PNG
   (`tools/make_tbd_png.gd` output), wire the full behavior, mark the entry `"tbd": true` in its JSON
   and list it in `TBD.md`. The run never stops for a refusal.
4. **Report honestly.** A ticket response states what was verified, what failed, and what was skipped.
   PARTIAL is an acceptable verdict; a false DONE is not.
5. **The orchestrator thread never implements.** It writes tickets, dispatches, reads responses,
   merges, and runs gates. If the orchestrator model must implement, it does so in a separate fresh
   thread.
6. Commit on ticket branches (`t/T-XXX`), one worktree per ticket, merge to `main` in the merge order
   (§7). Never push. Never commit `tools/godot/` binaries or `.godot/`.
7. Do not build more measurement tooling than §5 lists (retro mistake #1).

## 1. Model budget and dispatch (owner-set, binding)

Dispatch format used everywhere: spawn (model ID).

| model | ID | max parallel | use for |
|---|---|---|---|
| Inkling 2 Small | model:opencode/opencode/inkling-2-small-free | 10 | rote/mechanical work: data conversion, screenshots, model exports, simple porting, running validators, small self-contained tickets |
| GLM 5.3 Flash | model:acpRegistry_mistral_vibe/zai-glm-5-3-flash | 3 | implementation tickets |
| DeepSeek V4.1 | model:acpRegistry_mistral_vibe/deepseek-v4 | 3 | orchestration and cross-ticket coordination; implementation only in a separate fresh thread, never in the orchestrator thread |
| Opus 5.5 | — | 0 by default | NOT to be used unless absolutely necessary. Running out of Inkling budget is preferable to escalating |

Drain the cheap models first. Track what is spawned; never exceed the counts. A ticket that fails
twice on Inkling is re-dispatched once to GLM; a ticket that fails twice on GLM is split into two
smaller tickets, not escalated.

Brief-writing rules learned in the design session (they worked): give the worker the exact repo path,
the files to read first, the exact files it may create/edit, the commands to run before reporting, and
the report format. Tell it explicitly not to weaken checks. Workers start with zero context.

## 2. What exists already (do not rebuild)

| path | what | state |
|---|---|---|
| `TERRAIN_SPEC.md`, `TERRAIN_REF.md` | terrain spec + reference guide | final for GEN_VERSION 1 |
| `terrain_ref/voidgen.py` | Python generator — THE ORACLE | working, hash-pinned |
| `terrain_ref/validate.py`, `test_validate.py` | independent validator + 5,000-seed harness | see TERRAIN_REF.md status |
| `terrain_ref/gallery.py`, `gallery.json`, `render.py` | 16 pinned levels, PNG map renderer | working |
| `game/terrain/voidgen.gd` + `game/tests/test_terrain_parity.gd` | GDScript port, hash parity | see TERRAIN_REF.md status |
| `tools/godot/godot.exe` | Godot 4.7.2-stable (gitignored; reinstall via `tools/godot/README.md`) | installed |
| `DESIGN.md`, `game/data/offering_schedule.json` | game design, schedule | final for run 1 |
| `ENEMIES.md` (owner file, copied into the repo root) | fixed roster + HARD RULES | FIXED, never edit |
| `assets_src/enemies/` | the 17 owner images go here with their EXACT filenames | EMPTY until the owner drops them in — every missing file = TBD fallback, never a stall |
| `research/NULLSCAPE_PATTERNS.md` | wiki facts | reference only |
| `research/VOIDWRAP_RETRO.md` | retrospective of the EARLIER, abandoned build | HISTORY ONLY — never a source, never ported (D-055). Mentions of the earlier build elsewhere in these documents are history too |

## 3. Architecture and module boundaries

Engine: Godot 4.7.2, GDScript only (D-001). Project root: `game/`.

```
game/
  terrain/   voidgen.gd, void_rng.gd            PURE. no Node. byte-parity with terrain_ref.
  sim/       run_state.gd level_state.gd player.gd controller.gd collision.gd enemy_runtime.gd
             projectiles.gd gifts.gd beacon.gd economy.gd offers.gd input.gd state_hash.gd
             PURE + DETERMINISTIC. RefCounted only. no Node, no engine physics, no Time, no randf.
  core/      registry.gd stats.gd hooks.gd schemas/*.json content_api.gd
             PURE. loads content/ and data/. names NO content id.
  view/      level_mesher.gd materials.gd fog_env.gd billboard.gd enemy_view.gd vfx/ hud/ lobby/ audio/
             Node-based. reads sim state + events. never writes sim state.
  app/       main.tscn main.gd input_capture.gd loading_screen.gd menu.gd settings.gd
  content/   enemies/<id>/…  curses/*.json  upgrades/*.json  biomes/*.json  gimmicks/  modes/standard/
  data/      offering_schedule.json upgrade_pools.json economy.json player.json tips.json palette.json
  assets/    models/*.glb (build artifacts)  icons/*.png  audio/*.wav
  tests/     run_all.gd + test_*.gd (headless)   fixtures/dropin/…
  tools/     headless SceneTree scripts (bots, validators, sprite pipeline)
assets_src/  enemies/<exact filenames from ENEMIES.md>   blender/*.py (source of truth for .glb)
terrain_ref/ Python oracle (stdlib only)
tools/       godot/ (binary), gate.ps1, harness.ps1, blender/ (portable, gitignored)
```

Dependency rule (enforced by `tests/test_boundaries.gd`, a text scan): `terrain` imports nothing;
`sim` may use `terrain` and `core`; `core` may use `terrain`; `view` and `app` may use everything;
nothing under `terrain/ sim/ core/` may contain the strings `Node`, `get_tree`, `Engine.`, `Time.`,
`randf`, `randi`, `PhysicsServer`, `Input.` or any content id.

Simulation contract (DESIGN.md §13): 60 Hz fixed tick; `Sim.step(state, inputs: Array[PlayerInput])
-> Array[Event]`; state hash = SHA-256 of a canonical dump every 60 ticks; replay test proves
determinism. Votes/selections are inputs.

## 4. Build and test commands (PowerShell, from repo root)

```powershell
$G = "tools\godot\godot.exe"
# unit + integration tests (headless, exit code 0 = green)
& $G --headless --path game --script res://tests/run_all.gd
# terrain parity (GDScript vs Python goldens)
& $G --headless --path game --script res://tests/test_terrain_parity.gd -- "$PWD\terrain_ref\gallery.json"
# python oracle checks
python terrain_ref\test_validate.py
python terrain_ref\gallery.py --check
python terrain_ref\validate.py --selftest
# FULL generation harness: 5,000 seeds, all H/D invariants (run for terrain tickets and the audit)
python terrain_ref\validate.py --seeds 0:5000
# bot playthrough (headless, runs the sim faster than real time)
& $G --headless --path game --script res://tools/bot_run.gd -- --seed 1 --levels 1 --class dasher
# export a real Windows executable
& $G --headless --path game --export-release "Windows Desktop" ..\build\voidwrap_run.exe
# the gate = everything above except the 5,000-seed harness and the export
powershell -File tools\gate.ps1
```

`tools/gate.ps1` (ticket T-001) runs, in order, and stops at the first failure: python oracle checks →
terrain parity → `run_all.gd` → boundary scan → content schema validation → drop-in fixture test →
replay determinism test → sprite validator → fog-readability check. Target: ≤ 120 s warm. Formatting
is never a gate step (retro: `cargo fmt` stranded a worker).

"Gates green" in a Done-when = `tools\gate.ps1` exits 0 on the ticket branch rebased on current main.

## 5. Acceptance criteria for RUN 1 (numbers, not adjectives)

Run 1 is finished when ALL of these hold on `main`:

| # | criterion | measured by |
|---|---|---|
| A1 | `build\voidwrap_run.exe` exists, is a native Godot export (no browser/Electron), starts to the menu | T-056 smoke run: process alive 10 s, exit code 0 on `--quit-after 600` |
| A2 | terrain: 5,000-seed harness passes every H and D check; GDScript parity 16/16 + 40/40 | §4 commands |
| A3 | kiwi cat present, the bot runs with `--dodge` on, Last Light available, 2 charges held: the bot completes level 1 (all real black gifts → beacon) in ≥ 95 of 100 seeds, median ≤ 120 s sim time | `bot_run.gd --seeds 0:100 --dodge --enemy kiwi_cat` |
| A4 | replay determinism: 10 recorded bot runs replay with identical state hashes at every checkpoint | `test_replay.gd` |
| A5 | black→gold: after the last real black gift, gold gifts exist at exactly the same slot ids/positions (asserted on 100 seeds); beacon CLOSED→OPEN exactly then | `test_gifts.gd` |
| A6 | tripmines: occupancy read from terrain `occ` only; never highlighted; not counted in remaining; contact = the player's centre within 0.9 u of the box at ANY height (jumping over a mine does not avoid contact; a tripmine is a wall on its tile and the walkable bypass is the only way past); contact resolves in the fixed four-step order of DESIGN.md §3.3: 1. **Defuse roll** (Defuse Kit, §8): `roll = mix(mix(run_seed, level), slot_id) mod 100`; if `roll < 20 × stacks` (cap 60) the mine is **defused** — it is consumed, there is no blast and no death, and the chain resets. With 0 stacks the roll can never pass. 2. **Subspacial Barrier** (§8): if a shield is held, the shield is consumed and the mine is consumed with no blast; the chain resets. 3. **Last Light** (§3.1): if it is unspent and the player holds at least 1 void charge, it is spent as the final save (teleport to the beacon dais); the mine is consumed. 4. Otherwise the player is **killed** (`D-MINE`). The order is fixed: defuse roll, then Subspacial Barrier shield, then Last Light (D-053). The roll is deterministic — same seed + same slot id → same outcome on 1,000 seeds, and the observed defuse rate is within ±2 points of 20/40/60% at 1/2/3 stacks; a defused or shielded mine is consumed with no blast; death shows "gift Larper (Tripmine)" + `D-MINE` | `test_mines.gd` |
| A7 | all 12 enemies: behavior timings within ±1 tick of DESIGN.md §5; every body contact kills except thicc ben (blur 3.0 s + 18 u/s eject, never kills) and the three non-killing effects of §5; kill tests run with Last Light already spent (D-057); each has sprites.json with body_rect; hitbox test proves a point in transparent padding does not hit | `test_enemy_<id>.gd`, `test_hitbox.gd` |
| A8 | sprite validator: every enemy PNG has alpha 0 in all four corners and no opaque 1-px border; fog contrast ≥ 3.0 at 40 u | `tools/validate_sprites.gd` |
| A9 | lobby: physical scene; altars selectable with F (hold 0.35 s); schedule read from `data/offering_schedule.json`; mandatory bays gate the Descent Gate | `test_lobby.gd` (drives inputs) |
| A10 | content: 46 curses, 36 upgrades, 12 enemies, 5 biomes load and pass schema; level-1 shop pool is exactly Paycheck, More, Yearn for Speed | `test_content.gd` |
| A11 | economy audit: average-player model affords ≥ 1 offered item in ≥ 80% of shops and all 3 in ≤ 30% (1,000 simulated runs to level 30) | `tools/economy_audit.gd` |
| A12 | feel budget (DESIGN.md §2): loading screen ≥ 5.0 s and ≤ 8 s; gate→level ≤ 2.0 s; death→run-over ≤ 2.0 s; void fall→respawn ≤ 0.8 s; generate+mesh level 30 ≤ 1.5 s | `tools/feel_probe.gd` |
| A13 | performance: level 30 with 22 enemies, 600 frames: p99 frame time ≤ 16.6 ms (windowed 1080p), mean sim tick ≤ 2.0 ms | `tools/perf_probe.gd` |
| A14 | drop-in proof: fixture enemy/curse/upgrade/biome copied into `content/` are offered and work with zero core edits; boundary scan clean | `test_dropin.gd`, `test_boundaries.gd` |
| A15 | README and the lobby About plaque contain the disclaimer verbatim | `test_disclaimer.gd` (string compare) |
| A16 | `TBD.md` lists every TBD substitution; 0 tickets stalled on a refusal | audit T-099 |

If the night ends early, the cut order is from the bottom of the ticket list upward (later waves
first). Never cut Wave 0–2.

## 6. Tickets

Format (canon): `T-XXX` · THE OWNER'S SPEC (verbatim from the owner's brief/canon/ENEMIES.md — never
paraphrase it) · Assignment (plain text) · Read · Do · Done-when. Every Done-when implicitly includes:
**tests green + gates green**; tickets that touch `terrain/` or `terrain_ref/` also require **the
generation harness asserting the invariants across 5,000 seeds**.
Each worker writes `tickets/T-XXX.response.md`: verdict (DONE / PARTIAL / BLOCKED→TBD), what was
verified with command output, deviations, new DECISIONS entries.

### WAVE 0 — foundation (sequential)

**T-001 — Scaffold, gate, README**
THE OWNER'S SPEC: "a REAL game — it ships as its own standalone native .exe, NOT a browser game wrapped in an .exe (no Electron, no web-wrapper)"; "the overnight fleet can iterate on it — fast builds, headless-runnable tests, CLI-drivable". "The README must include: VOIDWRAP RUN is a personal, non-commercial project — no money is involved, and it is not affiliated with, endorsed by, or connected to any person, brand, character, or IP referenced or depicted in the game."
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: this file §3–4, DECISIONS.md A.
Do: create the `game/` folder tree of §3 (keep existing `game/terrain`, `game/tests`, `game/tools`); `game/tests/run_all.gd` (discovers `res://tests/test_*.gd`, each exposes `func run() -> Array[String]` of failures, prints `TESTS n passed m failed`, exit code = failures > 0); `tests/test_boundaries.gd`; `tools/gate.ps1`; `tools/harness.ps1`; `README.md` (what it is, how to run tests, how to build, the disclaimer verbatim, credits "enemy images: see content/enemies/*/SOURCES.md"); `TBD.md` (empty table); copy ENEMIES.md into the repo root if missing; first commit on `main`.
Done-when: `tools\gate.ps1` exits 0 (steps whose inputs do not exist yet print `SKIP <step> (pending T-XXX)` and are listed in the response); README contains the disclaimer string exactly.

**T-002 — Terrain parity lock**
THE OWNER'S SPEC: "seed-only multiplayer sync is a hard requirement — the generator's output must be a pure function of the seed alone." "The fleet ports and extends this instead of inventing their own."
Assignment: spawn (model:opencode/opencode/inkling-2-small-free)
Read: TERRAIN_REF.md.
Do: run every command in TERRAIN_REF.md §"Verify"; paste outputs into the response. If parity is not 56/56, re-dispatch to spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash) with the port brief in TERRAIN_REF.md §"Port guide" — the Python is never edited to match.
Done-when: harness 5,000 seeds all PASS; gallery 16/16; parity 56/56; selftest 12/12.

### WAVE 1 — engine layers (parallel after T-001)

**T-010 — Sim core, input, state hash, replay**
THE OWNER'S SPEC: "Keep ALL gameplay logic deterministic and input-driven, with zero hidden global state, so a future netcode layer only syncs seeds + player/enemy inputs."
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: DESIGN.md §13, TERRAIN_SPEC.md §3.
Do: `sim/run_state.gd`, `level_state.gd`, `input.gd` (PlayerInput: move_x/move_z int8 world-space, buttons bitmask JUMP=1 ABILITY=2 INTERACT=4), `sim.gd` (`step`), `state_hash.gd`, event list; `tests/test_replay.gd` (random-input 3,600-tick run recorded and replayed twice, hashes equal every 60 ticks; a deliberately perturbed input must change the hash).
Done-when: replay test green; boundary scan clean.

**T-011 — Level mesher, materials, fog**
THE OWNER'S SPEC: "Aesthetic: checkered theme, dim blue/cyan palette, blocky voxel style. Every model/terrain element passes a fog-readability check. The world is serious; enemies (PNG sprites per ENEMIES.md) are the only silly element." "Terrain/map must feel serious, atmospheric, moody … never make the terrain itself joke-y."
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: TERRAIN_SPEC.md §4, §8, §12 (all of it), DESIGN.md §10.
Do: `view/level_mesher.gd` builds from a Level dict: one ArrayMesh per material — platform top, walkway top, dead-end platform top (checker by `(x+z)&1`, 8 px/u nearest, ±6% grain), slab sides with trim band, ramps as wedges (ramp tiles are at most 10% of path rows, so wedges are rare), props as boxes, support spikes under platforms only, never under the hub (§12.4), hub sigil; greedy-merge coplanar same-material tiles into quads (≤ 30,000 triangles at level 30); `view/fog_env.gd` (WorldEnvironment: clear colour, exponential fog 0.012, ambient, no sun) reading `data/palette.json` + `content/biomes/<id>.json`; `tools/shot.gd` renders 4 fixed camera views of gallery seeds 1, 7@12, 7@30 to `shots/`; `tools/fog_check.gd` implements §12.3 exactly and exits 1 below threshold.
Done-when: `fog_check.gd` green for Deepwater; mesh for seed 7 level 30 builds in ≤ 600 ms; triangle count logged; 12 screenshots written.

**T-012 — Player controller and classes**
THE OWNER'S SPEC: "Classes (fixed roster): Dasher: a dash ability that regenerates in 3 seconds. Glider: glides — essentially the Nullscape glider. Athletic: double-jump upgrades are more powerful on this class, speed upgrades are more powerful on this class, and it starts with a built-in 15% speed increase."
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: DESIGN.md §3.1, §4; TERRAIN_SPEC.md §4–5.
Do: `sim/collision.gd` (AABB half-width 0.4, height 1.8 vs tile slabs 1 u thick, ramps, props; auto step-up 0.5 u), `sim/controller.gd` (constants from `data/player.json`: gravity 32, jump 12, run 9, coyote 0.10, buffer 0.10, jump cut ×0.5), dash / glide / athletic kits, **void charges** (2 held, cap 2; a void fall spends 1 charge and respawns on the last safe tile after 0.8 s with 1.0 s respawn invulnerability and a chain reset; a fall at 0 charges is a real death, `D-VOID`; beacon entry restores exactly 1 charge, capped at 2; charges carry over between levels — no reset at a level boundary), **safe tile** (solid, not glitched, outside every hazard footprint, and **at least 6 u from every enemy body and projectile**), **Last Light** (once per run; only while the player holds ≥ 1 void charge; saves a kill by an enemy, a tripmine or the nuke by teleporting to the beacon dais with the charges held and 2.0 s invulnerability; does not spend a charge; never triggers at 0 charges; never triggers on a void fall), launch pads (land on the pad's target tile). `tests/test_envelope.gd`: for every row of TERRAIN_SPEC §5.1 a scripted jump clears the VALIDATOR gap at that height and fails at gap+2; `tests/test_classes.gd`; `tests/test_charges.gd` (2 charges → 2 respawns → the 3rd fall kills; beacon entry 0→1, 1→2, 2→2; Hungry Void cap 1; the 8-tile ring and its re-validation; an enemy parked on the newest ring tile → respawn uses the next valid ring entry; all 8 invalid → the dais spawn tile); `tests/test_last_light.gd` (saves once at 2 charges and once at 1 charge; does nothing at 0 charges — the death is real; a void fall at 0 charges is `D-VOID` even with Last Light unspent; the second lethal hit after it is spent kills; HUD icon lit while armed, dim at 0 charges, grey once spent).
Done-when: envelope test green (this is the proof that the terrain guarantee and the controller agree — retro §4e); `test_charges.gd` and `test_last_light.gd` green.

**T-013 — Content registry, stats, hooks, drop-in proof**
THE OWNER'S SPEC: "Extensibility is a pillar: new content (enemies, modifiers, biomes, level gimmicks) must be addable LATER as drop-ins, without touching the core."
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: DESIGN.md §12.
Do: `core/registry.gd` (scan, sort by id, schema-validate, refuse boot with file name), `core/stats.gd` (closed stat list from DESIGN.md §12 + every stat named in §7–8 tables), `core/hooks.gd`, `core/content_api.gd`, JSON schemas, `tests/fixtures/dropin/` (one enemy, curse, upgrade, biome), `tests/test_dropin.gd`, `tests/test_content.gd`.
Done-when: drop-in test green with zero edits outside `content/`; a malformed JSON fixture fails boot with its file name.

**T-014a / T-014b / T-014c — Data conversion (three parallel rote tickets)**
THE OWNER'S SPEC: "aim for 40+ distinct curses at launch, each with a clear rule and counter-play where relevant"; "Aim for 30+ at launch with price tiers, delivered through the per-level UPGRADE POOLS."; "Loading screen … a rotating, data-driven tip pool (15+ tips, prioritizing gift-vs-hazard tells)."
Assignment: 3× spawn (model:opencode/opencode/inkling-2-small-free)
Read: DESIGN.md §7 (a), §8 (b), §2–3 and §14 (c); the schemas from T-013 once merged (until then use DESIGN.md §12 field names).
Do: (a) one `content/curses/<id>.json` per row of DESIGN.md §7.1 and §7.2 — 46 files; copy name, severity, min level, requires_enemy, max stacks, rule text and counter-play text verbatim; express the rule as `modifiers[]` where a stat exists, else `"script": true`. (b) one `content/upgrades/<id>.json` per row of §8 — 36 files; plus `data/upgrade_pools.json` (brackets 1, 2–3, 4–9, 10–17, 18–25, 26+; level 1 = exactly paycheck, more, yearn_for_speed; each later bracket = all upgrades whose tier has entered the pool) and `data/economy.json` (every number in DESIGN.md §3.2, §7 system, §8 system). (c) `data/tips.json` with 18 tips (≥ 8 tagged `hazard_tell`, written from DESIGN.md §3.3 and §5 facts only), `data/player.json`, `data/palette.json` (TERRAIN_SPEC §12.2) and the 5 `content/biomes/*.json` (DESIGN.md §10).
Done-when: counts exact (46 / 36 / 18 / 5); a script proves every table row has a file and every numeric field equals the table.

**T-015 — Blender-procedural models**
THE OWNER'S SPEC: "the Blender-procedural .glb policy (headless scripts as source of truth, .glb as build artifacts, no downloaded assets) applies to everything else (terrain, props, environment models)."
Assignment: spawn (model:opencode/opencode/inkling-2-small-free) for the Blender install + export runs; spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash) for the scripts.
Read: TERRAIN_SPEC.md §12; DESIGN.md §3.3, §11.
Do: install portable Blender into `tools/blender/` (gitignored, pin version in `tools/blender/VERSION.txt`); `assets_src/blender/*.py`, each run as `blender --background --python <script> --python-exit-code 1`, exporting to `game/assets/models/`: black gift, gold gift, tripmine box (black frame, six-pointed star), beacon (closed/open share one mesh), altar plinth, descent gate, urn, barrel, tall jar, launch pad, player figure (blocky, 1.8 u). Box-and-wedge voxel style only, vertex colours from the palette. `tools/build_models.ps1` rebuilds all.
Done-when: 11 `.glb` files load headless in Godot; each ≤ 2,000 triangles; rebuild is byte-stable twice in a row. If Blender cannot be installed: build the same models as GDScript box meshes in `view/proc_models.gd`, list them in TBD.md, verdict PARTIAL.

**T-016 — Enemy sprite pipeline**
THE OWNER'S SPEC (ENEMIES.md HARD RULES, verbatim): "BILLBOARDING: all PNG enemies always face the player — the sprite is rendered on the client, rotating to face the viewer at all times (like Evade-style entities on Roblox). Enemies are never seen edge-on or from the side; there is no "side" of a PNG enemy." "HITBOXES: an enemy's hitbox covers ONLY the actual body/person/object in the PNG — never the image file's transparent padding, corners, or margins. If the PNG is 512×512 but the cat occupies 300×400, the hitbox is the cat." "TRANSPARENCY: every PNG asset must have a fully transparent background — no white/colored squares or padding may ever render around a model. Validate each asset in a test scene against the game's fog and palette." "TBD FALLBACK: if any agent refuses or is blocked from adding a specific enemy/name/asset (e.g. a copyrighted character), it must NOT stall the ticket — immediately proceed with name "TBD" and a placeholder TBD PNG, wire the full behavior, and mark the entry TBD for later replacement. The run never stops for a refusal." Also: "PNG frames are committed as build artifacts with their sources documented".
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: ENEMIES.md (all), DESIGN.md §5 intro.
Do: `game/tools/sprite_pipeline.gd` (headless, Godot `Image`): for each of the 17 source files in `assets_src/enemies/` — referenced by number AND exact filename: Image 1 = "kiwicat.png", Image 2 = "springer.png", Image 3 = "thiccben.png", Image 4 = "isagi_idle.jpeg", Image 5 = "ISAGI_SHOOT.webp", Image 6 = "blueballprojectile.webp", Image 7 = "NUKE.jpeg", Image 8 = "character to be corrupted.png", Image 9 = "tripine.png", Image 10 = "toucher.jpeg", Image 11 = "glitchedground.jpeg", Image 12 = "babehseal.webp", Image 13 = "address me elephant.png", Image 14 = "explosionsffect.jpg", Image 15 = "claudelogo.png", Image 16 = "gin idle.png", Image 17 = "ginsword.png" — load, convert to RGBA PNG, remove the background (flood-fill from the four corners with colour tolerance 24/255; skip if the corners are already alpha 0), crop to the body, fit into a power-of-two canvas ≤ 512, write `content/enemies/<id>/sprites/<name>_NN.png`; build multi-frame animations from one base + overlays exactly as ENEMIES.md lists (coil 5 squash→extend, nuke 4 flame, YOU?! 5 corruption flicker, gift Larper 5 rotation/pulse, toucher finger 3 + floor 5, seal dash frames, address me 2, Claude plushie 3 idle, Isagi idle/wind-up flash/shoot, gin idle/launch); write `sprites.json` (frames, fps, `body_rect` = tight bbox of alpha > 16 per frame, world height) and `SOURCES.md` per enemy. `game/tools/validate_sprites.gd`: four corners alpha 0, no opaque 1-px border, ≥ 15% transparent pixels, fog contrast ≥ 3.0 at 40 u (TERRAIN_SPEC §12.3). `game/tools/make_tbd_png.gd`: 256×256 transparent PNG with a magenta "TBD" block body. **If a source file is missing, unreadable, fails validation after background removal, or the agent will not process it: emit the TBD PNG for that enemy's frames, set `"tbd": true`, add a TBD.md row, continue.** The clawd Crab plushie sprite source is the URL in ENEMIES.md; if it cannot be fetched → TBD.
Done-when: 12 `content/enemies/<id>/sprites.json` exist; `validate_sprites.gd` exits 0; TBD.md accurate.

### WAVE 2 — the loop (parallel after Wave 1 merges)

**T-020 — Gifts, slots, beacon, straggler beam**
THE OWNER'S SPEC: "1. You spawn into the level at the BEACON, which is closed (not open yet). 2. Collect all black gifts in the level. 3. When all black gifts are collected, the beacon OPENS. Now the player chooses: enter the beacon and complete the level immediately, OR stay and collect GOLD gifts for extra currency — gold gifts spawn in EXACTLY the same positions the black gifts occupied. … 5. Enter the beacon → level completed." "GOLD GIFT RULE (canon): gold gifts replace exactly the same positions as the black gifts. The level's gift slots are persistent positions — black first, then gold in the identical spot." "Straggler highlight beam marks the last 20% of REAL gifts only; hazards are never highlighted and never count toward remaining-gift totals."
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: TERRAIN_SPEC.md §6.1, §6.7; DESIGN.md §3.
Do: `sim/gifts.gd` (two bitsets by slot id; pickup radius from stats; positions ONLY from `Level.gifts` — no placement code may exist), `sim/beacon.gd` (CLOSED/OPEN, trigger cylinder r 1.5 h 3; on entry restore exactly 1 void charge capped at 2 and restore the Subspacial Barrier shield), level-complete event, straggler rule; views for gifts/beacon/beam; `tests/test_gifts.gd` (A5).
Done-when: A5 green on 100 seeds; grep proves no code outside `terrain/` computes a gift position; beacon entry restores exactly 1 charge (0→1, 1→2, 2→2) and never more.

**T-021 — Tripmines (gift Larper), counter-play, death attribution**
THE OWNER'S SPEC: "Tripmines: fake-gift hazards — black framed box, six-pointed star center, constant pink particles, slow rotation, glows like a normal gift at distance but visibly wrong up close. Spawn beyond Level 5. Per-gift-slot replacement chance: 1/20 at Level 5 → 1/10 at Level 25, linear between, HARD-CAPPED at exactly 1/10 forever after; a "More Tripmines"-style curse option may add flat extra mines but must never raise the per-slot chance. Total replacement fraction hard-capped at ~20%." "GIFT-DENSITY INVARIANT (load-bearing): the player must always be collecting real gifts — any mechanic that starves the level of real gifts fails the harness." "Counter-play upgrades: Defuse Kit (survive first contact, documented cooldown) and Subspacial Barrier (periodic/chance blast protection); tripmine blasts do not pierce shields." "Death attribution: every death shows its killer (e.g. "Tripmine") and has its own death codes." "Hazard spawn rule: hazards that replace gifts inherit validated gift spawn positions — never their own placement logic." ENEMIES.md: "Behavior (1:1): stationary hazard, same as Nullscape — detonates when triggered by a player stepping on it." + the HARD RULES of T-016.
SUPERSEDED BY D-051: the Defuse Kit is a stacking 20%/stack chance (cap 60%) that a tripmine defuses instead of killing, rolled deterministically as `mix(mix(run_seed, level), slot_id) mod 100 < 20 × stacks`; the Subspacial Barrier is 1 shield per level (restored on beacon entry) that absorbs exactly one tripmine and nothing else — nothing blocks the nuke.
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: DESIGN.md §3.1, §3.3, §5.7; TERRAIN_SPEC.md §6.8, §3 (the `mix` function).
Do: `content/enemies/gift_larper/` (enemy.json: each vote → `extra_mines += 3`; enemy.gd), mine entity from `occ == 1` slots only, tell distance 12 u, blast r 3 **kills**, **contact = the player's centre within 0.9 u (horizontal distance) of the box at ANY height — jumping over a mine does not avoid contact; a tripmine is a wall on its tile and the walkable bypass (a route that stays outside the mine's 0.9 u trigger cylinder) is the only way past**, the contact ladder of DESIGN.md §3.3 in this fixed order (defuse roll → Subspacial Barrier shield → Last Light → death), `sim/death.gd` (killer + death codes; the killer is the last thing that killed the player; a void fall is its own killer, `D-VOID`), run-over screen data; `tests/test_mines.gd` (A6) including the determinism test: same seed + same slot id → same outcome on 1,000 seeds, and the observed defuse rate within ±2 points of 20/40/60% at 1/2/3 stacks; **kill tests run with Last Light already spent** (D-057).
Done-when: A6 green; 5,000-seed harness still green.

**T-022 — Economy, chain, overtime, shop logic**
THE OWNER'S SPEC: "Upgrades can influence how much currency 1 gold gift gives (economy upgrades)." "UPGRADE POOLS (canon): the shop never shows the full catalog — each level has its own curated, affordable pool. Example Level 1 pool: Paycheck (+25 currency when you enter the beacon), More (10% more gift yield), Yearn for Speed (10% more speed) — cheap, foundational options. Expensive upgrades are not shown until the player can meaningfully buy them; the pools are data-driven per level and extend the OFFERING SCHEDULE." "Some upgrades stack (repeated purchases)."
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: DESIGN.md §3.2, §8; `data/economy.json`.
Do: `sim/economy.gd` (integer centi-gold; base 2.00; chain +0.05/4.0 s/cap 2.00; the chain resets on a missed window, a void fall, a defused or shielded tripmine, and thicc ben's eject; stipend 10+2L; overtime tier every 20 s max 8), `sim/offers.gd` shop draw (pool by level, tier min level, affordability `price ≤ max(2×purse, 80)`, stack pricing ×1.5^n, class weighting, reroll 15 g rising), seeded; `tools/economy_audit.gd` (A11).
Done-when: A11 green; level-1 shop offers exactly the three canon upgrades on 100 seeds; a test asserts all four chain-reset events and that nothing else resets the chain.

**T-023 — The Antechamber (lobby) and offering schedule**
THE OWNER'S SPEC: "INTERMISSION (canon): after entering the beacon, the intermission is a PHYSICAL LOBBY you walk around in — not a vote screen. Mini altars stand in the lobby; each altar exhibits one option: an enemy shown off as its PNG sprite model with a description, or a curse, or an upgrade. The player walks up to an altar and presses F to select it." "VOTING RULES (canon): enemies can be voted/selected multiple times — select an enemy 5 times and there will be 5 enemies in play. Some upgrades stack (repeated purchases). Curse/enemy/upgrade votes do NOT happen every intermission — they follow the OFFERING SCHEDULE". "The schedule is data-driven — one tunable file."
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: DESIGN.md §6, §7 system, §11; `data/offering_schedule.json`.
Do: `view/lobby/antechamber.gd` builds the hall by script (dimensions, bays, banners, altars, plinths, gate, About plaque — all from DESIGN.md §11); `sim/offers.gd` enemy draw (min level, max votes, starter pool, "Hunger" fallback) and curse draw (gating, requires_enemy, pool removal, stacks, ≥ 1 Mild, bounty, tithe, free reroll); selections are sim inputs (`Select`); gate opens when mandatory bays are resolved; pre-run lobby with CLASS + E; `tests/test_lobby.gd` (A9), `tests/test_schedule.gd` (levels 0–40 produce the bays of DESIGN.md §6 including the 25–30 repeat).
Done-when: A9 green; changing one entry in the JSON changes the lobby with no code edit (test does this).

**T-024 — Loading screen, menu, About**
THE OWNER'S SPEC: "Loading screen: shown on initial load and run start; ~5s minimum display (holds at 5s if load is faster, shows real progress if slower); doubles as onboarding via a rotating, data-driven tip pool (15+ tips, prioritizing gift-vs-hazard tells)." ENEMIES.md: "DISCLAIMER (required in README + about screen)".
Assignment: spawn (model:opencode/opencode/inkling-2-small-free)
Read: DESIGN.md §2, §14.
Do: `app/loading_screen.gd` (min 5.0 s, real progress beyond, tip rotation every 5 s, `hazard_tell` weight ×3), `app/menu.gd` (Play / Settings / About / Quit), About text = the disclaimer verbatim; `tests/test_loading.gd` (fast load → exactly ≥ 5.0 s; simulated 7 s load → 7 s with progress), `tests/test_disclaimer.gd` (A15).
Done-when: both tests green.

**T-025 — HUD**
THE OWNER'S SPEC: "Death attribution: every death shows its killer". "Straggler highlight beam … never count toward remaining-gift totals."
Assignment: spawn (model:opencode/opencode/inkling-2-small-free)
Read: DESIGN.md §14 HUD, §3.
Do: `view/hud/` exactly the elements listed in DESIGN.md §14 (including the **void charge pips**: one pip per holdable charge — 2, or 1 under Hungry Void — filled = held, hollow = spent); run-over screen (killer, death code, level, purse).
Done-when: `tests/test_hud.gd` — counter shows `collected / REAL total` (mines excluded) on a level-25 seed; the pip row shows 2 pips at 2 charges, 1 filled + 1 hollow at 1 charge, 2 hollow at 0, and exactly 1 pip under Hungry Void.

**T-026 — Walker bot and playthrough harness**
THE OWNER'S SPEC: "Target: runs overnight via multi-agent fleet, so every instruction must be executable without human decisions." (Retro: "the bot … is the only end-to-end proof the game works".)
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: TERRAIN_SPEC.md §5 (use the SAME movement graph — port the validator's graph builder into `game/tools/bot/graph.gd`; jump envelope = VALIDATOR limits, never narrower: retro §4e). Also TERRAIN_SPEC.md §1A: walkways are 1–2 cells wide and step by 1–2 HU, so the bot must handle 1-wide corridors and 1-HU walk edges.
Do: `tools/bot_run.gd`: nearest-real-gift routing over the movement graph, executes walk/jump/drop/pad edges through real `PlayerInput`s into the real sim at max speed; CLI `--seeds A:B` (runs seeds A..B−1), `--dodge` (reacts to telegraph events after 15 ticks; off by default), `--enemy <id>` (pins the level-1 starter enemy; default = the pre-run vote), `--class <id>`; every run starts with Last Light unspent and 2 void charges held (A3's state); returns to the beacon; records inputs for replays (feeds A4); prints `BOT seed level result ticks gifts deaths killer`.
Done-when: A3 green with `bot_run.gd --seeds 0:100 --dodge --enemy kiwi_cat`; A4 green.

**T-027 — Enemy framework**
THE OWNER'S SPEC: ENEMIES.md HARD RULES (BILLBOARDING, HITBOXES, TRANSPARENCY, TBD FALLBACK — verbatim text in T-016) and "All enemies stay server-sided … apart from gin ichimaru and his spears (spears included): rendered on the client, never the server."
Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash)
Read: DESIGN.md §5 intro, §12 Enemy API; TERRAIN_SPEC.md §6.5 anchors.
Do: `sim/enemy_runtime.gd` (EnemyBehavior base, per-enemy rng stream, spawn rule 6 s / the fallback order of DESIGN.md §5 (preferred kind → `lane` → any round-trip tile ≥ 25 u from spawn; tie-break farthest from the player, then lowest index) / ≥ 25 u from the player, vote counts, overtime multipliers, telegraph events, projectiles, `api.los` via tile/prop ray, and the **kill API**: `api.kill(player, killer_id)`, `api.push(player, dir, speed)`, `api.lock_abilities(player, ticks)` — there is no partial-effect call, an enemy either kills or applies a non-killing effect), `view/billboard.gd` (Y-billboard material facing the camera every frame, alpha-scissor 0.5, nearest filter, frame animation from sprites.json), hit cylinder from `body_rect` (diameter 0.8 × body width), diegetic spawn text; `tests/test_hitbox.gd` (A7 hitbox clause: a probe inside the PNG rect but outside body_rect never hits), `tests/test_billboard.gd` (sprite normal · camera forward ≤ −0.999 from 8 camera angles), `tests/test_kill_api.gd` (a body contact kills; a push does not; respawn invulnerability suppresses the kill; **kill tests run with Last Light already spent** — otherwise the save masks the kill, D-057).
Done-when: all three tests green with the fixture enemy.

### WAVE 3 — the 12 enemies (parallel after T-027 + T-016; one ticket each)

Every ticket T-030…T-041 carries this block verbatim —
THE OWNER'S SPEC (applies to every enemy ticket ever written): ENEMIES.md "🔒 Hard rules (owner-set, never negotiable)": BILLBOARDING, HITBOXES, TRANSPARENCY, DISCLAIMER, TBD FALLBACK (full text in T-016), plus that enemy's own section of ENEMIES.md copied verbatim (Behavior (1:1), New sound, Model, Animation, Attached PNGs with image number + exact filename).
Read: ENEMIES.md (its section), DESIGN.md §5.x (its numbers), §12.
Do: `content/enemies/<id>/enemy.json` + `enemy.gd`, view (frames, telegraph VFX), placeholder audio hooks named per its "New sound" line, `tests/test_enemy_<id>.gd` asserting every timing/number of its DESIGN.md §5.x paragraph within ±1 tick, that its body contact kills (thicc ben: that it never kills — blur 3.0 s + 18 u/s eject, and a launch into the void reports `D-VOID`), and its death code (thicc ben has none). **Kill tests run with Last Light already spent** (D-057): a kill assertion is only valid when the save cannot fire.
Done-when: its test green; sprite validator green for its frames; lobby exhibit shows it; if anything about its name/art is refused → TBD fallback, verdict PARTIAL, never BLOCKED.

| ticket | enemy | DESIGN | assignment |
|---|---|---|---|
| T-030 | kiwi cat — Image 1 = "kiwicat.png" | §5.1 | spawn (model:opencode/opencode/inkling-2-small-free) |
| T-031 | coil — Image 2 = "springer.png" | §5.2 | spawn (model:opencode/opencode/inkling-2-small-free) |
| T-032 | thicc ben — Image 3 = "thiccben.png" | §5.3 | spawn (model:opencode/opencode/inkling-2-small-free) |
| T-033 | Isagi — Image 4 = "isagi_idle.jpeg", Image 5 = "ISAGI_SHOOT.webp", Image 6 = "blueballprojectile.webp" | §5.4 | spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash) |
| T-034 | nuke — Image 7 = "NUKE.jpeg" | §5.5 | spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash) |
| T-035 | YOU?! — Image 8 = "character to be corrupted.png" | §5.6 | spawn (model:opencode/opencode/inkling-2-small-free) |
| T-036 | gift Larper — Image 9 = "tripine.png" (view + exhibit only; logic is T-021) | §5.7 | spawn (model:opencode/opencode/inkling-2-small-free) |
| T-037 | toucher — Image 10 = "toucher.jpeg", Image 11 = "glitchedground.jpeg" | §5.8 | spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash) |
| T-038 | seal — Image 12 = "babehseal.webp" | §5.9 | spawn (model:opencode/opencode/inkling-2-small-free) |
| T-039 | address me — Image 13 = "address me elephant.png", Image 14 = "explosionsffect.jpg" | §5.10 | spawn (model:opencode/opencode/inkling-2-small-free) |
| T-040 | Claude — Image 15 = "claudelogo.png" + clawd Crab plushie | §5.11 | spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash) |
| T-041 | gin ichimaru — Image 16 = "gin idle.png", Image 17 = "ginsword.png" (spears = view-layer VFX only; void zone = sim) | §5.12 | spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash) |

### WAVE 4 — content breadth (parallel)

**T-050 — Curses, declarative batch** · THE OWNER'S SPEC: "Curses: gated by minimum level; some only appear if their associated enemy is present in the run; picking a curse removes it from the pool; some stack." · Assignment: 2× spawn (model:opencode/opencode/inkling-2-small-free) (split the list in half) · Do: every curse JSON with `"script": false` works through modifiers only; `tests/test_curses_decl.gd` applies each and asserts the stat delta from its table row · Done-when: test green; DESIGN.md §7 safety rule asserted (no curse changes jump velocity/gravity; total run-speed reduction ≤ 10%; the glitched floor's −20% is an enemy effect and is excluded from that budget, asserted explicitly); no curse touches `void_charges_max` except Hungry Void (cap 1).

**T-051 — Curses, scripted batch** · THE OWNER'S SPEC: "Build an enemy-linked curse family around my fixed 12-enemy roster." · Assignment: 2× spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash) (enemy-linked / general) · Do: `content/curses/<id>.gd` for every `"script": true` curse, using hooks/API only; one test per curse asserting its rule sentence · Done-when: tests green; boundary scan clean; Understudies/gift Larper mines never exceed the 20% cap (assert on 1,000 seeds with max stacks); The Long Toll's second ben arrival lands at the same locked point 1.5 s after the first and never kills.

**T-052 — Upgrades, declarative batch** · THE OWNER'S SPEC: "some stack (e.g. +10% speed per stack, capped); some are information tools (radar/arrow to gifts), some are protection (block one hit, recharge), some are economy/mobility/utility."
SUPERSEDED BY D-051: protection is now tripmine-only and does not recharge on a timer — the Subspacial Barrier is 1 shield per level restored on beacon entry, and the Defuse Kit is a deterministic 20%/stack defuse chance (cap 60%).
· Assignment: 2× spawn (model:opencode/opencode/inkling-2-small-free) · Do/Done-when: as T-050 for upgrades; Athletic multipliers (speed ×1.5, air-jump height ×1.3) asserted.

**T-053 — Upgrades, scripted batch (radar family, barriers, class-only, Cartographer, Skeleton Key, Pocket Beacon)** · THE OWNER'S SPEC: "Radar modules exist (an upgrade family), including one that detects disguised tripmines." · Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash) · Done-when: one test per upgrade; Radar Module: Mines outlines only `occ == 1` slots within 14 u; Defuse Kit and Subspacial Barrier tests assert the §3.3 resolution order verbatim: 1. **Defuse roll** (Defuse Kit, §8): `roll = mix(mix(run_seed, level), slot_id) mod 100`; if `roll < 20 × stacks` (cap 60) the mine is **defused** — it is consumed, there is no blast and no death, and the chain resets. With 0 stacks the roll can never pass. 2. **Subspacial Barrier** (§8): if a shield is held, the shield is consumed and the mine is consumed with no blast; the chain resets. 3. **Last Light** (§3.1): if it is unspent and the player holds at least 1 void charge, it is spent as the final save (teleport to the beacon dais); the mine is consumed. 4. Otherwise the player is **killed** (`D-MINE`). The order is fixed: defuse roll, then Subspacial Barrier shield, then Last Light (D-053). The roll is deterministic (`mix(mix(run_seed, level), slot_id) mod 100 < 20 × stacks`, cap 60) and nothing absorbs the nuke.

**T-054 — Biomes** · THE OWNER'S SPEC: "biome/level variety plan" (DESIGN.md §10) + fog-readability canon · Assignment: spawn (model:opencode/opencode/inkling-2-small-free) · Do: wire act → biome; run `fog_check.gd` for all 5; if a biome fails, adjust ONLY that biome's light colours upward in lightness until it passes and record the new hex in DECISIONS.md · Done-when: 5/5 pass; 5 screenshots.

**T-055 — Placeholder audio** · THE OWNER'S SPEC (ENEMIES.md): "All sounds are brand-new — nothing is copied from Nullscape audio. Each enemy keeps its 1:1 behavior and cue timing (wind-up, warning, cooldown), but the audio itself is redesigned to match the new PNG model". · Assignment: spawn (model:opencode/opencode/inkling-2-small-free) · Do: `tools/synth_audio.py` (stdlib `wave` + math) synthesises one distinct placeholder `.wav` per cue named in each enemy's "New sound" line (file names = cue names), no downloaded or recorded audio; cue timings are driven by sim telegraph events, not by audio length · Done-when: every cue referenced in `content/enemies/*/enemy.json` resolves to a file; list in TBD.md that all audio is placeholder.

**T-056 — Windows export** · THE OWNER'S SPEC: "it ships as its own standalone native .exe" · Assignment: spawn (model:opencode/opencode/inkling-2-small-free) · Do: install the matching 4.7.2 export templates (official GitHub release, into the user templates folder), `game/export_presets.cfg` "Windows Desktop" (embed pck = on), export to `build/voidwrap_run.exe`, smoke run · Done-when: A1.

### WAVE 5 — tuning probes and the gate

**T-060 — Difficulty band probe** · Assignment: spawn (model:opencode/opencode/inkling-2-small-free) · Do: run `bot_run.gd --dodge` for 200 runs with seeded random votes; report reach-rates for levels 6/12/18 against DESIGN.md §9 bands. Report only — tuning changes are proposed in the response, applied by the orchestrator as a follow-up ticket touching `content/enemies/*/enemy.json` only.

**T-061 — Feel and perf probes** · Assignment: spawn (model:acpRegistry_mistral_vibe/zai-glm-5-3-flash) · Do: `tools/feel_probe.gd` (A12), `tools/perf_probe.gd` (A13) · Done-when: both print PASS/FAIL per row with numbers.

**T-099 — FINAL CONFORMANCE AUDIT (gate before alpha)**
THE OWNER'S SPEC: "a final audit ticket as conformance gate before alpha." And the tonal pillar: "the ENEMIES are silly, the WORLD is serious."
Assignment: spawn (model:acpRegistry_mistral_vibe/deepseek-v4) in a fresh thread, read-only except `AUDIT.md`.
Do: on `main`: run every command of §4 including the 5,000-seed harness and the export; evaluate A1–A16 one by one with pasted evidence; verify each canon line of the owner's VOIDWRAP_CANON list against code/tests (one row per canon bullet: file + test that proves it, or MISSING); verify the 12-enemy roster against ENEMIES.md name by name (TBD entries listed, never silently renamed); verify no core file names a content id; verify the disclaimer in README and About; **grep `DESIGN.md`, `FLEET_PACK.md`, `README.md` and `game/data/` for the retired vocabulary listed in DECISIONS.md D-052 (case-insensitive) and report every hit — the only allowed hits are lines beginning `SUPERSEDED BY` and verbatim owner quotes in FLEET_PACK.md**; list every `[CONTESTABLE]` added during the run; list retro defect classes checked (threshold moved to fit data? dead time > budget? gift inside geometry?).
Done-when: `AUDIT.md` exists with a verdict per criterion. Alpha tag `v0.1.0-alpha.1` is created ONLY if A1–A16 all pass; otherwise the orchestrator files fix tickets and re-runs T-099. A failing audit is a correct outcome; a softened one is not.

## 7. Merge order

1. T-001 → T-002 (main must be green before anything else starts).
2. Wave 1 in this order when ready: T-013, T-010, T-012, T-011, T-014a/b/c, T-016, T-015.
3. Wave 2: T-027, T-020, T-021, T-022, T-023, T-026, T-024, T-025.
4. Wave 3: T-030…T-041 in numeric order (each only adds `content/enemies/<id>/` + one test → no conflicts).
5. Wave 4: T-050, T-052, T-051, T-053, T-054, T-055, T-056.
6. Wave 5: T-061, T-060, T-099.

Before each merge: rebase on main, run `tools\gate.ps1`. A red gate after rebase goes back to the same
worker with the failing output. Two tickets touching the same file never run in parallel — the
boundaries in §3 were drawn so this only happens for `core/stats.gd` (append-only; resolve by keeping
both lines).

## 8. Suggested parallelism for the night (stays inside the budget)

| phase | running at once |
|---|---|
| Wave 0 | 1 GLM, then 1 Inkling |
| Wave 1 | 3 GLM (T-010, T-011, T-012 → then T-013, T-016, T-015 scripts) + 4 Inkling (T-014a/b/c, Blender install) |
| Wave 2 | 3 GLM rolling (T-027, T-020, T-021 → T-022, T-023, T-026) + 2 Inkling (T-024, T-025) |
| Wave 3 | 3 GLM (T-033, T-034, T-037 → T-040, T-041) + 7 Inkling (T-030, T-031, T-032, T-035, T-036, T-038, T-039) |
| Wave 4 | 3 GLM (T-051 ×2, T-053) + 7 Inkling (T-050 ×2, T-052 ×2, T-054, T-055, T-056) |
| Wave 5 | 1 GLM + 1 Inkling, then 1 DeepSeek (audit) |

One DeepSeek V4.1 thread orchestrates throughout (if Opus 5.5 orchestrates instead, DeepSeek is used
only for T-099).

## 9. After run 1 (not tonight)

Real audio design; multiplayer transport; more modes via `content/modes/`; gimmick drop-ins
(DESIGN.md §10); terrain archetype pack 2 (GEN_VERSION 2, Python oracle first).

## 9A. Tickets added by the ticket-completeness pass (2026-11-16)

Appended, not merged into §6: the tickets of §6 are unchanged. Full specs, the standing clause, the
animation tables, VFX tables, sound briefs and the dispatch addenda are in research/fable-tickets.md.
Enemy-system reasoning is in research/fable-enemies.md; fun signals in research/fable-funrisks.md.

[CONTESTABLE] notes instead of edits (things in earlier sections this pass would change but did not):
- §1 says a ticket that fails twice on Inkling is re-dispatched once to GLM. The owner's budget rule
  for tonight (§10, rule R2) says an Inkling ticket never goes to GLM. §10 wins tonight.
- §7 lists the merge order without the tickets below; §10 gives the complete order.
- T-001 says "first commit on main". Two commits already exist (ab471d8, 14be164); T-001 commits on top.
- §9 says "terrain archetype pack 2 (GEN_VERSION 2 …)". The generator is already at version 3.
- §2's table says the selftest is 5/5 in places written before the terrain changes; it is 15/15.

| ticket | title | assignment | spec |
|---|---|---|---|
| T-070 | Enemy systems fix (15 rules incl. the owner's Isagi and nuke rulings; answerability criterion) | spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash | fable-tickets.md §5 |
| T-071 | Floater kinematics, pursuit ceilings, stagger, ranged limits | spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash | fable-enemies.md §6 + fable-tickets.md §5 |
| T-072 | Scheduling arbiter and class ability lock | spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash | fable-enemies.md §6 |
| T-073 | Enemy data pass | spawn model:opencode/opencode/inkling-2-small-free | fable-enemies.md §6 |
| T-074 | Offer draw: NEW / REPEAT / FREE altars, caps, chaser ceiling | spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash | fable-enemies.md §6 |
| T-075 | Answerability harness | spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash | fable-enemies.md §6 |
| T-076 | Counter-play text: lobby panels and tips | spawn model:opencode/opencode/inkling-2-small-free | fable-enemies.md §6 |
| T-080 | Telemetry event log | spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash | fable-tickets.md §5 |
| T-081 | Fun-risk signals (eight; terrain-caused vs enemy-caused first) | spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash | fable-tickets.md §5 |
| T-082 | Camera, key bindings, settings | spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash | fable-tickets.md §5 |
| T-083 | Enemy animation data (two workers: enemies 1–6, 7–12) | 2× spawn model:opencode/opencode/inkling-2-small-free | fable-tickets.md §1, §5 |
| T-084 | Animation player and telegraph sync | spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash | fable-tickets.md §1.0, §5 |
| T-085 | VFX pack: tripmine, glitched floor, beacon, respawn | spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash | fable-tickets.md §2, §5 |
| T-086 | HUD: charge pips, Last Light icon, death attribution screen | spawn model:opencode/opencode/inkling-2-small-free | fable-tickets.md §2.4, §5 |
| T-087 | Audio cues | spawn model:opencode/opencode/inkling-2-small-free | fable-tickets.md §3, §5 |
| T-090 | Backlog: cross-ticket bug review | spawn model:acpRegistry_mistral_vibe/deepseek-v4 | fable-tickets.md §5 |
| T-091 | Backlog: dead vocabulary sweep | spawn model:opencode/opencode/inkling-2-small-free | fable-tickets.md §5 |
| T-092 | Backlog: validator selftest expansion | spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash | fable-tickets.md §5 |
| T-093 | Backlog: determinism fuzz | spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash | fable-tickets.md §5 |
| T-094 | Backlog: loading tip pool | spawn model:opencode/opencode/inkling-2-small-free | fable-tickets.md §5 |
| T-095 | Backlog: README and HOW-TO-PLAY | spawn model:opencode/opencode/inkling-2-small-free | fable-tickets.md §5 |
| T-096 | Backlog: death attribution edge cases | spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash | fable-tickets.md §5 |

## 10. OVERNIGHT RUN PLAN — the orchestrator executes this section literally

You are the orchestrator: DeepSeek V4.1 (model:acpRegistry_mistral_vibe/deepseek-v4). You dispatch,
read responses, merge, run gates and keep the log. You do not implement. This plan was written by the
design lead and has not been executed by anyone. Start only after the owner has committed this pass.

### 10.1 Rules

R1. NO SILENT SKIPS. Every ticket ends in exactly one of two states, written in RUNLOG.md with the
    time: MERGED-GREEN (gate exit 0 after merge) or PARKED (a written reason: what failed, the output,
    what was tried). A ticket is never dropped, never marked done on a worker's word, never left
    without a line.
R2. BUDGET (owner-set). At most 10 parallel Inkling 2 Small, at most 3 GLM 5.3 Flash, at most 3
    DeepSeek V4.1 INCLUDING YOURSELF. Opus 5.5 only if absolutely necessary. Drain cheap models first:
    an Inkling ticket never goes to GLM; a GLM ticket never goes to DeepSeek unless GLM is fully
    saturated (3 GLM workers running and the ticket has waited more than 30 minutes). A ticket that
    fails twice on its model is split into two smaller tickets for the SAME model, or PARKED.
R3. DISPATCH EXACTLY AS WRITTEN. The brief of a ticket = its full text from §6 (or from
    research/fable-tickets.md §5 / research/fable-enemies.md §6 for the tickets of §9A) + the standing
    clause of research/fable-tickets.md §5 + rule R4's addenda + the repository path + "do not commit
    to main; commit on branch t/<ticket id>". Do not summarise, shorten or reinterpret a ticket.
R4. DISPATCH ADDENDA. research/fable-tickets.md §4 has a table of missing lines. When you dispatch a
    ticket named in that table, append each of its lines verbatim to the brief under the heading
    ADDENDA (numbers supplied by the design lead; build them as written).
R5. FROZEN. ENEMIES.md behavior sentences, the 12-enemy roster, D-025 and every FINAL decision. A
    worker that finds a contradiction parks it in PARKED.md; you do not resolve it either.
R6. GATE AFTER EVERY MERGE: rebase the ticket branch on main, run tools\gate.ps1, merge only on exit 0.
    A red gate goes back to the same worker with the failing output (counts as one failure, R2).
R7. TBD FALLBACK for any stalling name or asset (ENEMIES.md hard rule). The 17 enemy images may be
    missing from assets_src/enemies/: every missing one becomes a TBD placeholder; the run continues.
R8. Never push. Never commit tools/godot/ or .godot/. Never move a threshold. Never edit
    terrain_ref/voidgen.py or game/terrain/voidgen.gd tonight (no ticket in this plan needs to).
R9. RUNLOG.md: one line per event — time, ticket, model, event (DISPATCHED / RESPONSE / GATE exit code
    / MERGED-GREEN / PARKED + reason). Write the line before you act on the event.
R10. If you are interrupted, the next orchestrator resumes from the first ticket in §10.2 that has no
     MERGED-GREEN or PARKED line in RUNLOG.md.

### 10.2 MANDATORY — in this order; each one MERGED-GREEN or PARKED with a written reason

Within a step, tickets on one line may run in parallel (inside R2); merge in the order listed.
A step starts when every ticket of the previous step is MERGED-GREEN or PARKED.

STEP a — enemy systems fix (before any enemy code exists)
T-070 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
Standing criterion (owner): every rule must leave every enemy answerable in the counter-play map of
research/fable-enemies.md §4; a rule that fails is parked in PARKED.md with a written reason, not
applied. Check the response for one answerability line per rule before merging.

STEP b — every remaining FLEET_PACK ticket, in the merge order of §7 with the §9A tickets slotted in.
Existing tickets keep the model assignments written in §6.
b1  T-001 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-002 — spawn model:opencode/opencode/inkling-2-small-free
    (main must be green before b2)
b2  Wave 1, merge order: T-013, T-010, T-012, T-082, T-011, T-014a, T-014b, T-014c, T-016, T-015
    T-013 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-010 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-012 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-082 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-011 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-014a — spawn model:opencode/opencode/inkling-2-small-free
    T-014b — spawn model:opencode/opencode/inkling-2-small-free
    T-014c — spawn model:opencode/opencode/inkling-2-small-free
    T-016 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-015 (install and export runs) — spawn model:opencode/opencode/inkling-2-small-free
    T-015 (scripts) — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
b3  Wave 2, merge order: T-027, T-071, T-072, T-020, T-021, T-022, T-023, T-074, T-026, T-024, T-025, T-086
    T-027 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-071 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-072 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-020 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-021 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-022 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-023 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-074 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-026 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-024 — spawn model:opencode/opencode/inkling-2-small-free
    T-025 — spawn model:opencode/opencode/inkling-2-small-free
    T-086 — spawn model:opencode/opencode/inkling-2-small-free
b4  Wave 3, merge order: T-083, T-084, then T-030 to T-041 in numeric order
    T-083 (enemies 1 to 6) — spawn model:opencode/opencode/inkling-2-small-free
    T-083 (enemies 7 to 12) — spawn model:opencode/opencode/inkling-2-small-free
    T-084 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-030 — spawn model:opencode/opencode/inkling-2-small-free
    T-031 — spawn model:opencode/opencode/inkling-2-small-free
    T-032 — spawn model:opencode/opencode/inkling-2-small-free
    T-033 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-034 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-035 — spawn model:opencode/opencode/inkling-2-small-free
    T-036 — spawn model:opencode/opencode/inkling-2-small-free
    T-037 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-038 — spawn model:opencode/opencode/inkling-2-small-free
    T-039 — spawn model:opencode/opencode/inkling-2-small-free
    T-040 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-041 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    (If T-070 was PARKED in whole: dispatch the enemy tickets anyway with research/fable-enemies.md
    F1 and F2 as ADDENDA, and write that in RUNLOG.md.)
b5  Wave 4, merge order: T-073, T-050, T-052, T-051, T-053, T-054, T-055, T-087, T-085, T-076, T-056
    T-073 — spawn model:opencode/opencode/inkling-2-small-free
    T-050 (two halves) — spawn model:opencode/opencode/inkling-2-small-free
    T-052 (two halves) — spawn model:opencode/opencode/inkling-2-small-free
    T-051 (enemy-linked) — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-051 (general) — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-053 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-054 — spawn model:opencode/opencode/inkling-2-small-free
    T-055 — spawn model:opencode/opencode/inkling-2-small-free
    T-087 — spawn model:opencode/opencode/inkling-2-small-free
    T-085 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-076 — spawn model:opencode/opencode/inkling-2-small-free
    T-056 — spawn model:opencode/opencode/inkling-2-small-free
b6  Wave 5 without the audit, merge order: T-075, T-061, T-060
    T-075 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-061 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    T-060 — spawn model:opencode/opencode/inkling-2-small-free

STEP c — telemetry event log
T-080 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
Logs every death with killer, every void fall, every charge spent and restored, every bypass passed
within 0.5 u of a mine, per-level clear time (full record list: research/fable-tickets.md §5).

STEP d — fun-risk signals
T-081 — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
Wires the eight cheap signals of research/fable-funrisks.md; the first block of the report is
terrain-caused vs enemy-caused charges and deaths. The report is information, not a gate.

STEP e — full gate re-run, by the orchestrator itself, on main, before the audit. Every command must
exit 0; paste each final line into RUNLOG.md. If one fails: file one fix ticket to the model that
owns the failing area, merge it under R6, and run step e again from the top.
    python terrain_ref\test_validate.py
    python terrain_ref\validate.py --selftest
    python terrain_ref\gallery.py --check
    python terrain_ref\validate.py --seeds 0:5000
    tools\godot\godot.exe --headless --path game --script res://tests/test_terrain_parity.gd -- "<repo>\terrain_ref\gallery.json"
    powershell -File tools\gate.ps1
Expected final lines: TESTS OK · SELFTEST 15/15 · GALLERY 16/16 OK · 32 PASS lines and exit 0 ·
PARITY 56/56 OK · gate exit 0.

STEP f — final audit (the last mandatory ticket; it is part of step b's list and runs here)
T-099 — spawn model:acpRegistry_mistral_vibe/deepseek-v4 (fresh thread, read-only except AUDIT.md)
Give it RUNLOG.md, PARKED.md, TBD.md and T-081's report. The alpha tag is created only if A1 to A16
all pass. A failing audit is a correct outcome; a softened one is not.

### 10.3 [OPTIONAL-BACKLOG]

Claimable ONLY after every mandatory item of §10.2 (steps a to f) is MERGED-GREEN or PARKED with a
written reason. ONE AT A TIME, in this order. After each merge run the full gate of step e again.
Write the findings in RUNLOG.md even if they are empty ("T-09x: no findings").

T-090 Cross-ticket bug review — spawn model:acpRegistry_mistral_vibe/deepseek-v4
    Re-read all merged diffs; hunt contradictions between tickets and specs.
T-091 Dead vocabulary sweep — spawn model:opencode/opencode/inkling-2-small-free
    Zero hits for "damage", "HP", "rooms", "hop", "2 per level" across all docs and code (allowed
    exceptions listed in the ticket).
T-092 Validator selftest expansion — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    15 to 25+ planted defects, each provoking exactly one metric.
T-093 Determinism fuzz — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    10 fresh seeds generated 3 times each, byte-identical output; plus a slow 20,000-seed validator pass.
T-094 Loading tip pool — spawn model:opencode/opencode/inkling-2-small-free
    30 tips, one per death attribution screen, each true in the current build.
T-095 README and HOW-TO-PLAY — spawn model:opencode/opencode/inkling-2-small-free
    Rewritten to match charges, instakill, beacon restore.
T-096 Death attribution edge cases — spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
    Every killer name renders, no orphan death codes.

### 10.4 What the owner should find in the morning

RUNLOG.md (every ticket with a final state), PARKED.md (every contradiction and every parked rule),
TBD.md (every placeholder), AUDIT.md (A1 to A16 with evidence, T-081's report appended), and
build\voidwrap_run.exe if A1 passed. If the night ended early: RUNLOG.md shows the last ticket reached.
