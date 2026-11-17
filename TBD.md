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
| Isagi voice + shot | Isagi's voice lines and shot | synthesized shout-formant + ball pop |
| gift Larper explosion | the Roblox tripmine explosion | synthesized blast |

## 3. Other placeholders

(none yet)
