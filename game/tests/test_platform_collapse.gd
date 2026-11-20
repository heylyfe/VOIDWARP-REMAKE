extends RefCounted
#
# Platform collapse after the beacon opens (sim/collapse.gd, view/collapse_view.gd, wired in
# app/world.gd). Driven through world.build() / world.step() only.
#   leg 1  before the beacon opens: nothing cracked, nothing removed (negative control)
#   leg 2  the open tick: cracked > 0, removed == 0, the crack overlay is visible
#   leg 3  open + 299: removed == 0; open + 300: removed > 0 (the 5 s boundary, both sides)
#   leg 4  the hub's tiles are never cracked and never removed, any tick, 3 seeds/levels
#   leg 5  a player parked on a non-hub tile drops into the real void_fall event
#   leg 6  determinism: two identical builds -> identical sets and fall tick
#   leg 7  collapse disabled: zero cracked, zero removed, the same player does NOT fall

const WorldScript := preload("res://app/world.gd")
const CollapseScript := preload("res://sim/collapse.gd")
const CollisionScript := preload("res://sim/collision.gd")

const DT := 1.0 / 60.0
const CASES := [[1, 5], [7, 3], [42, 11]]   # [seed, level]


func run() -> Array[String]:
	var f: Array[String] = []
	_legs_1_2_3(f)
	_leg_4(f)
	_leg_5_7(f)
	_leg_6(f)
	return f


func _build(seed_value: int, level: int, collapse_on: bool = true):
	var world = WorldScript.new()
	world.platform_collapse = collapse_on
	var ledger := {
		"class": "dasher", "votes": {}, "curses": {}, "stacks": {},
		"purse": 0, "tithes": 0, "hunger": 0, "last_vote": "",
	}
	if not world.build(seed_value, level, ledger):
		world.free()
		return null
	return world


func _drop(world) -> void:
	if world != null:
		world.teardown()
		world.free()


func _cracked(world) -> int:
	return CollapseScript.cracked_keys(world._collapse).size()


func _removed(world) -> int:
	return (world.w["removed"] as Dictionary).size()


## Open the beacon through its own API and run the one step that takes the open edge.
## Returns the collapse start tick (the world's tick on that step).
func _open(world) -> int:
	world.lstate.beacon.open(int(world.lstate.tick))
	world.step(DT)
	return int(world.lstate.tick)


func _steps(world, n: int) -> void:
	for _i in n:
		world.step(DT)


# ---- legs 1-3: before, the open tick, the 5 s boundary -------------------------------

func _legs_1_2_3(f: Array[String]) -> void:
	var world = _build(1, 5)
	if world == null:
		f.append("legs 1-3: build failed")
		return
	_steps(world, 30)
	# leg 1 (negative control): the beacon is closed, nothing has started
	if world.lstate.beacon.is_open():
		f.append("leg 1: beacon already open before the test opened it")
	if _cracked(world) != 0 or _removed(world) != 0:
		f.append("leg 1: before open cracked=%d removed=%d, want 0/0" % [_cracked(world), _removed(world)])
	if CollapseScript.phase(world._collapse) != CollapseScript.PHASE_IDLE:
		f.append("leg 1: collapse phase %d before open, want idle" % CollapseScript.phase(world._collapse))
	if world.collapse_view == null or world.collapse_view.overlay.visible:
		f.append("leg 1: crack overlay missing or visible before the beacon opened")
	# leg 2: the open tick
	var t0 := _open(world)
	if int(world._collapse["start_tick"]) != t0:
		f.append("leg 2: collapse start tick %d != the open-edge tick %d" % [int(world._collapse["start_tick"]), t0])
	if _cracked(world) <= 0:
		f.append("leg 2: on the open tick cracked=%d, want > 0" % _cracked(world))
	if _removed(world) != 0:
		f.append("leg 2: on the open tick removed=%d, want 0" % _removed(world))
	if not world.collapse_view.overlay.visible:
		f.append("leg 2: crack overlay not visible on the open tick")
	var saw_cracked := false
	for e in world.last_events:
		if str(e.get("e", "")) == CollapseScript.EV_CRACKED:
			saw_cracked = true
	if not saw_cracked:
		f.append("leg 2: no platforms_cracked event on the open tick")
	# leg 3: the boundary, both sides
	_steps(world, 299)   # 5.0 s at 60 Hz, hard-coded: the contract, not the constant
	if int(world.lstate.tick) != t0 + 299:
		f.append("leg 3: tick bookkeeping: at %d, want %d" % [int(world.lstate.tick), t0 + 299])
	if _removed(world) != 0:
		f.append("leg 3: at open+299 removed=%d, want 0" % _removed(world))
	if _cracked(world) <= 0:
		f.append("leg 3: at open+299 nothing is cracked any more")
	world.step(DT)
	if int(world.lstate.tick) != t0 + 300:
		f.append("leg 3: tick bookkeeping: at %d, want %d" % [int(world.lstate.tick), t0 + 300])
	if _removed(world) <= 0:
		f.append("leg 3: at open+300 removed=%d, want > 0" % _removed(world))
	if _removed(world) != (world._collapse["keys"] as Array).size():
		f.append("leg 3: removed %d != collapse keys %d" % [_removed(world), (world._collapse["keys"] as Array).size()])
	# the drop is visible, then gone
	_steps(world, 10)
	if not world.collapse_view.visible or world.collapse_view.drop_offset() >= -0.2:
		f.append("leg 3: 10 ticks after the fall the rest mesh is not dropping (y=%.3f)" % world.collapse_view.drop_offset())
	_steps(world, 60)
	if world.collapse_view.visible:
		f.append("leg 3: the fallen platforms still render 70 ticks after the fall")
	_drop(world)


# ---- leg 4: the hub never cracks, never falls ----------------------------------------

func _leg_4(f: Array[String]) -> void:
	for c in CASES:
		var world = _build(int(c[0]), int(c[1]))
		if world == null:
			f.append("leg 4: build failed seed=%d level=%d" % [c[0], c[1]])
			continue
		var hub: int = CollapseScript.hub_piece(world.lv)
		var hub_keys := {}
		for t in world.lv["tiles"]:
			if int(t[4]) == hub:
				hub_keys[CollisionScript.tile_key(int(t[0]), int(t[1]), int(t[2]))] = true
		if hub < 0 or hub_keys.size() != 205:
			f.append("leg 4 s%d l%d: hub piece %d with %d tiles, want the 205-tile hub" % [c[0], c[1], hub, hub_keys.size()])
		var bad := 0
		var steps := 0
		_steps(world, 5)
		_open(world)
		while steps < CollapseScript.FALL_TICKS + 20:
			for k in CollapseScript.cracked_keys(world._collapse):
				if hub_keys.has(k):
					bad += 1
			for k in (world.w["removed"] as Dictionary).keys():
				if hub_keys.has(k):
					bad += 1
			world.step(DT)
			steps += 1
		if bad > 0:
			f.append("leg 4 s%d l%d: %d hub tile hits in the cracked/removed sets" % [c[0], c[1], bad])
		if _removed(world) <= 0:
			f.append("leg 4 s%d l%d: nothing fell (the leg proves nothing)" % [c[0], c[1]])
		var dead := 0
		for k in hub_keys.keys():
			var p: PackedStringArray = str(k).split(",")
			if not CollisionScript.tile_alive(world.w, int(p[0]), int(p[1]), int(p[2])):
				dead += 1
		if dead > 0:
			f.append("leg 4 s%d l%d: %d hub tiles not alive after the fall" % [c[0], c[1], dead])
		_drop(world)


# ---- legs 5 + 7: a parked player falls (collapse on) / stays (collapse off) ----------

## A flat non-hub tile with nothing over or around it that could move the player: no prop,
## no pad, no other tile in its column, at least 4 u from every mine slot and gift slot.
func _park_tile(world) -> Array:
	var hub: int = CollapseScript.hub_piece(world.lv)
	var col_n := {}
	for t in world.lv["tiles"]:
		var ck := "%d,%d" % [int(t[0]), int(t[1])]
		col_n[ck] = int(col_n.get(ck, 0)) + 1
	var avoid: Array = []
	for s in world.lstate.mines.slots:
		avoid.append(Vector2(float(s["x"]), float(s["z"])))
	for g in world.lv["gifts"]:
		avoid.append(Vector2(float(g["x"]), float(g["z"])))
	for t in world.lv["tiles"]:
		if int(t[4]) == hub or int(t[3]) != 0:
			continue
		var ck := "%d,%d" % [int(t[0]), int(t[1])]
		if int(col_n[ck]) != 1 or world.w["prop_cols"].has(ck) or world.w["pads"].has(ck):
			continue
		var here := Vector2(float(t[0]), float(t[1]))
		if here.length() < 12.0:
			continue
		var ok := true
		for a in avoid:
			if (a as Vector2).distance_to(here) < 4.0:
				ok = false
				break
		if ok:
			return [int(t[0]), int(t[1]), int(t[2])]
	return []


func _park(world, t: Array) -> void:
	var c = world.ctl
	c.x = float(t[0]) + 0.5
	c.y = float(t[2]) * 0.5
	c.z = float(t[1]) + 0.5
	c.vx = 0.0
	c.vy = 0.0
	c.vz = 0.0
	c.grounded = true
	c.cur_key = "%d,%d,%d" % [int(t[0]), int(t[1]), int(t[2])]
	c.sync_body()


## Steps until a void_fall event (or n ticks). Returns the tick it fired on, -1 if none.
func _wait_fall(world, n: int) -> int:
	for _i in n:
		world.step(DT)
		for e in world.last_events:
			if str(e.get("e", "")) == "void_fall":
				return int(world.lstate.tick)
		if bool(world.ctl.dead):
			return -2
	return -1


func _leg_5_7(f: Array[String]) -> void:
	for collapse_on in [true, false]:
		var tag := "leg 5" if collapse_on else "leg 7"
		var world = _build(1, 5, collapse_on)
		if world == null:
			f.append("%s: build failed" % tag)
			continue
		var t := _park_tile(world)
		if t.is_empty():
			f.append("%s: no parking tile found" % tag)
			_drop(world)
			continue
		_park(world, t)
		_steps(world, 10)
		if not bool(world.ctl.grounded) or absf(float(world.ctl.y) - float(t[2]) * 0.5) > 0.01:
			f.append("%s: the parked player is not standing on %s (y=%.3f)" % [tag, str(t), float(world.ctl.y)])
		var t0 := _open(world)
		var before := _wait_fall(world, CollapseScript.FALL_TICKS - 1)
		if before != -1:
			f.append("%s: the player fell/died at tick %d, before the fall tick %d" % [tag, before, t0 + 300])
		var fell := _wait_fall(world, 240)
		if collapse_on:
			if fell <= t0 + CollapseScript.FALL_TICKS:
				f.append("leg 5: no void_fall after the platform fell (got %d, fall tick %d)" % [fell, t0 + 300])
		else:
			if fell != -1:
				f.append("leg 7: collapse off, the player still fell (tick %d)" % fell)
			if _cracked(world) != 0 or _removed(world) != 0:
				f.append("leg 7: collapse off, cracked=%d removed=%d, want 0/0" % [_cracked(world), _removed(world)])
			if world.collapse_view != null:
				f.append("leg 7: collapse off, but a collapse view was built")
		_drop(world)


# ---- leg 6: determinism ---------------------------------------------------------------

func _leg_6(f: Array[String]) -> void:
	var snaps: Array = []
	for _r in 2:
		var world = _build(7, 3)
		if world == null:
			f.append("leg 6: build failed")
			return
		_steps(world, 17)
		_open(world)
		_steps(world, 150)
		var cracked: Array = CollapseScript.cracked_keys(world._collapse).duplicate()
		_steps(world, 200)
		var removed: Array = (world.w["removed"] as Dictionary).keys()
		removed.sort()
		snaps.append({"cracked": cracked, "removed": removed,
				"fall": int(world._collapse["fall_tick"]), "n": int(world._collapse["removed_n"])})
		_drop(world)
	if snaps[0]["cracked"].is_empty() or snaps[0]["removed"].is_empty():
		f.append("leg 6: empty sets - the determinism check proves nothing")
	if snaps[0]["cracked"] != snaps[1]["cracked"]:
		f.append("leg 6: cracked sets differ between identical runs")
	if snaps[0]["removed"] != snaps[1]["removed"]:
		f.append("leg 6: removed sets differ between identical runs")
	if snaps[0]["fall"] != snaps[1]["fall"] or snaps[0]["n"] != snaps[1]["n"]:
		f.append("leg 6: fall tick / count differ: %s vs %s" % [str(snaps[0]["fall"]), str(snaps[1]["fall"])])
