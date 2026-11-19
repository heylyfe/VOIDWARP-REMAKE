extends RefCounted
#
# unannounced.gd - script curse (DESIGN.md section 7.1 row "unannounced").
# Rule sentence (spec, verbatim): "no trumpet — only the sprite and the rumble".
# Counter-play: "keep it on screen; Radar Module: Threats".
#
# Reading: address me's appearance is announced by three things - the sprite (the 12-tick
# spawn state), the elephant trumpet (the "spawn_trumpet" cue, view/audio/
# address_me_audio.gd) and the 5.0 s rumble ("rumble_build"). The curse removes the
# TRUMPET only: the sprite and the rumble stay, so the tell is still there but it is no
# longer audible from across the level. The explode boom ("explode_boom") is the kill
# itself, not a tell, so it stays too - the sentence names the trumpet, not the attack.
#
# The contract is the cue list the view asks for: cue_names(state) is the set of cues
# address me may play, and cue_allowed(state, cue) answers one cue. Nothing here plays
# or suppresses audio itself (the view owns the player); this file owns the list.

const CURSE_ID := "unannounced"

const TRUMPET_CUE := "spawn_trumpet"   # the cue the rule sentence removes
const RUMBLE_CUE := "rumble_build"     # the rumble that stays
const BOOM_CUE := "explode_boom"       # the kill's own boom (not a tell) - stays
const ALL_CUES := ["explode_boom", "rumble_build", "spawn_trumpet"]   # sorted


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## The cues address me may play: the trumpet is dropped while the curse is held.
## Pure helper - the test target.
static func cue_names(state: Dictionary) -> Array:
	var out: Array = []
	for cue in ALL_CUES:
		if cue_allowed(state, str(cue)):
			out.append(str(cue))
	return out


## True when `cue` may play: everything but the trumpet, which the curse silences.
## Pure helper - the test target.
static func cue_allowed(state: Dictionary, cue: String) -> bool:
	if held_stacks(state) >= 1 and cue == TRUMPET_CUE:
		return false
	return true


## True while the sprite (the spawn state) still shows - the curse never hides the
## body, only the trumpet. Pure helper.
static func sprite_visible(_state: Dictionary) -> bool:
	return true


## True while the rumble still plays - the curse never silences it. Pure helper.
static func rumble_audible(state: Dictionary) -> bool:
	return cue_allowed(state, RUMBLE_CUE)
