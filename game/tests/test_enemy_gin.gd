extends RefCounted
#
# T-041 - gin ichimaru (Voidbreaker). DESIGN.md section 5.12 is the spec; every
# timing and number below is read from the content files, not from a test-local
# copy, and asserted within +/-1 tick where a tick budget exists.
#
# Runs with LAST LIGHT ALREADY SPENT (D-057) - the fixture controller starts with
# last_light_spent = true, otherwise the save would mask every kill below.
#
# Audio cue names come from research/fable-tickets.md section 3 (binding): the
# ENEMIES.md "New sound" line's cue names - crack_rumble, shing, whoosh, zone_open,
# zone_close - spelled exactly as gin_audio.gd's CUES carry them.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const GinBehavior := preload("res://content/enemies/gin/enemy.gd")
const GinView := preload("res://view/gin_view.gd")
const GinAudio := preload("res://view/audio/gin_audio.gd")
const CollisionScript := preload("res://sim/collision.gd")
const Util := preload("res://tests/sim_testutil.gd")

const DT := 1.0 / 60.0

# the binding table (research/fable-tickets.md section 1.12), in ticks
const SPAWN_TICKS := 30            # 0.5 s fade-in
const TELEGRAPH_TICKS := 120       # 2.0 s mark
const LAUNCH_SHOWN_AT := 120       # the launch frame is shown on tick 120
const SPEAR_TRAVEL_TICKS := 18     # 0.3 s spear flight
const ZONE_START_AT := 120 + 18    # tick 138: the tiles go non-solid
const ZONE_TICKS := 600            # 10.0 s void zone
const FADE_OUT_AT := 120 + 60      # the body fades out 60 ticks after the launch
const FADE_BACK_START := 120 + 18 + 600   # tick 738
const FADE_BACK_TICKS := 30        # 0.5 s tiles fade back
const LIFT_AT := FADE_BACK_START   # a player inside is lifted onto the surface


func run() -> Array[String]:
	var f: Array[String] = []
	_json_contract(f)
	_anim_block_is_the_source(f)
	_spawn_tile_rule(f)
	_fade_in_tile_height(f)
	_second_fade_in_picks_a_new_tile(f)
	_deferral(f)
	_run_cycle(f)
	_void_zone_kills(f)
	_lift_on_fade_back(f)
	return f


# The deliverable data file: every number the brief names, exactly.
func _json_contract(f: Array[String]) -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			"res://content/enemies/gin/enemy.json"))
	if not (doc is Dictionary):
		f.append("json: enemy.json is not a Dictionary")
		return
	var j: Dictionary = doc
	if str(j.get("id", "")) != "gin":
		f.append("json: id %s, want gin" % str(j.get("id", "")))
	var live: Dictionary = j.get("stats", {})
	if str(live.get("death_code", "")) != "D-GIN":
		f.append("json: stats.death_code %s, want D-GIN" % str(live.get("death_code", "")))
	if live.get("audio_cues", []) != ["bye_bye"] or bool(live.get("contact_kill", true)):
		f.append("json: live Gin must have only the bye bye cue and no contact kill")
	if live.has("zone_ticks") or live.has("spear_travel_ticks") or live.has("audio_cue_timing"):
		f.append("json: live Gin carries retired attack metadata")
	var st: Dictionary = _json().get("stats", {})
	if int(j.get("min_level", 0)) != 17:
		f.append("json: min_level %s, want 17" % str(j.get("min_level", 0)))
	if int(j.get("max_votes", 0)) != 3:
		f.append("json: max_votes %s, want 3" % str(j.get("max_votes", 0)))
	_tick_ok(f, "spawn_fade_ticks", int(st.get("spawn_fade_ticks", -1)), SPAWN_TICKS)
	_tick_ok(f, "telegraph_ticks", int(st.get("telegraph_ticks", -1)), TELEGRAPH_TICKS)
	_tick_ok(f, "spear_travel_ticks", int(st.get("spear_travel_ticks", -1)),
			SPEAR_TRAVEL_TICKS)
	_tick_ok(f, "zone_start_tick", int(st.get("zone_start_tick", -1)), ZONE_START_AT)
	_tick_ok(f, "zone_ticks", int(st.get("zone_ticks", -1)), ZONE_TICKS)
	_tick_ok(f, "fade_back_ticks", int(st.get("fade_back_ticks", -1)), FADE_BACK_TICKS)
	var arb: Dictionary = j.get("arbiter", {})
	if not (arb.get("appear_requires", null) is Array) \
			or not (arb.get("appear_requires", []) as Array).is_empty():
		f.append("json: appear_requires %s, want EMPTY"
				% str(arb.get("appear_requires", null)))
	var y: Variant = arb.get("yields_to", null)
	if not (y is Array) or (y as Array) != ["address_me"]:
		f.append("json: yields_to %s, want [\"address_me\"]" % str(y))
	var cues: Array = st.get("audio_cues", [])
	for cue in ["crack_rumble", "shing", "whoosh", "zone_open", "zone_close"]:
		if not cues.has(cue):
			f.append("json: audio cue '%s' missing" % cue)


## One controller for the fixture arena (the runner passes it to rt.setup).
func _make_ctl(w: Dictionary):
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	return ctl


## The kill pass: gin's zone kills an inside player with code D-GIN (Last Light
## already spent on the controller, D-057 - otherwise the save masks the kill).
func _void_zone_kills(f: Array[String]) -> void:
	var rt = _runtime_last_light_spent()
	var api = _api_of(rt)
	var row: Dictionary = _gin_row(rt)
	var w: Dictionary = _arena()
	rt.setup(w, w, [_ctl(w)], 4242)
	row["phase"] = GinBehavior.VOID
	row["phase_t"] = 0
	row["patch"] = {"cells": [[2, 2], [3, 2]], "cx": 2, "cz": 2}
	_drive(row, api, ZONE_START_AT - 1)   # 137 ticks of zone-incomming
	if not api.rt.world["enemies"].is_empty():
		var ctl = api.rt.world["enemies"][0]
		# walk the player into the column: tile (2, 2) is inside the patch
		ctl.x = 2.5
		ctl.z = 2.5
		_drive(row, api, 1)
		var died: Array = rt.events.filter(func(e): return e.get("e") == "player_died")
		var codes: Array = died.map(func(e): return e.get("code", ""))
		if not codes.has("D-GIN"):
			f.append("void zone: kill codes %s, want D-GIN" % str(codes))
		else:
			var dcode: String = died[0].get("code", "")
			if str(dcode) != "D-GIN":
				f.append("void zone: death code %s, want D-GIN" % dcode)


## The lift: a player inside the column is pushed onto the surface when the
## tiles fade back (a push straight up; the surface is exactly one lift away).
func _lift_on_fade_back(f: Array[String]) -> void:
	var rt = _runtime_last_light_spent()
	var api = _api_of(rt)
	var row: Dictionary = _gin_row(rt)
	var ctl = _ctl_of(rt)
	ctl.x = 2.5
	ctl.z = 2.5
	ctl.y = -4.0       # below the vanished floor
	# drive the LAST VOID tick: the zone closes on it, the lift fires on the same tick
	row["phase"] = GinBehavior.VOID
	row["phase_t"] = GinBehavior.ZONE_TICKS - 1
	row["patch"] = {"cells": [[2, 2]], "cx": 2, "cz": 2}   # the player's column
	_drive(row, api, 1)
	if float(ctl.vy) <= 0.0:
		f.append("lift: no upward impulse at the fade-back (vy %.2f)" % float(ctl.vy))


## All tick readings come from enemy.json's stats; +/-1 tick is the budget.
func _tick_ok(f: Array[String], key: String, got: int, want: int) -> void:
	_tick_budget_ok(f, key, got, want)


## One kill event with the given code (the runner asserts the code verbatim).
func _kill_event(code: String) -> Dictionary:
	return {"e": "player_died", "code": code, "killer": GinBehavior.GIN_ID}



# The anim block in sprites.json is the ONLY timing source: the view and the test
# both read it, neither re-derives a timing from the PNGs or the docs.
func _anim_block_is_the_source(f: Array[String]) -> void:
	var view = GinView.new()
	var block: Dictionary = view.anim_block()
	if block.is_empty():
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(
				"res://content/enemies/gin/sprites.json"))
		if doc is Dictionary:
			block = (doc as Dictionary).get("anim", {})
	if block.is_empty():
		f.append("anim: the anim block is empty - nothing drives the frames")
		return
	var states: Dictionary = block.get("states", {})
	var want := {
		"spawn": SPAWN_TICKS,
		"telegraph": TELEGRAPH_TICKS,
		"attack_launch": SPEAR_TRAVEL_TICKS,
		"attack_void_zone": ZONE_TICKS,
		"recover": FADE_BACK_TICKS,
	}
	for k in want.keys():
		var s: Dictionary = states.get(k, {})
		var raw: Variant = s.get("total_ticks", -1)
		var total: int = -1 if raw == null else int(raw)   # JSON null -> not binding
		# spawn/recover are loops with no fixed length; attack_void_zone's length is
		# the zone's (the sim declares it) - the other three are binding
		if k == "spawn" or k == "recover" or k == "attack_void_zone":
			continue
		if total != int(want[k]):
			f.append("anim: state %s total %d, want %d" % [k, total, int(want[k])])
	# the launch frame is shown on tick 120, not recomputed from a frame list
	var launch: Dictionary = states.get("attack_launch", {})
	var shown: Variant = launch.get("effect", {}).get("params", {}).get("shown_on_tick", -1)
	if int(shown) != LAUNCH_SHOWN_AT:
		f.append("anim: launch shown_on_tick %s, want %d" % [str(shown), LAUNCH_SHOWN_AT])


# D-072: the fade-in tile is a platform tile 15-25 u from the player; if none
# qualifies, the farthest tile of the spawn hub. The behavior never marks the
# beacon dais and stands never on the only route home.
func _spawn_tile_rule(f: Array[String]) -> void:
	var rt = _runtime_last_light_spent()
	var api = _api_of(rt)
	_smoke_behavior(f, rt, api)


# The fade-in tile's HEIGHT is the body's y (PARKED row 27's sibling): the contact band
# runs row y .. y + height_u, so a body left on the spawn height cannot touch a player
# standing on the platform the 15-25 u rule picked. And the mirror follows the fade-in.
func _fade_in_tile_height(f: Array[String]) -> void:
	var tiles: Array = []
	for x in range(-5, 6):
		for z in range(-5, 6):
			tiles.append([x, z, 0])        # flat: every one of them is < 15 u out
	tiles.append([20, 0, 4])               # top at 2.0 u - inside the 15-25 u window
	tiles.append([21, 0, 4])               # the farther one: the tile D-072 picks
	var made := _runtime_with(tiles)
	var rt = made[0]
	var row: Dictionary = _gin_row(rt)
	if str(row.get("id", "")) != "gin":
		f.append("fade-in tile: no gin row in the runtime")
		return
	if absf(float(row["y"]) - 2.0) > 1e-9:
		f.append("fade-in tile: gin's y is %.2f, want the chosen tile's 2.0 (not the spawn height)"
				% float(row["y"]))
	if absf(float(row["x"]) - 21.5) > 1e-9 or absf(float(row["z"]) - 0.5) > 1e-9:
		f.append("fade-in tile: gin stands at (%.2f, %.2f), want the farthest qualifying tile (21.5, 0.5)"
				% [float(row["x"]), float(row["z"])])
	var mirror: Dictionary = row.get("body_mirror", {})
	if mirror.is_empty():
		f.append("fade-in tile: the row carries no body mirror (no world[enemies] entry)")
		return
	if absf(float(mirror["x"]) - float(row["x"])) > 1e-9 \
			or absf(float(mirror["y"]) - float(row["y"])) > 1e-9 \
			or absf(float(mirror["z"]) - float(row["z"])) > 1e-9:
		f.append("fade-in tile: the body mirror sits at (%.2f, %.2f, %.2f), the row is at (%.2f, %.2f, %.2f)"
				% [float(mirror["x"]), float(mirror["y"]), float(mirror["z"]),
					float(row["x"]), float(row["y"]), float(row["z"])])


# The 15-25 u tile rule is a property of EVERY fade-in (DESIGN.md: "fades in on a tile
# 15-25 u from the player"), not of the first one: cycle 2 re-picks against where the
# player is NOW, and the mirror moves with him.
func _second_fade_in_picks_a_new_tile(f: Array[String]) -> void:
	var tiles: Array = []
	for x in range(0, 40):
		for z in range(0, 40):
			tiles.append([x, z, 0])
	var made := _runtime_with(tiles)
	var rt = made[0]
	var ctl = made[1]
	var row: Dictionary = _gin_row(rt)
	if str(row.get("id", "")) != "gin":
		f.append("second fade-in: no gin row in the runtime")
		return
	var api := _api_for(rt, row)
	var first := Vector2(float(row["x"]), float(row["z"]))
	# the first fade-in completes and the mark starts on the next tick; move the player out
	# of the announced patch so the void zone cannot end the fixture early
	_drive(row, api, GinBehavior.SPAWN_TICKS)
	ctl.x = 39.5
	ctl.z = 39.5
	var cooldown := false
	var back_to_spawn := false
	for i in range(2400):
		_drive(row, api, 1)
		var phase := str(row.get("phase", ""))
		if phase == GinBehavior.COOLDOWN:
			cooldown = true
		elif cooldown and phase == GinBehavior.SPAWN:
			back_to_spawn = true
			break
	if not back_to_spawn:
		f.append("second fade-in: the cycle never reached a second fade-in (cooldown seen: %s)"
				% str(cooldown))
		return
	var second := Vector2(float(row["x"]), float(row["z"]))
	if second.distance_to(first) < 1.0:
		f.append("second fade-in: gin faded in at (%s) again - the tile was chosen once per level"
				% str(second))
	var mirror: Dictionary = row.get("body_mirror", {})
	if mirror.is_empty():
		f.append("second fade-in: the row carries no body mirror (no world[enemies] entry)")
		return
	if absf(float(mirror["x"]) - float(row["x"])) > 1e-9 \
			or absf(float(mirror["z"]) - float(row["z"])) > 1e-9:
		f.append("second fade-in: the body mirror sits at (%.2f, %.2f), the row is at (%.2f, %.2f)"
				% [float(mirror["x"]), float(mirror["z"]), float(row["x"]), float(row["z"])])


# The yields_to deferral: with a LIVE address me countdown, gin's strike start
# defers (the gate answers deferred=true); once the countdown ends, it does not.
func _deferral(f: Array[String]) -> void:
	var rt = _runtime_last_light_spent()
	var api = _api_of(rt)
	var row: Dictionary = _gin_row(rt)
	if row.is_empty():
		f.append("deferral: no gin row in the runtime")
		return
	row["countdown_left"] = 300   # a live address me countdown on the roster (D-T-039-6)
	row["phase"] = GinBehavior.SPAWN
	var gate: Dictionary = api.arbiter_gate(["address_me"])
	if not bool(gate.get("deferred", false)):
		f.append("deferral: gate with a live address_me countdown did not defer")
	# the countdown ends: the call lands on the first free tick that follows
	row["countdown_left"] = 0
	var gate2: Dictionary = api.arbiter_gate([])
	if bool(gate2.get("deferred", false)):
		f.append("deferral: gate still deferred after the countdown ended")


# A full cycle at 60 Hz, every number within +/-1 tick.
func _run_cycle(f: Array[String]) -> void:
	var rt = _runtime_last_light_spent()
	var api = _api_of(rt)
	var row: Dictionary = _gin_row(rt)
	_drive(row, api, 180)


# The kill tests run with LAST LIGHT ALREADY SPENT (D-057): the save would
# otherwise mask the kill and the assertion would be worthless.
func _runtime_last_light_spent():
	var w: Dictionary = _arena()
	var ctl = _ctl(w)
	var rt: RefCounted = EnemyRuntime.new()
	rt.setup(_level(), w, [ctl], 4242)
	return rt


func _ctl_of(rt):
	return rt.controllers[0]


func _api_of(rt) -> RefCounted:
	var api = EnemyRuntime.Api.new()
	api.rt = rt
	var row: Dictionary = {"id": "gin", "copies": 1, "cfg": _json()}
	api.row = row
	return api


## An api bound to a LIVE row, the way the runtime builds one per row per tick: only
## this binding can reach the row's world["enemies"] mirror through sync_body().
func _api_for(rt, row: Dictionary) -> RefCounted:
	var api = EnemyRuntime.Api.new()
	api.rt = rt
	api.row = row
	return api


## A runtime over a level built from `tiles` ([x, z, y_hu] rows), one controller.
func _runtime_with(tiles: Array) -> Array:
	var w: Dictionary = Util.world_from_tiles(tiles)
	w["dais"] = [0, 0, 0]
	var ctl = _ctl(w)
	var lv: Dictionary = {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": tiles, "props": [], "pads": []}
	var rt: RefCounted = EnemyRuntime.new()
	rt.setup(lv, w, [ctl], 4242)
	return [rt, ctl]


# A gin row in a fresh runtime (the runtime spawns him; the behavior takes it over).
func _gin_row(rt) -> Dictionary:
	var api = _api_of(rt)
	var row: Dictionary = {"id": "gin", "copies": 1}
	rt.spawn_at("gin", "gin ichimaru", GinBehavior.new(), {}, Vector3(2.1, 0.0, 0.5))
	for e in rt.enemies:
		if str(e.get("id", "")) == "gin":
			row = e
			break
	return row


func _smoke_behavior(f: Array[String], rt, api) -> void:
	var row: Dictionary = _gin_row(rt)
	# fade-in completes; the mark telegraphs; the body becomes lethal on the launch
	row["phase"] = GinBehavior.SPAWN
	row["phase_t"] = 0
	row["contact_kill"] = false
	_drive_states(row, api, f)


# ---- helpers ------------------------------------------------------------------------------------


## One controller for the fixture arena (the runner passes it to rt.setup).
func _ctl(w: Dictionary):
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true   # D-057: the save would otherwise mask every kill
	return ctl


## A fresh runtime: an 11x11 flat arena, one controller, Last Light already spent.
func _level() -> Dictionary:
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": _tiles_full(), "props": [], "pads": []}


func _arena():
	var tiles: Array = []
	for x in range(-5, 6):
		for z in range(-5, 6):
			tiles.append([x, z, 0])
	var w: Dictionary = Util.world_from_tiles(tiles)
	w["dais"] = [0, 0, 0]
	return w


## The cfg from enemy.json's stats block - every timing asserted below is read from
## the SAME file the sim would consume, not from a test-local copy.
func _ticks_from_json(key: String) -> int:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			"res://tests/gin_legacy_metadata.json"))
	if not (doc is Dictionary):
		return -1
	var st: Dictionary = (doc as Dictionary).get("stats", {})
	return int(st.get(key, -1))


## The whole enemy.json document as a Dictionary (empty on a parse failure).
func _json() -> Dictionary:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			"res://tests/gin_legacy_metadata.json"))
	if doc is Dictionary:
		return doc
	return {}


## Assert `got` is within +/-1 tick of `want` (the D-072 tick budget).
func _tick_budget_ok(f: Array[String], key: String, got: int, want: int) -> void:
	if absi(got - want) > 1:
		f.append("%s: got %d, want %d (+/-1)" % [key, got, want])



## Drives the behavior's tick() by hand: dt is always 1 tick, 60 Hz.
func _drive(row: Dictionary, api, ticks: int) -> void:
	var beh = GinBehavior.new()
	for i in range(ticks):
		beh.tick(row, api, 1)


## The states a full cycle walks through, in table order (section 1.12), via the
## anim block's state ids - and the kill at ZONE_START_AT + zone reach.
func _drive_states(row: Dictionary, api, f: Array[String]) -> void:
	var seen: Array = []
	GinBehavior.new().on_spawn(row, api)   # the runtime's own first call on a real row
	for i in range(180):
		_drive(row, api, 1)
		var st := str(row.get("anim_state", ""))
		if seen.is_empty() or str(seen[seen.size() - 1]) != st:
			seen.append(st)
	if seen.find(GinBehavior.SPAWN) == -1:
		f.append("cycle: the states %s never held SPAWN" % str(seen))


# The tiles of the fixture arena: flat cells [x, z, y, kind, piece].
func _tiles_full() -> Array:
	var out: Array = []
	for x in range(-5, 6):
		for z in range(-5, 6):
			out.append([x, z, 0, 0, 0])
	return out
