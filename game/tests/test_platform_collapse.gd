extends RefCounted
#
# Platform collapse after the beacon opens (sim/collapse.gd, view/collapse_view.gd, wired in
# app/world.gd). Driven through world.build() / world.step() only.
# The collapse is SEQUENTIAL, outside in (D-B10-1, supersedes D-B6-2): zone 0 (the farthest
# band) cracks on the open tick and falls 300 ticks later, the next zone cracks 600 ticks after
# that, and so on inward. Legs 1-12 were written for the one global fall; they now assert the
# first zone's fall (the same 5 s boundary) and legs 13-15 cover the rest of the schedule.
#   leg 1  before the beacon opens: nothing cracked, nothing removed (negative control)
#   leg 2  the open tick: ONLY zone 0 is cracked, removed == 0, only its overlay is visible
#   leg 3  open + 299: removed == 0; open + 300: removed == zone 0 exactly, the inner zones
#          still stand and still render (the 5 s boundary, both sides)
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
#   leg 13 the whole schedule, tick by tick, 3 seeds/levels: one zone cracking at a time,
#          zone i cracks on open + 900 i and falls on open + 900 i + 300, removed == the
#          fallen zones exactly, zones in outside-in order, whole pieces only, the hub left
#   leg 14 the zone-count rule and the numbers come from data/collapse.json
#   leg 15 the state hash carries the schedule (COLLAPSE line) and is replay-deterministic
#   leg 16 the per-zone meshes partition the non-hub level: summed over the zones they mesh
#          exactly what the one PART_REST build meshes (tile tops, ramps, props, pads, spikes)
#   leg 17 the hash pins the collapse CONFIG, not just the live schedule: enabled, the crack
#          and gap seconds and the zone width each change the hash (B10 review finding 1)

const WorldScript := preload("res://app/world.gd")
const CollapseScript := preload("res://sim/collapse.gd")
const CollisionScript := preload("res://sim/collision.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const MinesScript := preload("res://sim/mines.gd")
const RtScript := preload("res://sim/enemy_runtime.gd")

const DT := 1.0 / 60.0
const CASES := [[1, 5], [7, 3], [42, 11]]   # [seed, level]
# The contract at 60 Hz, hard-coded on purpose (leg 14 checks the data says the same):
const CRACK := 300   # 5.0 s from a zone's cracks to its fall
const GAP := 600     # 10.0 s from a fall to the next zone's cracks
const HashScript := preload("res://sim/state_hash.gd")
const RunStateScript := preload("res://sim/run_state.gd")
const VoidGenScript := preload("res://terrain/voidgen.gd")
const MesherScript := preload("res://view/level_mesher.gd")


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
	_leg_13(f)
	_leg_14(f)
	_leg_15(f)
	_leg_16(f)
	_leg_17(f)
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
	if world.collapse_view == null or world.collapse_view.any_overlay_visible():
		f.append("leg 1: crack overlay missing or visible before the beacon opened")
	# leg 2: the open tick
	var t0 := _open(world)
	if int(world._collapse["start_tick"]) != t0:
		f.append("leg 2: collapse start tick %d != the open-edge tick %d" % [int(world._collapse["start_tick"]), t0])
	if _cracked(world) <= 0:
		f.append("leg 2: on the open tick cracked=%d, want > 0" % _cracked(world))
	var nz := CollapseScript.zone_count(world._collapse)
	if nz < 2:
		f.append("leg 2: %d zone(s) on seed 1 level 5 - the sequential legs prove nothing" % nz)
	if CollapseScript.cracked_keys(world._collapse) != CollapseScript.zone_keys(world._collapse, 0):
		f.append("leg 2: the cracked set on the open tick is not exactly zone 0")
	if _cracked(world) >= (world._collapse["keys"] as Array).size():
		f.append("leg 2: every listed tile cracked on the open tick (the old global collapse)")
	if _removed(world) != 0:
		f.append("leg 2: on the open tick removed=%d, want 0" % _removed(world))
	if not world.collapse_view.zone_overlay_visible(0):
		f.append("leg 2: zone 0's crack overlay not visible on the open tick")
	for zi in range(1, nz):
		if world.collapse_view.zone_overlay_visible(zi):
			f.append("leg 2: zone %d's overlay is visible on the open tick (only zone 0 cracks)" % zi)
	var saw_cracked := false
	for e in world.last_events:
		if str(e.get("e", "")) == CollapseScript.EV_CRACKED and int(e.get("zone", -1)) == 0:
			saw_cracked = true
	if not saw_cracked:
		f.append("leg 2: no zone-0 platforms_cracked event on the open tick")
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
	var z0: Array = CollapseScript.zone_keys(world._collapse, 0)
	if _removed(world) != z0.size():
		f.append("leg 3: removed %d != zone 0's %d keys" % [_removed(world), z0.size()])
	for k in z0:
		if not (world.w["removed"] as Dictionary).has(k):
			f.append("leg 3: a zone-0 key %s is not removed at open+300" % str(k))
			break
	if _removed(world) >= (world._collapse["keys"] as Array).size():
		f.append("leg 3: every listed tile fell at open+300 (the old global collapse)")
	if _cracked(world) != 0:
		f.append("leg 3: cracked=%d right after zone 0 fell, want 0 (the 10 s gap)" % _cracked(world))
	# the drop is visible, then gone; the next zone stands and renders at rest
	_steps(world, 10)
	if not world.collapse_view.zone_visible(0) or world.collapse_view.drop_offset(0) >= -0.2:
		f.append("leg 3: 10 ticks after the fall zone 0 is not dropping (y=%.3f)" % world.collapse_view.drop_offset(0))
	_steps(world, 60)
	if world.collapse_view.zone_visible(0):
		f.append("leg 3: the fallen zone 0 still renders 70 ticks after the fall")
	if nz >= 2 and (not world.collapse_view.zone_visible(1) or world.collapse_view.drop_offset(1) != 0.0):
		f.append("leg 3: zone 1 is hidden or moving 70 ticks after zone 0 fell")
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
		while steps < CRACK + 20:
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
## Taken from the EARLIEST zone in fall order that has one: [x, z, y_hu, zone].
func _park_tile(world) -> Array:
	for zi in CollapseScript.zone_count(world._collapse):
		var t := _park_tile_in(world, zi)
		if not t.is_empty():
			return t
	return []


func _park_tile_in(world, zone: int) -> Array:
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
		if CollapseScript.zone_of(world._collapse,
				CollisionScript.tile_key(int(t[0]), int(t[1]), int(t[2]))) != zone:
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
			return [int(t[0]), int(t[1]), int(t[2]), zone]
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
		var off := _off(int(t[3]))
		if collapse_on and CollapseScript.zone_fall_offset(world._collapse, int(t[3])) != off:
			f.append("leg 5: zone %d's fall offset %d, want %d" % [int(t[3]),
					CollapseScript.zone_fall_offset(world._collapse, int(t[3])), off])
		var t0 := _open(world)
		var before := _wait_fall(world, off - 1)
		if before != -1:
			f.append("%s: the player fell/died at tick %d, before the fall tick %d" % [tag, before, t0 + off])
		var fell := _wait_fall(world, 240)
		if collapse_on:
			if fell <= t0 + off:
				f.append("leg 5: no void_fall after the platform fell (got %d, fall tick %d)" % [fell, t0 + off])
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


## A non-hub tile the collapse removes FIRST (zone 0, open + 300): [x, z, y_hu]. `avoid`
## skips keys already taken.
func _falling_tile(world, avoid: Array) -> Array:
	var hub: Dictionary = world._collapse["hub_keys"]
	for k in CollapseScript.zone_keys(world._collapse, 0):
		if hub.has(k) or avoid.has(str(k)):
			continue
		var p: PackedStringArray = str(k).split(",")
		return [int(p[0]), int(p[1]), int(p[2])]
	return []


## The first PRESENT gift slot standing on a tile of the EARLIEST-falling zone that has one:
## [slot, x, z, y_hu, zone], or [] when the level has none.
func _gift_on_falling_tile(world) -> Array:
	var g: RefCounted = world.lstate.gifts
	for zi in CollapseScript.zone_count(world._collapse):
		var keys: Dictionary = world._collapse["zones"][zi]["key_set"]
		for i in g.slots.size():
			if not g.present(i):
				continue
			var s: Dictionary = g.slots[i]
			if keys.has(CollisionScript.tile_key(int(s["x"]), int(s["z"]), int(s["y"]))):
				return [i, int(s["x"]), int(s["z"]), int(s["y"]), zi]
	return []


## The first LIVE tripmine slot standing on a tile of the EARLIEST-falling zone that has one:
## [slot, x, z, y_hu, zone], or [] when the level has none.
func _mine_on_falling_tile(world) -> Array:
	var m: RefCounted = world.lstate.mines
	for zi in CollapseScript.zone_count(world._collapse):
		var keys: Dictionary = world._collapse["zones"][zi]["key_set"]
		for slot_id in m.ids:
			if m.is_consumed(slot_id):
				continue
			var s: Dictionary = m.slots[slot_id]
			if keys.has(CollisionScript.tile_key(int(s["x"]), int(s["z"]), int(s["y"]))):
				return [slot_id, int(s["x"]), int(s["z"]), int(s["y"]), zi]
	return []


## Ticks from the open edge to zone zi's fall (the contract: zi x 900 + 300).
func _off(zi: int) -> int:
	return zi * (CRACK + GAP) + CRACK


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
	# up to its zone's fall: the gift is still in the air over a live tile
	_steps(world, _off(int(pick[4])) - 1)
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
	_steps(world, _off(int(pick[4])) - 1)
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
	_steps(world, CRACK - 6)
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
	_steps(world, maxi(_off(int(gp[4])), _off(int(mp[4]))) + 96)
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
	_steps(world, CRACK + 5)
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


# ---- leg 13: the whole sequential schedule, tick by tick ---------------------------------

## The XZ distance from the dais centre to piece pid's nearest tile, computed here from the
## Level dict (independent of sim/collapse.gd).
func _piece_dist(lv: Dictionary) -> Dictionary:
	var b: Array = lv["beacon"]
	var out := {}
	for t in lv["tiles"]:
		var d := Vector2(float(int(t[0]) - int(b[0])), float(int(t[1]) - int(b[1]))).length()
		var pid := int(t[4])
		if not out.has(pid) or d < float(out[pid]):
			out[pid] = d
	return out


func _leg_13(f: Array[String]) -> void:
	for c in CASES:
		var tag := "leg 13 s%d l%d" % [c[0], c[1]]
		var world = _build(int(c[0]), int(c[1]))
		if world == null:
			f.append("%s: build failed" % tag)
			continue
		var st: Dictionary = world._collapse
		var nz := CollapseScript.zone_count(st)
		if nz < 2:
			f.append("%s: %d zone(s), the schedule proves nothing" % [tag, nz])
		# whole pieces only, and outside in: every piece of zone i is at least as far as
		# every piece of zone i + 1; the hub piece is in no zone
		var pd := _piece_dist(world.lv)
		var hub: int = CollapseScript.hub_piece(world.lv)
		var piece_zone := {}
		for t in world.lv["tiles"]:
			var zi := CollapseScript.zone_of(st, CollisionScript.tile_key(int(t[0]), int(t[1]), int(t[2])))
			var pid := int(t[4])
			if pid == hub:
				if zi != -1:
					f.append("%s: a hub tile is in zone %d" % [tag, zi])
					break
				continue
			if piece_zone.has(pid) and int(piece_zone[pid]) != zi:
				f.append("%s: piece %d is split across zones %d and %d" % [tag, pid, piece_zone[pid], zi])
				break
			piece_zone[pid] = zi
		for i in range(nz - 1):
			var lo := INF
			var hi := -INF
			for pid in piece_zone:
				if int(piece_zone[pid]) == i:
					lo = minf(lo, float(pd[pid]))
				elif int(piece_zone[pid]) == i + 1:
					hi = maxf(hi, float(pd[pid]))
			if lo < hi:
				f.append("%s: zone %d (nearest %.2f) is closer than zone %d (farthest %.2f) - not outside in"
						% [tag, i, lo, i + 1, hi])
		_steps(world, 3)
		var t0 := _open(world)
		var last := t0 + (nz - 1) * (CRACK + GAP) + CRACK
		var errs := 0
		var cracked_ticks := 0
		while int(world.lstate.tick) <= last + 2 and errs < 4:
			var now := int(world.lstate.tick) - t0
			@warning_ignore("integer_division")
			var k := now / (CRACK + GAP)
			var in_crack := k < nz and now % (CRACK + GAP) < CRACK
			var fallen := 0
			if now >= CRACK:
				@warning_ignore("integer_division")
				fallen = mini(nz, (now + GAP) / (CRACK + GAP))
			var ck: Array = CollapseScript.cracked_keys(st)
			if in_crack:
				cracked_ticks += 1
				if ck != CollapseScript.zone_keys(st, k):
					f.append("%s: tick +%d the cracked set is not exactly zone %d" % [tag, now, k])
					errs += 1
			elif not ck.is_empty():
				f.append("%s: tick +%d something is cracked during a gap" % [tag, now])
				errs += 1
			var want := 0
			for i in fallen:
				want += CollapseScript.zone_keys(st, i).size()
			if _removed(world) != want:
				f.append("%s: tick +%d removed=%d, want the %d fallen zones' %d keys"
						% [tag, now, _removed(world), fallen, want])
				errs += 1
			var shown := 0
			for i in nz:
				if world.collapse_view.zone_overlay_visible(i) and world.collapse_view.zone_visible(i) \
						and CollapseScript.zone_phase(st, i) != CollapseScript.ZONE_FALLEN:
					shown += 1
			if shown != (1 if in_crack else 0):
				f.append("%s: tick +%d %d zone overlays showing, want %d" % [tag, now, shown, 1 if in_crack else 0])
				errs += 1
			world.step(DT)
		if cracked_ticks != nz * CRACK:
			f.append("%s: %d cracked ticks, want %d zones x %d" % [tag, cracked_ticks, nz, CRACK])
		if CollapseScript.phase(st) != CollapseScript.PHASE_FALLEN:
			f.append("%s: phase %d after the last zone, want fallen" % [tag, CollapseScript.phase(st)])
		if _removed(world) != (st["keys"] as Array).size():
			f.append("%s: at the end removed=%d, want every listed key %d" % [tag, _removed(world), (st["keys"] as Array).size()])
		for hk in (st["hub_keys"] as Dictionary).keys():
			var p: PackedStringArray = str(hk).split(",")
			if not CollisionScript.tile_alive(world.w, int(p[0]), int(p[1]), int(p[2])):
				f.append("%s: a hub tile is gone at the end" % tag)
				break
		_drop(world)


# ---- leg 14: the numbers and the zone-count rule are data ---------------------------------

func _leg_14(f: Array[String]) -> void:
	var cfg: Dictionary = CollapseScript.config()
	if float(cfg.get("crack_to_fall_s", -1.0)) != 5.0 or float(cfg.get("gap_after_fall_s", -1.0)) != 10.0:
		f.append("leg 14: data/collapse.json crack/gap %s/%s, want the owner's 5.0/10.0"
				% [str(cfg.get("crack_to_fall_s")), str(cfg.get("gap_after_fall_s"))])
	var lv: Dictionary = VoidGenScript.generate(1, 5, 1, 0)
	var st: Dictionary = CollapseScript.create(lv)
	if int(st["crack_ticks"]) != CRACK or int(st["gap_ticks"]) != GAP:
		f.append("leg 14: state ticks %d/%d, want %d/%d" % [int(st["crack_ticks"]), int(st["gap_ticks"]), CRACK, GAP])
	# the count rule: ceil(radius / width), clamped
	var wu := float(cfg["zone_width_u"])
	var zmax := int(cfg["zone_max"])
	if CollapseScript.zone_count_for(0.5 * wu) != maxi(1, int(cfg["zone_min"])):
		f.append("leg 14: a half-width level is not the minimum zone count")
	if CollapseScript.zone_count_for(2.5 * wu) != mini(3, zmax):
		f.append("leg 14: a 2.5-width level has %d zones, want 3" % CollapseScript.zone_count_for(2.5 * wu))
	if CollapseScript.zone_count_for(100.0 * wu) != zmax:
		f.append("leg 14: a huge level is not capped at zone_max %d" % zmax)
	if int(st["bands"]) != CollapseScript.zone_count_for(float(st["radius"])):
		f.append("leg 14: seed 1 level 5 uses %d bands, the rule says %d"
				% [int(st["bands"]), CollapseScript.zone_count_for(float(st["radius"]))])
	# a different data row changes the partition (the rule reads the data, not a constant)
	var one: Dictionary = CollapseScript.create(lv, {"crack_to_fall_s": 2.0, "gap_after_fall_s": 0.0,
			"zone_width_u": 1000.0, "zone_min": 1, "zone_max": 6})
	if CollapseScript.zone_count(one) != 1 or int(one["crack_ticks"]) != 120 or int(one["gap_ticks"]) != 0:
		f.append("leg 14: an override cfg was not honoured (zones=%d crack=%d gap=%d)"
				% [CollapseScript.zone_count(one), int(one["crack_ticks"]), int(one["gap_ticks"])])
	if (one["keys"] as Array) != (st["keys"] as Array):
		f.append("leg 14: the listed key set depends on the zone rule (it must not)")


# ---- leg 15: the state hash carries the schedule ------------------------------------------

func _hash_run(lvl_dict: Dictionary, upto: int) -> Array:
	var rs = RunStateScript.new_run(1, 1, [])
	rs.load_level(lvl_dict, 5)
	var cw := CollisionScript.make_world(lvl_dict["tiles"], lvl_dict["props"], lvl_dict["pads"],
			{"dais": lvl_dict["beacon"]})
	rs.level.collapse = CollapseScript.create(lvl_dict)
	var out: Array = [HashScript.sha256(rs)]
	CollapseScript.start(rs.level.collapse, 10)
	out.append(HashScript.sha256(rs))
	for t in range(11, upto):
		CollapseScript.tick(rs.level.collapse, t, cw)
	out.append(HashScript.sha256(rs))
	var has_line := false
	for line in HashScript.dump(rs):
		if str(line).begins_with("COLLAPSE "):
			has_line = true
	out.append(has_line)
	return out


func _leg_15(f: Array[String]) -> void:
	var lv: Dictionary = VoidGenScript.generate(1, 5, 1, 0)
	var a := _hash_run(lv, 10 + CRACK + 1)
	var b := _hash_run(lv, 10 + CRACK + 1)
	if not bool(a[3]):
		f.append("leg 15: no COLLAPSE line in the state dump")
	if a[0] == a[1]:
		f.append("leg 15: the hash did not change when the collapse started")
	if a[1] == a[2]:
		f.append("leg 15: the hash did not change when zone 0 fell")
	if a != b:
		f.append("leg 15: two identical runs hash differently")
	# negative control: without a collapse state there is no COLLAPSE line
	var rs = RunStateScript.new_run(1, 1, [])
	rs.load_level(lv, 5)
	for line in HashScript.dump(rs):
		if str(line).begins_with("COLLAPSE "):
			f.append("leg 15: a level with no collapse state still dumps a COLLAPSE line")


# ---- leg 16: the per-zone meshes partition the rest of the level ---------------------------

func _leg_16(f: Array[String]) -> void:
	for c in CASES:
		var lv: Dictionary = VoidGenScript.generate(int(c[0]), int(c[1]), 1, 0)
		var st: Dictionary = CollapseScript.create(lv)
		var rest: Dictionary = MesherScript.build(lv, {}, MesherScript.PART_REST)
		var sums := {"tiles_top": 0, "ramps": 0, "props": 0, "pads": 0, "spikes": 0}
		for zi in CollapseScript.zone_count(st):
			var zb: Dictionary = MesherScript.build(lv, {}, MesherScript.PART_ZONE, st["zones"][zi]["pieces"])
			if int(zb["tiles_top"]) + int(zb["ramps"]) <= 0:
				f.append("leg 16 s%d l%d: zone %d meshes no tile" % [c[0], c[1], zi])
			for k in sums:
				var v: Variant = zb[k]
				sums[k] = int(sums[k]) + ((v as Array).size() if v is Array else int(v))
		for k in sums:
			var rv: Variant = rest[k]
			var want: int = (rv as Array).size() if rv is Array else int(rv)
			if int(sums[k]) != want:
				f.append("leg 16 s%d l%d: zones mesh %s=%d, PART_REST meshes %d"
						% [c[0], c[1], k, int(sums[k]), want])
		# The count check above cannot see a dropped piece cancelled by a duplicated one, and
		# the mesher filters by PIECE id, so the partition has to hold at piece level too
		# (B10 review finding 4): every piece that has tiles is in exactly one zone, and the
		# hub is in none. A prop-only piece has no tiles and is legitimately in no zone.
		var hub := CollapseScript.hub_piece(lv)
		var has_tile := {}
		for t in lv["tiles"]:
			has_tile[int(t[4])] = true
		var seen_piece := {}
		for zi in CollapseScript.zone_count(st):
			for pid in (st["zones"][zi]["pieces"] as Dictionary):
				if seen_piece.has(pid):
					f.append("leg 16 s%d l%d: piece %d is in zone %d and zone %d"
							% [c[0], c[1], int(pid), int(seen_piece[pid]), zi])
				seen_piece[pid] = zi
		for p in lv["pieces"]:
			var pid2 := int(p["id"])
			if pid2 == hub:
				if seen_piece.has(pid2):
					f.append("leg 16 s%d l%d: the hub piece %d is in a zone" % [c[0], c[1], pid2])
				continue
			if has_tile.has(pid2) and not seen_piece.has(pid2):
				f.append("leg 16 s%d l%d: piece %d has tiles but is in no zone (it never falls)"
						% [c[0], c[1], pid2])
		# negative control: an empty zone set meshes nothing
		var none: Dictionary = MesherScript.build(lv, {}, MesherScript.PART_ZONE, {})
		if int(none["tiles_top"]) != 0 or int(none["props"]) != 0:
			f.append("leg 16 s%d l%d: an empty zone set still meshed geometry" % [c[0], c[1]])


# ---- leg 17: the hash pins the collapse CONFIG, not just the live schedule -----------------

## The state hash of a level whose collapse was created with `cfg` and `enabled`. No world is
## needed: the dump reads only the LevelState fields.
func _hash_cfg(lvl_dict: Dictionary, cfg: Dictionary, enabled: bool) -> String:
	var rs = RunStateScript.new_run(1, 1, [])
	rs.load_level(lvl_dict, 5)
	var st: Dictionary = CollapseScript.create(lvl_dict, cfg)
	st["enabled"] = enabled
	rs.level.collapse = st
	return HashScript.sha256(rs)


## B10 review finding 1: the COLLAPSE line used to carry only the live schedule, so two runs
## whose collapse.json differed hashed the same until the first zone fell and then diverged.
## enabled decides whether start() changes the world at all, and the crack/gap seconds and the
## zone width are DATA, not a function of the Level - each must move the hash on its own.
func _leg_17(f: Array[String]) -> void:
	var lv: Dictionary = VoidGenScript.generate(1, 5, 1, 0)
	var base := _hash_cfg(lv, {}, true)
	if _hash_cfg(lv, {}, false) == base:
		f.append("leg 17: collapse enabled and disabled hash the same (the review collision)")
	if _hash_cfg(lv, {"crack_to_fall_s": 4.0}, true) == base:
		f.append("leg 17: a 4 s crack and a 5 s crack hash the same")
	if _hash_cfg(lv, {"gap_after_fall_s": 9.0}, true) == base:
		f.append("leg 17: a 9 s gap and a 10 s gap hash the same")
	if _hash_cfg(lv, {"zone_width_u": 8.0}, true) == base:
		f.append("leg 17: an 8 u zone width and a 16 u zone width hash the same")
	if _hash_cfg(lv, {"zone_max": 2}, true) == base:
		f.append("leg 17: a 2-zone cap and a 6-zone cap hash the same")
	# and the same config twice must agree, or the digest is not deterministic
	if _hash_cfg(lv, {}, true) != base:
		f.append("leg 17: the same collapse config hashed differently twice")
