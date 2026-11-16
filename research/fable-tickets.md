# Ticket-completeness pass — full specs

Written 2026-11-16 by the design lead (Fable 5.2), against commit `14be164`. This file holds the full
specs; FLEET_PACK.md gets the short ticket entries and the overnight run plan that point here.

Rules of this pass: existing tickets and FINAL decisions are NOT edited. Anything I would change is a
`[CONTESTABLE]` note. Every number below that no earlier document states is marked `[CONTESTABLE]`
once, at the place it is introduced — the worker builds it as written and the owner may change it.
ENEMIES.md behavior sentences are frozen (D-040). TBD fallback applies to every asset.

Time base: the simulation ticks at 60 Hz. Every duration is given in seconds AND ticks; ticks win.
"Binding" = taken from DESIGN.md §5 and not negotiable.

Section status (updated as each section reaches disk):
- 1 Per-enemy animation specs — WRITTEN
- 2 VFX specs — WRITTEN
- 3 Sound briefs — WRITTEN
- 4 FLEET_PACK sweep: missing lines — WRITTEN
- 5 New tickets (full specs) — WRITTEN
- 6 Overnight run plan — lives in FLEET_PACK.md §10 (see that file)

---

## 1. Per-enemy PNG animation specs

### 1.0 Rules common to all 12

- Frames are the PNGs produced by T-016: `content/enemies/<id>/sprites/<name>_NN.png`. The names used
  below are the names T-016 must produce; if T-016 produced different names, T-083 renames in
  `sprites.json`, never in this spec.
- Every frame obeys the ENEMIES.md hard rules: billboard facing the viewer every frame; hit shape from
  `body_rect` of the frame CURRENTLY shown (so a squashed coil has a squashed hitbox); fully
  transparent background; passes `validate_sprites.gd` (corners alpha 0, no opaque border, fog
  contrast ≥ 3.0 at 40 u).
- A state's animation is driven by the SIMULATION state and its tick counter, never by a wall-clock
  timer in the view: `frame = table[state][ (ticks_in_state × fps) / 60 ]`. A telegraph animation
  therefore fills its cue exactly and the attack frame is shown on the tick the attack resolves.
- Effects that are not frames (flash, tint, scale pulse, shake, alpha) are shader/transform effects on
  the billboard. They never change `body_rect`.
- `spawn` for every enemy `[CONTESTABLE]`: alpha 0 → 1 over 0.50 s (30 ticks), scale 0.8 → 1.0, first
  idle frame. The body cannot touch or kill until the fade completes. The diegetic line
  (`THE … SHALL …`, section 4) floats at the spawn point for 4.0 s (240 ticks).
- No enemy has a `death` state: nothing in the roster can be killed. `despawn` (level end, or an enemy
  that leaves) = alpha 1 → 0 over 0.30 s (18 ticks) `[CONTESTABLE]`.
- Danger red `#FF2A2A` is the only colour used for telegraph flashes and ground telegraphs.

### 1.1 kiwi cat — Image 1 = "kiwicat.png"
Frames: `kiwicat_00` (the single PNG).

| state | frames | loop | timing | effect |
|---|---|---|---|---|
| spawn | kiwicat_00 | one-shot | 30 ticks | common fade |
| idle / chase | kiwicat_00 | loop | — | bob ± 0.08 u at 1.0 Hz `[CONTESTABLE]` |
| telegraph (meow) | kiwicat_00 | one-shot | 12 ticks every 180 ticks (3.0 s, binding) while within 14 u | scale pulse 1.0 → 1.12 → 1.0 |
| attack | — | — | contact kills on the tick the hit cylinders overlap | none: the cat has no wind-up, its tell is its presence |
| recover | — | — | — | — |
Zoomies (curse): the double meow = two pulses 12 ticks apart, then a red outline for the 180-tick sprint.

### 1.2 coil — Image 2 = "springer.png"
Frames: `coil_00` (fully squashed) … `coil_04` (fully extended); 5 frames.

| state | frames | loop | timing (binding) | effect |
|---|---|---|---|---|
| spawn | coil_02 | one-shot | 30 ticks | common fade |
| idle | coil_01 ↔ coil_02 | loop | 180 ticks (3.0 s); swap every 30 ticks | — |
| telegraph (pre-jump) | coil_02 → coil_01 → coil_00 | one-shot | 36 ticks (0.6 s): 12 ticks per frame; coil_00 is reached on tick 24 and held | red landing ring, radius 3 u, drawn at the target for the whole cue and the flight |
| attack — flight | coil_03 on ticks 0–20, coil_04 on ticks 21–144, coil_03 on ticks 145–164 | one-shot | 165 ticks (2.75 s); coil_04 (fully extended) spans the apex | — |
| attack — landing | coil_00 | one-shot | shown on tick 165 = the tick the landing kill and the shockwave resolve | shockwave ring expands to 6 u over 12 ticks |
| recover | coil_00 → coil_01 | one-shot | first 24 ticks of the next idle | — |

### 1.3 thicc ben — Image 3 = "thiccben.png"
Frames: `thiccben_00` (the single PNG); teleport is VFX.

| state | frames | loop | timing (binding) | effect |
|---|---|---|---|---|
| spawn | thiccben_00 | one-shot | 30 ticks | common fade |
| idle (parked) | thiccben_00 | loop | until 75 ticks before the next teleport (interval 801 ticks = 13.35 s) | none — a clock tower does not bob |
| telegraph | — at the DESTINATION: black smoke column | one-shot | 75 ticks (1.25 s); ben's own sprite fades alpha 1 → 0 over the first 30 ticks at the old position | smoke: 24 dark puffs `#031A1B`, 1.2 u wide, rising 2 u; in the last 30 ticks (0.5 s, the chime) the smoke pulses red twice |
| attack — arrival | thiccben_00 | one-shot | appears at full alpha on tick 75, the tick the lock is resolved | white flash on the sprite, 6 ticks |
| attack — ring (on touch) | thiccben_00 | one-shot | 18 ticks | sprite rocks ± 8° twice; a ring wave expands to 8 u (the cleanse radius) in 18 ticks |
| recover | thiccben_00 | — | — | — |
Player-side: screen blur 180 ticks (3.0 s, binding), strength 1 → 0 linearly over the last 60 ticks.

### 1.4 Isagi — Image 4 = "isagi_idle.jpeg", Image 5 = "ISAGI_SHOOT.webp", Image 6 = "blueballprojectile.webp"
Frames: `isagi_idle_00`, `isagi_shoot_00`, `isagi_ball_00`. ENEMIES.md: no prepare frame exists — the
wind-up is the idle pose with a telegraph flash.

| state | frames | loop | timing (binding) | effect |
|---|---|---|---|---|
| spawn / relocate-in | isagi_idle_00 | one-shot | 30 ticks | common fade (relocation: fade out 18, fade in 30) |
| idle | isagi_idle_00 | loop | — | — |
| telegraph (wind-up) | isagi_idle_00 | one-shot | 72 ticks (1.2 s) | red rim flash, period 24 → 12 → 6 ticks (three accelerating thirds); a thin red aim line from 1.0 u above his tile to the player, re-aimed each tick until release |
| attack (burst) | isagi_shoot_00 | one-shot | shown from tick 72; balls leave on ticks 72, 81, 90 (0.15 s apart); held until tick 102 | each ball: `isagi_ball_00` billboard, 1.0 u wide, spinning 720°/s, blue trail 0.6 u |
| recover (cooldown) | isagi_idle_00 | loop | 150 ticks (2.5 s) | sprite at 70% brightness = "cannot fire" |

### 1.5 nuke — Image 7 = "NUKE.jpeg"
Frames: `nuke_00`…`nuke_03` (missile with four booster-flame variants). The launcher has no body.

| state | frames | loop | timing (binding) | effect |
|---|---|---|---|---|
| spawn | — | — | — | no sprite; the first lock ring is its entrance |
| telegraph — tracking | ground ring only | loop | 150 ticks (2.5 s) | red ring radius 5 u following the player; it blinks with the beep: 2 Hz at tick 0 rising linearly to 8 Hz at tick 150 |
| telegraph — locked | ground ring, solid | one-shot | 90 ticks (1.5 s) | ring stops and fills from the rim inward; full on tick 90 |
| attack — descent | nuke_00→01→02→03 | loop at 12 fps (5 ticks per frame) | the same 90 ticks; the missile billboard (3 u tall) travels from 30 u above the ring centre to the ground, arriving on tick 90 | — |
| attack — explosion | — (VFX) | one-shot | starts on tick 90 = the tick the 5 u sphere resolves; 24 ticks | white core 6 ticks, then an orange-to-red sphere expanding to 5 u, then smoke |
| recover | — | — | 300 ticks (5.0 s) | nothing on screen |

### 1.6 YOU?! — Image 8 = "character to be corrupted.png"
Frames: `you_00`…`you_04` (the base character with five corruption-glitch variants).

| state | frames | loop | timing (binding) | effect |
|---|---|---|---|---|
| spawn | you_00 | one-shot | 30 ticks | common fade + horizontal tear |
| idle / chase | you_00→04 | loop at 8 fps (7–8 ticks per frame) | — | run-cycle bob |
| telegraph (rumble) | you_00→04 | loop at 16 fps (double speed) | 90 ticks (1.5 s) | sprite shakes ± 0.05 u; RGB-split grows 0 → 6 px; a thin red ring at its feet shows the plane the shockwave will travel in |
| attack (ring release) | you_04 | one-shot | shown on tick 90 = the tick the ring starts expanding (9 u/s to 14 u) | the ring is drawn as a 1.0 u TALL translucent red band, not a ground decal, so its height is readable |
| recover | you_00→04 at 8 fps | loop | 240 ticks (4.0 s) cooldown | — |

### 1.7 gift Larper — Image 9 = "tripine.png"
Frames: `larper_00`…`larper_04` (the tripmine turning, light pulsing).

| state | frames | loop | timing | effect |
|---|---|---|---|---|
| spawn | larper_00 | — | present from level start (it is a slot occupant, no fade) | — |
| idle | larper_00→04 | loop | 1 revolution per 4.0 s (binding): 48 ticks per frame | particles and glow per §2.1 (the deception rule) |
| telegraph | — | — | none: its tell is the look, within 12 u | — |
| attack — detonation | — (VFX) | one-shot | on the contact tick; 18 ticks | white flash, pink-to-black burst to 3 u |
| defused / shielded | larper_00 | one-shot | 24 ticks | sprite greys out and drops 0.5 u while fading; a small "pff" puff — no blast |

### 1.8 toucher — Image 10 = "toucher.jpeg", Image 11 = "glitchedground.jpeg"
Frames: `toucher_00`…`toucher_02` (finger, three flicker variants); `glitchfloor_00`…`glitchfloor_04`.

| state | frames | loop | timing | effect |
|---|---|---|---|---|
| spawn | toucher_00 | one-shot | 30 ticks | common fade |
| idle / chase | toucher_00→02 | loop at 10 fps (6 ticks per frame) "flickering back to back" | — | the finger always points at the player (the sprite may be mirrored horizontally; it is never rotated) |
| telegraph (glitch pulse) | toucher_00→02 at 20 fps | one-shot | the 18 ticks before each infection (infection every 120 ticks = 2.0 s, binding) | sprite scale 1.0 → 1.15 |
| attack — infect | toucher_02 | one-shot | on the infection tick | new tiles appear per §2.2 |
| attack — touch | — | — | contact kills on overlap | — |
| recover | — | — | — | — |

### 1.9 seal — Image 12 = "babehseal.webp"
Frames: `seal_00` (base), `seal_01` (mouth open), `seal_02` (flippers up), `seal_03` (flippers down).

| state | frames | loop | timing (binding) | effect |
|---|---|---|---|---|
| spawn | seal_00 | one-shot | 30 ticks | common fade |
| idle / flap | seal_02 ↔ seal_03 | loop, 9 ticks per frame | — | — |
| telegraph | seal_01 (mouth open), held | one-shot | 45 ticks (0.75 s) | dashed red line along the 3D dash line, 20 u long, dash segments 0.5 u; it brightens over the 45 ticks |
| attack (dash) | seal_01 with seal_02/03 flap overlay, 4 ticks per frame | one-shot | 60 ticks (1.0 s), 20 u; the bark plays on tick 0 of the dash | speed streak behind the sprite |
| recover | seal_00 | one-shot | 45 ticks (0.75 s) | — |

### 1.10 address me — Image 13 = "address me elephant.png", Image 14 = "explosionsffect.jpg"
Frames: `addressme_00` (normal), `addressme_01` (explode frame).

| state | frames | loop | timing (binding) | effect |
|---|---|---|---|---|
| spawn | addressme_00 | one-shot | 12 ticks (faster than the common fade: its trumpet is the tell) `[CONTESTABLE]` | appears 6 u in front of the player |
| telegraph (countdown) | addressme_00 | loop | 300 ticks (5.0 s) | a red ring around the sprite drains clockwise over the 300 ticks; the sprite's tint goes neutral → amber at tick 150 → red at tick 240; a second, green arc fills while the player is still (90 ticks = 1.5 s to fill) and empties the moment they move |
| leaves (answered) | addressme_00 | one-shot | 18 ticks | shrinks to 0 with a soft puff |
| attack (explode) | addressme_01 | one-shot | shown on tick 300 = the tick the kill resolves; 24 ticks | full-screen white flash 6 ticks |
| recover | — | — | 30–45 s away (−5 s per extra vote) | — |

### 1.11 Claude — Image 15 = "claudelogo.png" + clawd Crab plushie
Frames: `claude_00` (logo); `plushie_00`…`plushie_02` (plushie idle).

| state | frames | loop | timing (binding) | effect |
|---|---|---|---|---|
| spawn | claude_00 | one-shot | 30 ticks | common fade |
| idle | claude_00 | loop | — | the logo rotates 15° per beat in steps (a metronome); scale pulse 1.0 → 1.06 on every beat (beat = 36 ticks at 100 BPM, shortened by the current tempo) |
| telegraph — drums | claude_00 | one-shot | the beat BEFORE beats 1 and 3 | a red ring at its feet shows the plane; logo flashes white on the hit beat |
| attack — drums | claude_00 | one-shot | ring starts on the beat (12 u/s to 18 u) | 1.0 u tall translucent red band, as YOU?!'s |
| telegraph — strings | claude_00 | one-shot | one full beat (36 ticks at 100 BPM) | a red line 24 u long at the sweep's starting angle |
| attack — strings | claude_00 | one-shot | sweep of 120° over 4 beats | red beam 1.5 u wide at 0.5–1.5 u height |
| attack — wind | claude_00 | one-shot | shots leave on beats 1, 2, 3 | each shot: a white notification dot 0.5 u with a red rim and a trail |
| Deadline (agitation 100) | claude_00, red tint | loop | until a plushie is collected | — |
| plushie idle | plushie_00→02 | loop at 6 fps (10 ticks per frame) | — | bob ± 0.1 u; soft white glow; collected = pop 9 ticks |

### 1.12 gin ichimaru — Image 16 = "gin idle.png", Image 17 = "ginsword.png"
Frames: `gin_idle_00`, `gin_launch_00`.

| state | frames | loop | timing (binding) | effect |
|---|---|---|---|---|
| spawn / fade-in | gin_idle_00 | one-shot | 30 ticks | common fade, 15–25 u from the player |
| idle | gin_idle_00 | loop | — | — |
| telegraph (mark) | gin_idle_00 | one-shot | 120 ticks (2.0 s) | the 5×5 patch gets a red outline that blinks at 2 Hz for 60 ticks then 4 Hz for 60 ticks; cracks spread from the patch centre and reach the edge on tick 120 |
| attack (launch) | gin_launch_00 | one-shot | shown on tick 120; spears travel for 18 ticks (0.3 s) | view-layer only: 5 white spear streaks from gin to the patch; never simulated |
| attack — void zone | — | — | starts on tick 138 = the tick the tiles become non-solid; lasts 600 ticks (10 s) | tiles vanish; a dark column with a red rim marks the lethal volume |
| recover | gin_idle_00 | loop | tiles fade back over 30 ticks (0.5 s); cooldown 840 ticks (14 s) | he fades out 60 ticks after the launch and fades in again for the next strike |

---

## 2. VFX specs

Palette values are TERRAIN_SPEC §12.2 and DESIGN.md §10; nothing here adds a colour. All particle
systems are view-layer only and never read by the simulation. Sizes and rates below are
`[CONTESTABLE]` unless marked binding.

### 2.1 Tripmine — the deception rule
Canon: "black framed box, six-pointed star center, constant pink particles, slow rotation, glows like
a normal gift at distance but visibly wrong up close". DESIGN.md §3.3 (binding): beyond 12 u it shows
the same rim glow as a black gift; inside 12 u the particles and star are visible.

| element | spec |
|---|---|
| body | the T-015 tripmine box, 0.6 u cube, at the slot position; 5-frame turn, 1 revolution per 4.0 s (binding) |
| rim glow | identical to a black gift: `#7CFFF4` × 1.5 emission, at EVERY distance — this is the lie |
| star | six-pointed, on all four side faces, `#FF4FD8`, emission 1.0; alpha 0 beyond 14 u → 1 at 10 u |
| particles | **constant** (the emitter never stops, including beyond 12 u): 12 particles/s, lifetime 1.5 s, size 0.06 u, colour `#FF4FD8`, rising 0.4 u/s with ± 0.2 u drift, emission 2.0. Their alpha follows the same ramp as the star: 0 beyond 14 u → 1 at 10 u |
| readability | inside 12 u the particles must pass the fog check: contrast ≥ 4.5 against fog at 12 u in every biome (T-054's `fog_check.gd` gets this row) |
| up-close tells | at ≤ 4 u: the box is visibly a FRAME (hollow edges, a gift is solid), it turns (a gift bobs), and it has no ribbon |
| trigger ring (fun risk 8) | a faint `#FF4FD8` ground ring of radius 0.9 u, alpha 0.25, visible inside 12 u — shows the cylinder the player must stay out of |
| Method Acting (curse) | the ramp becomes 0 beyond 7 u → 1 at 5 u |
| Radar Module: Mines | pink outline through fog within 14 u, regardless of the ramp |

`[CONTESTABLE]` note on wording: this pass's brief says the particles are "readable at distance".
DESIGN.md §3.3 fixes the tell at 12 u. I kept DESIGN.md: the emitter is constant, the READABILITY
starts at 12 u. If "at distance" was meant to be farther, the two ramp numbers above are the only
things to change.

### 2.2 Glitched floor (toucher)
| element | spec |
|---|---|
| look | `glitchfloor_00…04` as a decal covering the tile top, cycling at 8 fps (7–8 ticks per frame), each tile offset by `(x + z) mod 5` frames so neighbours do not flash in unison |
| appear | on the infection tick: decal alpha 0 → 1 over 12 ticks, with a 1-tile-high vertical "tear" flash in danger red for 6 ticks (the squelch cue plays on this tick) |
| body | the tile keeps its checker underneath at 40% brightness, so the path stays readable |
| expire | the last 60 ticks (1.0 s) of its 12 s life (18 s from level 14, binding): the decal flickers at 10 Hz, then alpha → 0 over 12 ticks |
| on the player | while standing on it: a thin glitch vignette at the screen edge and the class-ability icon struck through (the lock) |
| ben's cleanse | tiles inside 8 u lose the decal in an outward wave over 18 ticks |

### 2.3 Beacon
| state | spec |
|---|---|
| CLOSED | `#3A4A55`, emission 0; the T-015 beacon mesh (a 3×3-tile-footprint, 4 u tall obelisk with a doorway) with the doorway filled by a dark slab; a dim ring of 8 unlit segments around the dais edge lights one segment per 12.5% of real black gifts collected (the progress read-out in the world) |
| opening | on the tick the last real black gift is collected: the slab splits and slides away over 36 ticks (0.6 s); emission ramps 0 → 4.0; the light column rises from the dais to Y +60 u over the same 36 ticks; one white shock ring crosses the hub (cosmetic) |
| OPEN | `#E8FFFF`, emission × 4.0, light column `#E8FFFF` 1.5 u wide, alpha 0.6, visible through fog from anywhere in the level; slow pulse 0.9 → 1.0 at 0.5 Hz; doorway glows |
| entering | the trigger cylinder (r 1.5 u, h 3 u, binding): screen fades to `#E8FFFF` over 18 ticks; the HUD pip restore (2.4) plays during the fade |
| blocked (Crowded Dais / Slow Door curses) | column turns danger red while entry is refused; Slow Door shows a ring filling over 180 ticks |

### 2.4 HUD — void charge pips, Last Light, death attribution
| element | spec |
|---|---|
| pips | bottom-left, 24 px from each edge; one pip per holdable charge (2, or 1 under Hungry Void — binding); each a 28 px diamond; held = filled `#7CFFF4` with emission; spent = 2 px outline `#3A4A55` |
| spend | on the fall tick: the pip cracks and drains downward over 18 ticks, the screen edge flashes void colour once |
| restore | on beacon entry: the first hollow pip fills upward over 24 ticks with a white glint; if already full, the pips pulse once (so the player learns nothing was gained) |
| free fall (Field Dressing) | the pip flashes white and stays filled; a small "FREE" tick appears for 60 ticks |
| Last Light icon | right of the pips, 28 px: lit (white, soft glow) while unspent AND charges ≥ 1; dim (40% alpha) at 0 charges; grey with a slash once spent (binding states, D-053) |
| Last Light trigger | full-screen white bloom 12 ticks, the icon shatters, the player appears on the dais |
| death attribution | within 2.0 s of death (binding): black-out over 18 ticks → the run-over screen. Centre: the killer's own sprite (its attack frame) at 256 px; under it the killer name in danger red, e.g. `gift Larper (Tripmine)`; under that the death code in small mono type, e.g. `D-MINE`; then level reached, purse, charges held at death. Void death: no sprite — the void colour and `The Void` / `D-VOID`. Curse death: the curse icon and `D-CURSE:<id>` |
| retry | one button, `Retry`, focused by default |

### 2.5 Void fall and respawn
| moment | spec (durations binding where DESIGN.md gives them) |
|---|---|
| fall | below the kill plane: camera stops following down, player sprite shrinks into the fog over 12 ticks |
| charge spent | pip spend animation (2.4) |
| wait | 48 ticks total (0.8 s, binding; 0 at Sure Foot ×2): screen desaturates to void colour and back |
| reappear | on the last safe tile: a vertical white streak 3 u tall collapses onto the tile over 9 ticks; a ground ring expands to 1.5 u |
| invulnerability | 60 ticks (1.0 s, binding): the player model blinks at 8 Hz with a white rim; the rim disappears on the tick invulnerability ends |
| death at 0 charges | no streak, no reappear: straight to death attribution with `D-VOID` |

---

## 3. Sound design briefs

Rules: every sound is NEW and synthesized by `tools/synth_audio.py` (stdlib `wave` + `math`); nothing
is taken from Nullscape or any recording. **Cue-first**: every lethal threat has an audio cue that
starts at or before the start of its visual telegraph and ends on the attack tick, so the binding cue
time is exactly the warning the player gets. Each cue also has the visual telegraph of section 1 —
audio is never the only tell (fun risk 9). File name = `content/enemies/<id>/audio/<cue>.wav`,
44.1 kHz mono 16-bit. Synthesis recipes are `[CONTESTABLE]` placeholders for a later real sound pass;
the TIMINGS are binding.

Three ENEMIES.md "New sound" lines name sounds that cannot be synthesized as written because they
are existing recordings: thicc ben "the real Big Ben bell chime", Isagi "direct shot voice lines …
gun-shot sound", gift Larper "Roblox tripmine explosion sound effect". Per the TBD FALLBACK rule each
gets a synthesized stand-in below, is marked `"tbd_audio": true`, and gets a TBD.md row. The run does
not stop for them.

| enemy | cue | when it plays (binding) | length | brief for the synth |
|---|---|---|---|---|
| kiwi cat | `meow` | every 180 ticks while within 14 u | 0.35 s | sine glide 700 → 1100 → 600 Hz with vibrato 8 Hz; soft attack. Volume rises as it closes |
| kiwi cat | `meow_double` (Zoomies) | two meows 12 ticks apart, then the sprint | 0.6 s | the same, pitched up a fourth |
| coil | `boing` | at pre-jump cue start; lasts the whole 36-tick cue | 0.6 s | sine with a fast downward-then-upward pitch wobble 220 ↔ 440 Hz at 12 Hz, decaying |
| coil | `twang` | on the landing tick | 0.4 s | metallic: three inharmonic sines (310, 827, 1340 Hz) with a 0.4 s decay + a low thump at 70 Hz |
| thicc ben | `chime` (TBD stand-in) | the LAST 30 ticks (0.5 s) of the 75-tick smoke | 0.5 s | four bell notes of the Westminster phrase compressed into 0.5 s: bell = sines at 1×, 2.0×, 2.4×, 3.0× with a 1.5 s tail that rings on after arrival. Synthesized notes, not a recording |
| thicc ben | `bong` | on touch (the ring) | 1.8 s | one deep bell at 98 Hz with the same partials, long tail |
| Isagi | `windup` (TBD stand-in) | at wind-up start; fills the 72-tick wind-up | 1.2 s | a rising whoosh: band-limited noise sweeping 300 → 3000 Hz, ending in a short silence of 3 ticks before the shot |
| Isagi | `shot` (TBD stand-in) | on ticks 72, 81, 90 (each ball) | 0.12 s | noise burst with a 60 ms decay + a 150 Hz thump |
| nuke | `lock_beep` | during tracking: beep rate 2 Hz → 8 Hz linearly over 150 ticks | 0.05 s each | 1200 Hz square blip |
| nuke | `locked` | on the tick the ring stops | 0.2 s | two-tone 1200 → 1600 Hz |
| nuke | `descent_roar` | the 90-tick descent | 1.5 s | low-passed noise, cutoff falling 2000 → 200 Hz, rising volume; ends on the impact tick |
| nuke | `boom` | impact tick | 1.2 s | 45 Hz sine thump + noise burst, long tail |
| YOU?! | `static_build` | the 90-tick rumble | 1.5 s | quiet white noise gated at 30 Hz, rising volume, with a reversed-envelope tone 400 → 900 Hz in the last 0.5 s — ends on the ring tick |
| YOU?! | `ring_release` | ring tick | 0.3 s | a short downward chirp 900 → 200 Hz |
| gift Larper | `mine_blast` (TBD stand-in) | contact tick | 0.8 s | sharp click + noise burst + 60 Hz thump |
| gift Larper | `mine_dud` | defused / shielded | 0.3 s | a falling "pff": noise with a fast low-pass sweep down |
| gift Larper | `mine_hum` | loops inside 6 u | loop | very quiet 180 Hz hum with a slow 0.5 Hz tremolo — a second, close-range tell |
| toucher | `squelch` | on each infection tick that adds tiles | 0.4 s | low noise burst through a wobbling band-pass (200–600 Hz at 15 Hz) + bit-crush |
| toucher | `prowl` | loops while within 14 u | loop | granular clicks at an irregular 6–10 Hz, volume by distance |
| seal | `bark` | on tick 0 of the dash (the telegraph itself is silent except `flap`) | 0.25 s | two quick sawtooth yelps at 500 and 650 Hz, 60 ms each |
| seal | `flap` | loops while flapping; twice as fast during the 45-tick telegraph | loop | soft filtered noise slaps at 3.3 Hz (6.6 Hz in the telegraph) — the speed-up IS the audio tell |
| address me | `trumpet` | on appearance | 0.9 s | brass-like: sawtooth 233 Hz with a rising formant sweep, a second voice a fifth above |
| address me | `rumble` | the 300-tick countdown | 5.0 s | 40 Hz sine with a slow tremolo that speeds up 1 → 6 Hz; ends on the explode tick |
| address me | `boom` | explode tick | 1.2 s | as the nuke's, pitched lower |
| address me | `leaves` | answered | 0.3 s | soft descending two-note |
| Claude | `beat` | every beat at the current tempo | 0.05 s | soft tick at 880 Hz — the metronome the player dodges to |
| Claude | `drum_hit` | beats 1 and 3 of a drums bar; a quieter pre-hit one beat earlier | 0.2 s | UI chime: sine 660 Hz + 1320 Hz, fast decay |
| Claude | `string_sweep` | the telegraph beat, then through the 4-beat sweep | 1 beat + 4 beats | rapid keystroke ticks (noise clicks) at 16 per beat, rising in pitch through the sweep |
| Claude | `wind_ping` | beats 1, 2, 3 of a wind bar | 0.15 s | notification ping: 1568 Hz then 2093 Hz |
| Claude | `plushie_pop` | plushie pickup | 0.2 s | a squeak (sine 1200 → 1800 Hz) and a pop |
| gin ichimaru | `crack_rumble` | the 120-tick mark | 2.0 s | low crackle: noise clicks at a rate rising 4 → 20 Hz over a 50 Hz drone |
| gin ichimaru | `shing` | launch tick (tick 120) | 0.3 s | bright metallic sweep: sine 2000 → 6000 Hz with a short noise tail |
| gin ichimaru | `whoosh` | the 18-tick spear flight | 0.3 s | band-passed noise sweeping down |
| gin ichimaru | `zone_open` / `zone_close` | zone start / tiles returning | 0.4 s each | a hollow drop / its reverse |

System sounds (same rules): `gift_black`, `gift_gold` (pitch rises one semitone per chain step, cap
at ×2.00), `chain_break`, `beacon_open`, `beacon_enter`, `charge_spent`, `charge_restored`,
`last_light`, `respawn`, `overtime_tick` (one low toll per tier), `altar_confirm`, `gate_open`.

---

## 4. FLEET_PACK.md sweep — where a worker would have to invent, and the missing line

Method: I re-read every ticket's Do and Done-when and asked "which number, timing or visual would the
worker have to make up?". Existing tickets are not edited. Each row is a **dispatch addendum**: the
orchestrator appends the line, verbatim, to that ticket's brief when it dispatches it (run plan, rule
R4). All addenda are `[CONTESTABLE]` — they are my numbers, stated so the worker does not invent its
own. The sweep was done from my reading of FLEET_PACK.md at `14be164`; I did not re-diff it line by
line in this pass, so a gap I did not notice may remain.

| ticket | what is missing | the missing line (append verbatim) |
|---|---|---|
| T-001 | what `tools/harness.ps1` runs | "`tools/harness.ps1` runs exactly: `python terrain_ref\validate.py --seeds 0:5000` and exits with its exit code." |
| T-010 | the canonical state dump | "State hash = SHA-256 of a UTF-8 text dump: one line per field, fields in a fixed order written in `state_hash.gd`, ints in decimal, floats as the 16 hex digits of their 64-bit pattern, arrays in index order, dictionaries by sorted key. Never hash a float's decimal string." |
| T-011 | the four camera views of `tools/shot.gd` | "Views, camera looking at the beacon tile: (1) from (0, 40, 40) u; (2) from (40, 25, 0) u; (3) top-down from (0, 90, 0) u, orthographic 140 u wide; (4) player's-eye: from (6, 3, 6) u on the hub looking along +x. FOV 75°." |
| T-011 | the texture grain | "Grain = per-texel lightness × (0.94 + 0.12 × (mix(x·8 + px, z·8 + pz) & 255) / 255), with `mix` from `void_rng.gd`. Static." |
| T-012 | acceleration and friction | "Ground and air: velocity moves toward the input target at 90 u/s² (full speed in 0.1 s), same for stopping. A `friction` multiplier (default 1.0) scales that 90; slippery surfaces set it to 0.4. External pushes are added as a separate velocity that decays linearly to 0 over the push's stated time." |
| T-012 | no ticket owns the camera, key bindings or settings | "Out of scope here — see T-082." |
| T-013 | the stat list ends in '…' | "The closed stat list is exactly: run_speed, jump_velocity (never modified by content), gravity (never modified by content), coyote_time, void_charges_max, void_fall_charge_cost, free_falls_per_level, defuse_chance, barrier_shields, glitch_slow_mul, respawn_delay, respawn_invuln, pickup_radius, gold_value, gift_yield_mul, chain_window, chain_cap, chain_step, stipend_flat, beacon_flat_gold, shop_price_mul, bounty_mul, interest_pct, interest_cap, fog_density, fill_light_range, gift_glow_range, mine_tell_range, radar_range, enemy_speed_mul, enemy_cooldown_mul, telegraph_mul, overtime_period, overtime_step, spawn_delay, ability_cooldown_mul, air_jumps, air_jump_height_mul, fall_speed_cap, push_taken_mul, friction. A stat a table row needs that is not here is a SPEC GAP: add it to this list in the same commit and name it in the response." |
| T-014b | which upgrades each class 'boosts' (weight ×2) | "Class boosts: Dasher — quick_recovery, twin_dash. Glider — featherfall, updraft, quick_recovery. Athletic — yearn_for_speed, spring_heels, marathon." |
| T-014b / T-022 | rounding | "All gold arithmetic is in integer centi-gold and rounds DOWN. A stacked price is `floor(price × 1.5^n)` in whole gold. A bounty is `floor(base × (20 + level) / 20)` in whole gold." |
| T-015 | model dimensions | "Sizes in u (w × h × d): black gift and gold gift 0.6 cube with a ribbon band; tripmine 0.6 cube, hollow frame edges 0.08 thick, star on four faces; beacon 3 × 4 × 3 obelisk with a 1.2 × 2.4 doorway on each side; altar plinth 1.2 × 1.0 × 1.2; descent gate 3 × 4 × 0.6 arch; urn 0.8 × 1.2 × 0.8; barrel 0.8 × 1.0 × 0.8; tall jar 0.5 × 1.6 × 0.5; launch pad 1.0 × 0.1 × 1.0; player figure 0.8 × 1.8 × 0.5 (head, torso, two arms, two legs as boxes)." |
| T-016 | how the derived frames are made | "Overlays, all seeded by `mix(enemy_index, frame)` so a rebuild is byte-stable: corruption (YOU?!, toucher) = shift 3 horizontal bands of 6–18 px height by ± 6 px, offset the red channel 2 px right and the blue 2 px left, drop 2% of opaque pixels to alpha 0 INSIDE the body only (never touch the outline); coil = scale the base vertically to 50, 65, 80, 100, 120% keeping the base line fixed; nuke = four flame overlays of length 20, 26, 22, 30% of the missile, colours `#FFC83D` → `#FF2A2A`; gift Larper = the base rotated in 5 steps of horizontal squash 100, 70, 30, 70, 100% with the light at 60, 80, 100, 80, 60% brightness; seal = mouth-open by a dark ellipse 18% of body width at the muzzle, flippers by rotating the lower 25% of the sprite ± 12°; address me explode = Image 14 composited over the elephant at 100% size, the elephant at 30% alpha." |
| T-016 | world size per sprite | "World height per enemy is the body-size table of DESIGN.md §5 written by T-070; until T-070 merges use research/fable-enemies.md F2." |
| T-020 | pickup test, gift idle motion, beam size | "Pickup when the horizontal distance from the player's centre to the slot position is ≤ `pickup_radius` (0.4 u) + 0.4 u and the vertical distance from the player's feet to the slot's tile top is ≤ 2.0 u. Gifts bob ± 0.1 u at 0.5 Hz and spin 45°/s (a tripmine turns, it does not bob). Straggler beam: 0.3 u wide, alpha 0.5." |
| T-023 | banner font, class exhibit colours | "Banners use the engine's default font, bold, all capitals, 0.9 u tall, emissive; subtitle 0.35 u italic. No font file is downloaded. Class colours: Dasher `#FF9A3D`, Glider `#7CFFF4`, Athletic `#B6FF5A`." |
| T-024 | what Settings contains | "Settings: master volume 0–100 (default 80), mouse sensitivity 0.02–0.30 °/px (default 0.12), field of view 60–90° (default 75), fullscreen on/off (default off), stored in `user://settings.json`." |
| T-025 | HUD sizes and the run-over layout | "Follow research/fable-tickets.md §2.4 exactly." |
| T-026 | what `--dodge` does when a telegraph arrives | "`--dodge` plays the documented answer for that telegraph, 15 ticks after the event: the answer table is research/fable-enemies.md §4 (leave the ring; hurdle on arrival; jump on the bark; stop at once; step behind a 2 HU rise). The same table drives T-075's answer bots — one implementation in `tools/bot/answers.gd`." |
| T-027 | the diegetic spawn line per enemy | "Spawn lines: THE KIWI CAT SHALL FOLLOW · THE COIL SHALL SPRING · THICC BEN SHALL TOLL · ISAGI SHALL SHOOT · THE NUKE SHALL SEEK · YOU SHALL ECHO · THE GIFT LARPER SHALL PRETEND · THE TOUCHER SHALL TOUCH · THE SEAL SHALL BARK · THE ELEPHANT SHALL BE ADDRESSED · CLAUDE SHALL COMPOSE · GIN SHALL SEVER. A TBD enemy shows TBD SHALL ARRIVE." |
| T-027 | the line-of-sight ray | "`api.los(a, b)`: sample the 3D segment every 0.25 u; blocked if a sample lies inside a tile slab (1 u thick below the tile top) or inside a prop box. Player and enemy sample points are their centres." |
| T-027 | when a body can first hurt | "A body cannot touch or kill during its 30-tick spawn fade (research/fable-tickets.md §1.0)." |
| T-030…T-041 | animation states, VFX, audio cue names | "Animation table: research/fable-tickets.md §1.x for this enemy. Audio cue names and timings: §3. Build both exactly; the test asserts the attack frame is shown on the tick the attack resolves." |
| T-050 / T-051 | 'slippery (friction ×0.4)' has no stat | "Slippery = the `friction` stat set to 0.4 while on the surface (T-012 addendum)." |
| T-053 | radar and minimap visuals | "Radar arrows: 24 px chevron at the screen edge pointing at the target, with the distance in u under it. Cartographer minimap: 220 px square, top-right under the purse, north-up, pieces as filled shapes in their biome colour, real gifts as 2 px dots, the player as a white triangle. Pocket Beacon channel: a ring around the player filling over 180 ticks, cancelled by any input." |
| T-055 | every cue's name, timing and recipe | "Follow research/fable-tickets.md §3 exactly; superseded in detail by T-087." |
| T-060 | what 'seeded random votes' means | "At each altar the bot picks altar index `rng.range(3)` from the run's own seeded stream; it buys the cheapest affordable upgrade and always pays no tithe." |
| T-061 | the perf probe's camera and scene | "Perf probe: level 30, seed 7, 22 enemies placed by a fixed vote list (kiwi 3, coil 2, ben 2, seal 2, YOU?! 1, nuke 2, Larper 2, toucher 1, address me 2, Isagi 1, Claude 1, gin 3), the bot playing with `--dodge`, camera in normal third-person; measure 600 frames after 120 warm-up frames, windowed 1920×1080, v-sync off. Report the machine's CPU and GPU names in the output." |
| A13 | which machine | "The reference machine is the one the run executes on; the probe prints its hardware so the number can be read in context." |

What the sweep did NOT cover: the enemy-system numbers (floater altitude, body sizes, pursuit
ceilings…) — they are T-070's job and are listed in research/fable-enemies.md; and the 17 post-run
preflight items, which stay open by the owner's instruction.

---

## 5. New tickets — full specs

House format. The short entries and the run order are in FLEET_PACK.md §9A and §10.

**STANDING CLAUSE — part of every ticket in this section; the orchestrator pastes it into each brief:**
> FROZEN: ENEMIES.md behavior sentences are the spec (D-040). The 12-enemy roster, the terrain shape
> contract (D-025) and every decision marked FINAL are not yours to change. Existing FLEET_PACK
> tickets are not edited. If this ticket contradicts ENEMIES.md, a FINAL decision or another ticket,
> do NOT resolve it: add a row to `PARKED.md` (ticket id, the two conflicting passages, what you built
> meanwhile), build the reading closest to ENEMIES.md, and continue. A number no document states is a
> SPEC GAP: write it into DECISIONS.md as [CONTESTABLE] with its gameplay reason BEFORE the code that
> uses it. Blocked on a name or an asset: TBD fallback (name "TBD", placeholder PNG or synthesized
> stand-in, full behavior wired, TBD.md row) — never stall. Never weaken a check to pass it.

### T-070 — Enemy systems fix  [MANDATORY, first]
THE OWNER'S SPEC: "T-070 enemy systems fix … apply the 14 enemy rules from research/fable-enemies.md as ruled by the owner, plus the Isagi lane ruling (D-056 stays FINAL; volley gap or ~4 s dwell limit so he is answerable even under Egoist) and the nuke ruling (missile life limit 6 s; props, spires and bastion walls block it). Standing criterion logged in the ticket: every rule must leave every enemy answerable in the counter-play map; any rule that fails gets parked with a written reason."
Assignment: spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
(Note: research/fable-enemies.md §6 assigned T-070 to DeepSeek V4.1; the owner's run plan assigns it to GLM 5.3 Flash. The run plan wins.)
Read: research/fable-enemies.md (all), DESIGN.md §5–§7, DECISIONS.md D-040, D-051, D-053, D-056, D-059, D-061, FLEET_PACK.md Wave 3 block.
Do — a DOCUMENT ticket (DESIGN.md §5/§6/§7.1, FLEET_PACK.md Wave 3 block by appended lines only, DECISIONS.md new entries, PARKED.md). Apply, each with its numbers:
1. Floater altitude: feet ease toward the target's feet at 2.0 u/s (F1).
2. Body-size table for all 12 (F2).
3. Coil: landing target = the player's last grounded tile; shove = 8 u/s decaying linearly to 0 over 0.5 s.
4. Copies of one enemy: cycle offset k/n; chaser copies spawn ≥ 30 u apart (F7).
5. Scheduling: address me appears only when no enemy body is within 12 u, no ring/patch is on the player, the player is grounded and not on glitched floor; gin does not mark during address me's countdown (F8).
6. Pursuit ceilings (kiwi cat 0.80, kitten 0.70, YOU?! 0.55, toucher 0.75, seal 0.60, Claude 0.55 of base run speed), bursts ≤ 1.00 for ≤ 3.0 s, overflow converted to tempo with a 60% floor (§5.1).
7. Seal: the dash is a fixed 3D line; telegraph only from 4–12 u; cleared by a jump on the bark, a 3 HU step, or a 0.7 u sidestep; Pup Pack text "jump each bark" (§5.2).
8. Ability lock per class incl. Athletic stride lock (§5.3).
9. Claude's wind shot: 7.0 u/s, 90°/s, life 4.0 s, dies on any tile slab or step riser.
10. Isagi — THE OWNER'S RULING: D-056 stays FINAL (he may still fall back to a `lane` anchor). Make him answerable there even under Egoist by BOTH of: (a) volley gap — a burst is fired in volleys of at most 3 balls 0.15 s apart, and consecutive volleys of one burst are separated by 0.75 s (45 ticks = one full jump), so each volley is cleared by its own jump; (b) dwell limit — on a `lane` anchor he stays at most 4.0 s (240 ticks) before relocating. `[CONTESTABLE]`: the owner wrote "volley gap or ~4 s dwell limit"; I specify both because (a) answers Egoist and (b) removes the parked body from the path. Supersedes the "does not wind up along a flat in-line walkway" proposal of research/fable-enemies.md §4.
11. Nuke — THE OWNER'S RULING: missile life limit 6 s; props, spires and bastion walls block it. Reading `[CONTESTABLE]`: one salvo (tracking, including restarts after a broken lock, plus descent) lasts at most 6.0 s (360 ticks) from its first tracking tick — if it has not detonated by then it expires harmlessly and the 5.0 s pause starts; the line-of-sight ray and the descending missile are blocked by any prop, any `spire` pad and any `bastion` tower (and by any tile slab): a missile that meets one detonates there. Counter-play text names both answers: leave the sphere, or get under/behind one of those.
12. gin stands on platform tiles only (farthest hub tile as fallback).
13. Last Light's arrival pushes enemy bodies within 8 u of the dais out to 8 u (no kill).
14. First-shown levels, vote caps, chaser ceiling 6, and the NEW / REPEAT / FREE altar rule (sections 1 and 3).
15. Wet Floor keeps "slippery" and loses its extra slow.
Then rewrite every counter-play line in DESIGN.md §5 and §7.1 to the answers of research/fable-enemies.md §4, and APPEND to the FLEET_PACK Wave 3 block one line per enemy: "Answer window to assert: …".
STANDING CRITERION (logged in this ticket by the owner): every rule must leave every enemy answerable in the counter-play map. For each rule write one line in the response: which row of the counter-play map it touches and why that row still has an answer. A rule that leaves a row without an answer is NOT applied: it is parked in PARKED.md with the written reason.
Rules "as ruled by the owner": apply a rule as FINAL only if DECISIONS.md or the owner's ticket text says so (items 10 and 11 above are owner rulings). Every other item is logged as a new DECISIONS entry marked [CONTESTABLE], numbered from D-064 upward.
Done-when: all 15 items are in DESIGN.md with numbers or parked with a reason; DESIGN.md §7.1 + §7.2 = 46 rows, §8 = 36 rows, ids unique; `git diff --stat ENEMIES.md` is empty; D-056's text is unchanged; the answerability line exists for every rule.

### T-071 … T-076 — enemy systems implementation
Specs unchanged from research/fable-enemies.md §6: T-071 floater kinematics, ceilings, stagger (GLM) · T-072 scheduling arbiter and class ability lock (GLM) · T-073 enemy data pass (Inkling) · T-074 offer draw NEW/REPEAT/FREE, caps, chaser ceiling (GLM) · T-075 answerability harness (GLM) · T-076 counter-play text and tips (Inkling). Add to T-071: the nuke salvo life limit and blocking (item 11) and Isagi's volley gap and dwell limit (item 10) are tested in `test_floaters.gd`'s sibling `test_ranged.gd`: a 7-ball Egoist burst arrives as 3 + 3 + 1 with 45-tick gaps; a nuke salvo never outlives 360 ticks; a missile over a `spire` pad detonates on the pad.

### T-080 — Telemetry event log  [MANDATORY c]
THE OWNER'S SPEC: "Telemetry event-log ticket … log every death with killer, every void fall, every charge spent and restored, every bypass passed within 0.5 u of a mine, per-level clear time."
Assignment: spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
Read: DESIGN.md §3, §13; research/fable-funrisks.md (T-080 paragraph).
Do: `app/run_log.gd` subscribes to sim events and appends one JSON object per line to `user://runs/<run_seed>_<start_tick>.jsonl`. Every record: `t` (sim tick), `level`, `phase` (black/gold/lobby), `type`, payload. Types, exactly: `run_start` (seed, class), `level_start` (slots, real gifts, mines, enemies in play), `gift` (slot id, black/gold, chain value), `void_fall` (tile fallen from, nearest enemy distance, pushed-in-last-120-ticks yes/no and by which enemy), `charge_spent` (cause: fall; free yes/no), `charge_restored` (before, after), `mine_pass` (slot id, closest horizontal distance; logged when the player's centre comes within 0.9 u + 0.5 u = 1.4 u of a live mine centre and leaves again without contact; this is the owner's "bypass passed within 0.5 u of a mine"), `mine_contact` (slot id, outcome: defused / shielded / last_light / killed), `death` (killer id, death code, killer on screen in the last 120 ticks yes/no, charges held, Last Light state), `last_light`, `beacon_open` (tick), `beacon_enter` (tick, overtime tier, gold collected / gold available), `level_clear` (black-phase ticks, gold-phase ticks, total ticks), `offer` (bay, the three ids), `pick` (bay, id, price or bounty), `lobby_enter`, `lobby_exit`, `run_end` (level reached, purse). The log is written by the view/app layer from events only — it never reads or writes sim state, and the replay test must stay green with logging on and off.
Done-when: `tests/test_run_log.gd` — a scripted bot run of 2 levels produces a file whose records include at least one of each type that can occur, every `death` has a killer and a code from the DESIGN.md §3.1 list, `charge_spent` count − `charge_restored` gains equals the pip change, and per-level `level_clear.total` equals `level_start.t` to `beacon_enter.t`; replay hashes identical with the log enabled and disabled.

### T-081 — Fun-risk signals  [MANDATORY d]
THE OWNER'S SPEC: "Fun-risk signals from research/fable-funrisks.md … wire the eight cheap signals named there; priority is terrain-caused vs enemy-caused deaths."
Assignment: spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
Read: research/fable-funrisks.md (all), T-080's record list.
Do: `tools/run_report.gd <folder>` reads run logs and prints, per level bucket (1–5, 6–10, 11–15, 16–20, 21–25, 26–30) and overall, these eight signals — IN THIS ORDER, the first is the priority:
1. **Terrain vs enemy** (risk 3): of all charges spent, the share with no enemy within 10 u and no push in the previous 120 ticks ("terrain-caused") vs the rest ("enemy-caused"); and of all deaths, `D-VOID` with the same test vs every other code. Printed as two percentages and the raw counts.
2. Restart time (risk 1): `death.t` → first controllable tick of level 1 of the next run, median seconds.
3. Unseen deaths (risk 2): share of deaths with `killer on screen = no`.
4. Level length and pressure (risk 4): median black-phase seconds, median gold-phase seconds, median overtime tier at beacon entry.
5. Stair rate (risk 5): jumps per minute and step-ups per minute of movement (T-080 adds two counters to `level_clear` for this: `jumps`, `stepups`).
6. Lobby time (risk 7): `beacon_enter` → next `level_start`, median seconds, split by offer type (E, C, U, REST and their combinations).
7. Mine margin (risk 8): mine deaths per 100 `mine_pass` + `mine_contact` events, split by chain value below / at-or-above ×1.50, and by walkway width 1 / 2 / platform.
8. Content health (risk 10): pick rate per curse, purchase rate per upgrade, share of runs ending within two levels of a Brutal pick, median and maximum level reached.
Also `tools/run_batch.ps1`: 100 bot runs (`bot_run.gd --dodge`, seeds 0–99, votes per the T-060 addendum) with logging on, then the report. The report is INFORMATION: it has no pass/fail and no threshold, and this ticket adds none (fun-risk document: signals are not gates).
Done-when: the batch runs to completion and the report prints all eight blocks with real counts; the first block appears first; `AUDIT.md` (T-099) receives the report as an appendix.

### T-082 — Camera, key bindings, settings
THE OWNER'S SPEC: "a REAL game — it ships as its own standalone native .exe". "The player walks up to an altar and presses F to select it."
Assignment: spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
Read: DESIGN.md §4, §11, §13; this file §4 (T-024 addendum).
Do `[CONTESTABLE]` — no earlier document states any of these: third-person orbit camera, 7.0 u behind and 2.5 u above the player's feet, default pitch −18°, pitch clamp −60°…+30°, FOV 75°, mouse yaw/pitch 0.12 °/px, no camera collision (there is nothing but void to clip), vertical spring 0.12 s over step-ups; `app/input_capture.gd` turns keys into `PlayerInput` with the move vector pre-rotated by camera yaw and quantized to int8: W A S D move, Space jump (hold = glide / variable jump), Left Shift class ability, F interact (hold 0.35 s at altars), Tab toggle HUD rows, Esc pause menu; mouse captured in levels and in the lobby; gamepad: left stick move, A jump, X ability, Y interact. Bindings in `data/bindings.json`.
Done-when: `tests/test_input.gd` — each key produces the documented bit; the same key sequence at two camera yaws produces move vectors rotated by exactly the yaw difference; the camera never changes sim state (replay test green with the camera moved randomly).

### T-083 — Enemy animation data
THE OWNER'S SPEC: "Per-enemy PNG animation specs, one section per enemy, all 12 … Cue TIMINGS in DESIGN.md are binding: the telegraph animation fills the cue exactly, the attack frame lands on the cue's end."
Assignment: 2× spawn model:opencode/opencode/inkling-2-small-free (enemies 1–6 / 7–12)
Read: this file §1 (the tables are the spec), each enemy's `sprites.json` from T-016.
Do: add an `anim` block to each `content/enemies/<id>/sprites.json`: one entry per state of its §1.x table — frames (by file name), loop yes/no, ticks per frame or explicit tick ranges, effect name and parameters. No code. If T-016 produced a TBD placeholder for an enemy, every state uses the TBD frame and the timings stay.
Done-when: `tools/check_anim_data.gd` proves every state of every §1.x table exists with the listed frames and tick counts (12/12), and every referenced frame file exists.

### T-084 — Animation player and telegraph sync
THE OWNER'S SPEC: the same sentence as T-083, plus ENEMIES.md hard rules "BILLBOARDING … HITBOXES … TRANSPARENCY".
Assignment: spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
Read: this file §1.0, T-027's `view/billboard.gd`.
Do: `view/enemy_anim.gd` picks the frame from the SIM state and its tick counter (never a view timer) using the `anim` block; billboard effects (flash, tint, scale pulse, shake, alpha) as shader parameters; the hit shape follows the `body_rect` of the frame shown; spawn fade blocks contact for 30 ticks.
Done-when: `tests/test_anim_sync.gd` — for each of the 12 enemies, driven by a scripted sim: the telegraph state lasts exactly its binding tick count; the attack frame is the frame shown on the tick the attack event fires (0 ticks of error); the billboard normal faces the camera from 8 angles in every state; a probe in the transparent padding of the CURRENT frame never hits.

### T-085 — VFX pack
THE OWNER'S SPEC: "VFX specs: tripmine particles (constant pink, readable at distance, visibly wrong up close — the deception rule), glitched floor, beacon closed/open … respawn effect." Canon: "black framed box, six-pointed star center, constant pink particles, slow rotation, glows like a normal gift at distance but visibly wrong up close".
Assignment: spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash
Read: this file §2.1, §2.2, §2.3, §2.5; TERRAIN_SPEC §12.
Do: build the four effects exactly as tabled, all view-layer, all driven by sim events.
Done-when: `tests/test_vfx.gd` — the mine emitter is active at every distance and its particle alpha is 0 at 14 u and 1 at 10 u (5 u and 7 u under Method Acting); the mine's rim glow parameters equal a black gift's; the beacon's column appears on the tick of the last real black gift; the respawn invulnerability blink ends on the tick invulnerability ends; `fog_check.gd` has the new 12 u particle row and passes for all 5 biomes.

### T-086 — HUD: charge pips, Last Light icon, death attribution screen
THE OWNER'S SPEC: "charge pips and death attribution on the HUD". "Death attribution: every death shows its killer (e.g. "Tripmine") and has its own death codes."
Assignment: spawn model:opencode/opencode/inkling-2-small-free
Read: this file §2.4; DESIGN.md §3.1, §14.
Do: extend T-025's HUD with the pip animations, the Last Light icon's three states and the run-over screen layout exactly as tabled.
Done-when: `tests/test_hud_charges.gd` — pips for 2/1/0 charges and for Hungry Void; the icon is lit, dim and grey in the three states of D-053; for each of the 12 death codes of DESIGN.md §3.1 plus one `D-CURSE:<id>` the run-over screen shows a name and a code within 120 ticks of death.

### T-087 — Audio cues
THE OWNER'S SPEC: "Sound design briefs per enemy: new sound matched to the new model, nothing from Nullscape audio, cue-first: every lethal threat's audio cue is learnable and precedes the attack by the binding cue time."
Assignment: spawn model:opencode/opencode/inkling-2-small-free
Read: this file §3; T-055's `tools/synth_audio.py`.
Do: one `.wav` per row of §3 at the listed length, synthesized; `content/enemies/<id>/enemy.json` lists each cue with the sim event that starts it and its offset in ticks. The three stand-ins get `"tbd_audio": true` and TBD.md rows. No downloaded or recorded audio.
Done-when: `tools/check_audio.gd` — every cue file exists with its length ± 10 ms; every lethal attack in the roster has a cue whose start tick is ≤ the attack tick minus its binding cue time; the cue ends on the attack tick ± 1.

### Backlog tickets (claimable only under the run plan's backlog rule)
- **T-090 — Cross-ticket bug review.** Assignment: spawn model:acpRegistry_mistral_vibe/deepseek-v4. Re-read every merged diff of the run against DESIGN.md, TERRAIN_SPEC.md and the tickets; list contradictions (file:line on both sides) in `REVIEW.md`; fix nothing. Done-when: REVIEW.md exists, even if it says "none found".
- **T-091 — Dead vocabulary sweep.** Assignment: spawn model:opencode/opencode/inkling-2-small-free. Case-insensitive whole-word search for "damage", "HP", "rooms", "hop", "2 per level" across all documents and code. Allowed: ENEMIES.md is clean already; DECISIONS.md historical entries (D-042, D-043, D-050–D-052 describe what was replaced), research/ files, lines starting `SUPERSEDED BY`, the arm trait named `hop` in terrain code and TERRAIN_SPEC (a trait, not the retired anchor), verbatim owner quotes. Report every hit; fix only hits outside the allowed list. Done-when: the report lists zero unallowed hits.
- **T-092 — Validator selftest expansion.** Assignment: spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash. From 15 to at least 25 planted defects in `terrain_ref/validate.py --selftest`, each provoking EXACTLY one check (assert the set of failing ids equals {that id}). No generator change; no threshold change. Done-when: `SELFTEST n/n` with n ≥ 25; harness 5,000 seeds unchanged.
- **T-093 — Determinism fuzz.** Assignment: spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash. 10 fresh seeds (≥ 100,000) × levels 1, 15, 30, generated 3 times each in 3 separate processes in Python and once in Godot: byte-identical canonical text. Then `validate.py --seeds 0:20000`. Report every failure honestly; expected: check H15 may fail about once per 30,000 levels (DECISIONS Handover, checkpoint 8) — report it, do not fix it, do not raise the limit. Done-when: the report exists with all numbers.
- **T-094 — Loading tip pool.** Assignment: spawn model:opencode/opencode/inkling-2-small-free. 30 tips in `data/tips.json`; at least one tip per death code, shown on that code's run-over screen; every tip checked against the CURRENT DESIGN.md (cite the section in a `source` field). Done-when: 30 tips, each with a source, ≥ 8 tagged `hazard_tell`.
- **T-095 — README and HOW-TO-PLAY.** Assignment: spawn model:opencode/opencode/inkling-2-small-free. Rewrite README.md's game description and add HOW_TO_PLAY.md to match void charges, one-hit contact and the beacon restoring one charge; keep the disclaimer verbatim. Done-when: `test_disclaimer.gd` green; no retired vocabulary.
- **T-096 — Death attribution edge cases.** Assignment: spawn model:acpRegistry_mistral_vibe/zai-glm-5-3-flash. Tests: every enemy id, every curse id and the void produce a name and a code on the run-over screen; no code is produced that DESIGN.md §3.1 does not list; a TBD enemy shows "TBD"; a kill during another enemy's push is attributed to the killer, a void fall after a push to the void. Done-when: tests green.

