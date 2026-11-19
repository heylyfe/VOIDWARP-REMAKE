extends RefCounted
#
# address me tests (ticket T-039). DESIGN.md section 5.10 is the spec; every timing and
# number of the paragraph is asserted within +/-1 tick. Kill tests run with the
# player's LAST LIGHT already spent (D-057) - otherwise the save masks the kill
# and the assertion is worthless.
#
# The four appear_requires are asserted one requirement per case (each where it must
# NOT appear), plus one where it may.
#
# Body contact: D-065 FINAL - address me never kills on contact (PARKED.md row 6
# records the ticket/FINAL clash and DECISIONS D-T-039-1 pins the built reading).
# The explode at countdown expiry is the only kill (D-ADDR, attribution per
# sim/death.gd; the cfg death_code arrives verbatim through api.kill).

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Util := preload("res://tests/sim_testutil.gd")
const AddressMeEnemy := preload("res://content/enemies/address_me/enemy.gd")
const DeathScript := preload("res://sim/death.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const BillboardScript := preload("res://view/billboard.gd")
const AddressMeViewScript := preload("res://view/address_me_view.gd")
const AntechamberScript := preload("res://view/lobby/antechamber.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const AddressMeAudioScript := preload("res://view/audio/address_me_audio.gd")
const OffersScript := preload("res://sim/offers.gd")

const DT := 1.0 / 60.0

# Body circle radius for containment proofs: collision.gd models the player
# body as an axis-aligned box of half-width hw = 0.4 (height 1.8); the
# horizontal body circle takes that half-width as its radius.
const BODY_R := 0.4


func run() -> Array[String]:
	var f: Array[String] = []
	_data_sheet(f)
	_appearance_gate(f)
	_appear_in_front_and_spawn_state(f)
	_countdown_kill_and_death_code(f)
	_stillness_window(f)
	_stillness_reset_on_movement(f)
	_contact_never_kills(f)
	_return_cadence_and_level_floor(f)
	_self_deferral_while_counting_down(f)
	_anim_block_wiring(f)
	_audio_cues(f)
	_lobby_exhibit(f)
	return f


# ---- fixtures ---------------------------------------------------------------

func _tiles_full() -> Array:
	var tiles: Array = []
	for x in range(-10, 11):
		for z in range(-10, 11):
			tiles.append([x, z, 0, 0, 0])
	return tiles


func _level() -> Dictionary:
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": _tiles_full(), "props": [], "pads": []}


func _arena() -> Dictionary:
	var flat: Array = []
	for t in _tiles_full():
		flat.append([t[0], t[1], t[2]])
	var w := Util.world_from_tiles(flat)
	w["dais"] = [0, 0, 0]
	return w


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


# Build the runtime cfg exactly as the engine does: the enemy.json stats block, plus
# the top-level spawn knobs and the arbiter block merged in (the row's cfg carries
# the gate - that is the whole point of the T-072 data contract).
func _runtime_cfg(votes: int = 1) -> Dictionary:
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


# [rt, row, ctl]; the controller sits on the dais tile and never moves.
func _spawn(votes: int = 1, display_name: String = "address me") -> Array:
	var w := _arena()
	var ctl = _spent_ctl(w)
	var rt = EnemyRuntime.new()
	rt.setup(_level(), w, [ctl], 4242)
	var row: Dictionary = rt.spawn_at("address_me", display_name, AddressMeEnemy.new(), _runtime_cfg(votes), Vector3(9.5, 0.0, 0.5))
	return [rt, row, ctl]


func _death_events(rt) -> Array:
	var out: Array = []
	for e in rt.events:
		if e.get("e", "") == "death":
			out.append(e)
	return out


# Run until the appearance has happened (row leaves "recover"), returning rt ticks waited.
func _wait_for_appearance(rt, row, max_ticks: int = 4000) -> int:
	for i in range(max_ticks):
		rt.step(DT)
		if str(row["anim_state"]) != "recover":
			return int(rt.tick)
	return -1


# Run until anim_state becomes `want` or max_ticks elapse.
func _wait_for_state(rt, row, want: String, max_ticks: int = 4000) -> int:
	for i in range(max_ticks):
		rt.step(DT)
		if str(row["anim_state"]) == want:
			return int(rt.tick)
	return -1


# Drive past the level-floor appearance, then past the 12-tick spawn state;
# returns rt tick at telegraph entry (i.e. countdown tick 0 completed).
func _enter_countdown(rt, row) -> int:
	var t_appear := _wait_for_appearance(rt, row, 4000)
	if t_appear < 0:
		return -1
	return _wait_for_state(rt, row, "telegraph", 60)


# True iff the body circle (centre (px, pz), radius body_r) lies wholly inside
# a circle footprint shape: dist(centre, shape centre) + body_r <= shape r.
# The arbiter's point_in_shape only proves the FEET point is inside, which lets
# the body straddle the footprint edge - this is the containment it cannot see.
func _body_circle_inside(shape: Dictionary, px: float, pz: float, body_r: float) -> bool:
	var dx := px - float(shape.get("cx", px))
	var dz := pz - float(shape.get("cz", pz))
	var d := sqrt(dx * dx + dz * dz)
	return d + body_r <= float(shape.get("r", 0.0)) + 1e-9


# ---- the data sheet (enemy.json) ---------------------------------------------

func _data_sheet(f: Array[String]) -> void:
	var path := "res://content/enemies/address_me/enemy.json"
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (doc is Dictionary):
		f.append("sheet: enemy.json does not parse")
		return
	var d: Dictionary = doc
	if str(d.get("name", "")) != "address me":
		f.append("sheet: name %s, want 'address me'" % str(d.get("name", "")))
	if int(d.get("min_level", 0)) != 9:
		f.append("sheet: min_level %d, want 9" % int(d.get("min_level", 0)))
	if int(d.get("max_votes", 0)) != 3:
		f.append("sheet: max_votes %d, want 3" % int(d.get("max_votes", 0)))
	if bool(d.get("contact_kill", true)):
		f.append("sheet: contact_kill must be false (D-065 FINAL)")
	var stats: Dictionary = d.get("stats", {})
	if absf(float(stats.get("world_height", 0.0)) - 2.5) > 1e-9:
		f.append("sheet: world_height %s, want 2.5" % str(stats.get("world_height")))
	if str(stats.get("death_code", "")) != "D-ADDR":
		f.append("sheet: death_code %s, want D-ADDR" % str(stats.get("death_code")))
	var arb: Dictionary = d.get("arbiter", {})
	if arb.is_empty():
		f.append("sheet: the arbiter block is missing")
	else:
		var reqs: Array = arb.get("appear_requires", [])
		var flat: Array = []
		for r in reqs:
			flat.append(str(r))
		for want in ["{ \"no_enemy_body_within\": 12.0 }",
				"{ \"no_targeted_telegraph\": true }",
				"{ \"player_grounded\": true }",
				"{ \"not_on_glitched_floor\": true }"]:
			if not flat.has(want):
				f.append("sheet: appear_requires missing %s (has %s)" % [want, str(reqs)])
		if str(arb.get("yields_to", [])) != str(["address_me"]):
			f.append("sheet: yields_to %s, want [\"address_me\"]" % str(arb.get("yields_to")))


# ---- the four appear_requires, one case each where it must NOT appear ----------

# contain_shape: when non-empty, additionally prove the player's body CIRCLE
# (centre + BODY_R) lies wholly inside the footprint, not merely that the feet
# point matches some coordinate - the gate's own shape test is a point test.
func _gate_blocked(f: Array[String], label: String, setup: Callable, contain_shape: Dictionary = {}) -> void:
	var spawned := _spawn()
	var rt = spawned[0]
	var row = spawned[1]
	setup.call(spawned)
	if not contain_shape.is_empty():
		var bctl = spawned[2]
		if not _body_circle_inside(contain_shape, float(bctl.x), float(bctl.z), BODY_R):
			f.append("gate %s: the player's body circle (centre (%.3f, %.3f), r %.2f) is not inside the footprint (%s)" % [label, float(bctl.x), float(bctl.z), BODY_R, str(contain_shape)])
	var appeared := false
	for i in range(700):
		rt.step(DT)
		if str(row["anim_state"]) != "recover":
			appeared = true
			break
	if appeared:
		f.append("gate %s: it appeared, want never (before tick 700)" % label)


func _appearance_gate(f: Array[String]) -> void:
	# control: a clean arena DOES let it appear (first tick all four hold)
	var clean := _spawn()
	var t_appear := _wait_for_appearance(clean[0], clean[1])
	if t_appear < 0:
		f.append("gate: never appeared in a clean arena")
	elif t_appear < 600:
		f.append("gate: appeared at tick %d, before the 10 s level floor (600)" % t_appear)

	# (a) an enemy body within 12 u of the player blocks all appearance
	_gate_blocked(f, "no_enemy_body_within", func(spawned: Array):
		var blocker_cfg := {"world_height": 1.0, "frame_w": 256, "frame_h": 256,
				"body_rect": [0, 0, 256, 256], "contact_kill": false, "cycle_ticks": 0}
		spawned[0].spawn_at("tbd", "TBD", EnemyRuntime.FixtureBehavior.new(), blocker_cfg,
				Vector3(4.5, 0.0, 0.5)))

	# (b) a live telegraph footprint covers the player (outlives the 700-tick window:
	# footprints expire when their telegraph ends - SR-4 liveness, not ticks>0 alone).
	# Containment is proven geometrically: the player's body circle (centre +
	# BODY_R) must lie wholly inside the footprint circle, not merely the feet
	# point (the arbiter's shape test is a point test).
	var b_shape := {"shape": "circle", "cx": 0.5, "cz": 0.5, "r": 2.0}
	_gate_blocked(f, "no_targeted_telegraph", func(spawned: Array):
		spawned[0].telegraphs.append({"kind": "test_patch", "source": "gin", "ticks": 10000,
				"total": 10000, "tick": 0,
				"shape": b_shape}), b_shape)

	# (c) the player is airborne
	_gate_blocked(f, "player_grounded", func(spawned: Array):
		spawned[2].grounded = false)

	# (d) the player stands on glitched floor
	_gate_blocked(f, "not_on_glitched_floor", func(spawned: Array):
		var rt = spawned[0]
		rt.world["glitched"]["0,0,0"] = true)


# ---- appearance position, spawn state, telegraph entry timing -----------------

func _appear_in_front_and_spawn_state(f: Array[String]) -> void:
	var spawned := _spawn()
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	var t_appear := _wait_for_appearance(rt, row)
	if t_appear < 0:
		f.append("appear: never appeared")
		return
	# exactly 6 u in front of the player's default facing (0,0,1): z = 0.5 + 6 = 6.5
	if absf(float(row["x"]) - 0.5) > 0.001:
		f.append("appear: x %.3f, want 0.5 (no lateral drift from the default heading)" % float(row["x"]))
	if absf(float(row["z"]) - 6.5) > 0.001:
		f.append("appear: z %.3f, want 6.5 (6 u in front of the default facing)" % float(row["z"]))
	if absf(float(row["y"]) - float(ctl.y)) > 0.001:
		f.append("appear: y %.3f, want the player's feet height %.3f" % [float(row["y"]), float(ctl.y)])
	if str(row["anim_state"]) != "spawn":
		f.append("appear: state %s, want spawn" % str(row["anim_state"]))
	# the spawn state lasts 12 ticks (+/-1) and then the countdown beings
	var t_tele := _wait_for_state(rt, row, "telegraph", 60)
	if t_tele < 0:
		f.append("appear: never reached the countdown")
		return
	if absi(t_tele - t_appear - 11) > 1:
		f.append("appear: spawn lasted %d ticks, want 12 +/-1" % (t_tele - t_appear))
	if int(row["countdown_left"]) != 300 and int(row["countdown_left"]) != 299:
		f.append("appear: countdown_left %d at telegraph entry, want 300 (or 299 after the first countdown tick)" % int(row["countdown_left"]))


# ---- the 5.0 s expiry kill (D-057; D-ADDR; killer "address me") ---------------

func _countdown_kill_and_death_code(f: Array[String]) -> void:
	var spawned := _spawn()
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	var t_tele := _enter_countdown(rt, row)
	if t_tele < 0:
		f.append("kill: never entered the countdown")
		return
	# the player is never still: vx stays at 9.0 u/s, so 1.5 s never elapse
	ctl.vx = 9.0
	var t_attack := _wait_for_state(rt, row, "attack", 400)
	if t_attack < 0:
		f.append("kill: the countdown never expired into the attack frame")
		return
	if absi(t_attack - t_tele - 300) > 2:
		f.append("kill: countdown lasted %d ticks, want 300 +/-2 (5.0 s)" % (t_attack - t_tele))
	if not ctl.dead:
		f.append("kill: the expiry did not kill the moving player (Last Light was spent)")
	var found := false
	for d in _death_events(rt):
		if str(d["code"]) == "D-ADDR":
			found = true
	if not found:
		f.append("kill: death events %s, want code D-ADDR" % str(_death_events(rt)))
	if str(DeathScript.killer_for("D-ADDR")) != "address me":
		f.append("kill: death.gd maps D-ADDR to %s, want address me" % str(DeathScript.killer_for("D-ADDR")))


# ---- stillness: hold still 1.5 s of the rumble and it leaves ------------------

func _stillness_window(f: Array[String]) -> void:
	var spawned := _spawn()
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	var t_tele := _enter_countdown(rt, row)
	if t_tele < 0:
		f.append("still: never entered the countdown")
		return
	# the controller never steps in these rt ticks: vx=vy=vz=0, grounded, so the
	# stillness counter must reach 90 and hand the episode to `leaves`
	var t_leaves := _wait_for_state(rt, row, "leaves", 400)
	if t_leaves < 0:
		f.append("still: the player held still for the whole rumble yet it never left")
		return
	if absi(t_leaves - t_tele - 89) > 2:
		f.append("still: leaves at %d ticks into the countdown, want 90 +/-2" % (t_leaves - t_tele))
	if ctl.dead:
		f.append("still: the player was killed despite achieving stillness")


# ---- stillness resets the moment the player moves -----------------------------

func _stillness_reset_on_movement(f: Array[String]) -> void:
	var spawned := _spawn()
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	var t_tele := _enter_countdown(rt, row)
	if t_tele < 0:
		f.append("reset: never entered the countdown")
		return
	# 60 still ticks, then break the stillness, then hold again: the window must restart
	for i in range(60):
		rt.step(DT)
	ctl.vx = 9.0
	rt.step(DT)
	ctl.vx = 0.0
	var t_still := -1
	for i in range(400):
		rt.step(DT)
		if int(row["still_t"]) >= 10:
			t_still = int(rt.tick)
			break
	if t_still < 0:
		f.append("reset: the stillness counter never resumed after movement")
		return
	# right after the break the counter must read 1 (not 61): it resets on ANY move tick
	if int(row["still_t"]) != 10:
		f.append("reset: still_t after 10 resumed ticks is %d, want exactly 10" % int(row["still_t"]))


# ---- body contact never kills (D-065 FINAL; PARKED row 6) ---------------------

func _contact_never_kills(f: Array[String]) -> void:
	var spawned := _spawn()
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	var t_appear := _wait_for_appearance(rt, row)
	if t_appear < 0:
		f.append("contact: never appeared")
		return
	# park the body right on top of the player: no kill, ever
	row["x"] = float(ctl.x)
	row["y"] = float(ctl.y)
	row["z"] = float(ctl.z)
	rt.sync_body_mirror(row)
	for i in range(120):
		rt.step(DT)
	if ctl.dead:
		f.append("contact: overlapping its body killed the player (D-065 says it never does)")


# ---- the return cadence: 30-45 s; votes discount; never in the first 10 s ----

func _return_cadence_and_level_floor(f: Array[String]) -> void:
	# 1 vote: the return timer draws from [1800, 2700]
	var s1 := _spawn(1)
	var r := _drive_to_leaves(s1[0], s1[1])
	if r < 0:
		f.append("return: the 1-vote fixture never resolved the countdown")
	else:
		if r < 1800 or r > 2700:
			f.append("return: 1-vote interval %d ticks, want within [1800, 2700]" % r)
	# 3 votes: [1800-600, 2700-600] = [1200, 2100]
	var s3 := _spawn(3)
	r = _drive_to_leaves(s3[0], s3[1])
	if r < 0:
		f.append("return: the 3-vote fixture never resolved the countdown")
	else:
		if r < 1200 or r > 2100:
			f.append("return: 3-vote interval %d ticks, want within [1200, 2100]" % r)
	# 2 votes: [1500, 2400]
	var s2 := _spawn(2)
	r = _drive_to_leaves(s2[0], s2[1])
	if r < 0:
		f.append("return: the 2-vote fixture never resolved the countdown")
	else:
		if r < 1500 or r > 2400:
			f.append("return: 2-vote interval %d ticks, want within [1500, 2400]" % r)
	# the level-tick floor: nothing appears before tick 600 even in a clean arena
	var floor_spawn := _spawn()
	var t := _wait_for_appearance(floor_spawn[0], floor_spawn[1])
	if t < 600:
		f.append("return: an appearance at tick %d slipped before the 10 s floor" % t)


# Runs one episode with the player standing still until `leaves` finishes and the
# return timer is set. Returns the drawn return_timer (ticks), or -1 on timeout.
func _drive_to_leaves(rt, row) -> int:
	var t_appear := _wait_for_appearance(rt, row, 4000)
	if t_appear < 0:
		return -1
	var t_tele := _wait_for_state(rt, row, "telegraph", 60)
	if t_tele < 0:
		return -1
	var t := _wait_for_state(rt, row, "leaves", 400)
	if t < 0:
		return -1
	_wait_for_state(rt, row, "recover", 400)
	return int(row["return_timer"])


# ---- it defers its own appearance while its countdown is live -----------------

func _self_deferral_while_counting_down(f: Array[String]) -> void:
	var spawned := _spawn()
	var rt = spawned[0]
	var row = spawned[1]
	var t_tele := _enter_countdown(rt, row)
	if t_tele < 0:
		f.append("defer: never entered the countdown")
		return
	var api = EnemyRuntime.Api.new()
	api.rt = rt
	api.row = row
	var live: Dictionary = api.arbiter_gate(["address_me"])
	if not bool(live.get("deferred", false)):
		f.append("defer: a live countdown did not defer this row's gate")
	# after the countdown resolves (stillness achieved), the defer lifts
	row["countdown_left"] = 0
	var lifted: Dictionary = api.arbiter_gate([])
	if bool(lifted.get("deferred", false)):
		f.append("defer: the deferral did not lift once the countdown ended")


# ---- the view's wiring to the anim block --------------------------------------

func _anim_block_wiring(f: Array[String]) -> void:
	var v = AddressMeViewScript.new()
	v.setup("res://content/enemies/address_me/sprites.json", "res://content/enemies/address_me")
	for state_id in ["spawn", "telegraph", "leaves", "attack", "recover"]:
		if not (v.anim_state_ids() as Array).has(state_id):
			f.append("view: anim block is missing state '%s'" % state_id)
	if v.billboard == null:
		f.append("view: billboard was not built")
		v.free()
		return
	v.position = Vector3(5.0, 0.0, 0.5)
	# in the countdown: red ring drains, green stillness arc fills, tints ramp
	var row := {"anim_state": "telegraph", "anim_state_t": 160, "countdown_left": 140,
			"still_t": 45, "x": 5.0, "y": 0.0, "z": 0.5}
	v.sync(row, DT)
	if v._countdown_arc == null or not v._countdown_arc.visible:
		f.append("view: countdown arc hidden during the rumble")
	elif v._countdown_mat != null:
		var fill := float(v._countdown_mat.get_shader_parameter("fill"))
		if absf(fill - 140.0 / 300.0) > 0.001:
			f.append("view: countdown fill %.4f, want %.4f (countdown_left / 300)" % [fill, 140.0 / 300.0])
	if v._stillness_arc == null or not v._stillness_arc.visible:
		f.append("view: stillness arc hidden during the rumble")
	elif v._stillness_mat != null:
		var fill2 := float(v._stillness_mat.get_shader_parameter("fill"))
		if absf(fill2 - 45.0 / 90.0) > 0.001:
			f.append("view: stillness fill %.4f, want %.4f (still_t / 90)" % [fill2, 45.0 / 90.0])
	if absf(v.billboard.modulate.r - 1.0) > 0.001 or absf(v.billboard.modulate.g - 0.76) > 0.02:
		f.append("view: tint at tick 160 is %s, want amber" % str(v.billboard.modulate))
	v.sync({"anim_state": "telegraph", "anim_state_t": 250, "countdown_left": 50,
			"still_t": 0, "x": 5.0, "y": 0.0, "z": 0.5}, DT)
	if absf(v.billboard.modulate.g - 0.38) > 0.02:
		f.append("view: tint at tick 250 is %s, want red" % str(v.billboard.modulate))
	if v._stillness_mat != null:
		var fill3 := float(v._stillness_mat.get_shader_parameter("fill"))
		if absf(fill3) > 0.001:
			f.append("view: stillness arc did not empty on move (fill %s)" % str(fill3))
	# leaves shrinks the sprite to 0
	v.sync({"anim_state": "leaves", "anim_state_t": 9, "countdown_left": 0, "still_t": 90,
			"x": 5.0, "y": 0.0, "z": 0.5}, DT)
	if v._sprite_wrap == null or absf(float(v._sprite_wrap.scale.x) - 0.5) > 0.001:
		f.append("view: leaves shrink %s, want 0.5 at 9/18 ticks" % str(v._sprite_wrap.scale if v._sprite_wrap != null else "missing"))
	# attack holds the explode frame and shows the flash for 6 ticks
	v.sync({"anim_state": "attack", "anim_state_t": 2, "countdown_left": 0, "still_t": 0,
			"x": 5.0, "y": 0.0, "z": 0.5}, DT)
	if v.billboard.frame_i != 1:
		f.append("view: attack frame %d, want 1 (the explode frame)" % v.billboard.frame_i)
	if v._flash == null or not v._flash.visible:
		f.append("view: the full-screen white flash is hidden during attack ticks 0-5")
	v.sync({"anim_state": "attack", "anim_state_t": 8, "countdown_left": 0, "still_t": 0,
			"x": 5.0, "y": 0.0, "z": 0.5}, DT)
	if v._flash != null and v._flash.visible:
		f.append("view: the flash is still visible at tick 8, want gone after 6 ticks")
	# recover hides the body
	v.sync({"anim_state": "recover", "anim_state_t": 1, "countdown_left": 0, "still_t": 0,
			"x": 5.0, "y": 0.0, "z": 0.5}, DT)
	if v.billboard.visible:
		f.append("view: the body is visible during recover")
	v.free()


# ---- the placeholder audio hooks ----------------------------------------------

func _audio_cues(f: Array[String]) -> void:
	if AddressMeAudioScript.cue_names() != ["explode_boom", "rumble_build", "spawn_trumpet"]:
		f.append("audio: cue names %s, want [explode_boom, rumble_build, spawn_trumpet]"
			% str(AddressMeAudioScript.cue_names()))
	if AddressMeAudioScript.file_name_for("spawn_trumpet") != "address_me_trumpet":
		f.append("audio: spawn_trumpet file name %s" % AddressMeAudioScript.file_name_for("spawn_trumpet"))
	if AddressMeAudioScript.file_name_for("rumble_build") != "address_me_rumble":
		f.append("audio: rumble_build file name %s" % AddressMeAudioScript.file_name_for("rumble_build"))
	if AddressMeAudioScript.file_name_for("explode_boom") != "address_me_boom":
		f.append("audio: explode_boom file name %s" % AddressMeAudioScript.file_name_for("explode_boom"))
	for cue in ["spawn_trumpet", "rumble_build", "explode_boom"]:
		var s: AudioStreamWAV = AddressMeAudioScript.stream_for(cue)
		if s == null or s.data.size() == 0:
			f.append("audio: the %s placeholder stream is empty" % cue)


# ---- the lobby exhibit shows it ------------------------------------------------

func _lobby_exhibit(f: Array[String]) -> void:
	var api: RefCounted = ContentApiScript.load()
	if not bool(api.call("is_ok")):
		f.append("lobby: content boot failed: %s" % " / ".join(api.call("boot_errors")))
		return
	if not (api.call("enemy_ids") as Array).has("address_me"):
		f.append("lobby: 'address_me' is not registered as an enemy")
		return
	# the E-bay draw path: offered at level 9 (its min_level), absent at level 8
	var gate: Dictionary = OffersScript.enemy_gate(api)
	var l9: Array = OffersScript.enemy_candidates(api, 9, "general", {}, gate)
	var l8: Array = OffersScript.enemy_candidates(api, 8, "general", {}, gate)
	if not l9.has("address_me"):
		f.append("lobby: 'address_me' is not a candidate enemy at level 9")
	if l8.has("address_me"):
		f.append("lobby: 'address_me' offered below its min_level (8)")
	var doc: Dictionary = api.call("enemy", "address_me")
	if str(doc.get("name", "")) != "address me":
		f.append("lobby: name %s, want address me" % str(doc.get("name")))
	if int(doc.get("min_level", 0)) != 9:
		f.append("lobby: min_level %d, want 9" % int(doc.get("min_level", 0)))
	if int(doc.get("max_votes", 0)) != 3:
		f.append("lobby: max_votes %d, want 3" % int(doc.get("max_votes", 0)))
	# the antechamber's exact path: parse sprites.json, build the billboard,
	# scale the body to ENEMY_BODY_H (1.6 u)
	var hall = AntechamberScript.new()
	var lb = IntermissionScript.create(api, 0, 0, 99)
	hall.lobby = lb
	var anchor = Node3D.new()
	var shown: String = hall._exhibit_enemy(anchor, {"id": "address_me", "name": "address me", "votes": 0})
	if shown != "address me":
		f.append("lobby: exhibit shows %s, want 'address me'" % shown)
	if anchor.get_child_count() != 1:
		f.append("lobby: %d children on the anchor, want 1 (the billboard)" % anchor.get_child_count())
	else:
		var child = anchor.get_child(0)
		if not (child is BillboardScript):
			f.append("lobby: the exhibit child is %s, want the billboarded PNG sprite" % child.get_class())
	var sdoc: Dictionary = hall._enemy_doc("address_me")
	if str(sdoc.get("behavior", "")).find("5.0 s") == -1:
		f.append("lobby: the lobby panel would show behavior %s" % str(sdoc.get("behavior")))
	if str(sdoc.get("counter_play", "")).find("stop") == -1:
		f.append("lobby: the lobby panel would show counter_play %s" % str(sdoc.get("counter_play")))
	if str(sdoc.get("tell", "")).find("trumpet") == -1:
		f.append("lobby: the lobby panel would show tell %s" % str(sdoc.get("tell")))
	anchor.free()
	hall.free()
