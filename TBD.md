# TBD.md - every placeholder left in the build

ENEMIES.md hard rule (TBD FALLBACK): a missing name or asset never stalls the run. The behavior is
wired in full, the entry is marked `"tbd": true` in its JSON, and the row appears here.

| # | ticket | what is TBD | why | owner action |
|---|---|---|---|---|
| 1 | T-016 | kiwi cat sprites - all frames TBD | Image 1 `assets_src/enemies/kiwicat.png` absent | drop the PNG in with the exact filename, rebuild the sprite pipeline |
| 2 | T-016 | coil sprites - all frames TBD | Image 2 `springer.png` absent | drop the PNG in, rebuild |
| 3 | T-016 | thicc ben sprites - all frames TBD | Image 3 `thiccben.png` absent | drop the PNG in, rebuild |
| 4 | T-016 | Isagi sprites - all frames TBD | Images 4/5/6 (`isagi_idle.jpeg`, `ISAGI_SHOOT.webp`, `blueballprojectile.webp`) absent | drop all three PNGs in, rebuild |
| 5 | T-016 | nuke sprites - all frames TBD | Image 7 `NUKE.jpeg` absent | drop the PNG in, rebuild |
| 6 | T-016 | YOU?! sprites - all frames TBD | Image 8 `character to be corrupted.png` absent | drop the PNG in, rebuild |
| 7 | T-016 | gift Larper sprites - all frames TBD | Image 9 `tripine.png` absent | drop the PNG in, rebuild |
| 8 | T-016 | toucher sprites - all frames TBD | Images 10/11 (`toucher.jpeg`, `glitchedground.jpeg`) absent | drop both PNGs in, rebuild |
| 9 | T-016 | seal sprites - all frames TBD | Image 12 `babehseal.webp` absent | drop the PNG in, rebuild |
| 10 | T-016 | address me sprites - all frames TBD | Images 13/14 (`address me elephant.png`, `explosionsffect.jpg`) absent | drop both PNGs in, rebuild |
| 11 | T-016 | Claude sprites - all frames TBD | Image 15 `claudelogo.png` absent (clawd Crab plushie source unfetched -> TBD) | drop the PNG in, rebuild |
| 12 | T-016 | gin ichimaru sprites - all frames TBD | Images 16/17 (`gin idle.png`, `ginsword.png`) absent | drop both PNGs in, rebuild |

## 2. Placeholder audio hooks (T-033)

| # | ticket | what is TBD | why | owner action |
|---|---|---|---|---|
| 1 | T-033 | isagi: `isagi_voice_direct_shot` - each burst's audio cue (ENEMIES.md Isagi "New sound": direct shot voice lines) | no audio files exist yet in the build | drop the hook file in, view wires it |
| 2 | T-033 | isagi: `isagi_shoot_sae_math_final_shot` - the shoot line per release (ENEMIES.md Isagi "New sound": Isagi shoot sae math final shot gun-shot sound) | no audio files exist yet | drop the hook file in, view wires it |
| 3 | T-033 | isagi: `isagi_gunshot` - per ball release, layered under the shoot line | no audio files exist yet | drop the hook file in, view wires it |

## 1. The 17 enemy images - ALL MISSING

Enemy sprites are produced by `game/tools/sprite_pipeline.gd` (T-016): missing, unreadable, or
validation-failing sources become `game/tools/make_tbd_png.gd` placeholder frames, `"tbd": true`
in `content/enemies/<id>/sprites.json`, and the rows below. Dropping the real PNG in with the
exact filename below and re-running the pipeline swaps the placeholder for real art with no code
change. Every frame is validated by `game/tools/validate_sprites.gd` (fog contrast, transparency,
body_rect).

| # | enemy | expected filename | state |
|---|---|---|---|
| 1 | kiwi cat | `kiwicat.png` | MISSING -> TBD |
| 2 | coil | `springer.png` | MISSING -> TBD |
| 3 | thicc ben | `thiccben.png` | MISSING -> TBD |
| 4 | Isagi | `isagi_idle.jpeg` | MISSING -> TBD |
| 5 | Isagi (shoot) | `ISAGI_SHOOT.webp` | MISSING -> TBD |
| 6 | Isagi (projectile) | `blueballprojectile.webp` | MISSING -> TBD |
| 7 | nuke | `NUKE.jpeg` | MISSING -> TBD |
| 8 | YOU?! | `character to be corrupted.png` | MISSING -> TBD |
| 9 | gift Larper | `tripine.png` | MISSING -> TBD |
| 10 | toucher | `toucher.jpeg` | MISSING -> TBD |
| 11 | toucher (floor) | `glitchedground.jpeg` | MISSING -> TBD |
| 12 | seal | `babehseal.webp` | MISSING -> TBD |
| 13 | address me | `address me elephant.png` | MISSING -> TBD |
| 14 | address me (explosion) | `explosionsffect.jpg` | MISSING -> TBD |
| 15 | Claude | `claudelogo.png` (+ clawd Crab plushie) | MISSING -> TBD |
| 16 | gin ichimaru | `gin idle.png` | MISSING -> TBD |
| 17 | gin ichimaru (sword) | `ginsword.png` | MISSING -> TBD |

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
| 23 | T-083 | toucher: spec `toucher_00..02` referenced as `sprites/cycle_00..02.png`, spec `glitchfloor_00..04` as `sprites/floor_00..04.png` | same T-016 placeholder naming | drop the real toucher.jpeg / glitchedground.jpeg derivatives in |
| 24 | T-083 | seal: spec `seal_01` (mouth open) and `seal_02/03` (flippers up/down) DO NOT EXIST in the TBD sheet. The anim block holds `idle_00.png` for idle (at the table's 9 ticks/frame) and telegraph (45 ticks held), and alternates `dash_00/dash_01.png` at the table's 4 ticks per frame for the 60-tick dash. Frame set cannot express the table's flap overlay | T-016 produced only `idle_00` and `dash_00/01` | drop the real babehseal derivatives in (mouth-open, flippers up/down); the anim block then names them and the frame-count gap closes |
| 25 | T-083 | address me: spec `addressme_00/01` referenced as `sprites/cycle_00/01.png`; the spec's explode frame (Image 14 composited over the elephant at 30% alpha) is unbuilt - both frames are identical placeholder art | same T-016 placeholder | drop the real address-me-elephant.png / explosionsffect.jpg derivatives in and rebuild |
| 26 | T-083 | claude: spec `claude_00` referenced as `sprites/idle_00.png`; spec `plushie_00..02` DO NOT EXIST - `plushie_idle` loops the three TBD logo frames at the table's 6 fps / 10 ticks per frame (the only 3-frame set in the sheet) | clawd Crab plushie sprite was never fetched (ENEMIES.md points at github.com/xyc/plushie) | fetch the clawd Crab sprite, rebuild the pipeline, point `plushie_idle` at the real plushie_00..02 |
| 27 | T-083 | gin: spec frames `gin_idle_00`/`gin_launch_00` happen to match the TBD names (`idle_00.png`/`launch_00.png`); no mismatch, but the art is still the TBD placeholder | T-016 TBD placeholder | drop the real gin idle.png / ginsword.png derivatives in |
| 28 | T-031 | coil cues `coil_boing` (the pre-jump boing) and `coil_landing_twang` (the metallic twang on landing) - no files exist; the enemy.json `stats.audio` block names them for T-055 to synthesise | ENEMIES.md "New sound" for coil (classic spring boing before every jump, metallic twang on landing); no audio is committed yet, per the placeholder-audio wave | T-055 synthesises both from the cue names; the sim never reads audio length, cue timings ride the telegraph events |

## 5. T-032 thicc ben placeholder rows

| # | ticket | what is TBD | why | owner action |
|---|---|---|---|---|
| 29 | T-032 | screen blur on the touch renders as a teal wash, not a true blur | no HUD blur shader exists yet; the binding strength curve (1.0 for 120 ticks, linear to 0 over the last 60 of 180) is implemented and tested in game/view/hud/screen_blur.gd (strength_for) | add the blur shader (BackBufferCopy), keep strength_for as-is |
| 30 | T-032 | the telegraph smoke VFX, the arrival white flash and the touch ring are placeholder-quality (CPUParticles3D puffs, over-bright modulate flash, expanding cylinder ring); the timings are read from the T-083 anim block (smoke 75 ticks, 30-tick ben fade at the old position, 6-tick flash, 18-tick ring to 8 u, 30-tick spawn fade) | real VFX polish is an art/tech-art pass; the anim block timings are binding and are wired | replace the looks; keep the anim-block-driven tick flow |
| 31 | T-035 | YOU?!: placeholder audio cue hook `you_corrupted_rumble` (quiet corrupted static + reversed glitch screech building up before each shockwave - the ENEMIES.md New sound line). Named in `enemy.json` (`stats.audio_cues`); no .wav exists yet | T-055 (placeholder audio synth) runs the whole roster and has not landed; the file stem is the hook name | run T-055 (file names = cue names); keep the hook name stable |
