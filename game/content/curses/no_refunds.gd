extends RefCounted
#
# no_refunds.gd — the Sealed Deals script curse (DESIGN.md section 7.2, GENERAL family;
# ticket T-051).
#
# Rule: "shop reroll plinth is gone".
#
# Hook contract: the plinth's own bay never shows a reroll altar again once this curse is
# held — reroll_plinth_visible() is the U/REST decision helper the shop views consult;
# the intermission's draw pools are untouched. Nothing under this file touches a
# Node, a clock or RNG.

const CURSE_ID := "no_refunds"


## True while the run holds Sealed Deals: the shop reroll plinth is gone for the rest
## of the level (the T-051 dispatcher reads this; the shop views render no plinth).
static func reroll_plinth_visible(state: Dictionary) -> bool:
	return held_stacks(state) == 0


## Stacks of this curse the run holds — {curse_id: stacks} is the same ledger shape
## the intermission bay draws read (one entry per id in the pool, highest first).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))

