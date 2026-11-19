#
# Three enemy-runtime fixes pinned (one section each, every section carries a
# negative control):
#
#   1. the dropped stats telegraph_mul (early_warning / hasty) and enemy_speed_mul
#      (rush_hour) get a consumer: EnemyRuntime.apply_stats() feeds curse_speed_mul
#      (FloatBody's knob) from enemy_speed_mul, and telegraph() scales every
#      announcement's ticks/total by telegraph_mul. The dict is the full truth once
#      applied; an empty dict (or one without the keys) leaves the canon 1.0 base.
#   2. PARKED.md row 7 - the per-player enumeration the nuke's 5 u blast needs:
#      players_in_radius(pos, r) (sphere, inclusive), entry shape identical to
#      nearest_player's. The nuke BEHAVIOUR's call site (content/enemies/nuke/
#      enemy.gd) is outside this wave's allowed files - see the wave report.
#   3. PARKED.md row 5 / DESIGN.md section 5 - preferred_kind "none" skips steps
#      (a) AND (b): the spawn rule goes straight to fallback (c). Implemented since
#      T-032; pinned here with a negative control ("" keeps the merged semantics).
#
# Never weakens test_telegraph_expiry.gd: the telegraph pins below only ADD a
# multiplier-aware read; the expiry clock (start tick + total) is unchanged.

extends RefCounted

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Util := preload("res://tests/sim_testutil.gd")
const ContentApiScript := preload("res://core/content_api.gd")

const DT := 1.0 / 60.0


func run() -> Array[String]:
	var f: Array[String] = []
	_telegraph_mul(f)
	_enemy_speed_mul(f)
	_players_in_radius(f)
	_none_anchor_kind(f)
	return f


# A synthetic level whose anchors LURE steps (a)/(b): a 45 u perch and a 55 u lane
# (the farthest in-window picks), plus a bridge column so the round-trip set exists.
# Same shape as test_spawn_rule.gd's fixture.
func _level() -> Dictionary:
	var tiles: Array = []
	for x in range(0, 100):
		tiles.append([x, 0, 0, 0, 0])
		tiles.append([x, 5, 0, 0, 1])
	for z in range(1, 5):
		tiles.append([0, z, 0, 0, 2])
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]],
			"anchors": [
				[0, 45, 5, 0, 1],   # perch, 45 u - the in-window (a) pick
				[2, 55, 5, 0, 1],   # lane, 55 u - the in-window (b) pick
			],
			"tiles": tiles, "props": [], "pads": []}


func _mk_world() -> Dictionary:
	return {"cols": {}, "prop_cols": {}, "pads": {}, "dais": [0, 0, 0], "glitched": {},
			"slippery": {}, "removed": {}, "kill_y": -40.0, "enemies": [], "projectiles": [],
			"hazards": []}


func _mk_ctl(w: Dictionary, x: float, y: float, z: float):
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.x = x
	ctl.y = y
	ctl.z = z
	ctl.grounded = true
	return ctl


# The stats dict world.gd will compute at build, built the same way
# test_stats_consumers.gd builds it: a real controller's base_stats() as base, the
# owned ids' modifiers repeated per stack, sorted - the mods_for_stacks +
# apply_modifiers pair.
static func _stats_for(stacks: Dictionary, curses: Dictionary) -> Dictionary:
	var api: RefCounted = ContentApiScript.load()
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	var mods: Array = []
	var curse_ids: Array = curses.keys()
	curse_ids.sort()
	for id in curse_ids:
		mods.append_array(ContentApiScript.mods_for_stacks(
				api.curse(str(id)).get("modifiers", []), int(curses[id])))
	var upgrade_ids: Array = stacks.keys()
	upgrade_ids.sort()
	for id in upgrade_ids:
		mods.append_array(ContentApiScript.mods_for_stacks(
				api.upgrade(str(id)).get("modifiers", []), int(stacks[id])))
	return ContentApiScript.apply_modifiers(ctl.base_stats(), mods,
			{"phase": "", "class": "dasher"})

# ---- 1a. telegraph_mul: the announcement's ticks/total are scaled ------------

func _telegraph_mul(f: Array[String]) -> void:
	var w := _mk_world()
	var ctl = _mk_ctl(w, 0.5, 0.0, 0.5)
	var rt = EnemyRuntime.new()
	var lv := _level()
	rt.setup(lv, w, [ctl], 7)
	# BASE BEHAVIOUR HOLDS: no stats applied - a 100 tick telegraph is 100 ticks
	rt.telegraph({"id": "t"}, "test_patch", {"shape": "circle", "cx": 0.5, "cz": 0.5, "r": 2.0}, 100)
	var base_row: Dictionary = rt.telegraphs[rt.telegraphs.size() - 1]
	if int(base_row["ticks"]) != 100 or int(base_row["total"]) != 100:
		f.append("telegraph_mul: unscaled telegraph held %s/%s ticks, want 100/100"
				% [str(base_row["ticks"]), str(base_row["total"])])
	# WITH THE CURSE HELD the behaviour changes: hasty x0.85 per stack shrinks it
	var hasty := _stats_for({}, {"hasty": 2})
	if absf(float(hasty.get("telegraph_mul", -1.0)) - 0.7225) > 1e-9:
		f.append("telegraph_mul: the hasty x2 dict carries %s, want 0.7225"
				% str(hasty.get("telegraph_mul")))
	rt.apply_stats(hasty)
	rt.telegraph({"id": "t2"}, "test_patch", {"shape": "circle", "cx": 0.5, "cz": 0.5, "r": 2.0}, 100)
	var shrunk: Dictionary = rt.telegraphs[rt.telegraphs.size() - 1]
	if int(shrunk["ticks"]) != 72 or int(shrunk["total"]) != 72:
		f.append("telegraph_mul: hasty x2 telegraph held %s/%s ticks, want 72/72"
				% [str(shrunk["ticks"]), str(shrunk["total"])])
	# ... and the expiry clock uses the SCALED total (a hasty telegraph stops
	# blocking the gate at its own earlier end, never at the base 100)
	for i in range(80):
		rt.step(DT)
	var live: bool = false
	for t in rt._live_telegraphs():
		if str(t.get("source", "")) == "t2":
			live = true
	if live:
		f.append("telegraph_mul: a hasty telegraph is still live 80 ticks in, want expired at 72")
	# ... and the upgrade stretches it: early_warning x1.15 per stack lengthens it
	var ew := _stats_for({"early_warning": 2}, {})
	if absf(float(ew.get("telegraph_mul", -1.0)) - 1.3225) > 1e-9:
		f.append("telegraph_mul: the early_warning x2 dict carries %s, want 1.3225"
				% str(ew.get("telegraph_mul")))
	rt.apply_stats(ew)
	rt.telegraph({"id": "u"}, "test_patch", {"shape": "circle", "cx": 0.5, "cz": 0.5, "r": 2.0}, 100)
	var stretched: Dictionary = rt.telegraphs[rt.telegraphs.size() - 1]
	if int(stretched["ticks"]) != 132 or int(stretched["total"]) != 132:
		f.append("telegraph_mul: early_warning x2 telegraph held %s/%s ticks, want 132/132"
				% [str(stretched["ticks"]), str(stretched["total"])])
	# the event stream carries the scaled number too
	var found := false
	for e in rt.events:
		if str(e.get("e", "")) == "telegraph" and str(e.get("source", "")) == "u":
			found = true
			if int(e.get("ticks", -1)) != 132:
				f.append("telegraph_mul: the telegraph event carries %s ticks, want 132"
						% str(e.get("ticks")))
	if not found:
		f.append("telegraph_mul: no telegraph event for the early_warning row")
	# NEGATIVE CONTROL: an empty dict resets to the canon 1.0 (nothing scaled)
	rt.apply_stats({})
	rt.telegraph({"id": "v"}, "test_patch", {"shape": "circle", "cx": 0.5, "cz": 0.5, "r": 2.0}, 100)
	var reset: Dictionary = rt.telegraphs[rt.telegraphs.size() - 1]
	if int(reset["ticks"]) != 100:
		f.append("telegraph_mul: an empty dict scaled to %s ticks, want the canon 100"
				% str(reset["ticks"]))


# ---- 1b. enemy_speed_mul: FloatBody feels the stats dict ----------------------

func _enemy_speed_mul(f: Array[String]) -> void:
	var w := _mk_world()
	var ctl = _mk_ctl(w, 0.5, 0.0, 0.5)
	var rt = EnemyRuntime.new()
	rt.setup(_level(), w, [ctl], 7)
	var cfg := {"base_speed": 3.0, "pursuit_ceiling": 1.0, "burst_ceiling": 1.0}
	# BASE BEHAVIOUR HOLDS: no stats applied - h_speed is exactly base_speed
	var row := {"id": "fb", "x": 10.0, "y": 0.0, "z": 0.5}
	var body := EnemyRuntime.FloatBody.from_cfg(cfg)
	body.update(_api_of(rt, row), 1)
	if absf(body.h_speed - 3.0) > 1e-6:
		f.append("enemy_speed_mul: unscaled h_speed %.4f, want 3.0" % body.h_speed)
	# WITH THE CURSE HELD: rush_hour x1.08 per stack flows through FloatBody
	var rush := _stats_for({}, {"rush_hour": 3})
	if absf(float(rush.get("enemy_speed_mul", -1.0)) - 1.08 * 1.08 * 1.08) > 1e-9:
		f.append("enemy_speed_mul: the rush_hour x3 dict carries %s, want 1.259712"
				% str(rush.get("enemy_speed_mul")))
	rt.apply_stats(rush)
	body.update(_api_of(rt, row), 1)
	var want := 3.0 * 1.08 * 1.08 * 1.08
	if absf(body.h_speed - want) > 1e-6:
		f.append("enemy_speed_mul: h_speed %.4f, want %.4f (rush_hour x3 through FloatBody)"
				% [body.h_speed, want])
	# NEGATIVE CONTROL: an empty dict resets to the canon 1.0 (no free speed)
	rt.apply_stats({})
	body.update(_api_of(rt, row), 1)
	if absf(body.h_speed - 3.0) > 1e-6:
		f.append("enemy_speed_mul: an empty dict left h_speed at %.4f, want 3.0"
				% body.h_speed)


# A bare Api bound to rt/row - FloatBody only reads speed_mul/curse_speed_mul/
# clamp_pursuit off it.
func _api_of(rt, row: Dictionary):
	var api = EnemyRuntime.Api.new()
	api.rt = rt
	api.row = row
	return api

# ---- 2. PARKED.md row 7: every player inside the blast sphere is enumerated ----

func _players_in_radius(f: Array[String]) -> void:
	var w := _mk_world()
	# two controllers inside the 5 u sphere, one outside (8 u away)
	var ctl0 = _mk_ctl(w, 0.5, 0.0, 0.5)
	var ctl1 = _mk_ctl(w, 3.0, 0.0, 2.0)
	var ctl2 = _mk_ctl(w, 9.0, 0.0, 0.5)
	var rt = EnemyRuntime.new()
	rt.setup(_level(), w, [ctl0, ctl1, ctl2], 7)
	var det := Vector3(0.5, 0.0, 0.5)
	var hits: Array = rt.players_in_radius(det, 5.0)
	var idx: Array = []
	for h in hits:
		idx.append(int(h["index"]))
	idx.sort()
	if idx.size() != 2 or idx[0] != 0 or idx[1] != 1:
		f.append("players_in_radius: the sphere reached %s, want both [0, 1]" % str(idx))
	# entry shape matches nearest_player's (index/dist/x/y/z/v*) so a blast can
	# hand each entry straight to api.kill(entry["index"], ...)
	for h in hits:
		for key in ["index", "dist", "x", "y", "z", "vx", "vy", "vz"]:
			if not h.has(key):
				f.append("players_in_radius: entry missing key '%s'" % key)
	for h in hits:
		if int(h["index"]) == 1:
			var want_d := Vector3(3.0 - 0.5, 0.0, 2.0 - 0.5).length()
			if absf(float(h["dist"]) - want_d) > 1e-6:
				f.append("players_in_radius: index 1 dist %.4f, want %.4f"
						% [float(h["dist"]), want_d])
	# boundary is INCLUSIVE: a player exactly at r is in (the blast's <= rule)
	var edge = _mk_ctl(_mk_world(), 0.5 + 5.0, 0.0, 0.5)
	var rt2 = EnemyRuntime.new()
	rt2.setup(_level(), _mk_world(), [edge], 7)
	var edge_hits: Array = rt2.players_in_radius(det, 5.0)
	if edge_hits.size() != 1:
		f.append("players_in_radius: a player exactly at r was not enumerated (inclusive boundary)")
	# the Api surface exposes the same enumeration to behaviours
	var api = EnemyRuntime.Api.new()
	api.rt = rt
	api.row = {"id": "probe"}
	var api_hits: Array = api.players_in_radius(det, 5.0)
	if api_hits.size() != 2:
		f.append("players_in_radius: the Api wrapper enumerated %d players, want 2"
				% api_hits.size())
	# NEGATIVE CONTROL: a sphere that reaches nobody returns empty, and the
	# 8 u-away player never appears even in a huge radius' absence - shrink the
	# radius below ctl1's distance: only ctl0 (at det) may remain
	var tiny: Array = rt.players_in_radius(det, 0.25)
	if tiny.size() != 1 or int(tiny[0]["index"]) != 0:
		f.append("players_in_radius: the 0.25 u sphere enumerated %s, want only [0]"
				% str(tiny.map(func(h): return h["index"])))
	var none: Array = rt.players_in_radius(Vector3(50.0, 0.0, 50.0), 5.0)
	if not none.is_empty():
		f.append("players_in_radius: an empty sphere enumerated %s, want []" % str(none))


# ---- 3. PARKED.md row 5 / DESIGN section 5: preferred_kind "none" -------------

func _none_anchor_kind(f: Array[String]) -> void:
	var lv := _level()
	var player := Vector3(0.5, 0.0, 0.5)
	# DESIGN section 5: `none` skips (a) AND (b) - the pick is the fallback (c)
	# round-trip tile, never the lure perch (45 u) or the lure lane (55 u)
	var s: Variant = EnemyRuntime.pick_spawn_tile(lv, "none", player)
	if s == null:
		f.append("none spawn: no fallback (c) tile at all")
		return
	if str(s.get("kind", "")) != "round_trip":
		f.append("none spawn: kind %s, want round_trip (the anchors must not answer)"
				% str(s.get("kind", "?")))
	if s.has("anchor_index"):
		f.append("none spawn: an anchor was used (index %s), want fallback (c)"
				% str(s.get("anchor_index")))
	# NEGATIVE CONTROL 1: the same level with the lure kinds live - "" keeps the
	# merged T-027 semantics (skip (a), still run (b)): the 55 u lane answers
	var s_lane: Variant = EnemyRuntime.pick_spawn_tile(lv, "", player)
	if s_lane == null or int(s_lane.get("anchor_index", -1)) != 1:
		f.append("none spawn negative control: \"\" returned %s, want the 55 u lane (anchor index 1)"
				% str(s_lane))
	# NEGATIVE CONTROL 2: "perch" runs (a): the 45 u perch answers - proving the
	# level lures (a) and the \"none\" result above was the rule, not the level
	var s_perch: Variant = EnemyRuntime.pick_spawn_tile(lv, "perch", player)
	if s_perch == null or int(s_perch.get("anchor_index", -1)) != 0:
		f.append("none spawn negative control: \"perch\" returned %s, want the 45 u perch (anchor index 0)"
				% str(s_perch))
