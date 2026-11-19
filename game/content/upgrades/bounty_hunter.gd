extends RefCounted
#
# bounty_hunter.gd - script upgrade (DESIGN.md section 8 row "bounty_hunter").
# Rule sentence: "curse bounties +50%".
# Dispatched by sim/upgrade_runtime.gd curse_draw() on every unresolved curse bay. The
# bounty an altar shows is the bounty paid on pick (sim/intermission.gd _select_curse), so
# raising it here raises both. Idempotent: the drawn base is kept in "bounty_base" and the
# shown bounty is always recomputed from it, so a second call on the same bay is a no-op
# and a reroll (fresh altars, no base yet) is boosted once.

const UPGRADE_ID := "bounty_hunter"
const BONUS_PCT := 50   # +50% per stack (max_stacks 1)


static func held_stacks(state: Dictionary) -> int:
	return int(state.get("upgrades_held", {}).get(UPGRADE_ID, 0))


## The boosted bounty for a drawn base, whole gold rounded down (economy.json's rule).
static func boosted(base: int, stacks: int) -> int:
	return int(floor(float(base) * float(100 + BONUS_PCT * maxi(stacks, 0)) / 100.0))


static func on_curse_draw(state: Dictionary) -> void:
	var n := held_stacks(state)
	if n <= 0:
		return
	for a in state.get("altars", []):
		if not (a is Dictionary):
			continue
		var altar: Dictionary = a
		if not altar.has("bounty"):
			continue
		if not altar.has("bounty_base"):
			altar["bounty_base"] = int(altar["bounty"])
		altar["bounty"] = boosted(int(altar["bounty_base"]), n)
