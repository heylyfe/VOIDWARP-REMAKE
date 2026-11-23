extends RefCounted
#
# Enemy gameplay negative controls (W12-C; audit game/out/coverage_map.md). Each of the
# 12 rt.step gameplay tests proves its claim on the happy path only. This file proves
# that each claim CAN FAIL. For every enemy, the most important gameplay claim is checked
# twice against the SAME assertion:
#
#   enabled  - the mechanism live: the claim must HOLD
#   disabled - the mechanism removed (never placed / the column emptied):
#              the SAME assertion must FAIL
#
# A claim that holds in both worlds is reported as a failure: it would mean the original
# test was not testing what it claimed. Fixtures are inherited from the source tests
# (test_enemy_*.gd); only the mechanism toggle differs between the two twins.
#
# The 12: address_me, claude, coil, gift_larper, gin, isagi, kiwi_cat, nuke, seal,
# thicc_ben, toucher, you.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const MinesScript := preload("res://sim/mines.gd")
const Util := preload("res://tests/sim_testutil.gd")
const AddressMeEnemy := preload("res://content/enemies/address_me/enemy.gd")
const ClaudeEnemy := preload("res://content/enemies/claude/enemy.gd")
const ClawdsScript := preload("res://sim/clawds.gd")
const BeaconScript := preload("res://sim/beacon.gd")
const CoilEnemy := preload("res://content/enemies/coil/enemy.gd")
const GinBehavior := preload("res://content/enemies/gin/enemy.gd")
const Isagi := preload("res://content/enemies/isagi/enemy.gd")
const KiwiCatScript := preload("res://content/enemies/kiwi_cat/enemy.gd")
const NukeBehavior := preload("res://content/enemies/nuke/enemy.gd")
const SealScript := preload("res://content/enemies/seal/enemy.gd")
const BenBehavior := preload("res://content/enemies/thicc_ben/enemy.gd")
const ToucherEnemy := preload("res://content/enemies/toucher/enemy.gd")
const YouEnemy := preload("res://content/enemies/you/enemy.gd")

const DT := 1.0 / 60.0
const LAND_TICK := 411          # coil: spawn 30 + idle 180 + cue 36 + flight 165


func run() -> Array[String]:
	var f: Array[String] = []
	_check(f, "address_me: the countdown's expiry kills (D-ADDR)", _claim_address_me(true), _claim_address_me(false))
	_check(f, "claude: 180 s with no clawd collected kills (D-CLAUDE)", _claim_claude(true), _claim_claude(false))
	_check(f, "coil: the landing on the player kills (D-COIL)", _claim_coil(true), _claim_coil(false))
	_check(f, "gift_larper: contact through the ladder kills (D-MINE)", _claim_gift_larper(true), _claim_gift_larper(false))
	_check(f, "gin: the void zone kills a player standing in it (D-GIN)", _claim_gin(true), _claim_gin(false))
	_check(f, "isagi: body contact kills (D-ISAGI)", _claim_isagi(true), _claim_isagi(false))
	_check(f, "kiwi_cat: body contact kills (D-KIWI)", _claim_kiwi_cat(true), _claim_kiwi_cat(false))
	_check(f, "nuke: the blast kills the parked player (D-NUKE)", _claim_nuke(true), _claim_nuke(false))
	_check(f, "seal: the dash kills (D-SEAL)", _claim_seal(true), _claim_seal(false))
	_check(f, "thicc_ben: the touch ejects the player (vy = 18.0)", _claim_thicc_ben(true), _claim_thicc_ben(false))
	_check(f, "toucher: the touch infects its tiles (glitched set populated)", _claim_toucher(true), _claim_toucher(false))
	_check(f, "you: the ring kills the grounded player (D-YOU)", _claim_you(true), _claim_you(false))
	return f


func _check(f: Array[String], label: String, held: bool, twin: bool) -> void:
	if not held:
		f.append("%s: the claim did not hold with the mechanism live" % label)
	if twin:
		f.append("%s: the same assertion held with the mechanism disabled - it cannot fail" % label)


# ---- shared fixtures ----------------------------------------------------------

# Last Light spent for real, then the arrival state cleared: exactly "alive,
# unshielded, Last Light spent" (D-057).
func _spent_ctl(w: Dictionary):
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.try_kill("D-TEST", "test", w, [])
	ctl.invuln = 0.0
	ctl.dead = false
	ctl.place(w)
	return ctl


func _has_death(events: Array, code: String) -> bool:
	for e in events:
		if str(e.get("e", "")) == "death" and str(e.get("code", "")) == code:
			return true
	return false


func _flat_3(half_x: int, half_z: int) -> Array:
	var tiles: Array = []
	for x in range(-half_x, half_x + 1):
		for z in range(-half_z, half_z + 1):
			tiles.append([x, z, 0])
	return tiles


func _flat_5(half_x: int, half_z: int) -> Array:
	var tiles: Array = []
	for x in range(-half_x, half_x + 1):
		for z in range(-half_z, half_z + 1):
			tiles.append([x, z, 0, 0, 0])
	return tiles


func _arena(half_x: int, half_z: int) -> Dictionary:
	var w := Util.world_from_tiles(_flat_3(half_x, half_z))
	w["dais"] = [0, 0, 0]
	return w


# the hand-built flat world dict the kennel-style tests use
func _hollow_world() -> Dictionary:
	return {"cols": {}, "prop_cols": {}, "pads": {}, "dais": [0, 0, 0], "glitched": {},
			"slippery": {}, "removed": {}, "kill_y": -40.0, "enemies": [], "projectiles": [],
			"hazards": []}


# the two-row walkable lane (z = 0 and z = 5) bridged at x = 0
func _lane_level(anchors: Array) -> Dictionary:
	var tiles: Array = []
	for x in range(0, 100):
		tiles.append([x, 0, 0, 0, 0])
		tiles.append([x, 5, 0, 0, 1])
	tiles.append([0, 1, 0, 0, 2])
	tiles.append([0, 2, 0, 0, 2])
	tiles.append([0, 3, 0, 0, 2])
	tiles.append([0, 4, 0, 0, 2])
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": anchors,
			"tiles": tiles, "props": [], "pads": []}


# ---- address_me ---------------------------------------------------------------

func _address_me_cfg(votes: int) -> Dictionary:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/address_me/enemy.json"))
	var cfg: Dictionary = (doc as Dictionary).get("stats", {}).duplicate(true)
	var d: Dictionary = doc as Dictionary
	if d.has("contact_kill"):
		cfg["contact_kill"] = d["contact_kill"]
	if d.has("preferred_kind"):
		cfg["preferred_kind"] = d["preferred_kind"]
	if d.has("arbiter"):
		cfg["arbiter"] = d["arbiter"]
	cfg["votes"] = votes
	return cfg


func _claim_address_me(enabled: bool) -> bool:
	var w := _arena(10, 10)
	var ctl = _spent_ctl(w)
	var rt = EnemyRuntime.new()
	rt.setup({"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": _flat_5(10, 10), "props": [], "pads": []}, w, [ctl], 4242)
	if enabled:
		rt.spawn_at("address_me", "address me", AddressMeEnemy.new(), _address_me_cfg(1),
				Vector3(9.5, 0.0, 0.5))
		# keep the player moving: stillness is the spec's success state (it leaves,
		# no kill) - only a moving player sees the countdown expire into the blast
		ctl.vx = 9.0
	var deaths: Array = []
	for i in range(4600):
		for e in rt.step(DT):
			if str(e.get("e", "")) == "death":
				deaths.append(e)
	return _has_death(deaths, "D-ADDR")


# ---- claude -------------------------------------------------------------------

func _claude_cfg() -> Dictionary:
	var txt := FileAccess.get_file_as_string("res://content/enemies/claude/enemy.json")
	var doc: Variant = JSON.parse_string(txt)
	return (doc as Dictionary)["stats"].duplicate(true)


## The revamped claim (D-T4-5): Claude does nothing himself, so the claim is the ANGER TIMER -
## 180 s (10800 ticks) with no clawd collected kills the player with D-CLAUDE. The mechanism
## toggle is the swarm itself: with no clawds attached there is no timer and no death.
func _claim_claude(enabled: bool) -> bool:
	var w := Util.world_from_tiles(_flat_3(10, 10))
	w["dais"] = [0, 0, 0]
	var ctl = _spent_ctl(w)
	var padded: Array = []
	for t in _flat_3(10, 10):
		padded.append([t[0], t[1], t[2], 0, 0])
	var L := {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": padded, "props": [], "pads": [],
			"seed": 4242, "level": 1, "gen_version": 1, "attempt": 0}
	var lv := {"clawds": null, "beacon": null}
	if enabled:
		ClawdsScript.attach(L, ClaudeEnemy.clawd_cfg())
		lv["clawds"] = ClawdsScript.create(L)
		lv["beacon"] = BeaconScript.create(L)
	var deaths: Array = []
	for i in range(10800):
		var ev: Array = []
		ClawdsScript.tick(lv, [ctl], w, i + 1, ev)
		for e in ev:
			if str((e as Dictionary).get("e", (e as Dictionary).get("type", ""))) == "death":
				deaths.append(e)
	return _has_death(deaths, "D-CLAUDE")


# ---- coil ---------------------------------------------------------------------

func _coil_cfg() -> Dictionary:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/coil/enemy.json"))
	var stats: Dictionary = (doc as Dictionary).get("stats", {})
	var sheet: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/coil/sprites.json"))
	var anims: Array = (sheet as Dictionary).get("animations", [])
	var br: Array = anims[0]["body_rect"][0] if anims.size() > 0 else [0, 0, 256, 256]
	return {
		"world_height": float(stats.get("world_height", 1.0)),
		"frame_w": 512, "frame_h": 512, "body_rect": br,
		"contact_kill": true, "preferred_kind": "lane",
		"cycle_s": float(stats.get("cycle_ticks", 405)) / 60.0,
		"cycle_ticks": int(stats.get("cycle_ticks", 405)),
		"idle_s": float(stats.get("idle_s", 3.0)),
	}


# claim: parked on the locked landing tile, the landing kills the player (D-COIL)
func _claim_coil(enabled: bool) -> bool:
	var w := _arena(5, 5)
	var ctl = _spent_ctl(w)
	var rt = EnemyRuntime.new()
	rt.setup({}, w, [ctl], 1234)
	if enabled:
		rt.spawn_at("coil", "coil", CoilEnemy.behavior(), _coil_cfg(),
				Vector3(3.5, 0.0, 0.5), 0, 1)
	for i in range(LAND_TICK + 26):
		rt.step(DT)
		ctl.step(DT, Util.mk_in(), w)
	return bool(ctl.dead) and str(ctl.dead_code) == "D-COIL"


# ---- gift_larper --------------------------------------------------------------

func _mine_level(with_mine: bool) -> Dictionary:
	var slots: Array = []
	if with_mine:
		slots = [{"id": 0, "x": 0, "z": 0, "y": 0, "piece": 0, "tier": 0, "occ": 1}]
	return {"gifts": slots}


# claim: a contact through the ladder kills with Last Light spent (D-MINE).
# the disabled twin removes the only mine from the world entirely.
func _claim_gift_larper(enabled: bool) -> bool:
	var m: RefCounted = MinesScript.create(_mine_level(enabled), 7, 11)
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.x = 0.5
	ctl.y = 0.0
	ctl.z = 0.5
	ctl.last_light_spent = true
	var players: Array = [{"x": float(ctl.x), "y": float(ctl.y), "z": float(ctl.z)}]
	var events: Array = []
	MinesScript.tick({"mines": m, "players": players, "beacon": null}, [ctl],
			{"dais": [0, 0, 0], "enemies": []}, [0], 7, events)
	return bool(ctl.dead) and str(ctl.dead_code) == "D-MINE"


# ---- gin ----------------------------------------------------------------------

func _gin_runtime():
	var w := _arena(5, 5)
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true
	var rt = EnemyRuntime.new()
	rt.setup({"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": _flat_5(5, 5), "props": [], "pads": []}, w, [ctl], 4242)
	return [rt, ctl]


func _gin_api_for(rt, row: Dictionary) -> RefCounted:
	var api = EnemyRuntime.Api.new()
	api.rt = rt
	api.row = row
	return api


func _gin_drive(row: Dictionary, api, ticks: int) -> void:
	var beh = GinBehavior.new()
	for i in range(ticks):
		beh.tick(row, api, 1)


# claim: a controller standing inside the void column dies with D-GIN
func _claim_gin(enabled: bool) -> bool:
	var pair = _gin_runtime()
	var rt = pair[0]
	if enabled:
		var row: Dictionary = {}
		rt.spawn_at("gin", "gin ichimaru", GinBehavior.new(), {}, Vector3(2.1, 0.0, 0.5))
		for e in rt.enemies:
			if str(e.get("id", "")) == "gin":
				row = e
				break
		if row.is_empty():
			return false
		var api := _gin_api_for(rt, row)
		row["phase"] = GinBehavior.VOID
		row["phase_t"] = 0
		row["patch"] = {"cells": [[2, 2], [3, 2]], "cx": 2, "cz": 2}
		_gin_drive(row, api, 137)   # ZONE_START_AT - 1 ticks of zone ramp
		var victim = rt.controllers[0]
		victim.x = 2.5
		victim.z = 2.5
		_gin_drive(row, api, 1)
		for e in rt.events:
			if str(e.get("e", "")) == "death" and str(e.get("code", "")) == "D-GIN":
				return true
		return false
	# disabled twin: no gin anywhere; the same collector runs over the same ticks
	for i in range(138):
		for e in rt.step(DT):
			if str(e.get("e", "")) == "death" and str(e.get("code", "")) == "D-GIN":
				return true
	return false


# ---- isagi --------------------------------------------------------------------

func _isagi_stats() -> Dictionary:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/isagi/enemy.json"))
	if doc is Dictionary:
		return (doc as Dictionary).get("stats", {})
	return {}


# claim: body contact kills with Last Light spent (D-ISAGI)
func _claim_isagi(enabled: bool) -> bool:
	var tiles: Array = []
	for x in range(0, 35):
		tiles.append([x, 0, 0, 0, 0])
	for x in range(30, 35):
		tiles.append([x, 4, 4, 0, 0])
	var w: Variant = Util.CollisionScript.make_world(tiles, [], [])
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.x = 5.5
	ctl.y = 0.0
	ctl.z = 0.5
	ctl.vy = 0.0
	ctl.last_light_spent = true
	var lv := {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [[0, 30, 4, 4]],
			"tiles": tiles, "props": [], "pads": []}
	var rt = EnemyRuntime.new()
	rt.setup(lv, w, [ctl], 7)
	if enabled:
		var cfg := {"id": "isagi", "name": "Isagi", "preferred_kind": "perch",
				"stats": _isagi_stats()}
		rt.spawn_at("isagi", "Isagi", Isagi.Behavior.new(), cfg, Vector3(5.9, 0.0, 0.5))
	var deaths: Array = []
	for i in range(4):
		for e in rt.step(DT):
			if str(e.get("e", "")) == "death":
				deaths.append(e)
	return _has_death(deaths, "D-ISAGI")


# ---- kiwi_cat -----------------------------------------------------------------

func _kiwi_runtime(lv: Dictionary) -> Array:
	var w := _hollow_world()
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true
	var rt = EnemyRuntime.new()
	rt.setup(lv, w, [ctl], 7)
	return [rt, ctl]


# claim: body contact kills with Last Light spent (D-KIWI)
func _claim_kiwi_cat(enabled: bool) -> bool:
	var pair := _kiwi_runtime(_lane_level([]))
	var rt = pair[0]
	if enabled:
		rt.spawn_at("kiwi_cat", "kiwi cat", KiwiCatScript.KiwiCatBehavior.new(),
				KiwiCatScript.cfg().duplicate(true), Vector3(0.5, 0.0, 0.5))
	var deaths: Array = []
	for e in rt.step(DT):
		if str(e.get("e", "")) == "death":
			deaths.append(e)
	return _has_death(deaths, "D-KIWI")


# ---- nuke ---------------------------------------------------------------------

func _nuke_cfg() -> Dictionary:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/nuke/enemy.json"))
	if not (doc is Dictionary) or not (doc as Dictionary).has("stats"):
		return {}
	var st: Dictionary = (doc as Dictionary)["stats"]
	var cfg: Dictionary = {}
	for k in st.keys():
		cfg[k] = st[k]
	return cfg


func _nuke_world(tiles: Array) -> Array:
	var tl: Array = []
	for t in tiles:
		tl.append([int(t[0]), int(t[1]), int(t[2]), 0, 0])
	var w: Variant = Util.CollisionScript.make_world(tl, [], [])
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.x = 0.5
	ctl.y = 0.0
	ctl.z = 0.5
	ctl.grounded = true
	ctl.last_light_spent = true
	var lv := {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": tl, "props": [], "pads": []}
	var rt = EnemyRuntime.new()
	rt.setup(lv, w, [ctl], 7)
	return [rt, ctl]


# claim: the blast kills the parked player ~240 ticks in (D-NUKE)
func _claim_nuke(enabled: bool) -> bool:
	var tiles: Array = []
	for x in range(0, 100):
		tiles.append([x, 0, 0])
	var pair := _nuke_world(tiles)
	var rt = pair[0]
	if enabled:
		rt.spawn_at("nuke", "nuke", NukeBehavior.new(), _nuke_cfg(), Vector3(60.5, 0.0, 2.5))
	var deaths: Array = []
	for i in range(700):
		for e in rt.step(DT):
			if str(e.get("e", "")) == "death":
				deaths.append(e)
	return _has_death(deaths, "D-NUKE")


# ---- seal ---------------------------------------------------------------------

func _seal_runtime(lv: Dictionary) -> Array:
	var w := _hollow_world()
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true
	ctl.x = 8.5
	ctl.z = 0.5
	var rt = EnemyRuntime.new()
	rt.setup(lv, w, [ctl], 7)
	return [rt, ctl]


# claim: the dash through the player kills (D-SEAL)
func _claim_seal(enabled: bool) -> bool:
	var pair := _seal_runtime(_lane_level([]))
	var rt = pair[0]
	if enabled:
		rt.spawn_at("seal", "seal", SealScript.SealBehavior.new(),
				SealScript.cfg().duplicate(true), Vector3(0.5, 0.0, 0.5))
	var deaths: Array = []
	for i in range(240):
		for e in rt.step(DT):
			if str(e.get("e", "")) == "death":
				deaths.append(e)
		if not deaths.is_empty():
			break
	return _has_death(deaths, "D-SEAL")


# ---- thicc_ben ----------------------------------------------------------------

func _ben_cfg_from_disk() -> Dictionary:
	var out := {}
	var f := FileAccess.open("res://content/enemies/thicc_ben/enemy.json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			out = parsed
	var sheet_file := FileAccess.open("res://content/enemies/thicc_ben/sprites.json", FileAccess.READ)
	if sheet_file != null:
		var sheet: Variant = JSON.parse_string(sheet_file.get_as_text())
		sheet_file.close()
		if sheet is Dictionary:
			out["world_height"] = float((sheet as Dictionary).get("world_height", 4.0))
			var anims: Variant = (sheet as Dictionary).get("animations", [])
			if anims is Array and not (anims as Array).is_empty():
				var a: Dictionary = (anims as Array)[0]
				out["frame_w"] = 256
				out["frame_h"] = 256
				out["body_rect"] = (a.get("body_rect", [[0, 0, 256, 256]]) as Array)[0]
	out["preferred_kind"] = "none"
	out["contact_kill"] = false
	return out


# claim: the touch ejects the player upward at exactly 18.0 u/s.
# ben can never kill, so the eject is the gameplay claim.
func _claim_thicc_ben(enabled: bool) -> bool:
	var w := _arena(5, 5)
	var ctl = _spent_ctl(w)
	ctl.x = 0.5
	ctl.y = 0.0
	ctl.z = 0.5
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0
	var rt = EnemyRuntime.new()
	rt.setup({}, w, [ctl], 4242, {})
	if enabled:
		rt.spawn_at("thicc_ben", "thicc ben", BenBehavior.new_behavior(),
				_ben_cfg_from_disk(), Vector3(0.5, 0.0, 0.5))
	for i in range(30):
		rt.step(DT)
	return absf(float(ctl.vy) - 18.0) <= 1e-6


# ---- toucher ------------------------------------------------------------------

func _toucher_cfg(base_speed: float, level_number: int) -> Dictionary:
	return {"world_height": 1.4, "frame_w": 256, "frame_h": 256,
			"body_rect": [16, 16, 224, 224], "contact_kill": true,
			"hit_diameter": 0.8, "preferred_kind": "lane",
			"base_speed": base_speed, "pursuit_ceiling": 0.75, "burst_ceiling": 0.75,
			"level_number": level_number, "death_code": "D-TOUCH"}


func _toucher_level() -> Dictionary:
	var tiles: Array = []
	for x in range(-40, 41):
		for z in range(-13, 14):
			tiles.append([x, z, 0, 0, 0])
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": tiles, "props": [], "pads": []}


func _toucher_claim(w: Dictionary) -> bool:
	var g: Dictionary = w["glitched"]
	return g.has("0,0,0") and g.size() == 29


# claim: the finger infects its 3.0 u patch - 29 tiles on the grid, the player's
# tile among them (DESIGN 5.8, decided 3.0 u inclusive)
func _claim_toucher(enabled: bool) -> bool:
	var tiles: Array = []
	for x in range(-40, 41):
		for z in range(-13, 14):
			tiles.append([x, z, 0])
	var w := Util.world_from_tiles(tiles)
	w["dais"] = [0, 0, 0]
	var ctl = _spent_ctl(w)
	var rt = EnemyRuntime.new()
	rt.setup(_toucher_level(), w, [ctl], 4242)
	var row: Dictionary = {}
	if enabled:
		row = rt.spawn_at("toucher", "toucher", ToucherEnemy.behavior(),
				_toucher_cfg(0.0, 1), Vector3(3.5, 0.0, 0.5), 0, 1)
	for i in range(900):
		rt.step(DT)
		if not row.is_empty() and str(row["anim_state"]) == "attack_infect":
			break
	return _toucher_claim(w)


# ---- you ----------------------------------------------------------------------

func _you_cfg(base_speed: float = 3.4) -> Dictionary:
	return {"world_height": 1.8, "frame_w": 256, "frame_h": 256,
			"body_rect": [16, 16, 224, 224], "contact_kill": true,
			"cycle_s": 0.625, "preferred_kind": "open",
			"base_speed": base_speed, "pursuit_ceiling": 0.55, "burst_ceiling": 1.0}


# claim: the ring kills the grounded player (D-YOU)
func _claim_you(enabled: bool) -> bool:
	var w := _arena(10, 10)
	var ctl = _spent_ctl(w)
	var rt = EnemyRuntime.new()
	rt.setup({"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": _flat_5(10, 10), "props": [], "pads": []}, w, [ctl], 4242)
	if enabled:
		rt.spawn_at("you", "YOU?!", YouEnemy.new(), _you_cfg(3.4), Vector3(11.0, 0.0, 0.5))
	var deaths: Array = []
	for i in range(800):
		for e in rt.step(DT):
			if str(e.get("e", "")) == "death":
				deaths.append(e)
	return _has_death(deaths, "D-YOU")





