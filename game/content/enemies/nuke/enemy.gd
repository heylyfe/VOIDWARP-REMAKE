extends RefCounted
#
# nuke behavior module (ticket T-034). Lives under content/ so the sim core stays
# enemy-agnostic; it extends the EnemyBehavior base (sim/enemy_runtime.gd, FLEET_PACK
# T-027) and carries NO sim state beyond its own row. The roster numbers arrive as the
# plain cfg dictionary from content/enemies/nuke/enemy.json (DESIGN.md section 12):
# DES(IGN).md section 5.5 (the loop), section SR-2 (a launcher, NO body on the map:
# world_height 0.0 -> no contact kill), and D-064 (the salvo life limit + blocking).
#
# The §5.5 loop, verbatim numbers through the cfg (60 Hz ticks):
#   lock a player (the ground ring follows them) -> track 2.5 s (150 ticks) with the
#   beep rising 2 -> 8 Hz -> the ring stops and fills from the rim inward while the
#   missile descends 1.5 s (the same 90 ticks as the locked ring, from 30 u above the
#   ring centre) -> explosion: sphere radius 5 u kills -> 5.0 s pause (300 ticks)
#   -> repeat.
#
# D-064 salvo: tracking, including EVERY restart after a broken lock, plus the descent,
# lasts at most 6.0 s (360 ticks) from the first tracking tick; expiry is harmless (no
# lock, no descent, no blast) and the 5.0 s pause starts. The 120-tick restart never
# resets the budget (the sim's SalvoClock: start() on an ACTIVE clock is a no-op).
#
# D-064 blocking: the LOS ray (traced from a point 12 u above and 20 u away, direction
# fixed per salvo) is checked during TRACKING - blocked 0.5 s continuously (30 ticks)
# breaks the lock; tracking restarts after 2.0 s (120 ticks). The DESCENDING missile is
# blocked by any prop, any spire pad and any tile slab/step riser standing in its column;
# a missile that meets one detonates THERE (on a spire pad, on the pad's top).
#
# Parked (not resolved here, T-PARKED rows in PARKED.md):
#   - the blast kills the NEAREST player inside the 5 u sphere: the kill API is
#     per-player and the section 12 surface exposes no player enumeration; covering
#     EVERY player inside needs an Api addition (multiplayer is not in scope).
#   - the sim never expires telegraph footprints (enemy_runtime.gd owns the entries):
#     the blast's ground-ring footprint stays live after the ring has resolved. The
#     match-side effect (address me defers while a ring is on the player) matches
#     SR-4's words while the ring is live; the stale-footprint drift is the runtime's.

const RT := preload("res://sim/enemy_runtime.gd")

# Phases of the §5.5 loop, in table order. anim_state names are exactly the anim
# block's state ids (content/enemies/nuke/sprites.json section 1.5) - the view layer
# (view/enemy_anim.gd's caller contract) drives set_animation(str(row["anim_state"])).

const TRACK := "track"            # lock acquired; the ring follows, beep rises
const LOCK := "lock"              # the ring fills AND the missile descends: the same
                                  # 90 ticks (the anim block's locked + descent states)
const RECOVER := "recover"        # the lock broke: the ring holds stopped, then re-tracks
const PAUSE := "pause"            # 5.0 s after the blast (or after a harmless expiry)

## The anim block's state id per phase, keyed by phase. LOCK shows the FALLING MISSILE as
## its body (the anim block's attack_descent frames - the descent's 90 ticks are "the same
## 90 ticks as the locked ring"); the locked ring itself is the sim's telegraph row the
## behaviour announces at the lock's start, whose own t the view renders (the fill params
## live in the anim block's telegraph_locked entry). The 120-tick broken-lock window has
## NO state of its own in the table: the row holds recover there (nothing on screen - the
## table's own recover row is the 5.0 s pause below; noted in the response file).
const ANIM_STATE := {
	TRACK: "telegraph_tracking",
	LOCK: "attack_descent",
	RECOVER: "recover",
	PAUSE: "attack_explosion",
}

## cfg keys (enemy.json stats); the sim constants below are the same numbers' fallbacks.
const TRACK_TICKS := "track_ticks"            # 150 (2.5 s)
const LOCK_TICKS := "lock_ticks"              # 90 (1.5 s)
const DESCENT_TICKS := "descent_ticks"        # 90 (1.5 s)
const EXPLOSION_TICKS := "explosion_ticks"    # 24 (drawn over the pause's first 24)
const PAUSE_TICKS := "pause_ticks"            # 300 (5.0 s)
const RING_RADIUS := "ring_radius"            # 5.0 u (the sphere and the ring)
const BLAST_RADIUS := "blast_radius"          # 5.0 u
const LOCK_HEIGHT := "lock_height"            # 12.0 u, the LOS origin's rise
const LOS_OFFSET := "tell_distance"           # 20.0 u, the LOS origin's throw - the
                                              # cfg's tell_distance is the warning cue's
                                              # range re-purposed; both are 20.0
const LOS_BREAK_TICKS := "los_break_ticks"    # 30 (0.5 s continuous)
const RELOCK_TICKS := "relock_ticks"          # 120 (2.0 s)
const SALVO_LIFE_TICKS := "salvo_life_ticks"  # 360 (6.0 s, D-064)
const DESCENT_HEIGHT := "descent_height"      # 30.0 u above the ring centre
const BEEP_HZ_START := "beep_hz_start"        # 2.0 Hz at tick 0
const BEEP_HZ_END := "beep_hz_end"            # 8.0 Hz at tick 150 (sim-data only: the
                                              # beep is the ground ring's blink, the anim
                                              # block's effect params own it; no sim read)


func on_spawn(row: Dictionary, api) -> void:
	row["age"] = 0
	_start_salvo(row, api)


func on_vote(_row: Dictionary, _api, _count: int) -> void:
	pass   # each vote adds +1 launcher: the vote counts feed the runtime's plan (copies)


func tick(row: Dictionary, api, dt_ticks: int) -> void:
	row["age"] = int(row["age"]) + dt_ticks
	var phase := str(row.get("phase", TRACK))
	match phase:
		TRACK:
			_tick_track(row, api, dt_ticks)
		LOCK:
			_tick_lock(row, api, dt_ticks)
		RECOVER:
			_tick_recover(row, api, dt_ticks)
		PAUSE:
			_tick_pause(row, api, dt_ticks)
	# base state per phase. LOCK carries the locked ring AND the falling missile (the
	# anim block: the descent's 90 ticks are "the same 90 ticks as the locked ring").
	# PAUSE refines itself: attack_explosion draws over the pause's first 24 ticks (the
	# sphere resolves on the blast tick), then recover - nothing on screen (the anim
	# block's recover state, 300 ticks).
	if phase == PAUSE:
		row["anim_state"] = "attack_explosion" \
				if int(row["explosion_left"]) > 0 else "recover"
	else:
		row["anim_state"] = ANIM_STATE[phase]


# ---- the pause --------------------------------------------------------------------------------


## The salvo ends: the 5.0 s pause (300 ticks). attack_explosion (one-shot, 24 ticks)
## draws over the first 24 of them (started on the blast tick - the tick the 5 u
## sphere resolves), then the anim block's recover state (nothing on screen).
func _set_pause(row: Dictionary, _api, paused_by: String) -> void:
	row["phase"] = PAUSE
	row["pause_left"] = _ticks(row, PAUSE_TICKS)
	row["explosion_left"] = _num(row, EXPLOSION_TICKS) \
			if paused_by == "blast" else 0
	row["paused_by"] = paused_by


# ---- the phases -------------------------------------------------------------------------------


## A fresh salvo: the nearest player is locked (the ring follows them), the ground ring is
## announced (150 ticks left), and the salvo clock starts (D-064: the budget counts from
## THIS tick forward; every restart below keeps it). The sim's ring footprint: announced
## once per salvo at the locked player's position (the ring follows only in the view - the
## anim block's params; the sim never expires telegraph rows: the drift is the runtime's).
func _start_salvo(row: Dictionary, api) -> void:
	var clock = row.get("salvo", null)
	if clock == null or bool(clock.expired):
		clock = RT.SalvoClock.new()
		row["salvo"] = clock
		row["salvo_begun"] = int(row.get("age", 0))
	clock.start()
	row["phase"] = TRACK
	row["track_left"] = _ticks(row, TRACK_TICKS)
	row["los_bad"] = 0
	var near: Dictionary = api.nearest_player(_pos_at(row))
	if near.is_empty():
		return   # nobody to lock: the countdown holds, nothing is announced
	var ring := _ring_centre(row, near)
	row["ring"] = {"x": ring["x"], "y": ring["y"], "z": ring["z"], "i": int(near["index"])}
	# the frozen LOS bearing: chosen fresh for THIS salvo - the launcher's line onto the
	# locked player at the salvo's first tick (0.0 -> +z); the origin's 20 u ride it
	row["salvo_ring0"] = ring
	row["los_dir"] = null
	api.telegraph("ground_ring", {"shape": "circle", "cx": float(ring["x"]),
			"cz": float(ring["z"]), "r": _num(row, RING_RADIUS),
			"y0": float(ring["y"]), "y1": float(ring["y"]) + 0.6},
			_ticks(row, TRACK_TICKS))


## Tracking (150 ticks): the ring follows the nearest player; the lock holds while the
## sky point sees them (12 u above, 20 u throw, frozen for the salvo). Losing the LOS for
## 30 ticks continuously breaks the lock (D-064).
func _tick_track(row: Dictionary, api, dt_ticks: int) -> void:
	var clock = row["salvo"]
	if not bool(clock.tick(dt_ticks)):
		# the budget ran out: expiry is harmless - no lock, no descent, no blast; the
		# 5.0 s pause starts (D-064)
		row["phase"] = PAUSE
		row["pause_left"] = _ticks(row, PAUSE_TICKS)
		row["explosion_left"] = 0
		row["paused_by"] = "expired"
		return
	var near: Dictionary = api.nearest_player(_pos_at(row))
	if near.is_empty():
		return   # nobody to lock: the track holds its countdown, nothing is announced
	var ring := _ring_centre(row, near)
	row["ring"] = {"x": ring["x"], "y": ring["y"], "z": ring["z"], "i": int(near["index"])}
	var origin := _los_origin(row, ring)
	if api.los(origin, Vector3(float(ring["x"]), float(ring["y"]), float(ring["z"]))):
		row["los_bad"] = 0
	else:
		row["los_bad"] = int(row["los_bad"]) + dt_ticks
		if int(row["los_bad"]) >= _ticks(row, LOS_BREAK_TICKS):
			# the lock breaks: the ring holds stopped where it broke (the row keeps the
			# locked anim; the one-shot holds its last frame), tracking restarts after
			# 120 ticks - a RESTART, never a budget reset (D-064)
			row["phase"] = RECOVER
			row["recover_left"] = _ticks(row, RELOCK_TICKS)
			row["track_left"] = _ticks(row, TRACK_TICKS)
			return
	row["track_left"] = int(row["track_left"]) - dt_ticks
	if int(row["track_left"]) <= 0:
		# the ring stops and fills while the missile falls: the same 90 ticks (1.5 s);
		# the detonation point is decided here, once, on the descent's first tick
		row["phase"] = LOCK
		row["lock_left"] = _ticks(row, LOCK_TICKS)
		_start_descend(row, api)
		# the locked ring: the sim's footprint at the lock's first tick (stops + fills;
		# solid, rim-inward, the anim block's params carry the look)
		var ring2: Dictionary = row["ring"]
		api.telegraph("ground_ring", {"shape": "circle", "cx": float(ring2["x"]),
				"cz": float(ring2["z"]), "r": _num(row, RING_RADIUS),
				"y0": float(ring2["y"]), "y1": float(ring2["y"]) + 0.6,
				"solid": true, "fill": "full on tick 90"}, _ticks(row, LOCK_TICKS))


## The ring fills from the rim inward AND the missile falls, the same 90 ticks (1.5 s):
## the ring full on tick 90 = the tick the 5 u sphere resolves; the row eases the
## detonation point down the column at 30 u / 90 ticks (1/3 u per tick); the budget
## keeps counting (the descent is inside the salvo's 6.0 s - D-064).
func _tick_lock(row: Dictionary, api, dt_ticks: int) -> void:
	row["salvo"].tick(dt_ticks)
	if bool(row["salvo"].expired):
		_set_pause(row, api, "expired")
		return
	row["lock_left"] = int(row["lock_left"]) - dt_ticks
	var det: Dictionary = row["det"]
	if float(det["y"]) > float(row["det_floor"]):
		det["y"] = maxf(float(det["y"]) - (1.0 / 3.0) * float(dt_ticks),
				float(row["det_floor"]))
	if int(row["lock_left"]) <= 0:
		_blast(row, api, det)


## The lock broke: 120 ticks (2.0 s) of the stopped ring, then tracking RESTARTS - a fresh
## 150-tick lock with a fresh ground ring; the salvo budget is untouched (D-064) - and the
## budget keeps counting through the restart: past its 360 ticks the salvo dies here too
## (harmlessly, the 5.0 s pause starts) - a restart never pushes a salvo past 6.0 s.
func _tick_recover(row: Dictionary, api, dt_ticks: int) -> void:
	row["salvo"].tick(dt_ticks)
	if bool(row["salvo"].expired):
		_set_pause(row, api, "expired")
		return
	row["recover_left"] = int(row["recover_left"]) - dt_ticks
	if int(row["recover_left"]) <= 0:
		row["los_bad"] = 0
		_start_salvo(row, api)


## D-064 blocking note (built at the LOCK's start, before the descent's first tick):
## a vertical LOS from 30 u above the ring's centre down to the ring decides the
## detonation height ONCE - any prop, spire pad or tile slab/step riser standing in the
## column blocks it and the missile detonates THERE (on a spire pad: on the pad's top).
## The top plate is the topmost tile the surface helper finds under the column; the
## ring's centre else.
func _start_descend(row: Dictionary, api) -> void:
	var ring: Dictionary = row["ring"]
	var det := {"x": float(ring["x"]), "y": float(ring["y"]) + 30.0, "z": float(ring["z"])}
	var floor_y := float(ring["y"])
	if not api.los(Vector3(det["x"], det["y"], det["z"]),
			Vector3(det["x"], det["y"] - 30.0, det["z"])):
		# something solid stands in the column: come down onto it (a spire pad's top)
		for t in api.tiles_in_radius(Vector3(det["x"], floor_y, det["z"]), 0.9):
			floor_y = maxf(floor_y, float(t["y"]))
	row["det"] = det
	row["det_floor"] = floor_y


## The blast (the sphere, radius 5 u, kills): the nearest player inside the sphere dies
## (code D-NUKE, killer nuke - the sim's kill API names the killer, never a damage number;
## D-T027-5). Multiplayer: the section 12 surface exposes no player enumeration, so the
## blast reaches the nearest player inside only (parked - see on_spawn's header note and
## PARKED.md). Announced attack_explosion (24 ticks) rides over the pause's first 24.
func _blast(row: Dictionary, api, det: Dictionary) -> void:
	var det_vec := Vector3(float(det["x"]), float(det["y"]), float(det["z"]))
	var near: Dictionary = api.nearest_player(det_vec)
	if not near.is_empty():
		var p := _player_detail(near)
		var dx: float = float(p["x"]) - float(det["x"])
		var dy: float = float(p["y"]) - float(det["y"])
		var dz: float = float(p["z"]) - float(det["z"])
		if sqrt(dx * dx + dy * dy + dz * dz) <= _num(row, BLAST_RADIUS):
			api.kill(near["index"], "nuke")
	_set_pause(row, api, "blast")


## The 5.0 s pause (300 ticks); attack_explosion draws over the first 24 of them, then
## recover (nothing on screen). On its end the loop repeats: a fresh salvo locks afresh.
func _tick_pause(row: Dictionary, api, dt_ticks: int) -> void:
	row["pause_left"] = int(row["pause_left"]) - dt_ticks
	row["explosion_left"] = maxi(int(row["explosion_left"]) - dt_ticks, 0)
	if int(row["pause_left"]) <= 0:
		_start_salvo(row, api)


# ---- helpers ------------------------------------------------------------------------------------


## A cfg-backed number with its spec fallback: the enemy.json stats carry the binding
## values; the constants below repeat the same numbers so a missing key never builds a
## silent 0 into a timing.
func _num(row: Dictionary, key: String) -> float:
	var cfg: Dictionary = row.get("cfg", {})
	return float(cfg.get(key, _FALLBACKS[key]))


func _ticks(row: Dictionary, key: String) -> int:
	return int(_num(row, key))


## The launcher's row position (a launcher, no body on the map: SR-2 - the row keeps its
## spawn spot; the ground ring lives under the LOCKED PLAYER, not under the launcher).
func _pos_at(row: Dictionary) -> Vector3:
	return Vector3(float(row["x"]), float(row["y"]), float(row["z"]))


## The ring's centre: the locked player's feet point (the ring follows them while
## tracking; a player that died mid-track unhooks the ring until the re-lock).
func _ring_centre(row: Dictionary, near: Dictionary) -> Dictionary:
	var p := _player_detail(near)
	return {"x": p["x"], "y": p["y"], "z": p["z"]}


## The player's detail dict for the geometry math (nearest_player carries it; the raw
## controller rows are mirrored in the same shape).
func _player_detail(near: Dictionary) -> Dictionary:
	if near.has("x"):
		return near
	return {"x": 0.0, "y": 0.0, "z": 0.0}


## The LOS origin (D-064): a point 12 u above and 20 u away from the ring centre, in a
## horizontal direction frozen for the salvo - the launcher's bearing onto the locked
## player at the salvo's first tick (0.0 -> +z). The trace runs origin -> ring centre.
func _los_origin(row: Dictionary, ring: Dictionary) -> Vector3:
	var dir_v: Variant = row.get("los_dir", null)
	if dir_v == null or not (dir_v is Vector3):
		var ring0: Dictionary = row.get("salvo_ring0", ring)
		var dx: float = float(ring0["x"]) - float(row["x"])
		var dz: float = float(ring0["z"]) - float(row["z"])
		var dir := Vector3(0.0, 0.0, 1.0)
		if sqrt(dx * dx + dz * dz) > 1e-9:
			dir = Vector3(dx / sqrt(dx * dx + dz * dz), 0.0, dz / sqrt(dx * dx + dz * dz))
		row["los_dir"] = dir
		dir_v = dir
	var centre := Vector3(float(ring["x"]), float(ring["y"]), float(ring["z"]))
	return centre + Vector3(0.0, _lock_h(row), 0.0) + dir_v * _los_off(row)


func _lock_h(row: Dictionary) -> float:
	return _num(row, LOCK_HEIGHT)


func _los_off(row: Dictionary) -> float:
	return _num(row, LOS_OFFSET)


# The cfg fallbacks - the same numbers the enemy.json stats bind (DESIGN.md section 5.5).
var _FALLBACKS := {
	TRACK_TICKS: 150.0, LOCK_TICKS: 90.0, DESCENT_TICKS: 90.0,
	EXPLOSION_TICKS: 24.0, PAUSE_TICKS: 300.0,
	RING_RADIUS: 5.0, BLAST_RADIUS: 5.0,
	LOCK_HEIGHT: 12.0, LOS_OFFSET: 20.0,
	LOS_BREAK_TICKS: 30.0, RELOCK_TICKS: 120.0, SALVO_LIFE_TICKS: 360.0,
	DESCENT_HEIGHT: 30.0, BEEP_HZ_START: 2.0, BEEP_HZ_END: 8.0,
}
