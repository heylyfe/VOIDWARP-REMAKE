extends RefCounted
#
# hooks.gd — the closed hook list (DESIGN.md section 12; ticket T-013).
#
# A content file declares `hooks: [name, ...]`; a handler is a function in the content's
# optional `<id>.gd` script. A hook handler receives (state, api) and may only change the
# world through `api` (core/content_api.gd plus the sim API passed by the caller) — never by
# touching nodes or globals. Handlers run in id order.
#
# The list is CLOSED: adding a hook is a core change (edit this file + the schema enums in
# core/schemas/curse.schema.json and upgrade.schema.json in the same commit). The registry
# rejects any hook name not in HOOKS, so a typo fails at boot with the file name.

const HOOKS: Array[String] = [
	"on_level_start",
	"on_gift_collected",
	"on_beacon_open",
	"on_beacon_enter",
	"on_void_fall",
	"on_charge_spent",
	"on_charge_restored",
	"on_mine_contact",
	"on_mine_defused",
	"on_barrier_absorbed",
	"on_player_death",
	"on_enemy_spawn",
	"on_tick",
	"on_shop_draw",
	"on_curse_draw",
]


## True when `name` is in the closed list.
static func is_known(name: String) -> bool:
	return HOOKS.has(name)
