extends "res://sim/enemy_runtime.gd".EnemyBehavior
#
# address me behavior module (ticket T-039; the Operator, ENEMIES.md "Operator -> address me",
# copied 1:1 in spirit; the VOIDWRAP_RUN mechanic: it spawns and you have 5 seconds to
# stand still). Spec: ENEMIES.md's section (frozen, D-040), DESIGN.md section 5.10 (the
# numbers, binding), section 12 (the API contract). Numbers under test (+/-1 tick):
#
#   - ONE at a time; appears 6 u in front of the player with an elephant trumpet, but
#     ONLY under the SR-4 scheduling gate (D-067): no enemy body within 12 u of the
#     player, no ring or patch on the player, player grounded, not on glitched floor.
#     Waits for the first tick all four hold (each requirement asserted alone in the test).
#   - never appears in the first 10 s of a level (level tick 0..599);
#   - a 5.0 s (300-tick) rumble counts down; the player must become still: no movement/
#     jump/ability input and speed < 0.5 u/s on ALL axes, held 1.5 CONTINUOUS seconds
#     (90 ticks) - the stillness countdown is this row's own state, and it travels in the
#     arbiter gate's `pending` array as the live id "address_me" (D-T-039-6);
#   - achieved -> it leaves (the `leaves` state, 18 ticks, shrink_puff);
#   - 5.0 s expire first -> explode frame (`attack`, 24 ticks), boom, KILL (D-ADDR);
#   - returns every 30-45 s, -5 s per extra vote beyond the first (min 15-30 s floor),
#     and the first appearance is allowed only at level tick 600 (D-T-039-4);
#   - its body NEVER kills (D-065 FINAL: "no body contact; it is a countdown, not an
#     obstacle") - the framework's contact pass is skipped; the kill is the expiry only.
#
# ENEMIES.md's behavior sentence is the spec (D-040). Readings and gaps are recorded in
# DECISIONS.md (D-T-039-1..14); the load-bearing ones:
#   D-T-039-2  stillness read via |v| < 0.5 u/s on all axes (the API carries no buttons)
#   D-T-039-3  the expiry kill is unconditional on the targeted player (no radius exists in the docs)
#   D-T-039-5  between episodes the body parks at y = 1000.0 u (AWAY_Y) so its own
#              mirror can never veto every later appearance through the gate itself
#   D-T-039-6  yields_to ["address_me"] - while its own countdown is live the gate
#              reports deferred=true; the countdown is row state, NOT a telegraph
#   D-T-039-7  "in front of the player" = the row's tracked last nonzero heading
#
# Spawn rule (D-056) still runs: preferred_kind "none" -> fallback (c); the row then
# parks (AWAY_Y) at on_spawn and waits for the gate; the appearance teleports it 6 u in
# front of the player (D-T-039-13).

const AWAY_Y := 1000.0                 # D-T-039-5: parked far above the level between episodes
const APPEAR_NOT_BEFORE_TICKS := 600   # never in the first 10 s of a level (5.10)
const APPEAR_IN_FRONT_U := 6.0         # appears 6 u in front of the player (5.10)
const COUNTDOWN_TICKS := 300           # 5.0 s
const STILL_TICKS := 90                # 1.5 s continuous
const STILL_SPEED := 0.5               # u/s on ALL axes (5.10)
const SPAWN_TICKS := 12                # the anim block spawn row: 12 ticks
const LEAVES_TICKS := 18               # the anim block leaves row: 18 ticks
const ATTACK_TICKS := 24               # the anim block attack row: 24 ticks
const RETURN_MIN_TICKS := 1800         # 30 s
const RETURN_MAX_TICKS := 2700         # 45 s
const RETURN_VOTE_DISCOUNT := 300      # -5 s per extra vote beyond the first
const RETURN_MIN_FLOOR := 900          # absolute floors, never beaten by votes (D-T-039-4)
const RETURN_MAX_FLOOR := 1800

const COUNTDOWN_ID := "address_me"     # the id gin (T-041) yields to; used in yields_to
const TELEGRAPH_ANIM := "telegraph"


func _init() -> void:
	id = "address_me"
	display_name = "address me"


func on_spawn(row: Dictionary, api) -> void:
	row["ticks"] = 0
	row["anim_state"] = "recover"          # nothing on screen between episodes
	row["anim_state_t"] = 0
	row["countdown_left"] = 0              # > 0 only during the 300-tick rumble
	row["still_t"] = 0
	row["return_timer"] = 0                # the first episode may fire as soon as the gate opens
	row["face_x"] = 0.0                    # the row's tracked heading (D-T-039-7)
	row["face_z"] = 1.0
	row["target_index"] = -1
	_park_away(row, api)


func tick(row: Dictionary, api, dt_ticks: int) -> void:
	row["ticks"] = int(row.get("ticks", 0)) + dt_ticks
	row["anim_state_t"] = int(row.get("anim_state_t", 0)) + dt_ticks
	_track_heading(row, api)
	match str(row["anim_state"]):
		"recover":
			_tick_recover(row, api, dt_ticks)
		"spawn":
			if int(row["anim_state_t"]) >= SPAWN_TICKS:
				row["anim_state"] = TELEGRAPH_ANIM
				row["anim_state_t"] = 0
				row["countdown_left"] = COUNTDOWN_TICKS
				row["still_t"] = 0
		"telegraph":
			_tick_countdown(row, api, dt_ticks)
		"leaves":
			if int(row["anim_state_t"]) >= LEAVES_TICKS:
				_end_episode(row, api)
		"attack":
			if int(row["anim_state_t"]) >= ATTACK_TICKS:
				_end_episode(row, api)
		_:
			row["anim_state"] = "recover"
			row["anim_state_t"] = 0


# ---- the waiting phase (the only arbiter call site) ---------------------------

func _tick_recover(row: Dictionary, api, dt_ticks: int) -> void:
	var level_tick := int(row.get("spawn_tick", 0)) + int(row["ticks"])
	if int(row["return_timer"]) > 0:
		row["return_timer"] = maxi(int(row["return_timer"]) - dt_ticks, 0)
		return
	if level_tick < APPEAR_NOT_BEFORE_TICKS:
		return
	var near: Dictionary = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
	if near.is_empty():
		return
	var gate: Dictionary = api.arbiter_gate(_live_pending(row))
	if not bool(gate.get("may_appear", false)):
		return            # one of the four SR-4 requirements is unmet: wait
	if bool(gate.get("deferred", false)):
		return            # our own countdown is live somewhere: the call lands next tick
	_appear(row, api, near)


# The pending array carries this row's own live countdown id so a gate re-evaluation
# defers while the countdown runs (D-T-039-6). The countdown is row state - it is
# never registered with api.telegraph (D-T-039-11).
func _live_pending(row: Dictionary) -> Array:
	return [COUNTDOWN_ID] if int(row.get("countdown_left", 0)) > 0 else []


func _appear(row: Dictionary, api, near: Dictionary) -> void:
	var fx: float = float(row["face_x"])
	var fz: float = float(row["face_z"])
	var len := sqrt(fx * fx + fz * fz)
	if len < 1e-9:
		fx = 0.0
		fz = 1.0
		len = 1.0
	row["x"] = float(near["x"]) + fx / len * APPEAR_IN_FRONT_U
	row["y"] = float(near["y"])
	row["z"] = float(near["z"]) + fz / len * APPEAR_IN_FRONT_U
	row["target_index"] = int(near.get("index", 0))
	row["anim_state"] = "spawn"
	row["anim_state_t"] = 0
	row["countdown_left"] = 0
	row["still_t"] = 0
	api.sync_body()


# ---- the countdown ------------------------------------------------------------

func _tick_countdown(row: Dictionary, api, dt_ticks: int) -> void:
	var near: Dictionary = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
	_update_stillness(row, near, dt_ticks)
	row["countdown_left"] = int(row["countdown_left"]) - dt_ticks
	# tie-break: stillness achieved on the same tick the countdown expires goes to the
	# player (leaves wins, no kill) - achieving the stop is the spec's own success state
	if int(row["still_t"]) >= STILL_TICKS:
		# achieved: it leaves (the leaves state, 18 ticks) - no kill
		row["anim_state"] = "leaves"
		row["anim_state_t"] = 0
		row["countdown_left"] = 0
		return
	if int(row["countdown_left"]) <= 0:
		# 5.0 s expire first: explode frame, boom, kill (D-T-039-12)
		var idx := int(row.get("target_index", 0))
		var code := str(row.get("cfg", {}).get("death_code", "D-ADDR"))
		api.kill(idx, "address me", code)   # cfg death_code, verbatim (D-ADDR)
		row["anim_state"] = "attack"
		row["anim_state_t"] = 0
		row["countdown_left"] = 0


# Stillness (D-T-039-2): speed < 0.5 u/s on ALL axes. The section-12 snapshot carries no
# button channel; every input the game can produce perturbs an axis past 0.5 u/s within a
# tick. Any failing tick resets the continuous window.
func _update_stillness(row: Dictionary, near: Dictionary, dt_ticks: int) -> void:
	var ok := false
	if not near.is_empty():
		var vx: float = absf(float(near.get("vx", 0.0)))
		var vy: float = absf(float(near.get("vy", 0.0)))
		var vz: float = absf(float(near.get("vz", 0.0)))
		if vx < STILL_SPEED and vy < STILL_SPEED and vz < STILL_SPEED:
			ok = true
	if ok:
		row["still_t"] = int(row["still_t"]) + dt_ticks
	else:
		row["still_t"] = 0


func _track_heading(row: Dictionary, api) -> void:
	var near: Dictionary = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
	if near.is_empty():
		return
	var vx: float = float(near.get("vx", 0.0))
	var vz: float = float(near.get("vz", 0.0))
	var len := sqrt(vx * vx + vz * vz)
	if len < STILL_SPEED:
		return
	row["face_x"] = vx / len
	row["face_z"] = vz / len


# ---- episode end ---------------------------------------------------------------

func _end_episode(row: Dictionary, api) -> void:
	# D-T-039-12: leaves/attack resolve at the same tick the countdown ends; the away
	# timer starts there (D-T-039-4), not at appearance.
	_park_away(row, api)
	row["anim_state"] = "recover"
	row["anim_state_t"] = 0
	row["return_timer"] = _next_return_ticks(row, api)
	row["target_index"] = -1


# uniform [lo, hi] in ticks, discounted -5 s per extra vote beyond the first, clamped to
# the absolute floors (D-T-039-4). cfg stamps "votes" at plan time (absent -> 1).
func _next_return_ticks(row: Dictionary, api) -> int:
	var votes: int = maxi(int(row.get("cfg", {}).get("votes", 1)) - 1, 0) * RETURN_VOTE_DISCOUNT
	var lo := maxi(RETURN_MIN_TICKS - votes, RETURN_MIN_FLOOR)
	var hi := maxi(RETURN_MAX_TICKS - votes, RETURN_MAX_FLOOR)
	var rng = api.rng()
	return rng.ri(lo, hi)


func _park_away(row: Dictionary, api) -> void:
	row["y"] = float(row.get("cfg", {}).get("away_y_u", AWAY_Y))
	api.sync_body()



