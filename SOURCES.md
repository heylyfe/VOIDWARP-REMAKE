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


## Generated curse and upgrade icons (the item set)

Every curse and every upgrade has its own icon, and the whole set is **synthesized from
code** by `game/tools/art/icons.gd` - no drawn, sampled, downloaded or traced art is used
anywhere in it. The generator is deterministic (fixed geometry, no randomness, no wall
clock), so the set is reproducible with one command:

```
tools/godot/godot.exe --headless --path game --script res://tools/art/icons.gd
```

Each icon is 128x128, built in the house style of the three class icons
(`docs/classes/*.svg`): flat geometric shapes, hard edges, a bright cyan rim, no gradients,
no text, no emoji. The palette is exactly the five house colours - `#0A2E30`, `#1C6E70`,
`#2FB7B0`, `#7CFFF4`, `#8FE8E0` - and nothing else: the generator snaps every pixel to the
nearest of them, so a pixel is either fully transparent or exactly one of the five.
`game/tests/test_icon_art.gd` asserts that, and asserts that every content id resolves to a
real texture through `game/view/icon_art.gd` (the one lookup the HUD rows, the Antechamber
altars and the death screen use), so a new upgrade or curse shipped without an icon fails
the suite instead of shipping a blank.

**On the Nullscape curse icons.** The owner's instruction was to take the Nullscape curse
icons only as inspiration for WHAT each icon depicts. That is all they were used for: the
idea that a curse gets a pictogram of its own effect. No Nullscape icon was traced, sampled,
recoloured, cropped or copied, and none was opened as a source image - every glyph below is
drawn from this game's own rule text for that curse, in this game's own palette and
construction. The two sets share no pixel.

| asset | path | origin | licence / note |
|---|---|---|---|
| Bargain (bargain) | `game/assets/icons/upgrades/bargain.png` | Original art synthesized by `game/tools/art/icons.gd` - a price tag with a falling arrow | Project-made art; no third-party material |
| Bounty Hunter (bounty_hunter) | `game/assets/icons/upgrades/bounty_hunter.png` | Original art synthesized by `game/tools/art/icons.gd` - a crosshair over a coin | Project-made art; no third-party material |
| Brace (brace) | `game/assets/icons/upgrades/brace.png` | Original art synthesized by `game/tools/art/icons.gd` - a shield stopping a falling arrow | Project-made art; no third-party material |
| Cartographer (cartographer) | `game/assets/icons/upgrades/cartographer.png` | Original art synthesized by `game/tools/art/icons.gd` - a folded map with a marked point | Project-made art; no third-party material |
| Cold Blood (cold_blood) | `game/assets/icons/upgrades/cold_blood.png` | Original art synthesized by `game/tools/art/icons.gd` - a clock ring around a snowflake | Project-made art; no third-party material |
| Defuse Kit (defuse_kit) | `game/assets/icons/upgrades/defuse_kit.png` | Original art synthesized by `game/tools/art/icons.gd` - a mine with its wire cut | Project-made art; no third-party material |
| Early Warning (early_warning) | `game/assets/icons/upgrades/early_warning.png` | Original art synthesized by `game/tools/art/icons.gd` - an eye with warning arcs either side | Project-made art; no third-party material |
| Featherfall (featherfall) | `game/assets/icons/upgrades/featherfall.png` | Original art synthesized by `game/tools/art/icons.gd` - a feather over a falling arrow | Project-made art; no third-party material |
| Field Dressing (field_dressing) | `game/assets/icons/upgrades/field_dressing.png` | Original art synthesized by `game/tools/art/icons.gd` - a medkit plate with a cross | Project-made art; no third-party material |
| Gilded Touch (gilded_touch) | `game/assets/icons/upgrades/gilded_touch.png` | Original art synthesized by `game/tools/art/icons.gd` - a hand under a coin | Project-made art; no third-party material |
| High Ceiling (high_ceiling) | `game/assets/icons/upgrades/high_ceiling.png` | Original art synthesized by `game/tools/art/icons.gd` - a chain link under a rising arrow | Project-made art; no third-party material |
| Hot Streak (hot_streak) | `game/assets/icons/upgrades/hot_streak.png` | Original art synthesized by `game/tools/art/icons.gd` - a flame | Project-made art; no third-party material |
| Insulation (insulation) | `game/assets/icons/upgrades/insulation.png` | Original art synthesized by `game/tools/art/icons.gd` - a boot standing on a mat | Project-made art; no third-party material |
| Last Call (last_call) | `game/assets/icons/upgrades/last_call.png` | Original art synthesized by `game/tools/art/icons.gd` - a bell | Project-made art; no third-party material |
| Ledge Grace (ledge_grace) | `game/assets/icons/upgrades/ledge_grace.png` | Original art synthesized by `game/tools/art/icons.gd` - a ledge with a coyote arc over its lip | Project-made art; no third-party material |
| Long Reach (long_reach) | `game/assets/icons/upgrades/long_reach.png` | Original art synthesized by `game/tools/art/icons.gd` - a dot inside two pickup rings | Project-made art; no third-party material |
| Marathon (marathon) | `game/assets/icons/upgrades/marathon.png` | Original art synthesized by `game/tools/art/icons.gd` - a running figure | Project-made art; no third-party material |
| More (more) | `game/assets/icons/upgrades/more.png` | Original art synthesized by `game/tools/art/icons.gd` - a gift box with a plus | Project-made art; no third-party material |
| Nest Egg (nest_egg) | `game/assets/icons/upgrades/nest_egg.png` | Original art synthesized by `game/tools/art/icons.gd` - an egg in a nest | Project-made art; no third-party material |
| Paycheck (paycheck) | `game/assets/icons/upgrades/paycheck.png` | Original art synthesized by `game/tools/art/icons.gd` - a banknote | Project-made art; no third-party material |
| Pocket Beacon (pocket_beacon) | `game/assets/icons/upgrades/pocket_beacon.png` | Original art synthesized by `game/tools/art/icons.gd` - a beacon under a ring | Project-made art; no third-party material |
| Quick Recovery (quick_recovery) | `game/assets/icons/upgrades/quick_recovery.png` | Original art synthesized by `game/tools/art/icons.gd` - a circular refresh arrow | Project-made art; no third-party material |
| Radar Module: Beacon (radar_beacon) | `game/assets/icons/upgrades/radar_beacon.png` | Original art synthesized by `game/tools/art/icons.gd` - a radar sweep with a beacon tower at its centre | Project-made art; no third-party material |
| Radar Module: Gifts (radar_gifts) | `game/assets/icons/upgrades/radar_gifts.png` | Original art synthesized by `game/tools/art/icons.gd` - a radar sweep with a gift box at its centre | Project-made art; no third-party material |
| Radar Module: Mines (radar_mines) | `game/assets/icons/upgrades/radar_mines.png` | Original art synthesized by `game/tools/art/icons.gd` - a radar sweep with a mine disc at its centre | Project-made art; no third-party material |
| Radar Module: Threats (radar_threats) | `game/assets/icons/upgrades/radar_threats.png` | Original art synthesized by `game/tools/art/icons.gd` - a radar sweep with a threat triangle at its centre | Project-made art; no third-party material |
| Skeleton Key (skeleton_key) | `game/assets/icons/upgrades/skeleton_key.png` | Original art synthesized by `game/tools/art/icons.gd` - a key | Project-made art; no third-party material |
| Slipstream (slipstream) | `game/assets/icons/upgrades/slipstream.png` | Original art synthesized by `game/tools/art/icons.gd` - an arrow with speed lines behind it | Project-made art; no third-party material |
| Spring Heels (spring_heels) | `game/assets/icons/upgrades/spring_heels.png` | Original art synthesized by `game/tools/art/icons.gd` - a spring under a rising arrow | Project-made art; no third-party material |
| Stand Fast (stand_fast) | `game/assets/icons/upgrades/stand_fast.png` | Original art synthesized by `game/tools/art/icons.gd` - an anchor | Project-made art; no third-party material |
| Straggler Scope (straggler_scope) | `game/assets/icons/upgrades/straggler_scope.png` | Original art synthesized by `game/tools/art/icons.gd` - a scope reticle over a beam | Project-made art; no third-party material |
| Subspacial Barrier (subspacial_barrier) | `game/assets/icons/upgrades/subspacial_barrier.png` | Original art synthesized by `game/tools/art/icons.gd` - a hexagon shield with a core | Project-made art; no third-party material |
| Sure Foot (sure_foot) | `game/assets/icons/upgrades/sure_foot.png` | Original art synthesized by `game/tools/art/icons.gd` - a boot with a check | Project-made art; no third-party material |
| Twin Dash (twin_dash) | `game/assets/icons/upgrades/twin_dash.png` | Original art synthesized by `game/tools/art/icons.gd` - two chevrons | Project-made art; no third-party material |
| Updraft (updraft) | `game/assets/icons/upgrades/updraft.png` | Original art synthesized by `game/tools/art/icons.gd` - a rising arrow between two wind arcs | Project-made art; no third-party material |
| Yearn for Speed (yearn_for_speed) | `game/assets/icons/upgrades/yearn_for_speed.png` | Original art synthesized by `game/tools/art/icons.gd` - a lightning bolt | Project-made art; no third-party material |
| Aftershock (aftershock) | `game/assets/icons/curses/aftershock.png` | Original art synthesized by `game/tools/art/icons.gd` - two shockwave rings around a core | Project-made art; no third-party material |
| Brittle (brittle) | `game/assets/icons/curses/brittle.png` | Original art synthesized by `game/tools/art/icons.gd` - a shield split by a crack | Project-made art; no third-party material |
| Bunker Buster (bunker_buster) | `game/assets/icons/curses/bunker_buster.png` | Original art synthesized by `game/tools/art/icons.gd` - a blast burst over a crate | Project-made art; no third-party material |
| Cold Start (cold_start) | `game/assets/icons/curses/cold_start.png` | Original art synthesized by `game/tools/art/icons.gd` - a cog with a snowflake at its hub | Project-made art; no third-party material |
| Crescendo (crescendo) | `game/assets/icons/curses/crescendo.png` | Original art synthesized by `game/tools/art/icons.gd` - four rising bars | Project-made art; no third-party material |
| Crowded Dais (crowded_dais) | `game/assets/icons/curses/crowded_dais.png` | Original art synthesized by `game/tools/art/icons.gd` - a beacon ringed by a crowd of dots | Project-made art; no third-party material |
| Crumbling (crumbling) | `game/assets/icons/curses/crumbling.png` | Original art synthesized by `game/tools/art/icons.gd` - a cracked tile shedding chips | Project-made art; no third-party material |
| Curfew (curfew) | `game/assets/icons/curses/curfew.png` | Original art synthesized by `game/tools/art/icons.gd` - a clock over a padlock | Project-made art; no third-party material |
| Direct Shot (direct_shot) | `game/assets/icons/curses/direct_shot.png` | Original art synthesized by `game/tools/art/icons.gd` - a ball with a ricochet path | Project-made art; no third-party material |
| Echo Ring (double_ring) | `game/assets/icons/curses/double_ring.png` | Original art synthesized by `game/tools/art/icons.gd` - two concentric rings | Project-made art; no third-party material |
| Dull Gifts (dull_gifts) | `game/assets/icons/curses/dull_gifts.png` | Original art synthesized by `game/tools/art/icons.gd` - a gift box struck through | Project-made art; no third-party material |
| Early Bird (early_bird) | `game/assets/icons/curses/early_bird.png` | Original art synthesized by `game/tools/art/icons.gd` - a clock with fast-forward chevrons | Project-made art; no third-party material |
| Egoist (egoist) | `game/assets/icons/curses/egoist.png` | Original art synthesized by `game/tools/art/icons.gd` - three balls around a plus | Project-made art; no third-party material |
| Hasty (hasty) | `game/assets/icons/curses/hasty.png` | Original art synthesized by `game/tools/art/icons.gd` - a clock with a bolt beside it | Project-made art; no third-party material |
| Hungry Void (hungry_void) | `game/assets/icons/curses/hungry_void.png` | Original art synthesized by `game/tools/art/icons.gd` - a toothed maw | Project-made art; no third-party material |
| Inflation (inflation) | `game/assets/icons/curses/inflation.png` | Original art synthesized by `game/tools/art/icons.gd` - a coin under a rising arrow | Project-made art; no third-party material |
| Leaky Purse (leaky_purse) | `game/assets/icons/curses/leaky_purse.png` | Original art synthesized by `game/tools/art/icons.gd` - a purse dripping | Project-made art; no third-party material |
| Lights Out (lights_out) | `game/assets/icons/curses/lights_out.png` | Original art synthesized by `game/tools/art/icons.gd` - a bulb struck through | Project-made art; no third-party material |
| The Litter (litter) | `game/assets/icons/curses/litter.png` | Original art synthesized by `game/tools/art/icons.gd` - a cat followed by a kitten | Project-made art; no third-party material |
| Long Night (long_night) | `game/assets/icons/curses/long_night.png` | Original art synthesized by `game/tools/art/icons.gd` - a crescent moon with a clock | Project-made art; no third-party material |
| The Long Toll (long_toll) | `game/assets/icons/curses/long_toll.png` | Original art synthesized by `game/tools/art/icons.gd` - two bells | Project-made art; no third-party material |
| Filibuster (longer_speech) | `game/assets/icons/curses/longer_speech.png` | Original art synthesized by `game/tools/art/icons.gd` - a speech bubble with two long lines | Project-made art; no third-party material |
| Method Acting (method_acting) | `game/assets/icons/curses/method_acting.png` | Original art synthesized by `game/tools/art/icons.gd` - a theatre mask | Project-made art; no third-party material |
| Mirror Match (mirror_match) | `game/assets/icons/curses/mirror_match.png` | Original art synthesized by `game/tools/art/icons.gd` - two arrows facing across a mirror line | Project-made art; no third-party material |
| Sealed Deals (no_refunds) | `game/assets/icons/curses/no_refunds.png` | Original art synthesized by `game/tools/art/icons.gd` - a reroll ring struck through | Project-made art; no third-party material |
| Overwound (overwound) | `game/assets/icons/curses/overwound.png` | Original art synthesized by `game/tools/art/icons.gd` - a tight spiral | Project-made art; no third-party material |
| Pup Pack (pup_pack) | `game/assets/icons/curses/pup_pack.png` | Original art synthesized by `game/tools/art/icons.gd` - a seal followed by a smaller seal | Project-made art; no third-party material |
| Quarter Chimes (quarter_chimes) | `game/assets/icons/curses/quarter_chimes.png` | Original art synthesized by `game/tools/art/icons.gd` - a clock with one quarter filled | Project-made art; no third-party material |
| Rearguard (rearguard) | `game/assets/icons/curses/rearguard.png` | Original art synthesized by `game/tools/art/icons.gd` - a beacon with a threat triangle behind it | Project-made art; no third-party material |
| Rush Hour (rush_hour) | `game/assets/icons/curses/rush_hour.png` | Original art synthesized by `game/tools/art/icons.gd` - a running figure with speed lines | Project-made art; no third-party material |
| Second Strike (second_strike) | `game/assets/icons/curses/second_strike.png` | Original art synthesized by `game/tools/art/icons.gd` - two missiles | Project-made art; no third-party material |
| Short Chain (short_chain) | `game/assets/icons/curses/short_chain.png` | Original art synthesized by `game/tools/art/icons.gd` - a chain cut in the middle | Project-made art; no third-party material |
| Wet Trail (slipstream_trail) | `game/assets/icons/curses/slipstream_trail.png` | Original art synthesized by `game/tools/art/icons.gd` - a wave over a drip | Project-made art; no third-party material |
| Slow Door (slow_door) | `game/assets/icons/curses/slow_door.png` | Original art synthesized by `game/tools/art/icons.gd` - a door with a clock | Project-made art; no third-party material |
| Spreading Rot (spreading_rot) | `game/assets/icons/curses/spreading_rot.png` | Original art synthesized by `game/tools/art/icons.gd` - a grid with infected cells | Project-made art; no third-party material |
| Tarnish (tarnish) | `game/assets/icons/curses/tarnish.png` | Original art synthesized by `game/tools/art/icons.gd` - a coin with a dull wedge | Project-made art; no third-party material |
| Thick Fog (thick_fog) | `game/assets/icons/curses/thick_fog.png` | Original art synthesized by `game/tools/art/icons.gd` - three fog bands | Project-made art; no third-party material |
| Token Limit (token_limit) | `game/assets/icons/curses/token_limit.png` | Original art synthesized by `game/tools/art/icons.gd` - a plushie over a limit bar | Project-made art; no third-party material |
| Twin Fangs (twin_fangs) | `game/assets/icons/curses/twin_fangs.png` | Original art synthesized by `game/tools/art/icons.gd` - two fangs | Project-made art; no third-party material |
| Unannounced (unannounced) | `game/assets/icons/curses/unannounced.png` | Original art synthesized by `game/tools/art/icons.gd` - a trumpet struck through | Project-made art; no third-party material |
| Understudies (understudies) | `game/assets/icons/curses/understudies.png` | Original art synthesized by `game/tools/art/icons.gd` - two mines | Project-made art; no third-party material |
| Unmarked (unmarked) | `game/assets/icons/curses/unmarked.png` | Original art synthesized by `game/tools/art/icons.gd` - a beam struck through | Project-made art; no third-party material |
| Weighed Down (weighed_down) | `game/assets/icons/curses/weighed_down.png` | Original art synthesized by `game/tools/art/icons.gd` - a weight | Project-made art; no third-party material |
| Wet Floor (wet_floor) | `game/assets/icons/curses/wet_floor.png` | Original art synthesized by `game/tools/art/icons.gd` - a puddle with slip arcs | Project-made art; no third-party material |
| Stage Presence (wide_blast) | `game/assets/icons/curses/wide_blast.png` | Original art synthesized by `game/tools/art/icons.gd` - a wide blast burst inside its ring | Project-made art; no third-party material |
| Zoomies (zoomies) | `game/assets/icons/curses/zoomies.png` | Original art synthesized by `game/tools/art/icons.gd` - a cat with speed lines | Project-made art; no third-party material |
