extends RefCounted
#
# thicc ben behavior module (ticket T-032; DESIGN.md section 5.3, ENEMIES.md "Bell").
# Lives under content/ so the sim core stays enemy-agnostic. Numbers are the
# section 5.3 paragraph (binding, tests assert within +/-1 tick):
#
#   - every 13.35 s (801 ticks, binding) ben teleports to the CLOSEST player;
#   - telegraph: black smoke at the DESTINATION for 1.25 s (75 ticks); the
#     Westminster chime sounds during the final 0.5 s (30 ticks);
#   - the destination is LOCKED at smoke start: player position + velocity x
#     0.5 s; a player >= 4.0 u from the locked point at arrival has broken the
#     lock (ben still appears at the locked point - "ben appears where they were");
#   - touch: screen blur 3.0 s (180 ticks; strength 1 -> 0 linearly over the last
#     60 ticks, view-side), player launched upward at 18 u/s (apex ~5 u), bell rings;
#   - ben NEVER kills (KILL RULE: his touch is one of the three listed non-killing
#     effects); his ring cleanses glitched tiles within 8 u (DESIGN.md 5.8).
#
# BILLBOARDING / HITBOXES: ben is a PNG sprite; the hit cylinder rides enemy.json's
# world_height 4.0 u and the sprites.json body_rect (diameter 1.2 u per DESIGN.md
# section 5.2). contact_kill is false in enemy.json - the framework's contact-kill
# pass skips him; the eject below is the whole of his touch.

const RT := preload("res://sim/enemy_runtime.gd")

# ---- section 5.3 numbers (binding; enemy.json stats mirror these) -------------
const TELEPORT_TICKS := 801        # 13.35 s
const TELEGRAPH_TICKS := 75        # 1.25 s of smoke at the destination
const CHIME_TAIL_TICKS := 30       # the final 0.5 s of the cue (Westminster bongs)
const LOCK_LEAD_S := 0.5           # destination = player pos + velocity x 0.5 s
const LOCK_BREAK_DIST := 4.0       # >= 4 u from the locked point at arrival = lock broken
const BLUR_TICKS := 180            # 3.0 s screen blur
const EJECT_SPEED := 18.0          # u/s straight up; apex = 18^2 / (2 x 32) = 5.0625 u
const CLEANSE_RADIUS := 8.0        # ben's ring cleanses glitched tiles within 8 u (5.8)
const RING_TICKS := 18             # the ring wave expands to 8 u over 18 ticks
const TOUCH_COOLDOWN := 30         # D-T-032-1 [CONTESTABLE]: one eject per 0.5 s per player
const SPAWN_FADE_TICKS := 30       # common fade: no touch until the fade completes (1.0)

const KIND := "teleport"           # the telegraph kind the view/tests match on
const EJECT_WHY := "thicc_ben_eject"   # DATA: data/economy.json break_events whitelist
const TELEGRAPH_R := 1.2           # the smoke column width from the T-083 anim block


# The behavior inner class the loader instantiates: `enemy.gd` exports the
# preload constant path; the engine boots `Behavior.new()` as the row's behavior.
class Behavior:
	extends RT.EnemyBehavior

	func on_spawn(row: Dictionary, _api) -> void:
		row["phase"] = "idle"
		row["phase_t"] = 0
		row["cycle_t"] = 0
		row["spawn_ticks_left"] = SPAWN_FADE_TICKS
		row["lock_x"] = 0.0
		row["lock_y"] = 0.0
		row["lock_z"] = 0.0
		row["lock_broken"] = false
		row["touch_cooldown"] = 0
		row["blur_ticks_left"] = 0
		row["ring_ticks_left"] = 0
		row["last_cleanse"] = 0


	# One 60 Hz tick.
	func tick(row: Dictionary, api, dt_ticks: int) -> void:
		row["spawn_ticks_left"] = maxi(int(row.get("spawn_ticks_left", 0)) - dt_ticks, 0)
		row["touch_cooldown"] = maxi(int(row.get("touch_cooldown", 0)) - dt_ticks, 0)
		row["ring_ticks_left"] = maxi(int(row.get("ring_ticks_left", 0)) - dt_ticks, 0)
		row["blur_ticks_left"] = maxi(int(row.get("blur_ticks_left", 0)) - dt_ticks, 0)
		if str(row.get("phase", "idle")) == "telegraph":
			_telegraph_tick(row, api, dt_ticks)
		else:
			_idle_tick(row, api, dt_ticks)
		_touch(row, api)


	# Parked until 75 ticks before the next teleport; the cycle is the binding
	# 801 ticks from on_spawn (D-T-032-9).
	func _idle_tick(row: Dictionary, api, dt_ticks: int) -> void:
		row["cycle_t"] = int(row["cycle_t"]) + dt_ticks
		row["phase_t"] = int(row["phase_t"]) + dt_ticks
		if int(row["cycle_t"]) >= TELEPORT_TICKS - TELEGRAPH_TICKS:
			_begin_telegraph(row, api)


	func _telegraph_tick(row: Dictionary, api, dt_ticks: int) -> void:
		row["cycle_t"] = int(row["cycle_t"]) + dt_ticks
		row["phase_t"] = int(row["phase_t"]) + dt_ticks
		if int(row["phase_t"]) >= TELEGRAPH_TICKS:
			_arrive(row, api)


	# The destination is locked at smoke start = player position + velocity x
	# 0.5 s (section 5.3). The closest player to BEN is the target.
	func _begin_telegraph(row: Dictionary, api) -> void:
		var pos := Vector3(float(row["x"]), float(row["y"]), float(row["z"]))
		var near: Dictionary = api.nearest_player(pos)
		if near.is_empty():
			row["cycle_t"] = TELEPORT_TICKS - TELEGRAPH_TICKS  # no target: retry next tick
			return
		var lead := LOCK_LEAD_S
		row["phase"] = "telegraph"
		row["phase_t"] = 0
		row["lock_x"] = float(near["x"]) + float(near.get("vx", 0.0)) * lead
		row["lock_y"] = float(near["y"]) + float(near.get("vy", 0.0)) * lead
		row["lock_z"] = float(near["z"]) + float(near.get("vz", 0.0)) * lead
		row["lock_broken"] = false
		api.telegraph(KIND, {"shape": "circle",
				"cx": float(row["lock_x"]), "cz": float(row["lock_z"]),
				"r": TELEGRAPH_R}, TELEGRAPH_TICKS)


	# Tick 75: ben appears at the LOCKED point, full stop. "Broken the lock" is
	# a >= 4 u miss at arrival (3D to the feet; D-T-032-11) - the arrival position
	# never re-aims, so the miss is the reward for moving.
	func _arrive(row: Dictionary, api) -> void:
		row["x"] = float(row["lock_x"])
		row["y"] = float(row["lock_y"])
		row["z"] = float(row["lock_z"])
		var pos := Vector3(float(row["x"]), float(row["y"]), float(row["z"]))
		var near: Dictionary = api.nearest_player(pos)
		if not near.is_empty():
			var d := Vector3(float(near["x"]) - pos.x, float(near["y"]) - pos.y,
					float(near["z"]) - pos.z).length()
			row["lock_broken"] = d >= LOCK_BREAK_DIST
		api.sync_body()
		row["phase"] = "idle"
		row["phase_t"] = 0
		row["cycle_t"] = 0


	# Touch (every tick the nearest body overlaps ben's cylinder, rate-limited by
	# the 30-tick cooldown): vertical launch 18 u/s, 3.0 s blur, bell, and the
	# ring cleanses glitched tiles within 8 u (DESIGN.md 5.8). NEVER a kill.
	func _touch(row: Dictionary, api) -> void:
		if int(row.get("spawn_ticks_left", 0)) > 0:
			return
		if int(row.get("touch_cooldown", 0)) > 0:
			return
		var pos := Vector3(float(row["x"]), float(row["y"]), float(row["z"]))
		var near: Dictionary = api.nearest_player(pos)
		if near.is_empty():
			return
		var r: float = float(row.get("diameter_u", 1.2)) * 0.5 + 0.4
		var dx: float = float(near["x"]) - pos.x
		var dz: float = float(near["z"]) - pos.z
		if dx * dx + dz * dz > r * r:
			return
		var py0: float = float(near["y"])
		var py1: float = py0 + 1.8
		if py0 > float(row["y"]) + float(row.get("height_u", 4.0)) or py1 < float(row["y"]):
			return
		var idx := int(near["index"])
		api.push(idx, Vector3(0.0, 1.0, 0.0), EJECT_SPEED)
		api.eject_player(idx, EJECT_WHY, BLUR_TICKS)
		row["last_cleanse"] = api.cleanse_glitched_within(pos, CLEANSE_RADIUS)
		row["blur_ticks_left"] = BLUR_TICKS
		row["ring_ticks_left"] = RING_TICKS
		row["touch_cooldown"] = TOUCH_COOLDOWN


# Convenience for the engine loader and tests: `enemy.gd` -> Behavior instance.
static func new_behavior() -> RefCounted:
	return Behavior.new()
