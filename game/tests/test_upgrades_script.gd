extends RefCounted
#
# Scripted upgrades, one test per upgrade (ticket T-053; DESIGN.md section 8,
# dispatch addendum R4, D-T053-1..8; the mine ladder of D-058/D-053 in mines.gd):
#   radar_beacon  - compass heading + distance from the beacon queries
#   radar_gifts   - nearest real gift within 40 u (80 u at 2 stacks)
#   radar_mines   - outlines ONLY occ == 1 slots within 14 u
#   radar_threats - enemies within 30 u, nearest first
#   cartographer  - pieces within 40 u of anywhere you have stood
#   skeleton_key  - the beacon opens at 90 % of real black gifts, rest go gold
#   pocket_beacon - INTERACT starts a 180-tick still channel; any input cancels;
#                   fill teleports to the dais; once per level
#   twin_dash     - a second dash stock, own 3 s regen, dasher only (by wiring)
#   updraft       - mid-glide re-press rises exactly 3.0 u, 6 s cooldown, once/glide
#   marathon      - athletic + owned -> +2 max stacks of Yearn for Speed in the shop
#   defuse_kit    - §3.3 step 1 verbatim: deterministic roll, 20 x stacks (cap 60),
#                   consumed with no blast/no death, chain resets, 0 stacks never
#   subspacial_barrier - §3.3 step 2 verbatim: shield consumed AFTER the defuse roll
#                   fails, no blast, chain resets; tripmines only - the nuke passes
#                   straight through to death (nothing absorbs the nuke)

const Util := preload("res://tests/sim_testutil.gd")
const VoidGenScript := preload("res://terrain/voidgen.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")
const LevelStateScript := preload("res://sim/level_state.gd")
const RunStateScript := preload("res://sim/run_state.gd")
const SimScript := preload("res://sim/sim.gd")
const InputScript := preload("res://sim/input.gd")
const UpgradesScript := preload("res://sim/upgrades.gd")
const ControllerScript := preload("res://sim/controller.gd")
const MinesScript := preload("res://sim/mines.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const BeaconScript := preload("res://sim/beacon.gd")
const OffersScript := preload("res://sim/offers.gd")
const RadarMines := preload("res://content/upgrades/radar_mines.gd")
const RadarBeacon := preload("res://content/upgrades/radar_beacon.gd")
const RadarGifts := preload("res://content/upgrades/radar_gifts.gd")
const RadarThreats := preload("res://content/upgrades/radar_threats.gd")
const Cartographer := preload("res://content/upgrades/cartographer.gd")
const SkeletonKey := preload("res://content/upgrades/skeleton_key.gd")
const PocketBeacon := preload("res://content/upgrades/pocket_beacon.gd")
const PocketBeaconContent := preload("res://content/upgrades/pocket_beacon.gd")
const Marathon := preload("res://content/upgrades/marathon.gd")
const T053Roles := preload("res://content/upgrades/t053_roles.gd")
const RadarArrowsScript := preload("res://view/hud/radar_arrows.gd")
const CartographerMapScript := preload("res://view/hud/cartographer_map.gd")

const SEED := 42
const LEVEL := 25


func run() -> Array[String]:
	var f: Array[String] = []
	_test_roles_aggregation(f)
	_test_radar_beacon(f)
	_test_radar_gifts(f)
	_test_radar_mines(f)
	_test_radar_threats(f)
	_test_cartographer(f)
	_test_skeleton_key(f)
	_test_pocket_beacon(f)
	_test_twin_dash(f)
	_test_updraft(f)
	_test_marathon(f)
	_test_defuse_kit(f)
	_test_subspacial_barrier(f)
	_test_radar_arrows_widget(f)
	_test_cartographer_map_widget(f)
	return f


# ---- the addendum R4 render contracts (D-T053-8) -----------------------------------

func _test_radar_arrows_widget(f: Array[String]) -> void:
	_expect(f, RadarArrowsScript.CHEVRON == 24.0, "radar arrows: the chevron is not 24 px")
	# a chevron for a target due right sits at the RIGHT screen edge; the label
	# (the distance in u) sits under it
	var vp := Vector2(800.0, 450.0)
	var pos: Vector2 = RadarArrowsScript._chevron_pos(0.0, vp)
	_expect(f, _near(pos.y, vp.y * 0.5, 1e-6) and pos.x > vp.x * 0.5,
			"radar arrows: a due-right chevron is not on the right screen edge (%s)" % [pos])
	_expect(f, pos.x <= vp.x - RadarArrowsScript.CHEVRON * 0.5
			and pos.x >= vp.x - RadarArrowsScript.CHEVRON * 0.5 - RadarArrowsScript.EDGE_MARGIN,
			"radar arrows: the 24 px chevron sits flush at the screen edge (x %f)" % pos.x)


func _test_cartographer_map_widget(f: Array[String]) -> void:
	_expect(f, CartographerMapScript.SIZE == 220.0, "cartographer map: not a 220 px square")
	var level := {
		"tiles": [[0, 0, 0, 0, 0], [1, 0, 0, 0, 1]],
		"pieces": [{"id": 0, "kind": 0}, {"id": 1, "kind": 1}],
		"gifts": [{"id": 0, "x": 2, "z": 0, "y": 0, "piece": 0, "tier": 0, "occ": 0},
				{"id": 1, "x": 3, "z": 0, "y": 0, "piece": 0, "tier": 0, "occ": 1},
				{"id": 2, "x": 4, "z": 0, "y": 0, "piece": 0, "tier": 0, "occ": 0}],
		"beacon": [0, 0, 0],
	}
	var foot: Dictionary = {Vector2i(2, 0): true}
	# scale 2 px per u, 220 px square centred on the player at (2.5, 0.5)
	var colours := {"platform": Color(0.2, 0.7, 0.7), "walkway": Color(0.2, 0.4, 0.9),
			"gift": Color(0.9, 0.8, 0.2), "mine": Color(1.0, 0.3, 0.8),
			"beacon": Color(0.5, 1.0, 0.5)}
	var model: Array = CartographerMapScript.build_model(level, foot, 2.5, 0.5,
			2.0, colours, 220.0)
	var platform_tiles := 0
	var walkway_tiles := 0
	var gift_dots := 0
	var mine_dots := 0
	var beacon_dots := 0
	var triangles := 0
	for item in model:
		if item.has("rect"):
			if item["color"].is_equal_approx(colours["platform"]):
				platform_tiles += 1
			elif item["color"].is_equal_approx(colours["walkway"]):
				walkway_tiles += 1
		elif item.has("dot"):
			if item["color"].is_equal_approx(colours["gift"]):
				gift_dots += 1
				_expect(f, _near(float(item["r"]), 1.0, 1e-6),
						"cartographer map: gift dots are not 2 px (r %f)" % float(item["r"]))
			elif item["color"].is_equal_approx(colours["mine"]):
				mine_dots += 1
			else:
				beacon_dots += 1
		elif item.has("triangle"):
			triangles += 1
			_expect(f, item["color"].is_equal_approx(Color(1.0, 1.0, 1.0, 1.0)),
					"cartographer map: the player triangle is not white")
	_expect(f, platform_tiles == 1 and walkway_tiles == 1,
			"cartographer map: pieces as filled shapes in their biome colours (%d/%d)" % [platform_tiles, walkway_tiles])
	_expect(f, gift_dots == 2 and mine_dots == 1 and beacon_dots == 1,
			"cartographer map: the real gift dot / mine / beacon markers (%d/%d/%d)" % [gift_dots, mine_dots, beacon_dots])
	_expect(f, triangles == 1, "cartographer map: no white player triangle")
	# north-up: the gift EAST of the player draws to the RIGHT of the square's centre
	var east_ok := false
	for item in model:
		if item.has("dot") and item["color"].is_equal_approx(colours["gift"]):
			if float(item["dot"].x) > 110.0 and _near(float(item["dot"].y), 110.0, 1.01):
				east_ok = true
	_expect(f, east_ok,
			"cartographer map: the east piece must draw right of centre (north-up)")


# ---- shared: a synthetic level dict ([x, z, y, piece, tier, occ] gift rows) ------

# Slot id i sits at world x = i * 10 + 0.5, z = 0.5, y = 0 (test_mines' layout).
static func _level(occs: Array) -> Dictionary:
	var slots: Array = []
	for i in occs.size():
		slots.append({"id": i, "x": i * 10, "z": 0, "y": 0, "piece": 0, "tier": 0,
				"occ": occs[i]})
	return {"gifts": slots, "beacon": [30, 0, 0], "spawns": [[0, 0, 0]]}


static func _state(occs: Array, seed: int, roles: Dictionary = {}) -> RefCounted:
	# A synthetic LevelState WITHOUT LevelState.build: the full build runs the
	# terrain hash over the level dict, which a synthetic level cannot satisfy.
	# The pieces the radar queries read (gifts / mines / beacon / players) are
	# built exactly as build() builds them, from the same synthetic level dict.
	var lvl := _level(occs)
	var lv: RefCounted = LevelStateScript.new()
	lv.gifts = GiftsScript.create(lvl)
	lv.beacon = BeaconScript.create(lvl)
	lv.mines = MinesScript.create(lvl, 1, seed)
	lv.players = [{"x": 0.5, "y": 0.0, "z": 0.5, "vx": 0.0, "vy": 0.0, "vz": 0.0,
			"grounded": true, "prev_buttons": 0}]
	lv.upgrades = UpgradesScript.create(roles)
	if lv.upgrades != null and lv.upgrades.has(UpgradesScript.ROLE_SKELETON_QUOTA):
		lv.gifts.black_quota = UpgradesScript.skeleton_threshold(lv.gifts.total_real)
	return lv


static func _kind(ev: Array, k: String) -> int:
	var n := 0
	for e in ev:
		if str(e.get("type", e.get("e", ""))) == k:
			n += 1
	return n


static func _expect(f: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		f.append(msg)


static func _near(a: float, b: float, eps: float) -> bool:
	return absf(a - b) <= eps


# ---- the role aggregation (D-T053-1) ---------------------------------------------

func _test_roles_aggregation(f: Array[String]) -> void:
	var none: Dictionary = T053Roles.roles_for({})
	_expect(f, none.is_empty(), "roles: empty stacks gave roles %s" % [none])
	var one: Dictionary = T053Roles.roles_for({RadarMines.UPGRADE_ID: 1,
			PocketBeacon.UPGRADE_ID: 1})
	_expect(f, one.get("mine_radar", false) == true and one.get("beacon_channel", false) == true,
			"roles: radar_mines/pocket_beacon stacks did not map to their roles")
	_expect(f, not one.has("gift_radar") and not one.has("skeleton_quota"),
			"roles: unowned roles leaked into the aggregation")


# ---- Radar Module: Beacon (no per-tick state; pure compass query) -----------------

func _test_radar_beacon(f: Array[String]) -> void:
	var lv := _state([0], 7)
	var b: RefCounted = lv.beacon
	var c: Dictionary = UpgradesScript.beacon_compass(lv, 10.5, 0.5)
	_expect(f, not c.is_empty(), "beacon compass: empty from a level with a beacon")
	_expect(f, _near(float(c["dx"]), float(b.cx) - 10.5, 1e-6)
			and _near(float(c["dz"]), float(b.cz) - 0.5, 1e-6),
			"beacon compass: dx/dz not the beacon's tile centre")
	var want: float = sqrt(pow(float(b.cx) - 10.5, 2) + pow(float(b.cz) - 0.5, 2))
	_expect(f, _near(float(c["dist"]), want, 1e-6),
			"beacon compass: dist %.4f, want %.4f" % [float(c["dist"]), want])
	_expect(f, RadarBeacon.ROLE == "beacon_compass", "beacon compass: role pairing moved")


# ---- Radar Module: Gifts (nearest REAL gift in 40/80 u) ---------------------------

func _test_radar_gifts(f: Array[String]) -> void:
	# occ 0 at 0.5 (collected), 10.5 (live), 30.5 - 20.5 u beyond slot 1.
	var lv := _state([0, 0, 0], 7)
	lv.gifts.collect(0, 1, 0, [])
	var hit: Dictionary = UpgradesScript.nearest_real_gift(lv, 0.5, 0.5, 40.0)
	_expect(f, int(hit.get("slot", -1)) == 1,
			"gift radar: slot %s, want the nearest live real gift 1" % [hit.get("slot")])
	_expect(f, _near(float(hit.get("dist", -1)), 10.0, 1e-6),
			"gift radar: dist %.4f, want 10.0" % [float(hit.get("dist", -1.0))])
	# 40 u at 1 stack only reaches slot 2 (30 u)? yes; slot 3 would be 40 off-scale.
	lv.gifts.collect(1, 2, 0, [])
	var hit2: Dictionary = UpgradesScript.nearest_real_gift(lv, 0.5, 0.5, 40.0)
	_expect(f, int(hit2.get("slot", -1)) == 2, "gift radar: slot 2 missed at 40 u")
	_expect(f, not UpgradesScript.nearest_real_gift(lv, 0.5, 0.5, 5.0).has("slot"),
			"gift radar: a gift 30 u away answered a 5 u query")
	_expect(f, RadarGifts.range_u(1) == 40.0 and RadarGifts.range_u(2) == 80.0,
			"gift radar: range_u stacks 1/2 not 40/80")


# ---- Radar Module: Mines - ONLY occ == 1 slots within 14 u ------------------------

func _test_radar_mines(f: Array[String]) -> void:
	# gifts at 0.5 / 10.5, a mine at 20.5, live real gifts beyond: the query point
	# stands on slot 0's tile (10 u to slot 1, 20 u to the mine).
	var seed := 4242
	var occs := [0, 0, 1, 0, 0]
	var lv := _state(occs, seed)
	var mines: RefCounted = lv.mines
	_expect(f, mines.count() == 1, "mine radar: mine set %d, want exactly the occ==1 slot" % mines.count())
	# the query stands on slot 1's tile: the mine (slot 2) is 10 u away - the live
	# real gift underfoot is NEVER outlined; only occ == 1 slots are.
	var ids: Array = UpgradesScript.mine_outline_ids(mines, 10.5, 0.5)
	_expect(f, ids == [2], "mine radar: %s within 14 u, want [2] (the mine at 20.5)" % [ids])
	for slot in ids:
		_expect(f, int(lv.gifts.slots[slot]["occ"]) == 1,
				"mine radar: slot %d outlined but is not occ == 1" % slot)
	# the 14 u bound: a query 5.5 u short of the mine (15 u away) sees nothing;
	# and a dead real gift never answers.
	_expect(f, UpgradesScript.mine_outline_ids(mines, 5.5, 0.5).is_empty(),
			"mine radar: a mine 15 u away answered - the bound must cut at 14 u")
	if not f.is_empty():
		return
	# consumption hides it: defuse (or shield) the mine and the outline clears
	var seed_defuse := -1
	for s in range(1, 100000):
		if MinesScript.defuse_roll(s, 1, 2, 3):
			seed_defuse = s
			break
	_expect(f, seed_defuse > 0, "mine radar: no seed defuses slot 2 at 3 stacks")
	if seed_defuse < 0:
		return
	var lv2 := _state(occs, seed_defuse)
	lv2.mines.consume(2)
	_expect(f, UpgradesScript.mine_outline_ids(lv2.mines, 0.5, 0.5).is_empty(),
			"mine radar: a consumed mine still outlined")


# ---- Radar Module: Threats (enemies within 30 u, nearest first) -------------------

func _test_radar_threats(f: Array[String]) -> void:
	var enemies := [
		{"x": 5.0, "y": 0.0, "z": 0.0, "r": 0.5},
		{"x": 0.0, "y": 0.0, "z": 10.0, "r": 0.5},
		{"x": 100.0, "y": 0.0, "z": 100.0, "r": 0.5},
	]
	var markers: Array = UpgradesScript.threat_markers(enemies, 0.0, 0.0)
	_expect(f, markers.size() == 2,
			"threat radar: %d markers, want 2 inside 30 u" % markers.size())
	if markers.size() == 2:
		_expect(f, _near(float(markers[0]["dist"]), 5.0, 1e-6),
				"threat radar: nearest first (dist %.4f)" % float(markers[0]["dist"]))
	_expect(f, RadarThreats.RANGE_U == 30.0, "threat radar: range const moved")


# ---- Cartographer (pieces within 40 u of anywhere you have stood) -----------------

func _test_cartographer(f: Array[String]) -> void:
	var roles := {UpgradesScript.ROLE_CARTOGRAPHER: true}
	# gifts every 10 u (slots 0,1,3,4,5 real; slot 2 the mine, 50 u from tile 0)
	var lv: RefCounted = _state([0, 0, 1, 0, 0, 0], 9, roles)
	var upg: RefCounted = lv.upgrades
	_expect(f, upg != null, "cartographer: no upgrade state built from the role")
	if upg == null:
		return
	upg.note_footprint(0, 0.5, 0.5)
	var rows: Array = upg.revealed(lv, 0)
	var kinds := {}
	for row in rows:
		kinds[str(row["kind"]) + ":" + str(row.get("slot", -1))] = true
	_expect(f, kinds.has("gift:0") and kinds.has("mine:2") and kinds.has("beacon:-1")
			and kinds.has("gift:3"),
			"cartographer: stood-at-tile reveal missing gift/mine/beacon (%s)" % [kinds])
	_expect(f, not kinds.has("gift:5"),
			"cartographer: a piece beyond 40 u of the only footprint was revealed (%s)" % [kinds])
	# gift:4 sits exactly 40.0 u from tile 0's centre - within (the bound is inclusive)
	# new footprints widen the reveal; collected gifts leave the map
	upg.note_footprint(0, 41.5, 0.5)
	rows = upg.revealed(lv, 0)
	kinds = {}
	for row in rows:
		kinds[str(row["kind"]) + ":" + str(row.get("slot", -1))] = true
	_expect(f, kinds.has("gift:4") and kinds.has("gift:5"),
			"cartographer: the far pieces missed after standing near them")
	lv.gifts.collect(4, 3, 0, [])
	rows = upg.revealed(lv, 0)
	for row in rows:
		_expect(f, not (str(row["kind"]) == "gift" and int(row.get("slot", -1)) == 4),
				"cartographer: a collected gift stayed on the map")


# ---- Skeleton Key (the beacon opens at 90 % of real black gifts) ------------------

func _test_skeleton_key(f: Array[String]) -> void:
	# 9 real black gifts: ceil(0.9 x 9) = 9 takes the last one; use 10 -> 9.
	var occs: Array = []
	for i in 10:
		occs.append(0)
	var lv := _state(occs, 11, {UpgradesScript.ROLE_SKELETON_QUOTA: true})
	_expect(f, lv.gifts.black_quota == SkeletonKey.threshold(10),
			"skeleton key: quota %d, want the content script's threshold %d"
					% [lv.gifts.black_quota, SkeletonKey.threshold(10)])
	_expect(f, SkeletonKey.threshold(10) == 9,
			"skeleton key: threshold %d, want ceil(0.9 x 10) = 9" % SkeletonKey.threshold(10))
	# default unchanged: the same level with no role keeps the exact merged rule
	var lv_plain := _state(occs, 11)
	_expect(f, lv_plain.gifts.black_quota == -1, "skeleton key: default quota moved")
	for i in 8:
		lv.gifts.collect(i, 4, 0, [])
	_expect(f, not lv.gifts.all_black_collected(),
			"skeleton key: 8/10 (below the quota of 9) opened the beacon")
	_expect(f, lv.gifts.phase == GiftsScript.PHASE_BLACK,
			"skeleton key: phase left black before the quota")
	lv.gifts.collect(8, 5, 0, [])
	_expect(f, lv.gifts.all_black_collected(),
			"skeleton key: 9/10 at the quota did not open")
	# a quota of 1 of 3 opens with two black gifts still standing - and those two
	# are gold gifts now (the same slot, gold phase: "the rest turn gold in place")
	var lv3 := _state([0, 0, 0], 11, {UpgradesScript.ROLE_SKELETON_QUOTA: 8})
	# threshold over total_real=3 would be 3; drive the quota by hand to check the
	# remainder reading itself (the sim's black_quota is the caller's contract).
	lv3.gifts.black_quota = 1
	lv3.gifts.collect(1, 6, 0, [])
	_expect(f, lv3.gifts.phase == GiftsScript.PHASE_GOLD,
			"skeleton key: quota 1/3 did not open the beacon phase")
	lv3.gifts.collect(0, 7, 0, [])
	_expect(f, lv3.gifts.collected(0) and lv3.gifts.phase == GiftsScript.PHASE_GOLD,
			"skeleton key: the remainder slot did not go gold in place")


# ---- Pocket Beacon (INTERACT + still -> 180-tick channel -> dais teleport) ---------

func _run_channel(seed: int) -> Array:
	var L := VoidGenScript.generate(seed, 1)
	var rs := RunStateScript.new_run(seed, 1, [])
	rs.upgrade_roles = {UpgradesScript.ROLE_BEACON_CHANNEL: true}
	rs.load_level(L, 1)
	return [rs, L]


func _test_pocket_beacon(f: Array[String]) -> void:
	var pair := _run_channel(SEED)
	var rs: RefCounted = pair[0]
	var lv: RefCounted = rs.level
	var ev: Array = SimScript.step(rs, [InputScript.new(0, 0, InputScript.BUTTON_INTERACT)])
	_expect(f, _kind(ev, "beacon_channel_started") == 1,
			"pocket beacon: INTERACT press while standing still started no channel")
	if lv.upgrades.channels.is_empty():
		f.append("pocket beacon: no channel state after the start")
		return
	# any input cancels: the ABILITY button breaks the channel the same tick
	ev = SimScript.step(rs, [InputScript.new(0, 0, InputScript.BUTTON_ABILITY)])
	_expect(f, _kind(ev, "beacon_channel_cancelled") == 1,
			"pocket beacon: a held button did not cancel the channel")
	# land again before restarting (the cancel tick jumped; free fall does not
	# start a stand-still channel)
	for wait in 300:
		SimScript.step(rs, [InputScript.neutral()])
		if bool(lv.players[0]["grounded"]):
			break
	_expect(f, bool(lv.players[0]["grounded"]), "pocket beacon: never landed to restart")
	# restart, then cancel with movement
	ev = SimScript.step(rs, [InputScript.new(0, 0, InputScript.BUTTON_INTERACT)])
	var pair2 := pair
	_expect(f, _kind(ev, "beacon_channel_started") == 1,
			"pocket beacon: a cancelled channel cannot restart")
	ev = SimScript.step(rs, [InputScript.new(60, 0, 0)])
	_expect(f, _kind(ev, "beacon_channel_cancelled") == 1,
			"pocket beacon: a move axis did not cancel the channel")
	for wait2 in 300:
		SimScript.step(rs, [InputScript.neutral()])
		if bool(lv.players[0]["grounded"]):
			break
	# restart and hold 180 neutral ticks exactly -> the dais teleport
	ev = SimScript.step(rs, [InputScript.new(0, 0, InputScript.BUTTON_INTERACT)])
	if _kind(ev, "beacon_channel_started") != 1:
		f.append("pocket beacon: the second restart failed")
		return
	var done := false
	for t in PocketBeaconContent.CHANNEL_TICKS:
		ev = SimScript.step(rs, [InputScript.neutral()])
		if _kind(ev, "beacon_teleport") == 1:
			_expect(f, t == PocketBeaconContent.CHANNEL_TICKS - 1,
					"pocket beacon: the fill took %d held ticks, want 180" % (t + 1))
			done = true
			break
	_expect(f, done, "pocket beacon: 180 held ticks did not teleport")
	var p: Dictionary = lv.players[0]
	_expect(f, _near(float(p["x"]), float(lv.beacon.cx), 1e-6)
			and _near(float(p["z"]), float(lv.beacon.cz), 1e-6)
			and _near(float(p["y"]), float(lv.beacon.base_y), 1e-6),
			"pocket beacon: the teleport did not land on the dais")
	# spent: a second channel start is refused within the same level
	var ev2: Array = SimScript.step(rs, [InputScript.new(0, 0, InputScript.BUTTON_INTERACT)])
	_expect(f, _kind(ev2, "beacon_channel_started") == 0,
			"pocket beacon: the channel started a second time in one level")
	_expect(f, PocketBeaconContent.CHANNEL_TICKS == 180
			and UpgradesScript.CHANNEL_TICKS == 180,
			"pocket beacon: the 180-tick contract moved")
	if rs.level.upgrades == null or not pair2[0].level.upgrades.has(UpgradesScript.ROLE_BEACON_CHANNEL):
		f.append("pocket beacon: roles wiring lost")


# ---- Twin Dash (second dash stock, own 3 s regen, granted charged) -----------------

static func _dasher() -> RefCounted:
	var ctl = ControllerScript.new()
	ctl.setup("dasher", ControllerScript.load_constants())
	ctl.apply_twin_dash()
	return ctl


static func _press(ctl, w: Dictionary, buttons: int, n: int = 1) -> Array:
	var ev: Array = []
	for i in n:
		ev.append_array(ctl.step(Util.DT, Util.mk_in(0, 0, buttons), w))
	return ev


## A flat 1-tall strip of tiles x = -4..n-1 (test_classes' _flat, local copy).
static func _flat(n: int) -> Dictionary:
	var tiles: Array = []
	for cx in range(-4, n):
		tiles.append([cx, 0, 0])
	return Util.world_from_tiles(tiles)


func _test_twin_dash(f: Array[String]) -> void:
	var ctl := _dasher()
	# stand the controller on a column of the strip (place() targets the dais
	# corner, which this 1-wide strip world has no tiles under)
	var w := _flat(30)
	ctl.place(w)
	ctl.x = 10.5
	ctl.z = 0.5
	var ev := _press(ctl, w, ControllerScript.BTN_ABILITY)
	_expect(f, ctl.dash_ticks > 0 and not ctl.dash_ready,
			"twin dash: the primary charge did not fire first")
	_press(ctl, w, 0, 12)                       # the dash span runs out
	var ev2 := _press(ctl, w, ControllerScript.BTN_ABILITY)
	_expect(f, _kind(ev2, "dash_start") == 1,
			"twin dash: the bonus stock did not dash after the primary cooled")
	_expect(f, int(ctl.bonus_dashes) == 0 and not ctl.dash_ready,
			"twin dash: the bonus stock did not spend (or the primary leaked ready)")
	var ev3 := _press(ctl, w, ControllerScript.BTN_ABILITY)
	_expect(f, _kind(ev3, "dash_start") == 0,
			"twin dash: a third dash fired with both charges spent")
	# both stocks regenerate: at 2.5 s neither is back
	_press(ctl, w, 0, 150)
	var ev4 := _press(ctl, w, ControllerScript.BTN_ABILITY)
	_expect(f, _kind(ev4, "dash_start") == 0,
			"twin dash: a dash fired before any 3 s regen completed")
	_press(ctl, w, 0, 40)
	var ev5 := _press(ctl, w, ControllerScript.BTN_ABILITY)
	_expect(f, _kind(ev5, "dash_start") == 1,
			"twin dash: no dash after the 3 s regen (t0 + 3.17 s)")


# ---- Updraft (glider: re-press mid-glide rises exactly 3.0 u, 6 s cooldown) -------



func _test_updraft(f: Array[String]) -> void:
	var ctl = ControllerScript.new()
	ctl.setup("glider", ControllerScript.load_constants())
	ctl.apply_updraft()
	var w := _flat(30)
	ctl.place(w)
	ctl.x = 10.5
	ctl.z = 0.5
	# hold jump from the ground: jump, apex, fall, glide engage
	_press(ctl, w, ControllerScript.BTN_JUMP, 45)
	var ev := _press(ctl, w, 0, 2)
	ev = _press(ctl, w, ControllerScript.BTN_JUMP)
	_expect(f, _kind(ev, "updraft_rise") == 1 and not ctl.gliding,
			"updraft: the mid-glide re-press did not rise")
	if _kind(ev, "updraft_rise") != 1:
		return
	_expect(f, _near(ctl.vy, ControllerScript.UPDRAFT_VY, 1e-6),
			"updraft: step-exit vy %.4f, want the exact 3 u apex vy" % ctl.vy)
	var y0: float = ctl.y
	var peak := y0
	for i in 60:
		ctl.step(Util.DT, Util.mk_in(0, 0, ControllerScript.BTN_JUMP), w)
		peak = maxf(peak, ctl.y)
		if ctl.grounded:
			break
	_expect(f, _near(peak - y0, ControllerScript.UPDRAFT_RISE_U, 0.25),
			"updraft: apex rose %.3f u, want 3.0 +/-0.25" % (peak - y0))
	_glide_land(ctl, w)
	# the 6 s cooldown: land, glide again, re-press inside 6 s -> no rise
	_press(ctl, w, ControllerScript.BTN_JUMP, 40)
	_press(ctl, w, 0, 1)
	var ev2 := _press(ctl, w, ControllerScript.BTN_JUMP)
	_expect(f, _kind(ev2, "updraft_rise") == 0,
			"updraft: a second rise inside the 6 s cooldown")
	var held := _glide_land(ctl, w)
	_expect(f, held > 0, "updraft: the second glide never landed")
	_press(ctl, w, 0, 380 - held)
	_press(ctl, w, ControllerScript.BTN_JUMP, 40)
	_press(ctl, w, 0, 1)
	var ev3 := _press(ctl, w, ControllerScript.BTN_JUMP)
	_expect(f, _kind(ev3, "updraft_rise") == 1,
			"updraft: no rise after the 6 s cooldown ran out")


## Hold jump through a capped 2 u/s glide-fall until the feet land (free fall
## tunnels the 0.5 u slab); returns the ticks actually held.
static func _glide_land(ctl, w: Dictionary) -> int:
	var n := 0
	while not bool(ctl.grounded) and n < 200:
		ctl.step(Util.DT, Util.mk_in(0, 0, ControllerScript.BTN_JUMP), w)
		n += 1
	return n


# ---- Marathon (athletic + owned -> +2 max stacks of Yearn for Speed) --------------

class _StubApi extends RefCounted:
	## The minimal draw_shop surface: one id in the level's pool, max_stacks 4.
	func shop_pool(_level: int) -> Array:
		return ["yearn_for_speed"]
	func upgrade(_id: String) -> Dictionary:
		return {"id": "yearn_for_speed", "name": "Yearn", "tier": "T1", "price": 60,
				"max_stacks": 4, "class_only": null, "class_boost": ["athletic"],
				"effect": "", "modifiers": [], "hooks": [], "script": false}
	func data(_name: String) -> Dictionary:
		return {}


func _test_marathon(f: Array[String]) -> void:
	_expect(f, Marathon.max_bonus("athletic", {Marathon.UPGRADE_ID: 1})
			== {Marathon.BOOSTED_ID: 2},
			"marathon: the athletic+owned pairing did not grant +2")
	_expect(f, Marathon.max_bonus("dasher", {Marathon.UPGRADE_ID: 1}).is_empty(),
			"marathon: a non-athletic class drew the bonus")
	_expect(f, Marathon.max_bonus("athletic", {}).is_empty(),
			"marathon: the bonus drew without the purchase")
	# the shop cap: 4 stacks held excludes further draws; Marathon's +2 lets the
	# 5th draw through (D-T053-7: the bonus dict is the caller's to aggregate)
	var api := _StubApi.new()
	var rng := VoidRngScript.new(123)
	var held_stacks := {"marathon": 1, "yearn_for_speed": 4}
	var no_bonus: Dictionary = OffersScript.draw_shop(api, 1, 10000, held_stacks,
			"athletic", rng)
	_expect(f, no_bonus["offers"].is_empty(),
			"marathon: yearn at max_stacks 4 was still offered")
	var with_bonus: Dictionary = OffersScript.draw_shop(api, 1, 10000, held_stacks,
			"athletic", rng, 1.0, {}, Marathon.max_bonus("athletic", held_stacks))
	var found := false
	for o in with_bonus["offers"]:
		if str(o["id"]) == "yearn_for_speed":
			found = true
	_expect(f, found, "marathon: with the bonus the 5th yearn stack draw was excluded")


# ---- Defuse Kit + Subspacial Barrier: the D-053 ladder, verbatim -------------------
# (Owning tickets' surface notes: sim/mines.gd owns the ladder; these tests pin it
# at the upgrade level - the roll value, the cap, 0 stacks, and the ORDER.)

## The data the ladder tests use: slot 1 is the mine; the controller stands on its
## tile with a Subspacial Barrier HELD and Last Light armed (1 charge, unspent) -
## every step below the roll is visibly available, so each run reveals which ran.
static func _mine_setup(seed: int) -> Array:
	var ctl := _armed_ctl()
	var lv := _state([0, 1], seed, {})
	var beacon: RefCounted = lv.beacon
	beacon.barriers[0] = true          # a Subspacial Barrier is HELD
	ctl.x = 10.5                       # the mine slot's tile centre (x = 10 -> 10.5)
	ctl.z = 0.5
	ctl.y = 0.0
	return [lv, beacon, ctl]


# A controller with Last Light armed (unspent, 1 charge held).
static func _armed_ctl() -> RefCounted:
	var ctl = ControllerScript.new()
	ctl.setup("dasher", ControllerScript.load_constants())
	ctl.charges = 1
	ctl.last_light_spent = false
	return ctl


## MinesScript.tick's minimal holder (test_mines' contract, re-used).
static func _hold(lv: RefCounted, ctl) -> Dictionary:
	return {"mines": lv.mines, "players": [{"x": float(ctl.x), "y": float(ctl.y),
			"z": float(ctl.z)}], "beacon": lv.beacon}


## Seeds where the slot-1 defuse roll passes (want) / fails at `stacks` stacks.
static func _seed_defuse(slot: int, stacks: int, want: bool) -> int:
	for s in range(1, 200000):
		if MinesScript.defuse_roll(s, 1, slot, stacks) == want:
			return s
	return -1


## One ladder run: the armed controller on the mine tile, barrier held, the given
## defuse stacks; one 60 Hz pass; returns [lv, beacon, ctl, events].
static func _run_ladder(seed: int, stacks: int) -> Array:
	var parts: Array = _mine_setup(seed)
	var lv: RefCounted = parts[0]
	var ev: Array = []
	MinesScript.tick(_hold(lv, parts[2]), [parts[2]], {"dais": [0, 0, 1], "enemies": []},
			[stacks], 7, ev)
	return [lv, parts[1], parts[2], ev]


func _test_defuse_kit(f: Array[String]) -> void:
	# 1. THE ROLL, verbatim (D-053): mix(mix(run_seed, level), slot_id) mod 100
	#    < 20 x stacks (cap 60); 0 stacks can never pass; pure in the four inputs.
	var agree := true
	for k in 200:
		var seed_v: int = 1000 + k
		var manual: int = VoidRngScript.mix(VoidRngScript.mix(seed_v, 3), 2) % 100
		if MinesScript.defuse_roll(seed_v, 3, 2, 1) != (manual < 20):
			agree = false
		if MinesScript.defuse_roll(seed_v, 3, 2, 2) != (manual < 40):
			agree = false
		if MinesScript.defuse_roll(seed_v, 3, 2, 3) != (manual < 60):
			agree = false
	_expect(f, agree, "defuse kit: the roll is not mix(mix(seed,level),slot)%100 < 20xstacks")
	var cap_ok := true
	for k in 200:
		var seed_v2: int = 50000 + k
		var manual2: int = VoidRngScript.mix(VoidRngScript.mix(seed_v2, 3), 2) % 100
		if MinesScript.defuse_roll(seed_v2, 3, 2, 4) != (manual2 < 60):
			cap_ok = false
		if MinesScript.defuse_roll(seed_v2, 3, 2, 9) != (manual2 < 60):
			cap_ok = false
	_expect(f, cap_ok, "defuse kit: the 60 cap is broken at 4+ stacks")
	var zero_ok := true
	for k in 3000:
		if MinesScript.defuse_roll(k, 7, 1 + k % 5, 0):
			zero_ok = false
	_expect(f, zero_ok, "defuse kit: a 0-stack roll passed")
	# THE ORDER (D-053): with a PASSING roll the mine is DEFUSED even though a
	# barrier is held and Last Light is armed - consumed, no blast, no death, the
	# chain resets, the barrier survives, Last Light is not spent.
	var seed_pass := _seed_defuse(1, 1, true)
	_expect(f, seed_pass > 0, "defuse kit: no passing seed found")
	if seed_pass < 0:
		return
	var r: Array = _run_ladder(seed_pass, 1)
	var lv: RefCounted = r[0]
	var beacon: RefCounted = r[1]
	var ctl: RefCounted = r[2]
	var ev: Array = r[3]
	_expect(f, _kind(ev, "mine_defused") == 1, "defuse kit: no mine_defused on a passing roll")
	_expect(f, not bool(ctl.dead) and _kind(ev, "mine_detonated") == 0,
			"defuse kit: the defused mine exploded or killed")
	_expect(f, lv.mines.is_consumed(1), "defuse kit: the defused mine was not consumed")
	_expect(f, bool(beacon.has_barrier(0)), "defuse kit: the defuse path consumed the barrier")
	_expect(f, int(ctl.charges) == 1 and not bool(ctl.last_light_spent),
			"defuse kit: the defuse path fell through to Last Light")
	_expect(f, _kind(ev, "chain_reset") == 1, "defuse kit: the defuse did not reset the chain")


func _test_subspacial_barrier(f: Array[String]) -> void:
	# THE ORDER: the shield runs AFTER the defuse roll - a FAILING roll (0 stacks)
	# with a held barrier and an armed Last Light resolves as the SHIELD path: the
	# shield and the mine are consumed, no blast, no death, the chain resets, and
	# Last Light is NOT reached (charges stay, save unspent).
	var seed_open := _seed_defuse(1, 1, false)
	_expect(f, seed_open > 0, "barrier: no failing seed found")
	if seed_open < 0:
		return
	var r: Array = _run_ladder(seed_open, 0)
	var lv: RefCounted = r[0]
	var beacon: RefCounted = r[1]
	var ctl: RefCounted = r[2]
	var ev: Array = r[3]
	_expect(f, _kind(ev, "mine_shielded") == 1,
			"barrier: a held shield after a failed roll did not shield the mine")
	_expect(f, not bool(beacon.has_barrier(0)),
			"barrier: the shielded mine did not consume the shield")
	_expect(f, lv.mines.is_consumed(1), "barrier: the shielded mine was not consumed")
	_expect(f, not bool(ctl.dead) and _kind(ev, "mine_detonated") == 0,
			"barrier: the shielded mine exploded or killed")
	_expect(f, int(ctl.charges) == 1 and not bool(ctl.last_light_spent),
			"barrier: the shield path fell through to Last Light")
	_expect(f, _kind(ev, "chain_reset") == 1, "barrier: the shield did not reset the chain")
	# NOTHING ABSORBS THE NUKE: the same held barrier survives an outright
	# non-mine kill (the nuke's D-NUKE kill runs the kill API, no ladder); the
	# charge was set to 0 so Last Light cannot interfere, the kill still kills,
	# and the barrier is still held afterwards (tripmines only, D-051).
	var parts2: Array = _mine_setup(seed_open)
	var ctl2: RefCounted = parts2[2]
	var beacon2: RefCounted = parts2[1]
	ctl2.charges = 0
	var ev2: Array = []
	var saved: bool = ctl2.try_kill("D-NUKE", "nuke", {"dais": [0, 0, 1]}, ev2)
	_expect(f, not saved and bool(ctl2.dead),
			"barrier: the nuke kill did not kill at 0 charges")
	_expect(f, bool(beacon2.has_barrier(0)),
			"barrier: the nuke kill consumed the Subspacial Barrier - nothing absorbs the nuke")
