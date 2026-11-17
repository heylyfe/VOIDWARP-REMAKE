extends RefCounted
#
# method_acting.gd - script curse (ticket T-051; DESIGN.md section 7.1 "method_acting").
# Rule sentence (spec, verbatim): "mine tells are visible only within 6 u (was 12 u)".
# Counter-play: "Radar Module: Mines; slow down at jackpots".
#
# Shape (the T-085 contract, no imports, no view reach-in): the mine view's alpha
# ramp reads this file's static tell_radius_u(state, stacks) - 5.0 u while the
# curse is held, 10.0 u otherwise (the T-085 VFX numbers; alpha 1 at that distance,
# fading to 0 at 2x). The DESIGN.md sentence's own pair (6 u vs the base 12 u rim
# glow, sim/mines.gd's TELL_DISTANCE) is exposed alongside as tell_visible_u for
# the sim-side rim-glow cutoff, so both scales stay one call away and T-085's
# consumer chooses. on_level_start stamps the held value into state["curse_st"]
# so an integration that cannot preload content (or a replay) can read the stamp
# instead of calling into this script.

const CURSE_ID := "method_acting"

## The T-085 VFX alpha ramp's tell distance: held 5.0 u, base 10.0 u.
const TELL_HELD_U := 5.0
const TELL_BASE_U := 10.0
## The DESIGN.md section 7.1 sentence's own pair (sim-side rim glow): held 6.0 u,
## base 12.0 u (mines.gd's TELL_DISTANCE).
const VISIBLE_HELD_U := 6.0
const VISIBLE_BASE_U := 12.0
## The curse_st stamp this script's on_level_start writes.
const ST_KEY := "method_acting_tell_u"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## The tell radius the mine view's alpha ramp reads (the T-085 contract):
## 5.0 u while Method Acting is held, 10.0 u otherwise.
static func tell_radius_u(state: Dictionary) -> float:
	if held_stacks(state) >= 1:
		return TELL_HELD_U
	return TELL_BASE_U


## The sim-side rim-glow cutoff the DESIGN.md sentence pins:
## 6.0 u while held, the base 12.0 u (mines.gd's TELL_DISTANCE) otherwise.
static func tell_visible_u(state: Dictionary) -> float:
	if held_stacks(state) >= 1:
		return VISIBLE_HELD_U
	return VISIBLE_BASE_U


## on_level_start: stamp the held tell onto the per-level scratch - the replay- and
## stub-safe read of this curse's effect.
static func on_level_start(state: Dictionary, api) -> void:
	var st: Dictionary = state.get("curse_st", {})
	if st.has(ST_KEY):
		return   # stamps only once per level; held_stacks() stays the live read
	st[ST_KEY] = tell_radius_u(state)
