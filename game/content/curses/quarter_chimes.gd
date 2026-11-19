extends RefCounted
#
# quarter_chimes.gd - script curse (DESIGN.md section 7.1 row "quarter_chimes").
# Rule sentence (spec, verbatim): "ben's teleport interval 13.35 → 9 s".
# Counter-play: "keep moving".
#
# Reading: ben's own cycle is the binding 801 ticks (13.35 s, T-032) and the smoke is
# the last 75 of them, so the idle runs 726 ticks before the behavior starts its own
# telegraph. The curse shortens the INTERVAL, not the smoke: once the row's idle has
# run IDLE_LIMIT_TICKS (465 = 540 - 75) the curse starts the smoke itself, using the
# behavior's own numbers (the 0.5 s velocity lead, the 1.2 u smoke column, the
# "teleport" kind). The behavior's own _telegraph_tick then counts the 75 ticks down
# and its own _arrive lands ben on the locked point, so the arrival-to-arrival
# interval becomes exactly 540 ticks (9.0 s) and nothing else about ben changes -
# the lock, the eject, the ring cleanse and the never-kills rule all stay his.
#
# The curse never writes the row while the smoke runs (phase != "idle"): a second
# start would re-lock the destination mid-telegraph, which the 5.3 contract forbids.

const CURSE_ID := "quarter_chimes"

const BEN_ID := "thicc_ben"          # the enemy the curse attaches to (content names content)
const TELEPORT_TICKS := 801          # ben's own 13.35 s cycle (T-032, binding)
const TELEGRAPH_TICKS := 75          # ben's own 1.25 s smoke (T-032, binding)
const INTERVAL_TICKS := 540          # 9.0 s, the rule sentence
const IDLE_LIMIT_TICKS := INTERVAL_TICKS - TELEGRAPH_TICKS   # 465: when the smoke starts
const LOCK_LEAD_S := 0.5             # ben's own destination lead (5.3)
const TELEGRAPH_R := 1.2             # ben's own smoke column width (T-083 anim block)
const KIND := "teleport"             # the telegraph kind ben announces (T-032)

## Per-level scratch: nothing is stored - the row's own cycle_t is the clock.
const ST_KEY := "quarter_chimes"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## The interval the curse pins, in ticks (the rule sentence's 9 s). Pure helper.
static func interval_ticks() -> int:
	return INTERVAL_TICKS


## The idle length that puts the smoke's start at exactly INTERVAL_TICKS after the
## previous arrival. Pure helper - the test target.
static func idle_limit_ticks() -> int:
	return IDLE_LIMIT_TICKS


## on_tick: start ben's smoke early once his idle has run the shortened interval.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	for i in range(rt.enemies.size()):
		var row = rt.enemies[i]
		if str(row.get("id", "")) != BEN_ID:
			continue
		if str(row.get("phase", "idle")) != "idle":
			continue   # the smoke is already running: never re-lock it
		if int(row.get("cycle_t", 0)) < IDLE_LIMIT_TICKS:
			continue
		_begin_smoke(row, api)


## Start the smoke the way ben's own _begin_telegraph does (5.3): the destination is
## the closest player's position plus velocity x 0.5 s, locked now and never re-aimed.
## No target: the idle keeps counting and the curse retries next tick.
static func _begin_smoke(row: Dictionary, api) -> void:
	var near: Dictionary = {}
	if api != null and api.has_method("nearest_player"):
		near = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
	if near.is_empty():
		return
	row["phase"] = "telegraph"
	row["phase_t"] = 0
	row["lock_x"] = float(near["x"]) + float(near.get("vx", 0.0)) * LOCK_LEAD_S
	row["lock_y"] = float(near["y"]) + float(near.get("vy", 0.0)) * LOCK_LEAD_S
	row["lock_z"] = float(near["z"]) + float(near.get("vz", 0.0)) * LOCK_LEAD_S
	row["lock_broken"] = false
	if api.has_method("telegraph"):
		api.telegraph(KIND, {"shape": "circle", "cx": float(row["lock_x"]),
				"cz": float(row["lock_z"]), "r": TELEGRAPH_R}, TELEGRAPH_TICKS)
