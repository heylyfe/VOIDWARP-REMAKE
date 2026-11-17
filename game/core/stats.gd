extends RefCounted
#
# stats.gd — the closed stat list (DESIGN.md section 12; ticket T-013).
#
# Modifier dicts in curse/upgrade JSON name one of these stats. The list is CLOSED: adding a
# stat is a core change (edit this file + the schema enums in core/schemas/curse.schema.json and
# upgrade.schema.json in the same commit); content data may never invent one. The registry
# rejects any modifier whose stat is not in STATS, so a typo fails at boot with the file name.
#
# Semantics (DESIGN.md section 12): a modifier is {stat, op: add|mul|set, value, when?}.
# Final stat = (base + sum of adds) * product of muls, then `set` wins. `when` filters the
# modifier to a context (always | black_phase | gold_phase | class:<id>); core/content_api.gd
# applies the arithmetic.
#
# This file is data only: no content ids, no engine types beyond Array/Dictionary (the boundary
# scan, game/tests/test_boundaries.gd, holds core/ to that).

## Every stat a modifier may name, sorted. Sources:
##   - DESIGN.md section 12 closed list (run_speed .. overtime_period), and
##   - every stat named in the section 7 / section 8 tables (all of them are in the section 12
##     list; nothing new was needed — verified against the shipped content in test_content.gd).
const STATS: Array[String] = [
	"barrier_shields",
	"chain_cap",
	"chain_window",
	"defuse_chance",
	"enemy_speed_mul",
	"fill_light_range",
	"fog_density",
	"glitch_slow_mul",
	"gold_value",
	"overtime_period",
	"pickup_radius",
	"respawn_delay",
	"respawn_invuln",
	"run_speed",
	"shop_price_mul",
	"stipend_flat",
	"telegraph_mul",
	"void_charges_max",
	"void_fall_charge_cost",
]


## True when `name` is in the closed list.
static func is_known(name: String) -> bool:
	return STATS.has(name)


## The default (unmodified) value of each stat, from DESIGN.md sections 3, 5, 7 and 8.
## Only stats with a stated base value are listed; a stat absent here has no base yet and its
## owner system (sim/ or view/) supplies the base when it wires modifiers in.
const DEFAULTS: Dictionary = {
	"barrier_shields": 0,          # Subspacial Barrier grants 1 per level (DESIGN.md section 8)
	"chain_cap": 2.0,              # section 3.2: chain cap x2.00
	"chain_window": 4.0,           # section 3.2: 4.0 s
	"defuse_chance": 0.0,          # no Defuse Kit, no defuse
	"enemy_speed_mul": 1.0,
	"fill_light_range": 18.0,      # section 12.2: player fill light range 18 u
	"fog_density": 0.012,          # section 10, act I base
	"glitch_slow_mul": 0.8,        # glitched floor slow is -20% (section 5, D-075)
	"gold_value": 1.0,             # multiplier on gold gift value
	"overtime_period": 20.0,       # section 3.2: a tier every 20 s
	"pickup_radius": 1.0,          # multiplier on the pickup radius
	"respawn_delay": 0.8,          # section 3.1: void-fall respawn after 0.8 s
	"respawn_invuln": 1.0,         # section 3.1: 1.0 s respawn invulnerability
	"run_speed": 1.0,              # multiplier on run speed (base 9.0 u/s, data/player.json)
	"shop_price_mul": 1.0,
	"stipend_flat": 0.0,           # flat gold added on beacon entry per stack
	"telegraph_mul": 1.0,
	"void_charges_max": 2,         # section 3.1: 2 held, cap 2
	"void_fall_charge_cost": 1,    # section 3.1: a void fall spends 1 charge
}
