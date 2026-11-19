extends RefCounted
#
# HUD radar wiring test (headless): the scripted radar and footprint roles got their
# views (radar_arrows.gd, cartographer_map.gd) long before hud.gd instantiated them or
# world.gd fed them - nothing called them, so the radars were dead in the shipped game
# (the same defect class as the views with no caller). Every leg builds a real level
# through world.build() and drives world.step(); nothing here calls a widget directly to
# set it up, so an unfed widget fails its leg.
#
#   leg 1 no radar owned:   zero chevrons, the footprint map hidden.
#   leg 2 mine radar:       after a step >= 1 chevron; its distance matches the sim
#                           query's own distance for that mine.
#   leg 3 gift radar:       the same shape (the nearest real gift).
#   leg 4 threat radar:     the same shape (a probe enemy stepped close to the player).
#   leg 5 beacon compass:   the same shape (the beacon delta, angle included).
#   leg 6 footprint map:    visible, and the revealed dot count matches the sim query
#                           for the same position.
#
# Negative control: disable the world.gd feed and every leg above fails.

const WorldScript := preload("res://app/world.gd")
const RT := preload("res://sim/enemy_runtime.gd")
const UpgradesScript := preload("res://sim/upgrades.gd")
const CollisionScript := preload("res://sim/collision.gd")

const SEED := 1
const LEVEL := 1
const MINE_LEVEL := 5   # level 1 rolls zero tripmines; seed 1 level 5 rolls one
const DT := 1.0 / 60.0
const EPS := 0.05


# The probe enemy: parked-behaviour stand-in for a live threat. It never attacks
# (contact_kill false), so the run cannot end mid-test.
class ProbeBehavior:
	extends RT.EnemyBehavior

	func tick(_row: Dictionary, _api, _dt_ticks: int) -> void:
		return


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_no_radar(f)
	_leg_mine_radar(f)
	_leg_gift_radar(f)
	_leg_threat_radar(f)
	_leg_beacon_compass(f)
	_leg_footprint_map(f)
	return f


func _ledger(stacks: Dictionary) -> Dictionary:
	return {"class": "dasher", "votes": {}, "curses": {}, "stacks": stacks.duplicate(),
			"purse": 500, "tithes": 0, "hunger": 0, "last_vote": ""}


func _build(f: Array[String], tag: String, stacks: Dictionary,
		p_seed: int = SEED, p_level: int = LEVEL):
	var world = WorldScript.new()
	if not world.build(p_seed, p_level, _ledger(stacks)):
		f.append("%s: world failed to build level %d seed %d" % [tag, p_level, p_seed])
		world.free()
		return null
	return world


func _drop(world) -> void:
	if world != null:
		world.teardown()
		world.free()

# ---- shared helpers -------------------------------------------------------------

## Teleport the body onto the nearest supported tile to (tx, tz): the target itself,
## then rings of 12 candidate offsets. Without this the body drops into the void and
## respawns at the spawn tile, out of radar reach.
func _stand_near(world, tx: float, tz: float) -> bool:
	var cands := [Vector2(0.0, 0.0)]
	for r in [2.0, 3.5, 5.0, 7.0, 9.0, 12.0]:
		for i in 12:
			var a := TAU * float(i) / 12.0
			cands.append(Vector2(cos(a) * r, sin(a) * r))
	for off in cands:
		var x: float = tx + float(off.x)
		var z: float = tz + float(off.y)
		var s = CollisionScript.support_at(world.w, x, z, 100.0, 200.0)
		if s == -INF or s == null:
			continue
		world.ctl.x = x
		world.ctl.z = z
		world.ctl.y = float(s)
		world.ctl.vx = 0.0
		world.ctl.vy = 0.0
		world.ctl.vz = 0.0
		return true
	return false


## The radar widget yields zero entries below a 1 px viewport; the headless harness
## never runs a layout pass, so give it one (the shipped window is real).
func _size_radar(world) -> void:
	world.hud.radar_arrows.size = Vector2(1152.0, 648.0)


## The sim's own query decides reach: if no mine is in range, stand on a supported
## tile near the nearest one.
func _ensure_mine_reach(world) -> void:
	var lv = world.lstate
	var px := float(world.ctl.x)
	var pz := float(world.ctl.z)
	if UpgradesScript.mine_outline_ids(lv.mines, px, pz).size() > 0:
		return
	var best_slot := -1
	var best_d2 := INF
	for slot in lv.mines.ids:
		var c: Vector3 = lv.mines.point(slot)
		var dx := c.x - px
		var dz := c.z - pz
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best_slot = slot
	if best_slot < 0:
		return
	var c: Vector3 = lv.mines.point(best_slot)
	_stand_near(world, c.x, c.z)


## Same shape for the gift radar's 40 u reach.
func _ensure_gift_reach(world) -> void:
	var lv = world.lstate
	var px := float(world.ctl.x)
	var pz := float(world.ctl.z)
	var gift: Dictionary = UpgradesScript.nearest_real_gift(lv, px, pz, 40.0)
	if not gift.is_empty():
		return
	var nearest: Dictionary = UpgradesScript.nearest_real_gift(lv, px, pz, 1.0e9)
	if nearest.is_empty():
		return
	_stand_near(world, float(nearest["x"]), float(nearest["z"]))


func _sorted_dists(items: Array) -> Array:
	var out: Array = []
	for it in items:
		out.append(float(it["dist"]))
	out.sort()
	return out


func _check_dists(f: Array[String], tag: String, items: Array, want_dists: Array) -> void:
	var want := want_dists.duplicate()
	want.sort()
	var got := _sorted_dists(items)
	if got.size() != want.size():
		f.append("%s: %d chevrons for %d sim-queried targets" % [tag, got.size(), want.size()])
		return
	for i in want.size():
		if absf(float(got[i]) - float(want[i])) > EPS:
			f.append("%s: chevron %d is %.3f u, the sim query says %.3f u" % [tag, i, got[i], want[i]])

# ---- leg 1: a run with no radar roles renders nothing --------------------------

func _leg_no_radar(f: Array[String]) -> void:
	var world = _build(f, "no-radar", {})
	if world == null:
		return
	_size_radar(world)
	world.step(DT)
	var items: Array = world.hud.radar_arrows._items
	if items.size() != 0:
		f.append("no-radar: %d chevrons drawn for a run that owns no radar" % items.size())
	if bool(world.hud.cartographer_map.visible):
		f.append("no-radar: the footprint map is visible for a run that owns no map")
	_drop(world)


# ---- leg 2: mine radar ----------------------------------------------------------

func _leg_mine_radar(f: Array[String]) -> void:
	var world = _build(f, "mine-radar", {"radar_mines": 1}, SEED, MINE_LEVEL)
	if world == null:
		return
	_ensure_mine_reach(world)
	_size_radar(world)
	world.step(DT)
	var px := float(world.ctl.x)
	var pz := float(world.ctl.z)
	var ids: Array = UpgradesScript.mine_outline_ids(world.lstate.mines, px, pz)
	var items: Array = world.hud.radar_arrows._items
	if ids.is_empty():
		f.append("mine-radar: the sim query finds nothing in reach post-teleport; leg cannot assert")
		_drop(world)
		return
	if items.is_empty():
		f.append("mine-radar: no chevron after a step for a run owning the mine radar")
		_drop(world)
		return
	var want: Array = []
	for slot in ids:
		var c: Vector3 = world.lstate.mines.point(slot)
		want.append(sqrt((c.x - px) * (c.x - px) + (c.z - pz) * (c.z - pz)))
	_check_dists(f, "mine-radar", items, want)
	_drop(world)

# ---- leg 3: gift radar ----------------------------------------------------------

func _leg_gift_radar(f: Array[String]) -> void:
	var world = _build(f, "gift-radar", {"radar_gifts": 1})
	if world == null:
		return
	_ensure_gift_reach(world)
	_size_radar(world)
	world.step(DT)
	var px := float(world.ctl.x)
	var pz := float(world.ctl.z)
	var gift: Dictionary = UpgradesScript.nearest_real_gift(world.lstate, px, pz, 40.0)
	var items: Array = world.hud.radar_arrows._items
	if gift.is_empty():
		f.append("gift-radar: the sim query finds no real gift in reach post-teleport; leg cannot assert")
		_drop(world)
		return
	if items.is_empty():
		f.append("gift-radar: no chevron after a step for a run owning the gift radar")
		_drop(world)
		return
	_check_dists(f, "gift-radar", items, [float(gift["dist"])])
	_drop(world)


# ---- leg 4: threat radar ---------------------------------------------------------

func _leg_threat_radar(f: Array[String]) -> void:
	var world = _build(f, "threat-radar", {"radar_threats": 1})
	if world == null:
		return
	var c = world.ctl
	var beh := ProbeBehavior.new()
	var cfg := {"contact_kill": false, "id": "kiwi_cat", "name": "RADAR PROBE"}
	world.rt.spawn_at("kiwi_cat", "RADAR PROBE", beh, cfg,
			Vector3(float(c.x) + 3.0, float(c.y), float(c.z)))
	_size_radar(world)
	world.step(DT)
	var px := float(world.ctl.x)
	var pz := float(world.ctl.z)
	var markers: Array = UpgradesScript.threat_markers(world.w.get("enemies", []), px, pz)
	var items: Array = world.hud.radar_arrows._items
	if markers.is_empty():
		f.append("threat-radar: the probe is not in the mirror within 30 u; leg cannot assert")
		_drop(world)
		return
	if items.is_empty():
		f.append("threat-radar: no chevron after a step for a run owning the threat radar")
		_drop(world)
		return
	var want: Array = []
	for m in markers:
		want.append(float(m["dist"]))
	_check_dists(f, "threat-radar", items, want)
	_drop(world)

# ---- leg 5: beacon compass -------------------------------------------------------

func _leg_beacon_compass(f: Array[String]) -> void:
	var world = _build(f, "beacon-compass", {"radar_beacon": 1})
	if world == null:
		return
	_size_radar(world)
	world.step(DT)
	var px := float(world.ctl.x)
	var pz := float(world.ctl.z)
	var b: Dictionary = UpgradesScript.beacon_compass(world.lstate, px, pz)
	var items: Array = world.hud.radar_arrows._items
	if b.is_empty():
		f.append("beacon-compass: the level has no beacon; leg cannot assert")
		_drop(world)
		return
	if items.is_empty():
		f.append("beacon-compass: no chevron after a step for a run owning the beacon compass")
		_drop(world)
		return
	var best_d := INF
	var best_i := -1
	for i in items.size():
		var d := absf(float(items[i]["dist"]) - float(b["dist"]))
		if d < best_d:
			best_d = d
			best_i = i
	if best_d > EPS:
		f.append("beacon-compass: nearest chevron is %.3f u from the sim query's own distance %.3f u"
				% [best_d, float(b["dist"])])
	else:
		var want_a := atan2(float(b["dz"]), float(b["dx"]))
		if absf(float(items[best_i]["angle"]) - want_a) > EPS:
			f.append("beacon-compass: chevron angle %.4f rad, the sim query says %.4f rad"
					% [float(items[best_i]["angle"]), want_a])
	_drop(world)


# ---- leg 6: the footprint map ----------------------------------------------------

func _leg_footprint_map(f: Array[String]) -> void:
	var world = _build(f, "footprint-map", {"cartographer": 1})
	if world == null:
		return
	_ensure_gift_reach(world)   # at least one real gift inside the footprint radius
	world.step(DT)
	if not bool(world.hud.cartographer_map.visible):
		f.append("footprint-map: the map is hidden for a run that owns the footprint map")
	var visited: Dictionary = world.lstate.upgrades.visited.get(0, {})
	if visited.is_empty():
		f.append("footprint-map: the footprint memory is empty after a step")
	var px := float(world.ctl.x)
	var pz := float(world.ctl.z)
	var want: int = world.lstate.upgrades.revealed(world.lstate, 0).size()
	var dots := 0
	for item in world.hud.cartographer_map._model:
		if item.has("dot"):
			dots += 1
	if dots != want:
		f.append("footprint-map: %d revealed dots drawn, the sim query returns %d rows for the same position"
				% [dots, want])
	_drop(world)
