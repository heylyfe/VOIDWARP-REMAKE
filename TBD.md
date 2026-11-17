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

| # | ticket | what is TBD | why | owner action |
|---|---|---|---|---|
| 21 | T-025 | HUD curse/upgrade/enemy-roster icons - synthesized hash-hue squares with the item id's initials (game/view/hud/icon_placeholder.gd) | no curse, upgrade or enemy icon assets exist anywhere in the repo | commission 40 px icon art per curse/upgrade/enemy; swap icon_placeholder.gd for a texture loader |

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
