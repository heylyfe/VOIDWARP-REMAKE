extends RefCounted
#
# sim/upgrade_runtime.gd - the upgrade hook dispatcher (DESIGN.md section 12's hook surface,
# the upgrade half). The same shape as sim/curse_runtime.gd, which solves this exact problem
# for curses: the owned ids are read generically, each module comes through a loader
# Callable the app hands in (sim/ never imports res://content/ - test_boundaries.gd), and a
# hook is called only when the module declares it, with the parameter count it declares.
#
# The hooks this dispatcher drives (all in core/hooks.gd's closed list):
#   on_curse_draw(state[, api])        a curse bay drew its altars (lobby; static entry)
#   on_beacon_enter(state[, api])      the player entered the open beacon
#   on_gift_collected(state[, api])    any gift pickup, black or gold
#   on_void_fall(state[, api])         a void fall the controller reported (free or paid)
#   on_mine_defused(state[, api])      the mine ladder's defuse roll succeeded
#   on_barrier_absorbed(state[, api])  the mine ladder's shield took the contact
# The world-tick hooks are event-driven: the app hands the tick's event list to
# dispatch_events() BEFORE its economy pass, so a hook that pays gold or protects the chain
# lands on the same tick the economy reads. The triggering event is state["event"] for the
# duration of the call.
#
# Nothing in this file names a content id. Determinism: modules run in sorted id order,
# there is no randomness here, and the only clocks are the LevelState tick and the
# integer tick counter of the run-speed boost.
#
# The shared state dict (the keys the modules read):
#   upgrades_held  Dictionary id -> stacks (stacks > 0 only)
#   upgrade_st     Dictionary, the modules' per-level scratch; reset by clear()
#   tick           int, the LevelState tick
#   level          int, the level number
#   players        Array of the live controllers
#   economy        the gold-phase economy (purse / chain)
#   beacon         the LevelState beacon
#   events         Array, the CURRENT tick's world event list
#   event          Dictionary, the event that triggered the running hook
#   altars         Array, on_curse_draw only: the drawn curse altars (edited in place)

## Every hook this dispatcher can call.
const HOOKS := ["on_curse_draw", "on_beacon_enter", "on_gift_collected", "on_void_fall",
		"on_mine_defused", "on_barrier_absorbed"]
## World event kind -> the hook it triggers. Kinds come from both event shapes (sim events
## key on "type", controller raw dicts on "e"): gifts.gd, beacon.gd, controller.gd, mines.gd.
const EVENT_HOOKS := {
	"gift_collected": "on_gift_collected",
	"beacon_enter": "on_beacon_enter",
	"void_fall": "on_void_fall",
	"mine_defused": "on_mine_defused",
	"mine_shielded": "on_barrier_absorbed",
}
## The economy's x1.00 chain in centi (sim/economy.gd CHAIN_START_CENTI).
const CHAIN_BASE_CENTI := 100


## World-level api handed to every module hook that declares two parameters. Gold moves
## through the economy's integer centi purse; the chain save marks a chain_reset event in
## the CURRENT tick's list so the app's economy pass skips it; the run-speed boost is a
## tick counter the app reads every tick before the controller steps.
class UpgradeApi:
	extends RefCounted

	var economy: RefCounted = null
	var events: Array = []            # the running dispatch's event list
	var boost_mul := 1.0              # the live run-speed boost multiplier
	var boost_ticks := 0              # controller steps the boost still covers

	## The purse in centi-gold (0 with no economy).
	func purse_centi() -> int:
		return int(economy.purse_centi) if economy != null else 0

	## Adds centi-gold to the purse (integer, never negative here: a gain only).
	func add_centi(n: int) -> void:
		if economy != null and n > 0:
			economy.purse_centi = int(economy.purse_centi) + n

	## True while a chain worth protecting is running: the gold phase is on and the chain
	## stands above x1.00 (a reset at x1.00 costs nothing, so it is not worth a save).
	func chain_live() -> bool:
		if economy == null or not bool(economy.gold_phase):
			return false
		return int(economy.chain_centi) > CHAIN_BASE_CENTI

	## Marks the first unsaved chain_reset with reason `why` in this tick's list as saved;
	## the app's economy pass never breaks the chain for a saved entry. False when no such
	## entry exists (nothing was spent).
	func save_chain(why: String) -> bool:
		for e in events:
			if not (e is Dictionary):
				continue
			var d: Dictionary = e
			if str(d.get("e", d.get("type", ""))) != "chain_reset":
				continue
			if str(d.get("why", "")) != why or bool(d.get("saved", false)):
				continue
			d["saved"] = true
			return true
		return false

	## Starts (or refreshes) a run-speed boost: mul for the next `ticks` controller steps.
	## A refresh never shortens a running boost and keeps the larger multiplier.
	func boost_speed(mul: float, ticks: int) -> void:
		if ticks <= 0 or mul <= 0.0:
			return
		boost_mul = mul if boost_ticks <= 0 else maxf(boost_mul, mul)
		boost_ticks = maxi(boost_ticks, ticks)


# ---- the dispatcher -------------------------------------------------------------------------

## [{"id": String, "mod": Script, "argc": {hook name: parameter count}}], sorted by id.
var modules: Array = []
var state: Dictionary = {}
var api: UpgradeApi = null


## The owned stacks (> 0) of a ledger stacks dict, as a fresh id -> int dict.
static func held_of(stacks: Dictionary) -> Dictionary:
	var out := {}
	for id in stacks.keys():
		var n := int(stacks[id])
		if n > 0:
			out[str(id)] = n
	return out


## Sorted owned ids, the dispatch order.
static func held_ids(stacks: Dictionary) -> Array:
	var ids: Array = held_of(stacks).keys()
	ids.sort()
	return ids


## The method-name -> parameter-count table of a module script (static funcs included).
static func method_argc(script: Script) -> Dictionary:
	var out := {}
	if script == null:
		return out
	for m in script.get_script_method_list():
		out[str(m.get("name", ""))] = (m.get("args", []) as Array).size()
	return out


## The owned modules that declare at least one dispatched hook, sorted by id.
## loader: id -> the module Script, or null (a declarative upgrade has no module).
static func _modules_for(stacks: Dictionary, loader: Callable) -> Array:
	var out: Array = []
	for id in held_ids(stacks):
		var mod: Variant = loader.call(id) if loader.is_valid() else null
		if mod == null or not (mod is Script):
			continue
		var argc := method_argc(mod)
		var any := false
		for h in HOOKS:
			if argc.has(h):
				any = true
				break
		if any:
			out.append({"id": id, "mod": mod, "argc": argc})
	return out


## LOBBY ENTRY (no level exists): dispatch on_curse_draw over every UNRESOLVED curse bay of
## a lobby's bay list (sim/intermission.gd bays: kind "C", "altars"). A module edits the
## altars in place (the bounty shown is the bounty paid on pick, intermission.gd
## _select_curse). Call it after the lobby is created and again after every select: a
## reroll redraws a bay with fresh altars, and a module keeps its edit idempotent, so a
## repeat call on an unchanged bay changes nothing. Returns the number of hook calls made.
static func curse_draw(bays: Array, stacks: Dictionary, loader: Callable,
		p_level: int = 0) -> int:
	var mods := _modules_for(stacks, loader)
	if mods.is_empty():
		return 0
	var calls := 0
	var held := held_of(stacks)
	for bay in bays:
		if not (bay is Dictionary):
			continue
		var b: Dictionary = bay
		if str(b.get("kind", "")) != "C" or bool(b.get("resolved", false)):
			continue
		var st := {"upgrades_held": held, "upgrade_st": {}, "level": p_level,
				"altars": b.get("altars", []), "bay": b}
		for m in mods:
			var argc: Dictionary = m["argc"]
			if not argc.has("on_curse_draw"):
				continue
			if int(argc["on_curse_draw"]) <= 1:
				m["mod"].call("on_curse_draw", st)
			else:
				m["mod"].call("on_curse_draw", st, null)
			calls += 1
	return calls


## Build the dispatcher for one level. ctx keys: players, economy, beacon, level, tick.
func setup(stacks: Dictionary, loader: Callable, ctx: Dictionary) -> void:
	clear()
	modules = _modules_for(stacks, loader)
	api = UpgradeApi.new()
	api.economy = ctx.get("economy", null)
	state = {
		"upgrades_held": held_of(stacks),
		"upgrade_st": {},
		"tick": int(ctx.get("tick", 0)),
		"level": int(ctx.get("level", 0)),
		"players": ctx.get("players", []),
		"economy": api.economy,
		"beacon": ctx.get("beacon", null),
		"events": [],
		"event": {},
	}


## True when at least one owned upgrade has a hook module (anything to dispatch).
func active() -> bool:
	return not modules.is_empty()


## The owned ids this dispatcher drives (sorted).
func module_ids() -> Array:
	var out: Array = []
	for m in modules:
		out.append(m["id"])
	return out


## Drop every module, the per-level scratch and any running boost (teardown / next build).
func clear() -> void:
	modules = []
	state = {}
	api = null


# ---- the world entry points (the app calls these) --------------------------------------------

## One pass over this tick's event list, from index `from` to the list's size at the call:
## every event kind in EVENT_HOOKS dispatches its hook once, in list order. Runs BEFORE the
## economy pass, so gold a hook pays and a chain_reset a hook saves land this tick.
func dispatch_events(tick_now: int, ev: Array, from: int = 0) -> void:
	if modules.is_empty():
		return
	var n := ev.size()
	for k in range(maxi(from, 0), n):
		var e: Variant = ev[k]
		if not (e is Dictionary):
			continue
		var kind := str((e as Dictionary).get("e", (e as Dictionary).get("type", "")))
		if not EVENT_HOOKS.has(kind):
			continue
		state["event"] = e
		_dispatch(str(EVENT_HOOKS[kind]), tick_now, ev)
	state["event"] = {}


## The run-speed multiplier for THIS controller step, consuming one tick of a running
## boost. 1.0 with no boost. The app multiplies the controller's run_speed stat by it.
func speed_step() -> float:
	if api == null or api.boost_ticks <= 0:
		return 1.0
	api.boost_ticks -= 1
	return api.boost_mul


## The boost ticks still to run (0 when none) - a read for the HUD and the tests.
func boost_ticks() -> int:
	return int(api.boost_ticks) if api != null else 0


# ---- internals -------------------------------------------------------------------------------

## Call `hook` on every module that declares it, in sorted id order.
func _dispatch(hook: String, tick_now: int, ev: Array) -> void:
	state["tick"] = tick_now
	state["events"] = ev
	if api != null:
		api.events = ev
	for m in modules:
		var argc: Dictionary = m["argc"]
		if not argc.has(hook):
			continue
		if int(argc[hook]) <= 1:
			m["mod"].call(hook, state)
		else:
			m["mod"].call(hook, state, api)
	if api != null:
		api.events = []
