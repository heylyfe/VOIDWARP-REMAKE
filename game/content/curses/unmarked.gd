extends RefCounted
#
# unmarked.gd — the Unmarked script curse (DESIGN.md section 7.2, GENERAL family;
# ticket T-051).
#
# Rule (the curse.json sentence, asserted as-is by the test): "no straggler beam".
#
# The straggler rule (DESIGN.md section 3.3, sim/gifts.gd) classifies the last 20 % of a
# level's REAL black gifts as stragglers. Unmarked suppresses exactly the beam shown for
# them: while this curse is held, straggler_ids() returns an empty list to every consumer
# (the view's straggler_beam.gd draws nothing), and with no stack held the answer is the
# sim's own, byte for byte. The sim state is read, never written.
#
# Hook contract (content/curses header note, D-T051-1): handlers are functions named after
# the closed hooks of core/hooks.gd, signature handler(state, api). The general read-only
# curses declare no handler functions (the JSON's hooks stay [], T-050's file) — the view
# and the dispatcher consult the pure helpers below. Nothing under this file touches a
# Node, a clock or RNG.

const CURSE_ID := "unmarked"


## Stacks of this curse the run holds ({curse_id: stacks} is the sim's ledger shape —
## the same key intermission.gd keeps as curses_held).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## The straggler-beam data source. Held: NO straggler is ever reported (the rule
## sentence). Not held: gifts.straggler_ids() unchanged — no weakening of that sim rule.
static func straggler_ids(state: Dictionary, gifts) -> Array:
	if held_stacks(state) > 0:
		return []
	return gifts.straggler_ids()

