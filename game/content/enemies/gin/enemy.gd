extends "res://sim/enemy_runtime.gd".EnemyBehavior
#
# gin ichimaru behavior (ticket T-041; DESIGN.md section 5.12 + the binding table,
# research/fable-tickets.md section 1.12). One strike cycle, in 60 Hz ticks:
#
#   fade in (30) -> mark (120) -> launch (18) -> void zone (600) -> fade back (30)
#   -> cooldown 840 - 180*(extra votes), min 300 -> fade in again (30) -> mark ...
#
#   - fade-in tile (D-072): 15-25 u from the player (bounds inclusive), farthest from
#     the player first, lowest tile index on ties; never the beacon dais cell; if no
#     tile qualifies, the farthest tile of the spawn hub (tiles within HUB_RADIUS of
#     the level's first `open` anchor). The platform-tile-only filter is recorded in
#     DECISIONS.md (D-T041-2): the section 12 surface returns no platform/walkway bit
#     on the tile rows, so on this sim surface the filter is the distance window and
#     the hub fallback only.
#   - the mark: the 5x5 tile patch centred on the player's tile, red outline #FF2A2A,
#     blinking 2 Hz (ticks 0-59) then 4 Hz (ticks 60-119), cracks reach the patch edge
#     on tick 120 (view layer). Announced through api.telegraph(kind "mark").
#   - tick 120: launch pose; the sword-spears streak to the patch over 18 ticks -
#     VIEW-LAYER ONLY (ENEMIES.md global note), never simulated, no projectiles.
#   - tick 120 + 18 = 138: the patch becomes a void zone for 600 ticks (10 s): the
#     tiles go non-solid (the view/mesher's concern - the zone is declared on the row
#     for the view) and anything that enters its column is KILLED with code D-GIN.
#   - the body fades out 60 ticks after the launch (tick 180 overall) - anim only.
#   - SR-4 / yields_to ["address_me"]: the strike NEVER STARTS while a live address
#     me countdown runs; the gate defers the start (api.arbiter_gate(pending)), the
#     countdown keeps ticking, and the mark lands on the first free tick that follows.
#   - never marks the beacon dais: the dais cell is cut out of the marked patch
#     (D-T041-3); the dais is never inside the lethal column.
#
# The sim never expires telegraph footprints (PARKED.md row 9): every timing here
# lives in this row's own state and is never read back off footprint lifetimes.
# The kill goes through api.kill - the controller answers (Last Light, D-057, is the
# controller's call, never the enemy's).

const GIN_ID := "gin"
const DEATH_CODE := "D-GIN"
const SwordAttack := preload("res://content/enemies/gin/sword_attack.gd")

# phases of the cycle (row["phase"]); each carries its own tick counter, row["phase_t"]
const SPAWN := "spawn"            # the fade-in, 30 ticks
const MARK := "mark"              # the 120-tick telegraph
const LAUNCH := "launch"          # the 18-tick spear flight
const VOID := "void"              # the 600-tick void zone
const FADE_BACK := "fade_back"    # the 30-tick fade
const COOLDOWN := "cooldown"      # 840 - 180 * extra votes, min 300

# anim state ids - exactly the anim block's state ids (content/enemies/gin/sprites.json,
# section 1.12); row["anim_state"] never carries anything else
const ANIM_SPAWN := "spawn"
const ANIM_IDLE := "idle"
const ANIM_TELEGRAPH := "telegraph"
const ANIM_LAUNCH := "attack_launch"
const ANIM_VOID := "attack_void_zone"
const ANIM_RECOVER := "recover"

# timings (DESIGN.md 5.12 / the section 1.12 table)
const SPAWN_TICKS := 30             # 0.5 s fade-in
const TELEGRAPH_TICKS := 120        # 2.0 s mark
const SPEAR_TRAVEL_TICKS := 18      # 0.3 s spear flight (view-layer only)
const ZONE_TICKS := 600             # 10.0 s void zone
const FADE_BACK_TICKS := 30         # 0.5 s tiles fade back
const FADE_OUT_TICKS := 60          # the body fades out 60 ticks after the launch
const COOLDOWN_TICKS := 840         # 14 s
const COOLDOWN_VOTE_DISCOUNT := 180 # -3 s per extra vote
const COOLDOWN_MIN := 300           # 5 s floor

# D-072 spawn geometry
const SPAWN_DIST_MIN := 15.0        # the 15-25 u rule, bounds inclusive
const SPAWN_DIST_MAX := 25.0
const PATCH_HALF := 2               # 5x5 tiles: centre +/- 2
const HUB_RADIUS := 12.0            # "tile of the spawn hub", D-T041-2
const LIFT_SPEED := 6.0             # the fade-back lift impulse, D-T041-4

const YIELDS_ID := "address_me"     # yields_to - spelled exactly in enemy.json


func _init() -> void:
	id = GIN_ID
	display_name = "gin ichimaru"


func on_spawn(row: Dictionary, _api) -> void:
	if row["cfg"].has("sword_attack"):
		row["phase"] = "waiting"
		row["contact_kill"] = false
		row["gin_next_tick"] = int(row["spawn_tick"])
		row["gin_twin_fangs"] = bool(row["cfg"].get("twin_fangs", false))
		return
	row["phase"] = SPAWN
	row["phase_t"] = 0
	row["patch"] = {}
	row["anim_state"] = ANIM_SPAWN
	row["anim_state_t"] = 0
	# the fade-in blocks the body's contact kill until it completes (the anim block's
	# spawn effect carries spawn_blocks_contact_ticks = 30)
	row["contact_kill"] = false
	_place_on_fade_in_tile(row, _api)
	# D-T030-1: the row's cfg carries the death code so the kill pass reports D-GIN
	row["cfg"]["death_code"] = DEATH_CODE


func tick(row: Dictionary, api, dt_ticks: int) -> void:
	if row["cfg"].has("sword_attack"):
		SwordAttack.tick(row, api)
		return
	row["phase_t"] = int(row.get("phase_t", 0)) + dt_ticks
	row["anim_state_t"] = int(row.get("anim_state_t", 0)) + dt_ticks
	match str(row.get("phase", SPAWN)):
		SPAWN:
			if int(row["phase_t"]) >= SPAWN_TICKS:
				var gate: Dictionary = api.arbiter_gate(_live_pending(api))
				if _gate_free(gate):
					_start_mark(row, api)
		MARK:
			if int(row["phase_t"]) >= TELEGRAPH_TICKS:
				row["phase"] = LAUNCH
				row["phase_t"] = 0
				row["anim_state"] = ANIM_LAUNCH
				row["anim_state_t"] = 0
				_cue(api, "shing")
				_cue(api, "whoosh")
		LAUNCH:
			if int(row["phase_t"]) >= SPEAR_TRAVEL_TICKS:
				row["phase"] = VOID
				row["phase_t"] = 0
				row["anim_state"] = ANIM_VOID
				_cue(api, "zone_open")
		VOID:
			# the boundary tick closes the zone FIRST (the tiles return), then the
			# lift saves anyone still inside - a fade-back tick is never a kill tick
			if int(row["phase_t"]) >= ZONE_TICKS:
				_open_fade_back(row, api)
				return
			# the zone is lethal: anything whose tile is inside the patch dies
			_void_kills(row, api)
			if int(row["phase_t"]) >= FADE_OUT_TICKS \
					and str(row.get("anim_state", "")) == ANIM_VOID:
				row["anim_state"] = ANIM_RECOVER   # the body fades out over the zone
			if int(row["phase_t"]) >= ZONE_TICKS:
				_open_fade_back(row, api)
		FADE_BACK:
			if int(row["phase_t"]) >= FADE_BACK_TICKS:
				row["phase"] = COOLDOWN
				row["phase_t"] = 0
				row["anim_state"] = ANIM_SPAWN
				row["anim_state_t"] = 0
				row["contact_kill"] = false   # the fade-in blocks the body again
		COOLDOWN:
			if int(row["phase_t"]) >= _cooldown_ticks(row):
				row["phase"] = SPAWN
				row["phase_t"] = 0
				row["anim_state"] = ANIM_SPAWN
				row["anim_state_t"] = 0
				# D-072 is a property of every fade-in, not of the spawn alone: the tile is
				# re-picked against where the player is NOW, so cycle 2+ does not fade in
				# on the tile the first spawn happened to choose.
				_place_on_fade_in_tile(row, api)


func hash_state(row: Dictionary) -> Array:
	if not row["cfg"].has("sword_attack"):
		return []
	var cfg: Dictionary = row["cfg"]["sword_attack"]
	return [row["spawn_tick"], row["copies"], row["phase"], row["gin_next_tick"],
			row["x"], row["y"], row["z"], row.get("gin_target", -1), row.get("gin_voice_tick", -1),
			row.get("gin_launch_tick", -1), row.get("gin_arrival_tick", -1),
			row.get("gin_sword_pos", Vector3.ZERO), row.get("gin_outcome", ""),
			row.get("gin_origin", Vector3.ZERO), row.get("gin_goal", Vector3.ZERO),
			row.get("gin_second_origin", Vector3.ZERO), row.get("gin_previous_feet", []),
			row["cfg"]["death_code"], cfg["sword_radius_u"],
			row.get("gin_flight_elapsed", -1), row.get("gin_twin_fangs", false),
			row.get("gin_second_pos", Vector3.ZERO), cfg["twin_clearance_u"],
			cfg["voice_ticks"], cfg["flight_ticks"], cfg["min_launch_distance_u"],
			cfg["clearance_u"], cfg["cooldown_ticks"], cfg["cooldown_vote_discount_ticks"],
			cfg["cooldown_min_ticks"]]


func hash_pending(entry: Dictionary) -> Array:
	var cfg: Dictionary = entry["cfg"]
	if not cfg.has("sword_attack"):
		return []
	var attack: Dictionary = cfg["sword_attack"]
	var keys := attack.keys()
	keys.sort()
	var state: Array = [cfg["death_code"], cfg.get("twin_fangs", false)]
	for key in keys:
		state.append([key, attack[key]])
	return state


# ---- archived mark + void-zone fixtures --------------------------------------------------------


# The patch: the 5x5 tile block centred on the player's tile, minus the dais cell.
func _patch(row: Dictionary, api) -> Dictionary:
	var near: Dictionary = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
	if near.is_empty():
		return {"cells": [], "cx": 0, "cz": 0}
	var cx := int(floor(float(near["x"])))
	var cz := int(floor(float(near["z"])))
	var cells: Array = []
	for dx in range(-PATCH_HALF, PATCH_HALF + 1):
		for dz in range(-PATCH_HALF, PATCH_HALF + 1):
			var tx: int = cx + dx
			var tz: int = cz + dz
			if _is_dais_cell(api, tx, tz):
				continue   # never marks the beacon dais (D-T041-3)
			cells.append([tx, tz])
	return {"cells": cells, "cx": cx, "cz": cz}


# The zone's hazard footprint for the telegraph row (a collision.gd hazard shape;
# the runtime's shape vocabulary is circle/ring - the square is drawn by the view
# from the patch cells, never by a collision shape).
func _patch_shape(row: Dictionary) -> Dictionary:
	var patch: Dictionary = row.get("patch", {})
	return {"shape": "circle", "cx": float(patch.get("cx", 0)) + 0.5,
			"cz": float(patch.get("cz", 0)) + 0.5, "r": float(PATCH_HALF) + 0.5}


# ---- the view's cue emitter --------------------------------------------------------------------


# The mark's own cue: the deep cracking rumble plays for the whole 120-tick mark.
func _cue(_host, _cue_name: String) -> void:
	pass   # the view reads the telegraph row and plays the 5 cues; no sim audio events


# ---- the phases --------------------------------------------------------------------------------


# The spawn fade completes: he arms the mark unless the gate defers it (SR-4) - the
# deferral holds THIS phase, so the mark lands on the first free tick that follows,
# never skipped. appear_requires is EMPTY (the brief): the gate only answers deferral.
func _gate_free(gate: Dictionary) -> bool:
	return bool(gate.get("may_appear", false)) and not bool(gate.get("deferred", false))


# The ids this row passes through the gate as live caller-side countdowns: a live
# address me countdown is ROW STATE on an address me row (D-T-039-11 - it is never a
# telegraph), so this behavior reads the roster and passes the id along when one runs.
func _live_pending(api) -> Array:
	var out: Array = []
	for e in api.rt.enemies:
		if str(e.get("id", "")) == YIELDS_ID and int(e.get("countdown_left", 0)) > 0:
			out.append(YIELDS_ID)
			break
	return out


func _start_mark(row: Dictionary, api) -> void:
	row["phase"] = MARK
	row["phase_t"] = 0
	row["patch"] = _patch(row, api)
	row["contact_kill"] = true   # the fade is done: the body answers for itself again
	row["anim_state"] = ANIM_TELEGRAPH
	row["anim_state_t"] = 0
	_cue(api, "crack_rumble")
	api.telegraph(MARK, _patch_shape(row), TELEGRAPH_TICKS)


# The void zone opens: lift any player still inside the column onto the surface
# (the tiles come back under their feet - D-T041-4).
func _open_fade_back(row: Dictionary, api) -> void:
	row["phase"] = FADE_BACK
	row["phase_t"] = 0
	row["anim_state"] = ANIM_RECOVER
	row["anim_state_t"] = 0
	_cue(api, "zone_close")
	var patch: Dictionary = row.get("patch", {})
	var cells: Array = patch.get("cells", [])
	for c in api.rt.controllers:
		if c == null or bool(c.dead):
			continue
		if _tile_inside(cells, float(c.x), float(c.z)):
			api.push(c, Vector3(0.0, 1.0, 0.0), LIFT_SPEED)


# The strike cooldown: 840 ticks (14 s), -180 per extra vote, floored at 300 (5 s).
func _cooldown_ticks(row: Dictionary) -> int:
	var extra: int = maxi(int(row.get("copies", 1)) - 1, 0)
	return maxi(COOLDOWN_TICKS - COOLDOWN_VOTE_DISCOUNT * extra, COOLDOWN_MIN)


# The void zone is lethal: anything whose tile is inside the patch dies, at any
# height - the column replaces the floor itself.
func _void_kills(row: Dictionary, api) -> void:
	var cells: Array = row.get("patch", {}).get("cells", [])
	if cells.is_empty():
		return
	for c in api.rt.controllers:
		if c == null or bool(c.dead):
			continue
		if _tile_inside(cells, float(c.x), float(c.z)):
			api.kill(c, GIN_ID, DEATH_CODE)


func _tile_inside(cells: Array, x: float, z: float) -> bool:
	var cx := int(floor(x))
	var cz := int(floor(z))
	for cell in cells:
		if int(cell[0]) == cx and int(cell[1]) == cz:
			return true
	return false


# ---- the D-072 fade-in tile --------------------------------------------------------------------


# Candidates: 15-25 u from the player (bounds inclusive), never the dais; farthest
# from the player first, lowest tile index on ties; if nothing qualifies, the farthest
# tile of the spawn hub (tiles within HUB_RADIUS of the level's first `open` anchor).
func _place_on_fade_in_tile(row: Dictionary, api) -> void:
	var near: Dictionary = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
	if near.is_empty():
		return
	var pp := Vector3(float(near["x"]), float(near["y"]), float(near["z"]))
	var spot: Variant = _farthest_tile(api, api.tiles_in_radius(pp, SPAWN_DIST_MAX), pp,
			SPAWN_DIST_MIN)
	if spot == null:
		var hubs: Array = api.anchors("open")
		if hubs.is_empty():
			return   # stay where the runtime put the row: fallback (c) already chose it
		var hub: Dictionary = hubs[0]
		spot = _farthest_tile(api, api.tiles_in_radius(
				Vector3(float(hub["x"]), float(hub["y"]), float(hub["z"])), HUB_RADIUS), pp, -1.0)
	row["x"] = float(spot["x"])
	row["y"] = float(spot["y"])
	row["z"] = float(spot["z"])
	# the fade-in is an instant reposition, so the body mirror follows it (PARKED row 27):
	# no_enemy_body_within and the D-059 safe tile read world["enemies"], not this row, and
	# the mirror is otherwise written once at the runtime's spawn point. y is the tile's too,
	# not the spawn point's (the contact band runs row y .. y + height_u, so a body left on a
	# lower platform cannot touch a player standing on this one).
	api.sync_body()


# Farthest-from-the-player tile of `tiles` at least `min_d` away, lowest index on ties.
func _farthest_tile(api, tiles: Array, pp: Vector3, min_d: float) -> Variant:
	var best: Variant = null
	var best_d := -1.0
	for t in tiles:
		if _is_dais(api, int(t["index"])):
			continue
		var d: float = Vector3(float(t["x"]) - pp.x, 0.0, float(t["z"]) - pp.z).length()
		if d < min_d:
			continue
		if best == null or d > best_d or (d == best_d and int(t["index"]) < int(best["index"])):
			best = t
			best_d = d
	return best


# The beacon dais cell, read off the world's own dais row (world["dais"] = [x, z, y]);
# never marked, never struck, never stood on by the fade-in (D-T041-3).
func _is_dais(api, tile_index: int) -> bool:
	var tiles: Array = api.rt.world.get("tiles", [])
	if int(tile_index) < 0 or int(tile_index) >= tiles.size():
		return false
	var t: Array = tiles[int(tile_index)]
	return _is_dais_cell(api, int(t[0]), int(t[1]))


## The dais CELL by coordinates: true when (tx, tz) is the cell the world's own
## dais row (world["dais"] = [x, z, y]) names.
func _is_dais_cell(api, tx: int, tz: int) -> bool:
	if not api.rt.world.has("dais"):
		return false
	var d: Array = api.rt.world["dais"]
	return int(d[0]) == tx and int(d[1]) == tz
