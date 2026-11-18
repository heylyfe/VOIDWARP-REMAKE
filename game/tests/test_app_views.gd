extends RefCounted
#
# APP-VIEWS test (headless): the playable level's core-loop views, through
# game/app/world.gd's own build(), step() and teardown(). The bug hunt found the app built
# terrain, fog, the camera, the enemy billboards and the HUD and instantiated no gift,
# tripmine or beacon view at all - view/gifts_view.gd, view/tripmine_view.gd and
# view/beacon_view.gd were referenced only by their own tests - so a real level was played
# blind: invisible gifts, an invisible beacon, invisible mines.
#
#   leg A (level 1, seed 1): build() adds the gift view with one black + one gold model
#   per REAL gift slot (occ == 1 slots get none), the black one shown and both on the
#   sim's own slot_pos(); and the beacon view on the dais tile with its column down.
#   Collecting every real black gift through world.step() flips the phase: the gold
#   models take over at the same slots and the light column is up on the open tick.
#   teardown() leaves no child, no view reference and no live node behind.
#   leg B (level 5, seed 0 - mine occupancy): one tripmine view root per mine, on the
#   sim's own point(), all shown; a consumed mine leaves the view on the next step().
#
# The test fails if build() stops instantiating the three views, if step() stops driving
# them from the sim state, or if teardown() stops freeing them.

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
	_leg_b(f)
	return f


func _leg_a(f: Array[String]) -> void:
	var world = WorldScript.new()
	if not world.build(SEED_A, LEVEL_A):
		f.append("leg A: world failed to build level %d seed %d" % [LEVEL_A, SEED_A])
		world.free()
		return
	if world.gifts_view == null or world.tripmine_view == null or world.beacon_view == null:
		f.append("leg A: build() added no core-loop view (gifts %s, tripmine %s, beacon %s)"
				% [str(world.gifts_view), str(world.tripmine_view), str(world.beacon_view)])
		_drop(world)
		return
	var g: RefCounted = world.lstate.gifts
	var real_total: int = int(g.total_real)
	if real_total <= 0:
		f.append("leg A: no real gifts in level %d seed %d" % [LEVEL_A, SEED_A])
		_drop(world)
		return
	var gv = world.gifts_view
	var slots: int = g.slots.size()

	# one black AND one gold model per REAL slot: the gold set is the same slot ids
	# (DESIGN.md section 3, "same slot id, same position"), hidden until the flip
	if int(gv.get_child_count()) != 2 * real_total:
		f.append("leg A: gift view holds %d nodes for %d real slots, want %d (black + gold)"
				% [int(gv.get_child_count()), real_total, 2 * real_total])
	if int(gv._black.size()) != slots or int(gv._gold.size()) != slots:
		f.append("leg A: gift slot tables are %d/%d entries, want %d (one per slot id)"
				% [int(gv._black.size()), int(gv._gold.size()), slots])
	var shown := 0
	for i in slots:
		var black = gv._black[i]
		var gold = gv._gold[i]
		if not bool(g.is_real(i)):
			if black != null or gold != null:
				f.append("leg A: tripmine slot %d got a gift node (occ == 1 never has one)" % i)
			continue
		if black == null:
			f.append("leg A: no black model for real slot %d" % i)
			continue
		if gold == null:
			f.append("leg A: no gold model for real slot %d" % i)
			continue
		var want: Vector3 = g.slot_pos(i)
		if not (black as Node3D).position.is_equal_approx(want):
			f.append("leg A: black gift %d sits at %s, want the sim's slot_pos %s"
					% [i, str((black as Node3D).position), str(want)])
		if not (gold as Node3D).position.is_equal_approx(want):
			f.append("leg A: gold gift %d sits at %s, want the same slot %s"
					% [i, str((gold as Node3D).position), str(want)])
		if not (black as Node3D).visible:
			f.append("leg A: black gift %d is hidden in the black phase" % i)
		if (gold as Node3D).visible:
			f.append("leg A: gold gift %d shows before the gold phase" % i)
		if (black as Node3D).visible:
			shown += 1
	if shown != real_total:
		f.append("leg A: %d black gifts on screen, want %d" % [shown, real_total])

	# the beacon view stands on the dais tile the Level dict names (the sim's own mapping)
	var bp: Array = world.lv["beacon"]
	var want_bp := Vector3(float(int(bp[0])) + 0.5, float(int(bp[2])) * 0.5,
			float(int(bp[1])) + 0.5)
	if not world.beacon_view.position.is_equal_approx(want_bp):
		f.append("leg A: the beacon view sits at %s, want the dais tile %s"
				% [str(world.beacon_view.position), str(want_bp)])
	if world.beacon_view.column_visible():
		f.append("leg A: the beacon column shows while the beacon is CLOSED")

	# collect every real black gift, one world.step() each (test_app_loop.gd's idiom):
	# the black models go out, the gold ones arrive at the same slots, and the light
	# column is up on the tick the beacon opens
	for i in slots:
		if not bool(g.is_real(i)):
			continue
		var pos: Vector3 = g.slot_pos(i)
		world.ctl.x = pos.x
		world.ctl.y = pos.y - 1.0   # feet on the slot's tile top; pickup centre 0.9 u up
		world.ctl.z = pos.z
		world.ctl.vy = 0.0
		world.step(DT)
	if g.phase != GiftsScript.PHASE_GOLD:
		f.append("leg A: the gold phase never started (phase = %s)" % str(g.phase))
	if not bool(world.lstate.beacon.is_open()):
		f.append("leg A: the beacon did not open on the last real black gift")
	var gold_shown := 0
	for i in slots:
		if not bool(g.is_real(i)):
			continue
		var black2 = gv._black[i]
		var gold2 = gv._gold[i]
		if black2 == null or gold2 == null:
			continue   # the missing model was reported above
		if (black2 as Node3D).visible:
			f.append("leg A: black gift %d still shows in the gold phase" % i)
		if not (gold2 as Node3D).visible:
			f.append("leg A: no gold gift at slot %d after the flip" % i)
			continue
		gold_shown += 1
	if gold_shown != real_total:
		f.append("leg A: %d gold gifts on screen, want %d (the same slots)"
				% [gold_shown, real_total])
	if not world.beacon_view.column_visible():
		f.append("leg A: no light column on the tick the beacon opened")
	elif world.beacon_view.column_height() <= 0.0:
		f.append("leg A: the light column has zero height on the open tick")

	# teardown leaves nothing behind: no child, no reference, no live node
	var freed_view = world.gifts_view
	world.teardown()
	if int(world.get_child_count()) != 0:
		f.append("teardown: %d children left behind" % int(world.get_child_count()))
	if is_instance_valid(freed_view):
		f.append("teardown: the gift view outlived the level (its nodes were not freed)")
	if world.gifts_view != null or world.tripmine_view != null or world.beacon_view != null:
		f.append("teardown: a view reference was not cleared (step() would touch freed nodes)")
	world.free()


func _leg_b(f: Array[String]) -> void:
	var world = WorldScript.new()
	if not world.build(SEED_B, LEVEL_B):
		f.append("leg B: world failed to build level %d seed %d" % [LEVEL_B, SEED_B])
		world.free()
		return
	if world.tripmine_view == null:
		f.append("leg B: build() added no tripmine view")
		_drop(world)
		return
	var mines: RefCounted = world.lstate.mines
	if mines.count() == 0:
		f.append("leg B: level %d seed %d has no tripmines (the tell is untested)"
				% [LEVEL_B, SEED_B])
		_drop(world)
		return
	var tv = world.tripmine_view
	if int(tv.get_child_count()) != mines.count():
		f.append("leg B: tripmine view holds %d nodes for %d mines, want one per mine"
				% [int(tv.get_child_count()), mines.count()])
	# every live mine has a node on the sim's own point(), and it shows
	for slot in mines.ids:
		var want: Vector3 = mines.point(int(slot))
		var shown := false
		for c in tv.get_children():
			if (c as Node3D).position.is_equal_approx(want):
				shown = (c as Node3D).visible
		if not shown:
			f.append("leg B: no visible tripmine node on the sim point for slot %d" % int(slot))
	# a consumed mine (defused / shielded / detonated) leaves the view on the next step
	var slot0: int = int(mines.ids[0])
	mines.consume(slot0)
	world.step(DT)
	var point0: Vector3 = mines.point(slot0)
	for c in tv.get_children():
		if (c as Node3D).position.is_equal_approx(point0) and (c as Node3D).visible:
			f.append("leg B: the consumed mine at slot %d still shows" % slot0)
	_drop(world)


func _drop(world) -> void:
	world.teardown()
	world.free()
