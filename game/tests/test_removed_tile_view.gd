extends RefCounted
#
# REMOVED-TILE VIEW test (headless, B7; PARKED.md row 32): a gift or a tripmine standing
# on a tile the `crumbling` curse removed must not hang in the air for the 5 s the hole
# lasts.
#
# The curse (content/curses/crumbling.gd) removes 1-wide walkway tiles 1.2 s after they
# are stepped on and returns them 5 s later, through the same w["removed"] set the
# platform collapse uses (app/world.gd _apply_tile_events). The B6 collapse sweep
# deliberately does NOT touch these slots: the curse's tiles RETURN, so marking a gift
# `lost` would destroy it permanently for a temporary hole. The fix is view-side
# (D-B7-1): the gift and the mine render hidden while their supporting tile is in
# w["removed"] and come back with the tile. No sim state changes - the gift stays
# collectible and stays in the quota, the mine stays live.
#
# Every leg runs on a REAL generated level through world.build() / world.step(), and the
# hole is opened through the world's own tile applicator (_apply_tile_events with the
# curse's own tile_fell / tile_returned events) - the exact call the crumbling
# dispatcher's events reach. The curse's own 72 / 300 tick schedule is
# test_curse_crumbling.gd's job, not this file's.
#
#   gift leg     - a gift on a removed tile renders hidden, comes back when the tile
#                  returns, and is still present() / collectible while hidden; a gift on
#                  a tile that is NOT removed still renders (the control that stops this
#                  test passing by hiding everything).
#   gold leg     - the same rule on the gold twin (the gold phase's model at the same
#                  slot id).
#   mine leg     - the same rule for a tripmine, which stays live (contact_at still
#                  answers at its own point) while hidden.
#   collapse leg - the rule is a NO-OP on the collapse path: a gift the sweep lost and a
#                  mine it dropped are hidden with their tile in the removed set and
#                  hidden with it out of the set, because present() / is_consumed already
#                  say so.

const WorldScript := preload("res://app/world.gd")
const CollisionScript := preload("res://sim/collision.gd")
const GiftsScript := preload("res://sim/gifts.gd")

const SEED := 1
const LEVEL := 1
const SEED_MINES := 0
const LEVEL_MINES := 5   # mine occupancy (TERRAIN_SPEC 6.8); seed 0 level 5 measured 3 mines
const DT := 1.0 / 60.0


func run() -> Array[String]:
	var f: Array[String] = []
	_gift_leg(f)
	_gold_leg(f)
	_mine_leg(f)
	_collapse_noop_leg(f)
	return f


# ---- helpers -------------------------------------------------------------------------------

func _check(f: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		f.append(msg)


func _build(seed_value: int, level: int):
	var world = WorldScript.new()
	if not world.build(seed_value, level):
		world.free()
		return null
	return world


func _drop(world) -> void:
	if world != null:
		world.teardown()
		world.free()


## The curse's fall, through the world's own tile applicator: the tile leaves collision
## (into w["removed"]) and the view pass runs on the same tick, exactly as
## world.step()'s _apply_tile_events + _view_pass pair does.
func _fell(world, key: String) -> void:
	world._apply_tile_events([{"e": "tile_fell", "key": key}], 0)
	world._view_pass()


## The curse's return: the tile comes back and the view pass runs.
func _returned(world, key: String) -> void:
	world._apply_tile_events([{"e": "tile_returned", "key": key}], 0)
	world._view_pass()


## The first real gift slot that is still present (the black phase's gift), -1 when none.
func _first_present(g) -> int:
	for i in g.slots.size():
		if g.present(i):
			return i
	return -1


## The tripmine view's root node for `slot` (null when that slot carries no mine).
func _mine_root(tv, slot: int) -> Node3D:
	for e in tv._nodes:
		if int(e["slot"]) == slot:
			return e["node"]
	return null


## Put the player's feet on the slot's tile top, still, and step one tick: the shipped
## pickup path (world.step -> GiftsScript.tick).
func _stand_on(world, pos: Vector3) -> void:
	world.ctl.x = pos.x
	world.ctl.y = pos.y - 1.0
	world.ctl.z = pos.z
	world.ctl.vx = 0.0
	world.ctl.vy = 0.0
	world.ctl.vz = 0.0
	world.ctl.invuln = 1000.0   # no mine / enemy may end the run mid-measurement
	world.step(DT)


# ---- leg 1: the gift ------------------------------------------------------------------------

func _gift_leg(f: Array[String]) -> void:
	var world = _build(SEED, LEVEL)
	if world == null:
		f.append("gift: world.build(%d, %d) failed" % [SEED, LEVEL])
		return
	var g: RefCounted = world.lstate.gifts
	var gv = world.gifts_view
	if g == null or gv == null:
		f.append("gift: build() added no gift view (gifts %s, view %s)" % [str(g), str(gv)])
		_drop(world)
		return
	# i is the slot the curse's hole opens under, j the control that must stay visible
	var i: int = _first_present(g)
	var j := -1
	for s in g.slots.size():
		if s != i and g.present(s):
			j = s
			break
	if i < 0 or j < 0:
		f.append("gift: level %d seed %d has fewer than 2 present gift slots" % [LEVEL, SEED])
		_drop(world)
		return
	var s_i: Dictionary = g.slots[i]
	var key: String = g.slot_tile_key(i)
	var want: String = CollisionScript.tile_key(int(s_i["x"]), int(s_i["z"]), int(s_i["y"]))
	_check(f, key == want,
			"gift: slot_tile_key(%d) = %s, want collision.gd's own key %s" % [i, key, want])
	_check(f, gv._black[i].visible, "gift: slot %d is hidden before any tile is removed" % i)
	_check(f, gv._black[j].visible, "gift: control slot %d is hidden before any tile is removed" % j)
	var rem_before: int = g.remaining()

	# the curse's fall: the tile leaves collision, the gift must leave the air with it
	_fell(world, key)
	_check(f, world.w["removed"].has(key), "gift: the tile applicator did not remove %s" % key)
	_check(f, not gv._black[i].visible,
			"gift: slot %d still renders in mid-air over the removed tile %s" % [i, key])
	_check(f, gv._black[j].visible, "gift: control slot %d went out with an unrelated tile" % j)
	_check(f, g.present(i),
			"gift: slot %d stopped being present() while its tile was a hole (the sim must be untouched)" % i)
	_check(f, not g.is_lost(i), "gift: slot %d was marked lost by a temporary hole" % i)
	_check(f, g.remaining() == rem_before,
			"gift: remaining() moved %d -> %d while the tile was a hole" % [rem_before, g.remaining()])

	# the curse's return: the tile comes back, the gift comes back with it
	_returned(world, key)
	_check(f, not world.w["removed"].has(key), "gift: the tile applicator did not restore %s" % key)
	_check(f, gv._black[i].visible, "gift: slot %d did not come back with its tile" % i)

	# still collectible while hidden: the hole opens again and the player walks onto the
	# slot - one world.step() picks the gift up through the shipped pickup loop
	_fell(world, key)
	_check(f, not gv._black[i].visible, "gift: slot %d renders over the second hole" % i)
	_stand_on(world, g.slot_pos(i))
	_check(f, g.collected(i), "gift: slot %d was not collectible while its tile was a hole" % i)
	_drop(world)


# ---- leg 2: the gold twin -------------------------------------------------------------------

## The gold gift is the same slot id's second model, shown once the phase flips. It carries
## the same rule, so a gold gift must not hang over a hole either.
func _gold_leg(f: Array[String]) -> void:
	var world = _build(SEED, LEVEL)
	if world == null:
		f.append("gold: world.build(%d, %d) failed" % [SEED, LEVEL])
		_drop(world)
		return
	var g: RefCounted = world.lstate.gifts
	var gv = world.gifts_view
	if g == null or gv == null:
		f.append("gold: build() added no gift view")
		_drop(world)
		return
	# collect every real black gift through world.step() (test_app_views.gd's idiom)
	for s in g.slots.size():
		if not g.is_real(s):
			continue
		_stand_on(world, g.slot_pos(s))
	if g.phase != GiftsScript.PHASE_GOLD:
		f.append("gold: the gold phase never started (phase = %s)" % str(g.phase))
		_drop(world)
		return
	var i: int = _first_present(g)
	if i < 0:
		f.append("gold: no present gold gift after the flip")
		_drop(world)
		return
	var key: String = g.slot_tile_key(i)
	_check(f, gv._gold[i].visible, "gold: slot %d is hidden before any tile is removed" % i)
	_fell(world, key)
	_check(f, not gv._gold[i].visible,
			"gold: the gold gift at slot %d still renders over the removed tile %s" % [i, key])
	_check(f, g.present(i), "gold: slot %d stopped being present() while its tile was a hole" % i)
	_returned(world, key)
	_check(f, gv._gold[i].visible, "gold: slot %d did not come back with its tile" % i)
	_drop(world)


# ---- leg 3: the tripmine --------------------------------------------------------------------

func _mine_leg(f: Array[String]) -> void:
	var world = _build(SEED_MINES, LEVEL_MINES)
	if world == null:
		f.append("mine: world.build(%d, %d) failed" % [SEED_MINES, LEVEL_MINES])
		return
	var m: RefCounted = world.lstate.mines
	var tv = world.tripmine_view
	if m == null or tv == null or m.ids.is_empty():
		f.append("mine: level %d seed %d carries no mine (mines %s, view %s)"
				% [LEVEL_MINES, SEED_MINES, str(m), str(tv)])
		_drop(world)
		return
	var slot: int = int(m.ids[0])
	var s_m: Dictionary = m.slots[slot]
	var key: String = m.slot_tile_key(slot)
	var want: String = CollisionScript.tile_key(int(s_m["x"]), int(s_m["z"]), int(s_m["y"]))
	_check(f, key == want,
			"mine: slot_tile_key(%d) = %s, want collision.gd's own key %s" % [slot, key, want])
	var root: Node3D = _mine_root(tv, slot)
	if root == null:
		f.append("mine: the tripmine view has no root for slot %d" % slot)
		_drop(world)
		return
	_check(f, root.visible, "mine: slot %d is hidden before any tile is removed" % slot)
	_fell(world, key)
	_check(f, not root.visible,
			"mine: slot %d still renders in mid-air over the removed tile %s" % [slot, key])
	_check(f, not m.is_consumed(slot), "mine: slot %d was consumed by a temporary hole" % slot)
	var p: Vector3 = m.point(slot)
	_check(f, m.contact_at(p.x, p.z) != -1,
			"mine: no live mine answers at slot %d's own point while its tile is a hole" % slot)
	_returned(world, key)
	_check(f, root.visible, "mine: slot %d did not come back with its tile" % slot)
	_drop(world)


# ---- leg 4: the collapse path is a no-op ----------------------------------------------------

## The collapse's contract is "the tile is gone for good": sim/collapse.gd writes into
## w["removed"] once and nothing restores it, and app/world.gd's _collapse_sweep marks what
## was standing there (gifts.lose / mines.drop). Those slots are already hidden by
## present() / is_consumed, so the new removed-set term must change nothing for them - with
## the key in the set and with it out of the set the node stays hidden.
func _collapse_noop_leg(f: Array[String]) -> void:
	var world = _build(SEED_MINES, LEVEL_MINES)
	if world == null:
		f.append("collapse: world.build(%d, %d) failed" % [SEED_MINES, LEVEL_MINES])
		return
	var g: RefCounted = world.lstate.gifts
	var m: RefCounted = world.lstate.mines
	var gv = world.gifts_view
	var tv = world.tripmine_view
	if g == null or m == null or gv == null or tv == null:
		f.append("collapse: build() added no gift / mine view")
		_drop(world)
		return
	var gi: int = _first_present(g)
	if gi < 0 or m.ids.is_empty():
		f.append("collapse: level %d seed %d needs one present gift and one mine"
				% [LEVEL_MINES, SEED_MINES])
		_drop(world)
		return
	var mi: int = int(m.ids[0])
	var gkey: String = g.slot_tile_key(gi)
	var mkey: String = m.slot_tile_key(mi)
	var mroot: Node3D = _mine_root(tv, mi)
	if mroot == null:
		f.append("collapse: the tripmine view has no root for slot %d" % mi)
		_drop(world)
		return

	# the sweep, on the keys the collapse would have removed
	world._collapse_sweep([gkey, mkey])
	_check(f, g.is_lost(gi), "collapse: the sweep did not lose the gift on %s" % gkey)
	_check(f, not g.present(gi), "collapse: a lost gift is still present()")
	_check(f, m.is_consumed(mi), "collapse: the sweep did not drop the mine on %s" % mkey)

	# with the tile in the removed set: hidden (as before)
	_fell(world, gkey)
	_fell(world, mkey)
	_check(f, not gv._black[gi].visible, "collapse: a lost gift renders over its removed tile")
	_check(f, not mroot.visible, "collapse: a dropped mine renders over its removed tile")

	# with the tile out of the removed set: still hidden - present() / is_consumed are what
	# hide them, so the new rule is a no-op on this path
	world.w["removed"].erase(gkey)
	world.w["removed"].erase(mkey)
	world._view_pass()
	_check(f, not gv._black[gi].visible,
			"collapse: a lost gift renders once its tile leaves the removed set (the new rule is not a no-op there)")
	_check(f, not mroot.visible,
			"collapse: a dropped mine renders once its tile leaves the removed set (the new rule is not a no-op there)")
	_drop(world)
