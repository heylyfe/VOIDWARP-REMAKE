extends RefCounted
#
# seal behavior module (ticket T-038). The burst-threat starter enemy: flaps toward the
# nearest player; at a readable distance it fixes a dash line and bursts down it.
# Numbers (DESIGN.md section 5.9, FINAL via D-064..D-075 / SR-2 / SR-5):
#   - flap speed 4.0 u/s (pursuit ceiling 0.60 -> never above 5.4 u/s while flapping, SR-5);
#   - body 0.6 u tall, hit diameter 0.6 u (SR-2: "easily hurdle-able; its dash is the threat");
#   - feet ease toward the target's feet at 2.0 u/s (SR-1, NEVER multiplied);
#   - the dash is a FIXED 3D line fixed at telegraph start: seal body centre -> player
#     centre (0.9 u above the player's feet), extended to 20 u; never re-aims during the
#     0.75 s telegraph or the 1.0 s dash (D-069);
#   - a telegraph starts only when the seal is BETWEEN 4 u and 12 u from its target
#     (closer than 4 u it keeps flapping - hurdle it; farther than 12 u it closes in);
#   - attack: telegraph 0.75 s (45 ticks, dashed red 3D line, mouth-open frame) -> bark on
#     tick 0 of the dash -> dash 20 u in 1.0 s (60 ticks) along the fixed line ->
#     recover/idle 0.75 s (45 ticks);
#   - Contact at any time = kill (the framework checks the cylinder every tick);
#   - KILL TESTS RUN WITH LAST LIGHT ALREADY SPENT (D-057).
#
# ENEMIES.md seal section (Behavior 1:1): "small, fast, kills instantly on contact; ~1s
# high-pitched cry before it attacks. VOIDWRAP_RUN: the cry is replaced by a real seal bark
# when it dashes - it opens its mouth and flaps." The DESIGN.md section 5.9 paragraph
# (FINAL) maps the cry onto the 0.75 s telegraph and the bark onto dash tick 0.
#
# Content id lives here, never under sim/ (DESIGN.md section 12). The row dict is the only
# state; the behavior only touches its own row through the api. Frame/telegraph VFX live in
# the view (game/view/seal_view.gd) - sprites and billboarding are view-layer only. The
# dash moves the body centre along the fixed line (row y = centre - body_height/2), so the
# framework's upright-cylinder contact check yields the section 5.9 clear rules for free:
# a player whose feet sit more than 1.2 u above their telegraph-start height (a jump clears
# 1.2 u from 0.12 s to 0.63 s) or whose head is below the line simply does not overlap the
# 0.6 u body band at any tick of the crossing.
#
# No arbiter block: SR-4 scheduling gates are address me's and gin ichimaru's alone
# (D-067); the seal's dash_line telegraph carries a radius-0 footprint, so it never
# registers as a targeted telegraph for anyone else either (D-T-038-2).

const RT := preload("res://sim/enemy_runtime.gd")

## Roster numbers (DESIGN.md section 5.9 / SR-2 / SR-5; the runtime constants match).
const BASE_SPEED := 4.0            # u/s flap, SR-5 row "seal (flapping)"
const PURSUIT_CEILING := 0.6       # 0.60 x 9.0 = 5.4 u/s, SR-5 (dash is an attack, not pursuit)
const BURST_CEILING := 1.0         # no telegraphed sprint exists for the seal; the dash runs
                                   # on its own fixed kinematics, never through FloatBody
const BODY_HEIGHT := 0.6
const HIT_DIAMETER := 0.6          # SR-2 (0.3 u radius)
const CLIMB := 2.0                 # SR-1 vertical easing, u/s, never multiplied
const MIN_LEVEL := 3
const MAX_VOTES := 3
const DEATH_CODE := "D-SEAL"       # DESIGN.md section 3.1 (FINAL)
const PREFERRED_KIND := "lane"     # DESIGN.md section 5 anchor table
const RANGE_MIN_U := 4.0           # telegraph only at >= 4 u ...
const RANGE_MAX_U := 12.0          # ... and <= 12 u (DESIGN.md section 5.9)
const TELEGRAPH_TICKS := 45        # 0.75 s, binding (T-083 anim block: telegraph)
const DASH_TICKS := 60             # 1.0 s, binding (T-083 anim block: attack)
const DASH_LENGTH_U := 20.0        # binding (T-083 anim block: attack; DESIGN.md 5.9)
const RECOVER_TICKS := 45          # 0.75 s idle, binding (T-083 anim block: recover)
const PLAYER_CENTRE_U := 0.9       # player centre = feet + 0.9 u above the feet (DESIGN.md 5.9)
const DASH_STEP_U := DASH_LENGTH_U / float(DASH_TICKS)   # 1/3 u per tick, 20 u in 60 ticks
const BARK_TICKS := 1              # the bark telegraph marker is one tick (the cue, not a
                                   # damage footprint)


## The runtime cfg this enemy hands to EnemyRuntime.plan()/spawn_at(): everything the
## framework needs to place, size, move and kill-check the body. Mirror of enemy.json's
## stats block - the test asserts the two agree.
static func cfg() -> Dictionary:
	return {
		"base_speed": BASE_SPEED,
		"pursuit_ceiling": PURSUIT_CEILING,
		"burst_ceiling": BURST_CEILING,
		"climb_u_per_s": CLIMB,
		"world_height": BODY_HEIGHT,
		"body_height": BODY_HEIGHT,
		"hit_diameter": HIT_DIAMETER,
		"preferred_kind": PREFERRED_KIND,
		"telegraph_range_min_u": RANGE_MIN_U,
		"telegraph_range_max_u": RANGE_MAX_U,
		"telegraph_ticks": TELEGRAPH_TICKS,
		"dash_ticks": DASH_TICKS,
		"dash_length_u": DASH_LENGTH_U,
		"recover_ticks": RECOVER_TICKS,
		"contact_kill": true,
		"death_code": DEATH_CODE,
		"cycle_s": 0.0,
		"cycle_ticks": 0,
		"frame_w": 256,
		"frame_h": 256,
		"body_rect": [16, 16, 224, 224],   # the T-016 TBD sheet's tight body bbox
	}


## The behavior. Phase machine on the row: "flap" -> "telegraph" -> "dash" -> "recover"
## -> "flap". Flap: FloatBody pursuit (SR-1 ease, SR-5 ceiling); the moment the nearest
## player is between 4 u and 12 u the seal plants itself and fixes the dash line (D-069).
## Telegraph: hold still for 45 ticks, one "dash_line" telegraph (radius-0 footprint; the
## view draws the red dashes, the audio layer stays silent). Dash: the body centre rides
## the fixed line 1/3 u per tick for 60 ticks; on tick 0 of the dash a one-tick "bark"
## telegraph fires (ENEMIES.md: the real seal bark, replacing the cry). Recover: hold for
## 45 ticks (api.tempo_ticks may shorten it, SR-5) then flap again. Contact kills at every
## phase - the framework checks it.
class SealBehavior:
	extends RT.EnemyBehavior

	func on_spawn(row: Dictionary, _api) -> void:
		row["phase"] = "flap"
		row["phase_left"] = 0
		row["dash_done_u"] = 0.0
		# the fixed dash line (body centre -> player centre at telegraph start, extended to
		# 20 u along the fixed direction); set when the telegraph starts
		row["line_x0"] = 0.0
		row["line_y0"] = 0.0
		row["line_z0"] = 0.0
		row["dash_dx"] = 0.0
		row["dash_dy"] = 0.0
		row["dash_dz"] = 1.0

	func tick(row: Dictionary, api, dt_ticks: int) -> void:
		var pos := Vector3(float(row["x"]), float(row["y"]), float(row["z"]))
		var near: Dictionary = api.nearest_player(pos)
		if near.is_empty():
			return   # no players: the seal holds still
		match str(row.get("phase", "flap")):
			"flap":
				_flap(row, api, dt_ticks, near)
			"telegraph":
				_telegraph_tick(row, api, dt_ticks)
			"dash":
				_dash_tick(row, api, dt_ticks)
			"recover":
				_recover_tick(row, dt_ticks)
			_:
				row["phase"] = "flap"

	func _flap(row: Dictionary, api, dt_ticks: int, near: Dictionary) -> void:
		var fb: Variant = row.get("float", null)
		if fb == null:
			fb = RT.FloatBody.from_cfg(row["cfg"])
			row["float"] = fb
		fb.step(row, api, dt_ticks, float(near["x"]), float(near["z"]))
		var dist := float(near["dist"])
		if dist < RANGE_MIN_U or dist > RANGE_MAX_U:
			return   # too close: keep flapping (hurdle it) / too far: close in
		_start_telegraph(row, api, near)

	func _start_telegraph(row: Dictionary, api, near: Dictionary) -> void:
		# D-069: fix the line NOW - seal body centre through the player's centre (0.9 u above
		# the feet), extended to 20 u. It never re-aims during the telegraph or the dash.
		var c0 := Vector3(float(row["x"]), float(row["y"]) + BODY_HEIGHT * 0.5, float(row["z"]))
		var p1 := Vector3(float(near["x"]), float(near["y"]) + PLAYER_CENTRE_U, float(near["z"]))
		var dir := p1 - c0
		if dir.length() < 1e-9:
			dir = Vector3(0.0, 0.0, 1.0)   # degenerate overlap: dash +z (contact kills anyway)
		dir = dir.normalized()
		row["line_x0"] = c0.x
		row["line_y0"] = c0.y
		row["line_z0"] = c0.z
		row["dash_dx"] = dir.x
		row["dash_dy"] = dir.y
		row["dash_dz"] = dir.z
		row["phase"] = "telegraph"
		row["phase_left"] = TELEGRAPH_TICKS
		var end := c0 + dir * DASH_LENGTH_U
		api.telegraph("dash_line", {"shape": "circle", "cx": c0.x, "cz": c0.z, "r": 0.0,
				"dash_line": [c0.x, c0.y, c0.z, end.x, end.y, end.z]}, TELEGRAPH_TICKS)

	func _telegraph_tick(row: Dictionary, api, dt_ticks: int) -> void:
		# stationary wind-up; on tick 0 of the dash the bark fires (ENEMIES.md: the cry is
		# replaced by a real seal bark when it dashes)
		row["phase_left"] = int(row.get("phase_left", 0)) - dt_ticks
		if int(row["phase_left"]) > 0:
			return
		row["phase"] = "dash"
		row["phase_left"] = DASH_TICKS
		row["dash_done_u"] = 0.0
		api.telegraph("bark", {"shape": "circle", "cx": float(row["x"]),
				"cz": float(row["z"]), "r": 0.0}, BARK_TICKS)

	func _dash_tick(row: Dictionary, api, dt_ticks: int) -> void:
		var step := DASH_STEP_U * float(dt_ticks)
		var done := float(row.get("dash_done_u", 0.0)) + step
		row["dash_done_u"] = done
		var start := Vector3(float(row["line_x0"]), float(row["line_y0"]), float(row["line_z0"]))
		var dir := Vector3(float(row["dash_dx"]), float(row["dash_dy"]), float(row["dash_dz"]))
		var c := start + dir * done
		# body centre rides the line: feet at centre - body_height/2 (the framework's
		# upright cylinder then equals the section 5.9 clear rules, see the file header)
		row["x"] = c.x
		row["z"] = c.z
		row["y"] = c.y - BODY_HEIGHT * 0.5
		row["phase_left"] = int(row.get("phase_left", 0)) - dt_ticks
		if int(row["phase_left"]) <= 0:
			row["phase"] = "recover"
			# the dash has settled: the body is 20 u down its fixed line, so the mirror
			# (what no_enemy_body_within and the D-059 safe tile read) moves with it. Once,
			# at the settle - mid-dash the mirror is a lagging snapshot like any mover's
			# (PARKED row 27: the mirror is otherwise the runtime's spawn point).
			api.sync_body()
			# SR-5: tempo (the part of a speed multiplier the ceiling removes) shortens the
			# idle, never below TEMPO_FLOOR of the base cycle (api.tempo_ticks applies it)
			row["phase_left"] = api.tempo_ticks(RECOVER_TICKS)

	func _recover_tick(row: Dictionary, dt_ticks: int) -> void:
		# stationary 0.75 s idle after the dash; then flap again. SR-1 easing resumes in the
		# flap phase (api.move_toward), never multiplied.
		row["phase_left"] = int(row.get("phase_left", 0)) - dt_ticks
		if int(row["phase_left"]) <= 0:
			row["phase"] = "flap"
