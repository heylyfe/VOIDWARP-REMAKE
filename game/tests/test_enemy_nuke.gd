extends RefCounted
#
# T-034 - the nuke (ICBM -> nuke; DESIGN.md section 5.5, section 12; D-064). Every
# timing and number of the section 5.5 paragraph is asserted within +/-1 tick; the kill
# tests run with LAST LIGHT ALREADY SPENT (D-057) - otherwise the save masks the kill
# and the assertion is worthless.
#
# Asserted from DESIGN.md section 5.5 (a coherent 60 Hz reading, deterministic):
#   - the ground ring follows the locked player: tracking 150 ticks (2.5 s), the beep
#     rising 2 -> 8 Hz over them (the anim block's params; the ring's radius 5 u);
#   - the ring stops: the locked telegraph's 90 ticks (1.5 s), the fill from the rim
#     inward, full on tick 90 - the same 90 ticks the missile descends (from 30 u above
#     the ring centre to the ground - or onto a spire pad's top, D-064);
#   - the explosion: sphere radius 5 u kills, then the 5.0 s pause (300 ticks) repeats;
#   - D-064 salvo: tracking including EVERY restart after a broken lock plus the descent
#     lasts at most 6.0 s (360 ticks) from the first tracking tick; expiry is harmless
#     and the 5.0 s pause starts; the restart after a broken lock NEVER resets it;
#   - D-064 blocking: the LOS ray (traced from a point 12 u above and 20 u away, the
#     direction fixed per salvo) blocked 0.5 s continuously (30 ticks) during tracking
#     breaks the lock, tracking restarts after 2.0 s (120 ticks); rays and descending
#     missiles are blocked by any prop, any spire pad and any tile slab/step riser; a
#     missile over a spire pad detonates ON the pad.
#
# Parked with the header (PARKED.md): the blast kills the NEAREST player inside the
# sphere (the kill API is per-player; the section 12 surface exposes no enumeration),
# and the sim never expires telegraph footprints (the ring's footprint stays live after
# it resolved) - both are the runtime's to fix, never this test's.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Util := preload("res://tests/sim_testutil.gd")
const NukeBehavior := preload("res://content/enemies/nuke/enemy.gd")
const CollisionScript := preload("res://sim/collision.gd")

const DT := 1.0 / 60.0

# the unified table's numbers (DESIGN.md section 5.5), the cfg keys of enemy.json
const TRACK_TICKS := 150          # 2.5 s
const LOCK_TICKS := 90            # 1.5 s
const DESCENT_TICKS := 90         # 1.5 s (the same 90 as the locked ring)
const EXPLOSION_TICKS := 24
const PAUSE_TICKS := 300          # 5.0 s
const LOS_BREAK_TICKS := 30       # 0.5 s continuous
const RELOCK_TICKS := 120         # 2.0 s
const SALVO_LIFE_TICKS := 360     # 6.0 s, D-064
const RING_RADIUS := 5.0
const BLAST_RADIUS := 5.0


## The behaviour's cfg: the REAL deliverable file's stats block (content/enemies/nuke/
## enemy.json), flatted one level - every timing and number asserted below is read from
## the same file the sim would consume, not from a test-local copy of it.
func _cfg() -> Dictionary:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			"res://content/enemies/nuke/enemy.json"))
	if not (doc is Dictionary) or not ((doc as Dictionary).has("stats")):
		return {}
	var st: Dictionary = (doc as Dictionary)["stats"]
	var cfg: Dictionary = {}
	for k in st.keys():
		cfg[k] = st[k]
	return cfg


func run() -> Array[String]:
	var f: Array[String] = []
	_salvo_timeline(f)
	_relock_never_resets_budget(f)
	_expires_harmlessly(f)
	_missile_on_spire_pad(f)
	_bodyless_launcher(f)
	_counter_play_named(f)
	_anim_block_wiring(f)
	return f


## [rt, ctl]; the controller sits parked on (0.5, 0, 0.5), last light ALREADY SPENT
## (D-057: the save would otherwise mask the kill and the assertion is worthless).
func _world(tiles: Array, props: Array = []) -> Array:
	var tl: Array = []
	for t in tiles:
		tl.append([int(t[0]), int(t[1]), int(t[2]), 0, 0])
	var w := Util.CollisionScript.make_world(tl, props, [])
	var ctl := Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.x = 0.5
	ctl.y = 0.0
	ctl.z = 0.5
	ctl.grounded = true
	ctl.last_light_spent = true   # D-057
	var lv := {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": tl, "props": props, "pads": []}
	var rt := EnemyRuntime.new()
	rt.setup(lv, w, [ctl], 7)
	return [rt, ctl]


func _steps(rt, n: int) -> Array:
	# every event tagged with the step's own tick (the death events carry none of
	# their own; the telegraph's rows stamp themselves)
	var out: Array = []
	for i in range(n):
		var at := int(rt.tick)
		for e in rt.step(DT):
			e["tick_rt"] = at
			out.append(e)
	return out


func _of(events: Array, kind: String) -> Array:
	var out: Array = []
	for e in events:
		if e.get("e", "") == kind:
			out.append(e)
	return out


# A flat walkable strip: the tiles x 0..99 at z 0 (the section 5.5 wide-platform park);
# the props empty: the D-025 terrain has almost nothing overhead (the parked P2).
func _flat() -> Array:
	var tiles: Array = []
	for x in range(0, 100):
		tiles.append([x, 0, 0])
	return tiles


## The break wall, for the broken-lock tests: the tower slabs the LOS ray walks through
## at 5.5..8.5 u (the ray descends from 12 u onto the ring; at that height it crosses
## the cells between the -20 u sky point and the ring; SLAB = 1.0 u).
func _break_wall(tiles: Array) -> void:
	for cx in range(-15, -8):
		tiles.append([cx, 0, 0])
		tiles.append([cx, 0, 13])
		tiles.append([cx, 0, 15])
		tiles.append([cx, 0, 17])


## D-064: a broken lock restarts tracking after 120 ticks, and the salvo's budget NEVER
## resets - tracking including every restart plus the descent lasts at most 360 ticks
## from the FIRST tracking tick. The break wall keeps breaking the lock; the budget runs
## out and the salvo dies harmlessly: no blast, nobody dies, the 5.0 s pause starts.
func _relock_never_resets_budget(f: Array[String]) -> void:
	var tiles := _flat()
	_break_wall(tiles)
	var pair := _world(tiles)
	var rt = pair[0]
	var ctl = pair[1]
	rt.spawn_at("nuke", "nuke", NukeBehavior.new(), _cfg(), Vector3(60.5, 0.0, 2.5))
	var events := _steps(rt, 1000)
	var row: Dictionary = rt.enemies[0]
	# the blast NEVER lands: every lock breaks before the 360 ticks end
	var deaths := _of(events, "death")
	if not deaths.is_empty():
		f.append("nuke/relock: a blast landed despite the broken locks (%s)" % str(deaths[0]))
	# the lock broke and tracking restarted: at least two tracking announcements inside
	# the salvo's own budget, the restart gap the 0.5 s break + the 2.0 s relock
	var rings: Array = []
	for item in rt.telegraphs:
		if str(item.get("kind", "")) == "ground_ring" \
				and not bool(item["shape"].get("solid", false)) and int(item["tick"]) < 360:
			rings.append(int(item["tick"]))
	if rings.size() < 2:
		f.append("nuke/relock: %d tracking announcements inside the budget, want >= 2"
				% str(rings.size()))
		return
	if absi((rings[1] - rings[0]) - (LOS_BREAK_TICKS + RELOCK_TICKS)) > 1:
		f.append("nuke/relock: the tracking restarted %d ticks after the first, want %d"
				% [(rings[1] - rings[0]), LOS_BREAK_TICKS + RELOCK_TICKS])
	# a restart never resets the budget: the third tracking window cannot finish either
	if rings.size() >= 3 and absi((rings[2] - rings[1]) - (LOS_BREAK_TICKS + RELOCK_TICKS)) > 1:
		f.append("nuke/relock: the second restart took %d ticks, want %d"
				% [(rings[2] - rings[1]), LOS_BREAK_TICKS + RELOCK_TICKS])


## D-064, the salvo's own tail: the clock expiry lands exactly ON the 360th tick from the
## first tracking tick (the tests run with LAST LIGHT ALREADY SPENT, D-057); the 5.0 s
## pause starts from it; the anim row carries recover (nothing on screen - no
## attack_explosion draws for an expiry that killed nobody).
func _expires_harmlessly(f: Array[String]) -> void:
	var tiles := _flat()
	_break_wall(tiles)
	var pair := _world(tiles)
	var rt = pair[0]
	rt.spawn_at("nuke", "nuke", NukeBehavior.new(), _cfg(), Vector3(60.5, 0.0, 2.5))
	var row: Dictionary = rt.enemies[0]
	var first_pause := -1
	var anim_at_pause := ""
	var clock_ticks_at_pause := -1
	var clock_expired_at_pause := false
	var retrack := -1
	var clock_ticks_at_retrack := -1
	for i in range(700):
		rt.step(DT)
		if first_pause < 0 and str(row["phase"]) == "pause":
			first_pause = i
			anim_at_pause = str(row["anim_state"])
			clock_ticks_at_pause = int(row["salvo"].ticks)
			clock_expired_at_pause = bool(row["salvo"].expired)
		elif first_pause >= 0 and retrack < 0 and str(row["phase"]) == "track":
			retrack = i
			clock_ticks_at_retrack = int(row["salvo"].ticks)
	# the clock snapshot is taken at the FIRST pause (700 steps span the 360-tick
	# expiry, the 300-tick pause and the start of the FRESH second salvo - whose
	# own clock legitimately restarts, D-064 "then a fresh salvo"; also asserted)
	if not clock_expired_at_pause or clock_ticks_at_pause != SALVO_LIFE_TICKS:
		f.append("nuke/expire: the salvo clock at %s (expired %s), want 360/true"
				% [str(clock_ticks_at_pause), str(clock_expired_at_pause)])
	if str(row.get("paused_by", "")) != "expired":
		f.append("nuke/expire: the salvo ended by '%s', want the harmless 'expired'"
				% str(row.get("paused_by", "")))
	if absi(first_pause - (SALVO_LIFE_TICKS - 1)) > 1:
		f.append("nuke/expire: the pause started on tick %d, want ~%d"
				% [first_pause, SALVO_LIFE_TICKS - 1])
	if anim_at_pause != "recover":
		f.append("nuke/expire: the anim state '%s' at the expiry, want recover"
				% anim_at_pause)
	# the fresh salvo: after the 300-tick pause the launcher re-tracks, tracking
	# again with its OWN clock started near 0 (the budget from its own first tick)
	if retrack < 0 or absi(retrack - (first_pause + PAUSE_TICKS)) > 1:
		f.append("nuke/expire: the fresh salvo re-tracked on %s, want ~%d"
				% [str(retrack), first_pause + PAUSE_TICKS])
	elif int(clock_ticks_at_retrack) > 1:
		f.append("nuke/expire: the fresh salvo's clock at %s on its first track, want 0/1"
				% str(clock_ticks_at_retrack))


## D-064 blocking: the DESCENDING missile is blocked by any spire pad (a pad = tiles); a
## missile that meets one detonates THERE - on the pad's top, never at the ground below.
## A tall pad column (its top plate at 4.0 u, the slabs 3..4) stands where the ring is;
## the player stands on top of it - the locked ring's centre already sits on the pad.
func _missile_on_spire_pad(f: Array[String]) -> void:
	var tiles := _flat()
	tiles.append([20, 0, 8])   # the spire pad's column: the top at 4.0 u (slab 3..4)
	var pair := _world(tiles)
	var rt = pair[0]
	var ctl = pair[1]
	# the player ON the pad's top (the ring's centre = the locked player's feet = 4.0)
	ctl.x = 20.5
	ctl.y = 4.0
	ctl.z = 0.5
	rt.spawn_at("nuke", "nuke", NukeBehavior.new(), _cfg(), Vector3(60.5, 0.0, 2.5))
	var events := _steps(rt, 400)
	var row: Dictionary = rt.enemies[0]
	var det: Dictionary = row.get("det", {})
	# the detonation height: ON the pad (4.0 u), never below it
	if det.is_empty() or absf(float(det.get("y", -100.0)) - 4.0) > 0.34:
		f.append("nuke/pad: the detonation at %s, want on the pad's top (4.0 u)"
				% str(det.get("y", "<none>")))
	# the blast: the sphere, radius 5 u, kills the player standing on the pad
	var deaths := _of(events, "death")
	if deaths.is_empty():
		f.append("nuke/pad: the player on the pad survived the blast")
		return
	var d0: Dictionary = deaths[0]
	if str(d0.get("code", "")) != "D-NUKE":
		f.append("nuke/pad: the death code %s, want D-NUKE" % str(d0.get("code", "")))


## SR-2: a launcher, NO body on the map - the launcher's row never kills by body
## contact, whatever it overlaps; the only kill it owns is the 5 u blast sphere.
func _bodyless_launcher(f: Array[String]) -> void:
	var pair := _world(_flat())
	var rt = pair[0]
	var ctl = pair[1]
	# the launcher parked ON the player's own tile: "a launcher, no body on the map"
	rt.spawn_at("nuke", "nuke", NukeBehavior.new(), _cfg(), Vector3(0.5, 0.0, 0.5))
	var row: Dictionary = rt.enemies[0]
	if float(row["diameter_u"]) > 0.0 or float(row["height_u"]) > 0.0:
		f.append("nuke/body: the launcher's body %s x %s, want 0.0 x 0.0 (no body)"
				% [str(row["diameter_u"]), str(row["height_u"])])
	if bool(row["contact_kill"]):
		f.append("nuke/body: the launcher's contact_kill, want false")
	var events := _steps(rt, 205)
	if not _of(events, "death").is_empty():
		f.append("nuke/body: a kill before the blast could ever land - body contact?")
	# past tick 239: the blast (the sphere, the player 0 u from the detonation) kills
	_steps(rt, 60)
	if not bool(ctl.dead) or str(ctl.dead_code) != "D-NUKE":
		f.append("nuke/body: the blast did not kill (dead %s, code %s), want D-NUKE"
				% [str(bool(ctl.dead)), str(ctl.dead_code)])


## The counter-play line carries BOTH readings (the parked P2); the tell line + the
## roster numbers live in the data (the enemy.json stats; the counter_play SIM data).
func _counter_play_named(f: Array[String]) -> void:
	var st: Dictionary = _cfg()
	var cp := str(st.get("counter_play", ""))
	if not cp.contains("leave the 5 u sphere"):
		f.append("nuke/counter-play: 'leave the sphere' reading missing")
	if not cp.contains("between you and the sky"):
		f.append("nuke/counter-play: the sky-covering reading missing")
	if not cp.contains("break line of sight"):
		f.append("nuke/counter-play: the ENEMIES.md wording missing")
	if not str(st.get("tell_line", "")).contains("lock-on beep"):
		f.append("nuke/tell: the lock-on beep not in the tell line")
	if str(st.get("death_code", "")) != "D-NUKE":
		f.append("nuke/death_code: %s, want D-NUKE" % str(st.get("death_code")))


## The anim block wiring: every anim state the behaviour carries exists in the frozen
## sprites.json (T-083, section 1.5); the three placeholder audio hooks are named per
## the ENEMIES.md 'New sound' line.
func _anim_block_wiring(f: Array[String]) -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			"res://content/enemies/nuke/sprites.json"))
	if not (doc is Dictionary) or not ((doc as Dictionary).has("anim")):
		f.append("nuke/anim: the sprites.json anim block missing")
		return
	var states: Dictionary = ((doc as Dictionary)["anim"] as Dictionary)["states"]
	for phase in [["track", "telegraph_tracking"], ["lock", "attack_descent"],
			["recover", "recover"], ["pause", "attack_explosion"]]:
		if not states.has(str(phase[1])):
			f.append("nuke/anim: the phase %s names state '%s', not in the anim block"
					% [str(phase[0]), str(phase[1])])
	var hooks := {
		"telegraph_tracking": "lock_on_beep",
		"attack_descent": "rocket_booster_roar",
		"attack_explosion": "impact_boom",
	}
	for k in hooks.keys():
		var params: Dictionary = states[k]["effect"]["params"]
		if str(params.get("audio", "")) != str(hooks[k]):
			f.append("nuke/audio: state '%s' hook '%s', want '%s'"
					% [str(k), str(params.get("audio", "")), str(hooks[k])])


## An unbroken salvo through the real runtime: the ring announced at the spawn (tick 0),
## the locked ring + the blast + the next lock on the loop's own steps; the player 60 u
## away (never within 25 u of the launcher - the spawn rule's floor).
func _salvo_timeline(f: Array[String]) -> void:
	var pair := _world(_flat())
	var rt = pair[0]
	var ctl = pair[1]
	rt.spawn_at("nuke", "nuke", NukeBehavior.new(), _cfg(), Vector3(60.5, 0.0, 2.5))
	var events := _steps(rt, 700)
	var teles := _of(events, "telegraph")
	# the ground ring: announced in the spawn's own step, BEFORE the loop - read it from
	# the sim's telegraph list (the rows keep their announcement tick; the sim never
	# expires telegraph footprints - the drift is the runtime's, see the response file)
	var rows: Array = rt.telegraphs
	if rows.is_empty() or str(rows[0].get("kind", "")) != "ground_ring":
		f.append("nuke: the ground ring never announced (rows %s)" % str(rows.size()))
		return
	var first: Dictionary = rows[0]
	if absi(int(first["tick"])) > 1:
		f.append("nuke: the first lock rang on tick %s, want 0" % str(first["tick"]))
	if absf(float(first["ticks"]) - TRACK_TICKS) > 1.0:
		f.append("nuke: the tracking lock held %s ticks, want %d (2.5 s)"
				% [str(first["ticks"]), TRACK_TICKS])
	var r := float(first["shape"].get("r", 0.0))
	if absf(r - RING_RADIUS) > 1e-6:
		f.append("nuke: the ground ring's radius %s, want 5.0" % str(r))
	# the locked ring: 90 ticks (1.5 s), the shape's own fill (solid, full on tick 90)
	var locked: Variant = null
	for item in rows:
		if str(item.get("kind", "")) == "ground_ring" \
				and bool(item["shape"].get("solid", false)):
			locked = item
			break
	if locked == null or absi(int(locked["tick"]) - TRACK_TICKS) > 1:
		f.append("nuke: the locked ring %s, want tick %d (the tracking 2.5 s)"
				% [str(locked), TRACK_TICKS])
		return
	if absi(int(locked["ticks"]) - LOCK_TICKS) > 1:
		f.append("nuke: the locked ring held %s ticks, want %d (1.5 s)"
				% [str(locked["ticks"]), LOCK_TICKS])
	# the blast: the sphere kills on tick 240 (150 tracking + 90 locked), never without
	var deaths := _of(events, "death")
	if deaths.is_empty():
		f.append("nuke: the player survived the blast (no death event), want D-NUKE")
		return
	var d0: Dictionary = deaths[0]
	if absi(int(d0.get("tick_rt", -1)) - (TRACK_TICKS + LOCK_TICKS)) > 1:
		f.append("nuke: the blast landed on tick %s, want %d (150 + 90)"
				% [str(d0.get("tick_rt", -1)), TRACK_TICKS + LOCK_TICKS])
	if str(d0.get("code", "")) != "D-NUKE" or str(d0.get("killer", "")) != "nuke":
		f.append("nuke: the death event %s, want code D-NUKE killer nuke" % str(d0))
		return
	if not bool(ctl.dead) or str(ctl.dead_code) != "D-NUKE":
		f.append("nuke: the controller %s dead (%s), want D-NUKE"
				% [str(bool(ctl.dead)), str(ctl.dead_code)])
	# the loop repeats after the 5.0 s pause: the next lock on tick 539-540 (240 + 300)
	var next_lock: int = -1
	for e in teles:
		if int(e["tick"]) > 250:
			next_lock = int(e["tick"])
			break
	if next_lock < 0 or absi(next_lock - (TRACK_TICKS + LOCK_TICKS + PAUSE_TICKS)) > 1:
		f.append("nuke: the next lock rang on %s, want %d (the 5.0 s pause then repeat)"
				% [str(next_lock), TRACK_TICKS + LOCK_TICKS + PAUSE_TICKS])
