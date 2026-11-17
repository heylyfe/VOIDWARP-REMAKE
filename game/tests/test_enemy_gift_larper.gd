extends RefCounted
#
# T-036 gift Larper - DESIGN.md section 5.7 + section 3.3 (every number, +/-1 tick where a
# timing exists), the contact-kill rule (the section 3.3 ladder) and its death code, and the
# cfg/enemy.json coherence of the roster. ENEMIES.md (Behavior 1:1): "stationary hazard, same
# as Nullscape - detonates when triggered by a player stepping on it."
#
#   - stationary: base_speed 0.0 (D-T-036-2); the row never moves, stepped 240 ticks;
#   - body 1.0 u tall, hit diameter 0.8 u (D-T-036-1 [CONTESTABLE] - SR-2 gives it no row);
#   - contact = the player's CENTRE within 0.9 u HORIZONTAL, ANY height (D-058): jumping
#     over the mine does NOT avoid it - asserted at jump-apex height (2.25 u);
#   - the ladder in the fixed order (D-058): the kill D-MINE with Last Light ALREADY SPENT
#     (D-057 - otherwise the save masks the kill), and Last Light available -> saved, not dead;
#   - the runtime's plain body-contact path is DISABLED for this row (cfg contact_kill=false,
#     D-T-036-3): spawn_at + overlap never kills - only the ladder does;
#   - 5-frame rotation cycle: 48 ticks per frame, 240 ticks (4.0 s -/+0) per revolution, 1 rev /
#     4.0 s (section 3.3 CANON + the T-083 anim block);
#   - attack_detonation 18 TOTAL ticks, defused 24 TOTAL ticks (T-083 anim block);
#   - tell: pink particles inside 12.0 u (boundary inclusive), beyond it none;
#   - each vote = +3 flat mines (5 votes = +15, clamped);
#   - first shown at level 5 (section 3.3 CANON), max_votes 5, preferred anchor kind NONE
#     (it lives in gift slots), death code D-MINE (DESIGN.md section 3.1 FINAL).
#
# The answer window (FLEET_PACK): walk around it - 12.0 u of tell at run speed 9.0 u/s is
# 80 ticks (1.33 s) of warning; D-026 guarantees a walkable bypass. Asserted as arithmetic.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const MinesScript := preload("res://sim/mines.gd")
const DeathScript := preload("res://sim/death.gd")
const Util := preload("res://tests/sim_testutil.gd")
const GiftLarperScript := preload("res://content/enemies/gift_larper/enemy.gd")
const GiftLarperViewScript := preload("res://view/gift_larper_view.gd")

const DT := 1.0 / 60.0
const TEST_LEVEL := 7
var LARPER_CFG: Dictionary = GiftLarperScript.cfg()


# One slot that is a mine (slot 0, world (0.5, 0.0, 0.5)) - the same Level.gifts shape the
# mines.gd tests use.
func _mine_level() -> Dictionary:
	var slots: Array = [{"id": 0, "x": 0, "z": 0, "y": 0, "piece": 0, "tier": 0, "occ": 1}]
	return {"gifts": slots}


func _holder(m: RefCounted, ctls: Array) -> Dictionary:
	var players: Array = []
	for c in ctls:
		players.append({"x": float(c.x), "y": float(c.y), "z": float(c.z)})
	return {"mines": m, "players": players, "beacon": null}


func _ctl_at(height: float) -> RefCounted:
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.x = 0.5
	ctl.y = height
	ctl.z = 0.5
	return ctl


# [runtime, controller]; controller sits at (0.5, 0.0, 0.5), Last Light already spent (D-057).
func _runtime() -> Array:
	var w := {"cols": {}, "prop_cols": {}, "pads": {}, "dais": [0, 0, 0], "glitched": {},
			"slippery": {}, "removed": {}, "kill_y": -40.0, "enemies": [], "projectiles": [],
			"hazards": []}
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true
	var lv := {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]],
			"anchors": [], "tiles": [[0, 0, 0, 0, 0]], "props": [], "pads": []}
	var rt = EnemyRuntime.new()
	rt.setup(lv, w, [ctl], 7)
	return [rt, ctl]


func _spawn_larper(rt, pos: Vector3) -> Dictionary:
	return rt.spawn_at("gift_larper", "gift Larper", GiftLarperScript.GiftLarperBehavior.new(),
			LARPER_CFG.duplicate(true), pos)


func _cfg_coherence(f: Array[String]) -> void:
	var text := FileAccess.get_file_as_string("res://content/enemies/gift_larper/enemy.json")
	var doc: Variant = JSON.parse_string(text)
	if not (doc is Dictionary):
		f.append("cfg: enemy.json unreadable")
		return
	var d := doc as Dictionary
	var stats: Dictionary = d.get("stats", {})
	_eq(f, "enemy.json id", str(d.get("id")), "gift_larper")
	_eq(f, "enemy.json name", str(d.get("name")), "gift Larper")
	_eq(f, "min_level", int(d.get("min_level")), 5)
	_eq(f, "max_votes", int(d.get("max_votes")), 5)
	_eq(f, "vote_effect", str(d.get("vote_effect")), "extra_mines += 3")
	_eq(f, "anchor_kinds", str(d.get("anchor_kinds")), str([]))
	_eq(f, "world_height", float(stats.get("world_height")), 1.0)
	_eq(f, "body_height", float(stats.get("body_height")), 1.0)
	_eq(f, "hit_diameter", float(stats.get("hit_diameter")), 0.8)
	_eq(f, "base_speed", float(stats.get("base_speed")), 0.0)
	_eq(f, "pursuit_ceiling", float(stats.get("pursuit_ceiling")), 0.0)
	_eq(f, "burst_ceiling", float(stats.get("burst_ceiling")), 0.0)
	_eq(f, "contact_radius", float(stats.get("contact_radius")), 0.9)
	_eq(f, "tell_distance", float(stats.get("tell_distance")), 12.0)
	_eq(f, "blast_radius", float(stats.get("blast_radius")), 3.0)
	_eq(f, "rotation_period", float(stats.get("rotation_period")), 4.0)
	_eq(f, "rotation_ticks", int(stats.get("rotation_ticks")), 240)
	_eq(f, "frame_ticks", int(stats.get("frame_ticks")), 48)
	_eq(f, "frames", int(stats.get("frames")), 5)
	_eq(f, "detonation_ticks", int(stats.get("detonation_ticks")), 18)
	_eq(f, "defused_ticks", int(stats.get("defused_ticks")), 24)
	_eq(f, "defuse_drop_u", float(stats.get("defuse_drop_u")), 0.5)
	_eq(f, "contact_kill cfg", str(bool(stats.get("contact_kill"))), "false")
	_eq(f, "death_code", str(stats.get("death_code")), "D-MINE")
	_eq(f, "audio cues", str(stats.get("audio_cues")), str(["explosion", "pff", "mine_hum"]))
	_eq(f, "behavior line", str(d.get("behavior", "").length() > 0), "true")
	_eq(f, "counter_play line", str(d.get("counter_play", "").length() > 0), "true")
	_eq(f, "tell line", str(d.get("tell", "").length() > 0), "true")
	_eq(f, "behavior cfg base_speed", float(LARPER_CFG["base_speed"]), 0.0)
	_eq(f, "behavior cfg pursuit_ceiling", float(LARPER_CFG["pursuit_ceiling"]), 0.0)
	_eq(f, "behavior cfg hit_diameter", float(LARPER_CFG["hit_diameter"]), 0.8)
	_eq(f, "behavior cfg contact_kill", str(bool(LARPER_CFG["contact_kill"])), "false")
	_eq(f, "behavior cfg death_code", str(LARPER_CFG["death_code"]), "D-MINE")
	_eq(f, "behavior cfg preferred_kind", str(LARPER_CFG["preferred_kind"]), "")
	_eq(f, "behavior cfg rotation_ticks", int(LARPER_CFG["cycle_ticks"]), 240)
	# sprites.json: world_height pinned 1.0 (D-T-036-1), 5 frames, T-083 anim timings
	var stext := FileAccess.get_file_as_string("res://content/enemies/gift_larper/sprites.json")
	var sdoc: Variant = JSON.parse_string(stext)
	if not (sdoc is Dictionary):
		f.append("sprites: sprites.json unreadable")
		return
	var s := sdoc as Dictionary
	_eq(f, "sprites world_height", float(s.get("world_height")), 1.0)
	var frames: Array = ((s.get("animations", []) as Array)[0] as Dictionary).get("frames", [])
	_eq(f, "frame count", frames.size(), 5)
	var states: Dictionary = ((s.get("anim", {})) as Dictionary).get("states", {})
	_eq(f, "idle ticks_per_frame", float((states.get("idle", {}) as Dictionary).get("ticks_per_frame", 0.0)), 48.0)
	_eq(f, "attack_detonation total_ticks",
			int((states.get("attack_detonation", {}) as Dictionary).get("total_ticks", 0)), 18)
	_eq(f, "defused total_ticks",
			int((states.get("defused", {}) as Dictionary).get("total_ticks", 0)), 24)
	var idle_fx: Dictionary = ((states.get("idle", {}) as Dictionary).get("effect", {})).get("params", {})
	_eq(f, "idle revolution_ticks", int(idle_fx.get("revolution_ticks", 0)), 240)
	_eq(f, "tell range param", float(idle_fx.get("tell_range_u", 0.0)), 12.0)
	# the D-MINE killer display name (death.gd's FINAL map)
	_eq(f, "D-MINE killer", str(DeathScript.CODES.get("D-MINE", "")), "gift Larper (Tripmine)")


func _eq(f: Array[String], what: String, got, want) -> void:
	if str(got) != str(want):
		f.append("%s: got %s, want %s" % [what, str(got), str(want)])


func run() -> Array[String]:
	var f: Array[String] = []
	_cfg_coherence(f)
	_extra_mines(f)
	_stationary(f)
	_ladder_kills_dmie(f)
	_height_blind_contact(f)
	_last_light_saves_when_available(f)
	_runtime_contact_never_kills(f)
	_rotation_cycle_ticks(f)
	_view_frames_and_effects(f)
	_answer_window_arithmetic(f)
	return f


# +3 per vote, clamped to the roster's 5 (=> +15); TERRAIN_SPEC section 6.8 caps the total.
func _extra_mines(f: Array[String]) -> void:
	var cases := {0: 0, 1: 3, 2: 6, 3: 9, 4: 12, 5: 15, 99: 15}
	for votes in cases.keys():
		var got: int = GiftLarperScript.extra_mines(int(votes))
		if got != int(cases[votes]):
			f.append("extra_mines(%d): got %d, want %d" % [int(votes), got, int(cases[votes])])


# 240 ticks station-keeping: the row never drifts (no chase, no wander).
func _stationary(f: Array[String]) -> void:
	var pair := _runtime()
	var rt = pair[0]
	var row := _spawn_larper(rt, Vector3(0.5, 1.0, 0.5))
	for i in range(240):
		rt.step(DT)
	if float(row["x"]) != 0.5 or float(row["y"]) != 1.0 or float(row["z"]) != 0.5:
		f.append("stationary: the mine moved to (%.3f, %.3f, %.3f)" % [row["x"], row["y"], row["z"]])


# Last Light ALREADY SPENT (D-057): the contact kills, D-MINE, and the blast consumes the mine.
func _ladder_kills_dmie(f: Array[String]) -> void:
	var m: RefCounted = MinesScript.create(_mine_level(), TEST_LEVEL, 11)
	var ctl := _ctl_at(0.0)
	ctl.last_light_spent = true
	var events: Array = []
	MinesScript.tick(_holder(m, [ctl]), [ctl], {"dais": [0, 0, 0], "enemies": []}, [0], 7, events)
	if not bool(ctl.dead):
		f.append("ladder: the contact did not kill (Last Light spent)")
		return
	if str(ctl.dead_code) != "D-MINE":
		f.append("ladder: death code %s, want D-MINE" % str(ctl.dead_code))
	var deaths: Array = []
	for e in events:
		if str(e.get("e", "")) == "death":
			deaths.append(e)
	if deaths.is_empty():
		f.append("ladder: no death event after the contact kill")
	else:
		_eq(f, "death killer", str(deaths[0].get("killer", "")), "gift Larper (Tripmine)")
	if not m.is_consumed(0):
		f.append("ladder: the mine was not consumed by the detonation")


# ANY height, D-058: jumping to the 2.25 u apex over the mine still detonates it.
func _height_blind_contact(f: Array[String]) -> void:
	var m: RefCounted = MinesScript.create(_mine_level(), TEST_LEVEL, 11)
	var ctl := _ctl_at(2.25)   # the jump apex; feet never touch the box
	ctl.last_light_spent = true
	var events: Array = []
	MinesScript.tick(_holder(m, [ctl]), [ctl], {"dais": [0, 0, 0], "enemies": []}, [0], 7, events)
	if not bool(ctl.dead):
		f.append("height-blind: a jump-apex contact did not kill (the trigger is any height)")
	elif str(ctl.dead_code) != "D-MINE":
		f.append("height-blind: death code %s, want D-MINE" % str(ctl.dead_code))


# Last Light AVAILABLE (not spent, charges held): the ladder spends it and the player lives;
# the mine is consumed and no death event fires (D-057 makes this the counter-case).
func _last_light_saves_when_available(f: Array[String]) -> void:
	var m: RefCounted = MinesScript.create(_mine_level(), TEST_LEVEL, 11)
	var ctl := _ctl_at(0.0)
	ctl.last_light_spent = false
	ctl.charges = 2
	var events: Array = []
	MinesScript.tick(_holder(m, [ctl]), [ctl], {"dais": [0, 0, 0], "enemies": []}, [0], 7, events)
	if bool(ctl.dead):
		f.append("last light: the player died with Last Light available and charges held")
		return
	if not bool(ctl.last_light_spent):
		f.append("last light: the save was not spent on the contact")
	if not m.is_consumed(0):
		f.append("last light: the mine was not consumed by the saved contact")
	var deaths := 0
	for e in events:
		if str(e.get("e", "")) == "death":
			deaths += 1
	if deaths != 0:
		f.append("last light: %d death events, want 0 (the save consumed it)" % deaths)


# D-T-036-3: the runtime's plain body-contact path NEVER fires for this row (the ladder owns
# the kill); a stepped row overlapping the player kills nothing.
func _runtime_contact_never_kills(f: Array[String]) -> void:
	var pair := _runtime()
	var rt = pair[0]
	var ctl = pair[1]
	_spawn_larper(rt, Vector3(ctl.x, 0.0, ctl.z))
	for i in range(120):
		rt.step(DT)
	if bool(ctl.dead):
		f.append("runtime path: the row killed through _contact_kills (the ladder must own the kill)")


# 5-frame cycle, 48 ticks per frame: frame flips at 48/96/144/192/240 ticks (+/-1), exactly one
# revolution per 240 ticks (4.0 s, the section 3.3 CANON turn).
func _rotation_cycle_ticks(f: Array[String]) -> void:
	var v = GiftLarperViewScript.new()
	v.setup()
	if v.billboard == null:
		f.append("rotation: the view built no billboard")
		return
	_eq(f, "rotation start frame", v.billboard.frame_i, 0)
	v.step(47)
	_eq(f, "frame at tick 47", v.billboard.frame_i, 0)
	v.step(1)   # 48 ticks
	_eq(f, "frame at tick 48", v.billboard.frame_i, 1)
	v.step(48)  # 96
	_eq(f, "frame at tick 96", v.billboard.frame_i, 2)
	v.step(48)  # 144
	_eq(f, "frame at tick 144", v.billboard.frame_i, 3)
	v.step(48)  # 192
	_eq(f, "frame at tick 192", v.billboard.frame_i, 4)
	v.step(48)  # 240 - one full revolution
	_eq(f, "frame at tick 240 (1 rev / 4.0 s)", v.billboard.frame_i, 0)
	_eq(f, "anim ticks after 240", v._anim_ticks, 240)
	_eq(f, "tell range wired", v.tell_range(), 12.0)
	v.free()


# The T-083 state windows: detonation 18 TOTAL ticks (flash + burst builds then clears),
# defused 24 TOTAL ticks (sprite hides), and on_spawn resets for a fresh level.
func _view_frames_and_effects(f: Array[String]) -> void:
	var v = GiftLarperViewScript.new()
	v.setup()
	if v.billboard == null:
		f.append("effects: the view built no billboard")
		return
	v.on_detonation()
	_eq(f, "detonation window left after start", v._det_left, 18)
	v.step(18)
	_eq(f, "detonation window after 18 ticks", v._det_left, 0)
	if v._burst != null and v._burst.visible:
		f.append("detonation: the burst is still visible after 18 ticks")
	v.on_defused()
	_eq(f, "defused window left after start", v._def_left, 24)
	v.step(24)
	_eq(f, "defused window after 24 ticks", v._def_left, 0)
	if v.billboard.visible:
		f.append("defused: the sprite is still visible after the 24-tick grey-out")
	v.on_spawn()
	if not v.billboard.visible:
		f.append("defused: on_spawn did not restore the sprite for a fresh level")
	v.free()


# The answer window (FLEET_PACK T-036): 12.0 u of tell at 9.0 u/s run speed = 1.33 s of
# warning (80 ticks); the 0.9 u trigger cylinder holds at any height (never jumpable); the
# walkable bypass is the only way past (D-026) - the mine's wall is the trigger itself.
func _answer_window_arithmetic(f: Array[String]) -> void:
	var consts: Dictionary = Util.consts()
	var run_speed := float(consts.get("run_speed", 9.0))
	var warning := 12.0 / run_speed
	if absi(int(round(warning * 60.0)) - 80) > 1:
		f.append("answer: 12.0 u tell at %.2f u/s = %d ticks, want ~80 (+/-1)"
				% [run_speed, int(round(warning * 60.0))])
	_eq(f, "trigger cylinder radius", float(GiftLarperScript.CONTACT_RADIUS), 0.9)
	_eq(f, "blast radius", float(GiftLarperScript.BLAST_RADIUS), 3.0)
	_eq(f, "tell boundary (inclusive)", float(GiftLarperScript.TELL_DISTANCE), 12.0)
	# the walkable bypass margin: the D-026 generator leaves a lane >= 1.0 u from the
	# trigger centre (TERRAIN_SPEC 6.8.1/6.8.2) - assert the cylinder leaves a strict gap
	if GiftLarperScript.CONTACT_RADIUS >= 1.0:
		f.append("answer: the 0.9 u cylinder would swallow the 1.0 u bypass margin")
