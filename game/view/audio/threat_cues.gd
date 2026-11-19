extends RefCounted
#
# The threat cue layer (PARKED.md rows 12-15; T-087's owner spec "every lethal threat's
# audio cue is learnable and precedes the attack"). The audio half of the telegraph layer
# (view/vfx/telegraph_view.gd owns one of these and plays what it returns).
#
# The schedule is DATA, never enemy ids in code: every enemy.json's
# stats.audio_cue_timing row {"event","kind","occurrence","offset_ticks","role","attack"}
# is read once. Three ways a cue becomes due:
#   1. "telegraph" rows: a sim telegraph event of that kind at tick T makes the cue due
#      at T + offset_ticks (gin's shing/whoosh at mark + 120, zone_open at + 138, nuke's
#      rocket_booster_roar on the locked ring, Claude's string_sweep on the strings
#      line, thicc ben's chime at teleport + 45). occurrence 2 is the locked ("solid")
#      variant of a two-step telegraph - nuke's ground_ring is the roster's only one;
#      occurrence 1 is the first (unlocked) one; null matches every occurrence.
#      A cue the telegraph view already sounded for the same step (its TELL_CUES map or
#      a sim "audio" event) is not sounded twice; a kind the view marks "kind:<k>" (its
#      sound rides the sim's own audio event - coil's boing) gets no offset-0 cue here.
#   2. "appear" rows: a row whose enemy has appear cues entering anim_state "spawn"
#      (address me's appearance teleports a parked row; no sim event exists for it).
#   3. the beat clock (Claude, section 3's rows "drum_hit | beats 1 and 3 ...; a quieter
#      pre-hit one beat earlier" and "wind_ping | beats 1, 2, 3 of a wind bar"): a row
#      that carries "beat_fired" and whose behavior answers _bar_kinds() is read on
#      every beat; when the NEXT beat fires a drum ring or a wind shot, the quieter
#      pre-hit of that attack's cue plays NOW - one full beat (36 ticks at 100 BPM,
#      22.5 at the Deadline's 160) before the attack leaves Claude. A new wind shot
#      (row last_shot_tick moves) plays its full-gain ping on the launch tick. The drum
#      ring's own full-gain ui_chime is the telegraph view's drum_ring tell.
#
# Clock: "step tick" = the runtime tick a step's events carry (rt.tick DURING the step;
# rt.tick after it is step tick + 1). Every logged cue carries it, so a test compares
# a cue against the attack's own step tick with no off-by-one.
#
# Pure: no nodes, no audio. log is the proof surface (headless tests read it).

static var ENEMY_ROOT := "res://content/enemies"   # static var so tests can point it at a scratch root
const PRE_HIT_GAIN := 0.5      # "a quieter pre-hit": half amplitude (-6 dB)
const LOG_MAX := 256
const APPEAR_STATE := "spawn"
const DRUM_CUE := "ui_chime"
const WIND_CUE := "notification_ping"

var enabled := true            # the negative control flips this off
var by_kind := {}              # telegraph kind -> [entry]
var by_appear := {}            # enemy id -> [entry]
var pending: Array = []        # [{cue, at, x, y, z, gain, attack, role, enemy}]
var log: Array = []            # [{cue, tick, gain, attack, role, enemy, why}], newest last
var _rows := {}                # row identity -> {"beat": int, "shot": int, "state": String}


func _init() -> void:
	load_table()


## Reads every enemy.json under ENEMY_ROOT once (stats.audio_cue_timing).
func load_table() -> void:
	by_kind = {}
	by_appear = {}
	var root := DirAccess.open(ENEMY_ROOT)
	if root == null:
		return
	var dirs: Array = Array(root.get_directories())
	dirs.sort()
	for d in dirs:
		var path := "%s/%s/enemy.json" % [ENEMY_ROOT, d]
		if not FileAccess.file_exists(path):
			continue
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (doc is Dictionary):
			continue
		var enemy := str((doc as Dictionary).get("id", d))
		var st: Variant = (doc as Dictionary).get("stats", {})
		if not (st is Dictionary):
			continue
		var timing: Variant = (st as Dictionary).get("audio_cue_timing", {})
		if not (timing is Dictionary):
			continue
		var names: Array = (timing as Dictionary).keys()
		names.sort()
		for cue in names:
			if not (timing[cue] is Dictionary):
				continue   # one corrupt row must not abort the scan for every cue after it
			var row: Dictionary = timing[cue]
			var occ: Variant = row.get("occurrence", null)
			var entry := {"cue": str(cue), "enemy": enemy,
					"offset": int(row.get("offset_ticks", 0)),
					"occurrence": -1 if occ == null else int(occ),
					"role": str(row.get("role", "")),
					"attack": "" if row.get("attack", null) == null else str(row["attack"])}
			match str(row.get("event", "")):
				"telegraph":
					var k := str(row.get("kind", ""))
					if not by_kind.has(k):
						by_kind[k] = []
					by_kind[k].append(entry)
				"appear":
					if not by_appear.has(enemy):
						by_appear[enemy] = []
					by_appear[enemy].append(entry)


## One step's raw events. `played` lists the cue names the telegraph view already
## sounded for this same step (never sounded twice). Returns the step tick the events
## carried (-1 when none carried one).
func schedule(events: Array, played: Array) -> int:
	var step := -1
	for e in events:
		if e.has("tick"):
			step = maxi(step, int(e["tick"]))
		if not enabled or str(e.get("e", "")) != "telegraph":
			continue
		var kind := str(e.get("kind", ""))
		if not by_kind.has(kind):
			continue
		var shape: Dictionary = e.get("shape", {})
		var occ := 2 if bool(shape.get("solid", false)) else 1
		var t := int(e.get("tick", 0))
		var pos := _pos_of(shape)
		for entry in by_kind[kind]:
			var want := int(entry["occurrence"])
			if want != -1 and want != occ:
				continue
			if int(entry["offset"]) == 0 and (played.has(str(entry["cue"]))
					or played.has("kind:" + kind)):
				continue   # the tell (or the sim's own audio event) already carries it
			_queue(entry, t + int(entry["offset"]), pos, 1.0, "telegraph:" + kind)
	return step


## Pops (and logs) every pending cue due at or before step tick `now`, oldest first.
func due(now: int) -> Array:
	var out: Array = []
	var keep: Array = []
	for p in pending:
		if int(p["at"]) <= now:
			out.append(p)
		else:
			keep.append(p)
	pending = keep
	out.sort_custom(func(a, b): return int(a["at"]) < int(b["at"]))
	for p in out:
		_log(p, int(p["at"]))
	return out


## The live enemy rows (rt.enemies, read only) after step tick `now`: the appear
## transitions and the beat clock. Returns the cues due now (already logged).
func watch_rows(enemies: Array, now: int) -> Array:
	var out: Array = []
	var seen := {}
	for row in enemies:
		var key := _row_key(row)
		seen[key] = true
		var prev: Dictionary = _rows.get(key, {})
		var st := str(row.get("anim_state", ""))
		var enemy := str(row.get("id", ""))
		if enabled and by_appear.has(enemy) and st == APPEAR_STATE \
				and str(prev.get("state", "")) != APPEAR_STATE:
			var pos := Vector3(float(row.get("x", 0.0)), float(row.get("y", 0.0)),
					float(row.get("z", 0.0)))
			for entry in by_appear[enemy]:
				_queue(entry, now + int(entry["offset"]), pos, 1.0, "appear")
		var cur := {"state": st, "beat": int(row.get("beat_fired", -999)),
				"shot": int(row.get("last_shot_tick", -1))}
		if enabled and row.has("beat_fired"):
			_beat_clock(row, prev, cur, now)
		_rows[key] = cur
	for k in _rows.keys():
		if not seen.has(k):
			_rows.erase(k)
	out.append_array(due(now))
	return out


## The beat clock: on every beat boundary (and on first sight) look ONE beat ahead with
## the behavior's own bar rule; the next beat's drum ring / wind shot gets its quieter
## pre-hit now. A new wind shot gets its full ping on the launch tick.
func _beat_clock(row: Dictionary, prev: Dictionary, cur: Dictionary, now: int) -> void:
	var beh: Variant = row.get("behavior", null)
	if beh == null or not (beh as Object).has_method("_bar_kinds"):
		return
	var consts: Dictionary = (beh as Object).get_script().get_script_constant_map()
	var bar := int(consts.get("BAR_BEATS", 4))
	var pos := Vector3(float(row.get("x", 0.0)), float(row.get("y", 0.0)),
			float(row.get("z", 0.0)))
	if not prev.is_empty() and int(cur["shot"]) != int(prev.get("shot", -1)) \
			and int(cur["shot"]) >= 0:
		_queue({"cue": WIND_CUE, "enemy": str(row.get("id", "")), "role": "on_attack",
				"attack": "wind_shot_kill"}, now, pos, 1.0, "launch")
	if not prev.is_empty() and int(cur["beat"]) == int(prev.get("beat", -999)):
		return
	var nxt := int(cur["beat"]) + 1
	var kinds: Array = (beh as Object).call("_bar_kinds", row, nxt / bar)
	var lead := _ticks_to_beat(beh, row, nxt)
	var enemy := str(row.get("id", ""))
	if kinds.has("drums") and (consts.get("DRUM_BEATS", []) as Array).has(nxt % bar):
		_queue({"cue": DRUM_CUE, "enemy": enemy, "role": "pre_hit",
				"attack": "drum_ring_kill"}, now, pos, PRE_HIT_GAIN, "pre_hit", now + lead)
	if kinds.has("wind") and (consts.get("WIND_BEATS", []) as Array).has(nxt % bar):
		_queue({"cue": WIND_CUE, "enemy": enemy, "role": "pre_hit",
				"attack": "wind_shot_kill"}, now, pos, PRE_HIT_GAIN, "pre_hit", now + lead)


## Ticks from now until beat `n` fires (beat n fires when beat_pos crosses n + 1),
## at the row's current tempo.
static func _ticks_to_beat(beh: Variant, row: Dictionary, n: int) -> int:
	var bpm := 100.0
	if (beh as Object).has_method("_bpm"):
		bpm = float((beh as Object).call("_bpm", row))
	var per_tick := maxf(bpm / 3600.0, 1e-6)
	var left := float(n + 1) - float(row.get("beat_pos", 0.0))
	return maxi(int(ceil(left / per_tick - 1e-9)), 1)


func _queue(entry: Dictionary, at: int, pos: Vector3, gain: float, why: String,
		attack_at: int = -1) -> void:
	pending.append({"cue": str(entry["cue"]), "at": at, "x": pos.x, "y": pos.y, "z": pos.z,
			"gain": gain, "attack": str(entry.get("attack", "")),
			"role": str(entry.get("role", "")), "enemy": str(entry.get("enemy", "")),
			"why": why, "attack_at": attack_at})


func _log(p: Dictionary, tick: int) -> void:
	log.append({"cue": p["cue"], "tick": tick, "gain": p["gain"], "attack": p["attack"],
			"role": p["role"], "enemy": p["enemy"], "why": p["why"],
			"attack_at": p.get("attack_at", -1)})
	if log.size() > LOG_MAX:
		log.pop_front()


## A row's identity across steps (rows are never copied): its rng object's instance id
## when it has one, else id + copy + spawn tick.
static func _row_key(row: Dictionary) -> String:
	var r: Variant = row.get("rng", null)
	if r is Object:
		return "o%d" % (r as Object).get_instance_id()
	return "%s#%d@%d" % [str(row.get("id", "")), int(row.get("copy_index", 0)),
			int(row.get("spawn_tick", 0))]


static func _pos_of(shape: Dictionary) -> Vector3:
	return Vector3(float(shape.get("cx", shape.get("fx", 0.0))),
			float(shape.get("y0", shape.get("fy", 0.0))),
			float(shape.get("cz", shape.get("fz", 0.0))))
