extends RefCounted
#
# APP-LOOP test (headless): the shipped app's level loop, end to end, through
# game/app/world.gd's own build() and step(). Proves the pieces the T-099 audit
# found missing from the shipped exe (D-APPFLOW-5) are now ticked:
#
#   leg A (level 1, seed 1): build -> HUD counter shows the REAL gift count
#   (not 0/0) -> collect every real black gift one per world.step() (the teleport
#   idiom of test_gifts.gd, driven through the full app tick: input capture,
#   controller, gifts, mines, beacon, enemy runtime, HUD sync) -> gold phase opens
#   the beacon on the same tick -> a gold gift pays the economy (purse > 0,
#   chain advances) -> the beacon entry completes the level: the level_completed
#   signal fires exactly once, is_complete() reports true, the HUD gift count and
#   purse/chain are real.
#   leg B (level 5, seed 0 - 3 mine slots measured): a tripmine contact runs the
#   ladder inside step() (Last Light save spends the save, mine consumed).
#   leg C (same world): a void fall past the kill plane costs exactly 1 charge
#   (the controller path rides inside step()).
#
# The test fails if step() stops ticking gifts (counter/collection asserts),
# mines (consumption assert) or the beacon (open / entry / signal asserts).

const WorldScript := preload("res://app/world.gd")
const GiftsScript := preload("res://sim/gifts.gd")

const SEED_A := 1
const LEVEL_A := 1
const SEED_B := 0
const LEVEL_B := 5   # mine occupancy (TERRAIN_SPEC 6.8); seed 0 level 5 measured 3 mines
const DT := 1.0 / 60.0


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_a(f)
	_leg_b_c(f)
	return f


func _leg_a(f: Array[String]) -> void:
	var world = WorldScript.new()
	var emitted: Array[int] = [0]
	world.level_completed.connect(func() -> void: emitted[0] = emitted[0] + 1)
	if not world.build(SEED_A, LEVEL_A):
		f.append("leg A: world failed to build level %d seed %d" % [LEVEL_A, SEED_A])
		world.free()
		return

	var g: RefCounted = world.lstate.gifts
	var real_total: int = int(g.total_real)
	if real_total <= 0:
		f.append("leg A: no real gifts in level %d seed %d" % [LEVEL_A, SEED_A])
		_drop(world)
		return

	# the HUD counter at level start: 0 collected, the REAL total (never 0/0)
	var counter := str(world.hud.gift_counter.counter_text())
	if counter != "0 / %d" % real_total:
		f.append("leg A: HUD counter at start reads '%s', want '0 / %d'" % [counter, real_total])

	# collect every real black gift, one world.step() each
	var gold_phase_seen := false
	var collected := 0
	for i in g.slots.size():
		if not g.is_real(i):
			continue
		var pos: Vector3 = g.slot_pos(i)
		world.ctl.x = pos.x
		world.ctl.y = pos.y - 1.0   # feet on the slot's tile top; pickup centre 0.9 u up
		world.ctl.z = pos.z
		world.ctl.vy = 0.0
		world.step(DT)
		collected += 1
		var want_collected: int = mini(int(g.total_real) - int(g.remaining()), real_total)
		var want_text := "%d / %d" % [want_collected, real_total]
		if str(world.hud.gift_counter.counter_text()) != want_text:
			f.append("leg A: after slot %d the HUD counter reads '%s', want '%s'"
					% [i, str(world.hud.gift_counter.counter_text()), want_text])
		if g.phase == GiftsScript.PHASE_GOLD:
			gold_phase_seen = true
	if int(g.remaining()) != int(g.total_real):
		f.append("leg A: after all black gifts, gold remaining %d, want %d (same slots)"
				% [int(g.remaining()), int(g.total_real)])
	if not gold_phase_seen:
		f.append("leg A: the gold phase never started (phase = %s)" % str(g.phase))

	# the beacon must be OPEN exactly then (black -> gold met)
	if not bool(world.lstate.beacon.is_open()):
		f.append("leg A: beacon still CLOSED after the last real black gift")

	# a gold gift pays the economy through the same tick (the chain multiplier advances)
	var purse_before: int = int(world._economy.purse_centi)
	var chain_before: float = float(world._economy.chain_display())
	for i in g.slots.size():
		if not g.is_real(i):
			continue
		var pos2: Vector3 = g.slot_pos(i)
		world.ctl.x = pos2.x
		world.ctl.y = pos2.y - 1.0
		world.ctl.z = pos2.z
		world.ctl.vy = 0.0
		world.step(DT)
		break   # one gold gift is enough to prove the credit
	var purse_after: int = int(world._economy.purse_centi)
	if purse_after <= purse_before:
		f.append("leg A: gold gift did not credit the purse (%d -> %d centi)" % [purse_before, purse_after])
	if float(world._economy.chain_display()) <= chain_before:
		f.append("leg A: gold gift did not advance the chain (%f -> %f)"
				% [chain_before, float(world._economy.chain_display())])
	var purse_text := str(world.hud.purse_chain.purse_text())
	if purse_text.begins_with("0.00"):
		f.append("leg A: HUD purse still reads '%s' after a gold gift" % purse_text)

	# enter the beacon: the level completes, the signal fires exactly once
	var bp: Array = world.lv["beacon"]
	var purse_pre_entry: int = int(world._economy.purse_centi)
	world.ctl.x = float(int(bp[0])) + 0.5
	world.ctl.y = float(int(bp[2])) * 0.5
	world.ctl.z = float(int(bp[1])) + 0.5
	world.ctl.vy = 0.0
	world.step(DT)
	if not bool(world.lstate.beacon.completed):
		f.append("leg A: beacon entry did not complete the level")
	if not world.is_complete():
		f.append("leg A: is_complete() is false after beacon entry")
	if emitted[0] != 1:
		f.append("leg A: level_completed emitted %d times, want exactly 1" % emitted[0])
	if int(world._economy.purse_centi) <= purse_pre_entry:
		f.append("leg A: beacon entry paid no stipend (%d -> %d centi)"
				% [purse_pre_entry, int(world._economy.purse_centi)])
	if bool(world._economy.gold_phase):
		f.append("leg A: gold phase still running after beacon entry")

	# the completion latch: further ticks re-emit nothing and change nothing
	var completed_at: int = int(world.lstate.tick)
	for j in range(3):
		world.step(DT)
	if emitted[0] != 1:
		f.append("leg A: level_completed re-emitted after completion (%d times)" % emitted[0])
	if int(world.lstate.tick) <= completed_at:
		f.append("leg A: the level stopped ticking after completion (tick did not advance)")
	if world.ctl.dead:
		f.append("leg A: the player died during the completion leg")
	_drop(world)


func _leg_b_c(f: Array[String]) -> void:
	var world = WorldScript.new()
	if not world.build(SEED_B, LEVEL_B):
		f.append("leg B: world failed to build level %d seed %d" % [LEVEL_B, SEED_B])
		world.free()
		return
	var mines: RefCounted = world.lstate.mines
	if mines.count() == 0:
		f.append("leg B: level %d seed %d has no tripmines (the ladder is untested)" % [LEVEL_B, SEED_B])
		_drop(world)
		return
	var ctl = world.ctl
	var charges_before: int = int(ctl.charges)
	var mine_slot: int = int(mines.ids[0])
	var mp: Vector3 = mines.point(mine_slot)
	ctl.x = mp.x
	ctl.y = float(int(mines.slots[mine_slot]["y"])) * 0.5   # feet on the tile top
	ctl.z = mp.z
	ctl.vy = 0.0
	world.step(DT)
	if not mines.is_consumed(mine_slot):
		f.append("leg B: tripmine at slot %d was not consumed by the contact ladder" % mine_slot)
	if not bool(ctl.last_light_spent):
		f.append("leg B: Last Light was not spent on the tripmine contact (charges %d)" % charges_before)
	if bool(ctl.dead):
		f.append("leg B: the player died to the tripmine despite holding a charge")

	# a void fall past the kill plane costs exactly one charge (controller path in step())
	var charges_pre_void: int = int(ctl.charges)
	ctl.respawn_t = -1.0
	ctl.invuln = 0.0
	ctl.x = -500.0   # over the void: no column underfoot
	ctl.y = -41.0    # already past the kill plane (-40.0)
	ctl.vy = -1.0
	ctl.grounded = false
	world.step(DT)
	if int(ctl.charges) != charges_pre_void - 1:
		f.append("leg C: void fall cost %d charges, want exactly 1 (was %d, now %d)"
				% [charges_pre_void - int(ctl.charges), charges_pre_void, int(ctl.charges)])
	if not bool(ctl.last_light_spent):
		f.append("leg C: Last Light state was clobbered by the void fall")
	_drop(world)


func _drop(world) -> void:
	world.teardown()
	world.free()
