extends RefCounted
#
# T-051 scripted curses - the GENERAL family (DESIGN.md section 7.2). The 11
# "script": true curses whose requires_enemy is null:
#   cold_start, crowded_dais, crumbling, curfew, dull_gifts, early_bird, leaky_purse,
#   no_refunds, rearguard, slow_door, unmarked.
# One test per curse, each asserting the JSON's own rule sentence. The enemy-linked
# half is the other worker's tests/test_curses_scripted_enemy.gd - nothing here names
# their curses, and every helper lives IN THIS FILE (no shared helper file).
#
# Module contract (DECISIONS D-T051-1): game/content/curses/<id>.gd, handlers named
# after the CLOSED hook list of core/hooks.gd, signature handler(state, api) ->
# <Array events | void>; every module self-guards on its own held stacks. The state
# keys the modules read/write (each documented in the module header):
#   "players"  Array of T-012 controller instances     "economy"  sim/economy.gd
#   "beacon"   sim/beacon.gd instance                  "tick"     level's 60 Hz tick
#   "enemies"  world mirror rows (x/y/z)               "events"   event sink (Array)
#   "enemy_runtime" sim/enemy_runtime.gd instance      "spawn_plan" the runtime's planned[]
#   "curses_held" {curse_id: stacks}                   "curse_st" per-curse slots
#
# GENERAL FAMILY NOTES (the basis of the rule readings):
#   - unmarked: suppresses ONLY the straggler rule
#   - dull_gifts: only the rim glow's radius changes; the gifts keep their values
#   - no_refunds: affects the U/REST bay's reroll altar
#   - early_bird: SPAWN_DELAY_TICKS 120; the runtime keeps its statutes otherwise
#   - leaky_purse: 5 % of the level's earned gold, whole gold floors, 20 g cap (T-CAP)
#   - curfew: 3600 ticks after the open tick, +2 tiers, TEAMCAP: clamp at
#     overtime_max_tier, one-shot
#   - cold_start: D-062's ruling + the glider's 0-energy reading (D-T051-3); never
#     touches jump_velocity/gravity/run_speed (the section 7.2 budget)
#   - crowded_dais: 3D distance, inclusive at 8.0 u (D-T051-1)
#   - slow_door: 3.0 s of continuous standing (180 whole ticks)
#   - rearguard: exactly one extra body per beacon open, id-copy at the beacon axis
#   - crumbling: schedule-only module; the world write is the dispatcher's
#
# While the hook dispatcher does not exist yet in sim/ (hook wiring is parked with the
# Field Dressing backlog row), these tests fire the handlers directly over REAL sim
# objects (T-012 controllers, sim/economy.gd, sim/beacon.gd, sim/gifts.gd, sim/
# enemy_runtime.gd) - the same objects a real dispatcher would pass.

const ControllerScript := preload("res://sim/controller.gd")
const EconomyScript := preload("res://sim/economy.gd")
const BeaconScript := preload("res://sim/beacon.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const EnemyRuntimeScript := preload("res://sim/enemy_runtime.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const HooksScript := preload("res://core/hooks.gd")
const TestUtil := preload("res://tests/sim_testutil.gd")

const Unmarked := preload("res://content/curses/unmarked.gd")
const NoRefunds := preload("res://content/curses/no_refunds.gd")
const DullGifts := preload("res://content/curses/dull_gifts.gd")
const ColdStart := preload("res://content/curses/cold_start.gd")
const EarlyBird := preload("res://content/curses/early_bird.gd")
const LeakyPurse := preload("res://content/curses/leaky_purse.gd")
const Curfew := preload("res://content/curses/curfew.gd")
const CrowdedDais := preload("res://content/curses/crowded_dais.gd")
const SlowDoor := preload("res://content/curses/slow_door.gd")
const Rearguard := preload("res://content/curses/rearguard.gd")
const Crumbling := preload("res://content/curses/crumbling.gd")

## The 11 modules, in the DECISIONS order (one test per curse below, same order).
const MODULES: Array = [
	Unmarked, NoRefunds, DullGifts, ColdStart, EarlyBird,
	LeakyPurse, Curfew, CrowdedDais, SlowDoor, Rearguard, Crumbling,
]


func run() -> Array[String]:
	var f: Array[String] = []
	_t_unmarked(f)
	_t_no_refunds(f)
	_t_dull_gifts(f)
	_t_cold_start(f)
	_t_early_bird(f)
	_t_leaky_purse(f)
	_t_curfew(f)
	_t_crowded_dais(f)
	_t_slow_door(f)
	_t_rearguard(f)
	_t_crumbling(f)
	_t_module_contract(f)
	return f


# ---- helpers -------------------------------------------------------------------

func _check(f: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		f.append(msg)


func _eqf(f: Array[String], got: float, want: float, msg: String) -> void:
	if not is_equal_approx(got, want):
		f.append("%s (got %s, want %s)" % [msg, str(got), str(want)])


func _eqi(f: Array[String], got: int, want: int, msg: String) -> void:
	if got != want:
		f.append("%s (got %d, want %d)" % [msg, got, want])


func _eqs(f: Array[String], got: String, want: String, msg: String) -> void:
	if got != want:
		f.append("%s (got '%s', want '%s')" % [msg, got, want])


func _held(id: String, stacks: int = 1) -> Dictionary:
	return {"curses_held": {id: stacks}}


## Minimal world dict (the T-020 test fixture's shape, one row of floor tiles).
func _world() -> Dictionary:
	var w: Dictionary = TestUtil.world_from_tiles([[3, 0, 0, 0, 0]])
	return w


# The test's own RNG stand-in: FakeRng pins the rearguard pick order exactly (its u32()
# returns the fixed s). A test-local stub - the enemy runtime keeps its stream shape.
class FakeRng:
	extends RefCounted
	var s: int = 0
	func u32() -> int:
		return s


# The api stub a future dispatcher hands a curse: the DESIGN.md section 12 curse-API
# surface the modules duck-type against, captured on this object.
class FakeApi:
	extends RefCounted
	var spawns: Array = []
	var gold: Array = []
	var rng_stream: RefCounted = null

	func _init(p_rng: RefCounted = null) -> void:
		rng_stream = p_rng

	func rng() -> RefCounted:
		return rng_stream

	func spawn_enemy(id: String, pos: Vector3) -> void:
		spawns.append({"id": id, "x": pos.x, "y": pos.y, "z": pos.z})

	func add_gold(g: int) -> void:
		gold.append(g)


## A real sim/beacon.gd over the synthetic level, OPEN. state carries it under
## "beacon" (the D-T051-1 state shape); a missing beacon row in the level dict is
## never a crash (the registry refuses such a level at boot).
func _open_beacon_state() -> Dictionary:
	var b: RefCounted = BeaconScript.create({"beacon": [0, 0, 1]})
	b.open(0)
	var st := {"beacon": b, "players": [], "enemies": [], "events": [], "tick": 0,
			"curse_st": {}, "curses_held": {}}
	return st


# A player controller helper: instance + setup(kit, consts()) + place on the dais
# spawn tile; used by the cold_start/slow_door tests (position (0.5, y, 0.5) whenever
# the caller asks). RefCounted; no engine surface.
func _ctl(kit: String) -> RefCounted:
	var ctl = ControllerScript.new()
	ctl.setup(kit, TestUtil.consts())
	return ctl


## One controller of kit (place its towers at (0.5, 0.5, 0.5) - the dais world centre).
func _t_unmarked(f: Array[String]) -> void:
	# "no straggler beam"
	var g: RefCounted = GiftsScript.create(_synthetic_gifts([0, 0, 0, 0, 0, 0]))
	for i in 5:
		GiftsScript.bit_set(g.black_taken, i)
	var tgr := Unmarked.straggler_ids(_held("unmarked"), g)
	_check(f, tgr.is_empty(), "unmarked: straggler list not emptied (%s)" % str(tgr))
	var tgr_off := Unmarked.straggler_ids({"curses_held": {}}, g)
	_eqi(f, tgr_off.size(), 1, "unmarked: without the curse the sim's straggler list changed shape")
	_eqi(f, int(tgr_off[0]), 5, "unmarked: straggler is not the last real gift")
	# ... and passthrough never twinkled the sim's own rule slot (gifts untouched):
	_eqi(f, g.total_real, 6, "unmarked: gifts' tally moved")


func _t_no_refunds(f: Array[String]) -> void:
	# "shop reroll plinth is gone"
	_check(f, not NoRefunds.reroll_plinth_visible(_held("no_refunds")),
			"no_refunds: reroll plinth still visible with the curse held")
	_check(f, NoRefunds.reroll_plinth_visible({"curses_held": {}}),
			"no_refunds: reroll plinth gone without the curse")


func _t_dull_gifts(f: Array[String]) -> void:
	# "black gift rim glow visible only within 20 u"
	var held := _held("dull_gifts")
	_check(f, DullGifts.rim_glow_visible(held, 0.0, 0.0, 0.0, 19.9, 0.0, 0.0),
			"dull_gifts: 19.9 u (inside 20) lost the glow")
	_check(f, not DullGifts.rim_glow_visible(held, 0.0, 0.0, 0.0, 20.05, 0.0, 0.0),
			"dull_gifts: 20.05 u (outside 20) still glows")
	_check(f, DullGifts.rim_glow_visible({"curses_held": {}}, 0.0, 0.0, 0.0, 90.0, 0.0, 0.0),
			"dull_gifts: without the curse the far glow went dark")
	_check(f, is_equal_approx(float(DullGifts.GLOW_RADIUS_U), 20.0),
			"dull_gifts: GLOW_RADIUS_U is not 20")


## A real sim/gifts.gd over a synthetic level dict (the test_gifts.gd fixture shape):
## occs are the slots' occupancies down the x = 3 column, z spacing 3.
func _synthetic_gifts(occs: Array) -> Dictionary:
	var gifts: Array = []
	var tiles: Array = []
	for i in occs.size():
		var z: int = i * 3
		gifts.append({"id": i, "x": 3, "z": z, "y": 0, "piece": 0, "tier": 0, "occ": occs[i]})
		tiles.append([3, z, 0, 0, 0])
	return {
		"gen_version": 0, "seed": 0, "level": 1, "players": 1, "extra_mines": 0, "attempt": 0,
		"beacon": [0, 0, 1], "spawns": [[0, 0, 1]], "arms": [], "pieces": [],
		"tiles": tiles, "props": [], "edges": [], "gifts": gifts, "anchors": [], "pads": [],
	}


func _t_cold_start(f: Array[String]) -> void:
	# "class ability starts each level on cooldown and recharges 25% slower
	#  (Athletic: coyote time -0.05 s instead)"
	# dasher: starts on cooldown, regen duration x1.25.
	var ctl = _ctl("dasher")
	var regen0: float = float(ctl.C["dash_regen"])
	_eqf(f, regen0, 3.0, "cold_start: dash_regen base moved (data/player.json)")
	var st := {"players": [ctl], "curses_held": {"cold_start": 1}}
	ColdStart.on_level_start(st, null)
	_eqf(f, float(ctl.C["dash_regen"]), regen0 * 1.25, "cold_start: dasher regen not 25% slower")
	_eqf(f, float(ctl.dash_cd), float(ctl.C["dash_regen"]), "cold_start: dasher not on cooldown")
	_check(f, not bool(ctl.dash_ready), "cold_start: dasher dash marked ready at level start")
	# and the recharge REALLY takes 25 % longer: 3.75 s of regen (was 3.0). The ready
	# step is the 225th/226th (the pure-float countdown 3.75 - n/60 crosses 0 at either
	# n = 225 or n = 226 depending on accumulation order; the BASE value 3.0 would be
	# ready at n = 180/181, so the slow is what the window pins).
	var w := _world()
	var ready_tick := -1
	for i in range(300):
		ctl.step(TestUtil.DT, TestUtil.mk_in(0, 0), w)
		if bool(ctl.dash_ready) and ready_tick < 0:
			ready_tick = i
	_check(f, ready_tick >= 224 and ready_tick <= 225,
			"cold_start: dasher ready after %d steps, want 225 (+/-1 float tick; 3.0 -> 3.75 s)"
					% (ready_tick + 1))
	_check(f, ready_tick >= 179, "cold_start: dasher regen got FASTER, not slower")
	# glider: the ability IS the glide; "starts on cooldown" = 0 energy (D-T051-3).
	var gl = _ctl("glider")
	ColdStart.on_level_start({"players": [gl], "curses_held": {"cold_start": 1}}, null)
	_eqf(f, float(gl.glide_energy), 0.0, "cold_start: glider did not start at 0 glide energy")
	# athletic: the D-062 substitute, coyote time -0.05 s, never below 0.
	var ath = _ctl("athletic")
	_eqf(f, float(ath.C["coyote_time"]), 0.10, "cold_start: athletic coyote base moved")
	ColdStart.on_level_start({"players": [ath], "curses_held": {"cold_start": 1}}, null)
	_eqf(f, float(ath.C["coyote_time"]), 0.05, "cold_start: athletic coyote not -0.05 s")
	# NOT held: nothing moves (guards, not globals).
	var fresh = _ctl("dasher")
	var regen_plain: float = float(fresh.C["dash_regen"])
	ColdStart.on_level_start({"players": [fresh], "curses_held": {}}, null)
	_eqf(f, float(fresh.C["dash_regen"]), regen_plain, "cold_start: not-held run still slowed the regen")
	# the section 7.2 safety rule: the curse never touches jump velocity, gravity or
	# run speed (verified on a held run).
	var safe = _ctl("dasher")
	ColdStart.on_level_start({"players": [safe], "curses_held": {"cold_start": 1}}, null)
	_eqf(f, float(safe.C["jump_velocity"]), 12.0, "cold_start: jump_velocity moved")
	_eqf(f, float(safe.C["gravity"]), 32.0, "cold_start: gravity moved")
	_eqf(f, float(safe.C["run_speed"]), 9.0, "cold_start: run_speed moved")


func _t_early_bird(f: Array[String]) -> void:
	# "enemies spawn 2 s after level start instead of 6 s"
	var ctl = _ctl("dasher")
	var rt: RefCounted = EnemyRuntimeScript.new()
	rt.setup({"tiles": [], "beacon": [0, 0, 1], "spawns": [[0, 0, 1]]}, _world(), [ctl], 7)
	_eqi(f, int(rt.spawn_delay_ticks), 360, "early_bird: base spawn delay is not 360")
	EarlyBird.on_level_start({"enemy_runtime": rt, "curses_held": {"early_bird": 1}}, null)
	_eqi(f, int(rt.spawn_delay_ticks), 120, "early_bird: spawn delay is not 120 ticks (2 s)")
	# not held: the base 360 stays
	var rt2: RefCounted = EnemyRuntimeScript.new()
	rt2.setup({"tiles": [], "beacon": [0, 0, 1], "spawns": [[0, 0, 1]]}, _world(), [ctl], 7)
	EarlyBird.on_level_start({"enemy_runtime": rt2, "curses_held": {}}, null)
	_eqi(f, int(rt2.spawn_delay_ticks), 360, "early_bird: not-held run still moved the spawn delay")


func _t_leaky_purse(f: Array[String]) -> void:
	# "a void fall drops 5% of this level's earned gold (max 20 g per fall)"
	var econ: RefCounted = EconomyScript.create({}, null)
	econ.add_gold(10)  # pre-level purse: 10 g
	var st := {"economy": econ, "events": [], "curse_st": {}, "curses_held": {"leaky_purse": 1}}
	LeakyPurse.on_level_start(st, null)
	econ.add_gold(50)  # 50 g earned this level (purse 60 g = 6000 centi)
	LeakyPurse.on_void_fall(st, null)
	_eqi(f, int(econ.purse_centi), 5800, "leaky_purse: fall 1 drop is not floor(5% x 50 g) = 2 g")
	# the 20 g cap: 2000 more g earned (2058 g in purse) -> 5% would be ~102 g; cap 20.
	econ.add_gold(2000)
	LeakyPurse.on_void_fall(st, null)
	_eqi(f, int(econ.purse_centi), 205800 - 2000, "leaky_purse: the 20 g cap did not hold")
	# the drop FLOORS: 5 % of 1.01 g (101 centi) is 5.05 centi -> 0 g; of 20.00 g -> 1 g.
	_eqi(f, LeakyPurse.drop_gold(101), 0, "leaky_purse: 1.01 g earned should floor to 0 g")
	_eqi(f, LeakyPurse.drop_gold(2000), 1, "leaky_purse: 20.00 g earned should drop floor(1.00) = 1 g")
	# and with the curse NOT held a fall costs nothing:
	var econ2: RefCounted = EconomyScript.create({}, null)
	econ2.add_gold(100)
	var st2 := {"economy": econ2, "events": [], "curse_st": {}, "curses_held": {}}
	LeakyPurse.on_level_start(st2, null)
	econ2.add_gold(50)
	LeakyPurse.on_void_fall(st2, null)
	_eqi(f, int(econ2.purse_centi), 15000, "leaky_purse: not-held run still dropped gold")


func _t_curfew(f: Array[String]) -> void:
	# "60 s after the beacon opens, overtime jumps +2 tiers"
	var econ: RefCounted = EconomyScript.create({}, null)
	econ.begin_gold_phase()
	var st := {"economy": econ, "events": [], "curse_st": {}, "curses_held": {"curfew": 1},
			"tick": 0}
	Curfew.on_beacon_open(st, null)
	for t in 3600:
		st["tick"] = t
		Curfew.on_tick(st, null)
	_eqi(f, int(econ.overtime_tier), 0, "curfew: the tier jumped before 60 s")
	st["tick"] = 3600
	Curfew.on_tick(st, null)
	_eqi(f, int(econ.overtime_tier), 2, "curfew: the +2 tier jump is missing at 60 s")
	st["tick"] = 3601
	Curfew.on_tick(st, null)
	_eqi(f, int(econ.overtime_tier), 2, "curfew: the jump fired twice")
	# the clamp: past the economy's own max_tier the jump lands at exactly the cap.
	var econ2: RefCounted = EconomyScript.create({}, null)
	econ2.begin_gold_phase()
	var st2 := {"economy": econ2, "events": [], "curse_st": {}, "curses_held": {"curfew": 1},
			"tick": 0}
	Curfew.on_beacon_open(st2, null)
	econ2.overtime_tier = int(econ2.overtime_max_tier) - 1
	st2["tick"] = 3600
	Curfew.on_tick(st2, null)
	_eqi(f, int(econ2.overtime_tier), int(econ2.overtime_max_tier),
			"curfew: the +2 did not clamp at the economy's overtime_max_tier")
	# not held: no open tick is recorded and the jump never fires.
	var econ3: RefCounted = EconomyScript.create({}, null)
	econ3.begin_gold_phase()
	var st3 := {"economy": econ3, "events": [], "curse_st": {}, "curses_held": {},
			"tick": 4000}
	Curfew.on_beacon_open(st3, null)
	Curfew.on_tick(st3, null)
	_eqi(f, int(econ3.overtime_tier), 0, "curfew: not-held run still jumped the tiers")


func _t_crowded_dais(f: Array[String]) -> void:
	# "the beacon cannot be entered while any enemy is within 8 u of it"
	var st := _open_beacon_state()
	st["curses_held"] = {"crowded_dais": 1}
	st["enemies"] = [{"x": 0.5, "y": 0.5, "z": 5.0}]  # 4.5 u from the beacon axis
	_check(f, CrowdedDais.entry_blocked(st), "crowded_dais: an enemy 4.5 u away did not block")
	st["enemies"] = [{"x": 0.5, "y": 0.5, "z": 8.5}]  # 8.0 u even - inclusive, still blocks
	_check(f, CrowdedDais.entry_blocked(st), "crowded_dais: exactly 8 u did not block")
	st["enemies"] = [{"x": 0.5, "y": 0.5, "z": 9.0}]  # 8.5 u - free
	_check(f, not CrowdedDais.entry_blocked(st), "crowded_dais: 8.5 u away still blocked")
	st["enemies"] = []
	_check(f, not CrowdedDais.entry_blocked(st), "crowded_dais: no enemy - entry blocked anyway")
	# vertical offset alone can creep under 8 u (3D distance, D-T051-1):
	st["enemies"] = [{"x": 0.5, "y": 7.5, "z": 0.5}]
	_check(f, CrowdedDais.entry_blocked(st), "crowded_dais: somebody directly overhead did not block")
	# not held: never blocks
	st["curses_held"] = {}
	st["enemies"] = [{"x": 0.5, "y": 0.5, "z": 0.5}]
	_check(f, not CrowdedDais.entry_blocked(st), "crowded_dais: not-held run blocked the dais")


func _t_slow_door(f: Array[String]) -> void:
	# "entering the beacon takes 3.0 s of standing in it"
	var st := _open_beacon_state()
	st["curses_held"] = {"slow_door": 1}
	var ctl = _ctl("dasher")
	ctl.x = 0.5
	ctl.y = 0.5
	ctl.z = 0.5  # inside the trigger cylinder (radius 1.5, height 3 over base_y 0.5)
	st["players"] = [ctl]
	SlowDoor.on_level_start(st, null)
	for i in 180:
		SlowDoor.on_tick(st, null)
		if i == 178:  # 179 ticks of standing = 2.983 s: NOT yet ready
			_check(f, not SlowDoor.entry_ready(st, 0), "slow_door: entry ready before 3.0 s")
	_check(f, SlowDoor.entry_ready(st, 0), "slow_door: 180 ticks of standing did not open the door")
	_eqf(f, SlowDoor.dwell_s(st, 0), 3.0, "slow_door: dwell clock is not 3.0 s at 180 ticks")
	# stepping OUT resets the clock (continuous standing only):
	ctl.z = 5.0
	SlowDoor.on_tick(st, null)
	_check(f, not SlowDoor.entry_ready(st, 0), "slow_door: leaving the beacon kept the dwell")
	# not held: the door is instant.
	var st2 := _open_beacon_state()
	SlowDoor.on_level_start(st2, null)
	_check(f, SlowDoor.entry_ready(st2, 0), "slow_door: not-held run still gated the door")


func _t_rearguard(f: Array[String]) -> void:
	# "when the beacon opens, one extra copy of a random enemy in play spawns at the beacon"
	var st := _open_beacon_state()
	st["curses_held"] = {"rearguard": 1}
	st["spawn_plan"] = [{"id": "kiwi_cat", "copies": 1}, {"id": "coil", "copies": 2}]
	var rng := FakeRng.new()
	rng.s = 1  # pins the pick to plan_ids[1]
	var api := FakeApi.new(rng)
	Rearguard.on_beacon_open(st, api)
	_eqi(f, api.spawns.size(), 1, "rearguard: not exactly ONE extra spawn")
	if api.spawns.size() == 1:
		_eqs(f, str(api.spawns[0]["id"]), "coil", "rearguard: the pick ignored the rng stream")
		_eqf(f, float(api.spawns[0]["x"]), 0.5, "rearguard: spawn is not at the beacon axis x")
		_eqf(f, float(api.spawns[0]["y"]), 0.5, "rearguard: spawn is not at the beacon floor y")
		_eqf(f, float(api.spawns[0]["z"]), 0.5, "rearguard: spawn is not at the beacon axis z")
	# not held: no spawn at all.
	var st2 := _open_beacon_state()
	st2["spawn_plan"] = [{"id": "kiwi_cat", "copies": 1}]
	var api2 := FakeApi.new(null)
	Rearguard.on_beacon_open(st2, api2)
	_eqi(f, api2.spawns.size(), 0, "rearguard: not-held run still spawned an enemy")
	# nothing in play: a no-op, never a crash.
	var st3 := _open_beacon_state()
	st3["curses_held"] = {"rearguard": 1}
	var api3 := FakeApi.new(null)
	Rearguard.on_beacon_open(st3, api3)
	_eqi(f, api3.spawns.size(), 0, "rearguard: an empty play spawned something")


func _t_crumbling(f: Array[String]) -> void:
	# "1-wide walkway tiles fall 1.2 s after being stepped on and return after 5 s"
	var st := {"tick": 0, "curse_st": {}, "curses_held": {"crumbling": 1}}
	var row: Dictionary = Crumbling.step_on(st, "0,0,0")
	_eqi(f, int(row["fall_tick"]), 72, "crumbling: the fall is not 72 ticks (1.2 s) out")
	_eqi(f, int(row["return_tick"]), 372, "crumbling: the return is not 300 ticks (5 s) after the fall")
	# silence until the fall tick, the fall exactly once, the return exactly at fall+300:
	var seen_fall := 0
	var seen_return := 0
	for t in 400:
		st["tick"] = t
		for ev in Crumbling.on_tick(st):
			if str(ev["e"]) == "tile_fell":
				seen_fall += 1
				_eqi(f, t, 72, "crumbling: fell at tick %d, want 72" % t)
			elif str(ev["e"]) == "tile_returned":
				seen_return += 1
				_eqi(f, t, 372, "crumbling: returned at tick %d, want 372" % t)
	_eqi(f, seen_fall, 1, "crumbling: the tile did not fall exactly once")
	_eqi(f, seen_return, 1, "crumbling: the tile did not return exactly once")
	# re-stepping never restarts a fallen tile's clock (the first schedule wins):
	st["tick"] = 200
	var row2: Dictionary = Crumbling.step_on(st, "0,0,0")
	_eqi(f, int(row2["fall_tick"]), 72, "crumbling: a re-step restarted the schedule")
	# a second tile is an independent schedule:
	st["tick"] = 400
	_eqi(f, int(Crumbling.step_on(st, "0,0,1")["fall_tick"]), 472,
			"crumbling: a second tile is not on its own clock")


# ---- the module contract ---------------------------------------------------------------

## Every "script": true curse with requires_enemy null (the family THIS ticket owns)
## has a module here, whose CURSE_ID is the JSON id and whose source quotes the JSON's
## own rule sentence VERBATIM (whitespace-normalised) - one rule sentence, asserted.
func _t_module_contract(f: Array[String]) -> void:
	var api: RefCounted = ContentApiScript.load()
	if not api.call("is_ok"):
		f.append("module contract: content api boot failed")
		return
	var family: Array[String] = []
	for id in api.call("curse_ids"):
		var doc: Dictionary = api.call("curse", id)
		if bool(doc.get("script", false)) and doc.get("requires_enemy") == null:
			family.append(id)
	_eqi(f, family.size(), 11, "general scripted family is not 11 curses: %s" % str(family))
	var text_cache := {}
	var modules_by_id := {
		"cold_start": ColdStart, "crowded_dais": CrowdedDais, "crumbling": Crumbling,
		"curfew": Curfew, "dull_gifts": DullGifts, "early_bird": EarlyBird,
		"leaky_purse": LeakyPurse, "no_refunds": NoRefunds, "rearguard": Rearguard,
		"slow_door": SlowDoor, "unmarked": Unmarked,
	}
	for id in family:
		if not modules_by_id.has(id):
			f.append("module contract: no module built for general scripted curse '%s'" % id)
			continue
		var mod = modules_by_id[id]
		var doc: Dictionary = api.call("curse", id)
		_eqs(f, str(mod.CURSE_ID), id, "module contract: CURSE_ID != JSON id (%s)" % id)
		if not text_cache.has(id):
			text_cache[id] = _norm(FileAccess.get_file_as_string("res://content/curses/%s.gd" % id))
		var src: String = text_cache[id]
		if src.is_empty():
			f.append("module contract: cannot read res://content/curses/%s.gd" % id)
			continue
		var rule := _norm(str(doc.get("rule", "")))
		if not src.contains(rule):
			f.append("module contract: %s.gd does not quote its rule sentence verbatim" % id)
		# ... and every hook the module handles IS in core/hooks.gd's closed list.
		for m in mod.get_script_method_list():
			var name := str(m["name"])
			if name.begins_with("on_") and not HooksScript.HOOKS.has(name):
				f.append("module contract: %s handles unknown hook '%s'" % [id, name])


## Whitespace-normalise for the verbatim comparison: collapse all whitespace runs
## (newlines included) to single spaces.
static func _norm(text: String) -> String:
	var merged := text.replace("\n", " ")
	while merged.contains("  "):
		merged = merged.replace("  ", " ")
	return merged.strip_edges()




