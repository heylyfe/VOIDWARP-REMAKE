extends RefCounted
#
# toucher behavior module (ticket T-037). ENEMIES.md section "Flesh -> toucher" is the
# spec (D-040), DESIGN.md section 5.8 carries the numbers (binding, tests assert within
# +/-1 tick), section 12 is the API contract, and the T-083 anim block in sprites.json
# pins the state timings. Lives under content/ so the sim core stays enemy-agnostic; it
# changes the world only through the section 12 enemy API (plus the two world maps other
# behaviors already reach through api.rt: telegraphs (coil) and events (coil) - the
# glitched-tile map is this enemy's own live state surface, written so the controller
# (D-051 slow + ability lock) and thicc ben's ring cleanse (T-032, api
# cleanse_glitched_within) both read the SAME state. That shared map is the "the two
# agree on what a glitched tile is" contract: keys are collision.gd's tile_key
# "x,z,y_hu" strings, values true.
#
# Numbers (DESIGN.md section 5.8):
#   - floats toward the nearest player at 6.75 u/s (pursuit ceiling 0.75 of BASE run
#     speed 9.0 = 6.75 u/s - its own base speed, so no multiplier ever speeds it up);
#     feet ease at 2.0 u/s, never multiplied (SR-1, FloatBody);
#   - touch = kill (the framework's body-contact pass; contact_kill true);
#   - every 2.0 s (120 ticks; tempo conversion binds at 1.2 s = 72 ticks, SR-5) it
#     infects all tiles within 3 u below it - a squelch cue whenever new tiles appear;
#   - glitched tile: lasts 12 s (720 ticks; 18 s = 1080 ticks from level 14);
#   - standing on it does NOT kill: the -20% run speed and the ability lock are the
#     controller's D-051 handling of world["glitched"] - this module only writes/ages
#     the keys and never kills through them;
#   - max 60 glitched tiles per toucher;
#   - thicc ben's ring cleanses glitched tiles within 8 u (T-032) - the behavior drops
#     cleansed keys from its own list so the cap stays honest;
#   - finger: 3 flicker frames (cycle anim, 10 fps); glitch pulse telegraph 18 ticks
#     before each infection; attack_infect is the infection tick itself - NO duration
#     is invented for it (the anim block records it as "on the infection tick").
#
# Decisions and readings: DECISIONS.md D-T-037-1..N.

const RT := preload("res://sim/enemy_runtime.gd")

# ---- DESIGN.md 5.8 numbers (binding; enemy.json stats mirror these) ------------
const INFECT_INTERVAL_TICKS := 120   # 2.0 s
const INFECT_RADIUS := 3.0           # tiles within 3 u below it
const MAX_GLITCHED_TILES := 60       # per toucher
const TELEGRAPH_TICKS := 18          # the glitch pulse before each infection
const TILE_LIFE_TICKS := 720         # 12 s
const TILE_LIFE_TICKS_L14 := 1080    # 18 s from level 14
const SPAWN_FADE_TICKS := 30         # the T-083 spawn row (common fade)
const DEATH_CODE := "D-TOUCH"        # DESIGN.md 3.1's closed death-code list
const ELEV_EPS := 1e-6               # "below it": tile top strictly under the feet

const TILE_LIFE_LEVEL := 14          # 18 s life from level 14 on (cfg level_number)
const TELEGRAPH_KIND := "toucher_pulse"
const SQUELCH_CUE := "toucher_squelch"

# A factory for the loader (T-073): returns a fresh behavior instance.
static func behavior() -> RefCounted:
	return ToucherBehavior.new()


## The behavior itself: an EnemyBehavior subclass living in this file (the runtime's
## sanctioned content shape). Rows are plain dictionaries; this touches its own row
## only (plus aging its own telegraph footprints, D-T072-4 / PARKED row 9).
class ToucherBehavior:
	extends RT.EnemyBehavior

	func _init() -> void:
		id = "toucher"
		display_name = "toucher"

	func on_spawn(row: Dictionary, _api) -> void:
		row["anim_state"] = "spawn"        # the common fade (30 ticks)
		row["anim_state_t"] = 0
		row["fade_left"] = SPAWN_FADE_TICKS
		row["infect_in"] = _first_infect_in(row)
		row["glitched"] = []               # own list: {"key","x","y","z","born","life"}
		row["last_infect_tick"] = -1
		row["infect_count"] = 0
		row["rt_tick"] = -1
		# SR-2 pin: the FINAL 1.4 u body / 0.8 u hit diameter (the T-016 placeholder
		# body_rect would derive 1.12 u).
		row["height_u"] = 1.4
		row["diameter_u"] = 0.8

	func tick(row: Dictionary, api, dt_ticks: int) -> void:
		row["rt_tick"] = int(api.rt.tick)
		row["anim_state_t"] = int(row.get("anim_state_t", 0)) + dt_ticks
		if int(row.get("fade_left", 0)) > 0:
			row["fade_left"] = maxi(0, int(row["fade_left"]) - dt_ticks)
		_age_tiles(row, api)
		_age_pulse(row, api, dt_ticks)     # PARKED row 9: own footprint lifetime
		# floats toward the nearest player at 6.75 u/s through every phase (SR-5's
		# clamp + SR-1's vertical easing live in FloatBody)
		var near: Dictionary = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
		if not near.is_empty():
			var fb: Variant = row.get("float", null)
			if fb == null:
				fb = RT.FloatBody.from_cfg(row["cfg"])
				row["float"] = fb
			fb.step(row, api, dt_ticks, float(near["x"]), float(near["z"]))
		_advance_state(row, api, dt_ticks)

	# SR-3: copy k of n starts its cycle k/n in - its first infection is staggered by
	# (INTERVAL - k/n x INTERVAL) so copies fire INTERVAL/n apart (coil's D-T-031-9
	# shape; never mid-telegraph - the stagger only ever ADDS ticks).
	func _first_infect_in(row: Dictionary) -> int:
		var copies: int = int(row.get("copies", 1))
		var copy_index: int = int(row.get("copy_index", 0))
		var phase := float(INFECT_INTERVAL_TICKS) * float(copy_index) / float(maxi(copies, 1))
		var extra := int(round(float(INFECT_INTERVAL_TICKS) - phase)) if phase > 0.0 else 0
		return SPAWN_FADE_TICKS + INFECT_INTERVAL_TICKS + extra

	func _advance_state(row: Dictionary, api, dt_ticks: int) -> void:
		match str(row.get("anim_state", "spawn")):
			"spawn":
				if int(row.get("fade_left", 0)) <= 0:
					row["anim_state"] = "idle_chase"
					row["anim_state_t"] = 0
			"idle_chase":
				row["infect_in"] = int(row["infect_in"]) - dt_ticks
				if int(row["infect_in"]) <= TELEGRAPH_TICKS:
					row["anim_state"] = "telegraph"
					row["anim_state_t"] = 0
					_announce_pulse(row, api)
			"telegraph":
				row["infect_in"] = int(row["infect_in"]) - dt_ticks
				if int(row["infect_in"]) <= 0:
					_infect(row, api)
			"attack_infect":
				# the infection tick only - no duration (the anim block records the
				# state as "on the infection tick"); the next tick returns to the cycle
				row["anim_state"] = "idle_chase"
				row["anim_state_t"] = 0
			_:
				row["anim_state"] = "idle_chase"
				row["anim_state_t"] = 0

	# The 18-tick glitch pulse: the view's telegraph VFX (anim block: scale_pulse
	# 1.0 -> 1.15 at 20 fps) and address me's SR-4 gate both read this footprint.
	func _announce_pulse(row: Dictionary, api) -> void:
		api.telegraph(TELEGRAPH_KIND,
				{"shape": "circle", "cx": float(row["x"]), "cz": float(row["z"]),
				"r": INFECT_RADIUS, "y0": float(row["y"]), "y1": float(row["y"])},
				TELEGRAPH_TICKS)

	# ---- the infection tick (DESIGN.md 5.8) ------------------------------------
	func _infect(row: Dictionary, api) -> void:
		var pos := Vector3(float(row["x"]), float(row["y"]), float(row["z"]))
		row["anim_state"] = "attack_infect"
		row["anim_state_t"] = 0
		row["infect_in"] = _interval_ticks(row, api)
		row["infect_count"] = int(row["infect_count"]) + 1
		var world_gl: Dictionary = api.rt.world.get("glitched", {})
		# Deterministic candidate order: api.tiles_in_radius walks the level's tile
		# array in index order. Only tiles strictly BELOW the finger infect ("all
		# tiles within 3 u below it", D-T-037-2).
		var fresh: Array = []
		for t in api.tiles_in_radius(pos, INFECT_RADIUS):
			if float(t["y"]) > float(row["y"]) + ELEV_EPS:
				continue
			# collision.gd's tile_key format ("x,z,y_hu") - the ONE glitched-tile
			# spelling for the controller, ben's cleanse and this row (D-T-037-5);
			# tiles_in_radius returns centres (+0.5) and tops (y_hu x 0.5).
			var key := "%d,%d,%d" % [int(floor(float(t["x"]))), int(floor(float(t["z"]))),
					int(round(float(t["y"]) * 2.0))]
			if world_gl.has(key):
				continue
			fresh.append({"key": key, "x": float(t["x"]), "y": float(t["y"]),
					"z": float(t["z"]), "born": int(api.rt.tick), "life": _tile_life_ticks(row)})
		# Max 60 per toucher (DESIGN.md 5.8): cap room is freed oldest-first (FIFO
		# eviction, D-T-037-3) so the patch follows its finger instead of disarming.
		var cap: int = MAX_GLITCHED_TILES
		var room: int = cap - (row["glitched"] as Array).size()
		var added: Array = []
		for entry in fresh:
			if (added as Array).size() >= room:
				var oldest: Dictionary = (row["glitched"] as Array)[0]
				world_gl.erase(str(oldest["key"]))
				(row["glitched"] as Array).pop_front()
				room += 1
			world_gl[str(entry["key"])] = true
			(row["glitched"] as Array).append(entry)
			added.append(entry)
		# the squelch (ENEMIES.md "New sound") - only when NEW tiles appeared
		if not added.is_empty():
			api.rt.events.append({"e": "audio", "cue": SQUELCH_CUE,
					"x": float(row["x"]), "y": float(row["y"]), "z": float(row["z"]),
					"tick": int(api.rt.tick)})
		row["last_infect_tick"] = int(api.rt.tick)
		row["last_infect_new"] = added.size()
		api.rt.events.append({"e": "toucher_infect", "new": added.size(),
				"total": (row["glitched"] as Array).size(), "cap": cap,
				"x": float(row["x"]), "y": float(row["y"]), "z": float(row["z"]),
				"tick": int(api.rt.tick)})

	# SR-5 tempo conversion: 120 / tempo_mul, never below 72 ticks (1.2 s). tempo_mul
	# comes from the row's own FloatBody (the pursuit-clamp overflow, capped at
	# 1/TEMPO_FLOOR); api.tempo_ticks applies the same floor here.
	func _interval_ticks(row: Dictionary, api) -> int:
		return api.tempo_ticks(INFECT_INTERVAL_TICKS)

	# Glitched tile life: 12 s; 18 s from level 14 (cfg "level_number" is the engine
	# caller's, D-T-037-4).
	func _tile_life_ticks(row: Dictionary) -> int:
		var lvl: int = int(float(str(row["cfg"].get("level_number", "1"))))
		return TILE_LIFE_TICKS_L14 if lvl >= TILE_LIFE_LEVEL else TILE_LIFE_TICKS

	# ---- aging own state --------------------------------------------------------
	# Expiry (born + life) and ben's ring cleanse (T-032's cleanse_glitched_within
	# erases keys straight out of world["glitched"]) both leave the toucher's list.
	func _age_tiles(row: Dictionary, api) -> void:
		var world_gl: Dictionary = api.rt.world.get("glitched", {})
		var now: int = int(api.rt.tick)
		var keep: Array = []
		for entry in row.get("glitched", []):
			var key := str(entry["key"])
			if not world_gl.has(key):
				continue            # cleansed by thicc ben's ring (or a future hand)
			if now >= int(entry["born"]) + int(entry["life"]):
				world_gl.erase(key)
				continue
			keep.append(entry)
		row["glitched"] = keep

	# PARKED row 9: the runtime never expires telegraph footprints (T-027's list);
	# the pulse is the toucher's own, so it ages it exactly like coil does
	# (D-T072-4): each own "toucher_pulse" entry ticks down to 0, never negative.
	# Aged BEFORE the state machine, so a pulse announced on this very tick keeps
	# its full announced lifetime.
	func _age_pulse(row: Dictionary, api, dt_ticks: int) -> void:
		var id := str(row.get("id", ""))
		for t in api.rt.telegraphs:
			if str(t.get("kind", "")) == TELEGRAPH_KIND and str(t.get("source", "")) == id:
				t["ticks"] = maxi(int(t.get("ticks", 0)) - dt_ticks, 0)
