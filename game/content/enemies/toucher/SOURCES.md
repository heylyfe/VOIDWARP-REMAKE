 toucher - SOURCES

Frames owned by `game/tools/art/toucher.gd` (this enemy is NOT built by
`game/tools/sprite_pipeline.gd` - the pipeline skips any enemy with an art module, so a
rebuild can never regress it). Spec: ENEMIES.md (roster + "Attachment mapping", by image
number AND exact filename) and DESIGN.md section 5 (world sizes). PNG frames under
`sprites/` are committed build artifacts with their sources documented here.

| image | exact filename | path (repo-relative) | state |
|---|---|---|---|
| 10 | `toucher.jpeg` | `assets_src/enemies/toucher.jpeg` | LANDED (art module) |
| 11 | `glitchedground.jpeg` | `assets_src/enemies/glitchedground.jpeg` | LANDED (art module) |

Recipe (game/tools/art/toucher.gd, headless `--script res://tools/art/toucher.gd`):
RGBA convert; background removed by a flood fill from the BORDER sampled colour
(finger: near-black, distance <= ~34/255; cube: near-white, distance <= ~61/255 - a
global key would eat the finger's dark outline pixels); tight crop to the body
(alpha > 16 = the only hitbox-eligible pixels); Lanczos upscale onto a 256x256
power-of-two canvas with >= 2 px of transparent margin (we keep >= 12 px). Every
body frame is one pasted base with a deterministic colour-only derivation (brightness
mult/add, scanline darkening, flash bands; the floor decals add row-displacement
glitch), so the spawn/idle/telegraph/attack silhouettes are IDENTICAL and the
body_rect never disagrees with the frame shown.

HITBOXES hard rule: a frame's `body_rect` in sprites.json (tight bbox of alpha > 16) is
the only solid part of the sprite; the transparent padding and margins never hit.

DISCLAIMER (ENEMIES.md hard rule): this is a personal, non-commercial project with no money
involved; it is not affiliated with, endorsed by, or connected to any person, brand,
character, or IP referenced or depicted here.
