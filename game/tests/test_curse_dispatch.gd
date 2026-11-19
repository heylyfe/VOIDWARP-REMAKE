extends RefCounted
#
# CURSE-DISPATCH test (headless, W9-A): a held SCRIPT curse changes the shipped game.
#
# 35 of the 46 curses are script modules (content/curses/<id>.gd). Each module had its own
# green unit test while nothing in the shipped game called it - the unit tests call the
# module directly, so they could not see that. This file never calls a curse module. Every
# case builds a real level through app/world.gd build() with a carried ledger (the app's
# lobby handover shape) and drives it with world.step(); the only variable between the two
# builds of a case is the ledger's curses dict. sim/curse_runtime.gd is the dispatcher the
# world runs the hooks through.
#
# Each case measures ONE number or state twice: with curses {} (the negative control: it
# must equal the un-cursed canon value, asserted as a literal) and with the curse held
# (it must equal the cursed value). A case therefore cannot pass because the wiring is
# absent (the held half fails) nor because the measurement is broken (the control half
# fails).
#
# Hooks covered (at least one each, three on_tick):
#   on_level_start  early_bird (runtime spawn delay; an enemy appears at 2 s, not 6 s)
#                   cold_start (the dasher's dash starts on cooldown, regen x1.25)
#   on_tick         overwound  (the live coil row's idle 3.0 -> 2.0 s)
#                   litter     (a real kitten body spawns behind the cat - and only one)
#                   pup_pack   (a real second seal body spawns - and only one)
#                   crescendo  (claude's agitation rises faster)
#   on_beacon_open  curfew     (60 s after the open, overtime is +2 tiers)
#                   rearguard  (an extra enemy body spawns at the beacon)
#   on_void_fall    leaky_purse (a fall drops 5% of this level's earned gold)
# Build-time / live queries wired in world.gd:
#   understudies    total_extra_mines -> voidgen's extra_mines argument
#   slow_door       entry_ready       -> the beacon entry gate (3 s dwell)
#   crowded_dais    entry_blocked     -> the beacon entry gate (enemy within 8 u)

const WorldScript := preload("res://app/world.gd")

const SEED := 1
const LEVEL := 5
const DT := 1.0 / 60.0


func run() -> Array[String]:
	var f: Array[String] = []
	_early_bird(f)
	_cold_start(f)
	_overwound(f)
	_litter(f)
	_pup_pack(f)
	_crescendo(f)
	_curfew(f)
	_rearguard(f)
	_leaky_purse(f)
	_understudies(f)
	_slow_door(f)
	_crowded_dais(f)
	return f


# ---- helpers -------------------------------------------------------------------------------

func _build(votes: Dictionary, curses: Dictionary, kit: String = "dasher"):
	var world = WorldScript.new()
	var ledger := {
		"class": kit, "votes": votes, "curses": curses, "stacks": {},
		"purse": 0, "tithes": 0, "hunger": 0, "last_vote": "",
	}
	if not world.build(SEED, LEVEL, ledger):
		world.free()
		return null
	return world


func _drop(world) -> void:
	if world != null:
		world.teardown()
		world.free()


func _steps(world, n: int) -> void:
	for _i in n:
		world.step(DT)


func _count_id(world, id: String) -> int:
	var n := 0
	for e in world.rt.enemies:
		if str(e.get("id", "")) == id:
			n += 1
	return n


func _first_row(world, id: String) -> Dictionary:
	for e in world.rt.enemies:
		if str(e.get("id", "")) == id:
			return e
	return {}


## Park the player on a real floor tile 6-12 u off the beacon (so it is never entered by
## accident - the level's spawn tile touches the beacon here) that carries no gift/mine
## slot, open the beacon through its own API and run the one step that takes the open edge.
func _open_beacon_away(world) -> void:
	var b = world.lstate.beacon
	var taken := {}
	for s in world.lstate.mines.slots:
		taken["%d,%d" % [int(s["x"]), int(s["z"])]] = true
	for t in world.lv["tiles"]:
		var dx := float(t[0]) + 0.5 - float(b.cx)
		var dz := float(t[1]) + 0.5 - float(b.cz)
		var d := sqrt(dx * dx + dz * dz)
		if d < 6.0 or d > 12.0 or taken.has("%d,%d" % [int(t[0]), int(t[1])]):
			continue
		world.ctl.x = float(t[0]) + 0.5
		world.ctl.y = float(t[2]) * 0.5
		world.ctl.z = float(t[1]) + 0.5
		world.ctl.vx = 0.0
		world.ctl.vy = 0.0
		world.ctl.vz = 0.0
		world.ctl.cur_key = "%d,%d,%d" % [int(t[0]), int(t[1]), int(t[2])]
		break
	b.open(int(world.lstate.tick))
	world.step(DT)


func _check(f: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		f.append(msg)


# ---- on_level_start ------------------------------------------------------------------------

## early_bird: the runtime's spawn delay is 120 ticks instead of 360, so after 200 ticks the
## voted coil is already on the level when cursed and still absent when not.
func _early_bird(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"early_bird": 1} if held else {}
		var world = _build({"coil": 1}, curses)
		if world == null:
			f.append("early_bird: build failed (held=%s)" % str(held))
			continue
		var delay := int(world.rt.spawn_delay_ticks)
		_steps(world, 200)
		var bodies := int(world.rt.enemies.size())
		if held:
			_check(f, delay == 120, "early_bird held: spawn delay %d, want 120" % delay)
			_check(f, bodies == 1, "early_bird held: %d bodies at tick 200, want 1 (spawned at 2 s)" % bodies)
		else:
			_check(f, delay == 360, "early_bird control: spawn delay %d, want 360" % delay)
			_check(f, bodies == 0, "early_bird control: %d bodies at tick 200, want 0 (6 s delay)" % bodies)
		_drop(world)


## cold_start: the dasher starts the level with its dash on cooldown and a x1.25 regen.
func _cold_start(f: Array[String]) -> void:
	var base_regen := -1.0
	for held in [false, true]:
		var curses := {"cold_start": 1} if held else {}
		var world = _build({}, curses, "dasher")
		if world == null:
			f.append("cold_start: build failed (held=%s)" % str(held))
			continue
		var ready := bool(world.ctl.dash_ready)
		var regen := float(world.ctl.C["dash_regen"])
		if held:
			_check(f, not ready, "cold_start held: dash_ready true at level start, want false")
			_check(f, is_equal_approx(regen, base_regen * 1.25),
					"cold_start held: dash_regen %.4f, want %.4f (x1.25)" % [regen, base_regen * 1.25])
		else:
			base_regen = regen
			_check(f, ready, "cold_start control: dash_ready false at level start, want true")
			_check(f, regen > 0.0, "cold_start control: dash_regen %.4f, want > 0" % regen)
		_drop(world)


# ---- on_tick -------------------------------------------------------------------------------

## overwound: the live coil row's idle time is 2.0 s while the curse is held (3.0 s base).
func _overwound(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"overwound": 1} if held else {}
		var world = _build({"coil": 1}, curses)
		if world == null:
			f.append("overwound: build failed (held=%s)" % str(held))
			continue
		_steps(world, 420)
		var row := _first_row(world, "coil")
		if row.is_empty():
			f.append("overwound: no coil on the level after 420 ticks (held=%s)" % str(held))
			_drop(world)
			continue
		var idle := float((row.get("cfg", {}) as Dictionary).get("idle_s", 3.0))
		if held:
			_check(f, is_equal_approx(idle, 2.0), "overwound held: coil idle_s %.2f, want 2.0" % idle)
		else:
			_check(f, is_equal_approx(idle, 3.0), "overwound control: coil idle_s %.2f, want 3.0" % idle)
		_drop(world)


## litter: one real kitten body (a cat row at 60% size) follows the voted cat. Exactly one -
## the kitten is never served a kitten of its own (the dispatcher's spawn budget).
func _litter(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"litter": 1} if held else {}
		var world = _build({"kiwi_cat": 1}, curses)
		if world == null:
			f.append("litter: build failed (held=%s)" % str(held))
			continue
		_steps(world, 600)
		var cats := _count_id(world, "kiwi_cat")
		var want := 2 if held else 1
		_check(f, cats == want, "litter %s: %d cat bodies after 600 ticks, want %d"
				% ["held" if held else "control", cats, want])
		if held and cats >= 2:
			var h0 := float(world.rt.enemies[0].get("height_u", 0.0))
			var d1 := float(world.rt.enemies[1].get("diameter_u", 0.0))
			var d0 := float(world.rt.enemies[0].get("diameter_u", 0.0))
			_check(f, d1 < d0 and h0 > 0.0,
					"litter held: kitten diameter %.3f not smaller than the cat's %.3f" % [d1, d0])
		_drop(world)


## pup_pack: every seal gets one real second seal body.
func _pup_pack(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"pup_pack": 1} if held else {}
		var world = _build({"seal": 1}, curses)
		if world == null:
			f.append("pup_pack: build failed (held=%s)" % str(held))
			continue
		_steps(world, 600)
		var seals := _count_id(world, "seal")
		var want := 2 if held else 1
		_check(f, seals == want, "pup_pack %s: %d seal bodies after 600 ticks, want %d"
				% ["held" if held else "control", seals, want])
		_drop(world)


## crescendo: claude's agitation rises 3/s instead of 2/s - after the same ticks the cursed
## row holds 1/s x elapsed more (clamped at 100, so the window stays short of the clamp).
func _crescendo(f: Array[String]) -> void:
	var agi := [0.0, 0.0]
	for k in 2:
		var held := k == 1
		var curses := {"crescendo": 1} if held else {}
		var world = _build({"claude": 1}, curses)
		if world == null:
			f.append("crescendo: build failed (held=%s)" % str(held))
			continue
		_steps(world, 420)
		var row := _first_row(world, "claude")
		if row.is_empty():
			f.append("crescendo: no claude on the level after 420 ticks (held=%s)" % str(held))
		else:
			agi[k] = float(row.get("agitation", 0.0))
		_drop(world)
	_check(f, agi[1] > agi[0] + 0.5,
			"crescendo: agitation held %.3f vs control %.3f, want held higher by ~1/s" % [agi[1], agi[0]])


# ---- on_beacon_open ------------------------------------------------------------------------

## curfew: 60 s (3600 ticks) after the beacon opens, the economy's overtime jumps +2 tiers.
## Base overtime is one tier per 20 s, so 3610 ticks after the open the control holds 3 and
## the cursed run 5.
func _curfew(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"curfew": 1} if held else {}
		var world = _build({}, curses)
		if world == null:
			f.append("curfew: build failed (held=%s)" % str(held))
			continue
		_open_beacon_away(world)
		_steps(world, 3610)
		var gold := bool(world._economy.gold_phase)
		var tier := int(world._economy.overtime_tier)
		var want := 5 if held else 3
		_check(f, gold, "curfew (held=%s): the gold phase ended early - the probe is invalid" % str(held))
		_check(f, tier == want, "curfew %s: overtime tier %d at open + 3610 ticks, want %d"
				% ["held" if held else "control", tier, want])
		_drop(world)


## rearguard: when the beacon opens, one extra copy of an in-play enemy spawns AT the beacon.
func _rearguard(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"rearguard": 1} if held else {}
		var world = _build({"coil": 1}, curses)
		if world == null:
			f.append("rearguard: build failed (held=%s)" % str(held))
			continue
		_steps(world, 400)   # the voted coil is on the level
		var before := int(world.rt.enemies.size())
		_open_beacon_away(world)
		_steps(world, 2)
		var after := int(world.rt.enemies.size())
		_check(f, before == 1, "rearguard (held=%s): %d bodies before the open, want 1" % [str(held), before])
		var want := before + 1 if held else before
		_check(f, after == want, "rearguard %s: %d bodies after the open, want %d"
				% ["held" if held else "control", after, want])
		if held and after == before + 1:
			var row: Dictionary = world.rt.enemies[after - 1]
			var dx := float(row["x"]) - float(world.lstate.beacon.cx)
			var dz := float(row["z"]) - float(world.lstate.beacon.cz)
			_check(f, dx * dx + dz * dz < 4.0,
					"rearguard held: the extra body spawned %.1f u from the beacon, want at it"
					% sqrt(dx * dx + dz * dz))
		_drop(world)


# ---- on_void_fall --------------------------------------------------------------------------

## leaky_purse: a void fall drops 5% of the gold earned this level (cap 20 g). 100 g are
## earned after level start, then the player falls: the cursed purse loses 5 g.
func _leaky_purse(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"leaky_purse": 1} if held else {}
		var world = _build({}, curses)
		if world == null:
			f.append("leaky_purse: build failed (held=%s)" % str(held))
			continue
		world._economy.add_gold(100)   # earned during the level (after on_level_start)
		var before := int(world._economy.purse_centi)
		world.ctl.y = -100.0           # past kill_plane_y: the fall happens on this tick
		world.step(DT)
		var after := int(world._economy.purse_centi)
		var want := before - 500 if held else before
		_check(f, before == 10000, "leaky_purse (held=%s): purse %d before the fall, want 10000"
				% [str(held), before])
		_check(f, after == want, "leaky_purse %s: purse %d centi after the fall, want %d"
				% ["held" if held else "control", after, want])
		_drop(world)


# ---- the build-time / live queries ---------------------------------------------------------

## understudies: +4 flat extra mines per stack reach voidgen's extra_mines argument.
func _understudies(f: Array[String]) -> void:
	var counts := [0, 0]
	for k in 2:
		var held := k == 1
		var curses := {"understudies": 1} if held else {}
		var world = _build({}, curses)
		if world == null:
			f.append("understudies: build failed (held=%s)" % str(held))
			continue
		var extra := int(world.lv.get("extra_mines", -1))
		var want := 4 if held else 0
		_check(f, extra == want, "understudies %s: voidgen extra_mines %d, want %d"
				% ["held" if held else "control", extra, want])
		counts[k] = int(world.lstate.mines.ids.size())
		_drop(world)
	_check(f, counts[1] > counts[0],
			"understudies: %d mines held vs %d control, want more when held" % [counts[1], counts[0]])


## Stand the player on the beacon (test_app_loop.gd's own placement), once per call.
func _stand_in_beacon(world) -> void:
	var bp: Array = world.lv["beacon"]
	world.ctl.x = float(int(bp[0])) + 0.5
	world.ctl.y = float(int(bp[2])) * 0.5
	world.ctl.z = float(int(bp[1])) + 0.5
	world.ctl.vx = 0.0
	world.ctl.vy = 0.0
	world.ctl.vz = 0.0


## Open the beacon with the player standing in it; step until complete or `limit` ticks.
## Returns the ticks it took (limit + 1 = never).
func _ticks_to_enter(world, limit: int) -> int:
	for t in range(1, limit + 1):
		world.step(DT)
		if bool(world.lstate.beacon.completed):
			return t
		if bool(world.ctl.dead):
			return limit + 1
	return limit + 1


## slow_door: entering takes 3.0 s (180 ticks) of standing in the open beacon. The control
## enters on the first tick; the cursed run is refused for the dwell, then enters.
func _slow_door(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"slow_door": 1} if held else {}
		var world = _build({}, curses)
		if world == null:
			f.append("slow_door: build failed (held=%s)" % str(held))
			continue
		_stand_in_beacon(world)
		world.lstate.beacon.open(int(world.lstate.tick))
		var t := _ticks_to_enter(world, 400)
		if held:
			_check(f, t >= 180 and t <= 190,
					"slow_door held: entered after %d ticks, want ~181 (3.0 s dwell)" % t)
		else:
			_check(f, t <= 2, "slow_door control: entered after %d ticks, want 1" % t)
		_drop(world)


## crowded_dais: the beacon cannot be entered while any enemy is within 8 u of it. A
## stationary non-killing fixture body stands 4 u off the beacon: the control enters at once,
## the cursed run is refused - and enters as soon as the body is moved 50 u away.
func _crowded_dais(f: Array[String]) -> void:
	const RtScript := preload("res://sim/enemy_runtime.gd")
	for held in [false, true]:
		var curses := {"crowded_dais": 1} if held else {}
		var world = _build({}, curses)
		if world == null:
			f.append("crowded_dais: build failed (held=%s)" % str(held))
			continue
		var b = world.lstate.beacon
		var body: Dictionary = world.rt.spawn_at("fixture", "fixture", RtScript.FixtureBehavior.new(),
				{"contact_kill": false}, Vector3(float(b.cx) + 4.0, float(b.base_y), float(b.cz)))
		_stand_in_beacon(world)
		b.open(int(world.lstate.tick))
		var t := _ticks_to_enter(world, 60)
		if held:
			_check(f, t > 60, "crowded_dais held: entered after %d ticks with a body 4 u away" % t)
			body["x"] = float(b.cx) + 50.0
			_stand_in_beacon(world)
			var t2 := _ticks_to_enter(world, 10)
			_check(f, t2 <= 2, "crowded_dais held: body moved away, entered after %d ticks, want 1" % t2)
		else:
			_check(f, t <= 2, "crowded_dais control: entered after %d ticks, want 1" % t)
		_drop(world)
