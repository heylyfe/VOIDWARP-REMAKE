extends RefCounted
#
# long_toll.gd - script curse (ticket T-051; DESIGN.md section 7.1 row "long_toll").
# Rule sentence (spec, verbatim): "every ben teleport tolls twice: a second ben
# arrives at the same locked point 1.5 s after the first".
# Counter-play: "air control is 100% - steer >= 4 u sideways during the launch".

# Reading (recorded in DECISIONS.md, the done-when sentence): the SECOND arrival is
# the same row re-running its smoke->arrive cycle against the FIRST arrival's locked
# point, never a fresh lock, and the total from first arrival to second arrival is
# exactly 90 ticks (1.5 s at 60 Hz). Ben never kills (KILL RULE, section 5.3), so a
# toll never kills either; the touch keeps its non-killing eject. Mechanics: on the
# first arrival tick (phase returned to "idle", cycle_t 0) the curse schedules
# due = tick + TOLL_INTERVAL_TICKS and parks the row's fresh cycle so the
# behavior's own smoke begins exactly 15 ticks later; during the smoke it
# overwrites row["lock_x"/"lock_y"/"lock_z"] with the stored point (the
# behavior re-locks at smoke start - the curse freezes that lock) and patches the
# row's smoke telegraph shape to the same point. The behavior's own arrive lands ben
# on the FIRST locked point at exactly +90 ticks.

const CURSE_ID := "long_toll"

const BEN_ID := "thicc_ben"                 # the enemy the curse attaches to
const TELEPORT_TICKS := 801                 # the behavior's 13.35 s cycle (T-032)
const TELEGRAPH_TICKS := 75                 # the behavior's 1.25 s smoke
const TOLL_INTERVAL_TICKS := 90             # 1.5 s, first arrival -> second arrival
# cycle_t that makes the behavior's own idle begin the smoke at exactly
# (T + TOLL_INTERVAL_TICKS - TELEGRAPH_TICKS) from a dispatch at T: the idle needs
# (90 - 75) = 15 more ticks, and the behavior checks .cycle_t >= 726 each idle tick.
const TELEPORT_WAIT_TICKS := TOLL_INTERVAL_TICKS - TELEGRAPH_TICKS   # 15

## Per-level scratch: "lt_<row index>" -> {"due": int, "x", "y", "z"} while a toll
## is being driven; "lt_seen_<row index>" -> last seen phase (transition detect).
const ST_PREFIX := "lt_"


## Stacks the run holds; >= 1 while the curse is picked (max_stacks 1).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## on_tick: catch arrivals, drive each row's second toll, freeze the lock.
static func on_tick(state: Dictionary, api) -> void:
	if held_stacks(state) <= 0:
		return
	var rt = state.get("enemy_runtime")
	if rt == null:
		return
	var st: Dictionary = state.get("curse_st", {})
	var tick := int(state.get("tick", 0))
	for i in range(rt.enemies.size()):
		var row = rt.enemies[i]
		if str(row.get("id", "")) != BEN_ID:
			continue
		var phase := str(row.get("phase", "idle"))
		var seen_key := "%sseen_%d" % [ST_PREFIX, i]
		var toll_key := "%stoll_%d" % [ST_PREFIX, i]
		var prev := str(st.get(seen_key, "idle"))
		st[seen_key] = phase
		if prev == "telegraph" and phase == "idle":
			_arrived(row, st, toll_key, tick)
		if not st.has(toll_key):
			continue
		_drive_toll(row, rt, st, toll_key, tick)


## The first arrival: schedule the second one at exactly +90 ticks from the same
## locked point, unless a toll is already pending for this row (that arrival is the
## toll itself - a toll never chains, the sentence tolls TELEPORTS twice).
static func _arrived(row: Dictionary, st: Dictionary, toll_key: String, tick: int) -> void:
	if st.has(toll_key):
		st.erase(toll_key)   # this arrival was the toll's second half
		return
	st[toll_key] = {"due": tick + TOLL_INTERVAL_TICKS, "x": float(row["x"]),
			"y": float(row["y"]), "z": float(row["z"])}
	# park the fresh cycle so the behavior's own idle begins its smoke at exactly
	# T + 15: the idle reaches 726 at tick T + 15, the smoke runs its 75 ticks, and
	# the behavior's own _arrive lands at tick T + 90 - the rule sentence's 1.5 s.
	row["cycle_t"] = TELEPORT_TICKS - TELEGRAPH_TICKS - TELEPORT_WAIT_TICKS


## Drive one pending toll: force the smoke to start on schedule, then freeze the
## lock point and the smoke shape onto the FIRST arrival's point until ben lands.
static func _drive_toll(row: Dictionary, rt, st: Dictionary, toll_key: String,
		tick: int) -> void:
	var toll: Dictionary = st[toll_key]
	var due := int(toll["due"])
	var phase := str(row.get("phase", "idle"))
	if phase != "telegraph":
		return
	# smoke running: freeze the lock (the behavior re-locked at smoke start) and
	# repoint the smoke shape at the first arrival's point
	row["lock_x"] = float(toll["x"])
	row["lock_y"] = float(toll["y"])
	row["lock_z"] = float(toll["z"])
	_repoint_smoke(row, rt, toll)
	if tick >= due:
		st.erase(toll_key)   # the behavior's arrive ran this tick; the toll is served


## Patch the smoke telegraph this row announced so the view draws it on the LOCKED
## point: the row's own entries only (kind "teleport", source the row's id - the
## same "row's own entry, aged by the caller" convention T-032 uses for rings).
static func _repoint_smoke(row: Dictionary, rt, toll: Dictionary) -> void:
	var id := str(row.get("id", ""))
	for t in rt.telegraphs:
		if str(t.get("kind", "")) == "teleport" and str(t.get("source", "")) == id:
			t["shape"]["cx"] = float(toll["x"])
			t["shape"]["cz"] = float(toll["z"])
