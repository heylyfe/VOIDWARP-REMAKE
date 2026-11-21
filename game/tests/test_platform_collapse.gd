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
#   leg 8  a gold gift on a fallen tile is LOST: not present, not collected, not paid
#   leg 9  a tripmine on a fallen tile is dropped: gone, and it cannot kill
#   leg 10 an enemy on a fallen tile falls and is retired past the kill plane - the same
#          behaviour for two different bodies
#   leg 11 negative control: collapse off -> the same gift, mine and enemy are untouched
#   leg 12 the gift quota is still met after a collapse (the beacon stays open)

const WorldScript := preload("res://app/world.gd")
const CollapseScript := preload("res://sim/collapse.gd")
const CollisionScript := preload("res://sim/collision.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const MinesScript := preload("res://sim/mines.gd")
const RtScript := preload("res://sim/enemy_runtime.gd")

const DT := 1.0 / 60.0
const CASES := [[1, 5], [7, 3], [42, 11]]   # [seed, level]


func run() -> Array[String]:
	var f: Array[String] = []
	_legs_1_2_3(f)
	_leg_4(f)
	_leg_5_7(f)
	_leg_6(f)
	_leg_8(f)
	_leg_9(f)
	_leg_10(f)
	_leg_11(f)
	_leg_12(f)
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


# ---- legs 8-12: what happens to everything standing on a platform that falls ----------
#
# The collapse itself only edits collision. The sweep that follows it (app/world.gd
# _collapse_sweep) is what decides the fate of the gifts and tripmines resting on those
# tiles; the enemy runtime's own support rule (sim/enemy_runtime.gd resting_key /
# _support_pass) decides the enemies'. These legs drive the real world, so they test the
# wiring, not a helper.

## Open the beacon the way play does: collect every real black gift (gifts.collect flips
## the phase to gold on the last one, which puts a gold gift at every real slot), then let
## the beacon open and take the open edge. Returns the collapse start tick.
func _open_gold(world) -> int:
	var g: RefCounted = world.lstate.gifts
	var ev: Array = []
	for i in g.slots.size():
		if g.is_real(i):
			g.collect(i, int(world.lstate.tick), 0, ev)
	world.lstate.beacon.open(int(world.lstate.tick))
	world.step(DT)
	return int(world.lstate.tick)


## A non-hub tile the collapse removes: [x, z, y_hu]. `avoid` skips keys already taken.
func _falling_tile(world, avoid: Array) -> Array:
	var hub: Dictionary = world._collapse["hub_keys"]
	for k in world._collapse["keys"]:
		if hub.has(k) or avoid.has(str(k)):
			continue
		var p: PackedStringArray = str(k).split(",")
		return [int(p[0]), int(p[1]), int(p[2])]
	return []


## The first PRESENT gift slot standing on a tile the collapse removes:
## [slot, x, z, y_hu], or [] when the level has none.
func _gift_on_falling_tile(world) -> Array:
	var g: RefCounted = world.lstate.gifts
	var keys: Dictionary = world._collapse["key_set"]
	for i in g.slots.size():
		if not g.present(i):
			continue
		var s: Dictionary = g.slots[i]
		if keys.has(CollisionScript.tile_key(int(s["x"]), int(s["z"]), int(s["y"]))):
			return [i, int(s["x"]), int(s["z"]), int(s["y"])]
	return []


## The first LIVE tripmine slot standing on a tile the collapse removes:
## [slot, x, z, y_hu], or [] when the level has none.
func _mine_on_falling_tile(world) -> Array:
	var m: RefCounted = world.lstate.mines
	var keys: Dictionary = world._collapse["key_set"]
	for slot_id in m.ids:
		if m.is_consumed(slot_id):
			continue
		var s: Dictionary = m.slots[slot_id]
		if keys.has(CollisionScript.tile_key(int(s["x"]), int(s["z"]), int(s["y"]))):
			return [slot_id, int(s["x"]), int(s["z"]), int(s["y"])]
	return []


## A no-op body of the given world height: it never moves on its own, so the only thing
## that can change its height is the support rule under test.
func _probe_cfg(height_u: float) -> Dictionary:
	return {"world_height": height_u, "frame_w": 256, "frame_h": 256,
			"body_rect": [0, 0, 256, 256], "contact_kill": false, "cycle_ticks": 0}


## Spawn a stationary probe body standing on tile [x, z, y_hu]. The id is a real content
## folder (so the billboard pass finds its sheet) but the behavior is the runtime's no-op
## fixture: nothing but the support rule under test can move the body.
func _probe(world, id: String, t: Array, height_u: float) -> Dictionary:
	world.bespoke_enemy_views = false
	return world.rt.spawn_at(id, id, RtScript.FixtureBehavior.new(), _probe_cfg(height_u),
			Vector3(float(t[0]) + 0.5, CollisionScript.tile_top(int(t[2])), float(t[1]) + 0.5))


# ---- leg 8: a gold gift on a fallen tile is lost --------------------------------------

func _leg_8(f: Array[String]) -> void:
	var world = _build(1, 5)
	if world == null:
		f.append("leg 8: build failed")
		return
	var g: RefCounted = world.lstate.gifts
	_open_gold(world)
	if g.phase != GiftsScript.PHASE_GOLD:
		f.append("leg 8: phase %s after collecting every black gift, want gold" % g.phase)
	var pick := _gift_on_falling_tile(world)
	if pick.is_empty():
		f.append("leg 8: no present gift slot on a tile the collapse removes")
		_drop(world)
		return
	var slot: int = int(pick[0])
	if not g.present(slot) or g.is_lost(slot):
		f.append("leg 8: the picked gift is not present before the fall")
	# the whole crack phase: the gift is still in the air over a live tile
	_steps(world, CollapseScript.FALL_TICKS - 1)
	if not g.present(slot) or g.is_lost(slot):
		f.append("leg 8: the gift was lost before the fall tick")
	world.step(DT)
	if not g.is_lost(slot):
		f.append("leg 8: the gift on a fallen tile was not lost (it hangs in the air)")
	if g.present(slot):
		f.append("leg 8: the lost gift still reads present - the view would draw it")
	if g.collected(slot):
		f.append("leg 8: the lost gift reads collected - it must not pay gold")
	# and it stays lost: nothing restores it on a later tick
	_steps(world, 30)
	if not g.is_lost(slot) or g.present(slot):
		f.append("leg 8: the lost gift came back 30 ticks later")
	_drop(world)


# ---- leg 9: a tripmine on a fallen tile is gone and cannot kill ------------------------

func _leg_9(f: Array[String]) -> void:
	var world = _build(1, 5)
	if world == null:
		f.append("leg 9: build failed")
		return
	var m: RefCounted = world.lstate.mines
	_open_gold(world)
	var pick := _mine_on_falling_tile(world)
	if pick.is_empty():
		f.append("leg 9: no live tripmine on a tile the collapse removes")
		_drop(world)
		return
	var slot: int = int(pick[0])
	var mx := float(int(pick[1])) + 0.5
	var mz := float(int(pick[2])) + 0.5
	if m.contact_at(mx, mz) != slot:
		f.append("leg 9: the mine does not trigger at its own point before the fall (the leg proves nothing)")
	_steps(world, CollapseScript.FALL_TICKS - 1)
	if m.is_consumed(slot):
		f.append("leg 9: the mine was dropped before the fall tick")
	world.step(DT)
	if not m.is_consumed(slot):
		f.append("leg 9: the mine on a fallen tile was not dropped (it hangs in the air)")
	if m.contact_at(mx, mz) != -1:
		f.append("leg 9: a dropped mine still triggers at its own point")
	# a player standing exactly where the mine was takes no mine event at all
	_park(world, [int(pick[1]), int(pick[2]), int(pick[3])])
	var hit := ""
	for _i in 20:
		world.step(DT)
		for e in world.last_events:
			var k := str(e.get("e", ""))
			if k == MinesScript.EV_MINE_CONTACT or k == MinesScript.EV_MINE_DETONATED:
				hit = k
	if hit != "":
		f.append("leg 9: a player standing where the fallen mine was still took a %s event" % hit)
	_drop(world)


# ---- leg 10: an enemy on a fallen tile falls, the same for two different bodies --------

func _leg_10(f: Array[String]) -> void:
	var world = _build(1, 5)
	if world == null:
		f.append("leg 10: build failed")
		return
	_open_gold(world)
	# the probes go down a few ticks before the fall, so nothing but the support rule can
	# move them: their behavior is a no-op
	_steps(world, CollapseScript.FALL_TICKS - 6)
	var ta := _falling_tile(world, [])
	if ta.is_empty():
		f.append("leg 10: no falling tile in the level")
		_drop(world)
		return
	var tb := _falling_tile(world, [CollisionScript.tile_key(int(ta[0]), int(ta[1]), int(ta[2]))])
	if tb.is_empty():
		f.append("leg 10: fewer than two falling tiles in the level")
		_drop(world)
		return
	var a: Dictionary = _probe(world, "gift_larper", ta, 1.0)
	var b: Dictionary = _probe(world, "toucher", tb, 2.0)
	var ya := float(a["y"])
	var yb := float(b["y"])
	var ia: int = (world.rt.enemies as Array).find(a)
	_steps(world, 6)
	if not bool(a.get("falling", false)) or not bool(b.get("falling", false)):
		f.append("leg 10: an enemy on a fallen tile did not start falling (it floats)")
	# the view: a falling body is still drawn (you watch it drop), a retired one is not
	if ia < 0 or ia >= world.boards.size() or world.boards[ia] == null:
		f.append("leg 10: the falling probe has no board (the view leg proves nothing)")
	elif not (world.boards[ia] as Node3D).visible:
		f.append("leg 10: a falling body was hidden before it reached the kill plane")
	# Step until both are retired instead of for a fixed count. The assertion at the end is
	# about what the view does to a RETIRED body, so the test should wait for the retirement
	# rather than assume a tick count: the fall is FALL_SPEED from the tile top, so a fixed
	# count silently couples the view assertion to the level's height. 300 ticks is 200 u of
	# travel - past the kill plane from any tile in the level - so the cap cannot hide a body
	# that never falls; the `gone` assertion below still fires for that.
	var waited := 0
	while waited < 300 and not (bool(a.get("gone", false)) and bool(b.get("gone", false))):
		world.step(DT)
		waited += 1
	if not bool(a.get("gone", false)) or not bool(b.get("gone", false)):
		f.append("leg 10: an enemy never reached the kill plane (a=%s b=%s)"
				% [str(a.get("gone", false)), str(b.get("gone", false))])
	if float(a["y"]) >= ya or float(b["y"]) >= yb:
		f.append("leg 10: an enemy did not lose height (a %.2f->%.2f b %.2f->%.2f)"
				% [ya, float(a["y"]), yb, float(b["y"])])
	if bool(a.get("gone", false)) != bool(b.get("gone", false)):
		f.append("leg 10: the two bodies behaved differently")
	var live: Array = world.w["enemies"]
	if live.has(a["body_mirror"]) or live.has(b["body_mirror"]):
		f.append("leg 10: a fallen enemy is still a live body in w[\"enemies\"]")
	# ...and it is not drawn 40 u below the level either
	if ia >= 0 and ia < world.boards.size() and world.boards[ia] != null:
		if (world.boards[ia] as Node3D).visible:
			f.append("leg 10: a body past the kill plane is still drawn below the level")
	_drop(world)


# ---- leg 11: negative control - collapse off, nothing is touched -----------------------

func _leg_11(f: Array[String]) -> void:
	var world = _build(1, 5, false)
	if world == null:
		f.append("leg 11: build failed")
		return
	var g: RefCounted = world.lstate.gifts
	var m: RefCounted = world.lstate.mines
	_open_gold(world)
	var gp := _gift_on_falling_tile(world)
	var mp := _mine_on_falling_tile(world)
	var ta := _falling_tile(world, [])
	if gp.is_empty() or mp.is_empty() or ta.is_empty():
		f.append("leg 11: the level has no gift/mine/tile to control against")
		_drop(world)
		return
	var gslot: int = int(gp[0])
	var mslot: int = int(mp[0])
	var mx := float(int(mp[1])) + 0.5
	var mz := float(int(mp[2])) + 0.5
	var probe: Dictionary = _probe(world, "gift_larper", ta, 1.0)
	var y0 := float(probe["y"])
	# the same number of ticks the collapse legs run, plus the fall window
	_steps(world, CollapseScript.FALL_TICKS + 96)
	if _removed(world) != 0:
		f.append("leg 11: collapse off, removed=%d, want 0" % _removed(world))
	if g.is_lost(gslot) or not g.present(gslot):
		f.append("leg 11: collapse off, the gift was still lost")
	if m.is_consumed(mslot):
		f.append("leg 11: collapse off, the mine was still dropped")
	if m.contact_at(mx, mz) != mslot:
		f.append("leg 11: collapse off, the mine no longer triggers at its own point")
	if bool(probe.get("falling", false)) or bool(probe.get("gone", false)):
		f.append("leg 11: collapse off, the enemy still fell")
	if absf(float(probe["y"]) - y0) > 0.001:
		f.append("leg 11: collapse off, the enemy's height changed (%.3f -> %.3f)"
				% [y0, float(probe["y"])])
	if not (world.w["enemies"] as Array).has(probe["body_mirror"]):
		f.append("leg 11: collapse off, the enemy left the live body list")
	_drop(world)


# ---- leg 12: the gift quota is still met after a collapse ------------------------------

func _leg_12(f: Array[String]) -> void:
	var world = _build(1, 5)
	if world == null:
		f.append("leg 12: build failed")
		return
	var g: RefCounted = world.lstate.gifts
	var quota := int(g.total_real)   # the default rule: every real black gift
	_open_gold(world)
	var collected_black := 0
	for i in g.slots.size():
		if g.is_real(i) and GiftsScript.bit_get(g.black_taken, i):
			collected_black += 1
	if collected_black < quota:
		f.append("leg 12: %d black gifts collected, quota %d - the beacon should not have opened"
				% [collected_black, quota])
	_steps(world, CollapseScript.FALL_TICKS + 5)
	var present_n := 0
	var lost_n := 0
	var gold_n := 0
	for i in g.slots.size():
		if not g.is_real(i):
			continue
		if g.is_lost(i):
			lost_n += 1
		elif g.collected(i):
			gold_n += 1
		else:
			present_n += 1
	if lost_n <= 0:
		f.append("leg 12: the collapse lost no gift (the leg proves nothing)")
	if present_n + lost_n + gold_n != quota:
		f.append("leg 12: present %d + lost %d + collected %d != quota %d"
				% [present_n, lost_n, gold_n, quota])
	if g.remaining() != present_n:
		f.append("leg 12: remaining() %d != the %d present gifts" % [g.remaining(), present_n])
	# the quota was met BEFORE the collapse and losing gifts cannot un-meet it
	if not g.all_black_collected():
		f.append("leg 12: the quota is no longer met after the collapse")
	if not world.lstate.beacon.is_open():
		f.append("leg 12: the beacon closed after the collapse")
	if collected_black < quota:
		f.append("leg 12: collected %d < quota %d after the collapse" % [collected_black, quota])
	# The HUD counter must not count a lost gift as collected. It reads the real collected
	# count (app/world.gd _sync_hud); the old total_real - remaining() arithmetic would
	# report lost_n gifts the player never took.
	world._sync_hud()
	var want := "%d / %d" % [gold_n, quota]
	var got_text: String = world.hud.gift_counter.counter_text()
	if got_text != want:
		f.append("leg 12: HUD counter '%s', want '%s' (a lost gift must not read as collected)"
				% [got_text, want])
	if got_text == "%d / %d" % [gold_n + lost_n, quota]:
		f.append("leg 12: HUD counter counts the %d lost gifts as collected" % lost_n)
	_drop(world)
