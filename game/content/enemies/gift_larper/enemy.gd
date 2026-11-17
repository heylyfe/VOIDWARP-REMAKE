extends RefCounted
#
# gift Larper behavior module (ticket T-021). Lives under content/ so the sim
# core stays enemy-agnostic; it carries NO sim state - it only translates the
# roster numbers (DESIGN.md section 5.7 / section 3.3) for the loader.
#
# Each vote adds +3 flat extra mines (TERRAIN_SPEC section 6.8 rolls them into
# the level's slot set; the 20% hard cap still applies - never more than the
# cap, never a per-slot-chance change).
#
# The tripmine does not MOVE (no anchor kind, no wander step, no attack phase):
# its whole behavior is the occupied-slot contact that sim/mines.gd resolves,
# so there is no per-tick AI here on purpose. If a later rework wants an active
# behavior, this is the file that carries it (re-based onto the EnemyBehavior
# base the enemy runtime, FLEET_PACK T-027, provides).

## Roster numbers (DESIGN.md section 5.7 + 3.3; the sim constants match).
const MAX_VOTES := 5
const MINES_PER_VOTE := 3
const TELL_DISTANCE := 12.0
const BLAST_RADIUS := 3.0
const CONTACT_RADIUS := 0.9


## The extra_mines value this roster contributes for `votes` votes (clamped to
## the roster's max): extra_mines += 3 per vote, no cap of its own - the
## terrain's cap math (TERRAIN_SPEC section 6.8) bounds the final count.
static func extra_mines(votes: int) -> int:
	if votes <= 0:
		return 0
	return mini(votes, MAX_VOTES) * MINES_PER_VOTE
