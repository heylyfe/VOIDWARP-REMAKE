extends RefCounted
#
# T-051 scripted curses - the ENEMY-LINKED modules on main. The 12 "script": true
# curses whose requires_enemy is set AND whose module is merged here:
#   aftershock, bunker_buster, crescendo, direct_shot, double_ring, egoist, litter,
#   long_toll, longer_speech, method_acting, mirror_match, overwound.
# One test per curse, each asserting the JSON's own rule sentence. The other 12
# enemy-linked script curses (pup_pack, quarter_chimes, second_strike,
# slipstream_trail, spreading_rot, token_limit, twin_fangs, unannounced,
# understudies, wet_floor, wide_blast, zoomies) have their modules on the unmerged
# t3/scripted-curses-groups-4-6 branch, not on main - PARKED.md keeps that row; the
# module-contract test below pins the full 24-id inventory so the next module merge
# must promote those ids into this file. Nothing here names the general family's
# 11 curses, and every helper lives IN THIS FILE (no shared helper file).
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
# The two ticket done-whens that are THIS file's:
#   - long_toll: the second ben arrival lands at the same locked point exactly
#     90 ticks (1.5 s) after the first and never kills - proven END-TO-END below
#     against the REAL thicc_ben behavior driven inside a REAL sim/enemy_runtime.gd
#     (the only curse where the rule lives in a behavior contract); and
#   - understudies' 20% mine cap: MODULE NOT ON MAIN (see the parked row) - the
#     1,000-seed walk is tools/check_mine_cap.gd on that branch, this checkout has
#     neither the tool nor the module, so the 100-seed assertion cannot exist yet.
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
const BenScript := preload("res://content/enemies/thicc_ben/enemy.gd")

const Aftershock := preload("res://content/curses/aftershock.gd")
const BunkerBuster := preload("res://content/curses/bunker_buster.gd")
const Crescendo := preload("res://content/curses/crescendo.gd")
const DirectShot := preload("res://content/curses/direct_shot.gd")
const DoubleRing := preload("res://content/curses/double_ring.gd")
const Egoist := preload("res://content/curses/egoist.gd")
const Litter := preload("res://content/curses/litter.gd")
const LongToll := preload("res://content/curses/long_toll.gd")
const LongerSpeech := preload("res://content/curses/longer_speech.gd")
const MethodActing := preload("res://content/curses/method_acting.gd")
const MirrorMatch := preload("res://content/curses/mirror_match.gd")
const Overwound := preload("res://content/curses/overwound.gd")

## The 12 modules above, in the order the tests run (one _t_ per curse below).
const MODULES: Array = [
	Aftershock, BunkerBuster, Crescendo, DirectShot, DoubleRing, Egoist,
	Litter, LongToll, LongerSpeech, MethodActing, MirrorMatch, Overwound,
]

## The enemy-linked script-curse ids whose modules are NOT on this checkout yet
## (each lives on the unmerged t3/scripted-curses-groups-4-6 branch; PARKED.md).
const NOT_ON_MAIN: Array[String] = [
	"pup_pack", "quarter_chimes", "second_strike", "slipstream_trail",
	"spreading_rot", "token_limit", "twin_fangs", "unannounced",
	"understudies", "wet_floor", "wide_blast", "zoomies",
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


## "agitation rises 3/s instead of 2/s"
func _t_crescendo(f: Array[String]) -> void:
	_eqf(f, Crescendo.BASE_RISE_PER_S, 2.0, "crescendo: the behavior's base rise moved")
	_eqf(f, Crescendo.TOTAL_RISE_PER_S, 3.0, "crescendo: the cursed total rise is not 3/s")
	_eqf(f, Crescendo.EXTRA_PER_S, 1.0, "crescendo: the curse's own slice is not the +1/s")
	_eqf(f, Crescendo.extra_after_ticks(60), 1.0,
			"crescendo: 60 ticks of the curse are not +1.0 agitation")
	var rt := _rt()
	var claude := _row(rt, "claude", Vector3(1.0, 0.0, 1.0), {})
	claude["agitation"] = 10.0
	var other := _row(rt, "coil", Vector3(2.0, 0.0, 1.0), {})
	other["agitation"] = 10.0
	var api := FakeApi.new()
	var st := _state(rt, _held("crescendo"), 0)
	for t in 60:
		st["tick"] = t
		Crescendo.on_tick(st, api)
	_eqf(f, float(claude["agitation"]), 11.0,
			"crescendo: 60 ticks on top of the 2/s base are not the 3/s sentence")
	_eqf(f, float(other["agitation"]), 10.0, "crescendo: a non-Claude row rose")
	# the clamp is the same 100 the base rise uses (the Deadline ceiling) ...
	for t in range(60, 180):
		st["tick"] = t
		Crescendo.on_tick(st, api)
	_eqf(f, float(claude["agitation"]), 13.0, "crescendo: the extra rise drifted")
	claude["agitation"] = 100.0
	Crescendo.on_tick(st, api)
	_eqf(f, float(claude["agitation"]), 100.0, "crescendo: agitation left the 100 clamp")
	# ... and the pure helper applies the same one-tick slice with the same clamp
	var probe := {"agitation": 99.9}
	Crescendo.apply_extra(probe, 30)
	_eqf(f, float(probe["agitation"]), 100.0, "crescendo: apply_extra left the 100 clamp")
	# not held: no rise from the curse
	var rt2 := _rt()
	var claude2 := _row(rt2, "claude", Vector3(1.0, 0.0, 1.0), {})
	claude2["agitation"] = 10.0
	Crescendo.on_tick(_state(rt2, {}, 0), api)
	_eqf(f, float(claude2["agitation"]), 10.0, "crescendo: a not-held run still rose")


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


## "each cat is followed by a kitten (60% size, 4.5 u/s, kills on contact) 6 u behind"
func _t_litter(f: Array[String]) -> void:
	_eqf(f, Litter.KITTEN_SIZE, 0.6, "litter: the kitten is not 60% of the cat")
	_eqf(f, Litter.KITTEN_SPEED, 4.5, "litter: the kitten speed is not 4.5 u/s")
	_eqf(f, Litter.KITTEN_CEILING, 0.70, "litter: the kitten's SR-5 ceiling is not 0.70")
	_eqf(f, Litter.TRAIL_U, 6.0, "litter: the kitten does not trail 6 u behind")
	_eqs(f, str(Litter.DEATH_CODE), "D-KIWI", "litter: the kitten is not still a kiwi cat")
	# the kitten's cfg: scaled body, own speed, SR-5 ceiling, contact kill ON, no meow
	var kc: Dictionary = Litter.kitten_cfg({"burst_ceiling": 1.0, "climb_u_per_s": 2.0,
			"world_height": 1.0, "body_height": 1.0, "hit_diameter": 0.9,
			"preferred_kind": "nook", "meow_period_ticks": 300, "meow_range_u": 25.0,
			"frame_w": 256, "frame_h": 256})
	_eqf(f, float(kc["base_speed"]), 4.5, "litter: the kitten cfg speed is not 4.5 u/s")
	_eqf(f, float(kc["pursuit_ceiling"]), 0.70, "litter: the kitten cfg ceiling is not 0.70")
	_eqf(f, float(kc["burst_ceiling"]), 0.6, "litter: the kitten burst ceiling did not scale to 60%")
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
		_eqf(f, float(def["cfg"]["base_speed"]), 4.5, "litter: the spawned kitten cfg speed moved")
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


# ---- the module contract ---------------------------------------------------------

## Every "script": true curse with requires_enemy set (the family THIS ticket owns)
## has a module here, whose CURSE_ID is the JSON id and whose source quotes the
## JSON's own rule sentence VERBATIM (whitespace-normalised) - one rule sentence,
## asserted. The full inventory is pinned at 24; the 12 modules the pending
## t3/scripted-curses-groups-4-6 branch holds are the NOT_ON_MAIN list exactly (see
## PARKED.md) - when they land, that list must shrink and the ids join this file.
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
