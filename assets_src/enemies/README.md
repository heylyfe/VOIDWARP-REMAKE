# Enemy source images

Drop the 17 source images here with EXACTLY these filenames (typos included — they are the real names, per ENEMIES.md):

Image 1 = "kiwicat.png" · Image 2 = "springer.png" · Image 3 = "thiccben.png" · Image 4 = "isagi_idle.jpeg" ·
Image 5 = "ISAGI_SHOOT.webp" · Image 6 = "blueballprojectile.webp" · Image 7 = "NUKE.jpeg" ·
Image 8 = "character to be corrupted.png" · Image 9 = "tripine.png" · Image 10 = "toucher.jpeg" ·
Image 11 = "glitchedground.jpeg" · Image 12 = "babehseal.png" · Image 13 = "address me elephant.png" ·
Image 14 = "explosionsffect.jpg" · Image 15 = "claudelogo.png" · Image 16 = "gin idle.png" · Image 17 = "ginsword.png"

Any file that is missing when the sprite pipeline runs (FLEET_PACK T-016) becomes a TBD placeholder PNG and a row in TBD.md.
The build never stops for a missing or refused asset.

## Owner replacements (2026-11-17, after the first art wave)

- **Image 12 (seal)** was replaced by the owner with a transparent-background harp-seal pup PNG.
  The file is now `babehseal.png`; the original `babehseal.webp` was removed so there is exactly
  one source per enemy. The new image already carries an alpha channel.
- **Image 13 (address me)** is UNCHANGED as a source file. The owner confirmed the office-interior
  photo is the intended art and its background must NOT be cut out: the art tool must keep the
  full photo, background included.
