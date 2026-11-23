extends RefCounted
#
# claude tests - the CYCLE 7 REVAMP (track T4; D-T4-1..D-T4-8).
#
# The owner's words (CYCLE7_BRIEF.md T4, verbatim): "Claude enemy revamp (spawns 5-15 clawds, collect to calm,
# warning sounds at 1 and 2 min, insta-kill at 3 min)". "Claude does NOTHING by himself: no attack, no movement."
#
# What is asserted here, and why every number is the deliverable data's own rather than a test-local copy:
#   - the roster data vs the behavior's mirror: enemy.json's stats block, cfg() and clawd_cfg() (D-T4-1..3);
#   - the clawd count across level sizes: 5 on a small map, 15 on a very big one, the count_by_tiles table
#     between them, and the [5, 15] clamp (D-T4-3);
#   - placement: walkable tiles only, never a gift slot / mine / beacon / hub / pad / spawn, spread out, and a
#     pure function of the Level dict (two attaches agree, a different seed does not) (D-T4-4);
#   - the body: 2.0 u tall, 1.6 u hit diameter, contact kills carry D-CLAUDE, the 30-tick spawn fade blocks it;
#   - "does nothing by himself": 600 ticks of a live body produce no ring, shot, sweep or plushie and no motion;
#   - the anger timer: warnings at EXACTLY 3600 and 7200 ticks, the kill at EXACTLY 10800 with cause "Claude",
#     a pickup resetting it to 0, and the freeze while the beacon is open (D-T4-5);
#   - the state hash: a CLAWDS line, two replays of one script hashing identically, a perturbed one diverging,
#     and the timer itself moving the hash (D-T4-6);
#   - the view: the anim block's spawn/idle wiring, the anger tint, the warning flash, the HUD pill's strings;
#   - the lobby exhibit path (antechamber's _exhibit_enemy, headless).
#
# Kill tests run with the player's LAST LIGHT already spent (D-057) - otherwise the save masks the kill and the
# assertion is worthless.

const ClawdsScript := preload("res://sim/clawds.gd")
const ClaudeEnemy := preload("res://content/enemies/claude/enemy.gd")
const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Util := preload("res://tests/sim_testutil.gd")
const DeathScript := preload("res://sim/death.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const BillboardScript := preload("res://view/billboard.gd")
const ClaudeViewScript := preload("res://view/claude_view.gd")
const ClawdViewScript := preload("res://view/clawd_view.gd")
const AngerMeterScript := preload("res://view/hud/anger_meter.gd")
const EnemyAnim := preload("res://view/enemy_anim.gd")
const OffersScript := preload("res://sim/offers.gd")
const AudioScript := preload("res://view/audio/claude_audio.gd")
const VoidGenScript := preload("res://terrain/voidgen.gd")
const RunStateScript := preload("res://sim/run_state.gd")
const HashScript := preload("res://sim/state_hash.gd")
const CollisionScript := preload("res://sim/collision.gd")
const BeaconScript := preload("res://sim/beacon.gd")
const LevelStateScript := preload("res://sim/level_state.gd")

const DT := 1.0 / 60.0
const SHEET := "res://content/enemies/claude/sprites.json"
const FOLDER := "res://content/enemies/claude"
## The three thresholds the owner named, in ticks at the fixed 60 Hz sim rate.
const WARN_1 := 3600
const WARN_2 := 7200
const KILL := 10800

var _events: Array = []   # every event since the current fixture spawned (rt.events resets per tick)


func run() -> Array[String]:
	var f: Array[String] = []
	_roster_data(f)
	_counts_across_level_sizes(f)
	_placement_rules(f)
	_body_and_contact(f)
	_spawn_fade_blocks_contact(f)
	_no_attack_no_movement(f)
	_timer_thresholds(f)
	_pickup_resets(f)
	_pause_in_gold_phase(f)
	_hash_and_replay(f)
	_anim_block_wiring(f)
	_hud_meter(f)
	_lobby_exhibit(f)
	return f


# ---- fixtures ------------------------------------------------------------------

## A flat synthetic Level dict: (2n+1)^2 floor tiles, the beacon and one spawn at the origin. The clawd
## placement only reads tiles / props / pads / gifts / jump_pads / spawns / beacon / pieces, so a hand-built
## dict is a legal input - and it makes the tile count exact, which is what the count table is a function of.
func _flat_level(n: int, seed: int = 5) -> Dictionary:
	var tiles: Array = []
	for x in range(-n, n + 1):
		for z in range(-n, n + 1):
			tiles.append([x, z, 0, 0, 0])
	return {"seed": seed, "level": 1, "gen_version": 1, "attempt": 0,
		"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "tiles": tiles,
		"props": [], "pads": [], "gifts": [], "pieces": []}


## A real generated level with the swarm attached (the hash/replay legs need a Level the generator owns).
func _gen_level(seed: int = 7, lvn: int = 1) -> Dictionary:
	var L: Dictionary = VoidGenScript.generate(seed, lvn)
	ClawdsScript.attach(L, ClaudeEnemy.clawd_cfg())
	return L


## The sim-side holder sim/clawds.gd reads: lv.clawds + lv.beacon (the pause rule). A plain Dictionary is
## enough - the module only ever calls .get() on it.
func _holder(L: Dictionary) -> Dictionary:
	return {"clawds": ClawdsScript.create(L), "beacon": BeaconScript.create(L)}


## The collision world the controller steps in, with the beacon dais (try_kill's Last Light teleport reads it).
func _world(L: Dictionary) -> Dictionary:
	return CollisionScript.make_world(L["tiles"], L["props"], L["pads"], {"dais": L["beacon"]})


## Last Light spent for real, then the arrival state cleared: the fixture is exactly "alive, unshielded,
## Last Light spent" (D-057).
func _spent_ctl(w: Dictionary):
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.try_kill("D-TEST", "test", w, [])
	ctl.invuln = 0.0
	ctl.dead = false
	ctl.place(w)
	return ctl


## Puts the player's FEET at a clawd's spot (the pickup test point is feet + 0.9 u, so the centre lands on
## the clawd's own centre).
func _stand_on(ctl, cl, i: int) -> void:
	var p: Vector3 = cl.spot_pos(i)
	ctl.x = p.x
	ctl.y = p.y - 0.9
	ctl.z = p.z
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0


## The cfg comes from the REAL enemy.json (D-T-034-7's rule): the numbers asserted are the deliverable data's
## own, never a test-local copy.
func _cfg() -> Dictionary:
	var txt := FileAccess.get_file_as_string("res://content/enemies/claude/enemy.json")
	var doc = JSON.parse_string(txt)
	return doc["stats"]


## [rt, row, ctl]; the controller sits on the spawn tile and never moves on its own.
func _spawn(pos: Vector3, extra: Array = []) -> Array:
	var w := Util.world_from_tiles(_tiles_full(extra))
	w["dais"] = [0, 0, 0]
	var ctl = _spent_ctl(w)
	var rt = EnemyRuntime.new()
	rt.setup(_level(extra), w, [ctl], 4242)
	var row: Dictionary = rt.spawn_at("claude", "Claude", ClaudeEnemy.new(), _cfg(), pos)
	_events = []
	return [rt, row, ctl]


func _tiles_full(extra: Array = []) -> Array:
	var tiles: Array = []
	for x in range(-10, 11):
		for z in range(-10, 11):
			tiles.append([x, z, 0])
	tiles.append_array(extra)
	return tiles


func _level(extra_tiles: Array = []) -> Dictionary:
	# the runtime's round_trip_set reads 5-element tile rows; world_from_tiles wants the [x, z, y_hu] triple
	var flat := _tiles_full(extra_tiles)
	var padded: Array = []
	for t in flat:
		padded.append([t[0], t[1], t[2], 0, 0])
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": padded, "props": [], "pads": []}


func _filter_events(kind: String) -> Array:
	var out: Array = []
	for e in _events:
		if str((e as Dictionary).get("e", (e as Dictionary).get("type", ""))) == kind:
			out.append(e)
	return out


## Steps n ticks of the runtime, folding every tick's events into _events.
func _run(rt, n: int) -> void:
	for _i in range(n):
		rt.step(DT)
		_events.append_array(rt.events)


# ---- the roster data vs the behavior's mirror ----------------------------------

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
	_num(f, "contact_kill", 1.0 if bool(doc["contact_kill"]) else 0.0, 1.0)
	if str(doc["vote_effect"]).find("one Claude") < 0:
		f.append("data: vote_effect %s, want the one-Claude line" % str(doc["vote_effect"]))
	var st: Dictionary = doc["stats"]
	# DESIGN.md section 5.11 / SR-2 / SR-5 numbers that survive the revamp (D-T4-1)
	_num(f, "world_height", float(st["world_height"]), 2.0)
	_num(f, "hit_diameter", float(st["hit_diameter"]), 1.6)
	_num(f, "base_speed", float(st["base_speed"]), 4.0)
	_num(f, "pursuit_ceiling", float(st["pursuit_ceiling"]), 0.55)
	_num(f, "spawn_fade_ticks", float(st["spawn_fade_ticks"]), 30.0)
	_num(f, "death_code", 1.0 if str(st["death_code"]) == "D-CLAUDE" else 0.0, 1.0)
	# the swarm + the anger timer (D-T4-3..D-T4-5): the owner's 5..15, 1 min / 2 min / 3 min
	_num(f, "clawd_count_min", float(st["clawd_count_min"]), 5.0)
	_num(f, "clawd_count_max", float(st["clawd_count_max"]), 15.0)
	_num(f, "clawd_min_spacing_tiles", float(st["clawd_min_spacing_tiles"]), 8.0)
	_num(f, "clawd_pickup_radius", float(st["clawd_pickup_radius"]), 1.6)
	_num(f, "anger_kill_ticks", float(st["anger_kill_ticks"]), float(KILL))
	_num(f, "anger_pause_when_beacon_open", 1.0 if bool(st["anger_pause_when_beacon_open"]) else 0.0, 1.0)
	_eq(f, "anger_killer_id", str(st["anger_killer_id"]), "Claude")
	_eq(f, "anger_death_code", str(st["anger_death_code"]), "D-CLAUDE")
	var wt: Array = st["anger_warning_ticks"]
	if wt.size() != 2 or int(wt[0]) != WARN_1 or int(wt[1]) != WARN_2:
		f.append("data: anger_warning_ticks %s, want [%d, %d] (60 s and 120 s)" % [str(wt), WARN_1, WARN_2])
	# the count table is the deliverable formula, not a code constant (D-T4-3)
	var tbl: Array = st["clawd_count_by_tiles"]
	if tbl.size() < 2:
		f.append("data: clawd_count_by_tiles has %d rows, want the size ladder" % tbl.size())
	else:
		var prev_t := -1
		var prev_c := -1
		for row in tbl:
			var rt := int((row as Dictionary)["tiles"])
			var rc := int((row as Dictionary)["count"])
			if rt <= prev_t or rc < prev_c:
				f.append("data: clawd_count_by_tiles is not ascending in tiles/count: %s" % str(tbl))
				break
			prev_t = rt
			prev_c = rc
		if int((tbl[0] as Dictionary)["count"]) != int(st["clawd_count_min"]):
			f.append("data: the count table's first row is not clawd_count_min")
		if int((tbl[tbl.size() - 1] as Dictionary)["count"]) != int(st["clawd_count_max"]):
			f.append("data: the count table's last row is not clawd_count_max")
	# the two new warning cues ARE the file names (T-055's contract), and the old kit's cues are gone
	var want_cues := ["claude_warning_1", "claude_warning_2"]
	_eq(f, "audio cues", str(st["audio_cues"]), str(want_cues))
	if str(AudioScript.CUE_WARNING_1) != "claude_warning_1" or str(AudioScript.CUE_WARNING_2) != "claude_warning_2":
		f.append("audio: claude_audio.gd cue names drifted from enemy.json's audio_cues")
	_eq(f, "cue_for_level(1)", AudioScript.cue_for_level(1), "claude_warning_1")
	_eq(f, "cue_for_level(2)", AudioScript.cue_for_level(2), "claude_warning_2")
	_eq(f, "cue_for_level(0)", AudioScript.cue_for_level(0), "")
	_eq(f, "cue_for_level(3)", AudioScript.cue_for_level(3), "")
	if AudioScript.play(null, "claude_warning_1"):
		f.append("audio: play() with no node must no-op false")
	# the old musical kit is DELETED, not disabled (D-T4-1): no beat clock, no drum/strings/wind/plushie knob
	for gone in ["bpm_base", "bpm_per_agitation", "bar_beats", "agitation_rise_per_s", "agitation_max",
			"drum_ring_speed_u_per_s", "drum_ring_max_radius", "strings_sweep_deg", "strings_length_u",
			"wind_speed_u_per_s", "wind_turn_deg_per_s", "plushie_interval_s", "plushie_calm"]:
		if st.has(gone):
			f.append("data: stats.%s survives the revamp (the old kit is deleted, D-T4-1)" % gone)
	# the mirror in the behavior agrees with the json (kiwi/seal cfg-mirror convention)
	var mirror: Dictionary = ClaudeEnemy.cfg()
	for k in mirror.keys():
		if not st.has(k):
			continue
		if _vals_agree(st[k], mirror[k]):
			continue
		f.append("mirror: stats.%s = %s, behavior cfg says %s" % [str(k), str(st[k]), str(mirror[k])])
	# clawd_cfg()'s keys are the json's with the clawd_/anger_ prefix stripped
	var cc: Dictionary = ClaudeEnemy.clawd_cfg()
	var pairs := [["count_min", "clawd_count_min"], ["count_max", "clawd_count_max"],
		["count_by_tiles", "clawd_count_by_tiles"], ["min_spacing_tiles", "clawd_min_spacing_tiles"],
		["pickup_radius", "clawd_pickup_radius"], ["warning_ticks", "anger_warning_ticks"],
		["kill_ticks", "anger_kill_ticks"], ["pause_when_beacon_open", "anger_pause_when_beacon_open"],
		["killer_id", "anger_killer_id"], ["death_code", "anger_death_code"]]
	for pair in pairs:
		var ck := str(pair[0])
		var jk := str(pair[1])
		if not cc.has(ck):
			f.append("mirror: clawd_cfg() has no '%s'" % ck)
			continue
		if not _vals_agree(st[jk], cc[ck]):
			f.append("mirror: stats.%s = %s, clawd_cfg().%s says %s" % [jk, str(st[jk]), ck, str(cc[ck])])
	if not _vals_agree(st["audio_cues"], cc.get("cues", [])):
		f.append("mirror: clawd_cfg().cues %s, want the json's audio_cues" % str(cc.get("cues", [])))
	# the sim module's own DEFAULTS agree with the data too (a cfg-less caller gets the same design). The
	# killer id and the death code are the exception: sim/clawds.gd names no content id (D-T4-2), so its
	# defaults are empty and the roster module is the only source of those two strings.
	var resolved: Dictionary = ClawdsScript.resolve_cfg({})
	for pair2 in pairs:
		var dk := str(pair2[0])
		if dk == "killer_id" or dk == "death_code":
			if str(resolved[dk]) != "":
				f.append("mirror: sim/clawds.gd DEFAULTS.%s names a content id (D-T4-2)" % dk)
			continue
		if not _vals_agree(cc[dk], resolved[dk]):
			f.append("mirror: sim/clawds.gd DEFAULTS.%s disagrees with the data" % dk)
	if str(DeathScript.killer_for("D-CLAUDE")) != "Claude":
		f.append("data: death.gd maps D-CLAUDE to %s, want Claude" % str(DeathScript.killer_for("D-CLAUDE")))


## Numeric-tolerant value agreement: scalars compare as numbers, arrays element-wise, strings as strings.
func _vals_agree(jv: Variant, cv: Variant) -> bool:
	if jv is Dictionary and cv is Dictionary:
		var jd: Dictionary = jv
		var cd: Dictionary = cv
		if jd.size() != cd.size():
			return false
		for k in jd.keys():
			if not cd.has(k) or not _vals_agree(jd[k], cd[k]):
				return false
		return true
	if jv is Array and cv is Array:
		var ja: Array = jv
		var ca: Array = cv
		if ja.size() != ca.size():
			return false
		for i in range(ja.size()):
			if not _vals_agree(ja[i], ca[i]):
				return false
		return true
	if jv is String or cv is String:
		return str(jv) == str(cv)
	if (jv is float or jv is int) and (cv is float or cv is int):
		return absf(float(jv) - float(cv)) <= 0.000001
	return str(jv) == str(cv)


# ---- the count: 5 on a small map, 15 on a very big one, the table between (D-T4-3) ----

func _counts_across_level_sizes(f: Array[String]) -> void:
	var cfg: Dictionary = ClaudeEnemy.clawd_cfg()
	# the table's own boundaries, read from the data (never a test-local copy of the ladder): a row applies
	# from its own tile count up, and one tile under it still answers with the row above
	var prev_count := int(cfg["count_min"])
	for row in cfg["count_by_tiles"]:
		var at := int((row as Dictionary)["tiles"])
		var want := int((row as Dictionary)["count"])
		_num(f, "count_for_tiles(%d)" % at, float(ClawdsScript.count_for_tiles(cfg, at)), float(want))
		if at > 0:
			_num(f, "count_for_tiles(%d) (one tile under the row)" % (at - 1),
				float(ClawdsScript.count_for_tiles(cfg, at - 1)), float(prev_count))
		prev_count = want
	# the clamp: a huge map never exceeds count_max, an empty one never drops below count_min
	_num(f, "count_for_tiles(99999)", float(ClawdsScript.count_for_tiles(cfg, 99999)),
		float(cfg["count_max"]))
	_num(f, "count_for_tiles(0)", float(ClawdsScript.count_for_tiles(cfg, 0)), float(cfg["count_min"]))
	# a small map: 21 x 21 = 441 tiles -> the floor of 5, and the placement really reaches it
	var small := _flat_level(10)
	var small_spots: Array = ClawdsScript.place_clawds(small, cfg)
	_num(f, "small map (441 tiles) clawds", float(small_spots.size()), float(cfg["count_min"]))
	# a very big map: 45 x 45 = 2025 tiles -> the ceiling of 15
	var big := _flat_level(22)
	var big_spots: Array = ClawdsScript.place_clawds(big, cfg)
	_num(f, "big map (2025 tiles) clawds", float(big_spots.size()), float(cfg["count_max"]))
	# the real generator, four level sizes: the count is the table's answer and always inside 5..15
	for lvn in [1, 10, 20, 30]:
		var L: Dictionary = VoidGenScript.generate(7, lvn)
		var n := (L["tiles"] as Array).size()
		var want := ClawdsScript.count_for_tiles(cfg, n)
		var spots: Array = ClawdsScript.place_clawds(L, cfg)
		if spots.size() < int(cfg["count_min"]) or spots.size() > int(cfg["count_max"]):
			f.append("count: level %d (%d tiles) placed %d clawds, want %d..%d"
				% [lvn, n, spots.size(), int(cfg["count_min"]), int(cfg["count_max"])])
		if spots.size() != want:
			f.append("count: level %d (%d tiles) placed %d clawds, the table says %d"
				% [lvn, n, spots.size(), want])
	# the count is monotone in the map size: a bigger map never asks for fewer clawds
	var prev := 0
	for n2 in [0, 400, 800, 1000, 1100, 1300, 1400, 1600, 1700, 3000]:
		var c := ClawdsScript.count_for_tiles(cfg, n2)
		if c < prev:
			f.append("count: the table drops from %d to %d at %d tiles" % [prev, c, n2])
		prev = c


# ---- placement: walkable, clear of the level's furniture, spread out, seed-pure (D-T4-4) ----

func _placement_rules(f: Array[String]) -> void:
	var cfg: Dictionary = ClaudeEnemy.clawd_cfg()
	var L := _flat_level(22)
	var spots: Array = ClawdsScript.place_clawds(L, cfg)
	if spots.size() != int(cfg["count_max"]):
		f.append("placement: %d spots on the big map, want %d" % [spots.size(), int(cfg["count_max"])])
	# every spot is a walkable floor tile of the Level (kind 0/1, not a ramp), never a prop cell
	var by_cell := {}
	for t in L["tiles"]:
		by_cell[Vector2i(int(t[0]), int(t[1]))] = t
	for p in spots:
		var key := Vector2i(int(p[0]), int(p[1]))
		if not by_cell.has(key):
			f.append("placement: spot %s is not a tile of the Level" % str(p))
			continue
		var t: Array = by_cell[key]
		if int(t[2]) != int(p[2]):
			f.append("placement: spot %s sits on tile height %d" % [str(p), int(t[2])])
		if int(t[3]) != 0:
			f.append("placement: spot %s is a ramp tile" % str(p))
	# spread out: the configured spacing holds on a map this big (the ladder only relaxes when it must)
	var min_d2 := 1e9
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			var dx := float(int(spots[i][0]) - int(spots[j][0]))
			var dz := float(int(spots[i][1]) - int(spots[j][1]))
			min_d2 = minf(min_d2, dx * dx + dz * dz)
	var want_d := float(int(cfg["min_spacing_tiles"]))
	if min_d2 < want_d * want_d:
		f.append("placement: the closest pair is %.2f tiles apart, want >= %.0f"
			% [sqrt(min_d2), want_d])
	# never on the beacon, a spawn, a gift slot (which is also a mine slot), a pad or a jump pad - and never
	# on the 8 neighbours of any of them
	var banned := {}
	var ban := func(x: int, z: int) -> void:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				banned[Vector2i(x + dx, z + dz)] = true
	ban.call(0, 0)                                   # the beacon and the spawn both sit at the origin
	for p2 in spots:
		if banned.has(Vector2i(int(p2[0]), int(p2[1]))):
			f.append("placement: spot %s is on the beacon/spawn or a neighbour" % str(p2))
	# a level with gifts and pads: the clawds keep clear of every one of them
	var L2 := _flat_level(22)
	L2["gifts"] = [{"id": 0, "x": 5, "z": 5, "y": 0, "piece": 0, "tier": 0, "occ": 1},
		{"id": 1, "x": -6, "z": 3, "y": 0, "piece": 0, "tier": 0, "occ": 0}]
	L2["pads"] = [[8, 8, 0, 12, 12, 0]]
	L2["jump_pads"] = [[-9, -9, 0]]
	var banned2 := {}
	var ban2 := func(x: int, z: int) -> void:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				banned2[Vector2i(x + dx, z + dz)] = true
	ban2.call(0, 0)
	for g in L2["gifts"]:
		ban2.call(int(g["x"]), int(g["z"]))
	for pd in L2["pads"]:
		ban2.call(int(pd[0]), int(pd[1]))
		ban2.call(int(pd[3]), int(pd[4]))
	for jp in L2["jump_pads"]:
		ban2.call(int(jp[0]), int(jp[1]))
	var spots2: Array = ClawdsScript.place_clawds(L2, cfg)
	if spots2.size() != int(cfg["count_max"]):
		f.append("placement: %d spots with gifts/pads on the map, want %d"
			% [spots2.size(), int(cfg["count_max"])])
	for p3 in spots2:
		if banned2.has(Vector2i(int(p3[0]), int(p3[1]))):
			f.append("placement: spot %s is on a gift/mine/pad/jump-pad or a neighbour" % str(p3))
	# a pure function of the Level dict: two placements agree, a different seed does not
	var again: Array = ClawdsScript.place_clawds(_flat_level(22), cfg)
	if str(again) != str(spots):
		f.append("placement: two placements of one Level disagree (not a pure function)")
	var other: Array = ClawdsScript.place_clawds(_flat_level(22, 6), cfg)
	if str(other) == str(spots):
		f.append("placement NC: a different seed placed the identical swarm")
	# no legal candidate -> no clawds (a ramp-only map, and a hub-only map)
	var ramps := _flat_level(1)
	for t2 in ramps["tiles"]:
		t2[3] = 1
	if not (ClawdsScript.place_clawds(ramps, cfg) as Array).is_empty():
		f.append("placement: a ramp-only map still placed clawds")
	var hub := _flat_level(1)
	hub["pieces"] = [{"role": VoidGenScript.ROLE_HUB}]
	for t3 in hub["tiles"]:
		t3[4] = 0
	if not (ClawdsScript.place_clawds(hub, cfg) as Array).is_empty():
		f.append("placement: a hub-only map still placed clawds")
	# attach() stores the swarm on the Level dict and create() builds the runtime from it
	var L3 := _flat_level(22)
	var attached: Array = ClawdsScript.attach(L3, cfg)
	if not L3.has("clawds") or (L3["clawds"] as Dictionary)["spots"].size() != attached.size():
		f.append("placement: attach() did not store the swarm on the Level dict")
	var cl = ClawdsScript.create(L3)
	if cl == null or cl.count() != attached.size():
		f.append("placement: create() did not build the runtime from the Level dict")
	elif cl.remaining() != attached.size():
		f.append("placement: a fresh swarm has %d remaining, want %d" % [cl.remaining(), attached.size()])
	if ClawdsScript.create(_flat_level(1)) != null:
		f.append("placement: create() built a swarm for a Level that carries none")


# ---- body: 2.0 u tall / 1.6 u diameter; contact kills carry D-CLAUDE ----------

func _body_and_contact(f: Array[String]) -> void:
	# SR-2's FINAL row: height 2.0, hit diameter 1.6 (0.8 x the 2.0 u body width)
	var spawned := _spawn(Vector3(12.5, 0.0, 0.5))
	var row = spawned[1]
	_run(spawned[0], 31)   # past the fade: the full body is live
	_num(f, "body height", float(row["height_u"]), 2.0)
	_num(f, "hit diameter", float(row["diameter_u"]), 1.6)
	# a body 3 u away never touches (contact = overlap of the cylinders only)
	var c := _spawn(Vector3(4.0, 0.0, 0.5))
	_run(c[0], 40)
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
	_run(rt, 30)   # ticks 1..30: the fade - no contact kill yet
	if ctl.dead:
		f.append("fade: the body killed during the 30-tick spawn fade")
	_run(rt, 5)    # the fade is over: the overlap kills now
	if not ctl.dead:
		f.append("fade: the overlapping body never killed after the fade ended")
	else:
		var found := false
		for d in _filter_events("death"):
			if str(d["code"]) == "D-CLAUDE":
				found = true   # the contact path passes cfg death_code (D-T030-1)
		if not found:
			f.append("fade: death events %s, want D-CLAUDE" % str(_filter_events("death")))


# ---- "does nothing by himself": no attack, no movement (D-T4-1) ---------------

func _no_attack_no_movement(f: Array[String]) -> void:
	# 12 u from the player, well inside the old 20 u leash: the old kit would have closed in and fired
	var spawned := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	var x0 := float(row["x"])
	var z0 := float(row["z"])
	_run(rt, 600)
	if absf(float(row["x"]) - x0) > 1e-9 or absf(float(row["z"]) - z0) > 1e-9:
		f.append("still: the body moved from (%.3f, %.3f) to (%.3f, %.3f)"
			% [x0, z0, float(row["x"]), float(row["z"])])
	# the old kit's hazard lists are not even created (deleted, not disabled)
	for gone in ["rings", "shots", "sweeps", "plushies", "agitation", "beat_pos", "last_drum_tick"]:
		if row.has(gone):
			f.append("still: the row still carries '%s' (the old kit is deleted, D-T4-1)" % gone)
	# and nothing was announced: no telegraph, no attack, no death
	for kind in ["telegraph", "attack", "death"]:
		if not _filter_events(kind).is_empty():
			f.append("still: the body emitted %d '%s' events in 600 ticks"
				% [_filter_events(kind).size(), kind])
	# the anim state is idle forever after the fade
	if str(row["anim_state"]) != "idle":
		f.append("still: the anim state is '%s' after 600 ticks, want idle" % str(row["anim_state"]))


# ---- the anger timer: 3600 / 7200 / 10800 ticks, exactly (D-T4-5) -------------

func _timer_thresholds(f: Array[String]) -> void:
	var L := _flat_level(22)
	ClawdsScript.attach(L, ClaudeEnemy.clawd_cfg())
	var lv := _holder(L)
	var cl = lv["clawds"]
	if cl == null:
		f.append("timer: the fixture level carries no clawd swarm")
		return
	var w := _world(L)
	var ctl = _spent_ctl(w)          # Last Light spent (D-057): the kill must land
	var warn_at: Array = []
	var warn_level: Array = []
	var warn_cue: Array = []
	var kill_at := -1
	var kill_cause := ""
	var kill_code := ""
	var death_code := ""
	var anger_at_warn: Array = []
	var ev: Array = []
	for t in range(1, KILL + 1):
		ev.clear()
		ClawdsScript.tick(lv, [ctl], w, t, ev)
		for e in ev:
			var kind := str((e as Dictionary).get("e", (e as Dictionary).get("type", "")))
			if kind == "clawd_warning":
				warn_at.append(t)
				warn_level.append(int(e["level"]))
				warn_cue.append(str(e["cue"]))
				anger_at_warn.append(int(cl.anger_ticks))
			elif kind == "clawd_kill":
				kill_at = t
				kill_cause = str(e["killer"])
				kill_code = str(e["code"])
			elif kind == "death":
				death_code = str(e["code"])
		if kill_at >= 0:
			break
	if warn_at.size() != 2:
		f.append("timer: %d warnings in %d ticks, want 2 (at %d and %d)"
			% [warn_at.size(), KILL, WARN_1, WARN_2])
	else:
		if int(warn_at[0]) != WARN_1:
			f.append("timer: warning 1 at tick %d, want exactly %d (60 s)" % [int(warn_at[0]), WARN_1])
		if int(warn_at[1]) != WARN_2:
			f.append("timer: warning 2 at tick %d, want exactly %d (120 s)" % [int(warn_at[1]), WARN_2])
		if int(warn_level[0]) != 1 or int(warn_level[1]) != 2:
			f.append("timer: warning levels %s, want [1, 2]" % str(warn_level))
		if str(warn_cue[0]) != "claude_warning_1" or str(warn_cue[1]) != "claude_warning_2":
			f.append("timer: warning cues %s, want the two new synth cues" % str(warn_cue))
		if int(anger_at_warn[0]) != WARN_1 or int(anger_at_warn[1]) != WARN_2:
			f.append("timer: anger at the warnings %s, want [%d, %d]"
				% [str(anger_at_warn), WARN_1, WARN_2])
	if kill_at != KILL:
		f.append("timer: the kill fired at tick %d, want exactly %d (180 s)" % [kill_at, KILL])
	if kill_cause != "Claude":
		f.append("timer: the kill's cause is '%s', want 'Claude'" % kill_cause)
	if kill_code != "D-CLAUDE":
		f.append("timer: the kill's code is '%s', want D-CLAUDE" % kill_code)
	if death_code != "D-CLAUDE":
		f.append("timer: the death event's code is '%s', want D-CLAUDE" % death_code)
	if not ctl.dead:
		f.append("timer: the player is alive after the 180 s kill")
	if int(cl.anger_ticks) != KILL:
		f.append("timer: anger %d after the kill, want it pinned at %d" % [int(cl.anger_ticks), KILL])
	# the kill fires exactly once: 300 more ticks change nothing
	var ev2: Array = []
	for t2 in range(KILL + 1, KILL + 301):
		ev2.clear()
		ClawdsScript.tick(lv, [ctl], w, t2, ev2)
		if not ev2.is_empty():
			f.append("timer: the spent timer emitted %s after the kill" % str(ev2))
			break
	if int(cl.anger_ticks) != KILL:
		f.append("timer: anger drifted to %d after the kill" % int(cl.anger_ticks))


# ---- a pickup CALMS Claude: the timer resets to 0, and a clawd is not a gift (D-T4-5) ----

func _pickup_resets(f: Array[String]) -> void:
	var L := _gen_level(7, 1)
	var lv = LevelStateScript.build(L, 1, 1)
	if lv.clawds == null:
		f.append("pickup: LevelState.build did not wire the swarm (lv.clawds is null)")
		return
	var cl = lv.clawds
	if cl.count() != (L["clawds"] as Dictionary)["spots"].size():
		f.append("pickup: lv.clawds has %d clawds, the Level dict %d"
			% [cl.count(), (L["clawds"] as Dictionary)["spots"].size()])
	var w := _world(L)
	var ctl = _spent_ctl(w)
	var ev: Array = []
	# 100 ticks away from every clawd: the timer runs
	for t in range(1, 101):
		ev.clear()
		ClawdsScript.tick(lv, [ctl], w, t, ev)
		if not ev.is_empty():
			f.append("pickup: an event fired while the player stood still: %s" % str(ev))
			break
	if int(cl.anger_ticks) != 100:
		f.append("pickup: anger %d after 100 idle ticks, want 100" % int(cl.anger_ticks))
	# the gift machine's own state, before the pickup: a clawd must never touch it
	var gifts_before := "%s|%s|%d" % [lv.gifts.black_taken, lv.gifts.gold_taken, lv.gifts.total_real]
	# stand on clawd 0 and tick once: collected, and the timer is back to 0
	_stand_on(ctl, cl, 0)
	ev.clear()
	ClawdsScript.tick(lv, [ctl], w, 101, ev)
	var got := 0
	for e in ev:
		if str((e as Dictionary).get("e", (e as Dictionary).get("type", ""))) == "clawd_collected":
			got += 1
			if int(e["clawd"]) != 0:
				f.append("pickup: the event names clawd %d, want 0" % int(e["clawd"]))
			if int(e["anger_ticks"]) != 0:
				f.append("pickup: the event reports anger %d, want 0" % int(e["anger_ticks"]))
	if got != 1:
		f.append("pickup: %d clawd_collected events on the pickup tick, want 1" % got)
	if not cl.is_taken(0):
		f.append("pickup: clawd 0 is not marked taken")
	if int(cl.anger_ticks) != 0:
		f.append("pickup: anger %d after the pickup, want 0 (collecting CALMS Claude)" % int(cl.anger_ticks))
	if cl.remaining() != cl.count() - 1:
		f.append("pickup: %d remaining after one pickup, want %d" % [cl.remaining(), cl.count() - 1])
	# the pickup tick does not also advance the timer (the reset wins the tick)
	_stand_on(ctl, cl, 1)
	ev.clear()
	ClawdsScript.tick(lv, [ctl], w, 102, ev)
	if int(cl.anger_ticks) != 0:
		f.append("pickup: anger %d on the tick after a pickup, want 0" % int(cl.anger_ticks))
	# away again: the timer runs from the reset
	for t2 in range(103, 153):
		ev.clear()
		ClawdsScript.tick(lv, [ctl], w, t2, ev)
	if int(cl.anger_ticks) != 50:
		f.append("pickup: anger %d 50 ticks after the reset, want 50" % int(cl.anger_ticks))
	# a clawd is NOT a gift: the gift machine's bitsets and total are untouched by two pickups
	var gifts_after := "%s|%s|%d" % [lv.gifts.black_taken, lv.gifts.gold_taken, lv.gifts.total_real]
	if gifts_after != gifts_before:
		f.append("pickup: the gift state moved on a clawd pickup (%s -> %s)" % [gifts_before, gifts_after])
	# a dead player collects nothing
	ctl.dead = true
	var before: int = cl.remaining()
	_stand_on(ctl, cl, 2)
	ev.clear()
	ClawdsScript.tick(lv, [ctl], w, 154, ev)
	if cl.remaining() != before:
		f.append("pickup: a dead player still collected a clawd")
	ctl.dead = false


# ---- the timer pauses while the beacon is open (the gold phase) (D-T4-5) ------

func _pause_in_gold_phase(f: Array[String]) -> void:
	var L := _flat_level(22)
	ClawdsScript.attach(L, ClaudeEnemy.clawd_cfg())
	var lv := _holder(L)
	var cl = lv["clawds"]
	var w := _world(L)
	var ctl = _spent_ctl(w)
	var ev: Array = []
	for t in range(1, 101):
		ev.clear()
		ClawdsScript.tick(lv, [ctl], w, t, ev)
	if int(cl.anger_ticks) != 100:
		f.append("pause: anger %d before the beacon opened, want 100" % int(cl.anger_ticks))
	if cl.paused(lv):
		f.append("pause: the timer is frozen while the beacon is closed")
	# the gold phase begins: the beacon opens and the timer must freeze
	lv["beacon"].open(101)
	if not lv["beacon"].is_open():
		f.append("pause: the fixture beacon did not open")
	if not cl.paused(lv):
		f.append("pause: the timer is not frozen with the beacon open")
	for t2 in range(101, 601):
		ev.clear()
		ClawdsScript.tick(lv, [ctl], w, t2, ev)
		if not ev.is_empty():
			f.append("pause: an event fired while the timer was frozen: %s" % str(ev))
			break
	if int(cl.anger_ticks) != 100:
		f.append("pause: anger %d after 500 frozen ticks, want 100" % int(cl.anger_ticks))
	# a pickup still calms him while frozen (the pickup pass runs before the pause check)
	_stand_on(ctl, cl, 0)
	ev.clear()
	ClawdsScript.tick(lv, [ctl], w, 601, ev)
	if int(cl.anger_ticks) != 0:
		f.append("pause: a pickup while frozen left anger %d, want 0" % int(cl.anger_ticks))
	# the data can turn the pause off: then the same ticks advance the timer
	cl.pause_when_beacon_open = false
	if cl.paused(lv):
		f.append("pause: the timer is frozen with anger_pause_when_beacon_open = false")
	for t3 in range(602, 702):
		ev.clear()
		ClawdsScript.tick(lv, [ctl], w, t3, ev)
	if int(cl.anger_ticks) != 100:
		f.append("pause NC: anger %d with the pause off, want 100" % int(cl.anger_ticks))


# ---- the state hash: a CLAWDS line, and a replay that hashes the same (D-T4-6) ----

func _hash_and_replay(f: Array[String]) -> void:
	var L := _gen_level(7, 1)
	# a level that carries no swarm dumps no CLAWDS line (every pre-existing dump is unchanged)
	var bare: Dictionary = VoidGenScript.generate(7, 1)
	var rs0 = RunStateScript.new_run(7, 1, [])
	rs0.load_level(bare, 1)
	if "\n".join(HashScript.dump(rs0)).contains("CLAWDS "):
		f.append("hash: a level without attach() dumps a CLAWDS line (old dumps would move)")
	var rs = RunStateScript.new_run(7, 1, [])
	rs.load_level(L, 1)
	if rs.level.clawds == null:
		f.append("hash: the fixture level carries no swarm")
		return
	var dump := "\n".join(HashScript.dump(rs))
	if not dump.contains("CLAWDS "):
		f.append("hash: the state dump carries no CLAWDS line")
	var a := _record(L, false)
	var b := _record(L, false)
	var p := _record(L, true)
	if int(a["picks"]) < 1:
		f.append("replay: the recorded run never collected a clawd")
	if a["hashes"] != b["hashes"]:
		f.append("replay: two replays of one script hashed differently")
	if not str(a["dump"]).contains("CLAWDS "):
		f.append("hash: the recorded dump carries no CLAWDS line")
	var diverged := 0
	for i in (a["hashes"] as Array).size():
		if (a["hashes"] as Array)[i] != (p["hashes"] as Array)[i]:
			diverged += 1
	if diverged == 0:
		f.append("replay NC: a perturbed replay hashed identically at every checkpoint")
	# the hash sees the timer alone: same positions, one tick of anger moved
	var rs2 = RunStateScript.new_run(7, 1, [])
	rs2.load_level(L, 1)
	var h1: String = HashScript.sha256(rs2)
	rs2.level.clawds.anger_ticks = 1
	if HashScript.sha256(rs2) == h1:
		f.append("hash: one tick of anger does not change the state hash")
	rs2.level.clawds.anger_ticks = 0
	if HashScript.sha256(rs2) != h1:
		f.append("hash: restoring the anger tick does not restore the hash")
	# ... and a collected clawd, and a fired warning
	rs2.level.clawds.taken[0] |= 1
	if HashScript.sha256(rs2) == h1:
		f.append("hash: a collected clawd does not change the state hash")
	rs2.level.clawds.taken[0] = 0
	rs2.level.clawds.warned = 1
	if HashScript.sha256(rs2) == h1:
		f.append("hash: a fired warning does not change the state hash")


## 600 ticks of a fixed script: stand on clawd 0 from tick 120 (perturb: from tick 180), hash every 60.
func _record(L: Dictionary, perturb: bool) -> Dictionary:
	var rs = RunStateScript.new_run(7, 1, [])
	rs.load_level(L, 1)
	var lv = rs.level
	var w := _world(L)
	var ctl = _spent_ctl(w)
	var hashes: Array = []
	var picks := 0
	var on := 180 if perturb else 120
	for t in range(1, 601):
		if t == on and lv.clawds.count() > 0:
			_stand_on(ctl, lv.clawds, 0)
		var ev: Array = []
		ClawdsScript.tick(lv, [ctl], w, t, ev)
		for e in ev:
			if str((e as Dictionary).get("e", (e as Dictionary).get("type", ""))) == "clawd_collected":
				picks += 1
		if t % 60 == 0:
			hashes.append(HashScript.sha256(rs))
	return {"hashes": hashes, "picks": picks, "dump": "\n".join(HashScript.dump(rs))}


# ---- the anim block wiring (through view/enemy_anim.gd, T-084's contract) -----

func _anim_block_wiring(f: Array[String]) -> void:
	var doc_text := FileAccess.get_file_as_string(SHEET)
	var doc: Dictionary = JSON.parse_string(doc_text)
	if not (doc is Dictionary) or not doc.has("anim"):
		f.append("anim: sprites.json has no anim block")
		return
	var states: Dictionary = doc["anim"]["states"]
	# the two states the revamped behavior can reach exist in the block
	for state_id in ["spawn", "idle"]:
		if not states.has(state_id):
			f.append("anim: the block is missing state '%s'" % state_id)
	# the spawn fade blocks contact for its 30 ticks (section 1.0)
	var p = EnemyAnim.new()
	p.setup("claude", doc, FOLDER)
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
	var row := {"anim_state": "idle", "anim_state_t": 0, "age": 180, "x": 5.0, "y": 0.0, "z": 0.5}
	v.position = Vector3(5.0, 0.0, 0.5)
	v.sync(row, DT)
	if v.anim_player.state_id != "idle":
		f.append("view: the anim player is not on the sim's state")
	# the anger tint: at full anger the logo is redder than at rest
	var calm: Color = v.billboard.modulate
	v.set_anger(1.0)
	v.sync(row, DT)
	var hot: Color = v.billboard.modulate
	if hot.g >= calm.g or hot.b >= calm.b:
		f.append("view: the anger tint did not redden the logo (%s -> %s)" % [str(calm), str(hot)])
	# a warning leaves a 30-tick flash on the logo
	v.on_warning(1)
	if int(v._flash) != 30:
		f.append("view: a warning left %d flash ticks, want 30" % int(v._flash))
	v.free()
	# the clawd sprites: one per live clawd, hidden when taken or when its tile is gone
	var L := _flat_level(22)
	ClawdsScript.attach(L, ClaudeEnemy.clawd_cfg())
	var cl = ClawdsScript.create(L)
	var cv = ClawdViewScript.new()
	cv.setup(cl)
	cv.sync(cl, 0)
	if _sprite_count(cv._root) != cl.remaining():
		f.append("view: %d clawd sprites for %d live clawds"
			% [_sprite_count(cv._root), cl.remaining()])
	cl.taken[0] |= 1
	cv.sync(cl, 1)
	if _sprite_count(cv._root) != cl.remaining():
		f.append("view: a collected clawd still draws (%d sprites, %d live)"
			% [_sprite_count(cv._root), cl.remaining()])
	var removed := {}
	removed[cl.tile_key(1)] = true
	cv.set_removed(removed)
	cv.sync(cl, 2)
	if _sprite_count(cv._root) != cl.remaining() - 1:
		f.append("view: a clawd on a removed tile still draws (%d sprites, %d live)"
			% [_sprite_count(cv._root), cl.remaining()])
	cv.free()


## The clawd sprites under the view's root: the collected pops are MeshInstance3D children of the same node,
## so a raw child count would count them too.
static func _sprite_count(root) -> int:
	var n := 0
	for c in root.get_children():
		if c is Sprite3D:
			n += 1
	return n


# ---- the HUD pill: the clawd counter and the anger clock (D-T4-8) -------------
func _hud_meter(f: Array[String]) -> void:
	var m = AngerMeterScript.new()
	m.sync({})
	if m.meter_text() != "" or m.visible:
		f.append("hud: the pill is visible on a level with no swarm")
	m.sync({"active": true, "taken": 3, "total": 8, "anger_ticks": 0, "warned": 0,
		"kill_ticks": KILL, "next_at": WARN_1, "paused": false})
	if not m.visible:
		f.append("hud: the pill is hidden on a level with a swarm")
	_eq(f, "hud calm", m.meter_text(), "CLAWD 3 / 8   CALM 60s")
	if m.border_color() == AngerMeterScript.WARN_COLOR or m.border_color() == AngerMeterScript.KILL_COLOR:
		f.append("hud: the calm pill already wears a warning border")
	m.sync({"active": true, "taken": 3, "total": 8, "anger_ticks": WARN_1, "warned": 1,
		"kill_ticks": KILL, "next_at": WARN_2, "paused": false})
	_eq(f, "hud warning 1", m.meter_text(), "CLAWD 3 / 8   ANGRY 1:00")
	if m.border_color() != AngerMeterScript.WARN_COLOR:
		f.append("hud: warning 1 does not wear the amber border")
	m.sync({"active": true, "taken": 3, "total": 8, "anger_ticks": WARN_2, "warned": 2,
		"kill_ticks": KILL, "next_at": KILL, "paused": false})
	_eq(f, "hud warning 2", m.meter_text(), "CLAWD 3 / 8   CLAUDE 1:00")
	if m.border_color() != AngerMeterScript.KILL_COLOR:
		f.append("hud: warning 2 does not wear the hazard border")
	m.sync({"active": true, "taken": 3, "total": 8, "anger_ticks": WARN_2, "warned": 2,
		"kill_ticks": KILL, "next_at": KILL, "paused": true})
	_eq(f, "hud paused", m.meter_text(), "CLAWD 3 / 8   PAUSED")
	if m.border_color() != AngerMeterScript.PAUSE_COLOR:
		f.append("hud: the frozen pill does not wear the pause border")
	# the pill sits below the collapse warning, in the same top-centre column
	if absf(m.offset_top - (AngerMeterScript.EDGE)) > 0.001:
		f.append("hud: the pill's top is %.1f, want %.1f" % [m.offset_top, AngerMeterScript.EDGE])
	m.free()


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
