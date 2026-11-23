extends RefCounted
#
# crescendo.gd - script curse (ticket T-051; DESIGN.md section 7.1 row "crescendo").
# Rule sentence (spec, verbatim, as rewritten by the cycle-7 Claude revamp, D-T4-7): "the anger timer runs 1.5x
# faster". Counter-play: "collect clawds first".
#
# Reading (D-T4-7): the anger timer is sim/clawds.gd's `anger_ticks`, which advances one tick per sim tick. The
# curse multiplies that rate by 1.5 on the clawd state, so the warnings land at 40 s and 80 s and the kill at
# 120 s instead of 60 / 120 / 180. The sim's own rate is untouched (the module never edits sim/clawds.gd), and
# the multiplier is a plain float the sim carries a fractional remainder for, so 1.5x is exactly 3 ticks per 2
# ticks and never drifts.

const CURSE_ID := "crescendo"

const ANGER_RATE_MUL := 1.5       # the rule sentence's 1.5x
const BASE_RATE_MUL := 1.0        # the sim's own rate (sim/clawds.gd anger_rate_mul default)


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## The anger rate multiplier this curse asks for: 1.5 while held, the sim's own 1.0 otherwise.
## Pure helper - the test target.
static func anger_rate_mul(state: Dictionary) -> float:
	if held_stacks(state) >= 1:
		return ANGER_RATE_MUL
	return BASE_RATE_MUL


## on_tick: push the multiplier onto the clawd state (a no-op when the level carries no swarm).
static func on_tick(state: Dictionary, _api) -> void:
	var cl = state.get("clawds")
	if cl == null:
		return
	cl.anger_rate_mul = anger_rate_mul(state)


## The tick count a threshold lands on at the cursed rate: the plain threshold divided by the multiplier, in
## integer ticks (3600 -> 2400, 7200 -> 4800, 10800 -> 7200). Pure helper - the test target.
static func ticks_at_rate(plain_ticks: int, rate: float) -> int:
	if rate <= 0.0:
		return plain_ticks
	return int(round(float(plain_ticks) / rate))
