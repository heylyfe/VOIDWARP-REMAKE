extends RefCounted
#
# isagi enemy (ticket T-033; DESIGN.md section 5.4, section 12; ENEMIES.md Guardian -> Isagi).
# Content module: carries NO sim state of its own - everything lives on the enemy row the
# runtime hands in, and every world change goes through the section 12 Api only.
#
# Behavior (DESIGN.md section 5.4 verbatim numbers, 60 Hz ticks):
#   - prefers `perch` anchors (D-056 stays FINAL: he may fall back to a `lane` anchor);
#     every 12 s (720 ticks) he relocates to the `perch` anchor nearest the player with
#     line of sight, falling back to `lane` only when no perch qualifies (D-T-033-2).
#   - Dwell limit (D-064, FINAL): on a `lane` anchor he stays at most 4.0 s (240 ticks)
#     before relocating.
#   - Flat in-line lane suppression (T-070 item 10 / R10, D-T-033-3): while the horizontal
#     line from him to the player runs along his walkway's axis with less than 2 HU of
#     total height change, he never BEGINS a wind-up - the relocation timer is cut to 4 s.
#   - With line of sight from any anchor: wind-up 1.2 s (72 ticks - idle sprite flash +
#     voice cue) -> the volleying burst at 22 u/s, radius 0.5 u, life 3.0 s (180 ticks),
#     stopped by any tile or prop -> cooldown 2.5 s (150 ticks). Ball hit = kill.
#   - Volley gap (D-064, FINAL): at most 3 balls per volley, balls inside a volley
#     0.15 s (9 ticks) apart, consecutive volleys 0.75 s (45 ticks) apart start to start
#     - the runtime's VolleyClock is the single implementation (test_ranged.gd).
#   - Ball flight: each ball leaves from 1.0 u above Isagi's tile and flies straight in 3D
#     to the player's centre at release (feet + 0.9 u); the line is fixed at release and
#     never homes. Egoist adds +1 ball per burst per stack (D-T-033-1: per-stack size is
#     DATA - `balls_per_stack` - because the ticket's "up to 7 balls as 3+3+1" and the
#     rule text's "+1 per stack" cannot both bind; D-064's gap shape holds either way).

const RT := preload("res://sim/enemy_runtime.gd")
const VOLLEY_GAP := RT.VOLLEY_GAP_TICKS      # 45 - one full jump, D-064 FINAL
const VOLLEY_IN := RT.VOLLEY_TICKS           # 9 - 0.15 s inside one volley
const VOLLEY_MAX := RT.VOLLEY_MAX            # 3 balls per volley, D-064 FINAL

# DESIGN.md section 5.4 / section 3.1 numbers, 60 Hz ticks (fps 60; the anim block 1.4
# carries the same binding counts for the view).
const RELOCATE_TICKS := 720      # 12.0 s
const LANE_DWELL_TICKS := 240    # 4.0 s (D-064, FINAL)
const WINDUP_TICKS := 72         # 1.2 s
const COOLDOWN_TICKS := 150      # 2.5 s
const SPAWN_FADE_TICKS := 30     # sprites.json anim block 1.4: spawn/relocate-in fade
const ATTACK_HOLD_TICKS := 30    # anim block 1.4: pose held 72 -> 102 (release at 0..90)
const BALL_LIFE_TICKS := 180     # 3.0 s
const SWITCH_GRACE_TICKS := 6    # relocation retry when no candidate qualifies

# DESIGN.md section 5.4 / 5.0 (SR-2) world numbers.
const BALL_SPEED := 22.0
const BALL_RADIUS := 0.5
const MUZZLE_UP := 1.0           # balls leave 1.0 u above his tile
const TARGET_CENTRE_UP := 0.9    # player centre = feet + 0.9 u
const PLAYER_FLOOR := 25.0       # the spawn rule's 25 u floor, held on relocations too
const LANE_PREFERRED := 60.0     # D-056 farthest-but-within-60 u preference, lane fallback
const LANE_PROBE := 24.0         # how far fellow lane anchors may define the walkway axis
const AXIS_DOT := 0.9            # "runs along a walkway axis" (D-T-033-3)
const STEP_HU := 2.0             # the 2 HU height change that answers a ball line
const VIEW_RANGE := 1e9          # LOS has no range cap in section 5.4


class Behavior:
	extends RT.EnemyBehavior

	const cfg_stats := "stats"

	func on_spawn(row: Dictionary, api) -> void:
		# SR-2 (D-T-033-4): the hit cylinder comes from the data, never from the TBD
		# placeholder sheet's square body_rect (that would double the spec diameter).
		var st: Dictionary = _stats(row)
		row["world_height"] = float(st.get("world_height", 1.8))
		row["height_u"] = float(st.get("world_height", 1.8))
		row["diameter_u"] = float(st.get("hit_diameter", 0.7))
		row["contact_kill"] = bool(st.get("contact_kill", true))
		row["st"] = "spawn"
		row["st_t"] = SPAWN_FADE_TICKS
		row["rel_t"] = RELOCATE_TICKS
		row["vc"] = RT.VolleyClock.new()
		row["balls"] = 0
		row["anchor_i"] = -1
		row["anchor_kind"] = ""
		var here := _anchor_at(row, api, row["x"], row["z"])
		if not here.is_empty():
			row["anchor_i"] = int(here["index"])
			row["anchor_kind"] = str(here["kind"])

	# One 60 Hz tick.
	func tick(row: Dictionary, api, dt_ticks: int) -> void:
		var st: Dictionary = _stats(row)
		row["st_t"] = maxi(int(row["st_t"]) - dt_ticks, 0)
		# the aim entry is aged before the state machine, so it reaches 0 exactly on the
		# tick the strike lands (D-T072-4: the entry's lifetime is its caller's)
		_age_aim(row, api, dt_ticks)
		_run_state(row, api, st, dt_ticks)
		_run_relocation(row, api, st, dt_ticks)
		if str(row["st"]) == "idle":
			_try_windup(row, api, st)

	func on_vote(_row: Dictionary, _api, _count: int) -> void:
		pass   # votes add copies (the engine plans one row per copy); stacks arrive via cfg

	# ---- state machine -------------------------------------------------------------------

	func _run_state(row: Dictionary, api, st: Dictionary, dt_ticks: int) -> void:
		match str(row["st"]):
			"spawn":
				if int(row["st_t"]) <= 0:
					row["st"] = "idle"
			"telegraph":
				if int(row["st_t"]) <= 0:
					_begin_burst(row, st)
			"attack":
				# the VolleyClock releases the balls (D-064 gaps); the pose holds while
				# the clock still has balls, and at least ATTACK_HOLD_TICKS (the anim
				# block's 72 -> 102 window) - Egoist volleys outlive that window
				_fire_scheduled(row, api, st, dt_ticks)
				var vc = row["vc"]
				if int(row["st_t"]) <= 0 and not vc.active():
					row["st"] = "recover"
					row["st_t"] = _cooldown(st)
			"recover":
				if int(row["st_t"]) <= 0:
					row["st"] = "idle"
			_:
				row["st"] = "idle"

	func _begin_burst(row: Dictionary, st: Dictionary) -> void:
		var stacks: int = int(st.get("egoist_stacks", 0))
		var balls: int = int(st.get("volley_balls", 3)) \
				+ int(st.get("balls_per_stack", 1)) * stacks
		row["balls"] = maxi(balls, 0)
		var vc = row["vc"]
		vc.start(int(row["balls"]))
		row["aim"] = {}   # the volley aim is captured at each volley's first release
		row["st"] = "attack"
		row["st_t"] = ATTACK_HOLD_TICKS

	# Each volley's line is fixed at ITS first release and never homes within the
	# volley: the balls of one volley share the release-time target (the section 5.4
	# answer "a jump per volley (0.45 s = 0.75 s apart) clears" - a jump stays above
	# 1.5 u for 0.43 s, longer than a volley's 0.30 s spread, but a SECOND volley
	# re-aims). row["aim"] holds the volley's release-time player centre.
	func _fire_scheduled(row: Dictionary, api, st: Dictionary, dt_ticks: int) -> void:
		var vc = row["vc"]
		while vc.tick(dt_ticks) > 0:
			if int(vc.in_volley) == 1:
				_capture_aim(row, api)
			_release_ball(row, api)

	func _capture_aim(row: Dictionary, api) -> void:
		var near: Dictionary = api.nearest_player(
				Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
		if near.is_empty():
			row["aim"] = {}
			return
		row["aim"] = {"x": float(near["x"]),
				"y": float(near["y"]) + TARGET_CENTRE_UP, "z": float(near["z"])}

	func _try_windup(row: Dictionary, api, st: Dictionary) -> void:
		if _suppressed(row, api, st):
			return
		# On a lane anchor a wind-up must still finish before the dwell limit moves him:
		# no new wind-up in the last wind-up+hold stretch of the dwell window.
		if str(row["anchor_kind"]) == "lane" \
				and int(row["rel_t"]) < WINDUP_TICKS + ATTACK_HOLD_TICKS:
			return
		if not _los_on_target(row, api):
			return
		row["st"] = "telegraph"
		row["st_t"] = _windup(st)
		# the wind-up telegraph IS the audio + flash cue (ENEMIES.md: an audio cue
		# precedes each burst; anim block 1.4: red rim flash + aim line). The aim line
		# is not a hazard: no hazard footprint, only the cues ride the event. The
		# footprint is a radius-0 circle at the muzzle, the seal's dash_line idiom
		# (D-T-038-2) - an "aim" kind with an absent radius makes point_in_shape
		# default the centre to the queried point and match EVERY point in the level.
		# `owner` keys the entry to this row's copy so the aging below (and no sibling's)
		# reaches it; unknown shape keys are ignored by every consumer.
		row["aim_tg"] = "%s#%d" % [str(row["id"]), int(row.get("copy_index", 0))]
		api.telegraph("aim", {"shape": "circle", "cx": float(row["x"]),
				"cz": float(row["z"]), "r": 0.0, "fx": float(row["x"]),
				"fy": float(row["y"]) + MUZZLE_UP, "fz": float(row["z"]),
				"owner": str(row["aim_tg"])}, _windup(st))

	# This row's own aim entry, aged here: enemy_arbiter.gd's contract is that a telegraph
	# entry lives while its ticks > 0 and that "entry lifetime is the caller's" (the runtime
	# only appends - rt.telegraphs is never pruned), so an un-aged aim row stays live for the
	# whole level and its footprint vetoes address me's no_targeted_telegraph. Matching on the
	# `owner` token also keeps one copy's tick() from aging a sibling's entry (every copy of
	# an enemy shares source = row["id"]).
	func _age_aim(row: Dictionary, api, dt_ticks: int) -> void:
		var tok := str(row.get("aim_tg", ""))
		if tok == "":
			return
		for t in api.rt.telegraphs:
			if str(t.get("kind", "")) != "aim":
				continue
			var shape: Dictionary = t.get("shape", {})
			if str(shape.get("owner", "")) != tok:
				continue
			t["ticks"] = maxi(int(t.get("ticks", 0)) - dt_ticks, 0)

	# ---- ball release ----------------------------------------------------------------------

	# One ball: leaves 1.0 u above his tile (section 5.4 muzzle height), flies the
	# volley's fixed release-time line at 22 u/s, radius 0.5 u, life 3.0 s (180 ticks);
	# any tile or prop stops it (the runtime) and a hit is a kill.
	func _release_ball(row: Dictionary, api) -> void:
		var aim: Dictionary = row.get("aim", {})
		if aim.is_empty():
			return   # nobody to be aimed at: no ball owns a line without a target
		var mx: float = float(row["x"])
		var my: float = float(row["y"]) + MUZZLE_UP
		var mz: float = float(row["z"])
		var d3 := Vector3(float(aim["x"]) - mx, float(aim["y"]) - my,
				float(aim["z"]) - mz)
		if d3.length() < 1e-9:
			d3 = Vector3(0.0, 0.0, 1.0)
		var st: Dictionary = _stats(row)
		var v: Vector3 = d3.normalized() * _ball_speed(st)
		api.spawn_projectile({"name": str(row["name"]), "x": mx, "y": my, "z": mz,
				"vx": v.x, "vy": v.y, "vz": v.z, "r": BALL_RADIUS,
				"life_ticks": BALL_LIFE_TICKS})

	# ---- relocation (D-056 preferences stay untouched; see D-T-033-2) ---------------------

	func _run_relocation(row: Dictionary, api, st: Dictionary, dt_ticks: int) -> void:
		# Dwell limit (D-064, FINAL): on a lane anchor he never stays past 4.0 s.
		# The flat in-line lane suppression cuts the timer the same way (T-070 item 10).
		if str(row["anchor_kind"]) == "lane":
			row["rel_t"] = mini(int(row["rel_t"]), LANE_DWELL_TICKS)
		row["rel_t"] = maxi(int(row["rel_t"]) - dt_ticks, 0)
		if int(row["rel_t"]) > 0:
			return
		_relocate(row, api)

	func _relocate(row: Dictionary, api) -> void:
		var near: Dictionary = api.nearest_player(
				Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
		if near.is_empty():
			row["rel_t"] = SWITCH_GRACE_TICKS
			return
		var pp := Vector3(float(near["x"]), float(near["y"]), float(near["z"]))
		var pick: Dictionary = _pick_perch(row, api, pp)
		if pick.is_empty():
			pick = _pick_lane(row, api, pp)
		if pick.is_empty():
			row["rel_t"] = SWITCH_GRACE_TICKS   # nothing qualifies: retry shortly
			return
		row["x"] = float(pick["x"])
		row["y"] = float(pick["y"])
		row["z"] = float(pick["z"])
		# the relocate is an instant reposition (up to a 12 s move at once), so the body
		# mirror follows it (PARKED row 27): no_enemy_body_within and the D-059 safe tile
		# read world["enemies"], never this row.
		api.sync_body()
		row["anchor_i"] = int(pick["index"])
		row["anchor_kind"] = str(pick["kind"])
		row["st"] = "spawn"                  # the relocate-in fade (anim block 1.4)
		row["st_t"] = SPAWN_FADE_TICKS
		row["rel_t"] = RELOCATE_TICKS
		# a fresh cycle never carries a half-spent burst into the new spot
		var vc = row["vc"]
		vc.start(0)
		row["balls"] = 0
		row["aim"] = {}

	# The `perch` anchor nearest the player WITH line of sight (muzzle to the player's
	# centre). The 25 u floor holds (D-T-033-2); the 60 u preference does NOT: nearest
	# means nearest. Ties: lowest anchor index. Copies skip their copy_index in the
	# sorted candidate list - a deterministic SR-3 spread without a sibling query.
	func _pick_perch(row: Dictionary, api, pp: Vector3) -> Dictionary:
		var cands: Array = _los_candidates(row, api, api.anchors("perch"), pp, "perch")
		return _pick_offset(row, cands)

	# D-056's fallback shape, behavior-side (the runtime's pick_spawn_tile is spawn-only):
	# lane anchors >= 25 u from the player, farthest-but-within 60 u first, else farthest;
	# tie lowest anchor index - never the anchor he just left.
	func _pick_lane(row: Dictionary, api, pp: Vector3) -> Dictionary:
		var out: Array = []
		for a in api.anchors("lane"):
			if int(a["index"]) == int(row["anchor_i"]):
				continue
			var pos := Vector3(float(a["x"]), float(a["y"]), float(a["z"]))
			var d := pos.distance_to(pp)
			if d < PLAYER_FLOOR:
				continue
			out.append({"x": a["x"], "y": a["y"], "z": a["z"], "index": int(a["index"]),
					"kind": "lane", "d": d, "pref": 0 if d <= LANE_PREFERRED else 1})
		if out.is_empty():
			return {}
		out.sort_custom(func(a, b) -> bool:
			if int(a["pref"]) != int(b["pref"]):
				return int(a["pref"]) < int(b["pref"])
			if absf(float(a["d"]) - float(b["d"])) > 1e-9:
				return float(a["d"]) > float(b["d"])   # farthest first (D-056)
			return int(a["index"]) < int(b["index"]))
		return _pick_offset(row, out)

	# perch candidates with LOS, sorted NEAREST to the player first, tie lowest index.
	func _los_candidates(row: Dictionary, api, anchors: Array, pp: Vector3, kind: String) -> Array:
		var out: Array = []
		for a in anchors:
			if int(a["index"]) == int(row["anchor_i"]):
				continue
			var pos := Vector3(float(a["x"]), float(a["y"]), float(a["z"]))
			var d := pos.distance_to(pp)
			if d < PLAYER_FLOOR:
				continue
			if not api.los(Vector3(pos.x, pos.y + MUZZLE_UP, pos.z),
					Vector3(pp.x, pp.y + TARGET_CENTRE_UP, pp.z)):
				continue
			out.append({"x": a["x"], "y": a["y"], "z": a["z"], "index": int(a["index"]),
					"kind": kind, "d": d})
		sort_by_player(out)
		return out

	static func sort_by_player(cands: Array) -> void:
		cands.sort_custom(func(a, b) -> bool:
			if absf(float(a["d"]) - float(b["d"])) > 1e-9:
				return float(a["d"]) < float(b["d"])   # nearest first (section 5.4)
			return int(a["index"]) < int(b["index"]))

	# copy k takes the (k mod n)-th candidate, so copies spread without sibling state.
	func _pick_offset(row: Dictionary, cands: Array) -> Dictionary:
		if cands.is_empty():
			return {}
		var k: int = int(row.get("copy_index", 0))
		return cands[k % cands.size()]

	# ---- the flat in-line lane suppression (T-070 item 10 / R10; D-T-033-3) ----------------

	func _suppressed(row: Dictionary, api, st: Dictionary) -> bool:
		if str(row["anchor_kind"]) != "lane":
			return false
		var lane := _anchor_at(row, api, row["x"], row["z"])
		if lane.is_empty():
			return false
		var near = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
		if near.is_empty():
			return false
		var axis := _walkway_axis(row, api)
		if axis == 0:
			return false   # two axes cross here: side-exit options exist, no suppression
		var dx: float = float(near["x"]) - float(row["x"])
		var dz: float = float(near["z"]) - float(row["z"])
		var dist: float = sqrt(dx * dx + dz * dz)
		if dist < 1e-9:
			return false
		var along: float = absf(dx) / dist if axis == 1 else absf(dz) / dist
		var height: float = absf(float(near["y"]) - float(row["y"]))
		return along >= AXIS_DOT and height < _step_hu(st)

	# The walkway axis under his feet, read from the TILE runs: whichever axis has the
	# longer contiguous flat run at his feet height IS the axis (a 1-wide lane runs on
	# x -> members share his z). 0 = crossing / no readable run: no suppression.
	# 1 = x, 2 = z, 0 = crossing.
	func _walkway_axis(row: Dictionary, api) -> int:
		var run_x := 0
		var run_z := 0
		for t in api.tiles_in_radius(Vector3(float(row["x"]), float(row["y"]), float(row["z"])), LANE_PROBE):
			if absf(float(t["y"]) - float(row["y"])) > 0.75:
				continue
			if absf(float(t["z"]) - float(row["z"])) <= 0.75:
				run_x += 1
			if absf(float(t["x"]) - float(row["x"])) <= 0.75:
				run_z += 1
		if run_x > run_z:
			return 1
		if run_z > run_x:
			return 2
		return 0

	# ---- helpers -----------------------------------------------------------------------------

	# True when the muzzle (1.0 u above his tile) sees the player's centre right now.
	func _los_on_target(row: Dictionary, api) -> bool:
		var near = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
		if near.is_empty():
			return false
		var a := Vector3(float(row["x"]), float(row["y"]) + MUZZLE_UP, float(row["z"]))
		var b := Vector3(float(near["x"]), float(near["y"]) + TARGET_CENTRE_UP, float(near["z"]))
		return api.los(a, b)

	# The anchor (perch first, then lane) whose integer cell matches (x, z); {} when none.
	func _anchor_at(row: Dictionary, api, x: Variant, z: Variant) -> Dictionary:
		var lx: int = int(round(float(x)))
		var lz: int = int(round(float(z)))
		for kind in ["perch", "lane"]:
			for a in api.anchors(kind):
				if int(round(float(a["x"]))) == lx and int(round(float(a["z"]))) == lz:
					return {"index": int(a["index"]), "kind": kind, "x": a["x"], "y": a["y"], "z": a["z"]}
		return {}

	func _stats(row: Dictionary) -> Dictionary:
		var cfg: Dictionary = row.get("cfg", {})
		if not cfg.has("stats"):
			return {}
		return cfg["stats"]

	func _windup(st: Dictionary) -> int:
		return int(round(float(st.get("windup_s", 1.2)) * 60.0))

	func _cooldown(st: Dictionary) -> int:
		return int(round(float(st.get("cooldown_s", 2.5)) * 60.0))

	func _ball_speed(st: Dictionary) -> float:
		return float(st.get("ball_speed", BALL_SPEED))

	func _step_hu(st: Dictionary) -> float:
		return float(st.get("step_clears_hu", STEP_HU))


