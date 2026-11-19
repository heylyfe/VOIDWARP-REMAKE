extends RefCounted
#
# UPGRADE HOOKS test (headless) - W13-A: sim/upgrade_runtime.gd, the upgrade hook
# dispatcher, and the LevelState upgrade roles, proven through world.build() +
# world.step() (the shipped path), never through a module unit call alone.
#
# Method: every leg states its claim as ONE expectation function that takes a world and
# returns the failures it finds. The function runs on the owned world (must return none)
# and then, UNCHANGED, on the control world - the same build minus the upgrade (must return
# at least one: the negative control). A leg whose expectation passes on the control world
# proves nothing, and fails this file. The total of control-side failures is printed as
#   NEGATIVE CONTROL failures=<n> legs=<m>
#
# Legs:
#   roles          lstate.upgrades non-null with the owned role; null in the control
#   skeleton_key   the role reaches the gifts: black_quota = ceil(90% of real black gifts)
#   nest_egg       beacon entry pays 5% of the carried purse (cap 30 g) per stack, on top
#                  of the stipend, through world.step()'s beacon-enter path (x1 and x2)
#   slipstream     a real gift pickup in world.step() boosts the controller's run speed
#                  x1.2 for exactly 120 controller steps, then it returns to the base
#   stand_fast     the first live-chain void fall in world.step() keeps the chain; the
#                  second resets it (once per level)
#   bounty_hunter  the curse altars a lobby draws from world.run_ledger() show and pay
#                  +50% bounty after UpgradeRuntime.curse_draw with the world's loader

const WorldScript := preload("res://app/world.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const UpgradeRuntimeScript := preload("res://sim/upgrade_runtime.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")

const SEED := 1
const LEVEL := 1
const DT := 1.0 / 60.0
const PURSE := 500

var _neg := 0     # control-side failures (the negative-control count)
var _legs := 0    # legs that ran a control


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_roles(f)
	_leg_skeleton_key(f)
	_leg_nest_egg(f)
	_leg_slipstream(f)
	_leg_stand_fast(f)
	_leg_bounty_hunter(f)
	print("NEGATIVE CONTROL failures=%d legs=%d" % [_neg, _legs])
	return f


# ---- shared helpers ------------------------------------------------------------------------

func _build(stacks: Dictionary, p_class: String = "dasher"):
	var world = WorldScript.new()
	var ledger := {
		"class": p_class, "votes": {}, "curses": {}, "stacks": stacks.duplicate(),
		"purse": PURSE, "tithes": 0, "hunger": 0, "last_vote": "",
	}
	if not world.build(SEED, LEVEL, ledger):
		world.free()
		return null
	return world


func _drop(world) -> void:
	if world != null:
		world.teardown()
		world.free()


## Runs `expect` (a Callable: world -> Array[String]) on the owned world, which must pass,
## and on the control world, which must FAIL. Every owned failure and a control pass are
## failures of this file; the control's own failure count feeds the negative-control total.
func _owned_vs_control(f: Array[String], leg: String, expect: Callable, owned, control) -> void:
	if owned == null or control == null:
		f.append("%s: a world failed to build" % leg)
		return
	var got: Array = expect.call(owned)
	for m in got:
		f.append("%s (owned): %s" % [leg, str(m)])
	var neg: Array = expect.call(control)
	_legs += 1
	_neg += neg.size()
	print("NEGATIVE CONTROL %s: %d control failure(s)%s" % [leg, neg.size(),
			(" - first: " + str(neg[0])) if not neg.is_empty() else ""])
	if neg.is_empty():
		f.append("%s: the expectation PASSED on the control world - it proves nothing" % leg)


## A real, uncollected gift slot, or -1.
func _a_gift_slot(world) -> int:
	var gifts = world.lstate.gifts
	for i in gifts.slots.size():
		if bool(gifts.is_real(i)) and not bool(gifts.collected(i)):
			return i
	return -1


## Puts the body on the open beacon's dais and steps once (the try_enter path).
func _enter_beacon(world) -> void:
	var b: RefCounted = world.lstate.beacon
	b.open(int(world.lstate.tick))
	world.ctl.x = float(b.cx)
	world.ctl.y = float(b.base_y)
	world.ctl.z = float(b.cz)
	world.ctl.grounded = true
	world.ctl.vy = 0.0
	world.step(DT)


## Drops the body below the kill plane and steps once (the controller's void-fall path).
func _void_fall(world) -> void:
	world.ctl.invuln = 0.0
	world.ctl.y = float(world.ctl.C["kill_plane_y"]) - 5.0
	world.ctl.vy = -10.0
	world.ctl.grounded = false
	world.step(DT)


## Parks the body on a real gift slot at least 4 u (horizontal) from the beacon axis and
## steps once so the controller settles there. False when no such slot exists.
func _park_away(world) -> bool:
	var g: RefCounted = world.lstate.gifts
	var b: RefCounted = world.lstate.beacon
	for i in g.slots.size():
		if not bool(g.is_real(i)) or bool(g.collected(i)):
			continue
		var pos: Vector3 = g.position_of(i)
		var dx := float(pos.x) - float(b.cx)
		var dz := float(pos.z) - float(b.cz)
		if dx * dx + dz * dz < 16.0:
			continue
		world.ctl.x = float(pos.x)
		world.ctl.y = float(pos.y) - 0.9
		world.ctl.z = float(pos.z)
		world.ctl.vx = 0.0
		world.ctl.vy = 0.0
		world.ctl.vz = 0.0
		world.ctl.grounded = true
		world.step(DT)
		return not bool(b.completed)
	return false


## Steps until the respawn finished (respawn_t back to -1), at most `cap` ticks.
func _until_respawned(world, cap: int = 240) -> void:
	for _i in range(cap):
		if float(world.ctl.respawn_t) < 0.0:
			return
		world.step(DT)


## Places the body on a real gift and steps until it is collected (at most 3 ticks).
## Returns true when the pickup went through world.step()'s gift path.
func _pickup_one(world) -> bool:
	var g: RefCounted = world.lstate.gifts
	var slot := _a_gift_slot(world)
	if slot < 0:
		return false
	var pos: Vector3 = g.position_of(slot)
	var before := int(g.remaining())
	world.ctl.x = float(pos.x)
	world.ctl.y = float(pos.y) - 0.9
	world.ctl.z = float(pos.z)
	world.ctl.vx = 0.0
	world.ctl.vy = 0.0
	world.ctl.vz = 0.0
	world.ctl.grounded = true
	for _i in range(3):
		world.step(DT)
		if int(g.remaining()) < before or bool(g.collected(slot)):
			return true
	return false


# ---- roles: the LevelState is built with the owned upgrades' roles ---------------------------

func _leg_roles(f: Array[String]) -> void:
	var owned = _build({"radar_mines": 1, "cartographer": 1, "radar_threats": 1})
	var control = _build({})
	var expect := func(w) -> Array:
		var out: Array = []
		var u: RefCounted = w.lstate.upgrades
		if u == null:
			out.append("lstate.upgrades is null")
			return out
		for role in ["mine_radar", "footprint_map", "threat_radar"]:
			if not bool(u.has(role)):
				out.append("role %s missing from lstate.upgrades" % role)
		return out
	_owned_vs_control(f, "roles", expect, owned, control)
	# Control canon, stated outright: an un-upgraded world keeps lstate.upgrades null.
	if control != null and control.lstate.upgrades != null:
		f.append("roles: the control world built a non-null lstate.upgrades")
	_drop(owned)
	_drop(control)


# ---- skeleton_key: the quota role reaches the gifts and the beacon opens at 90% ----------------

func _leg_skeleton_key(f: Array[String]) -> void:
	var owned = _build({"skeleton_key": 1})
	var control = _build({})
	var expect := func(w) -> Array:
		var out: Array = []
		var g: RefCounted = w.lstate.gifts
		var total := int(g.total_real)
		var quota := int(ceil(float(total) * 0.9))
		if total < 10:
			out.append("level has only %d real gifts - quota not distinguishable" % total)
			return out
		if int(g.black_quota) != quota:
			out.append("black_quota reads %d, want ceil(90%% of %d) = %d"
					% [int(g.black_quota), total, quota])
		# collect quota - 1 directly, the quota-th through world.step()'s pickup path
		var taken := 0
		for i in g.slots.size():
			if taken >= quota - 1:
				break
			if bool(g.is_real(i)) and not bool(g.collected(i)):
				g.collect(i, int(w.lstate.tick), 0, [])
				taken += 1
		if not _pickup_one(w):
			out.append("the quota-th gift did not collect through world.step()")
		if not bool(w.lstate.beacon.is_open()):
			out.append("the beacon is still shut with %d of %d real black gifts taken"
					% [quota, total])
		return out
	_owned_vs_control(f, "skeleton_key", expect, owned, control)
	_drop(owned)
	_drop(control)


# ---- nest_egg: beacon entry pays interest on the carried purse --------------------------------

func _nest_expect(w, stacks: int) -> Array:
	var out: Array = []
	var e: RefCounted = w._economy
	e.purse_centi = 50000
	_enter_beacon(w)
	if not bool(w.lstate.beacon.completed):
		out.append("the beacon was not entered")
		return out
	# stipend 10 + 2 x level = 12 g = 1200 centi; interest min(5% of 50000, 3000) per stack
	var want := 1200 + mini(50000 * 5 / 100, 3000) * stacks
	var got := int(e.purse_centi) - 50000
	if got != want:
		out.append("beacon entry paid %d centi, want %d (stipend 1200 + interest %d x %d)"
				% [got, want, mini(50000 * 5 / 100, 3000), stacks])
	return out


func _leg_nest_egg(f: Array[String]) -> void:
	for n in [1, 2]:
		var owned = _build({"nest_egg": n})
		var control = _build({})
		_owned_vs_control(f, "nest_egg x%d" % n, _nest_expect.bind(n), owned, control)
		# Control canon: the plain stipend and nothing else.
		if control != null and int(control._economy.purse_centi) != 50000 + 1200:
			f.append("nest_egg: the control world's entry paid %d centi, want the canon 1200"
					% (int(control._economy.purse_centi) - 50000))
		_drop(owned)
		_drop(control)


# ---- slipstream: a gift pickup boosts run speed x1.2 for 120 controller steps -----------------

func _leg_slipstream(f: Array[String]) -> void:
	var owned = _build({"slipstream": 1})
	var control = _build({})
	var expect := func(w) -> Array:
		var out: Array = []
		var base := float(w._stats_black.get("run_speed", 1.0))
		if not _pickup_one(w):
			out.append("no gift collected through world.step()")
			return out
		var g: RefCounted = w.lstate.gifts
		var rem := int(g.remaining())
		# the pickup tick's own controller step ran before the pickup; the boost covers
		# the next 120 controller steps exactly
		w.step(DT)
		if not is_equal_approx(float(w.ctl.run_speed_mul), base * 1.2):
			out.append("run_speed_mul after the pickup reads %.4f, want %.4f (x1.2)"
					% [float(w.ctl.run_speed_mul), base * 1.2])
		else:
			# the controller's own run speed reads the boosted multiplier
			var boosted := float(w.ctl.run_speed(w.w))
			w.ctl.run_speed_mul = base
			var plain := float(w.ctl.run_speed(w.w))
			w.ctl.run_speed_mul = base * 1.2
			if plain <= 0.0 or not is_equal_approx(boosted / plain, 1.2):
				out.append("controller run_speed %.4f vs %.4f is not x1.2" % [boosted, plain])
		for _i in range(119):
			w.step(DT)
		if int(g.remaining()) != rem:
			out.append("a second pickup landed inside the window; expiry not measurable")
			return out
		if not is_equal_approx(float(w.ctl.run_speed_mul), base * 1.2):
			out.append("the boost ended before 120 steps (run_speed_mul %.4f at step 120)"
					% float(w.ctl.run_speed_mul))
		w.step(DT)
		if not is_equal_approx(float(w.ctl.run_speed_mul), base):
			out.append("the boost outlived 120 steps (run_speed_mul %.4f at step 121, want %.4f)"
					% [float(w.ctl.run_speed_mul), base])
		return out
	_owned_vs_control(f, "slipstream", expect, owned, control)
	if control != null and not is_equal_approx(float(control.ctl.run_speed_mul),
			float(control._stats_black.get("run_speed", 1.0))):
		f.append("slipstream: the control world's run speed moved (%.4f)"
				% float(control.ctl.run_speed_mul))
	_drop(owned)
	_drop(control)


# ---- stand_fast: the first live-chain break per level keeps the chain -------------------------

func _leg_stand_fast(f: Array[String]) -> void:
	var owned = _build({"stand_fast": 1})
	var control = _build({})
	var expect := func(w) -> Array:
		var out: Array = []
		var e: RefCounted = w._economy
		# the gold phase through the world's own beacon-open edge. The level spawn sits
		# inside the beacon's trigger radius, so the body is parked on a gift slot away
		# from the dais first (else it enters the beacon on the open tick).
		if not _park_away(w):
			out.append("no gift slot far enough from the dais to park on")
			return out
		w.lstate.beacon.open(int(w.lstate.tick))
		w.step(DT)
		if not bool(e.gold_phase):
			out.append("the gold phase did not begin through world.step()")
			return out
		w.ctl.charges = 2
		e.collect_gold_gift()
		e.collect_gold_gift()
		var chain := int(e.chain_centi)
		var resets := int(e.chain_resets)
		_void_fall(w)
		if int(w.ctl.charges) != 1:
			out.append("the fall did not spend a charge (charges %d)" % int(w.ctl.charges))
		if int(e.chain_centi) != chain or int(e.chain_resets) != resets:
			out.append("the first void fall reset the chain (chain_centi %d -> %d)"
					% [chain, int(e.chain_centi)])
		# the save is spent: the second live-chain fall this level resets
		_until_respawned(w)
		e.collect_gold_gift()
		_void_fall(w)
		if int(e.chain_centi) != 100:
			out.append("the second void fall kept the chain (chain_centi %d, want 100)"
					% int(e.chain_centi))
		return out
	_owned_vs_control(f, "stand_fast", expect, owned, control)
	if control != null and int(control._economy.chain_centi) != 100:
		f.append("stand_fast: the control chain did not reset (chain_centi %d)"
				% int(control._economy.chain_centi))
	_drop(owned)
	_drop(control)


# ---- bounty_hunter: the curse bay a lobby draws from the world's ledger pays +50% -----------
#
# The curse draw is a LOBBY event (sim/intermission.gd), not a level one: the world's part
# is the ledger it hands the lobby (run_ledger) and the module loader. This leg builds the
# lobby with the same create() arguments view/lobby/lobby_scene.gd build() passes, at the
# first schedule level with a C bay, runs the dispatcher's on_curse_draw entry with the
# world's own loader, and picks an altar through the sim's select path.

const C_LOBBY := 2   # data/offering_schedule.json: lobby 2 lights a C bay

func _bounty_expect(w) -> Array:
	var out: Array = []
	var api: RefCounted = ContentApiScript.load()
	var ledger: Dictionary = w.run_ledger()
	var lb: RefCounted = IntermissionScript.create(api, C_LOBBY, int(ledger.get("purse", 0)),
			VoidRngScript.mix(SEED, 0x10B + C_LOBBY), ledger.get("votes", {}),
			ledger.get("curses", {}), ledger.get("stacks", {}), str(ledger.get("class", "")),
			int(ledger.get("tithes", 0)), int(ledger.get("hunger", 0)),
			str(ledger.get("last_vote", "")), ledger.get("stats", {}))
	var cbay: Dictionary = {}
	for bay in lb.bays:
		if str(bay.get("kind", "")) == "C":
			cbay = bay
	if cbay.is_empty():
		out.append("lobby %d has no C bay" % C_LOBBY)
		return out
	var raw: Array = []
	for a in cbay["altars"]:
		raw.append(int(a.get("bounty", 0)))
	UpgradeRuntimeScript.curse_draw(lb.bays, lb.upgrade_stacks,
			Callable(w, "_upgrade_module"), C_LOBBY)
	# a repeat call must not compound (the lobby asks again after every select)
	UpgradeRuntimeScript.curse_draw(lb.bays, lb.upgrade_stacks,
			Callable(w, "_upgrade_module"), C_LOBBY)
	var altars: Array = cbay["altars"]
	for i in altars.size():
		var want := int(floor(float(raw[i]) * 1.5))
		if int(raw[i]) <= 0:
			out.append("altar %d drew no bounty" % i)
		elif int(altars[i].get("bounty", 0)) != want:
			out.append("altar %d shows bounty %d, want floor(%d x 1.5) = %d"
					% [i, int(altars[i].get("bounty", 0)), int(raw[i]), want])
	# pick the first curse altar through the sim's own select path: the purse gains it
	var table: Array = lb.altar_table()
	var pick := -1
	for i in table.size():
		var t: Dictionary = table[i]
		if str(t.get("bay", "")) == "C" and str(t.get("kind", "")) == "offer" 				and int(t.get("altar", -1)) == 0:
			pick = i
			break
	if pick < 0:
		out.append("the altar table has no C offer")
		return out
	var before := int(lb.purse)
	var ev: Array = []
	if not bool(lb.apply_select(0, pick, ev)):
		out.append("the curse pick was refused (table index %d)" % pick)
		return out
	var paid := int(lb.purse) - before
	if paid != int(floor(float(raw[0]) * 1.5)):
		out.append("the pick paid %d g, want floor(%d x 1.5) = %d"
				% [paid, int(raw[0]), int(floor(float(raw[0]) * 1.5))])
	return out


func _leg_bounty_hunter(f: Array[String]) -> void:
	var owned = _build({"bounty_hunter": 1})
	var control = _build({})
	_owned_vs_control(f, "bounty_hunter", Callable(self, "_bounty_expect"), owned, control)
	_drop(owned)
	_drop(control)
