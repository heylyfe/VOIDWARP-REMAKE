extends RefCounted
#
# T-051 scripted curses - the ENEMY-LINKED modules on main. The 23 "script": true
# curses whose requires_enemy is set AND whose module is merged here:
#   aftershock, bunker_buster, crescendo, direct_shot, double_ring, egoist, litter,
#   long_toll, longer_speech, method_acting, mirror_match, overwound,
#   pup_pack, quarter_chimes, second_strike, slipstream_trail, spreading_rot,
#   token_limit, twin_fangs, unannounced, understudies, wet_floor, wide_blast.
# One test per curse, each asserting the JSON's own rule sentence. The last id of the
# 24-id family, zoomies, is still NOT_ON_MAIN: it is retired from the offer pool
# (commit "Zoomies: retired from the offer pool, not deleted") and its module lives on
# the unmerged t3/scripted-curses-groups-4-6 branch, which the owner ruled must never
# be merged - so it is reimplemented on main only if it ever returns to the pool. The
# module-contract test below pins the full 24-id inventory so that day cannot pass
# silently. Nothing here names the general family's 11 curses, and every helper lives
# IN THIS FILE (no shared helper file).
#
# Module contract (D-T051-1): game/content/curses/<id>.gd, handlers named after the
# CLOSED hook list of core/hooks.gd, signature handler(state, api) -> <void|events>;
# every mutating handler self-guards on its own held stacks. The state keys the
# modules read/write (each documented in the module header):
#   "enemy_runtime" sim/enemy_runtime.gd (its .enemies rows, .world, .projectiles,
#                   .telegraphs, .controllers)
#   "players"       the T-012 controller instances (the controllers are ALSO read as
#                   plain .get("x") rows by the pure helpers - both shapes work)
#   "tick"          the level's 60 Hz tick
#   "curses_held"   {curse_id: stacks}
#   "curse_st"      per-curse scratch slots
#
# The ticket done-whens that are THIS file's:
#   - long_toll: the second ben arrival lands at the same locked point exactly
#     90 ticks (1.5 s) after the first and never kills - proven END-TO-END below
#     against the REAL thicc_ben behavior driven inside a REAL sim/enemy_runtime.gd
#     (the only curse where the rule lives in a behavior contract);
#   - understudies' 20% mine cap: the REAL generator (terrain/voidgen.gd) is run with
#     the curse's flat add on top of the roster's and the placed tripmines are counted
#     against n // 5 - the cap holds and the base roll is untouched (no per-slot chance
#     moved); and
#   - quarter_chimes / pup_pack: the shortened ben interval and the staggered second
#     seal are proven END-TO-END against the REAL behaviors in a REAL runtime.
#
# Where a curse's rule needs the api, the test passes the FakeApi stub and asserts
# on what the module ASKED for (push/kill/spawn/telegraph calls); where the rule is
# a pure read, it calls the module's pure helper and asserts the number. No handler
# is ever called with a null api.

const ControllerScript := preload("res://sim/controller.gd")
const EnemyRuntimeScript := preload("res://sim/enemy_runtime.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const HooksScript := preload("res://core/hooks.gd")
const TestUtil := preload("res://tests/sim_testutil.gd")
const VoidGenScript := preload("res://terrain/voidgen.gd")
const BenScript := preload("res://content/enemies/thicc_ben/enemy.gd")
const SealScript := preload("res://content/enemies/seal/enemy.gd")
const GinScript := preload("res://content/enemies/gin/enemy.gd")

const Aftershock := preload("res://content/curses/aftershock.gd")
const BunkerBuster := preload("res://content/curses/bunker_buster.gd")
const ClawdsScript := preload("res://sim/clawds.gd")
const Crescendo := preload("res://content/curses/crescendo.gd")
const DirectShot := preload("res://content/curses/direct_shot.gd")
const DoubleRing := preload("res://content/curses/double_ring.gd")
const Egoist := preload("res://content/curses/egoist.gd")
const Litter := preload("res://content/curses/litter.gd")
const KiwiScript := preload("res://content/enemies/kiwi_cat/enemy.gd")
const LongToll := preload("res://content/curses/long_toll.gd")
const LongerSpeech := preload("res://content/curses/longer_speech.gd")
const MethodActing := preload("res://content/curses/method_acting.gd")
const MirrorMatch := preload("res://content/curses/mirror_match.gd")
const Overwound := preload("res://content/curses/overwound.gd")

# The reimplemented-on-main group (the 11 ids the audit found inert; the stale
# t3/scripted-curses-groups-4-6 branch is never merged - these are fresh modules).
const QuarterChimes := preload("res://content/curses/quarter_chimes.gd")
const SecondStrike := preload("res://content/curses/second_strike.gd")
const Understudies := preload("res://content/curses/understudies.gd")
const WideBlast := preload("res://content/curses/wide_blast.gd")
const SpreadingRot := preload("res://content/curses/spreading_rot.gd")
const WetFloor := preload("res://content/curses/wet_floor.gd")
const PupPack := preload("res://content/curses/pup_pack.gd")
const SlipstreamTrail := preload("res://content/curses/slipstream_trail.gd")
const Unannounced := preload("res://content/curses/unannounced.gd")
const TokenLimit := preload("res://content/curses/token_limit.gd")
const TwinFangs := preload("res://content/curses/twin_fangs.gd")

## The modules above, in the order the tests run (one _t_ per curse below).
const MODULES: Array = [
	Aftershock, BunkerBuster, Crescendo, DirectShot, DoubleRing, Egoist,
	Litter, LongToll, LongerSpeech, MethodActing, MirrorMatch, Overwound,
	QuarterChimes, SecondStrike, Understudies, WideBlast, SpreadingRot, WetFloor,
	PupPack, SlipstreamTrail, Unannounced, TokenLimit, TwinFangs,
]

## The enemy-linked script-curse ids whose modules are NOT on this checkout yet
## (each lives on the unmerged t3/scripted-curses-groups-4-6 branch; PARKED.md).
const NOT_ON_MAIN: Array[String] = [
	"zoomies",
]


func run() -> Array[String]:
	var f: Array[String] = []
	_t_aftershock(f)
	_t_bunker_buster(f)
	_t_crescendo(f)
	_t_direct_shot(f)
	_t_double_ring(f)
	_t_egoist(f)
	_t_litter(f)
	_t_long_toll(f)
	_t_longer_speech(f)
	_t_method_acting(f)
	_t_mirror_match(f)
	_t_overwound(f)
	_t_quarter_chimes(f)
	_t_second_strike(f)
	_t_understudies(f)
	_t_wide_blast(f)
	_t_spreading_rot(f)
	_t_wet_floor(f)
	_t_pup_pack(f)
	_t_slipstream_trail(f)
	_t_unannounced(f)
	_t_token_limit(f)
	_t_twin_fangs(f)
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


## Minimal flat world (the T-020 test fixture's shape) - one floor strip.
func _world() -> Dictionary:
	return TestUtil.world_from_tiles([[0, 0, 0], [1, 0, 0], [2, 0, 0], [3, 0, 0],
			[0, 1, 0], [10, 10, 0], [11, 10, 0]])


# The api stub a future dispatcher hands a curse: the DESIGN section 12 curse-API
# surface the modules duck-type against, recorded on this object. The stub never
# changes the world itself; assertions read what the module ASKED for.
class FakeApi:
	extends RefCounted
	var pushes: Array = []
	var kills: Array = []
	var spawns: Array = []
	var telegraphs: Array = []
	var near: Dictionary = {}

	func nearest_player(_pos: Vector3) -> Dictionary:
		return near

	func push(i: int, dir: Vector3, speed: float) -> void:
		pushes.append({"i": i, "dir": dir, "speed": speed})

	func kill(i: int, killer_id: String, code: String = "") -> bool:
		kills.append({"i": i, "killer": killer_id, "code": code})
		return true

	func spawn_enemy(def: Dictionary) -> void:
		spawns.append(def)

	func telegraph(kind: String, shape: Dictionary, ticks: int) -> void:
		telegraphs.append({"kind": kind, "shape": shape, "ticks": ticks})

	func sync_body() -> void:
		pass


## A REAL sim/enemy_runtime.gd over the synthetic level, no planned spawns, one
## controller. The modules read rt.enemies / rt.world / rt.telegraphs off it - the
## same objects a hook dispatcher would pass as state["enemy_runtime"].
func _rt() -> RefCounted:
	var ctl = ControllerScript.new()
	ctl.setup("dasher", TestUtil.consts())
	var rt = EnemyRuntimeScript.new()
	rt.setup({"tiles": [], "beacon": [0, 0, 1], "spawns": [[0, 0, 1]]}, _world(),
			[ctl], 7)
	return rt


## One more real T-012 controller of the kit, for tests that need several players.
func _mk_ctl(kit: String) -> RefCounted:
	var ctl = ControllerScript.new()
	ctl.setup(kit, TestUtil.consts())
	return ctl


## One live enemy row on the runtime (real row shape via spawn_at) carrying a no-op
## behavior - the tests drive the CURSE, never the enemy, and patch the fields the
## enemy behavior would own.
func _row(rt: RefCounted, id: String, pos: Vector3, cfg: Dictionary = {}) -> Dictionary:
	return rt.spawn_at(id, id, EnemyRuntimeScript.EnemyBehavior.new(), cfg, pos)


## The state dict a dispatcher hands the handler, over the runtime. `held` may be
## the _held() wrapper or the bare {curse_id: stacks} map - the wrapper is unwrapped.
func _state(rt: RefCounted, held: Dictionary, tick: int) -> Dictionary:
	var stacks: Dictionary = held.get("curses_held", held)
	return {"players": rt.controllers, "enemies": [], "enemy_runtime": rt,
			"economy": null, "beacon": null, "events": [], "tick": tick,
			"curse_st": {}, "curses_held": stacks}

## A real clawd runtime (sim/clawds.gd) over a flat fixture level, for the two curses that push
## their knobs onto it (D-T4-7).
func _clawds():
	var tiles: Array = []
	for x in range(-8, 9):
		for z in range(-8, 9):
			tiles.append([x, z, 0, 0, 0])
	var L := {"seed": 7, "level": 1, "gen_version": 1, "attempt": 0,
			"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "tiles": tiles,
			"props": [], "pads": [], "gifts": [], "pieces": []}
	ClawdsScript.attach(L, {})
	return ClawdsScript.create(L)


## _state() plus the clawd runtime the two clawd curses read (D-T4-7).
func _state_cl(rt: RefCounted, held: Dictionary, tick: int, cl) -> Dictionary:
	var st := _state(rt, held, tick)
	st["clawds"] = cl
	return st


func _norm(text: String) -> String:
	var merged := text.replace("#", " ").replace("\n", " ")
	while merged.contains("  "):
		merged = merged.replace("  ", " ")
	return merged.strip_edges()


# ---- one test per curse ----------------------------------------------------------

## "landing sends a second shockwave 0.5 s later, radius 9 u"
func _t_aftershock(f: Array[String]) -> void:
	_eqi(f, Aftershock.WAVE_DELAY_TICKS, 30, "aftershock: the delay is not 0.5 s (30 ticks)")
	_eqf(f, Aftershock.WAVE_RADIUS, 9.0, "aftershock: the wave radius is not 9 u")
	var rt := _rt()
	var coil := _row(rt, "coil", Vector3(5.0, 0.0, 5.0))
	var api := FakeApi.new()
	var st := _state(rt, _held("aftershock"), 100)
	# this tick's landing (D-T-031-11: the landing builds row["shock"], state recover)
	coil["shock"] = {"ticks": 30, "index": 0, "dir": 0}
	Aftershock.on_tick(st, api)
	var st_entries: Array = st["curse_st"].get(Aftershock.ST_KEY, [])
	_eqi(f, st_entries.size(), 1, "aftershock: the landing did not schedule one wave")
	if st_entries.size() == 1:
		_eqi(f, int(st_entries[0]["due"]), 130,
				"aftershock: the wave is not scheduled 0.5 s (30 ticks) after the landing")
		_eqf(f, float(st_entries[0]["x"]), 5.0, "aftershock: the wave point is not the landing point")
	# the same landing never schedules twice; an aged shock (ticks != 30) never schedules
	Aftershock.on_tick(st, api)
	_eqi(f, (st["curse_st"][Aftershock.ST_KEY] as Array).size(), 1,
			"aftershock: the same landing scheduled a second wave")
	coil["shock"] = {"ticks": 5, "index": 0, "dir": 0}
	Aftershock.on_tick(st, api)
	_eqi(f, (st["curse_st"][Aftershock.ST_KEY] as Array).size(), 1,
			"aftershock: an aged shock scheduled a wave")
	# before the due tick: silence. At the due tick: the 9 u wave pushes the player
	# 3 u in, outward along the wave->player line, at coil's own 8 u/s, and the wave
	# NEVER kills (section 12's push rule).
	rt.controllers[0].x = 8.0   # 3 u from the wave point (5, 0, 5)
	rt.controllers[0].z = 5.0
	rt.controllers[0].y = 0.0
	st["tick"] = 129
	api.pushes.clear()
	api.telegraphs.clear()
	Aftershock.on_tick(st, api)
	_eqi(f, api.pushes.size(), 0, "aftershock: the wave fired before the due tick")
	st["tick"] = 130
	Aftershock.on_tick(st, api)
	_eqi(f, api.pushes.size(), 1, "aftershock: the in player did not take the second wave")
	if api.pushes.size() == 1:
		_eqi(f, int(api.pushes[0]["i"]), 0, "aftershock: the push hit the wrong player")
		_eqf(f, float(api.pushes[0]["speed"]), 8.0, "aftershock: the push speed is not coil's 8 u/s")
		_eqf(f, float((api.pushes[0]["dir"] as Vector3).x), 1.0,
				"aftershock: the push is not outward along the wave->player line")
		_eqf(f, float((api.pushes[0]["dir"] as Vector3).y), 0.0,
				"aftershock: the push is not horizontal")
	_eqi(f, api.telegraphs.size(), 1, "aftershock: the wave was not announced")
	if api.telegraphs.size() == 1:
		_eqs(f, str(api.telegraphs[0]["kind"]), "aftershock_ring",
				"aftershock: the echo ring is not the aftershock_ring shape")
		_eqf(f, float(api.telegraphs[0]["shape"]["r"]), 9.0,
				"aftershock: the announced ring radius is not 9 u")
	# a fresh landing with the player 10 u OUT: the wave takes nobody, still no kill
	rt.controllers[0].x = 15.0   # 10 u from the same wave point
	var coil2 := _row(rt, "coil", Vector3(5.0, 0.0, 5.0))
	coil2["shock"] = {"ticks": 30, "index": 0, "dir": 0}
	st["tick"] = 200
	Aftershock.on_tick(st, api)
	api.pushes.clear()
	api.telegraphs.clear()
	st["tick"] = 230
	Aftershock.on_tick(st, api)
	_eqi(f, api.pushes.size(), 0, "aftershock: a player 10 u out took the wave")
	_eqi(f, api.kills.size(), 0, "aftershock: the wave killed (a push never kills)")
	# not held: no schedule at all
	var rt2 := _rt()
	var coil3 := _row(rt2, "coil", Vector3(5.0, 0.0, 5.0))
	coil3["shock"] = {"ticks": 30, "index": 0, "dir": 0}
	var st2 := _state(rt2, {}, 100)
	Aftershock.on_tick(st2, api)
	_check(f, not (st2["curse_st"].get(Aftershock.ST_KEY, []) as Array).size() > 0,
			"aftershock: a not-held run scheduled a wave")


## "explosions delete props within the blast for the rest of the level"
func _t_bunker_buster(f: Array[String]) -> void:
	var rt := _rt()
	var w: Dictionary = rt.world
	# prop columns (collision.gd make_world shape): entry y is in height units.
	w["prop_cols"] = {"5,5": [{"y": 0, "h": 1}], "5,10": [{"y": 0, "h": 1}],
			"6,6": [{"y": 2, "h": 1}]}
	var nuke := _row(rt, "nuke", Vector3(5.5, 0.0, 20.0), {"blast_radius": 4.0})
	nuke["explosion_left"] = 24   # the blast tick (attack_explosion draws over the first 24)
	nuke["det"] = {"x": 5.5, "y": 0.0, "z": 5.5}
	var api := FakeApi.new()
	var st := _state(rt, _held("bunker_buster"), 100)
	BunkerBuster.on_tick(st, api)
	_check(f, not w["prop_cols"].has("5,5"),
			"bunker_buster: a prop at the detonation point survived the blast")
	_check(f, w["prop_cols"].has("5,10"),
			"bunker_buster: a prop 5 u out (outside the 4 u blast) was deleted")
	# "6,6" is a HIGH prop: y 1.0 world u, 2.0 u above the detonation - still within 4 u
	# horizontally (d2 = 0.25 + 0.25 + 4.0 <= 16) -> deleted (the blast is a sphere)
	_check(f, not w["prop_cols"].has("6,6"),
			"bunker_buster: a raised prop inside the blast sphere survived")
	_eqi(f, int(st["curse_st"].get(BunkerBuster.ST_KEY, 0)), 1,
			"bunker_buster: the blast was not counted once")
	# a NON-blast tick is inert
	nuke["explosion_left"] = 23
	nuke["det"] = {"x": 5.5, "y": 0.0, "z": 10.5}
	BunkerBuster.on_tick(st, api)
	_eqi(f, int(st["curse_st"][BunkerBuster.ST_KEY]), 1,
			"bunker_buster: a non-blast tick fired")
	# a SECOND blast deletes more - the deletion is for the rest of the level, and
	# later explosions keep working
	var nuke2 := _row(rt, "nuke", Vector3(5.5, 0.0, 20.0), {"blast_radius": 4.0})
	nuke2["explosion_left"] = 24
	nuke2["det"] = {"x": 5.5, "y": 0.0, "z": 10.5}
	BunkerBuster.on_tick(st, api)
	_check(f, not w["prop_cols"].has("5,10"),
			"bunker_buster: the second blast did not delete its own sphere")
	_eqi(f, int(st["curse_st"][BunkerBuster.ST_KEY]), 2,
			"bunker_buster: the second blast was not counted")
	# the pure helper answers the sphere WITHOUT deleting
	var probe := {"9,9": [{"y": 0, "h": 1}], "0,3": [{"y": 0, "h": 1}]}
	var inside: Array = BunkerBuster.props_within(probe, Vector3(9.5, 0.0, 9.5), 4.0)
	_eqi(f, inside.size(), 1, "bunker_buster: the sphere helper returned the wrong count")
	if inside.size() == 1:
		_eqs(f, str(inside[0]), "9,9", "bunker_buster: the sphere helper picked the wrong key")
	_check(f, probe.has("9,9"), "bunker_buster: the pure helper deleted (it must only read)")
	# the fallback radius when the cfg carries none is the enemy.json 5.0 u
	_eqf(f, BunkerBuster.BLAST_RADIUS_FALLBACK, 5.0,
			"bunker_buster: the fallback blast radius moved")
	# not held: an explosion deletes nothing
	var rt2 := _rt()
	var w2: Dictionary = rt2.world
	w2["prop_cols"] = {"5,5": [{"y": 0, "h": 1}]}
	var st2 := _state(rt2, {}, 100)
	BunkerBuster.on_tick(st2, api)
	_check(f, w2["prop_cols"].has("5,5"), "bunker_buster: a not-held run deleted props")


## "the anger timer runs 1.5x faster"
func _t_crescendo(f: Array[String]) -> void:
	_eqf(f, Crescendo.ANGER_RATE_MUL, 1.5, "crescendo: the cursed rate is not 1.5x")
	_eqf(f, Crescendo.BASE_RATE_MUL, 1.0, "crescendo: the sim's own rate moved off 1.0")
	_eqf(f, Crescendo.anger_rate_mul({"curses_held": {}}), 1.0,
			"crescendo: a not-held run changed the rate")
	_eqf(f, Crescendo.anger_rate_mul(_held("crescendo")), 1.5,
			"crescendo: the held rate is not 1.5x")
	# the three thresholds land at 40 s / 80 s / 120 s instead of 60 / 120 / 180
	_eqi(f, Crescendo.ticks_at_rate(3600, 1.5), 2400, "crescendo: warning 1 is not at 40 s")
	_eqi(f, Crescendo.ticks_at_rate(7200, 1.5), 4800, "crescendo: warning 2 is not at 80 s")
	_eqi(f, Crescendo.ticks_at_rate(10800, 1.5), 7200, "crescendo: the kill is not at 120 s")
	_eqi(f, Crescendo.ticks_at_rate(3600, 1.0), 3600, "crescendo: the plain rate moved a threshold")
	# on_tick pushes the multiplier onto the clawd state
	var cl = _clawds()
	var st := _state_cl(_rt(), _held("crescendo"), 0, cl)
	Crescendo.on_tick(st, FakeApi.new())
	_eqf(f, float(cl.anger_rate_mul), 1.5, "crescendo: the clawd state did not take the 1.5x")
	# not held: the sim's own rate
	var cl2 = _clawds()
	var st2 := _state_cl(_rt(), {}, 0, cl2)
	Crescendo.on_tick(st2, FakeApi.new())
	_eqf(f, float(cl2.anger_rate_mul), 1.0, "crescendo: a not-held run still sped the timer up")
	# a level with no swarm: the hook is a no-op, not a crash
	var st3 := _state(_rt(), _held("crescendo"), 0)
	Crescendo.on_tick(st3, FakeApi.new())


## "balls ricochet once off tiles/props"
func _t_direct_shot(f: Array[String]) -> void:
	_eqi(f, DirectShot.BOUNCES, 1, "direct_shot: the ricochet count is not one")
	var rt := _rt()
	var ball := {"name": "isagi_shot", "x": 0.5, "y": 0.0, "z": 0.5,
			"vx": 60.0, "vz": 0.0, "bounces_left": 1}   # 1 u/s -> the next x step enters tile 1
	var api := FakeApi.new()
	var st := _state(rt, _held("direct_shot"), 0)
	_check(f, DirectShot.solid_next(rt.world, 1.5, 0.5),
			"direct_shot: tile 1 does not read as solid for the next step")
	_eqs(f, DirectShot.offending_axis(ball, st), "x",
			"direct_shot: the offending axis is not the one entering the tile")
	_check(f, DirectShot.try_bounce(ball, st, api),
			"direct_shot: the first wall hit did not ricochet")
	_eqf(f, float(ball["vx"]), -60.0, "direct_shot: the offending axis was not mirrored")
	_eqf(f, float(ball["vz"]), 0.0, "direct_shot: the OTHER axis moved on a ricochet")
	# "ricochet ONCE": the second hit dies the step (the flag stops every further call)
	_check(f, not DirectShot.try_bounce(ball, st, api),
			"direct_shot: the same ball ricocheted twice")
	_eqf(f, float(ball["vx"]), -60.0, "direct_shot: an exhausted ball still mirrored")
	_eqi(f, int(ball["bounces_left"]), 0, "direct_shot: the bounce counter went below zero")
	# a z-axis wall mirrors z, never x
	var ball2 := {"name": "isagi_volley", "x": 0.5, "y": 0.0, "z": 0.5,
			"vx": 0.0, "vz": 42.0, "bounces_left": 1}
	_eqs(f, DirectShot.offending_axis(ball2, st), "z",
			"direct_shot: the z entry was not the offending axis")
	_check(f, DirectShot.try_bounce(ball2, st, api), "direct_shot: the z ricochet failed")
	_eqf(f, float(ball2["vz"]), -42.0, "direct_shot: the z ricochet did not mirror z")
	_eqf(f, float(ball2["vx"]), 0.0, "direct_shot: the z ricochet touched x")
	# a clear path never bounces
	var ball3 := {"name": "isagi_shot", "x": 0.5, "y": 0.0, "z": 2.5,
			"vx": 30.0, "vz": 0.0, "bounces_left": 1}
	_check(f, not DirectShot.try_bounce(ball3, st, api),
			"direct_shot: a ball in the open ricocheted off air")
	_eqf(f, float(ball3["vx"]), 30.0, "direct_shot: a clear-path call moved the ball")
	# a non-Isagi ball is never touched (the curse reads the source's name); on_tick
	# over the real runtime's projectile list bounces each isagi ball once
	rt.projectiles.append({"name": "coil_shard", "x": 0.5, "y": 0.0, "z": 0.5,
			"vx": 60.0, "vz": 0.0, "bounces_left": 1})
	rt.projectiles.append({"name": "isagi_ball", "x": 0.5, "y": 0.0, "z": 0.5,
			"vx": 60.0, "vz": 0.0, "bounces_left": 1})
	DirectShot.on_tick(st, api)
	_eqf(f, float(rt.projectiles[0]["vx"]), 60.0,
			"direct_shot: a non-Isagi ball was mirrored")
	_eqf(f, float(rt.projectiles[1]["vx"]), -60.0,
			"direct_shot: the runtime's isagi ball did not ricochet")
	# not held: nothing bounces
	var rt2 := _rt()
	var st2 := _state(rt2, {}, 0)
	rt2.projectiles.append({"name": "isagi_ball", "x": 0.5, "y": 0.0, "z": 0.5,
			"vx": 60.0, "vz": 0.0, "bounces_left": 1})
	DirectShot.on_tick(st2, api)
	_eqf(f, float(rt2.projectiles[0]["vx"]), 60.0,
			"direct_shot: a not-held run still ricocheted")


## "every shockwave is followed by a second ring 0.6 s later"
func _t_double_ring(f: Array[String]) -> void:
	_eqi(f, DoubleRing.SECOND_DELAY_TICKS, 36, "double_ring: the echo is not 0.6 s (36 ticks) later")
	_eqf(f, DoubleRing.RING_SPEED, 9.0, "double_ring: the echo is not YOU's own 9 u/s ring")
	_eqf(f, DoubleRing.RING_MAX, 14.0, "double_ring: the 14 u cap moved")
	_eqf(f, DoubleRing.radius_at(36), 5.4, "double_ring: a ring 36 ticks after ITS release is not 5.4 u")
	_eqf(f, DoubleRing.radius_at(0), 0.0, "double_ring: the echo expanded before it flew")
	_eqf(f, DoubleRing.radius_at(60), 9.0, "double_ring: the echo is not YOU's own 9 u/s ring")
	_eqf(f, DoubleRing.radius_at(200), 14.0, "double_ring: the echo ignored the 14 u cap")
	var rt := _rt()
	var you := _row(rt, "you", Vector3(0.0, 0.0, 0.0))
	you["ring_seq"] = 1
	var api := FakeApi.new()
	var st := _state(rt, _held("double_ring"), 0)
	# player 0 (the runtime's real controller row) stands 5.4 u out on the ring plane:
	# inside the radial window (|5.4 - 5.4| = 0) and inside the feet window at 0
	var ctl = rt.controllers[0]
	ctl.x = 5.4
	ctl.y = 0.0
	ctl.z = 0.0
	# the curse watches for seq GROWTH: the first sight establishes the row's
	# baseline (a ring released before the curse watched is not echoed)
	DoubleRing.on_tick(st, api)
	_eqi(f, (st["curse_st"].get(DoubleRing.ST_KEY, []) as Array).size(), 0,
			"double_ring: the baseline sight scheduled an echo")
	you["ring_seq"] = 2   # a live shockwave release at tick 0
	DoubleRing.on_tick(st, api)
	var entries: Array = st["curse_st"].get(DoubleRing.ST_KEY, [])
	_eqi(f, entries.size(), 1, "double_ring: the release did not schedule one echo")
	if entries.size() == 1:
		_eqi(f, int(entries[0]["due"]), 36,
				"double_ring: the echo is not scheduled from the SAME origin 36 ticks later")
		_eqf(f, float(entries[0]["x"]), 0.0, "double_ring: the echo left the ring's origin")
	# the radial window |d - r| <= 0.7 with the feet window (feet - 1.5, feet + 1.0),
	# exactly like the first ring kills: A at 5.4 u on the plane dies; 7.0 u is
	# outside the window; 3 u above and 1.6 u below the plane survive even at radius
	var st_w := _state(rt, _held("double_ring"), 0)
	st_w["players"] = [
		{"x": 5.4, "y": 0.0, "z": 0.0},
		{"x": 7.0, "y": 0.0, "z": 0.0},
		{"x": 5.4, "y": 3.0, "z": 0.0},
		{"x": 5.4, "y": -1.6, "z": 0.0},
	]
	var hits: Array = DoubleRing.ring_hits(
			{"x": 0.0, "y": 0.0, "z": 0.0}, 5.4, st_w["players"])
	_eqi(f, hits.size(), 1, "double_ring: the echo window hit %d players, want 1 (A only)"
			% hits.size())
	# silence while the echo is on its way: the ring's own radius starts at 0 on its
	# due tick and expands at YOU's own 9 u/s - so the due tick itself kills nobody
	# (r = 0), and the player at 5.4 u dies when |5.4 - r| <= 0.7 first holds
	# (r = 4.8 at 32 ticks after the due tick)
	st["tick"] = 35
	DoubleRing.on_tick(st, api)
	_eqi(f, api.kills.size(), 0, "double_ring: the echo fired before 0.6 s")
	st["tick"] = 36
	DoubleRing.on_tick(st, api)
	_eqi(f, api.kills.size(), 0, "double_ring: the echo killed at r = 0 (wrong expansion)")
	st["tick"] = 68
	DoubleRing.on_tick(st, api)
	_eqi(f, api.kills.size(), 1, "double_ring: the echo did not kill the player in its window")
	if api.kills.size() == 1:
		_eqi(f, int(api.kills[0]["i"]), 0, "double_ring: the echo killed the wrong player")
		_eqs(f, str(api.kills[0]["killer"]), "YOU",
				"double_ring: the echo's killer id left D-YOU's closed YOU")
		_eqs(f, str(api.kills[0]["code"]), "D-YOU", "double_ring: the death code moved")
	# a SECOND shockwave (seq grows again) schedules its own echo - "every shockwave"
	you["ring_seq"] = 3
	st["tick"] = 40
	DoubleRing.on_tick(st, api)
	entries = st["curse_st"][DoubleRing.ST_KEY]
	_eqi(f, entries.size(), 2, "double_ring: a second shockwave did not get its own echo")
	_eqi(f, int(entries[1]["due"]), 76, "double_ring: the second echo is not +36 ticks")
	# not held: nothing is scheduled and nothing kills
	var rt2 := _rt()
	var you2 := _row(rt2, "you", Vector3(0.0, 0.0, 0.0))
	you2["ring_seq"] = 5
	var st2 := _state(rt2, {}, 0)
	DoubleRing.on_tick(st2, api)
	_check(f, not (st2["curse_st"].get(DoubleRing.ST_KEY, []) as Array).size() > 0,
			"double_ring: a not-held run scheduled an echo")


## "+1 ball per burst per stack"
func _t_egoist(f: Array[String]) -> void:
	_eqi(f, Egoist.BALLS_PER_STACK, 1, "egoist: the per-stack ball count is not +1")
	var stats := {"volley_balls": 3, "balls_per_stack": 1}
	_eqi(f, Egoist.burst_balls(stats, 0), 3, "egoist: the base burst moved (3, D-064)")
	_eqi(f, Egoist.burst_balls(stats, 1), 4, "egoist: 1 stack is not +1 ball")
	_eqi(f, Egoist.burst_balls(stats, 2), 5, "egoist: 2 stacks (the max) is not +2 balls")
	_eqi(f, Egoist.burst_balls({}, 0), 3,
			"egoist: the stats fallback burst moved (volley_balls 3)")
	# and the bigger burst still splits through the SAME D-064 volley discipline
	# (at most 3 balls per volley, 45 ticks apart) - no behavior edit. volley_plan
	# answers the volley SIZES, e.g. 7 -> [3, 3, 1].
	for n in range(3, 8):
		var plan: Array = EnemyRuntimeScript.volley_plan(n)
		for size in plan:
			_check(f, int(size) <= EnemyRuntimeScript.VOLLEY_MAX,
					"egoist: a %d-ball burst produced a %d-ball volley (D-064 broken)"
							% [n, int(size)])
	# on_tick stamps the held stacks onto every isagi row's stats block, so the
	# behavior's own assembly reads volley_balls + balls_per_stack * stacks
	var rt := _rt()
	var isagi := _row(rt, "isagi", Vector3(1.0, 0.0, 1.0), {"volley_balls": 3, "balls_per_stack": 1})
	var other := _row(rt, "coil", Vector3(2.0, 0.0, 1.0), {})
	var st := _state(rt, _held("egoist", 2), 0)
	Egoist.on_tick(st, FakeApi.new())
	_eqi(f, int(isagi["cfg"]["egoist_stacks"]), 2, "egoist: the row did not carry 2 stacks")
	_check(f, not other["cfg"].has("egoist_stacks"),
			"egoist: a non-Isagi row was stamped")
	# idempotent: a second tick changes nothing (the state hash stays stable)
	Egoist.on_tick(st, FakeApi.new())
	_eqi(f, int(isagi["cfg"]["egoist_stacks"]), 2, "egoist: the stamp was not idempotent")
	# not held: the guard is total - a fresh row is never stamped (not even with 0)
	var rt2 := _rt()
	var isagi2 := _row(rt2, "isagi", Vector3(1.0, 0.0, 1.0), {})
	Egoist.on_tick(_state(rt2, {}, 0), FakeApi.new())
	_check(f, not isagi2["cfg"].has("egoist_stacks"),
			"egoist: a not-held run stamped the row")


## "each cat is followed by a kitten (60% size, 1.2 u/s, kills on contact) 6 u behind"
func _t_litter(f: Array[String]) -> void:
	_eqf(f, Litter.KITTEN_SIZE, 0.6, "litter: the kitten is not 60% of the cat")
	_eqf(f, Litter.KITTEN_SPEED, 1.2, "litter: the kitten speed is not 1.2 u/s")
	_eqf(f, Litter.KITTEN_CEILING, 0.15, "litter: the kitten's SR-5 ceiling is not 0.15")
	# D-KIWI-SLOW-1: a kitten may NEVER be faster than its cat - base, absolute cap, or burst
	# (J6: kittens ARE kiwi cats, so the halved cat numbers carry the 0.8 ratio)
	_check(f, Litter.KITTEN_SPEED < KiwiScript.BASE_SPEED,
			"litter: the kitten's base is not below its cat's (1.2 < 1.5)")
	_check(f, Litter.KITTEN_CEILING * 9.0 < KiwiScript.PURSUIT_CEILING * 9.0,
			"litter: the kitten's absolute cap is not below its cat's (1.35 < 1.8)")
	_check(f, KiwiScript.BURST_CEILING * 0.6 * 9.0 < KiwiScript.BURST_CEILING * 9.0,
			"litter: the kitten's scaled burst is not below its cat's (1.08 < 1.8)")
	_eqf(f, KiwiScript.BASE_SPEED, 1.5, "litter-harness: the cat's base moved off 1.5 u/s")
	_eqf(f, KiwiScript.PURSUIT_CEILING * 9.0, 1.8, "litter-harness: the cat's cap moved off 1.8 u/s")
	_eqf(f, KiwiScript.BURST_CEILING * 9.0, 1.8, "litter-harness: the cat's burst ceiling moved off 1.8 u/s")
	_eqf(f, Litter.TRAIL_U, 6.0, "litter: the kitten does not trail 6 u behind")
	_eqs(f, str(Litter.DEATH_CODE), "D-KIWI", "litter: the kitten is not still a kiwi cat")
	# the kitten's cfg: scaled body, own speed, SR-5 ceiling, contact kill ON, no meow
	# (synthetic cat cfg passes burst_ceiling 0.55 - a pure helper check of the 0.6 scaling,
	# independent of the cat's shipped value)
	var kc: Dictionary = Litter.kitten_cfg({"burst_ceiling": 0.55, "climb_u_per_s": 2.0,
			"world_height": 1.0, "body_height": 1.0, "hit_diameter": 0.9,
			"preferred_kind": "nook", "meow_period_ticks": 300, "meow_range_u": 25.0,
			"frame_w": 256, "frame_h": 256})
	_eqf(f, float(kc["base_speed"]), 1.2, "litter: the kitten cfg speed is not 1.2 u/s")
	_eqf(f, float(kc["pursuit_ceiling"]), 0.15, "litter: the kitten cfg ceiling is not 0.15")
	_eqf(f, float(kc["burst_ceiling"]), 0.33, "litter: the kitten burst ceiling did not scale to 60% of 0.55")
	_eqf(f, float(kc["burst_ceiling"]) * 9.0, 2.97, "litter: the kitten burst in u/s is not 2.97")
	_eqf(f, float(kc["world_height"]), 0.6, "litter: the kitten world_height did not scale")
	_eqf(f, float(kc["body_height"]), 0.6, "litter: the kitten body_height did not scale")
	_eqf(f, float(kc["hit_diameter"]), 0.54, "litter: the kitten hit diameter did not scale")
	_check(f, bool(kc["contact_kill"]), "litter: the kitten cfg does not kill on contact")
	_eqi(f, int(kc["meow_period_ticks"]), 0, "litter: kittens meow (only the CAT meows)")
	_eqf(f, float(kc["meow_range_u"]), 0.0, "litter: kittens kept a meow range")
	_eqi(f, int(kc["meow_ticks"]), 0, "litter: kittens kept meow ticks")
	_eqs(f, str(kc["death_code"]), "D-KIWI", "litter: the kitten cfg death code moved")
	# the trailing point: 6 u BEHIND the cat on the cat->player line (farther from
	# the player than the cat is, so it always trails)
	var cat := {"x": 10.0, "y": 0.5, "z": 0.0}
	var player := {"x": 4.0, "y": 0.5, "z": 0.0}
	var tp: Vector3 = Litter.trail_point(cat, player)
	_eqf(f, tp.x, 16.0, "litter: the trail point is not 6 u behind the cat")
	_eqf(f, tp.z, 0.0, "litter: the trail point left the cat->player line")
	_eqf(f, tp.y, 0.5, "litter: the trail point left the cat's plane")
	# driving a cat row spawns exactly ONE kitten per cat through api.spawn_enemy
	var rt := _rt()
	var cat_row := _row(rt, "kiwi_cat", Vector3(10.0, 0.5, 0.0), {})
	cat_row["cfg"] = {"world_height": 1.0, "hit_diameter": 0.9}
	var api := FakeApi.new()
	api.near = {"index": 0, "x": 4.0, "y": 0.5, "z": 0.0, "vx": 0.0, "vy": 0.0, "vz": 0.0}
	var st := _state(rt, _held("litter"), 0)
	Litter.on_tick(st, api)
	_eqi(f, api.spawns.size(), 1, "litter: the cat was not followed by exactly one kitten")
	if api.spawns.size() == 1:
		var def: Dictionary = api.spawns[0]
		_eqs(f, str(def["id"]), "kiwi_cat", "litter: the kitten is not a real kiwi_cat row id")
		_eqs(f, str(def["name"]), "kitten", "litter: the kitten row is not named kitten")
		_eqf(f, float(def["x"]), 16.0, "litter: the kitten did not spawn 6 u behind")
		_eqf(f, float(def["cfg"]["base_speed"]), 1.2, "litter: the spawned kitten cfg speed moved")
		_eqi(f, int(def["cfg"]["contact_kill"]) if def["cfg"].has("contact_kill") else 1,
				1, "litter: the spawned kitten cfg does not kill on contact")
	# a second tick spawns nothing more (one kitten per cat, the marker lives in curse_st)
	Litter.on_tick(st, api)
	_eqi(f, api.spawns.size(), 1, "litter: a second kitten spawned for the same cat")
	# a second cat gets its own kitten
	var cat2 := _row(rt, "kiwi_cat", Vector3(10.0, 0.5, 10.0), {})
	cat2["cfg"] = {}
	st["tick"] = 1
	Litter.on_tick(st, api)
	_eqi(f, api.spawns.size(), 2, "litter: a second cat did not get its own kitten")
	# not held: no kitten
	var rt2 := _rt()
	_row(rt2, "kiwi_cat", Vector3(10.0, 0.5, 0.0), {})
	var st2 := _state(rt2, {}, 0)
	Litter.on_tick(st2, api)
	_eqi(f, api.spawns.size(), 2, "litter: a not-held run spawned a kitten")


## "every ben teleport tolls twice: a second ben arrives at the same locked point
## 1.5 s after the first" - the done-when's sentence, proven END-TO-END: the REAL
## thicc_ben behavior runs inside a REAL sim/enemy_runtime.gd and the curse joins
## the tick loop exactly where a dispatcher would put it.
func _t_long_toll(f: Array[String]) -> void:
	_eqi(f, LongToll.TOLL_INTERVAL_TICKS, 90, "long_toll: the toll interval is not 1.5 s (90 ticks)")
	_eqi(f, BenScript.TELEPORT_TICKS, 801, "long_toll: ben's own cycle moved (T-032)")
	_eqi(f, BenScript.TELEGRAPH_TICKS, 75, "long_toll: ben's own smoke moved (T-032)")
	var held: Dictionary = _long_toll_run(f, true)
	var arr: Array = held["arrivals"]
	if (arr as Array).size() < 2:
		return
	var first: Dictionary = arr[0]
	var second: Dictionary = arr[1]
	# the second arrival: EXACTLY +90 ticks (1.5 s at the 60 Hz sim rate), the same
	# locked point never re-locked (the player MOVED between the arrivals - a fresh
	# lock would land on the moved position), and it never kills
	_eqi(f, int(second["tick"]) - int(first["tick"]), 90,
			"long_toll: the second ben arrival is not 1.5 s after the first")
	_eqf(f, float(second["x"]), float(first["x"]),
			"long_toll: the second arrival left the first arrival's locked x")
	_eqf(f, float(second["y"]), float(first["y"]),
			"long_toll: the second arrival left the first arrival's locked y")
	_eqf(f, float(second["z"]), float(first["z"]),
			"long_toll: the second arrival left the first arrival's locked z")
	_eqf(f, float(first["y"]), 0.5,
			"long_toll: the lock is not the player's position at smoke start")
	_check(f, not bool(held["dead"]), "long_toll: an arrival killed the player")
	# the counterfactual: without the curse, the next arrival is ben's own 801-tick
	# cycle away and lands on the FRESH lock (the moved player) - so the 90-tick
	# same-point second arrival is the curse's doing, not the driver's
	var free: Dictionary = _long_toll_run(f, false)
	var arr2: Array = free["arrivals"]
	if (arr2 as Array).size() < 2:
		return
	_eqi(f, int(arr2[1]["tick"]) - int(arr2[0]["tick"]), 801,
			"long_toll: an unheld run's second arrival is not ben's own 801-tick cycle")
	_eqf(f, float(arr2[1]["x"]), 50.5,
			"long_toll: an unheld run did not land on the fresh (moved) lock")
	_check(f, not bool(free["dead"]), "long_toll: an unheld run killed the player")


## The shared driver for the long_toll done-when: a REAL sim/enemy_runtime.gd runs the
## REAL thicc_ben behavior (T-032's 801-tick cycle, 75-tick smoke, lock at smoke start,
## arrive at the locked point) and the curse joins the tick loop where a dispatcher
## would call it - once per tick, right after the runtime's step. The player stands at
## (0.5, 0.5, 0.5); after the FIRST arrival the test moves them to x = 50.5 (so a fresh
## lock would differ) and back onto the locked point at T1 + 45 (inside the 90-tick
## toll's second smoke), so the second arrival's touch eject actually plays. Returns
## a Dictionary with the observed arrivals and the "never kills" evidence:
##   {"arrivals": [{"tick", "x", "y", "z"}, ...], "dead": bool,
##    "ejected_at": [tick, ...]} - empty NEVER; on a dead drive the failures are
## appended and the caller sees a one-arrival result.
func _long_toll_run(f: Array[String], held: bool) -> Dictionary:
	var rt := _rt()
	var ctl = rt.controllers[0]
	ctl.x = 0.5
	ctl.y = 0.5
	ctl.z = 0.5
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0
	var ben: Dictionary = rt.spawn_at("thicc_ben", "Thicc Ben", BenScript.new_behavior(),
			{"contact_kill": false, "world_height": 4.0, "hit_diameter": 1.2},
			Vector3(10.5, 0.5, 10.5))
	var st := _state(rt, _held("long_toll") if held else {}, 0)
	var arrivals: Array = []
	var ejected_at: Array = []
	var prev_phase := "idle"
	var dead := false
	for t in 1800:
		var ev: Array = rt.step(TestUtil.DT)
		st["tick"] = rt.tick
		for e in ev:
			if str(e.get("e", "")) == "chain_reset" and str(e.get("why", "")) == "thicc_ben_eject":
				ejected_at.append(t)
		LongToll.on_tick(st, FakeApi.new())
		var phase := str(ben.get("phase", "idle"))
		if prev_phase == "telegraph" and phase == "idle":
			arrivals.append({"tick": t, "x": float(ben["x"]), "y": float(ben["y"]),
					"z": float(ben["z"])})
			if arrivals.size() == 1:
				ctl.x = 50.5          # a fresh lock would now aim at the moved player
		if prev_phase == "idle" and phase == "telegraph" and arrivals.size() == 1:
			ctl.x = 0.5               # back on the locked point: the touch must eject
		prev_phase = phase
		if bool(ctl.dead):
			dead = true
			break
		if arrivals.size() >= 2 and t > int(arrivals[1]["tick"]) + 95:
			break
	# no third arrival within 95 ticks of the second: a toll arrival that scheduled
	# its own +90 toll (chaining) would show up here
	if held:
		var chained := false
		if arrivals.size() >= 2:
			for a in range(2, arrivals.size()):
				if int(arrivals[a]["tick"]) <= int(arrivals[1]["tick"]) + 95:
					chained = true
		_check(f, not chained, "long_toll: a toll chained into another toll")
	_eqi(f, arrivals.size(), 2,
			"long_toll: the drive recorded the wrong arrival count (held=%s)" % str(held))
	var out := {"arrivals": arrivals, "dead": dead, "ejected_at": ejected_at}
	if held and arrivals.size() >= 2 and not dead:
		var ejected2 := false
		for et in ejected_at:
			if int(et) >= int(arrivals[1]["tick"]) - 1 and int(et) <= int(arrivals[1]["tick"]) + 30:
				ejected2 = true
		_check(f, ejected2,
				"long_toll: the second arrival's touch did not eject (the never-kills path unproven)")
	return out


## "you must hold still 2.5 s instead of 1.5 s"
func _t_longer_speech(f: Array[String]) -> void:
	_eqi(f, LongerSpeech.BASE_STILL_TICKS, 90, "longer_speech: the base gate is not 1.5 s (90)")
	_eqi(f, LongerSpeech.REQUIRED_STILL_TICKS, 150,
			"longer_speech: the cursed requirement is not 2.5 s (150)")
	_eqi(f, LongerSpeech.visible_for(150), 90,
			"longer_speech: true stillness 150 does not read as the 90-tick gate")
	_eqi(f, LongerSpeech.visible_for(90), 30,
			"longer_speech: the debit is not a flat 60-tick lag")
	_eqi(f, LongerSpeech.visible_for(10), 0, "longer_speech: the debit went negative")
	# end to end: the behavior's own counter climbs 1 per true still tick; the gate
	# (the behavior's still_t >= 90) fires when TRUE stillness has run 150 (2.5 s)
	# because the curse absorbs 60 of the climb
	var rt := _rt()
	var row := _row(rt, "address_me", Vector3(1.0, 0.0, 1.0), {})
	row["still_t"] = 0   # the behavior's on_spawn zeroes it
	var st := _state(rt, _held("longer_speech"), 0)
	var released_at := -1
	for t in range(1, 301):
		row["still_t"] = int(row["still_t"]) + 1   # the behavior's own +1 climb (still)
		st["tick"] = t
		LongerSpeech.on_tick(st, FakeApi.new())
		if released_at < 0 and int(row["still_t"]) >= 90:
			released_at = t
	_eqi(f, released_at, 150, "longer_speech: the gate did not release at exactly 2.5 s")
	# ... and the debt re-books per still run: break the run (the behavior's own reset
	# zeroes the counter), then the NEXT run again releases only at its own 150
	row["still_t"] = 0
	st["tick"] = 300
	LongerSpeech.on_tick(st, FakeApi.new())
	var released2 := -1
	for t2 in range(1, 301):
		row["still_t"] = int(row["still_t"]) + 1
		LongerSpeech.on_tick(st, FakeApi.new())
		if released2 < 0 and int(row["still_t"]) >= 90:
			released2 = t2
	_eqi(f, released2, 150, "longer_speech: the second run did not get its own 2.5 s")
	# not held: the visible counter IS the true counter - the 1.5 s gate at 90 stands
	var rt2 := _rt()
	var row2 := _row(rt2, "address_me", Vector3(1.0, 0.0, 1.0), {})
	row2["still_t"] = 90
	LongerSpeech.on_tick(_state(rt2, {}, 0), FakeApi.new())
	_eqi(f, int(row2["still_t"]), 90, "longer_speech: a not-held run debited the counter")


## "mine tells are visible only within 6 u (was 12 u)"
func _t_method_acting(f: Array[String]) -> void:
	var held := _held("method_acting")
	_eqf(f, MethodActing.tell_visible_u(held), 6.0,
			"method_acting: the sim-side tell cutoff is not 6 u while held")
	_eqf(f, MethodActing.tell_visible_u({"curses_held": {}}), 12.0,
			"method_acting: the base tell cutoff is not 12 u")
	_eqf(f, MethodActing.tell_radius_u(held), 5.0,
			"method_acting: the view ramp's held tell radius is not 5 u")
	_eqf(f, MethodActing.tell_radius_u({"curses_held": {}}), 10.0,
			"method_acting: the view ramp's base tell radius is not 10 u")
	# on_level_start stamps the held value once into curse_st (the replay-safe read)
	var st := {"curse_st": {}, "curses_held": {"method_acting": 1}}
	MethodActing.on_level_start(st, null)
	_eqf(f, float(st["curse_st"].get(MethodActing.ST_KEY, 0.0)), 5.0,
			"method_acting: on_level_start did not stamp the held tell radius")
	st["curse_st"][MethodActing.ST_KEY] = 99.0
	MethodActing.on_level_start(st, null)
	_eqf(f, float(st["curse_st"][MethodActing.ST_KEY]), 99.0,
			"method_acting: on_level_start stamped twice")


## "YOU?! uses your class kit: dashes 6 u every 5 s / ignores height (glides) /
##  moves +15%"
func _t_mirror_match(f: Array[String]) -> void:
	_eqf(f, MirrorMatch.DASH_U, 6.0, "mirror_match: the dash is not 6 u")
	_eqi(f, MirrorMatch.DASH_EVERY_TICKS, 300, "mirror_match: the dash cadence is not 5 s")
	_eqf(f, MirrorMatch.MIRROR_SPEED_MUL, 1.15, "mirror_match: the move mul is not +15%")
	_eqs(f, MirrorMatch.mirror_mode_for("dasher"), "dash",
			"mirror_match: the dasher kit does not map to the dash clause")
	_eqs(f, MirrorMatch.mirror_mode_for("glider"), "glide",
			"mirror_match: the glider kit does not map to the glide clause")
	_eqs(f, MirrorMatch.mirror_mode_for("athletic"), "speed",
			"mirror_match: the athletic kit does not map to the +15% clause")
	# the dash endpoint: 6 u toward the target, stopped 0.6 u short (it positions, it
	# never body-kills)
	var endp: Vector3 = MirrorMatch.dash_point({"x": 0.0, "y": 0.5, "z": 0.0},
			{"x": 10.0, "z": 0.0})
	_eqf(f, endp.x, 6.0, "mirror_match: the dash endpoint is not 6 u toward the target")
	_eqf(f, endp.z, 0.0, "mirror_match: the dash endpoint left the line")
	var short: Vector3 = MirrorMatch.dash_point({"x": 0.0, "y": 0.5, "z": 0.0},
			{"x": 1.0, "z": 0.0})
	_eqf(f, short.x, 0.4, "mirror_match: the dash did not stop 0.6 u short")
	var hold: Vector3 = MirrorMatch.dash_point({"x": 3.0, "y": 0.5, "z": 0.0},
			{"x": 3.2, "z": 0.0})
	_eqf(f, hold.x, 3.0, "mirror_match: a dash at the shell still moved")
	# the kit stamp from the NEAREST player's kit, applied once (idempotent); the
	# players are REAL T-012 controllers (the contract's shape - the kit rides the
	# controller's own "kit" property)
	var ctl_ath := _mk_ctl("athletic")
	var ctl_gli := _mk_ctl("glider")
	var ctl_dsh := _mk_ctl("dasher")
	ctl_dsh.x = 20.0
	ctl_dsh.y = 0.5
	ctl_dsh.z = 0.0
	var rt := _rt()
	rt.controllers = [ctl_ath, ctl_gli, ctl_dsh]
	var st := _state(rt, _held("mirror_match"), 0)
	var api := FakeApi.new()
	api.near = {"index": 0}   # the nearest player is 0 (athletic)
	var you := _row(rt, "you", Vector3(0.0, 0.5, 0.0), {"base_speed": 9.0})
	MirrorMatch.on_tick(st, api)
	_eqs(f, str(you["mirror_mode"]), "speed",
			"mirror_match: the athletic kit did not map to the +15% clause")
	_eqf(f, float(you["cfg"]["base_speed"]), 9.0 * 1.15,
			"mirror_match: the +15% move did not land on the row's cfg")
	MirrorMatch.on_tick(st, api)
	_eqf(f, float(you["cfg"]["base_speed"]), 9.0 * 1.15,
			"mirror_match: the +15% applied twice (not idempotent)")
	# the dasher clause: one 6 u dash on the 300-tick cadence, along the current line
	# to the NEAREST player (now the dasher controller, 20 u out)
	ctl_ath.kit = "dasher"
	api.near = {"index": 2}
	MirrorMatch.on_tick(st, api)
	_eqs(f, str(you["mirror_mode"]), "dash", "mirror_match: the dash clause did not stamp")
	you["x"] = 0.0
	you["z"] = 0.0
	st["curse_st"]["mm_dash_0"] = 5    # next dash at tick 5
	st["tick"] = 4
	MirrorMatch.on_tick(st, api)
	_eqf(f, float(you["x"]), 0.0, "mirror_match: the dash fired before its 300th tick")
	st["tick"] = 5
	MirrorMatch.on_tick(st, api)
	_eqf(f, float(you["x"]), 6.0, "mirror_match: the 5 s dash did not cross its 6 u")
	_eqf(f, float(you["z"]), 0.0, "mirror_match: the dash left the line to target")
	_eqi(f, int(st["curse_st"]["mm_dash_0"]), 305,
			"mirror_match: the next dash is not one full 5 s cadence later")
	st["tick"] = 6
	MirrorMatch.on_tick(st, api)
	_eqf(f, float(you["x"]), 6.0, "mirror_match: the dash moved on a non-cadence tick")
	# the glide clause stamps the feet-window flag (the ring's kill window reads it)
	ctl_ath.kit = "glider"
	api.near = {"index": 0}
	MirrorMatch.on_tick(st, api)
	_eqs(f, str(you["mirror_mode"]), "glide", "mirror_match: the glide clause did not stamp")
	_check(f, bool(you["mirror_glide"]), "mirror_match: the glide flag did not land")
	# not held: no stamp at all
	var rt2 := _rt()
	var you2 := _row(rt2, "you", Vector3(0.0, 0.5, 0.0), {"base_speed": 9.0})
	var st2 := _state(rt2, {}, 0)
	MirrorMatch.on_tick(st2, api)
	_check(f, not you2.has("mirror_mode"), "mirror_match: a not-held run stamped a kit")


## "coil idle time 3.0 -> 2.0 s (then 1.5 s)"
func _t_overwound(f: Array[String]) -> void:
	_eqf(f, Overwound.idle_s_for(0), 3.0, "overwound: the base idle moved (coil's own 3.0 s)")
	_eqf(f, Overwound.idle_s_for(1), 2.0, "overwound: stack 1 idle is not 2.0 s")
	_eqf(f, Overwound.idle_s_for(2), 1.5, "overwound: stack 2 idle is not the parenthetical 1.5 s")
	# on_tick keeps every coil row's cfg idle_s at the stacks' length - the same DATA
	# key the behavior reads (content/enemies/coil/enemy.gd: cfg idle_s, fallback 3.0)
	var rt := _rt()
	var coil := _row(rt, "coil", Vector3(1.0, 0.0, 1.0), {})
	var other := _row(rt, "kiwi_cat", Vector3(2.0, 0.0, 1.0), {})
	Overwound.on_tick(_state(rt, _held("overwound", 1), 0), FakeApi.new())
	_eqf(f, float(coil["cfg"].get("idle_s", 3.0)), 2.0,
			"overwound: stack 1 did not hold the coil cfg at 2.0 s")
	_check(f, not other["cfg"].has("idle_s"), "overwound: a non-coil row was shortened")
	Overwound.on_tick(_state(rt, _held("overwound", 2), 0), FakeApi.new())
	_eqf(f, float(coil["cfg"].get("idle_s", 3.0)), 1.5,
			"overwound: stack 2 did not hold the coil cfg at 1.5 s")
	Overwound.on_tick(_state(rt, _held("overwound", 2), 0), FakeApi.new())
	_eqf(f, float(coil["cfg"].get("idle_s", 3.0)), 1.5, "overwound: the write was not idempotent")
	# not held: coil's cfg keeps its fallback reading (the curse never writes)
	var rt2 := _rt()
	var coil2 := _row(rt2, "coil", Vector3(1.0, 0.0, 1.0), {})
	Overwound.on_tick(_state(rt2, {}, 0), FakeApi.new())
	_check(f, not coil2["cfg"].has("idle_s"), "overwound: a not-held run shortened the idle")


## "ben's teleport interval 13.35 → 9 s" - proven END-TO-END: the REAL thicc_ben
## behavior runs inside a REAL sim/enemy_runtime.gd and the curse joins the tick loop
## where a dispatcher would call it (once per tick, right after the runtime's step).
func _t_quarter_chimes(f: Array[String]) -> void:
	_eqi(f, QuarterChimes.INTERVAL_TICKS, 540,
			"quarter_chimes: the interval is not 9 s (540 ticks)")
	_eqi(f, QuarterChimes.TELEPORT_TICKS, BenScript.TELEPORT_TICKS,
			"quarter_chimes: the curse's ben cycle moved off the behavior's 801")
	_eqi(f, QuarterChimes.TELEGRAPH_TICKS, BenScript.TELEGRAPH_TICKS,
			"quarter_chimes: the curse's smoke moved off the behavior's 75")
	_eqi(f, QuarterChimes.IDLE_LIMIT_TICKS, 465,
			"quarter_chimes: the smoke does not start 465 ticks into the idle")
	_eqf(f, QuarterChimes.LOCK_LEAD_S, BenScript.LOCK_LEAD_S,
			"quarter_chimes: the destination lead moved off ben's 0.5 s")
	_eqf(f, QuarterChimes.TELEGRAPH_R, BenScript.TELEGRAPH_R,
			"quarter_chimes: the smoke column moved off ben's 1.2 u")
	_eqs(f, QuarterChimes.KIND, BenScript.KIND, "quarter_chimes: the telegraph kind moved")
	var held := _quarter_chimes_run(f, true)
	var free := _quarter_chimes_run(f, false)
	if held.size() < 2 or free.size() < 2:
		return
	_eqi(f, int(held[1]) - int(held[0]), 540,
			"quarter_chimes: the arrival-to-arrival interval is not 9 s")
	_eqi(f, int(free[1]) - int(free[0]), 801,
			"quarter_chimes: an unheld run's interval is not ben's own 801")


## The shared driver for quarter_chimes: a REAL sim/enemy_runtime.gd runs the REAL
## thicc_ben behavior and the curse joins the tick loop once per tick, right after the
## runtime's step. Returns the arrival ticks (the telegraph -> idle transitions).
func _quarter_chimes_run(f: Array[String], held: bool) -> Array:
	var rt := _rt()
	var ctl = rt.controllers[0]
	ctl.x = 0.5
	ctl.y = 0.5
	ctl.z = 0.5
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0
	var ben: Dictionary = rt.spawn_at("thicc_ben", "Thicc Ben", BenScript.new_behavior(),
			{"contact_kill": false, "world_height": 4.0, "hit_diameter": 1.2},
			Vector3(10.5, 0.5, 10.5))
	var st := _state(rt, _held("quarter_chimes") if held else {}, 0)
	var api := FakeApi.new()
	var arrivals: Array = []
	var prev := "idle"
	for t in 1800:
		rt.step(TestUtil.DT)
		st["tick"] = rt.tick
		api.near = {"index": 0, "x": float(ctl.x), "y": float(ctl.y), "z": float(ctl.z),
				"vx": 0.0, "vy": 0.0, "vz": 0.0}
		QuarterChimes.on_tick(st, api)
		var phase := str(ben.get("phase", "idle"))
		if prev == "telegraph" and phase == "idle":
			arrivals.append(t)
		prev = phase
		if arrivals.size() >= 2:
			break
	_check(f, not bool(ctl.dead), "quarter_chimes: ben's arrival killed the player")
	return arrivals


## "a second missile lands 1.0 s after the first on your new position"
func _t_second_strike(f: Array[String]) -> void:
	_eqi(f, SecondStrike.SECOND_DELAY_TICKS, 60,
			"second_strike: the delay is not 1.0 s (60 ticks)")
	_eqf(f, SecondStrike.BLAST_RADIUS, 5.0, "second_strike: the sphere is not the nuke's 5 u")
	_eqs(f, SecondStrike.DEATH_CODE, "D-NUKE", "second_strike: the death code is not the nuke's")
	_eqs(f, SecondStrike.RING_KIND, "ground_ring",
			"second_strike: the ring kind is not the nuke's")
	# the blast tick: the nuke row ENTERS its pause with paused_by "blast"
	var rt := _rt()
	var ctl = rt.controllers[0]
	ctl.x = 3.5
	ctl.y = 0.5
	ctl.z = 0.5
	var nuke := _row(rt, "nuke", Vector3(0.5, 0.5, 0.5), {})
	nuke["phase"] = "lock"
	nuke["det"] = {"x": 0.5, "y": 0.5, "z": 0.5}
	var api := FakeApi.new()
	api.near = {"index": 0, "x": 3.5, "y": 0.5, "z": 0.5, "vx": 0.0, "vy": 0.0, "vz": 0.0}
	var st := _state(rt, _held("second_strike"), 10)
	SecondStrike.on_tick(st, api)
	_eqi(f, (st["curse_st"].get(SecondStrike.ST_KEY, []) as Array).size(), 0,
			"second_strike: a missile was scheduled before any blast")
	nuke["phase"] = "pause"
	nuke["paused_by"] = "blast"
	st["tick"] = 20
	SecondStrike.on_tick(st, api)
	var entries: Array = st["curse_st"].get(SecondStrike.ST_KEY, [])
	_eqi(f, entries.size(), 1, "second_strike: the blast did not schedule a second missile")
	if entries.size() == 1:
		_eqi(f, int(entries[0]["due"]), 80,
				"second_strike: the second missile is not 1.0 s out")
		_eqf(f, float(entries[0]["x"]), 3.5,
				"second_strike: the missile did not aim at the new x")
		_eqf(f, float(entries[0]["z"]), 0.5,
				"second_strike: the missile did not aim at the new z")
	_eqi(f, api.telegraphs.size(), 1, "second_strike: the second missile announced no ring")
	if api.telegraphs.size() == 1:
		_eqs(f, str(api.telegraphs[0]["kind"]), "ground_ring",
				"second_strike: the second missile is not the nuke's own ring")
		_eqi(f, int(api.telegraphs[0]["ticks"]), 60, "second_strike: the ring is not 1.0 s")
	# the pause's remaining ticks schedule nothing more (the transition, not the phase)
	st["tick"] = 21
	SecondStrike.on_tick(st, api)
	_eqi(f, (st["curse_st"][SecondStrike.ST_KEY] as Array).size(), 1,
			"second_strike: the pause scheduled a second missile twice")
	# the counter-play: running out of the 5 u sphere survives
	ctl.x = 12.5
	st["tick"] = 80
	SecondStrike.on_tick(st, api)
	_eqi(f, api.kills.size(), 0, "second_strike: the second missile killed a player who ran")
	_eqi(f, (st["curse_st"][SecondStrike.ST_KEY] as Array).size(), 0,
			"second_strike: the landed missile stayed scheduled")
	# standing still inside the sphere dies with the nuke's own code
	var rt2 := _rt()
	var ctl2 = rt2.controllers[0]
	ctl2.x = 3.5
	ctl2.y = 0.5
	ctl2.z = 0.5
	var nuke2 := _row(rt2, "nuke", Vector3(0.5, 0.5, 0.5), {})
	nuke2["phase"] = "lock"
	nuke2["det"] = {"x": 0.5, "y": 0.5, "z": 0.5}
	var api2 := FakeApi.new()
	api2.near = {"index": 0, "x": 3.5, "y": 0.5, "z": 0.5, "vx": 0.0, "vy": 0.0, "vz": 0.0}
	var st2 := _state(rt2, _held("second_strike"), 10)
	SecondStrike.on_tick(st2, api2)
	nuke2["phase"] = "pause"
	nuke2["paused_by"] = "blast"
	st2["tick"] = 20
	SecondStrike.on_tick(st2, api2)
	st2["tick"] = 80
	SecondStrike.on_tick(st2, api2)
	_eqi(f, api2.kills.size(), 1, "second_strike: the second missile did not kill the stander")
	if api2.kills.size() == 1:
		_eqs(f, str(api2.kills[0]["code"]), "D-NUKE",
				"second_strike: the kill code is not D-NUKE")
		_eqs(f, str(api2.kills[0]["killer"]), "nuke",
				"second_strike: the killer is not the nuke")
	# not held: no second missile
	var rt3 := _rt()
	var nuke3 := _row(rt3, "nuke", Vector3(0.5, 0.5, 0.5), {})
	nuke3["phase"] = "lock"
	nuke3["det"] = {"x": 0.5, "y": 0.5, "z": 0.5}
	var api3 := FakeApi.new()
	api3.near = {"index": 0, "x": 0.5, "y": 0.5, "z": 0.5, "vx": 0.0, "vy": 0.0, "vz": 0.0}
	var st3 := _state(rt3, {}, 10)
	SecondStrike.on_tick(st3, api3)
	nuke3["phase"] = "pause"
	nuke3["paused_by"] = "blast"
	st3["tick"] = 20
	SecondStrike.on_tick(st3, api3)
	_eqi(f, (st3["curse_st"].get(SecondStrike.ST_KEY, []) as Array).size(), 0,
			"second_strike: a not-held run scheduled a second missile")


## "+4 flat extra mines per stack (20% cap still holds)"
func _t_understudies(f: Array[String]) -> void:
	_eqi(f, Understudies.MINES_PER_STACK, 4, "understudies: the flat add is not +4 per stack")
	_eqi(f, Understudies.MAX_STACKS, 3, "understudies: the stack cap is not the JSON's 3")
	_eqi(f, Understudies.extra_mines(_held("understudies", 1)), 4,
			"understudies: one stack is not +4 mines")
	_eqi(f, Understudies.extra_mines(_held("understudies", 2)), 8,
			"understudies: two stacks are not +8 mines")
	_eqi(f, Understudies.extra_mines(_held("understudies", 3)), 12,
			"understudies: three stacks are not +12 mines")
	_eqi(f, Understudies.extra_mines(_held("understudies", 4)), 12,
			"understudies: a fourth stack went past the JSON's max_stacks")
	_eqi(f, Understudies.extra_mines({"curses_held": {}}), 0,
			"understudies: a not-held run added mines")
	_eqi(f, Understudies.total_extra_mines(_held("understudies", 1), 6), 10,
			"understudies: the roster's own extra mines were not added to the flat add")
	# the 20% cap still holds: the REAL generator never places more than n // 5 mines,
	# with the curse's flat add on top of the roster's - and the base roll is untouched
	# (every base mine is still a mine, so no per-slot chance moved)
	var l0: Dictionary = VoidGenScript.generate(11, 12, 1, 0)
	var l3: Dictionary = VoidGenScript.generate(11, 12, 1,
			Understudies.total_extra_mines(_held("understudies", 3), 0))
	var g0: Array = l0.get("gifts", [])
	var g3: Array = l3.get("gifts", [])
	if g0.is_empty() or g3.is_empty():
		f.append("understudies: the generator produced no gift slots")
		return
	var cap := Understudies.mine_cap(g0.size())
	_eqi(f, cap, g0.size() / 5, "understudies: the cap is not the 20% n // 5")
	var n0 := _mine_count(g0)
	var n3 := _mine_count(g3)
	_check(f, n0 <= cap, "understudies: the base level already broke the 20% cap")
	_check(f, n3 <= cap, "understudies: the flat add broke the 20%% cap (%d > %d)" % [n3, cap])
	_check(f, n3 >= n0, "understudies: the flat add placed no extra mine")
	var moved := 0
	for i in range(mini(g0.size(), g3.size())):
		if int(g0[i]["occ"]) == 1 and int(g3[i]["occ"]) != 1:
			moved += 1
	_eqi(f, moved, 0, "understudies: the flat add changed the per-slot mine chance")


## The tripmine count of a generated level's gift rows (occ 1 = tripmine).
func _mine_count(gifts: Array) -> int:
	var n := 0
	for g in gifts:
		if int(g["occ"]) == 1:
			n += 1
	return n


## "mine blast radius 3 → 4.5 u and the blast chain-detonates mines inside it"
func _t_wide_blast(f: Array[String]) -> void:
	_eqf(f, WideBlast.BLAST_RADIUS_BASE, 3.0, "wide_blast: the base radius is not 3 u")
	_eqf(f, WideBlast.BLAST_RADIUS_HELD, 4.5, "wide_blast: the widened radius is not 4.5 u")
	_eqf(f, WideBlast.blast_radius_u({"curses_held": {}}), 3.0,
			"wide_blast: a not-held run widened the blast")
	_eqf(f, WideBlast.blast_radius_u(_held("wide_blast")), 4.5,
			"wide_blast: the held blast is not 4.5 u")
	_check(f, not WideBlast.chain_detonates({"curses_held": {}}),
			"wide_blast: a not-held run chain-detonated")
	_check(f, WideBlast.chain_detonates(_held("wide_blast")),
			"wide_blast: the held blast does not chain")
	# the chain: the mine 3.5 u away is inside BOTH spheres, the one 4.4 u away only
	# inside the widened one - so the widening is what adds it
	var origin := Vector3(0.0, 0.5, 0.0)
	var mines: Array = [Vector3(0.0, 0.5, 0.0), Vector3(3.5, 0.5, 0.0),
			Vector3(6.0, 0.5, 0.0), {"x": 0.0, "y": 0.5, "z": 4.4}]
	var held: Array = WideBlast.chain_targets(_held("wide_blast"), origin, mines, 0)
	_eqi(f, held.size(), 2, "wide_blast: the chain did not reach both mines inside 4.5 u")
	if held.size() == 2:
		_eqi(f, int(held[0]), 1, "wide_blast: the 3.5 u mine did not chain")
		_eqi(f, int(held[1]), 3, "wide_blast: the 4.4 u mine did not chain")
	var free: Array = WideBlast.chain_targets({"curses_held": {}}, origin, mines, 0)
	_eqi(f, free.size(), 0, "wide_blast: a not-held run chained a mine")
	# the detonating mine itself is never in its own chain
	var self_only: Array = WideBlast.chain_targets(_held("wide_blast"), origin,
			[Vector3(0.0, 0.5, 0.0)], 0)
	_eqi(f, self_only.size(), 0, "wide_blast: the blast chained the mine that detonated")


## A REAL sim/enemy_runtime.gd whose LEVEL carries tiles (the glitched-tile curses read
## rt.level's tile set, which the shared _rt() fixture leaves empty).
func _rt_with_level(tiles: Array) -> RefCounted:
	var ctl = ControllerScript.new()
	ctl.setup("dasher", TestUtil.consts())
	var rt = EnemyRuntimeScript.new()
	rt.setup({"tiles": tiles, "beacon": [0, 0, 1], "spawns": [[0, 0, 1]]},
			TestUtil.world_from_tiles(tiles), [ctl], 7)
	return rt


## "each glitched tile infects one adjacent tile after 6 s (max 2 generations)"
func _t_spreading_rot(f: Array[String]) -> void:
	_eqi(f, SpreadingRot.SPREAD_DELAY_TICKS, 360, "spreading_rot: the delay is not 6 s")
	_eqi(f, SpreadingRot.MAX_GENERATIONS, 2,
			"spreading_rot: the cap is not 2 generations")
	# a 5-tile strip at y_hu 0: the source at x = 2 grows +x first
	var tiles: Array = [[0, 0, 0], [1, 0, 0], [2, 0, 0], [3, 0, 0], [4, 0, 0]]
	var keys: Dictionary = SpreadingRot.tile_keys({"tiles": tiles})
	_eqi(f, keys.size(), 5, "spreading_rot: the level's tile keys were not read")
	_eqs(f, SpreadingRot.pick_adjacent("2,0,0", keys, {}), "3,0,0",
			"spreading_rot: the first adjacent tile is not +x")
	_eqs(f, SpreadingRot.pick_adjacent("2,0,0", keys, {"3,0,0": true}), "1,0,0",
			"spreading_rot: an already glitched neighbour was picked")
	_eqs(f, SpreadingRot.pick_adjacent("0,0,0", {"0,0,0": true}, {}), "",
			"spreading_rot: a tile with no neighbour still spread")
	# end to end: one glitched tile grows one ring per 6 s and stops at generation 2
	var rt := _rt_with_level(tiles)
	rt.world["glitched"]["2,0,0"] = true
	var st := _state(rt, _held("spreading_rot"), 0)
	var api := FakeApi.new()
	SpreadingRot.on_tick(st, api)
	_eqi(f, (rt.world["glitched"] as Dictionary).size(), 1,
			"spreading_rot: the source spread before its 6 s")
	for t in range(1, 361):
		st["tick"] = t
		SpreadingRot.on_tick(st, api)
	_eqi(f, (rt.world["glitched"] as Dictionary).size(), 2,
			"spreading_rot: the source did not infect exactly one tile at 6 s")
	_check(f, (rt.world["glitched"] as Dictionary).has("3,0,0"),
			"spreading_rot: the infected tile is not the +x neighbour")
	for t in range(361, 721):
		st["tick"] = t
		SpreadingRot.on_tick(st, api)
	_eqi(f, (rt.world["glitched"] as Dictionary).size(), 3,
			"spreading_rot: generation 1 did not spread once")
	_check(f, (rt.world["glitched"] as Dictionary).has("4,0,0"),
			"spreading_rot: generation 2 is not the next ring out")
	# generation 2 never spreads: nothing new in the next 6 s
	for t in range(721, 1080):
		st["tick"] = t
		SpreadingRot.on_tick(st, api)
	_eqi(f, (rt.world["glitched"] as Dictionary).size(), 3,
			"spreading_rot: a generation-2 tile spread (the cap is 2)")
	# the curse's own grown tile ages out at the toucher's own 12 s (born 360)
	st["tick"] = 1080
	SpreadingRot.on_tick(st, api)
	_eqi(f, (rt.world["glitched"] as Dictionary).size(), 2,
			"spreading_rot: the curse's own tile never aged out")
	_check(f, not (rt.world["glitched"] as Dictionary).has("3,0,0"),
			"spreading_rot: the aged tile is not the generation-1 one")
	# not held: the source never spreads
	var rt2 := _rt_with_level(tiles)
	rt2.world["glitched"]["2,0,0"] = true
	var st2 := _state(rt2, {}, 0)
	for t in range(0, 400):
		st2["tick"] = t
		SpreadingRot.on_tick(st2, api)
	_eqi(f, (rt2.world["glitched"] as Dictionary).size(), 1,
			"spreading_rot: a not-held run spread the rot")


## "glitched tiles are slippery (friction ×0.4); the toucher's slow stays −20% — no
## extra slow (D-075)"
func _t_wet_floor(f: Array[String]) -> void:
	_eqf(f, WetFloor.FRICTION_MUL, 0.4, "wet_floor: the friction is not x0.4")
	_eqf(f, WetFloor.friction_mul({"curses_held": {}}), 1.0,
			"wet_floor: a not-held run made the floor slippery")
	_eqf(f, WetFloor.friction_mul(_held("wet_floor")), 0.4,
			"wet_floor: the held floor is not x0.4 friction")
	# D-075: the toucher's slow stays -20% - the curse adds NO extra slow
	_eqf(f, WetFloor.slow_mul(_held("wet_floor")), ControllerScript.GLITCH_SLOW_MUL,
			"wet_floor: the curse changed the glitched floor's own slow")
	_eqf(f, WetFloor.slow_mul({"curses_held": {}}), ControllerScript.GLITCH_SLOW_MUL,
			"wet_floor: the base glitched slow moved")
	# on_tick marks exactly the glitched tiles in the world's own slippery map
	var rt := _rt()
	rt.world["glitched"]["2,0,0"] = true
	rt.world["glitched"]["3,0,0"] = true
	WetFloor.on_tick(_state(rt, _held("wet_floor"), 0), FakeApi.new())
	var slip: Dictionary = rt.world["slippery"]
	_eqi(f, slip.size(), 2, "wet_floor: the glitched tiles were not marked slippery")
	_check(f, slip.has("2,0,0") and slip.has("3,0,0"),
			"wet_floor: the marked keys are not the glitched keys")
	var ctl = rt.controllers[0]
	ctl.cur_key = "2,0,0"
	# the run speed is the glitched floor's own -20%, never more
	_eqf(f, ctl.run_speed(rt.world), float(ctl.C["run_speed"]) * ControllerScript.GLITCH_SLOW_MUL,
			"wet_floor: the glitched slow is not the toucher's own -20%")
	# the write is load-bearing: with the glitched map emptied, the controller still
	# reads 0.4 friction off the slippery map the curse wrote
	(rt.world["glitched"] as Dictionary).clear()
	_eqf(f, ctl.friction_mult(rt.world), 0.4,
			"wet_floor: the slippery map the curse wrote is not what the controller reads")
	# not held: nothing is marked
	var rt2 := _rt()
	rt2.world["glitched"]["2,0,0"] = true
	WetFloor.on_tick(_state(rt2, {}, 0), FakeApi.new())
	_eqi(f, (rt2.world["slippery"] as Dictionary).size(), 0,
			"wet_floor: a not-held run marked the floor slippery")


## The api a dispatcher hands a curse, with a spawn_enemy that REALLY lands the row in
## the runtime - so a curse that spawns a second body can be driven end-to-end.
class SpawnApi:
	extends RefCounted
	var rt = null
	var spawns: Array = []
	var telegraphs: Array = []
	var near: Dictionary = {}

	func nearest_player(_pos: Vector3) -> Dictionary:
		return near

	func spawn_enemy(def: Dictionary) -> void:
		spawns.append(def)
		if rt == null:
			return
		rt.spawn_at(str(def["id"]), str(def.get("name", "")), SealScript.SealBehavior.new(),
				def.get("cfg", {}), Vector3(float(def["x"]), float(def["y"]), float(def["z"])))

	func telegraph(kind: String, shape: Dictionary, ticks: int) -> void:
		telegraphs.append({"kind": kind, "shape": shape, "ticks": ticks})

	func sync_body() -> void:
		pass


## "every seal has a second seal that dashes 0.5 s after it" - proven END-TO-END: a REAL
## seal runs in a REAL sim/enemy_runtime.gd, the curse spawns its partner through
## api.spawn_enemy and staggers that partner's dash.
func _t_pup_pack(f: Array[String]) -> void:
	_eqi(f, PupPack.DASH_DELAY_TICKS, 30, "pup_pack: the stagger is not 0.5 s (30 ticks)")
	_eqi(f, PupPack.TELEGRAPH_TICKS, SealScript.TELEGRAPH_TICKS,
			"pup_pack: the seal's telegraph moved off 45")
	_eqi(f, PupPack.DASH_TICKS, SealScript.DASH_TICKS,
			"pup_pack: the seal's dash moved off 60")
	_eqf(f, PupPack.DASH_LENGTH_U, SealScript.DASH_LENGTH_U,
			"pup_pack: the fixed line moved off 20 u")
	_eqf(f, PupPack.BODY_HEIGHT, SealScript.BODY_HEIGHT,
			"pup_pack: the body height moved off the seal's")
	_eqf(f, PupPack.PLAYER_CENTRE_U, SealScript.PLAYER_CENTRE_U,
			"pup_pack: the aim point moved off the seal's")
	_eqs(f, PupPack.KIND, "dash_line", "pup_pack: the telegraph kind is not the seal's")
	_eqi(f, PupPack.second_telegraph_ticks(), 75,
			"pup_pack: the second seal's telegraph is not 45 + 30")
	var rt := _rt()
	var ctl = rt.controllers[0]
	ctl.x = 0.5
	ctl.y = 0.5
	ctl.z = 0.5
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0
	ctl.invuln = 1.0e9   # the dash line runs through the player: keep the geometry stable
	var seal: Dictionary = rt.spawn_at("seal", "seal", SealScript.SealBehavior.new(),
			SealScript.cfg(), Vector3(8.5, 0.5, 0.5))
	var api := SpawnApi.new()
	api.rt = rt
	var st := _state(rt, _held("pup_pack"), 0)
	var first_dash := -1
	var second_dash := -1
	var second_row: Variant = null
	for t in 400:
		rt.step(TestUtil.DT)
		st["tick"] = rt.tick
		api.near = {"index": 0, "x": float(ctl.x), "y": float(ctl.y), "z": float(ctl.z),
				"vx": 0.0, "vy": 0.0, "vz": 0.0}
		PupPack.on_tick(st, api)
		if first_dash < 0 and str(seal.get("phase", "")) == "dash":
			first_dash = t
		if second_row == null and rt.enemies.size() > 1:
			second_row = rt.enemies[1]
		if second_row != null and second_dash < 0 \
				and str(second_row.get("phase", "")) == "dash":
			second_dash = t
		if first_dash >= 0 and second_dash >= 0:
			break
	_eqi(f, api.spawns.size(), 1, "pup_pack: the seal was not given exactly one partner")
	_check(f, first_dash >= 0, "pup_pack: the first seal never dashed")
	_check(f, second_dash >= 0, "pup_pack: the second seal never dashed")
	if first_dash >= 0 and second_dash >= 0:
		_eqi(f, second_dash - first_dash, 30,
				"pup_pack: the second seal did not dash 0.5 s after the first")
	# the pack never grows: the partner carries the marker, so it is never paired again
	PupPack.on_tick(st, api)
	_eqi(f, api.spawns.size(), 1, "pup_pack: the pack grew a third seal")


## "a dash leaves a slippery trail (friction ×0.4) for 3 s"
func _t_slipstream_trail(f: Array[String]) -> void:
	_eqi(f, SlipstreamTrail.TRAIL_TICKS, 180, "slipstream_trail: the trail is not 3 s")
	_eqf(f, SlipstreamTrail.FRICTION_MUL, 0.4, "slipstream_trail: the friction is not x0.4")
	_eqf(f, SlipstreamTrail.friction_mul({"curses_held": {}}), 1.0,
			"slipstream_trail: a not-held run made the floor slippery")
	_eqf(f, SlipstreamTrail.friction_mul(_held("slipstream_trail")), 0.4,
			"slipstream_trail: the held trail is not x0.4 friction")
	_eqs(f, SlipstreamTrail.tile_key_at(3.4, 0.5, 2.6), "3,2,1",
			"slipstream_trail: the tile key is not collision.gd's x,z,y_hu")
	# a dashing seal leaves its tile slippery; a flapping one does not
	var rt := _rt()
	var seal := _row(rt, "seal", Vector3(3.5, 0.5, 2.5), {})
	seal["phase"] = "flap"
	var st := _state(rt, _held("slipstream_trail"), 0)
	SlipstreamTrail.on_tick(st, FakeApi.new())
	_eqi(f, (rt.world["slippery"] as Dictionary).size(), 0,
			"slipstream_trail: a flapping seal left a trail")
	seal["phase"] = "dash"
	st["tick"] = 10
	SlipstreamTrail.on_tick(st, FakeApi.new())
	var slip: Dictionary = rt.world["slippery"]
	_eqi(f, slip.size(), 1, "slipstream_trail: the dash left no trail")
	_check(f, slip.has("3,2,1"), "slipstream_trail: the trail is not under the seal")
	# the controller standing there really is slippery
	var ctl = rt.controllers[0]
	ctl.cur_key = "3,2,1"
	_eqf(f, ctl.friction_mult(rt.world), 0.4, "slipstream_trail: the trail is not slippery")
	# the trail expires 3 s after the last dash tick (stamped at 10, so due at 190)
	seal["phase"] = "recover"
	st["tick"] = 189
	SlipstreamTrail.on_tick(st, FakeApi.new())
	_eqi(f, (rt.world["slippery"] as Dictionary).size(), 1,
			"slipstream_trail: the trail expired early")
	st["tick"] = 190
	SlipstreamTrail.on_tick(st, FakeApi.new())
	_eqi(f, (rt.world["slippery"] as Dictionary).size(), 0,
			"slipstream_trail: the trail never expired")
	# not held: no trail
	var rt2 := _rt()
	var seal2 := _row(rt2, "seal", Vector3(3.5, 0.5, 2.5), {})
	seal2["phase"] = "dash"
	SlipstreamTrail.on_tick(_state(rt2, {}, 0), FakeApi.new())
	_eqi(f, (rt2.world["slippery"] as Dictionary).size(), 0,
			"slipstream_trail: a not-held run left a trail")


## "no trumpet — only the sprite and the rumble"
func _t_unannounced(f: Array[String]) -> void:
	_eqs(f, Unannounced.TRUMPET_CUE, "spawn_trumpet",
			"unannounced: the silenced cue is not the trumpet")
	_eqi(f, Unannounced.ALL_CUES.size(), 3,
			"unannounced: the cue list is not address me's own 3")
	var free: Array = Unannounced.cue_names({"curses_held": {}})
	_eqi(f, free.size(), 3, "unannounced: a not-held run dropped a cue")
	_check(f, free.has("spawn_trumpet"), "unannounced: the base run lost its trumpet")
	var held: Array = Unannounced.cue_names(_held("unannounced"))
	_eqi(f, held.size(), 2, "unannounced: the trumpet was not the only cue dropped")
	_check(f, not held.has("spawn_trumpet"), "unannounced: the trumpet still plays")
	_check(f, held.has("rumble_build"), "unannounced: the rumble was silenced too")
	_check(f, held.has("explode_boom"), "unannounced: the kill's boom was silenced too")
	_check(f, not Unannounced.cue_allowed(_held("unannounced"), "spawn_trumpet"),
			"unannounced: cue_allowed still allows the trumpet")
	_check(f, Unannounced.cue_allowed(_held("unannounced"), "rumble_build"),
			"unannounced: cue_allowed dropped the rumble")
	_check(f, Unannounced.sprite_visible(_held("unannounced")),
			"unannounced: the sprite was hidden")
	_check(f, Unannounced.rumble_audible(_held("unannounced")),
			"unannounced: the rumble was silenced")


## "a clawd leaves 20 s of anger instead of calming Claude completely"
func _t_token_limit(f: Array[String]) -> void:
	_eqi(f, TokenLimit.CALM_LEFTOVER_TICKS, 1200, "token_limit: the leftover is not 20 s")
	_eqi(f, TokenLimit.CALM_FULL_TICKS, 0, "token_limit: the sim's own calm moved off 0")
	_eqi(f, TokenLimit.calm_leftover_ticks({"curses_held": {}}), 0,
			"token_limit: a not-held run changed the calm")
	_eqi(f, TokenLimit.calm_leftover_ticks(_held("token_limit")), 1200,
			"token_limit: the held leftover is not 20 s")
	# on_tick pushes the leftover onto the clawd state
	var cl = _clawds()
	var st := _state_cl(_rt(), _held("token_limit"), 0, cl)
	TokenLimit.on_tick(st, FakeApi.new())
	_eqi(f, int(cl.calm_leftover_ticks), 1200,
			"token_limit: the clawd state did not take the 20 s leftover")
	# not held: the sim's own calm (a pickup resets the timer to 0)
	var cl2 = _clawds()
	var st2 := _state_cl(_rt(), {}, 0, cl2)
	TokenLimit.on_tick(st2, FakeApi.new())
	_eqi(f, int(cl2.calm_leftover_ticks), 0, "token_limit: a not-held run still left anger behind")
	# a level with no swarm: the hook is a no-op, not a crash
	var st3 := _state(_rt(), _held("token_limit"), 0)
	TokenLimit.on_tick(st3, FakeApi.new())


## "each strike marks two patches: yours and where you will be in 1.0 s"
func _t_twin_fangs(f: Array[String]) -> void:
	_eqi(f, TwinFangs.PREDICT_TICKS, 60, "twin_fangs: the lead is not 1.0 s (60 ticks)")
	_eqi(f, TwinFangs.PATCH_HALF, GinScript.PATCH_HALF,
			"twin_fangs: the patch is not gin's own 5x5")
	_eqi(f, TwinFangs.TELEGRAPH_TICKS, GinScript.TELEGRAPH_TICKS,
			"twin_fangs: the mark is not gin's own 120 ticks")
	_eqs(f, TwinFangs.DEATH_CODE, GinScript.DEATH_CODE,
			"twin_fangs: the death code is not gin's own")
	_eqs(f, TwinFangs.KIND, GinScript.MARK, "twin_fangs: the telegraph kind is not gin's")
	# where the player will be in 1.0 s
	var p: Vector3 = TwinFangs.predict_point({"x": 10.0, "y": 0.5, "z": 10.0,
			"vx": 2.0, "vy": 0.0, "vz": -1.0})
	_eqf(f, p.x, 12.0, "twin_fangs: the predicted x is not 1.0 s of velocity ahead")
	_eqf(f, p.z, 9.0, "twin_fangs: the predicted z is not 1.0 s of velocity ahead")
	_eqf(f, p.y, 0.5, "twin_fangs: the predicted point left the player's plane")
	# the patch is gin's own 5x5, minus the dais cell
	_eqi(f, TwinFangs.patch_cells(12, 10, [1, 1, 1]).size(), 25,
			"twin_fangs: the patch is not the strike's own 5x5")
	_eqi(f, TwinFangs.patch_cells(1, 1, [1, 1, 1]).size(), 24,
			"twin_fangs: the dais cell was marked")
	# the strike's start marks the second patch, and the void window makes it lethal
	var rt := _rt()
	var ctl = rt.controllers[0]
	ctl.x = 10.5
	ctl.y = 0.5
	ctl.z = 10.5
	ctl.vx = 2.0
	ctl.vz = 0.0
	var gin := _row(rt, "gin", Vector3(30.5, 0.5, 30.5), {})
	gin["phase"] = "spawn"
	var api := FakeApi.new()
	api.near = {"index": 0, "x": 10.5, "y": 0.5, "z": 10.5, "vx": 2.0, "vy": 0.0, "vz": 0.0}
	var st := _state(rt, _held("twin_fangs"), 0)
	TwinFangs.on_tick(st, api)
	_eqi(f, api.telegraphs.size(), 0, "twin_fangs: a mark was announced before the strike")
	gin["phase"] = "mark"
	st["tick"] = 1
	TwinFangs.on_tick(st, api)
	_eqi(f, api.telegraphs.size(), 1, "twin_fangs: the strike did not mark a second patch")
	if api.telegraphs.size() == 1:
		var sh: Dictionary = api.telegraphs[0]["shape"]
		_eqf(f, float(sh["cx"]), 12.5,
				"twin_fangs: the second patch is not 1.0 s ahead in x")
		_eqf(f, float(sh["cz"]), 10.5,
				"twin_fangs: the second patch left the player's z")
		_eqi(f, int(api.telegraphs[0]["ticks"]), GinScript.TELEGRAPH_TICKS,
				"twin_fangs: the second mark is not the strike's own 120 ticks")
	# the void window: a player standing in the second patch dies with D-GIN
	ctl.x = 12.5
	ctl.z = 10.5
	gin["phase"] = "void"
	st["tick"] = 140
	TwinFangs.on_tick(st, api)
	_eqi(f, api.kills.size(), 1, "twin_fangs: the second patch did not kill")
	if api.kills.size() == 1:
		_eqs(f, str(api.kills[0]["code"]), "D-GIN",
				"twin_fangs: the kill code is not gin's own")
		_eqs(f, str(api.kills[0]["killer"]), "gin", "twin_fangs: the killer is not gin")
	# the counter-play: a player who changed direction during the mark survives
	ctl.x = 40.5
	ctl.z = 40.5
	st["tick"] = 141
	TwinFangs.on_tick(st, api)
	_eqi(f, api.kills.size(), 1, "twin_fangs: the second patch killed a player who moved")
	# the patch is spent when the window closes: the next strike marks afresh
	gin["phase"] = "fade_back"
	st["tick"] = 700
	TwinFangs.on_tick(st, api)
	_check(f, not st["curse_st"].has("tf_patch_0"),
			"twin_fangs: the spent patch stayed armed after the window closed")
	# not held: no second patch
	var rt2 := _rt()
	var gin2 := _row(rt2, "gin", Vector3(30.5, 0.5, 30.5), {})
	gin2["phase"] = "spawn"
	var api2 := FakeApi.new()
	api2.near = {"index": 0, "x": 10.5, "y": 0.5, "z": 10.5, "vx": 2.0, "vy": 0.0, "vz": 0.0}
	var st2 := _state(rt2, {}, 0)
	TwinFangs.on_tick(st2, api2)
	gin2["phase"] = "mark"
	st2["tick"] = 1
	TwinFangs.on_tick(st2, api2)
	_eqi(f, api2.telegraphs.size(), 0, "twin_fangs: a not-held run marked a second patch")


# ---- the module contract ---------------------------------------------------------

## Every "script": true curse with requires_enemy set (the family THIS ticket owns)
## has a module here, whose CURSE_ID is the JSON id and whose source quotes the
## JSON's own rule sentence VERBATIM (whitespace-normalised) - one rule sentence,
## asserted. The full inventory is pinned at 24; the only id still NOT_ON_MAIN is
## zoomies (retired from the offer pool, its module on the never-merged
## t3/scripted-curses-groups-4-6 branch) - if it returns to the pool, that list must
## shrink and the id joins this file.
func _t_module_contract(f: Array[String]) -> void:
	var api: RefCounted = ContentApiScript.load()
	if not api.call("is_ok"):
		f.append("module contract: content api boot failed")
		return
	var family: Array[String] = []
	for id in api.call("curse_ids"):
		var doc: Dictionary = api.call("curse", id)
		if bool(doc.get("script", false)) and doc.get("requires_enemy") != null:
			family.append(id)
	_eqi(f, family.size(), 24, "enemy-linked scripted family is not 24 curses: %s" % str(family))
	family.sort()
	var present := {}
	for m in MODULES:
		present[str(m.CURSE_ID)] = m
	var missing: Array[String] = []
	for id in family:
		if not NOT_ON_MAIN.has(id) and not present.has(id):
			missing.append(id)
	_eqi(f, missing.size(), 0, "module contract: no module on main for %s" % str(missing))
	var still_out: Array[String] = []
	for id in NOT_ON_MAIN:
		if not family.has(id):
			still_out.append(id)
		if present.has(id):
			still_out.append(id + " (already merged - move its test into this file)")
	_eqi(f, still_out.size(), 0, "module contract: the NOT_ON_MAIN list drifted: %s" % str(still_out))
	var text_cache := {}
	var modules_by_id := {
		"aftershock": Aftershock, "bunker_buster": BunkerBuster, "crescendo": Crescendo,
		"direct_shot": DirectShot, "double_ring": DoubleRing, "egoist": Egoist,
		"litter": Litter, "long_toll": LongToll, "longer_speech": LongerSpeech,
		"method_acting": MethodActing, "mirror_match": MirrorMatch, "overwound": Overwound,
		"quarter_chimes": QuarterChimes, "second_strike": SecondStrike,
		"understudies": Understudies, "wide_blast": WideBlast,
		"spreading_rot": SpreadingRot, "wet_floor": WetFloor,
		"pup_pack": PupPack, "slipstream_trail": SlipstreamTrail,
		"unannounced": Unannounced, "token_limit": TokenLimit,
		"twin_fangs": TwinFangs,
	}
	for id in family:
		if not modules_by_id.has(id):
			continue   # parked: the merge-gap ids (NOT_ON_MAIN) are the pending branch's
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
		for mth in mod.get_script_method_list():
			var name := str(mth["name"])
			if name.begins_with("on_") and not HooksScript.HOOKS.has(name):
				f.append("module contract: %s handles unknown hook '%s'" % [id, name])
