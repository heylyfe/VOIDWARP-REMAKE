extends "res://sim/enemy_runtime.gd".EnemyBehavior
#
# YOU?! behavior module (ticket T-035). The corrupted copy of the player.
#
# Spec: ENEMIES.md (the Husk -> YOU?! section, copied 1:1) and DESIGN.md section
# 5.6 (the numbers); section 12 is the API contract. ENEMIES.md behavior sentences
# are the spec (D-040). Readings and gaps are recorded in DECISIONS.md
# (D-T-035-1..13); the load-bearing ones:
#
# - floats toward the nearest player at 3.4 u/s; pursuit ceiling 0.55, so never
#   above 4.95 u/s after any multiplier (SR-5); feet ease at 2.0 u/s (SR-1);
# - within 8 u: it STOPS and rumbles 3.0 s (180 ticks) -> a shockwave ring from its
#   position; the rumble is the tell (its view effect is the 180-tick `telegraph`
#   row of the T-083 anim block). It holds position for the whole tell (D-YOU-C7-2):
#   at 3.4 u/s a 3.0 s tell would otherwise carry it 10.2 u, straight through the
#   player's body, and the touch kill would land before the ring ever released;
# - the ring expands 9 u/s to radius 8 u, is 1.0 u tall and 0.6 u thick,
#   travels in the horizontal plane of its feet; hit = kill; jumpable;
#   the kill window is the player's feet strictly inside
#   (ring_feet - 1.5, ring_feet + 1.0) - D-T-035-1; the radial hit window is
#   |d - r| <= 0.7 u (band half-thickness + player half-width) - D-T-035-2;
# - ring cooldown 4.0 s; touch = kill (the framework's body-contact check,
#   unchanged - this module never decides contact kills itself);
# - 5-frame corrupted run cycle (sprites/cycle_00..04.png, 8 fps).
#
# Cycle 7 (owner: "you?!" smaller range + slower strike): the ring's reach is 8 u
# (57% of the old 14 u) and the tell is 3.0 s (2x the old 1.5 s). The ring's SPEED
# is unchanged at 9 u/s on purpose - the crossing time a jump must cover is
# 2 x 0.7 u / 9 u/s = 0.156 s whatever the radius is, so a smaller ring does not
# shrink the jump window; it only shortens how long the band lives (0.89 s instead
# of 1.56 s). D-YOU-C7-1 has the arithmetic.
#
# Echo Ring (the double_ring curse) is T-051's; this behavior makes each release
# observable on the row ("ring_seq" / "last_ring_tick") so its on_tick can detect
# a release and schedule the follow-up ring - D-T-035-10.

const RT := preload("res://sim/enemy_runtime.gd")

const TRIGGER_DISTANCE := 8.0
const RUMBLE_TICKS := 180                 # 3.0 s at 60 Hz
const RING_SPEED := 9.0                   # u/s
const RING_MAX := 8.0                     # u, hard cap
const RING_THICK := 0.6                   # u, radial thickness
const RING_RADIAL_WINDOW := RING_THICK * 0.5 + 0.4   # 0.7 u (D-T-035-2)
const RING_HEIGHT := 1.0                  # u, the drawn band + the upper kill edge
const RING_BELOW := 1.5                   # u, kill extends this far below the feet plane (D-T-035-1)
const RING_COOLDOWN := 240                # 4.0 s at 60 Hz
const ATTACK_HOLD := 18                   # release frame hold (D-T-035-3)
const RECOVER_TICKS := 240                # 4.0 s, the anim block's `recover` row
const KILLER_ID := "YOU"                  # api.kill -> "D-YOU" (D-T-035-4)
const TELEGRAPH_KIND := "you_rumble"


func _init() -> void:
	id = "you"
	display_name = "YOU?!"


## The runtime cfg this enemy hands to EnemyRuntime.plan()/spawn_at(): the stats block
## of content/enemies/you/enemy.json. Mirror - the test asserts the two agree.
static func cfg() -> Dictionary:
	return {
		"base_speed": 3.4,
		"pursuit_ceiling": 0.55,
		"burst_ceiling": 1.0,
		"world_height": 1.8,
		"hit_diameter": 0.7,
		"preferred_kind": "open",
		"contact_kill": true,
		"death_code": "D-YOU",
		"cycle_s": 0.625,
		"trigger_distance": TRIGGER_DISTANCE,
		"rumble_ticks": RUMBLE_TICKS,
		"ring_speed_u_per_s": RING_SPEED,
		"ring_max_radius": RING_MAX,
		"ring_thickness": RING_THICK,
		"ring_height": RING_HEIGHT,
		"ring_below_feet": RING_BELOW,
		"ring_cooldown_ticks": RING_COOLDOWN,
		"attack_hold_ticks": ATTACK_HOLD,
		"recover_ticks": RECOVER_TICKS,
	}


func on_spawn(row: Dictionary, _api) -> void:
	row["ticks"] = 0                     # row-local tick counter (echo ring detection)
	row["anim_state"] = "idle_chase"     # one of the T-083 anim block state keys
	row["anim_state_t"] = 0              # ticks spent in the current anim state
	row["cooldown_left"] = 0             # ring cooldown (240 from release)
	row["rumble_left"] = 0
	row["recover_left"] = 0
	row["rings"] = []                    # live rings, {"x", "y", "z", "r"} each
	row["ring_seq"] = 0
	row["last_ring_tick"] = -1


func tick(row: Dictionary, api, dt_ticks: int) -> void:
	row["ticks"] = int(row.get("ticks", 0)) + dt_ticks
	row["anim_state_t"] = int(row.get("anim_state_t", 0)) + dt_ticks
	# rings sub-step one tick at a time so a band never skips a player between checks
	for _i in range(maxi(dt_ticks, 0)):
		_step_ring_once(row, api)
	if int(row["cooldown_left"]) > 0:
		row["cooldown_left"] = maxi(0, int(row["cooldown_left"]) - dt_ticks)
	var near: Dictionary = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
	# floats toward the nearest player at 3.4 u/s through every phase EXCEPT the tell
	# (D-T-035-6, narrowed by D-YOU-C7-2): during the 3.0 s rumble it charges in place,
	# so the ring releases from the distance it telegraphed from and the touch kill
	# cannot land before the ring does. update() keeps h_speed/tempo_mul live (SR-5).
	if not near.is_empty():
		var fb: Variant = row.get("float", null)
		if fb == null:
			fb = RT.FloatBody.from_cfg(row["cfg"])
			row["float"] = fb
		if str(row["anim_state"]) == "telegraph":
			fb.update(api, dt_ticks)
		else:
			fb.step(row, api, dt_ticks, float(near["x"]), float(near["z"]))
	_advance_state(row, api, near, dt_ticks)


func _advance_state(row: Dictionary, api, near: Dictionary, dt_ticks: int) -> void:
	var state := str(row["anim_state"])
	match state:
		"idle_chase":
			if not near.is_empty() and int(row["cooldown_left"]) <= 0 \
					and float(near.get("dist", INF)) <= TRIGGER_DISTANCE:
				row["anim_state"] = "telegraph"
				row["anim_state_t"] = 0
				row["rumble_left"] = RUMBLE_TICKS
				api.telegraph(TELEGRAPH_KIND,
					{"shape": "circle", "cx": float(row["x"]), "cz": float(row["z"]),
					"r": RING_MAX, "y0": float(row["y"]), "y1": float(row["y"]) + RING_HEIGHT},
					RUMBLE_TICKS)
		"telegraph":
			row["rumble_left"] = int(row["rumble_left"]) - dt_ticks
			if int(row["rumble_left"]) <= 0:
				_release_ring(row)
		"attack":
			if int(row["anim_state_t"]) >= ATTACK_HOLD:
				row["anim_state"] = "recover"
				row["anim_state_t"] = 0
				row["recover_left"] = RECOVER_TICKS
		"recover":
			row["recover_left"] = int(row["recover_left"]) - dt_ticks
			if int(row["recover_left"]) <= 0:
				row["anim_state"] = "idle_chase"
				row["anim_state_t"] = 0
		_:
			row["anim_state"] = "idle_chase"
			row["anim_state_t"] = 0


func _release_ring(row: Dictionary) -> void:
	var ring := {"x": float(row["x"]), "y": float(row["y"]), "z": float(row["z"]), "r": 0.0}
	var rings: Array = row["rings"]
	rings.append(ring)
	row["rings"] = rings
	row["ring_seq"] = int(row["ring_seq"]) + 1
	row["last_ring_tick"] = int(row["ticks"])
	row["anim_state"] = "attack"
	row["anim_state_t"] = 0
	row["cooldown_left"] = RING_COOLDOWN


func _step_ring_once(row: Dictionary, api) -> void:
	var rings: Array = row.get("rings", [])
	if rings.is_empty():
		return
	var keep: Array = []
	for ring in rings:
		if bool(ring.get("done", false)):
			continue   # the 8 u tick is spent; the ring expires
		ring["r"] = float(ring["r"]) + RING_SPEED / 60.0
		if float(ring["r"]) >= RING_MAX:
			ring["r"] = RING_MAX
			ring["done"] = true
		_ring_kill_check(api, ring)
		keep.append(ring)
	row["rings"] = keep


# The ring hits the nearest player only through the section 12 API (D-T-035-13):
# the head is ignored; the player's feet must sit strictly inside
# (ring_feet - RING_BELOW, ring_feet + RING_HEIGHT) and within
# RING_RADIAL_WINDOW of the expanding edge.
func _ring_kill_check(api, ring: Dictionary) -> void:
	var near: Dictionary = api.nearest_player(Vector3(float(ring["x"]), float(ring["y"]), float(ring["z"])))
	if near.is_empty():
		return
	var dx := float(near["x"]) - float(ring["x"])
	var dz := float(near["z"]) - float(ring["z"])
	var dist := sqrt(dx * dx + dz * dz)
	if absf(dist - float(ring["r"])) > RING_RADIAL_WINDOW:
		return
	var feet := float(near["y"])
	var ry := float(ring["y"])
	if feet <= ry - RING_BELOW or feet >= ry + RING_HEIGHT:
		return
	api.kill(int(near["index"]), KILLER_ID)
