extends RefCounted
#
# Deterministic player simulation (ticket T-012): 60 Hz kinematic controller with the
# class kits (DESIGN.md section 4), void charges + safe-tile ring + respawn
# (DESIGN.md section 3.1, D-050, D-053, D-057, D-059, D-063, D-066), Last Light
# (D-053, D-073) and launch pads (TERRAIN_SPEC section 4).
#
# Pure + deterministic: floats through + - * / and sqrt only, no engine calls, one
# instance per player owned by the sim state tree. Collision is sim/collision.gd
# (D-047); the tile world lives in the level dict (tiles/props/pads arrays from
# game/terrain; glitched/slippery/removed/enemies/projectiles/hazards are live state).
#
# Per-tick input, the PlayerInput shape T-010 owns (sim/input.gd when merged):
#   {"move_x": int8, "move_z": int8, "buttons": int, "aim_x": float, "aim_z": float}
# move_x/move_z are world-space (pre-rotated by the client), buttons is the bitmask
# JUMP=1 ABILITY=2 INTERACT=4. aim_x/aim_z carry the dash fallback direction (camera
# forward, app-side per T-082); they default to +z here.
# step(dt, input, world) -> Array of event dicts; events are the only output besides
# the controller's own state (read by view/hud via the snapshot helpers).

const CollisionScript := preload("res://sim/collision.gd")

const BTN_JUMP := 1
const BTN_ABILITY := 2
const BTN_INTERACT := 4

# Mirrors data/player.json; the file wins for any key it carries.
const DEFAULTS := {
	"half_width": 0.4, "height": 1.8, "step_up": 0.5,
	"gravity": 32.0, "jump_velocity": 12.0, "run_speed": 9.0,
	"coyote_time": 0.10, "jump_buffer": 0.10, "jump_cut": 0.5,
	"accel": 90.0, "terminal_fall": 40.0, "kill_plane_y": -40.0,
	"void_charges": 2, "charge_cap": 2,
	"respawn_delay": 0.8, "respawn_invuln": 1.0,
	"safe_ring_size": 8, "safe_dwell": 0.5, "safe_enemy_dist": 6.0,
	"last_light_invuln": 2.0, "last_light_push_radius": 8.0,
	"dash_distance": 6.0, "dash_time": 0.20, "dash_regen": 3.0,
	"glide_fall_cap": 2.0, "glide_speed": 10.0, "glide_energy": 3.0,
	"athletic_run_mult": 1.15, "athletic_speed_upgrade_mult": 1.5,
	"athletic_air_jump_mult": 1.3,
	"pad_launch_vel": 16.0,
}

# T-053 Updraft (D-T053-6): the rise apex is exactly 3.0 u under gravity 32.0
# (vy = sqrt(2 x 32 x 3.0)); the cooldown is 6 s.
const UPDRAFT_RISE_U := 3.0
const UPDRAFT_VY := 13.856406460551018
const UPDRAFT_CD := 6.0

const KITS := ["dasher", "glider", "athletic"]


# data/player.json over every known numeric key onto the defaults (T-014c owns the
# file; missing file or keys fall back to DEFAULTS, never an error).
static func load_constants() -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	var f := FileAccess.open("res://data/player.json", FileAccess.READ)
	if f == null:
		return out
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null or not (parsed is Dictionary):
		return out
	var doc: Dictionary = parsed
	# T-014c's schema is nested; map it onto the controller's flat keys.
	# In-code fallbacks stay for the numbers the file does not carry: half_width /
	# height (DESIGN section 4 body), accel 90 (addendum R4), terminal_fall 40
	# (D-T012-1), kill_plane_y -40 and pad_launch_vel 16 (TERRAIN_SPEC section 4).
	var shared: Dictionary = doc.get("shared_kit", {})
	var classes: Dictionary = doc.get("classes", {})
	var dash: Dictionary = classes.get("dasher", {})
	var glider: Dictionary = classes.get("glider", {})
	var ath: Dictionary = classes.get("athletic", {})
	var vc: Dictionary = doc.get("void_charges", {})
	var vc_st: Dictionary = vc.get("safe_tile", {})
	var vc_hist: Dictionary = vc.get("history_ring", {})
	var ll: Dictionary = doc.get("last_light", {})
	var pairs: Array = [
		["run_speed", shared.get("run_speed")],
		["jump_velocity", shared.get("jump_velocity")],
		["gravity", shared.get("gravity")],
		["coyote_time", shared.get("coyote_time")],
		["jump_buffer", shared.get("jump_buffer")],
		["jump_cut", shared.get("jump_cut_mul")],
		["step_up", shared.get("auto_step_up")],
		["dash_distance", dash.get("dash_distance")],
		["dash_time", dash.get("dash_time")],
		["dash_regen", dash.get("dash_regen")],
		["glide_fall_cap", glider.get("glide_fall_speed_cap")],
		["glide_speed", glider.get("glide_horizontal_speed")],
		["glide_energy", glider.get("glide_energy")],
		["athletic_run_mult", ath.get("speed_bonus_mul")],
		["athletic_speed_upgrade_mult", ath.get("speed_upgrade_strength_mul")],
		["athletic_air_jump_mult", ath.get("double_jump_height_mul")],
		["void_charges", vc.get("start")],
		["charge_cap", vc.get("max")],
		["respawn_delay", vc.get("respawn_delay")],
		["respawn_invuln", vc.get("respawn_invulnerability")],
		["safe_enemy_dist", vc_st.get("min_distance_from_enemy_body_or_projectile")],
		["safe_ring_size", vc_hist.get("size")],
		["safe_dwell", vc_hist.get("min_stand_time")],
		["last_light_invuln", ll.get("invulnerability")],
		["last_light_push_radius", ll.get("arrival_enemy_push_radius")],
	]
	for p in pairs:
		var v: Variant = p[1]
		if v != null and (v is float or v is int):
			out[p[0]] = v
	# a flat-keyed file (or a future extension) overlays on top, key by key
	for k in out.keys():
		var v2: Variant = doc.get(k)
		if v2 != null and (v2 is float or v2 is int):
			out[k] = v2
	return out


var C: Dictionary = DEFAULTS.duplicate()
var kit: String = "dasher"

# body: feet position, world u.
var x := 0.0
var y := 0.0
var z := 0.0
var vx := 0.0
var vy := 0.0
var vz := 0.0
var grounded := false

# timers (seconds).
var lock := 0.0          # ability lock (D-070); glitched floor keeps the same state
var coyote := 0.0
var buffer := 0.0
var invuln := 0.0
var respawn_t := -1.0    # >= 0 while a void-fall respawn wait is running

# dasher.
var dash_ready := true
var dash_cd := 0.0
var dash_ticks := 0
var dash_dx := 0.0
var dash_dz := 0.0

# glider.
var gliding := false
var glide_energy := 3.0

# upgrades (set by the content layer via apply_* below).
var air_jumps := 0
var air_jumps_max := 0
var air_card_height := 1.0
var speed_base_add := 0.0
# T-053 Twin Dash (D-T053-5): dasher-only second
# dash stock with its own 3 s regen, frozen under ability lock like the primary;
# granted charged at purchase.
var bonus_dashes := 0
var bonus_dashes_max := 0
var bonus_cd := 0.0
# T-053 Updraft (D-T053-6): glider-only rise of 3.0 u
# on a re-pressed jump while gliding; apex exactly 3.0 u under gravity 32, once per
# glide engagement, 6 s cooldown frozen under ability lock like the dash. Granted
# (ready) ONLY by apply_updraft - the base glider has no updraft.
var updraft_ready := false
var updraft_cd := 0.0
var updraft_used := false
var updraft_owned := false

# void charges (D-050): charges carry over between levels (D-063).
var charges := 2
var charge_cap := 2
var last_light_spent := false

# safe-tile history ring (DESIGN section 3.1): entries {"x", "z", "y", "key"}.
var ring: Array = []
var cur_key := ""
var dwell := 0.0

# bookkeeping.
var prev_buttons := 0
var pad_flight := false
var facing_x := 0.0
var facing_z := 1.0
var dead := false
var dead_code := ""
var dead_killer := ""


func setup(kit_id: String, consts: Dictionary = {}) -> void:
	kit = kit_id if KITS.has(kit_id) else "dasher"
	C = DEFAULTS.duplicate()
	for k in C.keys():
		if consts.has(k):
			C[k] = consts[k]
	charges = int(C["void_charges"])
	charge_cap = int(C["charge_cap"])
	glide_energy = float(C["glide_energy"])


# Places the controller on the dais spawn tile of a world (feet on the tile top).
func place(w: Dictionary) -> void:
	var d: Array = w["dais"]
	x = float(d[0]) + 0.5
	y = float(d[2]) * 0.5
	z = float(d[1]) + 0.5
	vx = 0.0
	vy = 0.0
	vz = 0.0
	grounded = true
	cur_key = "%d,%d,%d" % [d[0], d[1], d[2]]


# True while class abilities are locked: an applied lock (D-070) or standing on
# glitched floor (D-051: abilities disabled while standing on it).
func ability_locked(w: Dictionary) -> bool:
	if lock > 0.0:
		return true
	return cur_key != "" and w["glitched"].has(cur_key)


# Run speed for the current tick (addendum R4, D-075, D-070, D-T012-3): class mult and
# upgrade pcts compose additively on base; under ability lock (or on glitched floor,
# D-051) the class mult is off and purchased upgrades work at normal strength; the
# glitched floor then applies its fixed x0.8 slow on top.
func run_speed(w: Dictionary) -> float:
	var ath := kit == "athletic" and not ability_locked(w)
	var glitched: bool = cur_key != "" and w["glitched"].has(cur_key)
	var class_mult := float(C["athletic_run_mult"]) if ath else 1.0
	var up: float = speed_base_add * (float(C["athletic_speed_upgrade_mult"]) if ath else 1.0)
	if glitched:
		return float(C["run_speed"]) * (1.0 + up) * 0.8
	return float(C["run_speed"]) * (class_mult + up)


func friction_mult(w: Dictionary) -> float:
	if cur_key != "" and (w["glitched"].has(cur_key) or w["slippery"].has(cur_key)):
		return 0.4
	return 1.0


# HUD Last Light icon state: "lit" while armed (unspent and charges >= 1),
# "dim" at 0 charges, "grey" once spent.
func hud_last_light() -> String:
	if last_light_spent:
		return "grey"
	return "lit" if charges >= 1 else "dim"


# One 60 Hz tick. Returns the events emitted by this tick.
func step(dt: float, a_in: Dictionary, w: Dictionary) -> Array:
	var ev: Array = []
	var was_dashing := dash_ticks > 0
	var buttons := int(a_in.get("buttons", 0))
	var jump_pressed := (buttons & BTN_JUMP) != 0 and (prev_buttons & BTN_JUMP) == 0
	var jump_released := (buttons & BTN_JUMP) == 0 and (prev_buttons & BTN_JUMP) != 0
	var ability_pressed := (buttons & BTN_ABILITY) != 0 and (prev_buttons & BTN_ABILITY) == 0

	if lock > 0.0:
		lock -= dt
		if lock < 0.0:
			lock = 0.0
	if invuln > 0.0:
		invuln -= dt
		if invuln < 0.0:
			invuln = 0.0
	# dash regeneration: time-based, 3 s (frozen under ability lock, D-070)
	if not dash_ready and lock <= 0.0:
		dash_cd -= dt
		dash_ready = dash_cd <= 0.0
	# T-053 Twin Dash (D-T053-5): the bonus stock regenerates on its own 3 s timer,
	# frozen under ability lock exactly like the primary.
	if bonus_dashes_max > 0 and bonus_dashes < bonus_dashes_max and lock <= 0.0:
		bonus_cd -= dt
		if bonus_cd <= 0.0:
			bonus_dashes += 1
			bonus_cd = 0.0
	# T-053 Updraft (D-T053-6): 6 s cooldown, frozen under ability lock. The
	# cooldown only ever runs on a GRANTED updraft (updraft_owned) - an unowned
	# controller (ready=false, cd=0) must not re-arm itself out of the regen math.
	if updraft_owned and not updraft_ready and lock <= 0.0:
		updraft_cd -= dt
		updraft_ready = updraft_cd <= 0.0

	if dead:
		prev_buttons = buttons
		return ev
	if respawn_t >= 0.0:
		_tick_respawn(dt, w, ev)
		prev_buttons = buttons
		return ev

	# ---- jump buffer / coyote -----------------------------------------------------
	if jump_pressed:
		buffer = float(C["jump_buffer"])
	if grounded:
		coyote = float(C["coyote_time"])
	elif coyote > 0.0:
		coyote = coyote - dt
	if buffer > 0.0:
		buffer = buffer - dt

	# ---- jump cut -----------------------------------------------------------------
	if jump_released and vy > 0.0:
		vy *= float(C["jump_cut"])

	# ---- dash (Dasher) ------------------------------------------------------------
	# T-053 Twin Dash (D-T053-5): primary charge first, then the bonus stock; the
	# consumed charge's own 3 s regen starts on consumption.
	if kit == "dasher" and ability_pressed and not ability_locked(w) \
			and (dash_ready or bonus_dashes > 0):
		var in_x := float(a_in.get("move_x", 0))
		var in_z := float(a_in.get("move_z", 0))
		var ax := float(a_in.get("aim_x", 0))
		var az := float(a_in.get("aim_z", 1))
		var dl: float
		var ddx: float
		var ddz: float
		if in_x != 0.0 or in_z != 0.0:
			dl = sqrt(in_x * in_x + in_z * in_z)
			ddx = in_x / dl
			ddz = in_z / dl
		else:
			dl = sqrt(ax * ax + az * az)
			if dl < 1e-9:
				ddx = 0.0
				ddz = 1.0
			else:
				ddx = ax / dl
				ddz = az / dl
		dash_dx = ddx
		dash_dz = ddz
		# an integer tick count, not a float timer: 0.20 s at 60 Hz is exactly 12 ticks,
		# so the dash span is exactly 6 u with no float residue
		dash_ticks = int(round(float(C["dash_time"]) * 60.0))
		if dash_ready:
			dash_ready = false
			dash_cd = float(C["dash_regen"])
		else:
			# Twin Dash's second stock (D-T053-5): its own 3 s regen begins here.
			bonus_dashes -= 1
			bonus_cd = float(C["dash_regen"])
		ev.append({"e": "dash_start"})

	# ---- jumps (ground, coyote, buffered on landing, air) ---------------------------
	var jump_v := float(C["jump_velocity"])
	if buffer > 0.0:
		var did_jump := false
		if grounded or coyote > 0.0:
			vy = jump_v
			did_jump = true
		elif air_jumps > 0 and not pad_flight:
			var hm: float = air_card_height
			if kit == "athletic" and not ability_locked(w):
				hm *= float(C["athletic_air_jump_mult"])
			vy = jump_v * hm
			air_jumps -= 1
			did_jump = true
		if did_jump:
			buffer = 0.0
			coyote = 0.0
			grounded = false
			gliding = false
			ev.append({"e": "jump"})

	# ---- glide engage (Glider) (the fall cap itself is applied after gravity) -------
	var was_gliding := gliding
	gliding = false
	if kit == "glider" and (buttons & BTN_JUMP) != 0 and not grounded and vy < 0.0 \
			and glide_energy > 0.0 and not ability_locked(w) and not pad_flight \
			and dash_ticks <= 0:
		gliding = true
		if not was_gliding:
			updraft_used = false   # once per glide ENGAGEMENT (D-T053-6)
		var h_spd: float = sqrt(vx * vx + vz * vz)
		var cap := float(C["glide_speed"])
		if h_spd > cap:
			var sc: float = cap / h_spd
			vx *= sc
			vz *= sc
	if gliding:
		glide_energy -= dt
		if glide_energy < 0.0:
			glide_energy = 0.0

	# ---- updraft (Glider, T-053, D-T053-6) -----------------------------------------
	# A re-pressed jump while gliding rises exactly 3.0 u: vy = sqrt(2 x g x 3 u)
	# under gravity 32 (apex = vy^2 / (2 g) = 3.0 u), ends the glide, once per
	# glide engagement, 6 s cooldown frozen under ability lock like the dash (D-070).
	if gliding and jump_pressed and kit == "glider" and updraft_ready \
			and not updraft_used and not ability_locked(w):
		# + gravity x dt: gravity runs after this block, so the step's EXIT vy is
		# the exact apex velocity and the rise is exactly 3.0 u (D-T053-6).
		vy = UPDRAFT_VY + float(C["gravity"]) * dt
		gliding = false
		updraft_used = true
		updraft_ready = false
		updraft_cd = UPDRAFT_CD
		ev.append({"e": "updraft"})

	# ---- horizontal acceleration (addendum R4) --------------------------------------
	var dashing_move := false
	if dash_ticks > 0:
		var ds: float = float(C["dash_distance"]) / float(C["dash_time"])
		vx = dash_dx * ds
		vz = dash_dz * ds
		vy = 0.0
		dash_ticks -= 1
		dashing_move = true
	elif gliding:
		# glide target speed is glide_speed in the input direction; no input coasts
		var mx := float(a_in.get("move_x", 0))
		var mz := float(a_in.get("move_z", 0))
		var dir_len: float = sqrt(mx * mx + mz * mz)
		var tvx2 := vx
		var tvz2 := vz
		if dir_len > 0.0:
			tvx2 = (mx / dir_len) * float(C["glide_speed"])
			tvz2 = (mz / dir_len) * float(C["glide_speed"])
		var dvx2 := tvx2 - vx
		var dvz2 := tvz2 - vz
		var dlen2: float = sqrt(dvx2 * dvx2 + dvz2 * dvz2)
		if dlen2 > 1e-9:
			var sc3: float = dlen2
			var want2: float = float(C["accel"]) * friction_mult(w) * dt
			if want2 < sc3:
				sc3 = want2
			var f3: float = sc3 / dlen2
			vx += dvx2 * f3
			vz += dvz2 * f3
	elif not pad_flight:
		var mx: float = float(a_in.get("move_x", 0))
		var mz: float = float(a_in.get("move_z", 0))
		var dir_len: float = sqrt(mx * mx + mz * mz)
		var tvx := 0.0
		var tvz := 0.0
		if dir_len > 0.0:
			var spd := run_speed(w)
			tvx = (mx / dir_len) * spd
			tvz = (mz / dir_len) * spd
			facing_x = mx / dir_len
			facing_z = mz / dir_len
		var dvx := tvx - vx
		var dvz := tvz - vz
		var dlen: float = sqrt(dvx * dvx + dvz * dvz)
		if dlen > 1e-9:
			var sc2: float = dlen
			var want: float = float(C["accel"]) * friction_mult(w) * dt
			if want < sc2:
				sc2 = want
			var f: float = sc2 / dlen
			vx += dvx * f
			vz += dvz * f

	# ---- gravity --------------------------------------------------------------------
	if not dashing_move:
		vy -= float(C["gravity"]) * dt
		var tf := float(C["terminal_fall"])
		if vy < -tf:
			vy = -tf
	if gliding and vy < -float(C["glide_fall_cap"]):
		vy = -float(C["glide_fall_cap"])

	# ---- move + collide (D-047) -----------------------------------------------------
	var ox := x
	var oz := z
	var oy := y
	var was_g := grounded
	var r: Dictionary = CollisionScript.move_body(w, x, y, z, vx * dt, vy * dt, vz * dt,
			float(C["height"]), float(C["step_up"]), was_g)
	x = r["x"]
	y = r["y"]
	z = r["z"]
	if absf(x - ox - vx * dt) > 1e-6:
		vx = 0.0
		if dash_ticks > 0:
			dash_ticks = 0
	if absf(z - oz - vz * dt) > 1e-6:
		vz = 0.0
		if dash_ticks > 0:
			dash_ticks = 0
	if was_dashing and dash_ticks == 0:
		# the dash span is exactly 6 u over 12 ticks; control resumes from 0 after it
		vx = 0.0
		vz = 0.0
	if r["hit_ceiling"] and vy > 0.0:
		vy = 0.0
	grounded = r["grounded"]
	if grounded and not was_g:
		glide_energy = float(C["glide_energy"])
		air_jumps = air_jumps_max
		pad_flight = false
		ev.append({"e": "land"})
	if grounded:
		vy = 0.0
		if buffer > 0.0:
			vy = float(C["jump_velocity"])
			buffer = 0.0
			ev.append({"e": "jump"})

	# T-081 step-up counter (D-T081-1): ground height GAINED while WALKING (grounded
	# contact on both sides of the move) of at least 1 HU = 0.5 u - the tread-then-step
	# stairs the shape contract produces. A jump, a landing from the air, a ramp's slope
	# (0.5 u per 1 u horizontal = 0.075 u per tick at run speed) and a launch pad never
	# reach 1 HU in one tick, so no guard against them is needed.
	if was_g and grounded:
		var rise: float = y - oy
		if rise >= 0.5 - 1e-4 and absf(x - ox) + absf(z - oz) > 0.01:
			ev.append({"e": "step_up", "hu": int(round(rise * 2.0))})

	# ---- launch pads (TERRAIN_SPEC section 4) ---------------------------------------
	if grounded and not pad_flight:
		_try_launch_pad(w, ev)

	# ---- void fall (DESIGN section 3.1, D-050, D-053) -------------------------------
	if y < float(C["kill_plane_y"]):
		_void_fall(w, ev)
		prev_buttons = buttons
		return ev

	# ---- safe-tile history ring ------------------------------------------------------
	_track_ring(dt, w, ev)
	prev_buttons = buttons
	return ev


# ---- launch pads: ballistic throw onto the pad's target tile -----------------------

func _try_launch_pad(w: Dictionary, ev: Array) -> void:
	var key: String = "%d,%d" % [int(floor(x)), int(floor(z))]
	var pad: Dictionary = w["pads"].get(key, {})
	if pad.is_empty():
		return
	var dy: float = (float(pad["ty"]) - float(y) * 2.0) * 0.5
	# solve y(t) = v0 t - 16 t^2 = dy on the descending branch (v0 = pad_launch_vel, g = 32)
	var v0 := float(C["pad_launch_vel"])
	var disc: float = v0 * v0 - 64.0 * dy
	if disc < 0.0:
		disc = 0.0
	var t2: float = (v0 + sqrt(disc)) / 32.0
	if t2 <= 0.0:
		t2 = 0.0001
	vx = (float(pad["tx"]) + 0.5 - x) / t2
	vz = (float(pad["tz"]) + 0.5 - z) / t2
	vy = v0
	grounded = false
	pad_flight = true
	gliding = false
	ev.append({"e": "pad_launch"})


# ---- void fall / respawn (D-050, D-053, D-043) --------------------------------------

func _void_fall(w: Dictionary, ev: Array) -> void:
	if charges >= 1:
		var before := charges
		charges -= 1
		respawn_t = float(C["respawn_delay"])
		vx = 0.0
		vy = 0.0
		vz = 0.0
		gliding = false
		dash_ticks = 0
		# T-080 telemetry payload: the tile the player last stood on, the nearest enemy
		# body at the fall, and the before/after charge counts (the log's charge_spent
		# record derives free from them; Field Dressing is not wired into this path yet).
		ev.append({"e": "void_fall", "charges": charges, "charges_before": before,
				"tile": cur_key, "nearest_enemy_dist": _nearest_enemy_dist(w)})
		ev.append({"e": "chain_reset", "why": "void_fall"})
	else:
		var dd: Dictionary = _die("D-VOID", "void", ev)
		# a void fall is its own killer (D-VOID): no enemy body was ever on screen
		dd["on_screen"] = false


func _tick_respawn(dt: float, w: Dictionary, ev: Array) -> void:
	respawn_t -= dt
	if respawn_t > 0.0:
		return
	respawn_t = -1.0
	var picked: Variant = null
	for k in range(ring.size() - 1, -1, -1):
		if valid_safe_tile(w, ring[k]):
			picked = ring[k]
			break
	if picked == null:
		var d: Array = w["dais"]
		picked = {"x": d[0], "z": d[1], "y": d[2]}
	x = float(picked["x"]) + 0.5
	y = float(picked["y"]) * 0.5
	z = float(picked["z"]) + 0.5
	vx = 0.0
	vy = 0.0
	vz = 0.0
	grounded = true
	pad_flight = false
	gliding = false
	glide_energy = float(C["glide_energy"])
	air_jumps = air_jumps_max
	invuln = float(C["respawn_invuln"])
	cur_key = "%d,%d,%d" % [int(picked["x"]), int(picked["z"]), int(picked["y"])]
	dwell = 0.0
	ev.append({"e": "respawn", "tile": cur_key, "charges": charges})


# Safe tile (D-059): the tile still exists (and was not removed), is not glitched,
# is outside every hazard footprint, and is at least safe_enemy_dist (6 u) from every
# enemy body and projectile. Distances are 3D from the tile's top centre.
func valid_safe_tile(w: Dictionary, t: Dictionary) -> bool:
	var tx: int = int(t["x"])
	var tz: int = int(t["z"])
	var ty: int = int(t["y"])
	if not CollisionScript.tile_alive(w, tx, tz, ty):
		return false
	var key: String = "%d,%d,%d" % [tx, tz, ty]
	if w["glitched"].has(key):
		return false
	var px: float = float(tx) + 0.5
	var py: float = float(ty) * 0.5
	var pz: float = float(tz) + 0.5
	if _in_any_hazard(w["hazards"], px, py, pz):
		return false
	var lim := float(C["safe_enemy_dist"])
	for e in w["enemies"]:
		var dx: float = float(e["x"]) - px
		var dyy: float = float(e["y"]) - py
		var dz: float = float(e["z"]) - pz
		if dx * dx + dyy * dyy + dz * dz < lim * lim:
			return false
	for p in w["projectiles"]:
		var dx2: float = float(p["x"]) - px
		var dyy2: float = float(p["y"]) - py
		var dz2: float = float(p["z"]) - pz
		if dx2 * dx2 + dyy2 * dyy2 + dz2 * dz2 < lim * lim:
			return false
	return true


# True when the point is inside one hazard footprint (circle / ring / box, each an
# optional y band in world u). Hazard shapes come from the enemy runtime's live state.
static func _in_any_hazard(hazards: Array, px: float, py: float, pz: float) -> bool:
	for hz in hazards:
		var y0: float = float(hz.get("y0", -INF))
		var y1: float = float(hz.get("y1", INF))
		if py < y0 - 1e-9 or py > y1 + 1e-9:
			continue
		var inside := false
		var shape: String = hz.get("shape", "circle")
		if shape == "circle":
			var dx: float = px - float(hz["cx"])
			var dz: float = pz - float(hz["cz"])
			inside = dx * dx + dz * dz <= float(hz["r"]) * float(hz["r"])
		elif shape == "ring":
			var dxr: float = px - float(hz["cx"])
			var dzr: float = pz - float(hz["cz"])
			var d2: float = dxr * dxr + dzr * dzr
			var r0: float = float(hz["r0"])
			var r1: float = float(hz["r1"])
			inside = d2 >= r0 * r0 - 1e-9 and d2 <= r1 * r1 + 1e-9
		elif shape == "box":
			inside = px >= float(hz["x0"]) - 1e-9 and px <= float(hz["x1"]) + 1e-9 \
					and pz >= float(hz["z0"]) - 1e-9 and pz <= float(hz["z1"]) + 1e-9
		if inside:
			return true
	return false


# ---- safe-tile history ring ---------------------------------------------------------

func _track_ring(dt: float, w: Dictionary, _ev: Array) -> void:
	if not grounded:
		return
	var sup: Dictionary = CollisionScript.support_at(w, x, z, y, CollisionScript.SKIN, true)
	if sup["tile"] == null:
		return
	var key: String = "%d,%d,%d" % [int(sup["cx"]), int(sup["cz"]), int(sup["tile"]["y"])]
	if key != cur_key:
		cur_key = key
		dwell = 0.0
	dwell += dt
	if dwell < float(C["safe_dwell"]):
		return
	for t in ring:
		if t["key"] == key:
			return
	ring.append({"x": int(sup["cx"]), "z": int(sup["cz"]),
			"y": int(sup["tile"]["y"]), "key": key})
	if ring.size() > int(C["safe_ring_size"]):
		ring.pop_front()

# ---- kills, Last Light, beacon (D-050, D-053, D-057, D-063, D-073) ------------------

# A killing blow lands (enemy, tripmine or nuke — never a void fall, which the step
# handles itself). Returns true when Last Light saved the player. Respawn
# invulnerability and Last Light invulnerability suppress kills without spending it.
# The save teleports to the beacon dais and pushes enemy bodies out to exactly 8 u
# (D-073), mutating w["enemies"] in place.
func try_kill(code: String, killer: String, w: Dictionary, ev: Array = []) -> bool:
	if dead or respawn_t >= 0.0:
		return false
	if invuln > 0.0:
		ev.append({"e": "kill_suppressed", "code": code, "killer": killer})
		return false
	if not last_light_spent and charges >= 1:
		last_light_spent = true
		var d: Array = w["dais"]
		x = float(d[0]) + 0.5
		y = float(d[2]) * 0.5
		z = float(d[1]) + 0.5
		vx = 0.0
		vy = 0.0
		vz = 0.0
		grounded = true
		pad_flight = false
		gliding = false
		dash_ticks = 0
		invuln = float(C["last_light_invuln"])
		cur_key = "%d,%d,%d" % [int(d[0]), int(d[1]), int(d[2])]
		dwell = 0.0
		push_enemy_bodies(w["enemies"], [x, y, z])
		ev.append({"e": "last_light_save", "code": code, "killer": killer,
				"charges": charges})
		return true
	_die(code, killer, ev)
	return false


# The arrival push (D-073): every enemy body within 8 u of the dais centre is pushed
# radially out (XZ) to exactly 8 u; y untouched; no kill, no behavior change.
static func push_enemy_bodies(enemies: Array, dais_center: Array) -> void:
	var rad: float = 8.0
	for e in enemies:
		var dx: float = float(e["x"]) - float(dais_center[0])
		var dz: float = float(e["z"]) - float(dais_center[2])
		var d: float = sqrt(dx * dx + dz * dz)
		if d < rad:
			if d < 1e-9:
				e["x"] = float(dais_center[0]) + rad
				e["z"] = float(dais_center[2])
			else:
				e["x"] = float(dais_center[0]) + dx / d * rad
				e["z"] = float(dais_center[2]) + dz / d * rad


func _die(code: String, killer: String, ev: Array) -> Dictionary:
	dead = true
	dead_code = code
	dead_killer = killer
	# T-080 telemetry payload on every death: charges held and the Last Light state
	# (hud_last_light: lit / dim / grey). on_screen is set by the killer's own layer
	# (enemy_runtime / mines / the void fall above) or defaults in the log.
	var evd := {"e": "death", "code": code, "killer": killer,
			"charges": charges, "last_light": hud_last_light()}
	ev.append(evd)
	return evd


# T-080: nearest enemy body (the world mirror's rows) from the player's centre
# (feet + 0.9 u), 3D; -1.0 when no bodies exist.
func _nearest_enemy_dist(w: Dictionary) -> float:
	var best := -1.0
	for e in w["enemies"]:
		var dx: float = float(e["x"]) - x
		var dy: float = float(e["y"]) - (y + 0.9)
		var dz: float = float(e["z"]) - z
		var d: float = sqrt(dx * dx + dy * dy + dz * dz)
		if best < 0.0 or d < best:
			best = d
	return best


# Beacon entry (DESIGN.md section 3.1): restores exactly 1 charge, capped. The caller
# checks the beacon's OPEN state and the 1.5 u trigger radius; charges never reset here.
func beacon_enter(ev: Array = []) -> bool:
	if charges < charge_cap:
		charges += 1
		ev.append({"e": "beacon_enter", "charges": charges})
		return true
	return false


# ---- upgrade plumbing (until the content layer's stat hooks exist, T-013) -----------

# One speed upgrade purchase of base strength pct (0.05 = +5%). Strength composition
# (D-T012-3): run = base * (class_mult + raw pcts), Athletic cards counted x1.5 while
# its class mult is active; on glitched floor the class mult is off (D-051) and the
# raw pcts remain.
func apply_speed_upgrade(pct: float) -> void:
	speed_base_add += pct


# One double-jump upgrade: +1 air jump; air-jump velocity = jump_velocity *
# card_height (*1.3 more on Athletic while not locked, D-070).
func apply_double_jump(card_height: float = 1.0) -> void:
	air_jumps_max += 1
	air_jumps = air_jumps_max
	air_card_height = card_height


# T-053 Twin Dash (D-T053-5): the second dash stock, granted charged (usable on
# the next ability press); its 3 s regen runs from each consumption.
func apply_twin_dash() -> void:
	bonus_dashes_max = 1
	bonus_dashes = 1
	bonus_cd = 0.0


# T-053 Updraft (D-T053-6): the 3 u rise is granted ready; once per glide.
func apply_updraft() -> void:
	updraft_owned = true
	updraft_ready = true
	updraft_cd = 0.0
	updraft_used = false


# Ability lock (D-070, SR-6): the toucher's floor and coil's shockwave call this.
func apply_lock(duration: float) -> void:
	if duration > lock:
		lock = duration


# ---- the lock's per-class effect list (T-072: read from data, never invented here) ----

# Effect-vocabulary fallback for a lock applied with no data file present (or a block
# a future schema change removed): the full SR-6 reading, per class. data/player.json
# (ability_lock.lock_effect) wins for every key it carries.
const LOCK_EFFECT_FALLBACK := {
	"dasher": ["dash_disabled"],
	"glider": ["glide_disabled"],
	"athletic": ["class_multipliers_off"],
}


# The lock's per-class effect names, from data/player.json (ability_lock.lock_effect):
# dash_disabled / glide_disabled / class_multipliers_off. An empty or missing read falls
# back to LOCK_EFFECT_FALLBACK, so a lock can never be a silent no-op.
static func lock_effects(kit_id: String) -> Array:
	var f := FileAccess.open("res://data/player.json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			var al: Dictionary = (parsed as Dictionary).get("ability_lock", {})
			var le: Dictionary = al.get("lock_effect", {})
			var v: Variant = le.get(kit_id, null)
			if v is Array and not (v as Array).is_empty():
				return v
	return LOCK_EFFECT_FALLBACK.get(kit_id, [])


# One ability lock from an enemy (the Arbiter's Api.lock_abilities caller; whole 60 Hz
# ticks - the window runs for ticks / 60 s). Which class abilities the lock disables
# comes from data/player.json via lock_effects: the dash start and its cooldown tick are
# gated by step() and the regen branch while lock > 0; the glide engage by the same gate;
# the class multipliers by run_speed() and the air-jump height - all read
# ability_locked() every tick.
func lock_abilities(ticks: int) -> void:
	apply_lock(float(maxi(int(ticks), 0)) / 60.0)
	var eff: Array = lock_effects(kit)
	if eff.has("glide_disabled"):
		gliding = false   # an active glide ends when the lock lands


# Hungry Void (D-052): charge cap becomes 1. Held charges above the new cap are lost
# so the HUD pip count stays exact.
func set_charge_cap(cap: int) -> void:
	charge_cap = cap
	if charges > cap:
		charges = cap

