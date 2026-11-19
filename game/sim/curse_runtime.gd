extends RefCounted
#
# sim/curse_runtime.gd - the curse hook dispatcher (DESIGN.md section 12's curse hook surface).
#
# Every scripted curse is a static module (extends RefCounted, static funcs only) that
# exposes some of four hooks:
#   on_level_start(state, api)   once per level, after the level and the runtime exist
#   on_tick(state, api)          once per 60 Hz sim tick
#   on_beacon_open(state, api)   on the tick the beacon flips open
#   on_void_fall(state, api)     once per void_fall event the controller reports
# and, separately, pure build-time QUERIES (extra_mines folding, the beacon entry gate)
# the caller asks through the static helpers / query methods below.
#
# Nothing in this file names a content id: the held dictionary's keys are read
# generically, and the modules are resolved through a loader Callable the app hands in
# (sim/ never imports res://content/ - test_boundaries.gd). Hooks are found by
# has_method-equivalent probing of the module's script method list, so a module that
# declares only some hooks is called only for those. A hook declared with ONE parameter
# (state only) is called with state alone; when such a hook returns an Array, its entries
# are appended to the tick's event list.
#
# Determinism: modules run in sorted id order, every hook call reads the same shared
# state dict, and the only randomness is this dispatcher's own stream (see CurseApi.rng),
# seeded from the run seed - a replay of (seed, level, held curses, inputs) is exact.
#
# The shared state dict (the keys the modules read):
#   curses_held    Dictionary id -> stacks (a copy of the run's ledger, stacks > 0 only)
#   curse_st       Dictionary, the modules' per-level scratch; reset by clear()
#   tick           int, the LevelState tick (the same clock the beacon/gifts use)
#   players        Array of the live controllers (index = player index)
#   enemy_runtime  the live EnemyRuntime
#   enemies        the runtime's live rows (rt.enemies)
#   events         Array, the CURRENT tick's world event list (appends land in it)
#   economy        the gold-phase economy (purse / overtime)
#   beacon         the LevelState beacon
#   spawn_plan     Array of {"id", "name", "count"} rows - this level's voted roster

const VoidRngScript := preload("res://terrain/void_rng.gd")

const HOOKS := ["on_level_start", "on_tick", "on_beacon_open", "on_void_fall"]
## The dispatcher's own random stream salt: mixed with the run seed and the level so the
## curse stream never shares state with an enemy row's stream (D-T010-3 streams stay exact).
const RNG_SALT := 0x0C5E0D15

## World-level api handed to every module hook. Not bound to an enemy row (a curse is not
## an enemy): telegraphs announce with an empty source, sync_body re-syncs every live body,
## rng() is the dispatcher's own stream. spawn_enemy and add_gold are the two curse-only
## surfaces the per-row EnemyRuntime.Api does not carry.
class CurseApi:
	extends RefCounted

	var rt: RefCounted = null         # the live EnemyRuntime
	var economy: RefCounted = null    # the gold-phase economy (purse)
	## id -> {"behavior": RefCounted, "cfg": Dictionary, "name": String} or {} when the id
	## cannot be built. Supplied by the app (sim/ may not load content itself).
	var enemy_factory: Callable = Callable()
	var stream: RefCounted = null      # the dispatcher's VoidRng
	## The spawn budget (no runaway growth): per (calling module, enemy id), a curse may add
	## at most as many bodies as the votes planned of that id - one extra body per voted
	## body, which is every spawning module's own rule sentence ("one trailing body per
	## voted body", "one extra copy"). It exists because a spawned body has the same
	## id as its parent, so a module that keys "already served" by row would otherwise
	## serve its own spawn next tick, and the next, without end.
	var planned_counts: Dictionary = {}   # enemy id -> bodies the votes planned
	var spawned_counts: Dictionary = {}   # "module|enemy id" -> bodies spawned this level
	var caller := ""                      # the module whose hook is running (set by _dispatch)

	func nearest_player(pos: Vector3) -> Dictionary:
		return rt.nearest_player(pos) if rt != null else {}

	func players_in_radius(pos: Vector3, r: float) -> Array:
		return rt.players_in_radius(pos, r) if rt != null else []

	func telegraph(kind: String, shape: Dictionary, ticks: int) -> void:
		if rt != null:
			rt.telegraph({}, kind, shape, ticks)

	func kill(player, killer_id: String, code: String = "") -> bool:
		if rt == null:
			return false
		return rt.kill(player, killer_id, code)

	func push(player, dir: Vector3, speed: float) -> void:
		if rt != null:
			rt.push(player, dir, speed)

	## Row-less: a curse may move any row (a dash, a teleport), so every live body mirror
	## is refreshed. The runtime re-syncs them all next step anyway; this is the instant fix.
	func sync_body() -> void:
		if rt == null:
			return
		for row in rt.enemies:
			rt.sync_body_mirror(row)

	## The dispatcher's own seeded stream (one per world, never an enemy row's stream).
	func rng() -> RefCounted:
		return stream

	## Whole gold, may be negative (a drop). The purse is the economy's integer centi field.
	func add_gold(gold: int) -> void:
		if economy != null:
			economy.add_gold(int(gold))

	## Two call shapes, both used by the modules:
	##   spawn_enemy(def: Dictionary)   def = {"id", "name"?, "x","y","z", "cfg"?, "copy_index"?, "copies"?}
	##   spawn_enemy(id: String, pos: Vector3)
	## The behavior always comes from the factory; an explicit def cfg replaces the
	## factory's cfg. Returns the new row, or {} when the id cannot be built or its budget is spent.
	func spawn_enemy(a, b = null) -> Dictionary:
		if rt == null or not enemy_factory.is_valid():
			return {}
		var id := ""
		var pos := Vector3.ZERO
		var def: Dictionary = {}
		if a is Dictionary:
			def = a
			id = str(def.get("id", ""))
			pos = Vector3(float(def.get("x", 0.0)), float(def.get("y", 0.0)),
					float(def.get("z", 0.0)))
		else:
			id = str(a)
			if b is Vector3:
				pos = b
		if id == "":
			return {}
		var budget_key := "%s|%s" % [caller, id]
		var used := int(spawned_counts.get(budget_key, 0))
		if used >= int(planned_counts.get(id, 0)):
			return {}
		var made: Variant = enemy_factory.call(id)
		if not (made is Dictionary) or (made as Dictionary).get("behavior", null) == null:
			return {}
		var cfg: Dictionary = (made as Dictionary).get("cfg", {})
		if def.has("cfg") and def["cfg"] is Dictionary:
			cfg = def["cfg"]
		var nm := str(def.get("name", (made as Dictionary).get("name", id)))
		spawned_counts[budget_key] = used + 1
		return rt.spawn_at(id, nm, made["behavior"], cfg, pos,
				int(def.get("copy_index", 0)), int(def.get("copies", 1)))


# ---- the dispatcher -------------------------------------------------------------------------

## [{"id": String, "mod": Script, "argc": {hook name: parameter count}}], sorted by id.
var modules: Array = []
var state: Dictionary = {}
var api: CurseApi = null
## Events a hook raised outside a tick (level start); drained into the first tick's list.
var pending: Array = []


## The held stacks (> 0) of a ledger curses dict, as a fresh id -> int dict.
static func held_of(curses_held: Dictionary) -> Dictionary:
	var out := {}
	for id in curses_held.keys():
		var n := int(curses_held[id])
		if n > 0:
			out[str(id)] = n
	return out


## Sorted held ids, the dispatch order.
static func held_ids(curses_held: Dictionary) -> Array:
	var ids: Array = held_of(curses_held).keys()
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


## BUILD-TIME QUERY (no runtime exists yet): fold the roster's extra mines through every
## held module that declares total_extra_mines(state, roster_extra). A module without the
## query leaves the number unchanged. loader: id -> Script or null.
static func extra_mines(curses_held: Dictionary, roster_extra: int, loader: Callable) -> int:
	var st := {"curses_held": held_of(curses_held), "curse_st": {}}
	var total := maxi(roster_extra, 0)
	for id in held_ids(curses_held):
		var mod: Variant = loader.call(id) if loader.is_valid() else null
		if mod == null or not method_argc(mod).has("total_extra_mines"):
			continue
		total = int(mod.call("total_extra_mines", st, total))
	return total


## Build the dispatcher for one level. ctx keys: rt, players, economy, beacon, spawn_plan,
## enemy_factory (Callable), seed (int), level (int), tick (int).
## loader: id -> the module Script, or null for a curse with no module (declarative only).
func setup(curses_held: Dictionary, loader: Callable, ctx: Dictionary) -> void:
	clear()
	var held := held_of(curses_held)
	for id in held_ids(curses_held):
		var mod: Variant = loader.call(id) if loader.is_valid() else null
		if mod == null or not (mod is Script):
			continue
		modules.append({"id": id, "mod": mod, "argc": method_argc(mod)})
	api = CurseApi.new()
	api.rt = ctx.get("rt", null)
	api.economy = ctx.get("economy", null)
	api.enemy_factory = ctx.get("enemy_factory", Callable())
	for row in ctx.get("spawn_plan", []):
		if row is Dictionary:
			var pid := str(row.get("id", ""))
			api.planned_counts[pid] = int(api.planned_counts.get(pid, 0)) + 					maxi(0, int(row.get("count", row.get("copies", 0))))
	api.stream = VoidRngScript.new(VoidRngScript.mix(VoidRngScript.mix(
			int(ctx.get("seed", 0)), RNG_SALT), int(ctx.get("level", 0))))
	state = {
		"curses_held": held,
		"curse_st": {},
		"tick": int(ctx.get("tick", 0)),
		"players": ctx.get("players", []),
		"enemy_runtime": api.rt,
		"enemies": api.rt.enemies if api.rt != null else [],
		"events": pending,
		"economy": api.economy,
		"beacon": ctx.get("beacon", null),
		"spawn_plan": ctx.get("spawn_plan", []),
	}


## True when at least one held curse has a module (anything to dispatch).
func active() -> bool:
	return not modules.is_empty()


## The held ids this dispatcher drives (sorted).
func module_ids() -> Array:
	var out: Array = []
	for m in modules:
		out.append(m["id"])
	return out


## Drop every module and the per-level scratch (teardown / next build).
func clear() -> void:
	modules = []
	state = {}
	api = null
	pending = []


# ---- hook entry points (the app calls these at its hook points) ------------------------------

func level_start(tick: int) -> void:
	_dispatch("on_level_start", tick, pending)


## Once per tick. Any events a level-start hook raised are flushed into this tick first.
func tick(tick_now: int, ev: Array) -> void:
	if not pending.is_empty():
		ev.append_array(pending)
		pending = []
	_dispatch("on_tick", tick_now, ev)


func beacon_open(tick_now: int, ev: Array) -> void:
	_dispatch("on_beacon_open", tick_now, ev)


## fall: the controller's void_fall event (free or charged); exposed to the module as
## state["void_fall"] for the duration of the call.
func void_fall(tick_now: int, ev: Array, fall: Dictionary = {}) -> void:
	state["void_fall"] = fall
	_dispatch("on_void_fall", tick_now, ev)
	state.erase("void_fall")


# ---- live queries (the app asks; the modules answer from the shared state) ------------------

## The beacon entry gate for one player: false when ANY held module refuses entry -
## entry_blocked(state) true (an enemy crowding the dais) or entry_ready(state, i) false
## (a dwell not yet served). A module without either query never blocks.
func entry_allowed(player_index: int) -> bool:
	for m in modules:
		var argc: Dictionary = m["argc"]
		if argc.has("entry_blocked") and bool(m["mod"].call("entry_blocked", state)):
			return false
		if argc.has("entry_ready") and not bool(m["mod"].call("entry_ready", state, player_index)):
			return false
	return true


# ---- internals -------------------------------------------------------------------------------

## Call `hook` on every module that declares it, in sorted id order. The runtime's own
## event list is watched across each call: a spawn / telegraph / kill a hook makes through
## the api lands there, and the runtime resets that list at the start of its next step, so
## the new entries are copied into `ev` (the caller's live tick list) right away.
func _dispatch(hook: String, tick_now: int, ev: Array) -> void:
	if modules.is_empty():
		return
	state["tick"] = tick_now
	state["events"] = ev
	var rt: RefCounted = api.rt if api != null else null
	if rt != null:
		state["enemies"] = rt.enemies
	for m in modules:
		var argc: Dictionary = m["argc"]
		if not argc.has(hook):
			continue
		var n0: int = rt.events.size() if rt != null else 0
		if api != null:
			api.caller = str(m["id"])
		var out: Variant = null
		if int(argc[hook]) <= 1:
			out = m["mod"].call(hook, state)
		else:
			m["mod"].call(hook, state, api)
		if out is Array:
			ev.append_array(out)
		if rt != null:
			var evs: Array = rt.events
			for k in range(n0, evs.size()):
				ev.append(evs[k])
