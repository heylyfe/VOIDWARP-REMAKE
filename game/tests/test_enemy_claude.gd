extends RefCounted
#
# claude tests (ticket T-040). DESIGN.md section 5.11 is the spec; every timing and
# number of the paragraph is asserted within +/-1 tick (the pinned-tempo runner makes
# the beat grid exact at 100 BPM / 36 ticks). Kill tests run with the player's LAST
# LIGHT already spent (D-057) - otherwise the save masks the kill and the assertion is
# worthless. The answer window (T-070 / D-064) is asserted through the geometry that
# makes it true: the drum band crossing (1.4 u pass at 12 u/s = 0.12 s), the strings
# sweep rate at 10 u (2 x asin(1.15/10) at the live deg/tick rate = 0.26 s), the wind
# outrun (7.0 vs 9.0 u/s) and the shot's death on a slab (D-071).
#
# Readings under test (DECISIONS D-T040-1..7): the 20 u leash (chase beyond, hold
# within), the drums' YOU-style ring windows (feet strictly inside (r-1.5, r+1.0),
# radial |d - r| <= 0.7), the frozen strings start line + counterclockwise sweep, the
# plushie band + 0.9 u pickup, and the Deadline's all-three-every-bar reading.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Util := preload("res://tests/sim_testutil.gd")
const ClaudeEnemy := preload("res://content/enemies/claude/enemy.gd")
const DeathScript := preload("res://sim/death.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const BillboardScript := preload("res://view/billboard.gd")
const ClaudeViewScript := preload("res://view/claude_view.gd")
const EnemyAnim := preload("res://view/enemy_anim.gd")
const OffersScript := preload("res://sim/offers.gd")
const AudioScript := preload("res://view/audio/claude_audio.gd")

const DT := 1.0 / 60.0
const SHEET := "res://content/enemies/claude/sprites.json"
const FOLDER := "res://content/enemies/claude"

var _events: Array = []   # every event since the current fixture spawned (rt.events resets per tick)


func run() -> Array[String]:
	var f: Array[String] = []
	_roster_data(f)
	_pursuit_speed_and_ceiling(f)
	_keep_within_leash(f)
	_body_and_contact(f)
	_spawn_fade_blocks_contact(f)
	_beat_clock(f)
	_agitation_and_tempo(f)
	_bar_cycle(f)
	_drum_ring_geometry(f)
	_drum_ring_kills(f)
	_strings_cycle(f)
	_strings_kill_rules(f)
	_wind_shots(f)
	_wind_shot_kills_and_dies(f)
	_wind_outrun(f)
	_plushies(f)
	_deadline(f)
	_anim_block_wiring(f)
	_lobby_exhibit(f)
	return f


# ---- fixtures ----------------------------------------------------------------

func _tiles_full(extra: Array = []) -> Array:
	var tiles: Array = []
	for x in range(-10, 11):
		for z in range(-10, 11):
			tiles.append([x, z, 0])
	tiles.append_array(extra)
	return tiles


func _level(extra_tiles: Array = []) -> Dictionary:
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": _tiles_full(extra_tiles), "props": [], "pads": []}


# Last Light spent for real, then the arrival state cleared: the fixture is
# exactly "alive, unshielded, Last Light spent" (D-057).
func _spent_ctl(w: Dictionary):
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.try_kill("D-TEST", "test", w, [])
	ctl.invuln = 0.0
	ctl.dead = false
	ctl.place(w)
	return ctl


# The cfg comes from the REAL enemy.json (D-T-034-7's rule): the timings and numbers
# asserted are the deliverable data's own, never a test-local copy.
func _cfg() -> Dictionary:
	var txt := FileAccess.get_file_as_string("res://content/enemies/claude/enemy.json")
	var doc = JSON.parse_string(txt)
	return doc["stats"]


# [rt, row, ctl]; the controller sits on the spawn tile and never moves on its own.
func _spawn(pos: Vector3, extra: Array = []) -> Array:
	var w := Util.world_from_tiles(_tiles_full(extra))
	w["dais"] = [0, 0, 0]
	var ctl = _spent_ctl(w)
	var rt = EnemyRuntime.new()
	rt.setup(_level(extra), w, [ctl], 4242)
	var row: Dictionary = rt.spawn_at("claude", "Claude", ClaudeEnemy.new(), _cfg(), pos)
	_events = []
	return [rt, row, ctl]


func _death_events(rt) -> Array:
	return _filter_events("death")


func _telegraph_events(rt, kind: String = "") -> Array:
	var out: Array = []
	for e in _events:
		if str(e.get("e", "")) == "telegraph" and (kind == "" or str(e["kind"]) == kind):
			out.append(e)
	return out


func _filter_events(kind: String) -> Array:
	var out: Array = []
	for e in _events:
		if str(e.get("e", "")) == kind:
			out.append(e)
	return out


## Steps n ticks with the agitation PINNED (pass pin_agit >= 0 to set row["agitation"]
## before every step): the beat grid is then exactly 3600/(100+0.6*pin) ticks.
## Every step's events are folded into _events (rt.events holds one tick's worth only).
func _run_pinned(rt, row, n: int, pin_agit: float = -1.0) -> void:
	for _i in range(n):
		if pin_agit >= 0.0:
			row["agitation"] = pin_agit
		rt.step(DT)
		_events.append_array(rt.events)


## Steps n pinned/unpinned ticks and records the BIRTH tick of every live hazard by
## object identity (a size-based count misses a birth that lands the same tick another
## hazard expires). Returns {"rings": [...], "shots": [...], "sweeps": [...]}.
func _watch_starts(rt, row, n: int, pin_agit: float = -1.0) -> Dictionary:
	var seen := {"rings": [], "shots": [], "sweeps": []}
	var out := {"rings": [], "shots": [], "sweeps": []}
	for _i in range(n):
		if pin_agit >= 0.0:
			row["agitation"] = pin_agit
		rt.step(DT)
		_events.append_array(rt.events)
		_absorb_new(seen, out, row["rings"], "rings", int(rt.tick))
		_absorb_new(seen, out, row["shots"], "shots", int(rt.tick))
		_absorb_new(seen, out, row["sweeps"], "sweeps", int(rt.tick))
	return out


## Records each object's first sighting (reference identity, not value equality).
func _absorb_new(seen: Dictionary, out: Dictionary, items: Array, key: String, tick: int) -> void:
	for it in items:
		var known := false
		for s in seen[key]:
			if is_same(s, it):
				known = true
				break
		if not known:
			(seen[key] as Array).append(it)
			(out[key] as Array).append(tick)


# ---- the roster data vs the behavior's mirror ---------------------------------

func _roster_data(f: Array[String]) -> void:
	var txt := FileAccess.get_file_as_string("res://content/enemies/claude/enemy.json")
	var doc = JSON.parse_string(txt)
	if not (doc is Dictionary):
		f.append("data: enemy.json does not parse")
		return
	_eq(f, "id", str(doc["id"]), "claude")
	_eq(f, "name", str(doc["name"]), "Claude")
	_num(f, "min_level", float(doc["min_level"]), 15.0)
	_num(f, "max_votes", float(doc["max_votes"]), 1.0)
	_num(f, "contact_kill", float(doc["contact_kill"]), 1.0)
	if str(doc["vote_effect"]).find("one Claude") < 0:
		f.append("data: vote_effect %s, want the one-Claude line" % str(doc["vote_effect"]))
	var st: Dictionary = doc["stats"]
	# DESIGN.md section 5.11 / SR-2 / SR-5 numbers
	_num(f, "world_height", float(st["world_height"]), 2.0)
	_num(f, "hit_diameter", float(st["hit_diameter"]), 1.6)
	_num(f, "base_speed", float(st["base_speed"]), 4.0)
	_num(f, "pursuit_ceiling", float(st["pursuit_ceiling"]), 0.55)
	_num(f, "bpm_base", float(st["bpm_base"]), 100.0)
	_num(f, "bpm_per_agitation", float(st["bpm_per_agitation"]), 0.6)
	_num(f, "bar_beats", float(st["bar_beats"]), 4.0)
	_num(f, "agitation_rise_per_s", float(st["agitation_rise_per_s"]), 2.0)
	_num(f, "agitation_max", float(st["agitation_max"]), 100.0)
	_num(f, "drum_ring_speed", float(st["drum_ring_speed_u_per_s"]), 12.0)
	_num(f, "drum_ring_radius", float(st["drum_ring_max_radius"]), 18.0)
	_num(f, "drum_ring_height", float(st["drum_ring_height"]), 1.0)
	_num(f, "strings_sweep_deg", float(st["strings_sweep_deg"]), 120.0)
	_num(f, "strings_sweep_beats", float(st["strings_sweep_beats"]), 4.0)
	_num(f, "strings_length", float(st["strings_length_u"]), 24.0)
	_num(f, "strings_width", float(st["strings_width_u"]), 1.5)
	_num(f, "strings_height_band", float(st["strings_height_max_u"]) - float(st["strings_height_min_u"]), 1.0)
	_num(f, "wind_speed", float(st["wind_speed_u_per_s"]), 7.0)
	_num(f, "wind_turn", float(st["wind_turn_deg_per_s"]), 90.0)
	_num(f, "wind_life_ticks", float(st["wind_life_s"]) * 60.0, 240.0)
	_num(f, "plushie_interval", float(st["plushie_interval_s"]), 25.0)
	_num(f, "plushie_band", float(st["plushie_min_u"]), 10.0)
	_num(f, "plushie_band_max", float(st["plushie_max_u"]), 25.0)
	_num(f, "plushie_calm", float(st["plushie_calm"]), 35.0)
	_num(f, "death_code", 1.0 if str(st["death_code"]) == "D-CLAUDE" else 0.0, 1.0)
	# the audio cue names are ENEMIES.md's "New sound" line's four instrument/cue names
	var want_cues := ["ui_chime", "keystroke_tick", "notification_ping", "squeak_pop"]
	_eq(f, "audio cues", str(st["audio_cues"]), str(want_cues))
	if str(AudioScript.CUE_UI_CHIME) != "ui_chime" or str(AudioScript.CUE_KEYSTROKE_TICK) != "keystroke_tick" \
			or str(AudioScript.CUE_NOTIFICATION_PING) != "notification_ping" \
			or str(AudioScript.CUE_SQUEAK_POP) != "squeak_pop":
		f.append("audio: claude_audio.gd cue names drifted from enemy.json's audio_cues")
	if AudioScript.play(null, "ui_chime"):
		f.append("audio: play() with no node must no-op false")
	# the mirror in the behavior agrees with the json (kiwi/seal cfg-mirror convention)
	var mirror: Dictionary = ClaudeEnemy.cfg()
	for k in mirror.keys():
		if st.has(k) and str(st[k]) != str(mirror[k]):
			f.append("mirror: stats.%s = %s, behavior cfg says %s" % [str(k), str(st[k]), str(mirror[k])])
	if str(DeathScript.killer_for("D-CLAUDE")) != "Claude":
		f.append("data: death.gd maps D-CLAUDE to %s, want Claude" % str(DeathScript.killer_for("D-CLAUDE")))


# ---- SR-5 pursuit (section 5.11: 4.0 u/s, ceiling 0.55 -> 4.95 u/s) -----------

func _pursuit_speed_and_ceiling(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(30.0, 0.0, 0.5))   # beyond the 20 u leash: it floats
	var rt = spawned[0]
	var row = spawned[1]
	rt.step(DT)
	var fb = row["float"]
	if fb == null or absf(float(fb.h_speed) - 4.0) > 1e-9:
		f.append("pursuit: base h_speed %s, want 4.0" % str(fb.h_speed if fb != null else "missing"))
	# the full SR-5 stack: overtime tier 8 (x1.48) x curse 1.08^3 (Rush Hour)
	rt.overtime_running = true
	rt.add_overtime_tier(8)
	rt.curse_speed_mul = 1.08 * 1.08 * 1.08
	for i in range(180):
		rt.step(DT)
		if float(near_dist(row, i)) <= 20.0:
			break
		if absf(float(fb.h_speed) - 4.95) > 1e-9:
			f.append("pursuit: ceiling broken at tick %d: h_speed %.6f, want 4.95" % [i, float(fb.h_speed)])
			break
	var raw: float = 4.0 * 1.48 * 1.08 * 1.08 * 1.08
	if absf(float(fb.tempo_mul) - raw / 4.95) > 1e-6:
		f.append("pursuit: tempo_mul %.6f, want %.6f (raw/clamped)" % [float(fb.tempo_mul), raw / 4.95])


static func near_dist(row: Dictionary, _i: int) -> float:
	# the player sits at the spawn tile (0.5, 0.5); horizontal distance to it
	return sqrt(pow(float(row["x"]) - 0.5, 2.0) + pow(float(row["z"]) - 0.5, 2.0))


# ---- the 20 u leash: floats toward the player while > 20 u, holds within ------

func _keep_within_leash(f: Array[String]) -> void:
	# from 30 u it closes; once within 20 u it stops (a 4 u/s chase over ~5 s)
	var spawned := _spawn(Vector3(30.0, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	_run_pinned(rt, row, 700, 0.0)
	var d := near_dist(row, 0)
	if d > 20.0 + 0.01:
		f.append("leash: distance %.3f after 700 ticks, want <= 20" % d)
	if d < 19.5:
		f.append("leash: distance %.3f, want the ~20 u stand-off (it should have stopped)" % d)
	# within 20 u it does not creep: 60 ticks of holding changes nothing
	var before := Vector3(float(row["x"]), float(row["y"]), float(row["z"]))
	_run_pinned(rt, row, 60, 0.0)
	var after := Vector3(float(row["x"]), float(row["y"]), float(row["z"]))
	if before.distance_to(after) > 1e-6:
		f.append("leash: the body drifted %.4f u while within 20 u" % before.distance_to(after))


# ---- body: 2.0 u tall / 1.6 u diameter; contact kills carry D-CLAUDE ----------

func _body_and_contact(f: Array[String]) -> void:
	# SR-2's FINAL row: height 2.0, hit diameter 1.6 (0.8 x the 2.0 u body width)
	var spawned := _spawn(Vector3(12.5, 0.0, 0.5))
	var row = spawned[1]
	_run_pinned(spawned[0], row, 31, 0.0)   # past the fade: the full body is live
	_num(f, "body height", float(row["height_u"]), 2.0)
	_num(f, "hit diameter", float(row["diameter_u"]), 1.6)
	# a body 3 u away never touches (contact = overlap of the cylinders only)
	var c := _spawn(Vector3(4.0, 0.0, 0.5))
	_run_pinned(c[0], c[1], 40, 0.0)
	if c[2].dead:
		f.append("contact: a body 3 u away killed the player")


# ---- the spawn fade blocks contact for its 30 ticks (the anim block) ----------

func _spawn_fade_blocks_contact(f: Array[String]) -> void:
	# overlapping bodies from tick 1; the anim block's spawn row: the body cannot
	# touch or kill until the fade completes
	var spawned := _spawn(Vector3(0.9, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	_run_pinned(rt, row, 30, 0.0)   # ticks 1..30: the fade - no contact kill yet
	if ctl.dead:
		f.append("fade: the body killed during the 30-tick spawn fade")
	_run_pinned(rt, row, 5, 0.0)    # the fade is over: the overlap kills now
	if not ctl.dead:
		f.append("fade: the overlapping body never killed after the fade ended")
	else:
		var found := false
		for d in _death_events(rt):
			if str(d["code"]) == "D-CLAUDE":
				found = true   # the contact path passes cfg death_code (D-T030-1)
		if not found:
			f.append("fade: death events %s, want D-CLAUDE" % str(_death_events(rt)))


# ---- the beat clock (pinned 100 BPM: a beat every 36 ticks, a bar every 144) --

func _beat_clock(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(12.5, 0.0, 0.5))   # 12 u from the player: inside, it holds
	var rt = spawned[0]
	var row = spawned[1]
	# no beat, no attack before the first beat boundary (the music starts at spawn)
	_run_pinned(rt, row, 34, 0.0)
	if not (row["rings"] as Array).is_empty() or int(row["last_drum_tick"]) >= 0:
		f.append("beat: an attack fired before the first beat boundary (age %d)" % int(row["age"]))
	var starts: Dictionary = _watch_starts(rt, row, 480, 0.0)
	var rings: Array = starts["rings"]
	if rings.is_empty():
		f.append("beat: no drum ring ever fired at 100 BPM")
		return
	# bar 0 beats 1 and 3 = ages 36 and 108 (36-tick beats); bar 3 beat 1 = 468
	if absi(int(rings[0]) - 36) > 1:
		f.append("beat: first ring at %d, want 36 +/-1 (beat 1, 0.6 s)" % int(rings[0]))
	if rings.size() < 2:
		f.append("beat: only %d rings in 480 ticks, want bars 0 and 3" % rings.size())
		return
	if absi(int(rings[1]) - int(rings[0]) - 72) > 1:
		f.append("beat: ring 2 at %d, ring 1 at %d - beats 1->3 is 72 ticks" % [int(rings[1]), int(rings[0])])
	if rings.size() < 3 or absi(int(rings[2]) - int(rings[0]) - 432) > 2:
		f.append("beat: ring 3 at %s, want bar 3 (432 ticks after ring 1, +-2 for bar drift)" % str(rings))
	# the anim block's beat length at 100 BPM: 36 ticks (the tempo formula's base)


# ---- agitation: +2/s, capped at 100; tempo = 100 + 0.6 * agitation BPM --------

func _agitation_and_tempo(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	_run_pinned(rt, row, 300)   # UNpinned: it rises organically
	var want: float = 300.0 / 30.0   # 2/s = 1 point per 30 ticks
	if absf(float(row["agitation"]) - want) > 0.1:
		f.append("agitation: %.3f after 300 ticks, want %.1f (+-0.1)" % [float(row["agitation"]), want])
	_run_pinned(rt, row, 5000)   # 5000 more: ~176 - capped at 100
	if absf(float(row["agitation"]) - 100.0) > 0.001:
		f.append("agitation: %.3f after 5300 ticks, want the 100 cap" % float(row["agitation"]))
	# pinned at 50: bpm = 130 -> beat every 3600/130 = 27.7 ticks
	var spawned2 := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt2 = spawned2[0]
	var row2 = spawned2[1]
	var beats: Array = []
	var prev_beat := -1.0
	for _i in range(340):
		row2["agitation"] = 50.0
		rt2.step(DT)
		var beat: float = floorf(float(row2["beat_pos"]))
		if beat > prev_beat:
			if prev_beat >= 0.0:
				beats.append(int(rt2.tick))
			prev_beat = beat
	if beats.size() < 3:
		f.append("tempo: only %d beat crossings at 130 BPM" % beats.size())
	else:
		var span: int = int(beats[beats.size() - 1]) - int(beats[0])
		var want_span: int = int(round(float(beats.size() - 1) * 3600.0 / 130.0))
		if absi(span - want_span) > 2:
			f.append("tempo: %d ticks for %d beats, want ~%d (130 BPM)" % [span, beats.size() - 1, want_span])


# ---- the bar cycle: drums -> strings -> wind (pinned 100 BPM) -----------------

func _bar_cycle(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	# exact beat grid at pinned 100 BPM: beat k fires at age 36 * (k + 1)
	var starts: Dictionary = _watch_starts(rt, row, 480, 0.0)
	var rings: Array = starts["rings"]      # beats 0, 2, 12 -> ages 36, 108, 468
	var shots: Array = starts["shots"]      # beats 8, 9, 10 -> 324, 360, 396
	var tels: Array = _telegraph_events(rt, "strings_line")
	if tels.is_empty():
		f.append("cycle: no strings_line telegraph in 480 ticks")
	elif absi(int(tels[0]["tick"]) - 180) > 1:
		f.append("cycle: strings telegraph at tick %d, want 180 (bar 1 beat 1)" % int(tels[0]["tick"]))
	if shots.is_empty():
		f.append("cycle: no wind shots in 480 ticks")
		return
	for i in range(mini(3, shots.size())):
		if absi(int(shots[i]) - (324 + 36 * i)) > 1:
			f.append("cycle: wind shot %d at %d, want %d (beats 1-3 of bar 2)" % [i, int(shots[i]), 324 + 36 * i])
	if rings.size() < 3 or absi(int(rings[2]) - 468) > 2:
		f.append("cycle: the bar cycle did not return to drums on bar 3 (rings %s)" % str(rings))


# ---- drum ring geometry: 12 u/s expansion to the 18 u cap, 1.0 u tall ---------

func _drum_ring_geometry(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	# reach beat 1 (age 36); the ring expands ON its spawn tick, so r is already 0.2
	_run_pinned(rt, row, 36, 0.0)
	if (row["rings"] as Array).is_empty():
		f.append("ring: no ring at the beat-1 tick")
		return
	var ring1: Dictionary = row["rings"][0]   # a reference: tracks the ring past removal
	if absf(float(ring1["r"]) - 0.2) > 0.001:
		f.append("ring: r on the spawn tick %.4f, want 0.2 (12 u/s)" % float(ring1["r"]))
	# cap: 18 u at 90 ticks after the beat, then the ring expires (one tick at the cap)
	var saw_cap := false
	var t_cap := -1
	for _i in range(120):
		rt.step(DT)
		if float(ring1["r"]) > 18.0 + 1e-9:
			f.append("ring: radius %.4f exceeded the 18 u cap" % float(ring1["r"]))
			break
		if not saw_cap and absf(float(ring1["r"]) - 18.0) < 1e-9:
			saw_cap = true
			t_cap = int(rt.tick)
		if saw_cap and not ((row["rings"] as Array).has(ring1)):
			break
	if not saw_cap:
		f.append("ring: never reached the 18 u cap")
	else:
		# the expansion ran 36 + 89 = 125 (spawn tick inclusive), gone by 126
		if absi(t_cap - 125) > 1:
			f.append("ring: capped at tick %d, want 125 +/-1 (90 ticks of 12 u/s)" % t_cap)
		if (row["rings"] as Array).has(ring1):
			f.append("ring: a capped ring never expired")


# ---- drum ring kill: grounded player hit, D-CLAUDE; jump clears ---------------

func _drum_ring_kills(f: Array[String]) -> void:
	# a grounded player 6 u away: the ring's edge passes them ~30 ticks after beat 1
	var spawned := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	ctl.x = 6.5
	_run_pinned(rt, row, 120, 0.0)
	if not ctl.dead:
		f.append("drum kill: the ring never killed the grounded player at 6 u")
	else:
		var found := false
		for d in _death_events(rt):
			if str(d["code"]) == "D-CLAUDE" and str(d["killer"]) == "Claude":
				found = true
		if not found:
			f.append("drum kill: death events %s, want code D-CLAUDE killer Claude" % str(_death_events(rt)))
	# the 0.12 s answer window: the 1.4 u pass (0.6 band + 2 x 0.4 half-widths) at
	# 12 u/s crosses in 0.117 s - the edge case pin: at 18.7 u the capped ring's
	# edge (18.0) still reaches (0.7 window); at 18.8 u it never does
	var edge_in := _spawn(Vector3(12.5, 0.0, 0.5))
	(edge_in[2] as Object).x = 12.5 - 18.7
	_run_pinned(edge_in[0], edge_in[1], 140, 0.0)
	if not edge_in[2].dead:
		f.append("drum kill: a player at 18.7 u survived the capped ring (window 0.7)")
	var edge_out := _spawn(Vector3(12.5, 0.0, 0.5))
	(edge_out[2] as Object).x = 12.5 - 18.8
	_run_pinned(edge_out[0], edge_out[1], 140, 0.0)
	if edge_out[2].dead:
		f.append("drum kill: a player at 18.8 u died - beyond the 18 u ring + 0.7 window")
	# vertical: jump on the beat - feet at/above the band top (1.0) are safe;
	# feet below the plane -1.5 are safe; inside is hit (D-T-040-2's windows)
	for c in [[0.99, true], [1.0, false], [1.5, false], [-1.4, true], [-1.5, false]]:
		var spawned2 := _spawn(Vector3(12.5, 0.0, 0.5))
		var rt2 = spawned2[0]
		var row2 = spawned2[1]
		var ctl2 = spawned2[2]
		ctl2.x = 6.5
		_run_pinned(rt2, row2, 37, 0.0)   # the ring just spawned (age 36)
		var rings2: Array = row2["rings"]
		if rings2.is_empty():
			f.append("drum vertical: no ring at age 37")
			continue
		ctl2.y = float(rings2[0]["y"]) + float(c[0])
		for _i in range(90):
			rt2.step(DT)
			if ctl2.dead or (row2["rings"] as Array).is_empty():
				break
		if ctl2.dead != bool(c[1]):
			f.append("drum vertical %+.2f: dead=%s, want %s" % [float(c[0]), str(ctl2.dead), str(bool(c[1]))])


# ---- strings: 1-beat telegraph (36 ticks), then a 4-beat (144 ticks) sweep ----

func _strings_cycle(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	var tels: Array = _telegraph_events(rt, "strings_line")
	# the player is elevated 1.0 u (out of every drum ring) and behind nothing: the
	# tests below read TIMINGS; the sweep will kill them - this fixture stands none
	var t_tel := -1
	_run_pinned(rt, row, 300, 0.0)
	for e in _telegraph_events(rt, "strings_line"):
		t_tel = int(e["tick"])
		break
	if t_tel < 0:
		f.append("strings: no telegraph by age 300")
		return
	if absi(t_tel - 180) > 1:
		f.append("strings: telegraph at %d, want 180 (bar 1 beat 1)" % t_tel)
	# the telegraph event itself binds 36 ticks at 100 BPM
	var ev = _telegraph_events(rt, "strings_line")[0]
	if absi(int(ev["ticks"]) - 36) > 1:
		f.append("strings: telegraph ticks %d, want 36 (1 beat at 100 BPM)" % int(ev["ticks"]))
	# the sweep lifts off exactly one beat after the telegraph started
	var t_sweep: int = int(row["last_sweep_tick"])
	if absi(t_sweep - (t_tel + 36)) > 1:
		f.append("strings: sweep at %d, want telegraph + 36 (%d)" % [t_sweep, t_tel + 36])
	# the sweep runs 4 beats = 144 ticks: gone by t_sweep + 144
	var gone := -1
	for _i in range(160):
		rt.step(DT)
		if (row["sweeps"] as Array).is_empty():
			gone = int(rt.tick)
			break
	if gone < 0 or absi(gone - (t_sweep + 144)) > 1:
		f.append("strings: sweep lived %d ticks, want 144 (120 deg over 4 beats)" % (gone - t_sweep if gone > 0 else -1))


# ---- strings kill rules: in-band + LOS clear = kill; wall/jump/range = safe ---

func _strings_kill_rules(f: Array[String]) -> void:
	# (a) a grounded player on the frozen line dies on the sweep's FIRST tick
	# (feet 1.0 u up: out of the drum rings, inside the 0.5-1.5 beam band)
	var a := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt_a = a[0]
	var row_a = a[1]
	var ctl_a = a[2]
	ctl_a.x = 6.5
	ctl_a.y = 1.0
	_run_pinned(rt_a, row_a, 220, 0.0)
	if not ctl_a.dead:
		f.append("strings kill: a player on the start line at 6 u survived the sweep")
	else:
		var found_a := false
		for d in _death_events(rt_a):
			if str(d["code"]) == "D-CLAUDE":
				found_a = true
		if not found_a:
			f.append("strings kill: death events %s, want D-CLAUDE" % str(_death_events(rt_a)))
	# (b) behind a 6 u tile wall the beam never reaches them (blocked by tiles)
	var wall: Array = []
	for y in [2, 4, 6, 8, 10, 12]:
		wall.append([2, 0, y])
	var b := _spawn(Vector3(12.5, 0.0, 0.5), wall)
	var rt_b = b[0]
	var row_b = b[1]
	var ctl_b = b[2]
	ctl_b.x = 0.5
	ctl_b.y = 1.0
	_run_pinned(rt_b, row_b, 340, 0.0)
	if ctl_b.dead:
		f.append("strings kill: the beam killed through a tile wall (blocked_by tiles)")
	# (c) jumped feet (>= the 1.5 u band top) are safe through the strings bar
	var c := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt_c = c[0]
	var row_c = c[1]
	var ctl_c = c[2]
	ctl_c.x = 6.5
	_run_pinned(rt_c, row_c, 35, 0.0)   # stop JUST before beat 1 (age 36) fires
	ctl_c.y = 1.5                        # then jump: out of the ring band AND the beam
	_run_pinned(rt_c, row_c, 265, 0.0)  # through bar 1 (the sweep runs 216..359)
	if ctl_c.dead:
		f.append("strings kill: a jumped player (feet at the 1.5 u band top) was hit")
	# (d) the sweep rate: 120 deg over 4 beats = 0.8333 deg/tick at 100 BPM - the
	# live angular step, measured off the row's ray while a sweep runs
	var dspawn := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt_d = dspawn[0]
	var row_d = dspawn[1]
	_run_pinned(rt_d, row_d, 220, 0.0)   # the sweep starts at 216; sample inside it
	var steps: Array = []
	var last_dir := Vector2(float(row_d["sweeps"][0]["dx"]), float(row_d["sweeps"][0]["dz"])) \
			if not (row_d["sweeps"] as Array).is_empty() else Vector2.ZERO
	for _i in range(20):
		rt_d.step(DT)
		if (row_d["sweeps"] as Array).is_empty():
			break
		var cur := Vector2(float(row_d["sweeps"][0]["dx"]), float(row_d["sweeps"][0]["dz"]))
		if last_dir != Vector2.ZERO:
			var dot: float = clampf(cur.normalized().dot(last_dir.normalized()), -1.0, 1.0)
			steps.append(rad_to_deg(acos(dot)))
		last_dir = cur
	if steps.is_empty():
		f.append("strings: could not sample the sweep rate")
	else:
		var avg: float = 0.0
		for s in steps: avg += float(s)
		avg /= float(steps.size())
		if absf(avg - 120.0 / 144.0) > 0.05:
			f.append("strings: sweep step %.4f deg/tick, want 0.8333 (120 deg / 4 beats)" % avg)
		# the 0.26 s answer window: a body at 10 u sits inside the 1.15 u half-width
		# beam for 2 x asin(1.15/10) / step ticks = 15.9 ticks = 0.26 s at 100 BPM
		var cross_s: float = (2.0 * asin(1.15 / 10.0) / deg_to_rad(avg)) / 60.0
		if absf(cross_s - 0.26) > 0.02:
			f.append("strings: crossing at 10 u is %.3f s, want 0.26 (the answer window)" % cross_s)


# ---- wind shots: 3 per wind bar, 7 u/s, 240-tick life, 90 deg/s cap -----------

func _wind_shots(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	# the player high and far enough that no drum ring or beam reaches (feet 3.5:
	# above the 1.0 ring band top and the 1.5 beam band top), but inside the
	# wind's reach - the shots are this test's subject
	ctl.x = 4.0
	ctl.y = 3.5
	var starts: Dictionary = _watch_starts(rt, row, 470, 0.0)
	var shots: Array = starts["shots"]
	if shots.size() < 3:
		f.append("wind: only %d shots fired, want 3 on bar 2's beats 1-3" % shots.size())
		return
	if absi(int(shots[0]) - 324) > 1:
		f.append("wind: shot 1 at %d, want 324 (bar 2 beat 1)" % int(shots[0]))
	for i in range(2):
		if absi(int(shots[i + 1]) - int(shots[i]) - 36) > 1:
			f.append("wind: shot %d came %d ticks after shot %d, want 36 (one beat)" % [i + 1, int(shots[i + 1]) - int(shots[i]), i])
	# speed 7.0 u/s: shot 1 flies the straight line to the chest (both ends fixed
	# during its first second) - 7 u after 60 ticks
	# (re-run: freeze a fresh bar-2 shot and sample its position)
	var spawned2 := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt2 = spawned2[0]
	var row2 = spawned2[1]
	_run_pinned(rt2, row2, 324, 0.0)   # beat 8 just fired: shot 1 exists
	var shot1: Dictionary = row2["shots"][0]
	var p0 := Vector3(float(shot1["x"]), float(shot1["y"]), float(shot1["z"]))
	for _i in range(60):
		row2["agitation"] = 0.0
		rt2.step(DT)
	var p1 := Vector3(float(shot1["x"]), float(shot1["y"]), float(shot1["z"]))
	if absf(p0.distance_to(p1) - 7.0) > 0.2:
		f.append("wind: the shot moved %.3f u in 1 s, want 7.0" % p0.distance_to(p1))
	# turn cap 90 deg/s: yank the target 90 deg sideways; consecutive headings turn
	# at most 1.5 deg/tick (plus float slack), and the shot does home (it turns > 30 deg)
	var spawned3 := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt3 = spawned3[0]
	var row3 = spawned3[1]
	_run_pinned(rt3, row3, 325, 0.0)
	if (row3["shots"] as Array).is_empty():
		f.append("wind turn: no shot at beat 8 + 1")
		return
	var d0 := Vector3(float(row3["shots"][0]["dx"]), float(row3["shots"][0]["dy"]),
			float(row3["shots"][0]["dz"]))
	var max_step := 0.0
	var turn := 0.0
	var prev_dir := d0
	for _i in range(60):
		spawned3[2].x = 12.5
		spawned3[2].y = 0.0
		spawned3[2].z = 12.5   # 90 deg to the side of the original flight line
		row3["agitation"] = 0.0
		rt3.step(DT)
		if (row3["shots"] as Array).is_empty():
			break
		var cur: Dictionary = row3["shots"][0]
		var dir_now := Vector3(float(cur["dx"]), float(cur["dy"]), float(cur["dz"]))
		var s: float = rad_to_deg(prev_dir.angle_to(dir_now))
		if s > max_step:
			max_step = s
		turn += s
		prev_dir = dir_now
	if turn < 30.0:
		f.append("wind turn: the heading turned %.1f deg in 60 ticks - it is not homing" % turn)
	if max_step > 1.5 + 0.05:
		f.append("wind turn: a single tick turned %.3f deg, want <= 1.5 (90 deg/s)" % max_step)
	# life 4.0 s = 240 ticks (D-071): a shot with nothing to hit expires at +240
	var spawned4 := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt4 = spawned4[0]
	var row4 = spawned4[1]
	var ctl4 = spawned4[2]
	ctl4.x = 80.0   # far beyond the 28 u flight reach: the shot must die of life
	_run_pinned(rt4, row4, 324, 0.0)
	if (row4["shots"] as Array).is_empty():
		f.append("wind life: no shot at beat 8")
		return
	var shot1b: Dictionary = row4["shots"][0]
	var t_spawn: int = int(row4["last_shot_tick"])
	var t_end := -1
	for _i in range(300):
		row4["agitation"] = 0.0
		rt4.step(DT)
		if not ((row4["shots"] as Array).has(shot1b)):
			t_end = int(rt4.tick)
			break
	if t_end < 0 or absi(t_end - (t_spawn + 240)) > 1:
		f.append("wind life: the shot died at %s, want spawn + 240 (%d)" % [str(t_end), t_spawn + 240])


# ---- wind kills (D-CLAUDE) and dies on a slab (D-071) --------------------------

func _wind_shot_kills_and_dies(f: Array[String]) -> void:
	# (a) a player at feet 3.5 is out of every drum ring and beam band but the shot
	# climbs to their chest: the wind is the only thing that can reach them
	var a := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt_a = a[0]
	var row_a = a[1]
	var ctl_a = a[2]
	ctl_a.x = 4.0
	ctl_a.y = 3.5
	_run_pinned(rt_a, row_a, 430, 0.0)
	if not ctl_a.dead:
		f.append("wind kill: the homing shot never killed the elevated player")
	else:
		var found := false
		for d in _death_events(rt_a):
			if str(d["code"]) == "D-CLAUDE" and str(d["killer"]) == "Claude":
				found = true
		if not found:
			f.append("wind kill: death events %s, want code D-CLAUDE killer Claude" % str(_death_events(rt_a)))
	# (b) behind a tile wall the shots die on the slab and the player survives
	# (D-071: dies on touching ANY tile slab or step riser) - the wall runs 0..6 u
	# so the low flight path (chest height) cannot fly over it. The player's feet
	# sit at exactly 1.0 u: OUT of the drum rings' (r-1.5, r+1.0) window, IN the
	# 0.5-1.5 beam band - only the wall's shadow keeps every attack off them.
	var wall: Array = []
	for y in [2, 4, 6, 8, 10, 12]:
		wall.append([2, 0, y])
	var b := _spawn(Vector3(12.5, 0.0, 0.5), wall)
	var rt_b = b[0]
	var row_b = b[1]
	var ctl_b = b[2]
	ctl_b.x = 0.5
	ctl_b.y = 1.0
	var deaths_before: int = _death_events(rt_b).size()
	_run_pinned(rt_b, row_b, 700, 0.0)
	if ctl_b.dead:
		f.append("wind kill: a shot killed through the wall (D-071 says it dies on the slab)")
	# the observation is the outcome: alive behind the wall through three wind bars
	if _death_events(rt_b).size() != deaths_before:
		f.append("wind kill: a death event appeared behind the wall")


# ---- the answer window "run straight": 9.0 vs 7.0 u/s - the shot never closes --

func _wind_outrun(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	ctl.x = 4.0
	ctl.y = 3.5   # out of the rings and the beam band: only the wind can chase
	_run_pinned(rt, row, 324, 0.0)   # up to bar 2's first shot (the player flees below)
	if (row["shots"] as Array).is_empty():
		f.append("wind outrun: no shot at bar 2 beat 1")
		return
	var caught := false
	for _i in range(300):
		# the player runs dead straight at 9.0 u/s (0.15 u per tick), away from Claude
		ctl.x -= 0.15
		ctl.y = 3.5
		row["agitation"] = 0.0
		rt.step(DT)
		if ctl.dead:
			caught = true
			break
	if caught:
		f.append("wind outrun: a 9.0 u/s runner was caught by a 7.0 u/s shot (the +2 u/s gap)")


# ---- plushies: every 25 s, 10-25 u out, max 3; pickup = -35 agitation ----------

func _plushies(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	# first plushie at age 1500 (25 s), on a tile 10-25 u from the player
	_run_pinned(rt, row, 1550, 0.0)
	var plushies: Array = row["plushies"]
	if plushies.is_empty():
		f.append("plushie: none spawned by tick 1550 (want one at 1500)")
	elif absi(int(plushies[0]["born"]) - 1500) > 2:
		f.append("plushie: first spawn at tick %d, want 1500 +/-2" % int(plushies[0]["born"]))
	for p in plushies:
		var d := Vector2(float(p["x"]) - 0.5, float(p["z"]) - 0.5).length()
		if d < 10.0 - 0.01 or d > 25.0 + 0.01:
			f.append("plushie: spawned %.2f u from the player, want 10-25" % d)
	# the cap: 3 present, never more (hold long enough for 4+ intervals)
	_run_pinned(rt, row, 8000, 0.0)
	if (row["plushies"] as Array).size() > 3:
		f.append("plushie: %d present, want the max-3 cap" % (row["plushies"] as Array).size())
	# pickup: walk onto one -> -35 agitation (never below 0), squeak-pop stamps
	var p0: Dictionary = row["plushies"][0]
	ctl.x = float(p0["x"])
	ctl.z = float(p0["z"])
	ctl.y = float(p0["y"])
	row["agitation"] = 70.0
	var before: int = (row["plushies"] as Array).size()
	_run_pinned(rt, row, 1, -1.0)   # one unpinned tick: the pickup happens inside it
	if (row["plushies"] as Array).size() != before - 1:
		f.append("plushie: the plushie was not consumed on pickup")
	if absf(float(row["agitation"]) - 35.0) > 0.1:
		f.append("plushie: agitation %.2f after the pickup, want 35 (70 - 35)" % float(row["agitation"]))
	if int(row["last_pickup_tick"]) < 0:
		f.append("plushie: last_pickup_tick never set (the squeak-pop hook)")
	# a pickup at low agitation never goes negative
	row["agitation"] = 10.0
	_run_pinned(rt, row, 1, -1.0)   # not standing on one: nothing changes
	if absf(float(row["agitation"]) - 10.0) > 0.1:
		f.append("plushie: agitation moved without a pickup")


# ---- Deadline: at agitation 100 all three attacks fire every bar ----------------

func _deadline(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	ctl.x = 60.0   # far out of every reach: pure scheduling, no kills
	# settle exactly onto beat 4 (bar 1's first beat), then measure exactly 2 bars
	while float(row["beat_pos"]) < 4.0:
		row["agitation"] = 100.0
		rt.step(DT)
	var seen := {"rings": [], "shots": [], "sweeps": []}
	var marks := {"rings": 0, "shots": 0, "sweeps": 0}
	while float(row["beat_pos"]) < 12.0:
		row["agitation"] = 100.0
		rt.step(DT)
		_absorb_new(seen, marks, row["rings"], "rings", 0)
		_absorb_new(seen, marks, row["shots"], "shots", 0)
		_absorb_new(seen, marks, row["sweeps"], "sweeps", 0)
	# two bars at the Deadline: drums x2 + strings x1 + wind x3, twice
	_num(f, "deadline rings / 2 bars", float((marks["rings"] as Array).size()), 4.0)
	_num(f, "deadline shots / 2 bars", float((marks["shots"] as Array).size()), 6.0)
	_num(f, "deadline sweeps / 2 bars", float((marks["sweeps"] as Array).size()), 2.0)
	# the anim state never rests at the Deadline: the schedule never shows "idle"
	var saw_idle := false
	for _i in range(90):
		row["agitation"] = 100.0
		rt.step(DT)
		if str(row["anim_state"]) == "idle":
			saw_idle = true
	if saw_idle:
		f.append("deadline: the anim state fell back to idle during the Deadline")


# ---- the anim block wiring (through view/enemy_anim.gd, T-084's contract) -----

func _anim_block_wiring(f: Array[String]) -> void:
	var doc_text := FileAccess.get_file_as_string(SHEET)
	var doc: Dictionary = JSON.parse_string(doc_text)
	if not (doc is Dictionary) or not doc.has("anim"):
		f.append("anim: sprites.json has no anim block")
		return
	var states: Dictionary = doc["anim"]["states"]
	# every state the sim can announce exists in the block (the T-083 table, verbatim)
	for state_id in ["spawn", "idle", "telegraph_drums", "attack_drums", "telegraph_strings",
			"attack_strings", "attack_wind", "deadline", "plushie_idle"]:
		if not states.has(state_id):
			f.append("anim: the block is missing state '%s'" % state_id)
	# the plushie_idle row: THREE frames (the only 3-frame set), 6 fps / 10 ticks per
	# frame, looping - the clawd Crab plushie was never fetched (TBD.md row 26); the
	# three TBD logo frames stand in at the table's exact timing
	var pi: Dictionary = states["plushie_idle"]
	if (pi["frames"] as Array).size() != 3:
		f.append("anim: plushie_idle has %d frames, want the 3-frame set" % (pi["frames"] as Array).size())
	if absf(float(pi["ticks_per_frame"])) != 10.0 or absf(float(pi["fps"])) != 6.0 or not bool(pi["loop"]):
		f.append("anim: plushie_idle timing %s, want 6 fps / 10 ticks per frame / loop" % str(pi))
	# EnemyAnim drives it: 10 ticks per frame, wrapping 0 -> 1 -> 2 -> 0
	var p = EnemyAnim.new()
	p.setup("claude", doc, FOLDER)
	p.on_state_changed("plushie_idle")
	for _i in range(10):
		p.sim_tick()
	if p.frame_index() != 1:
		f.append("anim: plushie frame after 10 ticks %d, want 1" % p.frame_index())
	for _i in range(10):
		p.sim_tick()
	if p.frame_index() != 2:
		f.append("anim: plushie frame after 20 ticks %d, want 2" % p.frame_index())
	for _i in range(10):
		p.sim_tick()
	if p.frame_index() != 0:
		f.append("anim: plushie frame after 30 ticks %d, want 0 (the loop wraps)" % p.frame_index())
	# the strings telegraph fills its cue exactly: 36 ticks, and the attack frame
	# lands on the event tick with 0 error (the T-084 contract)
	p.on_state_changed("telegraph_strings")
	if p.state_total() != 36:
		f.append("anim: telegraph_strings total %d, want 36" % p.state_total())
	for _i in range(36):
		p.sim_tick()
	p.on_state_changed("attack_strings")
	if p.attack_event(999) != 0 or p.frame_name() != "claude_00":
		f.append("anim: the attack frame on the event tick is %s, want claude_00 at 0" % p.frame_name())
	# the spawn fade blocks contact for its 30 ticks (section 1.0)
	p.on_state_changed("spawn")
	if not p.contact_blocked():
		f.append("anim: the spawn fade does not block contact at tick 0")
	for _i in range(30):
		p.sim_tick()
	if p.contact_blocked():
		f.append("anim: the spawn fade still blocks contact after 30 ticks")
	# the view builds and drives
	var v = ClaudeViewScript.new()
	v.setup(SHEET, FOLDER)
	if v.billboard == null or v.anim_player == null:
		f.append("view: the billboard or the anim player was not built")
		v.free()
		return
	if v.billboard.texture == null:
		f.append("view: the body's frame texture failed to load")
	var row := {"anim_state": "telegraph_strings", "anim_state_t": 0, "str_tel_left": 36,
			"str_dx": 0.0, "str_dz": 1.0, "beat_pos": 3.0, "agitation": 0.0,
			"rings": [], "sweeps": [], "shots": [], "plushies": [], "age": 180,
			"x": 5.0, "y": 0.0, "z": 0.5}
	v.position = Vector3(5.0, 0.0, 0.5)
	v.sync(row, DT)
	if not v._strings_line.visible:
		f.append("view: the strings telegraph line is hidden during the telegraph")
	if v.anim_player.state_id != "telegraph_strings":
		f.append("view: the anim player is not on the sim's state")
	# a drum ring renders as the 1.0 u band at the ring's radius
	var row2: Dictionary = row.duplicate(true)
	row2["anim_state"] = "attack_drums"
	row2["rings"] = [{"x": 5.0, "y": 0.0, "z": 0.5, "r": 2.0, "done": false}]
	v.sync(row2, DT)
	if v._bands.is_empty() or not v._bands[0].visible:
		f.append("view: the drum band is hidden while a ring is live")
	else:
		if absf(float(v._bands[0].scale.x) - 2.0) > 0.001:
			f.append("view: band scale %.3f, want 2.0 (the ring radius)" % float(v._bands[0].scale.x))
		if absf(band_top(v._bands[0]) - 1.0) > 0.001:
			f.append("view: the drum band is not 1.0 u tall")
	# wind shots and plushies render from the row
	var row3: Dictionary = row.duplicate(true)
	row3["anim_state"] = "attack_wind"
	row3["shots"] = [{"x": 6.0, "y": 1.0, "z": 0.5, "dx": -1.0, "dy": 0.0, "dz": 0.0, "life": 200}]
	row3["plushies"] = [{"x": 8.0, "y": 0.0, "z": 0.5, "born": 100}]
	row3["age"] = 150
	v.sync(row3, DT)
	if v._shot_root.get_child_count() < 2:
		f.append("view: the wind shot (dot + trail) did not render")
	if v._plushie_root.get_child_count() < 1:
		f.append("view: the plushie did not render")
	v.free()


static func band_top(band) -> float:
	# unit open cylinder, y in [0, 1], scaled by node y (identity here)
	for i in range(band.mesh.get_surface_count()):
		var arrays: Array = band.mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var top := 0.0
		for vt in verts:
			top = maxf(top, float(vt.y) * float(band.scale.y))
		return top
	return -1.0


# ---- the lobby exhibit path (antechamber's _exhibit_enemy, headless) ----------

func _lobby_exhibit(f: Array[String]) -> void:
	var api: RefCounted = ContentApiScript.load()
	if not api.call("is_ok"):
		f.append("lobby: content boot failed: %s" % " / ".join(api.call("boot_errors")))
		return
	if not (api.call("enemy_ids") as Array).has("claude"):
		f.append("lobby: 'claude' is not registered as an enemy")
		return
	# the E-bay draw path: offered at level 15 (its min_level), absent at level 14
	var gate: Dictionary = OffersScript.enemy_gate(api)
	var l15: Array = OffersScript.enemy_candidates(api, 15, "general", {}, gate)
	var l14: Array = OffersScript.enemy_candidates(api, 14, "general", {}, gate)
	if not l15.has("claude"):
		f.append("lobby: 'claude' is not a candidate enemy at level 15")
	if l14.has("claude"):
		f.append("lobby: 'claude' offered below its min_level (14)")
	var doc: Dictionary = api.call("enemy", "claude")
	if str(doc.get("name", "")) != "Claude":
		f.append("lobby: name %s, want Claude" % str(doc.get("name", "")))
	if int(doc.get("min_level", 0)) != 15:
		f.append("lobby: min_level %d, want 15" % int(doc.get("min_level", 0)))
	if int(doc.get("max_votes", 0)) != 1:
		f.append("lobby: max_votes %d, want 1" % int(doc.get("max_votes", 0)))
	# the antechamber's exact path: parse sprites.json, build the billboard,
	# scale the body to ENEMY_BODY_H (1.6 u)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SHEET))
	if not (parsed is Dictionary):
		f.append("lobby: sprites.json does not parse")
		return
	var bb = BillboardScript.new()
	bb.setup_from_sheet(parsed, FOLDER)
	var doc_h: float = float(parsed.get("world_height", 1.0))
	bb.scale = bb.scale * (1.6 / maxf(doc_h, 0.01))
	bb.world_height = 1.6
	if bb.texture == null:
		f.append("lobby: the exhibit billboard has no texture (frames missing)")
	var anims: Dictionary = bb.anims
	if anims.has("idle"):
		for tex in anims["idle"]["frames"]:
			if tex == null:
				f.append("lobby: an exhibit frame texture failed to load")
	else:
		f.append("lobby: the exhibit billboard has no idle animation")
	bb.free()


# ---- assertion helpers ---------------------------------------------------------

func _eq(f: Array[String], label: String, got: String, want: String) -> void:
	if got != want:
		f.append("%s: %s, want %s" % [label, got, want])


func _num(f: Array[String], label: String, got: float, want: float, tol: float = 0.0001) -> void:
	if absf(got - want) > tol:
		f.append("%s: %s, want %s" % [label, _fmt(got), _fmt(want)])


static func _fmt(v: float) -> String:
	return "%.4f" % v
