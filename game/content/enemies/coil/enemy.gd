#
# coil behavior module (ticket T-031). ENEMIES.md § 🌀 Springer → coil is the spec
# (D-040); DESIGN.md §5.2 carries the numbers; the T-083 anim block in
# sprites.json pins the tick timings (they are binding). Lives under content/ so the sim
# core stays enemy-agnostic; it changes the world only through the §12 enemy API (and
# reads its own placed row); nothing here touches nodes, autoloads or globals.
#
# Cycle (DESIGN.md §5.2): idle 3.0 s → pre-jump cue 0.6 s ("boing", squash frames, a red
# ring of radius 3 u drawn at the landing zone) → arc flight 2.75 s → landing.
# The landing zone is the player's LAST GROUNDED TILE when the cue starts (D-064 item 3):
# never a mid-air position over the void, never a predicted position, never updated after
# the cue starts. Landing on a player (within 1.2 u) = kill, code D-COIL. Landing
# shockwave: radius 6 u, pushes outward at 8 u/s decaying linearly to 0 over 0.5 s
# (~2.0 u of travel, D-066), does not kill, locks class abilities for 2.0 s (SR-6).
# A jump timed so the player is airborne at landing avoids the shockwave (D-T-031-3).
# The shove is one of only three things that spend/consume nothing the player holds - see
# "void charge": coil never touches void charges; its shove is velocity + a lock window.
#
# The body is hurdle-able while idle (1.0 u squashed, SR-2) and 2.0 u extended in flight.
# Body contact kills at every stage (the KILL RULE); the landing kill is the spec's own
# 1.2 u circle (D-T-031-4).
#
# Copies stagger their first cue by CYCLE/n (D-T-031-9); copies spawn >= 30 u apart
# (SR-3, D-056, unchanged). The landing-ring telegraph is the row's own entry, aged by the
# behavior (D-T072-4), kind "coil_ring", circle r = 3.0 with a y band on the landing
# plane so address me's no_targeted_telegraph gate reads it correctly (D-T-031-5).

const RT := preload("res://sim/enemy_runtime.gd")

# Timings (DESIGN.md §5.2 / the T-083 anim block; DESIGN.md §5.2 wins on disagreement).
const TICKS_PER_SECOND := 60
const IDLE_TICKS := 180        # 3.0 s
const CUE_TICKS := 36          # 0.6 s
const FLIGHT_TICKS := 165      # 2.75 s
const RECOVER_TICKS := 24      # the anim block's recover state
const SPAWN_TICKS := 30        # the anim block's spawn (common fade)
const CYCLE_TICKS := IDLE_TICKS + CUE_TICKS + FLIGHT_TICKS + RECOVER_TICKS   # 405
# DESIGN.md §5.2 numbers.
const KILL_RADIUS := 1.2       # landing on a player within 1.2 u = kill
const SHOCK_RADIUS := 6.0      # landing shockwave radius
const SHOCK_PUSH := 8.0        # u/s, decaying linearly to 0 over 0.5 s
const SHOCK_TICKS := 30        # 0.5 s decay window
const LOCK_TICKS := 120        # 2.0 s class-ability lock (SR-6)
const RING_RADIUS := 3.0       # the telegraph ring drawn at the landing zone
const APEX_U := 4.0            # arc apex above the chord (D-T-031-2, [CONTESTABLE])
const GROUND_EPS := 0.05       # feet-vs-tile-top match for the last-grounded-tile probe
const PLANE_EPS := 0.5         # 1 HU y band for "on the landing plane" (D-T-031-3)
const HALF_HU := 0.25


## A factory for the loader (T-073): returns a fresh behavior instance.
static func behavior() -> RefCounted:
	return CoilBehavior.new()


## The behavior itself: an EnemyBehavior subclass living in this file (the runtime's
## sanctioned content shape). Rows are plain dictionaries; this touches its own row only
## (plus aging its own telegraph entries, D-T072-4).
class CoilBehavior:
	extends RT.EnemyBehavior

	func on_spawn(row: Dictionary, api) -> void:
		# SR-2, D-T-031-7: pin the FINAL hitbox numbers on the row (the T-016 TBD
		# placeholder body_rect derives 1.6 u at 1.0 u height; the spec says 0.9).
		row["diameter_u"] = 0.9
		row["height_u"] = 1.0     # spawn pose is squashed
		row["state"] = "spawn"
		row["seg_left"] = SPAWN_TICKS
		row["flight_i"] = 0
		row["land_locked"] = false
		row["shock"] = null
		# SR-3 (D-T-031-9): copy k of n starts CYCLE k/n into its cycle; its first cue is
		# staggered so copies fire every CYCLE/n instead of as one blob. A copy that would
		# start inside a cue/flight segment instead starts pre-idle and waits longer -
		# never mid-telegraph.
		var copies: int = int(row.get("copies", 1))
		var copy_index: int = int(row.get("copy_index", 0))
		var phase: float = RT.stack_phase(float(CYCLE_TICKS), copy_index, copies)
		row["first_cue_extra"] = int(round(float(CYCLE_TICKS) - phase)) if phase > 0.0 else 0
		# The last grounded tile probe starts from the spawn position (D-064 item 3).
		var near: Dictionary = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
		if not near.is_empty():
			row["last_ground"] = {"x": floorf(float(near["x"])) + 0.5, "y": float(near["y"]),
					"z": floorf(float(near["z"])) + 0.5}
		else:
			row["last_ground"] = {"x": float(row["x"]), "y": float(row["y"]), "z": float(row["z"])}

	func tick(row: Dictionary, api, dt_ticks: int) -> void:
		_track_ground(row, api)
		_tick_shock(row, api, dt_ticks)
		_age_rings(row, api, dt_ticks)   # aging runs before the state machine: a ring born at the cue
		if dt_ticks <= 0:                     # expires exactly at the landing tick (D-T072-4)
			return
		var state: String = str(row.get("state", "idle"))
		match state:
			"spawn":
				row["seg_left"] = int(row["seg_left"]) - dt_ticks
				if int(row["seg_left"]) <= 0:
					_enter_idle(row, api, true)
			"idle":
				row["seg_left"] = int(row["seg_left"]) - dt_ticks
				if int(row["seg_left"]) <= 0:
					_begin_cue(row, api)
			"cue":
				row["seg_left"] = int(row["seg_left"]) - dt_ticks
				if int(row["seg_left"]) <= 0:
					_begin_flight(row)
			"flight":
				_tick_flight(row, api, dt_ticks)
			"recover":
				row["seg_left"] = int(row["seg_left"]) - dt_ticks
				if int(row["seg_left"]) <= 0:
					_enter_idle(row, api, false)
			_:
				_enter_idle(row, api, false)

	# --- the last-grounded-tile probe (D-064 item 3, within the §12 API) -------------
	# nearest_player carries no grounded flag, so the behavior derives "standing on a
	# tile" from the feet height matching a nearby tile slab's top. While airborne, or
	# over the void, the stored tile is kept unchanged - mid-air y never becomes the
	# landing zone.
	func _track_ground(row: Dictionary, api) -> void:
		var near: Dictionary = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
		if near.is_empty():
			return
		var px: float = float(near["x"])
		var py: float = float(near["y"])
		var pz: float = float(near["z"])
		var feet := Vector3(px, py, pz)
		var best: Variant = null
		var best_d := 1e30
		for t in api.tiles_in_radius(feet, 1.5):
			var td: float = float(t["y"]) - py
			if td < -GROUND_EPS or td > GROUND_EPS:
				continue
			var d: float = sqrt(pow(float(t["x"]) - px, 2.0) + pow(float(t["z"]) - pz, 2.0))
			if d < best_d:
				best_d = d
				best = t
		if best != null:
			row["last_ground"] = {"x": float(best["x"]), "y": float(best["y"]), "z": float(best["z"])}

	# --- aging this row's coil_ring entries (D-T072-4: entry lifetime is the caller's) -
	func _age_rings(row: Dictionary, api, dt_ticks: int) -> void:
		var id := str(row.get("id", ""))
		for t in api.rt.telegraphs:
			if str(t.get("kind", "")) == "coil_ring" and str(t.get("source", "")) == id:
				t["ticks"] = maxi(int(t.get("ticks", 0)) - dt_ticks, 0)

	# --- the landing shockwave (D-T-031-11): linear decay applied per tick -----------
	func _tick_shock(row: Dictionary, api, dt_ticks: int) -> void:
		var shock: Variant = row.get("shock", null)
		if shock == null or not (shock is Dictionary):
			return
		var left: int = int(shock.get("ticks", 0))
		if left <= 0:
			row["shock"] = null
			return
		var idx: int = int(shock.get("index", 0))
		var dir: Vector3 = shock.get("dir", Vector3(0.0, 0.0, 1.0))
		for _i in range(maxi(dt_ticks, 0)):
			if left <= 0:
				break
			var speed: float = SHOCK_PUSH * float(left) / float(SHOCK_TICKS)
			api.push(idx, dir, speed)
			left -= 1
		if left <= 0:
			row["shock"] = null
		else:
			shock["ticks"] = left
			row["shock"] = shock

	# --- state machine helpers ---------------------------------------------------------
	func _enter_idle(row: Dictionary, _api, _first: bool) -> void:
		row["state"] = "idle"
		row["height_u"] = 1.0     # hurdle-able while idle (SR-2)
		# idle length is data (idle_s) so Overwound can shorten it without a behavior
		# edit (D-T-031-12); the first idle carries the SR-3 copy stagger.
		var idle_ticks: int = int(round(float(row.get("cfg", {}).get("idle_s", 3.0)) * float(TICKS_PER_SECOND)))
		var extra: int = int(row.get("first_cue_extra", 0)) if _first else 0
		row["seg_left"] = maxi(idle_ticks + extra, 1)

	func _begin_cue(row: Dictionary, api) -> void:
		row["state"] = "cue"
		row["seg_left"] = CUE_TICKS
		# D-064 item 3: the landing zone is the player's last grounded tile at cue
		# start - never a mid-air position over the void, never a predicted position.
		var zone: Dictionary = row.get("last_ground", {"x": float(row["x"]), "y": float(row["y"]), "z": float(row["z"])})
		row["land_x"] = float(zone["x"])
		row["land_y"] = float(zone["y"])
		row["land_z"] = float(zone["z"])
		row["land_locked"] = true
		# the red ring (radius 3 u), visible for the whole cue and the flight; the y
		# band pins it to the landing plane for address me's gate (D-T-031-5).
		api.telegraph("coil_ring", {"shape": "circle", "cx": row["land_x"], "cz": row["land_z"],
				"r": RING_RADIUS, "y0": row["land_y"], "y1": row["land_y"]}, CUE_TICKS + FLIGHT_TICKS)
		# the boing (the New sound line: classic spring boing before every jump)
		api.rt.events.append({"e": "audio", "cue": "coil_boing",
				"x": float(row["x"]), "y": float(row["y"]), "z": float(row["z"]),
				"tick": int(api.rt.tick)})

	func _begin_flight(row: Dictionary) -> void:
		row["state"] = "flight"
		row["flight_i"] = 0
		row["height_u"] = 2.0      # extended at the apex (SR-2)
		row["from_x"] = float(row["x"])
		row["from_y"] = float(row["y"])
		row["from_z"] = float(row["z"])

	func _tick_flight(row: Dictionary, api, dt_ticks: int) -> void:
		row["flight_i"] = int(row["flight_i"]) + dt_ticks
		var t: float = clampf(float(row["flight_i"]) / float(FLIGHT_TICKS), 0.0, 1.0)
		var fx: float = float(row["from_x"])
		var fz: float = float(row["from_z"])
		var fy: float = float(row["from_y"])
		var lx: float = float(row["land_x"])
		var lz: float = float(row["land_z"])
		var ly: float = float(row["land_y"])
		row["x"] = fx + (lx - fx) * t
		row["z"] = fz + (lz - fz) * t
		# parabolic arc: chord lerp + 4*APEX*t*(1-t); APEX 4.0 u (D-T-031-2)
		row["y"] = fy + (ly - fy) * t + 4.0 * APEX_U * t * (1.0 - t)
		if int(row["flight_i"]) >= FLIGHT_TICKS:
			_land(row, api)

	# --- the landing tick ---------------------------------------------------------------
	func _land(row: Dictionary, api) -> void:
		var lx: float = float(row["land_x"])
		var ly: float = float(row["land_y"])
		var lz: float = float(row["land_z"])
		# snap to the locked zone exactly
		row["x"] = lx
		row["y"] = ly
		row["z"] = lz
		row["height_u"] = 1.0   # compressed on landing (coil_00)
		# the landing is the instant reposition the mirror has to follow (PARKED row 27):
		# no_enemy_body_within and the D-059 safe tile read world["enemies"], which still
		# holds the spawn point. Synced at the settle, not on the flight's interpolated
		# ticks - those are a mover's lagging snapshot, the landing is the new home.
		api.sync_body()
		row["state"] = "recover"
		row["seg_left"] = RECOVER_TICKS
		# resolve against the targeted player (D-T-031-10): horizontal circle 1.2 u, no y
		# band (D-T-031-4); else the 6 u shockwave for feet on the landing plane (D-T-031-3).
		var near: Dictionary = api.nearest_player(Vector3(lx, ly, lz))
		if not near.is_empty():
			var px: float = float(near["x"])
			var py: float = float(near["y"])
			var pz: float = float(near["z"])
			var dx: float = px - lx
			var dz: float = pz - lz
			var d: float = sqrt(dx * dx + dz * dz)
			if d <= KILL_RADIUS:
				api.kill(int(near["index"]), "coil")
			elif d <= SHOCK_RADIUS and absf(py - ly) <= PLANE_EPS:
				var dir := Vector3(dx, 0.0, dz)
				if dir.length() < 1e-9:
					dir = Vector3(0.0, 0.0, 1.0)
				else:
					dir = dir.normalized()
				row["shock"] = {"ticks": SHOCK_TICKS, "dir": dir, "index": int(near["index"])}
				api.lock_abilities(int(near["index"]), LOCK_TICKS)
		# the metallic twang (the New sound line) + the view's shockwave marker
		api.rt.events.append({"e": "coil_land", "cue": "coil_landing_twang",
				"x": lx, "y": ly, "z": lz, "tick": int(api.rt.tick)})
