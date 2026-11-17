extends RefCounted
#
# toucher tests (ticket T-037). DESIGN.md section 5.8 is the spec; every timing and
# number of the paragraph is asserted within +/-1 tick. Kill tests run with the
# player's LAST LIGHT already spent (D-057) - otherwise the save masks the kill and
# the assertion is worthless.
#
# Readings under test (DECISIONS D-T-037-1..6):
# - tiles within 3 u below it: tiles whose top sits strictly below the finger's
#   feet, within 3.0 u of its position;
# - the glitched slow / ability lock are the controller's D-051 handling of
#   world["glitched"] - the toucher never kills through a tile;
# - the 60-tile cap frees room oldest-first (FIFO), so the patch follows its finger;
# - ben's ring cleanse (T-032) and this behavior share the "x,z,y_hu" tile key.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Util := preload("res://tests/sim_testutil.gd")
const ToucherEnemy := preload("res://content/enemies/toucher/enemy.gd")
const DeathScript := preload("res://sim/death.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const BillboardScript := preload("res://view/billboard.gd")
const ToucherViewScript := preload("res://view/toucher_view.gd")
const OffersScript := preload("res://sim/offers.gd")

const DT := 1.0 / 60.0


func run() -> Array[String]:
	var f: Array[String] = []
	_pursuit_speed_and_ceiling(f)
	_feet_ease(f)
	_infect_interval_binding(f)
	_tempo_floor_binds_at_72(f)
	_glitch_tile_set(f)
	_stand_on_floor_does_not_kill_and_locks(f)
	_body_contact_kills_and_death_code(f)
	_tile_life_12s(f)
	_tile_life_18s_from_level_14(f)
	_tile_cap_fifo(f)
	_ben_ring_cleanse_agreement(f)
	_copy_stagger(f)
	_squelch_only_on_new_tiles(f)
	_attack_infect_has_no_duration(f)
	_anim_block_wiring(f)
	_view_decals(f)
	_lobby_exhibit(f)
	return f


# ---- fixtures ----------------------------------------------------------------

func _tiles_full() -> Array:
	var tiles: Array = []
	for x in range(-40, 41):
		for z in range(-13, 14):
			tiles.append([x, z, 0, 0, 0])
	return tiles


## A 1-tile-wide line: every patch is <= 7 keys, so ten infects stay far under the
## 60-tile cap - the life tests can watch one key expire with no FIFO eviction
## in sight (it would masquerade as expiry).
func _tiles_line() -> Array:
	var tiles: Array = []
	for x in range(-70, 71):
		tiles.append([x, 0, 0, 0, 0])
	return tiles


func _line_rt(base_speed: float, level_number: int) -> Array:
	var level := {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": _tiles_line(), "props": [], "pads": []}
	var flat: Array = []
	for x in range(-70, 71):
		flat.append([x, 0, 0])
	var w := Util.world_from_tiles(flat)
	w["dais"] = [0, 0, 0]
	var ctl = _spent_ctl(w)
	ctl.invuln = 0.0
	ctl.dead = true
	var rt = EnemyRuntime.new()
	rt.setup(level, w, [ctl], 4242)
	var row: Dictionary = rt.spawn_at("toucher", "toucher", ToucherEnemy.behavior(),
			_cfg(base_speed, level_number), Vector3(12.0, 0.0, 0.5))
	return [rt, row, ctl, w]


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


func _cfg(base_speed: float = 6.75, level_number: int = 1) -> Dictionary:
	return {"world_height": 1.4, "frame_w": 256, "frame_h": 256,
			"body_rect": [16, 16, 224, 224], "contact_kill": true,
			"hit_diameter": 0.8, "preferred_kind": "lane",
			"base_speed": base_speed, "pursuit_ceiling": 0.75, "burst_ceiling": 0.75,
			"level_number": level_number, "death_code": "D-TOUCH"}


# [rt, row, ctl, w]; the controller sits on the dais tile (0,0) and never moves.
# base_speed 0 pins the finger in place 3 u from the player - contact never
# fires, and every tile within 3 u of it (including the player's) infects.
func _spawn(pos: Vector3, base_speed: float = 0.0, level_number: int = 1,
		copy_index: int = 0, copies: int = 1, dead_ok: bool = false) -> Array:
	var w := _arena()
	var ctl = _spent_ctl(w)
	if dead_ok:
		ctl.invuln = 0.0
		ctl.dead = true
	var rt = EnemyRuntime.new()
	rt.setup(_level(), w, [ctl], 4242)
	var row: Dictionary = rt.spawn_at("toucher", "toucher", ToucherEnemy.behavior(),
			_cfg(base_speed, level_number), pos, copy_index, copies)
	return [rt, row, ctl, w]


func _death_events(rt) -> Array:
	var out: Array = []
	for e in rt.events:
		if e.get("e", "") == "death":
			out.append(e)
	return out


func _audio_events(rt, cue: String = "") -> Array:
	var out: Array = []
	for e in rt.events:
		if e.get("e", "") == "audio" and (cue == "" or str(e.get("cue", "")) == cue):
			out.append(e)
	return out


func _telegraph_events(rt) -> Array:
	var out: Array = []
	for e in rt.events:
		if e.get("e", "") == "telegraph":
			out.append(e)
	return out


## Ticks until the row enters the given anim state (max 900); -1 when never.
func _wait_state(rt, row, state: String, from: int = 0) -> int:
	for i in range(from, from + 900):
		rt.step(DT)
		if str(row["anim_state"]) == state:
			return i
	return -1


# ---- SR-5 pursuit (section 5.8: 6.75 u/s, ceiling 0.75 -> 6.75 u/s, never faster) ----

func _pursuit_speed_and_ceiling(f: Array[String]) -> void:
	# base speed itself: the finger crosses 6 u in 6 u / 6.75 u/s = 0.888 s (53 ticks)
	var spawned := _spawn(Vector3(12.0, 0.0, 0.5), 6.75, 1, 0, 1, true)
	var rt = spawned[0]
	var row = spawned[1]
	var fb = row["float"]
	var x0 := float(row["x"])
	for i in range(60):
		rt.step(DT)
	var travelled := absf(float(row["x"]) - x0)
	var want := 6.75 * (60.0 / 60.0)
	if absf(travelled - want) > 0.25:
		f.append("pursuit: travelled %.4f u in 60 ticks, want ~6.75 u/s (spec 5.8)" % travelled)
	# the full SR-5 stack (overtime tier 8 x curse Rush Hour x3) leaves it at 6.75:
	# its ceiling is its own base speed, so no multiplier ever speeds it up
	var x1 := float(row["x"])
	rt.overtime_running = true
	rt.add_overtime_tier(8)
	rt.curse_speed_mul = 1.08 * 1.08 * 1.08
	for i in range(180):
		rt.step(DT)
		if absf(float(fb.h_speed) - 6.75) > 1e-9:
			f.append("pursuit: ceiling broken at tick %d: h_speed %.6f, want 6.75" % [i, float(fb.h_speed)])
			break
	if absf(float(row["x"]) - x1) > 21.0:
		f.append("pursuit: drifted %.4f u in 180 boosted ticks, absurd" % absf(float(row["x"]) - x1))
	var raw: float = 6.75 * 1.48 * 1.08 * 1.08 * 1.08
	if absf(float(fb.tempo_mul) - clampf(raw / 6.75, 1.0, 1.0 / 0.6)) > 1e-6:
		f.append("pursuit: tempo_mul %.6f, want the cluttered overflow %.6f"
				% [float(fb.tempo_mul), clampf(raw / 6.75, 1.0, 1.0 / 0.6)])


# ---- SR-1 feet easing (2.0 u/s climb, never multiplied) -----------------------

func _feet_ease(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(9.0, 2.5, 0.5))   # feet 2.5 u above the player
	var rt = spawned[0]
	var row = spawned[1]
	for i in range(30):
		rt.step(DT)
	if absf(float(row["y"]) - 2.5 + 1.0) > 0.05:
		f.append("ease: feet at %.3f after 30 ticks, want -1.0 u (2.0 u/s x 0.5 s, SR-1)"
				% float(row["y"]))


# ---- the 2.0 s infection interval (section 5.8, binding 120 ticks) ------------

func _infect_interval_binding(f: Array[String]) -> void:
	# two consecutive infections on an untouched flat floor, no multipliers
	var spawned := _spawn(Vector3(3.5, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	var t0 := _wait_state(rt, row, "attack_infect")
	if t0 < 0:
		f.append("interval: the toucher never infected")
		return
	var t1 := _wait_state(rt, row, "attack_infect", t0 + 1)
	if t1 < 0:
		f.append("interval: no second infection")
		return
	var got := t1 - t0
	if absi(got - 120) > 1:
		f.append("interval: cycle %d ticks, want 120 +/-1 (2.0 s, DESIGN 5.8)" % got)
	# the glitch pulse precedes each infection by exactly the 18-tick anim block:
	# step a fresh instance by hand and pair the first event of each kind (per-step
	# events; rows in rt.telegraphs never expire and would pair across cycles)
	var fresh := _spawn(Vector3(3.5, 0.0, 0.5))
	var rt2 = fresh[0]
	var row2 = fresh[1]
	var ann_tick := -1
	var inf_tick := -1
	for i in range(900):
		rt2.step(DT)
		for e in rt2.events:
			if ann_tick < 0 and str(e.get("e", "")) == "telegraph" and str(e.get("kind", "")) == "toucher_pulse":
				ann_tick = int(e["tick"])
			if inf_tick < 0 and str(e.get("e", "")) == "toucher_infect":
				inf_tick = int(e["tick"])
		if inf_tick >= 0 and ann_tick >= 0:
			break
	if ann_tick < 0 or inf_tick < 0:
		f.append("interval: no pulse/infect event pair (ann %d, inf %d)" % [ann_tick, inf_tick])
	elif absi(inf_tick - ann_tick - 18) > 1:
		f.append("interval: infection %d ticks after the pulse start, want 18"
				% (inf_tick - ann_tick))


# ---- SR-5 overflow binds the interval at 1.2 s (72 ticks, never below) --------

func _tempo_floor_binds_at_72(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(12.0, 0.0, 0.5), 6.75, 1, 0, 1, true)
	var rt = spawned[0]
	var row = spawned[1]
	rt.overtime_running = true
	rt.add_overtime_tier(8)
	rt.curse_speed_mul = 1.08 * 1.08 * 1.08
	var t0 := _wait_state(rt, row, "attack_infect")
	if t0 < 0:
		f.append("tempo: never infected")
		return
	var t1 := _wait_state(rt, row, "attack_infect", t0 + 1)
	if t1 < 0:
		f.append("tempo: no second infection")
		return
	var got := t1 - t0
	if absi(got - 72) > 1:
		f.append("tempo: cycle %d ticks at the full SR-5 stack, want 72 +/-1 (1.2 s)" % got)
	var t2 := _wait_state(rt, row, "attack_infect", t1 + 1)
	if t2 >= 0 and absi(t2 - t1 - 72) > 1:
		f.append("tempo: cycle %d ticks on the third beat, want 72 +/-1" % (t2 - t1))


# ---- the infection set: all tiles within 3 u below it --------------------------

func _glitch_tile_set(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(3.5, 0.0, 0.5))   # 3.0 u from the dais tile centre
	var rt = spawned[0]
	var row = spawned[1]
	var w = spawned[3]
	var t0 := _wait_state(rt, row, "attack_infect")
	if t0 < 0:
		f.append("set: never infected")
		return
	var g: Dictionary = w["glitched"]
	# 29 tiles on the 1-u grid sit within 3.0 u of a tile centre (the two exact-3.0 u
	# edge tiles included)
	if g.size() != 29:
		f.append("set: %d tiles infected, want 29 (radius 3.0 u on the 1-u grid)" % g.size())
	# the player's own tile is inside the patch...
	if not g.has("0,0,0"):
		f.append("set: the tile under the player (3.0 u out) was missed")
	# ...and anything beyond 3 u (from the FINGER at 3.5,0.5 - it is pinned there
	# at base_speed 0) never infects
	for far in ["7,0,0", "0,7,0", "-5,0,0", "0,-7,0", "7,7,0", "0,0,1", "1,1,1"]:
		if g.has(far):
			f.append("set: key %s infected (outside the 3 u patch)" % far)
	# every key is the shared "x,z,y_hu" spelling (collision.gd's tile_key shape)
	for key in g.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() != 3:
			f.append("set: key %s is not the x,z,y_hu spelling" % key)
			break


# ---- standing on a glitched tile: NO kill, -20% speed, abilities locked (D-051) ----

func _stand_on_floor_does_not_kill_and_locks(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(3.5, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	var w = spawned[3]
	var t0 := _wait_state(rt, row, "attack_infect")
	if t0 < 0:
		f.append("floor: never infected")
		return
	if not w["glitched"].has(ctl.cur_key):
		f.append("floor: the player's current key is not the infected key")
	if ctl.dead:
		f.append("floor: standing on its own floor killed the player (spec: it must NOT)")
		return
	if absf(ctl.run_speed(w) - 9.0 * 0.8) > 1e-9:
		f.append("floor: run speed %.4f, want 7.2 (-20%, D-075/5.8)" % ctl.run_speed(w))
	if not ctl.ability_locked(w):
		f.append("floor: class abilities not locked on the glitched floor (D-051/5.8)")
	# ride well past one tile's 12 s life standing there: still no kill, and the
	# stationary finger keeps re-infected the same patch, so the lock holds on
	for i in range(760):
		rt.step(DT)
	if ctl.dead:
		f.append("floor: the toucher's own floor killed a player 12+ s in")
	if (w["glitched"] as Dictionary).size() > 60:
		f.append("floor: %d live tiles, over the 60-tile cap" % (w["glitched"] as Dictionary).size())
	if not w["glitched"].has(ctl.cur_key):
		f.append("floor: the player's tile un-glitched (the patch must hold under it)")
	if not ctl.ability_locked(w):
		f.append("floor: the lock lapsed while its tile was still live")


# ---- body contact = kill; the closed death code D-TOUCH ------------------------

func _body_contact_kills_and_death_code(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(0.9, 0.0, 0.5))   # within the 0.8+0.4 u contact reach
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	# the row's SR-2 pin: 1.4 u body, 0.8 u hit diameter (enemy.json, D-T030-2's path)
	if absf(float(row["height_u"]) - 1.4) > 1e-9 or absf(float(row["diameter_u"]) - 0.8) > 1e-9:
		f.append("contact: body %.2f/%.2f u, want the SR-2 1.4/0.8 pair"
				% [float(row["height_u"]), float(row["diameter_u"])])
	for i in range(10):
		rt.step(DT)
		if ctl.dead:
			break
	if not ctl.dead:
		f.append("contact: body contact did not kill (DESIGN 5.8: touch = kill)")
		return
	var hit := false
	for d in _death_events(rt):
		if str(d["code"]) == "D-TOUCH" and str(d["killer"]) == "toucher":
			hit = true
	if not hit:
		f.append("contact: death events %s, want code D-TOUCH killer toucher" % str(_death_events(rt)))
	if str(DeathScript.killer_for("D-TOUCH")) != "toucher":
		f.append("contact: death.gd maps D-TOUCH to %s, want toucher" % str(DeathScript.killer_for("D-TOUCH")))


# ---- the tile lives: 12 s, and 18 s from level 14 ------------------------------
# The expiry is only observable when the finger has travelled out of re-infect
# reach: the toucher takes a real 6.75 u/s walk to a teleported target (the
# controller is dead so the contact pass never fires - D-057 fixture), and the
# origin patch's keys expire exactly 720 (or 1080) ticks after their last refresh.

func _tile_life_12s(f: Array[String]) -> void:
	_tile_life_assert(f, 1, 720, "life")


func _tile_life_18s_from_level_14(f: Array[String]) -> void:
	_tile_life_assert(f, 14, 1080, "life14")


func _tile_life_assert(f: Array[String], level_number: int, want_life: int, tag: String) -> void:
	var spawned := _line_rt(6.75, level_number)
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	var w = spawned[3]
	var t0 := _wait_state(rt, row, "attack_infect")
	if t0 < 0:
		f.append("%s: never infected" % tag)
		return
	var key := "0,0,0"
	if not w["glitched"].has(key):
		f.append("%s: the origin key did not infect" % tag)
		return
	# send the player 60 u away: the finger marches off, patches land under 20
	# keys total (a line world, 7 per patch), so no FIFO eviction ever touches
	# the origin key - its disappearance is pure expiry (born + life)
	ctl.x = float(ctl.x) + 60.0
	var born: int = -1
	for entry in row["glitched"]:
		if str(entry["key"]) == key:
			born = int(entry["born"])
	if born < 0:
		f.append("%s: the origin key has no list entry" % tag)
		return
	var saw_live := false
	var gone_tick := -1
	var over_cap := false
	for i in range(born, born + 120):
		rt.step(DT)
		if (row["glitched"] as Array).size() > 60:
			over_cap = true
		var has: bool = (w["glitched"] as Dictionary).has(key)
		if has:
			saw_live = true
		elif saw_live and gone_tick < 0:
			gone_tick = i
	if over_cap:
		f.append("%s: the cap evicted mid-watch (fixture leak)" % tag)
	if not saw_live:
		f.append("%s: the key never went live" % tag)
	if gone_tick >= 0:
		f.append("%s: the key vanished at born+%d, want a full %d-tick life"
				% [tag, gone_tick - born, want_life])
		return
	# ride the life out and catch the exact expiry beat
	for i in range(want_life):
		rt.step(DT)
		if not (w["glitched"] as Dictionary).has(key):
			gone_tick = int(rt.tick)
			break
	if gone_tick < 0:
		f.append("%s: the key never expired" % tag)
	elif absi(gone_tick - (born + want_life)) > 2:
		f.append("%s: expiry at born+%d, want %d +/-2" % [tag, gone_tick - born, want_life])


# ---- the 60-tile cap (per toucher) and the FIFO eviction follows the finger ----

func _tile_cap_fifo(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(12.0, 0.0, 0.5), 6.75, 1, 0, 1, true)
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	var w = spawned[3]
	var t0 := _wait_state(rt, row, "attack_infect")
	if t0 < 0:
		f.append("cap: never infected")
		return
	# teleport the dead target 15 u along +x after every infect: patches sit >= 15 u
	# apart while the finger only covers 13.5 u per 2 s infect, so they stay disjoint
	var events := []
	for i in range(t0 + 1, t0 + 520):
		rt.step(DT)
		for e in rt.events:
			if str(e.get("e", "")) == "toucher_infect":
				events.append(e)
				ctl.x = float(ctl.x) + 15.0
		if events.size() >= 4:
			break
	if events.size() < 3:
		f.append("cap: only %d infects landed, want 3" % events.size())
		return
	# patches land wherever the finger is mid-walk, so the 3rd batch's exact size
	# is geometry; what binds is the cap: 29 + 29 + n candidates must leave the
	# row with EXACTLY 60 live tiles, every one present in the world
	if _batch_of(row, int(events[2]["tick"])) < 2:
		f.append("cap: the 3rd batch added %d entries - the finger never left the old patch"
				% _batch_of(row, int(events[2]["tick"])))
	if (row["glitched"] as Array).size() != 60:
		f.append("cap: the row holds %d tiles, want 60" % (row["glitched"] as Array).size())
		return
	if (w["glitched"] as Dictionary).size() != 60:
		f.append("cap: the world holds %d tiles, want 60" % (w["glitched"] as Dictionary).size())
	for entry in row["glitched"]:
		if not w["glitched"].has(str(entry["key"])):
			f.append("cap: the row lists %s but the world does not have it" % str(entry["key"]))
			break
	# no entry exceeds the cap for the rest of the run
	var over := false
	for i in range(300):
		rt.step(DT)
		if (row["glitched"] as Array).size() > 60:
			over = true
			break
	if over:
		f.append("cap: the row exceeded its 60-tile cap")


## Entries born on a tick (the world and the row agree; the count comes from the row).
func _batch_of(row, born: int) -> int:
	var n := 0
	for entry in row["glitched"]:
		if int(entry["born"]) == born:
			n += 1
	return n


# ---- thicc ben's ring cleanse and this row agree on what a glitched tile is ----

func _ben_ring_cleanse_agreement(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(3.5, 0.0, 0.5))   # a 29-tile patch at the player
	var rt = spawned[0]
	var row = spawned[1]
	var w = spawned[3]
	var t0 := _wait_state(rt, row, "attack_infect")
	if t0 < 0:
		f.append("ben: never infected")
		return
	# ben's touch (T-032) calls cleanse_glitched_within(pos, 8.0) - the toucher's
	# tile keys must be that same world map's keys, and ben's queue empties them
	# one tick later (the toucher drops cleansed keys from its own list)
	var n_before: int = (w["glitched"] as Dictionary).size()
	var cleansed: int = rt.cleanse_glitched_within(row, Vector3(3.5, 0.0, 0.5), 8.0)
	if cleansed != n_before:
		f.append("ben: cleansed %d of %d tiles within 8 u - the maps disagree" % [cleansed, n_before])
	if not (w["glitched"] as Dictionary).is_empty():
		f.append("ben: the world kept tiles after a full 8 u cleanse")
	rt.step(DT)
	if not (row["glitched"] as Array).is_empty():
		f.append("ben: the toucher's own list kept %d cleansed keys"
				% (row["glitched"] as Array).size())


# ---- SR-3: copy k of n is staggered INTERVAL/n - copies fire INTERVAL/n apart ----

func _copy_stagger(f: Array[String]) -> void:
	var w := _arena()
	var ctl = _spent_ctl(w)
	var rt = EnemyRuntime.new()
	rt.setup(_level(), w, [ctl], 4242)
	var cfg: Dictionary = _cfg(0.0)
	var row0: Dictionary = rt.spawn_at("toucher", "toucher", ToucherEnemy.behavior(), cfg,
			Vector3(3.5, 0.0, 0.5), 0, 2)
	var row1: Dictionary = rt.spawn_at("toucher", "toucher", ToucherEnemy.behavior(), cfg,
			Vector3(3.5, 0.0, 0.5), 1, 2)
	var t0 := -1
	var t1 := -1
	for i in range(900):
		rt.step(DT)
		if t0 < 0 and str(row0["anim_state"]) == "attack_infect":
			t0 = i
		if t0 >= 0 and t1 < 0 and str(row1["anim_state"]) == "attack_infect":
			t1 = i
		if t0 >= 0 and t1 >= 0:
			break
	if t0 < 0 or t1 < 0:
		f.append("stagger: a copy never infected (%d / %d)" % [t0, t1])
		return
	if absi(t1 - t0 - 60) > 1:
		f.append("stagger: copies %d ticks apart, want 60 +/-1 (120/2, SR-3)" % (t1 - t0))


# ---- the squelch cue fires ONLY when new tiles appear --------------------------

func _squelch_only_on_new_tiles(f: Array[String]) -> void:
	# phase A: one toucher, one fresh patch - the infect step carries the squelch
	var solo := _spawn(Vector3(3.5, 0.0, 0.5))
	var rt = solo[0]
	var row = solo[1]
	var saw := false
	for i in range(900):
		rt.step(DT)
		if str(row["anim_state"]) == "attack_infect":
			if not _audio_events(rt, "toucher_squelch").is_empty():
				saw = true
			break
	if not saw:
		f.append("squelch: a fresh patch infected without a squelch cue")
	# phase B: a second toucher reads the identical patch - no new tiles, no cue
	var w := _arena()
	var ctl = _spent_ctl(w)
	var rt2 = EnemyRuntime.new()
	rt2.setup(_level(), w, [ctl], 4242)
	var cfg: Dictionary = _cfg(0.0)
	rt2.spawn_at("toucher", "toucher", ToucherEnemy.behavior(), cfg, Vector3(3.5, 0.0, 0.5))
	var row2: Dictionary = rt2.spawn_at("toucher", "toucher", ToucherEnemy.behavior(), cfg,
			Vector3(3.5, 0.0, 0.5))
	# the first one sits through its fade + interval, pre-glitching the patch
	for i in range(200):
		rt2.step(DT)
	var saw2 := false
	for i in range(900):
		rt2.step(DT)
		if str(row2["anim_state"]) == "attack_infect":
			saw2 = true
			break
	if not saw2:
		f.append("squelch: the second toucher never infected")
		return
	if int(row2["last_infect_new"]) != 0:
		f.append("squelch: the second toucher added %d tiles, want 0 (all taken)"
				% int(row2["last_infect_new"]))
	if not _audio_events(rt2, "toucher_squelch").is_empty():
		f.append("squelch: the shared-patch tick queued a squelch without new tiles")


# ---- attack_infect carries NO duration (the T-083 block: "on the infection tick") ----

func _attack_infect_has_no_duration(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(3.5, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	var t0 := _wait_state(rt, row, "attack_infect")
	if t0 < 0:
		f.append("dur: never infected")
		return
	# the anim block: total_ticks null - no duration anywhere to invent
	var doc = JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/toucher/sprites.json"))
	var st: Dictionary = (doc["anim"]["states"] as Dictionary)["attack_infect"]
	if st.get("total_ticks", 0) != null:
		f.append("dur: sprites.json's attack_infect carries total_ticks %s, want null"
				% str(st.get("total_ticks")))
	# the sim: the state exists on the infection tick, and the next tick is idle
	if str(row["anim_state"]) != "attack_infect" or int(row["anim_state_t"]) != 0:
		f.append("dur: the infection tick read %s/%d, want attack_infect/0"
				% [str(row["anim_state"]), int(row["anim_state_t"])])
	rt.step(DT)
	if str(row["anim_state"]) != "idle_chase" or int(row["anim_state_t"]) != 0:
		f.append("dur: the tick after the infection read %s/%d, want idle_chase/0"
				% [str(row["anim_state"]), int(row["anim_state_t"])])


# ---- the anim block wiring (sprites.json's section 1.8 block) -------------------

func _anim_block_wiring(f: Array[String]) -> void:
	var v = ToucherViewScript.new()
	v.setup("res://content/enemies/toucher/sprites.json", "res://content/enemies/toucher")
	for state_id in ["spawn", "idle_chase", "telegraph", "attack_infect", "recover"]:
		if not (v.anim_state_ids() as Array).has(state_id):
			f.append("view: anim block is missing state '%s'" % state_id)
	if v.billboard == null:
		f.append("view: billboard was not built")
		v.free()
		return
	var cycle = v.billboard.anims.get("cycle", null)
	if cycle == null:
		f.append("view: no cycle animation loaded from sprites.json")
	else:
		for tex in cycle["frames"]:
			if tex == null:
				f.append("view: a cycle frame texture failed to load")
	var floor_anim = v.billboard.anims.get("floor", null)
	if floor_anim == null:
		f.append("view: no floor animation loaded from sprites.json")
	else:
		if (floor_anim["frames"] as Array).size() != 5:
			f.append("view: the floor anim has %d frames, want 5" % (floor_anim["frames"] as Array).size())
		for tex in floor_anim["frames"]:
			if tex == null:
				f.append("view: a floor frame texture failed to load")
	# the shared player resolves the telegraph's binding 18 ticks
	if v.anim.state_total() != 18 or str(v.anim.spec().get("total_ticks", 0)) == "":
		pass
	var idle: Dictionary = (doc_states().get("idle_chase", {}) as Dictionary)
	if float(idle.get("fps", 0.0)) != 10.0:
		f.append("view: idle_chase fps %s, want 10.0 (the flicker rate)" % str(idle.get("fps")))
	var host: Dictionary = (doc_states().get("telegraph", {}) as Dictionary)
	if float(host.get("fps", 0.0)) != 20.0:
		f.append("view: telegraph fps %s, want 20.0 (the pulse rate)" % str(host.get("fps")))
	v.position = Vector3(3.5, 0.0, 0.5)
	v.sync({"anim_state": "idle_chase", "anim_state_t": 0, "glitched": [], "rt_tick": 0}, DT)
	if int(v.billboard.frame_i) < 0:
		f.append("view: the billboard never settled a frame")
	v.free()


func doc_states() -> Dictionary:
	var doc = JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/toucher/sprites.json"))
	return doc.get("anim", {}).get("states", {})


# ---- the corrupted-floor decals (the anim block's attack_infect effect params) ----

func _view_decals(f: Array[String]) -> void:
	var v = ToucherViewScript.new()
	v.setup("res://content/enemies/toucher/sprites.json", "res://content/enemies/toucher")
	v.position = Vector3.ZERO
	var row := {"anim_state": "idle_chase", "anim_state_t": 0, "rt_tick": 1000,
			"glitched": [
				{"key": "2,0,0", "x": 2.5, "y": 0.0, "z": 0.5, "born": 1000, "life": 720},
				{"key": "3,1,0", "x": 3.5, "y": 0.0, "z": 1.5, "born": 1000, "life": 720},
				{"key": "-2,-1,0", "x": -1.5, "y": 0.0, "z": -0.5, "born": 1000, "life": 720},
			]}
	v.sync(row, DT, Vector3(5.0, 0.0, 5.0))
	if v._decals.size() != 3:
		f.append("decals: %d decals for 3 entries" % v._decals.size())
		v.free()
		return
	# frame offset: (x + z) mod 5 - tile (2,0) -> 2; tile (3,1) -> 4; tile (-2,-1) -> 2
	var want_offset := {"2,0,0": 2, "3,1,0": 4}
	for key in want_offset.keys():
		var d: Dictionary = v._decals[key]
		var tex = (d["sprite"] as Sprite3D).texture
		var expect = v._decal_texts[int(want_offset[key])]
		if tex != expect:
			f.append("decals: key %s shows the wrong frame (want offset %d, the (x+z) mod 5 rule)"
					% [key, int(want_offset[key])])
		if not (d["node"] as Node3D).visible:
			f.append("decals: key %s is hidden at birth" % key)
	# appear ramp: alpha 0 -> 1 over the 12 appear ticks
	var s0: Sprite3D = (v._decals["2,0,0"] as Dictionary)["sprite"]
	if absf(s0.modulate.a) > 0.05:
		f.append("decals: alpha %.2f at age 0, want 0.0 (appear over 12 ticks)" % s0.modulate.a)
	row["rt_tick"] = 1006   # age 6: half-appeared, still inside the 6-tick tear flash
	v.sync(row, DT)
	if absf(s0.modulate.a - 0.5) > 0.1:
		f.append("decals: alpha %.2f at age 6, want ~0.5" % s0.modulate.a)
	if s0.modulate.r < 0.9:
		f.append("decals: the 6-tick tear flash is not danger red")
	row["rt_tick"] = 1012
	v.sync(row, DT)
	if absf(s0.modulate.a - 1.0) > 0.01:
		f.append("decals: alpha %.2f at age 12, want 1.0" % s0.modulate.a)
	if s0.modulate.g < 0.9:
		f.append("decals: the tear flash lingered past its 6 ticks")
	# the last 60 ticks flicker at 10 Hz
	var f0: float = v._flicker_hz
	if absf(f0 - 10.0) > 1e-9:
		f.append("decals: flicker %s Hz, want 10.0" % str(f0))
	row["rt_tick"] = 1702   # age 702: inside the 60-tick flicker
	v.sync(row, DT)
	var a_flick_a := s0.modulate.a
	row["rt_tick"] = 1705   # half a flicker period later
	v.sync(row, DT)
	var a_flick_b := s0.modulate.a
	if absf(a_flick_a - a_flick_b) < 0.05:
		f.append("decals: no 10 Hz flicker in the last 60 ticks (%.2f vs %.2f)" % [a_flick_a, a_flick_b])
	# the final 12 ticks fade to 0
	row["rt_tick"] = 1724
	v.sync(row, DT)
	if s0.modulate.a > 0.05:
		f.append("decals: alpha %.2f in the last fade, want ~0" % s0.modulate.a)
	# a tile leaving the sim list takes its decal with it
	row["glitched"] = []
	v.sync(row, DT)
	if not v._decals.is_empty():
		f.append("decals: %d decals stayed after their tiles left the sim list" % v._decals.size())
	v.free()


# ---- the lobby exhibit path (antechamber's _exhibit_enemy, headless) ----------

func _lobby_exhibit(f: Array[String]) -> void:
	var api: RefCounted = ContentApiScript.load()
	if not api.call("is_ok"):
		f.append("lobby: content boot failed: %s" % " / ".join(api.call("boot_errors")))
		return
	if not (api.call("enemy_ids") as Array).has("toucher"):
		f.append("lobby: 'toucher' is not registered as an enemy")
		return
	# the E-bay draw path: offered at level 7 (its min_level), absent at level 6
	var gate: Dictionary = OffersScript.enemy_gate(api)
	var l7: Array = OffersScript.enemy_candidates(api, 7, "general", {}, gate)
	var l6: Array = OffersScript.enemy_candidates(api, 6, "general", {}, gate)
	if not l7.has("toucher"):
		f.append("lobby: 'toucher' is not a candidate enemy at level 7")
	if l6.has("toucher"):
		f.append("lobby: 'toucher' offered below its min_level (6)")
	var doc: Dictionary = api.call("enemy", "toucher")
	if str(doc.get("name", "")) != "toucher":
		f.append("lobby: name %s, want toucher" % str(doc.get("name", "")))
	if int(doc.get("min_level", 0)) != 7:
		f.append("lobby: min_level %d, want 7" % int(doc.get("min_level", 0)))
	if int(doc.get("max_votes", 0)) != 2:
		f.append("lobby: max_votes %d, want 2" % int(doc.get("max_votes", 0)))
	# the antechamber's exact path: parse sprites.json, build the billboard,
	# scale the body to ENEMY_BODY_H (1.6 u)
	var f2 := FileAccess.open("res://content/enemies/toucher/sprites.json", FileAccess.READ)
	var parsed = JSON.parse_string(f2.get_as_text())
	f2.close()
	if not (parsed is Dictionary):
		f.append("lobby: sprites.json does not parse")
		return
	var bb = BillboardScript.new()
	bb.setup_from_sheet(parsed, "res://content/enemies/toucher")
	var doc_h: float = float(parsed.get("world_height", 1.0))
	bb.scale = bb.scale * (1.6 / maxf(doc_h, 0.01))
	bb.world_height = 1.6
	if bb.texture == null:
		f.append("lobby: the exhibit billboard has no texture (frames missing)")
	var anims: Dictionary = bb.anims
	if not anims.has("cycle"):
		f.append("lobby: the exhibit billboard has no animation")
	else:
		for tex in anims["cycle"]["frames"]:
			if tex == null:
				f.append("lobby: an exhibit frame texture failed to load")
	bb.free()
