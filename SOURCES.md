# SOURCES

Where the game's non-generated assets come from. One row per asset, so anyone can trace an
image back to its origin and know what it may be used for. Per-enemy art keeps its own
`game/content/enemies/<id>/SOURCES.md`; this file covers everything else.

| asset | path | origin | licence / note |
|---|---|---|---|
| The Master (death-screen host) | `game/assets/characters/the_master.png` | The owner's supplied image (`the_master_cat.png`, a tabby cat in a white collar and a red striped tie), cropped to the bust and edge-faded to transparent by a scratch Godot script (2026-11-21) | Supplied by the owner for use in VOIDWARP RUN; no third-party licence recorded. Keep it out of any redistribution beyond the game until the owner confirms the rights |
| Class icons (dasher, glider, athletic) | `game/assets/icons/classes/<id>.png` | Rasterised at 256 px from the repo's own `docs/classes/<id>.svg` (`Image.load_svg_from_string` at 0.5x, blended onto the altar card colour #0D1229) | Project-made art, same terms as the SVGs |

## Synthesized audio cues (the player / UI / world / ambience set)

Every cue below is **synthesized from code** by `game/tools/audio/synth_cues.gd` - no sampled,
recorded or downloaded audio is used anywhere in the set. The generator is deterministic (a
fixed LCG seed per cue, a fixed 44.1 kHz mono 16-bit format, no wall clock), so the whole set
is reproducible with one command:

```
tools/godot/godot.exe --headless --path game --script res://tools/audio/synth_cues.gd
```

The cue NAMES are the contract the view layer plays (`game/view/audio/player_audio.gd`,
`ui_audio.gd`, `world_audio.gd`, `ambience_audio.gd`); the recipes may be rewritten without
renaming a cue. Project-made audio, same terms as the rest of the game.

| asset | path | origin | licence / note |
|---|---|---|---|
| footstep 1 | `game/assets/audio/player/footstep_01.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (low thump + filtered-noise scuff, variant 1) | Project-made audio; no third-party material |
| footstep 2 | `game/assets/audio/player/footstep_02.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (variant 2) | Project-made audio; no third-party material |
| footstep 3 | `game/assets/audio/player/footstep_03.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (variant 3) | Project-made audio; no third-party material |
| footstep 4 | `game/assets/audio/player/footstep_04.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (variant 4) | Project-made audio; no third-party material |
| landing | `game/assets/audio/player/land.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (body thud, pitch dropping as it settles, dust tail) | Project-made audio; no third-party material |
| dash | `game/assets/audio/player/dash.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (noise band with a rising cutoff under a rising tone) | Project-made audio; no third-party material |
| glide | `game/assets/audio/player/glide.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (wind: band of noise with a 2 Hz swell; looped, tail crossfaded into the head) | Project-made audio; no third-party material |
| gift pickup 1 | `game/assets/audio/world/gift_pickup_01.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (bell at A5 + fifth + octave, click transient) | Project-made audio; no third-party material |
| gift pickup 2 | `game/assets/audio/world/gift_pickup_02.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (bell at B5, a whole tone up) | Project-made audio; no third-party material |
| gift pickup 3 | `game/assets/audio/world/gift_pickup_03.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (bell at D6) | Project-made audio; no third-party material |
| level complete | `game/assets/audio/world/level_complete.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (rising C5-E5-G5-C6 arpeggio over a soft pad) | Project-made audio; no third-party material |
| death | `game/assets/audio/world/death.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (tone falling a two-octave minor third, noise breath, sub rumble) | Project-made audio; no third-party material |
| collapse crack | `game/assets/audio/world/collapse_crack.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (sparse threshold-triggered crackle over a low thump) | Project-made audio; no third-party material |
| collapse fall | `game/assets/audio/world/collapse_fall.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (rumble whose cutoff and pitch sink as the slab drops) | Project-made audio; no third-party material |
| menu hover | `game/assets/audio/ui/menu_hover.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (one soft 1320 Hz tick, 70 ms) | Project-made audio; no third-party material |
| menu click | `game/assets/audio/ui/menu_click.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (two tones a fifth apart, the second answering the first) | Project-made audio; no third-party material |
| lobby ambience | `game/assets/audio/ambience/lobby_ambience.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (55 / 82.5 / 110 Hz drone breathing at 0.25 Hz under airy noise; 4 s loop, tail crossfaded into the head) | Project-made audio; no third-party material |
| music bed | `game/assets/audio/ambience/music_bed.wav` | Synthesized by `game/tools/audio/synth_cues.gd` (four two-second chords, Am - F - C - G, with a detuned shimmer; 8 s loop, tail crossfaded into the head) | Project-made audio; no third-party material |

