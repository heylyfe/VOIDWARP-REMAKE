extends RefCounted
#
# wet_floor.gd - script curse (DESIGN.md section 7.1 row "wet_floor").
# Rule sentence (spec, verbatim): "glitched tiles are slippery (friction ×0.4); the
# toucher's slow stays −20% — no extra slow (D-075)".
# Counter-play: "jump across, don't walk; the slow stays 20%, so a glitched player at
# 7.2 u/s still gains 0.45 u/s on the toucher (SR-5)".
#
# Reading (D-075, binding): the curse adds SLIPPERINESS ONLY. The world already carries
# the map the controller's friction_mult reads - world["slippery"] (collision.gd: "extra
# slippery tile keys (e.g. Wet Floor); friction x0.4") - so the curse's whole job is to
# keep every glitched tile key in that map while it is held. It never touches the
# glitched floor's own -20%: that is the controller's glitch_slow_mul stat (an enemy
# effect, outside the curse budget), and slow_mul() below reports the value the curse
# must leave alone so the "no extra slow" half of the sentence is asserted, not assumed.

const CURSE_ID := "wet_floor"

const FRICTION_MUL := 0.4        # the rule sentence's friction x0.4
const GLITCH_SLOW_MUL := 0.8     # D-075: the glitched floor's own -20%, unchanged

## Per-level scratch: nothing is stored - world["slippery"] is the live state.
const ST_KEY := "wet_floor"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## The friction multiplier a glitched tile gets: 0.4 while held, 1.0 otherwise.
## Pure helper - the test target.
static func friction_mul(state: Dictionary) -> float:
	if held_stacks(state) >= 1:
		return FRICTION_MUL
	return 1.0


## The glitched floor's run-speed multiplier: the toucher's own -20% (0.8) whether or
## not the curse is held - "no extra slow" (D-075). Pure helper - the test target.
static func slow_mul(_state: Dictionary) -> float:
	return GLITCH_SLOW_MUL


## on_tick: keep every glitched tile key in the world's slippery map.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	var world: Dictionary = rt.world
	if world.is_empty():
		return
	var gl: Dictionary = world.get("glitched", {})
	var slip: Dictionary = world.get("slippery", {})
	for key in gl.keys():
		slip[key] = true
	world["slippery"] = slip
