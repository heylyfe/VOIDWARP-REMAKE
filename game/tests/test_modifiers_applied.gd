extends RefCounted
#
# MODIFIERS-APPLIED test (headless): the run's owned upgrade stacks and held curses reach
# the live run.
#
# core/content_api.gd's apply_modifiers() is already covered on its own (test_content.gd,
# test_curses_decl.gd, test_upgrades_decl.gd, test_dropin.gd). What was missing is the
# SHIPPED path: nothing under app/ or sim/ called it, so 36 upgrades and 46 curses shipped
# with modifier data and changed nothing. This file proves game/app/world.gd's build()
# feeds the run's ledgers through it, and that the economy and the controller it creates
# then behave differently.
#
# Every case builds a real level through world.build() with a CARRIED ledger (the app's own
# lobby handover shape), so no lobby replay is involved and the only variable is the stacks
# / curses dict. Nothing here calls apply_modifiers directly.
#
# The negative control is the same build with both dicts empty: every measured number must
# equal its canon base, so no case below can pass by accident.
#
# Measured through behaviour, not by reading the wiring: the economy pays a real gold gift,
# a real stipend, a real chain window and real overtime tiers, and the controller runs real
# 60 Hz ticks and reports its own speed, respawn wait, invulnerability and charge cap.

const WorldScript := preload("res://app/world.gd")
const CollisionScript := preload("res://sim/collision.gd")
const Util := preload("res://tests/sim_testutil.gd")

const SEED := 1
const LEVEL := 1
const DT := 1.0 / 60.0

# The canon bases (DESIGN.md sections 3.1 / 3.2 / 8, core/stats.gd DEFAULTS) the negative
# control asserts against, as literals: a drifted base fails here, not silently.
const BASE_GIFT_CENTI := 200        # gold gift base value 2.00 g
const BASE_WINDOW_S := 4.0          # chain window
const BASE_CAP := 2.0               # chain cap x2.00
const BASE_OVERTIME_S := 20.0       # one overtime tier per 20 s
const BASE_STIPEND_CENTI := 1200    # 10 + 2 x level 1, in centi-gold
const BASE_RUN_SPEED := 9.0         # data/player.json shared_kit.run_speed
const BASE_RESPAWN_DELAY_S := 0.8   # void-fall respawn wait
const BASE_RESPAWN_INVULN_S := 1.0  # post-respawn invulnerability
const BASE_CHARGE_CAP := 2          # 2 held, cap 2
const BASE_GLITCH_SLOW := 0.8       # D-075: the glitched floor's -20%

# The respawn wait is counted in whole 60 Hz ticks, so a float residue can cost one tick.
const TICK_TOLERANCE := 2


func run() -> Array[String]:
	var f: Array[String] = []
	_negative_control(f)
	_upgrades(f)
	_curses(f)
	return f


# ---- the negative control: no upgrades, no curses -> the canon base, everywhere ---------

func _negative_control(f: Array[String]) -> void:
	var world = _build({}, {})
	if world == null:
		f.append("negative control: world.build failed")
		return
	var payout := _gift_payout(world)
	_check(f, payout == BASE_GIFT_CENTI,
		"negative control: a gold gift paid %d centi, want the canon base %d"
				% [payout, BASE_GIFT_CENTI])
	_check(f, _chain_survives(world, BASE_WINDOW_S - 0.5),
		"negative control: the chain did not survive a %.1f s gap inside the %.1f s window"
				% [BASE_WINDOW_S - 0.5, BASE_WINDOW_S])
	_check(f, not _chain_survives(world, BASE_WINDOW_S + 0.5),
		"negative control: the chain survived a %.1f s gap past the %.1f s window"
				% [BASE_WINDOW_S + 0.5, BASE_WINDOW_S])
	var cap := _chain_cap(world)
	_check(f, absf(cap - BASE_CAP) <= 1e-9,
		"negative control: the chain capped at x%.4f, want x%.2f" % [cap, BASE_CAP])
	var tiers := _overtime_tiers(world, BASE_OVERTIME_S + 1.0)
	_check(f, tiers == 1,
		"negative control: %.1f s of gold phase gave %d overtime tiers, want 1"
				% [BASE_OVERTIME_S + 1.0, tiers])
	var stipend := _stipend_centi(world)
	_check(f, stipend == BASE_STIPEND_CENTI,
		"negative control: beacon entry paid %d centi, want the canon base %d"
				% [stipend, BASE_STIPEND_CENTI])

	var speed := _measured_speed(world)
	_check(f, absf(speed - BASE_RUN_SPEED) <= 0.05,
		"negative control: run speed %.4f, want the canon base %.2f" % [speed, BASE_RUN_SPEED])
	var glitched := _glitched_speed(world)
	_check(f, absf(glitched - BASE_RUN_SPEED * BASE_GLITCH_SLOW) <= 0.05,
		"negative control: glitched-floor speed %.4f, want %.2f (%.2f x %.2f)"
				% [glitched, BASE_RUN_SPEED * BASE_GLITCH_SLOW, BASE_RUN_SPEED,
						BASE_GLITCH_SLOW])
	var ticks := _respawn_ticks(world)
	_check(f, absi(ticks - _ticks_for(BASE_RESPAWN_DELAY_S)) <= TICK_TOLERANCE,
		"negative control: the void-fall respawn took %d ticks, want %d (%.2f s)"
				% [ticks, _ticks_for(BASE_RESPAWN_DELAY_S), BASE_RESPAWN_DELAY_S])
	var invuln := _respawn_invuln(world)
	_check(f, absf(invuln - BASE_RESPAWN_INVULN_S) <= 1e-9,
		"negative control: respawn invulnerability %.4f s, want %.2f s"
				% [invuln, BASE_RESPAWN_INVULN_S])
	_check(f, int(world.ctl.charge_cap) == BASE_CHARGE_CAP,
		"negative control: charge cap %d, want %d" % [int(world.ctl.charge_cap),
				BASE_CHARGE_CAP])
	# the gold-phase edge itself: with no `when: gold_phase` modifier the speed is unchanged
	var before := _measured_speed(world)
	_check(f, _open_gold_phase(world),
		"negative control: the gold phase did not start, so the phase edge is unproven")
	var during := _measured_speed(world)
	_check(f, absf(during - before) <= 1e-9,
		"negative control: the gold phase changed run speed %.4f -> %.4f with no curse held"
				% [before, during])
	_drop(world)


# ---- upgrades: five economy stats and three controller stats ----------------------------

func _upgrades(f: Array[String]) -> void:
	# gilded_touch / paycheck / hot_streak / high_ceiling / cold_blood touch five different
	# economy stats, so one build proves all five without any of them interacting.
	var world = _build({"gilded_touch": 1, "paycheck": 1, "hot_streak": 1,
			"high_ceiling": 1, "cold_blood": 1}, {})
	if world == null:
		f.append("upgrades: world.build failed")
		return
	var payout := _gift_payout(world)
	_check(f, payout == 400,
		"gilded_touch x1: a gold gift paid %d centi, want 400 (gold_value 1.0 + 1.0 on the 2.00 g base)"
				% payout)
	var stipend := _stipend_centi(world)
	_check(f, stipend == 3700,
		"paycheck x1: beacon entry paid %d centi, want 3700 (12 g stipend + 25 g)"
				% stipend)
	_check(f, _chain_survives(world, BASE_WINDOW_S + 0.5),
		"hot_streak x1: the chain did not survive a %.1f s gap, want the 5.0 s window"
				% (BASE_WINDOW_S + 0.5))
	_check(f, not _chain_survives(world, BASE_WINDOW_S + 1.5),
		"hot_streak x1: the chain survived a %.1f s gap, want the 5.0 s window"
				% (BASE_WINDOW_S + 1.5))
	var cap := _chain_cap(world)
	_check(f, absf(cap - 2.5) <= 1e-9,
		"high_ceiling x1: the chain capped at x%.4f, want x2.50" % cap)
	var tiers := _overtime_tiers(world, BASE_OVERTIME_S + 1.0)
	_check(f, tiers == 0,
		"cold_blood x1: %.1f s of gold phase gave %d overtime tiers, want 0 (the 30 s period)"
				% [BASE_OVERTIME_S + 1.0, tiers])
	_drop(world)

	# yearn_for_speed / sure_foot: two different controller stats.
	world = _build({"yearn_for_speed": 1, "sure_foot": 1}, {})
	if world == null:
		f.append("upgrades: the controller build failed")
		return
	var speed := _measured_speed(world)
	_check(f, absf(speed - 9.9) <= 0.05,
		"yearn_for_speed x1: run speed %.4f, want 9.90 (9.0 x 1.1)" % speed)
	var ticks := _respawn_ticks(world)
	_check(f, absi(ticks - _ticks_for(0.4)) <= TICK_TOLERANCE,
		"sure_foot x1: the void-fall respawn took %d ticks, want %d (0.4 s)"
				% [ticks, _ticks_for(0.4)])
	var invuln := _respawn_invuln(world)
	_check(f, absf(invuln - 2.0) <= 1e-9,
		"sure_foot x1: respawn invulnerability %.4f s, want 2.00 s" % invuln)
	_drop(world)

	# insulation: the glitched floor's own slow, on its own so the number is unambiguous.
	world = _build({"insulation": 1}, {})
	if world == null:
		f.append("upgrades: the insulation build failed")
		return
	var glitched := _glitched_speed(world)
	_check(f, absf(glitched - 8.1) <= 0.05,
		"insulation x1: glitched-floor speed %.4f, want 8.10 (9.0 x 0.9)" % glitched)
	_drop(world)

	# stack repetition: the ledger's stack COUNT has to reach apply_modifiers, not just the
	# content id. gilded_touch x2 is +2.00 g on the 2.00 g base (3.00 g -> 600 centi) and
	# yearn_for_speed x2 is 1.1 x 1.1 = 1.21 on the 9.0 base (10.89), so a wiring that
	# applied each owned upgrade exactly once fails both numbers.
	world = _build({"gilded_touch": 2, "yearn_for_speed": 2}, {})
	if world == null:
		f.append("upgrades: the stack build failed")
		return
	var stacked := _gift_payout(world)
	_check(f, stacked == 600,
		"gilded_touch x2: a gold gift paid %d centi, want 600 (gold_value 1.0 + 2.0 on the 2.00 g base)"
				% stacked)
	var stacked_speed := _measured_speed(world)
	_check(f, absf(stacked_speed - 10.89) <= 0.05,
		"yearn_for_speed x2: run speed %.4f, want 10.89 (9.0 x 1.1 x 1.1)" % stacked_speed)
	_drop(world)


# ---- curses: three economy stats and three controller stats ----------------------------

func _curses(f: Array[String]) -> void:
	# tarnish / short_chain / long_night: three different economy stats, one build.
	var world = _build({}, {"tarnish": 1, "short_chain": 1, "long_night": 1})
	if world == null:
		f.append("curses: world.build failed")
		return
	var payout := _gift_payout(world)
	_check(f, payout == 160,
		"tarnish x1: a gold gift paid %d centi, want 160 (gold_value 1.0 x 0.8 on the 2.00 g base)"
				% payout)
	_check(f, _chain_survives(world, 2.5),
		"short_chain: the chain did not survive a 2.5 s gap, want the 3.0 s window")
	_check(f, not _chain_survives(world, 3.5),
		"short_chain: the chain survived a 3.5 s gap, want the 3.0 s window")
	var tiers := _overtime_tiers(world, 15.0)
	_check(f, tiers == 1,
		"long_night: 15.0 s of gold phase gave %d overtime tiers, want 1 (the 14 s period)"
				% tiers)
	_drop(world)

	# hungry_void / brittle: the charge cap and both respawn numbers.
	world = _build({}, {"hungry_void": 1, "brittle": 1})
	if world == null:
		f.append("curses: the controller build failed")
		return
	_check(f, int(world.ctl.charge_cap) == 1,
		"hungry_void: charge cap %d, want 1" % int(world.ctl.charge_cap))
	_check(f, int(world.ctl.charges) == 1,
		"hungry_void: charges held %d at level start, want 1 (clamped to the new cap)"
				% int(world.ctl.charges))
	var ticks := _respawn_ticks(world)
	_check(f, absi(ticks - _ticks_for(1.6)) <= TICK_TOLERANCE,
		"brittle x1: the void-fall respawn took %d ticks, want %d (1.6 s)"
				% [ticks, _ticks_for(1.6)])
	var invuln := _respawn_invuln(world)
	_check(f, absf(invuln - 0.5) <= 1e-9,
		"brittle x1: respawn invulnerability %.4f s, want 0.50 s" % invuln)
	_drop(world)

	# weighed_down is the one `when: gold_phase` modifier in content: it must be inert in
	# the black phase and live in the gold phase, through step()'s own phase edge.
	world = _build({}, {"weighed_down": 1})
	if world == null:
		f.append("curses: the weighed_down build failed")
		return
	var black := _measured_speed(world)
	_check(f, absf(black - BASE_RUN_SPEED) <= 0.05,
		"weighed_down: black-phase run speed %.4f, want the unmodified %.2f"
				% [black, BASE_RUN_SPEED])
	_check(f, _open_gold_phase(world),
		"weighed_down: the gold phase did not start, so the phase edge is unproven")
	var gold := _measured_speed(world)
	_check(f, absf(gold - 8.1) <= 0.05,
		"weighed_down: gold-phase run speed %.4f, want 8.10 (9.0 x 0.9)" % gold)
	_drop(world)

	# stack repetition on the curse side: tarnish x2 is 0.8 x 0.8 = 0.64 on the 2.00 g base
	# (128 centi) and brittle x2 is the content's own 2.4 s / 0.0 s pair, so a wiring that
	# applied each held curse exactly once fails all three numbers.
	world = _build({}, {"tarnish": 2, "brittle": 2})
	if world == null:
		f.append("curses: the stack build failed")
		return
	var stacked := _gift_payout(world)
	_check(f, stacked == 128,
		"tarnish x2: a gold gift paid %d centi, want 128 (gold_value 1.0 x 0.8 x 0.8 on the 2.00 g base)"
				% stacked)
	var stacked_ticks := _respawn_ticks(world)
	_check(f, absi(stacked_ticks - _ticks_for(2.4)) <= TICK_TOLERANCE,
		"brittle x2: the void-fall respawn took %d ticks, want %d (2.4 s)"
				% [stacked_ticks, _ticks_for(2.4)])
	var stacked_invuln := _respawn_invuln(world)
	_check(f, absf(stacked_invuln - 0.0) <= 1e-9,
		"brittle x2: respawn invulnerability %.4f s, want 0.00 s" % stacked_invuln)
	_drop(world)


# ---- the real run path ------------------------------------------------------------------

## A real level through the shipped build path, with a carried ledger (the app's own
## handover shape). Empty stacks + curses is the negative control. null on a build failure.
func _build(stacks: Dictionary, curses: Dictionary):
	var world = WorldScript.new()
	var ledger := {
		"class": "dasher", "votes": {}, "curses": curses, "stacks": stacks,
		"purse": 0, "tithes": 0, "hunger": 0, "last_vote": "",
	}
	if not world.build(SEED, LEVEL, ledger):
		world.free()
		return null
	return world


## Opens the beacon through its own API and lets one step() run the gold-phase edge, which
## is where the `when: gold_phase` modifiers go live. The player is moved well clear of the
## beacon first: entering it would complete the level and end the gold phase on the same
## tick. Returns true when the gold phase is actually running afterwards.
func _open_gold_phase(world) -> bool:
	world.ctl.x = float(world.lstate.beacon.cx) + 20.0
	world.ctl.z = float(world.lstate.beacon.cz) + 20.0
	world.lstate.beacon.open(int(world.lstate.tick))
	world.step(DT)
	return bool(world._economy.gold_phase)


func _drop(world) -> void:
	world.teardown()
	world.free()


# ---- measurements: the world's own economy ----------------------------------------------

## One gold gift's payout in centi-gold, from the economy the run itself pays through.
func _gift_payout(world) -> int:
	var e: RefCounted = world._economy
	e.begin_gold_phase()
	var before: int = int(e.purse_centi)
	e.collect_gold_gift()
	return int(e.purse_centi) - before


## True when the chain survived a `gap`-second silence after one gift: the window is the
## only thing that decides it (tick_gold resets on a missed window).
func _chain_survives(world, gap: float) -> bool:
	var e: RefCounted = world._economy
	e.begin_gold_phase()
	e.collect_gold_gift()
	e.tick_gold(gap)
	return float(e.chain_display()) > 1.0


## The chain cap: gifts collected back to back until the chain stops rising.
func _chain_cap(world) -> float:
	var e: RefCounted = world._economy
	e.begin_gold_phase()
	for _i in range(60):
		e.collect_gold_gift()
	return float(e.chain_display())


## Overtime tiers gained over `seconds` of gold phase: the period is the only thing that
## decides it.
func _overtime_tiers(world, seconds: float) -> int:
	var e: RefCounted = world._economy
	e.begin_gold_phase()
	return int(e.tick_gold(seconds))


## The clear stipend, in centi-gold: what beacon entry actually credits.
func _stipend_centi(world) -> int:
	var e: RefCounted = world._economy
	var before: int = int(e.purse_centi)
	e.enter_beacon(LEVEL)
	return int(e.purse_centi) - before


# ---- measurements: the world's own controller -------------------------------------------

## The controller's live run speed: real 60 Hz ticks with full forward input on a flat
## strip, read off the body's own velocity (not off a stat field).
func _measured_speed(world) -> float:
	var ctl = world.ctl
	var flat := _flat()
	ctl.place(flat)
	Util.run_ticks(ctl, flat, 30, func(_c, _i): return Util.mk_in(1, 0))
	return float(ctl.vx)


## The same, with every tile of the strip glitched: the floor's own slow is the only
## difference (D-075).
func _glitched_speed(world) -> float:
	var ctl = world.ctl
	var flat := _flat()
	for cx in range(-4, 40):
		flat["glitched"]["%d,0,0" % cx] = true
	ctl.place(flat)
	Util.run_ticks(ctl, flat, 30, func(_c, _i): return Util.mk_in(1, 0))
	return float(ctl.vx)


## The void-fall respawn wait, counted in 60 Hz ticks between the fall and the respawn
## event. -1 when no respawn arrived inside 400 ticks.
func _respawn_ticks(world) -> int:
	var ctl = world.ctl
	var flat := _flat()
	ctl.place(flat)
	ctl.charges = int(ctl.charge_cap)
	ctl.y = -100.0   # past kill_plane_y (-40): the fall happens on this tick
	ctl.step(DT, Util.mk_in(), flat)
	var ticks := 0
	for _i in range(400):
		ticks += 1
		for e in ctl.step(DT, Util.mk_in(), flat):
			if str(e.get("e", "")) == "respawn":
				return ticks
	return -1


## The invulnerability the respawn granted, read on the tick it landed (nothing has
## decremented it yet).
func _respawn_invuln(world) -> float:
	var ctl = world.ctl
	var flat := _flat()
	ctl.place(flat)
	ctl.charges = int(ctl.charge_cap)
	ctl.y = -100.0
	ctl.step(DT, Util.mk_in(), flat)
	for _i in range(400):
		for e in ctl.step(DT, Util.mk_in(), flat):
			if str(e.get("e", "")) == "respawn":
				return float(ctl.invuln)
	return -1.0


func _ticks_for(seconds: float) -> int:
	return int(round(seconds / DT))


## A flat 44-tile strip along +x, with the dais ON it (the shape test_upgrades_decl.gd
## uses for the same measurement), so a speed reading is never a wall, a ledge or a fall.
func _flat() -> Dictionary:
	var tiles: Array = []
	for cx in range(-4, 40):
		tiles.append([cx, 0, 0, 0, 0])
	return CollisionScript.make_world(tiles, [], [], {"dais": [-4, 0, 0]})


func _check(f: Array[String], ok: bool, msg: String) -> bool:
	if not ok:
		f.append(msg)
	return ok
