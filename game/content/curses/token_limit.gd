extends RefCounted
#
# token_limit.gd - script curse (DESIGN.md section 7.1 row "token_limit").
# Rule sentence (spec, verbatim, as rewritten by the cycle-7 Claude revamp, D-T4-7): "a clawd leaves 20 s of
# anger instead of calming Claude completely". Counter-play: "route for clawds".
#
# Reading (D-T4-7): a clawd pickup sets sim/clawds.gd's `anger_ticks` to 0 - that is what "collecting a clawd
# CALMS Claude" means. The curse raises the leftover the pickup leaves behind to 1200 ticks (20 s), so every
# clawd buys 20 s less than it should and the warnings arrive sooner. The sim's own default is 0, so an
# un-cursed run is byte-identical to the plain design.
#
# The old second clause ("and spawn every 30 s") is dropped: clawds spawn once at level start in the revamp,
# so there is no periodic spawn to slow down (D-T4-7 records the drop rather than inventing a mechanic).

const CURSE_ID := "token_limit"

const CALM_LEFTOVER_TICKS := 1200   # the rule sentence's 20 s at the fixed 60 Hz tick
const CALM_FULL_TICKS := 0          # the sim's own calm (sim/clawds.gd calm_leftover_ticks default)


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## The anger a pickup leaves behind: 1200 ticks (20 s) while held, the sim's own 0 otherwise.
## Pure helper - the test target.
static func calm_leftover_ticks(state: Dictionary) -> int:
	if held_stacks(state) >= 1:
		return CALM_LEFTOVER_TICKS
	return CALM_FULL_TICKS


## on_tick: push the leftover onto the clawd state (a no-op when the level carries no swarm).
static func on_tick(state: Dictionary, _api) -> void:
	var cl = state.get("clawds")
	if cl == null:
		return
	cl.calm_leftover_ticks = calm_leftover_ticks(state)
