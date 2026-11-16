# TBD.md - every placeholder left in the build

ENEMIES.md hard rule (TBD FALLBACK): a missing name or asset never stalls the run. The behavior is
wired in full, the entry is marked `"tbd": true` in its JSON, and the row appears here.

| # | ticket | what is TBD | why | owner action |
|---|---|---|---|---|

## 1. The 17 enemy images - ALL MISSING

`assets_src/enemies/` contains only `README.md`. Every one of the 17 owner images is absent, so every
enemy sprite tonight is a `tools/make_tbd_png.gd` placeholder and every enemy entry carries
`"tbd": true`. Dropping the real PNG in with the exact filename below replaces it with no code change.

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
