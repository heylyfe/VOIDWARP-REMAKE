extends RefCounted
#
# mirror_match.gd - script curse (ticket T-051; DESIGN.md section 7.1 "mirror_match").
# Rule sentence (spec, verbatim): "YOU?! uses your class kit: dashes 6 u every 5 s /
# ignores height (glides) / moves +15%".
# Counter-play: "watch your own cooldown".
#
# Reading (recorded in DECISIONS.md, D-T051-4 [CONTESTABLE]): the triple clause maps
# one clause per class kit - dasher -> YOU?! dashes 6 u every 5 s; glider -> YOU?!
# ignores height (the glide flag the ring's feet window reads); athletic -> YOU?!
# moves +15% (the row's cfg base_speed multiplied once). The row mirrors THE NEAREST
# PLAYER's kit (api-readable through the state's controller list, index 0 first).
# The dash is an instant 6 u transit toward the player on the 300-tick cadence,
# stopping 0.6 u short of the target's centre (SR-2's player radius: the dash
# positions, it never body-kills - DASH_STOP_SHORT [CONTESTABLE]). A dash reads as
# the mirror's own kit move: no telegraph, matching the player's dasher cooldown.

const CURSE_ID := "mirror_match"

const YOU_ID := "you"              # the enemy the curse attaches to (content names content)
const DASH_U := 6.0                # u, the dasher-mirror dash length (the rule sentence)
const DASH_EVERY_TICKS := 300      # 5.0 s cadence (the rule sentence)
const MIRROR_SPEED_MUL := 1.15     # the athletic-mirror +15% (the rule sentence)
const DASH_STOP_SHORT := 0.6       # u short of the target's centre [CONTESTABLE, D-T051-4]

## Per-level scratch: "mm_dash_<row index>" -> next dash tick; "mm_seen_<row index>"
## -> the kit the row already mirrors (idempotence).
const ST_PREFIX := "mm_"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## Pure helper (test target): the clause a kit maps to.
static func mirror_mode_for(kit: String) -> String:
	match kit:
		"dasher":
			return "dash"
		"glider":
			return "glide"
		_:
			return "speed"   # athletic -> +15% move


## Pure helper (test target): the dash endpoint - DASH_U toward the target, capped
## DASH_STOP_SHORT short of the target's centre (never a body-kill transit).
static func dash_point(row: Dictionary, target: Dictionary) -> Vector3:
	var rx := float(row.get("x", 0.0))
	var rz := float(row.get("z", 0.0))
	var tx := float(target.get("x", rx))
	var tz := float(target.get("z", rz))
	var dx := tx - rx
	var dz := tz - rz
	var d := sqrt(dx * dx + dz * dz)
	if d <= DASH_STOP_SHORT:
		return Vector3(rx, float(row.get("y", 0.0)), rz)   # already at the shell: hold
	var step := minf(DASH_U, d - DASH_STOP_SHORT)
	return Vector3(rx + dx / d * step, float(row.get("y", 0.0)), rz + dz / d * step)


## on_tick: stamp the nearest player's kit onto every YOU?! row and run its clause.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	var players: Array = state.get("players", [])
	var st: Dictionary = state.get("curse_st", {})
	var tick := int(state.get("tick", 0))
	for i in range(rt.enemies.size()):
		var row = rt.enemies[i]
		if str(row.get("id", "")) != YOU_ID:
			continue
		var target: Dictionary = _mirror_target(row, players, api)
		var kit := str(target.get("kit", "dasher"))
		var seen_key := "%sseen_%d" % [ST_PREFIX, i]
		if str(st.get(seen_key, "")) != kit:
			st[seen_key] = kit
			_apply_kit(row, kit)
		match str(row.get("mirror_mode", "")):
			"dash":
				_dash_cadence(row, target, st, tick, i, api)
			_:
				pass   # glide and speed are stamped, not per-tick


## The row's mirror read: the nearest player (api when available, else player 0).
static func _mirror_target(row: Dictionary, players: Array, api) -> Dictionary:
	if api.has_method("nearest_player") and not players.is_empty():
		var near: Dictionary = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
		if not near.is_empty():
			var idx := int(near.get("index", 0))
			if idx >= 0 and idx < players.size():
				return players[idx]
	if players.is_empty():
		return {}
	return players[0]


## The kit stamp: dash/glide flags + the athletic cfg multiplier (idempotent).
static func _apply_kit(row: Dictionary, kit: String) -> void:
	row["mirror_mode"] = mirror_mode_for(kit)
	row["mirror_glide"] = (row["mirror_mode"] == "glide")
	if row["mirror_mode"] == "speed" and not row.has("mirror_speed_applied"):
		var stats: Dictionary = row.get("cfg", {})
		if stats.has("base_speed"):
			stats["base_speed"] = float(stats["base_speed"]) * MIRROR_SPEED_MUL
		row["mirror_speed_applied"] = true


## The dasher clause: one 6 u dash every 300 ticks along the current line to target.
static func _dash_cadence(row: Dictionary, target: Dictionary, st: Dictionary,
		tick: int, i: int, api) -> void:
	var key := "%sdash_%d" % [ST_PREFIX, i]
	var next_tick := int(st.get(key, DASH_EVERY_TICKS))
	if tick < next_tick:
		return
	if target.is_empty():
		st[key] = tick + DASH_EVERY_TICKS
		return
	var p := dash_point(row, target)
	row["x"] = p.x
	row["z"] = p.z
	st[key] = tick + DASH_EVERY_TICKS
	if api.has_method("sync_body"):
		api.sync_body()
