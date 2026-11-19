extends RefCounted
#
# understudies.gd - script curse (DESIGN.md section 7.1 row "understudies").
# Rule sentence (spec, verbatim): "+4 flat extra mines per stack (20% cap still
# holds)".
# Counter-play: "Defuse Kit".
#
# Reading: the roster's own contribution is gift Larper's extra_mines(votes) = +3 per
# vote (T-036); this curse adds a FLAT +4 per stack on top of it, and the terrain's
# hard cap is untouched - roll_mines() (TERRAIN_SPEC 6.8) never places more than
# n // 5 mines, so the extra mines are flat adds UNDER the same 20% ceiling and can
# never raise the per-slot chance. The module therefore exposes the curse's own
# contribution (extra_mines), the sum an engine caller hands the generator
# (total_extra_mines), and the cap itself (mine_cap) so the two stay one call apart.
#
# Nothing here writes the level: the generator owns placement, this file owns the
# number it is handed.

const CURSE_ID := "understudies"

const MINES_PER_STACK := 4      # the rule sentence's "+4 flat extra mines per stack"
const MAX_STACKS := 3           # the JSON's max_stacks (the cap on the flat add)
const CAP_DIVISOR := 5          # the 20% hard cap: n // 5 (TERRAIN_SPEC 6.8)


## Stacks the run holds, clamped to the JSON's max_stacks.
static func held_stacks(state: Dictionary) -> int:
	return mini(int(state.get("curses_held", {}).get(CURSE_ID, 0)), MAX_STACKS)


## The curse's own flat contribution: +4 per stack, 0 when not held. Pure helper.
static func extra_mines(state: Dictionary) -> int:
	return MINES_PER_STACK * held_stacks(state)


## What an engine caller hands the generator: the roster's own extra mines plus this
## curse's flat add. Pure helper - the test target.
static func total_extra_mines(state: Dictionary, roster_extra: int) -> int:
	return maxi(roster_extra, 0) + extra_mines(state)


## The 20% hard cap the rule sentence says still holds: n // 5 (TERRAIN_SPEC 6.8).
## Pure helper - the test target.
@warning_ignore("integer_division")
static func mine_cap(slots: int) -> int:
	return maxi(slots, 0) / CAP_DIVISOR
