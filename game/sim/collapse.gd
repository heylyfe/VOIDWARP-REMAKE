extends RefCounted
#
# sim/collapse.gd - the platform collapse after the beacon opens.
#
# Owner request 2026-11-20: "the platform should have cracks on them and 5s later they fall
# down to the void. The only platform that cannot be destroyed is the spawn platform."
# Owner correction 2026-11-21 (D-B10-1, supersedes D-B6-2's one global fall): the collapse is
# SEQUENTIAL, outside in, like a shrinking safe zone. The level is cut into ZONES by distance
# from the hub; the farthest zone cracks, falls 5.0 s later, then 10.0 s of nothing, then the
# next-closer zone cracks, and so on inward until only the hub is left. One zone cracks at a time.
#
# Every number lives in res://data/collapse.json (crack_to_fall_s, gap_after_fall_s, the zone
# width and the zone-count clamp); this file only holds the rule.
#
# The zone rule (create): every non-hub piece - a platform or a bridge, never a single tile -
# goes into exactly one zone, by the XZ distance from the dais centre to the piece's NEAREST
# tile centre (integer dx, dz, so the distance is sqrt of an int). The level radius R is the
# largest such distance; N = clamp(ceil(R / zone_width_u), zone_min, zone_max); band =
# min(N - 1, floor(d * N / R)). Bands no piece falls into are dropped, so there is no empty
# wait. Zones are stored in FALL ORDER: zones[0] is the farthest band and falls first.
#
# Pure, tick-driven state (a Dictionary; static functions only; no engine clock, no RNG):
#   create(level)        - built once per level from the Level dict. The hub (voidgen ROLE_HUB,
#                          the one spawn platform) is excluded at the source.
#   start(st, tick)      - the beacon-open tick: zones[0] cracks on this tick.
#   tick(st, tick, w, ev)- zone i cracks on start + i * (crack + gap) and falls `crack` ticks
#                          later: its tile keys are written into w["removed"] (collision
#                          tile_alive / support_at already honour it) and its prop boxes leave
#                          w["prop_cols"]. Nothing here touches a player: a body left without
#                          support drops through the controller's own kill plane.
#
# Timing at the fixed 60 Hz (collision.gd header, world.gd DT = 1/60): with the shipped data
# a zone is cracked on [crack_tick, crack_tick + 299] and gone from crack_tick + 300; the next
# zone cracks 600 ticks after that, so zone i cracks at start + 900 i.
#
# The schedule is a pure function of (level, start_tick); the live fields (phase, cur,
# fallen_n, removed_n, start_tick) are dumped by sim/state_hash.gd's COLLAPSE line.

const VoidGenScript := preload("res://terrain/voidgen.gd")
const CollisionScript := preload("res://sim/collision.gd")

const CONFIG_PATH := "res://data/collapse.json"
const TICK_HZ := 60

const EV_CRACKED := "platforms_cracked"   # + zone: int, n: int (tiles cracked), fall_tick: int
const EV_FELL := "platforms_fell"         # + zone: int, n: int (tiles removed from collision)

const PHASE_IDLE := 0       # beacon not open yet
const PHASE_CRACKING := 1   # zones[cur] is cracking
const PHASE_FALLEN := 2     # every zone is gone; only the hub is left
const PHASE_WAITING := 3    # the gap after a fall; zones[cur] cracks at crack_tick

const ZONE_IDLE := 0
const ZONE_CRACKING := 1
const ZONE_FALLEN := 2

static var _cfg_cache: Dictionary = {}


## The collapse numbers from res://data/collapse.json (read once, then cached).
static func config() -> Dictionary:
	if not _cfg_cache.is_empty():
		return _cfg_cache
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		push_error("collapse: %s missing" % CONFIG_PATH)
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		push_error("collapse: %s unreadable" % CONFIG_PATH)
		return {}
	_cfg_cache = d
	return _cfg_cache


## The hub piece id of a Level dict (-1 when the dict carries none). Identified by the
## generator's own role tag, never by coordinates.
static func hub_piece(level: Dictionary) -> int:
	for p in level.get("pieces", []):
		if int(p.get("role", -1)) == VoidGenScript.ROLE_HUB:
			return int(p["id"])
	return -1


## The zone count for a level of radius r_u (the data's rule; pure, for tests and probes).
static func zone_count_for(r_u: float, cfg: Dictionary = {}) -> int:
	var c: Dictionary = cfg if not cfg.is_empty() else config()
	var width: float = maxf(float(c.get("zone_width_u", 16.0)), 0.001)
	var n := ceili(r_u / width) if r_u > 0.0 else 1
	return clampi(n, int(c.get("zone_min", 1)), int(c.get("zone_max", 6)))


## A fresh collapse state for one level. cfg overrides res://data/collapse.json (tests).
static func create(level: Dictionary, cfg: Dictionary = {}) -> Dictionary:
	var c: Dictionary = cfg if not cfg.is_empty() else config()
	var hub := hub_piece(level)
	var bx := 0
	var bz := 0
	var b: Array = level.get("beacon", [0, 0, 1])
	if b.size() >= 2:
		bx = int(b[0])
		bz = int(b[1])
	# pass 1: every non-hub piece's nearest-tile squared distance to the dais (ints)
	var piece_d2 := {}
	var hub_keys := {}
	for t in level.get("tiles", []):
		var pid := int(t[4])
		var key: String = CollisionScript.tile_key(int(t[0]), int(t[1]), int(t[2]))
		if pid == hub:
			hub_keys[key] = true
			continue
		var dx := int(t[0]) - bx
		var dz := int(t[1]) - bz
		var d2 := dx * dx + dz * dz
		if not piece_d2.has(pid) or d2 < int(piece_d2[pid]):
			piece_d2[pid] = d2
	var r2 := 0
	for pid in piece_d2:
		r2 = maxi(r2, int(piece_d2[pid]))
	var radius := sqrt(float(r2))
	var n := zone_count_for(radius, c)
	var band_of := {}
	for pid in piece_d2:
		var bd := 0
		if radius > 0.0:
			bd = mini(n - 1, floori(sqrt(float(piece_d2[pid])) * float(n) / radius))
		band_of[pid] = bd
	# pass 2: tiles and props into their band, in the Level dict's order (deterministic)
	var bands: Array = []
	for bi in n:
		bands.append({"band": bi, "pieces": {}, "keys": [], "key_set": {}, "props": [],
				"d_min": INF, "d_max": 0.0})
	var keys: Array = []
	var seen := {}
	var zone_band := {}   # key -> band
	for t in level.get("tiles", []):
		var pid := int(t[4])
		if pid == hub:
			continue
		var key: String = CollisionScript.tile_key(int(t[0]), int(t[1]), int(t[2]))
		if seen.has(key) or hub_keys.has(key):
			continue
		seen[key] = true
		keys.append(key)
		var z: Dictionary = bands[int(band_of[pid])]
		(z["pieces"] as Dictionary)[pid] = true
		(z["keys"] as Array).append(key)
		(z["key_set"] as Dictionary)[key] = true
		var dd := sqrt(float((int(t[0]) - bx) * (int(t[0]) - bx) + (int(t[1]) - bz) * (int(t[1]) - bz)))
		z["d_min"] = minf(float(z["d_min"]), dd)
		z["d_max"] = maxf(float(z["d_max"]), dd)
		zone_band[key] = int(band_of[pid])
	var props: Array = []
	for p in level.get("props", []):
		var pid := int(p[5])
		if pid == hub or not band_of.has(pid):
			continue
		var pr := ["%d,%d" % [int(p[0]), int(p[1])], int(p[2]), int(p[3])]
		props.append(pr)
		(bands[int(band_of[pid])]["props"] as Array).append(pr)
	# fall order: farthest band first; a band no piece landed in is dropped
	var zones: Array = []
	var zone_of := {}
	for i in range(n - 1, -1, -1):
		var z: Dictionary = bands[i]
		if (z["keys"] as Array).is_empty():
			continue
		for key in z["keys"]:
			zone_of[key] = zones.size()
		zones.append(z)
	var crack := maxi(1, roundi(float(c.get("crack_to_fall_s", 5.0)) * TICK_HZ))
	var gap := maxi(0, roundi(float(c.get("gap_after_fall_s", 10.0)) * TICK_HZ))
	return {
		"enabled": true,
		"hub_piece": hub,
		"hub_keys": hub_keys,   # read-only reference for views and tests
		"keys": keys,           # every listed key, all zones (Level dict order)
		"key_set": seen,
		"props": props,
		"zones": zones,         # fall order: zones[0] = the farthest band
		"zone_of": zone_of,     # key -> index into zones
		"radius": radius,
		"bands": n,
		"crack_ticks": crack,
		"gap_ticks": gap,
		"partition": _partition_digest(zones),   # pins the zone assignment in the state hash
		"phase": PHASE_IDLE,
		"start_tick": -1,
		"cur": 0,               # the zone cracking now, or next to crack
		"crack_tick": -1,       # zones[cur]'s crack tick
		"fall_tick": -1,        # zones[cur]'s fall tick
		"fallen_n": 0,          # zones gone so far
		"removed_n": 0,         # tiles gone so far
	}


## A 16-hex digest of the zone assignment, computed once at create() and carried in the state so
## sim/state_hash.gd can pin it. Without this the hash would only pin the live schedule, and two
## runs whose collapse.json differed (zone width, the clamp, the crack/gap seconds) would hash
## the same until the first zone fell, then diverge - a real collision, not a theoretical one.
## Keys are sorted per zone so the digest does not depend on the Level dict's tile order.
static func _partition_digest(zones: Array) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for zi in zones.size():
		var ks: Array = (zones[zi]["keys"] as Array).duplicate()
		ks.sort()
		ctx.update(("Z%d|%s\n" % [zi, ",".join(ks)]).to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)


## The beacon-open tick: zones[0] cracks now. Returns its platforms_cracked event ({} when
## the state is disabled, already started, or has nothing to crack).
static func start(st: Dictionary, tick: int) -> Dictionary:
	if st.is_empty() or not bool(st.get("enabled", true)):
		return {}
	if int(st["phase"]) != PHASE_IDLE:
		return {}
	st["start_tick"] = tick
	if (st["zones"] as Array).is_empty():
		st["phase"] = PHASE_FALLEN
		return {}
	st["cur"] = 0
	return _crack(st, tick)


static func _crack(st: Dictionary, tick: int) -> Dictionary:
	var ct := zone_crack_tick(st, int(st["cur"]))
	st["phase"] = PHASE_CRACKING
	st["crack_tick"] = ct
	st["fall_tick"] = ct + int(st["crack_ticks"])
	return {"e": EV_CRACKED, "tick": tick, "zone": int(st["cur"]),
			"n": (st["zones"][int(st["cur"])]["keys"] as Array).size(),
			"fall_tick": int(st["fall_tick"])}


## One sim tick of the schedule. Returns the tile keys removed on this tick ([] on every tick
## that is not a fall). Appends platforms_fell / platforms_cracked events to ev when given.
static func tick(st: Dictionary, p_tick: int, w: Dictionary, ev: Variant = null) -> Array:
	var out: Array = []
	if st.is_empty():
		return out
	while true:
		var ph := int(st["phase"])
		if ph == PHASE_CRACKING and p_tick >= int(st["fall_tick"]):
			var zi := int(st["cur"])
			var got := _fall(st["zones"][zi], w)
			out.append_array(got)
			st["fallen_n"] = int(st["fallen_n"]) + 1
			st["removed_n"] = int(st["removed_n"]) + got.size()
			if ev is Array:
				(ev as Array).append({"e": EV_FELL, "tick": p_tick, "zone": zi, "n": got.size()})
			if zi + 1 < (st["zones"] as Array).size():
				st["cur"] = zi + 1
				st["phase"] = PHASE_WAITING
				st["crack_tick"] = zone_crack_tick(st, zi + 1)
				st["fall_tick"] = int(st["crack_tick"]) + int(st["crack_ticks"])
			else:
				st["phase"] = PHASE_FALLEN
			continue
		if ph == PHASE_WAITING and p_tick >= int(st["crack_tick"]):
			var cev := _crack(st, p_tick)
			if ev is Array:
				(ev as Array).append(cev)
			continue
		break
	return out


static func _fall(z: Dictionary, w: Dictionary) -> Array:
	var out: Array = []
	var removed: Dictionary = w["removed"]
	for key in z["keys"]:
		if not removed.has(key):
			removed[key] = true
		out.append(key)
	var pcols: Dictionary = w.get("prop_cols", {})
	for pr in z["props"]:
		var lst: Array = pcols.get(pr[0], [])
		for i in range(lst.size() - 1, -1, -1):
			if int(lst[i]["y"]) == int(pr[1]) and int(lst[i]["h"]) == int(pr[2]):
				lst.remove_at(i)
				break
		if lst.is_empty() and pcols.has(pr[0]):
			pcols.erase(pr[0])
	return out


# ---- read-only queries (views, bot, tests) ------------------------------------------

static func phase(st: Dictionary) -> int:
	return PHASE_IDLE if st.is_empty() else int(st["phase"])


## True while some zone's cracks are showing.
static func is_cracking(st: Dictionary) -> bool:
	return phase(st) == PHASE_CRACKING


static func zone_count(st: Dictionary) -> int:
	return 0 if st.is_empty() else (st["zones"] as Array).size()


## The tile keys of zone i (fall order), [] when out of range.
static func zone_keys(st: Dictionary, i: int) -> Array:
	if i < 0 or i >= zone_count(st):
		return []
	return st["zones"][i]["keys"]


## The zone index (fall order) of tile key "x,z,y_hu", -1 for a hub or unknown key.
static func zone_of(st: Dictionary, key: String) -> int:
	if st.is_empty():
		return -1
	return int((st["zone_of"] as Dictionary).get(key, -1))


## The tick zone i cracks on (-1 before the collapse started). Pure in start_tick.
static func zone_crack_tick(st: Dictionary, i: int) -> int:
	if st.is_empty() or int(st["start_tick"]) < 0:
		return -1
	return int(st["start_tick"]) + i * (int(st["crack_ticks"]) + int(st["gap_ticks"]))


## The tick zone i falls on (-1 before the collapse started).
static func zone_fall_tick(st: Dictionary, i: int) -> int:
	var ct := zone_crack_tick(st, i)
	return -1 if ct < 0 else ct + int(st["crack_ticks"])


## Ticks from the start to zone i's fall, known before the collapse starts (probes, bot).
static func zone_fall_offset(st: Dictionary, i: int) -> int:
	return i * (int(st["crack_ticks"]) + int(st["gap_ticks"])) + int(st["crack_ticks"])


## The fall tick of tile key `key` (-1 for a hub tile or before the start).
static func key_fall_tick(st: Dictionary, key: String) -> int:
	var zi := zone_of(st, key)
	return -1 if zi < 0 else zone_fall_tick(st, zi)


## ZONE_IDLE / ZONE_CRACKING / ZONE_FALLEN for zone i on p_tick, from the live state.
static func zone_phase(st: Dictionary, i: int) -> int:
	if st.is_empty() or i < 0 or i >= zone_count(st):
		return ZONE_IDLE
	if i < int(st["fallen_n"]):
		return ZONE_FALLEN
	if i == int(st["cur"]) and phase(st) == PHASE_CRACKING:
		return ZONE_CRACKING
	return ZONE_IDLE


## The tile keys cracked right now: the one cracking zone's keys ([] in a gap).
static func cracked_keys(st: Dictionary) -> Array:
	if phase(st) != PHASE_CRACKING:
		return []
	return st["zones"][int(st["cur"])]["keys"]


## True when tile key "x,z,y_hu" is part of the collapse (never a hub tile).
static func listed(st: Dictionary, key: String) -> bool:
	return not st.is_empty() and (st["key_set"] as Dictionary).has(key)


## 0..1 progress through zone i's crack phase on p_tick (1.0 once fallen, 0.0 before).
static func crack_progress(st: Dictionary, p_tick: int, i: int = -1) -> float:
	if i < 0:
		i = int(st.get("cur", 0))
	match zone_phase(st, i):
		ZONE_CRACKING:
			return clampf(float(p_tick - zone_crack_tick(st, i)) / float(st["crack_ticks"]), 0.0, 1.0)
		ZONE_FALLEN:
			return 1.0
	return 0.0


## Ticks since zone i fell (-1 before it). i defaults to the last zone that fell.
static func ticks_since_fall(st: Dictionary, p_tick: int, i: int = -1) -> int:
	if i < 0:
		i = int(st.get("fallen_n", 0)) - 1
	if zone_phase(st, i) != ZONE_FALLEN:
		return -1
	return p_tick - zone_fall_tick(st, i)
