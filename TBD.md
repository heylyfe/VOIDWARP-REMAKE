# TBD.md - every placeholder left in the build

ENEMIES.md hard rule (TBD FALLBACK): a missing name or asset never stalls the run. The behavior is
wired in full, the entry is marked `"tbd": true` in its JSON, and the row appears here.

| # | ticket | what is TBD | why | owner action |
|---|---|---|---|---|
| 1 | T-016 | kiwi cat sprites - REAL (T-ART-KIWI_CAT); `tools/art/kiwi_cat.gd` owns them | Image 1 `assets_src/enemies/kiwicat.png` present since the art wave | nothing - drop the module's rebuild output (`--script res://tools/art/kiwi_cat.gd`) if the source changes |
| 2 | T-016 | coil sprites - REAL ART (tools/art/coil.gd, 2026-11-17) | Image 2 `springer.png` present; opaque near-white checkerboard corners needed a per-enemy background removal (the shared 24/255 corner fill empties it) | done; rebuild = rerun `tools/godot/godot.exe --headless --path game --script res://tools/art/coil.gd` |
| 3 | T-016 | thicc ben sprites - REAL ART since 2026-11-17 | Image 3 `thiccben.png` present; cut out and graded by `game/tools/art/thicc_ben.gd` (art module owns the frames); distinct frame per T-083 anim-block state | none - done; rebuild via the art module, not the pipeline |
| 4 | T-016 | Isagi sprites - REAL ART (`tools/art/isagi.gd`, 2026-11-17) | Images 4/5/6 present since the art wave; the module removes the backgrounds and derives one frame per anim-block state | none - done; rebuild = rerun `tools/godot/godot.exe --headless --path game --script res://tools/art/isagi.gd` |
| 5 | T-016 | nuke sprites - real art (4/4 attack_descent frames) | `NUKE.jpeg` was present but the shared flood-fill pipeline could not eat its opaque white background; `game/tools/art/nuke.gd` (T-083 art pass) removes it with a border flood fill on distance-from-white and derives the four `attack_descent` burn-cycle frames from the base body | done; re-run `game/tools/art/nuke.gd` to regenerate; states with no frames in the T-083 block stay empty |
| 6 | T-016 | YOU?! sprites - REAL ART (`tools/art/you.gd`, 2026-11-17) | Image 8 present since the art wave; the module derives one frame per anim-block state | none - done; rebuild = rerun `tools/godot/godot.exe --headless --path game --script res://tools/art/you.gd` |
| 7 | T-016 | gift Larper sprites - REAL ART (tools/art/gift_larper.gd, 2026-11-17) | Image 9 `tripine.png` present (corners already alpha 0; near-black body needed an art-side grade to clear the fog rule) | done; rebuild = rerun `tools/godot/godot.exe --headless --path game --script res://tools/art/gift_larper.gd` |
| 8 | T-016 | toucher sprites - LANDED (T-ART): 17 real frames from `toucher.jpeg` / `glitchedground.jpeg` (all body states + 5 floor decals) | Images 10/11 landed via game/tools/art/toucher.gd | none - real art in game/content/enemies/toucher/sprites/; `"tbd": false` |
| 9 | T-016 | seal sprites - REAL ART (2026-11-17, `game/tools/art/seal.gd`) | Image 12 `babehseal.png` present (the owner replaced the source 2026-11-17: the webp photo was swapped for a transparent-background harp-seal pup render; exactly one source per enemy now). The old per-column-gradient cutout is gone - the alpha channel IS the matte (no flood fill, no defringe, no feather; the edge is already a ~10 px feather); tight crop + 512x512 bottom-anchored canvas; all five anim-block states ship distinct derived frames (telegraph = crouched wind-up, dash = lunge: stretch + low body + forward lean) | none - sealed (D-ART-SEAL-3) |
| 10 | T-016 | address me sprites - REAL ART (ART-ADDRESS_ME, 2026-11-17; owner ruling 2026-11-17, D-ART-ADDRESS_ME-5) | Images 13/14 (`address me elephant.png`, `explosionsffect.jpg`) turned into real art by `game/tools/art/address_me.gd`; the shared pipeline skips this enemy (it has an art module). The address me frame KEEPS the full office-interior photo (no background removal) per the owner's ruling; the explosion stays a cutout composited over the ghosted photo | none - landed; rebuild = rerun `tools/godot/godot.exe --headless --path game --script res://tools/art/address_me.gd` |
| 11 | T-016 | Claude sprites - REAL ART (tools/art/claude.gd, 2026-11-17) | Image 15 `claudelogo.png` present (clawd Crab plushie source unfetched -> plushie_00..02.png stay TBD) | done for the logo; rebuild = rerun `tools/godot/godot.exe --headless --path game --script res://tools/art/claude.gd` (accepts no args); plushie needs the sprite fetched (row 26) |
| 12 | T-016 / T-ART-GIN | gin ichimaru sprites - REAL ART (T-ART-GIN): `idle_00`, `spawn_00`, `telegraph_00`, `launch_00`, `recover_00` | Images 16/17 are present; the shared pipeline cannot cut the opaque sources, so `game/tools/art/gin.gd` owns the frames | none - re-run the module to regenerate; `attack_void_zone` keeps no frames by design (the void zone is VFX) |

## 2. Placeholder audio hooks (T-033)

| # | ticket | what is TBD | why | owner action |
|---|---|---|---|---|
| 1 | T-033 | isagi: `isagi_voice_direct_shot` - each burst's audio cue (ENEMIES.md Isagi "New sound": direct shot voice lines) | no audio files exist yet in the build | drop the hook file in, view wires it |
| 2 | T-033 | isagi: `isagi_shoot_sae_math_final_shot` - the shoot line per release (ENEMIES.md Isagi "New sound": Isagi shoot sae math final shot gun-shot sound) | no audio files exist yet | drop the hook file in, view wires it |
| 3 | T-033 | isagi: `isagi_gunshot` - per ball release, layered under the shoot line | no audio files exist yet | drop the hook file in, view wires it |

## 1. The 17 enemy images - 4 MISSING (coil, thicc ben, kiwi cat, isagi, YOU?!, toucher, gin, gift Larper, seal, the Claude logo and address me are real art since 2026-11-17; only the clawd Crab plushie and the four remaining source rows are still TBD)

Enemy sprites are normally produced by `game/tools/sprite_pipeline.gd` (T-016): missing, unreadable, or
validation-failing sources become `game/tools/make_tbd_png.gd` placeholder frames, `"tbd": true`
in `content/enemies/<id>/sprites.json`, and the rows below. Dropping the real PNG in with the
exact filename below and re-running the pipeline swaps the placeholder for real art with no code
change. Every frame is validated by `game/tools/validate_sprites.gd` (fog contrast, transparency,
body_rect). coil is the exception: its source is present but opaque, so `game/tools/art/coil.gd`
owns its frames (the pipeline skips enemies with an art module) - all 5 cycle frames are real art
(squash -> extend, 512x512 bottom-anchored, `"tbd": false`), the anim block and tick ranges are
unchanged, and fog contrast is ~8.4 at 40 u. thicc ben (row 3) and kiwi cat (row 1, T-ART-KIWI_CAT) are the others.

Isagi's three sources are no longer missing: `game/tools/art/isagi.gd` (the T-016 art module; the
shared pipeline skips any enemy with `tools/art/<id>.gd`) removed the backgrounds, derived the
anim-block frames per state (spawn/idle/telegraph/attack/recover) and flipped isagi's `tbd` to
false on 2026-11-17. Isagi's rows below say REAL ART; the other fourteen remain MISSING -> TBD.
Isagi's T-083 anim block named the TBD placeholder files, not the spec names - those references are
now the real frames (frame_map isagi_idle_00/isagi_shoot_00/isagi_ball_00); the tick counts, loop
flags, tick ranges and effect params are untouched.
body_rect). Note: the toucher is NOT pipeline-built - it is owned by `game/tools/art/toucher.gd`
(the pipeline skips it), which keys the black/white backdrops itself and derives the per-state
frames from one base.
change. Exception: `gin`'s two sources are opaque (near-white), so `game/tools/art/gin.gd`
(T-ART-GIN) produces its frames instead of the pipeline, which skips the enemy. Every frame is
validated by `game/tools/validate_sprites.gd` (fog contrast, transparency,
body_rect).
unchanged, and fog contrast is ~8.4 at 40 u. gift Larper is the same kind of exception since
2026-11-17: `tripine.png` needed its own module (`game/tools/art/gift_larper.gd`) because the
near-black body is 1.0 contrast vs fog as shipped - 6 real frames (5 distinct idle cycle frames
+ a defused pose), 512x512 bottom-anchored, `"tbd": false`, the anim block and tick ranges are
unchanged, fog contrast 3.05-3.87 at 40 u (palette fog; per-biome 4.3+).
body_rect). coil and Claude are the exceptions: their sources need their own background removal,
so `game/tools/art/coil.gd` and `game/tools/art/claude.gd` own their frames respectively (the
pipeline skips enemies with an art module) - coil's 5 cycle frames and Claude's 10 logo-derived
frames are real art (squash -> extend; one distinct frame per anim-block state, 512x512
bottom-anchored), the anim blocks and tick ranges are unchanged, and fog contrast is ~8.4 and
~5.9-8.9 at 40 u. Claude stays `"tbd": true` (the plushie placeholders).

ART-ADDRESS_ME: the address me rows are no longer MISSING - the frames are real art generated by
`game/tools/art/address_me.gd` (the shared pipeline skips any enemy with an art module). Since the
owner ruling of 2026-11-17 (D-ART-ADDRESS_ME-5) the address me frame is the FULL office-interior
photo - no background removal, no crop - tone-graded only; the attack frame stays the explosion
cutout composited over the ghosted photo.

| # | enemy | expected filename | state |
|---|---|---|---|
| 1 | kiwi cat | `kiwicat.png` | PRESENT -> real art (T-ART-KIWI_CAT; frames `cycle_00`, `spawn_00`, `idle_chase_00`, `telegraph_00`; `tbd: false`) |
| 2 | coil | `springer.png` | REAL ART (2026-11-17, `game/tools/art/coil.gd`) |
| 3 | thicc ben | `thiccben.png` | REAL ART - `game/tools/art/thicc_ben.gd` (2026-11-17); `cycle/spawn/attack_arrival/attack_ring/recover_00.png`; `tbd: false`; validate: SPRITES OK |
| 4 | Isagi | `isagi_idle.jpeg` | REAL ART - `game/tools/art/isagi.gd` (2026-11-17); frames `idle_00`, `spawn_00`, `telegraph_00`, `shoot_00`, `recover_00`, `fire_00..02`, `shot_00`; `tbd: false` |
| 5 | Isagi (shoot) | `ISAGI_SHOOT.webp` | REAL ART - the `attack` state frame `shoot_00.png` (`game/tools/art/isagi.gd`) |
| 6 | Isagi (projectile) | `blueballprojectile.webp` | REAL ART - the `shot` state frame `shot_00.png` (`game/tools/art/isagi.gd`) |
| 7 | nuke | `NUKE.jpeg` | REAL - base art + the four `attack_descent` frames (cycle_00..03.png, 512x128 POT, alpha-keyed background, tight body_rect); the other five T-083 states carry no sprite frames by the binding anim block (billboard-level effects) and stay empty | none for art; rebuild via `game/tools/art/nuke.gd` |
| 8 | YOU?! | `character to be corrupted.png` | REAL ART - `game/tools/art/you.gd` (2026-11-17); frames `cycle_00..04`, `you_spawn_00`, `you_idle_00..04`, `you_telegraph_00..04`, `you_attack_00`, `you_recover_00..04`; `tbd: false` |
| 9 | gift Larper | `tripine.png` | REAL ART - `game/tools/art/gift_larper.gd` (2026-11-17); frames `cycle_00..04` (5 distinct idle cycle) + `defused_00`; `tbd: false`; fog contrast 3.05-3.87 at 40 u |
| 10 | toucher | `toucher.jpeg` | LANDED (game/tools/art/toucher.gd; 12 real frames) |
| 11 | toucher (floor) | `glitchedground.jpeg` | LANDED (game/tools/art/toucher.gd; 5 real decal frames) |
| 12 | seal | `babehseal.webp` | REAL -> frames derived by `game/tools/art/seal.gd` (2026-11-17): idle_00/01, spawn_00, telegraph_00, dash_00/01, recover_00 |
| 13 | address me | `address me elephant.png` | REAL ART (ART-ADDRESS_ME, `game/tools/art/address_me.gd`; owner ruling 2026-11-17, D-ART-ADDRESS_ME-5): cycle_00/01, spawn_00, telegraph_00, leaves_00, attack_00; `tbd: false`; the frame is the FULL office-interior photo (edge-to-edge, no crop, no cutout), tone-graded only (x1.15 + 10/255) |
| 14 | address me (explosion) | `explosionsffect.jpg` | REAL ART - the explode frame is the spec's composite (explosionsffect.jpg cutout over the ghosted FULL photo at 30% alpha), shipped as `attack_00.png` / `cycle_01.png` (D-ART-ADDRESS_ME-4; the ruling covers the elephant photo only, so the fireball stays a cutout) |
| 15 | Claude | `claudelogo.png` (+ clawd Crab plushie) | REAL ART for the logo (2026-11-17, `game/tools/art/claude.gd`): 10 logo-derived frames, one per anim-block state; the clawd Crab plushie was never fetched -> `plushie_00..02.png` stay TBD placeholders (`tbd`: true) | plushie: fetch the clawd Crab sprite (ENEMIES.md points at github.com/xyc/plushie); rebuild the logo frames via `tools/godot/godot.exe --headless --path game --script res://tools/art/claude.gd` |
| 16 | gin ichimaru | `gin idle.png` | REAL ART (T-ART-GIN, `game/tools/art/gin.gd`) |
| 17 | gin ichimaru (sword) | `ginsword.png` | REAL ART (T-ART-GIN, `game/tools/art/gin.gd`) |

## 2. Synthesized stand-ins for named recordings

Three sounds in `ENEMIES.md` name existing recordings, which cannot be shipped. Each gets a
synthesized stand-in under the TBD rule, marked `"tbd_audio": true` (T-087).

| cue | what ENEMIES.md names | stand-in |
|---|---|---|
| thicc ben chime | Big Ben's chime | synthesized bell, same rhythm |
| thicc ben audio hooks (T-032) | the Westminster cues before each teleport ("New sound" line) | runtime-synthesized placeholder `AudioStreamWAV` hooks `thicc_ben_chime` / `thicc_ben_bell` in `game/view/audio/thicc_ben_audio.gd` (T-055 swaps in file-backed cues; cue names are the stable contract) |
| Isagi voice + shot | Isagi's voice lines and shot | synthesized shout-formant + ball pop |
| gift Larper explosion | the Roblox tripmine explosion | synthesized blast |

## 3. Other placeholders

| # | ticket | what is TBD | why | owner action |
|---|---|---|---|---|
| 21 | T-025 | HUD curse/upgrade/enemy-roster icons - synthesized hash-hue squares with the item id's initials (game/view/hud/icon_placeholder.gd) | no curse, upgrade or enemy icon assets exist anywhere in the repo | commission 40 px icon art per curse/upgrade/enemy; swap icon_placeholder.gd for a texture loader |
| 28 | T-030 | kiwi cat audio cue `meow` - not synthesized yet; `game/view/audio/kiwi_cat_audio.gd` no-ops silently until `assets/audio/enemies/kiwi_cat/meow.wav` lands | ENEMIES.md "New sound" ("cat meow when near player") is brand-new audio; T-055 owns placeholder synthesis | T-055 synthesises the placeholder (stdlib wave; cue name = file name); the owner replaces it with real cat meow art later |
| 29 | T-030 | kiwi cat audio cue `meow_double` (Zoomies) - not synthesized yet; same no-op hook | same | same - T-055 synthesises; the owner replaces |
| 30 | T-036 | gift Larper audio cue `explosion` - not synthesized yet; `game/view/audio/gift_larper_audio.gd` no-ops silently until `assets/audio/enemies/gift_larper/explosion.wav` lands | ENEMIES.md "New sound" ("Roblox tripmine explosion sound effect") is brand-new audio; T-055 owns placeholder synthesis (the TBD section 2 row already lists the missing recording as the synthesized blast) | T-055 synthesises the placeholder (stdlib wave; cue name = file name); the owner replaces it with a real recording later |
| 31 | T-036 | gift Larper audio cue `pff` (the defused puff, the T-083 anim block's defused effect) - not synthesized yet; same no-op hook | same - not an ENEMIES.md addition; it is the defused-state puff the anim block names; T-055 owns placeholder synthesis | same - T-055 synthesises; the owner replaces |
| 32 | T-038 | seal audio cue `bark` - not synthesized yet; `game/view/audio/seal_audio.gd` no-ops silently until `assets/audio/enemies/seal/bark.wav` lands | ENEMIES.md "New sound" ("actual seal barks (arf arf) on the dash") is brand-new audio; T-055 owns placeholder synthesis | T-055 synthesises the placeholder (stdlib wave; cue name = file name); the owner replaces it with real seal bark art later |
| 33 | T-038 | seal audio cue `flipper_flap` (wet flipper flaps while it moves) - not synthesized yet; `game/view/audio/seal_audio.gd` no-ops silently until `assets/audio/enemies/seal/flipper_flap.wav` lands | same | same - T-055 synthesises; the owner replaces |

## 4. T-083 animation-block TBD rows (this ticket, enemies 7-12)

T-016 produced TBD placeholders for all 12 enemies, so every T-083 anim block names the files that
exist, not the names the section 1.x tables use (section 1.0 pre-authorizes the rename here). The
class of placeholder is the same; the rows are split per enemy for owner action.

| # | ticket | what is TBD | why | owner action |
|---|---|---|---|---|
| 22 | T-083 | gift Larper: spec frames `larper_00..04` are referenced as `sprites/cycle_00..04.png`; timings unchanged | T-016 TBD placeholder names differ from the spec's names | drop the real tripine frames in keeping the cycle names, or rebuild the pipeline to emit the spec names |
| 23 | T-083 | toucher: FIXED (T-ART) - real art landed; the states' frames point at per-state files (spawn_00, idle_00..02, telegraph_00..02, attack_00), frame_map resolves the pinned spec names onto the cycle art (cycle_00..02), spec `glitchfloor_00..04` remain `sprites/floor_00..04.png` (now real decals), spec `toucher_00..02` remain cycle_00..02. Frame counts, tick ranges, loops and effect parameters unchanged | art landed via game/tools/art/toucher.gd | none - the A8 fog-contrast on the floor decals is met by relighting the ART (glowing magenta family), never the threshold |
| 24 | T-083 | seal: ~~spec `seal_01` (mouth open) and `seal_02/03`~~ DONE - the mouth gape ships as `telegraph_00.png`/`dash_00/01.png` (spec seal_01) and the idle flap pair is `idle_00/01.png` (spec seal_03/02); the anim block, tick ranges, loops, fps and effect params are unchanged | resolved by the seal art tickets (D-ART-SEAL-1, re-derived D-ART-SEAL-3) | none |
| 25 | T-083 | ~~address me~~ DONE (ART-ADDRESS_ME): spec `addressme_00/01` are referenced as `sprites/cycle_00/01.png`; the explode frame is now built as the spec intends (Image 14 / explosionsffect.jpg composited over the elephant at 30% alpha). The anim block's spawn/telegraph/leaves/attack states point at the distinct frames `sprites/spawn_00.png` / `sprites/telegraph_00.png` / `sprites/leaves_00.png` / `sprites/attack_00.png` (attack_00 and cycle_01 are the same composite under the two names the view and the anim block each expect - DECISIONS D-ART-ADDRESS_ME-4). `tbd` is now false in sprites.json | resolved by the address-me art ticket | none - landed |
| 26 | T-083 | claude: spec `claude_00` referenced as `sprites/idle_00.png`; spec `plushie_00..02` DO NOT EXIST - `plushie_idle` loops the three TBD logo frames at the table's 6 fps / 10 ticks per frame (the only 3-frame set in the sheet) | clawd Crab plushie sprite was never fetched (ENEMIES.md points at github.com/xyc/plushie) | fetch the clawd Crab sprite, rebuild the pipeline, point `plushie_idle` at the real plushie_00..02 |
| 27 | T-083 | gin: spec frames `gin_idle_00`/`gin_launch_00` resolve to `sprites/idle_00.png`/`sprites/launch_00.png`; REAL ART landed (T-ART-GIN) - every anim-block state now holds its own distinct frame (`spawn_00`/`telegraph_00`/`recover_00` derived from the body, `launch_00` from the sword); no TBD placeholder remains | T-016 TBD placeholder, replaced by real art | none - `attack_void_zone` stays frameless by design (the void zone is VFX) |
| 28 | T-031 | coil cues `coil_boing` (the pre-jump boing) and `coil_landing_twang` (the metallic twang on landing) - no files exist; the enemy.json `stats.audio` block names them for T-055 to synthesise | ENEMIES.md "New sound" for coil (classic spring boing before every jump, metallic twang on landing); no audio is committed yet, per the placeholder-audio wave | T-055 synthesises both from the cue names; the sim never reads audio length, cue timings ride the telegraph events |

## 5. T-032 thicc ben placeholder rows

| # | ticket | what is TBD | why | owner action |
|---|---|---|---|---|
| 29 | T-032 | screen blur on the touch renders as a teal wash, not a true blur | no HUD blur shader exists yet; the binding strength curve (1.0 for 120 ticks, linear to 0 over the last 60 of 180) is implemented and tested in game/view/hud/screen_blur.gd (strength_for) | add the blur shader (BackBufferCopy), keep strength_for as-is |
| 30 | T-032 | the telegraph smoke VFX, the arrival white flash and the touch ring are placeholder-quality (CPUParticles3D puffs, over-bright modulate flash, expanding cylinder ring); the timings are read from the T-083 anim block (smoke 75 ticks, 30-tick ben fade at the old position, 6-tick flash, 18-tick ring to 8 u, 30-tick spawn fade) | real VFX polish is an art/tech-art pass; the anim block timings are binding and are wired | replace the looks; keep the anim-block-driven tick flow |
| 31 | T-035 | YOU?!: placeholder audio cue hook `you_corrupted_rumble` (quiet corrupted static + reversed glitch screech building up before each shockwave - the ENEMIES.md New sound line). Named in `enemy.json` (`stats.audio_cues`); no .wav exists yet | T-055 (placeholder audio synth) runs the whole roster and has not landed; the file stem is the hook name | run T-055 (file names = cue names); keep the hook name stable |

## 6. T-039 address me placeholder rows

| # | ticket | what is TBD | why | owner action |
|---|---|---|---|---|
| 32 | T-039 | the placeholder audio cue hooks `spawn_trumpet` (elephant trumpet on spawn), `rumble_build` (low rumbling build-up over the 5 s), `explode_boom` (massive boom on the explode frame) - the ENEMIES.md "New sound" line. Named in `enemy.json` (`stats.audio_cues`); synthesised at runtime in `game/view/audio/address_me_audio.gd`; no .wav files exist yet | T-055 (placeholder audio synth) runs the whole roster and has not landed; the file stem is the hook name | run T-055 (file names = cue names); keep the hook names stable |

## 7. T-037 toucher placeholder rows

| # | ticket | what is TBD | why | owner action |
|---|---|---|---|---|
| 33 | T-037 | toucher: placeholder audio cue hook `toucher_squelch` (the ENEMIES.md New sound line: corrupted squelch - wet glitch gurgle and digital distortion - fired only on ticks where new glitched tiles appear). Named in `enemy.json` (`stats.audio_cues`); no .wav exists yet | T-055 (placeholder audio synth) runs the whole roster and has not landed; the file stem is the hook name | run T-055 (file names = cue names); keep the hook name stable |

## 8. T-055 placeholder audio - ALL ENEMY AUDIO IS PLACEHOLDER

EVERY enemy audio cue currently in the build is placeholder synthesis from
`tools/synth_audio.py` (stdlib `wave` + `math`; deterministic LCG noise;
peak-normalised; 44.1 kHz mono 16-bit). Nothing is downloaded, recorded or
copied from any existing work - that includes the three sounds ENEMIES.md
names as existing recordings (thicc ben's chime, Isagi's voice/gunshot, gift
Larper's tripmine blast), which are synthesized stand-ins, never the real
things. Each file lives at
`game/assets/audio/enemies/<id>/<cue>.wav` (the path the `game/view/audio/*_audio.gd`
hooks load) and every cue referenced in `content/enemies/*/enemy.json` resolves
to one. Cue timings are driven by sim telegraph events, never by audio length.
The hooks above that said "T-055 has not landed" are superseded by this section.

| # | ticket | what is TBD | why | owner action |
|---|---|---|---|---|
| 34 | T-055 | kiwi cat: `meow`, `meow_double` - synthesized placeholder meows (sine glide + vibrato, `meow_double` pitched up a fourth) | brand-new audio, no recording ships | replace with real cat-meow art, keep the cue names stable |
| 35 | T-055 | coil: `coil_boing`, `coil_landing_twang` - synthesized spring boing / inharmonic-sine twang | brand-new audio | replace with real spring samples, keep the cue names stable |
| 36 | T-055 | thicc ben: `thicc_ben_chime`, `thicc_ben_bell` - synthesized bell stand-in (Westminster-flavoured four-note figure compressed to 0.5 s; never the real recording) | ENEMIES.md names the real Big Ben chime - cannot ship | replace with licensed/real bell art, keep the cue names stable |
| 37 | T-055 | Isagi: `isagi_voice_direct_shot`, `isagi_shoot_sae_math_final_shot`, `isagi_gunshot` - synthesized rising whoosh / formant yell / noise-burst gunshot | ENEMIES.md names Isagi voice lines and a gunshot - no recordings ship; Isagi's `enemy.json` lists NO `audio_cues` yet, so these are named per the T-033 rows, not wired by any enemy.json | wire the cue list in T-087; replace the stand-ins with real (or owner-approved) art |
| 38 | T-055 | nuke: `lock_on_beep`, `rocket_booster_roar`, `impact_boom` - synthesized 1200 Hz square blip / falling-cutoff noise roar / 45 Hz sine boom | brand-new audio; nuke's `enemy.json` lists NO `audio_cues` yet; these are named per the TBD audio hooks in `nuke/sprites.json` | wire the cue list in T-087; replace with real art |
| 39 | T-055 | gift Larper: `explosion`, `pff` - synthesized click+noise blast / falling-pff puff | ENEMIES.md names the Roblox tripmine explosion - cannot ship | replace with real art, keep the cue names stable |
| 40 | T-055 | YOU?!: `you_corrupted_rumble` - synthesized gated-noise rumble + reversed-envelope tone | brand-new audio | replace with real art, keep the cue name stable |
| 41 | T-055 | seal: `bark`, `flipper_flap` - synthesized sawtooth yelps / filtered noise slaps | brand-new audio | replace with real seal art, keep the cue names stable |
| 42 | T-055 | address me: `spawn_trumpet`, `rumble_build`, `explode_boom` - synthesized sawtooth trumpet / 40 Hz build-up rumble / 41 Hz boom | brand-new audio | replace with real art, keep the cue names stable |
| 43 | T-055 | Claude: `ui_chime`, `keystroke_tick`, `notification_ping`, `squeak_pop` - synthesized UI chimes, ticks, ping, squeak-pop | brand-new audio | replace with real art, keep the cue names stable |
| 44 | T-055 | gin ichimaru: `crack_rumble`, `shing`, `whoosh`, `zone_open`, `zone_close` - synthesized crackle / metallic sweep / noise whoosh / hollow drop and reverse | brand-new audio | replace with real art, keep the cue names stable |
| 45 | T-055 | toucher: `toucher_squelch` - synthesized wobbling-band noise with bit-crush | brand-new audio | replace with real art, keep the cue name stable |
| 46 | T-055 | ALL cue recipes and lengths in `tools/synth_audio.py` are `[CONTESTABLE]` placeholders (research/fable-tickets.md section 3); cue names, formats (44.1 kHz mono 16-bit) and the file-name = cue-name contract are the stable part | the section 3 recipes are stand-ins pending a real sound pass | the real sound pass rewrites recipes only, never cue names

| 47 | T-087 | Isagi: `isagi_voice_direct_shot`, `isagi_shoot_sae_math_final_shot`, `isagi_gunshot` now listed in enemy.json (`audio_cues`) with "tbd_audio": true - synthesized voice / sae-math-final-shot / gun-shot stand-ins | ENEMIES.md names Isagi's direct-shot voice lines and the gun-shot - no recordings ship; enemy.json listed NO cues until T-087 wired them | the owner drops real (or owner-approved) voice/gun-shot art; cue names stay stable |
| 48 | T-087 | gift Larper: `explosion` (section 3 `mine_blast` row) now flagged "tbd_audio": true in enemy.json - the Roblox tripmine explosion stand-in | ENEMIES.md names the Roblox tripmine explosion sound - cannot ship; the synthesized stand-in keeps the cue wired | the owner replaces it (or never does) - cue name stays stable |
| 49 | T-087 | thicc ben: `thicc_ben_chime` - the Westminster stand-in (restated for T-087; section 2 and row 36) stays "tbd_audio": true, now with the binding math wired in enemy.json (anchor telegraph/teleport, offset 45, binding 30, ends on the arrival tick 75) | ENEMIES.md names Big Ben's real chime - cannot ship | the owner replaces it with licensed bell art; cue name + the 30-tick binding window stay stable |
