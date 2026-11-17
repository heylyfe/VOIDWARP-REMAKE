extends "res://sim/enemy_runtime.gd".EnemyBehavior
#
# claude behavior module (ticket T-040). The musical area-attack enemy: drums = radial
# shockwave rings, strings = sweeping beams, wind = homing shots; the attacks follow
# musical timing, so dodge rhythmically (ENEMIES.md "Cadence -> Claude", Behavior 1:1).
#
# Spec: DESIGN.md section 5.11 (the numbers, FINAL via D-064..D-075 / SR-2 / SR-5),
# ENEMIES.md's Claude section (the behavior sentences, D-040), the T-083 anim block in
# content/enemies/claude/sprites.json (state names + rates - read, never re-declared),
# section 12 (the API contract). Readings carried as DECISIONS D-T-040-1..7:
#   - floats at 4.0 u/s toward the nearest player while it is FARTHER than 20 u; within
#     20 u it holds position ("keeping within 20 u of the player" is the leash, not a
#     chase-to-contact; SR-2's consequence row is "keeps its distance (within 20 u)");
#   - pursuit ceiling 0.55 -> never above 4.95 u/s after ALL multipliers (SR-5); feet
#     ease at 2.0 u/s (SR-1, FloatBody - NEVER multiplied);
#   - beat clock: 100 BPM base (beat = 36 ticks at 60 Hz), tempo = 100 + 0.6 x agitation
#     BPM; the clock starts at spawn. One attack per bar (4 beats), cycling
#     drums -> strings -> wind. Agitation 0-100 rises 2/s; a plushie pickup is -35;
#     at 100 (Deadline) every bar runs all three attacks (tempo 160 BPM);
#   - DRUMS: on beats 1 and 3 of a drums bar a radial ring leaves Claude - 12 u/s to
#     radius 18 u, 1.0 u tall, kills, jumpable. The ring's vertical window and radial
#     window adopt D-T-035-1/D-T-035-2's YOU?! ring readings (feet strictly inside
#     (ring feet - 1.5, ring feet + 1.0); |d - r| <= 0.6/2 + 0.4 = 0.7 u);
#   - STRINGS: on the strings bar's beat 1 the direction to the player is FROZEN and a
#     red 24 u telegraph line shows for exactly 1 beat; the beam (24 u long, 1.5 u wide,
#     0.5-1.5 u above the origin's feet) then sweeps 120 degrees over 4 beats. Blocked
#     by tiles and props (api.los at the beam's heights); jumpable (feet at/above
#     origin feet + 1.5 clears the band);
#   - WIND: on beats 1, 2 and 3 of a wind bar a homing shot leaves Claude's body centre:
#     7.0 u/s, turns at most 90 deg/s (1.5 deg/tick - exact precomputed sin/cos step
#     constants, the section 13 lookup-table rule), lives 4.0 s = 240 ticks (D-071),
#     kills, and dies on touching any tile slab, step riser or prop (api.los per step);
#   - BODY: 2.0 u tall, hit diameter 1.6 u (SR-2); contact = kill (the framework's
#     cylinder check, unchanged); the spawn fade (30 ticks) blocks contact by zeroing
#     the row's diameter until the fade completes;
#   - PLUSHIES: every 25 s (1500 ticks) a clawd Crab plushie appears on a tile 10-25 u
#     from the player (max 3 present); picking one up is -35 agitation. The clawd Crab
#     sprite was never fetched (TBD.md row 26): the three TBD logo frames stand in at
#     the plushie_idle row's exact 6 fps / 10 ticks per frame (view-side).
#
# KILL TESTS RUN WITH LAST LIGHT ALREADY SPENT (D-057). No arbiter block: SR-4's
# scheduling gates are address me's and gin ichimaru's alone (D-067).

const RT := preload("res://sim/enemy_runtime.gd")

## Roster numbers (DESIGN.md section 5.11 / SR-2 / SR-5; mirrors enemy.json's stats).
const BODY_HEIGHT := 2.0
const HIT_DIAMETER := 1.6          # SR-2's FINAL row (0.8 x the 2.0 u body width)
const BASE_SPEED := 4.0            # u/s float
const PURSUIT_CEILING := 0.55      # 0.55 x 9.0 = 4.95 u/s cap, SR-5
const BURST_CEILING := 1.0         # no telegraphed sprint exists for claude
const KEEP_WITHIN_U := 20.0        # the leash (D-T-040-1)
const MIN_LEVEL := 15
const MAX_VOTES := 1
const DEATH_CODE := "D-CLAUDE"     # DESIGN.md section 3.1 (FINAL); death.gd's map
const KILLER_ID := "Claude"        # the runtime derives "D-CLAUDE" from this too

## Music (DESIGN.md section 5.11): 100 BPM base, +0.6 BPM per agitation point.
const BPM_BASE := 100.0
const BPM_PER_AGITATION := 0.6
const BAR_BEATS := 4
const BEATS_PER_BAR_F := 4.0

## Agitation and plushies.
const AGITATION_RISE_PER_S := 2.0
const AGITATION_MAX := 100.0
const PLUSHIE_CALM := 35.0
const PLUSHIE_INTERVAL_TICKS := 1500   # 25.0 s
const PLUSHIE_MAX := 3
const PLUSHIE_MIN_U := 10.0
const PLUSHIE_MAX_U := 25.0

## Drums.
const DRUM_BEATS := [0, 2]             # beats 1 and 3, 0-indexed within the bar
const DRUM_SPEED := 12.0               # u/s
const DRUM_RADIUS := 18.0              # u
const DRUM_HEIGHT := 1.0               # u, the band + the upper kill edge
const DRUM_BELOW := 1.5                # u, kill reaches this far below the feet plane
const DRUM_THICKNESS := 0.6            # u, radial thickness (as YOU?!'s ring)
const DRUM_RADIAL_WINDOW := DRUM_THICKNESS * 0.5 + 0.4   # 0.7 u (D-T-035-2's reading)
const DRUM_LIFE_TICKS := 90            # 18 u / 12 u/s = 1.5 s, tempo-independent

## Strings.
const STRINGS_TELEGRAPH_BEATS := 1.0
const STRINGS_SWEEP_DEG := 120.0
const STRINGS_SWEEP_BEATS := 4.0
const STRINGS_LENGTH := 24.0           # u
const STRINGS_HALF_WIDTH := 0.75       # 1.5 u wide -> 0.75 u each side of the ray
const STRINGS_HEIGHT_MIN := 0.5        # u above the origin's feet
const STRINGS_HEIGHT_MAX := 1.5
const PLAYER_HALF_WIDTH := 0.4         # DESIGN.md section 4's player AABB
const PLAYER_HEIGHT := 1.8
const PLAYER_CENTRE_U := 0.9           # body centre = feet + 0.9 u

## Wind.
const WIND_SPEED := 7.0                # u/s
const WIND_TURN_STEP := 1.5            # deg per tick = 90 deg/s at 60 Hz
const WIND_LIFE_TICKS := 240           # 4.0 s, D-071
const WIND_BEATS := [0, 1, 2]          # beats 1, 2 and 3, 0-indexed
const WIND_HIT_R := 0.25 + PLAYER_HALF_WIDTH   # 0.65 u, centre-to-centre
const WIND_SHOT_R := 0.25                      # the 0.5 u notification dot's radius
# One 1.5 deg turn step, precomputed (section 13: "no sin/cos - use lookup tables";
# these two literals are the lookup row for the FIXED per-tick step - 90 deg/s at 60 Hz):
const WIND_COS_STEP := 0.999657324975557    # cos(1.5 deg)
const WIND_SIN_STEP := 0.026176948307873    # sin(1.5 deg)

## Spawn fade (the anim block's spawn row).
const SPAWN_FADE_TICKS := 30


## The runtime cfg this enemy hands to EnemyRuntime.plan()/spawn_at(): the stats block
## of content/enemies/claude/enemy.json. Mirror - the test asserts the two agree.
static func cfg() -> Dictionary:
	return {
		"base_speed": BASE_SPEED,
		"pursuit_ceiling": PURSUIT_CEILING,
		"burst_ceiling": BURST_CEILING,
		"world_height": BODY_HEIGHT,
		"body_height": BODY_HEIGHT,
		"hit_diameter": HIT_DIAMETER,
		"preferred_kind": "open",
		"keep_within_u": KEEP_WITHIN_U,
		"bpm_base": BPM_BASE,
		"bpm_per_agitation": BPM_PER_AGITATION,
		"bar_beats": 4,
		"agitation_rise_per_s": AGITATION_RISE_PER_S,
		"agitation_max": AGITATION_MAX,
		"drum_beats": DRUM_BEATS,
		"drum_ring_speed_u_per_s": DRUM_SPEED,
		"drum_ring_max_radius": DRUM_RADIUS,
		"drum_ring_height": DRUM_HEIGHT,
		"drum_ring_thickness": DRUM_THICKNESS,
		"strings_telegraph_beats": STRINGS_TELEGRAPH_BEATS,
		"strings_sweep_deg": STRINGS_SWEEP_DEG,
		"strings_sweep_beats": STRINGS_SWEEP_BEATS,
		"strings_length_u": STRINGS_LENGTH,
		"strings_width_u": STRINGS_HALF_WIDTH * 2.0,
		"strings_height_min_u": STRINGS_HEIGHT_MIN,
		"strings_height_max_u": STRINGS_HEIGHT_MAX,
		"wind_shots_beats": [1, 2, 3],
		"wind_speed_u_per_s": WIND_SPEED,
		"wind_turn_deg_per_s": 90.0,
		"wind_life_s": 4.0,
		"plushie_interval_s": 25.0,
		"plushie_max": PLUSHIE_MAX,
		"plushie_min_u": PLUSHIE_MIN_U,
		"plushie_max_u": PLUSHIE_MAX_U,
		"plushie_calm": PLUSHIE_CALM,
		"spawn_fade_ticks": SPAWN_FADE_TICKS,
		"contact_kill": true,
		"death_code": DEATH_CODE,
		"cycle_s": 0.0,
		"cycle_ticks": 0,
		"frame_w": 256,
		"frame_h": 256,
		"body_rect": [16, 16, 224, 224],   # the T-016 TBD sheet's tight body bbox
	}


func _init() -> void:
	id = "claude"
	display_name = "Claude"


func on_spawn(row: Dictionary, _api) -> void:
	row["age"] = 0
	row["beat_pos"] = 0.0                # float beats since the music started
	row["beat_fired"] = -1               # the last beat index whose boundary fired
	row["agitation"] = 0.0
	row["plushie_cd"] = PLUSHIE_INTERVAL_TICKS
	row["plushies"] = []                 # {"x","y","z"} at tile-top height
	row["rings"] = []                    # live drum rings {"x","y","z","r"}
	row["sweeps"] = []                   # live beams (Deadline can run two)
	row["shots"] = []                    # live wind shots
	row["str_tel_left"] = 0              # the 1-beat strings telegraph
	row["str_dx"] = 0.0                  # the frozen sweep direction (unit, xz)
	row["str_dz"] = 1.0
	row["drum_hold"] = 0                 # anim-state holds (one beat after each fire)
	row["wind_hold"] = 0
	row["last_drum_tick"] = -1
	row["last_shot_tick"] = -1
	row["last_sweep_tick"] = -1
	row["last_plushie_tick"] = -1
	row["last_pickup_tick"] = -1
	row["anim_state"] = "spawn"
	row["anim_state_t"] = 0
	# the spawn fade blocks contact (the anim block's spawn row): no body contact
	# until the fade completes - the framework reads row diameter_u, so zero it
	row["diameter_full"] = float(row["diameter_u"])
	row["diameter_u"] = 0.0


func tick(row: Dictionary, api, dt_ticks: int) -> void:
	# one tick at a time: every number below is phase-locked to the 60 Hz grid
	for _i in range(maxi(dt_ticks, 0)):
		_tick_one(row, api)


func _tick_one(row: Dictionary, api) -> void:
	row["age"] = int(row["age"]) + 1
	if int(row["age"]) == SPAWN_FADE_TICKS:
		row["diameter_u"] = float(row["diameter_full"])   # the fade is done: contact kills
	_advance_music(row, api)
	_tick_agitation(row)
	_tick_plushies(row, api)
	_tick_float(row, api)
	_tick_rings(row, api)
	_tick_strings(row, api)
	_tick_shots(row, api)
	if int(row["drum_hold"]) > 0:
		row["drum_hold"] = int(row["drum_hold"]) - 1
	if int(row["wind_hold"]) > 0:
		row["wind_hold"] = int(row["wind_hold"]) - 1
	_pick_anim_state(row)


# ---- the music -------------------------------------------------------------------------------

func _bpm(row: Dictionary) -> float:
	return BPM_BASE + BPM_PER_AGITATION * float(row["agitation"])


func _beat_ticks(row: Dictionary) -> float:
	return 3600.0 / _bpm(row)            # 36.0 ticks at 100 BPM; 22.5 at the Deadline's 160


func _advance_music(row: Dictionary, api) -> void:
	row["beat_pos"] = float(row["beat_pos"]) + _bpm(row) / 3600.0
	var beat := int(floor(float(row["beat_pos"])))
	while int(row["beat_fired"]) < beat:
		row["beat_fired"] = int(row["beat_fired"]) + 1
		_on_beat(row, api, int(row["beat_fired"]))


## The kinds this bar runs. Deadline (agitation 100): all three, every bar. Otherwise
## one attack per bar, cycling drums -> strings -> wind (DESIGN.md section 5.11).
func _bar_kinds(row: Dictionary, bar: int) -> Array:
	if float(row["agitation"]) >= AGITATION_MAX - 1e-9:
		return ["drums", "strings", "wind"]
	var cycle := ["drums", "strings", "wind"]
	return [cycle[bar % 3]]


func _on_beat(row: Dictionary, api, beat: int) -> void:
	var in_bar := beat % BAR_BEATS
	var kinds: Array = _bar_kinds(row, beat / BAR_BEATS)
	if kinds.has("drums") and DRUM_BEATS.has(in_bar):
		_fire_drum(row, api)
	if kinds.has("strings") and in_bar == 0:
		_begin_strings(row, api)
	if kinds.has("wind") and WIND_BEATS.has(in_bar):
		_fire_shot(row, api)


# ---- agitation and plushies ------------------------------------------------------------------

func _tick_agitation(row: Dictionary) -> void:
	var a: float = minf(float(row["agitation"]) + AGITATION_RISE_PER_S / 60.0, AGITATION_MAX)
	row["agitation"] = a


## Every 25 s a plushie appears on a tile 10-25 u from the player, max 3 present
## (DESIGN.md section 5.11). Tile choice: the FARTHEST candidate in the band (ties by
## tile order) - deterministic, no rng draw needed (D-T-040-6). No eligible tile this
## tick: retry on the next tick, the 25 s clock restarts only on a real placement.
func _tick_plushies(row: Dictionary, api) -> void:
	if int(row["plushie_cd"]) > 0:
		row["plushie_cd"] = int(row["plushie_cd"]) - 1
		return
	if (row["plushies"] as Array).size() >= PLUSHIE_MAX:
		return   # hold at the cap: the clock stays open, the next pickup re-arms it
	var near: Dictionary = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
	if near.is_empty():
		return
	var px := float(near["x"])
	var pz := float(near["z"])
	var best: Variant = null
	var best_d := -1.0
	for t in api.tiles_in_radius(Vector3(px, float(near["y"]), pz), PLUSHIE_MAX_U):
		var dx := float(t["x"]) - px
		var dz := float(t["z"]) - pz
		var d := sqrt(dx * dx + dz * dz)
		if d < PLUSHIE_MIN_U or d > PLUSHIE_MAX_U:
			continue
		if best == null or d > best_d:
			best = t
			best_d = d
	if best == null:
		return
	var plushies: Array = row["plushies"]
	plushies.append({"x": float(best["x"]), "y": float(best["y"]), "z": float(best["z"])})
	row["plushies"] = plushies
	row["plushie_cd"] = PLUSHIE_INTERVAL_TICKS
	row["last_plushie_tick"] = int(row["age"])


## Walk-over pickup: 0.4 u half-width + a 0.5 u reach (D-T-040-6), any height within
## reach of the tile top. Pickup = -35 agitation (never below 0), squeak-pop.
func _pickup_plushies(row: Dictionary, api, near: Dictionary) -> void:
	if (row["plushies"] as Array).is_empty() or near.is_empty():
		return
	var keep: Array = []
	for p in row["plushies"]:
		var dx := float(near["x"]) - float(p["x"])
		var dz := float(near["z"]) - float(p["z"])
		var dy := float(near["y"]) - float(p["y"])
		var picked := dx * dx + dz * dz <= 0.9 * 0.9 and absf(dy) <= 2.0
		if not picked:
			keep.append(p)
			continue
		row["agitation"] = maxf(float(row["agitation"]) - PLUSHIE_CALM, 0.0)
		row["last_pickup_tick"] = int(row["age"])
	row["plushies"] = keep


# ---- movement (the leash) --------------------------------------------------------------------

## Floats toward the nearest player at 4.0 u/s (SR-5 ceiling 0.55 -> 4.95, SR-1 easing
## via FloatBody) while FARTHER than 20 u; within 20 u it holds position (D-T-040-1).
## The 20 u leash also bounds the plushie hunt: the plushie target search runs from the
## player, not from Claude.
func _tick_float(row: Dictionary, api) -> void:
	var near: Dictionary = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
	_pickup_plushies(row, api, near)
	if near.is_empty():
		return
	if float(near["dist"]) > KEEP_WITHIN_U:
		var fb: Variant = row.get("float", null)
		if fb == null:
			fb = RT.FloatBody.from_cfg(row["cfg"])
			row["float"] = fb
		fb.step(row, api, 1, float(near["x"]), float(near["z"]))


# ---- drums -----------------------------------------------------------------------------------

## On beats 1 and 3 of a drums bar: a radial ring leaves Claude's feet - 12 u/s to
## radius 18 u, 1.0 u tall, kills (DESIGN.md section 5.11). The runtime telegraph datum
## covers the ring's whole expansion so SR-4's "no ring is on the player" gate reads it.
func _fire_drum(row: Dictionary, api) -> void:
	var y := float(row["y"])
	var rings: Array = row["rings"]
	rings.append({"x": float(row["x"]), "y": y, "z": float(row["z"]), "r": 0.0, "done": false})
	row["rings"] = rings
	row["drum_hold"] = int(round(_beat_ticks(row)))
	row["last_drum_tick"] = int(row["age"])
	api.telegraph("drum_ring", {"shape": "circle", "cx": float(row["x"]),
			"cz": float(row["z"]), "r": DRUM_RADIUS, "y0": y, "y1": y + DRUM_HEIGHT},
			DRUM_LIFE_TICKS)


func _tick_rings(row: Dictionary, api) -> void:
	var rings: Array = row["rings"]
	if rings.is_empty():
		return
	var keep: Array = []
	for ring in rings:
		if bool(ring.get("done", false)):
			continue   # held one tick at the 18 u cap for the view; expired now
		ring["r"] = float(ring["r"]) + DRUM_SPEED / 60.0
		if float(ring["r"]) >= DRUM_RADIUS:
			ring["r"] = DRUM_RADIUS
			ring["done"] = true
		_ring_kill_check(api, ring)
		keep.append(ring)
	row["rings"] = keep


## YOU?!'s ring window (D-T-035-1/-2, adopted for claude's drums): the player's feet sit
## strictly inside (ring_feet - 1.5, ring_feet + 1.0) and within 0.7 u of the expanding
## edge - jump on the beat clears it (apex 2.25 u > the 1.0 u band top).
func _ring_kill_check(api, ring: Dictionary) -> void:
	var near: Dictionary = api.nearest_player(Vector3(float(ring["x"]), float(ring["y"]), float(ring["z"])))
	if near.is_empty():
		return
	var dx := float(near["x"]) - float(ring["x"])
	var dz := float(near["z"]) - float(ring["z"])
	var dist := sqrt(dx * dx + dz * dz)
	if absf(dist - float(ring["r"])) > DRUM_RADIAL_WINDOW:
		return
	var feet := float(near["y"])
	var ry := float(ring["y"])
	if feet <= ry - DRUM_BELOW or feet >= ry + DRUM_HEIGHT:
		return
	api.kill(int(near["index"]), KILLER_ID)


# ---- strings ---------------------------------------------------------------------------------

## On the strings bar's beat 1: freeze the sweep direction toward the player (D-069's
## fixed-line reading) and telegraph the red 24 u start line for exactly 1 beat.
func _begin_strings(row: Dictionary, api) -> void:
	var near: Dictionary = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
	var dx := 0.0
	var dz := 1.0
	if not near.is_empty():
		var vx := float(near["x"]) - float(row["x"])
		var vz := float(near["z"]) - float(row["z"])
		var l := sqrt(vx * vx + vz * vz)
		if l > 1e-9:
			dx = vx / l
			dz = vz / l
	row["str_dx"] = dx
	row["str_dz"] = dz
	row["str_tel_left"] = int(round(_beat_ticks(row) * STRINGS_TELEGRAPH_BEATS))
	var y := float(row["y"]) + (STRINGS_HEIGHT_MIN + STRINGS_HEIGHT_MAX) * 0.5
	var ex := float(row["x"]) + dx * STRINGS_LENGTH
	var ez := float(row["z"]) + dz * STRINGS_LENGTH
	api.telegraph("strings_line", {"shape": "circle", "cx": float(row["x"]),
			"cz": float(row["z"]), "r": 0.0, "y0": y, "y1": y,
			"line": [float(row["x"]), y, float(row["z"]), ex, y, ez]},
			int(row["str_tel_left"]))


func _tick_strings(row: Dictionary, api) -> void:
	if int(row["str_tel_left"]) > 0:
		row["str_tel_left"] = int(row["str_tel_left"]) - 1
		if int(row["str_tel_left"]) <= 0:
			# the telegraph is spent: the beam lifts off from Claude's CURRENT position
			# at the frozen angle (the telegraph warned exactly that line)
			var sweeps: Array = row["sweeps"]
			sweeps.append({"ox": float(row["x"]), "oy": float(row["y"]),
					"oz": float(row["z"]), "dx": float(row["str_dx"]),
					"dz": float(row["str_dz"]), "deg": 0.0})
			row["sweeps"] = sweeps
			row["last_sweep_tick"] = int(row["age"])
	for s in (row["sweeps"] as Array).duplicate():
		if bool(s.get("finished", false)):
			continue
		_tick_sweep(row, api, s)


## One sweep tick: kill-check the ray at its CURRENT angle, then advance it. The beam
## is the 24 u ray, 1.5 u wide, 0.5-1.5 u above the FROZEN origin feet; blocked by
## tiles and props (api.los); jumpable (feet at origin feet + 1.5 clears the band top).
## The ray advances by the tangent-chord identity - multiplying the unit direction by
## (1 + tan) on the perpendicular - so no trig call ever runs in the sim (section 13);
## the scalar deg drives the DURATION exactly, the vector is its geometry shadow.
## Sweep sense: counterclockwise, (-dz, dx) (D-T-040-4).
func _tick_sweep(row: Dictionary, api, s: Dictionary) -> void:
	_sweep_kill_check(api, s)
	var bt := _beat_ticks(row)
	var deg_step: float = STRINGS_SWEEP_DEG / (STRINGS_SWEEP_BEATS * bt)
	var done: float = float(s["deg"]) + deg_step
	if done >= STRINGS_SWEEP_DEG:
		s["deg"] = STRINGS_SWEEP_DEG
		s["finished"] = true
		return
	var rad: float = deg_step * 0.017453292519943295   # pi / 180; tan(rad) ~= rad here
	var ddx := float(s["dx"])
	var ddz := float(s["dz"])
	var nx: float = ddx - rad * ddz
	var nz: float = ddz + rad * ddx
	var nl := sqrt(nx * nx + nz * nz)
	s["dx"] = nx / nl
	s["dz"] = nz / nl
	s["deg"] = done


## The beam's kill rule at one instant: player centre within 1.15 u of the ray
## (0.75 half-width + 0.4 player half-width), projection along the ray inside
## [0, 24], body overlapping the 0.5-1.5 u band above the origin's feet, and the
## api.los ray from the beam's mid-height to the player's centre clear.
func _sweep_kill_check(api, s: Dictionary) -> void:
	var origin := Vector3(float(s["ox"]), float(s["oy"]), float(s["oz"]))
	var near: Dictionary = api.nearest_player(origin)
	if near.is_empty():
		return
	var feet := float(near["y"])
	if feet >= float(s["oy"]) + STRINGS_HEIGHT_MAX or feet + PLAYER_HEIGHT <= float(s["oy"]) + STRINGS_HEIGHT_MIN:
		return
	var dx := float(near["x"]) - float(s["ox"])
	var dz := float(near["z"]) - float(s["oz"])
	var ddx := float(s["dx"])
	var ddz := float(s["dz"])
	var along := dx * ddx + dz * ddz
	if along < 0.0 or along > STRINGS_LENGTH:
		return
	var px := dx - along * ddx
	var pz := dz - along * ddz
	if sqrt(px * px + pz * pz) > STRINGS_HALF_WIDTH + PLAYER_HALF_WIDTH:
		return
	if not api.los(origin + Vector3(0.0, (STRINGS_HEIGHT_MIN + STRINGS_HEIGHT_MAX) * 0.5, 0.0),
			Vector3(float(near["x"]), feet + PLAYER_CENTRE_U, float(near["z"]))):
		return
	api.kill(int(near["index"]), KILLER_ID)


func _drop_finished_sweeps(row: Dictionary) -> void:
	var keep: Array = []
	for s in row["sweeps"]:
		if not bool(s.get("finished", false)):
			keep.append(s)
	row["sweeps"] = keep


# ---- wind ------------------------------------------------------------------------------------

## On beats 1, 2 and 3 of a wind bar: a homing shot leaves Claude's body centre -
## 7.0 u/s, turn at most 90 deg/s, life 4.0 s, dies on any tile slab / riser / prop,
## kills (DESIGN.md section 5.11 + D-071).
func _fire_shot(row: Dictionary, api) -> void:
	var near: Dictionary = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
	var dx := 0.0
	var dy := 0.0
	var dz := 1.0
	if not near.is_empty():
		var v := Vector3(float(near["x"]) - float(row["x"]),
				float(near["y"]) + PLAYER_CENTRE_U - (float(row["y"]) + BODY_HEIGHT * 0.5),
				float(near["z"]) - float(row["z"]))
		if v.length() > 1e-9:
			v = v.normalized()
			dx = v.x
			dy = v.y
			dz = v.z
	var shots: Array = row["shots"]
	shots.append({"x": float(row["x"]), "y": float(row["y"]) + BODY_HEIGHT * 0.5,
			"z": float(row["z"]), "dx": dx, "dy": dy, "dz": dz, "life": WIND_LIFE_TICKS})
	row["shots"] = shots
	row["wind_hold"] = int(round(_beat_ticks(row)))
	row["last_shot_tick"] = int(row["age"])


## One shot per tick: steer (<= 1.5 deg toward the player's centre, the exact rotation
## constructed from the two precomputed 1.5 deg constants), move 7/60 u, die on solids
## (the prev->now segment clips a slab/riser/prop box), kill on the player's AABB
## (0.4 half-width + the 0.25 shot radius; the 1.8 u player height), expire at 240.
func _tick_shots(row: Dictionary, api) -> void:
	var shots: Array = row["shots"]
	if shots.is_empty():
		return
	var keep: Array = []
	for shot in shots:
		if not _shot_tick(row, api, shot):
			continue
		keep.append(shot)
	row["shots"] = keep


## Returns false when the shot died this tick.
func _shot_tick(row: Dictionary, api, shot: Dictionary) -> bool:
	var near: Dictionary = api.nearest_player(Vector3(float(shot["x"]), float(shot["y"]), float(shot["z"])))
	if not near.is_empty():
		var to := Vector3(float(near["x"]) - float(shot["x"]),
				float(near["y"]) + PLAYER_CENTRE_U - float(shot["y"]),
				float(near["z"]) - float(shot["z"]))
		var l := to.length()
		if l > 1e-9:
			var desired := to / l
			var dir := Vector3(float(shot["dx"]), float(shot["dy"]), float(shot["dz"]))
			if dir.dot(desired) >= WIND_COS_STEP:
				dir = desired        # within one 1.5 deg step of the target: aim
			else:
				var perp := desired - dir * dir.dot(desired)
				var pl := perp.length()
				if pl > 1e-9:
					dir = (dir * WIND_COS_STEP + perp * (WIND_SIN_STEP / pl)).normalized()
			shot["dx"] = dir.x
			shot["dy"] = dir.y
			shot["dz"] = dir.z
	var prev := Vector3(float(shot["x"]), float(shot["y"]), float(shot["z"]))
	var nxt := prev + Vector3(float(shot["dx"]), float(shot["dy"]), float(shot["dz"])) * (WIND_SPEED / 60.0)
	shot["x"] = nxt.x
	shot["y"] = nxt.y
	shot["z"] = nxt.z
	if not api.los(prev, nxt):
		return false              # clipped a tile slab, a step riser or a prop (D-071)
	if not near.is_empty():
		var px := float(near["x"]) - float(shot["x"])
		var pz := float(near["z"]) - float(shot["z"])
		var feet := float(near["y"])
		var in_xz := px * px + pz * pz <= WIND_HIT_R * WIND_HIT_R
		var in_y := float(shot["y"]) >= feet - WIND_SHOT_R and float(shot["y"]) <= feet + PLAYER_HEIGHT + WIND_SHOT_R
		if in_xz and in_y:
			api.kill(int(near["index"]), KILLER_ID)
			return false
	shot["life"] = int(shot["life"]) - 1
	return int(shot["life"]) > 0


# ---- the anim state --------------------------------------------------------------------------

## Priority (top wins): spawn fade -> attack_strings (a sweep is live) ->
## telegraph_strings -> attack_drums / attack_wind (the one-beat release holds) ->
## telegraph_drums (the beat BEFORE beats 1 and 3) -> deadline (agitation 100, the
## red face of the schedule) -> idle. All states render the same TBD logo frame;
## the deadline's red tint is the view's job (it reads row["agitation"] directly).
func _pick_anim_state(row: Dictionary) -> void:
	_drop_finished_sweeps(row)
	var st := "idle"
	if int(row["age"]) < SPAWN_FADE_TICKS:
		st = "spawn"
	elif not (row["sweeps"] as Array).is_empty():
		st = "attack_strings"
	elif int(row["str_tel_left"]) > 0:
		st = "telegraph_strings"
	elif int(row["drum_hold"]) > 0:
		st = "attack_drums"
	elif int(row["wind_hold"]) > 0:
		st = "attack_wind"
	elif _drum_telegraph_due(row):
		st = "telegraph_drums"
	elif float(row["agitation"]) >= AGITATION_MAX - 1e-9:
		st = "deadline"
	if st != str(row["anim_state"]):
		row["anim_state"] = st
		row["anim_state_t"] = 0
	else:
		row["anim_state_t"] = int(row["anim_state_t"]) + 1


## True while the NEXT beat is a drum-hit beat (in-bar 1 or 3, and the next bar
## runs drums): the anim block's telegraph_drums shows "the beat BEFORE beats 1 and 3".
func _drum_telegraph_due(row: Dictionary) -> bool:
	var next := int(row["beat_fired"]) + 1
	var kinds: Array = _bar_kinds(row, next / BAR_BEATS)
	return kinds.has("drums") and DRUM_BEATS.has(next % BAR_BEATS)
