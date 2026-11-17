extends RefCounted
#
# A6 (FLEET_PACK.md, ticket T-021): the tripmine.
#   - mine set = EXACTLY the Level.gifts occ == 1 slots (no other placement,
#     the hazard spawn rule - the generator rolled them in stream MINE);
#   - contact: the player's centre within 0.9 u HORIZONTAL of the box, at ANY
#     height (jumping over never avoids contact);
#   - the contact ladder in the fixed order (D-058): defuse roll -> Subspacial
#     Barrier shield -> Last Light -> death, the death carrying D-MINE;
#   - determinism: same seed + same slot id -> same outcome (1,000 seeds);
#   - the observed defuse rate at 1/2/3 stacks within +/-2 points of
#     20/40/60 % (D-051);
#   - kill tests run with Last Light ALREADY SPENT or otherwise moot (D-057):
#     a kill assertion is only valid when the save cannot fire.

const MinesScript := preload("res://sim/mines.gd")
const DeathScript := preload("res://sim/death.gd")
const BeaconScript := preload("res://sim/beacon.gd")
const ControllerScript := preload("res://sim/controller.gd")
const Util := preload("res://tests/sim_testutil.gd")

const TEST_LEVEL := 7


func run() -> Array[String]:
	var f: Array[String] = []
	_test_contact_geometry(f)
	_test_ladder(f)
	_test_blast(f)
	_test_determinism(f)
	_test_rates(f)
	_test_screen_data(f)
	_test_view(f)
	return f


# ---- fixtures -------------------------------------------------------------------

## A Level dict with a mixed slot table: occs[i] == 1 -> mine slot; else a real
## gift slot. Slot id i sits at world x = i * 10 + 0.5, z = 0.5, y = 0.
static func _level(occs: Array) -> Dictionary:
	var slots: Array = []
	for i in occs.size():
		slots.append({"id": i, "x": i * 10, "z": 0, "y": 0, "piece": 0, "tier": 0, "occ": occs[i]})
	return {"gifts": slots}


static func _ctl() -> RefCounted:
	var ctl = ControllerScript.new()
	ctl.setup("dasher", ControllerScript.load_constants())
	return ctl


## The minimal sim-context holder MinesScript.tick reads: the mine state, the
## player rows (kept in sync from the controllers) and the beacon (or null).
static func _holder(m: RefCounted, beacon: RefCounted, ctls: Array) -> Dictionary:
	var players: Array = []
	for c in ctls:
		if c == null:
			players.append({"x": 0.0, "y": 0.0, "z": 0.0})
		else:
			players.append({"x": float(c.x), "y": float(c.y), "z": float(c.z)})
	return {"mines": m, "players": players, "beacon": beacon}


## One mine-tick pass: builds the holder from ctls, steps, returns the events.
## The world carries the dais (Last Light branch) and an empty enemy list.
static func _tick(m: RefCounted, ctls: Array, stacks: Array, beacon: RefCounted = null,
		events: Array = []) -> Array:
	var holder := _holder(m, beacon, ctls)
	MinesScript.tick(holder, ctls, {"dais": [0, 0, 1], "enemies": []}, stacks, 7, events)
	return events


## A fresh controller standing on mine slot 0's tile centre at feet height h.
static func _ctl_at(height: float = 0.0) -> RefCounted:
	var ctl := _ctl()
	ctl.x = 0.5
	ctl.y = height
	ctl.z = 0.5
	return ctl


## The first seed whose slot-0 defuse roll at `stacks` stacks gives want.
static func _first_seed(want: bool, stacks: int = 3) -> int:
	for seed in range(1, 100000):
		if MinesScript.defuse_roll(seed, TEST_LEVEL, 0, stacks) == want:
			return seed
	return -1


static func _kind(ev: Array, k: String) -> int:
	var n := 0
	for e in ev:
		if str(e.get("type", e.get("e", ""))) == k:
			n += 1
	return n


# ---- contact geometry: the 0.9 u horizontal cylinder, any height ----------------

func _test_contact_geometry(f: Array[String]) -> void:
	# slot 0 = mine, slot 1 = a REAL gift slot (occ 0, never triggers anything)
	var m: RefCounted = MinesScript.create(_level([1, 0]), TEST_LEVEL, 11)
	# the tile centre triggers
	if m.contact_at(0.5, 0.5) != 0:
		f.append("contact: the mine tile centre did not trigger")
	# 0.89 u horizontally is inside; 0.91 u (the walk-lane margin of TERRAIN_SPEC
	# 6.8.1 is 1.0 u) is outside
	if m.contact_at(0.5 - 0.89, 0.5) != 0:
		f.append("contact: a 0.89 u offset should trigger (inside the 0.9 u cylinder)")
	if m.contact_at(0.5, 0.5 + 0.88) != 0:
		f.append("contact: a 0.88 u offset should trigger")
	if m.contact_at(0.5 - 0.91, 0.5) != -1:
		f.append("contact: a 0.91 u offset triggered (outside the 0.9 u cylinder)")
	if m.contact_at(0.5, 0.5 - 1.01) != -1:
		f.append("contact: a 1.01 u offset triggered")
	# the REAL gift slot never acts as a mine
	if m.contact_at(10.5, 0.5) != -1:
		f.append("contact: the occ == 0 slot triggered as a mine")
	# consumed mines stop triggering
	m.consume(0)
	if m.contact_at(0.5, 0.5) != -1:
		f.append("contact: a consumed mine still triggered")
	# any height: the trigger test has NO height term (dx^2 + dz^2 <= 0.81 only).
	# Prove it through the sim path: a controller at jump-apex height (2.25 u)
	# over the mine's xz triggers on the tick even though its feet never touch.
	var m2: RefCounted = MinesScript.create(_level([1]), TEST_LEVEL, 11)
	var ctl := _ctl_at(2.25)
	ctl.last_light_spent = true          # D-057: a kill test with the save moot
	ctl.charges = 0                      # and nothing to spend anyway
	var ev: Array = _tick(m2, [ctl], [0])
	if not bool(ctl.dead):
		f.append("contact: a player 2.25 u ABOVE the mine did not trigger contact at height")
	if m2.is_consumed(0):
		pass
	else:
		f.append("contact: the mine was not consumed by its contact")
	print("MINE contact: 0.9 u horizontal cylinder, any height, consumed = gone")


# ---- the blast: the blast kills what it reaches ---------------------------------

func _test_blast(f: Array[String]) -> void:
	# the contactor stands on the mine; a second player 2 u away is inside the
	# 3 u blast, a third 6 u away is not (D-T021-4: blast kills its radius).
	# every player has Last Light spent (D-057): a kill assertion is only valid
	# when the save cannot fire
	var m := MinesScript.create(_level([1]), TEST_LEVEL, 11)
	var a := _ctl_at(0.0)
	a.last_light_spent = true
	var b := _ctl_at(0.0)
	b.x = 0.5 + 2.0
	b.last_light_spent = true
	var c := _ctl_at(0.0)
	c.x = 0.5 + 6.0
	c.last_light_spent = true
	var holder := _holder(m, null, [a, b, c])
	MinesScript.tick(holder, [a, b, c], {"dais": [0, 0, 1], "enemies": []}, [0, 0, 0], 7, [])
	if not bool(a.dead) or not bool(b.dead) or bool(c.dead):
		f.append("blast: victims pattern wrong (a=%s b=%s c=%s die)" % [
			str(bool(a.dead)), str(bool(b.dead)), str(bool(c.dead))])
	# the two deaths are the same code, attributed through the killer ladder
	if str(a.dead_code) != "D-MINE" or str(b.dead_code) != "D-MINE":
		f.append("blast: a blast victim did not die D-MINE")


# ---- determinism: same seed + same slot id -> same outcome ----------------------

## One resolved outcome signature for the given mines state: the defuse flag,
## consumed state and death - pure functions of (seed, level, slot, stacks).
## Last Light is pre-spent so a non-defusing seed resolves to death (D-057).
static func _outcome(m: RefCounted, stacks: int) -> Array:
	var ctl := _ctl_at(0.0)
	ctl.last_light_spent = true
	_tick(m, [ctl], [stacks], null)
	var kinds: Array = []
	if m.is_consumed(0):
		kinds.append("consumed")
	if bool(ctl.dead):
		kinds.append("dead")
	return kinds


func _test_determinism(f: Array[String]) -> void:
	var saw_defuse := false
	var saw_death := false
	for seed in range(1000):
		var a: bool = MinesScript.defuse_roll(seed, TEST_LEVEL, 3, 1)
		var b: bool = MinesScript.defuse_roll(seed, TEST_LEVEL, 3, 1)
		if a != b:
			f.append("determinism: roll differs between identical calls (seed %d)" % seed)
		var r1: Array = _outcome(MinesScript.create(_level([1]), TEST_LEVEL, seed), 1)
		var r2: Array = _outcome(MinesScript.create(_level([1]), TEST_LEVEL, seed), 1)
		if r1 != r2:
			f.append("determinism: resolve differs between identical seeds (seed %d)" % seed)
			break
		if r1.is_empty() or str(r1[0]) != "consumed":
			f.append("determinism: seed %d resolved to an unexpected shape %s" % [seed, str(r1)])
			break
		# a consumed mine with no death is the defuse outcome; with death the
		# roll failed and the whole ladder ran - both must be stable per seed
		if r1.size() == 1:
			saw_defuse = true
		elif r1.size() == 2 and str(r1[1]) == "dead":
			saw_death = true
		else:
			f.append("determinism: seed %d resolved to an odd shape %s" % [seed, str(r1)])
			break
	if not saw_defuse or not saw_death:
		f.append("determinism: the 1,000 seeds saw only one outcome kind")
	print("MINE determinism: 1000 seeds, same seed -> same outcome")


# ---- the defuse rates: 20 / 40 / 60 % at 1 / 2 / 3 stacks -----------------------

func _test_rates(f: Array[String]) -> void:
	for stacks in [1, 2, 3]:
		var hit := 0
		var total := 0
		for seed in range(300):
			for slot in range(10):
				total += 1
				if MinesScript.defuse_roll(seed, TEST_LEVEL, slot, stacks):
					hit += 1
		var rate := float(hit) / float(total)
		var expect := float(stacks) * 0.2
		if absf(rate - expect) > 0.02:
			f.append("rates: %d stacks gave %.4f, want %.2f +/-0.02 (%d/%d)"
					% [stacks, rate, expect, hit, total])
	# the cap: 4+ stacks behave like 3 (60 %, never more)
	var hit4 := 0
	var total4 := 0
	for seed in range(300):
		for slot in range(10):
			total4 += 1
			if MinesScript.defuse_roll(seed, TEST_LEVEL, slot, 4):
				hit4 += 1
	var rate4 := float(hit4) / float(total4)
	if absf(rate4 - 0.6) > 0.02:
		f.append("rates: the 60%% cap is broken at 4 stacks (%.4f)" % rate4)
	print("MINE defuse rates: 20/40/60%% at 1/2/3 stacks within +/-2 points")


# ---- death attribution + run-over screen data ------------------------------------

func _test_screen_data(f: Array[String]) -> void:
	# the D-MINE death walks out of the ladder's step 4 (no shield, and the
	# fixture player's Last Light is already spent, D-057)
	var m := MinesScript.create(_level([1]), TEST_LEVEL, 11)
	var ctl := _ctl_at(0.0)
	ctl.last_light_spent = true
	_tick(m, [ctl], [0], null)
	if not bool(ctl.dead) or str(ctl.dead_code) != "D-MINE":
		f.append("screen: the fixture death is not D-MINE")
	var scr: Dictionary = DeathScript.screen_data(ctl, 4, 33)
	if str(scr.get("code", "")) != "D-MINE":
		f.append("screen: the screen row carries %s, want D-MINE" % str(scr.get("code", "")))
	if str(scr.get("killer", "")) != "gift Larper (Tripmine)":
		f.append("screen: the killer is '%s', want the roster name" % str(scr.get("killer", "")))
	if int(scr.get("level", -1)) != 4 or int(scr.get("purse", -1)) != 33:
		f.append("screen: the screen row lost level/purse (%s)" % str(scr))
	# the closed code map: a void fall is its own killer (D-VOID); thicc ben has none
	if DeathScript.killer_for("D-VOID") != "the void":
		f.append("screen: D-VOID is not its own killer name")
	if DeathScript.killer_for("D-MINE") != "gift Larper (Tripmine)":
		f.append("screen: D-MINE killer name drift")
	if DeathScript.killer_for("D-CURSE:hungry_void") != "curse hungry_void":
		f.append("screen: the curse code form drifted")
	if DeathScript.CODES.has("D-BEN"):
		f.append("screen: thicc ben grew a death code")
	# an alive controller attributes nothing
	var alive := _ctl()
	if not DeathScript.attribute(alive).is_empty():
		f.append("screen: an alive controller was attributed a death")


# ---- the view loads and syncs ----------------------------------------------------

func _test_view(f: Array[String]) -> void:
	var m := MinesScript.create(_level([1]), TEST_LEVEL, 11)
	var script = load("res://view/tripmine_view.gd")
	if script == null:
		f.append("view: tripmine_view.gd failed to load")
		return
	var v = script.new()
	v.setup(_level([1]), m)
	v.set_time(1.0)
	v.sync()
	# the tell: inside the 12 u radius the particles + star show; beyond it the
	# mine reads as a plain gift (the rim glow only)
	if not v.tell_visible(11.9) or v.tell_visible(12.1):
		f.append("view: the tell distance boundary drifted (want visible <= 12 u)")
	v.free()
	print("MINE view: tells at 12 u, box synced")


# ---- the ladder: defuse roll -> barrier -> Last Light -> death ------------------

func _test_ladder(f: Array[String]) -> void:
	var seed_pass := _first_seed(true, 3)
	var seed_fail := _first_seed(false, 3)
	if seed_pass < 0 or seed_fail < 0:
		f.append("ladder: no seed found with a passing/failing slot-0 defuse roll")
		return

	# 1. DEFUSE: roll passes -> mine consumed, no blast, no death; the shield
	#    and Last Light are untouched (the order contract, D-058).
	var m1 := MinesScript.create(_level([1]), TEST_LEVEL, seed_pass)
	var beacon1 := BeaconScript.create({"beacon": [10, 0, 1]})
	beacon1.barriers[0] = true
	var ctl1 := _ctl_at(0.0)
	var ev1: Array = _tick(m1, [ctl1], [3], beacon1)
	if not m1.is_consumed(0):
		f.append("ladder: a defused mine was not consumed")
	if _kind(ev1, "mine_defused") != 1:
		f.append("ladder: no mine_defused event on the defuse path")
	if _kind(ev1, "mine_detonated") != 0:
		f.append("ladder: a defused mine detonated")
	if not bool(beacon1.has_barrier(0)):
		f.append("ladder: the defuse path consumed the Subspacial Barrier")
	if bool(ctl1.last_light_spent):
		f.append("ladder: the defuse path spent Last Light")
	if _kind(ev1, "chain_reset") != 1:
		f.append("ladder: the defuse did not reset the chain")
	# 0 stacks never defuses, whatever the roll value is
	for s in range(6):
		if MinesScript.defuse_roll(1234, TEST_LEVEL, s, 0):
			f.append("ladder: a 0-stack roll defused")

	# 2. SHIELD: roll fails -> the Subspacial Barrier absorbs it; mine consumed,
	#    no death, chain resets; Last Light stays unspent.
	var m2 := MinesScript.create(_level([1]), TEST_LEVEL, seed_fail)
	var beacon2 := BeaconScript.create({"beacon": [10, 0, 1]})
	beacon2.barriers[0] = true
	var ctl2 := _ctl_at(0.0)
	var ev2: Array = _tick(m2, [ctl2], [0], beacon2)
	if bool(ctl2.dead) or bool(beacon2.has_barrier(0)):
		f.append("ladder: the shield path did not shield (dead=%s)" % str(bool(ctl2.dead)))
	if not m2.is_consumed(0):
		f.append("ladder: the shield path left the mine armed")
	if _kind(ev2, "mine_shielded") != 1:
		f.append("ladder: the shield path event count is wrong")
	if bool(ctl2.last_light_spent):
		f.append("ladder: the shield path spent Last Light")
	if _kind(ev2, "chain_reset") != 1:
		f.append("ladder: the shield path did not reset the chain")

	# 3. NO SHIELD: the Last Light save fires (charges held), the mine is
	#    consumed, nobody dies.
	var m3 := MinesScript.create(_level([1]), TEST_LEVEL, seed_fail)
	var ctl3 := _ctl_at(0.0)
	ctl3.charges = 2
	var ev3: Array = _tick(m3, [ctl3], [0], null)
	if not m3.is_consumed(0):
		f.append("ladder: the save path left the mine armed")
	if bool(ctl3.dead) or not bool(ctl3.last_light_spent):
		f.append("ladder: the Last Light save did not fire (dead=%s)" % str(bool(ctl3.dead)))

	# 4. DEATH: no shield, save spent (D-057) -> D-MINE, exactly one death.
	var m4 := MinesScript.create(_level([1]), TEST_LEVEL, seed_fail)
	var ctl4 := _ctl_at(0.0)
	ctl4.last_light_spent = true
	var ev4: Array = _tick(m4, [ctl4], [0], null)
	if bool(ctl4.dead) != true:
		f.append("ladder: a mined player survived (no shield, save spent)")
	if _kind(ev4, "mine_detonated") != 1:
		f.append("ladder: the death path did not detonate")
	if str(ctl4.dead_code) != "D-MINE":
		f.append("ladder: the death code is %s, want D-MINE" % str(ctl4.dead_code))
	# an invulnerable player triggers nothing (no consume, no death)
	var m5 := MinesScript.create(_level([1]), TEST_LEVEL, seed_fail)
	var ctl5 := _ctl_at(0.0)
	ctl5.invuln = 1.0
	_tick(m5, [ctl5], [0], null)
	if bool(ctl5.dead) or m5.is_consumed(0):
		f.append("ladder: an invulnerable player consumed a mine or died")

