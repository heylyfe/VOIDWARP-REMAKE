extends RefCounted
#
# leaky_purse.gd — the Leaky Purse script curse (DESIGN.md section 7.2, GENERAL family;
# ticket T-051).
#
# Rule: "a void fall drops 5% of this level's earned gold (max 20 g per fall)".
#
# "This level's earned gold" is the gold the purse GAINED since this level began (the
# on_level_start snapshot of economy.purse_centi; bounties paid in the intermission
# before the level already sat in the purse at that snapshot). Money is integer
# centi-gold (data/economy.json gold_arithmetic); the drop is floor(5 % of earned) in
# centi, floored again to whole gold, then capped at 20 g — two floors, never a rounding
# drift up. The gold leaves through api.add_gold(-drop) (DESIGN.md section 12's allowed
# "add gold" surface, negatives spend); with no api method present the economy's own
# purse field is the documented fallback a test stub may exercise instead.

const CURSE_ID := "leaky_purse"
const DROP_PCT := 0.05          # 5 % of this level's earned gold
const DROP_CAP_G := 20          # max 20 g per fall


## Stacks the run holds; >= 1 while the curse is picked (the sim's {curse_id: stacks}).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## on_level_start(state, api): snapshot the purse — the baseline "earned" measures from.
static func on_level_start(state: Dictionary, _api) -> void:
	var econ = state.get("economy", null)
	var slot := _slot(state)
	if econ != null:
		slot["centi_at_start"] = int(econ.purse_centi)


## on_void_fall(state, api): the drop. Never touches respawn/invulnerability (that is
## Brittle's declarative table row, T-050's file); this curse is ONLY the gold leak.
## api.add_gold(-drop_g) when the api carries it, else the economy's purse field.
static func on_void_fall(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return  # not held: no drop, the purse keeps everything
	var econ = state.get("economy", null)
	if econ == null:
		return
	var slot := _slot(state)
	var earned: int = maxi(0, int(econ.purse_centi) - int(slot.get("centi_at_start", 0)))
	var drop_g := drop_gold(earned)
	if drop_g <= 0:
		return
	slot["gold_dropped"] = int(slot.get("gold_dropped", 0)) + drop_g
	if api != null and api.has_method("add_gold"):
		api.add_gold(-drop_g)
	else:
		econ.purse_centi -= drop_g * 100  # the documented integer-centi purse
	var evs: Variant = state.get("events", null)
	if evs is Array:
		evs.append({"e": "leaky_purse_drop", "gold": drop_g})


## The rule sentence's arithmetic, pure: floor(5 % of earned centi) in centi, floored to
## whole gold, capped at 20. earned_centi may not be negative.
static func drop_gold(earned_centi: int) -> int:
	if earned_centi <= 0:
		return 0
	var centi := int(floor(float(earned_centi) * DROP_PCT))
	return mini(DROP_CAP_G, int(centi / 100))


# ---- per-curse state (the D-T051-1 shape: state["curse_st"][CURSE_ID]) ----------------

static func _slot(state: Dictionary) -> Dictionary:
	var root_v: Variant = state.get("curse_st", {})
	var root: Dictionary = {}
	if root_v is Dictionary:
		root = root_v
	if not root.has(CURSE_ID):
		root[CURSE_ID] = {}
	state["curse_st"] = root
	return root[CURSE_ID]

