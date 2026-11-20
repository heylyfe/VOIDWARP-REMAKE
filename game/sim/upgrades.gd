extends RefCounted
#
# sim/upgrades.gd - the scripted-upgrade engine (ticket T-053; DESIGN.md section 8,
# dispatch addendum R4, D-T053-1..8).
#
# This batch's scripted upgrades are computed here behind ROLE strings, never literal
# upgrade ids: the boundary scan (tests/test_boundaries.gd) forbids content ids under
# sim/, so the id -> role pairing and each id's own numbers live in one thin
# content/upgrades/<id>.gd script (the T-051 curse-script convention). The roles:
#   mine_radar      - disguised tripmines within 14 u get a pink outline through fog
#   gift_radar      - nearest real gift within 40 u (80 u at 2 stacks)
#   threat_radar    - enemies within 30 u
#   beacon_compass  - compass heading and distance to the beacon
#   footprint_map   - every piece within 40 u of anywhere the player has stood
#   skeleton_quota  - the beacon opens at 90 % of real black gifts
#   beacon_channel  - once per level, 180-tick standing-still channel to the dais
#
# Pure sim: no engine types beyond Array/Dictionary, no RNG, fixed 60 Hz tick (the
# channel is tick-counted, D-T053-3). The radar queries are read-only; the only state
# is the footprint-map memory and the beacon channel, both per player index.
#
# The section 3.3 mine-contact ladder does NOT live here: sim/mines.gd (T-021) owns
# it and this module never replaces it - the Defuse Kit roll and the Subspacial
# Barrier shield are consumed by mines.gd in the fixed order defuse roll -> barrier
# -> Last Light -> death (D-058, D-053).

const InputScript := preload("res://sim/input.gd")
# NOTE: no preload of level_state.gd here - level_state.gd preloads this script, and
# a cyclic preload refuses to parse. floor_i() is duplicated below instead (level_state's
# own floor_i, one branch apart, D-T053-2's footprint tile read).

## Role keys (D-T053-1); content scripts map their id onto exactly one of these.
const ROLE_MINE_RADAR := "mine_radar"
const ROLE_GIFT_RADAR := "gift_radar"
const ROLE_THREAT_RADAR := "threat_radar"
const ROLE_BEACON_COMPASS := "beacon_compass"
const ROLE_CARTOGRAPHER := "footprint_map"
const ROLE_SKELETON_QUOTA := "skeleton_quota"
const ROLE_BEACON_CHANNEL := "beacon_channel"

## Radar ranges (addendum R4 + the DESIGN.md section 8 table, verbatim).
const MINE_RADAR_RANGE := 14.0
const GIFT_RADAR_RANGE := 40.0
const GIFT_RADAR_RANGE_AT_2 := 80.0
const THREAT_RADAR_RANGE := 30.0
const CARTOGRAPHER_RANGE := 40.0
## Skeleton Key opens the beacon at 90 % of the real black gifts, rounded up.
const SKELETON_PCT := 0.9
## Pocket Beacon channel: 3.0 s = exactly 180 ticks at 60 Hz (addendum R4).
const CHANNEL_SECONDS := 3.0
const CHANNEL_TICKS := 180

## The roles dict as the caller supplied it (read-only shared data).
var roles: Dictionary = {}
## Footprint-map memory: player index -> {Vector2i tile: true} (D-T053-2).
var visited: Dictionary = {}
## Pocket Beacon channel ticks held, per player index.
var channels: Dictionary = {}
## Pocket Beacon spent flag: player index -> true once the teleport fired.
var channel_used: Dictionary = {}


## roles: {role key: true or value}. Empty roles -> null, so the sim's default path
## (no upgrades bought) stays byte-for-byte the pre-T-053 behaviour.
static func create(p_roles: Dictionary) -> RefCounted:
	if p_roles.is_empty():
		return null
	var u := new()
	u.roles = p_roles
	return u


func has(role: String) -> bool:
	return bool(roles.get(role, false))


## floor() without floor(): comparisons and int truncation only (level_state's own
## floor_i, here without the cyclic preload).
static func floor_i(v: float) -> int:
	var i := int(v)
	if v < 0.0 and float(i) != v:
		i -= 1
	return i


## Skeleton Key (D-T053-4): the collection count that opens the beacon - 90 % of the
## REAL black gifts, rounded up (10 gifts -> 9; 11 -> 10; never below 1 for a
## non-empty level).
static func skeleton_threshold(total_real: int) -> int:
	return int(ceil(float(total_real) * SKELETON_PCT))


# ------------------------------------------------------------- radar queries --------

## Beacon compass: world-space delta from the query point to the beacon's tile
## centre and the straight-line distance in u; {} when the level has no beacon.
static func beacon_compass(lv: RefCounted, px: float, pz: float) -> Dictionary:
	var b: RefCounted = lv.beacon
	if b == null:
		return {}
	var dx: float = float(b.cx) - px
	var dz: float = float(b.cz) - pz
	return {"dx": dx, "dz": dz, "dist": sqrt(dx * dx + dz * dz)}


## Nearest REAL gift (occ == 0 slot, never collected; mines are never information)
## within range_u of the query point: {slot, x, z, dist} or {}.
static func nearest_real_gift(lv: RefCounted, px: float, pz: float,
		range_u: float) -> Dictionary:
	var g: RefCounted = lv.gifts
	if g == null:
		return {}
	var best: Dictionary = {}
	var best_d2 := range_u * range_u
	for i in g.slots.size():
		if not g.present(i):
			continue
		var pos: Vector3 = g.position_of(i)
		var dx: float = px - pos.x
		var dz: float = pz - pos.z
		var d2: float = dx * dx + dz * dz
		if d2 <= best_d2:
			best_d2 = d2
			best = {"slot": i, "x": pos.x, "z": pos.z, "dist": sqrt(d2)}
	return best


## Mine radar: every UNCONSUMED mine slot within range_u of the query point. The
## candidate set is exactly mines.ids (the occ == 1 slots, T-021) filtered by
## consumption and distance - no slot without a mine and no mine beyond the range
## ever reaches the outline.
static func mine_outline_ids(mines: RefCounted, px: float, pz: float,
		range_u: float = MINE_RADAR_RANGE) -> Array:
	var out: Array = []
	if mines == null:
		return out
	var r2 := range_u * range_u
	for slot in mines.ids:
		if mines.is_consumed(slot):
			continue
		var c: Vector3 = mines.point(slot)
		var dx: float = px - c.x
		var dz: float = pz - c.z
		if dx * dx + dz * dz <= r2:
			out.append(slot)
	return out


## Threat radar: every enemy mirror (world["enemies"] rows: x, y, z, r) within
## range_u of the query point, nearest first: {x, z, dist} rows.
static func threat_markers(enemies: Array, px: float, pz: float,
		range_u: float = THREAT_RADAR_RANGE) -> Array:
	var out: Array = []
	for e in enemies:
		var dx: float = px - float(e["x"])
		var dz: float = pz - float(e["z"])
		var d2: float = dx * dx + dz * dz
		if d2 <= range_u * range_u:
			out.append({"x": float(e["x"]), "z": float(e["z"]), "dist": sqrt(d2)})
	out.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))
	return out


# -------------------------------------------------------- footprint map (D-T053-2) --

## One tick of footprint memory: records the 1 u tile under the player's centre.
func note_footprint(p_index: int, px: float, pz: float) -> void:
	var tile := Vector2i(floor_i(px), floor_i(pz))
	if not visited.has(p_index):
		visited[p_index] = {}
	visited[p_index][tile] = true


## Every piece within range_u of any recorded tile centre, as minimap rows:
##   {"kind": "gift", "slot": i, "x", "z", "piece", "tier"}   an uncollected real gift
##   {"kind": "mine", "slot": i, "x", "z", "piece", "tier"}   an unconsumed tripmine
##   {"kind": "beacon", "x", "z"}                             the beacon itself
func revealed(lv: RefCounted, p_index: int, range_u: float = CARTOGRAPHER_RANGE) -> Array:
	var out: Array = []
	if not visited.has(p_index):
		return out
	var tiles: Dictionary = visited[p_index]
	var r2 := range_u * range_u
	var g: RefCounted = lv.gifts
	if g != null:
		for i in g.slots.size():
			var pos: Vector3 = g.position_of(i)
			if not _near_any(tiles, pos.x, pos.z, r2):
				continue
			if g.is_real(i):
				if not g.present(i):
					continue
				out.append({"kind": "gift", "slot": i, "x": pos.x, "z": pos.z,
						"piece": str(g.slots[i]["piece"]), "tier": int(g.slots[i]["tier"])})
			elif lv.mines != null and not lv.mines.is_consumed(i):
				out.append({"kind": "mine", "slot": i, "x": pos.x, "z": pos.z,
						"piece": str(g.slots[i]["piece"]), "tier": int(g.slots[i]["tier"])})
	var b: RefCounted = lv.beacon
	if b != null and _near_any(tiles, float(b.cx), float(b.cz), r2):
		out.append({"kind": "beacon", "x": float(b.cx), "z": float(b.cz)})
	return out


static func _near_any(tiles: Dictionary, x: float, z: float, r2: float) -> bool:
	for tile in tiles:
		var dx: float = x - (float(tile.x) + 0.5)
		var dz: float = z - (float(tile.y) + 0.5)
		if dx * dx + dz * dz <= r2:
			return true
	return false


# ------------------------------------------- pocket beacon channel (D-T053-3) -------

## One per-tick pass for one player: the footprint-map note, then the
## beacon channel. Called from sim.gd after the movement step (and, on the
## controller path, by its owner the same way after the step). inp: this tick's
## PlayerInput; prev_buttons: last tick's button bitmask (the edges).
func step_player(lv: RefCounted, p_index: int, inp, prev_buttons: int,
		events: Array) -> void:
	if has(ROLE_CARTOGRAPHER):
		var p: Dictionary = lv.players[p_index]
		note_footprint(p_index, float(p["x"]), float(p["z"]))
	if has(ROLE_BEACON_CHANNEL):
		_channel_step(lv, p_index, lv.players[p_index], inp, prev_buttons, events)


## The Pocket Beacon channel. Start: the INTERACT press edge while standing still
## (D-T053-3 [CONTESTABLE]: DESIGN.md section 8 names no activation button and owns
## only the channel length and the stand-still rule). Cancel: any input OTHER
## than the channel button - any other button (pressed OR held), any move axis,
## leaving the ground. Fill: after CHANNEL_TICKS ticks held, the player's row
## teleports to the beacon dais centre and the beacon_teleport event fires; the
## beacon's own state machine is untouched.
##
## The channel button is excluded from the cancel test on purpose. A human press
## lasts several 16.7 ms ticks, so counting a held INTERACT as a cancel made the
## channel unfinishable: the press edge started it on tick N and the same key,
## still down, killed it on tick N+1. Only a one-tick tap could ever fill it.
func _channel_step(lv: RefCounted, p_index: int, p: Dictionary, inp,
		prev_buttons: int, events: Array) -> void:
	var buttons := int(inp.buttons)
	if channels.has(p_index):
		var other_buttons := buttons & ~InputScript.BUTTON_INTERACT
		if other_buttons != 0 or float(inp.move_x) != 0.0 or float(inp.move_z) != 0.0 \
				or not bool(p.get("grounded", true)):
			channels.erase(p_index)
			events.append({"e": "beacon_channel_cancelled", "player": p_index})
			return
		var ch: Dictionary = channels[p_index]
		ch["t"] = int(ch["t"]) + 1
		if int(ch["t"]) < CHANNEL_TICKS:
			return
		channels.erase(p_index)
		channel_used[p_index] = true
		var b: RefCounted = lv.beacon
		if b != null:
			p["x"] = float(b.cx)
			p["z"] = float(b.cz)
			p["y"] = float(b.base_y)
			p["vx"] = 0.0
			p["vz"] = 0.0
			p["vy"] = 0.0
			p["grounded"] = true
		events.append({"e": "beacon_teleport", "player": p_index})
		return
	var interact_edge := (buttons & InputScript.BUTTON_INTERACT) != 0 \
			and (prev_buttons & InputScript.BUTTON_INTERACT) == 0
	if not interact_edge or bool(channel_used.get(p_index, false)) \
			or float(inp.move_x) != 0.0 or float(inp.move_z) != 0.0 \
			or not bool(p.get("grounded", false)):
		return
	channels[p_index] = {"t": 0}
	events.append({"e": "beacon_channel_started", "player": p_index})
